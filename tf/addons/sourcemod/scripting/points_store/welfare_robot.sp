// Ownership uses the normal shop receipt. Only the owner's toggle is a cookie.
#define BP_WELFARE_ROBOT_ITEM "automatic_welfare_robot"
Cookie g_WelfareRobotCookie;
bool g_WelfareRobotEnabled[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceLoaded[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceDirty[MAXPLAYERS + 1];
bool g_WelfareRobotCollectionPending[MAXPLAYERS + 1];
bool g_WelfareRobotAllowSpectator[MAXPLAYERS + 1];
Handle g_WelfareRobotPurchaseTimer[MAXPLAYERS + 1];

void WelfareRobot_OnPluginStart()
{
    g_WelfareRobotCookie = new Cookie("points_store_welfare_robot", "Automatic welfare collection enabled", CookieAccess_Private);
    RegConsoleCmd("sm_welfarebot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    RegConsoleCmd("sm_welfarerobot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    RegConsoleCmd("sm_bot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    HookEvent("teamplay_round_start", Event_WelfareRobotRoundStart, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_win", Event_WelfareRobotRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_WelfareRobotTeamChanged, EventHookMode_Post);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client)) continue;
        g_WelfareRobotCollectionPending[client] = true;
        if (AreClientCookiesCached(client)) WelfareRobot_LoadPreference(client);
    }
}

void WelfareRobot_ResetClient(int client)
{
    delete g_WelfareRobotPurchaseTimer[client];
    g_WelfareRobotEnabled[client] = false;
    g_WelfareRobotPreferenceLoaded[client] = false;
    g_WelfareRobotPreferenceDirty[client] = false;
    g_WelfareRobotCollectionPending[client] = false;
    g_WelfareRobotAllowSpectator[client] = false;
    // The SQL callback owns the pack; invalidate, never delete it here.
    g_WelfareCollectionRequest[client] = null;
}

void WelfareRobot_OnMapEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_WelfareRobotPurchaseTimer[client];
        g_WelfareRobotCollectionPending[client] = false;
        g_WelfareRobotAllowSpectator[client] = false;
        g_WelfareCollectionRequest[client] = null;
    }
}

void WelfareRobot_OnMapStart()
{
    // Arm independently of asynchronous ownership/cookie/per-map readiness.
    // Do not collect until the per-map reset/restore callback has completed.
    for (int client = 1; client <= MaxClients; client++)
    {
        g_WelfareRobotCollectionPending[client] = Client_IsHumanInGame(client);
        g_WelfareRobotAllowSpectator[client] = false;
    }
}

void WelfareRobot_OnClientPutInServer(int client)
{
    if (!Client_IsHumanInGame(client)) return;
    // Clients can finish loading after the map's initial round-start event.
    g_WelfareRobotCollectionPending[client] = true;
    g_WelfareRobotAllowSpectator[client] = false;
    if (AreClientCookiesCached(client)) WelfareRobot_LoadPreference(client);
    WelfareRobot_ResumePendingCollections();
}

void WelfareRobot_LoadPreference(int client, bool resumeCollection = true)
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
    if (resumeCollection) WelfareRobot_ResumeCollection(client);
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
    if (!enabled)
    {
        delete g_WelfareRobotPurchaseTimer[client];
        g_WelfareRobotCollectionPending[client] = false;
        g_WelfareRobotAllowSpectator[client] = false;
    }

    char color[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(color, sizeof(color));
    if (enabled)
        CPrintToChat(client, "%s[Gems]{default} You enabled your {gold}Welfare Robot!{default} Welfare will be collected automatically when rounds start.", color);
    else
        CPrintToChat(client, "%s[Gems]{default} Automatic welfare collection disabled. Use {gold}!welfarebot{default} to toggle your robot.", color);
}

public Action Command_WelfareRobot(int client, int args)
{
    if (!Client_IsHumanInGame(client)) return Plugin_Handled;
    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    if (!g_ClientPurchasesLoaded[client]
        || Store_HasPendingPurchaseReceipt(client, BP_WELFARE_ROBOT_ITEM))
    {
        LoadClientPurchases(client);
        CPrintToChat(client, "%s Your Welfare Robot ownership is still loading. Try again shortly.", prefix);
        return Plugin_Handled;
    }
    if (!WelfareRobot_IsOwned(client))
    {
        CPrintToChat(client, "%s You do not own a {gold}Welfare Robot{default}. Purchase one in {gold}!shop{default}.", prefix);
        return Plugin_Handled;
    }
    // Reading cookies for a toggle must not trigger a pending collection first.
    if (!g_WelfareRobotPreferenceLoaded[client]) WelfareRobot_LoadPreference(client, false);
    if (!g_WelfareRobotPreferenceLoaded[client])
    {
        CPrintToChat(client, "%s Your Welfare Robot preference is still loading. Try again shortly.", prefix);
        return Plugin_Handled;
    }
    WelfareRobot_SetEnabled(client, !g_WelfareRobotEnabled[client]);
    return Plugin_Handled;
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
    for (int client = 1; client <= MaxClients; client++)
    {
        g_WelfareRobotAllowSpectator[client] = false;
        WelfareRobot_AttemptCollection(client);
    }
}

public void Event_WelfareRobotTeamChanged(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetBool("disconnect")) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    int team = event.GetInt("team");
    if (Client_IsHumanInGame(client) && (team == 2 || team == 3))
        WelfareRobot_ResumeCollection(client);
}

public void Event_WelfareRobotRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_WelfareRobotCollectionPending[client]) WelfareRobot_AttemptCollection(client, true);
    }
}

void WelfareRobot_AttemptCollection(int client, bool allowSpectator = false)
{
    if (!Client_IsHumanInGame(client)) return;
    g_WelfareRobotCollectionPending[client] = true;
    if (allowSpectator) g_WelfareRobotAllowSpectator[client] = true;
    WelfareRobot_ResumeCollection(client);
}

void WelfareRobot_ResumePendingCollections()
{
    for (int client = 1; client <= MaxClients; client++) WelfareRobot_ResumeCollection(client);
}

void WelfareRobot_ResumeCollection(int client)
{
    if (client <= 0 || client > MaxClients || !g_WelfareRobotCollectionPending[client]
        || !Client_IsHumanInGame(client)) return;
    // "Not loaded yet" is not the same as "does not own an enabled robot".
    if (!g_ClientPurchasesLoaded[client] || !g_WelfareRobotPreferenceLoaded[client]
        || Store_HasPendingPurchaseReceipt(client, BP_WELFARE_ROBOT_ITEM)) return;
    if (!WelfareRobot_CanCollect(client))
    {
        g_WelfareRobotCollectionPending[client] = false;
        g_WelfareRobotAllowSpectator[client] = false;
        return;
    }
    if (g_WelfareRobotPurchaseTimer[client] != null) return;
    int team = GetClientTeam(client);
    if (!g_WelfareRobotAllowSpectator[client] && team != 2 && team != 3) return;
    WelfareAvailability availability = Welfare_GetAvailability(client);
    if (availability == Welfare_Ready || availability == Welfare_AlreadyCollected
        || availability == Welfare_Disabled || availability == Welfare_RequestPending)
    {
        // Consume before starting SQL. Request ownership and the per-map guard
        // protect concurrent/manual collections. Loading/transient states stay
        // pending until a readiness callback or lifecycle event wakes them.
        g_WelfareRobotCollectionPending[client] = false;
        g_WelfareRobotAllowSpectator[client] = false;
        if (availability == Welfare_Ready) Welfare_BeginCollection(client, true);
    }
}

void WelfareRobot_AnnounceCollection(int client, int amount)
{
    char color[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(color, sizeof(color));
    CPrintToChat(client, "%s[Gems]{default} Your {gold}Welfare Robot{default} collected %s%d Gems{default} for you!", color, color, amount);
    SaySounds_TryPlayCommand(client, BP_SOUND_COMMAND, false);
}
