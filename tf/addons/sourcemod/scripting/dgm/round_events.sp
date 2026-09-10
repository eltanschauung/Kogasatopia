public void Event_RoundActive(Event event, const char[] name, bool dontBroadcast)
{
    g_bGameRulesReady = true;
    g_bSetupTeamRatioForwardFired = false;
    DGM_ClearAllRespawnTimers();
    g_iRoundStartTimestamp = GetTime();
    g_iLastRoundDuration = 0;
    DGM_ResetCaptureIntervalStats(g_iRoundStartTimestamp);

    if (g_cvTimeOverride != null)    g_cvTimeOverride.RestoreDefault();
    if (!g_cvPopulationRespawns.BoolValue)
    {
        // Round end forces this true; unmanaged modes need their configured state restored.
        g_InternalOverride = DGM_AreRespawnTimesForcedOn();
    }

    DGM_AdjustRespawnByPlayerCount(0);
    g_PointCaptures = 0;
    DGM_UpdateSetupState();
    if (!g_bRoundStartedOnce)
    {
        g_bRoundStartedOnce = true;
        RequestFrame(AdjustByPlayerCount);
    }
    if (GetConVarInt(g_cvSetSetupTime) != 0)
    {
        SetSetupTime(0);
        DGM_UpdateSetupState();
    }

    RequestFrame(DGM_FrameUpdateSetupState);
    DGM_QueueSetupStartCheck();
	if (GetConVarInt(g_cvAutoAddTime)) {
        int addTime = GetConVarInt(g_cvAutoAddTime);
		int entityTimer = FindEntityByClassname(-1, "tf_logic_koth");
		if (entityTimer > -1)
		{
			SetVariantInt(addTime);
			AcceptEntityInput(entityTimer, "SetBlueTimer");
			SetVariantInt(addTime);
			AcceptEntityInput(entityTimer, "SetRedTimer");
		}
	}
}

public void Event_SetupFinished(Event event, const char[] name, bool dontBroadcast)
{
    g_bGameRulesReady = true;
    DGM_SetSetupActive(false);
}

public void Event_RoundFullyActive(Event event, const char[] name, bool dontBroadcast)
{
    g_bGameRulesReady = true;
    if (DGM_IsSetupBhopActive())
    {
        DGM_SetSetupActive(true);
        return;
    }

    if (g_bSetupActive)
    {
        DGM_UpdateSetupState();
        return;
    }

    DGM_QueueSetupStartCheck();
}

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    g_bGameRulesReady = true;
    DGM_ClearAllRespawnTimers();
    int roundEndTimestamp = GetTime();
    g_iLastRoundDuration = DGM_CalculateRoundDurationSeconds(g_iRoundStartTimestamp, roundEndTimestamp);
    DGM_LogCaptureIntervalStats(event.GetInt("team"), g_iLastRoundDuration);

    SetConVarInt(g_cvTimeOverride, 30);
    g_PointCaptures = 0;
    DGM_ResetCaptureIntervalStats(0);
    g_InternalOverride = true; // We're gonna stop clients from getting insta-respawned with this
    DGM_RefreshRespawnVisualState();
}

public Action Command_ResetSetup(int client , int args)
{
    int timerEnt = DGM_FindSetupRoundTimer();
    if (timerEnt == -1)
    {
        if (client > 0) PrintToChat(client, "No team_round_timer entity found.");
        else PrintToServer("[Kogasa] No team_round_timer entity found.");
        return Plugin_Handled;
    }

    int time = 10;
    if (args > 0)
    {
        if (!GetCmdArgIntEx( 1, args))
        {
            ReplyToCommand(client, "Given time must be a number!" );
            return Plugin_Continue;
        }
    }
	char temp[ 4 ];
	GetCmdArg( 1, temp, 4 );
	time = StringToInt(temp) + 1;
    DGM_SetSetupTimerTime(timerEnt, time);

    if (client > 0) PrintToChatAll("Setup time reduced to %i seconds.", time);
    PrintToServer("[Kogasa] Setup time set to %i seconds.", time);
    return Plugin_Handled;
}

public Action Command_ExtendTimer(int client , int args)
{
	if (args < 1)
	{
		DGM_ReplyCurrentRoundTimers(client);
		return Plugin_Handled;
	}

    char temp[16];
    GetCmdArg(1, temp, sizeof(temp));
    int time = StringToInt(temp);
    if (time <= 0 || !GetCmdArgIntEx(1, time))
    {
        ReplyToCommand(client, "Given time must be a positive number!");
        return Plugin_Handled;
    }

    int timerEnt = FindEntityByClassname(-1, "team_round_timer");
    if (timerEnt == -1)
    {
        if (client > 0) PrintToChat(client, "No team_round_timer entity found.");
        else PrintToServer("[Kogasa] No team_round_timer entity found.");
        return Plugin_Handled;
    }

    DGM_SetRoundTimerTime(timerEnt, time);

    if (client > 0) PrintToChatAll("Round timer set to %i seconds.", time);
	PrintToServer("[Kogasa] Round timer set to %i seconds.", time);
	return Plugin_Handled;
}

void DGM_ReplyCurrentRoundTimers(int client)
{
	int timerEnt = -1;
	int found = 0;
	char targetName[64];

	while ((timerEnt = FindEntityByClassname(timerEnt, "team_round_timer")) != -1)
	{
		if (!IsValidEntity(timerEnt))
		{
			continue;
		}

		found++;
		DGM_GetEntityTargetName(timerEnt, targetName, sizeof(targetName));
		int remaining = DGM_GetRoundTimerRemaining(timerEnt);
		if (targetName[0] == '\0')
		{
			Format(targetName, sizeof(targetName), "unnamed");
		}

		if (remaining >= 0)
		{
			ReplyToCommand(client, "Timer #%d (%s): %d seconds remaining.", found, targetName, remaining);
		}
		else
		{
			ReplyToCommand(client, "Timer #%d (%s): remaining time unavailable.", found, targetName);
		}
	}

	if (found == 0)
	{
		ReplyToCommand(client, "No team_round_timer entity found.");
	}
}
