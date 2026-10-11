# Inventory stress laboratory — Kogasatopia-Debug only

Nothing here is an ordinary production plugin. The harness is opt-in and has
no startup stress loop. Keep generated profiles, real identifiers, cookies,
perf files, server console captures and logs out of Git. Artifact directories
and fixtures must be private (0700 directories / 0600 files).

## Test architecture

* `export_loadouts.php` reads the latest ten finalized non-MGE match logs and
  matches their players to the existing read-only clientprefs database. It
  selects sixteen compatible saved profiles, reusing available profiles only
  if there are fewer than sixteen. Fixtures contain anonymous profile numbers,
  validated custom item UIDs and stable hat IDs/paint choices, not identities.
  Class selection uses the source player's most-shot class with a saved custom
  loadout. Weapon choices for every class are retained for class-cycling trials.
* `loadout_stress.sp` creates **sixteen TF2 bots**, evenly across teams, with
  `noquota` and unique names. SourceTV/replay are never test players. Bots are
  frozen for the initial inventory experiment; weapons are switched through
  the normal server `use` command. Persistent cookies and real players are
  never modified. Normal entitlement, whitelist and class compatibility checks
  remain in place, so some saved purchases may not equip on bots.
* `WeaponsDebug_*` targets only ordinary bots. The native test API applies hats
  in memory and optionally forces custom equipment recreation at regeneration.
  No backend-update loadout flags are used. Existing user changes to gameplay
  are preserved in the debugging snapshot; they are not promoted to main.
* Weapons diagnostics span ManageRegularWeapons, full GiveNamedItem, weapon/
  wearable validation and GiveTo, PostInventoryApplication, model precaching,
  custom item attributes, model updates, entity hook attachment and hat refresh.
  Nested span IDs, parents and completed-child time distinguish the inclusive
  engine/hooks path from the measured SourcePawn children. Unmeasured remainder
  includes other plugins, engine work, dispatch and measurement overhead.
* The existing native whitelist/loadout extension additionally measures engine
  GetLoadoutItem, policy, custom resolution and its SourcePawn callback. It
  retains bounded numeric aggregates and never logs or allocates on that hot
  path. This debug-only collection is enabled with CheckLag profiling mode 2.
* An independent Profiler frame clock in the harness records gaps in **all**
  CheckLag modes. Its bounded frame ring is written only after the trial. Native
  aggregate samples are written once per second. This permits equivalent mode
  0/1/2 comparisons even when CheckLag itself is disabled.

## Bounds and cleanup

Trials refuse more than one human, stop if an additional human connects, reject
pre-existing test bot names, and verify all sixteen bots were created. Duration
is 15..300 seconds; operations are capped at 10,000; each timer processes at
most sixteen bots. Stop below 160 free edicts, on missing bots, on map change,
or on unload. Only bot serials created by the harness are kicked. The previous
`nb_stop` value is restored. Trials refuse to overwrite their output.
No unconditional `tf_bot_kick all`, cookie writes or production database cleanup.

These are fake-client TF2 bots, **not sixteen networked human clients**. This
tests inventory, callbacks, entity/model creation, snapshot contents and TF2
server processing, not sixteen client downloads or real Steam inventory replies.
The original stock Steam-selected weapons cannot be recreated from custom
loadout cookies alone. A bot reproduction can narrow an origin but a clean bot
test does not rule out network-only stalls.

## Build / stage

Compile `weapons.sp`, `checklag.sp` and `tools/debug/loadout_stress.sp` with the
installed stable SourceMod compiler, using this branch's includes before the
live include fallback. Build `extensions/whitelist_policy/src/build.sh` serially
with `SM_SDK` pointing at the existing SDK. Keep outputs outside the worktree.
Run the existing whitelist/cache and CheckLag parser unit suites before staging.
Save verified copies of live Weapons, CheckLag, native extension and affected
gamedata outside the repository. Deploy the matched plugin/extension build
together, then **restart**; never hot-swap an inline-hook owner during a test.

Prepare `data/loadout-stress` mode 0700, install the generated profiles as
`data/kogasatopia_debug_profiles.cfg` mode 0600. SourceMod requires this fixture
only when an explicit trial command is issued. Do not commit generated data.

## Commands and equivalent comparisons

Use `console.py` for literal console lines; it rejects control characters.

```
sm_checklag_mode 2
sm_loadoutstress_batch 1
sm_loadoutstress_force 0
sm_loadoutstress_class_cycle 0
sm_loadoutstress_start sig_on_mode2_staggered 60
sm_lagself
sm_loadoutstress_stop
```

Use new labels for every trial. Test the same map, profiles, batch, class cycle,
duration, native build and snapshot cvars with sigsegv on/off. Move only its
verified autoload marker and binaries into a private recoverable backup while
the server is stopped; restart and verify that the extension is absent.
Restore exactly those files for sig-on trials. Leave the fork repository alone.
Repeat in reverse order if comparing cold/warm model caches. Compare CheckLag
modes 0, 1 and 2, first staggered, then batch 16 with forced custom recreation.
Keep `sv_parallel_sendsnapshot` identical in all sig comparisons.

Use `summarize.py` on finished trial files. Independent observed rate and frame
counts are not the same statistic as PluginStats' smoothed tickrate. High batch
sizes can intentionally create lag without reproducing the original bug. Mark
that distinction in the results. Do not declare a culprit merely because an
inclusive parent is the largest scope in a five-second window.

Native sampling should be limited to one server main thread, 49–99 Hz, short
duration and 8-KiB DWARF stacks. No perf recording of every CPU/thread, no
systemwide tracing or unbounded symbol downloads. Use the installed compat
decoder for the 32-bit TF2 process. Preserve private captures outside Git and
publish only symbol/timing aggregates. If data is insufficient, add a finer
stage, build, commit, restart and repeat the same workload.

Finally remove the lab plugin and private fixture from active paths, restore
the original Weapons/native build, restore sigsegv's original enabled state,
and install main's lightweight CheckLag self-diagnostics. Verify the server is
running, no test bots remain, and normal plugin/extension load states are intact.
