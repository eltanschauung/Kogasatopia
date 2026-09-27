#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${STATE_DIR:-$HOME/resource-guard}"
SNAPSHOT_DIR="$STATE_DIR/snapshots"
METRICS_LOG="$STATE_DIR/metrics.tsv"
WATCHDOG_LOG="$STATE_DIR/watchdog.log"
SAMPLER_PID_FILE="$STATE_DIR/sampler.pid"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog.pid"
SAMPLER_STDOUT="$STATE_DIR/sampler.out"
WATCHDOG_STDOUT="$STATE_DIR/watchdog.out"
SAMPLER_SESSION="${SAMPLER_SESSION:-resource-guard-sampler}"
WATCHDOG_SESSION="${WATCHDOG_SESSION:-resource-guard-watchdog}"

SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-5}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-5}"
MEM_THRESHOLD="${MEM_THRESHOLD:-95}"
CPU_THRESHOLD="${CPU_THRESHOLD:-95}"
BREACHES_REQUIRED="${BREACHES_REQUIRED:-2}"
COOLDOWN_SEC="${COOLDOWN_SEC:-300}"
STOP_MODE="${STOP_MODE:-auto}"
MGE_STOP_SCRIPT="${MGE_STOP_SCRIPT:-/home/kogasa/stop_mge_screen.sh}"

PREV_CPU_TOTAL=0
PREV_CPU_IDLE=0
CPU_USED_PCT=0
LAST_SAMPLE=""

mkdir -p "$STATE_DIR" "$SNAPSHOT_DIR"

ts() {
  date -Is
}

log_watchdog() {
  printf '%s\t%s\n' "$(ts)" "$*" >> "$WATCHDOG_LOG"
}

pid_is_live() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid="$(cat "$pid_file")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

screen_has_session() {
  local session_name="$1"
  screen -list 2>/dev/null | grep -q "\\.${session_name}[[:space:]]"
}

read_mem_stats() {
  awk '
    /MemTotal:/ {mem_total=$2}
    /MemAvailable:/ {mem_avail=$2}
    /SwapTotal:/ {swap_total=$2}
    /SwapFree:/ {swap_free=$2}
    END {
      printf "%s %s %s %s\n", mem_total, mem_avail, swap_total, swap_free
    }
  ' /proc/meminfo
}

prime_cpu_stats() {
  read -r PREV_CPU_TOTAL PREV_CPU_IDLE < <(
    awk '
      /^cpu / {
        total=$2+$3+$4+$5+$6+$7+$8+$9
        idle=$5+$6
        printf "%s %s\n", total, idle
      }
    ' /proc/stat
  )
}

cpu_used_pct() {
  local cur_total cur_idle delta_total delta_idle used
  read -r cur_total cur_idle < <(
    awk '
      /^cpu / {
        total=$2+$3+$4+$5+$6+$7+$8+$9
        idle=$5+$6
        printf "%s %s\n", total, idle
      }
    ' /proc/stat
  )

  if (( PREV_CPU_TOTAL == 0 )); then
    PREV_CPU_TOTAL="$cur_total"
    PREV_CPU_IDLE="$cur_idle"
    CPU_USED_PCT=0
    return
  fi

  delta_total=$((cur_total - PREV_CPU_TOTAL))
  delta_idle=$((cur_idle - PREV_CPU_IDLE))
  PREV_CPU_TOTAL="$cur_total"
  PREV_CPU_IDLE="$cur_idle"

  if (( delta_total <= 0 )); then
    CPU_USED_PCT=0
    return
  fi

  used=$((100 * (delta_total - delta_idle) / delta_total))
  CPU_USED_PCT="$used"
}

load_stats() {
  awk '{printf "%s %s %s\n", $1, $2, $3}' /proc/loadavg
}

rootfs_pct() {
  df -P / | awk 'END {gsub(/%/, "", $5); print $5}'
}

srcds_rss_kb() {
  ps -C srcds_linux -o rss= 2>/dev/null | awk '{sum+=$1} END {print sum+0}'
}

top_cpu_row() {
  while IFS= read -r row; do
    [[ "$row" == *" ps "* ]] && continue
    xargs <<< "$row"
    return 0
  done < <(ps -eo pid=,comm=,%cpu=,%mem=,rss=,user= --sort=-%cpu)
}

top_mem_row() {
  while IFS= read -r row; do
    [[ "$row" == *" ps "* ]] && continue
    xargs <<< "$row"
    return 0
  done < <(ps -eo pid=,comm=,%cpu=,%mem=,rss=,user= --sort=-%mem)
}

write_metrics_header() {
  [[ -s "$METRICS_LOG" ]] && return
  printf 'ts\tmem_used_pct\tswap_used_pct\tcpu_used_pct\tload1\tload5\tload15\trootfs_pct\tmem_avail_mb\tsrcds_rss_mb\ttop_cpu\ttop_mem\n' >> "$METRICS_LOG"
}

rotate_metrics_log() {
  [[ -f "$METRICS_LOG" ]] || return 0
  local size
  size="$(wc -c < "$METRICS_LOG")"
  (( size < 10485760 )) && return
  mv "$METRICS_LOG" "$STATE_DIR/metrics.$(date +%Y%m%dT%H%M%S).tsv"
}

sample_once() {
  local record_metrics="${1:-1}"
  local mem_total mem_avail swap_total swap_free
  local mem_used_pct swap_used_pct cpu_pct load1 load5 load15
  local root_pct srcds_rss_mb mem_avail_mb top_cpu top_mem

  read -r mem_total mem_avail swap_total swap_free < <(read_mem_stats)
  cpu_used_pct
  cpu_pct="$CPU_USED_PCT"
  read -r load1 load5 load15 < <(load_stats)
  root_pct="$(rootfs_pct)"
  srcds_rss_mb="$(( $(srcds_rss_kb) / 1024 ))"
  mem_avail_mb="$(( mem_avail / 1024 ))"
  top_cpu="$(top_cpu_row)"
  top_mem="$(top_mem_row)"

  mem_used_pct=$((100 * (mem_total - mem_avail) / mem_total))
  if (( swap_total > 0 )); then
    swap_used_pct=$((100 * (swap_total - swap_free) / swap_total))
  else
    swap_used_pct=0
  fi

  if [[ "$record_metrics" == "1" ]]; then
    rotate_metrics_log
    write_metrics_header
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(ts)" \
      "$mem_used_pct" \
      "$swap_used_pct" \
      "$cpu_pct" \
      "$load1" \
      "$load5" \
      "$load15" \
      "$root_pct" \
      "$mem_avail_mb" \
      "$srcds_rss_mb" \
      "$top_cpu" \
      "$top_mem" \
      >> "$METRICS_LOG"
  fi

  LAST_SAMPLE="$mem_used_pct $cpu_pct $swap_used_pct $root_pct"
  printf '%s\n' "$LAST_SAMPLE"
}

write_snapshot() {
  local reason="$1"
  local snapshot_file="$SNAPSHOT_DIR/${reason}_$(date +%Y%m%dT%H%M%S).log"
  {
    echo "reason=$reason"
    echo "ts=$(ts)"
    echo
    echo "[uptime]"
    uptime
    echo
    echo "[free -h]"
    free -h
    echo
    echo "[df -h / /tmp /var/log /home]"
    df -h / /tmp /var/log /home 2>/dev/null || true
    echo
    echo "[vmstat 1 5]"
    vmstat 1 5
    echo
    echo "[top cpu]"
    ps -eo pid,ppid,user,unit,cmd,%cpu,%mem,rss --sort=-%cpu | head -n 20
    echo
    echo "[top mem]"
    ps -eo pid,ppid,user,unit,cmd,%mem,%cpu,rss --sort=-%mem | head -n 20
    echo
    echo "[tf2/mge status]"
    systemctl status tf2 mge --no-pager -l || true
  } > "$snapshot_file" 2>&1
}

stop_mge() {
  local method=""

  if [[ "$STOP_MODE" == "auto" || "$STOP_MODE" == "systemctl" ]]; then
    if [[ "$EUID" -eq 0 ]]; then
      systemctl stop mge
      method="systemctl-root"
    elif sudo -n true >/dev/null 2>&1; then
      sudo -n systemctl stop mge
      method="systemctl-sudo"
    elif [[ "$STOP_MODE" == "systemctl" ]]; then
      log_watchdog "systemctl-stop-unavailable"
      return 1
    fi
  fi

  if [[ -z "$method" ]]; then
    bash "$MGE_STOP_SCRIPT" || true
    method="stop-scripts"
  fi

  log_watchdog "stop-issued target=mge method=$method"
}

sample_loop() {
  prime_cpu_stats
  sleep 1
  while :; do
    sample_once 1 >/dev/null
    sleep "$SAMPLE_INTERVAL"
  done
}

watchdog_loop() {
  local breaches=0
  local last_stop=0
  local mem_pct cpu_pct swap_pct root_pct now

  prime_cpu_stats
  sleep 1
  log_watchdog "watchdog-start mem=$MEM_THRESHOLD cpu=$CPU_THRESHOLD breaches=$BREACHES_REQUIRED cooldown=$COOLDOWN_SEC mode=$STOP_MODE"

  while :; do
    sample_once 0 >/dev/null
    read -r mem_pct cpu_pct swap_pct root_pct <<< "$LAST_SAMPLE"
    log_watchdog "sample mem=$mem_pct cpu=$cpu_pct swap=$swap_pct rootfs=$root_pct breaches=$breaches"

    if (( mem_pct >= MEM_THRESHOLD || cpu_pct >= CPU_THRESHOLD )); then
      breaches=$((breaches + 1))
      log_watchdog "breach-count=$breaches"
    else
      breaches=0
    fi

    now="$(date +%s)"
    if (( breaches >= BREACHES_REQUIRED )); then
      if (( now - last_stop >= COOLDOWN_SEC )); then
        log_watchdog "threshold-hit mem=$mem_pct cpu=$cpu_pct swap=$swap_pct rootfs=$root_pct"
        write_snapshot "threshold_hit"
        stop_mge || true
        last_stop="$now"
      else
        log_watchdog "threshold-hit-but-cooldown active"
      fi
      breaches=0
    fi

    sleep "$WATCHDOG_INTERVAL"
  done
}

start_loop() {
  local mode="$1"
  local pid_file="$2"
  local stdout_file="$3"
  local session_name="$4"

  if command -v screen >/dev/null 2>&1; then
    if screen_has_session "$session_name"; then
      echo "$mode already running session=$session_name"
      return
    fi

    local screen_cmd
    printf -v screen_cmd 'cd %q && exec %q %q >> %q 2>&1' \
      "$SCRIPT_DIR" \
      "$SCRIPT_DIR/resource_guard.sh" \
      "$mode" \
      "$stdout_file"
    rm -f "$pid_file"
    screen -dmS "$session_name" bash -lc "$screen_cmd"
    echo "$mode started session=$session_name"
    return
  fi

  if pid_is_live "$pid_file"; then
    echo "$mode already running pid=$(cat "$pid_file")"
    return
  fi

  nohup "$0" "$mode" >> "$stdout_file" 2>&1 &
  echo "$!" > "$pid_file"
  echo "$mode started pid=$!"
}

stop_loop() {
  local mode="$1"
  local pid_file="$2"
  local session_name="$3"

  if command -v screen >/dev/null 2>&1 && screen_has_session "$session_name"; then
    screen -S "$session_name" -X quit || true
    rm -f "$pid_file"
    echo "$mode stopped session=$session_name"
    return
  fi

  if ! pid_is_live "$pid_file"; then
    rm -f "$pid_file"
    echo "$mode not running"
    return
  fi

  local pid
  pid="$(cat "$pid_file")"
  kill "$pid"
  rm -f "$pid_file"
  echo "$mode stopped pid=$pid"
}

status_loop() {
  local mode="$1"
  local pid_file="$2"
  local session_name="$3"

  if command -v screen >/dev/null 2>&1 && screen_has_session "$session_name"; then
    echo "$mode running session=$session_name"
    return
  fi

  if pid_is_live "$pid_file"; then
    echo "$mode running pid=$(cat "$pid_file")"
  else
    echo "$mode stopped"
  fi
}

usage() {
  cat <<'EOF'
usage:
  resource_guard.sh sample-loop
  resource_guard.sh watchdog-loop
  resource_guard.sh sample-once
  resource_guard.sh snapshot [reason]
  resource_guard.sh start
  resource_guard.sh stop
  resource_guard.sh status
EOF
}

cmd="${1:-}"
case "$cmd" in
  sample-loop)
    sample_loop
    ;;
  watchdog-loop)
    watchdog_loop
    ;;
  sample-once)
    prime_cpu_stats
    sleep 1
    sample_once 1
    ;;
  snapshot)
    write_snapshot "${2:-manual}"
    ;;
  start)
    start_loop sample-loop "$SAMPLER_PID_FILE" "$SAMPLER_STDOUT" "$SAMPLER_SESSION"
    start_loop watchdog-loop "$WATCHDOG_PID_FILE" "$WATCHDOG_STDOUT" "$WATCHDOG_SESSION"
    ;;
  stop)
    stop_loop sample-loop "$SAMPLER_PID_FILE" "$SAMPLER_SESSION"
    stop_loop watchdog-loop "$WATCHDOG_PID_FILE" "$WATCHDOG_SESSION"
    ;;
  status)
    status_loop sample-loop "$SAMPLER_PID_FILE" "$SAMPLER_SESSION"
    status_loop watchdog-loop "$WATCHDOG_PID_FILE" "$WATCHDOG_SESSION"
    ;;
  *)
    usage
    exit 1
    ;;
esac
