# balance op-ling-s64-peers-1118n-h-suzuran 1118_0718

args: `--squad hoshiguma,suzuran --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-h-suzuran --out build/cloud/op-ling-s64-peers-1118n/hos_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 25 | 25 | 19 | 110s / 100s / 170s / 57–181s | 100s / 170s | 3.9 / 2.8 | 46% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 63s / 63s / 63s / 63–63s | 63s / 63s | 1.5 / 2.0 | 6% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 接潮主教 | 23 | 22 | 48s | 0.16 | 10 | 1.1 | 14% |
| expert | 圣徒卡门 | 20 | 20 | 48s | 0.52 | 8 | - | - |
| expert | 塑路者 | 20 | 20 | 54s | 0.61 | 8 | - | - |
| expert | 接潮斥亡体 | 12 | 12 | 48s | 0.15 | 10 | - | - |
| expert | 接潮蔑死体 | 11 | 11 | 55s | 0.20 | 11 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 82s | 0.23 | 17 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 62% | 37% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 74 / 65 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 11:08 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 2 | 10:35 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 2 | 8:50 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:22 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:22 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:11 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:48 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 12:06 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 100 / 138 | 211 / 319 | 8 / 11 | 406 / 441 | 45 / 48 |
| expert | 0 | 32 | 8:00–10:00 | 82 / 116 | 30 / 99 | 6 / 10 | 396 / 441 | 38 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 12 | 1022 | 0.0 | 0.6 / 0.2% | 0.8 / 0.9% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 20 | 982 | 0.1 | 0.1 / 0.0% | 0.9 / 1.2% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 11s（32/32） | 11 / 60 | 0 | bone/slider ×16；bone/slider/stone ×16 |
| expert | 2 | 32 | 2:45 | 20 | 9s / 9s（32/32） | 7 / 32 | 0 | bone/slider/stone ×16；bone/slider ×16 |
| expert | 3 | 32 | 4:35 | 24 | 12s / 12s（32/32） | 9 / 33 | 0 | bone/floater/runner/slider ×10；bone/floater/reaper/runner/slider/tracer ×7；bone/slider/stone ×6 |
| expert | 4 | 32 | 5:25 | 36 | 18s / 15s（32/32） | 14 / 99 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×13；bone/floater/reaper/runner/slider/tracer ×11；bone/reaper/runner/slider/tracer ×8 |
| expert | 5 | 32 | 6:21 | 39 | 20s / 16s（32/32） | 14 / 69 | 0 | bone/reaper/runner/slider/tracer ×11；bone/floater/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×9 |
| expert | 6 | 31 | 8:01 | 27 | 13s / 11s（31/31） | 20 / 117 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×15；bone/founder/nest/runner/slider/spitter/stone/tracer ×8；bone/founder/nest/offspring/runner/slider/stone/tracer ×7 |
| expert | 7 | 24 | 9:05 | 22 | 13s / 12s（22/24） | 27 / 145 | 2 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×9；bone/floater/offspring/reaper/runner/slider/spitter/stone ×8；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×7 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 32 | 62% | 11:13 / 8:29 | 0.0 / - | 8 / 15 / 22 / 27 | 14% | 100% | 69 | 1851 | 举盾反击 11% 狐火 9% 真实 9% 剑气 7% | 自身回复 34% 补给 17% 铃兰 12% (819 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 32 | 62% | 11:13 / 8:29 | 100% | 100% | 1:17 | 0:46 / 3:09 | 2.7 / 53s | 77.4 | 77 | 6 | 0 | 5 | 25% / 26048 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 16.6 | 12.4% | class 114/35 control 44/17 economy 148/62 general 394/164 heal 51/22 melee 220/88 multi 62/20 shield 57/29 summon 62/29 survival 166/53 weak 29/13 | 0 |
| 合计 | | | | | class 114/35 control 44/17 economy 148/62 general 394/164 heal 51/22 melee 220/88 multi 62/20 shield 57/29 summon 62/29 survival 166/53 weak 29/13 | |

拿取最多（出现 / 拿取）：皇帝的恩宠 56/17，贵族刺剑 29/16，赶车夫的长鞭 34/15，锈蚀刀片 56/14，漆黑的舞鞋 31/14，老近卫军之锋 14/12，《旧高卢地名源流考》 24/9，药枚 12/8，“多功能”发夹 14/8，红色蝴蝶结 11/6，扣挠之手 6/6，猎人的口粮 16/6
