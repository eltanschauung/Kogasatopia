bool Harvester_IsEligibleClient(int client)
{
	return Weapons_IsClientInGame(client) && TF2_GetPlayerClass(client) == TFClass_Pyro;
}

void Harvester_ClearState(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
	{
		return;
	}

	Harvester_StopHealTimer(client);
	Harvester_StopHintTimer(client);
	Harvester_ClearRevengeCrit(client);
	tf2_players[client].scytheWeapon = 0;
	tf2_players[client].healCount = 0;
	tf2_players[client].lastHarvesterDirectHealTime = -1.0;
}

bool Harvester_IsWeapon(int weapon)
{
	return IsValidWeaponEntity(weapon)
		&& TF2CustAttr_GetInt(weapon, "harvester attributes", 0) == 1;
}

void Harvester_AddHealCount(int client, int amount)
{
	if (!Harvester_IsEligibleClient(client) || amount <= 0
		|| Harvester_HasRevengeCrit(client))
	{
		return;
	}

	tf2_players[client].healCount += amount;
	if (tf2_players[client].healCount >= HARVESTER_HEAL_COUNT_MAX)
	{
		Harvester_SetRevengeCrit(client);
		tf2_players[client].healCount = 0;
	}
	Harvester_ShowHealHint(client);
}

void Harvester_OnAfterburnDamage(int client)
{
	if (!Harvester_IsEligibleClient(client) || !IsPlayerAlive(client))
	{
		return;
	}

	tf2_players[client].scytheWeapon = CheckScythe(client);
	if (tf2_players[client].scytheWeapon == 0)
	{
		return;
	}

	Harvester_AddHealCount(client, ATTR_HARVESTER_AFTERBURN_HEALING_COUNT);
	if (tf2_players[client].scytheWeapon != 2)
	{
		return;
	}

	int healthBefore = GetClientHealth(client);
	AddPlayerHealth(client, 4, 1.0, false, true);
	if (GetClientHealth(client) > healthBefore)
	{
		tf2_players[client].lastHarvesterDirectHealTime = GetGameTime();
	}
}

void Harvester_StartHealTimer(int client)
{
	if (!Harvester_IsEligibleClient(client) || !IsPlayerAlive(client) || !WeaponsGameplay_IsEnabled()
		|| tf2_players[client].harvesterHealTimer != null)
	{
		return;
	}

	tf2_players[client].harvesterHealTimer = CreateTimer(
		HARVESTER_HEAL_TIMER_INTERVAL,
		Timer_HealTimer,
		GetClientUserId(client),
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Harvester_StopHealTimer(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
	{
		return;
	}

	if (tf2_players[client].harvesterHealTimer != null)
	{
		KillTimer(tf2_players[client].harvesterHealTimer);
		tf2_players[client].harvesterHealTimer = null;
	}
}

void Harvester_ShowHealHint(int client)
{
	if (!Harvester_IsEligibleClient(client) || !WeaponsGameplay_IsEnabled())
	{
		return;
	}

	if (tf2_players[client].harvesterHintTimer != null)
	{
		KillTimer(tf2_players[client].harvesterHintTimer);
		tf2_players[client].harvesterHintTimer = null;
	}

	if (Harvester_HasRevengeCrit(client))
	{
		PrintHintText(client, "Heal count: revenge");
	}
	else
	{
		PrintHintText(client, "Heal count: %d/%d",
			tf2_players[client].healCount, HARVESTER_HEAL_COUNT_MAX);
	}
	tf2_players[client].harvesterHealHintVisible = true;
	tf2_players[client].harvesterHintTimer = CreateTimer(
		HARVESTER_HINT_DURATION,
		Timer_ClearHarvesterHint,
		GetClientUserId(client),
		TIMER_FLAG_NO_MAPCHANGE);
}

void Harvester_ClearHealHint(int client)
{
	if (tf2_players[client].harvesterHealHintVisible)
	{
		if (IsClientInGame(client))
		{
			PrintHintText(client, "");
		}
		tf2_players[client].harvesterHealHintVisible = false;
	}
}

static void Harvester_StopHintTimer(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
	{
		return;
	}

	if (tf2_players[client].harvesterHintTimer != null)
	{
		KillTimer(tf2_players[client].harvesterHintTimer);
		tf2_players[client].harvesterHintTimer = null;
	}
	Harvester_ClearHealHint(client);
}

void Harvester_SyncHealTimer(int client)
{
	if (!Harvester_IsEligibleClient(client))
	{
		Harvester_ClearState(client);
		return;
	}
	if (!IsPlayerAlive(client) || !WeaponsGameplay_IsEnabled())
	{
		Harvester_StopHealTimer(client);
		return;
	}

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (Harvester_IsWeapon(activeWeapon))
	{
		Harvester_StartHealTimer(client);
	}
	else
	{
		Harvester_StopHealTimer(client);
	}
}

public void Harvester_FrameSyncHealTimer(any userId)
{
	int client = GetClientOfUserId(userId);
	if (client > 0)
	{
		if (!Harvester_IsEligibleClient(client) || CheckScythe(client) == 0)
		{
			Harvester_ClearState(client);
			return;
		}
		Harvester_SyncHealTimer(client);
	}
}

void ShockCharge_StartTimer(int client)
{
	if (!IsClientInGame(client) || !WeaponsGameplay_IsEnabled() || tf2_players[client].shockCharge >= 30
		|| tf2_players[client].shockChargeTimer != null)
	{
		return;
	}

	tf2_players[client].shockChargeTimer = CreateTimer(
		0.5,
		Timer_ShockCharge,
		GetClientUserId(client),
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ShockCharge_StopTimer(int client)
{
	if (!Weapons_IsValidPlayerIndex(client) || tf2_players[client].shockChargeTimer == null)
	{
		return;
	}

	KillTimer(tf2_players[client].shockChargeTimer);
	tf2_players[client].shockChargeTimer = null;
}

void Harvester_SetCritBoost(int client, bool enabled)
{
	if (enabled)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
		{
			return;
		}

		if (TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged))
		{
			if (TF2Util_GetPlayerConditionProvider(client, TFCond_Kritzkrieged) != client)
				tf2_players[client].harvesterCritBoostApplied = false;
			return;
		}
		TF2_AddCondition(client, TFCond_Kritzkrieged, TFCondDuration_Infinite, client);
		tf2_players[client].harvesterCritBoostApplied = true;
		return;
	}

	if (tf2_players[client].harvesterCritBoostApplied)
	{
		if (IsClientInGame(client)
			&& TF2Util_GetPlayerConditionProvider(client, TFCond_Kritzkrieged) == client)
		{
			TF2_RemoveCondition(client, TFCond_Kritzkrieged);
		}
		tf2_players[client].harvesterCritBoostApplied = false;
	}
}

static void Harvester_SetRevengeCrit(int client)
{
	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (!Harvester_IsWeapon(weapon)) return;
	tf2_players[client].harvesterRevengeReady = true;
	tf2_players[client].harvesterRevengeWeaponRef = EntIndexToEntRef(weapon);
	tf2_players[client].harvesterRevengeGeneration++;
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	Harvester_SetCritBoost(client, Harvester_IsWeapon(activeWeapon));
}

static void Harvester_ClearRevengeCrit(int client)
{
	tf2_players[client].harvesterCritConsumePending = false;
	tf2_players[client].harvesterRevengeReady = false;
	tf2_players[client].harvesterRevengeWeaponRef = INVALID_ENT_REFERENCE;
	tf2_players[client].harvesterRevengeGeneration++;
	Harvester_SetCritBoost(client, false);
}

bool Harvester_HasRevengeCrit(int client)
{
	if (!Harvester_IsEligibleClient(client) || !tf2_players[client].harvesterRevengeReady) return false;
	int weapon = EntRefToEntIndex(tf2_players[client].harvesterRevengeWeaponRef);
	return weapon > MaxClients && IsValidEntity(weapon)
		&& GetPlayerWeaponSlot(client, TFWeaponSlot_Melee) == weapon && Harvester_IsWeapon(weapon);
}

bool Harvester_ApplyRevengeCrit(int attacker, int victim, int weapon, int inflictor)
{
	if (!Harvester_HasRevengeCrit(attacker) || inflictor != attacker
		|| weapon != EntRefToEntIndex(tf2_players[attacker].harvesterRevengeWeaponRef)) return false;
	// Charge state belongs to this weapon, not TF2's shared revenge counter or
	// a transient crit-glow condition that deploying another weapon can change.
	tf2_players[attacker].harvesterCritConsumePending = true;
	tf2_players[attacker].harvesterCritVictimUserId = GetClientUserId(victim);
	tf2_players[attacker].harvesterCritAttemptTick = GetGameTickCount();
	DataPack attempt = new DataPack();
	attempt.WriteCell(GetClientUserId(attacker));
	attempt.WriteCell(tf2_players[attacker].harvesterRevengeGeneration);
	attempt.WriteCell(GetGameTickCount());
	RequestFrame(Harvester_ClearMissedAttempt, attempt);
	return true;
}

public void Harvester_ClearMissedAttempt(any data)
{
	DataPack attempt = view_as<DataPack>(data);attempt.Reset();
	int client = GetClientOfUserId(attempt.ReadCell());
	int generation = attempt.ReadCell(), tick = attempt.ReadCell();delete attempt;
	if (client > 0 && tf2_players[client].harvesterRevengeGeneration == generation
		&& tf2_players[client].harvesterCritAttemptTick == tick)
		tf2_players[client].harvesterCritConsumePending = false;
}

public void Harvester_OnConfirmedHit(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker <= 0 || !Harvester_HasRevengeCrit(attacker)
		|| !tf2_players[attacker].harvesterCritConsumePending || event.GetInt("damageamount") <= 0
		|| event.GetInt("userid") != tf2_players[attacker].harvesterCritVictimUserId
		|| GetGameTickCount() != tf2_players[attacker].harvesterCritAttemptTick) return;
	int weapon = EntRefToEntIndex(tf2_players[attacker].harvesterRevengeWeaponRef);
	if (event.GetInt("weaponid") != TF2Util_GetWeaponID(weapon)) return;
	Harvester_ClearRevengeCrit(attacker);
	Harvester_ShowHealHint(attacker);
}

