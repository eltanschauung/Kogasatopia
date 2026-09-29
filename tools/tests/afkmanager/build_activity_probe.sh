#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
afk="$root/tf/addons/sourcemod/scripting/afkmanager.sp"
module="$root/tf/addons/sourcemod/scripting/afkmanager/spec-when-full.sp"
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/activity_queue_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Compile actual production functions against isolated simulated clients.
for type in AFKClientState AFKAction; do
    sed -n "/^enum\( struct\)\? $type {/,/^}/p" "$afk"
done > "$work/activity_queue_state.inc"
for function in SpecQueue_ResetAutoQueueActivityBaselines SpecQueue_SuppressActivityAutoQueue SpecQueue_CheckActivity SpecQueue_BlocksAFKKick SpecQueue_IsPlayingTeam; do
    sed -n "/^\(void\|bool\) $function(/,/^}/p" "$module"
done > "$work/activity_queue_under_test.inc"
for function in AFK_ResetIdle AFK_RecordActivity AFK_ResetClient AFK_AdvanceIdle AFK_ManageClients; do
    sed -n "/^void $function(/,/^}/p" "$afk"
done >> "$work/activity_queue_under_test.inc"
cp "$root/tools/tests/afkmanager/activity_queue_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$root/tf/addons/sourcemod/scripting/include" -i "$scripting/include" -o "$output"
