void ConnectImmunityDatabase()
{
    Db_CancelTimer(g_hImmunityDbReconnectTimer);

    char configName[64];
    g_hDatabaseConfig.GetString(configName, sizeof(configName));
    TrimString(configName);
    if (!configName[0])
    {
        strcopy(configName, sizeof(configName), DB_DEFAULT_CONFIG);
    }

    if (!Db_CheckConfigOrLog("whalebalance", configName))
    {
        return;
    }

    Database.Connect(SQL_OnImmunityDatabaseConnected, configName);
}

static void ScheduleImmunityDatabaseReconnect(float delay = DB_RECONNECT_DELAY)
{
    g_bImmunityDbReady = false;
    g_bVolunteerDbReady = false;
    if (g_hImmunityDbReconnectTimer == null)
    {
        g_hImmunityDbReconnectTimer = CreateTimer(delay, Timer_ReconnectImmunityDatabase, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ReconnectImmunityDatabase(Handle timer, any data)
{
    g_hImmunityDbReconnectTimer = null;
    ConnectImmunityDatabase();
    return Plugin_Stop;
}

public void SQL_OnImmunityDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[whalebalance] Immunity DB connection failed: %s", error);
        ScheduleImmunityDatabaseReconnect();
        return;
    }

    if (g_hImmunityDb != null)
    {
        delete g_hImmunityDb;
    }

    g_hImmunityDb = db;
    g_bImmunityDbReady = false;
    g_bVolunteerDbReady = false;
    g_iPersistentVolunteerCount = 0;
    Db_CancelTimer(g_hImmunityDbReconnectTimer);

    if (!g_hImmunityDb.SetCharset("utf8mb4"))
    {
        LogError("[whalebalance] Failed to set utf8mb4 charset");
    }

    g_hImmunityDb.Query(SQL_OnImmunitySchemaReady,
        "CREATE TABLE IF NOT EXISTS autobalance_immunity ("
        ... "steamid64 VARCHAR(32) NOT NULL PRIMARY KEY, "
        ... "immune TINYINT(1) NOT NULL DEFAULT 1)");
}

public void SQL_OnImmunitySchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[whalebalance] Immunity schema creation failed: %s", error);
        if (Db_IsTransientError(error))
        {
            ScheduleImmunityDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    if (g_hPersistentImmunity != null)
    {
        g_hPersistentImmunity.Clear();
    }

    g_hImmunityDb.Query(SQL_OnPersistentImmunityLoaded,
        "SELECT steamid64 FROM autobalance_immunity WHERE immune != 0");

    g_hImmunityDb.Query(SQL_OnVolunteerSchemaReady,
        "CREATE TABLE IF NOT EXISTS autobalance_volunteers ("
        ... "steamid64 VARCHAR(32) NOT NULL PRIMARY KEY, "
        ... "volunteer TINYINT(1) NOT NULL DEFAULT 1)");
}

public void SQL_OnPersistentImmunityLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[whalebalance] Persistent immunity preload failed: %s", error);
        if (Db_IsTransientError(error))
        {
            ScheduleImmunityDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    if (g_hPersistentImmunity == null)
    {
        g_hPersistentImmunity = new StringMap();
    }
    else
    {
        g_hPersistentImmunity.Clear();
    }

    if (results != null)
    {
        char steamId[32];
        while (results.FetchRow())
        {
            results.FetchString(0, steamId, sizeof(steamId));
            TrimString(steamId);
            if (!steamId[0])
            {
                continue;
            }

            g_hPersistentImmunity.SetValue(steamId, 1, true);
        }
    }

    g_bImmunityDbReady = true;
}

public void SQL_OnVolunteerSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[whalebalance] Volunteer schema creation failed: %s", error);
        if (Db_IsTransientError(error))
        {
            ScheduleImmunityDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    if (g_hVolunteers != null)
    {
        g_hVolunteers.Clear();
    }
    g_iPersistentVolunteerCount = 0;

    g_hImmunityDb.Query(SQL_OnPersistentVolunteersLoaded,
        "SELECT steamid64 FROM autobalance_volunteers WHERE volunteer != 0");
}

public void SQL_OnPersistentVolunteersLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[whalebalance] Persistent volunteer preload failed: %s", error);
        if (Db_IsTransientError(error))
        {
            ScheduleImmunityDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    if (g_hVolunteers == null)
    {
        g_hVolunteers = new StringMap();
    }
    else
    {
        g_hVolunteers.Clear();
    }
    g_iPersistentVolunteerCount = 0;

    if (results != null)
    {
        char steamId[32];
        while (results.FetchRow())
        {
            results.FetchString(0, steamId, sizeof(steamId));
            TrimString(steamId);
            if (!steamId[0])
            {
                continue;
            }

            g_hVolunteers.SetValue(steamId, 1, true);
            g_iPersistentVolunteerCount++;
        }
    }

    g_bVolunteerDbReady = true;
}

static void AB_EscapeSql(const char[] input, char[] output, int maxlen)
{
    output[0] = '\0';
    Db_Escape(g_hImmunityDb, input, output, maxlen, "whalebalance");
}

public Action Command_Volunteer(int client, int args)
{
    if (g_hImmunityDb == null || !g_bVolunteerDbReady)
    {
        ReplyToCommand(client, "[whalebalance] Persistent volunteer database is not ready.");
        return Plugin_Handled;
    }

    int target = client;
    bool targetChangedByAdmin = false;

    if (args >= 1)
    {
        if (client > 0 && !CheckCommandAccess(client, "sm_volunteer_target", ADMFLAG_GENERIC, true))
        {
            ReplyToCommand(client, "[whalebalance] Usage: sm_volunteer");
            return Plugin_Handled;
        }

        char targetArg[MAX_TARGET_LENGTH];
        GetCmdArgString(targetArg, sizeof(targetArg));
        TrimString(targetArg);

        target = FindTarget(client, targetArg, true, false);
        if (target <= 0)
        {
            return Plugin_Handled;
        }

        targetChangedByAdmin = (target != client);
    }

    if (target <= 0)
    {
        ReplyToCommand(client, "[whalebalance] Usage: sm_volunteer [client name/substring]");
        return Plugin_Handled;
    }

    if (!IsClientInGame(target) || IsFakeClient(target))
    {
        ReplyToCommand(client, "[whalebalance] Invalid volunteer target.");
        return Plugin_Handled;
    }

    bool wasVolunteer = IsClientVolunteer(target);

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(target, steamId, sizeof(steamId), true))
    {
        ReplyToCommand(client, "[whalebalance] Failed to read SteamID64 for %N.", target);
        return Plugin_Handled;
    }

    char escapedSteam[64];
    AB_EscapeSql(steamId, escapedSteam, sizeof(escapedSteam));

    char query[256];
    if (wasVolunteer)
    {
        FormatEx(query, sizeof(query),
            "DELETE FROM autobalance_volunteers WHERE steamid64 = '%s'",
            escapedSteam);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "REPLACE INTO autobalance_volunteers (steamid64, volunteer) VALUES ('%s', 1)",
            escapedSteam);
    }

    DataPack pack = new DataPack();
    pack.WriteCell((client > 0) ? GetClientUserId(client) : 0);
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(wasVolunteer ? 1 : 0);
    pack.WriteCell(targetChangedByAdmin ? 1 : 0);
    pack.WriteString(steamId);

    g_hImmunityDb.Query(SQL_OnPersistentVolunteerToggled, query, pack);
    return Plugin_Handled;
}

public void SQL_OnPersistentVolunteerToggled(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    bool wasVolunteer = (pack.ReadCell() != 0);
    bool targetChangedByAdmin = (pack.ReadCell() != 0);
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;

    int actor = (actorUserId > 0) ? GetClientOfUserId(actorUserId) : 0;
    int target = GetClientOfUserId(targetUserId);
    bool nowVolunteer = !wasVolunteer;

    if (error[0])
    {
        if (actorUserId == 0 || (actor > 0 && IsClientInGame(actor)))
        {
            if (actor > 0 && IsClientInGame(actor))
            {
                PrintToChat(actor, "[Autobalance] Failed to toggle volunteer status.");
            }
            else
            {
                ReplyToCommand(actor, "[Autobalance] Failed to toggle volunteer status.");
            }
        }

        LogError("[whalebalance] Persistent volunteer toggle failed for %s: %s", steamId, error);
        if (Db_IsTransientError(error))
        {
            ScheduleImmunityDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    SetPersistentVolunteerCache(steamId, nowVolunteer);

    if (targetChangedByAdmin)
    {
        if (actorUserId == 0 || (actor > 0 && IsClientInGame(actor)))
        {
            if (target > 0 && IsClientInGame(target))
            {
                if (actor > 0 && IsClientInGame(actor))
                {
                    PrintToChat(actor,
                        nowVolunteer
                            ? "[Autobalance] %N is now an autobalance volunteer."
                            : "[Autobalance] %N is no longer an autobalance volunteer.",
                        target);
                }
                else
                {
                    ReplyToCommand(actor,
                        nowVolunteer
                            ? "[Autobalance] %N is now an autobalance volunteer."
                            : "[Autobalance] %N is no longer an autobalance volunteer.",
                        target);
                }
            }
            else
            {
                if (actor > 0 && IsClientInGame(actor))
                {
                    PrintToChat(actor,
                        nowVolunteer
                            ? "[Autobalance] Autobalance volunteer status applied."
                            : "[Autobalance] Autobalance volunteer status removed.");
                }
                else
                {
                    ReplyToCommand(actor,
                        nowVolunteer
                            ? "[Autobalance] Autobalance volunteer status applied."
                            : "[Autobalance] Autobalance volunteer status removed.");
                }
            }
        }

        if (target > 0 && IsClientInGame(target))
        {
            PrintToChat(target,
                nowVolunteer
                    ? "[Autobalance] You are now an autobalance volunteer; use !volunteer to opt out."
                    : "[Autobalance] You are no longer an autobalance volunteer; use !volunteer to opt in.");
        }

        if (actor > 0 && IsClientInGame(actor) && target > 0 && IsClientInGame(target))
        {
            LogBalance(
                nowVolunteer
                    ? "Volunteer status applied by %N to %N"
                    : "Volunteer status removed by %N from %N",
                actor, target);
        }
        else if (target > 0 && IsClientInGame(target))
        {
            LogBalance(
                nowVolunteer
                    ? "Volunteer status applied by console to %N"
                    : "Volunteer status removed by console from %N",
                target);
        }
        else
        {
            LogBalance(
                nowVolunteer
                    ? "Volunteer status applied for %s"
                    : "Volunteer status removed for %s",
                steamId);
        }
        return;
    }

    if (target > 0 && IsClientInGame(target))
    {
        PrintToChat(target,
            nowVolunteer
                ? "[Autobalance] You are now an autobalance volunteer; use !volunteer to opt out."
                : "[Autobalance] You are no longer an autobalance volunteer; use !volunteer to opt in.");
        LogBalance(
            nowVolunteer
                ? "%N volunteered for autobalance"
                : "%N stopped volunteering for autobalance",
            target);
    }
}

public Action Command_Immune(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[whalebalance] Usage: sm_immune <client name/substring>");
        return Plugin_Handled;
    }

    if (g_hImmunityDb == null || !g_bImmunityDbReady)
    {
        ReplyToCommand(client, "[whalebalance] Persistent immunity database is not ready.");
        return Plugin_Handled;
    }

    char targetArg[MAX_TARGET_LENGTH];
    GetCmdArgString(targetArg, sizeof(targetArg));
    TrimString(targetArg);

    int target = FindTarget(client, targetArg, true, false);
    if (target <= 0)
    {
        return Plugin_Handled;
    }

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(target, steamId, sizeof(steamId), true))
    {
        ReplyToCommand(client, "[whalebalance] Failed to read SteamID64 for %N.", target);
        return Plugin_Handled;
    }

    bool wasImmune = false;
    if (g_hPersistentImmunity != null)
    {
        int dummy = 0;
        wasImmune = g_hPersistentImmunity.GetValue(steamId, dummy);
    }

    char escapedSteam[64];
    AB_EscapeSql(steamId, escapedSteam, sizeof(escapedSteam));

    char query[256];
    if (wasImmune)
    {
        FormatEx(query, sizeof(query),
            "DELETE FROM autobalance_immunity WHERE steamid64 = '%s'",
            escapedSteam);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "REPLACE INTO autobalance_immunity (steamid64, immune) VALUES ('%s', 1)",
            escapedSteam);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(wasImmune ? 1 : 0);
    pack.WriteString(steamId);

    g_hImmunityDb.Query(SQL_OnPersistentImmunityToggled, query, pack);
    return Plugin_Handled;
}

public void SQL_OnPersistentImmunityToggled(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    bool wasImmune = (pack.ReadCell() != 0);
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;

    int actor = GetClientOfUserId(actorUserId);
    int target = GetClientOfUserId(targetUserId);

    if (error[0])
    {
        if (actor > 0 && IsClientInGame(actor))
        {
            ReplyToCommand(actor, "[whalebalance] Failed to toggle persistent immunity.");
        }

        LogError("[whalebalance] Persistent immunity toggle failed for %s: %s", steamId, error);
        return;
    }

    if (g_hPersistentImmunity != null)
    {
        if (wasImmune)
        {
            g_hPersistentImmunity.Remove(steamId);
        }
        else
        {
            g_hPersistentImmunity.SetValue(steamId, 1, true);
        }
    }

    if (target > 0 && IsClientInGame(target))
    {
        if (wasImmune)
        {
            CPrintToChatAllEx(target, "{lightgreen}[Server]{default} {teamcolor}%N{default} is no longer persistently autobalance-immune.", target);
            LogBalance("Persistent immunity removed by %N from %N", actor, target);
        }
        else
        {
            CPrintToChatAllEx(target, "{lightgreen}[Server]{default} {teamcolor}%N{default} is now persistently autobalance-immune.", target);
            LogBalance("Persistent immunity applied by %N to %N", actor, target);
        }
        return;
    }

    if (actor > 0 && IsClientInGame(actor))
    {
        ReplyToCommand(actor,
            wasImmune
                ? "[whalebalance] Persistent immunity removed."
                : "[whalebalance] Persistent immunity applied.");
    }
}

