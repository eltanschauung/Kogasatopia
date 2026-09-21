#define PARSEE_AUTOMATIC_MESSAGE_MAX_LENGTH 64
#define PARSEE_LIVE_FORCE_REPLACEMENT_LENGTH 48

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

    if (Filters_IsConnectedParseeClient(client))
    {
        g_bMuteArchivedSpeakers[client] = false;
        SetClientCookie(client, g_hCookieMuteArchivedSpeakers, "0");
        CPrintToChat(client, "{gold}[Filters]{default} You can now see messages from Memoman and Parsee again!");
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

bool Filters_IsConnectedParseeClient(int client)
{
    char steamId64[KOGASA_STEAMID_MAX];
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true)
        && StrEqual(steamId64, PARSEE_STEAMID64);
}

bool Filters_HasMutedArchivedSpeakers(int client)
{
    return g_bMuteArchivedSpeakers[client] && !Filters_IsConnectedParseeClient(client);
}

static int Filters_GetUtf8CharacterCount(const char[] message)
{
    int characters = 0;
    for (int offset = 0; message[offset] != '\0'; characters++)
    {
        int bytes = GetCharBytes(message[offset]);
        offset += bytes > 0 ? bytes : 1;
    }
    return characters;
}

bool Filters_TryReplaceConnectedParseeMessage(
    int client, const char[] message, const char[] senderMessage = "",
    const char[] rawMessage = "")
{
    bool forceReplacement = Filters_GetUtf8CharacterCount(rawMessage)
        > PARSEE_LIVE_FORCE_REPLACEMENT_LENGTH;
    if (!Filters_IsConnectedParseeClient(client)
        || (!forceReplacement && !g_hParseeEnabled.BoolValue && !g_hParseeMode.BoolValue)
        || GetConVarInt(g_sEnabled) == 0
        || !Filters_DbAvailable()
        || (!forceReplacement && !g_hParseeMode.BoolValue
            && GetRandomInt(1, 100) > PARSEE_LIVE_REPLACEMENT_PERCENT))
    {
        return false;
    }

    Filters_SendChatToReceiver(client, client, message, senderMessage);
    PrintToServer("%s", message);
    Filters_LogChatMessage(client, senderMessage[0] ? senderMessage : message, true);
    Filters_QueryRandomArchivedMessage(
        ArchivedSpeaker_Parsee, GetClientUserId(client), false, true);
    return true;
}

void Filters_QueryRandomArchivedMessage(
    ArchivedSpeaker speaker, int skipUserId = 0, bool logAttributed = true,
    bool shortMessagesOnly = false)
{
    bool liveParseeReplacement = speaker == ArchivedSpeaker_Parsee
        && skipUserId != 0 && !logAttributed;
    if (speaker == ArchivedSpeaker_Parsee
        && !g_hParseeEnabled.BoolValue && !liveParseeReplacement)
    {
        return;
    }

    char table[32], steam64[32], steam2[32], fallbackName[PRENAME_MAX_RENAME];
    Filters_GetArchivedSpeakerDetails(speaker, table, sizeof(table), steam64, sizeof(steam64), steam2, sizeof(steam2), fallbackName, sizeof(fallbackName));

    char messageSelection[160];
    if (shortMessagesOnly)
    {
        FormatEx(messageSelection, sizeof(messageSelection),
            "SELECT message FROM %s WHERE CHAR_LENGTH(message) < %d ORDER BY RAND() LIMIT 1",
            table, PARSEE_AUTOMATIC_MESSAGE_MAX_LENGTH);
    }
    else if (g_iArchivedMessageCounts[speaker] > 0)
    {
        int offset = GetRandomInt(0, g_iArchivedMessageCounts[speaker] - 1);
        FormatEx(messageSelection, sizeof(messageSelection),
            "SELECT message FROM %s LIMIT 1 OFFSET %d", table, offset);
    }
    else
    {
        // The initial count is asynchronous; do not leak a live message while it loads.
        FormatEx(messageSelection, sizeof(messageSelection),
            "SELECT message FROM %s ORDER BY RAND() LIMIT 1", table);
    }
    char query[1536];
    Format(query, sizeof(query),
        "SELECT p.message, "
        ... "COALESCE((SELECT newname FROM prename_rules WHERE pattern IN ('%s', '%s') ORDER BY (pattern = '%s') DESC LIMIT 1), NULLIF(sn.last_name, ''), '%s'), "
        ... "COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
        ... "FROM (%s) p "
        ... "LEFT JOIN filters_steam_names sn ON sn.steamid64 = '%s' "
        ... "LEFT JOIN filters_namecolors nc ON nc.steamid = '%s' LIMIT 1",
        steam64,
        steam2,
        steam64,
        fallbackName,
        messageSelection,
        steam64,
        steam64);
    DataPack pack = new DataPack();
    pack.WriteCell(speaker);
    pack.WriteCell(skipUserId);
    pack.WriteCell(logAttributed);
    g_hFiltersDb.Query(Filters_RandomArchivedMessageCallback, query, pack);
}

public void Filters_RandomArchivedMessageCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    ArchivedSpeaker speaker = view_as<ArchivedSpeaker>(pack.ReadCell());
    int skipUserId = pack.ReadCell();
    bool logAttributed = pack.ReadCell();
    delete pack;
    bool liveParseeReplacement = speaker == ArchivedSpeaker_Parsee
        && skipUserId != 0 && !logAttributed;
    if ((speaker == ArchivedSpeaker_Parsee
            && !g_hParseeEnabled.BoolValue && !liveParseeReplacement)
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
    Filters_RenderArchivedSpeakerMessage(
        speaker, message, displayName, color, pattern, false, skipUserId, logAttributed);
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

static void Filters_RenderArchivedSpeakerMessage(ArchivedSpeaker speaker,
    const char[] message, char[] displayName, char[] color, char[] pattern,
    bool webRelay, int skipUserId = 0, bool logAttributed = true)
{
    bool liveParseeReplacement = speaker == ArchivedSpeaker_Parsee
        && !webRelay && skipUserId != 0 && !logAttributed;
    if (speaker == ArchivedSpeaker_Parsee
        && !g_hParseeEnabled.BoolValue && !liveParseeReplacement)
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
    char renderedMessage[512];
    strcopy(renderedMessage, sizeof(renderedMessage), message);
    if (speaker == ArchivedSpeaker_Parsee)
    {
        FilterString(renderedMessage, sizeof(renderedMessage));
    }

    char output[768];
    Format(output, sizeof(output), "%s{default} : %s", renderedName, renderedMessage);
    if (webRelay)
    {
        Filters_PrintOutboxToClients(output, true);
    }
    else if (skipUserId == 0)
    {
        Filters_PrintToChatAll(output, true);
    }
    else if (skipUserId < 0)
    {
        Filters_PrintOutboxToClients(output, true);
    }
    else
    {
        int skipClient = skipUserId > 0 ? GetClientOfUserId(skipUserId) : 0;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (client == skipClient || !Filters_ShouldReceiveChat(client, 0)
                || Filters_HasMutedArchivedSpeakers(client))
            {
                continue;
            }
            CPrintToChat(client, "%s", output);
        }
    }
    PrintToServer("%s", output);
    if (!webRelay && logAttributed)
    {
        Filters_LogAttributedChat(steam64, displayName, renderedMessage, output);
    }
}

// Poll DB outbox and atomically claim one delivery row per server.
