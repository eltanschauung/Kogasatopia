import os
from pathlib import Path
import struct
import tempfile
import time
import unittest
from unittest.mock import patch

import publish_demos as publisher


class PublishDemosTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source, self.destination, self.state = root / 'tf', root / 'fastdl', root / 'state'
        self.source.mkdir()
        self.destination.mkdir()
        self.active = set()
        patcher = patch.object(publisher, 'open_files', side_effect=lambda: self.active)
        patcher.start()
        self.addCleanup(patcher.stop)

    def recording(self, name='map_sept_30_14-36.dem', finished=True):
        header = bytearray(1072)
        header[:8] = b'HL2DEMO\x00'
        struct.pack_into('<i', header, 8, 3)
        struct.pack_into('<fiii', header, 1056, 60 if finished else 0, 4000, 600, 200)
        path = self.source / name
        path.write_bytes(header + b'payload')
        old = time.time() - 60
        os.utime(path, (old, old))
        return path

    def run_publish(self, **kwargs):
        return publisher.publish(self.source, self.destination, self.state, **kwargs)

    def test_moves_without_copy_and_preserves_bytes_and_write_time(self):
        path = self.recording()
        metadata, content = path.stat(), path.read_bytes()
        self.assertEqual(self.run_publish(), 1)
        target = self.destination / path.name
        self.assertFalse(path.exists())
        self.assertEqual(target.read_bytes(), content)
        self.assertEqual(target.stat().st_ino, metadata.st_ino)
        self.assertEqual(target.stat().st_mtime_ns, metadata.st_mtime_ns)
        self.assertEqual(target.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.run_publish(), 0)

    def test_active_unfinished_recent_invalid_and_symlink_are_not_published(self):
        active = self.recording('active.dem')
        self.active.add(active)
        self.recording('unfinished.dem', finished=False)
        recent = self.recording('recent.dem')
        os.utime(recent, None)
        (self.source / 'invalid.dem').write_bytes(b'not a recording')
        (self.source / 'linked.dem').symlink_to(active)
        self.assertEqual(self.run_publish(), 0)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_failure_to_inspect_open_files_leaves_recordings_untouched(self):
        path = self.recording()
        with patch.object(publisher, 'open_files', side_effect=RuntimeError('lsof failed')):
            with self.assertRaises(RuntimeError):
                self.run_publish()
        self.assertTrue(path.exists())

    def test_never_overwrites_and_recovers_an_interrupted_move(self):
        path = self.recording()
        target = self.destination / path.name
        target.write_bytes(b'different recording')
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertEqual(target.read_bytes(), b'different recording')
        self.assertTrue(path.exists())
        target.unlink()
        os.link(path, target)
        self.assertEqual(self.run_publish(), 1)
        self.assertFalse(path.exists())

    def test_dry_run_does_not_move(self):
        path = self.recording()
        self.assertEqual(self.run_publish(dry_run=True), 1)
        self.assertTrue(path.exists())
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_one_collision_does_not_block_other_recordings(self):
        collision = self.recording('collision.dem')
        (self.destination / collision.name).write_bytes(b'other recording')
        ready = self.recording('ready.dem')
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertTrue(collision.exists())
        self.assertFalse(ready.exists())
        self.assertTrue((self.destination / ready.name).exists())


if __name__ == '__main__':
    unittest.main()
