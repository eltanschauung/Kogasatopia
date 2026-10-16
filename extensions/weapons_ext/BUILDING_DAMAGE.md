# Building crit damage

Weapons 7.4.0 / weapons_ext 2.2.0 adds one native detour on
`CBaseObject::OnTakeDamage(const CTakeDamageInfo&)`. It publishes the dedicated
`Weapons_OnBuildingTakeDamage` forward only for these exact classnames:

- `obj_sentrygun`
- `obj_dispenser`
- `obj_teleporter` (both modes)

The SourcePawn policy in `weapons/building_crit_damage.sp` uses the existing
`CritType` field: normal `1.0`, mini `1.35`, full `3.0`. Nonpositive damage and
unknown classifications remain unchanged. Damage-type flags are deliberately
not used to infer or upgrade classification: an incoming `CritType_None` with
`DMG_CRIT` remains normal. This does not synthesize crit classification from
attacker conditions or re-run player game rules on buildings.

Only the damage float is writable in the new forward. All attribution, vectors,
custom damage, flags and crit classification retain their original values.
The pre-existing player pre/post/rules forwards and their flag semantics are
unchanged. The new hook uses the same checked, 104-byte x86 `DamageInfo` layout,
now in `src/services/damage_info.h`.

The engine receives a stack-local copy, never a modified caller-owned record.
Reusing a splash record for another building therefore cannot multiply it
again. Nested damage has separate stack-local state. There is one multiplier
owner (Weapons), one base-function hook, no per-entity hook churn, polling or
per-frame work. Other listeners must not reapply the crit policy.

The original method still runs, retaining team checks, building attributes,
construction handling, plasma resistance and destruction/events. Derived
sentry modifiers run before the base-method hook and remain intact too.

## Validation

Run `bash extensions/weapons_ext/tests/run.sh` for native regression tests.
The production `WithBuildingDamage` helper is tested for exact class scope,
caller immutability, unchanged non-damage fields, flags independent of crit,
multiple targets sharing one record, and reentrant calls (1,062 checks).

`tests/building_damage_probe.sp` is restricted to an empty, LAN `itemtest`
fixture with no production configuration/database/cookies. It includes the
actual production SourcePawn callback, rather than a second multiplier policy.
Compile with both the repo scripting and include directories. The console-only
command is `sm_building_damage_probe`.

The fixture allocates a zeroed 104-byte test record with SourceScramble and
supplies explicitly known crit classifications. It calls the real virtual
`OnTakeDamage` through SDKTools, exercising sentry-specific handling and the
new native base detour. This is intentionally not a live admin damage native.

On 2026-10-16, the isolated x86 engine passed 477 checks covering:

- 20 damage becoming 20 / 27 / 60 for every building/mode;
- mini-crits with/without DMG_CRIT, full crits without it, and flag-only normal hits;
- policy-disabled baseline, zero damage and unknown classifications;
- native damage-vs-buildings attributes and stock plasma resistance;
- construction state and Wrangler shield resistance;
- one callback per hit, unchanged caller records and reused splash inputs;
- player exclusion and retained hurt/destruction events.

Wrangler's stock `0.33` reduction gives floating input `19.8` for a 60-damage
hit. Since building HUD health is rounded up, the normal/mini/full integer
losses are 19 / 26 / 59, not values based on an exact one-third shield factor.
The tests check the incoming floating value as well as the displayed HP delta.

The existing services probe also passed 49 checks, including player damage,
attributes, weapons and hats. Activation requires the new Weapons SMX, native
extension and consolidated `weapons.games.txt` together, followed by a process
restart; do not hot-unload weapons_ext under its consumers.

Source references: Valve's
[building damage path](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_obj.cpp)
and [sentry damage path](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_obj_sentrygun.cpp).
