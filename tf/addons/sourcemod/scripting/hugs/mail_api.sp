	public any Native_Hugs_GetRapesGiven(Handle plugin, int numParams)
	{
		int client = GetNativeCell(1);
		if (!IsClientIndexValid(client))
		{
			return 0;
		}
		return g_iRapesGiven[client];
	}

	public any Native_Hugs_AreStatsLoaded(Handle plugin, int numParams)
	{
		int client = GetNativeCell(1);
		return IsClientIndexValid(client) && g_bStatsLoaded[client];
	}

	public any Native_Hugs_RedeemMailedHug(Handle plugin, int numParams)
	{
		return Native_RedeemMailedInteraction(false, false);
	}

	public any Native_Hugs_RedeemMailedFeed(Handle plugin, int numParams)
	{
		return Native_RedeemMailedInteraction(false, true);
	}

	public any Native_Hugs_RedeemMailedRape(Handle plugin, int numParams)
	{
		return Native_RedeemMailedInteraction(true, false);
	}

	public any Native_Hugs_AnnounceMailedInteraction(Handle plugin, int numParams)
	{
		int receiver = GetNativeCell(1);
		char senderSteamId64[KOGASA_STEAMID_MAX];
		char senderName[MAX_NAME_LENGTH];
		char interactionType[16];
		GetNativeString(2, senderSteamId64, sizeof(senderSteamId64));
		GetNativeString(3, senderName, sizeof(senderName));
		GetNativeString(4, interactionType, sizeof(interactionType));

		if (!IsHumanClient(receiver) || !Kogasa_IsSteamId64(senderSteamId64))
		{
			return false;
		}

		bool rape = StrEqual(interactionType, "rape");
		bool feed = StrEqual(interactionType, "feed");
		if (!rape && !feed && !StrEqual(interactionType, "hug"))
		{
			return false;
		}

		int sender = Kogasa_FindClientBySteamId64(senderSteamId64);
		AnnounceMailedInteraction(sender, receiver, senderSteamId64, senderName, rape, feed);
		return true;
	}

	bool Native_RedeemMailedInteraction(bool rape, bool feed)
	{
		char senderSteamId64[KOGASA_STEAMID_MAX];
		char receiverSteamId64[KOGASA_STEAMID_MAX];
		char senderName[MAX_NAME_LENGTH];
		GetNativeString(1, senderSteamId64, sizeof(senderSteamId64));
		GetNativeString(2, receiverSteamId64, sizeof(receiverSteamId64));
		GetNativeString(3, senderName, sizeof(senderName));
		return ApplyMailedInteraction(senderSteamId64, receiverSteamId64, senderName, rape, feed);
	}

	bool ApplyMailedInteraction(
		const char[] senderSteamId64,
		const char[] receiverSteamId64,
		const char[] senderName,
		bool rape,
		bool feed)
	{
		if (!IsDatabaseReady() || senderName[0] == '\0'
			|| !Kogasa_IsSteamId64(senderSteamId64)
			|| !Kogasa_IsSteamId64(receiverSteamId64)
			|| StrEqual(senderSteamId64, receiverSteamId64, false))
		{
			return false;
		}

		int receiver = Kogasa_FindClientBySteamId64(receiverSteamId64);
		if (!IsHumanClient(receiver) || !EnsureStatsReady(receiver, false))
		{
			return false;
		}
		if (rape && IsRapeProtected(receiver))
		{
			CPrintToChat(receiver, "{green}[Hugs]{default} Your rape protection blocked that mailed interaction.");
			return false;
		}

		int sender = Kogasa_FindClientBySteamId64(senderSteamId64);
		if (sender > 0 && !EnsureStatsReady(sender, false))
		{
			return false;
		}

		int amount = GetEffectiveMultiplier();
		if (sender > 0)
		{
			if (rape)
			{
				g_iRapesGiven[sender] += amount;
			}
			else if (feed)
			{
				g_iFeedsGiven[sender] += amount;
			}
			else
			{
				g_iHugsGiven[sender] += amount;
			}
			SaveClientStats(sender);
		}
		else if (!CreditOfflineMailedInteraction(senderSteamId64, senderName, rape, feed, amount))
		{
			return false;
		}

		if (rape)
		{
			g_iRapesReceived[receiver] += amount;
			UpdateLastRapistsByName(receiver, senderName);
			if (sender > 0)
			{
				checkRapeChievements(sender);
			}
		}
		else if (feed)
		{
			g_iFeedsReceived[receiver] += amount;
			UpdateLastFeeders(receiver, senderName);
		}
		else
		{
			g_iHugsReceived[receiver] += amount;
			UpdateLastHuggers(receiver, senderName);
		}
		SaveClientStats(receiver);
		AnnounceMailedInteraction(sender, receiver, senderSteamId64, senderName, rape, feed);
		return true;
	}

	void AnnounceMailedInteraction(
		int sender,
		int receiver,
		const char[] senderSteamId64,
		const char[] senderName,
		bool rape,
		bool feed)
	{
		char senderDisplay[256];
		BuildMailedHugsChatName(sender, senderSteamId64, senderName, senderDisplay, sizeof(senderDisplay));

		char receiverDisplay[256];
		BuildHugsChatName(receiver, receiverDisplay, sizeof(receiverDisplay));
		char action[16];
		strcopy(action, sizeof(action), rape ? "raped" : (feed ? "fed" : "hugged"));

		if (!IsClientRedlisted(receiver))
		{
			CPrintToChatEx(receiver, sender > 0 ? sender : receiver,
				"{green}[Hugs] %s{default} %s you!", senderDisplay, action);
		}
		if (sender > 0)
		{
			CPrintToChatEx(sender, receiver,
				"{green}[Hugs]{default} You %s %s{default}!", action, receiverDisplay);
		}
	}

	void BuildMailedHugsChatName(
		int client,
		const char[] steamId64,
		const char[] fallbackName,
		char[] buffer,
		int maxlen)
	{
		if (client > 0)
		{
			BuildHugsChatName(client, buffer, maxlen);
			return;
		}
		if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdChatName") == FeatureStatus_Available
			&& Filters_GetSteamIdChatName(steamId64, fallbackName, buffer, maxlen)
			&& buffer[0])
		{
			return;
		}

		char colorTag[32];
		colorTag[0] = '\0';
		if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") == FeatureStatus_Available)
		{
			Filters_GetSteamIdColorTag(steamId64, colorTag, sizeof(colorTag));
		}
		if (!colorTag[0])
		{
			strcopy(colorTag, sizeof(colorTag), "{green}");
		}
		Format(buffer, maxlen, "%s%s", colorTag, fallbackName);
	}

	bool CreditOfflineMailedInteraction(
		const char[] senderSteamId64,
		const char[] senderName,
		bool rape,
		bool feed,
		int amount)
	{
		char senderSteam2[KOGASA_STEAMID_MAX];
		if (!Kogasa_ConvertSteamId64ToSteam2(senderSteamId64, senderSteam2, sizeof(senderSteam2)))
		{
			return false;
		}

		char steamEsc[96];
		char nameEsc[(MAX_NAME_LENGTH * 2) + 1];
		if (!Db_Escape(g_hDatabase, senderSteam2, steamEsc, sizeof(steamEsc), "Hugs")
			|| !Db_Escape(g_hDatabase, senderName, nameEsc, sizeof(nameEsc), "Hugs"))
		{
			return false;
		}

		char column[32];
		strcopy(column, sizeof(column), rape ? "rapes_given" : (feed ? "feeds_given" : "hugs_given"));
		char query[768];
		FormatEx(query, sizeof(query),
			"INSERT INTO %s (steamid, name, %s) VALUES ('%s', '%s', %d) "
			... "ON DUPLICATE KEY UPDATE name = VALUES(name), %s = %s + %d",
			HUGS_DB_TABLE, column, steamEsc, nameEsc, amount, column, column, amount);
		SQL_TQuery(g_hDatabase, SQL_OnMailedInteractionSaved, query);
		return true;
	}

	public void SQL_OnMailedInteractionSaved(Database db, DBResultSet results, const char[] error, any data)
	{
		if (error[0] != '\0')
		{
			LogError("[Hugs] Failed to credit mailed interaction: %s", error);
		}
	}

	// Cooldown variables
	float g_fLastHugTime[MAXPLAYERS + 1];
	float g_fLastRapeTime[MAXPLAYERS + 1];
	const float COOLDOWN_TIME = 8.0; // 8-second cooldown

	// --- State ---
	bool g_bDuelRequested = false;
	bool g_bDuelActive    = false;
	int  g_iRequester     = 0;
	int  g_iTarget        = 0;
	int  g_iScoreReq      = 0;
	int  g_iScoreTgt      = 0;
	char g_szDuelSteamIds[2][32];
	char g_szDuelNames[2][MAX_NAME_LENGTH];

	Handle g_hRequestTimer = null;

	// --- ConVars ---
	ConVar g_hTargetScore;
	ConVar g_hRequestTimeout;
	ConVar g_hRapeProtectionDuration;
	Handle g_hRapeProtectionTimer[MAXPLAYERS + 1];
	int g_iRapeProtectorUserId[MAXPLAYERS + 1];
	char g_szRapeProtectorName[MAXPLAYERS + 1][MAX_NAME_LENGTH + 32];
	char g_szRapeProtectedName[MAXPLAYERS + 1][MAX_NAME_LENGTH + 32];

