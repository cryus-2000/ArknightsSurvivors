# balance op-ling-s64-peers-1118n-e-angelina 1118_0724

args: `--squad exusiai,angelina --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-e-angelina --out build/cloud/op-ling-s64-peers-1118n/exu_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 16 | 16 | 10 | 102s / 81s / 171s / 56–171s | 81s / 171s | 5.1 / 2.9 | 39% |
| expert | 最后的骑士 | knight 4 | 4 | 1 | 98s / 98s / 98s / 98–98s | 98s / 98s | 1.9 / 1.5 | 47% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 73s / 73s / 73s / 73–73s | 53s / 53s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 19 | 14 | 54s | 0.45 | 5 | - | - |
| expert | 塑路者 | 16 | 14 | 67s | 0.48 | 5 | - | - |
| expert | 接潮主教 | 14 | 12 | 66s | 0.11 | 8 | 1.3 | 27% |
| expert | 接潮蔑死体 | 8 | 8 | 78s | 0.15 | 9 | - | - |
| expert | 接潮斥亡体 | 6 | 5 | 74s | 0.11 | 8 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 61s | 0.24 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 10 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 79 / 81 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 4 | 4:32 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 11:10 |
| expert | 0 | contact_slider | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:21 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:03 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:48 |
| expert | 0 | boss_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:25 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:19 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:17 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:09 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:35 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:13 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:32 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:23 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:28 |
| expert | 0 | boss_knight_boss | 第 3 轮 · 稳定 | 否 | 是 | 1 | 12:04 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 78 / 116 | 154 / 319 | 1 / 9 | 302 / 454 | 29 / 48 |
| expert | 0 | 22 | 8:00–10:00 | 71 / 93 | 41 / 112 | 1 / 7 | 338 / 443 | 29 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 20 | 369 | 0.1 | 0.2 / 0.1% | 1.6 / 4.6% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 12 | 545 | 0.4 | 1.9 / 0.2% | 2.7 / 5.3% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 31 | 1:15 | 15 | 10s / 10s（31/31） | 12 / 51 | 0 | bone/slider ×17；bone/slider/stone ×14 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 14 / 61 | 0 | bone/slider/stone ×17；bone/slider ×14 |
| expert | 3 | 24 | 4:52 | 24 | 14s / 13s（24/24） | 13 / 76 | 0 | bone/offspring/slider/stone ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×5 |
| expert | 4 | 23 | 5:43 | 37 | 17s / 12s（22/23） | 32 / 118 | 1 | bone/floater/reaper/runner/slider/tracer ×9；bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 5 | 20 | 6:40 | 38 | 19s / 15s（20/20） | 15 / 86 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 6 | 17 | 8:17 | 27 | 12s / 11s（17/17） | 9 / 59 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |
| expert | 7 | 11 | 9:10 | 22 | 12s / 12s（11/11） | 15 / 102 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 32 | 37% | 9:05 / 1:13 | 0.0 / - | 8 / 15 / 23 / 23 | 33% | 78% | 62 | 1381 | 散射 20% 弹匣倾泻 9% 真实 6% 过载模式 5% | 自身回复 41% 补给 19% 拾取 14% (619 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 32 | 37% | 9:05 / 1:13 | 96% | 78% | 1:19 | 0:48 / 3:02 | 1.8 / 74s | 37.0 | 75 | 11 | 2 | 4 | 25% / 16106 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 12.4 | 7.2% | class 85/29 control 34/16 economy 102/47 general 294/130 heal 35/11 melee 74/29 multi 142/56 shield 54/27 summon 47/17 survival 106/27 weak 24/9 | 0 |
| 合计 | | | | | class 85/29 control 34/16 economy 102/47 general 294/130 heal 35/11 melee 74/29 multi 142/56 shield 54/27 summon 47/17 survival 106/27 weak 24/9 | |

拿取最多（出现 / 拿取）：银餐叉 35/13，损坏的左轮弹巢 17/12，显圣吊坠 42/11，洁白的舞鞋 21/10，《旧高卢地名源流考》 19/10，穿甲弹 27/10，药枚 15/8，“多功能”发夹 12/8，贵族刺剑 17/6，古旧乐谱残章 10/6，支援急救包 12/6，老近卫军之锋 9/6
