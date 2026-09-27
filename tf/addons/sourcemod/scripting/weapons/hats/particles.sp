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
		for (int classIndex = 1; classIndex <= 9; classIndex++)
		{
			g_HatClassVariants[i][classIndex].particleReady = false;
			g_HatClassVariants[i][classIndex].particleInModel = false;
			if (IsHatEnabled(i) && IsClassAllowedForHat(i, view_as<TFClassType>(classIndex))
				&& g_HatClassVariants[i][classIndex].particleEffect[0]
				&& g_HatClassVariants[i][classIndex].particleFile[0])
				hasCustomPCF = true;
		}
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
				if (!IsHatEnabled(i))
					continue;
				for (int classIndex = 1; classIndex <= 9; classIndex++)
				{
					HatClassVariant classAssets;
					classAssets = g_HatClassVariants[i][classIndex];
					if (!IsClassAllowedForHat(i, view_as<TFClassType>(classIndex))
						|| !classAssets.particleEffect[0] || !classAssets.particleFile[0])
						continue;
					if (!CustomHats_ValidParticleFile(classAssets.particleFile))
					{
						LogError("[CustomHats] Invalid/missing PCF for %s class %d: %s", g_Hats[i].id, classIndex, classAssets.particleFile);
						continue;
					}
					bool found;
					char value[PLATFORM_MAX_PATH];
					for (int n = 0; n < files.Length; n++)
					{
						files.GetString(n, value, sizeof(value));
						int skip = value[0] == '!' ? 1 : 0;
						if (StrEqual(value[skip], classAssets.particleFile, false))
						{
							found = true;
							if (!skip)
							{
								Format(value, sizeof(value), "!%s", classAssets.particleFile);
								files.SetString(n, value);
								changed = true;
							}
							break;
						}
					}
					if (!found)
					{
						Format(value, sizeof(value), "!%s", classAssets.particleFile);
						files.PushString(value);
						changed = true;
					}
					AddFileToDownloadsTable(classAssets.particleFile);
					PrecacheGeneric(classAssets.particleFile, true);
				}
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
		if (!IsHatEnabled(i) || table == INVALID_STRING_TABLE)
			continue;
		for (int classIndex = 1; classIndex <= 9; classIndex++)
		{
			HatClassVariant classAssets;
			classAssets = g_HatClassVariants[i][classIndex];
			if (!IsClassAllowedForHat(i, view_as<TFClassType>(classIndex)) || !classAssets.particleEffect[0])
				continue;
			if (classAssets.particleFile[0])
			{
				if (!canLoad || !CustomHats_ValidParticleFile(classAssets.particleFile))
					continue;
				if (!CustomHats_PCFHasEffect(classAssets.particleFile, classAssets.particleEffect))
				{
					LogError("[CustomHats] Effect absent or unsupported PCF encoding: %s (%s)", classAssets.particleEffect, classAssets.particleFile);
					continue;
				}
				bool locked = LockStringTables(false);
				if (FindStringIndex(table, classAssets.particleEffect) == INVALID_STRING_INDEX)
					AddToStringTable(table, classAssets.particleEffect);
				LockStringTables(locked);
			}
			classAssets.particleReady = FindStringIndex(table, classAssets.particleEffect) != INVALID_STRING_INDEX;
			if (!classAssets.particleReady)
			{
				LogError("[CustomHats] Particle effect not precached: %s (%s)", classAssets.particleEffect, g_Hats[i].id);
				continue;
			}
			classAssets.particleInModel = CustomHats_ModelHasParticle(classAssets.model, classAssets.particleEffect);
			g_HatClassVariants[i][classIndex] = classAssets;
			LogMessage("[CustomHats] Loaded particle %s for %s class %d (%s).", classAssets.particleEffect,
				g_Hats[i].id, classIndex, classAssets.particleInModel ? "model attachment" : "wearable emitter");
		}
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

static bool CustomHats_CanDisplayParticle(int client)
{
	return Client_IsInGame(client) && IsPlayerAlive(client)
		&& !TF2_IsPlayerInCondition(client, TFCond_Cloaked)
		&& !TF2_IsPlayerInCondition(client, TFCond_Disguised)
		&& !TF2_IsPlayerInCondition(client, TFCond_Disguising)
		&& !TF2_IsPlayerInCondition(client, TFCond_Stealthed)
		&& !TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade);
}

void CustomHats_AttachParticle(int client, int wearable, int hatIndex)
{
	if (!CustomHats_CanDisplayParticle(client) || !IsHatIndexValid(hatIndex)
		|| wearable <= MaxClients || wearable >= sizeof(g_iHatParticleRef) || !IsValidEntity(wearable))
		return;
	int classIndex = view_as<int>(TF2_GetPlayerClass(client));
	if (classIndex < 1 || classIndex > 9)
		return;
	HatClassVariant classAssets;
	classAssets = g_HatClassVariants[hatIndex][classIndex];
	if (!classAssets.particleReady || classAssets.particleInModel
		|| EntRefToEntIndex(g_iHatParticleRef[wearable]) != INVALID_ENT_REFERENCE)
		return;
	int attachment;
	if (classAssets.particleAttachment[0])
	{
		attachment = LookupEntityAttachment(wearable, classAssets.particleAttachment);
		if (attachment < 1)
		{
			LogError("[CustomHats] Missing attachment %s on %s.", classAssets.particleAttachment, classAssets.model);
			return;
		}
	}
	int particle = CreateEntityByName("info_particle_system");
	if (particle <= MaxClients)
		return;
	DispatchKeyValue(particle, "effect_name", classAssets.particleEffect);
	DispatchKeyValue(particle, "start_active", "0");
	DispatchSpawn(particle);
	// Start at the wearer's position before parenting, even in distant arenas.
	float origin[3], angles[3];
	GetClientAbsOrigin(client, origin);
	if (attachment > 0)
		GetEntityAttachment(wearable, attachment, origin, angles);
	TeleportEntity(particle, origin, angles, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(particle, "SetParent", wearable, wearable);
	if (attachment > 0)
	{
		SetVariantString(classAssets.particleAttachment);
		AcceptEntityInput(particle, "SetParentAttachment", wearable, wearable);
	}
	SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", client);
	int point = classAssets.ownerCameraControlPoint;
	if (point > 0 && point <= GetEntPropArraySize(particle, Prop_Send, "m_hControlPointEnts"))
		SetEntPropEnt(particle, Prop_Send, "m_hControlPointEnts", client, point - 1);
	SDKHook(particle, SDKHook_SetTransmit, CustomHats_OnParticleTransmit);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Start");
	g_iHatParticleRef[wearable] = EntIndexToEntRef(particle);
}

public Action CustomHats_OnParticleTransmit(int particle, int viewer)
{
	int owner = GetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity");
	if (!CustomHats_CanDisplayParticle(owner))
		return Plugin_Handled;
	return WeaponsHatVisibility_OnTransmit(particle, viewer);
}

void CustomHats_OnConditionChanged(int client, TFCond condition)
{
	if (condition != TFCond_Cloaked && condition != TFCond_Disguised
		&& condition != TFCond_Disguising && condition != TFCond_Stealthed
		&& condition != TFCond_StealthedUserBuffFade)
		return;
	if (!Client_IsInGame(client))
		return;
	bool visible = CustomHats_CanDisplayParticle(client);
	int classIndex = view_as<int>(TF2_GetPlayerClass(client));
	for (int i = 0; i < g_iHatCount; i++)
	{
		int wearable = EntRefToEntIndex(g_iHatRef[client][i]);
		if (wearable <= MaxClients || !IsValidEntity(wearable))
			continue;
		if (visible && g_iHatEquippedClass[client][i] == classIndex)
			CustomHats_AttachParticle(client, wearable, i);
		else
			CustomHats_RemoveWearableParticle(wearable);
	}
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

