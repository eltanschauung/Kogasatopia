# Hat slots

`slot` accepts a single name or a comma-separated list:

```text
"slot" "Hat,Halo"
```

The hat reserves both slots. Selecting it unequips every selected hat sharing
either slot; selecting a conflicting single-slot hat removes the whole multi-slot
hat. The conflict message identifies the shared slot. Disabling a hat releases
all of its slots. Missing/empty lists retain the `default` slot.

Names are trimmed, case-insensitive, and deduplicated at configuration load.
There are at most eight distinct slots per hat, each up to 63 bytes; invalid
overlong lists/names are logged and the hat is rejected rather than silently
losing slot restrictions. No parsing occurs in wearable refresh paths.

The SourceMod menu lists a multi-slot hat in each of its slot categories.
Existing cookie IDs and persistence remain unchanged. Restored conflicting
selections use the existing first-configured-hat-wins normalization policy,
with overlap checked across all slots. The web equip path uses the same
selection setter, so it enforces the same restrictions.

Run `bash tools/tests/build_hat_slots_probe.sh` from the repository root to
compile the isolated state/menu probe. It uses fake clients, wearables and
menus; loading the probe does not change real players' selections or cookies.
