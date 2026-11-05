# balance capon_mate 1105_0503

args: `--bot expert --nocache --jobs 8 --preset skalter_mate --seeds 4 --tag capon_mate --out build/cloud/render-skalter-cap1-c4/capon_mate`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 19 | 19 | 11 | 95s / 95s / 105s / 86–106s | 95s / 105s | 20.9 / 2.8 | 27% |
| expert | 最后的骑士 | knight 4 | 4 | 4 | 72s / 71s / 85s / 64–85s | 71s / 85s | 11.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 16 | 15 | 56s | 0.58 | 10 | - | - |
| expert | 圣徒卡门 | 16 | 13 | 46s | 0.51 | 5 | - | - |
| expert | 接潮主教 | 16 | 14 | 66s | 0.12 | 11 | 1.2 | 16% |
| expert | 接潮斥亡体 | 10 | 9 | 43s | 0.15 | 10 | - | - |
| expert | 接潮蔑死体 | 6 | 5 | 84s | 0.17 | 12 | - | - |
| expert | 圣徒伊比利亚 | 5 | 4 | 34s | 0.38 | 11 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.1 / 0.1 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 15 | 0.0 / 0.0 / 0.0 / 0 | 19 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 28 | 53% | 21% | 25% (7) | 30% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 0% | 142 / 128 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:28 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:13 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:03 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:42 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:44 |
| expert | 0 | bullet | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:56 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 101 / 183 | 202 / 320 | 2 / 10 | 390 / 506 | 39 / 48 |
| expert | 0 | 24 | 8:00–10:00 | 81 / 134 | 43 / 134 | 1 / 5 | 388 / 484 | 34 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 13 | 1957 | 0.1 | 0.8 / 0.1% | 0.2 / 0.3% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 15 | 2159 | 0.2 | 0.0 / 0.0% | 1.1 / 2.1% | 0.0 / 0.0% | 0.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 10s / 10s（28/28） | 14 / 38 | 0 | bone/slider ×26；bone/slider/stone ×2 |
| expert | 2 | 28 | 2:45 | 20 | 10s / 10s（28/28） | 21 / 94 | 0 | bone/slider/stone ×26；bone/slider ×2 |
| expert | 3 | 23 | 4:40 | 24 | 15s / 11s（23/23） | 9 / 51 | 0 | bone/slider/stone ×7；bone/offspring/slider/stone ×5；bone/reaper/runner/slider/tracer ×3 |
| expert | 4 | 23 | 5:11 | 35 | 22s / 13s（23/23） | 13 / 116 | 0 | bone/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×8；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 5 | 23 | 6:16 | 39 | 24s / 15s（23/23） | 15 / 79 | 0 | bone/floater/reaper/runner/slider/tracer ×10；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×5 |
| expert | 6 | 21 | 8:10 | 26 | 23s / 12s（21/21） | 17 / 52 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4 |
| expert | 7 | 12 | 8:59 | 22 | 11s / 10s（12/12） | 16 / 27 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel+skalter | 4 | 75% | 10:34 / 8:28 | 0.0 / - | 8 / 16 / 23 / 27 | 28% | 100% | 61 | 1857 | 余震 27% 饱和复仇 10% 爆裂黎明 7% 真实 6% | 自身回复 31% 浊心斯卡蒂 30% 补给 14% (859 / 0.0) | contact_tracer |
| [expert] eyjafjalla+skalter | 4 | 25% | 7:36 / 3:42 | 0.0 / - | 8 / 16 / 23 / 21 | 22% | 66% | 15 | 1243 | 熔岩弹 25% 声浪 9% 火星 8% 终结技·eyjafjalla·熔岩 6% | 自身回复 32% 浊心斯卡蒂 25% 拾取 20% (781 / 0.0) | contact_tracer |
| [expert] skadi+skalter | 4 | 100% | 11:35 / 11:26 | 0.0 / - | 8 / 16 / 23 / 28 | - | 100% | 64 | 1863 | 大剑 26% 锚击 7% 终结技·skadi·浪头 7% 真实 6% | 自身回复 34% 浊心斯卡蒂 32% 补给 12% (1024 / 0.0) | bullet |
| [expert] mizuki+skalter | 4 | 0% | 10:56 / 4:44 | 0.0 / - | 8 / 15 / 20 / 22 | 39% | 66% | 72 | 1237 | 终结技·mizuki·横扫 22% 伞击 19% 触手 13% 声浪 9% | 水月 36% 自身回复 19% 流明 15% (1497 / 0.0) | boss_carmen |
| [expert] saria+skalter | 4 | 25% | 12:41 / 11:44 | 0.0 / - | 8 / 14 / 21 / 26 | 31% | 100% | 62 | 1586 | 终结技·saria·拳风 16% 食腐 7% 声浪 6% 伞击 6% | 塞雷娅 44% 自身回复 20% 浊心斯卡蒂 14% (1247 / 0.0) | boss_carmen |
| [expert] kaltsit+skalter | 4 | 75% | 11:49 / 11:06 | 0.0 / - | 8 / 16 / 22 / 28 | 8% | 100% | 72 | 1894 | Mon3tr 14% 终结技·kaltsit·熔毁 12% Mon3tr · 真伤 7% 声浪 5% | 凯尔希 36% 自身回复 25% 浊心斯卡蒂 13% (1079 / 0.0) | bullet |
| [expert] suzuran+skalter | 4 | 75% | 10:39 / 7:56 | 0.0 / - | 8 / 16 / 22 / 26 | 18% | 100% | 26 | 1808 | 狐火 22% 终结技·suzuran·斩痕 9% 声浪 8% 狐火点点 5% | 浊心斯卡蒂 28% 自身回复 25% 铃兰 16% (1289 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel+skalter | 4 | 75% | 10:34 / 8:28 | 100% | 100% | 1:08 | 0:50 / 2:01 | 2.8 / 41s | 134.0 | 84 | 2 | 0 | 4 | 55% / 49718 | corrode |
| [expert] eyjafjalla+skalter | 4 | 25% | 7:36 / 3:42 | 100% | 50% | 1:04 | 0:44 / 2:40 | 1.2 / 30s | 120.5 | 117 | 17 | 0 | 4 | 49% / 23683 | corrode |
| [expert] skadi+skalter | 4 | 100% | 11:35 / 11:26 | 100% | 100% | 1:18 | 0:50 / 4:13 | 2.8 / 64s | 125.0 | 90 | 0 | 0 | 4 | 45% / 37625 | - |
| [expert] mizuki+skalter | 4 | 0% | 10:56 / 4:44 | 100% | 75% | 1:07 | 0:47 / 2:46 | 1.2 / 103s | 148.3 | 140 | 2 | 0 | 3 | 37% / 16349 | corrode |
| [expert] saria+skalter | 4 | 25% | 12:41 / 11:44 | 100% | 100% | 1:24 | 0:48 / 3:47 | 2.2 / 120s | 149.1 | 96 | 0 | 11 | 4 | 10% / 6763 | corrode |
| [expert] kaltsit+skalter | 4 | 75% | 11:49 / 11:06 | 100% | 100% | 1:34 | 0:48 / 3:01 | 2.5 / 62s | 204.2 | 91 | 0 | 2 | 4 | 26% / 21152 | shock_paranoia |
| [expert] suzuran+skalter | 4 | 75% | 10:39 / 7:56 | 100% | 100% | 1:12 | 0:44 / 2:50 | 2.2 / 45s | 193.4 | 118 | 4 | 17 | 5 | 28% / 19930 | bullet |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 7.5 | 0.0% | class 8/1 control 2/0 economy 11/4 general 22/15 heal 2/1 melee 3/1 multi 11/3 shield 2/0 summon 3/1 survival 9/3 weak 3/1 | 0 |
| expert | kaltsit | 4 | 16.0 | 8.5% | class 16/6 control 4/2 economy 17/5 general 37/13 heal 27/12 melee 7/2 multi 8/0 shield 9/4 summon 7/2 survival 33/15 weak 6/3 | 0 |
| expert | mizuki | 4 | 10.0 | 3.6% | class 8/2 control 1/0 economy 16/9 general 34/8 heal 2/2 melee 5/2 shield 4/0 summon 21/10 survival 12/6 weak 4/1 | 0 |
| expert | saria | 4 | 14.8 | 14.9% | class 16/5 control 8/6 economy 23/7 general 45/15 heal 21/7 melee 9/3 multi 2/0 shield 6/5 summon 7/2 survival 19/7 weak 4/2 | 0 |
| expert | skadi | 4 | 15.8 | 7.0% | class 22/8 control 4/2 economy 22/5 general 44/21 heal 8/2 melee 37/8 multi 10/3 shield 5/3 summon 5/2 survival 20/8 weak 3/1 | 0 |
| expert | suzuran | 4 | 13.2 | 5.2% | class 12/3 control 20/13 economy 14/5 general 37/14 heal 6/0 melee 8/2 multi 4/0 shield 6/3 summon 10/7 survival 16/6 weak 3/0 | 0 |
| expert | wisadel | 4 | 15.0 | 7.9% | class 17/3 control 4/2 economy 19/8 general 48/21 heal 6/0 melee 8/2 multi 21/10 shield 10/4 summon 4/1 survival 22/8 weak 1/1 | 0 |
| 合计 | | | | | class 99/28 control 43/25 economy 122/43 general 267/107 heal 72/24 melee 77/20 multi 56/16 shield 42/19 summon 57/25 survival 131/53 weak 24/9 | |

拿取最多（出现 / 拿取）：《旧高卢地名源流考》 19/9，安洁莉娜的创想 16/9，赶车夫的长鞭 17/7，散轶诗简 14/7，损坏的左轮弹巢 6/6，支柱-援护 13/6，鸭爵金砖 6/6，皇帝的恩宠 22/5，演出用香水 11/5，“小格兰法洛” 7/5，“绽放” 7/4，生还者合约 8/4
