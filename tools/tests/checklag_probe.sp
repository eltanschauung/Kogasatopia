// Production diagnostics with synthetic clocks and an in-memory telemetry sink.
// Never emits fake CheckLag database incidents, hooks frames or delays a server.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <profiler>

public Plugin myinfo = { name = "CheckLag diagnostic regression probe", author = "Hombre", version = "1.0.0" };
float g_RoundQuietUntil;
ConVar g_CheckLagModeConVar;
int g_CheckLagMode = 2;
Handle g_AdminMonitorTimer;
float g_NextAdminAlertAt;
#define CHECKLAG_MONITOR_INTERVAL 1.0
float testTime = 30.0;
int testTick = 100, checks, failures, records;
char events[64][32], messages[64][512];

float ProbeTime() { return testTime; }
int ProbeTick() { return testTick; }
void ProbeRecord(const char[] eventName, const char[] message) {
    if (records >= sizeof(events)) return;
    strcopy(events[records], sizeof(events[]), eventName);
    strcopy(messages[records], sizeof(messages[]), message);
    records++;
}
void ProbeLog(const char[] format, const char[] message) {
    #pragma unused format
    #pragma unused message
}
float PluginStats_GetObservedTickrate() { return 66.666; }
float PluginStats_GetExpectedTickrate() { return 66.666; }
public Action Timer_MonitorTickrate(Handle timer) { return Plugin_Continue; }

#define GetEngineTime ProbeTime
#define GetGameTickCount ProbeTick
#define PluginStats_Record ProbeRecord
#define LogMessage ProbeLog
#define OnGameFrame ProbeFrame
#include "checklag_diagnostics.inc"
#include "checklag_mode.inc"
#undef GetEngineTime
#undef GetGameTickCount
#undef PluginStats_Record
#undef LogMessage
#undef OnGameFrame

void Check(bool condition, const char[] label) {
    checks++; if (!condition) { failures++; PrintToServer("[CheckLagProbe] FAIL: %s", label); }
}
void Reset() {
    testTime = 30.0; testTick = 100; records = 0;
    g_LagScopeIndexes.Clear(); g_LagScopeCount = 0;
    g_LagSlowCount = 0; g_LagSlowCursor = 0; g_LagCallSequence = 0;
    g_LagFrameCount = 0; g_LagFrameCursor = 0; g_LagHostReady = false;
}
void Call(const char[] name, float ms, int tick, float children = -1.0) {
    char scope[72], context[CHECKLAG_CONTEXT_LENGTH] = "class=6";
    strcopy(scope, sizeof(scope), name); testTick = tick;
    CheckLag_RecordScopeFields("probe.smx", scope, ms, context, tick, 1, 0, children);
}
void Frame(int previous, int end, float ms) {
    g_LagFrameCount = 1; g_LagFrameTick[0] = end; g_LagFrameStartTick[0] = previous;
    g_LagFrameGap[0] = ms / 1000.0; g_LagFrameAt[0] = testTime;
    g_LagFrameHost[0] = 0;
}
int FindEvent(const char[] name) {
    for (int row = 0; row < records; row++) if (StrEqual(events[row], name)) return row;
    return -1;
}
public void OnPluginStart() {
    g_LagScopeIndexes = new StringMap();
    g_CheckLagModeConVar = CreateConVar("sm_checklag_probe_mode", "1",
        "Isolated regression probe mode.", _, true, 0.0, true, 2.0);
    g_CheckLagModeConVar.AddChangeHook(CheckLag_ModeChanged);
    RegAdminCmd("sm_checklag_probe", Command_Probe, ADMFLAG_ROOT);
}
public void OnPluginEnd() {
    delete g_AdminMonitorTimer;
    delete g_LagScopeIndexes;
    delete g_LagFrameClock;
    delete g_LagHostClock;
    delete g_LagHostIntervalClock;
}
public Action Command_Probe(int client, int args) {
    #pragma unused args
    checks = 0; failures = 0;
    char defaultMode[8];
    g_CheckLagModeConVar.GetDefault(defaultMode, sizeof(defaultMode));
    Check(StrEqual(defaultMode, "1"), "mode defaults to alerts only");
    g_CheckLagModeConVar.SetInt(2);
    Check(g_CheckLagMode == 2 && Native_CheckLagIsProfilingEnabled(null, 0),
        "level two advertises profiling");
    Check(g_AdminMonitorTimer != null && g_LagFrameClock != null,
        "level two starts timer and frame profiler");
    Check(CheckLag_FrameMatchesCall(9419, 9420, 9419, 9419), "Heavy same-frame");
    Check(CheckLag_FrameMatchesCall(127090, 127091, -1, 127090), "Soldier legacy caller");
    Check(CheckLag_FrameMatchesCall(39306, 39307, 39306, 39306), "Soldier same-frame");
    Check(CheckLag_FrameMatchesCall(68258, 68259, 68258, 68258), "Engineer same-frame");
    Check(!CheckLag_FrameMatchesCall(65309, 65310, 65051, 65051), "stale Soldier excluded");
    Check(!CheckLag_FrameMatchesCall(64670, 64671, 64630, 64630), "stale Engineer excluded");
    Check(!CheckLag_FrameMatchesCall(80405, 80406, 80450, 80450), "later Scout excluded");
    Check(!CheckLag_FrameMatchesCall(95429, 95430, 95279, 95279), "stale Spy excluded");
    Check(!CheckLag_FrameMatchesCall(158042, 158043, 158053, 158053), "later Demo excluded");
    Check(!CheckLag_FrameMatchesCall(100, 101, 100, 101), "next-frame work excluded");
    Check(!CheckLag_FrameMatchesCall(100, 100, 100, 100), "no tick advance");
    Check(!CheckLag_FrameMatchesCall(100, 101, 99, 100), "multi-frame call not attributed wholly");
    Check(CheckLag_UninstrumentedRemainder(103.75, 1.25) == 102.5, "known nested subtraction");
    Check(CheckLag_UninstrumentedRemainder(1.0, 1.1) == 0.0, "rounding cannot yield negative remainder");
    Check(CheckLag_UninstrumentedRemainder(1.0, -1.0) == -1.0, "old callers remain unknown");

    int older[2], newer[2];
    Check(CheckLag_ParseCounter("123456789012345", older), "large nanosecond total");
    Check(CheckLag_ParseCounter("123456892762345", newer), "large nanosecond total with increment");
    Check(FloatAbs(CheckLag_CounterDelta(newer, older, true) - 103.75) < 0.0001, "nanosecond delta precision");
    Check(CheckLag_ParseCounter("999999999", older), "low rollover baseline");
    Check(CheckLag_ParseCounter("1000000000", newer), "low rollover sample");
    Check(CheckLag_CounterDelta(newer, older) == 1.0, "byte rollover precision");
    Check(FloatAbs(CheckLag_CounterDelta(newer, older, true) - 0.000001) < 0.00000001, "nanosecond rollover precision");
    Check(CheckLag_CounterDelta(older, newer) == -1.0, "counter reset detected");
    Check(!CheckLag_ParseCounter("-1", older), "negative counter rejected");
    Check(!CheckLag_ParseCounter("1x", older), "malformed counter rejected");
    Check(!CheckLag_ParseCounter("", older), "empty counter rejected");
    Check(!CheckLag_ParseCounter("9999999999999999999", older), "overflow rejected");

    Reset(); Call("unrelated window peak", 200.0, 90);
    Call("same-frame parent", 100.0, 100, 12.0);
    Call("same-frame child", 12.0, 100, 0.0);
    Frame(100, 101, 150.0);
    Check(CheckLag_RecentFrameRow() == 0, "recent worst frame selected");
    Check(CheckLag_RecentMeasuredScope() == 0, "largest window scope retained as context");
    int matching = CheckLag_FrameMeasuredCall(0);
    Check(matching >= 0 && g_LagSlowScope[matching] == 1, "correlation chooses parent, not stale peak or child");
    CheckLag_LogSnapshot(110, 57.0, 66.666, 0, true);
    int frameEvent = FindEvent("lag_frame");
    Check(frameEvent >= 0, "frame event persisted");
    if (frameEvent >= 0) {
        Check(StrContains(messages[frameEvent], "same-frame parent") >= 0, "correct matched scope");
        Check(StrContains(messages[frameEvent], "outside_largest_ms=50.000") >= 0, "nested intervals not double-counted");
    }
    Check(FindEvent("tickrate_drop") < 0 && FindEvent("lag_manual_snapshot") >= 0, "manual snapshots not incidents");
    int callEvent = FindEvent("lag_slow_call");
    Check(callEvent >= 0 && StrContains(messages[callEvent], "children_ms=") >= 0, "span detail present");
    Reset(); Call("stale Spy", 6.0, 90); Frame(100, 101, 918.0);
    Check(CheckLag_FrameMeasuredCall(0) == -1, "918 ms stall does not blame unrelated Spy");
    CheckLag_LogFrames(110);
    frameEvent = FindEvent("lag_frame");
    Check(frameEvent >= 0 && StrContains(messages[frameEvent], "same_tick_scope=none") >= 0, "unknown stall explicit");

    CheckLag_HostReset();
    Check(CheckLag_HostPoll(30.0, false) > 0, "host baseline sampled");
    Check(CheckLag_HostPoll(30.1, false) == 0, "routine host reads rate limited");
    Check(CheckLag_HostPoll(30.1, true) > 0, "stalled frame forces immediate host sample");
    int host = (g_LagHostCursor + CHECKLAG_HOST_LIMIT - 1) % CHECKLAG_HOST_LIMIT;
    Check(g_LagHostSamples[host].probeMs >= 0.0, "diagnostic overhead measured");
    Check((g_LagHostSamples[host].flags & CHECKLAG_HOST_CPU) != 0, "Linux thread CPU counter accessible");
    Check((g_LagHostSamples[host].flags & (CHECKLAG_HOST_FAULTS | CHECKLAG_HOST_IO))
        == (CHECKLAG_HOST_FAULTS | CHECKLAG_HOST_IO), "Linux fault and I/O counters accessible");
    Check(g_LagHostSamples[host].cpuMs >= 0.0, "valid sampled CPU delta");
    CheckLag_HostLog(g_LagHostSamples[host].sequence, 110, 101);
    Check(FindEvent("lag_host_window") >= 0, "host-window telemetry retained");

    g_LastLagSnapshotReady = true;
    g_CheckLagModeConVar.SetInt(1);
    Check(g_CheckLagMode == 1 && !Native_CheckLagIsProfilingEnabled(null, 0),
        "level one disables producer profiling");
    Check(g_LagFrameClock == null && g_LagHostClock == null && g_LagHostIntervalClock == null,
        "level one releases profiling clocks");
    Check(g_LagScopeCount == 0 && g_LagSlowCount == 0 && g_LagFrameCount == 0,
        "mode transition clears telemetry rings");
    Check(!g_LastLagSnapshotReady && !g_LagHostReady, "mode transition clears stale snapshot and host state");
    Check(g_AdminMonitorTimer != null, "level one retains alerts timer");
    Check(g_NextAdminAlertAt == g_RoundQuietUntil && g_RoundQuietUntil > testTime,
        "mode changes reset alert cooldown and quiet period");
    Check(Native_CheckLagRecordScope(null, 2) == 0, "disabled native returns before reading arguments");
    int oldHostSequence = g_LagHostSequence;
    Call("disabled scope", 100.0, 100);
    ProbeFrame();
    Check(g_LagScopeCount == 0 && g_LagFrameCount == 0, "level one skips scope and frame collection");
    Check(CheckLag_HostPoll(30.0, true) == 0 && g_LagHostSequence == oldHostSequence,
        "level one skips even forced host polling");
    records = 0;
    CheckLag_LogSnapshot(110, 57.0, 66.666, -1);
    CheckLag_LogFrames(110);
    Check(records == 0, "level one refuses detailed telemetry");
    CheckLag_LogTickrateAlert(110, 57.0, 66.666);
    Check(records == 1 && FindEvent("tickrate_drop") == 0, "level one logs one tickrate alert only");
    Check(StrContains(messages[0], "mode=1") >= 0 && StrContains(messages[0], "frame_ms=") < 0,
        "alerts-only payload omits profiling");

    g_CheckLagModeConVar.SetInt(0);
    Check(g_CheckLagMode == 0 && g_AdminMonitorTimer == null, "level zero stops monitor timer");
    Check(!Native_CheckLagIsProfilingEnabled(null, 0), "level zero disables producers");
    records = 0;
    CheckLag_LogTickrateAlert(110, 57.0, 66.666);
    CheckLag_LogSnapshot(110, 57.0, 66.666, -1, true);
    Check(records == 0, "level zero emits no telemetry");

    g_CheckLagModeConVar.SetInt(2);
    Check(g_LagFrameClock != null && g_AdminMonitorTimer != null, "profiling can be re-enabled dynamically");
    Call("reenabled scope", 10.0, 100);
    Check(g_LagScopeCount == 1 && g_LagSlowCount == 1, "re-enabled profiling accepts fresh spans");
    records = 0;
    CheckLag_LogSnapshot(110, 57.0, 66.666, 0, true);
    Check(FindEvent("lag_scope_snapshot") >= 0 && FindEvent("lag_slow_call") >= 0,
        "level two retains detailed telemetry");
    Check(StrContains(messages[0], "mode=2") >= 0, "full payload identifies mode two");
    g_CheckLagModeConVar.SetInt(1);
    Reset();
    ReplyToCommand(client, "[CheckLagProbe] %d checks; %d failures; no live incidents generated", checks, failures);
    return Plugin_Handled;
}
