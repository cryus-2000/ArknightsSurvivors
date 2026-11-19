# balance summon-reach-1119-sum-on 1119_1129

args: `--squad kaltsit,skalter,ling --bot expert --seeds 32 --seed0 1 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --tag summon-reach-1119-sum-on --out build/ab/summon-reach-1119/sum_on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 17 | 17 | 17 | 70s / 71s / 87s / 50–88s | 71s / 87s | 12.5 / 3.0 | - |
| expert | 最后的骑士 | knight 9 | 9 | 9 | 49s / 49s / 67s / 35–67s | 49s / 67s | 7.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 23 | 22 | 34s | 0.60 | 4 | - | - |
| expert | 塑路者 | 18 | 18 | 42s | 0.62 | 4 | - | - |
| expert | 接潮主教 | 16 | 15 | 33s | 0.21 | 6 | 1.0 | 23% |
| expert | 接潮蔑死体 | 9 | 8 | 34s | 0.24 | 7 | - | - |
| expert | 接潮斥亡体 | 7 | 7 | 33s | 0.18 | 6 | - | - |
| expert | 圣徒伊比利亚 | 5 | 4 | 34s | 0.43 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 81% | 18% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 87 / 79 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 2 | 8:51 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:23 |
| expert | 0 | contact_iberia | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:16 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:20 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:13 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 78 / 97 | 164 / 250 | 0 / 0 | 369 / 425 | 35 / 47 |
| expert | 0 | 28 | 8:00–10:00 | 61 / 78 | 19 / 32 | 0 / 0 | 364 / 425 | 26 / 44 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 6 | 408 | 0.0 | 10.3 / 3.6% | 0.2 / 0.4% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 26 | 1119 | 0.3 | 4.0 / 0.3% | 1.8 / 3.3% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 9s / 9s（32/32） | 10 / 38 | 0 | bone/slider ×19；bone/slider/stone ×13 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 15 / 98 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 3 | 31 | 4:16 | 25 | 9s / 9s（31/31） | 14 / 144 | 1 | bone/floater/runner/slider ×12；bone/slider/stone ×10；bone/offspring/slider/stone ×8 |
| expert | 4 | 30 | 5:06 | 35 | 12s / 12s（30/30） | 15 / 92 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×9 |
| expert | 5 | 30 | 6:15 | 39 | 11s / 10s（30/30） | 20 / 112 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×12；bone/reaper/runner/slider/tracer ×9；bone/floater/reaper/runner/slider/tracer ×9 |
| expert | 6 | 28 | 7:48 | 26 | 9s / 9s（28/28） | 19 / 50 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×11；bone/floater/founder/nest/runner/slider/stone/tracer ×9；bone/founder/nest/offspring/runner/slider/stone/tracer ×8 |
| expert | 7 | 27 | 8:58 | 21 | 9s / 9s（26/27） | 39 / 140 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×16；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×8；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 32 | 81% | 10:17 / 4:20 | 0.0 / - | 8 / 16 / 23 / 27 | 4% | 94% | 44 | 1849 | Mon3tr 28% Mon3tr · 真伤 11% 弦惊·剑势 7% 弦惊·剑气 5% | 凯尔希 37% 自身回复 16% 结构加固 15% (942 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 32 | 81% | 10:17 / 4:20 | 100% | 96% | - | 0:46 / 2:41 | 2.3 / 35s | 83.1 | 92 | 1 | 1 | 3 | 43% / 49675 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 32 | 15.8 | 2.5% | class 69/16 control 51/22 economy 159/54 general 370/180 heal 176/75 melee 49/18 multi 58/19 shield 43/29 summon 62/26 survival 157/57 weak 35/11 | 0 |
| 合计 | | | | | class 69/16 control 51/22 economy 159/54 general 370/180 heal 176/75 melee 49/18 multi 58/19 shield 43/29 summon 62/26 survival 157/57 weak 35/11 | |

拿取最多（出现 / 拿取）：猎人的口粮 39/16，血魔的银杯 26/15，“多功能”发夹 17/11，食腐者手杖 38/11，演出用香水 26/10，海潮的气息 0/10，《旧高卢地名源流考》 15/10，遥乡之引 12/9，涌动之餐 10/8，贵族刺剑 8/6，苍白花冠 25/6，投币玩具 8/6
