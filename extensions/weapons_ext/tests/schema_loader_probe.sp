/** Isolated integration check for Weapons' SMC configuration loader. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <weapons_attributes>
#include <weapons/econ_attributes.sp>
public Plugin myinfo = {name="Weapons Schema Loader Probe",author="Hombre",version="1.0"};
public void OnPluginStart() { WeaponsEcon_OnPluginStart(); }
public void OnMapStart() {
    WeaponsEcon_OnMapStart();
    bool okay=WeaponsAttrib_IsValidAttributeName("schema loader auto")
        && WeaponsAttrib_IsValidAttributeName("schema loader explicit");
    PrintToServer("[WeaponsSchemaLoaderProbe] configured_definitions=%s",okay?"PASS":"FAIL");
}
