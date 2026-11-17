# balance opb-fiammetta-1118a-lead 1117_1746

args: `--op fiammetta --bot expert --seeds 16 --nocache --jobs 8 --tag opb-fiammetta-1118a-lead --out build/cloud/opb-fiammetta-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 最后的骑士 | knight 1 | 1 | 1 | 68s / 68s / 68s / 68–68s | 68s / 68s | 5.5 / 2.0 | - |
| expert | 偏执泡影 | standard 1 | 1 | 0 | - | - | 5.4 / 2.0 | 50% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 11 | 7 | 57s | 0.58 | 8 | - | - |
| expert | 圣徒卡门 | 5 | 5 | 46s | 0.50 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 46s | 0.38 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 4 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 93% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 18% | 138 / 128 | 91% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:05 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 否 | 1 | 8:13 |
| expert | 0 | contact_founder | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:57 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:26 |
| expert | 0 | atk_stone | 未缩圈 | 否 | 否 | 1 | 2:28 |
| expert | 0 | contact_slider | 未缩圈 | 否 | 否 | 1 | 1:20 |
| expert | 0 | nest | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:20 |
| expert | 0 | contact_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:27 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:45 |
| expert | 0 | bullet | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:14 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:05 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 1:21 |
| expert | 0 | boss_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:25 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:01 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 74 / 127 | 64 / 237 | 4 / 9 | 282 / 449 | 27 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 73 / 93 | 24 / 34 | 4 / 7 | 360 / 409 | 34 / 44 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 15 | 373 | 0.0 | 1.6 / 0.4% | 0.2 / 0.4% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 1 | 968 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 12s / 11s（14/16） | 19 / 92 | 2 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 13 | 2:45 | 20 | 9s / 9s（13/13） | 23 / 80 | 0 | bone/slider ×8；bone/slider/stone ×5 |
| expert | 3 | 9 | 4:43 | 24 | 12s / 10s（9/9） | 34 / 73 | 0 | bone/slider/stone ×3；bone/reaper/runner/slider/tracer ×2；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 4 | 8 | 5:34 | 36 | 13s / 13s（6/8） | 54 / 96 | 1 | bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 5 | 5 | 6:44 | 39 | 18s / 18s（4/5） | 51 / 77 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 6 | 3 | 7:47 | 26 | 8s / 7s（3/3） | 3 / 8 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 8:57 | 22 | 8s / 8s（2/3） | 66 / 107 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] fiammetta | 16 | 6% | 5:46 / 1:20 | 0.0 / - | 8 / 15 / 22 / 17 | 40% | 48% | 50 | 871 | 炮击 18% 散射 14% 你须愧悔 7% 灼痕弹道 5% | 自身回复 41% 拾取 18% 补给 14% (562 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] fiammetta | 16 | 6% | 5:46 / 1:20 | 81% | 62% | 1:07 | 1:00 / 3:39 | 0.9 / 58s | 51.0 | 109 | 14 | 2 | 2 | 37% / 12005 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | fiammetta | 16 | 6.4 | 3.7% | class 28/11 control 8/6 economy 30/13 general 66/25 heal 10/3 melee 16/5 multi 40/17 shield 9/6 summon 14/5 survival 33/10 weak 3/2 | 0 |
| 合计 | | | | | class 28/11 control 8/6 economy 30/13 general 66/25 heal 10/3 melee 16/5 multi 40/17 shield 9/6 summon 14/5 survival 33/10 weak 3/2 | |

拿取最多（出现 / 拿取）：洁白的舞鞋 9/5，穿甲弹 8/4，银餐叉 7/3，显圣吊坠 12/3，人偶之家 4/3，“多功能”发夹 3/3，被撬开的道具箱 3/2，摩根队长佳酿 5/2，损坏的左轮弹巢 4/2，《旧高卢地名源流考》 4/2，恐鱼干 3/2，海潮的气息 0/2
