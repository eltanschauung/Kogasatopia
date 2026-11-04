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
overflow rejection, RED/BLU paints, tint copying, renderer initialization,
cache-safe model rebuilding, tracked-weapon binding, and clearing stale paint.

November 3, 2026 (original revision): 28 checks passed on MGE. Weapons and the probe compile without
warnings on SourceMod 1.12.0.7255. All fourteen new energy-sword asset downloads
returned HTTP 200 and their bzip2 payloads matched the supplied pack.

Filters integration is intentionally deferred at the operator's request. The
standalone OnClientSayCommand paint prompt remains, with no Filters edits or
chat-routing native. Standard paint selection uses the normal item menu.
Client-side visual appearance and a real user's cookie reconnect remain manual
in-game checks; server-side tint attributes and serialization are covered here.

## Follow-up: select paint before equip

The revised plugin and probe compile cleanly. Neither was loaded during the
follow-up, at the operator's request; the earlier 28-check result is not a
runtime result for this revision.

The model-only override wearables originally kept `m_bInitialized = 0`.
Valve's `CProxyItemTintColor::OnBind()` checks `CEconItemView::IsValid()` before
reading tint; `IsValid()` returns `m_bInitialized`. The VMT therefore used its
team-colored fallback despite the server attributes being correct. Painted
renderers now become initialized, but keep their undefined definition index and
only iterate their own runtime attributes, so another schema item's model or
attributes cannot replace the custom model.

`CEconItemView::GetModifiedRGBValue()` also caches its first result. Paint changes
now make model validation rebuild the render wearables rather than mutating a
previously drawn item's paint in place. Custom black avoids both the no-paint
value (0) and the legacy team-paint value (1), including existing cookies.

References:
- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/econ/econ_wearable.cpp
- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/econ/econ_item_view.h
- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/econ/econ_item_view.cpp

After activation, manually verify:
1. The weapon list has no separate Paint entry or Paintable suffix.
2. Selecting the sword opens the shared Hats paint list without equipping yet.
3. Back/cancel leaves the original loadout unchanged.
4. Selecting a paint equips normally, with the same paint visible in first and
   third person on RED and BLU. Change paint again without switching weapons.
5. No Paint restores the model's original team colors; black is near-black.
6. Class/loadout/access changes while the menu is open reject stale choices.
7. Resupply, death/respawn, switching weapons, and reconnect retain the selection.
