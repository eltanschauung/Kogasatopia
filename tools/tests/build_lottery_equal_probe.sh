#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/lottery-equal-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source="$root/tf/addons/sourcemod/scripting/points_store/lotteries"
for function in SQL_OnEqualLotteryInvalidTicketsLoaded SQLTxn_OnEqualLotteryTicketsRefunded; do
    sed -n "/^public void $function(/,/^}/p" "$source/state.inc"
done > "$work/equal_under_test.inc"
cp "$root/tools/tests/lottery_equal_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
