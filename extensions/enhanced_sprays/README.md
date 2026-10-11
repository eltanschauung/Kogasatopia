# enhanced_sprays

One TF2 SourceMod plugin and one native extension, authored by **Hombre and
Dragon**, replacing Instant Sprays, Resizable Sprays, Spray Tracer and the Late
Downloads dependency used by resizing. Version 1.0.0; native API 8.

## Current status: not deployed

This change is repository-only. Do not install or retire live components until
the server owner approves the rollout. Compiles and offline tests do not replace
an in-game acceptance test.

## Features and ownership

- `enhanced_sprays/switching.sp`: mid-game spray selection, `!refreshspray`,
  safe upload routing, owner-local previews, acknowledged normal-decal handoff,
  clipped brush surfaces and per-viewer moderation.
- `enhanced_sprays/resizing.sp`: `!spray [scale]`, `!bspray [scale] [player]`,
  `!sprayinfo`, the existing `rspr_adminoverride` permissions and shared rolling
  limit of three spray commands per five seconds.
- `enhanced_sprays/moderation.sp`: existing trace/admin menus, spray removal,
  `!mutesprays`, `!spraymute`, `!sprayunmute`, `!sprayban` and `!sprayunban`.
  The existing database tables, seven-day bans/mutes, original-image hashes,
  playtime gate, cookies and translations are retained.
- `enhanced_sprays.ext`: the only transport/filesystem/metadata owner. Uses the
  existing connection and file queue, not extra forced `Transmit()` calls.
  Compression workers bypass SourcePawn: only the installing game thread can
  enter upload-routing policy, retaining the parallel-compression crash fix.
  Unsupported x86 call/pop PIC prologues are rejected before hook activation.

All decal rendering paths consult the same spray-visibility policy. Resized
decals update the same tracing state and use the same spray-sound mute preference.
Mutes/bans are rechecked before resized placement; already-rendered unkeyed
Entity/BSP decals retain the old plugin's limitation: they cannot be selectively
erased by the player-decal clear API and expire with the client's decal/map state.
Spray Tracer's upstream code/credits are retained in its module; Resizable Sprays
is based on sappykun's work. SafetyHook is built from SourceMod's submodule and
its license is included. No Late Downloads source or runtime dependency remains.

## Reduced work

Resizing no longer owns `OnFileSend`, searches all owners for every download,
rereads VTF headers in SourcePawn, polls signon files on a repeating client
timer, or creates a repeating timer for every pending decal. Native metadata is
validated/cached once per CRC. A bounded per-connection asset ledger coalesces
identical file requests, runs inside the existing native frame scheduler and
notifies the plugin after completion/failure. Textures arrive before VMTs; the
material is precached only after its original eligible audience finishes.

Background preference queries default to every five seconds instead of 0.75;
deliberate spray presses and `!refreshspray` still query immediately. This removes
about 85% of the background queries, not 85% of total spray CPU cost. There is
still one lightweight switching poll, the tracing HUD refresh and necessary
native packet/filesystem hooks. No live performance improvement is claimed yet.

Pending placements are capped at 256, map decal materials at 512, metadata at
4096 CRCs/map, and delivery jobs at 512 files/client. Timeout is bounded to 1–60
seconds (`rspr_spraytimeout 0` now means 60, not an unbounded wait). Completion
uses the existing per-file TF2 queue signature, with whole-channel reliable-data
fallback if unavailable; it is not a client renderer acknowledgement.
Client serials and entity refs prevent reconnect/index recycling. Disconnects,
spray changes and map transitions cancel obsolete placements. Late joiners are
not sent resized materials already globally precached before they joined,
preserving the previous protection against cached missing materials.

## Configuration and API

Existing `sm_instant_sprays_enabled`, all `rspr_*` controls and `sm_spray_*`
moderation controls remain. The old `instant_sprays.cfg`, `resizablesprays.cfg`
and `plugin.spraytrace.cfg` are executed so existing settings survive activation.
`enhanced_sprays.cfg` contains the consolidated controls; avoid contradictory
duplicate settings there. `sm_enhanced_sprays_query_interval` defaults to 5
(allowed 0.75–30). Diagnostic command `sm_enhanced_sprays_status` retains
`sm_instant_sprays_status` as an alias.

The required controller include is `include/enhanced_sprays.inc`; optional
moderation consumers use `enhanced_sprays_optional.inc`. Public natives/forwards
are `ESprays_*`; API 8 adds validated texture metadata, immutable resize-material
preparation and coalesced asset deliveries. Requests are restricted to generated
spray VMTs/CRC textures, not arbitrary server files. Legacy `ISprays_*` consumers
must migrate; original includes/gamedata are archived, not auto-loaded.

## Future rollout (requires approval)

1. Build the plugin and the correct architecture extension as in `BUILD.txt`.
2. At a maintenance stop, move the three old live SMXs plus Instant Sprays/Late
   Downloads extension binaries and any autoload files to a recoverable backup.
   Audit other plugins for `latedl` dependencies before retiring it.
3. Install only `enhanced_sprays.smx`, the architecture-appropriate
   `enhanced_sprays.ext.2.tf2.so`, `enhanced_sprays.games.txt`, and new includes.
   Keep existing `spraytrace.phrases.txt`, DB state and client cookies.
4. Cold-start the server so hook ownership never overlaps. Both plugin and
   extension refuse legacy controllers; nothing automatically unloads them.
5. Test normal spray, switch to a new image without reconnecting, refresh a
   same-name file, resized/BSP sprays, animated and non-square images, muted/
   banned viewers, sound mute, admin menus, reconnects, map change and timeouts.
   Check errors and retain the old artifacts for rollback.

Retired plugin sources are under `archive/sourcemod_plugins/disabled/`; the old
extension source/includes/gamedata are under
`archive/sourcemod_extensions/disabled/instant-sprays/`. Runtime spray caches,
logs, database credentials, translations and server binaries are not removed by
this repository migration.
