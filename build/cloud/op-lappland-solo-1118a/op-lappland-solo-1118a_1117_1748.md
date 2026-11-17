# balance op-lappland-solo-1118a 1117_1748

args: `--op lappland --bot expert --seeds 16 --nocache --jobs 8 --tag op-lappland-solo-1118a --out build/cloud/op-lappland-solo-1118a`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 7 | 7 | 6 | 105s / 115s / 129s / 65–129s | 116s / 129s | 3.9 / 3.0 | 24% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 49s / 49s / 49s / 49–49s | 29s / 29s | 3.0 / 2.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 123s / 123s / 123s / 123–123s | 123s / 123s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 10 | 8 | 64s | 0.31 | 8 | - | - |
| expert | 塑路者 | 9 | 7 | 88s | 0.40 | 10 | - | - |
| expert | 接潮主教 | 6 | 4 | 64s | 0.10 | 9 | 1.2 | 12% |
| expert | 接潮斥亡体 | 3 | 2 | 51s | 0.14 | 11 | - | - |
| expert | 接潮蔑死体 | 3 | 2 | 106s | 0.13 | 10 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 59s | 0.29 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 15 | 0.0 / 0.0 / 0.0 / 0 | 18 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 50% | 43% | 6% (1) | 24% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 152 / 144 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 7:17 |
| expert | 0 | contact_founder | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:48 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:51 |
| expert | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:22 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 1:33 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:26 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:02 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 83 / 120 | 152 / 277 | 0 / 4 | 360 / 459 | 41 / 48 |
| expert | 0 | 10 | 8:00–10:00 | 73 / 91 | 39 / 103 | 0 / 0 | 360 / 408 | 32 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 8 | 556 | 0.2 | 3.5 / 0.3% | 2.4 / 3.0% | 0.0 / 0.0% | 0.4 |
| expert | 0 | 胜 | 8 | 1091 | 0.4 | 0.0 / 0.0% | 1.6 / 2.6% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 12s / 10s（16/16） | 19 / 129 | 1 | bone/slider ×8；bone/slider/stone ×8 |
| expert | 2 | 15 | 2:45 | 20 | 10s / 9s（15/15） | 13 / 31 | 0 | bone/slider/stone ×8；bone/slider ×7 |
| expert | 3 | 12 | 5:10 | 24 | 13s / 12s（12/12） | 18 / 109 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×3；bone/offspring/slider/stone ×1 |
| expert | 4 | 12 | 6:00 | 38 | 18s / 14s（11/12） | 15 / 46 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 5 | 10 | 6:59 | 38 | 23s / 14s（10/10） | 40 / 151 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/reaper/runner/slider/tracer ×1 |
| expert | 6 | 8 | 8:13 | 25 | 10s / 10s（8/8） | 29 / 73 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |
| expert | 7 | 4 | 8:57 | 21 | 10s / 10s（4/4） | 14 / 54 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] lappland | 16 | 50% | 9:21 / 1:33 | 0.0 / - | 8 / 15 / 22 / 23 | 32% | 72% | 68 | 1388 | 双刃 19% 剑气 8% 终结技·lappland·剑气 6% 拳击 6% | 自身回复 31% 塞雷娅 15% 补给 11% (930 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] lappland | 16 | 50% | 9:21 / 1:33 | 93% | 93% | 1:01 | 0:50 / 3:11 | 1.6 / 76s | 64.5 | 108 | 5 | 5 | 4 | 32% / 22233 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | lappland | 16 | 11.4 | 4.0% | class 65/21 control 17/9 economy 55/21 general 115/56 heal 11/2 melee 68/24 multi 14/2 shield 20/11 summon 22/12 survival 63/23 weak 6/2 | 0 |
| 合计 | | | | | class 65/21 control 17/9 economy 55/21 general 115/56 heal 11/2 melee 68/24 multi 14/2 shield 20/11 summon 22/12 survival 63/23 weak 6/2 | |

拿取最多（出现 / 拿取）：漆黑的舞鞋 12/6，锈蚀刀片 13/6，赶车夫的长鞭 10/5，药枚 7/5，《光耀卡西米尔》 4/4，皇帝的恩宠 23/3，支柱-勤奋 3/3，安洁莉娜的创想 6/3，锈刃-可视静谧 4/3，胎生百合 4/3，万能钥匙 4/3，舞者手链 3/3
