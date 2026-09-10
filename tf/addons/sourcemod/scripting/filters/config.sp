static void Filters_EnsureConfigFile(char[] configPath, int maxlen)
{
    BuildPath(Path_SM, configPath, maxlen, "configs/filters.cfg");

    if (!FileExists(configPath))
    {
        LogMessage("Config file not found, creating default: %s", configPath);
        CreateDefaultConfig(configPath);
    }
}

static bool Filters_BeginConfigSection(KeyValues kv, const char[] sectionName)
{
    if (!kv.JumpToKey(sectionName))
    {
        return false;
    }

    if (!kv.GotoFirstSubKey(false))
    {
        kv.GoBack();
        return false;
    }

    return true;
}

static void Filters_EndConfigSection(KeyValues kv)
{
    kv.GoBack();
    kv.GoBack();
}

static void Filters_ResetLoadedConfig()
{
    g_FilterCount = 0;
    g_CaseInsensitiveFilterCount = 0;
    g_GoodnightStopperCount = 0;
    g_BlacklistCount = 0;
    g_Blacklist50Count = 0;
    g_ForcedStatusCount = 0;
    g_AllowedCommandsCount = 0;

    if (g_WebNameColors == null)
    {
        g_WebNameColors = new StringMap();
    }
    else
    {
        g_WebNameColors.Clear();
    }
}

static void Filters_LoadFilterWords(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "filter_words"))
    {
        return;
    }

    do
    {
        if (g_FilterCount >= MAX_FILTERS)
        {
            LogError("Maximum filter limit reached (%d)", MAX_FILTERS);
            break;
        }

        char original[MAX_WORD_LENGTH];
        char filtered[MAX_WORD_LENGTH];
        kv.GetSectionName(original, sizeof(original));
        kv.GetString(NULL_STRING, filtered, sizeof(filtered));

        strcopy(g_FilterWords[g_FilterCount], MAX_WORD_LENGTH, original);
        strcopy(g_ReplacementWords[g_FilterCount], MAX_WORD_LENGTH, filtered);
        g_FilterCount++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadCaseInsensitiveFilterWords(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "filters_case_insensitive"))
    {
        return;
    }

    do
    {
        if (g_CaseInsensitiveFilterCount >= MAX_FILTERS)
        {
            LogError("Maximum case-insensitive filter limit reached (%d)", MAX_FILTERS);
            break;
        }

        char original[MAX_WORD_LENGTH];
        char filtered[MAX_WORD_LENGTH];
        kv.GetSectionName(original, sizeof(original));
        kv.GetString(NULL_STRING, filtered, sizeof(filtered));

        strcopy(g_CaseInsensitiveFilterWords[g_CaseInsensitiveFilterCount], MAX_WORD_LENGTH, original);
        strcopy(g_CaseInsensitiveReplacementWords[g_CaseInsensitiveFilterCount], MAX_WORD_LENGTH, filtered);
        g_CaseInsensitiveFilterCount++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadGoodnightStopperWords(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "filters_goodnightstopper"))
    {
        return;
    }

    do
    {
        if (g_GoodnightStopperCount >= MAX_FILTERS)
        {
            LogError("Maximum goodnight stopper limit reached (%d)", MAX_FILTERS);
            break;
        }

        char trigger[MAX_WORD_LENGTH];
        char replacement[MAX_FILTER_REPLACEMENT_LENGTH];
        kv.GetSectionName(trigger, sizeof(trigger));
        kv.GetString(NULL_STRING, replacement, sizeof(replacement));
        TrimString(trigger);
        TrimString(replacement);
        if (!trigger[0] || !replacement[0])
        {
            continue;
        }

        strcopy(g_GoodnightStopperWords[g_GoodnightStopperCount], MAX_WORD_LENGTH, trigger);
        strcopy(g_GoodnightStopperReplacements[g_GoodnightStopperCount], MAX_FILTER_REPLACEMENT_LENGTH, replacement);
        g_GoodnightStopperCount++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadBlacklistWords(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "blacklist_words"))
    {
        return;
    }

    do
    {
        if (g_BlacklistCount >= MAX_BLACKLIST)
        {
            LogError("Maximum blacklist limit reached (%d)", MAX_BLACKLIST);
            break;
        }

        char word[MAX_WORD_LENGTH];
        kv.GetSectionName(word, sizeof(word));
        strcopy(g_BlacklistWords[g_BlacklistCount], MAX_WORD_LENGTH, word);
        g_BlacklistCount++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadBlacklist50Words(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "blacklist_words_50"))
    {
        return;
    }

    do
    {
        if (g_Blacklist50Count >= MAX_BLACKLIST)
        {
            LogError("Maximum blacklist_50 limit reached (%d)", MAX_BLACKLIST);
            break;
        }

        char word[MAX_WORD_LENGTH];
        kv.GetSectionName(word, sizeof(word));
        strcopy(g_BlacklistWords50[g_Blacklist50Count], MAX_WORD_LENGTH, word);
        g_Blacklist50Count++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static bool Filters_IsValidForcedStatusType(const char[] status)
{
    return StrEqual(status, "redlist")
        || StrEqual(status, "filter_whitelist");
}

static void Filters_LoadForcedStatuses(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "force_status"))
    {
        return;
    }

    do
    {
        if (g_ForcedStatusCount >= MAX_FORCED_STATUS)
        {
            LogError("Maximum forced status limit reached (%d)", MAX_FORCED_STATUS);
            break;
        }

        char steamid[32];
        char status[32];
        kv.GetSectionName(steamid, sizeof(steamid));
        kv.GetString(NULL_STRING, status, sizeof(status));

        if (Filters_IsValidForcedStatusType(status))
        {
            strcopy(g_ForcedStatusSteamIDs[g_ForcedStatusCount], sizeof(g_ForcedStatusSteamIDs[]), steamid);
            strcopy(g_ForcedStatusTypes[g_ForcedStatusCount], sizeof(g_ForcedStatusTypes[]), status);
            g_ForcedStatusCount++;
        }
        else
        {
            LogError("Invalid status type '%s' for SteamID '%s'", status, steamid);
        }
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadAllowedCommands(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "commands"))
    {
        return;
    }

    do
    {
        if (g_AllowedCommandsCount >= MAX_COMMANDS)
        {
            LogError("Maximum commands limit reached (%d)", MAX_COMMANDS);
            break;
        }

        char command[MAX_WORD_LENGTH];
        kv.GetSectionName(command, sizeof(command));
        strcopy(g_AllowedCommands[g_AllowedCommandsCount], MAX_WORD_LENGTH, command);
        g_AllowedCommandsCount++;
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

static void Filters_LoadWebNameOverrides(KeyValues kv)
{
    if (!Filters_BeginConfigSection(kv, "webnames"))
    {
        return;
    }

    do
    {
        char name[128];
        char color[32];
        kv.GetSectionName(name, sizeof(name));
        kv.GetString(NULL_STRING, color, sizeof(color));

        TrimString(name);
        TrimString(color);
        if (!name[0] || !color[0])
        {
            continue;
        }

        StringToLower(name);
        g_WebNameColors.SetString(name, color);
    }
    while (kv.GotoNextKey(false));

    Filters_EndConfigSection(kv);
}

void LoadFilterConfig()
{
    char configPath[PLATFORM_MAX_PATH];
    Filters_EnsureConfigFile(configPath, sizeof(configPath));

    KeyValues kv = new KeyValues("filters");
    if (!kv.ImportFromFile(configPath))
    {
        LogError("Failed to parse config file: %s", configPath);
        delete kv;
        SetFailState("Failed to parse filters.cfg");
        return;
    }

    Filters_ResetLoadedConfig();
    Filters_LoadFilterWords(kv);
    Filters_LoadCaseInsensitiveFilterWords(kv);
    Filters_LoadGoodnightStopperWords(kv);
    Filters_LoadBlacklistWords(kv);
    Filters_LoadBlacklist50Words(kv);
    Filters_LoadForcedStatuses(kv);
    Filters_LoadAllowedCommands(kv);
    Filters_LoadWebNameOverrides(kv);

    delete kv;

    PrintToServer("[Word Filter] Loaded %d filter words, %d case-insensitive filters, %d goodnight stoppers, %d blacklist words, %d blacklist_50 words, %d forced status entries, and %d commands",
                  g_FilterCount, g_CaseInsensitiveFilterCount, g_GoodnightStopperCount, g_BlacklistCount, g_Blacklist50Count, g_ForcedStatusCount, g_AllowedCommandsCount);
}

static bool Filters_IsTriggerWordCharacter(char value)
{
    return (value >= 'a' && value <= 'z')
        || (value >= 'A' && value <= 'Z')
        || (value >= '0' && value <= '9')
        || value == '_';
}

static bool Filters_ContainsWholeTrigger(const char[] message, const char[] trigger)
{
    int messageLength = strlen(message);
    int triggerLength = strlen(trigger);
    if (triggerLength <= 0 || triggerLength > messageLength)
    {
        return false;
    }

    for (int start = 0; start + triggerLength <= messageLength; start++)
    {
        bool matches = true;
        for (int offset = 0; offset < triggerLength; offset++)
        {
            if (CharToLower(message[start + offset]) != CharToLower(trigger[offset]))
            {
                matches = false;
                break;
            }
        }

        if (matches
            && (start == 0 || !Filters_IsTriggerWordCharacter(message[start - 1]))
            && (start + triggerLength == messageLength || !Filters_IsTriggerWordCharacter(message[start + triggerLength])))
        {
            return true;
        }
    }

    return false;
}

bool Filters_FindGoodnightStopperReplacement(int client, const char[] message, char[] replacement, int maxlen)
{
    replacement[0] = '\0';
    if (Filters_GetAdminsDbLevel(client) > 0)
    {
        return false;
    }

    for (int i = 0; i < g_GoodnightStopperCount; i++)
    {
        if (!Filters_ContainsWholeTrigger(message, g_GoodnightStopperWords[i]))
        {
            continue;
        }

        strcopy(replacement, maxlen, g_GoodnightStopperReplacements[i]);
        return true;
    }

    return false;
}

public void FilterString(char[] input, int maxlen)
{
    bool caseSensitive = g_hFiltersCaseSensitive == null ? true : g_hFiltersCaseSensitive.BoolValue;

    // Apply word filters
    for (int i = 0; i < g_FilterCount; i++)
    {
        ReplaceString(input, maxlen, g_FilterWords[i], g_ReplacementWords[i], caseSensitive);
    }

    for (int i = 0; i < g_CaseInsensitiveFilterCount; i++)
    {
        ReplaceString(input, maxlen, g_CaseInsensitiveFilterWords[i], g_CaseInsensitiveReplacementWords[i], false);
    }
}

// Helper function to convert string to lowercase
void StringToLower(char[] input)
{
    int len = strlen(input);
    for (int i = 0; i < len; i++)
    {
        input[i] = CharToLower(input[i]);
    }
}

bool Filters_GetWebNameColor(const char[] name, char[] outColor, int maxlen)
{
    if (g_WebNameColors == null)
    {
        return false;
    }

    char key[128];
    strcopy(key, sizeof(key), name);
    TrimString(key);
    if (!key[0])
    {
        return false;
    }

    StringToLower(key);
    return g_WebNameColors.GetString(key, outColor, maxlen);
}

// Creates default config file
void CreateDefaultConfig(const char[] path)
{
    File file = OpenFile(path, "w");
    
    if (file == null)
    {
        LogError("Failed to create config file: %s", path);
        SetFailState("Could not create filters.cfg");
        return;
    }
    
    // Write default config structure
    file.WriteLine("\"filters\"");
    file.WriteLine("{");
    file.WriteLine("    \"filter_words\"");
    file.WriteLine("    {");
    file.WriteLine("        \"badword1\"    \"filtered\"");
    file.WriteLine("        \"badword2\"    \"filtered\"");
    file.WriteLine("    }");
    file.WriteLine("    \"filters_case_insensitive\"");
    file.WriteLine("    {");
    file.WriteLine("        \"bruh\"    \"trans rights\"");
    file.WriteLine("    }");
    file.WriteLine("    \"filters_goodnightstopper\"");
    file.WriteLine("    {");
    file.WriteLine("        \"gn\"           \"I'm bringing a friend\"");
    file.WriteLine("        \"goodnight\"    \"I'm getting friends to join\"");
    file.WriteLine("        \"cya\"          \"my friends are gonna connect soon\"");
    file.WriteLine("    }");
    file.WriteLine("    \"blacklist_words\"");
    file.WriteLine("    {");
    file.WriteLine("        \"blockedword1\"    \"\"");
    file.WriteLine("        \"blockedword2\"    \"\"");
    file.WriteLine("        \"blockedword3\"    \"\"");
    file.WriteLine("    }");
    file.WriteLine("    \"blacklist_words_50\"");
    file.WriteLine("    {");
    file.WriteLine("        \"softblocked1\"    \"\"");
    file.WriteLine("        \"softblocked2\"    \"\"");
    file.WriteLine("    }");
    file.WriteLine("    \"force_status\"");
    file.WriteLine("    {");
    file.WriteLine("        \"STEAM_0:0:33445566\"    \"redlist\"");
    file.WriteLine("        \"STEAM_0:0:11223344\"    \"filter_whitelist\"");
    file.WriteLine("    }");
    file.WriteLine("    \"commands\"");
    file.WriteLine("    {");
    file.WriteLine("        \"rtv\"    \"\"");
    file.WriteLine("        \"unrtv\"    \"\"");
    file.WriteLine("        \"nominate\"    \"\"");
    file.WriteLine("        \"nextmap\"    \"\"");
    file.WriteLine("        \"motd\"    \"\"");
    file.WriteLine("    }");
    file.WriteLine("}");
    
    delete file;
    
    LogMessage("Default config file created: %s", path);
}

