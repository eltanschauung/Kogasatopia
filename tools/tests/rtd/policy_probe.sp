#pragma semicolon 1
#pragma newdecls required

// Compile the real vote loader, but never start its commands/database/hooks.
#define myinfo VoteCoreInfo
#define AskPluginLoad2 VoteCoreAskPluginLoad2
#define OnPluginStart VoteCoreOnPluginStart
#define OnMapStart VoteCoreOnMapStart
#define OnPluginEnd VoteCoreOnPluginEnd
#define VOTEMENU_POLICY_TEST
#include "votemenu.sp"
#undef myinfo
#undef AskPluginLoad2
#undef OnPluginStart
#undef OnMapStart
#undef OnPluginEnd
#include "filters/chat_client_state.sp"

public Plugin myinfo =
{
    name = "Filters/Votemenu policy regression probe",
    author = "Hombre",
    version = "1.0"
};

int g_Checks;
int g_Failures;
void Check(bool result)
{
    g_Checks++;
    if (!result) g_Failures++;
}

void TestClient(int client)
{
    char output[64] = "sentinel";
    Check(!Filters_IsInGameChatClient(client));
    BuildDeathPrefix(client, output, sizeof(output));
    Check(output[0] == '\0');
}

public void OnPluginStart()
{
    TestClient(-1);
    TestClient(0);
    TestClient(MaxClients + 1);
    for (int client = MaxClients; client >= 1; client--)
    {
        if (!IsClientInGame(client))
        {
            TestClient(client);
            break;
        }
    }

    KeyValues kv = new KeyValues("fixture");
    Check(!VoteMenu_TestConfigBool(kv, "disabled"));
    kv.SetString("disabled", "1");
    Check(VoteMenu_TestConfigBool(kv, "disabled"));
    kv.SetString("disabled", "true");
    Check(VoteMenu_TestConfigBool(kv, "disabled"));
    kv.SetString("disabled", "0");
    Check(!VoteMenu_TestConfigBool(kv, "disabled"));
    kv.SetString("disabled", "false");
    Check(!VoteMenu_TestConfigBool(kv, "disabled"));
    delete kv;

    // Actual production config parsed through the actual plugin loader.
    g_VoteOptions = new ArrayList(sizeof(VoteOption));
    VoteMenu_TestLoadConfig();
    Check(g_VoteOptions.Length > 0);
    Check(VoteMenu_TestFindVote("free_rtd") == -1);
    VoteOption option;
    bool freeListenerPresent;
    for (int index = 0; index < g_VoteOptions.Length; index++)
    {
        g_VoteOptions.GetArray(index, option);
        if (StrEqual(option.listener, "freertd", false))
            freeListenerPresent = true;
    }
    Check(!freeListenerPresent);
    delete g_VoteOptions;
    PrintToServer("[PolicyProbe] checks=%d failures=%d", g_Checks, g_Failures);
}
