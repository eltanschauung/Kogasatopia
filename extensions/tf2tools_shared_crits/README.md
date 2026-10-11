# Shared TF2Tools critical-hit hooks

Stable SourceMod TF2Tools derivative, based on **1.12.0.7255** / commit
`03865e00cc124221122ae9798ad38998566f9a2b`. Version reported by the extension:
`1.12.0.7255-sharedcrits1`. Runtime changes are confined to TF2Tools; do not
replace SourceMod core or other extensions with outputs of this source build.

## Ownership and safety

Upstream installs two instance hooks for every weapon and removes them when
that weapon dies. Inventory regeneration repeats this SourceHook work for every
weapon. This derivative installs the same two critical-hit callbacks once per
distinct **game-server-owned vtable**, keeping them until the critical-hit
forward is disabled or TF2Tools unloads. It retains no weapon entity pointers.
The original critical calculation and SourcePawn forward semantics are unchanged.

The lifetime policy checks the image owning the vtable against the server DLL
image. Heap/private vtables and third-party module vtables keep the upstream
per-entity lifetime. Partial shared-hook installation rolls back both hook IDs
before falling back. Cleanup disables callbacks first, removes shared hooks by
SourceHook ID, and clears the cache. Game-server image lifetime—not entity
lifetime—is the invariant that makes sharing safe across maps.

`sm_tf2tools_crit_hooks` reports enabled state, shared tables/hooks and private
fallback entities. It does not disclose player identities or loadouts.

Weapons separately gates its DHooks swing/deploy hooks by custom attributes;
this package does not change DHooks or introduce another extension.

## Reproducible bounded build

Prerequisites: Git, AMBuild 2, Clang, 32-bit compiler/runtime development files,
Python 3, and a local SourceMod source cache containing the pinned base commit.
Submodules are initialized to their upstream-pinned revisions. The new build
directory must not exist. Nothing is installed automatically.

Tested dependencies:

- HL2SDK TF2 `42ab8953ee32ebeb1348485cb77bc98c81ed09b7`.
- Metamod parser-backport fork `10952328de32065685c72611afcd60e9c415c586`.
- Clang 19; optimized Linux x86 build, compatible with the current TF2 server.

```bash
bash build.sh /path/to/sourcemod-cache /path/to/hl2sdk-root \
  /path/to/metamod-source /path/to/new-private-build-directory
```

The four overlay files preserve upstream attribution and license headers.
`build_tf2tools_only.py` restricts AMBuild's damaged graph to TF2Tools and its
dependencies, uses one compiler job, and refuses compilation with less than
512 MiB available memory. The build intentionally uses a normal clone rather
than a linked worktree because this stable release's Versioning helper expects
`.git` to be a directory. Its shallow revision count does not reproduce the
official build number; the derivative identifies its pinned upstream base
explicitly in `GetExtensionVerString()`.

Standalone lifetime-policy test (Linux; both x86 and x64 were tested):

```bash
c++ -std=c++17 -Wall -Wextra -Werror \
  -Ioverlay/extensions/tf2 tests/shared_vtable_lifetime_test.cpp -ldl -o /tmp/shared-vtable-test
/tmp/shared-vtable-test
# Add -m32 to compile the same policy test for TF2's x86 architecture.
```

## Installation / rollback

Keep a verified backup of the installed stable
`addons/sourcemod/extensions/game.tf2.ext.2.tf2.so`. Stop the server and its
autorestart wrapper, atomically install the tested derivative, and restart.
Do not hot-unload TF2Tools underneath plugins using its forwards. Check
`sm exts list`, `sm_tf2tools_crit_hooks`, ordinary critical-hit behavior and the
SourceMod error log. Rollback follows the same stopped-server procedure with
the saved official stable binary. No gamedata or configuration changes are needed.

SourceMod's GPL and engine-linking exception are included in
`SOURCEMOD-LICENSE.txt`; retained upstream file headers state their authorship.
