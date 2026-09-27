import bz2
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from install_particle_hat import manifests, packed_manifest, particle_definitions, publish


class ParticleHatTests(unittest.TestCase):
    def test_publish_verifies_compression_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root, remote = Path(directory) / "tf", Path(directory) / "fastdl"
            root.mkdir()
            remote.mkdir()
            publish(root, remote, "particles/test.pcf", b"particle data")
            self.assertEqual((root / "particles/test.pcf").read_bytes(),
                             bz2.decompress((remote / "particles/test.pcf.bz2").read_bytes()))
            for path in (remote / "particles").iterdir():
                self.assertEqual(path.stat().st_mode & 0o777, 0o777)

    def test_manifests_preserve_duplicates_and_are_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root, remote = Path(directory) / "tf", Path(directory) / "fastdl"
            (root / "maps").mkdir(parents=True)
            remote.mkdir()
            (root / "maps/test.bsp").write_bytes(b"VBSP" + struct.pack("<I", 20) + bytes(64 * 16))
            path = root / "maps/test_particles.txt"
            path.write_text('"particles_manifest" { "file" "!particles/stock1.pcf" "file" "particles/stock2.pcf" }')
            manifests(root, remote, ["particles/custom.pcf"])
            first = path.read_bytes()
            manifests(root, remote, ["particles/custom.pcf"])
            self.assertEqual(first, path.read_bytes())
            self.assertIn(b"!particles/stock1.pcf", first)
            self.assertIn(b"particles/stock2.pcf", first)
            self.assertEqual(first.count(b"!particles/custom.pcf"), 1)

    def test_packed_manifest_takes_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            bsp = Path(directory) / "test.bsp"
            pak = io.BytesIO()
            with zipfile.ZipFile(pak, "w") as archive:
                archive.writestr("particles.txt", '"particles_manifest" {}')
            header = bytearray(b"VBSP" + struct.pack("<I", 20) + bytes(64 * 16))
            struct.pack_into("<ii", header, 8 + 40 * 16, len(header), len(pak.getvalue()))
            bsp.write_bytes(header + pak.getvalue())
            self.assertTrue(packed_manifest(bsp, "maps/test_particles.txt"))

    def test_binary_pcf_definition_names(self):
        data = b"<!-- dmx encoding binary 2 format pcf 1 -->\0"
        data += struct.pack("<H", 1) + b"DmeParticleSystemDefinition\0"
        data += struct.pack("<I", 1) + struct.pack("<H", 0) + b"test_effect\0" + bytes(16)
        self.assertEqual(particle_definitions(data), ["test_effect"])
        with self.assertRaises(ValueError):
            particle_definitions(b"invalid\0")


if __name__ == "__main__":
    unittest.main()

