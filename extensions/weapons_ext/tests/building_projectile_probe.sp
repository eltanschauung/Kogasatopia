/** Isolated LAN/itemtest only. Real stock PrimaryAttack -> rocket -> building. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2_stocks>
#include <weapons_attributes>
#include <weapons_damage>
#define Weapons_OnBuildingTakeDamage BuildingCrit_ProductionPolicy
#include <weapons/building_crit_damage.sp>
#undef Weapons_OnBuildingTakeDamage

public Plugin myinfo={name="Building Projectile Isolated Probe",author="Hombre",version="1.0"};
Handle g_Attack,g_CanAttack;
DynamicHook g_DamageHook;
int g_Red,g_Blue,g_Weapon,g_Target=-1,g_Rocket=INVALID_ENT_REFERENCE;
int g_Case,g_Checks,g_Failures,g_Leaks,g_PlayerRules,g_Shots,g_ForwardCalls;
int g_InventoryGeneration,g_CaseGeneration,g_Retries;
bool g_Running,g_Pre,g_Post,g_Forward,g_RocketSeen;
int g_RawCrit,g_RawType,g_Effective;
float g_RawDamage,g_ForwardBase,g_PolicyDamage,g_Deadline;
char g_Context[100];
#define MODES 9
#define CASES (4 * MODES * 2)
int Mode() {return (g_Case / 2) % MODES;}
int Kind() {return g_Case / (2 * MODES);}
int ExpectedCrit() {
    int mode=Mode();
    // Current Valve SetCritType refuses Full->Mini even in its demotion path.
    // This checks the real final field, not a guessed damage-derived crit.
    return mode==2 || mode==5 || mode==6 ? 2 : mode==0 ? 0 : 1;
}
void Check(bool okay,const char[] label) {
    g_Checks++;
    if(!okay) {g_Failures++;PrintToServer("[BuildingProjectileProbe] FAIL %s: %s",g_Context,label);}
}
public void OnPluginStart() {
    GameData data=new GameData("building-projectile-test");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(data,SDKConf_Signature,"CTFWeaponBaseGun::PrimaryAttack()");
    g_Attack=EndPrepSDKCall();
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(data,SDKConf_Signature,"CTFWeaponBase::CanAttack()");
    PrepSDKCall_SetReturnInfo(SDKType_Bool,SDKPass_Plain);
    g_CanAttack=EndPrepSDKCall();delete data;
    if(!g_Attack)SetFailState("Missing real PrimaryAttack binding");
    if(!g_CanAttack)SetFailState("Missing real CanAttack binding");
    data=new GameData("sdkhooks.games");
    int offset=data.GetOffset("OnTakeDamage");delete data;
    if(offset<=0)SetFailState("Missing damage virtual slot");
    g_DamageHook=new DynamicHook(offset,HookType_Entity,ReturnType_Int,ThisPointer_CBaseEntity);
    g_DamageHook.AddParam(HookParamType_ObjectPtr);
    RegAdminCmd("sm_building_projectile_probe",Begin,ADMFLAG_ROOT);
    HookEvent("post_inventory_application",Inventory,EventHookMode_Post);
}
public void Inventory(Event event,const char[] name,bool dontBroadcast) {
    if(g_Running && GetClientOfUserId(event.GetInt("userid"))==g_Blue)g_InventoryGeneration++;
}
public Action Begin(int client,int args) {
    if(client || g_Running)return Plugin_Handled;
    char map[64];GetCurrentMap(map,sizeof(map));
    if(!FindConVar("sv_lan").BoolValue || !StrEqual(map,"itemtest"))return Plugin_Handled;
    for(int i=1;i<=MaxClients;i++)if(IsClientConnected(i))return Plugin_Handled;
    g_Running=true;g_Case=0;g_Checks=0;g_Failures=0;g_Leaks=0;g_PlayerRules=0;
    if(args>0) {g_Case=GetCmdArgInt(1);if(g_Case<0 || g_Case>=CASES) {g_Running=false;return Plugin_Handled;}}
    g_InventoryGeneration=0;g_Retries=0;
    FindConVar("tf_weapon_criticals").IntValue=0;
    FindConVar("tf_damage_disablespread").IntValue=1;
    FindConVar("mp_friendlyfire").IntValue=0;
    g_Red=CreateFakeClient("Projectile target owner");g_Blue=CreateFakeClient("Projectile test soldier");
    if(!g_Red || !g_Blue) {Finish();return Plugin_Handled;}
    ChangeClientTeam(g_Red,2);ChangeClientTeam(g_Blue,3);
    TF2_SetPlayerClass(g_Red,TFClass_Engineer);TF2_SetPlayerClass(g_Blue,TFClass_Soldier);
    TF2_RespawnPlayer(g_Red);TF2_RespawnPlayer(g_Blue);
    GameRules_SetProp("m_iRoundState",RoundState_RoundRunning);
    SetEntityMoveType(g_Red,MOVETYPE_NONE);SetEntityMoveType(g_Blue,MOVETYPE_NONE);
    SetEntProp(g_Red,Prop_Data,"m_takedamage",0);SetEntProp(g_Blue,Prop_Data,"m_takedamage",0);
    float away[3]={0.0,2000.0,512.0};TeleportEntity(g_Red,away,NULL_VECTOR,NULL_VECTOR);
    CreateTimer(0.3,NextCase,_,TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}
public Action NextCase(Handle timer) {
    if(!g_Running)return Plugin_Stop;
    if(g_Case>=CASES || g_Failures>=3) {Finish();return Plugin_Stop;}
    GameRules_SetProp("m_iRoundState",RoundState_RoundRunning);
    char names[][]={"obj_sentrygun","obj_dispenser","obj_teleporter","obj_teleporter"};
    int types[]={2,0,1,1};
    int mode=Mode(),kind=Kind();float distance=(g_Case % 2)==0 ? 96.0 : 1024.0;
    Format(g_Context,sizeof(g_Context),"%s end=%d mode=%d range=%.0f",names[kind],kind==3,mode,distance);
    g_Weapon=GetPlayerWeaponSlot(g_Blue,0);
    Check(g_Weapon>MaxClients,"real Soldier primary weapon");
    if(g_Weapon<=MaxClients) {Finish();return Plugin_Stop;}
    g_CaseGeneration=g_InventoryGeneration;
    SetEntityMoveType(g_Blue,MOVETYPE_NONE);SetEntProp(g_Blue,Prop_Data,"m_takedamage",0);
    TF2_RemoveCondition(g_Blue,TFCond_Buffed);TF2_RemoveCondition(g_Blue,TFCond_Kritzkrieged);
    TF2_RemoveCondition(g_Blue,TFCond_CritCola);
    WeaponsAttrib_RemoveByName(g_Weapon,"minicrits become crits");
    WeaponsAttrib_RemoveByName(g_Weapon,"crits_become_minicrits");
    WeaponsAttrib_RemoveByName(g_Weapon,"dmg bonus vs buildings");
    if(mode==1 || mode==5 || mode==7 || mode==8)TF2_AddCondition(g_Blue,TFCond_Buffed,10.0,g_Blue);
    if(mode==2 || mode==6)TF2_AddCondition(g_Blue,TFCond_Kritzkrieged,10.0,g_Blue);
    if(mode==3)TF2_AddCondition(g_Blue,TFCond_CritCola,10.0,g_Blue);
    if(mode==5)Check(WeaponsAttrib_SetByName(g_Weapon,"minicrits become crits",1.0),"promotion attribute");
    if(mode==6)Check(WeaponsAttrib_SetByName(g_Weapon,"crits_become_minicrits",1.0),"demotion attribute");
    if(mode==7)Check(WeaponsAttrib_SetByName(g_Weapon,"dmg bonus vs buildings",2.0),"building modifier attribute");
    g_Target=CreateEntityByName(names[kind]);
    Check(g_Target>MaxClients,"real building entity");
    if(g_Target<=MaxClients) {Finish();return Plugin_Stop;}
    SetEntPropEnt(g_Target,Prop_Send,"m_hBuilder",g_Red);
    SetEntProp(g_Target,Prop_Send,"m_iTeamNum",2);SetEntProp(g_Target,Prop_Send,"m_iObjectType",types[kind]);
    SetEntProp(g_Target,Prop_Send,"m_iObjectMode",kind==3 ? 1 : 0);
    DispatchSpawn(g_Target);
    SetEntProp(g_Target,Prop_Send,"m_bPlacing",0);SetEntProp(g_Target,Prop_Send,"m_bBuilding",0);
    SetEntProp(g_Target,Prop_Send,"m_bDisabled",1);
    SetEntProp(g_Target,Prop_Data,"m_takedamage",2);SetEntProp(g_Target,Prop_Data,"m_lifeState",0);
    SetEntPropFloat(g_Target,Prop_Send,"m_flPercentageConstructed",1.0);
    SetVariantInt(2000);AcceptEntityInput(g_Target,"SetHealth");
    float target[3]={0.0,0.0,512.0};TeleportEntity(g_Target,target,NULL_VECTOR,NULL_VECTOR);
    g_DamageHook.HookEntity(Hook_Pre,g_Target,BeforeDamage);
    g_DamageHook.HookEntity(Hook_Post,g_Target,AfterDamage);
    float position[3]={0.0,0.0,512.0};position[0]=-distance;
    TeleportEntity(g_Blue,position,NULL_VECTOR,NULL_VECTOR);
    float eye[3],mins[3],maxs[3],delta[3],angles[3];
    GetClientEyePosition(g_Blue,eye);GetEntPropVector(g_Target,Prop_Send,"m_vecMins",mins);
    GetEntPropVector(g_Target,Prop_Send,"m_vecMaxs",maxs);
    for(int i;i<3;i++)target[i]+=(mins[i]+maxs[i])*0.5;
    MakeVectorFromPoints(eye,target,delta);GetVectorAngles(delta,angles);TeleportEntity(g_Blue,NULL_VECTOR,angles,NULL_VECTOR);
    SetEntPropEnt(g_Blue,Prop_Send,"m_hActiveWeapon",g_Weapon);
    SetEntProp(g_Weapon,Prop_Send,"m_iClip1",4);
    SetEntPropFloat(g_Weapon,Prop_Send,"m_flNextPrimaryAttack",0.0);
    SetEntPropFloat(g_Blue,Prop_Send,"m_flNextAttack",0.0);
    g_Pre=false;g_Post=false;g_Forward=false;g_RocketSeen=false;g_Shots=0;g_ForwardCalls=0;
    g_Rocket=INVALID_ENT_REFERENCE;g_Deadline=GetGameTime()+4.0;
    SDKCall(g_Attack,g_Weapon);
    if(GetEntProp(g_Weapon,Prop_Send,"m_iClip1")==4) {
        char classname[64];GetEntityClassname(g_Weapon,classname,sizeof(classname));
        LogMessage("[BuildingProjectileProbe] fire refused case=%d weapon=%s can_attack=%d alive=%d taunt=%d phase=%d no_attack=%d round=%d",g_Case,classname,SDKCall(g_CanAttack,g_Weapon),IsPlayerAlive(g_Blue),TF2_IsPlayerInCondition(g_Blue,TFCond_Taunting),TF2_IsPlayerInCondition(g_Blue,TFCond_Bonked),WeaponsAttrib_HookValueInt(0,"no_attack",g_Blue),GameRules_GetProp("m_iRoundState"));
    }
    CreateTimer(0.05,PollCase,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}
public void OnEntityCreated(int entity,const char[] classname) {
    if(g_Running && StrEqual(classname,"tf_projectile_rocket"))RequestFrame(ObserveRocket,EntIndexToEntRef(entity));
}
public void ObserveRocket(any ref) {
    int rocket=EntRefToEntIndex(ref);
    if(!g_Running || rocket<=MaxClients || !IsValidEntity(rocket))return;
    if(GetEntPropEnt(rocket,Prop_Send,"m_hOwnerEntity")!=g_Blue)return;
    g_Rocket=ref;g_RocketSeen=true;g_Shots++;
    Check(GetEntPropEnt(rocket,Prop_Send,"m_hLauncher")==g_Weapon,"stock rocket launcher attribution");
    bool critical=GetEntProp(rocket,Prop_Send,"m_bCritical")!=0;
    Check(critical==(Mode()==2 || Mode()==6),"Kritz decides actual rocket critical flag");
    if(Mode()==4)SetEntProp(rocket,Prop_Send,"m_iDeflected",1);
}
public MRESReturn BeforeDamage(int entity,DHookReturn result,DHookParam params) {
    if(!g_Running || entity!=g_Target)return MRES_Ignored;
    g_Pre=true;g_RawCrit=params.GetObjectVar(1,100,ObjectValueType_Int);
    g_RawType=params.GetObjectVar(1,60,ObjectValueType_Int);
    g_RawDamage=view_as<float>(params.GetObjectVar(1,48,ObjectValueType_Float));
    return MRES_Ignored;
}
public MRESReturn AfterDamage(int entity,DHookReturn result,DHookParam params) {
    if(!g_Running || entity!=g_Target)return MRES_Ignored;
    g_Post=true;
    Check(params.GetObjectVar(1,100,ObjectValueType_Int)==g_RawCrit,"engine caller crit unchanged");
    Check(FloatAbs(view_as<float>(params.GetObjectVar(1,48,ObjectValueType_Float))-g_RawDamage)<0.001,"engine caller base damage unchanged");
    Check(params.GetObjectVar(1,60,ObjectValueType_Int)==g_RawType,"engine caller flags unchanged");
    return MRES_Ignored;
}
public Action Weapons_OnBuildingTakeDamage(int entity,int attacker,int inflictor,float &damage,
    int type,int weapon,int custom,CritType crit) {
    if(!g_Running || entity!=g_Target)return Plugin_Continue;
    if(g_CaseGeneration!=g_InventoryGeneration)return Plugin_Continue;
    g_Forward=true;g_ForwardCalls++;g_ForwardBase=damage;g_Effective=view_as<int>(crit);
    Check(g_Pre,"raw input observed before native classification");
    Check(type==g_RawType,"scratch flags discarded");
    Check(attacker==g_Blue && weapon==g_Weapon,"real attacker and weapon preserved");
    Check(inflictor==EntRefToEntIndex(g_Rocket),"real projectile inflictor preserved");
    Action action=Plugin_Continue;
    if(Mode()!=8)action=BuildingCrit_ProductionPolicy(entity,attacker,inflictor,damage,type,weapon,custom,crit);
    g_PolicyDamage=damage;return action;
}
public Action Weapons_OnTakeDamageModifyRules(int victim,int &attacker,int &inflictor,
    float &damage,int &type,int &weapon,float force[3],float position[3],int custom,CritType &crit) {
    if(g_Running && victim==g_Target) {
        g_Leaks++;damage=17.0;crit=CritType_None;return Plugin_Changed;
    }
    if(g_Running && victim==g_Red)g_PlayerRules++;
    return Plugin_Continue;
}
public Action PollCase(Handle timer) {
    if(!g_Running)return Plugin_Stop;
    // First-round regeneration can replace a bot's weapon mid-flight. That is
    // an invalid test fixture, not a crit result: retry with the new inventory.
    if(g_CaseGeneration!=g_InventoryGeneration) {
        g_Retries++;PrintToServer("[BuildingProjectileProbe] inventory retry case=%d",g_Case);
        if(g_Target>MaxClients && IsValidEntity(g_Target))RemoveEntity(g_Target);g_Target=-1;
        int rocket=EntRefToEntIndex(g_Rocket);if(rocket>MaxClients && IsValidEntity(rocket))RemoveEntity(rocket);
        if(g_Retries>4) {Check(false,"inventory stabilized");Finish();}
        else CreateTimer(0.3,NextCase,_,TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    if(g_Post && g_Forward) {
        int crit=ExpectedCrit();float expected=crit==1 ? 121.5 : crit==2 ? 270.0 : 90.0;
        if(Mode()==8)expected=90.0;
        Check(g_RocketSeen && g_Shots==1,"one actual fired rocket");
        Check(g_RawCrit==0,"real projectile damage starts CRIT_NONE");
        Check(g_Effective==crit,"game rules derive effective None/Mini/Full");
        Check(FloatAbs(g_RawDamage-90.0)<0.01 && FloatAbs(g_ForwardBase-90.0)<0.01,"90 base retained without player range variance");
        Check(FloatAbs(g_PolicyDamage-expected)<0.01,"one production crit multiplier");
        float healthDamage=expected*(Mode()==7 ? 2.0 : 1.0);
        int actual=2000-GetEntProp(g_Target,Prop_Send,"m_iHealth");
        if(actual!=RoundToFloor(healthDamage))PrintToServer("[BuildingProjectileProbe] mismatch expected=%.2f health_loss=%d raw=%.2f effective=%d",healthDamage,actual,g_RawDamage,g_Effective);
        Check(actual==RoundToFloor(healthDamage),"stock building health/modifier result");
        Check(g_ForwardCalls==1,"one building forward per rocket");
        Check(g_Leaks==0,"no player rules forward from classification probe");
        PrintToServer("[BuildingProjectileProbe] case=%d kind=%d mode=%d distance=%d raw_crit=%d effective=%d base=%.1f policy=%.1f health_loss=%d",g_Case,Kind(),Mode(),(g_Case%2)==0?96:1024,g_RawCrit,g_Effective,g_ForwardBase,g_PolicyDamage,actual);
        LogMessage("[BuildingProjectileProbe] case=%d kind=%d mode=%d distance=%d raw_crit=%d effective=%d base=%.1f policy=%.1f health_loss=%d",g_Case,Kind(),Mode(),(g_Case%2)==0?96:1024,g_RawCrit,g_Effective,g_ForwardBase,g_PolicyDamage,actual);
        RemoveEntity(g_Target);g_Target=-1;g_Case++;CreateTimer(0.05,NextCase,_,TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    if(GetGameTime()>g_Deadline) {
        PrintToServer("[BuildingProjectileProbe] timeout shots=%d pre=%d post=%d forward=%d",g_Shots,g_Pre,g_Post,g_Forward);
        PrintToServer("[BuildingProjectileProbe] fixture alive=%d team=%d class=%d round=%d clip=%d owner=%d active=%d next=%.2f now=%.2f",IsPlayerAlive(g_Blue),GetClientTeam(g_Blue),view_as<int>(TF2_GetPlayerClass(g_Blue)),GameRules_GetProp("m_iRoundState"),GetEntProp(g_Weapon,Prop_Send,"m_iClip1"),GetEntPropEnt(g_Weapon,Prop_Send,"m_hOwnerEntity"),GetEntPropEnt(g_Blue,Prop_Send,"m_hActiveWeapon"),GetEntPropFloat(g_Weapon,Prop_Send,"m_flNextPrimaryAttack"),GetGameTime());
        Check(false,"real rocket reached building before timeout");
        Finish();return Plugin_Stop;
    }
    return Plugin_Continue;
}
void Finish() {
    if(!g_Running)return;
    if(g_Target>MaxClients && IsValidEntity(g_Target))RemoveEntity(g_Target);
    int rocket=EntRefToEntIndex(g_Rocket);if(rocket>MaxClients && IsValidEntity(rocket))RemoveEntity(rocket);
    if(g_Red>0 && IsClientInGame(g_Red) && g_Weapon>MaxClients && IsValidEntity(g_Weapon)) {
        SetEntProp(g_Red,Prop_Data,"m_takedamage",2);SetEntityHealth(g_Red,125);
        TF2_RemoveCondition(g_Blue,TFCond_Buffed);TF2_RemoveCondition(g_Blue,TFCond_Kritzkrieged);TF2_RemoveCondition(g_Blue,TFCond_CritCola);
        SDKHooks_TakeDamage(g_Red,g_Blue,g_Blue,5.0,DMG_GENERIC,g_Weapon);
        Check(g_PlayerRules>0,"normal player rules forward still dispatched");
    }
    PrintToServer("[BuildingProjectileProbe] cases=%d checks=%d failures=%d rules_leaks=%d",g_Case,g_Checks,g_Failures,g_Leaks);
    g_Running=false;
    if(g_Red>0 && IsClientConnected(g_Red))KickClient(g_Red,"isolated projectile test complete");
    if(g_Blue>0 && IsClientConnected(g_Blue))KickClient(g_Blue,"isolated projectile test complete");
    g_Red=0;g_Blue=0;g_Target=-1;
}
public void OnPluginEnd() {
    g_Running=false;
    if(g_Target>MaxClients && IsValidEntity(g_Target))RemoveEntity(g_Target);
    int rocket=EntRefToEntIndex(g_Rocket);if(rocket>MaxClients && IsValidEntity(rocket))RemoveEntity(rocket);
    if(g_Red>0 && IsClientConnected(g_Red))KickClient(g_Red,"isolated probe unloaded");
    if(g_Blue>0 && IsClientConnected(g_Blue))KickClient(g_Blue,"isolated probe unloaded");
}
