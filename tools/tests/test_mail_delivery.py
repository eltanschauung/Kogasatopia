"""Exercise the actual mail insertion SQL without touching production mail."""
import pathlib
import re
import sqlite3
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "tf/addons/sourcemod/scripting/server_mail/delivery.sp").read_text()
MAIL = "test_mail_delivery"
BANS = "test_mail_delivery_bans"
COLUMNS = """
mail_id INTEGER PRIMARY KEY AUTOINCREMENT,
sender_steamid64 TEXT, sender_name TEXT, receiver_steamid64 TEXT,
receiver_name TEXT, created_at INTEGER, title TEXT, contents TEXT,
gems INTEGER, gems_redeemed INTEGER, attachment_type TEXT,
attachment_redeemed INTEGER, expires_at INTEGER, read_at INTEGER,
idempotency_key TEXT UNIQUE, delivery_suppressed INTEGER DEFAULT 0
"""


def insert_sql(mysql, sender="sender", receiver="receiver", key="request"):
    blocks = re.findall(r'FormatEx\(query, sizeof\(query\),\s*((?:"[^"]*"\s*(?:\.\.\.\s*)?)+)\s*,\s*MAIL_TABLE,', SOURCE)
    template = next("".join(re.findall(r'"([^"]*)"', block)) for block in blocks
                    if ("INSERT INTO" if mysql else "INSERT OR IGNORE INTO") in block)
    return template % (MAIL, sender, "Sender", receiver, "Receiver", 1234,
                       "Title", "Contents", 7, "rtd", 0, "'" + key + "'",
                       BANS, sender, receiver)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("CREATE TABLE " + MAIL + " (" + COLUMNS + ")")
        self.db.execute("CREATE TABLE " + BANS + " (steamid64 TEXT PRIMARY KEY)")

    def tearDown(self):
        self.db.close()

    def check_delivery(self, banned, expected):
        for steam in banned:
            self.db.execute("INSERT INTO " + BANS + " VALUES (?)", (steam,))
        self.db.execute(insert_sql(False))
        self.assertEqual(self.db.execute("SELECT delivery_suppressed FROM " + MAIL).fetchone()[0], expected)
        self.assertEqual(self.db.execute("SELECT count(*) FROM " + MAIL +
                         " WHERE receiver_steamid64='receiver' AND delivery_suppressed=0").fetchone()[0], 1 - expected)
        self.assertEqual(self.db.execute("SELECT count(*) FROM " + MAIL +
                         " WHERE sender_steamid64='sender'").fetchone()[0], 1)

    def test_normal_delivery(self):
        self.check_delivery([], 0)

    def test_banned_sender(self):
        self.check_delivery(["sender"], 1)

    def test_banned_receiver(self):
        self.check_delivery(["receiver"], 1)

    def test_both_banned(self):
        self.check_delivery(["sender", "receiver"], 1)

    def test_unban_does_not_release_suppressed_mail(self):
        self.check_delivery(["receiver"], 1)
        self.db.execute("DELETE FROM " + BANS)
        self.db.execute(insert_sql(False, key="request"))
        self.db.execute(insert_sql(False, key="new_request"))
        self.assertEqual(self.db.execute("SELECT delivery_suppressed FROM " + MAIL +
                         " ORDER BY mail_id").fetchall(), [(1,), (0,)])

    def test_server_originated_mail(self):
        self.db.execute("INSERT INTO " + BANS + " VALUES ('receiver')")
        self.db.execute(insert_sql(False, sender=""))
        self.assertEqual(self.db.execute("SELECT delivery_suppressed FROM " + MAIL).fetchone()[0], 1)


def check_mysql():
    columns = COLUMNS.replace("INTEGER PRIMARY KEY AUTOINCREMENT", "INTEGER PRIMARY KEY AUTO_INCREMENT").replace("TEXT UNIQUE", "VARCHAR(128) UNIQUE")
    sql = "CREATE TEMPORARY TABLE " + MAIL + " (" + columns + ");"
    sql += "CREATE TEMPORARY TABLE " + BANS + " (steamid64 VARCHAR(32) PRIMARY KEY);"
    for i, banned in enumerate([[], ["sender"], ["receiver"], ["sender", "receiver"]]):
        sql += "DELETE FROM " + BANS + ";"
        for steam in banned:
            sql += "INSERT INTO " + BANS + " VALUES ('" + steam + "');"
        sql += insert_sql(True, key=str(i)) + ";"
        sql += "SELECT delivery_suppressed FROM " + MAIL + " WHERE idempotency_key='" + str(i) + "';"
    sql += insert_sql(True, key="3") + ";SELECT count(*) FROM " + MAIL + ";"
    output = subprocess.check_output(["sudo", "-n", "mysql", "-N", "sourcemod"], input=sql, text=True)
    assert output.split() == ["0", "1", "1", "1", "4"], output
    print("MariaDB temporary-table delivery and idempotency checks passed.")


if __name__ == "__main__":
    if "--mysql" in sys.argv:
        sys.argv.remove("--mysql")
        check_mysql()
    unittest.main()
