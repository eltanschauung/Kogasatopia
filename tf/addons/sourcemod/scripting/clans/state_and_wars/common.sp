bool Clans_IsRoundRunning()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_IsRoundRunning") == FeatureStatus_Available)
    {
        return DGM_IsRoundRunning();
    }

    return GameRules_GetRoundState() == RoundState_RoundRunning;
}

bool GetClientSteam64(int client, char[] steamid64, int maxlen)
{
    steamid64[0] = '\0';

    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    return Kogasa_GetClientSteamId64(client, steamid64, maxlen, true);
}

void ResolvePlayerDisplayName(const char[] steamid64, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    int client = Kogasa_FindClientBySteamId64(steamid64);
    if (client > 0)
    {
        GetClientName(client, buffer, maxlen);
        return;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetLastRecordedSteamName") == FeatureStatus_Available
        && Filters_GetLastRecordedSteamName(steamid64, buffer, maxlen) && buffer[0] != '\0')
    {
        return;
    }

    strcopy(buffer, maxlen, steamid64);
}

int FindClientByNameQuery(const char[] query)
{
    int partialClient = 0;
    int partialCount = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client))
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));

        if (StrEqual(name, query, false))
        {
            return client;
        }

        if (StrContains(name, query, false) != -1)
        {
            partialClient = client;
            partialCount++;
        }
    }

    return (partialCount == 1) ? partialClient : 0;
}

void EscapeSql(const char[] input, char[] output, int maxlen)
{
    output[0] = '\0';
    Db_Escape(g_Database, input, output, maxlen, "Clans");
}

void GetClanRankLabel(ClanRank rank, char[] buffer, int maxlen)
{
    if (rank >= ClanRank_Owner)
    {
        strcopy(buffer, maxlen, "Hokage");
        return;
    }

    if (rank >= ClanRank_Officer)
    {
        strcopy(buffer, maxlen, "Officer");
        return;
    }

    strcopy(buffer, maxlen, "Member");
}

bool TryGetSelectedTag(int client, const char[] steamid64, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (GetFeatureStatus(FeatureType_Native, "Tags_GetTag") != FeatureStatus_Available)
    {
        return false;
    }

    if (client > 0 && IsClientInGame(client))
    {
        return Tags_GetTag(client, "", buffer, maxlen) && buffer[0] != '\0';
    }

    return Tags_GetTag(0, steamid64, buffer, maxlen) && buffer[0] != '\0';
}

void TrySetClanJoinSelectedTag(int client, const char[] clanTag)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    if (GetFeatureStatus(FeatureType_Native, "Tags_SetSelectedTag") != FeatureStatus_Available)
    {
        return;
    }

    char selectedTag[CLAN_TAG_STORE_MAXLEN];
    ExtractRawClanTag(clanTag, selectedTag, sizeof(selectedTag));
    TrimString(selectedTag);
    if (!selectedTag[0] || !IsExportableClanTagText(selectedTag))
    {
        return;
    }

    Tags_SetSelectedTag(client, selectedTag);
}

void BuildClanDisplayTag(const char[] rawTag, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (!rawTag[0])
    {
        return;
    }

    if (rawTag[0] == '[')
    {
        strcopy(buffer, maxlen, rawTag);
        return;
    }

    FormatEx(buffer, maxlen, "[{gold}%s{default}]", rawTag);
}

void BuildClanChatSenderName(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available)
    {
        if (Filters_GetChatName(client, buffer, maxlen) && buffer[0] != '\0')
        {
            return;
        }
    }

    GetClientName(client, buffer, maxlen);
}

void ResolveClientTeamColorTag(int client, char[] buffer, int maxlen)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    if (StrContains(buffer, "{teamcolor}", false) == -1)
    {
        return;
    }

    char replacement[16];
    switch (GetClientTeam(client))
    {
        case 2:
        {
            strcopy(replacement, sizeof(replacement), "{red}");
        }
        case 3:
        {
            strcopy(replacement, sizeof(replacement), "{blue}");
        }
        default:
        {
            strcopy(replacement, sizeof(replacement), "{default}");
        }
    }

    ReplaceString(buffer, maxlen, "{teamcolor}", replacement, false);
}

bool IsConnectedClientInClan(int client, int clanId)
{
    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    if (g_bClientClanLoaded[client] && g_iClientClanId[client] == clanId)
    {
        return true;
    }

    char steamid64[STEAMID64_MAXLEN];
    int cachedClanId = 0;
    return GetClientSteam64(client, steamid64, sizeof(steamid64))
        && GetCachedClanIdForSteam64(steamid64, cachedClanId)
        && cachedClanId == clanId;
}

void BuildClanMemberMenuLabel(const char[] viewerSteamId64, const char[] memberSteamId64, ClanRank rank, char[] buffer, int maxlen)
{
    char name[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(memberSteamId64, name, sizeof(name));

    char rankLabel[16];
    GetClanRankLabel(rank, rankLabel, sizeof(rankLabel));

    if (viewerSteamId64[0] != '\0' && StrEqual(viewerSteamId64, memberSteamId64, false))
    {
        FormatEx(buffer, maxlen, "%s (You)", name);
        return;
    }

    FormatEx(buffer, maxlen, "%s (%s)", name, rankLabel);
}

void FormatClanTimestamp(int timestamp, char[] buffer, int maxlen)
{
    if (timestamp > 0)
    {
        FormatTime(buffer, maxlen, "%Y-%m-%d %H:%M:%S", timestamp);
        return;
    }

    strcopy(buffer, maxlen, "Unknown");
}

void QueryClanMemberDetailsForClient(int userId, int clanId, const char[] clanName, const char[] steamid64)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT cm.rank, cm.joined_at, COALESCE(cst.tag, ''), "
        ... "COALESCE((SELECT SUM(cwmk.kills) FROM clan_war_member_kills cwmk WHERE cwmk.steamid64 = cm.steamid64), 0) "
        ... "FROM clan_members cm "
        ... "LEFT JOIN clan_sub_tags cst ON cst.clan_id = cm.clan_id AND cst.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = %d AND cm.steamid64 = '%s' "
        ... "LIMIT 1",
        clanId,
        escapedSteam);

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(clanId);
    pack.WriteString(clanName);
    pack.WriteString(steamid64);

    g_Database.Query(SQL_OnClanMemberDetails, query, pack);
}

