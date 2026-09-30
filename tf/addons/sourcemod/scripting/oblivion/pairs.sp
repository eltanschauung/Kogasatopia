bool CanonicalAuth(const char[] input, char[] output, int size)
{
    output[0] = '\0';
    if (StrContains(input, "[U:1:", false) == 0)
    {
        int length = strlen(input);
        if (length < 7 || length > 16 || input[length - 1] != ']') return false;
        int account;
        for (int i = 5; i < length - 1; i++)
        {
            if (input[i] < '0' || input[i] > '9') return false;
            account = account * 10 + input[i] - '0';
        }
        FormatEx(output, size, "STEAM_0:%d:%d", account & 1, account >>> 1);
        return true;
    }
    if (StrContains(input, "STEAM_", false) != 0) return false;
    char pieces[3][24];
    if (ExplodeString(input, ":", pieces, sizeof(pieces), sizeof(pieces[])) != 3) return false;
    if (!StrEqual(pieces[0], "STEAM_0", false) && !StrEqual(pieces[0], "STEAM_1", false)) return false;
    if (!StrEqual(pieces[1], "0") && !StrEqual(pieces[1], "1")) return false;
    int len = strlen(pieces[2]);
    if (len < 1 || len > 10) return false;
    for (int i = 0; i < len; i++) if (pieces[2][i] < '0' || pieces[2][i] > '9') return false;
    FormatEx(output, size, "STEAM_0:%s:%s", pieces[1], pieces[2]);
    return true;
}

int PairIndex(const char[] viewer, const char[] subject)
{
    Pair pair;
    for (int i = 0; i < g_Pairs.Length; i++)
    {
        g_Pairs.GetArray(i, pair);
        if (StrEqual(pair.viewer, viewer) && StrEqual(pair.subject, subject)) return i;
    }
    return -1;
}

bool HiddenAuth(int viewer, const char[] subject)
{
    return viewer > 0 && viewer <= MaxClients && g_Auth[viewer][0] && PairIndex(g_Auth[viewer], subject) >= 0;
}

void LoadPairs()
{
    char backup[PLATFORM_MAX_PATH];
    FormatEx(backup, sizeof(backup), "%s.bak", g_Store);
    if (!FileExists(g_Store) && FileExists(backup))
    {
        if (!RenameFile(g_Store, backup)) SetFailState("Unable to restore the last saved Oblivion pairings.");
        LogMessage("Restored Oblivion pairings after an interrupted file replacement.");
    }
    if (!FileExists(g_Store)) return;
    KeyValues kv = new KeyValues("Oblivion");
    if (!kv.ImportFromFile(g_Store))
    {
        delete kv;
        SetFailState("Could not read %s; refusing to overwrite stored pairings.", g_Store);
        return;
    }
    if (kv.GotoFirstSubKey())
    {
        do
        {
            Pair pair;
            char raw[AUTH_LEN];
            kv.GetString("viewer", raw, sizeof(raw));
            if (!CanonicalAuth(raw, pair.viewer, AUTH_LEN))
            {
                delete kv;
                SetFailState("Invalid viewer identity in %s; stored data has been preserved.", g_Store);
                return;
            }
            kv.GetString("subject", raw, sizeof(raw));
            if (!CanonicalAuth(raw, pair.subject, AUTH_LEN) || StrEqual(pair.viewer, pair.subject))
            {
                delete kv;
                SetFailState("Invalid subject identity in %s; stored data has been preserved.", g_Store);
                return;
            }
            if (PairIndex(pair.viewer, pair.subject) < 0) g_Pairs.PushArray(pair);
        } while (kv.GotoNextKey());
    }
    delete kv;
}

bool SavePairs()
{
    KeyValues kv = new KeyValues("Oblivion");
    Pair pair;
    char key[16];
    for (int i = 0; i < g_Pairs.Length; i++)
    {
        g_Pairs.GetArray(i, pair);
        IntToString(i, key, sizeof(key));
        kv.JumpToKey(key, true);
        kv.SetString("viewer", pair.viewer);
        kv.SetString("subject", pair.subject);
        kv.GoBack();
    }
    kv.Rewind();
    char temporary[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
    FormatEx(temporary, sizeof(temporary), "%s.tmp", g_Store);
    FormatEx(backup, sizeof(backup), "%s.bak", g_Store);
    bool written = kv.ExportToFile(temporary);
    delete kv;
    if (!written) return false;
    bool previous = FileExists(g_Store);
    if (previous)
    {
        if (FileExists(backup) && !DeleteFile(backup)) return false;
        if (!RenameFile(backup, g_Store)) return false;
    }
    if (RenameFile(g_Store, temporary)) return true;
    if (previous && !RenameFile(g_Store, backup)) LogError("Failed to restore pairings backup %s", backup);
    return false;
}

void RebuildPairs()
{
    Pair pair;
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        g_HasRules[viewer] = false;
        for (int subject = 1; subject <= MaxClients; subject++)
        {
            bool wasHidden = g_Hidden[viewer][subject];
            g_Hidden[viewer][subject] = viewer != subject && g_Auth[viewer][0] && g_Auth[subject][0]
                && PairIndex(g_Auth[viewer], g_Auth[subject]) >= 0;
            if (!wasHidden && g_Hidden[viewer][subject] && g_MapActive) SilenceExistingLoops(viewer, subject);
        }
        for (int i = 0; i < g_Pairs.Length; i++)
        {
            g_Pairs.GetArray(i, pair);
            if (g_Auth[viewer][0] && StrEqual(g_Auth[viewer], pair.viewer)) g_HasRules[viewer] = true;
        }
    }
    if (g_MapActive) Roster_Update();
    if (g_MapActive) Teams_Update();
    if (g_MapActive) ClearBlockedConditions();
    Browser_Publish();
    Call_StartForward(g_StateChanged);
    Call_Finish();
}

bool ResolveIdentity(int admin, const char[] target, char[] auth, int maxlen)
{
    if (CanonicalAuth(target, auth, maxlen)) return true;
    int client = FindTarget(admin, target, true, false);
    if (client < 1) return false;
    if (!IsClientAuthorized(client) || !g_Auth[client][0])
    {
        ReplyToCommand(admin, "[Oblivion] That player does not have an authenticated SteamID yet.");
        return false;
    }
    strcopy(auth, maxlen, g_Auth[client]);
    return true;
}

public Action Command_Oblivion(int client, int args)
{
    if (args < 2 || args > 3)
    {
        ReplyToCommand(client, "Usage: sm_oblivion <viewer name/#userid/Steam2 ID> <hidden player> [on|off]");
        return Plugin_Handled;
    }
    char first[128], second[128], mode[16];
    GetCmdArg(1, first, sizeof(first));
    GetCmdArg(2, second, sizeof(second));
    if (args == 3) GetCmdArg(3, mode, sizeof(mode));
    else strcopy(mode, sizeof(mode), "on");
    if (!StrEqual(mode, "on", false) && !StrEqual(mode, "off", false))
    {
        ReplyToCommand(client, "[Oblivion] Use on or off.");
        return Plugin_Handled;
    }
    Pair pair;
    if (!ResolveIdentity(client, first, pair.viewer, AUTH_LEN) || !ResolveIdentity(client, second, pair.subject, AUTH_LEN)) return Plugin_Handled;
    if (StrEqual(pair.viewer, pair.subject))
    {
        ReplyToCommand(client, "[Oblivion] Choose two different players.");
        return Plugin_Handled;
    }
    int index = PairIndex(pair.viewer, pair.subject);
    bool enabled = StrEqual(mode, "on", false);
    if ((index >= 0) == enabled)
    {
        ReplyToCommand(client, "[Oblivion] This pairing is already %s.", enabled ? "enabled" : "disabled");
        return Plugin_Handled;
    }
    if (enabled) g_Pairs.PushArray(pair);
    else g_Pairs.Erase(index);
    if (!SavePairs())
    {
        if (enabled) g_Pairs.Erase(g_Pairs.Length - 1);
        else g_Pairs.PushArray(pair);
        ReplyToCommand(client, "[Oblivion] Could not save pairings; the change was not applied.");
        LogError("Failed to save %s", g_Store);
        return Plugin_Handled;
    }
    RebuildPairs();
    LogAction(client, -1, "Oblivion %s: viewer=%s subject=%s", mode, pair.viewer, pair.subject);
    ReplyToCommand(client, "[Oblivion] %s -> %s: %s (saved).", pair.viewer, pair.subject, mode);
    return Plugin_Handled;
}

public Action Command_List(int client, int args)
{
    ReplyToCommand(client, "[Oblivion] %d saved pairings (viewer -> hidden player):", g_Pairs.Length);
    Pair pair;
    for (int i = 0; i < g_Pairs.Length; i++)
    {
        g_Pairs.GetArray(i, pair);
        ReplyToCommand(client, "%s -> %s", pair.viewer, pair.subject);
    }
    return Plugin_Handled;
}
