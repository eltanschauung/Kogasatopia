# AFK Manager

Compile only `../whalescramble.sp`. `module.sp` contains AFK policy and input
tracking; `spec-when-full.sp` contains the isolated spectator queue/capacity
subsystem. Neither is a standalone plugin. Unload and retire `afkmanager.smx`
and `spec-when-full.smx` before activating the combined host. Startup rejects
these legacy plugins rather than allowing competing command/team-join owners.

## Ownership

The AFK module owns client activity, idle accounting, whitelist timeout
eligibility, the AFK forwards, and one one-second maintenance timer. The host
dispatches client/map/plugin lifecycle and real-input forwards. AFK and surrender
handling share one team-event hook; other policy modules keep their own hooks.
Queue activity checks run every three seconds from that timer using the
same activity state. There is no internal cross-plugin native dependency.
Reconciliation and pending-join timers belong to the queue module and are
cancelled on completion, replacement, disconnect, map end, or shutdown.

WhaleBalance's coordinator now also owns AFK removals and queue promotions.
Promotions wait while a balance/swap/scramble is running or settling. Pending
joins reserve their destination slots and prevent new balance operations;
autobalance's bot-inclusive counts also include incoming reservations. Queue
capacity remains human-only. AFK immunity policies remain independent of
autobalance/scramble immunity, duels and killstreaks. Voluntary spectator exits
and capacity correction are always allowed. Leaving a team invalidates stale
respawn retries and spectator exits cancel swap requests.

The DGM capacity/population helpers are now direct calls within this host, not
optional native lookups. `sm_afkmanager_kick_spec_min_player_count` remains for
old-config compatibility but its no-DGM fallback is no longer needed.

Idle time uses monotonic engine time. Dead time with a selected class pauses
the counter without erasing prior live idle time. Population exemptions and
team/class events reset idle bookkeeping without manufacturing actual input.
Buttons, mouse, weapon selection, spectator camera commands, chat, and voice
are activity. The public `AFKManager_GetLastActivityTime(client)` API returns
that real-input engine timestamp, or zero when unavailable.

Queued clients and pending promotions retain AFK-kick protection. The existing
`OnAFKKick` hook remains cancellable; `OnAFKSwitch` is now emitted after a
successful AFK move to spectator. Whitelist level exactly 2 doubles the live
timeout when the AFK action moves players to spectator. Eligibility uses the
AdminsDB cached client-level API each pass, so changes apply without reconnecting.
Without that API, the normal timeout applies. Spectator/kick timeouts are unchanged.

## Compatibility

Keep the existing convars and configuration files:

- `cfg/sourcemod/afkmanager.cfg`: `sm_afkmanager_*` controls.
- `cfg/sourcemod/plugin.spec-when-full.cfg`: `sm_fullspec_*` queue controls.
- `sm_spec_when_full_enabled`: independently enables capacity/queue handling.
- `sm_spec_when_full_log`: optional population logging through Plugin Statistics.
- `translations/spec-when-full.phrases.txt`: existing queue messages.

The FIFO, capacity reservations, suspension hysteresis, menus, `!joinqueue`,
`!leavequeue`, `!checkautojoin`, `!spec`, `!afk`, `!remove`, and aliases remain.
Activity autoqueue requires a human spectator with fresh input, not already
queued or joining. `!leavequeue`, spectator commands and their aliases grant
60 seconds of automatic-requeue immunity. Input during immunity is discarded;
explicit joining remains permitted. Map transitions preserve unexpired
immunity, while disconnects/new connections reset it.

The `afkmanager` library, `AFKManager_GetLastActivityTime`, `OnAFKKick` and
`OnAFKSwitch` remain public. `include/afkmanager.inc` now identifies
`whalescramble.smx` as the provider.

## Regression Probe

Run `bash tools/tests/afkmanager/build_activity_probe.sh` from the repository
root. Load its `/tmp/activity_queue_probe.smx` on a test server and execute
`sm_activity_queue_probe`, then unload it. The probe compiles extracted
production functions against simulated clients: real players are not moved,
kicked, or queued. It also verifies the live activity native.

Run `bash tools/tests/afkmanager/build_controller_probe.sh` and load
`/tmp/team_controller_probe.smx`, then execute `sm_team_controller_probe` for
coordinator/admission coverage. It extracts production coordination, reservation,
team-selection and spectator-move functions and simulates clients; no real
teams, queues, or convars are changed. Unload both probes after testing.

## Credits

AFK Manager: random, Hombre; original project URL `http://castaway.tf`.
Spectate When Full: Eric Zhang, `https://ericaftereric.top/`, originally
imported from the `eltanschauung/spec-when-full` fork at commit `0a34dca`.
