# TF2 build 11087207 gamedata recovery

Verified against the installed Linux x86 server ELF, not a guessed offset shift.

- Melee crit override: anchor to the exported
  `CTFWeaponBaseMelee::CalcIsAttackCriticalHelper` symbol and patch its
  `JNE +0x0d` at byte offset 17. The old cross-function offset landed inside
  `OnSwingHit`.
- No Thriller taunt: the random-roll branch that adds `IsHalloweenTaunt`
  moved from 0x151b to 0x1559 inside `ModifyOrAppendCriteria`.
- Econ Data: equip regions 968 -> 1004; particle tree 876 -> 912;
  cosmetic/weapon/taunt effect vectors 908/928/948 -> 944/964/984;
  loadout-slot-name vector 1432 -> 1468. Unchanged prefix fields were checked
  separately against their accessors; Windows offsets were not guessed.

The selected TF2 gamedata passed an offline scan of 153 Linux server/engine
signatures and all 12 memory-patch verification patterns.
Core gamedata for other games must be excluded using Game Master and
`#supported` selectors to avoid false failures.

Compile `tf2_econ_gamedata_probe.sp` against the live SourceMod include tree,
load it temporarily, and run `sm_econ_gamedata_probe` from the console.
It does not modify player state or write to the schema.
Reserved unnamed slots and duplicate aliases are valid.
On MGE this confirmed 11 named / 8 reserved slots, the Scout scattergun's
definition and slot, 68 equip regions, and particle-set counts
671 / 406 / 4 / 240 (all / cosmetic / weapon / taunt).
Unload and remove the temporary probe after verification.

Replacing gamedata on disk does not refresh already prepared calls.
Reload Econ Data before loading Weapons, and reload Source Scramble Manager
to recreate its managed taunt patch. Do not unload the Source Scramble extension.
