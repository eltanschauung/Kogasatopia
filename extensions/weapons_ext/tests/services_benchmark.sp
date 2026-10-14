/** Bounded, isolated weapons AND hats workload; no cookies/database access. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <weapons_ext>
#include <weapons_attributes>
#include <weapons_utils>
int g_Bots[16];
public Plugin myinfo={name="Weapons Services Benchmark",author="Hombre",version="1"};
public void OnPluginStart() { RegAdminCmd("sm_services_benchmark",Benchmark,ADMFLAG_ROOT); }
public Action Benchmark(int client,int args) {
    if(client!=0) return Plugin_Handled;
    for(int i=1;i<=MaxClients;i++) if(IsClientConnected(i)) {
        PrintToServer("[ServicesBenchmark] Refusing nonempty test server"); return Plugin_Handled;
    }
    for(int i=0;i<16;i++) {
        g_Bots[i]=CreateFakeClient("Bounded inventory test");
        if(!g_Bots[i]) { Cleanup(); PrintToServer("[ServicesBenchmark] Could not create 16 fake clients"); return Plugin_Handled; }
        ChangeClientTeam(g_Bots[i],i%2 ? 2 : 3);
        TF2_SetPlayerClass(g_Bots[i],TFClass_Engineer); TF2_RespawnPlayer(g_Bots[i]);
    }
    CreateTimer(0.2,Run,_,TIMER_FLAG_NO_MAPCHANGE); return Plugin_Handled;
}
public Action Run(Handle timer) {
    float weaponTime=0.0,hatTime=0.0,lookupTime;
    Handle item=TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
    TF2Items_SetClassname(item,"tf_wearable");TF2Items_SetItemIndex(item,54);
    TF2Items_SetQuality(item,6);TF2Items_SetLevel(item,10);TF2Items_SetNumAttributes(item,0);
    float start=GetEngineTime();
    int primary=GetPlayerWeaponSlot(g_Bots[0],0);
    for(int repeat=0;repeat<10000;repeat++) {
        WeaponsAttrib_GetByName(primary,"damage bonus");
        WeaponsAttrib_HookValueInt(0,"parachute_attribute",g_Bots[0]);
        WeaponsUtil_GetWeaponSlot(primary);
    }
    lookupTime=GetEngineTime()-start;
    for(int round=0;round<10;round++) for(int i=0;i<16;i++) {
        int bot=g_Bots[i];
        start=GetEngineTime();
        TF2_RegeneratePlayer(bot);
        primary=GetPlayerWeaponSlot(bot,0);
        WeaponsAttrib_SetByName(primary,"damage bonus",1.25);
        WeaponsAttrib_HookValueFloat(1.0,"mult_dmg",primary);
        WeaponsAttrib_RemoveByName(primary,"damage bonus");
        weaponTime+=GetEngineTime()-start;
        start=GetEngineTime();
        int hat=TF2Items_GiveNamedItem(bot,item);
        WeaponsUtil_EquipPlayerWearable(bot,hat);
        WeaponsAttrib_SetByName(hat,"set item tint RGB",12345.0);
        WeaponsAttrib_SetByName(hat,"set item tint RGB 2",54321.0);
        WeaponsAttrib_SetFromStringValue(hat,"cosmetic taunt sound","weapons/batsaber_swing1.wav");
        WeaponsAttrib_RemoveByName(hat,"cosmetic taunt sound");
        TF2_RemoveWearable(bot,hat);
        hatTime+=GetEngineTime()-start;
    }
    delete item;
    PrintToServer("[ServicesBenchmark] players=16 weapon_regens=160 hats=160 lookup_triplets=10000 lookup_ms=%.3f weapons_ms=%.3f hats_ms=%.3f",lookupTime*1000.0,weaponTime*1000.0,hatTime*1000.0);
    Cleanup(); return Plugin_Stop;
}
void Cleanup() {
    for(int i=0;i<16;i++) if(g_Bots[i]) {
        if(IsClientInGame(g_Bots[i])) KickClient(g_Bots[i],"isolated workload finished");g_Bots[i]=0;
    }
}
