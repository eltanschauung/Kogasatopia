static void GetClientSoundPreferenceValue(int client, SaySoundPreferenceType type, char[] value, int valueLen)
{
    if (type == SaySoundPreference_Death)
    {
        strcopy(value, valueLen, g_szDeathSound[client]);
        return;
    }

    strcopy(value, valueLen, g_szKillSound[client]);
}

static void SetClientSoundPreferenceValue(int client, SaySoundPreferenceType type, const char[] value)
{
    if (type == SaySoundPreference_Death)
    {
        strcopy(g_szDeathSound[client], sizeof(g_szDeathSound[]), value);
        SaveDeathSoundPreference(client);
        return;
    }

    strcopy(g_szKillSound[client], sizeof(g_szKillSound[]), value);
    SaveKillSoundPreference(client);
}

bool PreferenceListHasCommand(const char[] preferenceValue, const char[] commandName)
{
    if (!preferenceValue[0] || !commandName[0])
    {
        return false;
    }

    char working[MAX_COMMAND_NAME * 4];
    strcopy(working, sizeof(working), preferenceValue);
    TrimString(working);
    Strings_ToLower(working, sizeof(working));

    char normalizedCommand[MAX_COMMAND_NAME];
    strcopy(normalizedCommand, sizeof(normalizedCommand), commandName);
    TrimString(normalizedCommand);
    Strings_ToLower(normalizedCommand, sizeof(normalizedCommand));

    char token[MAX_COMMAND_NAME];
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

            if (StrEqual(token, normalizedCommand))
            {
                return true;
            }
        }

        start = end + 1;
        if (start > len)
        {
            break;
        }
    }

    return false;
}

static int CountSelectedPreferenceCommands(const char[] preferenceValue)
{
    if (!preferenceValue[0])
    {
        return 0;
    }

    int count = 0;
    char token[MAX_COMMAND_NAME];
    char working[MAX_COMMAND_NAME * 4];
    strcopy(working, sizeof(working), preferenceValue);
    TrimString(working);
    Strings_ToLower(working, sizeof(working));

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
            if (token[0])
            {
                count++;
            }
        }

        start = end + 1;
        if (start > len)
        {
            break;
        }
    }

    return count;
}

static bool ToggleClientSoundPreferenceCommand(int client, SaySoundPreferenceType type, const char[] commandName, char[] updatedValue, int updatedLen)
{
    updatedValue[0] = '\0';

    if (client <= 0 || client > MaxClients || !commandName[0] || !gConfigLoaded)
    {
        return false;
    }

    char currentValue[MAX_COMMAND_NAME * 4];
    GetClientSoundPreferenceValue(client, type, currentValue, sizeof(currentValue));

    bool currentlyEnabled = PreferenceListHasCommand(currentValue, commandName);
    int enabledCount = CountSelectedPreferenceCommands(currentValue);
    if (!currentlyEnabled && enabledCount >= MAX_SOUND_OPTIONS)
    {
        return false;
    }

    char rebuilt[MAX_COMMAND_NAME * 4];
    rebuilt[0] = '\0';

    char currentCommand[MAX_COMMAND_NAME];
    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, currentCommand, sizeof(currentCommand));
        if (!CanClientUseSaySoundCommand(client, currentCommand))
        {
            continue;
        }

        bool shouldEnable = PreferenceListHasCommand(currentValue, currentCommand);
        if (StrEqual(currentCommand, commandName))
        {
            shouldEnable = !currentlyEnabled;
        }

        if (!shouldEnable)
        {
            continue;
        }

        int currentLen = strlen(rebuilt);
        int needed = strlen(currentCommand) + (currentLen > 0 ? 1 : 0);
        if (currentLen + needed >= sizeof(rebuilt))
        {
            return false;
        }

        if (currentLen > 0)
        {
            StrCat(rebuilt, sizeof(rebuilt), ",");
        }

        StrCat(rebuilt, sizeof(rebuilt), currentCommand);
    }

    SetClientSoundPreferenceValue(client, type, rebuilt);
    strcopy(updatedValue, updatedLen, rebuilt);
    return true;
}

static bool GetCommandGroupName(const char[] commandName, char[] groupName, int groupLen)
{
    if (!gSoundGroupMap.GetString(commandName, groupName, groupLen))
    {
        strcopy(groupName, groupLen, DEFAULT_GROUP);
    }

    return groupName[0] != '\0';
}

static bool IsCommandInSoundGroup(const char[] commandName, const char[] groupName)
{
    char commandGroup[MAX_GROUP_NAME];
    GetCommandGroupName(commandName, commandGroup, sizeof(commandGroup));
    return StrEqual(commandGroup, groupName);
}

static bool CanShowSoundPreferenceGroupInMenu(int client, const char[] groupName)
{
    return !IsGroupAPIOnly(groupName) && CanClientUseSaySoundGroup(client, groupName);
}

static bool CanShowSoundPreferenceCommandInMenu(int client, const char[] commandName)
{
    char groupName[MAX_GROUP_NAME];
    GetCommandGroupName(commandName, groupName, sizeof(groupName));
    return CanShowSoundPreferenceGroupInMenu(client, groupName);
}

static bool GetSoundPreferenceGroupState(int client, const char[] preferenceValue, const char[] groupName, bool &anyEnabled, bool &allEnabled)
{
    anyEnabled = false;
    allEnabled = true;

    if (!groupName[0] || StrEqual(groupName, DEFAULT_GROUP) || !IsKnownGroup(groupName) || !CanClientUseSaySoundGroup(client, groupName))
    {
        return false;
    }

    bool foundAny = false;
    char currentCommand[MAX_COMMAND_NAME];
    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, currentCommand, sizeof(currentCommand));
        if (!IsCommandInSoundGroup(currentCommand, groupName) || !CanShowSoundPreferenceCommandInMenu(client, currentCommand))
        {
            continue;
        }

        foundAny = true;
        if (PreferenceListHasCommand(preferenceValue, currentCommand))
        {
            anyEnabled = true;
        }
        else
        {
            allEnabled = false;
        }
    }

    if (!foundAny)
    {
        allEnabled = false;
        return false;
    }

    return true;
}

static bool ToggleClientSoundPreferenceGroup(int client, SaySoundPreferenceType type, const char[] groupName, char[] updatedValue, int updatedLen)
{
    updatedValue[0] = '\0';

    if (client <= 0 || client > MaxClients || !groupName[0] || !gConfigLoaded)
    {
        return false;
    }

    char currentValue[MAX_COMMAND_NAME * 4];
    GetClientSoundPreferenceValue(client, type, currentValue, sizeof(currentValue));

    bool anyEnabled;
    bool allEnabled;
    if (!GetSoundPreferenceGroupState(client, currentValue, groupName, anyEnabled, allEnabled))
    {
        return false;
    }

    bool enableGroup = !allEnabled;
    char rebuilt[MAX_COMMAND_NAME * 4];
    rebuilt[0] = '\0';
    int validCount = 0;
    bool anyInvalid = false;

    char currentCommand[MAX_COMMAND_NAME];
    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, currentCommand, sizeof(currentCommand));
        if (!CanClientUseSaySoundCommand(client, currentCommand))
        {
            continue;
        }

        bool shouldEnable = PreferenceListHasCommand(currentValue, currentCommand);
        if (IsCommandInSoundGroup(currentCommand, groupName))
        {
            shouldEnable = enableGroup;
        }

        if (!shouldEnable)
        {
            continue;
        }

        if (!AppendSoundPreferenceCommand(client, currentCommand, rebuilt, sizeof(rebuilt), validCount, anyInvalid))
        {
            return false;
        }
    }

    SetClientSoundPreferenceValue(client, type, rebuilt);
    strcopy(updatedValue, updatedLen, rebuilt);
    return true;
}

static void BuildSoundPreferenceGroupMenuItem(const char[] groupName, char[] itemInfo, int itemLen)
{
    Format(itemInfo, itemLen, "%s%s", SOUND_PREF_GROUP_ITEM_PREFIX, groupName);
}

static bool GetSoundPreferenceGroupFromMenuItem(const char[] itemInfo, char[] groupName, int groupLen)
{
    groupName[0] = '\0';

    if (!Strings_StartsWith(itemInfo, SOUND_PREF_GROUP_ITEM_PREFIX))
    {
        return false;
    }

    Strings_CopyFrom(itemInfo, strlen(SOUND_PREF_GROUP_ITEM_PREFIX), groupName, groupLen);
    TrimString(groupName);
    Strings_ToLower(groupName, groupLen);
    return groupName[0] != '\0';
}

static void AddSoundPreferenceGroupMenuItems(Menu menu, int client, const char[] currentValue, bool paidOnly)
{
    char groupName[MAX_GROUP_NAME];
    char display[128];

    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (StrEqual(groupName, DEFAULT_GROUP) || IsGroupPaid(groupName) != paidOnly || !CanShowSoundPreferenceGroupInMenu(client, groupName))
        {
            continue;
        }

        bool anyEnabled;
        bool allEnabled;
        if (!GetSoundPreferenceGroupState(client, currentValue, groupName, anyEnabled, allEnabled))
        {
            continue;
        }

        char itemInfo[MAX_COMMAND_NAME];
        BuildSoundPreferenceGroupMenuItem(groupName, itemInfo, sizeof(itemInfo));
        Format(display, sizeof(display), "%s group (%s)", groupName, allEnabled ? "enabled" : (anyEnabled ? "partial" : "disabled"));
        menu.AddItem(itemInfo, display);
    }
}

static void AddSoundPreferenceCommandMenuItems(Menu menu, int client, const char[] currentValue, bool paidOnly)
{
    char commandName[MAX_COMMAND_NAME];
    char groupName[MAX_GROUP_NAME];
    char display[128];

    for (int i = 0; i < gCommandNames.Length; i++)
    {
        gCommandNames.GetString(i, commandName, sizeof(commandName));
        if (!gSoundGroupMap.GetString(commandName, groupName, sizeof(groupName)))
        {
            strcopy(groupName, sizeof(groupName), DEFAULT_GROUP);
        }

        if (IsGroupPaid(groupName) != paidOnly || !CanShowSoundPreferenceGroupInMenu(client, groupName))
        {
            continue;
        }

        Format(display, sizeof(display), "%s (%s)", commandName, PreferenceListHasCommand(currentValue, commandName) ? "enabled" : "disabled");
        menu.AddItem(commandName, display);
    }
}

static void ShowSoundPreferenceMenu(int client, SaySoundPreferenceType type)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (!gConfigLoaded)
    {
        PrintToChat(client, "[SaySounds] Sounds are not ready yet. Try again soon.");
        return;
    }

    char currentValue[MAX_COMMAND_NAME * 4];
    GetClientSoundPreferenceValue(client, type, currentValue, sizeof(currentValue));

    Menu menu = new Menu(type == SaySoundPreference_Death ? MenuHandler_DeathSounds : MenuHandler_KillSounds);

    char title[192];
    Format(title, sizeof(title), "%s Sounds (current: %s)",
        type == SaySoundPreference_Death ? "Death" : "Kill",
        currentValue[0] ? currentValue : "none");
    menu.SetTitle(title);

    AddSoundPreferenceGroupMenuItems(menu, client, currentValue, true);
    AddSoundPreferenceCommandMenuItems(menu, client, currentValue, true);
    AddSoundPreferenceCommandMenuItems(menu, client, currentValue, false);
    AddSoundPreferenceGroupMenuItems(menu, client, currentValue, false);

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

static int HandleSoundPreferenceMenu(Menu menu, MenuAction action, int client, int item, SaySoundPreferenceType type)
{
    if (action == MenuAction_Select)
    {
        if (client <= 0 || !IsClientInGame(client))
        {
            return 0;
        }

        char itemInfo[MAX_COMMAND_NAME];
        menu.GetItem(item, itemInfo, sizeof(itemInfo));

        char updatedValue[MAX_COMMAND_NAME * 4];
        char groupName[MAX_GROUP_NAME];
        bool success;
        if (GetSoundPreferenceGroupFromMenuItem(itemInfo, groupName, sizeof(groupName)))
        {
            success = ToggleClientSoundPreferenceGroup(client, type, groupName, updatedValue, sizeof(updatedValue));
        }
        else
        {
            success = ToggleClientSoundPreferenceCommand(client, type, itemInfo, updatedValue, sizeof(updatedValue));
        }

        if (!success)
        {
            PrintToChat(client, "[SaySounds] You can only store up to %d sounds.", MAX_SOUND_OPTIONS);
        }
        else
        {
            PrintToChat(client, "[SaySounds] %s sound list updated: %s",
                type == SaySoundPreference_Death ? "Death" : "Kill",
                updatedValue[0] ? updatedValue : "none");
            LogSoundPreferenceChange(client, type, updatedValue);
        }

        ShowSoundPreferenceMenu(client, type);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public int MenuHandler_DeathSounds(Menu menu, MenuAction action, int client, int item)
{
    return HandleSoundPreferenceMenu(menu, action, client, item, SaySoundPreference_Death);
}

public int MenuHandler_KillSounds(Menu menu, MenuAction action, int client, int item)
{
    return HandleSoundPreferenceMenu(menu, action, client, item, SaySoundPreference_Kill);
}

public Action Command_ShowDeathSoundsMenu(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    ShowSoundPreferenceMenu(client, SaySoundPreference_Death);
    return Plugin_Handled;
}

public Action Command_ShowKillSoundsMenu(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    ShowSoundPreferenceMenu(client, SaySoundPreference_Kill);
    return Plugin_Handled;
}

public Action Command_ListSounds(int client, int args)
{
    if (client <= 0)
    {
        PrintSaySoundGroups(client);
        for (int i = 0; i < gCommandNames.Length; i++)
        {
            char command[MAX_COMMAND_NAME];
            char sound[PLATFORM_MAX_PATH];
            char group[MAX_GROUP_NAME];
            gCommandNames.GetString(i, command, sizeof(command));
            if (!gSoundMap.GetString(command, sound, sizeof(sound)))
                continue;
            if (!gSoundGroupMap.GetString(command, group, sizeof(group)))
                strcopy(group, sizeof(group), DEFAULT_GROUP);
            PrintToServer("[SaySounds] %s!%s -> %s [%s]", IsGroupPaid(group) ? "[!shop] " : "", command, sound, group);
        }
        return Plugin_Handled;
    }

    if (!IsClientInGame(client))
        return Plugin_Handled;

    PrintSaySoundGroups(client);
    PrintToChat(client, "[SaySounds] Available commands:");
    PrintToChat(client, "[SaySounds] (Use !opt to mute/unmute, !opts for group toggles, !vol <0.0-1.0> for custom volume)");
    for (int i = 0; i < gCommandNames.Length; i++)
    {
        char command[MAX_COMMAND_NAME];
        char sound[PLATFORM_MAX_PATH];
        char group[MAX_GROUP_NAME];
        gCommandNames.GetString(i, command, sizeof(command));
        if (!gSoundMap.GetString(command, sound, sizeof(sound)))
            continue;
        if (!gSoundGroupMap.GetString(command, group, sizeof(group)))
            strcopy(group, sizeof(group), DEFAULT_GROUP);
        if (IsGroupAPIOnly(group))
            continue;
        PrintToChat(client, "%s!%s -> %s [%s]", IsGroupPaid(group) ? "[!shop] " : "", command, sound, group);
    }

    return Plugin_Handled;
}

public Action Command_ListGroups(int client, int args)
{
    if (client > 0 && !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    PrintSaySoundGroups(client);
    return Plugin_Handled;
}

void PrintSaySoundGroups(int client)
{
    int displayIndex = 1;
    char groupName[MAX_GROUP_NAME];

    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (StrEqual(groupName, DEFAULT_GROUP))
        {
            continue;
        }

        if (client > 0 && IsGroupAPIOnly(groupName))
        {
            continue;
        }

        if (client <= 0)
        {
            PrintToServer("%sgroup %d - %s", IsGroupPaid(groupName) ? "[!shop] " : "", displayIndex, groupName);
        }
        else
        {
            PrintToChat(client, "%sgroup %d - %s", IsGroupPaid(groupName) ? "[!shop] " : "", displayIndex, groupName);
        }

        displayIndex++;
    }

    if (displayIndex == 1)
    {
        if (client <= 0)
        {
            PrintToServer("[SaySounds] No sound groups are configured.");
        }
        else
        {
            PrintToChat(client, "[SaySounds] No sound groups are configured.");
        }
    }
}

stock bool SaySounds_ShouldPlay(int client)
{
    return GetClientVolume(client) > 0.0;
}

