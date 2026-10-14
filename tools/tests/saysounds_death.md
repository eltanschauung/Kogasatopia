# Saysounds death-event recipients

The victim receives their resolved death preference, or
`saysounds_default_death_sound` when no death preference is configured.
The distinct killer receives their configured kill preference; without a valid
kill preference, they receive no kill/death saysound for that event.

Everyone else retains the original public resolution:

1. A valid/audible weapon `saysound on kill` override takes precedence.
2. Two valid explicit death/kill preferences compete in one shared 50/50 draw.
3. Otherwise use whichever resolved public preference is available.
4. The default death sound is a public fallback only when no kill preference
   resolved; it never starts competing with a configured kill sound.

A suicide has only a victim, not a separate killer. World deaths and invalid
clients are handled without indexing invalid preferences. Each recipient gets
at most one sound from this pipeline. Sound-list/group selections resolve once,
not once per listener. Existing volume, forced groups, opt-outs, purchase/API
restrictions, and Oblivion filtering continue through the existing helpers.

Weapon override fallback keeps the old global eligibility decision, including
participants who would previously have heard it. This prevents unrelated
public death/kill sounds from leaking to bystanders merely because the newly
personalized participants were the override's only eligible listeners.

Usage is recorded once per resolved sound per event, not twice when the same
sound plays personally and publicly. Private-only usage records target the
participant; public usage retains target 0.

## Regression probe

`tools/tests/saysounds_death_probe.sp` includes the production event router and
replaces resolution/playback/logging with in-memory fixtures. It requires the
private lab marker and a server-console invocation. It creates an event object
for input but cancels it without firing; no real sound, death event, cookie
write, or production database event is generated.

Compile with the repository scripting directory and live SourceMod includes:

```sh
spcomp tools/tests/saysounds_death_probe.sp -w203 \
  -itf/addons/sourcemod/scripting \
  -itf/addons/sourcemod/scripting/include \
  -i/path/to/sourcemod/scripting/include \
  -o/private/lab/plugins/saysounds_death_probe.smx
```

Warning 203 is disabled for this standalone probe only: the included production
cookie-load/save functions are intentionally uncalled. Production Saysounds
is compiled with normal warnings enabled.

Run `sm_saysounds_death_probe` in an isolated TF2 lab. Coverage includes both
random outcomes, shared selection, usage deduplication, default/missing/invalid
preferences, suicides, world deaths, invalid victims, weapon overrides and
their inaudible fallback, per-client group/volume opt-outs, forced groups,
Oblivion filtering, paid-sound denial, and no duplicate emissions.

Validated in the isolated TF2 lab: **487 checks, 0 failures**. Production
Saysounds also compiles without warnings on SourceMod 1.12.0.7221.
