# balance opb-wisadel-1118a-lead 1117_1756

args: `--op wisadel --bot expert --seeds 16 --nocache --jobs 8 --tag opb-wisadel-1118a-lead --out build/cloud/opb-wisadel-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 10 | 10 | 9 | 90s / 87s / 137s / 49–137s | 87s / 137s | 6.0 / 3.0 | 11% |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 0.0 | 85% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 10 | 45s | 0.52 | 5 | - | - |
| expert | 塑路者 | 9 | 9 | 70s | 0.41 | 4 | - | - |
| expert | 接潮主教 | 6 | 5 | 61s | 0.15 | 7 | 1.0 | 13% |
| expert | 接潮斥亡体 | 3 | 3 | 48s | 0.15 | 8 | - | - |
| expert | 接潮蔑死体 | 3 | 2 | 66s | 0.14 | 8 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 60s | 0.22 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 10 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 56% | 43% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 85 / 84 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:36 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:41 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:16 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:41 |
| expert | 0 | bullet | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:38 |
| expert | 0 | boss_archon | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:10 |
| expert | 0 | shock_founder | 第 4 轮 · 预告 | 否 | 否 | 1 | 9:11 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 79 / 112 | 156 / 250 | 0 / 4 | 364 / 439 | 42 / 48 |
| expert | 0 | 13 | 8:00–10:00 | 71 / 93 | 30 / 64 | 0 / 0 | 374 / 439 | 41 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 454 | 0.0 | 0.4 / 0.3% | 1.9 / 2.0% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 9 | 753 | 0.2 | 0.8 / 0.2% | 1.0 / 2.4% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 10s（16/16） | 17 / 54 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| expert | 2 | 16 | 2:45 | 20 | 8s / 8s（16/16） | 6 / 44 | 0 | bone/slider ×11；bone/slider/stone ×5 |
| expert | 3 | 14 | 4:50 | 24 | 12s / 9s（14/14） | 24 / 88 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×3；bone/offspring/slider/stone ×2 |
| expert | 4 | 14 | 5:40 | 37 | 15s / 12s（14/14） | 10 / 69 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 14 | 6:46 | 39 | 15s / 14s（14/14） | 19 / 101 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 13 | 8:16 | 26 | 10s / 9s（13/13） | 14 / 92 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×3 |
| expert | 7 | 7 | 9:06 | 21 | 12s / 7s（7/7） | 26 / 57 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 16 | 56% | 9:51 / 3:41 | 0.0 / - | 8 / 15 / 23 / 25 | 22% | 89% | 69 | 1634 | 余震 25% 真实 9% 饱和复仇 9% 散射 6% | 自身回复 30% 塞雷娅 15% 补给 15% (747 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 16 | 56% | 9:51 / 3:41 | 100% | 87% | 1:01 | 0:50 / 3:29 | 2.0 / 61s | 53.5 | 79 | 4 | 0 | 3 | 45% / 44403 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | wisadel | 16 | 14.4 | 10.9% | class 55/16 control 12/7 economy 58/30 general 166/69 heal 22/8 melee 25/10 multi 87/25 shield 21/13 summon 27/16 survival 88/31 weak 16/6 | 0 |
| 合计 | | | | | class 55/16 control 12/7 economy 58/30 general 166/69 heal 22/8 melee 25/10 multi 87/25 shield 21/13 summon 27/16 survival 88/31 weak 16/6 | |

拿取最多（出现 / 拿取）：银餐叉 24/8，《旧高卢地名源流考》 10/7，夜阳花 8/6，显圣吊坠 26/6，损坏的左轮弹巢 7/5，生还者合约 7/4，洁白的舞鞋 22/4，皇帝的恩宠 11/4，残破合影 6/4，“多功能”发夹 7/4，散轶诗简 6/4，判官经文布 6/4
