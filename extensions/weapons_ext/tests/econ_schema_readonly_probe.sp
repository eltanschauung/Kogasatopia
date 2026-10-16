/** Read-only post-update schema smoke checks. Does not spawn clients or mutate the schema. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2_stocks>
#include <tf_econ_data>
int g_Checks, g_Failures;
void Check(bool passed, const char[] label)
{
    g_Checks++;
    if (!passed) g_Failures++;
    PrintToServer("[EconReadOnlyProbe] %s %s", passed ? "PASS" : "FAIL", label);
}
public void OnPluginStart()
{
    int slots = TF2Econ_GetLoadoutSlotCount();
    Check(slots > 0 && slots < 100, "loadout slot count");
    if (slots <= 0 || slots >= 100) return;
    Check(TF2Econ_TranslateLoadoutSlotNameToIndex("primary") == 0, "primary slot");
    Check(TF2Econ_TranslateLoadoutSlotNameToIndex("secondary") == 1, "secondary slot");
    Check(TF2Econ_TranslateLoadoutSlotNameToIndex("melee") == 2, "melee slot");
    Check(TF2Econ_TranslateLoadoutSlotNameToIndex("head") >= 0, "hat slot");
    Check(TF2Econ_TranslateLoadoutSlotNameToIndex("misc") >= 0, "misc slot");
    char text[128];
    Check(TF2Econ_GetAttributeName(2, text, sizeof(text)) && StrEqual(text, "damage bonus"), "attribute definition");
    Check(TF2Econ_GetItemLoadoutSlot(14, TFClass_Sniper) == 0, "sniper item slot");
    Check(TF2Econ_GetQualityName(6, text, sizeof(text)) && text[0] != 0, "quality table");
    ArrayList list = TF2Econ_GetRarityList();
    Check(list != null && list.Length > 0 && list.Length < 100, "rarity table");
    delete list;
    StringMap regions = TF2Econ_GetEquipRegionGroups();
    Check(regions != null && regions.Size > 0 && regions.Size < 1000, "equip-region table");
    delete regions;
    list = TF2Econ_GetParticleAttributeList(ParticleSet_CosmeticUnusualEffects);
    Check(list != null && list.Length > 0 && list.Length < 10000, "cosmetic particles");
    delete list;
    list = TF2Econ_GetParticleAttributeList(ParticleSet_WeaponUnusualEffects);
    Check(list != null && list.Length > 0 && list.Length < 10000, "weapon particles");
    delete list;
    list = TF2Econ_GetParticleAttributeList(ParticleSet_TauntUnusualEffects);
    Check(list != null && list.Length > 0 && list.Length < 10000, "taunt particles");
    delete list;
    PrintToServer("[EconReadOnlyProbe] checks=%d failures=%d", g_Checks, g_Failures);
}
