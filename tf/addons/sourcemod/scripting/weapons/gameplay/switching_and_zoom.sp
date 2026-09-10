public Action Timer_HealTimer(Handle timer, any userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client)
		|| tf2_players[client].harvesterHealTimer != timer)
	{
		return Plugin_Stop;
	}
	if (!WeaponsGameplay_IsEnabled())
	{
		tf2_players[client].harvesterHealTimer = null;
		return Plugin_Stop;
	}

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsPlayerAlive(client) || !Harvester_IsWeapon(activeWeapon))
	{
		tf2_players[client].harvesterHealTimer = null;
		return Plugin_Stop;
	}

	bool directHealBlocked = tf2_players[client].lastHarvesterDirectHealTime >= 0.0
		&& GetGameTime() - tf2_players[client].lastHarvesterDirectHealTime < HARVESTER_DIRECT_HEAL_BLOCK_TIME;
	if (!directHealBlocked
		&& tf2_players[client].healCount > 0
		&& GetClientHealth(client) < TF2_GetPlayerMaxHealth(client))
	{
		tf2_players[client].healCount--;
		AddPlayerHealth(client, ATTR_HARVESTER_HEALING, 1.0, false, true);
		ClientCommand(client, "playgamesound ui/item_metal_tiny_pickup.wav");
		Harvester_ShowHealHint(client);
	}

	return Plugin_Continue;
}

public Action Timer_ClearHarvesterHint(Handle timer, any userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client)
		|| tf2_players[client].harvesterHintTimer != timer)
	{
		return Plugin_Stop;
	}

	tf2_players[client].harvesterHintTimer = null;
	Harvester_ClearHealHint(client);
	return Plugin_Stop;
}

public Action Timer_ShockCharge(Handle timer, any userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client)
		|| tf2_players[client].shockChargeTimer != timer)
	{
		return Plugin_Stop;
	}
	if (!WeaponsGameplay_IsEnabled())
	{
		tf2_players[client].shockChargeTimer = null;
		return Plugin_Stop;
	}

	if (tf2_players[client].shockCharge >= 30)
	{
		tf2_players[client].shockChargeTimer = null;
		return Plugin_Stop;
	}

	tf2_players[client].shockCharge++;
	if (tf2_players[client].shockCharge % 2 == 0 || tf2_players[client].shockCharge == 1)
	{
		PrintHintText(client, "Shock Charge: %i%%%", (tf2_players[client].shockCharge * 100 / 30));
	}

	if (tf2_players[client].shockCharge >= 30)
	{
		tf2_players[client].shockChargeTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

static bool TryApplyHolsterReload(int weapon)
{
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return false;
	}

	int maxClip = TF2CustAttr_GetInt(weapon, "holster reload");
	if (maxClip <= 0)
	{
		return false;
	}

	int clip = GetClip(weapon);
	if (clip < 0 || clip >= maxClip)
	{
		return false;
	}

	int reserve = GetAmmo_Weapon(weapon);
	if (reserve <= 0)
	{
		return false;
	}

	int missing = maxClip - clip;
	int toReload = (missing < reserve) ? missing : reserve;
	if (toReload <= 0)
	{
		return false;
	}

	SetClip_Weapon(weapon, clip + toReload);
	SetAmmo_Weapon(weapon, reserve - toReload);
	return true;
}

void BlastJumpJarate_ClearPending(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	g_iBlastJumpJaratePendingWeapon[client] = INVALID_ENT_REFERENCE;
	g_flBlastJumpJaratePendingUntil[client] = 0.0;
}

static void BlastJumpJarate_OnDeploy(int client, int weapon)
{
	if (!Weapons_IsClientInGame(client)
		|| !Weapons_IsValidWeaponEntity(weapon))
	{
		return;
	}

	float duration = TF2CustAttr_GetFloat(weapon, ATTR_BLAST_JUMP_JARATE, 0.0);
	if (duration <= 0.0)
		return;

	if (TF2_IsPlayerInCondition(client, TFCond_BlastJumping))
	{
		TF2_AddCondition(client, TFCond_Jarated, duration);
		return;
	}

	g_iBlastJumpJaratePendingWeapon[client] = EntIndexToEntRef(weapon);
	g_flBlastJumpJaratePendingUntil[client] = GetGameTime() + 0.15;
}

public Action OnWeaponSwitch(int client, int weapon)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return Plugin_Continue;
	}

	int previousWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon != previousWeapon)
	{
		BlastJumpJarate_ClearPending(client);

		if (tf2_players[client].huntingRevolverWeaponRef != INVALID_ENT_REFERENCE
			|| HuntingRevolver_IsWeapon(previousWeapon))
		{
			HuntingRevolver_ResetClient(client, previousWeapon);
		}

		if (HuntingRevolver_IsWeapon(weapon))
		{
			HuntingRevolver_RecognizeWeapon(client, weapon);
		}

		BlastJumpJarate_OnDeploy(client, weapon);
	}
	if (weapon != previousWeapon)
	{
		if (Harvester_IsWeapon(weapon))
		{
			Harvester_StartHealTimer(client);
		}
		else if (Harvester_IsWeapon(previousWeapon))
		{
			Harvester_StopHealTimer(client);
		}
	}
	if (weapon != previousWeapon && GetEntProp(client, Prop_Send, "m_iRevengeCrits") > 0)
	{
		if (Harvester_IsWeapon(previousWeapon) && !Harvester_IsWeapon(weapon))
		{
			Harvester_SetCritBoost(client, false);
		}
		else if (Harvester_IsWeapon(weapon))
		{
			Harvester_SetCritBoost(client, true);
		}
	}
	TryApplyHolsterReload(previousWeapon);

	if (weapon != previousWeapon)
	{
		TryApplyHolsterReload(weapon);
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(
	int client,
	int &buttons,
	int &impulse,
	float velocity[3],
	float angles[3],
	int &weapon,
	int &subtype,
	int &commandNumber,
	int &tickCount,
	int &randomSeed,
	int mouse[2])
{
	if (!WeaponsGameplay_IsEnabled() || !Weapons_IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	bool trackedActiveWeapon = tf2_players[client].huntingRevolverWeaponRef != INVALID_ENT_REFERENCE
		&& tf2_players[client].huntingRevolverWeaponRef != 0
		&& EntRefToEntIndex(tf2_players[client].huntingRevolverWeaponRef) == activeWeapon;
	if (!trackedActiveWeapon && !HuntingRevolver_IsWeapon(activeWeapon))
	{
		if (tf2_players[client].huntingRevolverWeaponRef != INVALID_ENT_REFERENCE)
		{
			HuntingRevolver_ResetClient(client);
		}
		return Plugin_Continue;
	}

	if (!trackedActiveWeapon)
	{
		HuntingRevolver_RecognizeWeapon(client, activeWeapon);
	}

	bool attack2 = (buttons & IN_ATTACK2) != 0;
	bool jumping = GetEntProp(client, Prop_Send, "m_bJumping") != 0;
	if (attack2 && !tf2_players[client].huntingRevolverAttack2Held)
	{
		if (tf2_players[client].huntingRevolverZoomed)
		{
			HuntingRevolver_SetZoom(client, false);
		}
		else if (!jumping)
		{
			HuntingRevolver_SetZoom(client, true);
		}
	}
	tf2_players[client].huntingRevolverAttack2Held = attack2;

	bool commandChanged = false;
	if (attack2)
	{
		buttons &= ~IN_ATTACK2;
		commandChanged = true;
	}

	return commandChanged ? Plugin_Changed : Plugin_Continue;
}

public void HuntingRevolver_OnPostThinkPost(int client)
{
	if (!WeaponsGameplay_IsEnabled()
		|| !Weapons_IsClientInGame(client)
		|| !IsPlayerAlive(client)
		|| !tf2_players[client].huntingRevolverZoomed
		|| GetEntProp(client, Prop_Send, "m_bJumping") == 0)
	{
		return;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (HuntingRevolver_IsWeapon(weapon)
		&& EntRefToEntIndex(tf2_players[client].huntingRevolverWeaponRef) == weapon)
	{
		HuntingRevolver_SetZoom(client, false);
	}
}

bool HuntingRevolver_IsWeapon(int weapon)
{
	if (!IsValidWeaponEntity(weapon))
	{
		return false;
	}

	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	return StrEqual(classname, "tf_weapon_revolver")
		&& TF2CustAttr_GetInt(weapon, ATTR_HUNTING_REVOLVER, 0) != 0;
}

static void HuntingRevolver_RecognizeWeapon(int client, int weapon)
{
	int weaponRef = EntIndexToEntRef(weapon);
	if (tf2_players[client].huntingRevolverWeaponRef == weaponRef)
	{
		return;
	}

	HuntingRevolver_ResetClient(client);
	tf2_players[client].huntingRevolverWeaponRef = weaponRef;
}

static void HuntingRevolver_RecalculateSpeed(int client)
{
	if (g_SDKTeamFortressSetSpeed == null || !Weapons_IsValidPlayerIndex(client) || !IsClientInGame(client))
	{
		return;
	}

	SDKCall(g_SDKTeamFortressSetSpeed, client);
}

static void HuntingRevolver_SetFOV(int client, int fov)
{
	if (g_SDKSetFOV == null || !Weapons_IsValidPlayerIndex(client) || !IsClientInGame(client))
	{
		return;
	}

	SDKCall(g_SDKSetFOV, client, client, fov, HUNTING_REVOLVER_ZOOM_TIME, 0);
}

static void HuntingRevolver_SetZoom(int client, bool enabled)
{
	tf2_players[client].huntingRevolverZoomed = enabled;
	tf2_players[client].huntingRevolverZoomReadyTime = enabled
		? GetGameTime() + HUNTING_REVOLVER_ZOOM_TIME
		: 0.0;
	HuntingRevolver_SetFOV(client, enabled ? HUNTING_REVOLVER_FOV : 0);
	HuntingRevolver_RecalculateSpeed(client);
}

void HuntingRevolver_ResetClient(int client, int knownWeapon = -1)
{
	if (!Weapons_IsValidPlayerIndex(client))
	{
		return;
	}

	bool hasTrackedWeapon = tf2_players[client].huntingRevolverWeaponRef != INVALID_ENT_REFERENCE
		&& tf2_players[client].huntingRevolverWeaponRef != 0;
	bool customContext = hasTrackedWeapon
		|| tf2_players[client].huntingRevolverZoomed
		|| tf2_players[client].huntingRevolverAttack2Held
		|| HuntingRevolver_IsWeapon(knownWeapon);

	tf2_players[client].huntingRevolverZoomed = false;
	tf2_players[client].huntingRevolverZoomReadyTime = 0.0;
	if (customContext && IsClientInGame(client))
	{
		HuntingRevolver_SetFOV(client, 0);
		HuntingRevolver_RecalculateSpeed(client);
	}

	tf2_players[client].huntingRevolverAttack2Held = false;
	tf2_players[client].huntingRevolverWeaponRef = INVALID_ENT_REFERENCE;
}

