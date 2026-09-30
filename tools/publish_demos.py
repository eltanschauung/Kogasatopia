#!/usr/bin/env python3
"""Move finalized, closed TF2 demos into FastDL without copying or overwriting."""

import argparse
import fcntl
import math
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import time

SOURCE = Path('/home/kogasa/hlserver/tf2/tf')
DESTINATION = Path('/var/www/fastdl/demos')
STATE_DIR = Path('/var/lib/kogasatopia-demo-cleanup')
QUIET_SECONDS = 30
HEADER_SIZE = 1072
NAME = re.compile(r'[A-Za-z0-9_-]+\.dem', re.ASCII)


def open_files():
    result = subprocess.run(
        ['/usr/bin/lsof', '-nP', '-F', 'n'],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError('lsof failed; refusing to publish possibly active demos')
    return {Path(line[1:]) for line in result.stdout.splitlines() if line.startswith('n/')}


def finalized(path):
    # Source writes playback totals into this header when recording is finalized.
    with path.open('rb') as recording:
        header = recording.read(HEADER_SIZE)
    if len(header) != HEADER_SIZE or header[:8] != b'HL2DEMO\x00':
        return False
    protocol, = struct.unpack_from('<i', header, 8)
    duration, ticks, frames, signon = struct.unpack_from('<fiii', header, 1056)
    return (protocol == 3 and math.isfinite(duration) and duration > 0
            and ticks > 0 and frames >= 0 and signon >= 0)


def fingerprint(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns)


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def publish(source=SOURCE, destination=DESTINATION, state_dir=STATE_DIR, dry_run=False):
    source = source.resolve(strict=True)
    destination = destination.resolve(strict=True)
    if source == destination or source.stat().st_dev != destination.stat().st_dev:
        raise RuntimeError('Demo directories must be separate and on the same filesystem')
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Share the retention job's lock so publication and deletion cannot race.
    with (state_dir / 'lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        candidates = [path for path in source.glob('*.dem') if NAME.fullmatch(path.name)]
        if not candidates:
            return 0
        active = open_files()
        moved = 0
        errors = []
        now = time.time()
        for path in candidates:
            try:
                before = path.lstat()
                if (not stat.S_ISREG(before.st_mode) or path in active
                        or now - before.st_mtime < QUIET_SECONDS or not finalized(path)):
                    continue
                if fingerprint(before) != fingerprint(path.lstat()):
                    continue
                target = destination / path.name
                if target.exists() or target.is_symlink():
                    # Resume if a previous run stopped after linking but before unlinking.
                    if target.is_symlink() or not os.path.samefile(path, target):
                        raise RuntimeError(f'Refusing to overwrite published demo: {target.name}')
                    if not dry_run:
                        path.unlink()
                        sync_directory(source)
                elif not dry_run:
                    os.chmod(path, 0o644)
                    # link + unlink is a no-copy move. The final name appears atomically,
                    # and unlike rename(), link() never overwrites a collision.
                    os.link(path, target, follow_symlinks=False)
                    if fingerprint(before) != fingerprint(target.lstat()):
                        target.unlink()
                        raise RuntimeError(f'Recording changed during publication: {path.name}')
                    sync_directory(destination)
                    path.unlink()
                    sync_directory(source)
                moved += 1
                print(f'demo published: {path.name}; bytes={before.st_size}; dry_run={dry_run}')
            except FileNotFoundError:
                continue
            except (OSError, RuntimeError) as error:
                errors.append(str(error))
                print(f'demo publication failed: {path.name}: {error}', file=sys.stderr)
        if errors:
            raise RuntimeError(f'{len(errors)} demo(s) could not be published')
        return moved


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    publish(dry_run=args.dry_run)
