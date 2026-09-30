import importlib.util
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('cleanup_demos', Path(__file__).with_name('cleanup_demos.py'))
cleanup_demos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup_demos)


class DemoCleanupTest(unittest.TestCase):
    def test_cleanup_preserves_active_files_and_other_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'tf'
            root.mkdir()
            state = Path(directory) / 'state'
            closed = root / 'old.dem'
            compressed = root / 'old.dem.bz2'
            active = root / 'active.dem'
            asset = root / 'map.bsp'
            outside = Path(directory) / 'outside.dem'
            for path in (closed, compressed, active, asset, outside):
                path.write_text('data')
            (root / 'link.dem').symlink_to(outside)
            with patch.object(cleanup_demos, 'open_demos', return_value={active}):
                cleanup_demos.cleanup([root], state, dry_run=True)
                self.assertTrue(closed.exists())
                self.assertFalse((state / 'last_run').exists())
                cleanup_demos.cleanup([root], state)
                self.assertFalse(closed.exists())
                self.assertFalse(compressed.exists())
                self.assertTrue(active.exists())
                self.assertTrue(asset.exists())
                self.assertTrue(outside.exists())
                closed.write_text('new recording')
                cleanup_demos.cleanup([root], state)
                self.assertTrue(closed.exists())
                (state / 'last_run').write_text(str(int(time.time()) - cleanup_demos.INTERVAL))
                cleanup_demos.cleanup([root], state)
                self.assertFalse(closed.exists())

    def test_open_file_check_failure_does_not_delete_or_advance_schedule(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'tf'
            root.mkdir()
            demo = root / 'old.dem'
            demo.write_text('recording')
            state = Path(directory) / 'state'
            with patch.object(cleanup_demos, 'open_demos', side_effect=RuntimeError('lsof failed')):
                with self.assertRaises(RuntimeError):
                    cleanup_demos.cleanup([root], state)
            self.assertTrue(demo.exists())
            self.assertFalse((state / 'last_run').exists())


if __name__ == '__main__':
    unittest.main()
