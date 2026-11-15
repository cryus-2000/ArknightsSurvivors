# balance evmore-base 1115_1609

args: `--preset starts --bots expert,normal --seeds 8 --seed0 31 --nocache --jobs 8 --tag evmore-base --out build/cloud/evmore-base`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 33 | 33 | 30 | 97s / 95s / 113s / 86–114s | 96s / 113s | 18.2 / 2.9 | 14% |
| expert | 最后的骑士 | knight 4 | 4 | 3 | 61s / 58s / 81s / 46–81s | 58s / 81s | 9.8 / 2.0 | 33% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 47s / 47s / 47s / 47–47s | 47s / 47s | 6.4 / 2.0 | - |
| normal | 偏执泡影 | standard 1 | 1 | 0 | - | - | 6.7 / 1.0 | 78% |
| normal | 最后的骑士 | knight 1 | 1 | 1 | 59s / 59s / 59s / 59–59s | 59s / 59s | 9.2 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 35 | 33 | 61s | 0.52 | 7 | - | - |
| expert | 圣徒卡门 | 33 | 29 | 60s | 0.52 | 6 | - | - |
| expert | 接潮主教 | 28 | 26 | 49s | 0.16 | 7 | 1.1 | 16% |
| expert | 接潮蔑死体 | 15 | 15 | 49s | 0.22 | 7 | - | - |
| expert | 接潮斥亡体 | 13 | 11 | 54s | 0.15 | 8 | - | - |
| expert | 圣徒伊比利亚 | 6 | 6 | 56s | 0.31 | 7 | - | - |
| normal | 塑路者 | 27 | 8 | 60s | 0.54 | 9 | - | - |
| normal | 圣徒卡门 | 19 | 6 | 46s | 0.35 | 7 | - | - |
| normal | 接潮主教 | 4 | 0 | - | 0.00 | 14 | - | - |
| normal | 接潮蔑死体 | 3 | 0 | - | 0.33 | 14 | - | - |
| normal | 圣徒伊比利亚 | 1 | 1 | 39s | 0.40 | 8 | - | - |
| normal | 接潮斥亡体 | 1 | 0 | - | 0.17 | 16 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 56 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 13 |
| normal | 0 | 56 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 4 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 56 | 60% | 35% | 3% (2) | 5% |
| normal | 0 | 56 | 1% | 98% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 56 | 0% | 138 / 144 | 98% |
| normal | 0 | 56 | 8% | 182 / 169 | 82% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:43 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 8:54 |
| expert | 0 | contact_founder | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:18 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 否 | 1 | 8:12 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:54 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| expert | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:09 |
| expert | 0 | contact_founder | 第 4 轮 · 稳定 | 否 | 否 | 1 | 8:55 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:12 |
| expert | 0 | wound | 第 1 轮 · 稳定 | 否 | 否 | 1 | 8:20 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:55 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:52 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:08 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:58 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:23 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:43 |
| expert | 0 | nest | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:06 |
| normal | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 8 | 4:26 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 5 | 4:34 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 4 | 3:57 |
| normal | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 4 | 4:08 |
| normal | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 4 | 4:07 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 3 | 3:26 |
| normal | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 3 | 3:47 |
| normal | 0 | shock_path | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:02 |
| normal | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 否 | 2 | 3:26 |
| normal | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 2 | 2:44 |
| normal | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:03 |
| normal | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:56 |
| normal | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:11 |
| normal | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 1:58 |
| normal | 0 | mire | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:33 |
| normal | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:15 |
| normal | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:56 |
| normal | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:08 |
| normal | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:05 |
| normal | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:18 |
| normal | 0 | contact_slider | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:46 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 3:25 |
| normal | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:37 |
| normal | 0 | atk_nest | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| normal | 0 | mire | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:45 |
| normal | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:58 |
| normal | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:25 |
| normal | 0 | nest | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:02 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 56 | 全程 | 86 / 123 | 160 / 319 | 3 / 11 | 381 / 492 | 40 / 48 |
| expert | 0 | 43 | 8:00–10:00 | 75 / 106 | 29 / 96 | 1 / 7 | 382 / 490 | 36 / 48 |
| normal | 0 | 56 | 全程 | 74 / 163 | 40 / 102 | 2 / 8 | 309 / 479 | 34 / 48 |
| normal | 0 | 2 | 8:00–10:00 | 65 / 66 | 18 / 23 | 4 / 8 | 368 / 370 | 33 / 34 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 22 | 645 | 0.0 | 2.4 / 0.5% | 0.3 / 0.4% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 34 | 986 | 0.2 | 1.4 / 0.2% | 1.3 / 2.0% | 0.0 / 0.0% | 0.3 |
| normal | 0 | 失败 | 55 | 264 | 0.0 | 2.0 / 0.4% | 0.2 / 0.7% | 0.0 / 0.0% | 0.1 |
| normal | 0 | 胜 | 1 | 410 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 56 | 1:15 | 15 | 11s / 11s（56/56） | 13 / 60 | 0 | bone/slider/stone ×36；bone/slider ×20 |
| expert | 2 | 56 | 2:45 | 20 | 9s / 9s（56/56） | 13 / 80 | 0 | bone/slider ×36；bone/slider/stone ×20 |
| expert | 3 | 50 | 4:49 | 24 | 11s / 10s（50/50） | 24 / 104 | 2 | bone/slider/stone ×13；bone/reaper/runner/slider/tracer ×11；bone/floater/runner/slider ×10 |
| expert | 4 | 48 | 5:40 | 37 | 13s / 11s（47/48） | 18 / 97 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×19；bone/reaper/runner/slider/tracer ×13；bone/floater/reaper/runner/slider/tracer ×12 |
| expert | 5 | 47 | 6:43 | 39 | 15s / 14s（43/47） | 32 / 148 | 5 | bone/reaper/runner/slider/tracer ×13；bone/floater/reaper/runner/slider/tracer ×11；bone/offspring/reaper/runner/slider/spitter/tracer ×7 |
| expert | 6 | 38 | 8:05 | 26 | 9s / 9s（37/38） | 21 / 167 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×13；bone/founder/nest/offspring/runner/slider/stone/tracer ×12；bone/floater/founder/nest/runner/slider/stone/tracer ×9 |
| expert | 7 | 30 | 9:04 | 22 | 10s / 9s（29/30） | 35 / 149 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×16；bone/floater/offspring/reaper/runner/slider/spitter/stone ×10；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4 |
| normal | 1 | 56 | 1:15 | 15 | 15s / 12s（56/56） | 31 / 121 | 0 | bone/slider/stone ×28；bone/slider ×28 |
| normal | 2 | 53 | 2:45 | 20 | 9s / 9s（51/53） | 21 / 72 | 2 | bone/slider ×27；bone/slider/stone ×26 |
| normal | 3 | 13 | 4:41 | 25 | 12s / 10s（10/13） | 30 / 69 | 5 | bone/slider/stone ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/floater/runner/slider ×3 |
| normal | 4 | 7 | 5:31 | 37 | 16s / 17s（6/7） | 53 / 132 | 1 | bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| normal | 5 | 4 | 6:16 | 39 | 12s / 12s（4/4） | 15 / 61 | 0 | bone/reaper/runner/slider/tracer ×2；bone/floater/reaper/runner/slider/tracer ×2 |
| normal | 6 | 2 | 7:48 | 26 | 6s / 6s（2/2） | 50 / 73 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| normal | 7 | 2 | 8:58 | 22 | 12s / 12s（2/2） | 49 / 86 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（通关率，docs/38 §8.12） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 56 | 1% | 4:33 | 80% | 13.8 | 587 | - | **参考** |
| expert | 56 | 60% | 10:00 | 100% | 25.1 | 1601 | 50–70%（含超时） | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 8 | 50% | 9:23 / 4:41 | 0.0 / - | 8 / 15 / 23 / 24 | 11% | 87% | 62 | 1526 | 余震 25% 饱和复仇 9% 散射 7% 爆裂黎明 5% | 自身回复 29% 补给 18% 凯尔希 10% (764 / 0.0) | bullet |
| [expert] eyjafjalla | 8 | 25% | 7:12 / 4:18 | 0.0 / - | 8 / 16 / 23 / 20 | 6% | 54% | 56 | 1142 | 熔岩弹 16% 散射 10% 真实 10% 炮击 3% | 自身回复 40% 拾取 20% 补给 10% (777 / 0.0) | contact_tracer |
| [expert] skadi | 8 | 75% | 10:14 / 5:12 | 0.0 / - | 8 / 16 / 24 / 26 | 23% | 91% | 84 | 1728 | 大剑 27% 迅捷打击·γ型 6% 剑气 5% 跃浪击 4% | 自身回复 33% 补给 20% 拾取 12% (788 / 0.0) | bullet |
| [expert] mizuki | 8 | 87% | 11:49 / 11:26 | 0.0 / - | 8 / 16 / 22 / 28 | 3% | 96% | 99 | 1818 | 触手 15% 伞击 14% 终结技·mizuki·横扫 5% 剑气 4% | 水月 53% 自身回复 21% 补给 8% (838 / 0.0) | contact_tracer |
| [expert] saria | 8 | 75% | 10:38 / 6:55 | 0.0 / - | 7 / 15 / 22 / 26 | - | 91% | 46 | 1599 | 锯刃 10% 拳击 6% Mon3tr 6% 剑气 6% | 塞雷娅 46% 自身回复 23% 针剂回流 8% (1423 / 0.0) | bullet |
| [expert] kaltsit | 8 | 62% | 11:09 / 7:08 | 0.0 / - | 8 / 15 / 23 / 27 | 42% | 95% | 76 | 1783 | Mon3tr 23% Mon3tr · 真伤 8% 散射 7% 余震 6% | 凯尔希 32% 自身回复 22% 结构加固 16% (1046 / 0.0) | bullet |
| [expert] suzuran | 8 | 50% | 9:37 / 5:58 | 0.0 / - | 8 / 15 / 22 / 25 | 45% | 87% | 73 | 1609 | 狐火 12% 锯刃 10% Mon3tr 8% 替身闪现 5% | 自身回复 25% 铃兰 11% 补给 10% (1024 / 0.0) | contact_tracer |
| [normal] wisadel | 8 | 0% | 4:04 / 2:40 | 0.0 / - | 7 / 16 / 0 / 13 | 45% | 4% | 30 | 494 | 炮击 22% 余震 18% 刺剑 5% 终结技·wisadel·炮击 5% | 自身回复 60% 拾取 7% 浊心斯卡蒂 6% (319 / 0.0) | contact_tracer |
| [normal] eyjafjalla | 8 | 0% | 3:20 / 1:58 | 0.0 / - | 7 / 0 / 0 / 11 | 75% | 0% | 35 | 389 | 熔岩弹 29% 炮击 5% 锯刃 5% 终结技·eyjafjalla·熔岩 4% | 自身回复 52% 补给 10% 浊心斯卡蒂 9% (245 / 0.0) | contact_tracer |
| [normal] skadi | 8 | 12% | 6:23 / 3:36 | 0.0 / - | 7 / 15 / 22 / 18 | 60% | 20% | 46 | 923 | 大剑 24% 迅捷打击·γ型 7% 拳击 6% 终结技·skadi·浪头 6% | 自身回复 44% 塞雷娅 21% 拾取 10% (666 / 0.0) | contact_path |
| [normal] mizuki | 8 | 0% | 3:52 / 2:49 | 0.0 / - | 7 / 0 / 0 / 12 | 88% | 0% | 34 | 461 | 伞击 14% 终结技·mizuki·横扫 11% 余震 8% 触手 7% | 自身回复 69% 水月 9% 浊心斯卡蒂 6% (289 / 0.0) | contact_tracer |
| [normal] saria | 8 | 0% | 5:16 / 4:00 | 0.0 / - | 7 / 15 / 0 / 15 | 52% | 4% | 12 | 707 | 拳击 17% 大剑 12% 终结技·saria·拳风 10% 迅捷打击·γ型 5% | 塞雷娅 63% 自身回复 24% 针剂回流 3% (603 / 0.0) | boss_carmen |
| [normal] kaltsit | 8 | 0% | 4:03 / 2:46 | 0.0 / - | 7 / 16 / 0 / 13 | 79% | 4% | 25 | 502 | Mon3tr 28% 狐火 8% 终结技·kaltsit·熔毁 8% 锤击 5% | 凯尔希 38% 自身回复 38% 流明 7% (478 / 0.0) | contact_tracer |
| [normal] suzuran | 8 | 0% | 4:57 / 3:43 | 0.0 / - | 8 / 14 / 0 / 15 | 42% | 0% | 30 | 636 | 狐火 41% 狐火点点 9% 刺剑 4% 锤击 3% | 自身回复 43% 塞雷娅 17% 铃兰 11% (478 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 8 | 50% | 9:23 / 4:41 | 100% | 87% | 1:00 | 0:53 / 4:12 | 2.1 / 60s | 51.0 | 85 | 9 | 4 | 3 | 48% / 36494 | wound |
| [expert] eyjafjalla | 8 | 25% | 7:12 / 4:18 | 100% | 75% | 1:06 | 0:49 / 3:13 | 1.4 / 45s | 50.0 | 114 | 6 | 0 | 3 | 31% / 17251 | contact_reaper |
| [expert] skadi | 8 | 75% | 10:14 / 5:12 | 100% | 100% | 1:04 | 0:48 / 3:17 | 2.1 / 40s | 37.9 | 83 | 4 | 0 | 3 | 46% / 43176 | wound |
| [expert] mizuki | 8 | 87% | 11:49 / 11:26 | 100% | 100% | 1:03 | 0:51 / 3:08 | 2.4 / 67s | 63.6 | 70 | 0 | 0 | 4 | 33% / 30861 | corrode |
| [expert] saria | 8 | 75% | 10:38 / 6:55 | 100% | 100% | 1:15 | 0:59 / 3:54 | 2.4 / 89s | 99.7 | 130 | 5 | 22 | 4 | 8% / 6744 | corrode |
| [expert] kaltsit | 8 | 62% | 11:09 / 7:08 | 100% | 100% | 1:05 | 0:50 / 3:41 | 2.6 / 60s | 65.8 | 96 | 8 | 4 | 4 | 35% / 31358 | boss_knight_boss |
| [expert] suzuran | 8 | 50% | 9:37 / 5:58 | 100% | 100% | 1:02 | 0:49 / 3:11 | 2.0 / 53s | 80.8 | 118 | 6 | 0 | 4 | 17% / 12027 | corrode |
| [normal] wisadel | 8 | 0% | 4:04 / 2:40 | 62% | 12% | 1:07 | 2:38 / 4:30 | 0.1 / 49s | 33.3 | 101 | 15 | 3 | 0 | 45% / 6251 | contact_tracer |
| [normal] eyjafjalla | 8 | 0% | 3:20 / 1:58 | 50% | 0% | 1:05 | 2:19 / - | 0.0 / - | 35.0 | 102 | 14 | 6 | 1 | 35% / 3431 | contact_tracer |
| [normal] skadi | 8 | 12% | 6:23 / 3:36 | 100% | 62% | 1:18 | 2:10 / 4:13 | 0.6 / 55s | 38.6 | 126 | 10 | 3 | 0 | 39% / 17856 | contact_tracer |
| [normal] mizuki | 8 | 0% | 3:52 / 2:49 | 87% | 0% | 1:20 | 2:34 / - | 0.1 / 51s | 43.7 | 104 | 8 | 0 | 0 | 26% / 3026 | boss_carmen |
| [normal] saria | 8 | 0% | 5:16 / 4:00 | 100% | 37% | 1:17 | 2:12 / 3:05 | 0.2 / 53s | 45.9 | 128 | 6 | 10 | 0 | 21% / 4704 | boss_carmen |
| [normal] kaltsit | 8 | 0% | 4:03 / 2:46 | 62% | 12% | 1:10 | 2:15 / 4:05 | 0.2 / 45s | 47.5 | 142 | 14 | 2 | 0 | 30% / 4429 | boss_carmen |
| [normal] suzuran | 8 | 0% | 4:57 / 3:43 | 100% | 37% | 1:03 | 2:16 / - | 0.5 / 75s | 25.8 | 105 | 30 | 6 | 0 | 51% / 10266 | bullet |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 8 | 9.5 | 10.5% | class 16/4 control 2/2 economy 20/9 general 54/23 heal 4/2 melee 7/6 multi 26/9 shield 9/6 summon 7/2 survival 30/12 weak 4/1 | 0 |
| expert | kaltsit | 8 | 13.5 | 4.4% | class 23/8 control 6/4 economy 27/8 general 81/29 heal 32/11 melee 11/7 multi 16/5 shield 13/8 summon 13/5 survival 43/18 weak 11/5 | 0 |
| expert | mizuki | 8 | 15.2 | 6.5% | class 46/13 control 9/3 economy 33/8 general 103/43 heal 6/6 melee 22/9 multi 15/7 shield 21/6 summon 40/18 survival 39/6 weak 6/3 | 0 |
| expert | saria | 8 | 10.6 | 10.3% | class 25/4 control 9/4 economy 18/5 general 67/23 heal 33/15 melee 10/2 multi 9/7 shield 16/8 summon 12/5 survival 21/7 weak 6/5 | 0 |
| expert | skadi | 8 | 13.9 | 4.8% | class 23/4 control 6/5 economy 31/9 general 96/44 heal 9/6 melee 58/18 multi 12/4 shield 11/5 summon 12/4 survival 37/9 weak 5/3 | 0 |
| expert | suzuran | 8 | 14.2 | 8.8% | class 29/8 control 41/15 economy 33/14 general 86/36 heal 17/7 melee 11/3 multi 10/4 shield 8/4 summon 10/5 survival 47/14 weak 6/4 | 0 |
| expert | wisadel | 8 | 12.2 | 5.8% | class 30/8 control 7/5 economy 32/9 general 62/33 heal 6/2 melee 13/6 multi 41/15 shield 7/6 summon 11/3 survival 35/7 weak 9/4 | 0 |
| normal | eyjafjalla | 8 | 1.4 | 0.4% | class 3/1 economy 5/2 general 10/3 heal 4/1 melee 1/0 multi 13/3 shield 1/0 summon 2/1 survival 1/0 weak 2/0 | 0 |
| normal | kaltsit | 8 | 2.0 | 0.0% | class 11/3 control 1/0 economy 11/4 general 9/4 heal 14/3 melee 4/2 shield 2/0 summon 3/0 survival 3/0 | 0 |
| normal | mizuki | 8 | 1.6 | 0.6% | class 7/0 control 1/1 economy 13/2 general 9/5 heal 2/0 melee 4/0 multi 3/0 shield 2/0 summon 13/5 survival 4/0 weak 1/0 | 0 |
| normal | saria | 8 | 2.4 | 2.0% | class 7/4 control 1/0 economy 5/2 general 23/3 heal 17/6 melee 3/1 multi 1/1 shield 2/1 summon 3/0 survival 6/1 weak 3/0 | 0 |
| normal | skadi | 8 | 4.8 | 4.6% | class 11/1 control 3/1 economy 13/4 general 30/11 heal 3/1 melee 24/6 multi 4/1 shield 7/5 summon 4/0 survival 18/7 weak 2/1 | 0 |
| normal | suzuran | 8 | 3.4 | 1.8% | class 4/0 control 15/3 economy 12/7 general 12/10 heal 1/1 melee 7/3 shield 3/1 summon 2/0 survival 6/1 weak 1/1 | 0 |
| normal | wisadel | 8 | 1.8 | 3.0% | class 7/3 control 3/0 economy 9/4 general 13/2 heal 2/0 melee 5/1 multi 8/2 shield 1/1 summon 1/0 survival 6/1 weak 2/0 | 0 |
| 合计 | | | | | class 242/61 control 104/43 economy 262/87 general 655/269 heal 150/61 melee 180/64 multi 158/58 shield 103/51 summon 133/48 survival 296/83 weak 58/27 | |

拿取最多（出现 / 拿取）：《旧高卢地名源流考》 44/23，锈蚀刀片 51/17，洁白的舞鞋 35/15，“多功能”发夹 39/14，演出用香水 25/14，显圣吊坠 47/13，血魔的银杯 35/13，穿甲弹 34/12，药枚 15/12，凯旋号角 34/12，银餐叉 31/11，演员的首饰盒 22/11
