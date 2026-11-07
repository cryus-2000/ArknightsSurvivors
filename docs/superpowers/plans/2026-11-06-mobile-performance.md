# Mobile performance implementation plan

> Execute with subagent-driven-development and independent review. User authorized implementation after the audit, then requested broader performance optimization.

**Goal:** Reduce retained memory and frame stalls while preserving medium-quality visuals and deterministic gameplay. Baseline: a6b030e8a. No merge or release.

**Architecture:** Repair ownership cycles first. Bound memory-pressure maintenance separately from quality fallback. Optimize measured rendering work without changing geometry, draw ordering or random streams. Keep deferred loading and cache changes conservative to avoid trading memory for repeated stalls.

**Tech stack:** Godot/GDScript, existing godot_runner and check.py, GCP one-off validation. Python: D:/Anaconda/envs/RP/python.exe.

## Chunk 1: Memory correctness
- [x] Reproduce world/bullet_fx/ground sink and pxplane/child RefCounted cycles with weak-reference lifetime assertions.
- [x] Repair ownership and add regressions covering resources released after owner destruction, including owners never entering the scene tree.
- [x] Prevent repeated font cache clearing under sustained pressure; preserve escalation and allow a later recovered episode to clean again.
- [x] Validate lifecycle and pressure edge cases, then review changes.

## Chunk 2: Rendering and allocation
- [x] Inspect remaining per-frame pxplane work and build a focused baseline/optimized measurement.
- [x] Cache invariant geometry or batch commands only where exact geometry/order can be verified; retain changes only with measured benefit.
- [x] Inspect loading/cache cleanup for a safe additional reduction, without removing music layers or lowering quality.

## Chunk 3: Verification and handoff
- [x] Run short local sanity checks only via tools/godot_runner.py, headless and muted; heavy checks and TRACE belong in cloud.
- [x] Run python tools/check.py --auto --jobs 3 and applicable same-seed checks using project cloud workflow; report any infrastructure blocker explicitly.
- [x] Record before/after evidence and limitations; independently review diff and register handoff document in docs/00_index.md.
- [x] Commit only selected task files on codex/mobile-performance-1106; provide commit and validation evidence, no main merge.

Frame target is 33.3 ms at 30 FPS. Desktop measurements do not certify mobile performance. Current memory monitor excludes part of browser/CPU memory; repeated-session lifetime validation is required in addition to a single run peak.

Final validation: 181 checks passed on the final snapshot; seven affected-operator smoke runs passed; 661/360 TRACE rows match baseline. Local single-color GPU pixels match in six cases. Cloud software-render full A/B was invalidated by the screenshot-path error; local full A/B was not launched because another session was exporting. No whole-frame speedup or iPhone15Pro 30 FPS certification is claimed. See docs/mobile_performance_1106.md.
