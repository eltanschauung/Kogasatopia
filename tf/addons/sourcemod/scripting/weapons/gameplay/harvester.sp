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

// Use a separate, short-lived condition: Kritzkrieg's condition has a special
// provider list and is also managed by Medic healing. Never leave an infinite
// player-wide boost behind when the charged weapon is holstered or removed.
#define HARVESTER_CRIT_VISUAL_CONDITION TFCond_CritOnDamage
#define HARVESTER_CRIT_VISUAL_DURATION 0.25

void Harvester_SetCritBoost(int client, bool enabled)
{
	if (!Weapons_IsClientInGame(client))
	{
		tf2_players[client].harvesterCritBoostApplied = false;
		return;
	}

	int weapon = EntRefToEntIndex(tf2_players[client].harvesterRevengeWeaponRef);
	bool present = TF2_IsPlayerInCondition(client, HARVESTER_CRIT_VISUAL_CONDITION);
	int provider = present ? TF2Util_GetPlayerConditionProvider(client, HARVESTER_CRIT_VISUAL_CONDITION) : -1;
	bool owned = present && tf2_players[client].harvesterCritBoostApplied
		&& weapon > MaxClients && provider == weapon;
	if (!enabled)
	{
		if (owned) TF2_RemoveCondition(client, HARVESTER_CRIT_VISUAL_CONDITION);
		tf2_players[client].harvesterCritBoostApplied = false;
		tf2_players[client].harvesterCritVisualRefreshAt = 0.0;
		return;
	}

	// A boost supplied by another source is not ours to overwrite or remove.
	if (present && !owned) return;
	float now = GetGameTime();
	if (owned && now < tf2_players[client].harvesterCritVisualRefreshAt) return;
	TF2_AddCondition(client, HARVESTER_CRIT_VISUAL_CONDITION, HARVESTER_CRIT_VISUAL_DURATION, weapon);
	tf2_players[client].harvesterCritBoostApplied = true;
	tf2_players[client].harvesterCritVisualRefreshAt = now + 0.10;
}

void Harvester_SyncCritBoost(int client)
{
	if (!tf2_players[client].harvesterRevengeReady && !tf2_players[client].harvesterCritBoostApplied) return;
	if (!IsPlayerAlive(client) || !Harvester_HasRevengeCrit(client))
	{
		Harvester_ClearRevengeCrit(client);
		return;
	}
	Harvester_SetCritBoost(client, GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")
		== EntRefToEntIndex(tf2_players[client].harvesterRevengeWeaponRef));
}

static void Harvester_SetRevengeCrit(int client)
{
	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (!Harvester_IsWeapon(weapon)) return;
	tf2_players[client].harvesterRevengeReady = true;
	tf2_players[client].harvesterRevengeWeaponRef = EntIndexToEntRef(weapon);
	Harvester_SyncCritBoost(client);
}

static void Harvester_ClearRevengeCrit(int client)
{
	// Retain the weapon reference until the condition's ownership is checked.
	Harvester_SetCritBoost(client, false);
	tf2_players[client].harvesterRevengeReady = false;
	tf2_players[client].harvesterRevengeWeaponRef = INVALID_ENT_REFERENCE;
}

bool Harvester_HasRevengeCrit(int client)
{
	if (!Harvester_IsEligibleClient(client) || !tf2_players[client].harvesterRevengeReady) return false;
	int weapon = EntRefToEntIndex(tf2_players[client].harvesterRevengeWeaponRef);
	return weapon > MaxClients && IsValidEntity(weapon)
		&& GetPlayerWeaponSlot(client, TFWeaponSlot_Melee) == weapon && Harvester_IsWeapon(weapon);
}

bool Harvester_ShouldCritWeapon(int client, int weapon)
{
	return Harvester_HasRevengeCrit(client)
		&& weapon == EntRefToEntIndex(tf2_players[client].harvesterRevengeWeaponRef);
}

bool Harvester_ConsumeOnEnemyHit(int attacker, int victim, int weapon, int inflictor, int damageType)
{
	if (!Weapons_IsClientInGame(attacker) || !Weapons_IsClientInGame(victim)
		|| attacker == victim || GetClientTeam(attacker) <= 1 || GetClientTeam(victim) <= 1
		|| GetClientTeam(attacker) == GetClientTeam(victim) || inflictor != attacker
		|| !(damageType & DMG_CLUB) || !Harvester_ShouldCritWeapon(attacker, weapon)) return false;
	// The damage hook proves a melee contact. Consume here, once, instead of
	// matching a later player_hurt event against a transient active-weapon ID.
	Harvester_ClearRevengeCrit(attacker);
	Harvester_ShowHealHint(attacker);
	return true;
}
