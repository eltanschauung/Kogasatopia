void SaveNamePreferencesToDb(int client)
{
    if (!g_bDbReady || g_hFiltersDb == null || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId64[32];
    if (!Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true))
    {
        return;
    }

    char escapedSteam[64];
    char escapedColor[64];
    char escapedPattern[(NAME_PATTERN_MAX * 2) + 1];
    Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters");
    Db_Escape(g_hFiltersDb, g_NameColors[client], escapedColor, sizeof(escapedColor), "filters");
    Db_Escape(g_hFiltersDb, g_NamePatterns[client], escapedPattern, sizeof(escapedPattern), "filters");

    char query[512];
    Format(query, sizeof(query),
        "REPLACE INTO filters_namecolors (steamid, color, pattern, updated_at) VALUES ('%s', '%s', '%s', %d)",
        escapedSteam, escapedColor, escapedPattern, GetTime());
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

void LoadNamePreferencesFromDb(int client)
{
    g_NameColors[client][0] = '\0';
    g_NamePatterns[client][0] = '\0';

    if (!g_bDbReady || g_hFiltersDb == null || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId64[32];
    if (!Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true))
    {
        return;
    }

    char escapedSteam[64];
    Db_Escape(g_hFiltersDb, steamId64, escapedSteam, sizeof(escapedSteam), "filters");

    char query[256];
    Format(query, sizeof(query), "SELECT color, pattern FROM filters_namecolors WHERE steamid = '%s' LIMIT 1", escapedSteam);
    g_hFiltersDb.Query(Filters_LoadNamePreferencesCallback, query, GetClientUserId(client));
}

public void Filters_LoadNamePreferencesCallback(Database db, DBResultSet results, const char[] error, any userId)
{
    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[Filters] Failed to load name preferences: %s", error);
        return;
    }

    if (results == null || !results.FetchRow())
    {
        g_NameColors[client][0] = '\0';
        g_NamePatterns[client][0] = '\0';
        return;
    }

    char dbColor[32];
    char dbPattern[NAME_PATTERN_MAX];
    results.FetchString(0, dbColor, sizeof(dbColor));
    results.FetchString(1, dbPattern, sizeof(dbPattern));
    TrimString(dbColor);
    TrimString(dbPattern);
    ToLowercase(dbColor);
    ToLowercase(dbPattern);

    g_NameColors[client][0] = '\0';
    g_NamePatterns[client][0] = '\0';

    bool normalize = false;

    if (dbColor[0])
    {
        if (CColorExists(dbColor))
        {
            strcopy(g_NameColors[client], sizeof(g_NameColors[]), dbColor);
        }
        else
        {
            PrintToServer("[FILTERS] %N had invalid DB name color '%s', resetting to team color", client, dbColor);
            normalize = true;
        }
    }

    if (dbPattern[0])
    {
        if (IsValidNamePattern(dbPattern))
        {
            strcopy(g_NamePatterns[client], sizeof(g_NamePatterns[]), dbPattern);
        }
        else
        {
            PrintToServer("[FILTERS] %N had invalid DB name pattern '%s', clearing it", client, dbPattern);
            normalize = true;
        }
    }

    if (normalize)
    {
        SaveNamePreferencesToDb(client);
    }
}

// Process client cookies on connect/cache
void ProcessCookies(int client)
{
    if (!Filters_IsClientIndex(client) || !AreClientCookiesCached(client))
    {
        return;
    }

    if (g_PlayerState[client].cookiesProcessed)
    {
        return;
    }

    g_PlayerState[client].cookiesProcessed = true;

    char cookie[32];

    GetClientCookie(client, g_hCookieMuteArchivedSpeakers, cookie, sizeof(cookie));
    g_bMuteArchivedSpeakers[client] = StrEqual(cookie, "1");

    Filters_RefreshAdminDbStatus(client);

    // Check if client has forced redlist/filter status from config.
    char steamid[32];
    if (Kogasa_GetClientSteam2(client, steamid, sizeof(steamid), true))
    {
        for (int i = 0; i < g_ForcedStatusCount; i++)
        {
            if (StrEqual(steamid, g_ForcedStatusSteamIDs[i]))
            {
                if (StrEqual(g_ForcedStatusTypes[i], "redlist"))
                {
                    PrintToServer("[FILTERS] %N is force redlisted (from config)", client);
                    g_PlayerState[client].isredlisted = true;
                    SetClientCookie(client, g_hCookieredlist, "1");
                    return;
                }
                else if (StrEqual(g_ForcedStatusTypes[i], "filter_whitelist"))
                {
                    PrintToServer("[FILTERS] %N is force filter whitelisted (from config)", client);
                    g_PlayerState[client].isFilterWhitelisted = true;
                    return;
                }
            }
        }
    }
    
    // Process filters-owned cookies normally if no forced status.
    GetClientCookie(client, g_hCookieFilterWhitelist, cookie, sizeof(cookie));
    if (StrEqual(cookie, "1"))
    {
        PrintToServer("[FILTERS] %N is filter whitelisted", client);
        g_PlayerState[client].isFilterWhitelisted = true;
    }
    else
    {
        g_PlayerState[client].isFilterWhitelisted = false;
    }
    
    GetClientCookie(client, g_hCookieredlist, cookie, sizeof(cookie));
    if (StrEqual(cookie, "1"))
    {
        PrintToServer("[FILTERS] %N is redlisted", client);
        g_PlayerState[client].isredlisted = true;
    }
    else
    {
        g_PlayerState[client].isredlisted = false;
    }

}

int Filters_GetAdminsDbLevel(int client)
{
    if (GetFeatureStatus(FeatureType_Native, "AdminsDB_GetClientWhitelistLevel") != FeatureStatus_Available)
    {
        return 0;
    }

    return AdminsDB_GetClientWhitelistLevel(client);
}

bool Filters_CanSeeEnemyTeamChat(int client)
{
    return Filters_PChatEnabled() && Filters_GetAdminsDbLevel(client) >= 3;
}

void Filters_RefreshAdminDbStatus(int client)
{
    if (!Filters_IsRealClientInGame(client))
    {
        return;
    }

    int level = Filters_GetAdminsDbLevel(client);
    g_PlayerState[client].isWhitelisted = level >= 2;
    g_PlayerState[client].isBlacklisted = level < 0;
}

static void Filters_StartAutoRedlistCheck(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (g_hFiltersDb == null || !g_bDbReady)
    {
        return;
    }

    char steamId64[32];
    if (Kogasa_GetClientSteamId64(client, steamId64, sizeof(steamId64), true))
    {
        char query[256];
        Format(query, sizeof(query), "SELECT kills FROM whaletracker WHERE steamid = '%s' LIMIT 1", steamId64);
        g_hFiltersDb.Query(Filters_AutoRedlistKillsCallback, query, GetClientUserId(client));
    }

    char steamId2[32];
    if (Kogasa_GetClientSteam2(client, steamId2, sizeof(steamId2), true))
    {
        char query[256];
        Format(query, sizeof(query), "SELECT rapes_given FROM hugs_stats WHERE steamid = '%s' LIMIT 1", steamId2);
        g_hFiltersDb.Query(Filters_AutoRedlistRapesCallback, query, GetClientUserId(client));
    }
}

static bool Filters_IsForcedRedlist(int client)
{
    char steamid[32];
    if (!Kogasa_GetClientSteam2(client, steamid, sizeof(steamid), true))
    {
        return false;
    }

    for (int i = 0; i < g_ForcedStatusCount; i++)
    {
        if (StrEqual(steamid, g_ForcedStatusSteamIDs[i]) && StrEqual(g_ForcedStatusTypes[i], "redlist"))
        {
            return true;
        }
    }

    return false;
}

static bool Filters_IsAdminClient(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return false;
    }

    return (GetUserFlagBits(client) != 0);
}

static void Filters_EvaluateAutoRedlist(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (g_PlayerState[client].isWhitelisted)
    {
        return;
    }

    if (Filters_IsAdminClient(client) && !Filters_IsForcedRedlist(client))
    {
        if (g_PlayerState[client].isredlisted)
        {
            PerformUnredlist(0, client);
        }
        return;
    }

    bool hasRapes = g_AutoRedlistGotRapes[client];

    if (!hasRapes)
    {
        return;
    }

    int rapes = g_AutoRedlistRapes[client];
    bool belowThreshold = rapes < REDLIST_RAPES_THRESHOLD;

    if (!g_PlayerState[client].isredlisted)
    {
        if (belowThreshold)
        {
            Performredlist(0, client);
        }
        return;
    }

    if (!belowThreshold && !Filters_IsForcedRedlist(client))
    {
        PerformUnredlist(0, client);
    }
}

public void Filters_AutoRedlistKillsCallback(Database db, DBResultSet results, const char[] error, any userId)
{
    if (error[0])
    {
        LogError("[Filters] Failed to query WhaleTracker kills: %s", error);
        return;
    }

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    int kills = 0;
    if (results != null && results.FetchRow())
    {
        kills = results.FetchInt(0);
    }

    g_AutoRedlistKills[client] = kills;
    g_AutoRedlistGotKills[client] = true;
    Filters_EvaluateAutoRedlist(client);
}

public void Filters_AutoRedlistRapesCallback(Database db, DBResultSet results, const char[] error, any userId)
{
    if (error[0])
    {
        LogError("[Filters] Failed to query hugs rapes: %s", error);
        return;
    }

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    int rapes = 0;
    if (results != null && results.FetchRow())
    {
        rapes = results.FetchInt(0);
    }

    g_AutoRedlistRapes[client] = rapes;
    g_AutoRedlistGotRapes[client] = true;
    Filters_EvaluateAutoRedlist(client);
}

public void OnClientPostAdminCheck(int client)
{
    if (AreClientCookiesCached(client) && !g_PlayerState[client].cookiesProcessed)
    {
        ProcessCookies(client);
        Filters_UpdateVoiceOverrides();
    }

    if (Filters_IsRealClientInGame(client))
    {
        Filters_StartAutoRedlistCheck(client);
        LoadNamePreferencesFromDb(client);
        Filters_RecordSteamName(client);
        Prename_Apply(client);
        Filters_AnnounceClientJoin(client);
    }

    Filters_UpdateExternalStats(client);
}

public void OnClientCookiesCached(int client)
{
    if (!g_PlayerState[client].cookiesProcessed)
    {
        ProcessCookies(client);
    }
    Filters_UpdateVoiceOverrides();
    Filters_UpdateExternalStats(client);
    LoadNamePreferencesFromDb(client);
}

public void Filters_OnFilterModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    Filters_UpdateVoiceOverrides();
}

public void Filters_OnRedlistChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    Filters_UpdateVoiceOverrides();
}

public void Filters_OnMuteDeafenChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    Filters_RefreshMuteDeafenState();
}

public void Filters_OnParseeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (StringToInt(oldValue) == 0 && StringToInt(newValue) != 0)
    {
        Filters_RefreshArchivedMessageCount(ArchivedSpeaker_Parsee);
    }
}

public void Filters_OnMemomanChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (StringToInt(oldValue) != 0 && StringToInt(newValue) == 0)
    {
        Filters_PrintToChatAll(
            "{blue}Memoman{default}: BRU H\n{gold}[Server]{default} Memoman has been disabled!",
            true);
    }
}

public void OnClientPutInServer(int client)
{
    g_bMuteArchivedSpeakers[client] = false;
    Filters_ResetArchivedMessageCooldowns(client);
    Filters_ResetExternalStats(client);
}

public void OnClientDisconnect(int client)
{
    g_bMuteArchivedSpeakers[client] = false;
    g_TidyChatSuppressNextTeamAlert[client] = false;
    Filters_ResetArchivedMessageCooldowns(client);
    Filters_ClearClientState(client);
    Filters_ResetExternalStats(client);
    g_MuteDeafened[client] = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_VoiceBlocked[client][i] = false;
        g_VoiceBlocked[i][client] = false;
    }
    Filters_AnnouncePlayerEvent(client, false);
}

public void OnPluginEnd()
{
    Filters_StopOutboxTimer();
    if (g_hMuteDeafenTimer != null)
    {
        delete g_hMuteDeafenTimer;
        g_hMuteDeafenTimer = null;
    }

    for (int receiver = 1; receiver <= MaxClients; receiver++)
    {
        for (int sender = 1; sender <= MaxClients; sender++)
        {
            if (g_VoiceBlocked[receiver][sender])
            {
                SetListenOverride(receiver, sender, Listen_Default);
                g_VoiceBlocked[receiver][sender] = false;
            }
        }
    }

    g_ConnectQueueTimer = null;
    g_hFiltersDbReconnectTimer = null;

    if (g_ConnectQueue != null)
    {
        delete g_ConnectQueue;
        g_ConnectQueue = null;
    }

    if (g_WebNameColors != null)
    {
        delete g_WebNameColors;
        g_WebNameColors = null;
    }

    Db_Close(g_hFiltersDb, g_bDbReady);

    if (g_PrenameIdRules != null)
    {
        delete g_PrenameIdRules;
        g_PrenameIdRules = null;
    }
    if (g_PrenameOutputMap != null)
    {
        delete g_PrenameOutputMap;
        g_PrenameOutputMap = null;
    }
}

public any Native_Filters_IsRedlisted(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return false;
    }

    return g_PlayerState[client].isredlisted;
}

public any Native_Filters_GetChatName(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int maxlen = GetNativeCell(3);

    char buffer[256];
    buffer[0] = '\0';

    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        BuildRenderedClientName(client, buffer, sizeof(buffer));
    }

    SetNativeString(2, buffer, maxlen, true);
    return 1;
}

public any Native_Filters_GetSteamIdColorTag(Handle plugin, int numParams)
{
    char steamId[32];
    GetNativeString(1, steamId, sizeof(steamId));

    int maxlen = GetNativeCell(3);
    char buffer[32];
    buffer[0] = '\0';

    int client = 0;
    if (maxlen > 0 && Filters_FindClientBySteamId64(steamId, client))
    {
        Filters_GetClientColorToken(client, buffer, sizeof(buffer));
    }

    SetNativeString(2, buffer, maxlen, true);
    return (buffer[0] != '\0');
}

public any Native_Filters_GetSteamIdChatName(Handle plugin, int numParams)
{
    char steamId64[32];
    char fallbackName[128];
    GetNativeString(1, steamId64, sizeof(steamId64));
    GetNativeString(2, fallbackName, sizeof(fallbackName));
    int maxlen = GetNativeCell(4);

    char renderedName[256];
    renderedName[0] = '\0';
    int client = 0;
    if (maxlen > 0 && Filters_FindClientBySteamId64(steamId64, client))
    {
        BuildRenderedClientName(client, renderedName, sizeof(renderedName));
    }
    else if (maxlen > 0 && Filters_DbAvailable() && Kogasa_IsSteamId64(steamId64))
    {
        char steamId2[32];
        char escapedSteam64[64];
        char escapedSteam2[64];
        char escapedFallback[256];
        if (Kogasa_ConvertSteamId64ToSteam2(steamId64, steamId2, sizeof(steamId2))
            && Db_Escape(g_hFiltersDb, steamId64, escapedSteam64, sizeof(escapedSteam64), "filters")
            && Db_Escape(g_hFiltersDb, steamId2, escapedSteam2, sizeof(escapedSteam2), "filters")
            && Db_Escape(g_hFiltersDb, fallbackName, escapedFallback, sizeof(escapedFallback), "filters"))
        {
            char query[1024];
            FormatEx(query, sizeof(query),
                "SELECT COALESCE((SELECT newname FROM prename_rules "
                ... "WHERE pattern IN ('%s', '%s') ORDER BY (pattern = '%s') DESC LIMIT 1), "
                ... "NULLIF(sn.last_name, ''), '%s'), COALESCE(nc.color, ''), COALESCE(nc.pattern, '') "
                ... "FROM (SELECT 1) seed "
                ... "LEFT JOIN filters_steam_names sn ON sn.steamid64 = '%s' "
                ... "LEFT JOIN filters_namecolors nc ON nc.steamid = '%s' LIMIT 1",
                escapedSteam64,
                escapedSteam2,
                escapedSteam64,
                escapedFallback,
                escapedSteam64,
                escapedSteam64);

            DBResultSet results = SQL_Query(g_hFiltersDb, query);
            if (results != null && results.FetchRow())
            {
                char displayName[128];
                char color[32];
                char pattern[NAME_PATTERN_MAX];
                results.FetchString(0, displayName, sizeof(displayName));
                results.FetchString(1, color, sizeof(color));
                results.FetchString(2, pattern, sizeof(pattern));
                TrimString(displayName);
                TrimString(color);
                TrimString(pattern);
                ToLowercase(color);
                ToLowercase(pattern);
                BuildRenderedStoredName(displayName, color, pattern, renderedName, sizeof(renderedName));
            }
            delete results;
        }
    }

    SetNativeString(3, renderedName, maxlen, true);
    return renderedName[0] != '\0';
}

public any Native_Filters_GetLastRecordedSteamName(Handle plugin, int numParams)
{
    char steamId64[32];
    GetNativeString(1, steamId64, sizeof(steamId64));

    int maxlen = GetNativeCell(3);
    if (maxlen <= 0)
    {
        return false;
    }

    char buffer[128];
    buffer[0] = '\0';

    if (steamId64[0] != '\0' && Filters_QueryLastRecordedSteamName(steamId64, buffer, sizeof(buffer)))
    {
        SetNativeString(2, buffer, maxlen, true);
        return true;
    }

    SetNativeString(2, "", maxlen, true);
    return false;
}

// ==================== FILTER WHITELIST COMMANDS ====================

