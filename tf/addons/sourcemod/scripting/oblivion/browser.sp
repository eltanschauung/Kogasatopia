ConVar g_BrowserEnabled;
int g_BrowserPort;
float g_BrowserConnectedAt[MAXPLAYERS + 1];
enum struct BrowserAddress
{
    char auth[AUTH_LEN];
    char ip[16];
}
ArrayList g_BrowserAddresses;
char g_BrowserStore[PLATFORM_MAX_PATH];

bool Browser_ValidIp(const char[] ip)
{
    int parts, value, digits;
    bool nonzero;
    for (int i = 0; ; i++)
    {
        if (ip[i] >= '0' && ip[i] <= '9')
        {
            value = value * 10 + ip[i] - '0';
            if (++digits > 3 || value > 255) return false;
        }
        else if (ip[i] == '.' || !ip[i])
        {
            if (!digits || ++parts > 4) return false;
            nonzero = nonzero || value != 0;
            if (!ip[i]) return parts == 4 && nonzero;
            value = 0;
            digits = 0;
        }
        else return false;
    }
}

bool Browser_HasRules(const char[] auth)
{
    Pair pair;
    for (int i = 0; i < g_Pairs.Length; i++)
    {
        g_Pairs.GetArray(i, pair);
        if (StrEqual(pair.viewer, auth)) return true;
    }
    return false;
}

int Browser_AddressIndex(const char[] auth)
{
    BrowserAddress address;
    for (int i = 0; i < g_BrowserAddresses.Length; i++)
    {
        g_BrowserAddresses.GetArray(i, address);
        if (StrEqual(address.auth, auth)) return i;
    }
    return -1;
}

void Browser_LoadAddresses()
{
    char backup[PLATFORM_MAX_PATH];
    FormatEx(backup, sizeof(backup), "%s.bak", g_BrowserStore);
    if (!FileExists(g_BrowserStore) && FileExists(backup))
        if (!RenameFile(g_BrowserStore, backup)) SetFailState("Cannot restore browser IP data.");
    if (!FileExists(g_BrowserStore)) return;
    KeyValues kv = new KeyValues("OblivionBrowserIPs");
    if (!kv.ImportFromFile(g_BrowserStore))
    {
        delete kv;
        SetFailState("Cannot read %s; saved IP data preserved.", g_BrowserStore);
        return;
    }
    if (kv.GotoFirstSubKey())
    {
        do
        {
            BrowserAddress address;
            char rawAuth[128], rawIp[64];
            kv.GetString("viewer", rawAuth, sizeof(rawAuth));
            kv.GetString("ip", rawIp, sizeof(rawIp));
            if (!CanonicalAuth(rawAuth, address.auth, AUTH_LEN) || !Browser_ValidIp(rawIp)
                || Browser_AddressIndex(address.auth) >= 0)
            {
                delete kv;
                SetFailState("Invalid browser IP data in %s; file preserved.", g_BrowserStore);
                return;
            }
            strcopy(address.ip, sizeof(address.ip), rawIp);
            g_BrowserAddresses.PushArray(address);
        } while (kv.GotoNextKey());
    }
    delete kv;
}

bool Browser_SaveAddresses()
{
    KeyValues kv = new KeyValues("OblivionBrowserIPs");
    BrowserAddress address;
    char key[16];
    for (int i = 0; i < g_BrowserAddresses.Length; i++)
    {
        g_BrowserAddresses.GetArray(i, address);
        IntToString(i, key, sizeof(key));
        kv.JumpToKey(key, true);
        kv.SetString("viewer", address.auth);
        kv.SetString("ip", address.ip);
        kv.GoBack();
    }
    kv.Rewind();
    char temporary[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
    FormatEx(temporary, sizeof(temporary), "%s.tmp", g_BrowserStore);
    FormatEx(backup, sizeof(backup), "%s.bak", g_BrowserStore);
    bool written = kv.ExportToFile(temporary);
    delete kv;
    if (!written) return false;
    bool previous = FileExists(g_BrowserStore);
    if (previous)
    {
        if (FileExists(backup) && !DeleteFile(backup)) return false;
        if (!RenameFile(backup, g_BrowserStore)) return false;
    }
    if (RenameFile(g_BrowserStore, temporary)) return true;
    if (previous && !RenameFile(g_BrowserStore, backup)) LogError("Cannot restore browser IP backup %s", backup);
    return false;
}

void Browser_RefreshAddresses()
{
    bool changed;
    BrowserAddress address;
    // Removing the last SteamID rule also removes the remembered address.
    for (int i = g_BrowserAddresses.Length - 1; i >= 0; i--)
    {
        g_BrowserAddresses.GetArray(i, address);
        if (!Browser_HasRules(address.auth)) { g_BrowserAddresses.Erase(i); changed = true; }
    }
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientConnected(client) || g_BrowserDisconnecting[client]
            || !g_Auth[client][0] || !Browser_HasRules(g_Auth[client])) continue;
        char ip[64];
        // Pending connection identities must never overwrite an authenticated IP.
        if (!IsFakeClient(client) && IsClientAuthorized(client)) GetClientIP(client, ip, sizeof(ip), true);
        if (!Browser_ValidIp(ip)) continue;
        int index = Browser_AddressIndex(g_Auth[client]);
        if (index >= 0)
        {
            g_BrowserAddresses.GetArray(index, address);
            if (StrEqual(address.ip, ip)) continue;
        }
        strcopy(address.auth, sizeof(address.auth), g_Auth[client]);
        strcopy(address.ip, sizeof(address.ip), ip);
        if (index >= 0) g_BrowserAddresses.SetArray(index, address);
        else g_BrowserAddresses.PushArray(address);
        changed = true;
    }
    if (changed && !Browser_SaveAddresses())
        LogError("Browser IP data is active in memory but could not be saved to %s.", g_BrowserStore);
}

void Browser_Start()
{
    g_BrowserAddresses = new ArrayList(sizeof(BrowserAddress));
    BuildPath(Path_SM, g_BrowserStore, sizeof(g_BrowserStore), "data/oblivion_browser_ips.kv");
    Browser_LoadAddresses();
    g_BrowserPort = GetCommandLineParamInt("-port", FindConVar("hostport").IntValue);
    g_BrowserEnabled = CreateConVar("sm_oblivion_browser", "1", "Apply Oblivion rules to browser queries from viewers' last authenticated IPs, including after disconnect.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_BrowserEnabled.AddChangeHook(Browser_Changed);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client)) g_BrowserConnectedAt[client] = GetEngineTime();
}

public void Browser_Changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
    Browser_Publish();
}

void Browser_Publish()
{
    if (!g_Ready || g_BrowserEnabled == null) return;
    Browser_RefreshAddresses();
    OblivionNet_BrowserBegin(g_BrowserEnabled.BoolValue, g_BrowserPort);
    if (!g_BrowserEnabled.BoolValue) { OblivionNet_BrowserCommit(); return; }
    bool included[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientConnected(client) || g_BrowserDisconnecting[client]) continue;
        char name[MAX_NAME_LENGTH], ip[64];
        GetClientName(client, name, sizeof(name));
        bool bot = IsFakeClient(client);
        if (!bot && IsClientAuthorized(client) && g_Auth[client][0])
            GetClientIP(client, ip, sizeof(ip), true);
        // Source's ordinary game/browser transports use IPv4. Unsupported or
        // unresolved addresses remain anonymous instead of inheriting old IPs.
        if (StrContains(ip, ":") != -1 || StrEqual(ip, "loopback")) ip[0] = '\0';
        int score = g_MapActive && IsClientInGame(client) && IsValidEntity(client) ? GetClientFrags(client) : 0;
        float seconds = bot ? GetEngineTime() - g_BrowserConnectedAt[client] : GetClientTime(client);
        OblivionNet_BrowserPlayer(client, ip, name, score, seconds, bot);
        included[client] = true;
    }
    for (int viewer = 1; viewer <= MaxClients; viewer++)
        if (included[viewer] && g_HasRules[viewer])
            for (int subject = 1; subject <= MaxClients; subject++)
                if (included[subject] && Hidden(viewer, subject)) OblivionNet_BrowserHide(viewer, subject);
    // Re-resolve subjects from SteamID on every snapshot, never from a saved
    // client slot. Offline viewers need no artificial player-list entry.
    BrowserAddress address;
    for (int i = 0; i < g_BrowserAddresses.Length; i++)
    {
        g_BrowserAddresses.GetArray(i, address);
        for (int subject = 1; subject <= MaxClients; subject++)
            if (included[subject] && g_Auth[subject][0] && PairIndex(address.auth, g_Auth[subject]) >= 0)
                OblivionNet_BrowserHideAddress(address.ip, subject);
    }
    OblivionNet_BrowserCommit();
}

void Browser_Status(int client)
{
    int addresses, requests, lists, filtered, rows, infos;
    bool ready = OblivionNet_BrowserStatus(addresses, requests, lists, filtered, rows, infos);
    int sent, errors; OblivionNet_BrowserTransport(sent, errors);
    ReplyToCommand(client, "[Oblivion] Browser: %s; hooks=%s; %d active IPs; %d/%d lists filtered; %d rows hidden; %d counts adjusted.",
        g_BrowserEnabled.BoolValue ? "on" : "off", ready ? "ready" : "waiting for Steam", addresses, filtered, lists, rows, infos);
    ReplyToCommand(client, "[Oblivion] Browser transport: port=%d; %d datagrams sent; %d send fallbacks.", g_BrowserPort, sent, errors);
    ReplyToCommand(client, "[Oblivion] Browser IPs: %d remembered viewers; retained after disconnect and saved across restarts.", g_BrowserAddresses.Length);
}

public void OnClientSettingsChanged(int client)
{
    Browser_Publish();
}
