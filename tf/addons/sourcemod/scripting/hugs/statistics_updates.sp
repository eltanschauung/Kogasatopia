	void UpdateHugStats(int sender, int recipient, bool incrementSender = true)
	{
		if (!EnsureStatsReady(sender, false) || !EnsureStatsReady(recipient, false))
		{
			return;
		}

		int amount = GetEffectiveMultiplier();
		if (incrementSender)
		{
			g_iHugsGiven[sender] += amount;
			SaveClientStats(sender);
		}
		g_iHugsReceived[recipient] += amount;
		SaveClientStats(recipient);
	}

	void UpdateFeedStats(int sender, int recipient, bool incrementSender = true)
	{
		if (!EnsureStatsReady(sender, false) || !EnsureStatsReady(recipient, false))
		{
			return;
		}

		int amount = GetEffectiveMultiplier();
		if (incrementSender)
		{
			g_iFeedsGiven[sender] += amount;
			SaveClientStats(sender);
		}
		g_iFeedsReceived[recipient] += amount;
		SaveClientStats(recipient);
	}

	void UpdateRapeStats(int sender, int recipient, bool incrementSender = true)
	{
		if (!EnsureStatsReady(sender, false) || !EnsureStatsReady(recipient, false))
		{
			return;
		}

		int amount = GetEffectiveMultiplier();
		if (incrementSender)
		{
			g_iRapesGiven[sender] += amount;
			SaveClientStats(sender);
		}
		g_iRapesReceived[recipient] += amount;
		SaveClientStats(recipient);
	}

void UpdateRapeStatsDuel(int sender, int recipient, int score1, int score2)
{
		if (!EnsureStatsReady(sender, false) || !EnsureStatsReady(recipient, false))
		{
			return;
		}

		int amount = GetEffectiveMultiplier();
		g_iRapesGiven[sender] += score1 * amount;
		PrintToChat(sender, "[SM] %i rapes have been credited to your account!", score1 * amount);

	g_iRapesReceived[recipient] += score2 * amount;
	PrintToChat(recipient, "[SM] you just received %i rapes!", score2 * amount);
		
	UpdateLastRapists(recipient, sender);
	SaveClientStats(sender);
	SaveClientStats(recipient);
}

void BuildHuggerHistoryString(int client, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	bool appended = false;

	for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
	{
		if (!g_szLastHuggers[client][i][0])
		{
			continue;
		}

		if (appended)
		{
			StrCat(buffer, maxlen, ", ");
		}

		StrCat(buffer, maxlen, g_szLastHuggers[client][i]);
		appended = true;
	}

	if (!appended)
	{
		strcopy(buffer, maxlen, "None");
	}
}

void BuildFeederHistoryString(int client, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	bool appended = false;

	for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
	{
		if (!g_szLastFeeders[client][i][0])
		{
			continue;
		}

		if (appended)
		{
			StrCat(buffer, maxlen, ", ");
		}

		StrCat(buffer, maxlen, g_szLastFeeders[client][i]);
		appended = true;
	}

	if (!appended)
	{
		strcopy(buffer, maxlen, "None");
	}
}

void BuildRapistHistoryString(int client, char[] buffer, int maxlen)
{
	if (g_szLastRapists[client][0])
	{
		strcopy(buffer, maxlen, g_szLastRapists[client]);
	}
	else
	{
		strcopy(buffer, maxlen, "None");
	}
}

void UpdateLastHuggers(int recipient, const char[] huggerName)
{
	for (int i = MAX_HISTORY_ENTRIES - 1; i > 0; i--)
	{
		strcopy(g_szLastHuggers[recipient][i], MAX_NAME_LENGTH, g_szLastHuggers[recipient][i - 1]);
	}

	strcopy(g_szLastHuggers[recipient][0], MAX_NAME_LENGTH, huggerName);
	SaveClientStats(recipient);
}

void UpdateLastFeeders(int recipient, const char[] feederName)
{
	for (int i = MAX_HISTORY_ENTRIES - 1; i > 0; i--)
	{
		strcopy(g_szLastFeeders[recipient][i], MAX_NAME_LENGTH, g_szLastFeeders[recipient][i - 1]);
	}

	strcopy(g_szLastFeeders[recipient][0], MAX_NAME_LENGTH, feederName);
	SaveClientStats(recipient);
}

void UpdateLastRapists(int recipient, int sender)
{
	char rapistName[MAX_NAME_LENGTH];
	GetClientName(sender, rapistName, sizeof(rapistName));
	UpdateLastRapistsByName(recipient, rapistName);

	// Check for achievement progress from the sender
	checkRapeChievements(sender);
}

void UpdateLastRapistsByName(int recipient, const char[] rapistName)
{
	char rapists[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH];
	int count = ParseHistoryList(g_szLastRapists[recipient], rapists);
	int limit = (count < (MAX_HISTORY_ENTRIES - 1)) ? count : (MAX_HISTORY_ENTRIES - 1);

	for (int i = limit; i > 0; i--)
	{
		strcopy(rapists[i], MAX_NAME_LENGTH, rapists[i - 1]);
	}

	strcopy(rapists[0], MAX_NAME_LENGTH, rapistName);

	int newCount = (count >= MAX_HISTORY_ENTRIES) ? MAX_HISTORY_ENTRIES : count + 1;
	ImplodeStrings(rapists, newCount, ",", g_szLastRapists[recipient], HISTORY_STRING_LEN);
	SaveClientStats(recipient);
}

	int ParseHistoryList(const char[] input, char output[][MAX_NAME_LENGTH])
	{
		for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
		{
			output[i][0] = '\0';
		}

		if (!input[0])
		{
			return 0;
		}

		int count = ExplodeString(input, ",", output, MAX_HISTORY_ENTRIES, MAX_NAME_LENGTH);
		if (count < 0)
		{
			count = MAX_HISTORY_ENTRIES;
		}

		for (int i = 0; i < count; i++)
		{
			TrimString(output[i]);
		}

		return count;
	}


	bool IsSpecialClient(int client)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
			return false;

		char steamID[32];
		if (!Kogasa_GetClientSteam3(client, steamID, sizeof(steamID), true))
			return false;

		if (StrEqual(steamID, "[U:1:1605262060]") || StrEqual(steamID, "[U:1:360445377]"))
		{
			return true;
		}

		return false;
	}

