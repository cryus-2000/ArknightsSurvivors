# 92 · Codex 美术单：安洁莉娜「反重力」浮空帧条（2026-10-13）

> 用户 10-13：「安洁莉娜会浮空，给 codex 需求单」。
> 用途：安洁莉娜开三技能「秘杖·反重力模式」（10 秒）期间，人物离地浮空；技能结束落回地面。
> 原作依据：三技能「秘杖·反重力模式」（PRTS <https://prts.wiki/w/安洁莉娜>）；她是重力系术师。
> **通用规格一律按 docs/87**（96px 为主绘制、只画朝右、1px `#080E18` 外描边、alpha 只有 0 / 255、1x 与 @2x 逐帧对应、命名与 manifest 规则）。本单只写与 docs/87 不同的地方和这次的动作要求。

## 1. 交付帧条

基于现有 `art/incoming/op_angelina_idle@2x.png` / `_run` / `_attack` 的造型与配色（同一个人、同一套色板，四组旧动作 + 本单四组合计仍尽量 ≤ 24 色），新增四条：

| 文件 | 帧数 | fps | 循环 | 动作 |
|---|---|---|---|---|
| `op_angelina_float_in.png` / `@2x` | 4 | 12 | 否 | 起飞：f0 = 现有 idle f0（脚在地上）→ 微屈膝 → 离地 → f3 = float f0 |
| `op_angelina_float.png` / `@2x` | 6 | 8 | 是 | 浮空待机：悬停、缓慢起伏 |
| `op_angelina_float_move.png` / `@2x` | 6 | 10 | 是 | 浮空移动：前倾滑行，**不迈步** |
| `op_angelina_float_attack.png` / `@2x` | 5 | 12 | 否 | 浮空普攻：与现有 attack 同一出手动作，在空中做；**出手帧 = 2**（同现有 attack），末帧回到 float f0 |

落地不另画：程序把 `float_in` 倒放。技能的施法动作仍用现有 `op_angelina_skill`（地面施法），施法结束接 `float_in`。

## 2. 与 docs/87 不同的地方：离地高度

- 浮空四条（`float_in` 的 f3、其余三条全部帧）**不碰脚底线**：最低不透明行 = **38 ± 1**（1x；@2x = 76 ± 2），即离地约 8px。脚底中心 x 仍在 24 ± 2。
- `float_in`：f0 最低行 = 46（与 idle f0 完全相同），f1 = 46（屈膝蓄力），f2 ≈ 42，f3 = 38。
- 画布仍是 48×48 / 96×96，头顶（含头饰）不得出画布；必要时整体身形与 idle 同高，只是整体上移。
- **不画影子**、不画脚下光圈 / 重力波纹 / 发光：影子由程序画（离地时缩小变淡），重力场特效另行处理（fx_* 归 Claude）。
- `art_lint` 的 `ground` 检查对这四条会报「离地」：这是本单的设计要求，Claude 会在 `tools/art_lint.py` WAIVERS 里登记；**其他检查（朝向、描边、透明、配对、洋红、尺寸）照常必须全绿**。

## 3. 动作要求

### 3.1 浮空待机 `float`（6 帧循环）

- 整体随浮动上下起伏 1–2px（@2x 2–4px），节奏比地面呼吸慢、更「软」：f0 中位 → f1、f2 上浮 → f3 中位 → f4、f5 下沉 → 回 f0。
- 双腿放松、自然下垂并拢略弯，**脚尖朝下**，不做站姿也不做跑姿。
- 失重感靠二次运动表现：头发、裙摆、披肩 / 飘带、衣角**向上、向后飘**，比身体晚 1–2 帧，幅度 1–2px（@2x 2–3px）。
- 法杖握在身前右侧，杖头与地面待机同位置；不画杖头光效。
- 脸、衣纹、法杖主体逐帧同一组像素，只随起伏整体平移，不要每帧重绘造成闪烁。

### 3.2 浮空移动 `float_move`（6 帧循环）

- 身体整体前倾约 10°（靠躯干整体倾斜，不伸脖子，见 `art/incoming/character_posture_constraints.md`）。
- 双腿并拢向后拖，不迈步、不蹬腿；头发、裙摆向后拉长飘动，表现「被托着滑行」。
- 起伏 1px，频率比 `float` 快一点；离地高度同 §2。

### 3.3 浮空普攻 `float_attack`（5 帧）

- 与现有 `op_angelina_attack` 的挥杖 / 发射姿势一致（玩家要认得是同一个动作），只是腿部换成浮空姿态、整体离地。
- 出手帧 f2；f4 收势回到 `float` f0（逐像素一致最好）。
- 弹体、重力球、光效**不画**（`proj_angelina_orb` 等由程序发射）。

### 3.4 起飞 `float_in`（4 帧）

- f0 与 `op_angelina_idle` f0 逐像素相同；f1 微屈膝、裙摆下压（蓄力）；f2 离地、头发裙摆开始上扬；f3 与 `float` f0 逐像素相同。

## 4. 交付与自检

- 只动 `art/incoming/`：上面 8 个 PNG + `squad_angelina_float_manifest.json`（每条的帧数、fps、出手帧、离地最低行）+ `squad_angelina_float_handoff.md`（每条的动作说明、色数、art_lint 结果逐条说明）+ 预览 gif `squad_angelina_float_preview.gif`（顺序：idle → skill → float_in → float 两轮 → float_move 两轮 → float_attack → float_in 倒放 → idle）。
- 交付前跑 `python tools/art_lint.py --ops angelina`：除 §2 说明的离地 `ground` 项，其他全绿；同时看 `build/art_lint/compare_angelina.png` 确认朝右 3/4 侧身、与旧动作同一配色。
- 一个提交，提交说明写「Codex: 安洁莉娜浮空帧条（docs/92）」；交回时告诉 Claude 提交号。

## 5. Claude 收到后做的事（Codex 不用管）

- `angelina.json` 的 `sprites` 加 `float_in / float / float_move / float_attack`（foot 仍 [24, 46]，离地靠画面本身）；三技能持续期间用浮空组动作，结束倒放 `float_in` 落地。
- 程序影子：浮空时缩小到约 70%、变淡；判定（碰撞、拾取、受击）仍按地面位置。
- `tools/art_lint.py` WAIVERS 登记四条浮空帧条的 `ground` 豁免。
