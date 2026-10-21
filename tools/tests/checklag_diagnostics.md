# CheckLag v3 diagnostics

Historical pre-1.6 architecture and incident notes. Current modes 2 and 3,
sampling limits and clock precision are documented in [checklag_modes.md](checklag_modes.md).
The old full mode 2 described below is no longer available.

## Collection modes

`sm_checklag_mode` defaults to `1` and is bounded to 0..2:

- `0`: off; no monitor timer, automatic alerts, chat keyword responses,
  frame/host sampling, or callback scope collection. Explicit commands explain
  that CheckLag is disabled.
- `1`: tickrate alerts only. Keep the one-second tickrate check and normal
  cooldown/round guards. Save one small `tickrate_drop` event per alert, with
  no frame, host, network-loss/choke, scope, or call snapshots.
- `2`: the existing full in-plugin profiling, snapshots and `!lagdetails`.

Mode changes take effect immediately, discard stale diagnostic state, and
reset the alert cooldown. `!lagsnapshot` never bypasses the selected mode.
Updated `kogasa_performance.inc` callers check the optional
`CheckLag_IsProfilingEnabled` native before starting a profiler. Older compiled
callers remain binary-compatible; their submitted scopes are ignored below 2.
Weapons must be recompiled with the updated include to skip producer timing.
Read-only diagnostic detour bindings remain installed until Weapons unloads;
their profiling spans are disabled below 2.

The external native recorder is separate and remains stopped. Mode 2 does
not start it: its repeated capture startup/rollover coincided with all ten
alerts reviewed from 00:29:32 to 00:39:37 EDT on 2026-10-07. Those captures had
6.2..7.9-second blind spots and cannot identify a blocking native function.
After stopping the recorder, approximately four minutes of observation found
no new alerts with players still connected. This is strong correlation, not
proof of the precise blocking mechanism, and does not explain older
CPU-heavy inventory stalls.

## Why this upgrade

Reviewed every recorded CheckLag tickrate drop in the four hours ending
2026-10-05 02:06 EDT (all nine were on the main server).
The largest scope in a five-second window is not necessarily related to its
worst frame. Five of these alerts illustrate that problem:

| Alert tick | Worst frame tick | Frame ms | Window's largest interval | Interval tick | ms |
| --- | --- | --- | --- | --- | --- |
| 65333 | 65310 | 171.87 | Soldier inventory | 65051 | 23.54 |
| 127133 | 127091 | 93.75 | Soldier inventory | 127090 | 54.55 |
| 9473 | 9420 | 156.25 | Heavy inventory | 9419 | 103.75 |
| 39339 | 39307 | 144.53 | Soldier inventory | 39306 | 62.75 |
| 64739 | 64671 | 179.68 | Engineer inventory | 64630 | 32.21 |
| 80473 | 80406 | 250.00 | Scout inventory | 80450 | 0.92 |
| 95473 | 95430 | 917.96 | Spy inventory | 95279 | 6.01 |
| 68292 | 68259 | 140.62 | Engineer inventory | 68258 | 101.26 |
| 158092 | 158043 | 105.46 | Demoman inventory | 158053 | 1.55 |

No original incidents are rewritten. These numbers describe old measurements,
not proof of CPU attribution or an identified engine root cause.

## Reading new events

- Join on map session and `alert_tick`, never tick alone across maps.
- `tickrate_drop` keeps the old window fields with
  `measured_role=window_context`; admin chat now uses stalled-tick correlation.
- `lag_frame` records up to eight frames >=30 ms, their previous/work tick,
  actual wall duration, nominal budget, and the largest matching slow call.
  `outside_largest_ms` is only the portion outside that single interval.
  Do not sum overlapping inclusive scopes or call this exclusive CPU time.
  Calls completing on the following tick are excluded, as are known
  multi-frame scopes. Old callers are correlated by their end tick.
- `lag_slow_call` adds start tick, per-plugin span/parent IDs, completed direct
  children, and the remainder. `children_ms=-1` / `remainder_ms=-1` means
  an older compiled caller supplied no nesting data. Span IDs are local to
  the named plugin instance; they are not cross-plugin IDs.
- `lag_host_window` is linked to `lag_frame.host_seq`. It covers the explicitly
  logged sampling window, normally <=250 ms plus the stall, NOT exactly one
  frame. Main-thread CPU, scheduler runnable-wait, time slices, thread page
  faults and process-wide disk byte deltas can separate CPU-heavy work from
  blocked/off-CPU intervals. Missing/reset counters are -1; never interpret
  unavailable scheduler-wait statistics as zero. Flags: CPU=1, wait=2,
  faults=4, process I/O=8.
- `probe_ms` measures counter-read overhead. Reads are read-only, three small
  procfs files at most four times per second normally, or immediately after
  a stalled frame. No system settings or scheduler statistics are enabled.
  No environments, command lines, addresses, Steam IDs or names are read.
- Frame durations use the profiler clock; engine time is only for window age.
- Complete `GetLoadoutItem(engine+hooks)` and
  `GiveNamedItem/<classname>(engine+hooks)` spans include engine work and other
  hooks. Existing Weapons post-hook timings remain available as children.
  `sm_weapons_inventory_diagnostics 0` disables GiveNamedItem measurements.
  These detours never alter function parameters or results.
- `overwritten_calls` and `dropped_scopes` report bounded-buffer pressure.
  Logging remains alert-only, with bounded rings; no per-frame database writes.

## Verification

Compile `tools/tests/checklag_probe.sp` with the repository scripting path and
live SourceMod includes, load from `plugins/disabled` on a test server, run
`sm_checklag_probe`, unload. Expected: 45 checks, 0 failures. Synthetic
telemetry stays in memory and is never sent to the real statistics database.
It exercises all nine historical tick relationships, clock/counter rollover,
legacy callers, nested intervals, unmatched stalls, manual-vs-alert events,
rate-limited host sampling and overhead logging.

The separate `weapons/inventory_diagnostics_probe.sp` refuses to run with human
clients present. From the test console, `sm_inventory_diagnostics_probe`
creates one disposable bot, looks up/creates stock items for four classes,
verifies 16 inventory checks and removes it. It does not respawn the bot (MGE
can intentionally keep unassigned clients spectating).
Follow with `sm_lagsnapshot` (manual, not an incident)
and verify the complete engine spans and span metadata in the database.
Never force a delay or an actual lag alert to test this pipeline.

Linux counter references:
https://docs.kernel.org/scheduler/sched-stats.html
https://docs.kernel.org/filesystems/proc.html
