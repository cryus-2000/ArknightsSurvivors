# balance corehit-m0-on 1029_0747

args: `--preset starts --bots expert --seeds 4 --seed0 1 --jobs 4 --tag corehit-m0-on --extra=--meta=0 --out build/cloud/corehit-m0-on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 6 | 104s / 105s / 123s / 88–123s | 106s / 123s | 10.0 / 2.9 | 43% |
| expert | 伊祖米克 | resolve 2 | 2 | 2 | 151s / 151s / 169s / 134–169s | 132s / 149s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 159s / 159s / 159s / 159–159s | 159s / 159s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 19 | 17 | 55s | 0.67 | 3 | - | - |
| expert | 圣徒卡门 | 11 | 11 | 50s | 0.76 | 1 | - | - |
| expert | 接潮主教 | 7 | 6 | 36s | 0.15 | 6 | 1.0 | 12% |
| expert | 圣徒伊比利亚 | 5 | 3 | 48s | 0.34 | 5 | - | - |
| expert | 接潮斥亡体 | 4 | 4 | 34s | 0.15 | 6 | - | - |
| expert | 接潮蔑死体 | 3 | 2 | 52s | 0.20 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 7% | 227 / 222 | 83% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 2 | 3:45 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:54 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:45 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:38 |
| expert | 0 | mire | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:28 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:44 |
| expert | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:00 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 2:05 |
| expert | 0 | corrode | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:51 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:23 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:32 |
| expert | 0 | bullet | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | zone | 第 2 轮 · 稳定 | 是 | 是 | 1 | 7:07 |
| expert | 0 | mire | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:01 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:04 |
| expert | 0 | contact_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:47 |
| expert | 0 | zone | 第 4 轮 · 稳定 | 是 | 否 | 1 | 9:14 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 94 / 158 | 82 / 153 | 2 / 9 | 297 / 437 | 29 / 48 |
| expert | 0 | 14 | 8:00–10:00 | 75 / 98 | 39 / 60 | 1 / 6 | 327 / 405 | 26 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 11s / 10s（28/28） | 20 / 95 | 0 | bone/slider ×21；bone/slider/stone ×7 |
| expert | 2 | 27 | 2:45 | 20 | 12s / 11s（26/27） | 39 / 167 | 1 | bone/slider/stone ×21；bone/slider ×6 |
| expert | 3 | 24 | 4:32 | 24 | 14s / 10s（24/24） | 22 / 115 | 1 | bone/slider/stone ×6；bone/floater/runner/slider ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 4 | 23 | 5:05 | 35 | 25s / 17s（21/23） | 29 / 77 | 2 | bone/reaper/runner/slider/tracer ×11；bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 5 | 18 | 6:15 | 40 | 25s / 16s（17/18） | 44 / 144 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×6；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 6 | 12 | 8:06 | 26 | 26s / 14s（12/12） | 40 / 118 | 1 | bone/founder/nest/offspring/runner/slider/stone/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 7 | 9:00 | 22 | 14s / 12s（6/7） | 24 / 50 | 1 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 0% | 5:56 / 2:54 | 0.0 / - | 8 / 15 / 21 / 17 | - | 41% | 25 | 853 | 余震 35% 饱和复仇 17% 炮击 8% 殉爆 7% | 自身回复 31% 补给 16% 凯尔希 16% (455 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 4 | 25% | 6:09 / 2:05 | 0.0 / - | 8 / 14 / 19 / 15 | - | 41% | 53 | 692 | 熔岩弹 32% 火星 8% 狐火 7% 火山 6% | 自身回复 32% 拾取 19% 流明 14% (768 / 0.0) | contact_tracer |
| [expert] skadi | 4 | 75% | 11:19 / 9:51 | 0.0 / - | 8 / 16 / 22 / 27 | - | 100% | 75 | 1717 | 大剑 19% 延异视阈 7% 言 6% 余震 6% | 自身回复 48% 拾取 14% 补给 11% (1167 / 0.2) | contact_tracer |
| [expert] mizuki | 4 | 0% | 9:28 / 5:32 | 0.0 / - | 8 / 14 / 20 / 19 | 43% | 66% | 50 | 921 | 伞击 13% 锯刃 11% 触手 10% 余震 5% | 水月 53% 自身回复 20% 拾取 7% (1050 / 0.0) | contact_tracer |
| [expert] saria | 4 | 75% | 10:37 / 7:07 | 0.0 / - | 8 / 14 / 21 / 25 | 100% | 91% | 72 | 1540 | 余震 12% 锯刃 10% 延异视阈 9% 提喻 7% | 塞雷娅 61% 自身回复 26% 强心针 5% (951 / 0.0) | atk_tracer |
| [expert] kaltsit | 4 | 25% | 7:10 / 3:58 | 0.0 / - | 8 / 14 / 19 / 17 | 79% | 66% | 36 | 834 | Mon3tr 24% Mon3tr · 真伤 8% 锯刃 8% 狐火 6% | 凯尔希 37% 自身回复 23% 结构加固 17% (967 / 0.0) | contact_tracer |
| [expert] suzuran | 4 | 25% | 7:35 / 3:32 | 0.0 / - | 8 / 15 / 22 / 20 | 62% | 66% | 43 | 1194 | 狐火 30% 大剑 9% 锯刃 9% 余震 6% | 自身回复 26% 塞雷娅 23% 铃兰 15% (834 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 0% | 5:56 / 2:54 | 75% | 75% | 1:06 | 0:45 / 2:42 | 1.0 / 53s | 33.4 | 93 | 6 | 4 | 2 | 72% / 23568 | mire |
| [expert] eyjafjalla | 4 | 25% | 6:09 / 2:05 | 75% | 50% | 1:08 | 0:49 / 3:53 | 1.2 / 67s | 52.7 | 142 | 11 | 0 | 3 | 61% / 15530 | atk_tracer |
| [expert] skadi | 4 | 75% | 11:19 / 9:51 | 100% | 100% | 1:06 | 0:47 / 3:24 | 2.2 / 47s | 109.8 | 98 | 20 | 23 | 4 | 35% / 24452 | corrode |
| [expert] mizuki | 4 | 0% | 9:28 / 5:32 | 100% | 100% | 1:10 | 0:47 / 3:26 | 1.5 / 102s | 77.0 | 126 | 1 | 1 | 3 | 28% / 7920 | corrode |
| [expert] saria | 4 | 75% | 10:37 / 7:07 | 100% | 100% | 1:13 | 0:50 / 3:19 | 2.0 / 53s | 117.6 | 90 | 5 | 25 | 4 | 7% / 4388 | zone |
| [expert] kaltsit | 4 | 25% | 7:10 / 3:58 | 100% | 75% | 1:06 | 0:53 / 3:00 | 1.0 / 96s | 57.7 | 144 | 14 | 24 | 4 | 36% / 9584 | mire |
| [expert] suzuran | 4 | 25% | 7:35 / 3:32 | 100% | 75% | 1:01 | 0:50 / 3:54 | 1.8 / 32s | 111.1 | 127 | 18 | 3 | 4 | 30% / 9556 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 4.8 | 0.1% | class 11/3 control 1/0 economy 8/1 general 8/6 heal 5/0 melee 1/1 multi 7/3 shield 3/3 summon 2/0 survival 7/2 weak 1/0 | 0 |
| expert | kaltsit | 4 | 5.0 | 1.6% | class 5/1 economy 2/0 general 17/7 heal 14/5 melee 6/1 multi 1/0 shield 2/2 summon 4/2 survival 5/2 weak 2/0 | 0 |
| expert | mizuki | 4 | 5.0 | 2.5% | class 7/1 economy 9/3 general 19/5 heal 3/1 melee 2/2 multi 4/2 shield 3/0 summon 13/4 survival 9/2 weak 1/0 | 0 |
| expert | saria | 4 | 12.0 | 6.0% | class 20/6 economy 11/2 general 38/16 heal 18/6 melee 5/0 multi 3/0 shield 6/5 summon 5/3 survival 22/6 weak 6/4 | 0 |
| expert | skadi | 4 | 17.0 | 0.6% | class 18/8 control 2/2 economy 16/8 general 50/18 heal 10/3 melee 27/7 multi 4/2 shield 9/6 summon 7/2 survival 32/9 weak 7/3 | 0 |
| expert | suzuran | 4 | 10.8 | 4.4% | class 11/5 control 15/8 economy 6/3 general 33/14 heal 4/0 melee 6/1 multi 3/0 shield 6/4 summon 6/2 survival 17/6 weak 1/0 | 0 |
| expert | wisadel | 4 | 6.5 | 0.2% | class 5/0 control 1/0 economy 9/5 general 17/9 heal 5/2 melee 2/0 multi 6/4 shield 2/1 summon 5/3 survival 11/1 weak 1/1 | 0 |
| 合计 | | | | | class 77/24 control 19/10 economy 61/22 general 182/75 heal 59/17 melee 49/12 multi 28/11 shield 31/21 summon 42/16 survival 103/28 weak 19/8 | |

拿取最多（出现 / 拿取）：《旧高卢地名源流考》 10/8，药枚 7/6，散轶诗简 14/5，损坏的左轮弹巢 5/4，凯旋号角 10/4，古旧的蒸汽甲胄 4/4，血魔的银杯 11/4，显圣吊坠 7/3，“多功能”发夹 5/3，演出用香水 6/3，大教堂拼图 5/3，食腐者手杖 6/3
