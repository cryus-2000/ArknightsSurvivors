# balance gm_B_master_m0_s5 1029_1534

args: `--preset starts --bot master --seed0 5 --seeds 4 --jobs 4 --extra --tier=0 --tide=0 --tag gm_B_master_m0_s5 --out build/gm/B_s5`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 17 | 17 | 9 | 130s / 128s / 171s / 92–171s | 128s / 171s | 3.0 / 2.7 | 39% |
| master | 最后的骑士 | knight 6 | 6 | 6 | 99s / 91s / 137s / 67–137s | 91s / 137s | 3.2 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 圣徒卡门 | 19 | 14 | 76s | 0.14 | 9 | - | - |
| master | 接潮主教 | 16 | 9 | 73s | 0.05 | 14 | 1.6 | 14% |
| master | 塑路者 | 14 | 14 | 65s | 0.29 | 9 | - | - |
| master | 接潮蔑死体 | 10 | 6 | 61s | 0.08 | 15 | - | - |
| master | 接潮斥亡体 | 6 | 4 | 144s | 0.08 | 13 | - | - |
| master | 圣徒伊比利亚 | 2 | 0 | - | 0.03 | 24 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 28 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 16 | 0.0 / 0.0 / 0.0 / 0 | 18 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 28 | 3% | 176 / 182 | 89% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 3 | 13:00 |
| master | 0 | shock_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:59 |
| master | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:26 |
| master | 0 | mire | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:03 |
| master | 0 | dark | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:52 |
| master | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 7:48 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 28 | 全程 | 101 / 165 | 121 / 176 | 2 / 8 | 337 / 434 | 29 / 48 |
| master | 0 | 24 | 8:00–10:00 | 78 / 111 | 66 / 118 | 1 / 5 | 343 / 413 | 24 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 28 | 1:15 | 15 | 15s / 13s（28/28） | 14 / 80 | 0 | bone/slider/stone ×22；bone/slider ×6 |
| master | 2 | 28 | 2:45 | 20 | 12s / 11s（28/28） | 34 / 166 | 2 | bone/slider ×22；bone/slider/stone ×6 |
| master | 3 | 18 | 4:52 | 24 | 18s / 12s（18/18） | 8 / 23 | 0 | bone/floater/runner/slider ×7；bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| master | 4 | 18 | 5:11 | 36 | 28s / 24s（18/18） | 12 / 41 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×5 |
| master | 5 | 18 | 6:15 | 40 | 29s / 22s（18/18） | 22 / 83 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×4 |
| master | 6 | 12 | 8:25 | 26 | 17s / 16s（12/12） | 32 / 124 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| master | 7 | 6 | 9:13 | 22 | 21s / 14s（6/6） | 26 / 46 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 4 | 50% | 12:15 / 11:30 | 0.0 / - | 8 / 15 / 22 / 26 | 29% | 91% | 67 | 1740 | 余震 38% 饱和复仇 10% 爆裂黎明 10% 殉爆 8% | 自身回复 25% 塞雷娅 24% 凯尔希 11% (833 / 0.0) | contact_tracer |
| [master] eyjafjalla | 4 | 0% | 5:52 / 2:59 | 0.0 / - | 8 / 14 / 18 / 14 | 43% | 50% | 66 | 581 | 熔岩弹 32% 火山 9% 火星 9% 狐火 6% | 自身回复 36% 流明 29% 拾取 15% (582 / 0.0) | contact_tracer |
| [master] skadi | 4 | 75% | 10:43 / 8:52 | 0.0 / - | 8 / 16 / 22 / 27 | - | 100% | 64 | 1799 | 大剑 24% 余震 6% 潮刃 5% Mon3tr 4% | 自身回复 40% 凯尔希 20% 补给 18% (658 / 0.2) | bullet |
| [master] mizuki | 4 | 75% | 12:32 / 12:08 | 0.0 / - | 7 / 15 / 20 / 25 | 31% | 100% | 69 | 1521 | 真实 24% Mon3tr 9% 延异视阈 9% 伞击 8% | 水月 58% 自身回复 22% 凯尔希 9% (1261 / 0.8) | contact_tracer |
| [master] saria | 4 | 50% | 12:30 / 11:54 | 0.0 / - | 7 / 14 / 20 / 25 | 40% | 100% | 67 | 1492 | 余震 16% 震地 6% 饱和复仇 6% 拳击 5% | 塞雷娅 59% 自身回复 20% 针剂回流 10% (1238 / 0.0) | contact_tracer |
| [master] kaltsit | 4 | 50% | 11:24 / 7:48 | 0.0 / - | 7 / 14 / 19 / 23 | 76% | 83% | 72 | 1283 | Mon3tr 22% Mon3tr · 真伤 7% 余震 6% 刺剑 4% | 凯尔希 32% 自身回复 24% 塞雷娅 14% (1143 / 0.0) | contact_tracer |
| [master] suzuran | 4 | 75% | 12:22 / 11:56 | 0.0 / - | 8 / 14 / 21 / 26 | 30% | 100% | 82 | 1688 | 真实 24% 余震 17% 狐火 13% Mon3tr 8% | 自身回复 25% 铃兰 17% 凯尔希 15% (1119 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 4 | 50% | 12:15 / 11:30 | 100% | 100% | 1:08 | 0:45 / 2:34 | 2.5 / 86s | 108.0 | 66 | 3 | 0 | 3 | 70% / 47897 | shock_paranoia |
| [master] eyjafjalla | 4 | 0% | 5:52 / 2:59 | 50% | 25% | 1:02 | 0:48 / 3:16 | 0.2 / 371s | 33.5 | 114 | 8 | 1 | 2 | 68% / 11446 | shock_paranoia |
| [master] skadi | 4 | 75% | 10:43 / 8:52 | 100% | 100% | 1:03 | 0:47 / 3:33 | 2.5 / 54s | 81.8 | 62 | 7 | 7 | 4 | 41% / 32219 | dark |
| [master] mizuki | 4 | 75% | 12:32 / 12:08 | 100% | 100% | 1:04 | 0:54 / 4:24 | 1.2 / 103s | 139.2 | 88 | 0 | 50 | 3 | 16% / 10749 | corrode |
| [master] saria | 4 | 50% | 12:30 / 11:54 | 100% | 100% | 1:30 | 1:02 / 3:34 | 1.8 / 132s | 138.1 | 90 | 2 | 30 | 3 | 10% / 4978 | shock_paranoia |
| [master] kaltsit | 4 | 50% | 11:24 / 7:48 | 100% | 100% | 1:10 | 0:56 / 4:03 | 1.8 / 134s | 129.8 | 97 | 18 | 43 | 2 | 36% / 13580 | corrode |
| [master] suzuran | 4 | 75% | 12:22 / 11:56 | 100% | 100% | 0:57 | 0:41 / 2:55 | 1.8 / 65s | 114.8 | 87 | 5 | 18 | 3 | 17% / 11952 | shock_paranoia |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 4 | 1.2 | 0.0% | economy 1/0 general 3/0 heal 1/0 multi 5/2 shield 2/1 summon 4/1 survival 5/1 weak 1/0 | 0 |
| master | kaltsit | 4 | 7.8 | 0.0% | class 8/0 control 1/1 economy 9/1 general 27/8 heal 16/10 melee 2/0 multi 3/1 shield 5/4 summon 2/0 survival 16/2 weak 5/4 | 0 |
| master | mizuki | 4 | 8.2 | 26.2% | class 6/0 control 2/1 economy 9/2 general 27/8 melee 3/0 multi 7/2 shield 7/3 summon 15/8 survival 18/7 weak 6/2 | 0 |
| master | saria | 4 | 7.2 | 3.3% | class 8/0 control 1/0 economy 4/0 general 36/11 heal 14/8 melee 3/1 multi 1/0 shield 6/2 summon 3/1 survival 8/4 weak 6/2 | 0 |
| master | skadi | 4 | 10.5 | 0.7% | class 13/3 control 2/2 economy 13/2 general 27/10 heal 6/3 melee 13/7 multi 4/1 shield 6/5 summon 2/1 survival 18/6 weak 4/2 | 0 |
| master | suzuran | 4 | 10.5 | 24.8% | class 12/4 control 14/7 economy 7/1 general 41/10 heal 2/2 melee 6/3 multi 4/2 shield 5/2 summon 4/4 survival 14/6 weak 2/1 | 0 |
| master | wisadel | 4 | 11.2 | 0.6% | class 15/1 control 3/2 economy 6/3 general 19/9 heal 4/2 melee 5/0 multi 22/12 shield 7/7 summon 9/5 survival 23/3 weak 4/1 | 0 |
| 合计 | | | | | class 62/8 control 23/13 economy 49/9 general 180/56 heal 43/25 melee 32/11 multi 46/20 shield 38/24 summon 39/20 survival 102/29 weak 28/12 | |

拿取最多（出现 / 拿取）：药枚 11/9，穿甲弹 11/6，海潮的气息 0/6，《旧高卢地名源流考》 9/5，活玫瑰 14/5，凯旋号角 7/5，猎人的口粮 8/4，银餐叉 7/4，镶金骨骰 5/4，演出用香水 5/4，安洁莉娜的创想 5/4，特级馥郁咖啡豆 6/4
