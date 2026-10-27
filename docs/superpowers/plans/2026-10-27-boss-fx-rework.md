# Final Boss pixel-material VFX rework

**Goal:** Replace rejected geometric final Boss effects with the current Noita-inspired coarse pixel forms, restrained stepped light and material particles. Deliver real combat previews for visual approval before any release replacement.
**Architecture:** Keep attack simulation and geometry unchanged. Separate sober danger boundaries from animated material bodies; reuse the shared Boss grain budget and visual RNG. Work from the delivered Boss build on `codex/boss-fx-rework`.
**Tech stack:** Godot batched pixel geometry, existing CPU material grains, silent offscreen Godot captures, PNG/MP4/GIF review artifacts.

- [x] Read current style contracts (132/136/138) and inspect old battle frames; preserve baseline.
- [x] Root: replace `render/boss_attack_draw.gd` presentation for all 12 new attacks. Warnings remain exact, low-fill and magenta-edged; visible moving bodies have distinct silhouettes and material motion. No particles masquerading as extra hitboxes.
- [x] Particle worker: `render/final_attack_grains.gd` plus visual hooks in `enemies/final_attacks.gd`; shared budget, no gameplay RNG, no extra emitter nodes, low-quality geometry fallback.
- [x] Preview worker: real combat capture scene and serial runner for four Bosses, three attacks each; native-frame screenshots and at least 12 fps animated review. Show player, terrain, hazards and safe passages.
- [x] Root: maintain exact area/annulus geometry regression, inspect warning/impact/afterglow with particles on/off; compare the same seed and run required checks after visual iteration.
- [x] Independent reviewer: examine actual images and motion for pixel density, silhouette, dangerous-vs-decorative colors, excessive white area, clear safe gaps and readability around the player.
- [x] Deliver candidate previews and documented limits. No main merge, no release replacement before the user accepts the visuals.

## Material direction

- Paranoia: dark pearl bubbles with broken violet rims and inward sparks; paired spectral emitters feeding sharp violet light, followed by dissolving fragments.
- Knight: irregular blue ice facets and ground cracks, a defined chipped blade and spear tip, short cold splinters. Avoid repeated diamond icons.
- Ishar: layered teal choir energy with narrow pearl-white cores and flowing fins; wet tentacles have tapered body, dorsal ridges and small suckers.
- Izumik: heavy cyan organic limbs, moving foamy crests and concentric water pulses. Keep the inner refuge of annular attacks empty and visibly bounded.

Only the narrow lethal edge/core reaches HDR brightness. Warning interiors remain transparent; purely decorative debris cools/darkens quickly and stays local. Keep original warning duration, damage timing, radius, line width, travel vector and cancellation.

Implementation and verification: docs/167_boss_pixel_fx_1027.md. Candidate only; user visual acceptance and release integration remain separate.
