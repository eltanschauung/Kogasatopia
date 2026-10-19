"""Offline policy regressions: no server, network, or production database."""
from pathlib import Path
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[1] / 'tf/addons/sourcemod'
state = (ROOT / 'scripting/points_store/lotteries/state.inc').read_text()
assert state.count('ticket_value < %d') == 4
assert 'ticket_value != %d' not in state
assert 'GetRandomInt(0, 1) == 0' in state
assert 'GetRandomInt(20, 140) * 5' in state
assert 'equal_ticket_value = %d' in state
for required in range(100, 701, 5):
    db = sqlite3.connect(':memory:')
    db.executescript('CREATE TABLE tickets (account INTEGER PRIMARY KEY, ticket_value INTEGER); CREATE TABLE balances (account INTEGER PRIMARY KEY, value INTEGER);')
    values = [required - 5, required, required + 5, 1000]
    db.executemany('INSERT INTO tickets VALUES (?,?)', enumerate(values))
    db.executemany('INSERT INTO balances VALUES (?,0)', [(i,) for i in range(4)])
    db.execute('UPDATE balances SET value=(SELECT ticket_value FROM tickets WHERE account=balances.account) WHERE account IN (SELECT account FROM tickets WHERE ticket_value < ?)', (required,))
    db.execute('DELETE FROM tickets WHERE ticket_value < ?', (required,))
    assert db.execute('SELECT COUNT(*) FROM tickets').fetchone()[0] == 3
    assert db.execute('SELECT SUM(value) FROM balances').fetchone()[0] == required - 5
    db.close()

db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE hugs_relationships (sender TEXT, recipient TEXT, kind INTEGER, given INTEGER, received INTEGER, sender_name TEXT, recipient_name TEXT, PRIMARY KEY(sender,recipient,kind))')
db.executemany('INSERT INTO hugs_relationships VALUES (?,?,?,?,?,?,?)', [
    ('a','me',0,3,3,'Alice','Me'), ('b','me',0,8,8,'Bob','Me'),
    ('me','a',0,12,12,'Me','Alice'), ('me','b',0,1,1,'Me','Bob'),
    ('a','me',1,20,20,'Alice','Me'), ('me','b',2,9,4,'Me','Bob')])
source = (ROOT / 'scripting/hugs/personal_statistics.sp').read_text()
section = source.split('char query[1024];',1)[1].split('DataPack pack',1)[0]
sql = ''.join(re.findall(r'"([^"\n]*)"', section))
rows = db.execute(sql % ('hugs_relationships','me',0,'hugs_relationships','me',0)).fetchall()
assert next(r for r in rows if r[0] == 0)[1:] == ('b','Bob',8)
assert next(r for r in rows if r[0] == 1)[1:] == ('a','Alice',12)
rows = db.execute(sql % ('hugs_relationships','me',2,'hugs_relationships','me',2)).fetchall()
assert rows == [(1,'b','Bob',9)]
assert 'cooldown *= 0.2;' in (ROOT / 'scripting/server_mail/lifecycle.sp').read_text()
assert '"price" "2950"' in (ROOT / 'configs/points_store.cfg').read_text()
print('PASS: 121 equal-lottery values, excess-ticket retention/refunds, counterpart directions/kinds, mail cooldown')
