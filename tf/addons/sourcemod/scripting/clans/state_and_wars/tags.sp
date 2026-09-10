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

bool IsExportableClanTagText(const char[] text)
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

void ExtractRawClanTag(const char[] storedTag, char[] buffer, int maxlen)
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

