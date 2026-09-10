static int GetProjectileOwner(int projectile)
{
	if (projectile <= MaxClients || !IsValidEntity(projectile))
		return 0;

	if (HasEntProp(projectile, Prop_Send, "m_hThrower"))
	{
		int owner = GetEntPropEnt(projectile, Prop_Send, "m_hThrower");
		if (Weapons_IsClientInGame(owner))
		{
			return owner;
		}
	}

	if (HasEntProp(projectile, Prop_Send, "m_hOwnerEntity"))
	{
		int owner = GetEntPropEnt(projectile, Prop_Send, "m_hOwnerEntity");
		if (Weapons_IsClientInGame(owner))
		{
			return owner;
		}
	}

	return 0;
}

static bool SandmanPreJI_IsEnabledWeapon(int weapon)
{
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return false;

	if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") != SANDMAN_ITEMDEF)
		return false;

	return TF2CustAttr_GetInt(weapon, ATTR_SANDMAN_PRE_JI) != 0;
}

static float SandmanPreJI_GetBaseStunDuration()
{
	if (g_hSandmanBaseDuration != null)
	{
		return g_hSandmanBaseDuration.FloatValue;
	}

	return g_hSandmanFallbackBaseDuration != null ? g_hSandmanFallbackBaseDuration.FloatValue : 2.0;
}

static float SandmanPreJI_GetMaxStunFlightTime()
{
	return g_hSandmanMaxStunFlightTime != null ? g_hSandmanMaxStunFlightTime.FloatValue : 1.5;
}

static bool SandmanPreJI_IsStunBall(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char class[64];
	GetEntityClassname(entity, class, sizeof(class));
	return StrEqual(class, "tf_projectile_stun_ball");
}

public void SandmanPreJI_OnStunBallSpawnPost(int entity)
{
	if (!WeaponsGameplay_IsEnabled()
		|| entity <= 0 || entity >= MAX_TRACKED_ENTITIES || !IsValidEntity(entity))
		return;

	int owner = GetProjectileOwner(entity);
	int sandman = GetDamageSourceWeapon(owner, -1, entity);
	g_bProjectileSandmanPreJI[entity] = SandmanPreJI_IsEnabledWeapon(sandman);
}

static bool SandmanPreJI_IsEnabledProjectile(int projectile)
{
	if (!SandmanPreJI_IsStunBall(projectile))
		return false;

	if (projectile > 0 && projectile < MAX_TRACKED_ENTITIES && g_bProjectileSandmanPreJI[projectile])
	{
		return true;
	}

	int owner = GetProjectileOwner(projectile);
	int sandman = GetDamageSourceWeapon(owner, -1, projectile);
	bool enabled = SandmanPreJI_IsEnabledWeapon(sandman);
	if (enabled && projectile > 0 && projectile < MAX_TRACKED_ENTITIES)
	{
		g_bProjectileSandmanPreJI[projectile] = true;
	}
	return enabled;
}

static bool SandmanPreJI_IsEnabledForDamage(int attacker, int weapon, int inflictor)
{
	if (SandmanPreJI_IsEnabledProjectile(inflictor))
	{
		return true;
	}

	int sandman = GetDamageSourceWeapon(attacker, weapon, inflictor);
	return SandmanPreJI_IsEnabledWeapon(sandman);
}

Action SandmanPreJI_OnBaseballDamage(int victim, int attacker, int weapon, int inflictor, float &damage)
{
	if (!Weapons_IsClientInGame(victim) || !Weapons_IsClientInGame(attacker) || victim == attacker)
		return Plugin_Continue;

	if (!SandmanPreJI_IsEnabledForDamage(attacker, weapon, inflictor))
		return Plugin_Continue;

	damage = SANDMAN_PRE_JI_DAMAGE;
	return Plugin_Changed;
}

public MRESReturn SandmanPreJI_ApplyBallImpactEffectOnVictim_Pre(int entity, DHookParam parameters)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int victim = parameters.Get(1);
	if (!Weapons_IsClientInGame(victim) || !SandmanPreJI_IsEnabledProjectile(entity))
	{
		return MRES_Ignored;
	}

	g_iSandmanStunFrame[victim] = GetGameTickCount();
	g_iSandmanStunInflictorRef[victim] = EntIndexToEntRef(entity);
	return MRES_Ignored;
}

static int SandmanPreJI_FindPendingStunVictim()
{
	int frame = GetGameTickCount();
	int victim = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!Weapons_IsClientInGame(i) || g_iSandmanStunFrame[i] != frame)
		{
			continue;
		}

		if (victim != 0)
		{
			return 0;
		}
		victim = i;
	}
	return victim;
}

static int SandmanPreJI_GetStunVictim(Address sharedAddress)
{
	if (GetFeatureStatus(FeatureType_Native, "TF2Util_GetPlayerFromSharedAddress") == FeatureStatus_Available)
	{
		int victim = TF2Util_GetPlayerFromSharedAddress(sharedAddress);
		if (Weapons_IsClientInGame(victim))
		{
			return victim;
		}
	}

	return SandmanPreJI_FindPendingStunVictim();
}

public MRESReturn SandmanPreJI_StunPlayer_Pre(Address sharedAddress, DHookParam parameters)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int victim = SandmanPreJI_GetStunVictim(sharedAddress);
	if (!Weapons_IsClientInGame(victim) || g_iSandmanStunFrame[victim] != GetGameTickCount())
	{
		return MRES_Ignored;
	}

	int inflictor = EntRefToEntIndex(g_iSandmanStunInflictorRef[victim]);
	g_iSandmanStunFrame[victim] = 0;
	g_iSandmanStunInflictorRef[victim] = INVALID_ENT_REFERENCE;
	if (!SandmanPreJI_IsEnabledProjectile(inflictor))
	{
		return MRES_Ignored;
	}

	float spawnTime = (inflictor > 0 && inflictor < MAX_TRACKED_ENTITIES) ? g_flProjectileSpawnTime[inflictor] : 0.0;
	float maxFlightTime = SandmanPreJI_GetMaxStunFlightTime();
	float flightTime = spawnTime > 0.0 ? GetGameTime() - spawnTime : maxFlightTime;
	float cappedFlightTime = flightTime < maxFlightTime ? flightTime : maxFlightTime;
	float lifetimeRatio = cappedFlightTime / maxFlightTime;
	if (lifetimeRatio <= SANDMAN_PRE_JI_MIN_STUN_RATIO)
	{
		return MRES_Supercede;
	}

	float stunDuration = lifetimeRatio * SandmanPreJI_GetBaseStunDuration();
	if (HasEntProp(inflictor, Prop_Send, "m_bCritical") && GetEntProp(inflictor, Prop_Send, "m_bCritical") != 0)
	{
		stunDuration += 2.0;
	}

	int stunFlags = TF_STUNFLAGS_SMALLBONK;
	if (lifetimeRatio >= 1.0)
	{
		stunDuration += 1.0;
		stunFlags = TF_STUNFLAGS_BIGBONK;

		int attacker = GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity");
		if (Weapons_IsClientInGame(attacker) && !IsFakeClient(attacker) && !IsFakeClient(victim)
			&& attacker != victim && GetClientTeam(attacker) != GetClientTeam(victim))
		{
			FireSandmanMoonshot(attacker, victim);
			PrintCenterTextAll("%N moonshot %N!", attacker, victim);
		}
	}

	parameters.Set(1, stunDuration);
	parameters.Set(2, SANDMAN_PRE_JI_SLOWDOWN);
	parameters.Set(3, stunFlags);
	return MRES_ChangedHandled;
}

