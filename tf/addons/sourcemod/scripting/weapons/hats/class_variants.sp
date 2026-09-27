/** Resolved class-specific assets; existing class defindex overrides stay separate. */
enum struct HatClassVariant
{
	char model[PLATFORM_MAX_PATH];
	char particleEffect[128];
	char particleFile[PLATFORM_MAX_PATH];
	char particleAttachment[64];
	int body;
	int ownerCameraControlPoint;
	bool particleReady;
	bool particleInModel;
}

HatClassVariant g_HatClassVariants[MAX_HATS][10];

static void CustomHats_ReadVariantParticle(KeyValues config, HatClassVariant classAssets)
{
	if (!config.JumpToKey("particle"))
		return;
	config.GetString("effect", classAssets.particleEffect, sizeof(classAssets.particleEffect), classAssets.particleEffect);
	config.GetString("pcf", classAssets.particleFile, sizeof(classAssets.particleFile), classAssets.particleFile);
	config.GetString("attachment", classAssets.particleAttachment, sizeof(classAssets.particleAttachment), classAssets.particleAttachment);
	classAssets.ownerCameraControlPoint = config.GetNum("owner_camera_control_point", classAssets.ownerCameraControlPoint);
	config.GoBack();
}

void CustomHats_LoadClassVariants(KeyValues config, int hatIndex)
{
	for (int classIndex = 1; classIndex <= 9; classIndex++)
	{
		HatClassVariant classAssets;
		strcopy(classAssets.model, sizeof(classAssets.model), g_Hats[hatIndex].model);
		strcopy(classAssets.particleEffect, sizeof(classAssets.particleEffect), g_Hats[hatIndex].particleEffect);
		strcopy(classAssets.particleFile, sizeof(classAssets.particleFile), g_Hats[hatIndex].particleFile);
		strcopy(classAssets.particleAttachment, sizeof(classAssets.particleAttachment), g_Hats[hatIndex].particleAttachment);
		classAssets.body = config.GetNum("body", -1);
		classAssets.ownerCameraControlPoint = 0;
		CustomHats_ReadVariantParticle(config, classAssets);

		char classKey[32];
		TF2Classes_GetKey(view_as<TFClassType>(classIndex), classKey, sizeof(classKey));
		bool hasOverride = config.JumpToKey(classKey);
		if (!hasOverride && classIndex == view_as<int>(TFClass_DemoMan))
			hasOverride = config.JumpToKey("demo");
		if (hasOverride)
		{
			config.GetString("model", classAssets.model, sizeof(classAssets.model), classAssets.model);
			classAssets.body = config.GetNum("body", classAssets.body);
			CustomHats_ReadVariantParticle(config, classAssets);
			config.GoBack();
		}

		// PCFs commonly abbreviate Demoman as "demo", unlike config class keys.
		if (classIndex == view_as<int>(TFClass_DemoMan))
			strcopy(classKey, sizeof(classKey), "demo");
		ReplaceString(classAssets.model, sizeof(classAssets.model), "{class}", classKey);
		ReplaceString(classAssets.particleEffect, sizeof(classAssets.particleEffect), "{class}", classKey);
		ReplaceString(classAssets.particleFile, sizeof(classAssets.particleFile), "{class}", classKey);
		ReplaceString(classAssets.particleAttachment, sizeof(classAssets.particleAttachment), "{class}", classKey);
		classAssets.particleReady = false;
		classAssets.particleInModel = false;
		g_HatClassVariants[hatIndex][classIndex] = classAssets;
	}
}

bool CustomHats_VariantMatchesWearable(int wearable, int hatIndex, int classIndex)
{
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(wearable, Prop_Data, "m_ModelName", model, sizeof(model));
	return StrEqual(model, g_HatClassVariants[hatIndex][classIndex].model, false);
}
