# balance summon-reach2-1119-sum-off 1119_1223

args: `--squad kaltsit,skalter,ling --bot expert --seeds 32 --seed0 1 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --bal=summon/reach_fix=0 --tag summon-reach2-1119-sum-off --out build/ab/summon-reach2-1119/sum_off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 25 | 25 | 25 | 78s / 76s / 92s / 57–108s | 76s / 92s | 10.3 / 2.9 | - |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 66s / 66s / 66s / 66–66s | 66s / 66s | 7.6 / 2.0 | 3% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 23s / 23s / 23s / 23–23s | 23s / 23s | 9.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 21 | 21 | 45s | 0.62 | 4 | - | - |
| expert | 圣徒卡门 | 19 | 18 | 44s | 0.56 | 4 | - | - |
| expert | 接潮主教 | 18 | 18 | 32s | 0.21 | 6 | 1.3 | 28% |
| expert | 接潮蔑死体 | 12 | 12 | 32s | 0.23 | 7 | - | - |
| expert | 接潮斥亡体 | 6 | 6 | 32s | 0.19 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 28s | 0.46 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 84% | 15% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 105 / 99 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:42 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:24 |
| expert | 0 | contact_founder | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:26 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| expert | 0 | dark | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:45 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 81 / 95 | 206 / 250 | 0 / 0 | 371 / 409 | 35 / 48 |
| expert | 0 | 28 | 8:00–10:00 | 65 / 78 | 24 / 43 | 0 / 0 | 376 / 409 | 29 / 41 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 5 | 360 | 0.2 | 0.8 / 0.7% | 1.8 / 13.5% | 0.0 / 0.0% | 1.2 |
| expert | 0 | 胜 | 27 | 1199 | 0.3 | 3.4 / 0.3% | 1.6 / 2.2% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 9s / 9s（32/32） | 10 / 33 | 0 | bone/slider/stone ×17；bone/slider ×15 |
| expert | 2 | 32 | 2:45 | 20 | 9s / 9s（32/32） | 17 / 79 | 0 | bone/slider ×17；bone/slider/stone ×15 |
| expert | 3 | 31 | 4:25 | 25 | 11s / 10s（31/31） | 16 / 137 | 1 | bone/floater/runner/slider ×10；bone/slider/stone ×9；bone/offspring/slider/stone ×8 |
| expert | 4 | 30 | 5:14 | 36 | 13s / 12s（30/30） | 22 / 118 | 0 | bone/floater/reaper/runner/slider/tracer ×12；bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/reaper/runner/slider/tracer ×8 |
| expert | 5 | 30 | 6:16 | 39 | 12s / 12s（28/30） | 28 / 150 | 2 | bone/floater/reaper/runner/slider/tracer ×11；bone/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×9 |
| expert | 6 | 28 | 7:48 | 26 | 9s / 8s（28/28） | 21 / 65 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×11；bone/founder/nest/offspring/runner/slider/stone/tracer ×11；bone/founder/nest/runner/slider/spitter/stone/tracer ×6 |
| expert | 7 | 27 | 8:57 | 21 | 10s / 9s（27/27） | 29 / 127 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×12；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×8；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×7 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 32 | 84% | 10:32 / 4:45 | 0.0 / - | 8 / 16 / 23 / 27 | 0% | 94% | 53 | 1836 | Mon3tr 24% Mon3tr · 真伤 9% 弦惊·剑势 7% 泼墨 6% | 凯尔希 37% 自身回复 16% 结构加固 14% (1050 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+skalter+ling | 32 | 84% | 10:32 / 4:45 | 100% | 93% | - | 0:46 / 2:51 | 2.4 / 38s | 83.2 | 100 | 1 | 0 | 3 | 37% / 41229 | contact_founder |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 32 | 16.2 | 4.5% | class 87/23 control 43/23 economy 144/55 general 388/157 heal 205/81 melee 69/26 multi 62/19 shield 52/27 summon 75/41 survival 149/57 weak 33/8 | 0 |
| 合计 | | | | | class 87/23 control 43/23 economy 144/55 general 388/157 heal 205/81 melee 69/26 multi 62/19 shield 52/27 summon 75/41 survival 149/57 weak 33/8 | |

拿取最多（出现 / 拿取）：血魔的银杯 30/16，猎人的口粮 61/15，遥乡之引 17/14，《旧高卢地名源流考》 19/11，演出用香水 25/11，“多功能”发夹 19/10，衍生者终端-超级改 18/9，苍白花冠 27/9，食腐者手杖 36/9，涌动之餐 9/7，游戏室管理员权限卡 11/7，扣挠之手 7/7
