// Debug-branch-only test API. Never writes real-client cookies or bypasses
// entitlement/whitelist checks. Every mutating target must be a normal bot.
native void WeaponsLoadout_DebugEnable(bool enable);
native void WeaponsLoadout_DebugStats(float[] totals, float[] peaks, int size);
Handle g_WeaponsDebugNativeTimer;

bool WeaponsDebug_IsBot(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client);
}

public any Native_WeaponsDebugHats(Handle plugin, int params)
{
    int client = GetNativeCell(1);
    if (!WeaponsDebug_IsBot(client)) return ThrowNativeError(SP_ERROR_NATIVE, "Debug targets must be ordinary bots");
    char state[2048];
    GetNativeString(2, state, sizeof(state));
    RemoveHat(client, -1);
    ResetClientHatSelections(client);
    g_szHatIdChoice[client][0] = '\0';
    LoadStableHatStateChunk(client, state);
    NormalizeClientHatSlots(client);
    RecalculateClientEnabledHatCount(client);
    g_bHatStateLoaded[client] = true;
    g_bHatApplyPending[client] = true;
    return 1;
}

public any Native_WeaponsDebugReapply(Handle plugin, int params)
{
    int client = GetNativeCell(1);
    if (!WeaponsDebug_IsBot(client)) return ThrowNativeError(SP_ERROR_NATIVE, "Debug targets must be ordinary bots");
    g_bForceReequipItems[client] = true;
    TF2_RegeneratePlayer(client);
    ApplyClientCustomLoadout(client);
    return 1;
}

public Action WeaponsDebug_NativeTimer(Handle timer)
{
    WeaponsLoadout_DebugEnable(GetFeatureStatus(FeatureType_Native, "CheckLag_IsProfilingEnabled") == FeatureStatus_Available
        && CheckLag_IsProfilingEnabled());
    return Plugin_Continue;
}

void WeaponsDebug_Init()
{
    g_WeaponsDebugNativeTimer = CreateTimer(1.0, WeaponsDebug_NativeTimer, _, TIMER_REPEAT);
}

void WeaponsDebug_Shutdown()
{
    delete g_WeaponsDebugNativeTimer;
    WeaponsLoadout_DebugEnable(false);
}
