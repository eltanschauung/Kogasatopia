// Debug branch only: game-thread wall timings without file I/O, allocation,
// locks, SourcePawn callbacks, identities, pointers or retained engine objects.
#pragma once
#include <array>
#include <chrono>
namespace loadout_debug {
enum Stage { Total, Engine, Policy, Resolver, Callback, Count };
using Clock = std::chrono::steady_clock;
struct Recorder {
    bool enabled = false;
    std::array<double, Count> total{}, peak{};
    void Add(Stage stage, Clock::time_point start) {
        const double ms = std::chrono::duration<double, std::milli>(Clock::now() - start).count();
        total[stage] += ms;
        if (ms > peak[stage]) peak[stage] = ms;
    }
    void Reset() { total.fill(0); peak.fill(0); }
};
struct Scope {
    Recorder &record;
    Stage stage;
    bool active;
    Clock::time_point start;
    Scope(Recorder &record, Stage stage): record(record), stage(stage), active(record.enabled) {
        if (active) start = Clock::now();
    }
    ~Scope() { if (active) record.Add(stage, start); }
};
}
