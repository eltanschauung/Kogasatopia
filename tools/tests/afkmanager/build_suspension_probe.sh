#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/queue-suspension-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
for function in SpecQueue_UpdateQueueSuspension SpecQueue_Cmd_StopQueue SpecQueue_SetQueueSuspended; do
    sed -n "/^\(void\|public Action\) $function(/,/^}/p" "$root/tf/addons/sourcemod/scripting/afkmanager/spec-when-full.sp"
done > "$work/suspension_under_test.inc"
cp "$root/tools/tests/afkmanager/suspension_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
