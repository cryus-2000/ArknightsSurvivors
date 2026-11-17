# balance opb-hoshiguma-1118a-lead 1117_1753

args: `--op hoshiguma --bot expert --seeds 16 --nocache --jobs 8 --tag opb-hoshiguma-1118a-lead --out build/cloud/opb-hoshiguma-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 93s / 85s / 125s / 83–125s | 85s / 125s | 6.1 / 2.7 | 75% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 33s / 33s / 33s / 33–33s | 33s / 33s | 9.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 9 | 69s | 0.48 | 7 | - | - |
| expert | 接潮主教 | 7 | 6 | 40s | 0.17 | 6 | 1.0 | 15% |
| expert | 塑路者 | 5 | 4 | 82s | 0.32 | 9 | - | - |
| expert | 接潮斥亡体 | 4 | 4 | 46s | 0.19 | 6 | - | - |
| expert | 接潮蔑死体 | 3 | 2 | 34s | 0.20 | 8 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 42s | 0.39 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.1 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 107 / 106 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:37 |
| expert | 0 | contact_founder | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:11 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:29 |
| expert | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:54 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:02 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:15 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:10 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:50 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 80 / 122 | 135 / 250 | 0 / 4 | 343 / 422 | 42 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 71 / 83 | 22 / 31 | 0 / 0 | 381 / 420 | 36 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 290 | 0.0 | 0.3 / 0.6% | 0.2 / 0.2% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 1126 | 0.0 | 0.2 / 0.1% | 0.8 / 1.2% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 11s（15/16） | 15 / 74 | 1 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 2 | 15 | 2:45 | 20 | 8s / 9s（15/15） | 8 / 31 | 0 | bone/slider/stone ×8；bone/slider ×7 |
| expert | 3 | 12 | 4:57 | 24 | 14s / 10s（12/12） | 18 / 67 | 1 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 4 | 10 | 5:53 | 37 | 16s / 15s（9/10） | 24 / 111 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 5 | 9 | 6:47 | 39 | 13s / 13s（9/9） | 9 / 29 | 0 | bone/reaper/runner/slider/tracer ×2；bone/floater/reaper/runner/slider/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 6 | 8 | 8:03 | 27 | 8s / 8s（8/8） | 26 / 78 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×5；bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 8 | 9:08 | 22 | 9s / 8s（8/8） | 54 / 187 | 1 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma | 16 | 37% | 8:00 / 1:29 | 0.0 / - | 8 / 15 / 23 / 21 | 32% | 63% | 54 | 1271 | 举盾反击 8% 盾斧斩 7% 剑气 6% 余震 5% | 自身回复 47% 拾取 15% 补给 15% (617 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma | 16 | 37% | 8:00 / 1:29 | 93% | 68% | 1:06 | 0:48 / 3:26 | 1.6 / 56s | 58.1 | 89 | 8 | 3 | 3 | 24% / 13366 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 16 | 10.2 | 4.0% | class 38/15 control 9/3 economy 40/16 general 125/54 heal 14/8 melee 62/18 multi 11/6 shield 17/10 summon 15/6 survival 49/16 weak 19/11 | 0 |
| 合计 | | | | | class 38/15 control 9/3 economy 40/16 general 125/54 heal 14/8 melee 62/18 multi 11/6 shield 17/10 summon 15/6 survival 49/16 weak 19/11 | |

拿取最多（出现 / 拿取）：贵族刺剑 9/5，老近卫军之锋 5/5，残破合影 6/5，《旧高卢地名源流考》 7/4，锈蚀刀片 21/3，恐鱼干 9/3，药枚 3/3，热水壶 6/3，疗养体验卡 5/3，穿甲弹 2/3，漆黑的舞鞋 4/3，生还者合约 3/3
