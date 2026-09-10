void OnEnergyRingSpawnPost(int entity) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return;
	}

	// Pomson & Bison hitboxes
	float maxs[3] = { 2.0, 2.0, 10.0 };
	float mins[3] = { -2.0, -2.0, -10.0 };

	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);

	SetEntProp(entity, Prop_Send, "m_usSolidFlags", (GetEntProp(entity, Prop_Send, "m_usSolidFlags") | FSOLID_USE_TRIGGER_BOUNDS));
	SetEntProp(entity, Prop_Send, "m_triggerBloat", 24);
}

Action OnEnergyRingTouch(int entity, int other) {
	if (!WeaponsGameplay_IsEnabled())
	{
		return Plugin_Continue;
	}

	// Pomson & Bison light up friendly Huntsman arrows
	if (other >= 1 && other <= MaxClients) {
		int weapon = GetEntPropEnt(other, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(weapon)) {
			if (
				HasEntProp(weapon, Prop_Send, "m_bArrowAlight") &&
				GetEntProp(entity, Prop_Send, "m_iTeamNum") == GetEntProp(other, Prop_Send, "m_iTeamNum")
			) {
				SetEntProp(weapon, Prop_Send, "m_bArrowAlight", true);
			}
		}
	} else if (other > MaxClients) {
		char class[64];
		GetEntityClassname(other, class, sizeof(class));
		// Don't collide with projectiles
		if (StrContains(class, "tf_projectile_") == 0) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result) {
	WeaponsMovement_OnCalcIsAttackCritical(client, weapon);

	if (!WeaponsGameplay_IsEnabled()
		|| !IsClientInGame(client) || weapon <= MaxClients || !IsValidEntity(weapon))
		return Plugin_Continue;

	// The SDKCall re-enters this forward through SourceMod's crit hook.
	if (g_bCalculatingRandomCritOverride)
		return Plugin_Continue;

	float recoil = TF2CustAttr_GetFloat(weapon, ATTR_RECOIL_JUMPING, 0.0);
	if (recoil > 0.0)
	{
		float angles[3];
		float aimForward[3];
		float velocity[3];

		GetClientEyeAngles(client, angles);
		GetAngleVectors(angles, aimForward, NULL_VECTOR, NULL_VECTOR);
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

		ScaleVector(aimForward, -recoil);
		AddVectors(velocity, aimForward, velocity);
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);

		if (!(GetEntityFlags(client) & FL_ONGROUND))
		{
			TF2_StunPlayer(client, 0.3, 1.0, TF_STUNFLAG_SLOWDOWN | TF_STUNFLAG_LIMITMOVEMENT);
		}
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_RANDOM_CRITS_OVERRIDE, 0) != 0)
	{
		g_bCalculatingRandomCritOverride = true;
		result = view_as<bool>(SDKCall(g_SDKCalcIsAttackCriticalHelper, weapon));
		g_bCalculatingRandomCritOverride = false;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public MRESReturn IsFixedWeaponSpreadEnabled_Pre(DHookReturn returnValue, DHookParam parameters)
{
	if (!WeaponsGameplay_IsEnabled())
	{
		return MRES_Ignored;
	}

	int weapon = parameters.Get(1);
	if (!IsValidWeaponEntity(weapon))
	{
		return MRES_Ignored;
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_CIRCULAR_BULLET_SPREAD, 0) != 0
		|| TF2CustAttr_GetInt(weapon, ATTR_WIDE_HORIZONTAL_BULLET_SPREAD, 0) != 0)
	{
		returnValue.Value = true;
		return MRES_Supercede;
	}

	if (TF2CustAttr_GetInt(weapon, ATTR_RANDOM_SPREAD_OVERRIDE, 0) == 0)
	{
		return MRES_Ignored;
	}

	returnValue.Value = false;
	return MRES_Supercede;
}

