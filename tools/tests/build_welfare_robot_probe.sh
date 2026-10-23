#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/welfare-robot-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source="$root/tf/addons/sourcemod/scripting/points_store"
sed -n '/^enum WelfareAvailability$/,/^}/p' "$source/transfers_and_welfare.sp" > "$work/welfare_under_test.inc"
sed -n '/^bool Store_HasPendingPurchaseReceipt(/,/^}/p' "$source/shop.sp" >> "$work/welfare_under_test.inc"
for function in Timer_WelfareRoundWin Command_Welfare Welfare_GetAvailability Welfare_PrintUnavailable Welfare_BeginCollection DebitWelfarePoolForClient SQL_OnWelfarePoolDebited; do
    sed -n "/^\(void\|public Action\|WelfareAvailability\|public void\) $function(/,/^}/p" "$source/transfers_and_welfare.sp"
done >> "$work/welfare_under_test.inc"
cp "$source/welfare_robot.sp" "$work/"
cp "$root/tools/tests/welfare_robot_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"
