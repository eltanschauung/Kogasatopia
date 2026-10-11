# CheckLag observer-cost diagnostics

`sm_checklag_mode` defaults to 1: one tickrate monitor per second, with reused
Profiler handles measuring that monitor. Mode 0 bypasses collection. Mode 2
also measures frame collection and incoming scope recording. `sm_lagself`
reports the preceding five seconds of completed CheckLag work.

`lag_self_window` records per-tick root wall time and window totals.
`lag_self_category` records inclusive nested category timings; **do not sum
the categories**. `lag_self_emission` measures snapshot construction, telemetry
submission and log/chat emission. It excludes its own final summary write.
The current snapshot cannot be included in a retrospective completed-work
report; its final timing is logged separately and included in later reports.

Observer wall time is evidence of possible contribution, not proof of CPU
ownership. It includes synchronous callees such as plugin_statistics and file
I/O, while asynchronous DB work may execute later elsewhere. Frame gaps can
include sleeping and engine/plugin work not measured by CheckLag. Compare
equivalent workload trials in modes 0, 1 and 2 with an independent observer.

The fixed 512-tick ring covers more than five seconds at TF2's usual 66 Hz.
There are no per-frame disk writes, database queries, client identities or
native stack samples in this generally useful main-branch diagnostic.

Validation: compile against SourceMod 1.12; run `sm_lagself` in each mode;
exercise automatic and manual snapshots in mode 2; verify category timings
are nonnegative and that total root time is not a nested-category sum. Stress
and independent frame sampling are maintained only on Kogasatopia-Debug.
