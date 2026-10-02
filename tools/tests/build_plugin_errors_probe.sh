#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source="$root/tf/addons/sourcemod/scripting"
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/plugin_errors_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Extract production implementations; the probe only substitutes engine/player state.
tr -d '\r' < "$source/rtd/classes/containers.sp" | sed -n '/^\s*public Perk GetFromId(int iId)/,/^\s*}$/p' > "$work/perk_lookup_under_test.inc"
cp "$source/rtd/classes/rollers.sp" "$work/rollers_under_test.inc"
for function in Timer_PerkRunTick RemovePerk; do
    sed -n "/^\(public Action\|Perk\) $function(/,/^}/p" "$source/rtd.sp"
done > "$work/plugin_errors_under_test.inc"
for function in IsValidAnnouncerClient IsHumanAnnouncerClient Announcer_MessageClient; do
    sed -n "/^\(bool\|void\) $function(/,/^}/p" "$source/announcers.sp"
done >> "$work/plugin_errors_under_test.inc"
sed -n '/^void WeaponsSound_PlayCustomMeleeHit(/,/^}/p' "$source/weapons/sound_overrides.sp" >> "$work/plugin_errors_under_test.inc"
sed "/PRODUCTION_PERK_LOOKUP/r $work/perk_lookup_under_test.inc" "$root/tools/tests/plugin_errors_probe.sp" > "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
