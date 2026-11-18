# balance op-ling-s64-peers-1118n-l-skalter 1118_0730

args: `--op skalter --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-l-skalter --out build/cloud/op-ling-s64-peers-1118n/lead_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 6 | 125s / 104s / 235s / 72–235s | 104s / 235s | 5.0 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 16 | 12 | 68s | 0.47 | 6 | - | - |
| expert | 塑路者 | 14 | 11 | 73s | 0.52 | 6 | - | - |
| expert | 接潮主教 | 8 | 6 | 52s | 0.15 | 9 | 1.0 | 6% |
| expert | 接潮蔑死体 | 5 | 5 | 52s | 0.16 | 11 | - | - |
| expert | 接潮斥亡体 | 3 | 1 | 36s | 0.14 | 11 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 44s | 0.34 | 12 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 6 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 18% | 81% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 6% | 241 / 233 | 92% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 4 | 3:47 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 2 | 4:38 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 2 | 6:50 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:32 |
| expert | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:00 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:17 |
| expert | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:17 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:28 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:52 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:57 |
| expert | 0 | atk_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:52 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:12 |
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:33 |
| expert | 0 | mire | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:37 |
| expert | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:08 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:23 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:58 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:19 |
| expert | 0 | mire | 未缩圈 | 否 | 否 | 1 | 1:49 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:57 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 75 / 120 | 97 / 319 | 1 / 5 | 369 / 437 | 37 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 75 / 88 | 30 / 52 | 0 / 0 | 406 / 422 | 37 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 26 | 397 | 0.0 | 7.1 / 1.6% | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 1295 | 1.7 | 4.7 / 0.3% | 6.2 / 6.1% | 0.0 / 0.0% | 1.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 15s / 14s（32/32） | 15 / 58 | 0 | bone/slider ×17；bone/slider/stone ×15 |
| expert | 2 | 30 | 2:45 | 20 | 9s / 9s（30/30） | 20 / 89 | 0 | bone/slider ×15；bone/slider/stone ×15 |
| expert | 3 | 21 | 4:50 | 24 | 14s / 12s（20/21） | 43 / 113 | 3 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/slider/stone ×5；bone/reaper/runner/slider/tracer ×5 |
| expert | 4 | 16 | 5:44 | 37 | 18s / 13s（15/16） | 25 / 106 | 2 | bone/reaper/runner/slider/tracer ×7；bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 5 | 12 | 6:41 | 38 | 17s / 17s（9/12） | 54 / 139 | 3 | bone/reaper/runner/slider/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 6 | 8 | 8:07 | 26 | 12s / 10s（8/8） | 34 / 108 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 5 | 9:07 | 21 | 10s / 10s（5/5） | 32 / 84 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 32 | 18% | 6:34 / 1:49 | 0.0 / - | 7 / 15 / 22 / 18 | 42% | 58% | 42 | 964 | 声浪 19% 拳击 5% 终结技·skalter·激光 5% 剑气 4% | 自身回复 26% 浊心斯卡蒂 26% 塞雷娅 11% (793 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skalter | 32 | 18% | 6:34 / 1:49 | 93% | 65% | 1:16 | 1:04 / 3:03 | 1.2 / 61s | 55.1 | 130 | 7 | 7 | 3 | 26% / 8579 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | skalter | 32 | 6.7 | 2.8% | class 56/15 control 9/4 economy 73/30 general 156/67 heal 100/28 melee 29/11 multi 23/2 shield 28/21 summon 20/10 survival 58/22 weak 14/3 | 0 |
| 合计 | | | | | class 56/15 control 9/4 economy 73/30 general 156/67 heal 100/28 melee 29/11 multi 23/2 shield 28/21 summon 20/10 survival 58/22 weak 14/3 | |

拿取最多（出现 / 拿取）：食腐者手杖 21/9，《旧高卢地名源流考》 10/8，“多功能”发夹 9/7，海潮的气息 0/5，遥乡之引 9/5，药枚 5/5，“荒诞命运” 8/4，血魔的银杯 17/4，演出用香水 14/4，堡垒协议-方阵 10/4，三钥协定 6/3，苍白花冠 9/3
