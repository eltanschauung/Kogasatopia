# Respawn Modes

`dgm_halve_respawn_waves` defaults to `0`; server.cfg enables it with `1`.
It changes how DGM's reduced-respawn state works, not the existing
population/setup/admin policies which select that state.

- Normal state: `respawn_time 30`; TF2's original wave calculation is unchanged.
- Reduced state, compatible map: halve TF2's final wave length, after its native
  population scaling and minimum interval. No DGM forced-respawn timers run.
- Unsupported map or unavailable native hooks: retain the legacy timer fallback.
- Mode disabled: stop scaling and retain the legacy implementation.

The `respawn_time` value is a policy selector in native mode, not an actual
death-to-spawn delay. `sm_st` reports the effective native interval and the
unmodified normal interval for each team. A team setting of `-1` is valid:
TF2 resolves its own default, so Harvest works before its first capture.

## Engine Ownership

A post-detour on `CTFGameRules::GetRespawnWaveMaxLength(int, bool)` multiplies
positive return values by 0.5. Both scaled wave scheduling and the unscaled
minimum wait use this function. TF2's separate death/freezecam delay is preserved.
For example, a default unscaled wave of 10 becomes 5; a population-scaled interval
of 5 becomes 2.5, rather than being stuck at the stock five-second floor.
The wait still varies with the player's death time relative to the team wave.

TF2's player resource computes and networks `m_flNextRespawnTime` using the same
server calculation, so the spectator countdown agrees with native spawning.
No fake HUD countdown, player death-time rewrite, or plugin respawn timer is needed.

Map inputs and original team settings are never modified. Captures, same-tick
Set/Add inputs and native round resets therefore retain normal Valve semantics.
Set/Add observation coalesces pending wave rescheduling to the next frame.
Toggling modes proportionally adjusts the remaining queued team wave so an
old full-length interval cannot remain queued in reduced mode. Mode-off and
unload restore normal calculation without reconstructing map baselines.

Arena, MvM, Robot Destruction, per-player respawn override maps and small-format
gamemodes remain excluded. Normal PvP maps do not need explicit Set inputs.
Initialization failure logs an error and uses the existing fallback.
Signatures were verified against the installed Linux TF2 build 10828683.

New maps reset the policy selector to normal before their configs apply;
late plugin reloads preserve the current map's selected mode.
Population and setup policies may subsequently select reduced respawns.
Setup changes are temporary: setup end restores the configured map policy,
then applies population rules if enabled. Internal toggles do not overwrite
the cached map setting; admin changes remain authoritative for that map.

## Validation

Validated on the installed TF2 server using an uncommitted bot-only probe:

- Harvest: 13 state checks, including unset defaults, Set/Add inputs, round
  resets, mode toggles and restoring normal waves; no failures.
- Harvest before capture: native spawning with raw team settings still `-1`.
  At eight players per team, HUD predicted 14.144 seconds and spawn took
  14.174 seconds, including the unchanged 6.4-second camera sequence.
- Manjuu: raw team settings remained 6/6; HUD predicted 9.954 seconds and
  spawn took 9.974 seconds at low population.
- Badwater: setup selected reduced waves and setup end restored configured
  `respawn_time 30`; capture inputs and normal/reduced toggles retained
  the map's native wave values.
- Harvest to Badwater: map configs restored the payload policy to 30.

Five to ten seconds describes the wave portion for a normal unscaled wave
of ten, not the full death-to-spawn delay. Map-specific waves and population
scaling still apply, and the full death/freezecam sequence is not shortened.

Engine reference: [wave scheduling and minimum spawn wait](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/teamplayroundbased_gamerules.cpp),
[networked player respawn times](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_player_resource.cpp).
