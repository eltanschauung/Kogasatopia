// Slot membership is parsed once when a hat is registered. Wearable refreshes
// never tokenize configuration strings or allocate per-client slot state.
bool CustomHats_ParseSlots(int hatIndex, const char[] list)
{
	g_iHatSlotCount[hatIndex] = 0;
	int start = 0;
	int length = strlen(list);
	if (length >= HAT_SLOT_LIST_MAX) return false;
	for (int position = 0; position <= length; position++)
	{
		if (list[position] != ',' && list[position] != '\0') continue;
		char token[HAT_SLOT_LIST_MAX];
		strcopy(token, sizeof(token), list[start]);
		token[position - start] = '\0';
		start = position + 1;
		TrimString(token);
		Strings_ToLower(token, sizeof(token));
		if (!token[0]) continue;
		if (strlen(token) >= HAT_SLOT_NAME_MAX) return false;
		if (CustomHats_HasSlot(hatIndex, token)) continue;
		int count = g_iHatSlotCount[hatIndex];
		if (count >= HAT_MAX_SLOTS) return false;
		strcopy(g_szHatSlots[hatIndex][count], HAT_SLOT_NAME_MAX, token);
		g_iHatSlotCount[hatIndex]++;
	}
	if (g_iHatSlotCount[hatIndex] == 0)
	{
		strcopy(g_szHatSlots[hatIndex][0], HAT_SLOT_NAME_MAX, "default");
		g_iHatSlotCount[hatIndex] = 1;
	}
	return true;
}

bool CustomHats_HasSlot(int hatIndex, const char[] slot)
{
	for (int i = 0; i < g_iHatSlotCount[hatIndex]; i++)
		if (StrEqual(g_szHatSlots[hatIndex][i], slot, false)) return true;
	return false;
}

// Return the first hat's matching slot index, for a precise conflict message.
int CustomHats_FindSharedSlot(int first, int second)
{
	for (int i = 0; i < g_iHatSlotCount[first]; i++)
		if (CustomHats_HasSlot(second, g_szHatSlots[first][i])) return i;
	return -1;
}
