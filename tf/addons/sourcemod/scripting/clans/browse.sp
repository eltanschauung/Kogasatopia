public void SQL_OnClansListMenu(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan list query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load the clan list.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClansList);
    menu.SetTitle("Clans");
    menu.ExitButton = true;

    bool added = false;
    if (results != null)
    {
        while (results.FetchRow())
        {
            int clanId = results.FetchInt(0);
            int memberCount = results.FetchInt(3);
            int cachedGems = results.FetchInt(4);

            char name[CLAN_NAME_MAXLEN + 1];
            char tag[CLAN_TAG_STORE_MAXLEN];
            char info[96];
            char display[192];

            results.FetchString(1, name, sizeof(name));
            results.FetchString(2, tag, sizeof(tag));
            FormatEx(info, sizeof(info), "%d|%s", clanId, name);

            if (tag[0])
            {
                FormatEx(display, sizeof(display), "%s %s (%d, %d Gems)", name, tag, memberCount, cachedGems);
            }
            else
            {
                FormatEx(display, sizeof(display), "%s (%d, %d Gems)", name, memberCount, cachedGems);
            }

            CRemoveTags(display, sizeof(display));
            menu.AddItem(info, display);
            added = true;
        }
    }

    if (!added)
    {
        menu.AddItem("none", "No clans found", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClansList(Menu menu, MenuAction action, int param1, int param2)
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
            GetClanInfoById(clanId, SQL_OnClanInfoMenu, GetClientUserId(param1));
        }
    }

    return 0;
}

public void SQL_OnClanInfoMenu(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan info menu query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan info.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Clan not found.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char ownerSteam[STEAMID64_MAXLEN];
    char description[CLAN_DESC_MAXLEN + 1];
    char ownerName[MAX_NAME_LENGTH * 2];
    char title[192];
    char line[256];

    results.FetchString(1, clanName, sizeof(clanName));
    results.FetchString(2, clanTag, sizeof(clanTag));
    results.FetchString(3, ownerSteam, sizeof(ownerSteam));
    results.FetchString(4, description, sizeof(description));
    ResolvePlayerDisplayName(ownerSteam, ownerName, sizeof(ownerName));

    Menu menu = new Menu(MenuHandler_ClanInfoMenu);
    FormatEx(title, sizeof(title), "Clan Info\n%s", clanName);
    menu.SetTitle(title);

    FormatEx(line, sizeof(line), "Hokage: %s", ownerName);
    menu.AddItem("owner", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Clan tag: %s", clanTag[0] ? clanTag : "(none)");
    menu.AddItem("tag", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Desc: %s", description[0] ? description : "(none)");
    menu.AddItem("desc", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Member count: %d", results.FetchInt(5));
    menu.AddItem("members", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Gems: %d", results.FetchInt(6));
    menu.AddItem("gems", line, ITEMDRAW_DISABLED);

    menu.ExitButton = true;
    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanInfoMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void SQL_OnClanMenuContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan menu context query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan menu.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        ShowClanMainMenu(client, 0, ClanRank_Member, "", "", false, 0);
        return;
    }

    int clanId = results.FetchInt(ClanMenuCol_ClanId);
    ClanRank rank = view_as<ClanRank>(results.FetchInt(ClanMenuCol_Rank));
    int inviteCount = results.FetchInt(ClanMenuCol_InviteCount);
    bool isOpen = (results.FetchInt(ClanMenuCol_IsOpen) != 0);

    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(ClanMenuCol_ClanName, clanName, sizeof(clanName));
    results.FetchString(ClanMenuCol_ClanTag, clanTag, sizeof(clanTag));

    ShowClanMainMenu(client, clanId, rank, clanName, clanTag, isOpen, inviteCount);
}

public int MenuHandler_ClanMain(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "create", false))
        {
            Command_ClanCreate(client, 0);
        }
        else if (StrEqual(info, "join", false))
        {
            Command_ClanJoin(client, 0);
        }
        else if (StrEqual(info, "invites", false))
        {
            Command_ClanInvites(client, 0);
        }
        else if (StrEqual(info, "accept", false))
        {
            Command_ClanAcceptInvite(client, 0);
        }
        else if (StrEqual(info, "deny", false))
        {
            Command_ClanDenyInvite(client, 0);
        }
        else if (StrEqual(info, "leave", false))
        {
            Command_ClanLeave(client, 0);
        }
        else if (StrEqual(info, "members", false))
        {
            Command_ClanMembers(client, 0);
        }
        else if (StrEqual(info, "history", false))
        {
            Command_ClanHistory(client, 0);
        }
        else if (StrEqual(info, "tag", false))
        {
            StartClanTagPrompt(client);
        }
        else if (StrEqual(info, "rename", false))
        {
            Command_ClanRename(client, 0);
        }
        else if (StrEqual(info, "desc", false))
        {
            Command_ClanDesc(client, 0);
        }
        else if (StrEqual(info, "invite", false))
        {
            ShowClanInviteTargetMenu(client);
        }
        else if (StrEqual(info, "kick", false))
        {
            ShowClanKickTargetMenu(client);
        }
        else if (StrEqual(info, "war", false))
        {
            Command_ClanWar(client, 0);
        }
        else if (StrEqual(info, "open", false))
        {
            Command_ClanOpen(client, 0);
        }
        else if (StrEqual(info, "parent", false))
        {
            Command_ClanParent(client, 0);
        }
        else if (StrEqual(info, "refresh", false))
        {
            Command_ClanMenu(client, 0);
        }
    }

    return 0;
}

public Action Command_ClanMembers(int client, int args)
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

    GetClanByPlayer(steamid64, SQL_OnClanMembersContext, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Command_ClanDesc(int client, int args)
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

    GetClanByPlayer(steamid64, SQL_OnClanDescPromptContext, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Command_ClanRename(int client, int args)
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

    GetClanByPlayer(steamid64, SQL_OnClanRenamePromptContext, GetClientUserId(client));
    return Plugin_Handled;
}

public Action Command_ClanSetDesc(int client, int args)
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
        ... ") AS member_count "
        ... "FROM clans c "
        ... "ORDER BY member_count DESC, c.name ASC");

    g_Database.Query(SQL_OnClanSetDescMenu, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanSetDescMenu(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan setdesc list query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load the clan list.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanSetDescList);
    menu.SetTitle("Set Clan Desc");
    menu.ExitButton = true;

    bool added = false;
    if (results != null)
    {
        while (results.FetchRow())
        {
            int clanId = results.FetchInt(0);
            int memberCount = results.FetchInt(3);

            char name[CLAN_NAME_MAXLEN + 1];
            char tag[CLAN_TAG_STORE_MAXLEN];
            char info[96];
            char display[192];

            results.FetchString(1, name, sizeof(name));
            results.FetchString(2, tag, sizeof(tag));
            FormatEx(info, sizeof(info), "%d|%s", clanId, name);

            if (tag[0])
            {
                FormatEx(display, sizeof(display), "%s %s (%d)", name, tag, memberCount);
            }
            else
            {
                FormatEx(display, sizeof(display), "%s (%d)", name, memberCount);
            }

            menu.AddItem(info, display);
            added = true;
        }
    }

    if (!added)
    {
        menu.AddItem("none", "No clans found", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanSetDescList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[96];
        menu.GetItem(param2, info, sizeof(info));

        int sep = StrContains(info, "|");
        if (sep == -1)
        {
            return 0;
        }

        char clanIdText[16];
        char clanName[CLAN_NAME_MAXLEN + 1];
        strcopy(clanIdText, sizeof(clanIdText), info);
        clanIdText[sep] = '\0';
        strcopy(clanName, sizeof(clanName), info[sep + 1]);

        int clanId = StringToInt(clanIdText);
        if (clanId <= 0)
        {
            return 0;
        }

        g_PendingAdminClanDescId[param1] = clanId;
        strcopy(g_PendingAdminClanDescName[param1], sizeof(g_PendingAdminClanDescName[]), clanName);
        g_PromptState[param1] = Prompt_ClanAdminDescInput;

        PrintToChat(param1, "[Clans] Type the new description for '%s' in chat. Max length: %d. Type /cancel to abort.", clanName, CLAN_DESC_MAXLEN);
    }

    return 0;
}

public void SQL_OnClanDescPromptContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan description prompt context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank)) < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only the clan owner can set the clan description.");
        return;
    }

    g_PromptState[client] = Prompt_ClanDescInput;
    PrintToChat(client, "[Clans] Type your clan description in chat. Max length: %d. Type /cancel to abort.", CLAN_DESC_MAXLEN);
}

public void SQL_OnClanRenamePromptContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan rename prompt context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank)) < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only the clan owner can rename the clan.");
        return;
    }

    g_PromptState[client] = Prompt_ClanRenameName;
    PrintToChat(client, "[Clans] Type the new clan name in chat. Type /cancel to abort.");
}

public void SQL_OnClanDescContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char description[CLAN_DESC_MAXLEN + 1];
    pack.ReadString(description, sizeof(description));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan description context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank)) < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only the clan owner can set the clan description.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteString(description);

    SetClanDescription(clanId, description, SQL_OnClanDescSet, next);
}

public void SQL_OnAdminClanDescContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char description[CLAN_DESC_MAXLEN + 1];
    char fallbackClanName[CLAN_NAME_MAXLEN + 1];
    pack.ReadString(description, sizeof(description));
    pack.ReadString(fallbackClanName, sizeof(fallbackClanName));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Admin clan description context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up that clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] That clan no longer exists.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(1, clanName, sizeof(clanName));
    if (!clanName[0])
    {
        strcopy(clanName, sizeof(clanName), fallbackClanName);
    }

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteString(clanName);
    next.WriteString(description);

    SetClanDescription(clanId, description, SQL_OnAdminClanDescSet, next);
}

public void SQL_OnClanDescSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char description[CLAN_DESC_MAXLEN + 1];
    pack.ReadString(description, sizeof(description));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Set description failed: %s", error);
        PrintToChat(client, "[Clans] Failed to set the clan description.");
        return;
    }

    PrintToChat(client, "[Clans] Clan description updated.");
}

public void SQL_OnAdminClanDescSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char description[CLAN_DESC_MAXLEN + 1];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(description, sizeof(description));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Admin set description failed: %s", error);
        PrintToChat(client, "[Clans] Failed to set that clan description.");
        return;
    }

    PrintToChat(client, "[Clans] Clan description updated for '%s'.", clanName);
}

public Action Command_ClanInfo(int client, int args)
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
        ReplyToCommand(client, "[Clans] Usage: sm_claninfo <player|clan name|clan tag|sub-tag>");
        return Plugin_Handled;
    }

    char input[192];
    GetCmdArgString(input, sizeof(input));
    StripQuotes(input);
    TrimString(input);

    if (!input[0])
    {
        ReplyToCommand(client, "[Clans] Usage: sm_claninfo <player|clan name|clan tag|sub-tag>");
        return Plugin_Handled;
    }

    int target = FindClientByNameQuery(input);
    if (target > 0)
    {
        char steamid64[STEAMID64_MAXLEN];
        if (!GetClientSteam64(target, steamid64, sizeof(steamid64)))
        {
            PrintToChat(client, "[Clans] Could not read that player's SteamID64.");
            return Plugin_Handled;
        }

        GetClanByPlayer(steamid64, SQL_OnClanInfoPlayerLookup, GetClientUserId(client));
        return Plugin_Handled;
    }

    char escapedInput[256];
    char formattedTag[CLAN_TAG_STORE_MAXLEN];
    char escapedFormatted[256];
    EscapeSql(input, escapedInput, sizeof(escapedInput));
    FormatStoredClanTag(input, formattedTag, sizeof(formattedTag));
    EscapeSql(formattedTag, escapedFormatted, sizeof(escapedFormatted));

    char query[1400];
    FormatEx(query, sizeof(query),
        "SELECT DISTINCT c.id "
        ... "FROM clans c "
        ... "LEFT JOIN clan_sub_tags cst ON cst.clan_id = c.id "
        ... "WHERE LOWER(c.name) = LOWER('%s') "
        ... "OR LOWER(c.tag) = LOWER('%s') "
        ... "OR LOWER(c.tag) = LOWER('%s') "
        ... "OR LOWER(cst.tag) = LOWER('%s') "
        ... "OR LOWER(c.name) LIKE LOWER('%%%s%%') "
        ... "OR LOWER(c.tag) LIKE LOWER('%%%s%%') "
        ... "OR LOWER(cst.tag) LIKE LOWER('%%%s%%') "
        ... "ORDER BY CASE "
        ... "WHEN LOWER(c.name) = LOWER('%s') THEN 0 "
        ... "WHEN LOWER(c.tag) = LOWER('%s') THEN 1 "
        ... "WHEN LOWER(c.tag) = LOWER('%s') THEN 2 "
        ... "WHEN LOWER(cst.tag) = LOWER('%s') THEN 3 "
        ... "WHEN LOWER(c.name) LIKE LOWER('%%%s%%') THEN 4 "
        ... "WHEN LOWER(c.tag) LIKE LOWER('%%%s%%') THEN 5 "
        ... "WHEN LOWER(cst.tag) LIKE LOWER('%%%s%%') THEN 6 "
        ... "ELSE 7 END, c.id ASC "
        ... "LIMIT 1",
        escapedInput,
        escapedInput,
        escapedFormatted,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedFormatted,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput);

    g_Database.Query(SQL_OnClanInfoSearchLookup, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanInfoPlayerLookup(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan info player lookup failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan info.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] That player is not in a clan.");
        return;
    }

    GetClanInfoById(results.FetchInt(ClanByPlayerCol_Id), SQL_OnClanInfoById, GetClientUserId(client));
}

public void SQL_OnClanInfoSearchLookup(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan info search lookup failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan info.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] No clan matched that query.");
        return;
    }

    GetClanInfoById(results.FetchInt(0), SQL_OnClanInfoById, GetClientUserId(client));
}

public void SQL_OnClanInfoById(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan info query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan info.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Clan not found.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char ownerSteam[STEAMID64_MAXLEN];
    char description[CLAN_DESC_MAXLEN + 1];
    char ownerName[MAX_NAME_LENGTH * 2];

    results.FetchString(1, clanName, sizeof(clanName));
    results.FetchString(2, clanTag, sizeof(clanTag));
    results.FetchString(3, ownerSteam, sizeof(ownerSteam));
    results.FetchString(4, description, sizeof(description));
    ResolvePlayerDisplayName(ownerSteam, ownerName, sizeof(ownerName));

    CPrintToChat(client, "{default}[Clans] %s", clanName);
    CPrintToChat(client, "{default}[Clans] Hokage: %s", ownerName);
    CPrintToChat(client, "{default}[Clans] Clan tag: %s", clanTag[0] ? clanTag : "(none)");
    CPrintToChat(client, "{default}[Clans] Desc: %s", description[0] ? description : "(none)");
    CPrintToChat(client, "{default}[Clans] Member count: %d", results.FetchInt(5));
    CPrintToChat(client, "{default}[Clans] Gems: %d", results.FetchInt(6));
}

public Action Command_ClanGems(int client, int args)
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
        ReplyToCommand(client, "[Clans] Usage: sm_clangems <clan name or online player>");
        return Plugin_Handled;
    }

    char input[192];
    GetCmdArgString(input, sizeof(input));
    StripQuotes(input);
    TrimString(input);

    if (!input[0])
    {
        ReplyToCommand(client, "[Clans] Usage: sm_clangems <clan name or online player>");
        return Plugin_Handled;
    }

    char escapedInput[256];
    EscapeSql(input, escapedInput, sizeof(escapedInput));

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name "
        ... "FROM clans c "
        ... "WHERE LOWER(c.name) = LOWER('%s') "
        ... "OR LOWER(c.name) LIKE LOWER('%s%%') "
        ... "OR LOWER(c.name) LIKE LOWER('%%%s%%') "
        ... "ORDER BY CASE "
        ... "WHEN LOWER(c.name) = LOWER('%s') THEN 0 "
        ... "WHEN LOWER(c.name) LIKE LOWER('%s%%') THEN 1 "
        ... "ELSE 2 END, c.name ASC "
        ... "LIMIT 2",
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput,
        escapedInput);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(input);

    g_Database.Query(SQL_OnClanGemsSearchLookup, query, pack);
    return Plugin_Handled;
}

public void SQL_OnClanGemsSearchLookup(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char input[192];
    pack.ReadString(input, sizeof(input));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan Gems search failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up clan Gems.");
        return;
    }

    if (results != null && results.FetchRow())
    {
        int clanId = results.FetchInt(0);
        char matchedName[CLAN_NAME_MAXLEN + 1];
        results.FetchString(1, matchedName, sizeof(matchedName));

        if (!StrEqual(matchedName, input, false) && results.FetchRow())
        {
            PrintToChat(client, "[Clans] Multiple clans matched that query.");
            return;
        }

        QueryClanGemsById(clanId, SQL_OnClanGemsById, userId);
        return;
    }

    int target = FindClientByNameQuery(input);
    if (target <= 0)
    {
        PrintToChat(client, "[Clans] No clan or online player matched that query.");
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(target, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read that player's SteamID64.");
        return;
    }

    GetClanByPlayer(steamid64, SQL_OnClanGemsPlayerLookup, userId);
}

public void SQL_OnClanGemsPlayerLookup(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan Gems player lookup failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up clan Gems.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] That player is not in a clan.");
        return;
    }

    QueryClanGemsById(results.FetchInt(ClanByPlayerCol_Id), SQL_OnClanGemsById, data);
}

public void SQL_OnClanGemsById(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan Gems aggregate query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to calculate clan Gems.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Clan not found.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(1, clanName, sizeof(clanName));

    CPrintToChat(client, "{default}[Clans] %s Gems: %d", clanName, results.FetchInt(2));
}

public void SQL_OnClanMembersContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan members context query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan members.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(ClanByPlayerCol_Name, clanName, sizeof(clanName));

    QueryClanMembersListForClient(GetClientUserId(client), clanId, clanName);
}

public void SQL_OnClanMembersList(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    pack.ReadString(clanName, sizeof(clanName));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan members list query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan members.");
        return;
    }

    g_iClanMembersMenuClanId[client] = clanId;
    strcopy(g_sClanMembersMenuClanName[client], sizeof(g_sClanMembersMenuClanName[]), clanName);

    char clientSteamId[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, clientSteamId, sizeof(clientSteamId)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanMembersList);

    char title[192];
    FormatEx(title, sizeof(title), "Clan Members\n%s", clanName);
    menu.SetTitle(title);

    if (results != null)
    {
        while (results.FetchRow())
        {
            char steamid64[STEAMID64_MAXLEN];
            results.FetchString(ClanMemberListCol_SteamId64, steamid64, sizeof(steamid64));
            char label[192];
            BuildClanMemberMenuLabel(clientSteamId, steamid64, view_as<ClanRank>(results.FetchInt(ClanMemberListCol_Rank)), label, sizeof(label));
            menu.AddItem(steamid64, label);
        }
    }
    
    if (menu.ItemCount <= 0)
    {
        menu.AddItem("none", "No members found", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanMembersList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanMenu(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        if (client <= 0 || !IsClientInGame(client))
        {
            return 0;
        }

        char steamid64[STEAMID64_MAXLEN];
        menu.GetItem(param2, steamid64, sizeof(steamid64));

        if (!steamid64[0] || StrEqual(steamid64, "none", false))
        {
            return 0;
        }

        QueryClanMemberDetailsForClient(
            GetClientUserId(client),
            g_iClanMembersMenuClanId[client],
            g_sClanMembersMenuClanName[client],
            steamid64);
    }

    return 0;
}

public void SQL_OnClanMemberDetails(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan member details query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load clan member details.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Failed to load that clan member.");
        return;
    }

    g_iClanMembersMenuClanId[client] = clanId;
    strcopy(g_sClanMembersMenuClanName[client], sizeof(g_sClanMembersMenuClanName[]), clanName);

    char playerName[MAX_NAME_LENGTH * 2];
    char rankLabel[16];
    char joinedAtText[64];
    char subTag[CLAN_SUB_TAG_STORE_MAXLEN];
    char title[192];
    char line[192];
    int totalWarKills = results.FetchInt(3);

    ResolvePlayerDisplayName(steamid64, playerName, sizeof(playerName));
    GetClanRankLabel(view_as<ClanRank>(results.FetchInt(0)), rankLabel, sizeof(rankLabel));
    FormatClanTimestamp(results.FetchInt(1), joinedAtText, sizeof(joinedAtText));
    results.FetchString(2, subTag, sizeof(subTag));
    TrimString(subTag);

    Menu menu = new Menu(MenuHandler_ClanMemberDetails);
    FormatEx(title, sizeof(title), "Clan Member\n%s", clanName);
    menu.SetTitle(title);

    FormatEx(line, sizeof(line), "Player Name: %s", playerName);
    menu.AddItem("name", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Rank: %s", rankLabel);
    menu.AddItem("rank", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Join Date: %s", joinedAtText);
    menu.AddItem("joined", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Sub-Tag: %s", subTag[0] ? subTag : "None");
    menu.AddItem("subtag", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "War Kills: %d", totalWarKills);
    menu.AddItem("warkills", line, ITEMDRAW_DISABLED);

    menu.ExitBackButton = true;
    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanMemberDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            QueryClanMembersListForClient(
                GetClientUserId(param1),
                g_iClanMembersMenuClanId[param1],
                g_sClanMembersMenuClanName[param1]);
        }
    }

    return 0;
}

void StartSetClanSubTagFromInput(int client, const char[] input)
{
    char rawTag[CLAN_SUB_TAG_MAXLEN + 1];
    strcopy(rawTag, sizeof(rawTag), input);
    StripQuotes(rawTag);
    TrimString(rawTag);
    NormalizeClanTagText(rawTag);

    if (!rawTag[0])
    {
        PrintToChat(client, "[Clans] Sub-tag cannot be empty.");
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(rawTag);
    pack.WriteString(steamid64);

    GetClanByPlayer(steamid64, SQL_OnClanSubTagContext, pack);
}

void HandleClanCreateInput(int client, const char[] name)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    strcopy(clanName, sizeof(clanName), name);
    TrimString(clanName);

    if (!ValidateClanName(clanName))
    {
        PrintToChat(client, "[Clans] Clan names must be between 1 and %d characters.", CLAN_NAME_MAXLEN);
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(clanName, escapedName, sizeof(escapedName));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT COUNT(1) FROM clan_members WHERE steamid64 = '%s') AS in_clan, "
        ... "(SELECT COUNT(1) FROM clans WHERE name = '%s') AS name_taken",
        escapedSteam,
        escapedName);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(clanName);

    g_Database.Query(SQL_OnClanCreateValidate, query, pack);
}

void HandleClanRenameInput(int client, const char[] name)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    strcopy(clanName, sizeof(clanName), name);
    TrimString(clanName);

    if (!ValidateClanName(clanName))
    {
        PrintToChat(client, "[Clans] Clan names must be between 1 and %d characters.", CLAN_NAME_MAXLEN);
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(clanName, escapedName, sizeof(escapedName));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.id, cm.rank, "
        ... "(SELECT COUNT(1) FROM clans WHERE name = '%s' AND id != c.id) AS name_taken "
        ... "FROM clan_members cm "
        ... "INNER JOIN clans c ON c.id = cm.clan_id "
        ... "WHERE cm.steamid64 = '%s' LIMIT 1",
        escapedName,
        escapedSteam);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(clanName);

    g_Database.Query(SQL_OnClanRenameValidate, query, pack);
}

public void SQL_OnClanTagPromptContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Clan tag prompt context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    ClanRank rank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));
    char currentTag[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(ClanByPlayerCol_Tag, currentTag, sizeof(currentTag));
    TrimString(currentTag);

    if (!currentTag[0])
    {
        if (rank < ClanRank_Owner)
        {
            PrintToChat(client, "[Clans] Your clan owner must set a main clan tag before members can add sub-tags.");
            return;
        }

        g_PromptState[client] = Prompt_ClanTagInput;
        PrintToChat(client, "[Clans] Type your clan tag in chat. Type /cancel to abort.");
        return;
    }

    g_PromptState[client] = Prompt_ClanTagChoice;
    PrintToChat(client, "[Clans] Your clan already has a tag; use /cancel to cancel, /change to change the tag, and /sub to add an additional tag to your clan");
}

