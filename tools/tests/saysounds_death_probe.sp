// Runs the production death-event router against an in-memory playback sink.
// No sounds, cookies, database writes, damage, or player events are emitted.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

// Cookie helpers are not exercised by this routing probe; avoid a lab DB/extension.
void GetClientCookie(int client, Handle cookie, char[] value, int size) { value[0] = '\0'; }
void SetClientCookie(int client, Handle cookie, const char[] value) {}
bool AreClientCookiesCached(int client) { return false; }

#define TEST_CLIENTS 4
#define MAX_COMMAND_NAME 64
#define MAX_GROUP_NAME 32
#define SAYSOUND_ON_KILL_ATTR "saysound on kill"

char g_szDeathSound[TEST_CLIENTS + 1][MAX_COMMAND_NAME * 4];
char g_szKillSound[TEST_CLIENTS + 1][MAX_COMMAND_NAME * 4];
Handle g_hDeathCookie, g_hKillCookie;
ConVar g_hDefaultDeathSound;
bool connected[TEST_CLIENTS + 1], mutedGroup[TEST_CLIENTS + 1][3];
bool hidden[TEST_CLIENTS + 1][TEST_CLIENTS + 1], forcedGroup[3];
float volume[TEST_CLIENTS + 1];
int plays[TEST_CLIENTS + 1], usage[TEST_CLIENTS + 1], targets[TEST_CLIENTS + 1];
char heard[TEST_CLIENTS + 1][PLATFORM_MAX_PATH], weaponCommand[MAX_COMMAND_NAME];
bool weaponValid;
int coin, coinCalls, weaponUsage, checks, failures, resolutions[TEST_CLIENTS + 1];

void Check(bool condition, const char[] label)
{
    checks++;
    if (!condition) { failures++; PrintToServer("[DeathSoundProbe] FAIL: %s", label); }
}
int ProbeClient(int userid) { return userid; }
bool ProbeInGame(int client) { return client > 0 && client <= TEST_CLIENTS && connected[client]; }
bool ProbeEntity(int entity) { return entity == 100 && weaponValid; }
int Weapons_GetKillingWeapon(int attacker, int victim)
{
    Check(attacker > 0 && attacker <= TEST_CLIENTS && attacker != victim, "valid distinct killing weapon source");
    return 100;
}
FeatureStatus ProbeFeature(FeatureType feature, const char[] name)
{
    Check(feature == FeatureType_Native && StrEqual(name, "Weapons_GetKillingWeapon"), "optional weapon API queried");
    return FeatureStatus_Available;
}
bool TF2CustAttr_GetString(int entity, const char[] name, char[] value, int size)
{
    Check(entity == 100 && StrEqual(name, SAYSOUND_ON_KILL_ATTR), "correct weapon sound attribute queried");
    strcopy(value, size, weaponCommand); return weaponCommand[0] != '\0';
}
void Strings_ToLower(char[] value, int size)
{
    for (int i = 0; i < size && value[i]; i++) value[i] = CharToLower(value[i]);
}
bool ProbePrecache(const char[] sample, bool preload)
{
    Check(StrEqual(sample, "weapon") && preload, "weapon override keeps precaching");
    return true;
}
int ProbeRandom(int minimum, int maximum)
{
    Check(minimum == 0 && maximum == 1, "one shared 50/50 selection");
    coinCalls++; return coin;
}
int SoundGroup(const char[] group)
{
    if (StrEqual(group, "kill")) return 1;
    if (StrEqual(group, "weapon")) return 2;
    return 0;
}
bool CanPlaySaySoundToClient(int client, const char[] group, float &emitVolume, bool forcePlayback = false)
{
    #pragma unused forcePlayback
    if (!ProbeInGame(client)) return false;
    int index = SoundGroup(group);
    if (forcedGroup[index]) { emitVolume = 1.0; return true; }
    emitVolume = volume[client];
    return emitVolume > 0.0 && !mutedGroup[client][index];
}
bool Oblivion_ShouldHide(int client, int initiator)
{
    return client > 0 && client <= TEST_CLIENTS && initiator >= 0
        && initiator <= TEST_CLIENTS && hidden[client][initiator];
}
bool PlaySaySoundToTarget(int client, const char[] path, const char[] group,
    bool forcePlayback = false, int initiator = 0)
{
    Check(client > 0 && client <= TEST_CLIENTS, "no unfiltered global broadcast");
    Check(!forcePlayback, "personal sounds do not bypass preferences");
    float emitVolume;
    if (!CanPlaySaySoundToClient(client, group, emitVolume) || Oblivion_ShouldHide(client, initiator))
        return false;
    plays[client]++;
    strcopy(heard[client], sizeof(heard[]), path);
    return true;
}
bool GetCommandSoundDataForClientEx(int client, const char[] command,
    char[] path, int pathLen, char[] group, int groupLen, bool &restricted,
    bool &paidRestricted, char[] selected, int selectedLen, bool &fromGroup,
    char[] sourceGroup, int sourceLen)
{
    resolutions[client]++;
    if (StrEqual(command, "locked")) { paidRestricted = true; return false; }
    if (!StrEqual(command, "death") && !StrEqual(command, "kill")
        && !StrEqual(command, "doh") && !StrEqual(command, "weapon"))
        return false;
    strcopy(path, pathLen, command);
    strcopy(selected, selectedLen, command);
    strcopy(group, groupLen, StrEqual(command, "doh") ? "death" : command);
    fromGroup = false; strcopy(sourceGroup, sourceLen, "");
    return true;
}
void LogSaySoundUsage(const char[] eventName, int sourceClient, int targetClient,
    const char[] command, const char[] path, const char[] group, bool fromGroup,
    const char[] sourceGroup, bool fromApi, const char[] kind)
{
    Check(StrEqual(command, path) && group[0] && !fromGroup && !sourceGroup[0] && !fromApi,
        "resolved sound metadata preserved for logging");
    Check(StrEqual(kind, "diesound") || StrEqual(kind, "killsound") || StrEqual(kind, "weapon_killsound"),
        "usage kind preserved");
    if (StrEqual(eventName, "weapon_killsound_used")) weaponUsage++;
    else { usage[sourceClient]++; targets[sourceClient] = targetClient; }
}

#define MaxClients TEST_CLIENTS
#define GetClientOfUserId ProbeClient
#define IsClientInGame ProbeInGame
#define IsValidEntity ProbeEntity
#define GetFeatureStatus ProbeFeature
#define PrecacheSound ProbePrecache
#define GetRandomInt ProbeRandom
#include "saysounds/event_sounds.sp"
#undef MaxClients
#undef GetClientOfUserId
#undef IsClientInGame
#undef IsValidEntity
#undef GetFeatureStatus
#undef PrecacheSound
#undef GetRandomInt

public Plugin myinfo = { name = "Saysounds death recipient regression probe", author = "Hombre", version = "1.0.0" };
public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int length)
{
    if (!FileExists("addons/sourcemod/data/deploy_finished_lab.marker"))
    {
        strcopy(error, length, "Private isolated lab marker required.");
        return APLRes_Failure;
    }
    return APLRes_Success;
}
public void OnPluginStart()
{
    g_hDefaultDeathSound = CreateConVar("sm_deathsound_probe_default", "doh", "Private regression fixture.");
    RegAdminCmd("sm_saysounds_death_probe", RunProbe, ADMFLAG_ROOT);
}
void Reset()
{
    coin = 0; coinCalls = 0; weaponUsage = 0; weaponValid = true;
    weaponCommand[0] = '\0'; g_hDefaultDeathSound.SetString("doh");
    for (int i = 0; i <= TEST_CLIENTS; i++)
    {
        connected[i] = i > 0; volume[i] = 1.0;
        plays[i] = 0; usage[i] = 0; targets[i] = -1; resolutions[i] = 0;
        heard[i][0] = '\0'; g_szDeathSound[i][0] = '\0'; g_szKillSound[i][0] = '\0';
        for (int j = 0; j <= TEST_CLIENTS; j++) hidden[i][j] = false;
        for (int j = 0; j < 3; j++) mutedGroup[i][j] = false;
    }
    for (int j = 0; j < 3; j++) forcedGroup[j] = false;
    strcopy(g_szDeathSound[1], sizeof(g_szDeathSound[]), "death");
    strcopy(g_szKillSound[2], sizeof(g_szKillSound[]), "kill");
}
void Death(int victim = 1, int attacker = 2)
{
    Event event = CreateEvent("player_death", true);
    Check(event != null, "private un-fired event available");
    if (event == null) return;
    event.SetInt("userid", victim); event.SetInt("attacker", attacker);
    Event_PlayerDeathPost(event, "player_death", false);
    event.Cancel();
}
void ExpectClient(int client, const char[] sound)
{
    Check(plays[client] == (sound[0] ? 1 : 0), "one or zero emissions per listener");
    Check(StrEqual(heard[client], sound), "recipient gets intended sound");
}
void Expect(const char[] victim, const char[] killer, const char[] third, const char[] fourth)
{
    ExpectClient(1, victim); ExpectClient(2, killer); ExpectClient(3, third); ExpectClient(4, fourth);
}
public Action RunProbe(int client, int args)
{
    if (client != 0) return Plugin_Handled;
    checks = 0; failures = 0;
    Reset(); Death(); Expect("death", "kill", "death", "death");
    Check(coinCalls == 1, "bystanders share one public draw");
    Check(resolutions[1] == 1 && resolutions[2] == 1, "preferences resolve once, not per listener");
    Check(usage[1] == 1 && usage[2] == 1, "personal/public usage not double counted");
    Check(targets[1] == 0 && targets[2] == 2, "public versus personal usage target");
    Reset(); coin = 1; Death(); Expect("death", "kill", "kill", "kill");
    Check(targets[1] == 1 && targets[2] == 0, "opposite public selection keeps personal targets");

    Reset(); g_szDeathSound[1][0] = '\0'; Death(); Expect("doh", "kill", "kill", "kill");
    Check(coinCalls == 0, "personal default never competes with killer preference publicly");
    Reset(); g_szKillSound[2][0] = '\0'; Death(); Expect("death", "", "death", "death");
    Reset(); g_szDeathSound[1][0] = '\0'; g_szKillSound[2][0] = '\0';
    Death(); Expect("doh", "", "doh", "doh");
    Reset(); g_szDeathSound[1][0] = '\0'; g_szKillSound[2][0] = '\0';
    g_hDefaultDeathSound.SetString(""); Death(); Expect("", "", "", "");

    Reset(); strcopy(g_szKillSound[1], sizeof(g_szKillSound[]), "kill");
    Death(1, 1); Expect("death", "death", "death", "death");
    Check(coinCalls == 0 && usage[1] == 1, "suicide has no killer sound");
    Reset(); Death(1, 0); Expect("death", "death", "death", "death");
    Reset(); Death(0, 2); Expect("kill", "kill", "kill", "kill");

    Reset(); strcopy(weaponCommand, sizeof(weaponCommand), "weapon");
    Death(); Expect("death", "kill", "weapon", "weapon");
    Check(weaponUsage == 1 && usage[1] == 1 && usage[2] == 1, "weapon override and personal sounds log once");
    Reset(); strcopy(weaponCommand, sizeof(weaponCommand), "weapon");
    for (int i = 1; i <= TEST_CLIENTS; i++) mutedGroup[i][2] = true;
    Death(); Expect("death", "kill", "death", "death");
    Check(weaponUsage == 0, "inaudible weapon override preserves old public fallback");
    Reset(); strcopy(weaponCommand, sizeof(weaponCommand), "weapon");
    mutedGroup[3][2] = true; mutedGroup[4][2] = true;
    Death(); Expect("death", "kill", "", "");
    Check(coinCalls == 0 && weaponUsage == 0, "legacy weapon eligibility does not leak personal sounds to bystanders");
    Reset(); strcopy(weaponCommand, sizeof(weaponCommand), "weapon"); weaponValid = false;
    Death(); Expect("death", "kill", "death", "death");

    Reset(); mutedGroup[1][0] = true; Death(); Expect("", "kill", "death", "death");
    Reset(); mutedGroup[2][1] = true; coin = 1; Death(); Expect("death", "", "kill", "kill");
    Reset(); mutedGroup[3][0] = true; Death(); Expect("death", "kill", "", "death");
    Reset(); hidden[3][1] = true; Death(); Expect("death", "kill", "", "death");
    Reset(); strcopy(g_szKillSound[2], sizeof(g_szKillSound[]), "locked");
    Death(); Expect("death", "", "death", "death");
    Reset(); strcopy(g_szDeathSound[1], sizeof(g_szDeathSound[]), "locked");
    Death(); Expect("", "kill", "kill", "kill");
    Reset(); for (int i = 1; i <= TEST_CLIENTS; i++) volume[i] = 0.0;
    Death(); Expect("", "", "", "");
    Check(usage[1] == 0 && usage[2] == 0, "muted event emits no usage records");
    Reset(); for (int i = 1; i <= TEST_CLIENTS; i++) volume[i] = 0.0;
    forcedGroup[0] = true; Death(); Expect("death", "", "death", "death");

    ReplyToCommand(client, "[DeathSoundProbe] %d checks; %d failures; no sounds or live events emitted", checks, failures);
    return Plugin_Handled;
}
