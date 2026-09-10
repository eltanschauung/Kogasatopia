public Action Command_ClanMenu(int client, int args)
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

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return Plugin_Handled;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1) AS clan_id, "
        ... "(SELECT rank FROM clan_members WHERE steamid64 = '%s' LIMIT 1) AS rank, "
        ... "(SELECT name FROM clans WHERE id = (SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1) LIMIT 1) AS clan_name, "
        ... "(SELECT tag FROM clans WHERE id = (SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1) LIMIT 1) AS clan_tag, "
        ... "(SELECT is_open FROM clans WHERE id = (SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1) LIMIT 1) AS is_open, "
        ... "(SELECT COUNT(1) FROM clan_invites WHERE steamid64 = '%s' AND expires_at > %d) AS invite_count",
        escapedSteam,
        escapedSteam,
        escapedSteam,
        escapedSteam,
        escapedSteam,
        escapedSteam,
        GetTime());

    g_Database.Query(SQL_OnClanMenuContext, query, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Command_ClansList(int client, int args)
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

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, c.tag, ("
        ... "SELECT COUNT(1) FROM clan_members cm WHERE cm.clan_id = c.id"
        ... ") + ("
        ... "SELECT COUNT(1) "
        ... "FROM clan_members cm_child "
        ... "INNER JOIN clan_relations cr ON cr.clan_id_a = cm_child.clan_id "
        ... "WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id"
        ... ") AS member_count, "
        ... "(SELECT COALESCE(SUM(COALESCE(pb.balance, 0)), 0) "
        ... "FROM clan_members cm "
        ... "LEFT JOIN points_store_balances pb ON pb.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = c.id "
        ... "OR cm.clan_id IN (SELECT cr.clan_id_a FROM clan_relations cr WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id)) AS cached_gems "
        ... "FROM clans c "
        ... "ORDER BY member_count DESC, c.name ASC");

    g_Database.Query(SQL_OnClansListMenu, query, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Command_ClanHelp(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[Clans] This command can only be used by players.");
        return Plugin_Handled;
    }

    CPrintToChat(client, "{green}[Clans]{default} !clan: open the clan menu.");
    CPrintToChat(client, "{green}[Clans]{default} !clans: browse existing clans.");
    CPrintToChat(client, "{green}[Clans]{default} !claninvite <player>: invite a player.");
    CPrintToChat(client, "{green}[Clans]{default} !claninfo <player|name|tag>: show clan info.");
    CPrintToChat(client, "{green}[Clans]{default} !clanmembers: show your clan members.");
    CPrintToChat(client, "{green}[Clans]{default} !clanwar: declare war or surrender.");
    CPrintToChat(client, "{green}[Clans]{default} !clankick <player>: kick a member.");
    CPrintToChat(client, "{green}[Clans]{default} !clantag: set main tag or your sub-tag.");
    return Plugin_Handled;
}

public Action Command_ClanChat(int client, int args)
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
        PrintToChat(client, "[Clans] Usage: sm_cc <message>");
        return Plugin_Handled;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return Plugin_Handled;
    }

    char message[192];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);
    TrimString(message);

    if (!message[0])
    {
        PrintToChat(client, "[Clans] Usage: sm_cc <message>");
        return Plugin_Handled;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(message);

    GetClanByPlayer(steamid64, SQL_OnClanChatContext, pack);
    return Plugin_Handled;
}

public void SQL_OnClanChatContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char message[192];
    pack.ReadString(message, sizeof(message));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan chat context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char clanDisplayTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(ClanByPlayerCol_Tag, clanTag, sizeof(clanTag));
    BuildClanDisplayTag(clanTag, clanDisplayTag, sizeof(clanDisplayTag));

    char senderName[384];
    BuildClanChatSenderName(client, senderName, sizeof(senderName));

    char output[768];
    if (clanDisplayTag[0])
    {
        FormatEx(output, sizeof(output), "%s %s: %s", clanDisplayTag, senderName, message);
    }
    else
    {
        FormatEx(output, sizeof(output), "%s: %s", senderName, message);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsConnectedClientInClan(i, clanId))
        {
            continue;
        }

        ClansCPrintToChatExWrapped(i, client, "%s", output);
    }
}

