# balance op-ling-lead-1118c-angelina 1118_0020

args: `--op angelina --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118c-angelina --out build/cloud/op-ling-lead-1118c/lead_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 17 | 17 | 13 | 132s / 124s / 200s / 64–243s | 124s / 200s | 2.8 / 2.9 | 40% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 155s / 155s / 155s / 155–155s | 155s / 155s | 0.0 / 1.0 | 84% |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 1.1 / 1.0 | 64% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 237s / 237s / 237s / 237–237s | 217s / 217s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 25 | 19 | 64s | 0.32 | 8 | - | - |
| expert | 塑路者 | 18 | 16 | 84s | 0.36 | 8 | - | - |
| expert | 接潮主教 | 8 | 6 | 93s | 0.11 | 10 | 1.5 | 14% |
| expert | 接潮蔑死体 | 6 | 6 | 96s | 0.16 | 10 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 114s | 0.13 | 10 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 61s | 0.28 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 46% | 53% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 6% | 123 / 118 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 5 | 4:12 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:41 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:16 |
| expert | 0 | boss_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:23 |
| expert | 0 | boss_ishar | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:20 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:49 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 9:22 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:51 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:46 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:54 |
| expert | 0 | shock_paranoia | 第 2 轮 · 稳定 | 否 | 是 | 1 | 11:12 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:27 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 81 / 120 | 160 / 319 | 1 / 9 | 361 / 456 | 38 / 48 |
| expert | 0 | 22 | 8:00–10:00 | 77 / 120 | 37 / 117 | 1 / 9 | 391 / 442 | 34 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 17 | 320 | 0.2 | 0.1 / 0.0% | 1.8 / 5.9% | 0.0 / 0.0% | 0.5 |
| expert | 0 | 胜 | 15 | 720 | 0.7 | 1.7 / 0.1% | 6.1 / 10.3% | 0.0 / 0.0% | 1.6 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 14s / 14s（32/32） | 11 / 50 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 2 | 31 | 2:45 | 20 | 10s / 10s（30/31） | 12 / 71 | 1 | bone/slider ×19；bone/slider/stone ×12 |
| expert | 3 | 22 | 5:14 | 24 | 11s / 11s（21/22） | 14 / 66 | 0 | bone/floater/reaper/runner/slider/tracer ×8；bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×4 |
| expert | 4 | 22 | 6:07 | 38 | 22s / 16s（22/22） | 10 / 61 | 0 | bone/reaper/runner/slider/tracer ×8；bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 5 | 21 | 7:27 | 38 | 21s / 14s（20/21） | 23 / 123 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 6 | 16 | 8:22 | 25 | 14s / 11s（16/16） | 14 / 97 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3 |
| expert | 7 | 8 | 9:04 | 22 | 12s / 12s（8/8） | 16 / 60 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 32 | 46% | 9:20 / 1:49 | 0.0 / - | 7 / 15 / 22 / 23 | 38% | 74% | 64 | 1344 | 双重引力 11% 秘杖·速充模式 8% 重力弹 4% 剑气 4% | 自身回复 34% 补给 16% 塞雷娅 12% (743 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 32 | 46% | 9:20 / 1:49 | 93% | 75% | 1:07 | 0:52 / 3:06 | 1.6 / 80s | 40.3 | 85 | 7 | 2 | 6 | 26% / 14414 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | angelina | 32 | 10.7 | 6.7% | class 82/20 control 131/58 economy 100/32 general 296/120 heal 41/16 melee 50/14 multi 35/9 shield 29/16 summon 42/19 survival 110/34 weak 22/4 | 0 |
| 合计 | | | | | class 82/20 control 131/58 economy 100/32 general 296/120 heal 41/16 melee 50/14 multi 35/9 shield 29/16 summon 42/19 survival 110/34 weak 22/4 | |

拿取最多（出现 / 拿取）：凯旋号角 38/12，安洁莉娜的创想 42/11，“小格兰法洛” 16/11，“多功能”发夹 16/9，高闪相机 12/8，悬丝傀儡 11/7，Miss.Christine摸摸券 11/6，“荣耀套餐” 9/6，人偶之家 14/6，显圣吊坠 13/5，《旧高卢地名源流考》 7/5，摩根队长佳酿 14/4
