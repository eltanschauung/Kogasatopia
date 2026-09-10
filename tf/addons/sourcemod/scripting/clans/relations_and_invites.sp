public Action Command_ClanParent(int client, int args)
{
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

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT clan_id, rank FROM clan_members WHERE steamid64 = '%s' LIMIT 1",
        escapedSteam);

    g_Database.Query(SQL_OnClanParentContext, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanParentContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Parent context query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load parent-clan data.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int ownerClanId = results.FetchInt(0);
    ClanRank rank = view_as<ClanRank>(results.FetchInt(1));
    if (rank < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only clan owners can manage parent relations.");
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, name, tag FROM clans WHERE is_open = 1 AND id <> %d ORDER BY name ASC",
        ownerClanId);

    g_Database.Query(SQL_OnClanParentMenuList, query, GetClientUserId(client));
}

public void SQL_OnClanParentMenuList(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Parent menu query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load open clans.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanParent);
    menu.SetTitle("Choose parent clan");
    menu.AddItem("clear", "Clear parent relation");

    bool added = false;
    while (results != null && results.FetchRow())
    {
        int clanId = results.FetchInt(0);

        char info[16];
        IntToString(clanId, info, sizeof(info));

        char clanName[CLAN_NAME_MAXLEN + 1];
        char clanTag[CLAN_TAG_STORE_MAXLEN];
        char display[160];

        results.FetchString(1, clanName, sizeof(clanName));
        results.FetchString(2, clanTag, sizeof(clanTag));

        if (clanTag[0])
        {
            FormatEx(display, sizeof(display), "%s %s", clanName, clanTag);
        }
        else
        {
            strcopy(display, sizeof(display), clanName);
        }

        menu.AddItem(info, display);
        added = true;
    }

    if (!added)
    {
        menu.AddItem("noop", "No open clans available", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ClanParent(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "clear", false))
        {
            StartClanParentSelection(client, 0);
        }
        else
        {
            StartClanParentSelection(client, StringToInt(info));
        }
    }

    return 0;
}

void StartClanParentSelection(int client, int selectedParentClanId)
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

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT clan_id, rank FROM clan_members WHERE steamid64 = '%s' LIMIT 1",
        escapedSteam);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(selectedParentClanId);

    g_Database.Query(SQL_OnClanParentRevalidateOwner, query, pack);
}

public void SQL_OnClanParentRevalidateOwner(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int selectedParentClanId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Parent owner revalidation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate your clan state.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int ownerClanId = results.FetchInt(0);
    ClanRank rank = view_as<ClanRank>(results.FetchInt(1));
    if (rank < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only clan owners can manage parent relations.");
        return;
    }

    if (selectedParentClanId <= 0)
    {
        ClearParentRelation(ownerClanId, userId);
        return;
    }

    if (selectedParentClanId == ownerClanId)
    {
        PrintToChat(client, "[Clans] Your clan cannot be its own parent.");
        return;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT COUNT(1) FROM clans WHERE id = %d AND is_open = 1) AS parent_ok, "
        ... "(SELECT name FROM clans WHERE id = %d LIMIT 1) AS parent_name",
        selectedParentClanId,
        selectedParentClanId);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(ownerClanId);
    next.WriteCell(selectedParentClanId);

    g_Database.Query(SQL_OnClanParentValidateTarget, query, next);
}

public void SQL_OnClanParentValidateTarget(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int ownerClanId = pack.ReadCell();
    int selectedParentClanId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Parent target validation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate that parent clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Failed to validate that parent clan.");
        return;
    }

    if (results.FetchInt(0) <= 0)
    {
        PrintToChat(client, "[Clans] That clan is not open or no longer exists.");
        return;
    }

    SetParentRelation(ownerClanId, selectedParentClanId, userId);
}

public void SQLTxn_OnSetParentSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    PrintToChat(client, "[Clans] Parent clan relation saved.");
}

public void SQLTxn_OnSetParentFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Failed to save the parent clan relation.");
    }

    LogError("[Clans] Parent relation transaction failed at query %d: %s", failIndex, error);
}

public void SQL_OnClearParentRelation(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clear parent relation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to clear the parent relation.");
        return;
    }

    PrintToChat(client, "[Clans] Parent clan relation cleared.");
}

void AddInviteMenuItem(Menu menu, int inviteId, const char[] clanName, const char[] clanTag, int expiresAt)
{
    char info[16];
    IntToString(inviteId, info, sizeof(info));

    int secondsLeft = expiresAt - GetTime();
    if (secondsLeft < 0)
    {
        secondsLeft = 0;
    }

    int daysLeft = (secondsLeft + 86399) / 86400;
    if (daysLeft < 1)
    {
        daysLeft = 1;
    }

    char display[192];
    if (clanTag[0])
    {
        FormatEx(display, sizeof(display), "%s %s (%d day%s left)", clanName, clanTag, daysLeft, (daysLeft == 1) ? "" : "s");
    }
    else
    {
        FormatEx(display, sizeof(display), "%s (%d day%s left)", clanName, daysLeft, (daysLeft == 1) ? "" : "s");
    }

    menu.AddItem(info, display);
}

void AddInviteBrowseMenuItem(Menu menu, int inviteId, const char[] clanName, const char[] clanTag, const char[] inviterName, int expiresAt)
{
    int secondsLeft = expiresAt - GetTime();
    if (secondsLeft < 0)
    {
        secondsLeft = 0;
    }

    int daysLeft = (secondsLeft + 86399) / 86400;
    if (daysLeft < 1)
    {
        daysLeft = 1;
    }

    char display[256];
    if (clanTag[0])
    {
        FormatEx(display, sizeof(display), "From %s: %s %s (%d day%s left)", inviterName, clanName, clanTag, daysLeft, (daysLeft == 1) ? "" : "s");
    }
    else
    {
        FormatEx(display, sizeof(display), "From %s: %s (%d day%s left)", inviterName, clanName, daysLeft, (daysLeft == 1) ? "" : "s");
    }

    char info[16];
    IntToString(inviteId, info, sizeof(info));
    menu.AddItem(info, display);
}

void ShowInviteActionMenu(int client, int inviteId, const char[] summary)
{
    Menu menu = new Menu(MenuHandler_ClanInviteAction);

    char title[256];
    FormatEx(title, sizeof(title), "Invite Actions\n%s", summary);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    char info[16];
    IntToString(inviteId, info, sizeof(info));
    menu.AddItem(info, "Accept");
    menu.AddItem(info, "Deny");
    menu.Display(client, MENU_TIME_FOREVER);
}

public Action Command_ClanInvites(int client, int args)
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

    GetPendingInvites(steamid64, SQL_OnPendingInvitesForBrowse, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnPendingInvitesForBrowse(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Pending invite query (browse) failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan invites.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanInvites);
    menu.SetTitle("Clan Invites");
    menu.ExitButton = true;

    bool added = false;
    while (results != null && results.FetchRow())
    {
        int inviteId = results.FetchInt(PendingInviteCol_Id);
        char clanName[CLAN_NAME_MAXLEN + 1];
        char clanTag[CLAN_TAG_STORE_MAXLEN];
        char inviterSteam[STEAMID64_MAXLEN];
        char inviterName[MAX_NAME_LENGTH * 2];
        int expiresAt = results.FetchInt(PendingInviteCol_ExpiresAt);

        results.FetchString(PendingInviteCol_ClanName, clanName, sizeof(clanName));
        results.FetchString(PendingInviteCol_ClanTag, clanTag, sizeof(clanTag));
        results.FetchString(PendingInviteCol_InvitedBy, inviterSteam, sizeof(inviterSteam));
        ResolvePlayerDisplayName(inviterSteam, inviterName, sizeof(inviterName));

        AddInviteBrowseMenuItem(menu, inviteId, clanName, clanTag, inviterName, expiresAt);
        added = true;
    }

    if (!added)
    {
        menu.AddItem("none", "No pending clan invites", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ClanInvites(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        char display[256];
        menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));

        int inviteId = StringToInt(info);
        if (inviteId > 0)
        {
            ShowInviteActionMenu(param1, inviteId, display);
        }
    }

    return 0;
}

public int MenuHandler_ClanInviteAction(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanInvites(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        char display[32];
        menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));

        int inviteId = StringToInt(info);
        if (inviteId <= 0)
        {
            return 0;
        }

        if (StrEqual(display, "Accept", false))
        {
            StartAcceptInvite(param1, inviteId);
        }
        else
        {
            StartDenyInvite(param1, inviteId);
        }
    }

    return 0;
}

public Action Command_ClanAcceptInvite(int client, int args)
{
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

    GetPendingInvites(steamid64, SQL_OnPendingInvitesForAccept, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnPendingInvitesForAccept(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Pending invite query (accept) failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan invites.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        return;
    }

    int firstInviteId = results.FetchInt(PendingInviteCol_Id);
    char firstClanName[CLAN_NAME_MAXLEN + 1];
    char firstClanTag[CLAN_TAG_STORE_MAXLEN];
    int firstExpiresAt = results.FetchInt(PendingInviteCol_ExpiresAt);

    results.FetchString(PendingInviteCol_ClanName, firstClanName, sizeof(firstClanName));
    results.FetchString(PendingInviteCol_ClanTag, firstClanTag, sizeof(firstClanTag));

    if (!results.FetchRow())
    {
        StartAcceptInvite(client, firstInviteId);
        return;
    }

    Menu menu = new Menu(MenuHandler_AcceptInvite);
    menu.SetTitle("Select a clan invite to accept");

    AddInviteMenuItem(menu, firstInviteId, firstClanName, firstClanTag, firstExpiresAt);

    do
    {
        int inviteId = results.FetchInt(PendingInviteCol_Id);
        char clanName[CLAN_NAME_MAXLEN + 1];
        char clanTag[CLAN_TAG_STORE_MAXLEN];
        int expiresAt = results.FetchInt(PendingInviteCol_ExpiresAt);

        results.FetchString(PendingInviteCol_ClanName, clanName, sizeof(clanName));
        results.FetchString(PendingInviteCol_ClanTag, clanTag, sizeof(clanTag));

        AddInviteMenuItem(menu, inviteId, clanName, clanTag, expiresAt);
    }
    while (results.FetchRow());

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_AcceptInvite(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        StartAcceptInvite(client, StringToInt(info));
    }

    return 0;
}

void StartAcceptInvite(int client, int inviteId)
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

    int now = GetTime();

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT COUNT(1) FROM clan_members WHERE steamid64 = '%s') AS in_clan, "
        ... "(SELECT COUNT(1) FROM clan_invites WHERE id = %d AND steamid64 = '%s' AND expires_at > %d) AS invite_ok, "
        ... "(SELECT clan_id FROM clan_invites WHERE id = %d AND steamid64 = '%s' AND expires_at > %d LIMIT 1) AS clan_id, "
        ... "(SELECT name FROM clans WHERE id = (SELECT clan_id FROM clan_invites WHERE id = %d AND steamid64 = '%s' AND expires_at > %d LIMIT 1) LIMIT 1) AS clan_name, "
        ... "(SELECT COALESCE(tag, '') FROM clans WHERE id = (SELECT clan_id FROM clan_invites WHERE id = %d AND steamid64 = '%s' AND expires_at > %d LIMIT 1) LIMIT 1) AS clan_tag",
        escapedSteam,
        inviteId,
        escapedSteam,
        now,
        inviteId,
        escapedSteam,
        now,
        inviteId,
        escapedSteam,
        now,
        inviteId,
        escapedSteam,
        now);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(inviteId);
    pack.WriteString(steamid64);

    g_Database.Query(SQL_OnAcceptInviteValidate, query, pack);
}

public void SQL_OnAcceptInviteValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int inviteId = pack.ReadCell();
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
        LogError("[Clans] Accept invite validation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate that invite.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Failed to validate that invite.");
        return;
    }

    if (results.FetchInt(0) > 0)
    {
        PrintToChat(client, "[Clans] You are already in a clan.");
        return;
    }

    if (results.FetchInt(1) <= 0)
    {
        PrintToChat(client, "[Clans] That invite is no longer valid.");
        return;
    }

    int clanId = results.FetchInt(2);
    if (clanId <= 0)
    {
        PrintToChat(client, "[Clans] That invite is no longer valid.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(3, clanName, sizeof(clanName));
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(4, clanTag, sizeof(clanTag));

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    int now = GetTime();

    Transaction txn = new Transaction();
    char query[1024];

    FormatEx(query, sizeof(query),
        "INSERT INTO clan_members (clan_id, steamid64, rank, joined_at) "
        ... "SELECT i.clan_id, '%s', %d, %d "
        ... "FROM clan_invites i "
        ... "INNER JOIN clans c ON c.id = i.clan_id "
        ... "WHERE i.id = %d AND i.steamid64 = '%s' AND i.expires_at > %d LIMIT 1",
        escapedSteam,
        view_as<int>(ClanRank_Member),
        now,
        inviteId,
        escapedSteam,
        now);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "DELETE FROM clan_invites WHERE steamid64 = '%s' "
        ... "AND EXISTS (SELECT 1 FROM clan_members WHERE steamid64 = '%s')",
        escapedSteam,
        escapedSteam);
    txn.AddQuery(query);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteString(steamid64);
    next.WriteString(clanName);
    next.WriteString(clanTag);
    next.WriteCell(clanId);

    g_Database.Execute(txn, SQLTxn_OnAcceptInviteSuccess, SQLTxn_OnAcceptInviteFailure, next);
}

public void SQLTxn_OnAcceptInviteSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char steamid64[STEAMID64_MAXLEN];
    char fallbackClanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    pack.ReadString(steamid64, sizeof(steamid64));
    pack.ReadString(fallbackClanName, sizeof(fallbackClanName));
    pack.ReadString(clanTag, sizeof(clanTag));
    int clanId = pack.ReadCell();
    delete pack;

    if (steamid64[0] != '\0' && clanId > 0)
    {
        SetClientClanIdBySteam64(steamid64, clanId);
    }

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    TrySetClanJoinSelectedTag(client, clanTag);

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.name FROM clan_members m INNER JOIN clans c ON c.id = m.clan_id WHERE m.steamid64 = '%s' LIMIT 1",
        escapedSteam);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteString(fallbackClanName);
    next.WriteString(steamid64);
    next.WriteCell(clanId);

    g_Database.Query(SQL_OnAcceptInviteVerify, query, next);
}

public void SQLTxn_OnAcceptInviteFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char ignoredSteam[STEAMID64_MAXLEN];
    char ignoredClan[CLAN_NAME_MAXLEN + 1];
    char ignoredTag[CLAN_TAG_STORE_MAXLEN];
    pack.ReadString(ignoredSteam, sizeof(ignoredSteam));
    pack.ReadString(ignoredClan, sizeof(ignoredClan));
    pack.ReadString(ignoredTag, sizeof(ignoredTag));
    pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        if (StrContains(error, "Duplicate", false) != -1 || StrContains(error, "UNIQUE", false) != -1)
        {
            PrintToChat(client, "[Clans] You are already in a clan.");
        }
        else
        {
            PrintToChat(client, "[Clans] Failed to accept that invite.");
        }
    }

    LogError("[Clans] Accept invite transaction failed at query %d: %s", failIndex, error);
}

public void SQL_OnAcceptInviteVerify(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char fallbackClanName[CLAN_NAME_MAXLEN + 1];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(fallbackClanName, sizeof(fallbackClanName));
    pack.ReadString(steamid64, sizeof(steamid64));
    int clanId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Accept invite verify query failed: %s", error);
        PrintToChat(client, "[Clans] Invite processed, but verification failed.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] That invite was no longer valid.");
        return;
    }

    char actualClanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(0, actualClanName, sizeof(actualClanName));
    if (!actualClanName[0])
    {
        strcopy(actualClanName, sizeof(actualClanName), fallbackClanName);
    }

    char memberName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(steamid64, memberName, sizeof(memberName));
    if (clanId > 0)
    {
        AddClanHistoryEntry(clanId, "%s joined the clan", memberName);
    }

    PrintToChat(client, "[Clans] You joined '%s'.", actualClanName);
    AnnounceClanInviteAcceptedToMembers(clanId, actualClanName, steamid64);
}

public Action Command_ClanDenyInvite(int client, int args)
{
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

    GetPendingInvites(steamid64, SQL_OnPendingInvitesForDeny, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnPendingInvitesForDeny(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Pending invite query (deny) failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan invites.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You have no pending clan invites.");
        return;
    }

    int firstInviteId = results.FetchInt(PendingInviteCol_Id);
    char firstClanName[CLAN_NAME_MAXLEN + 1];
    char firstClanTag[CLAN_TAG_STORE_MAXLEN];
    int firstExpiresAt = results.FetchInt(PendingInviteCol_ExpiresAt);

    results.FetchString(PendingInviteCol_ClanName, firstClanName, sizeof(firstClanName));
    results.FetchString(PendingInviteCol_ClanTag, firstClanTag, sizeof(firstClanTag));

    if (!results.FetchRow())
    {
        StartDenyInvite(client, firstInviteId);
        return;
    }

    Menu menu = new Menu(MenuHandler_DenyInvite);
    menu.SetTitle("Select a clan invite to deny");

    AddInviteMenuItem(menu, firstInviteId, firstClanName, firstClanTag, firstExpiresAt);

    do
    {
        int inviteId = results.FetchInt(PendingInviteCol_Id);
        char clanName[CLAN_NAME_MAXLEN + 1];
        char clanTag[CLAN_TAG_STORE_MAXLEN];
        int expiresAt = results.FetchInt(PendingInviteCol_ExpiresAt);

        results.FetchString(PendingInviteCol_ClanName, clanName, sizeof(clanName));
        results.FetchString(PendingInviteCol_ClanTag, clanTag, sizeof(clanTag));

        AddInviteMenuItem(menu, inviteId, clanName, clanTag, expiresAt);
    }
    while (results.FetchRow());

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DenyInvite(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        StartDenyInvite(client, StringToInt(info));
    }

    return 0;
}

void StartDenyInvite(int client, int inviteId)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(inviteId);

    DeleteInvite(inviteId, SQL_OnDenyInviteDeleted, pack);
}

public void SQL_OnDenyInviteDeleted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int inviteId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Deny invite delete failed: %s", error);
        PrintToChat(client, "[Clans] Failed to deny that invite.");
        return;
    }

    PrintToChat(client, "[Clans] Invite #%d denied.", inviteId);
}
