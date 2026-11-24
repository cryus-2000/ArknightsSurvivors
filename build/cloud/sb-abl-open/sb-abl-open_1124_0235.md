# balance sb-abl-open 1124_0235

args: `--op sbell2 --bot expert --seeds 32 --seed0 1 --extra=--maxt=1000 --tier=0 --nocache --jobs 8 --tag sb-abl-open --out build/cloud/sb-abl-open`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 22 | 22 | 20 | 131s / 123s / 200s / 71–210s | 123s / 200s | 2.7 / 2.9 | 52% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 46s / 46s / 46s / 46–46s | 46s / 46s | 2.1 / 1.0 | 73% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 20 | 20 | 70s | 0.38 | 4 | - | - |
| expert | 圣徒卡门 | 19 | 16 | 76s | 0.27 | 4 | - | - |
| expert | 接潮主教 | 16 | 15 | 64s | 0.13 | 6 | 1.2 | 13% |
| expert | 接潮斥亡体 | 9 | 9 | 64s | 0.13 | 6 | - | - |
| expert | 接潮蔑死体 | 7 | 7 | 65s | 0.16 | 7 | - | - |
| expert | 圣徒伊比利亚 | 3 | 2 | 62s | 0.27 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 13 | 0.0 / 0.0 / 0.0 / 0 | 17 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 65% | 34% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 117 / 104 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:07 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:18 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:07 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 是 | 1 | 8:54 |
| expert | 0 | shock_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:03 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:44 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 否 | 1 | 9:11 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:19 |
| expert | 0 | corrode | 第 2 轮 · 稳定 | 否 | 是 | 1 | 10:25 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:35 |
| expert | 0 | atk_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:01 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 79 / 103 | 199 / 320 | 1 / 8 | 371 / 456 | 46 / 48 |
| expert | 0 | 27 | 8:00–10:00 | 71 / 103 | 35 / 98 | 0 / 8 | 390 / 456 | 45 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 11 | 758 | 0.0 | 5.9 / 1.2% | 0.3 / 0.3% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 21 | 1128 | 0.6 | 0.6 / 0.0% | 2.4 / 3.5% | 0.0 / 0.0% | 1.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 9s / 9s（32/32） | 17 / 111 | 1 | bone/slider/stone ×17；bone/slider ×15 |
| expert | 2 | 31 | 2:45 | 20 | 8s / 9s（31/31） | 12 / 58 | 0 | bone/slider ×16；bone/slider/stone ×15 |
| expert | 3 | 28 | 5:10 | 24 | 11s / 9s（28/28） | 23 / 72 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×3 |
| expert | 4 | 28 | 6:02 | 38 | 13s / 11s（27/28） | 26 / 105 | 1 | bone/floater/reaper/runner/slider/tracer ×13；bone/offspring/reaper/runner/slider/spitter/tracer ×8；bone/reaper/runner/slider/tracer ×5 |
| expert | 5 | 24 | 7:11 | 39 | 9s / 10s（23/24） | 22 / 151 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×6；bone/reaper/runner/slider/tracer ×5；bone/floater/reaper/runner/slider/tracer ×4 |
| expert | 6 | 22 | 8:22 | 25 | 10s / 8s（22/22） | 16 / 78 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×10；bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |
| expert | 7 | 13 | 9:11 | 22 | 8s / 8s（13/13） | 20 / 83 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] sbell2 | 32 | 65% | 10:30 / 1:44 | 0.0 / - | 8 / 15 / 22 / 25 | 18% | 89% | 60 | 1598 | 积雪 21% 霜涛 13% 铃音吹雪 13% Mon3tr 4% | 自身回复 35% 补给 16% 塞雷娅 11% (1076 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] sbell2 | 32 | 65% | 10:30 / 1:44 | 96% | 93% | 1:04 | 0:51 / 3:05 | 2.2 / 74s | 76.6 | 108 | 10 | 4 | 4 | 50% / 45432 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | sbell2 | 32 | 13.6 | 7.6% | class 131/41 control 159/77 economy 137/39 general 302/126 heal 46/16 melee 54/20 multi 44/13 shield 47/25 summon 50/18 survival 152/55 weak 21/5 | 0 |
| 合计 | | | | | class 131/41 control 159/77 economy 137/39 general 302/126 heal 46/16 melee 54/20 multi 44/13 shield 47/25 summon 50/18 survival 152/55 weak 21/5 | |

拿取最多（出现 / 拿取）：凯旋号角 43/14，安洁莉娜的创想 44/13，“荣耀套餐” 20/13，“小格兰法洛” 18/11，高闪相机 13/11，悬丝傀儡 17/11，《旧高卢地名源流考》 22/11，“多功能”发夹 14/9，洁白的舞鞋 15/7，支援急救包 14/6，蓝卡坞安全衣 6/6，疗养体验卡 9/5
