#include <sourcemod>
#include <sdktools>

#define STOCK_CONTROL_POINT_MODEL \
	"models/props_gameplay/cap_point_base.mdl"

#define TOUHOU_CONTROL_POINT_MODEL \
	"models/touhou/cap_point_touhou.mdl"

public Plugin myinfo =
{
	name = "Touhou Control Point Test",
	author = "Kogasatopia",
	description = "Replaces stock TF2 control point models with a Touhou model.",
	version = "1.0"
};

public void OnPluginStart()
{
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
	PrecacheModel(TOUHOU_CONTROL_POINT_MODEL, true);
	ReplaceControlPointModels();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ReplaceControlPointModels();
}

static void ReplaceControlPointModels()
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

		if (!StrEqual(model, STOCK_CONTROL_POINT_MODEL, false))
		{
			continue;
		}

		SetEntityModel(entity, TOUHOU_CONTROL_POINT_MODEL);

		SetVariantString("idle");
		AcceptEntityInput(entity, "SetDefaultAnimation");

		SetVariantString("idle");
		AcceptEntityInput(entity, "SetAnimation");
	}
}
