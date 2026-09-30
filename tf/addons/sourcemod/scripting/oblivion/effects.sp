enum struct EffectScope
{
    int entity;
    int reference;
    int kind;
}

enum
{
    EffectScope_Think,
    EffectScope_Touch,
    EffectScope_Bullets
};

ArrayList g_EffectScopes;
DynamicHook g_FireBullets;
bool g_ReplayingEffect;

void Effects_Start()
{
    g_EffectScopes = new ArrayList(sizeof(EffectScope));
    // Sentries fire from a named context think, which bypasses the ordinary
    // CBaseEntity::Think hook. Capture their actual FireBullets call instead.
    GameData data = new GameData("sdkhooks.games");
    int offset = data.GetOffset("FireBullets");
    delete data;
    if (offset <= 0) SetFailState("SourceMod's FireBullets offset is unavailable.");
    g_FireBullets = new DynamicHook(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);
    g_FireBullets.AddParam(HookParamType_ObjectPtr);
    AddTempEntHook("Fire Bullets", FilterEffect);
    AddTempEntHook("TFExplosion", FilterEffect);
    AddTempEntHook("TFBlood", FilterEffect);
    AddTempEntHook("EffectDispatch", FilterEffect);
    AddTempEntHook("Player Decal", FilterEffect);
}

void Effects_HookEntity(int entity)
{
    SDKHook(entity, SDKHook_Think, EffectThinkPre);
    SDKHook(entity, SDKHook_ThinkPost, EffectThinkPost);
    SDKHook(entity, SDKHook_Touch, EffectTouchPre);
    SDKHook(entity, SDKHook_TouchPost, EffectTouchPost);
    if (HasEntProp(entity, Prop_Send, "m_hBuilder"))
    {
        g_FireBullets.HookEntity(Hook_Pre, entity, EffectBulletsPre);
        g_FireBullets.HookEntity(Hook_Post, entity, EffectBulletsPost);
    }
}

void Effects_Reset()
{
    if (g_EffectScopes != null) g_EffectScopes.Clear();
}

void EnterEffectScope(int entity, int kind)
{
    Actor(entity); // Cache identity before a projectile can lose its owner.
    EffectScope scope;
    scope.entity = entity;
    scope.reference = EntIndexToEntRef(entity);
    scope.kind = kind;
    g_EffectScopes.PushArray(scope);
}

void LeaveEffectScope(int entity, int kind)
{
    // A projectile may delete itself inside Touch. Its SDKHooks post callback
    // can then be removed before it runs. Destruction cleanup may already have
    // removed this frame: never blindly pop an unrelated outer entity's scope.
    EffectScope scope;
    for (int i = g_EffectScopes.Length - 1; i >= 0; i--)
    {
        g_EffectScopes.GetArray(i, scope);
        if (scope.entity != entity || scope.kind != kind) continue;
        g_EffectScopes.Erase(i);
        break;
    }
}

void ForgetEffectScopes(int entity)
{
    if (g_EffectScopes == null) return;
    EffectScope scope;
    for (int i = g_EffectScopes.Length - 1; i >= 0; i--)
    {
        g_EffectScopes.GetArray(i, scope);
        if (scope.entity == entity) g_EffectScopes.Erase(i);
    }
}

int EffectSource()
{
    if (g_EffectScopes == null) return 0;
    EffectScope scope;
    for (int i = g_EffectScopes.Length - 1; i >= 0; i--)
    {
        g_EffectScopes.GetArray(i, scope);
        int entity = EntRefToEntIndex(scope.reference);
        if (entity != INVALID_ENT_REFERENCE) return entity;
    }
    return 0;
}

public Action EffectThinkPre(int entity)
{
    EnterEffectScope(entity, EffectScope_Think);
    return Plugin_Continue;
}
public void EffectThinkPost(int entity)
{
    LeaveEffectScope(entity, EffectScope_Think);
}
public Action EffectTouchPre(int entity, int other)
{
    EnterEffectScope(entity, EffectScope_Touch);
    return Plugin_Continue;
}
public void EffectTouchPost(int entity, int other)
{
    LeaveEffectScope(entity, EffectScope_Touch);
}

public MRESReturn EffectBulletsPre(int entity, DHookParam params)
{
    EnterEffectScope(entity, EffectScope_Bullets);
    return MRES_Ignored;
}

public MRESReturn EffectBulletsPost(int entity, DHookParam params)
{
    LeaveEffectScope(entity, EffectScope_Bullets);
    return MRES_Ignored;
}

public Action FilterEffect(const char[] name, const int[] recipients, int count, float delay)
{
    if (g_ReplayingEffect) return Plugin_Continue;
    int actor = EffectSource();
    if (StrEqual(name, "Fire Bullets")) actor = TE_ReadNum("m_iPlayer") + 1;
    else if (StrEqual(name, "Player Decal")) actor = TE_ReadNum("m_nPlayer");
    else if (!actor && TE_IsValidProp("entindex")) actor = TE_ReadNum("entindex");
    if (!actor) return Plugin_Continue;
    int kept[MAXPLAYERS], keptCount;
    for (int i = 0; i < count; i++) if (!HiddenEntity(recipients[i], actor)) kept[keptCount++] = recipients[i];
    if (keptCount == count) return Plugin_Continue;
    if (keptCount)
    {
        // SDKTools makes the current TE available during its interception hook.
        // Re-send the same fields synchronously with a reduced recipient filter.
        g_ReplayingEffect = true;
        TE_Send(kept, keptCount, delay);
        g_ReplayingEffect = false;
    }
    return Plugin_Handled;
}

void SilenceExistingLoops(int viewer, int subject)
{
    if (!IsClientInGame(viewer) || IsFakeClient(viewer) || !IsClientInGame(subject)) return;
    for (int entity = 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
        if (Actor(entity) == subject)
            EmitSoundToClient(viewer, "common/null.wav", entity, SNDCHAN_AUTO, SNDLEVEL_NONE, SND_STOPLOOPING, 0.0);
}
