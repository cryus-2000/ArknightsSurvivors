# balance bond2-ab3_texas_lappland_off 1106_1039

args: `--squad texas,lappland --bots expert,normal --seeds 8 --nocache --jobs 8 --tag bond2-ab3_texas_lappland_off --out build/cloud/bond2-ab3/texas_lappland_off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 91s / 91s / 96s / 88–96s | 91s / 96s | 35.1 / 3.0 | - |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 51s / 51s / 51s / 51–51s | 31s / 31s | 9.7 / 2.0 | - |
| normal | 偏执泡影 | standard 1 | 1 | 0 | - | - | 0.0 / 3.0 | 15% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 6 | 3 | 49s | 0.49 | 6 | - | - |
| expert | 接潮主教 | 4 | 3 | 37s | 0.20 | 7 | 1.0 | 19% |
| expert | 接潮蔑死体 | 4 | 3 | 37s | 0.22 | 8 | - | - |
| expert | 塑路者 | 3 | 3 | 50s | 0.58 | 6 | - | - |
| normal | 塑路者 | 5 | 1 | 76s | 0.63 | 9 | - | - |
| normal | 圣徒卡门 | 3 | 1 | 57s | 0.40 | 6 | - | - |
| normal | 接潮主教 | 1 | 1 | 35s | 0.18 | 7 | 1.0 | 8% |
| normal | 接潮斥亡体 | 1 | 1 | 35s | 0.16 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 11 |
| normal | 0 | 8 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 6 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 8 | 50% | 50% | 0% (0) | - |
| normal | 0 | 8 | 0% | 100% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 130 / 128 | 98% |
| normal | 0 | 8 | 0% | 145 / 131 | 88% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:35 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:33 |
| normal | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:08 |
| normal | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:28 |
| normal | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:49 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:22 |
| normal | 0 | contact_founder | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:27 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 77 / 107 | 151 / 250 | 0 / 4 | 329 / 418 | 39 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 64 / 77 | 28 / 33 | 0 / 0 | 356 / 391 | 36 / 48 |
| normal | 0 | 8 | 全程 | 74 / 109 | 72 / 240 | 0 / 2 | 296 / 439 | 35 / 48 |
| normal | 0 | 1 | 8:00–10:00 | 68 / 68 | 20 / 20 | 0 / 0 | 396 / 396 | 45 / 45 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 4 | 337 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 4 | 1300 | 0.0 | 0.5 / 0.4% | 0.5 / 0.4% | 0.0 / 0.0% | 0.0 |
| normal | 0 | 失败 | 8 | 220 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 15 | 10s / 10s（8/8） | 12 / 20 | 0 | bone/slider ×4；bone/slider/stone ×4 |
| expert | 2 | 8 | 2:45 | 20 | 8s / 8s（8/8） | 16 / 37 | 0 | bone/slider/stone ×4；bone/slider ×4 |
| expert | 3 | 5 | 4:32 | 24 | 9s / 9s（5/5） | 21 / 65 | 0 | bone/slider/stone ×3；bone/floater/runner/slider ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 4 | 5 | 5:02 | 35 | 14s / 15s（5/5） | 34 / 92 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 5 | 6:15 | 40 | 13s / 14s（5/5） | 36 / 108 | 0 | bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/reaper/runner/slider/tracer ×1 |
| expert | 6 | 4 | 7:52 | 26 | 10s / 10s（4/4） | 12 / 21 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 4 | 9:03 | 22 | 10s / 10s（4/4） | 31 / 53 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |
| normal | 1 | 8 | 1:15 | 15 | 10s / 10s（8/8） | 19 / 83 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| normal | 2 | 8 | 2:45 | 20 | 12s / 10s（8/8） | 15 / 31 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| normal | 3 | 2 | 4:45 | 24 | 8s / 8s（2/2） | 17 / 34 | 0 | bone/floater/reaper/runner/slider/tracer ×1；bone/slider/stone ×1 |
| normal | 4 | 2 | 5:00 | 34 | 13s / 13s（2/2） | 68 / 69 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| normal | 5 | 1 | 6:15 | 40 | 10s / 10s（1/1） | 18 / 18 | 0 | bone/floater/reaper/runner/slider/tracer ×1 |
| normal | 6 | 1 | 7:48 | 27 | 9s / 9s（1/1） | 0 / 0 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| normal | 7 | 1 | 8:58 | 21 | 7s / 7s（1/1） | 6 / 6 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（通关率，docs/38 §8.12） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 0% | 5:22 | 100% | 15.9 | 707 | - | **参考** |
| expert | 8 | 50% | 8:20 | 100% | 22.0 | 1335 | 50–70%（含超时） | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+lappland | 8 | 50% | 8:20 / 4:21 | 0.0 / - | 8 / 15 / 23 / 22 | 21% | 75% | 67 | 1335 | 双刃 15% 真实 11% 剑雨 8% 剑气 7% | 自身回复 51% 拾取 16% 流明 13% (795 / 0.0) | contact_tracer |
| [normal] texas+lappland | 8 | 0% | 5:22 / 3:51 | 0.0 / - | 7 / 15 / 23 / 16 | 41% | 12% | 52 | 707 | 双刃 15% 拔刀 8% 剑雨 7% 终结技·texas·斩开 7% | 自身回复 76% 拾取 13% 补给 7% (362 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+lappland | 8 | 50% | 8:20 / 4:21 | 100% | 75% | 1:07 | 0:50 / 4:03 | 1.5 / 45s | 78.4 | 103 | 6 | 0 | 2 | 25% / 12666 | boss_carmen |
| [normal] texas+lappland | 8 | 0% | 5:22 / 3:51 | 100% | 25% | 1:21 | 2:03 / 5:50 | 0.5 / 50s | 30.8 | 94 | 20 | 0 | 0 | 23% / 5495 | contact_path |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | texas | 8 | 11.8 | 12.1% | class 19/7 control 10/7 economy 33/14 general 60/25 heal 6/3 melee 41/16 multi 9/1 shield 9/7 summon 5/2 survival 31/10 weak 6/2 | 0 |
| normal | texas | 8 | 4.2 | 5.8% | class 6/0 control 4/2 economy 16/6 general 28/9 heal 4/1 melee 20/6 multi 1/0 shield 5/2 summon 6/3 survival 10/5 weak 2/0 | 0 |
| 合计 | | | | | class 25/7 control 14/9 economy 49/20 general 88/34 heal 10/4 melee 61/22 multi 10/1 shield 14/9 summon 11/5 survival 41/15 weak 8/2 | |

拿取最多（出现 / 拿取）：贵族刺剑 8/7，“多功能”发夹 6/5，皇帝的恩宠 18/4，凯旋号角 5/3，古怪的长笛 4/3，锈蚀刀片 18/3，老近卫军之锋 4/3，漆黑的舞鞋 6/3，安洁莉娜的创想 5/3，神音海螺 9/3，夜阳花 5/2，黑色郁金香 2/2
