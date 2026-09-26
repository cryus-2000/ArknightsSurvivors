# balance lr_solo_new 0926_1730

args: `--game game --jobs 4 --out build/cloud/logos-rework-new --op logos --bots expert,normal --seeds 16 --tag lr_solo_new`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 5 | 5 | 5 | 60s / 58s / 78s / 51–78s | 32s / 36s | 16.9 / 2.0 | - |
| expert | 偏执泡影 | standard 4 | 4 | 4 | 39s / 39s / 42s / 39–42s | 39s / 42s | 12.3 / 2.0 | - |
| expert | 伊莎玛拉 | resolve 4 | 4 | 4 | 41s / 40s / 45s / 39–45s | 40s / 45s | 15.0 / 2.0 | - |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 46s / 46s / 49s / 43–49s | 46s / 49s | 23.4 / 2.0 | - |
| normal | 最后的骑士 | knight 1 | 1 | 1 | 52s / 52s / 52s / 52–52s | 52s / 52s | 13.9 / 2.0 | - |
| normal | 伊祖米克 | deep 1 | 1 | 1 | 44s / 44s / 44s / 44–44s | 30s / 30s | 18.7 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 38 / 34 | 99% |
| normal | 0 | 16 | 0% | 87 / 72 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | shock | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:02 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 2 | 3:21 |
| normal | 0 | mire | 第 3 轮 · 稳定 | 否 | 是 | 2 | 7:28 |
| normal | 0 | contact_slider | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:07 |
| normal | 0 | bullet | 第 3 轮 · 稳定 | 否 | 否 | 1 | 6:50 |
| normal | 0 | boss_reaper | 第 3 轮 · 预告 | 否 | 否 | 1 | 5:56 |
| normal | 0 | contact_slider | 第 3 轮 · 收缩 | 否 | 是 | 1 | 8:13 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 6:05 |
| normal | 0 | boss_reaper | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:40 |
| normal | 0 | boss_tracer | 第 4 轮 · 稳定 | 否 | 否 | 1 | 8:56 |
| normal | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:15 |
| normal | 0 | contact_burrower | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:51 |
| normal | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:56 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 280 / 384 | 55 / 76 | 2 / 8 | 406 / 541 | 48 / 48 |
| expert | 0 | 16 | 8:00–10:00 | 197 / 238 | 41 / 59 | 2 / 7 | 361 / 425 | 48 / 48 |
| normal | 0 | 16 | 全程 | 270 / 450 | 35 / 73 | 1 / 3 | 355 / 447 | 42 / 48 |
| normal | 0 | 5 | 8:00–10:00 | 211 / 282 | 56 / 63 | 0 / 0 | 287 / 367 | 40 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 26 | 64s / 63s（16/16） | 3 / 7 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 16 | 2:45 | 33 | 18s / 18s（16/16） | 7 / 22 | 0 | bone/slider ×10；bone/slider/stone ×6 |
| expert | 3 | 16 | 4:15 | 41 | 10s / 9s（16/16） | 3 / 8 | 0 | bone/floater/ripper/runner/slider ×7；bone/offspring/ripper/slider/stone ×5；bone/ripper/slider/stone ×4 |
| expert | 4 | 16 | 5:40 | 48 | 11s / 10s（16/16） | 9 / 22 | 0 | bone/offspring/ripper/slider/spitter ×6；bone/floater/ripper/runner/slider/tracer ×6；bone/burrower/ripper/slider ×4 |
| expert | 5 | 16 | 7:32 | 57 | 9s / 8s（16/16） | 11 / 36 | 0 | bone/floater/founder/nest/ripper/runner/slider ×7；burrower/ripper/slider/spitter ×5；bone/burrower/offspring/ripper/slider/stone ×4 |
| expert | 6 | 16 | 8:42 | 63 | 7s / 7s（16/16） | 24 / 79 | 1 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×4；burrower/hulk/ripper/slider/spitter ×4；bone/burrower/offspring/ripper/slider/stone ×3 |
| normal | 1 | 16 | 1:15 | 26 | 14s / 10s（16/16） | 12 / 29 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| normal | 2 | 16 | 2:45 | 33 | 23s / 16s（16/16） | 14 / 72 | 0 | bone/slider ×11；bone/slider/stone ×5 |
| normal | 3 | 14 | 4:24 | 42 | 21s / 18s（14/14） | 2 / 12 | 1 | bone/floater/ripper/runner/slider ×6；bone/offspring/ripper/slider/stone ×4；bone/ripper/slider/stone ×2 |
| normal | 4 | 12 | 5:46 | 49 | 16s / 12s（12/12） | 37 / 140 | 2 | bone/floater/ripper/runner/slider/tracer ×6；bone/burrower/ripper/slider ×5；bone/offspring/ripper/slider/spitter ×1 |
| normal | 5 | 6 | 7:39 | 58 | 10s / 10s（5/6） | 31 / 81 | 3 | bone/floater/founder/nest/ripper/runner/slider ×3；burrower/ripper/slider/spitter ×2；bone/burrower/offspring/ripper/slider/stone ×1 |
| normal | 6 | 3 | 8:41 | 63 | 8s / 8s（3/3） | 74 / 136 | 1 | burrower/hulk/ripper/slider/spitter ×2；bone/burrower/offspring/ripper/slider/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 16 | 12% | 7:04 | 87% | 21.9 | 3369 | 30–55% / 7:00–13:00 | **偏难** |
| expert | 16 | 93% | 10:41 | 100% | 33.9 | 6527 | 70–95% / 9:00–13:00 | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos | 16 | 93% | 10:41 / 9:02 | 0.0 / - | 3 / 17 / 26 / 34 | - | 96% | 59 | 6527 | 延展敏锐 36% 提喻 12% 言 4% Mon3tr 3% | 凯尔希 46% 塞雷娅 13% 无人机 13% (404 / 0.4) | bullet |
| [normal] logos | 16 | 12% | 7:04 / 3:17 | 0.0 / - | 6 / 16 / 26 / 22 | 69% | 25% | 49 | 3369 | 提喻 11% 言 10% 延展敏锐 10% 大剑 5% | 拾取 33% 流明 14% 无人机 13% (340 / 0.3) | boss_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos | 16 | 93% | 10:41 / 9:02 | 100% | 100% | 2:38 | 2:15 / 3:15 | 2.4 / 20s | 20.2 | 54 | 2 | 0 | 16 | 59% / 62691 | shock |
| [normal] logos | 16 | 12% | 7:04 / 3:17 | 87% | 81% | 1:28 | 3:12 / 5:52 | 1.1 / 35s | 49.7 | 94 | 14 | 5 | 0 | 41% / 17637 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | logos | 16 | 29.9 | 3.3% | A 113/29 B 57/30 C 110/62 D 130/33 E 162/48 F 29/12 G 111/51 H 230/67 通用 319/152 | 0 |
| normal | logos | 16 | 11.6 | 1.1% | A 41/17 B 18/5 C 43/9 D 41/15 E 59/21 F 16/3 G 42/6 H 86/37 通用 124/74 | 0 |
| 合计 | | | | | A 154/46 B 75/35 C 153/71 D 171/48 E 221/69 F 45/15 G 153/57 H 316/104 通用 443/226 | |

拿取最多（出现 / 拿取）：“观望” 0/21，“犹疑” 0/20，“决心” 0/20，洁白的舞鞋 28/17，深蓝之心 0/13，海潮的气息 0/13，凯旋号角 38/11，涡旋座 39/11，羽兽肝酱 43/10，异铁小圆盾 29/10，古旧钱币 28/10，损坏的左轮弹巢 33/10
