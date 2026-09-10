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
    Filters_ResetConnectQueue();
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
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false)) return;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) Filters_UpdateExternalStats(client);
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false)) return;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) Filters_ResetExternalStats(client);
}

public void OnMapStart()
{
    Filters_StopOutboxTimer();
    Filters_StartTimers();
    g_TidyChatSuppressTeamAlertsUntil = 0.0;
    for (int client = 1; client <= MaxClients; client++) g_TidyChatSuppressNextTeamAlert[client] = false;
    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));
    Filters_InsertSystemMessage(false, false, "{gold}[Server]{default}: Map changed to {cornflowerblue}%s", mapName);
}

Database g_hFiltersDb = null;
