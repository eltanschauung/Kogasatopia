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
	Menu menu = new Menu(MenuHandler_Hats);
	menu.SetTitle("Custom Hats");
	TFClassType playerClass = TF2_GetPlayerClass(client);
	int added = 0;
	for (int i = 0; i < g_iHatCount; i++)
	{
		if (g_Hats[i].force || !CanClientViewHatForClass(i, playerClass))
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
		PrintToChat(client, "[Hats] No hats are available right now.");
		return;
	}
	menu.ExitBackButton = false;
	menu.Display(client, 20);
}

public int MenuHandler_Hats(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char itemId[64];
		menu.GetItem(item, itemId, sizeof(itemId));
		strcopy(g_szHatIdChoice[client], sizeof(g_szHatIdChoice[]), itemId);
		int hatIndex = FindHatIndexById(itemId);
		if (hatIndex < 0 || !CanClientUseHatForClass(client, hatIndex, TF2_GetPlayerClass(client)))
		{
			PrintHatLockedMessage(client, hatIndex);
			ShowHatMenu(client);
			return 0;
		}
		if (hatIndex >= 0)
		{
			g_iHatPaintChoice[client][hatIndex] = ClampPaintIndex(g_Hats[hatIndex].defaultPaint);
		}
		ShowHatToggleMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowHatToggleMenu(int client)
{
	int hatIndex = GetSelectedHatIndex(client);
	if (hatIndex >= 0 && !CanClientUseHatForClass(client, hatIndex, TF2_GetPlayerClass(client)))
	{
		PrintHatLockedMessage(client, hatIndex);
		ShowHatMenu(client);
		return;
	}

	Menu menu = new Menu(MenuHandler_HatToggle);
	if (hatIndex >= 0)
	{
		menu.SetTitle(g_Hats[hatIndex].name);
	}
	else
	{
		menu.SetTitle("Custom Hat");
	}
	menu.AddItem("enable", "1. Enable");
	menu.AddItem("disable", "2. Disable");
	if (hatIndex >= 0 && g_Hats[hatIndex].paintable)
	{
		menu.AddItem("paint", "3. Paint");
	}
	menu.ExitBackButton = true;
	menu.Display(client, 20);
}

public int MenuHandler_HatToggle(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		int hatIndex = GetSelectedHatIndex(client);
		if (hatIndex < 0)
		{
			return 0;
		}
		if (!CanClientUseHatForClass(client, hatIndex, TF2_GetPlayerClass(client)))
		{
			PrintHatLockedMessage(client, hatIndex);
			RemoveHat(client, hatIndex, false);
			ShowHatMenu(client);
			return 0;
		}

		if (StrEqual(info, "enable"))
		{
			SetClientHatEnabled(client, hatIndex, true);
			QueueHatStateSave(client);
			if (g_Hats[hatIndex].paintable)
			{
				ShowHatPaintMenu(client);
			}
			else
			{
				EquipHat(client, hatIndex);
			}
		}
		else if (StrEqual(info, "disable"))
		{
			SetClientHatEnabled(client, hatIndex, false);
			QueueHatStateSave(client, true);
			RemoveHat(client, hatIndex);
			PrintToChat(client, "[Hats] Disabled %s.", g_Hats[hatIndex].name);
		}
		else if (StrEqual(info, "paint"))
		{
			ShowHatPaintMenu(client);
		}
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
			RemoveHat(client, hatIndex, false);
			ShowHatMenu(client);
			return 0;
		}
		g_iHatPaintChoice[client][hatIndex] = paint;
		SetClientHatEnabled(client, hatIndex, true);
		QueueHatStateSave(client);

		EquipHat(client, hatIndex);
		PrintToChat(client, "[Hats] %s applied.", g_PaintNames[paint]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

