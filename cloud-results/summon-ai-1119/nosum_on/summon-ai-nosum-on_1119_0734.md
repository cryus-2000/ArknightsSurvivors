# balance summon-ai-nosum-on 1119_0734

args: `--squad texas,exusiai,hoshiguma --bot expert --seeds 16 --seed0 17 --jobs 4 --nocache --extra=--maxt=1000 --tier=0 --norecruit --tag summon-ai-nosum-on --out build/ab/summon-ai-1119/nosum_on`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 13 | 13 | 8 | 82s / 78s / 108s / 64–108s | 78s / 108s | 6.2 / 2.5 | 50% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 68s / 68s / 68s / 68–68s | 68s / 68s | 3.0 / 2.0 | - |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 59s / 59s / 59s / 59–59s | 59s / 59s | 6.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 12 | 12 | 34s | 0.20 | 8 | 1.0 | 18% |
| expert | 圣徒卡门 | 10 | 10 | 48s | 0.55 | 6 | - | - |
| expert | 塑路者 | 9 | 8 | 64s | 0.49 | 6 | - | - |
| expert | 接潮斥亡体 | 6 | 6 | 33s | 0.18 | 8 | - | - |
| expert | 接潮蔑死体 | 6 | 6 | 44s | 0.19 | 9 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 51s | 0.28 | 11 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 62% | 37% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 123 / 102 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 5 | 10:36 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:25 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 85 / 111 | 203 / 254 | 0 / 0 | 441 / 484 | 45 / 48 |
| expert | 0 | 15 | 8:00–10:00 | 73 / 92 | 27 / 47 | 0 / 0 | 380 / 484 | 35 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 6 | 766 | 0.0 | 0.8 / 0.1% | 1.0 / 0.8% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 10 | 747 | 0.1 | 0.0 / 0.0% | 0.5 / 0.8% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 9s（16/16） | 22 / 58 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 16 | 2:45 | 20 | 8s / 8s（16/16） | 6 / 17 | 0 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 3 | 16 | 4:37 | 24 | 9s / 9s（16/16） | 11 / 73 | 0 | bone/offspring/slider/stone ×4；bone/reaper/runner/slider/tracer ×4；bone/floater/runner/slider ×4 |
| expert | 4 | 16 | 5:27 | 36 | 12s / 12s（16/16） | 11 / 72 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×4 |
| expert | 5 | 16 | 6:23 | 39 | 16s / 13s（16/16） | 17 / 88 | 0 | bone/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×2 |
| expert | 6 | 15 | 7:57 | 27 | 9s / 9s（15/15） | 15 / 69 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4 |
| expert | 7 | 13 | 9:02 | 21 | 11s / 10s（13/13） | 24 / 67 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+exusiai+hoshiguma | 16 | 62% | 10:50 / 7:25 | 0.0 / - | 8 / 16 / 23 / 28 | 19% | 100% | 81 | 1884 | 举盾反击 12% 真实 11% 散射 11% 剑气 8% | 自身回复 51% 补给 24% 拾取 20% (747 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] texas+exusiai+hoshiguma | 16 | 62% | 10:50 / 7:25 | 100% | 100% | - | 0:47 / 2:41 | 2.7 / 48s | 60.8 | 73 | 5 | 0 | 3 | 14% / 17419 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | texas | 16 | 17.9 | 12.3% | class 75/25 control 20/14 economy 90/31 general 213/91 heal 26/7 melee 110/42 multi 18/8 shield 41/14 summon 31/16 survival 90/30 weak 16/9 | 0 |
| 合计 | | | | | class 75/25 control 20/14 economy 90/31 general 213/91 heal 26/7 melee 110/42 multi 18/8 shield 41/14 summon 31/16 survival 90/30 weak 16/9 | |

拿取最多（出现 / 拿取）：贵族刺剑 15/9，锈蚀刀片 30/9，赶车夫的长鞭 15/7，老近卫军之锋 5/6，漆黑的舞鞋 20/6，皇帝的恩宠 25/5，《旧高卢地名源流考》 13/5，远程协议-遥击 13/5，几丁质刺刃 5/5，“小格兰法洛” 6/5，国王的枝条 4/4，药枚 10/4
