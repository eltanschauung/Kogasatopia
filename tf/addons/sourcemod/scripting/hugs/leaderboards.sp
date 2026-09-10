	public void StatsCookieMenuHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
	{
		if (action == CookieMenuAction_DisplayOption)
		{
			Format(buffer, maxlen, "Check Hug/Rape Stats");
		}
		else if (action == CookieMenuAction_SelectOption)
		{
			Command_CheckHugs(client, 0);
		}
	}

	HugsLeaderboardKind GetLeaderboardKindFromCommand()
	{
		char command[64];
		GetCmdArg(0, command, sizeof(command));

		if (StrEqual(command, "sm_hl", false) || StrEqual(command, "sm_hl2", false) || StrEqual(command, "sm_hugsleaderboard", false))
		{
			return HugsLeaderboard_Hugs;
		}

		return HugsLeaderboard_Rapes;
	}

	bool IsLeaderboardReceivedFirstCommand()
	{
		char command[64];
		GetCmdArg(0, command, sizeof(command));
		return StrEqual(command, "sm_hl2", false) || StrEqual(command, "sm_rl2", false);
	}

	public Action Command_Leaderboard(int client, int args)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
		{
			return Plugin_Handled;
		}

		if (!IsDatabaseReady())
		{
			ReplyToCommand(client, "[SM] Database not ready.");
			return Plugin_Handled;
		}

		HugsLeaderboardKind kind = GetLeaderboardKindFromCommand();
		bool receivedFirst = IsLeaderboardReceivedFirstCommand();
		char givenColumn[32];
		char receivedColumn[32];
		if (kind == HugsLeaderboard_Hugs)
		{
			strcopy(givenColumn, sizeof(givenColumn), "h.hugs_given");
			strcopy(receivedColumn, sizeof(receivedColumn), "h.hugs_received");
		}
		else
		{
			strcopy(givenColumn, sizeof(givenColumn), "h.rapes_given");
			strcopy(receivedColumn, sizeof(receivedColumn), "h.rapes_received");
		}

		char primaryColumn[32];
		char secondaryColumn[32];
		strcopy(primaryColumn, sizeof(primaryColumn), receivedFirst ? receivedColumn : givenColumn);
		strcopy(secondaryColumn, sizeof(secondaryColumn), receivedFirst ? givenColumn : receivedColumn);

		char steam64Expr[288];
		strcopy(steam64Expr, sizeof(steam64Expr), "CONVERT(CAST(76561197960265728 + (SUBSTRING_INDEX(h.steamid, ':', -1) * 2) + SUBSTRING_INDEX(SUBSTRING_INDEX(h.steamid, ':', 2), ':', -1) AS CHAR) USING utf8mb4)");

		char query[2048];
		Format(query, sizeof(query),
			"SELECT h.name, %s AS given_count, %s AS received_count, h.steamid, "
			... "COALESCE(NULLIF(pr.newname, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, '')) AS wt_name "
			... "FROM %s h "
			... "LEFT JOIN prename_rules pr ON pr.pattern = %s COLLATE utf8mb4_general_ci "
			... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = %s COLLATE utf8mb4_uca1400_ai_ci "
			... "LEFT JOIN whaletracker w ON w.steamid = %s COLLATE utf8mb4_uca1400_ai_ci "
			... "WHERE %s > 0 OR %s > 0 "
			... "ORDER BY %s DESC, %s DESC, h.name ASC LIMIT 10",
			givenColumn,
			receivedColumn,
			HUGS_DB_TABLE,
			steam64Expr,
			steam64Expr,
			steam64Expr,
			givenColumn,
			receivedColumn,
			primaryColumn,
			secondaryColumn);

		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(view_as<int>(kind));
		SQL_TQuery(g_hDatabase, SQL_OnLeaderboardLoaded, query, pack);
		return Plugin_Handled;
	}

	public void SQL_OnLeaderboardLoaded(Database db, DBResultSet results, const char[] error, any data)
	{
		DataPack pack = view_as<DataPack>(data);
		pack.Reset();
		int client = GetClientOfUserId(pack.ReadCell());
		HugsLeaderboardKind kind = view_as<HugsLeaderboardKind>(pack.ReadCell());
		delete pack;

		if (!IsClientIndexValid(client) || !IsClientInGame(client))
		{
			return;
		}

		if (error[0])
		{
			LogError("[Hugs] Failed to load leaderboard: %s", error);
			CPrintToChat(client, "[SM] Failed to load leaderboard.");
			return;
		}

		CPrintToChat(client, (kind == HugsLeaderboard_Hugs) ? "{green}[Hugs Leaderboard]" : "{green}[Rapes Leaderboard]");
		int rank = 1;
		while (results.FetchRow())
		{
			char name[MAX_NAME_LENGTH];
			results.FetchString(0, name, sizeof(name));
			int given = results.FetchInt(1);
			int received = results.FetchInt(2);
			
			char steamid[64];
			results.FetchString(3, steamid, sizeof(steamid));
			
			char wt_name[MAX_NAME_LENGTH];
			results.FetchString(4, wt_name, sizeof(wt_name));

			if (name[0] == '\0' || StrEqual(name, "Unknown"))
			{
				if (wt_name[0] != '\0' && !StrEqual(wt_name, "Unknown"))
				{
					strcopy(name, sizeof(name), wt_name);
				}
				else
				{
					strcopy(name, sizeof(name), "Unknown");
				}
			}

			if (kind == HugsLeaderboard_Hugs)
			{
				CPrintToChat(client, "{default}#%d: {gold}%s {default} Hugs: {gold}%d | Received: {crimson}%d", rank, name, given, received);
			}
			else
			{
				char rankStr[64];
				GetRapeRank(given, rankStr, sizeof(rankStr));
				CPrintToChat(client, "{default}#%d: {gold}%s {default} Rapes: {gold}%d | Received: {crimson}%d {default}| {olive}%s", rank, name, given, received, rankStr);
			}
			rank++;
		}

		if (rank == 1)
		{
			CPrintToChat(client, "{default}No leaderboard entries yet.");
		}
	}

	/* ---------------- Commands ---------------- */

