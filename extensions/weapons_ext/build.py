#!/usr/bin/env python3
"""Serial, low-priority, memory-bounded AMBuild invocation; never installs."""
import argparse
import os
from pathlib import Path
import re
import resource
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('build_directory', type=Path)
parser.add_argument('--ambuild', default=str(Path.home()/'.local/bin/ambuild'))
opts = parser.parse_args()
available = next(int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemAvailable:'))
if available < 384 * 1024:
    raise SystemExit('Build paused: less than 384 MiB memory headroom; no compile started')
def constrain():
    os.nice(15)
    resource.setrlimit(resource.RLIMIT_AS, (1024 * 1024 * 1024, 1024 * 1024 * 1024))
log_path = opts.build_directory/'build.private.log'
log_path.touch(mode=0o600, exist_ok=True)
os.chmod(log_path, 0o600)
with log_path.open('w') as log:
    proc = subprocess.Popen([opts.ambuild, '-j', '1'], cwd=opts.build_directory,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=constrain)
    for line in proc.stdout:
        log.write(line)
        unit = re.search(r' -c (\S+)', line)
        if unit:
            print('Compiling:', Path(unit[1]).name, flush=True)
        elif any(x in line for x in ('error:', 'warning:', 'Build failed', 'Build succeeded', 'not found', 'undefined reference')):
            print(line.rstrip(), flush=True)
    result = proc.wait()
print('Build exit:', result, flush=True)
raise SystemExit(result)
