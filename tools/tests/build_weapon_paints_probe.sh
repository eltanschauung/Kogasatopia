#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/weapon-paints-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source="$root/tf/addons/sourcemod/scripting/weapons"
sed -n '/^#define WEAPON_PAINT_/p' "$source/weapon_paints.sp" > "$work/paint_under_test.inc"
sed -n '/^static const char g_PaintNames/,/^};/p' "$source/hats/menus.sp" >> "$work/paint_under_test.inc"
for function in ClampPaintIndex CustomHats_GetPaintCount CustomHats_GetPaintName; do
    sed -n "/^\(int\|void\) $function(/,/^}/p" "$source/hats/menus.sp"
done >> "$work/paint_under_test.inc"
for function in SetItemPaintTintAttribute ApplyPaint; do
    sed -n "/^void $function(/,/^}/p" "$source/hats/rendering.sp"
done >> "$work/paint_under_test.inc"
for function in ParseChatColor ParseHexColor DecodePaintChoice EncodePaintChoice BuildPaintCookieChunks ReadPaintCookieChunk SetPaintAttributes CopyPaintAttribute; do
    sed -n "/^static \(bool\|void\) $function(/,/^}/p" "$source/weapon_paints.sp"
done >> "$work/paint_under_test.inc"
sed -n '/^void WeaponsPaint_CopyToWearable(/,/^}/p' "$source/weapon_paints.sp" >> "$work/paint_under_test.inc"
sed -n '/^void WeaponsModels_ApplyWeaponPaint(/,/^}/p' "$source/model_overrides.sp" >> "$work/paint_under_test.inc"
sed -i 's/^static bool /bool /; s/^static void /void /' "$work/paint_under_test.inc"
"$scripting/spcomp" "$root/tools/tests/weapon_paints_probe.sp" -i "$work" -i "$scripting/include" -o "$output"
