#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
source_dir="$root/tf/addons/sourcemod/scripting"
scripting=${1:-/home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/weapons_buildings_probe.smx}

# Compile the real policy module with simulated clients/engine operations.
"$scripting/spcomp" "$root/tools/tests/weapons/building_restrictions_probe.sp" \
    -i "$source_dir" -i "$scripting/include" -o "$output"

# The production integration must continue to use the same central policy.
rg -q 'WeaponsBuildings_BeginInventory\(client\)' "$source_dir/weapons/loadout_controller.sp"
rg -q 'WeaponsBuildings_EndInventory\(client\)' "$source_dir/weapons/loadout_controller.sp"
rg -q 'WeaponsBuildings_PrepareCustomLoadout\(client\)' "$source_dir/weapons/loadout_controller.sp"
rg -q 'WeaponsBuildings_ShouldBlockCustomItem\(client, item\)' "$source_dir/weapons/item_config.sp"
rg -q 'WeaponsBuildings_OnItemRuntimeStateReady\(client, entity\)' "$source_dir/weapons.sp"
! rg -q 'WeaponsBuildings_Reconcile\(client' "$source_dir/weapons.sp"
