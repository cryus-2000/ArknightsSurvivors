# Three-operator standardization implementation plan

> For agentic workers: use subagent-driven-development; user approved the design and execution. Worktree codex-three-attack-timing; baseline e01ac517 (game = 43638231).

Goal: all three operators use common lifecycle/query/cancel contracts, retain existing combat behavior, support moving capabilities between skill slots.
Architecture: retain data_operator/character/blocks, attack_phases and existing effect implementations. Add the smallest capability-based lifecycle adapter for effect-owned states instead of duplicate timers or operator-ID dispatch. Apply to all nine skills and audit passive/progression paths.
Tech: GDScript, JSON, Python validation with tools/godot_runner.py.

## Chunk 1: baseline and implementation
- [x] Root saves cached TRACE for wisadel/saria/suzuran against e01ac517; independent event trace records skill effects and state before migration.
- [x] Implementer first adds failing tests in game/tests/skill_lifecycle_test.gd + tscn/uid: move cannon_load, calc_field, fox_cast haze to another slot, distinguish seconds/count/permanent, release/cancel/end once, refresh, passive/attack overlap. Use compiled independent test definitions, no hard-coded real operator ID in shared controller.
- [x] Implementer adds shared lifecycle helper under game/scripts/characters/blocks/ and integrates data_operator.gd methods skill_on/skill_active_left/skill_active_dur/skills_occupied/on_leave. Preserve existing dur/next_attacks/permanent, phase controller and shape execution; avoid second timer.
- [x] Implementer migrates ob_hw.h4_active_left, cannon occupancy, seg_saria hot/calc, seg_suzuran warm/haze and seg_wisadel ammo to contract-owned binding/query/end/cancel. Keep per-frame effect order and RNG use. Generic common dispatch identifies capability tags rather than character id or fixed slot. Source adapters may read their own existing state.
- [x] Implementer covers normal expiration and explicit cancel separately. Refresh is not end; callback executes once per actual activation. Preserve released projectiles, clear owned future queues/buffs appropriately, repeated cleanup safe.
- [x] Implementer validates new config if any in ob_check.gd, registers regression in tools/check.py, documents nine skills plus passive/progression audit in docs/61 and handoff. No mechanical rewrite of already-compliant abilities.
- [x] In skill_lifecycle_test.gd enumerate all nine skills at 1x/2x/4x attack speed, no target/dead target, manual/auto and leader/ally; test refresh, leave/redeploy, natural end/cancel and animation-effect state alignment. Use existing wisadel_s2_test.gd, attack_timing_test.gd and operator regression scenes for already-covered cases; report the mapping rather than claim unrun coverage. Expected: all assertions pass, no leaked buffs/queues, exactly-once completion. Root event harness game/tests/three_lifecycle_trace.gd compares pre/post activation timing and effect states.
- [x] Run targeted scene via godot_runner, then existing attack_phases, wisadel_s2, attack_timing, saria/suzuran regressions. Never direct Godot, no commits until root verifies.

## Chunk 2: review and acceptance
- [x] Spec review compares actual diff with approved design, all nine skills and independent cross-slot tests. Resolve issues.
- [x] Quality review checks lifecycle identity/end timing, no duplicate countdown, skill overlap, cancellation and assertions. Resolve issues.
- [x] Root compares before/after event traces and cached gameplay TRACE; explain any bug fixes separately. Run python tools/check.py --auto --jobs 3. Any SCRIPT ERROR/Parse Error fails. The full check includes all 18 operator smoke tests, required for shared-interface changes. No local balance A/B batches.
- [x] Record same-seed, targeted and full checks, update docs/00 index, design status and completion checklist. Explicit file selection only; unrelated untracked uid files untouched.
- [x] Commit on current codex branch; export local diagnostic EA via tools/export_build.py, verify committed source, sprite hashes and silent startup. Provide branch/hash/launcher; no main merge or public release.

## Final acceptance (2026-10-18)
- Spec and independent quality reviews approved; no remaining blockers.
- Full check: `python tools/check.py --auto --jobs 3`, 81 passed / 0 failed, 334 seconds. Logs: `build/check/quick_1018_172332`. Python environment preimports numpy before executing check.py.
- Core 2869 assertions; lifecycle 402; Wisadel 546; attack phases 66; attack timing 179. All 18 operator smoke tests and growth nodes passed. No SCRIPT ERROR / Parse Error.
- Nine skills x 1/2/4 attack speed: 27 deterministic traces, each 1440 ticks, identical to baseline e01ac517 production code (43638231). Cached ordinary-game TRACE: all 31 lines identical for each of three operators. Evidence: `build/three_lifecycle_equivalence`.
- Visual capture: `build/three_lifecycle_capture/review.html` covers Wisadel S2, Saria S3, Suzuran S3 and their exits. This is not an art redraw.
- Intentional fix: leaving before startup release now cancels pending actions and manual input. Regression first failed six assertions, then passed.
- Limits: native core comparison skipped (not built); 14 old golden comparisons skipped (stale). Existing art lint warnings/waivers and test exit resource warnings remain. Other 15 operators were smoke-tested but not individually migrated.
- Delivery: commit this source first, then export and verify local package. Package verification.json records its exact commit and startup/hash checks. No main merge or public release.

- Delivered source commit: `5d59e236`. Local package: `build/release/ThreeOperators_Standardized_5d59e236`; silent packaged startup passed, 16 Wisadel manifest hashes matched, exported skill_lifecycle module verified. `verification.json` records the exact source commit. Initial verifier launch hit sandbox temp permissions before startup; rerun with workspace TEMP/TMP passed.
