# balance opb-eyjafjalla-1118a-mate-kaltsit 1117_1749

args: `--squad kaltsit,eyjafjalla --bot expert --seeds 4 --nocache --jobs 8 --tag opb-eyjafjalla-1118a-mate-kaltsit --out build/cloud/opb-eyjafjalla-1118a/mate_kaltsit --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 2 | 2 | 2 | 80s / 80s / 80s / 80–80s | 80s / 80s | 11.6 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 3 | 3 | 60s | 0.54 | 7 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 34s | 0.44 | 6 | - | - |
| expert | 圣徒卡门 | 2 | 1 | 83s | 0.39 | 4 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 50% | 50% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 146 / 154 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:44 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:56 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 78 / 97 | 140 / 244 | 4 / 5 | 333 / 432 | 34 / 48 |
| expert | 0 | 3 | 8:00–10:00 | 68 / 72 | 23 / 24 | 1 / 1 | 370 / 432 | 32 / 44 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 2 | 1018 | 0.0 | 1.5 / 0.8% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 2 | 1304 | 0.0 | 0.0 / 0.0% | 1.0 / 1.4% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 8s / 8s（4/4） | 15 / 18 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 10s / 10s（4/4） | 18 / 33 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 3 | 4:48 | 24 | 10s / 10s（3/3） | 42 / 85 | 0 | bone/floater/runner/slider ×1；bone/floater/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 4 | 3 | 5:38 | 38 | 17s / 17s（3/3） | 42 / 125 | 0 | bone/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 5 | 3 | 6:28 | 38 | 25s / 14s（3/3） | 15 / 43 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 6 | 3 | 7:49 | 26 | 8s / 8s（3/3） | 33 / 87 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 2 | 8:57 | 22 | 9s / 9s（2/2） | 23 / 36 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+eyjafjalla | 4 | 50% | 9:05 / 4:56 | 0.0 / - | 8 / 15 / 22 / 24 | 0% | 91% | 61 | 1505 | Mon3tr 31% 熔岩弹 11% Mon3tr · 真伤 8% 终结技·kaltsit·熔毁 5% | 凯尔希 35% 自身回复 23% 结构加固 15% (992 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+eyjafjalla | 4 | 50% | 9:05 / 4:56 | 100% | 75% | 1:17 | 0:47 / 2:04 | 1.5 / 52s | 91.8 | 116 | 4 | 8 | 4 | 43% / 30825 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 4 | 11.2 | 8.2% | class 15/4 control 3/1 economy 10/2 general 26/15 heal 11/5 melee 5/4 multi 2/1 shield 6/3 summon 9/1 survival 16/6 weak 5/3 | 0 |
| 合计 | | | | | class 15/4 control 3/1 economy 10/2 general 26/15 heal 11/5 melee 5/4 multi 2/1 shield 6/3 summon 9/1 survival 16/6 weak 5/3 | |

拿取最多（出现 / 拿取）：食腐者手杖 3/3，“多功能”发夹 3/2，漆黑的舞鞋 2/2，荣耀绶带 2/2，演出用香水 3/1，赶车夫的长鞭 2/1，教堂救济餐券 1/1，断杖-织法者 1/1，断杖-智慧之光 1/1，恐鱼干 2/1，显圣吊坠 1/1，深洋主宰刻像 3/1
