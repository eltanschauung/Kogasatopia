#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source="$root/tf/addons/sourcemod/scripting"
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/announcer_sync_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Test the production selection and fan-out functions with no live-player effects.
for function in Announcer_PlaySound Announcer_PlaySoundInContext Announcer_PlaySoundCommand Announcer_CenterText SelectSynchronizedAnnouncerCommand SelectAnnouncerSoundCommand SelectPaidAnnouncerSoundForListener ResolveAnnouncerSoundForListener; do
    sed -n "/^\(static \)\?\(bool\|void\) $function(/,/^}/p" "$source/announcers.sp" | sed 's/^static //'
done > "$work/announcer_sync_under_test.inc"
for function in GetSoundSelectionIndex GetRandomCommandInGroupForClient GetCommandOptionForClientEx GetCommandSoundData GetCommandSoundDataForClientEx; do
    sed -n "/^\(static \)\?\(bool\|int\) $function(/,/^}/p" "$source/saysounds/playback.sp" | sed 's/^static //'
done > "$work/saysounds_selection_under_test.inc"
cp "$root/tools/tests/announcer_sync_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$source/include" -i "$scripting/include" -o "$output"
