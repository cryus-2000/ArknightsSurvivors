# balance bond2-ab3_texas_lappland_on 1106_1041

args: `--squad texas,lappland --bots expert,normal --seeds 8 --nocache --jobs 8 --tag bond2-ab3_texas_lappland_on --out build/cloud/bond2-ab3/texas_lappland_on --extra=--bal=link/bond_v2=1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 91s / 91s / 96s / 88–96s | 91s / 96s | 26.6 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 60s / 60s / 60s / 60–60s | 60s / 60s | 7.7 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 8 | 7 | 44s | 0.58 | 6 | - | - |
| expert | 接潮主教 | 4 | 3 | 42s | 0.15 | 7 | - | - |
| expert | 接潮蔑死体 | 2 | 2 | 35s | 0.24 | 4 | - | - |
| expert | 接潮斥亡体 | 2 | 1 | 42s | 0.10 | 8 | - | - |
| expert | 塑路者 | 1 | 1 | 50s | 0.25 | 8 | - | - |
| normal | 塑路者 | 6 | 2 | 66s | 0.62 | 10 | - | - |
| normal | 圣徒卡门 | 1 | 1 | 56s | 0.58 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 0.1 / 0.1 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 14 |
| normal | 0 | 8 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 1 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 8 | 50% | 50% | 0% (0) | - |
| normal | 0 | 8 | 0% | 100% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 97 / 90 | 100% |
| normal | 0 | 8 | 12% | 133 / 136 | 87% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:06 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:00 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:58 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:48 |
| normal | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:04 |
| normal | 0 | atk_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:04 |
| normal | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:56 |
| normal | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:19 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:13 |
| normal | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:01 |
| normal | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 75 / 101 | 152 / 281 | 0 / 4 | 326 / 419 | 36 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 72 / 82 | 28 / 34 | 0 / 0 | 372 / 404 | 32 / 45 |
| normal | 0 | 8 | 全程 | 72 / 104 | 41 / 60 | 0 / 0 | 285 / 409 | 32 / 43 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 4 | 133 | 0.0 | 3.2 / 0.5% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 4 | 1642 | 0.0 | 0.0 / 0.0% | 0.2 / 0.1% | 0.0 / 0.0% | 0.0 |
| normal | 0 | 失败 | 8 | 82 | 0.0 | 0.1 / 0.2% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 15 | 10s / 10s（8/8） | 15 / 30 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| expert | 2 | 8 | 2:45 | 20 | 8s / 8s（8/8） | 11 / 31 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| expert | 3 | 7 | 4:33 | 24 | 9s / 9s（7/7） | 40 / 115 | 2 | bone/slider/stone ×3；bone/reaper/runner/slider/tracer ×1；bone/floater/runner/slider ×1 |
| expert | 4 | 6 | 5:06 | 35 | 13s / 12s（5/6） | 29 / 91 | 1 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 5 | 5 | 6:15 | 39 | 11s / 11s（5/5） | 44 / 98 | 0 | bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 6 | 4 | 7:56 | 27 | 10s / 10s（4/4） | 42 / 99 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 4 | 9:06 | 22 | 11s / 10s（4/4） | 25 / 39 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4 |
| normal | 1 | 8 | 1:15 | 15 | 11s / 11s（8/8） | 19 / 42 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| normal | 2 | 8 | 2:45 | 20 | 9s / 9s（7/8） | 14 / 52 | 1 | bone/slider/stone ×5；bone/slider ×3 |
| normal | 3 | 3 | 4:40 | 25 | 10s / 10s（3/3） | 72 / 102 | 1 | bone/slider/stone ×1；bone/offspring/slider/stone ×1；bone/reaper/runner/slider/tracer ×1 |
| normal | 4 | 3 | 5:00 | 35 | -（0/3） | 96 / 122 | 3 | bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（通关率，docs/38 §8.12） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 0% | 4:18 | 87% | 13.5 | 523 | - | **参考** |
| expert | 8 | 50% | 8:25 | 100% | 22.5 | 1347 | 50–70%（含超时） | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+lappland | 8 | 50% | 8:25 / 4:48 | 0.0 / - | 8 / 16 / 24 / 22 | 48% | 79% | 68 | 1347 | 双刃 12% 剑气 7% 剑雨 7% 次元斩 6% | 自身回复 58% 补给 15% 拾取 14% (881 / 0.0) | contact_tracer |
| [normal] texas+lappland | 8 | 0% | 4:18 / 2:47 | 0.0 / - | 7 / 15 / 0 / 14 | 50% | 0% | 44 | 523 | 双刃 24% 拔刀 10% 剑雨 8% 骤雨 6% | 自身回复 72% 补给 9% 拾取 8% (263 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+lappland | 8 | 50% | 8:25 / 4:48 | 100% | 75% | 1:07 | 0:48 / 2:45 | 1.8 / 48s | 77.4 | 107 | 2 | 0 | 2 | 24% / 12582 | boss_carmen |
| [normal] texas+lappland | 8 | 0% | 4:18 / 2:47 | 87% | 37% | 1:07 | 2:02 / - | 0.4 / 62s | 17.2 | 92 | 10 | 0 | 0 | 26% / 4195 | atk_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | texas | 8 | 11.1 | 2.9% | class 32/21 control 10/3 economy 34/12 general 61/24 heal 7/3 melee 42/6 multi 3/0 shield 10/3 summon 15/7 survival 29/9 weak 3/1 | 0 |
| normal | texas | 8 | 3.2 | 1.9% | class 6/2 control 3/1 economy 11/3 general 15/8 heal 2/1 melee 17/5 multi 2/0 shield 2/1 summon 1/1 survival 6/3 weak 2/1 | 0 |
| 合计 | | | | | class 38/23 control 13/4 economy 45/15 general 76/32 heal 9/4 melee 59/11 multi 5/0 shield 12/4 summon 16/8 survival 35/12 weak 5/2 | |

拿取最多（出现 / 拿取）：锈蚀刀片 18/5，积攒之手 7/4，钝爪-突破 3/3，古怪的长笛 5/3，微缩舞台模型 3/3，贵族刺剑 6/2，赤金的远征 3/2，便携经书 2/2，漆黑的舞鞋 10/2，四叶草化石 2/2，折戟-浴血 4/2，摩根队长佳酿 6/2
