# balance gm_A_master_m0_s5a 1029_1536

args: `--preset starts --bot master --seed0 5 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --tag gm_A_master_m0_s5a --out build/gm/A_s5`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 7 | 7 | 3 | 121s / 103s / 162s / 99–162s | 103s / 162s | 2.4 / 3.0 | 21% |
| master | 最后的骑士 | knight 2 | 2 | 2 | 66s / 66s / 75s / 57–75s | 66s / 75s | 9.9 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 塑路者 | 8 | 7 | 69s | 0.29 | 15 | - | - |
| master | 接潮主教 | 6 | 3 | 47s | 0.07 | 16 | 1.0 | 6% |
| master | 接潮斥亡体 | 5 | 3 | 47s | 0.08 | 14 | - | - |
| master | 圣徒卡门 | 5 | 4 | 57s | 0.39 | 10 | - | - |
| master | 接潮蔑死体 | 1 | 0 | - | 0.04 | 26 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.1 / 0.0 / 0.1 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 7 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 21% | 166 / 158 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:59 |
| master | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 3:18 |
| master | 0 | shock_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:43 |
| master | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:25 |
| master | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_slider | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:36 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 94 / 126 | 100 / 176 | 3 / 9 | 278 / 411 | 26 / 48 |
| master | 0 | 9 | 8:00–10:00 | 84 / 111 | 57 / 104 | 1 / 5 | 338 / 402 | 24 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 18s / 14s（14/14） | 19 / 43 | 0 | bone/slider/stone ×14 |
| master | 2 | 12 | 2:45 | 20 | 12s / 10s（12/12） | 21 / 83 | 1 | bone/slider ×12 |
| master | 3 | 8 | 4:45 | 24 | 16s / 16s（8/8） | 1 / 10 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/floater/runner/slider ×2；bone/floater/reaper/runner/slider/tracer ×1 |
| master | 4 | 8 | 5:04 | 35 | 26s / 26s（8/8） | 19 / 75 | 0 | bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/reaper/runner/slider/tracer ×2 |
| master | 5 | 8 | 6:15 | 40 | 31s / 20s（8/8） | 41 / 110 | 1 | bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| master | 6 | 5 | 7:56 | 27 | 25s / 14s（5/5） | 33 / 80 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| master | 7 | 5 | 9:06 | 22 | 19s / 17s（5/5） | 9 / 25 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:21 / 11:43 | 0.0 / - | 8 / 14 / 22 / 28 | 8% | 100% | 86 | 1886 | 余震 42% 饱和复仇 12% 殉爆 11% 爆裂黎明 10% | 自身回复 23% 流明 22% 塞雷娅 18% (855 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 0% | 3:08 / 2:59 | 0.0 / - | 8 / 0 / 0 / 10 | - | 16% | 66 | 358 | 熔岩弹 36% 狐火 12% 光弹 9% 火星 9% | 自身回复 36% 流明 35% 拾取 18% (263 / 0.0) | contact_tracer |
| [master] skadi | 2 | 100% | 11:27 / 11:15 | 0.0 / - | 8 / 16 / 21 / 28 | - | 100% | 94 | 1898 | 大剑 27% 言 7% Mon3tr 6% 跃浪 4% | 自身回复 47% 凯尔希 19% 补给 13% (696 / 0.0) | contact_tracer |
| [master] mizuki | 2 | 100% | 11:49 / 10:57 | 0.0 / - | 7 / 16 / 22 / 27 | - | 100% | 100 | 1796 | 真实 49% 大剑 6% 延异视阈 6% 提喻 6% | 水月 64% 自身回复 21% 流明 10% (1231 / 1.0) | contact_tracer |
| [master] saria | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 6 / 14 / 18 / 22 | 37% | 100% | 81 | 1166 | 狐火 32% 震地 9% 冲锋模式 8% 拳击 8% | 塞雷娅 54% 自身回复 17% 流明 10% (1019 / 0.0) | bullet |
| [master] kaltsit | 2 | 0% | 4:34 / 2:25 | 0.0 / - | 8 / 15 / 0 / 14 | - | 33% | 14 | 640 | Mon3tr 38% 余震 11% 狐火 10% 刺剑 10% | 凯尔希 42% 自身回复 24% 结构加固 11% (561 / 0.0) | contact_tracer |
| [master] suzuran | 2 | 0% | 7:48 / 2:36 | 0.0 / - | 8 / 15 / 21 / 17 | 0% | 50% | 66 | 922 | 狐火 43% 刺剑 9% 言 8% 般若回旋 5% | 自身回复 37% 铃兰 31% 补给 19% (343 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:21 / 11:43 | 100% | 100% | 1:12 | 0:46 / 3:30 | 3.0 / 61s | 76.8 | 68 | 4 | 0 | 3 | 81% / 64103 | shock_paranoia |
| [master] eyjafjalla | 2 | 0% | 3:08 / 2:59 | 0% | 0% | 1:04 | 0:50 / 2:50 | 0.0 / - | 16.3 | 120 | 6 | 0 | 2 | 66% / 6628 | contact_tracer |
| [master] skadi | 2 | 100% | 11:27 / 11:15 | 100% | 100% | 1:05 | 0:50 / 3:37 | 2.5 / 54s | 94.1 | 60 | 4 | 0 | 4 | 45% / 35510 | - |
| [master] mizuki | 2 | 100% | 11:49 / 10:57 | 100% | 100% | 1:07 | 0:48 / 3:58 | 1.5 / 45s | 128.7 | 98 | 2 | 0 | 4 | 11% / 15730 | - |
| [master] saria | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 1:39 | 1:01 / 6:04 | 0.5 / 267s | 105.1 | 79 | 0 | 0 | 2 | 15% / 4711 | corrode |
| [master] kaltsit | 2 | 0% | 4:34 / 2:25 | 50% | 50% | 1:11 | 0:59 / 3:11 | 0.5 / 69s | 26.1 | 144 | 8 | 4 | 2 | 45% / 8686 | corrode |
| [master] suzuran | 2 | 0% | 7:48 / 2:36 | 50% | 50% | 1:00 | 0:44 / 4:07 | 0.5 / 36s | 42.8 | 73 | 2 | 0 | 2 | 44% / 8372 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 0.5 | 0.0% | heal 1/0 multi 3/1 summon 1/0 survival 4/0 | 0 |
| master | kaltsit | 2 | 3.0 | 0.0% | class 1/0 economy 1/0 general 4/2 heal 4/2 multi 1/0 summon 1/0 survival 4/2 | 0 |
| master | mizuki | 2 | 14.0 | 50.9% | class 13/3 economy 6/2 general 19/7 heal 1/1 melee 2/1 multi 2/0 shield 3/2 summon 13/9 survival 7/0 weak 5/3 | 0 |
| master | saria | 2 | 3.5 | 0.0% | class 2/0 economy 2/1 general 5/0 heal 7/4 multi 2/0 summon 1/0 survival 5/2 | 0 |
| master | skadi | 2 | 14.5 | 3.6% | class 11/1 control 3/3 economy 4/1 general 23/8 heal 1/0 melee 9/5 multi 1/0 shield 6/4 summon 6/2 survival 10/4 weak 4/1 | 0 |
| master | suzuran | 2 | 3.5 | 0.6% | class 1/0 control 2/1 general 7/1 melee 1/0 shield 1/1 survival 7/3 weak 1/1 | 0 |
| master | wisadel | 2 | 15.5 | 0.0% | class 4/0 economy 11/4 general 17/10 heal 4/2 melee 3/1 multi 12/8 shield 4/2 summon 2/1 survival 18/3 weak 4/0 | 0 |
| 合计 | | | | | class 32/4 control 5/4 economy 24/8 general 75/28 heal 18/9 melee 15/7 multi 21/9 shield 14/9 summon 24/12 survival 55/14 weak 14/5 | |

拿取最多（出现 / 拿取）：药枚 5/5，血魔的银杯 4/4，洁白的舞鞋 5/3，夜阳花 5/3，几丁质刺刃 4/3，银餐叉 5/3，散轶诗简 5/2，贵族刺剑 4/2，“苦痛的快乐” 2/2，无字珊瑚 3/2，支援起重机 3/2，特级馥郁咖啡豆 3/2
