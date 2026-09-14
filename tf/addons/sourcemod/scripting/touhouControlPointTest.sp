#include <sourcemod>
#include <sdktools>

#define STOCK_CONTROL_POINT_MODEL \
	"models/props_gameplay/cap_point_base.mdl"

#define TOUHOU_CONTROL_POINT_MODEL \
	"models/touhou/cap_point_touhou.mdl"

#define STOCK_RESUPPLY_LOCKER_MODEL \
	"models/props_gameplay/resupply_locker.mdl"

#define TOUHOU_RESUPPLY_LOCKER_MODEL \
	"models/touhou/eientei_resupply_locker.mdl"

bool g_bTouhouResupplyLockerReady;

public Plugin myinfo =
{
	name = "Touhou Control Point Test",
	author = "Kogasatopia",
	description = "Replaces stock TF2 control point and resupply locker models with Touhou models.",
	version = "1.1"
};

public void OnPluginStart()
{
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
	g_bTouhouResupplyLockerReady = FileExists(TOUHOU_RESUPPLY_LOCKER_MODEL, true);

	ReplaceGameplayPropModels();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ReplaceGameplayPropModels();
}

static void ReplaceGameplayPropModels()
{
	int entity = -1;

	while ((entity = FindEntityByClassname(entity, "prop_dynamic")) != -1)
	{
		char model[PLATFORM_MAX_PATH];

		GetEntPropString(
			entity,
			Prop_Data,
			"m_ModelName",
			model,
			sizeof(model)
		);

		if (StrEqual(model, STOCK_CONTROL_POINT_MODEL, false))
		{
			SetEntityModel(entity, TOUHOU_CONTROL_POINT_MODEL);

			SetVariantString("idle");
			AcceptEntityInput(entity, "SetDefaultAnimation");

			SetVariantString("idle");
			AcceptEntityInput(entity, "SetAnimation");
			continue;
		}

		if (g_bTouhouResupplyLockerReady
			&& StrEqual(model, STOCK_RESUPPLY_LOCKER_MODEL, false))
		{
			SetEntityModel(entity, TOUHOU_RESUPPLY_LOCKER_MODEL);
		}
	}
}
