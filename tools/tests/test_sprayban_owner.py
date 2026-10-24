"""Offline regressions for live Spray Tracer and the pending merged controller.

Extract the actual two SourcePawn functions, convert only their legacy variable
declarations to C++, and execute them against fake clients/persistence/rendering.
This is not a SourcePawn VM test: compile both full plugins with spcomp as well.
No server connections, database access, installation, or reloads occur here.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = (
    ROOT / "archive/sourcemod_plugins/disabled/spraytrace.sp",
    ROOT / "tf/addons/sourcemod/scripting/enhanced_sprays/moderation.sp",
)


def function(source, name):
    start = re.search(r"^(?:stock|public)[^\n]*\b" + name + r"\([^\n]*\)\s*\{", source, re.M)
    if start is None:
        raise AssertionError(f"Missing function {name}")
    end = source.index("\n}", start.end()) + 2
    return source[start.start():end]


def translate(source):
    result = function(source, "ApplyGlobalSprayBan") + "\n" + function(source, "IsSprayerMutedForViewer")
    result = result.replace("stock ApplyGlobalSprayBan(admin, target)",
                            "void ApplyGlobalSprayBan(int admin, int target)")
    result = result.replace("stock bool:IsSprayerMutedForViewer(viewer, sprayer)",
                            "bool IsSprayerMutedForViewer(int viewer, int sprayer)")
    result = re.sub(r"new String:(\w+)\[(\w+)\];", r"char \1[\2] = {};", result)
    result = re.sub(r"new Float:(\w+)\[(\d+)\];", r"float \1[\2] = {};", result)
    result = re.sub(r"\bnew\s+", "int ", result)
    return result


HARNESS = r'''
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
constexpr int MaxClients = 4, SPRAY_HASH_LENGTH = 32;
constexpr int SPRAY_MUTE_DURATION = 7 * 24 * 60 * 60;
constexpr char SPRAY_MUTE_GLOBAL_VIEWER[] = "global";
bool g_bSprayMutesLoaded, authenticated, banned, hashMuted;
int g_hSprayMuteMap, mask, savedExpiry, savedCount, announcements, logs, warnings;
int activeReads, hashReads, checks;
std::vector<int> cleared;
void Check(bool ok) { ++checks; if (!ok) std::abort(); }
bool IsValidClient(int c) { return c >= 1 && c <= MaxClients && (mask & (1 << (c-1))); }
bool Moderation_ValidClient(int c) { return IsValidClient(c); }
bool GetSprayMuteSteamId64(int c, char *out, int size) {
    if (!authenticated) return false;
    std::snprintf(out, size, "test-client-%d", c); return true;
}
bool GetSprayHash(int, char *out, int size) {
    ++hashReads; std::snprintf(out, size, "test-hash"); return true;
}
bool IsSprayMuteActive(const char *, const char *) { ++activeReads; return banned; }
bool IsSprayHashMuteActive(const char *, const char *) { return hashMuted; }
int GetTime() { return 1000; }
void BuildSprayMuteKey(const char *, const char *, char *out, int size) {
    std::snprintf(out, size, "test-key");
}
void SetTrieValue(int, const char *, int expires) { banned = true; savedExpiry = expires; }
void PersistSprayMute(const char *, const char *, int expires) {
    ++savedCount; Check(expires == savedExpiry);
}
void SendPlayerDecalToClient(int, int viewer, int entity, const float position[3]) {
    Check(entity == 0 && position[0] == 0 && position[1] == 0 && position[2] == 0);
    cleared.push_back(viewer);
}
void PrintToChat(int, const char *) { ++warnings; }
void PrintToChatAll(const char *, int) { ++announcements; }
void LogAction(int, int, const char *, int, int) { ++logs; }
'''

CASES = r'''
int main() {
    for (mask = 0; mask < 16; ++mask) {
        for (int flags = 0; flags < 16; ++flags) {
            g_bSprayMutesLoaded = flags & 1; authenticated = flags & 2;
            banned = flags & 4; hashMuted = flags & 8;
            for (int owner = -1; owner <= 5; ++owner) {
                for (int viewer = -1; viewer <= 5; ++viewer) {
                    activeReads = hashReads = 0;
                    bool expected = g_bSprayMutesLoaded && authenticated
                        && IsValidClient(owner) && IsValidClient(viewer)
                        && owner != viewer && (banned || hashMuted);
                    Check(IsSprayerMutedForViewer(viewer, owner) == expected);
                    if (owner == viewer) Check(activeReads == 0 && hashReads == 0);
                }
            }
        }
        for (int target = 1; target <= MaxClients; ++target) {
            for (int auth = 0; auth < 2; ++auth) {
                authenticated = auth; cleared.clear(); banned = false;
                savedCount = announcements = logs = warnings = savedExpiry = 0;
                ApplyGlobalSprayBan(1, target);
                if (!auth) {
                    Check(!banned && cleared.empty() && savedCount == 0);
                    Check(announcements == 0 && logs == 0 && warnings == 1);
                } else {
                    std::vector<int> expected;
                    for (int viewer = 1; viewer <= MaxClients; ++viewer)
                        if (viewer != target && IsValidClient(viewer)) expected.push_back(viewer);
                    Check(cleared == expected);
                    Check(banned && savedCount == 1 && savedExpiry == 1000 + SPRAY_MUTE_DURATION);
                    Check(announcements == 1 && logs == 1 && warnings == 0);
                }
            }
        }
    }
    std::printf("%d visibility/clear/persistence checks passed\n", checks);
}
'''


class SprayBanOwnerTests(unittest.TestCase):
    def test_actual_policy_functions(self):
        compiler = shutil.which("c++")
        self.assertIsNotNone(compiler, "A C++ compiler is required for the offline policy fixture")
        with tempfile.TemporaryDirectory(prefix="sprayban-owner-") as directory:
            for index, path in enumerate(SOURCES):
                with self.subTest(source=str(path.relative_to(ROOT))):
                    fixture = Path(directory) / f"fixture-{index}.cpp"
                    binary = Path(directory) / f"fixture-{index}"
                    fixture.write_text(HARNESS + translate(path.read_text()) + CASES)
                    subprocess.run([compiler, "-std=c++17", "-O1", str(fixture), "-o", str(binary)], check=True)
                    subprocess.run([str(binary)], check=True)

    def test_render_paths_share_policy(self):
        for path in SOURCES:
            source = path.read_text()
            forward = "ESprays_CanSeeSpray" if path.name == "moderation.sp" else "ISprays_CanSeeSpray"
            self.assertIn("IsSprayerMutedForViewer(viewer, client)", function(source, forward))
            self.assertIn("IsSprayerMutedForViewer(viewer, client)", function(source, "FilterPlayerSpray"))
            self.assertIn("!IsSprayerMutedForViewer(viewer, target)", function(source, "RemoveGlobalSprayBan"))


if __name__ == "__main__":
    unittest.main()
