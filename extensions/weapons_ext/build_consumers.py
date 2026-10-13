#!/usr/bin/env python3
"""Stage affected live-plugin rebuilds with unified metadata; never deploy."""
from pathlib import Path
import argparse
import importlib.util
import os
import shutil
import subprocess
import json

parser=argparse.ArgumentParser()
parser.add_argument('--server-scripting', required=True, type=Path)
parser.add_argument('--server-plugins', required=True, type=Path)
parser.add_argument('--kogasatopia', required=True, type=Path)
parser.add_argument('--whaletracker', required=True, type=Path)
parser.add_argument('--nativevotes', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--overlays', type=Path)
parser.add_argument('--api-includes', type=Path, help='Canonical unified headers when building another checkout or dirty source snapshot')
parser.add_argument('--relink-unbuildable', action='store_true', help='Relink one dependency in missing/unbuildable third-party binaries; preserve bytecode')
args=parser.parse_args()
root=Path(__file__).resolve().parent
api_includes=args.api_includes or root/'include'
if not api_includes.is_dir():api_includes=root.parents[1]/'tf/addons/sourcemod/scripting/include'
api_headers=('tf2.inc','tf2items.inc','conch_no_speed.inc','scattergun_pellets.inc',
             'tf2_spread_patterns.inc','whitelist_policy.inc','tf2_sentry_newtarget_dist.inc',
             'weapons_ext.inc','weapons_ext_dependency.inc')
spec=importlib.util.spec_from_file_location('metadata',root/'tests/smx_dependencies.py')
metadata=importlib.util.module_from_spec(spec);spec.loader.exec_module(metadata)
import sys
sys.path.insert(0,str(root/'tests'))
from relink_smx import relink
assert not args.output.exists(), 'Use a new private output directory'
args.output.mkdir(mode=0o700)

def source_only(directory,names):
    return [name for name in names if name in ('.git','__pycache__','target','build') or (not (Path(directory)/name).is_dir()
            and (Path(name).suffix not in ('.inc','.sp')))]
locations={
    'kogasatopia':args.kogasatopia/'tf/addons/sourcemod/scripting',
    'whaletracker':args.whaletracker/'scripting',
    'nativevotes':args.nativevotes,
    'live':args.server_scripting,
}
snapshots={}
for name,path in locations.items():
    target=args.output/name
    shutil.copytree(path,target,ignore=source_only)
    include=target/'include';include.mkdir(exist_ok=True)
    for header in (api_includes/name for name in api_headers):
        shutil.copyfile(header,include/header.name)
    snapshots[name]=target

if args.overlays:
    mapping={
        'weapons.sp':'weapons.sp', 'whitelist_policy.sp':'whitelist_policy.sp',
        'whitelist.sp':'weapons/whitelist.sp',
        'tf2_sentry_newtarget_dist.sp':'tf2_sentry_newtarget_dist.sp',
        'amplifier.inc':'new_engi_buildings/amplifier.inc',
        'pellets_and_deaths.sp':'weapons/gameplay/pellets_and_deaths.sp',
    }
    for source,target in mapping.items():
        shutil.copyfile(args.overlays/source,snapshots['kogasatopia']/target)

plugins=[p for p in sorted(args.server_plugins.glob('*.smx'))
         if metadata.has_legacy(metadata.extension_dependencies(p))]
# The Firework-only RTD helper is dormant but must not resurrect a legacy TF2
# dependency if full RTD is enabled after migration.
helper=args.server_plugins/'disabled/rtd_full_events.smx'
if helper.is_file() and metadata.has_legacy(metadata.extension_dependencies(helper)):plugins.append(helper)
results=[]
third_party={'centerprojectiles','hwn_cosmetic_enabler','mge','tf-bhop','tf2utils'}
for binary in plugins:
    name=binary.stem
    source=None
    for key in ('kogasatopia','whaletracker','nativevotes','live'):
        candidate=snapshots[key]/(name+'.sp')
        if candidate.is_file():source=candidate;break
    if source is None and name=='rtd_full_events':source=snapshots['kogasatopia']/'rtd/full_events.sp'
    if source is None or not source.is_file():
        if args.relink_unbuildable and name in third_party:
            deps=relink(binary,args.output/(name+'.smx'))
            row={'plugin':binary.name,'status':'dependency_relinked','bytecode_unchanged':True}
            results.append(row);print(json.dumps(row),flush=True);continue
        row={'plugin':binary.name,'status':'source_missing'}
        results.append(row);print(json.dumps(row),flush=True);continue
    output=args.output/(name+'.smx')
    command=[str(args.server_scripting/'spcomp'),str(source),
             '-i'+str(source.parent/'include'),'-i'+str(snapshots['kogasatopia']/'include'),
             '-i'+str(snapshots['live']/'include'),'-o'+str(output)]
    proc=subprocess.run(command,cwd=source.parent,capture_output=True,text=True)
    log=args.output/(name+'.compile.private.log')
    log.write_text(proc.stdout+proc.stderr);log.chmod(0o600)
    row={'plugin':binary.name,'status':'compiled' if proc.returncode==0 else 'compile_failed'}
    if proc.returncode and args.relink_unbuildable and name in third_party:
        if output.exists():output.unlink()
        deps=relink(binary,output)
        row={'plugin':binary.name,'status':'dependency_relinked','bytecode_unchanged':True}
    if not proc.returncode:
        deps=metadata.extension_dependencies(output)
        if metadata.has_legacy(deps) or sum(d['file']=='weapons_ext.ext' for d in deps)!=1:
            row['status']='metadata_failed'
        row['extensions']=[d['file'] for d in deps if d['file']!='core']
    results.append(row)
    print(json.dumps(row),flush=True)
manifest=args.output/'migration-build.json'
manifest.write_text(json.dumps(results,indent=2)+'\n')
assert all(r['status'] in ('compiled','dependency_relinked') for r in results), 'Migration is incomplete; no live files changed'
print('Consumer migration builds:',len(results),'passed; no binaries deployed')
