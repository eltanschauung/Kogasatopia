import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tf2_service as service


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        (self.game / 'tf').mkdir()
        self.file = self.game / 'tf/steam.inf'

    def test_installed_patch_not_steam_build_id(self):
        self.file.write_text('PatchVersion=11138802\nServerVersion=123\nappID=440\n')
        self.assertEqual(service.installed_version(self.game), '11138802')

    def test_invalid_or_foreign_install(self):
        for text in ('appID=440\n', 'appID=440\nPatchVersion=bad\n',
                     'appID=730\nPatchVersion=123\n'):
            with self.subTest(text=text):
                self.file.write_text(text)
                with self.assertRaises(ValueError):
                    service.installed_version(self.game)

    @patch('tf2_service.urllib.request.urlopen')
    def test_public_api_needs_no_key(self, urlopen):
        urlopen.return_value.__enter__.return_value.read.return_value = json.dumps({
            'response': {'success': True, 'up_to_date': True}}).encode()
        with patch.dict(os.environ, {'STEAM_API_KEY': 'test-secret-not-for-request'}):
            self.assertTrue(service.query_current('123'))
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, service.API + '?appid=440&version=123')
        self.assertNotIn('test-secret', request.full_url)
        self.assertEqual(urlopen.call_args.kwargs['timeout'], 8)

    @patch('tf2_service.urllib.request.urlopen')
    def test_malformed_results_do_not_skip_update(self, urlopen):
        for payload in ({}, {'response': {}}, {'response': {'success': False}},
                        {'response': {'success': True, 'up_to_date': 'true'}},
                        {'response': {'success': True, 'up_to_date': 1}}):
            urlopen.return_value.__enter__.return_value.read.return_value = json.dumps(payload).encode()
            with self.assertRaises((ValueError, KeyError)):
                service.query_current('123')

    @patch('tf2_service.installed_version', return_value='123')
    @patch('tf2_service.query_current', side_effect=urllib.error.URLError('test failure'))
    def test_api_failure_is_unknown(self, query, version):
        self.assertIsNone(service.check_current(Mock(game=self.game)))


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.config = service.Config(root / 'game', root / 'steamcmd.sh', root / 'state')
        self.config.game.mkdir()
        self.config.state.mkdir()
        for role in service.ROLES:
            path = self.config.game / (role + '.sh')
            path.write_text('#!/bin/sh\nexec ./srcds_run -game tf\n')
            path.chmod(0o700)
        self.config.steamcmd.touch()

    def start_case(self, current=True, update_error=None, screen_error=None):
        events = []
        def do_update(config):
            events.append('update')
            if update_error:
                raise update_error
            events.append('update-complete')
        def do_start(config, role):
            events.append('start-' + role)
            if role == 'mge' and screen_error:
                raise screen_error
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch('tf2_service.screens', return_value={}))
            stack.enter_context(patch('tf2_service.engines', return_value={}))
            stack.enter_context(patch('tf2_service.check_current', return_value=current))
            update = stack.enter_context(patch('tf2_service.update', side_effect=do_update))
            start = stack.enter_context(patch('tf2_service.start_screen', side_effect=do_start))
            stop = stack.enter_context(patch('tf2_service.stop_roles'))
            stack.enter_context(patch('tf2_service.installed_version', return_value='123'))
            if update_error or screen_error:
                with self.assertRaises(RuntimeError):
                    service.start(self.config)
            else:
                service.start(self.config)
            return events, update, start, stop

    def test_current_skips_steamcmd(self):
        events, update, start, stop = self.start_case()
        self.assertEqual(events, ['start-tf2', 'start-mge'])
        update.assert_not_called()
        stop.assert_not_called()
        self.assertFalse(json.loads((self.config.state / 'last-start.json').read_text())['steamcmd_ran'])

    def test_outdated_and_unknown_hold_both_until_update_finishes(self):
        for current in (False, None):
            with self.subTest(current=current):
                events, *_ = self.start_case(current)
                self.assertEqual(events, ['update', 'update-complete', 'start-tf2', 'start-mge'])

    def test_failed_update_starts_neither_server(self):
        events, update, start, stop = self.start_case(False, RuntimeError('update failed'))
        self.assertEqual(events, ['update'])
        start.assert_not_called()

    def test_partial_screen_launch_failure_rolls_back_both(self):
        events, update, start, stop = self.start_case(screen_error=RuntimeError('launch failed'))
        stop.assert_called_once_with(self.config, service.ROLES)

    @patch('tf2_service.screens', return_value={'tf2': 10})
    @patch('tf2_service.update')
    def test_running_screen_blocks_update_and_duplicate_start(self, update, screens):
        with self.assertRaises(RuntimeError):
            service.start(self.config)
        update.assert_not_called()

    @patch('tf2_service.screens', return_value={})
    @patch('tf2_service.engines', return_value={12: 100})
    def test_orphaned_engine_blocks_start(self, engines, screens):
        with self.assertRaises(RuntimeError):
            service.start(self.config)

    @patch('tf2_service.screens', return_value={})
    @patch('tf2_service.engines', return_value={})
    @patch('tf2_service.check_current')
    def test_legacy_autoupdate_rejected(self, current, engines, screens):
        (self.config.game / 'mge.sh').write_text('#!/bin/sh\n./srcds_run -autoupdate\n')
        with self.assertRaises(RuntimeError):
            service.start(self.config)
        current.assert_not_called()

    def fake_steamcmd(self, args, **kwargs):
        self.assertNotIn('validate', args)
        self.assertEqual(args[args.index('+app_update') + 1], '232250')
        self.assertLess(args.index('+force_install_dir'), args.index('+login'))
        kwargs['stdout'].write(b"Success! App '232250' fully installed.\n")
        return Mock(returncode=0)

    @patch('tf2_service.screens', return_value={})
    @patch('tf2_service.engines', return_value={})
    @patch('tf2_service.installed_version', return_value='123')
    @patch('tf2_service.check_current', return_value=True)
    def test_real_update_command_and_private_log(self, current, version, engines, screens):
        with patch('tf2_service.subprocess.run', side_effect=self.fake_steamcmd):
            service.update(self.config)
        logs = list(self.config.state.glob('steamcmd-*.private.log'))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)

    @patch('tf2_service.screens', return_value={})
    @patch('tf2_service.engines', return_value={})
    def test_zero_exit_without_success_marker_is_failure(self, engines, screens):
        with patch('tf2_service.subprocess.run', return_value=Mock(returncode=0)):
            with self.assertRaises(RuntimeError):
                service.update(self.config)

    @patch('tf2_service.screens', return_value={})
    @patch('tf2_service.engines', return_value={})
    @patch('tf2_service.installed_version', return_value='123')
    @patch('tf2_service.check_current', return_value=False)
    def test_still_outdated_after_update_blocks_launch(self, current, version, engines, screens):
        with patch('tf2_service.subprocess.run', side_effect=self.fake_steamcmd):
            with self.assertRaises(RuntimeError):
                service.update(self.config)

    @patch('tf2_service.screens', return_value={'tf2': 10, 'mge': 20})
    @patch('tf2_service.processes', return_value={10: (1, 100), 11: (10, 101), 20: (1, 200), 21: (20, 201)})
    @patch('tf2_service.wait_stopped', return_value={})
    @patch('tf2_service.subprocess.run')
    def test_stop_mge_targets_only_its_screen_and_descendants(self, run, wait, processes, screens):
        screens.side_effect = [{'tf2': 10, 'mge': 20}, {'tf2': 10}]
        self.assertTrue(service.stop_roles(self.config, ('mge',)))
        self.assertEqual(run.call_args.args[0], ['screen', '-S', '20.mge', '-X', 'quit'])
        self.assertEqual(wait.call_args.args[0], {20: 200, 21: 201})

    @patch('tf2_service.processes', return_value={10: (1, 999)})
    def test_recycled_pid_is_not_a_survivor(self, processes):
        self.assertEqual(service.remaining({10: 100}), {})

    def test_lock_is_exclusive_and_not_inherited(self):
        with service.lifecycle_lock(self.config):
            script = 'import fcntl,sys; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)'
            result = subprocess.run([sys.executable, '-c', script, str(self.config.state / 'lifecycle.lock')],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
        with service.lifecycle_lock(self.config):
            pass


if __name__ == '__main__':
    unittest.main()
