void LoadHatStateCookie(int client)
{
	ResetClientHatSelections(client);
	g_szHatIdChoice[client][0] = '\0';

	if (g_hHatStateCookie == INVALID_HANDLE || !AreClientCookiesCached(client))
	{
		SetClientDefaultHat(client);
		return;
	}

	char stateValue[HAT_COOKIE_VALUE_LEN];
	GetClientCookie(client, g_hHatStateCookie, stateValue, sizeof(stateValue));
	if (!stateValue[0])
	{
		SetClientDefaultHat(client);
		return;
	}

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
			if (IsHatEnabled(hatIndex) && !g_Hats[hatIndex].force)
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
			if (g_Hats[hatIndex].force)
			{
				needsResave = true;
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
		needsResave = true;
	}
	else
	{
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
			if (g_Hats[hatIndex].force)
			{
				needsResave = true;
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
	if (g_hHatStateCookie == INVALID_HANDLE || client <= 0 || client > MaxClients)
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

	char state[HAT_COOKIE_VALUE_LEN];
	state[0] = '\0';

	bool first = true;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!g_bHatEnabled[client][i] || !IsHatEnabled(i) || g_Hats[i].force)
		{
			continue;
		}

		int paint = g_Hats[i].paintable
			? ClampPaintIndex(g_iHatPaintChoice[client][i])
			: ClampPaintIndex(g_Hats[i].defaultPaint);
		char entry[24];
		Format(entry, sizeof(entry), "%d,%d", i, paint);

		int needed = strlen(state) + strlen(entry) + (first ? 0 : 1);
		if (needed >= sizeof(state))
		{
			break;
		}

		if (!first)
		{
			StrCat(state, sizeof(state), ",");
		}
		StrCat(state, sizeof(state), entry);
		first = false;
	}

	if (!state[0] && !allowClear)
	{
		if (g_hHatDebug != null && g_hHatDebug.BoolValue)
		{
			LogMessage("[CustomHats] Skipping empty cookie save for %N.", client);
		}
		return;
	}

	if (g_hHatDebug != null && g_hHatDebug.BoolValue)
	{
		LogMessage("[CustomHats] Save cookie for %N: \"%s\"", client, state);
	}
	SetClientCookie(client, g_hHatStateCookie, state);
}


