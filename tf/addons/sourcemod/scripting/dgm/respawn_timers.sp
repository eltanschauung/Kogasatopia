void DGM_StartRespawnReminderTimer(int client)
{
    DGM_ClearRespawnReminderTimer(client);
    if (!g_cvPopulationRespawns.BoolValue)
    {
        return;
    }

    g_hRespawnReminderTimers[client] = CreateTimer(
        DGM_RESPAWN_REMINDER_INTERVAL,
        Timer_RespawnReminder,
        GetClientUserId(client),
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RespawnReminder(Handle timer, int userId)
{
    int owner = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_hRespawnReminderTimers[client] == timer)
        {
            owner = client;
            break;
        }
    }

    int client = GetClientOfUserId(userId);
    if (!g_cvPopulationRespawns.BoolValue
        || owner == 0 || client != owner || !IsClientInGame(client)
        || g_InternalOverride || DGM_AreRespawnTimesForcedOn())
    {
        if (owner > 0)
        {
            g_hRespawnReminderTimers[owner] = null;
        }
        return Plugin_Stop;
    }

    CPrintToChat(client,
        "You currently have respawn times disabled. Use {gold}sm_respawn{default} to toggle back.");
    return Plugin_Continue;
}

void DGM_ClearRespawnReminderTimer(int client)
{
    if (client <= 0 || client > MaxClients || g_hRespawnReminderTimers[client] == null)
    {
        return;
    }

    delete g_hRespawnReminderTimers[client];
    g_hRespawnReminderTimers[client] = null;
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

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Client_IsInGame(i) || IsPlayerAlive(i) || GetClientTeam(i) <= view_as<int>(TFTeam_Spectator))
        {
            continue;
        }

        DGM_ClearRespawnTimer(i);
        TF2_RespawnPlayer(i);
        respawned++;
    }

    return respawned;
}

void DGM_ClearRespawnTimer(int client)
{
    if (client <= 0 || client > MaxClients || g_hRespawnTimers[client] == null)
    {
        return;
    }

    delete g_hRespawnTimers[client];
    g_hRespawnTimers[client] = null;
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
    }
}

void DGM_ScheduleRespawnTimer(int client, float delay)
{
    DGM_ClearRespawnTimer(client);

    int userId = GetClientUserId(client);
    if (userId <= 0)
    {
        return;
    }

    g_hRespawnTimers[client] = CreateTimer(
        delay, Timer_RespawnClient, userId, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
        int client = GetClientOfUserId(event.GetInt("userid"));
        if (!Client_IsInGame(client)) return;
        DGM_ClearRespawnTimer(client);

        if (DGM_ShouldDisableInstantRespawn())
        {
            return;
        }

        if (g_InternalOverride)
        {
            return;
        }

        float baseRespawn = GetConVarFloat(g_cvRespawnTime);
        if (FloatCompare(baseRespawn, DGM_RESPAWN_DISABLED_TIME) == 0)
        {
            return;
        }

        float override = GetConVarFloat(g_cvTimeOverride);
        if (override > 0)
        {
            DGM_ScheduleRespawnTimer(client, override);
            return;
        }

        float time = baseRespawn;
        int team = GetClientTeam(client);
        float redTime = GetConVarFloat(g_cvRedTime);
        float bluTime = GetConVarFloat(g_cvBluTime);
        if (redTime != bluTime)
        {
        if (team == 2) time = redTime;
        else if (team == 3) time = bluTime;
        }
        DGM_ScheduleRespawnTimer(client, time);
        return;
}

public Action Timer_RespawnClient(Handle timer, int userId)
{
    int client = GetClientOfUserId(userId);
    if (client <= 0 || !Client_IsInGame(client) || g_hRespawnTimers[client] != timer)
    {
        return Plugin_Stop;
    }

    g_hRespawnTimers[client] = null;

    if (DGM_ShouldDisableInstantRespawn())
    {
        return Plugin_Stop;
    }

    if (Client_IsInGame(client) && !IsPlayerAlive(client) && GetClientTeam(client) > 1) {
        TF2_RespawnPlayer(client);
    }
    return Plugin_Stop;
}

