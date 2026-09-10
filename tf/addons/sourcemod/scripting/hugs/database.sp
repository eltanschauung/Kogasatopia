	void ConnectToDatabase()
	{
		Db_CancelTimer(g_hDbReconnectTimer);
		Db_Close(g_hDatabase, g_bDatabaseReady);

		if (!Db_CheckConfigOrLog("Hugs", HUGS_DB_CONFIG))
		{
			return;
		}

		SQL_TConnect(SQL_OnDatabaseConnected, HUGS_DB_CONFIG);
	}

	public Action Timer_ReconnectDatabase(Handle timer, any data)
	{
		g_hDbReconnectTimer = null;
		ConnectToDatabase();
		return Plugin_Stop;
	}

	void ScheduleDatabaseReconnect(float delay = DB_RECONNECT_DELAY)
	{
		g_bDatabaseReady = false;
		if (g_hDbReconnectTimer == null)
		{
			g_hDbReconnectTimer = CreateTimer(delay, Timer_ReconnectDatabase, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	public void SQL_OnDatabaseConnected(Handle owner, Handle hndl, const char[] error, any data)
	{
		if (hndl == null)
		{
			LogError("[Hugs] Failed to connect to database: %s", error[0] ? error : "unknown error");
			ScheduleDatabaseReconnect();
			return;
		}

		g_hDatabase = view_as<Database>(hndl);
		g_bDatabaseReady = true;
		Db_CancelTimer(g_hDbReconnectTimer);
		EnsureStatsTable();
	}

	void EnsureStatsTable()
	{
		if (!IsDatabaseReady())
		{
			return;
		}

		g_iSchemaOpsPending = 0;

		char query[2048];
		Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS %s (steamid VARCHAR(64) PRIMARY KEY, name VARCHAR(%d) NOT NULL DEFAULT '', hugs_given INTEGER NOT NULL DEFAULT 0, hugs_received INTEGER NOT NULL DEFAULT 0, feeds_given INTEGER NOT NULL DEFAULT 0, feeds_received INTEGER NOT NULL DEFAULT 0, rapes_given INTEGER NOT NULL DEFAULT 0, rapes_received INTEGER NOT NULL DEFAULT 0, last_hugger1 VARCHAR(%d) NOT NULL DEFAULT '', last_hugger2 VARCHAR(%d) NOT NULL DEFAULT '', last_hugger3 VARCHAR(%d) NOT NULL DEFAULT '', last_hugger4 VARCHAR(%d) NOT NULL DEFAULT '', last_hugger5 VARCHAR(%d) NOT NULL DEFAULT '', last_feeder1 VARCHAR(%d) NOT NULL DEFAULT '', last_feeder2 VARCHAR(%d) NOT NULL DEFAULT '', last_feeder3 VARCHAR(%d) NOT NULL DEFAULT '', last_feeder4 VARCHAR(%d) NOT NULL DEFAULT '', last_feeder5 VARCHAR(%d) NOT NULL DEFAULT '', last_rapists VARCHAR(%d) NOT NULL DEFAULT '')",
			HUGS_DB_TABLE, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, MAX_NAME_LENGTH, HISTORY_STRING_LEN);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		// Add name column if it doesn't exist (for existing tables)
		Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS name VARCHAR(%d) NOT NULL DEFAULT ''", HUGS_DB_TABLE, MAX_NAME_LENGTH);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS feeds_given INTEGER NOT NULL DEFAULT 0", HUGS_DB_TABLE);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS feeds_received INTEGER NOT NULL DEFAULT 0", HUGS_DB_TABLE);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS last_rapists VARCHAR(%d) NOT NULL DEFAULT ''", HUGS_DB_TABLE, HISTORY_STRING_LEN);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		Format(query, sizeof(query),
			"CREATE TABLE IF NOT EXISTS %s (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, winner_steamid64 VARCHAR(32) NOT NULL, winner_name VARCHAR(%d) NOT NULL DEFAULT '', loser_steamid64 VARCHAR(32) NOT NULL, loser_name VARCHAR(%d) NOT NULL DEFAULT '', winner_score INT NOT NULL DEFAULT 0, loser_score INT NOT NULL DEFAULT 0, result_type VARCHAR(32) NOT NULL DEFAULT '', finished_at INT NOT NULL, PRIMARY KEY (id), KEY idx_hugs_duel_finished (finished_at), KEY idx_hugs_duel_winner (winner_steamid64)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
			HUGS_DUEL_HISTORY_TABLE,
			MAX_NAME_LENGTH,
			MAX_NAME_LENGTH);
		g_iSchemaOpsPending++;
		SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

		static const char g_LastHuggerColumns[MAX_HISTORY_ENTRIES][16] =
		{
			"last_hugger1",
			"last_hugger2",
			"last_hugger3",
			"last_hugger4",
			"last_hugger5"
		};

		static const char g_LastFeederColumns[MAX_HISTORY_ENTRIES][16] =
		{
			"last_feeder1",
			"last_feeder2",
			"last_feeder3",
			"last_feeder4",
			"last_feeder5"
		};

		for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
		{
			Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s VARCHAR(%d) NOT NULL DEFAULT ''", HUGS_DB_TABLE, g_LastHuggerColumns[i], MAX_NAME_LENGTH);
			g_iSchemaOpsPending++;
			SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);

			Format(query, sizeof(query), "ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s VARCHAR(%d) NOT NULL DEFAULT ''", HUGS_DB_TABLE, g_LastFeederColumns[i], MAX_NAME_LENGTH);
			g_iSchemaOpsPending++;
			SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);
		}
	}

	void RequestStatsReload()
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && !IsFakeClient(i))
			{
				AttemptLoadClientStats(i);
			}
		}
	}

	public void SQL_OnSchemaOpComplete(Database db, DBResultSet results, const char[] error, any data)
	{
		if (error[0])
		{
			LogError("[Hugs] SQL error: %s", error);
			if (Db_IsTransientError(error))
			{
				ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
			}
		}

		if (g_iSchemaOpsPending > 0)
		{
			g_iSchemaOpsPending--;
		}

		if (g_iSchemaOpsPending == 0)
		{
			RequestStatsReload();
		}
	}
