# Deploy-finished crash investigation (2026-10-06)

## What is proven

The initial synchronous self-removal design has a native use-after-unmap:

1. A virtual ItemPostFrame wrapper enters the SourcePawn pre-hook.
2. Cancellation calls DHookRemoveHookID for that executing hook.
3. DHooks deletes its DHooksManager. Its destructor removes the SourceHook
   hook and calls CHookManagerAutoGen::ReleaseHookMan.
4. When the last manager reference is released, the generated executable
   allocation is destroyed/unmapped.
5. The callback returns to an address in that unmapped allocation.

This was reproduced in a private, loopback-only TF2 instance using the installed
SourceMod/DHooks/Metamod binaries. GDB caught munmap for the trampoline page:
the stack includes Metamod, DHooks, and SourcePawn native dispatch. Continuing
then faults on return to the now-unmapped page (SIGSEGV in the controlled run).
The isolated phase log ends at synchronous removal, before ItemPostFrame
returns. No production client or loadout was used.

The relevant implementation is in DHooks natives.cpp (Native_RemoveHookID),
vhook.h (DHooksManager destructor), and Metamod
sourcehook_hookmangen.cpp (CHookManagerAutoGen::ReleaseHookMan).

## Historical main-server crash: evidence boundary

The kernel recorded INT3/SIGTRAP traps for the earlier MGE probe at 21:03:02
and the main server at 21:22:22 (America/New_York, 2026-10-06). Neither
historical incident retained a native core/minidump. There was no matching
Weapons SourceMod exception. The main server's old address-space mapping and
native call stack are unavailable.

The main server had the intermediate design that deferred completion removal,
but still removed hooks synchronously on cancellation. That intermediate
module was tested separately in the lab: 100 batches and 10,100 synthetic
successful Deploy calls, including rapid redeployment, cancellation before
completion, queued removal and entity destruction. It did not reproduce the
main-server fault.

Therefore the original synchronous self-removal bug is confirmed, but the
precise native cause of the later historical main-server crash is NOT
conclusively established. The matching trap category alone is insufficient.
Do not describe the controlled reproduction as a backtrace of that main-server
incident. A definitive attribution would require a native trace from it or a
reproduction of the later failure.

## Corrected architecture and verification

The feature installs ItemPostFrame once per weapon lifetime and reuses it.
Completion, later Deploy, switching, death, disconnect and map/config reset
only clear pending state. There is no DHookRemoveHookID, RequestFrame cleanup,
or timer polling in the production module. DHooks owns physical teardown at
entity destruction/plugin unload. The existing entity-destruction forward
clears the per-entity hook cache and pending client state.

A first normal ItemPostFrame still consumes exactly one successful Deploy
transition after owner, EntRef, alive and active-weapon validation. Sound
playback and its independent 1.5-second per-client/per-slot cooldown remain.

Verification of the corrected build:

- Production-code simulated probe: 29 checks, zero failures.
- Native ABI/lifecycle probe: 19 checks, zero failures, 200 synthetic successful
  Deploy transitions and 400 real virtual ItemPostFrame calls. It now executes
  the actual production cancellation function inside its executing native
  frame hook, the previously unsafe boundary.
- Full production lifetime module in the isolated GDB lab: 100 batches,
  10,100 synthetic Deploy calls, one-shot emission assertions, cancellation,
  queued entity destruction and reuse; normal exit code 0, no native fault.
- Clean staged-source snapshot and full working checkout compile successfully.
  Staging contains only this feature; unrelated in-progress changes are kept.
- Both live server processes were left running. No live reload/restart was
  performed during this investigation/deployment.

Raw debugger output, private lab logs and backup binaries are intentionally
outside the repository. The unsafe reproduction plugin is not distributed.
