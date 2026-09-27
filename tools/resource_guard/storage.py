import json
import logging
import sqlite3
import threading
import time
from pathlib import Path

import pymysql
import vdf


def database_settings(path):
    with open(path, encoding="utf-8") as handle:
        config = vdf.load(handle)["Databases"]["default"]
    if config.get("driver", "mysql").lower() not in ("mysql", "default"):
        raise ValueError("SourceMod default database must use MySQL")
    return {
        "host": config.get("host", "localhost"),
        "port": int(config.get("port", "3306") or "3306"),
        "user": config["user"], "password": config.get("pass", ""),
        "database": config["database"], "charset": "utf8mb4",
        "connect_timeout": 3, "read_timeout": 3, "write_timeout": 3,
        "autocommit": False,
    }


class Store:
    """Small local journal; MySQL outages never block the sampling loop."""

    def __init__(self, state):
        self.lock = threading.RLock()
        self.db = sqlite3.connect(Path(state) / "journal.sqlite3", check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS samples (occurred_at INTEGER, payload TEXT);
            CREATE INDEX IF NOT EXISTS samples_time ON samples(occurred_at);
            CREATE TABLE IF NOT EXISTS incidents (
                id TEXT PRIMARY KEY, occurred_at INTEGER, payload TEXT,
                revision INTEGER NOT NULL DEFAULT 1, sent_revision INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        """)
        self.db.commit()

    def close(self):
        self.db.close()

    def last_stop(self):
        row = self.db.execute("SELECT value FROM metadata WHERE name='last_stop'").fetchone()
        return int(row[0]) if row else 0

    def sample(self, row):
        with self.lock, self.db:
            self.db.execute("INSERT INTO samples VALUES (?,?)",
                            (row["occurred_at"], json.dumps(row)))

    def incident(self, event, stop=False):
        with self.lock, self.db:
            self.db.execute("INSERT INTO incidents(id,occurred_at,payload) VALUES (?,?,?)",
                            (event["incident_id"], event["sample"]["occurred_at"], json.dumps(event)))
            if stop:
                self.db.execute("INSERT OR REPLACE INTO metadata VALUES ('last_stop',?)",
                                (str(event["sample"]["occurred_at"]),))

    def action(self, incident_id, action, detail=""):
        with self.lock, self.db:
            row = self.db.execute("SELECT payload FROM incidents WHERE id=?", (incident_id,)).fetchone()
            if not row:
                return
            event = json.loads(row[0])
            event["action"], event["action_detail"] = action, detail[:255]
            self.db.execute("UPDATE incidents SET payload=?,revision=revision+1 WHERE id=?",
                            (json.dumps(event), incident_id))

    def recover(self):
        for event, _ in self.pending():
            if event["action"] == "mge_stop_pending":
                self.action(event["incident_id"], "interrupted_no_retry",
                            "Daemon restarted; stale stop request not replayed")

    def pending(self):
        with self.lock:
            rows = self.db.execute(
                "SELECT payload,revision FROM incidents WHERE revision>sent_revision ORDER BY occurred_at LIMIT 50"
            ).fetchall()
            return [(json.loads(row[0]), row[1]) for row in rows]

    def acknowledge(self, event_id, revision):
        with self.lock, self.db:
            self.db.execute("UPDATE incidents SET sent_revision=? WHERE id=? AND revision=?",
                            (revision, event_id, revision))

    def prune(self, now):
        with self.lock, self.db:
            self.db.execute("DELETE FROM samples WHERE occurred_at<?", (now - 86400,))
            self.db.execute(
                "DELETE FROM incidents WHERE occurred_at<? AND sent_revision=revision", (now - 7 * 86400,))
            # Unpublished incidents are never discarded.


class Publisher:
    def __init__(self, store, config_path):
        self.store = store
        self.config_path = config_path
        self.connection = None

    def connect(self):
        if self.connection is None:
            connection = pymysql.connect(**database_settings(self.config_path))
            try:
                with connection.cursor() as cursor:
                    for statement in Path(__file__).with_name("schema.sql").read_text().split(";"):
                        if statement.strip():
                            cursor.execute(statement)
                connection.commit()
            except Exception:
                connection.close()
                raise
            self.connection = connection
        return self.connection

    def close(self):
        if self.connection:
            self.connection.close()
            self.connection = None

    def publish(self, event):
        conn = self.connect()
        sample = event["sample"]
        columns = (
            "incident_id", "host_name", "occurred_at", "event_name", "reasons",
            "sample_interval_seconds", "consecutive_samples", "cpu_pct", "max_core_pct",
            "memory_pct", "iowait_pct", "steal_pct", "swap_pct", "disk_pct", "action",
            "action_detail", "evidence_json", "created_at", "updated_at",
        )
        now = int(time.time())
        values = (
            event["incident_id"], event["host_name"], sample["occurred_at"], event["event_name"],
            ",".join(event["reasons"]), sample["interval_seconds"], event["consecutive_samples"],
            sample["cpu_pct"], sample["max_core_pct"], sample["memory_pct"], sample["iowait_pct"],
            sample["steal_pct"], sample["swap_pct"], sample["disk_pct"], event["action"],
            event.get("action_detail", ""), json.dumps({"sample": sample, "history": event["history"]}),
            sample["occurred_at"], now,
        )
        with conn.cursor() as cursor:
            cursor.execute(
                f"INSERT INTO resource_guard_incidents ({','.join(columns)}) "
                f"VALUES ({','.join(['%s'] * len(columns))}) ON DUPLICATE KEY UPDATE "
                + ",".join(f"{column}=VALUES({column})" for column in columns[1:] if column != "created_at"),
                values,
            )
            cursor.executemany("""
                INSERT INTO resource_guard_incident_processes
                (incident_id,pid,process_started_at,process_name,systemd_unit,cpu_pct,rss_bytes,
                 read_bytes_per_second,write_bytes_per_second,threads)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE process_started_at=VALUES(process_started_at),
                process_name=VALUES(process_name),systemd_unit=VALUES(systemd_unit),
                cpu_pct=VALUES(cpu_pct),rss_bytes=VALUES(rss_bytes),
                read_bytes_per_second=VALUES(read_bytes_per_second),
                write_bytes_per_second=VALUES(write_bytes_per_second),threads=VALUES(threads)
            """, [(event["incident_id"], row["pid"], row["started_at"], row["name"], row["unit"],
                   row["cpu_pct"], row["rss_bytes"], row["read_bps"], row["write_bps"], row["threads"])
                  for row in event["processes"]])
        conn.commit()

    def flush(self):
        for event, revision in self.store.pending():
            self.publish(event)
            self.store.acknowledge(event["incident_id"], revision)

    def run(self, stop):
        retry = 3
        while not stop.is_set():
            try:
                self.connect()
                self.flush()
                retry = 3
            except (OSError, ValueError, KeyError, SyntaxError, sqlite3.Error, pymysql.MySQLError) as error:
                # Don't put database credentials or process command lines in logs.
                logging.warning("Database unavailable (%s); incidents remain queued locally", type(error).__name__)
                self.close()
                retry = min(retry * 2, 60)
            stop.wait(retry)
        self.close()
