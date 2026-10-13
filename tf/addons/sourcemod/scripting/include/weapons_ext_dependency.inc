// SPDX-License-Identifier: GPL-3.0-or-later
#if defined _weapons_ext_dependency_included
    #endinput
#endif
#define _weapons_ext_dependency_included

public Extension __ext_weapons_ext = {
    name = "weapons_ext",
    // Match the autoload marker's canonical key. SourceMod selects the
    // engine-specific binary; spelling that suffix here loads the DSO twice.
    file = "weapons_ext.ext",
    autoload = 1,
#if defined REQUIRE_EXTENSIONS
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_EXTENSIONS
public void __ext_weapons_ext_SetNTVOptional()
{
    MarkNativeAsOptional("TF2_IgnitePlayer");
    MarkNativeAsOptional("TF2_RespawnPlayer");
    MarkNativeAsOptional("TF2_RegeneratePlayer");
    MarkNativeAsOptional("TF2_AddCondition");
    MarkNativeAsOptional("TF2_RemoveCondition");
    MarkNativeAsOptional("TF2_SetPlayerPowerPlay");
    MarkNativeAsOptional("TF2_DisguisePlayer");
    MarkNativeAsOptional("TF2_RemovePlayerDisguise");
    MarkNativeAsOptional("TF2_StunPlayer");
    MarkNativeAsOptional("TF2_MakeBleed");
    MarkNativeAsOptional("TF2_GetResourceEntity");
    MarkNativeAsOptional("TF2_GetClass");
    MarkNativeAsOptional("TF2_IsPlayerInDuel");
    MarkNativeAsOptional("TF2_IsHolidayActive");
    MarkNativeAsOptional("TF2_RemoveWearable");
    MarkNativeAsOptional("TF2Items_GiveNamedItem");
    MarkNativeAsOptional("TF2Items_CreateItem");
    MarkNativeAsOptional("TF2Items_SetFlags");
    MarkNativeAsOptional("TF2Items_GetFlags");
    MarkNativeAsOptional("TF2Items_SetClassname");
    MarkNativeAsOptional("TF2Items_GetClassname");
    MarkNativeAsOptional("TF2Items_SetItemIndex");
    MarkNativeAsOptional("TF2Items_GetItemIndex");
    MarkNativeAsOptional("TF2Items_SetQuality");
    MarkNativeAsOptional("TF2Items_GetQuality");
    MarkNativeAsOptional("TF2Items_SetLevel");
    MarkNativeAsOptional("TF2Items_GetLevel");
    MarkNativeAsOptional("TF2Items_SetNumAttributes");
    MarkNativeAsOptional("TF2Items_GetNumAttributes");
    MarkNativeAsOptional("TF2Items_SetAttribute");
    MarkNativeAsOptional("TF2Items_GetAttributeId");
    MarkNativeAsOptional("TF2Items_GetAttributeValue");
    MarkNativeAsOptional("TF2ConchNoSpeed_AddRegenBuff");
    MarkNativeAsOptional("TF2ConchNoSpeed_RemoveRegenBuff");
    MarkNativeAsOptional("TF2ConchNoSpeed_IsRegenBuffActive");
    MarkNativeAsOptional("TF2Scatter_GetLastKillPellets");
    MarkNativeAsOptional("TF2Scatter_WasLastKillFull");
    MarkNativeAsOptional("TF2Scatter_IsCurrentShotFull");
    MarkNativeAsOptional("TF2Scatter_SetWeaponPelletCount");
    MarkNativeAsOptional("TF2Spread_SetPattern");
    MarkNativeAsOptional("TF2Spread_SetAmbassadorAccuracy");
    MarkNativeAsOptional("TF2Spread_IsAmbassadorAccuracyRecovered");
    MarkNativeAsOptional("TF2Weapon_SetPunchAngle");
    MarkNativeAsOptional("TF2SentryNewTarget_SetEnabled");
    MarkNativeAsOptional("TF2SentryNewTarget_SetDistance");
    MarkNativeAsOptional("TF2SentryNewTarget_GetRangeOffset");
    MarkNativeAsOptional("WhitelistPolicy_BeginPolicy");
    MarkNativeAsOptional("WhitelistPolicy_RegisterDefinition");
    MarkNativeAsOptional("WhitelistPolicy_CommitPolicy");
    MarkNativeAsOptional("WhitelistPolicy_ResetTransactions");
    MarkNativeAsOptional("WhitelistPolicy_BeginInventory");
    MarkNativeAsOptional("WhitelistPolicy_EndInventory");
    MarkNativeAsOptional("WhitelistPolicy_Evaluate");
    MarkNativeAsOptional("WhitelistPolicy_GetStats");
    MarkNativeAsOptional("WeaponsLoadout_Bind");
    MarkNativeAsOptional("WeaponsLoadout_Unbind");
    MarkNativeAsOptional("WeaponsLoadout_PublishSelection");
    MarkNativeAsOptional("WeaponsLoadout_InvalidateClient");
    MarkNativeAsOptional("WeaponsLoadout_GetStats");
}
#endif
