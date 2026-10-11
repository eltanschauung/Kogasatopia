// SPDX-License-Identifier: GPL-3.0-or-later
#include "asset_delivery.h"
#include <cassert>
#include <cstdio>

int main(){
    using namespace spray_assets;
    const std::string path="materials/enhanced_sprays/decals/abcdef12_2500.vmt";
    assert(AllowedPath(path)&&AllowedPath("materials/temp/abcdef12.vtf"));
    for(const char *bad:{"cfg/server.cfg","materials/temp/../secret.vtf","materials/temp/ABCDEFGH.vtf",
        "materials/enhanced_sprays/decals/abcdef12_1/../../a.vmt","materials/enhanced_sprays/decals/abcdef12_nan.vmt"})assert(!AllowedPath(bad));
    Ledger ledger;
    assert(ledger.Begin(path,1,11,10,20));assert(ledger.Existing(path)==1);
    assert(!ledger.Begin(path,2,12,10,20));assert(ledger.Status(1)==1);
    assert(!ledger.Begin("materials/temp/abcdef12.vtf",1,12,10,20));
    ledger.Poll(10.05,[](const auto &){return false;});assert(ledger.Status(1)==1);
    ledger.Poll(11,[](const auto &){return true;});assert(ledger.TakeEvents().empty());
    ledger.Poll(12,[](const auto &){return false;});assert(ledger.Status(1)==2);
    auto done=ledger.TakeEvents();assert(done.size()==1&&done[0].success&&done[0].token==1);
    ledger.Poll(13,[](const auto &){return false;});assert(ledger.TakeEvents().empty());
    assert(ledger.Begin("materials/temp/abcdef12.vtf",2,12,15,1));
    ledger.Poll(16,[](const auto &){return true;});assert(ledger.Status(2)==-1);
    assert(!ledger.TakeEvents()[0].success);
    assert(ledger.Begin("materials/temp/abcdef12.vtf",3,13,17,10));assert(ledger.Status(2)==0);
    ledger.Denied(13);assert(ledger.Status(3)==-1&&ledger.Pending()==0);
    ledger.Clear();assert(ledger.Status(1)==0&&ledger.TakeEvents().empty());
    // Disconnect/map reset destroys the ledger; an old token cannot hit a new session.
    assert(ledger.Begin(path,4,14,20,10));assert(ledger.Status(1)==0);
    ledger.Clear();
    for(int i=0;i<int(Ledger::Capacity);++i)
        assert(ledger.Begin("materials/enhanced_sprays/decals/abcdef12_"+std::to_string(i)+".vmt",i+10,i+20,30,10));
    assert(!ledger.Begin(path,9999,9999,30,10));
    std::puts("Asset delivery: path restrictions, coalescing, completion, retry, timeout, reset and capacity passed");
}
