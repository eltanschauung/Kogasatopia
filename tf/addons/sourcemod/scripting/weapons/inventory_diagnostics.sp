// Observe the complete engine item-creation path, not just TF2Items' post hook.
// Never alter parameters, return values, attributes, or item eligibility.
DynamicDetour g_WeaponsItemDiagnosticDetour;
ConVar g_WeaponsInventoryDiagnostics;
int g_WeaponsItemDiagnosticProfiles[16], g_WeaponsItemDiagnosticDepth;

#include "inventory_stages.sp"

void WeaponsInventoryDiagnostics_Init()
{
    g_WeaponsInventoryDiagnostics = CreateConVar("sm_weapons_inventory_diagnostics", "1",
        "Measure complete inventory item creation for CheckLag; read-only diagnostics.", _, true, 0.0, true, 1.0);
    GameData data = new GameData("weapons.inventory_diagnostics");
    if (data != null)
    {
        g_WeaponsItemDiagnosticDetour = DynamicDetour.FromConf(data, "CTFPlayer::GiveNamedItem");
        WeaponsInventoryStages_Init(data);
        delete data;
    }
    if (g_WeaponsItemDiagnosticDetour == null
        || !g_WeaponsItemDiagnosticDetour.Enable(Hook_Pre, WeaponsItemDiagnostic_Pre)
        || !g_WeaponsItemDiagnosticDetour.Enable(Hook_Post, WeaponsItemDiagnostic_Post))
    {
        WeaponsInventoryDiagnostics_Shutdown();
        // Optional diagnostics must not take down the custom-weapons plugin.
        LogError("Complete GiveNamedItem diagnostics unavailable; check weapons.inventory_diagnostics gamedata.");
    }
}

void WeaponsInventoryDiagnostics_Shutdown()
{
    WeaponsInventoryStages_Shutdown();
    if (g_WeaponsItemDiagnosticDetour != null)
    {
        g_WeaponsItemDiagnosticDetour.Disable(Hook_Pre, WeaponsItemDiagnostic_Pre);
        g_WeaponsItemDiagnosticDetour.Disable(Hook_Post, WeaponsItemDiagnostic_Post);
        delete g_WeaponsItemDiagnosticDetour;
    }
    g_WeaponsItemDiagnosticDepth = 0;
}

public MRESReturn WeaponsItemDiagnostic_Pre(int client, DHookReturn result, DHookParam params)
{
    int depth = g_WeaponsItemDiagnosticDepth++;
    if (depth < sizeof(g_WeaponsItemDiagnosticProfiles))
        g_WeaponsItemDiagnosticProfiles[depth] = g_WeaponsInventoryDiagnostics.BoolValue ? KogasaPerfBegin() : -1;
    return MRES_Ignored;
}

public MRESReturn WeaponsItemDiagnostic_Post(int client, DHookReturn result, DHookParam params)
{
    if (g_WeaponsItemDiagnosticDepth <= 0) return MRES_Ignored;
    int depth = --g_WeaponsItemDiagnosticDepth;
    if (depth >= sizeof(g_WeaponsItemDiagnosticProfiles)) return MRES_Ignored;
    int profile = g_WeaponsItemDiagnosticProfiles[depth];
    if (profile >= 0)
    {
        char name[40] = "unknown", scope[72];
        if (!params.IsNull(1)) params.GetString(1, name, sizeof(name));
        FormatEx(scope, sizeof(scope), "GiveNamedItem/%s(engine+hooks)", name);
        WeaponsPerf_EndClient(profile, scope, client);
    }
    return MRES_Ignored;
}
