/**
 * TF2 clients only learn custom PCFs from map particle manifests. The effect
 * string table precaches definitions; it does not load a PCF on its own.
 */
Handle g_hHatParseParticleMap;
bool g_bHatParticleMapLoaded;
int g_iHatParticleRef[2049];

void CustomHats_InitParticles()
{
	CustomHats_ResetParticles();
	GameData data = new GameData("weapons");
	if (data != null)
	{
		StartPrepSDKCall(SDKCall_Static);
		if (PrepSDKCall_SetFromConf(data, SDKConf_Signature, "ParseParticleEffectsMap"))
		{
			PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
			PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
			g_hHatParseParticleMap = EndPrepSDKCall();
		}
		delete data;
	}
	if (g_hHatParseParticleMap == null)
		LogError("[CustomHats] Cannot load custom PCFs: ParseParticleEffectsMap unavailable.");
}

void CustomHats_ResetParticles()
{
	g_bHatParticleMapLoaded = false;
	for (int i = 0; i < sizeof(g_iHatParticleRef); i++)
		g_iHatParticleRef[i] = INVALID_ENT_REFERENCE;
}

static bool CustomHats_ValidParticleFile(const char[] path)
{
	int length = strlen(path);
	return StrContains(path, "particles/", false) == 0
		&& StrContains(path[10], "/") == -1
		&& StrContains(path, "..") == -1
		&& StrContains(path, "\\") == -1
		&& length > 14 && StrEqual(path[length - 4], ".pcf", false)
		&& FileExists(path, true);
}

static bool CustomHats_ReadParticleManifest(const char[] path, ArrayList files)
{
	if (!FileExists(path))
		return true;
	KeyValues manifest = new KeyValues("particles_manifest");
	if (!manifest.ImportFromFile(path))
	{
		delete manifest;
		return false;
	}
	if (manifest.GotoFirstSubKey(false))
	{
		do
		{
			char key[64], value[PLATFORM_MAX_PATH];
			manifest.GetSectionName(key, sizeof(key));
			if (!StrEqual(key, "file", false))
				continue;
			manifest.GetString(NULL_STRING, value, sizeof(value));
			if (value[0])
				files.PushString(value);
		}
		while (manifest.GotoNextKey(false));
	}
	delete manifest;
	return true;
}

void CustomHats_PrecacheParticles()
{
	ArrayList files = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	bool hasCustomPCF;
	for (int i = 0; i < g_iHatCount; i++)
	{
		g_Hats[i].particleReady = false;
		g_Hats[i].particleInModel = false;
		if (IsHatEnabled(i) && g_Hats[i].particleEffect[0] && g_Hats[i].particleFile[0])
			hasCustomPCF = true;
	}

	bool canLoad = !hasCustomPCF;
	if (hasCustomPCF && g_hHatParseParticleMap != null)
	{
		char map[PLATFORM_MAX_PATH], basename[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
		GetCurrentMap(map, sizeof(map));
		int start;
		for (int n = 0; map[n]; n++)
			if (map[n] == '/') start = n + 1;
		strcopy(basename, sizeof(basename), map[start]);
		Format(path, sizeof(path), "maps/%s_particles.txt", basename);

		// A packed manifest wins over loose files in Valve's parser, on clients too.
		if (FileExists("particles.txt", true, "BSP") || FileExists(path, true, "BSP"))
			LogError("[CustomHats] %s has a packed particle manifest; merge custom PCFs into the BSP to enable particle hats.", map);
		else if (!CustomHats_ReadParticleManifest(path, files))
			LogError("[CustomHats] Refusing to overwrite invalid manifest: %s", path);
		else
		{
			bool changed = !FileExists(path);
			for (int i = 0; i < g_iHatCount; i++)
			{
				if (!IsHatEnabled(i) || !g_Hats[i].particleEffect[0] || !g_Hats[i].particleFile[0])
					continue;
				if (!CustomHats_ValidParticleFile(g_Hats[i].particleFile))
				{
					LogError("[CustomHats] Invalid/missing PCF for %s: %s", g_Hats[i].id, g_Hats[i].particleFile);
					continue;
				}
				bool found;
				char value[PLATFORM_MAX_PATH];
				for (int n = 0; n < files.Length; n++)
				{
					files.GetString(n, value, sizeof(value));
					int skip = value[0] == '!' ? 1 : 0;
					if (StrEqual(value[skip], g_Hats[i].particleFile, false))
					{
						found = true;
						if (!skip)
						{
							Format(value, sizeof(value), "!%s", g_Hats[i].particleFile);
							files.SetString(n, value);
							changed = true;
						}
						break;
					}
				}
				if (!found)
				{
					Format(value, sizeof(value), "!%s", g_Hats[i].particleFile);
					files.PushString(value);
					changed = true;
				}
				AddFileToDownloadsTable(g_Hats[i].particleFile);
				PrecacheGeneric(g_Hats[i].particleFile, true);
			}
			if (files.Length > 64)
				LogError("[CustomHats] %s exceeds TF2's 64 PCFs per map; not loading particle hats.", path);
			else if (files.Length > 0)
			{
				canLoad = true;
				if (changed)
				{
					File file = OpenFile(path, "w");
					if (file == null)
						canLoad = false;
					else
					{
						file.WriteLine("\"particles_manifest\"");
						file.WriteLine("{");
						char value[PLATFORM_MAX_PATH];
						for (int n = 0; n < files.Length; n++)
						{
							files.GetString(n, value, sizeof(value));
							file.WriteLine("    \"file\" \"%s\"", value);
						}
						file.WriteLine("}");
						delete file;
					}
				}
				if (canLoad)
				{
					AddFileToDownloadsTable(path);
					if (changed || !g_bHatParticleMapLoaded)
					{
						SDKCall(g_hHatParseParticleMap, basename, true);
						g_bHatParticleMapLoaded = true;
					}
				}
			}
		}
	}
	delete files;

	int table = FindStringTable("ParticleEffectNames");
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (!IsHatEnabled(i) || !g_Hats[i].particleEffect[0])
			continue;
		if (g_Hats[i].particleFile[0]
			&& (!canLoad || !CustomHats_ValidParticleFile(g_Hats[i].particleFile)))
			continue;
		// PCF loading and effect-name registration are separate engine operations.
		if (g_Hats[i].particleFile[0] && table != INVALID_STRING_TABLE)
		{
			if (!CustomHats_PCFHasEffect(g_Hats[i].particleFile, g_Hats[i].particleEffect))
			{
				LogError("[CustomHats] Effect absent or unsupported PCF encoding: %s (%s)", g_Hats[i].particleEffect, g_Hats[i].particleFile);
				continue;
			}
			bool locked = LockStringTables(false);
			AddToStringTable(table, g_Hats[i].particleEffect);
			LockStringTables(locked);
		}
		g_Hats[i].particleReady = table != INVALID_STRING_TABLE
			&& FindStringIndex(table, g_Hats[i].particleEffect) != INVALID_STRING_INDEX;
		if (!g_Hats[i].particleReady)
		{
			LogError("[CustomHats] Particle effect not precached: %s (%s)", g_Hats[i].particleEffect, g_Hats[i].id);
			continue;
		}
		g_Hats[i].particleInModel = CustomHats_ModelHasParticle(g_Hats[i].model, g_Hats[i].particleEffect);
		LogMessage("[CustomHats] Loaded particle %s for %s (%s).", g_Hats[i].particleEffect,
			g_Hats[i].id, g_Hats[i].particleInModel ? "model attachment" : "wearable emitter");
	}
}


bool CustomHats_PCFHasEffect(const char[] path, const char[] effect)
{
	File file = OpenFile(path, "rb", true);
	if (file == null)
		return false;
	char value[1024];
	int count;
	if (file.ReadString(value, sizeof(value)) <= 0
		|| StrContains(value, "dmx encoding binary 2 format pcf 1") == -1
		|| !file.ReadUint16(count) || count <= 0 || count > 8192)
	{
		delete file;
		return false;
	}
	bool[] definitions = new bool[count];
	for (int i = 0; i < count; i++)
	{
		if (file.ReadString(value, sizeof(value)) < 0)
		{
			delete file;
			return false;
		}
		definitions[i] = StrEqual(value, "DmeParticleSystemDefinition");
	}
	int elements;
	bool found;
	if (file.ReadInt32(elements) && elements > 0 && elements <= 65536)
	{
		for (int i = 0; i < elements; i++)
		{
			int type;
			if (!file.ReadUint16(type) || type >= count
				|| file.ReadString(value, sizeof(value)) < 0)
				break;
			if (definitions[type] && StrEqual(value, effect))
			{
				found = true;
				break;
			}
			if (!file.Seek(16, SEEK_CUR))
				break;
		}
	}
	delete file;
	return found;
}

bool CustomHats_ModelHasParticle(const char[] model, const char[] effect)
{
	File file = OpenFile(model, "rb", true);
	if (file == null)
		return false;
	int magic, version, offset, length;
	bool valid = file.ReadInt32(magic) && file.ReadInt32(version)
		&& magic == 0x54534449 && (version == 48 || version == 49)
		&& file.Seek(312, SEEK_SET) && file.ReadInt32(offset) && file.ReadInt32(length)
		&& offset > 0 && length > 0 && length < 16384;
	char text[16384];
	if (valid)
		valid = file.Seek(offset, SEEK_SET) && file.ReadString(text, sizeof(text), length) > 0;
	delete file;
	if (!valid)
		return false;
	KeyValues kv = new KeyValues("mdlkeyvalue");
	bool found;
	if (kv.ImportFromString(text) && kv.JumpToKey("Particles") && kv.GotoFirstSubKey())
	{
		do
		{
			char name[128];
			kv.GetString("name", name, sizeof(name));
			if (StrEqual(name, effect))
			{
				found = true;
				break;
			}
		}
		while (kv.GotoNextKey());
	}
	delete kv;
	return found;
}

void CustomHats_AttachParticle(int wearable, int hatIndex)
{
	if (!g_Hats[hatIndex].particleReady || g_Hats[hatIndex].particleInModel
		|| wearable >= sizeof(g_iHatParticleRef))
		return;
	int particle = CreateEntityByName("info_particle_system");
	if (particle == -1)
		return;
	DispatchKeyValue(particle, "effect_name", g_Hats[hatIndex].particleEffect);
	DispatchSpawn(particle);
	float origin[3];
	GetEntPropVector(wearable, Prop_Send, "m_vecOrigin", origin);
	TeleportEntity(particle, origin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(particle, "SetParent", wearable, wearable);
	if (g_Hats[hatIndex].particleAttachment[0])
	{
		SetVariantString(g_Hats[hatIndex].particleAttachment);
		AcceptEntityInput(particle, "SetParentAttachment");
	}
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Start");
	g_iHatParticleRef[wearable] = EntIndexToEntRef(particle);
}

void CustomHats_RemoveWearableParticle(int wearable)
{
	if (wearable <= MaxClients || wearable >= sizeof(g_iHatParticleRef))
		return;
	int particle = EntRefToEntIndex(g_iHatParticleRef[wearable]);
	g_iHatParticleRef[wearable] = INVALID_ENT_REFERENCE;
	if (particle > MaxClients && IsValidEntity(particle))
	{
		AcceptEntityInput(particle, "Stop");
		RemoveEntity(particle);
	}
}

public void CustomHats_EventParticleDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
		RemoveHat(client, -1);
}

