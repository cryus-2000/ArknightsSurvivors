# Monster art v2 — Claude handoff

Based on the user-approved monster_design_v2_preview.png. Produced with the built-in image generation tool, then color-keyed, resampled to the required logical frame dimensions, palette-reduced and given a 1px #080E18 contour.

| File | Frame size | Frames | PNG size |
|---|---|---|---|
| drifter.png | 14x16 | 2 | 28x16 |
| dart.png | 16x10 | 2 | 32x10 |
| crawler.png | 18x16 | 2 | 36x16 |
| shell.png | 22x20 | 2 | 44x20 |
| boss.png | 52x48 | 2 | 104x48 |

All files: RGBA PNG, transparent background, binary alpha (0/255), at most 16 opaque colors, horizontal left-to-right frames, right-facing. Use nearest-neighbor sampling. The pale carapace, navy tissue and cyan organs identify the approved designs at the small target resolution. Fine concept-art details are necessarily simplified.

Animations: drifter tendrils/contracting mantle; dart trailing fins; crawler alternating legs; shell legs/feeler; boss tentacles/maw. Both frames use the same scale and bottom alignment during export. In-game playback and visual pivot verification remain for integration; no runtime code or game/art/px files were modified.

monster_v2_actual_preview.png shows the actual output pixels enlarged with integer scaling. monster_v2_preview.html provides a two-frame looping visual check at 4 fps; this is a preview rate, not a required game rate.

Generation prompt summary: preserve only each approved monster from the design board, create two equal-cell right-facing poses, use hard-edged low-resolution pixel clusters, pale plates/navy tissues/cyan nodes, and a uniform magenta color-key background. The final PNGs have that background removed and are the production assets; the generated large source images are intermediate artwork.
