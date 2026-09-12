bool WeaponsGameplay_IsEnabled()
{
	return !g_bPluginEnding && g_hGameplayEnabled != null && GetConVarBool(g_hGameplayEnabled);
}

public MRESReturn CTFPlayerShared_Burn_Post(Address sharedAddress, DHookParam parameters)
{
	if (sharedAddress == Address_Null || g_iAfterburnDurationOffset < 0)
	{
		return MRES_Ignored;
	}

	Address durationAddress = sharedAddress
		+ view_as<Address>(g_iAfterburnDurationOffset);
	float duration = view_as<float>(
		LoadFromAddress(durationAddress, NumberType_Int32)
	);

	if (duration > AFTERBURN_DURATION_MAX)
	{
		StoreToAddress(
			durationAddress,
			view_as<int>(AFTERBURN_DURATION_MAX),
			NumberType_Int32
		);
	}

	return MRES_Ignored;
}

static void WeaponsGameplay_SetPatchEnabled(MemoryPatch patch, bool enabled)
{
	if (patch == null)
	{
		return;
	}

	if (enabled)
	{
		patch.Enable();
	}
	else
	{
		patch.Disable();
	}
}

static void WeaponsGameplay_SetWranglerPatchEnabled(MemoryPatch patch, bool enabled)
{
	if (patch == null)
	{
		return;
	}

	if (enabled)
	{
		// Enable() copies the configured patch bytes, including the placeholder
		// address. Install the live SourcePawn address after every enable.
		patch.Enable();
		StoreToAddress(
			patch.Address + view_as<Address>(0x04),
			view_as<int>(GetAddressOfCell(g_flWranglerCustomShieldValue)),
			NumberType_Int32
		);
	}
	else
	{
		patch.Disable();
	}
}

void WeaponsGameplay_SetPatchesEnabled(bool enabled)
{
	WeaponsGameplay_SetPatchEnabled(patch_RevertCozyCamper_FlinchNerf, enabled);
	WeaponsGameplay_SetPatchEnabled(patch_AllowRandomCritOverride, enabled);
	WeaponsGameplay_SetWranglerPatchEnabled(patch_Wrangler_CustomShieldRepair, enabled);
	WeaponsGameplay_SetWranglerPatchEnabled(patch_Wrangler_CustomShieldShellRefill, enabled);
	WeaponsGameplay_SetWranglerPatchEnabled(patch_Wrangler_CustomShieldRocketRefill, enabled);
	WeaponsGameplay_SetWranglerPatchEnabled(patch_Wrangler_CustomShieldDamageTaken, enabled);
	WeaponsGameplay_SetWranglerPatchEnabled(patch_Wrangler_RescueRanger_CustomShieldRepair, enabled);
}

#include "../gameplay_events.sp"
#include "../scattergun_knockback.sp"

bool WeaponsGameplay_IsEntityIndex(int entity)
{
	return entity > 0 && entity < GetMaxEntities();
}

void Weapons_ApplyEngineOverrides(int weapon)
{
	if (!IsValidWeaponEntity(weapon))
	{
		return;
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_HUNTING_REVOLVER, 0) != 0)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", TF_AMMO_PRIMARY_INDEX);
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Spread_SetPattern") == FeatureStatus_Available)
	{
		TF2SpreadPattern pattern = TF2Spread_Default;
		if (TF2CustAttr_GetInt(weapon, ATTR_WIDE_HORIZONTAL_BULLET_SPREAD, 0) != 0)
		{
			pattern = TF2Spread_WideHorizontal20;
		}
		else if (TF2CustAttr_GetInt(weapon, ATTR_CIRCULAR_BULLET_SPREAD, 0) != 0)
		{
			pattern = TF2Spread_Circular15;
		}
		TF2Spread_SetPattern(weapon, pattern);
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Scatter_SetWeaponPelletCount") == FeatureStatus_Available)
	{
		float pelletCount = TF2Attrib_HookValueFloat(10.0, "mult_bullets_per_shot", weapon);
		int pelletsFired = RoundToNearest(pelletCount);
		if (pelletsFired < 1)
		{
			pelletsFired = 1;
		}
		TF2Scatter_SetWeaponPelletCount(weapon, pelletsFired);
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Spread_SetAmbassadorAccuracy") == FeatureStatus_Available)
	{
		bool enabled = TF2CustAttr_GetInt(weapon, ATTR_AMBASSADOR_ACCURACY_RECOVERY, 0) != 0;
		TF2Spread_SetAmbassadorAccuracy(weapon, enabled);
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Weapon_SetPunchAngle") == FeatureStatus_Available)
	{
		char amountValue[16];
		TF2CustAttr_GetString(weapon, ATTR_PUNCH_ANGLE_MOD, amountValue, sizeof(amountValue));
		bool enabled = amountValue[0] != '\0';
		int amount = enabled ? StringToInt(amountValue) : 0;
		bool consistent = TF2CustAttr_GetInt(weapon, ATTR_PUNCH_ANGLE_IS_CONSISTENT, 0) != 0;
		TF2Weapon_SetPunchAngle(weapon, enabled, amount, consistent);
	}

}

bool WeaponsGameplay_HasHeadshotFeature(int weapon)
{
	return TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED, 0) != 0
		|| TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED_WHILE_ZOOMED, 0) != 0
		|| TF2CustAttr_GetInt(weapon, ATTR_AMBASSADOR_ACCURACY_RECOVERY, 0) != 0;
}

static bool WeaponsGameplay_IsHeadshotZoomed(int weapon)
{
	if (!IsValidWeaponEntity(weapon))
	{
		return false;
	}

	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (!Weapons_IsValidPlayerIndex(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == weapon
		&& tf2_players[client].huntingRevolverZoomed
		&& tf2_players[client].huntingRevolverZoomReadyTime > 0.0
		&& GetGameTime() >= tf2_players[client].huntingRevolverZoomReadyTime
		&& EntRefToEntIndex(tf2_players[client].huntingRevolverWeaponRef) == weapon;
}

bool WeaponsGameplay_CanHeadshotNow(int weapon)
{
	if (TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED, 0) != 0)
	{
		return true;
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_HEADSHOTS_ENABLED_WHILE_ZOOMED, 0) != 0)
	{
		if (!WeaponsGameplay_IsHeadshotZoomed(weapon))
		{
			return false;
		}

		float lastFireTime = GetEntPropFloat(weapon, Prop_Send, "m_flLastFireTime");
		return GetGameTime() - lastFireTime >= 1.0;
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_AMBASSADOR_ACCURACY_RECOVERY, 0) == 0)
	{
		return false;
	}

	return GetFeatureStatus(
		FeatureType_Native, "TF2Spread_IsAmbassadorAccuracyRecovered") == FeatureStatus_Available
		&& TF2Spread_IsAmbassadorAccuracyRecovered(weapon);
}

void WeaponsGameplay_DeleteConfigs()
{
	if (g_hWeaponsGameplayConfig != null)
	{
		delete g_hWeaponsGameplayConfig;
		g_hWeaponsGameplayConfig = null;
	}

}

// Addplayerhealth was made by chdata, I'm not able to find it online anymore so I'll rehost it in this repo
// Thank you Huutti/Castaway, Chaosxk, Drixevel and others for several pieces of code

void WeaponsGameplay_RegisterNatives()
{
	MarkNativeAsOptional("TF2Util_GetPlayerFromSharedAddress");
	CreateNative("Weapons_GetWeaponInfo", Native_GetWeaponInfo);
	CreateNative("Weapons_CanClassUseWeapon", Native_CanClassUseWeapon);
}

stock void ResetClientArrays(int client)
{
	if (!Weapons_IsValidPlayerIndex(client)) return;
	WeaponsGameplay_ClearPipebombWearerAttribute(client);
	WeaponsGameplay_ClearStickyFizzleWearerAttribute(client);
	BlastJumpJarate_ClearPending(client);
	HuntingRevolver_ResetClient(client);
	FullPelletIgnite_ClearClient(client);
	Harvester_ClearState(client);
	ShockCharge_StopTimer(client);
	tf2_players[client].shockCharge = 30;
	tf2_players[client].lastUber = 0.0;
	tf2_players[client].lastUberMedigunDefIndex = 0;
	tf2_players[client].engiMetal = 0;
	tf2_players[client].accuracyStreak = 0;
	tf2_players[client].accuracyStreakExpiresAt = 0.0;
	SecondaryDamageRefill_Reset(client);
	DamageSourceTracking_ResetClient(client);
	tf2_players[client].oldHealth = 0;
	if (tf2_players[client].sprokeTimer != null)
	{
		KillTimer(tf2_players[client].sprokeTimer);
		tf2_players[client].sprokeTimer = null;
	}
	Sproke_ClearEffect(client, true, false);
	for (int i = 0; i <= FAN_O_WAR_MAX_MARK_COUNT; i++)
	{
		tf2_players[client].markVictims[i] = -1;
	}
	g_iSandmanStunFrame[client] = 0;
	g_iSandmanStunInflictorRef[client] = INVALID_ENT_REFERENCE;
	g_iEnvironmentalKillAttackerUserId[client] = 0;
	g_fEnvironmentalKillTime[client] = 0.0;
	ScattergunKnockback_ResetClient(client);
}

void WeaponsGameplay_OnPluginStart(GameData conf) {
	g_bPluginEnding = false;
	WeaponsGameplayEvents_Init();
	PreCacheWeaponSounds();
	g_hGameplayEnabled = CreateConVar("sm_weapons_gameplay_enabled", "1",
		"Enable gameplay changes while keeping custom weapon loadouts, models, and sounds active.");
	g_hGameplayEnabled.AddChangeHook(WeaponsGameplay_OnEnabledChanged);
	g_hPomsonDamageMult = CreateConVar("sm_weapons_pomson_damage_mult", "0.50", "Damage multiplier for the Pomson 6000", FCVAR_NONE, true, 0.1, true, 2.0);
	g_hBisonDamageMult = CreateConVar("sm_weapons_bison_damage_mult", "0.8", "Damage multiplier for the Righteous Bison", FCVAR_NONE, true, 0.1, true, 2.0);
	g_hScattergunPelletsDebug = CreateConVar("sm_weapons_scattergun_pellets_debug", "0", "Log tracked shotgun/scattergun pellet forward diagnostics.");
	g_hMeatshotDebug = CreateConVar("sm_weapons_meatshot_debug", "0", "Print a client debug message after a valid meatshot kill.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hFallingStompAllWeapons = CreateConVar("sm_weapons_falling_stomp_all_weapons", "1", "Enable boots falling stomp on all player weapons.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hSandmanMaxStunFlightTime = CreateConVar("sm_weapons_sandman_max_stun_flight_time", "1.5", "Flight time at which the reverted Sandman reaches maximum stun duration.", FCVAR_NONE, true, 0.1);
	g_hSandmanFallbackBaseDuration = CreateConVar("sm_weapons_sandman_fallback_base_duration", "2.0", "Fallback maximum Sandman stun duration when tf_scout_stunball_base_duration is unavailable.", FCVAR_NONE, true, 0.1);
	g_hSandmanBaseDuration = FindConVar("tf_scout_stunball_base_duration");
	RegAdminCmd("sm_weapons_reload", Command_ReloadWeaponsConfig, ADMFLAG_CONFIG, "Reload weapon definitions from configs/weapons.cfg.");
	RegAdminCmd("sm_weapons_refresh", Command_ReloadWeaponsConfig, ADMFLAG_CONFIG, "Refresh weapon definitions from configs/weapons.cfg.");
	g_iMetalOffset = FindSendPropInfo("CTFPlayer", "m_iAmmo");
	g_iAfterburnDurationOffset = conf.GetOffset("CTFPlayerShared::m_flAfterburnDuration");
	if (g_iAfterburnDurationOffset < 0)
	{
		SetFailState("Failed to find CTFPlayerShared::m_flAfterburnDuration offset");
	}
	// This is used to ignore clients without the m_iAmmo netprop

		for (int i = 1; i <= MaxClients; i++)
		{
			tf2_players[i].sprokeTimer = null;
			tf2_players[i].sprokePrimaryRef = INVALID_ENT_REFERENCE;
			tf2_players[i].sprokeParticleRef = INVALID_ENT_REFERENCE;
			tf2_players[i].sprokeClipRecord = 0;
			if (IsClientInGame(i))
			{
				ResetClientArrays(i);
				// Ensure all damage/trace hooks are installed for clients that are already in-game
				SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
				SDKHook(i, SDKHook_WeaponSwitch, OnWeaponSwitch);
				SDKHook(i, SDKHook_WeaponSwitchPost, Weapons_OnWeaponSwitchPost);
				SDKHook(i, SDKHook_TraceAttack, OnTraceAttack);
				SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
				SDKHook(i, SDKHook_OnTakeDamageAlivePost, WeaponsGameplay_OnTakeDamageAlivePost);
				SDKHook(i, SDKHook_PostThinkPost, HuntingRevolver_OnPostThinkPost);
			}
		}

		HookAllBuildings();
		HookEvent("player_builtobject", Event_PlayerBuiltObject);

		HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
		HookEvent("player_hurt", Event_PlayerHurt_DoubleDonk, EventHookMode_Post);
		HookEvent("post_inventory_application", Event_Resupply, EventHookMode_Post);
		HookEvent("player_spawn", OnPlayerSpawn);
		HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);
		HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

		GameData overrideConf = new GameData("weapon_overrides.games");
		if (overrideConf == null) SetFailState("Failed to load weapon_overrides.games.txt conf!");

		// Setup SDKCall for GetMaxClip1
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(conf, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1()");
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		g_SDKGetMaxClip1 = EndPrepSDKCall();

		if (g_SDKGetMaxClip1 == null)
		{
			SetFailState("Failed to create SDKCall for GetMaxClip1");
		}

		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(conf, SDKConf_Virtual, "CTFWeaponBase::GetAfterburnRateOnHit()");
		PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
		g_SDKGetAfterburnRateOnHit = EndPrepSDKCall();

		if (g_SDKGetAfterburnRateOnHit == null)
		{
			SetFailState("Failed to create SDKCall for GetAfterburnRateOnHit");
		}

		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CTFPlayer::TeamFortress_SetSpeed()");
		g_SDKTeamFortressSetSpeed = EndPrepSDKCall();

		if (g_SDKTeamFortressSetSpeed == null)
		{
			SetFailState("Failed to create SDKCall for TeamFortress_SetSpeed");
		}

		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CBasePlayer::SetFOV");
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		g_SDKSetFOV = EndPrepSDKCall();

		if (g_SDKSetFOV == null)
		{
			SetFailState("Failed to create SDKCall for CBasePlayer::SetFOV");
		}

		// Virtual dispatch preserves TF2's native ranged/melee crit algorithms.
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(overrideConf, SDKConf_Virtual, "CTFWeaponBase::CalcIsAttackCriticalHelper()");
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		g_SDKCalcIsAttackCriticalHelper = EndPrepSDKCall();

		if (g_SDKCalcIsAttackCriticalHelper == null)
		{
			SetFailState("Failed to create SDKCall for CalcIsAttackCriticalHelper");
		}

		dhook_CTFPlayer_CalculateMaxSpeed = DynamicDetour.FromConf(conf, "CTFPlayer::TeamFortress_CalculateMaxSpeed");
		dhook_CTFLunchBox_ApplyBiteEffects = DynamicDetour.FromConf(conf, "CTFLunchBox::ApplyBiteEffects");
		dhook_CTFPlayerShared_StunPlayer = DynamicDetour.FromConf(conf, "CTFPlayerShared::StunPlayer");
		dhook_CTFPlayerShared_Burn = DynamicDetour.FromConf(conf, "CTFPlayerShared::Burn");
		dhook_IsFixedWeaponSpreadEnabled = DynamicDetour.FromConf(overrideConf, "IsFixedWeaponSpreadEnabled");
		dhook_CObjectCartDispenser_DispenseMetal = DynamicHook.FromConf(conf, "CObjectCartDispenser::DispenseMetal");
		dhook_CTFWeaponBase_CanFireCriticalShot = DynamicHook.FromConf(conf, "CTFWeaponBase::CanFireCriticalShot");
		dhook_CTFWeaponBase_PrimaryAttack = DynamicHook.FromConf(conf, "CTFWeaponBase::PrimaryAttack");
		dhook_CTFWeaponBase_SecondaryAttack = DynamicHook.FromConf(conf, "CTFWeaponBase::SecondaryAttack");
		dhook_CTFStunBall_ApplyBallImpactEffectOnVictim = DynamicHook.FromConf(conf, "CTFStunBall::ApplyBallImpactEffectOnVictim");

		if (dhook_CTFPlayer_CalculateMaxSpeed == null) SetFailState("Failed to create dhook_CTFPlayer_CalculateMaxSpeed");
		if (dhook_CTFLunchBox_ApplyBiteEffects == null) SetFailState("Failed to create dhook_CTFLunchBox_ApplyBiteEffects");
		if (dhook_CTFPlayerShared_StunPlayer == null) SetFailState("Failed to create dhook_CTFPlayerShared_StunPlayer");
		if (dhook_CTFPlayerShared_Burn == null) SetFailState("Failed to create dhook_CTFPlayerShared_Burn");
		if (dhook_IsFixedWeaponSpreadEnabled == null) SetFailState("Failed to create dhook_IsFixedWeaponSpreadEnabled");
		if (dhook_CObjectCartDispenser_DispenseMetal == null) SetFailState("Failed to create dhook_CObjectCartDispenser_DispenseMetal");
		if (dhook_CTFWeaponBase_CanFireCriticalShot == null) SetFailState("Failed to create dhook_CTFWeaponBase_CanFireCriticalShot");
		if (dhook_CTFWeaponBase_PrimaryAttack == null) SetFailState("Failed to create dhook_CTFWeaponBase_PrimaryAttack");
		if (dhook_CTFWeaponBase_SecondaryAttack == null) SetFailState("Failed to create dhook_CTFWeaponBase_SecondaryAttack");
		if (dhook_CTFStunBall_ApplyBallImpactEffectOnVictim == null) SetFailState("Failed to create dhook_CTFStunBall_ApplyBallImpactEffectOnVictim");

		dhook_CTFPlayer_CalculateMaxSpeed.Enable(Hook_Post, CalculateMaxSpeed);
		Escampette_RecalculateAllSpeeds();
		dhook_CTFLunchBox_ApplyBiteEffects.Enable(Hook_Pre, ApplyBiteEffects_Pre);
		dhook_CTFLunchBox_ApplyBiteEffects.Enable(Hook_Post, ApplyBiteEffects_Post);
		dhook_CTFPlayerShared_StunPlayer.Enable(Hook_Pre, SandmanPreJI_StunPlayer_Pre);
		dhook_CTFPlayerShared_Burn.Enable(Hook_Post, CTFPlayerShared_Burn_Post);
		dhook_IsFixedWeaponSpreadEnabled.Enable(Hook_Pre, IsFixedWeaponSpreadEnabled_Pre);
		WeaponsGameplay_HookExistingWeaponEntities();
		AmmoPickups_Init();

		// Create the patches
		patch_RevertCozyCamper_FlinchNerf = MemoryPatch.CreateFromConf(conf, "CTFPlayer::ApplyPunchImpulseX_FakeFullyChargedCondition");
		patch_AllowRandomCritOverride = MemoryPatch.CreateFromConf(overrideConf, "CTFWeaponBaseMelee::CalcIsAttackCriticalHelper_AllowOverride");
		patch_Wrangler_CustomShieldRepair = MemoryPatch.CreateFromConf(conf, "CObjectSentrygun::OnWrenchHit_CustomShieldRepair");
		patch_Wrangler_CustomShieldShellRefill = MemoryPatch.CreateFromConf(conf, "CObjectSentrygun::OnWrenchHit_CustomShieldShellRefill");
		patch_Wrangler_CustomShieldRocketRefill = MemoryPatch.CreateFromConf(conf, "CObjectSentrygun::OnWrenchHit_CustomShieldRocketRefill");
		patch_Wrangler_CustomShieldDamageTaken = MemoryPatch.CreateFromConf(conf, "CObjectSentrygun::OnTakeDamage_CustomShieldDamageTaken");
		patch_Wrangler_RescueRanger_CustomShieldRepair = MemoryPatch.CreateFromConf(conf, "CTFProjectile_Arrow::BuildingHealingArrow_CustomShieldRepair");

		if (!ValidateAndNullCheck(patch_RevertCozyCamper_FlinchNerf)) SetFailState("Failed to create patch_RevertCozyCamper_FlinchNerf");
		if (!ValidateAndNullCheck(patch_AllowRandomCritOverride)) SetFailState("Failed to create patch_AllowRandomCritOverride");
		if (!ValidateAndNullCheck(patch_Wrangler_CustomShieldRepair)) SetFailState("Failed to create patch_Wrangler_CustomShieldRepair");
		if (!ValidateAndNullCheck(patch_Wrangler_CustomShieldShellRefill)) SetFailState("Failed to create patch_Wrangler_CustomShieldShellRefill");
		if (!ValidateAndNullCheck(patch_Wrangler_CustomShieldRocketRefill)) SetFailState("Failed to create patch_Wrangler_CustomShieldRocketRefill");
		if (!ValidateAndNullCheck(patch_Wrangler_CustomShieldDamageTaken)) SetFailState("Failed to create patch_Wrangler_CustomShieldDamageTaken");
		if (!ValidateAndNullCheck(patch_Wrangler_RescueRanger_CustomShieldRepair)) SetFailState("Failed to create patch_Wrangler_RescueRanger_CustomShieldRepair");

		WeaponsGameplay_SetPatchesEnabled(WeaponsGameplay_IsEnabled());
		delete overrideConf;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				Harvester_SyncHealTimer(i);
			}
		}
}

public void PreCacheWeaponSounds() {
	AddFileToDownloadsTable("sound/weapons/halo_ce/plasrifle_overheat_10b.wav");
	PrecacheSound(SOUND_PLASMA_OVERHEAT, true);
	PrecacheSound(SOUND_PLASMA_OVERHEAT_END, true);
	PrecacheSound(SOUND_ARROW_HEAL, true);
	PrecacheSound(SOUND_NEON_SIGN, true);
	PrecacheSound(SOUND_FLAME_OUT, true);
	PrecacheSound(SOUND_AMBASSADOR_CRIT_RECEIVED, true);
	PrecacheSound(SOUND_AMBASSADOR_CRIT_HIT, true);
	PrecacheSound(FLS_EXPLODE_SOUND, true);
	PrecacheSound(FLS_NOTIFY_SOUND, true);
	PrecacheSound(FLS_NOTIFY_2, true);
	PrecacheSound(BURP_SOUND, true);
	PrecacheSound(SOUND_CLIP_REFILL_CRIT, true);
	PrecacheSound(SOUND_SECONDARY_CLIP_REFILL, true);
	PrecacheSound(SOUND_RESTORE_PRIMARY_SHOT, true);
}

static int WeaponsGameplay_FindParticleIndex(const char[] name)
{
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE)
		return INVALID_STRING_INDEX;

	char particle[128];
	int count = GetStringTableNumStrings(table);
	for (int i = 0; i < count; i++)
	{
		ReadStringTable(table, i, particle, sizeof(particle));
		if (StrEqual(particle, name, false))
		{
			return i;
		}
	}

	return INVALID_STRING_INDEX;
}

static void WeaponsGameplay_CacheParticles()
{
	g_iAmbassadorCritParticle = WeaponsGameplay_FindParticleIndex("crit_text");
	g_iShortCircuitParticle = WeaponsGameplay_FindParticleIndex(SHORT_CIRCUIT_PARTICLE);
}

void WeaponsGameplay_OnMapStart() {
	FullPelletIgnite_ClearAll();
	for (int client = 1; client <= MaxClients; client++)
	{
		WeaponsGameplay_ClearPipebombWearerAttribute(client);
		WeaponsGameplay_ClearStickyFizzleWearerAttribute(client);
		BlastJumpJarate_ClearPending(client);
	}
	Escampette_RecalculateAllSpeeds();
	PreCacheWeaponSounds();
	WeaponsGameplay_CacheParticles();
}

void WeaponsGameplay_OnMapEnd()
{
	Plasma_ClearAll();
	FullPelletIgnite_ClearAll();
	for (int client = 1; client <= MaxClients; client++)
	{
		WeaponsGameplay_ClearPipebombWearerAttribute(client);
		WeaponsGameplay_ClearStickyFizzleWearerAttribute(client);
		HuntingRevolver_ResetClient(client);
		Harvester_ClearState(client);
		ShockCharge_StopTimer(client);
	}
}

void WeaponsGameplay_OnPluginEnd()
{
	AmmoPickups_Shutdown();
	Plasma_ClearAll();
	g_bPluginEnding = true;
	Escampette_RecalculateAllSpeeds();
	WeaponsGameplayEvents_Shutdown();
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientArrays(i);
	}
	DestroyPatch(patch_RevertCozyCamper_FlinchNerf); patch_RevertCozyCamper_FlinchNerf = null;
	DestroyPatch(patch_AllowRandomCritOverride); patch_AllowRandomCritOverride = null;
	DestroyPatch(patch_Wrangler_CustomShieldRepair); patch_Wrangler_CustomShieldRepair = null;
	DestroyPatch(patch_Wrangler_CustomShieldShellRefill); patch_Wrangler_CustomShieldShellRefill = null;
	DestroyPatch(patch_Wrangler_CustomShieldRocketRefill); patch_Wrangler_CustomShieldRocketRefill = null;
	DestroyPatch(patch_Wrangler_CustomShieldDamageTaken); patch_Wrangler_CustomShieldDamageTaken = null;
	DestroyPatch(patch_Wrangler_RescueRanger_CustomShieldRepair); patch_Wrangler_RescueRanger_CustomShieldRepair = null;
	WeaponsGameplay_DeleteConfigs();
}

// I added functions like these while I was worried about memory safety... I assume they're redundant

void WeaponsGameplay_OnClientPutInServer(int client)
{
	if (IsClientInGame(client))
	{
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
		SDKHook(client, SDKHook_WeaponSwitchPost, Weapons_OnWeaponSwitchPost);
		SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		SDKHook(client, SDKHook_OnTakeDamageAlivePost, WeaponsGameplay_OnTakeDamageAlivePost);
		SDKHook(client, SDKHook_PostThinkPost, HuntingRevolver_OnPostThinkPost);
		ResetClientArrays(client);
	}
}

// Potentially important for memory safety
void WeaponsGameplay_OnClientDisconnect(int client)
{
	ResetClientArrays(client);
}

void WeaponsGameplay_OnEntityCreated(int entity, const char[] class) {
	if (!WeaponsGameplay_IsEntityIndex(entity) || !WeaponsGameplay_IsEnabled()) return;

	if (entity > 0 && entity < MAX_TRACKED_ENTITIES)
	{
		g_flProjectileSpawnTime[entity] = 0.0;
		g_bProjectileSandmanPreJI[entity] = false;
	}

	if (entity > 0 && entity < MAX_TRACKED_ENTITIES && StrContains(class, "tf_projectile_") == 0)
	{
		g_flProjectileSpawnTime[entity] = GetGameTime();
		SDKHook(entity, SDKHook_Touch, ProjectileDirectHit_OnTouch);
	}

	if (StrEqual(class, "tf_projectile_stun_ball"))
	{
		SDKHook(entity, SDKHook_SpawnPost, SandmanPreJI_OnStunBallSpawnPost);
		if (dhook_CTFStunBall_ApplyBallImpactEffectOnVictim != null)
		{
			dhook_CTFStunBall_ApplyBallImpactEffectOnVictim.HookEntity(Hook_Pre, entity, SandmanPreJI_ApplyBallImpactEffectOnVictim_Pre);
		}
	}

	if (StrEqual(class, "tf_projectile_energy_ring"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnEnergyRingSpawnPost);
		SDKHook(entity, SDKHook_Touch, OnEnergyRingTouch);
	}

	if (StrEqual(class, "mapobj_cart_dispenser") && dhook_CObjectCartDispenser_DispenseMetal != null)
	{
		dhook_CObjectCartDispenser_DispenseMetal.HookEntity(Hook_Pre, entity, CartDispenseMetal);
	}

	WeaponsGameplay_HookCriticalShotEntity(entity, class);
	WeaponsGameplay_HookShortCircuitEntity(entity, class);
	Plasma_Hook(entity, class);
}

public void OnEntityDestroyed(int entity)
{
	if (entity > 0 && entity < MAX_TRACKED_ENTITIES)
	{
		g_flProjectileSpawnTime[entity] = 0.0;
		g_bProjectileSandmanPreJI[entity] = false;
		g_bShortCircuitAttackHooks[entity] = false;
		g_bPlasmaHooked[entity] = false;
		g_bPlasmaOwnsAttackLock[entity] = false;
	}
}

public void OnGameFrame()
{
	if (!WeaponsGameplay_IsEnabled())
	{
		Plasma_ClearAll();
		return;
	}

	Plasma_OnFrame();
	static int frame;

	frame++;

	// run every frame
	if (frame % 1 == 0)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && IsPlayerAlive(client))
			{
				VitaSaw_CacheCharge(client);

				if (TF2_IsPlayerInCondition(client, TFCond_Bonked)) {
					tf2_players[client].bonkFrame = GetGameTickCount();
				}
			}
		}
	}
}
