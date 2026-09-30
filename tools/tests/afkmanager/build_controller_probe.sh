#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
source="$root/tf/addons/sourcemod/scripting"
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/team_controller_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

sed -n '/^enum TeamBalanceState$/,/^};/p' "$source/whalescramble.sp" > "$work/controller_state.inc"
for function in TeamBalance_SetState TeamBalance_RefreshState TeamBalance_TryBegin TeamBalance_FinishOperation; do
    sed -n "/^\(void\|bool\) $function(/,/^}/p" "$source/whalebalance/runtime.sp"
done > "$work/controller_under_test.inc"
cat "$source/whalebalance/admission.sp" >> "$work/controller_under_test.inc"
for function in SpecQueue_IsPlayingTeam SpecQueue_CountPlayingHumansLocally SpecQueue_CountPlayingHumansOnTeam SpecQueue_SelectPendingJoinTeam SpecQueue_HasPendingJoin SpecQueue_ReservePendingJoin SpecQueue_ClearPendingJoin SpecQueue_ClearAllPendingJoins SpecQueue_GetPendingJoinCount SpecQueue_GetPendingJoinCountForTeam; do
    sed -n "/^\(void\|bool\|int\) $function(/,/^}/p" "$source/afkmanager/spec-when-full.sp"
done >> "$work/controller_under_test.inc"
cp "$root/tools/tests/afkmanager/controller_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$source/include" -i "$scripting/include" -o "$output"
