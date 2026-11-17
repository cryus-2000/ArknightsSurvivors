# balance opb-saria-1118a-lead 1117_1755

args: `--op saria --bot expert --seeds 16 --nocache --jobs 8 --tag opb-saria-1118a-lead --out build/cloud/opb-saria-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 9 | 125s / 120s / 179s / 80–179s | 120s / 179s | 2.8 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 11 | 11 | 60s | 0.45 | 13 | - | - |
| expert | 圣徒卡门 | 10 | 9 | 103s | 0.32 | 9 | - | - |
| expert | 接潮主教 | 8 | 5 | 77s | 0.08 | 10 | 1.2 | 12% |
| expert | 接潮蔑死体 | 4 | 4 | 118s | 0.14 | 12 | - | - |
| expert | 接潮斥亡体 | 4 | 1 | 55s | 0.11 | 22 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 33s | 0.37 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 12 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 56% | 43% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 139 / 124 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:03 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:18 |
| expert | 0 | nest | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:15 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:51 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:19 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:07 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:01 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 100 / 135 | 174 / 320 | 1 / 10 | 445 / 480 | 44 / 48 |
| expert | 0 | 10 | 8:00–10:00 | 79 / 103 | 40 / 67 | 1 / 5 | 371 / 433 | 35 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 893 | 0.0 | 14.0 / 1.5% | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 9 | 1565 | 0.4 | 4.1 / 0.1% | 2.4 / 2.7% | 0.0 / 0.0% | 0.7 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 12s / 12s（16/16） | 10 / 33 | 0 | bone/slider ×8；bone/slider/stone ×8 |
| expert | 2 | 16 | 2:45 | 20 | 10s / 10s（16/16） | 7 / 27 | 0 | bone/slider/stone ×8；bone/slider ×8 |
| expert | 3 | 15 | 5:13 | 25 | 14s / 14s（15/15） | 33 / 81 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×3；bone/slider/stone ×2 |
| expert | 4 | 13 | 5:54 | 37 | 23s / 14s（12/13） | 26 / 114 | 1 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 5 | 11 | 6:58 | 39 | 26s / 27s（10/11） | 20 / 83 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 6 | 9 | 8:24 | 25 | 15s / 11s（8/9） | 31 / 120 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |
| expert | 7 | 4 | 9:13 | 22 | 13s / 13s（3/4） | 68 / 174 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 16 | 56% | 9:58 / 6:15 | 0.0 / - | 7 / 15 / 21 / 24 | 32% | 87% | 53 | 1458 | 终结技·saria·拳风 9% 剑气 8% 拳击 8% 余震 6% | 塞雷娅 47% 自身回复 21% 针剂回流 8% (1215 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 16 | 56% | 9:58 / 6:15 | 100% | 100% | 1:07 | 0:51 / 3:47 | 1.9 / 86s | 91.1 | 126 | 4 | 9 | 4 | 10% / 7597 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | saria | 16 | 10.6 | 3.9% | class 49/9 control 7/4 economy 51/22 general 137/57 heal 79/28 melee 26/12 multi 16/3 shield 23/7 summon 25/8 survival 49/17 weak 5/2 | 0 |
| 合计 | | | | | class 49/9 control 7/4 economy 51/22 general 137/57 heal 79/28 melee 26/12 multi 16/3 shield 23/7 summon 25/8 survival 49/17 weak 5/2 | |

拿取最多（出现 / 拿取）：猎人的口粮 20/6，遥乡之引 8/6，锈蚀刀片 8/5，血魔的银杯 19/5，苍白花冠 10/4，《旧高卢地名源流考》 11/4，鸭爵金砖 4/4，“国王的水晶” 5/3，赤金的远征 6/3，食腐者手杖 15/3，神音海螺 5/3，贵族刺剑 7/3
