# balance op-ling-hos-1118c-suzuran 1118_0024

args: `--squad hoshiguma,suzuran --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118c-suzuran --out build/cloud/op-ling-hos-1118c/hos_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 18 | 18 | 13 | 100s / 92s / 161s / 52–175s | 92s / 161s | 5.4 / 2.8 | 41% |
| expert | 最后的骑士 | knight 5 | 5 | 4 | 97s / 100s / 120s / 70–120s | 100s / 120s | 3.2 / 2.0 | 37% |
| expert | 伊祖米克 | resolve 3 | 3 | 3 | 98s / 71s / 154s / 69–154s | 51s / 134s | 0.0 / 2.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 47s / 47s / 47s / 47–47s | 47s / 47s | 9.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 21 | 19 | 45s | 0.52 | 7 | - | - |
| expert | 接潮主教 | 20 | 20 | 47s | 0.17 | 11 | 1.0 | 10% |
| expert | 塑路者 | 17 | 17 | 52s | 0.62 | 7 | - | - |
| expert | 接潮蔑死体 | 10 | 10 | 47s | 0.17 | 12 | - | - |
| expert | 接潮斥亡体 | 10 | 10 | 43s | 0.17 | 11 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 46s | 0.37 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 65% | 34% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 81 / 81 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:45 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:03 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:23 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:21 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:20 |
| expert | 0 | nest | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:26 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:20 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 9:03 |
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:02 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 94 / 155 | 180 / 318 | 9 / 12 | 384 / 423 | 44 / 48 |
| expert | 0 | 29 | 8:00–10:00 | 81 / 155 | 28 / 59 | 7 / 10 | 391 / 423 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 11 | 786 | 0.1 | 2.4 / 0.4% | 2.3 / 6.0% | 0.0 / 0.0% | 0.3 |
| expert | 0 | 胜 | 21 | 811 | 0.0 | 1.2 / 0.1% | 0.8 / 1.4% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 12s / 11s（32/32） | 12 / 36 | 0 | bone/slider ×16；bone/slider/stone ×16 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 7 / 29 | 0 | bone/slider/stone ×16；bone/slider ×15 |
| expert | 3 | 29 | 4:33 | 25 | 11s / 11s（29/29） | 8 / 49 | 0 | bone/floater/runner/slider ×10；bone/slider/stone ×8；bone/floater/reaper/runner/slider/tracer ×4 |
| expert | 4 | 29 | 5:26 | 36 | 19s / 15s（29/29） | 13 / 105 | 0 | bone/reaper/runner/slider/tracer ×10；bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/floater/reaper/runner/slider/tracer ×9 |
| expert | 5 | 29 | 6:24 | 39 | 18s / 16s（28/29） | 17 / 106 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×7 |
| expert | 6 | 28 | 8:00 | 27 | 12s / 11s（27/28） | 24 / 152 | 2 | bone/founder/nest/runner/slider/spitter/stone/tracer ×13；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/offspring/runner/slider/stone/tracer ×7 |
| expert | 7 | 24 | 9:05 | 22 | 11s / 11s（24/24） | 17 / 93 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×13；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 32 | 65% | 10:34 / 2:02 | 0.0 / - | 8 / 16 / 22 / 26 | 20% | 91% | 70 | 1750 | 举盾反击 12% 狐火 11% 剑气 8% 真实 7% | 自身回复 35% 补给 18% 拾取 14% (719 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 32 | 65% | 10:34 / 2:02 | 96% | 93% | 1:10 | 0:46 / 2:56 | 2.4 / 52s | 65.2 | 75 | 7 | 0 | 5 | 27% / 26843 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 14.8 | 9.1% | class 102/32 control 38/18 economy 137/43 general 374/171 heal 41/15 melee 201/69 multi 42/16 shield 58/26 summon 49/22 survival 157/45 weak 27/17 | 0 |
| 合计 | | | | | class 102/32 control 38/18 economy 137/43 general 374/171 heal 41/15 melee 201/69 multi 42/16 shield 58/26 summon 49/22 survival 157/45 weak 27/17 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 33/14，锈蚀刀片 48/13，《旧高卢地名源流考》 25/12，贵族刺剑 32/12，皇帝的恩宠 42/11，老近卫军之锋 17/11，漆黑的舞鞋 29/8，“多功能”发夹 18/7，“国王的水晶” 9/6，支援急救包 17/6，摩根队长佳酿 11/6，锈刃-可视静谧 13/5
