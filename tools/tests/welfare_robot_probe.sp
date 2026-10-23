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
#define BP_WELFARE_VOLUNTEER_RESET_STEAMID "test-reset-marker"
#define BP_WELFARE_VOLUNTEER_RESET_REWARD "test-reset-reward"

int checks, failures, replies, publicReplies, xpSounds, welfareSounds, loads;
int credits, refunds, awarded, collected, population = 3, minimum = 3;
int session = 1001, chosenAmount = 7, affected = 1;
int testTeam = 2, hookedEvents;
int registeredCommands, registeredCommandMask;
bool human = true, owned = true, cookiesCached = true, optedIn = true;
bool welfareEnabled = true, balanceReady = true;
bool g_WelfareVolunteerResetUsed;
bool volunteerEligible = true, volunteerNativeAvailable = true, resetAllowed = true;
bool checkingVolunteerReset, disconnectOnResetAnnouncement;
int volunteerResetMarker, resetAnnouncements, messageOrder;
int resetAnnouncementOrder, resetQueryOrder, resetCollectionOrder;
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
        if (checkingVolunteerReset)
        {
            if (!resetAnnouncementOrder) failures++;
            resetQueryOrder = ++messageOrder;
        }
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
    if (checkingVolunteerReset && StrContains(lastReply, "Your {gold}Welfare Robot{default} collected") != -1)
    {
        if (!resetAnnouncementOrder) failures++;
        resetCollectionOrder = ++messageOrder;
    }
}
stock void CPrintToChatAll(const char[] format, any ...)
{
    char output[512];VFormat(output,sizeof(output),format,2);
    if (StrContains(output,"bros can collect welfare again!") == -1) failures++;
    resetAnnouncements++;
    resetAnnouncementOrder = ++messageOrder;
    if (disconnectOnResetAnnouncement)
    {
        WelfareRobot_ResetClient(1);
        session++;
        human = false;
    }
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
stock FeatureStatus TestFeatureStatus(FeatureType type, const char[] name)
{
    if (type != FeatureType_Native || !StrEqual(name,"TeamBalance_IsVolunteerEligible")) failures++;
    return volunteerNativeAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}
stock bool TeamBalance_IsVolunteerEligible(int client) { return client == 1 && volunteerEligible; }
stock int GetPerMapAwardCountForSteamId(const char[] identity, const char[] type)
{
    #pragma unused identity
    #pragma unused type
    return volunteerResetMarker;
}
stock bool IncrementPerMapAwardCountForSteamId(const char[] identity, const char[] type)
{
    #pragma unused identity
    #pragma unused type
    volunteerResetMarker++;
    return true;
}
stock bool ResetPerMapAwardCount(int client, const char[] type)
{
    if (client != 1 || !StrEqual(type,"welfare")) failures++;
    if (!resetAllowed || collected < 1) return false;
    collected = 0;
    return true;
}
stock void LoadClientBonusPoints(int client)
{
    #pragma unused client
    loads++;
}
stock void LoadClientPurchases(int client)
{
    if (client != 1) failures++;
    loads++;
}
stock void LoadEconomyState() { loads++; }
stock int TestSerial(int client) { return client == 1 ? session : -1; }
stock int TestFromSerial(int serial) { return human && serial == session ? 1 : 0; }
stock int TestFromUserId(int userId) { return human && userId == session ? 1 : 0; }
stock int TestClientTeam(int client)
{
    if (client != 1 || !human) failures++;
    return testTeam;
}
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
    hookedEvents++;
    if (StrEqual(name, "player_team"))
    {
        if (mode != EventHookMode_Post) failures++;
    }
    else if ((!StrEqual(name, "teamplay_round_start") && !StrEqual(name, "teamplay_round_win"))
        || mode != EventHookMode_PostNoCopy) failures++;
}
stock void TestRegisterCommand(const char[] name, ConCmd callback, const char[] description)
{
    #pragma unused callback
    #pragma unused description
    registeredCommands++;
    if (StrEqual(name, "sm_welfarebot")) registeredCommandMask |= 1;
    else if (StrEqual(name, "sm_welfarerobot")) registeredCommandMask |= 2;
    else if (StrEqual(name, "sm_bot")) registeredCommandMask |= 4;
    else failures++;
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
#define GetClientOfUserId TestFromUserId
#define GetClientTeam TestClientTeam
#define GetRandomInt TestRandomInt
#define CreateTimer TestTimer
#define HookEvent TestHook
#define RegConsoleCmd TestRegisterCommand
#define GetFeatureStatus TestFeatureStatus
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
    testTeam = 2;
    g_WelfarePoolBalance = 100;
    affected = 1;
    g_WelfareVolunteerResetUsed = false;
    volunteerEligible = volunteerNativeAvailable = resetAllowed = true;
    checkingVolunteerReset = disconnectOnResetAnnouncement = false;
    volunteerResetMarker = resetAnnouncements = messageOrder = 0;
    resetAnnouncementOrder = resetQueryOrder = resetCollectionOrder = 0;
    savedCookie[0] = '\0';
    WelfareRobot_LoadPreference(1);
}

void ChangeTeam(int team, bool disconnect = false, int userId = -1)
{
    Event event = CreateEvent("player_team", true);
    event.SetInt("userid", userId < 0 ? session : userId);
    event.SetInt("team", team);
    event.SetBool("disconnect", disconnect);
    testTeam = team;
    Event_WelfareRobotTeamChanged(event, "player_team", false);
    delete event;
}

public void OnPluginStart()
{
    Fresh();
    g_ClientPurchasesLoaded[1] = false;
    WelfareRobot_OnPluginStart();
    g_ClientPurchasesLoaded[1] = true;
    Check(hookedEvents == 3, "round start, round end and team changes hooked without polling");
    Check(registeredCommands == 3 && registeredCommandMask == 7, "all three explicit robot command aliases registered");
    Check(WelfareRobot_CanCollect(1), "owned robot defaults enabled");
    Check(!WelfareRobot_CanCollect(2), "no fake or disconnected targets");
    owned = false;
    Command_WelfareRobot(1, 0);
    Check(StrContains(lastReply, "You do not own") != -1 && g_WelfareRobotEnabled[1], "non-owner cannot toggle");
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
    Check(g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "1"), "unavailable welfare does not toggle robot");
    Check(StrContains(lastReply, "already collected") != -1, "unavailable welfare prints normal reason");
    Command_WelfareRobot(1, 0);
    Check(!g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "0"), "robot command explicitly toggles off");
    Check(StrEqual(lastReply, "{cyan}[Gems]{default} Automatic welfare collection disabled. Use {gold}!welfarebot{default} to toggle your robot."), "disabled message points to new command and resets currency color");
    Command_Welfare(1, 0);
    Check(!g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "0"), "unavailable welfare does not enable disabled robot");
    Command_WelfareRobot(1, 0);
    Check(g_WelfareRobotEnabled[1] && StrEqual(savedCookie, "1"), "robot command explicitly toggles on");
    Check(StrEqual(lastReply, "{cyan}[Gems]{default} You enabled your {gold}Welfare Robot!{default} Welfare will be collected automatically when rounds start."), "enabled message resets currency color");
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

    Fresh();
    testTeam = 1;
    before = replies;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(g_WelfareRobotCollectionPending[1] && queuedSql == null && replies == before,
        "spectator defers automatic round-start collection silently");
    Event_WelfareRobotRoundStart(null, "", false);
    ChangeTeam(0);
    ChangeTeam(1);
    ChangeTeam(2, true);
    ChangeTeam(2, false, session + 1);
    Check(g_WelfareRobotCollectionPending[1] && queuedSql == null,
        "unassigned, spectator, disconnect and stale user events cannot collect");
    ChangeTeam(2);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql != null,
        "joining RED consumes deferred attempt and starts collection");
    DataPack teamRequest = queuedSql;
    ChangeTeam(3);
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(queuedSql == teamRequest, "subsequent team change and round end do not duplicate request");
    CompleteSql();
    Check(collected == 1, "deferred RED collection awards once");

    Fresh();
    testTeam = 0;
    Event_WelfareRobotRoundStart(null, "", false);
    ChangeTeam(3);
    Check(queuedSql != null && !g_WelfareRobotCollectionPending[1], "joining BLU also releases deferred collection");
    CompleteSql();

    Fresh();
    testTeam = 1;
    Event_WelfareRobotRoundStart(null, "", false);
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(queuedSql != null && !g_WelfareRobotCollectionPending[1] && testTeam == 1,
        "round end collects for connected owner who stayed spectator");
    teamRequest = queuedSql;
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(queuedSql == teamRequest, "repeated round end cannot rearm fallback");
    CompleteSql();
    ChangeTeam(2);
    Check(queuedSql == null && collected == 1, "joining after fallback cannot collect twice");

    Fresh();
    testTeam = 1;
    Event_WelfareRobotRoundStart(null, "", false);
    WelfareRobot_SetEnabled(1, false);
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "disabling cancels deferred attempt");
    Fresh();
    testTeam = 1;
    Event_WelfareRobotRoundStart(null, "", false);
    WelfareRobot_OnMapEnd();
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "map end discards deferred attempt");
    Event_WelfareRobotRoundStart(null, "", false);
    WelfareRobot_ResetClient(1);
    ChangeTeam(2);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "disconnect reset cannot pass deferred attempt to reused slot");

    Fresh();
    testTeam = 1;
    WelfareRobot_OnPurchased(1, "automatic_welfare_robot");
    purchaseTimer = g_WelfareRobotPurchaseTimer[1];
    Timer_WelfareRobotPurchase(purchaseTimer, timerSerial);
    delete purchaseTimer;
    Check(g_WelfareRobotCollectionPending[1] && queuedSql == null,
        "purchase still waits three seconds then defers spectator collection");
    ChangeTeam(3);
    Check(queuedSql != null, "purchase deferred attempt releases on team join");
    CompleteSql();

    Fresh();
    testTeam = 1;
    Event_WelfareRobotRoundStart(null, "", false);
    Command_Welfare(1, 0);
    Check(queuedSql != null, "manual welfare remains available in spectator");
    CompleteSql();
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(queuedSql == null && collected == 1, "manual payout prevents deferred fallback payout");

    Fresh();
    testTeam = 1;
    Event_WelfareRobotRoundStart(null, "", false);
    population = 2;
    before = replies;
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(queuedSql == null && replies == before && g_WelfareRobotCollectionPending[1],
        "spectator fallback respects population requirement and retains pending attempt");
    Fresh();
    testTeam = 1;
    g_ClientPurchasesLoaded[1] = false;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(g_WelfareRobotCollectionPending[1], "map-change ownership load must not discard deferred collection");
    g_ClientPurchasesLoaded[1] = true;
    ChangeTeam(2);
    Check(queuedSql != null, "team join after ownership load must still collect");
    if (queuedSql != null) CompleteSql();
    Fresh();
    g_PerMapAwardsReady = false;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(g_WelfareRobotCollectionPending[1], "map-change per-map load must not discard collection");
    g_PerMapAwardsReady = true;
    WelfareRobot_ResumePendingCollections();
    Check(queuedSql != null, "per-map ready callback resumes collection without another round start");
    CompleteSql();

    Fresh();
    WelfareRobot_OnMapEnd();
    human = false;
    WelfareRobot_OnMapStart();
    Event_WelfareRobotRoundStart(null, "", false);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "map can start before client finishes loading");
    human = true;
    testTeam = 1;
    g_ClientPurchasesLoaded[1] = false;
    g_WelfareRobotPreferenceLoaded[1] = false;
    WelfareRobot_OnClientPutInServer(1);
    Check(g_WelfareRobotCollectionPending[1], "late loading client arms collection after initial round start");
    ChangeTeam(2);
    Check(g_WelfareRobotCollectionPending[1] && queuedSql == null, "early team join retains pending ownership load");
    g_ClientPurchasesLoaded[1] = true;
    WelfareRobot_ResumeCollection(1);
    Check(queuedSql != null, "ownership completion resumes late client on RED");
    CompleteSql();

    // Cookie, receipt, balance, per-map state and pool SQL complete in any order.
    for (int order = 0; order < 5; order++)
    {
        Fresh();
        g_ClientPurchasesLoaded[1] = g_WelfareRobotPreferenceLoaded[1] = false;
        balanceReady = g_PerMapAwardsReady = g_EconomyStateLoaded = false;
        Event_WelfareRobotRoundStart(null, "", false);
        for (int step = 0; step < 5; step++)
        {
            switch ((order + step) % 5)
            {
                case 0: g_ClientPurchasesLoaded[1] = true;
                case 1: WelfareRobot_LoadPreference(1);
                case 2: balanceReady = true;
                case 3: g_PerMapAwardsReady = true;
                case 4: g_EconomyStateLoaded = true;
            }
            WelfareRobot_ResumePendingCollections();
            Check(step == 4 ? queuedSql != null : queuedSql == null,
                "readiness order only starts SQL after all dependencies are ready");
        }
        DataPack readyRequest = queuedSql;
        WelfareRobot_ResumePendingCollections();
        Check(queuedSql == readyRequest && !g_WelfareRobotCollectionPending[1], "repeated readiness signals cannot start a second collection");
        CompleteSql();
    }

    Fresh();
    testTeam = 1;
    g_ClientPurchasesLoaded[1] = false;
    Event_WelfareRobotRoundStart(null, "", false);
    Event_WelfareRobotRoundEnd(null, "", false);
    Check(g_WelfareRobotCollectionPending[1] && g_WelfareRobotAllowSpectator[1] && queuedSql == null,
        "round-end fallback remains authorized while ownership loads");
    g_ClientPurchasesLoaded[1] = true;
    WelfareRobot_ResumeCollection(1);
    Check(queuedSql != null && !g_WelfareRobotAllowSpectator[1], "late ownership callback collects spectator fallback exactly once");
    CompleteSql();

    Fresh();
    testTeam = 1;
    g_ClientPurchasesLoaded[1] = false;
    Event_WelfareRobotRoundStart(null, "", false);
    Event_WelfareRobotRoundEnd(null, "", false);
    Event_WelfareRobotRoundStart(null, "", false);
    g_ClientPurchasesLoaded[1] = true;
    WelfareRobot_ResumeCollection(1);
    Check(g_WelfareRobotCollectionPending[1] && !g_WelfareRobotAllowSpectator[1] && queuedSql == null,
        "new round removes previous round-end spectator permission");
    ChangeTeam(3);
    Check(queuedSql != null, "new round still collects once client joins BLU");
    CompleteSql();

    Fresh();
    WelfareRobot_OnMapEnd();
    WelfareRobot_OnMapStart();
    g_PerMapAwardsReady = false;
    WelfareRobot_ResumePendingCollections();
    Check(g_WelfareRobotCollectionPending[1] && queuedSql == null, "map transition defers until award reset completes");
    g_PerMapAwardsReady = true;
    WelfareRobot_ResumePendingCollections();
    Check(queuedSql != null, "map-transition reset callback wakes retained in-game client");
    CompleteSql();

    Fresh();
    owned = false;
    Event_WelfareRobotRoundStart(null, "", false);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "known non-owner does not retain collection work");
    Fresh();
    WelfareRobot_SetEnabled(1, false);
    Event_WelfareRobotRoundStart(null, "", false);
    Check(!g_WelfareRobotCollectionPending[1] && queuedSql == null, "known disabled robot does not retain collection work");
    Fresh();
    Command_WelfareRobot(1, 0);
    Check(!g_WelfareRobotEnabled[1] && queuedSql == null && collected == 0,
        "toggle command toggles instead of collecting even when welfare is available");
    Command_WelfareRobot(1, 0);
    Check(g_WelfareRobotEnabled[1] && queuedSql == null && collected == 0,
        "explicit enable does not perform an immediate manual collection");
    Fresh();
    g_ClientPurchasesLoaded[1] = false;
    Command_WelfareRobot(1, 0);
    Check(g_WelfareRobotEnabled[1] && StrContains(lastReply, "ownership is still loading") != -1,
        "unloaded ownership cannot toggle");
    Fresh();
    cookiesCached = false;
    g_WelfareRobotPreferenceLoaded[1] = false;
    Command_WelfareRobot(1, 0);
    Check(g_WelfareRobotEnabled[1] && StrContains(lastReply, "preference is still loading") != -1,
        "unloaded cookies cannot toggle");
    Fresh();
    g_WelfareRobotCollectionPending[1] = true;
    g_WelfareRobotPreferenceLoaded[1] = false;
    strcopy(savedCookie, sizeof(savedCookie), "1");
    Command_WelfareRobot(1, 0);
    Check(!g_WelfareRobotEnabled[1] && queuedSql == null && !g_WelfareRobotCollectionPending[1],
        "loading cookies to disable never starts pending collection first");
    Fresh();
    before = replies;
    Command_WelfareRobot(0, 0);
    Command_WelfareRobot(2, 0);
    Check(replies == before && g_WelfareRobotEnabled[1], "console and invalid clients cannot toggle");
    Fresh();
    population = 2;
    Command_Welfare(1, 0);
    Check(g_WelfareRobotEnabled[1] && StrContains(lastReply, "Minimum playercount") != -1,
        "low-population welfare prints restriction without toggling");
    Fresh();
    collected = 1;
    checkingVolunteerReset = true;
    Event_WelfareRobotRoundStart(null,"",false);
    Check(queuedSql == null && !g_WelfareRobotCollectionPending[1],
        "second round alone does not bypass once-per-map allowance");
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && volunteerResetMarker == 1 && g_WelfareVolunteerResetUsed,
        "delayed volunteer reset records and announces reset once");
    Check(queuedSql != null && resetQueryOrder > resetAnnouncementOrder,
        "delayed reset rearms consumed second-round attempt only after announcement");
    firstRequest = queuedSql;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && queuedSql == firstRequest,
        "duplicate reset timer cannot announce or collect twice");
    CompleteSql();
    Check(collected == 1 && resetCollectionOrder > resetQueryOrder
        && resetQueryOrder > resetAnnouncementOrder,
        "robot payout output strictly follows announcement and query submission");

    Fresh();
    testTeam = 1;
    collected = 1;
    checkingVolunteerReset = true;
    Timer_WelfareRoundWin(null);
    Check(queuedSql != null && resetAnnouncements == 1,
        "round-end reset also releases eligible spectator robot fallback");
    CompleteSql();

    Fresh();
    collected = 1;
    WelfareRobot_SetEnabled(1,false);
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && queuedSql == null && collected == 0,
        "disabled robot does not collect restored volunteer allowance");

    Fresh();
    collected = 1;
    volunteerEligible = false;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 0 && queuedSql == null && collected == 1,
        "non-volunteer receives no reset or robot rearm");
    Fresh();
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 0 && queuedSql == null,
        "no previously collected allowance means no reset announcement or robot attempt");
    Fresh();
    collected = 1;
    resetAllowed = false;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 0 && queuedSql == null && collected == 1,
        "failed allowance reset cannot announce or arm robot");
    Fresh();
    collected = 1;
    volunteerNativeAvailable = false;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 0 && queuedSql == null,
        "missing volunteer API cannot grant reset");
    Fresh();
    collected = 1;
    volunteerResetMarker = 1;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 0 && queuedSql == null && collected == 1,
        "persisted reset marker prevents another allowance after reload");

    Fresh();
    collected = 1;
    checkingVolunteerReset = true;
    disconnectOnResetAnnouncement = true;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && queuedSql == null,
        "disconnect or changed serial during announcement cannot receive robot handoff");

    Fresh();
    collected = 1;
    checkingVolunteerReset = true;
    population = 2;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && queuedSql == null && g_WelfareRobotCollectionPending[1],
        "reset still respects population and retains a pending collection");
    population = 3;
    WelfareRobot_ResumePendingCollections();
    Check(queuedSql != null && resetQueryOrder > resetAnnouncementOrder,
        "pending reset collection resumes when population requirement is met");
    CompleteSql();

    Fresh();
    collected = 1;
    checkingVolunteerReset = true;
    g_WelfareRobotPreferenceLoaded[1] = false;
    cookiesCached = false;
    Timer_WelfareRoundWin(null);
    Check(resetAnnouncements == 1 && queuedSql == null && g_WelfareRobotCollectionPending[1],
        "reset rearm survives delayed cookies");
    cookiesCached = true;
    WelfareRobot_LoadPreference(1);
    Check(queuedSql != null && resetQueryOrder > resetAnnouncementOrder,
        "late cookie callback collects after reset announcement");
    CompleteSql();
    WelfareRobot_ResetClient(1);
    PrintToServer("[WelfareRobotProbe] %d checks, %d failures", checks, failures);
}
