# Persistent class-limit immunity

`!climmune <name/substring>` (`sm_climmune`) toggles persistent class-limit
immunity, requiring the same generic-admin permission and online targeting
semantics as `sm_immune`. It is a separate SteamID64-backed privilege, stored in
`classlimits_immunity` using the existing WhaleScramble immunity connection and
database configuration. `!immune` continues to affect autobalance only.

Explicit class-limit immunity is independent of `restrict_immunity` and bypasses
normal class caps, low-population Heavy/Medic bans, per-client configured class
bans, joinclass interception, and periodic population enforcement. Existing
top-scorer/admin immunity still does not bypass absolute population/client bans.
Immune players still count as members of their chosen class. Other features
(overheal rules, autobalance, scramble, etc.) are unaffected.

All enforcement uses the preloaded in-memory SteamID64 cache; it performs no SQL
queries. Writes are asynchronous, applied to the cache only after success, and
serialized per SteamID. Cached grants remain effective during temporary outages;
commands remain unavailable until the database has loaded. A connection-generation
counter rejects stale callbacks; threaded Database handles are clones and must not
be compared numerically with the original connection handle.

## Regression probe

Compile `tools/tests/classlimits/climmune_probe.sp` with the repository scripting
directory and live include directory on the include path. Load the probe only in
MGE from `plugins/disabled`, never on production. It uses an explicitly separate
local SQLite database (`climmune_regression_fixture`) with a synthetic identity,
not `databases.cfg`, and stubs targeting/chat/authentication rather than touching
real clients. It clears only its fixture table on each run.

The probe checks admin registration, grant/removal, reload persistence, concurrent
toggle rejection, failed-write handling, stale-generation handling, retaining cached
grants during outages, and excluding bots/disconnected/unauthenticated clients.
Expected output: `[ClassImmunityProbe] PASS checks=20`. One synthetic failed-write
error is intercepted by the test stub, not written to the production error log.
Unload and retire the probe binary after the test.

Before live reload, compile `whalescramble.sp`, inspect the complete diff, and
verify the persistent-immunity guards precede restriction handling in
`ClassLimits_JoinClass`, `IsClientClassRestricted`, `EnforceClassPopulationLimits`,
and `IsClassAvailableForClient`. Reload only on MGE. Calling `sm_climmune` without
arguments must print usage; targeting a deliberately nonexistent name confirms
the persistent cache is ready without granting/removing anyone's immunity.
