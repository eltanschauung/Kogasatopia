/** Session-scoped loadout state, bounded native inputs, and reentrant equip handling. */
bool g_WeaponsApplyingLoadout[MAXPLAYERS + 1];
int g_WeaponsLoadoutRevision[MAXPLAYERS + 1];
DataPack g_WeaponsLoadoutRefreshRequest[MAXPLAYERS + 1];
QueryCookie g_WeaponsRespawnQuery[MAXPLAYERS + 1];
int g_WeaponsRespawnQueryClass[MAXPLAYERS + 1];
int s_LastUpdatedClient;

bool Weapons_LoadoutClientValid(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client);
}

bool Weapons_LoadoutClassValid(int playerClass)
{
    return playerClass > 0 && playerClass < NUM_PLAYER_CLASSES;
}

bool Weapons_LoadoutIdentityMatches(int serial, int client, int ref, int entity)
{
    return GetClientFromSerial(serial) == client && IsClientInGame(client)
        && entity > MaxClients && EntRefToEntIndex(ref) == entity && IsValidEntity(entity);
}

void Weapons_ResetLoadoutRequests(int client)
{
    g_WeaponsLoadoutRevision[client]++;
    // RequestFrame callbacks retain ownership of their packs until execution.
    g_WeaponsLoadoutRefreshRequest[client] = null;
    g_WeaponsApplyingLoadout[client] = false;
    g_WeaponsRespawnQuery[client] = QUERYCOOKIE_FAILED;
    g_WeaponsRespawnQueryClass[client] = 0;
    g_bForceReequipItems[client] = false;
}

public void OnClientConnected(int client)
{
    Weapons_ResetLoadoutRequests(client);
    g_bRetrievedLoadout[client] = false;
    for (int playerClass = 0; playerClass < NUM_PLAYER_CLASSES; playerClass++)
    {
        for (int slot = 0; slot < NUM_ITEMS; slot++)
        {
            g_CurrentLoadout[client][playerClass][slot].Clear(.initialize = true);
        }
    }
    CustomHats_OnClientConnected(client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    FetchLoadoutItems(client);
}

void FetchLoadoutItems(int client)
{
    if (Weapons_LoadoutClientValid(client) && AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }
}

public void OnClientCookiesCached(int client)
{
    CustomHats_OnClientCookiesCached(client);
    WeaponsHatVisibility_OnClientCookiesCached(client);
    bool wasRetrieved = g_bRetrievedLoadout[client];
    g_WeaponsLoadoutRevision[client]++;
    for (int playerClass = 0; playerClass < NUM_PLAYER_CLASSES; playerClass++)
    {
        for (int slot = 0; slot < NUM_ITEMS; slot++)
        {
            g_ItemPersistCookies[playerClass][slot].Get(client,
                g_CurrentLoadout[client][playerClass][slot].uid,
                sizeof(g_CurrentLoadout[][][].uid));
        }
    }
    g_bRetrievedLoadout[client] = true;
    WeaponsStats_MirrorClientSavedLoadout(client);
    if (!wasRetrieved && IsClientInGame(client))
    {
        Weapons_QueueLoadoutRefresh(client);
    }
}

void Weapons_QueueLoadoutRefresh(int client)
{
    if (!Weapons_LoadoutClientValid(client) || !IsClientInGame(client)
        || g_WeaponsLoadoutRefreshRequest[client] != null)
    {
        return;
    }
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    g_WeaponsLoadoutRefreshRequest[client] = pack;
    RequestFrame(Frame_ApplyRetrievedLoadout, pack);
}

void Frame_ApplyRetrievedLoadout(any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    bool ownsRequest = client > 0 && client <= MaxClients
        && g_WeaponsLoadoutRefreshRequest[client] == pack;
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_WeaponsLoadoutRefreshRequest[client] = null;
    if (IsClientInGame(client) && IsPlayerAlive(client) && g_bRetrievedLoadout[client])
    {
        ApplyClientCustomLoadout(client);
    }
}

Action OnPlayerLoadoutUpdated(UserMsg msg_id, BfRead msg, const int[] players,
    int playersNum, bool reliable, bool init)
{
    int client = msg.ReadByte();
    s_LastUpdatedClient = Weapons_LoadoutClientValid(client) ? GetClientSerial(client) : 0;
    return Plugin_Continue;
}

void OnPlayerLoadoutUpdatedPost(UserMsg msg_id, bool sent)
{
    int serial = s_LastUpdatedClient;
    s_LastUpdatedClient = 0; // Consume before equip can produce another usermessage.
    if (sent && serial != 0)
    {
        ApplyClientCustomLoadout(GetClientFromSerial(serial));
    }
}

void ApplyClientCustomLoadout(int client)
{
    if (!Weapons_LoadoutClientValid(client) || !IsClientInGame(client)
        || !sm_weapons_enable_loadout.BoolValue)
    {
        return;
    }
    if (g_WeaponsApplyingLoadout[client])
    {
        // No recursive item creation. Collapse nested requests into one next-frame pass.
        Weapons_QueueLoadoutRefresh(client);
        return;
    }
    int playerClass = view_as<int>(TF2_GetPlayerClass(client));
    if (!Weapons_LoadoutClassValid(playerClass))
    {
        return;
    }
    int serial = GetClientSerial(client);
    g_WeaponsApplyingLoadout[client] = true;
    Weapons_ApplyLoadoutPass(client, playerClass, serial);
    if (GetClientFromSerial(serial) == client)
    {
        g_WeaponsApplyingLoadout[client] = false;
    }
}

void Weapons_ApplyLoadoutPass(int client, int playerClass, int serial)
{
    int revision = g_WeaponsLoadoutRevision[client];
    for (int slot = 0; slot < NUM_ITEMS; slot++)
    {
        if (GetClientFromSerial(serial) != client || !IsClientInGame(client)
            || view_as<int>(TF2_GetPlayerClass(client)) != playerClass)
        {
            return;
        }
        if (revision != g_WeaponsLoadoutRevision[client])
        {
            Weapons_QueueLoadoutRefresh(client);
            return;
        }
        if (g_CurrentLoadout[client][playerClass][slot].IsEmpty())
        {
            continue;
        }
        CustomItemDefinition item;
        if (!g_CurrentLoadout[client][playerClass][slot].GetItemDefinition(item))
        {
            continue;
        }
        int ref = g_CurrentLoadout[client][playerClass][slot].entity;
        int entity = EntRefToEntIndex(ref);
        if (g_bForceReequipItems[client] || entity <= MaxClients
            || !IsValidEntity(entity) || (GetEntityFlags(entity) & FL_KILLME))
        {
            if (!CanPlayerEquipItem(client, item) || !IsCustomItemAllowed(client, item))
            {
                continue;
            }
            if (revision != g_WeaponsLoadoutRevision[client])
            {
                Weapons_QueueLoadoutRefresh(client);
                return;
            }
            entity = EquipCustomItem(client, item);
            if (GetClientFromSerial(serial) != client || !IsClientInGame(client)
                || view_as<int>(TF2_GetPlayerClass(client)) != playerClass)
            {
                return;
            }
            if (revision != g_WeaponsLoadoutRevision[client])
            {
                Weapons_QueueLoadoutRefresh(client);
                return;
            }
            // Never convert a failed spawn (-1) or publish into a disconnected slot.
            if (entity <= MaxClients || !IsValidEntity(entity))
            {
                continue;
            }
            Weapons_MarkValidatedAttachedEntity(entity, client, "loadout_apply");
            g_CurrentLoadout[client][playerClass][slot].entity = EntIndexToEntRef(entity);
        }
        else
        {
            EnsureCustomItemRuntimeAttributes(entity, item, client, "persisted_loadout");
            if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity))
            {
                return;
            }
            Weapons_MarkValidatedAttachedEntity(entity, client, "persisted_loadout");
            Weapons_NotifyItemRuntimeStateReady(client, entity);
        }
    }
    if (GetClientFromSerial(serial) == client && IsClientInGame(client))
    {
        WeaponsGameplay_QueueWearerAttributeRefresh(client);
    }
}

MRESReturn OnGetLoadoutItemPre(int client, DHookReturn hReturn, DHookParam hParams)
{
    return WeaponsWhitelist_OnGetLoadoutItemPre(client, hReturn, hParams);
}

MRESReturn OnGetLoadoutItemPost(int client, DHookReturn hReturn, DHookParam hParams)
{
    MRESReturn whitelistResult = WeaponsWhitelist_ApplyLoadoutRule(client, hReturn, hParams);
    if (whitelistResult == MRES_Supercede)
    {
        return whitelistResult;
    }
    if (!Weapons_LoadoutClientValid(client) || !sm_weapons_enable_loadout.BoolValue)
    {
        return MRES_Ignored;
    }
    int playerClass = hParams.Get(1);
    int slot = hParams.Get(2);
    if (!Weapons_LoadoutClassValid(playerClass) || slot < 0 || slot >= NUM_ITEMS)
    {
        return MRES_Ignored;
    }
    int storedItem = EntRefToEntIndex(g_CurrentLoadout[client][playerClass][slot].entity);
    if (!g_CurrentLoadout[client][playerClass][slot].IsEmpty())
    {
        CustomItemDefinition item;
        if (!g_CurrentLoadout[client][playerClass][slot].GetItemDefinition(item)
            || !CanPlayerEquipItemForClass(client, playerClass, item))
        {
            if (storedItem > MaxClients && IsValidEntity(storedItem))
            {
                RemoveEntity(storedItem);
                g_CurrentLoadout[client][playerClass][slot].entity = INVALID_ENT_REFERENCE;
            }
            return MRES_Ignored;
        }
    }
    if (storedItem <= MaxClients || !IsValidEntity(storedItem)
        || (GetEntityFlags(storedItem) & FL_KILLME) || !HasEntProp(storedItem, Prop_Send, "m_Item"))
    {
        if (g_CurrentLoadout[client][playerClass][slot].IsEmpty())
        {
            return MRES_Ignored;
        }
        // TF2 expects a non-null CEconItemView even while custom equip is deferred.
        static int defaultItemRef = INVALID_ENT_REFERENCE;
        storedItem = EntRefToEntIndex(defaultItemRef);
        if (storedItem <= MaxClients || !IsValidEntity(storedItem))
        {
            storedItem = TF2_SpawnWearable();
            if (storedItem <= MaxClients || !IsValidEntity(storedItem))
            {
                return MRES_Ignored;
            }
            defaultItemRef = EntIndexToEntRef(storedItem);
            // Intentional: RemoveEntity is deferred by the engine until after this call.
            RemoveEntity(storedItem);
        }
    }
    int offset = GetEntSendPropOffs(storedItem, "m_Item", true);
    if (offset <= 0)
    {
        return MRES_Ignored;
    }
    hReturn.Value = GetEntityAddress(storedItem) + view_as<Address>(offset);
    return MRES_Supercede;
}

MRESReturn OnManageRegularWeaponsPre(int client, Handle hParams)
{
    if (!Weapons_IsValidClient(client)) return MRES_Ignored;
    TFClassType playerClass = TF2_GetPlayerClass(client);
    if (!Weapons_LoadoutClassValid(view_as<int>(playerClass))) return MRES_Ignored;
    for (int slot = 0; slot < NUM_ITEMS; slot++)
    {
        int entity = EntRefToEntIndex(g_CurrentLoadout[client][playerClass][slot].entity);
        if (entity <= MaxClients || !IsValidEntity(entity)) continue;
        int baseItem = FindBaseItem(playerClass, slot);
        if (baseItem == TF_ITEMDEF_DEFAULT) continue;
        int itemdef = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
        if (TF2Econ_GetItemLoadoutSlot(itemdef, playerClass) != -1) continue;
        char classname[64];
        TF2Econ_GetItemClassName(baseItem, classname, sizeof(classname));
        TF2Econ_TranslateWeaponEntForClass(classname, sizeof(classname), playerClass);
        SetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex", baseItem);
        SetEntPropString(entity, Prop_Data, "m_iClassname", classname);
    }
    return MRES_Ignored;
}

MRESReturn OnManageRegularWeaponsPost(int client, Handle hParams)
{
    if (!Weapons_IsValidClient(client)) return MRES_Ignored;
    TFClassType playerClass = TF2_GetPlayerClass(client);
    if (!Weapons_LoadoutClassValid(view_as<int>(playerClass))) return MRES_Ignored;
    for (int slot = 0; slot < NUM_ITEMS; slot++)
    {
        int entity = EntRefToEntIndex(g_CurrentLoadout[client][playerClass][slot].entity);
        if (entity <= MaxClients || !IsValidEntity(entity)) continue;
        CustomItemDefinition item;
        if (!g_CurrentLoadout[client][playerClass][slot].GetItemDefinition(item)) continue;
        char classname[64];
        strcopy(classname, sizeof(classname), item.className);
        TF2Econ_TranslateWeaponEntForClass(classname, sizeof(classname), playerClass);
        SetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex", item.defindex);
        SetEntPropString(entity, Prop_Data, "m_iClassname", classname);
        Weapons_MarkValidatedAttachedEntity(entity, client, "manage_regular_weapons");
    }
    return MRES_Ignored;
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
    char command[64];
    kv.GetSectionName(command, sizeof(command));
    if (Weapons_LoadoutClientValid(client) && StrEqual(command, "MVM_Respec"))
    {
        g_bForceReequipItems[client] = true;
    }
    return Plugin_Continue;
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv)
{
    char command[64];
    kv.GetSectionName(command, sizeof(command));
    if (Weapons_LoadoutClientValid(client) && StrEqual(command, "MVM_Respec"))
    {
        g_bForceReequipItems[client] = false;
    }
}

int FindBaseItem(TFClassType playerClass, int slot)
{
    if (!Weapons_LoadoutClassValid(view_as<int>(playerClass)) || slot < 0 || slot >= NUM_ITEMS)
    {
        return TF_ITEMDEF_DEFAULT;
    }
    // The econ schema is stable for this plugin lifetime. Cache both hits and misses.
    static bool ready;
    static int baseItems[NUM_PLAYER_CLASSES][NUM_ITEMS];
    if (!ready)
    {
        ArrayList items = TF2Econ_GetItemList(FilterBaseItems);
        for (int c = 1; c < NUM_PLAYER_CLASSES; c++)
        {
            for (int s = 0; s < NUM_ITEMS; s++) baseItems[c][s] = TF_ITEMDEF_DEFAULT;
            for (int i = 0; i < items.Length; i++)
            {
                int defindex = items.Get(i);
                int itemSlot = TF2Econ_GetItemLoadoutSlot(defindex, view_as<TFClassType>(c));
                if (itemSlot >= 0 && itemSlot < NUM_ITEMS && baseItems[c][itemSlot] == TF_ITEMDEF_DEFAULT)
                {
                    baseItems[c][itemSlot] = defindex;
                }
            }
        }
        delete items;
        ready = true;
    }
    return baseItems[playerClass][slot];
}

bool FilterBaseItems(int itemdef, any data)
{
    return TF2Econ_IsItemInBaseSet(itemdef);
}

int Native_EquipPlayerItem(Handle plugin, int argc)
{
    int client = GetNativeCell(1);
    if (!Weapons_IsValidClient(client)) return INVALID_ENT_REFERENCE;
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(2, uid, sizeof(uid));
    CustomItemDefinition item;
    if (!GetCustomItemDefinition(uid, item)) return INVALID_ENT_REFERENCE;
    int entity = EquipCustomItem(client, item);
    return entity > MaxClients && IsValidEntity(entity) ? EntIndexToEntRef(entity) : INVALID_ENT_REFERENCE;
}

int Native_CanPlayerAccessItem(Handle plugin, int argc)
{
    int client = GetNativeCell(1);
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(2, uid, sizeof(uid));
    CustomItemDefinition item;
    return Weapons_LoadoutClientValid(client) && GetCustomItemDefinition(uid, item)
        && CanPlayerAccessItem(client, item);
}

int Native_GetItemList(Handle plugin, int argc)
{
    Function filter = GetNativeFunction(1);
    any data = GetNativeCell(2);
    StringMapSnapshot snapshot = GetCustomItemList();
    ArrayList items = new ArrayList(ByteCountToCells(MAX_ITEM_IDENTIFIER_LENGTH));
    for (int i = 0; i < snapshot.Length; i++)
    {
        char uid[MAX_ITEM_IDENTIFIER_LENGTH];
        snapshot.GetKey(i, uid, sizeof(uid));
        bool accept = true;
        if (filter != INVALID_FUNCTION)
        {
            Call_StartFunction(plugin, filter);
            Call_PushString(uid);
            Call_PushCell(data);
            Call_Finish(accept);
        }
        if (accept) items.PushString(uid);
    }
    delete snapshot;
    return MoveHandle(items, plugin);
}

int Native_IsItemUIDValid(Handle plugin, int argc)
{
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(1, uid, sizeof(uid));
    CustomItemDefinition item;
    return GetCustomItemDefinition(uid, item);
}

int Native_GetItemUIDFromEntity(Handle plugin, int argc)
{
    int entity = GetNativeCell(1);
    if (entity <= MaxClients || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_AttributeList"))
    {
        return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d is invalid or not an item", entity);
    }
    int length = GetNativeCell(3);
    if (length <= 0) return false;
    Address attribute = TF2Attrib_GetByName(entity, ATTRIB_NAME_CUSTOM_UID);
    if (!attribute) return false;
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    any rawValue = TF2Attrib_GetValue(attribute);
    TF2Attrib_UnsafeGetStringValue(rawValue, uid, sizeof(uid));
    if (!uid[0]) return false;
    SetNativeString(2, uid, length);
    return true;
}

int Native_GetItemLoadoutSlot(Handle plugin, int argc)
{
    int playerClass = GetNativeCell(2);
    if (!Weapons_LoadoutClassValid(playerClass)) return -1;
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(1, uid, sizeof(uid));
    CustomItemDefinition item;
    return GetCustomItemDefinition(uid, item) ? item.loadoutPosition[playerClass] : -1;
}

int Native_GetItemDisplayName(Handle plugin, int argc)
{
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(1, uid, sizeof(uid));
    CustomItemDefinition item;
    int length = GetNativeCell(3);
    if (length <= 0 || !GetCustomItemDefinition(uid, item) || !item.displayName[0]) return false;
    SetNativeString(2, item.displayName, length, true);
    return true;
}

int Native_IsItemReskinOnly(Handle plugin, int argc)
{
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(1, uid, sizeof(uid));
    CustomItemDefinition item;
    return GetCustomItemDefinition(uid, item) && item.reskinOnly;
}

int Native_GetItemExtData(Handle plugin, int argc)
{
    char uid[MAX_ITEM_IDENTIFIER_LENGTH], section[64];
    GetNativeString(1, uid, sizeof(uid));
    GetNativeString(2, section, sizeof(section));
    CustomItemDefinition item;
    if (!GetCustomItemDefinition(uid, item)) return 0;
    KeyValues result = item.GetExtData(section);
    return result != null ? MoveHandle(result, plugin) : 0;
}

int Native_SetPlayerLoadoutItem(Handle plugin, int argc)
{
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    GetNativeString(3, uid, sizeof(uid));
    return SetClientCustomLoadoutItem(GetNativeCell(1), GetNativeCell(2), uid, GetNativeCell(4));
}

bool SetClientCustomLoadoutItem(int client, int playerClass, const char[] uid, int flags)
{
    if (!Weapons_LoadoutClientValid(client) || !Weapons_LoadoutClassValid(playerClass)) return false;
    CustomItemDefinition item;
    if (!GetCustomItemDefinition(uid, item)) return false;
    if ((flags & LOADOUT_FLAG_UPDATE_BACKEND)
        && (!AreClientCookiesCached(client) || !CanPlayerEquipItemForClass(client, playerClass, item))) return false;
    int slot = item.loadoutPosition[playerClass];
    if (slot < 0 || slot >= NUM_ITEMS) return false;
    g_WeaponsLoadoutRevision[client]++;
    g_CurrentLoadout[client][playerClass][slot].entity = INVALID_ENT_REFERENCE;
    if (flags & LOADOUT_FLAG_UPDATE_BACKEND)
    {
        char previousUid[MAX_ITEM_IDENTIFIER_LENGTH];
        strcopy(previousUid, sizeof(previousUid), g_CurrentLoadout[client][playerClass][slot].uid);
        g_ItemPersistCookies[playerClass][slot].Set(client, uid);
        g_CurrentLoadout[client][playerClass][slot].SetItemUID(uid);
        if (!StrEqual(previousUid, uid, false))
        {
            if (previousUid[0]) WeaponsStats_RecordUnequip(client, playerClass, slot, previousUid, false);
            WeaponsStats_RecordEquip(client, playerClass, slot, uid, item);
        }
    }
    else
    {
        g_CurrentLoadout[client][playerClass][slot].SetOverloadItemUID(uid);
    }
    if (flags & LOADOUT_FLAG_ATTEMPT_REGEN) OnClientCustomLoadoutItemModified(client, playerClass);
    return true;
}

int Native_RemovePlayerLoadoutItem(Handle plugin, int argc)
{
    UnsetClientCustomLoadoutItem(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), GetNativeCell(4));
    return 0;
}

void UnsetClientCustomLoadoutItem(int client, int playerClass, int slot, int flags)
{
    if (!Weapons_LoadoutClientValid(client) || !Weapons_LoadoutClassValid(playerClass)
        || slot < 0 || slot >= NUM_ITEMS) return;
    g_WeaponsLoadoutRevision[client]++;
    if (flags & LOADOUT_FLAG_UPDATE_BACKEND)
    {
        if (!AreClientCookiesCached(client)) return;
        char previousUid[MAX_ITEM_IDENTIFIER_LENGTH];
        strcopy(previousUid, sizeof(previousUid), g_CurrentLoadout[client][playerClass][slot].uid);
        g_CurrentLoadout[client][playerClass][slot].Clear();
        g_ItemPersistCookies[playerClass][slot].Set(client, "");
        if (previousUid[0]) WeaponsStats_RecordUnequip(client, playerClass, slot, previousUid);
    }
    else
    {
        g_CurrentLoadout[client][playerClass][slot].SetOverloadItemUID("");
    }
    if (flags & LOADOUT_FLAG_ATTEMPT_REGEN) OnClientCustomLoadoutItemModified(client, playerClass);
}

int Native_GetPlayerLoadoutItem(Handle plugin, int argc)
{
    int client = GetNativeCell(1), playerClass = GetNativeCell(2), slot = GetNativeCell(3);
    int length = GetNativeCell(5), flags = GetNativeCell(6);
    if (!Weapons_LoadoutClientValid(client) || !Weapons_LoadoutClassValid(playerClass)
        || slot < 0 || slot >= NUM_ITEMS || length <= 0) return false;
    if (g_CurrentLoadout[client][playerClass][slot].IsEmpty()) return false;
    // Bound temporary storage independently of a caller-supplied buffer length.
    char uid[MAX_ITEM_IDENTIFIER_LENGTH];
    if (flags & LOADOUT_FLAG_UPDATE_BACKEND)
    {
        strcopy(uid, sizeof(uid), g_CurrentLoadout[client][playerClass][slot].uid);
    }
    else
    {
        strcopy(uid, sizeof(uid), g_CurrentLoadout[client][playerClass][slot].override_uid);
    }
    SetNativeString(4, uid, length);
    return true;
}

void OnClientCustomLoadoutItemModified(int client, int modifiedClass)
{
    if (!Weapons_IsValidClient(client) || view_as<int>(TF2_GetPlayerClass(client)) != modifiedClass
        || !sm_weapons_enable_loadout.BoolValue) return;
    if (!IsPlayerAllowedToRespawnOnLoadoutChange(client))
    {
        PrintToChat(client, "%t", "LoadoutChangesUpdate");
        return;
    }
    g_WeaponsRespawnQueryClass[client] = modifiedClass;
    g_WeaponsRespawnQuery[client] = QueryClientConVar(client, "tf_respawn_on_loadoutchanges",
        OnLoadoutRespawnPreference, GetClientSerial(client));
}

void OnLoadoutRespawnPreference(QueryCookie cookie, int client, ConVarQueryResult result,
    const char[] cvarName, const char[] cvarValue, any serial)
{
    if (!Weapons_IsValidClient(client) || GetClientFromSerial(serial) != client
        || cookie != g_WeaponsRespawnQuery[client]) return;
    g_WeaponsRespawnQuery[client] = QUERYCOOKIE_FAILED;
    if (result != ConVarQuery_Okay
        || view_as<int>(TF2_GetPlayerClass(client)) != g_WeaponsRespawnQueryClass[client]) return;
    if (!StringToInt(cvarValue) || !IsPlayerAllowedToRespawnOnLoadoutChange(client))
    {
        PrintToChat(client, "%t", "LoadoutChangesUpdate");
        return;
    }
    SetEntProp(client, Prop_Send, "m_bRegenerating", true);
    TF2_RespawnPlayer(client);
    if (GetClientFromSerial(serial) == client && IsClientInGame(client))
    {
        SetEntProp(client, Prop_Send, "m_bRegenerating", false);
    }
}

bool CanPlayerEquipItem(int client, const CustomItemDefinition item)
{
    return Weapons_IsValidClient(client)
        && CanPlayerEquipItemForClass(client, view_as<int>(TF2_GetPlayerClass(client)), item);
}

bool CanPlayerEquipItemForClass(int client, int playerClass, const CustomItemDefinition item)
{
    return Weapons_LoadoutClassValid(playerClass) && item.loadoutPosition[playerClass] != -1
        && CanPlayerAccessItem(client, item);
}

bool CanPlayerViewItem(int client, const CustomItemDefinition item)
{
    return Weapons_LoadoutClientValid(client) && (!item.access[0] || CheckCommandAccess(client, item.access, 0, true));
}

bool ItemRequiresPointsStorePurchase(int client, const CustomItemDefinition item)
{
    if (!item.pointsStorePurchase[0]) return false;
    return !Weapons_LoadoutClientValid(client) || !IsClientInGame(client)
        || GetFeatureStatus(FeatureType_Native, POINTS_STORE_HAS_PURCHASE_NATIVE) != FeatureStatus_Available
        || !PointsStore_HasPurchase(client, item.pointsStorePurchase);
}

bool CanPlayerAccessItem(int client, const CustomItemDefinition item)
{
    return CanPlayerViewItem(client, item) && !ItemRequiresPointsStorePurchase(client, item);
}

static bool IsPlayerInRespawnRoom(int client)
{
    float mins[3], maxs[3], center[3], origin[3];
    GetClientMins(client, mins);
    GetClientMaxs(client, maxs);
    GetClientAbsOrigin(client, origin);
    GetCenterFromPoints(mins, maxs, center);
    AddVectors(origin, center, center);
    return TF2Util_IsPointInRespawnRoom(center, client, true);
}

static bool IsPlayerAllowedToRespawnOnLoadoutChange(int client)
{
    return Weapons_IsValidClient(client) && IsPlayerAlive(client) && IsPlayerInRespawnRoom(client)
        && GameRules_GetRoundState() != RoundState_Stalemate;
}

static bool IsCustomItemAllowed(int client, const CustomItemDefinition item)
{
    if (!Weapons_IsValidClient(client)) return false;
    TFClassType playerClass = TF2_GetPlayerClass(client);
    if (!Weapons_LoadoutClassValid(view_as<int>(playerClass))) return false;
    int slot = item.loadoutPosition[playerClass];
    if (GameRules_GetRoundState() == RoundState_Stalemate && mp_stalemate_meleeonly != null
        && mp_stalemate_meleeonly.BoolValue
        && slot != 2 && !(playerClass == TFClass_Spy && (slot == 5 || slot == 6))) return false;
    if (GameRules_GetProp("m_bPlayingMedieval") && slot != 2)
    {
        bool allowed, overridden;
        if (item.nativeAttributes)
        {
            char value[8];
            item.nativeAttributes.GetString("allowed in medieval mode", value, sizeof(value));
            if (value[0])
            {
                overridden = true;
                allowed = StringToInt(value) != 0;
            }
        }
        if (!overridden && item.bKeepStaticAttributes)
        {
            ArrayList attributes = TF2Econ_GetItemStaticAttributes(item.defindex);
            allowed = attributes.FindValue(g_attrdef_AllowedInMedievalMode) != -1;
            delete attributes;
        }
        if (!allowed) return false;
    }
    return true;
}

Action DisplayItemDescriptions(int client, int argc)
{
    if (!Weapons_IsValidClient(client)) return Plugin_Handled;
    int playerClass = view_as<int>(TF2_GetPlayerClass(client));
    if (!Weapons_LoadoutClassValid(playerClass)) return Plugin_Handled;
    StringMap printed = new StringMap();
    StringMapSnapshot snapshot = GetCustomItemList();
    for (int i = 0; i < snapshot.Length; i++)
    {
        char uid[MAX_ITEM_IDENTIFIER_LENGTH];
        snapshot.GetKey(i, uid, sizeof(uid));
        CustomItemDefinition item;
        if (!GetCustomItemDefinition(uid, item) || item.loadoutPosition[playerClass] == -1
            || (sm_weapons_hide_reskin_only.BoolValue && item.reskinOnly)) continue;
        char description[MAX_ITEM_DESCRIPTION_LENGTH * 3], key[MAX_ITEM_DESCRIPTION_LENGTH * 3];
        bool described = FormatItemDescription(item, description, sizeof(description));
        strcopy(key, sizeof(key), described ? description : uid);
        if (printed.ContainsKey(key)) continue;
        printed.SetValue(key, 1);
        if (described) CPrintToChat(client, "%s", description);
        else CPrintToChat(client, "{gold}[Weapons]{default} This weapon has no set description.");
    }
    delete snapshot;
    delete printed;
    return Plugin_Handled;
}

bool FormatItemDescription(const CustomItemDefinition item, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (!item.descriptionPositive[0] && !item.descriptionNeutral[0] && !item.descriptionNegative[0]) return false;
    FormatEx(buffer, maxlen, "{gold}%s{default}:", item.displayName);
    bool needsComma;
    if (item.descriptionPositive[0]) AppendItemDescriptionPart(buffer, maxlen, "{green}", item.descriptionPositive, needsComma);
    if (item.descriptionNeutral[0]) AppendItemDescriptionPart(buffer, maxlen, "{default}", item.descriptionNeutral, needsComma);
    if (item.descriptionNegative[0]) AppendItemDescriptionPart(buffer, maxlen, "{red}", item.descriptionNegative, needsComma);
    return true;
}

void AppendItemDescriptionPart(char[] buffer, int maxlen, const char[] color, const char[] text, bool &needsComma)
{
    if (needsComma) StrCat(buffer, maxlen, ",");
    StrCat(buffer, maxlen, " ");
    StrCat(buffer, maxlen, color);
    StrCat(buffer, maxlen, text);
    needsComma = true;
}
