/**
 * Functions related to item entities.
 * Delayed work owns its DataPack and keeps entity/client serial identities.
 */

#define Weapons_VALIDATE_DELAY_SHORT 0.1
#define Weapons_VALIDATE_DELAY_LONG 0.5

// Sendtable offsets are immutable for a netclass during this plugin's lifetime.
StringMap g_WeaponsItemMetadataOffsets = null;

stock void Weapons_MarkValidatedAttachedEntity(int entity, int client = 0,
        const char[] context = "unknown", bool scheduleChecks = true,
        int sourceEntity = INVALID_ENT_REFERENCE) {
    if (entity <= MaxClients || !IsValidEntity(entity)) {
        return;
    }

    if (!HasEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity")) {
        Weapons_LogValidatedAttachedEntityState("missing_prop", entity, client, sourceEntity,
            context, -1, -1, false);
        return;
    }

    int before = GetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity");
    SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", true);
    if (Weapons_ValidateDebugEnabled()) {
        int after = GetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity");
        Weapons_LogValidatedAttachedEntityState("set", entity, client, sourceEntity,
            context, before, after, false);
    }

    if (scheduleChecks && (Weapons_ValidateDebugEnabled() || Weapons_ValidationRepairEnabled())) {
        Weapons_QueueValidatedAttachedEntityCheck(entity, client, sourceEntity, context,
            Weapons_VALIDATE_DELAY_SHORT);
        Weapons_QueueValidatedAttachedEntityCheck(entity, client, sourceEntity, context,
            Weapons_VALIDATE_DELAY_LONG);
    }
}

void Weapons_QueueValidatedAttachedEntityCheck(int entity, int client, int sourceEntity,
        const char[] context, float delay) {
    if (entity <= MaxClients || !IsValidEntity(entity)) {
        return;
    }

    // CreateDataTimer closes the pack both on execution and on map cancellation.
    // Never delete this pack in the callback: it is owned by the timer.
    DataPack pack;
    CreateDataTimer(delay, Timer_Weapons_CheckValidatedAttachedEntity, pack,
        TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(EntIndexToEntRef(entity));
    pack.WriteCell(Weapons_IsValidClient(client) ? GetClientSerial(client) : 0);
    pack.WriteCell(sourceEntity > MaxClients && IsValidEntity(sourceEntity)
        ? EntIndexToEntRef(sourceEntity) : INVALID_ENT_REFERENCE);
    pack.WriteString(context);
}

public Action Timer_Weapons_CheckValidatedAttachedEntity(Handle timer, any data) {
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int entityRef = pack.ReadCell();
    int serial = pack.ReadCell();
    int sourceRef = pack.ReadCell();
    char context[64];
    pack.ReadString(context, sizeof(context));

    int entity = EntRefToEntIndex(entityRef);
    int client = serial ? GetClientFromSerial(serial) : 0;
    int sourceEntity = EntRefToEntIndex(sourceRef);
    if (entity <= MaxClients || !IsValidEntity(entity)) {
        if (Weapons_ValidateDebugEnabled()) {
            LogMessage("[Weapons][Validate] phase=entity_gone context=%s ref=%d client=%d",
                context, entityRef, client);
        }
        return Plugin_Stop;
    }

    if (!HasEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity")) {
        Weapons_LogValidatedAttachedEntityState("missing_prop_delayed", entity, client,
            sourceEntity, context, -1, -1, false);
        return Plugin_Stop;
    }

    int before = GetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity");
    int after = before;
    bool repaired = false;
    if (!before && Weapons_ValidationRepairEnabled()) {
        SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", true);
        after = GetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity");
        repaired = after != 0;
    }

    if (!before) {
        Weapons_LogValidatedAttachedEntityState("dropped", entity, client, sourceEntity,
            context, before, after, repaired);
    } else if (Weapons_ValidateDebugEnabled()) {
        Weapons_LogValidatedAttachedEntityState("retained", entity, client, sourceEntity,
            context, before, after, false);
    }
    return Plugin_Stop;
}

bool Weapons_ValidateDebugEnabled() {
    return sm_weapons_validate_debug != null && sm_weapons_validate_debug.BoolValue;
}

bool Weapons_ValidationRepairEnabled() {
    return sm_weapons_validate_repair == null || sm_weapons_validate_repair.BoolValue;
}

void Weapons_LogValidatedAttachedEntityState(const char[] phase, int entity, int client,
        int sourceEntity, const char[] context, int before, int after, bool repaired) {
    if (!Weapons_ValidateDebugEnabled() && !StrEqual(phase, "dropped")) {
        return;
    }

    char entityClass[64], entityModel[PLATFORM_MAX_PATH];
    int entityDef, owner;
    Weapons_GetEntityDebugInfo(entity, entityClass, sizeof(entityClass), entityModel,
        sizeof(entityModel), entityDef, owner);

    char sourceClass[64], sourceModel[PLATFORM_MAX_PATH];
    int sourceDef, sourceOwner;
    Weapons_GetEntityDebugInfo(sourceEntity, sourceClass, sizeof(sourceClass), sourceModel,
        sizeof(sourceModel), sourceDef, sourceOwner);

    char clientLabel[96], ownerLabel[96], sourceOwnerLabel[96];
    Weapons_FormatClientLabel(client, clientLabel, sizeof(clientLabel));
    Weapons_FormatClientLabel(owner, ownerLabel, sizeof(ownerLabel));
    Weapons_FormatClientLabel(sourceOwner, sourceOwnerLabel, sizeof(sourceOwnerLabel));

    LogMessage("[Weapons][Validate] phase=%s context=%s before=%d after=%d repaired=%d entity=%d class=%s def=%d owner=%s model=\"%s\" client=%s source=%d source_class=%s source_def=%d source_owner=%s source_model=\"%s\" free_edicts=%d",
        phase, context, before, after, repaired ? 1 : 0, entity, entityClass,
        entityDef, ownerLabel, entityModel, clientLabel, sourceEntity, sourceClass,
        sourceDef, sourceOwnerLabel, sourceModel, GetMaxEntities() - GetEntityCount());
}

void Weapons_GetEntityDebugInfo(int entity, char[] className, int classLen,
        char[] model, int modelLen, int &defIndex, int &owner) {
    strcopy(className, classLen, "invalid");
    model[0] = '\0';
    defIndex = -1;
    owner = 0;
    if (!IsValidEntity(entity)) {
        return;
    }

    GetEntityClassname(entity, className, classLen);
    if (HasEntProp(entity, Prop_Data, "m_ModelName")) {
        GetEntPropString(entity, Prop_Data, "m_ModelName", model, modelLen);
    }
    if (HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex")) {
        defIndex = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
    }
    if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity")) {
        owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    }
}

bool Weapons_IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && !IsClientSourceTV(client) && !IsClientReplay(client)
        && !GetEntProp(client, Prop_Send, "m_bIsCoaching");
}

void Weapons_FormatClientLabel(int client, char[] buffer, int maxlen) {
    if (Weapons_IsValidClient(client)) {
        Format(buffer, maxlen, "%N(%d)", client, client);
        return;
    }
    Format(buffer, maxlen, "%d", client);
}

bool Weapons_GetItemMetadataOffsets(int entity, int offsets[2]) {
    char netClass[64];
    GetEntityNetClass(entity, netClass, sizeof(netClass));
    if (g_WeaponsItemMetadataOffsets == null) {
        g_WeaponsItemMetadataOffsets = new StringMap();
    }
    if (!g_WeaponsItemMetadataOffsets.GetArray(netClass, offsets, sizeof(offsets))) {
        offsets[0] = FindSendPropInfo(netClass, "m_iEntityQuality");
        offsets[1] = FindSendPropInfo(netClass, "m_iEntityLevel");
        g_WeaponsItemMetadataOffsets.SetArray(netClass, offsets, sizeof(offsets));
    }
    return offsets[0] > 0 && offsets[1] > 0;
}

/** Creates an item; returns an entity index, or -1 on failure. */
stock int TF2_CreateItem(int defindex, const char[] itemClass) {
    int weapon = CreateEntityByName(itemClass);
    if (weapon <= MaxClients || !IsValidEntity(weapon)) {
        return -1;
    }
    int reference = EntIndexToEntRef(weapon);
    int offsets[2];
    if (!HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")
        || !HasEntProp(weapon, Prop_Send, "m_bInitialized")
        || !Weapons_GetItemMetadataOffsets(weapon, offsets)) {
        LogError("[Weapons] %s is missing required econ item properties.", itemClass);
        RemoveEntity(weapon);
        return -1;
    }

    SetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex", defindex);
    SetEntProp(weapon, Prop_Send, "m_bInitialized", 1);
    // Preserve the raw-offset writes needed for the original quality/level override.
    SetEntData(weapon, offsets[0], 6);
    SetEntData(weapon, offsets[1], 1);
    SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 6);
    SetEntProp(weapon, Prop_Send, "m_iEntityLevel", 1);

    bool spawned = DispatchSpawn(weapon);
    weapon = EntRefToEntIndex(reference);
    if (weapon <= MaxClients || !IsValidEntity(weapon)) {
        return -1;
    }
    if (!spawned) {
        RemoveEntity(weapon);
        return -1;
    }
    Weapons_MarkValidatedAttachedEntity(weapon, 0, "create_post_spawn", false);
    return weapon;
}

/** Removes the given item based on its loadout slot. */
bool TF2_RemoveItemByLoadoutSlot(int client, int loadoutSlot) {
    if (!Weapons_IsValidClient(client) || loadoutSlot < 0) {
        return false;
    }
    int item = TF2Util_GetPlayerLoadoutEntity(client, loadoutSlot);
    if (item <= MaxClients || !IsValidEntity(item)) {
        // GPLE handles native class wearables only. Keep the original last-match policy.
        for (int i, n = TF2Util_GetPlayerWearableCount(client); i < n; i++) {
            int wearable = TF2Util_GetPlayerWearable(client, i);
            if (wearable <= MaxClients || !IsValidEntity(wearable)) {
                continue;
            }
            int itemdef = TF2_GetItemDefinitionIndex(wearable);
            if (TF2Econ_GetItemDefaultLoadoutSlot(itemdef) == loadoutSlot) {
                item = wearable;
            }
        }
    }
    if (item <= MaxClients || !IsValidEntity(item)) {
        return false;
    }

    if (TF2Util_IsEntityWearable(item)) {
        TF2_RemoveWearable(client, item);
    } else {
        int slot = TF2Util_GetWeaponSlot(item);
        if (slot < 0) {
            return false;
        }
        TF2_RemoveWeaponSlot(client, slot);
    }
    return true;
}

/** Engine equip/activate calls can re-enter plugin hooks and destroy their input entity. */
void TF2_EquipPlayerEconItem(int client, int item) {
    if (!Weapons_IsValidClient(client) || item <= MaxClients || !IsValidEntity(item)) {
        return;
    }
    int serial = GetClientSerial(client);
    int reference = EntIndexToEntRef(item);
    char weaponClass[64];
    GetEntityClassname(item, weaponClass, sizeof(weaponClass));
    bool wearable = StrContains(weaponClass, "tf_wearable", false) == 0;

    if (wearable) {
        TF2Util_EquipPlayerWearable(client, item);
    } else {
        EquipPlayerWeapon(client, item);
    }

    item = EntRefToEntIndex(reference);
    if (GetClientFromSerial(serial) != client || !Weapons_IsValidClient(client)
        || item <= MaxClients || !IsValidEntity(item)) {
        return;
    }
    if (HasEntProp(item, Prop_Send, "m_hOwnerEntity")
        && GetEntPropEnt(item, Prop_Send, "m_hOwnerEntity") != client) {
        return;
    }

    if (wearable) {
        Weapons_MarkValidatedAttachedEntity(item, client, "equip_wearable");
        return;
    }

    Weapons_MarkValidatedAttachedEntity(item, client, "equip_weapon", false);
    TF2_ResetWeaponAmmo(item);
    item = EntRefToEntIndex(reference);
    if (GetClientFromSerial(serial) != client || !Weapons_IsValidClient(client)
        || item <= MaxClients || !IsValidEntity(item)) {
        return;
    }
    // Calls GiveDefaultAmmo() for auto_fires_full_clip weapons, as before.
    ActivateEntity(item);
    item = EntRefToEntIndex(reference);
    if (item > MaxClients && IsValidEntity(item)) {
        client = GetClientFromSerial(serial);
        Weapons_MarkValidatedAttachedEntity(item, client, "activate_weapon");
    }
}
