#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("native", Path(__file__).parents[1] / "checklag_native.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

class NativeCaptureTests(unittest.TestCase):
    def test_chat_and_other_plugin_lines_rejected(self):
        self.assertIsNone(native.parse_line("client: v=3|alert_tick=100"))
        self.assertIsNone(native.parse_line("[weapons.smx] [CheckLag] v=3|alert_tick=100"))

    def test_metadata_allowlist_removes_private_fields(self):
        parsed = native.parse_line("[checklag.smx] [CheckLag] v=3|alert_tick=100|rate=55|ip=192.0.2.1|name=test|token=secret")
        self.assertEqual(parsed, ("Alert", {"v": "3", "alert_tick": "100", "rate": "55"}))

    def test_manual_snapshot_distinguished(self):
        kind, values = native.parse_line("[checklag.smx] [CheckLag] v=3|alert_tick=100|snapshot_kind=manual")
        self.assertEqual(kind, "Alert")
        self.assertEqual(values["snapshot_kind"], "manual")

    def test_frames_and_host_fields(self):
        parsed = native.parse_line("[checklag.smx] [CheckLag][Frame] v=3|alert_tick=100|rank=1|frame_ms=120.0|age_ms=500")
        self.assertEqual(parsed[0], "Frame")
        self.assertEqual(parsed[1]["frame_ms"], "120.0")
        self.assertEqual(native.parse_line("[checklag.smx] [CheckLag][Host] v=3|alert_tick=100|probe_ms=0.1")[0], "Host")

    def test_malformed_tick_rejected(self):
        self.assertIsNone(native.parse_line("[checklag.smx] [CheckLag] v=3|alert_tick=../other"))

    def test_matching_process_guard(self):
        with self.assertRaises(ValueError):
            native.identity(os.getpid())

    def test_private_empty_directory_guard(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(native.private_directory(root), root)
            (root / "keep").touch()
            with self.assertRaises(ValueError):
                native.private_directory(root)

    def test_world_readable_directory_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root.chmod(0o755)
            with self.assertRaises(ValueError):
                native.private_directory(root)

    def test_output_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "target"
            target.mkdir()
            link = Path(temporary) / "link"
            link.symlink_to(target)
            with self.assertRaises(ValueError):
                native.private_directory(link)

    def test_stacks_strip_addresses_and_private_paths(self):
        lines = [
            " srcds_linux 123 100.123456: cpu-clock:u:\n",
            "\t deadbeef CTFPlayer::ValidateWeapons()+0x42 (/private/server_srv.so)\n",
            "\t 1234abcd [unknown] (/private/jit.so)\n",
            "\n",
            "srcds_linux 123 100.234567: cpu-clock:u:\n",
            "\t aabbccdd EngineFunction() (/private/engine_srv.so)\n",
        ]
        stacks = list(native.sample_stacks(lines))
        self.assertEqual(len(stacks), 2)
        self.assertEqual(stacks[0][0], 100.123456)
        self.assertEqual(stacks[0][1][0], "CTFPlayer::ValidateWeapons() (server_srv.so)")
        self.assertNotIn("private", str(stacks))
        self.assertNotIn("deadbeef", str(stacks))

    def test_alert_waits_for_covering_sealed_segment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sample = root / "perf.data.1"
            sample.write_bytes(b"test fixture")
            observed = time.time_ns()
            os.utime(sample, ns=(observed - 1_000_000_000, observed - 1_000_000_000))
            pending = [{"observed_realtime_ns": observed, "alert": {"alert_tick": "100"}}]
            owned = []
            native.capture_pending(root, pending, [sample], owned, 2)
            self.assertEqual(len(pending), 1)
            self.assertFalse(owned)
            self.assertEqual(list(root.iterdir()), [sample])

    def test_retention_only_removes_owned_alerts(self):
        previous = os.umask(0o077)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                rolling = root / "rolling"
                rolling.mkdir()
                sample = rolling / "perf.data.1"
                sample.write_bytes(b"test fixture")
                os.utime(sample, ns=(time.time_ns(), time.time_ns() + 1_000_000_000))
                unrelated = root / "unrelated"
                unrelated.mkdir()
                owned = []
                for i in range(3):
                    pending = [{"alert": {"alert_tick": str(i)}, "frames": [], "hosts": [],
                                "observed_realtime_ns": time.time_ns()+i,
                                "observed_monotonic_ns": time.monotonic_ns()}]
                    with contextlib.redirect_stdout(io.StringIO()):
                        native.capture_pending(root, pending, [sample], owned, 2)
                    self.assertFalse(pending)
                self.assertEqual(len(owned), 2)
                self.assertTrue(unrelated.exists())
                self.assertTrue(sample.exists())
                self.assertEqual(sample.stat().st_nlink, 3)
                for directory in owned:
                    self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
                    metadata = directory / "metadata.json"
                    self.assertEqual(metadata.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(json.loads(metadata.read_text())["format"], native.MARKER)
        finally:
            os.umask(previous)

if __name__ == "__main__":
    unittest.main()
