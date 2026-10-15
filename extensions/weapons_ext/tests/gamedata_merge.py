"""Lossless quoted-token KeyValues merge with fail-closed collision handling."""
from pathlib import Path
import copy,json,re,sys
FILES=['weapons.txt','weapons.ammo_pickups.txt','weapons.deploy_finished.txt','weapons.inventory_diagnostics.txt','weapons.kunai_nerf.txt','weapons.schema.txt','weapons.services.txt','weapon_overrides.games.txt','tf2.items.txt','tf2.attributes.txt','tf2.utils.nosoop.txt','tf2.ontakedamage.txt','tf2.whitelist_policy.txt','conch_no_speed.games.txt','scattergun_pellets.games.txt','tf2_spread_patterns.games.txt','tf2_sentry_newtarget_dist.games.txt']
TOKEN=re.compile(r'\s+|//[^\n]*|/\*[\s\S]*?\*/|"((?:\\.|[^"\\])*)"|([{}])')
def parse(text):
    tokens=[];at=0
    while at<len(text):
        match=TOKEN.match(text,at)
        if not match:raise ValueError('Unexpected token near offset '+str(at))
        at=match.end()
        if match.group(1) is not None:tokens.append(('string',match.group(1)))
        elif match.group(2):tokens.append((match.group(2),match.group(2)))
    cursor=0
    def block(nested=False):
        nonlocal cursor
        result=[]
        while cursor<len(tokens):
            kind,key=tokens[cursor];cursor+=1
            if kind=='}':
                if not nested:raise ValueError('Unexpected closing brace')
                return result
            if kind!='string' or cursor==len(tokens):raise ValueError('Missing key/value')
            kind,value=tokens[cursor];cursor+=1
            if kind=='{':value=block(True)
            elif kind!='string':raise ValueError('Missing value')
            result.append((key,value))
        if nested:raise ValueError('Unclosed section')
        return result
    return block()
def emit(nodes,indent=0):
    result=[]
    for key,value in nodes:
        prefix='    '*indent
        if isinstance(value,list):result.extend([prefix+'"'+key+'"',prefix+'{',emit(value,indent+1),prefix+'}'])
        else:result.append(prefix+'"'+key+'" "'+value+'"')
    return '\n'.join(result)
def merge(destination,source,path=()):
    for key,value in source:
        matches=[i for i,(name,_) in enumerate(destination) if name==key]
        if not matches:destination.append((key,copy.deepcopy(value)));continue
        if len(matches)!=1:raise ValueError('Ambiguous destination '+str(path+(key,)))
        index=matches[0];old=destination[index][1]
        if old==value:continue
        # Merge selectors, section groups and entry platform dictionaries only.
        # Deeper directive lists (e.g. repeated address "read") are atomic.
        if isinstance(old,list) and isinstance(value,list) and len(path)<4:
            merge(old,value,path+(key,))
        else:raise ValueError('Conflicting value: '+str(path+(key,))+' old='+str(old)+' new='+str(value))
def main():
    root=Path(sys.argv[1]);output=Path(sys.argv[2]);combined=[]
    sources={}
    for filename in FILES:
        tree=parse((root/filename).read_text())
        assert len(tree)==1 and tree[0][0]=='Games',filename
        sources[filename]=tree
        try:merge(combined,tree)
        except ValueError as error:raise ValueError(filename+': '+str(error))
    # Every original leaf/subtree must survive; compare each key recursively.
    def contains(target,source):
        if target==source:return
        if len({key for key,_ in source})!=len(source):
            raise AssertionError('Ordered repeated directives must remain identical')
        for key,value in source:
            matches=[v for k,v in target if k==key];assert len(matches)==1,key
            if isinstance(value,list):contains(matches[0],value)
            else:assert matches[0]==value,key
    for tree in sources.values():contains(combined,tree)
    content='// Weapons-owned engine bindings. Source files and ownership audit: extensions/weapons_ext/GAMEDATA.md\n'+emit(combined)+'\n'
    assert parse(content)==combined
    output.write_text(content)
    print('Merged',len(FILES),'files losslessly; all original bindings preserved')
if __name__=='__main__':main()
