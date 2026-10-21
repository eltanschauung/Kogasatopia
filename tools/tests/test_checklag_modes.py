"""Offline policy checks; in-engine regression probe covers actual execution."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]/'tf/addons/sourcemod/scripting'
def source(name): return (ROOT/name).read_text()
def uncomment(text): return re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
def body(text,name):
    start=text.index('{',text.index(name))
    depth=0
    for index in range(start,len(text)):
        depth += (text[index]=='{')-(text[index]=='}')
        if not depth: return text[start+1:index]
    raise AssertionError('Unbalanced source')
MAIN=source('checklag.sp')
DIAG=source('checklag_diagnostics.inc')
MODE=source('checklag_mode.inc')
HOST=source('checklag_host.inc')
PERF=source('include/kogasa_performance.inc')
def constant(text,name): return float(re.search(r'#define '+name+r' ([0-9.]+)',text)[1])

class ModePolicy(unittest.TestCase):
    def test_default_and_reload_bound(self):
        self.assertIn('CreateConVar("sm_checklag_mode", "1"',MAIN)
        self.assertIn('SetBounds(ConVarBound_Upper, true, 3.0)',MAIN)
    def test_mode_two_cannot_enable_producers(self):
        enabled=body(MODE,'Native_CheckLagIsProfilingEnabled')
        self.assertIn('g_CheckLagMode == 3',enabled)
        self.assertIn('CHECKLAG_PROFILE_STRIDE',enabled)
        native=body(DIAG,'Native_CheckLagRecordScope')
        self.assertLess(native.index('g_CheckLagMode != 3'),native.index('GetNativeString'))
    def test_no_expensive_work_on_frame_path(self):
        frame=uncomment(body(DIAG,'public void OnGameFrame()'))
        for forbidden in ['Profiler','CheckLag_SelfBegin','CheckLag_HostPoll','OpenFile','PluginStats_Record','FormatEx','LogMessage','StringMap']:
            self.assertNotIn(forbidden,frame)
        self.assertIn('CHECKLAG_SLOW_FRAME_MS',frame)
    def test_basic_snapshot_precedes_detailed_work(self):
        snapshot=body(DIAG,'void CheckLag_LogSnapshot(')
        self.assertLess(snapshot.index('g_CheckLagMode == 2'),snapshot.index('GetClientAvgLoss'))
        basic=uncomment(body(DIAG,'void CheckLag_LogBasicSnapshot('))
        self.assertEqual(basic.count('PluginStats_Record('),1)
        self.assertNotRegex(basic,r'GetClient|HostPoll|GetEntityCount')
    def test_kernel_sampling_cannot_cascade_during_stalls(self):
        poll=uncomment(body(HOST,'int CheckLag_HostPoll('))
        self.assertIn('g_CheckLagMode != 3',poll)
        self.assertIn('if (now < g_LagHostNextAt) return 0;',poll)
        self.assertNotIn('!stalled',poll)
        self.assertEqual(constant(HOST,'CHECKLAG_HOST_INTERVAL'),1)
    def test_per_tick_and_output_budgets(self):
        self.assertEqual(constant(DIAG,'CHECKLAG_SCOPE_TICK_BUDGET'),32)
        self.assertIn('g_KogasaPerfStarts >= 32',PERF)
        self.assertIn('milliseconds >= 0.25',PERF)
        detail_events=1+constant(DIAG,'CHECKLAG_SNAPSHOT_FRAME_LIMIT')+1+constant(DIAG,'CHECKLAG_SNAPSHOT_SCOPE_LIMIT')+constant(DIAG,'CHECKLAG_SNAPSHOT_CALL_LIMIT')+2
        self.assertLessEqual(detail_events,10)
        self.assertGreaterEqual(constant(DIAG,'CHECKLAG_DETAIL_INTERVAL'),15)
    def test_mode_one_and_two_share_producer_fast_path(self):
        begin=body(PERF,'stock int KogasaPerfBegin()')
        self.assertEqual(begin.count('CheckLag_IsProfilingEnabled()'),1)
        self.assertLess(begin.index('tick != g_KogasaPerfCachedTick'),begin.index('CheckLag_IsProfilingEnabled()'))
        self.assertLess(begin.index('!g_KogasaPerfEnabled'),begin.index('.Start()'))
    def test_frame_boundaries_do_not_reuse_stale_calls(self):
        reset=uncomment(body(DIAG,'void CheckLag_ResetFrames()'))
        self.assertNotIn('g_LagBoundary = 0',reset)
        match=body(DIAG,'int CheckLag_FrameMeasuredCall(')
        self.assertIn('now - g_LagSlowAt[row] < CHECKLAG_SCOPE_WINDOW',match)
        self.assertIn('g_LagSlowBoundary[row] == g_LagFrameBoundary[frame]',match)
    def test_sampling_budget_is_bounded(self):
        stride=int(constant(DIAG,'CHECKLAG_PROFILE_STRIDE'))
        budget=int(constant(DIAG,'CHECKLAG_SCOPE_TICK_BUDGET'))
        for mode in range(4):
            admitted=sum(min(10000,budget) for tick in range(66) if mode==3 and tick%stride==0)
            self.assertLessEqual(admitted,160 if mode==3 else 0)

if __name__=='__main__': unittest.main()
