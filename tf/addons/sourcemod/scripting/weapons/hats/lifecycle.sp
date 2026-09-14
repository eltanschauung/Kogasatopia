void CustomHats_RegisterNatives()
{
	RegPluginLibrary("custom_hats");
	CreateNative("CustomHats_GetPrefix", Native_CustomHats_GetPrefix);
	CreateNative("CustomHats_GetTagChoices", Native_CustomHats_GetTagChoices);
	CreateNative("CustomHats_ResolveTag", Native_CustomHats_ResolveTag);
	CreateNative("CustomHats_FindTagSource", Native_CustomHats_FindTagSource);
}

void CustomHats_OnPluginStart()
{
	HookEvent("post_inventory_application", CustomHats_EventPostInventory, EventHookMode_Post);
	RegConsoleCmd("sm_hats", Command_Hats, "Open the custom hats menu");
	RegConsoleCmd("sm_hat", Command_Hats, "Open the custom hats menu");
	RegConsoleCmd("sm_wear", Command_Hats, "Open the custom hats menu");
	g_hHatStateCookie = RegClientCookie("custom_hats_state", "Custom hats state (hat,paint,hat,paint)", CookieAccess_Public);
	g_hHatDebug = CreateConVar("sm_custom_hats_debug", "0", "Enable custom hats debug logging (0/1).", FCVAR_NONE, true, 0.0, true, 1.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 0; j < MAX_HATS; j++)
		{
			g_bHatEnabled[i][j] = false;
			g_iHatRef[i][j] = INVALID_ENT_REFERENCE;
			g_iHideHatRef[i][j] = INVALID_ENT_REFERENCE;
			g_iHatPaintChoice[i][j] = 0;
		}
		g_szHatIdChoice[i][0] = '\0';
		g_bHatApplyPending[i] = false;
		g_bHatStateLoaded[i] = false;
		g_bHatStatePending[i] = false;
		g_bHatStatePendingAllowClear[i] = false;
		g_hPostInventoryTimer[i] = INVALID_HANDLE;
		g_iPostInventoryUserId[i] = 0;
		g_iPostInventoryRetry[i] = 0;
		g_hHatSaveTimer[i] = INVALID_HANDLE;
		g_bHatSaveAllowClear[i] = false;
		g_iClientEnabledHatCount[i] = 0;
	}

	LoadConfig();
	RecalculateAllClientEnabledHatCounts();
}

void CustomHats_OnConfigsExecuted()
{
	LoadConfig();
	RecalculateAllClientEnabledHatCounts();
	PrecacheConfiguredHats();
	RefreshAllClientHats();
}

void CustomHats_OnMapStart()
{
	PrecacheConfiguredHats();
}

void CustomHats_OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "points_store"))
	{
		RefreshAllClientHats();
	}
}

void CustomHats_OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "points_store"))
	{
		RefreshAllClientHats();
	}
}

static void RefreshAllClientHats()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			RequestFrame(ApplyHatFrame, GetClientUserId(client));
		}
	}
}

void CustomHats_OnPluginEnd()
{
	RemoveAllHats();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_hPostInventoryTimer[i] != INVALID_HANDLE)
		{
			delete g_hPostInventoryTimer[i];
			g_hPostInventoryTimer[i] = INVALID_HANDLE;
		}
		if (g_hHatSaveTimer[i] != INVALID_HANDLE)
		{
			delete g_hHatSaveTimer[i];
			g_hHatSaveTimer[i] = INVALID_HANDLE;
		}
	}
}

void CustomHats_OnClientPutInServer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}
	for (int i = 0; i < MAX_HATS; i++)
	{
		g_iHatRef[client][i] = INVALID_ENT_REFERENCE;
		g_iHideHatRef[client][i] = INVALID_ENT_REFERENCE;
	}
	g_bHatApplyPending[client] = false;
}

void CustomHats_OnClientConnected(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_hPostInventoryTimer[client] != INVALID_HANDLE)
	{
		delete g_hPostInventoryTimer[client];
		g_hPostInventoryTimer[client] = INVALID_HANDLE;
	}
	if (g_hHatSaveTimer[client] != INVALID_HANDLE)
	{
		delete g_hHatSaveTimer[client];
		g_hHatSaveTimer[client] = INVALID_HANDLE;
	}
	g_iPostInventoryUserId[client] = 0;
	g_iPostInventoryRetry[client] = 0;
	g_bHatSaveAllowClear[client] = false;
	g_iClientEnabledHatCount[client] = 0;
	ResetClientHatSelections(client);
	SetClientDefaultHat(client);
	g_bHatStateLoaded[client] = false;
	g_bHatStatePending[client] = false;
	g_bHatStatePendingAllowClear[client] = false;
}

void CustomHats_OnClientCookiesCached(int client)
{
	if (!Client_IsInGame(client))
	{
		return;
	}

	if (g_hHatDebug != null && g_hHatDebug.BoolValue)
	{
		LogMessage("[CustomHats] Cookies cached for %N (cached=%d).", client, AreClientCookiesCached(client));
	}

	if (g_bHatStatePending[client])
	{
		if (g_hHatDebug != null && g_hHatDebug.BoolValue)
		{
			LogMessage("[CustomHats] Pending cookie save for %N; saving now.", client);
		}
		SaveHatStateCookie(client, g_bHatStatePendingAllowClear[client]);
		g_bHatStateLoaded[client] = true;
		g_bHatStatePending[client] = false;
		g_bHatStatePendingAllowClear[client] = false;
		return;
	}

	LoadHatStateCookie(client);
	g_bHatStateLoaded[client] = true;
	MigrateLegacyHatCookieIfNeeded(client);

	if (IsPlayerAlive(client))
	{
		RequestFrame(ApplyHatFrame, GetClientUserId(client));
	}
}

void CustomHats_OnClientDisconnect(int client)
{
	if (g_hPostInventoryTimer[client] != INVALID_HANDLE)
	{
		delete g_hPostInventoryTimer[client];
		g_hPostInventoryTimer[client] = INVALID_HANDLE;
	}
	g_iPostInventoryUserId[client] = 0;
	g_iPostInventoryRetry[client] = 0;
	FlushHatStateSave(client);
	RemoveHat(client, -1, false);
	ResetClientHatSelections(client);
	SetClientDefaultHat(client);
	g_bHatStateLoaded[client] = false;
	g_bHatStatePending[client] = false;
	g_bHatStatePendingAllowClear[client] = false;
}

