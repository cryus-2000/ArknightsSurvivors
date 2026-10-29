# balance gm_B_expert_m0_s5 1029_1518

args: `--preset starts --bot expert --seed0 5 --seeds 4 --jobs 4 --extra --tier=0 --tide=0 --tag gm_B_expert_m0_s5 --out build/gm/B_s5`

### 最终 Boss（按类型；上面的「终局」列是四种混算）

| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / P90 / 最短–最长（出现起算） | 中 / P90（可受伤起算） | 阶段护盾秒 / 过卡点数 均 | 未击杀时剩余血量 |
|---|---|---|---|---|---|---|---|---|
| expert | 偏执泡影 | standard 1 | 1 | 1 | 131s / 131s / 131s / 131–131s | 131s / 131s | 11.8 / 3.0 | - |
| expert | 最后的骑士 | knight 1 | 1 | 0 | - | - | 0.0 / 0.0 | 94% |

### 中期 Boss（按类型）

| 机器人 | 中期 Boss | 出场 | 击杀 | 用时中位 | on_boss 中位 | 周围敌人 均 | 慌乱次数 均 | 慌乱期间掉血 均 |
|---|---|---|---|---|---|---|---|---|
| expert | 塑路者 | 13 | 9 | 99s | 0.20 | 10 | - | - |
| expert | 圣徒卡门 | 11 | 5 | 91s | 0.18 | 8 | - | - |
| expert | 接潮主教 | 4 | 1 | 85s | 0.06 | 14 | 2.0 | 12% |
| expert | 接潮斥亡体 | 3 | 1 | 85s | 0.06 | 14 | - | - |
| expert | 圣徒伊比利亚 | 1 | 1 | 99s | 0.13 | 10 | - | - |
| expert | 接潮蔑死体 | 1 | 0 | - | 0.04 | 26 | - | - |

### 控制（按来源，每局平均）

| 机器人 | 难度 | 局数 | 奠基者 冻结次 / 秒 / 挣脱 / 减速秒 | 漂移体 冻结次 / 秒 / 挣脱 / 减速秒 | Boss 冻结次 / 秒 / 挣脱 / 减速秒 | 其他 冻结次 / 秒 / 挣脱 / 减速秒 | 任何减速秒 |
|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 0 | 0.0 / 0.0 / 0.0 / 11 | 0.0 / 0.0 / 0.0 / 0 | 11 |

### 难度 / 缩圈 / 同屏峰值

#### 前 3 分钟

| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |
|---|---|---|---|---|---|
| expert | 0 | 28 | 17% | 255 / 246 | 74% |

#### 死因 × 缩圈阶段 × Boss 在场（失败的局）

| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |
|---|---|---|---|---|---|---|---|
| expert | 0 | boss_carmen | 第 1 轮 · 稳定 | 否 | 是 | 4 | 6:22 |
| expert | 0 | wound | 第 1 轮 · 稳定 | 否 | 是 | 2 | 7:31 |
| expert | 0 | corrode | 第 1 轮 · 稳定 | 否 | 否 | 2 | 4:48 |
| expert | 0 | wound | 第 2 轮 · 收缩 | 否 | 是 | 2 | 7:59 |
| expert | 0 | contact_tracer | 第 1 轮 · 收缩 | 否 | 否 | 2 | 2:53 |
| expert | 0 | mire | 第 2 轮 · 预告 | 否 | 否 | 1 | 5:30 |
| expert | 0 | contact_founder | 第 3 轮 · 稳定 | 否 | 是 | 1 | 10:13 |
| expert | 0 | mire | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:44 |
| expert | 0 | atk_tracer | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:47 |
| expert | 0 | contact_reaper | 第 2 轮 · 稳定 | 否 | 否 | 1 | 6:04 |
| expert | 0 | contact_founder | 第 2 轮 · 预告 | 否 | 否 | 1 | 4:55 |
| expert | 0 | corrode | 未缩圈 | 否 | 否 | 1 | 2:15 |
| expert | 0 | wound | 第 3 轮 · 稳定 | 否 | 否 | 1 | 9:35 |
| expert | 0 | corrode | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:55 |
| expert | 0 | corrode | 第 1 轮 · 预告 | 否 | 否 | 1 | 2:30 |
| expert | 0 | atk_reaper | 第 1 轮 · 稳定 | 否 | 否 | 1 | 6:40 |
| expert | 0 | atk_tracer | 第 1 轮 · 稳定 | 否 | 是 | 1 | 4:07 |
| expert | 0 | shock_path | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:45 |
| expert | 0 | dark | 第 1 轮 · 稳定 | 否 | 是 | 1 | 3:34 |
| expert | 0 | contact_slider | 第 2 轮 · 收缩 | 否 | 否 | 1 | 6:22 |

#### 同屏数量峰值（每局峰值的 平均 / 最大）

| 机器人 | 难度 | 局数 | 范围 | 敌人 | 敌方弹幕（含抛射） | 我方子弹 | 特效 | 飘字 |
|---|---|---|---|---|---|---|---|---|
| expert | 0 | 28 | 全程 | 90 / 196 | 58 / 159 | 2 / 8 | 257 / 442 | 24 / 48 |
| expert | 0 | 6 | 8:00–10:00 | 70 / 99 | 70 / 99 | 1 / 5 | 316 / 402 | 24 / 48 |

### 大群（按第几次）

| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |
|---|---|---|---|---|---|---|---|---|
| expert | 1 | 28 | 1:15 | 15 | 13s / 12s（28/28） | 25 / 66 | 0 | bone/slider/stone ×22；bone/slider ×6 |
| expert | 2 | 26 | 2:45 | 20 | 11s / 10s（23/26） | 46 / 123 | 3 | bone/slider ×21；bone/slider/stone ×5 |
| expert | 3 | 12 | 5:25 | 25 | 19s / 12s（10/12） | 16 / 49 | 2 | bone/reaper/runner/slider/tracer ×6；bone/floater/reaper/runner/slider/tracer ×2；bone/offspring/slider/stone ×2 |
| expert | 4 | 11 | 5:37 | 37 | 27s / 18s（9/11） | 40 / 144 | 3 | bone/offspring/reaper/runner/slider/spitter/tracer ×6；bone/reaper/runner/slider/tracer ×4；bone/floater/reaper/runner/slider/tracer ×1 |
| expert | 5 | 9 | 6:16 | 40 | 18s / 17s（5/9） | 42 / 99 | 3 | bone/floater/reaper/runner/slider/tracer ×4；bone/offspring/reaper/runner/slider/spitter/tracer ×3；bone/reaper/runner/slider/tracer ×2 |
| expert | 6 | 3 | 8:43 | 23 | 17s / 16s（3/3） | 27 / 39 | 0 | bone/floater/offspring/reaper/runner/slider/spitter/stone ×2；bone/founder/nest/runner/slider/spitter/stone/tracer ×1 |

| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 7:54 / 3:44 | 0.0 / - | 8 / 15 / 22 / 21 | 89% | 58% | 73 | 1180 | 余震 33% 饱和复仇 14% 殉爆 7% 炮击 7% | 自身回复 27% 塞雷娅 23% 补给 15% (775 / 0.0) | contact_tracer |
| [expert] eyjafjalla | 4 | 0% | 4:00 / 2:15 | 0.0 / - | 8 / 15 / 0 / 13 | - | 33% | 32 | 508 | 熔岩弹 32% 火星 8% 狐火 5% 点燃弹 5% | 自身回复 31% 补给 27% 拾取 16% (437 / 0.0) | atk_tracer |
| [expert] skadi | 4 | 0% | 7:26 / 5:37 | 0.0 / - | 8 / 15 / 20 / 19 | 7% | 41% | 46 | 988 | 大剑 28% 余震 12% 跃浪 6% 狐火 6% | 自身回复 36% 流明 18% 塞雷娅 14% (1188 / 0.0) | boss_carmen |
| [expert] mizuki | 4 | 0% | 5:03 / 2:30 | 0.0 / - | 8 / 14 / 0 / 14 | 85% | 33% | 24 | 625 | 伞击 21% 触手 14% 狐火 7% 大剑 7% | 水月 62% 自身回复 18% 补给 6% (961 / 0.0) | contact_tracer |
| [expert] saria | 4 | 0% | 5:31 / 3:34 | 0.0 / - | 7 / 14 / 19 / 15 | 81% | 25% | 10 | 652 | 拳击 15% 大剑 11% 刺剑 9% 秘杖·速充模式 8% | 塞雷娅 58% 自身回复 19% 补给 7% (948 / 0.0) | boss_carmen |
| [expert] kaltsit | 4 | 0% | 6:11 / 2:52 | 0.0 / - | 8 / 14 / 20 / 16 | 54% | 50% | 0 | 799 | Mon3tr 30% Mon3tr · 真伤 10% 刺剑 9% 余震 7% | 凯尔希 37% 自身回复 22% 结构加固 15% (1077 / 0.0) | contact_tracer |
| [expert] suzuran | 4 | 0% | 4:38 / 2:55 | 0.0 / - | 8 / 14 / 0 / 14 | 51% | 41% | 17 | 588 | 狐火 42% 狐火点点 8% 余震 6% 言 5% | 自身回复 27% 铃兰 19% 补给 13% (586 / 0.0) | contact_tracer |

### 机器人指标（docs/29）

| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [expert] wisadel | 4 | 25% | 7:54 / 3:44 | 100% | 75% | 0:57 | 0:49 / 3:38 | 1.5 / 84s | 83.7 | 104 | 10 | 0 | 3 | 69% / 30212 | mire |
| [expert] eyjafjalla | 4 | 0% | 4:00 / 2:15 | 50% | 25% | 1:04 | 0:48 / 2:37 | 0.5 / 53s | 27.7 | 137 | 10 | 0 | 2 | 59% / 8674 | contact_reaper |
| [expert] skadi | 4 | 0% | 7:26 / 5:37 | 100% | 100% | 1:04 | 0:47 / 2:51 | 0.8 / 100s | 103.7 | 174 | 29 | 19 | 3 | 51% / 18169 | wound |
| [expert] mizuki | 4 | 0% | 5:03 / 2:30 | 75% | 50% | 1:07 | 0:49 / 3:31 | 0.5 / 156s | 54.9 | 181 | 5 | 34 | 2 | 39% / 8014 | corrode |
| [expert] saria | 4 | 0% | 5:31 / 3:34 | 100% | 50% | 1:20 | 0:54 / 2:02 | 0.2 / 90s | 70.2 | 156 | 13 | 60 | 3 | 25% / 3871 | boss_carmen |
| [expert] kaltsit | 4 | 0% | 6:11 / 2:52 | 75% | 75% | 1:05 | 0:52 / 2:47 | 0.5 / 132s | 85.0 | 170 | 10 | 34 | 3 | 50% / 13645 | wound |
| [expert] suzuran | 4 | 0% | 4:38 / 2:55 | 50% | 50% | 1:04 | 0:49 / 3:25 | 0.2 / 138s | 41.9 | 130 | 5 | 22 | 2 | 50% / 7375 | contact_tracer |

### 藏品（docs/35）

| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |
|---|---|---|---|---|---|---|
| expert | eyjafjalla | 4 | 2.0 | 0.0% | class 4/1 economy 2/1 general 8/0 heal 1/0 melee 1/0 multi 10/4 shield 2/1 summon 1/1 survival 2/0 weak 4/0 | 0 |
| expert | kaltsit | 4 | 3.5 | 0.6% | class 7/0 economy 6/1 general 5/2 heal 10/4 melee 2/1 multi 2/1 shield 1/1 summon 4/0 survival 7/3 weak 2/1 | 0 |
| expert | mizuki | 4 | 3.0 | 0.0% | class 1/1 economy 7/4 general 9/5 melee 2/0 multi 1/0 summon 3/1 survival 2/1 weak 3/0 | 0 |
| expert | saria | 4 | 1.8 | 1.2% | class 3/1 control 1/1 economy 3/3 general 1/0 heal 1/0 melee 2/1 multi 1/0 shield 1/0 summon 2/0 survival 1/0 weak 2/1 | 0 |
| expert | skadi | 4 | 4.8 | 1.1% | class 4/2 control 4/1 economy 4/2 general 16/5 heal 3/0 melee 12/4 multi 3/0 shield 1/1 summon 1/1 survival 5/1 weak 3/2 | 0 |
| expert | suzuran | 4 | 3.5 | 0.0% | class 4/2 control 5/0 economy 2/1 general 9/7 melee 1/0 multi 2/1 shield 1/1 summon 2/0 survival 7/2 | 0 |
| expert | wisadel | 4 | 7.5 | 3.3% | class 3/0 control 3/0 economy 7/1 general 22/8 heal 4/1 melee 4/1 multi 13/8 shield 4/3 summon 2/1 survival 19/5 weak 4/2 | 0 |
| 合计 | | | | | class 26/7 control 13/2 economy 31/13 general 70/27 heal 19/5 melee 24/7 multi 32/14 shield 10/7 summon 15/4 survival 43/12 weak 18/6 | |

拿取最多（出现 / 拿取）：穿甲弹 6/4，海潮的气息 0/4，三钥协定 5/3，洁白的舞鞋 8/3，显圣吊坠 11/3，《光耀卡西米尔》 3/3，特级馥郁咖啡豆 4/3，“多功能”发夹 4/2，海程 5/2，“黑夜呢喃” 9/2，银餐叉 5/2，损坏的左轮弹巢 2/2
