#!/bin/bash

signedinttypes="char short int long"
unsignedinttypes="uchar ushort uint ulong"
inttypes="$signedinttypes $unsignedinttypes"
floattypes="half float double"
alltypes="$inttypes $floattypes"
nonconstantaddresses="private global local"
addresses="$nonconstantaddresses constant"
sizes="1 2 3 4 8 16"
roundingmodes="rte rtz rtn rtp"

# generated_output_type can be one of; header, cxx, cl
generated_output_type=

function check_bin {
  which $* &> /dev/null
}

function header()
{
  echo "// Copyright (C) Codeplay Software Limited"
  echo "//"
  echo "// Licensed under the Apache License, Version 2.0 (the \"License\") with LLVM"
  echo "// Exceptions; you may not use this file except in compliance with the License."
  echo "// You may obtain a copy of the License at"
  echo "//"
  echo "//     https://github.com/codeplaysoftware/oneapi-construction-kit/blob/main/LICENSE.txt"
  echo "//"
  echo "// Unless required by applicable law or agreed to in writing, software"
  echo "// distributed under the License is distributed on an \"AS IS\" BASIS, WITHOUT"
  echo "// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the"
  echo "// License for the specific language governing permissions and limitations"
  echo "// under the License."
  echo "//"
  echo "// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception"
  echo "//"
  echo "// WARNING: This file is generated by a script, do not edit it directly. Instead"
  echo "// changes should be made to the generate_header_30.sh script in builtins/scripts."
  echo ""
  if [[ "cl" == "$generated_output_type" ]]
  then
    echo "#ifndef OCL_CLBUILTINS_30_H_INCLUDED"
    echo "#define OCL_CLBUILTINS_30_H_INCLUDED"
    echo ""
    echo "#include \"builtins.h\""
    echo "#define ABACUS_ENABLE_OPENCL_3_0_BUILTINS"
    echo "#include <abacus/abacus_integer.h>"
    echo "#undef ABACUS_ENABLE_OPENCL_3_0_BUILTINS"
    echo ""
  fi
}

function footer()
{
  if [[ "cl" == "$generated_output_type" ]]
  then
    echo "#endif  // OCL_CLBUILTINS_30_H_INCLUDED"
  fi
  echo ""
}

function sand_line()
{
  echo ""
  echo "/*-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-*/"
  echo ""
}

function half_support_begin()
{
  if [[ "$1" == "half"* ]]
  then
    echo "#ifdef __CA_BUILTINS_HALF_SUPPORT"
  fi
}

function half_support_end()
{
  if [[ "$1" == "half"* ]]
  then
    echo "#endif  // __CA_BUILTINS_HALF_SUPPORT"
  fi
}

function double_support_begin()
{
  if [[ "$1" == "double"* ]]
  then
    echo "#ifdef __CA_BUILTINS_DOUBLE_SUPPORT"
  fi
}

function double_support_end()
{
  if [[ "$1" == "double"* ]]
  then
    echo "#endif // __CA_BUILTINS_DOUBLE_SUPPORT"
  fi
}

function force_cxx_unsafe_begin()
{
  echo "#ifndef __cplusplus"
}

function force_cxx_unsafe_end()
{
  echo "#endif//__cplusplus"
}

function cxx_unsafe_begin()
{
  [[ "cxx" != "$generated_output_type" ]] && force_cxx_unsafe_begin
}

function cxx_unsafe_end()
{
  [[ "cxx" != "$generated_output_type" ]] && force_cxx_unsafe_end
}

function all_ctz()
{
  echo "#if __OPENCL_C_VERSION__ >= 200"
  echo "size_t __CL_WORK_ITEM_ATTRIBUTES get_global_linear_id(void);"
  echo "size_t __CL_WORK_ITEM_ATTRIBUTES get_local_linear_id(void);"
  echo "size_t __CL_WORK_ITEM_ATTRIBUTES get_enqueued_local_size(uint dimidx);"

  for i in $inttypes
  do
    for k in $sizes
    do
      type=$i
      if [[ "1" != "$k" ]]
      then
        type=$type$k
      fi
      echo "$type __CL_CONST_ATTRIBUTES ctz($type x);"
    done
  done

  echo "#endif"
}

function all_typedefs()
{
  if [[ "header" == "$generated_output_type" ]]
  then
    echo "#ifdef __OPENCL_VERSION__"
    echo "#undef __OPENCL_VERSION__"
    echo "#endif"
    echo "#define __OPENCL_VERSION__ 300"
  fi
}

function all_vload()
{
  cxx_unsafe_begin
  for i in $alltypes
  do
    half_support_begin $i
    double_support_begin $i
    for m in 2 3 4 8 16
    do
      local body=";"
      if [[ "cl" == "$generated_output_type" ]]
      then
          if [[ "3" == "$m" ]]
          then
            body="{ const $i * pO = pointer + (offset * $m); $i$m data; data.x = pO[0]; data.y = pO[1]; data.z = pO[2]; return data; }"
          else
            body="{ typedef $i$m unaligned_type __attribute__((aligned(sizeof($i)))); return *(unaligned_type * )(pointer + (offset * $m)); }"
          fi
      fi

      if [[ "cxx" != "$generated_output_type" ]]
      then
        echo "$i$m __CL_BUILTIN_ATTRIBUTES vload$m(size_t offset, const $i * pointer) $body"
      fi
    done
    half_support_end $i
    double_support_end $i
  done
  cxx_unsafe_end
}

function all_vstore()
{
  cxx_unsafe_begin
  for i in $alltypes
  do
    half_support_begin $i
    double_support_begin $i
    for m in 2 3 4 8 16
    do
      local body=";"
      if [[ "cl" == "$generated_output_type" ]]
      then
          if [[ "3" == "$m" ]]
          then
            body="{ $i * pO = pointer + (offset * $m); pO[0] = payload.x; pO[1] = payload.y; pO[2] = payload.z; }"
          else
            body="{ typedef $i$m unaligned_type __attribute__((aligned(sizeof($i)))); *(unaligned_type * )(pointer + (offset * $m)) = payload; }"
          fi
      fi

      if [[ "cxx" != "$generated_output_type" ]]
      then
        echo "void __CL_BUILTIN_ATTRIBUTES vstore$m($i$m payload, size_t offset, $i * pointer) $body"
      fi
    done
    double_support_end $i
    half_support_end $i
  done
  cxx_unsafe_end
}

function all_vload_half()
{
  for suffix in "" a
  do
    for k in "" 2 3 4 8 16
    do
      # vload_halfn functions only require 2-byte
      # alignment, vloada_halfn require sizeof(halfn)
      # alignment, except for vloada_half3 which
      # requires sizeof(half4) alignment.  We use
      # ushort[n] in place of half[n] as it has the
      # same size.
      local align=ushort
      [[ "a" == "$suffix" ]] && align=ushort$k
      [[ "a" == "$suffix" ]] && [[ "3" == "$k" ]] && align=ushort4

      # Most address calculations are based on
      # multiplying the offset by $k words, except
      # for vloada_half3 which as a special case uses
      # 4-words (despite operating on half3 values).
      local n=$k
      [[ "" == "$k" ]] && n=1
      [[ "a" == "$suffix" ]] && [[ "3" == "$k" ]] && n=4

      local body=";"
      if [[ "cl" == "$generated_output_type" ]]
      then
        body="{\n"
        body+="#ifdef __CA_BUILTINS_HALF_SUPPORT\n"
        body+="typedef half${k} unaligned_type __attribute__((aligned(sizeof(${align}))));\n"
        body+="#else\n"
        body+="typedef ushort${k} unaligned_type __attribute__((aligned(sizeof(${align}))));\n"
        body+="#endif  // __CA_BUILTINS_HALF_SUPPORT\n"

        body+="const unaligned_type *p = (const unaligned_type *)(pointer + (offset * ${n}));\n"
        if [[ "3" != "$k" ]] ; then
          body+="unaligned_type t = *p;\n"
        else
          body+="unaligned_type t; t.x = p->x; t.y = p->y; t.z = p->z;\n"
        fi
        body+="#ifdef __CA_BUILTINS_HALF_SUPPORT\n"
        body+="if (__abacus_isftz() && !__abacus_isembeddedprofile()) {\n"
        body+="  return convert_half${k}_to_float${k}(as_ushort${k}(t));\n"
        body+="} else {\n"
        body+="  return convert_float${k}(t);\n"
        body+="}\n"
        body+="#else\n"
        body+="return convert_half${k}_to_float${k}(t);\n"
        body+="#endif  // __CA_BUILTINS_HALF_SUPPORT\n"
        body+="}\n"
      fi

      if [[ "cxx" != "$generated_output_type" ]]
      then
        echo -e "float${k} __CL_BUILTIN_ATTRIBUTES vload${suffix}_half${k}(size_t offset, const ${j} half * pointer) ${body}"
      fi
    done
  done
}

function one_vstore_half {
  local suffix=$1
  local typ=$2
  local size=$3
  local roundingmode=$4

  # vstore_halfn functions only require 2-byte alignment, vstorea_halfn
  # require sizeof(halfn) alignment, except for vstorea_half3 which
  # requires sizeof(half4) alignment.  We use ushort[n] in place of
  # half[n] as it has the same size.
  local align=ushort
  [[ "a" == "$suffix" ]] && align=ushort$size
  [[ "a" == "$suffix" ]] && [[ "3" == "$size" ]] && align=ushort4

  # Most address calculations are based on multiplying the offset by
  # $size words, except for vstorea_half3 which as a special case uses
  # 4-words (despite operating on half3 values).
  local n=$size
  [[ "" == "$size" ]] && n=1
  [[ "a" == "$suffix" ]] && [[ "3" == "$size" ]] && n=4

  local body=";"
  if [[ "cl" == "$generated_output_type" ]]
  then
    body="{\n"
    body+="#ifdef __CA_BUILTINS_HALF_SUPPORT\n"
    body+=" half${size} converted;\n"
    body+="if (__abacus_isftz() && !__abacus_isembeddedprofile()) {\n"
    body+="  ushort${size} soft_convert = convert_${typ}${size}_to_half${size}${roundingmode}(data);\n"
    body+="  converted = as_half${size}(soft_convert);\n"
    body+="} else {\n"
    body+="  converted = convert_half${size}${roundingmode}(data);\n"
    body+="}\n"
    body+="typedef half${size} unaligned_type __attribute__((aligned(sizeof(half))));\n"
    body+="#else\n"
    body+="  typedef ushort${size} unaligned_type __attribute__((aligned(sizeof(${align}))));\n"
    body+="  ushort${size} converted = convert_${typ}${size}_to_half${size}${roundingmode}(data);\n"
    body+="#endif  // __CA_BUILTINS_HALF_SUPPORT\n"
    body+="unaligned_type *p = (unaligned_type *)(pointer + (offset *${n}));\n"

    if [[ "3" != "$size" ]] ; then
      body+="  *p = converted;\n"
    else
      body+="  p->x = converted.x; p->y = converted.y; p->z = converted.z;\n"
    fi
    body+="}\n"
  fi

  if [[ "cxx" != "$generated_output_type" ]]
  then
    echo -e "void __CL_BUILTIN_ATTRIBUTES vstore${suffix}_half${size}${roundingmode}(${typ}${size} data, size_t offset, half * pointer) ${body}"
  fi
}

function all_vstore_half()
{
  for suffix in "" a
  do
    for i in $floattypes
    do
      if [[ "$i" == "half" ]]
      then
        continue
      fi

      double_support_begin $i
      for k in "" 2 3 4 8 16
      do
        one_vstore_half "$suffix" $i "$k" ""
        for m in $roundingmodes
        do
          one_vstore_half "$suffix" $i "$k" _$m
        done
      done
      double_support_end $i
    done
  done
}

function all_atomic()
{
  echo "#if __OPENCL_C_VERSION__ >= 300"
  echo "#define NULL 0"
  echo "typedef enum {"
  echo "  memory_order_relaxed,"
  echo "  memory_order_acquire,"
  echo "  memory_order_release,"
  echo "  memory_order_acq_rel"
  echo "} memory_order;"
  echo "typedef uint memory_scope;"
  echo "#define memory_scope_work_item 1u"
  echo "#define memory_scope_sub_group 2u"
  echo "#define memory_scope_work_group 3u"
  echo "#define memory_scope_device 4u"
  echo "#define memory_scope_all_svm_devices 5u"
  echo "#define memory_scope_all_devices 6u"
  echo ""
  echo "void __CL_BARRIER_ATTRIBUTES work_group_barrier(cl_mem_fence_flags flags);"
  echo "void __CL_BARRIER_ATTRIBUTES work_group_barrier(cl_mem_fence_flags flags, memory_scope scope);"
  echo ""
  for k in __local __global ""
  do
    for i in int uint float
    do
      echo "void __CL_BUILTIN_ATTRIBUTES atomic_init(volatile $k atomic_$i *obj, $i value);"
    done
  done
  echo "void __CL_BUILTIN_ATTRIBUTES atomic_work_item_fence(cl_mem_fence_flags flags, memory_order order, memory_scope scope);"

  for k in __local __global ""
  do
    for i in int uint float
    do
      echo "void __CL_BUILTIN_ATTRIBUTES atomic_store_explicit(volatile $k atomic_$i *object, $i desired, memory_order order, memory_scope scope);"
    done
  done

  for k in __local __global ""
  do
    for i in int uint float
    do
      echo "$i __CL_BUILTIN_ATTRIBUTES atomic_load_explicit(volatile $k atomic_$i *object, memory_order order, memory_scope scope);"
    done
  done

  for k in __local __global ""
  do
    for i in int uint float
    do
      echo "$i __CL_BUILTIN_ATTRIBUTES atomic_exchange_explicit(volatile $k atomic_$i *object, $i desired, memory_order order, memory_scope scope);"
    done
  done

  for name in atomic_compare_exchange_strong_explicit atomic_compare_exchange_weak_explicit
  do
    for k1 in __local __global ""
    do
      for i in int uint float
      do
        for k2 in __local __global __private ""
        do
          echo "bool __CL_BUILTIN_ATTRIBUTES $name(volatile $k1 atomic_$i *object, $k2 $i *expected, $i desired, memory_order success, memory_order failure);"
          echo "bool __CL_BUILTIN_ATTRIBUTES $name(volatile $k1 atomic_$i *object, $k2 $i *expected, $i desired, memory_order success, memory_order failure, memory_scope scope);"
        done
      done
    done
  done

  for t in int uint
  do
    for op in add sub or xor and min max
    do
      for addr in __local __global ""
      do
        echo "$t __CL_BUILTIN_ATTRIBUTES atomic_fetch_${op}_explicit(volatile $addr atomic_$t *object, $t operand, memory_order order, memory_scope scope);"
      done
    done
  done

  for op in test_and_set clear
  do
    for addr in __local __global ""
    do
      echo "bool __CL_BUILTIN_ATTRIBUTES atomic_flag_${op}_explicit(volatile $addr atomic_flag *object, memory_order order, memory_scope scope);"
    done
  done

  echo "#endif"
  echo ""
}

function all_sub_group()
{
  if [[ "header" == "$generated_output_type" ]]
  then
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_sub_group_size(void);"
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_max_sub_group_size(void);"
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_num_sub_groups(void);"
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_enqueued_num_sub_groups(void);"
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_sub_group_id(void);"
    echo "uint __CL_WORK_ITEM_ATTRIBUTES get_sub_group_local_id(void);"
    echo ""
    echo "int __CL_BARRIER_ATTRIBUTES sub_group_all(int predicate);"
    echo "int __CL_BARRIER_ATTRIBUTES sub_group_any(int predicate);"
    echo ""
  fi

  if [[ "header" == "$generated_output_type" ]]
  then
    for i in int uint long ulong half float double
    do
      half_support_begin $i
      double_support_begin $i

      echo "$i __CL_BARRIER_ATTRIBUTES sub_group_broadcast($i x, uint sub_group_local_id);"

      for op in reduce_add reduce_min reduce_max scan_exclusive_add scan_exclusive_min scan_exclusive_max scan_inclusive_add scan_inclusive_min scan_inclusive_max SPV_KHR_uniform_group_arithmetic reduce_mul reduce_and reduce_or reduce_xor scan_exclusive_mul scan_exclusive_and scan_exclusive_or scan_exclusive_xor scan_inclusive_mul scan_inclusive_and scan_inclusive_or scan_inclusive_xor
      do
        # A marker to output a comment
        if [[ "SPV_KHR_uniform_group_arithmetic" == "$op" ]]
        then
          echo ""
          echo "// SPV_KHR_uniform_group_arithmetic"
          echo ""
          continue
        fi
        if [[ "half" == "$i" || "float" == "$i" || "double" == "$i" ]]
        then
          if [[ "$op" == *_and || "$op" = *_or || "$op" == *_xor ]]
          then
            continue
          fi
        fi
        echo "$i __CL_BARRIER_ATTRIBUTES sub_group_$op($i x);"
      done
      double_support_end $i
      half_support_end $i
      echo ""
    done

    # Bool-type sub-group builtins
    echo ""
    echo "// SPV_KHR_uniform_group_arithmetic"
    echo ""
    for op in reduce_and reduce_or reduce_xor reduce_logical_and reduce_logical_or reduce_logical_xor scan_exclusive_and scan_exclusive_or scan_exclusive_xor scan_exclusive_logical_and scan_exclusive_logical_or scan_exclusive_logical_xor scan_inclusive_and scan_inclusive_or scan_inclusive_xor scan_inclusive_logical_and scan_inclusive_logical_or scan_inclusive_logical_xor
    do
      i="bool"
      echo "$i __CL_BARRIER_ATTRIBUTES sub_group_$op($i x);"
    done
    echo ""
  fi

  local body=";"

  if [[ "cl" == "$generated_output_type" ]]
  then
    body=" { (void)flags; }"
  fi
  echo "void __CL_BARRIER_ATTRIBUTES sub_group_barrier(cl_mem_fence_flags flags)$body"

  if [[ "cl" == "$generated_output_type" ]]
  then
    body=" { (void)flags; (void)scope; }"
  fi
  echo "void __CL_BARRIER_ATTRIBUTES sub_group_barrier(cl_mem_fence_flags flags, memory_scope scope)$body"
  echo ""
}

function all_work_group()
{
  echo "int __CL_BARRIER_ATTRIBUTES work_group_all(int x);"
  echo "int __CL_BARRIER_ATTRIBUTES work_group_any(int x);"
  echo ""

  for i in half int uint long ulong float double
  do
    half_support_begin $i
    double_support_begin $i
    echo "$i __CL_BARRIER_ATTRIBUTES work_group_broadcast($i a, size_t x);"
    echo "$i __CL_BARRIER_ATTRIBUTES work_group_broadcast($i a, size_t x, size_t y);"
    echo "$i __CL_BARRIER_ATTRIBUTES work_group_broadcast($i a, size_t x, size_t y, size_t z);"
    for op in reduce_add reduce_min reduce_max scan_exclusive_add scan_exclusive_min scan_exclusive_max scan_inclusive_add scan_inclusive_min scan_inclusive_max
    do
      echo "$i __CL_BARRIER_ATTRIBUTES work_group_$op($i x);"
    done
    double_support_end $i
    half_support_end $i
    echo ""
  done
}

function all_get_fence()
{
  local body=";"
    if [[ "cl" == "$generated_output_type" ]]
    then
      body="{ return 0; }"
    fi

  echo "cl_mem_fence_flags __CL_BUILTIN_ATTRIBUTES get_fence(bool *ptr)$body"
  echo "cl_mem_fence_flags __CL_BUILTIN_ATTRIBUTES get_fence(const bool *ptr)$body"
  for t in $alltypes
  do
    half_support_begin $t
    double_support_begin $t
    for s in "" 2 3 4 8 16
    do
      echo "cl_mem_fence_flags __CL_BUILTIN_ATTRIBUTES get_fence($t$s *ptr)$body"
      echo "cl_mem_fence_flags __CL_BUILTIN_ATTRIBUTES get_fence(const $t$s *ptr)$body"
    done
    double_support_end $t
    half_support_end $t
  done
}

function math_ptr_return()
{
  local originalType=$1
  local type=$1
  local size=$2
  local matchingSmallIntType=int

  if [[ "1" != "$size" ]]
  then
    type=$type$size
    matchingSmallIntType=$matchingSmallIntType$size
  fi

  for func in fract modf sincos
  do
    local body=";"

    if [[ "cl" == "$generated_output_type" ]]
    then
      body="{
        $type p;
        $type r = $func(x, &p);
        *y = p;
        return r;
      }"
    fi

    echo "$type __CL_BUILTIN_ATTRIBUTES $func($type x, $type * y) $body"
  done

  for func in frexp lgamma_r
  do
    local body=";"

    if [[ "cl" == "$generated_output_type" ]]
    then
      body="{
        $matchingSmallIntType p;
        $type r = $func(x, &p);
        *y = p;
        return r;
      }"
    fi

    echo "$type __CL_BUILTIN_ATTRIBUTES $func($type x, $matchingSmallIntType * y) $body"
  done

  for func in remquo
  do
    local body=";"

    if [[ "cl" == "$generated_output_type" ]]
    then
      body="{
        $matchingSmallIntType p;
        $type r = $func(x, y, &p);
        *z = p;
        return r;
      }"
    fi

    echo "$type __CL_BUILTIN_ATTRIBUTES $func($type x, $type y, $matchingSmallIntType * z) $body"
  done
}

function all_math_ptr_return()
{
  for i in $floattypes
  do
    half_support_begin $i
    double_support_begin $i
    for k in $sizes
    do
      math_ptr_return $i $k
    done
    double_support_end $i
    half_support_end $i
  done
}

function output_for_type()
{
  generated_output_type="$1"
  local outputFile="$2"
  echo -n "Generating: $1 $outputFile ... "

  header > "$outputFile"

  [[ "header" == "$generated_output_type" ]] && all_ctz >> "$outputFile"

  [[ "header" == "$generated_output_type" ]] && all_typedefs >> "$outputFile"

  # Atomic Builtins
  [[ "header" == "$generated_output_type" ]] && all_atomic >> "$outputFile"

  # Sub Group and Work Group Collective Builtins
  all_sub_group >> "$outputFile"
  [[ "header" == "$generated_output_type" ]] && all_work_group >> "$outputFile"

  [[ "header" == "$generated_output_type" ]] && sand_line >> "$outputFile"

  # Generic Address Space Builtins
  all_get_fence >> "$outputFile"

  sand_line >> "$outputFile"

  [[ "header" == "$generated_output_type" ]] && all_vload >> "$outputFile"
  [[ "header" == "$generated_output_type" ]] && all_vstore >> "$outputFile"
  all_vload_half >> "$outputFile"
  all_vstore_half >> "$outputFile"

  sand_line >> "$outputFile"

  # Math builtins
  all_math_ptr_return >> "$outputFile"

  footer >> "$outputFile"

  check_bin "$CLANG_FORMAT" && "$CLANG_FORMAT" -style=file -i "$outputFile"

  echo "done."
}

scriptDir="$(cd $(dirname $0); pwd)"

# This version of clang-format used is best if it matches the version specified
# in the root CMakeLists.txt file, so scrape that.
CLANG_FORMAT_VERSION="$(cat "$scriptDir"/../../../../CMakeLists.txt \
  | grep 'find_package(ClangTools' \
  | sed -e 's/.*ClangTools \([0-9\.]*\) COMPONENTS.*/\1/')"
CLANG_FORMAT_LONG="clang-format-${CLANG_FORMAT_VERSION}"
CLANG_FORMAT_SHORT="clang-format-${CLANG_FORMAT_VERSION%.[0-9]}"
check_bin "$CLANG_FORMAT_LONG" && CLANG_FORMAT="$CLANG_FORMAT_LONG"
check_bin "$CLANG_FORMAT_SHORT" && CLANG_FORMAT="$CLANG_FORMAT_SHORT"
# As a last resort, accept any version of clang-format, which is better than
# nothing. We generally don't let anything merge if it isn't formatted
# correctly anyway.
check_bin "clang-format" && CLANG_FORMAT="clang-format"
check_bin "$CLANG_FORMAT" \
  && echo "Using ${CLANG_FORMAT}." \
  || echo "Could not find ${CLANG_FORMAT_LONG} or ${CLANG_FORMAT_SHORT}."

output_for_type header "$scriptDir"/../include/builtins/builtins-3.0.h
output_for_type cl "$scriptDir"/../include/builtins/clbuiltins-3.0.h
