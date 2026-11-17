# balance opb-saria-1118a-mate-skadi 1117_1756

args: `--squad skadi,saria --bot expert --seeds 4 --nocache --jobs 8 --tag opb-saria-1118a-mate-skadi --out build/cloud/opb-saria-1118a/mate_skadi --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 103s / 114s / 119s / 76–119s | 114s / 119s | 4.8 / 3.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 44s / 44s / 44s / 44–44s | 44s / 44s | 6.5 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 4 | 4 | 60s | 0.43 | 7 | - | - |
| expert | 接潮主教 | 3 | 3 | 33s | 0.21 | 8 | 1.0 | 15% |
| expert | 接潮斥亡体 | 2 | 2 | 28s | 0.19 | 8 | - | - |
| expert | 塑路者 | 1 | 1 | 88s | 0.54 | 10 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 35s | 0.19 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 100% | 0% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 102 / 104 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | （全部胜利） | | | | 0 | |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 86 / 95 | 184 / 250 | 4 / 8 | 399 / 439 | 39 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 70 / 86 | 25 / 28 | 2 / 5 | 387 / 439 | 38 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 胜 | 4 | 1166 | 0.5 | 0.0 / 0.0% | 4.5 / 6.4% | 0.0 / 0.0% | 1.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 10s / 9s（4/4） | 9 / 18 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 8s / 9s（4/4） | 15 / 30 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 4 | 4:52 | 24 | 11s / 10s（4/4） | 31 / 47 | 0 | bone/floater/reaper/runner/slider/tracer ×1；bone/slider/stone ×1；bone/floater/runner/slider ×1 |
| expert | 4 | 4 | 5:42 | 38 | 16s / 14s（4/4） | 20 / 52 | 0 | bone/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 6:47 | 39 | 15s / 14s（4/4） | 11 / 28 | 0 | bone/floater/reaper/runner/slider/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 4 | 8:02 | 27 | 8s / 6s（4/4） | 15 / 43 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 4 | 9:07 | 22 | 14s / 13s（4/4） | 37 / 55 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skadi+saria | 4 | 100% | 11:28 / 10:44 | 0.0 / - | 8 / 15 / 22 / 28 | 0% | 100% | 75 | 1916 | 大剑 33% 迅捷打击·γ型 6% 剑气 5% 跃浪击 5% | 塞雷娅 49% 自身回复 21% 拾取 7% (1310 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skadi+saria | 4 | 100% | 11:28 / 10:44 | 100% | 100% | 1:07 | 0:46 / 4:00 | 2.8 / 47s | 85.1 | 116 | 1 | 0 | 4 | 53% / 62496 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | skadi | 4 | 16.0 | 9.0% | class 26/9 control 2/1 economy 10/7 general 44/18 heal 11/4 melee 18/6 multi 6/3 shield 5/0 summon 8/7 survival 21/8 weak 2/1 | 0 |
| 合计 | | | | | class 26/9 control 2/1 economy 10/7 general 44/18 heal 11/4 melee 18/6 multi 6/3 shield 5/0 summon 8/7 survival 21/8 weak 2/1 | |

拿取最多（出现 / 拿取）：地形图 4/2，血魔的银杯 3/2，生命之水 2/2，皇帝的恩宠 7/2，主教的研究 0/2，穿甲弹 2/2，赶车夫的长鞭 3/2，堡垒协议-方阵 2/2，涌动之餐 2/2，扣挠之手 2/2，大教堂拼图 2/2，散轶诗简 2/2
