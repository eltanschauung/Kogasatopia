# Building crit damage

Weapons 7.4.0 / weapons_ext 2.2.1 uses one native detour on
`CBaseObject::OnTakeDamage(const CTakeDamageInfo&)`. It publishes the dedicated
`Weapons_OnBuildingTakeDamage` forward only for these exact classnames:

- `obj_sentrygun`
- `obj_dispenser`
- `obj_teleporter` (both modes)

The SourcePawn policy in `weapons/building_crit_damage.sp` uses the existing
`CritType` field: normal `1.0`, mini `1.35`, full `3.0`. Nonpositive damage and
unknown classifications remain unchanged. Before that forward, the native
service invokes the game's `CTFGameRules::ApplyOnDamageModifyRules()` with the
actual building victim and a disposable copy of the incoming damage record.
It retains **only the resulting crit field**, not the damage, force basis,
base/max damage, flags, bonus, attribution or any other scratch output. Thus
Banner, Crit-a-Cola, reflected projectiles, critical damage flags and weapon
crit attributes are classified by TF2, not a SourcePawn condition heuristic.

This is necessary because genuine rocket damage arrives with `CRIT_NONE` even
when the shot is boosted. The earlier 2.2.0 implementation only multiplied
explicitly populated crit fields; tests supplying known types missed that bug.

The rule function may perform its own engine bookkeeping; it is not a pure
predicate. A non-player victim avoids its player-victim branches. No scratch
damage result or player range variance is committed to the building record.

Only the damage float is writable in the new forward. All attribution, vectors,
custom damage and flags retain their original values; crit is the effective
classification produced by the engine. The caller's crit field is untouched.
The pre-existing player pre/post/rules forwards and their flag semantics are
unchanged. The scratch pointer is marked with a reentrant, thread-local RAII
scope (record + victim identity) so the rules detour does not publish it as
`Weapons_OnTakeDamageModifyRules`. This suppresses only that exact record:
nested, unrelated player damage remains eligible for its normal forward.
The hook uses the same checked, 104-byte x86 `DamageInfo` layout,
now in `src/services/damage_info.h`.

The engine receives a stack-local copy, never a modified caller-owned record.
Reusing a splash record for another building therefore cannot multiply it
again. Nested damage has separate stack-local state. There is one multiplier
owner (Weapons), one base-function hook, no per-entity hook churn, polling or
per-frame work. The rules signature is bound once and SDKTools' shared interface
provides the current GameRules object per hit, rather than caching a map-owned
pointer. If no building listeners exist, the classifier is not run. Other
listeners must not reapply the crit policy.

The original method still runs, retaining team checks, building attributes,
construction handling, plasma resistance and destruction/events. Derived
sentry modifiers run before the base-method hook and remain intact too.

## Validation

Run `bash extensions/weapons_ext/tests/run.sh` for native regression tests.
The production `WithBuildingDamage` helper is tested for exact class scope,
caller immutability, unchanged non-damage fields, flags independent of crit,
multiple targets sharing one record, and reentrant calls (1,092 checks). New
cases poison every scratch byte to prove that only crit survives; they also
check nested suppression-scope restoration and 90/121.5/270 outcomes.

`tests/building_damage_probe.sp` is restricted to an empty, LAN `itemtest`
fixture with no production configuration/database/cookies. It includes the
actual production SourcePawn callback, rather than a second multiplier policy.
Compile with both the repo scripting and include directories. The console-only
command is `sm_building_damage_probe`.

The fixture allocates a zeroed 104-byte test record with SourceScramble and
supplies explicitly known crit classifications. It calls the real virtual
`OnTakeDamage` through SDKTools, exercising sentry-specific handling and the
new native base detour. This is intentionally not a live admin damage native.

The updated synthetic suite contains 477 checks covering:

- 20 damage becoming 20 / 27 / 60 for every building/mode;
- engine promotion of flag-only incoming None/Mini records to Full;
- policy-disabled baseline, zero damage and unknown classifications;
- native damage-vs-buildings attributes and stock plasma resistance;
- construction state and Wrangler shield resistance;
- one callback per hit, unchanged caller records and reused splash inputs;
- player exclusion and retained hurt/destruction events.

Wrangler's stock `0.33` reduction gives floating input `19.8` for a 60-damage
hit. Since building HUD health is rounded up, the normal/mini/full integer
losses are 19 / 26 / 59, not values based on an exact one-third shield factor.
The tests check the incoming floating value as well as the displayed HP delta.

`tests/building_projectile_probe.sp` additionally fires real stock Soldier
rockets through `CTFWeaponBaseGun::PrimaryAttack()` in the empty fixture. Its
test-only signature lives in `tests/building-projectile-test.txt`; never deploy
that gamedata or test plugin to production. It allocates no fake DamageInfo and
never assigns a crit type to an input record. Per-entity DHooks pre/post
observers verify that the actual engine record starts with `CRIT_NONE` and is
not mutated by the native copy/classification/multiplier pipeline.

The 72 cases cover sentry/dispenser/teleporter entrance/exit at 96 and 1024
units, with normal, Banner, Kritz, Crit-a-Cola, reflected-projectile state,
promotion/demotion attributes, a stock building modifier, and policy-disabled
baseline. Required outcomes before building-specific modifiers are exactly
90, 121.5 and 270. Near and far ordinary rockets both remain exactly 90. The
current engine's crit-demotion setter behavior is checked as observed, not
inferred from the modified damage. Specifically, Valve's nonzero `SetCritType`
uses the maximum of the old/new values: Kritz plus `crits_become_minicrits`
can calculate mini-crit scratch damage while leaving the final field Full.
This implementation copies that final field as specified; it does not change
the engine's setter globally or infer classification from scratch damage.
Inventory changes during the fixture's
initial round regeneration invalidate and retry a shot, rather than treating
a vanished launcher/boost as a crit-classification failure.

The existing services probe covers 49 checks including player damage,
attributes, weapons and hats. Repeat all suites after `changelevel itemtest`
to validate GameRules lifetime. This patch requires the new native extension
and a process restart; the existing 7.4.0 production SMX/crit policy is unchanged.
Do not hot-unload weapons_ext under its consumers.

Source references: Valve's
[building damage path](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_obj.cpp)
and [sentry damage path](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_obj_sentrygun.cpp).
