# balance summon-reach-1119-kal-off 1119_1121

args: `--op kaltsit --bot expert --seeds 32 --seed0 1 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --bal=summon/reach_fix=0 --tag summon-reach-1119-kal-off --out build/ab/summon-reach-1119/kal_off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 20 | 20 | 19 | 90s / 84s / 142s / 54–144s | 84s / 142s | 7.2 / 3.0 | 21% |
| expert | 最后的骑士 | knight 3 | 3 | 3 | 69s / 55s / 102s / 51–102s | 55s / 102s | 4.7 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 25 | 24 | 60s | 0.54 | 5 | - | - |
| expert | 圣徒卡门 | 16 | 16 | 51s | 0.46 | 5 | - | - |
| expert | 接潮主教 | 12 | 11 | 47s | 0.15 | 5 | 1.1 | 18% |
| expert | 接潮斥亡体 | 8 | 8 | 44s | 0.15 | 7 | - | - |
| expert | 接潮蔑死体 | 4 | 3 | 62s | 0.18 | 7 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 51s | 0.30 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 68% | 31% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 129 / 125 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:06 |
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:46 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:20 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:19 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:38 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:24 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:57 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:12 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:52 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:39 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 81 / 106 | 178 / 319 | 2 / 10 | 359 / 414 | 36 / 48 |
| expert | 0 | 25 | 8:00–10:00 | 68 / 106 | 27 / 50 | 2 / 10 | 367 / 414 | 26 / 45 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 495 | 0.1 | 1.5 / 1.1% | 0.8 / 1.6% | 0.0 / 0.0% | 0.3 |
| expert | 0 | 胜 | 22 | 1092 | 0.2 | 0.4 / 0.2% | 1.4 / 1.6% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（31/32） | 15 / 55 | 1 | bone/slider/stone ×21；bone/slider ×11 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 13 / 66 | 0 | bone/slider ×20；bone/slider/stone ×11 |
| expert | 3 | 30 | 4:40 | 24 | 11s / 9s（30/30） | 28 / 144 | 2 | bone/slider/stone ×7；bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/slider/stone ×6 |
| expert | 4 | 28 | 5:31 | 36 | 13s / 12s（28/28） | 19 / 74 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×8 |
| expert | 5 | 27 | 6:28 | 39 | 13s / 12s（25/27） | 25 / 144 | 2 | bone/floater/reaper/runner/slider/tracer ×10；bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 6 | 25 | 8:00 | 26 | 10s / 9s（25/25） | 34 / 149 | 1 | bone/founder/nest/offspring/runner/slider/stone/tracer ×10；bone/floater/founder/nest/runner/slider/stone/tracer ×9；bone/founder/nest/runner/slider/spitter/stone/tracer ×4 |
| expert | 7 | 20 | 9:01 | 22 | 9s / 9s（20/20） | 34 / 119 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×9；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×5 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit | 32 | 68% | 9:53 / 1:19 | 0.0 / - | 8 / 15 / 23 / 25 | 9% | 88% | 64 | 1635 | Mon3tr 27% Mon3tr · 真伤 7% 余震 6% 终结技·kaltsit·熔毁 5% | 凯尔希 33% 自身回复 22% 结构加固 14% (1004 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit | 32 | 68% | 9:53 / 1:19 | 96% | 87% | 1:07 | 0:53 / 2:56 | 2.1 / 52s | 76.4 | 105 | 3 | 0 | 3 | 37% / 32896 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 32 | 13.8 | 6.5% | class 110/40 control 36/15 economy 111/26 general 343/141 heal 166/66 melee 61/16 multi 41/17 shield 58/30 summon 64/30 survival 145/46 weak 29/14 | 0 |
| 合计 | | | | | class 110/40 control 36/15 economy 111/26 general 343/141 heal 166/66 melee 61/16 multi 41/17 shield 58/30 summon 64/30 survival 145/46 weak 29/14 | |

拿取最多（出现 / 拿取）：血魔的银杯 31/13，“多功能”发夹 27/13，演出用香水 20/12，猎人的口粮 49/11，苍白花冠 13/9，食腐者手杖 36/9，《旧高卢地名源流考》 16/8，遥乡之引 11/8，海程 13/7，残破合影 12/6，药枚 11/6，漆黑的舞鞋 10/6
