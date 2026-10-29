# balance gm_B_master_m0_s1b 1029_1533

args: `--preset starts --bot master --seed0 3 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --tag gm_B_master_m0_s1b --out build/gm/B_s1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 5 | 5 | 1 | 89s / 89s / 89s / 89–89s | 89s / 89s | 7.0 / 3.0 | 17% |
| master | 最后的骑士 | knight 3 | 3 | 2 | 127s / 127s / 177s / 78–177s | 128s / 177s | 1.9 / 2.0 | 17% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 塑路者 | 8 | 7 | 86s | 0.41 | 9 | - | - |
| master | 圣徒卡门 | 6 | 4 | 110s | 0.08 | 10 | - | - |
| master | 接潮主教 | 5 | 2 | 64s | 0.05 | 17 | 1.0 | 2% |
| master | 接潮蔑死体 | 4 | 2 | 64s | 0.07 | 16 | - | - |
| master | 圣徒伊比利亚 | 2 | 0 | - | 0.07 | 14 | - | - |
| master | 接潮斥亡体 | 1 | 0 | - | 0.06 | 14 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 17 | 0.0 / 0.0 / 0.0 / 0 | 19 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 0% | 149 / 125 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 2 | 10:17 |
| master | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 8:33 |
| master | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:23 |
| master | 0 | boss_knight_boss | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | dark | 第 1 轮 · 稳定 | 否 | 否 | 1 | 3:20 |
| master | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:47 |
| master | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:11 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 98 / 151 | 88 / 176 | 1 / 7 | 312 / 405 | 27 / 48 |
| master | 0 | 8 | 8:00–10:00 | 76 / 108 | 72 / 112 | 1 / 5 | 355 / 402 | 21 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 13s / 12s（14/14） | 25 / 76 | 0 | bone/slider ×9；bone/slider/stone ×5 |
| master | 2 | 14 | 2:45 | 20 | 14s / 13s（14/14） | 21 / 55 | 1 | bone/slider/stone ×9；bone/slider ×5 |
| master | 3 | 8 | 4:52 | 24 | 24s / 14s（8/8） | 8 / 32 | 0 | bone/slider/stone ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/reaper/runner/slider/tracer ×2 |
| master | 4 | 8 | 5:10 | 36 | 23s / 21s（8/8） | 44 / 90 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/floater/reaper/runner/slider/tracer ×2；bone/reaper/runner/slider/tracer ×2 |
| master | 5 | 7 | 6:15 | 40 | 33s / 34s（7/7） | 19 / 37 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2；bone/reaper/runner/slider/tracer ×2 |
| master | 6 | 4 | 8:40 | 22 | 22s / 18s（4/4） | 35 / 99 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |
| master | 7 | 1 | 8:55 | 21 | 33s / 33s（1/1） | 13 / 13 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 0% | 6:29 / 5:23 | 0.0 / - | 8 / 16 / 0 / 19 | 79% | 66% | 30 | 1036 | 余震 29% 饱和复仇 9% 言 7% 爆裂黎明 7% | 自身回复 47% 凯尔希 18% 拾取 17% (435 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 0% | 8:33 / 4:07 | 0.0 / - | 8 / 14 / 19 / 18 | 33% | 66% | 80 | 828 | 熔岩弹 28% 刺剑 8% 锚击 7% 火星 7% | 自身回复 33% 流明 19% 塞雷娅 14% (992 / 0.0) | boss_carmen |
| [master] skadi | 2 | 100% | 12:13 / 11:29 | 0.0 / - | 7 / 15 / 22 / 26 | - | 100% | 94 | 1721 | 大剑 23% 替身闪现 11% 锯刃 11% Mon3tr 8% | 自身回复 27% 塞雷娅 26% 凯尔希 14% (900 / 0.0) | contact_tracer |
| [master] mizuki | 2 | 50% | 12:09 / 11:18 | 0.0 / - | 7 / 14 / 21 / 26 | 0% | 100% | 100 | 1636 | 余震 13% 锚击 11% 伞击 7% 触手 7% | 水月 63% 自身回复 20% 凯尔希 9% (806 / 0.0) | contact_tracer |
| [master] saria | 2 | 0% | 8:10 / 3:20 | 0.0 / - | 6 / 14 / 18 / 18 | 21% | 50% | 30 | 792 | 言 22% 余震 16% 拳击 10% Mon3tr 10% | 塞雷娅 50% 自身回复 20% 凯尔希 10% (1062 / 0.0) | boss_carmen |
| [master] kaltsit | 2 | 0% | 9:53 / 6:47 | 0.0 / - | 8 / 14 / 22 / 22 | 47% | 83% | 16 | 1252 | Mon3tr 21% 炮击 9% 锚击 8% 余震 7% | 凯尔希 44% 自身回复 24% 结构加固 16% (952 / 0.0) | contact_tracer |
| [master] suzuran | 2 | 0% | 8:05 / 3:11 | 0.0 / - | 8 / 15 / 22 / 18 | 3% | 66% | 48 | 1055 | 狐火 34% 锯刃 11% 藏品 10% 熔岩弹 10% | 塞雷娅 24% 自身回复 23% 凯尔希 21% (678 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 0% | 6:29 / 5:23 | 100% | 100% | 1:03 | 0:42 / 2:42 | 1.0 / 38s | 55.6 | 76 | 22 | 9 | 2 | 60% / 22063 | wound |
| [master] eyjafjalla | 2 | 0% | 8:33 / 4:07 | 100% | 50% | 1:04 | 0:47 / 4:09 | 0.5 / 269s | 65.2 | 112 | 6 | 0 | 2 | 57% / 17271 | corrode |
| [master] skadi | 2 | 100% | 12:13 / 11:29 | 100% | 100% | 1:02 | 0:44 / 4:54 | 2.0 / 52s | 117.2 | 71 | 0 | 0 | 4 | 43% / 26432 | - |
| [master] mizuki | 2 | 50% | 12:09 / 11:18 | 100% | 100% | 1:04 | 0:46 / 5:15 | 2.0 / 104s | 80.7 | 64 | 0 | 0 | 3 | 16% / 10198 | corrode |
| [master] saria | 2 | 0% | 8:10 / 3:20 | 50% | 50% | 1:17 | 0:47 / 8:03 | 0.0 / - | 130.6 | 131 | 6 | 44 | 2 | 17% / 2892 | dark |
| [master] kaltsit | 2 | 0% | 9:53 / 6:47 | 100% | 100% | 1:03 | 0:50 / 3:15 | 1.0 / 98s | 91.5 | 102 | 12 | 22 | 2 | 34% / 13716 | wound |
| [master] suzuran | 2 | 0% | 8:05 / 3:11 | 50% | 50% | 0:52 | 0:56 / 2:59 | 1.0 / 83s | 64.8 | 96 | 0 | 0 | 3 | 43% / 9756 | shock_paranoia |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 3.0 | 0.0% | class 2/0 economy 1/0 general 4/2 heal 1/0 multi 5/3 shield 1/0 survival 3/1 weak 1/0 | 0 |
| master | kaltsit | 2 | 6.5 | 6.1% | class 3/1 control 2/1 general 17/4 heal 10/5 melee 3/0 shield 1/1 summon 1/1 survival 8/0 weak 1/0 | 0 |
| master | mizuki | 2 | 11.5 | 6.6% | class 7/0 economy 5/2 general 20/10 heal 4/1 melee 1/0 multi 1/0 shield 2/1 summon 9/5 survival 9/3 weak 3/1 | 0 |
| master | saria | 2 | 1.5 | 0.0% | class 1/0 general 6/2 summon 1/0 survival 3/1 weak 1/0 | 0 |
| master | skadi | 2 | 12.5 | 1.6% | class 10/1 economy 6/1 general 19/8 heal 1/0 melee 9/4 shield 2/1 summon 2/1 survival 13/7 weak 4/2 | 0 |
| master | suzuran | 2 | 7.5 | 10.4% | class 3/1 control 8/5 economy 3/0 general 9/1 heal 1/0 shield 5/2 summon 4/1 survival 6/4 weak 1/1 | 0 |
| master | wisadel | 2 | 7.0 | 0.0% | class 1/0 economy 5/2 general 6/1 heal 1/0 melee 1/0 multi 7/5 shield 2/1 survival 10/4 weak 1/1 | 0 |
| 合计 | | | | | class 27/3 control 10/6 economy 20/5 general 81/28 heal 18/6 melee 14/4 multi 13/8 shield 13/6 summon 17/8 survival 52/20 weak 12/5 | |

拿取最多（出现 / 拿取）：穿甲弹 4/4，药枚 4/4，海潮的气息 0/3，散轶诗简 5/3，凯旋号角 3/3，制式防暴用具 4/2，银餐叉 2/2，演出用香水 3/2，食腐者手杖 4/2，“璀璨悲泣” 2/2，扣挠之手 2/2，“苦痛的快乐” 2/2
