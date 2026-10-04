#!/usr/bin/env bash
set -euo pipefail
task_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
task_build="$(mktemp -d /tmp/whitelist-policy-tests.XXXXXX)"
"${CXX:-g++}" -std=c++17 -O2 -Wall -Wextra -Werror \
  "$task_dir/policy_test.cpp" -o "$task_build/policy_test"
"$task_build/policy_test"
task_root="$(cd "$task_dir/../../.." && pwd)"
task_controller="$task_root/tf/addons/sourcemod/scripting/weapons/loadout_controller.sp"
if rg -q 'WeaponsWhitelist_OnGetLoadoutItemPre|WeaponsWhitelistGetItemInLoadout|g_WeaponsWhitelistTournament' \
  "$task_root/tf/addons/sourcemod/scripting/weapons"; then
  echo "Legacy whitelist hot path is still present" >&2
  exit 1
fi
rg -q 'WhitelistPolicy_BeginInventory\(client\)' "$task_controller"
rg -q 'WhitelistPolicy_EndInventory\(client\)' "$task_controller"
rg -q 'if \(blocksCustom\)' "$task_controller"
