# Current-production CheckLag mode laboratory

Use `checklag_loadout_stress.sp` and `run_checklag_modes.py` for current merged
Weapons builds. The older `loadout_stress.sp`/`run_trial.py` and October 11
sources/results remain historical, not a deployment recipe for today's server.

The current suite tests sixteen **TF2 bots**, not sixteen networked humans.
Both hats and weapons are replayed from the same donor identity. Export the
latest ten finalized non-MGE matches with `export_loadouts.php`; fixtures are
anonymous but must stay mode 0600 outside Git. Do not modify real cookies or
purchases. Current laboratory grants are bot-serial-bound and in-memory only.

Create a private temporary directory under `/tmp` and copy the **current main
checkout's scripting tree**, not this branch's historical Weapons tree. From
that private scripting directory, apply `current_weapons_test_api.patch` with
`git apply --check` followed by `git apply`. Copy `current_weapons_test_api.sp`
to its `weapons/debug_loadout.sp`. Compile that tree's weapons.sp and compile
`checklag_loadout_stress.sp` with that tree's includes. Retain current production
extensions/gamedata; no legacy native extension or stack recorder is needed.
The current merged extension has no old lab-only loadout aggregate API: zero
placeholders in historical output columns mean **not collected**, not zero cost.

Stage the two test plugins in the live `plugins/disabled` directory with the
explicit names `weapons_modes_lab.smx` and `loadout_stress_modes.smx`. Save the
original map/convars and private fixture first. Only empty MGE is eligible.
Switch to a normal test map and let that map finish loading **before** unloading
production Weapons and explicitly loading these test plugins. Otherwise normal
SourceMod map-start auto-loading can restore production Weapons alongside the
laboratory plugin. The new harness has no auto-load dependency on weapons.smx
and refuses every trial unless exactly one running Weapons provider exists:
the laboratory plugin, with production weapons.smx not running. Verify
`sm_loadoutstress_state` reports `single_lab_provider=1` before proceeding.

The harness refuses any human and stops when one connects. It retains its
existing bot serial ownership, duration/operation/free-edict bounds, restores
`nb_stop`, and removes only owned bots. Disable and later restore sigsegv's
idle-optimization cvar for comparable bot runs. Do not alter the main server's
map, convars or native extension as part of these tests.

The controller selects only the MGE screen's descendant engine and stops on
process replacement or low memory. All current trials pair both domains.
Use the existing `~/.venvs/resource-guard/bin/python` interpreter (psutil).
Examples (from the deployed Debug tools directory):

```
python3 run_checklag_modes.py unique_mode1 --mode 1 --duration 30
python3 run_checklag_modes.py unique_mode2 --mode 2 --duration 30
python3 run_checklag_modes.py unique_mode3 --mode 3 --duration 30
python3 run_checklag_modes.py unique_ordinary --mode 2 --duration 15 --force 0 --class-cycle 0
python3 run_checklag_modes.py unique_dense --mode 3 --duration 15 --batch 16
```

For **explicitly authorized** controlled-alert validation only, `--hitch`
requests one 200ms bounded main-thread busy wait, during the owned bot trial.
The command is console-only, requires the running/population-safe harness, and
can fire only once per trial. It creates a real measured server stall, not fake
telemetry. Keep these runs separate from overhead comparisons. Mode 0 should
emit no alert; modes 1/2/3 should emit their selected evidence. Dense rebuilds
can independently cause intentionally expensive frames: neither kind of trial
proves the cause of a historical production incident.

Use independent frame/whole-engine CPU measurements as well as observer costs.
The primitive frame observer and producer-side profilers are deliberately not
inside CheckLag's self-accounting; do not present that subset as total overhead.
Check all emitted records, mode detail limits, new plugin errors and crashes.
Never commit private profiles, raw console/log captures, PIDs, identities or
environment/configuration contents. Anonymous timing/count aggregates are safe.

On completion: unload the lab and probe plugins, explicitly load/reload current
production Weapons/CheckLag, restore the original private fixture and convars,
restore the MGE map, move only this run's test binaries out of active/disabled
plugin discovery paths, and verify zero owned bots and healthy production APIs.
The main server must never receive a laboratory Weapons binary.
