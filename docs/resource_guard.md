# VPS resource diagnostics and MGE-only watchdog

One boot-enabled daemon owns collection, incident decisions, and service stops:
`resource-guard-watchdog.service`. The old sampler service is retired.
Runtime launcher: `/home/kogasa/resource_guard.sh`.
Implementation: `tools/resource_guard/`.

## Sampling and safety

Every **3 seconds**, record system CPU, busiest-core CPU, RAM, swap, disk space,
I/O wait, hypervisor steal, load, Linux pressure metrics, disk/network throughput,
and interval CPU/RAM/I/O for the highest-consuming processes. PID plus process
creation time prevents PID reuse from corrupting deltas. Process CPU is expressed
per core (a multithreaded process can exceed 100%); host CPU is normalized.
Command lines and environments are never collected, avoiding leaked passwords.

Two consecutive samples with **host CPU >=95% OR RAM >=95%** authorize stopping
**only MGE**, through `sudo -n systemctl stop mge.service`. TF2 is never a stop
target. The stop cooldown remains 300 seconds and survives daemon restarts.
The daemon does not automatically restart MGE.

Two consecutive samples of busiest-core CPU >=98%, I/O wait >=20%, or steal >=10%
create **diagnostic-only** incidents. Incident capture is limited to once per
five minutes during a continuing episode. These are investigative clues, not
proof that a particular process or plugin caused game lag.

Sampling uses a monotonic clock with interval deltas, not lifetime-average
`ps` CPU readings. SQL and service-stop operations run separately from sampling.

## Persistence

Credentials are read directly from the SourceMod `Databases/default` section in
`~/hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg`; none are copied into
the repository or service unit.

Tables in that database:
- `resource_guard_incidents`: timestamp, host metrics, reasons, action/outcome,
  and approximately 30 seconds of preceding sample evidence.
- `resource_guard_incident_processes`: incident-linked PID/name/systemd unit,
  interval CPU, resident memory, I/O rates, and thread count.

CheckLag records game tickrate events in `plugin_statistics_events`. Host
incidents are intentionally separate: they do not invent ticks or map sessions.
Their Unix-second `occurred_at` timestamps allow correlation with CheckLag.

A local SQLite journal at `~/resource-guard/journal.sqlite3` queues incidents
before publishing. Database outages retain them for idempotent replay; they do
not block sampling or stop decisions. Action updates are versioned so a queued
write cannot overwrite a newer action result. Interrupted stop requests are
marked, not replayed after restarting into a potentially healthy system.
Local regular samples retain 24 hours; published incidents retain seven days
locally. Unpublished incidents are never automatically discarded. Database
incidents remain until explicitly deleted. `daemon.log` rotates at 1 MiB with
three backups; old shell logs are preserved, but no longer appended.

## Operations

```sh
~/resource_guard.sh status
~/resource_guard.sh sample-once
sudo systemctl restart resource-guard-watchdog
sudo systemctl disable --now resource-guard-watchdog
~/.venvs/resource-guard/bin/python -m unittest discover -s tools/tests -p 'test_resource_guard.py'
```

Install dependencies from `tools/resource_guard/requirements.txt` into
`~/.venvs/resource-guard`. Deploy the tracked service unit to
`/etc/systemd/system/`, run `systemctl daemon-reload`, and enable/start it.
Do not also run the old screen/nohup sampler.

## Example queries

```sql
SELECT incident_id, FROM_UNIXTIME(occurred_at) AS happened,
       reasons, cpu_pct, memory_pct, iowait_pct, steal_pct, action
FROM resource_guard_incidents
ORDER BY occurred_at DESC LIMIT 20;

SELECT p.process_name, p.systemd_unit, p.cpu_pct, p.rss_bytes,
       p.read_bytes_per_second, p.write_bytes_per_second
FROM resource_guard_incident_processes p
WHERE p.incident_id = 'INCIDENT-UUID'
ORDER BY p.cpu_pct DESC;

SELECT i.incident_id, e.source_plugin, e.event_name, e.observed_tickrate
FROM resource_guard_incidents i
JOIN plugin_statistics_events e
  ON e.occurred_at BETWEEN i.occurred_at - 10 AND i.occurred_at + 10
WHERE e.source_plugin = 'checklag'
ORDER BY i.occurred_at DESC;
```
