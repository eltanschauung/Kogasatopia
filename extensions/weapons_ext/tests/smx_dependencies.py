#!/usr/bin/env python3
"""Read extension metadata, not arbitrary binary strings or runtime secrets."""
from pathlib import Path
import re
import struct
import zlib

LEGACY = {'game.tf2.ext', 'tf2items.ext', 'conch_no_speed.ext', 'scattergun_pellets.ext',
          'tf2_spread_patterns.ext', 'whitelist_policy.ext', 'tf2_sentry_newtarget_dist.ext',
          'tf2econdynamic.ext'}

def extension_dependencies(path):
    raw = Path(path).read_bytes()
    magic, version, compression, disksize, imagesize, sections, strings, data_offset = struct.unpack_from('<IHBIIBII', raw)
    if magic != 0x53504646: raise ValueError('Not a SourcePawn binary')
    image = raw[:data_offset] + (zlib.decompress(raw[data_offset:disksize]) if compression else raw[data_offset:])
    def text_at(offset):
        end = image.index(b'\0', offset)
        return image[offset:end].decode('utf-8', errors='replace')
    table = {}
    for index in range(sections):
        name, offset, size = struct.unpack_from('<III', image, 24 + index * 12)
        table[text_at(strings + name)] = (offset, size)
    if '.pubvars' not in table or '.data' not in table: return []
    data, _ = table['.data']
    datasize, memsize, start = struct.unpack_from('<III', image, data)
    names, _ = table['.names']
    variables, size = table['.pubvars']
    deps = []
    for at in range(variables, variables + size, 8):
        address, name = struct.unpack_from('<II', image, at)
        if not text_at(names + name).startswith('__ext_'): continue
        if address + 16 > datasize: raise ValueError('Invalid extension metadata')
        name_ptr, file_ptr, autoload, required = struct.unpack_from('<IIII', image, data + start + address)
        file = text_at(data + start + file_ptr)
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,100}', file): raise ValueError('Unsafe metadata filename')
        deps.append({'file':file, 'required':bool(required), 'autoload':bool(autoload)})
    return deps

def has_legacy(deps):
    return any(any(d['file'] == old or d['file'].startswith(old + '.') for old in LEGACY) for d in deps)

if __name__ == '__main__':
    import sys, json
    for arg in sys.argv[1:]:
        path = Path(arg)
        paths = sorted(path.glob('*.smx')) if path.is_dir() else [path]
        for binary in paths:
            deps = extension_dependencies(binary)
            if has_legacy(deps) or not path.is_dir():
                print(json.dumps({'plugin':binary.name, 'extensions':deps}))
