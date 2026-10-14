// Read-only, bounded Linux main-thread diagnostics. No PID, command line,
// environment, client identity, address or secret is recorded.
#define CHECKLAG_HOST_LIMIT 64
#define CHECKLAG_HOST_INTERVAL 0.25
#define CHECKLAG_HOST_CPU 1
#define CHECKLAG_HOST_WAIT 2
#define CHECKLAG_HOST_FAULTS 4
#define CHECKLAG_HOST_IO 8

enum struct CheckLagHostSample
{
    int flags;
    int sequence;
    int cpu[2];
    int wait[2];
    int slices[2];
    int minor[2];
    int major[2];
    int readBytes[2];
    int writeBytes[2];
    float at;
    float windowMs;
    float cpuMs;
    float waitMs;
    float sliceDelta;
    float minorDelta;
    float majorDelta;
    float readDelta;
    float writeDelta;
    float probeMs;
}

CheckLagHostSample g_LagHostSamples[CHECKLAG_HOST_LIMIT];
int g_LagHostCursor, g_LagHostSequence;
bool g_LagHostReady, g_LagHostWaitEnabled;
float g_LagHostNextAt;
Profiler g_LagHostClock;
Profiler g_LagHostIntervalClock;

// Read a bounded decimal token, retaining the exact text until subtraction.
static bool CheckLag_HostToken(const char[] line, int &position, char[] token, int size)
{
    while (line[position] == ' ' || line[position] == '\t') position++;
    int count;
    while (line[position] != '\0' && line[position] != ' '
        && line[position] != '\t' && line[position] != '\r' && line[position] != '\n')
    {
        if (count >= size - 1) return false;
        token[count++] = line[position++];
    }
    token[count] = '\0';
    return count > 0;
}

void CheckLag_HostReset()
{
    g_LagHostCursor = 0; g_LagHostSequence = 0;
    g_LagHostReady = false; g_LagHostNextAt = 0.0;
    if (g_CheckLagMode < 2) return;
    if (g_LagHostIntervalClock == null) g_LagHostIntervalClock = new Profiler();
    g_LagHostIntervalClock.Start();
    g_LagHostWaitEnabled = false;
    // SourceMod prefixes ordinary filenames with the game directory; file://
    // explicitly selects these absolute, read-only kernel paths.
    File file = OpenFile("file:///proc/sys/kernel/sched_schedstats", "rt");
    char value[16];
    if (file != null)
    {
        if (file.ReadLine(value, sizeof(value))) g_LagHostWaitEnabled = StringToInt(value) != 0;
        delete file;
    }
}

static void CheckLag_HostRead(CheckLagHostSample sample)
{
    sample.flags = 0;
    char line[1024], token[32];
    int position;
    File file = OpenFile("file:///proc/thread-self/schedstat", "rt");
    if (file != null)
    {
        if (file.ReadLine(line, sizeof(line))
            && CheckLag_HostToken(line, position, token, sizeof(token))
            && CheckLag_ParseCounter(token, sample.cpu)
            && CheckLag_HostToken(line, position, token, sizeof(token))
            && CheckLag_ParseCounter(token, sample.wait)
            && CheckLag_HostToken(line, position, token, sizeof(token))
            && CheckLag_ParseCounter(token, sample.slices))
        {
            sample.flags |= CHECKLAG_HOST_CPU;
            if (g_LagHostWaitEnabled) sample.flags |= CHECKLAG_HOST_WAIT;
        }
        delete file;
    }
    file = OpenFile("file:///proc/thread-self/stat", "rt");
    if (file != null)
    {
        if (file.ReadLine(line, sizeof(line)))
        {
            // comm may contain spaces/parentheses; fields start after its last ).
            position = FindCharInString(line, ')', true) + 1;
            bool minorOk, majorOk;
            if (position > 0)
                for (int field = 3; field <= 12; field++)
                {
                    if (!CheckLag_HostToken(line, position, token, sizeof(token))) break;
                    if (field == 10) minorOk = CheckLag_ParseCounter(token, sample.minor);
                    if (field == 12) majorOk = CheckLag_ParseCounter(token, sample.major);
                }
            if (minorOk && majorOk) sample.flags |= CHECKLAG_HOST_FAULTS;
        }
        delete file;
    }
    file = OpenFile("file:///proc/self/io", "rt");
    if (file != null)
    {
        bool readOk, writeOk;
        for (int row = 0; row < 16 && file.ReadLine(line, sizeof(line)); row++)
        {
            position = FindCharInString(line, ':') + 1;
            if (position <= 0 || !CheckLag_HostToken(line, position, token, sizeof(token))) continue;
            if (StrContains(line, "read_bytes:") == 0) readOk = CheckLag_ParseCounter(token, sample.readBytes);
            if (StrContains(line, "write_bytes:") == 0) writeOk = CheckLag_ParseCounter(token, sample.writeBytes);
        }
        if (readOk && writeOk) sample.flags |= CHECKLAG_HOST_IO;
        delete file;
    }
}

int CheckLag_HostPoll(float now, bool stalled)
{
    if (g_CheckLagMode < 2) return 0;
    if (now < g_LagHostNextAt && !stalled) return 0;
    if (g_LagHostClock == null) g_LagHostClock = new Profiler();
    g_LagHostClock.Start();
    CheckLagHostSample sample;
    CheckLag_HostRead(sample);
    sample.at = now;
    sample.cpuMs = -1.0; sample.waitMs = -1.0; sample.sliceDelta = -1.0;
    sample.minorDelta = -1.0; sample.majorDelta = -1.0;
    sample.readDelta = -1.0; sample.writeDelta = -1.0;
    if (g_LagHostReady)
    {
        int previous = (g_LagHostCursor + CHECKLAG_HOST_LIMIT - 1) % CHECKLAG_HOST_LIMIT;
        CheckLagHostSample old;
        old = g_LagHostSamples[previous];
        g_LagHostIntervalClock.Stop();
        sample.windowMs = g_LagHostIntervalClock.Time * 1000.0;
        int available = sample.flags & old.flags;
        if ((available & CHECKLAG_HOST_CPU) != 0)
        {
            sample.cpuMs = CheckLag_CounterDelta(sample.cpu, old.cpu, true);
            sample.sliceDelta = CheckLag_CounterDelta(sample.slices, old.slices);
        }
        if ((available & CHECKLAG_HOST_WAIT) != 0)
            sample.waitMs = CheckLag_CounterDelta(sample.wait, old.wait, true);
        if ((available & CHECKLAG_HOST_FAULTS) != 0)
        {
            sample.minorDelta = CheckLag_CounterDelta(sample.minor, old.minor);
            sample.majorDelta = CheckLag_CounterDelta(sample.major, old.major);
        }
        if ((available & CHECKLAG_HOST_IO) != 0)
        {
            sample.readDelta = CheckLag_CounterDelta(sample.readBytes, old.readBytes);
            sample.writeDelta = CheckLag_CounterDelta(sample.writeBytes, old.writeBytes);
        }
    }
    sample.sequence = ++g_LagHostSequence;
    g_LagHostClock.Stop();
    sample.probeMs = g_LagHostClock.Time * 1000.0;
    g_LagHostSamples[g_LagHostCursor] = sample;
    g_LagHostIntervalClock.Start();
    g_LagHostCursor = (g_LagHostCursor + 1) % CHECKLAG_HOST_LIMIT;
    g_LagHostReady = true; g_LagHostNextAt = now + CHECKLAG_HOST_INTERVAL;
    return sample.sequence;
}

void CheckLag_HostLog(int sequence, int alertTick, int frameTick)
{
    if (sequence <= 0) return;
    for (int row = 0; row < CHECKLAG_HOST_LIMIT; row++)
    {
        if (g_LagHostSamples[row].sequence != sequence) continue;
        CheckLagHostSample sample;
        sample = g_LagHostSamples[row];
        char message[512];
        FormatEx(message, sizeof(message),
            "v=3|alert_tick=%d|frame_tick=%d|host_seq=%d|flags=%d|window_ms=%.3f|thread_cpu_ms=%.3f|runnable_wait_ms=%.3f|thread_slices=%.0f|minor_faults=%.0f|major_faults=%.0f|process_read_bytes=%.0f|process_write_bytes=%.0f|probe_ms=%.3f",
            alertTick, frameTick, sequence, sample.flags, sample.windowMs, sample.cpuMs,
            sample.waitMs, sample.sliceDelta, sample.minorDelta, sample.majorDelta,
            sample.readDelta, sample.writeDelta, sample.probeMs);
        PluginStats_Record("lag_host_window", message);
        LogMessage("[CheckLag][Host] %s", message);
        return;
    }
}
