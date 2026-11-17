# balance opb-wisadel-1118a-mate-kaltsit 1117_1758

args: `--squad kaltsit,wisadel --bot expert --seeds 4 --nocache --jobs 8 --tag opb-wisadel-1118a-mate-kaltsit --out build/cloud/opb-wisadel-1118a/mate_kaltsit --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 最后的骑士 | knight 2 | 2 | 1 | 81s / 81s / 81s / 81–81s | 81s / 81s | 1.5 / 1.0 | 89% |
| expert | 偏执泡影 | standard 2 | 2 | 2 | 100s / 100s / 112s / 88–112s | 100s / 112s | 4.0 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 4 | 4 | 54s | 0.14 | 9 | 1.0 | 7% |
| expert | 接潮蔑死体 | 3 | 3 | 54s | 0.11 | 10 | - | - |
| expert | 圣徒卡门 | 2 | 2 | 86s | 0.39 | 6 | - | - |
| expert | 塑路者 | 2 | 2 | 71s | 0.55 | 6 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 25s | 0.21 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 18 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 75% | 25% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 153 / 132 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:16 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 82 / 92 | 171 / 250 | 2 / 10 | 398 / 413 | 45 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 72 / 85 | 26 / 37 | 2 / 8 | 366 / 403 | 31 / 40 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 1558 | 0.0 | 0.0 / 0.0% | 2.0 / 2.3% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 3 | 992 | 0.0 | 0.0 / 0.0% | 0.3 / 0.4% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 9s / 8s（4/4） | 11 / 16 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 9s / 9s（4/4） | 13 / 35 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 4 | 5:01 | 24 | 10s / 10s（4/4） | 28 / 40 | 0 | bone/reaper/runner/slider/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1；bone/slider/stone ×1 |
| expert | 4 | 4 | 5:51 | 38 | 13s / 14s（4/4） | 39 / 66 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/floater/reaper/runner/slider/tracer ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 6:59 | 38 | 23s / 24s（4/4） | 21 / 44 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/floater/reaper/runner/slider/tracer ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 4 | 8:15 | 26 | 11s / 10s（4/4） | 52 / 92 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 2 | 9:05 | 22 | 8s / 8s（2/2） | 0 / 1 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+wisadel | 4 | 75% | 11:14 / 10:16 | 0.0 / - | 8 / 14 / 22 / 28 | 44% | 100% | 50 | 1872 | 余震 21% Mon3tr 17% Mon3tr · 真伤 8% 饱和复仇 6% | 凯尔希 32% 自身回复 21% 结构加固 19% (1289 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+wisadel | 4 | 75% | 11:14 / 10:16 | 100% | 100% | 1:07 | 0:45 / 4:33 | 3.0 / 59s | 92.0 | 120 | 1 | 0 | 3 | 28% / 36233 | boss_knight_boss |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 4 | 17.8 | 7.4% | class 12/3 control 10/5 economy 22/9 general 58/24 heal 21/8 melee 10/2 multi 3/0 shield 7/3 summon 5/3 survival 23/12 weak 4/2 | 0 |
| 合计 | | | | | class 12/3 control 10/5 economy 22/9 general 58/24 heal 21/8 melee 10/2 multi 3/0 shield 7/3 summon 5/3 survival 23/12 weak 4/2 | |

拿取最多（出现 / 拿取）：铸阳巨械 1/2，悬丝傀儡 2/2，“绝唱” 3/2，《旧高卢地名源流考》 3/2，海潮的气息 0/2，苍白花冠 4/2，便携经书 3/2，“海洋的脉搏” 2/2，疗养体验卡 2/2，演员的首饰盒 1/1，贵族刺剑 2/1，演出用香水 2/1
