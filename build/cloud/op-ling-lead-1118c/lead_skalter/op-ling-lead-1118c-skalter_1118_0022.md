# balance op-ling-lead-1118c-skalter 1118_0022

args: `--op skalter --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118c-skalter --out build/cloud/op-ling-lead-1118c/lead_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 6 | 70s / 75s / 101s / 39–101s | 76s / 101s | 8.7 / 2.6 | 63% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 109s / 109s / 118s / 101–118s | 110s / 118s | 1.0 / 1.3 | 72% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 47s / 47s / 47s / 47–47s | 27s / 27s | 6.9 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 20 | 16 | 60s | 0.45 | 6 | - | - |
| expert | 塑路者 | 14 | 13 | 68s | 0.52 | 6 | - | - |
| expert | 接潮主教 | 6 | 6 | 33s | 0.21 | 7 | 1.0 | 23% |
| expert | 接潮蔑死体 | 3 | 3 | 28s | 0.24 | 6 | - | - |
| expert | 接潮斥亡体 | 3 | 3 | 38s | 0.20 | 8 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 46s | 0.31 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 28% | 71% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 9% | 219 / 228 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 3 | 4:58 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 3 | 1:52 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:30 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:01 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:17 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:00 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:13 |
| expert | 0 | atk_tracer | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:30 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:06 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:30 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:18 |
| expert | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:57 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:08 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:25 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:03 |
| expert | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:10 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:28 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 75 / 108 | 108 / 250 | 0 / 9 | 378 / 426 | 35 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 74 / 104 | 26 / 57 | 0 / 0 | 405 / 426 | 35 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 23 | 354 | 0.1 | 4.0 / 1.1% | 0.8 / 1.6% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 9 | 1055 | 0.0 | 3.8 / 0.0% | 1.1 / 0.9% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 15s / 15s（32/32） | 19 / 85 | 1 | bone/slider/stone ×20；bone/slider ×12 |
| expert | 2 | 29 | 2:45 | 20 | 8s / 9s（29/29） | 13 / 40 | 0 | bone/slider ×19；bone/slider/stone ×10 |
| expert | 3 | 23 | 4:48 | 24 | 12s / 11s（21/23） | 31 / 141 | 4 | bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/slider/stone ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 4 | 16 | 5:44 | 37 | 16s / 14s（14/16） | 37 / 155 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 5 | 14 | 6:40 | 38 | 15s / 12s（14/14） | 30 / 119 | 1 | bone/floater/reaper/runner/slider/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 6 | 13 | 8:00 | 26 | 10s / 9s（13/13） | 26 / 154 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 11 | 9:02 | 21 | 9s / 9s（11/11） | 39 / 80 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 32 | 28% | 7:13 / 1:45 | 0.0 / - | 7 / 15 / 23 / 20 | 22% | 62% | 43 | 1127 | 声浪 17% Mon3tr 9% 余震 5% 终结技·skalter·激光 4% | 自身回复 28% 浊心斯卡蒂 25% 凯尔希 10% (830 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 32 | 28% | 7:13 / 1:45 | 90% | 71% | 1:14 | 1:05 / 3:11 | 1.3 / 55s | 54.3 | 124 | 7 | 2 | 3 | 23% / 8619 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | skalter | 32 | 9.4 | 4.3% | class 93/31 control 24/13 economy 100/30 general 212/87 heal 115/48 melee 30/8 multi 36/14 shield 31/17 summon 41/15 survival 86/33 weak 15/4 | 0 |
| 合计 | | | | | class 93/31 control 24/13 economy 100/30 general 212/87 heal 115/48 melee 30/8 multi 36/14 shield 31/17 summon 41/15 survival 86/33 weak 15/4 | |

拿取最多（出现 / 拿取）：食腐者手杖 22/10，血魔的银杯 23/10，猎人的口粮 36/9，《旧高卢地名源流考》 16/8，苍白花冠 10/8，“多功能”发夹 11/7，遥乡之引 7/6，红色蝴蝶结 8/5，未知仪器 5/5，显圣吊坠 13/5，“岁怒” 4/5，支援起重机 10/5
