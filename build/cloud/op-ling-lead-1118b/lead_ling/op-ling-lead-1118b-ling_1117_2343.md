# balance op-ling-lead-1118b-ling 1117_2343

args: `--op ling --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118b-ling --out build/cloud/op-ling-lead-1118b/lead_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 5 | 5 | 4 | 93s / 91s / 130s / 60–130s | 92s / 130s | 6.4 / 3.0 | 9% |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 49s / 49s / 50s / 49–50s | 50s / 50s | 6.6 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 11 | 8 | 47s | 0.47 | 7 | - | - |
| expert | 塑路者 | 8 | 7 | 49s | 0.59 | 8 | - | - |
| expert | 接潮主教 | 5 | 4 | 46s | 0.18 | 7 | 1.0 | 0% |
| expert | 接潮蔑死体 | 4 | 4 | 46s | 0.18 | 8 | - | - |
| expert | 接潮斥亡体 | 1 | 0 | - | 0.15 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 145 / 132 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:04 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:34 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:39 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:57 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:07 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:19 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:56 |
| expert | 0 | mire | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:18 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:34 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 78 / 129 | 127 / 319 | 0 / 4 | 301 / 413 | 27 / 36 |
| expert | 0 | 7 | 8:00–10:00 | 73 / 85 | 26 / 33 | 0 / 0 | 381 / 397 | 27 / 35 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 258 | 0.0 | 0.3 / 0.4% | 0.1 / 0.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 1131 | 1.7 | 0.2 / 0.0% | 6.2 / 6.0% | 0.0 / 0.0% | 1.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 10s（16/16） | 25 / 90 | 1 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 15 | 2:45 | 20 | 9s / 10s（15/15） | 14 / 41 | 0 | bone/slider ×9；bone/slider/stone ×6 |
| expert | 3 | 12 | 4:32 | 24 | 13s / 9s（10/12） | 29 / 121 | 2 | bone/floater/runner/slider ×5；bone/slider/stone ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 4 | 10 | 5:18 | 36 | 18s / 12s（9/10） | 24 / 145 | 1 | bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 5 | 9 | 6:18 | 39 | 19s / 13s（9/9） | 31 / 58 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| expert | 6 | 7 | 7:55 | 27 | 10s / 9s（7/7） | 20 / 49 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 7 | 9:05 | 22 | 12s / 11s（6/7） | 18 / 47 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 16 | 37% | 7:46 / 1:39 | 0.0 / - | 8 / 16 / 23 / 21 | 31% | 66% | 62 | 1228 | 逍遥 8% 逍遥·鸣瑟 7% 真实 6% 弦惊·剑气 6% | 自身回复 39% 补给 19% 塞雷娅 16% (791 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 16 | 37% | 7:46 / 1:39 | 93% | 68% | 1:04 | 0:51 / 2:35 | 1.4 / 48s | 51.9 | 104 | 5 | 0 | 2 | 49% / 30176 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | ling | 16 | 9.5 | 7.0% | class 30/8 control 11/6 economy 41/14 general 127/59 heal 14/4 melee 16/1 multi 14/5 shield 12/6 summon 71/33 survival 48/15 weak 8/1 | 0 |
| 合计 | | | | | class 30/8 control 11/6 economy 41/14 general 127/59 heal 14/4 melee 16/1 multi 14/5 shield 12/6 summon 71/33 survival 48/15 weak 8/1 | |

拿取最多（出现 / 拿取）：散轶诗简 14/7，海程 14/7，几丁质刺刃 8/4，“岁怒” 4/4，胎生百合 5/4，无字珊瑚 5/4，洁白的舞鞋 6/3，古旧乐谱残章 4/3，海潮的气息 0/3，《旧高卢地名源流考》 4/3，生命之水 6/3，扣挠之手 4/3
