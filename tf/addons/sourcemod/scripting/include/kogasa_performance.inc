#if defined _kogasa_performance_included
 #endinput
#endif
#define _kogasa_performance_included
#include <sourcemod>
#include <profiler>

// Additional arguments are optional: older compiled callers remain compatible.
// childrenMs contains completed direct children from this plugin only. The
// remainder includes engine work, other plugins and diagnostic overhead; it
// must never be described as exclusive SourcePawn CPU time.
native void CheckLag_RecordScope(const char[] scope, float milliseconds, const char[] context = "",
    int startTick = -1, int spanId = 0, int parentId = 0, float childrenMs = -1.0);
// Optional for compatibility with older CheckLag builds.
native bool CheckLag_IsProfilingEnabled();
public SharedPlugin __pl_kogasa_performance = {name="checklag", file="checklag.smx", required=0};
public void __pl_kogasa_performance_SetNTVOptional()
{
    MarkNativeAsOptional("CheckLag_RecordScope");
    MarkNativeAsOptional("CheckLag_IsProfilingEnabled");
}

// A small per-plugin stack handles nested/reentrant callbacks without creating
// a Profiler handle for every damage event or user command. Timings are inclusive.
static Profiler g_KogasaPerfProfiles[16];
static int g_KogasaPerfDepth;
static int g_KogasaPerfStartTick[16], g_KogasaPerfSpan[16], g_KogasaPerfParent[16];
static int g_KogasaPerfSequence;
static float g_KogasaPerfChildren[16];
static int g_KogasaPerfCachedTick = -1, g_KogasaPerfStarts;
static bool g_KogasaPerfEnabled;
stock int KogasaPerfBegin()
{
    if (g_KogasaPerfDepth >= sizeof(g_KogasaPerfProfiles)) return -1;
    int tick = GetGameTickCount();
    if (tick != g_KogasaPerfCachedTick)
    {
        g_KogasaPerfCachedTick = tick;
        g_KogasaPerfStarts = 0;
        g_KogasaPerfEnabled = GetFeatureStatus(FeatureType_Native, "CheckLag_RecordScope") == FeatureStatus_Available
            && GetFeatureStatus(FeatureType_Native, "CheckLag_IsProfilingEnabled") == FeatureStatus_Available
            && CheckLag_IsProfilingEnabled();
    }
    // Mode 1/2 have the same disabled producer path. Mode 3 admits at most 32
    // starts per plugin on each sampled tick, including nested scopes. Omitted
    // children remain unmeasured inclusive remainder, not exclusive CPU time.
    if (!g_KogasaPerfEnabled || g_KogasaPerfStarts >= 32) return -1;
    g_KogasaPerfStarts++;
    int slot = g_KogasaPerfDepth++;
    g_KogasaPerfStartTick[slot] = tick;
    g_KogasaPerfSpan[slot] = ++g_KogasaPerfSequence;
    g_KogasaPerfParent[slot] = slot > 0 ? g_KogasaPerfSpan[slot - 1] : 0;
    g_KogasaPerfChildren[slot] = 0.0;
    if (g_KogasaPerfProfiles[slot] == null) g_KogasaPerfProfiles[slot] = new Profiler();
    g_KogasaPerfProfiles[slot].Start();
    return slot;
}
stock void KogasaPerfEnd(int slot, const char[] scope, const char[] context = "")
{
    if (slot < 0 || slot >= g_KogasaPerfDepth || slot >= sizeof(g_KogasaPerfProfiles)) return;
    g_KogasaPerfProfiles[slot].Stop();
    g_KogasaPerfDepth = slot;
    float milliseconds = g_KogasaPerfProfiles[slot].Time * 1000.0;
    if (slot > 0) g_KogasaPerfChildren[slot - 1] += milliseconds;
    if (milliseconds >= 0.25 && milliseconds < 60000.0
        && GetFeatureStatus(FeatureType_Native, "CheckLag_RecordScope") == FeatureStatus_Available)
        CheckLag_RecordScope(scope, milliseconds, context, g_KogasaPerfStartTick[slot],
            g_KogasaPerfSpan[slot], g_KogasaPerfParent[slot], g_KogasaPerfChildren[slot]);
}
