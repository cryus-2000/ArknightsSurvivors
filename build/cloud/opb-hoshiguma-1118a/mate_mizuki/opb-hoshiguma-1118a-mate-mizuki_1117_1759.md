# balance opb-hoshiguma-1118a-mate-mizuki 1117_1759

args: `--squad mizuki,hoshiguma --bot expert --seeds 4 --nocache --jobs 8 --tag opb-hoshiguma-1118a-mate-mizuki --out build/cloud/opb-hoshiguma-1118a/mate_mizuki --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 4 | 4 | 4 | 67s / 69s / 77s / 52–77s | 70s / 77s | 11.1 / 3.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 3 | 3 | 78s | 0.48 | 7 | - | - |
| expert | 圣徒卡门 | 2 | 2 | 94s | 0.20 | 4 | - | - |
| expert | 接潮主教 | 2 | 2 | 59s | 0.14 | 8 | 1.0 | 6% |
| expert | 接潮斥亡体 | 2 | 2 | 59s | 0.15 | 8 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 52s | 0.31 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 4 | 100% | 0% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 4 | 0% | 198 / 172 | 85% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | （全部胜利） | | | | 0 | |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 4 | 全程 | 98 / 118 | 96 / 143 | 1 / 4 | 434 / 450 | 46 / 48 |
| expert | 0 | 4 | 8:00–10:00 | 74 / 81 | 26 / 38 | 0 / 1 | 430 / 450 | 43 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 胜 | 4 | 569 | 0.0 | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 4 | 1:15 | 15 | 11s / 10s（4/4） | 16 / 31 | 0 | bone/slider ×3；bone/slider/stone ×1 |
| expert | 2 | 4 | 2:45 | 20 | 9s / 9s（4/4） | 32 / 84 | 0 | bone/slider/stone ×3；bone/slider ×1 |
| expert | 3 | 4 | 5:31 | 24 | 9s / 8s（4/4） | 8 / 31 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×1 |
| expert | 4 | 4 | 6:43 | 40 | 16s / 17s（4/4） | 0 / 0 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/founder/nest/offspring/runner/slider/stone/tracer ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 4 | 7:35 | 37 | 18s / 14s（4/4） | 14 / 53 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×2；bone/floater/founder/offspring/reaper/runner/slider/spitter/stone ×1；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 6 | 3 | 8:08 | 27 | 9s / 9s（3/3） | 19 / 57 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 3 | 9:11 | 22 | 9s / 9s（3/3） | 5 / 14 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/offspring/reaper/runner/slider/spitter/stone ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+hoshiguma | 4 | 100% | 11:07 / 10:52 | 0.0 / - | 8 / 15 / 23 / 28 | 0% | 100% | 91 | 1843 | 触手 20% 伞击 17% 剑气 6% 真实 5% | 水月 53% 自身回复 21% 拾取 8% (606 / 0.0) | boss_carmen |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] mizuki+hoshiguma | 4 | 100% | 11:07 / 10:52 | 100% | 100% | 1:28 | 0:49 / 3:12 | 2.5 / 74s | 29.9 | 50 | 1 | 12 | 4 | 40% / 49016 | - |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | mizuki | 4 | 17.5 | 6.5% | class 28/11 control 5/2 economy 20/6 general 54/25 heal 5/2 melee 3/1 multi 4/2 shield 8/3 summon 31/13 survival 25/4 weak 4/1 | 0 |
| 合计 | | | | | class 28/11 control 5/2 economy 20/6 general 54/25 heal 5/2 melee 3/1 multi 4/2 shield 8/3 summon 31/13 survival 25/4 weak 4/1 | |

拿取最多（出现 / 拿取）：炸裂之手 3/3，老蒲扇 2/2，《旧高卢地名源流考》 2/2，海程 6/2，绿叶菜罐头 2/2，黑色郁金香 2/2，铁卫-无锋 4/2，地形图 3/2，衍生者终端-超级改 7/2，散轶诗简 7/2，扣挠之手 2/2，堡垒协议-方阵 2/2
