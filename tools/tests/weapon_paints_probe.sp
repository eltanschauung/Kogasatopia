#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <weapons_attributes>
#define MAX_ITEM_IDENTIFIER_LENGTH 64
int g_iAppliedWeaponRef[MAXPLAYERS + 1];
int g_iLastViewmodelRef[MAXPLAYERS + 1];
int g_iLastWorldModelRef[MAXPLAYERS + 1];
int g_iLastOffHandViewmodelRef[MAXPLAYERS + 1];
stock bool Weapons_IsValidClient(int client) { return client == 1; }
#include "paint_under_test.inc"

int checks, failures;
void Check(bool condition, const char[] label)
{
    checks++;
    if (!condition) {
        failures++;
        LogError("[WeaponPaintProbe] FAIL: %s", label);
    }
}
float Tint(int entity, int index)
{
    Address attribute = WeaponsAttrib_GetByDefIndex(entity, index);
    return attribute ? WeaponsAttrib_GetValue(attribute) : -1.0;
}
public void OnPluginStart()
{
    int color, choice;
    char paintName[48];
    CustomHats_GetPaintName(0, paintName, sizeof(paintName));
    Check(StrEqual(paintName, "No Paint"), "shared hat paint menu labels");
    Check(ParseChatColor("orange", color) && color == 0xFFA500, "named color");
    Check(ParseChatColor("{deepskyblue}", color) && color == 0x00BFFF, "braced color");
    Check(ParseChatColor("HAUNTED", color) && color == 0x38F3AB, "case-insensitive color");
    Check(ParseChatColor("#aBcDeF", color) && color == 0xABCDEF, "hex color");
    Check(!ParseChatColor("{default}", color), "reject non-RGB chat token");
    Check(!ParseChatColor("#ABCDEFg", color), "reject trailing hex input");
    Check(!ParseChatColor("#12345g", color), "reject invalid hex input");
    Check(!ParseChatColor("not-a-color", color), "reject unknown color");
    Check(DecodePaintChoice("#000000", choice) && choice == (WEAPON_PAINT_CUSTOM_FLAG | 1), "near-black encoding");
    Check(!DecodePaintChoice("", choice), "reject empty cookie choice");
    Check(!DecodePaintChoice("30", choice) && !DecodePaintChoice("-1", choice), "reject invalid stock indexes");
    Check(DecodePaintChoice("29", choice) && choice == 29, "last stock paint");
    char encoded[16];
    EncodePaintChoice(WEAPON_PAINT_CUSTOM_FLAG | 0xABCDEF, encoded, sizeof(encoded));
    Check(StrEqual(encoded, "#ABCDEF") && DecodePaintChoice(encoded, choice)
        && choice == (WEAPON_PAINT_CUSTOM_FLAG | 0xABCDEF), "custom cookie round trip");

    StringMap paints = new StringMap();
    StringMap restored = new StringMap();
    char chunks[WEAPON_PAINT_COOKIE_CHUNKS][WEAPON_PAINT_COOKIE_LEN];
    int used;
    Check(BuildPaintCookieChunks(paints, chunks, used) && used == 0, "empty choices clear persistence");
    char key[64];
    for (int i; i < 20; i++) {
        key[0] = view_as<char>('a' + i); key[1] = '\0';
        paints.SetValue(key, 1);
    }
    Check(BuildPaintCookieChunks(paints, chunks, used) && used == 1, "20 short entries fit in one chunk");
    ReadPaintCookieChunk(restored, chunks[0]);
    Check(restored.Size == 20, "all entries after the sixteenth survive reload");
    ReadPaintCookieChunk(restored, "bad:999,negative:-1,empty:,custom:#FF8800");
    Check(restored.Size == 21 && restored.GetValue("custom", choice)
        && choice == (WEAPON_PAINT_CUSTOM_FLAG | 0xFF8800), "malformed entries ignored independently");
    paints.Clear();
    for (int i; i < 4; i++) {
        FormatEx(key, sizeof(key), "weapon_%050d", i);
        paints.SetValue(key, WEAPON_PAINT_CUSTOM_FLAG | 0xABCDEF);
    }
    Check(BuildPaintCookieChunks(paints, chunks, used) && used == 4, "long entries split into all four chunks");
    paints.SetValue("another_weapon_with_a_long_identifier_for_overflow_test", 1);
    Check(!BuildPaintCookieChunks(paints, chunks, used) && used == 0 && paints.Size == 5,
        "overflow rejected without silently dropping choices");
    delete paints; delete restored;

    int weapon = CreateEntityByName("tf_weapon_bat");
    int wearable = CreateEntityByName("tf_wearable");
    Check(weapon > MaxClients && wearable > MaxClients, "real TF2 econ entities created");
    if (weapon > MaxClients && wearable > MaxClients) {
        SetPaintAttributes(weapon, WEAPON_PAINT_CUSTOM_FLAG | 0xFF8800);
        Check(Tint(weapon, 142) == 16746496.0 && Tint(weapon, 261) == 16746496.0, "custom tint on weapon");
        CopyPaintAttribute(weapon, wearable, 142);
        CopyPaintAttribute(weapon, wearable, 261);
        Check(Tint(wearable, 142) == Tint(weapon, 142) && Tint(wearable, 261) == Tint(weapon, 261), "tint propagated to wearable");
        SetPaintAttributes(weapon, 27);
        Check(Tint(weapon, 142) == 12073019.0 && Tint(weapon, 261) == 5801378.0, "stock team paint has separate RED and BLU values");
        g_iAppliedWeaponRef[1] = EntIndexToEntRef(weapon);
        g_iLastViewmodelRef[1] = EntIndexToEntRef(wearable);
        g_iLastWorldModelRef[1] = g_iLastOffHandViewmodelRef[1] = INVALID_ENT_REFERENCE;
        WeaponsModels_ApplyWeaponPaint(1, weapon);
        Check(Tint(wearable, 142) == 12073019.0 && Tint(wearable, 261) == 5801378.0,
            "paint selection refreshes an already-valid model in place");
        SetPaintAttributes(weapon, 0);
        Check(Tint(weapon, 142) == -1.0 && Tint(weapon, 261) == -1.0, "No Paint removes both runtime tints");
        g_iAppliedWeaponRef[1] = INVALID_ENT_REFERENCE;
        WeaponsModels_ApplyWeaponPaint(1, weapon);
        Check(Tint(wearable, 142) == 12073019.0, "a different tracked weapon cannot repaint this model");
        g_iAppliedWeaponRef[1] = EntIndexToEntRef(weapon);
        WeaponsModels_ApplyWeaponPaint(1, weapon);
        Check(Tint(wearable, 142) == -1.0 && Tint(wearable, 261) == -1.0, "stale wearable tints cleared");
    }
    if (weapon > MaxClients) RemoveEntity(weapon);
    if (wearable > MaxClients) RemoveEntity(wearable);
    PrintToServer("[WeaponPaintProbe] %d checks, %d failures", checks, failures);
}
