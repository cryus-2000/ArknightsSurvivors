# balance op-mizuki-solo-1118a 1117_1748

args: `--op mizuki --bot expert --seeds 16 --nocache --jobs 8 --tag op-mizuki-solo-1118a --out build/cloud/op-mizuki-solo-1118a`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 13 | 13 | 13 | 97s / 97s / 120s / 53–133s | 97s / 120s | 5.4 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 1.0 | 39% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 136s / 136s / 136s / 136–136s | 116s / 116s | 0.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 12 | 12 | 63s | 0.57 | 7 | - | - |
| expert | 圣徒卡门 | 9 | 9 | 52s | 0.32 | 6 | - | - |
| expert | 接潮主教 | 8 | 8 | 77s | 0.12 | 7 | 1.0 | 7% |
| expert | 接潮斥亡体 | 5 | 5 | 81s | 0.14 | 8 | - | - |
| expert | 接潮蔑死体 | 3 | 3 | 73s | 0.16 | 6 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 54s | 0.26 | 10 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 87% | 12% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 166 / 141 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:58 |
| expert | 0 | mire | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:15 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 88 / 101 | 115 / 320 | 1 / 8 | 429 / 466 | 46 / 48 |
| expert | 0 | 15 | 8:00–10:00 | 76 / 95 | 31 / 54 | 1 / 5 | 425 / 435 | 44 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 2 | 422 | 0.0 | 0.0 / 0.0% | 1.5 / 3.1% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 14 | 936 | 0.0 | 0.1 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 14s / 11s（16/16） | 11 / 33 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 16 | 2:45 | 20 | 9s / 9s（16/16） | 15 / 51 | 0 | bone/slider ×10；bone/slider/stone ×6 |
| expert | 3 | 16 | 4:49 | 24 | 12s / 12s（16/16） | 16 / 34 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/slider/stone ×3 |
| expert | 4 | 16 | 5:46 | 36 | 13s / 12s（16/16） | 16 / 116 | 1 | bone/reaper/runner/slider/tracer ×7；bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 5 | 14 | 6:35 | 39 | 15s / 14s（14/14） | 20 / 109 | 0 | bone/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 6 | 13 | 8:11 | 27 | 11s / 10s（13/13） | 15 / 102 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 10 | 9:09 | 22 | 10s / 9s（10/10） | 14 / 43 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki | 16 | 87% | 11:17 / 6:15 | 0.0 / - | 8 / 15 / 23 / 27 | 3% | 95% | 88 | 1823 | 触手 18% 伞击 16% Mon3tr 6% 真实 5% | 水月 51% 自身回复 20% 塞雷娅 6% (728 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki | 16 | 87% | 11:17 / 6:15 | 100% | 100% | 1:03 | 0:48 / 2:55 | 2.4 / 67s | 61.4 | 65 | 2 | 4 | 4 | 38% / 37387 | mire |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | mizuki | 16 | 16.3 | 6.6% | class 96/33 control 18/8 economy 62/24 general 200/86 heal 25/8 melee 40/9 multi 21/2 shield 35/16 summon 97/42 survival 82/26 weak 16/7 | 0 |
| 合计 | | | | | class 96/33 control 18/8 economy 62/24 general 200/86 heal 25/8 melee 40/9 multi 21/2 shield 35/16 summon 97/42 survival 82/26 weak 16/7 | |

拿取最多（出现 / 拿取）：《旧高卢地名源流考》 19/8，散轶诗简 20/8，海程 18/7，游戏室管理员权限卡 8/6，扣挠之手 10/5，衍生者终端-超级改 24/5，“多功能”发夹 9/5，几丁质刺刃 6/5，“岁怒” 6/5，锈蚀刀片 14/4，胎生百合 4/4，急救药箱 4/4
