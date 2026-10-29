---
name: event-cg-pipeline
description: Create or revise reference-constrained pixel-painted game event illustrations, matching an approved illustration batch and delivering masters, display-size comparisons and an art handoff. Use for event CGs and scene cards, not character Spine sprites or animation strips.
---

# Event CG pipeline

Read the current brief and repository collaboration rules. The latest user-approved illustration specification overrides obsolete sprite or low-resolution draft rules. Use the available imagegen tool for raster creation and edits; export scripts are not a substitute for drawing.

## Separate references and freeze invariants
- Identify original scene reference (composition, subject, light, canonical colors), accepted style reference (pixel organization only), and edit target. Inspect each before generation.
- Record subject, position, recognizable objects, palette, text, crop-safe margins and overlay area. During style edits preserve these.
- Tell the generator explicitly that style-reference furniture, setting, palette and lighting layout must not migrate into the target scene.
- For canonical portraits, inspect the verified original portrait. Preserve identifying headwear, hair, mask/eyes, costume accents; do not infer from memory.
- Keep reference originals and their crops in ignored local review/build storage if the brief restricts them. Only newly drawn deliverables belong in incoming.

## Match actual pixel structure
A shared canvas or a prompt saying pixel art does not establish a style match. Choose accepted references appropriate to both environment and material; record which references govern which decisions.
Compare at identical display scale:
1. Silhouette stair steps and thin-line treatment.
2. Connected pixel-cluster size and shape.
3. Coherent light/shadow planes versus noisy or smeared texture.
4. Metal, cloth, stone, wood, water and glow handling.
5. Dark-value readability and focal hierarchy.

Repair failed materials specifically. Preserve shape and depth, remove photographic depth-of-field, smooth vector edges, airbrushed bloom or impasto when these conflict with the approved style. Depth can come from lower contrast and simpler distant clusters.
Do not enforce one arbitrary pixel-block size across all materials. Avoid oversized mosaic clusters, overbright outlines, loss of portrait identity, and flattened lighting during correction.
Do not solve mismatch using whole-image downsampling, palette quantization, sharpening or noise overlay. Routine export resizing is separate from style creation.

## Review before claims
- Inspect full master, actual display resolutions, and native-scale detail crops beside accepted references. Show same-scale crops without independent crop-fit enlargement that conceals density differences.
- Inspect original composition against the new frame and simulated text overlay/crop mask. Label simulated UI clearly; it is not an engine screenshot.
- Review the complete batch together, including unchanged assets. Check that style correction did not alter canonical colors, subject positions or text.
- Record per-asset findings and remaining limitations. Numeric QA cannot certify visual matching; never report complete alignment based only on dimensions or successful generation.
- Preserve rejected iterations in ignored build storage and deliver one current candidate per requested asset. Do not regenerate accepted unaffected assets without reason.

## Deliver and verify
Export the specified dimensions and color mode; validate decode, dimensions, filenames, count, hashes and review links after final copy. Save prompts, source provenance, manifest and handoff. Reference images must not leak into delivery.
Keep technical QA, visual self-review, user acceptance and runtime integration distinct. A filename such as approved_manifest.json does not authorize an approved status. Use pending_visual_review until actual approval.
Commit and integrate only under the live user/repository authorization. Never combine another task's changes.

## ArknightsSurvivors illustration contract
For the approved 2026-10-26 event batch, inspect art/incoming/event_cg_1026/generated_v2 and its manifest. These are style anchors, not generic scene content.
The 2026-10-29 brief specifies 1327x1185 RGB PNG masters, 1120x1000 desktop and 560x500 web previews. The old 140x125 / 64-color draft was rejected. Keep focal identifiers in the upper roughly60%, allow about3% edge crop, and simulate lower40% text darkening. Preserve each scene's original colors, including warm fire/daylight.
Use current brief values if changed. Assets go in the assigned art/incoming batch, QA in build. Engine integration and actual desktop/touch screenshots remain separate handoff steps.
