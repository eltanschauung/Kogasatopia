#!/usr/bin/env bash
set -euo pipefail
task_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sm_sdk="${SM_SDK:?Set SM_SDK to the SourceMod 1.12 source checkout}"
task_output="${1:-$task_source/build}"
mkdir -p "$task_output"
task_arch="${TARGET_ARCH:-x86}"
case "$task_arch" in
  x86) task_arch_flag=-m32 ;;
  x86_64) task_arch_flag=-m64 ;;
  *) echo "TARGET_ARCH must be x86 or x86_64" >&2; exit 1 ;;
esac
task_safetyhook="$sm_sdk/public/safetyhook"
test -s "$task_safetyhook/include/safetyhook.hpp"
task_objects=()
# Build the pinned SDK's inline-hook library, serially. No new extension,
# dependency downloads, or unbounded parallel compilation.
for task_unit in allocator easy inline_hook mid_hook utility vmt_hook os.linux; do
  task_object="$task_output/safetyhook-$task_unit.o"
  "${CXX:-g++}" "$task_arch_flag" -std=c++17 -O2 -fPIC -fvisibility=hidden -w \
    -I"$task_safetyhook/include" -I"$task_safetyhook/zydis" \
    -ffile-prefix-map="$sm_sdk"=sdk \
    -c "$task_safetyhook/src/$task_unit.cpp" -o "$task_object"
  task_objects+=("$task_object")
done
"${CC:-gcc}" "$task_arch_flag" -O2 -fPIC -fvisibility=hidden -w \
  -I"$task_safetyhook/zydis" -c "$task_safetyhook/zydis/Zydis.c" -o "$task_output/zydis.o"
task_objects+=("$task_output/zydis.o")
"${CXX:-g++}" "$task_arch_flag" -std=c++17 -O2 -g -fPIC -shared -fvisibility=hidden -Wall -Wextra -Werror \
  -Wno-unused-parameter -Wno-deprecated-copy -fno-sized-deallocation -D_LINUX -DPOSIX -DSM_GENERATED_BUILD \
  -I"$task_source" -I"$sm_sdk/public" -I"$sm_sdk/public/amtl" \
  -I"$sm_sdk/public/amtl/amtl" -I"$sm_sdk/sourcepawn/include" \
  -I"$task_safetyhook/include" -I"$task_safetyhook/zydis" \
  -ffile-prefix-map="$task_source"=. \
  "$task_source/extension.cpp" "$sm_sdk/public/smsdk_ext.cpp" "${task_objects[@]}" -pthread \
  -o "$task_output/whitelist_policy.ext.2.tf2.so"
