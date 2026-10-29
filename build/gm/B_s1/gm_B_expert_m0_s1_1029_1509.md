# balance gm_B_expert_m0_s1 1029_1509

args: `--preset starts --bot expert --seed0 1 --seeds 4 --jobs 4 --extra --tier=0 --tide=0 --tag gm_B_expert_m0_s1 --out build/gm/B_s1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 11 | 11 | 6 | 116s / 106s / 159s / 87–159s | 106s / 159s | 5.3 / 3.0 | 26% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 69s / 69s / 69s / 69–69s | 49s / 49s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 13 | 11 | 93s | 0.26 | 7 | - | - |
| expert | 圣徒卡门 | 10 | 6 | 71s | 0.29 | 6 | - | - |
| expert | 接潮主教 | 10 | 6 | 75s | 0.07 | 14 | 1.4 | 9% |
| expert | 接潮斥亡体 | 6 | 3 | 80s | 0.10 | 13 | - | - |
| expert | 接潮蔑死体 | 4 | 3 | 70s | 0.08 | 14 | - | - |
| expert | 圣徒伊比利亚 | 3 | 2 | 147s | 0.08 | 15 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 21% | 266 / 263 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 2 | 3:39 |
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 2 | 2:57 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 6:11 |
| expert | 0 | mire | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:18 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:34 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:39 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:00 |
| expert | 0 | shock_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | boss_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:40 |
| expert | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:38 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:21 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:34 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:48 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 89 / 220 | 89 / 199 | 2 / 7 | 278 / 406 | 26 / 48 |
| expert | 0 | 12 | 8:00–10:00 | 75 / 108 | 65 / 110 | 0 / 5 | 321 / 406 | 26 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 12s / 11s（28/28） | 23 / 133 | 1 | bone/slider ×19；bone/slider/stone ×9 |
| expert | 2 | 24 | 2:45 | 20 | 12s / 10s（24/24） | 35 / 145 | 2 | bone/slider/stone ×16；bone/slider ×8 |
| expert | 3 | 15 | 5:02 | 25 | 24s / 11s（12/15） | 14 / 96 | 3 | bone/reaper/runner/slider/tracer ×4；bone/floater/runner/slider ×4；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 4 | 14 | 5:18 | 36 | 24s / 15s（12/14） | 51 / 110 | 2 | bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×4 |
| expert | 5 | 13 | 6:15 | 40 | 24s / 18s（10/13） | 50 / 134 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 6 | 8:24 | 27 | 13s / 13s（6/6） | 33 / 90 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 2 | 9:05 | 21 | 8s / 8s（2/2） | 18 / 25 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 8:39 / 3:39 | 0.0 / - | 8 / 16 / 22 / 22 | 52% | 75% | 44 | 1248 | 余震 37% 饱和复仇 13% 爆裂黎明 8% 殉爆 7% | 自身回复 26% 凯尔希 25% 流明 12% (1215 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 4 | 0% | 5:47 / 2:39 | 0.0 / - | 8 / 14 / 20 / 15 | 17% | 50% | 81 | 637 | 熔岩弹 35% 火星 9% 火山 8% 点燃 5% | 自身回复 35% 拾取 18% 流明 14% (678 / 0.0) | contact_tracer |
| [expert] skadi | 4 | 50% | 7:43 / 3:39 | 0.0 / - | 8 / 15 / 22 / 20 | 88% | 58% | 80 | 1109 | 大剑 24% 言 11% 跃浪 7% Mon3tr 6% | 自身回复 39% 流明 25% 补给 10% (1055 / 0.0) | contact_tracer |
| [expert] mizuki | 4 | 50% | 10:24 / 5:09 | 0.0 / - | 6 / 14 / 20 / 23 | 46% | 75% | 74 | 1253 | 真实 24% 伞击 9% 提喻 8% 言 7% | 水月 54% 自身回复 21% 流明 6% (1529 / 0.0) | boss_carmen |
| [expert] saria | 4 | 25% | 10:19 / 2:40 | 0.0 / - | 7 / 14 / 20 / 22 | 33% | 75% | 84 | 1230 | 余震 19% 言 9% 拳击 8% 爆裂黎明 5% | 塞雷娅 50% 自身回复 18% 流明 15% (1226 / 0.0) | contact_tracer |
| [expert] kaltsit | 4 | 0% | 4:01 / 1:34 | 0.0 / - | 7 / 14 / 0 / 12 | - | 18% | 8 | 460 | Mon3tr 42% 炮击 11% 刺剑 7% Mon3tr · 真伤 6% | 凯尔希 41% 自身回复 24% 结构加固 12% (551 / 0.0) | contact_tracer |
| [expert] suzuran | 4 | 25% | 7:26 / 2:59 | 0.0 / - | 8 / 15 / 22 / 19 | 38% | 58% | 42 | 1080 | 真实 24% 狐火 24% 双刃 8% 余震 7% | 自身回复 24% 塞雷娅 23% 拾取 16% (988 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 8:39 / 3:39 | 100% | 75% | 1:06 | 0:45 / 2:38 | 1.5 / 82s | 109.0 | 138 | 8 | 5 | 3 | 73% / 34436 | mire |
| [expert] eyjafjalla | 4 | 0% | 5:47 / 2:39 | 50% | 25% | 1:08 | 0:49 / 3:06 | 0.5 / 88s | 77.4 | 132 | 9 | 0 | 1 | 68% / 14588 | corrode |
| [expert] skadi | 4 | 50% | 7:43 / 3:39 | 100% | 50% | 1:06 | 0:47 / 2:42 | 1.2 / 73s | 100.8 | 138 | 22 | 0 | 2 | 47% / 17057 | contact_tracer |
| [expert] mizuki | 4 | 50% | 10:24 / 5:09 | 100% | 100% | 1:05 | 0:47 / 2:21 | 1.5 / 99s | 150.4 | 147 | 9 | 29 | 4 | 18% / 9924 | shock_paranoia |
| [expert] saria | 4 | 25% | 10:19 / 2:40 | 75% | 75% | 1:23 | 0:50 / 2:50 | 1.5 / 106s | 142.9 | 120 | 4 | 0 | 3 | 14% / 4116 | boss_paranoia |
| [expert] kaltsit | 4 | 0% | 4:01 / 1:34 | 50% | 50% | 1:14 | 0:56 / 3:12 | 0.5 / 129s | 42.6 | 160 | 10 | 8 | 2 | 56% / 7900 | corrode |
| [expert] suzuran | 4 | 25% | 7:26 / 2:59 | 75% | 75% | 0:59 | 0:51 / 3:28 | 1.0 / 55s | 101.0 | 131 | 12 | 11 | 4 | 29% / 8946 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 2.8 | 0.5% | class 2/0 economy 3/1 general 6/4 heal 3/0 melee 1/1 multi 6/3 shield 4/2 survival 5/0 weak 1/0 | 0 |
| expert | kaltsit | 4 | 3.0 | 1.2% | class 2/1 economy 2/0 general 13/6 heal 7/2 melee 1/1 multi 1/0 shield 1/1 survival 3/1 weak 1/0 | 0 |
| expert | mizuki | 4 | 7.5 | 24.9% | class 7/4 control 5/4 economy 5/1 general 24/9 heal 3/1 melee 4/2 multi 2/0 shield 2/1 summon 14/4 survival 10/4 weak 3/0 | 0 |
| expert | saria | 4 | 9.0 | 5.5% | class 6/3 control 2/0 economy 10/3 general 22/7 heal 23/8 melee 7/4 multi 3/1 shield 6/4 summon 1/0 survival 18/5 weak 4/1 | 0 |
| expert | skadi | 4 | 8.5 | 0.0% | class 9/2 control 2/1 economy 5/1 general 24/10 heal 4/2 melee 17/8 multi 7/2 shield 3/1 summon 1/1 survival 16/4 weak 4/2 | 0 |
| expert | suzuran | 4 | 8.2 | 28.9% | class 7/1 control 8/5 economy 7/5 general 28/12 heal 1/1 melee 3/1 shield 2/1 summon 3/1 survival 12/6 weak 1/0 | 0 |
| expert | wisadel | 4 | 10.0 | 3.7% | class 11/4 control 2/1 economy 12/3 general 29/12 heal 2/1 melee 5/1 multi 21/5 shield 4/2 summon 8/3 survival 16/7 weak 2/1 | 0 |
| 合计 | | | | | class 44/15 control 19/11 economy 44/14 general 146/60 heal 43/15 melee 38/18 multi 40/11 shield 22/12 summon 27/9 survival 80/27 weak 16/4 | |

拿取最多（出现 / 拿取）：特级馥郁咖啡豆 9/6，赶车夫的长鞭 8/5，贵族刺剑 7/5，银餐叉 12/4，猎人的口粮 8/4，漆黑的舞鞋 8/4，“小格兰法洛” 8/4，凯旋号角 8/4，乌萨斯毡毯 5/4，洁白的舞鞋 8/3，生命之水 4/3，血魔的银杯 5/3
