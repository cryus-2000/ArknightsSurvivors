# balance hitlift-old-m0-1 1030_1527

args: `--preset starts --bots expert --seeds 2 --seed0 1 --nocache --jobs 4 --tag hitlift-old-m0-1 --out build/bl/hitlift-old_m0 --extra=--tier=0 --tide=0 --bal=boss/bullet_hit_k=0 --bal=boss/bullet_hit_k_mid=0 --bal=enemy/bullet_hit_lift=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 7 | 126s / 126s / 160s / 89–160s | 126s / 160s | 2.3 / 3.0 | 19% |
| expert | 伊祖米克 | resolve 1 | 1 | 0 | - | - | 0.0 / 2.0 | 21% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 8 | 7 | 75s | 0.09 | 16 | 1.3 | 30% |
| expert | 圣徒卡门 | 7 | 6 | 106s | 0.22 | 8 | - | - |
| expert | 塑路者 | 5 | 5 | 47s | 0.52 | 6 | - | - |
| expert | 接潮蔑死体 | 5 | 4 | 65s | 0.12 | 19 | - | - |
| expert | 接潮斥亡体 | 3 | 3 | 75s | 0.11 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 14 | 50% | 35% | 14% (2) | 20% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 7% | 191 / 165 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:05 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:13 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:02 |
| expert | 0 | corrode | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:14 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:06 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 108 / 189 | 116 / 199 | 2 / 7 | 320 / 437 | 41 / 48 |
| expert | 0 | 9 | 8:00–10:00 | 86 / 108 | 44 / 81 | 1 / 5 | 374 / 437 | 42 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 1188 | 0.0 | 4.4 / 0.9% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 7 | 2426 | 0.1 | 0.0 / 0.0% | 0.6 / 0.5% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 13s / 10s（14/14） | 14 / 49 | 0 | bone/slider ×11；bone/slider/stone ×3 |
| expert | 2 | 13 | 2:45 | 20 | 11s / 10s（13/13） | 28 / 74 | 2 | bone/slider/stone ×11；bone/slider ×2 |
| expert | 3 | 10 | 5:00 | 25 | 36s / 12s（9/10） | 16 / 65 | 1 | bone/offspring/slider/stone ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/floater/runner/slider ×2 |
| expert | 4 | 10 | 5:22 | 36 | 42s / 17s（9/10） | 22 / 79 | 1 | bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 5 | 9 | 6:17 | 40 | 33s / 24s（9/9） | 26 / 61 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 6 | 8 | 8:14 | 26 | 19s / 11s（8/8） | 19 / 45 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 4 | 9:03 | 21 | 18s / 10s（4/4） | 16 / 38 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 12:22 / 11:44 | 0.0 / - | 8 / 16 / 22 / 28 | 21% | 100% | 97 | 1968 | 余震 22% 真实 18% 饱和复仇 8% 爆裂黎明 5% | 自身回复 28% 流明 23% 凯尔希 19% (1567 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 0% | 2:39 / 2:13 | 0.0 / - | 8 / 0 / 0 / 9 | - | 0% | 13 | 281 | 熔岩弹 35% 拳击 10% 火星 10% 秘杖·速充模式 8% | 自身回复 33% 塞雷娅 16% 凯尔希 16% (253 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 8:45 / 6:02 | 0.0 / - | 8 / 14 / 23 / 22 | 2% | 66% | 48 | 1286 | 大剑 20% 真实 13% 熔岩弹 10% 余震 8% | 自身回复 50% 拾取 18% 凯尔希 16% (830 / 0.0) | boss_carmen |
| [expert] mizuki | 2 | 100% | 12:13 / 11:50 | 0.0 / - | 7 / 14 / 22 / 27 | - | 100% | 100 | 1800 | 伞击 14% 余震 13% 真实 12% 触手 10% | 水月 43% 自身回复 19% 凯尔希 10% (1587 / 0.0) | contact_tracer |
| [expert] saria | 2 | 0% | 8:07 / 3:14 | 0.0 / - | 8 / 14 / 19 / 18 | 19% | 50% | 53 | 816 | 拳击 14% 炮击 10% 举盾反击 8% 钩索 7% | 塞雷娅 59% 自身回复 21% 针剂回流 7% (773 / 0.0) | atk_tracer |
| [expert] kaltsit | 2 | 50% | 9:23 / 6:06 | 0.0 / - | 8 / 14 / 21 / 21 | - | 66% | 29 | 1264 | Mon3tr 24% 真实 8% 终结技·kaltsit·熔毁 7% 炮击 6% | 凯尔希 26% 自身回复 19% 塞雷娅 16% (1516 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 100% | 12:12 / 12:06 | 0.0 / - | 8 / 15 / 22 / 26 | - | 100% | 73 | 1867 | 余震 15% 狐火 14% 藏品 14% 饱和复仇 4% | 自身回复 28% 塞雷娅 27% 铃兰 17% (1209 / 0.0) | atk_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 12:22 / 11:44 | 100% | 100% | 1:10 | 0:47 / 3:42 | 3.0 / 56s | 231.8 | 122 | 8 | 13 | 3 | 41% / 32404 | wound |
| [expert] eyjafjalla | 2 | 0% | 2:39 / 2:13 | 0% | 0% | 1:13 | 0:49 / - | 0.0 / - | 50.3 | 135 | 8 | 1 | 0 | 59% / 5035 | corrode |
| [expert] skadi | 2 | 50% | 8:45 / 6:02 | 100% | 100% | 1:00 | 0:59 / 2:56 | 1.5 / 45s | 87.0 | 116 | 6 | 0 | 3 | 38% / 16897 | mire |
| [expert] mizuki | 2 | 100% | 12:13 / 11:50 | 100% | 100% | 1:09 | 0:49 / 3:39 | 3.0 / 75s | 173.3 | 122 | 4 | 24 | 8 | 28% / 19999 | - |
| [expert] saria | 2 | 0% | 8:07 / 3:14 | 50% | 50% | 1:20 | 0:51 / 2:38 | 0.5 / 174s | 107.1 | 118 | 0 | 0 | 2 | 24% / 4563 | corrode |
| [expert] kaltsit | 2 | 50% | 9:23 / 6:06 | 100% | 100% | 1:18 | 1:01 / 5:50 | 2.0 / 89s | 145.8 | 166 | 2 | 24 | 4 | 35% / 15220 | contact_reaper |
| [expert] suzuran | 2 | 100% | 12:12 / 12:06 | 100% | 100% | 1:07 | 0:51 / 4:03 | 2.5 / 61s | 135.4 | 99 | 2 | 0 | 4 | 19% / 13347 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 0.5 | 0.0% | economy 2/0 general 1/1 heal 1/0 multi 1/0 survival 1/0 | 0 |
| expert | kaltsit | 2 | 10.5 | 12.1% | class 7/3 control 1/0 economy 6/5 general 12/5 heal 5/3 melee 3/2 multi 3/1 shield 1/1 summon 3/1 survival 9/0 | 0 |
| expert | mizuki | 2 | 13.5 | 14.0% | class 4/1 economy 8/2 general 21/9 heal 4/0 melee 3/1 multi 2/1 shield 5/2 summon 14/8 survival 9/3 weak 2/0 | 0 |
| expert | saria | 2 | 4.0 | 0.0% | class 1/1 economy 1/0 general 9/3 heal 6/1 multi 2/1 shield 1/0 summon 1/1 survival 4/1 | 0 |
| expert | skadi | 2 | 9.0 | 14.1% | class 1/1 control 1/0 economy 6/1 general 16/6 heal 2/0 melee 8/4 multi 5/1 shield 2/0 summon 2/1 survival 9/4 weak 2/0 | 0 |
| expert | suzuran | 2 | 12.0 | 17.7% | class 4/0 control 8/4 economy 10/3 general 27/10 heal 1/1 melee 3/0 multi 4/1 shield 3/2 summon 5/1 survival 8/2 weak 3/0 | 0 |
| expert | wisadel | 2 | 13.0 | 21.8% | class 4/0 control 6/3 economy 12/3 general 20/9 heal 4/1 melee 6/2 multi 11/4 shield 5/1 summon 1/1 survival 7/1 weak 3/1 | 0 |
| 合计 | | | | | class 21/6 control 16/7 economy 45/14 general 106/43 heal 23/6 melee 23/9 multi 28/9 shield 17/6 summon 26/13 survival 47/11 weak 10/1 | |

拿取最多（出现 / 拿取）：穿甲弹 8/4，《旧高卢地名源流考》 6/3，赶车夫的长鞭 5/3，几丁质刺刃 3/3，贵族刺剑 6/3，皇家利口酒 4/3，“多功能”发夹 7/3，悬丝傀儡 3/3，无瑕宝玉 4/2，三钥协定 6/2，显圣吊坠 7/2，苍白花冠 2/2
