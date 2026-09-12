static bool HasTakeMinicritsProjectileAirborne(int client)
{
	if (!Weapons_IsClientInGame(client))
		return false;

	for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (!Weapons_IsValidWeaponEntity(weapon))
			continue;

		if (TF2CustAttr_GetInt(weapon, ATTR_TAKE_MINICRITS_PROJECTILE_AIRBORNE, 0) != 0)
			return true;
	}

	return false;
}


public Action TF2_OnTakeDamage(
	int victim,
	int &attacker,
	int &inflictor,
	float &damage,
	int &damageType,
	int &weapon,
	float damageForce[3],
	float damagePosition[3],
	int damageCustom,
	CritType &critType)
{
	if (!WeaponsGameplay_IsEnabled()
		|| !Weapons_IsClientInGame(victim)
		|| !Weapons_IsClientInGame(attacker)
		|| attacker == victim
		|| damage <= 0.0
		|| GetClientTeam(victim) <= 1
		|| GetClientTeam(attacker) <= 1
		|| GetClientTeam(victim) == GetClientTeam(attacker))
	{
		return Plugin_Continue;
	}

	if (!HasTakeMinicritsProjectileAirborne(victim)
		|| (GetEntityFlags(victim) & FL_ONGROUND))
	{
		return Plugin_Continue;
	}

	if (inflictor <= MaxClients
		|| !IsValidEntity(inflictor)
		|| !HasEntProp(inflictor, Prop_Send, "m_hLauncher")
		|| !DamageSource_IsProjectileDirectHit(victim, inflictor))
	{
		return Plugin_Continue;
	}

	if (critType == CritType_None)
	{
		critType = CritType_MiniCrit;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!WeaponsGameplay_IsEnabled()
		|| client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	bool damageChanged = false;
	if (inflictor > MaxClients && IsValidEntity(inflictor) && (damagetype & DMG_BULLET))
	{
		char classname[32];
		GetEntityClassname(inflictor, classname, sizeof(classname));
		if (StrEqual(classname, "obj_sentrygun"))
		{
			damagetype |= DMG_PREVENT_PHYSICS_FORCE;
			damageChanged = true;
		}
	}

	if (damage > 0.0
		&& attacker >= 1 && attacker <= MaxClients
		&& IsClientInGame(attacker)
		&& !IsFakeClient(client) && !IsFakeClient(attacker)
		&& client != attacker
		&& GetClientTeam(client) != GetClientTeam(attacker))
	{
		g_iEnvironmentalKillAttackerUserId[client] = GetClientUserId(attacker);
		g_fEnvironmentalKillTime[client] = GetGameTime();
	}
	if (attacker < 1) return damageChanged ? Plugin_Changed : Plugin_Continue;

	bool attackerIsPlayer = (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker));
	if (attackerIsPlayer && inflictor == attacker && CheckIfAfterburn(damagecustom))
	{
		Harvester_OnAfterburnDamage(attacker);
	}

	int damageWeapon = GetDamageSourceWeapon(attacker, weapon, inflictor);
	int directDamageWeapon = GetDamageSourceWeapon(0, weapon, inflictor);
	if (attackerIsPlayer
		&& damage > 0.0
		&& client != attacker
		&& GetClientTeam(client) > 1
		&& GetClientTeam(attacker) > 1
		&& GetClientTeam(client) != GetClientTeam(attacker))
	{
		DamageSource_RecordPotentialKill(attacker, client, directDamageWeapon);
	}
	if (attackerIsPlayer
		&& damageWeapon > MaxClients
		&& IsValidEntity(damageWeapon)
		&& inflictor == attacker
		&& (damagetype & (DMG_BULLET | DMG_BUCKSHOT))
		&& TF2CustAttr_GetInt(damageWeapon, ATTR_HITSCAN_NO_DAMAGE_PHYSICS, 0) != 0)
	{
		damagetype |= DMG_PREVENT_PHYSICS_FORCE;
		damageChanged = true;
	}

	FullPelletIgnite_TryMark(attacker, client, damageWeapon);
	if (attackerIsPlayer
		&& damage > 0.0
		&& client != attacker
		&& GetClientTeam(client) != GetClientTeam(attacker)
		&& directDamageWeapon > MaxClients
		&& IsValidEntity(directDamageWeapon)
		&& Harvester_IsWeapon(directDamageWeapon)
		&& GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") > 0
		&& !tf2_players[attacker].harvesterCritConsumePending)
	{
		tf2_players[attacker].harvesterCritConsumePending = true;
		RequestFrame(Harvester_ConsumeRevengeCrit, GetClientUserId(attacker));
	}

	if (attackerIsPlayer && damageWeapon > MaxClients && IsValidEntity(damageWeapon))
	{
		SecondaryDamageRefill_OnDamage(attacker, damage);
		ReloadOnHit_OnDamage(damageWeapon);
		if (damage > 0.0
			&& client != attacker
			&& GetClientTeam(client) > 1
			&& GetClientTeam(attacker) > 1
			&& GetClientTeam(client) != GetClientTeam(attacker))
		{
			RefillClipOnHit_OnDamage(damageWeapon);
			RefillSecondaryClipOnHit_OnDamage(attacker, damageWeapon);
			WeaponsSound_PlayOnHit(client, damageWeapon);
			WeaponsSound_PlayWearerOnHit(client, attacker);
			WeaponsSound_PlayCustomHitsound(attacker, directDamageWeapon);
			WeaponsSound_PlayCustomMeleeHit(attacker, directDamageWeapon);
		}

		// Resolve duel damage without falling back to the attacker's active weapon.
		int duelWeapon = GetDamageSourceWeapon(0, weapon, inflictor);
		if (duelWeapon > MaxClients && IsValidEntity(duelWeapon))
		{
			int victimWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
			if (victimWeapon > MaxClients && IsValidEntity(victimWeapon))
			{
				if (TF2CustAttr_GetInt(duelWeapon, "duel declared", 0) != 0
					&& TF2CustAttr_GetInt(victimWeapon, "duel declared", 0) != 0)
				{
					damagetype |= DMG_CRIT;
					return Plugin_Changed;
				}
				if (TF2CustAttr_GetInt(duelWeapon, "duel declared revolver", 0) != 0
					&& TF2CustAttr_GetInt(victimWeapon, "duel declared revolver", 0) != 0
					&& GetClip(duelWeapon) == 6)
				{
					damage = 100.0;
					damagetype |= DMG_CRIT;
					return Plugin_Changed;
				}
			}
		}
	}

	bool validWeapon = (weapon > MaxClients && IsValidEntity(weapon));
	int wepindex = (validWeapon ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") : -1);

	if (damagecustom == SANDMAN_DAMAGE_CUSTOM)
	{
		Action sandmanAction = SandmanPreJI_OnBaseballDamage(client, attacker, weapon, inflictor, damage);
		return damageChanged && sandmanAction == Plugin_Continue ? Plugin_Changed : sandmanAction;
	}

	if (wepindex == 442 || wepindex == 588)	 // Pomson, bison
	{
		float mult = 1.0;
		if (wepindex == 442)
		{
			mult = GetConVarFloat(g_hBisonDamageMult);
		}
		else
		{
			mult = GetConVarFloat(g_hPomsonDamageMult);
		}
		damage *= mult;
		// Remove bullet damage type (ignores bullet resist from e.g. Vaccinator) and restore knockback
		damagetype &= ~(DMG_BULLET | DMG_PREVENT_PHYSICS_FORCE);
		// Enable sonic flag so ranged resist attrib still works
		damagetype |= DMG_SONIC;
		return Plugin_Changed;
	}

	if (wepindex == 307) { //Ullapool Caber weapon index
		if (client == attacker) {
			damage = 50.0;
			return Plugin_Changed;
		} else if (damagecustom == 0) {
			damage = 35.00;
			return Plugin_Changed;
		} else if (damagecustom == 42) {
			damagetype|=TF_WEAPON_GRENADE_DEMOMAN;
			if (TF2_IsPlayerInCondition(attacker, TFCond_BlastJumping)) {
				damage = 175.00;
				damagetype|=DMG_CRIT;
				return Plugin_Changed;
			} else {
				damage = 90.00;
				return Plugin_Changed;
			}
		}
	} else if ((wepindex == 812 || wepindex == 833) && damage > 40.0) { // Cleavers
		if (TF2_IsPlayerInCondition(client, TFCond_Dazed) && !(damagetype & DMG_CRIT)) { // if stunned
			damage = 33.3;
			damagetype|=DMG_CRIT;
			TryAwardSandmanCleaverCombo(attacker, client);
			return Plugin_Changed;
		}
	} else {
		if (!validWeapon) {
			return damageChanged ? Plugin_Changed : Plugin_Continue;
		}

		if (TF2CustAttr_GetInt(weapon, "shock therapy attributes") != 0) {
			damage = float(tf2_players[attacker].shockCharge * 100 / 30);
			tf2_players[attacker].shockCharge = 0;
			ShockCharge_StartTimer(attacker);
			EmitAmbientSound(SOUND_NEON_SIGN, damagePosition, client, SNDLEVEL_NORMAL);
			return Plugin_Changed;
		} else if (TF2CustAttr_GetInt(weapon, "hitscan ignite targets") != 0) {
			float victimPos[3];
			float attackerPos[3];
			GetClientAbsOrigin(client, victimPos);
			GetClientAbsOrigin(attacker, attackerPos);
			if (GetVectorDistance(victimPos, attackerPos) <= 1024.0) {
				TF2_IgnitePlayer(client, attacker, 4.0);
				return Plugin_Changed;
			}
		return damageChanged ? Plugin_Changed : Plugin_Continue;
		}
	}
		
	return damageChanged ? Plugin_Changed : Plugin_Continue;
}

bool IsWorldInflictedDeath(Event event)
{
	char weapon[64];
	char weaponLogClassname[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	event.GetString("weapon_logclassname", weaponLogClassname, sizeof(weaponLogClassname));
	if (StrEqual(weapon, "world", false) || StrEqual(weaponLogClassname, "world", false))
	{
		return true;
	}

	if (event.GetInt("attacker") != 0)
	{
		return false;
	}

	int inflictor = event.GetInt("inflictor_entindex");
	if (inflictor == 0)
	{
		return true;
	}

	if (inflictor > MaxClients && IsValidEntity(inflictor))
	{
		char classname[64];
		GetEntityClassname(inflictor, classname, sizeof(classname));
		if (StrEqual(classname, "worldspawn", false) || StrEqual(classname, "trigger_hurt", false))
		{
			return true;
		}
	}

	return false;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    if (!WeaponsGameplay_IsEnabled()
		|| !Accuracy_IsValidClient(attacker) || !IsPlayerAlive(attacker))
        return Plugin_Continue;

	if (damagetype & DMG_BULLET)
	{
		int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if (weapon > MaxClients && IsValidEntity(weapon))
		{
			if (TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED_WHILE_ZOOMED, 0) != 0)
			{
				if (WeaponsGameplay_CanHeadshotNow(weapon))
				{
					damagetype |= DMG_USE_HITLOCATIONS;
				}
				else
				{
					damagetype &= ~DMG_USE_HITLOCATIONS;
				}
				return Plugin_Changed;
			}

			if (WeaponsGameplay_CanHeadshotNow(weapon))
			{
				damagetype |= DMG_USE_HITLOCATIONS;
				return Plugin_Changed;
			}
		}
	}

    if (GetClientTeam(victim) != GetClientTeam(attacker))
        return Plugin_Continue;

    if (CheckShock(attacker) != 2)
        return Plugin_Continue;

    int buff = OverhealStruct(victim);
    int health = GetClientHealth(victim);
    if (health >= buff)
        return Plugin_Continue;

    int medigun = GetPlayerWeaponSlot(attacker, 1);
    if (!IsValidEntity(medigun))
        return Plugin_Continue;

    float pos[3];
    GetClientAbsOrigin(victim, pos);  // was GetClientAbsAngles — wrong data
    TF2_SetHealth(victim, buff);
    tf2_players[attacker].shockCharge = 0;
    ShockCharge_StartTimer(attacker);
    EmitAmbientSound(SOUND_ARROW_HEAL, pos, victim, SNDLEVEL_NORMAL);

    float uber = (float(buff - health) / 5000.0) + GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
    SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", uber);

    return Plugin_Continue;
}

public Action OnTakeDamageAlive(
	int victim, int& attacker, int& inflictor, float& damage, int& damage_type,
	int& weapon, float damage_force[3], float damage_position[3], int damage_custom
) {

	if (!WeaponsGameplay_IsEnabled()
		|| !Accuracy_IsValidClient(attacker) || weapon < 1)
	{
		return Plugin_Continue;
	}
	bool validWeapon = (weapon > MaxClients && IsValidEntity(weapon));
	Action ambassador102Action = Ambassador102_OnHeadshotDamage(victim, attacker, weapon, damage, damage_type, damage_custom);
	if (ambassador102Action != Plugin_Continue)
		return ambassador102Action;

	ScattergunKnockback_OnDamage(victim, attacker, weapon, damage, damage_type);

	if (
		validWeapon &&
		damage > 0 &&
		victim != attacker &&
		inflictor == attacker &&
		TF2CustAttr_GetInt(weapon, "taser damage becomes metal") == 1
	) {
		if (TF2_GetPlayerClass(attacker) == TFClass_Engineer && g_iMetalOffset != -1)
		{
			int attackerMetal = TF_GetMetalAmount(attacker);
			int credit = RoundFloat(damage);
			if (attackerMetal + credit > 200)
				credit = 200 - attackerMetal;
			if (credit > 0)
			{
				TF_SetMetalAmount(attacker, attackerMetal + credit);
			}
		}
	}
	
	if (validWeapon && TF2CustAttr_GetInt(weapon, "mark for death multiple") != 0)
	{
		bool shift_array = true;

		// Do not shift the mark victim array if the current victim is present there already
		for (int i = 0; i < FAN_O_WAR_MAX_MARK_COUNT; i++)
		{
			if (tf2_players[attacker].markVictims[i] == victim)
			{
				shift_array = false;
				break;
			}
		}

		if (shift_array)
		{
			// Shift mark victim array by one
			for (int i = FAN_O_WAR_MAX_MARK_COUNT; i > 0; i--)
			{
				tf2_players[attacker].markVictims[i] = tf2_players[attacker].markVictims[i-1];
			}

			tf2_players[attacker].markVictims[0] = victim;

			// If last victim in the array has the mark condition, remove it
			int lastvictim = tf2_players[attacker].markVictims[FAN_O_WAR_MAX_MARK_COUNT];
			if (lastvictim >= 1 && lastvictim <= MaxClients && IsClientInGame(lastvictim))
			{
				TF2_RemoveCondition(lastvictim, TFCond_MarkedForDeath);
			}
		}
		
		// Mark the player we attacked
		TF2_AddCondition(victim, TFCond_MarkedForDeath, 15.0, attacker);
	}

	if (damage_custom == TF_CUSTOM_CANNONBALL_PUSH)
	{
		// This should prevent loose cannon causing a stun
		TF2_AddCondition(victim, TFCond_KnockedIntoAir, 0.001);
	}

	return Plugin_Continue;
}
