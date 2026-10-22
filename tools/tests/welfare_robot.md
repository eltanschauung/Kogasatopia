# Automatic Welfare Robot

`automatic_welfare_robot` is a permanent shop item costing 2,500 Gems. A
confirmed purchase enables it, prints the enable message, and schedules one
attempt three seconds later. Ownership comes from normal store receipts; the
enabled/disabled preference is a private ClientPrefs cookie.

On each `teamplay_round_start`, connected human owners with their robot enabled
attempt collection using the same welfare availability policy as manual users.
There is no background polling or offline collection. Normal population, pool,
balance-readiness and once-per-map requirements remain in force, including the
existing volunteer reset. Unavailable automatic attempts are silent.

For owners, `!welfare` (and its existing aliases) collects normally when possible.
If collection is unavailable, it toggles the robot instead. Automatic success
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

This validates deterministic policy and callback behavior, not a real purchase
or network/database fault injection. The production plugin must also compile
cleanly and load successfully after deployment.
