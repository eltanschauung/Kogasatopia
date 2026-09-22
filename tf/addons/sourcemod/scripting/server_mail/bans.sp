void ResetMailBanState(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_MailBanGeneration[client]++;
    g_MailBanLoaded[client] = false;
    g_MailBanned[client] = false;
    g_MailBanQueryPending[client] = false;
}
void ResetAllMailBanStates()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetMailBanState(client);
    }
}

void RefreshMailBanStateForAllClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsMailClient(client))
        {
            RequestMailBanState(client);
        }
    }
}

void RequestMailBanState(int client)
{
    if (!IsMailClient(client)
        || !g_MailDatabaseReady
        || g_MailDatabase == null
        || g_MailBanQueryPending[client])
    {
        return;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    char escapedSteam[(MAIL_STEAMID_MAX * 2) + 1];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name))
        || !EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        return;
    }

    int generation = ++g_MailBanGeneration[client];
    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT 1 FROM %s WHERE steamid64 = '%s' LIMIT 1",
        MAIL_BAN_TABLE,
        escapedSteam);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    pack.WriteCell(generation);
    pack.WriteString(steamId);
    g_MailBanQueryPending[client] = true;
    g_MailDatabase.Query(SQL_OnMailBanStateLoaded, query, pack);
}

public void SQL_OnMailBanStateLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    int generation = pack.ReadCell();
    char expectedSteam[MAIL_STEAMID_MAX];
    pack.ReadString(expectedSteam, sizeof(expectedSteam));
    delete pack;

    if (!IsMailClient(client) || generation != g_MailBanGeneration[client])
    {
        return;
    }

    char currentSteam[MAIL_STEAMID_MAX];
    char currentName[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, currentSteam, sizeof(currentSteam), currentName, sizeof(currentName))
        || !StrEqual(currentSteam, expectedSteam))
    {
        return;
    }

    g_MailBanQueryPending[client] = false;
    if (error[0] != '\0')
    {
        g_MailBanLoaded[client] = false;
        LogError("[server_mail] Failed to load a client's mail-ban state: %s", error);
        return;
    }

    g_MailBanned[client] = rows != null && rows.FetchRow();
    g_MailBanLoaded[client] = true;
}

bool CanClientUseMailCommands(int client, bool notify = true)
{
    if (!IsMailClient(client))
    {
        return false;
    }

    if (!g_MailBanLoaded[client])
    {
        RequestMailBanState(client);
        if (notify)
        {
            CPrintToChat(client, "%s Your mail access is still loading. Try again shortly.", MAIL_PREFIX);
        }
        return false;
    }

    if (g_MailBanned[client])
    {
        if (notify)
        {
            CPrintToChat(client, "%s You are banned from using mail commands.", MAIL_PREFIX);
        }
        return false;
    }

    return true;
}

public Action Command_MailBan(int client, int args)
{
    return HandleMailBanCommand(client, args, true);
}

public Action Command_MailUnban(int client, int args)
{
    return HandleMailBanCommand(client, args, false);
}

Action HandleMailBanCommand(int client, int args, bool ban)
{
    if (args != 1)
    {
        ReplyToCommand(client, "[Mail] Usage: sm_mail%s <target>", ban ? "ban" : "unban");
        return Plugin_Handled;
    }

    if (!g_MailDatabaseReady || g_MailDatabase == null)
    {
        ReplyToCommand(client, "[Mail] The mail database is temporarily unavailable.");
        return Plugin_Handled;
    }

    char targetArg[MAX_TARGET_LENGTH];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    int target = FindTarget(client, targetArg, true, false);
    if (target <= 0)
    {
        return Plugin_Handled;
    }

    if (g_MailBanQueryPending[target])
    {
        ReplyToCommand(client, "[Mail] That player's mail access is already being updated.");
        return Plugin_Handled;
    }

    char targetSteam[MAIL_STEAMID_MAX];
    char targetName[MAIL_NAME_MAX];
    char adminSteam[MAIL_STEAMID_MAX];
    char adminName[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(target, targetSteam, sizeof(targetSteam), targetName, sizeof(targetName))
        || !GetMailClientIdentity(client, adminSteam, sizeof(adminSteam), adminName, sizeof(adminName)))
    {
        ReplyToCommand(client, "[Mail] Could not resolve that player's identity.");
        return Plugin_Handled;
    }

    char escapedTarget[(MAIL_STEAMID_MAX * 2) + 1];
    char escapedAdmin[(MAIL_STEAMID_MAX * 2) + 1];
    char escapedAdminName[(MAIL_NAME_MAX * 2) + 1];
    if (!EscapeMailSql(targetSteam, escapedTarget, sizeof(escapedTarget))
        || !EscapeMailSql(adminSteam, escapedAdmin, sizeof(escapedAdmin))
        || !EscapeMailSql(adminName, escapedAdminName, sizeof(escapedAdminName)))
    {
        ReplyToCommand(client, "[Mail] Could not prepare the mail access update.");
        return Plugin_Handled;
    }

    char query[1024];
    if (ban)
    {
        FormatEx(query, sizeof(query),
            "REPLACE INTO %s (steamid64, banned_by_steamid64, banned_by_name, banned_at) "
            ... "VALUES ('%s', '%s', '%s', %d)",
            MAIL_BAN_TABLE,
            escapedTarget,
            escapedAdmin,
            escapedAdminName,
            GetTime());
    }
    else
    {
        FormatEx(query, sizeof(query),
            "DELETE FROM %s WHERE steamid64 = '%s'",
            MAIL_BAN_TABLE,
            escapedTarget);
    }

    int generation = ++g_MailBanGeneration[target];
    g_MailBanLoaded[target] = false;
    g_MailBanQueryPending[target] = true;
    ClearClientMailState(target);

    DataPack pack = new DataPack();
    pack.WriteCell(client == 0 ? 0 : GetClientUserId(client));
    pack.WriteCell(GetClientSerial(target));
    pack.WriteCell(generation);
    pack.WriteCell(ban);
    pack.WriteString(targetSteam);
    pack.WriteString(targetName);
    g_MailDatabase.Query(SQL_OnMailBanMutationComplete, query, pack);
    return Plugin_Handled;
}

public void SQL_OnMailBanMutationComplete(Database db, DBResultSet results,
    const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int adminUserId = pack.ReadCell();
    int target = GetClientFromSerial(pack.ReadCell());
    int generation = pack.ReadCell();
    bool ban = pack.ReadCell() != 0;
    char expectedSteam[MAIL_STEAMID_MAX];
    char targetName[MAIL_NAME_MAX];
    pack.ReadString(expectedSteam, sizeof(expectedSteam));
    pack.ReadString(targetName, sizeof(targetName));
    delete pack;

    int admin = adminUserId == 0 ? 0 : GetClientOfUserId(adminUserId);
    bool targetMatches = IsMailClient(target)
        && generation == g_MailBanGeneration[target];

    if (targetMatches)
    {
        char currentSteam[MAIL_STEAMID_MAX];
        char currentName[MAIL_NAME_MAX];
        targetMatches = GetMailClientIdentity(
                target,
                currentSteam,
                sizeof(currentSteam),
                currentName,
                sizeof(currentName))
            && StrEqual(currentSteam, expectedSteam);
    }

    if (error[0] != '\0')
    {
        LogError("[server_mail] Failed to update a client's mail-ban state: %s", error);
        ReplyToCommand(admin, "[Mail] Failed to %s %s.", ban ? "ban" : "unban", targetName);
        if (targetMatches)
        {
            ResetMailBanState(target);
            RequestMailBanState(target);
        }
        return;
    }

    if (targetMatches)
    {
        g_MailBanQueryPending[target] = false;
        g_MailBanLoaded[target] = true;
        g_MailBanned[target] = ban;
        if (ban)
        {
            CPrintToChat(target, "%s An admin banned you from using mail commands.", MAIL_PREFIX);
        }
        else
        {
            CPrintToChat(target, "%s An admin restored your access to mail commands.", MAIL_PREFIX);
        }
    }

    ReplyToCommand(admin, ban
        ? "[Mail] Banned %s from using mail commands."
        : "[Mail] Restored %s's access to mail commands.",
        targetName);

    if (target > 0)
    {
        if (ban)
        {
            LogAction(admin, target, "\"%L\" banned \"%L\" from mail commands.", admin, target);
        }
        else
        {
            LogAction(admin, target, "\"%L\" restored mail-command access for \"%L\".", admin, target);
        }
    }
}

