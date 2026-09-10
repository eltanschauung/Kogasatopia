void ShowClanInviteTargetMenu(int client)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanInviteTarget);
    menu.SetTitle("Invite player to clan");
    menu.ExitBackButton = true;

    bool added = false;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (target == client || !IsClientInGame(target) || IsFakeClient(target))
        {
            continue;
        }

        char steamid64[STEAMID64_MAXLEN];
        if (!GetClientSteam64(target, steamid64, sizeof(steamid64)))
        {
            continue;
        }

        char targetName[MAX_NAME_LENGTH];
        GetClientName(target, targetName, sizeof(targetName));

        menu.AddItem(steamid64, targetName);
        added = true;
    }

    if (!added)
    {
        menu.AddItem("none", "No valid players online", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanInviteTarget(Menu menu, MenuAction action, int param1, int param2)
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
        char steamid64[STEAMID64_MAXLEN];
        menu.GetItem(param2, steamid64, sizeof(steamid64));

        int target = Kogasa_FindClientBySteamId64(steamid64);
        if (target <= 0)
        {
            PrintToChat(param1, "[Clans] That player is no longer available.");
            ShowClanInviteTargetMenu(param1);
            return 0;
        }

        StartClanInviteToTarget(param1, target);
    }

    return 0;
}

public Action Command_ClanInvite(int client, int args)
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
        ReplyToCommand(client, "[Clans] Usage: sm_claninvite <target>");
        return Plugin_Handled;
    }

    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    int target = FindTarget(client, arg, true, false);
    if (target <= 0)
    {
        return Plugin_Handled;
    }

    StartClanInviteToTarget(client, target);
    return Plugin_Handled;
}

public void SQL_OnClanInviteInviterContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int inviterUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    int inviter = GetClientOfUserId(inviterUserId);
    if (inviter <= 0 || !IsClientInGame(inviter))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Invite clan lookup failed: %s", error);
        PrintToChat(inviter, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(inviter, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(ClanByPlayerCol_Name, clanName, sizeof(clanName));

    char escapedTarget[SQL_STEAMID64_MAXLEN];
    EscapeSql(targetSteam, escapedTarget, sizeof(escapedTarget));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT "
        ... "(SELECT COUNT(1) FROM clan_members WHERE steamid64 = '%s') AS in_clan, "
        ... "(SELECT COUNT(1) FROM clan_invites WHERE clan_id = %d AND steamid64 = '%s' AND expires_at > %d) AS invite_exists",
        escapedTarget,
        clanId,
        escapedTarget,
        GetTime());

    DataPack next = new DataPack();
    next.WriteCell(inviterUserId);
    next.WriteCell(targetUserId);
    next.WriteCell(clanId);
    next.WriteString(clanName);
    next.WriteString(targetSteam);

    g_Database.Query(SQL_OnClanInviteTargetValidate, query, next);
}

public void SQL_OnClanInviteTargetValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int inviterUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    int inviter = GetClientOfUserId(inviterUserId);
    if (inviter <= 0 || !IsClientInGame(inviter))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Invite target validation failed: %s", error);
        PrintToChat(inviter, "[Clans] Failed to validate the invite target.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(inviter, "[Clans] Failed to validate the invite target.");
        return;
    }

    if (results.FetchInt(0) > 0)
    {
        PrintToChat(inviter, "[Clans] That player is already in a clan.");
        return;
    }

    if (results.FetchInt(1) > 0)
    {
        PrintToChat(inviter, "[Clans] That player already has a pending invite from your clan.");
        return;
    }

    char inviterSteam[STEAMID64_MAXLEN];
    if (!GetClientSteam64(inviter, inviterSteam, sizeof(inviterSteam)))
    {
        PrintToChat(inviter, "[Clans] Could not read your SteamID64.");
        return;
    }

    DataPack next = new DataPack();
    next.WriteCell(inviterUserId);
    next.WriteCell(targetUserId);
    next.WriteCell(clanId);
    next.WriteString(clanName);
    next.WriteString(targetSteam);
    next.WriteString(inviterSteam);

    CreateInvite(clanId, targetSteam, inviterSteam, SQL_OnClanInviteCreated, next);
}

public void SQL_OnClanInviteCreated(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int inviterUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char targetSteam[STEAMID64_MAXLEN];
    char inviterSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(targetSteam, sizeof(targetSteam));
    pack.ReadString(inviterSteam, sizeof(inviterSteam));
    delete pack;

    int inviter = GetClientOfUserId(inviterUserId);
    int target = GetClientOfUserId(targetUserId);

    if (error[0])
    {
        if (inviter > 0 && IsClientInGame(inviter))
        {
            PrintToChat(inviter, "[Clans] Failed to create the invite.");
        }
        LogError("[Clans] CreateInvite failed: %s", error);
        return;
    }

    if (inviter > 0 && IsClientInGame(inviter))
    {
        char targetName[MAX_NAME_LENGTH];
        ResolvePlayerDisplayName(targetSteam, targetName, sizeof(targetName));
        PrintToChat(inviter, "[Clans] Invite sent to %s for '%s'.", targetName, clanName);
    }

    if (target > 0 && IsClientInGame(target))
    {
        char inviterName[MAX_NAME_LENGTH];
        ResolvePlayerDisplayName(inviterSteam, inviterName, sizeof(inviterName));
        PrintToChat(target, "[Clans] %s has invited you to clan %s! Type !accept to accept the invite.", inviterName, clanName);
    }

    char inviterName[MAX_NAME_LENGTH * 2];
    char targetName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(inviterSteam, inviterName, sizeof(inviterName));
    ResolvePlayerDisplayName(targetSteam, targetName, sizeof(targetName));
    AddClanHistoryEntry(clanId, "%s invited %s", inviterName, targetName);

    AnnounceClanInviteToMembers(clanId, clanName, inviterSteam, targetSteam);
}

void StartClanKickSteam64(int client, const char[] targetSteam)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    if (!targetSteam[0])
    {
        PrintToChat(client, "[Clans] That player is not available.");
        return;
    }

    char actorSteam[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, actorSteam, sizeof(actorSteam)))
    {
        PrintToChat(client, "[Clans] Failed to read a SteamID64.");
        return;
    }

    if (StrEqual(actorSteam, targetSteam, false))
    {
        PrintToChat(client, "[Clans] Use sm_clanleave to leave your clan.");
        return;
    }

    int target = Kogasa_FindClientBySteamId64(targetSteam);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(target > 0 ? GetClientUserId(target) : 0);
    pack.WriteString(targetSteam);

    GetClanByPlayer(actorSteam, SQL_OnClanKickActorContext, pack);
}

void ShowClanKickTargetMenu(int client)
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

    GetClanByPlayer(steamid64, SQL_OnClanKickMenuContext, GetClientUserId(client));
}

public void SQL_OnClanKickMenuContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick menu context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load kick targets.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    ClanRank actorRank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can kick members.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(view_as<int>(actorRank));

    GetClanMembers(clanId, SQL_OnClanKickMenuMembers, pack);
}

public void SQL_OnClanKickMenuMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    ClanRank actorRank = view_as<ClanRank>(pack.ReadCell());
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick menu member query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load kick targets.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanKickTarget);
    menu.SetTitle("Kick clan member");
    menu.ExitBackButton = true;

    bool added = false;
    while (results != null && results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        if (Kogasa_FindClientBySteamId64(memberSteam) == client)
        {
            continue;
        }

        ClanRank targetRank = view_as<ClanRank>(results.FetchInt(1));
        if (targetRank >= ClanRank_Owner)
        {
            continue;
        }

        if (actorRank == ClanRank_Officer && targetRank >= ClanRank_Officer)
        {
            continue;
        }

        char targetName[MAX_NAME_LENGTH];
        char targetRankName[16];
        char display[128];

        ResolvePlayerDisplayName(memberSteam, targetName, sizeof(targetName));
        GetClanRankLabel(targetRank, targetRankName, sizeof(targetRankName));
        FormatEx(display, sizeof(display), "%s (%s)", targetName, targetRankName);

        menu.AddItem(memberSteam, display);
        added = true;
    }

    if (!added)
    {
        menu.AddItem("none", "No kickable members", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

public int MenuHandler_ClanKickTarget(Menu menu, MenuAction action, int param1, int param2)
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
        char steamid64[STEAMID64_MAXLEN];
        menu.GetItem(param2, steamid64, sizeof(steamid64));

        StartClanKickSteam64(param1, steamid64);
    }

    return 0;
}

public Action Command_ClanKick(int client, int args)
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
        ReplyToCommand(client, "[Clans] Usage: sm_clankick <target>");
        return Plugin_Handled;
    }

    char actorSteam[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, actorSteam, sizeof(actorSteam)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return Plugin_Handled;
    }

    char query[64];
    GetCmdArgString(query, sizeof(query));
    StripQuotes(query);
    TrimString(query);

    if (!query[0])
    {
        ReplyToCommand(client, "[Clans] Usage: sm_clankick <target>");
        return Plugin_Handled;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(actorSteam);
    pack.WriteString(query);

    GetClanByPlayer(actorSteam, SQL_OnClanKickCommandContext, pack);
    return Plugin_Handled;
}

public void SQL_OnClanKickCommandContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char actorSteam[STEAMID64_MAXLEN];
    char query[64];
    pack.ReadString(actorSteam, sizeof(actorSteam));
    pack.ReadString(query, sizeof(query));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick command context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    ClanRank actorRank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can kick members.");
        return;
    }

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(view_as<int>(actorRank));
    next.WriteString(actorSteam);
    next.WriteString(query);

    GetClanMembers(clanId, SQL_OnClanKickCommandMembers, next);
}

public void SQL_OnClanKickCommandMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    ClanRank actorRank = view_as<ClanRank>(pack.ReadCell());
    char actorSteam[STEAMID64_MAXLEN];
    char query[64];
    pack.ReadString(actorSteam, sizeof(actorSteam));
    pack.ReadString(query, sizeof(query));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick command member query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load kick targets.");
        return;
    }

    char exactSteam[STEAMID64_MAXLEN];
    char partialSteam[STEAMID64_MAXLEN];
    exactSteam[0] = '\0';
    partialSteam[0] = '\0';

    int exactCount = 0;
    int partialCount = 0;

    while (results != null && results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        if (StrEqual(memberSteam, actorSteam, false))
        {
            continue;
        }

        ClanRank targetRank = view_as<ClanRank>(results.FetchInt(1));
        if (targetRank >= ClanRank_Owner)
        {
            continue;
        }

        if (actorRank == ClanRank_Officer && targetRank >= ClanRank_Officer)
        {
            continue;
        }

        char targetName[MAX_NAME_LENGTH];
        ResolvePlayerDisplayName(memberSteam, targetName, sizeof(targetName));

        if (StrEqual(memberSteam, query, false) || StrEqual(targetName, query, false))
        {
            exactCount++;
            if (exactCount == 1)
            {
                strcopy(exactSteam, sizeof(exactSteam), memberSteam);
            }
            continue;
        }

        if (StrContains(memberSteam, query, false) != -1 || StrContains(targetName, query, false) != -1)
        {
            partialCount++;
            if (partialCount == 1)
            {
                strcopy(partialSteam, sizeof(partialSteam), memberSteam);
            }
        }
    }

    if (exactCount > 1 || (exactCount == 0 && partialCount > 1))
    {
        PrintToChat(client, "[Clans] Multiple clan members matched that query.");
        return;
    }

    if (exactCount == 1)
    {
        StartClanKickSteam64(client, exactSteam);
        return;
    }

    if (partialCount == 1)
    {
        StartClanKickSteam64(client, partialSteam);
        return;
    }

    PrintToChat(client, "[Clans] No clan member matched that query.");
}

public void SQL_OnClanKickActorContext(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    int actor = GetClientOfUserId(actorUserId);
    if (actor <= 0 || !IsClientInGame(actor))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick actor context failed: %s", error);
        PrintToChat(actor, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(actor, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    ClanRank actorRank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(actor, "[Clans] Only officers and owners can kick members.");
        return;
    }

    char escapedTarget[SQL_STEAMID64_MAXLEN];
    EscapeSql(targetSteam, escapedTarget, sizeof(escapedTarget));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT rank FROM clan_members WHERE clan_id = %d AND steamid64 = '%s' LIMIT 1",
        clanId,
        escapedTarget);

    DataPack next = new DataPack();
    next.WriteCell(actorUserId);
    next.WriteCell(targetUserId);
    next.WriteCell(clanId);
    next.WriteCell(view_as<int>(actorRank));
    next.WriteString(targetSteam);

    g_Database.Query(SQL_OnClanKickTargetValidate, query, next);
}

public void SQL_OnClanKickTargetValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    int clanId = pack.ReadCell();
    ClanRank actorRank = view_as<ClanRank>(pack.ReadCell());
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    int actor = GetClientOfUserId(actorUserId);
    if (actor <= 0 || !IsClientInGame(actor))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Kick target validation failed: %s", error);
        PrintToChat(actor, "[Clans] Failed to validate the kick target.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(actor, "[Clans] That player is not in your clan.");
        return;
    }

    ClanRank targetRank = view_as<ClanRank>(results.FetchInt(0));

    if (targetRank >= ClanRank_Owner)
    {
        PrintToChat(actor, "[Clans] You cannot kick the clan owner.");
        return;
    }

    if (actorRank == ClanRank_Officer && targetRank >= ClanRank_Officer)
    {
        PrintToChat(actor, "[Clans] Officers can only kick regular members.");
        return;
    }

    char escapedTarget[SQL_STEAMID64_MAXLEN];
    EscapeSql(targetSteam, escapedTarget, sizeof(escapedTarget));

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query),
        "DELETE FROM clan_sub_tags WHERE clan_id = %d AND steamid64 = '%s'",
        clanId,
        escapedTarget);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "DELETE FROM clan_members WHERE clan_id = %d AND steamid64 = '%s'",
        clanId,
        escapedTarget);
    txn.AddQuery(query);

    DataPack next = new DataPack();
    next.WriteCell(actorUserId);
    next.WriteCell(targetUserId);
    next.WriteCell(clanId);
    next.WriteString(targetSteam);

    g_Database.Execute(txn, SQL_OnClanKickSuccess, SQL_OnClanKickFailure, next);
}

public void SQL_OnClanKickSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    int targetUserId = pack.ReadCell();
    int clanId = pack.ReadCell();
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    if (targetSteam[0] != '\0')
    {
        SetClientClanIdBySteam64(targetSteam, 0);
    }
    RefreshConnectedClanTagsForClan(clanId);

    int actor = GetClientOfUserId(actorUserId);
    int target = GetClientOfUserId(targetUserId);
    if (target <= 0 || !IsClientInGame(target))
    {
        target = Kogasa_FindClientBySteamId64(targetSteam);
    }

    char targetName[MAX_NAME_LENGTH];
    ResolvePlayerDisplayName(targetSteam, targetName, sizeof(targetName));

    if (actor > 0 && IsClientInGame(actor))
    {
        PrintToChat(actor, "[Clans] You kicked %s from the clan.", targetName);
    }

    if (target > 0 && IsClientInGame(target))
    {
        PrintToChat(target, "[Clans] You were kicked from your clan.");
    }
}

public void SQL_OnClanKickFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int actorUserId = pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    int actor = GetClientOfUserId(actorUserId);
    if (actor > 0 && IsClientInGame(actor))
    {
        PrintToChat(actor, "[Clans] Failed to kick that player.");
    }

    LogError("[Clans] Kick transaction failed for %s (query %d): %s", targetSteam, failIndex, error);
}

