# balance hitlift-new-m0-7 1030_1544

args: `--preset starts --bots expert --seeds 2 --seed0 7 --nocache --jobs 4 --tag hitlift-new-m0-7 --out build/bl/hitlift-new_m0 --extra=--tier=0 --tide=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 2 | 102s / 102s / 109s / 96–109s | 102s / 109s | 7.4 / 3.0 | 36% |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 64s / 64s / 69s / 60–69s | 64s / 69s | 6.8 / 2.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 0.0 / 2.0 | 16% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 10 | 9 | 45s | 0.46 | 12 | - | - |
| expert | 圣徒卡门 | 5 | 5 | 54s | 0.20 | 7 | - | - |
| expert | 接潮主教 | 3 | 2 | 26s | 0.12 | 19 | 1.0 | 13% |
| expert | 接潮蔑死体 | 3 | 2 | 26s | 0.15 | 22 | - | - |
| expert | 圣徒伊比利亚 | 2 | 0 | - | 0.12 | 26 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.1 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 14 | 28% | 64% | 7% (1) | 36% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 14% | 205 / 174 | 93% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_ishar | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:23 |
| expert | 0 | atk_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:29 |
| expert | 0 | mire | 第 3 轮 · 稳定 | 否 | 否 | 1 | 6:59 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:09 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:32 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 7:07 |
| expert | 0 | mire | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:09 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:29 |
| expert | 0 | corrode | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:51 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 106 / 181 | 77 / 199 | 2 / 7 | 340 / 438 | 43 / 48 |
| expert | 0 | 6 | 8:00–10:00 | 76 / 88 | 36 / 71 | 1 / 5 | 386 / 423 | 37 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 940 | 0.0 | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 4 | 2042 | 0.0 | 0.0 / 0.0% | 0.5 / 0.4% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 12s / 10s（14/14） | 19 / 37 | 0 | bone/slider/stone ×9；bone/slider ×5 |
| expert | 2 | 13 | 2:45 | 20 | 10s / 10s（12/13） | 34 / 132 | 2 | bone/slider ×9；bone/slider/stone ×4 |
| expert | 3 | 11 | 4:43 | 24 | 24s / 11s（10/11） | 19 / 61 | 1 | bone/slider/stone ×3；bone/floater/runner/slider ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 4 | 11 | 5:12 | 35 | 32s / 14s（10/11） | 31 / 74 | 2 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 5 | 10 | 6:19 | 40 | 30s / 22s（8/10） | 43 / 112 | 1 | bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 6 | 5 | 7:52 | 26 | 13s / 11s（5/5） | 11 / 19 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 5 | 9:02 | 21 | 12s / 12s（5/5） | 19 / 40 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 11:29 / 11:23 | 0.0 / - | 8 / 16 / 22 / 28 | 16% | 100% | 48 | 1986 | 余震 27% 真实 26% 饱和复仇 9% 爆裂黎明 8% | 凯尔希 32% 自身回复 24% 水月 12% (1121 / 0.0) | boss_ishar |
| [expert] eyjafjalla | 2 | 0% | 6:14 / 5:29 | 0.0 / - | 8 / 16 / 0 / 18 | - | 66% | 63 | 990 | 熔岩弹 24% 火山 12% 双刃 6% 火星 6% | 自身回复 39% 补给 17% 流明 15% (723 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 9:04 / 7:09 | 0.0 / - | 8 / 15 / 23 / 24 | 97% | 83% | 78 | 1527 | 大剑 27% 锯刃 11% 替身闪现 8% 跃浪 6% | 自身回复 46% 补给 21% 流明 17% (864 / 0.0) | contact_tracer |
| [expert] mizuki | 2 | 0% | 7:46 / 2:32 | 0.0 / - | 7 / 14 / 19 / 16 | 36% | 60% | 80 | 767 | 真实 49% 伞击 20% 触手 12% 光弹 6% | 水月 37% 流明 18% 自身回复 15% (1009 / 0.0) | bullet |
| [expert] saria | 2 | 50% | 9:28 / 7:07 | 0.0 / - | 7 / 14 / 21 / 23 | 89% | 83% | 42 | 1400 | 余震 23% 大剑 10% 炮击 10% 饱和复仇 7% | 塞雷娅 52% 自身回复 21% 补给 8% (1591 / 0.0) | boss_carmen |
| [expert] kaltsit | 2 | 0% | 5:19 / 3:09 | 0.0 / - | 8 / 16 / 0 / 16 | 64% | 50% | 28 | 809 | Mon3tr 31% 刺剑 15% 锯刃 10% 狐火 8% | 凯尔希 35% 自身回复 23% 结构加固 16% (672 / 0.0) | bullet |
| [expert] suzuran | 2 | 50% | 7:00 / 2:51 | 0.0 / - | 8 / 16 / 23 / 18 | - | 66% | 76 | 1170 | 狐火 33% 狐火点点 10% 延异视阈 9% 提喻 6% | 自身回复 31% 铃兰 23% 流明 16% (884 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 11:29 / 11:23 | 100% | 100% | 0:58 | 0:39 / 2:17 | 2.0 / 46s | 148.8 | 103 | 2 | 0 | 4 | 53% / 47570 | boss_ishar |
| [expert] eyjafjalla | 2 | 0% | 6:14 / 5:29 | 100% | 100% | 0:54 | 0:56 / 3:03 | 1.0 / 39s | 43.2 | 140 | 14 | 0 | 3 | 57% / 19334 | atk_tracer |
| [expert] skadi | 2 | 50% | 9:04 / 7:09 | 100% | 100% | 1:02 | 0:45 / 4:20 | 2.0 / 45s | 72.7 | 112 | 8 | 0 | 4 | 50% / 26307 | wound |
| [expert] mizuki | 2 | 0% | 7:46 / 2:32 | 50% | 50% | 1:05 | 0:47 / 4:13 | 0.5 / 93s | 89.1 | 140 | 2 | 0 | 3 | 37% / 9710 | corrode |
| [expert] saria | 2 | 50% | 9:28 / 7:07 | 100% | 100% | 1:05 | 0:47 / 4:32 | 1.5 / 105s | 143.1 | 156 | 3 | 64 | 4 | 10% / 4601 | corrode |
| [expert] kaltsit | 2 | 0% | 5:19 / 3:09 | 50% | 50% | 1:07 | 0:52 / 5:32 | 0.5 / 35s | 79.4 | 148 | 12 | 8 | 2 | 37% / 9995 | wound |
| [expert] suzuran | 2 | 50% | 7:00 / 2:51 | 50% | 50% | 0:57 | 0:58 / 2:22 | 1.5 / 23s | 123.5 | 129 | 18 | 0 | 2 | 44% / 8677 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 7.0 | 0.0% | class 3/1 control 1/1 economy 3/2 general 10/4 heal 1/1 melee 4/1 multi 7/3 shield 1/1 summon 2/0 survival 3/0 | 0 |
| expert | kaltsit | 2 | 2.5 | 3.2% | class 2/1 control 1/0 general 5/1 heal 2/1 melee 2/0 multi 1/0 shield 1/1 summon 2/1 survival 1/0 | 0 |
| expert | mizuki | 2 | 5.0 | 49.7% | class 2/0 control 1/0 economy 1/1 general 10/4 heal 3/0 multi 2/1 shield 1/0 summon 7/3 survival 3/1 weak 2/0 | 0 |
| expert | saria | 2 | 9.0 | 6.0% | class 10/5 control 1/0 economy 4/3 general 11/3 heal 9/2 melee 3/0 multi 4/1 shield 3/1 summon 2/1 survival 7/2 weak 1/0 | 0 |
| expert | skadi | 2 | 9.5 | 0.0% | class 7/2 control 1/1 economy 3/1 general 16/7 melee 8/2 multi 2/0 shield 1/1 summon 5/3 survival 2/1 weak 2/1 | 0 |
| expert | suzuran | 2 | 7.5 | 3.7% | class 6/1 control 6/3 economy 5/1 general 11/5 heal 2/0 melee 1/0 shield 3/1 survival 7/4 weak 2/0 | 0 |
| expert | wisadel | 2 | 15.0 | 26.6% | class 3/0 control 1/1 economy 9/4 general 17/9 heal 2/0 melee 3/1 multi 15/10 shield 3/0 summon 2/1 survival 10/2 weak 3/2 | 0 |
| 合计 | | | | | class 33/10 control 12/6 economy 25/12 general 80/33 heal 19/4 melee 21/4 multi 31/15 shield 13/5 summon 20/9 survival 33/10 weak 10/3 | |

拿取最多（出现 / 拿取）：穿甲弹 8/5，散轶诗简 6/4，洁白的舞鞋 4/3，损坏的左轮弹巢 5/3，显圣吊坠 7/2，老蒲扇 3/2，猎人的口粮 6/2，大教堂拼图 2/2，银餐叉 7/2，漆黑的舞鞋 4/2，“多功能”发夹 6/2，人偶之家 3/2
