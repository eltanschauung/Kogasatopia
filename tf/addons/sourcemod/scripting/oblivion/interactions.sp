DynamicDetour g_DamagePlayer, g_DamageObject, g_MedigunTarget, g_AirblastTarget;
DynamicDetour g_ObserverTarget, g_DispenserTarget;
DynamicDetour g_DeflectEntity;
DynamicHook g_Visibility;
DynamicDetour g_AddCondition;
StringMap g_SharedClients;
int g_SharedOffset;

void Interactions_Start()
{
    GameData data = new GameData("oblivion");
    if (data == null) SetFailState("Missing oblivion gamedata.");
    g_DamagePlayer = DynamicDetour.FromConf(data, "Oblivion_PlayerDamage");
    g_DamageObject = DynamicDetour.FromConf(data, "Oblivion_ObjectDamage");
    g_MedigunTarget = DynamicDetour.FromConf(data, "Oblivion_MedigunTarget");
    g_AirblastTarget = DynamicDetour.FromConf(data, "Oblivion_AirblastTarget");
    g_ObserverTarget = DynamicDetour.FromConf(data, "Oblivion_ObserverTarget");
    g_DispenserTarget = DynamicDetour.FromConf(data, "Oblivion_DispenserTarget");
    g_DeflectEntity = DynamicDetour.FromConf(data, "Oblivion_DeflectEntity");
    g_Visibility = new DynamicHook(data.GetOffset("FVisible"), HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
    g_Visibility.AddParam(HookParamType_CBaseEntity);
    g_Visibility.AddParam(HookParamType_Int);
    g_Visibility.AddParam(HookParamType_ObjectPtr);
    delete data;
    g_SharedClients = new StringMap();
    g_SharedOffset = FindSendPropInfo("CTFPlayer", "m_Shared");
    if (g_SharedOffset <= 0) SetFailState("Cannot locate the TF2 shared-player state.");
    // Reuse SourceMod's maintained AddCondition signature, including its Linux
    // and 64-bit variants, instead of duplicating it in our gamedata.
    GameData tf2data = new GameData("sm-tf2.games");
    g_AddCondition = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address);
    if (!g_AddCondition.SetFromConf(tf2data, SDKConf_Signature, "AddCondition"))
        SetFailState("SourceMod's AddCondition signature is unavailable.");
    delete tf2data;
    g_AddCondition.AddParam(HookParamType_Int);
    g_AddCondition.AddParam(HookParamType_Float);
    g_AddCondition.AddParam(HookParamType_CBaseEntity);
    if (g_DamagePlayer == null || g_DamageObject == null || g_MedigunTarget == null || g_AirblastTarget == null
        || g_ObserverTarget == null || g_DispenserTarget == null || g_DeflectEntity == null)
        SetFailState("An Oblivion interaction signature is unavailable for this server build.");
    if (!g_DamagePlayer.Enable(Hook_Pre, NativeDamage)
        || !g_DamageObject.Enable(Hook_Pre, NativeDamage)
        || !g_DamagePlayer.Enable(Hook_Post, NativeDamagePost)
        || !g_DamageObject.Enable(Hook_Post, NativeDamagePost)
        || !g_MedigunTarget.Enable(Hook_Pre, NativeMedigun)
        || !g_AirblastTarget.Enable(Hook_Pre, NativeAirblast)
        || !g_ObserverTarget.Enable(Hook_Pre, NativeObserver)
        || !g_DispenserTarget.Enable(Hook_Pre, NativeMedigun)
        || !g_DeflectEntity.Enable(Hook_Pre, NativeAirblast)
        || !g_AddCondition.Enable(Hook_Pre, NativeCondition)
        || !g_AddCondition.Enable(Hook_Post, NativeConditionPost))
        SetFailState("Unable to enable Oblivion interaction hooks.");
}

void Interactions_HookEntity(int entity)
{
    if (entity > 0 && entity <= MaxClients) RememberSharedState(entity);
    if (g_Visibility != null) g_Visibility.HookEntity(Hook_Pre, entity, NativeLineOfSight);
}

void RememberSharedState(int client)
{
    if (g_SharedClients == null || !IsClientInGame(client)) return;
    char key[24];
    FormatEx(key, sizeof(key), "%x", view_as<int>(GetEntityAddress(client)) + g_SharedOffset);
    g_SharedClients.SetValue(key, GetClientSerial(client));
}

public MRESReturn NativeCondition(Address shared, DHookParam params)
{
    int provider = params.IsNull(3) ? 0 : params.Get(3);
    BeginConditionEffect(provider);
    if (!provider && !EffectSource()) return MRES_Ignored;
    char key[24];
    FormatEx(key, sizeof(key), "%x", view_as<int>(shared));
    int serial;
    if (!g_SharedClients.GetValue(key, serial)) return MRES_Ignored;
    int client = GetClientFromSerial(serial);
    if (!client) return MRES_Ignored;
    if (EntitiesBlocked(client, provider) || EntitiesBlocked(client, EffectSource())) return MRES_Supercede;
    return MRES_Ignored;
}

void ClearBlockedConditions()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        bool participating;
        for (int other = 1; other <= MaxClients; other++)
            if (Blocked(client, other)) { participating = true; break; }
        if (!participating) continue;
        // TF2 networks five 32-bit condition words. Query providers only for
        // active bits, keeping unused enum values out of the utility native.
        for (int i = 0; i < 160; i++)
        {
            TFCond condition = view_as<TFCond>(i);
            if (!TF2_IsPlayerInCondition(client, condition)) continue;
            int provider = TF2Util_GetPlayerConditionProvider(client, condition);
            if (EntitiesBlocked(client, provider)) TF2_RemoveCondition(client, condition);
        }
    }
}

public MRESReturn NativeLineOfSight(int entity, DHookReturn result, DHookParam params)
{
    if (!EntitiesBlocked(entity, params.Get(1))) return MRES_Ignored;
    result.Value = false;
    return MRES_Supercede;
}

public MRESReturn NativeObserver(int viewer, DHookReturn result, DHookParam params)
{
    if (params.IsNull(1)) return MRES_Ignored;
    if (!HiddenEntity(viewer, params.Get(1))) return MRES_Ignored;
    result.Value = false;
    return MRES_Supercede;
}

public MRESReturn NativeDamage(int victim, DHookReturn result, DHookParam params)
{
    // Valve's CTakeDamageInfo: three Vector fields followed by the inflictor,
    // attacker and weapon EHANDLEs. EHANDLE remains four bytes on x86 and x64.
    int attacker = params.GetObjectVar(1, 40, ObjectValueType_Ehandle);
    int inflictor = params.GetObjectVar(1, 36, ObjectValueType_Ehandle);
    BeginDamageEffect(attacker, inflictor);
    if (!EntitiesBlocked(victim, attacker) && !EntitiesBlocked(victim, inflictor)) return MRES_Ignored;
    result.Value = 0;
    return MRES_Supercede;
}

public MRESReturn NativeMedigun(int weapon, DHookReturn result, DHookParam params)
{
    if (!EntitiesBlocked(weapon, params.Get(1))) return MRES_Ignored;
    result.Value = false;
    return MRES_Supercede;
}

public MRESReturn NativeAirblast(int weapon, DHookReturn result, DHookParam params)
{
    if (!EntitiesBlocked(params.Get(2), params.Get(1))) return MRES_Ignored;
    result.Value = false;
    return MRES_Supercede;
}

public MRESReturn NativeDamagePost(int victim, DHookReturn result, DHookParam params)
{
    EndDamageEffect();
    return MRES_Ignored;
}

public MRESReturn NativeConditionPost(Address shared, DHookParam params)
{
    EndConditionEffect();
    return MRES_Ignored;
}
