# Instant Sprays 1.3.5

Select a different spray in TF2's Options, then use the normal spray key. Your
new image appears locally using the texture already on your PC. The server
uploads it in the background, then replaces the temporary local display with a
normal player spray and delivers that placement to the other recipients.
Existing spray cooldowns and temp-entity moderation hooks still apply.

There is no reconnect or client plugin. A new selection may need a small preview
model and material (normally about 2.5 KB total, more for complex clipped shapes); the image itself does not need to upload before
you see it. Other players receive a previously unseen image after its normal
upload finishes. Switching back to a selection already cached in this connection
does not upload it again.

## Install

Requires TF2, SourceMod 1.12 and Metamod:Source 1.12. Copy the supplied `tf/` tree
into the server. A first installation can be loaded with `sm plugins load instant_sprays`;
replacing an already loaded native extension requires a safe extension reload or restart.
Native builds target Windows x86 and Linux
x86/x64; SourceMod selects the extension for the server architecture. Clients
need only ordinary TF2 and permitted spray uploads/downloads.

- Keep `sv_allowupload 1` and `sv_allowdownload 1` enabled.
- `sm_instant_sprays_enabled 1` enables the plugin. Its generated configuration
  is `tf/cfg/sourcemod/instant_sprays.cfg`.
- Players can use `!refreshspray` after replacing an image under the same filename.
- Root admins can use `sm_instant_sprays_status` for transfer diagnostics.

Update the plugin, extension, and `gamedata/instant_sprays.games.txt` together;
1.3.5 requires native API 6.

Client upload/download and spray-visibility preferences are respected. Supported sprays are 2D VTF
7.0–7.5 files up to 512 KiB inside `materials/vgui/logos/`, plus the stock
`materials/decals/spraylogo.vtf`. Invalid or unavailable uploads keep the previous
spray. A subsequent spray-key press retries a failed selection. The ordinary
decal event remains subject to other spray-control plugins.

## Implementation

The SourcePawn plugin observes the selected spray and checks it again on the
spray key. The native extension uses normal Source file transfers, isolates and
validates uploads, and publishes immutable CRC-named customization files through
the player's spray fields in `userinfo`. Active uploads get a progress-based
timeout; they are never restarted by repeated spray presses. Server-side file
delivery uses TF2's normal packet scheduling and file priority. The extension
does not force extra packets or promote file transfers over gameplay traffic.
Before publishing a new CRC, the extension delivers its renderer texture into
`materials/temp/` and waits for that file to finish. Linux uses the engine's
`CNetChan::IsFileInWaitingList` symbol; other platforms retain the conservative
whole-channel fallback until a matching queue query is supplied. Preview models,
renderer textures, customization DATs, and shared meshes are checked separately,
so another player's queued files do not delay a completed spray. Continuing file
progress extends a stalled-delivery deadline within a 180-second hard limit.
This prevents the stock
PlayerLogo proxy from retaining a missing-texture lookup. Four reserved VTF
padding bytes provide a stable new cache identity; image pixels, dimensions,
animation frames, and texture flags are unchanged. Clients may also request the
ordinary customization DAT, so first use can transfer both copies.

An owner-only preview, bounded to 64×64 units, temporarily displays the selected
local texture with animation. Brush collision planes clip its mesh to the
supporting surface, preserving UV coordinates rather than stretching the image.
Overlapping coplanar faces are combined without double blending. It replaces
the user's previous spray and is removed when the ordinary spray takes over.
The compiled idle pose preserves the surface alignment from the first frame.
Unsupported, non-brush, sky, nodraw and no-decal surfaces do not get a floating
preview. This planar preview does not bend around corners or conform
to displacement terrain; TF2's final decal remains responsible for those cases.
For upright world walls with displacement terrain below them, 1.3.1 keeps the
clipped surface instead of replaying the native decal, avoiding the stock
renderer projecting an extra image onto that terrain. After synchronization,
the same entity uses the uploaded, unchanged texture and is shown to the
original recipients once its small model/material files have arrived. Client
spray visibility/download settings and one-spray replacement still apply.
Native temp-entity hooks preserve moderation vetoes before
creating a preview; delayed placements pass through those hooks again.
Per-viewer moderation re-sends in the same frame are combined into one accepted
audience. Connection serials prevent a replacement player inheriting visibility.
The optional `instant_sprays_optional.inc` API lets spray tools read the current
published CRC (or the original image CRC for persistent mutes), receive image-change
notifications, and veto preview/clipped-model visibility per viewer. Kogasa's
Spray Tracer and Resizable Sprays integrations use these hooks. Failed shared
model transfers have a 60-second bound so one stalled viewer cannot hold up
everyone else. Owner preview models also have distinct connection identities.

Only server components are installed. Filesystem detours resolve their targets
through public SDK interfaces, without signature scans or changes to engine files
on disk. Background compression threads bypass the upload policy and SourceHook;
only the game thread can route an incoming spray into isolated storage. This fixes
the v1.3.3 crash in parallel outgoing file compression. The prepared-texture CRC
namespace is refreshed to avoid reusing missing-texture entries from failed transfers.
Cached spray files use TF2's normal
`tf/download/user_custom/` directory; preview assets are stored under
`tf/download/materials/instant_sprays/v7/` and `tf/download/models/instant_sprays/v7/`.
Unique preview models are capped at 192 per map and 128 per client connection;
ordinary full-square placements reuse the same image model.
Prepared model assets are also cached in memory for the map, avoiding repeated
temporary file writes on subsequent placements. Spray work taking over 20 ms
is logged, limited to one entry per operation per five seconds, for diagnosing
stalls without continuous profiling.
Temporary uploads are cleaned automatically. Cropped dimensions such as 1020×1024
are supported within the same VTF size and data-validation limits.

Windows runtime checks cover local previews, complete background transfers,
cached selections, unchanged sprays, same-filename refreshes, and invalid uploads.
The filesystem hook bridge also has a concurrent I/O regression with separate
upload identities. Full multiplayer spray visibility still needs in-game testing
on the destination server after the v1.3.4 crash fix and v1.3.5 per-file wait fix.
