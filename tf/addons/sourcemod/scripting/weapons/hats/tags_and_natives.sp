static bool GetHatPrefixForClientTeam(int client, int hatIndex, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (GetClientTeam(client) == view_as<int>(TFTeam_Blue) && g_Hats[hatIndex].bluPrefix[0])
	{
		strcopy(buffer, maxlen, g_Hats[hatIndex].bluPrefix);
	}
	else
	{
		strcopy(buffer, maxlen, g_Hats[hatIndex].prefix);
	}

	return buffer[0] != '\0';
}

static bool AppendJoinedPrefix(char[] buffer, int maxlen, const char[] prefix)
{
	if (!prefix[0])
	{
		return false;
	}

	if (buffer[0])
	{
		StrCat(buffer, maxlen, "|");
	}

	StrCat(buffer, maxlen, prefix);
	return true;
}

static bool AppendJoinedHatTagChoice(char[] buffer, int maxlen, const char[] hatId, const char[] prefix)
{
	if (!hatId[0] || !prefix[0])
	{
		return false;
	}

	if (buffer[0])
	{
		StrCat(buffer, maxlen, "|");
	}

	StrCat(buffer, maxlen, hatId);
	StrCat(buffer, maxlen, "=");
	StrCat(buffer, maxlen, prefix);
	return true;
}

static bool GetClientHatPrefixes(int client, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (!Client_IsInGame(client) || !HasClientEnabledHats(client))
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown)
	{
		return false;
	}

	bool found = false;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEquippedForClient(client, i) || !CanClientUseHatForClass(client, i, playerClass))
		{
			continue;
		}

		char prefix[128];
		if (!GetHatPrefixForClientTeam(client, i, prefix, sizeof(prefix)))
		{
			continue;
		}

		AppendJoinedPrefix(buffer, maxlen, prefix);
		found = true;
	}

	return found;
}

static bool GetClientHatTagChoices(int client, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (!Client_IsInGame(client) || !HasClientEnabledHats(client))
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown)
	{
		return false;
	}

	bool found = false;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEquippedForClient(client, i) || !CanClientUseHatForClass(client, i, playerClass))
		{
			continue;
		}

		char prefix[128];
		if (!GetHatPrefixForClientTeam(client, i, prefix, sizeof(prefix)))
		{
			continue;
		}

		AppendJoinedHatTagChoice(buffer, maxlen, g_Hats[i].id, prefix);
		found = true;
	}

	return found;
}

static bool ResolveClientHatTag(int client, const char[] hatId, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (!Client_IsInGame(client) || !HasClientEnabledHats(client) || !hatId[0])
	{
		return false;
	}

	int hatIndex = FindHatIndexById(hatId);
	if (!IsHatEquippedForClient(client, hatIndex))
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown || !CanClientUseHatForClass(client, hatIndex, playerClass))
	{
		return false;
	}

	return GetHatPrefixForClientTeam(client, hatIndex, buffer, maxlen);
}

static bool FindClientHatTagSource(int client, const char[] prefix, char[] hatId, int maxlen)
{
	hatId[0] = '\0';

	if (!Client_IsInGame(client) || !HasClientEnabledHats(client) || !prefix[0])
	{
		return false;
	}

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (playerClass == TFClass_Unknown)
	{
		return false;
	}

	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEquippedForClient(client, i) || !CanClientUseHatForClass(client, i, playerClass))
		{
			continue;
		}

		if (StrEqual(prefix, g_Hats[i].prefix, false) || (g_Hats[i].bluPrefix[0] && StrEqual(prefix, g_Hats[i].bluPrefix, false)))
		{
			strcopy(hatId, maxlen, g_Hats[i].id);
			return true;
		}
	}

	return false;
}

public any Native_CustomHats_GetPrefix(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(3);

	char buffer[4096];
	buffer[0] = '\0';

	bool found = GetClientHatPrefixes(client, buffer, sizeof(buffer));
	SetNativeString(2, buffer, maxlen, true);
	return found;
}

public any Native_CustomHats_GetTagChoices(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(3);

	char buffer[4096];
	buffer[0] = '\0';

	bool found = GetClientHatTagChoices(client, buffer, sizeof(buffer));
	SetNativeString(2, buffer, maxlen, true);
	return found;
}

public any Native_CustomHats_ResolveTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(4);

	char hatId[64];
	char buffer[128];
	hatId[0] = '\0';
	buffer[0] = '\0';

	GetNativeString(2, hatId, sizeof(hatId));
	bool found = ResolveClientHatTag(client, hatId, buffer, sizeof(buffer));
	SetNativeString(3, buffer, maxlen, true);
	return found;
}

public any Native_CustomHats_FindTagSource(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(4);

	char prefix[128];
	char hatId[64];
	prefix[0] = '\0';
	hatId[0] = '\0';

	GetNativeString(2, prefix, sizeof(prefix));
	bool found = FindClientHatTagSource(client, prefix, hatId, sizeof(hatId));
	SetNativeString(3, hatId, maxlen, true);
	return found;
}

