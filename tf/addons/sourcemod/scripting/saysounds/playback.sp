void HandleVolumeCommand(int client, const char[] arg)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (!arg[0])
    {
        PrintToChat(client, "[SaySounds] Usage: !vol <0.0 - 1.0> (current %.2f)", GetClientVolume(client));
        return;
    }

    float value = StringToFloat(arg);
    if (value < MIN_VOLUME || value > MAX_VOLUME)
    {
        PrintToChat(client, "[SaySounds] Volume must be between %.1f and %.1f.", MIN_VOLUME, MAX_VOLUME);
        return;
    }

    g_fClientVolume[client] = value;
    SaveVolumePreference(client);
    PrintToChat(client, "[SaySounds] Volume set to %.2f.", value);
}

float GetDefaultVolume()
{
    if (g_hDefaultVolume == null)
    {
        return 0.5;
    }

    float volume = g_hDefaultVolume.FloatValue;
    if (volume < MIN_VOLUME)
    {
        return MIN_VOLUME;
    }

    if (volume > MAX_VOLUME)
    {
        return MAX_VOLUME;
    }

    return volume;
}

float GetOptInVolume()
{
    float volume = GetDefaultVolume();
    if (volume <= 0.0)
    {
        return 0.5;
    }

    return volume;
}

float GetClientVolume(int client)
{
    float volume = g_fClientVolume[client];
    if (volume < 0.0)
    {
        volume = 0.0;
    }
    else if (volume > 0.0 && volume < MIN_VOLUME)
    {
        volume = MIN_VOLUME;
    }
    else if (volume > MAX_VOLUME)
    {
        volume = MAX_VOLUME;
    }
    return volume;
}

void LoadVolumePreference(int client)
{
    g_fClientVolume[client] = GetDefaultVolume();

    if (g_hVolumeCookie == INVALID_HANDLE)
    {
        return;
    }

    char value[16];
    GetClientCookie(client, g_hVolumeCookie, value, sizeof(value));

    if (!value[0])
    {
        return;
    }

    float parsed = StringToFloat(value);
    if (parsed < MIN_VOLUME)
    {
        parsed = MIN_VOLUME;
    }
    else if (parsed > MAX_VOLUME)
    {
        parsed = MAX_VOLUME;
    }

    g_fClientVolume[client] = parsed;
}

void SaveVolumePreference(int client)
{
    if (g_hVolumeCookie == INVALID_HANDLE)
        return;

    if (!AreClientCookiesCached(client))
        return;

    char value[16];
    float volume = GetClientVolume(client);
    Format(value, sizeof(value), "%.2f", volume);
    SetClientCookie(client, g_hVolumeCookie, value);
}

void LoadDisabledGroupPreferences(int client)
{
    ResetClientDisabledGroups(client);

    if (g_hDisabledGroupsCookie == INVALID_HANDLE)
    {
        return;
    }

    char value[MAX_GROUP_PREF_VALUE];
    GetClientCookie(client, g_hDisabledGroupsCookie, value, sizeof(value));
    ParseDisabledGroupCookieValue(client, value);
}

void SaveDisabledGroupPreferences(int client)
{
    if (g_hDisabledGroupsCookie == INVALID_HANDLE || !AreClientCookiesCached(client))
        return;

    char value[MAX_GROUP_PREF_VALUE];
    BuildDisabledGroupCookieValue(client, value, sizeof(value));
    SetClientCookie(client, g_hDisabledGroupsCookie, value);
}

bool GetCommandSoundData(const char[] commandName, char[] soundPath, int soundLen, char[] groupName, int groupLen)
{
    if (!gConfigLoaded)
    {
        return false;
    }

    char working[MAX_COMMAND_NAME * 4];
    strcopy(working, sizeof(working), commandName);
    TrimString(working);
    Strings_ToLower(working, sizeof(working));

    if (!working[0])
    {
        return false;
    }

    char chosen[MAX_COMMAND_NAME];
    if (StrContains(working, ",", false) != -1)
    {
        char options[MAX_SOUND_OPTIONS][MAX_COMMAND_NAME];
        int optionCount = 0;

        char token[MAX_COMMAND_NAME];
        int start = 0;
        int len = strlen(working);
        
        while (start < len && optionCount < MAX_SOUND_OPTIONS)
        {
            // Find next comma starting from current position
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
                // Extract token
                for (int i = 0; i < tokenLen; i++)
                {
                    token[i] = working[start + i];
                }
                token[tokenLen] = '\0';

                TrimString(token);
                Strings_ToLower(token, sizeof(token));

                if (token[0])
                {
                    char dummy[PLATFORM_MAX_PATH];
                    if (gSoundMap.GetString(token, dummy, sizeof(dummy)))
                    {
                        strcopy(options[optionCount], sizeof(options[]), token);
                        optionCount++;
                    }
                }
            }

            start = end + 1;
            
            // Safety check
            if (start > len)
            {
                break;
            }
        }

        if (optionCount == 0)
        {
            return false;
        }

        int pick = GetRandomInt(0, optionCount - 1);
        strcopy(chosen, sizeof(chosen), options[pick]);
    }
    else
    {
        strcopy(chosen, sizeof(chosen), working);
    }

    if (!gSoundMap.GetString(chosen, soundPath, soundLen))
    {
        return false;
    }

    if (!gSoundGroupMap.GetString(chosen, groupName, groupLen))
    {
        strcopy(groupName, groupLen, DEFAULT_GROUP);
    }

    return true;
}

static bool GetRandomCommandInGroupForClient(int client, const char[] groupName, char[] commandName, int commandLen, bool &restricted, bool &paidRestricted, bool bypassAPIOnly = false, bool bypassPaid = false)
{
    if (commandLen > 0)
    {
        commandName[0] = '\0';
    }

    char normalizedGroup[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalizedGroup, sizeof(normalizedGroup)))
    {
        return false;
    }

    if (!CanUseAPIOnlySaySoundGroup(normalizedGroup, bypassAPIOnly))
    {
        restricted = true;
        return false;
    }

    if (!bypassPaid && !CanClientUsePaidSaysoundGroup(client, normalizedGroup))
    {
        paidRestricted = true;
        return false;
    }

    char currentCommand[MAX_COMMAND_NAME];
    char currentGroup[MAX_GROUP_NAME];
    int matchCount = 0;

    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, currentCommand, sizeof(currentCommand));
        if (!gSoundGroupMap.GetString(currentCommand, currentGroup, sizeof(currentGroup)))
        {
            strcopy(currentGroup, sizeof(currentGroup), DEFAULT_GROUP);
        }

        if (!StrEqual(currentGroup, normalizedGroup))
        {
            continue;
        }

        matchCount++;
        if (GetRandomInt(1, matchCount) == 1)
        {
            strcopy(commandName, commandLen, currentCommand);
        }
    }

    return matchCount > 0 && commandName[0] != '\0';
}

bool GetCommandOptionForClient(int client, const char[] inputName, char[] commandName, int commandLen, bool &restricted, bool &paidRestricted, bool bypassAPIOnly = false)
{
    bool fromGroup = false;
    char sourceGroup[MAX_GROUP_NAME];
    return GetCommandOptionForClientEx(client, inputName, commandName, commandLen, restricted, paidRestricted, fromGroup, sourceGroup, sizeof(sourceGroup), bypassAPIOnly);
}

static bool GetCommandOptionForClientEx(int client, const char[] inputName, char[] commandName, int commandLen, bool &restricted, bool &paidRestricted, bool &fromGroup, char[] sourceGroup, int sourceGroupLen, bool bypassAPIOnly = false, bool bypassPaid = false)
{
    if (commandLen > 0)
    {
        commandName[0] = '\0';
    }
    fromGroup = false;
    if (sourceGroupLen > 0)
    {
        sourceGroup[0] = '\0';
    }

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

        if (!CanUseAPIOnlySaySoundGroup(groupName, bypassAPIOnly))
        {
            restricted = true;
            return false;
        }

        if (!bypassPaid && !CanClientUsePaidSaysoundGroup(client, groupName))
        {
            paidRestricted = true;
            return false;
        }

        strcopy(commandName, commandLen, normalizedName);
        return true;
    }

    char normalizedGroup[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(normalizedName, normalizedGroup, sizeof(normalizedGroup)))
    {
        return false;
    }

    if (!GetRandomCommandInGroupForClient(client, normalizedGroup, commandName, commandLen, restricted, paidRestricted, bypassAPIOnly, bypassPaid))
    {
        return false;
    }

    fromGroup = true;
    strcopy(sourceGroup, sourceGroupLen, normalizedGroup);
    return true;
}

stock bool GetCommandSoundDataForClient(int client, const char[] commandNames, char[] soundPath, int soundLen, char[] groupName, int groupLen, bool &restricted, bool &paidRestricted, bool bypassAPIOnly = false)
{
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    return GetCommandSoundDataForClientEx(client, commandNames, soundPath, soundLen, groupName, groupLen, restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup), bypassAPIOnly);
}

bool GetCommandSoundDataForClientEx(int client, const char[] commandNames, char[] soundPath, int soundLen, char[] groupName, int groupLen, bool &restricted, bool &paidRestricted, char[] selectedCommand, int selectedCommandLen, bool &fromGroup, char[] sourceGroup, int sourceGroupLen, bool bypassAPIOnly = false, bool bypassPaid = false)
{
    restricted = false;
    paidRestricted = false;
    fromGroup = false;
    if (selectedCommandLen > 0)
    {
        selectedCommand[0] = '\0';
    }
    if (sourceGroupLen > 0)
    {
        sourceGroup[0] = '\0';
    }

    if (!gConfigLoaded)
    {
        return false;
    }

    char working[MAX_COMMAND_NAME * 4];
    strcopy(working, sizeof(working), commandNames);
    TrimString(working);
    Strings_ToLower(working, sizeof(working));

    if (!working[0])
    {
        return false;
    }

    if (StrContains(working, ",", false) == -1)
    {
        char chosen[MAX_COMMAND_NAME];
        if (!GetCommandOptionForClientEx(client, working, chosen, sizeof(chosen), restricted, paidRestricted, fromGroup, sourceGroup, sourceGroupLen, bypassAPIOnly, bypassPaid))
        {
            return false;
        }

        if (!GetCommandSoundData(chosen, soundPath, soundLen, groupName, groupLen))
        {
            return false;
        }

        strcopy(selectedCommand, selectedCommandLen, chosen);
        return true;
    }

    char options[MAX_SOUND_OPTIONS][MAX_COMMAND_NAME];
    bool optionFromGroup[MAX_SOUND_OPTIONS];
    char optionSourceGroups[MAX_SOUND_OPTIONS][MAX_GROUP_NAME];
    int optionCount = 0;
    char token[MAX_COMMAND_NAME];
    int start = 0;
    int len = strlen(working);

    while (start < len && optionCount < MAX_SOUND_OPTIONS)
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

            if (token[0])
            {
                char chosen[MAX_COMMAND_NAME];
                bool currentFromGroup = false;
                char currentSourceGroup[MAX_GROUP_NAME];
                if (GetCommandOptionForClientEx(client, token, chosen, sizeof(chosen), restricted, paidRestricted, currentFromGroup, currentSourceGroup, sizeof(currentSourceGroup), bypassAPIOnly, bypassPaid))
                {
                    strcopy(options[optionCount], sizeof(options[]), chosen);
                    optionFromGroup[optionCount] = currentFromGroup;
                    strcopy(optionSourceGroups[optionCount], sizeof(optionSourceGroups[]), currentSourceGroup);
                    optionCount++;
                }
            }
        }

        start = end + 1;
        if (start > len)
        {
            break;
        }
    }

    if (optionCount == 0)
    {
        return false;
    }

    int pick = GetRandomInt(0, optionCount - 1);
    if (!GetCommandSoundData(options[pick], soundPath, soundLen, groupName, groupLen))
    {
        return false;
    }

    strcopy(selectedCommand, selectedCommandLen, options[pick]);
    fromGroup = optionFromGroup[pick];
    strcopy(sourceGroup, sourceGroupLen, optionSourceGroups[pick]);
    return true;
}

static bool CanClientHearSaySoundGroup(int client, const char[] groupName)
{
    return !IsClientGroupDisabled(client, groupName);
}

bool CanPlaySaySoundToClient(int client, const char[] groupName, float &emitVolume, bool forcePlayback = false)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return false;
    }

    if (forcePlayback || (g_hForce != null && g_hForce.BoolValue) || IsGroupForced(groupName))
    {
        emitVolume = 1.0;
        return true;
    }

    emitVolume = GetClientVolume(client);
    if (emitVolume <= 0.0)
    {
        return false;
    }

    if (!CanClientHearSaySoundGroup(client, groupName))
    {
        return false;
    }

    return true;
}

static bool EmitSaySoundToClient(int client, const char[] soundPath, float emitVolume)
{
    if (emitVolume <= 0.0)
    {
        return false;
    }

    EmitSoundToClient(client, soundPath, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, emitVolume, SNDPITCH_NORMAL);
    return true;
}

bool PlaySaySoundToTarget(int client, const char[] soundPath, const char[] groupName, bool forcePlayback = false)
{
    bool played = false;

    if (client == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            float emitVolume;
            if (!CanPlaySaySoundToClient(i, groupName, emitVolume, forcePlayback))
            {
                continue;
            }

            if (EmitSaySoundToClient(i, soundPath, emitVolume))
            {
                played = true;
            }
        }

        return played;
    }

    float emitVolume;
    if (!CanPlaySaySoundToClient(client, groupName, emitVolume, forcePlayback))
    {
        return false;
    }

    return EmitSaySoundToClient(client, soundPath, emitVolume);
}

bool PlaySaySound(const char[] soundPath, const char[] groupName)
{
    return PlaySaySoundToTarget(0, soundPath, groupName);
}

