#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
source_dir="$root/tf/addons/sourcemod/scripting"
scripting=${1:-/home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/deploy_finished_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
for function in WeaponsSound_TrackDeployFinish WeaponsSound_ClearDeployFinishState WeaponsSound_CancelDeployFinish WeaponsSound_CancelOtherDeploy WeaponsSound_DeployFinishEntityDestroyed WeaponsSound_DeployFinishHookRemoved WeaponsSound_ItemPostFramePre; do
    sed -n "/^\(public \|static \)\?\(void\|MRESReturn\) $function(/,/^}/p" "$source_dir/weapons/deploy_finished_sound.sp" | sed 's/^static //'
done > "$work/deploy_under_test.inc"
for function in WeaponsSound_PlayCustomDeploySound WeaponsSound_OnWeaponFinishedDeploy WeaponsSound_ResetClient WeaponsSound_ResetClients; do
    sed -n "/^\(static \)\?void $function(/,/^}/p" "$source_dir/weapons/sound_overrides.sp" | sed 's/^static //'
done >> "$work/deploy_under_test.inc"
rg -q '^public MRESReturn WeaponsSound_ItemPostFramePre' "$work/deploy_under_test.inc"
rg -q 'WeaponsSound_CancelDeployFinish\(GetClientOfUserId' "$source_dir/weapons/gameplay/pellets_and_deaths.sp"
rg -q 'Hook_Post, weapon, WeaponsSound_DeployPost' "$source_dir/weapons/deploy_finished_sound.sp"
rg -q 'if \(result.Value && Weapons_IsValidWeaponEntity' "$source_dir/weapons/deploy_finished_sound.sp"
cp "$root/tools/tests/weapons/deploy_finished_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
if [[ -n ${3:-} ]]; then
    for function in WeaponsSound_AddDeployFinishHook; do
        sed -n "/^static int $function(/,/^}/p" "$source_dir/weapons/deploy_finished_sound.sp" | sed 's/^static //'
    done > "$work/deploy_cleanup_under_test.inc"
    for function in WeaponsSound_ClearDeployFinishState WeaponsSound_CancelDeployFinish; do
        sed -n "/^\(static \)\?void $function(/,/^}/p" "$source_dir/weapons/deploy_finished_sound.sp" | sed 's/^static //'
    done >> "$work/deploy_cleanup_under_test.inc"
    cp "$root/tools/tests/weapons/deploy_finished_engine_probe.sp" "$work/engine_probe.sp"
    "$scripting/spcomp" "$work/engine_probe.sp" -i "$scripting/include" -o "$3"
fi
