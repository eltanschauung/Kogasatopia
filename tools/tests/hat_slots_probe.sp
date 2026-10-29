#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define MAX_HATS 32
#define HAT_MAX_SLOTS 8
#define HAT_SLOT_NAME_MAX 64
#define HAT_SLOT_LIST_MAX (HAT_MAX_SLOTS * HAT_SLOT_NAME_MAX)
enum TFClassType { TFClass_Unknown = 0, TFClass_Scout = 1 }
enum struct HatConfig
{
    char name[64];
    bool enabled;
    bool force;
    bool paintable;
    char id[64];
}
HatConfig g_Hats[MAX_HATS];
int g_iHatSlotCount[MAX_HATS], g_iHatCount;
char g_szHatSlots[MAX_HATS][HAT_MAX_SLOTS][HAT_SLOT_NAME_MAX];
bool g_bHatEnabled[MAXPLAYERS + 1][MAX_HATS];
int g_iClientEnabledHatCount[MAXPLAYERS + 1];
int checks, failures, removed, announcements;
char lastMessage[512];
ArrayList lastMenu;
bool visible[MAX_HATS];

methodmap TestMenu < Handle
{
    public TestMenu(Function handler)
    {
        #pragma unused handler
        return view_as<TestMenu>(new ArrayList(ByteCountToCells(64)));
    }
    public void SetTitle(const char[] title) {
        #pragma unused title
    }
    public bool AddItem(const char[] info, const char[] label)
    {
        #pragma unused label
        view_as<ArrayList>(this).PushString(info);
        return true;
    }
    property bool ExitBackButton
    {
        public set(bool enabled) {
            #pragma unused enabled
        }
    }
    public bool Display(int client, int seconds)
    {
        #pragma unused client
        #pragma unused seconds
        delete lastMenu;
        lastMenu = view_as<ArrayList>(this);
        return true;
    }
}
stock bool Client_IsInGame(int client) { return client == 1; }
stock bool IsHatIndexValid(int index) { return index >= 0 && index < g_iHatCount; }
stock bool IsHatEquippedForClient(int client, int index) { return g_bHatEnabled[client][index]; }
stock void RemoveHatIndex(int client, int index)
{
    #pragma unused client
    #pragma unused index
    removed++;
}
stock void GetHatChatColorForClientTeam(int client, int index, char[] out, int size)
{
    #pragma unused client
    #pragma unused index
    strcopy(out, size, "peachpuff");
}
stock void CPrintToChat(int client, const char[] format, any ...)
{
    #pragma unused client
    announcements++;
    VFormat(lastMessage, sizeof(lastMessage), format, 3);
}
stock void Strings_ToLower(char[] text, int size)
{
    for (int i = 0; i < size && text[i]; i++) text[i] = CharToLower(text[i]);
}
stock TFClassType TF2_GetPlayerClass(int client)
{
    #pragma unused client
    return TFClass_Scout;
}
stock bool CanClientViewHatForClass(int index, TFClassType playerClass)
{
    #pragma unused playerClass
    return visible[index];
}
stock bool CanClientAccessHat(int client, int index)
{
    #pragma unused client
    #pragma unused index
    return true;
}
stock void TestPrintToChat(int client, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused format
}
stock void MenuHandler_HatSlots() { }
stock void MenuHandler_Hats() { }

#define Menu TestMenu
#define PrintToChat TestPrintToChat
#include "slots.sp"
#include "hat_state_under_test.inc"
#include "hat_menus_under_test.inc"

void Check(bool pass, const char[] name)
{
    checks++;
    if (!pass) { failures++; PrintToServer("[HatSlotsProbe] FAIL: %s", name); }
}
void Seed(int index, const char[] slots)
{
    Check(CustomHats_ParseSlots(index, slots), "parse valid fixture");
    IntToString(index, g_Hats[index].id, sizeof(g_Hats[].id));
    Format(g_Hats[index].name, sizeof(g_Hats[].name), "Hat %d", index);
    visible[index] = true;
}
void ClearSelections()
{
    for (int i = 0; i < MAX_HATS; i++) g_bHatEnabled[1][i] = false;
    removed = announcements = 0;
}
bool MenuContains(const char[] value)
{
    return lastMenu != null && lastMenu.FindString(value) != -1;
}
public void OnPluginStart()
{
    g_iHatCount = 5;
    Seed(0, "Hat"); Seed(1, "Halo"); Seed(2, "Pet"); Seed(3, "Hat,Halo"); Seed(4, "");
    Check(g_iHatSlotCount[3] == 2 && CustomHats_HasSlot(3, "HAT") && CustomHats_HasSlot(3, "halo"),
        "multi-slot membership is case insensitive");
    Check(CustomHats_FindSharedSlot(0, 3) == 0 && CustomHats_FindSharedSlot(1, 3) == 0,
        "single-slot hats conflict with either occupied multi-slot");
    Check(CustomHats_FindSharedSlot(2, 3) == -1, "unrelated slots do not conflict");
    Check(CustomHats_HasSlot(4, "default"), "missing slot defaults to default");
    Check(CustomHats_ParseSlots(4, " , Hat,  HALO ,, hat, ") && g_iHatSlotCount[4] == 2,
        "trim whitespace, ignore empty entries and deduplicate case-insensitively");
    Check(CustomHats_ParseSlots(4, ", ,") && CustomHats_HasSlot(4, "default"), "empty-only list defaults");
    Check(CustomHats_ParseSlots(4, "hatbox") && CustomHats_FindSharedSlot(0, 4) == -1,
        "slot comparison is exact, not a substring match");
    Check(CustomHats_ParseSlots(4, "1,2,3,4,5,6,7,8"), "eight slots accepted");
    Check(!CustomHats_ParseSlots(4, "1,2,3,4,5,6,7,8,9"), "excess slots rejected rather than silently dropped");
    char longName[65];
    for (int i = 0; i < 64; i++) longName[i] = 'x';
    longName[64] = '\0';
    Check(!CustomHats_ParseSlots(4, longName), "overlong slot name rejected");
    longName[63] = '\0';
    Check(CustomHats_ParseSlots(4, longName), "63-byte slot name accepted");
    Seed(4, "default");

    g_bHatEnabled[1][0] = g_bHatEnabled[1][1] = g_bHatEnabled[1][2] = true;
    SetClientHatEnabled(1, 3, true, true);
    Check(!g_bHatEnabled[1][0] && !g_bHatEnabled[1][1] && g_bHatEnabled[1][2] && g_bHatEnabled[1][3],
        "equipping multi-slot hat removes both conflicts but preserves independent hat");
    Check(removed == 2 && announcements == 2 && g_iClientEnabledHatCount[1] == 2,
        "remove and announce each conflicting hat exactly once");
    Check(StrContains(lastMessage, "sharing slot 'halo'") != -1,
        "conflict message names the actual overlapping slot");
    SetClientHatEnabled(1, 3, false);
    SetClientHatEnabled(1, 0, true);
    Check(g_bHatEnabled[1][0] && !g_bHatEnabled[1][3], "disabling multi-slot hat releases its slots");
    SetClientHatEnabled(1, 3, true);
    SetClientHatEnabled(1, 1, true);
    Check(!g_bHatEnabled[1][3] && g_bHatEnabled[1][1], "single-slot selection can replace conflicting multi-slot hat");

    ClearSelections();
    g_bHatEnabled[1][0] = g_bHatEnabled[1][1] = g_bHatEnabled[1][2] = g_bHatEnabled[1][3] = true;
    Check(NormalizeClientHatSlots(1), "saved conflicting selections are normalized");
    Check(g_bHatEnabled[1][0] && g_bHatEnabled[1][1] && g_bHatEnabled[1][2] && !g_bHatEnabled[1][3],
        "normalization retains existing deterministic first-configured winners");
    Check(!NormalizeClientHatSlots(1), "normalization is idempotent");
    ClearSelections();
    Seed(0, "hat,halo"); Seed(1, "hat"); Seed(2, "halo"); Seed(3, "pet");
    for (int i = 0; i < 4; i++) g_bHatEnabled[1][i] = true;
    NormalizeClientHatSlots(1);
    Check(g_bHatEnabled[1][0] && !g_bHatEnabled[1][1] && !g_bHatEnabled[1][2] && g_bHatEnabled[1][3],
        "saved multi-slot winner reserves all its slots");

    ShowHatMenu(1);
    Check(lastMenu.Length == 4 && MenuContains("hat") && MenuContains("halo") && MenuContains("pet") && MenuContains("default"),
        "menu lists each constituent slot once");
    ShowHatsInSlotMenu(1, "halo");
    Check(lastMenu.Length == 2 && MenuContains("0") && MenuContains("2"), "multi-slot hat appears in Halo category");
    ShowHatsInSlotMenu(1, "hat");
    Check(lastMenu.Length == 2 && MenuContains("0") && MenuContains("1"), "multi-slot hat appears in Hat category");
    visible[0] = visible[1] = false;
    ShowHatMenu(1);
    Check(!MenuContains("hat") && MenuContains("halo"), "hidden hats do not create empty slot categories");
    delete lastMenu;
    PrintToServer("[HatSlotsProbe] %d checks, %d failures", checks, failures);
}
