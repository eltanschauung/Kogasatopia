// Stock scoreboard headers count C_Team::player_array, independently of the
// player-resource rows. Each recipient keeps its own team entities from its
// first snapshot so later pairing changes never leave duplicate client teams.
#define OBLIVION_TEAMS 4
int g_TeamSources[OBLIVION_TEAMS];
int g_PrivateTeams[MAXPLAYERS + 1][OBLIVION_TEAMS];
bool g_IsTeam[ENTITY_LIMIT];
int g_TeamOwnerSerial[ENTITY_LIMIT];
bool g_TeamsStarted;
static const char g_TeamInts[][] = { "m_iTeamNum", "m_iScore", "m_iRoundsWon", "m_nFlagCaptures", "m_iRole" };

void Teams_Reset()
{
    g_TeamsStarted = false;
    OblivionNet_TeamClear();
    for (int team = 0; team < OBLIVION_TEAMS; team++)
    {
        g_TeamSources[team] = INVALID_ENT_REFERENCE;
        for (int client = 0; client <= MaxClients; client++) g_PrivateTeams[client][team] = INVALID_ENT_REFERENCE;
    }
    for (int entity = 0; entity < ENTITY_LIMIT; entity++)
    {
        g_IsTeam[entity] = false;
        g_TeamOwnerSerial[entity] = 0;
    }
}

void Teams_Start()
{
    if (g_TeamsStarted) return;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "tf_team")) != -1)
    {
        if (entity >= ENTITY_LIMIT || g_TeamOwnerSerial[entity]) continue;
        int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
        if (team < 0 || team >= OBLIVION_TEAMS) continue;
        g_IsTeam[entity] = true;
        g_TeamSources[team] = EntIndexToEntRef(entity);
    }
    for (int team = 0; team < OBLIVION_TEAMS; team++)
        if (EntRefToEntIndex(g_TeamSources[team]) == INVALID_ENT_REFERENCE) return;
    g_TeamsStarted = true;
}

void Teams_Copy(int source, int mirror, int viewer)
{
    for (int i = 0; i < sizeof(g_TeamInts); i++)
    {
        int value = GetEntProp(source, Prop_Send, g_TeamInts[i]);
        if (GetEntProp(mirror, Prop_Send, g_TeamInts[i]) != value) SetEntProp(mirror, Prop_Send, g_TeamInts[i], value);
    }
    char name[64], previous[64];
    GetEntPropString(source, Prop_Send, "m_szTeamname", name, sizeof(name));
    GetEntPropString(mirror, Prop_Send, "m_szTeamname", previous, sizeof(previous));
    if (!StrEqual(name, previous)) SetEntPropString(mirror, Prop_Send, "m_szTeamname", name);
    int leader = GetEntPropEnt(source, Prop_Send, "m_hLeader");
    if (Hidden(viewer, leader)) leader = -1;
    if (GetEntPropEnt(mirror, Prop_Send, "m_hLeader") != leader) SetEntPropEnt(mirror, Prop_Send, "m_hLeader", leader);
    OblivionNet_TeamUpdate(mirror, source, g_Hidden[viewer], MaxClients + 1);
}

void Teams_Ensure(int viewer)
{
    if (!g_TeamsStarted) return;
    for (int team = 0; team < OBLIVION_TEAMS; team++)
    {
        int source = EntRefToEntIndex(g_TeamSources[team]);
        if (source == INVALID_ENT_REFERENCE) continue;
        int mirror = EntRefToEntIndex(g_PrivateTeams[viewer][team]);
        if (mirror == INVALID_ENT_REFERENCE)
        {
            // CreateEntityByName does not register teams in the game rules;
            // CTFTeamManager::CreateTeam performs that separately for real teams.
            mirror = CreateEntityByName("tf_team");
            if (mirror < 1 || mirror >= ENTITY_LIMIT)
            {
                LogError("Could not create private team %d for viewer %d.", team, viewer);
                continue;
            }
            char name[64];
            FormatEx(name, sizeof(name), "oblivion_team_%d_%d", GetClientUserId(viewer), team);
            DispatchKeyValue(mirror, "targetname", name);
            DispatchSpawn(mirror);
            g_IsTeam[mirror] = true;
            g_TeamOwnerSerial[mirror] = GetClientSerial(viewer);
            g_PrivateTeams[viewer][team] = EntIndexToEntRef(mirror);
        }
        Teams_Copy(source, mirror, viewer);
    }
}

void Teams_Update()
{
    if (!g_MapActive) return;
    Teams_Start();
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client) && !g_BrowserDisconnecting[client]) Teams_Ensure(client);
}

bool Teams_Blocked(int entity, int viewer)
{
    // Canonical entities are never sent to a player. Their client counterpart
    // would otherwise stay first in g_Teams even after becoming dormant.
    return !g_TeamOwnerSerial[entity] || g_TeamOwnerSerial[entity] != GetClientSerial(viewer);
}

void Teams_Remove(int viewer)
{
    for (int team = 0; team < OBLIVION_TEAMS; team++)
    {
        int mirror = EntRefToEntIndex(g_PrivateTeams[viewer][team]);
        g_PrivateTeams[viewer][team] = INVALID_ENT_REFERENCE;
        if (mirror == INVALID_ENT_REFERENCE) continue;
        OblivionNet_TeamForget(mirror);
        RemoveEntity(mirror);
    }
}

void Teams_Release()
{
    // C_Team removes itself from its client list on deletion; unlike the
    // player-resource singleton, these mirrors can be deleted on unload.
    for (int client = 1; client <= MaxClients; client++) Teams_Remove(client);
    OblivionNet_TeamClear();
}

void Teams_Status(int client)
{
    int viewers;
    for (int viewer = 1; viewer <= MaxClients; viewer++)
        if (EntRefToEntIndex(g_PrivateTeams[viewer][2]) != INVALID_ENT_REFERENCE) viewers++;
    ReplyToCommand(client, "[Oblivion] Team counters: %s; %d viewers with private team arrays.",
        g_TeamsStarted ? "ready" : "waiting for teams", viewers);
}
