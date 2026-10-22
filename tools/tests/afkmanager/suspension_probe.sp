#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
int clears, pendingClears, cancels, resets, schedules, failures;

enum struct Toggle {
    int IntValue;
}
enum struct Queue {
    int unused;
    void Clear() { clears++; }
}
Toggle g_cvSpecQueueSuspendAt;
Queue g_SpecQueue;
bool g_bSpecQueueConfigsExecuted = true;
bool g_bSpecQueueSuspended;
bool enabled = true;
int population, limit = 24;

bool SpecQueue_IsPluginEnabled() { return enabled; }
int SpecQueue_GetPlayingLimit() { return limit; }
int SpecQueue_CountQueueHumans() { return population; }
void SpecQueue_CancelPlayerChangeChecks() { cancels++; }
void SpecQueue_ClearAllPendingJoins() { pendingClears++; }
void SpecQueue_ResetAutoQueueActivityBaselines() { resets++; }
void SpecQueue_SchedulePlayerChangeChecks() { schedules++; }
void SpecQueue_LogPopulationSnapshot(const char[] eventName, int client = 0,
    int oldTeam = -1, int newTeam = -1, int userId = 0, const char[] reason = "") {}
void CReplyToCommand(int client, const char[] message) {}

#include "suspension_under_test.inc"

void Check(bool condition) {
    if (!condition) failures++;
}

public void OnPluginStart() {
    g_cvSpecQueueSuspendAt.IntValue = 28;
    population = 26;
    SpecQueue_UpdateQueueSuspension();
    Check(!g_bSpecQueueSuspended);
    SpecQueue_Cmd_StopQueue(0, 0);
    Check(g_bSpecQueueSuspended && clears == 1 && pendingClears == 1 && cancels == 1);
    SpecQueue_UpdateQueueSuspension();
    Check(g_bSpecQueueSuspended);
    SpecQueue_Cmd_StopQueue(0, 0);
    Check(clears == 1);
    population = 25;
    SpecQueue_UpdateQueueSuspension();
    Check(g_bSpecQueueSuspended);
    population = 24;
    SpecQueue_UpdateQueueSuspension();
    Check(!g_bSpecQueueSuspended && resets == 1 && schedules == 1);
    population = 28;
    SpecQueue_UpdateQueueSuspension();
    Check(g_bSpecQueueSuspended && clears == 2);
    population = 23;
    SpecQueue_UpdateQueueSuspension();
    Check(!g_bSpecQueueSuspended);
    enabled = false;
    SpecQueue_Cmd_StopQueue(0, 0);
    Check(!g_bSpecQueueSuspended);
    enabled = true;
    g_bSpecQueueConfigsExecuted = false;
    SpecQueue_Cmd_StopQueue(0, 0);
    Check(!g_bSpecQueueSuspended);
    g_bSpecQueueConfigsExecuted = true;
    limit = -1;
    SpecQueue_Cmd_StopQueue(0, 0);
    Check(!g_bSpecQueueSuspended);
    PrintToServer("[QueueSuspensionProbe] 11 checks, %d failures", failures);
}
