#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include "../../tf/addons/sourcemod/scripting/include/client_validation.inc"
#include "../../tf/addons/sourcemod/scripting/include/tf2_classes.inc"

#define MAX_HATS 3
enum struct HatConfig
{
    char id[64];
    char model[PLATFORM_MAX_PATH];
    char particleEffect[128];
    char particleFile[PLATFORM_MAX_PATH];
    char particleAttachment[64];
}
HatConfig g_Hats[MAX_HATS];
int g_iHatCount = 2;
int g_iHatRef[MAXPLAYERS + 1][MAX_HATS];
int g_iHatEquippedClass[MAXPLAYERS + 1][MAX_HATS];
bool g_ProbeHidden;
int g_ProbeModelRef = INVALID_ENT_REFERENCE;
int g_ProbeClientUserId;
int g_ProbeCleanupFrames;

bool IsHatEnabled(int index) { return index >= 0 && index < g_iHatCount; }
bool IsHatIndexValid(int index) { return IsHatEnabled(index); }
bool IsClassAllowedForHat(int index, TFClassType cls)
{
    return IsHatEnabled(index) && cls > TFClass_Unknown && cls <= TFClass_Engineer;
}
void RemoveHat(int client, int index)
{
    if (client <= 0 || client > MaxClients || index >= MAX_HATS)
        return;
    int first = index < 0 ? 0 : index;
    int last = index < 0 ? g_iHatCount : index + 1;
    for (int i = first; i < last; i++)
    {
        int entity = EntRefToEntIndex(g_iHatRef[client][i]);
        if (entity > MaxClients && IsValidEntity(entity))
            CustomHats_RemoveWearableParticle(entity);
    }
}
Action WeaponsHatVisibility_OnTransmit(int entity, int viewer)
{
    return entity > MaxClients && viewer > 0 && g_ProbeHidden ? Plugin_Handled : Plugin_Continue;
}
#include "../../tf/addons/sourcemod/scripting/weapons/hats/class_variants.sp"
#include "../../tf/addons/sourcemod/scripting/weapons/hats/particles.sp"

public Plugin myinfo =
{
    name = "Particle hat regression probe",
    author = "Kogasatopia",
    description = "Isolated class-variant, particle and cleanup checks",
    version = "2.1"
};

static void Require(bool value, const char[] message)
{
    if (!value)
        SetFailState("FAIL: %s", message);
}

static void ReadHat(KeyValues config, int index)
{
    config.GetSectionName(g_Hats[index].id, sizeof(g_Hats[].id));
    config.GetString("model", g_Hats[index].model, sizeof(g_Hats[].model));
    if (config.JumpToKey("particle"))
    {
        config.GetString("effect", g_Hats[index].particleEffect, sizeof(g_Hats[].particleEffect));
        config.GetString("pcf", g_Hats[index].particleFile, sizeof(g_Hats[].particleFile));
        config.GetString("attachment", g_Hats[index].particleAttachment, sizeof(g_Hats[].particleAttachment));
        config.GoBack();
    }
    CustomHats_LoadClassVariants(config, index);
}

public void OnPluginStart()
{
    KeyValues config = new KeyValues("CustomHats");
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/custom_hats.cfg");
    Require(config.ImportFromFile(path) && config.JumpToKey("hats"), "live config parse");
    Require(config.JumpToKey("sora_procuration"), "Procuration config");
    ReadHat(config, 0);
    config.GoBack();
    Require(config.JumpToKey("tsurugi_halo"), "Tsurugi config");
    ReadHat(config, 1);
    delete config;

    config = new KeyValues("fixture");
    Require(config.ImportFromString(
        "\"fixture\" { \"model\" \"models/base.mdl\" \"particle\" { \"effect\" \"base_{class}\" \"pcf\" \"particles/base.pcf\" \"attachment\" \"halo_{class}\" } \"scout\" { \"model\" \"models/scout.mdl\" \"body\" \"7\" \"particle\" { \"effect\" \"explicit_scout\" } } }"),
        "override fixture parse");
    ReadHat(config, 2);
    delete config;
    Require(StrEqual(g_HatClassVariants[2][1].model, "models/scout.mdl"), "class model override");
    Require(g_HatClassVariants[2][1].body == 7, "class body override");
    Require(StrEqual(g_HatClassVariants[2][1].particleEffect, "explicit_scout"), "class effect override");
    Require(StrEqual(g_HatClassVariants[2][1].particleFile, "particles/base.pcf"), "partial particle inheritance");
    Require(StrEqual(g_HatClassVariants[2][1].particleAttachment, "halo_scout"), "attachment template");
    Require(StrEqual(g_HatClassVariants[2][3].model, "models/base.mdl"), "base model inheritance");
    Require(StrEqual(g_HatClassVariants[2][4].particleEffect, "base_demo"), "Demoman template");

    CustomHats_InitParticles();
    Require(g_hHatParseParticleMap != null, "native map particle loader");
    ArrayList revisionFiles = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    revisionFiles.PushString("!particles/map_native.pcf");
    revisionFiles.PushString("particles/ba_tsurugi_blood.pcf");
    revisionFiles.PushString("!particles/procuration_v4.pcf");
    Require(CustomHats_ReserveParticleRevisions(revisionFiles), "reserve revisions");
    Require(revisionFiles.Length == 33, "32 slots plus native PCF, legacy entries retired");
    Require(!CustomHats_ReserveParticleRevisions(revisionFiles), "idempotent revision reservation");
    delete revisionFiles;
    CustomHats_PrecacheParticles();
    int downloads = FindStringTable("downloadables");
    Require(FindStringIndex(downloads, "particles/kogasa_particles_r01.pcf") != INVALID_STRING_INDEX,
        "published revision downloaded");
    for (int revision = 2; revision <= HAT_PARTICLE_REVISION_COUNT; revision++)
    {
        char revisionPath[PLATFORM_MAX_PATH];
        Format(revisionPath, sizeof(revisionPath), "particles/kogasa_particles_r%02d.pcf", revision);
        if (!FileExists(revisionPath, true))
            Require(FindStringIndex(downloads, revisionPath) == INVALID_STRING_INDEX,
                "missing revision not downloaded");
    }
    LogMessage("PASS: stable 32-slot manifests, native entries preserved, no missing-file downloads.");
    PrecacheModel(g_Hats[0].model, true);
    PrecacheModel(g_Hats[1].model, true);

    char probeModel[PLATFORM_MAX_PATH];
    ConVar modelOverride = CreateConVar("sm_particle_hat_probe_model", g_Hats[0].model,
        "Optional uncached model path for isolated late-install diagnostics.");
    modelOverride.GetString(probeModel, sizeof(probeModel));
    Require(FileExists(probeModel, true), "test model exists");
    PrecacheModel(probeModel, true);
    int previous = -1;
    while ((previous = FindEntityByClassname(previous, "prop_dynamic")) != -1)
    {
        char model[PLATFORM_MAX_PATH];
        GetEntPropString(previous, Prop_Data, "m_ModelName", model, sizeof(model));
        if (StrEqual(model, probeModel) || StrEqual(model, g_Hats[0].model))
            RemoveEntity(previous);
    }
    int prop = CreateEntityByName("prop_dynamic");
    Require(prop > MaxClients, "test model entity");
    DispatchKeyValue(prop, "model", probeModel);
    DispatchSpawn(prop);
    g_ProbeModelRef = EntIndexToEntRef(prop);
    SDKHook(prop, SDKHook_SetTransmit, Probe_BlockTransmit);
    for (int cls = 1; cls <= 9; cls++)
    {
        Require(g_HatClassVariants[0][cls].body == cls - 1, "nine body values");
        Require(g_HatClassVariants[0][cls].particleReady, "nine PCF effects registered");
        Require(!g_HatClassVariants[0][cls].particleInModel, "Procuration requires emitter");
        SetEntProp(prop, Prop_Send, "m_nBody", g_HatClassVariants[0][cls].body);
        Require(GetEntProp(prop, Prop_Send, "m_nBody") == cls - 1, "body applied");
        int attachment = LookupEntityAttachment(prop, g_HatClassVariants[0][cls].particleAttachment);
        LogMessage("Class %d effect=%s attachment=%s lookup=%d modelIndex=%d", cls,
            g_HatClassVariants[0][cls].particleEffect, g_HatClassVariants[0][cls].particleAttachment,
            attachment, GetEntProp(prop, Prop_Send, "m_nModelIndex"));
        Require(attachment > 0,
            "nine halo attachments");
        strcopy(g_HatClassVariants[0][cls].model, sizeof(g_HatClassVariants[][].model), probeModel);
        Require(CustomHats_VariantMatchesWearable(prop, 0, cls), "wearable variant identity");
    }
    Require(g_HatClassVariants[1][1].particleReady && g_HatClassVariants[1][1].particleInModel,
        "unchanged Tsurugi embedded particle");
    Require(!CustomHats_PCFHasEffect(g_Hats[0].particleFile, "procuration_v4"), "wrong effect rejected");
    LogMessage("PASS: class model/body/effect overrides, inheritance, all 9 effects/attachments, Tsurugi compatibility.");

    int owner;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsInGame(client) && IsPlayerAlive(client)
            && !TF2_IsPlayerInCondition(client, TFCond_Cloaked)
            && !TF2_IsPlayerInCondition(client, TFCond_Disguised)
            && !TF2_IsPlayerInCondition(client, TFCond_Disguising)
            && !TF2_IsPlayerInCondition(client, TFCond_Stealthed)
            && !TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade))
        {
            owner = client;
            break;
        }
    }
    if (owner == 0)
    {
        owner = CreateFakeClient("Procuration regression probe");
        Require(owner > 0, "isolated test client");
        g_ProbeClientUserId = GetClientUserId(owner);
        ChangeClientTeam(owner, 2);
        TF2_SetPlayerClass(owner, TFClass_Scout);
        TF2_RespawnPlayer(owner);
        Require(IsPlayerAlive(owner), "test client alive");
    }
    int cls = view_as<int>(TF2_GetPlayerClass(owner));
    g_HatClassVariants[0][cls].particleInModel = true;
    CustomHats_AttachParticle(owner, prop, 0);
    Require(g_iHatParticleRef[prop] == INVALID_ENT_REFERENCE, "embedded duplicate avoided");
    g_HatClassVariants[0][cls].particleInModel = false;
    CustomHats_AttachParticle(owner, prop, 0);
    int particle = EntRefToEntIndex(g_iHatParticleRef[prop]);
    Require(particle > MaxClients && IsValidEntity(particle), "wearable emitter created");
    SDKHook(particle, SDKHook_SetTransmit, Probe_BlockTransmit);
    Require(GetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity") == owner, "emitter owner");
    Require(GetEntPropEnt(particle, Prop_Send, "m_hControlPointEnts", 0) == owner, "camera CP1");
    Require(GetEntPropEnt(particle, Prop_Data, "m_hMoveParent") == prop, "wearable parent");
    int reference = EntIndexToEntRef(particle);
    CustomHats_AttachParticle(owner, prop, 0);
    Require(g_iHatParticleRef[prop] == reference, "duplicate attach prevented");
    g_ProbeHidden = true;
    Require(CustomHats_OnParticleTransmit(particle, owner) == Plugin_Handled, "shared visibility");
    g_ProbeHidden = false;
    if (g_ProbeClientUserId > 0)
    {
        g_iHatRef[owner][0] = EntIndexToEntRef(prop);
        g_iHatEquippedClass[owner][0] = cls;
        TF2_AddCondition(owner, TFCond_Stealthed, 1.0);
        CustomHats_OnConditionChanged(owner, TFCond_Stealthed);
        Require(g_iHatParticleRef[prop] == INVALID_ENT_REFERENCE, "stealth removes emitter");
        TF2_RemoveCondition(owner, TFCond_Stealthed);
        CustomHats_OnConditionChanged(owner, TFCond_Stealthed);
        particle = EntRefToEntIndex(g_iHatParticleRef[prop]);
        Require(particle > MaxClients && IsValidEntity(particle), "visibility restores emitter");
        reference = EntIndexToEntRef(particle);
        SDKHook(particle, SDKHook_SetTransmit, Probe_BlockTransmit);
        LogMessage("PASS: stealth removes the emitter; visibility restores its class variant.");
    }
    CustomHats_RemoveWearableParticle(prop);
    Require(g_iHatParticleRef[prop] == INVALID_ENT_REFERENCE, "tracking cleared");
    RemoveEntity(prop);
    RequestFrame(Probe_CheckRemoved, reference);
}

public Action Probe_BlockTransmit(int entity, int viewer) { return Plugin_Handled; }
public void Probe_CheckRemoved(any reference)
{
    int entity = EntRefToEntIndex(reference);
    if (entity != INVALID_ENT_REFERENCE)
    {
        Require(GetEntProp(entity, Prop_Send, "m_bActive") == 0
            && (GetEntProp(entity, Prop_Data, "m_iEFlags") & 1) != 0,
            "emitter stopped and queued for deletion");
        Require(++g_ProbeCleanupFrames < 10, "emitter eventually removed");
        RequestFrame(Probe_CheckRemoved, reference);
        return;
    }
    LogMessage("PASS: emitter attachment, owner/camera CP1, no duplicate, shared visibility and cleanup.");
    Probe_RemoveTestClient();
}
void Probe_RemoveTestClient()
{
    int client = GetClientOfUserId(g_ProbeClientUserId);
    g_ProbeClientUserId = 0;
    if (client > 0 && IsFakeClient(client))
        KickClient(client, "Particle regression probe completed");
}
public void OnEntityDestroyed(int entity) { CustomHats_RemoveWearableParticle(entity); }
public void OnPluginEnd()
{
    Probe_RemoveTestClient();
    int prop = EntRefToEntIndex(g_ProbeModelRef);
    if (prop > MaxClients && IsValidEntity(prop))
    {
        CustomHats_RemoveWearableParticle(prop);
        RemoveEntity(prop);
    }
    delete g_hHatParseParticleMap;
}

