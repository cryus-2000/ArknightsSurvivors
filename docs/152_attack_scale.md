# 152 · 攻速整条缩放：去掉动作窗口 / 出手间隔的下限（10-25）

> 用户 10-25（转 docs/140 §5）：攻速高了动作跟不上，「整个攻击条一起加速」——攻速倍率 k 时前摇、出手帧、收势、动画播放整条按 1/k 等比缩短，实际出手频率 = 面板攻速；k 超过某值后动画播放封顶，判定时间轴照样按 k 缩短。分支 `claude/atk-speed-scale`。

## 1. 盘点：出手节奏下限在哪

| 位置 | 作用 | 谁有 |
|---|---|---|
| `attack_timing.min_duration`（`character._start_action`） | 动作窗口 = max(min_duration, min(帧条标称时长, 出手间隔 × active_ratio)) → 间隔再短窗口也不低于它，窗口比间隔长时多出的攻速被动作吃掉（水月 3× 攻速时 0.36 > 0.30，能天使 0.133 > 0.117） | 20 人全有（下表 29 条帧条：普攻、技能里的普攻替换、skill_sN_attack、retrial、throw、beam） |
| `attack_timing.min_rest`（`data_operator.start_attack`） | 出手间隔不低于 动作窗口 + min_rest：直接把攻速封在 1/(0.36+0.09) ≈ 2.2 次/秒 | 水月（5 条） |
| 水月 `min_cd` 0.18（`seg_mizuki.h3_umbrella_interval`，面板「挥伞间隔」） | 挥伞间隔不低于 0.18 秒（≈ 5.5 次/秒，基础 0.9 秒时相当于 5× 攻速） | 水月 |
| 面板「挥伞间隔」显示（`seg_mizuki._h3mz_rows`） | 显示值也抬到 min_duration + min_rest | 水月 |
| `op_aspd` 属性下限 0.2（`stat_defs.gd`） | 只有下限（寒霜 / 慢速），上限没有 | 全员（不动） |

未发现别的硬下限：普攻 cd = every ÷ op_aspd × loc.interval，没有 maxf 兜底；召唤物 cd 用 max(0.05, aspd)。

| 干员 | 帧条 | 标称时长 | min_duration | min_rest |
|---|---|---|---|---|
| angelina | attack | 0.548 | 0.133 |  |
| exusiai | attack | 0.25 | 0.133 |  |
| eyjafjalla | attack | 0.499 | 0.133 |  |
| gladiia | attack | 0.667 | 0.133 |  |
| hoshiguma | attack | 0.592 | 0.133 |  |
| irene | attack | 0.417 | 0.133 |  |
| irene | attack_retrial | 0.62 | 0.2 |  |
| kaltsit | attack | 0.499 | 0.133 |  |
| lappland | attack | 0.439 | 0.133 |  |
| lappland | throw | 0.7 | 0.2 |  |
| logos | attack | 0.568 | 0.133 |  |
| lumen | attack | 0.508 | 0.133 |  |
| lumen | attack_beam | 0.508 | 0.133 |  |
| mizuki | attack | 0.72 | 0.36 | 0.09 |
| mizuki | skill | 0.72 | 0.36 | 0.09 |
| mizuki | skill_s1_attack | 0.72 | 0.36 | 0.09 |
| mizuki | skill_s2_attack | 0.72 | 0.36 | 0.09 |
| mizuki | skill_s3_attack | 0.72 | 0.36 | 0.09 |
| saria | attack | 0.65 | 0.2 |  |
| saria | skill_s3_attack | 0.65 | 0.2 |  |
| saria | move_skill_s3_attack | 0.65 | 0.2 |  |
| siege | attack | 0.639 | 0.133 |  |
| skadi | attack | 0.6 | 0.133 |  |
| skalter | attack | 0.628 | 0.133 |  |
| specter_unchained | attack | 0.908 | 0.2 |  |
| suzuran | attack | 0.72 | 0.2 |  |
| texas | attack | 0.507 | 0.133 |  |
| ulpianus | attack | 0.692 | 0.133 |  |
| wisadel | attack | 0.95 | 0.2 |  |

## 2. 改法（balance.json `atkspeed`）

- 窗口 = max(`min_window` 0.03，min(标称时长, 间隔 × active_ratio))；出手帧 = min(fire_time, 窗口 × windup_ratio)；帧号 / 逻辑窗口 / 技能接管 / 攻击阶段 / 移动攻击 / 原生动作全部按这个窗口走（本来就按 attack_dur 比例取帧），所以前摇、出手帧、收势、动画整条等比。
- `min_duration`、`min_rest` 不再参与（json 字段保留，契约校验仍要求它们合法；`atkspeed/legacy_floor` = 1 可恢复旧行为做对照）。水月 `min_cd` 0.18 → 0.05，面板间隔 = 实际间隔。
- **动画封顶**：动画倍率 k = 标称时长 ÷ 窗口 超过 `anim_k_cap`（3）后，`attack_phase_frame` 对前摇 / 收势按步长 k/3 隔帧抽取（出手帧、末帧定格不抽），只影响画面；判定时间轴不动，伤害不丢。
- 1× 攻速不变：同种子 TRACE（水月 seed 1 / 240 秒）对 origin/main da28a3e46 241 行逐行相同。

## 3. 测试与录像

- 旧测试按新口径改：`attack_rhythm`（窗口不再抬到 min_duration；k > 3 的帧映射改为「不超前、滞后不超过一个步长」）、`attack_timing`（k > 3 时 8 个姿势改为「出手帧只进入一次、至少 8÷(k/3)−1 个姿势」）。`attack_phases` / `move_attack` / core 不改直接过。
- 录像 `tools/probes/atk_rate_capture.py atk_rate mizuki 6 1,2.5,4`：水月三倍率并排，字幕标实测出手频率——1×：间隔 0.900 秒；2.5×：0.367 秒（面板 0.36）；4×：0.234 秒（面板 0.225，差一帧内的 1/60 取整）。旧版（min_duration + min_rest）4× 时间隔被抬到 0.45 秒（2.2 次/秒）。
