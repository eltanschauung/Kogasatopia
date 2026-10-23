# Automatic Welfare Robot

`automatic_welfare_robot` is a permanent shop item costing 2,500 Gems. A
confirmed purchase enables it, prints the enable message, and schedules one
attempt three seconds later. Ownership comes from normal store receipts; the
enabled/disabled preference is a private ClientPrefs cookie.

On each `teamplay_round_start`, connected human owners with their robot enabled
attempt collection if already on RED/BLU. Spectators/unassigned owners defer the
attempt until a `player_team` post event places them on RED/BLU. If still waiting
at round end (`teamplay_round_win`, TF2's round-end event), attempt collection in
spectator instead. The three-second purchase attempt follows the same team gate.
Map start and client entry also arm collection, so the initial round-start event
may occur before clients finish loading. Pending work survives asynchronous
cookie, ownership, balance, per-map state and pool initialization. Successful
readiness callbacks resume pending collections; "not loaded" is never treated
as "not owned". Round-end spectator permission remains attached to the pending
attempt until consumed, or is reset by the next round/map. Known disabled or
non-owned robots do not retain work. Deferred state is consumed before SQL
begins, and cleared on disable, disconnect, or map end. There is no background
polling or offline collection. Normal population, pool,
balance-readiness and once-per-map requirements remain in force, including the
existing volunteer reset. Unavailable automatic attempts are silent.

The five-second round-end volunteer reset re-arms robots only for clients whose
welfare allowance was actually reset. The global `!volunteer bros can collect
welfare again!` announcement is sent **before** any of these collection requests
are submitted, so the reset-triggered robot output cannot precede it. This is a
round-end fallback and can collect for a spectator; slow-loading state remains
pending under the normal readiness handling. Client serials protect the handoff
against disconnect/slot reuse. Duplicate reset timers and non-volunteers cannot
gain extra collections. This does not turn ordinary welfare into one payout per
round: the once-per-map allowance still applies except for the existing volunteer
reset.

`!welfare` (and its existing aliases) only collects welfare or prints the normal
unavailable reason. It never toggles the robot. Owners explicitly toggle their
robot using `!welfarebot`, `!welfarerobot`, or `!bot` (console commands
`sm_welfarebot`, `sm_welfarerobot`, `sm_bot`), regardless of welfare availability.
The toggle command does not buy the item or perform a manual collection.
Ownership and cookies must finish loading before toggling. Automatic success
has only the private robot message and client-targeted, non-forced `xp_gain`
Saysounds playback; manual welfare announcements and sounds stay unchanged.

One query token per client prevents overlapping manual/automatic withdrawals.
Pool updates remain conditional on sufficient funds. Callback validation checks
the client serial, request token, map-state generation, ownership and enabled
state before awarding automatic currency. A successful withdrawal that cannot
be credited is returned to the pool using the existing economy-delta path.
Disconnect/map-end invalidation never deletes a SQL-owned DataPack.

## Regression probe

```sh
bash tools/tests/build_welfare_robot_probe.sh
```

The probe extracts the actual collection policy/callback and includes the actual
robot module. Its database, currency, cookies, sound API and timers are simulated
in memory, so it can be loaded on MGE without touching player balances,
purchases, real preferences, the welfare pool, or production sound playback.
It prints a check/failure count, then should be unloaded. It tests purchase
confirmation and delay, cookie-load ordering, persisted toggles, unavailable
conditions, normal manual behavior, overlapping requests, opted-out sound,
depleted/contended pools, SQL failure, disconnect/slot reuse, map changes,
disabled robots and stale timers.
It also checks RED/BLU joins, spectator/unassigned deferral, round-end fallback,
repeated events, invalid/disconnect user events, deferred purchase collection,
deferred state cleanup, unchanged manual collection, and fallback eligibility.
Map-change regressions include clients entering after the first round start,
team selection before ownership finishes loading, delayed per-map reset,
rotated completion orders of all five readiness prerequisites, and round-end
fallback authorization surviving asynchronous initialization. These cases
reproduced three failures in version 1.1.7 before the readiness-aware fix.
The probe also extracts the actual delayed volunteer-reset callback and checks
second-round rearming, announcement-before-query/output ordering, duplicate
timers, spectator fallback, disabled robots, missing/reset-ineligible state,
disconnect/slot reuse and delayed prerequisites.

This validates deterministic policy and callback behavior, not a real purchase
or network/database fault injection. The production plugin must also compile
cleanly and load successfully after deployment.
