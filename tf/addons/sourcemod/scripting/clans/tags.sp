public Action Command_ClanTag(int client, int args)
{
    if (client <= 0)
    {
        ReplyToCommand(client, "[Clans] This command can only be used by players.");
        return Plugin_Handled;
    }

    if (!EnsureDatabaseReady(client))
    {
        return Plugin_Handled;
    }

    if (args < 1)
    {
        StartClanTagPrompt(client);
        return Plugin_Handled;
    }

    char rawTag[CLAN_TAG_MAXLEN + 1];
    GetCmdArgString(rawTag, sizeof(rawTag));
    StartSetMainClanTagFromInput(client, rawTag);
    return Plugin_Handled;
}

public void SQL_OnClanTagContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char rawTag[CLAN_TAG_MAXLEN + 1];
    pack.ReadString(rawTag, sizeof(rawTag));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Tag context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    ClanRank rank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));
    if (rank < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only the clan owner can set or change the main clan tag.");
        return;
    }

    int allowed = GetAllowedMainClanTagLength(client);
    if (strlen(rawTag) > allowed)
    {
        PrintToChat(client, "[Clans] Tag is too long. Max length: %d.", allowed);
        return;
    }

    if (!IsSafeClanTagText(rawTag))
    {
        PrintToChat(client, "[Clans] Tags may not contain control characters, pipes, or square brackets.");
        return;
    }

    char formattedTag[CLAN_TAG_STORE_MAXLEN];
    FormatStoredClanTag(rawTag, formattedTag, sizeof(formattedTag));

    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    char escapedTag[SQL_CLAN_TAG_MAXLEN];
    EscapeSql(formattedTag, escapedTag, sizeof(escapedTag));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT COUNT(1) FROM clans WHERE tag = '%s' AND id != %d",
        escapedTag,
        clanId);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(clanId);
    next.WriteString(formattedTag);

    g_Database.Query(SQL_OnClanTagUniqueCheck, query, next);
}

public void SQL_OnClanTagUniqueCheck(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char formattedTag[CLAN_TAG_STORE_MAXLEN];
    pack.ReadString(formattedTag, sizeof(formattedTag));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Tag uniqueness check failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate the clan tag.");
        return;
    }

    if (results != null && results.FetchRow() && results.FetchInt(0) > 0)
    {
        PrintToChat(client, "[Clans] That clan tag is already taken.");
        return;
    }

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(clanId);
    next.WriteString(formattedTag);

    SetClanTag(clanId, formattedTag, SQL_OnClanTagSet, next);
}

public void SQL_OnClanTagSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char formattedTag[CLAN_TAG_MAXLEN + 1];
    pack.ReadString(formattedTag, sizeof(formattedTag));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Set tag failed: %s", error);
        PrintToChat(client, "[Clans] Failed to set the clan tag.");
        return;
    }

    RefreshConnectedClanTagsForClan(clanId);
    PrintToChat(client, "[Clans] Clan tag updated to %s", formattedTag);
}

public void SQL_OnClanSubTagContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char rawTag[CLAN_SUB_TAG_MAXLEN + 1];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(rawTag, sizeof(rawTag));
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Sub-tag context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    char currentClanTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(ClanByPlayerCol_Tag, currentClanTag, sizeof(currentClanTag));
    TrimString(currentClanTag);

    if (!currentClanTag[0])
    {
        PrintToChat(client, "[Clans] Your clan must have a main clan tag before members can use sub-tags.");
        return;
    }

    int allowed = GetAllowedSubClanTagLength(client);
    if (strlen(rawTag) > allowed)
    {
        PrintToChat(client, "[Clans] Sub-tag is too long. Max length: %d.", allowed);
        return;
    }

    if (!IsSafeClanTagText(rawTag))
    {
        PrintToChat(client, "[Clans] Tags may not contain control characters, pipes, or square brackets.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedTag[SQL_CLAN_SUB_TAG_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(rawTag, escapedTag, sizeof(escapedTag));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT COUNT(1) FROM clan_sub_tags WHERE tag = '%s' AND steamid64 != '%s'",
        escapedTag,
        escapedSteam);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(clanId);
    next.WriteString(rawTag);
    next.WriteString(steamid64);

    g_Database.Query(SQL_OnClanSubTagUniqueCheck, query, next);
}

public void SQL_OnClanSubTagUniqueCheck(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char rawTag[CLAN_SUB_TAG_MAXLEN + 1];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(rawTag, sizeof(rawTag));
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Sub-tag uniqueness check failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate your clan sub-tag.");
        return;
    }

    if (results != null && results.FetchRow() && results.FetchInt(0) > 0)
    {
        PrintToChat(client, "[Clans] That clan sub-tag is already taken.");
        return;
    }

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(clanId);
    next.WriteString(rawTag);

    SetClanSubTag(clanId, steamid64, rawTag, SQL_OnClanSubTagSet, next);
}

public void SQL_OnClanSubTagSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char rawTag[CLAN_SUB_TAG_MAXLEN + 1];
    pack.ReadString(rawTag, sizeof(rawTag));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Set sub-tag failed: %s", error);
        PrintToChat(client, "[Clans] Failed to set your clan sub-tag.");
        return;
    }

    RefreshConnectedClanTagsForClan(clanId);
    PrintToChat(client, "[Clans] Clan sub-tag updated to '%s'.", rawTag);
}

