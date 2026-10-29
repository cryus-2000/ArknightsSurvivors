# balance gm_B_master_m18_s1a 1029_1545

args: `--preset starts --bot master --seed0 1 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --meta=18 --tag gm_B_master_m18_s1a --out build/gm/B_s1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| master | 偏执泡影 | standard 10 | 10 | 6 | 120s / 121s / 147s / 92–147s | 121s / 147s | 5.6 / 3.0 | 28% |
| master | 最后的骑士 | knight 1 | 1 | 1 | 51s / 51s / 51s / 51–51s | 51s / 51s | 17.6 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| master | 圣徒卡门 | 9 | 8 | 82s | 0.16 | 8 | - | - |
| master | 塑路者 | 8 | 8 | 62s | 0.36 | 9 | - | - |
| master | 接潮主教 | 7 | 3 | 36s | 0.03 | 16 | 1.0 | 6% |
| master | 接潮斥亡体 | 5 | 2 | 28s | 0.06 | 14 | - | - |
| master | 接潮蔑死体 | 2 | 1 | 141s | 0.07 | 19 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 16 | 0.0 / 0.0 / 0.0 / 0 | 17 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| master | 0 | 14 | 7% | 100 / 94 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| master | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:38 |
| master | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | boss_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| master | 0 | contact_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |
| master | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:36 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| master | 0 | 14 | 全程 | 114 / 193 | 125 / 192 | 3 / 7 | 327 / 419 | 29 / 48 |
| master | 0 | 11 | 8:00–10:00 | 79 / 133 | 65 / 121 | 2 / 5 | 314 / 402 | 23 / 46 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| master | 1 | 14 | 1:15 | 15 | 11s / 10s（14/14） | 13 / 41 | 0 | bone/slider ×14 |
| master | 2 | 14 | 2:45 | 20 | 12s / 11s（13/14） | 28 / 125 | 1 | bone/slider/stone ×14 |
| master | 3 | 10 | 4:54 | 25 | 28s / 12s（10/10） | 7 / 36 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/slider/stone ×3；bone/offspring/slider/stone ×1 |
| master | 4 | 10 | 5:17 | 36 | 34s / 28s（10/10） | 18 / 58 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| master | 5 | 10 | 6:17 | 40 | 35s / 32s（9/10） | 12 / 45 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×2 |
| master | 6 | 5 | 7:59 | 26 | 17s / 17s（5/5） | 5 / 18 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |
| master | 7 | 4 | 8:58 | 21 | 22s / 16s（4/4） | 17 / 30 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 9:05 / 6:38 | 0.0 / - | 8 / 15 / 22 / 24 | - | 83% | 92 | 1492 | 余震 31% 饱和复仇 10% 殉爆 9% 爆裂黎明 6% | 自身回复 35% 塞雷娅 24% 补给 21% (265 / 0.0) | contact_tracer |
| [master] eyjafjalla | 2 | 50% | 12:40 / 12:20 | 0.0 / - | 8 / 14 / 18 / 24 | 17% | 100% | 84 | 1231 | 熔岩弹 18% 余震 16% 刺剑 7% 火山 5% | 水月 35% 自身回复 35% 补给 16% (1256 / 0.5) | boss_carmen |
| [master] skadi | 2 | 100% | 11:15 / 10:51 | 0.0 / - | 8 / 16 / 22 / 28 | - | 100% | 96 | 1976 | 真实 48% 余震 14% 大剑 7% 饱和复仇 5% | 凯尔希 45% 自身回复 35% 结构加固 7% (489 / 0.0) | contact_tracer |
| [master] mizuki | 2 | 0% | 13:00 / 13:00 | 0.0 / - | 8 / 14 / 20 / 24 | 32% | 100% | 100 | 1504 | Mon3tr 14% 锚击 12% 狐火 12% 伞击 11% | 水月 46% 自身回复 21% 流明 12% (1004 / 0.0) | contact_tracer |
| [master] saria | 2 | 100% | 12:01 / 11:43 | 0.0 / - | 8 / 14 / 20 / 26 | - | 100% | 99 | 1580 | 熔岩弹 17% 锯刃 17% 替身闪现 11% 拳击 5% | 塞雷娅 52% 自身回复 15% 针剂回流 11% (906 / 0.0) | contact_tracer |
| [master] kaltsit | 2 | 0% | 7:53 / 2:47 | 0.0 / - | 8 / 16 / 21 / 18 | 30% | 50% | 86 | 950 | Mon3tr 34% 双刃 11% 刺剑 10% 言 6% | 凯尔希 48% 自身回复 29% 结构加固 17% (997 / 0.0) | contact_tracer |
| [master] suzuran | 2 | 50% | 9:01 / 5:36 | 0.0 / - | 8 / 14 / 21 / 20 | - | 66% | 66 | 1212 | 狐火 16% 余震 11% 炮击 9% 饱和复仇 6% | 自身回复 38% 铃兰 32% 补给 19% (583 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [master] wisadel | 2 | 50% | 9:05 / 6:38 | 100% | 100% | 1:06 | 0:46 / 3:56 | 2.0 / 46s | 28.2 | 40 | 14 | 0 | 2 | 62% / 36659 | contact_reaper |
| [master] eyjafjalla | 2 | 50% | 12:40 / 12:20 | 100% | 100% | 0:56 | 0:57 / 7:17 | 1.5 / 195s | 67.8 | 82 | 40 | 68 | 2 | 41% / 17156 | corrode |
| [master] skadi | 2 | 100% | 11:15 / 10:51 | 100% | 100% | 1:08 | 0:50 / 3:49 | 2.5 / 30s | 70.5 | 41 | 0 | 0 | 5 | 13% / 34050 | - |
| [master] mizuki | 2 | 0% | 13:00 / 13:00 | 100% | 100% | 1:10 | 0:49 / 5:29 | 1.0 / 117s | 125.1 | 77 | 0 | 0 | 4 | 23% / 12022 | boss_paranoia |
| [master] saria | 2 | 100% | 12:01 / 11:43 | 100% | 100% | 1:25 | 0:53 / 3:01 | 1.5 / 95s | 109.7 | 73 | 0 | 0 | 2 | 10% / 5604 | - |
| [master] kaltsit | 2 | 0% | 7:53 / 2:47 | 50% | 50% | 1:09 | 0:53 / 4:48 | 1.0 / 114s | 95.5 | 94 | 0 | 76 | 2 | 41% / 9908 | contact_tracer |
| [master] suzuran | 2 | 50% | 9:01 / 5:36 | 100% | 100% | 1:05 | 0:46 / 2:03 | 1.5 / 81s | 70.5 | 72 | 0 | 0 | 3 | 21% / 9192 | contact_reaper |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| master | eyjafjalla | 2 | 8.0 | 0.0% | class 6/0 economy 1/1 general 10/1 heal 1/0 melee 4/1 multi 9/4 shield 2/2 summon 0/1 survival 12/6 weak 3/0 | 0 |
| master | kaltsit | 2 | 2.5 | 1.9% | class 2/1 economy 1/0 general 8/0 heal 6/3 melee 1/0 multi 1/0 summon 3/1 survival 2/0 | 0 |
| master | mizuki | 2 | 6.0 | 0.3% | class 8/2 economy 2/0 general 8/0 heal 5/2 melee 1/0 multi 1/1 summon 8/4 survival 4/2 weak 1/1 | 0 |
| master | saria | 2 | 10.5 | 0.1% | class 8/1 control 2/2 economy 3/0 general 18/8 heal 8/3 melee 1/1 multi 2/0 shield 1/0 summon 1/0 survival 11/3 weak 4/3 | 0 |
| master | skadi | 2 | 15.0 | 51.4% | class 4/1 economy 13/5 general 18/8 heal 4/2 melee 10/7 multi 2/1 summon 2/1 survival 12/3 weak 4/2 | 0 |
| master | suzuran | 2 | 7.0 | 4.3% | class 2/0 control 8/5 economy 3/1 general 12/3 heal 1/0 melee 5/3 multi 1/0 summon 2/1 survival 5/1 weak 2/0 | 0 |
| master | wisadel | 2 | 9.5 | 2.7% | class 9/2 economy 2/0 general 8/5 heal 2/2 multi 5/3 shield 3/2 summon 3/0 survival 13/4 weak 4/1 | 0 |
| 合计 | | | | | class 39/7 control 10/7 economy 25/7 general 82/25 heal 27/12 melee 22/12 multi 21/9 shield 6/4 summon 19/8 survival 59/19 weak 18/7 | |

拿取最多（出现 / 拿取）：涌动之餐 4/4，凯旋号角 4/4，设计师量尺 4/3，损坏的左轮弹巢 3/3，衍生者终端-超级改 4/3，开裂的束缚带 6/3，穿甲弹 6/3，锈蚀刀片 9/3，食腐者手杖 3/3，贵族刺剑 3/3，大教堂拼图 2/2，银餐叉 3/2
