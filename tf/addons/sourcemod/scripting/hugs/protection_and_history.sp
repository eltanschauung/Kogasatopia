	public Action Command_RapeProtect(int client, int args)
	{
		if (!IsHumanClientInGame(client))
		{
			return Plugin_Handled;
		}

		if (args < 1)
		{
			CPrintToChat(client, "{green}[Hugs]{default} Usage: !protect <player>");
			return Plugin_Handled;
		}

		char targetArg[MAX_TARGET_LENGTH];
		GetCmdArg(1, targetArg, sizeof(targetArg));
		int target = FindTarget(client, targetArg, true, false);
		if (target <= 0)
		{
			return Plugin_Handled;
		}

		if (target == client)
		{
			CPrintToChat(client, "{green}[Hugs]{default} You cannot protect yourself.");
			return Plugin_Handled;
		}

		if (IsRapeProtected(target))
		{
			CPrintToChat(client, "{green}[Hugs]{default} %N is already protected.", target);
			return Plugin_Handled;
		}

		BuildHugsChatName(client, g_szRapeProtectorName[target], sizeof(g_szRapeProtectorName[]));
		BuildHugsChatName(target, g_szRapeProtectedName[target], sizeof(g_szRapeProtectedName[]));
		g_iRapeProtectorUserId[target] = GetClientUserId(client);
		float duration = g_hRapeProtectionDuration.FloatValue;
		g_hRapeProtectionTimer[target] = CreateTimer(duration, Timer_RapeProtectionExpired, GetClientSerial(target));

		CPrintToChatAllEx(client, "{green}[Hugs]{default} %s{default} is now protecting %s{default} from rape!", g_szRapeProtectorName[target], g_szRapeProtectedName[target]);
		return Plugin_Handled;
	}

	public Action Timer_RapeProtectionExpired(Handle timer, any targetSerial)
	{
		int target = GetClientFromSerial(targetSerial);
		if (!IsClientIndexValid(target) || g_hRapeProtectionTimer[target] != timer)
		{
			return Plugin_Stop;
		}

		g_hRapeProtectionTimer[target] = null;
		if (IsHumanClientInGame(target))
		{
			CPrintToChatAllEx(target, "{green}[Hugs]{default} %s{default}'s rape protection of %s{default} has now expired!", g_szRapeProtectorName[target], g_szRapeProtectedName[target]);
		}
		g_iRapeProtectorUserId[target] = 0;
		g_szRapeProtectorName[target][0] = '\0';
		g_szRapeProtectedName[target][0] = '\0';
		return Plugin_Stop;
	}

	bool IsRapeProtected(int target)
	{
		return IsClientIndexValid(target)
			&& g_hRapeProtectionTimer[target] != null
			&& g_iRapeProtectorUserId[target] > 0;
	}

	void ClearRapeProtection(int target, bool killTimer)
	{
		if (!IsClientIndexValid(target))
		{
			return;
		}

		if (killTimer && g_hRapeProtectionTimer[target] != null)
		{
			KillTimer(g_hRapeProtectionTimer[target]);
		}
		g_hRapeProtectionTimer[target] = null;
		g_iRapeProtectorUserId[target] = 0;
		g_szRapeProtectorName[target][0] = '\0';
		g_szRapeProtectedName[target][0] = '\0';
	}

	void BuildHugsChatName(int client, char[] buffer, int maxlen)
	{
		if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
			&& Filters_GetChatName(client, buffer, maxlen)
			&& buffer[0])
		{
			return;
		}

		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));
		Format(buffer, maxlen, "{default}%s", name);
	}

	public Action Command_DuelHistory(int client, int args)
	{
		if (!IsHumanClientInGame(client))
		{
			return Plugin_Handled;
		}

		if (!IsDatabaseReady())
		{
			CPrintToChat(client, "{green}[Hugs]{default} The duel history database is not ready.");
			return Plugin_Handled;
		}

		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		char query[384];
		Format(query, sizeof(query),
			"SELECT id, winner_name, loser_name, winner_score, loser_score, finished_at FROM %s ORDER BY finished_at DESC, id DESC LIMIT 25",
			HUGS_DUEL_HISTORY_TABLE);
		SQL_TQuery(g_hDatabase, SQL_OnDuelHistoryLoaded, query, pack);
		return Plugin_Handled;
	}

	public void SQL_OnDuelHistoryLoaded(Database db, DBResultSet results, const char[] error, any data)
	{
		DataPack pack = view_as<DataPack>(data);
		pack.Reset();
		int client = GetClientOfUserId(pack.ReadCell());
		delete pack;
		if (!IsHumanClientInGame(client))
		{
			return;
		}

		if (error[0])
		{
			LogError("[Hugs] Failed to load duel history: %s", error);
			CPrintToChat(client, "{green}[Hugs]{default} Could not load duel history.");
			return;
		}

		Menu menu = new Menu(MenuHandler_DuelHistory);
		menu.SetTitle("Recent Rape Duels");
		int count = 0;
		while (results != null && results.FetchRow())
		{
			int duelId = results.FetchInt(0);
			char winnerName[MAX_NAME_LENGTH], loserName[MAX_NAME_LENGTH];
			char cleanWinner[MAX_NAME_LENGTH], cleanLoser[MAX_NAME_LENGTH];
			char finishedAt[32], info[16], display[192];
			results.FetchString(1, winnerName, sizeof(winnerName));
			results.FetchString(2, loserName, sizeof(loserName));
			int winnerScore = results.FetchInt(3);
			int loserScore = results.FetchInt(4);
			int finishedTimestamp = results.FetchInt(5);

			StripMenuColorTags(winnerName, cleanWinner, sizeof(cleanWinner));
			StripMenuColorTags(loserName, cleanLoser, sizeof(cleanLoser));
			FormatTime(finishedAt, sizeof(finishedAt), "%m/%d %H:%M", finishedTimestamp);
			IntToString(duelId, info, sizeof(info));
			Format(display, sizeof(display), "#%d %s - %s defeated %s (%d-%d)", duelId, finishedAt, cleanWinner, cleanLoser, winnerScore, loserScore);
			menu.AddItem(info, display, ITEMDRAW_DISABLED);
			count++;
		}

		if (count == 0)
		{
			menu.AddItem("none", "No completed duels found.", ITEMDRAW_DISABLED);
		}
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}

	public int MenuHandler_DuelHistory(Menu menu, MenuAction action, int client, int item)
	{
		if (action == MenuAction_End)
		{
			delete menu;
		}
		return 0;
	}

	void StripMenuColorTags(const char[] input, char[] output, int maxlen)
	{
		int out = 0;
		bool inTag = false;
		for (int i = 0; input[i] != '\0' && out < maxlen - 1; i++)
		{
			if (input[i] == '{')
			{
				inTag = true;
				continue;
			}
			if (inTag)
			{
				if (input[i] == '}')
				{
					inTag = false;
				}
				continue;
			}
			output[out++] = input[i];
		}
		output[out] = '\0';
	}

