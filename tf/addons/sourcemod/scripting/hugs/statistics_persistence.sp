void ResetClientStats(int client)
{
	if (!IsClientIndexValid(client))
	{
		return;
	}

	CancelStatsRetryTimer(client);
	g_iHugsReceived[client] = 0;
	g_iHugsGiven[client] = 0;
	g_iFeedsReceived[client] = 0;
	g_iFeedsGiven[client] = 0;
	g_iRapesReceived[client] = 0;
	g_iRapesGiven[client] = 0;
	for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
	{
		g_szLastHuggers[client][i][0] = '\0';
		g_szLastFeeders[client][i][0] = '\0';
	}
	g_szLastRapists[client][0] = '\0';
	g_szClientSteamId[client][0] = '\0';
	g_bStatsLoaded[client] = false;
	g_bStatsPending[client] = false;
}

	bool EnsureStatsReady(int client, bool notify)
	{
		if (!IsHumanClient(client))
		{
			return true;
		}

		if (g_bStatsLoaded[client])
		{
			return true;
		}

		if (notify)
		{
			PrintToChat(client, "[SM] Your hug/rape stats are still loading. Please wait.");
		}

		AttemptLoadClientStats(client);
		return false;
	}

	bool EnsureClientSteamId(int client)
	{
		if (!IsClientIndexValid(client))
		{
			return false;
		}

		if (g_szClientSteamId[client][0])
		{
			return true;
		}

		char auth[32];
		if (!Kogasa_GetClientSteam2(client, auth, sizeof(auth), true))
		{
			return false;
		}

		if (StrEqual(auth, "STEAM_ID_PENDING"))
		{
			return false;
		}

		strcopy(g_szClientSteamId[client], sizeof(g_szClientSteamId[]), auth);
		return true;
	}

	bool IsDatabaseReady()
	{
		return Db_IsReady(g_hDatabase, g_bDatabaseReady);
	}

	void AttemptLoadClientStats(int client)
	{
		if (!IsHumanClient(client))
		{
			return;
		}

		if (g_bStatsLoaded[client] || g_bStatsPending[client])
		{
			return;
		}

		if (!IsDatabaseReady())
		{
			return;
		}

		if (!EnsureClientSteamId(client))
		{
			return;
		}

		char steamEsc[96];
		Db_Escape(g_hDatabase, g_szClientSteamId[client], steamEsc, sizeof(steamEsc), "Hugs");

	char query[768];
	Format(query, sizeof(query), "SELECT hugs_given, hugs_received, feeds_given, feeds_received, rapes_given, rapes_received, last_hugger1, last_hugger2, last_hugger3, last_hugger4, last_hugger5, last_feeder1, last_feeder2, last_feeder3, last_feeder4, last_feeder5, last_rapists FROM %s WHERE steamid = '%s'", HUGS_DB_TABLE, steamEsc);

		g_bStatsPending[client] = true;
		SQL_TQuery(g_hDatabase, SQL_OnStatsLoaded, query, GetClientUserId(client));
	}

	public void SQL_OnStatsLoaded(Database db, DBResultSet results, const char[] error, any data)
	{
		int client = GetClientOfUserId(data);
		if (!IsClientIndexValid(client))
		{
			return;
		}

		g_bStatsPending[client] = false;

		if (!IsClientInGame(client))
		{
			return;
		}

	if (error[0])
	{
		LogError("[Hugs] Failed to load stats: %s", error);
		if (Db_IsTransientError(error))
		{
			ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
		}
		ScheduleStatsRetry(client);
		return;
	}

	int hugsGiven = 0;
	int hugsReceived = 0;
	int feedsGiven = 0;
	int feedsReceived = 0;
	int rapesGiven = 0;
	int rapesReceived = 0;
	char lastRapists[HISTORY_STRING_LEN];

	lastRapists[0] = '\0';

	if (results != null && results.FetchRow())
	{
		hugsGiven = results.FetchInt(0);
		hugsReceived = results.FetchInt(1);
		feedsGiven = results.FetchInt(2);
		feedsReceived = results.FetchInt(3);
		rapesGiven = results.FetchInt(4);
		rapesReceived = results.FetchInt(5);
		for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
		{
			results.FetchString(6 + i, g_szLastHuggers[client][i], MAX_NAME_LENGTH);
			results.FetchString(11 + i, g_szLastFeeders[client][i], MAX_NAME_LENGTH);
		}
		results.FetchString(16, lastRapists, sizeof(lastRapists));
	}
	else
	{
		for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
		{
			g_szLastHuggers[client][i][0] = '\0';
			g_szLastFeeders[client][i][0] = '\0';
		}
	}

	g_iHugsGiven[client] = hugsGiven;
	g_iHugsReceived[client] = hugsReceived;
	g_iFeedsGiven[client] = feedsGiven;
	g_iFeedsReceived[client] = feedsReceived;
	g_iRapesGiven[client] = rapesGiven;
	g_iRapesReceived[client] = rapesReceived;
	strcopy(g_szLastRapists[client], HISTORY_STRING_LEN, lastRapists);
	g_bStatsLoaded[client] = true;
	CancelStatsRetryTimer(client);
}

	void SaveClientStats(int client)
	{
		if (!IsHumanClient(client))
		{
			return;
		}

		if (!g_bStatsLoaded[client])
		{
			return;
		}

		if (!IsDatabaseReady())
		{
			return;
		}

		if (!EnsureClientSteamId(client))
		{
			return;
		}

		char steamEsc[96];
		Db_Escape(g_hDatabase, g_szClientSteamId[client], steamEsc, sizeof(steamEsc), "Hugs");

		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));
		char nameEsc[MAX_NAME_LENGTH * 2 + 1];
		Db_Escape(g_hDatabase, name, nameEsc, sizeof(nameEsc), "Hugs");

	char rapistsEsc[HISTORY_STRING_LEN * 2 + 1];
	char huggerEscaped[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH * 2 + 1];
	char feederEscaped[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH * 2 + 1];
	for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
	{
		Db_Escape(g_hDatabase, g_szLastHuggers[client][i], huggerEscaped[i], sizeof(huggerEscaped[]), "Hugs");
		Db_Escape(g_hDatabase, g_szLastFeeders[client][i], feederEscaped[i], sizeof(feederEscaped[]), "Hugs");
	}
	Db_Escape(g_hDatabase, g_szLastRapists[client], rapistsEsc, sizeof(rapistsEsc), "Hugs");

    char query[3072];
    Format(query, sizeof(query), "REPLACE INTO %s (steamid, name, hugs_given, hugs_received, feeds_given, feeds_received, rapes_given, rapes_received, last_hugger1, last_hugger2, last_hugger3, last_hugger4, last_hugger5, last_feeder1, last_feeder2, last_feeder3, last_feeder4, last_feeder5, last_rapists) VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')",
        HUGS_DB_TABLE, steamEsc, nameEsc, g_iHugsGiven[client], g_iHugsReceived[client], g_iFeedsGiven[client], g_iFeedsReceived[client], g_iRapesGiven[client], g_iRapesReceived[client],
        huggerEscaped[0], huggerEscaped[1], huggerEscaped[2], huggerEscaped[3], huggerEscaped[4],
        feederEscaped[0], feederEscaped[1], feederEscaped[2], feederEscaped[3], feederEscaped[4], rapistsEsc);

		SQL_TQuery(g_hDatabase, SQL_OnStatsSaved, query);
	}

	public void SQL_OnStatsSaved(Database db, DBResultSet results, const char[] error, any data)
	{
		if (error[0])
		{
			LogError("[Hugs] Failed to save stats: %s", error);
			if (Db_IsTransientError(error))
			{
				ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
			}
		}
	}

	public void SQL_OnPrapeSaved(Database db, DBResultSet results, const char[] error, any data)
	{
		if (error[0])
		{
			LogError("[Hugs] Failed to update rapes_given: %s", error);
			if (Db_IsTransientError(error))
			{
				ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
			}
		}
	}

