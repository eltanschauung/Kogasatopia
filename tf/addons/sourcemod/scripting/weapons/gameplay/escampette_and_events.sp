static bool Escampette_IsEquipped(int client)
{
	if (!WeaponsGameplay_IsEnabled()
		|| !Weapons_IsClientInGame(client)
		|| !IsPlayerAlive(client)
		|| TF2_GetPlayerClass(client) != TFClass_Spy)
	{
		return false;
	}

	int watch = GetPlayerWeaponSlot(client, ESCAMPETTE_WATCH_SLOT);
	return watch > MaxClients
		&& IsValidEntity(watch)
		&& TF2CustAttr_GetInt(watch, ATTR_ESCAMPETTE, 0) != 0;
}

bool Escampette_HasSpeedBonus(int client)
{
	return Escampette_IsEquipped(client)
		&& TF2_IsPlayerInCondition(client, TFCond_Cloaked);
}

void Escampette_RecalculateSpeed(int client)
{
	if (g_SDKTeamFortressSetSpeed != null
		&& Weapons_IsClientInGame(client)
		&& IsPlayerAlive(client))
	{
		SDKCall(g_SDKTeamFortressSetSpeed, client);
	}
}

void Escampette_RecalculateAllSpeeds()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		Escampette_RecalculateSpeed(client);
	}
}

static void Escampette_FrameRecalculateSpeed(any userId)
{
	Escampette_RecalculateSpeed(GetClientOfUserId(userId));
}

static void Escampette_QueueSpeedRecalculation(int client)
{
	if (Weapons_IsValidPlayerIndex(client))
	{
		RequestFrame(Escampette_FrameRecalculateSpeed, GetClientUserId(client));
	}
}

public void WeaponsGameplay_OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	bool enabled = WeaponsGameplay_IsEnabled();
	WeaponsGameplay_SetPatchesEnabled(enabled);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
		{
			continue;
		}

		ResetClientArrays(client);
		if (enabled)
		{
			Harvester_SyncHealTimer(client);
		}
	}

	if (enabled)
	{
		HookAllBuildings();
		WeaponsGameplay_HookExistingWeaponEntities();
	}

	Escampette_RecalculateAllSpeeds();
}

void Escampette_OnDamageTaken(int victim, int attacker, float damage, const float damagePosition[3])
{
	// Preserve the prior behavior: positive damage from any non-world source counts.
	if (damage <= 0.0 || attacker <= 0 || !Escampette_HasSpeedBonus(victim))
	{
		return;
	}

	float cloakMeter = GetEntPropFloat(victim, Prop_Send, "m_flCloakMeter") - 10.0;
	if (cloakMeter < 0.0)
	{
		cloakMeter = 0.0;
	}

	SetEntPropFloat(victim, Prop_Send, "m_flCloakMeter", cloakMeter);
	EmitAmbientSound(SOUND_POMSON_DRAIN, damagePosition, victim, SNDLEVEL_NORMAL);
}

public Action Event_Resupply(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return Plugin_Continue;
	}

	int userId = event.GetInt("userid");
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Continue;
	BlastJumpJarate_ClearPending(client);
	Escampette_QueueSpeedRecalculation(client);
	HuntingRevolver_ResetClient(client);
	if (!Harvester_IsEligibleClient(client))
	{
		Harvester_ClearState(client);
	}

	VitaSaw_ApplyStoredCharge(client);
	RequestFrame(Harvester_FrameSyncHealTimer, GetClientUserId(client));

	if (tf2_players[client].shockCharge != 30)
	{
		tf2_players[client].shockCharge = 29; // The 29 is for visual effect
		ShockCharge_StartTimer(client);
		return Plugin_Changed;
	}

	if (tf2_players[client].sprokeTimer != null)
	{
		Sproke_ClearEffect(client, false, true);
	}
	return Plugin_Continue;

}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return Plugin_Continue;
	}

	int userId = event.GetInt("userid");
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Continue;
	WeaponsMovement_OnPlayerSpawn(client);
	BlastJumpJarate_ClearPending(client);
	Escampette_QueueSpeedRecalculation(client);
	HuntingRevolver_ResetClient(client);
	if (!Harvester_IsEligibleClient(client))
	{
		Harvester_ClearState(client);
	}

	ScattergunKnockback_ResetClient(client);
	VitaSaw_ApplyStoredCharge(client);
	RequestFrame(Harvester_FrameSyncHealTimer, GetClientUserId(client));

	return Plugin_Continue;
}

public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		Escampette_QueueSpeedRecalculation(client);
		HuntingRevolver_ResetClient(client);
		Harvester_ClearState(client);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		Escampette_QueueSpeedRecalculation(client);
		HuntingRevolver_ResetClient(client);
		Harvester_ClearState(client);
	}
}

#define FSOLID_USE_TRIGGER_BOUNDS 0x80
