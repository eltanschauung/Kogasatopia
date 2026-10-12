#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

Database g_hImmunityDb;
int gStage;
int gChecks;
int gTicks;
bool gFake;
bool gInGame = true;
bool gAuthenticated = true;
int gMessages;
int gErrors;

public Plugin myinfo = {name = "Class immunity regression probe", author = "Hombre", version = "1.0"};

void Check(bool condition, const char[] label)
{
    gChecks++;
    if (!condition) SetFailState("Class immunity probe failed: %s", label);
}
void TestRegister(const char[] name, ConCmd callback, int flags, const char[] description)
{
    #pragma unused callback
    #pragma unused description
    Check(StrEqual(name, "sm_climmune") && flags == ADMFLAG_GENERIC, "admin command registration");
}
bool TestInGame(int client) { return client == 1 && gInGame; }
bool TestFake(int client) { return client == 1 && gFake; }
bool TestSteam(int client, char[] output, int maxlen, bool validate)
{
    #pragma unused validate
    strcopy(output, maxlen, "synthetic-test-client");
    return client == 1 && gAuthenticated;
}
int TestUserId(int client) { return client == 1 ? 1001 : 0; }
int TestClient(int userid) { return userid == 1001 && gInGame ? 1 : 0; }
int TestTarget(int client, const char[] name, bool bots, bool immunity)
{
    #pragma unused client
    #pragma unused name
    Check(bots && !immunity, "same targeting semantics as immune");
    return 1;
}
int TestArgs(char[] output, int maxlen)
{
    strcopy(output, maxlen, "synthetic");
    return 9;
}
void TestReply(int client, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused format
    gMessages++;
}
void TestBroadcast(int client, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused format
    gMessages++;
}
void TestAction(int actor, int target, const char[] format, any ...)
{
    #pragma unused actor
    #pragma unused target
    #pragma unused format
}
void TestError(const char[] format, any ...)
{
    #pragma unused format
    gErrors++;
}
bool Db_IsTransientError(const char[] error) { return StrContains(error, "transient") == 0; }
void WhaleBalance_RequestImmunityDatabaseReconnect() { SetFailState("Unexpected reconnect"); }

#define RegAdminCmd TestRegister
#define IsClientInGame TestInGame
#define IsFakeClient TestFake
#define Kogasa_GetClientSteamId64 TestSteam
#define GetClientUserId TestUserId
#define GetClientOfUserId TestClient
#define FindTarget TestTarget
#define GetCmdArgString TestArgs
#define ReplyToCommand TestReply
#define CPrintToChatAllEx TestBroadcast
#define LogAction TestAction
#define LogError TestError
#include "classlimits/persistent_immunity.sp"

public void OnPluginStart()
{
    // Dedicated local SQLite fixture, never the production connection/config.
    KeyValues config = new KeyValues("database");
    config.SetString("driver", "sqlite");
    config.SetString("database", "climmune_regression_fixture");
    char error[256];
    g_hImmunityDb = SQL_ConnectCustom(config, error, sizeof(error), false);
    delete config;
    if (g_hImmunityDb == null) SetFailState("Fixture connection failed");
    ClassLimits_InitializePersistentImmunity();
    ClassLimits_InvalidateImmunityDatabase();
    // Drop only the fixture table in this explicitly test-only DB.
    Check(SQL_FastQuery(g_hImmunityDb, "DROP TABLE IF EXISTS classlimits_immunity"), "fixture reset");
    ClassLimits_LoadPersistentImmunity(g_hImmunityDb);
    CreateTimer(0.1, Tick, _, TIMER_REPEAT);
}


bool Pending()
{
    int value;
    return g_ClassLimitImmunityPending.GetValue("synthetic-test-client", value);
}

public Action Tick(Handle timer)
{
    #pragma unused timer
    if (++gTicks > 100) SetFailState("Fixture timed out stage=%d errors=%d ready=%d", gStage, gErrors, g_bClassLimitImmunityReady);
    if (gStage == 0 && g_bClassLimitImmunityReady)
    {
        Check(!ClassLimits_IsPersistentlyImmune(1), "initially not immune");
        Command_ClassLimitImmune(0, 1);
        Check(Pending(), "toggle is serialized by SteamID");
        int messages = gMessages;
        Command_ClassLimitImmune(0, 1);
        Check(gMessages == messages + 1, "duplicate pending toggle rejected");
        gStage = 1;
    }
    else if (gStage == 1 && !Pending())
    {
        Check(ClassLimits_IsPersistentlyImmune(1), "successful grant updates cache");
        Check(!ClassLimits_IsPersistentlyImmune(0), "console not a player");
        gFake = true;
        Check(!ClassLimits_IsPersistentlyImmune(1), "bots excluded");
        gFake = false;
        gInGame = false;
        Check(!ClassLimits_IsPersistentlyImmune(1), "disconnected clients excluded");
        gInGame = true;
        gAuthenticated = false;
        Check(!ClassLimits_IsPersistentlyImmune(1), "unauthenticated clients excluded");
        gAuthenticated = true;
        ClassLimits_InvalidateImmunityDatabase();
        Check(ClassLimits_IsPersistentlyImmune(1), "outage retains known immunity");
        g_ClassLimitImmunity.Clear();
        ClassLimits_LoadPersistentImmunity(g_hImmunityDb);
        gStage = 2;
    }
    else if (gStage == 2 && g_bClassLimitImmunityReady)
    {
        Check(ClassLimits_IsPersistentlyImmune(1), "DB reload restores persistent grant");
        Command_ClassLimitImmune(0, 1);
        gStage = 3;
    }
    else if (gStage == 3 && !Pending())
    {
        Check(!ClassLimits_IsPersistentlyImmune(1), "second command removes immunity");
        ClassLimits_InvalidateImmunityDatabase();
        ClassLimits_LoadPersistentImmunity(g_hImmunityDb);
        gStage = 4;
    }
    else if (gStage == 4 && g_bClassLimitImmunityReady)
    {
        Check(!ClassLimits_IsPersistentlyImmune(1), "removal survives DB reload");
        SQL_ClassLimitImmunityLoaded(g_hImmunityDb, null, "stale error", g_iClassLimitImmunityGeneration - 1);
        Check(g_bClassLimitImmunityReady && gErrors == 0, "stale preload ignored");
        DataPack pack = new DataPack();
        pack.WriteCell(g_iClassLimitImmunityGeneration);
        pack.WriteCell(0);
        pack.WriteCell(1001);
        pack.WriteCell(false);
        pack.WriteString("synthetic-test-client");
        g_ClassLimitImmunityPending.SetValue("synthetic-test-client", 1);
        SQL_ClassLimitImmunityToggled(g_hImmunityDb, null, "synthetic failure", pack);
        Check(!Pending() && !ClassLimits_IsPersistentlyImmune(1), "failed writes do not grant and release lock");
        Check(gErrors == 1, "expected fixture failure logged once");
        PrintToServer("[ClassImmunityProbe] PASS checks=%d; grant/remove/preload/serialization/failure/stale callbacks", gChecks);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public void OnPluginEnd()
{
    ClassLimits_ClosePersistentImmunity();
    delete g_hImmunityDb;
}
