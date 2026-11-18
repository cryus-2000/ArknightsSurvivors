# balance op-ling-lead-1118c-ling 1118_0014

args: `--op ling --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118c-ling --out build/cloud/op-ling-lead-1118c/lead_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 8 | 75s / 76s / 90s / 51–90s | 76s / 90s | 10.0 / 2.6 | - |
| expert | 最后的骑士 | knight 3 | 3 | 3 | 49s / 50s / 52s / 46–52s | 50s / 52s | 6.8 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 18 | 16 | 61s | 0.57 | 6 | - | - |
| expert | 圣徒卡门 | 16 | 10 | 37s | 0.47 | 6 | - | - |
| expert | 接潮主教 | 7 | 6 | 38s | 0.17 | 7 | 1.2 | 22% |
| expert | 接潮蔑死体 | 4 | 3 | 35s | 0.21 | 10 | - | - |
| expert | 接潮斥亡体 | 3 | 3 | 51s | 0.20 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 1 | 34s | 0.29 | 12 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 7 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 34% | 65% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 9% | 139 / 142 | 92% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 6 | 4:27 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 2 | 1:41 |
| expert | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 2 | 5:25 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:15 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:50 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:24 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:51 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:20 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 8:24 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:05 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:21 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:02 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:04 |
| expert | 0 | contact_tracer | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:22 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 73 / 107 | 99 / 250 | 1 / 8 | 306 / 439 | 28 / 45 |
| expert | 0 | 13 | 8:00–10:00 | 66 / 81 | 29 / 59 | 0 / 1 | 364 / 427 | 26 / 40 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 21 | 282 | 0.0 | 1.7 / 0.4% | 0.2 / 0.5% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 11 | 786 | 0.3 | 4.5 / 0.2% | 2.4 / 3.4% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 11s（31/32） | 16 / 81 | 3 | bone/slider/stone ×18；bone/slider ×14 |
| expert | 2 | 29 | 2:45 | 20 | 9s / 9s（29/29） | 21 / 82 | 0 | bone/slider ×18；bone/slider/stone ×11 |
| expert | 3 | 21 | 4:34 | 24 | 10s / 11s（21/21） | 33 / 129 | 1 | bone/offspring/slider/stone ×8；bone/reaper/runner/slider/tracer ×5；bone/floater/runner/slider ×3 |
| expert | 4 | 19 | 5:24 | 36 | 16s / 14s（18/19） | 24 / 85 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×6；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 5 | 16 | 6:21 | 39 | 13s / 12s（14/16） | 30 / 116 | 2 | bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/reaper/runner/slider/tracer ×4 |
| expert | 6 | 12 | 7:50 | 26 | 9s / 10s（12/12） | 13 / 53 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×5；bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 12 | 9:00 | 22 | 9s / 9s（11/12） | 32 / 168 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 32 | 34% | 7:06 / 1:21 | 0.0 / - | 8 / 16 / 23 / 20 | 19% | 60% | 63 | 1132 | 逍遥 8% 逍遥·鸣瑟 7% 泼墨 5% 弦惊·剑气 4% | 自身回复 42% 补给 16% 拾取 12% (607 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 32 | 34% | 7:06 / 1:21 | 90% | 65% | 1:05 | 0:50 / 3:16 | 1.2 / 47s | 52.4 | 95 | 9 | 0 | 2 | 47% / 25233 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | ling | 32 | 9.1 | 4.5% | class 78/28 control 19/9 economy 88/23 general 206/90 heal 25/8 melee 53/17 multi 40/13 shield 29/15 summon 105/45 survival 88/35 weak 23/9 | 0 |
| 合计 | | | | | class 78/28 control 19/9 economy 88/23 general 206/90 heal 25/8 melee 53/17 multi 40/13 shield 29/15 summon 105/45 survival 88/35 weak 23/9 | |

拿取最多（出现 / 拿取）：散轶诗简 28/11，“多功能”发夹 15/9，海程 16/8，衍生者终端-超级改 34/6，赶车夫的长鞭 12/6，炸裂之手 6/5，《旧高卢地名源流考》 11/5，扣挠之手 7/5，恐鱼干 12/5，古乔治营养原浆 6/5，便携经书 8/4，摩根队长佳酿 9/4
