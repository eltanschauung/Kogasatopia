#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/lottery-ticket-history-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp "$root/tf/addons/sourcemod/scripting/points_store/lotteries/history.inc" "$work/"
cp "$root/tools/tests/lottery_ticket_history_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
