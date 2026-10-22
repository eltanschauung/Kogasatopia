#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define MaxClients 4
#define BP_CURRENCY_COLOR_MAX 32
#define BP_CURRENCY_LONG_MAX 64
#define BP_WELFARE_MIN 4
#define BP_WELFARE_MAX 10
#define BP_SOUND_COMMAND "xp_gain"
#define BP_ECONOMY_TABLE "test_economy"
#define BP_ECONOMY_WELFARE_POOL_KEY "welfare_pool"
#define CookieAccess_Private 2

int checks, failures, replies, publicReplies, xpSounds, welfareSounds, loads;
int credits, refunds, awarded, collected, population = 3, minimum = 3;
int session = 1001, chosenAmount = 7, affected = 1;
bool human = true, owned = true, cookiesCached = true, optedIn = true;
bool welfareEnabled = true, balanceReady = true;
char savedCookie[8], lastReply[512], lastQuery[512];
DataPack queuedSql;
float delay;
any timerSerial;

methodmap TestCookie < Handle
{
    public TestCookie(const char[] name, const char[] description, int access)
    {
        #pragma unused name
        #pragma unused description
        #pragma unused access
        return view_as<TestCookie>(1);
    }
    public void Set(int client, const char[] value)
    {
        #pragma unused client
        strcopy(savedCookie, sizeof(savedCookie), value);
    }
    public void Get(int client, char[] value, int maxlen)
    {
        #pragma unused client
        strcopy(value, maxlen, savedCookie);
    }
}
methodmap TestDatabase < Handle
{
    public void Query(Function callback, const char[] query, any data)
    {
        #pragma unused callback
        strcopy(lastQuery, sizeof(lastQuery), query);
        queuedSql = view_as<DataPack>(data);
    }
}
methodmap TestResults < Handle
{
    property int AffectedRows
    {
        public get() { return affected; }
    }
}
TestDatabase g_Database;
bool g_DatabaseReady = true, g_PerMapAwardsReady = true, g_EconomyStateLoaded = true;
bool g_ClientPurchasesLoaded[MAXPLAYERS + 1];
StringMap g_StorePendingPurchaseReceipts[MAXPLAYERS + 1];
int g_WelfarePoolBalance = 100, g_CumulativeSpentBalance;
int g_PerMapStateGeneration = 1;
DataPack g_WelfareCollectionRequest[MAXPLAYERS + 1];

stock bool Client_IsHumanInGame(int client) { return client == 1 && human; }
stock bool IsClientAuthorizedHuman(int client) { return Client_IsHumanInGame(client); }
stock bool TestCookiesCached(int client) { return client == 1 && cookiesCached; }
stock int GetCachedPurchasePrice(int client, const char[] key)
{
    return client == 1 && owned && StrEqual(key, "automatic_welfare_robot") ? 2500 : 0;
}
stock void CPrintToChat(int client, const char[] format, any ...)
{
    if (client != 1) failures++;
    replies++;
    VFormat(lastReply, sizeof(lastReply), format, 3);
}
stock void GetCurrencyColorTag(char[] value, int maxlen) { strcopy(value, maxlen, "{cyan}"); }
stock void GetCurrencyPrefix(char[] value, int maxlen) { strcopy(value, maxlen, "{cyan}[Gems]{default}"); }
stock void GetCurrencyLongLabel(char[] value, int maxlen) { strcopy(value, maxlen, "Gems"); }
stock bool IsWelfareEnabled() { return welfareEnabled; }
stock int GetWelfareMinPlayers() { return minimum; }
stock int GetWelfareHumanPlayerCount() { return population; }
stock bool AreBonusPointsReady(int client) { return client == 1 && balanceReady; }
stock int GetPerMapAwardCount(int client, const char[] type)
{
    #pragma unused client
    #pragma unused type
    return collected;
}
stock void LoadClientBonusPoints(int client)
{
    #pragma unused client
    loads++;
}
stock void LoadEconomyState() { loads++; }
stock int TestSerial(int client) { return client == 1 ? session : -1; }
stock int TestFromSerial(int serial) { return human && serial == session ? 1 : 0; }
stock int TestRandomInt(int low, int high)
{
    if (low != 4 || high != 10) failures++;
    return chosenAmount;
}
stock Handle TestTimer(float interval, Timer callback, any serial, int flags)
{
    #pragma unused callback
    if (flags != TIMER_FLAG_NO_MAPCHANGE) failures++;
    delay = interval;
    timerSerial = serial;
    return CreateDataPack();
}
stock void TestHook(const char[] name, EventHook callback, EventHookMode mode)
{
    #pragma unused callback
    if (!StrEqual(name, "teamplay_round_start") || mode != EventHookMode_PostNoCopy) failures++;
}
stock bool SaySounds_TryPlayCommand(int client, const char[] command, bool force)
{
    if (client != 1 || !StrEqual(command, "xp_gain") || force) failures++;
    if (optedIn) xpSounds++;
    return optedIn;
}
stock void QueueEconomyDelta(const char[] key, int amount)
{
    if (!StrEqual(key, "welfare_pool")) failures++;
    refunds += amount;
}
stock void LogEconomyEvent(const char[] eventName, int client, int amount,
    const char[] type, int target, int pool, int spent)
{
    #pragma unused eventName
    #pragma unused client
    #pragma unused amount
    #pragma unused type
    #pragma unused target
    #pragma unused pool
    #pragma unused spent
}
stock void TestLogError(const char[] format, any ...)
{
    #pragma unused format
}
stock bool ApplyBonusPoints(int client, int amount, bool sound, bool chat, float chance,
    const char[] type, int target, float wait, int perMap)
{
    if (client != 1 || sound || chat || chance != 1.0 || !StrEqual(type, "welfare")
        || target != 0 || wait != 0.0 || perMap != 1) failures++;
    if (collected >= 1 || !g_PerMapAwardsReady) return false;
    collected++;
    credits++;
    awarded += amount;
    return true;
}
stock void PlayWelfareSound(int amount)
{
    #pragma unused amount
    welfareSounds++;
}
stock void BuildPurchaseDisplayName(int client, char[] value, int maxlen)
{
    #pragma unused client
    strcopy(value, maxlen, "Test");
}
stock void Oblivion_ChatAllEx(int client, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused format
    publicReplies++;
}

#define Cookie TestCookie
#define Database TestDatabase
#define DBResultSet TestResults
#define AreClientCookiesCached TestCookiesCached
#define GetClientSerial TestSerial
#define GetClientFromSerial TestFromSerial
#define GetRandomInt TestRandomInt
#define CreateTimer TestTimer
#define HookEvent TestHook
#define LogError TestLogError
#include "welfare_under_test.inc"
#include "welfare_robot.sp"

void Check(bool result, const char[] label)
{
    checks++;
    if (!result) { failures++; PrintToServer("[WelfareRobotProbe] Failed: %s", label); }
}
void CompleteSql(const char[] error = "")
{
    DataPack pack = queuedSql;
    queuedSql = null;
    SQL_OnWelfarePoolDebited(g_Database, view_as<TestResults>(1), error, pack);
}
void Fresh()
{
    WelfareRobot_ResetClient(1);
    if (queuedSql != null) { delete queuedSql; }
    human = owned = cookiesCached = optedIn = welfareEnabled = balanceReady = true;
    g_ClientPurchasesLoaded[1] = g_DatabaseReady = g_PerMapAwardsReady = g_EconomyStateLoaded = true;
    g_Database = view_as<TestDatabase>(1);
    collected = 0;
    population = 3;
    minimum = 3;
    g_WelfarePoolBalance = 100;
    affected = 1;
    savedCookie[0] = '\0';
    WelfareRobot_LoadPreference(1);
}

public void OnPluginStart()
{
    Fresh();
    WelfareRobot_OnPluginStart();
    Check(WelfareRobot_CanCollect(1), "owned robot defaults enabled");
    Check(!WelfareRobot_CanCollect(2), "no fake or disconnected targets");
    owned = false;
    Check(!WelfareRobot_TryToggle(1), "non-owner cannot toggle");
    WelfareRobot_OnPurchased(1, "automatic_welfare_robot");
    Check(g_WelfareRobotPurchaseTimer[1] == null, "no timer without ownership");
    owned = true;
    g_StorePendingPurchaseReceipts[1] = new StringMap();
    g_StorePendingPurchaseReceipts[1].SetValue("automatic_welfare_robot", 1);
    Check(!WelfareRobot_CanCollect(1), "unconfirmed receipt cannot operate");
    delete g_StorePendingPurchaseReceipts[1];
    cookiesCached = false;
    g_WelfareRobotPreferenceLoaded[1] = false;
    WelfareRobot_OnPurchased(1, "automatic_welfare_robot");
    Check(g_WelfareRobotEnabled[1] && g_WelfareRobotPreferenceDirty[1], "purchase before cookies enables");
    Check(delay == 3.0 && g_WelfareRobotPurchaseTimer[1] != null, "purchase schedules three seconds");
    strcopy(savedCookie, sizeof(savedCookie), "0");
    cookiesCached = true;
    WelfareRobot_LoadPreference(1);
    Check(StrEqual(savedCookie, "1") && g_WelfareRobotEnabled[1], "late cookie cannot overwrite purchase");
    Handle purchaseTimer = g_WelfareRobotPurchaseTimer[1];
    Timer_WelfareRobotPurchase(purchaseTimer, timerSerial);
    delete purchaseTimer;
    Check(queuedSql != null, "purchase timer starts collection");
    DataPack firstRequest = queuedSql;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(queuedSql == firstRequest && g_WelfareCollectionRequest[1] == firstRequest, "round and purchase share in-flight guard");
    CompleteSql();
    Check(credits == 1 && awarded == 7 && collected == 1 && g_WelfarePoolBalance == 93, "single pool debit and credit");
    Check(StrEqual(lastReply, "{cyan}[Gems]{default} Your {gold}Welfare Robot{default} collected {cyan}7 Gems{default} for you!"), "exact private collection text");
    Check(xpSounds == 1 && welfareSounds == 0 && publicReplies == 0, "private opted-in xp only");
    int before = replies;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(queuedSql == null && replies == before, "claimed map silently skipped");
    Command_Welfare(1, 0);
    Check(!g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "0"), "unavailable welfare toggles off");
    Check(StrContains(lastReply, "Automatic welfare collection disabled.") != -1, "disabled message");
    Command_Welfare(1, 0);
    Check(g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "1"), "unavailable welfare toggles on");
    Check(StrContains(lastReply, "You enabled your {gold}Welfare Robot!") != -1, "enabled message");
    Fresh();
    WelfareRobot_SetEnabled(1, false);
    before = replies;
    Command_Welfare(1, 0);
    Check(queuedSql != null && !g_WelfareRobotEnabled[1] && replies == before, "available welfare collects manually instead of toggling");
    CompleteSql();
    Check(publicReplies == 1 && welfareSounds == 1, "manual welfare unchanged");
    Fresh();
    optedIn = false;
    WelfareRobot_AttemptCollection(1);
    CompleteSql();
    Check(xpSounds == 1, "opted-out client hears no xp");
    Fresh();
    population = 2;
    before = replies;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null && replies == before, "minimum population respected silently");
    population = 3;
    g_WelfarePoolBalance = 0;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null && replies == before, "empty pool respected silently");
    g_WelfarePoolBalance = 1;
    WelfareRobot_AttemptCollection(1);
    CompleteSql();
    Check(g_WelfarePoolBalance == 0 && awarded == 22, "low funded pool clamps payout");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    int refunded = refunds;
    WelfareRobot_SetEnabled(1, false);
    CompleteSql();
    Check(refunds == refunded + 7 && collected == 0, "disabled in-flight robot refunds pool");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    refunded = refunds;
    human = false;
    WelfareRobot_ResetClient(1);
    session++;
    human = true;
    CompleteSql();
    Check(refunds == refunded + 7 && collected == 0, "disconnect or reused slot cannot receive payout");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    refunded = refunds;
    g_PerMapStateGeneration++;
    CompleteSql();
    Check(refunds == refunded + 7 && collected == 0, "old map generation refunds");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    refunded = refunds;
    WelfareRobot_OnMapEnd();
    CompleteSql();
    Check(refunds == refunded + 7 && collected == 0, "map end invalidates in-flight request");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    before = replies;
    CompleteSql("simulated SQL error");
    Check(queuedSql == null && g_WelfareCollectionRequest[1] == null && replies == before && collected == 0, "SQL error clears busy state silently");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    affected = 0;
    CompleteSql();
    Check(collected == 0 && g_WelfarePoolBalance == 100, "competing pool withdrawal cannot overpay");
    Fresh();
    g_PerMapAwardsReady = false;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null, "per-map state must be loaded");
    Fresh();
    WelfareRobot_SetEnabled(1, false);
    WelfareRobot_ResetClient(1);
    WelfareRobot_LoadPreference(1);
    Check(!g_WelfareRobotEnabled[1], "disabled preference survives reconnect");
    WelfareRobot_OnPurchased(1, "automatic_welfare_robot");
    before = replies;
    Check(Timer_WelfareRobotPurchase(null, session) == Plugin_Stop
        && g_WelfareRobotPurchaseTimer[1] != null && replies == before, "stale timer rejected");
    WelfareRobot_OnMapEnd();
    Check(g_WelfareRobotPurchaseTimer[1] == null, "map end cancels purchase timer");
    Fresh();
    welfareEnabled = false;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null, "disabled welfare blocks robot");
    welfareEnabled = true;
    balanceReady = false;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null, "balance must be ready");
    balanceReady = true;
    g_EconomyStateLoaded = false;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null, "pool must be loaded");
    g_EconomyStateLoaded = true;
    g_DatabaseReady = false;
    WelfareRobot_AttemptCollection(1);
    Check(queuedSql == null, "database must be ready");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    DataPack oldRequest = queuedSql;
    queuedSql = null;
    WelfareRobot_OnMapEnd();
    g_PerMapStateGeneration++;
    WelfareRobot_AttemptCollection(1);
    DataPack newRequest = queuedSql;
    refunded = refunds;
    SQL_OnWelfarePoolDebited(g_Database, view_as<TestResults>(1), "", oldRequest);
    Check(g_WelfareCollectionRequest[1] == newRequest && refunds == refunded + 7,
        "stale callback cannot clear newer request");
    CompleteSql();
    Check(collected == 1 && g_WelfareCollectionRequest[1] == null, "new request survives stale callback");
    Fresh();
    WelfareRobot_AttemptCollection(1);
    refunded = refunds;
    collected = 1;
    CompleteSql();
    Check(refunds == refunded + 7 && collected == 1, "another award before callback cannot double pay");
    WelfareRobot_ResetClient(1);
    PrintToServer("[WelfareRobotProbe] %d checks, %d failures", checks, failures);
}
