// Modes affect collection as well as output. Do not launch external profilers here.
void CheckLag_ResetProfilingState()
{
    g_LagScopeCount = 0;
    if (g_LagScopeIndexes != null) g_LagScopeIndexes.Clear();
    g_LagScopeDropped = 0;
    g_LagSlowCount = 0;
    g_LagSlowCursor = 0;
    g_LagCallSequence = 0;
    g_LagSlowOverwritten = 0;
    g_LastLagScopeLineCount = 0;
    g_LastLagSnapshotReady = false;
    g_LastLagFrameDetail[0] = '\0';
    CheckLag_ResetFrames();
}

void CheckLag_ApplyMode()
{
    delete g_AdminMonitorTimer;
    g_AdminMonitorTimer = null;
    CheckLag_ResetProfilingState();
    g_RoundQuietUntil = GetEngineTime() + 5.0;
    g_NextAdminAlertAt = g_RoundQuietUntil;
    if (g_CheckLagMode > 0)
        g_AdminMonitorTimer = CreateTimer(CHECKLAG_MONITOR_INTERVAL, Timer_MonitorTickrate, _, TIMER_REPEAT);
}

public void CheckLag_ModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_CheckLagMode = convar.IntValue;
    CheckLag_ApplyMode();
}

public any Native_CheckLagIsProfilingEnabled(Handle plugin, int params)
{
    return g_CheckLagMode == 2;
}

void CheckLag_LogTickrateAlert(int tick, float current, float maximum)
{
    if (g_CheckLagMode != 1) return;
    char message[160];
    FormatEx(message, sizeof(message),
        "v=3|mode=1|alert_tick=%d|rate=%.3f|expected=%.3f|snapshot_kind=automatic",
        tick, current, maximum);
    PluginStats_Record("tickrate_drop", message);
    LogMessage("[CheckLag] %s", message);
}
