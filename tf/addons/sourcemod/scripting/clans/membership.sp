public Action Command_ClanCreate(int client, int args)
{
    if (client <= 0)
    {
        ReplyToCommand(client, "[Clans] This command can only be used by players.");
        return Plugin_Handled;
    }

    if (!IsClanGemStoreAvailable())
    {
        PrintToChat(client, "[Clans] Clan creation requires Gems.");
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

    IsPlayerInClan(steamid64, SQL_OnClanCreateInitialCheck, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanCreateInitialCheck(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Create initial check failed: %s", error);
        PrintToChat(client, "[Clans] Failed to check your clan state.");
        return;
    }

    if (results != null && results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are already in a clan.");
        return;
    }

    g_PromptState[client] = Prompt_ClanCreateName;
    PrintToChat(client, "[Clans] Type your clan name in chat. Type /cancel to abort.");
}

public void SQL_OnClanCreateValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
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
        LogError("[Clans] Create validation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate clan creation.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] Failed to validate clan creation.");
        return;
    }

    int inClan = results.FetchInt(0);
    int nameTaken = results.FetchInt(1);

    if (inClan > 0)
    {
        PrintToChat(client, "[Clans] You are already in a clan.");
        return;
    }

    if (nameTaken > 0)
    {
        PrintToChat(client, "[Clans] That clan name is already taken.");
        return;
    }

    if (!SpendClanGems(client, CLAN_CREATE_GEM_COST))
    {
        PrintToChat(client, "[Clans] You need %d Gems to create a clan.", CLAN_CREATE_GEM_COST);
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        GiveClanGems(client, CLAN_CREATE_GEM_COST);
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    CreateClan(steamid64, clanName, userId);
}

public void SQL_OnClanRenameValidate(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
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
        LogError("[Clans] Rename validation failed: %s", error);
        PrintToChat(client, "[Clans] Failed to validate the clan rename.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (view_as<ClanRank>(results.FetchInt(1)) < ClanRank_Owner)
    {
        PrintToChat(client, "[Clans] Only the clan owner can rename the clan.");
        return;
    }

    if (results.FetchInt(2) > 0)
    {
        PrintToChat(client, "[Clans] That clan name is already taken.");
        return;
    }

    int clanId = results.FetchInt(0);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteString(clanName);

    SetClanName(clanId, clanName, SQL_OnClanRenameSet, next);
}

public void SQLTxn_OnCreateClanSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char ownerSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(ownerSteam, sizeof(ownerSteam));
    delete pack;

    int clanId = 0;
    if (numQueries > 0)
    {
        clanId = results[0].InsertId;
    }

    if (ownerSteam[0] != '\0' && clanId > 0)
    {
        SetClientClanIdBySteam64(ownerSteam, clanId);
    }

    char ownerName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(ownerSteam, ownerName, sizeof(ownerName));
    if (clanId > 0)
    {
        AddClanHistoryEntry(clanId, "Clan created by %s", ownerName);
    }

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Clan '%s' created successfully. (ID %d)", clanName, clanId);
    }
}

public void SQL_OnClanRenameSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
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
        LogError("[Clans] Rename set failed: %s", error);

        if (StrContains(error, "Duplicate", false) != -1 || StrContains(error, "UNIQUE", false) != -1)
        {
            PrintToChat(client, "[Clans] That clan name is already taken.");
        }
        else
        {
            PrintToChat(client, "[Clans] Failed to rename the clan.");
        }
        return;
    }

    PrintToChat(client, "[Clans] Clan renamed to '%s'.", clanName);
}

public void SQLTxn_OnCreateClanFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char ownerSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(ownerSteam, sizeof(ownerSteam));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        GiveClanGems(client, CLAN_CREATE_GEM_COST);

        if (StrContains(error, "Duplicate", false) != -1 || StrContains(error, "UNIQUE", false) != -1)
        {
            PrintToChat(client, "[Clans] That clan name is already taken.");
        }
        else
        {
            PrintToChat(client, "[Clans] Failed to create clan '%s'.", clanName);
        }
    }

    LogError("[Clans] CreateClan transaction failed (query %d): %s", failIndex, error);
}

public Action Command_ClanLeave(int client, int args)
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

    GetClanByPlayer(steamid64, SQL_OnClanLeaveContext, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnClanLeaveContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Leave context failed: %s", error);
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    ClanRank rank = view_as<ClanRank>(results.FetchInt(ClanByPlayerCol_Rank));

    if (rank >= ClanRank_Owner)
    {
        g_PromptState[client] = Prompt_ClanLeaveConfirm;
        PrintToChat(client, "[Clans] You are the clan owner. Type /yes to delete the clan and refund %d Gems, or /cancel to abort.", CLAN_CREATE_GEM_COST);
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    char clanName[CLAN_NAME_MAXLEN + 1];
    results.FetchString(ClanByPlayerCol_Name, clanName, sizeof(clanName));

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query),
        "DELETE FROM clan_sub_tags WHERE clan_id = %d AND steamid64 = '%s'",
        clanId,
        escapedSteam);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "DELETE FROM clan_members WHERE clan_id = %d AND steamid64 = '%s'",
        clanId,
        escapedSteam);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(clanId);
    pack.WriteString(clanName);
    pack.WriteString(steamid64);

    g_Database.Execute(txn, SQL_OnClanLeaveSuccess, SQL_OnClanLeaveFailure, pack);
}

void StartOwnerDeleteClan(int client)
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

    GetClanByPlayer(steamid64, SQL_OnOwnerDeleteClanContext, GetClientUserId(client));
}

public void SQL_OnOwnerDeleteClanContext(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Owner delete context failed: %s", error);
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
        PrintToChat(client, "[Clans] You are no longer the clan owner.");
        return;
    }

    int clanId = results.FetchInt(ClanByPlayerCol_Id);
    DeleteClan(clanId, GetClientUserId(client), true);
}

public void SQL_OnClanLeaveSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
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

    if (steamid64[0] != '\0')
    {
        SetClientClanIdBySteam64(steamid64, 0);
    }
    RefreshConnectedClanTagsForClan(clanId);

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    PrintToChat(client, "[Clans] You left '%s'.", clanName);
}

public void SQL_OnClanLeaveFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    pack.ReadCell();
    char clanName[CLAN_NAME_MAXLEN + 1];
    char steamid64[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(steamid64, sizeof(steamid64));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Failed to leave your clan.");
    }

    LogError("[Clans] Leave clan transaction failed while leaving '%s' (query %d): %s", clanName, failIndex, error);
}

public void SQLTxn_OnDeleteClanSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    bool refundOwner = (pack.ReadCell() != 0);
    int clanId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        if (refundOwner)
        {
            GiveClanGems(client, CLAN_CREATE_GEM_COST);
        }

        PrintToChat(client, "[Clans] Clan %d deleted.", clanId);
    }

    ClearConnectedClanId(clanId);
}

public void SQLTxn_OnDeleteClanFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    pack.ReadCell();
    int clanId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Failed to delete clan %d.", clanId);
    }

    LogError("[Clans] DeleteClan transaction failed (query %d): %s", failIndex, error);
}

void StartClanInviteToTarget(int client, int target)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    if (target <= 0 || target > MaxClients || !IsClientInGame(target) || IsFakeClient(target))
    {
        PrintToChat(client, "[Clans] That player is not available.");
        return;
    }

    if (target == client)
    {
        PrintToChat(client, "[Clans] You cannot invite yourself.");
        return;
    }

    char inviterSteam[STEAMID64_MAXLEN];
    char targetSteam[STEAMID64_MAXLEN];

    if (!GetClientSteam64(client, inviterSteam, sizeof(inviterSteam)) || !GetClientSteam64(target, targetSteam, sizeof(targetSteam)))
    {
        PrintToChat(client, "[Clans] Failed to read a SteamID64.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(GetClientUserId(target));
    pack.WriteString(targetSteam);

    GetClanByPlayer(inviterSteam, SQL_OnClanInviteInviterContext, pack);
}

