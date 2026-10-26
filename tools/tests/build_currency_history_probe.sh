#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/currency-history-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
# Expose file-private queue state only in this isolated fixture.
sed 's/^static //' "$root/tf/addons/sourcemod/scripting/points_store/leaderboard_history.sp" > "$work/leaderboard_history.sp"
cp "$root/tools/tests/currency_history_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
