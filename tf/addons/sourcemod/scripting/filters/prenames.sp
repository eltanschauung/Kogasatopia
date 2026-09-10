void Filters_PrenameLoadRules()
{
    if (!g_bDbReady || g_hFiltersDb == null)
    {
        return;
    }

    g_PrenameRulesLoaded = false;
    g_hFiltersDb.Query(Filters_PrenameLoadRulesCallback, "SELECT pattern, newname FROM prename_rules");
}

public void Filters_PrenameLoadRulesCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters/Prename] Failed to load rules: %s", error);
        g_PrenameRulesLoaded = false;
        return;
    }

    if (g_PrenameIdRules != null)
    {
        g_PrenameIdRules.Clear();
    }
    if (g_PrenameOutputMap != null)
    {
        g_PrenameOutputMap.Clear();
    }

    if (results == null)
    {
        g_PrenameRulesLoaded = true;
        Filters_ApplyPrenameToConnectedClients();
        return;
    }

    while (results.FetchRow())
    {
        char pattern[PRENAME_MAX_PATTERN];
        char newname[PRENAME_MAX_RENAME];
        results.FetchString(0, pattern, sizeof(pattern));
        results.FetchString(1, newname, sizeof(newname));

        if (Prename_IsIdString(pattern))
        {
            g_PrenameIdRules.SetString(pattern, newname);
        }
    }

    g_PrenameRulesLoaded = true;
    Filters_ApplyPrenameToConnectedClients();
}

static void Filters_ApplyPrenameToConnectedClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Filters_IsRealClientInGame(client))
        {
            Prename_Apply(client);
        }
    }
}

bool Prename_Apply(int client)
{
    if (!g_bDbReady || g_hFiltersDb == null || g_PrenameIdRules == null)
    {
        return false;
    }

    char currentName[MAX_NAME_LENGTH];
    GetClientName(client, currentName, sizeof(currentName));

    char steam2[32], steam64[32];
    Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));

    char rename[PRENAME_MAX_RENAME];
    if (Prename_TryGetIdRule(steam64, steam2, rename, sizeof(rename)))
    {
        if (!StrEqual(currentName, rename, false))
        {
            SetClientName(client, rename);
        }
        return true;
    }

    return true;
}

public Action Command_Prename(int client, int args)
{
    bool isAdmin = (client <= 0) || CheckCommandAccess(client, "sm_prename_admin", ADMFLAG_SLAY, true);

    if (!isAdmin)
    {
        if (client <= 0 || !IsClientInGame(client))
        {
            return Plugin_Handled;
        }

        if (args < 1)
        {
            ReplyToCommand(client, "[Kogasa] Usage: sm_prename <newname>");
            return Plugin_Handled;
        }

        char selfName[PRENAME_MAX_RENAME];
        GetCmdArg(1, selfName, sizeof(selfName));
        TrimString(selfName);
        if (!selfName[0])
        {
            ReplyToCommand(client, "[Kogasa] Usage: sm_prename <newname>");
            return Plugin_Handled;
        }

        char steam2[32], steam64[32], steamId[32];
        Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));
        Prename_GetPreferredClientId(steam64, steam2, steamId, sizeof(steamId));
        if (!steamId[0])
        {
            ReplyToCommand(client, "[Kogasa] Failed to resolve your SteamID.");
            return Plugin_Handled;
        }

        Prename_SaveRule(steamId, selfName);
        Prename_SetIdRuleCache(steamId, selfName);
        SetClientName(client, selfName);
        ReplyToCommand(client, "[Kogasa] Your prename was set to '%s'.", selfName);
        return Plugin_Handled;
    }

    if (args < 2)
    {
        ReplyToCommand(client, "[Kogasa] Usage: sm_prename <name_substring|steamid> <newname>");
        return Plugin_Handled;
    }

    char patternRaw[PRENAME_MAX_PATTERN];
    char newname[PRENAME_MAX_RENAME];
    GetCmdArg(1, patternRaw, sizeof(patternRaw));
    GetCmdArg(2, newname, sizeof(newname));
    TrimString(patternRaw);
    TrimString(newname);

    if (!patternRaw[0] || !newname[0])
    {
        ReplyToCommand(client, "[Kogasa] Usage: sm_prename <name_substring|steamid> <newname>");
        return Plugin_Handled;
    }

    if (Prename_IsIdString(patternRaw))
    {
        Prename_SaveRule(patternRaw, newname);
        Prename_SetIdRuleCache(patternRaw, newname);
        ReplyToCommand(client, "[Kogasa] Prename rule saved: '%s' -> '%s'", patternRaw, newname);
        return Plugin_Handled;
    }

    char targetName[MAX_NAME_LENGTH];
    int target = Prename_FindSingleClientByName(client, patternRaw, targetName, sizeof(targetName));
    if (target <= 0)
    {
        return Plugin_Handled;
    }

    char steam2[32], steam64[32], steamId[32];
    Prename_GetClientIds(target, steam2, sizeof(steam2), steam64, sizeof(steam64));
    Prename_GetPreferredClientId(steam64, steam2, steamId, sizeof(steamId));
    if (!steamId[0])
    {
        ReplyToCommand(client, "[Kogasa] Failed to resolve SteamID for %s.", targetName);
        return Plugin_Handled;
    }

    Prename_SaveRule(steamId, newname);
    Prename_SetIdRuleCache(steamId, newname);
    SetClientName(target, newname);
    ReplyToCommand(client, "[Kogasa] Prename rule saved: %s -> %s (%s)", targetName, newname, steamId);
    return Plugin_Handled;
}

public Action Command_PrenameReset(int client, int args)
{
    bool isAdmin = (client <= 0) || CheckCommandAccess(client, "sm_prename_admin", ADMFLAG_SLAY, true);

    if (!isAdmin)
    {
        if (client <= 0 || !IsClientInGame(client))
        {
            return Plugin_Handled;
        }

        char steam2[32], steam64[32], steamId[32];
        Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));
        Prename_GetPreferredClientId(steam64, steam2, steamId, sizeof(steamId));
        if (!steamId[0])
        {
            ReplyToCommand(client, "[Kogasa] Failed to resolve your SteamID.");
            return Plugin_Handled;
        }

        Prename_DeleteRule(steamId);
        Prename_RemoveIdRuleCache(steamId);
        ReplyToCommand(client, "[Kogasa] Your prename rule has been reset.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyToCommand(client, "[Kogasa] Usage: sm_reset <name|steamid>");
        return Plugin_Handled;
    }

    char targetRaw[PRENAME_MAX_PATTERN];
    GetCmdArg(1, targetRaw, sizeof(targetRaw));
    TrimString(targetRaw);

    if (!targetRaw[0])
    {
        ReplyToCommand(client, "[Kogasa] Usage: sm_reset <name|steamid>");
        return Plugin_Handled;
    }

    char steam2[32], steam64[32];
    if (!Prename_IsIdString(targetRaw))
    {
        char targetName[MAX_NAME_LENGTH];
        int target = Prename_FindSingleClientByName(client, targetRaw, targetName, sizeof(targetName));
        if (target <= 0)
        {
            return Plugin_Handled;
        }

        char resolvedId[32];
        Prename_GetClientIds(target, steam2, sizeof(steam2), steam64, sizeof(steam64));
        Prename_GetPreferredClientId(steam64, steam2, resolvedId, sizeof(resolvedId));
        if (!resolvedId[0])
        {
            ReplyToCommand(client, "[Kogasa] Failed to resolve SteamID for %s.", targetName);
            return Plugin_Handled;
        }

        Prename_DeleteRule(resolvedId);
        Prename_RemoveIdRuleCache(resolvedId);
        ReplyToCommand(client, "[Kogasa] Prename rule removed for %s (%s)", targetName, resolvedId);
        return Plugin_Handled;
    }

    if (StrContains(targetRaw, "STEAM_", false) == 0)
    {
        int match = Prename_FindClientBySteam2(targetRaw);
        if (match > 0)
        {
            Prename_GetClientIds(match, steam2, sizeof(steam2), steam64, sizeof(steam64));
            char resolvedId[32];
            Prename_GetPreferredClientId(steam64, steam2, resolvedId, sizeof(resolvedId));
            if (resolvedId[0])
            {
                Prename_DeleteRule(resolvedId);
                Prename_RemoveIdRuleCache(resolvedId);
                ReplyToCommand(client, "[Kogasa] Prename rule removed for '%s'", resolvedId);
                return Plugin_Handled;
            }
        }
    }

    Prename_DeleteRule(targetRaw);
    Prename_RemoveIdRuleCache(targetRaw);
    ReplyToCommand(client, "[Kogasa] Prename rule removed for '%s'", targetRaw);
    return Plugin_Handled;
}

public Action Command_PrenameMigrate(int client, int args)
{
    int migrated = 0;
    int processed = 0;

    g_PrenameDebugMigrate = true;
    Prename_DebugLog("---- migrate start ----");
    Prename_DebugLog("db_ready=%d id_rules=%d output_rules=%d",
        g_bDbReady ? 1 : 0,
        Prename_GetStringMapCount(g_PrenameIdRules),
        Prename_GetStringMapCount(g_PrenameOutputMap));

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }
        processed++;
        migrated += Prename_MigrateLegacyForClient(i);
    }

    Prename_DebugLog("---- migrate end migrated=%d processed=%d ----", migrated, processed);
    g_PrenameDebugMigrate = false;

    ReplyToCommand(client, "[Kogasa] Migrated %d rule(s) across %d client(s).", migrated, processed);
    return Plugin_Handled;
}

static int Prename_MigrateLegacyForClient(int client)
{
    if (!g_bDbReady || g_hFiltersDb == null || g_PrenameIdRules == null || g_PrenameOutputMap == null)
    {
        Prename_DebugLog("client=%d skip db_ready=%d id_rules=%d output_rules=%d",
            client,
            g_bDbReady ? 1 : 0,
            Prename_GetStringMapCount(g_PrenameIdRules),
            Prename_GetStringMapCount(g_PrenameOutputMap));
        return 0;
    }

    char currentName[MAX_NAME_LENGTH];
    GetClientName(client, currentName, sizeof(currentName));

    char lowerName[MAX_NAME_LENGTH];
    strcopy(lowerName, sizeof(lowerName), currentName);
    Prename_ToLowercaseInPlace(lowerName, sizeof(lowerName));

    char steam2[32], steam64[32], migrateId[32];
    Prename_GetClientIds(client, steam2, sizeof(steam2), steam64, sizeof(steam64));
    Prename_GetPreferredClientId(steam64, steam2, migrateId, sizeof(migrateId));

    if (!migrateId[0])
    {
        Prename_DebugLog("client=%d name=\"%s\" no_steamid", client, currentName);
        return 0;
    }

    char existing[PRENAME_MAX_RENAME];
    if (Prename_TryGetIdRule(steam64, steam2, existing, sizeof(existing)) && StrEqual(existing, currentName, false))
    {
        Prename_DebugLog("client=%d name=\"%s\" id=%s already_set", client, currentName, migrateId);
        return 0;
    }

    char output[PRENAME_MAX_RENAME];
    char matchKey[PRENAME_MAX_RENAME];
    if (!Prename_FindBestOutputMatch(lowerName, output, sizeof(output), matchKey, sizeof(matchKey)))
    {
        Prename_DebugLog("client=%d name=\"%s\" id=%s no_output_match", client, currentName, migrateId);
        return 0;
    }

    if (!StrEqual(output, currentName, false))
    {
        Prename_DebugLog("client=%d name=\"%s\" id=%s output=\"%s\" skipped_not_equal", client, currentName, migrateId, output);
        return 0;
    }

    Prename_SaveRule(migrateId, currentName);
    Prename_SetIdRuleCache(migrateId, currentName);
    Prename_DebugLog("client=%d name=\"%s\" id=%s migrated=1", client, currentName, migrateId);
    return 1;
}

static void Prename_SaveRule(const char[] pattern, const char[] newname)
{
    if (!g_bDbReady || g_hFiltersDb == null)
    {
        return;
    }

    char escapedPattern[PRENAME_MAX_PATTERN * 2];
    char escapedNewname[PRENAME_MAX_RENAME * 2];
    Db_Escape(g_hFiltersDb, pattern, escapedPattern, sizeof(escapedPattern), "filters");
    Db_Escape(g_hFiltersDb, newname, escapedNewname, sizeof(escapedNewname), "filters");

    char query[256];
    Format(query, sizeof(query),
        "REPLACE INTO prename_rules (pattern, newname) VALUES ('%s', '%s')",
        escapedPattern, escapedNewname);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

static void Prename_DeleteRule(const char[] pattern)
{
    if (!g_bDbReady || g_hFiltersDb == null)
    {
        return;
    }

    char escapedPattern[PRENAME_MAX_PATTERN * 2];
    Db_Escape(g_hFiltersDb, pattern, escapedPattern, sizeof(escapedPattern), "filters");

    char query[256];
    Format(query, sizeof(query), "DELETE FROM prename_rules WHERE pattern = '%s'", escapedPattern);
    g_hFiltersDb.Query(Filters_SimpleSqlCallback, query);
}

static void Prename_SetIdRuleCache(const char[] steamid, const char[] newname)
{
    if (g_PrenameIdRules == null)
    {
        return;
    }
    g_PrenameIdRules.SetString(steamid, newname);
}

static void Prename_RemoveIdRuleCache(const char[] steamid)
{
    if (g_PrenameIdRules == null)
    {
        return;
    }
    g_PrenameIdRules.Remove(steamid);
}

bool Prename_TryGetIdRule(const char[] steam64, const char[] steam2, char[] output, int maxlen)
{
    if (g_PrenameIdRules == null)
    {
        return false;
    }

    if (steam64[0] && g_PrenameIdRules.GetString(steam64, output, maxlen))
    {
        return true;
    }

    if (steam2[0] && g_PrenameIdRules.GetString(steam2, output, maxlen))
    {
        return true;
    }

    return false;
}

static bool Prename_FindBestOutputMatch(const char[] lowerName, char[] output, int outMax, char[] keyOut, int keyMax)
{
    if (g_PrenameOutputMap == null)
    {
        return false;
    }

    StringMapSnapshot snap = g_PrenameOutputMap.Snapshot();
    int count = snap.Length;
    int bestLen = -1;
    char key[PRENAME_MAX_RENAME];
    char bestKey[PRENAME_MAX_RENAME];
    bestKey[0] = '\0';

    for (int i = 0; i < count; i++)
    {
        snap.GetKey(i, key, sizeof(key));
        if (StrContains(lowerName, key) == -1)
        {
            continue;
        }

        int keyLen = strlen(key);
        if (keyLen > bestLen)
        {
            bestLen = keyLen;
            strcopy(bestKey, sizeof(bestKey), key);
        }
    }

    delete snap;

    if (bestKey[0] == '\0')
    {
        return false;
    }

    if (keyMax > 0)
    {
        strcopy(keyOut, keyMax, bestKey);
    }

    return g_PrenameOutputMap.GetString(bestKey, output, outMax);
}

static int Prename_FindClientBySteam2(const char[] steam2)
{
    if (!steam2[0])
    {
        return -1;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        char id[32];
        Kogasa_GetClientSteam2(i, id, sizeof(id), true);
        if (StrEqual(id, steam2, false))
        {
            return i;
        }
    }

    return -1;
}

static int Prename_FindSingleClientByName(int requester, const char[] patternRaw, char[] matchName, int matchMax)
{
    char pattern[PRENAME_MAX_PATTERN];
    strcopy(pattern, sizeof(pattern), patternRaw);
    Prename_ToLowercaseInPlace(pattern, sizeof(pattern));

    int matches = 0;
    int target = -1;
    char matchList[256];
    matchList[0] = '\0';

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];
        GetClientName(i, name, sizeof(name));

        char lowerName[MAX_NAME_LENGTH];
        strcopy(lowerName, sizeof(lowerName), name);
        Prename_ToLowercaseInPlace(lowerName, sizeof(lowerName));

        if (StrContains(lowerName, pattern, false) == -1)
        {
            continue;
        }

        matches++;
        target = i;
        if (matchMax > 0)
        {
            strcopy(matchName, matchMax, name);
        }

        if (matches == 1)
        {
            strcopy(matchList, sizeof(matchList), name);
        }
        else if (strlen(matchList) + strlen(name) + 2 < sizeof(matchList))
        {
            StrCat(matchList, sizeof(matchList), ", ");
            StrCat(matchList, sizeof(matchList), name);
        }
    }

    if (matches == 0)
    {
        ReplyToCommand(requester, "[Kogasa] No client matches '%s'.", patternRaw);
        return -1;
    }

    if (matches > 1)
    {
        ReplyToCommand(requester, "[Kogasa] Multiple matches for '%s': %s", patternRaw, matchList);
        return -1;
    }

    return target;
}

void Prename_ToLowercaseInPlace(char[] text, int maxlen)
{
    int length = strlen(text);
    if (length > maxlen - 1)
    {
        length = maxlen - 1;
    }

    for (int i = 0; i < length; i++)
    {
        text[i] = CharToLower(text[i]);
    }
}

static void Prename_GetPreferredClientId(const char[] steam64, const char[] steam2, char[] output, int maxlen)
{
    output[0] = '\0';
    if (steam64[0])
    {
        strcopy(output, maxlen, steam64);
    }
    else if (steam2[0])
    {
        strcopy(output, maxlen, steam2);
    }
}

void Prename_GetClientIds(int client, char[] steam2, int steam2Max, char[] steam64, int steam64Max)
{
    steam2[0] = '\0';
    steam64[0] = '\0';
    Kogasa_GetClientSteamId64(client, steam64, steam64Max, true);
    Kogasa_GetClientSteam2(client, steam2, steam2Max, true);
}

static bool Prename_IsIdString(const char[] text)
{
    if (!text[0])
    {
        return false;
    }

    if (StrContains(text, "STEAM_", false) == 0)
    {
        return true;
    }

    int len = strlen(text);
    if (len < 15)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        if (!IsCharNumeric(text[i]))
        {
            return false;
        }
    }

    return true;
}

static void Prename_DebugLog(const char[] fmt, any ...)
{
    if (!g_PrenameDebugMigrate)
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogToFileEx(g_PrenameDebugLogPath, "%s", buffer);
}

static int Prename_GetStringMapCount(StringMap map)
{
    if (map == null)
    {
        return 0;
    }

    StringMapSnapshot snap = map.Snapshot();
    int count = snap.Length;
    delete snap;
    return count;
}
