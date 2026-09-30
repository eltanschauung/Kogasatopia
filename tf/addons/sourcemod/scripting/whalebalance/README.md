# Unified Team Controller

`../whalescramble.sp` is the only compiled host. It dispatches DGM, class limits,
WhaleBalance/WhaleScramble and `../afkmanager/module.sp` lifecycle. Each subsystem
keeps its existing config, convars, commands and public library/API.

## Team Movement Ownership

`runtime.sp` owns operation leases/generations, move protection and respawn
verification. `admission.sp` coordinates AFK removals, voluntary spectator moves,
and spectator admission with balance/swap/scramble operations.

- Only one automatic move operation runs at a time, followed by a settle lease.
- Pending human joins reserve global/team capacity and block corrective balance
  and new swap/scramble operations until confirmation or timeout.
- Queue promotion waits/retries rather than consuming a FIFO entry while busy.
- AFK time still accrues while busy; expiration is retried without resetting it.
- Voluntary spectator exits/capacity enforcement never inherit balance immunity
  and cannot be locked out by a pending scramble or vote.
- Team changes invalidate mismatched respawn retries. Spectator exits cancel
  swap requests. Disconnect/map/unload dispatch cancels each owner's timers.
- Autobalance still counts bots but never selects them. Queue admission uses
  human-only counts. Incoming joins count toward autobalance's effective teams.

Do not load the retired standalone `afkmanager.smx` or `spec-when-full.smx`.
The compatibility `afkmanager` library/native/forwards now belong to this host.

## Verification

The production-function probes in `tools/tests/afkmanager` cover AFK activity,
whitelist timeouts, queue immunity, move ownership, reservation accounting,
bot-versus-human capacity, settle/expiry behavior and respawn cleanup. Run only
on a test server; unload the temporary probes afterward. Human-client admission
and capacity behavior should also be observed during normal populated play.
