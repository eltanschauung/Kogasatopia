#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <multicolors>
#include <plugin_statistics>

#undef REQUIRE_PLUGIN
#include <dgm_api>
#define REQUIRE_PLUGIN

#define CHECKLAG_HEALTHY_TICKRATE 62.0
#define CHECKLAG_MONITOR_INTERVAL 1.0
#define CHECKLAG_ADMIN_ALERT_INTERVAL 4.0

ConVar g_CheckLagModeConVar;
int g_CheckLagMode = 1;
Handle g_AdminMonitorTimer = null;
float g_NextAdminAlertAt = 0.0;
float g_RoundQuietUntil = 0.0;
#include "checklag_self.inc"
#include "checklag_diagnostics.inc"
#include "checklag_mode.inc"

public Plugin myinfo =
{
    name = "CheckLag",
    author = "Hombre",
    description = "Reports the server's current and expected tickrate.",
    version = "1.6.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errMax)
{
    MarkNativeAsOptional("DGM_IsRoundRunning");
    RegPluginLibrary("checklag");
    CreateNative("CheckLag_RecordScope",Native_CheckLagRecordScope);
    CreateNative("CheckLag_IsProfilingEnabled", Native_CheckLagIsProfilingEnabled);
    CreateNative("CheckLagDebug_ObserverCosts", Native_CheckLagObserverCosts);
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_LagScopeIndexes=new StringMap();
    g_CheckLagModeConVar = CreateConVar("sm_checklag_mode", "1",
        "CheckLag: 0=off, 1=alerts, 2=cheap frame evidence, 3=sampled bounded profiling.", _, true, 0.0, true, 3.0);
    // Reloads retain an existing ConVar object and its old upper bound.
    g_CheckLagModeConVar.SetBounds(ConVarBound_Upper, true, 3.0);
    RegAdminCmd("sm_lagself", Command_LagSelf, ADMFLAG_ROOT, "Completed observer costs (frame hot path is deliberately unprofiled).");
    g_CheckLagMode = g_CheckLagModeConVar.IntValue;
    g_CheckLagModeConVar.AddChangeHook(CheckLag_ModeChanged);
    RegAdminCmd("sm_lagdetails",Command_LagDetails,ADMFLAG_ROOT,"Recent measured callback times and network context.");
    RegAdminCmd("sm_lagsnapshot", Command_LagSnapshot, ADMFLAG_ROOT, "Persist current timings without classifying them as a tickrate drop.");
    RegConsoleCmd("sm_lag", Command_CheckLag, "Broadcast the server tickrate.");
    RegConsoleCmd("sm_checklag", Command_CheckLag, "Broadcast the server tickrate.");
    RegConsoleCmd("sm_ddos", Command_CheckLag, "Broadcast the server tickrate.");
    AddCommandListener(Listener_Chat, "say");
    AddCommandListener(Listener_Chat, "say_team");
    HookEvent("teamplay_round_start", Event_RoundQuietPeriod, EventHookMode_PostNoCopy);
    HookEventEx("teamplay_round_end", Event_RoundQuietPeriod, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_win", Event_RoundQuietPeriod, EventHookMode_PostNoCopy);
    HookEventEx("teamplay_round_stalemate", Event_RoundQuietPeriod, EventHookMode_PostNoCopy);
    CheckLag_ApplyMode();
}

public void Event_RoundQuietPeriod(Event event, const char[] name, bool dontBroadcast)
{
    CheckLag_ResetFrames();
    g_RoundQuietUntil = GetEngineTime() + 5.0;
    g_NextAdminAlertAt = g_RoundQuietUntil;
}

public void OnMapStart()
{
    CheckLag_SelfReset();
    CheckLag_ResetProfilingState();
    g_RoundQuietUntil = GetEngineTime() + 5.0;
    g_NextAdminAlertAt = g_RoundQuietUntil;
}

bool CheckLag_IsRoundRunning()
{
    Handle provider = FindPluginByFile("whalescramble.smx");
    if (provider != INVALID_HANDLE && GetPluginStatus(provider) != Plugin_Running)
        return false;
    return GetFeatureStatus(FeatureType_Native, "DGM_IsRoundRunning") == FeatureStatus_Available
        && DGM_IsRoundRunning();
}

public void OnPluginEnd()
{
    delete g_AdminMonitorTimer;
    g_AdminMonitorTimer = null;
    delete g_LagScopeIndexes;
    delete g_LagFrameClock;
    delete g_LagHostClock;
    delete g_LagHostIntervalClock;
    CheckLag_SelfShutdown();
}

bool IsWordCharacter(char value)
{
    return (value >= 'a' && value <= 'z')
        || (value >= 'A' && value <= 'Z')
        || (value >= '0' && value <= '9')
        || value == '_';
}

bool ContainsKeyword(const char[] message, const char[] keyword)
{
    int messageLength = strlen(message);
    int keywordLength = strlen(keyword);
    for (int start = 0; start + keywordLength <= messageLength; start++)
    {
        bool matches = true;
        for (int offset = 0; offset < keywordLength; offset++)
        {
            if (CharToLower(message[start + offset]) != CharToLower(keyword[offset]))
            {
                matches = false;
                break;
            }
        }

        if (matches
            && (start == 0 || !IsWordCharacter(message[start - 1]))
            && (start + keywordLength == messageLength || !IsWordCharacter(message[start + keywordLength])))
        {
            return true;
        }
    }
    return false;
}

bool IsBroadcastCommand(const char[] message)
{
    if (message[0] != '!' && message[0] != '/')
    {
        return false;
    }

    char command[32];
    int write = 0;
    for (int read = 1; message[read] != '\0' && message[read] != ' ' && write < sizeof(command) - 1; read++)
    {
        command[write++] = message[read];
    }
    command[write] = '\0';

    return StrEqual(command, "lag", false)
        || StrEqual(command, "checklag", false)
        || StrEqual(command, "ddos", false);
}

void FormatTickrateMessage(char[] message, int maxlen)
{
    float current = PluginStats_GetObservedTickrate();
    float maximum = PluginStats_GetExpectedTickrate();
    char color[16];
    strcopy(color, sizeof(color), current >= CHECKLAG_HEALTHY_TICKRATE ? "{green}" : "{salmon}");
    Format(message, maxlen, "{gold}[CheckLag]{default} Server tickrate: %s%.1f/%.1f", color, current, maximum);
}

void PrintTickrateToClient(int client)
{
    char message[128];
    FormatTickrateMessage(message, sizeof(message));
    CPrintToChat(client, "%s", message);
}

public Action Timer_MonitorTickrate(Handle timer)
{
    if (g_CheckLagMode == 0) return Plugin_Stop;
    int self = CheckLag_SelfBegin(Self_Monitor);
    Action action = CheckLag_MonitorTickrate();
    CheckLag_SelfEnd(self);
    return action;
}

Action CheckLag_MonitorTickrate()
{
    if (g_CheckLagMode == 0)
        return Plugin_Stop;
    if (GetEngineTime() < g_RoundQuietUntil || !CheckLag_IsRoundRunning())
    {
        return Plugin_Continue;
    }

    // Kernel reads are never on the frame/scope hot paths, even after a stall.
    if (g_CheckLagMode == 3) CheckLag_HostPoll(GetEngineTime(), false);
    float current = PluginStats_GetObservedTickrate();
    if (current >= CHECKLAG_HEALTHY_TICKRATE)
    {
        return Plugin_Continue;
    }

    float now = GetEngineTime();
    if (now < g_NextAdminAlertAt)
    {
        return Plugin_Continue;
    }

    float maximum = PluginStats_GetExpectedTickrate();
    int serverTick = GetGameTickCount();
    g_NextAdminAlertAt = now + CHECKLAG_ADMIN_ALERT_INTERVAL;
    int emission = CheckLag_SelfBegin(Self_Snapshot);
    if (g_CheckLagMode >= 2)
        CheckLag_LogSnapshot(serverTick, current, maximum, CheckLag_RecentMeasuredScope());
    else
        CheckLag_LogTickrateAlert(serverTick, current, maximum);
    CheckLag_SelfReport(serverTick, serverTick - 1);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)
            || !(GetUserFlagBits(client) & ADMFLAG_ROOT))
        {
            continue;
        }

        CPrintToChat(client,
            "{gold}[CheckLag] {green}(Admins){default} Lag detected at Tick #%d: {salmon}%.1f/%.1f",
            serverTick,
            current,
            maximum);
        if (g_CheckLagMode == 3)
        {
            int call = CheckLag_FrameMeasuredCall(CheckLag_RecentFrameRow());
            if (call >= 0)
                CPrintToChat(client,"{gold}[CheckLag]{default} Sampled interval on stalled frame: %s ({salmon}%.2f ms{default}, inclusive). {gold}!lagdetails{default} for context.",
                    g_LagScopeNames[g_LagSlowScope[call]], g_LagSlowDuration[call]);
            else
                CPrintToChat(client,"{gold}[CheckLag]{default} No matching sampled interval on the stalled frame. Sampling can miss the cause. {gold}!lagdetails{default} for context.");
        }
    }
    CheckLag_SelfEmission(emission);
    return Plugin_Continue;
}

public Action Listener_Chat(int client, const char[] command, int argc)
{
    if (g_CheckLagMode == 0 || client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return Plugin_Continue;
    }

    char message[256];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);
    TrimString(message);
    if (!IsBroadcastCommand(message)
        && (ContainsKeyword(message, "lag") || ContainsKeyword(message, "ddos")))
    {
        PrintTickrateToClient(client);
    }
    return Plugin_Continue;
}

public Action Command_CheckLag(int client, int args)
{
    if (g_CheckLagMode == 0)
    {
        ReplyToCommand(client, "[CheckLag] Disabled (sm_checklag_mode 0).");
        return Plugin_Handled;
    }
    char message[128];
    FormatTickrateMessage(message, sizeof(message));
    CPrintToChatAll("%s", message);
    return Plugin_Handled;
}
