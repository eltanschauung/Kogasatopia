void WeaponsGameplay_SetConfig(KeyValues config)
{
	WeaponsGameplay_DeleteConfigs();
	if (config == null)
		return;

	g_hWeaponsGameplayConfig = new KeyValues(WEAPONS_CONFIG_ROOT);
	g_hWeaponsGameplayConfig.Import(config);
}

public Action Command_ReloadWeaponsConfig(int client, int args)
{
	LoadWeaponsConfig();
	int regenerated = 0;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (IsClientInGame(target))
		{
			HuntingRevolver_ResetClient(target);
			if (IsPlayerAlive(target))
			{
				TF2_RegeneratePlayer(target);
				regenerated++;
			}
			Harvester_SyncHealTimer(target);
			Escampette_RecalculateSpeed(target);
		}
	}
	ReplyToCommand(client,
		"[Weapons] Reloaded configs/weapons.cfg and refreshed %d active loadouts.",
		regenerated);
	return Plugin_Handled;
}

static bool WeaponsGameplay_ItemKeyContainsIndex(const char[] itemKey, int index)
{
	int indexes[32];
	int count = ItemIndexes_Parse(itemKey, indexes, sizeof(indexes));
	for (int i = 0; i < count; i++)
	{
		if (indexes[i] == index)
		{
			return true;
		}
	}

	return false;
}

static bool WeaponsGameplay_JumpToConfiguredWeapon(int index)
{
	if (g_hWeaponsGameplayConfig == null)
		return false;

	g_hWeaponsGameplayConfig.Rewind();
	if (!g_hWeaponsGameplayConfig.GotoFirstSubKey(true))
		return false;

	do
	{
		char itemKey[64];
		g_hWeaponsGameplayConfig.GetSectionName(itemKey, sizeof(itemKey));
		if (WeaponsGameplay_ItemKeyContainsIndex(itemKey, index))
		{
			return true;
		}
	}
	while (g_hWeaponsGameplayConfig.GotoNextKey(true));

	g_hWeaponsGameplayConfig.Rewind();
	return false;
}

static bool WeaponsGameplay_CurrentSectionContainsItemIndex(KeyValues kv, int index)
{
	if (kv == null)
		return false;

	bool found = false;
	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			char itemKey[64];
			kv.GetSectionName(itemKey, sizeof(itemKey));
			if (WeaponsGameplay_ItemKeyContainsIndex(itemKey, index))
			{
				found = true;
				break;
			}
		}
		while (kv.GotoNextKey(false));

		kv.GoBack();
	}

	return found;
}

static bool WeaponsGameplay_IsAllowedForClient(int client)
{
	if (g_hWeaponsGameplayConfig == null || !Weapons_IsClientInGame(client))
		return true;

	if (!g_hWeaponsGameplayConfig.JumpToKey("classes", false))
		return true;

	char classKey[16];
	TF2Classes_GetKey(TF2_GetPlayerClass(client), classKey, sizeof(classKey));

	bool allowed = false;
	if (classKey[0] != '\0')
	{
		char value[8];
		g_hWeaponsGameplayConfig.GetString(classKey, value, sizeof(value));
		allowed = (value[0] != '\0' && StringToInt(value) != 0);
	}

	g_hWeaponsGameplayConfig.GoBack();
	return allowed;
}

static void WeaponsGameplay_GetWeaponClasses(int index, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	if (g_hWeaponsGameplayConfig == null)
		return;

	g_hWeaponsGameplayConfig.Rewind();
	if (!g_hWeaponsGameplayConfig.JumpToKey(WEAPONS_ITEM_CLASSES_SECTION, false))
		return;

	if (!g_hWeaponsGameplayConfig.GotoFirstSubKey(true))
	{
		g_hWeaponsGameplayConfig.Rewind();
		return;
	}

	do
	{
		char className[32];
		g_hWeaponsGameplayConfig.GetSectionName(className, sizeof(className));

		if (WeaponsGameplay_CurrentSectionContainsItemIndex(g_hWeaponsGameplayConfig, index))
		{
			if (buffer[0] != '\0')
				StrCat(buffer, maxlen, ",");
			StrCat(buffer, maxlen, className);
		}
	}
	while (g_hWeaponsGameplayConfig.GotoNextKey(true));

	g_hWeaponsGameplayConfig.Rewind();
}

static bool WeaponsGameplay_ClassCanUseWeapon(const char[] className, int index)
{
	if (g_hWeaponsGameplayConfig == null)
		return false;

	g_hWeaponsGameplayConfig.Rewind();
	if (!g_hWeaponsGameplayConfig.JumpToKey(WEAPONS_ITEM_CLASSES_SECTION, false))
		return false;

	if (!g_hWeaponsGameplayConfig.JumpToKey(className, false))
	{
		g_hWeaponsGameplayConfig.Rewind();
		return false;
	}

	bool found = WeaponsGameplay_CurrentSectionContainsItemIndex(g_hWeaponsGameplayConfig, index);
	g_hWeaponsGameplayConfig.Rewind();
	return found;
}

bool WeaponsGameplay_GetConfiguredInfo(int index, char[] weaponName, int weaponNameLen, char[] positive, int positiveLen, char[] neutral, int neutralLen, char[] negative, int negativeLen, char[] type, int typeLen, char[] classes, int classesLen)
{
	if (g_hWeaponsGameplayConfig == null)
		return false;

	if (!WeaponsGameplay_JumpToConfiguredWeapon(index))
		return false;

	g_hWeaponsGameplayConfig.GetString("name", weaponName, weaponNameLen, "Unknown Weapon");
	positive[0] = '\0';
	neutral[0] = '\0';
	negative[0] = '\0';
	strcopy(type, typeLen, "buff");

	if (g_hWeaponsGameplayConfig.JumpToKey("description", false))
	{
		g_hWeaponsGameplayConfig.GetString("positive", positive, positiveLen, "");
		g_hWeaponsGameplayConfig.GetString("neutral", neutral, neutralLen, "");
		g_hWeaponsGameplayConfig.GetString("negative", negative, negativeLen, "");
		g_hWeaponsGameplayConfig.GetString("type", type, typeLen, "buff");
		g_hWeaponsGameplayConfig.GoBack();
	}

	g_hWeaponsGameplayConfig.Rewind();
	WeaponsGameplay_GetWeaponClasses(index, classes, classesLen);
	return true;
}

public int Native_GetWeaponInfo(Handle plugin, int numParams)
{
	int index = GetNativeCell(1);

	char weaponName[128];
	char positive[256];
	char neutral[256];
	char negative[256];
	char type[32];
	char classes[128];
	bool found = WeaponsGameplay_GetConfiguredInfo(index, weaponName, sizeof(weaponName), positive, sizeof(positive), neutral, sizeof(neutral), negative, sizeof(negative), type, sizeof(type), classes, sizeof(classes));

	SetNativeString(2, found ? weaponName : "", GetNativeCell(3), true);
	SetNativeString(4, found ? positive : "", GetNativeCell(5), true);
	if (numParams >= 13)
	{
		SetNativeString(6, found ? neutral : "", GetNativeCell(7), true);
		SetNativeString(8, found ? negative : "", GetNativeCell(9), true);
		SetNativeString(10, found ? type : "buff", GetNativeCell(11), true);
		SetNativeString(12, found ? classes : "", GetNativeCell(13), true);
	}
	else
	{
		SetNativeString(6, found ? negative : "", GetNativeCell(7), true);
		SetNativeString(8, found ? type : "buff", GetNativeCell(9), true);
		SetNativeString(10, found ? classes : "", GetNativeCell(11), true);
	}
	return found;
}

public int Native_CanClassUseWeapon(Handle plugin, int numParams)
{
	char className[32];
	GetNativeString(1, className, sizeof(className));
	return WeaponsGameplay_ClassCanUseWeapon(className, GetNativeCell(2));
}

static void WeaponsGameplay_ApplyAttributeSection(int entity, const char[] sectionName, bool customAttributes)
{
	if (!g_hWeaponsGameplayConfig.JumpToKey(sectionName, false))
		return;

	if (g_hWeaponsGameplayConfig.GotoFirstSubKey(false))
	{
		do
		{
			char attr[128];
			char value[128];
			g_hWeaponsGameplayConfig.GetSectionName(attr, sizeof(attr));
			g_hWeaponsGameplayConfig.GetString(NULL_STRING, value, sizeof(value));

			if (attr[0] != '\0' && value[0] != '\0')
			{
				if (customAttributes)
				{
					TF2CustAttr_SetString(entity, attr, value);
				}
				else
				{
					TF2Attrib_SetByName(entity, attr, StringToFloat(value));
				}
			}
		}
		while (g_hWeaponsGameplayConfig.GotoNextKey(false));

		g_hWeaponsGameplayConfig.GoBack();
	}

	g_hWeaponsGameplayConfig.GoBack();
}

static void WeaponsGameplay_ApplyGameAttributeSection(int entity)
{
	WeaponsGameplay_ApplyAttributeSection(entity, "attributes_game", false);
}

static void WeaponsGameplay_ApplyCustomAttributeSection(int entity)
{
	WeaponsGameplay_ApplyAttributeSection(entity, "attributes_custom", true);
}

void WeaponsGameplay_ApplyConfiguredAttributes(int client, int index, int entity)
{
	if (g_hWeaponsGameplayConfig == null || !Weapons_IsClientInGame(client) || !Weapons_IsValidWeaponEntity(entity))
		return;

	if (!WeaponsGameplay_JumpToConfiguredWeapon(index))
		return;

	if (WeaponsGameplay_IsAllowedForClient(client))
	{
		WeaponsGameplay_ApplyGameAttributeSection(entity);
		WeaponsGameplay_ApplyCustomAttributeSection(entity);
		Weapons_NotifyItemRuntimeStateReady(client, entity);
	}

	g_hWeaponsGameplayConfig.Rewind();
}

static float WeaponsGameplay_GetPrimaryClipBonusFromLoadout(int client)
{
	float bestBonus = 0.0;

	for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (!Weapons_IsValidWeaponEntity(weapon))
			continue;

		float bonus = TF2CustAttr_GetFloat(weapon, ATTR_PRIMARY_CLIP_SIZE_BONUS, 0.0);
		if (bonus > bestBonus)
		{
			bestBonus = bonus;
		}
	}

	return bestBonus;
}

void WeaponsGameplay_ApplyPrimaryClipBonusFromLoadout(int client)
{
	if (!Weapons_IsClientInGame(client))
		return;

	int primary = GetPlayerWeaponSlot(client, WEAPON_SLOT_PRIMARY);
	if (!Weapons_IsValidWeaponEntity(primary))
		return;

	float bonus = WeaponsGameplay_GetPrimaryClipBonusFromLoadout(client);
	if (bonus <= 0.0)
		return;

	TF2Attrib_SetByName(primary, ATTR_CLIP_SIZE_BONUS, bonus);
}

static float WeaponsGameplay_GetPipebombDecreaseFromLoadout(int client)
{
	float decrease = 0.0;

	for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (!Weapons_IsValidWeaponEntity(weapon))
			continue;

		decrease += TF2CustAttr_GetFloat(weapon, ATTR_MAX_PIPEBOMBS_DECREASED_WEARER, 0.0);
	}

	return decrease;
}

void WeaponsGameplay_ClearPipebombWearerAttribute(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	int secondary = EntRefToEntIndex(g_iPipebombWearerSecondaryRef[client]);
	if (Weapons_IsValidWeaponEntity(secondary))
	{
		if (g_bPipebombWearerHadBaseAttribute[client])
		{
			TF2Attrib_SetByName(
				secondary,
				ATTR_MAX_PIPEBOMBS_DECREASED,
				g_flPipebombWearerBaseAttribute[client]
			);
		}
		else
		{
			TF2Attrib_RemoveByName(secondary, ATTR_MAX_PIPEBOMBS_DECREASED);
		}
	}

	g_iPipebombWearerSecondaryRef[client] = INVALID_ENT_REFERENCE;
	g_bPipebombWearerHadBaseAttribute[client] = false;
	g_flPipebombWearerBaseAttribute[client] = 0.0;
	g_flPipebombWearerBaseEffectiveAttribute[client] = 0.0;
}

void WeaponsGameplay_ApplyPipebombDecreaseFromLoadout(int client)
{
	if (!Weapons_IsClientInGame(client))
		return;

	int secondary = GetPlayerWeaponSlot(client, WEAPON_SLOT_SECONDARY);
	float decrease = WeaponsGameplay_GetPipebombDecreaseFromLoadout(client);

	if (EntRefToEntIndex(g_iPipebombWearerSecondaryRef[client]) != secondary)
	{
		WeaponsGameplay_ClearPipebombWearerAttribute(client);
	}

	if (!Weapons_IsValidWeaponEntity(secondary) || decrease == 0.0)
	{
		WeaponsGameplay_ClearPipebombWearerAttribute(client);
		return;
	}

	if (g_iPipebombWearerSecondaryRef[client] == INVALID_ENT_REFERENCE)
	{
		Address baseAttribute = TF2Attrib_GetByName(
			secondary,
			ATTR_MAX_PIPEBOMBS_DECREASED
		);

		g_iPipebombWearerSecondaryRef[client] = EntIndexToEntRef(secondary);
		g_bPipebombWearerHadBaseAttribute[client] = baseAttribute != Address_Null;
		g_flPipebombWearerBaseAttribute[client] =
			baseAttribute != Address_Null ? TF2Attrib_GetValue(baseAttribute) : 0.0;
		g_flPipebombWearerBaseEffectiveAttribute[client] = TF2Attrib_HookValueFloat(
			0.0,
			ATTR_CLASS_MAX_PIPEBOMBS_DECREASED,
			secondary
		);
	}

	float effectiveAttribute =
		g_flPipebombWearerBaseEffectiveAttribute[client] + decrease;
	if (effectiveAttribute < MIN_MAX_PIPEBOMBS_ATTRIBUTE)
	{
		decrease += MIN_MAX_PIPEBOMBS_ATTRIBUTE - effectiveAttribute;
	}

	TF2Attrib_SetByName(
		secondary,
		ATTR_MAX_PIPEBOMBS_DECREASED,
		g_flPipebombWearerBaseAttribute[client] + decrease
	);
}

static float WeaponsGameplay_GetStickyFizzleTimeFromLoadout(int client)
{
	float fizzleTime = 0.0;

	for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (!Weapons_IsValidWeaponEntity(weapon))
			continue;

		float value = TF2CustAttr_GetFloat(
			weapon,
			ATTR_STICKYBOMB_FIZZLE_TIME_WEARER,
			0.0
		);
		if (value > fizzleTime)
		{
			fizzleTime = value;
		}
	}

	return fizzleTime;
}

void WeaponsGameplay_ClearStickyFizzleWearerAttribute(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	int secondary = EntRefToEntIndex(g_iStickyFizzleWearerSecondaryRef[client]);
	if (Weapons_IsValidWeaponEntity(secondary))
	{
		if (g_bStickyFizzleWearerHadBaseAttribute[client])
		{
			TF2Attrib_SetByName(
				secondary,
				ATTR_STICKYBOMB_FIZZLE_TIME,
				g_flStickyFizzleWearerBaseAttribute[client]
			);
		}
		else
		{
			TF2Attrib_RemoveByName(secondary, ATTR_STICKYBOMB_FIZZLE_TIME);
		}
	}

	g_iStickyFizzleWearerSecondaryRef[client] = INVALID_ENT_REFERENCE;
	g_bStickyFizzleWearerHadBaseAttribute[client] = false;
	g_flStickyFizzleWearerBaseAttribute[client] = 0.0;
}

void WeaponsGameplay_ApplyStickyFizzleTimeFromLoadout(int client)
{
	if (!Weapons_IsClientInGame(client))
		return;

	int secondary = GetPlayerWeaponSlot(client, WEAPON_SLOT_SECONDARY);
	float fizzleTime = WeaponsGameplay_GetStickyFizzleTimeFromLoadout(client);

	if (EntRefToEntIndex(g_iStickyFizzleWearerSecondaryRef[client]) != secondary)
	{
		WeaponsGameplay_ClearStickyFizzleWearerAttribute(client);
	}

	if (!Weapons_IsValidWeaponEntity(secondary) || fizzleTime <= 0.0)
	{
		WeaponsGameplay_ClearStickyFizzleWearerAttribute(client);
		return;
	}

	if (g_iStickyFizzleWearerSecondaryRef[client] == INVALID_ENT_REFERENCE)
	{
		Address baseAttribute = TF2Attrib_GetByName(
			secondary,
			ATTR_STICKYBOMB_FIZZLE_TIME
		);

		g_iStickyFizzleWearerSecondaryRef[client] = EntIndexToEntRef(secondary);
		g_bStickyFizzleWearerHadBaseAttribute[client] = baseAttribute != Address_Null;
		g_flStickyFizzleWearerBaseAttribute[client] =
			baseAttribute != Address_Null ? TF2Attrib_GetValue(baseAttribute) : 0.0;
	}

	TF2Attrib_SetByName(secondary, ATTR_STICKYBOMB_FIZZLE_TIME, fizzleTime);
}

