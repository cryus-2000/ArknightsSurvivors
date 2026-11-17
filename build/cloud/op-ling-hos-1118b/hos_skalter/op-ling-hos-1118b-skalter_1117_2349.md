# balance op-ling-hos-1118b-skalter 1117_2349

args: `--squad hoshiguma,skalter --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118b-skalter --out build/cloud/op-ling-hos-1118b/hos_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 7 | 75s / 70s / 110s / 61–110s | 70s / 110s | 7.0 / 2.8 | 41% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 92s / 92s / 92s / 92–92s | 72s / 72s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 50s / 50s / 50s / 50–50s | 50s / 50s | 6.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 11 | 11 | 58s | 0.50 | 7 | - | - |
| expert | 塑路者 | 11 | 11 | 46s | 0.39 | 8 | - | - |
| expert | 接潮主教 | 5 | 5 | 51s | 0.16 | 7 | 1.3 | 19% |
| expert | 接潮蔑死体 | 3 | 3 | 43s | 0.18 | 8 | - | - |
| expert | 圣徒伊比利亚 | 2 | 2 | 48s | 0.33 | 6 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 58s | 0.15 | 8 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 13 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 56% | 43% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 6% | 110 / 98 | 100% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:45 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 否 | 1 | 9:39 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 1:50 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:49 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:36 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 1 | 8:55 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 1 | 5:52 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 87 / 110 | 158 / 292 | 0 / 0 | 392 / 448 | 41 / 48 |
| expert | 0 | 14 | 8:00–10:00 | 77 / 104 | 31 / 64 | 0 / 0 | 400 / 448 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 829 | 0.0 | 6.3 / 0.4% | 0.3 / 0.2% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 9 | 899 | 0.0 | 2.8 / 0.5% | 1.2 / 1.6% | 0.0 / 0.0% | 0.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 13s / 11s（15/16） | 17 / 61 | 0 | bone/slider/stone ×10；bone/slider ×6 |
| expert | 2 | 15 | 2:45 | 20 | 9s / 9s（15/15） | 9 / 40 | 0 | bone/slider ×9；bone/slider/stone ×6 |
| expert | 3 | 15 | 4:51 | 25 | 13s / 13s（14/15） | 17 / 82 | 1 | bone/offspring/slider/stone ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/floater/runner/slider ×3 |
| expert | 4 | 14 | 5:43 | 37 | 15s / 14s（14/14） | 9 / 31 | 0 | bone/floater/reaper/runner/slider/tracer ×7；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 5 | 14 | 6:38 | 38 | 21s / 14s（14/14） | 15 / 60 | 0 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×3；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 6 | 13 | 7:59 | 27 | 10s / 9s（13/13） | 11 / 22 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/founder/nest/offspring/runner/slider/stone/tracer ×4；bone/floater/founder/nest/runner/slider/stone/tracer ×3 |
| expert | 7 | 11 | 9:06 | 22 | 9s / 9s（11/11） | 19 / 100 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 16 | 56% | 9:54 / 1:50 | 0.0 / - | 7 / 15 / 23 / 26 | 9% | 91% | 42 | 1688 | 举盾反击 10% 剑气 9% 声浪 5% 终结技·hoshiguma·反震 5% | 自身回复 32% 浊心斯卡蒂 32% 补给 11% (693 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+skalter | 16 | 56% | 9:54 / 1:50 | 93% | 93% | 1:23 | 0:50 / 2:55 | 2.1 / 59s | 76.5 | 79 | 4 | 2 | 4 | 29% / 28856 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 16 | 13.8 | 4.4% | class 50/19 control 13/9 economy 57/20 general 164/71 heal 20/9 melee 98/37 multi 26/9 shield 22/14 summon 25/11 survival 49/17 weak 12/5 | 0 |
| 合计 | | | | | class 50/19 control 13/9 economy 57/20 general 164/71 heal 20/9 melee 98/37 multi 26/9 shield 22/14 summon 25/11 survival 49/17 weak 12/5 | |

拿取最多（出现 / 拿取）：漆黑的舞鞋 18/8，赶车夫的长鞭 18/7，皇帝的恩宠 21/7，老近卫军之锋 8/7，“多功能”发夹 9/6，《旧高卢地名源流考》 7/5，锈蚀刀片 22/5，扣挠之手 5/4，支援轰隆隆 9/4，生命之水 6/3，贵族刺剑 11/3，显圣吊坠 8/3
