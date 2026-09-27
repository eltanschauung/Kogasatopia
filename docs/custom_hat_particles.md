# Custom hat particles

Hats keep their own `custom_hats.cfg` and per-class particle configuration.
Tsurugi and Procuration now load from the immutable bundle
`particles/kogasa_particles_r01.pcf` (51 effect definitions, including children).
The names of the effects, attachment points and class variants are unchanged.

```text
"particle"
{
    "effect" "ba_tsurugi_blood"
    "pcf" "particles/kogasa_particles_r01.pcf"
}
```

Procuration uses `procuration_native_v4_{class}`, `halo_{class}`, and
`owner_camera_control_point "1"`; its body/class configuration is unchanged.
The PCF must declare the exact effect name. The validator supports binary-2 PCFs.
Omit `pcf` for an already precached stock particle.

If an MDL embeds its configured effect, TF2 owns the attachment and visibility.
Tsurugi already embeds `ba_tsurugi_blood` at `halo_fx`; no duplicate emitter
is created. Otherwise hats use a parented `info_particle_system`, cleaned up
on hat removal, death, disconnect, map cleanup and plugin unload.

## Stable revision manifests

Every installed BSP has a published loose
`maps/<physical-bsp-basename>_particles.txt`.
Workshop aliases are normalized: `workshop/koth_brine_rc3a.ugc2965195337`
uses `maps/koth_brine_rc3a_particles.txt`.

Each manifest preserves unrelated map PCFs and reserves these 32 entries:

```text
"particles_manifest"
{
    "file" "!particles/kogasa_particles_r01.pcf"
    // ... one entry for each revision ...
    "file" "!particles/kogasa_particles_r32.pcf"
}
```

Only r01 currently exists. Do NOT create empty placeholders for r02-r32:
clients would cache them and not download their eventual real contents.
Absent revisions are referenced by the manifest, but never put in downloads.
TF2 prints harmless `Particles: Missing ...` warnings for these absent slots;
it still loads the existing revisions. Empty placeholder PCFs are not a fix.
The hats module creates/reserves the current map manifest as needed and
downloads every existing revision, so future revisions need no manifest edits.
The verified `ParseParticleEffectsMap` SDKCall loads the same manifest on
the server; registering ParticleEffectNames alone does not load client PCFs.

Publish new effects to a previously unused revision, keeping published bundles
unchanged. Prefer new, versioned effect names when updating an existing effect,
and point that hat's `pcf` and `effect` at the new revision.
Retain old revisions for existing/cached definitions. Clients need a map load
or reconnect; reloading a server plugin cannot reload PCFs inside clients.

One-time migration: clients with an older downloaded map manifest must remove
that old `tf/download/maps/<map>_particles.txt` so the 32-slot manifest can
download. Future revision additions do not require repeating this step.
Remove the old `tf/custom/kogasa_particles` pack too: its global manifest can
mask testing of the normal server download path. Other maps' unrelated custom
or map-bundled particle files should not be deleted.

```sh
~/.venvs/hat-particles/bin/python tools/publish_particle_revisions.py \
    --tf-root ~/hlserver/tf2/tf --fastdl /var/www/fastdl/tf2 \
    --revision 1 \
    --source ~/hlserver/tf2/tf/particles/ba_tsurugi_blood.pcf \
    --source ~/hlserver/tf2/tf/particles/procuration_v4.pcf
```

Use `--dry-run` for preflight. Future publishes use `--revision 2`, etc.
The publisher validates/round-trips the merged DMX graph, rejects duplicate
effect names and attempts to replace an existing revision, preflights the
64-PCF map limit, verifies raw/bzip2 FastDL copies, and sets those FastDL
files/directories to 777. Run it again after installing maps.
The hats module also reserves/downloads the current map manifest at map load.

Models, materials, textures and r01 remain in `precachefiles.cfg`; reserved
nonexistent PCFs do not. Legacy standalone PCFs are retained server-side as
source assets but no longer advertised in the download config or manifests.

## Packed BSP limitation

Valve loads `particles.txt` embedded in the BSP first, then the map-named
manifest embedded in the BSP, and only then the loose map-named manifest.
Thus **a loose manifest cannot enable these effects on a map containing a
packed particle manifest**. This includes koth_brine_rc3a.

The publisher reports such maps and leaves BSPs untouched. The hats module
logs a **cache-dependent fallback**, still validates the PCF and exact effect
name, registers valid names, and allows their wearable emitters to spawn.
This only renders for clients whose particle definitions are already loaded
from a compatible map or local mod. Merely downloading/caching the PCF file
does not load its definitions on a blocked map. Missing/invalid PCFs and absent
effect names remain rejected; packed manifests are never rewritten or replaced.
The initial inventory found 112 affected BSPs out of 425 installed BSPs
(419 distinct loose manifest basenames). Compatible maps do not require a
client `tf/custom/kogasa_particles` pack. Supporting the blocked maps without
a client pack would require separately named, properly distributed map copies
with merged embedded manifests.

No global `particles_manifest.txt` or client custom pack is installed by
this server-side scheme.

## Verification

```sh
~/.venvs/hat-particles/bin/python -m unittest discover -s tools/tests \
    -p 'test_*particle*.py'
```

Tests cover revision naming, workshop normalization, idempotent manifests,
native PCF preservation, the 64-entry limit, child/material references,
duplicate effects, compression and permissions. The temporary integration
probe `tools/tests/particle_hat_probe.sp` verifies server parsing, particle
registration and wearable emitter lifecycle; unload/remove it after testing.

A real clean TF2 client still must verify downloads and actual rendering
on a compatible map: one correctly aligned effect, class variants, RED/BLU,
and death/respawn/equip cleanup. Server tests cannot verify client rendering.

References:
- [Valve per-map PCF loading and BSP precedence](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/particle_parse.cpp)
- [Valve model particle lifecycle](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/c_baseanimating.cpp)

