bool Filters_DebugEnabled()
{
    return g_hChatDebug != null && g_hChatDebug.BoolValue;
}

bool Filters_RedlistEnabled()
{
    return g_hRedlistEnabled != null && g_hRedlistEnabled.BoolValue;
}

bool Filters_PChatEnabled()
{
    return g_hPChat == null || g_hPChat.BoolValue;
}

bool Filters_MuteDeafenEnabled()
{
    return g_hMuteDeafenEnabled != null && g_hMuteDeafenEnabled.BoolValue;
}

bool Filters_IsClientGagged(int client)
{
    return Filters_IsClientIndex(client) && IsClientConnected(client)
        && (BaseComm_IsClientGagged(client)
            || (Filters_MuteDeafenEnabled() && g_MuteDeafened[client]));
}

int Filters_GetFilterMode()
{
    if (g_sChatMode2 == INVALID_HANDLE)
    {
        return 0;
    }
    int mode = GetConVarInt(g_sChatMode2);
    return mode < 0 ? 0 : (mode > 2 ? 2 : mode);
}

bool Filters_IsCordModeEnabled()
{
    return Filters_GetFilterMode() != 0;
}

bool Filters_CordModeWhitelistedCanReceiveBlacklisted()
{
    return Filters_GetFilterMode() != 0;
}

bool Filters_CordModeBlacklistedCanReceiveWhitelisted()
{
    return Filters_GetFilterMode() == 1;
}

void Filters_LogDebug(const char[] fmt, any ...)
{
    if (!Filters_DebugEnabled())
    {
        return;
    }
    char buffer[256];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogMessage("[Filters][Chat] %s", buffer);
}

bool Filters_IsClientIndex(int client)
{
    return client > 0 && client <= MaxClients;
}

bool Filters_IsRealClientInGame(int client)
{
    return Filters_IsClientIndex(client) && IsClientInGame(client) && !IsFakeClient(client);
}

void Filters_ClearClientState(int client)
{
    if (!Filters_IsClientIndex(client))
    {
        return;
    }
    g_PlayerState[client].isWhitelisted = false;
    g_PlayerState[client].isFilterWhitelisted = false;
    g_PlayerState[client].isBlacklisted = false;
    g_PlayerState[client].isredlisted = false;
    g_PlayerState[client].cookiesProcessed = false;
    g_NameColors[client][0] = '\0';
    g_NamePatterns[client][0] = '\0';
}

void Filters_ResetExternalStats(int client)
{
    if (!Filters_IsClientIndex(client))
    {
        return;
    }
    g_PlayerState[client].rapesGiven = 0;
    g_PlayerState[client].whaleKills = 0;
    g_PlayerState[client].hugsStatsLoaded = false;
    g_PlayerState[client].whaleStatsLoaded = false;
    g_AutoRedlistKills[client] = 0;
    g_AutoRedlistRapes[client] = 0;
    g_AutoRedlistGotKills[client] = false;
    g_AutoRedlistGotRapes[client] = false;
}

static bool Filters_TryGetRapesGiven(int client, int &value)
{
    if (GetFeatureStatus(FeatureType_Native, "Hugs_GetRapesGiven") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "Hugs_AreStatsLoaded") != FeatureStatus_Available
        || !Hugs_AreStatsLoaded(client))
    {
        return false;
    }
    value = Hugs_GetRapesGiven(client);
    return true;
}

static bool Filters_TryGetWhaleKills(int client, int &value)
{
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetCumulativeKills") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "WhaleTracker_AreStatsLoaded") != FeatureStatus_Available
        || !WhaleTracker_AreStatsLoaded(client))
    {
        return false;
    }
    value = WhaleTracker_GetCumulativeKills(client);
    return true;
}

void Filters_UpdateExternalStats(int client)
{
    if (!Filters_IsClientIndex(client) || !IsClientInGame(client))
    {
        return;
    }
    // Optional natives can run other plugins. Do not publish into a reused slot.
    int serial = GetClientSerial(client);
    int value;
    bool loaded = Filters_TryGetRapesGiven(client, value);
    if (GetClientFromSerial(serial) != client || !IsClientInGame(client))
    {
        return;
    }
    g_PlayerState[client].hugsStatsLoaded = loaded;
    if (loaded)
    {
        g_PlayerState[client].rapesGiven = value;
    }
    loaded = Filters_TryGetWhaleKills(client, value);
    if (GetClientFromSerial(serial) != client || !IsClientInGame(client))
    {
        return;
    }
    g_PlayerState[client].whaleStatsLoaded = loaded;
    if (loaded)
    {
        g_PlayerState[client].whaleKills = value;
    }
}

void RefreshHostAddress()
{
    if (g_hHostIpCvar == null)
    {
        g_hHostIpCvar = FindConVar("ip");
        if (g_hHostIpCvar == null)
        {
            g_hHostIpCvar = FindConVar("hostip");
        }
    }
    g_sHostIp[0] = '\0';
    if (g_hHostIpCvar != null)
    {
        g_hHostIpCvar.GetString(g_sHostIp, sizeof(g_sHostIp));
    }
    if (!g_sHostIp[0])
    {
        strcopy(g_sHostIp, sizeof(g_sHostIp), FILTERS_DEFAULT_HOST_IP);
    }
    if (g_hHostPortCvar == null)
    {
        g_hHostPortCvar = FindConVar("hostport");
    }
    g_iHostPort = g_hHostPortCvar != null ? g_hHostPortCvar.IntValue : 27015;
    RefreshPublicHostIp();
    Filters_LogDebug("Host identity refreshed: local=%s public=%s port=%d",
        g_sHostIp, g_sPublicHostIp, g_iHostPort);
    Filters_UpdateHostStampString();
}

void RefreshServerHostname()
{
    if (g_hHostnameCvar == null)
    {
        g_hHostnameCvar = FindConVar("hostname");
    }
    g_sServerName[0] = '\0';
    if (g_hHostnameCvar != null)
    {
        g_hHostnameCvar.GetString(g_sServerName, sizeof(g_sServerName));
    }
}

static void RefreshPublicHostIp()
{
    strcopy(g_sPublicHostIp, sizeof(g_sPublicHostIp), FILTERS_PUBLIC_HOST_IP);
}

static void Filters_GetPreferredHostIp(char[] buffer, int maxlen)
{
    if (!g_sPublicHostIp[0] && !g_sHostIp[0])
    {
        RefreshHostAddress();
    }
    strcopy(buffer, maxlen, g_sPublicHostIp[0] ? g_sPublicHostIp : g_sHostIp);
}

void Filters_GetLocalHostStamp(char[] ipOut, int ipLen, int &portOut)
{
    Filters_GetPreferredHostIp(ipOut, ipLen);
    portOut = g_iHostPort;
}

bool Filters_IsLocalHostStamp(const char[] otherIp, int otherPort)
{
    if (!otherIp[0] || otherPort <= 0)
    {
        return false;
    }
    char localIp[64];
    Filters_GetPreferredHostIp(localIp, sizeof(localIp));
    return localIp[0] != '\0' && StrEqual(localIp, otherIp, false) && otherPort == g_iHostPort;
}

static void Filters_UpdateHostStampString()
{
    char ip[64];
    int port;
    Filters_GetLocalHostStamp(ip, sizeof(ip), port);
    if (!ip[0])
    {
        strcopy(ip, sizeof(ip), FILTERS_DEFAULT_HOST_IP);
    }
    FormatEx(g_sHostStamp, sizeof(g_sHostStamp), "%s:%d", ip, port);
}

void Filters_GetHostStamp(char[] buffer, int maxlen)
{
    if (!g_sHostStamp[0])
    {
        Filters_UpdateHostStampString();
    }
    strcopy(buffer, maxlen, g_sHostStamp);
}
