#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name = "KOTH timer progress regression probe",
    author = "Hombre",
    description = "Tests the production progress helper and empty-MGE event integration.",
    version = "1.0"
};

int gChecks;
int gFailures;
bool gTimersAvailable;
bool gRefsValid;
float gTestTimes[2];
bool gIntegrationPending;
int gIntegrationRedRef = INVALID_ENT_REFERENCE;
int gIntegrationBluRef = INVALID_ENT_REFERENCE;
char gIntegrationPreviousMode[64];
int gIntegrationPreviousEnabled;
int gIntegrationPreviousGuards;

void TestFindTimers(int &red, int &blu)
{
    red = gTimersAvailable ? 101 : -1;
    blu = gTimersAvailable ? 102 : -1;
}
float TestRemaining(int timer)
{
    return timer == 101 ? gTestTimes[0] : gTestTimes[1];
}
int TestToRef(int timer) { return timer + 1000; }
int TestFromRef(int ref) { return gRefsValid ? ref - 1000 : INVALID_ENT_REFERENCE; }
void TestLog(const char[] format, any ...)
{
    #pragma unused format
}

#define DGM_FindKothTimers TestFindTimers
#define DGM_GetRoundTimerRemainingFloat TestRemaining
#define EntIndexToEntRef TestToRef
#define EntRefToEntIndex TestFromRef
#define LogWhale TestLog
#include "whalebalance/koth_timer_progress.sp"
#undef DGM_FindKothTimers
#undef DGM_GetRoundTimerRemainingFloat
#undef EntIndexToEntRef
#undef EntRefToEntIndex
#undef LogWhale

void Check(bool result, const char[] label)
{
    gChecks++;
    if (!result)
    {
        gFailures++;
        PrintToServer("[KothProgressProbe] FAIL %s", label);
    }
}

KothTimerProgress Decision()
{
    float red;
    float blu;
    return GetKothTimerProgress(red, blu);
}

public void OnPluginStart()
{
    RegAdminCmd("sm_koth_progress_probe", RunUnitTests, ADMFLAG_ROOT);
    RegAdminCmd("sm_koth_progress_integration", RunIntegration, ADMFLAG_ROOT);
    RegAdminCmd("sm_koth_progress_status", Status, ADMFLAG_ROOT);
}

public Action RunUnitTests(int client, int args)
{
    #pragma unused client
    #pragma unused args
    gChecks = gFailures = 0;
    ResetKothTimerProgress();
    gTimersAvailable = false;
    gRefsValid = true;
    Check(Decision() == KothTimerProgress_Unavailable, "no first capture falls back");
    RecordKothFirstCaptureTimers();
    Check(Decision() == KothTimerProgress_Unavailable, "missing timers fall back");
    gTimersAvailable = true;
    gTestTimes[0] = gTestTimes[1] = 300.0;
    RecordKothFirstCaptureTimers();
    Check(!g_bKothTimerBaselineValid, "do not retry a missed FIRST capture later");

    ResetKothTimerProgress();
    gTestTimes[0] = 300.0;
    gTestTimes[1] = 600.0;
    RecordKothFirstCaptureTimers();
    Check(g_bKothTimerBaselineValid, "positive asymmetric baselines recorded");
    Check(g_flKothFirstCaptureTimes[0] == 300.0 && g_flKothFirstCaptureTimes[1] == 600.0,
        "each team uses its own baseline");
    gTestTimes[0] = 0.0;
    gTestTimes[1] = 486.0;
    Check(Decision() == KothTimerProgress_Stomp, "19 percent consumed triggers");
    Check(KothTimerProgressNeedsScramble(Decision(), true, true), "both teams capped but low progress triggers");
    gTestTimes[1] = 480.0;
    Check(Decision() == KothTimerProgress_Stomp, "exactly 20 percent triggers");
    gTestTimes[1] = 479.9;
    Check(Decision() == KothTimerProgress_Competitive, "more than 20 percent avoids trigger");
    Check(!KothTimerProgressNeedsScramble(Decision(), false, true), "valid progress overrides capture fallback");
    gTestTimes[0] = 240.0;
    gTestTimes[1] = 0.0;
    Check(Decision() == KothTimerProgress_Stomp, "RED boundary is symmetric");
    gTestTimes[0] = 239.9;
    Check(Decision() == KothTimerProgress_Competitive, "RED more than 20 percent avoids trigger");
    gTestTimes[0] = gTestTimes[1] = 0.0;
    Check(Decision() == KothTimerProgress_Competitive, "expired timers are valid end values");
    RecordKothFirstCaptureTimers();
    Check(g_flKothFirstCaptureTimes[0] == 300.0 && g_flKothFirstCaptureTimes[1] == 600.0,
        "recaptures never overwrite baseline");
    gTestTimes[0] = -1.0;
    Check(Decision() == KothTimerProgress_Unavailable, "unreadable end time falls back");
    gTestTimes[0] = 100.0;
    gRefsValid = false;
    Check(Decision() == KothTimerProgress_Unavailable, "removed or recycled entity falls back");
    Check(!KothTimerProgressNeedsScramble(Decision(), true, true), "fallback both captured skips");
    Check(KothTimerProgressNeedsScramble(Decision(), true, false), "fallback BLU never captured triggers");
    Check(KothTimerProgressNeedsScramble(Decision(), false, true), "fallback RED never captured triggers");
    Check(KothTimerProgressNeedsScramble(Decision(), false, false), "fallback neither captured triggers");
    ResetKothTimerProgress();
    Check(!g_bKothTimerBaselineAttempted && !g_bKothTimerBaselineValid, "round reset clears flags");
    Check(g_iKothFirstCaptureTimerRefs[0] == INVALID_ENT_REFERENCE
        && g_iKothFirstCaptureTimerRefs[1] == INVALID_ENT_REFERENCE, "round reset clears references");
    Check(g_flKothFirstCaptureTimes[0] == 0.0 && g_flKothFirstCaptureTimes[1] == 0.0,
        "round reset clears baselines");
    gRefsValid = true;
    gTestTimes[0] = 0.0;
    RecordKothFirstCaptureTimers();
    Check(!g_bKothTimerBaselineValid, "zero first-capture baseline falls back");
    ResetKothTimerProgress();
    gTestTimes[0] = 180.0;
    gTestTimes[1] = 240.0;
    RecordKothFirstCaptureTimers();
    Check(g_bKothTimerBaselineValid && g_flKothFirstCaptureTimes[0] == 180.0
        && g_flKothFirstCaptureTimes[1] == 240.0, "next round records fresh baselines");
    PrintToServer("[KothProgressProbe] checks=%d failures=%d", gChecks, gFailures);
    return Plugin_Handled;
}

int CountHumans()
{
    int humans;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientConnected(client) && !IsFakeClient(client)
            && !IsClientSourceTV(client) && !IsClientReplay(client))
            humans++;
    }
    return humans;
}

public Action Status(int client, int args)
{
    #pragma unused client
    #pragma unused args
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));
    PrintToServer("[KothProgressProbe] status map=%s humans=%d", map, CountHumans());
    return Plugin_Handled;
}

void InvokeRoundStart(Handle plugin)
{
    Event event = CreateEvent("teamplay_round_start", true);
    Call_StartFunction(plugin, GetFunctionByName(plugin, "WhaleBalance_Event_RoundStart"));
    Call_PushCell(event);
    Call_PushString("teamplay_round_start");
    Call_PushCell(true);
    Call_Finish();
    delete event;
}

void InvokeCapture(Handle plugin, int team)
{
    Event event = CreateEvent("teamplay_point_captured", true);
    event.SetInt("team", team);
    Call_StartFunction(plugin, GetFunctionByName(plugin, "WhaleBalance_Event_PointCaptured"));
    Call_PushCell(event);
    Call_PushString("teamplay_point_captured");
    Call_PushCell(true);
    Call_Finish();
    delete event;
}

void InvokeRoundWin(Handle plugin)
{
    Event event = CreateEvent("teamplay_round_win", true);
    event.SetBool("full_round", true);
    event.SetInt("team", 3);
    Call_StartFunction(plugin, GetFunctionByName(plugin, "WhaleBalance_Event_RoundWin"));
    Call_PushCell(event);
    Call_PushString("teamplay_round_win");
    Call_PushCell(true);
    Call_Finish();
    delete event;
}

int MakeTimer(const char[] name)
{
    int timer = CreateEntityByName("team_round_timer");
    if (timer == -1) return -1;
    DispatchKeyValue(timer, "targetname", name);
    DispatchKeyValue(timer, "timer_length", "300");
    DispatchKeyValue(timer, "start_paused", "1");
    DispatchKeyValue(timer, "show_in_hud", "0");
    DispatchKeyValue(timer, "auto_countdown", "0");
    DispatchSpawn(timer);
    AcceptEntityInput(timer, "Pause");
    SetEntProp(timer, Prop_Send, "m_bAutoCountdown", 0);
    SetEntPropFloat(timer, Prop_Send, "m_flTimeRemaining", 300.0);
    return timer;
}

// Calls the live plugin's copied-event callbacks without broadcasting synthetic
// events to other plugins, ending the actual round, or moving any players.
// Argument chooses case: 1=20%-stomp, 2=>20%-competitive, 3=missing timer.
public Action RunIntegration(int client, int args)
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));
    if (client != 0 || CountHumans() != 0 || StrContains(map, "mge_", false) != 0 || gIntegrationPending)
    {
        PrintToServer("[KothProgressProbe] integration refused: console on empty MGE only");
        return Plugin_Handled;
    }
    if (args != 1)
    {
        PrintToServer("[KothProgressProbe] integration requires case 1, 2, or 3");
        return Plugin_Handled;
    }
    char arg[8];
    GetCmdArg(1, arg, sizeof(arg));
    int testCase = StringToInt(arg);
    Handle plugin = FindPluginByFile("whalescramble.smx");
    if (testCase < 1 || testCase > 3 || plugin == null || GetPluginStatus(plugin) != Plugin_Running)
    {
        PrintToServer("[KothProgressProbe] integration refused: case/plugin unavailable");
        return Plugin_Handled;
    }
    ConVar mode = FindConVar("sm_gamemode");
    ConVar enabled = FindConVar("sm_whalescramble_koth_no_cap");
    ConVar guards = FindConVar("sm_whalescramble_no_sequential");
    if (mode == null || enabled == null || guards == null)
        return Plugin_Handled;
    mode.GetString(gIntegrationPreviousMode, sizeof(gIntegrationPreviousMode));
    gIntegrationPreviousEnabled = enabled.IntValue;
    gIntegrationPreviousGuards = guards.IntValue;
    gIntegrationPending = true;
    mode.SetString("King of the Hill");
    enabled.SetInt(1);
    guards.SetInt(0);
    InvokeRoundStart(plugin);
    int red = MakeTimer("zz_red_koth_timer");
    int blu = MakeTimer("zz_blue_koth_timer");
    gIntegrationRedRef = red == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(red);
    gIntegrationBluRef = blu == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(blu);
    if (red != -1 && blu != -1)
    {
        InvokeCapture(plugin, 2);
        SetEntPropFloat(red, Prop_Send, "m_flTimeRemaining", 30.0);
        SetEntPropFloat(blu, Prop_Send, "m_flTimeRemaining", 270.0);
        InvokeCapture(plugin, 3); // must NOT overwrite 300/300 baseline
        if (testCase == 3) RemoveEntity(blu);
        else SetEntPropFloat(blu, Prop_Send, "m_flTimeRemaining", testCase == 1 ? 240.0 : 239.0);
        // RemoveEntity is deferred by the engine. Wait before reading the
        // removed timer's entref; otherwise case 3 still sees a live entity.
        CreateTimer(0.2, FinishIntegration, testCase, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Handled;
    }
    else PrintToServer("[KothProgressProbe] integration FAIL timer creation");
    CleanupIntegration();
    return Plugin_Handled;
}

public Action FinishIntegration(Handle timer, int testCase)
{
    #pragma unused timer
    Handle plugin = FindPluginByFile("whalescramble.smx");
    if (CountHumans() == 0 && plugin != null && GetPluginStatus(plugin) == Plugin_Running)
    {
        InvokeRoundWin(plugin);
        PrintToServer("[KothProgressProbe] integration case=%d complete; verify KOTH decision in log", testCase);
    }
    CleanupIntegration();
    return Plugin_Stop;
}

void CleanupIntegration()
{
    if (!gIntegrationPending) return;
    int red = EntRefToEntIndex(gIntegrationRedRef);
    int blu = EntRefToEntIndex(gIntegrationBluRef);
    if (red != INVALID_ENT_REFERENCE && IsValidEntity(red)) RemoveEntity(red);
    if (blu != INVALID_ENT_REFERENCE && IsValidEntity(blu)) RemoveEntity(blu);
    ConVar mode = FindConVar("sm_gamemode");
    ConVar enabled = FindConVar("sm_whalescramble_koth_no_cap");
    ConVar guards = FindConVar("sm_whalescramble_no_sequential");
    if (mode != null) mode.SetString(gIntegrationPreviousMode);
    if (enabled != null) enabled.SetInt(gIntegrationPreviousEnabled);
    if (guards != null) guards.SetInt(gIntegrationPreviousGuards);
    gIntegrationPending = false;
    gIntegrationRedRef = gIntegrationBluRef = INVALID_ENT_REFERENCE;
}

public void OnPluginEnd()
{
    CleanupIntegration();
}

public void OnMapEnd()
{
    CleanupIntegration();
}
