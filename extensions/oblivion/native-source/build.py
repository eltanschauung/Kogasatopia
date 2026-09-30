"""Rebuild CollisionHook and Oblivion Network with pinned public dependencies."""
from pathlib import Path
import argparse, os, shutil, subprocess, sys

SOURCE=Path(__file__).resolve().parent
DEPS=SOURCE/'build-deps'
PINS={
 'ambuild':('alliedmodders/ambuild','01212cb57c96561f664b6dfb2ee10e66de6f81e4'),
 'sourcemod':('alliedmodders/sourcemod','2e229b111534b1be007dc3bd9acfcf2fc472e893'),
 'metamod-source':('alliedmodders/metamod-source','75dd7b26fe92e535a11f0318ead73c3e05130d0b'),
 'hl2sdk-tf2':('alliedmodders/hl2sdk','0f358777e7a7f0ad4c6ed6595de1e4e81c15fa4e'),
}
def run(args,**kwargs):subprocess.run(args,check=True,**kwargs)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--targets',default='x86,x86_64');args=parser.parse_args()
    DEPS.mkdir(exist_ok=True)
    for name,(repository,revision) in PINS.items():
        target=DEPS/name
        if not target.exists():run(['git','clone','--filter=blob:none','--no-checkout','https://github.com/'+repository+'.git',str(target)])
        current=subprocess.run(['git','-C',str(target),'rev-parse','HEAD'],capture_output=True,text=True)
        if current.returncode or current.stdout.strip()!=revision:
            run(['git','-C',str(target),'fetch','--depth','1','origin',revision])
            run(['git','-C',str(target),'checkout','--detach',revision])
    run(['git','-C',str(DEPS/'sourcemod'),'submodule','update','--init','--depth','1','public/amtl','sourcepawn','public/safetyhook'])
    shutil.copytree(DEPS/'sourcemod/public/safetyhook',SOURCE/'safetyhook',dirs_exist_ok=True,ignore=shutil.ignore_patterns('.git'))
    env=dict(os.environ);env['PYTHONPATH']=str(DEPS/'ambuild')
    for project in [SOURCE, SOURCE/'oblivion-net']:
        build=project/'build';build.mkdir(exist_ok=True)
        run([sys.executable,str(project/'configure.py'),'--hl2sdk-root='+str(DEPS),'--sm-path='+str(DEPS/'sourcemod'),
             '--mms-path='+str(DEPS/'metamod-source'),'-s','tf2','--enable-optimize','--targets',args.targets],cwd=build,env=env)
        run([sys.executable,'-c','from ambuild2.run import cli_run; cli_run()','-j','4'],cwd=build,env=env)
