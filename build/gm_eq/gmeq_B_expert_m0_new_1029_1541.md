# balance gmeq_B_expert_m0_new 1029_1541

args: `--preset starts --bot expert --seed0 1 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --trace=1 --tag gmeq_B_expert_m0_new --out build/gm_eq`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 4 | 4 | 2 | 104s / 104s / 107s / 102–107s | 104s / 107s | 4.3 / 3.0 | 33% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 69s / 69s / 69s / 69–69s | 49s / 49s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 6 | 6 | 82s | 0.35 | 5 | - | - |
| expert | 圣徒卡门 | 6 | 3 | 57s | 0.29 | 7 | - | - |
| expert | 接潮主教 | 5 | 2 | 82s | 0.06 | 15 | 1.7 | 9% |
| expert | 接潮斥亡体 | 4 | 1 | 82s | 0.10 | 16 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 147s | 0.08 | 12 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 50s | 0.11 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 14% | 273 / 266 | 93% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 6:11 |
| expert | 0 | mire | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:18 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:34 |
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:56 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:00 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | boss_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:38 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:48 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 92 / 220 | 91 / 199 | 2 / 7 | 286 / 407 | 27 / 48 |
| expert | 0 | 5 | 8:00–10:00 | 71 / 82 | 72 / 110 | 0 / 0 | 321 / 407 | 26 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 12s / 10s（14/14） | 19 / 55 | 0 | bone/slider ×10；bone/slider/stone ×4 |
| expert | 2 | 13 | 2:45 | 20 | 11s / 10s（13/13） | 35 / 83 | 1 | bone/slider/stone ×9；bone/slider ×4 |
| expert | 3 | 9 | 4:54 | 24 | 22s / 11s（7/9） | 17 / 96 | 2 | bone/reaper/runner/slider/tracer ×3；bone/floater/runner/slider ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 4 | 8 | 5:12 | 35 | 30s / 16s（7/8） | 54 / 110 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 5 | 7 | 6:15 | 40 | 16s / 12s（5/7） | 56 / 134 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/reaper/runner/slider/tracer ×1 |
| expert | 6 | 2 | 8:34 | 24 | 15s / 15s（2/2） | 10 / 19 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 1 | 9:12 | 21 | 8s / 8s（1/1） | 12 / 12 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 9:00 / 6:18 | 0.0 / - | 8 / 16 / 22 / 24 | - | 83% | 28 | 1390 | 余震 39% 饱和复仇 12% Mon3tr 11% 爆裂黎明 9% | 凯尔希 36% 自身回复 24% 补给 11% (1246 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 0% | 3:45 / 2:56 | 0.0 / - | 8 / 0 / 0 / 12 | - | 33% | 74 | 430 | 熔岩弹 32% 火星 9% 大剑 8% 炮击 8% | 自身回复 30% 拾取 27% 流明 16% (426 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 7:53 / 4:00 | 0.0 / - | 8 / 14 / 21 / 20 | 77% | 66% | 72 | 1040 | 大剑 28% 言 13% 余震 11% 提喻 5% | 自身回复 46% 流明 20% 拾取 12% (1109 / 0.0) | contact_tracer |
| [expert] mizuki | 2 | 50% | 8:09 / 5:09 | 0.0 / - | 6 / 15 / 23 / 21 | 63% | 50% | 50 | 1289 | 提喻 17% 言 15% 刺剑 14% 伞击 12% | 水月 55% 自身回复 20% 塞雷娅 11% (1076 / 0.0) | atk_tracer |
| [expert] saria | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 7 / 14 / 20 / 25 | 33% | 100% | 100 | 1443 | 余震 17% 言 11% 食腐 10% 提喻 6% | 塞雷娅 42% 流明 22% 自身回复 17% (1655 / 0.0) | contact_tracer |
| [expert] kaltsit | 2 | 0% | 4:04 / 2:31 | 0.0 / - | 8 / 14 / 0 / 12 | - | 16% | 1 | 466 | Mon3tr 40% 炮击 10% 双刃 7% 刺剑 7% | 凯尔希 35% 自身回复 22% 结构加固 12% (706 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 0% | 7:31 / 7:14 | 0.0 / - | 8 / 15 / 0 / 20 | 38% | 66% | 33 | 1057 | 狐火 20% 双刃 16% 余震 14% 藏品 8% | 自身回复 27% 塞雷娅 26% 铃兰 19% (881 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 9:00 / 6:18 | 100% | 100% | 1:10 | 0:47 / 2:12 | 2.0 / 81s | 124.2 | 139 | 2 | 10 | 4 | 74% / 42377 | mire |
| [expert] eyjafjalla | 2 | 0% | 3:45 / 2:56 | 50% | 0% | 1:13 | 0:49 / 2:16 | 0.5 / 54s | 10.0 | 141 | 14 | 0 | 0 | 58% / 6372 | atk_reaper |
| [expert] skadi | 2 | 50% | 7:53 / 4:00 | 100% | 50% | 1:09 | 0:50 / 2:54 | 1.0 / 121s | 108.8 | 136 | 32 | 0 | 2 | 50% / 20883 | boss_carmen |
| [expert] mizuki | 2 | 50% | 8:09 / 5:09 | 100% | 100% | 1:09 | 0:49 / 2:32 | 1.5 / 47s | 136.3 | 144 | 18 | 36 | 4 | 26% / 12050 | corrode |
| [expert] saria | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 1:20 | 0:51 / 3:04 | 1.5 / 119s | 172.9 | 125 | 4 | 0 | 3 | 9% / 4540 | boss_paranoia |
| [expert] kaltsit | 2 | 0% | 4:04 / 2:31 | 50% | 50% | 1:19 | 0:59 / 4:04 | 0.5 / 111s | 38.8 | 192 | 19 | 10 | 2 | 53% / 7390 | contact_tracer |
| [expert] suzuran | 2 | 0% | 7:31 / 7:14 | 100% | 100% | 1:07 | 0:51 / 2:37 | 0.5 / 41s | 80.2 | 124 | 23 | 22 | 2 | 25% / 7798 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 2.5 | 1.0% | economy 1/0 general 3/3 heal 1/0 multi 3/1 shield 1/1 survival 2/0 weak 1/0 | 0 |
| expert | kaltsit | 2 | 2.5 | 2.4% | class 1/1 economy 1/0 general 7/3 heal 2/1 weak 1/0 | 0 |
| expert | mizuki | 2 | 9.0 | 0.0% | class 6/3 control 1/1 economy 3/0 general 15/8 heal 1/0 melee 2/1 summon 8/1 survival 7/4 weak 2/0 | 0 |
| expert | saria | 2 | 11.0 | 10.9% | class 2/0 control 1/0 economy 7/2 general 15/4 heal 12/6 melee 5/2 multi 1/0 shield 4/3 survival 13/4 weak 1/1 | 0 |
| expert | skadi | 2 | 9.0 | 0.0% | class 4/1 control 1/1 economy 4/1 general 15/7 heal 3/1 melee 10/4 multi 3/0 shield 2/0 survival 8/3 weak 2/0 | 0 |
| expert | suzuran | 2 | 7.0 | 8.2% | class 3/1 control 5/2 economy 4/4 general 13/3 melee 1/1 summon 1/0 survival 5/3 | 0 |
| expert | wisadel | 2 | 10.0 | 0.0% | class 8/3 control 1/1 economy 7/2 general 13/4 melee 2/1 multi 12/2 shield 1/1 summon 3/1 survival 9/4 weak 2/1 | 0 |
| 合计 | | | | | class 24/9 control 9/5 economy 27/9 general 81/32 heal 19/8 melee 20/9 multi 19/3 shield 8/5 summon 12/2 survival 44/18 weak 9/2 | |

拿取最多（出现 / 拿取）：猎人的口粮 4/3，漆黑的舞鞋 5/3，“小格兰法洛” 6/3，乌萨斯毡毯 3/3，贵族刺剑 3/3，尖叫樱桃 4/2，支援轰隆隆 2/2，生命之水 3/2，热水壶 3/2，支援起重机 4/2，锈刃-神力 4/2，演员的首饰盒 3/2
