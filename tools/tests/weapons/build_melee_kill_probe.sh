#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
source_dir="$root/tf/addons/sourcemod/scripting"
scripting=${1:-/home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/melee_kill_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Extract production code; the probe substitutes only engine/audio operations.
sed -n '/^void TryFireMeleeKill(/,/^}/p' "$source_dir/weapons/gameplay_events.sp" > "$work/melee_under_test.inc"
sed -n '/^enum AnnouncerConfigMode/,/^}/p' "$source_dir/announcers.sp" > "$work/announcer_enum_under_test.inc"
for function in AnnouncerConfig_EnterSection AnnouncerConfig_LeaveSection AnnouncerConfig_KeyValue GetConfigCommandName AddAnnouncerSoundCommand GetAnnouncerSoundCommandList FindAnnouncerSoundCommandList FindAnnouncerSoundCommandListInMap ClearSoundMap PlayAnnouncerKillSound Weapons_OnMeleeKill; do
    sed -n "/^\(public \|static \)\?\(SMCResult\|void\|ArrayList\|bool\) $function(/,/^}/p" "$source_dir/announcers.sp" | sed 's/^static //'
done > "$work/announcer_under_test.inc"
test -s "$work/melee_under_test.inc"
rg -q '^public void Weapons_OnMeleeKill' "$work/announcer_under_test.inc"
# Also protect the integration and both purchased-group discovery paths.
rg -q 'TryFireMeleeKill\(event, attacker, client, killWeapon\)' "$source_dir/weapons/gameplay/pellets_and_deaths.sp"
rg -q 'new GlobalForward\("Weapons_OnMeleeKill", ET_Ignore, Param_Cell, Param_Cell, Param_Cell\)' "$source_dir/weapons/gameplay_events.sp"
rg -q 'forward void Weapons_OnMeleeKill\(int attacker, int victim, int weapon\)' "$source_dir/include/weapons.inc"
test "$(rg -c 'AddPurchasedAnnouncerGroupsFromMap\(client, groups, g_MeleeKillSoundMap\)' "$source_dir/announcers.sp")" = 2
cp "$root/tools/tests/weapons/melee_kill_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$source_dir" -i "$scripting/include" -o "$output"
