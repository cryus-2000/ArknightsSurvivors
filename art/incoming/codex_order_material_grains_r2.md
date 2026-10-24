# 给 Codex：材质颗粒第 2 轮（10-24，粒子化会话验收 codex/particle-materials @ 7289a73dc 后）

验收结论见 docs/137。代码已在 `claude/particles-8d10a8` 接手并修了能修的（Dictionary 假 g 报错、16×16 点阵、--matab 轮换、契约脚本排队、.gd.uid）。下面只剩**观感**两项，需要你出稿、用户看过再定。

**基线**：请从 `claude/particles-8d10a8` 当前提交开 `codex/material-grains-r2`，不要从 7289a73dc 开（否则会把已修的问题带回来）。

## 范围

只动这几处，别的文件不碰（粒子化会话同期在改 `render/fx_grains.gd` 的其他段，冲突时以本单范围为准、改动集中在下列常量 / 函数里）：

1. **拉普兰德剑气碎片后半段偏暗**（`fx_grains.gd` 的 `MATERIALS.blade.ramp` 与 `_lappland_step` 里的色乘子 `Color(0.75, 0.85, 0.9)`）。
   - 现象：交接后约 0.15 秒碎片就落到暗青色，和地面同色，只剩一片暗点（docs/137 §3 对照图 / `lappland.gif` 第 20–22 帧）。
   - 要求：整个寿命内碎片都读得出是「剑气碎开」，最后一阶仍比地面亮；不许整体加白发光（防油腻规矩：辉光预算不变）。
2. **用户要求「明显差异」**：剑气本体转碎片的那一刻要一眼能看出来（现在原版与材质版前 0.16 秒完全一样，碎开后又太暗）。可调交接时刻、碎片初速 / 散角 / 寿命；不改技能伤害、范围、周期、出手时刻，随机只用 `g.vrng`。

## 不做

- 歌蕾蒂娅、其他干员、封印叉、剑气弹体本身。
- 不新增节点 / 绘制路径 / 预算；不改 `budget()`（高 900 / 中 450 共用）。

## 验收标准（粒子化会话按此验）

- 同帧对照（左原版右材质）+ 1/3 速 gif：用 `--materialmovie --lapplandmovie`（`tests/material_movie.gd`），交 `build/` 下的 png 序列即可，不进 git。
- `python tools/material_grains_contract.py` 通过；`python tools/check.py --auto --jobs 3` 除金样过期外全过。
- 同 seed：`--bal=fx/material_grains=1` 开窗口局与关时 TRACE 逐行相同（粒子化会话跑）。
- 交付说明写清：改了哪几个数、为什么；用户是否已看过。
