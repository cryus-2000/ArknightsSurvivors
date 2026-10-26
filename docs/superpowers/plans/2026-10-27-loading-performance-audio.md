# Loading, performance and laser mix implementation plan

**Goal:** One continuous startup loading screen, less intrusive laser cues and measured rendering/memory improvements, preserving the complete Boss and music behavior.
**Architecture:** Keep the existing loader and boot stages but give web one visual owner until the title is ready. Fix bounded cache/render lifetime costs only after evidence. Reuse existing audio generators and cue mixer.
**Tech stack:** Godot GDScript, HTML/JavaScript loader, Python audio/probe tools.

- [x] Root: capture current title frame/memory baseline through silent non-focusing runner; inspect double loading sequence.
- [x] Root: regress web download→engine→Godot progress→ready lifecycle, missing status, error visibility, monotonic progress and one disposal. Keep DOM loader throughout web boot and forward actual Godot progress; desktop remove static loader image. Keep separate loading for starting a run.
- [x] Audio worker: trace beam consumers, measure spectra/RMS, replace harsh beam charge/hit with lower-frequency cues preserving warning timing and priority, bound overlapping voices; focused regression and reproducible generator.
- [x] Performance reviewer: identify current hotspots read-only. Root: implement only evidenced bounded optimizations, regress lifecycle/geometry, measure desktop frame/memory effects with clear limits.
- [x] Run focused tests, full required branch check and same-seed reproduction; read-only review changes.
- [x] Commit selected files, export/verify updated internal Windows and web artifacts as relevant. Do not merge main or publish externally. Document evidence and platform limits.
