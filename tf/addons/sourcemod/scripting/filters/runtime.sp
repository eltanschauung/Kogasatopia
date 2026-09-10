void Filters_StartTimers()
{
    if (g_hPollOutboxTimer == null)
    {
        g_iOutboxTimerGeneration++;
        g_hPollOutboxTimer = CreateTimer(FILTERS_OUTBOX_POLL_INTERVAL, Timer_PollOutbox, g_iOutboxTimerGeneration, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    if (g_hMuteDeafenTimer == null)
    {
        g_hMuteDeafenTimer = CreateTimer(FILTERS_MUTE_CHECK_INTERVAL, Timer_RefreshMuteDeafenState, _, TIMER_REPEAT);
    }
}

void Filters_StopOutboxTimer()
{
    // The timer handle can already be closed by SourceMod lifecycle events. Retire it by generation instead.
    g_iOutboxTimerGeneration++;
    g_hPollOutboxTimer = null;
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
        bool shouldDeafen = canCheck
            && Filters_IsRealClientInGame(client)
            && MuteCheck_CountMutedClients(client) > 0;

        if (g_MuteDeafened[client] != shouldDeafen)
        {
            g_MuteDeafened[client] = shouldDeafen;
            changed = true;
        }
    }

    if (changed)
    {
        Filters_UpdateVoiceOverrides();
    }
}

public Action Timer_RefreshMuteDeafenState(Handle timer)
{
    Filters_RefreshMuteDeafenState();
    return Plugin_Continue;
}

void Filters_RestoreConnectedClients()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
        {
            continue;
        }

        if (AreClientCookiesCached(i))
        {
            ProcessCookies(i);
        }
        else
        {
            Filters_ClearClientState(i);
        }

        Filters_ResetExternalStats(i);
        Filters_UpdateExternalStats(i);
    }
}

public void OnConfigsExecuted()
{
    RefreshHostAddress();
    RefreshServerHostname();
}

public void OnLibraryAdded(const char[] name)
{
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false))
    {
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            Filters_UpdateExternalStats(i);
        }
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "hugs", false) && !StrEqual(name, "whaletracker", false))
    {
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            Filters_ResetExternalStats(i);
        }
    }
}

public void OnMapStart()
{
    // On a first-load map start, an OnPluginStart-created timer may still be alive.
    // Stop it before recreating the poller so one server cannot relay each row twice.
    Filters_StopOutboxTimer();
    Filters_StartTimers();
    g_TidyChatSuppressTeamAlertsUntil = 0.0;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_TidyChatSuppressNextTeamAlert[client] = false;
    }

    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));
    Filters_InsertSystemMessage(false, false, "{gold}[Server]{default}: Map changed to {cornflowerblue}%s", mapName);
}

// Database for chat log
Database g_hFiltersDb = null;
