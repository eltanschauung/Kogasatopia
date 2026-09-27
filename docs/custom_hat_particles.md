# Custom hat particles

The hats module accepts a nested `particle` block independently of weapon
attributes and keeps `custom_hats.cfg` separate:

```text
"tsurugi_halo"
{
    "name" "Tsurugi Halo"
    "model" "models/player/bluearchive/tsurugi_halo.mdl"
    "particle"
    {
        "effect" "ba_tsurugi_blood"
        "pcf" "particles/ba_tsurugi_blood.pcf"
    }
    "slot" "Halo"
    "chat_color" "darkred"
    "prefix" "JUSTICE"
}
```

The PCF must declare the exact effect name. The current validator supports
binary-2 PCFs (the supplied Tsurugi file's format); unsupported encodings are
reported rather than silently registering a nonexistent effect.
Omit `pcf` for an already precached stock particle.

If the MDL embeds this effect in its `Particles` model keyvalues, TF2 owns the
effect's attachment and visibility. Tsurugi already embeds
`ba_tsurugi_blood` at `halo_fx`, so no duplicate emitter is created.
Otherwise, the module creates a parented `info_particle_system`; an optional
`attachment` key selects a named attachment on the wearable. These emitters
are removed with the hat, on death, disconnect, map cleanup and plugin unload.

## Loading and publishing

PrecacheGeneric and ParticleEffectNames do not teach a client about an unknown
PCF. TF2 loads definitions through `maps/<map-basename>_particles.txt`.
The module preserves the existing loose manifest, appends enabled hats' PCFs,
downloads it and loads it server-side through the verified
`ParseParticleEffectsMap` SDKCall. Effect names are registered separately.

Valve gives manifests embedded in BSPs priority over loose manifests:
`particles.txt` in BSP, then the map-named manifest in BSP, then the loose
map-named manifest. **Particle hats cannot be enabled on those maps merely by
publishing a loose manifest.** They require merging the PCF into the packed
manifest and distributing a properly versioned map. The plugin and publisher
report these maps; neither overwrites/repackages installed BSPs.

The publisher installs archive models/materials/PCFs, optionally relocates a
replacement model and fixes its MDL header name, publishes raw and bzip2 copies,
verifies decompression, and sets relevant FastDL paths to 777.
It does NOT install the archive's global `particles_manifest.txt` or replace
the stock Gibus.

```sh
python3 -m venv ~/.venvs/hat-particles
~/.venvs/hat-particles/bin/pip install srctools
~/.venvs/hat-particles/bin/python tools/install_particle_hat.py \
    ~/ba_tsurugi_halo.zip \
    --tf-root ~/hlserver/tf2/tf --fastdl /var/www/fastdl/tf2 \
    --model-source models/player/items/all_class/ghostly_gibus_scout \
    --model-target models/player/bluearchive/tsurugi_halo \
    --pcf particles/ba_tsurugi_blood.pcf --effect ba_tsurugi_blood
```

Run publishing again when adding maps or PCFs; include all required custom PCFs
with additional `--pcf` arguments. Add the model, sidecars, materials and PCFs
to `precachefiles.cfg`. The module precaches the model and downloads the PCF
and current map manifest itself. Clients must reconnect/load a map after
deployment: plugin reload cannot retroactively load PCFs into connected clients.

## Verification

```sh
~/.venvs/hat-particles/bin/python -m unittest discover -s tools/tests -p 'test_*.py'
```

`tools/tests/particle_hat_probe.sp` is a temporary server-side integration
probe. Compile/load it only for a test, then unload it and remove its SMX.
It loads the published pl_vigil_rc10 manifest without changing maps, checks
the effect definition and MDL attachment, verifies registration and download
entries, and checks emitter creation/removal. It does not verify client rendering.

In a real TF2 client on a supported map, verify download completion, halo_fx
alignment, a single blood effect, RED/BLU appearance, death/respawn and
equip/unequip cleanup. Also verify a clean client without a local mod.

References:
- [Valve map PCF loading](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/particle_parse.cpp)
- [Valve model particle attachment lifecycle](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/c_baseanimating.cpp)

