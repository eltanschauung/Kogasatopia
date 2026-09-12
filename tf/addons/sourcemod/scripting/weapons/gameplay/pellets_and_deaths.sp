void ScatterPellets_Debug(const char[] format, any ...)
{
	if (g_hScattergunPelletsDebug == null || !GetConVarBool(g_hScattergunPelletsDebug))
		return;

	char message[256];
	VFormat(message, sizeof(message), format, 2);
	LogMessage("[scattergun_pellets] %s", message);
}

public Action Command_ScatterPelletsStatus(int client, int args)
{
	ReplyToCommand(client, "[Weapons] scattergun_pellets extension: %s", LibraryExists("scattergun_pellets") ? "available" : "unavailable");

	if (Accuracy_IsValidClient(client))
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		char classname[64];
		classname[0] = '\0';
		if (weapon > MaxClients && IsValidEntity(weapon))
		{
			GetEntityClassname(weapon, classname, sizeof(classname));
		}
		ReplyToCommand(client, "[Weapons] active weapon: ent=%d class=%s", weapon, classname);
	}

	return Plugin_Handled;
}

public void TF2Shotgun_OnPelletShot(int attacker, int victim, int pellets, int total, bool kill)
{
	ScatterPellets_Debug("pellet shot: attacker=%d victim=%d pellets=%d total=%d kill=%d", attacker, victim, pellets, total, kill ? 1 : 0);

	if (!WeaponsGameplay_IsEnabled())
	{
		ScatterPellets_Debug("ignored: sm_weapons_gameplay_enabled is 0");
		return;
	}

	if (!Accuracy_IsValidClient(attacker) || !Accuracy_IsValidClient(victim) || attacker == victim)
	{
		ScatterPellets_Debug("ignored: invalid attacker/victim");
		return;
	}
	if (GetClientTeam(attacker) <= 1
		|| GetClientTeam(victim) <= 1
		|| GetClientTeam(attacker) == GetClientTeam(victim))
	{
		ScatterPellets_Debug("ignored: friendly/noncombat target");
		return;
	}
	if (g_bAccuracyExploding[attacker])
	{
		ScatterPellets_Debug("ignored: accuracy explosion in progress");
		return;
	}

	if (total < MEATSHOT_MIN_PELLETS)
	{
		ScatterPellets_Debug("ignored: shot fired fewer than %d pellets", MEATSHOT_MIN_PELLETS);
		return;
	}

	if (pellets > FLAME_SHOTGUN_FULL_PELLET_THRESHOLD) // 7/10, this is only for the flame shotgun, virtually 7/9
			Accuracy_OnFlameShotgunStack(attacker, victim);

	if (pellets < total)
	{
		ScatterPellets_Debug("ignored: not a full pellet shot");
		return;
	}

	if (g_hMeatshotDebug.BoolValue && !IsFakeClient(attacker))
	{
		PrintToChat(attacker, "[debug] You got a meatshot!");
	}

	if (!kill || IsFakeClient(attacker) || IsFakeClient(victim))
	{
		return;
	}

	FireMeatshotKill(attacker, victim);

}

int Accuracy_GetClassSubtractionValue(int client)
{
	TFClassType cls = TF2_GetPlayerClass(client);
	switch (cls)
	{
		case TFClass_Scout:
			return 65;
		case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan, TFClass_Engineer:
			return 68;
		case TFClass_Heavy, TFClass_Medic, TFClass_Sniper, TFClass_Spy:
			return 75;
		default:
			return 0;
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return Plugin_Continue;
	}

	int userId = event.GetInt("userid");
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Continue;
	WeaponsMovement_OnPlayerDeath(client);

	BlastJumpJarate_ClearPending(client);
	Sproke_ClearEffect(client, false, true);
	HuntingRevolver_ResetClient(client);
	Harvester_ClearState(client);
	ShockCharge_StopTimer(client);
	tf2_players[client].shockCharge = 30;
	tf2_players[client].accuracyStreak = 0;
	tf2_players[client].accuracyStreakExpiresAt = 0.0;
	SecondaryDamageRefill_Reset(client);

	VitaSaw_CacheCharge(client, false);

	int attackerId = event.GetInt("attacker");
	int attacker = GetClientOfUserId(attackerId);
	bool worldDeath = IsWorldInflictedDeath(event);
	int environmentalAttacker = GetClientOfUserId(g_iEnvironmentalKillAttackerUserId[client]);
	if (worldDeath
		&& environmentalAttacker > 0
		&& IsClientInGame(environmentalAttacker)
		&& !IsFakeClient(environmentalAttacker)
		&& GetClientTeam(environmentalAttacker) != GetClientTeam(client)
		&& GetGameTime() - g_fEnvironmentalKillTime[client] <= ENVIRONMENTAL_KILL_CREDIT_WINDOW)
	{
		FireEnvironmentalKill(environmentalAttacker, client);
	}
	g_iEnvironmentalKillAttackerUserId[client] = 0;
	g_fEnvironmentalKillTime[client] = 0.0;

	if (attacker == 0)
	{
		return Plugin_Continue;
	}

	int killWeapon = DamageSource_GetKillingWeapon(attacker, client);
	TryAwardAmbassadorHeadshotKill(event, attacker, client, killWeapon);

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		if (attacker != client
			&& GetClientTeam(attacker) > 1
			&& GetClientTeam(client) > 1
			&& GetClientTeam(attacker) != GetClientTeam(client))
		{
			WearerRefillSecondaryClipOnKill(attacker);
		}

		if (Weapons_IsValidWeaponEntity(killWeapon))
		{
			ReloadOnKill_OnKill(killWeapon);
			RefillPrimaryClipOnKill(attacker, killWeapon);
		}
	}

	if (tf2_players[attacker].scytheWeapon != 0
		&& GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") <= 0
		&& TF2_IsPlayerInCondition(client, TFCond_OnFire))
	{
		Harvester_AddHealCount(attacker, ATTR_HARVESTER_HEALING_COUNT);
	}

	if (tf2_players[client].scytheWeapon != 0 && TF2_IsPlayerInCondition(attacker, TFCond_OnFire))
	{
		if (TF2_IsPlayerInCondition(attacker, TFCond_OnFire))
		{
			TF2_RemoveCondition(attacker, TFCond_OnFire);
			int targets[2];
			targets[0] = client;
			targets[1] = attacker;
			for (int i = 0; i < 2; i++)
			{
				EmitSoundToClient(
					targets[i],
					SOUND_FLAME_OUT,
					SOUND_FROM_PLAYER,
					SNDCHAN_AUTO,
					SNDLEVEL_NORMAL,
					SND_NOFLAGS,
					0.4,
					SNDPITCH_NORMAL
				);
			}
		}
	}
	return Plugin_Continue;
}
