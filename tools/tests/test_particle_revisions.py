import io
from pathlib import Path
import sys
import unittest

from srctools.dmx import Attribute, Element, ValueType

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publish_particle_revisions import (
    REVISIONS, manifest_entries, map_basename, merge_pcfs, reserved_manifest,
)
from install_particle_hat import particle_definitions


def pcf(name):
    child = Element(name + "_child", "DmeParticleSystemDefinition")
    child["material"] = "test/material.vmt"
    parent = Element(name, "DmeParticleSystemDefinition")
    parent["children"] = Attribute.array("children", ValueType.ELEMENT, [child])
    root = Element("root", "DmeElement")
    root["particleSystemDefinitions"] = Attribute.array(
        "particleSystemDefinitions", ValueType.ELEMENT, [parent, child])
    stream = io.BytesIO()
    root.export_binary(stream, version=2, fmt_name="pcf", fmt_ver=1)
    return stream.getvalue()


class RevisionTests(unittest.TestCase):
    def test_workshop_physical_basename(self):
        for name in ("workshop/koth_brine_rc3a.ugc2965195337",
                     "maps/workshop/koth_brine_rc3a.ugc2965195337.bsp",
                     "koth_brine_rc3a.bsp"):
            self.assertEqual(map_basename(name), "koth_brine_rc3a")

    def test_32_slots_preserves_native_entries_and_retires_old_files(self):
        entries = ["!particles/map.pcf", "particles/ba_tsurugi_blood.pcf",
                   "!particles/procuration_v4.pcf", REVISIONS[0], "!" + REVISIONS[0]]
        data = reserved_manifest(entries)
        result = manifest_entries(data, "test")
        self.assertEqual(result, ["!particles/map.pcf"] + ["!" + p for p in REVISIONS])
        self.assertEqual(reserved_manifest(result), data)

    def test_maximum_64_entries(self):
        reserved_manifest([f"particles/map{i}.pcf" for i in range(32)])
        with self.assertRaises(ValueError):
            reserved_manifest([f"particles/map{i}.pcf" for i in range(33)])

    def test_merge_preserves_children_materials_and_encoding(self):
        sources = [pcf("tsurugi"), pcf("procuration")]
        data = merge_pcfs(sources)
        self.assertEqual(set(particle_definitions(data)),
                         {"tsurugi", "tsurugi_child", "procuration", "procuration_child"})
        root, fmt, version = Element.parse(io.BytesIO(data))
        self.assertEqual((fmt, version), ("pcf", 1))
        for parent in root["particleSystemDefinitions"].iter_elem():
            if not parent.name.endswith("_child"):
                child = next(parent["children"].iter_elem())
                self.assertEqual(child["material"].val_str, "test/material.vmt")
        self.assertEqual(merge_pcfs(sources), data)

    def test_duplicate_effect_rejected(self):
        source = pcf("same")
        with self.assertRaises(ValueError):
            merge_pcfs([source, source])


if __name__ == "__main__":
    unittest.main()

