#!/usr/bin/env bash
set -euo pipefail
SERVICE=resource-guard-watchdog.service
PYTHON=/home/kogasa/.venvs/resource-guard/bin/python
MAIN=/home/kogasa/Kogasatopia/tools/resource_guard/main.py
case "${1:-status}" in
  start) exec sudo -n systemctl start "$SERVICE" ;;
  stop) exec sudo -n systemctl stop "$SERVICE" ;;
  status) exec systemctl status "$SERVICE" --no-pager ;;
  sample-once) exec "$PYTHON" "$MAIN" --once ;;
  run|watchdog-loop) exec "$PYTHON" "$MAIN" ;;
  migrate) exec "$PYTHON" "$MAIN" --migrate ;;
  *) echo "Usage: resource_guard.sh {start|stop|status|sample-once|migrate}" >&2; exit 2 ;;
esac
