# Weapons gamedata ownership

`tf/addons/sourcemod/gamedata/weapons.games.txt` is the single package-owned
engine-binding file for Weapons and all twelve `weapons_ext` modules. Both
SourcePawn opens `weapons.games`; native callers open `./weapons.games` through
`WEAPONS_GAMECONFIG_NAME`. Both resolve to the same physical file. Feature
definitions and signature/offset names remain unchanged.

The distinct SourceMod cache identities are intentional. Native modules bind
before DHooks registers its `Functions` parser in `SDK_OnAllLoaded`. Reusing
that early cache entry from SourcePawn would omit `Functions` and `MemPatches`,
even though the file contains them. SourcePawn's separate first parse occurs
after its DHooks/SourceScramble dependencies have loaded. Do not normalize away
the native `./` prefix or add load-order-sensitive autoload-marker workarounds.
This costs one extra cold parse, not per-weapon parsing or per-frame work.

## Consolidated inputs

The 2026-10-15 audit checked active SourcePawn callers, deployed SMX config
strings, and the native extension. These seventeen files had no active consumer
outside Weapons / weapons_ext:

- weapons.txt
- weapons.ammo_pickups.txt
- weapons.deploy_finished.txt
- weapons.inventory_diagnostics.txt
- weapons.kunai_nerf.txt
- weapons.schema.txt
- weapons.services.txt
- weapon_overrides.games.txt
- tf2.items.txt
- tf2.attributes.txt
- tf2.utils.nosoop.txt
- tf2.ontakedamage.txt
- tf2.whitelist_policy.txt
- conch_no_speed.games.txt
- scattergun_pellets.games.txt
- tf2_spread_patterns.games.txt
- tf2_sentry_newtarget_dist.games.txt

The items, attributes, and utilities inputs previously existed only in the live
installation; their bindings are now versioned here. Legacy standalone extension
sources are historical, non-deployed references, not supported consumers of the
retired files. Do not restore their binaries or run their old updaters.

`sm-tf2.games` remains separate: SourceMod owns/updates it, TF2Tools consumes it,
and Oblivion also uses it. SDKTools, SDKHooks, econ-data, buildings, and all other
shared/non-Weapons gamedata remain untouched.

## Updating and validating

Edit the consolidated file for Weapons-specific engine changes. Do not copy
upstream files wholesale over it. All original platform values, signature escape
bytes, calling conventions, and ordered address read directives were preserved.
Identical duplicates were deduplicated; conflicting definitions fail validation
rather than silently choosing an input.

The migration helper `tests/gamedata_merge.py` can reconstruct and verify the
merge against a directory containing the seventeen original inputs. Originals
are not retained as parallel production configuration. `tests/gamedata_test.py`
checks parser/merge invariants, the two-cache/one-file contract, and the
consolidated file's structure. Run it through `tests/run.sh`.

`gamedata_runtime_probe.sp` compares the original 17 inputs in a private migration
fixture. `gamedata_contract_probe.sp` needs only the consolidated file and checks
all 26 DHooks definitions and seven patch definitions without enabling any.
Always include a fresh-process test with no legacy configs present: warm-cache
or map-only testing cannot detect the parser-registration hazard above.

Deploy the new config, rebuilt Weapons plugin, and rebuilt native extension as
one package. A full process restart is required for native activation. Remove
the seventeen legacy files only after their active consumers are migrated;
do not hot-unload the extension underneath plugins. Validate extension module
status, plugin startup, weapon/hat inventory regeneration, and a map transition.
