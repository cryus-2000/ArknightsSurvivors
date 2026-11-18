# balance op-ling-s64-ling-1118n-h-ling 1118_0717

args: `--squad hoshiguma,ling --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-ling-1118n-h-ling --out build/cloud/op-ling-s64-ling-1118n/hos_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 19 | 19 | 14 | 102s / 99s / 148s / 51–161s | 99s / 148s | 4.7 / 2.6 | 57% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 51s / 51s / 51s / 51–51s | 51s / 51s | 4.0 / 2.0 | 0% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 73s / 73s / 73s / 73–73s | 53s / 53s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 24 | 22 | 65s | 0.48 | 6 | - | - |
| expert | 接潮主教 | 18 | 17 | 54s | 0.15 | 10 | 1.4 | 22% |
| expert | 塑路者 | 15 | 15 | 67s | 0.53 | 7 | - | - |
| expert | 接潮斥亡体 | 11 | 11 | 46s | 0.15 | 9 | - | - |
| expert | 接潮蔑死体 | 7 | 6 | 60s | 0.19 | 12 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 74s | 0.23 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 12 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 50% | 50% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 76 / 70 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 9:07 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:03 |
| expert | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:15 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:27 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 11:00 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:48 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:29 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:57 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 11:00 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:48 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:18 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 9:56 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:52 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:39 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 90 / 120 | 177 / 319 | 0 / 10 | 392 / 438 | 45 / 48 |
| expert | 0 | 27 | 8:00–10:00 | 78 / 96 | 39 / 114 | 0 / 5 | 392 / 438 | 37 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 16 | 712 | 0.0 | 2.0 / 0.4% | 0.6 / 0.8% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 16 | 1184 | 0.1 | 0.1 / 0.0% | 0.6 / 1.1% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 8 / 25 | 0 | bone/slider ×17；bone/slider/stone ×15 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 8 / 60 | 0 | bone/slider/stone ×17；bone/slider ×15 |
| expert | 3 | 30 | 4:55 | 24 | 13s / 11s（29/30） | 21 / 93 | 1 | bone/reaper/runner/slider/tracer ×8；bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 4 | 29 | 5:47 | 37 | 18s / 14s（28/29） | 19 / 78 | 1 | bone/floater/reaper/runner/slider/tracer ×12；bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/reaper/runner/slider/tracer ×5 |
| expert | 5 | 28 | 6:49 | 38 | 18s / 14s（28/28） | 22 / 150 | 0 | bone/reaper/runner/slider/tracer ×10；bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 6 | 24 | 8:08 | 27 | 10s / 10s（23/24） | 14 / 84 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×9；bone/founder/nest/offspring/runner/slider/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×5 |
| expert | 7 | 20 | 9:09 | 22 | 13s / 10s（20/20） | 23 / 175 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×10；bone/floater/offspring/reaper/runner/slider/spitter/stone ×7；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 32 | 50% | 10:12 / 4:47 | 0.0 / - | 8 / 15 / 22 / 26 | 21% | 90% | 63 | 1660 | 举盾反击 8% 剑气 6% 弦惊·剑势 5% 真实 5% | 自身回复 40% 补给 20% 拾取 13% (757 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+ling | 32 | 50% | 10:12 / 4:47 | 100% | 96% | 1:13 | 0:46 / 3:13 | 2.3 / 64s | 75.2 | 82 | 9 | 2 | 4 | 21% / 20991 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 13.5 | 6.1% | class 110/41 control 33/12 economy 117/43 general 329/122 heal 45/13 melee 180/69 multi 34/11 shield 57/24 summon 60/25 survival 162/57 weak 34/14 | 0 |
| 合计 | | | | | class 110/41 control 33/12 economy 117/43 general 329/122 heal 45/13 melee 180/69 multi 34/11 shield 57/24 summon 60/25 survival 162/57 weak 34/14 | |

拿取最多（出现 / 拿取）：锈蚀刀片 52/16，赶车夫的长鞭 31/14，漆黑的舞鞋 24/11，皇帝的恩宠 41/10，老近卫军之锋 11/9，贵族刺剑 21/9，“多功能”发夹 23/8，《旧高卢地名源流考》 21/8，“岁怒” 8/7，支援防暴桩 16/6，判官经文布 9/6，《大静谧》 7/6
