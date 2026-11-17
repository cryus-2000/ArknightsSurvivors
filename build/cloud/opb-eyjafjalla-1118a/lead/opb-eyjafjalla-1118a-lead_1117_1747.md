# balance opb-eyjafjalla-1118a-lead 1117_1747

args: `--op eyjafjalla --bot expert --seeds 16 --nocache --jobs 8 --tag opb-eyjafjalla-1118a-lead --out build/cloud/opb-eyjafjalla-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 5 | 5 | 5 | 78s / 80s / 96s / 57–96s | 80s / 96s | 10.0 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 8 | 6 | 47s | 0.54 | 6 | - | - |
| expert | 塑路者 | 6 | 5 | 42s | 0.66 | 6 | - | - |
| expert | 接潮主教 | 4 | 4 | 46s | 0.17 | 7 | 1.0 | 12% |
| expert | 接潮斥亡体 | 2 | 2 | 46s | 0.14 | 8 | - | - |
| expert | 接潮蔑死体 | 2 | 2 | 40s | 0.21 | 8 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 43s | 0.30 | 11 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 5 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 31% | 68% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 12% | 195 / 197 | 92% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | mire | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:03 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:04 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:24 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:21 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 2:15 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:05 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:40 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:43 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 2:16 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:17 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 69 / 91 | 110 / 250 | 4 / 9 | 250 / 404 | 35 / 48 |
| expert | 0 | 5 | 8:00–10:00 | 69 / 77 | 16 / 19 | 2 / 6 | 353 / 380 | 31 / 39 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 11 | 121 | 0.0 | 1.6 / 0.3% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 5 | 1259 | 0.4 | 6.0 / 0.1% | 1.4 / 1.7% | 0.0 / 0.0% | 0.6 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 12s / 12s（16/16） | 22 / 65 | 0 | bone/slider ×8；bone/slider/stone ×8 |
| expert | 2 | 14 | 2:45 | 20 | 8s / 8s（14/14） | 19 / 71 | 0 | bone/slider/stone ×7；bone/slider ×7 |
| expert | 3 | 10 | 4:27 | 24 | 11s / 11s（9/10） | 33 / 79 | 2 | bone/offspring/slider/stone ×5；bone/floater/runner/slider ×2；bone/reaper/runner/slider/tracer ×1 |
| expert | 4 | 7 | 5:12 | 35 | 14s / 15s（5/7） | 46 / 199 | 2 | bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 5 | 6:21 | 39 | 13s / 12s（5/5） | 24 / 61 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 6 | 5 | 7:55 | 27 | 9s / 10s（5/5） | 21 / 43 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 5 | 9:05 | 21 | 9s / 9s（5/5） | 12 / 59 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] eyjafjalla | 16 | 31% | 6:24 / 2:15 | 0.0 / - | 8 / 16 / 23 / 18 | 24% | 51% | 58 | 969 | 熔岩弹 21% 散射 9% 余震 6% 火星 5% | 自身回复 32% 补给 18% 拾取 11% (690 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] eyjafjalla | 16 | 31% | 6:24 / 2:15 | 87% | 56% | 1:05 | 0:50 / 3:06 | 1.2 / 46s | 47.1 | 122 | 6 | 3 | 3 | 39% / 15894 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 16 | 7.8 | 4.9% | class 37/11 control 10/6 economy 42/9 general 90/42 heal 19/3 melee 15/7 multi 54/19 shield 11/6 summon 9/5 survival 44/16 weak 2/1 | 0 |
| 合计 | | | | | class 37/11 control 10/6 economy 42/9 general 90/42 heal 19/3 melee 15/7 multi 54/19 shield 11/6 summon 9/5 survival 44/16 weak 2/1 | |

拿取最多（出现 / 拿取）：洁白的舞鞋 6/5，显圣吊坠 16/4，损坏的左轮弹巢 4/4，贵族刺剑 5/4，“多功能”发夹 5/4，银餐叉 11/3，穿甲弹 17/3，安洁莉娜的创想 3/3，万能钥匙 7/3，破坏协议-压制 5/3，“国王的水晶” 4/3，涡旋座 2/2
