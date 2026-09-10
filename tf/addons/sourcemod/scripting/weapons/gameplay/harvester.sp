bool Harvester_IsEligibleClient(int client)
{
	return IsClientInGame(client) && TF2_GetPlayerClass(client) == TFClass_Pyro;
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
		|| GetEntProp(client, Prop_Send, "m_iRevengeCrits") > 0)
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

	if (GetEntProp(client, Prop_Send, "m_iRevengeCrits") > 0)
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
		if (!IsClientInGame(client) || !IsPlayerAlive(client)
			|| TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged))
		{
			return;
		}

		TF2_AddCondition(client, TFCond_Kritzkrieged, TFCondDuration_Infinite);
		tf2_players[client].harvesterCritBoostApplied = true;
		return;
	}

	if (tf2_players[client].harvesterCritBoostApplied)
	{
		if (IsClientInGame(client))
		{
			TF2_RemoveCondition(client, TFCond_Kritzkrieged);
		}
		tf2_players[client].harvesterCritBoostApplied = false;
	}
}

static void Harvester_SetRevengeCrit(int client)
{
	SetEntProp(client, Prop_Send, "m_iRevengeCrits", 1);
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	Harvester_SetCritBoost(client, Harvester_IsWeapon(activeWeapon));
}

static void Harvester_ClearRevengeCrit(int client)
{
	tf2_players[client].harvesterCritConsumePending = false;
	if (IsClientInGame(client))
	{
		SetEntProp(client, Prop_Send, "m_iRevengeCrits", 0);
	}
	Harvester_SetCritBoost(client, false);
}

public void Harvester_ConsumeRevengeCrit(any userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || !IsClientInGame(client))
	{
		return;
	}

	tf2_players[client].harvesterCritConsumePending = false;
	SetEntProp(client, Prop_Send, "m_iRevengeCrits", 0);
	Harvester_SetCritBoost(client, false);
	Harvester_ShowHealHint(client);
}

