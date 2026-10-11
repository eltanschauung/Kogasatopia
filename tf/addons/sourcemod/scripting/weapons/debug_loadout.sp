// Debug-branch-only test API. Never writes real-client cookies or grants
// real-client entitlements. Lab grants are serial-bound; whitelist stays intact.
native void WeaponsLoadout_DebugEnable(bool enable);
native void WeaponsLoadout_DebugStats(float[] totals, float[] peaks, int size);
Handle g_WeaponsDebugNativeTimer;
bool g_WeaponsDebugHatGrant[MAXPLAYERS + 1][MAX_HATS];
int g_WeaponsDebugSerial[MAXPLAYERS + 1];
bool g_WeaponsDebugHatsEnabled[MAXPLAYERS + 1];

bool WeaponsDebug_IsBot(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client);
}

bool WeaponsDebug_HasProfile(int client)
{
    return WeaponsDebug_IsBot(client)
        && g_WeaponsDebugSerial[client] == GetClientSerial(client);
}

public any Native_WeaponsDebugHats(Handle plugin, int params)
{
    int client = GetNativeCell(1);
    if (!WeaponsDebug_IsBot(client)) return ThrowNativeError(SP_ERROR_NATIVE, "Debug targets must be ordinary bots");
    char state[2048];
    GetNativeString(2, state, sizeof(state));
    g_WeaponsDebugSerial[client]=GetClientSerial(client);
    g_WeaponsDebugHatsEnabled[client]=params>=3?GetNativeCell(3)!=0:true;
    RemoveHat(client, -1);
    ResetClientHatSelections(client);
    g_szHatIdChoice[client][0] = '\0';
    LoadStableHatStateChunk(client, state);
    for (int hat=0;hat<MAX_HATS;hat++) g_WeaponsDebugHatGrant[client][hat]=g_bHatEnabled[client][hat];
    NormalizeClientHatSlots(client);
    RecalculateClientEnabledHatCount(client);
    g_bHatStateLoaded[client] = true;
    g_bHatApplyPending[client] = true;
    return 1;
}

public any Native_WeaponsDebugHatCount(Handle plugin, int params)
{
    int client=GetNativeCell(1),count;
    if (!WeaponsDebug_IsBot(client)) return 0;
    for (int hat=0;hat<g_iHatCount;hat++) {
        int entity=EntRefToEntIndex(g_iHatRef[client][hat]);
        if (entity>MaxClients&&IsValidEntity(entity)) count++;
    }
    return count;
}

bool WeaponsDebug_HatGrant(int client,int hat)
{
    return WeaponsDebug_IsBot(client)&&g_WeaponsDebugSerial[client]==GetClientSerial(client)
        &&hat>=0&&hat<MAX_HATS&&g_WeaponsDebugHatGrant[client][hat];
}

bool WeaponsDebug_HatsDisabled(int client)
{
    return WeaponsDebug_IsBot(client)&&g_WeaponsDebugSerial[client]==GetClientSerial(client)
        &&!g_WeaponsDebugHatsEnabled[client];
}

bool WeaponsDebug_ItemGrant(int client,const CustomItemDefinition item)
{
    if (!WeaponsDebug_IsBot(client)||g_WeaponsDebugSerial[client]!=GetClientSerial(client)) return false;
    int playerClass=view_as<int>(TF2_GetPlayerClass(client));
    if (!Weapons_LoadoutClassValid(playerClass)) return false;
    int slot=item.loadoutPosition[playerClass];
    return slot>=0&&slot<NUM_ITEMS&&StrEqual(g_CurrentLoadout[client][playerClass][slot].override_uid,item.uid);
}

public any Native_WeaponsDebugReapplyHats(Handle plugin,int params)
{
    int client=GetNativeCell(1);
    if (!WeaponsDebug_IsBot(client)) return ThrowNativeError(SP_ERROR_NATIVE,"Debug targets must be ordinary bots");
    RemoveHat(client,-1);
    UpdateHatForClient(client);
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
