public Action Command_FilterWhitelist(int client, int args)
{
    return Filters_RunTargetAdminCommand(client, args,
        "[Kogasa] Usage: sm_filterwhitelist <player>",
        "Filter whitelisted %s",
        FilterAdmin_FilterWhitelist);
}

public Action Command_UnFilterWhitelist(int client, int args)
{
    return Filters_RunTargetAdminCommand(client, args,
        "[Kogasa] Usage: sm_unfilterwhitelist <player>",
        "Removed filter whitelist from %s",
        FilterAdmin_UnFilterWhitelist);
}

void PerformFilterWhitelist(int client, int target)
{
    g_PlayerState[target].isFilterWhitelisted = true;
    SetClientCookie(target, g_hCookieFilterWhitelist, "1");
    LogAction(client, target, "\"%L\" filter whitelisted \"%L\"", client, target);
}

void PerformUnFilterWhitelist(int client, int target)
{
    g_PlayerState[target].isFilterWhitelisted = false;
    SetClientCookie(target, g_hCookieFilterWhitelist, "0");
    LogAction(client, target, "\"%L\" removed filter whitelist from \"%L\"", client, target);
}

public Action Command_Listredlists(int client, int args)
{
    return Filters_RunStatusListCommand(client, FilterStatus_redlist);
}

public Action Command_FiltersHelp(int client, int args)
{
    return Filters_RunFiltersHelpCommand(client);
}

public Action Command_FiltersDebug(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    Filters_UpdateExternalStats(client);

    int rapes = g_PlayerState[client].rapesGiven;
    int kills = g_PlayerState[client].whaleKills;
    char redlisted[4];
    if (g_PlayerState[client].isredlisted)
    {
        strcopy(redlisted, sizeof(redlisted), "yes");
    }
    else
    {
        strcopy(redlisted, sizeof(redlisted), "no");
    }
    char over50[4];
    if (kills > 50)
    {
        strcopy(over50, sizeof(over50), "yes");
    }
    else
    {
        strcopy(over50, sizeof(over50), "no");
    }

    CPrintToChat(client, "{default}[SM] Rapes sent: %d | WhaleTracker kills: %d | Kills > 50: %s | Redlisted: %s", rapes, kills, over50, redlisted);

    if (!g_PlayerState[client].hugsStatsLoaded || !g_PlayerState[client].whaleStatsLoaded)
    {
        CPrintToChat(client, "{default}[SM] Stats are still loading; values may be 0.");
    }

    return Plugin_Handled;
}

// ==================== redlist COMMANDS ====================

public Action Command_redlist(int client, int args)
{
    return Filters_RunTargetAdminCommand(client, args,
        "[Kogasa] Usage: sm_redlist <player>",
        "redlisted %s",
        FilterAdmin_redlist);
}

public Action Command_Unredlist(int client, int args)
{
    return Filters_RunTargetAdminCommand(client, args,
        "[Kogasa] Usage: sm_unredlist <player>",
        "Removed redlist from %s",
        FilterAdmin_Unredlist);
}

void Performredlist(int client, int target)
{
    g_PlayerState[target].isredlisted = true;
    SetClientCookie(target, g_hCookieredlist, "1");
    LogAction(client, target, "\"%L\" redlisted \"%L\"", client, target);
    Filters_UpdateVoiceOverrides();
}

void PerformUnredlist(int client, int target)
{
    g_PlayerState[target].isredlisted = false;
    SetClientCookie(target, g_hCookieredlist, "0");
    LogAction(client, target, "\"%L\" removed redlist from \"%L\"", client, target);
    Filters_UpdateVoiceOverrides();
}

void CPrintToChatTeam(int team, int sender, const char[] message, const char[] senderMessage = "")
{
    char prefixed[256];
    bool prefixedReady = false;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }
        if (!Filters_ShouldReceiveChat(client, sender))
        {
            continue;
        }

        if (GetClientTeam(client) == team)
        {
            Filters_SendChatToReceiver(client, sender, message, senderMessage);
        }
        else if (Filters_CanSeeEnemyTeamChat(client))
        {
            if (!prefixedReady)
            {
                Format(prefixed, sizeof(prefixed), "t: %s", message);
                prefixedReady = true;
            }
            Filters_SendChatToReceiver(client, sender, prefixed);
        }
    }
}

public Action Listener_Colors(int client, const char[] command, int argc)
{
    return Command_Colors(client, argc);
}

public Action Command_Colors(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    static const char colorLines[][] =
    {
        "{aliceblue}aliceblue, {antiquewhite}antiquewhite, {aqua}aqua, {aquamarine}aquamarine, {azure}azure, {beige}beige, {bisque}bisque, {black}black, {blanchedalmond}blanchedalmond, {blue}blue",
        "{blueviolet}blueviolet, {brown}brown, {burlywood}burlywood, {cadetblue}cadetblue, {chartreuse}chartreuse, {chocolate}chocolate, {coral}coral, {cornflowerblue}cornflowerblue, {cornsilk}cornsilk, {crimson}crimson",
        "{cyan}cyan, {darkblue}darkblue, {darkcyan}darkcyan, {darkgoldenrod}darkgoldenrod, {darkgray}darkgray, {darkgrey}darkgrey, {darkgreen}darkgreen, {darkkhaki}darkkhaki, {darkmagenta}darkmagenta, {darkolivegreen}darkolivegreen",
        "{darkorange}darkorange, {darkorchid}darkorchid, {darkred}darkred, {darksalmon}darksalmon, {darkseagreen}darkseagreen, {darkslateblue}darkslateblue, {darkslategray}darkslategray, {darkslategrey}darkslategrey, {darkturquoise}darkturquoise, {darkviolet}darkviolet",
        "{deeppink}deeppink, {deepskyblue}deepskyblue, {dimgray}dimgray, {dimgrey}dimgrey, {dodgerblue}dodgerblue, {firebrick}firebrick, {floralwhite}floralwhite, {forestgreen}forestgreen, {fuchsia}fuchsia, {gainsboro}gainsboro",
        "{ghostwhite}ghostwhite, {gold}gold, {goldenrod}goldenrod, {gray}gray, {grey}grey, {green}green, {greenyellow}greenyellow, {honeydew}honeydew, {hotpink}hotpink, {indianred}indianred",
        "{indigo}indigo, {ivory}ivory, {khaki}khaki, {lavender}lavender, {lavenderblush}lavenderblush, {lawngreen}lawngreen, {lemonchiffon}lemonchiffon, {lightblue}lightblue, {lightcoral}lightcoral, {lightcyan}lightcyan",
        "{lightgoldenrodyellow}lightgoldenrodyellow, {lightgray}lightgray, {lightgrey}lightgrey, {lightgreen}lightgreen, {lightpink}lightpink, {lightsalmon}lightsalmon, {lightseagreen}lightseagreen, {lightskyblue}lightskyblue, {lightslategray}lightslategray, {lightslategrey}lightslategrey",
        "{lightsteelblue}lightsteelblue, {lightyellow}lightyellow, {lime}lime, {limegreen}limegreen, {linen}linen, {magenta}magenta, {maroon}maroon, {mediumaquamarine}mediumaquamarine, {mediumblue}mediumblue, {mediumorchid}mediumorchid",
        "{mediumpurple}mediumpurple, {mediumseagreen}mediumseagreen, {mediumslateblue}mediumslateblue, {mediumspringgreen}mediumspringgreen, {mediumturquoise}mediumturquoise, {mediumvioletred}mediumvioletred, {midnightblue}midnightblue, {mintcream}mintcream, {mistyrose}mistyrose, {moccasin}moccasin",
        "{navajowhite}navajowhite, {navy}navy, {oldlace}oldlace, {olive}olive, {olivedrab}olivedrab, {orange}orange, {orangered}orangered, {orchid}orchid, {palegoldenrod}palegoldenrod, {palegreen}palegreen",
        "{paleturquoise}paleturquoise, {palevioletred}palevioletred, {papayawhip}papayawhip, {peachpuff}peachpuff, {peru}peru, {pink}pink, {plum}plum, {powderblue}powderblue, {purple}purple, {red}red",
        "{rosybrown}rosybrown, {royalblue}royalblue, {saddlebrown}saddlebrown, {salmon}salmon, {sandybrown}sandybrown, {seagreen}seagreen, {seashell}seashell, {sienna}sienna, {silver}silver, {skyblue}skyblue",
        "{slateblue}slateblue, {slategray}slategray, {slategrey}slategrey, {snow}snow, {springgreen}springgreen, {steelblue}steelblue, {tan}tan, {teal}teal, {thistle}thistle, {tomato}tomato",
        "{turquoise}turquoise, {violet}violet, {wheat}wheat, {white}white, {whitesmoke}whitesmoke, {yellow}yellow, {yellowgreen}yellowgreen"
    };

    for (int i = 0; i < sizeof(colorLines); i++)
    {
        CPrintToChat(client, "%s", colorLines[i]);
    }
    CPrintToChat(client, "{default}[Filters] Store owners can use {gold}!america{default}, {gold}!mapflag{default}, {gold}!trans{default}, or {gold}!rainbow{default} for preset patterns.");
    CPrintToChat(client, "{default}[Filters] Gradient access owners can use {gold}!gradient <color1> <color2>{default} or {gold}!hue <color1> <color2>{default}.");

    return Plugin_Handled;
}

bool CheckCommands(const char[] sArgs)
{
    // Allow any message starting with !
    if (strncmp(sArgs, "!", 1) == 0) {
        return true;
    }
    
    // Allow any message containing %
    if (StrContains(sArgs, "%", false) != -1) {
        return true;
    }
    
    // Check against allowed commands list from config
    for (int i = 0; i < g_AllowedCommandsCount; i++) {
        if (StrEqual(sArgs, g_AllowedCommands[i], false)) {
            return true;
        }
    }
    return false;
}

bool CheckBlacklistedTerms(const char[] sArgs)
{
    if (g_hFiltersEnabled != null && !g_hFiltersEnabled.BoolValue)
    {
        return false;
    }

    if (g_hBlacklistMinLen != null && strlen(sArgs) < g_hBlacklistMinLen.IntValue)
    {
        return false;
    }

    for (int i = 0; i < g_BlacklistCount; i++)
    {
        // skip empty entries
        if (g_BlacklistWords[i][0] == '\0')
            continue;

        if (StrContains(sArgs, g_BlacklistWords[i], false) != -1)
        {
            PrintToServer("Blacklisted term: %s", g_BlacklistWords[i]);
            return true;
        }
    }

    for (int i = 0; i < g_Blacklist50Count; i++)
    {
        if (g_BlacklistWords50[i][0] == '\0')
            continue;

        if (StrContains(sArgs, g_BlacklistWords50[i], false) != -1)
        {
            if (GetRandomInt(0, 1) == 1)
            {
                PrintToServer("Blacklisted term (50%%): %s", g_BlacklistWords50[i]);
                return true;
            }
            return false;
        }
    }

    return false;
}
void Filters_AnnouncePlayerJoin(const char[] name)
{
    char serverName[128];
    Filters_GetServerName(serverName, sizeof(serverName));
    if (serverName[0])
    {
        Filters_InsertSystemMessage(true, false, "{gold}[Server]{default}: {cornflowerblue}%s{default} connected to {gold}[%s]{default}.", name, serverName);
    }
    else
    {
        Filters_InsertSystemMessage(true, false, "{gold}[Server]{default}: {cornflowerblue}%s{default} connected to the server.", name);
    }
}

void Filters_AnnouncePlayerLeave(const char[] name)
{
    char serverName[128];
    Filters_GetServerName(serverName, sizeof(serverName));
    if (serverName[0])
    {
        Filters_InsertSystemMessage(true, false, "{gold}[Server]{default}: {cornflowerblue}%s{default} disconnected from {gold}[%s]{default}.", name, serverName);
    }
    else
    {
        Filters_InsertSystemMessage(true, false, "{gold}[Server]{default}: {cornflowerblue}%s{default} disconnected from the server.", name);
    }
}

static void Filters_GetServerName(char[] buffer, int maxlen)
{
    if (!g_sServerName[0])
    {
        RefreshServerHostname();
    }
    strcopy(buffer, maxlen, g_sServerName);
}

void Filters_RecordSteamName(int client)
{
    if (!Filters_DbAvailable() || !Filters_IsRealClientInGame(client))
    {
        return;
    }

    char steamId64[32];
    if (!GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64)) || steamId64[0] == '\0')
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    TrimString(name);
    if (name[0] == '\0')
    {
        return;
    }

    char lowerName[128];
    strcopy(lowerName, sizeof(lowerName), name);
    Prename_ToLowercaseInPlace(lowerName, sizeof(lowerName));

    char escapedSteam[64];
    char escapedName[256];
    char escapedLower[256];
    Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters");
    Db_Escape(g_hFiltersDb, name, escapedName, sizeof(escapedName), "filters");
    Db_Escape(g_hFiltersDb, lowerName, escapedLower, sizeof(escapedLower), "filters");

    char query[768];
    Format(query, sizeof(query),
        "INSERT INTO filters_steam_names (steamid64, last_name, last_name_lower, updated_at) "
        ... "VALUES ('%s', '%s', '%s', %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "last_name = VALUES(last_name), "
        ... "last_name_lower = VALUES(last_name_lower), "
        ... "updated_at = VALUES(updated_at)",
        escapedSteam,
        escapedName,
        escapedLower,
        GetTime());
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

bool Filters_QueryLastRecordedSteamName(const char[] steamId64, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (!Filters_DbAvailable() || steamId64[0] == '\0')
    {
        return false;
    }

    char escapedSteam[64];
    Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters");

    char query[256];
    Format(query, sizeof(query),
        "SELECT last_name FROM filters_steam_names WHERE steamid64 = '%s' LIMIT 1",
        escapedSteam);

    DBResultSet results = SQL_Query(g_hFiltersDb, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_hFiltersDb, error, sizeof(error));
        LogError("[Filters] Last recorded Steam name query failed: %s", error);
        return false;
    }

    bool found = false;
    if (results.FetchRow())
    {
        results.FetchString(0, buffer, maxlen);
        TrimString(buffer);
        found = (buffer[0] != '\0');
    }

    delete results;
    return found;
}

// ==================== PRENAME (MERGED) ====================

