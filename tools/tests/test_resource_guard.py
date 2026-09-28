import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

import vdf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from resource_guard.collector import Collector, busy, rate
from resource_guard.main import make_event, stop_mge
from resource_guard.policy import Decision, Policy
from resource_guard.storage import Publisher, Store, database_settings


def sample(timestamp=1000, **changes):
    return {
        "occurred_at": timestamp, "interval_seconds": 3, "cpu_pct": 0,
        "memory_pct": 0, "max_core_pct": 0, "iowait_pct": 0, "steal_pct": 0,
        "swap_pct": 0, "disk_pct": 0, **changes,
    }


class PolicyTests(unittest.TestCase):
    def test_four_high_samples_to_stop(self):
        policy = Policy()
        self.assertIsNone(policy.evaluate(sample(cpu_pct=95)))
        decision = policy.evaluate(sample(1003, cpu_pct=95))
        self.assertFalse(decision.stop_mge)
        self.assertEqual(decision.required_samples, 2)
        self.assertIsNone(policy.evaluate(sample(1006, cpu_pct=95)))
        decision = policy.evaluate(sample(1009, cpu_pct=95))
        self.assertTrue(decision.stop_mge)
        self.assertEqual(decision.required_samples, 4)

    def test_alternating_cpu_and_memory(self):
        policy = Policy()
        self.assertIsNone(policy.evaluate(sample(cpu_pct=95)))
        self.assertIsNone(policy.evaluate(sample(1003, memory_pct=95)))
        self.assertIsNone(policy.evaluate(sample(1006, cpu_pct=95)))
        decision = policy.evaluate(sample(1009, memory_pct=95))
        self.assertTrue(decision.stop_mge)
        self.assertIn("cpu_or_memory_pct", decision.reasons)

    def test_healthy_resets(self):
        policy = Policy()
        policy.evaluate(sample(cpu_pct=95))
        self.assertIsNone(policy.evaluate(sample(1003)))
        self.assertIsNone(policy.evaluate(sample(1006, memory_pct=95)))

    def test_diagnostics_never_stop(self):
        for reason, value in (("max_core_pct", 98), ("iowait_pct", 20), ("steal_pct", 10)):
            policy = Policy()
            policy.evaluate(sample(**{reason: value}))
            decision = policy.evaluate(sample(1003, **{reason: value}))
            self.assertFalse(decision.stop_mge)
            self.assertIn(reason, decision.reasons)

    def test_cooldown_survives_restarts(self):
        policy = Policy(last_stop=990)
        for timestamp in (1000, 1003, 1006, 1009):
            decision = policy.evaluate(sample(timestamp, cpu_pct=100))
            self.assertTrue(decision is None or not decision.stop_mge)
        self.assertTrue(policy.evaluate(sample(1290, cpu_pct=100)).stop_mge)

    def test_swap_disk_do_not_stop(self):
        policy = Policy()
        policy.evaluate(sample(swap_pct=99, disk_pct=99))
        self.assertIsNone(policy.evaluate(sample(1003, swap_pct=99, disk_pct=99)))

    def test_interval_rates_and_counter_reset(self):
        self.assertEqual(rate(130, 100, 3), 10)
        self.assertEqual(rate(10, 100, 3), 0)
        self.assertEqual(rate(100, None, 3), 0)


class CollectorTests(unittest.TestCase):
    @patch("resource_guard.collector.unit_for", return_value="mge.service")
    @patch("resource_guard.collector.psutil.process_iter")
    def test_interval_delta_and_pid_reuse(self, process_iter, _unit):
        proc = MagicMock()
        proc.pid = 42
        proc.create_time.return_value = 100
        proc.cpu_times.return_value = Mock(user=1.6, system=0)
        proc.memory_info.return_value.rss = 1024
        proc.name.return_value = "srcds_linux"
        proc.num_threads.return_value = 2
        proc.io_counters.return_value = Mock(read_bytes=130, write_bytes=100)
        process_iter.return_value = [proc]
        collector = Collector.__new__(Collector)
        collector.previous = {(42, 100): (1.0, 100, 100)}
        row = collector.processes(3)[0]
        self.assertEqual(row["cpu_pct"], 20)
        self.assertEqual(row["read_bps"], 10)
        self.assertNotIn("cmdline", row)
        proc.create_time.return_value = 200
        row = collector.processes(3)[0]
        self.assertEqual(row["cpu_pct"], 0)
        self.assertEqual(row["read_bps"], 0)

    def test_wait_and_steal_are_not_computational_cpu(self):
        self.assertEqual(busy(Mock(idle=10, iowait=20, steal=30)), 40)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(self.temp.name)
        policy = Policy()
        for timestamp in (1000, 1003, 1006):
            policy.evaluate(sample(timestamp, cpu_pct=100))
        decision = policy.evaluate(sample(1009, cpu_pct=100))
        self.event = make_event(sample(1009, cpu_pct=100), [], [], decision)
        self.assertEqual(self.event["consecutive_samples"], 4)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_db_failure_retains_pending(self):
        self.store.incident(self.event)
        publisher = Publisher(self.store, "/unused")
        publisher.publish = Mock(side_effect=OSError("offline"))
        with self.assertRaises(OSError):
            publisher.flush()
        self.assertEqual(len(self.store.pending()), 1)

    def test_ack_cannot_hide_newer_action(self):
        self.store.incident(self.event, stop=True)
        old, revision = self.store.pending()[0]
        self.store.action(old["incident_id"], "mge_stopped")
        self.store.acknowledge(old["incident_id"], revision)
        self.assertEqual(self.store.pending()[0][0]["action"], "mge_stopped")
        self.assertEqual(self.store.last_stop(), 1009)

    def test_recovery_does_not_repeat_stop(self):
        self.store.incident(self.event, stop=True)
        self.store.recover()
        self.assertEqual(self.store.pending()[0][0]["action"], "interrupted_no_retry")

    def test_retention_keeps_unpublished(self):
        self.store.incident(self.event)
        self.store.sample(sample())
        self.store.prune(1000000)
        self.assertEqual(len(self.store.pending()), 1)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 0)
        event, revision = self.store.pending()[0]
        self.store.acknowledge(event["incident_id"], revision)
        self.store.prune(1000000)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM incidents").fetchone()[0], 0)

    def test_replay_uses_same_id(self):
        self.store.incident(self.event)
        publisher = Publisher(self.store, "/unused")
        publisher.publish = Mock()
        publisher.flush()
        self.assertEqual(publisher.publish.call_args.args[0]["incident_id"], self.event["incident_id"])
        publisher.flush()
        self.assertEqual(publisher.publish.call_count, 1)

    def test_sql_is_parameterized(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        publisher = Publisher(self.store, "/unused")
        publisher.connection = connection
        event = {**self.event, "host_name": "'; DROP TABLE anything; --"}
        publisher.publish(event)
        query, values = cursor.execute.call_args.args
        self.assertNotIn(event["host_name"], query)
        self.assertIn(event["host_name"], values)

    def test_keyvalues_config_quotes(self):
        config = Path(self.temp.name) / "databases.cfg"
        config.write_text(vdf.dumps({"Databases": {"driver_default": "mysql", "default": {
            "host": "127.0.0.1", "user": "test", "pass": "a//b", "database": "test",
        }}}))
        self.assertEqual(database_settings(config)["password"], "a//b")


class ActionTests(unittest.TestCase):
    @patch("resource_guard.main.subprocess.run")
    def test_only_mge_service_is_stopped(self, run):
        run.return_value.returncode = 0
        self.assertEqual(stop_mge()[0], "mge_stopped")
        self.assertEqual(run.call_args_list[-1].args[0],
                         ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "stop", "mge.service"])

    @patch("resource_guard.main.subprocess.run")
    def test_inactive_has_no_stop(self, run):
        run.return_value.returncode = 3
        self.assertEqual(stop_mge()[0], "mge_already_inactive")
        self.assertEqual(run.call_count, 1)

    @patch("resource_guard.main.subprocess.run")
    def test_stop_failure_recorded(self, run):
        run.side_effect = [Mock(returncode=0), Mock(returncode=1)]
        self.assertEqual(stop_mge()[0], "mge_stop_failed")


@unittest.skipUnless(os.environ.get("RESOURCE_GUARD_DB_TEST") == "1", "Opt-in live database test")
class DatabaseIntegrationTests(unittest.TestCase):
    def test_roundtrip_replay_and_action_update(self):
        with tempfile.TemporaryDirectory() as state:
            store = Store(state)
            publisher = Publisher(store, Path.home() / "hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg")
            event = make_event(sample(), [{
                "pid": 1, "started_at": 1.0, "name": "resource_guard_test",
                "unit": "test.service", "threads": 1, "rss_bytes": 1024,
                "cpu_pct": 1.5, "read_bps": None, "write_bps": 5,
            }], [], Decision(("deployment_probe",), False))
            event["event_name"] = "deployment_probe"
            event["action"] = "test_no_stop"
            connection = publisher.connect()
            try:
                store.incident(event)
                publisher.flush()
                publisher.publish(event)  # Repeated delivery must not duplicate.
                store.action(event["incident_id"], "test_action_updated")
                publisher.flush()
                with connection.cursor() as cursor:
                    cursor.execute("SELECT action FROM resource_guard_incidents WHERE incident_id=%s",
                                   (event["incident_id"],))
                    self.assertEqual(cursor.fetchall(), (("test_action_updated",),))
                    cursor.execute("SELECT process_name,read_bytes_per_second "
                                   "FROM resource_guard_incident_processes WHERE incident_id=%s",
                                   (event["incident_id"],))
                    self.assertEqual(cursor.fetchall(), (("resource_guard_test", None),))
                self.assertEqual(store.pending(), [])
            finally:
                with connection.cursor() as cursor:
                    cursor.execute("DELETE FROM resource_guard_incidents WHERE incident_id=%s",
                                   (event["incident_id"],))
                connection.commit()
                publisher.close()
                store.close()


if __name__ == "__main__":
    unittest.main()
