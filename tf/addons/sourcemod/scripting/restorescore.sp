/*
 * Restore Score — based on F2's plugin and Kogasatopia's score adjustments.
 * 1.2.0: send scoreboard adjustments through restore_score.ext; never write
 * m_iTotalScore, which TF2 also uses as its Strange/MvM scoring baseline.
 * The original upstream auto-updater is intentionally not registered by this
 * fork: it could replace the fix with the incompatible original plugin.
 */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2_stocks>
#include <restore_score_display>

#define PLUGIN_VERSION "1.2.0"
public Plugin myinfo = {
    name = "Restore Score", author = "F2; Kogasatopia; Codex",
    description = "Restore and adjust scoreboard totals without changing Strange scoring",
    version = PLUGIN_VERSION, url = "https://github.com/eltanschauung/Kogasatopia"
};

int g_iAddScore[MAXPLAYERS + 1];
int g_iScoreAdjustment[MAXPLAYERS + 1];
int g_iQualifyingTeleports[MAXPLAYERS + 1];
StringMap g_OldScores;
bool g_Ready;

bool IsRealPlayer(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && !IsClientSourceTV(client) && !IsClientReplay(client);
}
int DisplayedScore(int client) {
    int resource = GetPlayerResourceEntity();
    if (resource == -1) return -1;
    return RSDisplay_Calculate(GetEntProp(resource, Prop_Send, "m_iTotalScore", _, client),
        g_iAddScore[client], g_iScoreAdjustment[client]);
}
void Publish(int client) {
    if (g_Ready) RSDisplay_Set(client, g_iAddScore[client], g_iScoreAdjustment[client]);
}
void ClearClient(int client) {
    g_iAddScore[client] = 0;
    g_iScoreAdjustment[client] = 0;
    g_iQualifyingTeleports[client] = 0;
    Publish(client);
}
void ResetOldScores() {
    g_OldScores.Clear();
    for (int client = 1; client <= MaxClients; client++) ClearClient(client);
}
bool RestoreSavedScore(int client, const char[] steamid) {
    int saved;
    if (!g_OldScores.GetValue(steamid, saved)) return false;
    g_OldScores.Remove(steamid);
    g_iAddScore[client] = saved;
    Publish(client);
    return true;
}
void RememberScore(int client, const char[] steamid) {
    int score = DisplayedScore(client);
    if (score > 0) g_OldScores.SetValue(steamid, score);
    else g_OldScores.Remove(steamid);
}
void TryRestore(int client) {
    if (!IsRealPlayer(client) || IsFakeClient(client)) return;
    char steamid[64];
    if (GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true))
        RestoreSavedScore(client, steamid);
}
public void OnPluginStart() {
    if (GetEngineVersion() != Engine_TF2 || RSDisplay_ApiVersion() != 1)
        SetFailState("Requires TF2 and the matching Restore Score Display extension.");
    g_OldScores = new StringMap();
    g_Ready = true;
    RSDisplay_Reset();
    HookEvent("player_death", Event_player_death, EventHookMode_Post);
    HookEvent("player_teleported", Event_player_teleported, EventHookMode_Post);
    HookEvent("player_activate", Event_player_activate, EventHookMode_Post);
    HookEvent("teamplay_restart_round", Event_restart_round, EventHookMode_Post);
    RegAdminCmd("sm_restorescore_status", Command_Status, ADMFLAG_ROOT, "Inspect raw and displayed scores.");
#if defined RESTORESCORE_TEST
    TestStart();
#endif
}
public void OnPluginEnd() {
    if (g_Ready) RSDisplay_Reset();
    g_Ready = false;
    delete g_OldScores;
}
public void OnMapStart() {
    if (g_Ready) ResetOldScores();
#if defined RESTORESCORE_TEST
    TestMapStart();
#endif
}
public void Event_restart_round(Event event, const char[] name, bool dontBroadcast) { ResetOldScores(); }
public void OnClientConnected(int client) { ClearClient(client); }
public void OnClientPutInServer(int client) { TryRestore(client); }
public void OnClientAuthorized(int client, const char[] auth) { TryRestore(client); }
public void OnClientPostAdminCheck(int client) { TryRestore(client); }
public void Event_player_activate(Event event, const char[] name, bool dontBroadcast) {
    TryRestore(GetClientOfUserId(event.GetInt("userid")));
}
// SourceMod runs this forward before decrementing its player count and before
// the game's ClientDisconnect. Capture the display offset while it still exists.
public void OnClientDisconnect(int client) { SaveDisconnect(client); }

public void Event_player_death(Event event, const char[] name, bool dontBroadcast) {
    if (event.GetInt("customkill") != TF_CUSTOM_BACKSTAB
        || (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)) return;
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!IsRealPlayer(attacker) || attacker == victim || TF2_GetPlayerClass(attacker) != TFClass_Spy) return;
    // Preserve Kogasa's one-point backstab deduction on the scoreboard.
    if (g_iScoreAdjustment[attacker] > -2147483647) g_iScoreAdjustment[attacker]--;
    Publish(attacker);
}
public void Event_player_teleported(Event event, const char[] name, bool dontBroadcast) {
    int user = GetClientOfUserId(event.GetInt("userid"));
    int builder = GetClientOfUserId(event.GetInt("builderid"));
    if (user == builder || !IsRealPlayer(user) || !IsRealPlayer(builder)
        || TF2_GetPlayerClass(builder) != TFClass_Engineer || GetClientTeam(user) != GetClientTeam(builder)) return;
    // Only parity is needed; avoid a session-long integer counter overflow.
    g_iQualifyingTeleports[builder] ^= 1;
    if (!g_iQualifyingTeleports[builder]) {
        if (g_iScoreAdjustment[builder] > -2147483647) g_iScoreAdjustment[builder]--;
        Publish(builder);
    }
}
void SaveDisconnect(int client) {
    if (client < 1 || client > MaxClients) return;
    bool others;
    for (int other = 1; other <= MaxClients; other++)
        if (other != client && IsRealPlayer(other)) { others = true; break; }
    if (!others) { ResetOldScores(); return; }
    if (IsRealPlayer(client) && !IsFakeClient(client)) {
        char steamid[64];
        // Capture the displayed total before clearing this connection's offset.
        if (GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true))
            RememberScore(client, steamid);
    }
    ClearClient(client);
}
public Action Command_Status(int client, int args) {
    int resource = GetPlayerResourceEntity();
    ReplyToCommand(client, "[Restore Score] %s; network-only display; saved players=%d; resource=%d", PLUGIN_VERSION, g_OldScores.Size, resource);
    for (int target = 1; target <= MaxClients; target++) {
        if (!IsRealPlayer(target) || resource == -1) continue;
        ReplyToCommand(client, "[Restore Score] %N: raw=%d, restored=%d, adjustment=%d, serialized=%d", target,
            GetEntProp(resource, Prop_Send, "m_iTotalScore", _, target), g_iAddScore[target], g_iScoreAdjustment[target],
            RSDisplay_ReadSerialized(resource, target));
    }
    return Plugin_Handled;
}
#if defined RESTORESCORE_TEST
 #include "selftest.sp"
#endif
