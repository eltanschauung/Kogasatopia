"""Offline regressions; never connects to the server or a production database."""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'tf/addons/sourcemod/scripting/points_store'
STATE = (ROOT / 'lotteries/state.inc').read_text()
DRAW = (ROOT / 'lotteries/draw.inc').read_text()
PURCHASE = (ROOT / 'lotteries/ticket_purchases.inc').read_text()
LIFECYCLE = (ROOT / 'lotteries/lifecycle_and_schema.inc').read_text()

def window_current(deadline, now):
    # Exercise the production helper's expression, rather than a second copy.
    body = STATE.split('bool IsLotteryCallWindowCurrent(',1)[1].split('}',1)[0]
    expression = body.split('return ',1)[1].split(';',1)[0]
    expression = expression.replace('&&',' and ').replace('LOTTO_CALL_WARNING_SECONDS','60')
    assert re.fullmatch(r'[a-z0-9_ <>=+()\-]+', expression)
    return eval(expression, {'__builtins__': {}}, {'deadline': deadline, 'now': now})

class LotteryWindowTests(unittest.TestCase):
    def test_only_final_minute_is_valid(self):
        self.assertTrue(window_current(1060,1000))
        self.assertTrue(window_current(1060,1059))
        self.assertTrue(window_current(1060,1060))
        self.assertFalse(window_current(1060,999))
        self.assertFalse(window_current(1060,1061))
        self.assertFalse(window_current(0,1000))
        self.assertFalse(window_current(1780,1000)) # 13 minutes early

    def test_stale_restore_clears_before_refunding(self):
        body = STATE.split('void SetActiveLottery(',1)[1].split('bool IsLotteryCallWindowCurrent',1)[0]
        self.assertLess(body.index('ResetLotteryCallState();'), body.index('BeginEqualLotteryRefunds();'))
        self.assertIn('ResumePendingLotteryCall();',body)

    def test_no_ticket_draw_clears_special_mode(self):
        body = DRAW.split('if (ticketCount <= 0 || prizePool <= 0)',1)[1].split('DataPack winnerPack',1)[0]
        self.assertIn('ResetLotteryCallState();',body)
        reset = STATE.split('void ResetLotteryCallState()',1)[1].split('void ResumePendingLotteryCall()',1)[0]
        for required in ['g_CurrentLotteryEqual = false;', 'g_CurrentLotterySuper = false;', 'g_CurrentLotteryEqualTicketValue = 0;', 'g_LotteryCallDeadline = 0;', 'PersistLotteryCallState();']:
            self.assertIn(required,reset)

    def test_reload_cleanup_keeps_all_tickets_and_balances(self):
        db=sqlite3.connect(':memory:')
        db.executescript('CREATE TABLE lotto (id INT, super_lottery INT, equal_lottery INT, equal_ticket_value INT, call_deadline INT, finished INT); INSERT INTO lotto VALUES (1,0,1,340,0,0); CREATE TABLE tickets(value INT); INSERT INTO tickets VALUES (700); CREATE TABLE balances(value INT); INSERT INTO balances VALUES (50);')
        persist = STATE.split('void PersistLotteryCallState()',1)[1].split('void ResetLotteryCallState()',1)[0]
        sql = re.search(r'"(UPDATE [^"\n]+)"',persist)[1] % ('lotto',0,0,0,0,1)
        db.execute(sql)
        self.assertEqual(db.execute('SELECT equal_lottery,equal_ticket_value,call_deadline FROM lotto').fetchone(), (0,0,0))
        self.assertEqual(db.execute('SELECT value FROM tickets').fetchone(), (700,))
        self.assertEqual(db.execute('SELECT value FROM balances').fetchone(), (50,))

    def test_bets_use_required_value_before_validation_and_spending(self):
        body = PURCHASE.split('void AttemptLotteryTicketPurchase(',1)[1]
        self.assertLess(body.index('amount = GetLotteryEqualTicketValue();'),body.index('if (amount <= 0)'))
        self.assertNotIn('amount < GetLotteryEqualTicketValue()',body)
        self.assertNotIn('Equal Lottery tickets must have',body)

    def test_one_minute_warning_and_absolute_map_deadline(self):
        self.assertIn('int callDelay = LOTTO_CALL_WARNING_SECONDS;',DRAW)
        self.assertIn('g_LotteryCallDeadline = GetTime() + callDelay;',DRAW)
        self.assertNotIn('LOTTO_MAP_CHANGE_DELAY',LIFECYCLE)
        self.assertIn('call_deadline INTEGER NOT NULL DEFAULT 0',LIFECYCLE)

if __name__ == '__main__': unittest.main()
