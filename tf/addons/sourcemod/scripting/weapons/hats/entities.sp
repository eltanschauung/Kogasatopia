void EquipHat(int client, int hatIndex)
{
	RemoveHat(client, hatIndex, false);

	TFClassType playerClass = TF2_GetPlayerClass(client);
	if (!IsClassAllowedForHat(hatIndex, playerClass))
	{
		return;
	}
	if (!CanClientAccessHat(client, hatIndex))
	{
		return;
	}

	int classIndex = view_as<int>(playerClass);
	int hideDefIndex = GetHideDefIndexForClass(hatIndex, classIndex);
	if (hideDefIndex > 0)
	{
		int hideWearable = CreateWearableBase(client, hideDefIndex, g_Hats[hatIndex].level, g_Hats[hatIndex].quality);
		if (hideWearable != -1)
		{
			g_iHideHatRef[client][hatIndex] = EntIndexToEntRef(hideWearable);
		}
	}

	int hatDefIndex = GetHatDefIndexForClass(hatIndex, classIndex);
	if (hatDefIndex <= 0)
	{
		return;
	}
	int paint = g_Hats[hatIndex].force
		? ClampPaintIndex(g_Hats[hatIndex].defaultPaint)
		: g_iHatPaintChoice[client][hatIndex];
	int wearable = CreateHat(client, g_Hats[hatIndex].model, hatDefIndex, g_Hats[hatIndex].level, g_Hats[hatIndex].quality, paint, g_Hats[hatIndex].style, g_Hats[hatIndex].hasModelScale, g_Hats[hatIndex].modelScale);
	if (wearable != -1)
	{
		if (g_Hats[hatIndex].bluSkin >= 0 && GetClientTeam(client) == view_as<int>(TFTeam_Blue))
		{
			SetEntProp(wearable, Prop_Send, "m_nSkin", g_Hats[hatIndex].bluSkin);
		}
		g_iHatRef[client][hatIndex] = EntIndexToEntRef(wearable);
	}
	if (!g_Hats[hatIndex].force)
	{
		QueueHatStateSave(client);
	}
}

void RemoveHatIndex(int client, int hatIndex)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	int ent = EntRefToEntIndex(g_iHatRef[client][hatIndex]);
	if (ent != INVALID_ENT_REFERENCE)
	{
		RemoveEntity(ent);
	}
	g_iHatRef[client][hatIndex] = INVALID_ENT_REFERENCE;

	int hideEnt = EntRefToEntIndex(g_iHideHatRef[client][hatIndex]);
	if (hideEnt != INVALID_ENT_REFERENCE)
	{
		RemoveEntity(hideEnt);
	}
	g_iHideHatRef[client][hatIndex] = INVALID_ENT_REFERENCE;
}

void RemoveHat(int client, int hatIndex, bool saveState = true)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (hatIndex < 0)
	{
		for (int i = 0; i < MAX_HATS; i++)
		{
			RemoveHatIndex(client, i);
		}
		if (saveState)
		{
			QueueHatStateSave(client);
		}
		return;
	}

	RemoveHatIndex(client, hatIndex);
	if (saveState)
	{
		QueueHatStateSave(client);
	}
}

int CreateWearableBase(int client, int itemIndex, int level, int quality)
{
	if (itemIndex <= 0)
	{
		return -1;
	}

	int entity = CreateEntityByName("tf_wearable");
	if (entity == -1 || !IsValidEntity(entity))
	{
		return -1;
	}

	SetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex", itemIndex);
	SetEntProp(entity, Prop_Send, "m_bInitialized", 1);
	SetEntProp(entity, Prop_Send, "m_iEntityLevel", level);
	SetEntProp(entity, Prop_Send, "m_iEntityQuality", quality);
	SetEntProp(entity, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

	SetEntProp(entity, Prop_Send, "m_fEffects", HAT_EF_BONEMERGE | HAT_EF_BONEMERGE_FASTCULL);
	SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	SetEntProp(entity, Prop_Send, "m_nSkin", GetClientTeam(client));
	SetEntProp(entity, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 11);
	SetEntProp(entity, Prop_Send, "m_iItemIDLow", 2048);
	SetEntProp(entity, Prop_Send, "m_iItemIDHigh", 0);

	DispatchSpawn(entity);
	ActivateEntity(entity);
	TF2Util_EquipPlayerWearable(client, entity);
	Weapons_MarkValidatedAttachedEntity(entity, client, "custom_hat");

	return entity;
}

int CreateHat(int client, const char[] modelPath, int itemIndex, int level, int quality, int paint, int style, bool hasModelScale, float modelScale)
{
	int entity = CreateWearableBase(client, itemIndex, level, quality);
	if (entity == -1)
	{
		return -1;
	}

	ApplyCustomModel(entity, modelPath);
	ApplyModelScale(entity, hasModelScale, modelScale);

	if (paint > 0)
	{
		ApplyPaint(entity, paint);
	}

	ApplyStyle(entity, style);
	return entity;
}

