# Codex 素材单：乌尔比安「撼地」冲击环

> 数值会话 10-22 写单（分支 `claude/ulpianus-buff`）。用户要求：乌尔比安原作是近卫·撼地者（攻击周围所有敌人），本作每次锚击砸地时追加一圈以他为中心向外扩的「撼地」冲击环。
> 规格一律按 docs/93 §0（特效 / 地面件通用规格：横排帧条、1x + @2x、alpha 只有 0 / 255、地面件俯视压扁 y ≈ 0.55、原点写进 manifest、≤ 16 色、只动 `art/incoming/`）。本单只写范围。
> 现在是**程序占位**（`ulp_wave` 地裂环 + `crack` 裂纹粒子），游戏照常能玩；素材到了由 Claude 接线替换。

## 要画的（2 条，共用一套帧）

| 文件 | 尺寸（1x 单帧） | 帧 | 层 | 内容 |
|---|---|---|---|---|
| `fx_ulpianus_quake_ring` | 200×112 | 7 帧 16fps，不循环 | ground | 锚砸地瞬间，以落锚处（= 乌尔比安脚下）为心向外扩的一圈地裂冲击环：第 1–2 帧中心爆开一圈碎石与水花，3–6 帧环向外推、身后留辐射状裂纹，第 7 帧环最大并散成尘土。**末帧外圈半径约 95**（程序按半径把整条缩放到 150 / 精二 180 世界像素，最多放大 2 倍）。主色沿用 `fx_ulpianus_anchor_impact_*`、`fx_ulpianus_drag_dust` 的深海蓝灰 + 少量白色水沫 |
| `fx_ulpianus_quake_ring_e2` | 同上 | 同上，逐帧对应 | ground | 精二版：同一套帧，裂纹里透出血脉红（参考精二红纹 `[1.0, 0.45, 0.5]`），环更厚 |

- 原点 = 帧中心 (100, 56)，俯视压扁 y ≈ 0.55；二值透明，淡出靠抖动疏密。
- 不画人物、不画锚本体（锚击已有 `fx_ulpianus_anchor_impact_back / _front`）。
- 交付：`ulpianus_quake_manifest.json`（文件名、帧数、fps、帧尺寸、1x / @2x 原点、层、色数）+ 深色地面底的预览 GIF（环按 150 半径合成在乌尔比安脚下）。

## 接线说明（Claude 侧，Codex 不用管）

`game/data/characters/ulpianus.json` 的 `blocks.trait` 两条「撼地」（`elite < 2` / `elite >= 2`），把 `fx` 里的 `ulp_wave` + `crack` 换成 `sprite` 帧条，按 `r_scale` 缩放到 `quake_r` / `quake_r_e2`。
