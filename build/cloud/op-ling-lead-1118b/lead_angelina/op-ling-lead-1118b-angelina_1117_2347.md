# balance op-ling-lead-1118b-angelina 1117_2347

args: `--op angelina --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-lead-1118b-angelina --out build/cloud/op-ling-lead-1118b/lead_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 6 | 6 | 5 | 150s / 162s / 243s / 75–243s | 162s / 243s | 1.8 / 3.0 | 25% |
| expert | 最后的骑士 | knight 2 | 2 | 1 | 155s / 155s / 155s / 155–155s | 155s / 155s | 0.0 / 1.0 | 84% |
| expert | 伊莎玛拉 | deep 1 | 1 | 0 | - | - | 1.1 / 1.0 | 65% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 9 | 51s | 0.35 | 9 | - | - |
| expert | 塑路者 | 7 | 6 | 100s | 0.37 | 8 | - | - |
| expert | 接潮主教 | 4 | 4 | 103s | 0.11 | 9 | 1.0 | 11% |
| expert | 接潮蔑死体 | 3 | 3 | 106s | 0.15 | 11 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 61s | 0.28 | 6 | - | - |
| expert | 接潮斥亡体 | 1 | 1 | 100s | 0.11 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 37% | 62% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 12% | 120 / 112 | 98% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:08 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:16 |
| expert | 0 | boss_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:23 |
| expert | 0 | boss_ishar | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:19 |
| expert | 0 | atk_tracer | 未缩圈 | 否 | 否 | 1 | 1:49 |
| expert | 0 | wound | 第 3 轮 · 预告 | 否 | 否 | 1 | 9:22 |
| expert | 0 | atk_tracer | 第 1 轮 · 收缩 | 否 | 否 | 1 | 2:51 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:11 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 78 / 120 | 129 / 316 | 1 / 9 | 341 / 423 | 35 / 48 |
| expert | 0 | 10 | 8:00–10:00 | 80 / 120 | 34 / 105 | 1 / 9 | 400 / 417 | 34 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 10 | 278 | 0.4 | 0.2 / 0.0% | 2.3 / 9.2% | 0.0 / 0.0% | 0.7 |
| expert | 0 | 胜 | 6 | 652 | 0.3 | 4.2 / 0.1% | 7.2 / 7.5% | 0.0 / 0.0% | 0.8 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 14s / 14s（16/16） | 8 / 35 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 15 | 2:45 | 20 | 10s / 10s（14/15） | 11 / 32 | 1 | bone/slider ×9；bone/slider/stone ×6 |
| expert | 3 | 10 | 5:10 | 24 | 11s / 10s（10/10） | 16 / 66 | 0 | bone/floater/reaper/runner/slider/tracer ×3；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/reaper/runner/slider/tracer ×2 |
| expert | 4 | 10 | 6:01 | 38 | 23s / 16s（10/10） | 10 / 61 | 0 | bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2 |
| expert | 5 | 10 | 7:35 | 38 | 18s / 13s（9/10） | 29 / 123 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×2；bone/offspring/reaper/runner/slider/spitter/tracer ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 6 | 7 | 8:29 | 25 | 10s / 10s（7/7） | 3 / 19 | 0 | bone/floater/founder/nest/runner/slider/stone/tracer ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×1；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |
| expert | 7 | 3 | 9:07 | 22 | 12s / 12s（3/3） | 15 / 45 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 16 | 37% | 8:40 / 1:49 | 0.0 / - | 7 / 15 / 22 / 21 | 45% | 70% | 52 | 1245 | 双重引力 12% 秘杖·速充模式 8% 重力弹 4% 藏品 4% | 自身回复 34% 塞雷娅 15% 补给 14% (685 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] angelina | 16 | 37% | 8:40 / 1:49 | 87% | 68% | 1:08 | 0:49 / 3:01 | 1.5 / 85s | 33.7 | 86 | 8 | 3 | 6 | 27% / 11923 | boss_carmen |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | angelina | 16 | 10.4 | 8.8% | class 40/8 control 64/33 economy 60/18 general 136/55 heal 16/7 melee 25/11 multi 16/4 shield 15/9 summon 21/10 survival 41/9 weak 14/2 | 0 |
| 合计 | | | | | class 40/8 control 64/33 economy 60/18 general 136/55 heal 16/7 melee 25/11 multi 16/4 shield 15/9 summon 21/10 survival 41/9 weak 14/2 | |

拿取最多（出现 / 拿取）：凯旋号角 20/7，高闪相机 7/6，“多功能”发夹 9/5，安洁莉娜的创想 16/5，“小格兰法洛” 9/5，悬丝傀儡 5/4，“荣耀套餐” 5/4，古怪的长笛 6/4，显圣吊坠 9/3，血魔的银杯 6/3，羽兽肝酱 3/3，“绽放” 4/3
