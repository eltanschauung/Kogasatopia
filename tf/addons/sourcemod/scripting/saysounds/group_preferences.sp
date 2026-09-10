static void ShowGroupOptionsMenu(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (!gConfigLoaded || gGroupNames == null)
    {
        PrintToChat(client, "[SaySounds] Sounds are not ready yet. Try again soon.");
        return;
    }

    Menu menu = new Menu(MenuHandler_GroupOptions);
    menu.SetTitle("SaySound Groups");

    char groupName[MAX_GROUP_NAME];
    char display[128];
    int itemCount = 0;

    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (StrEqual(groupName, DEFAULT_GROUP))
        {
            continue;
        }

        Format(display, sizeof(display), "%s (%s)", groupName, IsClientGroupDisabled(client, groupName) ? "disabled" : "enabled");
        menu.AddItem(groupName, display);
        itemCount++;
    }

    if (itemCount == 0)
    {
        delete menu;
        PrintToChat(client, "[SaySounds] No sound groups are configured.");
        return;
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GroupOptions(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        if (client <= 0 || !IsClientInGame(client))
        {
            return 0;
        }

        char groupName[MAX_GROUP_NAME];
        menu.GetItem(item, groupName, sizeof(groupName));

        bool disabled = !IsClientGroupDisabled(client, groupName);
        if (SetClientGroupDisabled(client, groupName, disabled))
        {
            SaveDisabledGroupPreferences(client);
            PrintToChat(client, "[SaySounds] Group %s %s.", groupName, disabled ? "disabled" : "enabled");
        }

        ShowGroupOptionsMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public Action Command_ListOptedInClients(int client, int args)
{
    char allSoundsNames[256];
    char allSoundsNamesOverflow[256];
    char mostlyEnabledNames[1024];
    char allSoundsPlainNames[256];
    char allSoundsPlainNamesOverflow[256];
    char mostlyEnabledPlainNames[1024];
    int allSoundsCount = 0;
    int mostlyEnabledCount = 0;
    int totalGroups = 0;

    if (gGroupNames != null)
    {
        char groupName[MAX_GROUP_NAME];
        for (int i = 0; i < gGroupNames.Length; i++)
        {
            gGroupNames.GetString(i, groupName, sizeof(groupName));
            if (!StrEqual(groupName, DEFAULT_GROUP))
            {
                totalGroups++;
            }
        }
    }

    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsClientInGame(target) || IsFakeClient(target) || !SaySounds_ShouldPlay(target))
        {
            continue;
        }

        int enabledGroups = 0;
        if (gGroupNames != null)
        {
            char groupName[MAX_GROUP_NAME];
            for (int i = 0; i < gGroupNames.Length; i++)
            {
                gGroupNames.GetString(i, groupName, sizeof(groupName));
                if (!StrEqual(groupName, DEFAULT_GROUP) && !IsClientGroupDisabled(target, groupName))
                {
                    enabledGroups++;
                }
            }
        }

        if (enabledGroups == totalGroups)
        {
            if (allSoundsCount < 6)
            {
                AppendOptListClientName(allSoundsNames, sizeof(allSoundsNames), target, allSoundsCount, true);
                AppendOptListClientName(allSoundsPlainNames, sizeof(allSoundsPlainNames), target, allSoundsCount, false);
            }
            else
            {
                AppendOptListClientName(allSoundsNamesOverflow, sizeof(allSoundsNamesOverflow), target, allSoundsCount - 6, true);
                AppendOptListClientName(allSoundsPlainNamesOverflow, sizeof(allSoundsPlainNamesOverflow), target, allSoundsCount - 6, false);
            }
            allSoundsCount++;
        }
        else if (enabledGroups * 5 > totalGroups * 4)
        {
            AppendOptListClientName(mostlyEnabledNames, sizeof(mostlyEnabledNames), target, mostlyEnabledCount, true);
            AppendOptListClientName(mostlyEnabledPlainNames, sizeof(mostlyEnabledPlainNames), target, mostlyEnabledCount, false);
            mostlyEnabledCount++;
        }
    }

    if (allSoundsCount == 0)
    {
        strcopy(allSoundsNames, sizeof(allSoundsNames), "none");
        strcopy(allSoundsPlainNames, sizeof(allSoundsPlainNames), "none");
    }
    if (mostlyEnabledCount == 0)
    {
        strcopy(mostlyEnabledNames, sizeof(mostlyEnabledNames), "none");
        strcopy(mostlyEnabledPlainNames, sizeof(mostlyEnabledPlainNames), "none");
    }

    if (client > 0 && IsClientInGame(client))
    {
        CPrintToChatEx(client, client, "[Saysounds] Clients will all sounds enabled: %s", allSoundsNames);
        if (allSoundsCount > 6)
        {
            CPrintToChatEx(client, client, "[Saysounds] Clients will all sounds enabled: %s", allSoundsNamesOverflow);
        }
        CPrintToChatEx(client, client, "[Saysounds] Clients with >80%% of sound groups enabled: %s", mostlyEnabledNames);
    }
    else
    {
        ReplyToCommand(client, "[Saysounds] Clients will all sounds enabled: %s", allSoundsPlainNames);
        if (allSoundsCount > 6)
        {
            ReplyToCommand(client, "[Saysounds] Clients will all sounds enabled: %s", allSoundsPlainNamesOverflow);
        }
        ReplyToCommand(client, "[Saysounds] Clients with >80%% of sound groups enabled: %s", mostlyEnabledPlainNames);
    }

    return Plugin_Handled;
}

static void AppendOptListClientName(char[] output, int maxlen, int client, int existingCount, bool colorized)
{
    if (existingCount > 0)
    {
        StrCat(output, maxlen, ", ");
    }

    char displayName[256];
    if (!colorized)
    {
        GetClientName(client, displayName, sizeof(displayName));
    }
    else
    {
        char colorToken[32];
        char steamId64[32];
        if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") != FeatureStatus_Available
            || !GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64))
            || !Filters_GetSteamIdColorTag(steamId64, colorToken, sizeof(colorToken))
            || !colorToken[0])
        {
            strcopy(colorToken, sizeof(colorToken), "teamcolor");
        }

        FormatEx(displayName, sizeof(displayName), "{%s}%N{default}", colorToken, client);
    }

    if (colorized)
    {
        ChatColors_ResolveTeamTag(client, displayName, sizeof(displayName));
    }
    StrCat(output, maxlen, displayName);
}

public Action Command_ToggleSoundOpt(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    if (args >= 1)
    {
        char arg[MAX_GROUP_NAME];
        GetCmdArg(1, arg, sizeof(arg));
        TrimString(arg);
        Strings_ToLower(arg, sizeof(arg));

        if (StrEqual(arg, "off") || StrEqual(arg, "mute") || StrEqual(arg, "none"))
        {
            g_fClientVolume[client] = 0.0;
            SaveVolumePreference(client);
            PrintToChat(client, "[SaySounds] Say sounds muted.");
            return Plugin_Handled;
        }

        if (StrEqual(arg, "on"))
        {
            ResetClientDisabledGroups(client);
            SaveDisabledGroupPreferences(client);
            g_fClientVolume[client] = GetOptInVolume();
            SaveVolumePreference(client);
            PrintToChat(client, "[SaySounds] Say sounds enabled.");
            return Plugin_Handled;
        }

        if (StrEqual(arg, DEFAULT_GROUP))
        {
            ResetClientDisabledGroups(client);
            SaveDisabledGroupPreferences(client);
            g_fClientVolume[client] = GetOptInVolume();
            SaveVolumePreference(client);
            PrintToChat(client, "[SaySounds] Say sounds enabled.");
            return Plugin_Handled;
        }

        if (!arg[0] || !IsKnownGroup(arg))
        {
            PrintToChat(client, "[SaySounds] Unknown sound group.");
            return Plugin_Handled;
        }

        bool disabled = !IsClientGroupDisabled(client, arg);
        SetClientGroupDisabled(client, arg, disabled);
        SaveDisabledGroupPreferences(client);
        PrintToChat(client, "[SaySounds] Group %s %s.", arg, disabled ? "disabled" : "enabled");
    }
    else
    {
        if (GetClientVolume(client) > 0.0)
        {
            g_fClientVolume[client] = 0.0;
            SaveVolumePreference(client);
            PrintToChat(client, "[SaySounds] Say sounds muted.");
        }
        else
        {
            g_fClientVolume[client] = GetOptInVolume();
            SaveVolumePreference(client);
            PrintToChat(client, "[SaySounds] Say sounds enabled.");
        }
    }

    return Plugin_Handled;
}

public Action Command_ShowGroupOptions(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    ShowGroupOptionsMenu(client);
    return Plugin_Handled;
}

enum SaySoundPreferenceType
{
    SaySoundPreference_Death = 0,
    SaySoundPreference_Kill
};

