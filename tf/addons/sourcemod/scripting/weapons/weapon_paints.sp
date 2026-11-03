/**
 * Paint support for custom items marked `"paintable" "true"` in weapons.cfg.
 *
 * Paints are chosen from the sm_cw menu (a "Paint <item>" entry under the equipped item) and are
 * applied the same way the custom hats module paints hats: through the "set item tint RGB"
 * attributes (142 / 261).  Whether the paint actually shows depends on the item's materials
 * using the ItemTintColor proxy.
 *
 * Besides the stock paints, players can pick "Custom paint" and type a morecolors chat color name
 * (or a #RRGGBB hex code) in chat.
 *
 * Choices are stored per item uid in client cookies as `uid:<paint index>` or `uid:#RRGGBB`.
 */

#define WEAPON_PAINT_ATTRIB_RED 142
#define WEAPON_PAINT_ATTRIB_BLU 261

// Encoded choice: 0 = no paint, 1..N = stock paint index, flag | rgb = custom color.
#define WEAPON_PAINT_CUSTOM_FLAG 0x1000000
#define WEAPON_PAINT_RGB_MASK 0xFFFFFF

#define WEAPON_PAINT_COOKIE_CHUNKS 4
#define WEAPON_PAINT_COOKIE_LEN 100
#define WEAPON_PAINT_PROMPT_SECONDS 60.0
#define WEAPON_PAINT_MENU_KEY_CUSTOM "custom"
#define WEAPON_PAINT_MENU_PREFIX "paint:"

static Cookie s_PaintCookies[WEAPON_PAINT_COOKIE_CHUNKS];
static StringMap s_PaintChoices[MAXPLAYERS + 1];
static int s_PaintCookieChunksUsed[MAXPLAYERS + 1];

static char s_PaintMenuUid[MAXPLAYERS + 1][MAX_ITEM_IDENTIFIER_LENGTH];
static bool s_bAwaitingCustomPaint[MAXPLAYERS + 1];
static float s_flCustomPaintPromptTime[MAXPLAYERS + 1];

void WeaponsPaint_OnPluginStart() {
	for (int i; i < WEAPON_PAINT_COOKIE_CHUNKS; i++) {
		char name[32], description[64];
		if (i == 0) {
			strcopy(name, sizeof(name), "custom_weapon_paints");
			strcopy(description, sizeof(description), "Custom weapon paints (uid:paint,...)");
		} else {
			FormatEx(name, sizeof(name), "custom_weapon_paints_%d", i + 1);
			FormatEx(description, sizeof(description), "Custom weapon paints continuation %d", i + 1);
		}
		s_PaintCookies[i] = new Cookie(name, description, CookieAccess_Private);
	}
}

void WeaponsPaint_OnClientCookiesCached(int client) {
	ResetPaintChoices(client);

	char chunk[WEAPON_PAINT_COOKIE_LEN];
	int chunksUsed;
	for (int i; i < WEAPON_PAINT_COOKIE_CHUNKS; i++) {
		s_PaintCookies[i].Get(client, chunk, sizeof(chunk));
		if (!chunk[0]) {
			continue;
		}
		chunksUsed = i + 1;

		char entries[16][WEAPON_PAINT_COOKIE_LEN];
		int count = ExplodeString(chunk, ",", entries, sizeof(entries), sizeof(entries[]));
		for (int e; e < count; e++) {
			int separator = FindCharInString(entries[e], ':', true);
			if (separator <= 0) {
				continue;
			}
			entries[e][separator] = '\0';

			int choice;
			if (DecodePaintChoice(entries[e][separator + 1], choice) && choice) {
				s_PaintChoices[client].SetValue(entries[e], choice);
			}
		}
	}
	s_PaintCookieChunksUsed[client] = chunksUsed;
}

void WeaponsPaint_OnClientDisconnect(int client) {
	delete s_PaintChoices[client];
	s_PaintCookieChunksUsed[client] = 0;
	s_PaintMenuUid[client][0] = '\0';
	s_bAwaitingCustomPaint[client] = false;
}

/**
 * Applies the client's paint choice for `item` to an item entity.  Does nothing for items that
 * aren't paintable.
 */
void WeaponsPaint_ApplyToEntity(int client, const CustomItemDefinition item, int entity) {
	if (!item.paintable || client <= 0 || client > MaxClients || !IsValidEntity(entity)) {
		return;
	}
	SetPaintAttributes(entity, GetPaintChoice(client, item.uid));
}

/**
 * Copies paint attributes from a weapon onto a wearable that renders its custom model, so the
 * model's ItemTintColor proxy sees the same paint.
 */
void WeaponsPaint_CopyToWearable(int weapon, int wearable) {
	if (!IsValidEntity(weapon) || !IsValidEntity(wearable)) {
		return;
	}
	CopyPaintAttribute(weapon, wearable, WEAPON_PAINT_ATTRIB_RED);
	CopyPaintAttribute(weapon, wearable, WEAPON_PAINT_ATTRIB_BLU);
}

/**
 * Shows the paint selection menu for a paintable item.  Only reached from the sm_cw menu.
 */
void WeaponsPaint_ShowMenu(int client, const char[] uid) {
	CustomItemDefinition item;
	if (!GetCustomItemDefinition(uid, item) || !item.paintable) {
		WeaponsLoadout_DisplayEquipMenu(client);
		return;
	}
	strcopy(s_PaintMenuUid[client], sizeof(s_PaintMenuUid[]), uid);

	char current[64];
	DescribePaintChoice(GetPaintChoice(client, uid), current, sizeof(current));

	Menu menu = new Menu(MenuHandler_WeaponPaint);
	menu.SetTitle("Select Paint: %s\nCurrent: %s", item.displayName, current);

	char key[8], name[48];
	CustomHats_GetPaintName(0, name, sizeof(name));
	menu.AddItem("0", name);
	menu.AddItem(WEAPON_PAINT_MENU_KEY_CUSTOM, "Custom paint (type a chat color)");
	for (int i = 1; i < CustomHats_GetPaintCount(); i++) {
		IntToString(i, key, sizeof(key));
		CustomHats_GetPaintName(i, name, sizeof(name));
		menu.AddItem(key, name);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

static int MenuHandler_WeaponPaint(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(item, info, sizeof(info));

		if (StrEqual(info, WEAPON_PAINT_MENU_KEY_CUSTOM)) {
			StartCustomPaintPrompt(client);
			return 0;
		}

		int paint = ClampPaintIndex(StringToInt(info));
		SetPaintChoice(client, s_PaintMenuUid[client], paint);

		char name[48];
		CustomHats_GetPaintName(paint, name, sizeof(name));
		CPrintToChat(client, "{gold}[Weapons]{default} %s applied.", name);
		WeaponsLoadout_DisplayEquipMenu(client);
	} else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsClientInGame(client)) {
		WeaponsLoadout_DisplayEquipMenu(client);
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

static void StartCustomPaintPrompt(int client) {
	s_bAwaitingCustomPaint[client] = true;
	s_flCustomPaintPromptTime[client] = GetEngineTime();

	CPrintToChat(client, "{gold}[Weapons]{default} Type a chat color in chat to use as paint, "
			... "e.g. {orange}orange{default}, {deepskyblue}deepskyblue{default} or "
			... "{haunted}haunted{default}, or a hex code like {gold}#FF8800{default}.");
	CPrintToChat(client, "{gold}[Weapons]{default} Color names: "
			... "{lightblue}doctormckay.com/morecolors.php{default}. Type {red}cancel{default} to stop.");
}

/**
 * Consumes the client's next chat message while a custom paint prompt is open.
 */
Action WeaponsPaint_OnClientSayCommand(int client, const char[] message) {
	if (client <= 0 || client > MaxClients || !s_bAwaitingCustomPaint[client]) {
		return Plugin_Continue;
	}

	if (GetEngineTime() - s_flCustomPaintPromptTime[client] > WEAPON_PAINT_PROMPT_SECONDS) {
		s_bAwaitingCustomPaint[client] = false;
		return Plugin_Continue;
	}

	char input[64];
	strcopy(input, sizeof(input), message);
	TrimString(input);
	StripQuotes(input);
	TrimString(input);

	// chat commands still go through, and close the prompt
	if (input[0] == '!' || input[0] == '/') {
		s_bAwaitingCustomPaint[client] = false;
		return Plugin_Continue;
	}

	if (StrEqual(input, "cancel", false)) {
		s_bAwaitingCustomPaint[client] = false;
		CPrintToChat(client, "{gold}[Weapons]{default} Custom paint cancelled.");
		WeaponsPaint_ShowMenu(client, s_PaintMenuUid[client]);
		return Plugin_Handled;
	}

	int rgb;
	if (!ParseChatColor(input, rgb)) {
		CPrintToChat(client, "{gold}[Weapons]{default} \"%s\" isn't a chat color. "
				... "Try again, or type {red}cancel{default}.", input);
		s_flCustomPaintPromptTime[client] = GetEngineTime();
		return Plugin_Handled;
	}

	// a paint value of 0 means "unpainted" to the game, so pure black becomes #000001
	if (rgb == 0) {
		rgb = 1;
	}

	s_bAwaitingCustomPaint[client] = false;
	SetPaintChoice(client, s_PaintMenuUid[client], WEAPON_PAINT_CUSTOM_FLAG | rgb);

	char description[64];
	DescribePaintChoice(WEAPON_PAINT_CUSTOM_FLAG | rgb, description, sizeof(description));
	CPrintToChat(client, "{gold}[Weapons]{default} Custom paint \x07%06X%s{default} applied.",
			rgb, description);
	WeaponsLoadout_DisplayEquipMenu(client);
	return Plugin_Handled;
}

/**
 * Accepts a morecolors name (optionally wrapped in braces) or a #RRGGBB hex code.
 */
static bool ParseChatColor(const char[] input, int &rgb) {
	char name[64];
	int length = strlen(input);
	if (length >= 2 && input[0] == '{' && input[length - 1] == '}') {
		strcopy(name, length - 1 < sizeof(name) ? length - 1 : sizeof(name), input[1]);
	} else {
		strcopy(name, sizeof(name), input);
	}
	TrimString(name);

	if (name[0] == '#') {
		return ParseHexColor(name[1], rgb);
	}

	for (int i; name[i]; i++) {
		name[i] = CharToLower(name[i]);
	}

	CCheckTrie();
	int value;
	if (!name[0] || !GetTrieValue(CTrie, name, value)) {
		return false;
	}
	rgb = value & WEAPON_PAINT_RGB_MASK;
	return true;
}

static bool ParseHexColor(const char[] hex, int &rgb) {
	if (strlen(hex) != 6) {
		return false;
	}
	for (int i; i < 6; i++) {
		if (!IsCharNumeric(hex[i]) && !(CharToLower(hex[i]) >= 'a' && CharToLower(hex[i]) <= 'f')) {
			return false;
		}
	}
	rgb = StringToInt(hex, 16) & WEAPON_PAINT_RGB_MASK;
	return true;
}

static int GetPaintChoice(int client, const char[] uid) {
	int choice;
	if (s_PaintChoices[client] && s_PaintChoices[client].GetValue(uid, choice)) {
		return choice;
	}
	return 0;
}

static void SetPaintChoice(int client, const char[] uid, int choice) {
	if (!uid[0]) {
		return;
	}
	if (!s_PaintChoices[client]) {
		s_PaintChoices[client] = new StringMap();
	}
	if (choice) {
		s_PaintChoices[client].SetValue(uid, choice);
	} else {
		s_PaintChoices[client].Remove(uid);
	}
	SavePaintChoices(client);
	RefreshLiveItemPaint(client, uid);
}

static void ResetPaintChoices(int client) {
	delete s_PaintChoices[client];
	s_PaintChoices[client] = new StringMap();
	s_PaintCookieChunksUsed[client] = 0;
}

/**
 * Repaints the client's currently spawned copy of the item (if any) and rebuilds the custom
 * model wearables so they pick up the new paint.
 */
static void RefreshLiveItemPaint(int client, const char[] uid) {
	if (!IsClientInGame(client)) {
		return;
	}
	CustomItemDefinition item;
	if (!GetCustomItemDefinition(uid, item)) {
		return;
	}
	int entity = FindClientItemEntity(client, uid);
	if (entity == -1) {
		return;
	}
	WeaponsPaint_ApplyToEntity(client, item, entity);
	QueueClientModelUpdate(client);
}

static int FindClientItemEntity(int client, const char[] uid) {
	for (int slot; slot <= TFWeaponSlot_Item2; slot++) {
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (EntityHasItemUID(weapon, uid)) {
			return weapon;
		}
	}
	int count = WeaponsUtil_GetPlayerWearableCount(client);
	for (int i; i < count; i++) {
		int wearable = WeaponsUtil_GetPlayerWearable(client, i);
		if (EntityHasItemUID(wearable, uid)) {
			return wearable;
		}
	}
	return -1;
}

static bool EntityHasItemUID(int entity, const char[] uid) {
	if (entity <= MaxClients || !IsValidEntity(entity)
			|| !HasEntProp(entity, Prop_Send, "m_AttributeList")) {
		return false;
	}
	Address attribute = WeaponsAttrib_GetByName(entity, ATTRIB_NAME_CUSTOM_UID);
	if (!attribute) {
		return false;
	}
	char entityUid[MAX_ITEM_IDENTIFIER_LENGTH];
	WeaponsAttrib_UnsafeGetStringValue(WeaponsAttrib_GetValue(attribute), entityUid, sizeof(entityUid));
	return StrEqual(entityUid, uid);
}

static void SetPaintAttributes(int entity, int choice) {
	if (choice & WEAPON_PAINT_CUSTOM_FLAG) {
		float value = float(choice & WEAPON_PAINT_RGB_MASK);
		WeaponsAttrib_SetByDefIndex(entity, WEAPON_PAINT_ATTRIB_RED, value);
		WeaponsAttrib_SetByDefIndex(entity, WEAPON_PAINT_ATTRIB_BLU, value);
	} else if (choice > 0) {
		ApplyPaint(entity, ClampPaintIndex(choice));
	} else {
		WeaponsAttrib_RemoveByDefIndex(entity, WEAPON_PAINT_ATTRIB_RED);
		WeaponsAttrib_RemoveByDefIndex(entity, WEAPON_PAINT_ATTRIB_BLU);
	}
}

static void CopyPaintAttribute(int from, int to, int defindex) {
	Address attribute = WeaponsAttrib_GetByDefIndex(from, defindex);
	if (attribute) {
		WeaponsAttrib_SetByDefIndex(to, defindex, WeaponsAttrib_GetValue(attribute));
	}
}

static void DescribePaintChoice(int choice, char[] buffer, int maxlen) {
	if (choice & WEAPON_PAINT_CUSTOM_FLAG) {
		int rgb = choice & WEAPON_PAINT_RGB_MASK;
		char colorName[32];
		if (FindChatColorName(rgb, colorName, sizeof(colorName))) {
			FormatEx(buffer, maxlen, "%s (#%06X)", colorName, rgb);
		} else {
			FormatEx(buffer, maxlen, "#%06X", rgb);
		}
		return;
	}
	CustomHats_GetPaintName(choice, buffer, maxlen);
}

static bool FindChatColorName(int rgb, char[] buffer, int maxlen) {
	CCheckTrie();
	StringMapSnapshot names = view_as<StringMap>(CTrie).Snapshot();
	bool found;
	char name[32];
	for (int i; i < names.Length && !found; i++) {
		names.GetKey(i, name, sizeof(name));
		int value;
		if (GetTrieValue(CTrie, name, value) && (value & WEAPON_PAINT_RGB_MASK) == rgb) {
			strcopy(buffer, maxlen, name);
			found = true;
		}
	}
	delete names;
	// black is stored as #000001 so it isn't mistaken for "unpainted"
	if (!found && rgb == 1) {
		strcopy(buffer, maxlen, "black");
		found = true;
	}
	return found;
}

static bool DecodePaintChoice(const char[] value, int &choice) {
	if (value[0] == '#') {
		int rgb;
		if (!ParseHexColor(value[1], rgb)) {
			return false;
		}
		choice = WEAPON_PAINT_CUSTOM_FLAG | (rgb ? rgb : 1);
		return true;
	}
	int paint;
	if (StringToIntEx(value, paint) != strlen(value) || paint < 0) {
		return false;
	}
	choice = ClampPaintIndex(paint);
	return true;
}

static void EncodePaintChoice(int choice, char[] buffer, int maxlen) {
	if (choice & WEAPON_PAINT_CUSTOM_FLAG) {
		FormatEx(buffer, maxlen, "#%06X", choice & WEAPON_PAINT_RGB_MASK);
	} else {
		IntToString(choice, buffer, maxlen);
	}
}

static void SavePaintChoices(int client) {
	if (!AreClientCookiesCached(client) || !s_PaintChoices[client]) {
		return;
	}

	char chunks[WEAPON_PAINT_COOKIE_CHUNKS][WEAPON_PAINT_COOKIE_LEN];
	int chunk;

	StringMapSnapshot uids = s_PaintChoices[client].Snapshot();
	char uid[MAX_ITEM_IDENTIFIER_LENGTH], value[16], entry[MAX_ITEM_IDENTIFIER_LENGTH + 16];
	for (int i; i < uids.Length; i++) {
		uids.GetKey(i, uid, sizeof(uid));
		int choice;
		if (!s_PaintChoices[client].GetValue(uid, choice) || !choice) {
			continue;
		}
		EncodePaintChoice(choice, value, sizeof(value));
		FormatEx(entry, sizeof(entry), "%s:%s", uid, value);

		int needed = strlen(chunks[chunk]) + strlen(entry) + (chunks[chunk][0] ? 1 : 0);
		if (needed >= sizeof(chunks[])) {
			if (++chunk >= WEAPON_PAINT_COOKIE_CHUNKS) {
				LogError("[Weapons] Cannot persist all weapon paints for %N: cookie limit reached.", client);
				chunk = WEAPON_PAINT_COOKIE_CHUNKS - 1;
				break;
			}
		}
		if (chunks[chunk][0]) {
			StrCat(chunks[chunk], sizeof(chunks[]), ",");
		}
		StrCat(chunks[chunk], sizeof(chunks[]), entry);
	}
	delete uids;

	int chunksUsed = chunks[0][0] ? chunk + 1 : 0;
	int chunksToWrite = chunksUsed > s_PaintCookieChunksUsed[client]
			? chunksUsed : s_PaintCookieChunksUsed[client];
	if (chunksToWrite == 0) {
		chunksToWrite = 1;
	}
	for (int i; i < chunksToWrite; i++) {
		s_PaintCookies[i].Set(client, i < chunksUsed ? chunks[i] : "");
	}
	s_PaintCookieChunksUsed[client] = chunksUsed;
}
