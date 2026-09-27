#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

run_case() (
  local expected="$1"
  shift
  export STATE_DIR
  STATE_DIR="$(mktemp -d /tmp/resource-guard-test.XXXXXX)"
  trap 'rm -rf -- "$STATE_DIR"' EXIT
  source "$ROOT/tools/resource_guard.sh" status >/dev/null
  local -a samples=("$@")
  local sample_index=0
  STOP_MODE=systemctl
  # Never call real service controls or create diagnostic snapshots in tests.
  systemctl() { printf '%s\n' "$*" >> "$STATE_DIR/actions"; }
  sudo() {
    [[ "$1" == -n ]] && shift
    if [[ "$1" == true ]]; then return 0; fi
    "$@"
  }
  prime_cpu_stats() { :; }
  sleep() { :; }
  write_snapshot() { printf '%s\n' "$1" >> "$STATE_DIR/snapshots-created"; }
  sample_once() {
    if (( sample_index >= ${#samples[@]} )); then exit 0; fi
    LAST_SAMPLE="${samples[sample_index]}"
    sample_index=$((sample_index + 1))
  }
  (watchdog_loop)
  local actions=0
  if [[ -f "$STATE_DIR/actions" ]]; then
    actions="$(wc -l < "$STATE_DIR/actions")"
    if grep -vx 'stop mge' "$STATE_DIR/actions"; then
      echo 'FAIL: unexpected service control' >&2
      exit 1
    fi
  fi
  [[ "$BREACHES_REQUIRED" == 2 && "$actions" == "$expected" ]]
)

run_case 1 '95 0 0 0' '95 0 0 0'
run_case 1 '0 95 0 0' '0 95 0 0'
run_case 0 '95 0 0 0' '0 0 0 0' '95 0 0 0'
run_case 0 '94 94 99 99' '94 94 99 99'

(
  export STATE_DIR
  STATE_DIR="$(mktemp -d /tmp/resource-guard-test.XXXXXX)"
  trap 'rm -rf -- "$STATE_DIR"' EXIT
  source "$ROOT/tools/resource_guard.sh" status >/dev/null
  PREV_CPU_TOTAL=100
  PREV_CPU_IDLE=50
  awk() { printf '200 100\n'; }
  cpu_used_pct
  [[ "$CPU_USED_PCT" == 50 && "$PREV_CPU_TOTAL" == 200 ]]
  awk() { printf '300 190\n'; }
  cpu_used_pct
  [[ "$CPU_USED_PCT" == 10 && "$PREV_CPU_TOTAL" == 300 ]]
)
echo 'PASS: two consecutive breaches, healthy reset, MGE-only stop, interval CPU sampling.'
