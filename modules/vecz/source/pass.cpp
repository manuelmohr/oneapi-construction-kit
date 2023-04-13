// Copyright (C) Codeplay Software Limited. All Rights Reserved.

#include "vecz/pass.h"

#include <compiler/utils/attributes.h>
#include <compiler/utils/builtin_info.h>
#include <compiler/utils/device_info.h>
#include <compiler/utils/metadata.h>
#include <compiler/utils/vectorization_factor.h>
#include <llvm/IR/DebugInfoMetadata.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/PassManager.h>
#include <llvm/Support/CommandLine.h>
#include <llvm/Support/Debug.h>

#include <cstdlib>
#include <functional>
#include <tuple>

#include "vectorization_context.h"
#include "vectorization_helpers.h"
#include "vectorization_unit.h"
#include "vectorizer.h"
#include "vecz/vecz_choices.h"
#include "vecz/vecz_target_info.h"
#include "vecz_pass_builder.h"

#define DEBUG_TYPE "vecz"

using namespace llvm;

/// @brief Provide debug logging for Vecz's PassManager
///
/// This flag is intended for testing and debugging purposes.
cl::opt<bool> DebugVeczPipeline(
    "debug-vecz-pipeline",
    cl::desc("Enable debug logging of the vecz PassManager"));

/// @brief Provide debug logging for Vecz's PassManager
///
/// This flag specifies a textual description of the optimization pass pipeline
/// to run over the kernel.
cl::opt<std::string> VeczPassPipeline(
    "vecz-passes",
    cl::desc(
        "A textual description of the pass pipeline. To have analysis passes "
        "available before a certain pass, add 'require<foo-analysis>'."));

namespace vecz {
using FnVectorizationResult =
    std::pair<Function *, compiler::utils::VectorizationFactor>;
AnalysisKey VeczPassOptionsAnalysis::Key;

PreservedAnalyses RunVeczPass::run(Module &M, ModuleAnalysisManager &MAM) {
  auto getVeczOptions = MAM.getResult<VeczPassOptionsAnalysis>(M);
  auto preserved = PreservedAnalyses::none();
  // Cache the current set of functions as the vectorizer will insert new ones,
  // which we don't want to revisit.
  SmallVector<std::pair<Function *, llvm::SmallVector<VeczPassOptions, 1>>, 4>
      FnOpts;
  for (auto &Fn : M.functions()) {
    llvm::SmallVector<VeczPassOptions, 1> Opts;
    if (!getVeczOptions(Fn, MAM, Opts)) {
      continue;
    }
    FnOpts.emplace_back(std::make_pair(&Fn, std::move(Opts)));
  }

  ModulePassManager PM;

  auto &device_info = MAM.getResult<compiler::utils::DeviceInfoAnalysis>(M);
  TargetInfo *target_info = MAM.getResult<vecz::TargetInfoAnalysis>(M);
  assert(target_info && "Missing TargetInfo");
  auto &builtin_info = MAM.getResult<compiler::utils::BuiltinInfoAnalysis>(M);

  VectorizationContext Ctx(M, *target_info, builtin_info);
  VeczPassMachinery Mach(M.getContext(), target_info->getTargetMachine(), Ctx,
                         /*verifyEach*/ false,
                         DebugVeczPipeline
                             ? compiler::utils::DebugLogging::Normal
                             : compiler::utils::DebugLogging::None);
  Mach.initializeStart();
  Mach.getMAM().registerPass([&device_info] {
    return compiler::utils::DeviceInfoAnalysis(device_info);
  });
  Mach.initializeFinish();

  // Forcibly compute the DeviceInfoAnalysis so that cached retrievals work.
  PM.addPass(
      RequireAnalysisPass<compiler::utils::DeviceInfoAnalysis, Module>());

  bool const Check = VeczPassPipeline.empty();
  if (Check) {
    if (!buildPassPipeline(PM)) {
      return PreservedAnalyses::all();
    }
  } else {
    if (auto Err = Mach.getPB().parsePassPipeline(PM, VeczPassPipeline)) {
      // NOTE this is a command line user error print, not a debug print.
      // We may want to hoist this out of Vecz once CA-4134 is resolved.
      errs() << "vecz pipeline: " << toString(std::move(Err)) << "\n";
      return PreservedAnalyses::all();
    }
  }

  // Create the vectorization units and clone the kernels
  using ResultTy =
      SmallVector<std::pair<VectorizationUnit *, VeczPassOptions *>, 2>;
  SmallDenseMap<Function *, ResultTy, 2> Results;
  for (auto &P : FnOpts) {
    Function *Fn = P.first;
    ResultTy T;
    Results.insert(std::make_pair(Fn, std::move(T)));
    for (auto &Opts : P.second) {
      auto *const VU =
          createVectorizationUnit(Ctx, Fn, Opts, Mach.getFAM(), Check);
      if (!VU) {
        LLVM_DEBUG(llvm::dbgs() << Fn->getName() << " was not vectorized\n");
        continue;
      }
      Results[Fn].emplace_back(std::make_pair(VU, &Opts));

      if (auto *const VecFn = vecz::cloneFunctionToVector(*VU)) {
        VU->setVectorizedFunction(VecFn);

        // Allows the Vectorization Unit Analysis to work on the vector kernel
        Ctx.setActiveVU(VecFn, VU);
      } else {
        LLVM_DEBUG(llvm::dbgs() << Fn->getName() << " could not be cloned\n");
      }
    }
  }

  // Vectorize everything
  PM.run(M, Mach.getMAM());

  auto AllOnModule = llvm::PreservedAnalyses::allInSet<AllAnalysesOn<Module>>();
  auto eraseFailed = [&](VectorizationUnit *VU) {
    Function *VectorizedFn = VU->vectorizedFunction();
    if (VectorizedFn) {
      // If we fail to vectorize a function, we still cloned and then
      // deleted it which affects internal addresses. The module has changed
      // and we can't cache any analyses.
      Mach.getFAM().invalidate(*VectorizedFn, llvm::PreservedAnalyses::all());
      // Remove the partially-vectorized function if something went wrong.
      Ctx.clearActiveVU(VectorizedFn);
      VU->setVectorizedFunction(nullptr);
      VectorizedFn->eraseFromParent();
    }
    MAM.invalidate(M, AllOnModule);
  };

  // Fix up the metadata and clean out any dead kernels
  for (auto &P : Results) {
    Function *Fn = P.first;
    auto &Result = P.second;
    bool const IsKernel = compiler::utils::isKernel(*Fn);
    bool DropScalarMDs = IsKernel && !Result.empty();
    for (auto &R : Result) {
      VectorizationUnit *VU = R.first;
      trackVeczSuccessFailure(*VU);
      if (!createVectorizedFunctionMetadata(*VU)) {
        // We only drop the metadata from the scalar kernel when the number of
        // Results is non-zero and they all succeeded
        DropScalarMDs = false;
        LLVM_DEBUG(dbgs() << Fn->getName() << " failed to vectorize\n");
        eraseFailed(VU);
      }
    }
    if (DropScalarMDs) {
      compiler::utils::dropIsKernel(*Fn);
    }
  }
  return PreservedAnalyses::none();
}

PreservedAnalyses VeczPassOptionsPrinterPass::run(Module &M,
                                                  ModuleAnalysisManager &MAM) {
  auto getVeczOptions = MAM.getResult<VeczPassOptionsAnalysis>(M);
  for (auto &F : M.functions()) {
    OS << "Function '" << F.getName() << "'";
    llvm::SmallVector<VeczPassOptions, 1> Opts;
    if (!getVeczOptions(F, MAM, Opts)) {
      OS << " will not be vectorized\n";
      continue;
    }

    OS << " will be vectorized {\n";
    for (auto &O : Opts) {
      OS << "  VF = ";
      if (O.factor.isScalable()) {
        OS << "vscale x ";
      }
      OS << O.factor.getKnownMin();

      if (O.vecz_auto) {
        OS << ", (auto)";
      }

      OS << ", vec-dim = " << O.vec_dim_idx;

      if (O.local_size) {
        OS << ", local-size = " << O.local_size;
      }

      OS << ", choices = [";
      OS.tell();
      auto AvailChoices = VectorizationChoices::queryAvailableChoices();
      unsigned NumChoices = 0;

      for (auto &C : AvailChoices) {
        if (!O.choices.isEnabled(C.number)) {
          continue;
        }
        if (!NumChoices) {
          OS << "\n    ";
        } else {
          OS << ",";
        }
        OS << C.name;
        NumChoices++;
      }
      // Pretty-print the list of choices on one line if empty, else formatted
      // across several lines. Always end with a newline, meaning the options
      // are closed off with a '}' on the first column.
      if (NumChoices) {
        OS << "\n  ]\n";
      } else {
        OS << "]\n";
      }
    }
    OS << "}\n";
  }

  return PreservedAnalyses::all();
}

}  // namespace vecz
