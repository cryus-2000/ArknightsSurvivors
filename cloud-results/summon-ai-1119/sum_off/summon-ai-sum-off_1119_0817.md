# balance summon-ai-sum-off 1119_0817

args: `--squad kaltsit,skalter,ling --bot expert --seeds 16 --seed0 17 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --bal=summon/hunt=0 --bal=summon/cmd=0 --tag summon-ai-sum-off --out build/ab/summon-ai-1119/sum_off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 12 | 12 | 12 | 93s / 100s / 108s / 60–122s | 100s / 108s | 6.1 / 3.0 | - |
| expert | 最后的骑士 | knight 3 | 3 | 3 | 56s / 64s / 66s / 40–66s | 64s / 66s | 6.1 / 2.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 3.0 / 2.0 | 14% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 14 | 14 | 32s | 0.21 | 6 | 1.0 | 11% |
| expert | 圣徒卡门 | 9 | 9 | 51s | 0.55 | 3 | - | - |
| expert | 接潮蔑死体 | 8 | 8 | 36s | 0.21 | 6 | - | - |
| expert | 塑路者 | 8 | 8 | 48s | 0.64 | 4 | - | - |
| expert | 接潮斥亡体 | 6 | 6 | 31s | 0.20 | 6 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 30s | 0.42 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 93% | 6% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 92 / 85 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_ishar | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:02 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 89 / 104 | 212 / 312 | 0 / 0 | 387 / 419 | 37 / 48 |
| expert | 0 | 16 | 8:00–10:00 | 69 / 87 | 22 / 32 | 0 / 0 | 375 / 406 | 29 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 442 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 15 | 1088 | 0.5 | 0.1 / 0.2% | 1.0 / 2.3% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 9s（16/16） | 8 / 17 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| expert | 2 | 16 | 2:45 | 20 | 9s / 8s（16/16） | 9 / 34 | 0 | bone/slider ×11；bone/slider/stone ×5 |
| expert | 3 | 16 | 4:28 | 25 | 10s / 10s（16/16） | 11 / 33 | 0 | bone/floater/runner/slider ×8；bone/slider/stone ×3；bone/offspring/slider/stone ×3 |
| expert | 4 | 16 | 5:18 | 36 | 15s / 15s（16/16） | 23 / 92 | 0 | bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×3 |
| expert | 5 | 16 | 6:17 | 39 | 14s / 11s（16/16） | 10 / 29 | 0 | bone/reaper/runner/slider/tracer ×8；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 6 | 16 | 7:49 | 26 | 10s / 10s（16/16） | 11 / 45 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4 |
| expert | 7 | 15 | 8:57 | 22 | 10s / 10s（15/15） | 25 / 78 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 93% | 11:24 / 10:40 | 0.0 / - | 8 / 16 / 23 / 28 | 1% | 100% | 54 | 1968 | Mon3tr 22% Mon3tr · 真伤 10% 弦惊·剑势 9% 弦惊·剑气 5% | 凯尔希 38% 自身回复 16% 浊心斯卡蒂 15% (955 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 93% | 11:24 / 10:40 | 100% | 100% | - | 0:45 / 2:37 | 2.9 / 40s | 80.4 | 83 | 1 | 0 | 4 | 34% / 40744 | boss_ishar |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 16 | 17.6 | 5.5% | class 39/12 control 22/13 economy 89/27 general 204/78 heal 95/37 melee 29/9 multi 29/12 shield 37/21 summon 39/22 survival 108/41 weak 16/9 | 0 |
| 合计 | | | | | class 39/12 control 22/13 economy 89/27 general 204/78 heal 95/37 melee 29/9 multi 29/12 shield 37/21 summon 39/22 survival 108/41 weak 16/9 | |

拿取最多（出现 / 拿取）：《旧高卢地名源流考》 15/8，苍白花冠 13/7，血魔的银杯 15/7，食腐者手杖 17/6，遥乡之引 7/6，药枚 9/6，猎人的口粮 28/5，安洁莉娜的创想 12/5，“多功能”发夹 8/5，炸裂之手 5/5，演出用香水 11/4，乌萨斯毡毯 7/4
