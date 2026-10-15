#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp -d /tmp/weapons-ext-tests.XXXXXXXX)"
for test_name in hot_paths policy loadout_cache shared_vtable_lifetime; do
    "${CXX:-g++}" ${TEST_ARCH_FLAG:--m32} -std=c++17 -O2 -Wall -Wextra -Werror \
        -I"$test_root/src" -I"$test_root/src/whitelist" -I"$test_root/src/tf2tools" \
        "$test_root/tests/${test_name}_test.cpp" -ldl -o "$test_output/$test_name"
    "$test_output/$test_name"
done
python3 "$test_root/tests/smx_relink_test.py"
python3 "$test_root/tests/gamedata_test.py"
echo "Test binaries retained in $test_output"
