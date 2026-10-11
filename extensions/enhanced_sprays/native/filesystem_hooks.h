// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>
#include <cstdint>

namespace spray_files {
struct Targets {void *exists,*open,*write,*close,*directory;};
struct Policy {
    bool (*exists)(const char *,const char *,bool &);
    bool (*beforeOpen)(const char *&,const char *,const char *&);
    void (*opened)(void *);
    bool (*write)(int,void *,int &);
    void (*closed)(void *);
    bool (*directory)(const char *,const char *);
};
// These detours do not enter SourceHook. Worker threads call the original
// filesystem directly; only the installing (game) thread may invoke Policy.
bool Install(const Targets &,const Policy &,char *error,size_t size);
void Uninstall();
uint64_t WorkerCalls();
}
