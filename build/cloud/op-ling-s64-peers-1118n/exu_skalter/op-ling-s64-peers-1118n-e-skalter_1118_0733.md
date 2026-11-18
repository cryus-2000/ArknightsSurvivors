# balance op-ling-s64-peers-1118n-e-skalter 1118_0733

args: `--squad exusiai,skalter --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-e-skalter --out build/cloud/op-ling-s64-peers-1118n/exu_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 19 | 19 | 13 | 65s / 63s / 76s / 45–104s | 63s / 76s | 10.9 / 2.9 | 34% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 48s / 48s / 48s / 48–48s | 48s / 48s | 5.9 / 2.0 | - |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 48s / 48s / 48s / 48–48s | 28s / 28s | 6.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 23 | 22 | 52s | 0.59 | 5 | - | - |
| expert | 接潮主教 | 14 | 14 | 36s | 0.18 | 6 | 1.0 | 16% |
| expert | 圣徒卡门 | 14 | 14 | 48s | 0.47 | 5 | - | - |
| expert | 接潮蔑死体 | 7 | 7 | 27s | 0.25 | 4 | - | - |
| expert | 接潮斥亡体 | 7 | 7 | 37s | 0.16 | 6 | - | - |
| expert | 圣徒伊比利亚 | 5 | 5 | 34s | 0.37 | 4 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 46% | 53% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 89 / 88 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 2 | 10:34 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 8:19 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:37 |
| expert | 0 | boss_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:16 |
| expert | 0 | shock_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:32 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:15 |
| expert | 0 | contact_reaper | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:35 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:13 |
| expert | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:20 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:38 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:49 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 1:30 |
| expert | 0 | contact_slider | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:22 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:10 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 82 / 116 | 162 / 250 | 0 / 9 | 345 / 424 | 30 / 41 |
| expert | 0 | 24 | 8:00–10:00 | 62 / 77 | 21 / 46 | 0 / 5 | 358 / 409 | 27 / 35 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 17 | 446 | 0.2 | 4.2 / 1.3% | 1.6 / 4.0% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 15 | 760 | 0.0 | 2.3 / 0.5% | 1.7 / 3.3% | 0.0 / 0.0% | 0.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 9s（32/32） | 17 / 96 | 1 | bone/slider ×22；bone/slider/stone ×10 |
| expert | 2 | 31 | 2:45 | 20 | 8s / 8s（31/31） | 10 / 53 | 0 | bone/slider/stone ×21；bone/slider ×10 |
| expert | 3 | 31 | 4:35 | 24 | 12s / 9s（30/31） | 20 / 136 | 2 | bone/floater/runner/slider ×9；bone/offspring/slider/stone ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 4 | 29 | 5:25 | 36 | 12s / 12s（27/29） | 23 / 135 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×11；bone/floater/reaper/runner/slider/tracer ×7 |
| expert | 5 | 27 | 6:22 | 39 | 13s / 12s（25/27） | 17 / 104 | 2 | bone/floater/reaper/runner/slider/tracer ×10；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×6 |
| expert | 6 | 24 | 7:53 | 27 | 7s / 7s（24/24） | 11 / 57 | 2 | bone/founder/nest/offspring/runner/slider/stone/tracer ×9；bone/founder/nest/runner/slider/spitter/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×7 |
| expert | 7 | 21 | 9:00 | 21 | 8s / 9s（21/21） | 37 / 126 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×8；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×7；bone/floater/offspring/reaper/runner/slider/spitter/stone ×6 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 32 | 46% | 9:21 / 1:30 | 0.0 / - | 8 / 16 / 24 / 25 | 11% | 91% | 55 | 1636 | 散射 25% 弹匣倾泻 11% 真实 8% 过载模式 8% | 自身回复 26% 浊心斯卡蒂 21% 补给 14% (728 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 32 | 46% | 9:21 / 1:30 | 96% | 93% | 1:09 | 0:50 / 3:37 | 2.2 / 45s | 54.1 | 85 | 4 | 0 | 3 | 29% / 27402 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 14.6 | 8.7% | class 110/41 control 34/19 economy 140/51 general 310/152 heal 40/9 melee 71/25 multi 164/63 shield 45/23 summon 49/19 survival 138/50 weak 29/15 | 0 |
| 合计 | | | | | class 110/41 control 34/19 economy 140/51 general 310/152 heal 40/9 melee 71/25 multi 164/63 shield 45/23 summon 49/19 survival 138/50 weak 29/15 | |

拿取最多（出现 / 拿取）：显圣吊坠 43/14，洁白的舞鞋 31/13，损坏的左轮弹巢 19/13，穿甲弹 36/12，银餐叉 35/11，“多功能”发夹 19/10，《旧高卢地名源流考》 18/9，远程协议-遥击 14/8，散轶诗简 17/7，赶车夫的长鞭 15/6，凯旋号角 10/6，老近卫军之锋 7/6
