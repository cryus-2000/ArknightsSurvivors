# balance dps_saria_base 0926_1748

args: `--game game --jobs 4 --out build/cloud/boss-dps-r1-base --op saria --bots expert,normal --seeds 24 --tag dps_saria_base`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 8 | 8 | 8 | 75s / 59s / 179s / 47–179s | 37s / 158s | 9.2 / 2.0 | - |
| expert | 最后的骑士 | knight 8 | 8 | 7 | 68s / 53s / 107s / 47–107s | 53s / 107s | 6.5 / 1.9 | 36% |
| expert | 伊莎玛拉 | resolve 5 | 5 | 4 | 77s / 48s / 174s / 38–174s | 48s / 174s | 7.3 / 1.6 | 92% |
| expert | 偏执泡影 | standard 2 | 2 | 2 | 62s / 62s / 65s / 60–65s | 62s / 65s | 3.2 / 2.0 | - |
| normal | 最后的骑士 | knight 8 | 8 | 7 | 69s / 58s / 129s / 48–129s | 58s / 129s | 8.8 / 2.0 | 14% |
| normal | 偏执泡影 | standard 4 | 4 | 1 | 49s / 49s / 49s / 49–49s | 49s / 49s | 0.9 / 0.5 | 95% |
| normal | 伊莎玛拉 | resolve 1 | 1 | 1 | 49s / 49s / 49s / 49–49s | 49s / 49s | 17.2 / 2.0 | - |
| normal | 伊祖米克 | deep 1 | 1 | 1 | 110s / 110s / 110s / 110–110s | 93s / 93s | 0.0 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 24 | 0% | 18 / 18 | 100% |
| normal | 0 | 24 | 0% | 20 / 20 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| expert | 0 | shock | 第 2 轮 · 收缩 | 否 | 否 | 1 | 9:14 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 7:42 |
| normal | 0 | boss_tracer | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| normal | 0 | corrode | 第 2 轮 · 收缩 | 否 | 是 | 1 | 7:06 |
| normal | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:45 |
| normal | 0 | contact_slider | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:36 |
| normal | 0 | dark | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:23 |
| normal | 0 | mire | 第 3 轮 · 收缩 | 否 | 是 | 1 | 8:08 |
| normal | 0 | shock | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | shock | 第 3 轮 · 预告 | 否 | 是 | 1 | 10:56 |
| normal | 0 | shock | 第 4 轮 · 收缩 | 否 | 否 | 1 | 8:53 |
| normal | 0 | bullet | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:58 |
| normal | 0 | mire | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:45 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 24 | 全程 | 298 / 478 | 52 / 92 | 2 / 7 | 406 / 505 | 46 / 48 |
| expert | 0 | 24 | 8:00–10:00 | 243 / 358 | 43 / 74 | 1 / 6 | 379 / 472 | 41 / 48 |
| normal | 0 | 24 | 全程 | 306 / 472 | 48 / 76 | 2 / 8 | 386 / 502 | 42 / 48 |
| normal | 0 | 18 | 8:00–10:00 | 278 / 472 | 42 / 63 | 2 / 8 | 361 / 502 | 39 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 24 | 1:15 | 26 | 34s / 34s（24/24） | 1 / 4 | 0 | bone/slider ×12；bone/slider/stone ×12 |
| expert | 2 | 24 | 2:45 | 33 | 33s / 22s（24/24） | 4 / 12 | 0 | bone/slider/stone ×12；bone/slider ×12 |
| expert | 3 | 24 | 4:52 | 44 | 30s / 22s（24/24） | 16 / 71 | 0 | bone/floater/ripper/runner/slider/tracer ×8；bone/burrower/ripper/slider ×8；bone/offspring/ripper/slider/spitter ×6 |
| expert | 4 | 24 | 6:03 | 50 | 20s / 16s（24/24） | 16 / 34 | 0 | bone/burrower/ripper/slider ×9；bone/offspring/ripper/slider/spitter ×9；bone/floater/ripper/runner/slider/tracer ×6 |
| expert | 5 | 24 | 7:26 | 57 | 18s / 14s（24/24） | 14 / 76 | 0 | bone/floater/founder/nest/ripper/runner/slider ×9；bone/burrower/offspring/ripper/slider/stone ×8；burrower/ripper/slider/spitter ×7 |
| expert | 6 | 24 | 8:42 | 63 | 15s / 10s（24/24） | 30 / 86 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×9；burrower/offspring/ripper/slider/spitter/stone ×5；burrower/ripper/slider/spitter ×4 |
| expert | 7 | 4 | 9:15 | 66 | 7s / 7s（4/4） | 30 / 74 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×2；burrower/hulk/ripper/slider/spitter ×1；burrower/offspring/ripper/slider/spitter/stone ×1 |
| normal | 1 | 24 | 1:15 | 26 | 9s / 9s（24/24） | 7 / 24 | 0 | bone/slider/stone ×17；bone/slider ×7 |
| normal | 2 | 24 | 2:45 | 33 | 19s / 12s（24/24） | 6 / 26 | 0 | bone/slider ×17；bone/slider/stone ×7 |
| normal | 3 | 24 | 4:40 | 43 | 43s / 26s（24/24） | 18 / 78 | 0 | bone/floater/ripper/runner/slider/tracer ×6；bone/floater/ripper/runner/slider ×5；bone/offspring/ripper/slider/stone ×5 |
| normal | 4 | 24 | 6:00 | 50 | 37s / 30s（24/24） | 18 / 81 | 0 | bone/offspring/ripper/slider/spitter ×9；bone/floater/ripper/runner/slider/tracer ×8；bone/burrower/ripper/slider ×7 |
| normal | 5 | 20 | 7:38 | 58 | 29s / 16s（17/20） | 45 / 141 | 3 | bone/burrower/offspring/ripper/slider/stone ×8；bone/floater/founder/nest/ripper/runner/slider ×7；burrower/ripper/slider/spitter ×5 |
| normal | 6 | 15 | 8:37 | 63 | 27s / 11s（15/15） | 25 / 84 | 0 | burrower/ripper/slider/spitter ×4；burrower/offspring/ripper/slider/spitter/stone ×4；bone/floater/founder/nest/ripper/runner/slider ×3 |
| normal | 7 | 3 | 9:18 | 66 | 14s / 11s（3/3） | 49 / 76 | 0 | burrower/offspring/ripper/slider/spitter/stone ×2；burrower/hulk/ripper/slider/spitter ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 24 | 41% | 9:58 | 100% | 29.7 | 5739 | 30–55% / 7:00–13:00 | **达标** |
| expert | 24 | 87% | 11:16 | 100% | 34.0 | 6988 | 70–95% / 9:00–13:00 | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 24 | 87% | 11:16 / 9:14 | 0.0 / - | 6 / 15 / 25 / 34 | 64% | 100% | 70 | 6988 | 殉爆 7% 余震 6% 锚击 5% 刺剑 5% | 塞雷娅 75% 流明 12% 凯尔希 3% (789 / 0.0) | bullet |
| [normal] saria | 24 | 41% | 9:58 / 6:36 | 0.0 / - | 6 / 15 / 25 / 30 | 56% | 44% | 53 | 5739 | 锯刃 11% 拳击 8% Mon3tr 7% 大剑 6% | 塞雷娅 79% 凯尔希 8% 拾取 4% (1145 / 0.6) | shock |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 24 | 87% | 11:16 / 9:14 | 100% | 100% | 1:57 | 0:49 / 3:27 | 2.0 / 96s | 17.6 | 80 | 1 | 4 | 12 | 7% / 7709 | bullet |
| [normal] saria | 24 | 41% | 9:58 / 6:36 | 100% | 100% | 1:19 | 3:19 / 7:20 | 1.8 / 59s | 34.1 | 130 | 2 | 10 | 0 | 13% / 8534 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | saria | 24 | 29.7 | 3.8% | A 281/86 B 74/40 C 161/70 D 188/50 E 172/39 F 49/27 G 146/54 H 369/112 通用 463/245 | 0 |
| normal | saria | 24 | 20.5 | 1.7% | A 157/56 B 58/18 C 115/32 D 147/51 E 110/33 F 29/13 G 129/36 H 240/65 通用 302/189 | 0 |
| 合计 | | | | | A 438/142 B 132/58 C 276/102 D 335/101 E 282/72 F 78/40 G 275/90 H 609/177 通用 765/434 | |

拿取最多（出现 / 拿取）：“观望” 0/44，“决心” 0/43，“犹疑” 0/27，海潮的气息 0/27，镶金骨骰 80/25，皇帝的恩宠 66/25，“黑夜呢喃” 75/23，老近卫军之锋 76/21，阿卡胡拉饭碗 42/20，漆黑的舞鞋 47/19，深蓝之心 0/19，涡旋座 59/19
