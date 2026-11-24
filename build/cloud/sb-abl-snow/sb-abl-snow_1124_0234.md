# balance sb-abl-snow 1124_0234

args: `--op sbell2 --bot expert --seeds 32 --seed0 1 --extra=--maxt=1000 --tier=0 --nocache --jobs 8 --tag sb-abl-snow --out build/cloud/sb-abl-snow`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 19 | 19 | 15 | 138s / 120s / 215s / 69–237s | 120s / 215s | 2.2 / 3.0 | 38% |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 3.0 / 2.0 | 27% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 57s / 57s / 57s / 57–57s | 57s / 57s | 2.6 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 19 | 19 | 85s | 0.44 | 5 | - | - |
| expert | 圣徒卡门 | 17 | 11 | 45s | 0.26 | 5 | - | - |
| expert | 接潮主教 | 13 | 12 | 60s | 0.14 | 6 | 1.0 | 11% |
| expert | 接潮蔑死体 | 7 | 6 | 68s | 0.13 | 8 | - | - |
| expert | 接潮斥亡体 | 6 | 6 | 52s | 0.13 | 5 | - | - |
| expert | 圣徒伊比利亚 | 5 | 5 | 73s | 0.21 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 12 | 0.0 / 0.0 / 0.0 / 1 | 16 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 50% | 50% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 166 / 160 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 6 | 5:19 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:36 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:25 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:37 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 11:58 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:01 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:21 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:18 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:24 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:49 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 82 / 113 | 191 / 319 | 0 / 7 | 374 / 447 | 46 / 48 |
| expert | 0 | 22 | 8:00–10:00 | 77 / 113 | 32 / 60 | 0 / 0 | 403 / 447 | 47 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 16 | 416 | 0.0 | 2.6 / 0.5% | 0.6 / 1.0% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 16 | 1364 | 0.6 | 2.6 / 0.3% | 1.9 / 1.7% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 16s / 15s（32/32） | 15 / 83 | 0 | bone/slider/stone ×18；bone/slider ×14 |
| expert | 2 | 31 | 2:45 | 20 | 10s / 10s（31/31） | 16 / 77 | 0 | bone/slider ×17；bone/slider/stone ×14 |
| expert | 3 | 25 | 5:06 | 24 | 9s / 9s（25/25） | 25 / 131 | 1 | bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×7；bone/offspring/slider/stone ×5 |
| expert | 4 | 24 | 6:02 | 37 | 11s / 11s（23/24） | 29 / 117 | 1 | bone/floater/reaper/runner/slider/tracer ×10；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×5 |
| expert | 5 | 22 | 7:19 | 39 | 13s / 12s（22/22） | 18 / 63 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 19 | 8:27 | 25 | 10s / 9s（19/19） | 27 / 136 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 9 | 9:04 | 21 | 7s / 6s（9/9） | 15 / 73 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] sbell2 | 32 | 50% | 9:46 / 2:37 | 0.0 / - | 7 / 15 / 23 / 24 | 27% | 80% | 58 | 1459 | 开阵 19% 铃音吹雪 15% 霜涛 11% Mon3tr 6% | 自身回复 38% 补给 18% 拾取 11% (1031 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] sbell2 | 32 | 50% | 9:46 / 2:37 | 96% | 90% | 1:26 | 1:14 / 3:21 | 1.8 / 72s | 71.9 | 116 | 15 | 3 | 4 | 49% / 39732 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | sbell2 | 32 | 11.5 | 4.9% | class 129/41 control 119/37 economy 96/39 general 280/114 heal 26/8 melee 42/11 multi 52/14 shield 56/27 summon 48/20 survival 116/46 weak 20/10 | 0 |
| 合计 | | | | | class 129/41 control 119/37 economy 96/39 general 280/114 heal 26/8 melee 42/11 multi 52/14 shield 56/27 summon 48/20 survival 116/46 weak 20/10 | |

拿取最多（出现 / 拿取）：“多功能”发夹 18/11，安洁莉娜的创想 40/7，“小格兰法洛” 9/7，《旧高卢地名源流考》 18/7，凯旋号角 42/6，高闪相机 6/6，舞者手链 8/5，支援急救包 12/5，“荒诞命运” 9/5，堡垒协议-方阵 11/5，药枚 12/5，《光耀卡西米尔》 6/5
