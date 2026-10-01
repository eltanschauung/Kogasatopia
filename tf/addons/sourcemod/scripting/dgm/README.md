# Respawn Modes

`dgm_halve_respawn_waves` defaults to `0`; server.cfg enables it with `1`.
It changes the implementation of DGM's reduced-respawn state, not the existing
population/setup/admin policy that selects that state.

- Normal state: `respawn_time 30`; sm_respawn restores the latest map-authored
  team waves and cancels DGM forced-respawn timers.
- Reduced state, compatible map: half each team's native map-authored wave;
  DGM forced-respawn timers are suppressed and mp_disable_respawn_times is 0.
- Reduced state, unsupported/uninitialized map: existing DGM timer fallback.
- Mode disabled: restore native baselines and retain the legacy implementation.

Compatibility requires real map outputs targeting named tf_gamerules entities,
Set inputs for both teams, and initialized nonnegative team wave values.
Arena, MvM, Robot Destruction, per-player respawn overrides, and small-format
gamemodes are excluded. Maps that initialize their waves on the first capture
remain on the fallback until both values are known.

native_respawn_waves.sp observes native Set/Add calls and RoundRespawn, preserving
an unmodified baseline. Add operations are rebased against that baseline;
coalesced next-frame entity inputs apply the multiplier. Own-input and map
generation guards prevent recursive hooks, compounded halving, and stale work.
RoundRespawn also clears round-win's temporary suppression without clearing
the admin's selected normal/reduced state. Unload and mode-off restore baselines.

This halves configured waves, not the complete death/freeze-camera delay.
TF2 population scaling and its five-second floor can make the effective interval
reduction differ from 50%. Already queued waves are not forcibly rescheduled.

sm_st reports native ownership, applied values, and normal baselines for diagnosis.
Linux and linux64 signatures were verified against TF2 build 10828683; hook
initialization failure logs an error and falls back instead of failing the host.

Deployment verification uses a temporary external test plugin, not a shipped
dependency. It invokes the real sm_respawn command and checks normal restoration,
capture-style Set/Add changes, same-tick writes, repeated native resets, convar
off/on, pending-work cancellation, and round-end/reset transitions.
On 2026-09-30 all 19 automated live state checks passed. Additional Badwater
capture-output, armed reload, normal-restoration, and 2Fort fallback checks passed.
