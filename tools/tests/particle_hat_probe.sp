#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

enum struct HatConfig
{
	char id[64];
	char model[PLATFORM_MAX_PATH];
	char particleEffect[128];
	char particleFile[PLATFORM_MAX_PATH];
	char particleAttachment[64];
	bool particleReady;
	bool particleInModel;
}
HatConfig g_Hats[1];
int g_iHatCount = 1;
int g_iProbeParticleRef = INVALID_ENT_REFERENCE;

bool IsHatEnabled(int index) { return index == 0; }
void RemoveHat(int client, int index) {}
#include "../../tf/addons/sourcemod/scripting/weapons/hats/particles.sp"

public void OnPluginStart()
{
	RegAdminCmd("sm_particle_hat_probe_status", Command_ProbeStatus, ADMFLAG_ROOT);
	CustomHats_InitParticles();
	if (g_hHatParseParticleMap == null)
		SetFailState("Particle map SDKCall unavailable");
	// Probe a loose manifest without changing the running map or its packed manifest.
	SDKCall(g_hHatParseParticleMap, "pl_vigil_rc10", true);
	strcopy(g_Hats[0].id, sizeof(g_Hats[].id), "tsurugi_halo");
	strcopy(g_Hats[0].model, sizeof(g_Hats[].model), "models/player/bluearchive/tsurugi_halo.mdl");
	strcopy(g_Hats[0].particleFile, sizeof(g_Hats[].particleFile), "particles/ba_tsurugi_blood.pcf");
	strcopy(g_Hats[0].particleEffect, sizeof(g_Hats[].particleEffect), "ba_tsurugi_blood");

	if (!CustomHats_PCFHasEffect(g_Hats[0].particleFile, g_Hats[0].particleEffect))
		SetFailState("PCF definition validation failed");
	if (!CustomHats_ModelHasParticle(g_Hats[0].model, g_Hats[0].particleEffect))
		SetFailState("Embedded model particle detection failed");
	bool locked = LockStringTables(false);
	int table = FindStringTable("ParticleEffectNames");
	AddToStringTable(table, g_Hats[0].particleEffect);
	LockStringTables(locked);
	int index = FindStringIndex(table, g_Hats[0].particleEffect);
	if (index == INVALID_STRING_INDEX)
		SetFailState("Particle registration failed");
	LogMessage("PASS: native PCF load, effect definition, model attachment and effect index %d.", index);

	PrecacheModel(g_Hats[0].model, true);
	int previous = -1;
	while ((previous = FindEntityByClassname(previous, "prop_dynamic")) != -1)
	{
		char model[PLATFORM_MAX_PATH];
		GetEntPropString(previous, Prop_Data, "m_ModelName", model, sizeof(model));
		if (StrEqual(model, g_Hats[0].model)) RemoveEntity(previous);
	}
	int prop = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(prop, "model", g_Hats[0].model);
	DispatchSpawn(prop);
	g_Hats[0].particleReady = true;
	g_Hats[0].particleInModel = true;
	CustomHats_AttachParticle(prop, 0);
	if (g_iHatParticleRef[prop] != INVALID_ENT_REFERENCE)
		SetFailState("Embedded model received duplicate emitter");
	g_Hats[0].particleInModel = false;
	CustomHats_AttachParticle(prop, 0);
	int particle = EntRefToEntIndex(g_iHatParticleRef[prop]);
	if (particle <= MaxClients || !IsValidEntity(particle))
		SetFailState("Fallback emitter creation failed");
	CustomHats_RemoveWearableParticle(prop);
	int particleRef = EntIndexToEntRef(particle);
	g_iProbeParticleRef = particleRef;
	RemoveEntity(prop);
	RequestFrame(CheckParticleRemoved, particleRef);

	int downloads = FindStringTable("downloadables");
	char current[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	GetCurrentMap(current, sizeof(current));
	Format(path, sizeof(path), "maps/%s_particles.txt", current);
	LogMessage("Download PCF=%d model=%d material=%d currentManifest=%d",
		FindStringIndex(downloads, g_Hats[0].particleFile),
		FindStringIndex(downloads, g_Hats[0].model),
		FindStringIndex(downloads, "materials/particles/ba_tsurugi/blood_lifecycle.vtf"),
		FindStringIndex(downloads, path));
}

public void OnPluginEnd() { delete g_hHatParseParticleMap; }

public void CheckParticleRemoved(int reference)
{
	int particle = EntRefToEntIndex(reference);
	if (particle != INVALID_ENT_REFERENCE)
	{
		int flags = GetEntProp(particle, Prop_Data, "m_iEFlags");
		if (GetEntProp(particle, Prop_Send, "m_bActive") != 0 || !(flags & 1))
			SetFailState("Fallback emitter was not stopped/queued for deletion");
	}
	LogMessage("PASS: no duplicate embedded emitter; fallback stopped and removed/queued for deletion.");
}

public Action Command_ProbeStatus(int client, int args)
{
	CheckParticleRemoved(g_iProbeParticleRef);
	return Plugin_Handled;
}

