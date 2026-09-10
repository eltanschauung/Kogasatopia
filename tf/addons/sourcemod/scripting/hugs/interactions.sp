	public Action Command_Hug(int client, int args)
	{
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: !hug <name>");
			return Plugin_Handled;
		}

		if (IsSpecialClient(client))
		{
			return Plugin_Handled;
		}

		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		float currentTime = GetGameTime();
		float remaining = 0.0;
		if (IsCooldownBlocked(g_fLastHugTime[client], currentTime, remaining))
		{
			ReplyToCommand(client, "[SM] You must wait %.1f seconds before hugging again.", remaining);
			return Plugin_Handled;
		}

		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
					arg1,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int successCount = 0;
		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));

		bool isGroupTarget = IsGroupTargetArg(arg1);

		for (int i = 0; i < target_count; i++)
		{
			int target = target_list[i];
			if (target == client) continue;

			if (!EnsureStatsReady(target, false))
			{
				continue;
			}

			char targetNameDisplay[MAX_NAME_LENGTH];
			GetClientName(target, targetNameDisplay, sizeof(targetNameDisplay));

			// Send message to the recipient unless they are redlisted
			if (!IsClientRedlisted(target))
			{
				PrintToChat(target, "\x01[SM] \x04%s \x01hugged you!", clientName);
			}

			// Send message to the sender
			PrintToChat(client, "\x01[SM] You hugged \x04%s\x01!", targetNameDisplay);

			// Update hug stats
			// If it's a group target, we don't increment per target here
			UpdateHugStats(client, target, !isGroupTarget);

			// Update last huggers list
			UpdateLastHuggers(target, clientName);
			
			successCount++;
		}

		if (isGroupTarget && successCount > 0)
		{
			int amount = GetEffectiveMultiplier();
			g_iHugsGiven[client] += amount;
			SaveClientStats(client);
		}

		if (successCount > 0)
		{
			PrintToChat(client, "\x01[SM] Use !hugs to check your stats.");
			g_fLastHugTime[client] = currentTime;
		}

		return Plugin_Handled;
	}

	public Action Command_Feed(int client, int args)
	{
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: !feed <name>");
			return Plugin_Handled;
		}

		if (IsSpecialClient(client))
		{
			return Plugin_Handled;
		}

		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		float currentTime = GetGameTime();
		float remaining = 0.0;
		if (IsCooldownBlocked(g_fLastHugTime[client], currentTime, remaining))
		{
			ReplyToCommand(client, "[SM] You must wait %.1f seconds before feeding again.", remaining);
			return Plugin_Handled;
		}

		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
					arg1,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int successCount = 0;
		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));

		bool isGroupTarget = IsGroupTargetArg(arg1);

		for (int i = 0; i < target_count; i++)
		{
			int target = target_list[i];
			if (target == client) continue;

			if (!EnsureStatsReady(target, false))
			{
				continue;
			}

			char targetNameDisplay[MAX_NAME_LENGTH];
			GetClientName(target, targetNameDisplay, sizeof(targetNameDisplay));

			// Send message to the recipient unless they are redlisted
			if (!IsClientRedlisted(target))
			{
				PrintToChat(target, "\x01[SM] \x04%s \x01fed you!", clientName);
			}

			// Send message to the sender
			PrintToChat(client, "\x01[SM] You fed \x04%s\x01!", targetNameDisplay);

			// Update feed stats
			// If it's a group target, we don't increment per target here
			UpdateFeedStats(client, target, !isGroupTarget);

			// Update last feeders list
			UpdateLastFeeders(target, clientName);

			successCount++;
		}

		if (isGroupTarget && successCount > 0)
		{
			int amount = GetEffectiveMultiplier();
			g_iFeedsGiven[client] += amount;
			SaveClientStats(client);
		}

		if (successCount > 0)
		{
			PrintToChat(client, "\x01[SM] Use !feeds to check your stats.");
			g_fLastHugTime[client] = currentTime;
		}

		return Plugin_Handled;
	}

	public Action Command_Rape(int client, int args)
	{
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: !rape <name>");
			return Plugin_Handled;
		}

		if (IsSpecialClient(client))
		{
			return Plugin_Handled;
		}

		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		float currentTime = GetGameTime();
		float remaining = 0.0;
		if (IsCooldownBlocked(g_fLastRapeTime[client], currentTime, remaining))
		{ 
			ReplyToCommand(client, "[SM] You must wait %.1f seconds before raping again.", remaining);
			return Plugin_Handled;
		}

		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
					arg1,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int successCount = 0;
		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));

		bool isGroupTarget = IsGroupTargetArg(arg1);

		for (int i = 0; i < target_count; i++)
		{
			int target = target_list[i];
			if (target == client) continue;

			if (IsRapeProtected(target))
			{
				CPrintToChat(client, "{green}[Hugs]{default} %N is currently protected from rape.", target);
				continue;
			}

			if (!EnsureStatsReady(target, false))
			{
				continue;
			}

			char targetNameDisplay[MAX_NAME_LENGTH];
			GetClientName(target, targetNameDisplay, sizeof(targetNameDisplay));

			// Send message to the recipient unless they are redlisted
			if (!IsClientRedlisted(target))
			{
				PrintToChat(target, "\x01[SM] \x04%s \x01raped you!", clientName);
			}

			// Send message to the sender
			PrintToChat(client, "\x01[SM] You raped \x04%s\x01!", targetNameDisplay);

			// Update rape stats
			// If it's a group target, we don't increment per target here
			UpdateRapeStats(client, target, !isGroupTarget);

			// Update last rapists list
			UpdateLastRapists(target, client);
			
			successCount++;
		}

		if (isGroupTarget && successCount > 0)
		{
			int amount = GetEffectiveMultiplier();
			g_iRapesGiven[client] += amount;
			SaveClientStats(client);
		}

		if (successCount > 0)
		{
			PrintToChat(client, "\x01[SM] Use !rapes to check your stats.");
			g_fLastRapeTime[client] = currentTime;
		}

		return Plugin_Handled;
	}

	public Action Command_CheckHugs(int client, int args)
	{
		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		char lastHuggers[HISTORY_STRING_LEN];
		BuildHuggerHistoryString(client, lastHuggers, sizeof(lastHuggers));

		PrintToChat(client, "\x01[SM] Hugs Received: \x04%d\x01 | Hugs Given: \x04%d", g_iHugsReceived[client], g_iHugsGiven[client]);
		PrintToChat(client, "\x01[SM] Last Huggers: \x04%s", lastHuggers);

		return Plugin_Handled;
	}

	public Action Command_CheckFeeds(int client, int args)
	{
		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		char lastFeeders[HISTORY_STRING_LEN];
		BuildFeederHistoryString(client, lastFeeders, sizeof(lastFeeders));

		PrintToChat(client, "\x01[SM] Feeded: \x04%d\x01 | Fed: \x04%d", g_iFeedsReceived[client], g_iFeedsGiven[client]);
		PrintToChat(client, "\x01[SM] Last Feeders: \x04%s", lastFeeders);

		return Plugin_Handled;
	}

	public Action Command_CheckRapes(int client, int args)
	{
		if (!EnsureStatsReady(client, true))
		{
			return Plugin_Handled;
		}

		char lastRapists[HISTORY_STRING_LEN];
		BuildRapistHistoryString(client, lastRapists, sizeof(lastRapists));
		int count = g_iRapesGiven[client];

		PrintToChat(client, "\x01[SM] Rapes Received: \x04%d\x01 | Rapes Given: \x04%d", g_iRapesReceived[client], g_iRapesGiven[client]);
		PrintToChat(client, "\x01[SM] Last Rapists: \x04%s", lastRapists);
		
		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));

		char rankStr[64];
		GetRapeRank(count, rankStr, sizeof(rankStr));
		PrintToChatAll("%s's rapes have reached a new rank: %s!", name, rankStr);

		return Plugin_Handled;
	}

	public Action Command_Prape(int client, int args)
	{
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: sm_prape <player>");
			return Plugin_Handled;
		}

		if (!IsDatabaseReady())
		{
			ReplyToCommand(client, "[SM] Database not ready.");
			return Plugin_Handled;
		}

		char arg[64];
		GetCmdArg(1, arg, sizeof(arg));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;

		target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			sizeof(target_list),
			COMMAND_FILTER_CONNECTED,
			target_name,
			sizeof(target_name),
			tn_is_ml
		);

		if (target_count <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		for (int i = 0; i < target_count; i++)
		{
			int target = target_list[i];
			if (!IsClientInGame(target) || IsFakeClient(target))
			{
				continue;
			}

			if (!EnsureClientSteamId(target))
			{
				continue;
			}

			char steamEsc[64];
			Db_Escape(g_hDatabase, g_szClientSteamId[target], steamEsc, sizeof(steamEsc), "Hugs");

			char query[256];
			Format(query, sizeof(query),
				"INSERT INTO %s (steamid, rapes_given) VALUES ('%s', 1) ON DUPLICATE KEY UPDATE rapes_given = GREATEST(rapes_given, 1)",
				HUGS_DB_TABLE, steamEsc);
			SQL_TQuery(g_hDatabase, SQL_OnPrapeSaved, query, GetClientUserId(target));

			if (g_bStatsLoaded[target] && g_iRapesGiven[target] < 1)
			{
				g_iRapesGiven[target] = 1;
			}
		}

		if (tn_is_ml)
		{
			ShowActivity2(client, "[SM] ", "Set rapes_given to 1 for %s", target_name);
		}
		else
		{
			ShowActivity2(client, "[SM] ", "Set rapes_given to 1 for %s", target_name);
		}

		return Plugin_Handled;
	}

