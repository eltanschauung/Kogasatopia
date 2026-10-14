enum struct DeathEventSaySound
{
    bool available;
    bool played;
    bool publicPlayback;
    int source;
    int initiator;
    char path[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char command[MAX_COMMAND_NAME];
    bool fromGroup;
    char sourceGroup[MAX_GROUP_NAME];
}

static void ResolveDeathEventSaySound(int client, const char[] command, DeathEventSaySound sound)
{
    sound.source = client;
    sound.initiator = client;
    bool restricted, paidRestricted;
    sound.available = GetCommandSoundDataForClientEx(client, command,
        sound.path, PLATFORM_MAX_PATH, sound.groupName, MAX_GROUP_NAME,
        restricted, paidRestricted, sound.command, MAX_COMMAND_NAME,
        sound.fromGroup, sound.sourceGroup, MAX_GROUP_NAME);
}

static bool PlayDeathEventSaySoundToClient(DeathEventSaySound sound, int client)
{
    if (!sound.available || client <= 0)
        return false;

    bool played = PlaySaySoundToTarget(client, sound.path, sound.groupName, false, sound.initiator);
    sound.played = sound.played || played;
    return played;
}

static bool PlayDeathEventSaySoundToOthers(DeathEventSaySound sound, int victim, int attacker)
{
    bool played;
    for (int client = 1; client <= MaxClients; client++)
    {
        // Participants never receive the shared selection on top of their own.
        if (client == victim || client == attacker)
            continue;
        if (PlayDeathEventSaySoundToClient(sound, client))
            played = true;
    }
    sound.publicPlayback = sound.publicPlayback || played;
    return played;
}

static bool CanHearDeathEventSaySound(DeathEventSaySound sound, int client)
{
    float emitVolume;
    return sound.available
        && CanPlaySaySoundToClient(client, sound.groupName, emitVolume)
        && !Oblivion_ShouldHide(client, sound.initiator);
}

static void LogDeathEventSaySound(DeathEventSaySound sound, const char[] eventName, const char[] kind)
{
    if (!sound.played)
        return;
    // One usage per resolved sound/event, even if both personal and public.
    LogSaySoundUsage(eventName, sound.source, sound.publicPlayback ? 0 : sound.source,
        sound.command, sound.path, sound.groupName, sound.fromGroup, sound.sourceGroup, false, kind);
}

void LoadDeathSoundPreference(int client)
{
    g_szDeathSound[client][0] = '\0';

    if (g_hDeathCookie == INVALID_HANDLE)
    {
        return;
    }

    char value[MAX_COMMAND_NAME * 4];
    GetClientCookie(client, g_hDeathCookie, value, sizeof(value));
    TrimString(value);
    Strings_ToLower(value, sizeof(value));

    if (!value[0])
    {
        return;
    }

    strcopy(g_szDeathSound[client], sizeof(g_szDeathSound[]), value);
}

void SaveDeathSoundPreference(int client)
{
    if (g_hDeathCookie == INVALID_HANDLE || !AreClientCookiesCached(client))
        return;

    SetClientCookie(client, g_hDeathCookie, g_szDeathSound[client]);
}

void LoadKillSoundPreference(int client)
{
    g_szKillSound[client][0] = '\0';

    if (g_hKillCookie == INVALID_HANDLE)
    {
        return;
    }

    char value[MAX_COMMAND_NAME * 4];
    GetClientCookie(client, g_hKillCookie, value, sizeof(value));
    TrimString(value);
    Strings_ToLower(value, sizeof(value));

    if (!value[0])
    {
        return;
    }

    strcopy(g_szKillSound[client], sizeof(g_szKillSound[]), value);
}

void SaveKillSoundPreference(int client)
{
    if (g_hKillCookie == INVALID_HANDLE || !AreClientCookiesCached(client))
        return;

    SetClientCookie(client, g_hKillCookie, g_szKillSound[client]);
}

public void Event_PlayerDeathPost(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    DeathEventSaySound deathSound, killSound, weaponSound;
    bool explicitDeathPreference;

    if (attacker > 0 && attacker <= MaxClients && attacker != victim
        && IsClientInGame(attacker) && g_szKillSound[attacker][0])
    {
        ResolveDeathEventSaySound(attacker, g_szKillSound[attacker], killSound);
    }

    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
    {
        explicitDeathPreference = g_szDeathSound[victim][0] != '\0';
        if (explicitDeathPreference)
        {
            ResolveDeathEventSaySound(victim, g_szDeathSound[victim], deathSound);
        }
        else
        {
            // The victim's personal default is independent of the killer's preference.
            char command[MAX_COMMAND_NAME * 4];
            GetDefaultDeathSound(command, sizeof(command));
            if (command[0])
                ResolveDeathEventSaySound(victim, command, deathSound);
        }
    }

    PlayDeathEventSaySoundToClient(deathSound, victim);
    if (attacker != victim)
        PlayDeathEventSaySoundToClient(killSound, attacker);

    bool weaponHandled = PlayWeaponKillSaySoundForOthers(attacker, victim, weaponSound);
    if (!weaponHandled)
    {
        // Preserve the old public fallback: a default death sound only competes
        // when no killer sound resolved. Explicit death sounds keep the 50/50 draw.
        bool publicDeath = deathSound.available && (explicitDeathPreference || !killSound.available);
        if (publicDeath && killSound.available)
        {
            if (GetRandomInt(0, 1) == 0)
                PlayDeathEventSaySoundToOthers(deathSound, victim, attacker);
            else
                PlayDeathEventSaySoundToOthers(killSound, victim, attacker);
        }
        else if (publicDeath)
        {
            PlayDeathEventSaySoundToOthers(deathSound, victim, attacker);
        }
        else if (killSound.available)
        {
            PlayDeathEventSaySoundToOthers(killSound, victim, attacker);
        }
    }

    LogDeathEventSaySound(deathSound, "diesound_used", "diesound");
    LogDeathEventSaySound(killSound, "killsound_used", "killsound");
    LogDeathEventSaySound(weaponSound, "weapon_killsound_used", "weapon_killsound");
}

void GetDefaultDeathSound(char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (g_hDefaultDeathSound != null)
    {
        g_hDefaultDeathSound.GetString(buffer, maxlen);
        TrimString(buffer);
    }
}

static bool GetWeaponKillSaySoundCommand(int attacker, int victim, char[] commandName, int maxlen)
{
    if (maxlen > 0)
    {
        commandName[0] = '\0';
    }

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Weapons_GetKillingWeapon") != FeatureStatus_Available)
    {
        return false;
    }

    int weapon = Weapons_GetKillingWeapon(attacker, victim);
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return false;
    }

    TF2CustAttr_GetString(weapon, SAYSOUND_ON_KILL_ATTR, commandName, maxlen);
    TrimString(commandName);
    Strings_ToLower(commandName, maxlen);

    return commandName[0] != '\0';
}

static bool PlayWeaponKillSaySoundForOthers(int attacker, int victim, DeathEventSaySound sound)
{
    if (attacker == victim)
        return false;
    char command[MAX_COMMAND_NAME * 4];
    if (!GetWeaponKillSaySoundCommand(attacker, victim, command, sizeof(command)))
        return false;

    ResolveDeathEventSaySound(attacker, command, sound);
    if (!sound.available)
        return false;

    // Weapon-attribute broadcasts historically had no initiating client.
    sound.initiator = 0;
    PrecacheSound(sound.path, true);
    if (PlayDeathEventSaySoundToOthers(sound, victim, attacker))
        return true;

    // Keep the old global override/fallback decision even when its only eligible
    // listeners were participants, who now hear their personal preferences.
    return CanHearDeathEventSaySound(sound, victim) || CanHearDeathEventSaySound(sound, attacker);
}
