# balance gm_B_master_m18_s1b 1029_1549

args: `--preset starts --bot master --seed0 3 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --meta=18 --tag gm_B_master_m18_s1b --out build/gm/B_s1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 11 | 11 | 4 | 125s / 127s / 161s / 87–161s | 128s / 161s | 3.3 / 3.0 | 24% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 圣徒卡门 | 13 | 8 | 124s | 0.06 | 10 | - | - |
| master | 接潮主教 | 9 | 3 | 129s | 0.02 | 22 | 1.2 | 6% |
| master | 接潮斥亡体 | 5 | 2 | 154s | 0.06 | 18 | - | - |
| master | 塑路者 | 5 | 4 | 82s | 0.32 | 13 | - | - |
| master | 接潮蔑死体 | 4 | 2 | 113s | 0.06 | 24 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 30 | 0.0 / 0.0 / 0.0 / 0 | 32 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 0% | 75 / 66 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 3 | 10:18 |
| master | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | shock_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:50 |
| master | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 111 / 180 | 145 / 176 | 2 / 8 | 370 / 433 | 27 / 48 |
| master | 0 | 13 | 8:00–10:00 | 80 / 111 | 86 / 121 | 2 / 5 | 354 / 399 | 20 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 11s / 11s（14/14） | 8 / 44 | 0 | bone/slider ×9；bone/slider/stone ×5 |
| master | 2 | 14 | 2:45 | 20 | 14s / 13s（14/14） | 17 / 61 | 0 | bone/slider/stone ×9；bone/slider ×5 |
| master | 3 | 7 | 5:07 | 24 | 18s / 19s（7/7） | 10 / 36 | 0 | bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/offspring/slider/stone ×1 |
| master | 4 | 7 | 5:18 | 36 | 31s / 19s（7/7） | 30 / 72 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×1 |
| master | 5 | 7 | 6:15 | 40 | 34s / 32s（7/7） | 36 / 89 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×1 |
| master | 6 | 4 | 9:01 | 23 | 18s / 16s（4/4） | 27 / 40 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:13 / 11:27 | 0.0 / - | 8 / 15 / 21 / 27 | 20% | 100% | 100 | 1716 | 余震 27% 饱和复仇 8% Mon3tr 6% 殉爆 5% | 自身回复 31% 水月 20% 凯尔希 12% (1015 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 0% | 7:36 / 6:50 | 0.0 / - | 8 / 15 / 17 / 18 | 71% | 50% | 45 | 1013 | 熔岩弹 22% 锚击 11% 盾斧斩 7% 撼地 6% | 自身回复 40% 水月 22% 流明 19% (548 / 0.0) | contact_tracer |
| [master] skadi | 2 | 50% | 12:22 / 11:44 | 0.0 / - | 8 / 15 / 21 / 26 | 16% | 100% | 98 | 1651 | 大剑 21% Mon3tr 17% Mon3tr · 真伤 9% 熔岩弹 8% | 凯尔希 41% 自身回复 29% 结构加固 15% (766 / 0.0) | bullet |
| [master] mizuki | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 7 / 14 / 18 / 23 | 24% | 100% | 58 | 1251 | Mon3tr 14% 伞击 13% 熔岩弹 11% 触手 10% | 水月 51% 自身回复 20% 凯尔希 10% (1352 / 0.0) | boss_carmen |
| [master] saria | 2 | 50% | 11:07 / 9:33 | 0.0 / - | 7 / 14 / 18 / 21 | 15% | 83% | 16 | 1132 | Mon3tr 25% 食腐 13% 拳击 7% Mon3tr · 清创 7% | 塞雷娅 41% 自身回复 24% 凯尔希 19% (830 / 0.0) | boss_carmen |
| [master] kaltsit | 2 | 50% | 12:45 / 12:31 | 0.0 / - | 8 / 14 / 19 / 24 | 35% | 100% | 88 | 1254 | Mon3tr 16% 余震 15% 狐火 12% 般若回旋 4% | 凯尔希 42% 自身回复 28% 结构加固 21% (1126 / 0.0) | boss_carmen |
| [master] suzuran | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 8 / 14 / 20 / 26 | 27% | 100% | 80 | 1576 | 狐火 17% 锯刃 15% 熔岩弹 11% 替身闪现 10% | 塞雷娅 25% 自身回复 19% 凯尔希 17% (1274 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:13 / 11:27 | 100% | 100% | 1:06 | 0:44 / 6:16 | 3.0 / 105s | 117.4 | 67 | 4 | 58 | 2 | 51% / 31297 | shock_paranoia |
| [master] eyjafjalla | 2 | 0% | 7:36 / 6:50 | 100% | 100% | 1:02 | 0:45 / 6:18 | 0.5 / 66s | 37.0 | 86 | 18 | 4 | 2 | 42% / 12878 | wound |
| [master] skadi | 2 | 50% | 12:22 / 11:44 | 100% | 100% | 0:52 | 0:54 / 4:44 | 1.5 / 80s | 100.4 | 60 | 0 | 1 | 4 | 42% / 24346 | shock_paranoia |
| [master] mizuki | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 0:53 | 0:57 / 5:51 | 0.5 / 353s | 116.2 | 74 | 2 | 120 | 2 | 27% / 8808 | shock_paranoia |
| [master] saria | 2 | 50% | 11:07 / 9:33 | 100% | 100% | 1:15 | 0:48 / 4:00 | 0.5 / 327s | 56.1 | 67 | 3 | 42 | 3 | 12% / 4587 | wound |
| [master] kaltsit | 2 | 50% | 12:45 / 12:31 | 100% | 100% | 1:01 | 0:49 / 3:54 | 1.0 / 237s | 75.8 | 74 | 5 | 64 | 2 | 24% / 9993 | shock_paranoia |
| [master] suzuran | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 0:50 | 0:53 / 3:43 | 2.5 / 130s | 122.5 | 88 | 18 | 40 | 2 | 24% / 14721 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 3.0 | 0.9% | class 2/0 control 1/1 economy 3/0 general 4/0 melee 1/1 multi 5/2 shield 2/1 summon 3/0 weak 2/1 | 0 |
| master | kaltsit | 2 | 8.5 | 3.6% | class 2/2 control 1/1 economy 6/0 general 12/2 heal 10/6 melee 3/0 shield 4/2 survival 11/3 weak 2/1 | 0 |
| master | mizuki | 2 | 5.0 | 0.0% | class 6/1 control 2/2 economy 1/0 general 10/1 melee 1/0 multi 1/0 summon 4/2 survival 4/2 weak 2/2 | 0 |
| master | saria | 2 | 2.5 | 13.9% | class 1/0 control 1/0 general 5/0 heal 8/4 melee 2/1 summon 1/0 survival 1/0 | 0 |
| master | skadi | 2 | 8.0 | 0.0% | class 9/2 control 2/1 economy 4/0 general 9/1 heal 1/1 melee 7/3 multi 2/1 shield 2/0 summon 1/1 survival 12/6 weak 1/0 | 0 |
| master | suzuran | 2 | 10.0 | 5.2% | class 5/1 control 7/6 economy 6/3 general 19/6 heal 3/0 multi 1/0 shield 1/0 summon 2/1 survival 11/3 weak 1/0 | 0 |
| master | wisadel | 2 | 12.5 | 0.0% | class 7/1 control 1/1 economy 3/1 general 18/6 heal 1/0 melee 3/1 multi 8/5 shield 2/1 summon 2/0 survival 14/7 weak 5/2 | 0 |
| 合计 | | | | | class 32/7 control 15/12 economy 23/4 general 77/16 heal 23/11 melee 17/6 multi 17/8 shield 11/4 summon 13/4 survival 53/21 weak 13/6 | |

拿取最多（出现 / 拿取）：凯旋号角 5/6，“黑夜呢喃” 6/4，演出用香水 4/4，皇帝的恩宠 8/3，显圣吊坠 6/3，悬丝傀儡 3/3，食腐者手杖 2/3，指路鳞 3/3，特级馥郁咖啡豆 4/2，洁白的舞鞋 7/2，镶金骨骰 3/2，舞者手链 2/2
