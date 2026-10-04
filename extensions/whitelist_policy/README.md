# TF2 Whitelist Policy

Native extension and SourcePawn companion by **Hombre**.
Inspired by Sappykun's whitelist enabler plugin (the previous
`enablewhitelist.sp`, later embedded in Weapons).
GPL-3.0-or-later; the SourceMod SDK retains its own linking exception.

## Ownership and behavior

Weapons remains the sole owner of its GetLoadoutItem detour. Its post hook calls
one native policy evaluator. There is no extra inventory/loadout detour and no
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

Only a boolean combo decision is cached inside a paired
ManageRegularWeapons inventory transaction. No CEconItemView pointer is retained.
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

Use a server restart for the initial migration: the old plugin changed convar
flags, and old code/detours may still be loaded in another server process.

Commands:

- sm_whitelist_reload: root-admin reload after editing the whitelist or schema.
- sm_whitelist_status: readiness, policy generation, lookups, combo scans, denials.

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

Requires g++ and multilib development libraries for x86. The build is native-only;
it does not download dependencies or require an HL2SDK/Metamod toolchain.
The deployment build used SourceMod SDK fa56d42535171c3298cdb119fb95502a7076d7cc,
tested against the live SourceMod 1.12.0.7219 Linux x86 runtime.

The unit tests cover combo classifications, normal/other quality exemption,
denial priority, and nested transaction reset. The repository's
tools/tests/weapons/whitelist_policy_probe.sp validates stock view fields and
compares native decisions with raw engine inventory/classification calls.
Its default command is read-only; the server-console-only
`sm_whitelist_probe bot` option creates and immediately removes a disposable
fake client to exercise the native inventory path on an empty test server.
That probe assumes the current live allow-all whitelist. It is not installed
as an active production plugin.

## ABI safety / limitations

Supports Linux x86 and x86-64, not Windows. Function symbols are resolved through
gamedata rather than fixed addresses. The private player inventory offset is
verified against the actual GetLoadoutItem instruction and its call target.
Quality/initialized field offsets come from sendprops, then are validated with
stock item views. Spy's unused primary slot correctly has an invalid stock view.

TF2 updates can change these private bindings. Update gamedata if the guard
fails; never disable it simply to make the extension load. The x86-64 binary
build is provided, but the actual deployment/runtime checks target x86.
This removes the old hot-path convar writes and SourcePawn SDKCall/string work;
it does not eliminate the engine's own inventory-generation costs.
