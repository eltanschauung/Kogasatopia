#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <server_mail>
#define REQUIRE_PLUGIN

#define KOGASA_STEAMID_MAX 32

char g_CurrencyShortLabel[32] = "Gems";
char g_TestArgs[2][512];
char g_TestLastKey[128];
char g_TestReply[1024];
StringMap g_TestKeys;
bool g_TestMailAvailable = true;
int g_TestRejectTarget;
int g_TestSends;
int g_TestErrors;
int g_TestExpectedAmount = 100;

stock bool Test_IsHuman(int client)
{
    return client == 1 || client == 2;
}

stock bool Test_IsInGame(int client)
{
    return client > 0;
}

stock bool Test_GetSteamId(int client, char[] output, int maxlen, bool validated)
{
    FormatEx(output, maxlen, "7656119800000000%d", client);
    return validated;
}

stock int Test_GetCmdArg(int arg, char[] output, int maxlen)
{
    strcopy(output, maxlen, g_TestArgs[arg - 1]);
    return strlen(output);
}

stock FeatureStatus Test_GetFeatureStatus(FeatureType type, const char[] name)
{
    if (type != FeatureType_Native || !StrEqual(name, "ServerMail_SendCurrency"))
        SetFailState("Unexpected feature check");
    return g_TestMailAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}

stock void Test_Reply(int client, const char[] format, any ...)
{
    #pragma unused client
    VFormat(g_TestReply, sizeof(g_TestReply), format, 3);
}

stock void Test_Log(int client, int target, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused target
    #pragma unused format
}

stock void Test_Message(const char[] format, any ...)
{
    #pragma unused format
}

stock void Test_Error(const char[] format, any ...)
{
    #pragma unused format
    g_TestErrors++;
}

stock void Test_Register(const char[] name, ConCmd callback, int flags, const char[] help)
{
    #pragma unused callback
    if (!StrEqual(name, "sm_stimulus") || flags != ADMFLAG_GENERIC || !help[0])
        SetFailState("Invalid admin command registration");
}

// No real mail native is called by this probe.
stock bool Test_SendCurrency(int sender, int receiver, const char[] title,
    const char[] contents, int amount, const char[] key)
{
    if (sender != 0 || !Test_IsHuman(receiver) || amount != g_TestExpectedAmount
        || !title[0] || strlen(title) >= 128 || !contents[0])
        SetFailState("Invalid mail request");
    int existing;
    if (g_TestKeys.GetValue(key, existing))
        SetFailState("Duplicate mail request key");
    g_TestKeys.SetValue(key, 1);
    strcopy(g_TestLastKey, sizeof(g_TestLastKey), key);
    g_TestSends++;
    return receiver != g_TestRejectTarget;
}

#define MaxClients 4
#define Client_IsHumanInGame Test_IsHuman
#define Client_IsInGame Test_IsInGame
#define Kogasa_GetClientSteamId64 Test_GetSteamId
#define GetCmdArg Test_GetCmdArg
#define GetFeatureStatus Test_GetFeatureStatus
#define ReplyToCommand Test_Reply
#define LogAction Test_Log
#define LogMessage Test_Message
#define LogError Test_Error
#define ServerMail_SendCurrency Test_SendCurrency
#define RegAdminCmd Test_Register
#include "../../tf/addons/sourcemod/scripting/points_store/stimulus.sp"
#undef GetFeatureStatus
#undef ServerMail_SendCurrency

static void Expect(bool condition, const char[] label)
{
    if (!condition)
        SetFailState("Stimulus probe failed: %s", label);
}

public void OnPluginStart()
{
    Stimulus_OnPluginStart();
    g_TestKeys = new StringMap();

    char values[][] = {"", "0", "-1", "1.0", "1abc", "2147483648", "999999999999999",
        "1", "100", "0005", "2147483647"};
    int expected[] = {0, 0, 0, 0, 0, 0, 0, 1, 100, 5, 2147483647};
    strcopy(g_TestArgs[1], sizeof(g_TestArgs[]), "Probe");
    for (int i = 0; i < sizeof(expected); i++)
    {
        g_TestExpectedAmount = expected[i];
        strcopy(g_TestArgs[0], sizeof(g_TestArgs[]), values[i]);
        int previousSends = g_TestSends;
        Command_Stimulus(0, 2);
        Expect(g_TestSends - previousSends == (expected[i] > 0 ? 2 : 0), values[i]);
    }
    g_TestSends = 0;
    g_TestExpectedAmount = 100;

    strcopy(g_TestArgs[0], sizeof(g_TestArgs[]), "100");
    strcopy(g_TestArgs[1], sizeof(g_TestArgs[]), "The Onyx Stimulus");
    Command_Stimulus(0, 1);
    Expect(g_TestSends == 0, "missing title");
    Command_Stimulus(0, 3);
    Expect(g_TestSends == 0, "unquoted title rejected");

    strcopy(g_TestArgs[0], sizeof(g_TestArgs[]), "100abc");
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 0, "invalid amount rejected");
    strcopy(g_TestArgs[0], sizeof(g_TestArgs[]), "100");
    g_TestArgs[1][0] = '\0';
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 0, "empty title rejected");
    for (int i = 0; i < 128; i++)
        g_TestArgs[1][i] = 'x';
    g_TestArgs[1][128] = '\0';
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 0, "128-byte title rejected");

    strcopy(g_TestArgs[1], sizeof(g_TestArgs[]), "The Onyx Stimulus");
    g_TestMailAvailable = false;
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 0, "mail provider unavailable");
    g_TestMailAvailable = true;
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 2, "only connected humans receive checks");
    Expect(StrContains(g_TestReply, "for 2 connected players; 0 failed.") >= 0, "queued feedback");
    int sender;
    Expect(g_StimulusPendingSenders.GetValue(g_TestLastKey, sender), "pending insert tracked");
    ServerMail_OnMailSendResult(g_TestLastKey, true, 123, true);
    Expect(!g_StimulusPendingSenders.GetValue(g_TestLastKey, sender), "successful insert cleaned");

    Command_Stimulus(0, 2);
    Expect(g_TestSends == 4, "second invocation uses distinct request keys");
    ServerMail_OnMailSendResult(g_TestLastKey, false, 0, false);
    Expect(g_TestErrors == 1, "async failure logged");
    Expect(!g_StimulusPendingSenders.GetValue(g_TestLastKey, sender), "failed insert cleaned");
    ServerMail_OnMailSendResult("unrelated", false, 0, false);
    Expect(g_TestErrors == 1, "unrelated callbacks ignored");

    g_TestRejectTarget = 2;
    Command_Stimulus(0, 2);
    Expect(g_TestSends == 6, "queue rejection exercised");
    Expect(StrContains(g_TestReply, "for 1 connected players; 1 failed.") >= 0, "queue failure feedback");
    Expect(!g_StimulusPendingSenders.GetValue(g_TestLastKey, sender), "rejected insert cleaned");

    PrintToServer("[stimulus_probe] PASS: amount bounds, title validation, recipient filtering, request keys, queue and async failures; no real mail issued.");
    bool mailAvailable = GetFeatureStatus(FeatureType_Native, "ServerMail_SendCurrency") == FeatureStatus_Available;
    PrintToServer("[stimulus_probe] Live currency mail API available: %s", mailAvailable ? "yes" : "no");
    if (mailAvailable)
        Expect(!ServerMail_SendCurrency(0, 0, "Probe", "Invalid receiver probe", 1), "invalid server receiver rejected");
}

public void OnPluginEnd()
{
    Stimulus_OnPluginEnd();
    delete g_TestKeys;
}
