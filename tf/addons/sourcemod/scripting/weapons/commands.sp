void WeaponsCommands_OnPluginStart()
{
	RegConsoleCmd("sm_weaponinfo", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_weaponchanges", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_reverts", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_revert", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_r", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_rp", Command_WeaponInfo, "Lists configured weapon changes");
	RegConsoleCmd("sm_changes", Command_WeaponInfo, "Lists configured weapon changes");
}

void WeaponsCommands_ResetClient(int client)
{
	g_WeaponsHtmlMotdPreference[client] = WeaponsHtmlMotd_Unknown;
}

void WeaponsCommands_QueryHtmlMotdPreference(int client)
{
	WeaponsCommands_ResetClient(client);
	if (!Client_IsInGame(client) || IsFakeClient(client)) return;

	QueryClientConVar(client, "cl_disablehtmlmotd", WeaponsCommands_OnHtmlMotdQueried,
		GetClientSerial(client));
}

public void WeaponsCommands_OnHtmlMotdQueried(QueryCookie cookie, int client,
	ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any serial)
{
	if (GetClientFromSerial(serial) != client || result != ConVarQuery_Okay) return;

	g_WeaponsHtmlMotdPreference[client] = StringToInt(cvarValue) == 0
		? WeaponsHtmlMotd_Enabled
		: WeaponsHtmlMotd_Disabled;
}

bool WeaponsCommands_TryShowClassPage(int client, bool customWeapons)
{
	if (g_WeaponsHtmlMotdPreference[client] != WeaponsHtmlMotd_Enabled) return false;

	char classKey[16];
	TF2Classes_GetKey(TF2Classes_GetCurrentOrDesired(client), classKey, sizeof(classKey));
	if (!classKey[0]) return false;

	char view[48];
	FormatEx(view, sizeof(view), "%s-%s-ingame",
		classKey, customWeapons ? "custom" : "reverts");

	char url[256];
	FormatEx(url, sizeof(url), "https://kogasa.tf/weapons?view=%s&motd=2#%s", view, view);

	KeyValues panel = new KeyValues("data");
	panel.SetString("title", customWeapons ? "Custom Weapons" : "Weapon Reverts");
	panel.SetString("type", "2");
	panel.SetString("msg", url);
	panel.SetNum("customsvr", 1);
	ShowVGUIPanel(client, "info", panel);
	delete panel;
	return true;
}

static KeyValues LoadWeaponsItemClassesConfig()
{
	if (g_WeaponsConfig == null)
		return null;

	KeyValues config = new KeyValues(WEAPONS_CONFIG_ROOT);
	config.Import(g_WeaponsConfig);
	return config;
}

static void FormatWeaponInfoLine(char[] buffer, int maxlen, const char[] weaponName, const char[] positive, const char[] neutral, const char[] negative)
{
	Format(buffer, maxlen, "{gold}%s{default}:", weaponName);
	bool needsComma = false;

	if (positive[0] != '\0')
	{
		AppendWeaponInfoLinePart(buffer, maxlen, "{green}", positive, needsComma);
	}
	if (neutral[0] != '\0')
	{
		AppendWeaponInfoLinePart(buffer, maxlen, "{default}", neutral, needsComma);
	}
	if (negative[0] != '\0')
	{
		AppendWeaponInfoLinePart(buffer, maxlen, "{red}", negative, needsComma);
	}
}

static void AppendWeaponInfoLinePart(char[] buffer, int maxlen, const char[] color, const char[] text, bool &needsComma)
{
	if (needsComma)
	{
		StrCat(buffer, maxlen, ",");
	}
	StrCat(buffer, maxlen, " ");
	StrCat(buffer, maxlen, color);
	StrCat(buffer, maxlen, text);
	needsComma = true;
}

public Action Command_WeaponInfo(int client, int args)
{
	if (!Client_IsInGame(client))
		return Plugin_Handled;
	if (WeaponsCommands_TryShowClassPage(client, false))
		return Plugin_Handled;

	if (g_hWeaponsGameplayConfig == null)
	{
		CPrintToChat(client, "{green}[Info] {default}No weapon data available on this server.");
		return Plugin_Handled;
	}

	char classKey[16];
	TF2Classes_GetKey(TF2Classes_GetCurrentOrDesired(client), classKey, sizeof(classKey));
	if (classKey[0] == '\0')
		return Plugin_Handled;

	KeyValues config = LoadWeaponsItemClassesConfig();
	if (config == null
		|| !config.JumpToKey(WEAPONS_ITEM_CLASSES_SECTION, false)
		|| !config.JumpToKey(classKey, false))
	{
		CPrintToChat(client, "{green}[Info] {default}No weapon data available for your class.");
		delete config;
		return Plugin_Handled;
	}

	StringMap printed = new StringMap();
	if (config.GotoFirstSubKey(false))
	{
		do
		{
			char indexKey[64];
			config.GetSectionName(indexKey, sizeof(indexKey));
			int indexes[1];
			if (ItemIndexes_Parse(indexKey, indexes, sizeof(indexes)) == 0)
				continue;
			int weaponIndex = indexes[0];

			char weaponName[128];
			char positive[256];
			char neutral[256];
			char negative[256];
			char type[32];
			char classes[128];
			if (!WeaponsGameplay_GetConfiguredInfo(weaponIndex, weaponName, sizeof(weaponName), positive, sizeof(positive), neutral, sizeof(neutral), negative, sizeof(negative), type, sizeof(type), classes, sizeof(classes)))
				continue;

			char dedupeKey[512];
			Format(dedupeKey, sizeof(dedupeKey), "%s|%s|%s", positive, neutral, negative);
			if (printed.ContainsKey(dedupeKey))
				continue;
			printed.SetValue(dedupeKey, 1);

			char line[512];
			FormatWeaponInfoLine(line, sizeof(line), weaponName, positive, neutral, negative);
			CPrintToChat(client, "%s", line);
		}
		while (config.GotoNextKey(false));
	}

	delete printed;
	delete config;
	return Plugin_Handled;
}
