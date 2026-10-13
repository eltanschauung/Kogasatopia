#!/usr/bin/env python3
"""Update one legacy extension dependency without altering plugin bytecode.

For installed third-party binaries whose exact source/build includes are absent.
No runtime aliases, shim extensions or game-code changes are introduced. The
original binary is never modified; output goes to a new staging file.
"""
from pathlib import Path
import hashlib
import struct
import zlib
from smx_dependencies import extension_dependencies, has_legacy, LEGACY

def relink(source, output):
    source, output = Path(source), Path(output)
    assert not output.exists(), 'Refuse to overwrite a migration build'
    raw=source.read_bytes()
    header=list(struct.unpack_from('<IHBIIBII',raw))
    magic,version,compression,disksize,imagesize,count,strings,data_offset=header
    assert magic==0x53504646 and compression in (0,1)
    image=bytearray(raw[:data_offset]+(zlib.decompress(raw[data_offset:disksize]) if compression else raw[data_offset:]))
    assert len(image)==imagesize
    def text(at):return bytes(image[at:image.index(0,at)]).decode('utf-8',errors='replace')
    sections={}
    for i in range(count):
        name,offset,size=struct.unpack_from('<III',image,24+i*12)
        sections[text(strings+name)]=(i,offset,size)
    _,data,size=sections['.data']
    datasize,memsize,start=struct.unpack_from('<III',image,data)
    assert start+datasize==size, 'Unsupported data-section layout'
    _,names,_=sections['.names']
    _,variables,varsize=sections['.pubvars']
    candidates=[]
    for at in range(variables,variables+varsize,8):
        address,name=struct.unpack_from('<II',image,at)
        if not text(names+name).startswith('__ext_'):continue
        values=struct.unpack_from('<IIII',image,data+start+address)
        file=text(data+start+values[1])
        if any(file==old or file.startswith(old+'.') for old in LEGACY):candidates.append((address,values))
    assert len(candidates)==1, 'Only single-legacy-dependency binaries may be relinked'
    # Do not silently leave compiled feature-detection logic referring to the
    # retired extension libraries. Such a plugin requires its actual source.
    _,native_table,native_size=sections['.natives']
    native_names={text(names+struct.unpack_from('<I',image,at)[0]) for at in range(native_table,native_table+native_size,4)}
    data_strings=set(bytes(image[data+start:data+start+datasize]).split(b'\0'))
    assert 'LibraryExists' not in native_names or not data_strings.intersection({b'tf2',b'TF2Items',b'conch_no_speed',b'scattergun_pellets',b'tf2_spread_patterns',b'whitelist_policy_native',b'tf2_sentry_newtarget_dist'}), 'Legacy feature checks require a source rebuild'
    code_index,code,code_size=sections['.code']
    before_code=hashlib.sha256(image[code:code+code_size]).digest()
    names_index,native_table,native_size=sections['.natives']
    before_natives=bytes(image[native_table:native_table+native_size])
    address,oldvalues=candidates[0]
    name=b'weapons_ext\0';file=b'weapons_ext.ext\0'
    append=name+file
    append+=b'\0'*((-len(append))%4)
    struct.pack_into('<IIII',image,data+start+address,datasize,datasize+len(name),1,oldvalues[3])
    struct.pack_into('<III',image,data,datasize+len(append),memsize+len(append),start)
    insertion=data+size
    image[insertion:insertion]=append
    for section,(i,offset,oldsize) in sections.items():
        if offset>=insertion:offset+=len(append)
        if section=='.data':oldsize+=len(append)
        struct.pack_into('<II',image,24+i*12+4,offset,oldsize)
    if strings>=insertion:header[6]+=len(append)
    if data_offset>=insertion:header[7]+=len(append)
    header[4]=len(image)
    body=zlib.compress(bytes(image[header[7]:])) if compression else bytes(image[header[7]:])
    header[3]=header[7]+len(body)
    result=bytearray(image[:header[7]])+body
    struct.pack_into('<IHBIIBII',result,0,*header)
    output.write_bytes(result)
    after=extension_dependencies(output)
    assert not has_legacy(after) and sum(d['file']=='weapons_ext.ext' for d in after)==1
    new_code=code+len(append) if code>=insertion else code
    new_natives=native_table+len(append) if native_table>=insertion else native_table
    assert hashlib.sha256(image[new_code:new_code+code_size]).digest()==before_code
    assert bytes(image[new_natives:new_natives+native_size])==before_natives
    return after

if __name__=='__main__':
    import sys
    relink(sys.argv[1],sys.argv[2])
    print('Relinked dependency; bytecode and native table unchanged')
