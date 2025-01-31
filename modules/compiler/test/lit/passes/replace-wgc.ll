; Copyright (C) Codeplay Software Limited
;
; Licensed under the Apache License, Version 2.0 (the "License") with LLVM
; Exceptions; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     https://github.com/codeplaysoftware/oneapi-construction-kit/blob/main/LICENSE.txt
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
; WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
; License for the specific language governing permissions and limitations
; under the License.
;
; SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

; RUN: muxc --passes replace-wgc,verify < %s \
; RUN:   | FileCheck %s --check-prefixes CHECK,CHECK-ALL
; RUN: muxc --passes "replace-wgc<scans-only>,verify" < %s \
; RUN:   | FileCheck %s --check-prefixes CHECK,CHECK-SCANS-ONLY

; Check that the replace-wgc correctly defines the work-group collective
; functions, optionally only defining the scans and leaving others intact.

target triple = "spir64-unknown-unknown"
target datalayout = "e-p:64:64:64-m:e-i64:64-f80:128-n8:16:32:64-S128"

; CHECK-ALL: @__mux_work_group_reduce_smin_i32.accumulator = internal addrspace(3) global i32 undef
; CHECK: @__mux_work_group_scan_inclusive_umax_i32.accumulator = internal addrspace(3) global i32 undef
; CHECK: @__mux_work_group_scan_exclusive_fadd_f32.accumulator = internal addrspace(3) global float undef
; CHECK-ALL: @__mux_work_group_broadcast_i32.accumulator = internal addrspace(3) global i32 undef

; If this isn't a scan we shouldn't have defined it
; CHECK-SCANS-ONLY: declare spir_func i32 @__mux_work_group_reduce_smin_i32(i32, i32)
declare spir_func i32 @__mux_work_group_reduce_smin_i32(i32 %id, i32 %x)
; CHECK-ALL: define spir_func i32 @__mux_work_group_reduce_smin_i32(i32 %id, i32 [[PARAM:%.*]])
; CHECK-ALL-LABEL: entry:
; CHECK-ALL: %[[SUBGROUP:.+]] = call i32 @__mux_sub_group_reduce_smin_i32(i32 %{{.+}})
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_ONCE:#[0-9]+]]
; CHECK-ALL: store i32 2147483647, ptr addrspace(3) @__mux_work_group_reduce_smin_i32.accumulator
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK-ALL: %[[CURRVAL:.+]] = load i32, ptr addrspace(3) @__mux_work_group_reduce_smin_i32.accumulator
; CHECK-ALL: %[[ACCUM:.*]] = call i32 @llvm.smin.i32(i32 %[[CURRVAL]], i32 %[[SUBGROUP]])
; CHECK-ALL: store i32 %[[ACCUM]], ptr addrspace(3) @__mux_work_group_reduce_smin_i32.accumulator
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK-ALL: %[[RESULT:.*]] = load i32, ptr addrspace(3) @__mux_work_group_reduce_smin_i32.accumulator
; CHECK-ALL: ret i32 %[[RESULT]]


declare spir_func i32 @__mux_work_group_scan_inclusive_umax_i32(i32 %id, i32 %x)
; CHECK: define spir_func i32 @__mux_work_group_scan_inclusive_umax_i32(i32 %id, i32 [[PARAM:%.*]])
; CHECK-LABEL: entry:
; This is just to ensure SCHEDULE_ONCE is defined on all paths...
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_ONCE]]
; CHECK-SCANS-ONLY: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_ONCE:#[0-9]+]]
; CHECK: store i32 0, ptr addrspace(3) @__mux_work_group_scan_inclusive_umax_i32.accumulator
; CHECK: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_LINEAR:#[0-9]+]]
; CHECK: %[[CURRVAL:.+]] = load i32, ptr addrspace(3) @__mux_work_group_scan_inclusive_umax_i32.accumulator
; CHECK: %[[SCAN:.+]] = call i32 @__mux_sub_group_scan_inclusive_umax_i32(i32 %x)
; CHECK: %[[RESULT:.+]] = call i32 @llvm.umax.i32(i32 %[[CURRVAL]], i32 %[[SCAN]])
; CHECK: %[[SIZE:.+]] = call i32 @__mux_get_sub_group_size()
; CHECK: %[[LAST:.+]] = sub nuw i32 %[[SIZE]], 1
; CHECK: %[[TAIL:.+]] = call i32 @__mux_sub_group_broadcast_i32(i32 %[[SCAN]], i32 %[[LAST]])
; CHECK: %[[ACCUM:.+]] = call i32 @llvm.umax.i32(i32 %[[CURRVAL]], i32 %[[TAIL]])
; CHECK: store i32 %[[ACCUM]], ptr addrspace(3) @__mux_work_group_scan_inclusive_umax_i32.accumulator
; CHECK: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK: ret i32 %[[RESULT]]


declare spir_func float @__mux_work_group_scan_exclusive_fadd_f32(i32 %id, float %x)
; CHECK: define spir_func float @__mux_work_group_scan_exclusive_fadd_f32(i32 %id, float [[PARAM:%.*]])
; CHECK-LABEL: entry:
; CHECK: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_ONCE]]
; CHECK: store float -0.000000e+00, ptr addrspace(3) @__mux_work_group_scan_exclusive_fadd_f32.accumulator
; CHECK: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272) [[SCHEDULE_LINEAR]]
; CHECK: %[[CURRVAL:.+]] = load float, ptr addrspace(3) @__mux_work_group_scan_exclusive_fadd_f32.accumulator
; CHECK: %[[SGSCAN:.+]] = call float @__mux_sub_group_scan_exclusive_fadd_f32(float %x)
; CHECK: %[[SGID:.+]] = call i32 @__mux_get_sub_group_local_id()
; CHECK: %[[CMPID:.+]] = icmp eq i32 %[[SGID]], 0
; CHECK: %[[SELECT:.+]] = select i1 %[[CMPID]], float -0.000000e+00, float %[[SGSCAN]]
; CHECK: %[[WGSCAN:.+]] = fadd float %[[CURRVAL]], %[[SELECT]]
; CHECK: %[[SIZE:.+]] = call i32 @__mux_get_sub_group_size()
; CHECK: %[[LAST:.+]] = sub nuw i32 %[[SIZE]], 1
; CHECK: %[[SCAN_TAIL:.+]] = call float @__mux_sub_group_broadcast_f32(float %[[SELECT]], i32 %[[LAST]])
; CHECK: %[[TAIL:.+]] = call float @__mux_sub_group_broadcast_f32(float %x, i32 %[[LAST]])
; CHECK: %[[TOTAL:.+]] = fadd float %[[SCAN_TAIL]], %[[TAIL]]
; CHECK: %[[ACCUM:.+]] = fadd float %[[CURRVAL]], %[[TOTAL]]
; CHECK: store float %[[ACCUM]], ptr addrspace(3) @__mux_work_group_scan_exclusive_fadd_f32.accumulator
; CHECK: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK: %[[LIDX:.+]] = call spir_func i64 @__mux_get_local_id(i32 0)
; CHECK: %[[CMPX:.+]] = icmp eq i64 %[[LIDX]], 0
; CHECK: %[[LIDY:.+]] = call spir_func i64 @__mux_get_local_id(i32 1)
; CHECK: %[[CMPY:.+]] = icmp eq i64 %[[LIDY]], 0
; CHECK: %[[CMPXY:.+]] = and i1 %[[CMPX]], %[[CMPY]]
; CHECK: %[[LIDZ:.+]] = call spir_func i64 @__mux_get_local_id(i32 2)
; CHECK: %[[CMPZ:.+]] = icmp eq i64 %[[LIDZ]], 0
; CHECK: %[[CMPXYZ:.+]] = and i1 %[[CMPXY]], %[[CMPZ]]
; CHECK: %[[RESULT:.+]] = select i1 %[[CMPXYZ]], float 0.000000e+00, float %[[WGSCAN]]
; CHECK: ret float %[[RESULT]]


; CHECK-SCANS-ONLY: declare spir_func i32 @__mux_work_group_broadcast_i32(i32, i32, i64, i64, i64)
declare spir_func i32 @__mux_work_group_broadcast_i32(i32 %barrier_id, i32 %x, i64 %idx, i64 %idy, i64 %idz)
; CHECK-ALL: define spir_func i32 @__mux_work_group_broadcast_i32(i32 %barrier_id, i32 [[PARAM:%.*]], i64 {{%.*}}, i64 {{%.*}}, i64 {{%.*}})
; CHECK-ALL-LABEL: entry:
; CHECK-ALL: call i64 @__mux_get_local_id(i32 0)

; CHECK-ALL-LABEL: broadcast:
; CHECK-ALL: store i32 [[PARAM]], ptr addrspace(3) @__mux_work_group_broadcast_i32.accumulator

; CHECK-ALL-LABEL: exit:
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK-ALL: [[RESULT:%.*]] = load i32, ptr addrspace(3) @__mux_work_group_broadcast_i32.accumulator
; CHECK-ALL: call void @__mux_work_group_barrier(i32 0, i32 2, i32 272)
; CHECK-ALL: ret i32 [[RESULT]]


declare spir_func half @__mux_work_group_scan_exclusive_fadd_f16(i32 %id, half %x)
; CHECK: define spir_func half @__mux_work_group_scan_exclusive_fadd_f16(i32 %id, half [[PARAM:%.*]])

; CHECK-DAG: attributes [[SCHEDULE_ONCE]] = { "mux-barrier-schedule"="once" }
; CHECK-DAG: attributes [[SCHEDULE_LINEAR]] = { "mux-barrier-schedule"="linear" }

!opencl.ocl.version = !{!0}
!0 = !{i32 3, i32 0}
