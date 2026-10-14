/** Isolated engine-only merger regression tests. No production state or DB. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <weapons_ext>
#include <weapons_attributes>
#include <weapons_utils>
#include <weapons_view>
#include <weapons_damage>
int g_Bot, g_Checks, g_Failures, g_DamagePre, g_DamagePost, g_DamageRules;
bool g_ModifyCrit;
public Plugin myinfo = {name="Weapons Services Isolated Probe", author="Hombre",version="1.0"};
public void OnPluginStart() { RegAdminCmd("sm_weapons_services_probe", Probe, ADMFLAG_ROOT); }
void Check(bool condition,const char[] label) {
    g_Checks++;
    if(!condition) { g_Failures++; PrintToServer("[WeaponsServicesProbe] FAIL %s",label); }
    else PrintToServer("[WeaponsServicesProbe] PASS %s",label);
}
public Action Probe(int client,int args) {
    if(client!=0 || g_Bot) return Plugin_Handled;
    for(int other=1;other<=MaxClients;other++)
        if(IsClientConnected(other) && !IsFakeClient(other)) return Plugin_Handled;
    g_Checks=0; g_Failures=0;
    g_Bot=CreateFakeClient("Services isolated test");
    Check(g_Bot>0,"create fake client"); if(!g_Bot) return Plugin_Handled;
    ChangeClientTeam(g_Bot,2); TF2_SetPlayerClass(g_Bot,TFClass_Engineer); TF2_RespawnPlayer(g_Bot);
    CreateTimer(0.2,Run,GetClientUserId(g_Bot),TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}
public Action Run(Handle timer,int userid) {
    int bot=GetClientOfUserId(userid); if(bot!=g_Bot || !bot) return Plugin_Stop;
    Check(IsPlayerAlive(bot),"engine respawn");
    int weapon=GetPlayerWeaponSlot(bot,0);
    Check(weapon>MaxClients && WeaponsUtil_IsEntityWeapon(weapon),"weapon type");
    Check(WeaponsUtil_GetWeaponSlot(weapon)==0,"weapon slot");
    Check(WeaponsUtil_GetWeaponMaxClip(weapon)==6,"engine shotgun clip");
    Check(WeaponsUtil_GetPlayerMaxAmmo(bot,2)==200,"engine secondary max ammo");
    Check(WeaponsAttrib_SetByName(weapon,"damage bonus",1.25),"attribute set by name");
    Address attribute=WeaponsAttrib_GetByName(weapon,"damage bonus");
    Check(attribute!=Address_Null,"attribute lookup");
    Check(FloatAbs(WeaponsAttrib_GetValue(attribute)-1.25)<0.001,"attribute value ABI");
    Check(WeaponsAttrib_GetDefIndex(attribute)==2,"attribute definition ABI");
    Check(FloatAbs(WeaponsAttrib_HookValueFloat(1.0,"mult_dmg",weapon)-1.25)<0.001,"float attribute hook");
    WeaponsAttrib_RemoveByDefIndex(weapon,2);
    Check(WeaponsAttrib_GetByDefIndex(weapon,2)==Address_Null,"runtime remove");
    Check(WeaponsAttrib_SetFromStringValue(weapon,"damage bonus","1.50"),"numeric parsing");
    Check(FloatAbs(WeaponsAttrib_HookValueFloat(1.0,"mult_dmg",weapon)-1.5)<0.001,"parsed numeric value");
    Check(WeaponsAttrib_SetFromStringValue(weapon,"cosmetic taunt sound","weapons/batsaber_swing1.wav"),"heap string parsing");
    attribute=WeaponsAttrib_GetByName(weapon,"cosmetic taunt sound");
    char text[128];
    WeaponsAttrib_UnsafeGetStringValue(view_as<any>(WeaponsAttrib_GetValue(attribute)),text,sizeof(text));
    Check(StrEqual(text,"weapons/batsaber_swing1.wav"),"heap string read");
    WeaponsAttrib_HookValueString("fallback","nonexistent_probe_class",weapon,text,sizeof(text));
    Check(StrEqual(text,"fallback"),"string_t return ABI");
    Check(WeaponsAttrib_HookValueInt(37,"nonexistent_probe_class",weapon)==37,"integer attribute hook");
    int ids[32]; float values[32];
    Check(WeaponsAttrib_ListDefIndices(weapon,ids,sizeof(ids))>=2,"runtime attribute vector");
    Check(WeaponsAttrib_GetStaticAttribs(42,ids,values,sizeof(ids))>0,"static item attribute vector");
    Check(WeaponsAttrib_GetSOCAttribs(weapon,ids,values,sizeof(ids))>=0,"SOC view");
    WeaponsAttrib_RemoveByName(weapon,"cosmetic taunt sound");
    WeaponsAttrib_RemoveByName(weapon,"damage bonus");
    WeaponsAttrib_InvalidateDefinitions();
    Check(WeaponsAttrib_IsValidAttributeName("damage bonus"),"schema invalidation");
    TF2_AddCondition(bot,TFCond_SpeedBuffAlly,10.0,bot);
    Check(WeaponsUtil_GetPlayerConditionProvider(bot,TFCond_SpeedBuffAlly)==bot,"condition provider ABI");
    Check(WeaponsUtil_GetPlayerConditionDuration(bot,TFCond_SpeedBuffAlly)>0.0,"condition duration ABI");
    WeaponsUtil_SetPlayerConditionDuration(bot,TFCond_SpeedBuffAlly,3.0);
    Check(FloatAbs(WeaponsUtil_GetPlayerConditionDuration(bot,TFCond_SpeedBuffAlly)-3.0)<0.001,"condition mutation");
    WeaponsUtil_SetPlayerConditionProvider(bot,TFCond_SpeedBuffAlly,bot);
    TF2_RemoveCondition(bot,TFCond_SpeedBuffAlly);
    Check(WeaponsUtil_GetConditionCount()>100,"condition bounds");
    WeaponsUtil_GetConditionName(TFCond_OnFire,text,sizeof(text));
    Check(text[0]!=0,"condition name address");
    int sharedOffset=FindSendPropInfo("CTFPlayer","m_Shared");
    Check(WeaponsUtil_GetPlayerFromSharedAddress(GetEntityAddress(bot)+view_as<Address>(sharedOffset))==bot,"shared client cache");
    Check(WeaponsUtil_GetEntityMaxHealth(bot)==125,"entity max health");
    Check(WeaponsUtil_GetPlayerMaxHealthBoost(bot)>=125,"shared overheal health");
    SetEntityHealth(bot,100);
    Check(WeaponsUtil_TakeHealth(bot,5.0)==5 && GetClientHealth(bot)==105,"engine health call");
    Check(WeaponsUtil_GetPlayerLoadoutEntity(bot,0)>MaxClients,"native loadout entity");
    float position[3]; WeaponsUtil_GetPlayerShootPosition(bot,position);
    Check(position[2]!=0.0,"vector return shoot position");
    Check(WeaponsUtil_IsCustomDamageTypeDOT(TF_CUSTOM_BLEEDING),"DOT config");
    WeaponsUtil_UpdatePlayerSpeed(bot,true);
    WeaponsUtil_UpdatePlayerSpeed(bot,false);
    WeaponsView_SetLimits(20,160);
    WeaponsView_SetPreference(bot,136);
    Check(GetEntProp(bot,Prop_Send,"m_iFOV")==136,"native FOV preference");
    Check(WeaponsView_SetZoom(bot,48,0.15),"native hunting zoom call");
    Check(GetEntProp(bot,Prop_Send,"m_iFOV")==48,"zoom target FOV");
    WeaponsView_SetPreference(bot,144);
    Check(GetEntProp(bot,Prop_Send,"m_iFOV")==48,"preference does not undo custom zoom");
    Check(WeaponsView_SetZoom(bot,0,0.15),"native unzoom");
    Check(GetEntProp(bot,Prop_Send,"m_iFOV")==144,"unzoom restores saved preference");
    Check(GetEntPropEnt(bot,Prop_Data,"m_hZoomOwner")==-1,"zoom owner cleared");
    WeaponsView_SetCentered(bot,true);
    attribute=WeaponsAttrib_GetByDefIndex(weapon,289);
    Check(attribute!=Address_Null && WeaponsAttrib_GetValue(attribute)==1.0,"centered weapon attribute");
    WeaponsView_SetCentered(bot,false);
    attribute=WeaponsAttrib_GetByDefIndex(weapon,289);
    Check(attribute!=Address_Null && WeaponsAttrib_GetValue(attribute)==0.0,"center setting disabled");
    int previous=WeaponsUtil_GetPlayerWearableCount(bot);
    Handle hat=TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
    TF2Items_SetClassname(hat,"tf_wearable"); TF2Items_SetItemIndex(hat,54);
    TF2Items_SetQuality(hat,6); TF2Items_SetLevel(hat,10); TF2Items_SetNumAttributes(hat,0);
    int wearable=TF2Items_GiveNamedItem(bot,hat); delete hat;
    Check(wearable>MaxClients && WeaponsUtil_IsEntityWearable(wearable),"hat type");
    WeaponsUtil_EquipPlayerWearable(bot,wearable);
    Check(WeaponsUtil_GetPlayerWearableCount(bot)==previous+1,"native hat equip/vector");
    Check(WeaponsUtil_GetPlayerWearable(bot,previous)==wearable,"wearable vector handle");
    WeaponsAttrib_SetByName(wearable,"set item tint RGB",12345.0);
    attribute=WeaponsAttrib_GetByName(wearable,"set item tint RGB");
    Check(attribute!=Address_Null && WeaponsAttrib_GetValue(attribute)==12345.0,"hat attribute pipeline");
    TF2_RemoveWearable(bot,wearable);
    g_DamagePre=0; g_DamagePost=0; g_DamageRules=0; g_ModifyCrit=true;
    // Use a real player attacker for a player-owned weapon. TF2's kill-eater
    // bookkeeping assumes that relationship; world + owned weapon is invalid.
    SDKHooks_TakeDamage(bot,bot,bot,3.0,DMG_GENERIC,weapon);
    g_ModifyCrit=false;
    Check(g_DamagePre==1 && g_DamagePost==1,"one native pre/post damage callback");
    Check(g_DamageRules>0,"native damage rules callback");
    PrintToServer("[WeaponsServicesProbe] checks=%d failures=%d",g_Checks,g_Failures);
    KickClient(bot,"isolated test complete"); g_Bot=0;
    return Plugin_Stop;
}
public Action Weapons_OnTakeDamage(int victim,int &attacker,int &inflictor,float &damage,int &type,int &weapon,float force[3],float position[3],int custom,CritType &crit) {
    if(victim!=g_Bot) return Plugin_Continue;
    g_DamagePre++;
    if(g_ModifyCrit) { crit=CritType_MiniCrit; return Plugin_Changed; }
    return Plugin_Continue;
}
public void Weapons_OnTakeDamagePost(int victim,int attacker,int inflictor,float damage,int type,int weapon,const float force[3],const float position[3],int custom,CritType crit) {
    if(victim==g_Bot) g_DamagePost++;
}
public Action Weapons_OnTakeDamageModifyRules(int victim,int &attacker,int &inflictor,float &damage,int &type,int &weapon,float force[3],float position[3],int custom,CritType &crit) {
    if(victim==g_Bot) g_DamageRules++;
    return Plugin_Continue;
}
