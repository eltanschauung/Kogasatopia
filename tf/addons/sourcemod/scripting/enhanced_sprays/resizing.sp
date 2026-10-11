// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from Resizable Sprays by sappykun. Shared transfer ownership lives
// in enhanced_sprays.ext; this module owns only commands and decal placement.
#define RESIZE_WINDOW 5.0
#define RESIZE_LIMIT 3
#define RESIZE_PENDING_LIMIT 256
#define RESIZE_MATERIAL_LIMIT 512

enum struct ResizePlacement {
    int sprayerSerial;
    int ownerSerial;
    int crc;
    int entityRef;
    int hitbox;
    bool bsp;
    float position[3];
    char material[PLATFORM_MAX_PATH];
    char materialFile[PLATFORM_MAX_PATH];
    int serial[MAXPLAYERS + 1];
    int textureToken[MAXPLAYERS + 1];
    int materialToken[MAXPLAYERS + 1];
    int deliveryState[MAXPLAYERS + 1]; // 1 texture pending, 2 VMT pending, 3 ready.
}
ConVar g_ResizeEnabled, g_ResizeChatty, g_ResizeLogLevel, g_ResizeMaxScale, g_ResizeAbsolute;
ConVar g_ResizeDistance, g_ResizeFrequency, g_ResizeTimeout;
ArrayList g_ResizePending;
StringMap g_ResizeMaterials;
float g_ResizeScale[MAXPLAYERS + 1], g_ResizeLast[MAXPLAYERS + 1], g_ResizeJoin[MAXPLAYERS + 1];
float g_ResizeCommands[MAXPLAYERS + 1][RESIZE_LIMIT];
int g_ResizeCount[MAXPLAYERS + 1];
bool g_ResizeNotice[MAXPLAYERS + 1];
bool Resize_IsEnabled() {
    return g_ResizeEnabled != null && g_ResizeEnabled.BoolValue;
}

void Resize_Start() {
    g_ResizePending = new ArrayList(sizeof(ResizePlacement));
    g_ResizeMaterials = new StringMap();
    RegConsoleCmd("sm_spray", Resize_Command, "Place a repeatable, scalable spray decal.");
    RegConsoleCmd("sm_bspray", Resize_Command, "Place a repeatable, scalable BSP spray decal.");
    RegConsoleCmd("sm_sprayinfo", Resize_Info, "Display shared spray metadata/delivery state.");
    CreateConVar("rspr_version", ENHANCED_SPRAYS_VERSION, "Integrated resizable sprays version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_ResizeEnabled = CreateConVar("rspr_enabled", "1.0", "Enable resizable sprays.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_ResizeChatty = CreateConVar("rspr_chatty", "1", "Show spray download notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_ResizeLogLevel = CreateConVar("rspr_loglevel", "2", "Logging: 0 errors, 1 warnings, 2 information, 3 debug.");
    g_ResizeDistance = CreateConVar("rspr_maxspraydistance", "1024.0", "Maximum non-admin placement distance; 0 is unlimited.", FCVAR_NOTIFY, true, 0.0);
    g_ResizeMaxScale = CreateConVar("rspr_maxsprayscale", "240", "Maximum relative spray scale for non-admins.", FCVAR_NOTIFY, true, 0.0);
    g_ResizeAbsolute = CreateConVar("rspr_maxsprayscale_absolute", "32.0", "Maximum relative spray scale for everyone.", FCVAR_NOTIFY, true, 0.0);
    g_ResizeFrequency = CreateConVar("rspr_decalfrequency", "0.5", "Non-admin spray cooldown.", FCVAR_NOTIFY, true, 0.0);
    g_ResizeTimeout = CreateConVar("rspr_spraytimeout", "20.0", "Delivery deadline in seconds; bounded to 1-60 (0 uses 60).", FCVAR_NOTIFY, true, 0.0);
    AutoExecConfig(true, "resizablesprays");
    for (int client = 1; client <= MaxClients; client++)Resize_ClientJoin(client);
}
void Resize_ClientJoin(int client) {
    g_ResizeScale[client] = 1.0;
    g_ResizeLast[client] = -9999.0;
    g_ResizeJoin[client] = GetEngineTime();
    g_ResizeCount[client] = 0;
    g_ResizeNotice[client] = false;
}
void Resize_Reset() {
    if (g_ResizePending != null)g_ResizePending.Clear();
    if (g_ResizeMaterials != null)g_ResizeMaterials.Clear();
    for (int client = 1; client <= MaxClients; client++)Resize_ClientJoin(client);
}
void Resize_Stop() {
    delete g_ResizePending;
    delete g_ResizeMaterials;
}
void Resize_ClientLeave(int client) {
    int serial = GetClientSerial(client);
    Resize_CancelOwner(serial);
    if (g_ResizePending != null) {
        ResizePlacement placement;
        for (int i = 0; i < g_ResizePending.Length; i++) {
            g_ResizePending.GetArray(i, placement, sizeof(placement));
            placement.serial[client] = 0;
            g_ResizePending.SetArray(i, placement, sizeof(placement));
        }
    }
    // Native completion state is destroyed with this connection. Do not let a
    // recycled player slot inherit a successful transfer or a pending audience.
    Resize_ProcessPending();
}
void Resize_CancelOwner(int serial) {
    if (g_ResizePending == null)return;
    ResizePlacement placement;
    for (int i = g_ResizePending.Length - 1; i >= 0; i--) {
        g_ResizePending.GetArray(i, placement, sizeof(placement));
        if (placement.ownerSerial == serial || placement.sprayerSerial == serial)g_ResizePending.Erase(i);
    }
}
void Resize_SprayChanged(int client) {
    Resize_CancelOwner(GetClientSerial(client));
}
bool Resize_Admin(int client) {
    return CheckCommandAccess(client, "rspr_adminoverride", ADMFLAG_KICK, false);
}
bool Resize_AllowCommand(int client) {
    float now = GetEngineTime();
    int count;
    for (int i = 0; i < g_ResizeCount[client]; i++) {
        float timestamp = g_ResizeCommands[client][i];
        if (now - timestamp < RESIZE_WINDOW)g_ResizeCommands[client][count++] = timestamp;
    }
    g_ResizeCount[client] = count;
    if (count >= RESIZE_LIMIT) {
        if (!g_ResizeNotice[client])ReplyToCommand(client, "[Sprays] Spray commands are limited to 3 uses per 5 seconds.");
        g_ResizeNotice[client] = true;
        return false;
    }
    g_ResizeCommands[client][count] = now;
    g_ResizeCount[client] = count + 1;
    g_ResizeNotice[client] = false;
    return true;
}
bool Resize_Viewer(int owner, int viewer) {
    return Human(viewer) && g_ViewAllowed[viewer] && g_DownloadAllowed[viewer]
        && ESprays_CanView(owner, viewer);
}
public bool Resize_TraceFilter(int entity, int mask) {
    return entity == 0 || entity > MaxClients;
}
public Action Resize_Command(int client, int args) {
    if (!Human(client) || !g_ResizeEnabled.BoolValue || !IsPlayerAlive(client))return Plugin_Handled;
    if (!Resize_AllowCommand(client))return Plugin_Handled;
    float now = GetEngineTime();
    if (!Resize_Admin(client) && now - g_ResizeLast[client] < g_ResizeFrequency.FloatValue)return Plugin_Handled;
    g_ResizeLast[client] = now;
    char command[32], argument[64];
    GetCmdArg(0, command, sizeof(command));
    bool bsp = StrEqual(command, "sm_bspray"), canTarget = Resize_Admin(client) || bsp;
    int owner = client;
    if (args > 0) {
        float scale;
        GetCmdArg(1, argument, sizeof(argument));
        if (args > 2 || (!canTarget && args > 1) || !StringToFloatEx(argument, scale)
            || scale != scale || FloatAbs(scale) > 65536.0) {
            ReplyToCommand(client, "Usage: %s [desired_scale]%s", command, canTarget ? " [user]" : "");
            return Plugin_Handled;
        }
        g_ResizeScale[client] = scale;
        if (args == 2) {
            GetCmdArg(2, argument, sizeof(argument));
            owner = FindTarget(client, argument, true, true);
            if (!Human(owner))return Plugin_Handled;
        }
    }
    int width, height, frames, crc;
    if (!ESprays_GetTextureInfo(owner, width, height, frames, crc) || height <= 0) {
        ReplyToCommand(client, "[Sprays] We're still preparing this spray. Try again shortly or use !refreshspray.");
        return Plugin_Handled;
    }
    // This is an explicit placement of an already validated, cached image.
    // Disabling switching/uploads must not disable the independent resize module.
    if (!g_Download.BoolValue)return Plugin_Handled;
    if (g_ResizePending.Length >= RESIZE_PENDING_LIMIT) {
        ReplyToCommand(client, "[Sprays] The shared delivery queue is full. Try again shortly.");
        return Plugin_Handled;
    }
    float scale = g_ResizeScale[client];
    if (scale <= 0.0)scale = 1.0;
    if (!Resize_Admin(client) && scale > g_ResizeMaxScale.FloatValue)scale = g_ResizeMaxScale.FloatValue;
    if (scale > g_ResizeAbsolute.FloatValue)scale = g_ResizeAbsolute.FloatValue;
    if (scale <= 0.0)scale = 1.0;
    ResizePlacement placement;
    float eye[3], angles[3];
    GetClientEyePosition(client, eye);GetClientEyeAngles(client, angles);
    Handle trace = TR_TraceRayFilterEx(eye, angles, MASK_SHOT, RayType_Infinite, Resize_TraceFilter);
    bool hit = TR_DidHit(trace);
    int entity = TR_GetEntityIndex(trace);
    if (hit)TR_GetEndPosition(placement.position, trace);
    placement.hitbox = TR_GetHitBoxIndex(trace);
    delete trace;
    if (!hit || entity < 0 || (!Resize_Admin(client) && g_ResizeDistance.FloatValue > 0.0
        && GetVectorDistance(eye, placement.position) > g_ResizeDistance.FloatValue)) {
        ReplyToCommand(client, "[Sprays] You are too far from a valid surface to place a spray.");
        return Plugin_Handled;
    }
    // Bound unique materials per map, as well as pending placements and native jobs.
    if (g_ResizeMaterials.Size >= RESIZE_MATERIAL_LIMIT) {
        ReplyToCommand(client, "[Sprays] This map's spray material budget is exhausted.");
        return Plugin_Handled;
    }
    char texture[PLATFORM_MAX_PATH];
    if (!ESprays_PrepareResize(owner, scale * 64.0 / float(height), placement.material,
        sizeof(placement.material), texture, sizeof(texture)))return Plugin_Handled;
    Format(placement.materialFile, sizeof(placement.materialFile), "materials/%s.vmt", placement.material);
    placement.sprayerSerial = GetClientSerial(client);
    placement.ownerSerial = GetClientSerial(owner);
    placement.crc = crc;
    placement.entityRef = entity > 0 ? EntIndexToEntRef(entity) : 0;
    placement.bsp = bsp;
    int timeout = RoundToCeil(g_ResizeTimeout.FloatValue);
    if (timeout <= 0)timeout = 60;
    // Freeze the original audience with serials. New joins never inherit deliveries.
    int targets;
    float firstPrecache;
    int stored;
    bool precached = g_ResizeMaterials.GetValue(placement.material, stored);
    firstPrecache = view_as<float>(stored);
    for (int viewer = 1; viewer <= MaxClients; viewer++) {
        if (!Resize_Viewer(owner, viewer) || (precached && g_ResizeJoin[viewer] > firstPrecache))continue;
        int token = ESprays_RequestAsset(viewer, texture, timeout);
        if (token <= 0)continue;
        placement.serial[viewer] = GetClientSerial(viewer);
        placement.textureToken[viewer] = token;
        placement.deliveryState[viewer] = 1;
        targets++;
    }
    if (targets == 0)return Plugin_Handled;
    g_ResizePending.PushArray(placement, sizeof(placement));
    if (g_ResizeChatty.BoolValue)ReplyToCommand(client, "[Sprays] Preparing your resized spray...");
    Resize_ProcessPending();
    return Plugin_Handled;
}

void Resize_ProcessPending(int eventViewer = 0, int eventToken = 0) {
    if (g_ResizePending == null)return;
    ResizePlacement placement;
    for (int i = g_ResizePending.Length - 1; i >= 0; i--) {
        g_ResizePending.GetArray(i, placement, sizeof(placement));
        if (eventViewer > 0 && (placement.serial[eventViewer] == 0
            || (placement.textureToken[eventViewer] != eventToken && placement.materialToken[eventViewer] != eventToken)))continue;
        int owner = GetClientFromSerial(placement.ownerSerial);
        int sprayer = GetClientFromSerial(placement.sprayerSerial);
        int entity = placement.entityRef == 0 ? 0 : EntRefToEntIndex(placement.entityRef);
        if (!Human(owner) || !Human(sprayer) || entity < 0 || !g_ResizeEnabled.BoolValue) {
            g_ResizePending.Erase(i);continue;
        }
        int targets[MAXPLAYERS], count;
        for (int viewer = 1; viewer <= MaxClients; viewer++) {
            if (placement.serial[viewer] == 0 || placement.deliveryState[viewer] == 3
                || (eventViewer > 0 && viewer != eventViewer))continue;
            if (GetClientFromSerial(placement.serial[viewer]) != viewer || !Human(viewer)) {
                placement.serial[viewer] = 0;continue;
            }
            int state = ESprays_AssetStatus(viewer, placement.textureToken[viewer]);
            if (state == 1)continue;
            if (state != 2) {placement.serial[viewer] = 0;continue;}
            if (placement.materialToken[viewer] == 0) {
                int timeout = RoundToCeil(g_ResizeTimeout.FloatValue);
                placement.materialToken[viewer] = ESprays_RequestAsset(viewer, placement.materialFile, timeout <= 0 ? 60 : timeout);
                placement.deliveryState[viewer] = 2;
            }
            state = ESprays_AssetStatus(viewer, placement.materialToken[viewer]);
            if (state == 2)placement.deliveryState[viewer] = 3;
            else if (state == 1)continue;
            else placement.serial[viewer] = 0;
        }
        bool pending;
        for (int viewer = 1; viewer <= MaxClients; viewer++) {
            if (placement.serial[viewer] != 0 && placement.deliveryState[viewer] != 3) {pending = true;break;}
        }
        if (pending) {
            g_ResizePending.SetArray(i, placement, sizeof(placement));continue;
        }
        g_ResizePending.Erase(i);
        // Policy is checked once at placement, not repeatedly for every other
        // recipient's completion callback. Also honors external ESprays consumers.
        for (int viewer = 1; viewer <= MaxClients; viewer++)
            if (placement.serial[viewer] != 0 && GetClientFromSerial(placement.serial[viewer]) == viewer
                && Resize_Viewer(owner, viewer))targets[count++] = viewer;
        if (count == 0)continue;
        if (!g_ResizeMaterials.ContainsKey(placement.material) && g_ResizeMaterials.Size >= RESIZE_MATERIAL_LIMIT)continue;
        int table = FindStringTable("decalprecache");
        if (table < 0 || GetStringTableNumStrings(table) >= GetStringTableMaxStrings(table) - 32)continue;
        // Do not advertise the material until all eligible recipients have either
        // received texture + VMT or failed; failed viewers never get the decal.
        int index = PrecacheDecal(placement.material, false);
        if (index <= 0)continue;
        if (!g_ResizeMaterials.ContainsKey(placement.material))
            g_ResizeMaterials.SetValue(placement.material, view_as<int>(GetEngineTime()));
        TE_Start(placement.bsp ? "BSP Decal" : "Entity Decal");
        TE_WriteVector("m_vecOrigin", placement.position);
        TE_WriteNum("m_nEntity", entity);TE_WriteNum("m_nIndex", index);
        if (!placement.bsp) {
            TE_WriteVector("m_vecStart", placement.position);
            TE_WriteNum("m_nHitbox", placement.hitbox);
        }
        TE_Send(targets, count);
        Moderation_RecordPlacement(owner, entity, placement.position);
        Moderation_EmitSpraySound(placement.position);
        if (g_ResizeLogLevel.IntValue >= 3)LogMessage("Resized spray placed: viewers=%d pending=%d", count, g_ResizePending.Length);
    }
}
public Action Resize_Info(int client, int args) {
    if (!Human(client))return Plugin_Handled;
    int target = client;
    if (args > 0 && Resize_Admin(client)) {
        char argument[64];GetCmdArg(1, argument, sizeof(argument));
        target = FindTarget(client, argument, true, true);
        if (!Human(target))return Plugin_Handled;
    }
    int width, height, frames, crc;
    bool ready = ESprays_GetTextureInfo(target, width, height, frames, crc);
    ReplyToCommand(client, "[Sprays] Ready=%d size=%dx%d frames=%d CRC=%08x; pending placements=%d",
        ready, width, height, frames, crc, g_ResizePending.Length);
    return Plugin_Handled;
}
