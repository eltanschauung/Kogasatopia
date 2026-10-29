// Ownership uses the normal shop receipt. Only the owner's toggle is a cookie.
#define BP_WELFARE_ROBOT_ITEM "automatic_welfare_robot"
#define BP_WELFARE_ROBOT_RETRY_INTERVAL 1.0
#define BP_WELFARE_ROBOT_LOAD_RETRY_INTERVAL 5.0
Cookie g_WelfareRobotCookie;
bool g_WelfareRobotEnabled[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceLoaded[MAXPLAYERS + 1];
bool g_WelfareRobotPreferenceDirty[MAXPLAYERS + 1];
bool g_WelfareRobotCollectionPending[MAXPLAYERS + 1];
bool g_WelfareRobotAllowSpectator[MAXPLAYERS + 1];
Handle g_WelfareRobotPurchaseTimer[MAXPLAYERS + 1];
// Identity-scoped so reconnects and recycled client slots cannot rearm the
// first-join trigger. This is map-local state, not a persistent preference.
StringMap g_WelfareRobotTeamJoinsThisMap;
Handle g_WelfareRobotRetryTimer;
float g_WelfareRobotNextLoadRetry[MAXPLAYERS + 1];
float g_WelfareRobotNextPoolRetry;

void WelfareRobot_OnPluginStart()
{
    g_WelfareRobotTeamJoinsThisMap = new StringMap();
    g_WelfareRobotCookie = new Cookie("points_store_welfare_robot", "Automatic welfare collection enabled", CookieAccess_Private);
    RegConsoleCmd("sm_welfarebot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    RegConsoleCmd("sm_welfarerobot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    RegConsoleCmd("sm_bot", Command_WelfareRobot, "Toggle your Automatic Welfare Robot.");
    HookEvent("teamplay_round_start", Event_WelfareRobotRoundStart, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_win", Event_WelfareRobotRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_WelfareRobotTeamChanged, EventHookMode_Post);
    HookEvent("player_spawn", Event_WelfareRobotSpawn, EventHookMode_Post);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client)) continue;
        int team = GetClientTeam(client);
        if (team == 2 || team == 3) WelfareRobot_RecordFirstTeamJoin(client);
        g_WelfareRobotCollectionPending[client] = true;
        if (AreClientCookiesCached(client)) WelfareRobot_LoadPreference(client);
    }
    WelfareRobot_QueueRetry(true);
}

void WelfareRobot_OnPluginEnd()
{
    delete g_WelfareRobotRetryTimer;
    delete g_WelfareRobotTeamJoinsThisMap;
}

void WelfareRobot_ResetClient(int client)
{
    delete g_WelfareRobotPurchaseTimer[client];
    g_WelfareRobotEnabled[client] = false;
    g_WelfareRobotPreferenceLoaded[client] = false;
    g_WelfareRobotPreferenceDirty[client] = false;
    g_WelfareRobotCollectionPending[client] = false;
    g_WelfareRobotAllowSpectator[client] = false;
    g_WelfareRobotNextLoadRetry[client] = 0.0;
    // The SQL callback owns the pack; invalidate, never delete it here.
    g_WelfareCollectionRequest[client] = null;
}

void WelfareRobot_OnMapEnd()
{
    delete g_WelfareRobotRetryTimer;
    g_WelfareRobotNextPoolRetry = 0.0;
    g_WelfareRobotTeamJoinsThisMap.Clear();
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_WelfareRobotPurchaseTimer[client];
        g_WelfareRobotCollectionPending[client] = false;
        g_WelfareRobotAllowSpectator[client] = false;
        g_WelfareRobotNextLoadRetry[client] = 0.0;
        g_WelfareCollectionRequest[client] = null;
    }
}

void WelfareRobot_OnMapStart()
{
    // First-join identities were cleared at map end. Do not clear them here:
    // late loading seeds already-playing clients before the initial MapStart.
    // Arm independently of asynchronous ownership/cookie/per-map readiness.
    // Do not collect until the per-map reset/restore callback has completed.
    for (int client = 1; client <= MaxClients; client++)
    {
        g_WelfareRobotCollectionPending[client] = Client_IsHumanInGame(client);
        g_WelfareRobotAllowSpectator[client] = false;
    }
    WelfareRobot_QueueRetry(true);
}

void WelfareRobot_OnClientPutInServer(int client)
{
    if (!Client_IsHumanInGame(client)) return;
    // Clients can finish loading after the map's initial round-start event.
    g_WelfareRobotCollectionPending[client] = true;
    g_WelfareRobotAllowSpectator[client] = false;
    WelfareRobot_OnClientReady(client);
}

void WelfareRobot_OnClientReady(int client)
{
    if (!Client_IsHumanInGame(client)) return;
    // Authorization is a readiness signal, not a new collection opportunity:
    // preserve any round-end spectator permission granted while it loaded.
    if (AreClientCookiesCached(client)) WelfareRobot_LoadPreference(client);
    WelfareRobot_ResumePendingCollections();
    WelfareRobot_QueueRetry(true);
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

    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    if (enabled)
        CPrintToChat(client, "%s You enabled your {gold}Welfare Robot!{default} Welfare will be collected automatically when rounds start.", prefix);
    else
        CPrintToChat(client, "%s Automatic welfare collection disabled. Use {gold}!welfarebot{default} to toggle your robot.", prefix);
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
    if (!Client_IsHumanInGame(client) || (team != 2 && team != 3)) return;

    if (WelfareRobot_RecordFirstTeamJoin(client))
    {
        // This is a new collection opportunity, not merely a readiness signal:
        // earlier ownership/toggle/allowance checks may have consumed pending.
        WelfareRobot_AttemptCollection(client);
    }
    else WelfareRobot_ResumeCollection(client);
    // The event's new team can precede the client's observable team property.
    WelfareRobot_QueueRetry(true);
}

public void Event_WelfareRobotSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Client_IsHumanInGame(client)) return;
    int team = GetClientTeam(client);
    if (team != 2 && team != 3) return;
    // Some map/client restore sequences do not emit a spectator->team event.
    if (WelfareRobot_RecordFirstTeamJoin(client)) WelfareRobot_AttemptCollection(client);
    else WelfareRobot_ResumeCollection(client);
    WelfareRobot_QueueRetry();
}

bool WelfareRobot_RecordFirstTeamJoin(int client)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))) return false;
    int seen;
    if (g_WelfareRobotTeamJoinsThisMap.GetValue(steamId, seen)) return false;
    g_WelfareRobotTeamJoinsThisMap.SetValue(steamId, 1);
    return true;
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
    WelfareRobot_QueueRetry();
}

void WelfareRobot_ResumePendingCollections()
{
    for (int client = 1; client <= MaxClients; client++) WelfareRobot_ResumeCollection(client);
    WelfareRobot_QueueRetry();
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
        || availability == Welfare_Disabled)
    {
        // Consume before starting SQL. Request ownership and the per-map guard
        // protect concurrent/manual collections. Loading/transient states stay
        // pending until a readiness callback, lifecycle event or retry wakes them.
        g_WelfareRobotCollectionPending[client] = false;
        // Retain fallback permission while SQL is in flight, so a failed
        // round-end withdrawal can resume even if the owner stays spectator.
        if (availability != Welfare_Ready) g_WelfareRobotAllowSpectator[client] = false;
        if (availability == Welfare_Ready) Welfare_BeginCollection(client, true);
    }
}

void WelfareRobot_QueueRetry(bool includeSpectators = false)
{
    if (g_WelfareRobotRetryTimer != null) return;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_WelfareRobotCollectionPending[client] || !Client_IsHumanInGame(client)) continue;
        int team = GetClientTeam(client);
        if (!includeSpectators && !g_WelfareRobotAllowSpectator[client] && team != 2 && team != 3) continue;
        // One shared one-shot timer, only while unresolved work exists. No
        // frame hook and no persistent polling of idle spectator-only owners.
        g_WelfareRobotRetryTimer = CreateTimer(BP_WELFARE_ROBOT_RETRY_INTERVAL,
            Timer_WelfareRobotRetry, 0, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
}

public Action Timer_WelfareRobotRetry(Handle timer)
{
    if (timer != g_WelfareRobotRetryTimer) return Plugin_Stop;
    g_WelfareRobotRetryTimer = null;
    float now = GetEngineTime();
    bool retryPool;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_WelfareRobotCollectionPending[client] || !Client_IsHumanInGame(client)) continue;
        int team = GetClientTeam(client);
        if (!g_WelfareRobotAllowSpectator[client] && team != 2 && team != 3) continue;
        if (!g_WelfareRobotPreferenceLoaded[client] && AreClientCookiesCached(client))
            WelfareRobot_LoadPreference(client, false);
        if (g_DatabaseReady && g_Database != null && IsClientAuthorizedHuman(client))
        {
            retryPool = retryPool || !g_EconomyStateLoaded || g_WelfarePoolBalance <= 0;
            if (now >= g_WelfareRobotNextLoadRetry[client])
            {
                g_WelfareRobotNextLoadRetry[client] = now + BP_WELFARE_ROBOT_LOAD_RETRY_INTERVAL;
                // Respect the store's outstanding-request tokens; never queue
                // redundant reads while the original authorization load runs.
                if (!g_ClientPurchasesLoaded[client] && g_StorePurchaseLoad[client] == null)
                    LoadClientPurchases(client);
                if (!AreBonusPointsReady(client) && g_StoreBalanceLoad[client] == null)
                    LoadClientBonusPoints(client);
            }
        }
    }
    if (retryPool && now >= g_WelfareRobotNextPoolRetry)
    {
        g_WelfareRobotNextPoolRetry = now + BP_WELFARE_ROBOT_LOAD_RETRY_INTERVAL;
        LoadEconomyState();
    }
    WelfareRobot_ResumePendingCollections();
    return Plugin_Stop;
}

void WelfareRobot_RetryFailedCollection(int client, int generation, bool ownsRequest, bool automatic)
{
    if (!automatic || !ownsRequest || generation != g_PerMapStateGeneration
        || !Client_IsHumanInGame(client)) return;
    // SQL failures are transient, not a consumed collection opportunity. Retry
    // on the shared timer, not recursively inside the database callback.
    g_WelfareRobotCollectionPending[client] = true;
    WelfareRobot_QueueRetry();
}

void WelfareRobot_AnnounceCollection(int client, int amount)
{
    g_WelfareRobotAllowSpectator[client] = false;
    char prefix[96], currency[BP_CURRENCY_LONG_MAX];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyLongLabel(currency, sizeof(currency));
    char color[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(color, sizeof(color));
    CPrintToChat(client, "%s Your {gold}Welfare Robot{default} collected %s%d %s{default} for you!", prefix, color, amount, currency);
    SaySounds_TryPlayCommand(client, BP_SOUND_COMMAND, false);
}
