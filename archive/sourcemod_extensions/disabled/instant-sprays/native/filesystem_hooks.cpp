// SPDX-License-Identifier: GPL-3.0-or-later
#include "filesystem_hooks.h"
#include "safetyhook/inline_hook.hpp"
#include <array>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <thread>

namespace spray_files {
namespace {
std::array<safetyhook::InlineHook,5> detours;
Policy policy{};
std::thread::id gameThread;
std::atomic<bool> enabled{false};
std::atomic<unsigned> active{0};
std::atomic<uint64_t> workerCalls{0};
struct Call {
    bool route;
    Call():route(false){
        active.fetch_add(1,std::memory_order_acquire);
        const bool game=std::this_thread::get_id()==gameThread;
        route=game&&enabled.load(std::memory_order_acquire);
        if(!game)workerCalls.fetch_add(1,std::memory_order_relaxed);
    }
    ~Call(){active.fetch_sub(1,std::memory_order_release);}
};

// Native member-function trampolines preserve thiscall on Win32 and the
// platform ABI on Linux/x64. No virtual dispatch or shared hook context occurs.
class Bridge {
public:
    bool Exists(const char *name,const char *id){
        Call scope;bool result=false;
        if(scope.route&&policy.exists&&policy.exists(name,id,result))return result;
        return (this->*existsOriginal)(name,id);
    }
    void *Open(const char *name,const char *options,const char *id){
        Call scope;
        const bool routed=scope.route&&policy.beforeOpen&&policy.beforeOpen(name,options,id);
        void *handle=(this->*openOriginal)(name,options,id);
        if(routed&&policy.opened)policy.opened(handle);
        return handle;
    }
    int Write(const void *bytes,int size,void *handle){
        Call scope;int result=0;
        if(scope.route&&policy.write&&policy.write(size,handle,result))return result;
        return (this->*writeOriginal)(bytes,size,handle);
    }
    void Close(void *handle){
        Call scope;(this->*closeOriginal)(handle);
        if(scope.route&&policy.closed)policy.closed(handle);
    }
    void Directory(const char *name,const char *id){
        Call scope;
        if(scope.route&&policy.directory&&policy.directory(name,id))return;
        (this->*directoryOriginal)(name,id);
    }
    static bool (Bridge::*existsOriginal)(const char *,const char *);
    static void *(Bridge::*openOriginal)(const char *,const char *,const char *);
    static int (Bridge::*writeOriginal)(const void *,int,void *);
    static void (Bridge::*closeOriginal)(void *);
    static void (Bridge::*directoryOriginal)(const char *,const char *);
};
bool (Bridge::*Bridge::existsOriginal)(const char *,const char *)=nullptr;
void *(Bridge::*Bridge::openOriginal)(const char *,const char *,const char *)=nullptr;
int (Bridge::*Bridge::writeOriginal)(const void *,int,void *)=nullptr;
void (Bridge::*Bridge::closeOriginal)(void *)=nullptr;
void (Bridge::*Bridge::directoryOriginal)(const char *,const char *)=nullptr;

template<class Member> bool Attach(size_t index,void *target,Member member,Member &original,char *error,size_t size){
    void *callback=nullptr;std::memcpy(&callback,&member,sizeof(callback));
    auto hook=safetyhook::InlineHook::create(target,callback,safetyhook::InlineHook::StartDisabled);
    if(!hook){std::snprintf(error,size,"Cannot prepare filesystem hook %zu (error %u)",index,unsigned(hook.error().type));return false;}
    void *trampoline=hook->original<void *>();
    original=nullptr;std::memcpy(&original,&trampoline,sizeof(trampoline));
    detours[index]=std::move(*hook);return true;
}
}
bool Install(const Targets &targets,const Policy &callbacks,char *error,size_t size){
    gameThread=std::this_thread::get_id();policy=callbacks;workerCalls=0;
    if(!Attach(0,targets.exists,&Bridge::Exists,Bridge::existsOriginal,error,size)
       ||!Attach(1,targets.open,&Bridge::Open,Bridge::openOriginal,error,size)
       ||!Attach(2,targets.write,&Bridge::Write,Bridge::writeOriginal,error,size)
       ||!Attach(3,targets.close,&Bridge::Close,Bridge::closeOriginal,error,size)
       ||!Attach(4,targets.directory,&Bridge::Directory,Bridge::directoryOriginal,error,size)){
        Uninstall();return false;
    }
    enabled.store(true,std::memory_order_release);
    for(size_t i=0;i<detours.size();++i){
        auto result=detours[i].enable();
        if(!result){std::snprintf(error,size,"Cannot enable filesystem hook %zu",i);Uninstall();return false;}
    }
    return true;
}
void Uninstall(){
    enabled.store(false,std::memory_order_release);
    for(auto &hook:detours)if(hook)(void)hook.disable();
    // Keep each trampoline alive until filesystem calls already inside this
    // module have returned. No game-thread callbacks run while draining.
    while(active.load(std::memory_order_acquire))std::this_thread::sleep_for(std::chrono::milliseconds(1));
    for(auto &hook:detours)hook.reset();
    policy={};
}
uint64_t WorkerCalls(){return workerCalls.load(std::memory_order_relaxed);}
}
