// A private resource entity supplies each affected viewer's scoreboard. The
// canonical server resource is never edited, and other viewers keep it.
int g_Resource = INVALID_ENT_REFERENCE;
int g_PrivateResource[MAXPLAYERS + 1];
bool g_IsResource[ENTITY_LIMIT];
bool g_RosterStarted;

static const char g_ResourceInts[][] =
{
    "m_iPing", "m_iScore", "m_iDeaths", "m_bConnected", "m_iTeam", "m_bAlive",
    "m_iHealth", "m_iAccountID", "m_bValid", "m_iUserID", "m_iTotalScore",
    "m_iMaxHealth", "m_iMaxBuffedHealth", "m_iPlayerClass", "m_bArenaSpectator",
    "m_iActiveDominations", "m_iChargeLevel", "m_iDamage", "m_iDamageAssist",
    "m_iDamageBoss", "m_iHealing", "m_iHealingAssist", "m_iDamageBlocked",
    "m_iCurrencyCollected", "m_iBonusPoints", "m_iPlayerLevel", "m_iStreaks",
    "m_iUpgradeRefundCredits", "m_iBuybackCredits", "m_iPlayerClassWhenKilled",
    "m_iConnectionState"
};
static const char g_ResourceFloats[][] = { "m_flNextRespawnTime", "m_flConnectTime" };
static const char g_ResourceScalars[][] = { "m_iPartyLeaderRedTeamIndex", "m_iPartyLeaderBlueTeamIndex", "m_iEventTeamStatus" };
int g_IntSizes[sizeof(g_ResourceInts)];
int g_FloatSizes[sizeof(g_ResourceFloats)];
int g_SnapshotInts[sizeof(g_ResourceInts)][(MAXPLAYERS + 1) * 4];
bool g_DirtyInts[sizeof(g_ResourceInts)][(MAXPLAYERS + 1) * 4];
float g_SnapshotFloats[sizeof(g_ResourceFloats)][MAXPLAYERS + 1];
bool g_DirtyFloats[sizeof(g_ResourceFloats)][MAXPLAYERS + 1];
bool g_LastRosterMask[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_SnapshotReady;

void Roster_Reset()
{
    g_Resource = INVALID_ENT_REFERENCE;
    g_RosterStarted = false;
    g_SnapshotReady = false;
    for (int i = 0; i <= MaxClients; i++) g_PrivateResource[i] = INVALID_ENT_REFERENCE;
    for (int i = 0; i < ENTITY_LIMIT; i++) g_IsResource[i] = false;
}

void Roster_Start()
{
    if (g_RosterStarted) return;
    int resource = GetPlayerResourceEntity();
    if (resource <= MaxClients || !IsValidEntity(resource)) return;
    g_Resource = EntIndexToEntRef(resource);
    g_IsResource[resource] = true;
    for (int i = 0; i < sizeof(g_ResourceInts); i++)
    {
        g_IntSizes[i] = HasEntProp(resource, Prop_Send, g_ResourceInts[i]) ? GetEntPropArraySize(resource, Prop_Send, g_ResourceInts[i]) : 0;
        int limit = StrEqual(g_ResourceInts[i], "m_iStreaks") ? (MaxClients + 1) * 4 : MaxClients + 1;
        if (g_IntSizes[i] > limit) g_IntSizes[i] = limit;
    }
    for (int i = 0; i < sizeof(g_ResourceFloats); i++)
    {
        g_FloatSizes[i] = HasEntProp(resource, Prop_Send, g_ResourceFloats[i]) ? GetEntPropArraySize(resource, Prop_Send, g_ResourceFloats[i]) : 0;
        if (g_FloatSizes[i] > MaxClients + 1) g_FloatSizes[i] = MaxClients + 1;
    }
    if (g_IntSizes[3] <= MaxClients || g_IntSizes[8] <= MaxClients)
        SetFailState("Unexpected player-resource layout; refusing partial scoreboard hiding.");
    g_RosterStarted = true;
    Roster_Update();
}

int Roster_Create(int viewer)
{
    int entity = CreateEntityByName("tf_player_manager");
    if (entity < 1) return INVALID_ENT_REFERENCE;
    char name[64];
    FormatEx(name, sizeof(name), "oblivion_roster_%d", GetClientUserId(viewer));
    DispatchKeyValue(entity, "targetname", name);
    DispatchSpawn(entity);
    g_IsResource[entity] = true;
    SDKHook(entity, SDKHook_Think, Roster_BlockThink);
    return EntIndexToEntRef(entity);
}

public Action Roster_BlockThink(int entity)
{
    return Plugin_Handled;
}

void Roster_ReadSnapshot(int original)
{
    // Read the canonical resource once per update, regardless of how many
    // viewers have private copies. Only changed values are written to clones.
    for (int prop = 0; prop < sizeof(g_ResourceInts); prop++)
        for (int slot = 0; slot < g_IntSizes[prop]; slot++)
        {
            int value = GetEntProp(original, Prop_Send, g_ResourceInts[prop], _, slot);
            g_DirtyInts[prop][slot] = !g_SnapshotReady || value != g_SnapshotInts[prop][slot];
            g_SnapshotInts[prop][slot] = value;
        }
    for (int prop = 0; prop < sizeof(g_ResourceFloats); prop++)
        for (int slot = 0; slot < g_FloatSizes[prop]; slot++)
        {
            float value = GetEntPropFloat(original, Prop_Send, g_ResourceFloats[prop], slot);
            g_DirtyFloats[prop][slot] = !g_SnapshotReady || value != g_SnapshotFloats[prop][slot];
            g_SnapshotFloats[prop][slot] = value;
        }
    g_SnapshotReady = true;
}

void Roster_CopySnapshot(int original, int destination, int viewer, bool full)
{
    bool maskChanged[MAXPLAYERS + 1];
    for (int slot = 0; slot <= MaxClients; slot++)
        maskChanged[slot] = g_LastRosterMask[viewer][slot] != Hidden(viewer, slot);
    for (int prop = 0; prop < sizeof(g_ResourceInts); prop++)
    {
        for (int slot = 0; slot < g_IntSizes[prop]; slot++)
        {
            int subject = StrEqual(g_ResourceInts[prop], "m_iStreaks") ? slot / 4 : slot;
            bool hidden = Hidden(viewer, subject);
            if (!full && !maskChanged[subject] && (hidden || !g_DirtyInts[prop][slot])) continue;
            SetEntProp(destination, Prop_Send, g_ResourceInts[prop], hidden ? 0 : g_SnapshotInts[prop][slot], _, slot);
        }
    }
    for (int prop = 0; prop < sizeof(g_ResourceFloats); prop++)
        for (int slot = 0; slot < g_FloatSizes[prop]; slot++)
        {
            bool hidden = Hidden(viewer, slot);
            if (!full && !maskChanged[slot] && (hidden || !g_DirtyFloats[prop][slot])) continue;
            SetEntPropFloat(destination, Prop_Send, g_ResourceFloats[prop], hidden ? 0.0 : g_SnapshotFloats[prop][slot], slot);
        }
    for (int i = 0; i < sizeof(g_ResourceScalars); i++)
    {
        if (!HasEntProp(original, Prop_Send, g_ResourceScalars[i])) continue;
        int value = GetEntProp(original, Prop_Send, g_ResourceScalars[i]);
        if (i < 2 && Hidden(viewer, value)) value = 0;
        SetEntProp(destination, Prop_Send, g_ResourceScalars[i], value);
    }
    for (int slot = 0; slot <= MaxClients; slot++) g_LastRosterMask[viewer][slot] = Hidden(viewer, slot);
}

void Roster_Copy(int original, int destination, int viewer)
{
    Roster_ReadSnapshot(original);
    Roster_CopySnapshot(original, destination, viewer, true);
}

void Roster_Update()
{
    int resource = EntRefToEntIndex(g_Resource);
    if (!g_RosterStarted || resource == INVALID_ENT_REFERENCE) return;
    bool snapshotRead;
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!IsClientInGame(viewer) || IsFakeClient(viewer)) continue;
        int clone = EntRefToEntIndex(g_PrivateResource[viewer]);
        bool fresh;
        if (g_HasRules[viewer] && clone == INVALID_ENT_REFERENCE)
        {
            g_PrivateResource[viewer] = Roster_Create(viewer);
            clone = EntRefToEntIndex(g_PrivateResource[viewer]);
            fresh = true;
            if (clone == INVALID_ENT_REFERENCE) LogError("Unable to allocate private roster for client %d", viewer);
        }
        // Retain an existing clone through 'off': deleting it would clear the
        // stock client's global resource pointer until a new entity is created.
        if (clone != INVALID_ENT_REFERENCE)
        {
            if (!snapshotRead) { Roster_ReadSnapshot(resource); snapshotRead = true; }
            Roster_CopySnapshot(resource, clone, viewer, fresh);
        }
    }
}

public Action Roster_Transmit(int entity, int viewer)
{
    if (viewer < 1 || viewer > MaxClients) return Plugin_Continue;
    int clone = EntRefToEntIndex(g_PrivateResource[viewer]);
    int wanted = clone != INVALID_ENT_REFERENCE ? clone : EntRefToEntIndex(g_Resource);
    return entity == wanted ? Plugin_Continue : Plugin_Handled;
}

void Roster_Release()
{
    int resource = EntRefToEntIndex(g_Resource);
    if (resource == INVALID_ENT_REFERENCE) return;
    // Keep resource objects alive until map cleanup. Restore full data and their
    // stock Think before hooks disappear, avoiding a dangling client singleton.
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        int clone = EntRefToEntIndex(g_PrivateResource[viewer]);
        if (clone == INVALID_ENT_REFERENCE) continue;
        Roster_Copy(resource, clone, 0);
        SDKUnhook(clone, SDKHook_Think, Roster_BlockThink);
        if (HasEntProp(clone, Prop_Data, "m_nNextThinkTick"))
            SetEntProp(clone, Prop_Data, "m_nNextThinkTick", GetGameTickCount() + 1);
    }
}
