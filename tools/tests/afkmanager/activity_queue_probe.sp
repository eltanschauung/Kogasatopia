#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <afkmanager>

#define SQ_ACTIVITY_QUEUE_INTERVAL 3.0
#define SQ_ACTIVITY_QUEUE_IMMUNITY 60.0
#include "activity_queue_state.inc"

public Plugin myinfo = {
    name = "Spectator activity queue regression probe",
    author = "Kogasatopia",
    description = "Runs extracted production functions against simulated clients.",
    version = "1.0"
};

enum struct Toggle {
    bool BoolValue;
    int IntValue;
    float FloatValue;
}
bool inQueue[MAXPLAYERS + 1];
enum struct Queue {
    int Length;
    bool InQueue(int client) {
        return inQueue[client];
    }
    bool IsEmpty() {
        return this.Length == 0;
    }
}
Toggle g_cvSpecQueueAutoJoin;
Queue g_SpecQueue;
bool human[MAXPLAYERS + 1];
bool spectator[MAXPLAYERS + 1];
bool pending[MAXPLAYERS + 1];
float activity[MAXPLAYERS + 1];
float g_flSpecQueueActivityBaseline[MAXPLAYERS + 1];
float g_flSpecQueueImmuneUntil[MAXPLAYERS + 1];
Handle g_hSpecQueuePendingTimers[MAXPLAYERS + 1];
int g_iSpecQueuePendingUserIds[MAXPLAYERS + 1];
int g_iSpecQueuePendingTeams[MAXPLAYERS + 1];
bool g_bSpecQueuePendingFromQueue[MAXPLAYERS + 1];
AFKClientState g_AFKClients[MAXPLAYERS + 1];
Toggle g_cvAFKAction;
Toggle g_cvAFKMinPlayerCount;
Toggle g_cvAFKAliveTime;
Toggle g_cvAFKSpecTime;
Toggle g_cvAFKSpecMovedTime;
int teams[MAXPLAYERS + 1];
bool alive[MAXPLAYERS + 1];
TFClassType classes[MAXPLAYERS + 1];
bool gProbeCanKickSpectators;
bool gProbeTeamBusy;
bool gProbeWhitelistAvailable;
int gProbeWhitelistLevel;
int population;
int kicks;
int moves;
float gProbeTime;
bool operational;
bool serverFull;
int reads;
int scheduled;
int notices;
int assertions;
int failures;

void CheckLiveNative() {
    if (GetFeatureStatus(FeatureType_Native, "AFKManager_GetLastActivityTime") != FeatureStatus_Available) {
        SetFailState("Updated AFKManager native is unavailable");
    }
    Check(AFKManager_GetLastActivityTime(0) == 0.0, "invalid-client API result");
    Check(AFKManager_GetLastActivityTime(MAXPLAYERS + 1) == 0.0, "out-of-range API result");
}

public void OnPluginStart() {
    RegAdminCmd("sm_activity_queue_probe", RunProbe, ADMFLAG_ROOT);
}

void Check(bool result, const char[] label) {
    assertions++;
    if (!result) {
        failures++;
        PrintToServer("[ActivityProbe] FAIL: %s", label);
    }
}

void ResetScenario() {
    gProbeTime = 100.0;
    operational = g_cvSpecQueueAutoJoin.BoolValue = true;
    serverFull = true;
    reads = scheduled = notices = 0;
    g_SpecQueue.Length = 0;
    for (int client = 1; client <= MaxClients; client++) {
        human[client] = spectator[client] = inQueue[client] = pending[client] = false;
        activity[client] = g_flSpecQueueImmuneUntil[client] = 0.0;
        g_flSpecQueueActivityBaseline[client] = 90.0;
    }
    human[1] = spectator[1] = true;
    activity[1] = 99.0;
    teams[1] = 2;
    alive[1] = true;
    classes[1] = TFClass_Soldier;
    gProbeCanKickSpectators = true;
    gProbeTeamBusy = false;
    gProbeWhitelistAvailable = true;
    gProbeWhitelistLevel = 0;
    population = 24;
    kicks = moves = 0;
    g_cvAFKAction.IntValue = 1;
    g_cvAFKMinPlayerCount.IntValue = 2;
    g_cvAFKAliveTime.FloatValue = 60.0;
    g_cvAFKSpecTime.FloatValue = 300.0;
    g_cvAFKSpecMovedTime.FloatValue = 180.0;
    AFK_ResetClient(1);
}

float ProbeTime() { return gProbeTime; }
float ProbeActivity(int client) { reads++; return activity[client]; }
void ProbeChat(int client, const char[] format, any ...) {
    #pragma unused client
    #pragma unused format
    notices++;
}
void SpecQueue_UpdateQueueSuspension() {}
bool SpecQueue_IsPluginOperational() { return operational; }
bool SpecQueue_IsServerFull() { return serverFull; }
void SpecQueue_PruneWaitQueue() {
    g_SpecQueue.Length = 0;
    for (int client = 1; client <= MAXPLAYERS; client++) {
        if (inQueue[client] && (!human[client] || !spectator[client])) {
            inQueue[client] = false;
        }
        if (inQueue[client]) {
            g_SpecQueue.Length++;
        }
    }
}
bool Client_IsHumanInGame(int client) {
    return client > 0 && client <= MaxClients && human[client];
}
bool SpecQueue_IsQueuedSpectator(int client) { return Client_IsHumanInGame(client) && spectator[client]; }
bool SpecQueue_HasPendingJoin(int client) { return pending[client]; }
bool SpecQueue_AddClientToWaitQueue(int client, const char[] reason) {
    #pragma unused reason
    if (!SpecQueue_IsQueuedSpectator(client) || inQueue[client]) { return false; }
    inQueue[client] = true;
    g_SpecQueue.Length++;
    return true;
}
void SpecQueue_SchedulePlayerChangeChecks() { scheduled++; }
int ProbeUserId(int userId) { return userId == 1001 ? 1 : 0; }
void SpecQueue_LogPopulationSnapshot(const char[] eventName, int client = 0,
    int oldTeam = -1, int newTeam = -1, int userId = 0, const char[] reason = "") {
    #pragma unused eventName
    #pragma unused client
    #pragma unused oldTeam
    #pragma unused newTeam
    #pragma unused userId
    #pragma unused reason
}
public Action ProbeTimer(Handle timer) { return Plugin_Stop; }
int ProbeCount(bool inGameOnly) {
    #pragma unused inGameOnly
    return population;
}
int ProbeTeam(int client) { return teams[client]; }
int ProbeWhitelistLevel(int client) {
    #pragma unused client
    return gProbeWhitelistLevel;
}
FeatureStatus ProbeFeatureStatus(FeatureType type, const char[] name) {
    #pragma unused type
    #pragma unused name
    return gProbeWhitelistAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}
bool ProbeAlive(int client) { return alive[client]; }
TFClassType ProbeClass(int client) { return classes[client]; }
bool AFK_CanKickSpectators() { return gProbeCanKickSpectators; }
bool TeamBalance_CanRunAFKAction() { return !gProbeTeamBusy; }
bool AFK_KickClient(int client) {
    #pragma unused client
    kicks++;
    return true;
}
void AFK_MoveToSpectator(int client, float time) {
    moves++;
    teams[client] = 1;
    AFK_ResetIdle(client, time);
}

#define GetEngineTime ProbeTime
#define GetFeatureStatus ProbeFeatureStatus
#define AdminsDB_GetClientWhitelistLevel ProbeWhitelistLevel
#define AFK_GetLastActivityTime ProbeActivity
#define GetClientCount ProbeCount
#define GetClientTeam ProbeTeam
#define GetClientOfUserId ProbeUserId
#define IsPlayerAlive ProbeAlive
#define TF2_GetPlayerClass ProbeClass
#define CPrintToChat ProbeChat
#include "activity_queue_under_test.inc"

public Action RunProbe(int client, int args) {
    assertions = failures = 0;
    CheckLiveNative();

    ResetScenario();
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1] && scheduled == 1 && notices == 1, "fresh spectator activity queues once");
    SpecQueue_CheckActivity(gProbeTime);
    Check(scheduled == 1 && notices == 1, "queued client is not repeated");

    ResetScenario(); serverFull = false;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0 && scheduled == 0 && notices == 0,
        "spare capacity with no queue leaves spectators alone");
    Check(g_flSpecQueueActivityBaseline[1] == 100.0,
        "inactive queue discards spectator activity");
    serverFull = true; gProbeTime = 102.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "input from before queue activation is not replayed");
    activity[1] = 101.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1], "fresh input can queue once playing teams are full");

    ResetScenario(); serverFull = false;
    human[2] = spectator[2] = inQueue[2] = true;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1] && inQueue[2] && scheduled == 1,
        "existing waiting queue accepts fresh input while a slot is available");

    ResetScenario(); serverFull = false; inQueue[2] = true;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && !inQueue[2], "stale queue entries do not enable autoqueue");

    ResetScenario(); serverFull = false; pending[2] = true;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "pending join alone does not enable activity autoqueue");

    ResetScenario(); activity[1] = 0.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "no observed input stays unqueued");

    ResetScenario(); activity[1] = 90.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "activity before spectator baseline stays unqueued");

    ResetScenario(); pending[1] = true;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0, "pending join is not queued again");

    ResetScenario(); spectator[1] = false;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0, "playing client is skipped");

    ResetScenario(); human[1] = false;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0, "bots and disconnected clients are skipped");

    ResetScenario(); operational = false;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0, "inactive or suspended queue is skipped");

    ResetScenario(); g_cvSpecQueueAutoJoin.BoolValue = false;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1] && reads == 0, "automatic queue convar is respected");

    ResetScenario(); SpecQueue_SuppressActivityAutoQueue(1);
    Check(g_flSpecQueueImmuneUntil[1] == 160.0 && g_flSpecQueueActivityBaseline[1] == 100.0, "command grants 60 seconds");
    gProbeTime = 159.0; activity[1] = 158.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "input during immunity is ignored");
    gProbeTime = 163.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "ignored input is not replayed after immunity");
    activity[1] = 162.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1], "new post-immunity input queues");

    ResetScenario(); SpecQueue_SuppressActivityAutoQueue(1, 300.0);
    Check(g_flSpecQueueImmuneUntil[1] == 400.0, "spectator command grants five minutes");
    gProbeTime = 399.0; activity[1] = 398.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "spectator immunity lasts the full five minutes");
    gProbeTime = 403.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "spectator immunity input is not replayed");
    activity[1] = 402.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1], "fresh input queues after spectator immunity expires");

    ResetScenario(); g_flSpecQueueImmuneUntil[1] = 160.0;
    gProbeTime = 163.0; activity[1] = 159.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(!inQueue[1], "unpolled input inside immunity is also discarded");
    activity[1] = 160.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1], "input at exact immunity expiry is allowed");

    ResetScenario(); g_flSpecQueueImmuneUntil[1] = 160.0;
    SpecQueue_ResetAutoQueueActivityBaselines();
    Check(g_flSpecQueueActivityBaseline[1] == gProbeTime && g_flSpecQueueImmuneUntil[1] == 160.0, "map/resume reset keeps unexpired immunity");

    ResetScenario(); human[2] = spectator[2] = true; activity[2] = 99.0;
    SpecQueue_CheckActivity(gProbeTime);
    Check(inQueue[1] && inQueue[2] && scheduled == 1, "multiple spectators share one reconciliation");

    ResetScenario();
    Check(g_AFKClients[1].lastActivityTime == 0.0, "client reset does not invent activity");
    AFK_ResetIdle(1, gProbeTime);
    Check(g_AFKClients[1].lastActivityTime == 0.0, "idle bookkeeping does not invent activity");
    AFK_RecordActivity(1);
    Check(g_AFKClients[1].lastActivityTime == gProbeTime, "actual input records engine timestamp");
    gProbeTime = 103.0; human[1] = false; AFK_RecordActivity(1);
    Check(g_AFKClients[1].lastActivityTime == 100.0, "non-human input does not update activity");

    ResetScenario();
    AFK_AdvanceIdle(1, 103.0, true);
    AFK_AdvanceIdle(1, 120.0, false);
    Check(g_AFKClients[1].idleSeconds == 3.0, "paused dead time is not counted");
    AFK_AdvanceIdle(1, 124.0, true);
    Check(g_AFKClients[1].idleSeconds == 7.0, "live time resumes without losing prior idle time");
    gProbeTime = 125.0; AFK_RecordActivity(1);
    Check(g_AFKClients[1].idleSeconds == 0.0 && g_AFKClients[1].lastIdleCheck == 125.0, "input resets idle accounting immediately");
    AFK_AdvanceIdle(1, 124.0, true);
    Check(g_AFKClients[1].idleSeconds == 0.0, "negative time delta does not decrease idle time");

    ResetScenario(); AFK_ManageClients(160.0);
    Check(moves == 0 && kicks == 0, "live timeout is not premature at exact threshold");
    AFK_ManageClients(161.0);
    Check(moves == 1 && kicks == 0, "idle live player is moved to spectator");

    ResetScenario(); g_cvAFKAction.IntValue = 0; AFK_ManageClients(161.0);
    Check(kicks == 1 && moves == 0, "kick action kicks instead of spectating");

    ResetScenario(); gProbeTeamBusy = true; AFK_ManageClients(161.0);
    Check(moves == 0 && g_AFKClients[1].idleSeconds == 61.0,
        "busy coordinator defers AFK move without resetting accrued idle time");
    gProbeTeamBusy = false; AFK_ManageClients(162.0);
    Check(moves == 1, "deferred AFK move resumes when coordinator is idle");

    ResetScenario(); alive[1] = false; AFK_ManageClients(200.0);
    Check(moves == 0 && g_AFKClients[1].idleSeconds == 0.0, "dead players with a selected class pause idle time");
    classes[1] = TFClass_Unknown; AFK_ManageClients(261.0);
    Check(moves == 1, "idle class-selection menu still counts");

    ResetScenario(); gProbeWhitelistLevel = 2; AFK_ManageClients(220.0);
    Check(moves == 0, "whitelist level 2 doubles live timeout");
    AFK_ManageClients(221.0);
    Check(moves == 1, "whitelist bonus expires at doubled timeout");
    for (int level = -2; level <= 3; level++) {
        if (level == 2) { continue; }
        ResetScenario(); gProbeWhitelistLevel = level; AFK_ManageClients(161.0);
        Check(moves == 1, "other whitelist levels use normal timeout");
    }
    ResetScenario(); gProbeWhitelistLevel = 2; gProbeWhitelistAvailable = false;
    AFK_ManageClients(161.0);
    Check(moves == 1, "missing whitelist API uses normal timeout");
    ResetScenario(); gProbeWhitelistLevel = 2; AFK_ManageClients(170.0);
    gProbeWhitelistLevel = 0; AFK_ManageClients(171.0);
    Check(moves == 1, "whitelist changes apply without reconnecting");

    ResetScenario(); teams[1] = 1; g_AFKClients[1].movedToSpec = true;
    AFK_ManageClients(281.0);
    Check(kicks == 1, "AFK-moved spectators use their separate timeout");

    ResetScenario(); teams[1] = 1; AFK_ManageClients(281.0);
    Check(kicks == 0, "voluntary spectators retain the ordinary timeout");
    AFK_ManageClients(401.0);
    Check(kicks == 1, "ordinary spectator timeout expires");

    ResetScenario(); teams[1] = 1; g_cvAFKAction.IntValue = 2; AFK_ManageClients(500.0);
    Check(kicks == 0, "spectate-only action never kicks spectators");

    ResetScenario(); teams[1] = 1; gProbeCanKickSpectators = false; AFK_ManageClients(500.0);
    Check(kicks == 0 && g_AFKClients[1].idleSeconds == 0.0, "spectator population gate resets only idle state");

    ResetScenario(); population = 1; AFK_ManageClients(500.0);
    Check(kicks == 0 && moves == 0 && g_AFKClients[1].idleSeconds == 0.0, "below-minimum population prevents AFK actions");

    ResetScenario(); inQueue[1] = true;
    Check(SpecQueue_BlocksAFKKick(1), "queued spectator is protected from AFK kick");
    inQueue[1] = false; pending[1] = true;
    Check(SpecQueue_BlocksAFKKick(1), "pending promotion is protected from AFK kick");
    operational = false;
    Check(!SpecQueue_BlocksAFKKick(1), "disabled queue does not grant AFK immunity");

    ResetScenario();
    Handle stale = CreateTimer(30.0, ProbeTimer, _, TIMER_FLAG_NO_MAPCHANGE);
    g_hSpecQueuePendingTimers[1] = stale;
    g_iSpecQueuePendingUserIds[1] = 1001;
    SpecQueue_ClearPendingJoin(1);
    Check(g_hSpecQueuePendingTimers[1] == null && g_iSpecQueuePendingUserIds[1] == 0,
        "clearing a reservation cancels its timer and state");
    Handle current = CreateTimer(30.0, ProbeTimer, _, TIMER_FLAG_NO_MAPCHANGE);
    g_hSpecQueuePendingTimers[1] = current;
    g_iSpecQueuePendingUserIds[1] = 1001;
    g_bSpecQueuePendingFromQueue[1] = true;
    SpecQueue_Timer_ExpirePendingJoin(stale, 1001);
    Check(g_hSpecQueuePendingTimers[1] == current && g_iSpecQueuePendingUserIds[1] == 1001,
        "old timeout cannot clear a newer reservation");
    SpecQueue_Timer_ExpirePendingJoin(current, 999);
    Check(g_iSpecQueuePendingUserIds[1] == 1001, "wrong-user timeout cannot clear reservation");
    SpecQueue_Timer_ExpirePendingJoin(current, 1001);
    Check(g_hSpecQueuePendingTimers[1] == null && g_iSpecQueuePendingUserIds[1] == 0 && inQueue[1],
        "matching failed promotion clears itself and requeues");
    delete current;

    g_hSpecQueuePendingTimers[1] = CreateTimer(30.0, ProbeTimer, _, TIMER_FLAG_NO_MAPCHANGE);
    g_iSpecQueuePendingUserIds[1] = 1001;
    SpecQueue_ClearAllPendingJoins();
    Check(g_hSpecQueuePendingTimers[1] == null && g_iSpecQueuePendingUserIds[1] == 0,
        "map/shutdown cleanup cancels all reservations");

    PrintToServer("[ActivityProbe] %d assertions, %d failures", assertions, failures);
    return Plugin_Handled;
}
