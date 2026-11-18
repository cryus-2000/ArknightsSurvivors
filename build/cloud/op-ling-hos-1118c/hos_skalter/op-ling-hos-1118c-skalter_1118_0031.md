# balance op-ling-hos-1118c-skalter 1118_0031

args: `--squad hoshiguma,skalter --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118c-skalter --out build/cloud/op-ling-hos-1118c/hos_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 22 | 22 | 17 | 91s / 77s / 147s / 61–170s | 77s / 147s | 5.9 / 2.9 | 33% |
| expert | 伊祖米克 | resolve 2 | 2 | 2 | 99s / 99s / 107s / 92–107s | 80s / 87s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 50s / 50s / 50s / 50–50s | 50s / 50s | 3.0 / 1.5 | 63% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 22 | 21 | 54s | 0.43 | 7 | - | - |
| expert | 塑路者 | 21 | 21 | 71s | 0.40 | 8 | - | - |
| expert | 接潮主教 | 12 | 12 | 58s | 0.15 | 10 | 1.2 | 20% |
| expert | 圣徒伊比利亚 | 6 | 6 | 58s | 0.28 | 8 | - | - |
| expert | 接潮斥亡体 | 6 | 6 | 92s | 0.14 | 11 | - | - |
| expert | 接潮蔑死体 | 6 | 6 | 44s | 0.19 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 13 | 0.0 / 0.0 / 0.0 / 0 | 16 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 62% | 37% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 107 / 100 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 11:20 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:39 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:50 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:49 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:36 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:55 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:52 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:08 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 11:42 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:22 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 89 / 120 | 193 / 320 | 0 / 10 | 397 / 466 | 44 / 48 |
| expert | 0 | 29 | 8:00–10:00 | 78 / 104 | 33 / 112 | 0 / 5 | 400 / 466 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 12 | 916 | 0.1 | 3.7 / 0.2% | 0.8 / 1.3% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 20 | 949 | 0.1 | 2.8 / 0.2% | 0.9 / 1.1% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 12s / 11s（31/32） | 13 / 61 | 0 | bone/slider/stone ×21；bone/slider ×11 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 8 / 40 | 0 | bone/slider ×20；bone/slider/stone ×11 |
| expert | 3 | 31 | 5:15 | 24 | 13s / 11s（30/31） | 14 / 82 | 1 | bone/reaper/runner/slider/tracer ×8；bone/slider/stone ×5；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 4 | 28 | 5:56 | 37 | 17s / 13s（27/28） | 15 / 83 | 0 | bone/floater/reaper/runner/slider/tracer ×10；bone/offspring/reaper/runner/slider/spitter/tracer ×8；bone/reaper/runner/slider/tracer ×7 |
| expert | 5 | 26 | 6:49 | 38 | 21s / 14s（26/26） | 14 / 65 | 0 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/reaper/runner/slider/tracer ×4 |
| expert | 6 | 24 | 8:03 | 26 | 10s / 9s（24/24） | 16 / 74 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×11；bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/floater/founder/nest/runner/slider/stone/tracer ×4 |
| expert | 7 | 20 | 9:06 | 22 | 10s / 9s（20/20） | 18 / 100 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×9；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 32 | 62% | 10:37 / 1:50 | 0.0 / - | 8 / 15 / 22 / 26 | 15% | 95% | 54 | 1710 | 举盾反击 10% 剑气 9% 真实 5% 声浪 5% | 浊心斯卡蒂 32% 自身回复 31% 补给 11% (824 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 32 | 62% | 10:37 / 1:50 | 96% | 96% | 1:21 | 0:50 / 3:18 | 2.2 / 73s | 73.2 | 81 | 6 | 4 | 4 | 29% / 29604 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 14.2 | 6.5% | class 116/36 control 29/18 economy 116/41 general 351/145 heal 41/13 melee 213/81 multi 49/18 shield 52/29 summon 51/21 survival 123/43 weak 27/8 | 0 |
| 合计 | | | | | class 116/36 control 29/18 economy 116/41 general 351/145 heal 41/13 melee 213/81 multi 49/18 shield 52/29 summon 51/21 survival 123/43 weak 27/8 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 42/17，漆黑的舞鞋 38/17，皇帝的恩宠 42/13，《旧高卢地名源流考》 22/12，锈蚀刀片 50/12，老近卫军之锋 17/12，贵族刺剑 24/10，“多功能”发夹 16/9，药枚 11/6，显圣吊坠 16/5，“荣耀套餐” 5/5，紧急活性剂 6/5
