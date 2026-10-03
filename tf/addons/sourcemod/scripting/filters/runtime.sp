void Filters_StartTimers()
{
    if (g_hPollOutboxTimer == null)
    {
        g_iOutboxTimerGeneration++;
        g_hPollOutboxTimer = CreateTimer(FILTERS_OUTBOX_POLL_INTERVAL, Timer_PollOutbox,
            g_iOutboxTimerGeneration, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    if (g_hMuteDeafenTimer == null)
        g_hMuteDeafenTimer = CreateTimer(FILTERS_MUTE_CHECK_INTERVAL, Timer_RefreshMuteDeafenState, _, TIMER_REPEAT);
}

void Filters_StopOutboxTimer()
{
    // A NO_MAPCHANGE timer may already have been closed by the engine.
    g_iOutboxTimerGeneration++;
    g_hPollOutboxTimer = null;
    Filters_AbandonOutboxBatch();
}

static bool Filters_CanCheckMutedClients()
{
    return Filters_MuteDeafenEnabled();
}

void Filters_RefreshMuteDeafenState()
{
    bool canCheck = Filters_CanCheckMutedClients();
    bool changed = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        bool shouldDeafen = canCheck && Filters_IsRealClientInGame(client) && MuteCheck_CountMutedClients(client) > 0;
        if (g_MuteDeafened[client] != shouldDeafen)
        {
            g_MuteDeafened[client] = shouldDeafen;
            changed = true;
        }
    }
    if (changed) Filters_UpdateVoiceOverrides();
}

public Action Timer_RefreshMuteDeafenState(Handle timer)
{
    if (timer != g_hMuteDeafenTimer) return Plugin_Stop;
    Filters_RefreshMuteDeafenState();
    return Plugin_Continue;
}

void Filters_RestoreConnectedClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        // Late-loaded plugins do not receive the past post-admin forwards.
        Filters_AssignVoiceGroup(client);
        if (AreClientCookiesCached(client)) ProcessCookies(client);
        else Filters_ClearClientState(client);
        Filters_ResetExternalStats(client);
        Filters_UpdateExternalStats(client);
    }
}

public void OnConfigsExecuted()
{
    RefreshHostAddress();
    RefreshServerHostname();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "oblivion")) RequestFrame(Filters_OblivionRefreshVoice);
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false)) return;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) Filters_UpdateExternalStats(client);
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "oblivion")) RequestFrame(Filters_OblivionRefreshVoice);
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false)) return;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) Filters_ResetExternalStats(client);
}

static int g_FiltersPreviousMapPopulation;
static int g_FiltersLivePopulation;
static bool g_FiltersSamplePopulation;
static int g_FiltersMapAlertGeneration;
static bool g_FiltersMapAlertPending;
static char g_FiltersPendingMapName[128];

public void OnMapEnd()
{
    // Client teardown precedes this forward on TF2. The final live frame still
    // has the real connection count; querying here can already return zero.
    g_FiltersPreviousMapPopulation = g_FiltersLivePopulation;
    g_FiltersSamplePopulation = false;
    g_FiltersMapAlertPending = false;
    g_FiltersMapAlertGeneration++;
}

public void OnGameFrame()
{
    if (g_FiltersSamplePopulation) g_FiltersLivePopulation = GetClientCount(false);
}

public Action Filters_TryMapAlert(Handle timer, any generation)
{
    if (generation != g_FiltersMapAlertGeneration || !g_FiltersMapAlertPending) return Plugin_Stop;
    if (!Filters_DbAvailable()) return Plugin_Continue;
    if (!Filters_InsertSystemMessage(false, false,
        "{gold}[Server]{default}: Map changed to {cornflowerblue}%s", g_FiltersPendingMapName)) return Plugin_Continue;
    g_FiltersMapAlertPending = false;
    return Plugin_Stop;
}

public void OnMapStart()
{
    g_FiltersLivePopulation = GetClientCount(false);
    g_FiltersSamplePopulation = true;
    Filters_StopOutboxTimer();
    Filters_StartTimers();
    g_TidyChatSuppressTeamAlertsUntil = 0.0;
    for (int client = 1; client <= MaxClients; client++) g_TidyChatSuppressNextTeamAlert[client] = false;
    g_FiltersMapAlertGeneration++;
    g_FiltersMapAlertPending = g_FiltersPreviousMapPopulation >= 3;
    if (g_FiltersMapAlertPending)
    {
        GetCurrentMap(g_FiltersPendingMapName, sizeof(g_FiltersPendingMapName));
        // Allow map config/database startup to finish; the message is queued once.
        CreateTimer(1.0, Filters_TryMapAlert, g_FiltersMapAlertGeneration,
            TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

Database g_hFiltersDb = null;
