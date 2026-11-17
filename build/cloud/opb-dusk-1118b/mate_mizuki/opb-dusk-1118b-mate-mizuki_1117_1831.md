# balance opb-dusk-1118b-mate-mizuki 1117_1831

args: `--squad mizuki,dusk --bot expert --seeds 4 --nocache --jobs 8 --tag opb-dusk-1118b-mate-mizuki --out build/cloud/opb-dusk-1118b/mate_mizuki --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 3 | 3 | 3 | 125s / 100s / 182s / 94–182s | 100s / 182s | 2.7 / 2.7 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 34s / 34s / 34s / 34–34s | 34s / 34s | 9.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 3 | 3 | 64s | 0.51 | 9 | - | - |
| expert | 接潮主教 | 3 | 3 | 35s | 0.19 | 6 | 1.0 | 3% |
| expert | 塑路者 | 2 | 2 | 76s | 0.36 | 12 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 65s | 0.14 | 6 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 19s | 0.25 | 4 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 4 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 8 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 100% | 0% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 119 / 108 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | （全部胜利） | | | | 0 | |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 96 / 115 | 130 / 240 | 2 / 3 | 432 / 445 | 46 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 82 / 115 | 25 / 34 | 2 / 3 | 428 / 445 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 胜 | 4 | 1019 | 0.0 | 8.0 / 0.2% | 0.2 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 10s / 10s（4/4） | 10 / 17 | 0 | bone/slider ×4 |
| expert | 2 | 4 | 2:45 | 20 | 8s / 8s（4/4） | 18 / 29 | 0 | bone/slider/stone ×4 |
| expert | 3 | 4 | 5:11 | 24 | 15s / 16s（4/4） | 16 / 38 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/floater/reaper/runner/slider/tracer ×1；bone/floater/runner/slider ×1 |
| expert | 4 | 4 | 6:15 | 38 | 16s / 12s（4/4） | 22 / 47 | 0 | bone/reaper/runner/slider/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 7:07 | 36 | 27s / 27s（4/4） | 44 / 116 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/floater/founder/offspring/reaper/runner/slider/spitter/stone ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 3 | 8:06 | 24 | 10s / 9s（3/3） | 3 / 10 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/founder/nest/runner/slider/stone/tracer ×1；bone/founder/nest/offspring/runner/slider/stone/tracer ×1 |
| expert | 7 | 2 | 8:56 | 21 | 8s / 8s（2/2） | 10 / 18 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+dusk | 4 | 100% | 11:42 / 10:34 | 0.0 / - | 8 / 15 / 22 / 28 | 0% | 100% | 97 | 1846 | 伞击 16% 触手 15% 真实 8% 墨弹 5% | 水月 57% 自身回复 20% 塞雷娅 9% (911 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+dusk | 4 | 100% | 11:42 / 10:34 | 100% | 100% | 1:08 | 0:52 / 4:04 | 2.8 / 65s | 54.6 | 70 | 1 | 19 | 4 | 35% / 38961 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | mizuki | 4 | 15.0 | 9.0% | class 17/4 control 2/1 economy 19/4 general 44/23 heal 7/0 melee 7/5 multi 4/1 shield 7/3 summon 25/11 survival 22/5 weak 6/3 | 0 |
| 合计 | | | | | class 17/4 control 2/1 economy 19/4 general 44/23 heal 7/0 melee 7/5 multi 4/1 shield 7/3 summon 25/11 survival 22/5 weak 6/3 | |

拿取最多（出现 / 拿取）：炸裂之手 3/3，海程 4/2，锈蚀刀片 3/2，《旧高卢地名源流考》 2/2，海潮的气息 0/2，扣挠之手 2/2，衍生者终端-超级改 7/1，涡旋座 2/1，散轶诗简 7/1，赶车夫的长鞭 1/1，布雷奥甘肖像 1/1，深洋主宰刻像 2/1
