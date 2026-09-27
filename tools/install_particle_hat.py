#!/usr/bin/env python3
"""Install a particle hat archive and publish merged TF2 map particle manifests.

Dependency: srctools. Never installs a global particles_manifest.txt.
"""
import argparse
import bz2
import io
from pathlib import Path, PurePosixPath
import struct
import zipfile

from srctools import Keyvalues


def publish(root, fastdl, relative, data):
    local = root / relative
    remote = fastdl / relative
    local.parent.mkdir(parents=True, exist_ok=True)
    remote.parent.mkdir(parents=True, exist_ok=True)
    local.write_bytes(data)
    remote.write_bytes(data)
    compressed = remote.with_name(remote.name + ".bz2")
    compressed.write_bytes(bz2.compress(data))
    for path in (remote, compressed, *remote.parents):
        if path == fastdl.parent:
            break
        path.chmod(0o777)
    assert bz2.decompress(compressed.read_bytes()) == local.read_bytes()


def packed_manifest(bsp, manifest):
    with bsp.open("rb") as stream:
        header = stream.read(8 + 64 * 16)
        if header[:4] != b"VBSP":
            raise ValueError(f"Invalid BSP: {bsp}")
        offset, length = struct.unpack_from("<ii", header, 8 + 40 * 16)
        if not length:
            return False
        stream.seek(offset)
        data = stream.read(length)
    with zipfile.ZipFile(io.BytesIO(data)) as pak:
        names = {name.lower() for name in pak.namelist()}
        return "particles.txt" in names or manifest.lower() in names


def particle_definitions(data):
    stream = io.BytesIO(data)

    def cstring():
        value = bytearray()
        while True:
            char = stream.read(1)
            if not char:
                raise ValueError("Truncated binary PCF")
            if char == b"\0":
                return value.decode("utf-8")
            value.extend(char)

    if "dmx encoding binary 2 format pcf 1" not in cstring():
        raise ValueError("Expected binary-2 PCF")
    strings = [cstring() for _ in range(struct.unpack("<H", stream.read(2))[0])]
    count = struct.unpack("<I", stream.read(4))[0]
    definitions = []
    for _ in range(count):
        kind = strings[struct.unpack("<H", stream.read(2))[0]]
        name = cstring()
        stream.read(16)
        if kind == "DmeParticleSystemDefinition":
            definitions.append(name)
    return definitions


def manifests(root, fastdl, pcfs):
    published = 0
    skipped = []
    for bsp in sorted((root / "maps").rglob("*.bsp")):
        relative = f"maps/{bsp.stem}_particles.txt"
        if packed_manifest(bsp, relative):
            skipped.append(str(bsp.relative_to(root)))
            continue
        path = root / relative
        entries = []
        if path.exists():
            parsed = Keyvalues.parse(path.read_text(), str(path), single_line=True)
            for entry in parsed.find_key("particles_manifest"):
                if entry.name != "file" or entry.has_children():
                    raise ValueError(f"Unsupported manifest entry in {path}")
                entries.append(entry.value)
        for pcf in pcfs:
            matches = [i for i, value in enumerate(entries) if value.lstrip("!") == pcf]
            if matches:
                for i in matches:
                    entries[i] = "!" + pcf
            else:
                entries.append("!" + pcf)
        if len(entries) > 64:
            raise ValueError(f"Over TF2's 64-file map manifest limit: {path}")
        text = '"particles_manifest"\n{\n'
        text += "".join(f'    "file" "{value}"\n' for value in entries)
        text += "}\n"
        publish(root, fastdl, relative, text.encode())
        published += 1
    print(f"Published and verified {published} map manifests.")
    for path in skipped:
        print(f"Packed manifest takes priority; requires BSP merge: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--tf-root", required=True, type=Path)
    parser.add_argument("--fastdl", required=True, type=Path)
    parser.add_argument("--model-source", required=True)
    parser.add_argument("--model-target", required=True)
    parser.add_argument("--pcf", action="append", required=True)
    parser.add_argument("--effect", required=True)
    args = parser.parse_args()
    root, fastdl = args.tf_root.resolve(), args.fastdl.resolve()
    if not root.is_dir() or not fastdl.is_dir():
        parser.error("TF and FastDL roots must exist")
    assets = {}
    with zipfile.ZipFile(args.archive) as archive:
        for member in archive.infolist():
            if member.is_dir():
                continue
            parts = PurePosixPath(member.filename).parts
            if ".." in parts or member.filename.startswith("/"):
                raise ValueError("Unsafe archive path")
            # Mod archives may have one enclosing directory.
            start = next((i for i, p in enumerate(parts) if p in ("models", "materials", "particles")), None)
            if start is None:
                continue
            relative = "/".join(parts[start:])
            if relative == "particles/particles_manifest.txt":
                continue
            if relative.startswith(args.model_source + "."):
                relative = args.model_target + relative[len(args.model_source):]
            elif relative.startswith("models/"):
                continue
            data = archive.read(member)
            if relative == args.model_target + ".mdl":
                if data[:4] != b"IDST":
                    raise ValueError("Invalid MDL")
                name = args.model_target.removeprefix("models/") + ".mdl"
                if len(name.encode()) >= 64:
                    raise ValueError("MDL header name is too long")
                data = data[:12] + name.encode().ljust(64, b"\0") + data[76:]
            assets[relative] = data
    for pcf in args.pcf:
        data = assets.get(pcf, (root / pcf).read_bytes() if (root / pcf).exists() else b"")
        definitions = particle_definitions(data)
        print(f"{pcf}: {', '.join(definitions)}")
        if args.effect not in definitions:
            raise ValueError(f"Effect {args.effect} is absent from {pcf}")
    for relative, data in sorted(assets.items()):
        publish(root, fastdl, relative, data)
    print(f"Installed and verified {len(assets)} assets (raw and bzip2 FastDL).")
    manifests(root, fastdl, args.pcf)


if __name__ == "__main__":
    main()

