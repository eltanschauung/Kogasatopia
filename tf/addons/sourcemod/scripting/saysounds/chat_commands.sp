Action ChatCommandListener(int client, const char[] command, int argc)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Continue;
    }

    char message[256];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);
    TrimString(message);

    if (!message[0] || !gConfigLoaded)
    {
        return Plugin_Continue;
    }

    char payload[256];
    strcopy(payload, sizeof(payload), message);
    if (payload[0] == '!')
    {
        Strings_ShiftLeft(payload, sizeof(payload), 1);
    }
    TrimString(payload);

    if (!payload[0])
    {
        return Plugin_Continue;
    }

    char commandName[MAX_COMMAND_NAME * 4];
    char args[256];

    strcopy(commandName, sizeof(commandName), payload);
    int spaceIndex = FindCharInString(commandName, ' ');
    if (spaceIndex != -1)
    {
        commandName[spaceIndex] = '\0';

        strcopy(args, sizeof(args), payload);
        Strings_ShiftLeft(args, sizeof(args), spaceIndex + 1);
        TrimString(args);
    }
    else
    {
        args[0] = '\0';
    }

    Strings_ToLower(commandName, sizeof(commandName));

    if (!commandName[0])
    {
        return Plugin_Continue;
    }

    int initiator = (client > 0 && client <= MaxClients) ? client : -1;
    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    bool restricted = false;
    bool paidRestricted = false;
    if (!GetCommandSoundDataForClientEx(initiator, commandName, soundPath, sizeof(soundPath), groupName, sizeof(groupName), restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup)))
    {
        if (restricted)
        {
            PrintToChat(initiator, "[SaySounds] That sound group is only available through the API.");
            return Plugin_Handled;
        }

        if (paidRestricted)
        {
            PrintToChat(initiator, "[SaySounds] That sound group requires a shop purchase. Use !shop.");
            return Plugin_Handled;
        }

        return Plugin_Continue;
    }

    float now = GetGameTime();

    if (initiator != -1)
    {
        if (g_fNextAllowedSound[initiator] > now)
        {
            float remaining = g_fNextAllowedSound[initiator] - now;
            PrintToChat(initiator, "[SaySounds] Please wait %.1f seconds before triggering another sound.", remaining);
            return Plugin_Handled;
        }

		if(CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT, true))
			g_fNextAllowedSound[initiator] = now + ADMIN_COOLDOWN;
		else
			g_fNextAllowedSound[initiator] = now + DEFAULT_COOLDOWN;
        
    }

    if (PlaySaySound(soundPath, groupName))
    {
        LogSaySoundUsage("saysound_used", initiator, 0, selectedCommand, soundPath, groupName, fromGroup, sourceGroup, false, "chat");
    }

    return Plugin_Continue;
}

