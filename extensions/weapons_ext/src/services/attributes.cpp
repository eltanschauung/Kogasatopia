// SPDX-License-Identifier: GPL-3.0-or-later
// Native port of TF2Attributes 1.7.5, originally by FlaminSarge.
// Preserves the game's attribute types, runtime ownership, and cache invalidation.
#include "attributes.h"
#include <algorithm>
#include <vector>
#include <unordered_set>

namespace weapons_services {
namespace {
IGameConfig *config;
SendOffsets offsets;
void *(*schema)();
void *(*itemDefinition)(void *, int);
void *(*socData)(void *);
void *(*definitionByID)(void *, int);
void *(*definitionByName)(void *, const char *);
void (*setRuntime)(void *, void *, float);
void *(*getAttribute)(void *, int);
void (*removeAttribute)(void *, void *);
void (*destroyAll)(void *);
void (*addCustom)(void *, const char *, float, float);
void (*removeCustom)(void *, const char *);
float (*hookFloat)(float, const char *, const CBaseEntity *, void *, bool);
int (*hookInt)(int, const char *, const CBaseEntity *, void *, bool);
// GCC's Linux x86 ABI returns string_t through a hidden, callee-popped
// output pointer even though it contains only one pointer. Use an actual
// by-value aggregate signature; treating it as an integer corrupts the stack.
struct PooledString { uintptr_t value; };
PooledString (*hookString)(void *, PooledString, CBaseEntity *, PooledString, void *);
void (*copyString)(uintptr_t, const char **);
PooledString (*pooledString)(const char *);
int changedSlot, initSlot, networkSlot, parseSlot, unloadSlot;
void *schemaIdentity;
std::unordered_map<std::string, void *> names;
std::unordered_map<int, void *> definitions;
struct Managed { void *type; uint32_t value; };
std::vector<Managed> managed;
std::unordered_map<std::string, uint32_t> stringValues;
std::unordered_set<uint32_t> managedValues;

void *Schema() {
    void *current = schema();
    if (current != schemaIdentity) {
        names.clear(); definitions.clear(); schemaIdentity = current;
    }
    return current;
}
void *Definition(int id) {
    void *current = Schema();
    if (!current) return nullptr;
    auto found = definitions.find(id);
    if (found != definitions.end()) return found->second;
    void *result = definitionByID(current, id);
    // Missing dynamic definitions must not poison a cache before registration.
    if (result) definitions.emplace(id, result);
    return result;
}
void *Definition(const char *name) {
    void *current = Schema();
    if (!current || !name) return nullptr;
    auto found = names.find(name);
    if (found != names.end()) return found->second;
    void *result = definitionByName(current, name);
    if (result) names.emplace(name, result);
    return result;
}
void *List(IPluginContext *ctx, cell_t ref, bool required = true) {
    auto *entity = Entity(ctx, ref);
    if (!entity) return nullptr;
    void *list = offsets.Member(entity, "m_AttributeList");
    if (!list && required) ctx->ThrowNativeError("Entity %d has no attribute list", ref);
    return list;
}
void *NativeDefinition(IPluginContext *ctx, const cell_t *p, bool byName) {
    void *def = byName ? Definition(Text(ctx, p[2])) : Definition(p[2]);
    if (!def) ctx->ThrowNativeError("Invalid attribute definition");
    return def;
}
void *Pointer(IPluginContext *ctx, cell_t raw) {
    uintptr_t value = uint32_t(raw);
    if (value < 0x10000) { ctx->ThrowNativeError("Invalid borrowed attribute address"); return nullptr; }
    return reinterpret_cast<void *>(value);
}
void Changed(void *list) {
    void *manager = Field<void *>(list, 0x18);
    if (manager) Virtual<void>(manager, changedSlot);
}
void Cleanup() {
    // Remove only values owned by this service. Remove before freeing, including
    // unload while entities are alive, so engine lists never hold freed strings.
    if (!managed.empty()) for (int index = 0; index < 2048; ++index) {
        auto *entity = gamehelpers->ReferenceToEntity(index);
        if (!entity) continue;
        void *list = offsets.Member(entity, "m_AttributeList");
        if (!list) continue;
        const int count = Field<int>(list, 0x10);
        if (count < 0 || count > 65536) continue;
        auto *data = Field<uint8_t *>(list, 4);
        std::vector<int> remove;
        for (int i = 0; data && i < count; ++i) {
            int id=Field<uint16_t>(data, i * 16 + 4);
            void *def=Definition(id);
            if (def && !Virtual<bool>(Field<void *>(def,8),networkSlot)
                && managedValues.count(Field<uint32_t>(data, i * 16 + 8)))
                remove.push_back(id);
        }
        for (int id : remove) if (void *def = Definition(id)) removeAttribute(list, def);
        if (!remove.empty()) Changed(list);
    }
    for (auto &value : managed) Virtual<void, uint32_t *>(value.type, unloadSlot, &value.value);
    managed.clear(); stringValues.clear(); managedValues.clear();
    names.clear(); definitions.clear(); schemaIdentity = nullptr;
}
cell_t Set(IPluginContext *ctx, const cell_t *p, bool byName) {
    void *list = List(ctx, p[1]); if (!list) return 0;
    void *def = NativeDefinition(ctx, p, byName); if (!def) return 0;
    setRuntime(list, def, sp_ctof(p[3])); return 1;
}
cell_t SetName(IPluginContext *c, const cell_t *p) { return Set(c,p,true); }
cell_t SetID(IPluginContext *c, const cell_t *p) { return Set(c,p,false); }
cell_t Get(IPluginContext *ctx, const cell_t *p, bool byName) {
    void *list = List(ctx, p[1], byName); if (!list) return 0;
    int id = p[2];
    if (byName) { void *def = NativeDefinition(ctx,p,true); if (!def) return 0; id = Field<uint16_t>(def,4); }
    return cell_t(uintptr_t(getAttribute(list,id)));
}
cell_t GetName(IPluginContext *c, const cell_t *p) { return Get(c,p,true); }
cell_t GetID(IPluginContext *c, const cell_t *p) { return Get(c,p,false); }
cell_t Remove(IPluginContext *ctx, const cell_t *p, bool byName) {
    void *list = List(ctx,p[1]); if (!list) return 0;
    void *def = NativeDefinition(ctx,p,byName); if (!def) return 0;
    removeAttribute(list,def); return 1;
}
cell_t RemoveName(IPluginContext *c, const cell_t *p) { return Remove(c,p,true); }
cell_t RemoveID(IPluginContext *c, const cell_t *p) { return Remove(c,p,false); }
cell_t RemoveAll(IPluginContext *ctx, const cell_t *p) {
    void *list = List(ctx,p[1]); if (!list) return 0; destroyAll(list); return 1;
}
cell_t ClearCache(IPluginContext *ctx, const cell_t *p) {
    void *list = List(ctx,p[1],false); if (!list) return 0; Changed(list); return 1;
}
cell_t SetString(IPluginContext *ctx, const cell_t *p) {
    void *list = List(ctx,p[1]); if (!list) return 0;
    void *def = Definition(Text(ctx,p[2])); if (!def) return 0;
    const char *text = Text(ctx,p[3]); if (!text) return 0;
    void *type = Field<void *>(def,8);
    bool networked = Virtual<bool>(type,networkSlot);
    void *knownString = Definition("cosmetic taunt sound");
    bool isString = knownString && type == Field<void *>(knownString,8);
    std::string key = std::to_string(Field<uint16_t>(def,4)) + ':' + text;
    auto found = stringValues.find(key);
    uint32_t value = 0;
    if (!networked && isString && found != stringValues.end()) value = found->second;
    else {
        Virtual<void, uint32_t *>(type,initSlot,&value);
        if (!Virtual<bool, void *, const char *, uint32_t *, bool>(type,parseSlot,def,text,&value,true)) {
            Virtual<void, uint32_t *>(type,unloadSlot,&value); return 0;
        }
        if (!networked) {
            managed.push_back({type,value}); managedValues.insert(value);
            if (isString) stringValues.emplace(std::move(key),value);
        }
    }
    float raw; std::memcpy(&raw,&value,4); setRuntime(list,def,raw); return 1;
}
template<int Offset, class T> cell_t Read(IPluginContext *ctx, const cell_t *p) {
    void *value = Pointer(ctx,p[1]); return value ? cell_t(Field<T>(value,Offset)) : 0;
}
template<int Offset, class T> cell_t Write(IPluginContext *ctx, const cell_t *p) {
    void *value = Pointer(ctx,p[1]); if (!value) return 0; Field<T>(value,Offset) = T(p[2]); return 0;
}
cell_t UnsafeString(IPluginContext *ctx, const cell_t *p) {
    if (p[3] <= 0) return 0;
    const char *text = nullptr; copyString(uint32_t(p[1]),&text);
    size_t written = 0; ctx->StringToLocalUTF8(p[2],p[3],text ? text : "",&written); return written;
}
cell_t ValidName(IPluginContext *ctx, const cell_t *p) { return Definition(Text(ctx,p[1])) != nullptr; }
cell_t Integer(IPluginContext *ctx, const cell_t *p) {
    void *def = Definition(p[1]); return def ? Field<uint8_t>(def,14) : ctx->ThrowNativeError("Invalid definition");
}
cell_t CustomAdd(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[1],true); if (!entity) return 0;
    const char *name = Text(ctx,p[2]); if (!Definition(name)) return ctx->ThrowNativeError("Invalid definition");
    addCustom(entity,name,sp_ctof(p[3]),sp_ctof(p[4])); return 0;
}
cell_t CustomRemove(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[1],true); if (!entity) return 0;
    const char *name = Text(ctx,p[2]); if (!Definition(name)) return ctx->ThrowNativeError("Invalid definition");
    removeCustom(entity,name); return 0;
}
cell_t HookFloat(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[3]); return entity ? sp_ftoc(hookFloat(sp_ctof(p[1]),Text(ctx,p[2]),entity,nullptr,false)) : 0;
}
cell_t HookInt(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[3]); return entity ? hookInt(p[1],Text(ctx,p[2]),entity,nullptr,false) : 0;
}
cell_t HookString(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[3]); if (!entity || p[5] <= 0) return 0;
    void *list = offsets.Member(entity,"m_AttributeList"); if (!list) return ctx->ThrowNativeError("No attribute manager");
    const char *initial = Text(ctx,p[1]), *attribute = Text(ctx,p[2]);
    // AttribHookValue uses pooled string_t handles. Pool via SourceMod's engine
    // helper instead of temporarily rewriting worldspawn's targetname.
    PooledString input = pooledString(initial);
    PooledString attr = pooledString(attribute);
    uintptr_t result = hookString(Field<void *>(list,24),input,entity,attr,nullptr).value;
    size_t written = 0;
    ctx->StringToLocalUTF8(p[4],p[5],result ? reinterpret_cast<const char *>(result) : "",&written);
    return written;
}
int CopyStatic(void *vector, IPluginContext *ctx, const cell_t *p, int max, int stride, int idOffset, int valueOffset) {
    if (max <= 0 || max > 65536) return ctx->ThrowNativeError("Invalid attribute array capacity");
    cell_t *ids = nullptr, *values = nullptr;
    if (ctx->LocalToPhysAddr(p[2],&ids) || ctx->LocalToPhysAddr(p[3],&values)) return 0;
    std::fill_n(ids,max,0); std::fill_n(values,max,0);
    int count = Field<int>(vector,12);
    if (count < 0 || count > 65536) return ctx->ThrowNativeError("Invalid engine attribute count");
    auto *data = Field<uint8_t *>(vector,0);
    if (count && !data) return ctx->ThrowNativeError("Missing attribute storage");
    for (int i=0; i<std::min(max,count); ++i) {
        ids[i]=Field<uint16_t>(data,i*stride+idOffset); values[i]=Field<uint32_t>(data,i*stride+valueOffset);
    }
    return count;
}
cell_t Static(IPluginContext *ctx, const cell_t *p) {
    void *def = itemDefinition(Schema(),p[1]);
    if (!def) return ctx->ThrowNativeError("Invalid item definition");
    return CopyStatic(static_cast<uint8_t *>(def)+28,ctx,p,p[4],8,0,4);
}
cell_t SOC(IPluginContext *ctx, const cell_t *p) {
    auto *entity = Entity(ctx,p[1]); if (!entity) return 0;
    void *view = offsets.Member(entity,"m_Item"); if (!view) return -1;
    void *soc = socData(view); if (!soc) return 0;
    void *vector = Field<void *>(soc,52);
    if (vector) return CopyStatic(vector,ctx,p,p[4],8,0,4);
    if (!(Field<uint8_t>(soc,39)&4)) return 0;
    if (p[4]<=0) return ctx->ThrowNativeError("Invalid capacity");
    cell_t *ids=nullptr,*values=nullptr;
    ctx->LocalToPhysAddr(p[2],&ids); ctx->LocalToPhysAddr(p[3],&values);
    if (!ids || !values) return 0;
    std::fill_n(ids,p[4],0); std::fill_n(values,p[4],0);
    ids[0]=Field<uint16_t>(soc,44); values[0]=Field<uint32_t>(soc,48); return 1;
}
cell_t ListIDs(IPluginContext *ctx, const cell_t *p) {
    void *list=List(ctx,p[1]); if (!list) return 0;
    if (p[3]<=0 || p[3]>65536) return ctx->ThrowNativeError("Invalid capacity");
    cell_t *ids=nullptr; if (ctx->LocalToPhysAddr(p[2],&ids)) return 0;
    std::fill_n(ids,p[3],0);
    int count=Field<int>(list,16); auto *data=Field<uint8_t *>(list,4);
    if (count<0 || count>65536 || (count && !data)) return ctx->ThrowNativeError("Invalid runtime list");
    for(int i=0;i<std::min(p[3],count);++i) ids[i]=Field<uint16_t>(data,i*16+4);
    return count;
}
cell_t Invalidate(IPluginContext *, const cell_t *) { InvalidateAttributeDefinitions(); return 0; }
sp_nativeinfo_t natives[] = {
    {"WeaponsAttrib_SetByName",SetName},{"WeaponsAttrib_SetByDefIndex",SetID},
    {"WeaponsAttrib_GetByName",GetName},{"WeaponsAttrib_GetByDefIndex",GetID},
    {"WeaponsAttrib_SetFromStringValue",SetString},{"WeaponsAttrib_RemoveByName",RemoveName},
    {"WeaponsAttrib_RemoveByDefIndex",RemoveID},{"WeaponsAttrib_RemoveAll",RemoveAll},
    {"WeaponsAttrib_ClearCache",ClearCache},{"WeaponsAttrib_ListDefIndices",ListIDs},
    {"WeaponsAttrib_GetStaticAttribs",Static},{"WeaponsAttrib_GetSOCAttribs",SOC},
    {"WeaponsAttrib_SetDefIndex",Write<4,uint16_t>},{"WeaponsAttrib_GetDefIndex",Read<4,uint16_t>},
    {"WeaponsAttrib_SetValue",Write<8,uint32_t>},{"WeaponsAttrib_GetValue",Read<8,uint32_t>},
    {"WeaponsAttrib_SetRefundableCurrency",Write<12,uint32_t>},{"WeaponsAttrib_GetRefundableCurrency",Read<12,uint32_t>},
    {"WeaponsAttrib_UnsafeGetStringValue",UnsafeString},{"WeaponsAttrib_IsValidAttributeName",ValidName},
    {"WeaponsAttrib_IsIntegerValue",Integer},{"WeaponsAttrib_AddCustomPlayerAttribute",CustomAdd},
    {"WeaponsAttrib_RemoveCustomPlayerAttribute",CustomRemove},{"WeaponsAttrib_HookValueFloat",HookFloat},
    {"WeaponsAttrib_HookValueInt",HookInt},{"WeaponsAttrib_HookValueString",HookString},
    {"WeaponsAttrib_InvalidateDefinitions",Invalidate},{nullptr,nullptr}
};
class Attributes final : public SDKExtension {
public:
    bool SDK_OnLoad(char *error,size_t length,bool) override {
        if (!OpenConfig("tf2.attributes",config,error,length)) return false;
        const char *message=config->GetKeyValue("PluginFailMessage");
        if(message && *message) { std::snprintf(error,length,"%s",message); return false; }
#define BIND(variable,key) variable=Symbol<decltype(variable)>(config,key); if(!variable) { std::snprintf(error,length,"Attributes: missing %s",key); return false; }
        BIND(schema,"GEconItemSchema"); BIND(itemDefinition,"CEconItemSchema::GetItemDefinition");
        BIND(socData,"CEconItemView::GetSOCData"); BIND(definitionByID,"CEconItemSchema::GetAttributeDefinition");
        BIND(definitionByName,"CEconItemSchema::GetAttributeDefinitionByName");
        BIND(setRuntime,"CAttributeList::SetRuntimeAttributeValue"); BIND(getAttribute,"CAttributeList::GetAttributeByID");
        BIND(removeAttribute,"CAttributeList::RemoveAttribute"); BIND(destroyAll,"CAttributeList::DestroyAllAttributes");
        BIND(addCustom,"CTFPlayer::AddCustomAttribute"); BIND(removeCustom,"CTFPlayer::RemoveCustomAttribute");
        BIND(hookFloat,"CAttributeManager::AttribHookValue<float>"); BIND(hookInt,"CAttributeManager::AttribHookValue<int>");
        BIND(hookString,"CAttributeManager::ApplyAttributeStringWrapper");
        BIND(copyString,"CopyStringAttributeValueToCharPointerOutput");
#undef BIND
        IGameConfig *services=nullptr;
        if(!OpenConfig("weapons.services",services,error,length)) return false;
        pooledString=Symbol<decltype(pooledString)>(services,"AllocPooledString");
        gameconfs->CloseGameConfigFile(services);
        if(!pooledString) { std::snprintf(error,length,"Missing AllocPooledString"); return false; }
#define SLOT(variable,key) if(!Offset(config,key,variable)) { std::snprintf(error,length,"Attributes: missing %s",key); return false; }
        SLOT(changedSlot,"CAttributeManager::OnAttributeValuesChanged");
        SLOT(initSlot,"ISchemaAttributeTypeBase::InitializeNewEconAttributeValue");
        SLOT(networkSlot,"ISchemaAttributeTypeBase::BSupportsGame...");
        SLOT(parseSlot,"ISchemaAttributeTypeBase::BConvertStringToEconAttributeValue");
        SLOT(unloadSlot,"ISchemaAttributeTypeBase::UnloadEconAttributeValue");
#undef SLOT
        sharesys->AddNatives(myself,natives); return true;
    }
    void OnCoreMapEnd() override { Cleanup(); }
    void SDK_OnUnload() override {
        if(config) { if(schema && definitionByID && removeAttribute) Cleanup(); gameconfs->CloseGameConfigFile(config); config=nullptr; }
    }
} module;
}
bool SetAttribute(CBaseEntity *entity,int definition,float value) {
    void *list=offsets.Member(entity,"m_AttributeList"),*def=Definition(definition);
    if(!list || !def) return false;
    setRuntime(list,def,value); return true;
}
void InvalidateAttributeDefinitions() { names.clear(); definitions.clear(); schemaIdentity=nullptr; }
}
SDKExtension &AttributesModule() { return weapons_services::module; }
