# balance op-ling-exu-1118c-ling 1118_0022

args: `--squad exusiai,ling --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118c-ling --out build/cloud/op-ling-exu-1118c/exu_ling --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 11 | 11 | 5 | 67s / 65s / 77s / 62–77s | 65s / 77s | 10.2 / 3.0 | 27% |
| expert | 最后的骑士 | knight 1 | 1 | 1 | 72s / 72s / 72s / 72–72s | 72s / 72s | 4.4 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 25 | 21 | 44s | 0.54 | 4 | - | - |
| expert | 塑路者 | 14 | 14 | 48s | 0.57 | 5 | - | - |
| expert | 接潮主教 | 11 | 9 | 37s | 0.18 | 6 | 1.1 | 15% |
| expert | 接潮斥亡体 | 7 | 7 | 37s | 0.20 | 6 | - | - |
| expert | 接潮蔑死体 | 4 | 2 | 40s | 0.21 | 9 | - | - |
| expert | 圣徒伊比利亚 | 2 | 1 | 47s | 0.41 | 7 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 2 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 6 | 0.0 / 0.0 / 0.0 / 0 | 8 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 18% | 81% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 85 / 76 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 3 | 10:36 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 3 | 4:13 |
| expert | 0 | wound | 第 4 轮 · 预告 | 否 | 否 | 2 | 9:00 |
| expert | 0 | shock_paranoia | 第 5 轮 · 稳定 | 否 | 是 | 2 | 10:33 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:26 |
| expert | 0 | atk_tracer | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:12 |
| expert | 0 | corrode | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:12 |
| expert | 0 | contact_reaper | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:14 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:15 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 5:31 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:50 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:38 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:05 |
| expert | 0 | contact_founder | 第 3 轮 · 稳定 | 否 | 否 | 1 | 7:55 |
| expert | 0 | contact_slider | 第 3 轮 · 收缩 | 否 | 是 | 1 | 7:06 |
| expert | 0 | nest | 第 3 轮 · 预告 | 否 | 否 | 1 | 6:20 |
| expert | 0 | contact_reaper | 第 3 轮 · 收缩 | 否 | 否 | 1 | 6:36 |
| expert | 0 | contact_tracer | 第 2 轮 · 稳定 | 否 | 否 | 1 | 5:52 |
| expert | 0 | contact_tracer | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:16 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 是 | 1 | 7:20 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 78 / 106 | 131 / 281 | 0 / 4 | 314 / 423 | 28 / 39 |
| expert | 0 | 14 | 8:00–10:00 | 67 / 91 | 20 / 27 | 0 / 0 | 364 / 416 | 29 / 33 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 26 | 392 | 0.0 | 1.7 / 0.7% | 0.5 / 1.5% | 0.0 / 0.0% | 0.2 |
| expert | 0 | 胜 | 6 | 687 | 0.2 | 0.0 / 0.0% | 3.3 / 6.0% | 0.0 / 0.0% | 0.7 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 10s / 10s（32/32） | 14 / 52 | 0 | bone/slider/stone ×16；bone/slider ×16 |
| expert | 2 | 32 | 2:45 | 20 | 8s / 8s（32/32） | 13 / 46 | 0 | bone/slider ×16；bone/slider/stone ×16 |
| expert | 3 | 29 | 4:27 | 25 | 12s / 10s（29/29） | 20 / 103 | 0 | bone/floater/runner/slider ×12；bone/offspring/slider/stone ×7；bone/slider/stone ×6 |
| expert | 4 | 27 | 5:17 | 36 | 14s / 13s（23/27） | 34 / 116 | 5 | bone/reaper/runner/slider/tracer ×11；bone/floater/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×7 |
| expert | 5 | 22 | 6:18 | 39 | 14s / 12s（21/22） | 25 / 117 | 2 | bone/offspring/reaper/runner/slider/spitter/tracer ×8；bone/floater/reaper/runner/slider/tracer ×7；bone/reaper/runner/slider/tracer ×5 |
| expert | 6 | 16 | 7:50 | 27 | 9s / 8s（14/16） | 31 / 124 | 2 | bone/founder/nest/runner/slider/spitter/stone/tracer ×6；bone/founder/nest/offspring/runner/slider/stone/tracer ×6；bone/floater/founder/nest/runner/slider/stone/tracer ×4 |
| expert | 7 | 13 | 9:01 | 21 | 10s / 10s（12/13） | 36 / 154 | 1 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×7；bone/floater/offspring/reaper/runner/slider/spitter/stone ×3；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×3 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+ling | 32 | 18% | 8:00 / 3:39 | 0.0 / - | 8 / 16 / 23 / 22 | 26% | 79% | 66 | 1346 | 散射 19% 弹匣倾泻 7% 过载模式 6% 终结技·exusiai·爆裂弹 5% | 自身回复 43% 拾取 18% 补给 18% (603 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+ling | 32 | 18% | 8:00 / 3:39 | 100% | 90% | 1:15 | 0:49 / 2:29 | 1.7 / 43s | 42.6 | 85 | 6 | 0 | 3 | 22% / 14559 | shock_paranoia |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 11.1 | 5.4% | class 77/30 control 22/11 economy 111/45 general 262/103 heal 33/9 melee 39/13 multi 123/50 shield 28/18 summon 57/23 survival 128/43 weak 20/9 | 0 |
| 合计 | | | | | class 77/30 control 22/11 economy 111/45 general 262/103 heal 33/9 melee 39/13 multi 123/50 shield 28/18 summon 57/23 survival 128/43 weak 20/9 | |

拿取最多（出现 / 拿取）：银餐叉 32/11，洁白的舞鞋 23/10，显圣吊坠 31/10，“多功能”发夹 10/10，损坏的左轮弹巢 12/10，穿甲弹 25/9，衍生者终端-超级改 20/6，摩根队长佳酿 12/6，解约协议 7/6，《旧高卢地名源流考》 11/5，堡垒协议-方阵 12/5，判官经文布 6/4
