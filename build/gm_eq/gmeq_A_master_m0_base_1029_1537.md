# balance gmeq_A_master_m0_base 1029_1537

args: `--preset starts --bot master --seed0 1 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --trace=1 --tag gmeq_A_master_m0_base --out build/gm_eq`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 7 | 7 | 2 | 105s / 105s / 115s / 95–115s | 105s / 115s | 0.9 / 2.7 | 38% |
| master | 最后的骑士 | knight 2 | 2 | 1 | 138s / 138s / 138s / 138–138s | 138s / 138s | 0.6 / 2.0 | 11% |
| master | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 0.0 / 1.0 | 59% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 塑路者 | 8 | 6 | 56s | 0.40 | 15 | - | - |
| master | 接潮主教 | 5 | 2 | 58s | 0.03 | 18 | 1.7 | 2% |
| master | 圣徒卡门 | 5 | 3 | 116s | 0.27 | 14 | - | - |
| master | 接潮蔑死体 | 3 | 2 | 58s | 0.09 | 20 | - | - |
| master | 圣徒伊比利亚 | 3 | 0 | - | 0.06 | 18 | - | - |
| master | 接潮斥亡体 | 2 | 2 | 172s | 0.08 | 20 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 20 | 0.0 / 0.0 / 0.0 / 0 | 21 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 14% | 195 / 182 | 88% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| master | 0 | bullet | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:04 |
| master | 0 | boss_knight_boss | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:37 |
| master | 0 | boss_ishar | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:47 |
| master | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 115 / 221 | 102 / 176 | 2 / 9 | 301 / 435 | 26 / 48 |
| master | 0 | 10 | 8:00–10:00 | 75 / 110 | 66 / 99 | 1 / 5 | 310 / 392 | 16 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 15s / 11s（14/14） | 18 / 60 | 0 | bone/slider ×13；bone/slider/stone ×1 |
| master | 2 | 12 | 2:45 | 20 | 12s / 11s（12/12） | 28 / 96 | 1 | bone/slider/stone ×11；bone/slider ×1 |
| master | 3 | 9 | 5:05 | 25 | 29s / 17s（9/9） | 4 / 35 | 0 | bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/offspring/slider/stone ×2 |
| master | 4 | 9 | 5:19 | 36 | 57s / 22s（9/9） | 28 / 139 | 0 | bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| master | 5 | 8 | 6:15 | 40 | 60s / 42s（8/8） | 37 / 87 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| master | 6 | 2 | 8:09 | 28 | 17s / 17s（2/2） | 6 / 11 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| master | 7 | 1 | 9:06 | 22 | 14s / 14s（1/1） | 10 / 10 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:27 / 11:55 | 0.0 / - | 8 / 16 / 22 / 26 | 45% | 100% | 87 | 1742 | 余震 30% 饱和复仇 7% 爆裂黎明 7% Mon3tr 6% | 自身回复 25% 塞雷娅 25% 凯尔希 21% (919 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 0% | 2:47 / 2:31 | 0.0 / - | 8 / 0 / 0 / 10 | - | 0% | 20 | 294 | 熔岩弹 34% 炮击 14% 火星 8% 钩索 8% | 自身回复 44% 补给 30% 拾取 15% (248 / 0.0) | contact_tracer |
| [master] skadi | 2 | 100% | 11:56 / 11:35 | 0.0 / - | 8 / 15 / 22 / 26 | - | 100% | 74 | 1725 | 大剑 27% Mon3tr 8% 刺剑 6% 跃浪 6% | 自身回复 31% 凯尔希 20% 流明 19% (1115 / 0.0) | contact_tracer |
| [master] mizuki | 2 | 0% | 7:48 / 2:37 | 0.0 / - | 8 / 14 / 18 / 16 | 11% | 50% | 66 | 728 | 触手 19% 伞击 17% 锯刃 11% 言 9% | 水月 59% 自身回复 20% 塞雷娅 15% (1054 / 0.0) | contact_tracer |
| [master] saria | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 6 / 14 / 20 / 24 | 33% | 100% | 97 | 1564 | Mon3tr 20% 余震 17% 锚击 11% 撼地 6% | 塞雷娅 43% 自身回复 22% 凯尔希 21% (1008 / 0.0) | contact_tracer |
| [master] kaltsit | 2 | 0% | 9:23 / 5:47 | 0.0 / - | 8 / 14 / 18 / 20 | 76% | 66% | 32 | 1032 | Mon3tr 28% Mon3tr · 真伤 11% 锚击 9% 刺剑 8% | 凯尔希 41% 自身回复 24% 结构加固 22% (1041 / 0.0) | contact_tracer |
| [master] suzuran | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 8 / 14 / 20 / 24 | 32% | 100% | 100 | 1353 | 狐火 39% Mon3tr 17% 藏品 7% 拳击 5% | 自身回复 21% 凯尔希 18% 塞雷娅 17% (990 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 12:27 / 11:55 | 100% | 100% | 1:08 | 0:47 / 2:19 | 2.0 / 54s | 127.3 | 65 | 0 | 31 | 3 | 57% / 35101 | shock_paranoia |
| [master] eyjafjalla | 2 | 0% | 2:47 / 2:31 | 0% | 0% | 0:56 | 0:58 / - | 0.0 / - | 24.9 | 120 | 12 | 0 | 1 | 53% / 4451 | bullet |
| [master] skadi | 2 | 100% | 11:56 / 11:35 | 100% | 100% | 1:06 | 0:49 / 3:46 | 2.0 / 64s | 108.9 | 78 | 4 | 57 | 4 | 50% / 36051 | - |
| [master] mizuki | 2 | 0% | 7:48 / 2:37 | 50% | 50% | 1:06 | 0:51 / 4:07 | 0.0 / - | 87.2 | 134 | 2 | 55 | 0 | 43% / 8172 | atk_tracer |
| [master] saria | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 1:27 | 0:50 / 3:06 | 1.5 / 142s | 148.0 | 76 | 0 | 7 | 2 | 8% / 4171 | boss_ishar |
| [master] kaltsit | 2 | 0% | 9:23 / 5:47 | 100% | 100% | 1:06 | 0:51 / 3:19 | 0.5 / 50s | 101.1 | 101 | 4 | 56 | 2 | 41% / 12361 | corrode |
| [master] suzuran | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 1:06 | 0:47 / 3:40 | 1.5 / 133s | 105.3 | 72 | 12 | 9 | 2 | 40% / 16072 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 1.5 | 0.0% | general 3/1 melee 1/0 multi 2/1 summon 1/0 survival 2/1 | 0 |
| master | kaltsit | 2 | 5.5 | 0.0% | class 1/0 economy 2/1 general 11/5 heal 6/3 multi 1/1 shield 4/1 survival 7/0 weak 2/0 | 0 |
| master | mizuki | 2 | 2.0 | 0.0% | class 1/0 general 4/2 melee 1/0 summon 5/2 survival 3/0 weak 1/0 | 0 |
| master | saria | 2 | 6.0 | 0.0% | class 4/0 control 1/1 economy 2/1 general 4/3 heal 8/4 melee 1/0 multi 1/0 shield 1/1 summon 3/1 survival 8/1 | 0 |
| master | skadi | 2 | 9.0 | 0.0% | class 4/0 control 1/0 economy 4/0 general 11/3 heal 2/1 melee 14/9 multi 1/0 shield 6/4 summon 1/0 survival 11/1 | 0 |
| master | suzuran | 2 | 7.0 | 7.3% | class 4/0 control 6/4 economy 1/0 general 8/3 heal 2/1 multi 1/0 shield 2/2 summon 1/1 survival 6/3 | 0 |
| master | wisadel | 2 | 12.0 | 0.4% | class 8/4 control 1/1 economy 1/1 general 17/6 heal 4/0 melee 4/1 multi 12/5 shield 4/2 summon 3/0 survival 10/2 weak 4/2 | 0 |
| 合计 | | | | | class 22/4 control 9/6 economy 10/3 general 58/23 heal 22/9 melee 21/10 multi 18/7 shield 17/10 summon 14/4 survival 47/8 weak 7/2 | |

拿取最多（出现 / 拿取）：药枚 4/4，穿甲弹 4/3，苍白花冠 3/3，凯旋号角 4/3，贵族刺剑 5/3，海程 6/2，香草沙士汽水 5/2，猎人的口粮 4/2，特级馥郁咖啡豆 6/2，永流之手 3/2，海潮的气息 0/2，遥乡之引 3/2
