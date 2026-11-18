# balance op-ling-hos-1118c-angelina 1118_0027

args: `--squad hoshiguma,angelina --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118c-angelina --out build/cloud/op-ling-hos-1118c/hos_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 21 | 21 | 13 | 141s / 113s / 213s / 59–313s | 113s / 213s | 2.3 / 2.7 | 39% |
| expert | 最后的骑士 | knight 3 | 3 | 3 | 86s / 74s / 129s / 55–129s | 74s / 129s | 2.0 / 2.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 2.8 / 2.0 | 11% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 54s / 54s / 54s / 54–54s | 34s / 34s | 1.3 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 19 | 17 | 67s | 0.46 | 7 | - | - |
| expert | 接潮主教 | 15 | 15 | 66s | 0.13 | 8 | 1.1 | 14% |
| expert | 塑路者 | 15 | 15 | 69s | 0.49 | 8 | - | - |
| expert | 接潮蔑死体 | 13 | 13 | 66s | 0.16 | 9 | - | - |
| expert | 圣徒伊比利亚 | 5 | 5 | 60s | 0.23 | 10 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 79s | 0.13 | 12 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 15 | 0.0 / 0.0 / 0.0 / 0 | 16 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 53% | 46% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 12% | 98 / 94 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 5 | 10:51 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 2 | 1:48 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:16 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:39 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:47 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:16 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 14:09 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:05 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 85 / 128 | 188 / 320 | 1 / 10 | 368 / 447 | 42 / 48 |
| expert | 0 | 26 | 8:00–10:00 | 81 / 114 | 32 / 104 | 1 / 8 | 387 / 447 | 37 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 15 | 465 | 0.1 | 0.1 / 0.0% | 0.7 / 1.7% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 17 | 604 | 0.1 | 0.0 / 0.0% | 1.9 / 2.7% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 13s / 11s（31/32） | 15 / 76 | 1 | bone/slider/stone ×21；bone/slider ×11 |
| expert | 2 | 28 | 2:45 | 20 | 9s / 8s（28/28） | 6 / 24 | 0 | bone/slider ×17；bone/slider/stone ×11 |
| expert | 3 | 26 | 5:05 | 24 | 12s / 11s（26/26） | 12 / 76 | 0 | bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×7；bone/floater/runner/slider ×5 |
| expert | 4 | 26 | 5:55 | 37 | 22s / 15s（26/26） | 9 / 77 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×6 |
| expert | 5 | 25 | 6:57 | 39 | 18s / 14s（25/25） | 3 / 34 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 6 | 25 | 8:26 | 25 | 12s / 11s（23/25） | 9 / 45 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×10；bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5 |
| expert | 7 | 13 | 9:11 | 22 | 10s / 10s（13/13） | 17 / 98 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 32 | 53% | 10:11 / 1:44 | 0.0 / - | 8 / 15 / 22 / 24 | 18% | 83% | 64 | 1526 | 举盾反击 12% 真实 8% 秘杖·速充模式 7% 剑气 7% | 自身回复 46% 补给 17% 拾取 14% (638 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 32 | 53% | 10:11 / 1:44 | 87% | 87% | 1:21 | 0:47 / 2:50 | 2.1 / 71s | 45.1 | 71 | 6 | 0 | 5 | 30% / 26272 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 13.5 | 10.1% | class 106/42 control 33/16 economy 119/44 general 305/126 heal 56/25 melee 165/66 multi 44/17 shield 55/23 summon 39/12 survival 124/47 weak 39/14 | 0 |
| 合计 | | | | | class 106/42 control 33/16 economy 119/44 general 305/126 heal 56/25 melee 165/66 multi 44/17 shield 55/23 summon 39/12 survival 124/47 weak 39/14 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 39/22，贵族刺剑 28/13，《旧高卢地名源流考》 20/11，老近卫军之锋 11/9，皇帝的恩宠 34/8，食腐者手杖 13/8，锈蚀刀片 36/7，漆黑的舞鞋 17/7，“绝唱” 7/7，血魔的银杯 11/6，洁白的舞鞋 16/6，“多功能”发夹 18/6
