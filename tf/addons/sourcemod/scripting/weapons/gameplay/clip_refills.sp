void SecondaryDamageRefill_Reset(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	tf2_players[client].secondaryDamageProgress = 0.0;
	tf2_players[client].secondaryDamageProgressExpiresAt = 0.0;
}

void SecondaryDamageRefill_OnDamage(int attacker, int weapon, float damage)
{
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		return;

	if (weapon <= MaxClients || !IsValidEntity(weapon) || damage <= 0.0)
		return;

	int requirement = TF2CustAttr_GetInt(weapon, ATTR_RESTORE_PRIMARY_SHOT_BY_DAMAGE, 0);
	if (requirement <= 0)
		return;

	float now = GetGameTime();
	if (tf2_players[attacker].secondaryDamageProgressExpiresAt <= now)
	{
		tf2_players[attacker].secondaryDamageProgress = 0.0;
	}

	tf2_players[attacker].secondaryDamageProgress += damage;
	tf2_players[attacker].secondaryDamageProgressExpiresAt = now + RESTORE_PRIMARY_SHOT_DAMAGE_WINDOW;

	int primary = GetPlayerWeaponSlot(attacker, 0);
	if (primary <= MaxClients || !IsValidEntity(primary))
		return;

	int maxClip = GetWeaponMaxClip(primary);
	if (maxClip <= 0)
		return;

	int clip = GetClip(primary);
	if (clip < 0)
		return;

	bool updated = false;
	float requirementFloat = float(requirement);
	while (tf2_players[attacker].secondaryDamageProgress >= requirementFloat)
	{
		if (clip >= maxClip)
		{
			float cap = requirementFloat * 2.0;
			if (tf2_players[attacker].secondaryDamageProgress > cap)
			{
				tf2_players[attacker].secondaryDamageProgress = cap;
			}
			break;
		}

		clip++;
		tf2_players[attacker].secondaryDamageProgress -= requirementFloat;
		updated = true;
	}

	if (updated)
	{
		SetClip_Weapon(primary, clip);
		EmitSoundToClient(attacker, SOUND_SECONDARY_CLIP_REFILL);
	}
}

static bool ReloadWeaponClip(int weapon, int reloadAmount)
{
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return false;

	if (reloadAmount <= 0)
		return false;

	int maxClip = GetWeaponMaxClip(weapon);
	if (maxClip <= 0)
		return false;

	int clip = GetClip(weapon);
	if (clip < 0 || clip >= maxClip)
		return false;

	clip += reloadAmount;
	if (clip > maxClip)
	{
		clip = maxClip;
	}

	SetClip_Weapon(weapon, clip);
	return true;
}

void ReloadOnHit_OnDamage(int weapon)
{
	ReloadWeaponClip(weapon, TF2CustAttr_GetInt(weapon, ATTR_RELOAD_ON_HIT));
}

void RefillClipOnHit_OnDamage(int weapon)
{
	int refillAmount = TF2CustAttr_GetInt(weapon, ATTR_REFILL_CLIP_ON_HIT, 0);
	if (refillAmount <= 0)
	{
		return;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(EntIndexToEntRef(weapon));
	pack.WriteCell(refillAmount);
	RequestFrame(RefillClipOnHit_ApplyFrame, pack);
}

static void RefillClipOnHit_ApplyFrame(any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int weapon = EntRefToEntIndex(pack.ReadCell());
	int refillAmount = pack.ReadCell();
	delete pack;

	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return;
	}

	ReloadWeaponClip(weapon, refillAmount);
}

static void RefillSecondaryClipOnHit_ApplyFrame(any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int attacker = GetClientOfUserId(pack.ReadCell());
	int sourceWeapon = EntRefToEntIndex(pack.ReadCell());
	int refillAmount = pack.ReadCell();
	delete pack;

	if (!Weapons_IsClientInGame(attacker)
		|| !Weapons_IsValidWeaponEntity(sourceWeapon))
	{
		return;
	}

	RefillSecondaryClip(attacker, refillAmount);
}

static bool RefillSecondaryClip(int attacker, int refillAmount)
{
	if (!Weapons_IsClientInGame(attacker) || refillAmount <= 0)
		return false;

	int secondary = GetPlayerWeaponSlot(attacker, WEAPON_SLOT_SECONDARY);
	if (!Weapons_IsClipWeaponEntity(secondary)
		|| !ReloadWeaponClip(secondary, refillAmount))
	{
		return false;
	}

	EmitSoundToAll(
		SOUND_SECONDARY_CLIP_REFILL,
		attacker,
		SNDCHAN_AUTO,
		SNDLEVEL_NORMAL
	);
	return true;
}

void WearerRefillSecondaryClipOnKill(int attacker)
{
	int refillAmount = 0;
	for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
	{
		int weapon = GetPlayerWeaponSlot(attacker, slot);
		if (!Weapons_IsValidWeaponEntity(weapon))
			continue;

		int amount = TF2CustAttr_GetInt(
			weapon, ATTR_WEARER_REFILL_SECONDARY_CLIP_ON_KILL, 0);
		if (amount > refillAmount)
		{
			refillAmount = amount;
		}
	}

	RefillSecondaryClip(attacker, refillAmount);
}

void RefillSecondaryClipOnHit_OnDamage(int attacker, int weapon)
{
	int refillAmount = TF2CustAttr_GetInt(weapon, ATTR_REFILL_SECONDARY_CLIP_ON_HIT, 0);
	if (refillAmount <= 0)
	{
		return;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(attacker));
	pack.WriteCell(EntIndexToEntRef(weapon));
	pack.WriteCell(refillAmount);
	RequestFrame(RefillSecondaryClipOnHit_ApplyFrame, pack);
}

void ReloadOnKill_OnKill(int weapon)
{
	ReloadWeaponClip(weapon, TF2CustAttr_GetInt(weapon, ATTR_RELOAD_ON_KILL));
}

static bool RefillPrimaryClipFromWeapon(int attacker, int sourceWeapon, int amount)
{
	if (!Weapons_IsClientInGame(attacker)
		|| !Weapons_IsValidWeaponEntity(sourceWeapon)
		|| amount <= 0)
	{
		return false;
	}

	int primary = GetPlayerWeaponSlot(attacker, WEAPON_SLOT_PRIMARY);
	if (!Weapons_IsClipWeaponEntity(primary))
		return false;

	return ReloadWeaponClip(primary, amount);
}

static void RefillPrimaryClip_ApplyFrame(any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int attacker = GetClientOfUserId(pack.ReadCell());
	int sourceWeapon = EntRefToEntIndex(pack.ReadCell());
	int amount = pack.ReadCell();
	delete pack;

	if (RefillPrimaryClipFromWeapon(attacker, sourceWeapon, amount))
	{
		EmitSoundToAll(
			SOUND_CLIP_REFILL_CRIT,
			attacker,
			SNDCHAN_AUTO,
			SNDLEVEL_NORMAL
		);
	}
}

static void RefillPrimaryClipNextFrame(int attacker, int sourceWeapon, int amount)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(attacker));
	pack.WriteCell(EntIndexToEntRef(sourceWeapon));
	pack.WriteCell(amount);
	RequestFrame(RefillPrimaryClip_ApplyFrame, pack);
}

void RefillPrimaryClipOnKill(int attacker, int weapon)
{
	if (!Weapons_IsClientInGame(attacker) || !Weapons_IsValidWeaponEntity(weapon))
		return;

	int amount = TF2CustAttr_GetInt(weapon, ATTR_REFILL_PRIMARY_CLIP_ON_KILL, 0);
	if (amount <= 0)
	{
		amount = TF2CustAttr_GetInt(weapon, ATTR_RESTORE_PRIMARY_SHOT_KILL, 0);
	}

	if (amount <= 0)
		return;

	RefillPrimaryClipFromWeapon(attacker, weapon, amount);
}

void RefillPrimaryClipOnCrit(int attacker, int victim, int weapon, float damage, int damageType)
{
	if (!Weapons_IsClientInGame(attacker)
		|| !Weapons_IsClientInGame(victim)
		|| !Weapons_IsValidWeaponEntity(weapon)
		|| attacker == victim
		|| damage <= 0.0
		|| GetClientTeam(attacker) <= 1
		|| GetClientTeam(victim) <= 1
		|| GetClientTeam(attacker) == GetClientTeam(victim)
		|| !(damageType & DMG_CRIT))
	{
		return;
	}

	int amount = TF2CustAttr_GetInt(weapon, ATTR_REFILL_PRIMARY_CLIP_ON_CRIT, 0);
	if (amount <= 0)
		return;

	RefillPrimaryClipNextFrame(attacker, weapon, amount);
}

