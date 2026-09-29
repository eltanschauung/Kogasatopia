"""Portable native build using pinned public dependencies (Python + AMBuild)."""
from pathlib import Path
import argparse,os,subprocess,sys
ROOT=Path(__file__).resolve().parent
PINS={
 'ambuild':('alliedmodders/ambuild','01212cb57c96561f664b6dfb2ee10e66de6f81e4'),
 'sourcemod':('alliedmodders/sourcemod','2e229b111534b1be007dc3bd9acfcf2fc472e893'),
 'metamod-source':('alliedmodders/metamod-source','75dd7b26fe92e535a11f0318ead73c3e05130d0b'),
 'hl2sdk-tf2':('alliedmodders/hl2sdk','0f358777e7a7f0ad4c6ed6595de1e4e81c15fa4e'),
}
def run(args,**kw):subprocess.run(args,check=True,**kw)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--targets',default='x86,x86_64');args=parser.parse_args()
    deps=ROOT/'build-deps';deps.mkdir(exist_ok=True)
    for name,(repo,revision) in PINS.items():
        target=deps/name
        if not target.exists():run(['git','clone','--filter=blob:none','--no-checkout','https://github.com/'+repo+'.git',str(target)])
        current=subprocess.run(['git','-C',str(target),'rev-parse','HEAD'],capture_output=True,text=True)
        if current.returncode or current.stdout.strip()!=revision:
            run(['git','-C',str(target),'fetch','--depth','1','origin',revision])
            run(['git','-C',str(target),'checkout','--detach',revision])
    run(['git','-C',str(deps/'sourcemod'),'submodule','update','--init','--depth','1','public/amtl','sourcepawn'])
    env=dict(os.environ);env['PYTHONPATH']=str(deps/'ambuild')
    build=ROOT/'build';build.mkdir(exist_ok=True)
    run([sys.executable,str(ROOT/'configure.py'),'--hl2sdk-root='+str(deps),'--sm-path='+str(deps/'sourcemod'),
         '--mms-path='+str(deps/'metamod-source'),'-s','tf2','--enable-optimize','--targets',args.targets],cwd=build,env=env)
    run([sys.executable,'-c','from ambuild2.run import cli_run; cli_run()','-j','4'],cwd=build,env=env)
