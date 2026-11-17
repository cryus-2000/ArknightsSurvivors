# balance op-ling-exu-1118b-angelina 1117_2346

args: `--squad exusiai,angelina --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118b-angelina --out build/cloud/op-ling-exu-1118b/exu_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 5 | 103s / 91s / 147s / 86–147s | 91s / 147s | 3.4 / 2.7 | 42% |
| expert | 最后的骑士 | knight 3 | 3 | 1 | 70s / 70s / 70s / 70–70s | 70s / 70s | 1.0 / 1.0 | 63% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 10 | 8 | 69s | 0.43 | 5 | - | - |
| expert | 接潮主教 | 9 | 9 | 73s | 0.12 | 8 | 1.1 | 19% |
| expert | 塑路者 | 7 | 7 | 55s | 0.54 | 5 | - | - |
| expert | 接潮蔑死体 | 5 | 5 | 54s | 0.16 | 6 | - | - |
| expert | 接潮斥亡体 | 4 | 4 | 96s | 0.09 | 9 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 63s | 0.24 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.1 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 90 / 98 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:19 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 2 | 11:23 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:16 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:38 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:45 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 9:26 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:14 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:46 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 78 / 93 | 172 / 320 | 1 / 10 | 314 / 394 | 28 / 38 |
| expert | 0 | 13 | 8:00–10:00 | 78 / 93 | 37 / 75 | 0 / 5 | 352 / 394 | 29 / 38 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 351 | 0.2 | 1.3 / 0.2% | 2.3 / 7.1% | 0.0 / 0.0% | 0.5 |
| expert | 0 | 胜 | 6 | 575 | 1.0 | 3.2 / 0.0% | 4.0 / 8.7% | 0.0 / 0.0% | 1.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 11s（16/16） | 16 / 51 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 15 | 2:45 | 20 | 8s / 8s（15/15） | 14 / 84 | 0 | bone/slider ×8；bone/slider/stone ×7 |
| expert | 3 | 13 | 4:47 | 24 | 13s / 11s（13/13） | 15 / 51 | 0 | bone/slider/stone ×3；bone/floater/reaper/runner/slider/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 4 | 13 | 5:38 | 37 | 14s / 13s（13/13） | 13 / 74 | 0 | bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 5 | 13 | 6:35 | 39 | 18s / 14s（13/13） | 19 / 91 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/floater/reaper/runner/slider/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| expert | 6 | 13 | 8:26 | 26 | 11s / 11s（11/13） | 29 / 192 | 1 | bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3 |
| expert | 7 | 6 | 9:14 | 22 | 10s / 10s（6/6） | 33 / 172 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 16 | 37% | 9:46 / 2:14 | 0.0 / - | 8 / 15 / 22 / 25 | 27% | 87% | 68 | 1542 | 散射 20% 真实 9% 弹匣倾泻 8% 过载模式 6% | 自身回复 41% 补给 19% 拾取 17% (674 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 16 | 37% | 9:46 / 2:14 | 93% | 87% | 1:21 | 0:46 / 2:55 | 2.2 / 70s | 37.6 | 77 | 8 | 0 | 5 | 23% / 18097 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 16 | 14.1 | 10.8% | class 55/12 control 22/14 economy 57/25 general 164/67 heal 35/12 melee 26/7 multi 99/35 shield 25/13 summon 29/12 survival 70/25 weak 16/4 | 0 |
| 合计 | | | | | class 55/12 control 22/14 economy 57/25 general 164/67 heal 35/12 melee 26/7 multi 99/35 shield 25/13 summon 29/12 survival 70/25 weak 16/4 | |

拿取最多（出现 / 拿取）：穿甲弹 22/9，显圣吊坠 22/8，洁白的舞鞋 21/7，银餐叉 24/6，“多功能”发夹 10/6，损坏的左轮弹巢 10/5，演出用香水 7/5，《旧高卢地名源流考》 9/4，支援补给站 7/4，海潮的气息 0/4，骑士戒律·新编 4/4，高闪相机 4/4
