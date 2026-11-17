# balance op-specter_unchained-solo-1118a 1117_1950

args: `--op specter_unchained --bot expert --seeds 16 --nocache --jobs 8 --tag op-specter_unchained-solo-1118a --out build/cloud/op-specter_unchained-solo-1118a`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 7 | 79s / 70s / 110s / 63–110s | 70s / 110s | 7.7 / 3.0 | 28% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 11 | 9 | 37s | 0.40 | 6 | - | - |
| expert | 圣徒卡门 | 10 | 10 | 38s | 0.46 | 6 | - | - |
| expert | 接潮主教 | 3 | 3 | 37s | 0.17 | 6 | 1.0 | 30% |
| expert | 接潮斥亡体 | 3 | 3 | 37s | 0.19 | 6 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 73s | 0.26 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 43% | 56% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 12% | 210 / 208 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:44 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 2:27 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:36 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 否 | 1 | 7:52 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:22 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:00 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:35 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:57 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:46 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 79 / 107 | 163 / 317 | 0 / 4 | 349 / 438 | 42 / 48 |
| expert | 0 | 9 | 8:00–10:00 | 75 / 92 | 25 / 44 | 0 / 1 | 393 / 438 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 9 | 459 | 0.0 | 3.3 / 0.7% | 0.6 / 0.9% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 7 | 1213 | 0.0 | 4.7 / 0.3% | 0.6 / 0.2% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 13s / 14s（16/16） | 15 / 78 | 0 | bone/slider ×8；bone/slider/stone ×8 |
| expert | 2 | 14 | 2:45 | 20 | 9s / 8s（14/14） | 20 / 102 | 0 | bone/slider/stone ×7；bone/slider ×7 |
| expert | 3 | 12 | 4:49 | 24 | 10s / 9s（12/12） | 17 / 79 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/slider/stone ×2；bone/offspring/slider/stone ×2 |
| expert | 4 | 12 | 5:42 | 37 | 13s / 12s（12/12） | 24 / 60 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| expert | 5 | 12 | 6:47 | 39 | 14s / 13s（11/12） | 24 / 86 | 1 | bone/reaper/runner/slider/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×3 |
| expert | 6 | 10 | 8:09 | 26 | 9s / 8s（10/10） | 37 / 152 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×2 |
| expert | 7 | 7 | 9:04 | 22 | 8s / 8s（7/7） | 47 / 123 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] specter_unchained | 16 | 43% | 8:32 / 2:27 | 0.0 / - | 7 / 15 / 23 / 23 | 12% | 75% | 71 | 1398 | 锯刃 25% 替身闪现 13% 血色潮痕 5% 剑气 4% | 自身回复 38% 拾取 16% 补给 15% (996 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] specter_unchained | 16 | 43% | 8:32 / 2:27 | 87% | 75% | 1:07 | 0:51 / 3:33 | 1.6 / 51s | 74.4 | 131 | 15 | 2 | 4 | 45% / 31974 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | specter_unchained | 16 | 12.7 | 4.9% | class 70/30 control 9/5 economy 58/25 general 148/60 heal 16/4 melee 83/31 multi 19/3 shield 25/7 summon 27/12 survival 54/18 weak 11/8 | 0 |
| 合计 | | | | | class 70/30 control 9/5 economy 58/25 general 148/60 heal 16/4 melee 83/31 multi 19/3 shield 25/7 summon 27/12 survival 54/18 weak 11/8 | |

拿取最多（出现 / 拿取）：漆黑的舞鞋 12/7，老近卫军之锋 6/6，赶车夫的长鞭 11/5，锈蚀刀片 21/5，贵族刺剑 16/5，《旧高卢地名源流考》 11/4，“苦痛的快乐” 2/4，皇帝的恩宠 17/3，堡垒协议-方阵 6/3，破坏协议-压制 6/3，海程 7/3，扣挠之手 3/3
