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
"${CXX:-g++}" "$task_arch_flag" -std=c++17 -O2 -g -fPIC -shared -fvisibility=hidden -Wall -Wextra -Werror \
  -Wno-unused-parameter -Wno-deprecated-copy -fno-sized-deallocation -D_LINUX -DPOSIX -DSM_GENERATED_BUILD \
  -I"$task_source" -I"$sm_sdk/public" -I"$sm_sdk/public/amtl" \
  -I"$sm_sdk/public/amtl/amtl" -I"$sm_sdk/sourcepawn/include" \
  -ffile-prefix-map="$task_source"=. \
  "$task_source/extension.cpp" "$sm_sdk/public/smsdk_ext.cpp" \
  -o "$task_output/whitelist_policy.ext.2.tf2.so"
