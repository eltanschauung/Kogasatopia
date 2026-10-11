#include "../src/debug_timing.h"
#include <cassert>
int main() {
    using namespace loadout_debug;
    Recorder record;
    { Scope timing(record, Total); }
    assert(record.total[Total] == 0);
    record.enabled = true;
    { Scope root(record, Total); { Scope child(record, Policy); } }
    assert(record.total[Total] >= record.total[Policy]);
    assert(record.peak[Total] >= 0);
    record.Reset();
    for (double value : record.total) assert(value == 0);
}
