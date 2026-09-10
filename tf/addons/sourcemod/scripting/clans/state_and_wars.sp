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

static bool TryGetSelectedTag(int client, const char[] steamid64, char[] buffer, int maxlen)
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

static void ResolveClientTeamColorTag(int client, char[] buffer, int maxlen)
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

bool GetClanWarInstanceIdSync(int warId, int createdAt, int &instanceId)
{
    instanceId = 0;

    if (!EnsureDatabaseReady() || warId <= 0 || createdAt <= 0)
    {
        return false;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "SELECT id FROM clan_war_instances WHERE war_id = %d AND created_at = %d LIMIT 1",
        warId,
        createdAt);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch war instance %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (results.FetchRow())
    {
        instanceId = results.FetchInt(0);
    }

    delete results;
    return (instanceId > 0);
}

bool EnsureClanWarInstanceSync(int warId, int clanIdA, int clanIdB, int createdAt, int &instanceId)
{
    instanceId = 0;

    if (!EnsureDatabaseReady() || warId <= 0 || clanIdA <= 0 || clanIdB <= 0 || createdAt <= 0)
    {
        return false;
    }

    if (GetClanWarInstanceIdSync(warId, createdAt, instanceId))
    {
        return true;
    }

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_war_instances (war_id, clan_id_a, clan_id_b, score_a, score_b, winner_clan_id, status, created_at, finished_at) "
        ... "VALUES (%d, %d, %d, 0, 0, NULL, %d, %d, NULL)",
        warId,
        clanIdA,
        clanIdB,
        view_as<int>(ClanWarStatus_Active),
        createdAt);

    if (!SQL_FastQuery(g_Database, query))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to create war instance for %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        return false;
    }

    return GetClanWarInstanceIdSync(warId, createdAt, instanceId);
}

void UpdateClanWarInstanceFinalState(int instanceId, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status, int finishedAt)
{
    if (instanceId <= 0 || !EnsureDatabaseReady())
    {
        return;
    }

    char winnerValue[16];
    if (winnerClanId > 0)
    {
        IntToString(winnerClanId, winnerValue, sizeof(winnerValue));
    }
    else
    {
        strcopy(winnerValue, sizeof(winnerValue), "NULL");
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_war_instances SET score_a = %d, score_b = %d, winner_clan_id = %s, status = %d, finished_at = %d "
        ... "WHERE id = %d",
        scoreA,
        scoreB,
        winnerValue,
        view_as<int>(status),
        finishedAt,
        instanceId);

    g_Database.Query(SQL_GenericQueryCallback, query);
}

void QueueClanWarKillDelta(int warInstanceId, int clanId, const char[] steamid64, int kills = 1, int currencyStolen = 0)
{
    if (warInstanceId <= 0 || clanId <= 0 || !steamid64[0] || kills <= 0)
    {
        return;
    }

    if (g_hPendingClanWarKillDeltas == null)
    {
        g_hPendingClanWarKillDeltas = new ArrayList(sizeof(PendingClanWarKillDelta));
    }

    PendingClanWarKillDelta delta;
    for (int i = 0; i < g_hPendingClanWarKillDeltas.Length; i++)
    {
        g_hPendingClanWarKillDeltas.GetArray(i, delta);
        if (delta.warInstanceId != warInstanceId || delta.clanId != clanId || !StrEqual(delta.steamid64, steamid64, false))
        {
            continue;
        }

        delta.kills += kills;
        delta.currencyStolen += currencyStolen;
        g_hPendingClanWarKillDeltas.SetArray(i, delta);
        return;
    }

    delta.warInstanceId = warInstanceId;
    delta.clanId = clanId;
    delta.kills = kills;
    delta.currencyStolen = currencyStolen;
    strcopy(delta.steamid64, sizeof(delta.steamid64), steamid64);
    g_hPendingClanWarKillDeltas.PushArray(delta);
}

void RecordClanWarKill(int warInstanceId, int clanId, const char[] steamid64, int currencyStolen = 0)
{
    QueueClanWarKillDelta(warInstanceId, clanId, steamid64, 1, currencyStolen);
}

bool FlushPendingClanWarKillWritesSync()
{
    if (!EnsureDatabaseReady() || g_hPendingClanWarKillDeltas == null || g_bClanWarKillFlushInFlight)
    {
        return false;
    }

    if (g_hPendingClanWarKillDeltas.Length <= 0)
    {
        return true;
    }

    ArrayList batch = g_hPendingClanWarKillDeltas;
    g_hPendingClanWarKillDeltas = new ArrayList(sizeof(PendingClanWarKillDelta));
    g_bClanWarKillFlushInFlight = true;
    FlushNextClanWarKillDelta(batch, 0);
    return true;
}

void RequeueClanWarKillBatch(ArrayList batch, int startIndex)
{
    if (batch == null)
    {
        return;
    }

    PendingClanWarKillDelta delta;
    for (int i = startIndex; i < batch.Length; i++)
    {
        batch.GetArray(i, delta);
        QueueClanWarKillDelta(delta.warInstanceId, delta.clanId, delta.steamid64, delta.kills, delta.currencyStolen);
    }
}

void FlushNextClanWarKillDelta(ArrayList batch, int index)
{
    if (batch == null)
    {
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    if (!EnsureDatabaseReady())
    {
        RequeueClanWarKillBatch(batch, index);
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    if (index >= batch.Length)
    {
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    PendingClanWarKillDelta delta;
    batch.GetArray(index, delta);

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(delta.steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    if (IsMySql())
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_war_member_kills (war_instance_id, clan_id, steamid64, kills, currency_stolen) "
            ... "VALUES (%d, %d, '%s', %d, %d) "
            ... "ON DUPLICATE KEY UPDATE kills = kills + %d, currency_stolen = currency_stolen + %d, clan_id = VALUES(clan_id)",
            delta.warInstanceId,
            delta.clanId,
            escapedSteam,
            delta.kills,
            delta.currencyStolen,
            delta.kills,
            delta.currencyStolen);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_war_member_kills (war_instance_id, clan_id, steamid64, kills, currency_stolen) "
            ... "VALUES (%d, %d, '%s', %d, %d) "
            ... "ON CONFLICT(war_instance_id, steamid64) DO UPDATE SET kills = clan_war_member_kills.kills + %d, currency_stolen = clan_war_member_kills.currency_stolen + %d, clan_id = excluded.clan_id",
            delta.warInstanceId,
            delta.clanId,
            escapedSteam,
            delta.kills,
            delta.currencyStolen,
            delta.kills,
            delta.currencyStolen);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(batch);
    pack.WriteCell(index);
    g_Database.Query(SQL_OnClanWarKillDeltaWritten, query, pack);
}

public void SQL_OnClanWarKillDeltaWritten(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    ArrayList batch = view_as<ArrayList>(pack.ReadCell());
    int index = pack.ReadCell();
    delete pack;

    PendingClanWarKillDelta delta;
    batch.GetArray(index, delta);

    if (error[0])
    {
        LogError("[Clans] Failed to persist war kill delta for instance %d/%s: %s", delta.warInstanceId, delta.steamid64, error);
        HandleDatabaseConnectionLoss(error);
        RequeueClanWarKillBatch(batch, index);
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    FlushNextClanWarKillDelta(batch, index + 1);
}

void AnnounceClanInviteToMembers(int clanId, const char[] clanName, const char[] inviterSteam, const char[] targetSteam)
{
    DataPack pack = new DataPack();
    pack.WriteString(clanName);
    pack.WriteString(inviterSteam);
    pack.WriteString(targetSteam);

    GetClanMembers(clanId, SQL_OnAnnounceClanInviteToMembers, pack);
}

void AnnounceClanInviteAcceptedToMembers(int clanId, const char[] clanName, const char[] accepterSteam)
{
    DataPack pack = new DataPack();
    pack.WriteString(clanName);
    pack.WriteString(accepterSteam);

    GetClanMembers(clanId, SQL_OnAnnounceClanInviteAcceptedToMembers, pack);
}

int GetAllowedMainClanTagLength(int client)
{
    int allowed = CheckCommandAccess(client, "clans_long_tag", ADMFLAG_GENERIC, true) ? CLAN_TAG_ADMIN_MAXLEN : CLAN_TAG_PLAYER_MAXLEN;
    int storageSafe = CLAN_TAG_MAXLEN - CLAN_TAG_FORMAT_OVERHEAD;

    if (allowed > storageSafe)
    {
        allowed = storageSafe;
    }

    return allowed;
}

int GetAllowedSubClanTagLength(int client)
{
    return CheckCommandAccess(client, "clans_long_tag", ADMFLAG_GENERIC, true) ? CLAN_TAG_ADMIN_MAXLEN : CLAN_TAG_PLAYER_MAXLEN;
}

static bool ValidateClanTagText(const char[] text, bool allowFormatting)
{
    if (!text[0])
    {
        return false;
    }

    int len = strlen(text);
    for (int i = 0; i < len;)
    {
        int ch = view_as<int>(text[i]) & 0xFF;

        if (ch < 0x20 || ch == 0x7F)
        {
            return false;
        }

        if (ch == '|')
        {
            return false;
        }

        if (!allowFormatting && (ch == '[' || ch == ']'))
        {
            return false;
        }

        if (ch < 0x80)
        {
            i++;
            continue;
        }

        int needed = 0;
        int codepoint = 0;
        int minimum = 0;

        if ((ch & 0xE0) == 0xC0)
        {
            needed = 2;
            codepoint = ch & 0x1F;
            minimum = 0x80;
        }
        else if ((ch & 0xF0) == 0xE0)
        {
            needed = 3;
            codepoint = ch & 0x0F;
            minimum = 0x800;
        }
        else if ((ch & 0xF8) == 0xF0)
        {
            needed = 4;
            codepoint = ch & 0x07;
            minimum = 0x10000;
        }
        else
        {
            return false;
        }

        if ((i + needed) > len)
        {
            return false;
        }

        for (int j = 1; j < needed; j++)
        {
            int continuation = view_as<int>(text[i + j]) & 0xFF;
            if ((continuation & 0xC0) != 0x80)
            {
                return false;
            }

            codepoint = (codepoint << 6) | (continuation & 0x3F);
        }

        if (codepoint < minimum || codepoint > 0x10FFFF)
        {
            return false;
        }

        if (codepoint >= 0xD800 && codepoint <= 0xDFFF)
        {
            return false;
        }

        i += needed;
    }

    return true;
}

bool IsSafeClanTagText(const char[] text)
{
    return ValidateClanTagText(text, false);
}

static bool IsExportableClanTagText(const char[] text)
{
    return ValidateClanTagText(text, true);
}

static bool IsClanTagColorTokenAt(const char[] text, int start, int &end)
{
    end = start;

    if (text[start] != '{')
    {
        return false;
    }

    for (int i = start + 1; text[i] != '\0'; i++)
    {
        if (text[i] == '}')
        {
            end = i + 1;
            return i > start + 1;
        }

        if (text[i] == '{' || text[i] == '[' || text[i] == ']' || text[i] == '|')
        {
            return false;
        }
    }

    return false;
}

static void RemoveClanTagTextRange(char[] text, int start, int stop)
{
    int write = start;
    for (int read = stop; ; read++)
    {
        text[write++] = text[read];
        if (text[read] == '\0')
        {
            break;
        }
    }
}

void NormalizeClanTagText(char[] text)
{
    TrimString(text);

    int tokenStart = 0;
    int tokenEnd = 0;
    while (IsClanTagColorTokenAt(text, tokenStart, tokenEnd))
    {
        int visibleStart = tokenEnd;
        while (text[visibleStart] == ' ')
        {
            visibleStart++;
        }

        if (visibleStart > tokenEnd)
        {
            RemoveClanTagTextRange(text, tokenEnd, visibleStart);
        }

        tokenStart = tokenEnd;
    }
}

void FormatStoredClanTag(const char[] rawTag, char[] buffer, int maxlen)
{
    char normalized[CLAN_TAG_STORE_MAXLEN];
    strcopy(normalized, sizeof(normalized), rawTag);
    NormalizeClanTagText(normalized);

    FormatEx(buffer, maxlen, "[{gold}%s{default}]", normalized);
}

static void ExtractRawClanTag(const char[] storedTag, char[] buffer, int maxlen)
{
    static const char prefix[] = "[{gold}";
    static const char suffix[] = "{default}]";

    buffer[0] = '\0';

    if (!storedTag[0])
    {
        return;
    }

    int len = strlen(storedTag);
    int prefixLen = sizeof(prefix) - 1;
    int suffixLen = sizeof(suffix) - 1;

    if (len > (prefixLen + suffixLen))
    {
        bool prefixMatch = true;
        for (int i = 0; i < prefixLen; i++)
        {
            if (storedTag[i] != prefix[i])
            {
                prefixMatch = false;
                break;
            }
        }

        bool suffixMatch = true;
        for (int i = 0; i < suffixLen; i++)
        {
            if (storedTag[(len - suffixLen) + i] != suffix[i])
            {
                suffixMatch = false;
                break;
            }
        }

        if (prefixMatch && suffixMatch)
        {
            int rawLen = len - prefixLen - suffixLen;
            int copyLen = (rawLen < (maxlen - 1)) ? rawLen : (maxlen - 1);

            for (int i = 0; i < copyLen; i++)
            {
                buffer[i] = storedTag[prefixLen + i];
            }

            buffer[copyLen] = '\0';
            NormalizeClanTagText(buffer);
            return;
        }
    }

    strcopy(buffer, maxlen, storedTag);
    NormalizeClanTagText(buffer);
}

static bool AppendJoinedClanTag(char[] buffer, int maxlen, const char[] tag)
{
    if (!tag[0])
    {
        return false;
    }

    if (buffer[0])
    {
        StrCat(buffer, maxlen, "|");
    }

    StrCat(buffer, maxlen, tag);
    return true;
}

void ClearClientClanTagsCache(int client, bool loaded = false)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_sClientClanTags[client][0] = '\0';
    g_bClientClanTagsLoaded[client] = loaded;
    g_bClientClanTagsPending[client] = false;
}

void RequestClientClanTagsLoad(int client, bool force = false)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    if (!EnsureDatabaseReady())
    {
        return;
    }

    if (g_bClientClanTagsPending[client])
    {
        return;
    }

    if (!force && g_bClientClanTagsLoaded[client])
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        ClearClientClanTagsCache(client, true);
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT 0 AS sort_order, 0 AS created_at, c.tag "
        ... "FROM clan_members cm "
        ... "INNER JOIN clans c ON c.id = cm.clan_id "
        ... "WHERE cm.steamid64 = '%s' AND c.tag IS NOT NULL AND LENGTH(c.tag) > 0 "
        ... "UNION ALL "
        ... "SELECT 1 AS sort_order, cst.created_at, cst.tag "
        ... "FROM clan_members self_cm "
        ... "INNER JOIN clan_sub_tags cst ON cst.clan_id = self_cm.clan_id "
        ... "WHERE self_cm.steamid64 = '%s' AND cst.tag IS NOT NULL AND LENGTH(cst.tag) > 0 "
        ... "ORDER BY sort_order ASC, created_at ASC",
        escapedSteam,
        escapedSteam);

    g_sClientClanTags[client][0] = '\0';
    g_bClientClanTagsLoaded[client] = false;
    g_bClientClanTagsPending[client] = true;
    g_Database.Query(SQL_OnClientClanTagsLoaded, query, GetClientUserId(client));
}

public void SQL_OnClientClanTagsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bClientClanTagsPending[client] = false;

    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Failed to load clan tags for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    g_sClientClanTags[client][0] = '\0';

    char storedTag[CLAN_TAG_STORE_MAXLEN];
    char rawTag[CLAN_SUB_TAG_STORE_MAXLEN];
    while (results != null && results.FetchRow())
    {
        int sortOrder = results.FetchInt(0);
        results.FetchString(2, storedTag, sizeof(storedTag));
        TrimString(storedTag);

        if (!storedTag[0])
        {
            continue;
        }

        if (sortOrder == 0)
        {
            ExtractRawClanTag(storedTag, rawTag, sizeof(rawTag));
        }
        else
        {
            strcopy(rawTag, sizeof(rawTag), storedTag);
        }

        TrimString(rawTag);
        if (IsExportableClanTagText(rawTag))
        {
            AppendJoinedClanTag(g_sClientClanTags[client], sizeof(g_sClientClanTags[]), rawTag);
        }
    }

    g_bClientClanTagsLoaded[client] = true;
}

void RefreshConnectedClanTagsForClan(int clanId)
{
    if (clanId <= 0)
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || g_iClientClanId[client] != clanId)
        {
            continue;
        }

        RequestClientClanTagsLoad(client, true);
    }
}

public any Native_Clans_GetTags(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int maxlen = GetNativeCell(3);

    char buffer[4096];
    buffer[0] = '\0';

    bool found = false;
    if (Client_IsHumanInGame(client))
    {
        if (g_bClientClanTagsLoaded[client] && g_sClientClanTags[client][0])
        {
            strcopy(buffer, sizeof(buffer), g_sClientClanTags[client]);
            found = true;
        }
        else if (!g_bClientClanTagsPending[client])
        {
            RequestClientClanTagsLoad(client);
        }
    }

    SetNativeString(2, buffer, maxlen, true);
    return found;
}

public any Native_Clans_GetSameTeamClanMemberCount(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int team = (numParams >= 2) ? GetNativeCell(2) : 0;
    return GetSameTeamClanMemberCount(client, team);
}

void RebuildClanIdCache()
{
    g_bClanIdCacheReady = false;

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query), "SELECT steamid64, clan_id FROM clan_members");
    g_Database.Query(SQL_OnClanIdCacheRebuilt, query);
}

public void SQL_OnClanIdCacheRebuilt(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Clans] Failed to rebuild clan id cache: %s", error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    if (!HasUsableResultSet(results))
    {
        LogError("[Clans] Failed to rebuild clan id cache: query returned no result set.");
        return;
    }

    if (g_hClanIdCache != null)
    {
        delete g_hClanIdCache;
    }

    g_hClanIdCache = new StringMap();

    char steamid64[STEAMID64_MAXLEN];
    while (results.FetchRow())
    {
        results.FetchString(0, steamid64, sizeof(steamid64));
        TrimString(steamid64);
        if (!steamid64[0])
        {
            continue;
        }

        g_hClanIdCache.SetValue(steamid64, results.FetchInt(1), true);
    }

    g_bClanIdCacheReady = true;
}

bool GetCachedClanIdForSteam64(const char[] steamid64, int &clanId)
{
    clanId = 0;
    return (g_hClanIdCache != null && steamid64[0] != '\0' && g_hClanIdCache.GetValue(steamid64, clanId));
}

bool GetLoadedClientClanId(int client, int &clanId)
{
    clanId = 0;

    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    if (!g_bClientClanLoaded[client])
    {
        return false;
    }

    clanId = g_iClientClanId[client];
    return true;
}

bool ResolveClientClanIdForWarScoring(int client, int &clanId)
{
    clanId = 0;

    if (GetLoadedClientClanId(client, clanId))
    {
        return true;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return false;
    }

    if (GetCachedClanIdForSteam64(steamid64, clanId))
    {
        return true;
    }

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[160];
    FormatEx(query, sizeof(query), "SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1", escapedSteam);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to resolve scoring clan id for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (results.FetchRow())
    {
        clanId = results.FetchInt(0);
        UpdateClanIdCacheEntry(steamid64, clanId);
    }

    delete results;
    return true;
}

void UpdateClanIdCacheEntry(const char[] steamid64, int clanId)
{
    if (steamid64[0] == '\0')
    {
        return;
    }

    if (g_hClanIdCache == null)
    {
        g_hClanIdCache = new StringMap();
    }

    if (clanId > 0)
    {
        g_hClanIdCache.SetValue(steamid64, clanId, true);
    }
    else
    {
        g_hClanIdCache.Remove(steamid64);
    }
}

void RemoveClanIdCacheMembers(int clanId)
{
    if (clanId <= 0 || g_hClanIdCache == null)
    {
        return;
    }

    StringMapSnapshot snap = g_hClanIdCache.Snapshot();
    if (snap == null)
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    int cachedClanId = 0;
    for (int i = 0; i < snap.Length; i++)
    {
        snap.GetKey(i, steamid64, sizeof(steamid64));
        if (!g_hClanIdCache.GetValue(steamid64, cachedClanId) || cachedClanId != clanId)
        {
            continue;
        }

        g_hClanIdCache.Remove(steamid64);
    }

    delete snap;
}

int GetSameTeamClanMemberCount(int client, int team = 0)
{
    if (!Client_IsHumanInGame(client))
    {
        return 0;
    }

    if (team <= 1)
    {
        team = GetClientTeam(client);
    }

    if (team <= 1)
    {
        return 0;
    }

    int clanId = 0;
    if (!ResolveClientClanIdForTeamGuard(client, clanId))
    {
        return 0;
    }

    if (clanId <= 0)
    {
        return 0;
    }

    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Client_IsHumanInGame(i) || GetClientTeam(i) != team)
        {
            continue;
        }

        int currentClanId = 0;
        if (!ResolveClientClanIdForTeamGuard(i, currentClanId))
        {
            continue;
        }

        if (currentClanId == clanId)
        {
            count++;
        }
    }

    return count;
}

bool ResolveClientClanIdForTeamGuard(int client, int &clanId)
{
    clanId = 0;

    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    if (GetLoadedClientClanId(client, clanId))
    {
        return true;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return false;
    }

    if (GetCachedClanIdForSteam64(steamid64, clanId))
    {
        return true;
    }

    if (g_bClanIdCacheReady)
    {
        return true;
    }

    if (!g_bClientClanLoadPending[client])
    {
        RequestClientClanIdLoad(client);
    }

    return false;
}

void RequestClientClanIdLoad(int client)
{
    if (!EnsureDatabaseReady() || !Client_IsHumanInGame(client))
    {
        return;
    }

    if (g_bClientClanLoadPending[client])
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT cm.clan_id, cm.rank, c.name, COALESCE(c.tag, '') "
        ... "FROM clan_members cm "
        ... "INNER JOIN clans c ON c.id = cm.clan_id "
        ... "WHERE cm.steamid64 = '%s' LIMIT 1",
        escapedSteam);

    g_bClientClanLoadPending[client] = true;
    g_Database.Query(SQL_OnClientClanIdLoaded, query, GetClientUserId(client));
}

public void SQL_OnClientClanIdLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bClientClanLoadPending[client] = false;

    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Failed to load clan id for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    g_iClientClanId[client] = 0;
    g_ClientClanRank[client] = ClanRank_Member;
    g_sClientClanName[client][0] = '\0';
    g_sClientClanTag[client][0] = '\0';

    if (HasUsableResultSet(results) && results.FetchRow())
    {
        g_iClientClanId[client] = results.FetchInt(0);
        g_ClientClanRank[client] = view_as<ClanRank>(results.FetchInt(1));
        results.FetchString(2, g_sClientClanName[client], sizeof(g_sClientClanName[]));
        results.FetchString(3, g_sClientClanTag[client], sizeof(g_sClientClanTag[]));
    }
    g_bClientClanLoaded[client] = true;

    char steamid64[STEAMID64_MAXLEN];
    if (GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        UpdateClanIdCacheEntry(steamid64, g_iClientClanId[client]);
    }
}

bool GetLoadedClientClanContext(int client, char[] steamid64, int steamidLen, int &clanId, ClanRank &rank, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen)
{
    steamid64[0] = '\0';
    clanId = 0;
    rank = ClanRank_Member;
    clanName[0] = '\0';
    clanTag[0] = '\0';

    if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client] || !GetClientSteam64(client, steamid64, steamidLen))
    {
        return false;
    }

    clanId = g_iClientClanId[client];
    rank = g_ClientClanRank[client];
    strcopy(clanName, clanNameLen, g_sClientClanName[client]);
    strcopy(clanTag, clanTagLen, g_sClientClanTag[client]);
    return (clanId <= 0 || clanName[0] != '\0');
}

bool GetCachedOnlineClanSummary(int clanId, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen, char[] representativeName, int representativeNameLen, int &onlineCount)
{
    clanName[0] = '\0';
    clanTag[0] = '\0';
    representativeName[0] = '\0';
    onlineCount = 0;

    ClanRank bestRank = ClanRank_Member;
    bool hasRepresentative = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client] || g_iClientClanId[client] != clanId)
        {
            continue;
        }

        onlineCount++;
        if (!clanName[0])
        {
            strcopy(clanName, clanNameLen, g_sClientClanName[client]);
            strcopy(clanTag, clanTagLen, g_sClientClanTag[client]);
        }

        if (!hasRepresentative || g_ClientClanRank[client] > bestRank)
        {
            GetClientName(client, representativeName, representativeNameLen);
            bestRank = g_ClientClanRank[client];
            hasRepresentative = true;
        }
    }

    return clanName[0] != '\0';
}

void SetClientClanIdBySteam64(const char[] steamid64, int clanId)
{
    UpdateClanIdCacheEntry(steamid64, clanId);

    char currentSteam[STEAMID64_MAXLEN];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client))
        {
            continue;
        }

        if (!GetClientSteam64(client, currentSteam, sizeof(currentSteam)))
        {
            continue;
        }

        if (!StrEqual(currentSteam, steamid64, false))
        {
            continue;
        }

        g_iClientClanId[client] = clanId;
        g_bClientClanLoaded[client] = true;
        g_bClientClanLoadPending[client] = false;
        g_ClientClanRank[client] = ClanRank_Member;
        g_sClientClanName[client][0] = '\0';
        g_sClientClanTag[client][0] = '\0';

        if (clanId > 0)
        {
            /* Refresh the extended context cache asynchronously. */
            g_bClientClanLoaded[client] = false;
            RequestClientClanIdLoad(client);
            RequestClientClanTagsLoad(client, true);
        }
        else
        {
            ClearClientClanTagsCache(client, true);
        }
    }
}

void ClearConnectedClanId(int clanId)
{
    if (clanId <= 0)
    {
        return;
    }

    RemoveClanIdCacheMembers(clanId);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client))
        {
            continue;
        }

        if (g_iClientClanId[client] != clanId)
        {
            continue;
        }

        g_iClientClanId[client] = 0;
        g_bClientClanLoaded[client] = true;
        g_bClientClanLoadPending[client] = false;
        g_ClientClanRank[client] = ClanRank_Member;
        g_sClientClanName[client][0] = '\0';
        g_sClientClanTag[client][0] = '\0';
        ClearClientClanTagsCache(client, true);
    }
}

void CleanupExpiredInvites()
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    int now = GetTime();
    char query[256];
    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE expires_at <= %d", now);
    g_Database.Query(SQL_GenericQueryCallback, query);
}

public Action Timer_CleanupExpiredInvites(Handle timer, any data)
{
    CleanupExpiredInvites();
    CleanupExpiredWars();
    return Plugin_Continue;
}

public Action Timer_FlushClanWarDeltas(Handle timer, any data)
{
    FlushPendingClanWarPersistenceSync();
    return Plugin_Continue;
}

stock void GetClanById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, name, tag, owner, is_open, created_at FROM clans WHERE id = %d LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void GetClanInfoById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, c.tag, c.owner, COALESCE(c.`desc`, ''), ("
        ... "SELECT COUNT(1) FROM clan_members cm WHERE cm.clan_id = c.id"
        ... ") + ("
        ... "SELECT COUNT(1) "
        ... "FROM clan_members cm_child "
        ... "INNER JOIN clan_relations cr ON cr.clan_id_a = cm_child.clan_id "
        ... "WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id"
        ... ") AS member_count, "
        ... "(SELECT COALESCE(SUM(COALESCE(pb.balance, 0)), 0) "
        ... "FROM clan_members cm "
        ... "LEFT JOIN points_store_balances pb ON pb.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = c.id "
        ... "OR cm.clan_id IN (SELECT cr.clan_id_a FROM clan_relations cr WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id)) AS cached_gems "
        ... "FROM clans c "
        ... "WHERE c.id = %d "
        ... "LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void QueryClanGemsById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, "
        ... "COALESCE(SUM(COALESCE(pb.balance, 0)), 0) "
        ... "FROM clans c "
        ... "LEFT JOIN clan_members cm "
        ... "ON (cm.clan_id = c.id "
        ... "OR cm.clan_id IN (SELECT cr.clan_id_a FROM clan_relations cr WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id)) "
        ... "LEFT JOIN points_store_balances pb ON pb.steamid64 = cm.steamid64 "
        ... "WHERE c.id = %d "
        ... "GROUP BY c.id, c.name "
        ... "LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void QueryClanMembersListForClient(int userId, int clanId, const char[] clanName)
{
    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT cm.steamid64, cm.rank, cm.joined_at, COALESCE(cst.tag, '') "
        ... "FROM clan_members cm "
        ... "LEFT JOIN clan_sub_tags cst ON cst.clan_id = cm.clan_id AND cst.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = %d "
        ... "ORDER BY cm.joined_at ASC, cm.rank DESC, cm.steamid64 ASC",
        clanId);

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(clanId);
    pack.WriteString(clanName);

    g_Database.Query(SQL_OnClanMembersList, query, pack);
}

void GetClanByPlayer(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, c.tag, c.owner, c.is_open, c.created_at, cm.rank, cm.joined_at "
        ... "FROM clans c "
        ... "INNER JOIN clan_members cm ON cm.clan_id = c.id "
        ... "WHERE cm.steamid64 = '%s' "
        ... "LIMIT 1",
        escapedSteam);

    g_Database.Query(callback, query, data);
}

void IsPlayerInClan(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT clan_id, rank FROM clan_members WHERE steamid64 = '%s' LIMIT 1",
        escapedSteam);
    g_Database.Query(callback, query, data);
}

stock void GetClanMembers(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT steamid64, rank, joined_at FROM clan_members WHERE clan_id = %d ORDER BY rank DESC, joined_at ASC",
        clanId);
    g_Database.Query(callback, query, data);
}

public void SQL_OnAnnounceClanInviteToMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char clanName[CLAN_NAME_MAXLEN + 1];
    char inviterSteam[STEAMID64_MAXLEN];
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(inviterSteam, sizeof(inviterSteam));
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Invite announcement member query failed: %s", error);
        return;
    }

    if (results == null)
    {
        return;
    }

    char inviterName[MAX_NAME_LENGTH * 2];
    char targetName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(inviterSteam, inviterName, sizeof(inviterName));
    ResolvePlayerDisplayName(targetSteam, targetName, sizeof(targetName));

    while (results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        int member = Kogasa_FindClientBySteamId64(memberSteam);
        if (member <= 0 || !IsClientInGame(member))
        {
            continue;
        }

        PrintToChat(member, "[Clans] %s invited %s to '%s'.", inviterName, targetName, clanName);
    }
}

public void SQL_OnAnnounceClanInviteAcceptedToMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char clanName[CLAN_NAME_MAXLEN + 1];
    char accepterSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(accepterSteam, sizeof(accepterSteam));
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Invite accept announcement member query failed: %s", error);
        return;
    }

    if (results == null)
    {
        return;
    }

    char accepterName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(accepterSteam, accepterName, sizeof(accepterName));

    while (results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        int member = Kogasa_FindClientBySteamId64(memberSteam);
        if (member <= 0 || !IsClientInGame(member))
        {
            continue;
        }

        PrintToChat(member, "[Clans] %s accepted an invite to '%s'.", accepterName, clanName);
    }
}

void CreateClan(const char[] ownerSteamId64, const char[] name, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedOwner[SQL_STEAMID64_MAXLEN];
    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(ownerSteamId64, escapedOwner, sizeof(escapedOwner));
    EscapeSql(name, escapedName, sizeof(escapedName));

    char lastInsertExpr[32];
    if (IsMySql())
    {
        strcopy(lastInsertExpr, sizeof(lastInsertExpr), "LAST_INSERT_ID()");
    }
    else
    {
        strcopy(lastInsertExpr, sizeof(lastInsertExpr), "last_insert_rowid()");
    }
    int now = GetTime();

    Transaction txn = new Transaction();

    char query[512];
    FormatEx(query, sizeof(query),
        "INSERT INTO clans (name, tag, owner, is_open, created_at) VALUES ('%s', NULL, '%s', 0, %d)",
        escapedName,
        escapedOwner,
        now);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "INSERT INTO clan_members (clan_id, steamid64, rank, joined_at) VALUES (%s, '%s', %d, %d)",
        lastInsertExpr,
        escapedOwner,
        view_as<int>(ClanRank_Owner),
        now);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteString(name);
    pack.WriteString(ownerSteamId64);

    g_Database.Execute(txn, SQLTxn_OnCreateClanSuccess, SQLTxn_OnCreateClanFailure, pack);
}

void DeleteClan(int clanId, int requesterUserId = 0, bool refundOwner = false)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    ResolveActiveWarsForDeletedClan(clanId);

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d OR clan_id_b = %d", clanId, clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_sub_tags WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_members WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clans WHERE id = %d", clanId);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteCell(refundOwner ? 1 : 0);
    pack.WriteCell(clanId);

    g_Database.Execute(txn, SQLTxn_OnDeleteClanSuccess, SQLTxn_OnDeleteClanFailure, pack);
}

void AddClanMember(int clanId, const char[] steamid64, SQLQueryCallback callback, any data = 0, ClanRank rank = ClanRank_Member)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_members (clan_id, steamid64, rank, joined_at) VALUES (%d, '%s', %d, %d)",
        clanId,
        escapedSteam,
        view_as<int>(rank),
        GetTime());
    g_Database.Query(callback, query, data);
}

void SetClanTag(int clanId, const char[] tag, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedTag[SQL_CLAN_TAG_MAXLEN];
    EscapeSql(tag, escapedTag, sizeof(escapedTag));

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET tag = '%s' WHERE id = %d",
        escapedTag,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanDescription(int clanId, const char[] description, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedDescription[SQL_CLAN_DESC_MAXLEN];
    EscapeSql(description, escapedDescription, sizeof(escapedDescription));

    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET `desc` = '%s' WHERE id = %d",
        escapedDescription,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanName(int clanId, const char[] name, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(name, escapedName, sizeof(escapedName));

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET name = '%s' WHERE id = %d",
        escapedName,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanSubTag(int clanId, const char[] steamid64, const char[] tag, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedTag[SQL_CLAN_SUB_TAG_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(tag, escapedTag, sizeof(escapedTag));

    char query[384];
    FormatEx(query, sizeof(query),
        "REPLACE INTO clan_sub_tags (clan_id, steamid64, tag, created_at) VALUES (%d, '%s', '%s', %d)",
        clanId,
        escapedSteam,
        escapedTag,
        GetTime());
    g_Database.Query(callback, query, data);
}

void SetClanOpen(int clanId, bool isOpen, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET is_open = %d WHERE id = %d",
        isOpen ? 1 : 0,
        clanId);
    g_Database.Query(callback, query, data);
}

void CreateInvite(int clanId, const char[] steamid64, const char[] inviter, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedInviter[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(inviter, escapedInviter, sizeof(escapedInviter));

    char query[384];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_invites (clan_id, steamid64, invited_by, expires_at) VALUES (%d, '%s', '%s', %d)",
        clanId,
        escapedSteam,
        escapedInviter,
        GetTime() + INVITE_EXPIRE_SECONDS);
    g_Database.Query(callback, query, data);
}

void DeleteInvite(int inviteId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE id = %d", inviteId);
    g_Database.Query(callback, query, data);
}

void GetPendingInvites(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id, c.name, c.tag, i.invited_by, i.expires_at "
        ... "FROM clan_invites i "
        ... "INNER JOIN clans c ON c.id = i.clan_id "
        ... "WHERE i.steamid64 = '%s' AND i.expires_at > %d "
        ... "ORDER BY i.expires_at ASC",
        escapedSteam,
        GetTime());
    g_Database.Query(callback, query, data);
}

void NormalizeClanWarPair(int firstClanId, int secondClanId, int &clanIdA, int &clanIdB)
{
    if (firstClanId <= secondClanId)
    {
        clanIdA = firstClanId;
        clanIdB = secondClanId;
        return;
    }

    clanIdA = secondClanId;
    clanIdB = firstClanId;
}

void ResetActiveWarCache()
{
    g_bActiveWarCacheReady = false;

    if (g_hActiveWars == null)
    {
        g_hActiveWars = new ArrayList(sizeof(ActiveClanWar));
        return;
    }

    g_hActiveWars.Clear();
}

int FindActiveWarIndexByWarId(int warId)
{
    if (g_hActiveWars == null || warId <= 0)
    {
        return -1;
    }

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.warId == warId)
        {
            return i;
        }
    }

    return -1;
}

int FindActiveWarIndexByClan(int clanId)
{
    if (g_hActiveWars == null || clanId <= 0)
    {
        return -1;
    }

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending)
        {
            continue;
        }

        if (war.clanIdA == clanId || war.clanIdB == clanId)
        {
            return i;
        }
    }

    return -1;
}

int FindActiveWarIndexByPair(int firstClanId, int secondClanId)
{
    if (g_hActiveWars == null || firstClanId <= 0 || secondClanId <= 0 || firstClanId == secondClanId)
    {
        return -1;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(firstClanId, secondClanId, clanIdA, clanIdB);

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending)
        {
            continue;
        }

        if (war.clanIdA == clanIdA && war.clanIdB == clanIdB)
        {
            return i;
        }
    }

    return -1;
}

bool GetActiveClanWarForClanCached(int clanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!g_bActiveWarCacheReady)
    {
        return false;
    }

    int index = FindActiveWarIndexByClan(clanId);
    if (index == -1)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    warId = war.warId;
    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;
    return true;
}

bool GetActiveClanWarByPairCached(int firstClanId, int secondClanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!g_bActiveWarCacheReady)
    {
        return false;
    }

    int index = FindActiveWarIndexByPair(firstClanId, secondClanId);
    if (index == -1)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    warId = war.warId;
    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;
    return true;
}

bool ClanWarsRuntimeReady()
{
    return g_cvClanWarsEnabled != null
        && g_cvClanWarsEnabled.BoolValue
        && g_Database != null
        && g_bDatabaseReady
        && g_bActiveWarCacheReady
        && g_hActiveWars != null;
}

bool EnsureClanWarsAvailable(int client = 0)
{
    if (ClanWarsRuntimeReady())
    {
        return true;
    }

    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Clan wars are temporarily unavailable.");
    }
    return false;
}

bool PopulateActiveWarLabels(ActiveClanWar war)
{
    char clanNameA[CLAN_NAME_MAXLEN + 1];
    char clanTagA[CLAN_TAG_STORE_MAXLEN];
    char ownerNameA[MAX_NAME_LENGTH * 2];
    char clanNameB[CLAN_NAME_MAXLEN + 1];
    char clanTagB[CLAN_TAG_STORE_MAXLEN];
    char ownerNameB[MAX_NAME_LENGTH * 2];
    int memberCount = 0;

    war.announceLabelA[0] = '\0';
    war.announceLabelB[0] = '\0';
    war.historyLabelA[0] = '\0';
    war.historyLabelB[0] = '\0';

    if (!GetClanInfoSummarySync(war.clanIdA, clanNameA, sizeof(clanNameA), clanTagA, sizeof(clanTagA), ownerNameA, sizeof(ownerNameA), memberCount))
    {
        FormatEx(war.announceLabelA, sizeof(war.announceLabelA), "[%d]", war.clanIdA);
        FormatEx(war.historyLabelA, sizeof(war.historyLabelA), "[%d]", war.clanIdA);
        return false;
    }

    if (!GetClanInfoSummarySync(war.clanIdB, clanNameB, sizeof(clanNameB), clanTagB, sizeof(clanTagB), ownerNameB, sizeof(ownerNameB), memberCount))
    {
        BuildClanWarTagLabel(clanTagA, clanNameA, war.announceLabelA, sizeof(war.announceLabelA));
        BuildClanHistoryTagLabel(clanTagA, clanNameA, war.historyLabelA, sizeof(war.historyLabelA));
        FormatEx(war.announceLabelB, sizeof(war.announceLabelB), "[%d]", war.clanIdB);
        FormatEx(war.historyLabelB, sizeof(war.historyLabelB), "[%d]", war.clanIdB);
        return false;
    }

    BuildClanWarTagLabel(clanTagA, clanNameA, war.announceLabelA, sizeof(war.announceLabelA));
    BuildClanWarTagLabel(clanTagB, clanNameB, war.announceLabelB, sizeof(war.announceLabelB));
    BuildClanHistoryTagLabel(clanTagA, clanNameA, war.historyLabelA, sizeof(war.historyLabelA));
    BuildClanHistoryTagLabel(clanTagB, clanNameB, war.historyLabelB, sizeof(war.historyLabelB));
    return true;
}

void UpsertActiveWarCacheEntry(int warId, int clanIdA, int clanIdB, int scoreA, int scoreB, int createdAt, int expiresAt, int instanceId = 0)
{
    if (warId <= 0 || clanIdA <= 0 || clanIdB <= 0)
    {
        return;
    }

    if (g_hActiveWars == null)
    {
        g_hActiveWars = new ArrayList(sizeof(ActiveClanWar));
    }

    int index = FindActiveWarIndexByWarId(warId);
    if (index == -1)
    {
        index = FindActiveWarIndexByPair(clanIdA, clanIdB);
    }

    ActiveClanWar war;
    if (index != -1)
    {
        g_hActiveWars.GetArray(index, war);
    }

    war.warId = warId;
    if (instanceId > 0)
    {
        war.instanceId = instanceId;
    }
    war.clanIdA = clanIdA;
    war.clanIdB = clanIdB;
    war.scoreA = scoreA;
    war.scoreB = scoreB;
    war.createdAt = createdAt;
    war.expiresAt = expiresAt;
    war.writeDirty = false;
    war.writePending = false;
    war.finalizePending = false;
    war.finalizeWritePending = false;
    war.finalizeWinnerClanId = 0;
    war.finalizeStatus = ClanWarStatus_Active;
    war.finalizeFinishedAt = 0;
    PopulateActiveWarLabels(war);

    if (index == -1)
    {
        g_hActiveWars.PushArray(war);
    }
    else
    {
        g_hActiveWars.SetArray(index, war);
    }
}

void RemoveActiveWarCacheIndex(int index)
{
    if (g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return;
    }

    g_hActiveWars.Erase(index);
}

bool DispatchActiveWarScoreWrite(int index)
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);

    if (war.finalizePending || !war.writeDirty || war.writePending)
    {
        return true;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_wars SET score_a = %d, score_b = %d, expires_at = %d "
        ... "WHERE id = %d AND created_at = %d AND status = %d",
        war.scoreA,
        war.scoreB,
        war.expiresAt,
        war.warId,
        war.createdAt,
        view_as<int>(ClanWarStatus_Active));

    DataPack pack = new DataPack();
    pack.WriteCell(war.warId);
    pack.WriteCell(war.createdAt);
    pack.WriteCell(war.scoreA);
    pack.WriteCell(war.scoreB);
    pack.WriteCell(war.expiresAt);
    pack.WriteCell(war.instanceId);

    war.writePending = true;
    g_hActiveWars.SetArray(index, war);
    g_Database.Query(SQL_OnActiveWarScoreWrite, query, pack);
    return true;
}

public void SQL_OnActiveWarScoreWrite(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    int scoreA = pack.ReadCell();
    int scoreB = pack.ReadCell();
    int expiresAt = pack.ReadCell();
    int instanceId = pack.ReadCell();
    delete pack;

    bool saved = (!error[0] && results != null && results.AffectedRows > 0);

    int index = FindActiveWarIndexByWarId(warId);
    if (index != -1)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(index, war);
        if (war.createdAt == createdAt)
        {
            war.writePending = false;
            if (saved && war.scoreA == scoreA && war.scoreB == scoreB && war.expiresAt == expiresAt)
            {
                war.writeDirty = false;
            }
            else
            {
                war.writeDirty = true;
            }
            g_hActiveWars.SetArray(index, war);
        }
    }

    if (error[0])
    {
        LogError("[Clans] Failed to persist war %d score snapshot: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
    }
    else if (!saved)
    {
        LogError("[Clans] Failed to persist war %d score snapshot: no active row matched id=%d created_at=%d", warId, warId, createdAt);
    }
    else
    {
        DispatchClanWarInstanceScoreWrite(instanceId, createdAt, scoreA, scoreB);
    }
}

void DispatchClanWarInstanceScoreWrite(int instanceId, int createdAt, int scoreA, int scoreB)
{
    if (!EnsureDatabaseReady() || g_Database == null || instanceId <= 0)
    {
        return;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "UPDATE clan_war_instances SET score_a = %d, score_b = %d WHERE id = %d AND created_at = %d AND status = %d",
        scoreA,
        scoreB,
        instanceId,
        createdAt,
        view_as<int>(ClanWarStatus_Active));

    g_Database.Query(SQL_OnClanWarInstanceScoreWrite, query, instanceId);
}

public void SQL_OnClanWarInstanceScoreWrite(Database db, DBResultSet results, const char[] error, any data)
{
    int instanceId = data;

    if (error[0])
    {
        LogError("[Clans] Failed to persist war instance %d score snapshot: %s", instanceId, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    if (results == null || results.AffectedRows <= 0)
    {
        LogError("[Clans] Failed to persist war instance %d score snapshot: no active instance row matched", instanceId);
    }
}

void FlushPendingActiveWarWrites()
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null)
    {
        return;
    }

    for (int i = g_hActiveWars.Length - 1; i >= 0; i--)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(i, war);

        if (war.finalizePending)
        {
            DispatchFinalizeActiveWarWrite(i);
            continue;
        }

        DispatchActiveWarScoreWrite(i);
    }
}

bool DispatchFinalizeActiveWarWrite(int index)
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);

    if (!war.finalizePending || war.finalizeWritePending)
    {
        return true;
    }

    char winnerValue[16];
    if (war.finalizeWinnerClanId > 0)
    {
        IntToString(war.finalizeWinnerClanId, winnerValue, sizeof(winnerValue));
    }
    else
    {
        strcopy(winnerValue, sizeof(winnerValue), "NULL");
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_wars SET score_a = %d, score_b = %d, winner_clan_id = %s, status = %d, finished_at = %d "
        ... "WHERE id = %d AND created_at = %d",
        war.scoreA,
        war.scoreB,
        winnerValue,
        view_as<int>(war.finalizeStatus),
        war.finalizeFinishedAt,
        war.warId,
        war.createdAt);

    DataPack pack = new DataPack();
    pack.WriteCell(war.warId);
    pack.WriteCell(war.createdAt);

    war.finalizeWritePending = true;
    g_hActiveWars.SetArray(index, war);
    g_Database.Query(SQL_OnFinalizeActiveWarWrite, query, pack);
    return true;
}

public void SQL_OnFinalizeActiveWarWrite(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int index = FindActiveWarIndexByWarId(warId);

    if (error[0])
    {
        LogError("[Clans] Failed to finalize war %d: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
        if (index != -1)
        {
            ActiveClanWar war;
            g_hActiveWars.GetArray(index, war);
            if (war.createdAt == createdAt)
            {
                war.finalizeWritePending = false;
                war.finalizePending = true;
                g_hActiveWars.SetArray(index, war);
            }
        }
        return;
    }

    if (index != -1)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(index, war);
        if (war.createdAt == createdAt)
        {
            RemoveActiveWarCacheIndex(index);
        }
    }
}

void FlushPendingClanWarPersistenceSync()
{
    FlushPendingActiveWarWrites();
    FlushPendingClanWarKillWritesSync();
}

bool LoadActiveClanWarsCacheSync()
{
    ResetActiveWarCache();

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b, created_at, expires_at "
        ... "FROM clan_wars WHERE status = %d",
        view_as<int>(ClanWarStatus_Active));

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to load active war cache: %s", error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    ArrayList pendingWars = new ArrayList(sizeof(ActiveClanWar));
    ActiveClanWar loadedWar;
    while (results.FetchRow())
    {
        loadedWar.warId = results.FetchInt(0);
        loadedWar.instanceId = 0;
        loadedWar.clanIdA = results.FetchInt(1);
        loadedWar.clanIdB = results.FetchInt(2);
        loadedWar.scoreA = results.FetchInt(3);
        loadedWar.scoreB = results.FetchInt(4);
        loadedWar.createdAt = results.FetchInt(5);
        loadedWar.expiresAt = results.FetchInt(6);
        loadedWar.writeDirty = false;
        loadedWar.writePending = false;
        loadedWar.finalizePending = false;
        loadedWar.finalizeWritePending = false;
        loadedWar.finalizeWinnerClanId = 0;
        loadedWar.finalizeStatus = ClanWarStatus_Active;
        loadedWar.finalizeFinishedAt = 0;
        loadedWar.announceLabelA[0] = '\0';
        loadedWar.announceLabelB[0] = '\0';
        loadedWar.historyLabelA[0] = '\0';
        loadedWar.historyLabelB[0] = '\0';
        pendingWars.PushArray(loadedWar);
    }

    delete results;

    for (int i = 0; i < pendingWars.Length; i++)
    {
        pendingWars.GetArray(i, loadedWar);
        int instanceId = 0;
        if (!EnsureClanWarInstanceSync(loadedWar.warId, loadedWar.clanIdA, loadedWar.clanIdB, loadedWar.createdAt, instanceId)
            && (!EnsureDatabaseReady() || g_Database == null))
        {
            delete pendingWars;
            ResetActiveWarCache();
            return false;
        }
        UpsertActiveWarCacheEntry(loadedWar.warId, loadedWar.clanIdA, loadedWar.clanIdB, loadedWar.scoreA, loadedWar.scoreB, loadedWar.createdAt, loadedWar.expiresAt, instanceId);
    }

    delete pendingWars;
    g_bActiveWarCacheReady = true;
    return true;
}

bool EnsureActiveWarCacheEntryForWarIdSync(int warId, int &index)
{
    index = FindActiveWarIndexByWarId(warId);
    if (index != -1)
    {
        return true;
    }

    if (!EnsureDatabaseReady() || warId <= 0)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b, created_at, expires_at "
        ... "FROM clan_wars WHERE id = %d AND status = %d LIMIT 1",
        warId,
        view_as<int>(ClanWarStatus_Active));

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to hydrate active war cache for id %d: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    int loadedWarId = results.FetchInt(0);
    int clanIdA = results.FetchInt(1);
    int clanIdB = results.FetchInt(2);
    int scoreA = results.FetchInt(3);
    int scoreB = results.FetchInt(4);
    int createdAt = results.FetchInt(5);
    int expiresAt = results.FetchInt(6);
    int instanceId = 0;
    EnsureClanWarInstanceSync(loadedWarId, clanIdA, clanIdB, createdAt, instanceId);

    UpsertActiveWarCacheEntry(
        loadedWarId,
        clanIdA,
        clanIdB,
        scoreA,
        scoreB,
        createdAt,
        expiresAt,
        instanceId);

    delete results;
    index = FindActiveWarIndexByWarId(warId);
    return (index != -1);
}

void BuildPlainClanTag(const char[] storedTag, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (!storedTag[0])
    {
        return;
    }

    char rawTag[CLAN_TAG_STORE_MAXLEN];
    ExtractRawClanTag(storedTag, rawTag, sizeof(rawTag));
    CRemoveTags(rawTag, sizeof(rawTag));
    TrimString(rawTag);

    if (!rawTag[0])
    {
        return;
    }

    FormatEx(buffer, maxlen, "[%s]", rawTag);
}

void BuildClanWarTagLabel(const char[] storedTag, const char[] clanName, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (storedTag[0])
    {
        BuildClanDisplayTag(storedTag, buffer, maxlen);
        return;
    }

    strcopy(buffer, maxlen, clanName);
}

void BuildClanHistoryTagLabel(const char[] storedTag, const char[] clanName, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (storedTag[0])
    {
        BuildPlainClanTag(storedTag, buffer, maxlen);
        if (buffer[0])
        {
            return;
        }
    }

    strcopy(buffer, maxlen, clanName);
    CRemoveTags(buffer, maxlen);
    TrimString(buffer);
}

void BuildClanWarHistorySummary(int viewerClanId, int clanIdA, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status, const char[] clanNameA, const char[] clanTagA, const char[] clanNameB, const char[] clanTagB, char[] buffer, int maxlen)
{
    char labelA[96];
    char labelB[96];
    BuildClanHistoryTagLabel(clanTagA, clanNameA, labelA, sizeof(labelA));
    BuildClanHistoryTagLabel(clanTagB, clanNameB, labelB, sizeof(labelB));

    bool viewerIsClanA = (viewerClanId == clanIdA);
    int ownScore = viewerIsClanA ? scoreA : scoreB;
    int otherScore = viewerIsClanA ? scoreB : scoreA;

    char opponentLabel[96];
    if (viewerIsClanA)
    {
        strcopy(opponentLabel, sizeof(opponentLabel), labelB);
    }
    else
    {
        strcopy(opponentLabel, sizeof(opponentLabel), labelA);
    }

    if (status == ClanWarStatus_Active)
    {
        FormatEx(buffer, maxlen, "Active vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (status == ClanWarStatus_Expired)
    {
        FormatEx(buffer, maxlen, "Expired vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (status == ClanWarStatus_Surrendered)
    {
        if (winnerClanId == viewerClanId)
        {
            FormatEx(buffer, maxlen, "Won by surrender vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        }
        else
        {
            FormatEx(buffer, maxlen, "Surrendered to %s (%d-%d)", opponentLabel, ownScore, otherScore);
        }
        return;
    }

    if (winnerClanId == viewerClanId)
    {
        FormatEx(buffer, maxlen, "Won vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (winnerClanId > 0)
    {
        FormatEx(buffer, maxlen, "Lost vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    FormatEx(buffer, maxlen, "War vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
}

void ShowClanWarHistoryDetailsMenu(int client, int clanId, const char[] clanName, int warInstanceId)
{
    if (client <= 0 || !IsClientInGame(client) || warInstanceId <= 0 || !EnsureDatabaseReady(client))
    {
        return;
    }

    g_iClanHistoryMenuClanId[client] = clanId;
    strcopy(g_sClanHistoryMenuClanName[client], sizeof(g_sClanHistoryMenuClanName[]), clanName);

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id_a, i.clan_id_b, "
        ... "COALESCE(w.score_a, i.score_a), COALESCE(w.score_b, i.score_b), "
        ... "COALESCE(w.winner_clan_id, COALESCE(i.winner_clan_id, 0)), "
        ... "COALESCE(w.status, i.status), i.created_at, COALESCE(w.finished_at, COALESCE(i.finished_at, 0)), "
        ... "COALESCE(ca.name, ''), COALESCE(ca.tag, ''), COALESCE(cb.name, ''), COALESCE(cb.tag, '') "
        ... "FROM clan_war_instances i "
        ... "LEFT JOIN clan_wars w ON w.id = i.war_id AND w.created_at = i.created_at AND w.status = %d "
        ... "LEFT JOIN clans ca ON ca.id = i.clan_id_a "
        ... "LEFT JOIN clans cb ON cb.id = i.clan_id_b "
        ... "WHERE i.id = %d AND (i.clan_id_a = %d OR i.clan_id_b = %d) "
        ... "LIMIT 1",
        view_as<int>(ClanWarStatus_Active),
        warInstanceId,
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war detail query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load war details.");
        delete results;
        return;
    }

    if (!results.FetchRow())
    {
        PrintToChat(client, "[Clans] That war could not be found.");
        delete results;
        return;
    }

    int clanIdA = results.FetchInt(1);
    int scoreA = results.FetchInt(3);
    int scoreB = results.FetchInt(4);
    int winnerClanId = results.FetchInt(5);
    ClanWarStatus status = view_as<ClanWarStatus>(results.FetchInt(6));
    int createdAt = results.FetchInt(7);
    int finishedAt = results.FetchInt(8);

    char clanNameA[CLAN_NAME_MAXLEN + 1];
    char clanTagA[CLAN_TAG_STORE_MAXLEN];
    char clanNameB[CLAN_NAME_MAXLEN + 1];
    char clanTagB[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(9, clanNameA, sizeof(clanNameA));
    results.FetchString(10, clanTagA, sizeof(clanTagA));
    results.FetchString(11, clanNameB, sizeof(clanNameB));
    results.FetchString(12, clanTagB, sizeof(clanTagB));
    delete results;

    char summary[192];
    char startedText[32];
    char finishedText[32];
    BuildClanWarHistorySummary(clanId, clanIdA, scoreA, scoreB, winnerClanId, status, clanNameA, clanTagA, clanNameB, clanTagB, summary, sizeof(summary));
    FormatTime(startedText, sizeof(startedText), "%Y-%m-%d %H:%M", createdAt);
    if (finishedAt > 0)
    {
        FormatTime(finishedText, sizeof(finishedText), "%Y-%m-%d %H:%M", finishedAt);
    }
    else
    {
        strcopy(finishedText, sizeof(finishedText), "Ongoing");
    }

    Menu menu = new Menu(MenuHandler_ClanWarHistoryDetails);
    char title[192];
    char line[192];
    FormatEx(title, sizeof(title), "War Details\n%s", clanName);
    menu.SetTitle(title);

    FormatEx(line, sizeof(line), "Summary: %s", summary);
    menu.AddItem("summary", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Started: %s", startedText);
    menu.AddItem("started", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Finished: %s", finishedText);
    menu.AddItem("finished", line, ITEMDRAW_DISABLED);

    menu.AddItem("top5", "Top 5 Kills", ITEMDRAW_DISABLED);

    FormatEx(query, sizeof(query),
        "SELECT wk.steamid64, wk.clan_id, wk.kills, COALESCE(wk.currency_stolen, 0), COALESCE(c.name, ''), COALESCE(c.tag, '') "
        ... "FROM clan_war_member_kills wk "
        ... "LEFT JOIN clans c ON c.id = wk.clan_id "
        ... "WHERE wk.war_instance_id = %d "
        ... "ORDER BY wk.kills DESC, wk.clan_id ASC, wk.steamid64 ASC "
        ... "LIMIT 5",
        warInstanceId);

    results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war leader query failed: %s", error);
        delete results;
        menu.AddItem("leaders_error", "Failed to load kill leaders", ITEMDRAW_DISABLED);
    }
    else
    {
        bool addedLeaders = false;
        int place = 1;
        while (results.FetchRow())
        {
            char steamid64[STEAMID64_MAXLEN];
            char leaderClanName[CLAN_NAME_MAXLEN + 1];
            char leaderClanTag[CLAN_TAG_STORE_MAXLEN];
            char clanLabel[96];
            char playerName[MAX_NAME_LENGTH * 2];

            results.FetchString(0, steamid64, sizeof(steamid64));
            results.FetchString(4, leaderClanName, sizeof(leaderClanName));
            results.FetchString(5, leaderClanTag, sizeof(leaderClanTag));
            BuildClanHistoryTagLabel(leaderClanTag, leaderClanName, clanLabel, sizeof(clanLabel));
            ResolvePlayerDisplayName(steamid64, playerName, sizeof(playerName));

            if (clanLabel[0])
            {
                FormatEx(line, sizeof(line), "%d. %s %s - %d kills, %d Gems stolen", place, clanLabel, playerName, results.FetchInt(2), results.FetchInt(3));
            }
            else
            {
                FormatEx(line, sizeof(line), "%d. %s - %d kills, %d Gems stolen", place, playerName, results.FetchInt(2), results.FetchInt(3));
            }

            menu.AddItem("leader", line, ITEMDRAW_DISABLED);
            place++;
            addedLeaders = true;
        }
        delete results;

        if (!addedLeaders)
        {
            menu.AddItem("leaders_none", "No tracked kills yet", ITEMDRAW_DISABLED);
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, CLAN_MENU_TIME);
}

void ShowClanHistoryMenu(int client, int clanId, const char[] clanName)
{
    if (client <= 0 || !IsClientInGame(client) || clanId <= 0 || !EnsureDatabaseReady(client))
    {
        return;
    }

    g_iClanHistoryMenuClanId[client] = clanId;
    strcopy(g_sClanHistoryMenuClanName[client], sizeof(g_sClanHistoryMenuClanName[]), clanName);

    Menu menu = new Menu(MenuHandler_ClanHistory);
    char title[192];
    char line[320];
    char query[1024];
    char timestamp[32];
    FormatEx(title, sizeof(title), "Clan History\n%s", clanName);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    bool added = false;

    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id_a, i.clan_id_b, "
        ... "COALESCE(w.score_a, i.score_a), COALESCE(w.score_b, i.score_b), "
        ... "COALESCE(w.winner_clan_id, COALESCE(i.winner_clan_id, 0)), "
        ... "COALESCE(w.status, i.status), i.created_at, COALESCE(w.finished_at, COALESCE(i.finished_at, 0)), "
        ... "COALESCE(ca.name, ''), COALESCE(ca.tag, ''), COALESCE(cb.name, ''), COALESCE(cb.tag, '') "
        ... "FROM clan_war_instances i "
        ... "LEFT JOIN clan_wars w ON w.id = i.war_id AND w.created_at = i.created_at AND w.status = %d "
        ... "LEFT JOIN clans ca ON ca.id = i.clan_id_a "
        ... "LEFT JOIN clans cb ON cb.id = i.clan_id_b "
        ... "WHERE i.clan_id_a = %d OR i.clan_id_b = %d "
        ... "ORDER BY CASE WHEN w.id IS NOT NULL THEN i.created_at ELSE COALESCE(i.finished_at, i.created_at) END DESC, i.id DESC "
        ... "LIMIT 100",
        view_as<int>(ClanWarStatus_Active),
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war history query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan history.");
        delete results;
        delete menu;
        return;
    }

    bool addedWars = false;
    while (results.FetchRow())
    {
        if (!addedWars)
        {
            menu.AddItem("wars_header", "Wars", ITEMDRAW_DISABLED);
            addedWars = true;
        }

        char clanNameA[CLAN_NAME_MAXLEN + 1];
        char clanTagA[CLAN_TAG_STORE_MAXLEN];
        char clanNameB[CLAN_NAME_MAXLEN + 1];
        char clanTagB[CLAN_TAG_STORE_MAXLEN];
        char summary[192];
        char info[32];

        results.FetchString(9, clanNameA, sizeof(clanNameA));
        results.FetchString(10, clanTagA, sizeof(clanTagA));
        results.FetchString(11, clanNameB, sizeof(clanNameB));
        results.FetchString(12, clanTagB, sizeof(clanTagB));
        BuildClanWarHistorySummary(
            clanId,
            results.FetchInt(1),
            results.FetchInt(3),
            results.FetchInt(4),
            results.FetchInt(5),
            view_as<ClanWarStatus>(results.FetchInt(6)),
            clanNameA,
            clanTagA,
            clanNameB,
            clanTagB,
            summary,
            sizeof(summary));

        int displayTime = results.FetchInt(8);
        if (displayTime <= 0)
        {
            displayTime = results.FetchInt(7);
        }
        FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%d", displayTime);
        FormatEx(line, sizeof(line), "%s - %s", timestamp, summary);
        FormatEx(info, sizeof(info), "war:%d", results.FetchInt(0));
        menu.AddItem(info, line);
        added = true;
    }
    delete results;

    FormatEx(query, sizeof(query),
        "SELECT summary, created_at FROM clan_history WHERE clan_id = %d ORDER BY created_at DESC, id DESC LIMIT 100",
        clanId);

    results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan history query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan history.");
        delete results;
        delete menu;
        return;
    }

    bool addedActivity = false;
    char summary[CLAN_HISTORY_SUMMARY_MAXLEN + 1];
    while (results.FetchRow())
    {
        if (!addedActivity)
        {
            menu.AddItem("activity_header", "Activity", ITEMDRAW_DISABLED);
            addedActivity = true;
        }

        results.FetchString(0, summary, sizeof(summary));
        FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%d", results.FetchInt(1));
        FormatEx(line, sizeof(line), "%s - %s", timestamp, summary);
        menu.AddItem("history", line, ITEMDRAW_DISABLED);
        added = true;
    }
    delete results;

    if (!added)
    {
        menu.AddItem("none", "No clan history yet", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

void BuildWarPlayerLabel(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char displayName[384];
    BuildClanChatSenderName(client, displayName, sizeof(displayName));

    char steamid64[STEAMID64_MAXLEN];
    char selectedTag[256];
    char displayTag[256];
    if (GetClientSteam64(client, steamid64, sizeof(steamid64))
        && TryGetSelectedTag(client, steamid64, selectedTag, sizeof(selectedTag)))
    {
        BuildClanDisplayTag(selectedTag, displayTag, sizeof(displayTag));
        if (displayTag[0])
        {
            FormatEx(buffer, maxlen, "%s %s", displayTag, displayName);
            ResolveClientTeamColorTag(client, buffer, maxlen);
            return;
        }
    }

    strcopy(buffer, maxlen, displayName);
    ResolveClientTeamColorTag(client, buffer, maxlen);
}

bool GetClanInfoSummarySync(int clanId, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen, char[] ownerName, int ownerNameLen, int &memberCount)
{
    clanName[0] = '\0';
    clanTag[0] = '\0';
    ownerName[0] = '\0';
    memberCount = 0;

    if (!EnsureDatabaseReady() || clanId <= 0)
    {
        return false;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.name, COALESCE(c.tag, ''), c.owner, ("
        ... "SELECT COUNT(1) FROM clan_members cm WHERE cm.clan_id = c.id"
        ... ") + ("
        ... "SELECT COUNT(1) "
        ... "FROM clan_members cm_child "
        ... "INNER JOIN clan_relations cr ON cr.clan_id_a = cm_child.clan_id "
        ... "WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id"
        ... ") AS member_count "
        ... "FROM clans c "
        ... "WHERE c.id = %d "
        ... "LIMIT 1",
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan summary for %d: %s", clanId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    char ownerSteam[STEAMID64_MAXLEN];
    results.FetchString(0, clanName, clanNameLen);
    results.FetchString(1, clanTag, clanTagLen);
    results.FetchString(2, ownerSteam, sizeof(ownerSteam));
    memberCount = results.FetchInt(3);
    delete results;

    ResolvePlayerDisplayName(ownerSteam, ownerName, ownerNameLen);
    return true;
}

bool GetClientClanContextSync(int client, char[] steamid64, int steamidLen, int &clanId, ClanRank &rank, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen)
{
    steamid64[0] = '\0';
    clanId = 0;
    rank = ClanRank_Member;
    clanName[0] = '\0';
    clanTag[0] = '\0';

    if (!EnsureDatabaseReady() || !GetClientSteam64(client, steamid64, steamidLen))
    {
        return false;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, COALESCE(c.tag, ''), cm.rank "
        ... "FROM clans c "
        ... "INNER JOIN clan_members cm ON cm.clan_id = c.id "
        ... "WHERE cm.steamid64 = '%s' "
        ... "LIMIT 1",
        escapedSteam);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch client clan context for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return true;
    }

    clanId = results.FetchInt(0);
    results.FetchString(1, clanName, clanNameLen);
    results.FetchString(2, clanTag, clanTagLen);
    rank = view_as<ClanRank>(results.FetchInt(3));
    delete results;
    return true;
}

bool GetActiveClanWarForClanSync(int clanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    if (GetActiveClanWarForClanCached(clanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        return true;
    }

    if (g_bActiveWarCacheReady)
    {
        return false;
    }

    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!EnsureDatabaseReady() || clanId <= 0)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b "
        ... "FROM clan_wars "
        ... "WHERE status = %d AND expires_at > %d AND (clan_id_a = %d OR clan_id_b = %d) "
        ... "LIMIT 1",
        view_as<int>(ClanWarStatus_Active),
        GetTime(),
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch active war for clan %d: %s", clanId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    warId = results.FetchInt(0);
    clanIdA = results.FetchInt(1);
    clanIdB = results.FetchInt(2);
    scoreA = results.FetchInt(3);
    scoreB = results.FetchInt(4);
    delete results;
    return (warId > 0);
}

int GetPendingClanWarStolenTotal(int warInstanceId, int clanId)
{
    if (g_hPendingClanWarKillDeltas == null || warInstanceId <= 0 || clanId <= 0)
    {
        return 0;
    }

    int total = 0;
    PendingClanWarKillDelta delta;
    for (int i = 0; i < g_hPendingClanWarKillDeltas.Length; i++)
    {
        g_hPendingClanWarKillDeltas.GetArray(i, delta);
        if (delta.warInstanceId == warInstanceId && delta.clanId == clanId)
        {
            total += delta.currencyStolen;
        }
    }

    return total;
}

int GetClanWarStolenTotalSync(int warInstanceId, int clanId)
{
    int total = GetPendingClanWarStolenTotal(warInstanceId, clanId);
    if (!EnsureDatabaseReady() || warInstanceId <= 0 || clanId <= 0)
    {
        return total;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(SUM(currency_stolen), 0) FROM clan_war_member_kills WHERE war_instance_id = %d AND clan_id = %d",
        warInstanceId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan war stolen total: %s", error);
        delete results;
        return total;
    }

    if (results.FetchRow())
    {
        total += results.FetchInt(0);
    }
    delete results;
    return total;
}

bool GetClanWarRedeclareCooldownSync(int declaringClanId, int targetClanId, int &secondsLeft)
{
    secondsLeft = 0;
    if (!EnsureDatabaseReady() || declaringClanId <= 0 || targetClanId <= 0 || declaringClanId == targetClanId)
    {
        return false;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(declaringClanId, targetClanId, clanIdA, clanIdB);

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(finished_at, 0) FROM clan_wars WHERE clan_id_a = %d AND clan_id_b = %d LIMIT 1",
        clanIdA,
        clanIdB);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan war redeclare cooldown for pair %d/%d: %s", clanIdA, clanIdB, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    int finishedAt = results.FetchInt(0);
    delete results;

    if (finishedAt <= 0)
    {
        return false;
    }

    secondsLeft = (finishedAt + CLAN_WAR_REDECLARE_COOLDOWN_SECONDS) - GetTime();
    return secondsLeft > 0;
}

void GetClanWarTargetCooldownLabel(int targetClanId, char[] buffer, int maxlen)
{
    if (targetClanId <= 0 || maxlen <= 0)
    {
        return;
    }

    buffer[0] = '\0';

    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char representativeName[MAX_NAME_LENGTH * 2];
    int onlineCount = 0;
    if (GetCachedOnlineClanSummary(targetClanId, clanName, sizeof(clanName), clanTag, sizeof(clanTag), representativeName, sizeof(representativeName), onlineCount))
    {
        BuildClanDisplayTag(clanTag, buffer, maxlen);
        if (!buffer[0])
        {
            strcopy(buffer, maxlen, clanName);
        }
        return;
    }

    FormatEx(clanName, sizeof(clanName), "%d", targetClanId);
    clanTag[0] = '\0';

    if (EnsureDatabaseReady())
    {
        char query[128];
        FormatEx(query, sizeof(query), "SELECT name, COALESCE(tag, '') FROM clans WHERE id = %d LIMIT 1", targetClanId);

        DBResultSet results = SQL_Query(g_Database, query);
        if (HasUsableResultSet(results) && results.FetchRow())
        {
            results.FetchString(0, clanName, sizeof(clanName));
            results.FetchString(1, clanTag, sizeof(clanTag));
        }
        delete results;
    }

    BuildClanDisplayTag(clanTag, buffer, maxlen);
    if (!buffer[0])
    {
        strcopy(buffer, maxlen, clanName);
    }
}

void AddClanHistoryEntry(int clanId, const char[] fmt, any ...)
{
    if (clanId <= 0 || !EnsureDatabaseReady())
    {
        return;
    }

    char summary[CLAN_HISTORY_SUMMARY_MAXLEN + 1];
    char escapedSummary[SQL_CLAN_HISTORY_SUMMARY_MAXLEN];
    VFormat(summary, sizeof(summary), fmt, 3);
    CRemoveTags(summary, sizeof(summary));
    TrimString(summary);

    if (!summary[0])
    {
        return;
    }

    EscapeSql(summary, escapedSummary, sizeof(escapedSummary));

    char query[768];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_history (clan_id, summary, created_at) VALUES (%d, '%s', %d)",
        clanId,
        escapedSummary,
        GetTime());

    g_Database.Query(SQL_GenericQueryCallback, query);
}

bool FinalizeClanWarSync(int warId, int clanIdA, int clanIdB, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status)
{
    if (warId <= 0 || clanIdA <= 0 || clanIdB <= 0)
    {
        return false;
    }

    int warIndex = FindActiveWarIndexByWarId(warId);
    if (warIndex == -1 && !EnsureActiveWarCacheEntryForWarIdSync(warId, warIndex))
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(warIndex, war);

    if (war.finalizePending)
    {
        return true;
    }

    char historyLabelA[96];
    char historyLabelB[96];
    char announceLabelA[96];
    char announceLabelB[96];

    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;

    strcopy(historyLabelA, sizeof(historyLabelA), war.historyLabelA);
    strcopy(historyLabelB, sizeof(historyLabelB), war.historyLabelB);
    strcopy(announceLabelA, sizeof(announceLabelA), war.announceLabelA);
    strcopy(announceLabelB, sizeof(announceLabelB), war.announceLabelB);

    if (!historyLabelA[0])
    {
        FormatEx(historyLabelA, sizeof(historyLabelA), "[%d]", clanIdA);
    }
    if (!historyLabelB[0])
    {
        FormatEx(historyLabelB, sizeof(historyLabelB), "[%d]", clanIdB);
    }
    if (!announceLabelA[0])
    {
        FormatEx(announceLabelA, sizeof(announceLabelA), "[%d]", clanIdA);
    }
    if (!announceLabelB[0])
    {
        FormatEx(announceLabelB, sizeof(announceLabelB), "[%d]", clanIdB);
    }

    war.writeDirty = false;
    war.finalizePending = true;
    war.finalizeWritePending = false;
    war.finalizeWinnerClanId = winnerClanId;
    war.finalizeStatus = status;
    war.finalizeFinishedAt = GetTime();
    g_hActiveWars.SetArray(warIndex, war);

    int stolenA = (war.instanceId > 0) ? GetClanWarStolenTotalSync(war.instanceId, clanIdA) : 0;
    int stolenB = (war.instanceId > 0) ? GetClanWarStolenTotalSync(war.instanceId, clanIdB) : 0;

    if (status == ClanWarStatus_Expired)
    {
        AddClanHistoryEntry(clanIdA, "War with %s expired at %d-%d", historyLabelB, scoreA, scoreB);
        AddClanHistoryEntry(clanIdB, "War with %s expired at %d-%d", historyLabelA, scoreB, scoreA);
    }
    else if (winnerClanId == clanIdA)
    {
        AddClanHistoryEntry(clanIdA, "Won war vs %s (%d-%d, %d Gems stolen)", historyLabelB, scoreA, scoreB, stolenA);
        AddClanHistoryEntry(clanIdB, "Lost war vs %s (%d-%d, %d Gems stolen)", historyLabelA, scoreB, scoreA, stolenB);
    }
    else if (winnerClanId == clanIdB)
    {
        AddClanHistoryEntry(clanIdA, "Lost war vs %s (%d-%d, %d Gems stolen)", historyLabelB, scoreA, scoreB, stolenA);
        AddClanHistoryEntry(clanIdB, "Won war vs %s (%d-%d, %d Gems stolen)", historyLabelA, scoreB, scoreA, stolenB);
    }

    if (status == ClanWarStatus_Expired)
    {
        CPrintToChatAll("{gold}[Clans]{default} War between %s and %s expired. Final score: %d-%d", announceLabelA, announceLabelB, scoreA, scoreB);
    }
    else if (winnerClanId == clanIdA)
    {
        CPrintToChatAll("{gold}[Clans]{default} %s won the war against %s! Final score: %d-%d. %s stole {lightgreen}%d Gems{default}!", announceLabelA, announceLabelB, scoreA, scoreB, announceLabelA, stolenA);
    }
    else if (winnerClanId == clanIdB)
    {
        CPrintToChatAll("{gold}[Clans]{default} %s won the war against %s! Final score: %d-%d. %s stole {lightgreen}%d Gems{default}!", announceLabelB, announceLabelA, scoreB, scoreA, announceLabelB, stolenB);
    }

    if (war.instanceId > 0)
    {
        UpdateClanWarInstanceFinalState(war.instanceId, war.scoreA, war.scoreB, winnerClanId, status, war.finalizeFinishedAt);
    }

    if (g_bDatabaseReady)
    {
        FlushPendingClanWarPersistenceSync();
    }

    return true;
}

void BroadcastClanWarScoreUpdate(const char[] scoringLabel, const char[] otherLabel, int scoringClanId, int otherClanId, int scoringScore, int otherScore, int warInstanceId, int attacker, int victim)
{
    if ((scoringScore % 5) != 0)
    {
        return;
    }

    char attackerLabel[512];
    char victimLabel[512];
    BuildWarPlayerLabel(attacker, attackerLabel, sizeof(attackerLabel));
    BuildWarPlayerLabel(victim, victimLabel, sizeof(victimLabel));

    bool stolenAlert = ((scoringScore % 10) == 0);
    bool broadcastOutsiders = stolenAlert;

    int leaderScore = (scoringScore >= otherScore) ? scoringScore : otherScore;
    int trailingScore = (scoringScore >= otherScore) ? otherScore : scoringScore;
    int leaderClanId = (scoringScore >= otherScore) ? scoringClanId : otherClanId;
    int leaderStolen = 0;
    if (stolenAlert && warInstanceId > 0)
    {
        leaderStolen = GetClanWarStolenTotalSync(warInstanceId, leaderClanId);
    }
    char leaderLabel[96];
    char trailingLabel[96];
    strcopy(leaderLabel, sizeof(leaderLabel), (scoringScore >= otherScore) ? scoringLabel : otherLabel);
    strcopy(trailingLabel, sizeof(trailingLabel), (scoringScore >= otherScore) ? otherLabel : scoringLabel);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        bool isParticipant = IsConnectedClientInClan(i, scoringClanId) || IsConnectedClientInClan(i, otherClanId);
        if (!isParticipant && !broadcastOutsiders)
        {
            continue;
        }

        ClansCPrintToChatExWrapped(i, attacker, "%s killed %s!", attackerLabel, victimLabel);
        if (stolenAlert)
        {
            CPrintToChat(i, "{gold}[Clans]{default} %s is beating %s %d-%d and has stolen {lightgreen}%d Gems{default} so far!!!", leaderLabel, trailingLabel, leaderScore, trailingScore, leaderStolen);
        }
        else
        {
            CPrintToChat(i, "{gold}[Clans]{default} %s's score: %d | %s's score: %d", scoringLabel, scoringScore, otherLabel, otherScore);
        }
    }
}

void CleanupExpiredWars()
{
    if (!g_bActiveWarCacheReady || g_hActiveWars == null)
    {
        return;
    }

    int now = GetTime();
    for (int i = g_hActiveWars.Length - 1; i >= 0; i--)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending || war.expiresAt > now)
        {
            continue;
        }

        FinalizeClanWarSync(
            war.warId,
            war.clanIdA,
            war.clanIdB,
            war.scoreA,
            war.scoreB,
            0,
            ClanWarStatus_Expired);
    }
}

bool StartClanWarAsync(int client, int declaringClanId, int targetClanId, const char[] declarerSteam)
{
    if (!EnsureClanWarsAvailable(client) || declaringClanId <= 0 || targetClanId <= 0 || declaringClanId == targetClanId)
    {
        return false;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(declaringClanId, targetClanId, clanIdA, clanIdB);

    int existingWarId = 0;
    int existingClanIdA = 0;
    int existingClanIdB = 0;
    int existingScoreA = 0;
    int existingScoreB = 0;
    if (GetActiveClanWarByPairCached(declaringClanId, targetClanId, existingWarId, existingClanIdA, existingClanIdB, existingScoreA, existingScoreB))
    {
        return false;
    }

    char escapedDeclarer[SQL_STEAMID64_MAXLEN];
    EscapeSql(declarerSteam, escapedDeclarer, sizeof(escapedDeclarer));

    int now = GetTime();
    char query[2048];
    if (IsMySql())
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_wars (clan_id_a, clan_id_b, declared_by, score_a, score_b, winner_clan_id, status, created_at, expires_at, finished_at) "
            ... "VALUES (%d, %d, '%s', 0, 0, NULL, %d, %d, %d, NULL) "
            ... "ON DUPLICATE KEY UPDATE declared_by = IF(status = %d, declared_by, VALUES(declared_by)), score_a = IF(status = %d, score_a, 0), score_b = IF(status = %d, score_b, 0), winner_clan_id = IF(status = %d, winner_clan_id, NULL), created_at = IF(status = %d, created_at, VALUES(created_at)), expires_at = IF(status = %d, expires_at, VALUES(expires_at)), finished_at = IF(status = %d, finished_at, NULL), status = IF(status = %d, status, VALUES(status))",
            clanIdA,
            clanIdB,
            escapedDeclarer,
            view_as<int>(ClanWarStatus_Active),
            now,
            now + CLAN_WAR_EXPIRE_SECONDS,
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active));
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_wars (clan_id_a, clan_id_b, declared_by, score_a, score_b, winner_clan_id, status, created_at, expires_at, finished_at) "
            ... "VALUES (%d, %d, '%s', 0, 0, NULL, %d, %d, %d, NULL) "
            ... "ON CONFLICT(clan_id_a, clan_id_b) DO UPDATE SET declared_by = CASE WHEN status = %d THEN declared_by ELSE excluded.declared_by END, score_a = CASE WHEN status = %d THEN score_a ELSE 0 END, score_b = CASE WHEN status = %d THEN score_b ELSE 0 END, winner_clan_id = CASE WHEN status = %d THEN winner_clan_id ELSE NULL END, created_at = CASE WHEN status = %d THEN created_at ELSE excluded.created_at END, expires_at = CASE WHEN status = %d THEN expires_at ELSE excluded.expires_at END, finished_at = CASE WHEN status = %d THEN finished_at ELSE NULL END, status = CASE WHEN status = %d THEN status ELSE excluded.status END",
            clanIdA,
            clanIdB,
            escapedDeclarer,
            view_as<int>(ClanWarStatus_Active),
            now,
            now + CLAN_WAR_EXPIRE_SECONDS,
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active));
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(declaringClanId);
    pack.WriteCell(targetClanId);
    pack.WriteCell(clanIdA);
    pack.WriteCell(clanIdB);
    pack.WriteCell(now);
    g_Database.Query(SQL_OnStartClanWarUpsert, query, pack);
    return true;
}

public void SQL_OnStartClanWarUpsert(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int declaringClanId = pack.ReadCell();
    int targetClanId = pack.ReadCell();
    int clanIdA = pack.ReadCell();
    int clanIdB = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0])
    {
        LogError("[Clans] Failed to start war between %d and %d: %s", clanIdA, clanIdB, error);
        HandleDatabaseConnectionLoss(error);
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, score_a, score_b, created_at, expires_at, status FROM clan_wars WHERE clan_id_a = %d AND clan_id_b = %d LIMIT 1",
        clanIdA,
        clanIdB);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(declaringClanId);
    next.WriteCell(targetClanId);
    next.WriteCell(clanIdA);
    next.WriteCell(clanIdB);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarSelected, query, next);
}

public void SQL_OnStartClanWarSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int declaringClanId = pack.ReadCell();
    int targetClanId = pack.ReadCell();
    int clanIdA = pack.ReadCell();
    int clanIdB = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0] || results == null || !results.FetchRow())
    {
        if (error[0])
        {
            LogError("[Clans] Failed to fetch newly started war for pair %d/%d: %s", clanIdA, clanIdB, error);
            HandleDatabaseConnectionLoss(error);
        }
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    int warId = results.FetchInt(0);
    int scoreA = results.FetchInt(1);
    int scoreB = results.FetchInt(2);
    int rowCreatedAt = results.FetchInt(3);
    int expiresAt = results.FetchInt(4);
    ClanWarStatus status = view_as<ClanWarStatus>(results.FetchInt(5));

    if (status == ClanWarStatus_Active && rowCreatedAt != createdAt)
    {
        int instanceId = 0;
        EnsureClanWarInstanceSync(warId, clanIdA, clanIdB, rowCreatedAt, instanceId);
        UpsertActiveWarCacheEntry(warId, clanIdA, clanIdB, scoreA, scoreB, rowCreatedAt, expiresAt, instanceId);

        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] These clans are already at war.");
        }
        return;
    }

    if (status != ClanWarStatus_Active || rowCreatedAt != createdAt)
    {
        LogError("[Clans] Unexpected war row state after declaring pair %d/%d: status=%d created_at=%d expected_created_at=%d", clanIdA, clanIdB, view_as<int>(status), rowCreatedAt, createdAt);
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    UpsertActiveWarCacheEntry(warId, clanIdA, clanIdB, 0, 0, createdAt, expiresAt, 0);

    char declaringClanName[CLAN_NAME_MAXLEN + 1];
    char declaringClanTag[CLAN_TAG_STORE_MAXLEN];
    char declaringRepresentative[MAX_NAME_LENGTH * 2];
    char targetClanName[CLAN_NAME_MAXLEN + 1];
    char targetClanTag[CLAN_TAG_STORE_MAXLEN];
    char targetRepresentative[MAX_NAME_LENGTH * 2];
    int onlineCount = 0;

    if (!GetCachedOnlineClanSummary(declaringClanId, declaringClanName, sizeof(declaringClanName), declaringClanTag, sizeof(declaringClanTag), declaringRepresentative, sizeof(declaringRepresentative), onlineCount))
    {
        FormatEx(declaringClanName, sizeof(declaringClanName), "%d", declaringClanId);
        declaringClanTag[0] = '\0';
    }
    if (!GetCachedOnlineClanSummary(targetClanId, targetClanName, sizeof(targetClanName), targetClanTag, sizeof(targetClanTag), targetRepresentative, sizeof(targetRepresentative), onlineCount))
    {
        FormatEx(targetClanName, sizeof(targetClanName), "%d", targetClanId);
        targetClanTag[0] = '\0';
    }

    char declaringHistoryLabel[96];
    char targetHistoryLabel[96];
    char declaringAnnounceLabel[96];
    char targetAnnounceLabel[96];
    BuildClanHistoryTagLabel(declaringClanTag, declaringClanName, declaringHistoryLabel, sizeof(declaringHistoryLabel));
    BuildClanHistoryTagLabel(targetClanTag, targetClanName, targetHistoryLabel, sizeof(targetHistoryLabel));
    BuildClanWarTagLabel(declaringClanTag, declaringClanName, declaringAnnounceLabel, sizeof(declaringAnnounceLabel));
    BuildClanWarTagLabel(targetClanTag, targetClanName, targetAnnounceLabel, sizeof(targetAnnounceLabel));

    AddClanHistoryEntry(declaringClanId, "Declared war on %s", targetHistoryLabel);
    AddClanHistoryEntry(targetClanId, "War declared by %s", declaringHistoryLabel);
    CPrintToChatAll("{gold}[Clans]{default} %s has declared war on %s!", declaringAnnounceLabel, targetAnnounceLabel);

    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] War declared.");
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_war_instances (war_id, clan_id_a, clan_id_b, score_a, score_b, winner_clan_id, status, created_at, finished_at) "
        ... "VALUES (%d, %d, %d, 0, 0, NULL, %d, %d, NULL)",
        warId,
        clanIdA,
        clanIdB,
        view_as<int>(ClanWarStatus_Active),
        createdAt);

    DataPack next = new DataPack();
    next.WriteCell(warId);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarInstanceInserted, query, next);
}

public void SQL_OnStartClanWarInstanceInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Failed to create war instance for %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    char query[192];
    FormatEx(query, sizeof(query), "SELECT id FROM clan_war_instances WHERE war_id = %d AND created_at = %d LIMIT 1", warId, createdAt);

    DataPack next = new DataPack();
    next.WriteCell(warId);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarInstanceSelected, query, next);
}

public void SQL_OnStartClanWarInstanceSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    if (error[0] || results == null || !results.FetchRow())
    {
        if (error[0])
        {
            LogError("[Clans] Failed to fetch war instance for %d/%d: %s", warId, createdAt, error);
            HandleDatabaseConnectionLoss(error);
        }
        return;
    }

    int index = FindActiveWarIndexByWarId(warId);
    if (index == -1)
    {
        return;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    if (war.createdAt == createdAt)
    {
        war.instanceId = results.FetchInt(0);
        g_hActiveWars.SetArray(index, war);
    }
}

void ResolveActiveWarsForDeletedClan(int clanId)
{
    if (g_bActiveWarCacheReady)
    {
        int warIndex = FindActiveWarIndexByClan(clanId);
        while (warIndex != -1)
        {
            ActiveClanWar war;
            g_hActiveWars.GetArray(warIndex, war);

            int winnerClanId = (war.clanIdA == clanId) ? war.clanIdB : war.clanIdA;
            if (!FinalizeClanWarSync(war.warId, war.clanIdA, war.clanIdB, war.scoreA, war.scoreB, winnerClanId, ClanWarStatus_Surrendered))
            {
                break;
            }

            warIndex = FindActiveWarIndexByClan(clanId);
        }
        return;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;

    while (GetActiveClanWarForClanSync(clanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        int winnerClanId = (clanIdA == clanId) ? clanIdB : clanIdA;
        if (!FinalizeClanWarSync(warId, clanIdA, clanIdB, scoreA, scoreB, winnerClanId, ClanWarStatus_Surrendered))
        {
            break;
        }
    }
}

void SetParentRelation(int clanIdA, int clanIdB, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d AND relation_type = 3", clanIdA);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "INSERT INTO clan_relations (clan_id_a, clan_id_b, relation_type, created_at) VALUES (%d, %d, 3, %d)",
        clanIdA,
        clanIdB,
        GetTime());
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteCell(clanIdA);
    pack.WriteCell(clanIdB);

    g_Database.Execute(txn, SQLTxn_OnSetParentSuccess, SQLTxn_OnSetParentFailure, pack);
}

void ClearParentRelation(int clanIdA, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d AND relation_type = 3", clanIdA);
    g_Database.Query(SQL_OnClearParentRelation, query, requesterUserId);
}

public void SQL_GenericQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Clans] SQL query failed: %s", error);
        HandleDatabaseConnectionLoss(error);
    }
}

