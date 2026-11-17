# balance op-phantom-solo-1118f 1117_1955

args: `--op phantom --bot expert --seeds 16 --nocache --jobs 8 --tag op-phantom-solo-1118f --out build/cloud/op-phantom-solo-1118f`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 13 | 13 | 12 | 80s / 78s / 98s / 48–120s | 78s / 98s | 8.5 / 3.0 | 1% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 12 | 52s | 0.59 | 7 | - | - |
| expert | 塑路者 | 9 | 9 | 38s | 0.51 | 8 | - | - |
| expert | 接潮主教 | 7 | 7 | 32s | 0.26 | 9 | 1.2 | 18% |
| expert | 接潮斥亡体 | 6 | 6 | 29s | 0.23 | 9 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 71s | 0.29 | 12 | - | - |
| expert | 圣徒伊比利亚 | 1 | 0 | - | 0.13 | 18 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.1 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 75% | 18% | 6% (1) | 1% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 47 / 26 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:41 |
| expert | 0 | contact_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:06 |
| expert | 0 | contact_founder | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:37 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 84 / 97 | 217 / 320 | 3 / 9 | 358 / 404 | 34 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 69 / 85 | 34 / 85 | 2 / 8 | 366 / 404 | 27 / 41 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 4 | 244 | 0.2 | 1.0 / 2.9% | 1.2 / 6.3% | 0.0 / 0.0% | 0.5 |
| expert | 0 | 胜 | 12 | 662 | 0.1 | 3.7 / 0.2% | 1.3 / 2.8% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 11s（15/16） | 4 / 31 | 1 | bone/slider ×8；bone/slider/stone ×8 |
| expert | 2 | 15 | 2:45 | 20 | 9s / 9s（15/15） | 2 / 23 | 0 | bone/slider/stone ×8；bone/slider ×7 |
| expert | 3 | 15 | 4:36 | 24 | 11s / 11s（15/15） | 7 / 32 | 0 | bone/floater/runner/slider ×4；bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/slider/stone ×3 |
| expert | 4 | 15 | 5:27 | 36 | 15s / 15s（15/15） | 19 / 165 | 1 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 5 | 14 | 6:25 | 39 | 18s / 12s（14/14） | 8 / 35 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×5；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 12 | 7:53 | 27 | 9s / 8s（12/12） | 10 / 57 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×3 |
| expert | 7 | 11 | 8:59 | 21 | 9s / 9s（11/11） | 24 / 99 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] phantom | 16 | 75% | 10:16 / 1:41 | 0.0 / - | 8 / 16 / 23 / 26 | 1% | 93% | 82 | 1698 | 虚影 11% 影刃 8% 剑气 8% 真实 5% | 自身回复 34% 补给 20% 塞雷娅 11% (570 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] phantom | 16 | 75% | 10:16 / 1:41 | 93% | 93% | 1:03 | 0:50 / 3:54 | 2.2 / 44s | 46.3 | 59 | 6 | 0 | 3 | 28% / 21749 | contact_founder |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | phantom | 16 | 14.2 | 9.2% | class 41/13 control 17/7 economy 79/27 general 182/84 heal 18/7 melee 106/35 multi 17/3 shield 34/17 summon 20/11 survival 67/18 weak 12/5 | 0 |
| 合计 | | | | | class 41/13 control 17/7 economy 79/27 general 182/84 heal 18/7 melee 106/35 multi 17/3 shield 34/17 summon 20/11 survival 67/18 weak 12/5 | |

拿取最多（出现 / 拿取）：老近卫军之锋 11/9，赶车夫的长鞭 21/7，锈蚀刀片 17/6，漆黑的舞鞋 20/6，《旧高卢地名源流考》 9/5，贵族刺剑 18/5，便携经书 6/5，古旧铸物 5/4，药枚 4/4，源石鸢尾花 7/4，涡旋座 5/4，Miss.Christine摸摸券 6/3
