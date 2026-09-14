public int Native_ShouldPlay(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return SaySounds_ShouldPlay(client);
}

public int Native_PlaySoundToOptedIn(Handle plugin, int numParams)
{
    char soundPath[PLATFORM_MAX_PATH];
    GetNativeString(1, soundPath, sizeof(soundPath));
    TrimString(soundPath);

    if (!soundPath[0])
    {
        return 0;
    }

    char groupName[MAX_GROUP_NAME];
    if (numParams >= 2)
    {
        GetNativeString(2, groupName, sizeof(groupName));
        TrimString(groupName);
        Strings_ToLower(groupName, sizeof(groupName));
    }
    else
    {
        groupName[0] = '\0';
    }

    NormalizeSoundPath(soundPath, sizeof(soundPath));

    if (!groupName[0])
    {
        strcopy(groupName, sizeof(groupName), DEFAULT_GROUP);
    }

    PrecacheSound(soundPath, true);
    if (PlaySaySound(soundPath, groupName))
    {
        LogSaySoundUsage("saysound_used", 0, 0, "", soundPath, groupName, false, "", true, "api_sound");
    }
    return 0;
}

public int Native_PlayCommand(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 0 || client > MaxClients)
    {
        return 0;
    }

    bool forcePlayback = false;
    if (numParams >= 3)
    {
        forcePlayback = view_as<bool>(GetNativeCell(3));
    }

    bool bypassAPIOnly = true;
    if (numParams >= 4)
    {
        bypassAPIOnly = view_as<bool>(GetNativeCell(4));
    }

    char commandName[MAX_COMMAND_NAME * 4];
    GetNativeString(2, commandName, sizeof(commandName));
    TrimString(commandName);
    Strings_ToLower(commandName, sizeof(commandName));

    if (!commandName[0])
    {
        return 0;
    }

    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    bool restricted = false;
    bool paidRestricted = false;
    if (!GetCommandSoundDataForClientEx(client, commandName, soundPath, sizeof(soundPath), groupName, sizeof(groupName), restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup), bypassAPIOnly, true))
    {
        return 0;
    }

    PrecacheSound(soundPath, true);
    bool played = PlaySaySoundToTarget(client, soundPath, groupName, forcePlayback);
    if (played)
    {
        LogSaySoundUsage("saysound_used", client, client, selectedCommand, soundPath, groupName, fromGroup, sourceGroup, true, "api_command");
    }
    return played ? 1 : 0;
}

public int Native_PlayCommandAs(Handle plugin, int numParams)
{
    int sourceClient = GetNativeCell(1);
    int targetClient = GetNativeCell(2);
    if (sourceClient <= 0 || sourceClient > MaxClients || !IsClientInGame(sourceClient))
    {
        return 0;
    }
    if (targetClient < 0 || targetClient > MaxClients)
    {
        return 0;
    }

    bool forcePlayback = false;
    if (numParams >= 4)
    {
        forcePlayback = view_as<bool>(GetNativeCell(4));
    }

    bool bypassAPIOnly = true;
    if (numParams >= 5)
    {
        bypassAPIOnly = view_as<bool>(GetNativeCell(5));
    }

    char commandName[MAX_COMMAND_NAME * 4];
    GetNativeString(3, commandName, sizeof(commandName));
    TrimString(commandName);
    Strings_ToLower(commandName, sizeof(commandName));

    if (!commandName[0])
    {
        return 0;
    }

    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    bool restricted = false;
    bool paidRestricted = false;
    if (!GetCommandSoundDataForClientEx(sourceClient, commandName, soundPath, sizeof(soundPath), groupName, sizeof(groupName), restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup), bypassAPIOnly, true))
    {
        return 0;
    }

    PrecacheSound(soundPath, true);
    bool played = PlaySaySoundToTarget(targetClient, soundPath, groupName, forcePlayback);
    if (played)
    {
        LogSaySoundUsage("saysound_used", sourceClient, targetClient, selectedCommand, soundPath, groupName, fromGroup, sourceGroup, true, "api_command_as");
    }
    return played ? 1 : 0;
}

public int Native_CanClientUseCommand(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return 0;
    }

    char commandName[MAX_COMMAND_NAME * 4];
    GetNativeString(2, commandName, sizeof(commandName));
    TrimString(commandName);
    Strings_ToLower(commandName, sizeof(commandName));

    bool bypassAPIOnly = true;
    if (numParams >= 3)
    {
        bypassAPIOnly = view_as<bool>(GetNativeCell(3));
    }

    return CanClientUseSaySoundInput(client, commandName, bypassAPIOnly);
}

public int Native_IsCommandPaid(Handle plugin, int numParams)
{
    char commandName[MAX_COMMAND_NAME * 4];
    GetNativeString(1, commandName, sizeof(commandName));
    TrimString(commandName);
    Strings_ToLower(commandName, sizeof(commandName));

    return IsSaySoundInputPaid(commandName);
}

public int Native_GetCommandGroup(Handle plugin, int numParams)
{
    char commandName[MAX_COMMAND_NAME * 4];
    GetNativeString(1, commandName, sizeof(commandName));
    TrimString(commandName);
    Strings_ToLower(commandName, sizeof(commandName));

    char groupName[MAX_GROUP_NAME];
    bool found = GetSaySoundInputGroup(commandName, groupName, sizeof(groupName));

    int groupLen = GetNativeCell(3);
    if (groupLen > 0)
    {
        SetNativeString(2, found ? groupName : "", groupLen);
    }

    return found;
}

public Action Command_SetVolume(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        PrintToServer("[SaySounds] This command can only be used by players.");
        return Plugin_Handled;
    }

    // Wait for cookies to load before allowing changes
    if (GetCmdArgs() < 1)
    {
        PrintToChat(client, "[SaySounds] Usage: !vol <0.0 - 1.0> (current %.2f)", GetClientVolume(client));
        return Plugin_Handled;
    }

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    HandleVolumeCommand(client, arg);
    return Plugin_Handled;
}

bool AppendSoundPreferenceCommand(int client, const char[] commandName, char[] aggregated, int aggregatedLen, int &validCount, bool &anyInvalid)
{
    if (!CanClientUseSaySoundCommand(client, commandName))
    {
        anyInvalid = true;
        return false;
    }

    if (PreferenceListHasCommand(aggregated, commandName))
    {
        return true;
    }

    if (validCount >= MAX_SOUND_OPTIONS)
    {
        anyInvalid = true;
        return false;
    }

    int currentLen = strlen(aggregated);
    int needed = (currentLen > 0 ? 1 : 0) + strlen(commandName);
    if (currentLen + needed >= aggregatedLen - 1)
    {
        anyInvalid = true;
        return false;
    }

    if (currentLen > 0)
    {
        StrCat(aggregated, aggregatedLen, ",");
    }

    StrCat(aggregated, aggregatedLen, commandName);
    validCount++;
    return true;
}

static bool AppendSoundPreferenceGroup(int client, const char[] groupName, char[] aggregated, int aggregatedLen, int &validCount, bool &anyInvalid)
{
    char normalizedGroup[MAX_GROUP_NAME];
    if (!ResolveKnownGroupName(groupName, normalizedGroup, sizeof(normalizedGroup)))
    {
        anyInvalid = true;
        return false;
    }

    if (!CanClientUseSaySoundGroup(client, normalizedGroup))
    {
        anyInvalid = true;
        return false;
    }

    bool addedAny = false;
    char currentCommand[MAX_COMMAND_NAME];
    char currentGroup[MAX_GROUP_NAME];

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

        if (AppendSoundPreferenceCommand(client, currentCommand, aggregated, aggregatedLen, validCount, anyInvalid))
        {
            addedAny = true;
        }
    }

    if (!addedAny)
    {
        anyInvalid = true;
    }

    return addedAny;
}

static bool BuildSoundPreferenceList(int client, const char[] input, char[] aggregated, int aggregatedLen, bool &anyInvalid, bool allowGroups)
{
    aggregated[0] = '\0';
    anyInvalid = false;

    if (!input[0])
    {
        return false;
    }

    char token[MAX_COMMAND_NAME];
    int len = strlen(input);
    int start = 0;
    int validCount = 0;

    while (start < len)
    {
        // Find next comma starting from current position
        int commaPos = -1;
        for (int i = start; i < len; i++)
        {
            if (input[i] == ',')
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
                token[i] = input[start + i];
            }
            token[tokenLen] = '\0';

            TrimString(token);
            Strings_ToLower(token, sizeof(token));

            if (token[0])
            {
                char path[PLATFORM_MAX_PATH];
                if (gSoundMap.GetString(token, path, sizeof(path)))
                {
                    AppendSoundPreferenceCommand(client, token, aggregated, aggregatedLen, validCount, anyInvalid);
                }
                else if (allowGroups)
                {
                    AppendSoundPreferenceGroup(client, token, aggregated, aggregatedLen, validCount, anyInvalid);
                }
                else
                {
                    anyInvalid = true;
                }
            }
        }

        // Move past the comma
        start = end + 1;
        
        // Safety check: if we've moved past the end, break
        if (start > len)
        {
            break;
        }
    }

    return (validCount > 0);
}

public Action Command_SetDeathSound(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    if (!gConfigLoaded)
    {
        PrintToChat(client, "[SaySounds] Sounds are not ready yet. Try again soon.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "[SaySounds] Usage: !diesound <command/group[,command/group...]|none> (current: %s)", g_szDeathSound[client][0] ? g_szDeathSound[client] : "none");
        return Plugin_Handled;
    }

    char buffer[256];
    GetCmdArgString(buffer, sizeof(buffer));
    TrimString(buffer);
    Strings_ToLower(buffer, sizeof(buffer));

    if (!buffer[0] || StrEqual(buffer, "none") || StrEqual(buffer, "off"))
    {
        g_szDeathSound[client][0] = '\0';
        SaveDeathSoundPreference(client);
        PrintToChat(client, "[SaySounds] Death sound cleared.");
        LogSoundPreferenceChange(client, SaySoundPreference_Death, "");
        return Plugin_Handled;
    }

    char aggregated[256];
    bool anyInvalid = false;
    if (!BuildSoundPreferenceList(client, buffer, aggregated, sizeof(aggregated), anyInvalid, true))
    {
        PrintToChat(client, "[SaySounds] No valid sounds supplied. Use !sounds to list commands.");
        return Plugin_Handled;
    }

    strcopy(g_szDeathSound[client], 256, aggregated);
    SaveDeathSoundPreference(client);
    PrintToChat(client, "[SaySounds] Death sound set to %s.", aggregated);
    LogSoundPreferenceChange(client, SaySoundPreference_Death, aggregated);
    if (anyInvalid)
    {
        PrintToChat(client, "[SaySounds] Some sounds were unknown and ignored.");
    }
    return Plugin_Handled;
}

public Action Command_SetKillSound(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    if (!gConfigLoaded)
    {
        PrintToChat(client, "[SaySounds] Sounds are not ready yet. Try again soon.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "[SaySounds] Usage: !killsound <command/group[,command/group...]|none> (current: %s)", g_szKillSound[client][0] ? g_szKillSound[client] : "none");
        return Plugin_Handled;
    }

    char buffer[256];
    GetCmdArgString(buffer, sizeof(buffer));
    TrimString(buffer);
    Strings_ToLower(buffer, sizeof(buffer));

    if (!buffer[0] || StrEqual(buffer, "none") || StrEqual(buffer, "off"))
    {
        g_szKillSound[client][0] = '\0';
        SaveKillSoundPreference(client);
        PrintToChat(client, "[SaySounds] Kill sound cleared.");
        LogSoundPreferenceChange(client, SaySoundPreference_Kill, "");
        return Plugin_Handled;
    }

    char aggregated[256];
    bool anyInvalid = false;
    if (!BuildSoundPreferenceList(client, buffer, aggregated, sizeof(aggregated), anyInvalid, true))
    {
        PrintToChat(client, "[SaySounds] No valid sounds supplied. Use !sounds to list commands.");
        return Plugin_Handled;
    }

    strcopy(g_szKillSound[client], 256, aggregated);  // FIXED: Changed from g_szDeathSound to g_szKillSound
    SaveKillSoundPreference(client);
    PrintToChat(client, "[SaySounds] Kill sound set to %s.", aggregated);
    LogSoundPreferenceChange(client, SaySoundPreference_Kill, aggregated);
    if (anyInvalid)
    {
        PrintToChat(client, "[SaySounds] Some sounds were unknown and ignored.");
    }
    return Plugin_Handled;
}

public Action Command_PlaySpecificSound(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    if (!gConfigLoaded)
    {
        PrintToChat(client, "[SaySounds] Sounds are not ready yet. Try again soon.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "[SaySounds] Usage: !saysound <command|group>");
        return Plugin_Handled;
    }

    char arg[MAX_COMMAND_NAME * 4];
    GetCmdArgString(arg, sizeof(arg));
    StripQuotes(arg);
    TrimString(arg);
    Strings_ToLower(arg, sizeof(arg));

    if (!arg[0])
    {
        PrintToChat(client, "[SaySounds] Usage: !saysound <command|group>");
        return Plugin_Handled;
    }

    char path[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    bool restricted = false;
    bool paidRestricted = false;
    if (!GetCommandSoundDataForClientEx(client, arg, path, sizeof(path), groupName, sizeof(groupName), restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup)))
    {
        if (restricted)
        {
            PrintToChat(client, "[SaySounds] That sound group is only available through the API.");
            return Plugin_Handled;
        }

        if (paidRestricted)
        {
            PrintToChat(client, "[SaySounds] That sound group requires a shop purchase. Use !shop.");
            return Plugin_Handled;
        }

        PrintToChat(client, "[SaySounds] Unknown sound '%s'. Use !sounds to list commands.", arg);
        return Plugin_Handled;
    }

    float now = GetGameTime();
    if (g_fNextAllowedSound[client] > now)
    {
        float remaining = g_fNextAllowedSound[client] - now;
        PrintToChat(client, "[SaySounds] Please wait %.1f seconds before triggering another sound.", remaining);
        return Plugin_Handled;
    }

    if (PlaySaySoundToTarget(0, path, groupName))
    {
        LogSaySoundUsage("saysound_used", client, 0, selectedCommand, path, groupName, fromGroup, sourceGroup, false, "command");
    }
    g_fNextAllowedSound[client] = GetGameTime() + DEFAULT_COOLDOWN;
    return Plugin_Handled;
}

