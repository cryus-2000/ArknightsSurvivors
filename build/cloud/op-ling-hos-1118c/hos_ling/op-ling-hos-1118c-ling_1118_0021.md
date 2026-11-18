# balance op-ling-hos-1118c-ling 1118_0021

args: `--squad hoshiguma,ling --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118c-ling --out build/cloud/op-ling-hos-1118c/hos_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 22 | 22 | 15 | 113s / 100s / 186s / 72–195s | 100s / 186s | 4.0 / 2.9 | 40% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 84s / 84s / 114s / 54–114s | 84s / 114s | 2.6 / 1.3 | 69% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 19 | 18 | 78s | 0.47 | 8 | - | - |
| expert | 接潮主教 | 18 | 16 | 54s | 0.13 | 9 | 1.1 | 19% |
| expert | 圣徒卡门 | 18 | 15 | 66s | 0.41 | 7 | - | - |
| expert | 接潮蔑死体 | 12 | 11 | 54s | 0.16 | 10 | - | - |
| expert | 接潮斥亡体 | 6 | 5 | 61s | 0.16 | 9 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 64s | 0.28 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 53% | 46% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 109 / 106 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 10:49 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 7:45 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:37 |
| expert | 0 | boss_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:21 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:56 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:38 |
| expert | 0 | bullet | 未缩圈 | 否 | 否 | 1 | 1:40 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:12 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:14 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:58 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:58 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 86 / 115 | 181 / 320 | 0 / 4 | 384 / 452 | 44 / 48 |
| expert | 0 | 25 | 8:00–10:00 | 77 / 99 | 36 / 113 | 0 / 0 | 399 / 438 | 36 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 15 | 647 | 0.1 | 0.1 / 0.0% | 0.7 / 1.2% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 17 | 1201 | 0.2 | 0.4 / 0.0% | 1.3 / 2.0% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 13s / 12s（32/32） | 14 / 42 | 1 | bone/slider/stone ×20；bone/slider ×12 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 14 / 51 | 0 | bone/slider ×19；bone/slider/stone ×12 |
| expert | 3 | 26 | 4:59 | 24 | 13s / 12s（26/26） | 17 / 72 | 0 | bone/reaper/runner/slider/tracer ×7；bone/offspring/slider/stone ×7；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 4 | 26 | 5:56 | 37 | 17s / 16s（26/26） | 17 / 81 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×8；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 5 | 25 | 6:48 | 38 | 18s / 15s（24/25） | 16 / 66 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 6 | 21 | 8:06 | 26 | 11s / 10s（21/21） | 15 / 64 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×10；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 17 | 9:07 | 22 | 11s / 11s（17/17） | 31 / 133 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×7；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 32 | 53% | 10:02 / 1:40 | 0.0 / - | 8 / 15 / 22 / 25 | 28% | 88% | 65 | 1575 | 举盾反击 9% 弦惊·剑气 6% 剑气 5% 弦惊·剑势 5% | 自身回复 42% 补给 19% 拾取 15% (784 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 32 | 53% | 10:02 / 1:40 | 96% | 87% | 1:27 | 0:47 / 3:21 | 2.1 / 71s | 78.0 | 85 | 11 | 1 | 4 | 21% / 18345 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 11.8 | 5.0% | class 115/40 control 32/18 economy 110/33 general 307/122 heal 28/9 melee 166/52 multi 41/15 shield 44/23 summon 41/14 survival 117/43 weak 26/9 | 0 |
| 合计 | | | | | class 115/40 control 32/18 economy 110/33 general 307/122 heal 28/9 melee 166/52 multi 41/15 shield 44/23 summon 41/14 survival 117/43 weak 26/9 | |

拿取最多（出现 / 拿取）：“多功能”发夹 23/14，皇帝的恩宠 25/12，锈蚀刀片 40/10，漆黑的舞鞋 30/10，贵族刺剑 38/8，赶车夫的长鞭 24/8，永流之手 8/6，支援起重机 9/5，支援补给站 9/5，铁卫-临时要塞 9/5，银餐叉 15/5，堡垒协议-方阵 9/5
