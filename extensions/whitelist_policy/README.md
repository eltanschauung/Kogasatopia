# TF2 Whitelist Policy

Native extension and SourcePawn companion by **Hombre**.
Inspired by Sappykun's whitelist enabler plugin (the previous
`enablewhitelist.sp`, later embedded in Weapons).
GPL-3.0-or-later; the SourceMod SDK retains its own linking exception.

## Ownership and behavior

The existing extension is now Weapons' sole GetLoadoutItem detour owner. Weapons
binds a cold custom-slot resolver and a denial-notice callback; its old DHooks
GetLoadoutItem pre/post callbacks are removed. Whitelist and custom selection
share this one native path. There is no second extension/loadout detour and no
mp_tournament mutation, flag manipulation, or global tournament-mode override.
The engine still performs its normal inventory generation.

The companion loads mp_tournament_whitelist, preserving Valve's file/default
semantics: missing file means allow-all, while a present file without
unlisted_items_default_to defaults to deny. Malformed replacements retain the
last good policy; a malformed initial policy prevents the companion starting.
Schema names and entity classes are resolved only when rebuilding the policy.
The extension atomically swaps the finished definition table.

For an ordinary denied raw item, normal-quality instances remain exempt and the
engine's stock item view is used. Existing custom-weapon selections can still
override ordinary whitelist stock fallbacks, matching Weapons' previous order.
The raw Demoman wearable + shield + sword/katana combination still denies all
three slots and takes precedence over custom replacements. Optional notices
remain coalesced and session-safe.

The boolean combo decision and resolved custom-slot entity references are cached
inside a paired ManageRegularWeapons inventory transaction. No CEconItemView
pointer is retained. Unselected slots never enter SourcePawn. Selected slots
enter it once per outer transaction, then reuse a serial-checked entity reference.
Removed/recycled entities force resolution again. The deferred blank wearable
placeholder retains the existing engine-deferred deletion behavior; it is not a
persistent native item allocation. Ordinary entities newly marked FL_KILLME are
not reused. Failed resolutions are cached only inside the same transaction.
Outside a transaction, custom permissions are checked on every lookup.

Weapons publishes selection bits on cookies, equip/unequip/native overrides,
connect and map/config load. Entity publication, building-policy changes and
sm_weapons_enable_loadout changes invalidate the native cache. A revision change
during a reentrant resolver discards its result. Client disconnect, plugin
pause/unload and policy rebuild invalidate transactions and cached references;
unload clears callback ownership before script memory can disappear.
Unexpected worker-thread calls pass through the engine without entering
SourcePawn or mutable caches; normal inventory interception is game-thread-only.
The first relevant lookup reads all three raw selected items; subsequent ones
reuse that result. Outside a transaction it is recomputed, avoiding stale
Steam-inventory/loadout decisions. Transactions reset on disconnect, map start,
and policy rebuild. New nested transactions cannot invalidate their parent.

## Installation

Install the matching binary as:

- Linux x86: tf/addons/sourcemod/extensions/whitelist_policy.ext.2.tf2.so
- Linux x86-64: tf/addons/sourcemod/extensions/x64/whitelist_policy.ext.2.tf2.so

Install tf2.whitelist_policy.txt in gamedata and whitelist_policy.inc in
scripting/include. Compile/deploy whitelist_policy.sp and the updated weapons.sp.
Do not leave enablewhitelist.smx active: its old tournament-toggle detours must
not compete with this policy. The old tf2.enablewhitelist gamedata is retired.
Binaries are deployed separately, not tracked in Git.

Use a server restart for migration to 1.1.0. Install the matching extension and
Weapons binary together; never layer the native hook over the old SourcePawn
GetLoadoutItem hook. Do not unload an extension while its engine callback is on
the stack. The old whitelist companion remains a cold configuration loader;
no extra extension or recurring timer is introduced.

Commands:

- sm_whitelist_reload: root-admin reload after editing the whitelist or schema.
- sm_whitelist_status: readiness, policy generation, lookups, combo scans, denials.
- sm_weapons_loadout_status: hook/owner status and native fast-path counters.
- WeaponsLoadout_GetStats: hook bound, owner present, engine lookups, resolver
  callbacks, transaction-cache hits and unselected-slot fast paths (six cells).

The plugin reloads on startup, map start, configs executed, and whitelist-path
changes. There is no file-watch timer. After a mid-map schema/file edit, run
sm_whitelist_reload explicitly. Startup requires the companion. Its later reload
or removal retains the last committed native policy, without disabling Weapons
or bypassing bans. The native extension is a required dependency; invalid engine
bindings fail extension loading.

## Builds and tests

Set SM_SDK to a compatible SourceMod SDK checkout with its amtl/sourcepawn
submodules initialized, then:

```sh
SM_SDK=/path/to/sourcemod TARGET_ARCH=x86 bash src/build.sh
SM_SDK=/path/to/sourcemod TARGET_ARCH=x86_64 bash src/build.sh src/build/x64
bash tests/run.sh
```

Requires g++ and multilib development libraries for x86, plus the pinned SDK's
initialized safetyhook submodule. SafetyHook is linked into this extension,
not installed separately. The build is serial and does not download dependencies
or require an HL2SDK/Metamod toolchain. Run it with nice and a bounded memory limit.
The deployment build used SourceMod SDK fa56d42535171c3298cdb119fb95502a7076d7cc,
tested against the live SourceMod 1.12.0.7219 Linux x86 runtime.

The unit tests cover combo classifications, normal/other quality exemption,
denial priority, and nested transaction reset. The repository's
`tests/loadout_cache_test.cpp` covers transaction-only cache reuse, nested
boundaries, revision changes during callbacks, miss caching and client reuse.
`tests/loadout_probe.sp` provides a bounded console-only A/B benchmark and
regression checks using one disposable fake client on an empty MGE server.
It compares equal SDKCall overhead, nested custom cache reuse, selection changes
and uncached lookups outside inventory transactions. Do not deploy it permanently.

The repository's
tools/tests/weapons/whitelist_policy_probe.sp validates stock view fields and
compares native decisions with raw engine inventory/classification calls.
Its default command is read-only; the server-console-only
`sm_whitelist_probe bot` option creates and immediately removes a disposable
fake client to exercise the native inventory path on an empty test server.
That probe assumes the current live allow-all whitelist. It is not installed
as an active production plugin.

### Bounded x86 MGE validation (2026-10-10)

SourceMod 1.12: 576 policy checks + 284 cache checks passed; the in-engine probe
passed 14 checks including nested transactions, selection removal, uncached
out-of-transaction permissions, placeholder addresses and a real Halo Sniper
custom entity's m_Item address. Three 1,000-call samples per case, including
identical SDKCall overhead, measured:

| Lookup | Prior SourcePawn hook | Unified native hook |
| --- | ---: | ---: |
| Stock slot | 6.639–7.302 µs | 0.635–0.781 µs |
| Warm custom slot in inventory | 8.130–8.538 µs | 0.648–0.785 µs |

The 3,002 custom lookups required one resolver callback and 3,001 native cache
hits. This benchmarks lookup dispatch, not inventory generation/model loading,
and is not evidence that the previously investigated 50–140 ms stalls are fixed.

## ABI safety / limitations

Supports Linux x86 and x86-64, not Windows. Function symbols are resolved through
gamedata rather than fixed addresses. The private player inventory offset is
verified against the actual GetLoadoutItem instruction and its call target.
Quality/initialized field offsets come from sendprops, then are validated with
stock item views. Spy's unused primary slot correctly has an invalid stock view.

TF2 updates can change these private bindings. Update gamedata if the guard
fails; never disable it simply to make the extension load. The x86-64 binary
build is provided, but the actual deployment/runtime checks target x86.
This removes the old hot-path convar writes, SourcePawn SDKCall/string work and
ordinary GetLoadoutItem VM dispatches. Native counters have no clock sampling.
CheckLag still profiles ManageRegularWeapons (engine plus hooks) and cold
custom resolution; the retired SourcePawn GetLoadoutItem pre/post timing spans
are intentionally gone.
it does not eliminate the engine's own inventory-generation costs.
