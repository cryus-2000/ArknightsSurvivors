# balance dps_suzuran_base 0926_1728

args: `--game game --jobs 4 --out build/cloud/boss-dps-r1-base --op suzuran --bots expert,normal --seeds 24 --tag dps_suzuran_base`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 7 | 7 | 4 | 57s / 57s / 65s / 51–65s | 33s / 40s | 5.3 / 1.3 | 86% |
| expert | 最后的骑士 | knight 7 | 7 | 4 | 57s / 57s / 66s / 48–66s | 58s / 66s | 9.7 / 1.7 | 24% |
| expert | 伊莎玛拉 | resolve 3 | 3 | 1 | 14s / 14s / 14s / 14–14s | 14s / 14s | 0.0 / 0.3 | 67% |
| expert | 偏执泡影 | standard 3 | 3 | 3 | 77s / 90s / 100s / 43–100s | 90s / 100s | 6.9 / 2.0 | - |
| normal | 偏执泡影 | standard 3 | 3 | 2 | 50s / 50s / 52s / 48–52s | 50s / 52s | 6.1 / 1.3 | 100% |
| normal | 最后的骑士 | knight 2 | 2 | 2 | 60s / 60s / 62s / 59–62s | 60s / 62s | 3.9 / 2.0 | - |
| normal | 伊祖米克 | deep 1 | 1 | 1 | 71s / 71s / 71s / 71–71s | 31s / 31s | 24.7 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 24 | 0% | 19 / 11 | 98% |
| normal | 0 | 24 | 0% | 20 / 16 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 4 | 12:20 |
| expert | 0 | bullet | 第 3 轮 · 预告 | 否 | 是 | 2 | 10:01 |
| expert | 0 | bullet | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | contact_knight_boss | 第 5 轮 · 预告 | 否 | 是 | 1 | 10:44 |
| expert | 0 | shock | 第 1 轮 · 稳定 | 否 | 是 | 1 | 9:47 |
| expert | 0 | bullet | 第 2 轮 · 预告 | 否 | 是 | 1 | 7:19 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | bullet | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:52 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 8:10 |
| normal | 0 | bullet | 第 4 轮 · 稳定 | 否 | 否 | 2 | 9:20 |
| normal | 0 | bullet | 第 3 轮 · 收缩 | 否 | 是 | 2 | 7:31 |
| normal | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 2 | 7:39 |
| normal | 0 | mire | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:29 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 7:22 |
| normal | 0 | mire | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:36 |
| normal | 0 | mire | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:00 |
| normal | 0 | mire | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:55 |
| normal | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:45 |
| normal | 0 | contact_slider | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:19 |
| normal | 0 | mire | 第 2 轮 · 稳定 | 否 | 是 | 1 | 7:14 |
| normal | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| normal | 0 | boss_tracer | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:55 |
| normal | 0 | bullet | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:04 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 24 | 全程 | 285 / 450 | 48 / 78 | 8 / 10 | 400 / 499 | 41 / 48 |
| expert | 0 | 21 | 8:00–10:00 | 271 / 450 | 45 / 78 | 6 / 9 | 378 / 434 | 39 / 48 |
| normal | 0 | 24 | 全程 | 297 / 510 | 41 / 58 | 8 / 11 | 350 / 456 | 38 / 48 |
| normal | 0 | 12 | 8:00–10:00 | 264 / 510 | 43 / 58 | 6 / 9 | 354 / 456 | 37 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 24 | 1:15 | 26 | 13s / 13s（24/24） | 2 / 5 | 0 | bone/slider ×12；bone/slider/stone ×12 |
| expert | 2 | 24 | 2:45 | 33 | 13s / 12s（24/24） | 5 / 33 | 0 | bone/slider/stone ×12；bone/slider ×12 |
| expert | 3 | 24 | 4:45 | 43 | 26s / 20s（24/24） | 11 / 32 | 0 | bone/offspring/ripper/slider/spitter ×7；bone/burrower/ripper/slider ×6；bone/floater/ripper/runner/slider/tracer ×4 |
| expert | 4 | 24 | 6:03 | 50 | 22s / 18s（24/24） | 8 / 36 | 0 | bone/floater/ripper/runner/slider/tracer ×13；bone/offspring/ripper/slider/spitter ×7；bone/burrower/ripper/slider ×4 |
| expert | 5 | 23 | 7:34 | 57 | 19s / 14s（23/23） | 24 / 108 | 2 | bone/floater/founder/nest/ripper/runner/slider ×10；bone/burrower/offspring/ripper/slider/stone ×7；burrower/ripper/slider/spitter ×6 |
| expert | 6 | 21 | 8:47 | 64 | 21s / 13s（21/21） | 17 / 74 | 0 | burrower/offspring/ripper/slider/spitter/stone ×11；burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×3；bone/floater/founder/nest/ripper/runner/slider ×3 |
| expert | 7 | 1 | 9:15 | 66 | 8s / 8s（1/1） | 0 / 0 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×1 |
| normal | 1 | 24 | 1:15 | 26 | 10s / 10s（24/24） | 7 / 44 | 0 | bone/slider ×15；bone/slider/stone ×9 |
| normal | 2 | 24 | 2:45 | 33 | 13s / 14s（24/24） | 4 / 17 | 0 | bone/slider/stone ×15；bone/slider ×9 |
| normal | 3 | 24 | 4:38 | 43 | 31s / 19s（23/24） | 21 / 74 | 1 | bone/floater/ripper/runner/slider ×8；bone/burrower/ripper/slider ×5；bone/floater/ripper/runner/slider/tracer ×4 |
| normal | 4 | 22 | 5:58 | 49 | 26s / 21s（20/22） | 29 / 98 | 0 | bone/offspring/ripper/slider/spitter ×8；bone/floater/ripper/runner/slider/tracer ×8；bone/burrower/ripper/slider ×6 |
| normal | 5 | 14 | 7:38 | 58 | 18s / 14s（10/14） | 22 / 141 | 3 | bone/floater/founder/nest/ripper/runner/slider ×6；burrower/ripper/slider/spitter ×4；bone/burrower/offspring/ripper/slider/stone ×4 |
| normal | 6 | 10 | 8:48 | 64 | 10s / 9s（9/10） | 47 / 171 | 3 | burrower/offspring/ripper/slider/spitter/stone ×3；burrower/ripper/slider/spitter ×2；bone/floater/founder/nest/ripper/runner/slider ×2 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 24 | 20% | 8:37 | 100% | 26.1 | 4477 | 30–55% / 7:00–13:00 | **偏难** |
| expert | 24 | 50% | 10:57 | 100% | 32.7 | 6689 | 70–95% / 9:00–13:00 | **偏难** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 24 | 50% | 10:57 / 7:03 | 0.0 / - | 7 / 15 / 25 / 33 | 59% | 100% | 65 | 6689 | 狐火 12% Mon3tr 6% 藏品 5% 火山弹 4% | 铃兰 35% 凯尔希 25% 塞雷娅 20% (542 / 0.5) | bullet |
| [normal] suzuran | 24 | 20% | 8:37 / 5:19 | 0.0 / - | 7 / 15 / 25 / 26 | 68% | 29% | 64 | 4477 | 狐火 29% 锚击 5% 刺剑 5% 火山弹 5% | 铃兰 34% 流明 20% 拾取 12% (459 / 0.4) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 24 | 50% | 10:57 / 7:03 | 100% | 100% | 1:35 | 0:57 / 3:04 | 1.8 / 79s | 22.7 | 67 | 3 | 5 | 14 | 16% / 15206 | bullet |
| [normal] suzuran | 24 | 20% | 8:37 / 5:19 | 100% | 100% | 1:25 | 3:50 / 6:45 | 1.5 / 55s | 25.0 | 87 | 9 | 3 | 0 | 32% / 14992 | bullet |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | suzuran | 24 | 28.5 | 9.2% | A 203/52 B 77/44 C 175/96 D 174/31 E 208/42 F 47/29 G 130/58 H 342/121 通用 438/221 | 0 |
| normal | suzuran | 24 | 16.8 | 1.1% | A 102/34 B 50/9 C 94/32 D 89/37 E 112/45 F 25/8 G 89/27 H 180/65 通用 242/147 | 0 |
| 合计 | | | | | A 305/86 B 127/53 C 269/128 D 263/68 E 320/87 F 72/37 G 219/85 H 522/186 通用 680/368 | |

拿取最多（出现 / 拿取）：“犹疑” 0/42，“决心” 0/37，海潮的气息 0/23，“观望” 0/22，羽兽肝酱 61/19，损坏的左轮弹巢 69/17，“黑夜呢喃” 62/17，皇帝的恩宠 73/17，支柱-援护 26/16，镶金骨骰 71/16，演员的首饰盒 47/15，阿卡胡拉饭碗 40/15
