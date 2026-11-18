# balance op-ling-exu-1118c-skalter 1118_0031

args: `--squad exusiai,skalter --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118c-skalter --out build/cloud/op-ling-exu-1118c/exu_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 14 | 14 | 12 | 57s / 58s / 73s / 38–73s | 58s / 73s | 12.6 / 3.0 | 38% |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 0.0 | 5% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 20 | 17 | 43s | 0.56 | 4 | - | - |
| expert | 塑路者 | 19 | 17 | 45s | 0.58 | 5 | - | - |
| expert | 接潮主教 | 10 | 10 | 40s | 0.18 | 6 | 1.2 | 29% |
| expert | 圣徒伊比利亚 | 5 | 5 | 38s | 0.33 | 7 | - | - |
| expert | 接潮蔑死体 | 5 | 5 | 30s | 0.22 | 7 | - | - |
| expert | 接潮斥亡体 | 5 | 5 | 46s | 0.19 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 99 / 92 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 3 | 7:57 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 3:53 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 否 | 1 | 7:39 |
| expert | 0 | contact_founder | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:13 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:50 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:12 |
| expert | 0 | atk_reaper | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:23 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:53 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:41 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:01 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:28 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:59 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:46 |
| expert | 0 | boss_knight_boss | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:37 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:18 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 73 / 97 | 133 / 250 | 0 / 10 | 315 / 430 | 29 / 48 |
| expert | 0 | 19 | 8:00–10:00 | 65 / 73 | 21 / 55 | 0 / 5 | 363 / 429 | 28 / 46 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 20 | 339 | 0.0 | 4.0 / 2.0% | 0.7 / 1.3% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 12 | 530 | 0.0 | 2.3 / 0.3% | 2.0 / 4.4% | 0.0 / 0.0% | 0.6 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 17 / 42 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 14 / 71 | 0 | bone/slider ×19；bone/slider/stone ×13 |
| expert | 3 | 27 | 4:24 | 25 | 10s / 9s（27/27） | 16 / 90 | 0 | bone/offspring/slider/stone ×10；bone/slider/stone ×9；bone/floater/runner/slider ×6 |
| expert | 4 | 26 | 5:14 | 36 | 10s / 11s（25/26） | 31 / 128 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/floater/reaper/runner/slider/tracer ×9；bone/reaper/runner/slider/tracer ×6 |
| expert | 5 | 24 | 6:18 | 39 | 12s / 12s（22/24） | 30 / 167 | 2 | bone/floater/reaper/runner/slider/tracer ×9；bone/reaper/runner/slider/tracer ×8；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 6 | 21 | 7:52 | 27 | 8s / 7s（19/21） | 34 / 154 | 3 | bone/founder/nest/offspring/runner/slider/stone/tracer ×8；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×6 |
| expert | 7 | 16 | 9:00 | 22 | 8s / 8s（14/16） | 32 / 110 | 2 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×7；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 32 | 37% | 8:27 / 3:37 | 0.0 / - | 8 / 16 / 24 / 23 | 17% | 84% | 51 | 1463 | 散射 25% 弹匣倾泻 11% 真实 8% 过载模式 7% | 自身回复 31% 浊心斯卡蒂 24% 补给 16% (604 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 32 | 37% | 8:27 / 3:37 | 100% | 84% | 1:18 | 0:49 / 2:59 | 1.8 / 41s | 39.3 | 80 | 5 | 0 | 3 | 29% / 24001 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 13.1 | 9.7% | class 119/42 control 23/13 economy 127/43 general 280/121 heal 29/11 melee 53/18 multi 173/71 shield 33/21 summon 39/19 survival 109/45 weak 28/14 | 0 |
| 合计 | | | | | class 119/42 control 23/13 economy 127/43 general 280/121 heal 29/11 melee 53/18 multi 173/71 shield 33/21 summon 39/19 survival 109/45 weak 28/14 | |

拿取最多（出现 / 拿取）：银餐叉 44/17，损坏的左轮弹巢 20/16，显圣吊坠 46/15，洁白的舞鞋 27/12，穿甲弹 36/11，“多功能”发夹 14/9，《旧高卢地名源流考》 12/9，锈刃-可视静谧 12/7，远程协议-遥击 12/6，支援轰隆隆 10/5，赶车夫的长鞭 13/5，神音海螺 10/5
