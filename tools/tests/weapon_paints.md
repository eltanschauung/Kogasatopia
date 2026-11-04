# Weapon paint regression probe

Run `bash tools/tests/build_weapon_paints_probe.sh` with the live scripting
directory available (or pass it as argument 1). The default output is
`/tmp/weapon-paints-probe.smx`. Load it only on the test server and unload/remove
it afterward. It creates and removes two temporary econ entities; no player
inventory or saved cookie is modified.

The probe extracts production paint/color/serialization/model-refresh helpers,
then exercises them under SourceMod with the real Weapons attribute service.
Checks cover named and hex colors, malformed input, stock index validation,
custom-color round trips, twenty short entries in a cookie, multi-chunk packing,
overflow rejection, RED/BLU paints, tint copying, an in-place model repaint,
tracked-weapon binding, and clearing stale wearable paint.

November 3, 2026: 28 checks passed on MGE. Weapons and the probe compile without
warnings on SourceMod 1.12.0.7255. All fourteen new energy-sword asset downloads
returned HTTP 200 and their bzip2 payloads matched the supplied pack.

Filters integration is intentionally deferred at the operator's request. The
standalone OnClientSayCommand paint prompt remains, with no Filters edits or
chat-routing native. Standard paint selection uses the normal item menu.
Client-side visual appearance and a real user's cookie reconnect remain manual
in-game checks; server-side tint attributes and serialization are covered here.
