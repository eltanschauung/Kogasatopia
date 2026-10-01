void SecondaryDamageRefill_Reset(int client)
{
	if (!Weapons_IsValidPlayerIndex(client))
		return;

	tf2_players[client].secondaryDamageProgress = 0.0;
	tf2_players[client].secondaryDamageProgressExpiresAt = 0.0;
}

void SecondaryDamageRefill_OnDamage(int attacker, float damage)
{
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		return;

	if (damage <= 0.0)
		return;

	int activeWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
	if (!Weapons_IsValidWeaponEntity(activeWeapon))
		return;

	int requirement = TF2CustAttr_GetInt(
		activeWeapon, ATTR_RESTORE_PRIMARY_SHOT_BY_DAMAGE, 0);
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
	int amount = TF2CustAttr_GetInt(weapon, ATTR_RELOAD_ON_HIT);
	if (amount <= 0) return;
	// Hitscan damage can run before PrimaryAttack subtracts its shot. Defer
	// the refill so a hit from a full clip still restores the fired round.
	DataPack pack = new DataPack();
	pack.WriteCell(EntIndexToEntRef(weapon));
	pack.WriteCell(amount);
	RequestFrame(RefillClipOnHit_ApplyFrame, pack);
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

static void RefillSecondaryClipPercentageOnHit_ApplyFrame(any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int attacker = GetClientOfUserId(pack.ReadCell());
    int sourceWeapon = EntRefToEntIndex(pack.ReadCell());
    float refillPercentage = pack.ReadFloat();
    delete pack;

    if (!Weapons_IsClientInGame(attacker)
        || !Weapons_IsValidWeaponEntity(sourceWeapon))
    {
        return;
    }

    RefillSecondaryClipByPercentage(attacker, refillPercentage);
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

static bool RefillHeavyLunchboxMeter(int client, int secondary, float fraction)
{
    if (TF2_GetPlayerClass(client) != TFClass_Heavy || !Weapons_IsValidWeaponEntity(secondary)
        || !HasEntProp(client, Prop_Send, "m_flItemChargeMeter")) return false;
    char classname[64];
    GetEntityClassname(secondary, classname, sizeof(classname));
    if (!StrEqual(classname, "tf_weapon_lunchbox")) return false;
    float previous = GetEntPropFloat(client, Prop_Send, "m_flItemChargeMeter", WEAPON_SLOT_SECONDARY);
    if (previous >= 100.0) return false;
    float charge = previous + fraction * 100.0;
    if (charge > 100.0) charge = 100.0;
    SetEntPropFloat(client, Prop_Send, "m_flItemChargeMeter", charge, WEAPON_SLOT_SECONDARY);
    if (charge >= 100.0)
    {
        // Direct netprop updates skip CTFLunchBox::OnResourceMeterFilled.
        // Reproduce its single-ammo grant when the meter crosses full.
        int ammoType = GetEntProp(secondary, Prop_Send, "m_iPrimaryAmmoType");
        if (ammoType >= 0 && ammoType < GetEntPropArraySize(client, Prop_Send, "m_iAmmo"))
        {
            int ammo = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
            int maximum = TF2Util_GetPlayerMaxAmmo(client, ammoType);
            if (ammo < maximum) SetEntProp(client, Prop_Send, "m_iAmmo", ammo + 1, _, ammoType);
        }
    }
    EmitSoundToClient(client, SOUND_SECONDARY_CLIP_REFILL);
    return true;
}

static bool RefillSecondaryClipByPercentage(int attacker, float refillPercentage)
{
    if (!Weapons_IsClientInGame(attacker) || refillPercentage <= 0.0)
    {
        return false;
    }

    int secondary = GetPlayerWeaponSlot(attacker, WEAPON_SLOT_SECONDARY);
    if (RefillHeavyLunchboxMeter(attacker, secondary, refillPercentage)) return true;
    int maxClip = GetWeaponMaxClip(secondary);
    if (maxClip <= 0)
    {
        return false;
    }

    int refillAmount = RoundToNearest(float(maxClip) * refillPercentage);
    if (refillAmount < 1)
    {
        refillAmount = 1;
    }

    return RefillSecondaryClip(attacker, refillAmount);
}

void WearerRefillSecondaryClipOnKill(int attacker)
{
    float refillPercentage = 0.0;
    for (int slot = 0; slot <= WEAPON_SLOT_LAST; slot++)
    {
        int weapon = GetPlayerWeaponSlot(attacker, slot);
        if (!Weapons_IsValidWeaponEntity(weapon))
        {
            continue;
        }

        float percentage = TF2CustAttr_GetFloat(
            weapon, ATTR_WEARER_REFILL_SECONDARY_CLIP_ON_KILL_PERCENTAGE, 0.0);
        if (percentage > refillPercentage)
        {
            refillPercentage = percentage;
        }
    }

    if (refillPercentage > 0.0)
    {
        RefillSecondaryClipByPercentage(attacker, refillPercentage);
        return;
    }

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
    float refillPercentage = TF2CustAttr_GetFloat(
        weapon, ATTR_REFILL_SECONDARY_CLIP_ON_HIT_PERCENTAGE, 0.0);
    if (refillPercentage > 0.0)
    {
        DataPack percentagePack = new DataPack();
        percentagePack.WriteCell(GetClientUserId(attacker));
        percentagePack.WriteCell(EntIndexToEntRef(weapon));
        percentagePack.WriteFloat(refillPercentage);
        RequestFrame(RefillSecondaryClipPercentageOnHit_ApplyFrame, percentagePack);
        return;
    }

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

void RefillPrimaryClipOnKill(int attacker, int killWeapon)
{
	if (!Weapons_IsClientInGame(attacker))
		return;

	int sourceWeapon = killWeapon;
	int amount = Weapons_IsValidWeaponEntity(killWeapon)
		? TF2CustAttr_GetInt(killWeapon, ATTR_REFILL_PRIMARY_CLIP_ON_KILL, 0)
		: 0;
	if (amount <= 0)
	{
		int activeWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if (Weapons_IsValidWeaponEntity(activeWeapon))
		{
			amount = TF2CustAttr_GetInt(
				activeWeapon, ATTR_RESTORE_PRIMARY_SHOT_KILL, 0);
			sourceWeapon = activeWeapon;
		}
	}

	if (amount <= 0)
		return;

	RefillPrimaryClipFromWeapon(attacker, sourceWeapon, amount);
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

