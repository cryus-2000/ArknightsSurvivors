# balance opb-exusiai-1118a-mate-skadi 1117_1755

args: `--squad skadi,exusiai --bot expert --seeds 4 --nocache --jobs 8 --tag opb-exusiai-1118a-mate-skadi --out build/cloud/opb-exusiai-1118a/mate_skadi --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 72s / 67s / 90s / 60–90s | 67s / 90s | 9.8 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 3 | 3 | 83s | 0.50 | 6 | - | - |
| expert | 接潮主教 | 3 | 3 | 21s | 0.20 | 8 | 1.0 | 12% |
| expert | 圣徒卡门 | 2 | 1 | 38s | 0.40 | 6 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 30s | 0.16 | 8 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 16s | 0.30 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 75% | 25% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 68 / 72 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:10 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 86 / 94 | 193 / 250 | 0 / 0 | 374 / 379 | 34 / 40 |
| expert | 0 | 3 | 8:00–10:00 | 64 / 71 | 21 / 35 | 0 / 0 | 371 / 379 | 25 / 26 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 145 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 3 | 479 | 0.0 | 0.3 / 1.1% | 2.0 / 3.5% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 9s / 8s（4/4） | 8 / 17 | 0 | bone/slider ×4 |
| expert | 2 | 4 | 2:45 | 20 | 10s / 10s（4/4） | 11 / 25 | 0 | bone/slider/stone ×4 |
| expert | 3 | 4 | 4:48 | 24 | 12s / 11s（4/4） | 9 / 23 | 0 | bone/offspring/slider/stone ×2；bone/floater/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 4 | 4 | 5:38 | 37 | 17s / 17s（4/4） | 3 / 12 | 0 | bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 6:34 | 38 | 14s / 12s（3/4） | 61 / 174 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/reaper/runner/slider/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 6 | 3 | 7:47 | 26 | 10s / 9s（3/3） | 1 / 2 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 8:57 | 21 | 9s / 9s（3/3） | 42 / 101 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skadi+exusiai | 4 | 75% | 10:11 / 7:10 | 0.0 / - | 8 / 15 / 23 / 26 | 16% | 100% | 76 | 1758 | 大剑 28% 散射 10% 剑气 5% 终结技·skadi·浪头 4% | 自身回复 41% 补给 28% 浊心斯卡蒂 7% (747 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] skadi+exusiai | 4 | 75% | 10:11 / 7:10 | 100% | 100% | 1:07 | 0:51 / 3:48 | 2.5 / 42s | 31.6 | 76 | 5 | 0 | 3 | 43% / 46098 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | skadi | 4 | 16.5 | 4.0% | class 21/4 control 8/3 economy 22/6 general 42/19 heal 8/2 melee 30/10 multi 10/4 shield 5/3 summon 11/6 survival 17/5 weak 6/4 | 0 |
| 合计 | | | | | class 21/4 control 8/3 economy 22/6 general 42/19 heal 8/2 melee 30/10 multi 10/4 shield 5/3 summon 11/6 survival 17/5 weak 6/4 | |

拿取最多（出现 / 拿取）：锈蚀刀片 7/3，扣挠之手 3/3，赶车夫的长鞭 6/2，深洋主宰刻像 2/2，《旧高卢地名源流考》 3/2，恐鱼干 4/2，皇帝的恩宠 6/2，老近卫军之锋 3/2，几丁质刺刃 2/2，漆黑的舞鞋 4/1，三钥协定 1/1，神音海螺 3/1
