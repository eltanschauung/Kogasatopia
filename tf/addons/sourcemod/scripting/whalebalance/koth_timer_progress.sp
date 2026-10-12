// Event-driven KOTH progress: snapshot once at the first capture, compare at
// full-round end. Entrefs prevent replaced/recycled timers using stale baselines.
#define KOTH_MIN_TIMER_PROGRESS 0.20
#define KOTH_TIMER_RED 0
#define KOTH_TIMER_BLU 1

enum KothTimerProgress
{
    KothTimerProgress_Unavailable = 0,
    KothTimerProgress_Competitive,
    KothTimerProgress_Stomp
};

bool g_bKothTimerBaselineAttempted = false;
bool g_bKothTimerBaselineValid = false;
int g_iKothFirstCaptureTimerRefs[2] = {INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE};
float g_flKothFirstCaptureTimes[2];

void ResetKothTimerProgress()
{
    g_bKothTimerBaselineAttempted = false;
    g_bKothTimerBaselineValid = false;
    for (int i = 0; i < sizeof(g_iKothFirstCaptureTimerRefs); i++)
    {
        g_iKothFirstCaptureTimerRefs[i] = INVALID_ENT_REFERENCE;
        g_flKothFirstCaptureTimes[i] = 0.0;
    }
}

void RecordKothFirstCaptureTimers()
{
    if (g_bKothTimerBaselineAttempted)
    {
        return;
    }
    g_bKothTimerBaselineAttempted = true;

    int timers[2];
    DGM_FindKothTimers(timers[KOTH_TIMER_RED], timers[KOTH_TIMER_BLU]);
    if (timers[KOTH_TIMER_RED] == -1 || timers[KOTH_TIMER_BLU] == -1
        || timers[KOTH_TIMER_RED] == timers[KOTH_TIMER_BLU])
    {
        LogWhale("KOTH first-capture timers unavailable; using capture-based fallback this round.");
        return;
    }

    for (int i = 0; i < sizeof(timers); i++)
    {
        float remaining = DGM_GetRoundTimerRemainingFloat(timers[i]);
        // Reject zero/negative/unreadable values (and NaN). A zero baseline
        // cannot define a percentage of the initial timer.
        if (!(remaining > 0.0))
        {
            LogWhale("KOTH first-capture timer value unavailable; using capture-based fallback this round.");
            return;
        }
        g_iKothFirstCaptureTimerRefs[i] = EntIndexToEntRef(timers[i]);
        g_flKothFirstCaptureTimes[i] = remaining;
    }
    g_bKothTimerBaselineValid = true;
    LogWhale("KOTH first-capture timers recorded: red=%.3f blu=%.3f.",
        g_flKothFirstCaptureTimes[KOTH_TIMER_RED], g_flKothFirstCaptureTimes[KOTH_TIMER_BLU]);
}

KothTimerProgress GetKothTimerProgress(float &redRemaining, float &bluRemaining)
{
    redRemaining = -1.0;
    bluRemaining = -1.0;
    if (!g_bKothTimerBaselineValid)
    {
        return KothTimerProgress_Unavailable;
    }

    float remaining[2];
    for (int i = 0; i < sizeof(remaining); i++)
    {
        int timer = EntRefToEntIndex(g_iKothFirstCaptureTimerRefs[i]);
        if (timer == INVALID_ENT_REFERENCE)
        {
            return KothTimerProgress_Unavailable;
        }
        remaining[i] = DGM_GetRoundTimerRemainingFloat(timer);
        if (!(remaining[i] >= 0.0))
        {
            return KothTimerProgress_Unavailable;
        }
    }

    redRemaining = remaining[KOTH_TIMER_RED];
    bluRemaining = remaining[KOTH_TIMER_BLU];
    for (int i = 0; i < sizeof(remaining); i++)
    {
        // Exactly 20% consumed still qualifies: the team must use MORE than
        // 20% of its own recorded timer to avoid this auto-scramble trigger.
        if (remaining[i] >= g_flKothFirstCaptureTimes[i] * (1.0 - KOTH_MIN_TIMER_PROGRESS))
        {
            return KothTimerProgress_Stomp;
        }
    }
    return KothTimerProgress_Competitive;
}

bool KothTimerProgressNeedsScramble(KothTimerProgress progress, bool redCapped, bool bluCapped)
{
    if (progress == KothTimerProgress_Unavailable)
    {
        return !redCapped || !bluCapped;
    }
    return progress == KothTimerProgress_Stomp;
}
