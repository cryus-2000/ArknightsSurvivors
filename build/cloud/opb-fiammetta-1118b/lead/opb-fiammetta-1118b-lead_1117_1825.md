# balance opb-fiammetta-1118b-lead 1117_1825

args: `--op fiammetta --bot expert --seeds 16 --nocache --jobs 8 --tag opb-fiammetta-1118b-lead --out build/cloud/opb-fiammetta-1118b/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 77s / 74s / 95s / 63–95s | 74s / 95s | 7.8 / 3.0 | 34% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 68s / 68s / 68s / 68–68s | 68s / 68s | 3.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 11 | 8 | 41s | 0.57 | 5 | - | - |
| expert | 接潮主教 | 6 | 6 | 45s | 0.17 | 9 | 1.0 | 19% |
| expert | 塑路者 | 6 | 4 | 43s | 0.61 | 6 | - | - |
| expert | 接潮斥亡体 | 3 | 3 | 46s | 0.16 | 8 | - | - |
| expert | 接潮蔑死体 | 3 | 3 | 33s | 0.22 | 12 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 178 / 172 | 90% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:52 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:19 |
| expert | 0 | atk_reaper | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:33 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:08 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:19 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:35 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:48 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:25 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 76 / 111 | 133 / 250 | 6 / 11 | 299 / 412 | 28 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 71 / 88 | 27 / 36 | 4 / 7 | 355 / 412 | 29 / 38 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 289 | 0.0 | 1.0 / 0.8% | 0.2 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 1026 | 0.2 | 2.5 / 0.1% | 2.2 / 4.2% | 0.0 / 0.0% | 0.7 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 12s / 12s（16/16） | 15 / 52 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| expert | 2 | 15 | 2:45 | 20 | 9s / 9s（15/15） | 16 / 52 | 0 | bone/slider ×10；bone/slider/stone ×5 |
| expert | 3 | 10 | 4:24 | 25 | 12s / 12s（10/10） | 22 / 55 | 0 | bone/slider/stone ×5；bone/offspring/slider/stone ×2；bone/floater/runner/slider ×2 |
| expert | 4 | 10 | 5:14 | 36 | 16s / 16s（10/10） | 13 / 60 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 5 | 10 | 6:18 | 39 | 17s / 14s（8/10） | 42 / 126 | 2 | bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| expert | 6 | 8 | 7:55 | 27 | 10s / 10s（8/8） | 36 / 96 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 6 | 8:59 | 22 | 9s / 9s（6/6） | 18 / 48 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] fiammetta | 16 | 37% | 7:46 / 2:25 | 0.0 / - | 8 / 16 / 23 / 21 | 16% | 65% | 73 | 1247 | 散射 17% 炮击 13% 你须愧悔 8% 灼痕弹道 5% | 自身回复 36% 拾取 19% 补给 14% (722 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] fiammetta | 16 | 37% | 7:46 / 2:25 | 93% | 68% | 1:08 | 0:59 / 3:01 | 1.5 / 44s | 57.9 | 106 | 10 | 0 | 3 | 34% / 18917 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | fiammetta | 16 | 10.4 | 6.6% | class 31/8 control 13/6 economy 48/19 general 107/44 heal 11/4 melee 26/10 multi 70/25 shield 19/11 summon 11/4 survival 62/31 weak 11/5 | 0 |
| 合计 | | | | | class 31/8 control 13/6 economy 48/19 general 107/44 heal 11/4 melee 26/10 multi 70/25 shield 19/11 summon 11/4 survival 62/31 weak 11/5 | |

拿取最多（出现 / 拿取）：洁白的舞鞋 16/9，银餐叉 11/6，“多功能”发夹 9/5，被撬开的道具箱 5/5，地底的灼痕 6/4，《旧高卢地名源流考》 7/4，漆黑的舞鞋 5/4，损坏的左轮弹巢 4/4，显圣吊坠 27/3，穿甲弹 12/3，老近卫军之锋 3/3，荣耀绶带 3/3
