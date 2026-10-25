# 159 · 突击模式队友低频自冲刺（10-26）

> 用户 10-26：「干员在突击模式下可以自己冲刺，像德克萨斯这种靠冲刺打伤害的可以加上低频的冲刺」。前提不变：平时（随行）队友不自己冲，只在队长冲刺时跟随（docs/151 §3 `command/dash_follow`）；指挥圆盘的突击冲锋属于指令（docs/114 §14）。分支 `claude/assault-dash`。

## 1. 规则

| 谁 | 何时冲 | 频率 | 怎么冲 |
|---|---|---|---|
| 突击中的其他队友（`command.roam` 缺省 true，倒地除外） | 突击状态下到点、突击目标离自己 ≥ 60 + 目标半径、路没被挡 | 每 `command/roam_dash_cd` 7 秒（起手按编队序号错开 ×0.6–1.0；干员 `def.command.roam_dash_cd` 可覆盖）；条件不满足 1 秒后重试 | 复用「第一下冲锋」`begin_rush`：朝突击目标冲一段（≤ `rush_dist` 260，速度 780），撞怪 / 冲到位把身边怪推开，冲刺中短暂无敌 |
| 德克萨斯（天赋 `on_dash_end` 靠冲刺回技力，`def.command.roam_dash = false` 关掉通用冲刺） | 突击状态下到点、320 内有敌人 | 每 4.5 秒（`base.roam_dash_cd`），贴身也冲（`roam_min_d` 0） | 自己 json 里 `cond: roaming` 的 `dash_line`（`tick` 块，加在 trait 末尾）：朝最近敌人冲 `dash_len` 140，带伤害（`dash_mult`），来源「突进」，吃天赋回技力 |
| 随行 / 归队中的队友 | 不冲 | — | — |

冲刺不改变队长位置，冲完照常走突击接敌 / 归队。`balance.json command/roam_dash` 0 = 全关；`roam_dash_cd` 可调。新条件 `cond: roaming`（`character.is_roaming`：非队长、指挥 = 突击、可出击、没倒地）可供其他干员 json 复用。

## 2. 验证

- 回归 `assault_dash`（`game/tests/assault_dash_test.gd`，真实对局：skadi 队长 + 德克萨斯 + 拉普兰德）：随行 12 秒 0 次、突击 20 秒德克萨斯 4 次 / 拉普兰德 2 次（切突击那一下 + 到点自冲刺，计时重置为约 7 秒）、切回随行 14 秒 0 次。
- `texas_contract` / `command_ai` / `command_wheel` / core 通过；非突击局同种子 TRACE（水月 / 德克萨斯 seed 1 / 240 秒）对 df7bbadc6 241 行逐行相同。
- 录像 `tools/probes/assault_dash_capture.py assault_dash 14`：德克萨斯随行 2 秒后切突击，6.5 / 11.0 秒各自冲一次（4.5 秒节奏）。
