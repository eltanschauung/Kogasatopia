public Action Command_ClanOpen(int client, int args)
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

    int requestedState = -1;
    if (args >= 1)
    {
        char arg[8];
        GetCmdArg(1, arg, sizeof(arg));
        requestedState = (StringToInt(arg) != 0) ? 1 : 0;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return Plugin_Handled;
    }

    GetClanByPlayer(steamid64, SQL_OnClanOpenContext, requestedState == -1 ? (GetClientUserId(client) * 10) + 9 : (GetClientUserId(client) * 10) + requestedState);
    return Plugin_Handled;
}

public void SQL_OnClanOpenContext(Database db, DBResultSet results, const char[] error, any data)
{
    int userId = data / 10;
    int encoded = data % 10;
    int requestedState = (encoded == 9) ? -1 : encoded;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan open context failed: %s", error);
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
        PrintToChat(client, "[Clans] Only the clan owner can change join settings.");
        return;
    }

    bool newOpen = (requestedState == -1) ? (results.FetchInt(ClanByPlayerCol_IsOpen) == 0) : (requestedState != 0);
    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(newOpen ? 1 : 0);

    SetClanOpen(clanId, newOpen, SQL_OnClanOpenSet, pack);
}

public void SQL_OnClanOpenSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    bool isOpen = (pack.ReadCell() != 0);
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Set clan open failed: %s", error);
        PrintToChat(client, "[Clans] Failed to update open-clan settings.");
        return;
    }

    PrintToChat(client, "[Clans] Clan join setting updated: %s.", isOpen ? "open" : "closed");
}

public Action Command_ClanJoin(int client, int args)
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

    IsPlayerInClan(steamid64, SQL_OnClanJoinMembershipCheck, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanJoinMembershipCheck(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Join membership check failed: %s", error);
        PrintToChat(client, "[Clans] Failed to check your clan state.");
        return;
    }

    if (results != null && results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are already in a clan.");
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query), "SELECT id, name, tag FROM clans WHERE is_open = 1 ORDER BY name ASC");
    g_Database.Query(SQL_OnClanJoinOpenList, query, GetClientUserId(client));
}

public void SQL_OnClanJoinOpenList(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Join open list failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load open clans.");
        return;
    }

    Menu menu = new Menu(MenuHandler_JoinOpenClan);
    menu.SetTitle("Join Open Clan");

    if (results == null || results.RowCount <= 0)
    {
        menu.AddItem("none", "No open clans available", ITEMDRAW_DISABLED);
        menu.Display(client, CLAN_MENU_TIME);
        return;
    }

    char info[16];
    char name[CLAN_NAME_MAXLEN + 1];
    while (results.FetchRow())
    {
        int clanId = results.FetchInt(0);
        results.FetchString(1, name, sizeof(name));
        IntToString(clanId, info, sizeof(info));
        menu.AddItem(info, name);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_JoinOpenClan(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        int clanId = StringToInt(info);
        if (clanId > 0)
        {
            StartJoinOpenClan(param1, clanId);
        }
    }

    return 0;
}

void StartJoinOpenClan(int client, int clanId)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT COUNT(1) FROM clan_members WHERE steamid64 = '%s') AS in_clan, "
        ... "(SELECT COUNT(1) FROM clans WHERE id = %d AND is_open = 1) AS clan_open, "
        ... "(SELECT name FROM clans WHERE id = %d LIMIT 1) AS clan_name, "
        ... "(SELECT COALESCE(tag, '') FROM clans WHERE id = %d LIMIT 1) AS clan_tag",
        escapedSteam,
        clanId,
        clanId,
        clanId);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(clanId);
    pack.WriteString(steamid64);

    g_Database.Query(SQL_OnJoinOpenClanValidate, query, pack);
}

public void SQL_OnJoinOpenClanValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Join validation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate that clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Failed to validate that clan.");
        return;
    }

    if (results.FetchInt(0) > 0)
    {
        PrintToChat(client, "[Clans] You are already in a clan.");
        return;
    }

    if (results.FetchInt(1) <= 0)
    {
        PrintToChat(client, "[Clans] That clan is no longer open.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(2, clanName, sizeof(clanName));
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(3, clanTag, sizeof(clanTag));

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(clanId);
    next.WriteString(clanName);
    next.WriteString(clanTag);
    next.WriteString(steamid64);

    AddClanMember(clanId, steamid64, SQL_OnJoinOpenClanSuccess, next, ClanRank_Member);
}

public void SQL_OnJoinOpenClanSuccess(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(clanTag, sizeof(clanTag));
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        if (StrContains(error, "Duplicate", false) != -1 || StrContains(error, "UNIQUE", false) != -1)
        {
            PrintToChat(client, "[Clans] You are already in a clan.");
        }
        else
        {
            PrintToChat(client, "[Clans] Failed to join '%s'.", clanName);
        }
        LogError("[Clans] Join open clan failed: %s", error);
        return;
    }

    if (steamid64[0] != '\0' && clanId > 0)
    {
        SetClientClanIdBySteam64(steamid64, clanId);
    }
    TrySetClanJoinSelectedTag(client, clanTag);

    char memberName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(steamid64, memberName, sizeof(memberName));
    if (clanId > 0)
    {
        AddClanHistoryEntry(clanId, "%s joined the clan", memberName);
    }

    PrintToChat(client, "[Clans] You joined '%s'.", clanName);
}

