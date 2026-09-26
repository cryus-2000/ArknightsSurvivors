# balance lr_share_new 0926_1733

args: `--game game --jobs 4 --out build/cloud/logos-rework-new --squad logos,siege,mizuki --bots expert,normal --seeds 8 --extra=--nodeath --tag lr_share_new`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 伊祖米克 | deep 4 | 4 | 4 | 67s / 67s / 76s / 57–76s | 30s / 31s | 21.5 / 2.0 | - |
| expert | 偏执泡影 | standard 2 | 2 | 2 | 39s / 39s / 39s / 39–39s | 39s / 39s | 23.6 / 2.0 | - |
| expert | 伊莎玛拉 | resolve 2 | 2 | 2 | 39s / 39s / 39s / 39–39s | 39s / 39s | 24.9 / 2.0 | - |
| normal | 最后的骑士 | knight 4 | 4 | 4 | 46s / 46s / 47s / 45–47s | 46s / 47s | 22.9 / 2.0 | - |
| normal | 偏执泡影 | standard 3 | 3 | 3 | 51s / 44s / 71s / 39–71s | 44s / 71s | 9.7 / 2.0 | - |
| normal | 伊莎玛拉 | resolve 1 | 1 | 1 | 39s / 39s / 39s / 39–39s | 39s / 39s | 11.2 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 12 / 13 | 100% |
| normal | 0 | 8 | 0% | 8 / 8 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | （全部胜利） | | | | 0 | |
| normal | 0 | （全部胜利） | | | | 0 | |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 180 / 204 | 34 / 49 | 0 / 0 | 374 / 386 | 48 / 48 |
| expert | 0 | 8 | 8:00–10:00 | 172 / 182 | 25 / 36 | 0 / 0 | 365 / 383 | 48 / 48 |
| normal | 0 | 8 | 全程 | 218 / 333 | 51 / 74 | 0 / 0 | 393 / 429 | 48 / 48 |
| normal | 0 | 8 | 8:00–10:00 | 203 / 316 | 48 / 74 | 0 / 0 | 369 / 420 | 48 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 26 | 10s / 10s（8/8） | 4 / 6 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| expert | 2 | 8 | 2:45 | 33 | 11s / 12s（8/8） | 3 / 14 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| expert | 3 | 8 | 4:15 | 41 | 9s / 6s（8/8） | 1 / 3 | 0 | bone/ripper/slider/stone ×4；bone/offspring/ripper/slider/stone ×4 |
| expert | 4 | 8 | 5:40 | 48 | 6s / 6s（8/8） | 8 / 42 | 0 | bone/burrower/ripper/slider ×3；bone/offspring/ripper/slider/spitter ×3；bone/floater/ripper/runner/slider/tracer ×2 |
| expert | 5 | 8 | 7:24 | 57 | 9s / 9s（8/8） | 5 / 13 | 0 | bone/floater/founder/nest/ripper/runner/slider ×5；burrower/ripper/slider/spitter ×2；bone/burrower/offspring/ripper/slider/stone ×1 |
| expert | 6 | 8 | 8:34 | 62 | 7s / 6s（8/8） | 13 / 32 | 0 | burrower/ripper/slider/spitter ×4；bone/floater/founder/nest/ripper/runner/slider ×2；bone/burrower/offspring/ripper/slider/stone ×2 |
| normal | 1 | 8 | 1:15 | 26 | 8s / 8s（8/8） | 3 / 6 | 0 | bone/slider/stone ×6；bone/slider ×2 |
| normal | 2 | 8 | 2:45 | 33 | 14s / 14s（8/8） | 1 / 5 | 0 | bone/slider ×6；bone/slider/stone ×2 |
| normal | 3 | 8 | 4:20 | 41 | 20s / 20s（8/8） | 6 / 32 | 0 | bone/ripper/slider/stone ×3；bone/offspring/ripper/slider/stone ×2；bone/floater/ripper/runner/slider ×2 |
| normal | 4 | 8 | 5:39 | 48 | 18s / 7s（8/8） | 13 / 48 | 0 | bone/floater/ripper/runner/slider/tracer ×4；bone/offspring/ripper/slider/spitter ×2；bone/burrower/ripper/slider ×2 |
| normal | 5 | 8 | 7:23 | 56 | 11s / 6s（8/8） | 18 / 58 | 0 | burrower/ripper/slider/spitter ×4；bone/floater/founder/nest/ripper/runner/slider ×3；bone/burrower/offspring/ripper/slider/stone ×1 |
| normal | 6 | 8 | 8:33 | 62 | 11s / 7s（8/8） | 40 / 155 | 0 | bone/floater/founder/nest/ripper/runner/slider ×3；bone/burrower/offspring/ripper/slider/stone ×2；burrower/ripper/slider/spitter ×2 |
| normal | 7 | 1 | 9:15 | 66 | 10s / 10s（1/1） | 75 / 75 | 0 | burrower/offspring/ripper/slider/spitter/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 100% | 10:47 | 100% | 33.6 | 6641 | 30–55% / 7:00–13:00 | **偏易** |
| expert | 8 | 100% | 10:53 | 100% | 34.6 | 6748 | 70–95% / 9:00–13:00 | **偏易** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos+siege+mizuki | 8 | 100% | 10:53 / 10:39 | 0.0 / - | 7 / 17 / 26 / 35 | - | 100% | 67 | 6748 | 延展敏锐 34% 触手 28% 伞击 11% 提喻 11% | 水月 91% 无人机 5% 拾取 2% (294 / 2.2) | bullet |
| [normal] logos+siege+mizuki | 8 | 100% | 10:47 / 10:39 | 0.0 / - | 6 / 16 / 26 / 34 | - | 62% | 94 | 6641 | 延展敏锐 34% 触手 15% 提喻 14% 伞击 9% | 水月 85% 拾取 7% 无人机 6% (509 / 0.5) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos+siege+mizuki | 8 | 100% | 10:53 / 10:39 | 100% | 100% | - | 0:52 / 3:36 | 2.5 / 15s | 8.2 | 33 | 0 | 0 | 15 | 50% / 54653 | - |
| [normal] logos+siege+mizuki | 8 | 100% | 10:47 / 10:39 | 100% | 100% | - | 2:35 / 6:14 | 2.4 / 22s | 32.8 | 84 | 0 | 7 | 0 | 58% / 57069 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | logos | 8 | 28.1 | 1.3% | A 44/16 B 16/7 C 52/27 D 62/21 E 69/18 F 7/3 G 47/22 H 102/35 通用 133/76 | 0 |
| normal | logos | 8 | 23.9 | 1.9% | A 44/19 B 26/8 C 46/13 D 52/22 E 49/16 F 10/2 G 45/20 H 80/27 通用 120/64 | 0 |
| 合计 | | | | | A 88/35 B 42/15 C 98/40 D 114/43 E 118/34 F 17/5 G 92/42 H 182/62 通用 253/140 | |

拿取最多（出现 / 拿取）：“决心” 0/17，“犹疑” 0/15，“观望” 0/15，贵族刺剑 23/10，老近卫军之锋 26/10，“黑夜呢喃” 23/10，镶金骨骰 25/10，显圣吊坠 22/9，海潮的气息 0/8，游戏室管理员权限卡 10/8，制式防暴用具 24/7，破坏协议-压制 17/7
