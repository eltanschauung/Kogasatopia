// Tests the actual optional diagnostic module. Never records fake DB incidents.
// Engine exercise is restricted to the isolated diagnostic lab, with no humans.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <dhooks>
ConVar g_WeaponsInventoryDiagnostics;
int g_WeaponsInventoryProfileDepth;
int checks, failures, records, sequence, clientBeingTested;
char lastScope[72];
int KogasaPerfBegin() { return ++sequence; }
void WeaponsPerf_EndClient(int profile, const char[] scope, int client, const char[] detail = "")
{
    #pragma unused profile
    #pragma unused client
    #pragma unused detail
    records++;
    strcopy(lastScope, sizeof(lastScope), scope);
}
#include "weapons/inventory_stages.sp"
public Plugin myinfo = {name="Inventory stages diagnostic probe",author="Hombre",version="1.0.0"};

void Check(bool condition, const char[] label)
{
    checks++;
    if (!condition) { failures++; PrintToServer("[InventoryStagesProbe] FAIL: %s", label); }
}
public void OnPluginStart()
{
    g_WeaponsInventoryDiagnostics = CreateConVar("sm_inventory_stages_probe_enable", "1");
    RegAdminCmd("sm_inventory_stages_probe", Command_Probe, ADMFLAG_ROOT);
}
public void OnPluginEnd()
{
    WeaponsInventoryStages_Shutdown();
    if (clientBeingTested > 0 && IsClientConnected(clientBeingTested))
        KickClientEx(clientBeingTested, "Inventory stages probe complete");
}
public Action Command_Probe(int client, int args)
{
    checks=0; failures=0; records=0;
    g_WeaponsInventoryProfileDepth=0;
    g_WeaponsInventoryDiagnostics.BoolValue=true;
    WeaponsInventoryStages_Begin(InventoryStage_ValidateWeapons, 0);
    Check(g_WeaponsInventoryStageProfiles[InventoryStage_ValidateWeapons][0] == -1,
        "outside inventory not profiled");
    WeaponsInventoryStages_End(InventoryStage_ValidateWeapons);
    Check(records == 0, "outside inventory no telemetry");
    g_WeaponsInventoryProfileDepth=1;
    g_WeaponsInventoryDiagnostics.BoolValue=false;
    WeaponsInventoryStages_Begin(InventoryStage_ValidateWeapons, 0);
    WeaponsInventoryStages_End(InventoryStage_ValidateWeapons);
    Check(records == 0, "disabled no telemetry");
    g_WeaponsInventoryDiagnostics.BoolValue=true;
    for (int stage=0; stage<view_as<int>(InventoryStage_Count); stage++)
    {
        int before=records;
        WeaponsInventoryStages_Begin(view_as<WeaponsInventoryStage>(stage), 0);
        int first=g_WeaponsInventoryStageProfiles[stage][0];
        WeaponsInventoryStages_Begin(view_as<WeaponsInventoryStage>(stage), 0);
        Check(g_WeaponsInventoryStageProfiles[stage][1] != first, "reentrant profile independent");
        WeaponsInventoryStages_End(view_as<WeaponsInventoryStage>(stage));
        Check(g_WeaponsInventoryStageDepth[stage] == 1, "inner scope restores parent");
        WeaponsInventoryStages_End(view_as<WeaponsInventoryStage>(stage));
        Check(records == before+2 && g_WeaponsInventoryStageDepth[stage] == 0,
            "paired stage produces two traces");
        Check(StrContains(lastScope, "(engine+hooks)") >= 0, "scope explicitly inclusive");
        for (int depth=0; depth<WEAPONS_INVENTORY_STAGE_DEPTH+3; depth++)
            WeaponsInventoryStages_Begin(view_as<WeaponsInventoryStage>(stage), 0);
        Check(g_WeaponsInventoryStageDepth[stage] == WEAPONS_INVENTORY_STAGE_DEPTH+3,
            "overflow remains balanced without array access");
        for (int depth=0; depth<WEAPONS_INVENTORY_STAGE_DEPTH+3; depth++)
            WeaponsInventoryStages_End(view_as<WeaponsInventoryStage>(stage));
        Check(g_WeaponsInventoryStageDepth[stage] == 0, "overflow unwinds safely");
        WeaponsInventoryStages_End(view_as<WeaponsInventoryStage>(stage));
        Check(g_WeaponsInventoryStageDepth[stage] == 0, "unpaired end harmless");
    }

    if (args > 0)
    {
        if (client != 0 || !FileExists("addons/sourcemod/data/deploy_finished_lab.marker"))
        {
            Check(false, "engine test requires private lab marker and server console");
        }
        else
        {
            bool human;
            for (int target=1; target<=MaxClients; target++)
                if (IsClientInGame(target) && !IsFakeClient(target)) human=true;
            Check(!human, "engine test no humans");
            if (!human)
            {
                GameData data=new GameData("weapons.games");
                WeaponsInventoryStages_Init(data);
                delete data;
                for (int stage=0; stage<view_as<int>(InventoryStage_Count); stage++)
                    Check(g_WeaponsInventoryStages[stage] != null, "stage ABI resolved and enabled");
                clientBeingTested=CreateFakeClient("InventoryStagesProbe");
                Check(clientBeingTested > 0, "disposable fake client created");
                if (clientBeingTested > 0)
                {
                    ChangeClientTeam(clientBeingTested, 3);
                    int before=records;
                    TFClassType classes[]={TFClass_Scout,TFClass_Engineer,TFClass_Spy,TFClass_Pyro};
                    for (int c=0; c<sizeof(classes); c++)
                    {
                        TF2_SetPlayerClass(clientBeingTested, classes[c], false, true);
                        TF2_RespawnPlayer(clientBeingTested);
                        TF2_RegeneratePlayer(clientBeingTested);
                    }
                    Check(records > before, "real inventory stages executed through engine");
                    for (int stage=0; stage<view_as<int>(InventoryStage_Count); stage++)
                        Check(g_WeaponsInventoryStageDepth[stage] == 0, "engine callbacks balanced");
                    KickClientEx(clientBeingTested, "Inventory stages probe complete");
                    clientBeingTested=0;
                }
            }
        }
    }
    WeaponsInventoryStages_Shutdown();
    for (int stage=0; stage<view_as<int>(InventoryStage_Count); stage++)
        Check(g_WeaponsInventoryStages[stage] == null, "shutdown releases optional detours");
    g_WeaponsInventoryProfileDepth=0;
    ReplyToCommand(client, "[InventoryStagesProbe] %d checks; %d failures; %d in-memory stage records",
        checks, failures, records);
    return Plugin_Handled;
}
