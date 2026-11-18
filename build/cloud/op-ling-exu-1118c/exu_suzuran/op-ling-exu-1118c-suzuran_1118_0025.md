# balance op-ling-exu-1118c-suzuran 1118_0025

args: `--squad exusiai,suzuran --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118c-suzuran --out build/cloud/op-ling-exu-1118c/exu_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 12 | 12 | 7 | 69s / 65s / 100s / 50–100s | 65s / 100s | 9.4 / 3.0 | 15% |
| expert | 最后的骑士 | knight 3 | 3 | 0 | - | - | 4.0 / 1.3 | 55% |
| expert | 伊莎玛拉 | deep 2 | 2 | 0 | - | - | 3.8 / 2.0 | 9% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 22 | 20 | 35s | 0.58 | 4 | - | - |
| expert | 塑路者 | 20 | 20 | 36s | 0.65 | 5 | - | - |
| expert | 接潮主教 | 11 | 10 | 31s | 0.22 | 7 | 1.0 | 15% |
| expert | 接潮斥亡体 | 7 | 7 | 34s | 0.19 | 7 | - | - |
| expert | 接潮蔑死体 | 4 | 3 | 22s | 0.22 | 6 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 42s | 0.32 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 21% | 78% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 59 / 51 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 3 | 7:35 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 3 | 9:11 |
| expert | 0 | boss_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 3 | 10:26 |
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 2 | 10:38 |
| expert | 0 | boss_ishar | 第 5 轮 · 稳定 | 否 | 是 | 2 | 11:04 |
| expert | 0 | contact_slider | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:21 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:45 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:15 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:43 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:36 |
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:58 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:31 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:06 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:42 |
| expert | 0 | shock_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:31 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:10 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:52 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 81 / 113 | 136 / 250 | 9 / 12 | 325 / 385 | 31 / 48 |
| expert | 0 | 23 | 8:00–10:00 | 70 / 89 | 22 / 40 | 6 / 10 | 343 / 385 | 31 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 25 | 436 | 0.2 | 2.3 / 1.1% | 1.4 / 3.9% | 0.0 / 0.0% | 0.4 |
| expert | 0 | 胜 | 7 | 620 | 0.4 | 0.0 / 0.0% | 2.1 / 4.6% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 9 / 37 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 9 / 38 | 0 | bone/slider ×19；bone/slider/stone ×13 |
| expert | 3 | 30 | 4:15 | 25 | 10s / 10s（30/30） | 13 / 124 | 1 | bone/floater/runner/slider ×16；bone/slider/stone ×7；bone/offspring/slider/stone ×6 |
| expert | 4 | 28 | 5:05 | 35 | 13s / 14s（28/28） | 18 / 108 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×9；bone/floater/reaper/runner/slider/tracer ×8 |
| expert | 5 | 27 | 6:15 | 39 | 14s / 13s（25/27） | 18 / 65 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×6 |
| expert | 6 | 23 | 7:48 | 26 | 11s / 10s（22/23） | 25 / 160 | 2 | bone/floater/founder/nest/runner/slider/stone/tracer ×11；bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×5 |
| expert | 7 | 20 | 8:56 | 22 | 10s / 10s（18/20） | 43 / 170 | 3 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×10；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×8；bone/floater/offspring/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+suzuran | 32 | 21% | 9:03 / 3:36 | 0.0 / - | 8 / 16 / 23 / 25 | 17% | 86% | 68 | 1608 | 散射 20% 狐火 10% 弹匣倾泻 9% 真实 8% | 自身回复 37% 补给 18% 拾取 14% (525 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+suzuran | 32 | 21% | 9:03 / 3:36 | 100% | 90% | 1:13 | 0:48 / 3:02 | 2.0 / 35s | 43.1 | 66 | 4 | 0 | 3 | 24% / 22112 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 14.1 | 9.8% | class 107/31 control 36/13 economy 133/53 general 345/157 heal 30/11 melee 44/10 multi 160/74 shield 44/29 summon 37/17 survival 135/44 weak 24/13 | 0 |
| 合计 | | | | | class 107/31 control 36/13 economy 133/53 general 345/157 heal 30/11 melee 44/10 multi 160/74 shield 44/29 summon 37/17 survival 135/44 weak 24/13 | |

拿取最多（出现 / 拿取）：穿甲弹 39/17，洁白的舞鞋 28/17，显圣吊坠 40/14，银餐叉 40/14，损坏的左轮弹巢 13/12，《旧高卢地名源流考》 14/11，“多功能”发夹 16/10，海潮的气息 0/7，主教的研究 0/7，药枚 10/7，残破合影 7/6，古旧钱币 12/6
