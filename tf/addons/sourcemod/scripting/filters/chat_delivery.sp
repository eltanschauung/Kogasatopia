bool Filters_ShouldReceiveChat(int receiver, int sender)
{
    if (receiver <= 0 || !IsClientInGame(receiver))
    {
        return false;
    }

    if (!Filters_RedlistEnabled())
    {
        return true;
    }

    if (!g_PlayerState[receiver].isredlisted)
    {
        return true;
    }

    return (sender > 0 && sender <= MaxClients && g_PlayerState[sender].isredlisted);
}

void Filters_PrintToChatAll(const char[] message, bool skipArchivedMuted = false)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Filters_ShouldReceiveChat(i, 0))
        {
            continue;
        }
        if (skipArchivedMuted && g_bMuteArchivedSpeakers[i])
        {
            continue;
        }
        CPrintToChat(i, "%s", message);
    }
}

void Filters_SendChatToReceiver(int receiver, int sender, const char[] message, const char[] senderMessage = "")
{
    if (receiver <= 0 || !IsClientInGame(receiver))
    {
        return;
    }

    if (Filters_RedlistEnabled()
        && sender > 0
        && sender <= MaxClients
        && g_PlayerState[sender].isredlisted
        && !g_PlayerState[receiver].isredlisted)
    {
        if (g_PlayerState[receiver].isWhitelisted && Filters_PChatEnabled())
        {
            CPrintToChatEx(receiver, sender, "{axis}[Fake] %s", receiver == sender && senderMessage[0] ? senderMessage : message);
        }
        return;
    }

    CPrintToChatEx(receiver, sender, "%s", receiver == sender && senderMessage[0] ? senderMessage : message);
}

static void Filters_PrintToChatAllEx(int sender, const char[] message, const char[] senderMessage = "")
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Filters_ShouldReceiveChat(i, sender))
        {
            continue;
        }
        Filters_SendChatToReceiver(i, sender, message, senderMessage);
    }
}

void Filters_UpdateVoiceOverrides()
{
    int filterMode = Filters_GetFilterMode();
    bool cordMode = filterMode != 0;
    bool redlistEnabled = Filters_RedlistEnabled();
    for (int sender = 1; sender <= MaxClients; sender++)
    {
        if (!IsClientInGame(sender))
        {
            continue;
        }

        bool senderBlacklisted = g_PlayerState[sender].isBlacklisted;
        for (int receiver = 1; receiver <= MaxClients; receiver++)
        {
            if (receiver == sender || !IsClientInGame(receiver))
            {
                continue;
            }

            bool shouldBlock = false;
            if (g_MuteDeafened[receiver])
            {
                shouldBlock = true;
            }
            else if (redlistEnabled && g_PlayerState[receiver].isredlisted)
            {
                shouldBlock = !g_PlayerState[sender].isredlisted;
            }
            else if (cordMode)
            {
                bool receiverBlacklisted = g_PlayerState[receiver].isBlacklisted;
                bool receiverWhitelisted = g_PlayerState[receiver].isWhitelisted;
                if (receiverBlacklisted)
                {
                    shouldBlock = !senderBlacklisted && !(g_PlayerState[sender].isWhitelisted && Filters_CordModeBlacklistedCanReceiveWhitelisted());
                }
                else
                {
                    shouldBlock = senderBlacklisted && !receiverWhitelisted;
                }
            }

            if (shouldBlock)
            {
                if (!g_VoiceBlocked[receiver][sender])
                {
                    SetListenOverride(receiver, sender, Listen_No);
                    g_VoiceBlocked[receiver][sender] = true;
                }
            }
            else if (g_VoiceBlocked[receiver][sender])
            {
                SetListenOverride(receiver, sender, Listen_Default);
                g_VoiceBlocked[receiver][sender] = false;
            }
        }
    }
}

void ApplyFiltersIfNeeded(char[] message, int maxlen, const ChatContext context)
{
    if (context.isFilterWhitelisted)
    {
        return;
    }

    FilterString(message, maxlen);
}

bool HandleCordModeBlacklistedChat(int client, const char[] message, const ChatContext context, const char[] senderMessage = "")
{
    if (!context.isBlacklisted || !context.cordMode)
    {
        return false;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && g_PlayerState[i].isBlacklisted && Filters_ShouldReceiveChat(i, client))
        {
            Filters_SendChatToReceiver(i, client, message, senderMessage);
        }
    }

    if (Filters_CordModeWhitelistedCanReceiveBlacklisted())
    {
        SendToWhitelistedAdminsBlacklisted(client, message, "fm1:");
    }
    PrintToServer("x: %s", message);
    return true;
}

bool HandleRestrictedMessage(int client, const char[] message, const ChatContext context, const char[] senderMessage = "")
{
    if (((context.hasBlacklistedTerm && !context.isWhitelisted) && !context.cordMode) || context.isGagged)
    {
        CPrintToChatEx(client, client, "%s", senderMessage[0] ? senderMessage : message);
        PrintToServer("x: %s", message);
        SendToWhitelistedAdmins(client, message, "x:");
        if (context.isGagged)
        {
            Filters_RelayChatToServers(client, message);
        }
        return true;
    }

    return false;
}

bool HandleEnabledChat(int client, const char[] message, const ChatContext context, const char[] senderMessage = "")
{
    if (!context.pluginEnabled)
    {
        return false;
    }

    bool teamChatOnly = g_hFiltersTeamChat != null && g_hFiltersTeamChat.BoolValue;

    if (!context.cordMode)
    {
        if (context.isBlacklisted)
        {
            int senderTeam = GetClientTeam(client);
            char prefixed[256];
            bool prefixedReady = false;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (!IsClientInGame(i) || !Filters_ShouldReceiveChat(i, client))
                {
                    continue;
                }

                if (!teamChatOnly)
                {
                    Filters_SendChatToReceiver(i, client, message, senderMessage);
                    continue;
                }

                if (GetClientTeam(i) == senderTeam)
                {
                    Filters_SendChatToReceiver(i, client, message, senderMessage);
                }
                else if (Filters_CanSeeEnemyTeamChat(i))
                {
                    if (!prefixedReady)
                    {
                        Format(prefixed, sizeof(prefixed), "t: %s", message);
                        prefixedReady = true;
                    }
                    Filters_SendChatToReceiver(i, client, prefixed);
                }
            }
        }
        else if (teamChatOnly)
        {
            CPrintToChatTeam(GetClientTeam(client), client, message, senderMessage);
        }
        else
        {
            Filters_PrintToChatAllEx(client, message, senderMessage);
        }
    }
    else
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
            {
                continue;
            }
            if (!Filters_ShouldReceiveChat(i, client))
            {
                continue;
            }
            if ((!g_PlayerState[i].isBlacklisted || (context.isWhitelisted && Filters_CordModeBlacklistedCanReceiveWhitelisted()))
                && (!teamChatOnly || GetClientTeam(i) == GetClientTeam(client)))
            {
                Filters_SendChatToReceiver(i, client, message, senderMessage);
            }
        }
    }

    PrintToServer("%s", message);
    if (!teamChatOnly)
    {
        Filters_LogChatMessage(client, message);
    }
    return true;
}

void SendFallbackMessage(int client)
{
    char displayName[384];
    BuildChatDisplayName(client, displayName, sizeof(displayName));

    char output[256];
    Format(output, sizeof(output), "%s: {gold}nigger", displayName);
    Filters_PrintToChatAllEx(client, output);
    Filters_LogChatMessage(client, output);
}

public Action Command_WebSay(int client, int args)
{
    // Console-only intended, but allow any caller
    char raw[256];
    GetCmdArgString(raw, sizeof(raw));
    TrimString(raw);
    if (!raw[0] || GetConVarInt(g_hChatFrontend) < 1)
    {
        return Plugin_Handled;
    }
    char hash[32];
    char msgPart[256];
    int idx = BreakString(raw, hash, sizeof(hash));
    if (idx == -1)
    {
        strcopy(msgPart, sizeof(msgPart), hash);
        strcopy(hash, sizeof(hash), "web");
    }
    else
    {
        strcopy(msgPart, sizeof(msgPart), raw[idx]);
        if (!hash[0])
        {
            strcopy(hash, sizeof(hash), "web");
        }
    }
    TrimString(msgPart);
    if (!msgPart[0])
    {
        return Plugin_Handled;
    }

    char colorTag[32];
    if (!Filters_GetWebNameColor(hash, colorTag, sizeof(colorTag)))
    {
        strcopy(colorTag, sizeof(colorTag), "{gold}");
    }

    char label[96];
    Format(label, sizeof(label), "%s[%s]{default}", colorTag, hash);
    char out[256];
    Format(out, sizeof(out), "%s %s", label, msgPart);
    Filters_PrintToChatAll(out);
    Filters_LogDebug("sm_websay broadcast hash %s message %s", hash, msgPart);
    // Log web message
    if (g_bDbReady)
    {
        char sanitizedMsg[512];
        char escapedMsg[512];
        char escapedHash[64];
        Filters_SanitizeDbMessage(msgPart, sanitizedMsg, sizeof(sanitizedMsg));
        Db_Escape(g_hFiltersDb, sanitizedMsg, escapedMsg, sizeof(escapedMsg), "filters");
        Db_Escape(g_hFiltersDb, hash, escapedHash, sizeof(escapedHash), "filters");
        char escapedServerTag[FILTERS_CROSS_SERVER_TAG_MAX * 2];
        Filters_GetEscapedCrossServerTag(escapedServerTag, sizeof(escapedServerTag));
        char query[1024];
        Format(query, sizeof(query),
            "INSERT INTO whaletracker_chat (created_at, steamid, personaname, iphash, server_tag, message, alert) VALUES (%d, NULL, NULL, '%s', '%s', '%s', 1)",
            GetTime(), escapedHash, escapedServerTag, escapedMsg);
        g_hFiltersDb.Query(Filters_InsertChatCallback, query);
        Filters_QueueOutboxMessage(GetTime(), hash, "", msgPart, false, true);
    }
    else
    {
        Filters_LogDebug("DB not ready; unable to log sm_websay message");
    }
    return Plugin_Handled;
}

// Helper function to send message to whitelisted admins
void SendToWhitelistedAdmins(int sender, const char[] message, const char[] prefix = "")
{
    if (!Filters_PChatEnabled())
    {
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;
            
        if (g_PlayerState[i].isWhitelisted)
        {
            if (prefix[0] != '\0')
            {
                char out[512];
                Format(out, sizeof(out), "%s %s", prefix, message);
                Filters_SendChatToReceiver(i, sender, out);
            }
            else
                Filters_SendChatToReceiver(i, sender, message);
        }
    }
}

void SendToWhitelistedAdminsBlacklisted(int sender, const char[] message, const char[] prefix = "")
{
    SendToWhitelistedAdmins(sender, message, prefix);
}

