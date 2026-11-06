# balance bond2-pg_nobuff 1106_1101

args: `--squad exusiai,texas --bots expert --seeds 12 --seed0 101 --nocache --jobs 8 --tag bond2-pg_nobuff --out build/cloud/bond2-pg/nobuff --extra=--bal=link/bond_buff_penguin=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 92s / 93s / 99s / 87–99s | 93s / 99s | 26.5 / 3.0 | 3% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 7 | 7 | 50s | 0.55 | 5 | - | - |
| expert | 塑路者 | 7 | 6 | 47s | 0.58 | 6 | - | - |
| expert | 接潮主教 | 6 | 5 | 27s | 0.21 | 4 | 2.0 | 25% |
| expert | 接潮斥亡体 | 3 | 2 | 40s | 0.19 | 5 | - | - |
| expert | 接潮蔑死体 | 3 | 3 | 27s | 0.21 | 4 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 12 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 12 | 41% | 58% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 12 | 0% | 110 / 85 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_founder | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:23 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:03 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:58 |
| expert | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:04 |
| expert | 0 | contact_founder | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:23 |
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:16 |
| expert | 0 | atk_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:14 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 12 | 全程 | 80 / 118 | 157 / 280 | 0 / 4 | 325 / 409 | 30 / 35 |
| expert | 0 | 7 | 8:00–10:00 | 65 / 81 | 26 / 33 | 0 / 0 | 342 / 380 | 30 / 35 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 375 | 0.1 | 0.4 / 1.0% | 1.1 / 3.9% | 0.0 / 0.0% | 0.3 |
| expert | 0 | 胜 | 5 | 1557 | 0.2 | 0.4 / 0.2% | 2.8 / 3.4% | 0.0 / 0.0% | 0.8 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 12 | 1:15 | 15 | 9s / 9s（12/12） | 13 / 33 | 0 | bone/slider ×6；bone/slider/stone ×6 |
| expert | 2 | 12 | 2:45 | 20 | 9s / 9s（12/12） | 12 / 38 | 0 | bone/slider/stone ×6；bone/slider ×6 |
| expert | 3 | 11 | 4:29 | 25 | 9s / 10s（11/11） | 25 / 51 | 0 | bone/slider/stone ×4；bone/floater/runner/slider ×3；bone/offspring/slider/stone ×2 |
| expert | 4 | 11 | 5:03 | 35 | 12s / 12s（10/11） | 66 / 117 | 1 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3 |
| expert | 5 | 9 | 6:15 | 40 | 12s / 12s（8/9） | 33 / 125 | 1 | bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 6 | 7 | 7:51 | 26 | 8s / 8s（7/7） | 11 / 40 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 7 | 9:01 | 22 | 10s / 10s（6/7） | 40 / 119 | 1 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+texas | 12 | 41% | 8:55 / 3:58 | 0.0 / - | 8 / 16 / 24 / 24 | 18% | 86% | 76 | 1484 | 散射 18% 真实 9% 弹匣倾泻 8% 过载模式 7% | 自身回复 45% 补给 20% 拾取 15% (902 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+texas | 12 | 41% | 8:55 / 3:58 | 100% | 91% | 1:18 | 0:48 / 3:57 | 1.9 / 43s | 74.5 | 103 | 8 | 2 | 3 | 25% / 16621 | contact_founder |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 12 | 14.0 | 10.9% | class 55/15 control 15/10 economy 58/21 general 118/43 heal 12/2 melee 21/10 multi 66/27 shield 15/7 summon 17/6 survival 50/20 weak 14/7 | 0 |
| 合计 | | | | | class 55/15 control 15/10 economy 58/21 general 118/43 heal 12/2 melee 21/10 multi 66/27 shield 15/7 summon 17/6 survival 50/20 weak 14/7 | |

拿取最多（出现 / 拿取）：显圣吊坠 14/6，银餐叉 16/6，损坏的左轮弹巢 7/6，穿甲弹 15/5，洁白的舞鞋 14/4，《旧高卢地名源流考》 8/4，皇帝的恩宠 6/3，热水壶 6/3，钝爪-突破 7/3，赶车夫的长鞭 5/3，佣兵保单 4/3，万能钥匙 3/2
