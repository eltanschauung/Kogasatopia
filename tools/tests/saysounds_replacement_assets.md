# FastDL-only announcer replacements

`PrecacheReplacementSounds()` must not require the server to have a local audio
copy. The replacement paths are used for sound precaching, the downloadables
string table, and client sound emission. No server-side decoder or duration
lookup is used. Ordinary saysounds already follow this model.

Keep the successful `PrecacheSound()` requirement before adding an entry to the
ready arrays, keep group/path ordering, and report failed precaches. This does
not validate the audio itself: clients still need a valid downloadable file.
A local server copy remains useful for non-FastDL download fallback, but it is
not required when clients obtain the asset from FastDL.

## Regression probe

Before running, verify on the host that
`/var/www/fastdl/tf2/sound/unreal/killingspree.mp3` or its `.bz2` exists. The probe
requires that `sound/unreal/killingspree.mp3` is absent from the engine's server
search paths. Change the real integration sample if the server asset layout
changes; do not move/delete production sounds to satisfy the test.

Build with:

```bash
bash tools/tests/build_saysounds_replacement_assets_probe.sh
```

Load the temporary probe SMX on MGE and run
`sm_saysounds_replacement_probe` from its console. The probe extracts and tests
the production loader with mocked precache/download operations, then separately
checks real engine precaching and download-table registration for the existing
FastDL-only MP3. It does not play audio or modify players/entities.

Expected result: `checks=13 failures=0`, printed to the server console and
`addons/sourcemod/data/saysounds-replacement-assets-probe.txt`.

Coverage: no local existence gate, MP3 and WAV readiness, precache failure
rejection/logging, download path prefix, aligned groups and stable ordering,
stale-pool clearing, plus real FastDL-only engine/table checks.

Unload the probe and remove its live SMX and result file afterward. Compilation
and the in-engine probe passed on MGE on 2026-10-22. Audible client playback was
not tested by this probe.
