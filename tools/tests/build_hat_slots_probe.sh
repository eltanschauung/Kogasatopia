#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/hat-slots-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source="$root/tf/addons/sourcemod/scripting/weapons/hats"
cp "$source/slots.sp" "$work/"
for function in RecalculateClientEnabledHatCount NormalizeClientHatSlots SetClientHatEnabled; do
    sed -n "/^\(void\|bool\) $function(/,/^}/p" "$source/client_state.sp"
done > "$work/hat_state_under_test.inc"
for function in ShowHatMenu ShowHatsInSlotMenu; do
    sed -n "/^void $function(/,/^}/p" "$source/menus.sp"
done > "$work/hat_menus_under_test.inc"
"$scripting/spcomp" "$root/tools/tests/hat_slots_probe.sp" -i "$work" -i "$scripting/include" -o "$output"
