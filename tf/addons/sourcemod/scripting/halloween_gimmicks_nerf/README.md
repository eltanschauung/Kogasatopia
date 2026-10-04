# Halloween Gimmicks Nerf

Map rules formerly provided by `nerfhalloweengimmicks.sp` (Hombre), now hosted
by `whalescramble.sp`. Existing convar names and
`cfg/sourcemod/nerfhalloweengimmicks.cfg` are retained for compatibility.

WhaleScramble dispatches lifecycle, entity creation, condition addition, and
round events. The module owns its damage and spell-pickup SDKHooks. Spell
removal is independent of Halloween map detection.

Unload the retired `nerfhalloweengimmicks.smx` before loading the merged
WhaleScramble. Do not leave the standalone binary in the active plugin folder.
Hombre is already included in WhaleScramble's author list.

`tools/tests/halloween_gimmicks_nerf_probe.sp` provides an empty-server runtime
probe for spell cleanup, convar changes, and pumpkin condition replacement.
