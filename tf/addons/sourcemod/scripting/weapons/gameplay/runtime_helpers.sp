public void WeaponsGameplay_FrameApplyWearerAttributes(any userId)
{
	int client = GetClientOfUserId(userId);
	WeaponsGameplay_ApplyPrimaryClipBonusFromLoadout(client);
	WeaponsGameplay_ApplyPipebombDecreaseFromLoadout(client);
	WeaponsGameplay_ApplyStickyFizzleTimeFromLoadout(client);
}

void WeaponsGameplay_QueueWearerAttributeRefresh(int client)
{
	if (!Weapons_IsClientInGame(client))
		return;

	RequestFrame(WeaponsGameplay_FrameApplyWearerAttributes, GetClientUserId(client));
}

void WeaponsGameplay_OnItemRuntimeStateReady(int client, int entity)
{
	if (!Weapons_IsClientInGame(client) || !Weapons_IsValidWeaponEntity(entity))
		return;

	WeaponsGameplay_QueueWearerAttributeRefresh(client);
}

public int TF2Items_OnGiveNamedItem_Post(int client, char[] classname, int itemDefinitionIndex, int itemLevel, int itemQuality, int entityIndex)
{
	CustomHats_OnGiveNamedItemPost(client);

	if (WeaponsGameplay_IsEnabled()) {
		ShockCharge_StopTimer(client);
		tf2_players[client].shockCharge = 30;
		TF2Attrib_SetByName(entityIndex, "crit mod disabled hidden", 0.00);

		char auth[32];
		if (g_hFallingStompAllWeapons != null
			&& GetConVarBool(g_hFallingStompAllWeapons)
			&& Kogasa_GetClientSteam2(client, auth, sizeof(auth), true))
		{
			if (!(StrEqual(auth, "STEAM_0:1:101494818")))
			{
				TF2Attrib_SetByName(entityIndex, "boots falling stomp", 1.00);
			}
		}

		if (entityIndex > MaxClients
			&& IsValidEntity(entityIndex)
			&& TF2Attrib_HookValueInt(0, "killstreak tier", entityIndex) <= 0)
		{
			TF2Attrib_SetByName(entityIndex, "killstreak tier", 1.0);
		}

		int oldMax = GetWeaponMaxClip(entityIndex);
		int oldClip = GetClip(entityIndex);

		WeaponsGameplay_ApplyConfiguredAttributes(client, itemDefinitionIndex, entityIndex);

		int newMax = GetWeaponMaxClip(entityIndex);
		if (oldMax > 0 && oldClip == oldMax && newMax > oldMax)
		{
			SetClip_Weapon(entityIndex, newMax);
		}

		WeaponsGameplay_QueueWearerAttributeRefresh(client);
	}

	return 0;
}

bool ValidateAndNullCheck(MemoryPatch patch) {
		return patch != null && patch.Validate();
}

void DestroyPatch(MemoryPatch patch)
{
	if (patch != null)
	{
		patch.Disable();
		delete patch;
	}
}

public float clamp(float a, float b, float c)
{
	return (a > c ? c : (a < b ? b : a));
}

void HookAllBuildings()
{
	static const char classes[][] = { "obj_sentrygun", "obj_dispenser" };

	for (int i = 0; i < sizeof(classes); i++)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, classes[i])) != -1)
		{
			HookBuildingEntity(ent);
		}
	}
}

void HookBuildingEntity(int entity)
{
	if (entity <= 0 || !IsValidEntity(entity))
		return;

	SDKHook(entity, SDKHook_OnTakeDamage, OnBuildingDamaged);
}

float ValveRemapVal(float val, float a, float b, float c, float d) {
	// https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/public/mathlib/mathlib.h#L648

	float tmp;

	if (a == b) {
		return (val >= b ? d : c);
	}

	tmp = ((val - a) / (b - a));

	if (tmp < 0.0) tmp = 0.0;
	if (tmp > 1.0) tmp = 1.0;

	return (c + ((d - c) * tmp));
}

int abs(int x)
{
	int mask = x >> 31;
	return (x + mask) ^ mask;
}
