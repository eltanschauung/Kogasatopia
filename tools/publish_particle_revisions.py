#!/usr/bin/env python3
"""Publish immutable particle revisions and stable 32-slot map manifests."""
import argparse
import io
from pathlib import Path
import re
import uuid

from srctools import Keyvalues
from srctools.dmx import Attribute, Element, ValueType

from install_particle_hat import packed_manifest, particle_definitions, publish

REVISIONS = tuple(f"particles/kogasa_particles_r{i:02d}.pcf" for i in range(1, 33))
LEGACY = {"particles/ba_tsurugi_blood.pcf", "particles/procuration_v4.pcf"}


def map_basename(name):
    name = name.replace("\\", "/").rsplit("/", 1)[-1].lower()
    name = re.sub(r"\.bsp$", "", name)
    return re.sub(r"\.ugc[0-9]+$", "", name)


def manifest_entries(data, filename):
    parsed = Keyvalues.parse(data.decode("utf-8-sig"), filename, single_line=True)
    result = []
    for entry in parsed.find_key("particles_manifest"):
        if entry.name != "file" or entry.has_children():
            raise ValueError(f"Unsupported manifest entry in {filename}")
        result.append(entry.value)
    return result


def reserved_manifest(entries):
    # Retired standalone files now live inside r01; keep unrelated map PCFs.
    result = []
    for entry in entries:
        path = entry.lstrip("!").lower()
        if path not in LEGACY and path not in REVISIONS:
            result.append(entry)
    result.extend("!" + path for path in REVISIONS)
    if len(result) > 64:
        raise ValueError("Manifest exceeds TF2's 64-entry limit")
    return ('"particles_manifest"\n{\n' +
            "".join(f'    "file" "{entry}"\n' for entry in result) + "}\n").encode()


def merge_pcfs(sources):
    definitions = []
    names = set()
    for source in sources:
        root, fmt, version = Element.parse(io.BytesIO(source))
        if fmt != "pcf" or version != 1:
            raise ValueError("Expected PCF format 1")
        for effect in root["particleSystemDefinitions"].iter_elem():
            if effect.type != "DmeParticleSystemDefinition" or effect.name in names:
                raise ValueError(f"Invalid/duplicate effect: {effect.name}")
            names.add(effect.name)
            definitions.append(effect)
    if not definitions:
        raise ValueError("Empty particle bundle")
    root = Element("kogasa_particles", "DmeElement",
                   uuid.uuid5(uuid.NAMESPACE_URL, "https://kogasa.tf/particles/bundle-root"))
    root["editorType"] = "particleSystemDefinitionList"
    root["particleSystemDefinitions"] = Attribute.array(
        "particleSystemDefinitions", ValueType.ELEMENT, definitions)
    output = io.BytesIO()
    root.export_binary(output, version=2, fmt_name="pcf", fmt_ver=1)
    data = output.getvalue()
    # Round-trip validates the element graph, not just the binary header.
    decoded, _, _ = Element.parse(io.BytesIO(data))
    actual = {effect.name for effect in decoded["particleSystemDefinitions"].iter_elem()}
    if actual != names or set(particle_definitions(data)) != names:
        raise ValueError("Bundle lost particle definitions")
    return data


def plan_manifests(root):
    planned = {}
    blocked = []
    for bsp in sorted((root / "maps").rglob("*.bsp")):
        relative = f"maps/{map_basename(bsp.name)}_particles.txt"
        if packed_manifest(bsp, relative):
            blocked.append(str(bsp.relative_to(root)))
        if relative not in planned:
            path = root / relative
            entries = manifest_entries(path.read_bytes(), relative) if path.exists() else []
            planned[relative] = reserved_manifest(entries)
    if not planned:
        raise ValueError("No installed BSPs found")
    return planned, blocked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tf-root", type=Path, required=True)
    parser.add_argument("--fastdl", type=Path, required=True)
    parser.add_argument("--revision", type=int, default=1, choices=range(1, 33))
    parser.add_argument("--source", type=Path, action="append", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root, remote = args.tf_root.resolve(), args.fastdl.resolve()
    if not root.is_dir() or not remote.is_dir():
        parser.error("TF and FastDL roots must exist")
    data = merge_pcfs([path.read_bytes() for path in args.source])
    relative = REVISIONS[args.revision - 1]
    # Clients cache downloads by filename. Never mutate a published revision.
    for target in (root / relative, remote / relative):
        if target.exists() and target.read_bytes() != data:
            raise ValueError(f"Immutable revision already exists: {target}; use a new revision")
    planned, blocked = plan_manifests(root)
    if not args.dry_run:
        publish(root, remote, relative, data)
        for name, manifest in planned.items():
            publish(root, remote, name, manifest)
        for name, manifest in planned.items():
            if (root / name).read_bytes() != manifest:
                raise ValueError(f"Manifest verification failed: {name}")
    print(f"{'Planned' if args.dry_run else 'Published/verified'} {relative}: "
          f"{len(particle_definitions(data))} effects, {len(data)} bytes; "
          f"{len(planned)} map manifests with 32 reserved revisions")
    print(f"{len(blocked)} BSPs have overriding packed manifests (left untouched):")
    for name in blocked:
        print(name)


if __name__ == "__main__":
    main()

