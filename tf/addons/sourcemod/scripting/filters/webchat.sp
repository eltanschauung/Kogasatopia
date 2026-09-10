public Action Timer_PollOutbox(Handle timer, any data)
{
    if (data != g_iOutboxTimerGeneration || timer != g_hPollOutboxTimer)
    {
        return Plugin_Stop;
    }

    if (!Filters_DbAvailable() || !g_bOutboxStampReady)
    {
        Filters_LogDebug("DB/schema not ready; skipping outbox poll");
        return Plugin_Continue;
    }
    char hostStamp[96];
    Filters_GetHostStamp(hostStamp, sizeof(hostStamp));
    if (!hostStamp[0])
    {
        Filters_LogDebug("Host stamp unavailable; skipping outbox poll");
        return Plugin_Continue;
    }
    char escapedStamp[192];
    Db_Escape(g_hFiltersDb, hostStamp, escapedStamp, sizeof(escapedStamp), "filters");
    char query[1024];
    Format(query, sizeof(query), "SELECT id, iphash, source_subnet, display_name, message, host_ip, host_port, webchatonly, alert, server_ip, server_port, delivered_to, server_tag FROM whaletracker_chat_outbox o WHERE NOT EXISTS (SELECT 1 FROM whaletracker_chat_outbox_deliveries d WHERE d.outbox_id = o.id AND d.server_stamp = '%s') ORDER BY id ASC LIMIT 20", escapedStamp);
    g_hFiltersDb.Query(Filters_OutboxQueryCallback, query);
    Filters_LogDebug("Polling chat outbox for pending messages");
    return Plugin_Continue;
}

public void Filters_OutboxQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0' || results == null)
    {
        if (error[0] != '\0') LogError("[Filters] Outbox query failed: %s", error);
        return;
    }
    char localStamp[96];
    char hostNeedle[128];
    Filters_GetHostStamp(localStamp, sizeof(localStamp));
    hostNeedle[0] = '\0';
    if (localStamp[0])
    {
        Format(hostNeedle, sizeof(hostNeedle), "|%s|", localStamp);
    }
    while (results.FetchRow())
    {
        int id = results.FetchInt(0);
        char hash[64];
        results.FetchString(1, hash, sizeof(hash));
        char sourceSubnet[32];
        results.FetchString(2, sourceSubnet, sizeof(sourceSubnet));
        char display[128];
        results.FetchString(3, display, sizeof(display));
        char msg[512];
        results.FetchString(4, msg, sizeof(msg));
        char sourceIp[64];
        results.FetchString(5, sourceIp, sizeof(sourceIp));
        int sourcePort = 0;
        int fieldCount = results.FieldCount;
        if (fieldCount > 6)
        {
            sourcePort = results.FetchInt(6);
        }
        bool webchatOnly = false;
        if (fieldCount > 7)
        {
            webchatOnly = results.FetchInt(7) != 0;
        }
        char sourceTag[FILTERS_CROSS_SERVER_TAG_MAX];
        sourceTag[0] = '\0';
        if (fieldCount > 12)
        {
            results.FetchString(12, sourceTag, sizeof(sourceTag));
        }
        // alert flag and server_ip/server_port are reserved for future use
        if (fieldCount > 11 && hostNeedle[0])
        {
            char deliveredTo[256];
            results.FetchString(11, deliveredTo, sizeof(deliveredTo));
            if (StrContains(deliveredTo, hostNeedle, false) != -1)
            {
                Filters_RecordOutboxDelivery(id, localStamp);
                Filters_LogDebug("Migrated legacy delivery stamp for chat id %d", id);
                continue;
            }
        }
        Filters_ClaimOutboxForDelivery(id, hash, sourceSubnet, sourceTag, display, msg, sourceIp, sourcePort, webchatOnly, localStamp);
    }
    Filters_MaybeCleanupOutbox();
    Filters_MaybeCleanupChatHistory();
}

static void Filters_RecordOutboxDelivery(int rowId, const char[] localStamp)
{
    if (rowId <= 0 || !localStamp[0] || !Filters_DbAvailable())
    {
        return;
    }

    char escapedStamp[192];
    Db_Escape(g_hFiltersDb, localStamp, escapedStamp, sizeof(escapedStamp), "filters");
    char query[512];
    Format(query, sizeof(query),
        "INSERT IGNORE INTO whaletracker_chat_outbox_deliveries (outbox_id, server_stamp, delivered_at) VALUES (%d, '%s', %d)",
        rowId,
        escapedStamp,
        GetTime());
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

static void Filters_ClaimOutboxForDelivery(int rowId, const char[] hash, const char[] sourceSubnet, const char[] sourceTag, const char[] display, const char[] msg, const char[] sourceIp, int sourcePort, bool webchatOnly, const char[] localStamp)
{
    if (rowId <= 0 || !localStamp[0] || !Filters_DbAvailable())
    {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(rowId);
    pack.WriteString(hash);
    pack.WriteString(sourceSubnet);
    pack.WriteString(sourceTag);
    pack.WriteString(display);
    pack.WriteString(msg);
    pack.WriteString(sourceIp);
    pack.WriteCell(sourcePort);
    pack.WriteCell(webchatOnly ? 1 : 0);

    char query[512];
    char escapedStamp[192];
    Db_Escape(g_hFiltersDb, localStamp, escapedStamp, sizeof(escapedStamp), "filters");
    Format(query, sizeof(query),
        "INSERT IGNORE INTO whaletracker_chat_outbox_deliveries (outbox_id, server_stamp, delivered_at) VALUES (%d, '%s', %d)",
        rowId,
        escapedStamp,
        GetTime());
    g_hFiltersDb.Query(Filters_OutboxClaimCallback, query, pack);
}

public void Filters_OutboxClaimCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (error[0] != '\0' || results == null)
    {
        if (error[0] != '\0') LogError("[Filters] Outbox delivery claim failed: %s", error);
        delete pack;
        return;
    }

    pack.Reset();
    int id = pack.ReadCell();
    char hash[64];
    pack.ReadString(hash, sizeof(hash));
    char sourceSubnet[32];
    pack.ReadString(sourceSubnet, sizeof(sourceSubnet));
    char sourceTag[FILTERS_CROSS_SERVER_TAG_MAX];
    pack.ReadString(sourceTag, sizeof(sourceTag));
    char display[128];
    pack.ReadString(display, sizeof(display));
    char msg[512];
    pack.ReadString(msg, sizeof(msg));
    char sourceIp[64];
    pack.ReadString(sourceIp, sizeof(sourceIp));
    int sourcePort = pack.ReadCell();
    bool webchatOnly = pack.ReadCell() != 0;
    delete pack;

    if (results.AffectedRows <= 0)
    {
        Filters_LogDebug("Skipping chat id %d; this server already claimed delivery", id);
        return;
    }

    Filters_DeliverOutboxRow(id, hash, sourceSubnet, sourceTag, display, msg, sourceIp, sourcePort, webchatOnly);
}

static void Filters_DeliverOutboxRow(int id, const char[] hash, const char[] sourceSubnet, const char[] sourceTag, const char[] display, const char[] msg, const char[] sourceIp, int sourcePort, bool webchatOnly)
{
    bool isPlayerRelay = (strncmp(hash, "player:", 7) == 0);
    char label[256];
    char colorTag[32] = "{gold}";
    if (!isPlayerRelay)
    {
        if (display[0])
        {
            Filters_GetWebNameColor(display, colorTag, sizeof(colorTag));
            Format(label, sizeof(label), "%s[%s]{default}", colorTag, display);
        }
        else if (StrEqual(hash, "system"))
        {
            Format(label, sizeof(label), "{gold}[Server]{default}");
        }
        else
        {
            Filters_GetWebNameColor(hash, colorTag, sizeof(colorTag));
            Format(label, sizeof(label), "%s[Web Player # %s]{default}", colorTag, hash);
        }
    }
    bool fromLocalServer = Filters_IsLocalHostStamp(sourceIp, sourcePort);
    char sourcePrefix[FILTERS_CROSS_SERVER_TAG_MAX + 32];
    sourcePrefix[0] = '\0';
    if (!fromLocalServer && sourceTag[0])
    {
        Format(sourcePrefix, sizeof(sourcePrefix), "{gold}[%s]{default} ", sourceTag);
    }

    bool suppressChatBroadcast = webchatOnly || StrEqual(hash, "system") || fromLocalServer;
    bool isWebchatRelay = !isPlayerRelay && !StrEqual(hash, "system") && display[0];
    bool parseeEnabled = g_hParseeEnabled != null && g_hParseeEnabled.BoolValue;
    bool forceParseeRelay = parseeEnabled
        && g_hWebchatParsee != null
        && g_hWebchatParsee.BoolValue
        && isWebchatRelay;
    bool subnetParseeRelay = parseeEnabled
        && StrEqual(sourceSubnet, PARSEE_WEB_SUBNET_STAMP);
    if (subnetParseeRelay)
    {
        Filters_ArchiveSubnetParseeMessage(id);
    }
    if (forceParseeRelay || subnetParseeRelay)
    {
        if (!suppressChatBroadcast)
        {
            Filters_QueryArchivedSpeakerRelay(ArchivedSpeaker_Parsee, msg);
        }
        Filters_LogDebug("Routed webchat id %d through Parsee (forced=%d, subnet=%s)", id, forceParseeRelay ? 1 : 0, sourceSubnet);
        return;
    }

    if (isPlayerRelay)
    {
        char out[768];
        Format(out, sizeof(out), "%s%s", sourcePrefix, msg);
        if (!suppressChatBroadcast)
        {
            Filters_PrintOutboxToClients(out);
        }
        if (!fromLocalServer && !webchatOnly)
        {
            PrintToServer("%s", out);
        }
    }
    else
    {
        char out[768];
        Format(out, sizeof(out), "%s%s %s", sourcePrefix, label, msg);
        if (!suppressChatBroadcast)
        {
            Filters_PrintOutboxToClients(out);
        }
        if (!fromLocalServer && !webchatOnly)
        {
            PrintToServer("%s", out);
        }
    }
    if (fromLocalServer)
    {
        Filters_LogDebug("Suppressed relay of local chat id %d (%s:%d)", id, sourceIp, sourcePort);
    }
    else if (webchatOnly)
    {
        Filters_LogDebug("Suppressed relay of webchat-only chat id %d", id);
    }
    Filters_LogDebug("Relayed chat id %d hash %s tag %s name %s msg %s (from %s:%d)", id, hash, sourceTag, display, msg, sourceIp, sourcePort);
}

void Filters_PrintOutboxToClients(const char[] message, bool skipArchivedMuted = false)
{
    bool frontendEnabled = GetConVarInt(g_hChatFrontend) >= 1;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Filters_ShouldReceiveChat(client, 0))
        {
            continue;
        }
        if (skipArchivedMuted && g_bMuteArchivedSpeakers[client])
        {
            continue;
        }
        if (!frontendEnabled && Filters_GetAdminsDbLevel(client) != -3)
        {
            continue;
        }

        CPrintToChat(client, "%s", message);
    }
}

static void Filters_MaybeCleanupOutbox()
{
    if (!Filters_DbAvailable())
    {
        return;
    }
    int now = GetTime();
    if (g_iLastOutboxCleanup != 0 && now - g_iLastOutboxCleanup < FILTERS_OUTBOX_CLEANUP_INTERVAL)
    {
        return;
    }
    g_iLastOutboxCleanup = now;
    int cutoff = now - FILTERS_OUTBOX_RETENTION_SECONDS;
    if (cutoff <= 0)
    {
        return;
    }
    char query[128];
    Format(query, sizeof(query),
        "DELETE FROM whaletracker_chat_outbox_deliveries WHERE delivered_at < %d",
        cutoff);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);

    Format(query, sizeof(query),
        "DELETE FROM whaletracker_chat_outbox WHERE created_at < %d",
        cutoff);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

static void Filters_MaybeCleanupChatHistory()
{
    if (!g_bDbReady || g_hFiltersDb == null)
    {
        return;
    }
    int now = GetTime();
    if (g_iLastChatCleanup != 0 && now - g_iLastChatCleanup < FILTERS_OUTBOX_CLEANUP_INTERVAL)
    {
        return;
    }
    g_iLastChatCleanup = now;
    int cutoff = now - FILTERS_CHAT_RETENTION_SECONDS;
    if (cutoff <= 0)
    {
        return;
    }
    char query[128];
    Format(query, sizeof(query),
        "DELETE FROM whaletracker_chat WHERE created_at < %d",
        cutoff);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

void Filters_SanitizeDbMessage(const char[] message, char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, message);
    ReplaceString(buffer, maxlen, "{teamcolor}", "{grey}", false);
}

static void Filters_GetCrossServerTag(char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (g_hCrossServerTag == null)
    {
        return;
    }

    g_hCrossServerTag.GetString(buffer, maxlen);
    TrimString(buffer);
    if (StrEqual(buffer, "none", false))
    {
        buffer[0] = '\0';
    }
}

void Filters_GetEscapedCrossServerTag(char[] buffer, int maxlen)
{
    char tag[FILTERS_CROSS_SERVER_TAG_MAX];
    Filters_GetCrossServerTag(tag, sizeof(tag));
    Db_Escape(g_hFiltersDb, tag, buffer, maxlen, "filters");
}

static bool Filters_IsChatDatabaseImmune(int client)
{
    char steamId64[KOGASA_STEAMID_MAX];
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true)
        && StrEqual(steamId64, FILTERS_CHAT_DATABASE_IMMUNE_STEAMID64);
}

void Filters_QueueOutboxMessage(int timestamp, const char[] iphash, const char[] displayName, const char[] message, bool webchatOnly, bool alertFlag)
{
    if (!g_bDbReady || g_hFiltersDb == null)
    {
        return;
    }

    char sanitizedMsg[512];
    char escapedMsg[512];
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters");
    char escapedHash[128];
    Db_Escape(g_hFiltersDb, iphash, escapedHash, sizeof(escapedHash), "filters");
    char escapedDisplay[256];
    Db_Escape(g_hFiltersDb, displayName, escapedDisplay, sizeof(escapedDisplay), "filters");
    char escapedServerTag[FILTERS_CROSS_SERVER_TAG_MAX * 2];
    Filters_GetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag));
    int webFlag = webchatOnly ? 1 : 0;
    int alert = alertFlag ? 1 : 0;

    char query[1024];
    if (g_bOutboxStampReady)
    {
        char localIp[64];
        int localPort;
        Filters_GetLocalHostStamp(localIp, sizeof(localIp), localPort);
        char escapedIp[128];
        Db_Escape(g_hFiltersDb, localIp, escapedIp, sizeof(escapedIp), "filters");
        Format(query, sizeof(query),
            "INSERT INTO whaletracker_chat_outbox (created_at, iphash, server_tag, display_name, message, host_ip, host_port, webchatonly, alert) VALUES (%d, '%s', '%s', '%s', '%s', '%s', %d, %d, %d)",
            timestamp,
            escapedHash,
            escapedServerTag,
            escapedDisplay,
            escapedMsg,
            escapedIp,
            localPort,
            webFlag,
            alert);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO whaletracker_chat_outbox (created_at, iphash, server_tag, display_name, message, webchatonly, alert) VALUES (%d, '%s', '%s', '%s', '%s', %d, %d)",
            timestamp,
            escapedHash,
            escapedServerTag,
            escapedDisplay,
            escapedMsg,
            webFlag,
            alert);
    }

    g_hFiltersDb.Query(Filters_OutboxInsertCallback, query);
}

void Filters_RelayChatToServers(int client, const char[] message)
{
    if (Filters_IsChatDatabaseImmune(client)
        || !Filters_DbAvailable()
        || !g_bOutboxStampReady)
    {
        return;
    }

    char hash[64];
    if (client > 0 && IsClientInGame(client))
    {
        char steamId[32];
        if (Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
        {
            Format(hash, sizeof(hash), "player:%s", steamId);
        }
        else
        {
            Format(hash, sizeof(hash), "player:uid%d", GetClientUserId(client));
        }
    }
    else
    {
        strcopy(hash, sizeof(hash), "player:unknown");
    }

    char displayName[128];
    if (client > 0 && IsClientInGame(client))
    {
        GetClientName(client, displayName, sizeof(displayName));
    }
    else
    {
        strcopy(displayName, sizeof(displayName), "");
    }

    Filters_QueueOutboxMessage(GetTime(), hash, displayName, message, false, true);
}

void Filters_LogChatMessage(int client, const char[] message)
{
    if (Filters_IsChatDatabaseImmune(client))
    {
        return;
    }

    if (!Filters_DbAvailable())
    {
        Filters_LogDebug("DB not ready; skipping chat log for client %d", client);
        return;
    }


    char steamId[32];
    bool hasSteam = false;
    steamId[0] = '\0';
    if (client > 0 && IsClientInGame(client) && Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
    {
        hasSteam = true;
    }
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    char escapedName[MAX_NAME_LENGTH * 2];
    char sanitizedMsg[512];
    char escapedMsg[512];
    Db_Escape(g_hFiltersDb, name, escapedName, sizeof(escapedName), "filters");
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters");
    char escapedServerTag[FILTERS_CROSS_SERVER_TAG_MAX * 2];
    Filters_GetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag));
    char query[1024];
    if (hasSteam)
    {
        Format(query, sizeof(query),
            "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, '%s', '%s', NULL, '%s', '%s', 1)",
            GetTime(), steamId, escapedName, escapedServerTag, escapedMsg);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, NULL, '%s', NULL, '%s', '%s', 1)",
            GetTime(), escapedName, escapedServerTag, escapedMsg);
    }
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);
    Filters_LogDebug("Logged chat from %s: %s", hasSteam ? steamId : "unknown", message);
    Filters_RelayChatToServers(client, message);
}

void Filters_LogAttributedChat(const char[] steamId64, const char[] displayName, const char[] message, const char[] relayMessage)
{
    if (!Filters_DbAvailable())
    {
        return;
    }

    char escapedSteam[64];
    char escapedName[PRENAME_MAX_RENAME * 2];
    char sanitizedMsg[512];
    char escapedMsg[1024];
    Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters");
    Db_Escape(g_hFiltersDb, displayName, escapedName, sizeof(escapedName), "filters");
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters");
    char escapedServerTag[FILTERS_CROSS_SERVER_TAG_MAX * 2];
    Filters_GetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag));

    int timestamp = GetTime();
    char query[1536];
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, '%s', '%s', NULL, '%s', '%s', 1)",
        timestamp,
        escapedSteam,
        escapedName,
        escapedServerTag,
        escapedMsg);
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);

    char hash[64];
    Format(hash, sizeof(hash), "player:%s", steamId64);
    Filters_QueueOutboxMessage(timestamp, hash, displayName, relayMessage, false, true);
}

public void Filters_InsertChatCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to log chat: %s", error);
        return;
    }
    Filters_LogDebug("Chat insert succeeded");
}

void Filters_InsertSystemMessage(bool webchatOnly, bool alertFlag, const char[] format, any ...)
{
    if (!Filters_DbAvailable())
    {
        Filters_LogDebug("DB not ready; skipping system message");
        return;
    }

    char message[256];
    VFormat(message, sizeof(message), format, 4);

    int timestamp = GetTime();
    char sanitizedMsg[512];
    char escapedMsg[512];
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters");
    char escapedServerTag[FILTERS_CROSS_SERVER_TAG_MAX * 2];
    Filters_GetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag));
    char localIp[64];
    int localPort;
    Filters_GetLocalHostStamp(localIp, sizeof(localIp), localPort);
    char escapedIp[128];
    Db_Escape(g_hFiltersDb, localIp, escapedIp, sizeof(escapedIp), "filters");

    // Broadcast immediately to the local server unless webchat-only.
    if (!webchatOnly)
    {
        Filters_PrintToChatAll(message);
        PrintToServer("%s", message);
        Filters_LogDebug("Local system message broadcast: %s", message);
    }
    else
    {
        Filters_LogDebug("Webchat-only system message queued without local broadcast: %s", message);
    }

    char query[1024];
    int alert = alertFlag ? 1 : 0;
    Format(query, sizeof(query),
        "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, NULL, '[SERVER]', 'system', '%s', '%s', %d)",
        timestamp,
        escapedServerTag,
        escapedMsg,
        alert);
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);

    Filters_QueueOutboxMessage(timestamp, "system", "", message, webchatOnly, alertFlag);
    Filters_LogDebug("Queued system message: %s", message);
}

void Filters_AnnouncePlayerEvent(int client, bool connected)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    ConnectEvent event;
    GetClientName(client, event.name, sizeof(event.name));
    event.connected = connected;

    g_ConnectQueue.PushArray(event);

    if (g_ConnectQueueTimer == null)
    {
        g_ConnectQueueTimer = CreateTimer(FILTERS_CONNECT_QUEUE_DELAY, Timer_ProcessConnectQueue);
    }
}

public Action Timer_ProcessConnectQueue(Handle timer)
{
    g_ConnectQueueTimer = null;

    int count = g_ConnectQueue.Length;
    if (count > 5)
    {
        Filters_LogDebug("Dropped %d connection events due to spam/map change", count);
        g_ConnectQueue.Clear();
        return Plugin_Stop;
    }

    for (int i = 0; i < count; i++)
    {
        ConnectEvent event;
        g_ConnectQueue.GetArray(i, event);

        if (event.connected)
        {
            Filters_AnnouncePlayerJoin(event.name);
        }
        else
        {
            Filters_AnnouncePlayerLeave(event.name);
        }
    }

    g_ConnectQueue.Clear();
    return Plugin_Stop;
}

void Filters_AnnounceClientJoin(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char steam2[32], steam64[32];
    Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));

    char prename[PRENAME_MAX_RENAME];
    if (Prename_TryGetIdRule(steam64, steam2, prename, sizeof(prename)))
    {
        TrimString(prename);
        if (prename[0])
        {
            Filters_AnnouncePlayerJoin(prename);
            return;
        }
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    Filters_AnnouncePlayerJoin(name);
}

public void Filters_OutboxInsertCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to insert chat outbox entry: %s", error);
    }
}

enum struct ChatContext
{
    bool pluginEnabled;
    bool cordMode;
    bool isBlacklisted;
    bool isWhitelisted;
    bool isFilterWhitelisted;
    bool hasBlacklistedTerm;
    bool isGagged;
}

enum FilterStatusList
{
    FilterStatus_redlist = 0
};

enum FilterAdminAction
{
    FilterAdmin_FilterWhitelist = 0,
    FilterAdmin_UnFilterWhitelist,
    FilterAdmin_redlist,
    FilterAdmin_Unredlist
};

