#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/bounty_list_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
sed '/^#include /,$d' "$root/tf/addons/sourcemod/scripting/points_store/bounties.inc" > "$work/bounty_state.inc"
sed 's/g_Database.Query(/ProbeQuery(/' "$root/tf/addons/sourcemod/scripting/points_store/bounties/listing_and_cache.inc" > "$work/bounty_list_under_test.inc"
cp "$root/tools/tests/bounty_list_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"

