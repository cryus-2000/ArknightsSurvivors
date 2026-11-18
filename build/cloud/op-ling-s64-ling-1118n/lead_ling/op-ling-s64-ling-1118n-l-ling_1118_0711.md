# balance op-ling-s64-ling-1118n-l-ling 1118_0711

args: `--op ling --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-ling-1118n-l-ling --out build/cloud/op-ling-s64-ling-1118n/lead_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 10 | 10 | 8 | 96s / 73s / 174s / 43–174s | 74s / 174s | 7.9 / 2.6 | 77% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 52s / 52s / 52s / 52–52s | 52s / 52s | 6.1 / 2.0 | - |
| expert | 伊祖米克 | resolve 1 | 1 | 1 | 53s / 53s / 53s / 53–53s | 33s / 33s | 3.0 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 18 | 14 | 42s | 0.55 | 5 | - | - |
| expert | 塑路者 | 17 | 16 | 60s | 0.55 | 5 | - | - |
| expert | 接潮主教 | 15 | 13 | 42s | 0.17 | 9 | 1.1 | 14% |
| expert | 接潮斥亡体 | 10 | 10 | 46s | 0.15 | 9 | - | - |
| expert | 接潮蔑死体 | 5 | 4 | 32s | 0.22 | 7 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 23s | 0.45 | 3 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 5 | 0.0 / 0.0 / 0.0 / 0 | 7 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 31% | 68% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 129 / 117 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:38 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 2 | 8:03 |
| expert | 0 | wound | 第 4 轮 · 收缩 | 否 | 否 | 2 | 9:13 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:12 |
| expert | 0 | contact_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:17 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:08 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:09 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:29 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:55 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 是 | 1 | 7:20 |
| expert | 0 | contact_tracer | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:24 |
| expert | 0 | shock_founder | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:21 |
| expert | 0 | contact_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 4:54 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:07 |
| expert | 0 | atk_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:15 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 8:13 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:26 |
| expert | 0 | wound | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:01 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 80 / 114 | 130 / 319 | 1 / 10 | 341 / 444 | 30 / 41 |
| expert | 0 | 16 | 8:00–10:00 | 71 / 114 | 30 / 113 | 1 / 10 | 367 / 444 | 26 / 41 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 22 | 420 | 0.0 | 5.2 / 1.2% | 0.0 / 0.0% | 0.0 / 0.0% | 0.0 |
| expert | 0 | 胜 | 10 | 1218 | 0.3 | 4.3 / 0.2% | 2.3 / 2.5% | 0.0 / 0.0% | 0.4 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 17 / 51 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 2 | 32 | 2:45 | 20 | 9s / 8s（32/32） | 14 / 65 | 0 | bone/slider ×19；bone/slider/stone ×13 |
| expert | 3 | 27 | 4:31 | 25 | 11s / 10s（26/27） | 34 / 137 | 2 | bone/offspring/slider/stone ×10；bone/slider/stone ×8；bone/reaper/runner/slider/tracer ×3 |
| expert | 4 | 24 | 5:22 | 36 | 17s / 15s（21/24） | 45 / 164 | 4 | bone/offspring/reaper/runner/slider/spitter/tracer ×11；bone/reaper/runner/slider/tracer ×10；bone/floater/reaper/runner/slider/tracer ×3 |
| expert | 5 | 20 | 6:25 | 39 | 15s / 14s（19/20） | 35 / 138 | 1 | bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×4 |
| expert | 6 | 16 | 8:00 | 26 | 10s / 10s（14/16） | 46 / 153 | 3 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/floater/founder/nest/runner/slider/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×3 |
| expert | 7 | 11 | 9:02 | 21 | 9s / 8s（10/11） | 76 / 219 | 2 | bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×3；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 32 | 31% | 8:04 / 4:08 | 0.0 / - | 8 / 16 / 23 / 22 | 25% | 75% | 65 | 1302 | 弦惊·剑势 6% 逍遥·鸣瑟 6% 弦惊·剑气 5% 真实 5% | 自身回复 40% 补给 18% 拾取 16% (796 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] ling | 32 | 31% | 8:04 / 4:08 | 100% | 78% | 1:03 | 0:47 / 3:28 | 1.8 / 50s | 60.5 | 111 | 10 | 1 | 2 | 44% / 28963 | wound |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | ling | 32 | 11.2 | 6.9% | class 86/23 control 38/18 economy 103/34 general 265/120 heal 32/5 melee 43/10 multi 37/15 shield 34/22 summon 151/66 survival 125/36 weak 27/8 | 0 |
| 合计 | | | | | class 86/23 control 38/18 economy 103/34 general 265/120 heal 32/5 melee 43/10 multi 37/15 shield 34/22 summon 151/66 survival 125/36 weak 27/8 | |

拿取最多（出现 / 拿取）：散轶诗简 36/13，《旧高卢地名源流考》 14/11，衍生者终端-超级改 47/10，无字珊瑚 10/9，几丁质刺刃 11/9，海程 27/9，扣挠之手 7/7，极速之手 14/6，“多功能”发夹 10/6，三钥协定 6/5，夜阳花 13/5，海潮的气息 0/5
