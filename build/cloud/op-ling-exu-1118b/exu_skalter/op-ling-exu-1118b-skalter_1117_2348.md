# balance op-ling-exu-1118b-skalter 1117_2348

args: `--squad exusiai,skalter --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118b-skalter --out build/cloud/op-ling-exu-1118b/exu_skalter --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 7 | 7 | 6 | 60s / 66s / 73s / 38–73s | 66s / 73s | 12.3 / 3.0 | 27% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 9 | 7 | 44s | 0.57 | 4 | - | - |
| expert | 塑路者 | 9 | 8 | 46s | 0.59 | 5 | - | - |
| expert | 圣徒伊比利亚 | 4 | 4 | 40s | 0.33 | 8 | - | - |
| expert | 接潮主教 | 4 | 4 | 48s | 0.17 | 6 | 1.5 | 21% |
| expert | 接潮蔑死体 | 2 | 2 | 45s | 0.20 | 6 | - | - |
| expert | 接潮斥亡体 | 2 | 2 | 48s | 0.18 | 5 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.1 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 106 / 96 | 95% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:01 |
| expert | 0 | wound | 第 2 轮 · 稳定 | 否 | 否 | 1 | 7:39 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 8:02 |
| expert | 0 | contact_founder | 第 4 轮 · 收缩 | 否 | 否 | 1 | 9:13 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:50 |
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:41 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:12 |
| expert | 0 | atk_reaper | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:23 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:53 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 73 / 93 | 144 / 250 | 1 / 10 | 311 / 416 | 29 / 48 |
| expert | 0 | 9 | 8:00–10:00 | 67 / 73 | 21 / 55 | 1 / 5 | 362 / 416 | 28 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 336 | 0.0 | 2.6 / 2.6% | 0.5 / 0.6% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 6 | 483 | 0.0 | 3.7 / 0.5% | 3.2 / 6.9% | 0.0 / 0.0% | 1.0 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 10s / 10s（16/16） | 17 / 42 | 0 | bone/slider/stone ×11；bone/slider ×5 |
| expert | 2 | 16 | 2:45 | 20 | 8s / 8s（16/16） | 19 / 71 | 0 | bone/slider ×11；bone/slider/stone ×5 |
| expert | 3 | 13 | 4:31 | 25 | 12s / 10s（13/13） | 11 / 46 | 0 | bone/slider/stone ×5；bone/offspring/slider/stone ×4；bone/floater/runner/slider ×2 |
| expert | 4 | 13 | 5:21 | 36 | 10s / 10s（12/13） | 32 / 122 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×2 |
| expert | 5 | 12 | 6:22 | 39 | 13s / 12s（10/12） | 40 / 167 | 2 | bone/floater/reaper/runner/slider/tracer ×5；bone/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 6 | 9 | 7:57 | 27 | 8s / 7s（8/9） | 18 / 131 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×3；bone/founder/nest/runner/slider/spitter/stone/tracer ×2 |
| expert | 7 | 7 | 9:04 | 22 | 8s / 8s（6/7） | 35 / 110 | 1 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 16 | 37% | 8:15 / 3:37 | 0.0 / - | 8 / 16 / 23 / 23 | 15% | 83% | 48 | 1391 | 散射 25% 弹匣倾泻 11% 过载模式 8% 真实 8% | 自身回复 31% 浊心斯卡蒂 23% 补给 18% (578 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+skalter | 16 | 37% | 8:15 / 3:37 | 100% | 81% | 1:12 | 0:50 / 3:21 | 1.7 / 48s | 36.8 | 78 | 5 | 1 | 3 | 31% / 23850 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 16 | 12.6 | 9.0% | class 72/23 control 15/8 economy 58/24 general 145/57 heal 11/5 melee 19/5 multi 83/37 shield 19/12 summon 12/5 survival 50/19 weak 9/6 | 0 |
| 合计 | | | | | class 72/23 control 15/8 economy 58/24 general 145/57 heal 11/5 melee 19/5 multi 83/37 shield 19/12 summon 12/5 survival 50/19 weak 9/6 | |

拿取最多（出现 / 拿取）：显圣吊坠 23/8，穿甲弹 18/8，损坏的左轮弹巢 9/8，银餐叉 20/7，洁白的舞鞋 13/6，“多功能”发夹 8/6，锈刃-可视静谧 8/4，远程协议-遥击 10/4，生还者合约 6/4，《旧高卢地名源流考》 6/4，支柱-枯法 6/3，“绽放” 8/3
