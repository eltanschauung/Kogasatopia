# Engineer building restrictions

`building_restrictions_probe.sp` compiles the real
`weapons/building_restrictions.sp` against simulated clients and engine calls.
It never changes a real player's inventory, loadout, cookies, or buildings.
Its TF2Items forward is renamed so loading the probe cannot intercept live
item creation. The build script also checks the production integration points.

```sh
bash tools/tests/weapons/build_building_restrictions_probe.sh
```

On a test server, load the generated plugin from `plugins/disabled`, run
`sm_buildings_probe` from the console, then unload it. Expected result:
`[BuildingsProbe] 34 checks; 0 failures`.

Covered cases include planned and holstered restrictions, stock/tool spawn
suppression, preserving saved custom PDAs, one deferred cleanup after nested
inventory operations, coalesced notifications, failed-equip recovery,
access/game-mode checks, other classes/Spy sappers, optional Amplifier native
fallback, disconnects, map resets, and reentrant session replacement.

The production policy predicts the incoming custom loadout before inventory
generation. TF2Items rejects prohibited stock tools before creation, while
custom equip/repair and econ-view overrides skip incompatible tools without
changing saved selections. Item-ready hooks only schedule reconciliation;
they never synchronously detach tools. A serial- and request-owned deferred
pass cleans up existing tools and calls the existing owned-building helper
once on activation or settled inventory application.

For a live performance check, compare CheckLag's `EngineerBuildings/prepare`,
`reconcile`, `detach_tool`, and `remove_tool` scopes with
`ManageRegularWeapons/engineer(engine+hooks)`. Repeated regenerations with
Super Gunslinger and a saved custom PDA should report blocked/skipped tools,
not repeated synchronous stripping inside item equip.
