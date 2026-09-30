#!/usr/bin/env python3
"""Delete closed demo recordings older than two weeks, checking once daily."""

import argparse
import fcntl
import os
from pathlib import Path
import subprocess
import time

ROOTS = (
    Path('/home/kogasa/hlserver/tf2/tf'),
    Path('/var/www/fastdl/demos'),
)
STATE_DIR = Path('/var/lib/kogasatopia-demo-cleanup')
INTERVAL = 24 * 60 * 60
RETENTION = 14 * 24 * 60 * 60


def find_demos(roots):
    demos = []
    for configured_root in roots:
        root = configured_root.resolve(strict=True)
        for directory, _, names in os.walk(root, followlinks=False):
            for name in names:
                if not name.endswith(('.dem', '.dem.bz2')):
                    continue
                path = Path(directory) / name
                if not path.is_symlink() and path.is_file() and path.resolve().is_relative_to(root):
                    demos.append(path)
    return demos


def open_demos(demos):
    if not demos:
        return set()
    # Query all open files once, including recordings outside these directories.
    result = subprocess.run(
        ['/usr/bin/lsof', '-nP', '-F', 'n'],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError('lsof failed; refusing to delete possibly active recordings')
    return {Path(line[1:]) for line in result.stdout.splitlines() if line.startswith('n/')}


def cleanup(roots=ROOTS, state_dir=STATE_DIR, force=False, dry_run=False):
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state_dir / 'lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        marker = state_dir / 'last_run'
        now = int(time.time())
        last_run = int(marker.read_text()) if marker.exists() else 0
        if not force and now - last_run < INTERVAL:
            return

        demos = find_demos(roots)
        active = open_demos(demos)
        removed = size = skipped = 0
        for path in demos:
            if path in active:
                skipped += 1
                continue
            try:
                stat = path.stat()
                if now - stat.st_mtime < RETENTION:
                    continue
                size += stat.st_size
                if not dry_run:
                    path.unlink()
                removed += 1
            except FileNotFoundError:
                continue
        if not dry_run:
            temporary = marker.with_suffix('.tmp')
            temporary.write_text(str(now))
            temporary.replace(marker)
        print(f'demo cleanup: {removed} files, {size} bytes; {skipped} open recordings skipped; dry_run={dry_run}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    cleanup(force=args.force, dry_run=args.dry_run)
