# balance opb-exusiai-1118a-lead 1117_1753

args: `--op exusiai --bot expert --seeds 16 --nocache --jobs 8 --tag opb-exusiai-1118a-lead --out build/cloud/opb-exusiai-1118a/lead --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 9 | 9 | 8 | 82s / 78s / 131s / 43–131s | 78s / 131s | 6.7 / 2.8 | 81% |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 50s / 50s / 50s / 50–50s | 30s / 30s | 3.4 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 9 | 8 | 40s | 0.54 | 5 | - | - |
| expert | 塑路者 | 8 | 7 | 55s | 0.59 | 5 | - | - |
| expert | 接潮主教 | 6 | 5 | 34s | 0.20 | 8 | 1.0 | 15% |
| expert | 接潮斥亡体 | 5 | 4 | 36s | 0.16 | 7 | - | - |
| expert | 圣徒伊比利亚 | 5 | 5 | 45s | 0.32 | 12 | - | - |
| expert | 接潮蔑死体 | 1 | 1 | 34s | 0.22 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 9 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 56% | 43% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 104 / 90 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:00 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:15 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:24 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:33 |
| expert | 0 | contact_tracer | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:09 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 9:16 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 80 / 107 | 173 / 319 | 1 / 10 | 322 / 401 | 28 / 34 |
| expert | 0 | 11 | 8:00–10:00 | 70 / 88 | 28 / 64 | 0 / 5 | 339 / 393 | 28 / 32 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 7 | 441 | 0.1 | 14.4 / 1.5% | 0.3 / 0.7% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 9 | 877 | 0.4 | 5.0 / 0.5% | 2.8 / 3.4% | 0.0 / 0.0% | 0.3 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 10s（16/16） | 14 / 31 | 0 | bone/slider/stone ×13；bone/slider ×3 |
| expert | 2 | 16 | 2:45 | 20 | 7s / 8s（16/16） | 10 / 37 | 0 | bone/slider ×13；bone/slider/stone ×3 |
| expert | 3 | 14 | 4:27 | 25 | 10s / 9s（14/14） | 26 / 77 | 0 | bone/slider/stone ×5；bone/floater/runner/slider ×4；bone/offspring/slider/stone ×4 |
| expert | 4 | 13 | 5:17 | 36 | 12s / 11s（13/13） | 20 / 98 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×4 |
| expert | 5 | 12 | 6:18 | 39 | 18s / 12s（12/12） | 16 / 45 | 0 | bone/floater/reaper/runner/slider/tracer ×5；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×3 |
| expert | 6 | 10 | 7:51 | 27 | 10s / 9s（10/10） | 25 / 70 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×3 |
| expert | 7 | 10 | 9:01 | 22 | 13s / 11s（10/10） | 24 / 77 | 0 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai | 16 | 56% | 9:16 / 3:53 | 0.0 / - | 8 / 16 / 23 / 24 | 13% | 83% | 70 | 1561 | 散射 20% 弹匣倾泻 9% 过载模式 6% 终结技·exusiai·爆裂弹 6% | 自身回复 32% 补给 14% 拾取 12% (830 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai | 16 | 56% | 9:16 / 3:53 | 100% | 87% | 1:00 | 0:50 / 2:42 | 1.9 / 46s | 60.1 | 95 | 6 | 0 | 3 | 24% / 20067 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 16 | 13.1 | 6.2% | class 45/15 control 23/9 economy 56/15 general 138/70 heal 11/2 melee 26/10 multi 77/31 shield 26/16 summon 28/12 survival 74/25 weak 14/4 | 0 |
| 合计 | | | | | class 45/15 control 23/9 economy 56/15 general 138/70 heal 11/2 melee 26/10 multi 77/31 shield 26/16 summon 28/12 survival 74/25 weak 14/4 | |

拿取最多（出现 / 拿取）：银餐叉 17/9，穿甲弹 16/7，洁白的舞鞋 23/7，贵族刺剑 6/5，药枚 6/5，“多功能”发夹 7/4，显圣吊坠 15/4，损坏的左轮弹巢 6/4，王庭盟约 2/3，《旧高卢地名源流考》 7/3，投币玩具 7/3，安洁莉娜的创想 8/3
