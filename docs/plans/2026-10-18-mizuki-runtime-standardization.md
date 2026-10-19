# Mizuki runtime standardization and animation repair

User approved all four steps plus removal of replaced old code (2026-10-18). Baseline abb6f217 includes the accepted three-operator modules. Branch codex/mizuki-standardization originates at main and fast-forwards that dependency; do not edit other worktrees.

## Design
Keep all skill damage/ranges/SP/duration/target rules and growth. Replace umbrella free immediate damage with existing start_attack -> fire event -> recovery. One completed body attack per gameplay umbrella release; S1 charge consumed on release, not startup. Tentacle followups and mirror echoes remain dependent effects, not extra body animations. S2/S3 activation, state and cleanup must use common lifecycle and animation sequences. Keep source counters authoritative. Reuse approved native-Spine pixel strips, no regenerated poses. Capture reference duration separately from runtime timing.

Fast attack readability: use the common timing contract and provide an explicit minimum complete action/recovery where needed (data-defined, not role-ID logic). Show requested versus effective interval in evidence; user approved timing correction even when full actions cap effective attack rate. Do not silently alter damage to compensate. Preserve a visible rest between attacks. Prototype target normal .9s cycle, .72s action; high-speed floor .36s action + .09s rest (.45s minimum cycle). Confirm against actual frames and captures before final delivery.

## Execution (subagent-driven-development)
- [x] Inspect dependencies/callers and approved asset manifests; map every runtime animation, anchor, fire and duration. Keep original sources and old trial worktree unchanged.
- [x] Add a failing regression for damage before fire, multiple releases per animation, charge on startup, S2/S3 duration/exit, pending attacks after leave, target loss, manual/auto, leader/ally and growth effects. Use godot_runner only, workspace TEMP/TMP, Python D:/Anaconda/python.exe.
- [x] Implement minimal common timing/capability adapters in data_operator/character/seg_mizuki/validation as necessary. Remove free-update/direct-release path once searches show no callers; preserve passive/stakes/jelly/mirror/delayed semantics and per-source effects. Update old Mizuki tests to assert the new intended contract, never simply drop cases.
- [x] Root copies verified native-Spine animation assets into unique runtime filenames, JSON mappings and source/hash manifest. Read-only audit subagent supplies dimensions and event references. No art creation needed; do not edit other characters or other agents' uncommitted files.
- [x] Spec review then independent quality review; fix blockers. Verify 1/2/4x normal and S2/S3 requested vs actual intervals, exactly one damage release per full animation, no cancel leak, same-seed reproducibility (intentional pre/post timing differences documented). Preserve three-operator regression.
- [x] Run python tools/check.py --auto --jobs 3 via numpy preimport if required. No SCRIPT ERROR/Parse Error. No local balance A/B batches. Capture actual game normal/S2/S3 and full animation overview, inspect before handoff.
- [ ] Document deleted entry points and retained shared methods, update docs61/index plus handoff. Selectively commit, export committed HEAD local diagnostic EA with tools/export_build.py, verify hashes and silent packaged startup. No main merge/push/public release.

## Migration constraints from plan review
S1 currently stacks up to stack_max; common instant helper overwrites and must gain the existing explicit stack semantics (default unchanged). S2/S3 must initialize numeric duration through normal release or an explicitly tested common path. Moving the free tick must preserve exactly one tick for sustain, kill-heal budget, stakes, jelly, mirror and delayed effects. No gameplay tick may depend on whether a sprite loaded. Minimum action/rest must cap cooldown as well as playback; add validation and regression for optional bounds, unchanged defaults for other operators. Full native sources use 192px @2x frames; retain the canvas and adjusted logical anchor rather than clipping them into prior128 crops.

## Final verification
2026-10-18 final auto check: 82 checks, 0 failed, 334 seconds; same-seed 4-minute runs identical. Initial gallery overflow fixed and covered by a new regression. Spec and independent quality review passed. Export/startup evidence is recorded after commit under build/release.
