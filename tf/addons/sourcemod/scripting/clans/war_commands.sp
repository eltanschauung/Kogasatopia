public Action Command_ClanWar(int client, int args)
{
    if (client <= 0)
    {
        ReplyToCommand(client, "[Clans] This command can only be used by players.");
        return Plugin_Handled;
    }

    if (!EnsureClanWarsAvailable(client))
    {
        return Plugin_Handled;
    }

    char steamid64[STEAMID64_MAXLEN];
    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    int clanId = 0;
    ClanRank rank = ClanRank_Member;
    if (!GetLoadedClientClanContext(client, steamid64, sizeof(steamid64), clanId, rank, clanName, sizeof(clanName), clanTag, sizeof(clanTag)))
    {
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return Plugin_Handled;
    }

    if (clanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return Plugin_Handled;
    }

    if (rank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can declare war.");
        return Plugin_Handled;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;
    if (GetActiveClanWarForClanCached(clanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        ShowClanWarDecisionMenu(client, (clanIdA == clanId) ? clanIdB : clanIdA, true);
        return Plugin_Handled;
    }

    ShowClanWarTargetMenu(client, clanId);
    return Plugin_Handled;
}

public Action Command_ClanHistory(int client, int args)
{
    if (client <= 0)
    {
        ReplyToCommand(client, "[Clans] This command can only be used by players.");
        return Plugin_Handled;
    }

    if (!EnsureDatabaseReady(client))
    {
        return Plugin_Handled;
    }

    char steamid64[STEAMID64_MAXLEN];
    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    int clanId = 0;
    ClanRank rank = ClanRank_Member;
    if (!GetClientClanContextSync(client, steamid64, sizeof(steamid64), clanId, rank, clanName, sizeof(clanName), clanTag, sizeof(clanTag)))
    {
        PrintToChat(client, "[Clans] Failed to load your clan history.");
        return Plugin_Handled;
    }

    if (clanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return Plugin_Handled;
    }

    ShowClanHistoryMenu(client, clanId, clanName);
    return Plugin_Handled;
}

void ShowClanWarTargetMenu(int client, int actorClanId)
{
    if (!EnsureClanWarsAvailable(client))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanWarTarget);
    menu.SetTitle("Declare War");
    menu.ExitBackButton = true;

    int seenClanIds[MAXPLAYERS + 1];
    int seenCount = 0;
    bool added = false;

    for (int pass = 0; pass < 2; pass++)
    {
        ClanRank desiredRank = (pass == 0) ? ClanRank_Owner : ClanRank_Officer;

        for (int target = 1; target <= MaxClients; target++)
        {
            if (!Client_IsHumanInGame(target) || target == client)
            {
                continue;
            }

            char targetSteam[STEAMID64_MAXLEN];
            char targetClanName[CLAN_NAME_MAXLEN + 1];
            char targetClanTag[CLAN_TAG_STORE_MAXLEN];
            int targetClanId = 0;
            ClanRank targetRank = ClanRank_Member;
            if (!GetLoadedClientClanContext(target, targetSteam, sizeof(targetSteam), targetClanId, targetRank, targetClanName, sizeof(targetClanName), targetClanTag, sizeof(targetClanTag)))
            {
                continue;
            }

            if (targetClanId <= 0 || targetClanId == actorClanId || targetRank != desiredRank)
            {
                continue;
            }

            bool alreadySeen = false;
            for (int i = 0; i < seenCount; i++)
            {
                if (seenClanIds[i] == targetClanId)
                {
                    alreadySeen = true;
                    break;
                }
            }

            if (alreadySeen)
            {
                continue;
            }

            int warId = 0;
            int clanIdA = 0;
            int clanIdB = 0;
            int scoreA = 0;
            int scoreB = 0;
            if (GetActiveClanWarForClanCached(targetClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
            {
                continue;
            }

            seenClanIds[seenCount++] = targetClanId;

            char displayTag[CLAN_TAG_STORE_MAXLEN];
            char targetName[MAX_NAME_LENGTH];
            char display[192];
            char info[16];
            BuildClanDisplayTag(targetClanTag, displayTag, sizeof(displayTag));
            GetClientName(target, targetName, sizeof(targetName));
            IntToString(targetClanId, info, sizeof(info));

            if (displayTag[0])
            {
                FormatEx(display, sizeof(display), "%s %s - %s", displayTag, targetClanName, targetName);
            }
            else
            {
                FormatEx(display, sizeof(display), "%s - %s", targetClanName, targetName);
            }

            CRemoveTags(display, sizeof(display));
            menu.AddItem(info, display);
            added = true;
        }
    }

    if (!added)
    {
        menu.AddItem("none", "No eligible clan owners/officers are online", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

void ShowClanWarDecisionMenu(int client, int targetClanId, bool surrender)
{
    if (!EnsureClanWarsAvailable(client))
    {
        return;
    }

    char actorSteam[STEAMID64_MAXLEN];
    char actorClanName[CLAN_NAME_MAXLEN + 1];
    char actorClanTag[CLAN_TAG_STORE_MAXLEN];
    int actorClanId = 0;
    ClanRank actorRank = ClanRank_Member;
    if (!GetLoadedClientClanContext(client, actorSteam, sizeof(actorSteam), actorClanId, actorRank, actorClanName, sizeof(actorClanName), actorClanTag, sizeof(actorClanTag)) || actorClanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    Menu menu = new Menu(MenuHandler_ClanWarDecision);
    char title[512];

    if (surrender)
    {
        int warId = 0;
        int clanIdA = 0;
        int clanIdB = 0;
        int scoreA = 0;
        int scoreB = 0;
        if (!GetActiveClanWarByPairCached(actorClanId, targetClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
        {
            PrintToChat(client, "[Clans] You are not currently at war with that clan.");
            delete menu;
            return;
        }

        int actorScore = (actorClanId == clanIdA) ? scoreA : scoreB;
        int targetScore = (targetClanId == clanIdA) ? scoreA : scoreB;

        char targetLabel[96];
        int warIndex = FindActiveWarIndexByPair(actorClanId, targetClanId);
        if (warIndex != -1)
        {
            ActiveClanWar war;
            g_hActiveWars.GetArray(warIndex, war);
            strcopy(targetLabel, sizeof(targetLabel), (targetClanId == war.clanIdA) ? war.announceLabelA : war.announceLabelB);
        }
        if (!targetLabel[0])
        {
            FormatEx(targetLabel, sizeof(targetLabel), "%d", targetClanId);
        }
        CRemoveTags(targetLabel, sizeof(targetLabel));
        TrimString(targetLabel);
        FormatEx(title, sizeof(title), "Clan War\nOpponent: %s\nCurrent score: %d - %d", targetLabel, actorScore, targetScore);
    }
    else
    {
        char targetClanName[CLAN_NAME_MAXLEN + 1];
        char targetClanTag[CLAN_TAG_STORE_MAXLEN];
        char representativeName[MAX_NAME_LENGTH * 2];
        int onlineCount = 0;
        if (!GetCachedOnlineClanSummary(targetClanId, targetClanName, sizeof(targetClanName), targetClanTag, sizeof(targetClanTag), representativeName, sizeof(representativeName), onlineCount))
        {
            PrintToChat(client, "[Clans] That clan is not available.");
            delete menu;
            return;
        }

        char plainTag[CLAN_TAG_STORE_MAXLEN];
        BuildPlainClanTag(targetClanTag, plainTag, sizeof(plainTag));
        FormatEx(title, sizeof(title),
            "Clan War\n%s\nTag: %s\nRepresented by: %s\nOnline members: %d",
            targetClanName,
            plainTag[0] ? plainTag : "(none)",
            representativeName[0] ? representativeName : "online member",
            onlineCount);
    }

    menu.SetTitle(title);
    menu.ExitBackButton = true;

    char info[32];
    FormatEx(info, sizeof(info), "%s:%d", surrender ? "surrender" : "declare", targetClanId);
    menu.AddItem(info, surrender ? "Surrender" : "Go to war");
    menu.AddItem("cancel", "Cancel");
    menu.Display(client, CLAN_MENU_TIME);
}

void ShowClanWarSurrenderConfirmMenu(int client, int targetClanId)
{
    if (!EnsureClanWarsAvailable(client))
    {
        return;
    }

    char actorSteam[STEAMID64_MAXLEN];
    char actorClanName[CLAN_NAME_MAXLEN + 1];
    char actorClanTag[CLAN_TAG_STORE_MAXLEN];
    int actorClanId = 0;
    ClanRank actorRank = ClanRank_Member;
    if (!GetLoadedClientClanContext(client, actorSteam, sizeof(actorSteam), actorClanId, actorRank, actorClanName, sizeof(actorClanName), actorClanTag, sizeof(actorClanTag)) || actorClanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can surrender a war.");
        return;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;
    if (!GetActiveClanWarByPairCached(actorClanId, targetClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        PrintToChat(client, "[Clans] You are not currently at war with that clan.");
        return;
    }

    int actorScore = (actorClanId == clanIdA) ? scoreA : scoreB;
    int targetScore = (targetClanId == clanIdA) ? scoreA : scoreB;

    char targetLabel[96];
    targetLabel[0] = '\0';
    int warIndex = FindActiveWarIndexByPair(actorClanId, targetClanId);
    if (warIndex != -1)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(warIndex, war);
        strcopy(targetLabel, sizeof(targetLabel), (targetClanId == war.clanIdA) ? war.announceLabelA : war.announceLabelB);
    }
    if (!targetLabel[0])
    {
        FormatEx(targetLabel, sizeof(targetLabel), "%d", targetClanId);
    }
    CRemoveTags(targetLabel, sizeof(targetLabel));
    TrimString(targetLabel);

    Menu menu = new Menu(MenuHandler_ClanWarSurrenderConfirm);
    char title[512];
    FormatEx(title, sizeof(title), "Confirm Surrender\nOpponent: %s\nCurrent score: %d - %d\nThis will end the war.", targetLabel, actorScore, targetScore);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    char info[16];
    IntToString(targetClanId, info, sizeof(info));
    menu.AddItem("cancel", "Cancel");
    menu.AddItem(info, "Confirm surrender");
    menu.Display(client, CLAN_MENU_TIME);
}

void HandleClanWarDeclare(int client, int targetClanId)
{
    if (!EnsureClanWarsAvailable(client))
    {
        return;
    }

    char actorSteam[STEAMID64_MAXLEN];
    char actorClanName[CLAN_NAME_MAXLEN + 1];
    char actorClanTag[CLAN_TAG_STORE_MAXLEN];
    int actorClanId = 0;
    ClanRank actorRank = ClanRank_Member;
    if (!GetLoadedClientClanContext(client, actorSteam, sizeof(actorSteam), actorClanId, actorRank, actorClanName, sizeof(actorClanName), actorClanTag, sizeof(actorClanTag)))
    {
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (actorClanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can declare war.");
        return;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;
    if (GetActiveClanWarForClanCached(actorClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        ShowClanWarDecisionMenu(client, (clanIdA == actorClanId) ? clanIdB : clanIdA, true);
        return;
    }

    if (targetClanId == actorClanId)
    {
        PrintToChat(client, "[Clans] You cannot declare war on your own clan.");
        return;
    }

    if (GetActiveClanWarForClanCached(targetClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        PrintToChat(client, "[Clans] That clan is already at war.");
        return;
    }

    int cooldownSeconds = 0;
    if (GetClanWarRedeclareCooldownSync(actorClanId, targetClanId, cooldownSeconds))
    {
        char targetLabel[96];
        GetClanWarTargetCooldownLabel(targetClanId, targetLabel, sizeof(targetLabel));
        int cooldownMinutes = (cooldownSeconds + 59) / 60;
        CPrintToChat(client, "{green}[Clans]{default} You can't declare war on %s until %d minutes from now.", targetLabel, cooldownMinutes);
        return;
    }

    if (!StartClanWarAsync(client, actorClanId, targetClanId, actorSteam))
    {
        PrintToChat(client, "[Clans] Failed to declare war.");
        return;
    }

    PrintToChat(client, "[Clans] War declaration queued.");
}

void HandleClanWarSurrender(int client, int targetClanId)
{
    if (!EnsureClanWarsAvailable(client))
    {
        return;
    }

    char actorSteam[STEAMID64_MAXLEN];
    char actorClanName[CLAN_NAME_MAXLEN + 1];
    char actorClanTag[CLAN_TAG_STORE_MAXLEN];
    int actorClanId = 0;
    ClanRank actorRank = ClanRank_Member;
    if (!GetLoadedClientClanContext(client, actorSteam, sizeof(actorSteam), actorClanId, actorRank, actorClanName, sizeof(actorClanName), actorClanTag, sizeof(actorClanTag)))
    {
        PrintToChat(client, "[Clans] Failed to look up your clan.");
        return;
    }

    if (actorClanId <= 0)
    {
        PrintToChat(client, "[Clans] You are not in a clan.");
        return;
    }

    if (actorRank < ClanRank_Officer)
    {
        PrintToChat(client, "[Clans] Only officers and owners can surrender a war.");
        return;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;
    if (!GetActiveClanWarByPairCached(actorClanId, targetClanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        PrintToChat(client, "[Clans] You are not currently at war with that clan.");
        return;
    }

    if (!FinalizeClanWarSync(warId, clanIdA, clanIdB, scoreA, scoreB, targetClanId, ClanWarStatus_Surrendered))
    {
        PrintToChat(client, "[Clans] Failed to surrender the war.");
        return;
    }

    PrintToChat(client, "[Clans] You surrendered the war.");
}

public int MenuHandler_ClanWarTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanMenu(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        int targetClanId = StringToInt(info);
        if (targetClanId > 0)
        {
            ShowClanWarDecisionMenu(param1, targetClanId, false);
        }
    }

    return 0;
}

public int MenuHandler_ClanWarDecision(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanWar(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "cancel", false))
        {
            Command_ClanMenu(param1, 0);
            return 0;
        }

        char pieces[2][16];
        int count = ExplodeString(info, ":", pieces, sizeof(pieces), sizeof(pieces[]));
        if (count != 2)
        {
            return 0;
        }

        int targetClanId = StringToInt(pieces[1]);
        if (targetClanId <= 0)
        {
            return 0;
        }

        if (StrEqual(pieces[0], "declare", false))
        {
            HandleClanWarDeclare(param1, targetClanId);
        }
        else if (StrEqual(pieces[0], "surrender", false))
        {
            ShowClanWarSurrenderConfirmMenu(param1, targetClanId);
        }
    }

    return 0;
}

public int MenuHandler_ClanWarSurrenderConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanWar(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "cancel", false))
        {
            Command_ClanWar(param1, 0);
            return 0;
        }

        int targetClanId = StringToInt(info);
        if (targetClanId > 0)
        {
            HandleClanWarSurrender(param1, targetClanId);
        }
    }

    return 0;
}

public int MenuHandler_ClanHistory(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            Command_ClanMenu(param1, 0);
        }
    }
    else if (action == MenuAction_Select)
    {
        int client = param1;
        if (client <= 0 || !IsClientInGame(client))
        {
            return 0;
        }

        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        char pieces[2][16];
        if (ExplodeString(info, ":", pieces, sizeof(pieces), sizeof(pieces[])) == 2 && StrEqual(pieces[0], "war", false))
        {
            int warInstanceId = StringToInt(pieces[1]);
            if (warInstanceId > 0)
            {
                ShowClanWarHistoryDetailsMenu(client, g_iClanHistoryMenuClanId[client], g_sClanHistoryMenuClanName[client], warInstanceId);
            }
        }
    }

    return 0;
}

public int MenuHandler_ClanWarHistoryDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
        {
            ShowClanHistoryMenu(param1, g_iClanHistoryMenuClanId[param1], g_sClanHistoryMenuClanName[param1]);
        }
    }

    return 0;
}

void PrintClanWarGemStealMessages(int attacker, int victim, int stolen)
{
    if (stolen <= 0)
    {
        return;
    }

    char attackerName[384];
    char victimName[384];
    BuildClanChatSenderName(attacker, attackerName, sizeof(attackerName));
    BuildClanChatSenderName(victim, victimName, sizeof(victimName));

    CPrintToChatEx(victim, attacker, "{cyan}[Gems]{default} %s stole {red}%d {cyan}Gems{default} from you!", attackerName, stolen);
    CPrintToChatEx(attacker, victim, "{cyan}[Gems]{default} You stole {green}+%d {cyan}Gems {default}from %s!", stolen, victimName);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int deathFlags = event.GetInt("death_flags");

    if (!ClanWarsRuntimeReady() || !Clans_IsRoundRunning())
    {
        return;
    }

    if (victim <= 0 || victim > MaxClients || attacker <= 0 || attacker > MaxClients || attacker == victim)
    {
        return;
    }

    if (deathFlags & TF_DEATHFLAG_DEADRINGER)
    {
        return;
    }

    if (!IsClientInGame(victim) || !IsClientInGame(attacker) || IsFakeClient(victim) || IsFakeClient(attacker))
    {
        return;
    }

    if (GetClientTeam(victim) <= 1 || GetClientTeam(attacker) <= 1 || GetClientTeam(victim) == GetClientTeam(attacker))
    {
        return;
    }

    int attackerClanId = 0;
    int victimClanId = 0;
    if (!ResolveClientClanIdForWarScoring(attacker, attackerClanId) || !ResolveClientClanIdForWarScoring(victim, victimClanId))
    {
        return;
    }

    if (attackerClanId <= 0 || victimClanId <= 0 || attackerClanId == victimClanId)
    {
        return;
    }

    int warIndex = FindActiveWarIndexByPair(attackerClanId, victimClanId);
    if (warIndex == -1)
    {
        return;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(warIndex, war);

    bool attackerIsClanA = (attackerClanId == war.clanIdA);
    if (attackerIsClanA)
    {
        war.scoreA++;
    }
    else
    {
        war.scoreB++;
    }

    war.writeDirty = true;

    g_hActiveWars.SetArray(warIndex, war);

    int stolen = StealClanWarGems(attacker, victim, CLAN_WAR_GEMS_STOLEN_PER_KILL);
    if (stolen > 0)
    {
        PrintClanWarGemStealMessages(attacker, victim, stolen);
    }

    char attackerSteam[STEAMID64_MAXLEN];
    if (war.instanceId > 0 && GetClientSteam64(attacker, attackerSteam, sizeof(attackerSteam)))
    {
        RecordClanWarKill(war.instanceId, attackerClanId, attackerSteam, stolen);
    }

    int attackerScore = attackerIsClanA ? war.scoreA : war.scoreB;
    int victimScore = attackerIsClanA ? war.scoreB : war.scoreA;

    BroadcastClanWarScoreUpdate(
        attackerIsClanA ? war.announceLabelA : war.announceLabelB,
        attackerIsClanA ? war.announceLabelB : war.announceLabelA,
        attackerClanId,
        victimClanId,
        attackerScore,
        victimScore,
        war.instanceId,
        attacker,
        victim);

    if (attackerScore >= CLAN_WAR_POINT_GOAL)
    {
        FinalizeClanWarSync(war.warId, war.clanIdA, war.clanIdB, war.scoreA, war.scoreB, attackerClanId, ClanWarStatus_Finished);
    }
}

