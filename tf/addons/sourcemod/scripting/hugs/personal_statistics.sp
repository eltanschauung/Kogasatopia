// Lifetime totals use the existing, backfilled account counters. Counterpart
// counts are persisted separately: the legacy last-five names cannot establish
// an all-time ranking and must not be converted into invented event counts.
#define HUGS_RELATIONSHIP_TABLE "hugs_relationships"
bool g_HugsRelationshipsReady;

void Hugs_RecordRelationship(int sender, int recipient, int kind, int given, int received)
{
    char senderId[32], recipientId[32];
    if (!Kogasa_GetClientSteamId64(sender, senderId, sizeof(senderId))
        || !Kogasa_GetClientSteamId64(recipient, recipientId, sizeof(recipientId))) return;
    Hugs_RecordRelationshipSteam(senderId, recipientId, kind, given, received);
}

void Hugs_RecordRelationshipSteam(const char[] senderId, const char[] recipientId,
    int kind, int given, int received, const char[] senderFallback = "")
{
    if (!IsDatabaseReady() || !g_HugsRelationshipsReady || (given <= 0 && received <= 0)
        || !Kogasa_IsSteamId64(senderId) || !Kogasa_IsSteamId64(recipientId)) return;
    int sender = Kogasa_FindClientBySteamId64(senderId);
    int recipient = Kogasa_FindClientBySteamId64(recipientId);
    char senderName[MAX_NAME_LENGTH], recipientName[MAX_NAME_LENGTH];
    strcopy(senderName, sizeof(senderName), senderFallback);
    if (sender > 0) GetClientName(sender, senderName, sizeof(senderName));
    if (recipient > 0) GetClientName(recipient, recipientName, sizeof(recipientName));
    char escapedSender[MAX_NAME_LENGTH * 2 + 1], escapedRecipient[MAX_NAME_LENGTH * 2 + 1];
    if (!Db_Escape(g_hDatabase, senderName, escapedSender, sizeof(escapedSender), "Hugs")
        || !Db_Escape(g_hDatabase, recipientName, escapedRecipient, sizeof(escapedRecipient), "Hugs")) return;
    char query[1200];
    FormatEx(query, sizeof(query),
        "INSERT INTO %s (sender, recipient, kind, given, received, sender_name, recipient_name) "
        ... "VALUES ('%s','%s',%d,%d,%d,'%s','%s') ON DUPLICATE KEY UPDATE "
        ... "given=given+VALUES(given), received=received+VALUES(received), "
        ... "sender_name=IF(VALUES(sender_name)='',sender_name,VALUES(sender_name)), "
        ... "recipient_name=IF(VALUES(recipient_name)='',recipient_name,VALUES(recipient_name))",
        HUGS_RELATIONSHIP_TABLE, senderId, recipientId, kind, given, received, escapedSender, escapedRecipient);
    g_hDatabase.Query(Hugs_OnRelationshipSaved, query);
}

public void Hugs_OnRelationshipSaved(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0]) LogError("[Hugs] Could not save counterpart statistics: %s", error);
}

public void Hugs_OnRelationshipSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    g_HugsRelationshipsReady = !error[0];
    SQL_OnSchemaOpComplete(db, results, error, data);
}

public Action Command_MyInteractionStats(int client, int args)
{
    if (!IsHumanClient(client) || !EnsureStatsReady(client, true)) return Plugin_Handled;
    if (!g_HugsRelationshipsReady)
    {
        CPrintToChat(client, "{gold}[Hugs]{default} Counterpart statistics are not ready yet.");
        return Plugin_Handled;
    }
    char command[32], steamId[32];
    GetCmdArg(0, command, sizeof(command));
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId))) return Plugin_Handled;
    int kind = StrEqual(command, "sm_myrapes", false) ? 2 : (StrEqual(command, "sm_myfeeds", false) ? 1 : 0);
    int given = kind == 2 ? g_iRapesGiven[client] : (kind == 1 ? g_iFeedsGiven[client] : g_iHugsGiven[client]);
    int received = kind == 2 ? g_iRapesReceived[client] : (kind == 1 ? g_iFeedsReceived[client] : g_iHugsReceived[client]);
    char label[16];
    strcopy(label, sizeof(label), kind == 2 ? "Rapes" : (kind == 1 ? "Feeds" : "Hugs"));
    CPrintToChat(client, "{gold}[%s]{default} Received: {cyan}%d{default}.", label, received);
    CPrintToChat(client, "{gold}[%s]{default} Given: {cyan}%d{default}.", label, given);
    // Return counterpart aggregates only, never duplicate or rescan raw events.
    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT 0, sender, MAX(sender_name), SUM(received) AS amount FROM %s "
        ... "WHERE recipient='%s' AND kind=%d GROUP BY sender HAVING amount>0 "
        ... "UNION ALL SELECT 1, recipient, MAX(recipient_name), SUM(given) AS amount FROM %s "
        ... "WHERE sender='%s' AND kind=%d GROUP BY recipient HAVING amount>0 ORDER BY 1, amount DESC, 2",
        HUGS_RELATIONSHIP_TABLE, steamId, kind, HUGS_RELATIONSHIP_TABLE, steamId, kind);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(label);
    g_hDatabase.Query(Hugs_OnPersonalStatsLoaded, query, pack);
    return Plugin_Handled;
}

public void Hugs_OnPersonalStatsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char label[16];
    pack.ReadString(label, sizeof(label));
    delete pack;
    if (!IsHumanClient(client)) return;
    if (error[0])
    {
        LogError("[Hugs] Could not load counterpart statistics: %s", error);
        CPrintToChat(client, "{gold}[%s]{default} Counterpart statistics are temporarily unavailable.", label);
        return;
    }
    int printed[2];
    bool dividerPrinted;
    while (results != null && results.FetchRow())
    {
        int direction = results.FetchInt(0);
        if (direction < 0 || direction >= sizeof(printed) || printed[direction] >= 3) continue;
        if (direction == 1 && !dividerPrinted)
        {
            if (!printed[0])
                CPrintToChat(client, "{gold}[%s]{default} Most received from: {grey}No recorded history yet{default}.", label);
            CPrintToChat(client, "{gold} ----- ----- -----");
            dividerPrinted = true;
        }
        char steamId[32], name[MAX_NAME_LENGTH], display[256];
        results.FetchString(1, steamId, sizeof(steamId));
        if (PublicActivity_IsExcludedSteam(steamId)) continue;
        int other = Kogasa_FindClientBySteamId64(steamId);
        if (other > 0 && Oblivion_ShouldHide(client, other)) continue;
        results.FetchString(2, name, sizeof(name));
        if (!name[0]) strcopy(name, sizeof(name), "Unknown player");
        BuildMailedHugsChatName(other, steamId, name, display, sizeof(display));
        char teamColor[16] = "{gold}";
        if (other > 0)
        {
            if (GetClientTeam(other) == 2) strcopy(teamColor, sizeof(teamColor), "{red}");
            else if (GetClientTeam(other) == 3) strcopy(teamColor, sizeof(teamColor), "{blue}");
        }
        ReplaceString(display, sizeof(display), "{teamcolor}", teamColor, false);
        printed[direction]++;
        CPrintToChat(client, "{gold}[%s]{default} %s #%d: %s{default} ({cyan}%d{default}, recorded history).",
            label, direction == 0 ? "Most received from" : "Most given to", printed[direction], display, results.FetchInt(3));
    }
    if (!dividerPrinted)
    {
        if (!printed[0])
            CPrintToChat(client, "{gold}[%s]{default} Most received from: {grey}No recorded history yet{default}.", label);
        CPrintToChat(client, "{gold} ----- ----- -----");
    }
    if (!printed[1])
        CPrintToChat(client, "{gold}[%s]{default} Most given to: {grey}No recorded history yet{default}.", label);
}
