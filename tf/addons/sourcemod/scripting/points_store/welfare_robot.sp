// Ownership uses the normal shop receipt. Only the owner's toggle is a cookie.
#define BP_WELFARE_ROBOT_ITEM "automatic_welfare_robot"
Cookie g_WelfareRobotCookie;
bool g_WelfareRobotEnabled[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceLoaded[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceDirty[MAXPLAYERS + 1];
Handle g_WelfareRobotPurchaseTimer[MAXPLAYERS + 1];

void WelfareRobot_OnPluginStart()
{
    g_WelfareRobotCookie = new Cookie("points_store_welfare_robot", "Automatic welfare collection enabled", CookieAccess_Private);
    HookEvent("teamplay_round_start", Event_WelfareRobotRoundStart, EventHookMode_PostNoCopy);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client) && AreClientCookiesCached(client)) WelfareRobot_LoadPreference(client);
    }
}

void WelfareRobot_ResetClient(int client)
{
    delete g_WelfareRobotPurchaseTimer[client];
    g_WelfareRobotEnabled[client] = false;
    g_WelfareRobotPreferenceLoaded[client] = false;
    g_WelfareRobotPreferenceDirty[client] = false;
    // The SQL callback owns the pack; invalidate, never delete it here.
    g_WelfareCollectionRequest[client] = null;
}

void WelfareRobot_OnMapEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_WelfareRobotPurchaseTimer[client];
        g_WelfareCollectionRequest[client] = null;
    }
}

void WelfareRobot_LoadPreference(int client)
{
    if (!IsClientAuthorizedHuman(client) || !AreClientCookiesCached(client)) return;
    if (g_WelfareRobotPreferenceDirty[client])
    {
        // A purchase before cookies loaded must not be overwritten by old data.
        g_WelfareRobotCookie.Set(client, g_WelfareRobotEnabled[client] ? "1" : "0");
        g_WelfareRobotPreferenceDirty[client] = false;
    }
    else
    {
        char value[8];
        g_WelfareRobotCookie.Get(client, value, sizeof(value));
        g_WelfareRobotEnabled[client] = !StrEqual(value, "0");
    }
    g_WelfareRobotPreferenceLoaded[client] = true;
}

bool WelfareRobot_IsOwned(int client)
{
    return Client_IsHumanInGame(client) && g_ClientPurchasesLoaded[client]
        && !Store_HasPendingPurchaseReceipt(client, BP_WELFARE_ROBOT_ITEM)
        && GetCachedPurchasePrice(client, BP_WELFARE_ROBOT_ITEM) > 0;
}

bool WelfareRobot_CanCollect(int client)
{
    return WelfareRobot_IsOwned(client) && g_WelfareRobotPreferenceLoaded[client]
        && g_WelfareRobotEnabled[client];
}

void WelfareRobot_SetEnabled(int client, bool enabled)
{
    g_WelfareRobotEnabled[client] = enabled;
    g_WelfareRobotPreferenceLoaded[client] = true;
    if (AreClientCookiesCached(client))
    {
        g_WelfareRobotCookie.Set(client, enabled ? "1" : "0");
        g_WelfareRobotPreferenceDirty[client] = false;
    }
    else g_WelfareRobotPreferenceDirty[client] = true;
    if (!enabled) delete g_WelfareRobotPurchaseTimer[client];

    char color[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(color, sizeof(color));
    if (enabled)
        CPrintToChat(client, "%s[Gems] You enabled your {gold}Welfare Robot!{default} Welfare will be collected automatically when rounds start.", color);
    else
        CPrintToChat(client, "%s[Gems] Automatic welfare collection disabled. Use {gold}!welfare{default} to toggle your robot.", color);
}

bool WelfareRobot_TryToggle(int client)
{
    if (!WelfareRobot_IsOwned(client)) return false;
    if (!g_WelfareRobotPreferenceLoaded[client]) WelfareRobot_LoadPreference(client);
    if (!g_WelfareRobotPreferenceLoaded[client])
    {
        CPrintToChat(client, "{gold}[Gems]{default} Your Welfare Robot preference is still loading. Try again shortly.");
        return true;
    }
    WelfareRobot_SetEnabled(client, !g_WelfareRobotEnabled[client]);
    return true;
}

void WelfareRobot_OnPurchased(int client, const char[] itemKey)
{
    if (!StrEqual(itemKey, BP_WELFARE_ROBOT_ITEM) || !WelfareRobot_IsOwned(client)) return;
    WelfareRobot_SetEnabled(client, true);
    delete g_WelfareRobotPurchaseTimer[client];
    g_WelfareRobotPurchaseTimer[client] = CreateTimer(3.0, Timer_WelfareRobotPurchase,
        GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_WelfareRobotPurchase(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (client <= 0 || g_WelfareRobotPurchaseTimer[client] != timer) return Plugin_Stop;
    g_WelfareRobotPurchaseTimer[client] = null;
    WelfareRobot_AttemptCollection(client);
    return Plugin_Stop;
}

public void Event_WelfareRobotRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++) WelfareRobot_AttemptCollection(client);
}

void WelfareRobot_AttemptCollection(int client)
{
    if (WelfareRobot_CanCollect(client) && Welfare_GetAvailability(client) == Welfare_Ready)
        Welfare_BeginCollection(client, true);
}

void WelfareRobot_AnnounceCollection(int client, int amount)
{
    char color[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(color, sizeof(color));
    CPrintToChat(client, "%s[Gems]{default} Your {gold}Welfare Robot{default} collected %s%d Gems{default} for you!", color, color, amount);
    SaySounds_TryPlayCommand(client, BP_SOUND_COMMAND, false);
}
