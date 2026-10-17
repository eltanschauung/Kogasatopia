// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace weapons_services {
// Runtime TF2 x86 layout, matching SM-TFOnTakeDamage's class definitions.
// Deliberately not the SDK's potentially stale CTakeDamageInfo class.
struct DamageInfo {
    float force[3],position[3],reported[3];
    uint32_t inflictor,attacker,weapon;
    float damage,maxDamage,baseDamage;
    int type,custom,stats,ammo,otherPlayers,penetration;
    float bonus;
    uint32_t bonusProvider;
    bool friendlyFire;
    uint8_t padding[3];
    float damageForForce;
    int crit;
};
static_assert(sizeof(DamageInfo)==104 && offsetof(DamageInfo,crit)==100,"TF2 x86 damage ABI");

inline bool IsEngineerBuilding(const char *name) {
    return name && (!std::strcmp(name,"obj_sentrygun")
        || !std::strcmp(name,"obj_dispenser") || !std::strcmp(name,"obj_teleporter"));
}

// Suppress only the scratch record's public rules forward, not nested damage
// involving a different record. The owning slot is thread-local in damage.cpp.
struct DamageClassificationContext {
    const DamageInfo *info=nullptr;
    const void *victim=nullptr;
    bool Matches(const DamageInfo &record,const void *target) const {
        return info==&record && victim==target;
    }
};
class DamageClassificationScope {
    DamageClassificationContext &slot_;
    DamageClassificationContext previous_;
public:
    DamageClassificationScope(DamageClassificationContext &slot,const DamageInfo &scratch,const void *victim)
        :slot_(slot),previous_(slot) { slot_={&scratch,victim}; }
    ~DamageClassificationScope() { slot_=previous_; }
    DamageClassificationScope(const DamageClassificationScope &)=delete;
    DamageClassificationScope &operator=(const DamageClassificationScope &)=delete;
};

template<class Classify,class Notify,class Original>
int WithBuildingDamage(const char *name,const DamageInfo &input,Classify classify,Notify notify,Original original) {
    if (!IsEngineerBuilding(name)) return original(input);
    // Radius/multi-target damage may reuse the caller's record. Never mutate it
    // or a later building would receive a second crit multiplier. Stack-local
    // copies also keep nested damage independent; no per-entity state is needed.
    DamageInfo info=input;
    DamageInfo scratch=input;
    classify(scratch);
    // ApplyOnDamageModifyRules also changes damage, flags, bonus, force basis,
    // etc. None of those player-oriented results belong in building damage.
    // The original base damage and all metadata other than crit remain intact.
    info.crit=scratch.crit;
    notify(info);
    return original(info);
}
}
