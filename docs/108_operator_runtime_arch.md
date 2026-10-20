# 108 干员动画运行时架构（现行，2026-10-20；同日标准化收口见 §12）

> 架构会话 10-20 审读 `6b697796..7784b32c`（Codex 10-17 起的 three-attack-timing → mizuki-standardization → logos-projectiles → siege-ulpianus-runtime → eyja-volcanic-weight、doctor-style-integration、summon-alignment、enemy-mechanics、anim-review-fixes 等分支）后收拢的**现行口径**。
> 冲突时以本文为准；docs/105（已实施记录）、106 §4、98 §2–§3、87 §1 / §3.5 中与本文不一致的段落已加指向本文的标注。字段写法细节仍见 87 §3.5（序列）、docs/107（召唤物显示时钟）、docs/plans/2026-10-18-*（各模块设计稿）。
> 编号说明：任务原定 107，但 107 已被《召唤物美术运行时对齐》占用，改用 108。

## 1. 分层：谁拥有什么

| 层 | 文件 | 拥有 | 不许做 |
|---|---|---|---|
| 动作窗口（逻辑） | `character.gd` `_start_action` / `start_attack` / `start_skill` | `attack_t`、`attack_dur`、`attack_fire_at`、`fire_t`、`act_kind`、`act_anim`、`attack_phased` | — |
| 帧时钟（纯显示） | `character.gd` `frame_seconds` / `frames_seconds` / `timed_frame` / `attack_phase_frame` | 由秒数换帧号 | 改伤害时刻 |
| 技能序列（纯显示） | `character.gd` `sq*`、`_start_skill_seq`、`_tick_sq`、`_sq_pause` / `_sq_clear`、`set_attack_phase` | start → enter → loop/run/attack → end 的阶段与恢复 | 调度伤害 |
| 持续攻击（逻辑） | `blocks/attack_phases.gd`（状态在 `data_operator.phases`） | 分阶段倍率、连发队列、阶段切换、结束事件 | 执行具体效果（交给 `phase_shot` / 适配器） |
| 技能生命周期（逻辑） | `blocks/skill_lifecycle.gd`（状态在 `data_operator.lifecycle`） | 绑定「权威计数器」（s_t / ammo / perm_on / 适配器自己的字段），算剩余、占用、自然结束、取消 | 自己推进计数器 |
| 占用闸门 | `data_operator.skills_occupied()` | 动作中技能 / 水月收势 / 持续攻击 / 独占生命周期 → 禁止起新技能；**不禁止充能** | — |
| 原生动作覆盖（纯显示） | `native_motion.gd`（状态在 `data_operator.native_motion`），信号由手写段 `*_native_signals` 提供 | 按 json `native_motion` 把原生姿势覆盖到 `anim_state()`（§3.5） | 读写伤害、位移；认识具体干员 |
| 召唤物显示时钟（纯显示） | `summon_visual.gd`（状态在召唤物字典 `s.visual`） | 原生帧按源时间轴播放，出手事件对齐真实 `_mf_strike` | 被玩法读取 |
| 怪物原生条（纯显示） | `art.gd enemy_pixel_*` + `data/enemy_pixels.json`、`world.gd _dc_compute / _draw_enemy_full / _enemy_top` | 归一化锚点、显示倍率、标签高度 | 改判定半径 |

**同 seed 规则**：上表「纯显示」层只能写自己的状态；玩法随机一律 `g.rng`，画面随机 `g.vrng`（`weapons.gd` 新加的火花用了全局 `randf()`，不影响同 seed 但不合 106 §6.4，见 §8）。

## 2. 每帧次序（data_operator.update，10-20）

```
s_t 递减
AttackPhases.tick        ← 连发队列 / 阶段切换 / 结束事件（在弹体推进之前）
ObHw.hw_tick             ← 手写迁移段（浪墙 / 弹体 / 锚…），返回 true = 本帧不起手
NativeMotion.tick        ← 纯显示
SkillLifecycle.tick      ← 绑定计数器归零 → 结束事件（全部效果结束才发一次）
ObSummon.mf_tick         ← 带 at 的 on_skill_end（attack_phases / lifecycle 管的技能跳过，防重复）
_tick_pending / _sustain / SegMizuki.h3_tick_effects / _tick_shots / exu_tick / sm_tick …
起技能（skills_occupied 闸门）
AttackPhases.attack_locked → return
起普攻（start_attack → AttackPhases.begin_round）
```

结束事件有三个来源，互斥：① `s_t` 由正变零（seg_texas / mf_tick 旧路径，跳过 `attack_phases` 与 lifecycle 已管的技能）；② `AttackPhases.tick` 的 `phase_skill_end`；③ `SkillLifecycle.tick` 的 `phase_skill_end`。

## 3. 状态机

### 3.1 普攻（attack_timing）

```
            start_attack(aim, dur, fire_at, anim, interval)
                │  dur = min(timing.duration, interval×active_ratio)，不低于 min_duration
                │  fire_at = min(timing.fire_time, dur×windup_ratio)
                ▼
  [前摇 0..fire_at] ──fire_t 到点── _release()（每次动作只调一次）── [收势 fire_at..dur] ── 待机
  画面：前摇映射到 0..fire-1 帧，收势映射到 fire..n-1 帧（attack_phase_frame）
  cd = max(cd, attack_dur + min_rest)    ← 只有写了 min_rest 的（水月）
```

没写 `attack_timing` 的槽：有 `frame_durations` 时 `dur = Σframe_durations`、`fire_at = fire_time`；都没写时走旧口径 `dur = frames/fps`、`fire_at = (fire+0.5)/fps`。

### 3.2 技能序列（纯显示，87 §3.5）

```
sq_ph: 0 无 ─起手─▶ 1 start/intro ─▶ (4 enter) ─▶ 2 loop/run/attack 变体 ─剩余≤0─▶ 3 end ─▶ 0
  · 起手 / 收势途中被别的动作打断 → 序列作废
  · loop / enter 被另一技能序列遮住 → 压进 sq_paused（每技能一份），遮挡结束后恢复；原技能已结束 → 只播 end
  · 持续攻击切阶段 → set_attack_phase 替换 loop/attack/end（只在两轮之间），可播 transition
```

### 3.3 持续攻击（attack_phases，首例维什戴尔 S2）

```
_release_skill ─AttackPhases.start─▶ 阶段0 ─(技能已用比例 ≥ at[j]，且当前轮已完)─▶ 阶段 j（transition 期间不起新轮）
每轮：begin_round 冻结倍率 / 动画 / 连发表；_release → release：shot0 立即、其余按 shot_offsets 入队
s_t 到 0：不再起新轮 → 排空当前轮 → phase_skill_end（一次）→ 序列收势结束后 phases = {}
离队 / 中断：cancel → s_t=0、清队列、cancel_skill_action（已发弹体保留）
```

### 3.4 技能生命周期（skill_lifecycle）

`bind(key, skill, source, field, foreground, exclusive, cleanup, unit)`：效果适配器在技能 `do` 执行期间（`effect_skill` 有效）把自己的计数器登记进来。

| 量 | 规则 |
|---|---|
| `skill_active_left(i)` | 有前台效果 → 前台最大剩余；否则持续攻击剩余；否则手写段；否则 `max(s_t, 次数)` |
| `skill_on(i)` | `s_t>0 或 perm_on 或 ammo>0 或 前台效果剩余>0 或 手写段剩余>0` |
| 占用 | `exclusive` 效果剩余>0，或该技能序列未退出 |
| 结束 | 该技能所有已绑效果都 ≤0 → `phase_skill_end` 一次；刷新（重绑同 key）不算结束 |
| 取消 | `on_leave` → 计数器清零 + `cleanup`；不触发自然结束 |
| 默认绑定 | `bind_skill_duration`：永久 → `perm_on`（后台、unit permanent）；次数 → `ammo`（后台、unit attacks）；水月 s_t → 前台 |

条目寿命：某技能的效果全部结束、且该技能序列已退出后，**下一帧**移除（`left` 回到 -1、`owns` 为假）；结束当帧保留，防旧 s_t 路径同帧再发一次 on_skill_end。

现有适配器绑定：塞雷娅 `heal_over_time`（后台）/ `calc_field`（前台）；铃兰 `fox_haze`（前台）/ `fox_warm`（永久）；维什戴尔 `cannon_load`（前台、独占、发数）。

### 3.5 原生动作覆盖（native_motion，数据驱动）

手写段只暴露**信号**（`data_operator.native_signals()` 汇总 `SegSiege.h4_native_signals`、`SegUlpianus.hw_native_signals`）：名 → 进度 0–1，如 `leap`、`tether.reel`、`zip.hold`、`hook.drag`、`whirl`。`native_motion.gd` 不认识任何干员，只按 json 走：

```json
"native_motion": {
  "clips":    {"attack": 0.667, "attack_s2": 0.667},          // 起手（_start_action）后整条播的秒数
  "variants": [{"slot": "attack", "perm": 1, "use": "attack_s2"}],  // 普攻时技能 perm 永久生效 → 换播 use
  "states": [                                                 // 按序取第一条命中的
    {"on": "tether.reel", "slot": "tether_native", "from": 3, "to": 4, "rate": 2},  // 帧 = from + min(to-from, int(k×rate))
    {"on": "tether",      "slot": "tether_native", "from": 1, "to": 2, "rate": 2},  // on 匹配信号名或其「族.」前缀
    {"on": "act:throw",   "slot": "idle", "loop": true}                              // act:<槽> = 该动作窗口内；loop 按槽帧时长循环
  ],
  "exits": [{"on": "tether", "slot": "tether_native", "from": 6, "tail": 0.16}]   // 信号族结束 → 从 from 帧用 tail 秒播完
}
```

帧数一律取槽的 `frames`（不再写死 8）。校验见 V4 / V8。新人若有 Spine 原生姿势：手写段加一个 `*_native_signals`（只读自己的状态、写进 out），其余全填 json。

## 4. json 字段表（现行）

位置缩写：`S.` = `sprites.`，`S.<slot>.` = 任一帧条槽，`B.` = `blocks.`。时间一律秒，坐标一律 **1x 逻辑像素、帧内坐标、朝右**。

| 字段 | 含义 | 校验 | 用者 |
|---|---|---|---|
| `S.<slot>.{tex,frames,fps,foot,fire}` | 帧条槽；`fire` 零基出手帧 | validate_operator / art_lint | 全员 |
| `S.<slot>.frame_durations[]` | 每帧秒数，长度 = frames；完整条求和与 frames/fps 相等时按名义值（不改物理帧数） | `valid_frame_durations` | exusiai eyja logos saria siege suzuran ulpianus wisadel |
| `S.<slot>.fire_time` | 出手 / 事件时刻，替代 `(fire+0.5)/fps` | 同上（< 总时长） | 同上 + mizuki |
| `S.attack.attack_timing{duration,fire_time,active_ratio,windup_ratio[,min_duration,min_rest]}` | 普攻随攻速压缩的完整动作（§3.1） | `valid_attack_timing`（**只查 `attack` 槽**） | mizuki saria suzuran wisadel |
| `S.<slot>.muzzles[帧][发]` | 逐帧炮口 [x,y]，随 face 镜像 | `h4_phase_validate`（只炮击） | wisadel s2_attack / s2_over_attack |
| `S.<slot>.<点名>[帧]`、`pt_foot` | 逐帧定位点（盾心 `shield`、手 `hand`、炮口 `muzzles`）；一律经 `sprite_point_at(槽, 点名, 帧, 组内序号)` 换世界坐标（含 pt_foot、flip / mirror、draw_scale；画面点加 draw_off，玩法点不加） | V5 / V6 / V9 | hoshiguma、ulpianus、wisadel |
| `S.<slot>.frame_size` | 非正方形单帧尺寸 | 无 | wisadel 魂灵 |
| `S.<slot>.visual{anim,times[],duration,event}` | 召唤物原生显示时钟（docs/107）；`anim` 必须在 `extra_sprites` | `summon_visual.errors` | kaltsit skalter specter wisadel |
| `S.skills.sN` | 单条 `{anim}` / hold `{intro,hold,hold_ms}` / 起手型 `{start,loop[,enter,run,attack,end,shadow,shadow_a]}` | validate_operator（87 §3.5） | 8 人 |
| `S.skills.sN.phases[]{loop,attack,end[,transition]}` | 持续攻击每阶段的动画；数量 = `attack_phases`；首段不写 transition | `AttackPhases.validate` | wisadel s2 |
| `B.skills[i].attack_phases[]{at,interval_mult,damage_mult,burst,shot_offsets[],target}` | §3.3；`at` 首项 0 严格递增 <1；`shot_offsets` 长 = burst，首 0 严格递增 <1（出手→收势末的比例）；`target` inherit / random | `AttackPhases.validate`：普攻须 circle / cone / cannon，不能 armed / combo / free，**整名干员任一处有 `swap_attack` 即禁用** | wisadel s2 |
| `B.skills[i].attack_effect{src,size,aim_r[,mark]}` | 炮击适配器参数 | `h4_phase_validate` | wisadel |
| `B.skills[i].stack_max` | 次数型技能可叠加上限（`load_skill_attacks`） | — | — |
| 顶层 `native_motion{clips,variants,states,exits}` | 原生动作覆盖（§3.5）；收势可超出逻辑窗口 | V4 / V8 | siege ulpianus |
| `B.*.trig every_n.vis_anim` | 非 replace 的追加段触发时只播的画面帧条（`play_vis_anim`，不占动作窗口、不改出手）；须是 sprites 键并列进 `extra_sprites` | ob_check `trig.every_n` | skadi 反手斩（10-20） |
| 顶层 `native_motion{<slot>: 秒}` | 原生动作显示时长；收势可超出逻辑窗口 | **无** | siege ulpianus |
| `S.draw_scale` | 本体整体显示倍率 | 无 | mizuki 0.9 |
| `S.size` | 画布边长（运行时不读；art_lint 核对贴图） | V2 / V3 | 全员 |
| `S.foot_exempt`、`S.<slot>.foot_exempt` | 不合 §5 口径的原因说明（字符串）；写了才放行 | V2 | saria suzuran wisadel mizuki、ulpianus 两槽 |
| `S.foot` | 顶层缺省脚底；槽内 `foot` 优先 | — | 全员 |
| `data/enemy_pixels.json{anchor,scale,frames,frame_size,preserve_palette[,visible_height,visible_rect]}` | 原生怪透明留白条：归一化锚点、显示倍率（普通 0.667 / 大型 1.0），标签高度按可见像素顶 | enemy_pixel_contract | 116 条 |
| `enemies.json draw_scale` / `transformed_draw_scale` | 怪物显示倍率（不改判定） | — | 7 种 |

## 5. 画布与原点口径

**定稿规格（10-20 协调人转用户批准，V2 / V3 强制）**：

| 画布（1x） | 用途 | foot | 规则 |
|---|---|---|---|
| 48 | 旧干员（未换新美术） | 顶层脚底行 46 | 维持到重画，不再新增 |
| **64** | 现行干员身体（只交 @2x = 128） | 顶层 **(32, 60) 整数** | **主规格**；`sprites.size: 64` |
| 96 | 64 四边各加 16 透明边，装超界动作 | 顶层 foot + (16, 16) = (48, 76) | 只给超界槽用；像素密度不变、**不得**因画布大而放大人物 |
| 128 | 64 四边各加 32 透明边 | 顶层 foot + (32, 32) = (64, 92) | 同上 |

- 槽 foot 必须正好是「顶层 foot + (0|16|32, 同值)」；Spine 烘焙出的小数原点由交付侧在出图时对齐到整数（不是在 json 里写小数）。
- 例外须在 json 写 `foot_exempt` 说明原因（V2 放行、art_lint V3 跳过）。现有例外：塞雷娅 / 铃兰 / 维什戴尔的小数顶层 foot 与整数跑步条（取整会让本体平移半个 @2x 像素、维什戴尔还会挪炮口原点，等协调人定是否取整）；水月 96 画布；乌尔比安 whirl_native / attack_s2 的 128 裁窗脚底行 90。
- 召唤物 / 魂灵等非本体槽（带 `visual`、被 `visual.anim` 引用、或带 `frame_size`）不受本节约束，按 docs/107。

- foot 一律 1x 逻辑像素；art_lint 对浮点 foot 取 floor 行；@2x 由 `hires_of` 自动折算。
- 例外：**水月整套用 96 画布 + `draw_scale 0.9`**（docs/103 10-16 的试验值沿用），不是 64 主规格；定位点换算已乘 draw_scale，但 V9 仍要求有定位点的干员先确认缩放再加。
- 怪物：原生条不再「脚底贴画布底」，按 `enemy_pixels.json` 归一化锚点 + 0.667 / 1.0 显示倍率；98 §10 的放大档作废、以 98 §10.1 为准。

## 6. 现状表（10-20 main 7784b32c）

| 干员 | 画布 | 时序字段 | 技能序列 | 共用模块 | 备注 |
|---|---|---|---|---|---|
| 维什戴尔 | 64 + 96 | attack_timing、frame_durations、muzzles | s2 phases×2、s3 start/loop/attack/end | attack_phases（炮击适配）、lifecycle `cannon_load` | 魂灵之影走 `visual` 显示时钟：出场 `native_soul_start` → 常驻 `soul_idle` → 魂炮开火起 `native_soul_attack`（OnAttack 对齐出膛，开火窗口内仍画 `fx_wisadel_soul_fire`）→ 离场 `native_soul_die`（10-20，seg_wisadel `_h4_soul_native`） |
| 塞雷娅 | 64 + 96 | attack_timing、frame_durations | s1/s2 `skill_heal`、s3 序列 | lifecycle `heal_over_time` / `calc_field` | |
| 铃兰 | 64 + 96 | attack_timing、frame_durations | s2 hold、s3 序列 | lifecycle `fox_haze` / `fox_warm` | |
| 水月 | **96 + draw_scale 0.9** | attack_timing（含 min_duration / min_rest） | s2/s3 start/loop/attack/end | lifecycle `skill:i`（s_t 前台） | 删 `flow: free`；伞 `shape.umbrella` 走 start→fire→recovery |
| 逻各斯 | 64 | frame_durations | s1/s3 序列、s2 单条 | `hw_native_body_state` | 交替弹体 a/b |
| 艾雅法拉 | 64 + 96 | frame_durations | s3 start/loop/run/end | — | 熔岩弹 `magma_projectile.gd`、S3 收势 0.28 s、`look.weighted` |
| 能天使 | 64 | frame_durations（全槽） | s1–s3 单条 | 次数型 lifecycle 默认绑定 | |
| 推进之王 | 64 | frame_durations | 无（`skills[].anim`） | native_motion（数据驱动） | 取消号令 |
| 乌尔比安 | 64 + 128 | frame_durations、`hand` | 无（elite2 `anim: throw`） | native_motion（数据驱动） | 锚 / 锁链从 `hand` 连出 |
| 推进之王 | 64（**顶层 size / foot 仍写 48 / (24,46)**） | frame_durations | 无（`skills[].anim`） | native_motion | 取消号令 |
| 乌尔比安 | 64 + 128（同上，顶层未改） | frame_durations、`hand` | 无（elite2 `anim: throw`） | native_motion | 锚 / 锁链从 `hand` 连出 |
| 斯卡蒂（10-20 claude/skadi-integrate） | 64 + 96 | frame_durations + fire_time（窗口沿用旧条，同 seed 不变） | 无（S3 `swap_attack` 用 attack_spin；S2 skill 槽借 leap_strike 帧条） | talent `vis_anim: backslash` | Codex cz 原生 idle / attack / death + Claude Spine 脚本 run / leap_strike / attack_spin / backslash |
| 安洁莉娜 | 48（新序列、旧画布） | fire | s3 start/enter/loop/run/attack/end | — | 帧条待重画 |
| 安洁莉娜 | 64 + 96（attack） | frame_durations、fire_time（出手时刻同旧条） | s3 start/enter/loop/run/attack/end | 次数 / 永久默认绑定 | 10-20 原作条 + dl 步态跑步；浮空离地 9 像素烘进帧条（`tools/probes/package_angelina.py`） |

其余 8 人（星熊、艾丽妮、凯尔希、流明、斯卡蒂、浊心斯卡蒂、归溟幽灵鲨、德克萨斯）仍是 48 旧口径，见 §9。

## 7. 旧口径 ↔ 新口径冲突清单

| # | 旧（出处） | 新（现行） | 处理 |
|---|---|---|---|
| 1 | 干员 48×48、foot (24,46)（87 §1、98 §2–§3） | 64 主规格 + 96 / 128 透明加边（§5） | 已标注 |
| 2 | 出手 = fire 帧中点 `(fire+0.5)/fps`（87 §3.5） | 有 `fire_time` / `attack_timing` 时按秒数；伤害事件在出手帧**起点** | 已标注 |
| 3 | 时长 = 帧数 / fps | `frame_durations` 求和；`attack_timing` 随攻速压缩 | 已标注 |
| 4 | 变体普攻按 fps 偏移对齐普攻出手（87 §3.5 `sN.attack`） | `attack_phased` 时按 `attack_phase_frame` 同一时钟 | 已标注 |
| 5 | 技能末帧 = idle f0（98 §2、87 §1） | 收势可越过逻辑窗口（native_motion、召唤物 visual）；首末帧回 idle 只对旧条强制 | 已标注 |
| 6 | 帧数 idle 4 / run 6 / attack 4–6（87 §1、98 §3） | 新规格 8 帧起、原生条 12–40 帧，节奏写进 frame_durations | 已标注 |
| 7 | 外描边 100% `#080E18` | 新规格暗色收边走 art_lint WAIVERS | 仍按 87 §4 豁免 |
| 8 | 怪物只许整数倍缩放、脚底贴底（98 §1–§2） | enemy_pixels 归一化锚点 + 0.667 / 1.0 | 已标注 |
| 9 | Mon3tr 64×64 foot (32,60)（98 §3） | 旧 `m_*` 槽只当计时契约，画面由 256@2x 原生条 + `visual` 播 | 已标注 |
| 10 | `flow: free`（水月充满即发，105 §1、106） | 删除；水月走普通动作窗口 | 已标注 |
| 11 | `sprites.skill_pose`（105 §3.2） | 删除，出现即校验失败 | 105 已写 |
| 12 | 105 §4 安洁莉娜示例 `start: float_in` | `start: skill` + `enter: float_in` | 105 头注已写 |
| 13 | 105 §2 水月槽名 `player_*` | `mizuki_runtime_*` | 已标注 |

## 8. 废弃字段 / 代码路径

- `attack.flow: "free"`、`B["_free"]`、`SegMizuki.h3_free_update`、`_h3_free_skill`（水月）。
- `verb.mirror`（水月 S3 镜像）及其 `where_ok` / `EXEC_SEG` 登记；水月 S3 的 `echo` 字段改为 `full_circle{cond}`。
- `ObHw.h4_active_left`（固定技能下标 2 查 haze_t / ammo / calc）→ lifecycle 绑定。
- `ObHw.h4_leave`（铃兰离队撤加成）→ lifecycle `cleanup`。
- 维什戴尔 `sustain / over_mult / burst / s2_queue / s2_over` → `attack_phases`。
- `sprites.skill_pose`、`out_rev`（→ `end.reverse`）。
- 推进之王 S2 程序整身旋转（`h4_draw_body` 在有 native_motion 时让位）；独立号令。
- Mon3tr `fx_mon3tr_afterimage` 固定残影、旧 `m_*` PNG 的绘制（槽保留作计时）。
- 艾雅法拉 weighted 路径下的通用爆炸 / 火星 / boom_fx（非 weighted 路径保留）。
- 怪物 98 §10 放大档。

## 9. 剩余 9 人接入方案

任务原写「10 人」，实际未换新美术的是 9 人：安洁莉娜（新序列、旧画布）、星熊、艾丽妮、凯尔希、流明、斯卡蒂、浊心斯卡蒂（skalter）、归溟幽灵鲨（specter_unchained）、德克萨斯。另有博士已换；召唤物（Mon3tr、浊心的海嗣、替身、魂灵）已走 `visual`。

通用步骤（每人一样）：① Codex 交 64 画布 @2x 八帧级 idle / run / attack / skill / hurt / death（超界用 96，foot = 64 口径 + 16）；② json 改 `size: 64`、顶层与每槽 `foot`、`frame_durations` + `fire_time`；③ 普攻加 `S.attack.attack_timing`（参考值：duration = 原动作秒数、active_ratio 0.9、windup_ratio 0.45，水月类快手 0.375）；④ 有持续期的技能写 `S.skills.sN`；⑤ 跑 §10 的校验 + 同 seed（`trace_base.py`，纯换图应逐行相同；加 `attack_timing` 会改出手时刻，属有意变化，需协调人确认后再更新基线）。

| 干员 | 普攻形状 | 技能类型 | 可套模块 | 需要的帧条 / 字段 | 风险 |
|---|---|---|---|---|---|
| 安洁莉娜 | point_aoe | s1 次数、s2 永久、s3 限时浮空 | 序列已接；lifecycle 次数 / 永久默认绑定已生效 | 只需重画 float_* 四条到 64 + 改 foot；浮空离地行按 98 §2 换算到 64 | 浮空行 38 是 48 口径，换画布要重算（64 口径约 50–52）；`airborne` 的 shadow 系数 |
| 星熊 | cone | s1 窗口、s2/s3 限时 | 序列（s3 持盾冲锋 start/loop/end）；**不能用 attack_phases**（s3 有 swap_attack） | idle/run/attack/skill/throw + `noshield` 四条；逐帧 `shield` 定位点要按新画布重标或写 `pt_foot` | 盾心定位点 ×8 帧 × 多条；`noshield` 现缺图走 fallback |
| 艾丽妮 | thrust（H3 手写） | s1 次数（瞬发）、s2 瞬发、s3 限时 barrage | 序列（s3 start/loop/end）；thrust 不是 circle/cone，**不能用 attack_phases** | `second`（二段刺帧号）、`finisher` 槽要随新帧条重写 | `S.second=3` 是帧号常量，帧数变了要改；`e3_ir_anim` 手写覆盖 |
| 凯尔希 | support（治疗） | s1 瞬发、s2 永久、s3 限时 | 本体：序列；Mon3tr 已走 `visual`，不用动 | 本体 6 条；`command` 槽（s2/s3 用） | Mon3tr 的 `m_*` 计时契约不要随本体一起改；s2 永久 → lifecycle 后台 |
| 流明 | lantern（H3） | s1 瞬发、s2 永久、s3 限时塔 | 序列（s3）；`prop_lighthouse` 已是 64 | 本体 6 条 | lantern 起手累计治疗计时，attack_timing 压缩会改治疗节奏，需数值会话复核 |
| 斯卡蒂 | cone | s1/s2 瞬发、s3 限时 | s3 用序列 + `sN.attack` 变体代替 `attack_spin`；**不能用 attack_phases**（s3 swap_attack） | attack_spin、leap_strike（elite1 `anim`） | swap_attack 换普攻形状 → 变体帧条要和换后的出手对齐，建议 attack_spin 也写 attack_timing |
| 浊心斯卡蒂 | circle | s1 限时、s2 永久、s3 限时 | 本体可用 attack_phases（circle），但现设计无分阶段需要；海嗣已走 `visual` | 本体 6 条 | 浮游离地行（98 §2）换算到 64 |
| 归溟幽灵鲨 | saw（H3） | s1/s2/s3 限时（s2 undying / substitute） | 序列；替身 `doll` 已走 `visual`（闪现环斩仍旧动作） | fall、doll_spin（elite2） | `h3_anim_state` 倒下帧条覆盖；替身环斩待补原生 |
| 德克萨斯 | dash_line | s1 瞬发、s2 永久、s3 限时 mode | 序列（s3）；dash_line **不能用 attack_phases** | 本体 6 条；当前无 `extra_sprites` | on_skill_end（s3）走 s_t 旧路径，换 lifecycle 绑定时要确认不重复触发 |

**推进之王 / 乌尔比安补尾**：已改（10-20 §12）。

### 9.1 试点：德克萨斯「只填 json」（10-20）

帧条不变，只改 json：`sprites.skills`（S1 / S2 单条 `skill`；S3 `{start: skill, loop: idle, run: run}`）+ `extra_sprites: []`。**没有改任何代码**。结果：
- 契约校验 V1–V9 零错误；`texas_contract` 回归（快检项）通过：S1 窗口 / 出手与原单条相同，S3 起手 → 持续期站立 idle / 移动 run → 结束退出，S2 永久由生命周期默认绑定为后台 permanent、不占技能通道。
- 同 seed：seed 1 180 秒、seed 2 240 秒满技力（`--sptest`）两局对 2968bf4a 逐行相同。
- 还缺（换新美术时才补，都是填 json）：64 画布帧条与 `size: 64` / `foot: [32, 60]`；`frame_durations` / `fire_time`；`attack_timing`（会改普攻出手时刻，属数值决定，交数值会话）；S3 若要专属循环 / 收势条，加 `skill_s3_loop` / `skill_s3_end` 并列进 `extra_sprites`。dash_line 普攻**不能**用 attack_phases（只支持 circle / cone / cannon），德克萨斯本来也不需要。
- 结论：现有积木 + 新契约下，新人动画接入只填 json 成立；需要写代码的只剩「新的普攻形状 / 新手写机制」本身，以及有 Spine 原生姿势时的一个 `*_native_signals` 信号函数。

## 10. 「新人接入只填 json」检查表（10-20 已全部实现：`operator_contract.gd`，test_core 坏样例逐条覆盖）

已有：skill_pose 禁用、`attack_timing`（仅 attack 槽）、`frame_durations`、sN 序列互斥、`summon_visual.errors`、`AttackPhases.validate`、`h4_phase_validate`。

| # | 建议新增校验 | 原因 |
|---|---|---|
| V1 | `attack_timing` 对**所有**槽校验（现在只查 `S.attack`；水月 skill / skill_sN_attack 上的不查） | 水月 5 个槽写了 attack_timing，只有 1 个被校验 |
| V2 | 每个被引用的槽必须有 `foot`，或顶层 `foot` 与 `size` 一致（`size` 64 ⇒ 顶层 foot y∈[56,64]） | 推进之王 / 乌尔比安顶层残留 48 口径 |
| V3 | `size` 与实际 @2x 单帧宽 / 2 一致，或槽宽 ∈ {size, size+32, size+64}（96 / 128 加边） | `size` 目前运行时不读、没人查 |
| V4 | 顶层 `native_motion` 的键必须是存在的槽、值 >0、对应条 8 帧（`pose` 写死 `hf 8`、`clampi 0..7`） | 现在零校验 |
| V5 | 逐帧定位点（任意 `[[x,y]|null]` 数组键，如 `shield` / `hand`）长度 = frames | 换帧条时最容易漏 |
| V6 | `muzzles` 长度 = frames 推广到非炮击（现在只在 attack_phases 炮击里查） | 新炮手 / 枪手会复用 |
| V7 | `frame_durations` 存在时 `fire_time` 必须落在 `fire` 帧区间内 | 防止帧号与秒数两套出手不一致 |
| V8 | `extra_sprites` 必须覆盖 `S.skills.*`、`phases[]`、`native_motion`、`visual.anim` 引用的所有槽 | 现在只部分路径查 |
| V9 | `draw_scale ≠ 1` 与逐帧定位点不能同时出现（`sprite_point` 不乘 draw_scale） | 水月 0.9 若加点会偏 10% |

实现：V1、V2、V4–V9 在 `game/scripts/characters/operator_contract.gd`（`validate_operator` 调用，错误以「V<n> 」开头）；V3 在 `tools/art_lint.py` 的「尺寸帧数」项；`test_core.test_operator_contract` 先断言 18 人真实数据零错误，再对每条规则一个坏样例断言只报对应编号。

## 11. 审查发现（严重度：高 = 会出错 / 中 = 维护或性能风险 / 低 = 口径不一）

| # | 级 | 发现 | 位置 | 建议 |
|---|---|---|---|---|
| F1 | 中 | `native_motion.gd` 按干员 id 写死分支（`o.id == "ulpianus"` / `"siege"`）并读手写段私有状态（`hw.sg.leap_t`、`hw.anchor.phase`、`hw.hooks`），`pose()` 写死 8 帧；名为通用模块，实为两人专用 | native_motion.gd 9、42–66 | 改成数据驱动：json 声明「状态 → 槽 + 帧区间」，手写段只暴露 `phase()`；接第三人前必须先改 |
| F2 | 中 | 新测试 `logos_projectile_test`、`three_operator_art_test`（及各 *_capture / *_trace）未登记进 `tools/check.py`，快检不跑（`native_core_test` 由 native_load 项调用，已覆盖） | tools/check.py REGRESSIONS | 前两项登记为回归；capture / trace 属手动工具，在 106 §5 注明 |
| F3 | 中 | `SkillLifecycle` 结束后的效果不移除：`left()` 对已结束的前台效果返回 0 而非 -1，`owns()` 永远为真；同一技能若下一次走不同路径（例如精英化换效果、或改成 s_t 型）会被旧条目遮住，`trig.on_skill_end` 的旧路径也会被 `owns` 永久跳过 | skill_lifecycle.gd `left` / `owns` / `tick` | 结束时 `erase` 或在 `_release_skill` 起点清掉该技能的旧条目 |
| F4 | 中 | 持续攻击 `target: random` 每发调用 `nearest_enemies(g.enemies.size(), …)`（全量排序 + boss_focus 重排）；炮击适配同样写法。四连发 × 400 只怪约每 0.2 s 一次全量排序 | data_operator `phase_shot`、seg_wisadel `h4_phase_shot` | 改为范围内计数 + `g.rng` 抽第 k 个，不排序；先用同局轮换量化 |
| F5 | 中 | 定位点换算有两份：`sprite_point()`（含 `draw_off`、`pt_foot`、flip 与 `sprite_mirror`）与 `h4_phase_shot` 自算炮口（只用 `face`、不含 pt_foot / mirror / draw_off）；任何带 `mirror` 的炮手会左右反 | seg_wisadel.gd 870–876 | 抽 `sprite_point_at(slot, key, frame, idx)` 共用 |
| F6 | 低 | `S.size` 运行时不读；推进之王 / 乌尔比安顶层 size / foot 残留 48 口径 | siege.json / ulpianus.json | V2 / V3；下次改 json 顺手改 |
| F7 | 低 | `sprite_point` 不乘 `draw_scale`，`_strip`（FX 助手）却乘 → 水月若加定位点 / 特效锚会偏 | character.gd 1688 / 2132 | V9 或补乘法 |
| F8 | 低 | `weapons.gd` 新火花用全局 `randf()`（画面随机应用 `g.vrng`） | weapons.gd（eyja weighted 火花） | 改 `g.vrng` |
| F9 | 低 | `attack_phases` 的 swap_attack 禁令按整名干员 `blocks` 查，星熊 / 斯卡蒂 / 乌尔比安任一技能有 swap 就整人不能用 | ob_check.gd 83 | 改为只查同一技能，或文档化（本文 §9 已注） |
| F10 | 低 | `_enemy_top` / `enemy_pixel_spec` 每次调用 `trim_suffix` + `str(get_rid())` 建字符串；只在标签 / 盾标路径用，量小 | art.gd 10–36 | 观察，不必改 |
| F11 | 低 | 同 seed：本批改动（attack_timing 改出手时刻、水月删 free、eyja 改弹速与收势）都是**有意的时序变化**，TRACE 基线需由协调人统一刷新；`phase_shot` 的 `g.rng` 抽取只在 random 阶段消耗，顺序稳定 | — | 合入后跑 `trace_base.py` 全员一次重建基线 |

本次审查没有发现需要立即改代码的明确 bug（F3 / F5 是潜在问题，现有 9 人的数据不触发）。

## 12. 标准化收口（2026-10-20，分支 claude/op-standardize）

| 项 | 处理 | 同 seed / 画面 |
|---|---|---|
| F1 | native_motion 改数据驱动（§3.5），删 id 分支与私有状态读取、帧数取槽 frames；推进之王 / 乌尔比安改填 json；`tools/probes/package_siege_ulpianus.py` 只写 clips | 推进之王 / 乌尔比安 TRACE 逐行相同；截图脚本逐帧状态记录相同 |
| F2 | check.py 登记 `logos_projectiles`、`three_operator_art`（另加 `texas_contract`） | — |
| F3 | 生命周期条目结束后移除（§3.4），skill_lifecycle_test 补回归 | 7 人 TRACE 逐行相同 |
| F4 | `random_enemy`（射程内不排序、g.rng 抽一次）替代全量排序；**单独提交**，会改维什戴尔 S2 后半段同 seed 选中的目标 | 胜率 A/B 按「平衡批跑一律云端」待协调人排云端 |
| F5 / F7 | `sprite_point_at` 统一定位点 / 炮口；乘 draw_scale；玩法点（炮口）不加绘制期的 draw_off | 维什戴尔见下 |
| F6 / V2 / V3 | 推进之王 / 乌尔比安顶层 64 / (32,60)；`fire` 改为 `fire_time` 所在帧（V7 抓出的旧值，运行时不读） | 逐行相同 |
| F8 | weapons.gd 画面随机全改 `g.vrng` | 不影响玩法随机 |
| F9 | swap_attack 禁令只查同一技能；另校验他技换上的普攻须是 circle / cone | — |

**新发现（中）**：维什戴尔 seed 1 180 秒在 **2968bf4a 本身**两次运行就不一致（99 / 100 / 150 秒处分叉，与机器负载相关），所以维什戴尔的同 seed 对照没有意义，需单独排查（候选：随渲染频率变化的状态被玩法读到）。其余干员同 seed 稳定。

**截图对照**：现有 `*_capture` 截图在同一提交上连跑三次就有每帧数万到十几万像素的差异（背景光束按真实时间动、部分特效用未播种的全局随机），像素零差无法作为验收口径。改用截图脚本逐帧写出的 evidence.json（动作 / 帧号 / 位置 / 阶段）：推进之王、乌尔比安、维什戴尔 S2 / S3、水月 S2 / S3 六组与 2968bf4a 逐字节相同。要做像素级回归，需先让截图局冻结真实时间与全局随机（建议另开一项）。
