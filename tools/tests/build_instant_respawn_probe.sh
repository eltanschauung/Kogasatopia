#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/dgm-instant-respawn-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source="$root/tf/addons/sourcemod/scripting/dgm"
for function in DGM_RefreshRespawnVisualState DGM_AreRespawnTimesForcedOn; do
    sed -n "/^\(void\|bool\) $function(/,/^}/p" "$source/respawn_and_setup_state.sp"
done > "$work/instant_visual_under_test.inc"
cp "$source/respawn_timers.sp" "$work/"
sed -n '/^public Action Command_InstantRespawnToggle(/,/^}/p' "$source/commands.sp" > "$work/instant_command_under_test.inc"
"$scripting/spcomp" "$root/tools/tests/instant_respawn_probe.sp" -i "$work" -i "$scripting/include" -o "$output"
