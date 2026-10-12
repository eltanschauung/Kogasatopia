# KOTH timer-progress autoscramble regression

The existing `sm_whalescramble_koth_no_cap` switch now uses each team's timer
remaining at the first capture as its baseline. At full-round end, either team
consuming **at most 20%** triggers the existing next-round autoscramble controller.
Both teams must consume **more than 20%** to avoid this trigger. Other autoscramble
triggers, cooldowns, and no-sequential guards are unchanged.

The baseline resets on `teamplay_round_start` and map lifecycle changes. Missing,
unreadable, zero initial, or removed/recycled timer entities fall back to the old
never-captured rule. A missed first-capture baseline is not replaced on recapture.
No frame hook or polling timer is added.

Compile the production plugin normally. Compile the standalone probe with the
repository scripting directory and live includes in its include paths:

```sh
spcomp tools/tests/whalescramble/koth_timer_progress_probe.sp \
  -i tf/addons/sourcemod/scripting -i /path/to/live/scripting/include \
  -o /private/test/output/koth_timer_progress_probe.smx
```

Load the probe **only on MGE**, run `sm_koth_progress_probe`, and verify its summary
has zero failures. These tests include the actual production helper with mocked
timer discovery/values/reference resolution, covering the exact boundary, RED/BLU
symmetry, asymmetric baselines, snapshot-once semantics, reset, and all fallback
capture combinations.

`sm_koth_progress_status` prints only map name and real-human count. The integration
command refuses non-console callers, non-MGE maps, or any connected human. On empty
MGE, reload the production WhaleScramble plugin between the following test cases:

```text
sm_koth_progress_integration 1
sm_koth_progress_integration 2
sm_koth_progress_integration 3
```

The integration probe creates temporary paused `team_round_timer` entities and
invokes the live plugin's first-capture and full-round-end callbacks with copied
events, without broadcasting synthetic events, ending the real round, or moving
players. Each case starts at RED=300/BLU=300 and invokes a recapture after changing
the timers, verifying the baseline is not overwritten:

| Case | End RED | End BLU | Expected timer decision | Expected KOTH trigger |
| --- | ---: | ---: | --- | --- |
| 1 | 30 | 240 | Stomp (2), exactly 20% for BLU | Armed |
| 2 | 30 | 239 | Competitive (1), both >20% | Skipped |
| 3 | 30 | Removed | Unavailable (0), both captured | Fallback skips |

Inspect only the new `KOTH first-capture timers recorded` / `KOTH auto scramble
check` / `KOTH auto scramble armed` log lines; do not publish raw server logs.
The probe restores changed convars and removes its temporary entities. Reload the
production plugin afterward to clear synthetic round state, then unload and retire
the probe binary outside the active plugins folder. Do not run actual
`teamplay_round_start`/`teamplay_round_win` events against occupied servers.

## Verified 2026-10-11

On empty MGE (`mge_eientei_v4a`): production and probe compiled without warnings;
the helper passed 25 checks with zero failures. The live callbacks and real timer
entities produced the expected three decisions above. No WhaleScramble/probe
errors appeared. The production plugin was reloaded to clear test state, the
probe was unloaded, and its binary was retired outside the plugin directory.
The main server was not reloaded or restarted.
