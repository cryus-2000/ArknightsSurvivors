# 拉普兰德「双手平举前推」帧核对（11-07）

用户：「双手平举往前推的动作其实是攻击动作，查阅原本的 prts 对应的动作序列」。对照图：`docs/img/lappland_pose_compare_1107.png`；原作渲染：`build/prts_ref/lappland/lappland_sheet.png`（只有 Idle / Attack / Skill 三段采样）。

## 1. 原作动作段（PRTS Spine，`lappland_info.json`）

| 段 | 时长 | 出手事件 | 姿势 |
|---|---|---|---|
| Idle | 2.0s | — | 持剑立姿 |
| Attack | 1.33s | 0.60s | 0.3s 侧身蓄势 → 0.6s 单臂前刺、剑水平前指 → 0.97s 收回 |
| Combat | 1.17s | 0.47s | 本地没有渲染采样；游戏用它做普攻（见下） |
| Skill | 1.33s | 0.57s | 0.28s 立姿 → 0.57s 双剑交叉前压 → 0.95s 蹲身双手前推、多剑水平前指 |
| Start / Die | 0.83s / 1.0s | | 入场 / 倒下 |

「双手平举前推、蹲身」在原作里属于 **Skill 段 0.5–0.95s**（出手之后的释放姿势）；Attack 段 0.6s 的单臂前刺是普攻的前推。

## 2. 游戏现在怎么用（实测：lappland 当队长，`--dashat` 冲刺 5 次，8–40s 逐帧记 anim_state）

| 状态 | 帧条 → 原作 | 实测显示的帧 |
|---|---|---|
| 待机 | idle ← Idle | idle |
| 移动 | run（Spine 静态脚本重绘的前倾跑姿，非原作段） | run f0–f7 |
| 冲刺中 | 不单独切帧：照常 run / 普攻 / throw | run、attack f7、throw f0–f1 |
| 普攻（站立） | `attack`=op_lappland_combat ← 原作 Combat | combat f0–f7 |
| 普攻（移动中） | `move_attack` = combat 上半身 + 跑步腿 | f0–f7（f4 因攻速抽帧偶尔跳过） |
| S1 / S3 | `skill` ← 原作 Skill | 站着播 f0–f7；移动中出手帧（f3）之后让给 run，所以 f4–f7 只在站定时出现 |
| S2 | `throw` = op_lappland_attack ← 原作 Attack | 移动中只看到 f0–f3 |

用户截图的姿势（蹲、双手前推、剑水平、剑指向前）最像 **skill f4–f6**（其次 move_attack / combat f4–f5 的前推）。我没能在探针里复现「移动 + 冲刺时显示 skill f4–f6」：skill f4 起移动时会让位给 run。所以这一帧最可能出现在站定放 S1 / S3、或被冲刺拖动的瞬间（冲刺中 mv 不一定高于 RUN_ENTER，不会立刻换成 run）。**需要用户说一下截图时是在做什么**（站着放技能？冲刺？招募 / 图鉴？），或我用 GCP 录一段对应场景再定。

## 3. 建议（未改任何代码 / 素材）

| 状态 | 现在 | 建议 |
|---|---|---|
| 移动 / 冲刺 | run（重绘前倾） | 不用任何前推帧；run 保持，冲刺期间强制 run 相位，避免被技能 / 普攻帧条占住（需先确认截图场景） |
| 普攻（站立） | combat 全 8 帧 | 前推出手帧应落在原作 Combat OnAttack 0.47s（f4–f5，源帧 14），保持 |
| 普攻（移动） | move_attack | 同上；若要「跑动时不出现站定前推姿」，只能换成 run 上半身不动（缺：无） |
| S1 / S3 | skill 全 8 帧，移动中截断到 f3 | 截断点之后的前推（f4–f6）本就是技能释放姿，不应出现在跑动里；保持截断，另加冲刺中同样让位 |
| 图鉴 | 另核（本次未看）| 图鉴「攻击」应取 combat f4（出手帧）而不是 skill f4–f6 |

帧条缺什么：无；Combat 原作只有游戏帧条里的 8 帧，PRTS 渲染缺 Combat 段采样，若要逐帧复核需补渲 Combat（`tools/prts_spine.py`）。

## 4. 实施（11-07，用户确认「是在放一技能的时候」）

- 根因：S1「日晷」的施放动作 `sprites.skills.s1.anim = skill`，而 `skill` 条是原作 Skill 段，其 f4–f6（0.5–0.8s）是蹲身双手前推的释放姿；S1 站定放时整段播出。原作 Attack 段（S2 的 `throw`）才是单臂前刺的攻击动作。
- 改法（只画）：`lappland.json` 新增 `s1cast` 帧条槽——同 `op_lappland_attack` 贴图（原作 Attack 段），逐帧时长重排成总长 1.3333s、出手帧起点 0.5677s，与原 `skill` 条完全相同，所以 S1 施放窗口与出手时刻不变；`skills.s1.anim` 改 `s1cast`，`extra_sprites` 加 `s1cast`。`skill` 条只剩 S3 起手。
- 冲刺：`sprites.dash_run: true` + `character.gd` 的 `want` 判断：队长冲刺中放技能时身体播 run 相位（只改 anim_kind，`attack_t` / `fire_t` 不动）。
- 验证：同种子 TRACE（拉普兰德 seed 3，120 秒，`--dashat=20,40,60,80`）旧 / 新各 121 行逐行相同。
