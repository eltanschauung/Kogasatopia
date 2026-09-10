public Action CommandListener_Say(int client, const char[] command, int argc)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (!text[0])
    {
        return Plugin_Continue;
    }

    if (g_PromptState[client] == Prompt_ClanCreateName)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan creation cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        HandleClanCreateInput(client, text);
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanRenameName)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan rename cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        HandleClanRenameInput(client, text);
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanLeaveConfirm)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan deletion cancelled.");
            return Plugin_Handled;
        }

        if (StrEqual(text, "/yes", false))
        {
            g_PromptState[client] = Prompt_None;
            StartOwnerDeleteClan(client);
            return Plugin_Handled;
        }

        PrintToChat(client, "[Clans] Type /yes to confirm clan deletion or /cancel to abort.");
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanTagChoice)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan tag action cancelled.");
            return Plugin_Handled;
        }

        if (StrEqual(text, "/change", false))
        {
            g_PromptState[client] = Prompt_ClanTagInput;
            PrintToChat(client, "[Clans] Type the new clan tag in chat. Type /cancel to abort.");
            return Plugin_Handled;
        }

        if (StrEqual(text, "/sub", false))
        {
            g_PromptState[client] = Prompt_ClanSubTagInput;
            PrintToChat(client, "[Clans] Type your clan sub-tag in chat. If you already have one, this will replace it. Type /cancel to abort.");
            return Plugin_Handled;
        }

        PrintToChat(client, "[Clans] Use /cancel, /change, or /sub.");
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanTagInput)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan tag update cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        StartSetMainClanTagFromInput(client, text);
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanSubTagInput)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan sub-tag update cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        StartSetClanSubTagFromInput(client, text);
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanDescInput)
    {
        if (StrEqual(text, "/cancel", false))
        {
            g_PromptState[client] = Prompt_None;
            PrintToChat(client, "[Clans] Clan description update cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        StartSetClanDescFromInput(client, text);
        return Plugin_Handled;
    }
    else if (g_PromptState[client] == Prompt_ClanAdminDescInput)
    {
        if (StrEqual(text, "/cancel", false))
        {
            ResetClientState(client);
            PrintToChat(client, "[Clans] Clan description update cancelled.");
            return Plugin_Handled;
        }

        g_PromptState[client] = Prompt_None;
        StartSetAdminClanDescFromInput(client, text);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool ValidateClanName(const char[] name)
{
    int len = strlen(name);
    return (len > 0 && len <= CLAN_NAME_MAXLEN);
}

void StartClanTagPrompt(int client)
{
    if (!EnsureDatabaseReady(client))
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    GetClanByPlayer(steamid64, SQL_OnClanTagPromptContext, GetClientUserId(client));
}

void StartSetMainClanTagFromInput(int client, const char[] input)
{
    char rawTag[CLAN_TAG_MAXLEN + 1];
    strcopy(rawTag, sizeof(rawTag), input);
    StripQuotes(rawTag);
    TrimString(rawTag);
    NormalizeClanTagText(rawTag);

    if (!rawTag[0])
    {
        PrintToChat(client, "[Clans] Tag cannot be empty.");
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(rawTag);

    GetClanByPlayer(steamid64, SQL_OnClanTagContext, pack);
}

void StartSetClanDescFromInput(int client, const char[] input)
{
    char description[CLAN_DESC_MAXLEN + 1];
    strcopy(description, sizeof(description), input);
    StripQuotes(description);
    TrimString(description);

    if (!description[0])
    {
        PrintToChat(client, "[Clans] Description cannot be empty.");
        return;
    }

    if (strlen(description) > CLAN_DESC_MAXLEN)
    {
        PrintToChat(client, "[Clans] Description is too long. Max length: %d.", CLAN_DESC_MAXLEN);
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        PrintToChat(client, "[Clans] Could not read your SteamID64.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(description);

    GetClanByPlayer(steamid64, SQL_OnClanDescContext, pack);
}

void StartSetAdminClanDescFromInput(int client, const char[] input)
{
    int clanId = g_PendingAdminClanDescId[client];

    char clanName[CLAN_NAME_MAXLEN + 1];
    strcopy(clanName, sizeof(clanName), g_PendingAdminClanDescName[client]);
    g_PendingAdminClanDescId[client] = 0;
    g_PendingAdminClanDescName[client][0] = '\0';

    if (clanId <= 0)
    {
        PrintToChat(client, "[Clans] No clan selected.");
        return;
    }

    char description[CLAN_DESC_MAXLEN + 1];
    strcopy(description, sizeof(description), input);
    StripQuotes(description);
    TrimString(description);

    if (!description[0])
    {
        PrintToChat(client, "[Clans] Description cannot be empty.");
        return;
    }

    if (strlen(description) > CLAN_DESC_MAXLEN)
    {
        PrintToChat(client, "[Clans] Description is too long. Max length: %d.", CLAN_DESC_MAXLEN);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(clanId);
    pack.WriteString(description);
    pack.WriteString(clanName);

    GetClanById(clanId, SQL_OnAdminClanDescContext, pack);
}

void ShowClanMainMenu(int client, int clanId, ClanRank rank, const char[] clanName, const char[] clanTag, bool isOpen, int inviteCount)
{
    Menu menu = new Menu(MenuHandler_ClanMain);

    char title[256];
    if (clanId > 0)
    {
        char rankName[16];
        GetClanRankLabel(rank, rankName, sizeof(rankName));

        if (clanTag[0])
        {
            FormatEx(title, sizeof(title), "Clan Menu\n%s %s\nRank: %s\nJoining: %s", clanName, clanTag, rankName, isOpen ? "Open" : "Closed");
        }
        else
        {
            FormatEx(title, sizeof(title), "Clan Menu\n%s\nRank: %s\nJoining: %s", clanName, rankName, isOpen ? "Open" : "Closed");
        }

        menu.SetTitle(title);

        if (rank >= ClanRank_Owner)
        {
            char deleteLabel[64];
            FormatEx(deleteLabel, sizeof(deleteLabel), "Delete clan (+%d Gems refund)", CLAN_CREATE_GEM_COST);
            menu.AddItem("leave", deleteLabel);
        }
        else
        {
            menu.AddItem("leave", "Leave clan");
        }

        menu.AddItem("members", "Members");
        menu.AddItem("history", "Clan history");
        menu.AddItem("invite", "Invite player");

        if (rank >= ClanRank_Officer)
        {
            menu.AddItem("kick", "Kick player");
            menu.AddItem("war", "Declare war");
        }

        if (rank >= ClanRank_Owner)
        {
            menu.AddItem("rename", "Rename clan");
            menu.AddItem("tag", "Clan tag");
            menu.AddItem("desc", "Clan description");
            menu.AddItem("open", isOpen ? "Close clan joining" : "Open clan joining");
            menu.AddItem("parent", "Parent clan");
        }
    }
    else
    {
        if (inviteCount > 0)
        {
            FormatEx(title, sizeof(title), "Clan Menu\nYou are not in a clan\nPending invites: %d", inviteCount);
        }
        else
        {
            strcopy(title, sizeof(title), "Clan Menu\nYou are not in a clan");
        }

        menu.SetTitle(title);

        char createLabel[96];
        if (IsClanGemStoreAvailable())
        {
            FormatEx(createLabel, sizeof(createLabel), "Create clan (-%d Gems)", CLAN_CREATE_GEM_COST);
            menu.AddItem("create", createLabel);
        }
        else
        {
            FormatEx(createLabel, sizeof(createLabel), "Create clan (Gems unavailable)");
            menu.AddItem("create_disabled", createLabel, ITEMDRAW_DISABLED);
        }
        menu.AddItem("join", "Join open clan");

        if (inviteCount > 0)
        {
            char invitesLabel[64];
            FormatEx(invitesLabel, sizeof(invitesLabel), "Invites (%d)", inviteCount);
            menu.AddItem("invites", invitesLabel);
        }
        else
        {
            menu.AddItem("noop_invites", "Invites (0)", ITEMDRAW_DISABLED);
        }

        if (inviteCount > 0)
        {
            char acceptLabel[64];
            char denyLabel[64];

            FormatEx(acceptLabel, sizeof(acceptLabel), "Accept invite%s (%d)", (inviteCount == 1) ? "" : "s", inviteCount);
            FormatEx(denyLabel, sizeof(denyLabel), "Deny invite%s (%d)", (inviteCount == 1) ? "" : "s", inviteCount);

            menu.AddItem("accept", acceptLabel);
            menu.AddItem("deny", denyLabel);
        }
    }

    menu.AddItem("refresh", "Refresh");
    menu.Display(client, CLAN_MENU_TIME);
}

