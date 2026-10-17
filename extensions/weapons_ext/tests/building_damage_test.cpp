// SPDX-License-Identifier: GPL-3.0-or-later
#include "services/damage_info.h"
#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>
using namespace weapons_services;
int main() {
    int checks=0;
    auto check=[&](bool result) { ++checks; assert(result); };
    auto identity=[](DamageInfo &) {};
    for (const char *name:{"obj_sentrygun","obj_dispenser","obj_teleporter"}) {
        check(IsEngineerBuilding(name));
        for (int crit:{-1,0,1,2,3}) for(int flags:{0,1<<20,(1<<20)|64}) {
            DamageInfo input{};
            input.damage=20.0f;input.maxDamage=20.0f;input.baseDamage=-1.0f;
            input.type=flags;input.crit=crit;input.custom=12;input.attacker=37;
            input.force[2]=14.0f;input.position[1]=100.0f;input.damageForForce=7.0f;
            const DamageInfo snapshot=input;
            const float expected=20.0f*(crit==1 ? 1.35f : crit==2 ? 3.0f : 1.0f);
            int calls=0,notifications=0;
            auto notify=[&](DamageInfo &info) {
                ++notifications;
                if(info.crit==1)info.damage*=1.35f;
                if(info.crit==2)info.damage*=3.0f;
            };
            auto original=[&](const DamageInfo &info) {
                ++calls;
                check(std::fabs(info.damage-expected)<0.0001f);
                auto unchanged=info;unchanged.damage=snapshot.damage;
                check(!std::memcmp(&unchanged,&snapshot,sizeof(info)));
                return 123;
            };
            // The SAME incoming record damages multiple targets, as in splash.
            for(int target=0;target<4;target++) {
                check(WithBuildingDamage(name,input,identity,notify,original)==123);
                check(!std::memcmp(&input,&snapshot,sizeof(input)));
            }
            check(calls==4 && notifications==4);
            // Reentrant damage must not inherit or consume another hit's state.
            WithBuildingDamage(name,input,identity,[&](DamageInfo &outer) {
                notify(outer);
                WithBuildingDamage(name,input,identity,notify,original);
                check(std::fabs(outer.damage-expected)<0.0001f);
            },original);
            check(!std::memcmp(&input,&snapshot,sizeof(input)));
        }
    }
    for(const char *name:{static_cast<const char *>(nullptr),"player","prop_physics","obj_attachment_sapper",
                         "obj_sentrygun_extra","tank_boss","eyeball_boss","obj_cart_dispenser"}) {
        check(!IsEngineerBuilding(name));
        DamageInfo info{};info.damage=20.0f;info.crit=2;
        int notified=0;
        int result=WithBuildingDamage(name,info,[&](DamageInfo &) {check(false);},[&](DamageInfo &) {++notified;},
            [&](const DamageInfo &passed) {check(&passed==&info);return 456;});
        check(result==456 && notified==0 && info.damage==20.0f);
    }
    for(int effective:{0,1,2}) {
        DamageInfo incoming{};incoming.damage=90.0f;incoming.crit=0;incoming.type=1<<6;
        incoming.attacker=37;incoming.inflictor=42;incoming.weapon=48;
        const auto saved=incoming;
        DamageClassificationContext probe;
        int buildingToken=0,playerToken=0;
        int notifications=0;
        WithBuildingDamage("obj_dispenser",incoming,[&](DamageInfo &scratch) {
            check(&scratch!=&incoming && !std::memcmp(&scratch,&saved,sizeof(scratch)));
            DamageClassificationScope guard(probe,scratch,&buildingToken);
            check(probe.Matches(scratch,&buildingToken) && !probe.Matches(incoming,&buildingToken));
            check(!probe.Matches(scratch,&playerToken)); // Same record, real player: do not suppress.
            DamageInfo nested{};
            { DamageClassificationScope inner(probe,nested,&playerToken);check(probe.Matches(nested,&playerToken)); }
            check(probe.Matches(scratch,&buildingToken));
            // A real rules call modifies much more than classification. Poison
            // all scratch bytes so leaking ANY field becomes a regression.
            std::memset(&scratch,0x5a,sizeof(scratch));scratch.crit=effective;
        },[&](DamageInfo &local) {
            ++notifications;
            check(probe.info==nullptr && local.crit==effective && local.damage==90.0f);
            auto comparison=local;comparison.crit=saved.crit;
            check(!std::memcmp(&comparison,&saved,sizeof(local)));
            local.damage*=effective==1?1.35f:effective==2?3.0f:1.0f;
        },[&](const DamageInfo &local) {
            check(std::fabs(local.damage-(effective==1?121.5f:effective==2?270.0f:90.0f))<0.0001f);
            auto comparison=local;comparison.crit=saved.crit;comparison.damage=saved.damage;
            check(!std::memcmp(&comparison,&saved,sizeof(local)));return 1;
        });
        check(notifications==1 && probe.info==nullptr && !std::memcmp(&incoming,&saved,sizeof(incoming)));
    }
    // Model Valve's monotonic setter, while observing its actual requests.
    for(int initial:{0,1,2}) for(int first:{0,1,2}) for(int later:{-1,0,1,2}) {
        DamageInfo scratch{};scratch.damage=90.0f;scratch.crit=initial;
        DamageInfo unrelated=scratch;
        DamageClassificationContext probe;
        int building=0,nestedVictim=0;
        auto request=[&](DamageInfo &record,int value) {
            probe.ObserveCritRequest(record,value);
            if(value==0 || value>record.crit) record.crit=value;
        };
        {
            DamageClassificationScope guard(probe,scratch,&building);
            request(scratch,first);
            const bool firstDemotion=initial==2 && first==1;
            check(probe.EffectiveCrit(scratch)==(firstDemotion ? 1 : scratch.crit));
            request(unrelated,1);
            check(probe.EffectiveCrit(scratch)==(firstDemotion ? 1 : scratch.crit));
            { // Nested damage must neither inherit nor erase the outer intent.
                DamageClassificationScope nested(probe,unrelated,&nestedVictim);
                request(unrelated,2);request(unrelated,1);
                check(probe.EffectiveCrit(unrelated)==1);
                check(probe.EffectiveCrit(scratch)==scratch.crit);
            }
            check(probe.EffectiveCrit(scratch)==(firstDemotion ? 1 : scratch.crit));
            if(later!=-1) request(scratch,later);
            const bool demotion=later==-1 ? firstDemotion : later==1 && scratch.crit==2;
            check(probe.EffectiveCrit(scratch)==(demotion ? 1 : scratch.crit));
            check(scratch.damage==90.0f); // Observing never changes damage/field.
            if(demotion) check(scratch.crit==2);
        }
        check(probe.info==nullptr && !probe.demoteFull);
        check(probe.EffectiveCrit(scratch)==scratch.crit);
    }
    std::cout<<"Building damage isolation: "<<checks<<" checks passed\n";
}
