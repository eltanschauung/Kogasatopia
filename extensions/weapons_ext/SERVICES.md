# Unified Weapons services (2.2)

`weapons_ext` now contains twelve internal modules, behind one extension identity,
one client dispatcher, and one detour runtime. The seven listed SourcePawn
providers are retired, not wrapped:

- `tf2attributes`: native `WeaponsAttrib_*` API, schema definition caches,
  class-level sendprop caches, deduplicated managed strings, safe map/unload cleanup.
- `tf2utils`: native `WeaponsUtil_*` API, native virtual/static engine calls,
  constant-time shared-player lookup, sparse deferred work instead of a
  SourcePawn PreThinkPost hook on every player.
- `tf_ontakedamage`: native `Weapons_OnTakeDamage*` forwards and scoped,
  reentrancy-safe mini-crit event correction. The dedicated
  `Weapons_OnBuildingTakeDamage` forward exposes real crit classification for
  the building-only 1.35x/3x policy; see [BUILDING_DAMAGE.md](BUILDING_DAMAGE.md).
- `fov` and `centerprojectiles`: one native view-policy owner. Weapons keeps
  commands and the existing `fov_override` / `tf2centerprojectiles` cookies.
  Hunting Revolver calls `WeaponsView_SetZoom` directly; it does not rely on
  a separate FOV plugin intercepting a SourcePawn SDKCall.
- `tf_econ_dynamic_compat` and `tf2econdynamic`: the config loader is a Weapons
  module and the engine injector is now a native schema service. Use
  `WeaponsSchemaAttribute` from `weapons_schema.inc`; the old methodmap and
  extension dependency are not exported. Registration directly invalidates the
  native attribute caches, including when the schema tree backing store moves.
  Map reinstallation uses the root's lifecycle dispatch, not another LevelInit
  hook. The October TF2 secondary name-lookup index fix is retained.
  KeyValues remain opaque engine allocations: creation/cloning, access and
  destruction all use resolved server functions, not the incompatible SDK
  KeyValues layout. The empty handle template is cloned from an engine-owned
  definition and cleared by the engine, avoiding a guessed allocation size.
- `tf2_sentry_newtarget_dist`: its existing engine module was already merged;
  its convars and config execution now belong to Weapons.

Commands, cookie keys, attribute config names, FOV limits, and sentry settings
remain meaningful user-facing features, not compatibility shims. Removed
provider library names and old attribute/utilities/damage APIs are not exported.
All active consumers must be rebuilt together. Do not restore the retired
providers beside this extension; the startup guard rejects their active files.

## Boundaries and lifecycle

Target remains **Linux x86 TF2**, not a new 64-bit port. Borrowed attribute
addresses expire on runtime-list mutation, entity deletion, or schema reload.
Schema service insertions automatically invalidate definitions. Call
`WeaponsAttrib_InvalidateDefinitions` only for modifications made outside it.
Missing definitions are never cached. Managed non-networked values are removed
from live lists before freeing, and networked values are left alone.

Native damage actions retain the old semantics: a non-Continue result commits
edits; it does not independently cancel damage. Mini-crit correction exists
only within the current `OnTakeDamage_Alive` call, including nested calls.

FOV limit changes do not invent preferences for clients without cookies. Native
zoom processing preserves smooth sniper/Hunting Revolver transitions and clears
the engine zoom owner after a successful return to the saved FOV. Projectile
preferences reconcile on inventory events and late custom-item initialization;
The Original remains centered when the user's preference is off.

## Validation

- Native tests in `tests/run.sh` remain applicable.
- `tests/services_probe.sp` tests attributes (including pooled-string ABI),
  conditions, ammo/health, wearables, FOV/zoom, centering, and damage callbacks.
- `tests/services_benchmark.sp` exercises **16** isolated clients, **160** weapon
  inventory regenerations, **160** hat applications, and **10,000** lookup triplets.
- Use an isolated server without production databases, cookies or configs.
  Use valid player attackers with player-owned weapons in damage fixtures.
- Run probes again after map changes and check the server's error log.
- `tests/schema_probe.sp` exercises schema handle ownership/cloning, auto/explicit
  IDs, Valve protection, name-index replacement, injected string types, 512
  insertions with warm caches, and reinstallation before plugin OnMapStart.
- `schema_loader_probe.sp` with `schema_fixture.txt` verifies the actual Weapons
  SMC loader on startup and map changes in an isolated test configuration.
- Compile every caller, verify no old provider dependencies/symbols remain,
  stop both shared-tree servers, back up exact files, install atomically, retire
  providers recoverably, restart both screens, and verify plugin/extension status.

Benchmarks measure isolated API/application paths, not a promise about complete
human gameplay FPS. Keep heavyweight diagnostic probes out of production.
