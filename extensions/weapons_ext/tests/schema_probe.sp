/** Isolated schema regression probe. Never load on a production server. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <weapons_schema>
#include <weapons_attributes>
int g_Checks, g_Failures, g_AutoID, g_Bot;
bool g_Registered;
public Plugin myinfo = {name="Weapons Schema Isolated Probe",author="Hombre",version="1.0"};
public void OnPluginStart() { RegAdminCmd("sm_weapons_schema_probe",Probe,ADMFLAG_ROOT); }
void Check(bool condition,const char[] label) {
    g_Checks++;
    if(!condition) g_Failures++;
    PrintToServer("[WeaponsSchemaProbe] %s %s",condition?"PASS":"FAIL",label);
}
public Action Probe(int client,int args) {
    if(client || g_Bot) return Plugin_Handled;
    // This fixture deliberately renames and reallocates definitions. Start a
    // fresh isolated process for another mutation run; map changes test replay.
    if(g_Registered) {
        PrintToServer("[WeaponsSchemaProbe] Already completed; use map changes to test replay");
        return Plugin_Handled;
    }
    for(int other=1;other<=MaxClients;other++)
        if(IsClientConnected(other) && !IsFakeClient(other)) return Plugin_Handled;
    g_Checks=0; g_Failures=0;
    g_Bot=CreateFakeClient("Schema isolated test");
    if(!g_Bot) { Check(false,"create test player"); return Plugin_Handled; }
    ChangeClientTeam(g_Bot,2); TF2_SetPlayerClass(g_Bot,TFClass_Engineer); TF2_RespawnPlayer(g_Bot);
    CreateTimer(0.2,Run,GetClientUserId(g_Bot),TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}
int ReadID(int weapon,const char[] name) {
    if(!WeaponsAttrib_SetByName(weapon,name,0.25)) return -1;
    Address attribute=WeaponsAttrib_GetByName(weapon,name);
    int id=attribute==Address_Null?-1:WeaponsAttrib_GetDefIndex(attribute);
    WeaponsAttrib_RemoveByName(weapon,name);
    return id;
}
void FloatDefinition(WeaponsSchemaAttribute attribute,const char[] name) {
    attribute.Clear(); attribute.SetName(name); attribute.SetClass("weapons_schema_probe_add");
    attribute.SetDescriptionFormat("value_is_additive");
}
public Action Run(Handle timer,int userid) {
    int bot=GetClientOfUserId(userid);
    if(!bot || bot!=g_Bot) return Plugin_Stop;
    int weapon=GetPlayerWeaponSlot(bot,0);
    Check(weapon>MaxClients,"real engine inventory");
    WeaponsSchemaAttribute attribute=new WeaponsSchemaAttribute();
    Check(attribute!=null,"one canonical handle owner");
    Check(!attribute.Register(),"empty definition rejected");
    FloatDefinition(attribute,"schema probe auto");
    Check(attribute.Register(),"automatic definition registered");
    Check(WeaponsAttrib_IsValidAttributeName("schema probe auto"),"October secondary name index");
    int autoID=ReadID(weapon,"schema probe auto");
    Check(autoID>=4000,"automatic ID range");
    Check(attribute.Register() && ReadID(weapon,"schema probe auto")==autoID,"repeat registration stable ID");
    attribute.SetName("SCHEMA PROBE AUTO");
    Check(attribute.Register() && ReadID(weapon,"SCHEMA PROBE AUTO")==autoID,"case-insensitive ID stability");
    attribute.SetName("schema probe auto");
    Check(attribute.Register(),"restore spelling");
    WeaponsAttrib_SetByName(weapon,"schema probe auto",0.5);
    Check(FloatAbs(WeaponsAttrib_HookValueFloat(1.0,"weapons_schema_probe_add",weapon)-1.5)<0.001,"engine attribute class hook");
    WeaponsAttrib_RemoveByName(weapon,"schema probe auto");
    Check(attribute.Import("schema probe auto"),"import engine-owned definition clone");
    attribute.SetName("schema probe renamed");
    Check(attribute.Register(),"explicit ID rename");
    Check(!WeaponsAttrib_IsValidAttributeName("schema probe auto"),"old name and cached pointer invalidated");
    Check(ReadID(weapon,"schema probe renamed")==autoID,"rename preserves ID");
    FloatDefinition(attribute,"schema probe auto");
    Check(attribute.Register() && ReadID(weapon,"schema probe auto")!=autoID,"renamed auto slot is not stolen");
    g_AutoID=ReadID(weapon,"schema probe auto");
    FloatDefinition(attribute,"schema probe explicit"); attribute.SetDefIndex(62000);
    Check(attribute.Register() && ReadID(weapon,"schema probe explicit")==62000,"explicit definition index");
    attribute.SetDefIndex(62001);
    Check(!attribute.Register(),"duplicate name at another ID rejected");
    FloatDefinition(attribute,"schema probe valve id"); attribute.SetDefIndex(2);
    Check(!attribute.Register(),"Valve index protected");
    FloatDefinition(attribute,"damage bonus");
    Check(!attribute.Register(),"Valve name protected");
    Check(ReadID(weapon,"damage bonus")==2,"Valve definition intact");
    attribute.Clear(); attribute.SetClass("schema_probe_default_name");
    attribute.SetDescriptionFormat("value_is_additive");
    Check(attribute.Register() && WeaponsAttrib_IsValidAttributeName("schema_probe_default_name"),"missing name defaults to class");
    Check(!attribute.Import("schema probe missing"),"missing import rejected");
    Check(attribute.Import("cosmetic taunt sound"),"import Valve string definition");
    attribute.ClearDefIndex(); attribute.SetName("schema probe string"); attribute.SetClass("schema_probe_string");
    Check(attribute.Register(),"new string attribute registered");
    Check(WeaponsAttrib_SetFromStringValue(weapon,"schema probe string","schema-probe-value"),"injected string type conversion");
    Address value=WeaponsAttrib_GetByName(weapon,"schema probe string");
    char text[128];
    WeaponsAttrib_UnsafeGetStringValue(view_as<any>(WeaponsAttrib_GetValue(value)),text,sizeof(text));
    Check(StrEqual(text,"schema-probe-value"),"injected string value roundtrip");
    WeaponsAttrib_RemoveByName(weapon,"schema probe string");
    // Warm pointers, then force substantial tree growth. No production schemas.
    Check(WeaponsAttrib_IsValidAttributeName("schema probe auto"),"cache warm before schema growth");
    float started=GetEngineTime(); bool inserted=true;
    for(int i=0;i<512;i++) {
        char name[64]; Format(name,sizeof(name),"schema probe growth %d",i);
        FloatDefinition(attribute,name);
        if(!attribute.Register()) inserted=false;
    }
    Check(inserted,"512 schema insertions");
    Check(ReadID(weapon,"schema probe auto")==g_AutoID,"warm cache remains safe after map growth");
    PrintToServer("[WeaponsSchemaProbe] growth512_ms=%.3f",(GetEngineTime()-started)*1000.0);
    Handle clone=CloneHandle(attribute);
    delete attribute;
    WeaponsSchemaAttribute cloned=view_as<WeaponsSchemaAttribute>(clone);
    Check(cloned.Import("schema probe auto"),"clone survives original handle deletion");
    cloned.Clear(); Check(!cloned.Register(),"clear resets all properties"); delete cloned;
    g_Registered=true;
    PrintToServer("[WeaponsSchemaProbe] checks=%d failures=%d",g_Checks,g_Failures);
    KickClient(bot,"isolated schema test complete"); g_Bot=0;
    return Plugin_Stop;
}
public void OnMapStart() {
    if(!g_Registered) return;
    Check(WeaponsAttrib_IsValidAttributeName("schema probe auto"),"native reinstall before plugin OnMapStart");
    Check(WeaponsAttrib_IsValidAttributeName("schema probe renamed"),"renamed registry survives map change");
    Check(WeaponsAttrib_IsValidAttributeName("schema probe growth 511"),"all registered definitions survive map change");
    Check(!WeaponsAttrib_IsValidAttributeName("schema probe valve id"),"rejected registration absent after map change");
    PrintToServer("[WeaponsSchemaProbe] post-map checks=%d failures=%d",g_Checks,g_Failures);
}
