# balance bond2-ab3_irene_lumen_off 1106_1047

args: `--squad irene,lumen --bots expert,normal --seeds 8 --nocache --jobs 8 --tag bond2-ab3_irene_lumen_off --out build/cloud/bond2-ab3/irene_lumen_off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 102s / 96s / 124s / 88–124s | 96s / 124s | 17.4 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 79s / 79s / 79s / 79–79s | 79s / 79s | 7.3 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 5 | 4 | 62s | 0.55 | 8 | - | - |
| expert | 圣徒卡门 | 4 | 3 | 56s | 0.42 | 8 | - | - |
| expert | 接潮主教 | 3 | 3 | 55s | 0.16 | 7 | 1.0 | 26% |
| expert | 接潮斥亡体 | 3 | 3 | 55s | 0.13 | 9 | - | - |
| normal | 塑路者 | 4 | 1 | 41s | 0.57 | 13 | - | - |
| normal | 圣徒卡门 | 3 | 0 | - | 0.15 | 14 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 7 |
| normal | 0 | 8 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 3 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 8 | 50% | 50% | 0% (0) | - |
| normal | 0 | 8 | 0% | 100% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 8 | 0% | 172 / 160 | 99% |
| normal | 0 | 8 | 0% | 245 / 233 | 56% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:22 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:39 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:38 |
| expert | 0 | atk_tracer | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:37 |
| normal | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:24 |
| normal | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:46 |
| normal | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:23 |
| normal | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:23 |
| normal | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:12 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 3:28 |
| normal | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:52 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 8 | 全程 | 85 / 114 | 106 / 250 | 0 / 0 | 311 / 437 | 40 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 74 / 78 | 26 / 40 | 0 / 0 | 387 / 430 | 43 / 48 |
| normal | 0 | 8 | 全程 | 90 / 152 | 35 / 59 | 2 / 7 | 221 / 333 | 33 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 4 | 166 | 0.0 | 0.2 / 0.3% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 4 | 1605 | 0.2 | 10.2 / 0.1% | 4.2 / 4.6% | 0.0 / 0.0% | 0.8 |
| normal | 0 | 失败 | 8 | 146 | 0.0 | 0.1 / 0.2% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 8 | 1:15 | 15 | 12s / 12s（8/8） | 19 / 46 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| expert | 2 | 8 | 2:45 | 20 | 10s / 9s（8/8） | 13 / 27 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| expert | 3 | 6 | 4:39 | 24 | 10s / 9s（6/6） | 34 / 101 | 0 | bone/floater/runner/slider ×3；bone/reaper/runner/slider/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 4 | 6 | 5:01 | 35 | 16s / 14s（6/6） | 32 / 61 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 6 | 6:15 | 40 | 13s / 13s（5/6） | 50 / 136 | 2 | bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×2 |
| expert | 6 | 4 | 8:06 | 25 | 11s / 11s（4/4） | 9 / 21 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |
| expert | 7 | 3 | 9:04 | 21 | 12s / 10s（3/3） | 20 / 47 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |
| normal | 1 | 8 | 1:15 | 15 | 12s / 10s（8/8） | 25 / 61 | 0 | bone/slider ×5；bone/slider/stone ×3 |
| normal | 2 | 8 | 2:45 | 20 | 13s / 12s（8/8） | 54 / 94 | 0 | bone/slider/stone ×5；bone/slider ×3 |
| normal | 3 | 1 | 4:17 | 25 | 24s / 24s（1/1） | 13 / 13 | 1 | bone/offspring/slider/stone ×1 |

### 按机器人汇总

| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（通关率，docs/38 §8.12） | 判定 |
|---|---|---|---|---|---|---|---|---|
| normal | 8 | 0% | 4:14 | 87% | 13.0 | 491 | - | **参考** |
| expert | 8 | 50% | 8:20 | 100% | 21.8 | 1315 | 50–70%（含超时） | **达标** |

### 明细

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] irene+lumen | 8 | 50% | 8:20 / 3:38 | 0.0 / - | 8 / 16 / 23 / 22 | 92% | 75% | 86 | 1315 | 刺剑 15% 裂潮 6% 钩索 5% 剑气 4% | 流明 35% 自身回复 27% 拾取 9% (1060 / 0.0) | contact_tracer |
| [normal] irene+lumen | 8 | 0% | 4:14 / 3:28 | 0.0 / - | 7 / 0 / 0 / 13 | 68% | 0% | 72 | 491 | 刺剑 23% 光弹 12% 狐火 8% 终结技·irene·行刑 5% | 流明 42% 自身回复 41% 凯尔希 7% (411 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] irene+lumen | 8 | 50% | 8:20 / 3:38 | 100% | 75% | 1:12 | 0:46 / 2:34 | 1.6 / 58s | 81.0 | 130 | 4 | 0 | 3 | 34% / 19136 | contact_path |
| [normal] irene+lumen | 8 | 0% | 4:14 / 3:28 | 87% | 0% | 1:18 | 1:54 / - | 0.1 / 41s | 32.1 | 128 | 15 | 0 | 0 | 33% / 4388 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | irene | 8 | 11.2 | 5.1% | class 28/8 control 6/2 economy 26/7 general 81/35 heal 14/3 melee 34/11 multi 3/0 shield 8/5 summon 8/2 survival 33/12 weak 9/5 | 0 |
| normal | irene | 8 | 2.1 | 3.5% | class 4/0 control 1/0 economy 6/5 general 11/4 heal 2/0 melee 9/2 multi 2/1 shield 1/0 summon 5/2 survival 5/3 | 0 |
| 合计 | | | | | class 32/8 control 7/2 economy 32/12 general 92/39 heal 16/3 melee 43/13 multi 5/1 shield 9/5 summon 13/4 survival 38/15 weak 9/5 | |

拿取最多（出现 / 拿取）：漆黑的舞鞋 10/4，“绽放” 4/3，《旧高卢地名源流考》 4/3，皇帝的恩宠 12/3，夜阳花 5/2，赶车夫的长鞭 8/2，“多功能”发夹 3/2，Miss.Christine摸摸券 4/2，折戟-浴血 3/2，老近卫军之锋 2/2，赤金的远征 4/2，地底的灼痕 2/2
