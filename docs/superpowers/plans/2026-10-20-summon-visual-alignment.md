# Summon Visual Alignment Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan. User already approved independent visual clock with unchanged gameplay timing.

**Goal:** Bind source-supported new summon bodies to live render paths without changing hits, motion or RNG.
**Architecture:** An opt-in sampled visual sprite referenced from the legacy gameplay spec; separate attack-start and actual-hit timestamps. Existing gameplay fields remain immutable. Unmatched custom poses remain explicit fallbacks.
**Tech Stack:** Godot GDScript, JSON data, Python/Pillow asset export.

- [x] Add failing pure visual sampler regression and integration timing assertions.
- [x] Implement sampling, tail/interrupt and field validation in the minimum shared summon draw path.
- [x] Export selected native strips, retain canonical foot/density, wire supported states for four bodies.
- [x] Review Mon3tr FX against new bodies; write exact runtime mapping and fallback matrix.
- [x] Run regressions, same-seed TRACE and full auto checks. Inspect screenshot/visual evidence; deliver selected files/commit only, no main merge.
