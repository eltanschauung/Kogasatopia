void TidyChat_Initialize()
{
    HookEvent("player_disconnect", TidyChat_EventPlayerDisconnect, EventHookMode_Pre);
    HookEvent("player_team", TidyChat_EventPlayerTeam, EventHookMode_Pre);
    HookEvent("server_cvar", TidyChat_EventCvar, EventHookMode_Pre);
    HookEvent("player_changename", TidyChat_EventPlayerChangeName, EventHookMode_Pre);

    UserMsg sayText2 = GetUserMessageId("SayText2");
    if (sayText2 != INVALID_MESSAGE_ID)
    {
        HookUserMessage(sayText2, TidyChat_UserMessageHook, true);
    }

    UserMsg voiceSubtitle = GetUserMessageId("VoiceSubtitle");
    if (voiceSubtitle != INVALID_MESSAGE_ID)
    {
        HookUserMessage(voiceSubtitle, TidyChat_UserMessageVoiceSubtitle, true);
    }
}

static void TidyChat_BuildTeamJoinText(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case 1: strcopy(buffer, maxlen, "entered {lightsteelblue}Keine's Class");
        case 2: strcopy(buffer, maxlen, "joined team {red}Fujiwara");
        case 3: strcopy(buffer, maxlen, "joined team {blue}Houraisan");
        case 4: strcopy(buffer, maxlen, "joined team {green}Konpaku");
        case 5: strcopy(buffer, maxlen, "joined team {yellow}Kirisame");
        default: buffer[0] = '\0';
    }
}

static void TidyChat_PrintTeamJoinAlert(int client, int team)
{
    if (!Filters_IsRealClientInGame(client))
    {
        return;
    }

    char teamText[64];
    TidyChat_BuildTeamJoinText(team, teamText, sizeof(teamText));
    if (!teamText[0])
    {
        return;
    }

    char renderedName[256];
    BuildRenderedClientName(client, renderedName, sizeof(renderedName));
    if (!renderedName[0])
    {
        char clientName[MAX_NAME_LENGTH];
        GetClientName(client, clientName, sizeof(clientName));
        Format(renderedName, sizeof(renderedName), "{teamcolor}%s{default}", clientName);
    }

    CPrintToChatAllEx(client, "%s %s", renderedName, teamText);
}

public any Native_FilterAlerts_MarkAutobalance(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client > 0 && client <= MaxClients)
    {
        g_TidyChatSuppressNextTeamAlert[client] = true;
    }
    return 1;
}

public any Native_FilterAlerts_SuppressTeamAlertWindow(Handle plugin, int numParams)
{
    float seconds = view_as<float>(GetNativeCell(1));
    if (seconds <= 0.0)
    {
        return 0;
    }

    float until = GetGameTime() + seconds;
    if (until > g_TidyChatSuppressTeamAlertsUntil)
    {
        g_TidyChatSuppressTeamAlertsUntil = until;
    }
    return 1;
}

public Action TidyChat_UserMessageHook(UserMsg msgId, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
    message.ReadByte();
    message.ReadByte();

    char messageName[96];
    char firstParameter[96];
    message.ReadString(messageName, sizeof(messageName));
    message.ReadString(firstParameter, sizeof(firstParameter));

    if (GetClientCount(false) < 7
        && (StrContains(messageName, "Name_Change", false) != -1
            || StrContains(firstParameter, "Name_Change", false) != -1))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action TidyChat_EventPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && client <= MaxClients)
    {
        g_TidyChatSuppressNextTeamAlert[client] = false;
    }

    if (g_hTidyChatEnabled.BoolValue && g_hTidyChatDisconnect.BoolValue)
    {
        event.BroadcastDisabled = true;
    }
    return Plugin_Continue;
}

public Action TidyChat_EventPlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || IsFakeClient(client))
    {
        event.BroadcastDisabled = true;
    }
    return Plugin_Continue;
}

public Action TidyChat_EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hTidyChatEnabled.BoolValue || !g_hTidyChatTeam.BoolValue || event.GetBool("silent"))
    {
        return Plugin_Continue;
    }

    if (g_TidyChatSuppressTeamAlertsUntil > 0.0)
    {
        if (GetGameTime() < g_TidyChatSuppressTeamAlertsUntil)
        {
            event.BroadcastDisabled = true;
            return Plugin_Handled;
        }
        g_TidyChatSuppressTeamAlertsUntil = 0.0;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Filters_IsRealClientInGame(client))
    {
        event.BroadcastDisabled = true;
        return Plugin_Handled;
    }

    if (g_TidyChatSuppressNextTeamAlert[client])
    {
        g_TidyChatSuppressNextTeamAlert[client] = false;
        event.BroadcastDisabled = true;
        return Plugin_Handled;
    }

    int team = event.GetInt("team");
    event.BroadcastDisabled = true;
    TidyChat_PrintTeamJoinAlert(client, team);
    return Plugin_Handled;
}

public Action TidyChat_EventCvar(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hTidyChatEnabled.BoolValue && g_hTidyChatCvar.BoolValue)
    {
        event.BroadcastDisabled = true;
    }
    return Plugin_Continue;
}

public Action TidyChat_UserMessageVoiceSubtitle(UserMsg msgId, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
    if (g_hTidyChatEnabled.BoolValue && g_hTidyChatVoice.BoolValue)
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

