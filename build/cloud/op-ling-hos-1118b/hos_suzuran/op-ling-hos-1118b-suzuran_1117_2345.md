# balance op-ling-hos-1118b-suzuran 1117_2345

args: `--squad hoshiguma,suzuran --bot expert --seeds 16 --seed0 1 --nocache --jobs 16 --tag op-ling-hos-1118b-suzuran --out build/cloud/op-ling-hos-1118b/hos_suzuran --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 8 | 8 | 5 | 96s / 82s / 135s / 65–135s | 82s / 135s | 4.8 / 3.0 | 31% |
| expert | 伊祖米克 | resolve 3 | 3 | 3 | 98s / 71s / 154s / 69–154s | 51s / 134s | 0.0 / 2.0 | - |
| expert | 最后的骑士 | knight 3 | 3 | 2 | 93s / 93s / 117s / 70–117s | 94s / 117s | 3.4 / 2.0 | 37% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 47s / 47s / 47s / 47–47s | 47s / 47s | 9.1 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 12 | 11 | 48s | 0.56 | 7 | - | - |
| expert | 接潮主教 | 11 | 11 | 47s | 0.17 | 11 | 1.0 | 14% |
| expert | 塑路者 | 7 | 7 | 47s | 0.62 | 7 | - | - |
| expert | 接潮蔑死体 | 6 | 6 | 47s | 0.17 | 11 | - | - |
| expert | 接潮斥亡体 | 5 | 5 | 50s | 0.16 | 11 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 43s | 0.35 | 6 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 0.0 / 0.0 / 0.0 / 3 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 14 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 16 | 68% | 31% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 16 | 0% | 86 / 89 | 99% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:45 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 1 | 11:03 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:23 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 11:21 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 16 | 全程 | 95 / 115 | 186 / 286 | 9 / 12 | 390 / 424 | 44 / 48 |
| expert | 0 | 15 | 8:00–10:00 | 78 / 97 | 30 / 59 | 6 / 10 | 392 / 424 | 41 / 48 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 5 | 891 | 0.0 | 0.0 / 0.0% | 4.2 / 9.8% | 0.0 / 0.0% | 0.4 |
| expert | 0 | 胜 | 11 | 772 | 0.0 | 1.2 / 0.0% | 0.5 / 1.5% | 0.0 / 0.0% | 0.1 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 16 | 1:15 | 15 | 11s / 11s（16/16） | 12 / 36 | 0 | bone/slider/stone ×9；bone/slider ×7 |
| expert | 2 | 16 | 2:45 | 20 | 9s / 9s（16/16） | 6 / 21 | 0 | bone/slider ×9；bone/slider/stone ×7 |
| expert | 3 | 15 | 4:29 | 25 | 11s / 10s（15/15） | 10 / 49 | 0 | bone/floater/runner/slider ×6；bone/slider/stone ×4；bone/floater/reaper/runner/slider/tracer ×2 |
| expert | 4 | 15 | 5:19 | 36 | 16s / 17s（15/15） | 7 / 36 | 0 | bone/floater/reaper/runner/slider/tracer ×6；bone/offspring/reaper/runner/slider/spitter/tracer ×5；bone/reaper/runner/slider/tracer ×4 |
| expert | 5 | 15 | 6:19 | 39 | 21s / 17s（15/15） | 14 / 106 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/floater/reaper/runner/slider/tracer ×4；bone/reaper/runner/slider/tracer ×4 |
| expert | 6 | 15 | 7:59 | 27 | 12s / 12s（15/15） | 10 / 52 | 0 | bone/founder/nest/runner/slider/spitter/stone/tracer ×9；bone/floater/founder/nest/runner/slider/stone/tracer ×4；bone/founder/nest/offspring/runner/slider/stone/tracer ×2 |
| expert | 7 | 14 | 9:07 | 22 | 12s / 11s（14/14） | 12 / 93 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×7；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×5；bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 16 | 68% | 10:56 / 4:23 | 0.0 / - | 8 / 16 / 22 / 27 | 19% | 95% | 77 | 1852 | 举盾反击 13% 狐火 9% 剑气 9% 真实 7% | 自身回复 36% 补给 20% 拾取 13% (722 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] hoshiguma+suzuran | 16 | 68% | 10:56 / 4:23 | 100% | 93% | 1:08 | 0:46 / 2:56 | 2.6 / 49s | 63.8 | 70 | 6 | 0 | 5 | 28% / 31556 | shock_paranoia |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | hoshiguma | 16 | 16.6 | 9.9% | class 59/24 control 24/11 economy 85/25 general 211/96 heal 28/8 melee 104/36 multi 25/9 shield 26/15 summon 23/11 survival 87/24 weak 12/6 | 0 |
| 合计 | | | | | class 59/24 control 24/11 economy 85/25 general 211/96 heal 28/8 melee 104/36 multi 25/9 shield 26/15 summon 23/11 survival 87/24 weak 12/6 | |

拿取最多（出现 / 拿取）：赶车夫的长鞭 19/8，皇帝的恩宠 23/7，《旧高卢地名源流考》 11/7，锈蚀刀片 25/7，老近卫军之锋 8/6，“多功能”发夹 11/5，漆黑的舞鞋 14/4，国王的枝条 5/4，深蓝回忆 0/4，贵族刺剑 15/4，赤金的远征 7/3，“国王的水晶” 4/3
