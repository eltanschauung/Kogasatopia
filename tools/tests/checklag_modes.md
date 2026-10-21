# Bounded CheckLag modes (1.6)

The default remains `sm_checklag_mode 1`; valid values are 0..3. Mode changes
are immediate and clear stale evidence. The upper bound is refreshed on plugin
reload, including an engine ConVar retained from an older CheckLag build.

| Mode | Continuous collection | Alert evidence |
| --- | --- | --- |
| 0 | No monitor or diagnostic collection | None |
| 1 | Existing one-second tickrate monitor | Tickrate and observer-cost summaries |
| 2 | Same producer-disabled path as 1; a primitive frame-gap observer | Same summaries plus worst coarse frame gap in the preceding five seconds |
| 3 | Primitive frame observer, sampled callback timings, kernel counters at most once per second | Rate-limited, strictly bounded scope/call/frame and host-window detail |

Mode 2 deliberately gives up callback attribution, network-loss/choke scans,
kernel reads, strings and per-frame Profiler/self-profiler calls. Its frame
path reads engine time and tick number, and stores only gaps >=30ms in a fixed
64-row ring. Engine-time float precision is coarse on long-running servers:
these are approximate stall measurements, not microsecond timings. Frame
gaps include engine work, other plugins, sleeping and scheduler delays.

Mode 3 is **not** the old full mode 2 under another number. It advertises
producer profiling on one tick in sixteen. The shared producer include caches
native availability/admission per tick, permits at most 32 timing starts per
plugin on admitted ticks (nested scopes included), and submits only intervals
>=0.25ms. The receiver independently caps scope submissions at 32 per tick.
This intentionally omits some operations/children; inclusive remainders are
not exclusive CPU attribution. Missing sampled spans cannot exonerate a path.
Existing compiled producers also receive sampled native admission, but Weapons
must be rebuilt with the updated include to receive the producer-side cap.

Mode 3 kernel sampling is on the one-second monitor, **never** on the frame or
scope hot path. A stall cannot force another counter read. CPU/wait/fault/I/O
values describe an explicitly measured sampling window, not a specific frame.
Unavailable counters remain -1. No external/native stack recorder is launched.

Each automatic alert emits three records in modes 1 and 2: the alert, one
completed-observer summary and one emission-cost summary. Mode 3 adds at most
two frame records, one host window, two scope summaries and two calls: at most
ten records total. Detailed snapshots are separated by at least 15 seconds;
other alerts and repeated manual snapshot requests downgrade to one basic
snapshot (plus automatic observer summaries when applicable). Automatic alert
cooldown remains four seconds. No synchronous database query or log write is
performed on a frame/scope path.

`sm_lagdetails` reads the saved/basic evidence. `sm_lagsnapshot` respects the
selected mode and detail throttle. `sm_lagself` reports completed root wall
time for the one-second monitor, incoming retained scopes and alert pipeline.
The primitive frame observer is deliberately **not self-profiled**: its cost
is not reported as zero. Independent matched workload/CPU/frame measurements
must be used to evaluate its net impact. Summaries state `frame_path=unprofiled`.

Frame-to-scope correlation uses observer boundaries, not a guess based solely
on tick numbers. SourceMod timers can run before `OnGameFrame` at the same tick.
Boundaries do not restart on a round reset while old scope rows still exist;
scope age is checked explicitly. Mode/map resets clear both scope and frame
state. Mode 2 never claims callback ownership.

## Validation

Run `python3 tools/tests/test_checklag_modes.py`. Compile and run the existing
`tools/tests/checklag_probe.sp` on MGE: 76 checks, zero failures; it uses an
in-memory sink and never creates fake production incidents. Controlled alert
validation and the paired 16-bot weapons/hats workload live only on the Debug
branch. Keep private fixtures, captures, identities and raw logs out of Git.
