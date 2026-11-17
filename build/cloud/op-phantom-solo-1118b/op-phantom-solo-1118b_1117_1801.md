# balance op-phantom-solo-1118b 1117_1801

args: `--op phantom --bot expert --seeds 16 --nocache --jobs 8 --tag op-phantom-solo-1118b --out build/cloud/op-phantom-solo-1118b`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 88s / 84s / 99s / 82–99s | 84s / 99s | 6.5 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 2.0 | 18% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 9 | 9 | 66s | 0.60 | 7 | - | - |
| expert | 圣徒卡门 | 8 | 5 | 60s | 0.52 | 8 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 62s | 0.28 | 10 | - | - |
| expert | 接潮主教 | 3 | 2 | 54s | 0.13 | 7 | 1.0 | 33% |
| expert | 接潮蔑死体 | 3 | 2 | 54s | 0.18 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 18% | 81% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 131 / 114 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 9:00 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:31 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:03 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:51 |
| expert | 0 | nest | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:51 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:03 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:24 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 2:09 |
| expert | 0 | corrode | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:23 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:19 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:16 |
| expert | 0 | contact_slider | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:31 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 79 / 114 | 102 / 280 | 1 / 8 | 326 / 396 | 30 / 48 |
| expert | 0 | 7 | 8:00–10:00 | 75 / 87 | 37 / 75 | 0 / 0 | 363 / 395 | 27 / 30 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 13 | 357 | 0.0 | 3.2 / 0.9% | 0.2 / 0.4% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 3 | 956 | 0.0 | 0.0 / 0.0% | 0.3 / 0.8% | 0.0 / 0.0% | 0.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 10s（16/16） | 14 / 40 | 0 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 2 | 15 | 2:45 | 20 | 10s / 10s（15/15） | 18 / 101 | 0 | bone/slider/stone ×8；bone/slider ×7 |
| expert | 3 | 13 | 4:42 | 24 | 11s / 10s（13/13） | 32 / 93 | 2 | bone/floater/runner/slider ×4；bone/floater/reaper/runner/slider/tracer ×3；bone/slider/stone ×3 |
| expert | 4 | 11 | 5:34 | 37 | 17s / 15s（10/11） | 24 / 107 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 10 | 6:22 | 38 | 20s / 13s（10/10） | 32 / 177 | 1 | bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 6 | 7 | 8:10 | 26 | 14s / 11s（7/7） | 28 / 85 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 4 | 9:06 | 22 | 9s / 9s（3/4） | 66 / 143 | 1 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] phantom | 16 | 18% | 7:40 / 2:09 | 0.0 / - | 8 / 15 / 23 / 21 | 27% | 68% | 55 | 1204 | 虚影 10% 影刃 7% 剑气 7% 真实 6% | 自身回复 47% 补给 21% 拾取 15% (633 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] phantom | 16 | 18% | 7:40 / 2:09 | 93% | 81% | 1:04 | 0:50 / 3:00 | 1.4 / 61s | 49.5 | 96 | 9 | 0 | 2 | 24% / 11734 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | phantom | 16 | 10.7 | 7.6% | class 51/24 control 18/7 economy 69/22 general 104/40 heal 13/4 melee 77/36 multi 14/7 shield 10/9 summon 16/5 survival 46/14 weak 9/3 | 0 |
| 合计 | | | | | class 51/24 control 18/7 economy 69/22 general 104/40 heal 13/4 melee 77/36 multi 14/7 shield 10/9 summon 16/5 survival 46/14 weak 9/3 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 15/13，贵族刺剑 10/6，漆黑的舞鞋 12/5，锈蚀刀片 21/5，老近卫军之锋 5/5，锈刃-突破 5/4，洁白的舞鞋 5/3，王庭盟约 3/3，万能钥匙 5/3，支援补给站 5/3，海潮的气息 0/3，悬丝傀儡 4/3
