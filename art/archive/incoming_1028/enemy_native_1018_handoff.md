# Monster native-part animation test integration — 2026-10-18

Art source commit: codex/art 0a21f5a6. Full construction delivery: art/incoming/cj_enemy_native_actions_1018/runtime_manifest.json in that branch.

This branch copies 116 runtime strips (397 frames) into the authoritative root art/incoming names and adds game/data/enemy_pixels.json. Friendly knight uses e_knight_walk*; enemy/Boss knight retains mounted e_knight*. Original custom move meanings, attack timing, damage, AI and collision sizes remain unchanged.

Validation: 153 original-reference animations and 116 runtime strips passed saved-part recomposition, binary transparency, clipping and source hash checks. 76 full-check items passed, 0 failed. Seed 1 / Saria / 45s matched base 6b697796 in all 46 TRACE lines. Python delivery checker negative tests: 4 passed.

New render contract handles source canvas anchors, scale, preserved palette, death sprites and visible-pixel HUD height. Regression scenes: enemy_pixel_contract and knight_pixel_split. Real rendered captures use tools/probes/enemy_animation_capture.py; initial 5-second AI recordings are not all-move coverage.

Known visual limits: Carmen spin has no native rear-view attachments (compressed/mirrored side view); mounted knight is dark in the current scene lighting. Art remains subject to user visual review. No production release or main merge.

Existing lifecycle issue found during capture: telegraph._spawn_after creates the parent spawned_after list and child owner back-reference. In a rendered Path demo this retains about 88 MB of atlas textures at exit. The capture scene breaks these references only after recording; production cleanup is not changed by this art integration. Repeated demo/session teardown should be addressed separately before a production release.
