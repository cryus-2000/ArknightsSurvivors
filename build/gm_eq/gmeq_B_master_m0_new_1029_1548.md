# balance gmeq_B_master_m0_new 1029_1548

args: `--preset starts --bot master --seed0 1 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --trace=1 --tag gmeq_B_master_m0_new --out build/gm_eq`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 10 | 10 | 9 | 111s / 105s / 171s / 88–171s | 105s / 171s | 8.1 / 3.0 | 41% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 塑路者 | 8 | 8 | 84s | 0.40 | 8 | - | - |
| master | 接潮主教 | 7 | 6 | 65s | 0.08 | 16 | 1.5 | 6% |
| master | 接潮斥亡体 | 4 | 3 | 65s | 0.10 | 14 | - | - |
| master | 圣徒卡门 | 4 | 3 | 78s | 0.39 | 9 | - | - |
| master | 接潮蔑死体 | 3 | 3 | 71s | 0.10 | 17 | - | - |
| master | 圣徒伊比利亚 | 2 | 1 | 42s | 0.18 | 13 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 10 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 14% | 199 / 156 | 87% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:17 |
| master | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |
| master | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:01 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 114 / 180 | 114 / 185 | 1 / 7 | 301 / 421 | 30 / 46 |
| master | 0 | 10 | 8:00–10:00 | 84 / 97 | 60 / 109 | 1 / 5 | 352 / 421 | 28 / 42 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 12s / 10s（14/14） | 19 / 60 | 0 | bone/slider ×14 |
| master | 2 | 13 | 2:45 | 20 | 15s / 13s（12/13） | 27 / 95 | 2 | bone/slider/stone ×13 |
| master | 3 | 10 | 5:05 | 24 | 27s / 19s（10/10） | 7 / 42 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/slider/stone ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| master | 4 | 10 | 5:18 | 36 | 47s / 35s（10/10） | 32 / 106 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×2 |
| master | 5 | 10 | 6:15 | 40 | 41s / 31s（10/10） | 31 / 111 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×1 |
| master | 6 | 7 | 8:11 | 26 | 18s / 15s（7/7） | 8 / 21 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |
| master | 7 | 5 | 9:13 | 22 | 17s / 14s（5/5） | 7 / 17 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 7:54 / 4:17 | 0.0 / - | 8 / 16 / 23 / 21 | 51% | 66% | 82 | 1252 | 余震 34% 饱和复仇 13% 爆裂黎明 9% 殉爆 8% | 自身回复 34% 塞雷娅 26% 凯尔希 16% (534 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 50% | 7:41 / 2:31 | 0.0 / - | 8 / 14 / 20 / 17 | - | 50% | 48 | 884 | 熔岩弹 29% 炮击 14% 火星 6% 火山 5% | 自身回复 46% 补给 34% 歌蕾蒂娅 13% (771 / 0.0) | contact_tracer |
| [master] skadi | 2 | 100% | 11:52 / 11:33 | 0.0 / - | 8 / 15 / 22 / 27 | - | 100% | 98 | 1906 | 大剑 33% 迅捷打击·γ型 8% 跃浪 7% 跃浪击 5% | 自身回复 31% 流明 23% 凯尔希 22% (820 / 0.0) | contact_tracer |
| [master] mizuki | 2 | 50% | 12:28 / 11:57 | 0.0 / - | 7 / 15 / 20 / 24 | 41% | 100% | 70 | 1509 | Mon3tr 21% 锯刃 16% 伞击 11% 触手 8% | 水月 55% 自身回复 23% 塞雷娅 10% (1519 / 0.5) | contact_tracer |
| [master] saria | 2 | 100% | 11:44 / 11:39 | 0.0 / - | 6 / 14 / 20 / 26 | - | 100% | 86 | 1704 | 余震 17% 食腐 16% 言 7% 延异视阈 5% | 塞雷娅 48% 自身回复 17% 针剂回流 11% (938 / 0.0) | contact_tracer |
| [master] kaltsit | 2 | 50% | 7:16 / 2:47 | 0.0 / - | 8 / 15 / 21 / 18 | - | 50% | 66 | 1072 | Mon3tr 38% 言 7% 伞击 5% 提喻 5% | 凯尔希 41% 自身回复 32% 结构加固 12% (593 / 0.0) | contact_tracer |
| [master] suzuran | 2 | 50% | 7:14 / 3:01 | 0.0 / - | 8 / 15 / 22 / 19 | - | 66% | 70 | 1094 | 狐火 25% 炮击 15% 延异视阈 10% 锤击 8% | 自身回复 39% 铃兰 34% 补给 21% (479 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 7:54 / 4:17 | 100% | 50% | 1:08 | 0:47 / 2:29 | 1.5 / 30s | 52.9 | 71 | 0 | 0 | 2 | 74% / 33472 | contact_tracer |
| [master] eyjafjalla | 2 | 50% | 7:41 / 2:31 | 50% | 50% | 0:56 | 0:58 / 5:16 | 1.0 / 141s | 92.3 | 96 | 6 | 10 | 1 | 55% / 18403 | contact_tracer |
| [master] skadi | 2 | 100% | 11:52 / 11:33 | 100% | 100% | 1:06 | 0:49 / 3:57 | 2.5 / 59s | 93.4 | 68 | 1 | 0 | 3 | 61% / 45763 | - |
| [master] mizuki | 2 | 50% | 12:28 / 11:57 | 100% | 100% | 1:07 | 0:50 / 3:29 | 1.0 / 112s | 124.2 | 102 | 4 | 92 | 2 | 23% / 11218 | corrode |
| [master] saria | 2 | 100% | 11:44 / 11:39 | 100% | 100% | 1:25 | 0:51 / 5:10 | 3.0 / 90s | 108.4 | 78 | 0 | 0 | 4 | 6% / 4339 | - |
| [master] kaltsit | 2 | 50% | 7:16 / 2:47 | 50% | 50% | 1:07 | 0:52 / 4:34 | 1.5 / 64s | 67.2 | 98 | 0 | 14 | 2 | 46% / 8002 | corrode |
| [master] suzuran | 2 | 50% | 7:14 / 3:01 | 50% | 50% | 1:03 | 0:46 / 2:15 | 1.5 / 57s | 47.9 | 83 | 16 | 0 | 2 | 30% / 8256 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 5.0 | 0.0% | class 3/1 economy 2/0 general 7/2 heal 1/1 melee 1/0 multi 5/3 shield 2/0 summon 1/0 survival 6/2 weak 1/1 | 0 |
| master | kaltsit | 2 | 8.5 | 6.6% | class 4/1 economy 2/0 general 20/4 heal 11/7 melee 1/0 multi 1/0 shield 2/0 summon 1/0 survival 6/2 weak 4/3 | 0 |
| master | mizuki | 2 | 7.5 | 1.2% | class 1/0 economy 2/2 general 13/2 heal 1/0 melee 1/0 shield 1/1 summon 8/5 survival 7/4 weak 2/1 | 0 |
| master | saria | 2 | 9.0 | 16.6% | class 7/1 control 1/1 economy 5/0 general 13/3 heal 12/9 melee 2/1 shield 2/1 summon 3/1 survival 8/1 | 0 |
| master | skadi | 2 | 11.0 | 1.6% | class 3/0 economy 5/0 general 17/5 heal 2/1 melee 15/8 multi 4/0 shield 3/3 summon 2/2 survival 13/3 weak 2/0 | 0 |
| master | suzuran | 2 | 11.0 | 2.3% | class 7/2 control 4/3 economy 2/1 general 15/3 heal 1/0 melee 2/1 multi 3/1 shield 5/3 summon 2/0 survival 10/6 weak 4/2 | 0 |
| master | wisadel | 2 | 8.0 | 0.0% | class 6/2 economy 2/0 general 12/6 heal 2/0 multi 10/6 shield 1/0 summon 3/0 survival 6/2 weak 2/0 | 0 |
| 合计 | | | | | class 31/7 control 5/4 economy 20/3 general 97/25 heal 30/18 melee 22/10 multi 23/10 shield 16/8 summon 20/8 survival 56/20 weak 15/7 | |

拿取最多（出现 / 拿取）：穿甲弹 6/4，开裂的束缚带 5/4，食腐者手杖 3/4，赶车夫的长鞭 5/4，演出用香水 4/3，涌动之餐 3/3，血魔的银杯 3/3，特级馥郁咖啡豆 3/3，洁白的舞鞋 7/2，漆黑的舞鞋 3/2，“黑夜呢喃” 3/2，摩根队长佳酿 2/2
