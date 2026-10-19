# Native Spine pose editor

User approved the local editor design on 2026-10-20. Pilot: Siege Run, eight existing poses, 0.6 s cycle. Source geometry, textures and existing art remain read-only. No game changes.

Implementation: `tools/spine_editor/` contains the browser UI, shared pose math, a loopback Python server and focused tests. Load native 3.5 runtime locally, evaluate each original animation/deform, restore the authored bone matrices, then apply saved edits. Re-pixelize each attachment on the common grid. Save a versioned pose patch with a source fingerprint; export transparent frame strips and a review GIF to a separate output folder. This is not a .spine authoring project or a game-ready rig.

- [x] Test rigid hierarchy transforms, two-bone IK, weapon grip and patch validation before implementing.
- [x] Implement exact-source loading, interactive joint controls, draw order, undo/redo, import/save.
- [x] Implement pixel preview and PNG/GIF export without modifying original assets.
- [x] Check reload/export, invalid requests, visual preview and project check routing.

Validation: Node assertions for math and model; Python unittest for safe request validation/export and source isolation; browser interaction where available. Keep static, browser and engine verification separate. No gameplay timing/RNG/TRACE changes are intended.

Result: Node math/validation assertions and three Python tests pass. Real IAB verified drag, micro-adjust, undo, draw order, save/reload, frame playback and export. tools/check.py --auto --jobs 3: 73 checks, 0 failed (97/97 Godot cache hits); native extension unavailable and old golden fixtures skipped by the existing check suite. No game code changed.
