#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2>
#include <tf_econ_data>

public Plugin myinfo =
{
    name = "TF2 Econ gamedata compatibility probe",
    author = "Hombre",
    description = "Read-only checks for schema offsets after TF2 updates",
    version = "1.0.0"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_econ_gamedata_probe", Probe, ADMFLAG_ROOT);
}

public Action Probe(int client, int args)
{
    int count = TF2Econ_GetLoadoutSlotCount();
    if (count <= 0 || count > 64)
    {
        ReplyToCommand(client, "[EconProbe] FAIL: implausible slot count %d", count);
        return Plugin_Handled;
    }
    char name[64];
    int namedSlots;
    int reservedSlots;
    for (int i = 0; i < count; i++)
    {
        name[0] = '\0';
        if (!TF2Econ_TranslateLoadoutSlotIndexToName(i, name, sizeof(name)))
        {
            // The schema also contains intentionally unnamed reserved slots.
            reservedSlots++;
            continue;
        }
        namedSlots++;
        // Valve's table contains aliases (e.g. duplicate "action" slots).
        // Name lookup correctly returns the first matching index.
        int mapped = TF2Econ_TranslateLoadoutSlotNameToIndex(name);
        char canonical[64];
        if (mapped < 0 || mapped > i
            || !TF2Econ_TranslateLoadoutSlotIndexToName(mapped, canonical, sizeof(canonical))
            || !StrEqual(name, canonical))
        {
            ReplyToCommand(client, "[EconProbe] FAIL: slot name round-trip %d", i);
            return Plugin_Handled;
        }
    }
    if (namedSlots < 9
        || TF2Econ_TranslateLoadoutSlotNameToIndex("primary") != 0
        || TF2Econ_TranslateLoadoutSlotNameToIndex("secondary") != 1
        || TF2Econ_TranslateLoadoutSlotNameToIndex("melee") != 2
        || !TF2Econ_GetItemClassName(13, name, sizeof(name))
        || !StrEqual(name, "tf_weapon_scattergun")
        || TF2Econ_GetItemLoadoutSlot(13, TFClass_Scout) != 0)
    {
        ReplyToCommand(client, "[EconProbe] FAIL: known slot/item definition");
        return Plugin_Handled;
    }

    StringMap regions = TF2Econ_GetEquipRegionGroups();
    StringMapSnapshot keys = regions.Snapshot();
    int regionCount = keys.Length;
    delete keys;
    delete regions;
    if (regionCount <= 0)
    {
        ReplyToCommand(client, "[EconProbe] FAIL: empty equip-region list");
        return Plugin_Handled;
    }
    for (int set = view_as<int>(ParticleSet_All);
        set <= view_as<int>(ParticleSet_TauntUnusualEffects); set++)
    {
        ArrayList particles = TF2Econ_GetParticleAttributeList(view_as<TFEconParticleSet>(set));
        int particleCount = particles.Length;
        if (particleCount <= 0
            || !TF2Econ_GetParticleAttributeSystemName(particles.Get(0), name, sizeof(name)))
        {
            delete particles;
            ReplyToCommand(client, "[EconProbe] FAIL: particle set %d", set);
            return Plugin_Handled;
        }
        delete particles;
        ReplyToCommand(client, "[EconProbe] PASS: particle set %d count=%d", set, particleCount);
    }
    ReplyToCommand(client, "[EconProbe] PASS: %d named/%d reserved slots, known item, %d equip regions",
        namedSlots, reservedSlots, regionCount);
    return Plugin_Handled;
}
