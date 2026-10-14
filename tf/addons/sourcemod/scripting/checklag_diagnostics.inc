#define CHECKLAG_SCOPE_LIMIT 256
#define CHECKLAG_SCOPE_WINDOW 5.0
#define CHECKLAG_CONTEXT_LENGTH 160
#define CHECKLAG_SNAPSHOT_SCOPE_LIMIT 32
#define CHECKLAG_SLOW_CALL_LIMIT 128
#define CHECKLAG_SNAPSHOT_CALL_LIMIT 24
#define CHECKLAG_SLOW_CALL_MS 1.0
#define CHECKLAG_FRAME_LIMIT 512
#define CHECKLAG_SNAPSHOT_FRAME_LIMIT 8
#define CHECKLAG_SLOW_FRAME_MS 30.0

#include <profiler>
#include "checklag_math.inc"
#include "checklag_host.inc"

StringMap g_LagScopeIndexes;
char g_LagScopeNames[CHECKLAG_SCOPE_LIMIT][160];
char g_LagScopePeakContext[CHECKLAG_SCOPE_LIMIT][CHECKLAG_CONTEXT_LENGTH];
float g_LagScopeTotal[CHECKLAG_SCOPE_LIMIT], g_LagScopePeak[CHECKLAG_SCOPE_LIMIT];
float g_LagScopeStarted[CHECKLAG_SCOPE_LIMIT], g_LagScopeUpdated[CHECKLAG_SCOPE_LIMIT];
float g_LagScopePeakAt[CHECKLAG_SCOPE_LIMIT];
int g_LagScopePeakTick[CHECKLAG_SCOPE_LIMIT];
int g_LagScopePeakStartTick[CHECKLAG_SCOPE_LIMIT], g_LagScopePeakSpan[CHECKLAG_SCOPE_LIMIT];
int g_LagScopePeakParent[CHECKLAG_SCOPE_LIMIT];
float g_LagScopePeakChildren[CHECKLAG_SCOPE_LIMIT];
int g_LagScopeCalls[CHECKLAG_SCOPE_LIMIT], g_LagScopeCount, g_LagScopeDropped;
int g_LagSlowScope[CHECKLAG_SLOW_CALL_LIMIT], g_LagSlowTick[CHECKLAG_SLOW_CALL_LIMIT];
int g_LagSlowSequence[CHECKLAG_SLOW_CALL_LIMIT], g_LagCallSequence;
float g_LagSlowDuration[CHECKLAG_SLOW_CALL_LIMIT], g_LagSlowAt[CHECKLAG_SLOW_CALL_LIMIT];
char g_LagSlowContext[CHECKLAG_SLOW_CALL_LIMIT][CHECKLAG_CONTEXT_LENGTH];
int g_LagSlowCount, g_LagSlowCursor;
int g_LagSlowStartTick[CHECKLAG_SLOW_CALL_LIMIT], g_LagSlowSpan[CHECKLAG_SLOW_CALL_LIMIT];
int g_LagSlowParent[CHECKLAG_SLOW_CALL_LIMIT], g_LagSlowOverwritten;
float g_LagSlowChildren[CHECKLAG_SLOW_CALL_LIMIT];
float g_LagFrameGap[CHECKLAG_FRAME_LIMIT], g_LagFrameAt[CHECKLAG_FRAME_LIMIT];
int g_LagFrameTick[CHECKLAG_FRAME_LIMIT], g_LagFrameCount, g_LagFrameCursor;
int g_LagFrameStartTick[CHECKLAG_FRAME_LIMIT], g_LagFrameHost[CHECKLAG_FRAME_LIMIT];
int g_LastFrameTick;
Profiler g_LagFrameClock;
char g_LastLagScopeLines[CHECKLAG_SNAPSHOT_SCOPE_LIMIT][384];
int g_LastLagScopeLineCount, g_LastLagAlertTick;
bool g_LastLagSnapshotReady;
float g_LastLagAlertAt, g_LastLagAlertRate, g_LastLagAlertFrame;
char g_LastLagFrameDetail[384];

void CheckLag_ResetFrames()
{
    g_LagFrameCount = 0;
    g_LagFrameCursor = 0;
    g_LastFrameTick = GetGameTickCount();
    if (g_CheckLagMode < 2)
    {
        delete g_LagFrameClock;
        delete g_LagHostClock;
        delete g_LagHostIntervalClock;
        g_LagHostReady = false;
        return;
    }
    if (g_LagFrameClock == null) g_LagFrameClock = new Profiler();
    g_LagFrameClock.Start();
    CheckLag_HostReset();
}

void CheckLag_SanitizeField(char[] value, int maxlen)
{
    ReplaceString(value, maxlen, "|", "/", false);
    ReplaceString(value, maxlen, "\r", " ", false);
    ReplaceString(value, maxlen, "\n", " ", false);
}

public any Native_CheckLagRecordScope(Handle plugin, int params)
{
    if (g_CheckLagMode < 2 || g_LagScopeIndexes == null) return 0;
    char filename[80], scope[72], context[CHECKLAG_CONTEXT_LENGTH];
    GetPluginFilename(plugin, filename, sizeof(filename));
    GetNativeString(1, scope, sizeof(scope));
    // Existing compiled callers pass two arguments.
    if (params >= 3) GetNativeString(3, context, sizeof(context));
    int startTick = params >= 4 ? GetNativeCell(4) : -1;
    int span = params >= 5 ? GetNativeCell(5) : 0;
    int parent = params >= 6 ? GetNativeCell(6) : 0;
    float children = params >= 7 ? view_as<float>(GetNativeCell(7)) : -1.0;
    float duration = GetNativeCell(2);
    CheckLag_RecordScopeFields(filename, scope, duration, context, startTick, span, parent, children);
    return 0;
}

void CheckLag_RecordScopeFields(const char[] filename, char scope[72], float duration,
    char context[CHECKLAG_CONTEXT_LENGTH], int startTick = -1, int span = 0, int parent = 0, float children = -1.0)
{
    if (g_CheckLagMode < 2) return;
    char key[160];
    CheckLag_SanitizeField(scope, sizeof(scope));
    CheckLag_SanitizeField(context, sizeof(context));
    if (!scope[0] || !(duration >= 0.0 && duration < 60000.0)) return;
    float now = GetEngineTime();
    int tick = GetGameTickCount();
    FormatEx(key, sizeof(key), "%s / %s", filename, scope);
    int index;
    if (!g_LagScopeIndexes.GetValue(key, index))
    {
        if (g_LagScopeCount >= CHECKLAG_SCOPE_LIMIT) { g_LagScopeDropped++; return; }
        index = g_LagScopeCount++;
        g_LagScopeIndexes.SetValue(key, index);
        strcopy(g_LagScopeNames[index], sizeof(g_LagScopeNames[]), key);
        g_LagScopeStarted[index] = now;
        g_LagScopeTotal[index] = 0.0;
        g_LagScopePeak[index] = 0.0;
        g_LagScopeCalls[index] = 0;
    }
    if (now - g_LagScopeStarted[index] >= CHECKLAG_SCOPE_WINDOW)
    {
        g_LagScopeStarted[index] = now;
        g_LagScopeTotal[index] = 0.0;
        g_LagScopePeak[index] = 0.0;
        g_LagScopeCalls[index] = 0;
    }
    g_LagScopeUpdated[index] = now;
    g_LagScopeTotal[index] += duration;
    g_LagScopeCalls[index]++;
    if (duration >= g_LagScopePeak[index])
    {
        g_LagScopePeak[index] = duration;
        g_LagScopePeakAt[index] = now;
        g_LagScopePeakTick[index] = tick;
        g_LagScopePeakStartTick[index] = startTick;
        g_LagScopePeakSpan[index] = span;
        g_LagScopePeakParent[index] = parent;
        g_LagScopePeakChildren[index] = children;
        strcopy(g_LagScopePeakContext[index], sizeof(g_LagScopePeakContext[]), context);
    }
    if (duration >= CHECKLAG_SLOW_CALL_MS)
    {
        int row = g_LagSlowCursor;
        if (g_LagSlowCount == CHECKLAG_SLOW_CALL_LIMIT && now - g_LagSlowAt[row] < CHECKLAG_SCOPE_WINDOW)
            g_LagSlowOverwritten++;
        g_LagSlowScope[row] = index;
        g_LagSlowTick[row] = tick;
        g_LagSlowAt[row] = now;
        g_LagSlowDuration[row] = duration;
        g_LagSlowSequence[row] = ++g_LagCallSequence;
        g_LagSlowStartTick[row] = startTick;
        g_LagSlowSpan[row] = span;
        g_LagSlowParent[row] = parent;
        g_LagSlowChildren[row] = children;
        strcopy(g_LagSlowContext[row], sizeof(g_LagSlowContext[]), context);
        g_LagSlowCursor = (row + 1) % CHECKLAG_SLOW_CALL_LIMIT;
        if (g_LagSlowCount < CHECKLAG_SLOW_CALL_LIMIT) g_LagSlowCount++;
    }
}

public void OnGameFrame()
{
    if (g_CheckLagMode < 2) return;
    float now = GetEngineTime(), gap;
    if (g_LagFrameClock == null) { CheckLag_ResetFrames(); return; }
    g_LagFrameClock.Stop();
    gap = g_LagFrameClock.Time;
    g_LagFrameClock.Start();
    int previousTick = g_LastFrameTick;
    g_LastFrameTick = GetGameTickCount();
    if (now < g_RoundQuietUntil || gap < 0.0 || gap > 60.0) return;
    int host = CheckLag_HostPoll(now, gap * 1000.0 >= CHECKLAG_SLOW_FRAME_MS);
    int row = g_LagFrameCursor;
    g_LagFrameGap[row] = gap;
    g_LagFrameAt[row] = now;
    g_LagFrameTick[row] = GetGameTickCount();
    g_LagFrameStartTick[row] = previousTick;
    g_LagFrameHost[row] = host;
    g_LagFrameCursor = (row + 1) % CHECKLAG_FRAME_LIMIT;
    if (g_LagFrameCount < CHECKLAG_FRAME_LIMIT) g_LagFrameCount++;
}

int CheckLag_RecentFrameRow()
{
    float now = GetEngineTime();
    int best = -1;
    for (int row = 0; row < g_LagFrameCount; row++)
        if (now - g_LagFrameAt[row] < CHECKLAG_SCOPE_WINDOW
            && (best < 0 || g_LagFrameGap[row] > g_LagFrameGap[best])) best = row;
    return best;
}

int CheckLag_FrameMeasuredCall(int frame)
{
    if (frame < 0) return -1;
    int best = -1;
    for (int row = 0; row < g_LagSlowCount; row++)
        if (CheckLag_FrameMatchesCall(g_LagFrameStartTick[frame], g_LagFrameTick[frame],
                g_LagSlowStartTick[row], g_LagSlowTick[row])
            && (best < 0 || g_LagSlowDuration[row] > g_LagSlowDuration[best])) best = row;
    return best;
}

void CheckLag_LogFrames(int alertTick)
{
    if (g_CheckLagMode < 2) return;
    bool shown[CHECKLAG_FRAME_LIMIT];
    float now = GetEngineTime();
    g_LastLagFrameDetail[0] = '\0';
    for (int rank = 0; rank < CHECKLAG_SNAPSHOT_FRAME_LIMIT; rank++)
    {
        int best = -1;
        for (int row = 0; row < g_LagFrameCount; row++)
            if (!shown[row] && now - g_LagFrameAt[row] < CHECKLAG_SCOPE_WINDOW
                && g_LagFrameGap[row] * 1000.0 >= CHECKLAG_SLOW_FRAME_MS
                && (best < 0 || g_LagFrameGap[row] > g_LagFrameGap[best])) best = row;
        if (best < 0) break;
        shown[best] = true;
        int call = CheckLag_FrameMeasuredCall(best);
        char scope[160] = "none", message[512];
        float duration = g_LagFrameGap[best] * 1000.0, measured;
        int sequence;
        if (call >= 0)
        {
            measured = g_LagSlowDuration[call]; sequence = g_LagSlowSequence[call];
            strcopy(scope, sizeof(scope), g_LagScopeNames[g_LagSlowScope[call]]);
        }
        float outside = duration > measured ? duration - measured : 0.0;
        FormatEx(message, sizeof(message),
            "v=3|alert_tick=%d|rank=%d|frame_tick=%d|previous_tick=%d|frame_ms=%.3f|budget_ms=%.3f|age_ms=%.1f|same_tick_scope=%s|scope_ms=%.3f|call_seq=%d|outside_largest_ms=%.3f|host_seq=%d",
            alertTick, rank + 1, g_LagFrameTick[best], g_LagFrameStartTick[best],
            duration, GetTickInterval() * 1000.0, (now - g_LagFrameAt[best]) * 1000.0,
            scope, measured, sequence, outside, g_LagFrameHost[best]);
        PluginStats_Record("lag_frame", message);
        LogMessage("[CheckLag][Frame] %s", message);
        CheckLag_HostLog(g_LagFrameHost[best], alertTick, g_LagFrameTick[best]);
        if (rank == 0)
            FormatEx(g_LastLagFrameDetail, sizeof(g_LastLagFrameDetail),
                "Worst frame: %.3f ms at tick %d (work tick %d); matching interval: %s %.3f ms; outside that largest interval %.3f ms. This is not exclusive CPU attribution.",
                duration, g_LagFrameTick[best], g_LagFrameStartTick[best], scope, measured, outside);
    }
}

float CheckLag_RecentFramePeak(int &tick)
{
    float now = GetEngineTime(), peak;
    tick = 0;
    for (int i = 0; i < g_LagFrameCount; i++)
        if (now - g_LagFrameAt[i] < CHECKLAG_SCOPE_WINDOW && g_LagFrameGap[i] > peak)
        { peak = g_LagFrameGap[i]; tick = g_LagFrameTick[i]; }
    return peak * 1000.0;
}

int CheckLag_RecentMeasuredScope()
{
    int best = -1;
    float now = GetEngineTime();
    for (int i = 0; i < g_LagScopeCount; i++)
        if (g_LagScopeCalls[i] > 0 && now - g_LagScopePeakAt[i] < CHECKLAG_SCOPE_WINDOW
            && (best < 0 || g_LagScopePeak[i] > g_LagScopePeak[best])) best = i;
    return best;
}

void CheckLag_LogSnapshot(int alertTick, float current, float maximum, int measured, bool manual = false)
{
    if (g_CheckLagMode < 2) return;
    float now = GetEngineTime(), loss, choke;
    int frameTick, humans;
    float framePeak = CheckLag_RecentFramePeak(frameTick);
    int entities = GetEntityCount();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)) continue;
        humans++;
        float l = GetClientAvgLoss(client, NetFlow_Outgoing), h = GetClientAvgChoke(client, NetFlow_Outgoing);
        if (l > loss) loss = l;
        if (h > choke) choke = h;
    }
    char message[512], scope[160] = "none";
    float peak;
    int calls;
    if (measured >= 0)
    {
        strcopy(scope, sizeof(scope), g_LagScopeNames[measured]);
        peak = g_LagScopePeak[measured];
        calls = g_LagScopeCalls[measured];
    }
    FormatEx(message, sizeof(message),
        "v=3|alert_tick=%d|rate=%.3f|expected=%.3f|window_s=%.1f|frame_peak_ms=%.2f|frame_tick=%d|humans=%d|entities=%d|free_edicts=%d|loss_pct=%.2f|choke_pct=%.2f|measured=%s|peak_ms=%.3f|calls=%d|dropped_scopes=%d|overwritten_calls=%d|measured_role=window_context",
        alertTick, current, maximum, CHECKLAG_SCOPE_WINDOW, framePeak, frameTick,
        humans, entities, GetMaxEntities() - entities, loss * 100.0, choke * 100.0,
        scope, peak, calls, g_LagScopeDropped, g_LagSlowOverwritten);
    StrCat(message, sizeof(message), manual ? "|snapshot_kind=manual" : "|snapshot_kind=automatic");
    StrCat(message, sizeof(message), "|mode=2");
    PluginStats_Record(manual ? "lag_manual_snapshot" : "tickrate_drop", message);
    LogMessage("[CheckLag] %s", message);
    g_LastLagAlertTick = alertTick;
    g_LastLagAlertAt = now;
    g_LastLagAlertRate = current;
    g_LastLagAlertFrame = framePeak;
    g_LastLagScopeLineCount = 0;
    g_LastLagSnapshotReady = true;
    CheckLag_LogFrames(alertTick);

    // Bounded, queued telemetry only on alerts. Nested inclusive timings must
    // not be summed as exclusive CPU time. Bucket/peak ages show freshness.
    bool shown[CHECKLAG_SCOPE_LIMIT];
    for (int rank = 0; rank < CHECKLAG_SNAPSHOT_SCOPE_LIMIT; rank++)
    {
        int best = -1;
        for (int i = 0; i < g_LagScopeCount; i++)
            if (!shown[i] && g_LagScopeCalls[i] > 0 && now - g_LagScopeUpdated[i] < CHECKLAG_SCOPE_WINDOW
                && now - g_LagScopePeakAt[i] < CHECKLAG_SCOPE_WINDOW
                && (best < 0 || g_LagScopePeak[i] > g_LagScopePeak[best])) best = i;
        if (best < 0) break;
        shown[best] = true;
        FormatEx(message, sizeof(message),
            "v=3|alert_tick=%d|rank=%d|scope=%s|total_ms=%.3f|calls=%d|peak_ms=%.3f|peak_tick=%d|peak_age_ms=%.1f|bucket_age_ms=%.1f|start_tick=%d|span_id=%d|parent_id=%d|children_ms=%.3f|remainder_ms=%.3f|context=%s",
            alertTick, rank + 1, g_LagScopeNames[best], g_LagScopeTotal[best],
            g_LagScopeCalls[best], g_LagScopePeak[best], g_LagScopePeakTick[best],
            (now - g_LagScopePeakAt[best]) * 1000.0, (now - g_LagScopeStarted[best]) * 1000.0,
            g_LagScopePeakStartTick[best], g_LagScopePeakSpan[best], g_LagScopePeakParent[best],
            g_LagScopePeakChildren[best],
            CheckLag_UninstrumentedRemainder(g_LagScopePeak[best], g_LagScopePeakChildren[best]),
            g_LagScopePeakContext[best]);
        PluginStats_Record("lag_scope_snapshot", message);
        LogMessage("[CheckLag][Scope] %s", message);
        FormatEx(g_LastLagScopeLines[g_LastLagScopeLineCount++], sizeof(g_LastLagScopeLines[]),
            "%s: %.3f ms peak / %.3f ms total / %d calls; peak_tick=%d; %s",
            g_LagScopeNames[best], g_LagScopePeak[best], g_LagScopeTotal[best],
            g_LagScopeCalls[best], g_LagScopePeakTick[best], g_LagScopePeakContext[best]);
    }
    bool callsShown[CHECKLAG_SLOW_CALL_LIMIT];
    for (int rank = 0; rank < CHECKLAG_SNAPSHOT_CALL_LIMIT; rank++)
    {
        int best = -1;
        for (int i = 0; i < g_LagSlowCount; i++)
            if (!callsShown[i] && now - g_LagSlowAt[i] < CHECKLAG_SCOPE_WINDOW
                && (best < 0 || g_LagSlowDuration[i] > g_LagSlowDuration[best])) best = i;
        if (best < 0) break;
        callsShown[best] = true;
        FormatEx(message, sizeof(message),
            "v=3|alert_tick=%d|seq=%d|scope=%s|ms=%.3f|end_tick=%d|start_s=%.3f|end_s=%.3f|age_ms=%.1f|start_tick=%d|span_id=%d|parent_id=%d|children_ms=%.3f|remainder_ms=%.3f|context=%s",
            alertTick, g_LagSlowSequence[best], g_LagScopeNames[g_LagSlowScope[best]],
            g_LagSlowDuration[best], g_LagSlowTick[best],
            g_LagSlowAt[best] - g_LagSlowDuration[best] / 1000.0, g_LagSlowAt[best],
            (now - g_LagSlowAt[best]) * 1000.0, g_LagSlowStartTick[best],
            g_LagSlowSpan[best], g_LagSlowParent[best], g_LagSlowChildren[best],
            CheckLag_UninstrumentedRemainder(g_LagSlowDuration[best], g_LagSlowChildren[best]),
            g_LagSlowContext[best]);
        PluginStats_Record("lag_slow_call", message);
        LogMessage("[CheckLag][Call] %s", message);
    }
}

public Action Command_LagSnapshot(int client, int args)
{
    if (g_CheckLagMode < 2)
    {
        ReplyToCommand(client, "[CheckLag] Profiling is disabled; use sm_checklag_mode 2 for snapshots.");
        return Plugin_Handled;
    }
    int tick = GetGameTickCount();
    CheckLag_LogSnapshot(tick, PluginStats_GetObservedTickrate(), PluginStats_GetExpectedTickrate(),
        CheckLag_RecentMeasuredScope(), true);
    ReplyToCommand(client, "[CheckLag] Manual snapshot saved for Tick #%d (not a tickrate-drop event).", tick);
    return Plugin_Handled;
}

public Action Command_LagDetails(int client, int args)
{
    if (g_CheckLagMode < 2)
    {
        ReplyToCommand(client, "[CheckLag] Profiling is disabled; use sm_checklag_mode 2 for details.");
        return Plugin_Handled;
    }
    if (g_LastLagSnapshotReady)
    {
        ReplyToCommand(client, "[CheckLag] Saved alert Tick #%d (%.1f seconds ago): %.1f tick/s; recent frame peak %.1f ms. Inclusive times:",
            g_LastLagAlertTick, GetEngineTime() - g_LastLagAlertAt, g_LastLagAlertRate, g_LastLagAlertFrame);
        if (g_LastLagFrameDetail[0]) ReplyToCommand(client, "[CheckLag] %s", g_LastLagFrameDetail);
        ReplyToCommand(client, "[CheckLag] The following are five-second window context, not necessarily the stalled tick. CPU/wait/IO windows are stored separately.");
        int count = g_LastLagScopeLineCount < 12 ? g_LastLagScopeLineCount : 12;
        for (int i = 0; i < count; i++) ReplyToCommand(client, "  %s", g_LastLagScopeLines[i]);
        ReplyToCommand(client, "[CheckLag] Full snapshot is stored in plugin_statistics_events and SourceMod logs; join on session + alert_tick.");
        return Plugin_Handled;
    }
    int frameTick;
    float framePeak = CheckLag_RecentFramePeak(frameTick);
    ReplyToCommand(client, "[CheckLag] Recent server frame peak: %.1f ms (tick %d). Live inclusive timings:", framePeak, frameTick);
    bool shown[CHECKLAG_SCOPE_LIMIT];
    float now = GetEngineTime();
    for (int rank = 0; rank < 8; rank++)
    {
        int best = -1;
        for (int i = 0; i < g_LagScopeCount; i++)
            if (!shown[i] && g_LagScopeCalls[i] > 0 && now - g_LagScopeUpdated[i] < CHECKLAG_SCOPE_WINDOW
                && (best < 0 || g_LagScopeTotal[i] > g_LagScopeTotal[best])) best = i;
        if (best < 0) break;
        shown[best] = true;
        ReplyToCommand(client, "  %s: %.3f ms total / %d calls; %.3f ms peak; %s",
            g_LagScopeNames[best], g_LagScopeTotal[best], g_LagScopeCalls[best],
            g_LagScopePeak[best], g_LagScopePeakContext[best]);
    }
    if (CheckLag_RecentMeasuredScope() < 0)
        ReplyToCommand(client, "  No recent instrumented scopes. Other plugins, engine or I/O can still cause stalls.");
    return Plugin_Handled;
}
