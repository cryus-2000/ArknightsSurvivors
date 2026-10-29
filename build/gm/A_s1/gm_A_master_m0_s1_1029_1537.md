# balance gm_A_master_m0_s1 1029_1537

args: `--preset starts --bot master --seed0 1 --seeds 4 --jobs 4 --extra --tier=0 --tide=0 --tag gm_A_master_m0_s1 --out build/gm/A_s1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 13 | 13 | 6 | 111s / 110s / 141s / 95–141s | 110s / 141s | 1.7 / 2.7 | 43% |
| master | 最后的骑士 | knight 4 | 4 | 2 | 114s / 114s / 138s / 91–138s | 114s / 138s | 3.4 / 2.0 | 8% |
| master | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 0.0 / 1.0 | 59% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 塑路者 | 16 | 14 | 59s | 0.40 | 12 | - | - |
| master | 圣徒卡门 | 11 | 7 | 101s | 0.27 | 9 | - | - |
| master | 接潮主教 | 9 | 4 | 58s | 0.05 | 17 | 1.6 | 4% |
| master | 圣徒伊比利亚 | 6 | 2 | 55s | 0.06 | 16 | - | - |
| master | 接潮蔑死体 | 5 | 3 | 44s | 0.09 | 19 | - | - |
| master | 接潮斥亡体 | 4 | 3 | 166s | 0.08 | 18 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 28 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 16 | 0.0 / 0.0 / 0.0 / 0 | 18 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 28 | 10% | 178 / 162 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | boss_knight_boss | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:15 |
| master | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| master | 0 | bullet | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:04 |
| master | 0 | mire | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:36 |
| master | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:37 |
| master | 0 | nest | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:37 |
| master | 0 | boss_ishar | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:47 |
| master | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | nest | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:19 |
| master | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:54 |
| master | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:02 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 28 | 全程 | 106 / 221 | 100 / 180 | 2 / 11 | 307 / 437 | 25 / 48 |
| master | 0 | 18 | 8:00–10:00 | 78 / 110 | 62 / 108 | 1 / 5 | 324 / 407 | 19 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 28 | 1:15 | 15 | 13s / 11s（28/28） | 19 / 76 | 0 | bone/slider ×22；bone/slider/stone ×6 |
| master | 2 | 26 | 2:45 | 20 | 13s / 11s（25/26） | 28 / 96 | 2 | bone/slider/stone ×20；bone/slider ×6 |
| master | 3 | 18 | 4:58 | 25 | 21s / 17s（18/18） | 6 / 35 | 0 | bone/reaper/runner/slider/tracer ×6；bone/offspring/slider/stone ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| master | 4 | 18 | 5:16 | 36 | 46s / 24s（16/18） | 27 / 139 | 1 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/floater/reaper/runner/slider/tracer ×4 |
| master | 5 | 15 | 6:15 | 40 | 46s / 31s（15/15） | 32 / 87 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| master | 6 | 7 | 8:12 | 26 | 23s / 18s（7/7） | 10 / 38 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |
| master | 7 | 5 | 9:08 | 22 | 15s / 14s（5/5） | 21 / 46 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 4 | 50% | 10:29 / 5:15 | 0.0 / - | 8 / 16 / 22 / 24 | 45% | 91% | 80 | 1547 | 余震 26% 提喻 8% 言 8% 饱和复仇 7% | 自身回复 36% 凯尔希 19% 补给 12% (718 / 0.0) | contact_tracer |
| [master] eyjafjalla | 4 | 0% | 6:02 / 2:31 | 0.0 / - | 8 / 14 / 19 / 14 | 5% | 25% | 35 | 600 | 熔岩弹 29% 火星 7% 炮击 7% 点燃 5% | 自身回复 38% 补给 18% 拾取 15% (696 / 0.0) | contact_tracer |
| [master] skadi | 4 | 100% | 11:56 / 11:31 | 0.0 / - | 7 / 15 / 22 / 26 | - | 100% | 75 | 1775 | 大剑 27% Mon3tr 9% 锯刃 6% 替身闪现 5% | 自身回复 30% 流明 18% 凯尔希 16% (874 / 0.0) | contact_tracer |
| [master] mizuki | 4 | 0% | 8:03 / 2:37 | 0.0 / - | 8 / 14 / 20 / 17 | 49% | 50% | 60 | 881 | 触手 16% 伞击 16% 熔岩弹 10% 锯刃 5% | 水月 59% 自身回复 19% 塞雷娅 7% (1011 / 0.0) | contact_tracer |
| [master] saria | 4 | 50% | 12:21 / 11:35 | 0.0 / - | 6 / 15 / 21 / 26 | 33% | 100% | 90 | 1691 | 余震 15% Mon3tr 15% 食腐 7% 锚击 5% | 塞雷娅 44% 自身回复 23% 凯尔希 15% (959 / 0.0) | contact_tracer |
| [master] kaltsit | 4 | 0% | 9:31 / 5:47 | 0.0 / - | 8 / 14 / 19 / 20 | 55% | 66% | 41 | 1042 | Mon3tr 24% 锚击 12% Mon3tr · 真伤 10% 撼地 5% | 凯尔希 38% 自身回复 26% 结构加固 18% (856 / 0.0) | contact_tracer |
| [master] suzuran | 4 | 0% | 8:44 / 2:54 | 0.0 / - | 8 / 14 / 20 / 18 | 32% | 66% | 66 | 950 | 狐火 47% Mon3tr 19% 熔岩弹 5% 藏品 3% | 凯尔希 25% 自身回复 23% 铃兰 15% (725 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 4 | 50% | 10:29 / 5:15 | 100% | 100% | 1:05 | 0:44 / 2:24 | 1.8 / 47s | 95.9 | 69 | 5 | 16 | 3 | 51% / 29979 | shock_paranoia |
| [master] eyjafjalla | 4 | 0% | 6:02 / 2:31 | 50% | 50% | 1:00 | 0:52 / 4:19 | 0.5 / 179s | 47.4 | 122 | 16 | 0 | 2 | 53% / 11039 | mire |
| [master] skadi | 4 | 100% | 11:56 / 11:31 | 100% | 100% | 1:04 | 0:46 / 3:46 | 2.2 / 70s | 99.0 | 64 | 2 | 28 | 4 | 50% / 33907 | - |
| [master] mizuki | 4 | 0% | 8:03 / 2:37 | 75% | 50% | 1:00 | 0:54 / 3:23 | 0.2 / 56s | 109.6 | 130 | 2 | 28 | 1 | 37% / 9005 | contact_tracer |
| [master] saria | 4 | 50% | 12:21 / 11:35 | 100% | 100% | 1:27 | 0:49 / 2:39 | 2.0 / 95s | 143.8 | 76 | 0 | 4 | 3 | 7% / 4326 | boss_ishar |
| [master] kaltsit | 4 | 0% | 9:31 / 5:47 | 100% | 100% | 1:04 | 0:51 / 3:33 | 0.5 / 96s | 85.0 | 89 | 8 | 38 | 2 | 37% / 11025 | mire |
| [master] suzuran | 4 | 0% | 8:44 / 2:54 | 75% | 75% | 0:59 | 0:51 / 3:23 | 1.0 / 122s | 67.2 | 98 | 7 | 5 | 2 | 48% / 11943 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 4 | 3.2 | 0.0% | class 3/0 control 1/1 economy 2/0 general 11/5 heal 3/1 melee 1/0 multi 5/3 shield 1/0 summon 2/0 survival 8/3 weak 1/0 | 0 |
| master | kaltsit | 4 | 5.0 | 3.0% | class 7/0 economy 4/1 general 17/5 heal 15/8 multi 3/1 shield 11/4 survival 8/0 weak 3/1 | 0 |
| master | mizuki | 4 | 3.0 | 0.0% | class 5/0 economy 1/0 general 7/2 heal 1/1 melee 2/0 multi 2/1 summon 9/4 survival 7/3 weak 3/1 | 0 |
| master | saria | 4 | 8.0 | 7.2% | class 6/0 control 1/1 economy 6/2 general 19/6 heal 19/12 melee 3/2 multi 2/1 shield 3/3 summon 5/3 survival 23/2 weak 1/0 | 0 |
| master | skadi | 4 | 9.8 | 0.0% | class 10/1 control 1/0 economy 7/1 general 26/9 heal 7/3 melee 27/13 multi 2/1 shield 10/6 summon 2/0 survival 28/3 weak 2/2 | 0 |
| master | suzuran | 4 | 4.2 | 3.6% | class 5/0 control 6/4 economy 2/1 general 11/3 heal 4/1 multi 2/0 shield 2/2 summon 1/1 survival 8/5 | 0 |
| master | wisadel | 4 | 9.5 | 0.2% | class 10/4 control 1/1 economy 2/1 general 33/12 heal 6/0 melee 5/1 multi 21/11 shield 7/3 summon 3/0 survival 16/2 weak 6/3 | 0 |
| 合计 | | | | | class 46/5 control 10/7 economy 24/6 general 124/42 heal 55/26 melee 38/16 multi 37/18 shield 34/18 summon 22/8 survival 98/18 weak 16/7 | |

拿取最多（出现 / 拿取）：药枚 8/8，银餐叉 9/7，穿甲弹 8/6，猎人的口粮 10/6，演出用香水 7/6，海潮的气息 0/5，苍白花冠 9/4，贵族刺剑 8/4，海程 9/3，特级馥郁咖啡豆 8/3，食腐者手杖 4/3，锈蚀刀片 9/3
