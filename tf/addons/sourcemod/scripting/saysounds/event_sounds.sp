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

    if (attacker > 0 && attacker != victim && PlayWeaponKillSaySound(attacker, victim))
    {
        return;
    }

    char victimPath[PLATFORM_MAX_PATH];
    char attackerPath[PLATFORM_MAX_PATH];
    char victimGroup[MAX_GROUP_NAME];
    char attackerGroup[MAX_GROUP_NAME];
    char victimCommand[MAX_COMMAND_NAME];
    char attackerCommand[MAX_COMMAND_NAME];
    char victimSourceGroup[MAX_GROUP_NAME];
    char attackerSourceGroup[MAX_GROUP_NAME];
    bool victimFromGroup = false;
    bool attackerFromGroup = false;
    bool haveVictim = false;
    bool haveAttacker = false;
    bool restricted = false;
    bool paidRestricted = false;

    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && attacker != victim && g_szKillSound[attacker][0])
    {
        haveAttacker = GetCommandSoundDataForClientEx(attacker, g_szKillSound[attacker], attackerPath, sizeof(attackerPath), attackerGroup, sizeof(attackerGroup), restricted, paidRestricted, attackerCommand, sizeof(attackerCommand), attackerFromGroup, attackerSourceGroup, sizeof(attackerSourceGroup));
    }

    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
    {
        if (g_szDeathSound[victim][0])
        {
            haveVictim = GetCommandSoundDataForClientEx(victim, g_szDeathSound[victim], victimPath, sizeof(victimPath), victimGroup, sizeof(victimGroup), restricted, paidRestricted, victimCommand, sizeof(victimCommand), victimFromGroup, victimSourceGroup, sizeof(victimSourceGroup));
        }
        else if (!haveAttacker)
        {
            char defaultDeathCommand[MAX_COMMAND_NAME * 4];
            GetDefaultDeathSound(defaultDeathCommand, sizeof(defaultDeathCommand));
            if (defaultDeathCommand[0])
            {
                haveVictim = GetCommandSoundDataForClientEx(victim, defaultDeathCommand, victimPath, sizeof(victimPath), victimGroup, sizeof(victimGroup), restricted, paidRestricted, victimCommand, sizeof(victimCommand), victimFromGroup, victimSourceGroup, sizeof(victimSourceGroup));
            }
        }
    }

    if (haveVictim && haveAttacker)
    {
        if (GetRandomInt(0, 1) == 0)
        {
            if (PlaySaySound(victimPath, victimGroup))
            {
                LogSaySoundUsage("diesound_used", victim, 0, victimCommand, victimPath, victimGroup, victimFromGroup, victimSourceGroup, false, "diesound");
            }
        }
        else
        {
            if (PlaySaySound(attackerPath, attackerGroup))
            {
                LogSaySoundUsage("killsound_used", attacker, 0, attackerCommand, attackerPath, attackerGroup, attackerFromGroup, attackerSourceGroup, false, "killsound");
            }
        }
        return;
    }

    if (haveVictim)
    {
        if (PlaySaySound(victimPath, victimGroup))
        {
            LogSaySoundUsage("diesound_used", victim, 0, victimCommand, victimPath, victimGroup, victimFromGroup, victimSourceGroup, false, "diesound");
        }
    }
    else if (haveAttacker)
    {
        if (PlaySaySound(attackerPath, attackerGroup))
        {
            LogSaySoundUsage("killsound_used", attacker, 0, attackerCommand, attackerPath, attackerGroup, attackerFromGroup, attackerSourceGroup, false, "killsound");
        }
    }
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

static bool PlayWeaponKillSaySound(int attacker, int victim)
{
    char commandName[MAX_COMMAND_NAME * 4];
    if (!GetWeaponKillSaySoundCommand(attacker, victim, commandName, sizeof(commandName)))
    {
        return false;
    }

    char soundPath[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    char selectedCommand[MAX_COMMAND_NAME];
    char sourceGroup[MAX_GROUP_NAME];
    bool fromGroup = false;
    bool restricted = false;
    bool paidRestricted = false;
    if (!GetCommandSoundDataForClientEx(attacker, commandName, soundPath, sizeof(soundPath), groupName, sizeof(groupName), restricted, paidRestricted, selectedCommand, sizeof(selectedCommand), fromGroup, sourceGroup, sizeof(sourceGroup)))
    {
        return false;
    }

    PrecacheSound(soundPath, true);
    if (!PlaySaySoundToTarget(0, soundPath, groupName))
    {
        return false;
    }

    LogSaySoundUsage("weapon_killsound_used", attacker, 0, selectedCommand, soundPath, groupName, fromGroup, sourceGroup, false, "weapon_killsound");
    return true;
}
