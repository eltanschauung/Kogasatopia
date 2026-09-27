# Custom hat class variants

Hats remain in `configs/custom_hats.cfg`. Existing hats and their public API
continue working without changes.

## Class overrides

The existing `scout`, `soldier`, `pyro`, `demoman`, `heavy`, `engineer`,
`medic`, `sniper`, and `spy` sections can override `model`, `body`, and a
nested `particle` section, in addition to their existing defindex settings.
Unspecified values inherit the hat's top-level values. `body` is the model's
encoded `m_nBody` value, not a bodygroup index; leaving it absent preserves
native body selection. Procuration's `class_fit` bodygroup has base 1, so its
nine class variants use body values 0 through 8.

```text
"model" "models/example/shared.mdl"
"scout"
{
    "model" "models/example/scout.mdl"
    "body" "0"
    "particle"
    {
        "effect" "example_scout"
        "attachment" "halo_scout"
    }
}
```

Model, particle effect, PCF, and attachment paths may contain `{class}`.
This resolves to TF2 class names, with `demo` for Demoman in asset templates.
The config section remains `demoman` (`demo` is also accepted for asset overrides).
Every allowed class's resolved model and effect is precached and validated.
A missing attachment prevents that emitter from being created and logs an error.

`particle/owner_camera_control_point` optionally assigns the wearer to a
numbered particle control point. Procuration uses CP1 to suppress its effect
when the wearer is the first-person camera; third-person/taunt cameras remain
controlled by the PCF. Zero/absent means no extra control point.

Emitters belong to the equipped wearable, not a separately polling plugin.
Class changes rebuild mismatched variants through post-inventory handling.
Death, unequip, wearable removal, map end and unload remove the emitter.
Cloak/disguise suppress and remove emitters; they return when visibility is
restored. Emitters use the shared Hat Removal preferences.

## Procuration installation

The example entry is in `configs/examples/procuration_hat.cfg`.
The supplied PCF is `particles/procuration_v4.pcf`; its actual effects are
`procuration_native_v4_<class>`, not `procuration_v4` or the PCF root name.
The model has nine `halo_<class>` attachments and nine class body variants.
The supplied reference implementation ("Procuration Halo Smoke", Codex,
GPL-3.0-or-later) provided the attachment and owner-camera control-point layout.

Install the model, all model companions, materials and PCF under the server's
`tf/`, publish raw and bzip2 copies to FastDL, and add them to
`precachefiles.cfg`. The plugin loads custom PCFs through its existing map
manifest pipeline. Packed map manifests still take priority over loose ones.

For reliable local client loading, install the PCF and particle materials in
`tf/custom/kogasa_particles/` and append
`"file" "!particles/procuration_v4.pcf"` inside its
`particles/particles_manifest.txt`, preserving stock entries and other custom
PCFs. Restart TF2 to load an updated global particle manifest.
FastDL downloads alone do not guarantee custom PCF initialization on clients.
