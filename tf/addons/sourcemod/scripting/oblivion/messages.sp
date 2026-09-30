void Messages_Start()
{
    static const char events[][] =
    {
        "player_connect", "player_connect_client", "player_disconnect", "player_team",
        "player_changename", "player_death", "player_hurt", "player_healed",
        "player_healonhit", "player_extinguished", "player_ignited", "player_say",
        "player_changeclass", "player_spawn", "player_builtobject", "player_upgradedobject",
        "object_destroyed", "object_detonated", "object_deflected", "player_teleported",
        "player_stunned", "player_jarated", "player_jarated_fade", "player_death_explosion",
        "item_found", "achievement_earned"
    };
    for (int i = 0; i < sizeof(events); i++)
    {
        if (HookEventEx(events[i], FilterEvent, EventHookMode_Pre))
            HookEvent(events[i], RelayFilteredEvent, EventHookMode_Post);
    }
    static const char messages[][] =
    {
        "SayText", "SayText2", "VoiceSubtitle", "PlayerJarated", "PlayerJaratedFade",
        "PlayerExtinguished", "PlayerIgnited", "PlayerIgnitedInv", "PlayerShieldBlocked"
    };
    for (int i = 0; i < sizeof(messages); i++)
    {
        UserMsg id = GetUserMessageId(messages[i]);
        if (id != INVALID_MESSAGE_ID) HookUserMessage(id, FilterMessage, true);
    }
    AddCommandListener(FilterSpectate, "spec_player");
}

bool EventHidden(Event event, int viewer)
{
    if (viewer < 1 || viewer > MaxClients || !g_HasRules[viewer]) return false;
    char name[64];
    event.GetName(name, sizeof(name));
    // These notifications carry an entity index, unlike the userids used by
    // death/chat events. They are rendered into chat by the client itself.
    if ((StrEqual(name, "item_found") || StrEqual(name, "achievement_earned"))
        && Hidden(viewer, event.GetInt("player", 0))) return true;
    static const char fields[][] = { "userid", "attacker", "assister", "healer", "patient", "victim", "ownerid", "builderid", "deflector", "stunner" };
    for (int i = 0; i < sizeof(fields); i++)
    {
        int userid = event.GetInt(fields[i], 0);
        if (userid && Hidden(viewer, GetClientOfUserId(userid))) return true;
    }
    char network[AUTH_LEN], auth[AUTH_LEN];
    event.GetString("networkid", network, sizeof(network));
    return CanonicalAuth(network, auth, sizeof(auth)) && HiddenAuth(viewer, auth);
}

public Action FilterEvent(Event event, const char[] name, bool dontBroadcast)
{
    if (dontBroadcast) return Plugin_Continue;
    bool needsFilter;
    for (int viewer = 1; viewer <= MaxClients; viewer++)
        if (IsClientInGame(viewer) && !IsFakeClient(viewer) && EventHidden(event, viewer)) needsFilter = true;
    if (!needsFilter) return Plugin_Continue;
    event.BroadcastDisabled = true;
    event.SetBool("oblivion_internal_filtered", true);
    // Wait for all pre-hooks, including custom weapon/kill-icon editors, before
    // sending the final event fields. The marker is not part of the wire schema.
    return Plugin_Continue;
}

public void RelayFilteredEvent(Event event, const char[] name, bool dontBroadcast)
{
    if (event == null || !event.GetBool("oblivion_internal_filtered", false)) return;
    for (int viewer = 1; viewer <= MaxClients; viewer++)
        if (IsClientInGame(viewer) && !IsFakeClient(viewer) && !EventHidden(event, viewer)) event.FireToClient(viewer);
}

public Action FilterMessage(UserMsg id, BfRead input, const int[] recipients, int count, bool reliable, bool init)
{
    int bytes = input.BytesLeft;
    if (bytes < 1 || bytes > 4096) return Plugin_Continue;
    char payload[4096];
    for (int i = 0; i < bytes; i++) payload[i] = input.ReadByte();
    int actor = payload[0];
    char name[64];
    GetUserMessageName(id, name, sizeof(name));
    int other;
    if (bytes > 1 && (StrContains(name, "PlayerJarated") == 0 || StrEqual(name, "PlayerExtinguished") || StrEqual(name, "PlayerIgnited")))
        other = payload[1];
    int kept[MAXPLAYERS], keptCount;
    for (int i = 0; i < count; i++)
        if (!Hidden(recipients[i], actor) && !Hidden(recipients[i], other)
            && !HiddenEntity(recipients[i], EffectSource())) kept[keptCount++] = recipients[i];
    if (keptCount == count) return Plugin_Continue;
    if (keptCount)
    {
        DataPack pack = new DataPack();
        pack.WriteCell(id);
        pack.WriteCell(reliable ? USERMSG_RELIABLE : 0);
        pack.WriteCell(keptCount);
        for (int i = 0; i < keptCount; i++) pack.WriteCell(GetClientSerial(kept[i]));
        pack.WriteCell(bytes);
        for (int i = 0; i < bytes; i++) pack.WriteCell(payload[i]);
        RequestFrame(RelayMessage, pack);
    }
    return Plugin_Handled;
}

public void RelayMessage(DataPack pack)
{
    pack.Reset();
    UserMsg id = view_as<UserMsg>(pack.ReadCell());
    int flags = pack.ReadCell() | USERMSG_BLOCKHOOKS;
    int oldCount = pack.ReadCell();
    int recipients[MAXPLAYERS], count;
    for (int i = 0; i < oldCount; i++)
    {
        int client = GetClientFromSerial(pack.ReadCell());
        if (client > 0 && IsClientInGame(client)) recipients[count++] = client;
    }
    int bytes = pack.ReadCell();
    if (count)
    {
        BfWrite output = view_as<BfWrite>(StartMessageEx(id, recipients, count, flags));
        if (output != null)
        {
            for (int i = 0; i < bytes; i++) output.WriteByte(pack.ReadCell());
            EndMessage();
        }
    }
    delete pack;
}

public Action FilterSpectate(int client, const char[] command, int argc)
{
    if (client <= 0 || argc < 1) return Plugin_Continue;
    char target[64];
    GetCmdArg(1, target, sizeof(target));
    int slot = StringToInt(target);
    return Hidden(client, slot) ? Plugin_Handled : Plugin_Continue;
}
