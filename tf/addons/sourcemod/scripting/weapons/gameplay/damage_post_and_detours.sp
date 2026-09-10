static float WeaponsGameplay_GetAfterburnRateOnHit(int weapon)
{
	return SDKCall(g_SDKGetAfterburnRateOnHit, weapon);
}

// Set DamageType Ignite compatibility based on nosoop's SM-TFAttributeSupport:
// https://github.com/nosoop/SM-TFAttributeSupport
static void WeaponsGameplay_ApplyDamageTypeIgniteDuration(int weapon, int victim, int attacker)
{
	if (WeaponsGameplay_GetAfterburnRateOnHit(weapon) > 0.0
		|| !TF2_IsPlayerInCondition(victim, TFCond_OnFire))
	{
		return;
	}

	float desiredDuration = TF2Attrib_HookValueFloat(0.0, "set_dmgtype_ignite", weapon);
	if (desiredDuration <= 0.0)
	{
		return;
	}

	float additionalDuration = desiredDuration - TF2Util_GetPlayerBurnDuration(victim);
	if (additionalDuration > 0.0)
	{
		TF2Util_IgnitePlayer(victim, attacker, additionalDuration, weapon);
	}
}

public void WeaponsGameplay_OnTakeDamageAlivePost(
	int victim, int attacker, int inflictor, float damage, int damageType,
	int weapon, const float damageForce[3], const float damagePosition[3], int damageCustom)
{
	if (!WeaponsGameplay_IsEnabled() || !Weapons_IsClientInGame(victim))
	{
		return;
	}

	Escampette_OnDamageTaken(victim, attacker, damage, damagePosition);
	if (!Weapons_IsClientInGame(attacker))
	{
		return;
	}

	int damageWeapon = GetDamageSourceWeapon(0, weapon, inflictor);
	RefillPrimaryClipOnCrit(attacker, victim, damageWeapon, damage, damageType);

	FullPelletIgnite_TryConsumePost(victim, attacker, weapon, inflictor);

	if (damageCustom == TF_CUSTOM_BURNING
		|| weapon <= MaxClients || !IsValidEntity(weapon) || !TF2Util_IsEntityWeapon(weapon))
	{
		return;
	}

	WeaponsGameplay_ApplyDamageTypeIgniteDuration(weapon, victim, attacker);
}

MRESReturn CalculateMaxSpeed(int client, DHookReturn returnValue) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	if (
		client >= 1 &&
		client <= MaxClients &&
		IsValidEntity(client) &&
		IsClientInGame(client)
	) {
		int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (tf2_players[client].huntingRevolverZoomed
			&& HuntingRevolver_IsWeapon(activeWeapon))
		{
			float speed = view_as<float>(returnValue.Value);
			if (speed > HUNTING_REVOLVER_MAX_ZOOM_SPEED)
			{
				returnValue.Value = HUNTING_REVOLVER_MAX_ZOOM_SPEED;
				return MRES_Override;
			}
		}

		switch (TF2_GetPlayerClass(client))
		{
			case TFClass_Scout:
			{
				int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);

				if (primary > MaxClients && IsValidEntity(primary) && TF2CustAttr_GetInt(primary, "original babyface attributes") == 1) {
					// Original BFB proper speed application
					float boost = GetEntPropFloat(client, Prop_Send, "m_flHypeMeter");
					returnValue.Value = view_as<float>(returnValue.Value) * ValveRemapVal(boost, 0.0, 99.0, 1.0, 1.383);
					return MRES_Override;
				}
			}
			case TFClass_Heavy:
			{
				// Steak boosts speed by 35% instead of 30%
				if (
					TF2_IsPlayerInCondition(client, TFCond_CritCola) &&
					view_as<float>(returnValue.Value) < 230.0 * 1.35
				) {
					returnValue.Value = view_as<float>(returnValue.Value) * 1.35 / 1.30;
					return MRES_Override;
				}
			}
			case TFClass_Spy:
			{
				if (Escampette_HasSpeedBonus(client))
				{
					returnValue.Value = view_as<float>(returnValue.Value) * 1.30;
					return MRES_Override;
				}
			}
		}
	}
	return MRES_Ignored;
}

MRESReturn ApplyBiteEffects_Pre(int entity, DHookParam parameters) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int client = parameters.Get(1);
	if (
		client >= 1 &&
		client <= MaxClients
	) {
		tf2_players[client].oldHealth = GetClientHealth(client);
	}
	return MRES_Ignored;
}

MRESReturn ApplyBiteEffects_Post(int entity, DHookParam parameters) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int lunchbox_type = TF2Attrib_HookValueInt(0, "set_weapon_mode", entity);
	int client = parameters.Get(1);
	if (
		client >= 1 &&
		client <= MaxClients &&
		(lunchbox_type == LUNCHBOX_CHOCOLATE_BAR || lunchbox_type == LUNCHBOX_FISHCAKE)
	) {
		int health_cur = GetClientHealth(client);
		int health_gained = health_cur - tf2_players[client].oldHealth;
		if (health_gained < 25) {
			int heal_amt = min(25 - health_gained, DALOKOHS_OVERHEAL - health_cur);
			if (heal_amt > 0) {
				AddPlayerHealth(client, heal_amt);
			}
		}
	}
	return MRES_Ignored;
}

MRESReturn CartDispenseMetal(int entity, DHookReturn returnValue, DHookParam parameters) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int client = parameters.Get(1);
	if (
		client > 0 &&
		client <= MaxClients
	) {
		int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);

		if (secondary > MaxClients && IsValidEntity(secondary)) {
			// Reduced metal yields from Payload carts
			float ammo_mult = TF2CustAttr_GetFloat(secondary, "mult metal from carts", 1.0);

			if (ammo_mult != 1.0) {
				TF2Attrib_AddCustomPlayerAttribute(client, "metal_pickup_decreased", ammo_mult, 0.001);
			}
		}
	}
	return MRES_Ignored;
}

public MRESReturn CanFireCriticalShot_Post(int weapon, DHookReturn hReturn, DHookParam parameters)
{
    if (!WeaponsGameplay_IsEnabled()
		|| weapon <= MaxClients || !IsValidEntity(weapon))
        return MRES_Ignored;

    int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
    if (client <= 0 || client > MaxClients)
        return MRES_Ignored;

	bool isHeadshot = parameters.Get(1);
	if (isHeadshot && Ambassador102_IsEnabledWeapon(weapon))
	{
		hReturn.Value = true;
		return MRES_Override;
	}

	if (!WeaponsGameplay_HasHeadshotFeature(weapon))
		return MRES_Ignored;

	if (!isHeadshot)
	{
		// Preserve the legacy headshot attribute's existing non-headshot behavior.
		if (TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED, 0) != 0)
		{
			hReturn.Value = true;
			return MRES_Override;
		}
		return MRES_Ignored;
	}

	hReturn.Value = WeaponsGameplay_CanHeadshotNow(weapon);
	return MRES_Override;
}

// Gas passer buff is a candidate for removal, it's uninspired and could be more creative
public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return;
	}

	if (condition == TFCond_BlastJumping)
	{
		bool withinDeployWindow = g_flBlastJumpJaratePendingUntil[client] > 0.0
			&& GetGameTime() <= g_flBlastJumpJaratePendingUntil[client];
		int weapon = EntRefToEntIndex(g_iBlastJumpJaratePendingWeapon[client]);
		BlastJumpJarate_ClearPending(client);

		if (withinDeployWindow
			&& Weapons_IsValidWeaponEntity(weapon)
			&& GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == weapon)
		{
			float duration = TF2CustAttr_GetFloat(weapon, ATTR_BLAST_JUMP_JARATE, 0.0);
			if (duration > 0.0)
			{
				TF2_AddCondition(client, TFCond_Jarated, duration);
			}
		}
	}

	if (condition == TFCond_Gas) //If gas is applied
	{
		TF2_AddCondition(client, TFCond_Jarated, 6.0); //Apply Jarate for 6 seconds
	}

	if (condition == TFCond_Cloaked)
	{
		Escampette_RecalculateSpeed(client);
	}

	if (condition == TFCond_Taunting) {
		int secondary = GetPlayerWeaponSlot(client, 1);
		int active = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

		if (active == secondary) {
			float duration = Sproke_GetAttributeDuration(secondary);
			Sproke_TryActivate(client, duration);
		}
	}

	if (
		condition == TFCond_Dazed &&
		abs(GetGameTickCount() - tf2_players[client].bonkFrame) <= 2 &&
		tf2_players[client].bonkFrame > 0
	) {
		// bonk mark for death
		int stun_amt = GetEntProp(client, Prop_Send, "m_iMovementStunAmount");
		float mark_dur = ValveRemapVal(float(stun_amt), 63.0, 127.0, BONK_MARK_FOR_DEATH_MIN, BONK_MARK_FOR_DEATH_MAX);
		TF2_AddCondition(client, TFCond_MarkedForDeathSilent, mark_dur);

		// remove the slowdown
		TF2_RemoveCondition(client, TFCond_Dazed);
	}
}

void WeaponsGameplay_OnConditionRemoved(int client, TFCond condition)
{
	if (condition == TFCond_Cloaked)
	{
		Escampette_RecalculateSpeed(client);
	}
}

