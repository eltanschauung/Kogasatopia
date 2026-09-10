// Backpressure covers SELECT and its delivery claims. Merely guarding SELECT
// still allows the next poll to enqueue the same rows while INSERT IGNORE waits.
int g_FiltersOutboxBatchCounter;
int g_FiltersOutboxActiveBatch;
int g_FiltersOutboxBatchGeneration;
int g_FiltersOutboxPendingParts;
Database g_FiltersOutboxBatchConnection;
DataPack g_FiltersOutboxCleanup;

bool Filters_OutboxConnectionIsCurrent(Database db)
{
    return db != null && g_hFiltersDb != null && Filters_DbAvailable()
        && g_hFiltersDb.IsSameConnection(db);
}

void Filters_AbandonOutboxBatch()
{
    g_FiltersOutboxActiveBatch = 0;
    g_FiltersOutboxPendingParts = 0;
    delete g_FiltersOutboxBatchConnection;
    g_FiltersOutboxBatchConnection = null;
}

void Filters_FinishOutboxPart(int batch)
{
    if (batch == 0 || batch != g_FiltersOutboxActiveBatch) return;
    if (--g_FiltersOutboxPendingParts <= 0) Filters_AbandonOutboxBatch();
}

public Action Timer_PollOutbox(Handle timer, any data)
{
    if (data != g_iOutboxTimerGeneration || timer != g_hPollOutboxTimer) return Plugin_Stop;
    if (!Filters_DbAvailable() || !g_bOutboxStampReady) return Plugin_Continue;
    if (g_FiltersOutboxActiveBatch != 0)
    {
        if (g_FiltersOutboxBatchGeneration == data
            && g_FiltersOutboxBatchConnection != null
            && g_hFiltersDb.IsSameConnection(g_FiltersOutboxBatchConnection)) return Plugin_Continue;
        // The old callbacks retain their own DataPacks and may finish later;
        // their batch IDs cannot release the new batch's lock/counters.
        Filters_AbandonOutboxBatch();
    }
    char hostStamp[96], escapedStamp[193];
    Filters_GetHostStamp(hostStamp, sizeof(hostStamp));
    if (!hostStamp[0] || !Db_Escape(g_hFiltersDb, hostStamp, escapedStamp, sizeof(escapedStamp), "filters")) return Plugin_Continue;
    int batch = ++g_FiltersOutboxBatchCounter;
    if (batch == 0) batch = ++g_FiltersOutboxBatchCounter;
    g_FiltersOutboxActiveBatch = batch;
    g_FiltersOutboxBatchGeneration = data;
    g_FiltersOutboxPendingParts = 1; // SELECT sentinel; claims acquire extra parts.
    g_FiltersOutboxBatchConnection = view_as<Database>(CloneHandle(g_hFiltersDb));
    DataPack pack = new DataPack();
    pack.WriteCell(batch);
    pack.WriteCell(data);
    pack.WriteString(hostStamp);
    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT id, iphash, source_subnet, display_name, message, host_ip, host_port, webchatonly, alert, server_ip, server_port, delivered_to, server_tag "
        ... "FROM whaletracker_chat_outbox o WHERE created_at >= %d AND NOT EXISTS "
        ... "(SELECT 1 FROM whaletracker_chat_outbox_deliveries d WHERE d.outbox_id = o.id AND d.server_stamp = '%s') ORDER BY id ASC LIMIT 20",
        GetTime() - FILTERS_OUTBOX_RETENTION_SECONDS, escapedStamp);
    g_hFiltersDb.Query(Filters_OutboxQueryCallback, query, pack, DBPrio_Low);
    return Plugin_Continue;
}

public void Filters_OutboxQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int batch = pack.ReadCell(), generation = pack.ReadCell();
    char localStamp[96], currentStamp[96];
    pack.ReadString(localStamp, sizeof(localStamp));
    delete pack;
    if (batch != g_FiltersOutboxActiveBatch) return;
    Filters_GetHostStamp(currentStamp, sizeof(currentStamp));
    if (generation != g_iOutboxTimerGeneration || !Filters_OutboxConnectionIsCurrent(db)
        || !StrEqual(currentStamp, localStamp))
    {
        Filters_FinishOutboxPart(batch);
        return;
    }
    if (error[0] != '\0' || results == null)
    {
        LogError("[Filters] Outbox query failed: %s", error[0] ? error : "missing result set");
        Filters_FinishOutboxPart(batch);
        return;
    }
    char hostNeedle[128];
    FormatEx(hostNeedle, sizeof(hostNeedle), "|%s|", localStamp);
    int fieldCount = results.FieldCount;
    while (results.FetchRow())
    {
        int id = results.FetchInt(0);
        char hash[64], sourceSubnet[32], display[128], msg[512], sourceIp[64];
        char sourceTag[FILTERS_CROSS_SERVER_TAG_MAX];
        results.FetchString(1, hash, sizeof(hash));
        results.FetchString(2, sourceSubnet, sizeof(sourceSubnet));
        results.FetchString(3, display, sizeof(display));
        results.FetchString(4, msg, sizeof(msg));
        results.FetchString(5, sourceIp, sizeof(sourceIp));
        int sourcePort = fieldCount > 6 ? results.FetchInt(6) : 0;
        bool webchatOnly = fieldCount > 7 && results.FetchInt(7) != 0;
        sourceTag[0] = '\0';
        if (fieldCount > 12) results.FetchString(12, sourceTag, sizeof(sourceTag));
        if (fieldCount > 11)
        {
            char deliveredTo[256];
            results.FetchString(11, deliveredTo, sizeof(deliveredTo));
            if (StrContains(deliveredTo, hostNeedle, false) != -1)
            {
                Filters_RecordOutboxDelivery(id, localStamp);
                continue;
            }
        }
        Filters_ClaimOutboxForDelivery(id, hash, sourceSubnet, sourceTag, display, msg,
            sourceIp, sourcePort, webchatOnly, localStamp);
    }
    Filters_MaybeCleanupOutbox();
    Filters_MaybeCleanupChatHistory();
    Filters_FinishOutboxPart(batch);
}

static void Filters_RecordOutboxDelivery(int rowId, const char[] localStamp)
{
    if (rowId <= 0 || !localStamp[0] || !Filters_DbAvailable()) return;
    char escapedStamp[193], query[512];
    if (!Db_Escape(g_hFiltersDb, localStamp, escapedStamp, sizeof(escapedStamp), "filters")) return;
    FormatEx(query, sizeof(query),
        "INSERT IGNORE INTO whaletracker_chat_outbox_deliveries (outbox_id, server_stamp, delivered_at) VALUES (%d, '%s', %d)",
        rowId, escapedStamp, GetTime());
    int batch = g_FiltersOutboxActiveBatch;
    if (batch != 0) g_FiltersOutboxPendingParts++;
    g_hFiltersDb.Query(Filters_LegacyOutboxClaimCallback, query, batch, DBPrio_Low);
}

public void Filters_LegacyOutboxClaimCallback(Database db, DBResultSet results, const char[] error, any batch)
{
    if (error[0]) LogError("[Filters] Legacy delivery migration failed: %s", error);
    Filters_FinishOutboxPart(batch);
}

static void Filters_ClaimOutboxForDelivery(int rowId, const char[] hash, const char[] sourceSubnet,
    const char[] sourceTag, const char[] display, const char[] msg, const char[] sourceIp,
    int sourcePort, bool webchatOnly, const char[] localStamp)
{
    if (rowId <= 0 || !localStamp[0] || !Filters_DbAvailable()) return;
    char escapedStamp[193], query[512];
    if (!Db_Escape(g_hFiltersDb, localStamp, escapedStamp, sizeof(escapedStamp), "filters")) return;
    int batch = g_FiltersOutboxActiveBatch;
    DataPack pack = new DataPack();
    pack.WriteCell(batch);
    pack.WriteString(localStamp);
    pack.WriteCell(rowId);
    pack.WriteString(hash);
    pack.WriteString(sourceSubnet);
    pack.WriteString(sourceTag);
    pack.WriteString(display);
    pack.WriteString(msg);
    pack.WriteString(sourceIp);
    pack.WriteCell(sourcePort);
    pack.WriteCell(webchatOnly);
    FormatEx(query, sizeof(query),
        "INSERT IGNORE INTO whaletracker_chat_outbox_deliveries (outbox_id, server_stamp, delivered_at) VALUES (%d, '%s', %d)",
        rowId, escapedStamp, GetTime());
    if (batch != 0) g_FiltersOutboxPendingParts++;
    g_hFiltersDb.Query(Filters_OutboxClaimCallback, query, pack, DBPrio_Low);
}

public void Filters_OutboxClaimCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int batch = pack.ReadCell();
    char localStamp[96], currentStamp[96];
    pack.ReadString(localStamp, sizeof(localStamp));
    int id = pack.ReadCell();
    char hash[64], sourceSubnet[32], sourceTag[FILTERS_CROSS_SERVER_TAG_MAX];
    char display[128], msg[512], sourceIp[64];
    pack.ReadString(hash, sizeof(hash));
    pack.ReadString(sourceSubnet, sizeof(sourceSubnet));
    pack.ReadString(sourceTag, sizeof(sourceTag));
    pack.ReadString(display, sizeof(display));
    pack.ReadString(msg, sizeof(msg));
    pack.ReadString(sourceIp, sizeof(sourceIp));
    int sourcePort = pack.ReadCell();
    bool webchatOnly = pack.ReadCell() != 0;
    delete pack;
    if (error[0] != '\0' || results == null)
    {
        LogError("[Filters] Outbox delivery claim failed for %d: %s", id, error[0] ? error : "missing result set");
        Filters_FinishOutboxPart(batch);
        return;
    }
    Filters_GetHostStamp(currentStamp, sizeof(currentStamp));
    // A committed claim is server-scoped, not map-scoped. It may complete over a
    // map boundary, but cannot deliver under another database/server identity.
    if (results.AffectedRows > 0 && Filters_OutboxConnectionIsCurrent(db) && StrEqual(localStamp, currentStamp))
    {
        Filters_DeliverOutboxRow(id, hash, sourceSubnet, sourceTag, display, msg, sourceIp, sourcePort, webchatOnly);
    }
    Filters_FinishOutboxPart(batch);
}

static void Filters_DeliverOutboxRow(int id, const char[] hash, const char[] sourceSubnet,
    const char[] sourceTag, const char[] display, const char[] msg, const char[] sourceIp,
    int sourcePort, bool webchatOnly)
{
    bool isPlayerRelay = strncmp(hash, "player:", 7) == 0;
    char label[256], colorTag[32] = "{gold}";
    if (!isPlayerRelay)
    {
        if (display[0])
        {
            Filters_GetWebNameColor(display, colorTag, sizeof(colorTag));
            FormatEx(label, sizeof(label), "%s[%s]{default}", colorTag, display);
        }
        else if (StrEqual(hash, "system")) strcopy(label, sizeof(label), "{gold}[Server]{default}");
        else
        {
            Filters_GetWebNameColor(hash, colorTag, sizeof(colorTag));
            FormatEx(label, sizeof(label), "%s[Web Player # %s]{default}", colorTag, hash);
        }
    }
    bool fromLocalServer = Filters_IsLocalHostStamp(sourceIp, sourcePort);
    char sourcePrefix[FILTERS_CROSS_SERVER_TAG_MAX + 32];
    sourcePrefix[0] = '\0';
    if (!fromLocalServer && sourceTag[0]) FormatEx(sourcePrefix, sizeof(sourcePrefix), "{gold}[%s]{default} ", sourceTag);
    bool suppressChatBroadcast = webchatOnly || StrEqual(hash, "system") || fromLocalServer;
    bool isWebchatRelay = !isPlayerRelay && !StrEqual(hash, "system") && display[0];
    bool parseeEnabled = g_hParseeEnabled != null && g_hParseeEnabled.BoolValue;
    bool forceParseeRelay = parseeEnabled && g_hWebchatParsee != null && g_hWebchatParsee.BoolValue && isWebchatRelay;
    bool subnetParseeRelay = parseeEnabled && StrEqual(sourceSubnet, PARSEE_WEB_SUBNET_STAMP);
    if (subnetParseeRelay) Filters_ArchiveSubnetParseeMessage(id);
    if (forceParseeRelay || subnetParseeRelay)
    {
        if (!suppressChatBroadcast) Filters_QueryArchivedSpeakerRelay(ArchivedSpeaker_Parsee, msg);
        Filters_LogDebug("Routed webchat id %d through Parsee (forced=%d, subnet=%s)", id, forceParseeRelay ? 1 : 0, sourceSubnet);
        return;
    }
    char out[896];
    if (isPlayerRelay) FormatEx(out, sizeof(out), "%s%s", sourcePrefix, msg);
    else FormatEx(out, sizeof(out), "%s%s %s", sourcePrefix, label, msg);
    if (!suppressChatBroadcast) Filters_PrintOutboxToClients(out);
    if (!fromLocalServer && !webchatOnly) PrintToServer("%s", out);
    Filters_LogDebug("Relayed chat id %d hash %s tag %s name %s msg %s (from %s:%d)",
        id, hash, sourceTag, display, msg, sourceIp, sourcePort);
}

void Filters_PrintOutboxToClients(const char[] message, bool skipArchivedMuted = false)
{
    bool frontendEnabled = g_hChatFrontend != null && GetConVarInt(g_hChatFrontend) >= 1;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Filters_ShouldReceiveChat(client, 0)) continue;
        if (skipArchivedMuted && g_bMuteArchivedSpeakers[client]) continue;
        if (!frontendEnabled && Filters_GetAdminsDbLevel(client) != -3) continue;
        if (IsClientInGame(client)) CPrintToChat(client, "%s", message);
    }
}

static void Filters_MaybeCleanupOutbox()
{
    if (!Filters_DbAvailable() || g_FiltersOutboxCleanup != null) return;
    int now = GetTime();
    if (g_iLastOutboxCleanup != 0 && now >= g_iLastOutboxCleanup
        && now - g_iLastOutboxCleanup < FILTERS_OUTBOX_CLEANUP_INTERVAL) return;
    int cutoff = now - FILTERS_OUTBOX_RETENTION_SECONDS;
    if (cutoff <= 0) return;
    g_iLastOutboxCleanup = now;
    Transaction txn = new Transaction();
    char query[384];
    // Delete messages first. Removing live delivery receipts first can make an
    // already-relayed message look new to another server's concurrent poll.
    FormatEx(query, sizeof(query), "DELETE FROM whaletracker_chat_outbox WHERE created_at < %d", cutoff);
    txn.AddQuery(query);
    FormatEx(query, sizeof(query),
        "DELETE FROM whaletracker_chat_outbox_deliveries WHERE delivered_at < %d AND NOT EXISTS "
        ... "(SELECT 1 FROM whaletracker_chat_outbox o WHERE o.id = whaletracker_chat_outbox_deliveries.outbox_id)", cutoff);
    txn.AddQuery(query);
    g_FiltersOutboxCleanup = new DataPack();
    g_hFiltersDb.Execute(txn, Filters_OutboxCleanupSucceeded, Filters_OutboxCleanupFailed, g_FiltersOutboxCleanup, DBPrio_Low);
}

public void Filters_OutboxCleanupSucceeded(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    if (g_FiltersOutboxCleanup == pack) g_FiltersOutboxCleanup = null;
    delete pack;
}

public void Filters_OutboxCleanupFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    if (g_FiltersOutboxCleanup == pack) g_FiltersOutboxCleanup = null;
    delete pack;
    LogError("[Filters] Outbox cleanup failed at query %d: %s", failIndex, error);
}

static void Filters_MaybeCleanupChatHistory()
{
    if (!Filters_DbAvailable()) return;
    int now = GetTime();
    if (g_iLastChatCleanup != 0 && now >= g_iLastChatCleanup
        && now - g_iLastChatCleanup < FILTERS_OUTBOX_CLEANUP_INTERVAL) return;
    int cutoff = now - FILTERS_CHAT_RETENTION_SECONDS;
    if (cutoff <= 0) return;
    g_iLastChatCleanup = now;
    char query[128];
    FormatEx(query, sizeof(query), "DELETE FROM whaletracker_chat WHERE created_at < %d", cutoff);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query, 0, DBPrio_Low);
}

void Filters_SanitizeDbMessage(const char[] message, char[] buffer, int maxlen)
{
    if (maxlen <= 0) return;
    strcopy(buffer, maxlen, message);
    ReplaceString(buffer, maxlen, "{teamcolor}", "{grey}", false);
}

static void Filters_GetCrossServerTag(char[] buffer, int maxlen)
{
    if (maxlen <= 0) return;
    buffer[0] = '\0';
    if (g_hCrossServerTag == null) return;
    g_hCrossServerTag.GetString(buffer, maxlen);
    TrimString(buffer);
    if (StrEqual(buffer, "none", false)) buffer[0] = '\0';
}

bool Filters_TryGetEscapedCrossServerTag(char[] buffer, int maxlen)
{
    char tag[FILTERS_CROSS_SERVER_TAG_MAX];
    Filters_GetCrossServerTag(tag, sizeof(tag));
    return Db_Escape(g_hFiltersDb, tag, buffer, maxlen, "filters");
}

void Filters_GetEscapedCrossServerTag(char[] buffer, int maxlen)
{
    if (maxlen > 0 && !Filters_TryGetEscapedCrossServerTag(buffer, maxlen)) buffer[0] = '\0';
}

static bool Filters_IsChatDatabaseImmune(int client)
{
    char steamId64[KOGASA_STEAMID_MAX];
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true)
        && StrEqual(steamId64, FILTERS_CHAT_DATABASE_IMMUNE_STEAMID64);
}

void Filters_QueueOutboxMessage(int timestamp, const char[] iphash, const char[] displayName,
    const char[] message, bool webchatOnly, bool alertFlag)
{
    if (!g_bDbReady || g_hFiltersDb == null) return;
    char sanitizedMsg[512], escapedMsg[1025], escapedHash[129], escapedDisplay[257];
    char escapedServerTag[(FILTERS_CROSS_SERVER_TAG_MAX * 2) + 1];
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    if (!Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters")
        || !Db_Escape(g_hFiltersDb, iphash, escapedHash, sizeof(escapedHash), "filters")
        || !Db_Escape(g_hFiltersDb, displayName, escapedDisplay, sizeof(escapedDisplay), "filters")
        || !Filters_TryGetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag))) return;
    char query[2048];
    if (g_bOutboxStampReady)
    {
        char localIp[64], escapedIp[129];
        int localPort;
        Filters_GetLocalHostStamp(localIp, sizeof(localIp), localPort);
        if (!Db_Escape(g_hFiltersDb, localIp, escapedIp, sizeof(escapedIp), "filters")) return;
        FormatEx(query, sizeof(query),
            "INSERT INTO whaletracker_chat_outbox (created_at, iphash, server_tag, display_name, message, host_ip, host_port, webchatonly, alert) VALUES (%d, '%s', '%s', '%s', '%s', '%s', %d, %d, %d)",
            timestamp, escapedHash, escapedServerTag, escapedDisplay, escapedMsg, escapedIp, localPort, webchatOnly ? 1 : 0, alertFlag ? 1 : 0);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO whaletracker_chat_outbox (created_at, iphash, server_tag, display_name, message, webchatonly, alert) VALUES (%d, '%s', '%s', '%s', '%s', %d, %d)",
            timestamp, escapedHash, escapedServerTag, escapedDisplay, escapedMsg, webchatOnly ? 1 : 0, alertFlag ? 1 : 0);
    }
    g_hFiltersDb.Query(Filters_OutboxInsertCallback, query);
}

void Filters_RelayChatToServers(int client, const char[] message)
{
    if (Filters_IsChatDatabaseImmune(client) || !Filters_DbAvailable() || !g_bOutboxStampReady) return;
    char hash[64], displayName[128];
    displayName[0] = '\0';
    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        char steamId[32];
        if (Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true)) FormatEx(hash, sizeof(hash), "player:%s", steamId);
        else FormatEx(hash, sizeof(hash), "player:uid%d", GetClientUserId(client));
        GetClientName(client, displayName, sizeof(displayName));
    }
    else strcopy(hash, sizeof(hash), "player:unknown");
    Filters_QueueOutboxMessage(GetTime(), hash, displayName, message, false, true);
}

void Filters_LogChatMessage(int client, const char[] message)
{
    if (Filters_IsChatDatabaseImmune(client) || !Filters_DbAvailable()) return;
    char steamId[32], name[MAX_NAME_LENGTH], escapedName[(MAX_NAME_LENGTH * 2) + 1];
    char sanitizedMsg[512], escapedMsg[1025], escapedSteam[65];
    char escapedServerTag[(FILTERS_CROSS_SERVER_TAG_MAX * 2) + 1];
    bool hasSteam = false;
    steamId[0] = '\0';
    strcopy(name, sizeof(name), "Server");
    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        hasSteam = Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true);
        GetClientName(client, name, sizeof(name));
    }
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    if (!Db_Escape(g_hFiltersDb, name, escapedName, sizeof(escapedName), "filters")
        || !Db_Escape(g_hFiltersDb, steamId, escapedSteam, sizeof(escapedSteam), "filters")
        || !Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters")
        || !Filters_TryGetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag))) return;
    char query[2048];
    if (hasSteam)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, '%s', '%s', NULL, '%s', '%s', 1)",
            GetTime(), escapedSteam, escapedName, escapedServerTag, escapedMsg);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, NULL, '%s', NULL, '%s', '%s', 1)",
            GetTime(), escapedName, escapedServerTag, escapedMsg);
    }
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);
    Filters_RelayChatToServers(client, message);
}

void Filters_LogAttributedChat(const char[] steamId64, const char[] displayName, const char[] message, const char[] relayMessage)
{
    if (!Filters_DbAvailable()) return;
    char escapedSteam[65], escapedName[(PRENAME_MAX_RENAME * 2) + 1];
    char sanitizedMsg[512], escapedMsg[1025];
    char escapedServerTag[(FILTERS_CROSS_SERVER_TAG_MAX * 2) + 1];
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    if (!Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters")
        || !Db_Escape(g_hFiltersDb, displayName, escapedName, sizeof(escapedName), "filters")
        || !Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters")
        || !Filters_TryGetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag))) return;
    int timestamp = GetTime();
    char query[2048];
    FormatEx(query, sizeof(query),
        "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, '%s', '%s', NULL, '%s', '%s', 1)",
        timestamp, escapedSteam, escapedName, escapedServerTag, escapedMsg);
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);
    char hash[64];
    FormatEx(hash, sizeof(hash), "player:%s", steamId64);
    Filters_QueueOutboxMessage(timestamp, hash, displayName, relayMessage, false, true);
}

public void Filters_InsertChatCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0]) LogError("[Filters] Failed to log chat: %s", error);
    else Filters_LogDebug("Chat insert succeeded");
}

void Filters_InsertSystemMessage(bool webchatOnly, bool alertFlag, const char[] format, any ...)
{
    if (!Filters_DbAvailable()) return;
    char message[256], sanitizedMsg[512], escapedMsg[1025];
    char escapedServerTag[(FILTERS_CROSS_SERVER_TAG_MAX * 2) + 1];
    VFormat(message, sizeof(message), format, 4);
    Filters_SanitizeDbMessage(message, sanitizedMsg, sizeof(sanitizedMsg));
    if (!Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters")
        || !Filters_TryGetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag))) return;
    int timestamp = GetTime();
    char query[1792];
    FormatEx(query, sizeof(query),
        "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, NULL, '[SERVER]', 'system', '%s', '%s', %d)",
        timestamp, escapedServerTag, escapedMsg, alertFlag ? 1 : 0);
    // Capture/queue persistence before broadcasting through re-entrant chat hooks.
    g_hFiltersDb.Query(Filters_InsertChatCallback, query);
    Filters_QueueOutboxMessage(timestamp, "system", "", message, webchatOnly, alertFlag);
    if (!webchatOnly)
    {
        Filters_PrintToChatAll(message);
        PrintToServer("%s", message);
    }
}

void Filters_ResetConnectQueue()
{
    // A map-scoped timer can already have been closed at a map boundary.
    // Retire by ownership; an older live timer will stop on its next callback.
    g_ConnectQueueTimer = null;
    if (g_ConnectQueue != null) g_ConnectQueue.Clear();
}

void Filters_AnnouncePlayerEvent(int client, bool connected)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)
        || g_ConnectQueue == null) return;
    ConnectEvent event;
    GetClientName(client, event.name, sizeof(event.name));
    event.connected = connected;
    g_ConnectQueue.PushArray(event);
    if (g_ConnectQueueTimer == null)
        g_ConnectQueueTimer = CreateTimer(FILTERS_CONNECT_QUEUE_DELAY, Timer_ProcessConnectQueue,
            g_iOutboxTimerGeneration, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ProcessConnectQueue(Handle timer, any generation)
{
    if (timer != g_ConnectQueueTimer) return Plugin_Stop;
    g_ConnectQueueTimer = null;
    if (g_ConnectQueue == null) return Plugin_Stop;
    ArrayList pending = g_ConnectQueue;
    g_ConnectQueue = new ArrayList(sizeof(ConnectEvent));
    int count = pending.Length;
    if (generation != g_iOutboxTimerGeneration || count > 5)
    {
        Filters_LogDebug("Dropped %d connection events due to spam/map change", count);
        delete pending;
        return Plugin_Stop;
    }
    for (int i = 0; i < count && generation == g_iOutboxTimerGeneration; i++)
    {
        ConnectEvent event;
        pending.GetArray(i, event);
        if (event.connected) Filters_AnnouncePlayerJoin(event.name);
        else Filters_AnnouncePlayerLeave(event.name);
    }
    // New events may have arrived synchronously during a broadcast. They live
    // in the new queue, not the snapshot being drained here.
    delete pending;
    return Plugin_Stop;
}

void Filters_AnnounceClientJoin(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) return;
    char steam2[32], steam64[32], prename[PRENAME_MAX_RENAME];
    Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));
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
    if (error[0]) LogError("[Filters] Failed to insert chat outbox entry: %s", error);
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
