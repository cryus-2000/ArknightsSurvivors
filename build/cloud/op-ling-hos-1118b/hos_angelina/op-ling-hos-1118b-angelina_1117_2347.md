# balance op-ling-hos-1118b-angelina 1117_2347

args: `--squad hoshiguma,angelina --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118b-angelina --out build/cloud/op-ling-hos-1118b/hos_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 10 | 10 | 6 | 122s / 128s / 181s / 59–181s | 128s / 181s | 3.2 / 2.4 | 54% |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 2.8 / 2.0 | 11% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 74s / 74s / 74s / 74–74s | 74s / 74s | 3.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 11 | 10 | 64s | 0.48 | 8 | - | - |
| expert | 接潮主教 | 9 | 9 | 66s | 0.13 | 8 | 1.2 | 14% |
| expert | 接潮蔑死体 | 8 | 8 | 64s | 0.17 | 8 | - | - |
| expert | 塑路者 | 5 | 5 | 64s | 0.49 | 9 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 83s | 0.14 | 11 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 43% | 56% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 18% | 98 / 94 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 4 | 10:49 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 2 | 1:48 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:39 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:19 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:47 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 78 / 110 | 161 / 318 | 1 / 10 | 350 / 454 | 40 / 48 |
| expert | 0 | 12 | 8:00–10:00 | 81 / 104 | 28 / 68 | 1 / 8 | 381 / 454 | 37 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 9 | 343 | 0.1 | 0.1 / 0.1% | 0.4 / 1.4% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 7 | 612 | 0.1 | 0.0 / 0.0% | 1.3 / 3.1% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 11s（15/16） | 17 / 76 | 1 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 13 | 2:45 | 20 | 9s / 9s（13/13） | 6 / 19 | 0 | bone/slider ×7；bone/slider/stone ×6 |
| expert | 3 | 12 | 4:45 | 24 | 12s / 11s（12/12） | 15 / 76 | 0 | bone/floater/runner/slider ×4；bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 4 | 12 | 5:35 | 37 | 19s / 14s（12/12） | 4 / 26 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×3 |
| expert | 5 | 12 | 6:33 | 38 | 18s / 14s（12/12） | 4 / 28 | 0 | bone/reaper/runner/slider/tracer ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 6 | 12 | 8:17 | 27 | 11s / 11s（11/12） | 7 / 45 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/founder/nest/offspring/runner/slider/stone/tracer ×5；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |
| expert | 7 | 7 | 9:15 | 22 | 11s / 11s（7/7） | 28 / 98 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 16 | 43% | 9:19 / 1:44 | 0.0 / - | 8 / 15 / 22 / 23 | 28% | 76% | 60 | 1446 | 举盾反击 13% 秘杖·速充模式 9% 剑气 7% 真实 6% | 自身回复 51% 补给 16% 拾取 14% (519 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 16 | 43% | 9:19 / 1:44 | 81% | 81% | 1:29 | 0:46 / 2:38 | 2.1 / 63s | 43.1 | 68 | 5 | 0 | 5 | 31% / 25266 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 16 | 12.8 | 9.1% | class 50/20 control 17/10 economy 63/25 general 130/46 heal 29/16 melee 75/32 multi 22/8 shield 27/14 summon 24/9 survival 54/17 weak 22/8 | 0 |
| 合计 | | | | | class 50/20 control 17/10 economy 63/25 general 130/46 heal 29/16 melee 75/32 multi 22/8 shield 27/14 summon 24/9 survival 54/17 weak 22/8 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 16/9，锈蚀刀片 15/6，《旧高卢地名源流考》 9/6，老近卫军之锋 6/6，贵族刺剑 14/5，洁白的舞鞋 9/5，血魔的银杯 6/4，食腐者手杖 6/4，“多功能”发夹 7/4，《大静谧》 4/4，皇帝的恩宠 16/3，扣挠之手 3/3
