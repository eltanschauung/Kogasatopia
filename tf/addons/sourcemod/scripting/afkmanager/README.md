# AFK Manager

Compile only `../afkmanager.sp`. `spec-when-full.sp` is its included spectator
queue/capacity module, not a second plugin. Retire `spec-when-full.smx` when
deploying; the host also unloads a still-running legacy instance on late load
to prevent duplicate command and team-join ownership.

## Ownership

The host owns client activity, idle accounting, SteamID exception caching,
team/class hooks, the AFK forwards, and one one-second maintenance timer.
Queue activity checks run every three seconds from that timer using the
same activity state. There is no internal cross-plugin native dependency.
Reconciliation and pending-join timers belong to the queue module and are
cancelled on completion, replacement, disconnect, map end, or shutdown.

Idle time uses monotonic engine time. Dead time with a selected class pauses
the counter without erasing prior live idle time. Population exemptions and
team/class events reset idle bookkeeping without manufacturing actual input.
Buttons, mouse, weapon selection, spectator camera commands, chat, and voice
are activity. The public `AFKManager_GetLastActivityTime(client)` API returns
that real-input engine timestamp, or zero when unavailable.

Queued clients and pending promotions retain AFK-kick protection. The existing
`OnAFKKick` hook remains cancellable; `OnAFKSwitch` is now emitted after a
successful AFK move to spectator. The existing SteamID timeout exception is
cached on authentication instead of resolving it in every maintenance pass.

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

## Regression Probe

Run `bash tools/tests/afkmanager/build_activity_probe.sh` from the repository
root. Load its `/tmp/activity_queue_probe.smx` on a test server and execute
`sm_activity_queue_probe`, then unload it. The probe compiles extracted
production functions against simulated clients: real players are not moved,
kicked, or queued. It also verifies the live activity native.

## Credits

AFK Manager: random, Hombre; original project URL `http://castaway.tf`.
Spectate When Full: Eric Zhang, `https://ericaftereric.top/`, originally
imported from the `eltanschauung/spec-when-full` fork at commit `0a34dca`.
