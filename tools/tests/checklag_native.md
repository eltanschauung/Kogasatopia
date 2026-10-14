# CheckLag native sampling and finer inventory stages

This diagnostic pass leaves game behavior unchanged. Native recording runs
outside TF2: no signal handlers, unwinding, ptrace stops, or profiler library
are installed in the server.

## Engine-stage timings

The optional `weapons.inventory_diagnostics` gamedata adds read-only pre/post
detours for:

- `CTFPlayer::ValidateWearables` and `ValidateWeapons`
- `CBaseCombatWeapon::GiveTo`, `CEconWearable::GiveTo`, `CEconEntity::GiveTo`
- `CTFWeaponBase::UpdateExtraWearables`
- `CTFPlayer::PostInventoryApplication`
- `CBaseEntity::PrecacheModel`

They record only inside an existing `ManageRegularWeapons` span, and only with
`sm_weapons_inventory_diagnostics 1`. Timings include nested engine/hooks work.
Do not add inclusive parent and child times together. Unavailable optional
symbols are reported, not made fatal to Weapons.

Additional SourcePawn spans measure entity-create/destroy dispatch, weapon
sound-hook installation, and lazy deploy-finish frame-hook installation.
These identify hook churn that previously fell into the inventory remainder.

Compile `tools/tests/weapons/inventory_stages_probe.sp` and run
`sm_inventory_stages_probe engine` only in an isolated TF2 test instance with
the private lab marker and no humans. It exercises depth limits, nesting,
disabled/outside-inventory cases, all eight bindings, and inventory
regeneration for Scout/Engineer/Spy/Pyro. The successful engine run produced
86 checks, zero failures. The separate CheckLag probe produced 45 checks,
zero failures; neither creates real lag incidents.

## Bounded external recorder

`tools/checklag_native.py record` uses system perf on the verified TF2 main
thread, at at most 99 Hz, with 8192-byte DWARF user-stack samples. Root is
required under the current kernel perf policy; the tool never changes sysctls.

The output must be a new dedicated, empty, recorder-owned mode-0700 directory.
Its files are mode 0600. Raw DWARF samples include arbitrary stack memory:
treat the entire output as sensitive, never publish or commit it. Log parsing
retains only an explicit allowlist of CheckLag numeric/scope fields, not chat,
client names, addresses, or the original log lines.

Ten-second independent captures avoid unreliable signal-based perf rotation.
There are small sampling gaps between segments. Sealed files are immutable;
alert directories hardlink them before rolling retention unlinks older names.
The recorder retains at most six sealed rolling segments plus the active
segment, and ten alert archives,
stops at 384 MiB of unique capture files, and expires after at most 24 hours.
Pending alerts are archived only after a segment covering their observation
has sealed. TF2 process exit or PID reuse stops recording; it does not
automatically follow a new server process.

Deploy the tested script as a root-owned helper before privileged execution.
Example, substituting the explicitly verified main-thread PID and fresh output
directory:

```sh
sudo systemd-run --unit=checklag-native \
  --property=RuntimeMaxSec=86400 --property=MemoryMax=160M \
  --property=CPUQuota=10% --property=Nice=10 \
  --property=IOSchedulingClass=idle \
  /usr/bin/python3 /usr/local/libexec/checklag-native.py record \
  --pid VERIFIED_PID --log-dir /home/kogasa/hlserver/tf2/tf/addons/sourcemod/logs \
  --output FRESH_PRIVATE_DIRECTORY --hours 24
```

Stop with `sudo systemctl stop checklag-native.service`. Only the recorder's
perf child receives its shutdown signal; TF2 is never signalled.

The recorder observes automatic v3 CheckLag log events. New CheckLag emits
`snapshot_kind=manual|automatic`; manual snapshots are ignored. Older v3
alerts without that key remain compatible. Existing database events are not
changed or backfilled.

## Symbol-only reports and limits

Use a decoder matching the sampled process architecture. Debian amd64 perf
records this 32-bit TF2 process but does not unwind its x86 stacks. A private
Debian i386 perf and matching libraries were verified without changing the
server architecture or installing an in-server extension. Disable debuginfod
downloads. Do not use i386 perf's broken `--ns` output formatting.

```sh
sudo /usr/bin/python3 /usr/local/libexec/checklag-native.py report \
  --capture PRIVATE_ALERT_DIRECTORY \
  --perf /usr/local/lib/checklag-perf32/usr/bin/perf \
  --library-path /usr/local/lib/checklag-perf32/usr/lib/i386-linux-gnu
```

The report prints symbol-only aggregated stacks, stripping addresses and
directory paths; it does not print registers or stack bytes. Missing unwind
support is an error, not silently reported as no samples. An alert may
legitimately have no CPU samples in its estimated frame window.

Join native capture metadata to the existing map-session/tick database records.
Frame-window alignment uses the observed log time minus logged frame age,
with a +/-150 ms tolerance for logging/polling delay. Samples are statistical
on-CPU evidence, not exact exclusive timings. Sleeping, blocked, or descheduled
time cannot be attributed from these samples; use CheckLag host CPU, faults,
I/O and scheduler counters alongside them. No claim of a root cause should
be made from a lone stack.

## Local verification

```sh
python3 -m unittest discover -s tools/tests -p test_checklag_native.py -v
```

The twelve unit tests cover metadata redaction, manual events, malformed
ticks, process identity, private-directory guards, symbol sanitization and
bounded hardlink retention. Integration testing uses a private synthetic log
outside SourceMod/DB and verifies repeated closed captures and real TF2
32-bit stack decoding. Never manufacture a stall on a production server.

Installing new SMX files does not activate them in an already loaded plugin.
Deploy without reload when requested; the finer stages become active on the
next explicit plugin load/restart. The external recorder works immediately.
