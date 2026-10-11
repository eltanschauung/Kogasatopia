# Melee-kill announcer integration

Add a flat command pool alongside the other sections in announcers.cfg:

```text
"melee_kill"
{
    "your_saysound_command" ""
}
```

The command must already exist in saysounds.cfg. Paid announcer ownership,
disabled packs, SaySounds opt-outs, synchronized selection and Oblivion
visibility use the existing airshot announcer playback pipeline.
There is no fallback sound when this section is absent or empty.

Weapons publishes `Weapons_OnMeleeKill(attacker, victim, weapon)` once from its
existing player_death handler. It reuses the strict same-tick damage weapon;
there is no active-weapon fallback, additional SDKHook, detour, timer or
per-frame/per-damage tracking. The event must be an enemy kill, not a feigned
death, and have TF2's DMG_MELEE flag plus an actual melee-slot weapon.
TF2 aliases DMG_MELEE to DMG_BLAST_SURFACE. DMG_CLUB alone is not sufficient,
because Sandman and Wrap Assassin projectiles also use DMG_CLUB.

Valve references:

- [DoMeleeDamage](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weaponbase_melee.cpp)
- [TF2 damage aliases](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_shareddefs.h)
- [Bat projectile damage](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_bat.h)

Build the regression probe with:

```sh
bash tools/tests/weapons/build_melee_kill_probe.sh
```

Load the probe temporarily on a TF2 test server, run
`sm_melee_kill_probe`, then unload it. Expected: 34 checks, 0 failures.
It extracts production classification, config-parser and routing functions,
substituting engine/audio operations. The consumer callback is renamed so it
cannot receive live Weapons events; its private test forward never reaches the
real announcer plugin. No game events are dispatched or player/audio state
changed. It covers ordinary/critical swings, backstabs, feigns, projectiles,
explosions, afterburn, invalid entities, teams, config parsing and airshot
compatibility. The existing announcer-sync probe separately exercises paid
pack selection and opt-outs.
