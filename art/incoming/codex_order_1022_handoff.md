# Codex 素材单 10-22：精英化素材核对 + 骑士 @2x 返修

> 协调人 10-22 派单。按 docs/104 的单子格式：本单只写**范围**（谁、哪一版母稿、整条还是单帧、交付路径），口径一律引用原文档（干员画布 / foot：docs/108 §5；敌人原生条：docs/98 §10.1 与 `game/data/enemy_pixels.json`；验收：docs/104 §4 三层，人眼先行）。
> Codex 只动 `art/incoming/`，不改 `game/`；交付带提交号与改动路径。

## 1. 精英化形态素材（docs/91 设计、docs/93 素材单）：核对结果，本单不派新活

逐条核对 docs/93 表里的全部文件名（82 条，含 `_1/_2/_3`、`_t1–_t3`、`_open/_close`）与 `art/incoming/`、各干员 json、`game.gd V6_FRAMES`（10-22，main 9481b312）：

- **全部已交付并接入**（docs/93 §1.6 / §2.5 / §3.5 / §4.5 / §5.2 的接入记录），没有缺图项。
- 表面上「找不到」的 7 条都有去处，不是欠交：

| docs/93 文件名 | 现状 |
|---|---|
| `fx_ulpianus_anchor_impact` | 按表里「ground + front 两层」交成 `fx_ulpianus_anchor_impact_back` / `_front`（+ @2x） |
| `fx_specter_saw_cold` | 按 0.85 倍另起名，交成 `fx_specter_saw_cold_back` / `_front`（+ @2x），docs/93 §3.5 |
| `fx_slash_heavy_rose` 的 @2x | 有意没有：Codex 版改名 `fx_hoshiguma_slash_rose`，原文件恢复为无 @2x 的旧版，docs/93 §1.6 |
| `op_kaltsit_m_lunge` / `op_kaltsit_m_leap` | 10-20 Mon3tr 整套换原生条（`visual` 显示时钟，docs/107），旧 48 条已删 |
| `op_ulpianus_throw` | 10-20 换原生 `tether_native`（docs/108 §6），旧条已删 |
| `fx_wisadel_soul_fire` | 魂灵之影换原生条 + `visual`（docs/108 §4），旧开火条不再使用 |

- 精英化相关的人物 / 召唤物帧条都已在新口径上：星熊 `throw`、归溟幽灵鲨 `doll_spin` 为 64 画布；斯卡蒂 `leap_strike`、艾丽妮 `finisher` 为 96 加边画布（foot = 64 口径 + 16，docs/108 §5）。仍是 48 口径的只有浊心斯卡蒂 `ishar_*` 四条和归溟幽灵鲨 `doll`，它们带 `visual`，画面由原生条播，旧条只当计时契约（docs/108 §5 召唤物例外），**不用重画**。
- 结论：docs/93 没有可开工的未交付条目。若之后要按 64 画布的人物体型复查精英化特效的尺寸与挂点（例如头顶光环、挑刺弧光），由 Claude 在游戏内截图核对后另开单，本单不预设。

## 2. 返修单：骑士 `e_knight*` @2x 尺寸

**问题**（docs/115 §4）：骑士 1x 与 @2x 不是同一套尺寸，@2x 不是 1x 的整数倍。`A.tex()` 按文件名优先取 @2x、再按固定密度 2.0 换算坐标，凡按 1x 坐标取 @2x 像素的地方（画像裁切等）会取错区域；画像现在绕开 @2x 读 1x 应急。

现状（10-22，main 9481b312）：

| 文件 | 1x 尺寸（单帧 × 帧数） | @2x 尺寸（单帧 × 帧数） |
|---|---|---|
| `e_knight` | 192×80（96×80 × 2） | 586×293（293×293 × 2） |
| `e_knight_move` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_attack` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_charge` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_charge_form` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_death` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_plant` | 384×80（96×80 × 4） | 1172×293（293×293 × 4） |
| `e_knight_spin` | 576×80（96×80 × 6） | 1758×293（293×293 × 6） |
| `e_knight_thrust` | 288×80（96×80 × 3） | 879×293（293×293 × 3） |
| `e_knight_walk` / `_walk_move` / `_walk_attack` / `_walk_charge` / `_walk_death` | 无 1x | 794×397 / 1588×397（397×397 × 2 / 4） |

1x 是 V9 骑乘造型（`knight_v9_handoff.md`，锚点 (48,77)）；@2x 是之后的原生透明加边条（`enemy_pixels.json` 记 `frame_size [293, 293]`、归一化锚点 (0.4983, 0.8055)、scale 1.0）。

**要求**：
- 重交骑士全部动作的 1x / @2x 成对条，**@2x = 1x × 2 精确尺寸**：每帧 @2x 宽高正好是 1x 单帧的 2 倍，帧数、帧序两边一致，整条宽 = 单帧宽 × 帧数。
- 造型以**当前 @2x 原生条为准**（现在游戏里画的就是它），不要退回 V9 的 1x 造型。原生 293 是奇数、不能二等分，所以 @2x 单帧加 1 列 / 1 行透明边到偶数（例如 294×294），1x 为同一姿势的 147×147；锚点按新画布重算，在 manifest 里写 1x / @2x 两套像素原点。
- `e_knight_walk*` 五条一并补 1x（同上规则），或在 handoff 写明「只交 @2x」并由协调人确认（docs/104 §1：干员只交 @2x，敌人未改此口径）。
- 不改像素内容、不改帧数与出手帧（攻击 / 冲锋 / 刺击的结算帧同现版）。

**交付**：只动 `art/incoming/`；一个提交；附 `knight_size_fix_manifest.json`（每条：文件名、帧数、1x / @2x 单帧尺寸、1x / @2x 锚点像素、SHA-256）+ 简短 handoff（说明加边方向）+ 新旧 @2x 叠图对照（逐帧差异应只在加的 1 像素边）。
**验收**（docs/104 §4）：① 人眼：新旧 @2x 并排逐帧一致；② 数值：`tools/enemy_art_check.py` 与尺寸核对（@2x = 1x × 2）；③ 游戏内：Claude 接入时同步改 `enemy_pixels.json` 的 `frame_size` / `anchor`，画像 `_portrait_tex_1x_key()` 的应急绕路随之删除。
