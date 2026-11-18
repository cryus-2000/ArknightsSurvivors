# balance op-ling-s64-peers-1118n-l-angelina 1118_0721

args: `--op angelina --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-l-angelina --out build/cloud/op-ling-s64-peers-1118n/lead_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 17 | 17 | 13 | 140s / 140s / 219s / 46–313s | 140s / 219s | 3.3 / 2.8 | 45% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 86s / 86s / 116s / 57–116s | 86s / 116s | 2.3 / 1.3 | 66% |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 0.0 / 0.0 | 81% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 19 | 17 | 105s | 0.38 | 9 | - | - |
| expert | 圣徒卡门 | 16 | 10 | 72s | 0.35 | 8 | - | - |
| expert | 接潮主教 | 15 | 14 | 64s | 0.13 | 8 | 1.2 | 12% |
| expert | 接潮斥亡体 | 8 | 7 | 85s | 0.10 | 10 | - | - |
| expert | 接潮蔑死体 | 7 | 7 | 50s | 0.19 | 7 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 56s | 0.27 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 46% | 53% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 142 / 140 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 4 | 4:19 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 2 | 11:07 |
| expert | 0 | contact_floater | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:28 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:35 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:48 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:08 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:40 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:44 |
| expert | 0 | contact_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:29 |
| expert | 0 | boss_ishar | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:23 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:30 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 10:25 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:57 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 82 / 118 | 158 / 320 | 1 / 8 | 372 / 462 | 38 / 48 |
| expert | 0 | 22 | 8:00–10:00 | 78 / 100 | 34 / 98 | 1 / 8 | 378 / 441 | 34 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 17 | 413 | 0.1 | 0.8 / 0.2% | 0.9 / 1.5% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 15 | 577 | 0.9 | 1.5 / 0.2% | 4.2 / 6.3% | 0.0 / 0.0% | 1.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 15s / 14s（32/32） | 14 / 56 | 0 | bone/slider ×17；bone/slider/stone ×15 |
| expert | 2 | 32 | 2:45 | 20 | 11s / 11s（32/32） | 13 / 69 | 0 | bone/slider/stone ×17；bone/slider ×15 |
| expert | 3 | 23 | 5:17 | 24 | 16s / 11s（22/23） | 8 / 37 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 4 | 22 | 6:03 | 37 | 25s / 16s（21/22） | 14 / 137 | 1 | bone/reaper/runner/slider/tracer ×12；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×3 |
| expert | 5 | 19 | 7:27 | 40 | 18s / 15s（19/19） | 8 / 57 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×3 |
| expert | 6 | 17 | 8:34 | 24 | 12s / 11s（17/17） | 7 / 48 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4 |
| expert | 7 | 7 | 9:06 | 21 | 12s / 11s（7/7） | 48 / 156 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 32 | 46% | 9:31 / 3:48 | 0.0 / - | 7 / 15 / 22 / 23 | 45% | 75% | 73 | 1371 | 双重引力 11% 藏品 7% 秘杖·速充模式 6% Mon3tr 4% | 自身回复 32% 补给 16% 流明 11% (766 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 32 | 46% | 9:31 / 3:48 | 100% | 75% | 1:09 | 0:53 / 3:25 | 1.8 / 83s | 39.3 | 87 | 7 | 1 | 6 | 24% / 13839 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | angelina | 32 | 11.8 | 9.6% | class 86/26 control 135/72 economy 111/40 general 298/113 heal 31/9 melee 45/17 multi 39/11 shield 42/22 summon 55/20 survival 109/37 weak 27/11 | 0 |
| 合计 | | | | | class 86/26 control 135/72 economy 111/40 general 298/113 heal 31/9 melee 45/17 multi 39/11 shield 42/22 summon 55/20 survival 109/37 weak 27/11 | |

拿取最多（出现 / 拿取）：凯旋号角 36/17，安洁莉娜的创想 34/16，悬丝傀儡 20/14，“多功能”发夹 23/12，高闪相机 13/9，散轶诗简 19/7，热水壶 8/6，药枚 11/6，贵族刺剑 11/6，《大静谧》 6/6，“小格兰法洛” 13/5，“文明的存续” 6/4
