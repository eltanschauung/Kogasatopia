void LoadSaySoundConfig()
{
    gSoundMap.Clear();
    gSoundGroupMap.Clear();
    gAPIOnlyGroups.Clear();
    gForcedSoundGroups.Clear();
    gPaidSaysoundGroups.Clear();
    gGroupAliases.Clear();
    gCommandNames.Clear();
    gGroupNames.Clear();
    gRoundStartSirenReplacements.Clear();
    gRoundStartSirenGroups.Clear();
    gReadyRoundStartSirenReplacements.Clear();
    gReadyRoundStartSirenGroups.Clear();
    gRoundWinReplacements.Clear();
    gRoundWinGroups.Clear();
    gReadyRoundWinReplacements.Clear();
    gReadyRoundWinGroups.Clear();
    gRoundLoseReplacements.Clear();
    gRoundLoseGroups.Clear();
    gReadyRoundLoseReplacements.Clear();
    gReadyRoundLoseGroups.Clear();
    gAnnouncerMiscReplacements.Clear();
    gAnnouncerMiscGroups.Clear();
    gReadyAnnouncerMiscReplacements.Clear();
    gReadyAnnouncerMiscGroups.Clear();
    gCountdownReplacements.Clear();
    gCountdownGroups.Clear();
    gReadyCountdownReplacements.Clear();
    gReadyCountdownGroups.Clear();
    gUnlockReplacements.Clear();
    gUnlockGroups.Clear();
    gReadyUnlockReplacements.Clear();
    gReadyUnlockGroups.Clear();
    gConfigLoaded = false;
    gConfigInAPIOnlyGroups = false;
    gConfigInPaidSaysoundGroups = false;
    gConfigInGroupAliases = false;
    gConfigInRoundStartSirens = false;
    gConfigInRoundWinReplacements = false;
    gConfigInRoundLoseReplacements = false;
    gConfigInAnnouncerMiscReplacements = false;
    gConfigInCountdownReplacements = false;
    gConfigInUnlockReplacements = false;
    gConfigSectionDepth = 0;
    gConfigAPIOnlyGroupsDepth = -1;
    gConfigPaidSaysoundGroupsDepth = -1;
    gConfigGroupAliasesDepth = -1;
    gConfigRoundStartSirensDepth = -1;
    gConfigRoundWinReplacementsDepth = -1;
    gConfigRoundLoseReplacementsDepth = -1;
    gConfigAnnouncerMiscReplacementsDepth = -1;
    gConfigCountdownReplacementsDepth = -1;
    gConfigUnlockReplacementsDepth = -1;
    EnsureGroupRegistered(DEFAULT_GROUP);

    char filePath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, filePath, sizeof(filePath), CONFIG_FILE);

    if (!FileExists(filePath))
    {
        LogError("[SaySounds] Config file not found: %s", filePath);
        return;
    }

    SMCParser parser = new SMCParser();
    parser.OnEnterSection = Config_EnterSection;
    parser.OnLeaveSection = Config_LeaveSection;
    parser.OnKeyValue = Config_KeyValue;

    int errorLine, errorColumn;
    SMCError result;
    result = parser.ParseFile(filePath, errorLine, errorColumn);

    if (result != SMCError_Okay)
    {
        char error[256];
        parser.GetErrorString(result, error, sizeof(error));
        LogError("[SaySounds] Failed to parse config: %s (line %d, column %d)", error, errorLine, errorColumn);
        delete parser;
        gSoundMap.Clear();
        gCommandNames.Clear();
        RefreshForcedSoundGroups();
        return;
    }

    delete parser;
    RefreshForcedSoundGroups();

    if (gCommandNames.Length == 0)
    {
        LogError("[SaySounds] No command entries found in config.");
        return;
    }

    gConfigLoaded = true;
}

public SMCResult Config_EnterSection(SMCParser parser, const char[] name, bool optQuotes)
{
    gConfigSectionDepth++;

    char sectionName[64];
    strcopy(sectionName, sizeof(sectionName), name);
    TrimString(sectionName);
    Strings_ToLower(sectionName, sizeof(sectionName));

    if (StrEqual(sectionName, API_ONLY_GROUPS_SECTION)
        || StrEqual(sectionName, "api_only_groups")
        || StrEqual(sectionName, "api-only-groups"))
    {
        gConfigInAPIOnlyGroups = true;
        gConfigAPIOnlyGroupsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, PAID_SAYSOUND_GROUPS_SECTION)
        || StrEqual(sectionName, "paid_saysound_groups")
        || StrEqual(sectionName, "paid-saysound-groups"))
    {
        gConfigInPaidSaysoundGroups = true;
        gConfigPaidSaysoundGroupsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, GROUP_ALIASES_SECTION)
        || StrEqual(sectionName, "group_aliases")
        || StrEqual(sectionName, "group-aliases"))
    {
        gConfigInGroupAliases = true;
        gConfigGroupAliasesDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, ROUND_START_SIRENS_SECTION)
        || StrEqual(sectionName, "round_start_siren_replacements")
        || StrEqual(sectionName, "round-start-siren-replacements"))
    {
        gConfigInRoundStartSirens = true;
        gConfigRoundStartSirensDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, ROUND_WIN_REPLACEMENTS_SECTION)
        || StrEqual(sectionName, "round_win_replacements")
        || StrEqual(sectionName, "round-win-replacements"))
    {
        gConfigInRoundWinReplacements = true;
        gConfigRoundWinReplacementsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, ROUND_LOSE_REPLACEMENTS_SECTION)
        || StrEqual(sectionName, "round_lose_replacements")
        || StrEqual(sectionName, "round-lose-replacements"))
    {
        gConfigInRoundLoseReplacements = true;
        gConfigRoundLoseReplacementsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, ANNOUNCER_MISC_REPLACEMENTS_SECTION)
        || StrEqual(sectionName, "replace_announcer_misc")
        || StrEqual(sectionName, "replace-announcer-misc"))
    {
        gConfigInAnnouncerMiscReplacements = true;
        gConfigAnnouncerMiscReplacementsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, COUNTDOWN_REPLACEMENTS_SECTION)
        || StrEqual(sectionName, "count_down_replacements")
        || StrEqual(sectionName, "count-down-replacements"))
    {
        gConfigInCountdownReplacements = true;
        gConfigCountdownReplacementsDepth = gConfigSectionDepth;
    }
    else if (StrEqual(sectionName, UNLOCK_REPLACEMENTS_SECTION)
        || StrEqual(sectionName, "unlock_replacements")
        || StrEqual(sectionName, "unlock-replacements"))
    {
        gConfigInUnlockReplacements = true;
        gConfigUnlockReplacementsDepth = gConfigSectionDepth;
    }

    return SMCParse_Continue;
}

public SMCResult Config_LeaveSection(SMCParser parser)
{
    if (gConfigInAPIOnlyGroups && gConfigSectionDepth == gConfigAPIOnlyGroupsDepth)
    {
        gConfigInAPIOnlyGroups = false;
        gConfigAPIOnlyGroupsDepth = -1;
    }

    if (gConfigInPaidSaysoundGroups && gConfigSectionDepth == gConfigPaidSaysoundGroupsDepth)
    {
        gConfigInPaidSaysoundGroups = false;
        gConfigPaidSaysoundGroupsDepth = -1;
    }

    if (gConfigInGroupAliases && gConfigSectionDepth == gConfigGroupAliasesDepth)
    {
        gConfigInGroupAliases = false;
        gConfigGroupAliasesDepth = -1;
    }

    if (gConfigInRoundStartSirens && gConfigSectionDepth == gConfigRoundStartSirensDepth)
    {
        gConfigInRoundStartSirens = false;
        gConfigRoundStartSirensDepth = -1;
    }

    if (gConfigInRoundWinReplacements && gConfigSectionDepth == gConfigRoundWinReplacementsDepth)
    {
        gConfigInRoundWinReplacements = false;
        gConfigRoundWinReplacementsDepth = -1;
    }

    if (gConfigInRoundLoseReplacements && gConfigSectionDepth == gConfigRoundLoseReplacementsDepth)
    {
        gConfigInRoundLoseReplacements = false;
        gConfigRoundLoseReplacementsDepth = -1;
    }

    if (gConfigInAnnouncerMiscReplacements
        && gConfigSectionDepth == gConfigAnnouncerMiscReplacementsDepth)
    {
        gConfigInAnnouncerMiscReplacements = false;
        gConfigAnnouncerMiscReplacementsDepth = -1;
    }

    if (gConfigInCountdownReplacements
        && gConfigSectionDepth == gConfigCountdownReplacementsDepth)
    {
        gConfigInCountdownReplacements = false;
        gConfigCountdownReplacementsDepth = -1;
    }

    if (gConfigInUnlockReplacements
        && gConfigSectionDepth == gConfigUnlockReplacementsDepth)
    {
        gConfigInUnlockReplacements = false;
        gConfigUnlockReplacementsDepth = -1;
    }

    if (gConfigSectionDepth > 0)
    {
        gConfigSectionDepth--;
    }

    return SMCParse_Continue;
}

public SMCResult Config_KeyValue(SMCParser parser, const char[] key, const char[] value, bool keyQuoted, bool valueQuoted)
{
    if (gConfigInRoundStartSirens)
    {
        Config_ReplacementSound(value, gRoundStartSirenReplacements, gRoundStartSirenGroups);
        return SMCParse_Continue;
    }

    if (gConfigInRoundWinReplacements)
    {
        Config_ReplacementSound(value, gRoundWinReplacements, gRoundWinGroups);
        return SMCParse_Continue;
    }

    if (gConfigInRoundLoseReplacements)
    {
        Config_ReplacementSound(value, gRoundLoseReplacements, gRoundLoseGroups);
        return SMCParse_Continue;
    }

    if (gConfigInAnnouncerMiscReplacements)
    {
        Config_ReplacementSound(value, gAnnouncerMiscReplacements, gAnnouncerMiscGroups);
        return SMCParse_Continue;
    }

    if (gConfigInCountdownReplacements)
    {
        Config_ReplacementSound(value, gCountdownReplacements, gCountdownGroups);
        return SMCParse_Continue;
    }

    if (gConfigInUnlockReplacements)
    {
        Config_ReplacementSound(value, gUnlockReplacements, gUnlockGroups);
        return SMCParse_Continue;
    }

    if (gConfigInAPIOnlyGroups)
    {
        Config_APIOnlyGroup(key);
        return SMCParse_Continue;
    }

    if (gConfigInPaidSaysoundGroups)
    {
        Config_PaidSaysoundGroup(key, value);
        return SMCParse_Continue;
    }

    if (gConfigInGroupAliases)
    {
        Config_GroupAlias(key, value);
        return SMCParse_Continue;
    }

    char commandName[MAX_COMMAND_NAME];
    strcopy(commandName, sizeof(commandName), key);
    TrimString(commandName);

    if (!commandName[0])
    {
        return SMCParse_Continue;
    }

    if (commandName[0] == '!' || commandName[0] == '/')
    {
        Strings_ShiftLeft(commandName, sizeof(commandName), 1);
    }

    Strings_ToLower(commandName, sizeof(commandName));

    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    ParseSoundConfigEntry(value, soundPath, sizeof(soundPath), groupName, sizeof(groupName));

    if (!soundPath[0])
    {
        LogError("[SaySounds] Command '%s' has an empty sound path.", commandName);
        return SMCParse_Continue;
    }

    if (!groupName[0])
    {
        strcopy(groupName, sizeof(groupName), DEFAULT_GROUP);
    }

    EnsureGroupRegistered(groupName);

    int existingIndex = FindCommandIndex(commandName);
    if (existingIndex == -1)
    {
        gCommandNames.PushString(commandName);
    }

    gSoundMap.SetString(commandName, soundPath);
    gSoundGroupMap.SetString(commandName, groupName);
    return SMCParse_Continue;
}

static void Config_APIOnlyGroup(const char[] key)
{
    char groupName[MAX_GROUP_NAME];
    strcopy(groupName, sizeof(groupName), key);
    TrimString(groupName);
    Strings_ToLower(groupName, sizeof(groupName));

    if (!groupName[0] || StrEqual(groupName, DEFAULT_GROUP))
    {
        return;
    }

    EnsureGroupRegistered(groupName);

    // API-only membership is presence-based; the value is reserved for config compatibility.
    gAPIOnlyGroups.SetValue(groupName, 1);
}

static void Config_PaidSaysoundGroup(const char[] key, const char[] value)
{
    char groupName[MAX_GROUP_NAME];
    strcopy(groupName, sizeof(groupName), key);
    TrimString(groupName);
    Strings_ToLower(groupName, sizeof(groupName));

    if (!groupName[0] || StrEqual(groupName, DEFAULT_GROUP))
    {
        return;
    }

    EnsureGroupRegistered(groupName);

    if (ConfigValueIsEnabled(value))
    {
        gPaidSaysoundGroups.SetValue(groupName, 1);
    }
    else
    {
        gPaidSaysoundGroups.Remove(groupName);
    }
}

static void Config_GroupAlias(const char[] key, const char[] value)
{
    char groupName[MAX_GROUP_NAME];
    strcopy(groupName, sizeof(groupName), key);
    TrimString(groupName);
    Strings_ToLower(groupName, sizeof(groupName));

    char aliasName[MAX_COMMAND_NAME];
    strcopy(aliasName, sizeof(aliasName), value);
    TrimString(aliasName);
    Strings_ToLower(aliasName, sizeof(aliasName));

    if (!groupName[0] || !aliasName[0] || StrEqual(aliasName, DEFAULT_GROUP))
    {
        return;
    }

    if (aliasName[0] == '!' || aliasName[0] == '/')
    {
        Strings_ShiftLeft(aliasName, sizeof(aliasName), 1);
    }

    EnsureGroupRegistered(groupName);
    gGroupAliases.SetString(aliasName, groupName);
}

static void Config_ReplacementSound(const char[] configuredPath, ArrayList replacements, ArrayList groups)
{
    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    ParseSoundConfigEntry(configuredPath, soundPath, sizeof(soundPath), groupName, sizeof(groupName));

    if (!soundPath[0]
        || (StrContains(soundPath, ".mp3", false) == -1
            && StrContains(soundPath, ".wav", false) == -1))
    {
        return;
    }

    if (!groupName[0])
    {
        strcopy(groupName, sizeof(groupName), DEFAULT_GROUP);
    }

    EnsureGroupRegistered(groupName);

    int index = replacements.FindString(soundPath);
    if (index == -1)
    {
        replacements.PushString(soundPath);
        groups.PushString(groupName);
    }
    else
    {
        groups.SetString(index, groupName);
    }
}

static void PrecacheReplacementSounds(
    ArrayList replacements,
    ArrayList groups,
    ArrayList readyReplacements,
    ArrayList readyGroups,
    const char[] replacementType)
{
    readyReplacements.Clear();
    readyGroups.Clear();

    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char downloadPath[PLATFORM_MAX_PATH];
    for (int i = 0; i < replacements.Length; i++)
    {
        replacements.GetString(i, soundPath, sizeof(soundPath));
        groups.GetString(i, groupName, sizeof(groupName));
        FormatEx(downloadPath, sizeof(downloadPath), "sound/%s", soundPath);

        if (!FileExists(downloadPath, true))
        {
            LogError("[SaySounds] %s replacement not found: %s", replacementType, downloadPath);
            continue;
        }

        AddFileToDownloadsTable(downloadPath);
        if (PrecacheSound(soundPath, true))
        {
            readyReplacements.PushString(soundPath);
            readyGroups.PushString(groupName);
        }
    }
}

void PrecacheConfiguredSounds()
{
    if (!gConfigLoaded)
    {
        return;
    }

    char commandName[MAX_COMMAND_NAME];
    char soundPath[PLATFORM_MAX_PATH];

    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, commandName, sizeof(commandName));
        if (!gSoundMap.GetString(commandName, soundPath, sizeof(soundPath)))
        {
            continue;
        }

        PrecacheSound(soundPath, true);
    }

    PrecacheReplacementSounds(
        gRoundStartSirenReplacements,
        gRoundStartSirenGroups,
        gReadyRoundStartSirenReplacements,
        gReadyRoundStartSirenGroups,
        "Round-start siren"
    );
    PrecacheReplacementSounds(
        gRoundWinReplacements,
        gRoundWinGroups,
        gReadyRoundWinReplacements,
        gReadyRoundWinGroups,
        "Round-win"
    );
    PrecacheReplacementSounds(
        gRoundLoseReplacements,
        gRoundLoseGroups,
        gReadyRoundLoseReplacements,
        gReadyRoundLoseGroups,
        "Round-loss"
    );
    PrecacheReplacementSounds(
        gAnnouncerMiscReplacements,
        gAnnouncerMiscGroups,
        gReadyAnnouncerMiscReplacements,
        gReadyAnnouncerMiscGroups,
        "Miscellaneous announcer"
    );
    PrecacheReplacementSounds(
        gCountdownReplacements,
        gCountdownGroups,
        gReadyCountdownReplacements,
        gReadyCountdownGroups,
        "Setup countdown"
    );
    PrecacheReplacementSounds(
        gUnlockReplacements,
        gUnlockGroups,
        gReadyUnlockReplacements,
        gReadyUnlockGroups,
        "Control-point unlock"
    );
}

int FindCommandIndex(const char[] commandName)
{
    char current[MAX_COMMAND_NAME];
    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, current, sizeof(current));
        if (StrEqual(current, commandName))
        {
            return i;
        }
    }

    return -1;
}

void NormalizeSoundPath(char[] soundPath, int maxlen)
{
    ReplaceString(soundPath, maxlen, "\\", "/");

    while (soundPath[0] == '/')
    {
        Strings_ShiftLeft(soundPath, maxlen, 1);
    }

    if (Strings_StartsWith(soundPath, "sound/"))
    {
        Strings_ShiftLeft(soundPath, maxlen, 6);
    }
}

static void ParseSoundConfigEntry(const char[] value, char[] soundPath, int soundLen, char[] groupName, int groupLen)
{
    if (soundLen > 0)
    {
        soundPath[0] = '\0';
    }
    if (groupLen > 0)
    {
        groupName[0] = '\0';
    }

    char raw[PLATFORM_MAX_PATH];
    strcopy(raw, sizeof(raw), value);
    TrimString(raw);

    if (!raw[0])
    {
        return;
    }

    int delim = FindCharInString(raw, '|');
    if (delim != -1)
    {
        char groupPart[MAX_GROUP_NAME];
        strcopy(groupPart, sizeof(groupPart), raw);
        groupPart[delim] = '\0';
        TrimString(groupPart);
        Strings_ToLower(groupPart, sizeof(groupPart));

        char pathPart[PLATFORM_MAX_PATH];
        Strings_CopyFrom(raw, delim + 1, pathPart, sizeof(pathPart));
        TrimString(pathPart);

        if (groupLen > 0)
        {
            strcopy(groupName, groupLen, groupPart);
        }

        strcopy(soundPath, soundLen, pathPart);
    }
    else
    {
        strcopy(soundPath, soundLen, raw);
    }

    NormalizeSoundPath(soundPath, soundLen);
}

static int FindGroupIndex(const char[] groupName)
{
    if (gGroupNames == null)
    {
        return -1;
    }

    char current[MAX_GROUP_NAME];
    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, current, sizeof(current));
        if (StrEqual(current, groupName))
        {
            return i;
        }
    }

    return -1;
}

static void EnsureGroupRegistered(const char[] groupName)
{
    if (gGroupNames == null)
    {
        return;
    }

    char normalized[MAX_GROUP_NAME];
    strcopy(normalized, sizeof(normalized), groupName);
    TrimString(normalized);
    Strings_ToLower(normalized, sizeof(normalized));

    if (!normalized[0])
    {
        return;
    }

    if (FindGroupIndex(normalized) != -1)
    {
        return;
    }

    gGroupNames.PushString(normalized);
}

bool IsKnownGroup(const char[] groupName)
{
    char resolved[MAX_GROUP_NAME];
    return ResolveKnownGroupName(groupName, resolved, sizeof(resolved));
}

bool ResolveKnownGroupName(const char[] inputName, char[] groupName, int groupLen)
{
    if (groupLen > 0)
    {
        groupName[0] = '\0';
    }

    if (!inputName[0])
    {
        return false;
    }

    char normalized[MAX_GROUP_NAME];
    strcopy(normalized, sizeof(normalized), inputName);
    TrimString(normalized);
    Strings_ToLower(normalized, sizeof(normalized));

    if (!normalized[0])
    {
        return false;
    }

    if (StrEqual(normalized, DEFAULT_GROUP))
    {
        strcopy(groupName, groupLen, normalized);
        return true;
    }

    if (FindGroupIndex(normalized) != -1)
    {
        strcopy(groupName, groupLen, normalized);
        return true;
    }

    if (gGroupAliases == null || !gGroupAliases.GetString(normalized, groupName, groupLen))
    {
        return false;
    }

    TrimString(groupName);
    Strings_ToLower(groupName, groupLen);
    return groupName[0] != '\0'
        && (StrEqual(groupName, DEFAULT_GROUP) || FindGroupIndex(groupName) != -1);
}

static bool ConfigValueIsEnabled(const char[] value)
{
    char normalized[16];
    strcopy(normalized, sizeof(normalized), value);
    TrimString(normalized);
    Strings_ToLower(normalized, sizeof(normalized));

    if (!normalized[0])
    {
        return true;
    }

    return !StrEqual(normalized, "0")
        && !StrEqual(normalized, "false")
        && !StrEqual(normalized, "off")
        && !StrEqual(normalized, "no");
}

bool IsGroupAPIOnly(const char[] groupName)
{
    if (gAPIOnlyGroups == null || !groupName[0])
    {
        return false;
    }

    char normalized[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalized, sizeof(normalized)))
    {
        return false;
    }

    int apiOnly = 0;
    return gAPIOnlyGroups.GetValue(normalized, apiOnly) && apiOnly != 0;
}

bool IsGroupPaid(const char[] groupName)
{
    if (gPaidSaysoundGroups == null || !groupName[0])
    {
        return false;
    }

    char normalized[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalized, sizeof(normalized)))
    {
        return false;
    }

    int paid = 0;
    return gPaidSaysoundGroups.GetValue(normalized, paid) && paid != 0;
}

public void ConVar_ForcedGroupsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshForcedSoundGroups();
}

void RefreshForcedSoundGroups()
{
    if (gForcedSoundGroups == null)
    {
        return;
    }

    gForcedSoundGroups.Clear();

    if (g_hForcedGroups == null)
    {
        return;
    }

    char configuredGroups[MAX_GROUP_PREF_VALUE];
    g_hForcedGroups.GetString(configuredGroups, sizeof(configuredGroups));

    int cursor = 0;
    while (configuredGroups[cursor] != '\0')
    {
        int comma = FindCharInString(configuredGroups[cursor], ',');
        char groupName[MAX_GROUP_NAME];

        if (comma == -1)
        {
            strcopy(groupName, sizeof(groupName), configuredGroups[cursor]);
        }
        else
        {
            int copyLength = comma;
            if (copyLength >= sizeof(groupName))
            {
                copyLength = sizeof(groupName) - 1;
            }

            strcopy(groupName, copyLength + 1, configuredGroups[cursor]);
        }

        TrimString(groupName);
        Strings_ToLower(groupName, sizeof(groupName));

        char normalized[MAX_GROUP_NAME];
        if (groupName[0]
            && !StrEqual(groupName, DEFAULT_GROUP)
            && ResolveKnownGroupName(groupName, normalized, sizeof(normalized)))
        {
            gForcedSoundGroups.SetValue(normalized, 1);
        }

        if (comma == -1)
        {
            break;
        }

        cursor += comma + 1;
    }
}

bool IsGroupForced(const char[] groupName)
{
    if (gForcedSoundGroups == null || !groupName[0])
    {
        return false;
    }

    char normalized[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalized, sizeof(normalized)))
    {
        return false;
    }

    int forced = 0;
    return gForcedSoundGroups.GetValue(normalized, forced) && forced != 0;
}

bool CanUseAPIOnlySaySoundGroup(const char[] groupName, bool bypassAPIOnly = false)
{
    return bypassAPIOnly || !IsGroupAPIOnly(groupName);
}

bool CanClientUsePaidSaysoundGroup(int client, const char[] groupName)
{
    char normalized[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalized, sizeof(normalized)) || !IsGroupPaid(normalized))
    {
        return true;
    }

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, POINTS_STORE_HAS_PURCHASE_NATIVE) != FeatureStatus_Available)
    {
        return false;
    }

    return PointsStore_HasPurchase(client, normalized);
}

bool CanClientUseSaySoundGroup(int client, const char[] groupName, bool bypassAPIOnly = false)
{
    return CanUseAPIOnlySaySoundGroup(groupName, bypassAPIOnly)
        && CanClientUsePaidSaysoundGroup(client, groupName);
}

bool CanClientUseSaySoundCommand(int client, const char[] commandName, bool bypassAPIOnly = false)
{
    char path[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    if (!GetCommandSoundData(commandName, path, sizeof(path), groupName, sizeof(groupName)))
    {
        return false;
    }

    return CanClientUseSaySoundGroup(client, groupName, bypassAPIOnly);
}

bool CanClientUseSaySoundInput(int client, const char[] inputName, bool bypassAPIOnly = false)
{
    bool restricted = false;
    bool paidRestricted = false;
    char chosen[MAX_COMMAND_NAME];
    return GetCommandOptionForClient(client, inputName, chosen, sizeof(chosen), restricted, paidRestricted, bypassAPIOnly);
}

bool IsSaySoundInputPaid(const char[] inputName)
{
    char normalizedName[MAX_COMMAND_NAME];
    strcopy(normalizedName, sizeof(normalizedName), inputName);
    TrimString(normalizedName);
    Strings_ToLower(normalizedName, sizeof(normalizedName));

    if (!normalizedName[0])
    {
        return false;
    }

    char soundPath[PLATFORM_MAX_PATH];
    if (gSoundMap.GetString(normalizedName, soundPath, sizeof(soundPath)))
    {
        char groupName[MAX_GROUP_NAME];
        if (!gSoundGroupMap.GetString(normalizedName, groupName, sizeof(groupName)))
        {
            strcopy(groupName, sizeof(groupName), DEFAULT_GROUP);
        }

        return IsGroupPaid(groupName);
    }

    char groupName[MAX_GROUP_NAME];
    return ResolveKnownGroupName(normalizedName, groupName, sizeof(groupName)) && IsGroupPaid(groupName);
}

bool GetSaySoundInputGroup(const char[] inputName, char[] groupName, int groupLen)
{
    if (groupLen > 0)
    {
        groupName[0] = '\0';
    }

    char normalizedName[MAX_COMMAND_NAME];
    strcopy(normalizedName, sizeof(normalizedName), inputName);
    TrimString(normalizedName);
    Strings_ToLower(normalizedName, sizeof(normalizedName));

    if (!normalizedName[0])
    {
        return false;
    }

    if (ResolveKnownGroupName(normalizedName, groupName, groupLen))
    {
        return true;
    }

    char soundPath[PLATFORM_MAX_PATH];
    if (!gSoundMap.GetString(normalizedName, soundPath, sizeof(soundPath)))
    {
        return false;
    }

    if (!gSoundGroupMap.GetString(normalizedName, groupName, groupLen))
    {
        strcopy(groupName, groupLen, DEFAULT_GROUP);
    }

    return groupName[0] != '\0';
}

static void EnsureClientGroupPreferenceMap(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (g_hClientDisabledGroups[client] == null)
    {
        g_hClientDisabledGroups[client] = new StringMap();
    }
}

void ResetClientDisabledGroups(int client)
{
    EnsureClientGroupPreferenceMap(client);

    if (g_hClientDisabledGroups[client] != null)
    {
        g_hClientDisabledGroups[client].Clear();
    }
}

bool IsClientGroupDisabled(int client, const char[] groupName)
{
    if (client <= 0 || client > MaxClients || !groupName[0] || StrEqual(groupName, DEFAULT_GROUP))
    {
        return false;
    }

    char normalizedGroup[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalizedGroup, sizeof(normalizedGroup)))
    {
        return false;
    }

    EnsureClientGroupPreferenceMap(client);

    int disabled = 0;
    return g_hClientDisabledGroups[client] != null
        && g_hClientDisabledGroups[client].GetValue(normalizedGroup, disabled)
        && disabled != 0;
}

bool SetClientGroupDisabled(int client, const char[] groupName, bool disabled)
{
    if (client <= 0 || client > MaxClients || !groupName[0] || StrEqual(groupName, DEFAULT_GROUP))
    {
        return false;
    }

    char normalizedGroup[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalizedGroup, sizeof(normalizedGroup)) || StrEqual(normalizedGroup, DEFAULT_GROUP))
    {
        return false;
    }

    EnsureClientGroupPreferenceMap(client);

    if (g_hClientDisabledGroups[client] == null)
    {
        return false;
    }

    if (disabled)
    {
        g_hClientDisabledGroups[client].SetValue(normalizedGroup, 1);
    }
    else
    {
        g_hClientDisabledGroups[client].Remove(normalizedGroup);
    }

    return true;
}

void BuildDisabledGroupCookieValue(int client, char[] value, int valueLen)
{
    value[0] = '\0';

    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    EnsureClientGroupPreferenceMap(client);
    if (g_hClientDisabledGroups[client] == null || gGroupNames == null)
    {
        return;
    }

    char groupName[MAX_GROUP_NAME];
    int disabled = 0;

    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (StrEqual(groupName, DEFAULT_GROUP))
        {
            continue;
        }

        if (!g_hClientDisabledGroups[client].GetValue(groupName, disabled) || disabled == 0)
        {
            continue;
        }

        if (value[0])
        {
            StrCat(value, valueLen, ",");
        }

        StrCat(value, valueLen, groupName);
    }
}

void ParseDisabledGroupCookieValue(int client, const char[] rawValue)
{
    ResetClientDisabledGroups(client);

    if (!rawValue[0])
    {
        return;
    }

    char working[MAX_GROUP_PREF_VALUE];
    strcopy(working, sizeof(working), rawValue);
    TrimString(working);
    Strings_ToLower(working, sizeof(working));

    if (!working[0])
    {
        return;
    }

    char token[MAX_GROUP_NAME];
    int start = 0;
    int len = strlen(working);

    while (start < len)
    {
        int commaPos = -1;
        for (int i = start; i < len; i++)
        {
            if (working[i] == ',')
            {
                commaPos = i;
                break;
            }
        }

        int end = (commaPos == -1) ? len : commaPos;
        int tokenLen = end - start;

        if (tokenLen > 0 && tokenLen < sizeof(token))
        {
            for (int i = 0; i < tokenLen; i++)
            {
                token[i] = working[start + i];
            }
            token[tokenLen] = '\0';

            TrimString(token);
            Strings_ToLower(token, sizeof(token));

            if (token[0] && !StrEqual(token, DEFAULT_GROUP) && IsKnownGroup(token))
            {
                SetClientGroupDisabled(client, token, true);
            }
        }

        start = end + 1;
        if (start > len)
        {
            break;
        }
    }
}

