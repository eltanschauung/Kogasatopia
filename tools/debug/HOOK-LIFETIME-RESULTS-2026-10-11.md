# Weapon and hat hook-lifetime investigation — 2026-10-11

## Changes and evidence

Main production fixes:

- `7af386a`: gate Weapons entity sound/deploy hooks by assigned features.
- `8c3a79b`: shared critical-hit hooks in the existing TF2Tools extension.

Unfeatured weapons no longer receive melee PrimaryAttack or Deploy hooks.
`custom melee swing sound` installs the two swing hooks only on melee-slot
weapons. `custom deploy finished sound` installs Deploy-post plus ItemPostFrame
hooks before deployment. Ordinary deploy and confirmed-hit sounds retain their
existing client-switch/damage paths without acquiring those entity hooks.

Custom-attribute setters, whole-KeyValues replacement, item-ready reconciliation,
active-weapon switching and a startup scan cover assignment after creation.
Installed hooks are retained for an entity generation; attribute removal makes
them inert. EntRefs, cached feature flags and actual active-weapon checks prevent
stale entity reuse. Late assignment can join the original deploy lockout only;
later reload lockouts and unsuccessful same-active-weapon switch attempts do not
re-arm completion. Death, disconnect, switching away and destruction cancel it.

The second bottleneck was TF2Tools' two critical-helper instance hooks being
installed/removed for every created/destroyed weapon. The stable derivative
shares those hooks by game-server-owned vtable, with per-entity fallback for
private/third-party-image vtables. It does not change critical calculations or
forward semantics, nor add another extension. Read its [build/safety notes](../../extensions/tf2tools_shared_crits/README.md).

On the tested full extension stack, `sm_tf2tools_crit_hooks` reported 77 shared
tables / 154 hooks and zero private fallback entities. Map changes, class changes,
ordinary attacks and repeated inventory destruction/recreation were exercised.
The image-lifetime policy unit test passed in both Linux x86 and x64 builds.
Runtime testing and deployment were Linux x86 only.

## Controlled workloads

The existing laboratory replayed 16 anonymous profiles from the preceding ten
matches: 87 valid saved custom weapon selections and 31 custom hats. Two invalid
weapon selections were skipped consistently. Each bot's weapon and hat selections
come from the **same source player's SteamID64**. No human cookies were modified.
Fixtures, identities, private logs and recordings remain outside Git.

All comparisons used `koth_harvest_final`, the same fixture, class cycling,
weapons **and hats enabled**, 25-second measurement windows, idle optimization
disabled for the trial, parallel snapshots at 2, and lightweight CheckLag mode 1.
Batch 1 staggers inventory work. Batch 16 forcibly rebuilds all 16 players'
equipment per timer service and deliberately exceeds ordinary gameplay load.
When equipment can be rebuilt faster, more operations fit in a fixed window;
raw counts of slow frames must not be compared without this throughput context.

The baseline/gating tests ran early morning. Shared-hook tests ran after a later
session restart. To control for that time gap, **the shared build was reversed
to official TF2Tools while retaining the exact final Weapons binary**, followed
by otherwise equivalent afternoon trials. The reverse tests reproduced the
additional cost of per-entity critical hooks.

### Staggered forced rebuilds (249 operations per trial)

| Variant | Observed frame rate | Worst frame | Worst inventory operation | Frames >=60 ms |
| --- | ---: | ---: | ---: | ---: |
| Original Weapons + official TF2Tools, early baseline | 66.873/s | 122.670 ms | 74.556 ms | 40 |
| Gated Weapons + official TF2Tools, afternoon reverse test | 66.926/s | 82.805 ms | 57.580 ms | 5 |
| Gated Weapons + shared TF2Tools | 66.926/s | 52.675 ms | 34.168 ms | 0 |

### Forced batch-16 rebuild storm

| Variant | Observed frame rate | Operations | Worst frame | Worst inventory operation | Frames >=100 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original Weapons + official TF2Tools, early baseline | 26.668/s | 1,584 | 287.173 ms | 82.638 ms | 99 |
| Gated Weapons + official TF2Tools, afternoon reverse test | 40.083/s | 2,384 | 295.710 ms | 75.838 ms | 148 |
| Gated Weapons + shared TF2Tools, first run | 65.485/s | 3,904 | 203.100 ms | 30.180 ms | 15 |
| Gated Weapons + shared TF2Tools, repeat | 66.585/s | 3,968 | 157.361 ms | 24.493 ms | 10 |

The repeated shared run completed about 66% more equipment rebuild operations
than the same-session official-TF2Tools reverse test. Worst operation time fell
from 75.838 to 24.493 ms. This isolates shared critical-hook lifetime as a
meaningful additional improvement after sound-hook gating.

These are bounded laboratory observations, not a guarantee that all gameplay
lag is solved. The intentionally extreme batch-16 storm still produced occasional
long frames. Warmup, model-cache state and other server activity affect peaks.
Cold-transition trials that did not finish before the controller timeout were
stopped safely and **excluded**, not treated as completed performance results.

### Ordinary inventory path

With force disabled and both equipment domains enabled: 249 operations,
66.927 observed frames/s, worst frame 47.525 ms, worst operation 27.603 ms,
no frames >=60 ms. Observed custom-hat coverage was 25–31; forced rebuild runs
maintained all 31. This tests regeneration, class cycling and slot switches
without forcibly recreating every custom item.

## Functional regression probe

`sound_hook_probe.sp` is **debug-only**. Compile it against the Debug Weapons
build and run `sm_soundhookprobe` from the empty-server console. It creates one
owned ordinary bot, temporarily allows bot input, and exits if a human arrives.
It restores its bot convars and removes only its owned bot.

Final result: **25 checks, zero failures**. Coverage includes:

- Stock weapons have no sound/deploy hooks; ranged weapons reject melee hooks.
- Attributes assigned after creation attach the correct pair of hooks.
- Actual melee input emits the custom swing sample and calls the crit forward.
- Twenty repeated assignments retain the same hook IDs.
- Removing an attribute makes retained hooks silent.
- Mid-deploy assignment emits once on the first operational ItemPostFrame,
  not at switch start; pending state is cleared before emission.
- Whole-KeyValues replacement and ready-weapon assignment do not re-arm.
- Rapid switch-away and death cancel completion.
- Class changes invalidate old weapon references and keep critical callbacks
  working on the replacement inventory.

During probe development, assertions initially sampled the old inventory before
TF2's deferred respawn replacement, and bot AI changed class. Those test issues
were corrected by resolving the new inventory after a settling frame and
constraining only the owned test bot. Failed development runs are not presented
as successful regression runs.

No process crash/restart occurred during completed comparative stress runs.
There were no new Weapons/TF2Tools errors in those runs. Pre-existing RTD invalid
timer/handle errors appeared on both original and optimized stacks, and one
recurred after production startup; that unrelated issue was not changed here.

## Production handoff

Both main TF2 and MGE were restarted with production Weapons, production native
loadout policy and lightweight CheckLag, retaining the tested shared TF2Tools
derivative. The two laboratory plugins were moved outside the active plugins
directory. Bot input/class overrides were restored. All 624 preserved config
checksums matched, including admin configuration. No extension hot-unload was
used underneath dependent plugins.

Ordinary **human** Halo Sniper switching and custom-hat equip/unequip validation
has been requested separately. Until that response arrives, bot validation must
not be described as human validation.
