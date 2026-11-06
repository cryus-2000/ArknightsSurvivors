# balance bond2-ab3_irene_lumen_on 1106_1050

args: `--squad irene,lumen --bots expert,normal --seeds 8 --nocache --jobs 8 --tag bond2-ab3_irene_lumen_on --out build/cloud/bond2-ab3/irene_lumen_on --extra=--bal=link/bond_v2=1`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 5 | 5 | 5 | 116s / 129s / 135s / 91–135s | 129s / 135s | 7.2 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 5 | 4 | 76s | 0.41 | 6 | - | - |
| expert | 塑路者 | 4 | 4 | 78s | 0.49 | 8 | - | - |
| expert | 接潮主教 | 2 | 2 | 75s | 0.11 | 9 | 1.0 | 16% |
| expert | 圣徒伊比利亚 | 2 | 2 | 66s | 0.26 | 10 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 88s | 0.09 | 12 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 62s | 0.18 | 9 | - | - |
| normal | 塑路者 | 6 | 2 | 70s | 0.47 | 14 | - | - |
| normal | 圣徒卡门 | 2 | 1 | 71s | 0.43 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 14 | 0.0 / 0.0 / 0.0 / 0 | 16 |
| normal | 0 | 8 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 2 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 8 | 62% | 37% | 0% (0) | - |
| normal | 0 | 8 | 0% | 100% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 178 / 176 | 98% |
| normal | 0 | 8 | 0% | 201 / 187 | 78% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:02 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:03 |
| expert | 0 | atk_nest | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:05 |
| normal | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:21 |
| normal | 0 | contact_bone | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:48 |
| normal | 0 | mire | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:05 |
| normal | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:01 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:14 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:34 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 100 / 133 | 177 / 320 | 0 / 0 | 328 / 445 | 38 / 48 |
| expert | 0 | 5 | 8:00–10:00 | 80 / 89 | 35 / 60 | 0 / 0 | 381 / 430 | 36 / 47 |
| normal | 0 | 8 | 全程 | 84 / 134 | 40 / 60 | 0 / 0 | 225 / 309 | 29 / 38 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 3 | 81 | 0.0 | 0.3 / 0.1% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 5 | 1708 | 0.6 | 0.2 / 0.1% | 2.0 / 2.1% | 0.0 / 0.0% | 0.8 |
| normal | 0 | 失败 | 8 | 165 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 15 | 11s / 11s（8/8） | 13 / 25 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| expert | 2 | 8 | 2:45 | 20 | 10s / 10s（8/8） | 15 / 50 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| expert | 3 | 7 | 5:03 | 24 | 12s / 11s（7/7） | 21 / 121 | 2 | bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×1；bone/floater/runner/slider ×1 |
| expert | 4 | 7 | 5:09 | 35 | 18s / 16s（4/7） | 67 / 126 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 5 | 5 | 6:15 | 40 | 20s / 20s（4/5） | 66 / 110 | 0 | bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 6 | 5 | 8:18 | 26 | 18s / 13s（5/5） | 18 / 34 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 3 | 9:18 | 22 | 10s / 10s（3/3） | 23 / 43 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |
| normal | 1 | 8 | 1:15 | 15 | 11s / 11s（8/8） | 25 / 77 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| normal | 2 | 8 | 2:45 | 20 | 14s / 11s（8/8） | 28 / 121 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| normal | 3 | 3 | 4:50 | 24 | 13s / 13s（2/3） | 11 / 24 | 3 | bone/offspring/slider/stone ×1；bone/reaper/runner/slider/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| normal | 4 | 2 | 5:05 | 34 | -（0/2） | 70 / 125 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×2 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（通关率，docs/38 §8.12） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 0% | 4:28 | 100% | 13.5 | 524 | - | **参考** |
| expert | 8 | 62% | 9:21 | 100% | 22.9 | 1356 | 50–70%（含超时） | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] irene+lumen | 8 | 62% | 9:21 / 5:02 | 0.0 / - | 8 / 15 / 22 / 23 | 27% | 75% | 88 | 1356 | 刺剑 14% 剑气 6% 裂潮 5% 手炮轰击 5% | 流明 37% 自身回复 26% 补给 11% (1435 / 0.0) | bullet |
| [normal] irene+lumen | 8 | 0% | 4:28 / 3:34 | 0.0 / - | 7 / 14 / 0 / 14 | 68% | 4% | 71 | 524 | 刺剑 24% 光弹 11% 真实 6% 技能连携·灼烧光点·lumen 6% | 流明 40% 自身回复 38% 歌蕾蒂娅 5% (432 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] irene+lumen | 8 | 62% | 9:21 / 5:02 | 100% | 100% | 1:12 | 0:46 / 2:46 | 1.8 / 76s | 90.4 | 151 | 8 | 0 | 3 | 37% / 20570 | boss_carmen |
| [normal] irene+lumen | 8 | 0% | 4:28 / 3:34 | 100% | 25% | 1:03 | 1:46 / 2:46 | 0.4 / 70s | 34.3 | 124 | 24 | 0 | 0 | 36% / 5522 | contact_path |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | irene | 8 | 11.0 | 3.8% | class 26/8 control 6/3 economy 37/14 general 61/30 heal 4/1 melee 45/11 multi 7/1 shield 8/4 summon 6/3 survival 35/10 weak 5/3 | 0 |
| normal | irene | 8 | 3.2 | 6.5% | class 5/1 control 1/0 economy 13/8 general 12/5 heal 4/0 melee 17/6 multi 1/0 summon 1/1 survival 12/5 weak 1/0 | 0 |
| 合计 | | | | | class 31/9 control 7/3 economy 50/22 general 73/35 heal 8/1 melee 62/17 multi 8/1 shield 8/4 summon 7/4 survival 47/15 weak 6/3 | |

拿取最多（出现 / 拿取）：贵族刺剑 14/7，三钥协定 7/5，林间夜话 4/4，赶车夫的长鞭 8/4，便携经书 4/4，医者-自医 4/3，迷梦香精 3/3，难闻的止血剂 3/2，锈蚀刀片 16/2，支援补给站 2/2，地底的灼痕 5/2，老近卫军之锋 2/2
