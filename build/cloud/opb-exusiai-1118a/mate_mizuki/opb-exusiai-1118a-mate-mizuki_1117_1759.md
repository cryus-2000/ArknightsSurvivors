# balance opb-exusiai-1118a-mate-mizuki 1117_1759

args: `--squad mizuki,exusiai --bot expert --seeds 4 --nocache --jobs 8 --tag opb-exusiai-1118a-mate-mizuki --out build/cloud/opb-exusiai-1118a/mate_mizuki --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 79s / 71s / 133s / 34–133s | 71s / 133s | 9.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 4 | 4 | 48s | 0.45 | 8 | - | - |
| expert | 圣徒卡门 | 2 | 2 | 87s | 0.41 | 7 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 39s | 0.37 | 4 | - | - |
| expert | 接潮主教 | 1 | 1 | 45s | 0.15 | 5 | 1.0 | 11% |
| expert | 接潮斥亡体 | 1 | 1 | 45s | 0.17 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 75% | 25% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 110 / 124 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:08 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 89 / 98 | 77 / 95 | 0 / 0 | 427 / 443 | 44 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 71 / 88 | 18 / 25 | 0 / 0 | 416 / 422 | 42 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 1 | 1012 | 0.0 | 14.0 / 3.1% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 3 | 998 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 10s / 10s（4/4） | 12 / 21 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 10s / 10s（4/4） | 4 / 16 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 4 | 4:48 | 25 | 10s / 10s（4/4） | 8 / 20 | 0 | bone/slider/stone ×2；bone/floater/reaper/runner/slider/tracer ×1；bone/floater/runner/slider ×1 |
| expert | 4 | 4 | 5:38 | 36 | 14s / 14s（4/4） | 14 / 26 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 6:38 | 40 | 14s / 12s（4/4） | 36 / 121 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 6 | 4 | 8:04 | 27 | 9s / 9s（4/4） | 50 / 135 | 1 | bone/founder/nest/runner/slider/spitter/stone/tracer ×3；bone/floater/founder/nest/runner/slider/stone/tracer ×1 |
| expert | 7 | 3 | 9:12 | 22 | 11s / 10s（3/3） | 10 / 31 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+exusiai | 4 | 75% | 10:31 / 8:08 | 0.0 / - | 8 / 16 / 23 / 27 | 0% | 100% | 97 | 1788 | 触手 16% 伞击 13% 散射 12% 真实 7% | 水月 53% 自身回复 19% 拾取 7% (866 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+exusiai | 4 | 75% | 10:31 / 8:08 | 100% | 100% | 1:05 | 0:49 / 3:54 | 2.2 / 54s | 68.5 | 83 | 2 | 14 | 3 | 33% / 39090 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | mizuki | 4 | 15.8 | 9.4% | class 15/6 control 3/1 economy 16/5 general 41/21 heal 7/2 melee 11/3 multi 7/1 shield 9/5 summon 21/14 survival 20/2 weak 6/3 | 0 |
| 合计 | | | | | class 15/6 control 3/1 economy 16/5 general 41/21 heal 7/2 melee 11/3 multi 7/1 shield 9/5 summon 21/14 survival 20/2 weak 6/3 | |

拿取最多（出现 / 拿取）：散轶诗简 5/3，《旧高卢地名源流考》 3/3，扣挠之手 3/2，“多功能”发夹 6/2，海程 3/2，几丁质刺刃 3/2，衍生者终端-超级改 0/2，古旧钱币 1/1，锈刃-突破 1/1，破坏协议-压制 1/1，猎人的口粮 2/1，Miss.Christine摸摸券 1/1
