// SPDX-License-Identifier: GPL-3.0-or-later
// Dynamic schema injection, based on nosoop's SMExt-TFEconDynamic.
// Copyright (C) 2023 nosoop. SourceMod/Valve linking exception applies.
#include "attributes.h"
#include <IHandleSys.h>
#include <utlmap.h>
#include <utlstring.h>
#include <map>
#include <memory>
#include <string>
#include <cctype>
#include <cstdlib>

namespace weapons_schema {
struct EngineKeys;
static EngineKeys *(*copyKeys)(const EngineKeys *);
static void (*deleteKeys)(EngineKeys *);
static void (*clearKeys)(EngineKeys *);
static const char *(*keyName)(const EngineKeys *);
static void (*setKeyName)(EngineKeys *, const char *);
static const char *(*getString)(EngineKeys *, const char *, const char *);
static void (*setString)(EngineKeys *, const char *, const char *);
static bool (*getBool)(EngineKeys *, const char *, bool, bool *);
static void (*setInt)(EngineKeys *, const char *, int);
// Opaque engine objects: current TF2 KeyValues are larger than the HL2SDK
// copy and their child pointers have moved. Never allocate, dereference, copy
// or destroy them using the SDK's locally linked KeyValues implementation.
struct EngineKeys {
    EngineKeys *MakeCopy() const { return copyKeys(this); }
    void deleteThis() { deleteKeys(this); }
    const char *GetName() const { return keyName(this); }
    void SetName(const char *name) { setKeyName(this, name); }
    const char *GetString(const char *key) { return getString(this, key, ""); }
    void SetString(const char *key, const char *value) { setString(this, key, value); }
    bool GetBool(const char *key) { return getBool(this, key, false, nullptr); }
    void SetBool(const char *key, bool value) { setInt(this, key, int(value)); }
};
// Linux x86 engine-owned definition layout. Never run a locally invented
// destructor on these definitions: their strings/types belong to the engine.
struct Definition {
    EngineKeys *keys;
    unsigned short index;
    void *type;
    bool hidden, forceDescription, integer, instance;
    int assetExport, assetBucket;
    bool setBonus;
    int userGenerated, effect, format;
    char *description, *armory, *name, *attributeClass;
    bool market, recipe;
    int tag;
    string_t pooledClass;
};
static_assert(sizeof(Definition) == 0x44, "Schema port requires the Linux x86 definition ABI");
using Attributes = CUtlMap<int, Definition, int>;
using Names = CUtlMap<const char *, int, int>;
struct DeleteKeys { void operator()(EngineKeys *kv) const { if (kv) kv->deleteThis(); } };
using Keys = std::unique_ptr<EngineKeys, DeleteKeys>;
static Keys emptyTemplate;
struct Container { Keys keys{emptyTemplate->MakeCopy()}; };

static void *(*getSchema)();
static bool (*initialize)(Definition *, EngineKeys *, CUtlVector<CUtlString> *);
static int attributesOffset, namesOffset;
static Attributes *attributes;
static Names *names;
static HandleType_t handleType;
static std::map<std::string, Keys> registered;
static std::map<std::string, int> autoIndices;
static int nextAutoIndex = 4000;

static std::string Canonical(const char *name) {
    std::string key(name);
    for (char &ch : key) ch = char(std::tolower(static_cast<unsigned char>(ch)));
    return key;
}
static bool Refresh() {
    void *schema = getSchema ? getSchema() : nullptr;
    if (!schema) return false;
    auto *currentAttributes = &weapons_services::Field<Attributes>(schema, attributesOffset);
    auto *currentNames = &weapons_services::Field<Names>(schema, namesOffset);
    // Fail closed on an incompatible layout, before any tree mutation.
    if (currentAttributes->Count() < 100 || currentAttributes->Count() > 65535) return false;
    int index = currentAttributes->Find(2); // Valve's fixed damage bonus definition.
    if (index == currentAttributes->InvalidIndex()) return false;
    const auto &definition = currentAttributes->Element(index);
    if (definition.index != 2 || !definition.keys || !definition.name
        || std::strcmp(definition.name, "damage bonus")) return false;
    int nameIndex = currentNames->Find("damage bonus");
    if (nameIndex == currentNames->InvalidIndex() || currentNames->Element(nameIndex) != index) return false;
    attributes = currentAttributes;
    names = currentNames;
    return true;
}
static Definition *ByName(const char *name) {
    int at = names->Find(name);
    if (at == names->InvalidIndex()) return nullptr;
    int index = names->Element(at);
    if (!attributes->IsValidIndex(index)) return nullptr;
    auto &definition = attributes->Element(index);
    return definition.name && !stricmp(definition.name, name) ? &definition : nullptr;
}
static bool IsInjected(const Definition &definition) {
    return definition.keys && definition.keys->GetBool("injected");
}
static bool Inject(EngineKeys *source) {
    if (!Refresh()) {
        g_pSM->LogError(myself, "Weapons schema: runtime layout validation failed");
        return false;
    }
    Keys copy(source->MakeCopy());
    const char *attributeName = copy->GetString("name");
    const char *attributeClass = copy->GetString("attribute_class");
    if (!*attributeName || !*attributeClass) {
        g_pSM->LogError(myself, "Weapons schema: missing required name/class (%d/%d)", int(*attributeName != 0), int(*attributeClass != 0));
        return false;
    }
    std::string key = Canonical(attributeName);
    bool automatic = !std::strcmp(copy->GetName(), "auto");
    int id = 0;
    Definition *named = ByName(attributeName);
    if (named && !IsInjected(*named)) return false; // Also protect Valve names, not just IDs.
    if (automatic) {
        if (named) id = named->index;
        else if (auto found = autoIndices.find(key); found != autoIndices.end()) {
            int at = attributes->Find(found->second);
            if (at == attributes->InvalidIndex()) id = found->second;
            else {
                const auto &definition = attributes->Element(at);
                if (IsInjected(definition) && definition.name && Canonical(definition.name) == key) id = found->second;
            }
        }
        if (!id) {
            while (nextAutoIndex <= 65535 && attributes->Find(nextAutoIndex) != attributes->InvalidIndex()) ++nextAutoIndex;
            if (nextAutoIndex > 65535) return false;
            id = nextAutoIndex;
        }
    } else {
        char *end = nullptr;
        long parsed = std::strtol(copy->GetName(), &end, 10);
        if (!end || *end || parsed <= 0 || parsed > 65535) {
            g_pSM->LogError(myself, "Weapons schema: invalid definition index string");
            return false;
        }
        id = int(parsed);
    }
    if (named && named->index != id) return false; // Never create ambiguous name aliases.
    int existing = attributes->Find(id);
    std::string previousName;
    if (existing != attributes->InvalidIndex()) {
        auto &definition = attributes->Element(existing);
        if (!IsInjected(definition)) return false;
        if (definition.name) previousName = definition.name;
    }
    copy->SetName(std::to_string(id).c_str());
    copy->SetBool("injected", true);
    Definition definition{};
    CUtlVector<CUtlString> errors;
    bool initialized = initialize(&definition, copy.get(), &errors);
    if (!initialized || !definition.keys || !definition.type || !definition.name || !*definition.name || definition.index != id) {
        g_pSM->LogError(myself, "Weapons schema definition validation: init=%d keys=%d type=%d name=%d index=%d expected=%d",
            int(initialized), int(definition.keys != nullptr), int(definition.type != nullptr), int(definition.name != nullptr), int(definition.index), id);
        for (int i = 0; i < errors.Count(); ++i) g_pSM->LogError(myself, "Weapons schema engine validation: %s", errors[i].Get());
        return false;
    }
    int inserted = attributes->InsertOrReplace(id, definition);
    if (inserted == attributes->InvalidIndex()) return false;
    // October 2026 TF2 uses this secondary index exclusively for name lookup.
    // Remove a renamed definition's old alias before registering the new one.
    if (!previousName.empty() && stricmp(previousName.c_str(), definition.name)) {
        int old = names->Find(previousName.c_str());
        if (old != names->InvalidIndex() && names->Element(old) == inserted) names->RemoveAt(old);
    }
    names->InsertOrReplace(attributes->Element(inserted).name, inserted);
    if (automatic) autoIndices[key] = id;
    // CUtlMap insertion can relocate its entire backing allocation. Invalidate
    // the merged attribute service here, not via a second SourcePawn boundary.
    weapons_services::InvalidateAttributeDefinitions();
    return true;
}

class Handles final : public IHandleTypeDispatch {
    void OnHandleDestroy(HandleType_t, void *object) override { delete static_cast<Container *>(object); }
} handles;
static Container *Read(IPluginContext *context, cell_t raw) {
    HandleSecurity security(context->GetIdentity(), myself->GetIdentity());
    Container *container = nullptr;
    HandleError error = handlesys->ReadHandle(Handle_t(raw), handleType, &security, reinterpret_cast<void **>(&container));
    if (error != HandleError_None) context->ThrowNativeError("Invalid WeaponsSchemaAttribute handle (error %d)", int(error));
    return container;
}
static cell_t Create(IPluginContext *context, const cell_t *) {
    auto container = std::make_unique<Container>();
    HandleError error;
    Handle_t handle = handlesys->CreateHandle(handleType, container.get(), context->GetIdentity(), myself->GetIdentity(), &error);
    if (!handle) return context->ThrowNativeError("Cannot create WeaponsSchemaAttribute (error %d)", int(error));
    container.release();
    return cell_t(handle);
}
static cell_t Set(IPluginContext *context, const cell_t *p, const char *key) {
    auto *container = Read(context, p[1]);
    if (container) container->keys->SetString(key, weapons_services::Text(context, p[2]));
    return 0;
}
static cell_t SetClass(IPluginContext *c, const cell_t *p) { return Set(c, p, "attribute_class"); }
static cell_t SetName(IPluginContext *c, const cell_t *p) { return Set(c, p, "name"); }
static cell_t SetFormat(IPluginContext *c, const cell_t *p) { return Set(c, p, "description_format"); }
static cell_t SetCustom(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (container) container->keys->SetString(weapons_services::Text(context, p[2]), weapons_services::Text(context, p[3]));
    return 0;
}
static cell_t SetIndex(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (!container) return 0;
    if (p[2] <= 0 || p[2] > 65535) return context->ThrowNativeError("Attribute definition index must be 1..65535");
    container->keys->SetName(std::to_string(p[2]).c_str());
    return 0;
}
static cell_t ClearIndex(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (container) container->keys->SetName("auto");
    return 0;
}
static cell_t Register(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (!container) return 0;
    Keys copy(container->keys->MakeCopy());
    if (!*copy->GetString("name")) copy->SetString("name", copy->GetString("attribute_class"));
    if (!*copy->GetString("name") || !Inject(copy.get())) return 0;
    std::string key = Canonical(copy->GetString("name"));
    // Failed registrations never pollute the map-reinstallation registry.
    // Keep only one registered definition for an ID that has been renamed.
    Definition *definition = ByName(copy->GetString("name"));
    int id = definition->index;
    for (auto entry = registered.begin(); entry != registered.end();) {
        Definition *other = ByName(entry->second->GetString("name"));
        if (entry->first != key && (!other || other->index == id)) entry = registered.erase(entry);
        else ++entry;
    }
    registered[key] = std::move(copy);
    return 1;
}
static cell_t Import(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (!container || !Refresh()) return 0;
    auto *definition = ByName(weapons_services::Text(context, p[2]));
    if (!definition || !definition->keys) return 0;
    // Clone first so assigning an imported definition can never self-free.
    container->keys.reset(definition->keys->MakeCopy());
    return 1;
}
static cell_t Clear(IPluginContext *context, const cell_t *p) {
    auto *container = Read(context, p[1]);
    if (container) container->keys.reset(emptyTemplate->MakeCopy());
    return 0;
}
static const sp_nativeinfo_t natives[] = {
    {"WeaponsSchemaAttribute.WeaponsSchemaAttribute", Create},
    {"WeaponsSchemaAttribute.SetClass", SetClass}, {"WeaponsSchemaAttribute.SetName", SetName},
    {"WeaponsSchemaAttribute.SetDescriptionFormat", SetFormat}, {"WeaponsSchemaAttribute.SetCustom", SetCustom},
    {"WeaponsSchemaAttribute.SetDefIndex", SetIndex}, {"WeaponsSchemaAttribute.ClearDefIndex", ClearIndex},
    {"WeaponsSchemaAttribute.Register", Register}, {"WeaponsSchemaAttribute.Import", Import},
    {"WeaponsSchemaAttribute.Clear", Clear}, {nullptr, nullptr}
};
class Schema final : public SDKExtension {
    bool SDK_OnLoad(char *error, size_t length, bool) override {
        IGameConfig *config = nullptr;
        if (!weapons_services::OpenConfig(WEAPONS_GAMECONFIG_NAME, config, error, length)) return false;
        getSchema = weapons_services::Symbol<decltype(getSchema)>(config, "GEconItemSchema");
        initialize = weapons_services::Symbol<decltype(initialize)>(config, "CEconItemAttributeDefinition::BInitFromKV");
#define KEY_BIND(variable, name) variable = weapons_services::Symbol<decltype(variable)>(config, name)
        KEY_BIND(copyKeys, "KeyValues::MakeCopy"); KEY_BIND(deleteKeys, "KeyValues::deleteThis");
        KEY_BIND(clearKeys, "KeyValues::Clear"); KEY_BIND(keyName, "KeyValues::GetName");
        KEY_BIND(setKeyName, "KeyValues::SetName"); KEY_BIND(getString, "KeyValues::GetString");
        KEY_BIND(setString, "KeyValues::SetString"); KEY_BIND(getBool, "KeyValues::GetBool");
        KEY_BIND(setInt, "KeyValues::SetInt");
#undef KEY_BIND
        bool layout = weapons_services::Offset(config, "SchemaAttributes", attributesOffset)
            && weapons_services::Offset(config, "SchemaAttributeNames", namesOffset);
        gameconfs->CloseGameConfigFile(config);
        if (!getSchema || !initialize || !layout || !copyKeys || !deleteKeys || !clearKeys
            || !keyName || !setKeyName || !getString || !setString || !getBool || !setInt || !Refresh()) {
            std::snprintf(error, length, "Weapons schema signatures/layout validation failed");
            return false;
        }
        // Obtain an engine-allocated empty template without guessing its size
        // or calling an SDK constructor. All future handles clone this template.
        emptyTemplate.reset(attributes->Element(attributes->Find(2)).keys->MakeCopy());
        clearKeys(emptyTemplate.get());
        emptyTemplate->SetName("auto");
        HandleError handleError;
        handleType = handlesys->CreateType("WeaponsSchemaAttribute", &handles, 0, nullptr, nullptr, myself->GetIdentity(), &handleError);
        if (!handleType) { std::snprintf(error, length, "Weapons schema handle type failed (%d)", int(handleError)); return false; }
        sharesys->AddNatives(myself, natives);
        return true;
    }
    void OnCoreMapStart(edict_t *, int, int) override {
        // Root dispatch runs after engine LevelInit, before plugin OnMapStart.
        // No second LevelInit hook or independent extension lifecycle owner.
        weapons_services::InvalidateAttributeDefinitions();
        for (const auto &entry : registered)
            if (!Inject(entry.second.get())) g_pSM->LogError(myself, "Weapons schema: map reinstallation rejected a registered definition");
    }
    void SDK_OnUnload() override {
        if (handleType) handlesys->RemoveType(handleType, myself->GetIdentity());
        handleType = 0;
        registered.clear(); autoIndices.clear(); nextAutoIndex = 4000;
        emptyTemplate.reset();
        attributes = nullptr; names = nullptr; getSchema = nullptr; initialize = nullptr;
        weapons_services::InvalidateAttributeDefinitions();
    }
} module;
}
SDKExtension &SchemaModule() { return weapons_schema::module; }
