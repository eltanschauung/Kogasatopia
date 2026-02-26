#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <mapchooser>
#include <morecolors>

#pragma newdecls required
#pragma semicolon 1

#define PL_VERSION "3.0.0"

public Plugin myinfo =
{
	name = "Adverts",
	author = "Hombre, Tsunami",
	description = "Print advertisement messages in an interval",
	version = PL_VERSION,
	url = "https://kogasa.tf"
};

enum struct Advertisement
{
	char center[1024];
	char chat[2048];
	char hint[1024];
	char menu[1024];
	bool adminsOnly;
	bool hasFlags;
	int flags;
}

ArrayList g_Ads;
ConVar g_CvarEnabled, g_CvarFile, g_CvarInterval, g_CvarRandom, g_CvarPrefix;
Handle g_Timer;
int g_AdIndex;

public void OnPluginStart()
{
	CreateConVar("sm_adverts_version", PL_VERSION, "Display advertisements", FCVAR_NOTIFY);
	g_CvarEnabled = CreateConVar("sm_adverts_enabled", "1", "Enable/disable displaying advertisements.");
	g_CvarFile = CreateConVar("sm_adverts_file", "adverts.cfg", "File to read the advertisements from.");
	g_CvarInterval = CreateConVar("sm_adverts_interval", "600", "Number of seconds between advertisements.");
	g_CvarRandom = CreateConVar("sm_adverts_random", "1", "Enable/disable random advertisements.");
	g_CvarPrefix = CreateConVar("sm_adverts_prefix", "{gold}[Server]", "Prefix added before each chat advertisement (a space is appended automatically).");

	g_CvarFile.AddChangeHook(CvarChanged_File);
	g_CvarRandom.AddChangeHook(CvarChanged_Reload);
	g_CvarInterval.AddChangeHook(CvarChanged_Timer);

	g_Ads = new ArrayList(sizeof(Advertisement));
	RegServerCmd("sm_adverts_reload", Command_ReloadAds, "Reload the advertisements");
}

public void OnConfigsExecuted()
{
	LoadAdvertisements();
	RestartTimer();
}

public void OnPluginEnd()
{
	delete g_Timer;
	delete g_Ads;
}

public void CvarChanged_Reload(ConVar convar, const char[] oldValue, const char[] newValue)
{
	LoadAdvertisements();
}

public void CvarChanged_File(ConVar convar, const char[] oldValue, const char[] newValue)
{
	LoadAdvertisements();
}

public void CvarChanged_Timer(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RestartTimer();
}

public Action Command_ReloadAds(int args)
{
	LoadAdvertisements();
	return Plugin_Handled;
}

public int MenuHandler_Noop(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}

public Action Timer_DisplayAd(Handle timer)
{
	if (!g_CvarEnabled.BoolValue || !g_Ads.Length) {
		return Plugin_Continue;
	}

	Advertisement ad;
	g_Ads.GetArray(g_AdIndex, ad);

	char msg[1024], prefix[128];
	g_CvarPrefix.GetString(prefix, sizeof(prefix));

	if (ad.center[0]) {
		ProcessVariables(ad.center, msg, sizeof(msg));
		for (int i = 1; i <= MaxClients; i++) {
			if (CanSeeAd(i, ad)) {
				PrintCenterText(i, "%s", msg);
			}
		}
	}

	if (ad.chat[0]) {
		char lines[10][1024], tmp[1024];
		int count = ExplodeString(ad.chat, "\n", lines, sizeof(lines), sizeof(lines[]));
		for (int n = 0; n < count; n++) {
			ProcessVariables(lines[n], tmp, sizeof(tmp));
			FormatChatMessage(prefix, tmp, lines[n], sizeof(lines[]));
			PrintToServer("[Advertisements] %s", lines[n]);
		}
		for (int i = 1; i <= MaxClients; i++) {
			if (!CanSeeAd(i, ad)) {
				continue;
			}
			for (int n = 0; n < count; n++) {
				if (StrContains(lines[n], "{teamcolor}", false) != -1) {
					CPrintToChatEx(i, i, "%s", lines[n]);
				} else {
					CPrintToChat(i, "%s", lines[n]);
				}
			}
		}
	}

	if (ad.hint[0]) {
		ProcessVariables(ad.hint, msg, sizeof(msg));
		for (int i = 1; i <= MaxClients; i++) {
			if (CanSeeAd(i, ad)) {
				PrintHintText(i, "%s", msg);
			}
		}
	}

	if (ad.menu[0]) {
		ProcessVariables(ad.menu, msg, sizeof(msg));
		Panel panel = new Panel();
		panel.DrawText(msg);
		panel.CurrentKey = 10;
		for (int i = 1; i <= MaxClients; i++) {
			if (CanSeeAd(i, ad)) {
				panel.Send(i, MenuHandler_Noop, 10);
			}
		}
		delete panel;
	}

	if (++g_AdIndex >= g_Ads.Length) {
		g_AdIndex = 0;
	}
	return Plugin_Continue;
}

bool CanSeeAd(int client, Advertisement ad)
{
	if (!IsClientInGame(client) || IsFakeClient(client)) {
		return false;
	}

	int bits = GetUserFlagBits(client);
	if (ad.adminsOnly) {
		return (bits & (ADMFLAG_GENERIC | ADMFLAG_ROOT)) != 0;
	}
	if (ad.hasFlags) {
		return (bits & (ad.flags | ADMFLAG_ROOT)) == 0;
	}
	return true;
}

void LoadAdvertisements()
{
	g_AdIndex = 0;
	g_Ads.Clear();

	char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	g_CvarFile.GetString(file, sizeof(file));
	BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);
	if (!FileExists(path)) {
		SetFailState("File Not Found: %s", path);
		return;
	}

	KeyValues kv = new KeyValues("Advertisements");
	kv.SetEscapeSequences(true);
	if (!kv.ImportFromFile(path) || !kv.GotoFirstSubKey()) {
		delete kv;
		return;
	}

	char flags[22];
	do {
		Advertisement ad;
		kv.GetString("center", ad.center, sizeof(ad.center));
		kv.GetString("chat", ad.chat, sizeof(ad.chat));
		kv.GetString("hint", ad.hint, sizeof(ad.hint));
		kv.GetString("menu", ad.menu, sizeof(ad.menu));
		kv.GetString("flags", flags, sizeof(flags), "none");
		ad.adminsOnly = StrEqual(flags, "");
		ad.hasFlags = !StrEqual(flags, "none");
		ad.flags = ReadFlagString(flags);
		g_Ads.PushArray(ad);
	} while (kv.GotoNextKey());
	delete kv;

	if (g_CvarRandom.BoolValue) {
		ShuffleAdvertisements();
	}
}

void ShuffleAdvertisements()
{
	Advertisement a, b;
	for (int i = g_Ads.Length - 1; i > 0; i--) {
		int j = GetRandomInt(0, i);
		if (i == j) {
			continue;
		}
		g_Ads.GetArray(i, a);
		g_Ads.GetArray(j, b);
		g_Ads.SetArray(i, b);
		g_Ads.SetArray(j, a);
	}
}

void RestartTimer()
{
	delete g_Timer;
	int interval = g_CvarInterval.IntValue;
	if (interval > 0) {
		g_Timer = CreateTimer(float(interval), Timer_DisplayAd, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void FormatChatMessage(const char[] prefix, const char[] msg, char[] out, int maxlen)
{
	if (prefix[0]) {
		FormatEx(out, maxlen, "%s %s", prefix, msg);
	} else {
		strcopy(out, maxlen, msg);
	}
}

void ProcessVariables(const char[] src, char[] out, int maxlen)
{
	char name[64], value[256];
	int i, j, len;

	while (src[i] && j < maxlen - 1) {
		if (src[i] != '{' || (len = FindCharInString(src[i + 1], '}')) == -1) {
			out[j++] = src[i++];
			continue;
		}

		strcopy(name, len + 1, src[i + 1]);

		if (StrEqual(name, "currentmap", false)) {
			GetCurrentMap(value, sizeof(value));
			GetMapDisplayName(value, value, sizeof(value));
			j += strcopy(out[j], maxlen - j, value);
		} else if (StrEqual(name, "nextmap", false)) {
			if (LibraryExists("mapchooser") && EndOfMapVoteEnabled() && !HasEndOfMapVoteFinished()) {
				j += strcopy(out[j], maxlen - j, "Pending Vote");
			} else {
				GetNextMap(value, sizeof(value));
				GetMapDisplayName(value, value, sizeof(value));
				j += strcopy(out[j], maxlen - j, value);
			}
		} else if (StrEqual(name, "date", false)) {
			FormatTime(value, sizeof(value), "%m/%d/%Y");
			j += strcopy(out[j], maxlen - j, value);
		} else if (StrEqual(name, "time", false)) {
			FormatTime(value, sizeof(value), "%I:%M:%S%p");
			j += strcopy(out[j], maxlen - j, value);
		} else if (StrEqual(name, "time24", false)) {
			FormatTime(value, sizeof(value), "%H:%M:%S");
			j += strcopy(out[j], maxlen - j, value);
		} else if (StrEqual(name, "timeleft", false)) {
			int mins, secs, left;
			if (GetMapTimeLeft(left) && left > 0) {
				mins = left / 60;
				secs = left % 60;
			}
			j += FormatEx(out[j], maxlen - j, "%d:%02d", mins, secs);
		} else {
			ConVar cv = FindConVar(name);
			if (cv != null) {
				cv.GetString(value, sizeof(value));
				j += strcopy(out[j], maxlen - j, value);
			} else {
				j += FormatEx(out[j], maxlen - j, "{%s}", name);
			}
		}

		i += len + 2;
	}
	out[j] = '\0';
}
