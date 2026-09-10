static void Filters_GetArchivedSpeakerDetails(
    ArchivedSpeaker speaker,
    char[] table,
    int tableLen,
    char[] steamId64,
    int steam64Len,
    char[] steamId2,
    int steam2Len,
    char[] fallbackName,
    int nameLen)
{
    if (speaker == ArchivedSpeaker_Memoman)
    {
        strcopy(table, tableLen, "memoman_messages");
        strcopy(steamId64, steam64Len, MEMOMAN_STEAMID64);
        strcopy(steamId2, steam2Len, MEMOMAN_STEAMID2);
        strcopy(fallbackName, nameLen, MEMOMAN_FALLBACK_NAME);
        return;
    }

    strcopy(table, tableLen, "parsee_messages");
    strcopy(steamId64, steam64Len, PARSEE_STEAMID64);
    strcopy(steamId2, steam2Len, PARSEE_STEAMID2);
    strcopy(fallbackName, nameLen, PARSEE_FALLBACK_NAME);
}

static int Filters_GetArchivedSpeakerTeam(ArchivedSpeaker speaker)
{
    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    int client;
    if (Filters_FindClientBySteamId64(steam64, client))
    {
        int team = GetClientTeam(client);
        if (team == 2 || team == 3)
        {
            return team;
        }
    }

    int now = GetTime();
    if (g_iArchivedSpeakerTeam[speaker] != 2 && g_iArchivedSpeakerTeam[speaker] != 3)
    {
        g_iArchivedSpeakerTeam[speaker] = GetRandomInt(2, 3);
        g_iArchivedSpeakerTeamExpiresAt[speaker] = now + ARCHIVED_MESSAGE_TEAM_DURATION_SECONDS;
    }
    else if (now >= g_iArchivedSpeakerTeamExpiresAt[speaker])
    {
        g_iArchivedSpeakerTeam[speaker] = g_iArchivedSpeakerTeam[speaker] == 2 ? 3 : 2;
        g_iArchivedSpeakerTeamExpiresAt[speaker] = now + ARCHIVED_MESSAGE_TEAM_DURATION_SECONDS;
    }

    return g_iArchivedSpeakerTeam[speaker];
}

static void Filters_GetArchivedSpeakerTeamColor(ArchivedSpeaker speaker, char[] color, int maxlen)
{
    strcopy(color, maxlen, Filters_GetArchivedSpeakerTeam(speaker) == 2 ? "red" : "blue");
}

void Filters_RefreshArchivedMessageCount(ArchivedSpeaker speaker, int requesterUserId = 0)
{
    g_iArchivedMessageCounts[speaker] = 0;
    if (!Filters_DbAvailable())
    {
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    DataPack pack = new DataPack();
    pack.WriteCell(speaker);
    pack.WriteCell(requesterUserId);

    char query[96];
    Format(query, sizeof(query), "SELECT COUNT(*) FROM %s", table);
    g_hFiltersDb.Query(Filters_ArchivedMessageCountCallback, query, pack);
}

public void Filters_ArchivedMessageCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    ArchivedSpeaker speaker = pack.ReadCell();
    int requesterUserId = pack.ReadCell();
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to count archived messages: %s", error);
        return;
    }

    if (results != null && results.FetchRow())
    {
        g_iArchivedMessageCounts[speaker] = results.FetchInt(0);
    }

    if (requesterUserId == 0)
    {
        return;
    }

    int client = requesterUserId > 0 ? GetClientOfUserId(requesterUserId) : 0;
    if (requesterUserId > 0 && client <= 0)
    {
        return;
    }

    if (g_iArchivedMessageCounts[speaker] <= 0)
    {
        if (client > 0)
        {
            CPrintToChat(client, "{default}[Filters] No archived messages are available.");
        }
        return;
    }

    Filters_QueryRandomArchivedMessage(speaker);
}

public Action Command_RandomParseeMessage(int client, int args)
{
    if (!g_hParseeEnabled.BoolValue)
    {
        return Plugin_Handled;
    }

    return Filters_CommandRandomArchivedMessage(client, ArchivedSpeaker_Parsee);
}

public Action Command_RandomMemomanMessage(int client, int args)
{
    if (!g_hMemomanEnabled.BoolValue)
    {
        return Plugin_Handled;
    }

    return Filters_CommandRandomArchivedMessage(client, ArchivedSpeaker_Memoman);
}

public Action Command_MuteParsee(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!AreClientCookiesCached(client))
    {
        CPrintToChat(client, "{gold}[Filters]{default} Your preferences are still loading.");
        return Plugin_Handled;
    }

    g_bMuteArchivedSpeakers[client] = !g_bMuteArchivedSpeakers[client];
    SetClientCookie(
        client,
        g_hCookieMuteArchivedSpeakers,
        g_bMuteArchivedSpeakers[client] ? "1" : "0");

    if (g_bMuteArchivedSpeakers[client])
    {
        CPrintToChat(client, "{gold}[Filters]{default} You'll no longer see messages from Memoman or Parsee.");
    }
    else
    {
        CPrintToChat(client, "{gold}[Filters]{default} You can now see messages from Memoman and Parsee again!");
    }

    return Plugin_Handled;
}

void Filters_ScheduleArchivedMessageTriggers(int client, const char[] message)
{
    if (g_hMemomanEnabled.BoolValue
        && StrContains(message, "memo", false) != -1)
    {
        Filters_ScheduleArchivedMessageTrigger(client, ArchivedSpeaker_Memoman);
    }
    if (g_hParseeEnabled.BoolValue
        && (StrContains(message, "parsee", false) != -1
            || StrContains(message, "kig", false) != -1))
    {
        Filters_ScheduleArchivedMessageTrigger(client, ArchivedSpeaker_Parsee);
    }
}

static void Filters_ScheduleArchivedMessageTrigger(int client, ArchivedSpeaker speaker)
{
    DataPack pack;
    CreateDataTimer(GetRandomFloat(2.0, 5.0), Timer_ArchivedMessageTrigger, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(speaker);
}

public Action Timer_ArchivedMessageTrigger(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    ArchivedSpeaker speaker = pack.ReadCell();
    if ((speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
        || (speaker == ArchivedSpeaker_Memoman && !g_hMemomanEnabled.BoolValue))
    {
        return Plugin_Stop;
    }

    if (client > 0 && IsClientInGame(client))
    {
        Filters_CommandRandomArchivedMessage(client, speaker);
    }
    return Plugin_Stop;
}

static Action Filters_CommandRandomArchivedMessage(int client, ArchivedSpeaker speaker)
{
    int now = GetTime();
    if (client > 0 && now < g_iNextArchivedMessageTime[client][speaker])
    {
        char displayName[PRENAME_MAX_RENAME];
        strcopy(displayName, sizeof(displayName), speaker == ArchivedSpeaker_Memoman ? "Memoman" : "Parsee");
        char color[8];
        Filters_GetArchivedSpeakerTeamColor(speaker, color, sizeof(color));
        int secondsRemaining = g_iNextArchivedMessageTime[client][speaker] - now;
        CPrintToChat(client, "{gold}[Filters] {%s}%s{default} is on cooldown! (%ds)", color, displayName, secondsRemaining);
        return Plugin_Handled;
    }

    if (!Filters_DbAvailable())
    {
        if (client > 0)
        {
            CPrintToChat(client, "{default}[Filters] The message database is not ready.");
        }
        return Plugin_Handled;
    }

    if (client > 0)
    {
        int cooldown = Filters_GetArchivedMessageCooldown(client, speaker);
        g_iNextArchivedMessageTime[client][speaker] = now + cooldown;
    }

    if (g_iArchivedMessageCounts[speaker] <= 0)
    {
        Filters_RefreshArchivedMessageCount(speaker, client > 0 ? GetClientUserId(client) : -1);
        return Plugin_Handled;
    }

    Filters_QueryRandomArchivedMessage(speaker);
    return Plugin_Handled;
}

static int Filters_GetArchivedMessageCooldown(int client, ArchivedSpeaker speaker)
{
    if (speaker == ArchivedSpeaker_Parsee
        && GetFeatureStatus(FeatureType_Native, "PointsStore_HasPurchase") == FeatureStatus_Available
        && PointsStore_HasPurchase(client, PARSEE_COOLDOWN_REDUCTION_ITEM))
    {
        return PARSEE_PURCHASE_COOLDOWN_SECONDS;
    }

    return Filters_GetAdminsDbLevel(client) > 1
        ? ARCHIVED_MESSAGE_WHITELIST_COOLDOWN_SECONDS
        : ARCHIVED_MESSAGE_COOLDOWN_SECONDS;
}

void Filters_ResetArchivedMessageCooldowns(int client)
{
    for (int speaker = 0; speaker < view_as<int>(ArchivedSpeaker_Count); speaker++)
    {
        g_iNextArchivedMessageTime[client][speaker] = 0;
    }
}

static void Filters_QueryRandomArchivedMessage(ArchivedSpeaker speaker)
{
    if (speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
    {
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    int offset = GetRandomInt(0, g_iArchivedMessageCounts[speaker] - 1);
    char query[1536];
    Format(query, sizeof(query),
        "SELECT p.message, "
        ... "COALESCE((SELECT newname FROM prename_rules WHERE pattern IN ('%s', '%s') ORDER BY (pattern = '%s') DESC LIMIT 1), NULLIF(sn.last_name, ''), '%s'), "
        ... "COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
        ... "FROM (SELECT message FROM %s LIMIT 1 OFFSET %d) p "
        ... "LEFT JOIN filters_steam_names sn ON sn.steamid64 = '%s' "
        ... "LEFT JOIN filters_namecolors nc ON nc.steamid = '%s' LIMIT 1",
        steam64,
        steam2,
        steam64,
        fallbackName,
        table,
        offset,
        steam64,
        steam64);
    g_hFiltersDb.Query(Filters_RandomArchivedMessageCallback, query, speaker);
}

public void Filters_RandomArchivedMessageCallback(Database db, DBResultSet results, const char[] error, any data)
{
    ArchivedSpeaker speaker = view_as<ArchivedSpeaker>(data);
    if ((speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
        || (speaker == ArchivedSpeaker_Memoman && !g_hMemomanEnabled.BoolValue))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to load a random archived message: %s", error);
        return;
    }
    if (results == null || !results.FetchRow())
    {
        Filters_RefreshArchivedMessageCount(speaker);
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    char message[512];
    char displayName[PRENAME_MAX_RENAME];
    char color[32];
    char pattern[NAME_PATTERN_MAX];
    results.FetchString(0, message, sizeof(message));
    results.FetchString(1, displayName, sizeof(displayName));
    results.FetchString(2, color, sizeof(color));
    results.FetchString(3, pattern, sizeof(pattern));
    Filters_RenderArchivedSpeakerMessage(speaker, message, displayName, color, pattern, false);
}

void Filters_QueryArchivedSpeakerRelay(ArchivedSpeaker speaker, const char[] message)
{
    if (speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
    {
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    DataPack pack = new DataPack();
    pack.WriteCell(speaker);
    pack.WriteString(message);

    char query[1536];
    Format(query, sizeof(query),
        "SELECT COALESCE((SELECT newname FROM prename_rules WHERE pattern IN ('%s', '%s') ORDER BY (pattern = '%s') DESC LIMIT 1), NULLIF(sn.last_name, ''), '%s'), "
        ... "COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
        ... "FROM (SELECT 1) seed "
        ... "LEFT JOIN filters_steam_names sn ON sn.steamid64 = '%s' "
        ... "LEFT JOIN filters_namecolors nc ON nc.steamid = '%s' LIMIT 1",
        steam64,
        steam2,
        steam64,
        fallbackName,
        steam64,
        steam64);
    g_hFiltersDb.Query(Filters_ArchivedSpeakerRelayCallback, query, pack);
}

void Filters_ArchiveSubnetParseeMessage(int outboxId)
{
    if (!g_hParseeEnabled.BoolValue || outboxId <= 0 || !Filters_DbAvailable())
    {
        return;
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT IGNORE INTO parsee_messages (date, message, source_outbox_id) "
        ... "SELECT FROM_UNIXTIME(created_at), message, id "
        ... "FROM whaletracker_chat_outbox "
        ... "WHERE id = %d AND source_subnet = '%s' "
        ... "AND CHAR_LENGTH(TRIM(message)) >= 5",
        outboxId,
        PARSEE_WEB_SUBNET_STAMP);
    g_hFiltersDb.Query(Filters_ArchiveSubnetParseeMessageCallback, query);
}

public void Filters_ArchiveSubnetParseeMessageCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to archive subnet-matched Parsee message: %s", error);
        return;
    }

    if (results != null && results.AffectedRows > 0)
    {
        g_iArchivedMessageCounts[ArchivedSpeaker_Parsee]++;
    }
}

public void Filters_ArchivedSpeakerRelayCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    ArchivedSpeaker speaker = view_as<ArchivedSpeaker>(pack.ReadCell());
    char message[512];
    pack.ReadString(message, sizeof(message));
    delete pack;

    if (speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
    {
        return;
    }

    char table[32], steam64[32], steam2[32], displayName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), displayName, sizeof(displayName));

    char color[32];
    char pattern[NAME_PATTERN_MAX];
    color[0] = '\0';
    pattern[0] = '\0';
    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to load archived speaker identity: %s", error);
    }
    else if (results != null && results.FetchRow())
    {
        results.FetchString(0, displayName, sizeof(displayName));
        results.FetchString(1, color, sizeof(color));
        results.FetchString(2, pattern, sizeof(pattern));
    }

    Filters_RenderArchivedSpeakerMessage(speaker, message, displayName, color, pattern, true);
}

static void Filters_RenderArchivedSpeakerMessage(ArchivedSpeaker speaker, const char[] message, char[] displayName, char[] color, char[] pattern, bool webRelay)
{
    if (speaker == ArchivedSpeaker_Parsee && !g_hParseeEnabled.BoolValue)
    {
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    TrimString(displayName);
    TrimString(color);
    TrimString(pattern);
    ToLowercase(color);
    ToLowercase(pattern);

    char renderedName[256];
    int target = 0;
    if (Filters_FindClientBySteamId64(steam64, target))
    {
        GetClientName(target, displayName, PRENAME_MAX_RENAME);
        if (HasValidNamePattern(target) || g_NameColors[target][0])
        {
            BuildRenderedClientName(target, renderedName, sizeof(renderedName));
        }
        else
        {
            int team = GetClientTeam(target);
            if (team == 2)
            {
                strcopy(color, 32, "red");
            }
            else if (team == 3)
            {
                strcopy(color, 32, "blue");
            }
            else
            {
                Filters_GetArchivedSpeakerTeamColor(speaker, color, 32);
            }
            BuildRenderedStoredName(displayName, color, "", renderedName, sizeof(renderedName));
        }
    }
    else
    {
        if (!IsValidNamePattern(pattern) && !color[0])
        {
            Filters_GetArchivedSpeakerTeamColor(speaker, color, 32);
        }
        BuildRenderedStoredName(displayName, color, pattern, renderedName, sizeof(renderedName));
    }
    char output[768];
    Format(output, sizeof(output), "%s{default} : %s", renderedName, message);
    if (webRelay)
    {
        Filters_PrintOutboxToClients(output, true);
    }
    else
    {
        Filters_PrintToChatAll(output, true);
    }
    PrintToServer("%s", output);
    if (!webRelay)
    {
        Filters_LogAttributedChat(steam64, displayName, message, output);
    }
}

// Poll DB outbox and atomically claim one delivery row per server.
