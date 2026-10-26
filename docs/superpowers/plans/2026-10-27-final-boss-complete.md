# Final Boss completion implementation plan

> For agentic workers: use subagent-driven-development. User authorized autonomous product decisions and complete implementation, including effects; do not request design approval. No Brainstorming.

**Goal:** Deliver four final bosses with at least seven distinct active attacks each, meaningful encounter mechanics, readable effects, and all reported combat/audio fixes.

**Architecture:** Extend the existing boss scripts, telegraph damage pipeline and rendering. Keep seeded gameplay separate from rendering, one authoritative hit geometry, and explicit tracking then lock periods. Reuse the current worktree on codex/final-boss-complete from main 151d572a4. Preserve unrelated main Exusiai import changes.

**Tech Stack:** Godot GDScript, JSON data, Python regression/build tools, WAV audio.

## Chunk 1: Boss combat (implementation agent)
- [x] Inspect live boss scripts and reference docs 49/49c, testing and render contracts.
- [x] Add regressions for >=7 active moves per final boss, natural scheduling/force_move coverage, no starvation, targeting and authoritative effects.
- [x] Paranoia: sequential moving-target stack fix; revive 80%; add three distinct attacks appropriate to bubbles/illusions/corrosion (pursuit bubbles, phantom assault, inward bubble pressure or equivalent). Preserve counterplay.
- [x] Knight: add three distinct moves (branching ice fissures, traveling crescent slash, lateral reposition then spear strike); disperse five pillars across arena sectors with spacing and reachable charge lanes; no replacement until current batch exhausted, including throw/phase entry/expiry paths. Improve frost laser effect.
- [x] Ishar: add three distinct attacks beyond existing four (choir aimed fire, moving choir pressure, ocean/tentacle attack). Human healing promotes at most three sea enemies to genuine elite stats, no recursive multipliers; red outline. Three permanently purifiable tears each control one empowerment slot, remove linked promotion immediately, unhandled tears affect transformed fight; bounded transformation and meaningful counterplay. Avoid new double rewards.
- [x] Izumik: add three distinct attacks beyond existing four (protective tentacle, migrating tide with gap, delayed undersea eruption or equivalent). All offspring spawn at reachable arena edge and slow movement (45 initial), no near-body spawns. Keep wave/lamp counterplay.
- [x] Audit targeted attacks of all bosses: follow intended target during windup then freeze with >=0.4s escape window; positional/arena attacks retain shape. Fix off-origin/multi-target tracking correctly.
- [x] Provide integrated matching VFX, telegraphs, move catalog and headless tests; no placeholder art or repeated renamed attacks. Agent owns boss scripts, boss patterns, telegraph, boss-only rendering/new renderer and focused boss tests. Root owns ishar_encounter and shared supporting changes. Coordinate shared world rendering edits with root.

## Chunk 2: Supporting fixes (root)
- [x] Lappland S3: preserve original colors of leader/allies/friendly summons during global desaturation, without changing damage or timing.
- [x] Final boss entrance: stop ordinary spawn, preserve already living mobs; retain boss mechanism summons. Remove both clearing entrances, update regression.
- [x] Exusiai: inspect all gunshot consumers and existing dirty imports; reduce piercing transient/overlap and mix masking, preserve BGM gain and gameplay. Keep chosen originals and adjust consistently. Verify waveform, sample format, loudness/polyphony and tests.
- [x] Add concise accurate player-facing text and update documentation index with delivered encounter inventory.

## Chunk 3: Verification and delivery
- [x] Run baseline core checks before gameplay modifications; focused failing regressions before fixes where practical.
- [x] Run python tools/check.py --auto --jobs 3, focused boss/mechanic/audio tests and same-seed reproducibility. Gameplay differs intentionally; no requirement that changed encounters match old outcomes. No local balance A/B batches.
- [x] Review every new move's natural reachability, cancellation, damage, performance bounds, and preview integration; render proof sheets through godot_runner only, silent non-focusing windows only if needed.
- [x] Separate spec compliance and code quality review, address all material findings.
- [ ] Commit selected files only, preserve generated/unrelated files. Deliver tested commit and runnable internal build; integration subject to current Git collaboration rules. Do not publish externally.

## Acceptance
All listed user issues addressed; final active attacks >=7 each, usable in actual encounters and previews; foes create pressure through readable combinations rather than unavoidable hits. Same seed reproducible, low quality changes drawing only. Automated launches silent/headless except required offscreen captures. Record actual checks and any platform limitations without claiming untested playability.

Plan review accepted with clarifications: audit every Boss entrance, including paired and mid bosses, for mob preservation and ordinary spawn policy. Naturally exercise all seven moves across phases and verify late fight pressure with no inherited mobs (not only force_move). Tear promotion ownership must handle purification, host death, transformation and boss death; remove only its own modifiers, preserve HP ratio and never duplicate rewards. User autonomous authority resolves routine choices without approval gates.
