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

Handle g_AdminMonitorTimer = null;
float g_NextAdminAlertAt = 0.0;
float g_RoundQuietUntil = 0.0;
#include "checklag_diagnostics.inc"

public Plugin myinfo =
{
    name = "CheckLag",
    author = "Hombre",
    description = "Reports the server's current and expected tickrate.",
    version = "1.2.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errMax)
{
    MarkNativeAsOptional("DGM_IsRoundRunning");
    RegPluginLibrary("checklag");
    CreateNative("CheckLag_RecordScope",Native_CheckLagRecordScope);
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_LagScopeIndexes=new StringMap();g_LastFrameAt=GetEngineTime();
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
    g_AdminMonitorTimer = CreateTimer(CHECKLAG_MONITOR_INTERVAL, Timer_MonitorTickrate, _, TIMER_REPEAT);
}

public void Event_RoundQuietPeriod(Event event, const char[] name, bool dontBroadcast)
{
    CheckLag_ResetFrames();
    g_RoundQuietUntil = GetEngineTime() + 5.0;
    g_NextAdminAlertAt = g_RoundQuietUntil;
}

public void OnMapStart()
{
    CheckLag_ResetFrames();
    g_LagScopeCount=0;if(g_LagScopeIndexes!=null)g_LagScopeIndexes.Clear();
    g_LagScopeDropped = 0;
    g_LagSlowCount = 0;
    g_LagSlowCursor = 0;
    g_LagCallSequence = 0;
    g_LastLagScopeLineCount = 0;
    g_LastLagSnapshotReady = false;
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
    if (GetEngineTime() < g_RoundQuietUntil || !CheckLag_IsRoundRunning())
    {
        return Plugin_Continue;
    }

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
    int measured=CheckLag_RecentMeasuredScope();
    CheckLag_LogSnapshot(serverTick, current, maximum, measured);

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
        if(measured>=0)
            CPrintToChat(client,"{gold}[CheckLag]{default} Measured: %s ({salmon}%.2f ms{default} peak). {gold}!lagdetails{default} for context.",g_LagScopeNames[measured],g_LagScopePeak[measured]);
    }
    return Plugin_Continue;
}

public Action Listener_Chat(int client, const char[] command, int argc)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
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
    char message[128];
    FormatTickrateMessage(message, sizeof(message));
    CPrintToChatAll("%s", message);
    return Plugin_Handled;
}
