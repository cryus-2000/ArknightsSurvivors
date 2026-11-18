# balance op-ling-s64-peers-1118n-e-suzuran 1118_0714

args: `--squad exusiai,suzuran --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-e-suzuran --out build/cloud/op-ling-s64-peers-1118n/exu_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 13 | 13 | 4 | 73s / 75s / 87s / 56–87s | 75s / 87s | 6.7 / 3.0 | 33% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 71s / 71s / 79s / 63–79s | 71s / 79s | 2.0 / 2.0 | 44% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 20 | 20 | 38s | 0.60 | 5 | - | - |
| expert | 塑路者 | 20 | 19 | 38s | 0.66 | 4 | - | - |
| expert | 接潮主教 | 15 | 14 | 42s | 0.18 | 9 | 1.2 | 21% |
| expert | 接潮蔑死体 | 8 | 7 | 34s | 0.21 | 9 | - | - |
| expert | 接潮斥亡体 | 7 | 7 | 53s | 0.15 | 9 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 45s | 0.33 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 9 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 18% | 81% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 73 / 52 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 6 | 10:42 |
| expert | 0 | shock_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 3 | 10:39 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 2 | 5:42 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 否 | 2 | 9:10 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 2 | 7:11 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 2 | 8:54 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 8:08 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:14 |
| expert | 0 | nest | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:15 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:01 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:53 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:20 |
| expert | 0 | corrode | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:25 |
| expert | 0 | nest | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:03 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 85 / 105 | 142 / 281 | 9 / 11 | 325 / 453 | 31 / 47 |
| expert | 0 | 23 | 8:00–10:00 | 74 / 97 | 22 / 41 | 7 / 10 | 334 / 420 | 30 / 47 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 26 | 536 | 0.2 | 5.0 / 0.7% | 1.2 / 3.2% | 0.0 / 0.0% | 0.3 |
| expert | 0 | 胜 | 6 | 844 | 0.2 | 0.0 / 0.0% | 2.2 / 4.1% | 0.0 / 0.0% | 0.2 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 11 / 62 | 0 | bone/slider ×18；bone/slider/stone ×14 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 8 / 53 | 0 | bone/slider/stone ×18；bone/slider ×14 |
| expert | 3 | 32 | 4:15 | 25 | 10s / 9s（32/32） | 13 / 61 | 0 | bone/offspring/slider/stone ×15；bone/floater/runner/slider ×8；bone/slider/stone ×8 |
| expert | 4 | 31 | 5:06 | 35 | 13s / 13s（31/31） | 35 / 126 | 1 | bone/reaper/runner/slider/tracer ×14；bone/floater/reaper/runner/slider/tracer ×11；bone/offspring/reaper/runner/slider/spitter/tracer ×6 |
| expert | 5 | 28 | 6:16 | 39 | 15s / 13s（26/28） | 25 / 97 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×12；bone/floater/reaper/runner/slider/tracer ×8；bone/reaper/runner/slider/tracer ×7 |
| expert | 6 | 23 | 7:55 | 27 | 10s / 9s（22/23） | 30 / 196 | 2 | bone/founder/nest/runner/slider/spitter/stone/tracer ×10；bone/floater/founder/nest/runner/slider/stone/tracer ×10；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 18 | 9:01 | 22 | 11s / 12s（17/18） | 30 / 121 | 3 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×6 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+suzuran | 32 | 18% | 9:11 / 4:53 | 0.0 / - | 8 / 16 / 23 / 25 | 25% | 93% | 67 | 1620 | 散射 21% 真实 10% 狐火 10% 弹匣倾泻 8% | 自身回复 35% 补给 19% 拾取 14% (700 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+suzuran | 32 | 18% | 9:11 / 4:53 | 100% | 96% | 1:16 | 0:48 / 3:05 | 2.2 / 40s | 52.6 | 86 | 7 | 1 | 3 | 22% / 21124 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 14.2 | 11.2% | class 109/33 control 34/11 economy 136/41 general 314/150 heal 36/12 melee 52/22 multi 170/77 shield 48/24 summon 53/22 survival 149/51 weak 32/10 | 0 |
| 合计 | | | | | class 109/33 control 34/11 economy 136/41 general 314/150 heal 36/12 melee 52/22 multi 170/77 shield 48/24 summon 53/22 survival 149/51 weak 32/10 | |

拿取最多（出现 / 拿取）：损坏的左轮弹巢 21/18，银餐叉 42/15，洁白的舞鞋 35/15，穿甲弹 37/15，显圣吊坠 35/14，《旧高卢地名源流考》 20/10，皇帝的恩宠 13/8，皇家利口酒 7/7，蓝卡坞安全衣 7/7，药枚 12/6，支柱-援护 16/6，生还者合约 8/6
