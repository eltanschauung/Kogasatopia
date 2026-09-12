bool Accuracy_IsValidClient(int client)
{
	return Weapons_IsClientInGame(client);
}

bool IsValidWeaponEntity(int weapon)
{
	return Weapons_IsValidWeaponEntity(weapon);
}

static bool IsAmbassadorHeadshotWeapon(int weapon)
{
	if (!IsValidWeaponEntity(weapon))
		return false;

	int defIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	return (defIndex == AMBASSADOR_ITEMDEF || defIndex == FESTIVE_AMBASSADOR_ITEMDEF);
}

bool Ambassador102_IsEnabledWeapon(int weapon)
{
	return IsAmbassadorHeadshotWeapon(weapon) && TF2CustAttr_GetInt(weapon, ATTR_AMBASSADOR_102, 0) != 0;
}

static bool WeaponsGameplay_IsCriticalShotHookClass(const char[] classname)
{
	return StrEqual(classname, "tf_weapon_pistol") || StrEqual(classname, "tf_weapon_revolver");
}

void WeaponsGameplay_HookCriticalShotEntity(int weapon, const char[] classname)
{
	if (dhook_CTFWeaponBase_CanFireCriticalShot == null
		|| !WeaponsGameplay_IsEntityIndex(weapon)
		|| !IsValidEntity(weapon)
		|| !WeaponsGameplay_IsCriticalShotHookClass(classname))
	{
		return;
	}

	dhook_CTFWeaponBase_CanFireCriticalShot.HookEntity(Hook_Post, weapon, CanFireCriticalShot_Post);
}

void WeaponsGameplay_HookShortCircuitEntity(int weapon, const char[] classname)
{
	if (dhook_CTFWeaponBase_PrimaryAttack == null
		|| dhook_CTFWeaponBase_SecondaryAttack == null
		|| weapon <= MaxClients
		|| weapon >= MAX_TRACKED_ENTITIES
		|| !IsValidEntity(weapon)
		|| !StrEqual(classname, "tf_weapon_mechanical_arm")
		|| g_bShortCircuitAttackHooks[weapon])
	{
		return;
	}

	dhook_CTFWeaponBase_PrimaryAttack.HookEntity(Hook_Pre, weapon, ShortCircuit_PrimaryAttack_Pre);
	dhook_CTFWeaponBase_SecondaryAttack.HookEntity(Hook_Pre, weapon, ShortCircuit_SecondaryAttack_Pre);
	g_bShortCircuitAttackHooks[weapon] = true;
}

void WeaponsGameplay_HookExistingWeaponEntities()
{
	char classname[64];
	int maxEntities = GetMaxEntities();
	for (int weapon = MaxClients + 1; weapon < maxEntities; weapon++)
	{
		if (!IsValidEntity(weapon))
			continue;

		GetEntityClassname(weapon, classname, sizeof(classname));
		WeaponsGameplay_HookCriticalShotEntity(weapon, classname);
		WeaponsGameplay_HookShortCircuitEntity(weapon, classname);
		Plasma_Hook(weapon, classname);
	}
}

static bool ShortCircuit_IsEnabledWeapon(int weapon)
{
	if (!WeaponsGameplay_IsEnabled()
		|| !IsValidWeaponEntity(weapon)
		|| TF2CustAttr_GetInt(weapon, ATTR_SHORT_CIRCUIT_PREFEB2014, 0) != 1)
	{
		return false;
	}

	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	return StrEqual(classname, "tf_weapon_mechanical_arm");
}

static bool ShortCircuit_IsEligibleProjectile(int entity, const char[] classname)
{
	return entity > MaxClients
		&& StrContains(classname, "tf_projectile_") == 0
		&& StrContains(classname, "tf_projectile_spell") == -1
		&& !StrEqual(classname, "tf_projectile_energy_ring")
		&& !StrEqual(classname, "tf_projectile_grapplinghook")
		&& !StrEqual(classname, "tf_projectile_syringe");
}

public bool ShortCircuit_TraceFilter(int entity, int contentsMask, any target)
{
	if (entity == target || entity <= MaxClients)
		return false;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	return StrContains(classname, "obj_") != 0
		&& StrContains(classname, "tf_projectile_") != 0
		&& !StrEqual(classname, "func_respawnroomvisualizer");
}

static float ShortCircuit_FixYaw(float angle)
{
	return angle > 180.0 ? angle - 360.0 : angle;
}

static float ShortCircuit_CalcViewOffset(const float viewAngles[3], const float targetAngles[3])
{
	float pitch = FloatAbs(viewAngles[0] - targetAngles[0]);
	float yaw = ShortCircuit_FixYaw(FloatAbs(viewAngles[1] - targetAngles[1]));
	return SquareRoot(pitch * pitch + yaw * yaw);
}

static void ShortCircuit_RotateVectorAroundZ(const float vector[3], float angle, float output[3])
{
	float radians = DegToRad(angle);
	output[0] = vector[0] * Cosine(radians) - vector[1] * Sine(radians);
	output[1] = vector[0] * Sine(radians) + vector[1] * Cosine(radians);
	output[2] = vector[2];
}

static void ShortCircuit_ShowParticle(const float origin[3], const float target[3], const float angles[3])
{
	if (g_iShortCircuitParticle == INVALID_STRING_INDEX)
		return;

	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", origin[0]);
	TE_WriteFloat("m_vecOrigin[1]", origin[1]);
	TE_WriteFloat("m_vecOrigin[2]", origin[2]);
	TE_WriteFloat("m_vecStart[0]", target[0]);
	TE_WriteFloat("m_vecStart[1]", target[1]);
	TE_WriteFloat("m_vecStart[2]", target[2]);
	TE_WriteVector("m_vecAngles", angles);
	TE_WriteNum("m_iParticleSystemIndex", g_iShortCircuitParticle);
	TE_SendToAllInRange(origin, RangeType_Visibility, 0.0);
}

static bool DoShortCircuitProjectileRemoval(int owner, int weapon, int baseAmount, int amountPerDestroyed, float playerDamage = 0.0)
{
	if (!Weapons_IsClientInGame(owner) || !IsPlayerAlive(owner))
		return false;

	int metal = TF_GetMetalAmount(owner);
	if (baseAmount > 0)
	{
		TF_SetMetalAmount(owner, metal - baseAmount);
	}

	float eyePosition[3];
	float eyeAngles[3];
	GetClientEyePosition(owner, eyePosition);
	GetClientEyeAngles(owner, eyeAngles);

	bool hit = false;
	char classname[64];
	int maxEntities = GetMaxEntities();
	for (int target = 1; target < maxEntities; target++)
	{
		if (!IsValidEntity(target))
			continue;

		GetEntityClassname(target, classname, sizeof(classname));
		bool isPlayer = target <= MaxClients;
		if (!isPlayer && !ShortCircuit_IsEligibleProjectile(target, classname))
			continue;

		if (isPlayer && (!Weapons_IsClientInGame(target) || !IsPlayerAlive(target)))
			continue;

		if (GetEntProp(target, Prop_Send, "m_iTeamNum") == GetClientTeam(owner))
			continue;

		float targetPosition[3];
		GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetPosition);
		if (isPlayer)
			targetPosition[2] += SHORT_CIRCUIT_PLAYER_CENTER_HEIGHT;

		float distance = GetVectorDistance(eyePosition, targetPosition);
		if (distance >= SHORT_CIRCUIT_MAX_RANGE)
			continue;

		float direction[3];
		float targetAngles[3];
		MakeVectorFromPoints(eyePosition, targetPosition, direction);
		GetVectorAngles(direction, targetAngles);
		targetAngles[1] = ShortCircuit_FixYaw(targetAngles[1]);

		float flatEyeAngles[3];
		flatEyeAngles[0] = 0.0;
		flatEyeAngles[1] = eyeAngles[1];
		flatEyeAngles[2] = eyeAngles[2];
		targetAngles[0] = 0.0;
		float angleLimit = isPlayer
			? ValveRemapVal(distance, 0.0, 150.0, 70.0, 25.0)
			: ValveRemapVal(distance, 0.0, 200.0, 80.0, 40.0);
		if (ShortCircuit_CalcViewOffset(flatEyeAngles, targetAngles) >= angleLimit)
			continue;

		TR_TraceRayFilter(eyePosition, targetPosition, MASK_SOLID, RayType_EndPoint, ShortCircuit_TraceFilter, target);
		if (TR_DidHit())
			continue;

		if (isPlayer)
		{
			if (playerDamage <= 0.0)
				continue;

			SDKHooks_TakeDamage(target, weapon, owner, playerDamage, DMG_SHOCK, weapon, NULL_VECTOR, targetPosition, false);
		}
		else
		{
			if (amountPerDestroyed > 0)
			{
				metal = TF_GetMetalAmount(owner);
				if (metal < baseAmount + amountPerDestroyed)
					break;

				TF_SetMetalAmount(owner, metal - amountPerDestroyed);
			}

			RemoveEntity(target);
		}

		hit = true;
		float muzzleOffset[3] = {10.0, -10.0, -20.0};
		float rotatedOffset[3];
		float particleOrigin[3];
		ShortCircuit_RotateVectorAroundZ(muzzleOffset, flatEyeAngles[1], rotatedOffset);
		AddVectors(eyePosition, rotatedOffset, particleOrigin);
		ShortCircuit_ShowParticle(particleOrigin, targetPosition, flatEyeAngles);
	}

	return hit;
}

public MRESReturn ShortCircuit_PrimaryAttack_Pre(int weapon)
{
	if (!ShortCircuit_IsEnabledWeapon(weapon))
		return MRES_Ignored;

	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	DoShortCircuitProjectileRemoval(owner, weapon, 0, 15, 0.0);
	return MRES_Ignored;
}

public MRESReturn ShortCircuit_SecondaryAttack_Pre(int weapon)
{
	return ShortCircuit_IsEnabledWeapon(weapon) ? MRES_Supercede : MRES_Ignored;
}

Action Ambassador102_OnHeadshotDamage(int victim, int attacker, int weapon, float &damage, int damagetype, int damagecustom)
{
	if (damagecustom != TF_CUSTOM_HEADSHOT || !Ambassador102_IsEnabledWeapon(weapon))
		return Plugin_Continue;

	if (!Weapons_IsClientInGame(victim) || !Weapons_IsClientInGame(attacker))
		return Plugin_Continue;

	if ((damagetype & DMG_ACID) != DMG_ACID)
	{
		EmitSoundToClient(victim, SOUND_AMBASSADOR_CRIT_RECEIVED, SOUND_FROM_PLAYER, SNDCHAN_AUTO, 95);
		EmitSoundToClient(attacker, SOUND_AMBASSADOR_CRIT_HIT, SOUND_FROM_PLAYER, SNDCHAN_AUTO, 85);

		if (g_iAmbassadorCritParticle != INVALID_STRING_INDEX)
		{
			float origin[3];
			GetEntPropVector(victim, Prop_Send, "m_vecOrigin", origin);

			TE_Start("TFParticleEffect");
			TE_WriteFloat("m_vecOrigin[0]", origin[0]);
			TE_WriteFloat("m_vecOrigin[1]", origin[1]);
			TE_WriteFloat("m_vecOrigin[2]", origin[2] + 56.0);
			TE_WriteNum("m_iParticleSystemIndex", g_iAmbassadorCritParticle);
			TE_SendToClient(attacker);
		}
	}

	damage = 102.0;
	return Plugin_Changed;
}

void TryAwardAmbassadorHeadshotKill(Event event, int attacker, int victim, int weapon)
{
	if (!Accuracy_IsValidClient(attacker) || !Accuracy_IsValidClient(victim) || attacker == victim)
		return;
	if (IsFakeClient(attacker) || IsFakeClient(victim))
		return;
	if (GetClientTeam(attacker) <= 1 || GetClientTeam(attacker) == GetClientTeam(victim))
		return;
	if (event.GetInt("customkill") != TF_CUSTOM_HEADSHOT)
		return;
	if (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
		return;

	if (!IsAmbassadorHeadshotWeapon(weapon))
		return;

	FireAmbassadorHeadshotKill(attacker, victim);
}

void TryAwardSandmanCleaverCombo(int attacker, int victim)
{
	if (!Accuracy_IsValidClient(attacker) || !Accuracy_IsValidClient(victim) || attacker == victim)
		return;
	if (IsFakeClient(attacker) || IsFakeClient(victim))
		return;
	if (GetClientTeam(attacker) <= 1 || GetClientTeam(attacker) == GetClientTeam(victim))
		return;

	FireSandmanCleaverCombo(attacker, victim);
}
