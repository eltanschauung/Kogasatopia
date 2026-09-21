static void LoadStableHatStateChunk(int client, const char[] stateValue)
{
	char entries[32][96];
	int entryCount = ExplodeString(stateValue, ",", entries, sizeof(entries), sizeof(entries[]));
	for (int i = 0; i < entryCount; i++)
	{
		TrimString(entries[i]);
		if (!entries[i][0])
		{
			continue;
		}

		char entryParts[2][64];
		int partCount = ExplodeString(entries[i], ":", entryParts, sizeof(entryParts), sizeof(entryParts[]));
		if (partCount <= 0 || !entryParts[0][0])
		{
			continue;
		}

		int hatIndex = FindHatIndexById(entryParts[0]);
		if (!IsHatEnabled(hatIndex))
		{
			continue;
		}
		g_bHatEnabled[client][hatIndex] = true;
		if (partCount > 1 && entryParts[1][0])
		{
			g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(StringToInt(entryParts[1]));
		}
		if (!g_Hats[hatIndex].paintable)
		{
			g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(g_Hats[hatIndex].defaultPaint);
		}

		if (!g_szHatIdChoice[client][0])
		{
			strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), g_Hats[hatIndex].id);
		}
	}
}

void LoadHatStateCookie(int client)
{
	ResetClientHatSelections(client);
	g_szHatIdChoice[client][0] = '\0';
	g_iHatCookieChunksUsed[client] = 0;

	if (g_hHatStateCookies[0] == INVALID_HANDLE || !AreClientCookiesCached(client))
	{
		SetClientDefaultHat(client);
		return;
	}

	char stateValue[HAT_COOKIE_VALUE_LEN];
	GetClientCookie(client, g_hHatStateCookies[0], stateValue, sizeof(stateValue));
	if (!stateValue[0])
	{
		SetClientDefaultHat(client);
		return;
	}
	g_iHatCookieChunksUsed[client] = 1;

	if (g_hHatDebug != null && g_hHatDebug.BoolValue)
	{
		LogMessage("[CustomHats] Load cookie for %N: \"%s\"", client, stateValue);
	}

	bool needsResave = false;
	if (StrContains(stateValue, "|") != -1)
	{
		char parts[3][64];
		int count = ExplodeString(stateValue, "|", parts, sizeof(parts), sizeof(parts[]));
		if (count > 1 && parts[1][0] != '\0' && StringToInt(parts[0]) != 0)
		{
			int hatIndex = FindHatIndexById(parts[1]);
			if (IsHatEnabled(hatIndex))
			{
				g_bHatEnabled[client][hatIndex] = true;
				if (count > 2)
				{
					g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(StringToInt(parts[2]));
				}
				if (!g_Hats[hatIndex].paintable)
				{
					g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(g_Hats[hatIndex].defaultPaint);
				}
				strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), parts[1]);
			}
		}
		// The pipe format used a stable id, but is rewritten once into the
		// canonical comma-separated id:paint format.
		needsResave = true;
		if (!g_szHatIdChoice[client][0])
		{
			SetClientDefaultHat(client);
		}
		RecalculateClientEnabledHatCount(client);
		if (needsResave)
		{
			SaveHatStateCookie(client);
		}
		return;
	}

	if (StrContains(stateValue, ":") != -1)
	{
		LoadStableHatStateChunk(client, stateValue);
		for (int chunk = 1; chunk < MAX_HATS; chunk++)
		{
			if (g_hHatStateCookies[chunk] == INVALID_HANDLE)
			{
				continue;
			}
			char chunkValue[HAT_COOKIE_VALUE_LEN];
			GetClientCookie(client, g_hHatStateCookies[chunk], chunkValue, sizeof(chunkValue));
			if (!chunkValue[0])
			{
				continue;
			}
			LoadStableHatStateChunk(client, chunkValue);
			g_iHatCookieChunksUsed[client] = chunk + 1;
		}
	}
	else
	{
		// Numeric hat indices are configuration-order dependent. Resolve them
		// against the current config once, then immediately persist stable ids.
		needsResave = true;
		char entries[64][12];
		int entryCount = ExplodeString(stateValue, ",", entries, sizeof(entries), sizeof(entries[]));
		for (int i = 0; i + 1 < entryCount; i += 2)
		{
			int hatIndex = 0;
			int paint = 0;
			if (!TryParseNonNegativeInt(entries[i], hatIndex))
			{
				continue;
			}
			if (!TryParseNonNegativeInt(entries[i + 1], paint))
			{
				continue;
			}
			if (!IsHatEnabled(hatIndex))
			{
				continue;
			}
			g_bHatEnabled[client][hatIndex] = true;
			g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(paint);
			if (!g_Hats[hatIndex].paintable)
			{
				g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(g_Hats[hatIndex].defaultPaint);
			}
			if (!g_szHatIdChoice[client][0])
			{
				strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), g_Hats[hatIndex].id);
			}
		}
	}

	if (!g_szHatIdChoice[client][0])
	{
		SetClientDefaultHat(client);
	}
	RecalculateClientEnabledHatCount(client);

	if (needsResave)
	{
		SaveHatStateCookie(client);
	}
}

void QueueHatStateSave(int client, bool allowClear = false)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}
	if (allowClear)
	{
		g_bHatSaveAllowClear[client] = true;
	}
	if (g_hHatSaveTimer[client] != INVALID_HANDLE)
	{
		delete g_hHatSaveTimer[client];
		g_hHatSaveTimer[client] = INVALID_HANDLE;
	}
	g_hHatSaveTimer[client] = CreateTimer(HAT_COOKIE_SAVE_DELAY, Timer_HatStateSave, client);
}

void FlushHatStateSave(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}
	if (g_hHatSaveTimer[client] == INVALID_HANDLE)
	{
		return;
	}
	delete g_hHatSaveTimer[client];
	g_hHatSaveTimer[client] = INVALID_HANDLE;
	bool allowClear = g_bHatSaveAllowClear[client];
	g_bHatSaveAllowClear[client] = false;
	SaveHatStateCookie(client, allowClear);
}

public Action Timer_HatStateSave(Handle timer, any client)
{
	int index = view_as<int>(client);
	if (index <= 0 || index > MaxClients)
	{
		return Plugin_Stop;
	}
	g_hHatSaveTimer[index] = INVALID_HANDLE;
	bool allowClear = g_bHatSaveAllowClear[index];
	g_bHatSaveAllowClear[index] = false;
	SaveHatStateCookie(index, allowClear);
	return Plugin_Stop;
}

void SaveHatStateCookie(int client, bool allowClear = false)
{
	if (g_hHatStateCookies[0] == INVALID_HANDLE || client <= 0 || client > MaxClients)
	{
		return;
	}

	if (!AreClientCookiesCached(client))
	{
		g_bHatStatePending[client] = true;
		g_bHatStatePendingAllowClear[client] = allowClear;
		if (g_hHatDebug != null && g_hHatDebug.BoolValue)
		{
			LogMessage("[CustomHats] Cookie cache not ready for %N; deferring save.", client);
		}
		return;
	}

	char states[MAX_HATS][HAT_COOKIE_VALUE_LEN];
	int chunk = 0;
	bool first = true;
	for (int i = 0; i < g_iHatCount; i++)
	{
		// Persist only the player's explicit choice. A forced hat is added to the
		// effective loadout at dispense time and must not alter that choice.
		if (!g_bHatEnabled[client][i] || !IsHatEnabled(i))
		{
			continue;
		}

		int paint = g_Hats[i].paintable
			? ClampPaintIndex(g_iHatPaintChoice[client][i])
			: ClampPaintIndex(g_Hats[i].defaultPaint);
		char entry[72];
		Format(entry, sizeof(entry), "%s:%d", g_Hats[i].id, paint);

		int needed = strlen(states[chunk]) + strlen(entry) + (first ? 0 : 1);
		if (needed >= sizeof(states[]))
		{
			chunk++;
			first = true;
			if (chunk >= MAX_HATS)
			{
				LogError("[CustomHats] Cannot persist all selected hats for client %d: cookie chunk limit reached.", client);
				return;
			}
		}

		if (!first)
		{
			StrCat(states[chunk], sizeof(states[]), ",");
		}
		StrCat(states[chunk], sizeof(states[]), entry);
		first = false;
	}

	if (!states[0][0] && !allowClear)
	{
		if (g_hHatDebug != null && g_hHatDebug.BoolValue)
		{
			LogMessage("[CustomHats] Skipping empty cookie save for %N.", client);
		}
		return;
	}

	if (g_hHatDebug != null && g_hHatDebug.BoolValue)
	{
		LogMessage("[CustomHats] Save cookie for %N using %d chunk(s): \"%s\"", client, states[0][0] ? chunk + 1 : 0, states[0]);
	}

	int newChunksUsed = states[0][0] ? chunk + 1 : 0;
	int chunksToWrite = newChunksUsed;
	if (g_iHatCookieChunksUsed[client] > chunksToWrite)
	{
		chunksToWrite = g_iHatCookieChunksUsed[client];
	}
	if (allowClear && chunksToWrite == 0)
	{
		chunksToWrite = 1;
	}

	for (int i = 0; i < chunksToWrite; i++)
	{
		if (g_hHatStateCookies[i] != INVALID_HANDLE)
		{
			SetClientCookie(client, g_hHatStateCookies[i], i < newChunksUsed ? states[i] : "");
		}
	}
	g_iHatCookieChunksUsed[client] = newChunksUsed;
}


