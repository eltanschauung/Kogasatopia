#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include "strings.inc"

#define ANNOUNCER_MAX_COMMAND_NAME 64
#define ANNOUNCER_SOUND_PLAY_AS_NATIVE "SaySounds_PlayCommandAs"
#define ANNOUNCER_SOUND_NATIVE "SaySounds_PlayCommand"
#define MAX_COMMAND_NAME 64
#define MAX_GROUP_NAME 32
#define MAX_SOUND_OPTIONS 16
#define DEFAULT_GROUP "all"

public Plugin myinfo = {
    name = "Announcer synchronization regression probe",
    author = "Kogasatopia",
    description = "Exercises production selection and delivery with simulated listeners.",
    version = "1.0"
};

StringMap gSoundMap, gSoundGroupMap;
ArrayList gCommandNames, gCandidates;
bool gConfigLoaded = true;
int gOwned[MAXPLAYERS + 1], gDisabled[MAXPLAYERS + 1];
bool gMuted[MAXPLAYERS + 1];
char gHeard[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
int gSeeds[MAXPLAYERS + 1];
int gRandomReads, gAssertions, gFailures, gCenterMessages;

bool IsHumanAnnouncerClient(int client) { return client >= 1 && client <= 7; }
bool IsValidAnnouncerClient(int client) { return IsHumanAnnouncerClient(client); }
bool CanUsePurchaseAwareSoundSelection(int client) { return IsHumanAnnouncerClient(client); }
bool ShouldResolveAnnouncerSoundPerListener(const char[] command) { return !SaySounds_IsCommandPaid(command); }
ArrayList FindAnnouncerSoundCommandList(const char[] command) { return gCandidates; }
bool Oblivion_ShouldHide(int target, int source) { return false; }
FeatureStatus ProbeFeature(FeatureType type, const char[] name) { return FeatureStatus_Available; }
void ProbeCenter(int client, const char[] text, any ...) { gCenterMessages++; }

int GroupMask(const char[] command) {
    if (StrEqual(command, "dragonball") || StrContains(command, "db_") == 0) return 1;
    if (StrEqual(command, "family") || StrContains(command, "family_") == 0) return 2;
    return 0;
}
bool SaySounds_IsCommandPaid(const char[] command) { return GroupMask(command) != 0; }
bool SaySounds_CanClientUseCommand(int client, const char[] command) {
    int mask = GroupMask(command);
    return mask == 0 || (gOwned[client] & mask) != 0;
}
bool IsAnnouncerSoundCommandDisabled(int client, const char[] command) {
    return (gDisabled[client] & GroupMask(command)) != 0;
}
bool ResolveKnownGroupName(const char[] group, char[] output, int length) {
    if (!StrEqual(group, "dragonball") && !StrEqual(group, "family")) return false;
    strcopy(output, length, group);
    return true;
}
bool IsAnnouncerOnlyCommand(const char[] command) { return false; }
bool CanUseAPIOnlySaySoundGroup(const char[] group, bool bypass) { return true; }
bool CanClientUsePaidSaysoundGroup(int client, const char[] group) {
    return SaySounds_CanClientUseCommand(client, group);
}
int ProbeRandom(int minimum, int maximum) {
    gRandomReads++;
    return minimum + (gRandomReads * 7919) % (maximum - minimum + 1);
}

bool ProbePlay(int source, int target, const char[] command, bool force, bool bypass, int seed) {
    char path[PLATFORM_MAX_PATH], group[MAX_GROUP_NAME], selected[MAX_COMMAND_NAME], sourceGroup[MAX_GROUP_NAME];
    bool restricted, paidRestricted, fromGroup;
    if (!GetCommandSoundDataForClientEx(source, command, path, sizeof(path), group, sizeof(group),
        restricted, paidRestricted, selected, sizeof(selected), fromGroup, sourceGroup, sizeof(sourceGroup), bypass, true, true, seed)) return false;
    bool played;
    for (int client = 1; client <= 7; client++) {
        if ((target != 0 && client != target) || (!force && gMuted[client])) continue;
        strcopy(gHeard[client], sizeof(gHeard[]), path);
        gSeeds[client] = seed;
        played = true;
    }
    return played;
}
bool ProbePlayAs(int source, int target, const char[] command, bool force, bool bypass, int seed) {
    return ProbePlay(source, target, command, force, bypass, seed);
}
bool ProbePlayCommand(int target, const char[] command, bool force, bool bypass, int seed) {
    return ProbePlay(6, target, command, force, bypass, seed);
}

#define GetRandomInt ProbeRandom
#define GetFeatureStatus ProbeFeature
#define PrintCenterText ProbeCenter
#define SaySounds_PlayCommandAs ProbePlayAs
#define SaySounds_PlayCommand ProbePlayCommand
#include "announcer_sync_under_test.inc"
#include "saysounds_selection_under_test.inc"

void Check(bool result, const char[] label) {
    gAssertions++;
    if (!result) {
        gFailures++;
        PrintToServer("[AnnouncerSyncProbe] FAIL: %s", label);
    }
}
void AddSound(const char[] command, const char[] group) {
    char path[PLATFORM_MAX_PATH];
    FormatEx(path, sizeof(path), "probe/%s.mp3", command);
    gSoundMap.SetString(command, path);
    gSoundGroupMap.SetString(command, group);
    gCommandNames.PushString(command);
    gCandidates.PushString(command);
}
void ResetDelivery() {
    for (int client = 1; client <= 7; client++) gHeard[client][0] = '\0';
}

public void OnPluginStart() {
    gSoundMap = new StringMap();
    gSoundGroupMap = new StringMap();
    gCommandNames = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    gCandidates = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    AddSound("stock", "unreal");
    AddSound("db_a", "dragonball");
    AddSound("db_b", "dragonball");
    AddSound("family_a", "family");
    gOwned[1] = gOwned[2] = gOwned[3] = gOwned[7] = 1;
    gDisabled[3] = 1;
    gOwned[4] = 2;
    gOwned[5] = 3;
    gDisabled[5] = 2;
    gMuted[7] = true;

    Check(Announcer_PlaySound(0, 6, "stock"), "broadcast delivered");
    Check(StrEqual(gHeard[1], gHeard[2]) && StrEqual(gHeard[1], gHeard[5]), "same eligible pack selects same variant");
    Check(gSeeds[1] == gSeeds[2] && gSeeds[1] == gSeeds[5], "same variant shares sample seed");
    Check(StrContains(gHeard[1], "probe/db_") == 0, "paid override still selected");
    Check(StrEqual(gHeard[3], "probe/stock.mp3") && StrEqual(gHeard[6], "probe/stock.mp3"), "disabled/unowned pack retains default");
    Check(StrEqual(gHeard[4], "probe/family_a.mp3"), "other pack remains distinct");
    Check(!gHeard[7][0], "muted listener remains muted");

    ResetDelivery();
    Announcer_PlaySound(0, 1, "db_a");
    Check(StrEqual(gHeard[1], "probe/db_a.mp3") && StrEqual(gHeard[4], gHeard[1])
        && StrEqual(gHeard[6], gHeard[1]), "paid source sound still broadcasts unchanged");

    ResetDelivery();
    Announcer_CenterText(0, 6, "stock", true, "probe");
    Check(StrEqual(gHeard[1], gHeard[2]) && StrEqual(gHeard[1], gHeard[5]), "center-text broadcast also synchronized");
    Check(gCenterMessages == 6, "center-text delivery count preserved");

    StringMap choices = new StringMap();
    char first[64], second[64];
    int before = gRandomReads;
    SelectPaidAnnouncerSoundForListener(gCandidates, 1, first, sizeof(first), choices);
    SelectPaidAnnouncerSoundForListener(gCandidates, 2, second, sizeof(second), choices);
    Check(StrEqual(first, second) && gRandomReads == before + 1, "one command draw per eligible cohort");
    SelectAnnouncerSoundCommand(gCandidates, 5, second, sizeof(second), choices);
    Check(StrEqual(first, second), "shutdown fallback shares paid selection");
    SelectPaidAnnouncerSoundForListener(gCandidates, 3, second, sizeof(second), choices);
    Check(!second[0], "empty eligible cohort has no override");

    ArrayList large = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    ArrayList eligible = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    ArrayList reordered = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    char candidate[MAX_COMMAND_NAME];
    for (int i = 0; i < 40; i++) {
        FormatEx(candidate, sizeof(candidate), "option_%d", i);
        large.PushString(candidate);
    }
    eligible.PushString("option_35");
    eligible.PushString("option_39");
    reordered.PushString("option_39");
    reordered.PushString("option_35");
    before = gRandomReads;
    SelectSynchronizedAnnouncerCommand(large, eligible, choices, first, sizeof(first));
    SelectSynchronizedAnnouncerCommand(large, reordered, choices, second, sizeof(second));
    Check(StrEqual(first, second) && gRandomReads == before + 1,
        "large eligibility signatures ignore filtered-list order");
    eligible.Clear();
    eligible.PushString("option_35");
    SelectSynchronizedAnnouncerCommand(large, eligible, choices, second, sizeof(second));
    Check(StrEqual(second, "option_35") && gRandomReads == before + 2,
        "eligibility above bit 32 has a distinct cache key");
    ArrayList otherList = large.Clone();
    before = gRandomReads;
    SelectSynchronizedAnnouncerCommand(otherList, reordered, choices, second, sizeof(second));
    Check(gRandomReads == before + 1, "different config lists have isolated choices");
    delete otherList;
    delete reordered;
    delete eligible;
    delete large;
    delete choices;
    choices = new StringMap();
    before = gRandomReads;
    SelectPaidAnnouncerSoundForListener(gCandidates, 1, second, sizeof(second), choices);
    Check(gRandomReads == before + 1, "new announcement draws again");

    Announcer_PlaySound(1, 6, "dragonball", choices);
    Announcer_PlaySound(2, 6, "dragonball", choices);
    Check(StrEqual(gHeard[1], gHeard[2]) && gSeeds[1] == gSeeds[2], "group sample synchronized across targeted deliveries");
    Announcer_PlaySound(1, 6, "db_a,db_b", choices);
    Announcer_PlaySound(2, 6, "db_a,db_b", choices);
    Check(StrEqual(gHeard[1], gHeard[2]), "comma-list sample synchronized");
    int previousSeed = gSeeds[1];
    delete choices;
    choices = new StringMap();
    Announcer_PlaySound(1, 6, "db_a,db_b", choices);
    Check(gSeeds[1] != previousSeed, "sample seed lifetime ends with announcement");
    delete choices;

    int state = -1;
    before = gRandomReads;
    GetSoundSelectionIndex(4, state);
    Check(gRandomReads == before + 1 && state == -1, "unseeded API retains normal randomness");
    before = gRandomReads;
    bool seen[4];
    for (int seed = 0; seed < 1000; seed++) {
        int left = seed, right = seed;
        int a = GetSoundSelectionIndex(4, left), b = GetSoundSelectionIndex(4, right);
        Check(a == b && a >= 0 && a < 4, "seeded choices match and stay in bounds");
        seen[a] = true;
    }
    Check(seen[0] && seen[1] && seen[2] && seen[3], "fresh seeds can choose every variant");
    Check(gRandomReads == before, "seeded selection leaves global RNG untouched");
    PrintToServer("[AnnouncerSyncProbe] %d assertions, %d failures", gAssertions, gFailures);
    delete gCandidates;
    delete gCommandNames;
    delete gSoundGroupMap;
    delete gSoundMap;
}
