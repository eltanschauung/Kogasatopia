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
                check(WithBuildingDamage(name,input,notify,original)==123);
                check(!std::memcmp(&input,&snapshot,sizeof(input)));
            }
            check(calls==4 && notifications==4);
            // Reentrant damage must not inherit or consume another hit's state.
            WithBuildingDamage(name,input,[&](DamageInfo &outer) {
                notify(outer);
                WithBuildingDamage(name,input,notify,original);
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
        int result=WithBuildingDamage(name,info,[&](DamageInfo &) {++notified;},
            [&](const DamageInfo &passed) {check(&passed==&info);return 456;});
        check(result==456 && notified==0 && info.damage==20.0f);
    }
    std::cout<<"Building damage isolation: "<<checks<<" checks passed\n";
}
