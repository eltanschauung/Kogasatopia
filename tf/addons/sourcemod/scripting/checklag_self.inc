// Bounded observer-cost accounting. Never feeds back into RecordScope or logs
// from a frame/native callback. Nested categories are inclusive; only roots
// contribute to total time. This is wall time, not exclusive CPU attribution.
#include <profiler>
#define CHECKLAG_SELF_ROWS 512
#define CHECKLAG_SELF_DEPTH 16
enum CheckLagSelfCategory
{
    Self_Frame, Self_RecordScope, Self_Monitor, Self_Snapshot, Self_Command,
    Self_CategoryCount
}
static const char g_SelfNames[][] = {"frame", "record_scope", "monitor", "snapshot", "command"};
Profiler g_SelfClocks[CHECKLAG_SELF_DEPTH];
int g_SelfDepth, g_SelfCategory[CHECKLAG_SELF_DEPTH], g_SelfCursor, g_SelfCount;
int g_SelfTick[CHECKLAG_SELF_ROWS], g_SelfCalls[CHECKLAG_SELF_ROWS][Self_CategoryCount];
float g_SelfAt[CHECKLAG_SELF_ROWS], g_SelfTotal[CHECKLAG_SELF_ROWS];
float g_SelfMs[CHECKLAG_SELF_ROWS][Self_CategoryCount];
int g_SelfOverflow;

int CheckLag_SelfBegin(CheckLagSelfCategory category)
{
    if (g_SelfDepth >= CHECKLAG_SELF_DEPTH) { g_SelfOverflow++; return -1; }
    int slot = g_SelfDepth++;
    g_SelfCategory[slot] = view_as<int>(category);
    if (g_SelfClocks[slot] == null) g_SelfClocks[slot] = new Profiler();
    g_SelfClocks[slot].Start();
    return slot;
}

float CheckLag_SelfEnd(int slot)
{
    if (slot < 0 || slot >= g_SelfDepth) return 0.0;
    g_SelfClocks[slot].Stop();
    float ms = g_SelfClocks[slot].Time * 1000.0;
    g_SelfDepth = slot;
    int tick = GetGameTickCount();
    int row = (g_SelfCursor + CHECKLAG_SELF_ROWS - 1) % CHECKLAG_SELF_ROWS;
    if (g_SelfCount == 0 || g_SelfTick[row] != tick)
    {
        row = g_SelfCursor;
        g_SelfCursor = (row + 1) % CHECKLAG_SELF_ROWS;
        if (g_SelfCount < CHECKLAG_SELF_ROWS) g_SelfCount++;
        g_SelfTick[row] = tick;
        g_SelfTotal[row] = 0.0;
        for (int category = 0; category < view_as<int>(Self_CategoryCount); category++)
        { g_SelfMs[row][category] = 0.0; g_SelfCalls[row][category] = 0; }
    }
    g_SelfAt[row] = GetEngineTime();
    int category = g_SelfCategory[slot];
    g_SelfMs[row][category] += ms;
    g_SelfCalls[row][category]++;
    if (slot == 0) g_SelfTotal[row] += ms;
    return ms;
}

void CheckLag_SelfReset()
{
    g_SelfCount = 0; g_SelfCursor = 0; g_SelfOverflow = 0; g_SelfDepth = 0;
}

void CheckLag_SelfShutdown()
{
    for (int slot = 0; slot < CHECKLAG_SELF_DEPTH; slot++) delete g_SelfClocks[slot];
}

void CheckLag_SelfReport(int alertTick, int workTick, int client = -1)
{
    float now = GetEngineTime(), total, peak, work;
    int peakTick, roots;
    float categories[Self_CategoryCount];
    int calls[Self_CategoryCount];
    for (int row = 0; row < g_SelfCount; row++)
    {
        if (now - g_SelfAt[row] > 5.0) continue;
        total += g_SelfTotal[row]; roots++;
        if (g_SelfTotal[row] > peak) { peak = g_SelfTotal[row]; peakTick = g_SelfTick[row]; }
        if (g_SelfTick[row] == workTick) work += g_SelfTotal[row];
        for (int category = 0; category < view_as<int>(Self_CategoryCount); category++)
        { categories[category] += g_SelfMs[row][category]; calls[category] += g_SelfCalls[row][category]; }
    }
    char message[512];
    FormatEx(message, sizeof(message),
        "v=1|mode=%d|alert_tick=%d|work_tick=%d|window_ms=%.3f|tick_peak_ms=%.3f|peak_tick=%d|work_tick_self_ms=%.3f|sampled_ticks=%d|overflow=%d|attribution=wall_inclusive|snapshot_in_progress=1",
        g_CheckLagMode, alertTick, workTick, total, peak, peakTick, work, roots, g_SelfOverflow);
    if (client >= 0) ReplyToCommand(client, "[CheckLag][Self] %s", message);
    else { PluginStats_Record("lag_self_window", message); LogMessage("[CheckLag][Self] %s", message); }
    for (int category = 0; category < view_as<int>(Self_CategoryCount); category++)
    {
        FormatEx(message, sizeof(message), "v=1|alert_tick=%d|category=%s|inclusive_ms=%.3f|calls=%d",
            alertTick, g_SelfNames[category], categories[category], calls[category]);
        if (client >= 0) ReplyToCommand(client, "[CheckLag][Self] %s", message);
        else { PluginStats_Record("lag_self_category", message); LogMessage("[CheckLag][Self] %s", message); }
    }
}

public Action Command_LagSelf(int client, int args)
{
    CheckLag_SelfReport(GetGameTickCount(), GetGameTickCount(), client);
    ReplyToCommand(client, "[CheckLag] Prior completed work only. Snapshot/alert time is reported after completion; category sums are nested and must not be added.");
    return Plugin_Handled;
}

void CheckLag_SelfEmission(int started)
{
    if (started < 0 || started >= g_SelfDepth) return;
    // Stop exactly once; SourceMod rejects a second Stop on the same sample.
    float elapsed = CheckLag_SelfEnd(started);
    char message[192];
    FormatEx(message, sizeof(message), "v=1|mode=%d|emit_tick=%d|alert_pipeline_ms=%.3f|note=excludes_this_summary",
        g_CheckLagMode, GetGameTickCount(), elapsed);
    PluginStats_Record("lag_self_emission", message);
    LogMessage("[CheckLag][SelfEmission] %s", message);
}
