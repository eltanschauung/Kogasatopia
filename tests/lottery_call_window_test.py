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
LOTTERIES = (ROOT / 'lotteries.inc').read_text()
EMPTY_RETRY_SECONDS = int(re.search(r'#define LOTTO_EMPTY_RETRY_SECONDS (\d+)', LOTTERIES)[1])

def window_current(deadline, now):
    # Exercise the production helper's expression, rather than a second copy.
    body = STATE.split('bool IsLotteryCallWindowCurrent(',1)[1].split('}',1)[0]
    expression = body.split('return ',1)[1].split(';',1)[0]
    expression = expression.replace('&&',' and ').replace('LOTTO_CALL_WARNING_SECONDS','60')
    assert re.fullmatch(r'[a-z0-9_ <>=+()\-]+', expression)
    return eval(expression, {'__builtins__': {}}, {'deadline': deadline, 'now': now})

def schedule_current(deadline, now, special_lottery=False):
    body = STATE.split('bool IsLotteryCallScheduleCurrent(',1)[1].split('void PersistLotteryCallState()',1)[0]
    if special_lottery:
        assert 'return IsLotteryCallWindowCurrent(deadline, now);' in body
        return window_current(deadline, now)
    expression = body.rsplit('return ',1)[1].split(';',1)[0]
    expression = expression.replace('&&',' and ').replace('LOTTO_EMPTY_RETRY_SECONDS', str(EMPTY_RETRY_SECONDS))
    assert re.fullmatch(r'[a-z0-9_ <>=+()\-]+', expression)
    return eval(expression, {'__builtins__': {}}, {'deadline': deadline, 'now': now})

def empty_draw_body():
    return DRAW.split('if (ticketCount <= 0 || prizePool <= 0)',1)[1].split('DataPack winnerPack',1)[0]

def persist_sql(deadline):
    body = STATE.split('void PersistLotteryCallState()',1)[1].split('void ResetLotteryCallState(',1)[0]
    return re.search(r'"(UPDATE [^"\n]+)"',body)[1] % ('lotto',0,0,0,deadline,1)

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
        body = empty_draw_body()
        self.assertIn('ResetLotteryCallState(GetTime() + LOTTO_EMPTY_RETRY_SECONDS);',body)
        reset = STATE.split('void ResetLotteryCallState(',1)[1].split('void ResumePendingLotteryCall()',1)[0]
        for required in ['g_CurrentLotteryEqual = false;', 'g_CurrentLotterySuper = false;', 'g_CurrentLotteryEqualTicketValue = 0;', 'g_LotteryCallDeadline = nextDeadline;', 'PersistLotteryCallState();']:
            self.assertIn(required,reset)

    def test_empty_draw_silently_retries_in_five_minutes(self):
        body = empty_draw_body()
        self.assertEqual(EMPTY_RETRY_SECONDS,300)
        self.assertIn('g_LotteryDrawInProgress = false;',body)
        self.assertIn('ResumePendingLotteryCall();',body)
        self.assertNotRegex(body,r'Reply|CPrint|PrintTo|LogMessage|GetRandom|Command_DoLottery')
        callback = DRAW.split('public Action Timer_LotteryCall(',1)[1].split('public Action Timer_RetryStartLotteryDraw(',1)[0]
        self.assertIn('StartLotteryDraw(requesterUserId, lotteryId);',callback)
        self.assertNotRegex(callback,r'CPrint|GetRandom|Command_DoLottery')

    def test_repeated_empty_draws_keep_same_lottery_and_deadline(self):
        db=sqlite3.connect(':memory:')
        db.executescript('CREATE TABLE lotto (id INT, super_lottery INT, equal_lottery INT, equal_ticket_value INT, call_deadline INT, finished INT); INSERT INTO lotto VALUES (1,0,1,340,0,0); CREATE TABLE tickets(value INT); CREATE TABLE balances(value INT); INSERT INTO balances VALUES (50);')
        expression = re.search(r'ResetLotteryCallState\((.+)\);',empty_draw_body())[1]
        expression = expression.replace('GetTime()', 'now').replace('LOTTO_EMPTY_RETRY_SECONDS', str(EMPTY_RETRY_SECONDS))
        self.assertRegex(expression,r'^now \+ 300$')
        now=1000
        for _ in range(4):
            deadline=eval(expression,{'__builtins__': {}},{'now':now})
            db.execute(persist_sql(deadline))
            self.assertEqual(deadline-now,300)
            self.assertEqual(db.execute('SELECT * FROM lotto').fetchone(),(1,0,0,0,deadline,0))
            self.assertEqual(db.execute('SELECT COUNT(*) FROM tickets').fetchone(),(0,))
            self.assertEqual(db.execute('SELECT value FROM balances').fetchone(),(50,))
            now=deadline
        db.close()

    def test_retry_restores_without_extending_special_window(self):
        self.assertTrue(schedule_current(1300,1000))
        self.assertTrue(schedule_current(1300,1250))
        self.assertTrue(schedule_current(1300,1300))
        self.assertTrue(schedule_current(1300,1400)) # overdue retry runs next second
        self.assertFalse(schedule_current(1301,1000))
        self.assertFalse(schedule_current(0,1000))
        self.assertFalse(schedule_current(1300,1000,True))
        self.assertTrue(schedule_current(1060,1000,True))
        self.assertFalse(schedule_current(1060,1061,True))
        resume = STATE.split('void ResumePendingLotteryCall()',1)[1].split('void SetCurrentLotterySuper(',1)[0]
        self.assertIn('IsLotteryCallScheduleCurrent(',resume)
        self.assertIn('remaining > 0 ? remaining : 1',resume)
        self.assertNotRegex(resume,r'CPrint|GetRandom|Command_DoLottery')

    def test_scheduled_cron_calls_are_silent_and_cannot_reroll(self):
        for condition,following in [('g_LotteryCallTimer != null','if (g_LotteryDrawInProgress)'),('g_LotteryDrawInProgress','if (g_LotteryCallDeadline')]:
            body = DRAW.split(f'if ({condition})',1)[1].split(following,1)[0]
            self.assertRegex(body,r'if \(client > 0\)\s*\{\s*ReplyToCommand')
            self.assertIn('return Plugin_Handled;',body)
            self.assertNotRegex(body,r'GetRandom|CPrint|CreateTimer')

    def test_reload_cleanup_keeps_all_tickets_and_balances(self):
        db=sqlite3.connect(':memory:')
        db.executescript('CREATE TABLE lotto (id INT, super_lottery INT, equal_lottery INT, equal_ticket_value INT, call_deadline INT, finished INT); INSERT INTO lotto VALUES (1,0,1,340,0,0); CREATE TABLE tickets(value INT); INSERT INTO tickets VALUES (700); CREATE TABLE balances(value INT); INSERT INTO balances VALUES (50);')
        db.execute(persist_sql(0))
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
