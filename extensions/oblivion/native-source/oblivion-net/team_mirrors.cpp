// SPDX-License-Identifier: GPL-3.0-or-later
#include "extension.h"
#include "team_mirrors.h"
#include "dt_send.h"
#include "server_class.h"
#include <cstring>
#include <unordered_map>
#include <vector>

namespace {
struct ArrayProxy {
    SendProp *prop = nullptr;
    SendVarProxyFn value = nullptr;
    ArrayLengthSendProxyFn length = nullptr;
} players, objects;
struct Mirror {
    cell_t reference;
    const void *pointer;
    std::vector<int> players, objects;
};
std::unordered_map<int, Mirror> mirrors;
bool installed;

const Mirror *Find(const void *pointer, int id) {
    auto found = mirrors.find(id);
    if (found == mirrors.end() || found->second.pointer != pointer
        || gamehelpers->ReferenceToEntity(found->second.reference) != pointer) return nullptr;
    return &found->second;
}
int PlayerLength(const void *pointer, int id) {
    auto mirror = Find(pointer, id);
    return mirror ? static_cast<int>(mirror->players.size()) : players.length(pointer, id);
}
int ObjectLength(const void *pointer, int id) {
    auto mirror = Find(pointer, id);
    return mirror ? static_cast<int>(mirror->objects.size()) : objects.length(pointer, id);
}
void PlayerValue(const SendProp *prop, const void *pointer, const void *data, DVariant *out, int element, int id) {
    if (auto mirror = Find(pointer, id)) {
        out->m_Int = element >= 0 && element < static_cast<int>(mirror->players.size()) ? mirror->players[element] : 0;
        return;
    }
    players.value(prop, pointer, data, out, element, id);
}
void ObjectValue(const SendProp *prop, const void *pointer, const void *data, DVariant *out, int element, int id) {
    if (auto mirror = Find(pointer, id)) {
        out->m_Int = element >= 0 && element < static_cast<int>(mirror->objects.size()) ? mirror->objects[element] : 0;
        return;
    }
    objects.value(prop, pointer, data, out, element, id);
}
bool Locate(ArrayProxy &array, const char *name) {
    sm_sendprop_info_t info;
    if (!gamehelpers->FindSendPropInfo("CTFTeam", name, &info)) {
        // SendPropArray2 stringifies its name argument; TF2's string-literal
        // declarations consequently include quotation marks in the wire name.
        char quoted[64]; snprintf(quoted, sizeof(quoted), "\"%s\"", name);
        if (!gamehelpers->FindSendPropInfo("CTFTeam", quoted, &info)) {
            smutils->LogError(myself, "Missing CTFTeam property %s", name);
            return false;
        }
    }
    if (info.prop->GetType() != DPT_Array
        || !info.prop->GetArrayProp() || !info.prop->GetArrayLengthProxy()
        || !info.prop->GetArrayProp()->GetProxyFn()) {
        smutils->LogError(myself, "CTFTeam %s: type=%d array=%d length=%d count=%d", name,
            info.prop->GetType(), info.prop->GetArrayProp() != nullptr,
            info.prop->GetArrayLengthProxy() != nullptr, info.prop->GetNumElements());
        return false;
    }
    array.prop = info.prop;
    array.length = info.prop->GetArrayLengthProxy();
    array.value = info.prop->GetArrayProp()->GetProxyFn();
    return true;
}
bool IsTeam(CBaseEntity *entity) {
    auto cls = entity ? gamehelpers->FindEntityServerClass(entity) : nullptr;
    return cls && std::strcmp(cls->GetName(), "CTFTeam") == 0;
}
cell_t Start(IPluginContext *context, const cell_t *) {
    if (installed) return 0;
    if (!Locate(players, "player_array") || !Locate(objects, "team_object_array"))
        return context->ThrowNativeError("Cannot locate TF2's dynamic team arrays");
    players.prop->SetArrayLengthProxy(PlayerLength);
    players.prop->GetArrayProp()->SetProxyFn(PlayerValue);
    objects.prop->SetArrayLengthProxy(ObjectLength);
    objects.prop->GetArrayProp()->SetProxyFn(ObjectValue);
    installed = true;
    return 0;
}
cell_t Update(IPluginContext *context, const cell_t *params) {
    const int targetIndex = params[1], sourceIndex = params[2], size = params[4];
    auto target = gamehelpers->ReferenceToEntity(targetIndex);
    auto source = gamehelpers->ReferenceToEntity(sourceIndex);
    if (!installed || !IsTeam(source) || !IsTeam(target) || source == target
        || size < 1 || size > 102 || mirrors.find(sourceIndex) != mirrors.end())
        return context->ThrowNativeError("Invalid private team update");
    cell_t *hidden;
    context->LocalToPhysAddr(params[3], &hidden);
    Mirror next{gamehelpers->EntityToReference(target), target, {}, {}};
    const int count = players.length(source, sourceIndex);
    const int objectCount = objects.length(source, sourceIndex);
    if (count < 0 || count > players.prop->GetNumElements()
        || objectCount < 0 || objectCount > objects.prop->GetNumElements())
        return context->ThrowNativeError("Invalid canonical team array length");
    for (int i = 0; i < count; ++i) {
        DVariant out{};
        auto prop = players.prop->GetArrayProp();
        players.value(prop, source, reinterpret_cast<const char *>(source) + prop->GetOffset(), &out, i, sourceIndex);
        if (out.m_Int > 0 && out.m_Int < size && hidden[out.m_Int]) continue;
        next.players.push_back(out.m_Int);
    }
    // Preserve the team's other network data, including full handle serials.
    for (int i = 0; i < objectCount; ++i) {
        DVariant out{};
        auto prop = objects.prop->GetArrayProp();
        objects.value(prop, source, reinterpret_cast<const char *>(source) + prop->GetOffset(), &out, i, sourceIndex);
        next.objects.push_back(out.m_Int);
    }
    auto found = mirrors.find(targetIndex);
    bool dirty = found == mirrors.end() || found->second.reference != next.reference
        || found->second.players != next.players || found->second.objects != next.objects;
    if (dirty) {
        mirrors[targetIndex] = std::move(next);
        gamehelpers->SetEdictStateChanged(gamehelpers->EdictOfIndex(targetIndex), 0);
    }
    return static_cast<cell_t>(mirrors[targetIndex].players.size());
}
cell_t Forget(IPluginContext *, const cell_t *params) { mirrors.erase(params[1]); return 0; }
cell_t Clear(IPluginContext *, const cell_t *) { mirrors.clear(); return 0; }

#ifdef OBLIVION_NETWORK_TESTS
// Read the exact length/value proxies used by Source's packet encoder.
cell_t ReadMembers(IPluginContext *context, const cell_t *params) {
    auto entity = gamehelpers->ReferenceToEntity(params[1]);
    if (!installed || !IsTeam(entity) || params[3] < 0) return context->ThrowNativeError("Invalid team fixture");
    cell_t *output; context->LocalToPhysAddr(params[2], &output);
    const int count = players.prop->GetArrayLengthProxy()(entity, params[1]);
    if (count > params[3]) return context->ThrowNativeError("Team fixture output too small");
    for (int i = 0; i < count; ++i) {
        DVariant out{}; auto prop = players.prop->GetArrayProp();
        prop->GetProxyFn()(prop, entity, reinterpret_cast<const char *>(entity) + prop->GetOffset(), &out, i, params[1]);
        output[i] = out.m_Int;
    }
    return count;
}
#endif
sp_nativeinfo_t natives[] = {
    {"OblivionNet_TeamStart", Start}, {"OblivionNet_TeamUpdate", Update},
    {"OblivionNet_TeamForget", Forget}, {"OblivionNet_TeamClear", Clear},
#ifdef OBLIVION_NETWORK_TESTS
    {"OblivionNet_TestTeamMembers", ReadMembers},
#endif
    {nullptr, nullptr}
};
}

void RegisterTeamMirrorNatives() { sharesys->AddNatives(myself, natives); }
void StopTeamMirrors() {
    mirrors.clear();
    if (!installed) return;
    if (players.prop->GetArrayLengthProxy() == PlayerLength) players.prop->SetArrayLengthProxy(players.length);
    if (players.prop->GetArrayProp()->GetProxyFn() == PlayerValue) players.prop->GetArrayProp()->SetProxyFn(players.value);
    if (objects.prop->GetArrayLengthProxy() == ObjectLength) objects.prop->SetArrayLengthProxy(objects.length);
    if (objects.prop->GetArrayProp()->GetProxyFn() == ObjectValue) objects.prop->GetArrayProp()->SetProxyFn(objects.value);
    installed = false;
}
