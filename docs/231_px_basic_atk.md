# 231 普攻 pixelfx 试点：拉普兰德 / 能天使（11-02）

用户 11-02 定：普攻也可以用 pixelfx 自写专属特效替换（不用库模板），按普攻预算；同日又定「光晕 + 余韵」口径（docs/238）和「整套替换」（docs/237）。本文是试点结果，也是**其余 18 人普攻照做的步骤**（docs/229 §9：18 人普攻归 A–D 各组）。硬数字以 docs/229 §0 / §2.5 / §3 为准，本文只写做法和试点实测。

分支 `claude/elastic-brattain-98b1d9`（基于 integ-1101 c73d2ff86，已合 `claude/fx-lead-prep` 88c92cb8a）。

## 0 结论

| 项 | 拉普兰德（近战） | 能天使（远程） |
|---|---|---|
| 换了什么 | 普攻「双刃」刀光 fx_lappland_slash → **fx_lappland_px_slash**（含 twin 第二刀） | 枪口 → **fx_exusiai_px_atk_muzzle**；命中 → **fx_exusiai_px_atk_hit**；弹体 → **proj_exusiai_px_bullet**；精一层数弹体 t1–t3 → **proj_exusiai_px_bullet_t1–t3** |
| 帧条（@2x，全部另有 `_glow` 条） | 90×180 × 7 帧 @24：主体 4 帧（0.17 s）+ 余韵 3 帧；2 个变体 | 枪口 32×32 × 4 @24（主体 3 + 枪烟 1）；命中 24×18 × 7 @24（主体 4 + 余烬 3）；各 2 个变体。弹体 32×12 × 2 @20 循环 × 4 色（不出变体） |
| 包体（32 色调色板 PNG，本体 + glow，含变体） | (2.5 + 0.5) × 2 = **6.0 KB**（上限单条 4 / 每人 8） | 枪口 0.6 × 2、命中 0.6 × 2、弹体 0.5 × 4 = **4.4 KB** |
| 近白像素（白只在核心，上限 12%） | 旧 32.8% → **3.7%** | 枪口 32.5 → 3.9%；命中 21.2 → 0.9%；弹体 20.0 → 6.8% |
| 帧时（--mobilecap 网页，后期同局轮换） | 见 §4 | 同一局 |
| 判定 / 玩法 | 不动；同种子 TRACE 见 §3 | 同左 |
| 对照录像 | `Claude outputs/fx_basic_atk/basic_atk_ab.mp4`（左旧右新，同种子原速 30 帧） | 同一文件后半段 |

回退：`--bal=fx/px_basic=0`（balance 写 `fx/px_basic: 0` 同效）整体回旧帧条，不用改数据。

## 1 旧普攻盘点（改前实测）

| 干员 | 件 | 帧条 | 帧数 / fps / 时长 | 包体 | 观感问题 |
|---|---|---|---|---|---|
| 拉普兰德 | 刀光 fx_lappland_slash@2x | 128×128 × 4 | 4 @10 = **0.4 s**（超普攻 0.2 s 档） | 3.3 KB（RGBA） | 弧只占帧的 ~30×50，远小于判定半径 100；近白 33%；末帧几点碎块 |
| 拉普兰德 | 兜底 fx_slash_heavy_deep（贴图缺失才画） | 28×34 × 5，1x | — | — | 放大 6.2 倍（docs/229 §1 反例），现在不会画到 |
| 能天使 | 枪口 fx_exusiai_muzzle@2x | 32×32 × 3 | 3 @30 = 0.1 s | 0.4 KB | 首帧整块白（近白 33%） |
| 能天使 | 命中 fx_exusiai_hit@2x | 24×24 × 3 | 3 @24 = 0.125 s | 0.3 KB | 第 2 帧规整红圈、第 3 帧棋盘格淡出（都是被否的做法） |
| 能天使 | 弹体 proj_exusiai_bullet@2x（t1–t3 24×12） | 32×12 × 2 | 2 @20 循环 | 0.2 KB | 实心红条，射速高时首尾相接连成光束（docs/228 §7.3） |

## 2 照做步骤（每人普攻）

1. **看旧件。** 干员 JSON 的 `attack` 段（cone 的 `fx[].strip` / `if_tex`、projectile 的 `tex / muzzle_fx / hit_fx`）、成长段里的普攻变体（如能天使精一 `tex` 列表），以及 `seg_<id>.gd` 里写死的缺省名。记下帧条尺寸、帧数、fps、游戏里的 scale / fit / along，填 §1 那样的表。
2. **写源码。** `tools/pixelfx_fx/<类>/ak-<干员>-<件>.js`，模板直接抄：
   - 近战刀光：`melee/ak-lappland-slash.js`。圆心在原点左 `cx`（along 0.5 × 判定半径），弧半径 = 判定半径 × `REACH.sweep`，张角 = 判定半角 × 2；主刃 + 细第二刃；外缘噪声崩口；余韵是主刃走过处的断续残痕（第二刃不留，免得成两道同心圈）。
   - 枪口：`projectiles/ak-exusiai-muzzle.js`（keep 原画布，原点 = 枪口；余韵是一缕枪烟）。
   - 命中：`impacts/ak-exusiai-hit.js`（**游戏里命中不旋转**，只做不对称、不画方向；余韵是带重力下落的余烬）。
   - 弹体：`projectiles/ak-exusiai-bullet.js`（纯函数循环 2 帧，画布与旧弹体相同，弹尾断成长短不一的几截）。
   - `import { OP, FPS, REACH, DUR, TAIL_ALPHA } from "../house.js"`；`palette: OP.<干员>`（不要再往前补深海黑）；`fps: FPS.basic`；`duration` = 主体 + `DUR.basicTail`。
3. **颜色与透明（返工最多的地方）。**
   - 主体用设定色那一阶往下走（7 阶里的第 3 阶及以下）；**最亮两阶只给核心**：刀口最外一线、只在头两帧；枪口 / 弹头最前一两格；命中芯 1 像素。火星也别用最亮两阶。验收：近白（RGB 最小值 ≥ 230）≤ 12%。
   - **不要用 `p.dot(…, a)` / `shade` 的 `out.a` / `arc(…, a)` 做半透明**：pixelfx 的 painter 在 a < 1 时是 4×4 Bayer 抖动，导出来是棋盘格（docs/229 §2.4 禁用）。半透明一律 `p.blend` / `p.disc`；刀尾、断弧靠变细、变短收掉。
   - 余韵 alpha ≤ `TAIL_ALPHA`（0.4）、像素稀疏、方向 / 间距不等（±30% 以上）。
   - 光晕照常写 `p.glow(…, k ≤ 0.3)`：它进 light 层，导出成 `_glow` 条在游戏加色层叠画，不再被量化成暗环（第一版烤进颜色时就是暗环）。
4. **在库里看效果。** `build/pixelfx` 下 `node tools/check.mjs <类>/<名>`（越界、末帧非空要清掉）、`node tools/render.mjs <类>/<名>` 看接触表，至少改三轮。
5. **登记导出目标。** 本组 `tools/pixelfx_fx/targets_<组>.json` 加 `"<游戏贴图名>": {"fx": "<类>/<名>", "hires": true, "keep": <枪口 / 弹体 true>, "variants": 2}`（普攻 2 个变体，docs/229 §2.11；**弹体这类循环件写 1**：它走 spr_rot，不挑变体；可选 `"spark": [颗 ≤ 4, 色阶下标, 速度]`，本试点没加，帧条里已有火星）；同一源码换色用 `"opts": {"palette": [...]}`（例：能天使 t1–t3，见 `targets_basic.json`）。贴图名一律 `fx_<干员>_px_*` / `proj_<干员>_px_*`（fx_coverage 自动算已做），**不要以 fx_slash / fx_claw 开头**（会被 blade_scale 再缩一遍）。
6. **导出。** `python tools/pixelfx_export.py --lib E:/ArknightsSurvivors/build/pixelfx --only <名,…>`。**必须用 fx-lead-prep 88c92cb8a 及以后的 export.py**（分层出 `<名>` + `<名>_glow`，并出 `_v1` 变体）。打印的每行都要登记；本体 + glow ≤ 4 KB / 条、**含变体**每人普攻 ≤ 8 KB。近白可以用 docs/231 附的口径自己量（RGB 最小值 ≥ 230 的非空像素占比）。
7. **登记接入。**
   - `art.gd` V6_FRAMES 本组块里加 `"<名>": [帧数, fps], "<名>_glow": [帧数, fps]`。
   - `godot --headless --path game --import`，新 `.import`（含 `_glow`）的 `process/fix_alpha_border` 改 false。
   - `python tools/asset_index.py`（本地跑，**不提交 game/art/index.json**，合并人统一生成；要导网页测帧时，另做一个只含 index.json 的测量提交，不进分支，见 §4）。
   - 干员 JSON 换名，`if_tex` 一起换；seg_*.gd 里写死的缺省名一并换（否则 fx_coverage 仍报未做）；弹体锚点表（如 `EXU_TEX_ANCHOR`）给新名加一条。
8. **回退、轮换、满屏砍余韵（art.gd 两张表，代码挂点已接好）。**
   - `PX_BASIC_OLD` 加 `"新名": "旧名"`：`Art.px_basic(g, name)` 在 `fx/px_basic = 0` 或 `g.opt_old & Game.OPT_PXB` 时返回旧名。挂点：`ob_fx.fx_spawn`（JSON fx 段的 strip）、`op_api.spawn_fx_sprite`（枪口 / 命中这类 fx_sprite）、能天使 `seg_exusiai` 生成子弹时。别的远程干员的弹体若不走前两处，在生成时同样包一层 `Art.px_basic(g, 名)`。
   - `PX_BASIC_BODY` 加 `"新名": 主体帧数`：`Art.px_tail_cut` 在满屏（`g.fx.size()` > balance `fx/px_tail_cap`，缺省 300）时把寿命截到主体帧，余韵不播（docs/229 §2.5「满屏时只留主体」）。挂点同上两处。
   - 光晕、变体不用另挂：`vfx.px_glow` 按实际绘制的贴图名 + `_glow` 查，`vfx.px_vary` 在开播时挑变体 + 镜像 + 小转角；回退成旧名时都自然不生效。`PX_BASIC_OLD` / `PX_BASIC_BODY` 只写基础名（不写 `_v1`），换名和截断在挑变体之前做。
   - 近战干员换了专属刀光帧条时，把它加进 `PX_BASIC_NO_ARC`（干员 id → 刀光帧条名）：不再画通用近战刀光弧（`character.arc_targets` → `vfx.melee_arc`），否则两道弧叠在一起（本试点录像里看到的）；回退旧条时照画。
9. **验证。**
   - 同种子 TRACE：`python tools/trace_base.py 1 <干员> 240 --here`；有精一件的另跑 `--extra=--prog=8`（`--extra` 要写成等号形式）。退出码 0 = TRACE 逐行相同。
   - 对照录像：同种子原速 30 帧（`--fixed-fps 30 … --realtime --recframes`），旧版加 `--bal=fx/px_basic=0`，左旧右新 hstack；过 vreview。
   - 帧时：§4 的命令，P50 / P95 差 ≤ 0.3 ms。
   - `python tools/fx_coverage.py --op <干员>` 普攻行应为已做；只为回退保留的旧名在本组 coverage_<组>.json 登记 `已做` + 理由。

## 3 判定与同种子 TRACE

（待填）

## 4 帧时（--mobilecap 网页仿真，同局轮换）

（待填）

## 5 对照与预审

（待填）

## 6 遗留

- 拉普兰德「回敬」（rage2 节点）的反斩仍用旧 fx_lappland_slash + 兜底 fx_slash_heavy_deep，属成长形态，归 A 组；终结技 ult_moves_c 里的 fx_lappland_slash 归终结技。attack 段里 `if_tex: "!fx_lappland_px_slash"` 的兜底 blade 只在新贴图缺失时画，留着。
- 能天使连携 link_fx_a 仍用旧 fx_exusiai_muzzle（连携段，归 D 组）。
- 旧条暂不删：都是 `--bal=fx/px_basic=0` 的回退件，用户定稿后由合并人清点。
- 拉普兰德 OP 色阶本身饱和度很低（设定色 #dbe0f2，平均饱和 0.09），新刀光是银灰调；若要更亮的「冷光」，改 house.js OP.lappland（组长）。
