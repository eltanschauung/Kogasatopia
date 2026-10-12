# RTD firework-only mode

`sm_rtd2_firework_only` defaults to `1`; `0` restores full RTD. The mode is
latched at map start so delayed non-Firework effects are not abandoned mid-roll.

Firework-only maps have no RTD game-event, usercmd, critical-hit, condition,
homing/frame, sound, voice, resupply, damage or GetMaxHealth hooks. `sm_firework`
retains payment/target confirmation, recipient cooldowns, launch/explosion,
sound and particles. Its one-second cooldown HUD timer exists only while a
cooldown is active. The RTD2 library remains registered for compatibility, but
random/gifted/forced rolls cannot bypass the mode through its APIs.

Full RTD's automatic forwards live in `rtd/full_events.sp`, compiled as
`plugins/disabled/rtd_full_events.smx`. RTD loads/unloads this implementation
detail only for full-RTD maps. Do not install it in the automatic plugins root.
Map teardown blocks callbacks before freeing state; load confirmation uses a
short one-shot timer because console-buffer plugin commands can be deferred.

## Compile / regression checks

Compile `rtd.sp`, `rtd/full_events.sp`, `votemenu.sp`, and `filters.sp` with the
stable server compiler and repository include directory. Install the bridge
only under `plugins/disabled` and the other binaries under `plugins`.

Run `verify_forwards.py rtd.smx rtd_full_events.smx` to inspect the actual
compiled public tables: the six automatic full-RTD forwards must be absent
from RTD itself and present in the optional bridge.

`rtd_full_events_probe.sp` is an isolated fake core. It never changes any real
player's input, weapon, conditions or critical-hit result. Compile a test copy
of the bridge as `plugins/disabled/rtd_full_events_probe_bridge.smx`, load the
probe on empty MGE, then run `sm_rtd_bridge_probe`. Expected: 9 checks, 0
failures, including array/reference copy-back and actual helper unload. Unload
and retire both test binaries afterward; do not load production RTD for this
test, because it defines the same private bridge-binding native.

`policy_probe.sp` includes the real Votemenu loader and Filters client-state
helper without starting Votemenu's commands/database/hooks. With `free_rtd`
disabled in the live config, expected: 16 checks, 0 failures (one unoccupied
client slot is needed). It checks invalid client death prefixes, config bools,
and exclusion of the vote ID and bare alias.

After next-map activation, verify `sm_firework` payment/cooldowns and effects;
`sm_rtd` should report disabled, and `rtd_full_events.smx` should not be loaded.
Verify Filters' normal/spectator/dead chat and hidden slash commands remain
unchanged. No production plugin reload or map change is required for these
isolated regression probes.
