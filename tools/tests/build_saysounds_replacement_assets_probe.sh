#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source="$root/tf/addons/sourcemod/scripting"
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/saysounds_replacement_assets_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Exercise the actual replacement loader, with mocked I/O plus real engine checks.
sed -n '/^static void PrecacheReplacementSounds(/,/^}/p' \
    "$source/saysounds/config.sp" | sed 's/^static void /void /' \
    > "$work/saysounds_replacement_assets_under_test.inc"
test -s "$work/saysounds_replacement_assets_under_test.inc"
cp "$root/tools/tests/saysounds_replacement_assets_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$work" -i "$scripting/include" -o "$output"
