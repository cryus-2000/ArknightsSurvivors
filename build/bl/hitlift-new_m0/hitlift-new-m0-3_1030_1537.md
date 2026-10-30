# balance hitlift-new-m0-3 1030_1537

args: `--preset starts --bots expert --seeds 2 --seed0 3 --nocache --jobs 4 --tag hitlift-new-m0-3 --out build/bl/hitlift-new_m0 --extra=--tier=0 --tide=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 5 | 132s / 134s / 157s / 100–157s | 134s / 157s | 2.3 / 3.0 | 9% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 119s / 119s / 119s / 119–119s | 99s / 99s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 2.0 | 18% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 11 | 10 | 38s | 0.59 | 10 | - | - |
| expert | 接潮主教 | 9 | 7 | 113s | 0.09 | 21 | 1.0 | 13% |
| expert | 接潮蔑死体 | 7 | 5 | 113s | 0.08 | 23 | - | - |
| expert | 圣徒卡门 | 4 | 4 | 84s | 0.29 | 9 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 86s | 0.11 | 18 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 110s | 0.13 | 19 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.1 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 14 | 42% | 28% | 28% (4) | 11% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 0% | 228 / 208 | 92% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:55 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:14 |
| expert | 0 | contact_founder | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:05 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:20 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 124 / 193 | 124 / 199 | 3 / 8 | 350 / 419 | 42 / 48 |
| expert | 0 | 10 | 8:00–10:00 | 98 / 168 | 60 / 153 | 1 / 5 | 350 / 419 | 35 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 8 | 1441 | 0.0 | 0.9 / 0.3% | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 3214 | 0.0 | 1.8 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 12s / 10s（14/14） | 21 / 62 | 0 | bone/slider ×9；bone/slider/stone ×5 |
| expert | 2 | 14 | 2:45 | 20 | 19s / 10s（14/14） | 23 / 80 | 0 | bone/slider/stone ×9；bone/slider ×5 |
| expert | 3 | 13 | 4:51 | 24 | 35s / 14s（12/13） | 22 / 153 | 1 | bone/floater/reaper/runner/slider/tracer ×5；bone/slider/stone ×2；bone/offspring/slider/stone ×2 |
| expert | 4 | 12 | 5:16 | 36 | 48s / 28s（11/12） | 47 / 143 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 11 | 6:15 | 40 | 50s / 40s（10/11） | 38 / 107 | 0 | bone/floater/reaper/runner/slider/tracer ×7；bone/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 6 | 7 | 8:28 | 24 | 43s / 15s（7/7） | 31 / 90 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 9:03 | 22 | 15s / 15s（3/3） | 6 / 8 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 100% | 11:53 / 11:40 | 0.0 / - | 8 / 16 / 24 / 28 | - | 100% | 88 | 1919 | 余震 30% 饱和复仇 9% 爆裂黎明 7% 殉爆 5% | 自身回复 33% 凯尔希 19% 拾取 17% (1315 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 50% | 8:11 / 3:55 | 0.0 / - | 8 / 15 / 21 / 20 | 34% | 66% | 38 | 1103 | 熔岩弹 23% 盾斧斩 7% 火山 7% 火星 6% | 自身回复 29% 塞雷娅 27% 拾取 17% (1345 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 12:29 / 11:59 | 0.0 / - | 8 / 14 / 21 / 26 | 8% | 100% | 78 | 1711 | 大剑 36% 迅捷打击·γ型 8% 跃浪 8% 剑雨 6% | 塞雷娅 57% 自身回复 23% 针剂回流 7% (1572 / 0.0) | bullet |
| [expert] mizuki | 2 | 50% | 12:37 / 12:14 | 0.0 / - | 8 / 14 / 20 / 25 | 18% | 100% | 90 | 1626 | 伞击 11% 触手 8% 骑士 8% 秘杖·速充模式 7% | 水月 51% 自身回复 20% 流明 14% (2357 / 0.0) | bullet |
| [expert] saria | 2 | 50% | 12:48 / 12:37 | 0.0 / - | 7 / 14 / 20 / 25 | 4% | 100% | 54 | 1525 | 刺剑 24% Mon3tr 10% 拳击 8% Mon3tr · 真伤 6% | 塞雷娅 44% 自身回复 16% 凯尔希 8% (1993 / 0.0) | bullet |
| [expert] kaltsit | 2 | 0% | 4:39 / 4:14 | 0.0 / - | 8 / 16 / 0 / 15 | - | 50% | 40 | 615 | Mon3tr 28% 狐火 16% 熔岩弹 9% 提喻 7% | 凯尔希 35% 自身回复 32% 结构加固 17% (442 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 0% | 10:10 / 7:20 | 0.0 / - | 8 / 16 / 21 / 22 | 32% | 83% | 50 | 1466 | 狐火 24% 拳击 14% 骑士 13% 狐火点点 10% | 塞雷娅 36% 自身回复 18% 流明 14% (1230 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 100% | 11:53 / 11:40 | 100% | 100% | 1:01 | 0:43 / 4:04 | 3.0 / 45s | 206.6 | 108 | 0 | 0 | 4 | 55% / 45026 | - |
| [expert] eyjafjalla | 2 | 50% | 8:11 / 3:55 | 100% | 50% | 1:03 | 0:48 / 3:28 | 1.0 / 91s | 102.5 | 138 | 28 | 52 | 2 | 47% / 18821 | bullet |
| [expert] skadi | 2 | 50% | 12:29 / 11:59 | 100% | 100% | 0:44 | 1:05 / 5:04 | 3.0 / 100s | 187.8 | 122 | 0 | 0 | 4 | 64% / 43339 | corrode |
| [expert] mizuki | 2 | 50% | 12:37 / 12:14 | 100% | 100% | 1:02 | 0:45 / 5:19 | 1.5 / 79s | 188.4 | 184 | 12 | 0 | 4 | 23% / 13821 | bullet |
| [expert] saria | 2 | 50% | 12:48 / 12:37 | 100% | 100% | 1:26 | 0:48 / 4:05 | 3.0 / 122s | 193.3 | 141 | 12 | 52 | 4 | 14% / 7462 | corrode |
| [expert] kaltsit | 2 | 0% | 4:39 / 4:14 | 100% | 50% | 1:04 | 0:56 / 3:36 | 1.0 / 33s | 17.0 | 122 | 0 | 0 | 4 | 38% / 6733 | contact_reaper |
| [expert] suzuran | 2 | 0% | 10:10 / 7:20 | 100% | 100% | 0:43 | 1:01 / 3:43 | 2.0 / 79s | 132.8 | 120 | 0 | 0 | 4 | 35% / 16760 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 7.5 | 5.7% | class 5/2 control 1/1 economy 6/2 general 13/3 heal 1/1 melee 1/0 multi 4/2 shield 2/0 summon 1/1 survival 4/2 weak 0/1 | 0 |
| expert | kaltsit | 2 | 2.0 | 0.0% | class 1/0 control 3/0 economy 2/0 general 4/2 heal 2/1 melee 1/0 multi 1/0 survival 2/1 weak 1/0 | 0 |
| expert | mizuki | 2 | 10.5 | 5.9% | class 7/2 economy 9/2 general 12/8 heal 3/1 melee 6/2 multi 2/1 shield 2/1 summon 11/4 survival 5/0 weak 1/0 | 0 |
| expert | saria | 2 | 16.0 | 1.1% | class 5/1 control 5/3 economy 12/3 general 21/5 heal 10/4 melee 6/2 multi 7/2 shield 12/5 summon 6/3 survival 18/4 weak 1/0 | 0 |
| expert | skadi | 2 | 16.5 | 0.0% | class 11/3 economy 10/6 general 22/8 heal 5/0 melee 15/3 multi 2/1 shield 3/1 summon 4/3 survival 22/6 weak 3/2 | 0 |
| expert | suzuran | 2 | 11.0 | 1.5% | class 6/1 control 9/4 economy 3/0 general 17/10 heal 4/0 melee 1/1 multi 2/2 shield 3/2 summon 2/0 survival 9/2 weak 1/0 | 0 |
| expert | wisadel | 2 | 15.5 | 8.1% | class 13/4 control 3/3 economy 7/2 general 21/10 heal 2/1 melee 5/0 multi 9/3 shield 3/3 summon 1/0 survival 12/5 weak 2/0 | 0 |
| 合计 | | | | | class 48/13 control 21/11 economy 49/15 general 110/46 heal 27/8 melee 35/8 multi 27/11 shield 25/12 summon 25/11 survival 72/20 weak 9/3 | |

拿取最多（出现 / 拿取）：洁白的舞鞋 6/4，无字珊瑚 5/4，海潮的气息 0/4，《旧高卢地名源流考》 5/4，损坏的左轮弹巢 5/4，“多功能”发夹 10/3，遥乡之引 3/3，鸭爵金砖 3/3，猎人的口粮 8/2，万能钥匙 2/2，夜阳草 5/2，“荣耀套餐” 4/2
