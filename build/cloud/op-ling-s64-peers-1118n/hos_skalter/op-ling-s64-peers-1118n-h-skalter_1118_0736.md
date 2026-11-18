# balance op-ling-s64-peers-1118n-h-skalter 1118_0736

args: `--squad hoshiguma,skalter --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-h-skalter --out build/cloud/op-ling-s64-peers-1118n/hos_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 22 | 22 | 17 | 116s / 93s / 247s / 51–335s | 93s / 247s | 5.1 / 2.5 | 75% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 89s / 89s / 89s / 89–89s | 89s / 89s | 3.0 / 2.0 | 14% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 67s / 67s / 67s / 67–67s | 47s / 47s | 1.5 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 22 | 19 | 77s | 0.29 | 8 | - | - |
| expert | 塑路者 | 19 | 18 | 81s | 0.49 | 8 | - | - |
| expert | 接潮主教 | 17 | 17 | 56s | 0.14 | 10 | 1.1 | 15% |
| expert | 接潮斥亡体 | 9 | 9 | 54s | 0.18 | 9 | - | - |
| expert | 接潮蔑死体 | 8 | 8 | 60s | 0.17 | 13 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 45s | 0.33 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 16 | 0.0 / 0.0 / 0.0 / 0 | 20 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 59% | 40% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 100 / 78 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 10:28 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 2 | 10:15 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:32 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:21 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:19 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:28 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 9:06 |
| expert | 0 | boss_carmen | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:33 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:10 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 93 / 121 | 179 / 320 | 1 / 9 | 400 / 428 | 44 / 48 |
| expert | 0 | 27 | 8:00–10:00 | 81 / 121 | 35 / 94 | 0 / 5 | 401 / 428 | 38 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 13 | 913 | 0.0 | 2.8 / 0.5% | 0.3 / 0.4% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 19 | 1112 | 0.1 | 0.2 / 0.0% | 0.9 / 1.1% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 10s（32/32） | 10 / 23 | 0 | bone/slider ×18；bone/slider/stone ×14 |
| expert | 2 | 32 | 2:45 | 20 | 9s / 9s（32/32） | 9 / 32 | 0 | bone/slider/stone ×18；bone/slider ×14 |
| expert | 3 | 27 | 5:06 | 24 | 11s / 10s（27/27） | 12 / 62 | 0 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 4 | 27 | 6:01 | 38 | 17s / 13s（27/27） | 21 / 100 | 0 | bone/floater/reaper/runner/slider/tracer ×12；bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 5 | 26 | 7:08 | 38 | 20s / 17s（25/26） | 20 / 129 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×7；bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×5 |
| expert | 6 | 23 | 8:20 | 26 | 13s / 10s（23/23） | 9 / 35 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/founder/nest/runner/slider/spitter/stone/tracer ×4 |
| expert | 7 | 16 | 9:12 | 22 | 11s / 10s（16/16） | 31 / 142 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×7；bone/floater/offspring/reaper/runner/slider/spitter/stone ×7；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 32 | 59% | 10:31 / 4:10 | 0.0 / - | 8 / 15 / 22 / 26 | 24% | 92% | 50 | 1637 | 举盾反击 11% 剑气 9% 声浪 5% 真实 5% | 浊心斯卡蒂 32% 自身回复 30% 补给 13% (923 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 32 | 59% | 10:31 / 4:10 | 100% | 96% | 1:17 | 0:50 / 3:02 | 2.3 / 74s | 80.9 | 89 | 7 | 2 | 4 | 30% / 28099 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 12.9 | 5.8% | class 107/29 control 46/27 economy 119/46 general 331/139 heal 40/11 melee 148/51 multi 25/7 shield 52/25 summon 53/25 survival 122/42 weak 29/10 | 0 |
| 合计 | | | | | class 107/29 control 46/27 economy 119/46 general 331/139 heal 40/11 melee 148/51 multi 25/7 shield 52/25 summon 53/25 survival 122/42 weak 29/10 | |

拿取最多（出现 / 拿取）：漆黑的舞鞋 27/12，贵族刺剑 28/11，《旧高卢地名源流考》 17/10，锈蚀刀片 31/8，赶车夫的长鞭 24/8，皇帝的恩宠 29/7，立体艺术装置 12/7，“绽放” 12/7，“小格兰法洛” 7/6，药枚 14/6，未知仪器 8/6，海潮的气息 0/6
