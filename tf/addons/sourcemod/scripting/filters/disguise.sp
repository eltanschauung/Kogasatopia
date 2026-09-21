void Filters_ClearDisguise(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_DisguiseActive[client] = false;
    g_DisguiseChatInProgress[client] = false;
    g_DisguiseTargetSteamId64[client][0] = 0;
    g_DisguiseDisplayName[client][0] = 0;
}

bool Filters_IsDisguiseChatCommand(const char[] text)
{
    char token[32];
    BreakString(text, token, sizeof(token));
    return StrEqual(token, "/disguise", false)
        || StrEqual(token, "/disguisereset", false);
}

public Action Command_DisguiseReset(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[Filters] This command must be used in game.");
        return Plugin_Handled;
    }

    Filters_ClearDisguise(client);
    ReplyToCommand(client, "[Filters] Chat disguise cleared.");
    return Plugin_Handled;
}

public Action Command_Disguise(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[Filters] This command must be used in game.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyToCommand(client, "[Filters] Usage: sm_disguise <name|steamid64>");
        return Plugin_Handled;
    }

    if (!Filters_DbAvailable())
    {
        ReplyToCommand(client, "[Filters] The name database is unavailable.");
        return Plugin_Handled;
    }

    char search[128];
    GetCmdArgString(search, sizeof(search));
    TrimString(search);
    StripQuotes(search);
    TrimString(search);
    if (!search[0])
    {
        ReplyToCommand(client, "[Filters] Usage: sm_disguise <name|steamid64>");
        return Plugin_Handled;
    }

    bool isSteamId = Kogasa_IsSteamId64(search);
    if (!isSteamId)
    {
        ToLowercase(search);
    }

    char escaped[256];
    if (!Db_Escape(g_hFiltersDb, search, escaped, sizeof(escaped), "filters"))
    {
        ReplyToCommand(client, "[Filters] Could not search the name database.");
        return Plugin_Handled;
    }

    char predicate[320];
    if (isSteamId)
    {
        FormatEx(predicate, sizeof(predicate), "sn.steamid64 = '%s'", escaped);
    }
    else
    {
        FormatEx(predicate, sizeof(predicate), "sn.last_name_lower = '%s'", escaped);
    }

    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT sn.steamid64, sn.last_name, COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
        ... "FROM filters_steam_names sn "
        ... "LEFT JOIN filters_namecolors nc ON nc.steamid = sn.steamid64 COLLATE utf8mb4_general_ci "
        ... "WHERE %s ORDER BY sn.updated_at DESC LIMIT 2",
        predicate);

    DBResultSet results = SQL_Query(g_hFiltersDb, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_hFiltersDb, error, sizeof(error));
        LogError("[Filters] Disguise name lookup failed: %s", error);
        ReplyToCommand(client, "[Filters] Could not search the name database.");
        return Plugin_Handled;
    }

    bool found = results.FetchRow();
    if (!found && !isSteamId)
    {
        delete results;
        FormatEx(predicate, sizeof(predicate), "LOCATE('%s', sn.last_name_lower) > 0", escaped);
        FormatEx(query, sizeof(query),
            "SELECT sn.steamid64, sn.last_name, COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
            ... "FROM filters_steam_names sn "
            ... "LEFT JOIN filters_namecolors nc ON nc.steamid = sn.steamid64 COLLATE utf8mb4_general_ci "
            ... "WHERE %s ORDER BY sn.updated_at DESC LIMIT 2",
            predicate);
        results = SQL_Query(g_hFiltersDb, query);
        if (results == null)
        {
            char error[256];
            SQL_GetError(g_hFiltersDb, error, sizeof(error));
            LogError("[Filters] Disguise partial-name lookup failed: %s", error);
            ReplyToCommand(client, "[Filters] Could not search the name database.");
            return Plugin_Handled;
        }
        found = results.FetchRow();
    }

    if (!found)
    {
        delete results;
        ReplyToCommand(client, "[Filters] No recorded player matches '%s'.", search);
        return Plugin_Handled;
    }

    char targetSteamId64[32];
    char targetName[128];
    char color[32];
    char pattern[NAME_PATTERN_MAX];
    results.FetchString(0, targetSteamId64, sizeof(targetSteamId64));
    results.FetchString(1, targetName, sizeof(targetName));
    results.FetchString(2, color, sizeof(color));
    results.FetchString(3, pattern, sizeof(pattern));
    bool ambiguous = results.FetchRow();
    delete results;

    if (ambiguous)
    {
        ReplyToCommand(client, "[Filters] Multiple players match '%s'; use a SteamID64.", search);
        return Plugin_Handled;
    }
    if (!Kogasa_IsSteamId64(targetSteamId64) || !targetName[0])
    {
        ReplyToCommand(client, "[Filters] That player has no usable recorded identity.");
        return Plugin_Handled;
    }

    char ownSteamId64[32];
    if (Kogasa_GetClientSteamId64(client, ownSteamId64, sizeof(ownSteamId64), true)
        && StrEqual(ownSteamId64, targetSteamId64))
    {
        ReplyToCommand(client, "[Filters] You are already that player.");
        return Plugin_Handled;
    }

    char steamId2[32];
    char prename[PRENAME_MAX_RENAME];
    steamId2[0] = 0;
    if (Kogasa_ConvertSteamId64ToSteam2(targetSteamId64, steamId2, sizeof(steamId2))
        && Prename_TryGetIdRule(targetSteamId64, steamId2, prename, sizeof(prename))
        && prename[0])
    {
        strcopy(targetName, sizeof(targetName), prename);
    }

    TrimString(color);
    TrimString(pattern);
    ToLowercase(color);
    ToLowercase(pattern);
    char renderedName[256];
    BuildRenderedStoredName(targetName, color, pattern, renderedName, sizeof(renderedName));
    if (!renderedName[0])
    {
        ReplyToCommand(client, "[Filters] Could not render that player's name.");
        return Plugin_Handled;
    }

    strcopy(g_DisguiseTargetSteamId64[client], sizeof(g_DisguiseTargetSteamId64[]), targetSteamId64);
    strcopy(g_DisguiseDisplayName[client], sizeof(g_DisguiseDisplayName[]), renderedName);
    g_DisguiseActive[client] = true;
    ReplyToCommand(client, "[Filters] Chat disguise set to %s. Use /disguisereset to clear it.", targetName);
    return Plugin_Handled;
}

void Filters_DisguiseMessageForReceiver(int receiver, int sender, const char[] message, char[] output, int maxlen)
{
    strcopy(output, maxlen, message);
    if (sender <= 0 || sender > MaxClients || !g_DisguiseActive[sender]
        || !g_DisguiseChatInProgress[sender] || !g_DisguiseDisplayName[sender][0])
    {
        return;
    }

    char receiverSteamId64[32];
    if (Kogasa_GetClientSteamId64(receiver, receiverSteamId64, sizeof(receiverSteamId64), true)
        && StrEqual(receiverSteamId64, g_DisguiseTargetSteamId64[sender]))
    {
        return;
    }

    char realDisplayName[384];
    BuildChatDisplayName(sender, realDisplayName, sizeof(realDisplayName));
    if (!realDisplayName[0])
    {
        return;
    }

    int position = StrContains(message, realDisplayName);
    int bodyStart = StrContains(message, " : ");
    if (position < 0 || (bodyStart >= 0 && position > bodyStart) || position >= maxlen)
    {
        return;
    }

    char prefix[MAX_MESSAGE_LENGTH];
    strcopy(prefix, sizeof(prefix), message);
    prefix[position] = 0;
    FormatEx(output, maxlen, "%s%s%s",
        prefix, g_DisguiseDisplayName[sender], message[position + strlen(realDisplayName)]);
}
