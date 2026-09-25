public Action Command_Hats(int client, int args)
{
	if (!Client_IsInGame(client))
	{
		return Plugin_Handled;
	}

	if (!HasEnabledHats())
	{
		ReplyToCommand(client, "[Hats] No hats are available right now.");
		return Plugin_Handled;
	}

	ShowHatMenu(client);
	return Plugin_Handled;
}

int CustomHats_OnGiveNamedItemPost(int client)
{
	if (!Client_IsInGame(client) || g_bHatApplyPending[client])
	{
		return 0;
	}
	if (!g_bHatStateLoaded[client] && AreClientCookiesCached(client))
	{
		LoadHatStateCookie(client);
		g_bHatStateLoaded[client] = true;
	}
	if (!HasEnabledHats())
	{
		return 0;
	}
	if (!HasClientEnabledHats(client))
	{
		return 0;
	}

	g_bHatApplyPending[client] = true;
	return 0;
}

public void CustomHats_EventPostInventory(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!Client_IsInGame(client))
	{
		return;
	}
	if (!g_bHatStateLoaded[client] && AreClientCookiesCached(client))
	{
		LoadHatStateCookie(client);
		g_bHatStateLoaded[client] = true;
	}
	if (TF2_GetPlayerClass(client) == TFClass_Unknown)
	{
		g_bHatApplyPending[client] = false;
		SchedulePostInventoryRefresh(client);
		return;
	}
	bool shouldApply = g_bHatApplyPending[client] || ShouldRefreshHats(client);
	g_bHatApplyPending[client] = false;
	if (!shouldApply)
	{
		SchedulePostInventoryRefresh(client);
		return;
	}
	RequestFrame(ApplyHatFrame, GetClientUserId(client));
	SchedulePostInventoryRefresh(client);
}

static void SchedulePostInventoryRefresh(int client)
{
	if (!HasEnabledHats() || !HasClientEnabledHats(client))
	{
		return;
	}
	g_iPostInventoryRetry[client] = 0;
	g_iPostInventoryUserId[client] = GetClientUserId(client);
	if (g_hPostInventoryTimer[client] != INVALID_HANDLE)
	{
		delete g_hPostInventoryTimer[client];
		g_hPostInventoryTimer[client] = INVALID_HANDLE;
	}
	g_hPostInventoryTimer[client] = CreateTimer(HAT_POSTINVENTORY_DELAY, Timer_PostInventoryRefresh, client);
}

public Action Timer_PostInventoryRefresh(Handle timer, any client)
{
	int index = view_as<int>(client);
	if (index <= 0 || index > MaxClients)
	{
		return Plugin_Stop;
	}
	g_hPostInventoryTimer[index] = INVALID_HANDLE;
	if (!Client_IsInGame(index))
	{
		return Plugin_Stop;
	}
	if (g_iPostInventoryUserId[index] != GetClientUserId(index))
	{
		return Plugin_Stop;
	}
	if (!g_bHatStateLoaded[index] && !AreClientCookiesCached(index))
	{
		return Plugin_Stop;
	}
	if (TF2_GetPlayerClass(index) == TFClass_Unknown)
	{
		if (g_iPostInventoryRetry[index] < HAT_POSTINVENTORY_MAX_RETRIES)
		{
			g_iPostInventoryRetry[index]++;
			g_hPostInventoryTimer[index] = CreateTimer(HAT_POSTINVENTORY_DELAY, Timer_PostInventoryRefresh, index);
		}
		return Plugin_Stop;
	}
	g_iPostInventoryRetry[index] = 0;
	if (CookieMatchesEquippedHats(index))
	{
		return Plugin_Stop;
	}
	if (ShouldRefreshHats(index))
	{
		RequestFrame(ApplyHatFrame, GetClientUserId(index));
	}
	return Plugin_Stop;
}

public void ApplyHatFrame(any userid)
{
	int client = GetClientOfUserId(userid);
	if (!Client_IsInGame(client))
	{
		return;
	}
	UpdateHatForClient(client);
}

void ResetClientHatSelections(int client)
{
	for (int i = 0; i < MAX_HATS; i++)
	{
		g_bHatEnabled[client][i] = false;
		g_iHatPaintChoice[client][i] = 0;
	}
	for (int i = 0; i < g_iHatCount; i++)
	{
		g_iHatPaintChoice[client][i] = ClampPaintIndex(g_Hats[i].defaultPaint);
	}
	RecalculateClientEnabledHatCount(client);
}

void RecalculateClientEnabledHatCount(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}
	int count = 0;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (IsHatEquippedForClient(client, i))
		{
			count++;
		}
	}
	g_iClientEnabledHatCount[client] = count;
}

void RecalculateAllClientEnabledHatCounts()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RecalculateClientEnabledHatCount(i);
	}
}

bool NormalizeClientHatSlots(int client)
{
	bool changed = false;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!g_bHatEnabled[client][i])
		{
			continue;
		}
		for (int j = 0; j < i; j++)
		{
			if (g_bHatEnabled[client][j]
				&& StrEqual(g_Hats[i].slot, g_Hats[j].slot, false))
			{
				g_bHatEnabled[client][i] = false;
				RemoveHatIndex(client, i);
				changed = true;
				break;
			}
		}
	}
	RecalculateClientEnabledHatCount(client);
	return changed;
}

void SetClientHatEnabled(int client, int hatIndex, bool enabled, bool announceConflicts = false)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}
	if (!IsHatIndexValid(hatIndex))
	{
		return;
	}
	if (enabled)
	{
		for (int i = 0; i < g_iHatCount; i++)
		{
			if (i == hatIndex || !g_bHatEnabled[client][i]
				|| !StrEqual(g_Hats[i].slot, g_Hats[hatIndex].slot, false))
			{
				continue;
			}

			g_bHatEnabled[client][i] = false;
			RemoveHatIndex(client, i);
			if (announceConflicts && Client_IsInGame(client))
			{
				char color[32];
				GetHatChatColorForClientTeam(client, i, color, sizeof(color));
				CPrintToChat(client,
					"{gold}[CustomHats]{default} {%s}%s{default} was uneqipped due to sharing slot '%s'.",
					color, g_Hats[i].name, g_Hats[i].slot);
			}
		}
	}
	if (g_bHatEnabled[client][hatIndex] == enabled)
	{
		RecalculateClientEnabledHatCount(client);
		return;
	}
	g_bHatEnabled[client][hatIndex] = enabled;
	RecalculateClientEnabledHatCount(client);
}

bool HasClientEnabledHats(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return false;
	}
	return g_iClientEnabledHatCount[client] > 0;
}

bool TryParseNonNegativeInt(const char[] text, int &value)
{
	if (!text[0])
	{
		return false;
	}
	value = StringToInt(text);
	if (value == 0 && !StrEqual(text, "0"))
	{
		return false;
	}
	return value >= 0;
}

void UpdateHatForClient(int client)
{
	if (!HasEnabledHats() || !HasClientEnabledHats(client))
	{
		RemoveHat(client, -1);
		return;
	}

	if (GetClientTeam(client) <= 1)
	{
		RemoveHat(client, -1);
		return;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown)
	{
		return;
	}
	int classIndex = view_as<int>(playerClass);
	for (int i = 0; i < g_iHatCount; i++)
	{
		bool enabled = IsHatEquippedForClient(client, i)
			&& CanClientUseHatForClass(client, i, playerClass);
		if (!enabled)
		{
			RemoveHatIndex(client, i);
			continue;
		}

		bool hatValid = CustomHats_HasValidEntRef(g_iHatRef[client][i]);
		bool hideValid = CustomHats_HasValidEntRef(g_iHideHatRef[client][i]);
		bool shouldHaveHide = (GetHideDefIndexForClass(i, classIndex) > 0);
		if (hatValid && ((shouldHaveHide && hideValid) || (!shouldHaveHide && !hideValid)))
		{
			continue;
		}

		EquipHat(client, i);
	}
}

bool CustomHats_HasValidEntRef(int entRef)
{
	int ent = EntRefToEntIndex(entRef);
	return ent != INVALID_ENT_REFERENCE;
}

static bool ShouldRefreshHats(int client)
{
	if (!HasEnabledHats() || !HasClientEnabledHats(client))
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	int classIndex = view_as<int>(playerClass);
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEquippedForClient(client, i))
		{
			continue;
		}

		bool allowed = CanClientUseHatForClass(client, i, playerClass);
		bool hatValid = CustomHats_HasValidEntRef(g_iHatRef[client][i]);
		bool hideValid = CustomHats_HasValidEntRef(g_iHideHatRef[client][i]);
		bool shouldHaveHide = allowed && (GetHideDefIndexForClass(i, classIndex) > 0);

		if (allowed && !hatValid)
		{
			return true;
		}
		if (!allowed && hatValid)
		{
			return true;
		}
		if (shouldHaveHide && !hideValid)
		{
			return true;
		}
		if (!shouldHaveHide && hideValid)
		{
			return true;
		}
	}

	return false;
}

static bool CookieMatchesEquippedHats(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return true;
	}
	if (!g_bHatStateLoaded[client])
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown)
	{
		return false;
	}
	int classIndex = view_as<int>(playerClass);
	for (int i = 0; i < g_iHatCount; i++)
	{
		bool enabled = IsHatEquippedForClient(client, i)
			&& CanClientUseHatForClass(client, i, playerClass);
		bool hatValid = CustomHats_HasValidEntRef(g_iHatRef[client][i]);
		bool hideValid = CustomHats_HasValidEntRef(g_iHideHatRef[client][i]);
		bool shouldHaveHide = enabled && (GetHideDefIndexForClass(i, classIndex) > 0);

		if (enabled && !hatValid)
		{
			return false;
		}
		if (!enabled && hatValid)
		{
			return false;
		}
		if (shouldHaveHide && !hideValid)
		{
			return false;
		}
		if (!shouldHaveHide && hideValid)
		{
			return false;
		}
	}

	return true;
}

