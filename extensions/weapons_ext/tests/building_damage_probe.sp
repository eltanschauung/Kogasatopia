/** Isolated-only real CBaseObject damage test. Never load on a human server. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <sourcescramble>
#include <weapons_attributes>
#include <weapons_damage>
#define Weapons_OnBuildingTakeDamage BuildingCrit_ProductionPolicy
#include <weapons/building_crit_damage.sp>
#undef Weapons_OnBuildingTakeDamage

public Plugin myinfo={name="Building Crit Isolated Probe",author="Hombre",version="1.0"};
Handle g_BaseDamage,g_VirtualDamage;
int g_Red,g_Blue,g_Weapon,g_Checks,g_Failures,g_BuildingCalls,g_ExpectType,g_ExpectCrit;
int g_NpcEvents,g_DestroyedEvents;
bool g_Testing,g_ApplyPolicy=true;
char g_Context[64];
float g_LastForwardDamage;

public void OnPluginStart() {
    GameData conf=new GameData("weapons.games");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(conf,SDKConf_Signature,"CBaseObject::OnTakeDamage()");
    // ABI: one pointer-sized cell containing a test-owned DamageInfo address.
    PrepSDKCall_AddParameter(SDKType_PlainOldData,SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData,SDKPass_Plain);
    g_BaseDamage=EndPrepSDKCall();delete conf;
    if(!g_BaseDamage)SetFailState("Missing building damage signature");
    conf=new GameData("sdkhooks.games");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(conf,SDKConf_Virtual,"OnTakeDamage");
    PrepSDKCall_AddParameter(SDKType_PlainOldData,SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData,SDKPass_Plain);
    g_VirtualDamage=EndPrepSDKCall();delete conf;
    if(!g_VirtualDamage)SetFailState("Missing virtual damage binding");
    RegAdminCmd("sm_building_damage_probe",Command_Probe,ADMFLAG_ROOT);
    HookEvent("npc_hurt",Hurt,EventHookMode_Post);
    HookEvent("object_destroyed",Destroyed,EventHookMode_Post);
}
void Check(bool okay,const char[] label) {
    g_Checks++;
    if(!okay) {g_Failures++;PrintToServer("[BuildingCritProbe] FAIL %s: %s",g_Context,label);}
}
public Action Command_Probe(int client,int args) {
    if(client!=0 || g_Testing)return Plugin_Handled;
    char map[64];GetCurrentMap(map,sizeof(map));
    if(!FindConVar("sv_lan").BoolValue || !StrEqual(map,"itemtest")) {
        PrintToServer("[BuildingCritProbe] Refusing non-isolated test environment");return Plugin_Handled;
    }
    for(int i=1;i<=MaxClients;i++) if(IsClientConnected(i)) {
        PrintToServer("[BuildingCritProbe] Refusing a nonempty server");return Plugin_Handled;
    }
    g_Checks=0;g_Failures=0;g_BuildingCalls=0;g_NpcEvents=0;g_DestroyedEvents=0;g_Testing=true;
    g_Red=CreateFakeClient("Building target owner");g_Blue=CreateFakeClient("Building test attacker");
    if(!g_Red || !g_Blue) {Cleanup();SetFailState("Could not create test clients");}
    ChangeClientTeam(g_Red,2);ChangeClientTeam(g_Blue,3);
    TF2_SetPlayerClass(g_Red,TFClass_Engineer);TF2_SetPlayerClass(g_Blue,TFClass_Engineer);
    TF2_RespawnPlayer(g_Red);TF2_RespawnPlayer(g_Blue);
    CreateTimer(0.2,Run,_,TIMER_FLAG_NO_MAPCHANGE);return Plugin_Handled;
}
int Building(const char[] name,int type,int mode) {
    int entity=CreateEntityByName(name);
    if(entity<=MaxClients)return -1;
    SetEntPropEnt(entity,Prop_Send,"m_hBuilder",g_Red);
    SetEntProp(entity,Prop_Send,"m_iTeamNum",2);
    SetEntProp(entity,Prop_Send,"m_iObjectType",type);
    SetEntProp(entity,Prop_Send,"m_iObjectMode",mode);
    if(!DispatchSpawn(entity)) {RemoveEntity(entity);return -1;}
    SetEntProp(entity,Prop_Send,"m_bPlacing",0);
    SetEntProp(entity,Prop_Send,"m_bBuilding",0);
    SetEntProp(entity,Prop_Data,"m_takedamage",2);
    SetEntProp(entity,Prop_Data,"m_lifeState",0);
    SetEntPropFloat(entity,Prop_Send,"m_flPercentageConstructed",1.0);
    float origin[3]={0.0,0.0,512.0};origin[0]=float(entity*16);
    TeleportEntity(entity,origin,NULL_VECTOR,NULL_VECTOR);
    ResetHealth(entity);return entity;
}
void ResetHealth(int entity) {SetVariantInt(2000);AcceptEntityInput(entity,"SetHealth");}
MemoryBlock HitInfo(float damage,int crit,int flags=0,int custom=0) {
    MemoryBlock info=new MemoryBlock(104);
    info.StoreToOffset(36,EntIndexToEntRef(g_Blue)&0x7FFFFFFF,NumberType_Int32);
    info.StoreToOffset(40,EntIndexToEntRef(g_Blue)&0x7FFFFFFF,NumberType_Int32);
    info.StoreToOffset(44,EntIndexToEntRef(g_Weapon)&0x7FFFFFFF,NumberType_Int32);
    info.StoreToOffset(48,view_as<int>(damage),NumberType_Int32);
    info.StoreToOffset(52,view_as<int>(damage),NumberType_Int32);
    info.StoreToOffset(56,view_as<int>(-1.0),NumberType_Int32);
    info.StoreToOffset(60,flags,NumberType_Int32);
    info.StoreToOffset(64,custom,NumberType_Int32);
    info.StoreToOffset(88,-1,NumberType_Int32);
    info.StoreToOffset(100,crit,NumberType_Int32);
    return info;
}
void Damage(int entity,MemoryBlock info,int crit,int flags) {
    g_ExpectType=flags;g_ExpectCrit=(flags & DMG_CRIT) ? 2 : crit;
    // Virtual entry also runs sentry-specific modifiers before the base detour.
    SDKCall(g_VirtualDamage,entity,info.Address);
}
void TestHit(int entity,int crit,int flags,int expected,int custom=0,float base=20.0) {
    ResetHealth(entity);int calls=g_BuildingCalls;
    MemoryBlock info=HitInfo(base,crit,flags,custom);
    Damage(entity,info,crit,flags);
    int actual=2000-GetEntProp(entity,Prop_Send,"m_iHealth");
    if(actual!=expected)PrintToServer("[BuildingCritProbe] mismatch base=%.1f crit=%d flags=%d custom=%d expected=%d actual=%d",base,crit,flags,custom,expected,actual);
    Check(actual==expected,"actual engine health loss");
    Check(g_BuildingCalls==calls+1,"one building forward per hit");
    Check(info.LoadFromOffset(48,NumberType_Int32)==view_as<int>(base),"caller damage not mutated");
    Check(info.LoadFromOffset(100,NumberType_Int32)==crit,"caller crit unchanged");
    Check(info.LoadFromOffset(60,NumberType_Int32)==flags,"caller flags unchanged");
    delete info;
}
public Action Run(Handle timer) {
    g_Weapon=GetPlayerWeaponSlot(g_Blue,0);
    Check(g_Weapon>MaxClients,"real attacker-owned weapon");
    char names[][]={"obj_sentrygun","obj_dispenser","obj_teleporter","obj_teleporter"};
    int types[]={2,0,1,1};
    int buildings[4];
    for(int i=0;i<4;i++) {
        Format(g_Context,sizeof(g_Context),"%s mode=%d",names[i],i==3?1:0);
        int entity=Building(names[i],types[i],i==3?1:0);buildings[i]=entity;
        Check(entity>MaxClients,"spawn building");if(entity<=MaxClients)continue;
        g_ApplyPolicy=false;TestHit(entity,2,DMG_CRIT,20);g_ApplyPolicy=true;
        TestHit(entity,0,0,20);TestHit(entity,1,0,27);TestHit(entity,2,DMG_CRIT,60);
        TestHit(entity,1,DMG_CRIT,60);TestHit(entity,0,DMG_CRIT,60);TestHit(entity,2,0,60);
        TestHit(entity,0,0,0,0,0.0);TestHit(entity,3,0,20);
        // Engine mult_dmg_vs_buildings runs AFTER the custom multiplier.
        bool attribute=WeaponsAttrib_SetByName(g_Weapon,"dmg bonus vs buildings",2.0);
        Check(attribute,"building damage attribute exists");
        if(attribute) {TestHit(entity,0,0,40);TestHit(entity,1,0,54);TestHit(entity,2,DMG_CRIT,120);}
        WeaponsAttrib_RemoveByName(g_Weapon,"dmg bonus vs buildings");
        // Stock plasma resistance remains in the real building damage code.
        TestHit(entity,0,0,4,TF_CUSTOM_PLASMA);TestHit(entity,1,0,27,TF_CUSTOM_PLASMA,100.0);
        TestHit(entity,2,DMG_CRIT,12,TF_CUSTOM_PLASMA);
        SetEntProp(entity,Prop_Send,"m_bBuilding",1);
        TestHit(entity,0,0,20);TestHit(entity,1,0,27);TestHit(entity,2,DMG_CRIT,60);
        SetEntProp(entity,Prop_Send,"m_bBuilding",0);
        if(i==0) {
            SetEntProp(entity,Prop_Send,"m_nShieldLevel",1);
            // Stock shield passes 0.33x into the base method, not exactly 1/3.
            // CBaseObject exposes ceil(remaining health), truncating HP lost.
            TestHit(entity,0,DMG_BULLET,19,0,60.0);
            Check(FloatAbs(g_LastForwardDamage-19.8)<0.001,"stock shield precedes crit policy");
            TestHit(entity,1,DMG_BULLET,26,0,60.0);
            Check(FloatAbs(g_LastForwardDamage-19.8)<0.001,"mini shield input not pre-multiplied");
            TestHit(entity,2,DMG_BULLET|DMG_CRIT,59,0,60.0);
            Check(FloatAbs(g_LastForwardDamage-19.8)<0.001,"full shield input not pre-multiplied");
            SetEntProp(entity,Prop_Send,"m_nShieldLevel",0);
        }
    }
    strcopy(g_Context,sizeof(g_Context),"same damage record across multiple targets");
    MemoryBlock shared=HitInfo(20.0,2,DMG_CRIT);
    for(int i=0;i<4;i++) if(buildings[i]>MaxClients) {
        ResetHealth(buildings[i]);Damage(buildings[i],shared,2,DMG_CRIT);
        Check(2000-GetEntProp(buildings[i],Prop_Send,"m_iHealth")==60,"no cumulative crit multiplier");
    }
    delete shared;
    // Players still follow the existing native/SDKHooks path, never this forward.
    strcopy(g_Context,sizeof(g_Context),"player exclusion");
    int previous=g_BuildingCalls;
    SDKHooks_TakeDamage(g_Red,g_Blue,g_Blue,5.0,DMG_GENERIC,g_Weapon);
    Check(g_BuildingCalls==previous,"player never enters building forward");
    // Destruction/events still run through the original engine implementation.
    for(int i=0;i<4;i++) if(buildings[i]>MaxClients && IsValidEntity(buildings[i])) {
        SetVariantInt(20);AcceptEntityInput(buildings[i],"SetHealth");
        MemoryBlock lethal=HitInfo(20.0,2,DMG_CRIT);Damage(buildings[i],lethal,2,DMG_CRIT);delete lethal;
        if(IsValidEntity(buildings[i]))RemoveEntity(buildings[i]);
    }
    Check(g_NpcEvents>0,"npc_hurt events retained");
    Check(g_DestroyedEvents>=4,"building destruction events retained");
    PrintToServer("[BuildingCritProbe] checks=%d failures=%d building_calls=%d",g_Checks,g_Failures,g_BuildingCalls);
    Cleanup();return Plugin_Stop;
}
public Action Weapons_OnBuildingTakeDamage(int entity,int attacker,int inflictor,float &damage,
    int flags,int weapon,int custom,CritType crit) {
    if(!g_Testing)return Plugin_Continue;
    g_BuildingCalls++;
    g_LastForwardDamage=damage;
    Check(flags==g_ExpectType && view_as<int>(crit)==g_ExpectCrit,"real crit and flags preserved");
    if(!g_ApplyPolicy)return Plugin_Continue;
    return BuildingCrit_ProductionPolicy(entity,attacker,inflictor,damage,flags,weapon,custom,crit);
}
public void Hurt(Event event,const char[] name,bool noBroadcast) {if(g_Testing)g_NpcEvents++;}
public void Destroyed(Event event,const char[] name,bool noBroadcast) {if(g_Testing)g_DestroyedEvents++;}
void Cleanup() {
    if(g_Red>0 && IsClientConnected(g_Red))KickClient(g_Red,"isolated test complete");
    if(g_Blue>0 && IsClientConnected(g_Blue))KickClient(g_Blue,"isolated test complete");
    g_Red=0;g_Blue=0;g_Testing=false;
}
public void OnPluginEnd() {Cleanup();}
