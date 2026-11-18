# balance op-ling-s64-peers-1118n-l-suzuran 1118_0711

args: `--op suzuran --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-l-suzuran --out build/cloud/op-ling-s64-peers-1118n/lead_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 6 | 87s / 79s / 135s / 66–135s | 80s / 135s | 6.7 / 2.3 | 71% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 44s / 44s / 44s / 44–44s | 44s / 44s | 4.9 / 1.3 | 73% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 17 | 14 | 66s | 0.49 | 9 | - | - |
| expert | 塑路者 | 16 | 15 | 43s | 0.64 | 7 | - | - |
| expert | 接潮主教 | 9 | 8 | 46s | 0.15 | 9 | 1.3 | 21% |
| expert | 接潮斥亡体 | 7 | 6 | 54s | 0.14 | 11 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 29s | 0.42 | 10 | - | - |
| expert | 接潮蔑死体 | 2 | 2 | 28s | 0.24 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 7 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 25% | 75% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 134 / 134 | 96% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 否 | 2 | 6:07 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 2 | 5:26 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:19 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:00 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:53 |
| expert | 0 | mire | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:03 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:06 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:25 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:04 |
| expert | 0 | contact_tracer | 未缩圈 | 否 | 否 | 1 | 1:59 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:07 |
| expert | 0 | mire | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:24 |
| expert | 0 | dark | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:05 |
| expert | 0 | contact_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:31 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:02 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:32 |
| expert | 0 | contact_reaper | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:06 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:08 |
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:55 |
| expert | 0 | blast_runner | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:07 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:52 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 88 / 126 | 107 / 280 | 8 / 10 | 378 / 469 | 44 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 78 / 118 | 24 / 43 | 5 / 9 | 399 / 459 | 43 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 24 | 400 | 0.0 | 7.5 / 1.3% | 0.3 / 0.4% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 8 | 913 | 0.2 | 0.0 / 0.0% | 2.2 / 4.4% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 12s / 11s（32/32） | 18 / 69 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 2 | 31 | 2:45 | 20 | 10s / 10s（31/31） | 17 / 79 | 0 | bone/slider ×19；bone/slider/stone ×12 |
| expert | 3 | 27 | 4:35 | 24 | 18s / 12s（26/27） | 32 / 122 | 3 | bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/floater/runner/slider ×7；bone/slider/stone ×5 |
| expert | 4 | 22 | 5:25 | 36 | 18s / 17s（19/22） | 37 / 114 | 3 | bone/floater/reaper/runner/slider/tracer ×10；bone/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 5 | 17 | 6:24 | 39 | 19s / 13s（14/17） | 34 / 165 | 3 | bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×4；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 13 | 7:59 | 26 | 9s / 9s（12/13） | 17 / 72 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×4 |
| expert | 7 | 12 | 9:02 | 22 | 11s / 12s（11/12） | 50 / 184 | 1 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×4；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 32 | 25% | 7:32 / 1:59 | 0.0 / - | 8 / 15 / 23 / 21 | 37% | 66% | 49 | 1205 | 狐火 20% 狐火点点 6% 终结技·suzuran·斩痕 4% Mon3tr 4% | 自身回复 28% 补给 14% 铃兰 13% (714 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] suzuran | 32 | 25% | 7:32 / 1:59 | 96% | 81% | 1:02 | 0:50 / 3:36 | 1.5 / 52s | 49.9 | 111 | 6 | 3 | 3 | 27% / 12041 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | suzuran | 32 | 9.3 | 5.1% | class 88/35 control 94/46 economy 92/29 general 186/91 heal 24/10 melee 41/13 multi 26/11 shield 23/18 summon 30/16 survival 96/25 weak 12/4 | 0 |
| 合计 | | | | | class 88/35 control 94/46 economy 92/29 general 186/91 heal 24/10 melee 41/13 multi 26/11 shield 23/18 summon 30/16 survival 96/25 weak 12/4 | |

拿取最多（出现 / 拿取）：凯旋号角 29/13，安洁莉娜的创想 31/11，堡垒协议-方阵 9/10，《旧高卢地名源流考》 11/10，高闪相机 13/8，疗养体验卡 8/6，“多功能”发夹 7/6，猎人的口粮 9/5，支援急救包 9/5，海潮的气息 0/5，“小格兰法洛” 8/5，衍生者终端-超级改 10/5
