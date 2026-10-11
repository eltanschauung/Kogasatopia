// A decimal counter split before subtraction avoids float precision loss from
// long-running nanosecond totals. All supported counters are nonnegative.
bool CheckLag_ParseCounter(const char[] value, int counter[2])
{
    counter[0] = 0; counter[1] = 0;
    int length = strlen(value);
    if (length < 1 || length > 18) return false;
    for (int i = 0; i < length; i++)
        if (value[i] < '0' || value[i] > '9') return false;
    if (length <= 9) { counter[1] = StringToInt(value); return true; }
    char high[10];
    strcopy(high, length - 9 + 1, value);
    counter[0] = StringToInt(high);
    counter[1] = StringToInt(value[length - 9]);
    return true;
}

float CheckLag_CounterDelta(const int newer[2], const int older[2], bool nanos = false)
{
    if (newer[0] < older[0] || (newer[0] == older[0] && newer[1] < older[1]))
        return -1.0;
    int high = newer[0] - older[0], low = newer[1] - older[1];
    if (low < 0) { high--; low += 1000000000; }
    return nanos ? float(high) * 1000.0 + float(low) / 1000000.0
        : float(high) * 1000000000.0 + float(low);
}

stock bool CheckLag_FrameMatchesCall(int previousTick, int endTick, int callStartTick, int callEndTick)
{
    // OnGameFrame observes work from the preceding tick. Do not associate a
    // call elsewhere in the five-second window, or subsequent same-tick work.
    return endTick > previousTick && callEndTick >= previousTick && callEndTick < endTick
        && (callStartTick < 0 || (callStartTick >= previousTick && callStartTick <= callEndTick));
}

float CheckLag_UninstrumentedRemainder(float duration, float children)
{
    if (children < 0.0) return -1.0; // An older compiled caller did not supply this.
    return duration > children ? duration - children : 0.0;
}
