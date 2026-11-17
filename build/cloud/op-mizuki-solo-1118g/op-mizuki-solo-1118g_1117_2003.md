# balance op-mizuki-solo-1118g 1117_2003

args: `--op mizuki --bot expert --seeds 16 --seed0 17 --nocache --jobs 8 --tag op-mizuki-solo-1118g --out build/cloud/op-mizuki-solo-1118g`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 12 | 12 | 12 | 95s / 95s / 118s / 60–144s | 96s / 118s | 5.5 / 2.8 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 76s / 76s / 76s / 76–76s | 76s / 76s | 6.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 11 | 10 | 46s | 0.17 | 5 | 1.1 | 11% |
| expert | 圣徒卡门 | 10 | 9 | 62s | 0.51 | 5 | - | - |
| expert | 塑路者 | 8 | 7 | 54s | 0.52 | 8 | - | - |
| expert | 接潮斥亡体 | 7 | 6 | 45s | 0.18 | 5 | - | - |
| expert | 接潮蔑死体 | 4 | 4 | 56s | 0.20 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 68s | 0.28 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 81% | 18% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 181 / 126 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:49 |
| expert | 0 | boss_immortal | 第 2 轮 · 收缩 | 否 | 是 | 1 | 9:25 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:39 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 87 / 124 | 106 / 243 | 0 / 0 | 429 / 453 | 46 / 48 |
| expert | 0 | 14 | 8:00–10:00 | 72 / 87 | 24 / 48 | 0 / 0 | 424 / 439 | 43 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 3 | 1528 | 0.0 | 5.7 / 0.6% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 13 | 702 | 0.0 | 0.0 / 0.0% | 0.4 / 0.7% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 17s / 12s（16/16） | 14 / 58 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 16 | 2:45 | 20 | 9s / 8s（16/16） | 11 / 34 | 0 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 3 | 15 | 4:52 | 25 | 11s / 9s（15/15） | 18 / 74 | 0 | bone/slider/stone ×4；bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×2 |
| expert | 4 | 14 | 5:36 | 37 | 14s / 14s（14/14） | 14 / 66 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 5 | 14 | 6:42 | 38 | 13s / 12s（14/14） | 13 / 41 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 12 | 8:06 | 27 | 8s / 8s（12/12） | 24 / 65 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 10 | 9:11 | 22 | 10s / 10s（10/10） | 8 / 39 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki | 16 | 81% | 10:50 / 5:39 | 0.0 / - | 8 / 16 / 23 / 26 | 4% | 95% | 76 | 1741 | 触手 18% 伞击 15% Mon3tr 7% 真实 6% | 水月 57% 自身回复 20% 凯尔希 8% (861 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki | 16 | 81% | 10:50 / 5:39 | 100% | 100% | 1:04 | 0:52 / 3:33 | 2.4 / 61s | 62.6 | 86 | 5 | 6 | 4 | 37% / 34549 | boss_immortal |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | mizuki | 16 | 15.0 | 7.5% | class 57/16 control 19/7 economy 67/25 general 162/67 heal 25/9 melee 32/13 multi 20/3 shield 19/12 summon 100/53 survival 84/26 weak 22/9 | 0 |
| 合计 | | | | | class 57/16 control 19/7 economy 67/25 general 162/67 heal 25/9 melee 32/13 multi 20/3 shield 19/12 summon 100/53 survival 84/26 weak 22/9 | |

拿取最多（出现 / 拿取）：散轶诗简 20/10，衍生者终端-超级改 17/9，几丁质刺刃 9/8，《旧高卢地名源流考》 9/7，无字珊瑚 10/6，“岁怒” 7/6，海程 21/5，炸裂之手 8/5，恐鱼干 10/4，扣挠之手 8/4，支援起重机 4/4，皇帝的恩宠 10/4
