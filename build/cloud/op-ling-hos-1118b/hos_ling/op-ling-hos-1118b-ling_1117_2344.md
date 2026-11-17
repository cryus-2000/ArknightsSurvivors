# balance op-ling-hos-1118b-ling 1117_2344

args: `--squad hoshiguma,ling --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118b-ling --out build/cloud/op-ling-hos-1118b/hos_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 6 | 89s / 88s / 154s / 40–154s | 88s / 154s | 6.5 / 2.6 | 50% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 49s / 49s / 57s / 42–57s | 50s / 57s | 5.1 / 2.0 | 36% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 10 | 9 | 63s | 0.54 | 8 | - | - |
| expert | 圣徒卡门 | 8 | 8 | 58s | 0.52 | 8 | - | - |
| expert | 接潮主教 | 7 | 7 | 60s | 0.13 | 11 | 1.2 | 17% |
| expert | 接潮蔑死体 | 4 | 4 | 54s | 0.16 | 14 | - | - |
| expert | 接潮斥亡体 | 3 | 3 | 65s | 0.17 | 9 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 57s | 0.26 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 50% | 50% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 12% | 101 / 88 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 12:04 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:34 |
| expert | 0 | shock_founder | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:16 |
| expert | 0 | boss_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:59 |
| expert | 0 | shock_founder | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:08 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:15 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:53 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:26 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 85 / 112 | 132 / 250 | 1 / 10 | 367 / 445 | 40 / 48 |
| expert | 0 | 12 | 8:00–10:00 | 78 / 97 | 30 / 42 | 1 / 7 | 400 / 445 | 38 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 8 | 587 | 0.0 | 3.0 / 1.4% | 1.0 / 2.0% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 8 | 1048 | 0.0 | 0.9 / 0.1% | 1.6 / 3.6% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 14s / 12s（16/16） | 14 / 75 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| expert | 2 | 14 | 2:45 | 20 | 9s / 10s（14/14） | 4 / 20 | 0 | bone/slider ×10；bone/slider/stone ×4 |
| expert | 3 | 13 | 4:46 | 24 | 13s / 9s（13/13） | 10 / 49 | 0 | bone/reaper/runner/slider/tracer ×4；bone/offspring/slider/stone ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 4 | 12 | 5:37 | 37 | 15s / 16s（12/12） | 15 / 48 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 5 | 12 | 6:30 | 38 | 21s / 16s（12/12） | 20 / 50 | 0 | bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 6 | 12 | 8:02 | 27 | 12s / 10s（12/12） | 8 / 38 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×3 |
| expert | 7 | 11 | 9:10 | 21 | 12s / 11s（11/11） | 30 / 97 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 16 | 50% | 9:12 / 1:53 | 0.0 / - | 8 / 15 / 22 / 24 | 17% | 79% | 77 | 1508 | 举盾反击 9% 剑气 6% 弦惊·剑气 6% 真实 6% | 自身回复 44% 补给 18% 拾取 14% (636 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 16 | 50% | 9:12 / 1:53 | 87% | 81% | 1:31 | 0:48 / 2:33 | 2.0 / 57s | 77.5 | 76 | 9 | 0 | 3 | 22% / 18587 | atk_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 16 | 11.4 | 7.0% | class 35/11 control 13/10 economy 55/16 general 155/71 heal 11/4 melee 82/28 multi 21/6 shield 24/12 summon 16/6 survival 70/16 weak 10/3 | 0 |
| 合计 | | | | | class 35/11 control 13/10 economy 55/16 general 155/71 heal 11/4 melee 82/28 multi 21/6 shield 24/12 summon 16/6 survival 70/16 weak 10/3 | |

拿取最多（出现 / 拿取）：贵族刺剑 15/6，皇帝的恩宠 16/5，赶车夫的长鞭 16/5，老近卫军之锋 8/5，药枚 7/4，《旧高卢地名源流考》 7/4，漆黑的舞鞋 13/4，“绽放” 6/3，Scout的狙击镜 6/3，锈蚀刀片 14/3，“多功能”发夹 8/3，生还者合约 6/3
