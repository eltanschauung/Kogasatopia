# weapons_ext

One Linux x86 SourceMod extension owns TF2Items, the stable TF2Tools derivative,
Conch No Speed, Scattergun Pellets, TF2 Spread Patterns, TF2 Whitelist Policy and
TF2 Sentry NewTarget Distance. There are no legacy binary aliases or shim
extensions. Consumers must be rebuilt with the updated includes.

## Architecture and overhead

- One extension interface, SourceMod SDK bootstrap, Metamod identity and native
  owner, instead of seven. One CDetour/SafetyHook/Zydis runtime is linked once.
- One player-manager listener dispatches the relevant lifecycle callbacks to
  the component state. Conditions remain demand-driven inside TF2Tools.
- Concheror hooks bypass irrelevant conditions immediately. Relevant conditions
  resolve exact player-shared pointers through a fixed, allocation-free cache,
  replacing a scan of every connected client. Disconnect retires entries before
  an index or player object can be reused; late startup seeds existing clients.
- Pellet completion visits only deduplicated pending attacker/victim pairs,
  replacing the per-frame max-clients squared scan. Idle frames scan no pairs.
  The fixed FIFO has no heap allocations. Each frame consumes its starting batch;
  reentrant hit events survive for the next frame. Kill events consume the shot
  first, so a later frame does not emit a second non-kill completion.
- TraceAttack uses one hook per server-owned player vtable, rather than adding
  a vtable-wide callback for every connected client. Shared hooks survive client
  disconnects/maps and are removed by hook ID on shutdown; private/unloadable
  vtables retain per-entity hooks. The existing pellet deduplication stays as a
  defensive check. `sm_weapons_ext_status` reports shared trace-table ownership.
- Native item generation uses a direct entity-reference conversion. Both pre
  and post hooks attach for existing clients during late load, and the unified
  whitelist module supplies validated stock-view vtables before native creation.
- The existing transaction-scoped native custom-loadout/whitelist cache and
  engine-image-owned shared critical-hit vtable hooks are retained.
- Econ layout/sendprop and inventory instruction guards fail closed after an
  incompatible TF2 update. Component startup failure unwinds in reverse order.
  Standalone files or resident standalone images cause startup rejection before
  this extension attaches component hooks. A full restart is required.

Reducing the extension count alone is not a measured tickrate improvement. The
hot-path changes above reduce work structurally; in-engine A/B timings and
ordinary human inventory/hat validation remain necessary before production use.

## API and migration

Use `#include <weapons_ext>`. Individual feature declarations retain their
descriptive `TF2_*`, `TF2Items_*`, `TF2Spread_*`, etc. names; there is only one
extension dependency and one registered extension library, `weapons_ext`.
The canonical includes are in `tf/addons/sourcemod/scripting/include` in the
Kogasatopia repository. The TF2 core include is intentionally overridden too;
indirect consumers such as `tf2_stocks` must not retain `game.tf2.ext` metadata.
SourceMod package upgrades must preserve/reapply this repository's includes.
The dependency's file key is `weapons_ext.ext`, matching `weapons_ext.autoload`.
SourceMod resolves the engine suffix itself. An explicit `.2.tf2` dependency
creates a second owner for the same DSO and invalidates handle identities.

All existing gamedata filenames are retained to preserve their updater/ABI
ownership. This is not a compatibility extension. TF2Tools reads `sm-tf2.games`
from the installed stable SourceMod package; TF2Items reads `tf2.items.txt`.
The other five feature gamedata files remain in the repository's gamedata tree.
Before creating a demand-driven TF2Tools detour, its own config is explicitly
selected in the shared CDetour manager.

Build every active consumer identified by `tests/smx_dependencies.py`, including
WhaleTracker and Nativevotes. Stale compiled consumers are not supported.
`build_consumers.py` stages these builds and verifies their extension metadata;
it does not install, change settings or reload anything.

When migration is authorized, stop both server processes and their restart
wrappers. Back up verified binaries/includes first, retire the original seven
extension binaries and TF2Items autoload marker, and install
`weapons_ext.ext.2.tf2.so` with `weapons_ext.autoload`. Install all rebuilt
consumers and updated includes together. Do not hot-unload or hot-load this
bundle under production plugins. The missing optional `game.tf2.ext` automatic
entry in SourceMod's extension list is expected; no legacy module should load.
For five third-party binaries whose exact source/includes are unavailable,
`build_consumers.py --relink-unbuildable` can replace their single legacy
extension dependency in a new staging copy. `tests/relink_smx.py` preserves and
verifies the bytecode and native table, rejects legacy library-detection logic,
and does not overwrite the original. This is metadata migration, not a runtime
compatibility layer. All in-house consumers are recompiled instead.
Validate `sm exts list`, `sm_weapons_ext_status`, `sm_tf2tools_crit_hooks`, native
loadout status, weapons, hats, conditions, pellet forwards and sentry range.
Rollback uses a stopped-server restoration of the complete original set.

## Build and checks

The extension imports TF2Items' current x86 econ layout. x64 and Windows are
deliberately rejected rather than advertised without an ABI implementation.
Build dependencies are local; nothing is automatically downloaded or installed.

```sh
mkdir /path/to/private-build
cd /path/to/private-build
CC=clang CXX=clang++ python3 /path/to/weapons_ext/src/configure.py \
  --sm-path=/path/to/sourcemod-1.12-sdk \
  --mms-path=/path/to/metamod-source \
  --hl2sdk-root=/path/to/hl2sdk-root \
  --hl2sdk-manifest-path=/path/to/hl2sdk-manifests \
  -s tf2 --targets=x86 --enable-optimize
python3 /path/to/weapons_ext/build.py /path/to/private-build
bash /path/to/weapons_ext/tests/run.sh
```

The serial, low-priority build is limited to 1 GiB address space per compiler
process and requires at least 384 MiB available memory before starting. It never
deploys. The build output is under `weapons_ext.ext.2.tf2/linux-x86/`.

Tests cover all 4,096 valid pellet pairs, deduplication, FIFO wraparound,
reentrancy, hash collisions, disconnection and client reuse, plus the existing
576 whitelist checks, 284 transaction/loadout-cache checks and shared-vtable
lifetime tests. `tests/runtime_probe.sp` is a console-only, isolated-server
probe, not a permanent production plugin. Never point tests at production DBs.

The expanded probe checks weapon/wearable creation with exactly one generation
forward, condition behavior, spread/pellet/sentry API bindings, native econ-view
identity, nested inventory caching/invalidation/deleted-entity handling, and
exactly one shared-critical callback. It passed 32 checks in the isolated x86
server on 2026-10-13. This is native API validation, not a full production
Weapons/custom-hats visual test or a measured A/B performance improvement.

## Provenance and license

- TF2Tools: AlliedModders SourceMod stable 1.12.0.7255,
  `03865e00cc124221122ae9798ad38998566f9a2b`, with Kogasatopia's tested shared-crits
  overlay. Original AlliedModders attribution and linking exception remain.
- TF2Items: [Asher Baker/asherkin and AzuiSleet](https://github.com/asherkin/TF2Items),
  `e3508121c09f0d2a3d7721ce109d7727f32bd078`. Original headers/attribution remain.
- Other components: Kogasatopia sources as of `07da40f`, by Hombre and the
  authors credited in the original files. Whitelist work was inspired by
  Sappykun's whitelist enabler plugin.

The new integration code is GPL-3.0-or-later. Included upstream sources retain
their own license notices. SafetyHook, Zydis and SDK libraries are taken from the
pinned, locally initialized SDK, not copied into this directory.
