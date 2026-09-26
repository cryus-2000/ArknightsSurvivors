# balance lr_share_base 0926_1731

args: `--game game --jobs 4 --out build/cloud/logos-rework-base --squad logos,siege,mizuki --bots expert,normal --seeds 8 --extra=--nodeath --tag lr_share_base`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊莎玛拉 | resolve 3 | 3 | 3 | 39s / 39s / 39s / 39–39s | 39s / 39s | 29.1 / 2.0 | - |
| expert | 最后的骑士 | knight 2 | 2 | 2 | 44s / 44s / 46s / 43–46s | 44s / 46s | 25.9 / 2.0 | - |
| expert | 伊祖米克 | deep 2 | 2 | 2 | 53s / 53s / 57s / 49–57s | 30s / 30s | 23.8 / 2.0 | - |
| expert | 偏执泡影 | standard 1 | 1 | 1 | 39s / 39s / 39s / 39–39s | 39s / 39s | 29.4 / 2.0 | - |
| normal | 伊祖米克 | deep 3 | 3 | 3 | 59s / 57s / 64s / 56–64s | 30s / 30s | 20.7 / 2.0 | - |
| normal | 最后的骑士 | knight 2 | 2 | 2 | 50s / 50s / 58s / 42–58s | 50s / 58s | 19.5 / 2.0 | - |
| normal | 偏执泡影 | standard 2 | 2 | 2 | 39s / 39s / 40s / 39–40s | 40s / 40s | 15.9 / 2.0 | - |
| normal | 伊莎玛拉 | resolve 1 | 1 | 1 | 38s / 38s / 38s / 38–38s | 38s / 38s | 26.4 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 7 / 6 | 100% |
| normal | 0 | 8 | 0% | 8 / 7 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | （全部胜利） | | | | 0 | |
| normal | 0 | （全部胜利） | | | | 0 | |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 167 / 182 | 40 / 69 | 0 / 0 | 371 / 415 | 48 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 164 / 182 | 28 / 69 | 0 / 0 | 347 / 376 | 46 / 48 |
| normal | 0 | 8 | 全程 | 268 / 378 | 62 / 75 | 0 / 0 | 413 / 461 | 48 / 48 |
| normal | 0 | 8 | 8:00–10:00 | 217 / 282 | 51 / 75 | 0 / 0 | 396 / 446 | 48 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 26 | 10s / 10s（8/8） | 1 / 3 | 0 | bone/slider/stone ×4；bone/slider ×4 |
| expert | 2 | 8 | 2:45 | 33 | 7s / 8s（8/8） | 1 / 4 | 0 | bone/slider ×4；bone/slider/stone ×4 |
| expert | 3 | 8 | 4:15 | 41 | 8s / 6s（8/8） | 0 / 0 | 0 | bone/ripper/slider/stone ×4；bone/offspring/ripper/slider/stone ×2；bone/floater/ripper/runner/slider ×2 |
| expert | 4 | 8 | 5:40 | 48 | 7s / 7s（8/8） | 7 / 13 | 0 | bone/burrower/ripper/slider ×4；bone/floater/ripper/runner/slider/tracer ×3；bone/offspring/ripper/slider/spitter ×1 |
| expert | 5 | 8 | 7:26 | 57 | 7s / 7s（8/8） | 7 / 19 | 0 | burrower/ripper/slider/spitter ×4；bone/floater/founder/nest/ripper/runner/slider ×2；bone/burrower/offspring/ripper/slider/stone ×2 |
| expert | 6 | 8 | 8:36 | 62 | 6s / 6s（8/8） | 8 / 33 | 0 | bone/floater/founder/nest/ripper/runner/slider ×4；burrower/offspring/ripper/slider/spitter/stone ×2；burrower/ripper/slider/spitter ×1 |
| normal | 1 | 8 | 1:15 | 26 | 8s / 8s（8/8） | 1 / 3 | 0 | bone/slider/stone ×4；bone/slider ×4 |
| normal | 2 | 8 | 2:45 | 33 | 11s / 10s（8/8） | 1 / 4 | 0 | bone/slider ×4；bone/slider/stone ×4 |
| normal | 3 | 8 | 4:16 | 41 | 30s / 23s（8/8） | 3 / 21 | 0 | bone/ripper/slider/stone ×3；bone/floater/ripper/runner/slider ×3；bone/offspring/ripper/slider/stone ×2 |
| normal | 4 | 8 | 5:41 | 48 | 23s / 20s（8/8） | 7 / 18 | 0 | bone/burrower/ripper/slider ×4；bone/offspring/ripper/slider/spitter ×2；bone/floater/ripper/runner/slider/tracer ×2 |
| normal | 5 | 8 | 7:35 | 58 | 15s / 14s（8/8） | 41 / 139 | 0 | bone/floater/founder/nest/ripper/runner/slider ×6；bone/burrower/offspring/ripper/slider/stone ×2 |
| normal | 6 | 8 | 8:25 | 61 | 10s / 10s（8/8） | 19 / 62 | 0 | burrower/ripper/slider/spitter ×4；bone/floater/founder/nest/ripper/runner/slider ×2；bone/burrower/offspring/ripper/slider/stone ×1 |
| normal | 7 | 4 | 9:20 | 66 | 9s / 8s（4/4） | 19 / 62 | 0 | burrower/hulk/ripper/slider/spitter ×3；burrower/offspring/ripper/slider/spitter/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 100% | 10:49 | 100% | 33.8 | 6668 | 30–55% / 7:00–13:00 | **偏易** |
| expert | 8 | 100% | 10:43 | 100% | 34.6 | 6606 | 70–95% / 9:00–13:00 | **偏易** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos+siege+mizuki | 8 | 100% | 10:43 / 10:39 | 0.0 / - | 7 / 16 / 27 / 35 | - | 96% | 70 | 6606 | 言 23% 触手 19% 提喻 18% 湮灭 12% | 水月 89% 无人机 7% 塞雷娅 1% (333 / 1.4) | mire |
| [normal] logos+siege+mizuki | 8 | 100% | 10:49 / 10:38 | 0.1 / 7:54 | 7 / 16 / 26 / 34 | - | 66% | 82 | 6668 | 言 18% 触手 16% 提喻 15% 伞击 12% | 水月 93% 拾取 5% 无人机 0% (504 / 0.2) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos+siege+mizuki | 8 | 100% | 10:43 / 10:39 | 100% | 100% | 8:50 | 0:56 / 3:07 | 2.6 / 14s | 8.1 | 36 | 0 | 2 | 18 | 67% / 75034 | - |
| [normal] logos+siege+mizuki | 8 | 100% | 10:49 / 10:38 | 100% | 100% | - | 2:29 / 7:27 | 2.5 / 32s | 18.2 | 69 | 0 | 4 | 0 | 53% / 54096 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | logos | 8 | 27.6 | 1.7% | A 46/13 B 29/13 C 55/26 D 58/21 E 56/17 F 12/7 G 47/22 H 92/24 通用 162/80 | 0 |
| normal | logos | 8 | 22.6 | 0.2% | A 34/11 B 16/5 C 33/8 D 37/13 E 61/20 F 5/1 G 37/11 H 87/25 通用 139/87 | 0 |
| 合计 | | | | | A 80/24 B 45/18 C 88/34 D 95/34 E 117/37 F 17/8 G 84/33 H 179/49 通用 301/167 | |

拿取最多（出现 / 拿取）：“决心” 0/18，“犹疑” 0/17，“观望” 0/13，“黑夜呢喃” 17/8，“璀璨悲泣” 16/8，老近卫军之锋 21/8，深蓝之心 0/8，损坏的左轮弹巢 18/8，残破合影 24/7，演员的首饰盒 14/7，聚火源石虫 20/7，镶金骨骰 16/7
