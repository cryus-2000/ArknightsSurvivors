# balance op-ling-exu-1118c-angelina 1118_0028

args: `--squad exusiai,angelina --bot expert --seeds 32 --seed0 1 --nocache --jobs 16 --tag op-ling-exu-1118c-angelina --out build/cloud/op-ling-exu-1118c/exu_angelina --extra=--maxt=1000 --tier=0`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 19 | 19 | 10 | 100s / 100s / 147s / 60–147s | 100s / 147s | 3.8 / 2.7 | 36% |
| expert | 最后的骑士 | knight 4 | 4 | 2 | 60s / 60s / 70s / 50–70s | 60s / 70s | 2.3 / 1.2 | 63% |
| expert | 伊莎玛拉 | deep 1 | 1 | 1 | 37s / 37s / 37s / 37–37s | 37s / 37s | 7.5 / 2.0 | - |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 圣徒卡门 | 21 | 17 | 55s | 0.41 | 5 | - | - |
| expert | 接潮主教 | 17 | 17 | 75s | 0.13 | 7 | 1.2 | 18% |
| expert | 塑路者 | 15 | 14 | 62s | 0.54 | 5 | - | - |
| expert | 接潮斥亡体 | 11 | 11 | 87s | 0.11 | 8 | - | - |
| expert | 接潮蔑死体 | 6 | 6 | 52s | 0.17 | 5 | - | - |
| expert | 圣徒伊比利亚 | 3 | 3 | 74s | 0.22 | 9 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 0.0 / 0.0 / 0.0 / 1 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 10 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 胜负构成（超时 = 满血 Boss 未打完，照算失败，死因统计不含）

| 机器人 | 难度 | 局数 | 胜 | 死亡 | 超时（满血 Boss 未打完） | 超时时 Boss 剩余血 均 |
|---|---|---|---|---|---|---|
| expert | 0 | 32 | 40% | 59% | 0% (0) | - |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 32 | 3% | 94 / 92 | 94% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | bullet | 第 4 轮 · 稳定 | 否 | 是 | 3 | 10:40 |
| expert | 0 | corrode | 第 4 轮 · 稳定 | 否 | 是 | 3 | 11:19 |
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 2 | 5:12 |
| expert | 0 | boss_knight_boss | 第 4 轮 · 稳定 | 否 | 是 | 2 | 10:19 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 是 | 2 | 4:06 |
| expert | 0 | wound | 第 3 轮 · 收缩 | 否 | 否 | 1 | 9:26 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:14 |
| expert | 0 | corrode | 第 5 轮 · 稳定 | 否 | 是 | 1 | 10:46 |
| expert | 0 | corrode | 第 2 轮 · 预告 | 否 | 否 | 1 | 6:24 |
| expert | 0 | shock_paranoia | 第 4 轮 · 稳定 | 否 | 是 | 1 | 10:26 |
| expert | 0 | corrode | 第 3 轮 · 稳定 | 否 | 是 | 1 | 11:39 |
| expert | 0 | bullet | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:00 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 32 | 全程 | 78 / 106 | 175 / 320 | 1 / 10 | 325 / 405 | 29 / 44 |
| expert | 0 | 25 | 8:00–10:00 | 74 / 93 | 37 / 128 | 0 / 5 | 342 / 402 | 28 / 44 |

### 2 秒上限 / Boss 保护 / 单次上限触发（--telemetry=full）

| 机器人 | 难度 | 结果 | 局数 | 受击笔数 均 | 全免(截到0)笔数 均 | 任意2秒上限 触发笔数 / 截掉量占比 | Boss保护 触发笔数 / 占比 | 单次上限 触发笔数 / 占比 | 截掉一半以上笔数 均 |
|---|---|---|---|---|---|---|---|---|---|
| expert | 0 | 失败 | 19 | 429 | 0.3 | 0.7 / 0.2% | 2.3 / 5.5% | 0.0 / 0.0% | 0.5 |
| expert | 0 | 胜 | 13 | 562 | 0.7 | 2.2 / 0.1% | 3.8 / 7.2% | 0.0 / 0.0% | 0.9 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 32 | 1:15 | 15 | 11s / 11s（32/32） | 15 / 51 | 0 | bone/slider/stone ×18；bone/slider ×14 |
| expert | 2 | 31 | 2:45 | 20 | 9s / 9s（31/31） | 12 / 84 | 0 | bone/slider ×17；bone/slider/stone ×14 |
| expert | 3 | 26 | 4:48 | 24 | 12s / 11s（25/26） | 13 / 51 | 1 | bone/slider/stone ×6；bone/floater/reaper/runner/slider/tracer ×6；bone/floater/runner/slider ×5 |
| expert | 4 | 25 | 5:36 | 37 | 14s / 13s（25/25） | 14 / 74 | 0 | bone/reaper/runner/slider/tracer ×11；bone/offspring/reaper/runner/slider/spitter/tracer ×10；bone/floater/reaper/runner/slider/tracer ×4 |
| expert | 5 | 25 | 6:36 | 40 | 16s / 13s（25/25） | 17 / 94 | 0 | bone/offspring/reaper/runner/slider/spitter/tracer ×9；bone/floater/reaper/runner/slider/tracer ×6；bone/reaper/runner/slider/tracer ×5 |
| expert | 6 | 24 | 8:23 | 25 | 11s / 11s（22/24） | 23 / 192 | 1 | bone/floater/founder/nest/runner/slider/stone/tracer ×8；bone/founder/nest/runner/slider/spitter/stone/tracer ×5；bone/founder/nest/offspring/runner/slider/stone/tracer ×4 |
| expert | 7 | 12 | 9:08 | 22 | 11s / 10s（12/12） | 18 / 172 | 0 | bone/floater/founder/nest/reaper/runner/slider/stone/tracer ×6；bone/floater/offspring/reaper/runner/slider/spitter/stone ×4；bone/floater/founder/nest/reaper/runner/slider/spitter/stone ×2 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 32 | 40% | 9:40 / 2:14 | 0.0 / - | 8 / 15 / 23 / 25 | 27% | 84% | 65 | 1536 | 散射 18% 真实 10% 弹匣倾泻 8% 终结技·exusiai·爆裂弹 5% | 自身回复 40% 补给 22% 拾取 18% (698 / 0.0) | bullet |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] exusiai+angelina | 32 | 40% | 9:40 / 2:14 | 96% | 87% | 1:17 | 0:47 / 3:10 | 2.1 / 70s | 41.5 | 81 | 9 | 0 | 4 | 22% / 17409 | corrode |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | exusiai | 32 | 14.2 | 11.3% | class 99/31 control 37/24 economy 113/50 general 322/135 heal 49/14 melee 59/19 multi 187/67 shield 52/27 summon 64/28 survival 145/50 weak 33/10 | 0 |
| 合计 | | | | | class 99/31 control 37/24 economy 113/50 general 322/135 heal 49/14 melee 59/19 multi 187/67 shield 52/27 summon 64/28 survival 145/50 weak 33/10 | |

拿取最多（出现 / 拿取）：显圣吊坠 48/16，损坏的左轮弹巢 21/14，洁白的舞鞋 34/13，穿甲弹 42/13，银餐叉 42/11，“多功能”发夹 18/11，《旧高卢地名源流考》 23/10，衍生者终端-超级改 21/7，“绝唱” 6/7，散轶诗简 14/6，高闪相机 6/6，残破合影 12/5
