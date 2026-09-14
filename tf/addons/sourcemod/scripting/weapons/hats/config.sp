void RemoveAllHats()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			RemoveHat(i, -1);
		}
	}
}

void PrecacheConfiguredHats()
{
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEnabled(i))
		{
			continue;
		}
		PrecacheModel(g_Hats[i].model, true);
	}
}

void LoadConfig()
{
	g_iHatCount = 0;
	g_iDefaultHatIndex = -1;
	for (int i = 0; i < MAX_HATS; i++)
	{
		ResetHatConfig(g_Hats[i]);
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CUSTOM_HATS_CONFIG_FILE);

	if (!FileExists(path))
	{
		CreateDefaultConfig(path);
	}

	KeyValues kv = new KeyValues("CustomHats");
	if (!kv.ImportFromFile(path))
	{
		LogError("[CustomHats] Failed to parse config file: %s", path);
		delete kv;
		return;
	}

	if (kv.JumpToKey("hats", false))
	{
		if (kv.GotoFirstSubKey())
		{
			do
			{
				if (g_iHatCount >= MAX_HATS)
				{
					LogError("[CustomHats] Too many hats configured (max %d).", MAX_HATS);
					break;
				}

				char hatId[64];
				kv.GetSectionName(hatId, sizeof(hatId));

				HatConfig hat;
				ResetHatConfig(hat);
				strcopy(hat.id, sizeof(hat.id), hatId);
				kv.GetString("name", hat.name, sizeof(hat.name), hatId);
				kv.GetString("prefix", hat.prefix, sizeof(hat.prefix), "");
				TrimString(hat.prefix);
				kv.GetString("blu_prefix", hat.bluPrefix, sizeof(hat.bluPrefix), "");
				TrimString(hat.bluPrefix);
				kv.GetString("points_store_purchase", hat.pointsStorePurchase, sizeof(hat.pointsStorePurchase), "");
				TrimString(hat.pointsStorePurchase);
				kv.GetString("model", hat.model, sizeof(hat.model), DEFAULT_SCOUT_MODEL);
				char modelScale[32];
				kv.GetString("model_scale", modelScale, sizeof(modelScale), "");
				TrimString(modelScale);
				if (modelScale[0])
				{
					hat.modelScale = StringToFloat(modelScale);
					hat.hasModelScale = hat.modelScale > 0.0;
					if (!hat.hasModelScale)
					{
						LogError("[CustomHats] Ignoring invalid model_scale for %s: %s", hat.id, modelScale);
					}
				}
				hat.enabled = (kv.GetNum("enabled", 1) != 0) && hat.model[0];
				hat.force = kv.GetNum("force", 0) != 0;
				hat.baseDefIndex = kv.GetNum("defindex", 0);
				hat.baseHideDefIndex = kv.GetNum("hide_defindex", 0);
				hat.quality = kv.GetNum("quality", 6);
				hat.level = kv.GetNum("level", 10);
				int paintIndex = kv.GetNum("paint_index", -1);
				if (paintIndex < 0)
				{
					paintIndex = kv.GetNum("paint", 0);
				}
				hat.defaultPaint = ClampPaintIndex(paintIndex);
				char paintFlag[8];
				kv.GetString("paint", paintFlag, sizeof(paintFlag), "false");
	hat.paintable = ParseBoolString(paintFlag, false);
	hat.style = kv.GetNum("style", 0);
	hat.bluSkin = kv.GetNum("blu_skin", -1);

	char classes[128];
	kv.GetString("classes", classes, sizeof(classes), "scout");
	hat.classMask = ParseClassMask(classes);

				LoadClassOverrides(kv, "soldier", TFClass_Soldier, hat);
				LoadClassOverrides(kv, "pyro", TFClass_Pyro, hat);
				LoadClassOverrides(kv, "demoman", TFClass_DemoMan, hat);
				LoadClassOverrides(kv, "heavy", TFClass_Heavy, hat);
				LoadClassOverrides(kv, "engineer", TFClass_Engineer, hat);
				LoadClassOverrides(kv, "medic", TFClass_Medic, hat);
				LoadClassOverrides(kv, "sniper", TFClass_Sniper, hat);
				LoadClassOverrides(kv, "spy", TFClass_Spy, hat);

				AddHatConfig(hat);
			}
			while (kv.GotoNextKey());
			kv.GoBack();
		}
		kv.GoBack();
	}

	delete kv;
}

void CreateDefaultConfig(const char[] path)
{
	File file = OpenFile(path, "w");
	if (file == null)
	{
		LogError("[CustomHats] Failed to create config file: %s", path);
		return;
	}

	file.WriteLine("\"CustomHats\"");
	file.WriteLine("{");
	file.WriteLine("    \"hats\"");
	file.WriteLine("    {");
	file.WriteLine("        \"mercenary_derby\"");
	file.WriteLine("        {");
	file.WriteLine("            \"name\" \"mercenary_derby\"");
	file.WriteLine("            \"enabled\" \"1\"");
	file.WriteLine("            \"force\" \"0\"");
	file.WriteLine("            \"model\" \"%s\"", DEFAULT_SCOUT_MODEL);
	file.WriteLine("            \"model_scale\" \"\"");
	file.WriteLine("            \"defindex\" \"451\"");
	file.WriteLine("            \"hide_defindex\" \"111\"");
	file.WriteLine("            \"quality\" \"6\"");
	file.WriteLine("            \"level\" \"10\"");
	file.WriteLine("            \"paint\" \"false\"");
	file.WriteLine("            \"paint_index\" \"0\"");
	file.WriteLine("            \"style\" \"0\"");
	file.WriteLine("            \"classes\" \"all\"");
	file.WriteLine("            \"points_store_purchase\" \"\"");
	file.WriteLine("            \"prefix\" \"\"");
	file.WriteLine("            \"blu_prefix\" \"\"");
	file.WriteLine("        }");
	file.WriteLine("    }");
	file.WriteLine("}");
	delete file;
}

