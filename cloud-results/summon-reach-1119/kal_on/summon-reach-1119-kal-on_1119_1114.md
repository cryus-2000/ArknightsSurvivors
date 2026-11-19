# balance summon-reach-1119-kal-on 1119_1114

args: `--op kaltsit --bot expert --seeds 32 --seed0 1 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --tag summon-reach-1119-kal-on --out build/ab/summon-reach-1119/kal_on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 21 | 21 | 20 | 79s / 76s / 105s / 58–105s | 76s / 105s | 8.4 / 2.9 | 22% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 82s / 82s / 82s / 82–82s | 62s / 62s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 61s / 61s / 61s / 61–61s | 61s / 61s | 3.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 21 | 19 | 35s | 0.59 | 6 | - | - |
| expert | 塑路者 | 18 | 17 | 59s | 0.52 | 5 | - | - |
| expert | 接潮主教 | 14 | 13 | 36s | 0.17 | 6 | 1.0 | 20% |
| expert | 接潮斥亡体 | 7 | 6 | 36s | 0.18 | 7 | - | - |
| expert | 接潮蔑死体 | 7 | 7 | 36s | 0.21 | 7 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 52s | 0.29 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 68% | 31% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 134 / 122 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:07 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:23 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:19 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:31 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:56 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:09 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:30 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:57 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:09 |
| expert | 0 | contact_founder | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:46 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 79 / 95 | 191 / 313 | 1 / 9 | 349 / 424 | 33 / 48 |
| expert | 0 | 24 | 8:00–10:00 | 68 / 83 | 24 / 42 | 1 / 9 | 366 / 424 | 23 / 45 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 404 | 0.0 | 0.6 / 0.7% | 0.2 / 0.3% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 22 | 1395 | 0.0 | 1.7 / 0.2% | 0.7 / 0.7% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 10s（31/32） | 14 / 75 | 1 | bone/slider/stone ×22；bone/slider ×10 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 17 / 69 | 0 | bone/slider ×21；bone/slider/stone ×10 |
| expert | 3 | 28 | 4:31 | 24 | 11s / 9s（27/28） | 26 / 171 | 2 | bone/floater/runner/slider ×10；bone/slider/stone ×7；bone/offspring/slider/stone ×4 |
| expert | 4 | 26 | 5:21 | 36 | 14s / 14s（25/26） | 28 / 137 | 1 | bone/floater/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/reaper/runner/slider/tracer ×8 |
| expert | 5 | 25 | 6:22 | 39 | 14s / 13s（25/25） | 26 / 86 | 0 | bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×8；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 6 | 24 | 7:54 | 26 | 9s / 9s（24/24） | 33 / 135 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×11；bone/founder/nest/offspring/runner/slider/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×5 |
| expert | 7 | 23 | 9:04 | 22 | 10s / 9s（23/23） | 34 / 138 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×10；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×7；bone/floater/offspring/reaper/runner/slider/spitter/stone ×6 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit | 32 | 68% | 9:36 / 1:19 | 0.0 / - | 8 / 16 / 23 / 25 | 6% | 82% | 66 | 1616 | Mon3tr 30% Mon3tr · 真伤 8% 终结技·kaltsit·熔毁 5% 余震 4% | 凯尔希 33% 自身回复 24% 结构加固 16% (1094 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit | 32 | 68% | 9:36 / 1:19 | 96% | 87% | 1:07 | 0:53 / 3:14 | 2.0 / 45s | 90.9 | 115 | 2 | 3 | 4 | 42% / 35576 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 32 | 13.3 | 4.9% | class 93/34 control 27/12 economy 118/40 general 334/131 heal 168/58 melee 59/24 multi 51/21 shield 40/20 summon 50/27 survival 131/47 weak 19/11 | 0 |
| 合计 | | | | | class 93/34 control 27/12 economy 118/40 general 334/131 heal 168/58 melee 59/24 multi 51/21 shield 40/20 summon 50/27 survival 131/47 weak 19/11 | |

拿取最多（出现 / 拿取）：演出用香水 26/14，食腐者手杖 35/11，猎人的口粮 42/9，“多功能”发夹 15/9，血魔的银杯 29/7，遥乡之引 13/7，显圣吊坠 15/7，“苦痛的快乐” 7/7，皇帝的恩宠 16/6，涌动之餐 10/6，《旧高卢地名源流考》 15/6，净尘之手 6/6
