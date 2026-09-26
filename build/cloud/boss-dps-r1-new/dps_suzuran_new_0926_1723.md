# balance dps_suzuran_new 0926_1723

args: `--game game --jobs 4 --out build/cloud/boss-dps-r1-new --op suzuran --bots expert,normal --seeds 24 --tag dps_suzuran_new`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 7 | 7 | 7 | 73s / 66s / 129s / 48–129s | 33s / 109s | 7.5 / 2.0 | - |
| expert | 偏执泡影 | standard 6 | 6 | 3 | 49s / 39s / 70s / 39–70s | 39s / 70s | 6.9 / 1.5 | 62% |
| expert | 最后的骑士 | knight 6 | 6 | 6 | 55s / 56s / 63s / 42–63s | 56s / 63s | 7.5 / 2.0 | - |
| expert | 伊莎玛拉 | resolve 2 | 2 | 2 | 54s / 54s / 69s / 39–69s | 54s / 69s | 15.6 / 2.0 | - |
| normal | 伊祖米克 | deep 2 | 2 | 2 | 62s / 62s / 77s / 48–77s | 30s / 30s | 19.4 / 2.0 | - |
| normal | 最后的骑士 | knight 1 | 1 | 1 | 46s / 46s / 46s / 46–46s | 46s / 46s | 21.3 / 2.0 | - |
| normal | 伊莎玛拉 | resolve 1 | 1 | 1 | 42s / 42s / 42s / 42–42s | 42s / 42s | 7.5 / 2.0 | - |
| normal | 偏执泡影 | standard 1 | 1 | 0 | - | - | 0.0 / 0.0 | 91% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 24 | 0% | 12 / 11 | 100% |
| normal | 0 | 24 | 0% | 22 / 20 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| expert | 0 | shock | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:57 |
| expert | 0 | mire | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:58 |
| expert | 0 | corrode | 第 4 轮 · 收缩 | 否 | 否 | 1 | 8:35 |
| expert | 0 | bullet | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 2 | 7:27 |
| normal | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:43 |
| normal | 0 | mire | 第 3 轮 · 稳定 | 否 | 是 | 2 | 8:09 |
| normal | 0 | contact_slider | 第 3 轮 · 预告 | 否 | 是 | 1 | 8:15 |
| normal | 0 | corrode | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:37 |
| normal | 0 | boss_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:36 |
| normal | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:50 |
| normal | 0 | boss_tracer | 第 5 轮 · 预告 | 否 | 否 | 1 | 9:54 |
| normal | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 是 | 1 | 8:05 |
| normal | 0 | boss_tracer | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:19 |
| normal | 0 | shock | 第 5 轮 · 收缩 | 否 | 否 | 1 | 9:29 |
| normal | 0 | bullet | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:38 |
| normal | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:18 |
| normal | 0 | contact_iberia | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:11 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:54 |
| normal | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | contact_slider | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:09 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 24 | 全程 | 266 / 400 | 49 / 106 | 8 / 12 | 399 / 477 | 46 / 48 |
| expert | 0 | 23 | 8:00–10:00 | 252 / 400 | 44 / 86 | 6 / 11 | 379 / 477 | 45 / 48 |
| normal | 0 | 24 | 全程 | 270 / 462 | 39 / 76 | 7 / 8 | 338 / 437 | 36 / 48 |
| normal | 0 | 10 | 8:00–10:00 | 288 / 462 | 48 / 76 | 6 / 7 | 321 / 420 | 30 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 24 | 1:15 | 26 | 11s / 11s（24/24） | 2 / 3 | 0 | bone/slider ×17；bone/slider/stone ×7 |
| expert | 2 | 24 | 2:45 | 33 | 14s / 13s（24/24） | 2 / 6 | 0 | bone/slider/stone ×17；bone/slider ×7 |
| expert | 3 | 24 | 4:40 | 43 | 23s / 18s（24/24） | 6 / 25 | 0 | bone/offspring/ripper/slider/spitter ×6；bone/offspring/ripper/slider/stone ×6；bone/burrower/ripper/slider ×4 |
| expert | 4 | 24 | 5:54 | 49 | 19s / 16s（24/24） | 10 / 32 | 0 | bone/burrower/ripper/slider ×9；bone/offspring/ripper/slider/spitter ×8；bone/floater/ripper/runner/slider/tracer ×7 |
| expert | 5 | 24 | 7:40 | 58 | 14s / 12s（23/24） | 18 / 150 | 1 | burrower/ripper/slider/spitter ×8；bone/floater/founder/nest/ripper/runner/slider ×8；bone/burrower/offspring/ripper/slider/stone ×8 |
| expert | 6 | 22 | 8:44 | 63 | 13s / 10s（22/22） | 17 / 100 | 1 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×7；burrower/hulk/ripper/slider/spitter ×5；bone/floater/founder/nest/ripper/runner/slider ×3 |
| expert | 7 | 2 | 9:15 | 66 | 10s / 10s（2/2） | 5 / 10 | 0 | burrower/offspring/ripper/slider/spitter/stone ×2 |
| normal | 1 | 24 | 1:15 | 26 | 11s / 11s（24/24） | 6 / 44 | 0 | bone/slider/stone ×13；bone/slider ×11 |
| normal | 2 | 24 | 2:45 | 33 | 13s / 11s（24/24） | 6 / 53 | 0 | bone/slider ×13；bone/slider/stone ×11 |
| normal | 3 | 22 | 4:32 | 42 | 21s / 18s（22/22） | 24 / 115 | 2 | bone/ripper/slider/stone ×8；bone/floater/ripper/runner/slider ×5；bone/burrower/ripper/slider ×4 |
| normal | 4 | 18 | 5:50 | 49 | 32s / 30s（18/18） | 22 / 62 | 0 | bone/floater/ripper/runner/slider/tracer ×7；bone/offspring/ripper/slider/spitter ×6；bone/burrower/ripper/slider ×5 |
| normal | 5 | 11 | 7:28 | 57 | 26s / 12s（10/11） | 37 / 119 | 1 | burrower/ripper/slider/spitter ×5；bone/floater/founder/nest/ripper/runner/slider ×4；bone/burrower/offspring/ripper/slider/stone ×2 |
| normal | 6 | 8 | 8:45 | 63 | 18s / 10s（7/8） | 59 / 139 | 1 | burrower/offspring/ripper/slider/spitter/stone ×2；bone/floater/founder/nest/ripper/runner/slider ×2；burrower/hulk/ripper/slider/spitter ×2 |
| normal | 7 | 2 | 9:19 | 66 | 12s / 12s（2/2） | 102 / 117 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×1；burrower/offspring/ripper/slider/spitter/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 24 | 16% | 7:53 | 100% | 23.8 | 3992 | 30–55% / 7:00–13:00 | **偏难** |
| expert | 24 | 75% | 10:57 | 100% | 33.3 | 6730 | 70–95% / 9:00–13:00 | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 24 | 75% | 10:57 / 7:57 | 0.0 / - | 7 / 15 / 25 / 33 | 60% | 100% | 70 | 6730 | 狐火 10% Mon3tr 7% 触手 7% Mon3tr · 真伤 6% | 凯尔希 29% 铃兰 27% 流明 12% (439 / 0.3) | bullet |
| [normal] suzuran | 24 | 16% | 7:53 / 3:54 | 0.0 / - | 7 / 15 / 24 / 24 | 56% | 29% | 56 | 3992 | 狐火 33% Mon3tr 6% 大剑 5% 刺剑 4% | 铃兰 31% 凯尔希 18% 流明 17% (399 / 0.4) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 24 | 75% | 10:57 / 7:57 | 100% | 100% | 1:27 | 0:56 / 3:25 | 2.4 / 74s | 17.4 | 54 | 2 | 3 | 16 | 14% / 13458 | bullet |
| [normal] suzuran | 24 | 16% | 7:53 / 3:54 | 100% | 91% | 1:23 | 3:19 / 6:25 | 1.2 / 57s | 26.4 | 81 | 8 | 2 | 0 | 36% / 13417 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | suzuran | 24 | 29.7 | 7.1% | A 199/62 B 84/43 C 170/82 D 170/44 E 186/54 F 58/27 G 159/69 H 384/126 通用 475/214 | 0 |
| normal | suzuran | 24 | 14.5 | 2.4% | A 92/37 B 34/17 C 57/18 D 72/21 E 103/35 F 23/9 G 62/25 H 164/57 通用 234/132 | 0 |
| 合计 | | | | | A 291/99 B 118/60 C 227/100 D 242/65 E 289/89 F 81/36 G 221/94 H 548/183 通用 709/346 | |

拿取最多（出现 / 拿取）：“决心” 0/31，“观望” 0/29，“犹疑” 0/26，海潮的气息 0/21，皇帝的恩宠 49/20，深蓝之心 0/20，镶金骨骰 62/19，洁白的舞鞋 33/18，堡垒协议-方阵 60/18，漆黑的舞鞋 30/17，凯旋号角 63/16，涡旋座 53/15
