#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools_sound>
#include <sdktools_stringtables>

#define MAX_GROUP_NAME 32

public Plugin myinfo = {
    name = "SaySounds replacement assets regression probe",
    author = "Hombre",
    description = "Checks FastDL-only replacement readiness without playing audio.",
    version = "1.0.0"
};

int checks, failures, existenceChecks, precaches, logs;
ArrayList downloads;

stock bool ProbeFileExists(const char[] path, bool useValveFs = false)
{
    #pragma unused path
    #pragma unused useValveFs
    existenceChecks++;
    return false;
}

bool ProbePrecache(const char[] path, bool preload)
{
    if (!preload) failures++;
    precaches++;
    return !StrEqual(path, "probe/rejected.mp3");
}

void ProbeDownload(const char[] path) { downloads.PushString(path); }

void ProbeError(const char[] format, any ...)
{
    char message[512];
    VFormat(message, sizeof(message), format, 2);
    if (StrContains(message, "failed to precache") == -1) failures++;
    logs++;
}

#define FileExists ProbeFileExists
#define PrecacheSound ProbePrecache
#define AddFileToDownloadsTable ProbeDownload
#define LogError ProbeError
#include "saysounds_replacement_assets_under_test.inc"
#undef FileExists
#undef PrecacheSound
#undef AddFileToDownloadsTable
#undef LogError

void Check(bool success, const char[] label)
{
    checks++;
    if (!success)
    {
        failures++;
        PrintToServer("[SaySoundsAssetsProbe] FAIL: %s", label);
    }
}

public void OnPluginStart()
{
    RegAdminCmd("sm_saysounds_replacement_probe", RunProbe, ADMFLAG_ROOT);
}

public Action RunProbe(int client, int args)
{
    #pragma unused client
    #pragma unused args
    checks = failures = existenceChecks = precaches = logs = 0;
    downloads = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    ArrayList replacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    ArrayList groups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    ArrayList ready = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    ArrayList readyGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    char path[PLATFORM_MAX_PATH], group[MAX_GROUP_NAME];

    replacements.PushString("probe/fastdl-only.mp3"); groups.PushString("first");
    replacements.PushString("probe/fastdl-only.wav"); groups.PushString("second");
    replacements.PushString("probe/rejected.mp3"); groups.PushString("rejected");
    ready.PushString("stale.mp3"); readyGroups.PushString("stale");

    PrecacheReplacementSounds(replacements, groups, ready, readyGroups, "Probe");
    Check(existenceChecks == 0, "no local filesystem check");
    Check(precaches == 3, "every configured sample attempts precache");
    Check(downloads.Length == 3, "download registration retained");
    Check(ready.Length == 2 && readyGroups.Length == 2, "only successful precaches enter aligned ready pools");
    ready.GetString(0, path, sizeof(path)); readyGroups.GetString(0, group, sizeof(group));
    Check(StrEqual(path, "probe/fastdl-only.mp3") && StrEqual(group, "first"), "MP3 path and group preserved");
    ready.GetString(1, path, sizeof(path)); readyGroups.GetString(1, group, sizeof(group));
    Check(StrEqual(path, "probe/fastdl-only.wav") && StrEqual(group, "second"), "WAV path and group preserved");
    downloads.GetString(0, path, sizeof(path));
    Check(StrEqual(path, "sound/probe/fastdl-only.mp3"), "download uses sound prefix");
    Check(logs == 1, "precache failure remains visible");

    replacements.Clear(); groups.Clear();
    PrecacheReplacementSounds(replacements, groups, ready, readyGroups, "Probe");
    Check(ready.Length == 0 && readyGroups.Length == 0, "empty config clears stale ready entries");

    // This existing production asset is on FastDL, not in the server sound tree.
    // Do not emit audio, add fabricated downloads, or modify any game entities.
    strcopy(path, sizeof(path), "unreal/killingspree.mp3");
    Check(!FileExists("sound/unreal/killingspree.mp3", true), "integration sample absent from server search paths");
    Check(PrecacheSound(path, true), "engine precaches FastDL-only MP3");
    Check(FindStringIndex(FindStringTable("soundprecache"), path) != INVALID_STRING_INDEX,
        "engine retains FastDL-only precache table entry");
    AddFileToDownloadsTable("sound/unreal/killingspree.mp3");
    Check(FindStringIndex(FindStringTable("downloadables"), "sound/unreal/killingspree.mp3") != INVALID_STRING_INDEX,
        "engine accepts FastDL-only download table entry");

    delete downloads; delete replacements; delete groups; delete ready; delete readyGroups;
    char result[128];
    FormatEx(result, sizeof(result), "checks=%d failures=%d", checks, failures);
    PrintToServer("[SaySoundsAssetsProbe] %s", result);
    File output = OpenFile("addons/sourcemod/data/saysounds-replacement-assets-probe.txt", "w");
    if (output != null) { output.WriteLine("%s", result); delete output; }
    return Plugin_Handled;
}
