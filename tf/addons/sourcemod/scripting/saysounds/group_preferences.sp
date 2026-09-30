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
    if (!gConfigLoaded || gGroupNames == null)
    {
        ReplyToCommand(client, "[SaySounds] Sound groups are not ready yet.");
        return Plugin_Handled;
    }
    int total;
    char group[MAX_GROUP_NAME];
    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, group, sizeof(group));
        if (!StrEqual(group, DEFAULT_GROUP)) total++;
    }
    int players[MAXPLAYERS], enabled[MAXPLAYERS], count;
    char names[MAXPLAYERS][MAX_NAME_LENGTH];
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsClientInGame(target) || IsFakeClient(target)
            || (client > 0 && Oblivion_ShouldHide(client, target))) continue;
        int groups;
        bool audible = SaySounds_ShouldPlay(target);
        if (audible) for (int i = 0; i < gGroupNames.Length; i++)
        {
            gGroupNames.GetString(i, group, sizeof(group));
            if (!StrEqual(group, DEFAULT_GROUP) && !IsClientGroupDisabled(target, group)) groups++;
        }
        // -1 sorts completely muted clients below users with zero configured groups.
        if (!audible) groups = -1;
        char name[MAX_NAME_LENGTH];GetClientName(target, name, sizeof(name));
        int position = count;
        while (position > 0 && (enabled[position - 1] < groups
            || (enabled[position - 1] == groups && strcmp(names[position - 1], name, false) > 0)))
        {
            players[position] = players[position - 1];enabled[position] = enabled[position - 1];
            strcopy(names[position], sizeof(names[]), names[position - 1]);position--;
        }
        players[position] = target;enabled[position] = groups;
        strcopy(names[position], sizeof(names[]), name);count++;
    }
    for (int i = 0; i < count; i++)
    {
        int target = players[i];char status[512];
        if (enabled[i] < 0 || (total > 0 && enabled[i] == 0))
            strcopy(status, sizeof(status), "{red}All groups disabled");
        else if (enabled[i] == total)
            strcopy(status, sizeof(status), "{lightgreen}All groups");
        else
        {
            bool listDisabled = enabled[i] * 2 >= total;
            strcopy(status, sizeof(status), listDisabled ? "{yellowgreen}Disabled groups " : "{salmon}Enabled groups ");
            int listed;
            for (int groupIndex = 0; groupIndex < gGroupNames.Length; groupIndex++)
            {
                gGroupNames.GetString(groupIndex, group, sizeof(group));
                if (StrEqual(group, DEFAULT_GROUP) || IsClientGroupDisabled(target, group) != listDisabled) continue;
                if (listed++) StrCat(status, sizeof(status), ", ");
                StrCat(status, sizeof(status), group);
            }
        }
        if (client > 0 && IsClientInGame(client))
        {
            char displayName[256];
            if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") != FeatureStatus_Available
                || !Filters_GetChatName(target, displayName, sizeof(displayName)))
                FormatEx(displayName, sizeof(displayName), "{teamcolor}%N", target);
            CPrintToChatEx(client, target, "{gold}%d. %s{default}: %s", i + 1, displayName, status);
        }
        else
        {
            CRemoveTags(status, sizeof(status));
            ReplyToCommand(client, "%d. %s: %s", i + 1, names[i], status);
        }
    }
    if (!count) ReplyToCommand(client, "[SaySounds] No players to list.");
    return Plugin_Handled;
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

public Action Command_TouhouOnly(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!gConfigLoaded || gGroupNames == null || !AreClientCookiesCached(client))
    {
        PrintToChat(client, "[SaySounds] Sound preferences are not ready yet. Try again soon.");
        return Plugin_Handled;
    }

    static const char touhouGroup[] = "touhou";
    if (!IsKnownGroup(touhouGroup))
    {
        PrintToChat(client, "[SaySounds] The touhou sound group is not configured.");
        return Plugin_Handled;
    }

    ResetClientDisabledGroups(client);

    char groupName[MAX_GROUP_NAME];
    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (!StrEqual(groupName, DEFAULT_GROUP) && !StrEqual(groupName, touhouGroup))
        {
            SetClientGroupDisabled(client, groupName, true);
        }
    }

    OptClientIntoSaySounds(client);
    SaveDisabledGroupPreferences(client);
    PrintToChat(client, "[SaySounds] Only the touhou sound group is enabled.");
    return Plugin_Handled;
}

public Action Command_ProjectMoonOnly(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (!gConfigLoaded || gGroupNames == null || !AreClientCookiesCached(client))
    {
        PrintToChat(client, "[SaySounds] Sound preferences are not ready yet. Try again soon.");
        return Plugin_Handled;
    }

    static const char limbusGroup[] = "limbus";
    static const char lobcorpGroup[] = "lobcorp";
    if (!IsKnownGroup(limbusGroup) || !IsKnownGroup(lobcorpGroup))
    {
        PrintToChat(client, "[SaySounds] The limbus or lobcorp sound group is not configured.");
        return Plugin_Handled;
    }

    ResetClientDisabledGroups(client);

    char groupName[MAX_GROUP_NAME];
    for (int i = 0; i < gGroupNames.Length; i++)
    {
        gGroupNames.GetString(i, groupName, sizeof(groupName));
        if (!StrEqual(groupName, DEFAULT_GROUP)
            && !StrEqual(groupName, limbusGroup)
            && !StrEqual(groupName, lobcorpGroup))
        {
            SetClientGroupDisabled(client, groupName, true);
        }
    }

    OptClientIntoSaySounds(client);
    SaveDisabledGroupPreferences(client);
    PrintToChat(client, "[SaySounds] Only the limbus and lobcorp sound groups are enabled.");
    return Plugin_Handled;
}

static void OptClientIntoSaySounds(int client)
{
    if (GetClientVolume(client) > 0.0)
    {
        return;
    }

    g_fClientVolume[client] = GetOptInVolume();
    SaveVolumePreference(client);
}

enum SaySoundPreferenceType
{
    SaySoundPreference_Death = 0,
    SaySoundPreference_Kill
};
