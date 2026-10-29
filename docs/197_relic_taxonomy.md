# 197 藏品分类统一成一套（映射表，待审）

- 状态：**映射表待协调人审**，审过再动数据。分支 `claude/relic-taxonomy`（自 `claude/integ-1029` ba5c4d658）。
- 来源：用户 10-29 批准设计总纲第 1 步（藏品分类只留一套，用 docs/181 的 7 条流派）。
- 约束：不改玩法。实现后做云端同种子配对（改前 / 改后，m0、m18 各 56 局），胜率差 <10 点、每局藏品数基本不变才算过。不动 `relic/*`、`shop/*` 数值旋钮。

## 1 现状：5 套并存

| 字段 | 在哪 | 取值 | 谁在读 |
|---|---|---|---|
| `lanes` | relics.json（relic_effects.json 有 18 条覆盖） | docs/35 A–H 8 条 | 抽取流派加权、守护·续航时间系数、主流派、事件对口、诡意行商、机器人选卡、balance_run 流派矩阵、图鉴「流派」行、gen_relic_icons |
| `cat` | relics.json | 17 类（含「需新机制·排异反应」） | 三选一卡名前缀【cat】、卡片配色 / 英文角标（UI.CAT_COL / CAT_EN）、图鉴「原类别」、作战记录、事件交易子选项 |
| `effect_category` | relic_effects.json | 17 类 | 只有图鉴「效果分类」一行 |
| `tags` | relics.json / relic_effects.json | 30 种 | relic_db 的 roll_shop / roll_chest / roll_boss 倾向（**死代码**，只有 test_core、relic_reclassification 测试在调）、机器人（shield / survival）、relic_fx 国王套装（king） |
| 干员 `lanes` + 藏品作用域 `lane:<键>` | characters/*.json、relic_effects.json | docs/181 七条 | affects 卡底标签、combat 流派倍率、vis_growth、relic_fx `_lane_ok` |

另有两套「谁受益」：

- affects.gd：卡底干员标签，已按 7 流派。
- build_affinity.gd：3 条链（control 97/95/96、followup 130/171/234、skill 85/110/111），按干员出手来源推「现在可用 / 培养后」。供卡面说明行、招募保底、商人预告用。

## 2 新的一套

每件藏品只有一个字段 `lane`，取 11 个值之一：

- 7 条流派（docs/181，与干员 `lanes` 同一组键）：`melee` 近战扩域、`multi` 多弹火力、`summon` 召唤驻场、`control` 控场引爆、`weak` 弱点收割、`shield` 护盾反击、`heal` 治疗转伤。
- 4 个非流派组（docs/181 §5「通用、职业、经济、生存各自单列」）：`class` 职业、`general` 通用、`survival` 生存（含灯火）、`economy` 经济（源石锭 + 三选一选项）。

删掉的字段：

- relics.json：`lanes`（A–H）与顶层 `lanes` 名表、`cat`、`tags`。
- relic_effects.json：`lanes` 覆盖、`effect_category` 与 `effect_categories` 名表、`tags`。

国王套装要靠一个标记找同伴，这不是分类：改成显式 `set: "king"`（4 件），relic_fx 读它。

## 3 归类规则（按顺序，先中先得）

1. docs/181 §3 明确改标「通用」的：#65 #103 #104 #112 → `general`。
2. relic_effects 里已有 `lane:<键>` 作用域或 `if.lane` 触发条件（docs/181 已实现）→ 该流派。
3. 结局、遭诅古物 → `general`（稀有度已经区分它们）。
4. 说明里点名流派（「近战扩域干员」「多弹火力干员」「召唤驻场干员」「弱点收割」「控场」）→ 该流派。
5. 按职业生效 → `class`。判定：说明写「先锋 / 近卫 / 重装 / 特种 / 狙击 / 术师 / 医疗 / 辅助干员」，或典训 / 突破 / 协议这类「X-Y」名。docs/181 原则 4：职业件不是流派。
6. 旧 D 且效果分类是弱点 → `weak`。包括 #47 全员弱点，#48 #49 #50 #230 敌人生命；docs/181 §3.5 把它们列在弱点收割下。
7. 旧 A / E 剩下的 → `general`。这些是全队伤害 / 攻速、闪避后增伤、队长生命联动等。
8. 旧 C：效果分类为控制 → `control`；技力循环 / 技能增伤 → `general`。
9. 旧 H 或旧无流派：
   - 护盾 → `shield`；治疗 → `heal`。
   - 减伤 / 生命 / 闪避 / 灯火 → `survival`。
   - 源石锭 / 选项 → `economy`。
   - 成长与招募及其余 → `general`。
10. 旧 G（编队·协同）剩下的 → `general`。旧 F（深蓝·低灯火）→ 灯火件 `survival`，遭诅件 `general`。

结果没有一件归两条流派。

### 需要拍板的边界件

| # | 名称 | 规则给的 | 另一种归法 | 我的倾向 |
|---|---|---|---|---|
| 159 / 160 / 161 | 医者-突破 / 自医 / 妙手 | 159 `heal`（旧 H），160、161 `class` | 三件都 `class`（职业件不动）；或都 `heal`（docs/181 §3.6 把 159、161 列在治疗转伤） | 都 `class`：效果按「医疗干员」生效，和其他职业系列一致 |
| 231 / 233 | 小格兰法洛 / 荣耀套餐 | `control`（旧 C） | `general`：队长受击触发的全场眩晕，不靠控场干员 | `control`：效果就是控制，标签显示控场干员 |
| 191 / 192 | 阿卡胡拉饭碗 / 立体艺术装置 | `heal` | `survival`：一次性回血，不是治疗转伤 | `survival` |
| 204 / 255 | 火油与药膏 / 佣兵保单 | `survival`（灯火） | `general` | 不改 |
| 252 | 刻勋之手 | `general`（击杀累积全队伤害） | `weak`（旧 D） | `general` |
| 169 | 扼喉之手 | `class`（狙击干员斩杀） | `weak` | `class` |

## 4 每个读取方怎么改

| 读取方 | 现在 | 改为 |
|---|---|---|
| `progression.relic_pool_ids` 流派加权 | 已拿 A–G 某流派 n 件 → ×1.3^n（封顶 ×2），H 不计 | 已拿 7 流派或 `class` 某组 n 件 → 同样 ×1.3^n。`general / survival / economy` 不计，与旧 H 一样，免得拿了生存就只剩生存 |
| 同上 守护·续航时间系数 | H 件 3:00 前 ×0.7 → 9:00 ×1.0 | 改为 `shield / heal / survival` 三组 |
| `endings.main_lane` 主流派 | 持有 lanes 计数最多且 ≥3 件；不足时按队长：召唤干员 B、近战职业 A、其余 E | 只数 7 流派；不足 3 件取队长的 `lanes[0]` |
| 事件对口：events_v2 16 处 `lanes`、`relic_lane.lanes`、`lane_event_w`；对口三选一 `lane_bias`；诡意行商前两格 | 读 A–H | 读新键：A→melee、B→summon、C→control、D→weak、E→multi。F/G/H 的事件改填 survival / general / heal，逐条列在实现提交里 |
| `build_affinity` 三条链 | 按干员出手来源推「现在可用 / 培养后」 | 链 = 流派，资格改为「编队有该流派干员」（docs/181 §6.3）。skill 链三件已归 `general`，不再有说明行。招募保底、商人预告跟着读流派 |
| `affects.gd` 卡底「谁受益」 | 7 流派 + 宽泛特征 | 不改。它成为唯一的「谁受益」，build_affinity 的说明行判定改调它 |
| 机器人 `bot.gd`：--lanes 偏好、master 选卡 lane 分、tags shield / survival | A–H、tags | 改读新键；shield / survival 改读 `lane` |
| `relic_fx` 国王套装 | tags 含 king | `set == "king"` |
| `relic_db` roll_shop / roll_chest / roll_boss + profile.affinity | tags 倾向（死代码） | 删，连同 test_core、relic_reclassification 里对它们的调用 |
| 三选一卡名【cat】前缀、`choice_panel` 配色 / 英文角标 | cat 17 类 → UI.CAT_COL / CAT_EN | 前缀改【流派名 / 组名】。配色与英文角标改 11 个键：7 流派沿用 affects 的暖金流派色，4 组用现有灯火 / 生存 / 战斗色 |
| 图鉴 | 「效果分类」「原类别」「流派」三行 | 一行「流派」（或「通用 / 职业 / 生存 / 经济」）；按流派分组留给界面会话 |
| 作战记录、事件交易子选项 | cat | lane 名 |
| `balance_run.py` 流派矩阵 / relic_out | A–H | 新 11 键 |
| `data_lint` | 只查干员 lanes 合法 | 加：每件藏品恰好一个合法 `lane`；不再允许 cat / tags / effect_category |
| `gen_relic_icons.py` | 按 lanes[0] 取图案 | 按 lane；图标不重画 |

## 5 预计对抽取权重的影响

方法：用基线云端 A 组 112 局实际的拿取顺序，在每次拿取时算候选池里各组的抽取份额，旧规则与新规则对比。份额 = 稀有度权重 × 流派加权 × 时间系数；不含护盾保底、核心延后、得偿所愿等其余修正。

| 组 | 旧 | 新（7 流派 + 职业加权，生存三组吃时间系数） |
|---|---|---|
| 通用 | 32.7% | 29.9% |
| 职业 | 24.6% | 26.2% |
| 生存 | 15.9% | 15.0% |
| 经济 | 10.1% | 11.1% |
| 治疗转伤 | 3.7% | 4.3% |
| 近战扩域 | 2.9% | 2.7% |
| 护盾反击 | 2.7% | 3.0% |
| 弱点收割 | 2.5% | 2.7% |
| 召唤驻场 | 2.0% | 2.3% |
| 多弹火力 | 1.8% | 1.9% |
| 控场引爆 | 1.0% | 1.0% |

最大变化是通用 −2.8 点：旧 A / C / G 里的全队件以前会互相加权，现在不加。其余各组变化都在 ±1.6 点内，预计不改玩法。

另有两处会变：

- 机器人 master 选卡按新流派打分，同种子下选卡会不同。配对对照要接受这部分噪声。
- build_affinity 说明行：skill 链三件（85 / 110 / 111）不再有触发说明行；control / followup 的「培养后」改为「编队有本流派干员」。卡面文字有变化，数值不变。

## 6 实现与验收（审过后）

1. 数据：relics.json 写入 `lane`，删除旧字段；relic_effects.json 删除 `lanes` / `effect_category` / `tags`；国王套装四件加 `set`。
2. 代码：按 §4 逐个读取方改；`data_lint` 加检查。
3. 本地只跑相关快检：data_lint、core、relic_impl、relic_reclassification、card_desc、build_affinity、merchant_build_offer、node_cards、event_trade、vis_growth、smoke。
4. 云端同种子配对：改前 = integ-1029 头，改后 = 本分支；starts 7 × seed 1–8，m0 / m18 各 56 局。胜率差 <10 点、每局藏品数基本不变才算过。

## 7 逐件映射（265 件）

| 新分类 | 件数 |
|---|---|
| 近战扩域 `melee` | 6 |
| 多弹火力 `multi` | 5 |
| 召唤驻场 `summon` | 8 |
| 控场引爆 `control` | 7 |
| 弱点收割 `weak` | 7 |
| 护盾反击 `shield` | 10 |
| 治疗转伤 `heal` | 11 |
| 职业 `class` | 51 |
| 通用 `general` | 99 |
| 生存 `survival` | 40 |
| 经济 `economy` | 21 |

### 近战扩域 `melee`（6）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 54 | 皇帝的恩宠 | 基础 | A | 攻击与输出 | damage | 181 已实现作用域 |
| 55 | 贵族刺剑 | 稀有 | A | 攻击与输出 | damage | 181 已实现作用域 |
| 56 | 老近卫军之锋 | 核心 | A | 攻击与输出 | damage | 181 已实现作用域 |
| 63 | 锈蚀刀片 | 基础 | A | 攻击与输出 | damage | 说明点名流派 |
| 64 | 赶车夫的长鞭 | 稀有 | A | 攻击与输出 | range | 181 已实现作用域 |
| 81 | 漆黑的舞鞋 | 稀有 | A | 攻击与输出 | range | 181 已实现作用域 |

### 多弹火力 `multi`（5）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 57 | 显圣吊坠 | 基础 | E | 攻击与输出 | damage | 181 已实现作用域 |
| 58 | 银餐叉 | 稀有 | E | 攻击与输出 | damage | 181 已实现作用域 |
| 59 | 损坏的左轮弹巢 | 核心 | E | 攻击与输出 | damage | 181 已实现作用域 |
| 82 | 洁白的舞鞋 | 稀有 | E | 攻击与输出 | range | 181 已实现作用域 |
| 265 | 穿甲弹 | 稀有 | E | 攻击与输出 | range | 说明点名流派 |

### 召唤驻场 `summon`（8）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 80 | 海程 | 稀有 | B | 攻击与输出 | followup | 181 已实现作用域 |
| 84 | 几丁质刺刃 | 核心 | B | 追击与控制 | followup | 181 已实现作用域 |
| 129 | 散轶诗简 | 稀有 | B | 追击与控制 | followup | 181 已实现作用域 |
| 130 | 衍生者终端-超级改 | 基础 | C | 追击与控制 | followup | 181 已实现作用域 |
| 170 | 扣挠之手 | 核心 | B | 追击与控制 | followup | 181 已实现作用域 |
| 171 | 炸裂之手 | 核心 | B | 追击与控制 | skill_cycle | 181 已实现作用域 |
| 234 | “岁怒” | 核心 | B | 追击与控制 | followup | 181 已实现作用域 |
| 246 | 无字珊瑚 | 核心 | B/F | 灯火 | followup | 181 已实现作用域 |

### 控场引爆 `control`（7）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 95 | 悬丝傀儡 | 核心 | C | 追击与控制 | control | 旧 C · 控制 |
| 96 | “童趣玩偶” | 升华 | C | 追击与控制 | control | 旧 C · 控制 |
| 97 | 凯旋号角 | 稀有 | C | 追击与控制 | control | 旧 C · 控制 |
| 98 | 高闪相机 | 核心 | C | 追击与控制 | control | 旧 C · 控制 |
| 99 | 精神治疗录像带 | 升华 | C | 追击与控制 | control | 旧 C · 控制 |
| 231 | “小格兰法洛” | 核心 | C | 追击与控制 | control | 旧 C · 控制 |
| 233 | “荣耀套餐” | 核心 | C | 追击与控制 | control | 旧 C · 控制 |

### 弱点收割 `weak`（7）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 45 | 残破合影 | 稀有 | D | 削弱敌人 | weakness | 181 已实现作用域 |
| 46 | 恐鱼干 | 基础 | D | 削弱敌人 | weakness | 181 已实现作用域 |
| 47 | 迷迭香之拥 | 升华 | D | 削弱敌人 | weakness | 旧 D · 弱点 |
| 48 | 镶金骨骰 | 稀有 | D | 削弱敌人 | weakness | 旧 D · 弱点 |
| 49 | “黑夜呢喃” | 基础 | D | 削弱敌人 | weakness | 旧 D · 弱点 |
| 50 | 《大静谧》 | 核心 | D | 削弱敌人 | weakness | 旧 D · 弱点 |
| 230 | “苦痛的快乐” | 稀有 | D | 削弱敌人 | weakness | 旧 D · 弱点 |

### 护盾反击 `shield`（10）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 7 | 特级馥郁咖啡豆 | 稀有 | — | 护盾 | shield | 旧无 · 护盾 |
| 15 | 《杜林地上环游记》 | 基础 | H | 护盾 | shield | 旧 H · 护盾 |
| 16 | 《旧高卢地名源流考》 | 稀有 | — | 护盾 | shield | 旧无 · 护盾 |
| 100 | 皇族金胸针 | 核心 | H | 护盾 | shield | 旧 H · 护盾 |
| 118 | 药枚 | 稀有 | H | 护盾 | shield | 旧 H · 护盾 |
| 193 | “多功能”发夹 | 稀有 | — | 不适用 | shield | 旧无 · 护盾 |
| 199 | 御2 | 基础 | H | 护盾 | shield | 旧 H · 护盾 |
| 200 | 嵌体甲片 | 稀有 | H | 护盾 | shield | 旧 H · 护盾 |
| 202 | “国王的护戒” | 核心 | H | 护盾 | shield | 旧 H · 护盾 |
| 260 | 铁卫-高塔 | 升华 | H | 生存 | shield | 旧 H · 护盾 |

### 治疗转伤 `heal`（11）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 69 | 活玫瑰 | 基础 | H | 生存 | healing | 旧 H · 治疗 |
| 70 | 苍白花冠 | 稀有 | — | 生存 | healing | 旧无 · 治疗 |
| 71 | 涌动之餐 | 核心 | H | 生存 | healing | 旧 H · 治疗 |
| 72 | 演出用香水 | 稀有 | H | 生存 | healing | 旧 H · 治疗 |
| 102 | 食腐者手杖 | 稀有 | H | 生存 | healing | 旧 H · 治疗 |
| 116 | 遥乡之引 | 核心 | H | 生存 | healing | 旧 H · 治疗 |
| 159 | 医者-突破 | 基础 | H | 生存 | healing | 旧 H · 治疗 |
| 191 | 阿卡胡拉饭碗 | 基础 | H | 生存 | healing | 旧 H · 治疗 |
| 192 | 立体艺术装置 | 稀有 | — | 生存 | healing | 旧无 · 治疗 |
| 263 | 血魔的银杯 | 稀有 | H | 生存 | healing | 旧 H · 治疗 |
| 264 | 猎人的口粮 | 基础 | H | 生存 | healing | 旧 H · 治疗 |

### 职业 `class`（51）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 33 | 钝爪-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 34 | 折戟-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 35 | 铁卫-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 36 | 残弩-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 37 | 断杖-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 38 | 支柱-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 39 | 医者-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 40 | 锈刃-典训 | 稀有 | G | 编队协同 | growth | 按职业生效 |
| 106 | 突击协议-利刃 | 基础 | G | 编队协同 | squad | 按职业生效 |
| 107 | 堡垒协议-方阵 | 基础 | G | 编队协同 | squad | 按职业生效 |
| 108 | 远程协议-遥击 | 基础 | G | 编队协同 | squad | 按职业生效 |
| 109 | 破坏协议-压制 | 基础 | G | 编队协同 | squad | 按职业生效 |
| 133 | 钝爪-突破 | 基础 | A | 不适用 | damage | 按职业生效 |
| 134 | 钝爪-爆发 | 稀有 | A | 不适用 | skill_cycle | 按职业生效 |
| 135 | 钝爪-熟稔 | 核心 | A | 不适用 | skill_cycle | 按职业生效 |
| 136 | 钝爪-百战 | 升华 | A | 攻击与输出 | skill_cycle | 按职业生效 |
| 137 | 折戟-突破 | 基础 | A | 不适用 | damage | 按职业生效 |
| 138 | 折戟-锋刃 | 稀有 | A | 攻击与输出 | damage | 按职业生效 |
| 139 | 折戟-浴血 | 稀有 | A | 技能与技力 | skill_cycle | 按职业生效 |
| 140 | 折戟-一夫当关 | 稀有 | A | 不适用 | range | 按职业生效 |
| 141 | 折戟-破釜沉舟 | 核心 | A | 攻击与输出 | damage | 按职业生效 |
| 142 | 铁卫-突破 | 基础 | A | 不适用 | defense | 按职业生效 |
| 143 | 铁卫-侵掠 | 稀有 | A | 攻击与输出 | damage | 按职业生效 |
| 144 | 铁卫-推进 | 核心 | A | 不适用 | damage | 按职业生效 |
| 145 | 铁卫-无锋 | 稀有 | A | 技能与技力 | skill_cycle | 按职业生效 |
| 146 | 铁卫-临时要塞 | 核心 | A | 不适用 | damage | 按职业生效 |
| 147 | 残弩-突破 | 基础 | G | 编队协同 | growth | 按职业生效 |
| 148 | 残弩-百步穿杨 | 基础 | E | 攻击与输出 | damage | 按职业生效 |
| 149 | 残弩-交叉火力 | 基础 | G | 编队协同 | damage | 按职业生效 |
| 150 | 残弩-神速 | 稀有 | G | 编队协同 | attack_speed | 按职业生效 |
| 151 | 断杖-突破 | 基础 | G | 编队协同 | growth | 按职业生效 |
| 152 | 断杖-织法者 | 稀有 | E | 攻击与输出 | damage | 按职业生效 |
| 153 | 断杖-凝神 | 稀有 | G | 编队协同 | damage | 按职业生效 |
| 154 | 断杖-苦难巫咒 | 基础 | G | 编队协同 | damage | 按职业生效 |
| 155 | 支柱-突破 | 基础 | G | 编队协同 | growth | 按职业生效 |
| 156 | 支柱-勤奋 | 基础 | G | 编队协同 | range | 按职业生效 |
| 157 | 支柱-援护 | 稀有 | E | 编队协同 | squad | 按职业生效 |
| 158 | 支柱-枯法 | 稀有 | E | 攻击与输出 | damage | 按职业生效 |
| 163 | 锈刃-突破 | 基础 | A | 攻击与输出 | damage | 按职业生效 |
| 164 | 锈刃-研磨 | 基础 | A | 攻击与输出 | attack_speed | 按职业生效 |
| 165 | 锈刃-单兵 | 稀有 | A | 攻击与输出 | damage | 按职业生效 |
| 166 | 锈刃-可视静谧 | 稀有 | A | 攻击与输出 | dodge | 按职业生效 |
| 167 | 锈刃-神力 | 基础 | A | 攻击与输出 | control | 按职业生效 |
| 168 | 尖刺之手 | 核心 | A | 不适用 | damage | 按职业生效 |
| 169 | 扼喉之手 | 核心 | D/E | 削弱敌人 | weakness | 按职业生效 |
| 173 | 积攒之手 | 稀有 | A | 不适用 | skill_cycle | 按职业生效 |
| 174 | 净尘之手 | 核心 | E | 攻击与输出 | damage | 按职业生效 |
| 175 | 碎靶之手 | 核心 | E | 攻击与输出 | damage | 按职业生效 |
| 256 | 断杖-学识 | 稀有 | G | 编队协同 | damage | 按职业生效 |
| 257 | 断杖-智慧之光 | 核心 | G | 编队协同 | damage | 按职业生效 |
| 258 | 断杖-破解 | 稀有 | E | 攻击与输出 | squad | 按职业生效 |

### 通用 `general`（99）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 1 | 精选兽肉罐头 | 升华 | G | 编队协同 | squad | 旧 G · squad |
| 2 | 凉拌海草 | 基础 | A | 攻击与输出 | attack_speed | 旧 A 但全队 / 队长生效 |
| 3 | 橙味风暴 | 基础 | A | 攻击与输出 | damage | 旧 A 但全队 / 队长生效 |
| 4 | 咖啡平原咖啡糖 | 基础 | A | 攻击与输出 | attack_speed | 旧 A 但全队 / 队长生效 |
| 5 | 尖叫樱桃 | 基础 | A | 攻击与输出 | damage | 旧 A 但全队 / 队长生效 |
| 6 | 皮特水果什锦 | 基础 | — | 生存 | damage | 旧无 · damage |
| 9 | 红色蝴蝶结 | 基础 | G | 不适用 | choice | 旧 G · choice |
| 10 | 独奏八音盒 | 基础 | G | 编队协同 | economy | 旧 G · economy |
| 11 | 源石鸢尾花 | 基础 | G | 编队协同 | economy | 旧 G · economy |
| 14 | 赤金的远征 | 基础 | G | 编队协同 | economy | 旧 G · economy |
| 42 | “静音小队” | 升华 | A | 攻击与输出 | damage | 旧 A 但全队 / 队长生效 |
| 65 | “复仇者” | 核心 | A | 攻击与输出 | damage | 181 改标通用 |
| 66 | 制式防暴用具 | 稀有 | — | 追击与控制 | damage | 旧无 · damage |
| 67 | 皇帝的收藏 | 核心 | — | 追击与控制 | damage | 旧无 · damage |
| 68 | “璀璨悲泣” | 核心 | — | 追击与控制 | damage | 旧无 · damage |
| 76 | 人偶之家 | 基础 | — | 不适用 | growth | 旧无 · 成长 / 招募 |
| 77 | 微缩舞台模型 | 稀有 | — | 不适用 | growth | 旧无 · 成长 / 招募 |
| 78 | 缠梦古堡模型 | 核心 | — | 不适用 | growth | 旧无 · 成长 / 招募 |
| 79 | 涡旋座 | 稀有 | — | 攻击与输出 | damage | 旧无 · damage |
| 83 | 胎生百合 | 核心 | C | 不适用 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 85 | 古高卢银币 | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 86 | 高卢银行支票 | 基础 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 87 | 《第二经济改革法》 | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 88 | 香草沙士汽水 | 基础 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 89 | 羽兽肝酱 | 核心 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 90 | 迷梦香精 | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 91 | 摩根队长佳酿 | 基础 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 92 | 生命之水 | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 93 | 皇家利口酒 | 核心 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 94 | “绽放” | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 101 | 老蒲扇 | 稀有 | G | 编队协同 | squad | 旧 G · squad |
| 103 | 安洁莉娜的创想 | 稀有 | C | 追击与控制 | control | 181 改标通用 |
| 104 | Scout的狙击镜 | 稀有 | G | 编队协同 | damage | 181 改标通用 |
| 105 | 黑色郁金香 | 核心 | C | 技能与技力 | damage | 旧 C · damage → 通用 |
| 110 | 绿叶菜罐头 | 核心 | C | 技能与技力 | damage | 旧 C · damage → 通用 |
| 111 | 叙拉古人的愤怒 | 核心 | C | 技能与技力 | damage | 旧 C · damage → 通用 |
| 112 | 荣耀绶带 | 核心 | D | 攻击与输出 | damage | 181 改标通用 |
| 114 | 国王的新枪 | 核心 | — | 条件触发 | attack_speed | 旧无 · attack_speed |
| 117 | 遗落之帜 | 核心 | — | 条件触发 | damage | 旧无 · damage |
| 120 | 《光耀卡西米尔》 | 核心 | A | 闪避 | damage | 旧 A 但全队 / 队长生效 |
| 121 | 《归来》 | 升华 | A | 闪避 | damage | 旧 A 但全队 / 队长生效 |
| 122 | 疗养体验卡 | 稀有 | — | 条件触发 | attack_speed | 旧无 · attack_speed |
| 123 | 疗养特供卡 | 核心 | — | 条件触发 | attack_speed | 旧无 · attack_speed |
| 124 | 古乔治营养原浆 | 核心 | A | 攻击与输出 | damage | 旧 A 但全队 / 队长生效 |
| 125 | 紧急活性剂 | 核心 | A | 攻击与输出 | attack_speed | 旧 A 但全队 / 队长生效 |
| 127 | 国王的枝条 | 核心 | — | 条件触发 | skill_cycle | 旧无 · skill_cycle |
| 128 | 诸王的冠冕 | 升华 | — | 条件触发 | damage | 旧无 · damage |
| 160 | 医者-自医 | 基础 | G | 编队协同 | healing | 旧 G · healing |
| 161 | 医者-妙手 | 基础 | G | 编队协同 | healing | 旧 G · healing |
| 172 | 极速之手 | 稀有 | G | 编队协同 | attack_speed | 旧 G · attack_speed |
| 176 | 永流之手 | 核心 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 177 | 游戏室管理员权限卡 | 稀有 | G | 编队协同 | growth | 旧 G · growth |
| 178 | Miss.Christine摸摸券 | 稀有 | G | 编队协同 | growth | 旧 G · growth |
| 179 | 古旧铸物 | 核心 | G | 编队协同 | growth | 旧 G · growth |
| 180 | 地形图 | 基础 | G | 编队协同 | squad | 旧 G · squad |
| 181 | 神音海螺 | 基础 | G | 编队协同 | squad | 旧 G · squad |
| 182 | 林间夜话 | 基础 | G | 编队协同 | squad | 旧 G · squad |
| 183 | 教堂救济餐券 | 稀有 | G | 编队协同 | squad | 旧 G · squad |
| 184 | 地区行动方案 | 基础 | G | 不适用 | economy | 旧 G · economy |
| 185 | 全局作战文件 | 稀有 | G | 不适用 | growth | 旧 G · growth |
| 186 | 人事部密信 | 稀有 | G | 不适用 | growth | 旧 G · growth |
| 187 | 一份演讲稿 | 基础 | G | 编队协同 | growth | 旧 G · growth |
| 189 | 罗德岛战术电台 | 基础 | G | 编队协同 | choice | 旧 G · choice |
| 201 | 达里奥的提灯 | 稀有 | — | 需新机制·排异反应 | skill_cycle | 旧无 · skill_cycle |
| 203 | 郁金香的秘方 | 稀有 | — | 需新机制·排异反应 | skill_cycle | 旧无 · skill_cycle |
| 207 | 投币玩具 | 稀有 | — | 经济 | attack_speed | 旧无 · attack_speed |
| 208 | 骑士戒律·新编 | 核心 | — | 经济 | attack_speed | 旧无 · attack_speed |
| 209 | 支援补给站 | 稀有 | G | 支援装置 | healing | 旧 G · healing |
| 210 | 支援地雷组 | 稀有 | — | 支援装置 | damage | 旧无 · damage |
| 211 | 支援轰隆隆 | 稀有 | G | 支援装置 | damage | 旧 G · damage |
| 212 | 支援起重机 | 稀有 | G | 支援装置 | control | 旧 G · control |
| 213 | 支援防暴桩 | 稀有 | G | 支援装置 | control | 旧 G · control |
| 214 | 支援急救包 | 基础 | G | 支援装置 | healing | 旧 G · healing |
| 215 | 布雷奥甘肖像 | 遭诅古物 | — | 负面藏品 | skill_cycle | 遭诅 |
| 216 | 海神的代谢 | 遭诅古物 | — | 负面藏品 | defense | 遭诅 |
| 217 | 失败的标本 | 遭诅古物 | — | 需新机制·排异反应 | ending | 结局 / 代价 |
| 218 | “应急灯” | 遭诅古物 | F | 负面藏品 | light | 遭诅 |
| 219 | “光明之躯” | 遭诅古物 | F | 负面藏品 | light | 遭诅 |
| 220 | 主教的研究 | 遭诅古物 | — | 负面藏品 | light | 遭诅 |
| 221 | 深蓝之心 | 结局 | — | 结局 | ending | 结局 / 代价 |
| 222 | 海潮的气息 | 结局 | — | 结局 | squad | 结局 / 代价 |
| 223 | 退行的罗辛南特 | 结局 | — | 结局 | ending | 结局 / 代价 |
| 225 | 骑士骨血 | 结局 | — | 结局 | ending | 结局 / 代价 |
| 227 | “文明的存续” | 稀有 | A | 攻击与输出 | weakness | 旧 A 但全队 / 队长生效 |
| 229 | “审判庭之火” | 核心 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 232 | “碎片大厦的回忆” | 升华 | C | 追击与控制 | damage | 旧 C · damage → 通用 |
| 236 | “分浪” | 稀有 | C | 技能与技力 | skill_cycle | 旧 C · skill_cycle → 通用 |
| 237 | “海洋的脉搏” | 稀有 | A | 攻击与输出 | attack_speed | 旧 A 但全队 / 队长生效 |
| 238 | “决心” | 结局 | — | 结局 | ending | 结局 / 代价 |
| 239 | “观望” | 结局 | — | 结局 | choice | 结局 / 代价 |
| 240 | “犹疑” | 结局 | — | 结局 | choice | 结局 / 代价 |
| 241 | “未尽的生命” | 遭诅古物 | — | 需新机制·排异反应 | ending | 结局 / 代价 |
| 242 | 深蓝回忆 | 结局 | — | 结局 | ending | 结局 / 代价 |
| 243 | 深蓝之树 | 遭诅古物 | F | 负面藏品 | light | 遭诅 |
| 244 | 人事部铜印 | 稀有 | G | 编队协同 | growth | 旧 G · growth |
| 245 | 博士银印 | 升华 | G | 编队协同 | growth | 旧 G · growth |
| 251 | “国王的水晶” | 稀有 | — | 经济 | growth | 旧无 · 成长 / 招募 |
| 252 | 刻勋之手 | 核心 | D | 攻击与输出 | damage | ? |
| 261 | 生还者合约 | 稀有 | G | 编队协同 | growth | 旧 G · growth |

### 生存 `survival`（40）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 17 | 热水壶 | 基础 | — | 生存 | defense | 旧无 · defense |
| 18 | 特殊抑制器 | 基础 | — | 生存 | defense | 旧无 · defense |
| 19 | 石像鬼塑像 | 基础 | — | 生存 | defense | 旧无 · defense |
| 20 | 血魔的寝床 | 基础 | — | 生存 | defense | 旧无 · defense |
| 21 | 长生者之证 | 稀有 | — | 生存 | defense | 旧无 · defense |
| 30 | 夜阳花 | 基础 | — | 灯火 | light | 旧无 · 灯火 |
| 31 | 聚火源石虫 | 基础 | — | 灯火 | light | 旧无 · 灯火 |
| 32 | 指路鳞 | 稀有 | — | 灯火 | light | 旧无 · 灯火 |
| 41 | 开裂的束缚带 | 基础 | — | 削弱敌人 | defense | 旧无 · defense |
| 43 | 奇渊面具 | 稀有 | — | 削弱敌人 | defense | 旧无 · defense |
| 44 | 教母的信物 | 核心 | — | 削弱敌人 | defense | 旧无 · defense |
| 51 | 异铁小圆盾 | 基础 | H | 生存 | defense | 旧 H · defense |
| 52 | 军团护心镜 | 稀有 | H | 生存 | defense | 旧 H · defense |
| 53 | 古旧的蒸汽甲胄 | 核心 | H | 生存 | defense | 旧 H · defense |
| 60 | 难闻的止血剂 | 基础 | H | 生存 | defense | 旧 H · defense |
| 61 | 急救药箱 | 稀有 | H | 生存 | defense | 旧 H · defense |
| 62 | 未知仪器 | 核心 | — | 生存 | defense | 旧无 · defense |
| 73 | 设计师量尺 | 基础 | H | 闪避 | dodge | 旧 H · dodge |
| 74 | “法术杀手” | 基础 | H | 闪避 | dodge | 旧 H · dodge |
| 75 | 舞者手链 | 基础 | H | 闪避 | dodge | 旧 H · dodge |
| 113 | 王庭盟约 | 稀有 | — | 不适用 | defense | 旧无 · defense |
| 115 | 古堡的子嗣 | 稀有 | H | 生存 | defense | 旧 H · defense |
| 119 | 捕鳞蓑 | 基础 | — | 闪避 | defense | 旧无 · defense |
| 126 | 国王的圆饼 | 核心 | — | 条件触发 | defense | 旧无 · defense |
| 131 | 沃特大叔养护套装 | 基础 | — | 生存 | defense | 旧无 · defense |
| 132 | 乌萨斯毡毯 | 基础 | — | 生存 | defense | 旧无 · defense |
| 162 | 医者-固化序列 | 稀有 | H | 生存 | defense | 旧 H · defense |
| 204 | 火油与药膏 | 核心 | F | 灯火 | light | 旧 F · 灯火 |
| 205 | 夜阳草 | 基础 | — | 灯火 | light | 旧无 · 灯火 |
| 228 | “时光之末” | 升华 | H | 生存 | defense | 旧 H · defense |
| 235 | “基岩” | 稀有 | — | 生存 | defense | 旧无 · defense |
| 247 | 地底的灼痕 | 基础 | — | 灯火 | light | 旧无 · 灯火 |
| 248 | 铸阳巨械 | 稀有 | — | 灯火 | light | 旧无 · 灯火 |
| 249 | 凝固灯油 | 基础 | — | 灯火 | light | 旧无 · 灯火 |
| 250 | 崇圣灯油 | 稀有 | — | 灯火 | light | 旧无 · 灯火 |
| 253 | 蓝卡坞安全衣 | 核心 | F | 负面藏品 | defense | 旧 F · 灯火 |
| 254 | 《刀光剑影》 | 升华 | F | 负面藏品 | attack_speed | 旧 F · 灯火 |
| 255 | 佣兵保单 | 核心 | F | 生存 | defense | 旧 F · 灯火 |
| 259 | 铁卫-城墙 | 稀有 | H | 生存 | defense | 旧 H · defense |
| 262 | 养育者基因种 | 核心 | — | 需新机制·排异反应 | defense | 旧无 · defense |

### 经济 `economy`（21）

| # | 名称 | 稀有度 | 旧 lanes | 旧 cat | 旧 effect_category | 依据 |
|---|---|---|---|---|---|---|
| 8 | 蓝色丝巾 | 基础 | — | 经济 | economy | 旧无 · economy |
| 12 | 古怪的长笛 | 基础 | — | 经济 | economy | 旧无 · economy |
| 13 | 玻璃小鸟 | 基础 | — | 经济 | economy | 旧无 · economy |
| 22 | 被撬开的道具箱 | 基础 | — | 经济 | economy | 旧无 · economy |
| 23 | 古旧乐谱残章 | 基础 | — | 经济 | economy | 旧无 · economy |
| 24 | 解约协议 | 基础 | — | 经济 | economy | 旧无 · economy |
| 25 | 万能钥匙 | 基础 | — | 经济 | economy | 旧无 · economy |
| 26 | 女妖之吻 | 稀有 | — | 经济 | economy | 旧无 · economy |
| 27 | 古旧钱币 | 基础 | — | 经济 | economy | 旧无 · economy |
| 28 | 演员的首饰盒 | 基础 | — | 经济 | economy | 旧无 · economy |
| 29 | 无瑕宝玉 | 稀有 | — | 经济 | economy | 旧无 · economy |
| 188 | 锈蚀的铁锤 | 核心 | — | 经济 | economy | 旧无 · economy |
| 190 | 四叶草化石 | 核心 | — | 经济 | choice | 旧无 · choice |
| 194 | 三钥协定 | 基础 | — | 经济 | choice | 旧无 · choice |
| 195 | 便携经书 | 基础 | — | 不适用 | choice | 旧无 · choice |
| 196 | 判官经文布 | 稀有 | — | 不适用 | choice | 旧无 · choice |
| 197 | 深洋主宰刻像 | 稀有 | — | 不适用 | choice | 旧无 · choice |
| 198 | 鸭爵金砖 | 核心 | — | 不适用 | choice | 旧无 · choice |
| 206 | 大教堂拼图 | 稀有 | — | 需新机制·启示 | choice | 旧无 · choice |
| 224 | “荒诞命运” | 基础 | — | 经济 | economy | 旧无 · economy |
| 226 | “绝唱” | 核心 | — | 需新机制·启示 | choice | 旧无 · choice |

