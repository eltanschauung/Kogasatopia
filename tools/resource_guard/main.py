import argparse
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import fcntl
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from resource_guard.collector import Collector
from resource_guard.policy import Policy
from resource_guard.storage import Publisher, Store


def stop_mge():
    # Fixed service target only: never shell commands, arbitrary PIDs, or TF2.
    try:
        active = subprocess.run(
            ["/usr/bin/systemctl", "is-active", "--quiet", "mge.service"], timeout=3)
        if active.returncode == 3:
            return "mge_already_inactive", ""
        if active.returncode != 0:
            return "mge_stop_failed", f"Status check exit {active.returncode}"
        result = subprocess.run(
            ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "stop", "mge.service"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        if result.returncode:
            return "mge_stop_failed", f"systemctl exit {result.returncode}"
        return "mge_stopped", ""
    except (OSError, subprocess.TimeoutExpired) as error:
        return "mge_stop_failed", type(error).__name__


def finish_action(store, incident_id):
    action, detail = stop_mge()
    store.action(incident_id, action, detail)
    logging.warning("Incident %s: %s", incident_id, action)


def make_event(sample, processes, history, decision):
    return {
        "incident_id": str(uuid.uuid4()), "host_name": socket.gethostname(),
        "event_name": "resource_threshold" if decision.stop_mge else "resource_pressure",
        "reasons": decision.reasons, "consecutive_samples": 2, "sample": sample,
        "processes": processes, "history": list(history),
        "action": "mge_stop_pending" if decision.stop_mge else "diagnostic_only",
        "action_detail": "",
    }


def monitor(state, config_path, interval):
    # Only one collector/action owner can use this state directory.
    with open(state / "daemon.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        store = Store(state)
        store.recover()
        policy = Policy(last_stop=store.last_stop())
        collector = Collector()
        stop = threading.Event()
        for name in (signal.SIGTERM, signal.SIGINT):
            signal.signal(name, lambda *_: stop.set())
        publisher = Publisher(store, config_path)
        db_thread = threading.Thread(target=publisher.run, args=(stop,), daemon=True)
        db_thread.start()
        history = deque(maxlen=10)
        next_sample = time.monotonic() + interval
        next_prune = 0
        logging.info("Watchdog started: interval=%ss breaches=2 CPU/RAM=95%% target=mge only", interval)
        with ThreadPoolExecutor(max_workers=1, thread_name_prefix="mge-stop") as actions:
            while not stop.wait(max(0, next_sample - time.monotonic())):
                if not db_thread.is_alive():
                    raise RuntimeError("Database worker exited unexpectedly")
                collection_start = time.monotonic()
                sample, processes = collector.sample()
                sample["scheduler_delay_seconds"] = round(max(0, collection_start - next_sample), 3)
                sample["collection_ms"] = round((time.monotonic() - collection_start) * 1000, 2)
                store.sample(sample)
                history.append({**sample, "top_cpu": sorted(processes, key=lambda row: row["cpu_pct"], reverse=True)[:3]})
                decision = policy.evaluate(sample)
                if decision:
                    event = make_event(sample, processes, history, decision)
                    store.incident(event, decision.stop_mge)
                    logging.warning("Incident %s reasons=%s action=%s",
                                    event["incident_id"], ",".join(decision.reasons), event["action"])
                    if decision.stop_mge:
                        actions.submit(finish_action, store, event["incident_id"])
                if sample["occurred_at"] >= next_prune:
                    store.prune(sample["occurred_at"])
                    next_prune = sample["occurred_at"] + 3600
                next_sample += interval
                if next_sample < time.monotonic():
                    next_sample = time.monotonic() + interval
        db_thread.join(timeout=12)
        # Unpublished rows survive shutdown and are replayed idempotently.
        if not db_thread.is_alive():
            store.close()
        logging.info("Watchdog stopped")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, default=Path.home() / "resource-guard")
    parser.add_argument("--db-config", type=Path, default=Path.home() / "hlserver/tf2/tf/addons/sourcemod/configs/databases.cfg")
    parser.add_argument("--interval", type=float, default=3.0)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--migrate", action="store_true")
    args = parser.parse_args()
    if args.interval < 1:
        parser.error("interval must be at least one second")
    os.umask(0o077)
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    if args.once:
        collector = Collector()
        time.sleep(args.interval)
        sample, processes = collector.sample()
        print(json.dumps({"sample": sample, "processes": processes}))
        return
    handler = RotatingFileHandler(args.state / "daemon.log", maxBytes=1048576, backupCount=3)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logging.basicConfig(level=logging.INFO, handlers=[handler])
    if args.migrate:
        store = Store(args.state)
        publisher = Publisher(store, args.db_config)
        publisher.connect()
        publisher.close()
        store.close()
        print("Database schema ready.")
        return
    monitor(args.state, args.db_config, args.interval)


if __name__ == "__main__":
    main()
