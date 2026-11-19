# balance summon-ai-sum-on 1119_0805

args: `--squad kaltsit,skalter,ling --bot expert --seeds 16 --seed0 17 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --tag summon-ai-sum-on --out build/ab/summon-ai-1119/sum_on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 12 | 12 | 12 | 76s / 73s / 95s / 57–108s | 74s / 95s | 10.6 / 2.8 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 23s / 23s / 23s / 23–23s | 23s / 23s | 9.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 13 | 12 | 44s | 0.56 | 4 | - | - |
| expert | 塑路者 | 9 | 9 | 41s | 0.53 | 5 | - | - |
| expert | 接潮主教 | 7 | 7 | 28s | 0.22 | 7 | 1.5 | 32% |
| expert | 接潮蔑死体 | 6 | 6 | 28s | 0.25 | 7 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 78s | 0.19 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 81% | 18% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 108 / 117 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_founder | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:26 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| expert | 0 | dark | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:45 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 79 / 89 | 199 / 250 | 0 / 0 | 363 / 403 | 34 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 65 / 75 | 27 / 43 | 0 / 0 | 376 / 403 | 30 / 40 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 3 | 262 | 0.0 | 0.7 / 0.8% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 13 | 1118 | 0.2 | 2.2 / 0.3% | 1.2 / 2.0% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 9s / 9s（16/16） | 10 / 28 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 16 | 2:45 | 20 | 8s / 8s（16/16） | 16 / 73 | 0 | bone/slider ×10；bone/slider/stone ×6 |
| expert | 3 | 15 | 4:24 | 25 | 10s / 9s（15/15） | 22 / 137 | 1 | bone/floater/runner/slider ×5；bone/slider/stone ×5；bone/offspring/slider/stone ×3 |
| expert | 4 | 14 | 5:13 | 36 | 13s / 12s（14/14） | 28 / 118 | 0 | bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/reaper/runner/slider/tracer ×2 |
| expert | 5 | 14 | 6:15 | 39 | 13s / 13s（13/14） | 38 / 150 | 1 | bone/reaper/runner/slider/tracer ×6；bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 6 | 13 | 7:50 | 26 | 9s / 8s（13/13） | 19 / 65 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×6；bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 12 | 8:56 | 22 | 9s / 9s（12/12） | 27 / 127 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×8；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 81% | 10:06 / 4:45 | 0.0 / - | 8 / 16 / 23 / 26 | 0% | 89% | 46 | 1746 | Mon3tr 26% Mon3tr · 真伤 8% 弦惊·剑势 7% 泼墨 6% | 凯尔希 36% 自身回复 17% 结构加固 14% (979 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 81% | 10:06 / 4:45 | 100% | 87% | - | 0:46 / 2:59 | 2.2 / 38s | 77.3 | 99 | 1 | 1 | 3 | 37% / 38785 | contact_reaper |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 16 | 15.2 | 3.8% | class 33/10 control 17/10 economy 72/31 general 190/74 heal 98/36 melee 36/15 multi 31/8 shield 25/11 summon 35/17 survival 71/26 weak 12/5 | 0 |
| 合计 | | | | | class 33/10 control 17/10 economy 72/31 general 190/74 heal 98/36 melee 36/15 multi 31/8 shield 25/11 summon 35/17 survival 71/26 weak 12/5 | |

拿取最多（出现 / 拿取）：血魔的银杯 15/7，猎人的口粮 35/7，演出用香水 11/6，“多功能”发夹 10/6，食腐者手杖 16/6，遥乡之引 6/5，扣挠之手 5/5，苍白花冠 11/4，皇帝的恩宠 11/4，蓝卡坞安全衣 5/4，摩根队长佳酿 8/4，净尘之手 4/4
