"""Run actual history SQL templates on disposable SQLite/MariaDB fixtures.

Default: SQLite in memory. --mariadb-root-test: uniquely named throwaway DB via
local root socket authentication. No production configuration is read.
"""
import argparse
import json
from pathlib import Path
import re
import sqlite3
import uuid

SOURCE = Path(__file__).resolve().parents[2] / "tf/addons/sourcemod/scripting/points_store/leaderboard_history.sp"


def templates(mysql):
    source = SOURCE.read_text()
    formats = re.findall(r'FormatEx\(query, sizeof\(query\),\s*((?:"(?:\\.|[^"\\])*"\s*(?:\.\.\.\s*)?)+), CURRENCY_HISTORY_TABLE', source)
    formats = ["".join(json.loads(s) for s in re.findall(r'"(?:\\.|[^"\\])*"', f)) for f in formats]
    assert len(formats) == 2
    create = next(s for s in formats if s.startswith("CREATE"))
    insert = next(s for s in formats if s.startswith("INSERT"))
    indexes = re.search(r'g_IsMySql \? "(,KEY idx_balance_history_date[^"\n]+)" : ""', source).group(1)
    create = create % ("history", indexes if mysql else "")
    insert = insert % "history"
    row = json.loads(re.search(r'FormatEx\(row, sizeof\(row\), ("[^"\n]+")', source).group(1))
    suffix = re.search(r'StrCat\(query, sizeof\(query\), g_IsMySql\s*\? "([^"]+)"\s*: "([^"]+)"', source)
    return create, insert, row, suffix.group(1 if mysql else 2)


def exercise(db, mysql):
    create, insert, row, suffix = templates(mysql)
    c = db.cursor()
    c.execute(create)
    db.commit()
    checks = 0

    def archive(key, day, timestamp, add=0):
        values = [row % ("," if i > 1 else "", key, day, timestamp, 27016, f"{i:017d}", i*100+add) for i in range(1, 51)]
        c.execute(insert + "".join(values) + suffix)
        db.commit()

    def scalar(sql):
        c.execute(sql)
        return c.fetchone()[0]

    archive("first", "2026-10-22", 1000)
    assert scalar("SELECT COUNT(*) FROM history") == 50
    assert scalar("SELECT SUM(balance) FROM history") == 127500
    checks += 2
    # Retry must not rewrite a previously committed snapshot, even if caller data changed.
    archive("first", "2026-10-22", 1000, 999)
    assert scalar("SELECT COUNT(*) FROM history") == 50
    assert scalar("SELECT SUM(balance) FROM history") == 127500
    checks += 2
    # Two refreshes in the same second remain independently queryable.
    archive("second", "2026-10-22", 1000, 10)
    assert scalar("SELECT COUNT(DISTINCT snapshot_id) FROM history") == 2
    assert scalar("SELECT COUNT(*) FROM history WHERE snapshot_date='2026-10-22'") == 100
    checks += 2
    archive("third", "2026-10-25", 2000, 20)
    assert scalar("SELECT COUNT(*) FROM history WHERE snapshot_date='2026-10-25'") == 50
    assert scalar("SELECT balance FROM history WHERE snapshot_id='first' AND steamid64='00000000000000001'") == 100
    assert scalar("SELECT balance FROM history WHERE snapshot_id='third' AND steamid64='00000000000000001'") == 120
    assert scalar("SELECT COUNT(*) FROM history") == 150
    checks += 4
    c.close()
    print(f"{'MariaDB' if mysql else 'SQLite'}: {checks} full-top-50 history SQL checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mariadb-root-test", action="store_true")
    args = parser.parse_args()
    if not args.mariadb_root_test:
        with sqlite3.connect(":memory:") as db:
            exercise(db, False)
    else:
        import pymysql
        name = "codex_balance_history_test_" + uuid.uuid4().hex
        db = pymysql.connect(unix_socket="/run/mysqld/mysqld.sock", user="root")
        try:
            with db.cursor() as c:
                c.execute("CREATE DATABASE `"+name+"`")
            db.select_db(name)
            with db.cursor() as c:
                c.execute("SELECT DATABASE()")
                assert c.fetchone()[0] == name
            exercise(db, True)
        finally:
            db.rollback()
            with db.cursor() as c:
                c.execute("DROP DATABASE `"+name+"`")
            db.close()
