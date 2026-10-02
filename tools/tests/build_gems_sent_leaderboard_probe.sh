#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/gems_sent_leaderboard_probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# Expose file-private helpers only in the fixture, using the production module.
sed 's/^static //' "$root/tf/addons/sourcemod/scripting/points_store/leaderboard.sp" > "$work/gems_sent_under_test.inc"
cp "$root/tools/tests/gems_sent_leaderboard_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
