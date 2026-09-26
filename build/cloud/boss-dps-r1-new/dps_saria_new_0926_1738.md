# balance dps_saria_new 0926_1738

args: `--game game --jobs 4 --out build/cloud/boss-dps-r1-new --op saria --bots expert,normal --seeds 24 --tag dps_saria_new`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 9 | 9 | 9 | 65s / 66s / 91s / 48–91s | 41s / 76s | 7.9 / 2.0 | - |
| expert | 伊莎玛拉 | resolve 7 | 7 | 7 | 47s / 49s / 57s / 39–57s | 49s / 57s | 9.3 / 2.0 | - |
| expert | 最后的骑士 | knight 6 | 6 | 5 | 65s / 49s / 133s / 43–133s | 49s / 133s | 11.3 / 1.8 | 33% |
| expert | 偏执泡影 | standard 2 | 2 | 2 | 49s / 49s / 60s / 39–60s | 50s / 60s | 10.9 / 2.0 | - |
| normal | 偏执泡影 | standard 6 | 6 | 5 | 87s / 70s / 178s / 43–178s | 70s / 178s | 1.1 / 1.3 | 88% |
| normal | 最后的骑士 | knight 4 | 4 | 2 | 89s / 89s / 127s / 51–127s | 89s / 127s | 1.7 / 1.8 | 34% |
| normal | 伊莎玛拉 | resolve 3 | 3 | 3 | 60s / 56s / 71s / 54–71s | 56s / 71s | 2.6 / 2.0 | - |
| normal | 伊祖米克 | deep 2 | 2 | 1 | 71s / 71s / 71s / 71–71s | 44s / 44s | 2.0 / 2.0 | 3% |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 24 | 0% | 16 / 16 | 100% |
| normal | 0 | 24 | 0% | 16 / 16 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 2 | 8:19 |
| normal | 0 | corrode | 第 2 轮 · 收缩 | 否 | 是 | 2 | 10:04 |
| normal | 0 | bullet | 第 3 轮 · 预告 | 否 | 是 | 2 | 8:41 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:41 |
| normal | 0 | shock | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | boss_nest | 第 1 轮 · 稳定 | 否 | 是 | 1 | 9:54 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 8:18 |
| normal | 0 | mire | 第 3 轮 · 预告 | 否 | 是 | 1 | 9:12 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 24 | 全程 | 284 / 450 | 55 / 126 | 1 / 7 | 412 / 612 | 45 / 48 |
| expert | 0 | 24 | 8:00–10:00 | 251 / 423 | 45 / 84 | 1 / 6 | 391 / 509 | 44 / 48 |
| normal | 0 | 24 | 全程 | 322 / 454 | 54 / 114 | 1 / 6 | 384 / 525 | 42 / 48 |
| normal | 0 | 21 | 8:00–10:00 | 297 / 451 | 45 / 67 | 1 / 5 | 347 / 525 | 33 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 24 | 1:15 | 26 | 27s / 22s（24/24） | 2 / 4 | 0 | bone/slider/stone ×14；bone/slider ×10 |
| expert | 2 | 24 | 2:45 | 33 | 27s / 21s（24/24） | 3 / 6 | 0 | bone/slider ×14；bone/slider/stone ×10 |
| expert | 3 | 24 | 4:52 | 44 | 22s / 15s（24/24） | 8 / 25 | 0 | bone/floater/ripper/runner/slider/tracer ×11；bone/offspring/ripper/slider/spitter ×8；bone/ripper/slider/stone ×2 |
| expert | 4 | 24 | 6:02 | 50 | 15s / 12s（24/24） | 8 / 29 | 0 | bone/burrower/ripper/slider ×13；bone/offspring/ripper/slider/spitter ×7；bone/floater/ripper/runner/slider/tracer ×4 |
| expert | 5 | 24 | 7:29 | 57 | 16s / 12s（24/24） | 18 / 46 | 0 | bone/burrower/offspring/ripper/slider/stone ×10；bone/floater/founder/nest/ripper/runner/slider ×8；burrower/ripper/slider/spitter ×6 |
| expert | 6 | 24 | 8:41 | 63 | 13s / 11s（24/24） | 24 / 147 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×9；bone/burrower/offspring/ripper/slider/stone ×5；burrower/hulk/ripper/slider/spitter ×4 |
| expert | 7 | 7 | 9:13 | 66 | 10s / 11s（7/7） | 8 / 26 | 0 | burrower/offspring/ripper/slider/spitter/stone ×5；burrower/hulk/ripper/slider/spitter ×2 |
| normal | 1 | 24 | 1:15 | 26 | 10s / 9s（24/24） | 5 / 15 | 0 | bone/slider/stone ×14；bone/slider ×10 |
| normal | 2 | 24 | 2:45 | 33 | 21s / 16s（24/24） | 4 / 21 | 0 | bone/slider ×14；bone/slider/stone ×10 |
| normal | 3 | 24 | 4:48 | 44 | 40s / 32s（24/24） | 18 / 49 | 0 | bone/floater/ripper/runner/slider/tracer ×7；bone/offspring/ripper/slider/spitter ×6；bone/burrower/ripper/slider ×6 |
| normal | 4 | 24 | 6:07 | 50 | 28s / 28s（24/24） | 25 / 115 | 0 | bone/floater/ripper/runner/slider/tracer ×10；bone/offspring/ripper/slider/spitter ×9；bone/burrower/ripper/slider ×5 |
| normal | 5 | 20 | 7:48 | 58 | 29s / 26s（20/20） | 27 / 57 | 0 | bone/floater/founder/nest/ripper/runner/slider ×10；bone/burrower/offspring/ripper/slider/stone ×7；burrower/ripper/slider/spitter ×3 |
| normal | 6 | 16 | 8:49 | 64 | 26s / 23s（15/16） | 36 / 98 | 1 | burrower/offspring/ripper/slider/spitter/stone ×5；burrower/hulk/ripper/slider/spitter ×4；burrower/ripper/slider/spitter ×3 |
| normal | 7 | 2 | 9:17 | 66 | 8s / 8s（2/2） | 15 / 30 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×1；burrower/hulk/ripper/slider/spitter ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 24 | 45% | 10:31 | 100% | 31.2 | 6239 | 30–55% / 7:00–13:00 | **达标** |
| expert | 24 | 95% | 11:03 | 100% | 34.0 | 6838 | 70–95% / 9:00–13:00 | **偏易** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 24 | 95% | 11:03 / 10:39 | 0.0 / - | 6 / 15 / 26 / 34 | 33% | 100% | 67 | 6838 | 锯刃 8% 言 5% 殉爆 4% 余震 4% | 塞雷娅 78% 凯尔希 9% 流明 5% (621 / 0.0) | bullet |
| [normal] saria | 24 | 45% | 10:31 / 7:08 | 0.0 / - | 7 / 15 / 25 / 31 | 63% | 48% | 53 | 6239 | 拳击 8% 大剑 8% 刺剑 7% 余震 6% | 塞雷娅 74% 流明 7% 水月 6% (1234 / 0.4) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] saria | 24 | 95% | 11:03 / 10:39 | 100% | 100% | 1:42 | 0:49 / 3:33 | 2.2 / 74s | 18.4 | 66 | 1 | 3 | 13 | 6% / 6807 | bullet |
| [normal] saria | 24 | 45% | 10:31 / 7:08 | 100% | 100% | 1:16 | 3:43 / 6:07 | 1.6 / 92s | 47.7 | 139 | 4 | 14 | 0 | 14% / 10209 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | saria | 24 | 30.0 | 6.0% | A 260/81 B 93/52 C 183/95 D 165/42 E 182/45 F 54/25 G 155/50 H 367/103 通用 463/239 | 0 |
| normal | saria | 24 | 20.1 | 1.4% | A 198/65 B 54/14 C 119/39 D 107/38 E 98/33 F 20/6 G 111/29 H 207/75 通用 328/184 | 0 |
| 合计 | | | | | A 458/146 B 147/66 C 302/134 D 272/80 E 280/78 F 74/31 G 266/79 H 574/178 通用 791/423 | |

拿取最多（出现 / 拿取）：“决心” 0/43，“犹疑” 0/41，“观望” 0/32，漆黑的舞鞋 49/27，凯旋号角 82/24，海潮的气息 0/24，深蓝之心 0/24，老近卫军之锋 74/21，古高卢银币 34/20，羽兽肝酱 75/19，残破合影 54/18，聚火源石虫 52/18
