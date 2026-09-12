int GetDamageSourceWeapon(int attacker, int weapon, int inflictor)
{
	if (weapon > MaxClients && IsValidEntity(weapon))
	{
		return weapon;
	}

	if (inflictor > MaxClients && IsValidEntity(inflictor))
	{
		if (HasEntProp(inflictor, Prop_Send, "m_hLauncher"))
		{
			int launcher = GetEntPropEnt(inflictor, Prop_Send, "m_hLauncher");
			if (launcher > MaxClients && IsValidEntity(launcher))
			{
				return launcher;
			}
		}

		if (HasEntProp(inflictor, Prop_Send, "m_hOriginalLauncher"))
		{
			int launcher = GetEntPropEnt(inflictor, Prop_Send, "m_hOriginalLauncher");
			if (launcher > MaxClients && IsValidEntity(launcher))
			{
				return launcher;
			}
		}
	}

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		int activeWeapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
		if (activeWeapon > MaxClients && IsValidEntity(activeWeapon))
		{
			return activeWeapon;
		}
	}

	return -1;
}

void DamageSourceTracking_ResetClient(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	g_iProjectileDirectHitRef[client] = INVALID_ENT_REFERENCE;
	g_iProjectileDirectHitTick[client] = 0;
	g_iLastDamageWeaponRef[client] = INVALID_ENT_REFERENCE;
	g_iLastDamageWeaponAttackerUserId[client] = 0;
	g_iLastDamageWeaponTick[client] = 0;
}

public void ProjectileDirectHit_OnTouch(int projectile, int other)
{
	if (!Weapons_IsClientInGame(other))
		return;

	g_iProjectileDirectHitRef[other] = EntIndexToEntRef(projectile);
	g_iProjectileDirectHitTick[other] = GetGameTickCount();
}

bool DamageSource_IsProjectileDirectHit(int victim, int inflictor)
{
	return Weapons_IsClientInGame(victim)
		&& inflictor > MaxClients
		&& IsValidEntity(inflictor)
		&& g_iProjectileDirectHitTick[victim] == GetGameTickCount()
		&& g_iProjectileDirectHitRef[victim] == EntIndexToEntRef(inflictor);
}

void DamageSource_RecordPotentialKill(int attacker, int victim, int weapon)
{
	if (!Weapons_IsValidPlayerIndex(victim))
		return;

	g_iLastDamageWeaponRef[victim] = INVALID_ENT_REFERENCE;
	g_iLastDamageWeaponAttackerUserId[victim] = 0;
	g_iLastDamageWeaponTick[victim] = 0;

	if (!Weapons_IsClientInGame(attacker) || !Weapons_IsValidWeaponEntity(weapon))
		return;

	g_iLastDamageWeaponRef[victim] = EntIndexToEntRef(weapon);
	g_iLastDamageWeaponAttackerUserId[victim] = GetClientUserId(attacker);
	g_iLastDamageWeaponTick[victim] = GetGameTickCount();
}

int DamageSource_GetKillingWeapon(int attacker, int victim)
{
	if (!Weapons_IsClientInGame(attacker)
		|| !Weapons_IsValidPlayerIndex(victim)
		|| g_iLastDamageWeaponAttackerUserId[victim] != GetClientUserId(attacker)
		|| g_iLastDamageWeaponTick[victim] != GetGameTickCount())
	{
		return -1;
	}

	int weapon = EntRefToEntIndex(g_iLastDamageWeaponRef[victim]);
	return Weapons_IsValidWeaponEntity(weapon) ? weapon : -1;
}

public any Native_GetKillingWeapon(Handle plugin, int numParams)
{
	return DamageSource_GetKillingWeapon(GetNativeCell(1), GetNativeCell(2));
}

static void FullPelletIgnite_ClearPair(int attacker, int victim)
{
	if (!Weapons_IsValidPlayerIndex(attacker) || !Weapons_IsValidPlayerIndex(victim))
	{
		return;
	}

	g_bPendingFullPelletIgnite[attacker][victim] = false;
	g_iPendingFullPelletWeaponRef[attacker][victim] = INVALID_ENT_REFERENCE;
	g_fPendingFullPelletBurnDuration[attacker][victim] = 0.0;
	g_iPendingFullPelletTick[attacker][victim] = 0;
}

void FullPelletIgnite_ClearClient(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
	{
		return;
	}

	for (int other = 1; other <= MaxClients; other++)
	{
		FullPelletIgnite_ClearPair(client, other);
		FullPelletIgnite_ClearPair(other, client);
	}
}

void FullPelletIgnite_ClearAll()
{
	for (int attacker = 1; attacker <= MaxClients; attacker++)
	{
		for (int victim = 1; victim <= MaxClients; victim++)
		{
			FullPelletIgnite_ClearPair(attacker, victim);
		}
	}
}

void FullPelletIgnite_TryMark(int attacker, int victim, int weapon)
{
	if (!Accuracy_IsValidClient(attacker) || !Accuracy_IsValidClient(victim) || attacker == victim)
	{
		return;
	}

	FullPelletIgnite_ClearPair(attacker, victim);
	if (!WeaponsGameplay_IsEnabled()
		|| !IsPlayerAlive(victim)
		|| GetClientTeam(attacker) <= 1
		|| GetClientTeam(victim) <= 1
		|| GetClientTeam(attacker) == GetClientTeam(victim)
		|| g_bAccuracyExploding[attacker]
		|| !IsValidWeaponEntity(weapon)
		|| GetFeatureStatus(FeatureType_Native, "TF2Scatter_IsCurrentShotFull") != FeatureStatus_Available)
	{
		return;
	}

	float burnDuration = TF2CustAttr_GetFloat(weapon, ATTR_IGNITE_ON_FULL_PELLET_HIT, 0.0);
	if (burnDuration <= 0.0 || !TF2Scatter_IsCurrentShotFull(attacker, victim, weapon))
	{
		return;
	}

	g_bPendingFullPelletIgnite[attacker][victim] = true;
	g_iPendingFullPelletWeaponRef[attacker][victim] = EntIndexToEntRef(weapon);
	g_fPendingFullPelletBurnDuration[attacker][victim] = burnDuration;
	g_iPendingFullPelletTick[attacker][victim] = GetGameTickCount();
}

void FullPelletIgnite_TryConsumePost(int victim, int attacker, int weapon, int inflictor)
{
	if (!Weapons_IsValidPlayerIndex(attacker) || !Weapons_IsValidPlayerIndex(victim)
		|| !g_bPendingFullPelletIgnite[attacker][victim])
	{
		return;
	}

	int damageWeapon = GetDamageSourceWeapon(attacker, weapon, inflictor);
	bool matches = g_iPendingFullPelletTick[attacker][victim] == GetGameTickCount()
		&& IsValidWeaponEntity(damageWeapon)
		&& EntIndexToEntRef(damageWeapon) == g_iPendingFullPelletWeaponRef[attacker][victim];
	float burnDuration = g_fPendingFullPelletBurnDuration[attacker][victim];
	FullPelletIgnite_ClearPair(attacker, victim);

	if (!matches || burnDuration <= 0.0 || !IsPlayerAlive(victim)
		|| TF2_IsPlayerInCondition(victim, TFCond_Disguised)
		|| TF2_IsPlayerInCondition(victim, TFCond_Cloaked)
		|| TF2_IsPlayerInCondition(victim, TFCond_AfterburnImmune))
	{
		return;
	}

	TF2Util_IgnitePlayer(victim, attacker, burnDuration, damageWeapon);
}
