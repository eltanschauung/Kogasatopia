	public void checkRapeChievements(int client)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
			return;
		
		if (!EnsureStatsReady(client, false))
			return;

		int count = g_iRapesGiven[client];
		
		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));
		
		switch (count)
		{
			case 1:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Strange!", name);
			}
			case 10:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Unremarkable!", name);
			}
			case 25:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Scarcely Lethal!", name);
			}
			case 45:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Mildly Menacing!", name);
			}
			case 70:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Somewhat Threatening!", name);
			}
			case 100:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Uncharitable!", name);
			}
			case 135:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Notably Dangerous!", name);
			}
			case 175:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Sufficiently Lethal!", name);
			}
			case 225:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Truly Feared!", name);
			}
			case 275:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Spectacularly Lethal!", name);
			}
			case 350:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Gore-Spattered!", name);
			}
			case 500:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Wicked Nasty!", name);
			}
			case 750:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Positively Inhumane!", name);
			}
			case 999:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Totally Ordinary!", name);
			}
			case 1000:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Face-Melting!", name);
			}
			case 1500:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Rage-Inducing!", name);
			}
			case 2500:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Server-Clearing!", name);
			}
			case 5000:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Epic!", name);
			}
			case 7500:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Legendary!", name);
			}
			case 7616:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Australian!", name);
			}
			case 8500:
			{
				PrintToChatAll("%s's rapes have reached a new rank: Hale's Own!", name);
			}
		}

	}

	void GetRapeRank(int count, char[] buffer, int maxlen)
	{
		if (count >= 8500) strcopy(buffer, maxlen, "Hale's Own");
		else if (count >= 7616) strcopy(buffer, maxlen, "Australian");
		else if (count >= 7500) strcopy(buffer, maxlen, "Legendary");
		else if (count >= 5000) strcopy(buffer, maxlen, "Epic");
		else if (count >= 2500) strcopy(buffer, maxlen, "Server-Clearing");
		else if (count >= 1500) strcopy(buffer, maxlen, "Rage-Inducing");
		else if (count >= 1000) strcopy(buffer, maxlen, "Face-Melting");
		else if (count >= 999) strcopy(buffer, maxlen, "Totally Ordinary");
		else if (count >= 750) strcopy(buffer, maxlen, "Positively Inhumane");
		else if (count >= 500) strcopy(buffer, maxlen, "Wicked Nasty");
		else if (count >= 350) strcopy(buffer, maxlen, "Gore-Spattered");
		else if (count >= 275) strcopy(buffer, maxlen, "Spectacularly Lethal");
		else if (count >= 225) strcopy(buffer, maxlen, "Truly Feared");
		else if (count >= 175) strcopy(buffer, maxlen, "Sufficiently Lethal");
		else if (count >= 135) strcopy(buffer, maxlen, "Notably Dangerous");
		else if (count >= 100) strcopy(buffer, maxlen, "Uncharitable");
		else if (count >= 70) strcopy(buffer, maxlen, "Somewhat Threatening");
		else if (count >= 45) strcopy(buffer, maxlen, "Mildly Menacing");
		else if (count >= 25) strcopy(buffer, maxlen, "Scarcely Lethal");
		else if (count >= 10) strcopy(buffer, maxlen, "Unremarkable");
		else strcopy(buffer, maxlen, "Strange");
	}

	/* ---------------- Helpers ---------------- */

	bool IsClientIndexValid(int client)
	{
		return (client > 0 && client <= MaxClients);
	}

	bool IsHumanClient(int client)
	{
		return (IsClientIndexValid(client) && IsClientConnected(client) && !IsFakeClient(client));
	}

	bool IsHumanClientInGame(int client)
	{
		return (IsHumanClient(client) && IsClientInGame(client));
	}

	bool IsGroupTargetArg(const char[] arg)
	{
		return (StrEqual(arg, "@all", false) || StrEqual(arg, "@red", false) || StrEqual(arg, "@blue", false));
	}

	bool IsCooldownBlocked(float lastTime, float currentTime, float &remaining)
	{
		if (COOLDOWN_TIME - (currentTime - lastTime) > COOLDOWN_TIME)
		{
			remaining = 0.0;
			return false;
		}

		float elapsed = currentTime - lastTime;
		if (elapsed < COOLDOWN_TIME)
		{
			remaining = COOLDOWN_TIME - elapsed;
			return true;
		}

		remaining = 0.0;
		return false;
	}

	int FindPlayerBySubstring(const char[] partial, int exclude)
	{
		char name[64];
		// Exact (case-insensitive)
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == exclude || !IsClientInGame(i)) continue;
			GetClientName(i, name, sizeof(name));
			if (StrEqual(name, partial, false))
				return i;
		}
		// Substring
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == exclude || !IsClientInGame(i)) continue;
			GetClientName(i, name, sizeof(name));
			if (StrContains(name, partial, false) != -1)
				return i;
		}
		return 0;
	}

	void ResetDuel()
	{
		CancelRequestTimer();
		g_bDuelRequested = false;
		g_bDuelActive    = false;
		g_iRequester     = 0;
		g_iTarget        = 0;
		g_iScoreReq      = 0;
		g_iScoreTgt      = 0;
		g_szDuelSteamIds[0][0] = '\0';
		g_szDuelSteamIds[1][0] = '\0';
		g_szDuelNames[0][0] = '\0';
		g_szDuelNames[1][0] = '\0';
	}

	void CaptureDuelParticipantSnapshots()
	{
		int clients[2];
		clients[0] = g_iRequester;
		clients[1] = g_iTarget;
		for (int i = 0; i < sizeof(clients); i++)
		{
			g_szDuelSteamIds[i][0] = '\0';
			g_szDuelNames[i][0] = '\0';
			if (!IsHumanClient(clients[i]))
			{
				continue;
			}

			Kogasa_GetClientSteamId64(clients[i], g_szDuelSteamIds[i], sizeof(g_szDuelSteamIds[]), true);
			GetClientName(clients[i], g_szDuelNames[i], sizeof(g_szDuelNames[]));
		}
	}

	void RecordDuelVictory(int winner, int loser, int winnerScore, int loserScore, const char[] resultType)
	{
		if (!IsDatabaseReady() || winnerScore < 0 || loserScore < 0)
		{
			return;
		}

		int winnerSlot = (winner == g_iRequester) ? 0 : 1;
		int loserSlot = (loser == g_iRequester) ? 0 : 1;
		if (!g_szDuelSteamIds[winnerSlot][0] || !g_szDuelSteamIds[loserSlot][0])
		{
			return;
		}

		char winnerSteamEsc[65], loserSteamEsc[65];
		char winnerNameEsc[(MAX_NAME_LENGTH * 2) + 1], loserNameEsc[(MAX_NAME_LENGTH * 2) + 1];
		char resultEsc[65];
		if (!Db_Escape(g_hDatabase, g_szDuelSteamIds[winnerSlot], winnerSteamEsc, sizeof(winnerSteamEsc), "Hugs")
			|| !Db_Escape(g_hDatabase, g_szDuelSteamIds[loserSlot], loserSteamEsc, sizeof(loserSteamEsc), "Hugs")
			|| !Db_Escape(g_hDatabase, g_szDuelNames[winnerSlot], winnerNameEsc, sizeof(winnerNameEsc), "Hugs")
			|| !Db_Escape(g_hDatabase, g_szDuelNames[loserSlot], loserNameEsc, sizeof(loserNameEsc), "Hugs")
			|| !Db_Escape(g_hDatabase, resultType, resultEsc, sizeof(resultEsc), "Hugs"))
		{
			return;
		}

		char query[1024];
		Format(query, sizeof(query),
			"INSERT INTO %s (winner_steamid64, winner_name, loser_steamid64, loser_name, winner_score, loser_score, result_type, finished_at) VALUES ('%s', '%s', '%s', '%s', %d, %d, '%s', %d)",
			HUGS_DUEL_HISTORY_TABLE,
			winnerSteamEsc,
			winnerNameEsc,
			loserSteamEsc,
			loserNameEsc,
			winnerScore,
			loserScore,
			resultEsc,
			GetTime());
		SQL_TQuery(g_hDatabase, SQL_OnDuelVictorySaved, query);
	}

	public void SQL_OnDuelVictorySaved(Database db, DBResultSet results, const char[] error, any data)
	{
		if (error[0])
		{
			LogError("[Hugs] Failed to save duel victory: %s", error);
		}
	}

	void StartRequestTimer(float seconds)
	{
		CancelRequestTimer();
		g_hRequestTimer = CreateTimer(seconds, Timer_RequestExpire, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	void CancelRequestTimer()
	{
		if (g_hRequestTimer != null)
		{
			CloseHandle(g_hRequestTimer);
			g_hRequestTimer = null;
		}
	}

	public Action Timer_RequestExpire(Handle timer)
	{
		if (timer != g_hRequestTimer)
			return Plugin_Stop;

		g_hRequestTimer = null;

		if (!g_bDuelRequested || g_bDuelActive)
			return Plugin_Stop;

		if (IsClientInGame(g_iRequester))
			PrintToChatSafe(g_iRequester, "\x04[RAPE DUEL]\x01 Duel request to %N expired.", g_iTarget);
		if (IsClientInGame(g_iTarget))
			PrintToChatSafe(g_iTarget, "\x04[RAPE DUEL]\x01 Duel request from %N expired.", g_iRequester);

		ResetDuel();
		return Plugin_Stop;
	}

	// Safe Print (skip if client invalid / disconnected)
	void PrintToChatSafe(int client, const char[] fmt, any ...)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
			return;

		char buffer[256];
		VFormat(buffer, sizeof(buffer), fmt, 3);
		PrintToChat(client, "%s", buffer);
	}

