#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2_stocks>

#define TEAM_RED 2
#define TEAM_BLUE 3
#define TEAM_BALANCE_OPERATION_LEASE 5.0
#define TEAM_BALANCE_SETTLE_TIME 3.0
#define SQ_JOIN_RESERVATION_TIMEOUT 3.0
#include "controller_state.inc"

public Plugin myinfo = {
    name = "Unified team controller regression probe",
    author = "Kogasatopia",
    description = "Simulated clients; no real player moves or kicks.",
    version = "1.0"
};

TeamBalanceState g_eTeamBalanceState;
int g_iBalanceOperationGeneration;
float g_fTeamBalanceStateUntil;
float g_fImbalanceDetectedAt;
int g_iBalanceRespawnExpectedTeam[MAXPLAYERS + 1];
int g_iSpecQueuePendingUserIds[MAXPLAYERS + 1];
int g_iSpecQueuePendingTeams[MAXPLAYERS + 1];
bool g_bSpecQueuePendingFromQueue[MAXPLAYERS + 1];
Handle g_hSpecQueuePendingTimers[MAXPLAYERS + 1];
bool connected[MAXPLAYERS + 1];
bool fake[MAXPLAYERS + 1];
int teams[MAXPLAYERS + 1];
int userIds[MAXPLAYERS + 1];
bool queueOperational;
bool roundEnding;
bool scrambleCooldown;
float now;
int gProbePlayingLimit;
int respawnClears;
int swapClears;
int moves;
int checks;
int failures;

void Check(bool result, const char[] label) {
    checks++;
    if (!result) {
        failures++;
        PrintToServer("[ControllerProbe] FAIL: %s", label);
    }
}

float ProbeTime() { return now; }
bool ProbeInGame(int client) { return client > 0 && client <= MaxClients && connected[client]; }
bool ProbeFake(int client) { return fake[client]; }
int ProbeTeam(int client) { return teams[client]; }
int ProbeUserId(int client) { return userIds[client]; }
int ProbeSerial(int client) { return client; }
int ProbeFromSerial(int serial) { return ProbeInGame(serial) ? serial : 0; }
bool Client_IsHumanInGame(int client) { return ProbeInGame(client) && !fake[client]; }
bool IsGameTeam(int team) { return team >= 2 && team <= 5; }
bool TeamBalance_IsRoundEndingSoon() { return roundEnding; }
bool TeamBalance_IsScrambleCooldownActiveInternal() { return scrambleCooldown; }
bool TeamBalance_IsSessionOnTeam(int serial, int team) {
    return ProbeInGame(serial) && teams[serial] == team;
}
void TeamBalance_ClearRespawnState(int client) {
    g_iBalanceRespawnExpectedTeam[client] = 0;
    respawnClears++;
}
void ClearTeamSwapRequestsForClient(int client) {
    #pragma unused client
    swapClears++;
}
void LogBalance(const char[] format, any ...) {
    #pragma unused format
}
bool SpecQueue_IsPluginOperational() { return queueOperational; }
int SpecQueue_GetPlayingLimit() { return gProbePlayingLimit; }
bool SpecQueue_IsServerFull() {
    return SpecQueue_CountPlayingHumansLocally() + SpecQueue_GetPendingJoinCount() >= gProbePlayingLimit;
}
public Action SpecQueue_Timer_ExpirePendingJoin(Handle timer, any userId) {
    #pragma unused timer
    #pragma unused userId
    return Plugin_Stop;
}
void ProbeChangeTeam(int client, int team) {
    teams[client] = team;
    moves++;
    TeamBalance_OnClientTeamChanged(client, team);
}

#define GetEngineTime ProbeTime
#define IsClientConnected ProbeInGame
#define IsClientInGame ProbeInGame
#define IsFakeClient ProbeFake
#define GetClientTeam ProbeTeam
#define GetClientUserId ProbeUserId
#define GetClientSerial ProbeSerial
#define GetClientFromSerial ProbeFromSerial
#define ChangeClientTeam ProbeChangeTeam
#include "controller_under_test.inc"

void Reset() {
    SpecQueue_ClearAllPendingJoins();
    for (int client = 1; client <= MaxClients; client++) {
        connected[client] = fake[client] = false;
        teams[client] = g_iBalanceRespawnExpectedTeam[client] = 0;
        userIds[client] = 1000 + client;
    }
    connected[1] = connected[2] = connected[3] = true;
    teams[1] = TEAM_RED;
    teams[2] = TEAM_BLUE;
    teams[3] = 1;
    gProbePlayingLimit = 4;
    now = 100.0;
    queueOperational = true;
    roundEnding = scrambleCooldown = false;
    g_eTeamBalanceState = TeamBalance_Idle;
    g_fTeamBalanceStateUntil = 0.0;
    respawnClears = swapClears = moves = 0;
}

public void OnPluginStart() {
    RegAdminCmd("sm_team_controller_probe", Run, ADMFLAG_ROOT);
}

public Action Run(int client, int args) {
    checks = failures = 0;
    Reset();
    Check(TeamBalance_CanAdmitClients() && TeamBalance_CanRunAFKAction(), "idle permits admissions and AFK");
    Check(TeamBalance_TryBegin(TeamBalance_ScramblePending, 5.0, true), "scramble acquires coordinator");
    Check(!TeamBalance_CanAdmitClients() && !TeamBalance_CanRunAFKAction(), "scramble excludes admission and AFK");
    Check(!SpecQueue_ReservePendingJoin(3, true, 0), "busy coordinator rejects reservation");
    Check(!TeamBalance_TryBegin(TeamBalance_AFKRemoval, 5.0, true), "no overlapping move ownership");
    TeamBalance_FinishOperation(true);
    Check(!TeamBalance_CanAdmitClients(), "settling blocks promotion");
    now = 103.0;
    Check(TeamBalance_CanAdmitClients(), "settle lease expiry resumes admission");

    Reset();
    Check(SpecQueue_ReservePendingJoin(3, true, TEAM_RED), "spectator reserves RED destination");
    Check(SpecQueue_GetPendingJoinCount() == 1 && SpecQueue_GetPendingJoinCountForTeam(TEAM_RED) == 1,
        "reservation counted globally and per team");
    Check(!TeamBalance_TryBegin(TeamBalance_Autobalance, 5.0, true), "reservation blocks corrective autobalance");
    Check(!TeamBalance_TryBegin(TeamBalance_ManualSwap, 5.0, true), "reservation blocks manual pair swap");
    Check(!TeamBalance_TryBegin(TeamBalance_ScrambleVote, 5.0, true), "reservation blocks scramble vote ownership");
    Check(!TeamBalance_CanRunAFKAction(), "reservation postpones AFK action");
    Check(SpecQueue_ReservePendingJoin(3, true, TEAM_RED) && SpecQueue_GetPendingJoinCount() == 1,
        "repeated reservation does not double count");
    Check(SpecQueue_SelectPendingJoinTeam(0) == TEAM_BLUE, "pending RED slot affects next admission");
    Check(TeamBalance_TryBegin(TeamBalance_QueueJoin, 5.0, true), "promotion can own its reservation");
    Check(TeamBalance_CanAdmitClients(), "promotion's jointeam command can pass its own lease");
    teams[3] = TEAM_RED;
    Check(SpecQueue_GetPendingJoinCount() == 0 && g_hSpecQueuePendingTimers[3] == null,
        "confirmed join is not counted twice and timer is cancelled");
    TeamBalance_FinishOperation(true);
    Check(!TeamBalance_CanRunAFKAction(), "promotion settles before AFK action");

    Reset();
    connected[4] = fake[4] = true;
    teams[4] = TEAM_RED;
    Check(SpecQueue_CountPlayingHumansLocally() == 2 && SpecQueue_CountPlayingHumansOnTeam(TEAM_RED) == 1,
        "queue capacity remains human-only despite bots");
    Check(!SpecQueue_ReservePendingJoin(4, false, 0), "bots cannot reserve spectator slots");
    Check(SpecQueue_ReservePendingJoin(3, false, TEAM_RED), "bots do not consume human admission quota");
    connected[5] = true; teams[5] = 1;
    Check(!SpecQueue_ReservePendingJoin(5, false, TEAM_RED), "reserved team cannot be overbooked");
    Check(SpecQueue_ReservePendingJoin(5, false, TEAM_BLUE), "opposite team's remaining slot is available");
    connected[6] = true; teams[6] = 1;
    Check(!SpecQueue_ReservePendingJoin(6, false, 0), "global reservations enforce full capacity");
    userIds[3] = 9999;
    Check(!SpecQueue_HasPendingJoin(3), "reused client slot cannot inherit old reservation");
    SpecQueue_ClearPendingJoin(3);
    SpecQueue_ClearAllPendingJoins();
    Check(SpecQueue_GetPendingJoinCount() == 0, "map/disconnect cleanup releases all reservations");

    Reset();
    roundEnding = true;
    Check(!TeamBalance_TryBegin(TeamBalance_Autobalance, 5.0, true), "round-end autobalance policy retained");
    Check(TeamBalance_TryBegin(TeamBalance_AFKRemoval, 5.0, true), "AFK removal does not inherit round-end immunity");
    TeamBalance_FinishOperation(false);
    Check(TeamBalance_TryBegin(TeamBalance_QueueJoin, 5.0, true), "admission remains possible near round end");
    TeamBalance_FinishOperation(false);
    scrambleCooldown = true;
    Check(TeamBalance_TryBegin(TeamBalance_AFKRemoval, 5.0, true), "AFK removal does not inherit scramble cooldown");

    Reset();
    Check(TeamBalance_MoveToSpectator(1, "test_afk", true), "AFK removal changes team");
    Check(teams[1] == 1 && moves == 1 && g_eTeamBalanceState == TeamBalance_Settling,
        "successful AFK move enters settling");
    Check(respawnClears > 0 && swapClears > 0, "spectator move invalidates respawn and swap work");
    Check(!TeamBalance_MoveToSpectator(2, "test_afk", true) && teams[2] == TEAM_BLUE,
        "second AFK action waits for first move to settle");
    Reset();
    TeamBalance_SetState(TeamBalance_ScrambleMoving, 5.0);
    int generation = g_iBalanceOperationGeneration;
    Check(TeamBalance_MoveToSpectator(1, "voluntary"), "voluntary spectator exit is never locked out");
    Check(g_eTeamBalanceState == TeamBalance_ScrambleMoving && g_iBalanceOperationGeneration == generation,
        "voluntary exit does not steal another operation's lease");
    g_iBalanceRespawnExpectedTeam[2] = TEAM_RED;
    TeamBalance_OnClientTeamChanged(2, TEAM_BLUE);
    Check(g_iBalanceRespawnExpectedTeam[2] == 0, "unexpected team changes invalidate respawn retries");
    g_iBalanceRespawnExpectedTeam[2] = TEAM_BLUE;
    TeamBalance_OnClientTeamChanged(2, TEAM_BLUE);
    Check(g_iBalanceRespawnExpectedTeam[2] == TEAM_BLUE, "matching respawn remains owned");
    Check(g_fImbalanceDetectedAt == 0.0, "team change restarts imbalance age tracking");
    SpecQueue_ClearAllPendingJoins();
    PrintToServer("[ControllerProbe] %d assertions, %d failures", checks, failures);
    return Plugin_Handled;
}
