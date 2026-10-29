# balance gmeq_A_expert_m0_base 1029_1529

args: `--preset starts --bot expert --seed0 1 --seeds 2 --jobs 4 --extra --tier=0 --tide=0 --trace=1 --tag gmeq_A_expert_m0_base --out build/gm_eq`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 4 | 4 | 2 | 135s / 135s / 177s / 94–177s | 136s / 177s | 5.0 / 3.0 | 43% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 80s / 80s / 80s / 80–80s | 60s / 60s | 0.3 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 6 | 5 | 77s | 0.34 | 6 | - | - |
| expert | 圣徒卡门 | 6 | 4 | 54s | 0.35 | 6 | - | - |
| expert | 圣徒伊比利亚 | 3 | 2 | 85s | 0.13 | 12 | - | - |
| expert | 接潮主教 | 3 | 1 | 32s | 0.03 | 16 | 1.0 | 2% |
| expert | 接潮斥亡体 | 2 | 0 | - | 0.05 | 31 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 32s | 0.18 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 0.1 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 12 | 0.0 / 0.0 / 0.0 / 0 | 15 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 14 | 7% | 235 / 214 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:41 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:34 |
| expert | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:20 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 3:21 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:15 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:47 |
| expert | 0 | wound | 第 2 轮 · 预告 | 否 | 是 | 1 | 7:11 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:50 |
| expert | 0 | shock_paranoia | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:54 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 14 | 全程 | 96 / 190 | 97 / 176 | 2 / 9 | 253 / 412 | 25 / 48 |
| expert | 0 | 5 | 8:00–10:00 | 71 / 82 | 53 / 104 | 1 / 5 | 351 / 384 | 22 / 43 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 14 | 1:15 | 15 | 11s / 10s（14/14） | 21 / 55 | 0 | bone/slider ×11；bone/slider/stone ×3 |
| expert | 2 | 14 | 2:45 | 20 | 11s / 11s（13/14） | 32 / 74 | 1 | bone/slider/stone ×11；bone/slider ×3 |
| expert | 3 | 9 | 5:08 | 24 | 18s / 13s（7/9） | 14 / 96 | 2 | bone/floater/reaper/runner/slider/tracer ×3；bone/floater/runner/slider ×2；bone/offspring/slider/stone ×1 |
| expert | 4 | 8 | 5:25 | 35 | 18s / 17s（5/8） | 38 / 127 | 2 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 5 | 6 | 6:21 | 39 | 25s / 28s（5/6） | 59 / 134 | 1 | bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 3 | 8:19 | 25 | 11s / 12s（3/3） | 32 / 42 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 2 | 9:12 | 22 | 12s / 12s（2/2） | 37 / 51 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 8:30 / 5:41 | 0.0 / - | 8 / 15 / 22 / 22 | - | 83% | 56 | 1364 | 余震 36% 饱和复仇 14% 殉爆 7% 爆裂黎明 6% | 自身回复 32% 凯尔希 17% 拾取 17% (822 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 2 | 0% | 4:57 / 4:34 | 0.0 / - | 8 / 15 / 0 / 16 | - | 33% | 65 | 635 | 熔岩弹 26% 狐火 13% 大剑 8% 炮击 8% | 自身回复 30% 拾取 27% 流明 16% (616 / 0.0) | contact_tracer |
| [expert] skadi | 2 | 50% | 8:09 / 3:21 | 0.0 / - | 8 / 14 / 21 / 18 | - | 50% | 69 | 1040 | 真实 49% 言 14% 大剑 12% 盾斧斩 5% | 自身回复 41% 拾取 23% 流明 22% (1209 / 0.0) | contact_tracer |
| [expert] mizuki | 2 | 0% | 9:07 / 5:15 | 0.0 / - | 7 / 14 / 21 / 20 | 42% | 50% | 50 | 1119 | 触手 14% 伞击 12% 锚击 12% 速射 8% | 水月 59% 自身回复 20% 塞雷娅 15% (1895 / 0.0) | contact_tracer |
| [expert] saria | 2 | 0% | 6:59 / 6:47 | 0.0 / - | 8 / 14 / 0 / 17 | 80% | 66% | 0 | 834 | 拳击 12% 炮击 10% 言 10% 延异视阈 10% | 塞雷娅 52% 自身回复 20% 拾取 9% (940 / 0.0) | contact_tracer |
| [expert] kaltsit | 2 | 0% | 8:25 / 3:50 | 0.0 / - | 8 / 14 / 18 / 18 | 65% | 50% | 60 | 827 | Mon3tr 38% 炮击 11% 熔岩弹 8% 刺剑 7% | 凯尔希 38% 自身回复 26% 结构加固 19% (1368 / 0.0) | contact_tracer |
| [expert] suzuran | 2 | 50% | 7:14 / 2:54 | 0.0 / - | 8 / 16 / 22 / 19 | - | 50% | 70 | 1158 | 狐火 30% 大剑 17% 炮击 11% 余震 6% | 自身回复 28% 塞雷娅 24% 铃兰 16% (810 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 2 | 50% | 8:30 / 5:41 | 100% | 100% | 1:10 | 0:47 / 4:48 | 1.5 / 71s | 83.6 | 104 | 4 | 2 | 2 | 71% / 40916 | contact_reaper |
| [expert] eyjafjalla | 2 | 0% | 4:57 / 4:34 | 100% | 50% | 1:13 | 0:49 / 2:16 | 1.0 / 54s | 16.8 | 148 | 18 | 0 | 2 | 54% / 10902 | contact_tracer |
| [expert] skadi | 2 | 50% | 8:09 / 3:21 | 50% | 50% | 1:09 | 0:50 / 2:25 | 1.0 / 98s | 94.3 | 144 | 9 | 0 | 2 | 24% / 16170 | contact_tracer |
| [expert] mizuki | 2 | 0% | 9:07 / 5:15 | 100% | 100% | 1:17 | 0:51 / 2:30 | 0.5 / 72s | 129.6 | 179 | 4 | 148 | 5 | 31% / 9567 | corrode |
| [expert] saria | 2 | 0% | 6:59 / 6:47 | 100% | 100% | 1:11 | 0:52 / 4:55 | 1.0 / 174s | 65.2 | 148 | 8 | 8 | 4 | 19% / 5314 | atk_tracer |
| [expert] kaltsit | 2 | 0% | 8:25 / 3:50 | 100% | 50% | 1:05 | 0:51 / 3:49 | 0.0 / - | 146.7 | 142 | 15 | 68 | 2 | 46% / 11102 | shock_paranoia |
| [expert] suzuran | 2 | 50% | 7:14 / 2:54 | 50% | 50% | 1:06 | 0:48 / 4:02 | 1.5 / 31s | 106.0 | 113 | 8 | 6 | 4 | 30% / 7518 | atk_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 2 | 4.0 | 0.5% | economy 1/0 general 7/5 heal 1/0 multi 3/1 shield 1/1 summon 2/1 survival 3/0 weak 1/0 | 0 |
| expert | kaltsit | 2 | 4.0 | 0.0% | economy 3/1 general 3/0 heal 6/3 shield 2/0 summon 3/2 survival 5/2 | 0 |
| expert | mizuki | 2 | 6.0 | 0.3% | class 5/2 economy 3/0 general 10/3 heal 1/0 melee 0/1 shield 2/1 summon 9/4 survival 6/0 weak 0/1 | 0 |
| expert | saria | 2 | 3.0 | 0.0% | class 2/0 economy 2/0 general 4/3 heal 4/2 multi 1/0 shield 1/1 weak 1/0 | 0 |
| expert | skadi | 2 | 7.0 | 49.8% | class 7/1 control 1/1 economy 3/1 general 7/4 heal 4/2 melee 10/3 multi 3/0 summon 1/1 survival 3/1 weak 3/0 | 0 |
| expert | suzuran | 2 | 9.5 | 4.7% | class 5/2 control 6/2 economy 3/2 general 15/7 heal 1/0 melee 3/0 multi 2/1 shield 3/2 summon 1/1 survival 10/2 weak 2/0 | 0 |
| expert | wisadel | 2 | 8.5 | 0.0% | class 2/0 control 1/0 economy 6/0 general 14/8 melee 1/0 multi 6/3 shield 1/1 summon 2/1 survival 9/4 | 0 |
| 合计 | | | | | class 21/5 control 8/3 economy 21/4 general 60/30 heal 17/7 melee 14/4 multi 15/5 shield 10/6 summon 18/10 survival 36/9 weak 7/1 | |

拿取最多（出现 / 拿取）：散轶诗简 5/3，海程 4/3，银餐叉 5/2，橙味风暴 4/2，《旧高卢地名源流考》 3/2，几丁质刺刃 2/2，游戏室管理员权限卡 4/2，主教的研究 0/2，活玫瑰 7/2，苍白花冠 3/2，“多功能”发夹 4/2，猎人的口粮 3/2
