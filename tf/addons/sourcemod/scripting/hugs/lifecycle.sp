	public void OnPluginStart()
	{
		LoadTranslations("common.phrases");

		RegConsoleCmd("sm_hug", Command_Hug, "Hug another player by name");
		RegConsoleCmd("sm_feed", Command_Feed, "Feed another player by name");
		RegConsoleCmd("sm_rape", Command_Rape, "Rape another player by name");
		RegConsoleCmd("sm_checkhugs", Command_CheckHugs, "Check your total hugs received and given");
		RegConsoleCmd("sm_checkrapes", Command_CheckRapes, "Check your total rapes received and given");
		RegConsoleCmd("sm_hugcheck", Command_CheckHugs, "Check your total hugs received and given");
		RegConsoleCmd("sm_rapecheck", Command_CheckRapes, "Check your total rapes received and given");
		RegConsoleCmd("sm_hugs", Command_CheckHugs); // Alias for !checkhugs
		RegConsoleCmd("sm_feeds", Command_CheckFeeds); // Alias for !feeds
		RegConsoleCmd("sm_fed", Command_CheckFeeds); // Alias for !fed
		RegConsoleCmd("sm_rapes", Command_CheckRapes); // Alias for !checkrapes

		RegAdminCmd("sm_prape", Command_Prape, ADMFLAG_SLAY, "sm_prape <player> - Sets rapes_given to at least 1");

		AddCommandListener(Hugs_SayListener, "say");
		AddCommandListener(Hugs_SayListener, "say_team");

		RegConsoleCmd("sm_hl", Command_Leaderboard, "Show hugs leaderboard");
		RegConsoleCmd("sm_hl2", Command_Leaderboard, "Show hugs received leaderboard");
		RegConsoleCmd("sm_rl", Command_Leaderboard, "Show rapes leaderboard");
		RegConsoleCmd("sm_rl2", Command_Leaderboard, "Show rapes received leaderboard");
		RegConsoleCmd("sm_leaderboard", Command_Leaderboard, "Show rapes leaderboard");
		RegConsoleCmd("sm_rapesleaderboard", Command_Leaderboard, "Show rapes leaderboard");
		RegConsoleCmd("sm_hugsleaderboard", Command_Leaderboard, "Show hugs leaderboard");

		// Set default values for cookies if they don't exist
		SetCookieMenuItem(StatsCookieMenuHandler, 0, "Hug/Rape Stats");
		
		RegConsoleCmd("sm_duel",   Command_Duel,   "Challenge a player: !duel <name substring>");
		RegConsoleCmd("sm_rapeduel",   Command_Duel,   "Alias of !duel");
		RegConsoleCmd("sm_duelhistory", Command_DuelHistory, "Show recent duel victories");
		RegConsoleCmd("sm_rapeduelhistory", Command_DuelHistory, "Show recent duel victories");
		RegConsoleCmd("sm_accept", Command_Accept, "Accept a pending duel");
		RegConsoleCmd("sm_protect", Command_RapeProtect, "Protect a player from rape");
		RegConsoleCmd("sm_guard", Command_RapeProtect, "Protect a player from rape");
		RegConsoleCmd("sm_rapeprotect", Command_RapeProtect, "Protect a player from rape");
		RegConsoleCmd("sm_rapeshield", Command_RapeProtect, "Protect a player from rape");
		RegConsoleCmd("sm_shield", Command_RapeProtect, "Protect a player from rape");
		RegConsoleCmd("sm_defend", Command_RapeProtect, "Protect a player from rape");

		HookEvent("player_death",            Event_PlayerDeath, EventHookMode_Post);
		HookEvent("teamplay_round_win",      Event_RoundEnd,    EventHookMode_Post);
		HookEvent("teamplay_round_stalemate",Event_RoundEnd,    EventHookMode_Post);

		g_hTargetScore    = CreateConVar("sm_rapeduel_targetscore", "5",  "rapes needed to win a duel", _, true, 1.0);
		g_hRequestTimeout = CreateConVar("sm_rapeduel_requesttime", "30", "Seconds before a duel request expires", _, true, 5.0);
		g_hRapeProtectionDuration = CreateConVar("sm_rapeprotection_duration", "60", "Seconds that rape protection lasts.", _, true, 1.0);

		AutoExecConfig(true, "rapeduel");

		for (int i = 1; i <= MaxClients; i++)
		{
			ResetClientStats(i);
			g_fLastHugTime[i] = 0.0;
			g_fLastRapeTime[i] = 0.0;
			g_hReminderTimer[i] = null;
			g_hStatsRetryTimer[i] = null;
			g_hRapeProtectionTimer[i] = null;
			g_iRapeProtectorUserId[i] = 0;
			g_szRapeProtectorName[i][0] = '\0';
			g_szRapeProtectedName[i][0] = '\0';
		}

		g_hMultiplierCvar = CreateConVar("sm_hugs_multiplier", "1", "Multiplier for hug/rape stats (0 or 1 disable).", FCVAR_NOTIFY);
		g_hMultiplierCvar.AddChangeHook(ConVarChanged_Multiplier);
		UpdateMultiplierValue();

		ConnectToDatabase();
		EnsureRedlistCookie();
	}

	public void OnPluginEnd()
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			ClearRapeProtection(i, true);
		}
		Db_CancelTimer(g_hDbReconnectTimer);
		Db_Close(g_hDatabase, g_bDatabaseReady);
	}

	void EnsureRedlistCookie()
	{
		if (g_hRedlistCookie == INVALID_HANDLE)
		{
			g_hRedlistCookie = FindClientCookie("filter_redlist");
		}
	}

	bool IsClientRedlisted(int client)
	{
		if (!IsClientIndexValid(client))
		{
			return false;
		}

		if (GetFeatureStatus(FeatureType_Native, "Filters_IsRedlisted") == FeatureStatus_Available)
		{
			return Filters_IsRedlisted(client);
		}

		if (!AreClientCookiesCached(client))
		{
			return false;
		}

		EnsureRedlistCookie();
		if (g_hRedlistCookie == INVALID_HANDLE)
		{
			return false;
		}

		char cookie[8];
		GetClientCookie(client, g_hRedlistCookie, cookie, sizeof(cookie));
		return StrEqual(cookie, "1");
	}

	Action Hugs_SayListener(int client, const char[] command, int argc)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
		{
			return Plugin_Continue;
		}

		char message[256];
		GetCmdArgString(message, sizeof(message));
		StripQuotes(message);
		TrimString(message);

		if (!message[0])
		{
			return Plugin_Continue;
		}

		if (message[0] != '!' && message[0] != '/')
		{
			return Plugin_Continue;
		}

		char payload[256];
		strcopy(payload, sizeof(payload), message);
		payload[0] = ' ';
		TrimString(payload);
		if (!payload[0])
		{
			return Plugin_Continue;
		}

		char cmdName[64];
		char args[192];
		strcopy(cmdName, sizeof(cmdName), payload);
		int spaceIndex = FindCharInString(cmdName, ' ');
		if (spaceIndex != -1)
		{
			cmdName[spaceIndex] = '\0';
			strcopy(args, sizeof(args), payload[spaceIndex + 1]);
			TrimString(args);
		}
		else
		{
			args[0] = '\0';
		}

		if (!StrEqual(cmdName, "hug", false) && !StrEqual(cmdName, "feed", false) && !StrEqual(cmdName, "rape", false))
		{
			return Plugin_Continue;
		}

		if (!IsClientRedlisted(client))
		{
			return Plugin_Continue;
		}

		if (StrEqual(cmdName, "hug", false))
		{
			if (args[0])
			{
				FakeClientCommand(client, "sm_hug %s", args);
			}
			else
			{
				FakeClientCommand(client, "sm_hug");
			}
		}
		else if (StrEqual(cmdName, "feed", false))
		{
			if (args[0])
			{
				FakeClientCommand(client, "sm_feed %s", args);
			}
			else
			{
				FakeClientCommand(client, "sm_feed");
			}
		}
		else
		{
			if (args[0])
			{
				FakeClientCommand(client, "sm_rape %s", args);
			}
			else
			{
				FakeClientCommand(client, "sm_rape");
			}
		}

		return Plugin_Handled;
	}

	public void OnClientPutInServer(int client)
	{
		ClearRapeProtection(client, true);
		ResetClientStats(client);
		g_fLastHugTime[client] = 0.0;
		g_fLastRapeTime[client] = 0.0;

		if (!IsHumanClient(client))
		{
			if (IsClientIndexValid(client))
			{
				g_bStatsLoaded[client] = true;
			}
			return;
		}

		AttemptLoadClientStats(client);
		MaybeScheduleReminder(client);
	}

	public void OnClientAuthorized(int client, const char[] auth)
	{
		if (!IsHumanClient(client))
		{
			return;
		}

		AttemptLoadClientStats(client);
	}

	public void OnClientDisconnect(int client)
	{
		ClearRapeProtection(client, true);
		SaveClientStats(client);
		ResetClientStats(client);
		CancelReminderTimer(client);

		if (g_bDuelRequested)
		{
			if (client == g_iRequester || client == g_iTarget)
			{
				PrintToChatSafe(g_iRequester, "\x04[RAPE DUEL]\x01 Duel request canceled (%N disconnected).", client);
				PrintToChatSafe(g_iTarget,    "\x04[RAPE DUEL]\x01 Duel request canceled (%N disconnected).", client);
				ResetDuel();
			}
		}
	else if (g_bDuelActive)
	{
		if (client == g_iRequester || client == g_iTarget)
		{
			int winner = (client == g_iRequester) ? g_iTarget : g_iRequester;
				if (IsClientInGame(winner))
				{
					PrintToChatAll("\x04[RAPE DUEL]\x01 %N disconnected. %N wins the rape duel by forfeit! Final Score: %N %d - %N %d",
								   client, winner,
								   g_iRequester, g_iScoreReq,
								   g_iTarget,    g_iScoreTgt);
				}
				int winnerScore = (winner == g_iRequester) ? g_iScoreReq : g_iScoreTgt;
				int loserScore = (winner == g_iRequester) ? g_iScoreTgt : g_iScoreReq;
				RecordDuelVictory(winner, client, winnerScore, loserScore, "forfeit");
				ResetDuel();
		}
	}
}

