// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace spray_assets {
inline bool Hex(const std::string &s) {
    return s.size()==8&&std::all_of(s.begin(),s.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');});
}
// This is intentionally not a general-purpose arbitrary-file download native.
inline bool AllowedPath(const std::string &path) {
    const std::string texture="materials/temp/",material="materials/enhanced_sprays/decals/";
    if(path.compare(0,texture.size(),texture)==0)
        return path.size()==texture.size()+12&&path.substr(path.size()-4)==".vtf"&&Hex(path.substr(texture.size(),8));
    if(path.compare(0,material.size(),material)!=0||path.size()>128||path.substr(path.size()-4)!=".vmt")return false;
    const auto stem=path.substr(material.size(),path.size()-material.size()-4);
    return stem.size()>9&&Hex(stem.substr(0,8))&&stem[8]=='_'&&
        std::all_of(stem.begin()+9,stem.end(),[](char c){return c>='0'&&c<='9';});
}
struct Job {
    int token=0,state=1;
    unsigned transfer=0;
    double checkAfter=0,deadline=0;
};
struct Event {int token;std::string path;bool success;};
class Ledger {
    std::map<std::string,Job> jobs;
    std::map<int,std::string> tokens;
    std::set<std::string> pending;
    std::vector<Event> events;
public:
    static constexpr size_t Capacity=512;
    // Reuses pending/successful deliveries, but permits retry after a failure.
    int Existing(const std::string &path) const {
        auto it=jobs.find(path);return it!=jobs.end()&&it->second.state>=1?it->second.token:0;
    }
    bool Begin(const std::string &path,int token,unsigned transfer,double now,double timeout) {
        if(token<=0||tokens.count(token)||!AllowedPath(path)||Existing(path)||(jobs.size()>=Capacity&&!jobs.count(path)))return false;
        auto old=jobs.find(path);if(old!=jobs.end())tokens.erase(old->second.token);
        jobs[path]={token,1,transfer,now+.1,now+std::clamp(timeout,1.0,60.0)};
        tokens[token]=path;pending.insert(path);return true;
    }
    void Finish(const std::string &path,bool success) {
        auto it=jobs.find(path);if(it==jobs.end()||it->second.state!=1)return;
        it->second.state=success?2:-1;pending.erase(path);events.push_back({it->second.token,path,success});
    }
    void Denied(unsigned transfer) {
        for(auto it=pending.begin();it!=pending.end();){auto path=*it++;if(jobs.at(path).transfer==transfer)Finish(path,false);}
    }
    template<class Waiting> void Poll(double now,Waiting waiting) {
        for(auto it=pending.begin();it!=pending.end();){auto path=*it++;const auto &job=jobs.at(path);
            if(now>=job.deadline)Finish(path,false);
            else if(now>=job.checkAfter&&!waiting(path))Finish(path,true);
        }
    }
    int Status(int token) const {
        auto it=tokens.find(token);return it==tokens.end()?0:jobs.at(it->second).state;
    }
    std::vector<Event> TakeEvents(){auto result=std::move(events);events.clear();return result;}
    size_t Pending() const{return pending.size();}
    void Clear(){jobs.clear();tokens.clear();pending.clear();events.clear();}
};
}
