# Shared TF2/MGE startup

`tools/tf2_service.py` is the lifecycle/update owner for both servers. The systemd
unit `tools/systemd/tf2.service` launches the existing `tf2` and `mge` screen names
using the private, deployment-local `tf2.sh` and `mge.sh`. Those launchers keep
their server-specific arguments, but must not contain `-autoupdate` (or its
Steam directory/script switches). Do not commit credential-bearing launchers.

## Operation

```sh
sudo systemctl restart tf2  # stops both, checks once, starts both
sudo systemctl stop tf2     # stops both
sudo systemctl start tf2    # starts both if the unit is inactive
python3 ~/Kogasatopia/tools/tf2_service.py check  # read-only version probe
python3 ~/Kogasatopia/tools/tf2_service.py stop-mge  # watchdog/manual MGE-only stop
```

There is no separate `mge.service`. Its unit is disabled and masked so an old
automation job cannot start a second lifecycle/update owner. A stopped MGE is
not automatically respawned by systemd; `systemctl restart tf2` restores both.
The ordinary `srcds_run` crash-restart behavior inside each screen is retained,
but per-screen automatic updates are removed. Use the shared service for update
checks; individual legacy `start_*_screen.sh` helpers bypass the update gate.

## Update policy

1. Serialize lifecycle commands with `~/.local/state/tf2-servers/lifecycle.lock`.
2. Refuse startup/update if either managed screen or an engine from the shared
   installation is still running.
3. Read `PatchVersion` from `tf/steam.inf` and query Valve's public
   [UpToDateCheck API](https://partner.steamgames.com/doc/webapi/ISteamApps#UpToDateCheck)
   for game app 440, with an eight-second timeout. This endpoint needs **no API
   key**; do not copy any frontend environment or secret into this deployment.
4. If current, skip SteamCMD entirely. If outdated, unavailable, malformed, or
   the local version is unreadable, run anonymous SteamCMD for server app 232250
   against the existing shared installation, **without `validate`**.
   Before invoking SteamCMD, require at least 1 GiB available on both its
   bootstrap filesystem and the game filesystem. This is a minimum safety
   margin, not a guarantee that every update will fit. Insufficient space is
   reported directly in the journal; the wrapper never deletes data itself.
   Preserve the configured `/home/kogasa/hlserver/tf2` alias in the command:
   do not resolve it to the mixed-case Steam library path containing spaces.
5. Require SteamCMD's successful exit and app-success marker. If Valve still
   explicitly reports an outdated version afterward, fail with neither screen
   started. A failed post-update API request may rely on confirmed SteamCMD
   success instead.
6. Only after that gate completes, launch TF2, then MGE. MGE can never run ahead
   of an update. Failed screen launches stop both as cleanup.

Valve's endpoint checks game-version compatibility, not every Steam depot build
or file checksum. Same-version optional depot changes may not be detected;
perform a manual incremental `app_update 232250` with both servers stopped when
such an update is needed. Reserve `validate` for explicit repair, not startup.

The unit allows up to 25 minutes for startup (SteamCMD itself has a 20-minute
timeout). It uses `KillMode=control-group` and cleanup on failed starts. Both
screens/engines belong to `tf2.service`. The resource watchdog calls `stop-mge`,
which identifies only MGE's screen descendants and never stops `tf2.service`.
No periodic API requests or resident manager are added after startup.

## Diagnostics and tests

Startup decisions appear in `journalctl -u tf2`. The safe last-start summary is
`~/.local/state/tf2-servers/last-start.json`. SteamCMD output is retained in
mode-0600 `steamcmd-*.private.log` files there, not in Git or chat. Do not dump
raw screen output: existing private launch arguments can contain secrets.

SteamCMD failures include the exit code and private-log path. Known disk-space
errors are summarized without copying arbitrary private output into the journal.
The production lowercase `steamapps/common/team fortress 2 dedicated server`
path aliases the existing mixed-case installation. Both spellings must resolve
to the same directory, not two partial installations. If recovering split
files, stop both engines first and preserve conflicting files before merging;
do not launch using only a recovered `steam.inf` without the rest of the update.

```sh
python3 -m unittest discover -s tools/tests -p test_tf2_service.py -v
# The existing watchdog suite uses its pinned virtualenv:
~/.venvs/resource-guard/bin/python -m unittest discover -s tools/tests -p test_resource_guard.py -v
```

Tests mock version responses, SteamCMD, and screen operations. They cover
current/outdated/unknown decisions, failure cleanup, update ordering, shared
locking, disk-space preflight, configured install-alias preservation, private
failure reporting, no validation, no API-key transmission, and MGE-only shutdown. They do
not start production engines or update production files.
