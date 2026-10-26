"""Exercise production normalization SQL on isolated SQLite/MariaDB fixtures.

Default mode uses in-memory SQLite. --mariadb-root-test creates a uniquely named
temporary database through local socket root authentication and drops only that
database afterward. It never reads server connection config or selects production.
"""
import argparse
import json
from pathlib import Path
import re
import sqlite3
import uuid

SOURCE = Path(__file__).resolve().parents[2] / "tf/addons/sourcemod/scripting/points_store/lotteries/state.inc"


def sql_statements(required, mysql):
    source = SOURCE.read_text().split("public void SQL_OnEqualLotteryInvalidTicketsLoaded(", 1)[1]
    source = source.split("public void SQLTxn_OnEqualLotteryTicketsRefunded(", 1)[0]
    formats = re.findall(r'FormatEx\(query, sizeof\(query\),\s*((?:"(?:\\.|[^"\\])*"\s*(?:\.\.\.\s*)?)+),\s*(.*?)\);', source, re.S)
    assert len(formats) == 5, "Review fixture extraction if transaction structure changes"
    receipt = ("CONCAT('lotto_equal:',lottery_id,':',id,':',created_at,':',ticket_value,':',%d)" if mysql else
               "'lotto_equal:'||lottery_id||':'||id||':'||created_at||':'||ticket_value||':%d'") % required
    values = {"BP_IDEMPOTENT_AWARDS_TABLE":"receipts", "BP_BALANCE_TABLE":"balances", "LOTTO_TICKET_TABLE":"tickets",
              "receiptKey":receipt, "requiredValue":required, "GetTime()":1000, "lotteryId":17}
    result = []
    for index in (0, 1 if mysql else 2, 3, 4):
        strings, args = formats[index]
        template = "".join(json.loads(s) for s in re.findall(r'"(?:\\.|[^"\\])*"', strings))
        result.append(template % tuple(values[a.strip()] for a in args.split(",")))
    return result


def exercise(db, mysql):
    checks = 0
    cursor = db.cursor()
    cursor.execute("CREATE TABLE balances (steamid64 VARCHAR(32) PRIMARY KEY,balance INTEGER,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
    cursor.execute("CREATE TABLE tickets (id INTEGER PRIMARY KEY,lottery_id INTEGER,steamid64 VARCHAR(32),ticket VARCHAR(64),ticket_value INTEGER,created_at INTEGER)")
    cursor.execute("CREATE TABLE receipts (award_key VARCHAR(128) PRIMARY KEY,steamid64 VARCHAR(32),amount INTEGER,reason VARCHAR(64),created_at INTEGER)")
    db.commit()
    for required in (100, 340, 680):
        for table in ("receipts", "tickets", "balances"):
            cursor.execute("DELETE FROM " + table)
        cursor.execute("INSERT INTO balances (steamid64,balance) VALUES ('low',50),('high',50),('exact',50)")
        cursor.execute(f"INSERT INTO tickets VALUES (1,17,'low','LOW',10,123),(2,17,'high','UNCHANGED',1000,123),(3,17,'exact','EXACT',{required},123),(4,17,'offline','OFFLINE',2000,123),(5,18,'high','OTHER',2000,123)")
        db.commit()

        def scalar(sql):
            cursor.execute(sql)
            return cursor.fetchone()[0]

        def wealth():
            return scalar("SELECT COALESCE(SUM(balance),0) FROM balances") + scalar("SELECT SUM(ticket_value) FROM tickets WHERE lottery_id=17")

        initial = wealth()
        statements = sql_statements(required, mysql)
        # Injected failure after receipts/credits must roll everything back.
        cursor.execute("BEGIN")
        for sql in statements[:2]:
            cursor.execute(sql)
        db.rollback()
        assert wealth() == initial and scalar("SELECT COUNT(*) FROM receipts") == 0
        checks += 1
        db.commit()
        for repetition in range(2):
            cursor.execute("BEGIN")
            for sql in statements:
                cursor.execute(sql)
            db.commit()
            assert wealth() == initial
            assert scalar("SELECT balance FROM balances WHERE steamid64='high'") == 50+1000-required
            assert scalar("SELECT balance FROM balances WHERE steamid64='offline'") == 2000-required
            assert scalar("SELECT balance FROM balances WHERE steamid64='low'") == 60
            assert scalar("SELECT COUNT(*) FROM receipts") == 3
            assert scalar("SELECT SUM(ticket_value) FROM tickets WHERE lottery_id=17") == required*3
            assert scalar("SELECT COUNT(*) FROM tickets WHERE id=2 AND ticket='UNCHANGED' AND created_at=123") == 1
            assert scalar("SELECT ticket_value FROM tickets WHERE id=5") == 2000
            checks += 8
            db.commit()
    cursor.close()
    print(f"{'MariaDB' if mysql else 'SQLite'}: {checks} SQL conservation/refund/retry/rollback checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mariadb-root-test", action="store_true")
    args = parser.parse_args()
    if not args.mariadb_root_test:
        with sqlite3.connect(":memory:") as db:
            db.create_function("GREATEST", -1, max)
            exercise(db, False)
    else:
        import pymysql
        name = "codex_lotto_refund_test_" + uuid.uuid4().hex
        db = pymysql.connect(unix_socket="/run/mysqld/mysqld.sock", user="root")
        try:
            with db.cursor() as cursor:
                cursor.execute("CREATE DATABASE `"+name+"`")
            db.select_db(name)
            with db.cursor() as cursor:
                cursor.execute("SELECT DATABASE()")
                assert cursor.fetchone()[0] == name
            exercise(db, True)
        finally:
            db.rollback()
            with db.cursor() as cursor:
                cursor.execute("DROP DATABASE `"+name+"`")
            db.close()
