#!/usr/bin/env python3
"""One update gate and lifecycle owner for the shared TF2/MGE installation."""

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
import fcntl
import http.client
import json
import logging
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

LOG = logging.getLogger('tf2-service')
ROLES = ('tf2', 'mge')
APP_ID = '232250'
GAME_ID = '440'
API = 'https://api.steampowered.com/ISteamApps/UpToDateCheck/v1/'


@dataclass(frozen=True)
class Config:
    game: Path
    steamcmd: Path
    state: Path

    @classmethod
    def production(cls):
        home = Path.home()
        return cls(home / 'hlserver/tf2', home / 'hlserver/steamcmd.sh',
                   home / '.local/state/tf2-servers')


def installed_version(game):
    values = {}
    for line in (game / 'tf/steam.inf').read_text().splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    version = values.get('PatchVersion', '')
    if values.get('appID') != GAME_ID or not re.fullmatch(r'[0-9]+', version):
        raise ValueError('Not a valid TF2 steam.inf')
    return version


def query_current(version):
    """Public endpoint: no API key or unrelated application environment needed."""
    query = urllib.parse.urlencode({'appid': GAME_ID, 'version': version})
    request = urllib.request.Request(API + '?' + query, headers={'User-Agent': 'Kogasatopia-TF2-Startup/1'})
    with urllib.request.urlopen(request, timeout=8) as response:
        data = response.read(65537)
    if len(data) > 65536:
        raise ValueError('Oversized version response')
    result = json.loads(data)['response']
    if result.get('success') is not True or type(result.get('up_to_date')) is not bool:
        raise ValueError('Unusable version response')
    return result['up_to_date']


def check_current(config):
    try:
        version = installed_version(config.game)
        current = query_current(version)
        LOG.info('Version check: %s (installed=%s)', 'current' if current else 'outdated', version)
        return current
    except (OSError, ValueError, KeyError, TypeError, urllib.error.URLError, http.client.HTTPException) as error:
        # Never log response bodies, environment variables, credentials, or URLs.
        LOG.warning('Version check unavailable (%s); falling back to SteamCMD', type(error).__name__)
        return None


def processes():
    """PID/parent/start-time only; no secret-bearing process arguments."""
    result = {}
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        try:
            stat = (path / 'stat').read_text()
            fields = stat[stat.rfind(')') + 2:].split()
            if fields[0] in ('Z', 'X'):
                continue
            result[int(path.name)] = (int(fields[1]), int(fields[19]))
        except (OSError, ValueError, IndexError):
            continue
    return result


def descendants(root, table):
    selected = {root}
    while True:
        children = {pid for pid, (parent, _) in table.items() if parent in selected}
        if children <= selected:
            return {pid: table[pid][1] for pid in selected if pid in table}
        selected |= children


def engines(config):
    root = config.game.resolve()
    selected = {}
    for pid, (_, started) in processes().items():
        path = Path('/proc') / str(pid)
        try:
            exe = (path / 'exe').resolve()
            if exe.name in ('srcds_linux', 'srcds_linux64') and (
                    root in exe.parents or (path / 'cwd').resolve() == root):
                selected[pid] = started
        except (OSError, RuntimeError):
            continue
    return selected


def screens():
    result = subprocess.run(['screen', '-ls'], capture_output=True, text=True, timeout=5)
    if result.returncode not in (0, 1):
        raise RuntimeError('Cannot inspect screen sessions')
    selected = {}
    for pid, role in re.findall(r'^\s*(\d+)\.(tf2|mge)\s', result.stdout, re.M):
        if role in selected:
            raise RuntimeError('Duplicate managed screen name: ' + role)
        selected[role] = int(pid)
    return selected


def remaining(selected):
    table = processes()
    return {pid: started for pid, started in selected.items()
            if pid in table and table[pid][1] == started}


def wait_stopped(selected, seconds):
    deadline = time.monotonic() + seconds
    while remaining(selected) and time.monotonic() < deadline:
        time.sleep(0.1)
    return remaining(selected)


def stop_roles(config, roles):
    sessions = screens()
    table = processes()
    selected = {}
    for role in roles:
        if role in sessions:
            selected.update(descendants(sessions[role], table))
    if set(roles) == set(ROLES):
        # Also stop any orphaned engines from this exact shared installation.
        selected.update(engines(config))
    for role in roles:
        if role in sessions:
            subprocess.run(['screen', '-S', f'{sessions[role]}.{role}', '-X', 'quit'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    survivors = wait_stopped(selected, 5)
    for pid, started in survivors.items():
        # A re-used PID must never receive a signal.
        if remaining({pid: started}):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if wait_stopped(selected, 5):
        raise RuntimeError('Managed processes did not stop; refusing to modify shared files')
    if any(role in screens() for role in roles):
        raise RuntimeError('A managed screen survived shutdown')
    LOG.info('Stopped screens: %s', ', '.join(roles))
    return bool(selected)


@contextmanager
def lifecycle_lock(config):
    config.state.mkdir(parents=True, mode=0o700, exist_ok=True)
    with (config.state / 'lifecycle.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        deadline = time.monotonic() + 25
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Another lifecycle/update operation owns the lock') from None
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def update(config):
    if not config.steamcmd.is_file():
        raise RuntimeError('SteamCMD launcher is missing')
    if screens() or engines(config):
        raise RuntimeError('Refusing to update shared files while a managed server is running')
    # Force the existing shared installation, not a second Steam library. No validate.
    args = [str(config.steamcmd), '+@ShutdownOnFailedCommand', '1',
            '+@NoPromptForPassword', '1', '+force_install_dir', str(config.game.resolve()),
            '+login', 'anonymous', '+app_update', APP_ID, '+quit']
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    log = config.state / f'steamcmd-{stamp}.private.log'
    LOG.info('SteamCMD update beginning; both screens remain stopped (no validation)')
    with log.open('xb') as output:
        os.chmod(log, 0o600)
        result = subprocess.run(args, cwd=config.steamcmd.parent, stdout=output,
                                stderr=subprocess.STDOUT, timeout=1200)
    with log.open('rb') as output:
        output.seek(max(0, log.stat().st_size - 65536))
        tail = output.read()
    success = re.search(rb"Success! App '232250' (?:fully installed|already up to date)\.", tail)
    if result.returncode or not success:
        raise RuntimeError('SteamCMD did not confirm success; both screens remain stopped (private log saved)')
    installed_version(config.game)  # An incomplete installation must not launch.
    if check_current(config) is False:
        raise RuntimeError('TF2 remains outdated after SteamCMD; both screens remain stopped')
    LOG.info('SteamCMD completed successfully; shared installation ready')


def start_screen(config, role):
    subprocess.run(['screen', '-dmS', role, '/bin/bash', '-lc',
                    'cd "$1" && exec "$2"', 'tf2-screen', str(config.game),
                    str(config.game / (role + '.sh'))], check=True, capture_output=True, timeout=5)
    deadline = time.monotonic() + 3
    while role not in screens():
        if time.monotonic() >= deadline:
            raise RuntimeError('Screen did not start: ' + role)
        time.sleep(0.1)
    LOG.info('Started screen: %s', role)


def start(config):
    began = time.monotonic()
    if screens() or engines(config):
        raise RuntimeError('Servers already running; use systemctl restart tf2')
    for role in ROLES:
        script = config.game / (role + '.sh')
        if not script.is_file() or not os.access(script, os.X_OK):
            raise RuntimeError('Missing executable launcher: ' + role)
        # Do not allow either srcds_run loop to bypass our shared updater lock.
        commands = '\n'.join(line.split('#', 1)[0] for line in script.read_text().splitlines())
        if re.search(r'(?<!\S)[-+]autoupdate\b', commands):
            raise RuntimeError('Remove per-server autoupdate from launcher: ' + role)
    current = check_current(config)
    if current is not True:
        update(config)
    else:
        LOG.info('SteamCMD skipped: installed TF2 version is current')
    try:
        for role in ROLES:
            start_screen(config, role)
    except Exception:
        stop_roles(config, ROLES)
        raise
    result = {'occurred_at': int(time.time()), 'version': installed_version(config.game),
              'steamcmd_ran': current is not True, 'elapsed_seconds': round(time.monotonic() - began, 3)}
    target = config.state / 'last-start.json'
    temporary = target.with_suffix('.new')
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.chmod(0o600)
    temporary.replace(target)
    LOG.info('Both screens launched; update gate completed in %.3fs', result['elapsed_seconds'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('start', 'stop', 'stop-mge', 'check'))
    args = parser.parse_args()
    os.umask(0o077)
    logging.basicConfig(level=logging.INFO, format='[tf2-service] %(message)s')
    config = Config.production()
    try:
        if args.command == 'check':
            return 0 if check_current(config) is True else 1
        with lifecycle_lock(config):
            if args.command == 'start':
                start(config)
            elif args.command == 'stop':
                stop_roles(config, ROLES)
            elif not stop_roles(config, ('mge',)):
                return 3  # Watchdog: already inactive; never touch main TF2.
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        # Subprocess exceptions can include launch arguments: report only their type.
        LOG.error('%s', str(error) if isinstance(error, RuntimeError) else type(error).__name__)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
