#if defined _kogasa_performance_included
 #endinput
#endif
#define _kogasa_performance_included
#include <sourcemod>
#include <profiler>

native void CheckLag_RecordScope(const char[] scope, float milliseconds, const char[] context = "");
public SharedPlugin __pl_kogasa_performance = {name="checklag", file="checklag.smx", required=0};
public void __pl_kogasa_performance_SetNTVOptional() { MarkNativeAsOptional("CheckLag_RecordScope"); }

// A small per-plugin stack handles nested/reentrant callbacks without creating
// a Profiler handle for every damage event or user command. Timings are inclusive.
static Profiler g_KogasaPerfProfiles[16];
static int g_KogasaPerfDepth;
stock int KogasaPerfBegin()
{
    if (g_KogasaPerfDepth >= sizeof(g_KogasaPerfProfiles)
        || GetFeatureStatus(FeatureType_Native, "CheckLag_RecordScope") != FeatureStatus_Available) return -1;
    int slot = g_KogasaPerfDepth++;
    if (g_KogasaPerfProfiles[slot] == null) g_KogasaPerfProfiles[slot] = new Profiler();
    g_KogasaPerfProfiles[slot].Start();
    return slot;
}
stock void KogasaPerfEnd(int slot, const char[] scope, const char[] context = "")
{
    if (slot < 0) return;
    g_KogasaPerfProfiles[slot].Stop();
    g_KogasaPerfDepth = slot;
    float milliseconds = g_KogasaPerfProfiles[slot].Time * 1000.0;
    if (milliseconds >= 0.0 && milliseconds < 60000.0
        && GetFeatureStatus(FeatureType_Native, "CheckLag_RecordScope") == FeatureStatus_Available)
        CheckLag_RecordScope(scope, milliseconds, context);
}
