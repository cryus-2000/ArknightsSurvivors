# balance gm_A_expert_m0_s5a 1029_1523

args: `--preset starts --bot expert --seed0 5 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --tag gm_A_expert_m0_s5a --out build/gm/A_s5`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 3 | 141s / 161s / 161s / 101–161s | 161s / 161s | 2.2 / 2.7 | 44% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 7 | 2 | 152s | 0.10 | 6 | - | - |
| expert | 塑路者 | 6 | 6 | 82s | 0.38 | 10 | - | - |
| expert | 接潮主教 | 4 | 2 | 104s | 0.04 | 16 | 1.5 | 6% |
| expert | 接潮蔑死体 | 3 | 2 | 104s | 0.05 | 15 | - | - |
| expert | 圣徒伊比利亚 | 2 | 1 | 99s | 0.07 | 22 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 132s | 0.09 | 14 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 20 | 0.0 / 0.0 / 0.0 / 0 | 22 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 14% | 237 / 207 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:05 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |
| expert | 0 | dark | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:12 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:07 |
| expert | 0 | boss_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:56 |
| expert | 0 | mire | 未缩圈 | 否 | 否 | 1 | 1:34 |
| expert | 0 | zone | 第 2 轮 · 收缩 | 是 | 否 | 1 | 9:47 |
| expert | 0 | contact_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:34 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 91 / 200 | 95 / 176 | 3 / 9 | 281 / 401 | 23 / 48 |
| expert | 0 | 7 | 8:00–10:00 | 94 / 200 | 77 / 162 | 1 / 5 | 349 / 397 | 23 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 17s / 13s（14/14） | 35 / 124 | 1 | bone/slider/stone ×14 |
| expert | 2 | 13 | 2:45 | 20 | 10s / 10s（12/13） | 23 / 70 | 1 | bone/slider ×13 |
| expert | 3 | 7 | 5:35 | 24 | 36s / 11s（6/7） | 12 / 30 | 0 | bone/floater/runner/slider ×2；bone/offspring/slider/stone ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 4 | 7 | 5:53 | 35 | 44s / 20s（5/7） | 41 / 140 | 1 | bone/reaper/runner/slider/tracer ×2；bone/floater/reaper/runner/slider/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 5 | 5 | 6:54 | 38 | 86s / 88s（4/5） | 37 / 78 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 6 | 3 | 8:37 | 23 | 13s / 13s（2/3） | 35 / 71 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 1 | 9:17 | 22 | 12s / 12s（1/1） | 3 / 3 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 8:23 / 4:05 | 0.0 / - | 8 / 15 / 22 / 20 | 35% | 66% | 72 | 1146 | 余震 33% 饱和复仇 10% 锚击 9% 爆裂黎明 7% | 自身回复 30% 塞雷娅 26% 凯尔希 15% (820 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 0% | 3:59 / 2:47 | 0.0 / - | 8 / 14 / 0 / 12 | 25% | 16% | 3 | 436 | 熔岩弹 37% 火星 8% 刺剑 8% 盾斧斩 6% | 自身回复 27% 塞雷娅 24% 补给 22% (541 / 0.0) | boss_carmen |
| [expert] skadi | 2 | 0% | 9:03 / 5:07 | 0.0 / - | 8 / 14 / 19 / 20 | 18% | 66% | 76 | 952 | 大剑 27% 余震 13% 狐火 12% 跃浪 6% | 自身回复 31% 拾取 19% 流明 19% (1434 / 0.0) | boss_carmen |
| [expert] mizuki | 2 | 50% | 12:20 / 11:41 | 0.0 / - | 8 / 15 / 20 / 26 | 76% | 100% | 100 | 1556 | 真实 49% 钩索 15% 伞击 9% 触手 6% | 水月 56% 自身回复 18% 流明 10% (1896 / 0.5) | contact_tracer |
| [expert] saria | 2 | 0% | 9:58 / 6:56 | 0.0 / - | 6 / 15 / 19 / 21 | 39% | 83% | 12 | 1068 | 刺剑 20% 锯刃 16% 炮击 8% 拳击 8% | 塞雷娅 54% 自身回复 20% 强心针 9% (1941 / 0.0) | bullet |
| [expert] kaltsit | 2 | 50% | 7:07 / 1:34 | 0.0 / - | 8 / 14 / 20 / 15 | - | 60% | 57 | 813 | Mon3tr 47% 狐火 13% Mon3tr · 真伤 7% 秘杖·速充模式 6% | 凯尔希 42% 自身回复 27% 拾取 10% (648 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 0% | 7:40 / 5:34 | 0.0 / - | 8 / 15 / 18 / 19 | - | 83% | 14 | 1006 | 狐火 36% 弹匣倾泻 11% 盾斧斩 9% 拳击 5% | 自身回复 33% 塞雷娅 22% 铃兰 19% (850 / 0.0) | atk_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 8:23 / 4:05 | 100% | 50% | 1:07 | 0:48 / 2:14 | 1.0 / 81s | 81.2 | 103 | 4 | 12 | 4 | 66% / 25721 | atk_tracer |
| [expert] eyjafjalla | 2 | 0% | 3:59 / 2:47 | 50% | 50% | 1:05 | 0:51 / 2:44 | 0.0 / - | 32.1 | 160 | 4 | 2 | 2 | 65% / 7417 | dark |
| [expert] skadi | 2 | 0% | 9:03 / 5:07 | 100% | 100% | 1:06 | 0:50 / 2:42 | 1.0 / 95s | 100.1 | 161 | 21 | 0 | 2 | 50% / 16193 | corrode |
| [expert] mizuki | 2 | 50% | 12:20 / 11:41 | 100% | 100% | 1:05 | 0:51 / 3:30 | 1.5 / 54s | 195.1 | 144 | 1 | 22 | 4 | 19% / 12860 | boss_paranoia |
| [expert] saria | 2 | 0% | 9:58 / 6:56 | 100% | 100% | 1:39 | 0:55 / 4:54 | 0.5 / 192s | 146.3 | 174 | 16 | 94 | 3 | 13% / 5013 | wound |
| [expert] kaltsit | 2 | 50% | 7:07 / 1:34 | 50% | 50% | 1:09 | 0:50 / 2:37 | 1.5 / 137s | 77.5 | 112 | 3 | 0 | 3 | 58% / 11844 | mire |
| [expert] suzuran | 2 | 0% | 7:40 / 5:34 | 100% | 100% | 1:05 | 0:49 / 3:19 | 1.5 / 127s | 92.8 | 103 | 6 | 42 | 2 | 37% / 11968 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 1.5 | 0.0% | class 1/1 economy 1/1 general 4/0 heal 1/0 multi 3/1 shield 1/0 survival 1/0 | 0 |
| expert | kaltsit | 2 | 5.5 | 0.0% | class 3/0 economy 2/1 general 15/3 heal 8/2 melee 1/0 shield 2/1 survival 6/2 weak 2/2 | 0 |
| expert | mizuki | 2 | 10.0 | 49.7% | class 10/4 control 1/1 economy 6/0 general 14/5 heal 1/0 melee 1/0 multi 1/0 shield 5/2 summon 14/4 survival 6/4 | 0 |
| expert | saria | 2 | 5.5 | 0.0% | control 1/0 economy 5/2 general 12/4 heal 6/3 melee 2/0 multi 1/0 survival 5/1 weak 0/1 | 0 |
| expert | skadi | 2 | 3.5 | 0.0% | class 1/0 economy 3/0 general 9/2 melee 7/3 multi 1/0 shield 1/1 survival 4/0 weak 2/1 | 0 |
| expert | suzuran | 2 | 4.5 | 0.0% | control 3/2 economy 2/0 general 4/3 melee 1/0 multi 2/1 shield 2/1 summon 1/0 survival 7/2 weak 3/0 | 0 |
| expert | wisadel | 2 | 8.5 | 0.0% | class 3/0 control 2/1 economy 7/0 general 10/6 heal 2/0 melee 2/1 multi 6/3 shield 2/2 summon 1/1 survival 11/3 weak 1/0 | 0 |
| 合计 | | | | | class 18/5 control 7/4 economy 26/4 general 68/23 heal 18/5 melee 14/4 multi 14/5 shield 13/7 summon 16/5 survival 40/12 weak 8/4 | |

拿取最多（出现 / 拿取）：涡旋座 4/3，特级馥郁咖啡豆 5/3，药枚 4/3，残破合影 3/3，凯旋号角 6/3，洁白的舞鞋 4/2，遥乡之引 3/2，“基岩” 3/2，古旧的蒸汽甲胄 2/2，支援急救包 2/2，穿甲弹 2/2，三钥协定 2/1
