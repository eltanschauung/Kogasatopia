// Timer ownership belongs to a client session, not a reusable player slot.
// Clear ownership before calling engine natives: respawning fires hooks synchronously.
int g_iRespawnScheduledTeam[MAXPLAYERS + 1];

void DGM_StartRespawnReminderTimer(int client)
{
    DGM_ClearRespawnReminderTimer(client);
    if (!Client_IsInGame(client) || !g_cvPopulationRespawns.BoolValue)
    {
        return;
    }

    g_hRespawnReminderTimers[client] = CreateTimer(
        DGM_RESPAWN_REMINDER_INTERVAL,
        Timer_RespawnReminder,
        GetClientSerial(client),
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RespawnReminder(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0 || g_hRespawnReminderTimers[client] != timer)
    {
        return Plugin_Stop;
    }

    if (!g_cvPopulationRespawns.BoolValue || !IsClientInGame(client)
        || g_InternalOverride || DGM_AreRespawnTimesForcedOn())
    {
        g_hRespawnReminderTimers[client] = null;
        return Plugin_Stop;
    }

    CPrintToChat(client,
        "You currently have respawn times disabled. Use {gold}sm_respawn{default} to toggle back.");
    return Plugin_Continue;
}

void DGM_ClearRespawnReminderTimer(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    Handle timer = g_hRespawnReminderTimers[client];
    g_hRespawnReminderTimers[client] = null;
    delete timer;
}

void DGM_ClearAllRespawnReminderTimers()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        DGM_ClearRespawnReminderTimer(client);
    }
}

void DGM_ResetRespawnReminderTimerHandles()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_hRespawnReminderTimers[client] = null;
    }
}

int DGM_RespawnDeadClients()
{
    int respawned = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsInGame(client) || IsPlayerAlive(client)
            || GetClientTeam(client) <= view_as<int>(TFTeam_Spectator))
        {
            continue;
        }

        DGM_ClearRespawnTimer(client);
        TF2_RespawnPlayer(client);
        respawned++;
    }
    return respawned;
}

void DGM_ClearRespawnTimer(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    Handle timer = g_hRespawnTimers[client];
    g_hRespawnTimers[client] = null;
    g_iRespawnScheduledTeam[client] = 0;
    delete timer;
}

void DGM_ClearAllRespawnTimers()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        DGM_ClearRespawnTimer(client);
    }
}

void DGM_ResetRespawnTimerHandles()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_hRespawnTimers[client] = null;
        g_iRespawnScheduledTeam[client] = 0;
    }
}

void DGM_ScheduleRespawnTimer(int client, float delay)
{
    DGM_ClearRespawnTimer(client);
    if (!Client_IsInGame(client) || GetClientTeam(client) <= view_as<int>(TFTeam_Spectator))
    {
        return;
    }

    // Also rejects NaN. ConVars are bounded, but this helper has other callers.
    if (!(delay >= 0.0))
    {
        delay = 0.0;
    }

    g_iRespawnScheduledTeam[client] = GetClientTeam(client);
    g_hRespawnTimers[client] = CreateTimer(
        delay, Timer_RespawnClient, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Client_IsInGame(client))
    {
        return;
    }
    DGM_ClearRespawnTimer(client);

    if (DGM_ShouldDisableInstantRespawn() || g_InternalOverride)
    {
        return;
    }

    float baseRespawn = g_cvRespawnTime.FloatValue;
    if (FloatCompare(baseRespawn, DGM_RESPAWN_DISABLED_TIME) == 0)
    {
        return;
    }

    float overrideTime = g_cvTimeOverride.FloatValue;
    if (overrideTime > 0.0)
    {
        DGM_ScheduleRespawnTimer(client, overrideTime);
        return;
    }

    float delay = baseRespawn;
    int team = GetClientTeam(client);
    float redTime = g_cvRedTime.FloatValue;
    float bluTime = g_cvBluTime.FloatValue;
    if (redTime != bluTime)
    {
        if (team == 2)
        {
            delay = redTime;
        }
        else if (team == 3)
        {
            delay = bluTime;
        }
    }
    DGM_ScheduleRespawnTimer(client, delay);
}

public Action Timer_RespawnClient(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (client == 0 || g_hRespawnTimers[client] != timer)
    {
        return Plugin_Stop;
    }

    int expectedTeam = g_iRespawnScheduledTeam[client];
    g_hRespawnTimers[client] = null;
    g_iRespawnScheduledTeam[client] = 0;

    // Settings and team membership can change while the timer is queued.
    if (!Client_IsInGame(client) || g_InternalOverride
        || DGM_AreRespawnTimesForcedOn() || DGM_ShouldDisableInstantRespawn())
    {
        return Plugin_Stop;
    }

    if (!IsPlayerAlive(client) && expectedTeam > 1 && GetClientTeam(client) == expectedTeam)
    {
        TF2_RespawnPlayer(client);
    }
    return Plugin_Stop;
}
