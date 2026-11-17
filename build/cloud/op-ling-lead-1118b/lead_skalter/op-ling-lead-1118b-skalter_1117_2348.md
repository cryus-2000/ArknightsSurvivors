# balance op-ling-lead-1118b-skalter 1117_2348

args: `--op skalter --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118b-skalter --out build/cloud/op-ling-lead-1118b/lead_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 64s / 71s / 81s / 39–81s | 71s / 81s | 9.9 / 2.5 | 84% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 118s / 118s / 118s / 118–118s | 118s / 118s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 11 | 51s | 0.46 | 7 | - | - |
| expert | 塑路者 | 5 | 5 | 68s | 0.54 | 8 | - | - |
| expert | 接潮主教 | 4 | 4 | 33s | 0.22 | 6 | 1.0 | 25% |
| expert | 接潮蔑死体 | 2 | 2 | 24s | 0.27 | 4 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 43s | 0.17 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 12% | 235 / 252 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 2 | 4:50 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 2 | 1:55 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:17 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:00 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:13 |
| expert | 0 | atk_tracer | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:30 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:18 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:06 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 79 / 108 | 122 / 250 | 1 / 9 | 389 / 422 | 35 / 48 |
| expert | 0 | 7 | 8:00–10:00 | 76 / 104 | 28 / 57 | 0 / 0 | 409 / 422 | 33 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 325 | 0.0 | 2.7 / 1.0% | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 1195 | 0.0 | 5.7 / 0.0% | 1.0 / 0.6% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 15s / 16s（16/16） | 20 / 85 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 14 | 2:45 | 20 | 9s / 9s（14/14） | 15 / 40 | 0 | bone/slider ×9；bone/slider/stone ×5 |
| expert | 3 | 13 | 4:47 | 24 | 15s / 13s（11/13） | 33 / 141 | 3 | bone/offspring/slider/stone ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 4 | 9 | 5:41 | 37 | 17s / 14s（8/9） | 41 / 117 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 5 | 8 | 6:40 | 38 | 14s / 10s（8/8） | 45 / 119 | 1 | bone/floater/reaper/runner/slider/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 6 | 7 | 8:03 | 26 | 10s / 10s（7/7） | 28 / 154 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |
| expert | 7 | 5 | 8:59 | 22 | 8s / 8s（5/5） | 40 / 68 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 16 | 37% | 7:23 / 1:49 | 0.0 / - | 7 / 15 / 23 / 20 | 22% | 65% | 46 | 1163 | 声浪 18% Mon3tr 7% 大剑 6% 剑气 3% | 自身回复 29% 浊心斯卡蒂 26% 补给 9% (881 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 16 | 37% | 7:23 / 1:49 | 87% | 68% | 1:17 | 1:05 / 3:20 | 1.5 / 53s | 60.5 | 127 | 8 | 2 | 3 | 24% / 8718 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | skalter | 16 | 9.5 | 5.7% | class 46/15 control 10/4 economy 53/15 general 102/45 heal 61/22 melee 15/6 multi 21/9 shield 18/7 summon 15/5 survival 40/20 weak 7/4 | 0 |
| 合计 | | | | | class 46/15 control 10/4 economy 53/15 general 102/45 heal 61/22 melee 15/6 multi 21/9 shield 18/7 summon 15/5 survival 40/20 weak 7/4 | |

拿取最多（出现 / 拿取）：血魔的银杯 12/6，食腐者手杖 13/5，未知仪器 5/5，《旧高卢地名源流考》 11/4，猎人的口粮 19/4，银餐叉 6/4，红色蝴蝶结 4/3，显圣吊坠 7/3，聚火源石虫 6/3，苍白花冠 5/3，羽兽肝酱 3/3，游戏室管理员权限卡 3/2
