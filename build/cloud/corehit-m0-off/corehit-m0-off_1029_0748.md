# balance corehit-m0-off 1029_0748

args: `--preset starts --bots expert --seeds 4 --seed0 5 --jobs 4 --tag corehit-m0-off --extra --meta=0 --bal=enemy/bullet_core_hit=0 --out build/cloud/corehit-m0-off`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 12 | 12 | 7 | 129s / 124s / 172s / 90–172s | 124s / 172s | 2.9 / 3.0 | 28% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 158s / 158s / 158s / 158–158s | 158s / 158s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 12 | 11 | 72s | 0.71 | 3 | - | - |
| expert | 圣徒卡门 | 10 | 10 | 66s | 0.76 | 2 | - | - |
| expert | 接潮主教 | 10 | 9 | 54s | 0.15 | 5 | 1.1 | 19% |
| expert | 接潮斥亡体 | 7 | 6 | 52s | 0.15 | 5 | - | - |
| expert | 接潮蔑死体 | 3 | 3 | 71s | 0.16 | 7 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 40s | 0.45 | 2 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 25% | 225 / 218 | 87% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 2 | 13:00 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 2:25 |
| expert | 0 | contact_founder | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:18 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:28 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:18 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:31 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:16 |
| expert | 0 | bullet | 第 2 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | shock_paranoia | 第 3 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 13:00 |
| expert | 0 | contact_slider | 第 1 轮 · 收缩 | 否 | 否 | 1 | 3:12 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |
| expert | 0 | nest | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:13 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:21 |
| expert | 0 | contact_slider | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:30 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:57 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:12 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:21 |
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:56 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 90 / 154 | 84 / 162 | 2 / 9 | 290 / 425 | 27 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 72 / 91 | 37 / 92 | 1 / 6 | 344 / 395 | 25 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 14s / 12s（28/28） | 24 / 56 | 0 | bone/slider/stone ×22；bone/slider ×6 |
| expert | 2 | 24 | 2:45 | 20 | 11s / 10s（23/24） | 44 / 113 | 4 | bone/slider ×20；bone/slider/stone ×4 |
| expert | 3 | 20 | 4:39 | 24 | 11s / 11s（18/20） | 22 / 102 | 2 | bone/offspring/slider/stone ×5；bone/floater/runner/slider ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 4 | 19 | 5:06 | 35 | 30s / 18s（17/19） | 47 / 147 | 4 | bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×5 |
| expert | 5 | 15 | 6:15 | 40 | 31s / 24s（14/15） | 30 / 100 | 1 | bone/reaper/runner/slider/tracer ×6；bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 6 | 11 | 8:12 | 27 | 19s / 14s（11/11） | 29 / 90 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 8 | 9:09 | 22 | 18s / 13s（8/8） | 35 / 61 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 6:27 / 2:25 | 0.0 / - | 8 / 14 / 22 / 16 | - | 33% | 57 | 806 | 余震 38% 饱和复仇 16% 炮击 9% 殉爆 7% | 自身回复 27% 塞雷娅 24% 补给 10% (729 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 4 | 50% | 6:59 / 2:18 | 0.0 / - | 8 / 16 / 22 / 18 | - | 50% | 78 | 1049 | 熔岩弹 28% 余震 14% 火星 7% 饱和复仇 4% | 自身回复 33% 补给 24% 塞雷娅 12% (889 / 0.5) | contact_tracer |
| [expert] skadi | 4 | 25% | 11:27 / 7:16 | 0.0 / - | 8 / 14 / 20 / 25 | 32% | 91% | 98 | 1477 | 大剑 23% 余震 16% 刺剑 6% 狐火 5% | 自身回复 34% 流明 22% 塞雷娅 15% (1489 / 0.0) | contact_tracer |
| [expert] mizuki | 4 | 50% | 12:37 / 11:42 | 0.0 / - | 8 / 14 / 20 / 23 | 38% | 100% | 86 | 1264 | 伞击 13% Mon3tr 11% 触手 9% 言 6% | 水月 43% 自身回复 21% 塞雷娅 8% (1453 / 0.0) | contact_tracer |
| [expert] saria | 4 | 50% | 10:17 / 3:12 | 0.0 / - | 7 / 14 / 20 / 22 | 33% | 75% | 69 | 1274 | 余震 18% 炮击 11% 拳击 9% 钩索 6% | 塞雷娅 58% 自身回复 22% 补给 8% (1357 / 0.2) | contact_tracer |
| [expert] kaltsit | 4 | 0% | 4:12 / 2:30 | 0.0 / - | 8 / 14 / 0 / 12 | - | 16% | 7 | 463 | Mon3tr 41% 刺剑 9% 熔岩弹 5% Mon3tr · 真伤 5% | 凯尔希 39% 自身回复 27% 结构加固 15% (536 / 0.0) | contact_tracer |
| [expert] suzuran | 4 | 0% | 3:51 / 2:56 | 0.0 / - | 8 / 14 / 0 / 12 | - | 8% | 34 | 424 | 狐火 57% 拔刀 3% 锚击 3% 提喻 3% | 自身回复 36% 铃兰 18% 补给 14% (341 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 6:27 / 2:25 | 75% | 75% | 0:57 | 0:49 / 4:16 | 1.2 / 59s | 56.2 | 119 | 4 | 3 | 2 | 75% / 19764 | contact_founder |
| [expert] eyjafjalla | 4 | 50% | 6:59 / 2:18 | 50% | 50% | 1:04 | 0:48 / 2:41 | 1.2 / 37s | 86.2 | 121 | 7 | 14 | 3 | 49% / 15899 | atk_tracer |
| [expert] skadi | 4 | 25% | 11:27 / 7:16 | 100% | 100% | 1:04 | 0:47 / 3:57 | 2.2 / 64s | 119.4 | 130 | 8 | 0 | 4 | 43% / 25030 | shock_paranoia |
| [expert] mizuki | 4 | 50% | 12:37 / 11:42 | 100% | 100% | 1:05 | 0:48 / 4:00 | 2.2 / 98s | 120.9 | 112 | 4 | 8 | 4 | 28% / 10589 | shock_paranoia |
| [expert] saria | 4 | 50% | 10:17 / 3:12 | 75% | 75% | 1:24 | 0:51 / 4:48 | 2.2 / 65s | 140.8 | 126 | 4 | 20 | 4 | 14% / 4931 | contact_slider |
| [expert] kaltsit | 4 | 0% | 4:12 / 2:30 | 50% | 50% | 1:05 | 0:51 / 3:38 | 0.5 / 80s | 52.0 | 152 | 4 | 1 | 2 | 49% / 6727 | atk_reaper |
| [expert] suzuran | 4 | 0% | 3:51 / 2:56 | 50% | 25% | 1:05 | 0:48 / 3:37 | 0.5 / 50s | 44.6 | 118 | 9 | 0 | 1 | 57% / 7180 | atk_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 8.0 | 0.0% | class 10/1 control 2/2 economy 11/5 general 28/10 heal 6/3 melee 1/0 multi 15/7 shield 5/2 summon 1/0 survival 13/2 weak 2/0 | 0 |
| expert | kaltsit | 4 | 3.5 | 1.0% | class 4/2 economy 3/0 general 6/4 heal 7/3 melee 4/2 summon 2/0 survival 9/2 weak 4/1 | 0 |
| expert | mizuki | 4 | 12.0 | 3.8% | class 15/8 control 3/1 economy 8/3 general 32/11 heal 7/3 melee 5/1 multi 2/1 shield 4/3 summon 26/8 survival 27/8 weak 3/1 | 0 |
| expert | saria | 4 | 11.2 | 2.6% | class 14/4 control 2/1 economy 16/4 general 29/13 heal 21/3 melee 2/1 multi 2/0 shield 4/4 summon 4/2 survival 27/13 weak 2/0 | 0 |
| expert | skadi | 4 | 12.0 | 0.0% | class 13/4 control 2/1 economy 8/4 general 33/14 heal 4/0 melee 20/5 multi 2/1 shield 8/4 summon 7/4 survival 29/9 weak 5/2 | 0 |
| expert | suzuran | 4 | 2.5 | 0.0% | class 2/0 control 3/2 economy 4/0 general 4/1 heal 2/2 melee 3/0 multi 1/1 shield 3/1 survival 9/3 weak 1/0 | 0 |
| expert | wisadel | 4 | 6.8 | 0.0% | class 6/0 control 1/1 economy 8/4 general 17/9 heal 1/0 melee 1/1 multi 9/4 shield 2/1 summon 3/2 survival 11/3 weak 4/2 | 0 |
| 合计 | | | | | class 64/19 control 13/8 economy 58/20 general 149/62 heal 48/14 melee 36/10 multi 31/14 shield 26/15 summon 43/16 survival 125/40 weak 21/6 | |

拿取最多（出现 / 拿取）：“多功能”发夹 10/7，银餐叉 8/6，迷梦香精 7/5，古旧钱币 6/5，便携经书 8/4，洁白的舞鞋 9/4，《旧高卢地名源流考》 7/4，三钥协定 4/3，凯旋号角 5/3，“法术杀手” 6/3，教堂救济餐券 5/3，高闪相机 3/3
