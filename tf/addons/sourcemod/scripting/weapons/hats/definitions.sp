static const int g_ClassMaskByIndex[10] =
{
	0,
	CLASSMASK_SCOUT,
	CLASSMASK_SNIPER,
	CLASSMASK_SOLDIER,
	CLASSMASK_DEMO,
	CLASSMASK_MEDIC,
	CLASSMASK_HEAVY,
	CLASSMASK_PYRO,
	CLASSMASK_SPY,
	CLASSMASK_ENGINEER
};

void ResetHatConfig(HatConfig hat)
{
	hat.enabled = false;
	hat.force = false;
	hat.id[0] = '\0';
	hat.name[0] = '\0';
	hat.prefix[0] = '\0';
	hat.bluPrefix[0] = '\0';
	hat.pointsStorePurchase[0] = '\0';
	hat.model[0] = '\0';
	hat.hasModelScale = false;
	hat.modelScale = 1.0;
	hat.quality = 6;
	hat.level = 10;
	hat.defaultPaint = 0;
	hat.paintable = false;
	hat.style = 0;
	hat.bluSkin = -1;
	hat.classMask = CLASSMASK_SCOUT;
	hat.baseDefIndex = 0;
	hat.baseHideDefIndex = 0;
	for (int i = 0; i < sizeof(hat.defindexByClass); i++)
	{
		hat.defindexByClass[i] = 0;
		hat.hideDefindexByClass[i] = 0;
	}
}

bool IsHatIndexValid(int hatIndex)
{
	return hatIndex >= 0 && hatIndex < g_iHatCount;
}

bool IsHatEnabled(int hatIndex)
{
	return IsHatIndexValid(hatIndex) && g_Hats[hatIndex].enabled && g_Hats[hatIndex].model[0];
}

bool IsHatEquippedForClient(int client, int hatIndex)
{
	return IsHatEnabled(hatIndex)
		&& (g_Hats[hatIndex].force || g_bHatEnabled[client][hatIndex]);
}

static bool IsHatSelectable(int hatIndex)
{
	return IsHatEnabled(hatIndex) && !g_Hats[hatIndex].force;
}

bool CanClientAccessHat(int client, int hatIndex)
{
	if (!IsHatIndexValid(hatIndex))
	{
		return false;
	}
	if (g_Hats[hatIndex].force)
	{
		return true;
	}
	if (!g_Hats[hatIndex].pointsStorePurchase[0])
	{
		return true;
	}
	if (!Client_IsInGame(client))
	{
		return false;
	}
	if (GetFeatureStatus(FeatureType_Native, POINTS_STORE_HAS_PURCHASE_NATIVE) != FeatureStatus_Available)
	{
		return false;
	}
	return PointsStore_HasPurchase(client, g_Hats[hatIndex].pointsStorePurchase);
}

bool CanClientUseHatForClass(int client, int hatIndex, TFClassType playerClass)
{
	return CanClientViewHatForClass(hatIndex, playerClass)
		&& CanClientAccessHat(client, hatIndex);
}

bool CanClientViewHatForClass(int hatIndex, TFClassType playerClass)
{
	return IsHatEnabled(hatIndex)
		&& IsClassAllowedForHat(hatIndex, playerClass);
}

void PrintHatLockedMessage(int client, int hatIndex)
{
	if (!Client_IsInGame(client) || !IsHatIndexValid(hatIndex))
	{
		return;
	}
	if (g_Hats[hatIndex].pointsStorePurchase[0])
	{
		PrintToChat(client, "[Hats] %s is locked. Purchase it from !shop first.", g_Hats[hatIndex].name);
	}
}

bool HasEnabledHats()
{
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (IsHatEnabled(i))
		{
			return true;
		}
	}
	return false;
}

int FindHatIndexById(const char[] id)
{
	if (!id[0])
	{
		return -1;
	}
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (StrEqual(g_Hats[i].id, id, false))
		{
			return i;
		}
	}
	return -1;
}

int GetDefaultHatIndex()
{
	if (IsHatSelectable(g_iDefaultHatIndex))
	{
		return g_iDefaultHatIndex;
	}
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (IsHatSelectable(i))
		{
			return i;
		}
	}
	return -1;
}

int GetSelectedHatIndex(int client)
{
	int hatIndex = FindHatIndexById(g_szHatIdChoice[client]);
	if (IsHatSelectable(hatIndex))
	{
		return hatIndex;
	}
	int defaultIndex = GetDefaultHatIndex();
	if (defaultIndex >= 0)
	{
		strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), g_Hats[defaultIndex].id);
	}
	else
	{
		g_szHatIdChoice[client][0] = '\0';
	}
	return defaultIndex;
}

void SetClientDefaultHat(int client)
{
	int hatIndex = GetDefaultHatIndex();
	if (hatIndex >= 0)
	{
		strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), g_Hats[hatIndex].id);
		g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(g_Hats[hatIndex].defaultPaint);
	}
	else
	{
		g_szHatIdChoice[client][0] = '\0';
	}
}

bool AddHatConfig(HatConfig hat)
{
	if (!hat.id[0])
	{
		return false;
	}
	if (FindHatIndexById(hat.id) >= 0)
	{
		LogError("[CustomHats] Duplicate hat id in config: %s", hat.id);
		return false;
	}
	if (g_iHatCount >= MAX_HATS)
	{
		LogError("[CustomHats] Too many hats configured (max %d).", MAX_HATS);
		return false;
	}
	if (!hat.name[0])
	{
		strcopy(hat.name, sizeof(hat.name), hat.id);
	}
	int hatIndex = g_iHatCount;
	g_Hats[hatIndex] = hat;
	if (hat.enabled && !hat.force && g_iDefaultHatIndex < 0)
	{
		g_iDefaultHatIndex = hatIndex;
	}
	g_iHatCount++;
	return true;
}

int ParseClassMask(const char[] list)
{
	char buffer[128];
	strcopy(buffer, sizeof(buffer), list);
	TrimString(buffer);
	Strings_ToLower(buffer, sizeof(buffer));

	if (!buffer[0])
	{
		return CLASSMASK_SCOUT;
	}
	if (StrEqual(buffer, "all"))
	{
		return CLASSMASK_ALL;
	}

	int mask = 0;
	char parts[16][32];
	int count = ExplodeString(buffer, ",", parts, sizeof(parts), sizeof(parts[]));
	for (int i = 0; i < count; i++)
	{
		TrimString(parts[i]);
		Strings_ToLower(parts[i], sizeof(parts[i]));
		if (!parts[i][0])
		{
			continue;
		}
		if (StrEqual(parts[i], "all"))
		{
			return CLASSMASK_ALL;
		}
		if (StrEqual(parts[i], "scout"))
		{
			mask |= CLASSMASK_SCOUT;
		}
		else if (StrEqual(parts[i], "soldier"))
		{
			mask |= CLASSMASK_SOLDIER;
		}
		else if (StrEqual(parts[i], "pyro"))
		{
			mask |= CLASSMASK_PYRO;
		}
		else if (StrEqual(parts[i], "demoman") || StrEqual(parts[i], "demo"))
		{
			mask |= CLASSMASK_DEMO;
		}
		else if (StrEqual(parts[i], "heavy"))
		{
			mask |= CLASSMASK_HEAVY;
		}
		else if (StrEqual(parts[i], "engineer"))
		{
			mask |= CLASSMASK_ENGINEER;
		}
		else if (StrEqual(parts[i], "medic"))
		{
			mask |= CLASSMASK_MEDIC;
		}
		else if (StrEqual(parts[i], "sniper"))
		{
			mask |= CLASSMASK_SNIPER;
		}
		else if (StrEqual(parts[i], "spy"))
		{
			mask |= CLASSMASK_SPY;
		}
	}

	if (mask == 0)
	{
		mask = CLASSMASK_SCOUT;
	}
	return mask;
}

bool IsClassAllowedForHat(int hatIndex, TFClassType class)
{
	if (!IsHatIndexValid(hatIndex))
	{
		return false;
	}
	int classIndex = view_as<int>(class);
	if (classIndex < 1 || classIndex > 9)
	{
		return false;
	}
	return (g_Hats[hatIndex].classMask & g_ClassMaskByIndex[classIndex]) != 0;
}

bool ParseBoolString(const char[] value, bool defaultValue)
{
	if (!value[0])
	{
		return defaultValue;
	}
	if (StrEqual(value, "1") || StrEqual(value, "true", false) || StrEqual(value, "yes", false) || StrEqual(value, "on", false))
	{
		return true;
	}
	if (StrEqual(value, "0") || StrEqual(value, "false", false) || StrEqual(value, "no", false) || StrEqual(value, "off", false))
	{
		return false;
	}
	return defaultValue;
}

void LoadClassOverrides(KeyValues kv, const char[] key, TFClassType class, HatConfig hat)
{
	if (!kv.JumpToKey(key))
	{
		return;
	}

	int classIndex = view_as<int>(class);
	if (classIndex < 1 || classIndex > 9)
	{
		kv.GoBack();
		return;
	}

	int defindex = kv.GetNum("defindex", 0);
	int hideDefindex = kv.GetNum("hide_defindex", 0);
	if (defindex > 0)
	{
		hat.defindexByClass[classIndex] = defindex;
	}
	if (hideDefindex > 0)
	{
		hat.hideDefindexByClass[classIndex] = hideDefindex;
	}
	kv.GoBack();
}

int GetHatDefIndexForClass(int hatIndex, int classIndex)
{
	if (!IsHatIndexValid(hatIndex) || classIndex < 1 || classIndex > 9)
	{
		return 0;
	}
	int defindex = g_Hats[hatIndex].defindexByClass[classIndex];
	if (defindex > 0)
	{
		return defindex;
	}
	return g_Hats[hatIndex].baseDefIndex;
}

int GetHideDefIndexForClass(int hatIndex, int classIndex)
{
	if (!IsHatIndexValid(hatIndex) || classIndex < 1 || classIndex > 9)
	{
		return 0;
	}
	int defindex = g_Hats[hatIndex].hideDefindexByClass[classIndex];
	if (defindex > 0)
	{
		return defindex;
	}
	return g_Hats[hatIndex].baseHideDefIndex;
}

