#include "shared_vtable_lifetime.h"
#include <cassert>
#include <cstring>
#include <cstdio>

struct ServerImage { virtual int value() { return 1; } };
struct WeaponImage { virtual int value() { return 2; } };

int main()
{
    ServerImage server;
    WeaponImage weapon;
    void **serverVtable = *reinterpret_cast<void ***>(&server);
    void **weaponVtable = *reinterpret_cast<void ***>(&weapon);
    assert(IsServerImageVtable(weaponVtable, serverVtable));
    assert(!IsServerImageVtable(nullptr, serverVtable));
    assert(!IsServerImageVtable(weaponVtable, nullptr));
    void **privateVtable = new void *[1];
    privateVtable[0] = weaponVtable[0];
    assert(!IsServerImageVtable(privateVtable, serverVtable));
    delete[] privateVtable;
#if !defined _WIN32
    // Another loaded image must not be cached: it may unload independently.
    assert(!IsServerImageVtable(reinterpret_cast<void **>(&std::puts), serverVtable));
#endif
    std::puts("Shared-vtable lifetime policy: PASS");
}
