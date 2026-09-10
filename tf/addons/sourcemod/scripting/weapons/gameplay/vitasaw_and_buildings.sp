static void VitaSaw_ClearStoredCharge(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	tf2_players[client].lastUber = 0.0;
	tf2_players[client].lastUberMedigunDefIndex = 0;
}

static bool VitaSaw_IsEquipped(int client)
{
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	return IsValidWeaponEntity(melee) && TF2CustAttr_GetInt(melee, ATTR_VITA_SAW_REVERT, 0) != 0;
}

static bool VitaSaw_GetMedigun(int client, int &medigun)
{
	medigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	return IsValidWeaponEntity(medigun);
}

void VitaSaw_CacheCharge(int client, bool requireAlive = true)
{
	if (!Accuracy_IsValidClient(client) || TF2_GetPlayerClass(client) != TFClass_Medic)
	{
		VitaSaw_ClearStoredCharge(client);
		return;
	}

	if (requireAlive && !IsPlayerAlive(client))
		return;

	int medigun;
	if (!VitaSaw_IsEquipped(client) || !VitaSaw_GetMedigun(client, medigun))
	{
		if (requireAlive)
		{
			VitaSaw_ClearStoredCharge(client);
		}
		return;
	}

	tf2_players[client].lastUber = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
	tf2_players[client].lastUberMedigunDefIndex = GetEntProp(medigun, Prop_Send, "m_iItemDefinitionIndex");
}

void VitaSaw_ApplyStoredCharge(int client)
{
	if (!Accuracy_IsValidClient(client) || !IsPlayerAlive(client) || TF2_GetPlayerClass(client) != TFClass_Medic)
		return;

	int medigun;
	if (!VitaSaw_IsEquipped(client) || !VitaSaw_GetMedigun(client, medigun))
		return;

	int storedDefIndex = tf2_players[client].lastUberMedigunDefIndex;
	if (storedDefIndex <= 0)
		return;

	if (GetEntProp(medigun, Prop_Send, "m_iItemDefinitionIndex") != storedDefIndex)
	{
		VitaSaw_ClearStoredCharge(client);
		return;
	}

	float preservedCharge = tf2_players[client].lastUber;
	if (preservedCharge > VITASAW_MAX_PRESERVED_CHARGE)
	{
		preservedCharge = VITASAW_MAX_PRESERVED_CHARGE;
	}

	float currentCharge = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
	if (preservedCharge > currentCharge)
	{
		SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", preservedCharge);
	}

	VitaSaw_ClearStoredCharge(client);
}

static bool Accuracy_IsValidFlameShotgun(int weapon)
{
	return (IsValidWeaponEntity(weapon) && TF2CustAttr_GetInt(weapon, "flame shotgun attributes") != 0);
}

Action OnBuildingDamaged(int entity, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!WeaponsGameplay_IsEnabled()
		|| !IsValidEntity(entity) || attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
		return Plugin_Continue;

	int weapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return Plugin_Continue;

	int drainAttr = TF2CustAttr_GetInt(weapon, "drain ammo on hit building");
	if (drainAttr <= 0)
		return Plugin_Continue;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	bool isDispenser = StrEqual(classname, "obj_dispenser");
	bool isSentry = StrEqual(classname, "obj_sentrygun");

	if (!isDispenser && !isSentry)
		return Plugin_Continue;

	int drained = 0;

	if (isDispenser)
	{
		int currentMetal = GetEntProp(entity, Prop_Send, "m_iAmmoMetal");
		int newMetal = currentMetal - drainAttr;
		if (newMetal < 0)
			newMetal = 0;
		SetEntProp(entity, Prop_Send, "m_iAmmoMetal", newMetal);
		drained = currentMetal - newMetal;
	}
	else
	{
		int currentShells = GetEntProp(entity, Prop_Send, "m_iAmmoShells");
		int newShells = currentShells - drainAttr;
		if (newShells < 0)
			newShells = 0;
		SetEntProp(entity, Prop_Send, "m_iAmmoShells", newShells);
		drained = currentShells - newShells;
	}

	if (drained > 0 && TF2_GetPlayerClass(attacker) == TFClass_Engineer && g_iMetalOffset != -1)
	{
		int attackerMetal = TF_GetMetalAmount(attacker);
		int credit = drained;
		if (attackerMetal + credit > 200)
			credit = 200 - attackerMetal;
		if (credit > 0)
		{
			TF_SetMetalAmount(attacker, attackerMetal + credit);
		}
	}

	return Plugin_Continue;
}

public void Event_PlayerBuiltObject(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return;
	}

	int ent = event.GetInt("index");
	HookBuildingEntity(ent);
}

static void FlameShotgun_Explode(int attacker, int victim, float position[3], float damage, float radius)
{
	if (!Accuracy_IsValidClient(attacker) || g_bAccuracyExploding[attacker])
		return;

	g_bAccuracyExploding[attacker] = true;

	int bomb = CreateEntityByName("tf_generic_bomb");
	if (bomb == -1)
	{
		g_bAccuracyExploding[attacker] = false;
		return;
	}

	DispatchKeyValueVector(bomb, "origin", position);
	DispatchKeyValueFloat(bomb, "damage", damage);
	DispatchKeyValueFloat(bomb, "radius", radius);
	DispatchKeyValue(bomb, "health", "1");
	DispatchSpawn(bomb);

	EmitAmbientSound(FLS_EXPLODE_SOUND, position, victim, SNDLEVEL_NORMAL);

	int particle = CreateEntityByName("info_particle_system");
	if (particle != -1)
	{
		float particlePos[3];
		particlePos = position;
		particlePos[2] += Accuracy_GetClassSubtractionValue(attacker);
		TeleportEntity(particle, particlePos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "effect_name", "mvm_cash_explosion");
		DispatchKeyValue(particle, "start_active", "0");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");
		CreateTimer(1.0, Accuracy_Timer_RemoveEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
	}

	int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	SDKHooks_TakeDamage(bomb, attacker, attacker, 9001.0, DMG_BULLET, weapon);

	int targetTeam = GetClientTeam(victim);
	if (targetTeam > 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!Accuracy_IsValidClient(i) || !IsPlayerAlive(i))
				continue;
			if (GetClientTeam(i) != targetTeam)
				continue;

			float clientPos[3];
			GetClientAbsOrigin(i, clientPos);
			if (GetVectorDistance(position, clientPos) <= radius)
			{
				TF2_IgnitePlayer(i, attacker, 2.0);
			}
		}
	}

	g_bAccuracyExploding[attacker] = false;
}

public Action Accuracy_Timer_RemoveEntity(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if (entity != INVALID_ENT_REFERENCE)
	{
		RemoveEntity(entity);
	}
	return Plugin_Stop;
}

void Accuracy_OnFlameShotgunStack(int attacker, int victim, int weapon = -1)
{
	if (!Accuracy_IsValidClient(attacker) || !Accuracy_IsValidClient(victim) || attacker == victim)
		return;
	if (g_bAccuracyExploding[attacker])
		return;

	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	}
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		ScatterPellets_Debug("meatshot ignored: no valid active weapon");
		return;
	}
	if (!Accuracy_IsValidFlameShotgun(weapon))
	{
		ScatterPellets_Debug("meatshot ignored: weapon lacks flame shotgun attributes");
		return;
	}

	float eye[3];
	GetClientEyePosition(attacker, eye);

	float now = GetGameTime();
	if (tf2_players[victim].accuracyStreakExpiresAt <= now)
	{
		tf2_players[victim].accuracyStreak = 0;
	}

	tf2_players[victim].accuracyStreak++;
	tf2_players[victim].accuracyStreakExpiresAt = now + FLS_STREAK_WINDOW;
	if (tf2_players[victim].accuracyStreak >= FLS_STREAK_TARGET)
	{
		float boomPos[3];
		GetClientAbsOrigin(victim, boomPos);
		boomPos[2] -= Accuracy_GetClassSubtractionValue(victim);

		if (IsPlayerAlive(victim))
		{
			TF2_IgnitePlayer(victim, attacker, 4.0);
		}
		FlameShotgun_Explode(attacker, victim, boomPos, FLS_EXPLODE_DAMAGE, FLS_EXPLODE_RADIUS);
		EmitAmbientSound(FLS_NOTIFY_2, eye, attacker, SNDLEVEL_NORMAL);

		int maxClip = GetWeaponMaxClip(weapon);
		if (maxClip > 0)
		{
			int clip = GetClip(weapon);
			if (clip >= 0 && clip < maxClip)
			{
				SetClip_Weapon(weapon, maxClip);
			}
		}

		tf2_players[victim].accuracyStreak = 0;
		tf2_players[victim].accuracyStreakExpiresAt = 0.0;
	}
	else
	{
		EmitAmbientSound(FLS_NOTIFY_SOUND, eye, attacker, SNDLEVEL_NORMAL);
	}
}

