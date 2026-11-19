# balance summon-ai-sum-on 1119_0800

args: `--squad kaltsit,skalter,ling --bot expert --seeds 16 --seed0 1 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --tag summon-ai-sum-on --out build/ab/summon-ai-1119/sum_on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 14 | 14 | 14 | 77s / 77s / 92s / 57–94s | 77s / 92s | 10.4 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 66s / 66s / 66s / 66–66s | 66s / 66s | 6.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 11 | 11 | 50s | 0.62 | 4 | - | - |
| expert | 接潮主教 | 10 | 10 | 30s | 0.22 | 6 | 1.2 | 25% |
| expert | 圣徒卡门 | 8 | 8 | 41s | 0.59 | 4 | - | - |
| expert | 接潮蔑死体 | 5 | 5 | 33s | 0.21 | 7 | - | - |
| expert | 接潮斥亡体 | 5 | 5 | 28s | 0.19 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 28s | 0.46 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 93% | 6% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 102 / 84 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:24 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 83 / 95 | 224 / 250 | 0 / 0 | 383 / 397 | 37 / 48 |
| expert | 0 | 15 | 8:00–10:00 | 66 / 78 | 22 / 31 | 0 / 0 | 377 / 389 | 29 / 43 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 102 | 0.0 | 2.0 / 2.6% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 15 | 1300 | 0.4 | 2.4 / 0.2% | 1.5 / 2.0% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 9s / 9s（16/16） | 11 / 33 | 0 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 2 | 16 | 2:45 | 20 | 9s / 9s（16/16） | 18 / 79 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 3 | 16 | 4:25 | 24 | 12s / 11s（16/16） | 13 / 64 | 0 | bone/slider/stone ×6；bone/floater/runner/slider ×4；bone/offspring/slider/stone ×4 |
| expert | 4 | 16 | 5:15 | 36 | 12s / 12s（16/16） | 17 / 76 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/reaper/runner/slider/tracer ×5 |
| expert | 5 | 16 | 6:17 | 39 | 11s / 11s（15/16） | 20 / 141 | 1 | bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 15 | 7:47 | 26 | 9s / 9s（15/15） | 26 / 62 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4 |
| expert | 7 | 15 | 8:57 | 21 | 10s / 10s（15/15） | 24 / 43 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×7；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 93% | 10:58 / 6:24 | 0.0 / - | 8 / 16 / 24 / 28 | 0% | 100% | 61 | 1927 | Mon3tr 24% Mon3tr · 真伤 11% 弦惊·剑势 8% 墨龙 6% | 凯尔希 37% 自身回复 16% 结构加固 15% (1147 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 16 | 93% | 10:58 / 6:24 | 100% | 100% | - | 0:46 / 2:39 | 2.6 / 37s | 92.2 | 102 | 0 | 1 | 4 | 37% / 44245 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 16 | 16.6 | 5.5% | class 50/9 control 21/12 economy 73/25 general 195/86 heal 111/45 melee 32/10 multi 25/9 shield 25/15 summon 35/23 survival 77/27 weak 20/4 | 0 |
| 合计 | | | | | class 50/9 control 21/12 economy 73/25 general 195/86 heal 111/45 melee 32/10 multi 25/9 shield 25/15 summon 35/23 survival 77/27 weak 20/4 | |

拿取最多（出现 / 拿取）：血魔的银杯 17/9，猎人的口粮 26/9，《旧高卢地名源流考》 11/8，遥乡之引 10/8，衍生者终端-超级改 11/8，苍白花冠 21/6，涌动之餐 4/5，游戏室管理员权限卡 8/5，海程 9/5，演出用香水 12/5，疗养体验卡 6/4，教堂救济餐券 4/4
