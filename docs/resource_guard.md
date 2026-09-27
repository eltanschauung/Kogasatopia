# VPS resource watchdog

Runtime script: `/home/kogasa/resource_guard.sh`.
Logs: `/home/kogasa/resource-guard/`.

The sampler and watchdog run as separate boot-enabled systemd services:
`resource-guard-sampler.service` and `resource-guard-watchdog.service`.
Both restart automatically if their process exits.

The watchdog samples every five seconds. Two consecutive samples with CPU or
memory usage at least 95% create a diagnostic snapshot and stop **only MGE** via
`sudo -n systemctl stop mge`. Healthy samples reset the consecutive count.
The stop cooldown remains five minutes. The watchdog never stops TF2 and does
not automatically restart MGE; the existing MGE startup schedule remains intact.
CPU utilization is measured between samples, not since watchdog startup.

Check with `systemctl status resource-guard-sampler resource-guard-watchdog`.
Disable with `sudo systemctl disable --now resource-guard-watchdog
resource-guard-sampler`.
The script's legacy `start`, `stop`, and `status` commands manage screen/nohup
loops, not these systemd services; do not start duplicate loops.

Regression checks: `bash tools/tests/resource_guard_test.sh`. Service stops are
mocked; the tests do not stop either game server.
