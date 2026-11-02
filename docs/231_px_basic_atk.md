# 231 普攻 pixelfx 试点：拉普兰德 / 能天使（11-02）

用户 11-02 定：普攻也可以用 pixelfx 自写专属特效替换（不用库模板），按普攻预算。本文是试点结果，也是**其余 18 人普攻照做的步骤**（docs/229 §3：18 人普攻归 A–D 各组）。硬数字以 docs/229 §0 / §3 为准，本文只写做法和试点实测。

分支 `claude/elastic-brattain-98b1d9`（基于 integ-1101 c73d2ff86，已合 `claude/fx-lead-prep` 724b05688）。

## 0 结论

| 项 | 拉普兰德（近战） | 能天使（远程） |
|---|---|---|
| 换了什么 | 普攻「双刃」刀光 fx_lappland_slash → **fx_lappland_px_slash**（含精一 twin 第二刀） | 枪口 fx_exusiai_muzzle → **fx_exusiai_px_atk_muzzle**；命中 fx_exusiai_hit → **fx_exusiai_px_atk_hit**；弹体 proj_exusiai_bullet → **proj_exusiai_px_bullet**；精一层数弹体 t1–t3 → **proj_exusiai_px_bullet_t1–t3** |
| 帧条 | 84×184 × 4 帧 @24（0.17 s），@2x | 枪口 32×32 × 3 @24（0.125 s）；命中 22×18 × 4 @24（0.17 s）；弹体 32×12 × 2 @20 循环（×4 色） |
| 包体（32 色调色板 PNG） | 2.4 KB（旧 3.3 KB 仍被回敬 / 终结技引用，不删） | 0.4 + 0.4 + 0.3 × 4 = 2.0 KB（旧条仍是回退件） |
| 帧时（--mobilecap 网页，后期同局轮换） | 见 §4 | 见 §4 |
| 判定 / 玩法 | 不动；同种子 TRACE 见 §3 | 同左 |
| 对照录像 | `Claude outputs/fx_basic_atk/basic_atk_ab.mp4`（左旧右新） | 同一文件后半段 |

回退：`--bal=fx/px_basic=0`（balance 写 `fx/px_basic: 0` 同效）整体回旧帧条，不用改数据。

## 1 旧普攻盘点（改前实测）

| 干员 | 件 | 帧条 | 帧数 / fps / 时长 | 包体 | 游戏里每 1x 像素的世界像素 |
|---|---|---|---|---|---|
| 拉普兰德 | 刀光 fx_lappland_slash@2x | 128×128 × 4 | 4 @10 = **0.4 s** | 3.3 KB（RGBA） | 2.0（scale 1，along 0.5）；弧只占帧的 ~30×50，远小于判定半径 100 |
| 拉普兰德 | 兜底刀光 fx_slash_heavy_deep（贴图缺失才画） | 28×34 × 5，1x | — | — | 6.2（docs/229 §1 反例） |
| 能天使 | 枪口 fx_exusiai_muzzle@2x | 32×32 × 3 | 3 @30 = 0.1 s | 0.4 KB | 1.6（PX × 0.8） |
| 能天使 | 命中 fx_exusiai_hit@2x | 24×24 × 3 | 3 @24 = 0.125 s | 0.3 KB | 1.6；第 2 帧是规整红圈、第 3 帧棋盘格淡出 |
| 能天使 | 弹体 proj_exusiai_bullet@2x（及 t1–t3 24×12） | 32×12 × 2 | 2 @20 循环 | 0.2 KB | 1.6；实心红条，射速高时首尾相接连成光束（docs/228 §7.3） |

## 2 照做步骤（每人普攻）

1. **看旧件。** `grep` 干员 JSON 的 `attack` 段（cone 的 `fx[].strip`、projectile 的 `tex / muzzle_fx / hit_fx`）和 `seg_<id>.gd` 里写死的缺省名，记下帧条尺寸、帧数、fps、在游戏里的 scale / fit / along（§1 那张表的样子）。
2. **写源码。** `tools/pixelfx_fx/<类>/ak-<干员>-<件>.js`，模板直接抄：
   - 近战刀光：`melee/ak-lappland-slash.js`（圆心在原点左 `cx`，弧半径 = 判定半径 × `REACH.sweep`，张角 = 判定半角 × 2；主刃 + 细第二刃；首帧爆亮，外缘噪声崩口；碎光很少）。
   - 枪口：`projectiles/ak-exusiai-muzzle.js`（保留原画布 keep，原点 = 枪口）。
   - 命中：`impacts/ak-exusiai-hit.js`（**游戏里命中不旋转**，只做不对称，不画方向）。
   - 弹体：`projectiles/ak-exusiai-bullet.js`（纯函数循环 2 帧，画布与旧弹体相同，弹尾断成长短不一的几截）。
   - 色阶 `import { OP, FPS, REACH } from "../house.js"`，`palette: OP.<干员>`（近战可在前面补一阶 `#06142a`）；`fps: FPS.basic`（24）。
   - **不要烤光晕**（`p.glow`）：低 alpha 像素量化成 32 色后在游戏里是一圈暗环（本试点第一版的教训）；光交给 optical 层。
   - `duration` 让最后一帧为空：命中 ≤ 0.2 s、枪口 ≤ 0.15 s（导出时末尾空帧会被去掉，帧数按非空帧算）。
3. **在库里看效果。** `build/pixelfx` 下 `node tools/check.mjs <类>/<名>`（越界、末帧非空要清掉）、`node tools/render.mjs <类>/<名>` 看接触表，至少改三轮。
4. **登记导出目标。** 本组 `tools/pixelfx_fx/targets_<组>.json` 加 `"<游戏贴图名>": {"fx": "<类>/<名>", "hires": true, "keep": <枪口 / 弹体 true>}`；同一源码换色用 `"opts": {"palette": [...]}`（例：能天使 t1–t3）。贴图名一律 `fx_<干员>_px_*` / `proj_<干员>_px_*`（fx_coverage 自动算已做），**不要以 fx_slash / fx_claw 开头**。
5. **导出。** `python tools/pixelfx_export.py --lib E:/ArknightsSurvivors/build/pixelfx --only <名,…>`。**必须用 fx-lead-prep 724b05688 及以后的 export.py**（反预乘；旧版半透明处在 Godot 里发灰）。打印的 KB 要 ≤ 3（单条）、每人普攻合计 ≤ 6。
6. **登记接入。**
   - `art.gd` V6_FRAMES 本组块里加 `"<名>": [帧数, fps]`。
   - `godot --headless --path game --import`，新 `.import` 的 `process/fix_alpha_border` 改 false。
   - `python tools/asset_index.py`（本地跑，**不提交 game/art/index.json**，合并人统一生成）。
   - 干员 JSON 换名；`if_tex` 也一起换。seg_*.gd 里写死的缺省名一并换（否则 fx_coverage 仍报未做）。弹体若有锚点表（如 `EXU_TEX_ANCHOR`），新名加一条。
7. **可回退 + 可轮换。** `art.gd` 的 `PX_BASIC_OLD` 加 `"新名": "旧名"`。三处挂点已接好，新干员不用再改代码：
   - `ob_fx.fx_spawn`（JSON fx 段的 strip，近战刀光走这里）；
   - `op_api.spawn_fx_sprite`（枪口 / 命中这类 fx_sprite）；
   - 弹体：能天使在 `seg_exusiai` 生成子弹时过 `EXU_ART.px_basic(o.g, btex)`；别的远程干员的弹体字段若不走上两处，同样在生成时包一层 `Art.px_basic(g, 名)`。
   `Art.px_basic(g, name)`：名字在表里且（`fx/px_basic` = 0 或 `g.opt_old & Game.OPT_PXB`）时返回旧名，否则原样；不在表里的零开销。
8. **验证。**
   - 同种子 TRACE：`python tools/trace_base.py 1 <干员> 240 --here`（有精一件的加 `--extra "--prog=8"`），退出码 0 = 逐行相同。
   - 对照录像：同种子原速 30 帧，旧版加 `--bal=fx/px_basic=0`，左旧右新 hstack；过 vreview。
   - 帧时：见 §4 的命令，P50 / P95 差 ≤ 0.3 ms。
   - `python tools/fx_coverage.py --op <干员>` 普攻行应为已做；只剩回退用途的旧名在本组 coverage_<组>.json 登记 `已做` + 理由。

## 3 判定与同种子 TRACE

（待填）

## 4 帧时（--mobilecap 网页仿真，同局轮换）

（待填）

## 5 对照与预审

（待填）

## 6 遗留

- 拉普兰德「回敬」（rage2 节点）的反斩仍用旧 fx_lappland_slash + 兜底 fx_slash_heavy_deep，属成长形态，归 A 组技能批；终结技 ult_moves_c 里的 fx_lappland_slash 归终结技。
- 能天使连携 link_fx_a 仍用旧 fx_exusiai_muzzle（连携段，归 D 组）。
- 旧条暂不删：都是 `--bal=fx/px_basic=0` 的回退件，用户定稿后由合并人清点。
