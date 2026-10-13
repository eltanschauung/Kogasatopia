#!/usr/bin/env python3
import struct
import tempfile
from pathlib import Path
import zlib
import re
from relink_smx import relink
from smx_dependencies import extension_dependencies

# SourceMod keys extension owners by the requested name, not the resulting
# physical DSO. The .autoload marker uses this unsuffixed key too.
header=Path(__file__).resolve().parents[3]/'tf/addons/sourcemod/scripting/include/weapons_ext_dependency.inc'
assert re.search(r'file\s*=\s*"weapons_ext\.ext"\s*,',header.read_text()), 'Dependency must match autoload owner; never spell the engine suffix here'

def fixture(compressed, data_first):
    names=b'__ext_tf2\0ExampleNative\0'
    contents={
        '.names':names,
        '.pubvars':struct.pack('<II',0,0),
        '.natives':struct.pack('<I',len(b'__ext_tf2\0')),
        '.code':bytes(range(32)),
    }
    payload=struct.pack('<IIII',16,16+len(b'TF2 Tools\0'),0,1)+b'TF2 Tools\0game.tf2.ext\0'
    payload+=b'\0'*((-len(payload))%4)
    contents['.data']=struct.pack('<III',len(payload),len(payload)+1024,12)+payload
    order=['.data','.code','.names','.pubvars','.natives'] if data_first else ['.code','.names','.pubvars','.natives','.data']
    strings=b''.join(name.encode()+b'\0' for name in order)
    string_offset=24+len(order)*12
    data_offset=string_offset+len(strings)
    body=b'';table=b'';name_offset=0
    for name in order:
        table+=struct.pack('<III',name_offset,data_offset+len(body),len(contents[name]))
        body+=contents[name];name_offset+=len(name)+1
    encoded=zlib.compress(body) if compressed else body
    header=struct.pack('<IHBIIBII',0x53504646,0x0107,int(compressed),data_offset+len(encoded),data_offset+len(body),len(order),string_offset,data_offset)
    return header+table+strings+encoded

with tempfile.TemporaryDirectory(prefix='weapons-ext-smx-') as directory:
    base=Path(directory)
    for compressed in (False,True):
        for first in (False,True):
            source=base/f'old-{compressed}-{first}.smx'
            target=base/f'new-{compressed}-{first}.smx'
            initial=fixture(compressed,first)
            source.write_bytes(initial)
            relink(source,target)
            assert source.read_bytes()==initial
            assert extension_dependencies(target)==[{'file':'weapons_ext.ext','required':True,'autoload':True}]
            try:relink(source,target)
            except AssertionError:pass
            else:raise AssertionError('Output overwrite was not rejected')
print('SMX migration tests passed: compressed/uncompressed, section relocation, bytecode preservation, overwrite refusal')
