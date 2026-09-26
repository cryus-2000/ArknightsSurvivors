# balance lr_solo_base 0926_1728

args: `--game game --jobs 4 --out build/cloud/logos-rework-base --op logos --bots expert,normal --seeds 16 --tag lr_solo_base`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 4 | 4 | 4 | 41s / 41s / 46s / 39–46s | 41s / 46s | 13.1 / 2.0 | - |
| expert | 伊祖米克 | deep 4 | 4 | 4 | 48s / 47s / 56s / 44–56s | 30s / 32s | 14.8 / 2.0 | - |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 43s / 43s / 44s / 42–44s | 43s / 44s | 20.0 / 2.0 | 4% |
| expert | 伊莎玛拉 | resolve 2 | 2 | 2 | 38s / 38s / 39s / 38–39s | 38s / 39s | 31.2 / 2.0 | - |
| normal | 偏执泡影 | standard 1 | 1 | 1 | 40s / 40s / 40s / 40–40s | 40s / 40s | 25.6 / 2.0 | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 19 / 16 | 100% |
| normal | 0 | 16 | 0% | 37 / 25 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | mire | 第 4 轮 · 稳定 | 否 | 否 | 1 | 8:58 |
| expert | 0 | contact_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | shock | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:01 |
| expert | 0 | mire | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:11 |
| normal | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 2 | 6:26 |
| normal | 0 | corrode | 第 3 轮 · 收缩 | 否 | 否 | 2 | 6:32 |
| normal | 0 | boss_tracer | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:10 |
| normal | 0 | corrode | 第 4 轮 · 收缩 | 否 | 否 | 1 | 7:59 |
| normal | 0 | boss_burrower | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:35 |
| normal | 0 | boss_burrower | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:30 |
| normal | 0 | contact_tracer | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:15 |
| normal | 0 | corrode | 第 2 轮 · 稳定 | 是 | 否 | 1 | 6:05 |
| normal | 0 | mire | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:05 |
| normal | 0 | mire | 第 3 轮 · 收缩 | 否 | 是 | 1 | 8:03 |
| normal | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:48 |
| normal | 0 | shock | 第 3 轮 · 稳定 | 否 | 否 | 1 | 6:58 |
| normal | 0 | bullet | 第 4 轮 · 预告 | 否 | 否 | 1 | 7:30 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 204 / 264 | 72 / 118 | 1 / 9 | 374 / 466 | 47 / 48 |
| expert | 0 | 15 | 8:00–10:00 | 199 / 258 | 55 / 118 | 1 / 6 | 325 / 399 | 47 / 48 |
| normal | 0 | 16 | 全程 | 283 / 427 | 44 / 134 | 1 / 7 | 347 / 429 | 45 / 48 |
| normal | 0 | 3 | 8:00–10:00 | 204 / 219 | 54 / 78 | 0 / 0 | 291 / 372 | 32 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 26 | 23s / 20s（16/16） | 2 / 7 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 16 | 2:45 | 33 | 10s / 8s（16/16） | 2 / 8 | 0 | bone/slider ×10；bone/slider/stone ×6 |
| expert | 3 | 16 | 4:15 | 41 | 10s / 11s（16/16） | 2 / 7 | 0 | bone/offspring/ripper/slider/stone ×7；bone/floater/ripper/runner/slider ×6；bone/ripper/slider/stone ×3 |
| expert | 4 | 16 | 5:40 | 48 | 9s / 8s（16/16） | 7 / 16 | 0 | bone/floater/ripper/runner/slider/tracer ×8；bone/burrower/ripper/slider ×4；bone/offspring/ripper/slider/spitter ×4 |
| expert | 5 | 15 | 7:31 | 57 | 11s / 10s（15/15） | 11 / 52 | 1 | bone/burrower/offspring/ripper/slider/stone ×7；bone/floater/founder/nest/ripper/runner/slider ×5；burrower/ripper/slider/spitter ×3 |
| expert | 6 | 14 | 8:33 | 62 | 9s / 8s（13/14） | 29 / 163 | 1 | bone/floater/founder/nest/ripper/runner/slider ×5；burrower/ripper/slider/spitter ×4；bone/burrower/offspring/ripper/slider/stone ×2 |
| expert | 7 | 2 | 9:20 | 66 | 10s / 10s（2/2） | 20 / 30 | 0 | burrower/floater/founder/nest/reaper/ripper/runner/slider/tracer ×1；burrower/hulk/ripper/slider/spitter ×1 |
| normal | 1 | 16 | 1:15 | 26 | 10s / 10s（16/16） | 6 / 30 | 0 | bone/slider ×8；bone/slider/stone ×8 |
| normal | 2 | 16 | 2:45 | 33 | 12s / 11s（16/16） | 4 / 23 | 0 | bone/slider/stone ×8；bone/slider ×8 |
| normal | 3 | 16 | 4:23 | 42 | 23s / 21s（16/16） | 10 / 85 | 0 | bone/ripper/slider/stone ×6；bone/floater/ripper/runner/slider ×4；bone/offspring/ripper/slider/stone ×3 |
| normal | 4 | 15 | 5:42 | 48 | 26s / 26s（12/15） | 32 / 155 | 3 | bone/burrower/ripper/slider ×9；bone/offspring/ripper/slider/spitter ×4；bone/floater/ripper/runner/slider/tracer ×2 |
| normal | 5 | 6 | 7:20 | 56 | 19s / 16s（3/6） | 46 / 110 | 3 | burrower/ripper/slider/spitter ×3；bone/burrower/offspring/ripper/slider/stone ×3 |
| normal | 6 | 2 | 8:20 | 61 | 9s / 9s（2/2） | 2 / 4 | 0 | bone/floater/founder/nest/ripper/runner/slider ×1；burrower/ripper/slider/spitter ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 16 | 6% | 7:09 | 100% | 22.2 | 3287 | 30–55% / 7:00–13:00 | **偏难** |
| expert | 16 | 75% | 10:13 | 100% | 32.5 | 6139 | 70–95% / 9:00–13:00 | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos | 16 | 75% | 10:13 / 7:11 | 0.0 / - | 5 / 16 / 26 / 32 | 9% | 100% | 64 | 6139 | 言 21% 提喻 13% 墓志铭 9% 湮灭 8% | 凯尔希 28% 拾取 15% 塞雷娅 14% (360 / 0.6) | bullet |
| [normal] logos | 16 | 6% | 7:09 / 5:30 | 0.0 / - | 7 / 16 / 25 / 22 | 54% | 14% | 47 | 3287 | 言 13% 提喻 9% 大剑 9% 锚击 7% | 拾取 25% 无人机 23% 流明 16% (226 / 0.4) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] logos | 16 | 75% | 10:13 / 7:11 | 100% | 100% | 2:09 | 1:38 / 3:07 | 2.5 / 23s | 18.6 | 52 | 1 | 4 | 16 | 59% / 59836 | mire |
| [normal] logos | 16 | 6% | 7:09 / 5:30 | 100% | 100% | 1:18 | 3:29 / 6:00 | 1.3 / 29s | 32.0 | 80 | 16 | 4 | 0 | 37% / 13787 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | logos | 16 | 27.0 | 2.5% | A 111/33 B 41/19 C 111/45 D 107/23 E 139/52 F 24/14 G 99/32 H 228/65 通用 265/153 | 0 |
| normal | logos | 16 | 12.4 | 0.3% | A 44/13 B 16/6 C 33/14 D 39/15 E 40/12 F 11/4 G 48/15 H 81/33 通用 123/87 | 0 |
| 合计 | | | | | A 155/46 B 57/25 C 144/59 D 146/38 E 179/64 F 35/18 G 147/47 H 309/98 通用 388/240 | |

拿取最多（出现 / 拿取）：“观望” 0/24，“犹疑” 0/22，海潮的气息 0/20，“决心” 0/17，深蓝之心 0/13，镶金骨骰 42/12，演员的首饰盒 28/11，奇渊面具 34/11，洁白的舞鞋 20/11，损坏的左轮弹巢 27/10，舞者手链 32/10，急救药箱 11/10
