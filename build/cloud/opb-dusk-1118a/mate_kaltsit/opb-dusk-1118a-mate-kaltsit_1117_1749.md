# balance opb-dusk-1118a-mate-kaltsit 1117_1749

args: `--squad kaltsit,dusk --bot expert --seeds 4 --nocache --jobs 8 --tag opb-dusk-1118a-mate-kaltsit --out build/cloud/opb-dusk-1118a/mate_kaltsit --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 2 | 2 | 2 | 100s / 100s / 119s / 81–119s | 100s / 119s | 4.1 / 3.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 58s / 58s / 58s / 58–58s | 58s / 58s | 3.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 3 | 2 | 60s | 0.51 | 6 | - | - |
| expert | 接潮主教 | 2 | 2 | 53s | 0.14 | 12 | 1.0 | 16% |
| expert | 接潮蔑死体 | 2 | 2 | 53s | 0.17 | 12 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 37s | 0.44 | 9 | - | - |
| expert | 圣徒卡门 | 1 | 1 | 79s | 0.40 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 75% | 25% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 160 / 134 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:14 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 87 / 114 | 183 / 250 | 4 / 9 | 368 / 402 | 34 / 48 |
| expert | 0 | 3 | 8:00–10:00 | 73 / 75 | 28 / 29 | 4 / 9 | 379 / 402 | 24 / 27 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 651 | 0.0 | 1.0 / 0.4% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 3 | 1453 | 0.3 | 9.7 / 0.1% | 2.7 / 3.1% | 0.0 / 0.0% | 0.7 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 8s / 8s（4/4） | 8 / 20 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 10s / 10s（4/4） | 7 / 12 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 3 | 4:48 | 24 | 10s / 10s（3/3） | 20 / 30 | 0 | bone/floater/runner/slider ×1；bone/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 4 | 3 | 5:38 | 37 | 15s / 16s（3/3） | 33 / 46 | 0 | bone/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 3 | 6:33 | 37 | 23s / 15s（3/3） | 24 / 36 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 6 | 3 | 7:59 | 27 | 11s / 12s（3/3） | 22 / 44 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 9:09 | 21 | 9s / 9s（3/3） | 21 / 34 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+dusk | 4 | 75% | 9:53 / 5:14 | 0.0 / - | 8 / 15 / 23 / 24 | 11% | 75% | 46 | 1603 | Mon3tr 25% Mon3tr · 真伤 10% 墨弹 7% 小自在 7% | 凯尔希 34% 自身回复 24% 结构加固 19% (1120 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] kaltsit+dusk | 4 | 75% | 9:53 / 5:14 | 100% | 100% | 1:13 | 0:48 / 2:18 | 2.0 / 55s | 92.2 | 119 | 2 | 6 | 4 | 39% / 37398 | contact_reaper |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | kaltsit | 4 | 13.8 | 9.2% | class 24/8 control 1/0 economy 13/5 general 43/20 heal 18/6 melee 19/5 multi 3/0 shield 6/1 summon 7/2 survival 23/7 weak 4/1 | 0 |
| 合计 | | | | | class 24/8 control 1/0 economy 13/5 general 43/20 heal 18/6 melee 19/5 multi 3/0 shield 6/1 summon 7/2 survival 23/7 weak 4/1 | |

拿取最多（出现 / 拿取）：食腐者手杖 2/2，赶车夫的长鞭 5/2，净尘之手 2/2，老近卫军之锋 2/2，四叶草化石 2/2，蓝卡坞安全衣 2/2，玻璃小鸟 2/1，恐鱼干 2/1，支援防暴桩 1/1，地底的灼痕 2/1，涡旋座 1/1，贵族刺剑 3/1
