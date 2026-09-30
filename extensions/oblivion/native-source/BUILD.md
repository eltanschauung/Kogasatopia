# Native dependency source

`oblivion-net/` contains the server-only Oblivion Network extension. It hooks
the SDK's `IServerGameEnts::CheckTransmit` interface after the game has finished
its transmission decisions; it requires no binary signatures or client changes.
The normal build excludes its isolated-server regression-test entry point.
Version 0.2.0 also hooks SteamGameServer015's packet interface and sends browser
replies through the existing game UDP socket. Windows discovers that socket by
querying handles of its own process; Linux uses `/proc/self/fd`. It never closes
the borrowed socket. Challenge generation uses the bundled CC0 SipHash reference
(its exact upstream revision and license texts are in `oblivion-net/third_party/`).

This is the CollisionHook project at commit
`b4e8c2487ba311d5b218f21a9774c83cd0fd15c8` from
https://github.com/Adrianilloo/Collisionhook. The extension code is unchanged;
the included binaries were rebuilt against Metamod 1.12's API. The separate
TF2 gamedata has an updated Windows x86 collision-filter signature.

On Linux with Python 3, Git, GCC/G++ and the appropriate 32/64-bit development
libraries, run `python3 build.py`. It fetches the exact public dependency
revisions used for these builds and produces `build/package/addons/` for
CollisionHook and `oblivion-net/build/package/addons/` for Oblivion Network.
Use `--targets x86_64` if only the 64-bit compiler/libraries are installed.
SourcePawn sources can be rebuilt with the server's `spcomp` and include files.

Dependency source locations and pinned revisions are in `build.py`. SourceMod
also pins AMTL, SourcePawn and SafetyHook through its submodules; SafetyHook
contains its Zydis dependency. Their original notices and licenses accompany
their source checkouts. SourceMod/CollisionHook use the GPL with the SourceMod
Valve-engine linking exception. The license texts are in `../licenses/`.
