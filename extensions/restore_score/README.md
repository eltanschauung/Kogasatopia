# Restore Score 1.2.0 + Restore Score Display 1.0.0

Repository layout: the package's `native-source/` directory is stored here as
`src/`; the SourcePawn plugin and include are under the repository's `tf/` tree.
Linux extension binaries are deployed separately and are not tracked in Git.

Fix for Kogasatopia's accelerated Strange cosmetic leveling when scoreboard
adjustments are applied to Spy players. Includes reconnect score restoration,
the existing backstab and teleporter deductions, and a required native extension.

## Install

1. Copy the included `tf/` files into the server's `tf/` directory. Keep one active
   `restorescore.smx`; remove/replace any other copy of the old plugin. The package
   includes Windows x86 and Linux x86/x64 extensions. SourceMod selects the matching
   binary; Linux x64 uses the `extensions/x64/` subdirectory.
2. If `teleporter_score.smx` is active, disable it when enabling this version.
   That separate plugin blocks TF2's teleporter points at their source, while this
   plugin already deducts those points from the scoreboard. Running both would
   subtract twice. Preserve unrelated plugins and configuration.
3. Restart the server or change maps for the initial replacement. This discards
   any altered scoring baseline left by the old plugin. Run
   `sm_restorescore_status` in the server console to inspect raw/displayed scores.

Requires SourceMod/Metamod 1.12 and the standard TF2 tools. No client download,
new gamedata/signature, or inventory changes are needed. The original F2 updater
registration was removed so it cannot overwrite this fork with the old version.

## Why it fixes the problem

TF2 computes cosmetic Points Scored progress from the difference between its
fresh score and the stored `CTFPlayerResource::m_iTotalScore`. The old plugin
lowered that stored value after every manager think; TF2 then treated the next
correction upward as new progress, repeatedly.

The extension changes only the outgoing score property through its send proxy.
The stored score and genuine Strange/MvM progression remain under TF2's control.
Reconnect credit and deductions are applied to the displayed score, including
Oblivion's private resources. Hidden/disconnected rows remain zero. Scores clear
on map/match reset; an empty server clears the reconnect cache, excluding TV.

64 isolated Windows server checks passed, including reproduction of the old
feedback loop, zero repeated deltas after the fix, genuine later score gains,
reconnect/slot reuse, map resets, plugin lifecycle, and SourceTV snapshot encoding.
Linux x86/x64 binaries were built; Linux runtime and real inventory counters
still need the final in-game acceptance check. The LAN tests used `-nosteam`
after a separate stock control reproduced an unrelated Windows Steam-library
map-change abort. Normal deployment does not require that launch option.

## Source and builds

The updated SourcePawn code and native include are in `tf/addons/sourcemod/scripting/`.
Compile `restorescore.sp` with SourceMod 1.12's `spcomp`, including the supplied
`scripting/include/` directory. Native source is in `src/`. To rebuild,
run `python3 build.py --targets x86,x86_64` there (Git, Python, C++ compiler and
32-bit development libraries are required). Windows x86 builds use an x86 MSVC
developer shell and `python build.py --targets x86`. Dependencies are pinned.

Based on F2's Restore Score and Kogasatopia's modifications; new extension/fix by
Codex. GPLv3 with the SourceMod linking exception; license texts are included.

Source examined: Kogasatopia commit `59dde35ed6f1ab77879854b6d8738fb8b9ec0790`.
Valve's scoring path is in `game/server/tf/tf_player_resource.cpp`,
`CTFPlayerResource::UpdateConnectedPlayer`.
