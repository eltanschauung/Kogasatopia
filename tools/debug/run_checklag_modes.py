"""Bounded MGE-only trial controller; retains only anonymous timing aggregates."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import psutil

sys.path.insert(0,'/home/kogasa/Kogasatopia-Debug/tools/debug')
from console import send
from summarize import summarize
sys.path.insert(0,'/home/kogasa/Kogasatopia/tools')
from tf2_service import screens, descendants, processes

parser=argparse.ArgumentParser()
parser.add_argument('label')
parser.add_argument('--mode',type=int,choices=range(4),required=True)
parser.add_argument('--duration',type=int,default=30)
parser.add_argument('--batch',type=int,choices=range(1,17),default=1)
parser.add_argument('--hitch',action='store_true')
parser.add_argument('--force',type=int,choices=[0,1],default=1)
parser.add_argument('--class-cycle',type=int,choices=[0,1],default=1)
args=parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_-]{1,63}',args.label) or not 15<=args.duration<=60:
    raise SystemExit('Invalid trial bounds')
root=Path('/home/kogasa/hlserver/tf2/tf/addons/sourcemod')
output=root/'data/loadout-stress'/(args.label+'.log')
if output.exists(): raise SystemExit('Trial output already exists')
children=descendants(screens()['mge'],processes())
targets=[pid for pid in children if Path(f'/proc/{pid}/comm').read_text().strip() in ('srcds_linux','srcds_linux64')]
if len(targets)!=1: raise SystemExit('Cannot uniquely identify MGE engine')
engine=psutil.Process(targets[0])
identity=engine.create_time()
offsets={p:p.stat().st_size for p in (root/'logs').glob('errors_*.log')}
send('mge',f'sm_checklag_mode {args.mode}')
for command in ['sm_loadoutstress_batch '+str(args.batch),'sm_loadoutstress_force '+str(args.force),
                'sm_loadoutstress_class_cycle '+str(args.class_cycle),'sm_loadoutstress_hats 1','sm_loadoutstress_weapons 1']:
    send('mge',command)
time.sleep(2)
start=time.monotonic()
cpu_start=sum(engine.cpu_times()[:2])
rss_peak=0
send('mge',f'sm_loadoutstress_start {args.label} {args.duration}')
injected=False
try:
    while time.monotonic()-start < args.duration+35:
        if not engine.is_running() or engine.create_time()!=identity: raise RuntimeError('MGE restarted unexpectedly')
        if psutil.virtual_memory().available<256*1024**2: raise RuntimeError('Memory safety stop')
        rss_peak=max(rss_peak,engine.memory_info().rss)
        if args.hitch and not injected and time.monotonic()-start>=12:
            send('mge','sm_loadoutstress_hitch')
            injected=True
        if output.exists():
            text=output.read_text()
            if re.search(r'^summary\|',text,re.M):
                result=summarize(output)
                result['test_mode']=args.mode
                result['intentional_200ms_stall']=injected
                result['engine_cpu_ms_per_s']=(sum(engine.cpu_times()[:2])-cpu_start)*1000/(time.monotonic()-start)
                result['engine_peak_rss_mib']=round(rss_peak/1024**2,1)
                errors=[]
                for path in (root/'logs').glob('errors_*.log'):
                    with path.open(errors='replace') as file:
                        file.seek(offsets.get(path,0))
                        errors.extend(re.findall(r'Blaming: ([A-Za-z0-9_./-]+\.smx)',file.read()))
                result['new_plugin_errors']=errors
                result_path=output.with_suffix('.metrics.json')
                result_path.write_text(json.dumps(result,sort_keys=True))
                result_path.chmod(0o600)
                print(json.dumps(result,sort_keys=True),flush=True)
                if result['summary'].get('reason')!='complete': raise RuntimeError('Trial aborted safely')
                break
        time.sleep(0.25)
    else: raise RuntimeError('Trial timeout')
except BaseException:
    send('mge','sm_loadoutstress_stop')
    raise
