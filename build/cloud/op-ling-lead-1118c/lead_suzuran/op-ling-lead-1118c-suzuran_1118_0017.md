# balance op-ling-lead-1118c-suzuran 1118_0017

args: `--op suzuran --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118c-suzuran --out build/cloud/op-ling-lead-1118c/lead_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 13 | 13 | 13 | 84s / 79s / 121s / 57–125s | 79s / 121s | 7.8 / 2.8 | - |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 62s / 62s / 65s / 60–65s | 62s / 65s | 3.4 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 19 | 13 | 54s | 0.48 | 9 | - | - |
| expert | 塑路者 | 18 | 17 | 56s | 0.59 | 9 | - | - |
| expert | 接潮主教 | 15 | 14 | 53s | 0.14 | 12 | 1.2 | 21% |
| expert | 接潮蔑死体 | 9 | 9 | 50s | 0.19 | 13 | - | - |
| expert | 接潮斥亡体 | 6 | 5 | 57s | 0.14 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 6 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 46% | 53% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 129 / 120 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:17 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 2 | 9:04 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 2 | 4:46 |
| expert | 0 | contact_nest | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:15 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:52 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:40 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:50 |
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:23 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:26 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 9:01 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:44 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:06 |
| expert | 0 | wound | 第 2 轮 · 收缩 | 否 | 是 | 1 | 7:06 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 89 / 144 | 127 / 285 | 8 / 10 | 387 / 483 | 45 / 48 |
| expert | 0 | 18 | 8:00–10:00 | 77 / 112 | 27 / 57 | 6 / 9 | 388 / 431 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 17 | 333 | 0.0 | 3.5 / 1.5% | 0.1 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 15 | 987 | 0.1 | 6.0 / 0.8% | 0.9 / 0.8% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 11s（32/32） | 8 / 52 | 0 | bone/slider ×16；bone/slider/stone ×16 |
| expert | 2 | 32 | 2:45 | 20 | 11s / 10s（32/32） | 8 / 34 | 0 | bone/slider/stone ×16；bone/slider ×16 |
| expert | 3 | 26 | 4:41 | 25 | 16s / 13s（24/26） | 34 / 134 | 3 | bone/floater/runner/slider ×8；bone/slider/stone ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 4 | 22 | 5:27 | 36 | 19s / 14s（21/22） | 40 / 113 | 1 | bone/reaper/runner/slider/tracer ×8；bone/offspring/reaper/runner/slider/spitter/tracer ×8；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 5 | 20 | 6:20 | 39 | 27s / 16s（18/20） | 30 / 166 | 2 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 6 | 18 | 8:07 | 26 | 15s / 11s（17/18） | 20 / 135 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/founder/nest/offspring/runner/slider/stone/tracer ×5；bone/founder/nest/runner/slider/spitter/stone/tracer ×4 |
| expert | 7 | 13 | 9:05 | 21 | 12s / 10s（12/13） | 27 / 97 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×9；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 32 | 46% | 8:26 / 3:44 | 0.0 / - | 8 / 15 / 23 / 22 | 23% | 72% | 63 | 1337 | 狐火 18% 狐火点点 5% 藏品 4% 终结技·suzuran·斩痕 4% | 自身回复 31% 铃兰 15% 塞雷娅 14% (735 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 32 | 46% | 8:26 / 3:44 | 100% | 71% | 1:01 | 0:50 / 3:02 | 1.8 / 60s | 58.9 | 95 | 5 | 0 | 4 | 24% / 12211 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | suzuran | 32 | 10.8 | 6.9% | class 117/39 control 113/48 economy 101/38 general 236/107 heal 31/7 melee 52/14 multi 36/14 shield 32/23 summon 31/11 survival 117/39 weak 19/6 | 0 |
| 合计 | | | | | class 117/39 control 113/48 economy 101/38 general 236/107 heal 31/7 melee 52/14 multi 36/14 shield 32/23 summon 31/11 survival 117/39 weak 19/6 | |

拿取最多（出现 / 拿取）：凯旋号角 42/11，“荣耀套餐” 15/10，安洁莉娜的创想 34/9，“小格兰法洛” 9/8，《旧高卢地名源流考》 13/8，“多功能”发夹 10/7，悬丝傀儡 6/6，穿甲弹 11/6，堡垒协议-方阵 11/6，古乔治营养原浆 6/5，贵族刺剑 11/4，国王的圆饼 5/4
