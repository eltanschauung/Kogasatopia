"""Verify compiled hook ownership (not merely early-returning callbacks)."""
import struct
import sys
import zlib
from pathlib import Path

AUTOMATIC = {
    "OnGameFrame", "OnEntityCreated", "OnPlayerRunCmd",
    "TF2_OnConditionAdded", "TF2_OnConditionRemoved", "TF2_CalcIsAttackCritical",
}

def public_names(path):
    raw = Path(path).read_bytes()
    magic, version, compression, disk, size, count, strings, data = struct.unpack_from("<IHB IIBII", raw)
    assert magic == 0x53504646
    image = raw[:data] + zlib.decompress(raw[data:disk]) if compression == 1 else raw
    sections = {}
    def cstring(offset):
        return image[offset:image.index(b"\0",offset)].decode()
    for index in range(count):
        name, offset, length = struct.unpack_from("<III", image, 24 + index * 12)
        sections[cstring(strings + name)] = (offset, length)
    names, _ = sections[".names"]
    publics, length = sections[".publics"]
    return {cstring(names + struct.unpack_from("<II", image, offset)[1]) for offset in range(publics, publics + length, 8)}

core, bridge = map(public_names, sys.argv[1:3])
assert not (core & AUTOMATIC), "Core still exports automatic full-RTD hooks"
assert AUTOMATIC <= bridge, "Bridge missing an automatic callback"
assert "RTD_Full_GameFrame" in core
assert "RTD_Full_PlayerRunCmd" in core
print("Compiled hook ownership: PASS (6 automatic forwards isolated; none in rtd.smx)")
