"""Validate exported production trigger SQL in a disposable MariaDB database.

Run the dedicated SourcePawn probe first; give this script its MySQL DDL export.
Only local root socket authentication is used, never production config/credentials.
"""
import argparse
from pathlib import Path
import re
import uuid


def exercise(db, ddl):
    c = db.cursor()
    checks = 0

    def check(ok):
        nonlocal checks
        checks += 1
        assert ok, f"Fixture assertion {checks} failed"

    def q(sql):
        c.execute(sql)

    def scalar(sql):
        q(sql)
        return c.fetchone()[0]

    q("CREATE TABLE points_store_lottery_tickets(id INTEGER PRIMARY KEY,lottery_id INTEGER,steamid64 VARCHAR(32),display_name VARCHAR(64),ticket VARCHAR(64),ticket_value INTEGER,created_at INTEGER,UNIQUE(lottery_id,steamid64)) ENGINE=InnoDB")
    q("CREATE TABLE points_store_balances(steamid64 VARCHAR(32) PRIMARY KEY,balance INTEGER) ENGINE=InnoDB")
    q("CREATE TABLE points_store_lotteries(id INTEGER PRIMARY KEY,equal_lottery INTEGER,equal_ticket_value INTEGER) ENGINE=InnoDB")
    for sql in ddl:
        q(sql)
    check(scalar("SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE()") == 3)
    check(scalar("SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='points_store_lottery_ticket_history'") == 4)
    q("INSERT INTO points_store_lotteries VALUES(17,0,0)")
    q("INSERT INTO points_store_balances VALUES('00000000000000001',900)")
    q("INSERT INTO points_store_lottery_tickets VALUES(1,17,'00000000000000001','Synthetic','FIRST',100,123)")
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='purchase' AND old_ticket_value=0 AND ticket_value=100 AND stake_delta=100 AND balance_snapshot=900") == 1)
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE CHAR_LENGTH(recorded_date)=10 AND recorded_at>0 AND steamid64='00000000000000001'") == 1)
    db.begin()
    q("UPDATE points_store_lottery_tickets SET ticket='SECOND',ticket_value=340,created_at=124 WHERE id=1")
    q("UPDATE points_store_balances SET balance=660")
    db.commit()
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='replace' AND old_ticket_value=100 AND ticket_value=340 AND stake_delta=240 AND old_created_at=123 AND ticket_created_at=124") == 1)
    db.begin()
    q("UPDATE points_store_lottery_tickets SET ticket='ROLLBACK',ticket_value=680,created_at=125 WHERE id=1")
    q("UPDATE points_store_balances SET balance=320")
    db.rollback()
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 2)
    check(scalar("SELECT ticket_value FROM points_store_lottery_tickets WHERE id=1") == 340)
    check(scalar("SELECT balance FROM points_store_balances") == 660)
    q("CREATE TRIGGER fail_journal BEFORE INSERT ON points_store_lottery_ticket_history FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='injected fixture journal failure'")
    import pymysql
    try:
        q("INSERT INTO points_store_lottery_tickets VALUES(2,17,'00000000000000002','Synthetic','FAIL',100,126)")
    except pymysql.MySQLError:
        check(True)
    else:
        check(False)
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_tickets WHERE id=2") == 0)
    q("DROP TRIGGER fail_journal")
    q("UPDATE points_store_lotteries SET equal_lottery=1,equal_ticket_value=100")
    q("CREATE TABLE receipts(award_key VARCHAR(128) PRIMARY KEY,steamid64 VARCHAR(32),amount INTEGER,reason VARCHAR(64),created_at INTEGER) ENGINE=InnoDB")
    from test_lottery_equal_sql import sql_statements
    conversion = [re.sub(r"\bbalances\b", "points_store_balances",
                        re.sub(r"\btickets\b", "points_store_lottery_tickets", sql))
                  for sql in sql_statements(100, True)]
    db.begin()
    for sql in conversion:
        q(sql)
    db.commit()
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='equal_conversion' AND old_ticket_value=340 AND ticket_value=100 AND stake_delta=-240 AND balance_snapshot=900 AND equal_lottery=1 AND equal_ticket_value=100") == 1)
    check(scalar("SELECT SUM(amount) FROM receipts WHERE reason='lottery_equal_excess_refund'") == 240)
    db.begin()
    for sql in conversion:
        q(sql)
    db.commit()
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 3)
    check(scalar("SELECT balance FROM points_store_balances") == 900)
    q("UPDATE points_store_lottery_tickets SET ticket_value=ticket_value,display_name='Renamed' WHERE id=1")
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 3)
    q("DELETE FROM points_store_lottery_tickets WHERE id=1")
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='remove' AND old_ticket_value=100 AND ticket_value=0 AND stake_delta=-100") == 1)
    check(scalar("SELECT ticket_value FROM points_store_lottery_ticket_history WHERE record_id=1") == 100)
    # Reinstallation must retain existing triggers/history rather than DROP them.
    for index, sql in enumerate(ddl):
        try:
            q(sql)
        except pymysql.MySQLError as exc:
            check(index > 0 and "already exists" in str(exc).lower())
        else:
            check(index == 0)
    check(scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 4)
    c.close()
    print(f"MariaDB: {checks} ticket journal checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mysql-export", type=Path, required=True)
    args = parser.parse_args()
    ddl = [line.strip().rstrip(";") for line in args.mysql_export.read_text().splitlines() if line.strip()]
    assert len(ddl) == 4
    assert ddl[0].startswith("CREATE TABLE IF NOT EXISTS points_store_lottery_ticket_history ")
    assert all(s.startswith("CREATE TRIGGER points_store_lotto_history_") for s in ddl[1:])
    import pymysql
    name = "codex_ticket_journal_test_" + uuid.uuid4().hex
    db = pymysql.connect(unix_socket="/run/mysqld/mysqld.sock", user="root", autocommit=True)
    try:
        with db.cursor() as c:
            c.execute("CREATE DATABASE `" + name + "`")
        db.select_db(name)
        with db.cursor() as c:
            c.execute("SELECT DATABASE()")
            assert c.fetchone()[0] == name
        exercise(db, ddl)
    finally:
        db.rollback()
        with db.cursor() as c:
            c.execute("DROP DATABASE `" + name + "`")
        db.close()
