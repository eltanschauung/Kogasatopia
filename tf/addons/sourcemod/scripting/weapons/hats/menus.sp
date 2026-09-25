static const char g_PaintNames[][48] =
{
	"No Paint",
	"A color similar to slate",
	"A deep commitment to purple",
	"A distinctive lack of hue",
	"A mann's mint",
	"After eight",
	"Aged Moustache Grey",
	"An Extraordinary abundance of tinge",
	"Australium gold",
	"Color no 216-190-216",
	"Dark salmon injustice",
	"Drably olive",
	"Indubitably green",
	"Mann co orange",
	"Muskelmannbraun",
	"Noble hatters violet",
	"Peculiarly drab tincture",
	"Pink as hell",
	"Radigan conagher brown",
	"A bitter taste of defeat and lime",
	"The color of a gentlemanns business pants",
	"Ye olde rustic colour",
	"Zepheniahs greed",
	"An air of debonair",
	"Balaclavas are forever",
	"Cream spirit",
	"Operators overalls",
	"Team spirit",
	"The value of teamwork",
	"Waterlogged lab coat"
};

int ClampPaintIndex(int paint)
{
	if (paint < 0)
	{
		return 0;
	}
	int maxPaint = sizeof(g_PaintNames) - 1;
	if (paint > maxPaint)
	{
		return maxPaint;
	}
	return paint;
}

void ShowHatMenu(int client)
{
	Menu menu = new Menu(MenuHandler_HatSlots);
	menu.SetTitle("Custom Hats");
	TFClassType playerClass = TF2_GetPlayerClass(client);
	int added = 0;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (g_Hats[i].force || !CanClientViewHatForClass(i, playerClass))
		{
			continue;
		}
		bool alreadyListed = false;
		for (int j = 0; j < i; j++)
		{
			if (!g_Hats[j].force && CanClientViewHatForClass(j, playerClass)
				&& StrEqual(g_Hats[i].slot, g_Hats[j].slot, false))
			{
				alreadyListed = true;
				break;
			}
		}
		if (alreadyListed)
		{
			continue;
		}
		menu.AddItem(g_Hats[i].slot, g_Hats[i].slot);
		added++;
	}
	if (added == 0)
	{
		delete menu;
		PrintToChat(client, "[Hats] No hats are available right now.");
		return;
	}
	menu.ExitBackButton = false;
	menu.Display(client, 20);
}

public int MenuHandler_HatSlots(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char slot[64];
		menu.GetItem(item, slot, sizeof(slot));
		ShowHatsInSlotMenu(client, slot);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void ShowHatsInSlotMenu(int client, const char[] slot)
{
	Menu menu = new Menu(MenuHandler_Hats);
	char title[96];
	Format(title, sizeof(title), "Custom Hats: %s", slot);
	menu.SetTitle(title);
	TFClassType playerClass = TF2_GetPlayerClass(client);
	int added = 0;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (g_Hats[i].force || !CanClientViewHatForClass(i, playerClass)
			|| !StrEqual(g_Hats[i].slot, slot, false))
		{
			continue;
		}
		char label[128];
		Format(label, sizeof(label), "%s%s%s",
			g_Hats[i].name,
			g_bHatEnabled[client][i] ? " [ON]" : "",
			CanClientAccessHat(client, i) ? "" : " [!Shop]");
		menu.AddItem(g_Hats[i].id, label);
		added++;
	}
	if (added == 0)
	{
		delete menu;
		ShowHatMenu(client);
		return;
	}
	menu.ExitBackButton = true;
	menu.Display(client, 20);
}

public int MenuHandler_Hats(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char itemId[64];
		menu.GetItem(item, itemId, sizeof(itemId));
		int hatIndex = FindHatIndexById(itemId);
		if (hatIndex < 0)
		{
			ShowHatMenu(client);
			return 0;
		}

		if (g_bHatEnabled[client][hatIndex])
		{
			SetClientHatEnabled(client, hatIndex, false);
			QueueHatStateSave(client, true);
			RemoveHat(client, hatIndex);
			PrintToChat(client, "[Hats] Disabled %s.", g_Hats[hatIndex].name);
			ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
			return 0;
		}

		if (!CanClientUseHatForClass(client, hatIndex, TF2_GetPlayerClass(client)))
		{
			PrintHatLockedMessage(client, hatIndex);
			ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
			return 0;
		}

		strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), itemId);
		EquipSelectedHatFromMenu(client, hatIndex);
		if (g_Hats[hatIndex].paintable)
		{
			ShowHatPaintMenu(client);
		}
		else
		{
			ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
		}
	}
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && Client_IsInGame(client))
	{
		ShowHatMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowHatPaintMenu(int client)
{
	Menu menu = new Menu(MenuHandler_HatPaint);
	menu.SetTitle("Select Paint");

	char key[8];
	for (int i = 0; i < sizeof(g_PaintNames); i++)
	{
		IntToString(i, key, sizeof(key));
		menu.AddItem(key, g_PaintNames[i]);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 20);
}

public int MenuHandler_HatPaint(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(item, info, sizeof(info));
		int paint = ClampPaintIndex(StringToInt(info));
		int hatIndex = GetSelectedHatIndex(client);
		if (hatIndex < 0)
		{
			return 0;
		}
		if (!g_Hats[hatIndex].paintable)
		{
			return 0;
		}
		if (!CanClientUseHatForClass(client, hatIndex, TF2_GetPlayerClass(client)))
		{
			PrintHatLockedMessage(client, hatIndex);
			RemoveHat(client, hatIndex);
			ShowHatMenu(client);
			return 0;
		}
		if (!g_bHatEnabled[client][hatIndex])
		{
			ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
			return 0;
		}
		g_iHatPaintChoice[client][hatIndex] = paint;
		QueueHatStateSave(client);
		EquipHat(client, hatIndex);
		PrintToChat(client, "[Hats] %s applied.", g_PaintNames[paint]);
		ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
	}
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && Client_IsInGame(client))
	{
		int hatIndex = GetSelectedHatIndex(client);
		if (hatIndex >= 0)
		{
			ShowHatsInSlotMenu(client, g_Hats[hatIndex].slot);
		}
		else
		{
			ShowHatMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void EquipSelectedHatFromMenu(int client, int hatIndex)
{
	SetClientHatEnabled(client, hatIndex, true, true);
	QueueHatStateSave(client);
	EquipHat(client, hatIndex);
	char color[32];
	GetHatChatColorForClientTeam(client, hatIndex, color, sizeof(color));
	CPrintToChat(client, "{gold}[CustomHats]{default} {%s}%s{default} equipped.",
		color, g_Hats[hatIndex].name);
}

