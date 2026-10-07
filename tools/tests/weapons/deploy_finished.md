# Deploy-finished sound

```text
"attributes_custom"
{
    "custom deploy finished sound" "tools/ifm/beep.wav"
}
```

Paths are relative to `sound/`. Playback uses the existing custom deploy
sound emission/precaching and cloaked-Spy policy. Finished sounds have their
own 1.5-second per-client/per-slot cooldown, independent of start sounds.

A successful virtual Deploy post-hook arms a weapon EntRef. Its first normal
ItemPostFrame consumes that transition only if the owner is alive and this
is still the active weapon. Switches, transfers, destruction, death,
disconnect, map/config reset and shutdown clear pending state.

## Crash containment and architectural correction

The original temporary-hook design removed ItemPostFrame hooks at completion
or cancellation. A synchronous self-removal probe crashed MGE; deferring
completion cleanup fixed that probe, but a subsequent main-server crash had
no core/minidump or Weapons SourceMod exception. Therefore its exact native
fault is unconfirmed; runtime hook churn remains the leading regression risk.

The corrected design never removes a frame hook during runtime reconciliation.
It installs one hook per weapon lifetime on first successful deploy, caches
the ID, and reuses it. Completion/cancellation only clear state; inactive
callbacks do a bounds check and pending-client lookup and return immediately.
There are no timer polls, deferred cleanup actions, or per-frame entity scans.
Entity destruction clears the cache through the existing destruction forward;
DHooks owns physical hook removal at destruction/plugin unload.

Linux 32/64-bit virtual offsets are verified for TF2 build 11087207:
Deploy 268, ItemPostFrame 279, including knife overrides. Windows is unverified.

## Tests

```sh
bash tools/tests/weapons/build_deploy_finished_probe.sh \
  /home/kogasa/hlserver/tf2/tf/addons/sourcemod/scripting \
  /tmp/deploy_finished_probe.smx \
  /tmp/deploy_finished_engine_probe.smx
```

`sm_deploy_finished_probe`: 29 checks, no failures. Extracted production
state/cooldown functions use simulated clients/entities/audio. Includes
one-shot delivery, cancellation, invalid/recycled refs, transfers/redeploy,
destruction/cache reset, independent cooldowns, slots, clients and cloak.

`sm_deploy_finished_engine_probe`: 19 checks, no failures; 200 synthetic
successful Deploy transitions on ownerless pistol/knife entities, with 400
real virtual ItemPostFrame calls. A pre-hook safely substitutes a successful
Deploy return without touching a player's inventory. The Deploy post-hook
installs/reuses the real production lifetime frame hook, verifying nested
hook setup, no physical removal during repeated deployment, and destruction
callbacks. The actual production cancellation runs inside the executing hook
to regress the original trampoline-lifetime failure. Wait for its asynchronous
summary before unloading.

These probes emit no audio and are not a human gameplay/listening test.

See [the crash investigation](deploy_finished_crash.md) for native reproduction,
the 10,100-transition stress test and the limits of historical attribution.
