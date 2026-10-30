# balance hitlift-new-m0-1 1030_1533

args: `--preset starts --bots expert --seeds 2 --seed0 1 --nocache --jobs 4 --tag hitlift-new-m0-1 --out build/bl/hitlift-new_m0 --extra=--tier=0 --tide=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 115s / 117s / 134s / 87–134s | 117s / 134s | 4.5 / 3.0 | 0% |
| expert | 伊祖米克 | resolve 1 | 1 | 0 | - | - | 0.0 / 2.0 | 22% |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 0.0 | 66% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 8 | 6 | 64s | 0.10 | 14 | 1.4 | 26% |
| expert | 接潮蔑死体 | 7 | 5 | 58s | 0.11 | 15 | - | - |
| expert | 圣徒卡门 | 6 | 6 | 158s | 0.19 | 6 | - | - |
| expert | 塑路者 | 5 | 5 | 47s | 0.52 | 6 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 70s | 0.09 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.1 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 13 | 0.0 / 0.0 / 0.0 / 0 | 18 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 14 | 35% | 50% | 14% (2) | 11% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 7% | 191 / 165 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:05 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:13 |
| expert | 0 | wound | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:59 |
| expert | 0 | corrode | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:14 |
| expert | 0 | boss_knight_boss | 第 1 轮 · 稳定 | 否 | 是 | 1 | 11:18 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:12 |
| expert | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:14 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 105 / 172 | 104 / 174 | 2 / 7 | 327 / 426 | 41 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 78 / 112 | 42 / 66 | 1 / 5 | 356 / 426 | 35 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 9 | 1678 | 0.0 | 3.9 / 0.5% | 0.3 / 0.5% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 5 | 2110 | 0.0 | 0.0 / 0.0% | 0.2 / 0.1% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 13s / 10s（14/14） | 14 / 49 | 0 | bone/slider ×11；bone/slider/stone ×3 |
| expert | 2 | 13 | 2:45 | 20 | 11s / 10s（13/13） | 28 / 74 | 2 | bone/slider/stone ×11；bone/slider ×2 |
| expert | 3 | 10 | 5:06 | 24 | 20s / 13s（8/10） | 17 / 81 | 2 | bone/floater/runner/slider ×4；bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/slider/stone ×1 |
| expert | 4 | 10 | 5:27 | 35 | 22s / 19s（7/10） | 41 / 138 | 3 | bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 5 | 8 | 6:22 | 39 | 22s / 14s（7/8） | 27 / 74 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 6 | 6 | 8:20 | 25 | 18s / 12s（6/6） | 10 / 22 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 9:05 | 21 | 12s / 12s（3/3） | 14 / 21 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 12:28 / 11:57 | 0.0 / - | 8 / 16 / 23 / 28 | 22% | 100% | 86 | 1973 | 余震 22% 真实 19% 饱和复仇 6% 爆裂黎明 6% | 自身回复 25% 流明 21% 凯尔希 20% (1892 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 0% | 2:39 / 2:13 | 0.0 / - | 8 / 0 / 0 / 9 | - | 0% | 13 | 281 | 熔岩弹 35% 拳击 10% 火星 10% 秘杖·速充模式 8% | 自身回复 33% 塞雷娅 16% 凯尔希 16% (253 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 9:13 / 6:59 | 0.0 / - | 8 / 14 / 23 / 24 | - | 83% | 52 | 1364 | 大剑 19% 真实 15% 熔岩弹 10% 余震 8% | 自身回复 50% 凯尔希 15% 拾取 13% (882 / 0.0) | boss_carmen |
| [expert] mizuki | 2 | 50% | 12:37 / 12:14 | 0.0 / - | 7 / 14 / 20 / 26 | 0% | 100% | 67 | 1644 | 余震 13% 伞击 12% Mon3tr · 真伤 10% 真实 10% | 水月 38% 自身回复 19% 流明 13% (2055 / 0.0) | contact_tracer |
| [expert] saria | 2 | 0% | 7:16 / 3:14 | 0.0 / - | 8 / 14 / 18 / 17 | 66% | 50% | 10 | 764 | 拳击 15% 炮击 10% 钩索 7% 冲锋模式 6% | 塞雷娅 57% 自身回复 22% 针剂回流 7% (704 / 0.0) | bullet |
| [expert] kaltsit | 2 | 0% | 5:43 / 5:14 | 0.0 / - | 8 / 15 / 0 / 16 | - | 50% | 0 | 728 | Mon3tr 30% 炮击 7% 拳击 6% 冲锋模式 6% | 凯尔希 28% 自身回复 21% 结构加固 13% (996 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 100% | 11:58 / 11:55 | 0.0 / - | 8 / 16 / 22 / 26 | - | 100% | 67 | 1784 | 狐火 15% 余震 15% 藏品 9% 拳击 5% | 自身回复 30% 塞雷娅 25% 铃兰 18% (1139 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 12:28 / 11:57 | 100% | 100% | 1:10 | 0:47 / 3:44 | 3.0 / 52s | 251.6 | 148 | 17 | 16 | 4 | 40% / 30392 | wound |
| [expert] eyjafjalla | 2 | 0% | 2:39 / 2:13 | 0% | 0% | 1:13 | 0:49 / - | 0.0 / - | 50.3 | 135 | 8 | 1 | 0 | 59% / 5035 | corrode |
| [expert] skadi | 2 | 50% | 9:13 / 6:59 | 100% | 100% | 1:00 | 0:59 / 2:56 | 2.0 / 81s | 89.1 | 116 | 5 | 0 | 3 | 34% / 17897 | wound |
| [expert] mizuki | 2 | 50% | 12:37 / 12:14 | 100% | 100% | 1:09 | 0:49 / 3:37 | 2.0 / 89s | 217.3 | 150 | 0 | 51 | 8 | 25% / 15039 | corrode |
| [expert] saria | 2 | 0% | 7:16 / 3:14 | 50% | 50% | 1:20 | 0:51 / 2:38 | 0.5 / 215s | 93.0 | 124 | 2 | 4 | 2 | 25% / 4472 | boss_knight_boss |
| [expert] kaltsit | 2 | 0% | 5:43 / 5:14 | 100% | 100% | 1:18 | 1:01 / 5:20 | 1.0 / 98s | 69.6 | 173 | 4 | 34 | 3 | 37% / 8923 | atk_reaper |
| [expert] suzuran | 2 | 100% | 11:58 / 11:55 | 100% | 100% | 1:07 | 0:51 / 4:03 | 3.0 / 82s | 169.8 | 96 | 5 | 0 | 4 | 20% / 13849 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 0.5 | 0.0% | economy 2/0 general 1/1 heal 1/0 multi 1/0 survival 1/0 | 0 |
| expert | kaltsit | 2 | 6.5 | 0.0% | class 3/0 economy 4/4 general 8/5 heal 4/2 melee 1/0 multi 2/1 shield 1/1 summon 1/0 survival 3/0 weak 1/0 | 0 |
| expert | mizuki | 2 | 11.0 | 11.8% | class 7/1 control 2/0 economy 9/3 general 20/10 heal 1/0 melee 5/0 shield 1/0 summon 7/6 survival 6/2 weak 3/0 | 0 |
| expert | saria | 2 | 3.0 | 0.0% | class 2/0 economy 3/2 general 5/3 melee 1/0 multi 1/0 shield 1/0 summon 1/1 survival 3/0 | 0 |
| expert | skadi | 2 | 9.5 | 15.9% | class 2/1 economy 8/1 general 17/5 heal 1/0 melee 8/4 multi 4/1 shield 3/1 summon 2/1 survival 11/5 weak 2/0 | 0 |
| expert | suzuran | 2 | 10.0 | 12.5% | class 1/0 control 6/4 economy 7/1 general 22/8 heal 1/1 melee 4/1 multi 3/1 shield 3/1 summon 4/1 survival 8/2 weak 3/0 | 0 |
| expert | wisadel | 2 | 14.0 | 20.6% | class 2/1 control 4/2 economy 10/4 general 14/9 heal 3/0 melee 5/1 multi 12/2 shield 3/0 summon 2/3 survival 6/3 weak 3/3 | 0 |
| 合计 | | | | | class 17/3 control 12/6 economy 43/15 general 87/41 heal 11/3 melee 24/6 multi 23/5 shield 12/3 summon 17/12 survival 38/12 weak 12/3 | |

拿取最多（出现 / 拿取）：指路鳞 3/3，无瑕宝玉 3/2，显圣吊坠 7/2，被撬开的道具箱 3/2，散轶诗简 2/2，《旧高卢地名源流考》 7/2，支援急救包 3/2，皇帝的恩宠 9/2，主教的研究 0/2，人偶之家 2/2，赤金的远征 4/2，银餐叉 7/2
