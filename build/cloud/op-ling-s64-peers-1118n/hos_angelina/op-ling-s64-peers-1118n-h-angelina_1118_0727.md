# balance op-ling-s64-peers-1118n-h-angelina 1118_0727

args: `--squad hoshiguma,angelina --bot expert --seeds 32 --seed0 33 --nocache --jobs 16 --tag op-ling-s64-peers-1118n-h-angelina --out build/cloud/op-ling-s64-peers-1118n/hos_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 24 | 24 | 19 | 132s / 128s / 198s / 48–277s | 128s / 198s | 3.7 / 3.0 | 35% |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 77s / 77s / 95s / 59–95s | 77s / 95s | 3.0 / 2.0 | 15% |
| expert | 伊祖米克 | resolve 3 | 3 | 3 | 73s / 83s / 85s / 51–85s | 63s / 65s | 1.5 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 26 | 26 | 80s | 0.48 | 8 | - | - |
| expert | 圣徒卡门 | 17 | 16 | 60s | 0.29 | 8 | - | - |
| expert | 接潮主教 | 14 | 14 | 70s | 0.12 | 8 | 1.2 | 21% |
| expert | 接潮蔑死体 | 9 | 9 | 71s | 0.15 | 9 | - | - |
| expert | 接潮斥亡体 | 5 | 5 | 67s | 0.15 | 9 | - | - |
| expert | 圣徒伊比利亚 | 5 | 5 | 59s | 0.24 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 12 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 75% | 25% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 0% | 90 / 82 | 97% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 11:12 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 2 | 10:52 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 12:52 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 5:35 |
| expert | 0 | atk_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:05 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 92 / 120 | 222 / 320 | 1 / 10 | 408 / 435 | 45 / 48 |
| expert | 0 | 30 | 8:00–10:00 | 80 / 112 | 28 / 92 | 1 / 10 | 399 / 433 | 40 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 8 | 408 | 0.2 | 0.0 / 0.0% | 1.0 / 1.5% | 0.0 / 0.0% | 0.1 |
| expert | 0 | 胜 | 24 | 549 | 0.2 | 0.1 / 0.0% | 1.4 / 3.2% | 0.0 / 0.0% | 0.5 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 11s（32/32） | 11 / 36 | 0 | bone/slider ×19；bone/slider/stone ×13 |
| expert | 2 | 32 | 2:45 | 20 | 9s / 9s（32/32） | 8 / 30 | 0 | bone/slider/stone ×19；bone/slider ×13 |
| expert | 3 | 31 | 5:07 | 24 | 16s / 11s（31/31） | 11 / 60 | 0 | bone/floater/reaper/runner/slider/tracer ×11；bone/offspring/reaper/runner/slider/spitter/tracer ×7；bone/reaper/runner/slider/tracer ×6 |
| expert | 4 | 31 | 5:57 | 38 | 18s / 14s（30/31） | 13 / 126 | 1 | bone/reaper/runner/slider/tracer ×9；bone/floater/reaper/runner/slider/tracer ×9；bone/offspring/reaper/runner/slider/spitter/tracer ×9 |
| expert | 5 | 30 | 7:09 | 39 | 19s / 14s（30/30） | 6 / 41 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/reaper/runner/slider/tracer ×6 |
| expert | 6 | 29 | 8:21 | 26 | 10s / 10s（29/29） | 5 / 45 | 0 | bone/founder/nest/offspring/runner/slider/stone/tracer ×7；bone/floater/founder/nest/runner/slider/stone/tracer ×7；bone/founder/nest/runner/slider/spitter/stone/tracer ×7 |
| expert | 7 | 18 | 9:06 | 21 | 11s / 10s（18/18） | 2 / 29 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×8；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×6；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×4 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 32 | 75% | 11:30 / 5:35 | 0.0 / - | 8 / 15 / 22 / 27 | 13% | 96% | 75 | 1767 | 举盾反击 12% 真实 11% 剑气 7% 双重引力 6% | 自身回复 41% 补给 23% 拾取 13% (681 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+angelina | 32 | 75% | 11:30 / 5:35 | 100% | 100% | 1:19 | 0:48 / 3:24 | 2.3 / 68s | 36.8 | 61 | 6 | 3 | 5 | 28% / 29955 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 32 | 16.4 | 12.9% | class 127/43 control 48/22 economy 155/42 general 419/199 heal 50/14 melee 223/84 multi 37/10 shield 59/26 summon 55/21 survival 160/50 weak 41/14 | 0 |
| 合计 | | | | | class 127/43 control 48/22 economy 155/42 general 419/199 heal 50/14 melee 223/84 multi 37/10 shield 59/26 summon 55/21 survival 160/50 weak 41/14 | |

拿取最多（出现 / 拿取）：贵族刺剑 28/18，漆黑的舞鞋 37/15，老近卫军之锋 20/14，赶车夫的长鞭 42/13，锈蚀刀片 48/12，皇帝的恩宠 48/12，《旧高卢地名源流考》 25/10，“多功能”发夹 17/8，疗养体验卡 11/7，《光耀卡西米尔》 8/6，铁卫-临时要塞 7/6，支柱-援护 14/6
