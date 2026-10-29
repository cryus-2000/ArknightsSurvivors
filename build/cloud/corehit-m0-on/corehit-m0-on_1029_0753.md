# balance corehit-m0-on 1029_0753

args: `--preset starts --bots expert --seeds 4 --seed0 5 --jobs 4 --tag corehit-m0-on --extra=--meta=0 --out build/cloud/corehit-m0-on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 5 | 142s / 157s / 168s / 93–168s | 157s / 168s | 2.2 / 3.0 | 13% |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 90s / 90s / 115s / 65–115s | 90s / 115s | 6.3 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 10 | 74s | 0.70 | 1 | - | - |
| expert | 塑路者 | 11 | 11 | 62s | 0.69 | 2 | - | - |
| expert | 接潮主教 | 10 | 8 | 59s | 0.15 | 5 | 1.0 | 11% |
| expert | 接潮斥亡体 | 6 | 4 | 60s | 0.14 | 4 | - | - |
| expert | 接潮蔑死体 | 4 | 4 | 59s | 0.18 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 25% | 213 / 190 | 92% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 3 | 2:20 |
| expert | 0 | atk_tracer | 第 2 轮 · 稳定 | 否 | 否 | 2 | 6:23 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 2 | 3:03 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 2 | 5:36 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:22 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | wound | 第 2 轮 · 预告 | 否 | 是 | 1 | 7:00 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:32 |
| expert | 0 | corrode | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:51 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:07 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:34 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:15 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:49 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:07 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 92 / 181 | 70 / 162 | 2 / 9 | 289 / 427 | 26 / 48 |
| expert | 0 | 10 | 8:00–10:00 | 84 / 98 | 31 / 57 | 1 / 6 | 339 / 403 | 30 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 14s / 12s（28/28） | 22 / 53 | 0 | bone/slider/stone ×22；bone/slider ×6 |
| expert | 2 | 23 | 2:45 | 20 | 10s / 10s（22/23） | 31 / 109 | 3 | bone/slider ×19；bone/slider/stone ×4 |
| expert | 3 | 19 | 4:41 | 24 | 13s / 11s（19/19） | 15 / 90 | 0 | bone/offspring/slider/stone ×6；bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 4 | 19 | 5:06 | 35 | 32s / 26s（17/19） | 32 / 78 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/floater/reaper/runner/slider/tracer ×7；bone/reaper/runner/slider/tracer ×3 |
| expert | 5 | 17 | 6:15 | 40 | 29s / 28s（13/17） | 43 / 122 | 4 | bone/reaper/runner/slider/tracer ×8；bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 6 | 10 | 8:13 | 27 | 23s / 16s（10/10） | 37 / 87 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 8 | 9:17 | 22 | 15s / 14s（8/8） | 30 / 110 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 6:58 / 2:25 | 0.0 / - | 8 / 15 / 21 / 18 | - | 41% | 64 | 906 | 余震 37% 饱和复仇 14% 炮击 9% 殉爆 7% | 自身回复 29% 塞雷娅 24% 拾取 9% (705 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 4 | 0% | 5:11 / 2:17 | 0.0 / - | 7 / 14 / 21 / 13 | 26% | 25% | 60 | 600 | 熔岩弹 31% 狐火 9% 余震 9% 火星 8% | 自身回复 35% 补给 34% 塞雷娅 14% (564 / 0.0) | contact_tracer |
| [expert] skadi | 4 | 50% | 12:33 / 11:33 | 0.0 / - | 8 / 14 / 21 / 26 | 6% | 100% | 92 | 1632 | 大剑 23% 余震 14% 狐火 5% 潮刃 5% | 自身回复 28% 流明 19% 补给 18% (1341 / 0.8) | contact_tracer |
| [expert] mizuki | 4 | 50% | 8:12 / 2:32 | 0.0 / - | 8 / 14 / 21 / 19 | 100% | 58% | 82 | 1044 | 伞击 19% 触手 14% 延异视阈 8% 钩索 6% | 水月 51% 自身回复 19% 塞雷娅 8% (1168 / 0.2) | contact_tracer |
| [expert] saria | 4 | 25% | 7:10 / 2:51 | 0.0 / - | 7 / 14 / 20 / 17 | 100% | 58% | 22 | 862 | 余震 18% 刺剑 14% 拳击 11% 炮击 10% | 塞雷娅 59% 自身回复 22% 补给 9% (824 / 0.0) | atk_tracer |
| [expert] kaltsit | 4 | 0% | 5:05 / 2:34 | 0.0 / - | 8 / 14 / 0 / 14 | - | 50% | 3 | 609 | Mon3tr 36% 锚击 9% 刺剑 9% Mon3tr · 真伤 7% | 凯尔希 44% 自身回复 29% 结构加固 18% (721 / 0.0) | contact_tracer |
| [expert] suzuran | 4 | 25% | 6:27 / 2:57 | 0.0 / - | 8 / 15 / 21 / 17 | 79% | 41% | 31 | 916 | 狐火 43% 余震 8% Mon3tr 5% 锚击 4% | 自身回复 28% 补给 16% 铃兰 15% (637 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 6:58 / 2:25 | 75% | 75% | 0:57 | 0:49 / 4:04 | 1.2 / 59s | 53.4 | 119 | 3 | 0 | 2 | 73% / 23960 | corrode |
| [expert] eyjafjalla | 4 | 0% | 5:11 / 2:17 | 25% | 25% | 1:04 | 0:48 / 4:43 | 0.5 / 63s | 50.7 | 116 | 3 | 0 | 2 | 51% / 8248 | contact_tracer |
| [expert] skadi | 4 | 50% | 12:33 / 11:33 | 100% | 100% | 1:04 | 0:47 / 3:00 | 3.0 / 58s | 110.0 | 103 | 4 | 6 | 5 | 42% / 26272 | corrode |
| [expert] mizuki | 4 | 50% | 8:12 / 2:32 | 75% | 75% | 1:05 | 0:48 / 3:28 | 1.8 / 76s | 108.3 | 149 | 3 | 15 | 4 | 38% / 10301 | wound |
| [expert] saria | 4 | 25% | 7:10 / 2:51 | 75% | 75% | 1:24 | 0:51 / 3:47 | 1.0 / 83s | 88.5 | 126 | 4 | 21 | 3 | 16% / 3363 | corrode |
| [expert] kaltsit | 4 | 0% | 5:05 / 2:34 | 75% | 75% | 1:05 | 0:51 / 3:27 | 0.8 / 76s | 50.1 | 156 | 7 | 12 | 3 | 47% / 9572 | corrode |
| [expert] suzuran | 4 | 25% | 6:27 / 2:57 | 75% | 50% | 1:05 | 0:48 / 5:01 | 1.0 / 51s | 59.4 | 114 | 5 | 0 | 3 | 43% / 9230 | atk_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 4.2 | 0.0% | class 4/2 economy 11/2 general 12/1 heal 1/0 melee 4/1 multi 9/3 shield 2/1 summon 1/0 survival 11/7 weak 3/0 | 0 |
| expert | kaltsit | 4 | 3.0 | 0.0% | class 1/0 economy 1/0 general 9/5 heal 10/4 melee 1/0 multi 1/0 shield 1/0 summon 2/0 survival 11/3 weak 2/0 | 0 |
| expert | mizuki | 4 | 7.5 | 1.5% | class 7/1 control 1/1 economy 4/1 general 25/15 heal 4/0 melee 1/0 multi 2/0 shield 3/1 summon 12/2 survival 22/8 weak 5/1 | 0 |
| expert | saria | 4 | 5.5 | 0.0% | class 5/3 economy 5/1 general 18/7 heal 14/1 melee 3/1 multi 4/2 shield 4/3 summon 1/0 survival 16/3 weak 1/1 | 0 |
| expert | skadi | 4 | 15.8 | 2.3% | class 26/8 control 4/1 economy 19/10 general 37/16 heal 9/2 melee 24/10 multi 7/2 shield 6/3 summon 6/3 survival 31/5 weak 6/3 | 0 |
| expert | suzuran | 4 | 6.8 | 0.0% | class 8/0 control 10/6 economy 4/0 general 17/9 heal 5/1 melee 1/0 multi 5/1 shield 4/1 survival 16/7 weak 4/2 | 0 |
| expert | wisadel | 4 | 6.5 | 0.0% | class 8/3 economy 4/1 general 26/10 heal 3/1 melee 3/0 multi 11/7 shield 4/2 summon 2/1 survival 9/0 weak 3/1 | 0 |
| 合计 | | | | | class 59/17 control 15/8 economy 48/15 general 144/63 heal 46/9 melee 37/12 multi 39/15 shield 24/11 summon 24/6 survival 116/33 weak 24/8 | |

拿取最多（出现 / 拿取）：穿甲弹 9/4，“多功能”发夹 6/4，显圣吊坠 14/4，生还者合约 5/4，海潮的气息 0/4，古旧钱币 3/4，皇帝的恩宠 11/4，“绽放” 4/3，支援补给站 9/3，地形图 3/3，锈刃-可视静谧 6/3，《旧高卢地名源流考》 6/3
