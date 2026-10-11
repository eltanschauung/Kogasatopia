#!/usr/bin/env python3
"""Run one bounded empty-server trial; no deployment/restart or database writes."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import time
from console import send
from summarize import summarize

def available_kib():
    for line in Path('/proc/meminfo').read_text().splitlines():
        if line.startswith('MemAvailable:'): return int(line.split()[1])
    raise RuntimeError('MemAvailable unavailable')

def run(args):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,63}', args.label): raise ValueError('Unsafe label')
    if not 15 <= args.duration <= 300 or not 1 <= args.batch <= 16 or args.mode not in (0,1,2):
        raise ValueError('Trial bounds invalid')
    root=Path(args.sm_path).resolve()
    output=root/'data'/'loadout-stress'/(args.label+'.log')
    if output.exists(): raise ValueError('Output exists; use a new label')
    if available_kib()<512*1024: raise RuntimeError('Insufficient memory headroom')
    processes=[p for p in Path('/proc').iterdir() if p.name.isdigit()
               and (p/'comm').exists() and (p/'comm').read_text().strip()=='srcds_linux']
    if len(processes)!=1: raise RuntimeError('Exactly one TF2 process required')
    target=processes[0]
    # Identity checked internally only; do not retain or print process metadata.
    identity=(target/'stat').read_text().rsplit(')',1)[1].split()[19]
    perf=None; perf_log=None
    try:
        if args.perf_output:
            path=Path(args.perf_output)
            if path.exists() or path.is_symlink(): raise ValueError('Perf output must be new')
            if path.parent.stat().st_mode & 0o077: raise ValueError('Perf directory must be private')
            perf_log=path.with_suffix('.private.log').open('x')
            os.chmod(perf_log.name,0o600)
            command=['sudo','-n','perf','record','-e','cpu-clock:u','-F','49',
                '--call-graph','dwarf,8192','--clockid','mono','--no-inherit',
                '--no-buildid-cache','-m','64','-t',target.name,'-o',str(path),
                '--','sleep',str(args.duration+8)]
            perf=subprocess.Popen(command,stdout=perf_log,stderr=perf_log)
        send(args.session,'sm_checklag_mode %d'%args.mode)
        send(args.session,'sm_loadoutstress_batch %d'%args.batch)
        send(args.session,'sm_loadoutstress_force %d'%args.force)
        send(args.session,'sm_loadoutstress_class_cycle %d'%args.class_cycle)
        send(args.session,'sm_loadoutstress_hats %d'%args.hats)
        send(args.session,'sm_loadoutstress_weapons %d'%args.weapons)
        # Allow profiling mode change/native timer to settle before setup.
        time.sleep(2)
        send(args.session,'sm_loadoutstress_start %s %d'%(args.label,args.duration))
        started=time.monotonic()
        while time.monotonic()-started<args.duration+30:
            if not target.exists() or (target/'stat').read_text().rsplit(')',1)[1].split()[19]!=identity:
                raise RuntimeError('TF2 process changed; trial interrupted')
            if available_kib()<256*1024: raise RuntimeError('Memory safety stop')
            if args.perf_output and Path(args.perf_output).exists() and Path(args.perf_output).stat().st_size>32*1024*1024:
                raise RuntimeError('Perf capture exceeded 32MiB')
            if output.exists():
                text=output.read_text()
                if text.startswith('summary|') or '\nsummary|' in text:
                    import json
                    result=summarize(output)
                    print(json.dumps(result,indent=2),flush=True)
                    if result['summary'].get('reason')!='complete': raise RuntimeError('Trial stopped before completion')
                    return
            time.sleep(0.5)
        raise RuntimeError('Trial timed out; no completed summary')
    except BaseException:
        send(args.session,'sm_loadoutstress_stop')
        raise
    finally:
        if perf is not None:
            # This bounded child terminates naturally, never signal the target.
            try: perf.wait(timeout=15)
            except subprocess.TimeoutExpired: raise RuntimeError('Bounded perf child unexpectedly outlived its duration')
        if perf_log: perf_log.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('label')
    parser.add_argument('--duration',type=int,default=60)
    parser.add_argument('--batch',type=int,default=1)
    parser.add_argument('--mode',type=int,default=2)
    parser.add_argument('--force',type=int,choices=[0,1],default=0)
    parser.add_argument('--class-cycle',type=int,choices=[0,1],default=0)
    parser.add_argument('--hats',type=int,choices=[0,1],default=1)
    parser.add_argument('--weapons',type=int,choices=[0,1],default=1)
    parser.add_argument('--sm-path',required=True)
    parser.add_argument('--session',default='tf2')
    parser.add_argument('--perf-output')
    run(parser.parse_args())
