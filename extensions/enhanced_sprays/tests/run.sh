#!/usr/bin/env bash
# Offline tests only: no server connection, installation or plugin reload.
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# != 3 || $1 != /* || $2 != /* || $3 != /* ]]; then
    printf '%s\n' 'Usage: run.sh ABSOLUTE_OUTPUT_DIR ABSOLUTE_NATIVE_BUILD_DIR ABSOLUTE_SOURCEMOD_SOURCE' >&2
    exit 2
fi
output_dir=$1
native_build_dir=$2
sm_source=$3
compiler=${CXX:-clang++}
mkdir -p -- "$output_dir"
for arch in x86_64 x86; do
    bits=64
    [[ $arch == x86 ]] && bits=32
    flags=(-m"$bits" -std=c++17 -O1 -Wall -Wextra -Werror -I"$source_dir/native")
    for test in spray_policy preview_geometry asset_delivery; do
        sources=("$source_dir/tests/${test}_test.cpp")
        [[ $test != asset_delivery ]] && sources+=("$source_dir/native/$test.cpp")
        "$compiler" "${flags[@]}" "${sources[@]}" -o "$output_dir/$test-$arch"
        "$output_dir/$test-$arch"
    done
    if [[ $arch == x86 ]]; then
        "$compiler" "${flags[@]}" -fPIE -pie -pthread -I"$sm_source/public/safetyhook/include" \
            "$source_dir/tests/filesystem_threads_test.cpp" "$source_dir/native/filesystem_hooks.cpp" \
            "$native_build_dir/spray_safetyhook/linux-$arch/libspray_safetyhook.a" \
            -o "$output_dir/filesystem-pic-$arch"
        fixture=$(mktemp -d "$output_dir/filesystem-pic-fixture.XXXXXXXX")
        "$output_dir/filesystem-pic-$arch" "$fixture" expect-refusal
    fi
    # A non-PIE synthetic fixture keeps 32-bit call/pop thunks out of the stolen
    # prologues. The separate PIE test above verifies unsafe targets fail closed.
    "$compiler" "${flags[@]}" -fno-pie -no-pie -pthread -I"$sm_source/public/safetyhook/include" \
        "$source_dir/tests/filesystem_threads_test.cpp" "$source_dir/native/filesystem_hooks.cpp" \
        "$native_build_dir/spray_safetyhook/linux-$arch/libspray_safetyhook.a" \
        -o "$output_dir/filesystem-threads-$arch"
    fixture=$(mktemp -d "$output_dir/filesystem-fixture-$arch.XXXXXXXX")
    "$output_dir/filesystem-threads-$arch" "$fixture"
done
printf '%s\n' 'All x86/x64 offline spray regressions passed; live server untouched.'
