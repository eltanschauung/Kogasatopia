#ifndef KOGASA_SHARED_VTABLE_LIFETIME_H
#define KOGASA_SHARED_VTABLE_LIFETIME_H

// TF2Tools is GPL-3.0 with the AlliedModders engine-linking exception.
// Share only vtables owned by the game-server image. Private copies and tables
// from unloadable third-party modules must keep per-entity hook lifetimes.
#if defined _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

inline bool IsServerImageVtable(void **weaponVtable, void **serverVtable)
{
    if (!weaponVtable || !serverVtable)
        return false;
#if defined _WIN32
    MEMORY_BASIC_INFORMATION weaponInfo, serverInfo;
    return VirtualQuery(weaponVtable, &weaponInfo, sizeof(weaponInfo)) == sizeof(weaponInfo)
        && VirtualQuery(serverVtable, &serverInfo, sizeof(serverInfo)) == sizeof(serverInfo)
        && weaponInfo.Type == MEM_IMAGE && serverInfo.Type == MEM_IMAGE
        && weaponInfo.AllocationBase == serverInfo.AllocationBase;
#else
    Dl_info weaponInfo, serverInfo;
    return dladdr(weaponVtable, &weaponInfo) != 0
        && dladdr(serverVtable, &serverInfo) != 0
        && weaponInfo.dli_fbase == serverInfo.dli_fbase;
#endif
}

#endif
