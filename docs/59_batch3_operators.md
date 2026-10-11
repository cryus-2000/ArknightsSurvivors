# 59 · 第三批干员技能设计（浊心斯卡蒂 / 德克萨斯 / 星熊 / 能天使 / 安洁莉娜）

> 2026-10-11，干员会话按用户指令（10-11：「原作的技能风格 + 肉鸽元素的再设计」）起草。**只是设计 + 数据草案，本提交不含代码。**
> 契约沿用 docs/26 v2.5：每名干员 **普攻 + 3 个技能 + 1 个天赋**，S1 招募即有、S2 精一、S3 精二；三技能并行充能，就绪时先放 S3 > S2 > S1；「·N」= 充能需求（SP）；**永久** = JSON `permanent: true`，**次数型** = 装填 N 次打完为止，**手动** = JSON `mode: "manual"`，只在该干员当主控时手动（队友一律自动，机器人按 `bot_wants_manual`）。
> 名单与优先级由用户定（10-11），五人全部进**基础池**，不走战绩解锁（docs/23 §11.2 里「浊心斯卡蒂 = 结局三解锁」的旧草案作废）。
> 数值口径：几何单位与 docs/26 / 各干员 JSON 相同（像素；近战 reach 105–132、远程 range 310–350、普攻 atk 24–52、间隔 0.7–1.4 秒）；DPS 预算按 docs/27 §3.3（主输出 25–35，节奏 85%、保护 70%、增幅 65%）；技能预算 S1 ≈ 3–5 秒普攻、S2 ≈ 8–12 秒、S3 ≈ 15–25 秒或 8–14 秒形态。
> 原作资料口径同 docs/49：名称以官方为准、**只转述不照抄**；本文里标（待核）的技能名 / 顺序在落地前对 PRTS 再核一次（原作技能名是本作「认得出」的关键，核错比机制错更显眼）。

---

## 0. 总览

| 优先 | 干员 | 职业 · 分支 | 补的位置 | 不许撞的人 | 一句话 |
|---|---|---|---|---|---|
| 1 | **浊心斯卡蒂** `skalter` | 辅助 · 吟游者 | 第二名辅助；唯一以**博士**为中心的增益光环；深海猎人协同的中枢 | 铃兰（跟随主控的减速 / 易伤光域 + 永久队友攻 +15%）、流明（灯火操作） | 歌域绕着博士转，灯火高时是治愈的歌，灯火低时是溟海的歌 |
| 2 | **德克萨斯** `texas` | 先锋 · 冲锋手 | 第二名先锋；节奏位的另一种动词 | 推进之王（锤击命中回技力）、艾丽妮（原地直线穿刺） | 冲刺穿阵回技力，主控一冲她就跟着冲 |
| 3 | **星熊** `hoshiguma` | 重装 · 铁卫 | 第二名重装；**不治疗**的保护 | 塞雷娅（阻挡圈 + 回血）、凯尔希 / 流明（治疗） | 盾卫格挡、挡下就反砍，魔王一刀穿一列 |
| 4 | **能天使** `exusiai` | 狙击 · 速射手 | 第二名狙击；高频单体对比维什戴尔的慢炮 | 维什戴尔（范围炮击 + 余震）、Logos（远程单体法伤）、铃兰（追踪狐火） | 一秒三发，弹夹越打越满，满了倾泻 |
| 5 | **安洁莉娜** `angelina` | 辅助 · 控场 | 第三名辅助；**聚怪 / 悬浮**型控制 | 铃兰（减速域）、艾丽妮（单点浮空）、乌尔比安（钩 2 人） | 把敌人拉成一圈、再整片托上天，给范围干员喂靶子 |

共同的肉鸽再设计原则（和第二批一致，docs/26「第二批其余四人」）：

1. 原作的**动词**保留（唱歌增益 / 冲刺回费 / 格挡反击 / 连射 / 重力拉拽），翻译进「主控唯一受击、干员不死、10 分钟大群」的规则。
2. 每人至少一条与**本作系统**（灯火 / 灯标 / 溟痕 / 黑潮 / 冲刺 / 拾取 / 藏品流派）挂钩的「肉鸽扭转」，写在各自的「肉鸽扭转」行；不做纯数值翻版。
3. 单人开局前两分钟必须能自己清潮（docs/23 §10），所以吟游者和控场也要有普攻伤害；精一天赋不依赖队友。
4. 接入尽量走现成挂点（`dmg_taken_mult / prevent_death / sanctuary / light_radius_mult / on_kill / extra_bodies / stats.add("op:<id>")`），本批预计 **game.gd 改动 ≤ 2 处**（§6）。

---

## 1. 浊心斯卡蒂 `skalter`（辅助 · 吟游者，优先 1）

**定位**：增幅位（DPS 预算 65%），**歌域以主控为中心**（`g.ppos`；用户 10-11 定，原稿以博士为中心，博士拖在身后会让前方追兵吃不到歌域），灯火高低决定歌是哪一首。铃兰是跟着主控的减速 / 易伤光域、队友攻击 +15% 永久；她不减速、不易伤，给的是**攻速 + 深海猎人攻击 + 灯火保护**，伤害是法术脉冲。流明把灯火拉高、幽灵鲨在昏暗里更强，她两头都接：灯火 ≥ 70 时歌域更大更治愈，< 30 时歌域变成溟海的歌、伤害更高。

**原作对应**（吟游者：不攻击、持续回复周围友军）：普攻 ← 特性「持续治疗」+ 天赋「深海的呼唤」（周围友军攻击提升，深海猎人更多；待核：原作一技能名也叫这个还是叫「吟游」，落地前核）；S1「吟游」（待核）← 原作「回复 + 增益」的短循环版；S2「深海的呼唤」← 原作「周围友军攻击提升、深海猎人翻倍」，本作做永久型（原作是常驻光环）；S3「死地之歌」← 原作自损换友军大幅攻击 + 持续回复，本作把「自损」改成**灯火流失**；天赋「溟海颂歌」← 原作天赋二（深海猎人 / 海嗣相关增益）。

**普攻 · 海潮低吟**：每 1.0 秒以主控为中心放出一圈声浪，半径 190，命中圈内**全部**敌人，法术伤害 atk 14（area）。主控在歌域内时每 3 秒回复 0.3%（刻意低于流明 0.67%/秒、凯尔希 1%/秒：她不是奶位）。DPS 单体 14，群体不设上限——和幽灵鲨 r120 的物理环斩（46 / 1.2 秒）错开一个量级。
- 手动普攻（v2.5）：不分方向，只受闸门（同幽灵鲨）。
- 图鉴演示没有主控时以她自己的位置为中心。

| 技能 | SP | 效果 |
|---|---|---|
| S1 吟游 | ·7 | 5 秒：歌域半径 ×1.4、主控每秒回复 1%、期间**受击灯火流失减半**（`lamp_loss_mult` 临时 ×0.5，流明 S2 是永久 ×0.7，不重复） |
| S2 深海的呼唤 | ·15 **永久** | 歌域半径 +30%；歌域内队友**攻速 +15%**；编队里的深海猎人（斯卡蒂、乌尔比安、归溟幽灵鲨）再 +15% 攻击（`op_atk add 0.15, "op:<id>"`，与乌尔比安天赋同写法） |
| S3 死地之歌 | ·24，12 秒 | 歌域 ×2，全队攻击 +50%，声浪伤害 ×3；主控每秒回复 1.5%；**代价：灯火每秒 -2**（12 秒 -24，从充盈唱到照亮边缘）。昏暗（< 30）时灯火不再扣（已经在海底了），改为声浪再 ×1.5 |
| 天赋 溟海颂歌（精一） | — | 灯火 ≥ 70「充盈」：歌域 +20%、回复翻倍；灯火 < 30「昏暗」：声浪伤害 +50%、歌域内敌人移速 -10%（不是减速状态，不与铃兰 / 安洁莉娜叠「slow」）；编队里每名深海猎人：歌域内所有队友攻击 +4%（最多 3 人 +12%） |

**肉鸽扭转**：歌域 = 博士位置，玩家「让博士站在哪」第一次有意义（倒车、绕圈时歌域扫过身后的追兵）；灯火双向：高灯火流派（流明、H 守护）拿她当第二奶，深蓝流派（F、幽灵鲨）拿她当昏暗增伤；S3 自损灯火是深蓝线主动压灯火的手段，和「深蓝之心」事件衔接。

**成长线（6 节点，同构）**：声浪半径 +15% → 声浪伤害 +15%（命中处小涟漪）→ 精一（S2 + 天赋）→ 自定义「潮汐和声」：每第 3 次声浪追加一次 ×0.6 的回声（follow_up）→ 自定义「深海的回响」：S1 期间歌域内敌人每秒额外法伤 ×0.3 → 精二（S3 + 普攻质变「溟海之声」：歌域边缘出现 6 个绕行的海潮音符，碰到的敌人被推开 kb 120，每 0.5 秒一次）。

**数值预算**：atk 14 / cd 1.0 / aura 190；S1 ≈ 5 秒 ×1.4 域 ≈ 4 秒普攻；S2 永久 +30% 效率；S3 12 秒 ×3 ≈ 24 秒普攻（上限）；天赋 +10–20%。主控受击属性（docs/23 公式，原作精二满级 生命 1530 / 防御 148 / 法抗 20%，远程 ×1.00）：max_hp 105、armor 1.0、arts_res 0.2、regen 1.1。档位建议 **A+**（增幅型，`skill_power +0.02`）。

**实现成本 ≈ 6 小时**，不改 game.gd：
- 现成：光环绘制 `draw_auras()`（铃兰同写法）、`area_hit()` 脉冲、`g.doc_pos`、队友增益 `g.stats.add(&"op_atk"/&"op_aspd", "add", v, "skalter_song", "op:" + o.id)`（乌尔比安 `_apply_stacks` 照抄，每帧按「谁在歌域内」刷新来源）、`g._heal()`、`g.lamp` 直接加减、`g.lamp_loss_mult`（combat.gd 92 行已乘）。
- 新写：按灯火档切歌的状态机（三档颜色 / 音色）、S3 灯火扣减与昏暗分支。
- 美术：idle / run / attack（抬手唱）/ skill 四组，歌域地面纹理程序绘制；特效主色「浊心红」`(0.85, 0.25, 0.35)` + 海蓝波纹，昏暗时转深紫。音效：atk = 低吟一拍 + 水波、s1 = 上行吟唱、s2 = 深海长鸣 + 和声（永久定音）、s3 = 挽歌 + 心跳渐快。

**强度测试**：
- 单人：`balance_run.py --op skalter --bot expert --seeds 12`（标准 --tier=0）与 `--bots master --tier=2 --seeds 12`（Ⅷ），胜率（含超时）目标 50–70，对照铃兰同参数（同角色相差 ≤ 15 个百分点，docs/27 §9.3）。
- 编队：`--squad skalter,wisadel,saria --seeds 6`、`--squad skalter,ulpianus,specter_unchained --seeds 6`（深海猎人三人队，看天赋叠满）、`--preset share --extra=--nodeath`（她的伤害占比目标 10–25%）。
- 旋钮：偏弱先动 `aura`（190 → 210）再动 `atk`；偏强先收 `s3_atk`（0.5 → 0.35）与 `s3_mult`，不动 S2 永久值；深海猎人队过强时收 `talent_hunter`（0.04 → 0.03）。

---

## 2. 德克萨斯 `texas`（先锋 · 冲锋手，优先 2）

**定位**：节奏位（DPS 预算 85%）。推进之王 = 锤击命中回技力 + 眩晕；她 = **冲刺穿阵**回技力，而且**主控按冲刺时她同步冲一次**，把玩家的冲刺键变成全队充能节拍。艾丽妮是站桩直线穿刺（180 × 26，两段，浮空）；她是人跟着剑走（位移 140、宽 44，一段，眩晕短）。

**原作对应**（冲锋手：攻击敌人时回复部署费用）：普攻 ← 特性「攻击回费」→ 冲刺穿过敌人回全队技力；S1「剑雨」← 原作二技能（周围敌人伤害 + 眩晕 + 回费）；S2「可靠伙伴」（待核：原作天赋名）← 快速再部署 / 回费 → 本作做成**主控冲刺冷却缩短**的永久型；S3 **用缄默德克萨斯的三技能原作名**（用户 10-11 定；机制按本文「连冲」不变，实装时对 PRTS 核名并替换下文暂名「速递」）；天赋「冲锋手」← 职业特性本身。

**普攻 · 疾行斩**：每 1.1 秒朝最近敌人的方向冲刺 140（宽 44，穿透），沿途全部敌人受物理 atk 26；冲到头停 0.15 秒再由 `follow()` 归队。每次冲刺**穿过 ≥ 1 名敌人**则全队技力 +0.6 秒（推进之王每次命中 +0.5 秒、精一翻倍；她不翻倍，靠次数）。DPS 单体 23.6 ≈ 85% 预算。
- 手动普攻（v2.5）：A 方向类，严格沿瞄准方向冲（前方没人照冲，可当小位移）。
- 队友时冲刺起点 = 自己当前位置；主控时冲刺 = 主控本体位移（和乌尔比安弹射同写法，`update` 里覆盖 `pos`）。

| 技能 | SP | 效果 |
|---|---|---|
| S1 剑雨 | ·6 | 以自身为中心 r130 剑雨 ×1.6，眩晕 0.5 秒（精英 0.25、Boss 不晕），全队技力 +10% |
| S2 可靠伙伴 | ·14 **永久** | 冲刺距离 +40%（140 → 196）、疾行斩 ×1.3；**主控的冲刺冷却 -20%**（她当队友也生效：「可靠的伙伴」在旁边你跑得更顺） |
| S3 速递 | ·20，8 秒 | 每 0.5 秒自动向敌群最密处冲刺一次（共 16 次），每次 ×0.9、穿过的敌人眩晕 0.3 秒、全队技力 +0.4 秒；结束时在落点放一次剑雨 ×1.6 |
| 天赋 冲锋手（精一） | — | **主控按下冲刺时**，德克萨斯同步沿同方向冲一次疾行斩（每 2 秒至多一次，不占普攻冷却）并全队技力 +1 秒；每次疾行斩穿过 3 名以上敌人时额外 +0.3 秒 |

**肉鸽扭转**：节奏位第一次和**玩家操作**绑定——冲刺既是保命键也是充能键，手残机器人（不冲）和高手（频繁冲）在她身上差距最大；S2 改主控冲刺冷却，是干员第一次改博士 / 主控的操作参数（DASH_CD 目前是常量，见 §6）；C 控制 / 技能循环流派里「技力回复」类藏品对她的触发次数最多。

**成长线**：冲刺宽度 +30% → 疾行斩 ×1.15 → 精一 → 自定义「回马剑」：冲到头 0.2 秒后原路反冲一次（×0.5，follow_up）→ 自定义「剑雨·连」：S1 0.3 秒后再落一次剑雨（×0.6，重新瞄准）→ 精二（S3 + 普攻质变「余像」：冲刺路径上留下 0.6 秒剑气残像，踩进的敌人受 ×0.3 并减速 0.5 秒）。

**数值预算**：atk 26 / cd 1.1 / dash_len 140 / dash_w 44；补偿 = 每冲 0.6 秒全队技力（≈ 推进之王 0.5 × 精一 2 = 1.0 的六成，靠天赋的冲刺同步补回）。主控属性（原作精二满级 生命 1986 / 防御 441 / 法抗 0%，近战 ×1.06）：max_hp 118、armor 3.0、arts_res 0.0、regen 1.3。档位建议 **A**（基准，0）。

**实现成本 ≈ 8 小时**，game.gd **1 处**（冲刺冷却倍率）：
- 现成：位移 = 乌尔比安弹射（update 里覆盖 pos、follow 之后执行）；线段命中 = 艾丽妮 `刺剑` 的线段判定（长 × 宽）；全队技力 = 推进之王 `_squad_sp_seconds()`（建议**搬到 character.gd** 作共享工具，两人同用）；眩晕 `e.stun`；主控冲刺状态 `g.dash_t`（天赋读它的上升沿）。
- 新写：`g.dash_cd_mult`（DASH_CD 是常量，加一个倍率变量，开局 1.0，干员 `sync_stats` 时写；1 处）；S3 的 16 次连冲状态机。
- 美术：idle / run / attack（拔剑前冲）/ skill（剑雨）；特效主色「企鹅黑 + 橙」`(1.0, 0.55, 0.2)`：冲刺拖尾橙色剑光、剑雨 = 落下的短剑影。音效：atk = 短促拔剑 + 风切、s1 = 密集剑雨落地、s2 = 一声皮靴踏地（永久定音）、s3 = 连续破风 + 引擎般的节奏。

**强度测试**：
- 单人：`--op texas --bot expert --seeds 12`（标准）、`--bots master --tier=2 --seeds 12`（Ⅷ），目标 50–70；对照推进之王 ≤ 15 个百分点。**另加 `--bot bad` 4 seed**，看「不冲刺的机器人」她是否明显弱于推进之王（预期弱 5–10 个百分点，这是设计意图，但不该掉出 docs/29 bad 档的 3:00–8:00 存活框）。
- 编队：`--squad texas,wisadel,saria`、`--squad texas,eyjafjalla,kaltsit`；`--preset share --extra=--nodeath` 伤害占比目标 20–35%（节奏位）。
- 旋钮：偏弱先加 `hit_sp`（0.6 → 0.8）再 `atk`；偏强先收 `talent_sp`（1.0 → 0.7）和 S3 的 `s3_sp`，不动冲刺距离（手感）。

---

## 3. 星熊 `hoshiguma`（重装 · 铁卫，优先 3）

**定位**：保护位（DPS 预算 70%），**不治疗**。塞雷娅 = 360° 阻挡圈推开 + 回血 + 钙质化减速易伤；她 = **格挡（伤害归零）→ 反击 → 击退**，受击越多反击越多。分支名用官方「铁卫」（用户 10-11 定）。

**原作对应**：普攻 ← 大刀 + 盾（原作普攻单体近战）→ 本作扇形横扫；S1「强力击」（待核：原作一技能是通用强力击型）← 攻击提升型 → 本作做成「举盾一击」；S2「热砂」← 攻防提升 + 概率格挡 / 反伤；S3「魔王」← 攻防大幅提升、**攻击命中直线上的 3 名敌人** → 幸存者里改成整条直线；天赋「盾卫」← 概率完全免伤。原作天赋二「铁壁」（部署后防御提升）没有对应——干员不受击。

**普攻 · 盾斧斩**：前压横扫 140°、r 110，物理 atk 30，每 1.1 秒，命中击退 kb 220（塞雷娅拳击 kb 低、靠阻挡圈推）。DPS 27 ≈ 70% 预算 + 保护补偿。手动普攻：A 方向类。

| 技能 | SP | 效果 |
|---|---|---|
| S1 举盾 | ·6 | 3 秒内主控**下一次**受到的伤害被完全格挡（归零、不掉灯火）；格挡成功的瞬间星熊反手重斩 r120 ×2.0、击退 kb 360；3 秒内没挨打则改为向前一记 ×1.5（不白放） |
| S2 热砂 | ·14，8 秒 | 攻击 +40%，主控受到的伤害 -20%，「盾卫」免伤概率 ×2；斩击落点留下 2 秒热砂（r 80，踩进的敌人每秒 ×0.3 灼伤，dot） |
| S3 魔王 | ·22，10 秒 | 攻击 +60%；盾斧斩改为**直线斩**（长 220、宽 50，命中沿线全部，原作「3 名」→ 全部），每次命中击退 ×1.5；期间主控受伤 -30%，每次受击（含被格挡的）触发一次 r120 震退 kb 300 |
| 天赋 盾卫（精一） | — | 主控每次受到伤害 20% 概率完全免伤（Boss 攻击 10%，用对局随机数），**免伤的攻击不掉灯火**；免伤瞬间星熊盾推 r90 内敌人 kb 200。**灯标读条期间概率 +15%**（守塔时她站在你身前） |

**肉鸽扭转**：格挡是本作第一个「概率免伤」机制，和灯火直接接（挡下的那一下灯火不掉，等于保护灯火而不是回血——给 H 守护 / 高灯火流派一个不靠治疗的解）；灯标读条加成把她和溟痕清理绑在一起；魔王的直线斩和安洁莉娜 / 乌尔比安的聚怪天然联动。

**成长线**：盾斧斩范围 +15% → 盾斧斩 ×1.15 → 精一（S2 + 天赋）→ 自定义「盾墙」：盾卫免伤时同时推开的敌人眩晕 0.4 秒 → 自定义「热砂·余烬」：热砂持续 2 → 4 秒、灼伤 ×0.5 → 精二（S3 + 普攻质变「鬼面」：每第 4 次盾斧斩变成一记直线斩，长 220 × 宽 50，×1.3）。

**数值预算**：atk 30 / cd 1.1 / reach 110；补偿 = 20% 免伤（≈ 受伤 -20%）+ 击退。主控属性（原作精二满级 生命 3446 / 防御 625 / 法抗 10%，近战 ×1.06）：max_hp 128、armor 3.5、arts_res 0.1、regen 1.0。档位建议 **A+**（保护型，`skill_power +0.02`）。

**实现成本 ≈ 7 小时**，game.gd / combat.gd **0–1 处**：
- 现成：`dmg_taken_mult()` 每次伤害都询问（combat.gd 65 行）——返回 0.0 即格挡；`melee_hit()` 带 kb / stun；直线斩 = 艾丽妮线段判定；dot = 艾雅法拉点燃的敌人字段写法；震退 = `area_hit(kb)`。
- 需确认：伤害被乘成 0 后，combat.gd 92 行的灯火流失 `lamp_loss` 按 dmg 算仍有 `hit_base 4.0` 的底——**若底不为零，加一句「dmg ≤ 0 不扣灯火」**（1 处，也是「挡下的不掉灯火」的来源）。免伤概率必须用 `g.rng`（同 seed 可复现，docs/36 §3）。
- 美术：idle / run / attack（大刀横扫）/ skill（举盾）；特效主色「鬼金」`(0.95, 0.75, 0.3)`：格挡 = 盾面金色闪光 + 冲击环，热砂 = 地面橙砂颗粒，魔王 = 刀身黑红面具纹。音效：atk = 大刀破风 + 盾沿碰响、hit = 厚重斩入、s1 = 盾面「铛」一声（格挡成功再响一次）、s2 = 砂石流 + 热浪、s3 = 鬼面低吼 + 刀鸣。

**强度测试**：
- 单人：`--op hoshiguma --bot expert --seeds 12`（标准）、`--bots master --tier=2 --seeds 12`（Ⅷ），目标 50–70；对照塞雷娅 ≤ 15 个百分点。额外看 docs/29 的「承伤 / 分」「熄灯秒」：她的承伤应比塞雷娅低 15–25%，熄灯秒应更低（挡下的不掉灯火）；回血应几乎为零（验证「不治疗」）。
- 编队：`--squad hoshiguma,wisadel,eyjafjalla`（双输出 + 她）、`--squad hoshiguma,angelina,logos`（聚怪 + 直线斩）；伤害占比目标 10–25%。
- 旋钮：偏弱先加 `block_chance`（0.20 → 0.25）再 `atk`；偏强先收 S2 的 `s2_dr`（0.2 → 0.15）和 S3 的 `s3_dr`，**不动盾卫基础概率**（它是身份）。Ⅷ 跌破 50 时优先看 `beacon_bonus`（0.15）是否该上调——它不给奖励、只在读条时生效，符合「收紧只用不给奖励的旋钮」的反向逻辑。

---

## 4. 能天使 `exusiai`（狙击 · 速射手，优先 4）

**定位**：主输出（DPS 预算 100%）。维什戴尔 = 1.4 秒一发范围炮 + 余震 + 殉爆；Logos = 1.4 秒一发单体法伤 + 安魂；铃兰 = 追踪狐火 2 发。她 = **0.35 秒一发**物理直线弹、单体、无范围，清群靠「**每次射击的子弹数**」这个可成长的量——肉鸽里她是子弹数流派的载体。

**原作对应**（速射手：攻击速度快）：普攻 ← 特性；S1「强力击」← 原作一技能（下次攻击提升）；S2「过载模式」← 原作二技能（攻速大幅提升）；S3「处决模式」← 原作三技能（每次攻击连射 4 发、攻击略降）；天赋「速射」（待核：原作天赋一名）← 攻速 / 弹幕相关。

**普攻 · 速射**：每 0.35 秒向最近敌人（精英优先度 ×1.2）射 1 发物理弹，range 300，弹速 520，atk 9，不穿透。DPS 25.7 ≈ 预算下沿（命中率 ≈ 0.85 已计）。**子弹数** `shots`（基础 1）是她全部成长的轴：每多 1 发在扇形 ±8° 内并排射出，各自独立索敌（最近的 N 个不同目标，不够时打同一个）。手动普攻：B 需要目标类（锥内最近）。

| 技能 | SP | 效果 |
|---|---|---|
| S1 强力击 | ·6 **次数型** | 装填 6 发强力弹：之后的射击每发 ×1.8、穿透 1 名敌人，打完为止（`shots` 越多耗得越快，是刻意的） |
| S2 过载模式 | ·14，8 秒 | 射击间隔 0.35 → 0.20（攻速 +75%），每发 ×0.9；结束时**过热** 1.0 秒不射（原作没有，肉鸽代价，让 S2 不是纯白给） |
| S3 处决模式 | ·22，10 秒 | 每次射击改为 **4 连射**（间隔 0.06 秒，每发 ×0.7），射程 +20%，优先精英 / Boss；连射与 `shots` 相乘（成长拿到 2 发 → 每次 8 发）；期间每连射的最后一发对非精英造成 0.2 秒停顿 |
| 天赋 速射（精一） | — | **弹夹**：每击杀 1 名敌人弹夹 +1（上限 8）；弹夹满时下一次射击改为一次倾泻 8 发散射（±25°，每发 ×0.8，穿透 1）并清空弹夹。主控在灯光内（`_lamp_r` 内 / `e.lit`）击杀时弹夹 +2 |

**肉鸽扭转**：`shots`（每次射击子弹数）是一个干员侧属性，成长节点、精二、她自己的技能都往上加；通用藏品里带 `projectile` 标签的加成对她每发都生效，E 远程火力流派的「射程 / 远程增伤」她吃得最满；弹夹用击杀喂、在灯光内翻倍——高灯火站灯里打就是她的最优解，与流明 / 浊心斯卡蒂（充盈）协同。

**成长线**：射程 +15% → 速射 ×1.15 → 精一（S2 + 天赋）→ 自定义「双枪」：`shots` +1（每次射击 2 发）→ 自定义「跳弹」：子弹命中后 40% 概率向 120 内另一名敌人跳弹一次（×0.5，ricochet）→ 精二（S3 + 普攻质变「天使的弹幕」：`shots` 再 +1（共 3 发），弹夹上限 8 → 12）。

**数值预算**：atk 9 / cd 0.35 / range 300 / shots 1；S1 6 发 ×1.8 ≈ 5 秒普攻；S2 8 秒 +75% ≈ 6 秒普攻 + 过热；S3 10 秒 ×（4 × 0.7 = 2.8）≈ 18 秒普攻。主控属性（原作精二满级 生命 1613 / 防御 136 / 法抗 0%，远程 ×1.00）：max_hp 105、armor 1.0、arts_res 0.0、regen 1.1。档位建议 **S**（`atk +0.03, skill_power +0.03`，与乌尔比安 / 艾丽妮同档；她是「爽」的另一种代表）。

**实现成本 ≈ 6 小时**，不改 game.gd：
- 现成：脚本自推进的投射物（流明 `bolts` 同写法，命中走 `g._hit("速射") + g._damage`）；穿透 / 跳弹 = 弹体字段 `pierce_left` / `bounce_left`；`e.lit` / `_lamp_r()` 判灯光内；`on_kill(e)` 喂弹夹；停顿 = 短 `e.stun`。
- 性能：3 发/秒 × shots 3 × S3 4 = 36 发/秒上限，弹体用 `world.tb_*` 贴图矩形合批（docs/50 约定），不画圆。
- 美术：idle / run / attack（双枪连射，fire 帧要短）/ skill；特效主色「天使红」`(0.95, 0.3, 0.3)` + 白色弹道，弹夹满时枪口金光。音效：atk = 轻脆枪声（限流 0.06 秒，-11 dB）、hit = 短金属击、s1 = 装填咔嗒、s2 = 枪机加速到嗡鸣、s3 = 四连「哒哒哒哒」+ 弹壳落地；big = 弹夹倾泻。

**强度测试**：
- 单人：`--op exusiai --bot expert --seeds 12`（标准）、`--bots master --tier=2 --seeds 12`（Ⅷ），目标 50–70；对照维什戴尔 ≤ 15 个百分点。**重点看 1:15 骨潮**（Logos 当年纯单体清不动，docs/26「第二批数值粗调」）：若单人 3:30 存活 < 90%，先把成长节点「双枪」提前到第 1 节点，而不是加 atk。
- 编队：`--squad exusiai,saria,suzuran`（E 远程队）、`--squad exusiai,angelina,hoshiguma`（聚怪喂靶）；`--preset share --extra=--nodeath` 伤害占比 30–50%。
- 旋钮：偏弱先加 `shots` 的成长节点位置、再 `atk`（9 → 10）；偏强先收 `s3_mult`（0.7 → 0.6）、`mag_mult`（0.8 → 0.65），**不动 cd 0.35**（手感 / 音效限流都按它调）。

---

## 5. 安洁莉娜 `angelina`（辅助 · 控场，优先 5）

**定位**：增幅 / 控制位（DPS 预算 65%）。铃兰是「减速 + 易伤」的光域；她是**拉拽、聚拢、悬浮**——不让敌人慢，而是让敌人**挤在一起**，给艾雅法拉 / 幽灵鲨 / 星熊魔王 / 维什戴尔喂范围靶子。艾丽妮浮空是单点（天赋吃控制）；她是整片悬浮，两人同队是控制流派（C）的终点。藏品 #103「安洁莉娜的创想」（敌人移速 -15%、受到的击退 +40%，`enemy_kb`）已在池里：她的拉拽 / 悬浮**吃同一个 `enemy_kb` 倍率**，拿到创想她更强，而不是重复一遍减速。

**原作对应**（凝滞师：攻击造成法术伤害并减速）：普攻 ← 特性「法伤 + 停顿」→ 本作重力弹落点拉拽；S1「重力调节」（待核）← 原作一技能（攻击提升 + 停顿延长）；S2「重力控制」（待核：原作二技能名）← 攻击多个目标 → 本作做永久「重力场」；S3「悬浮」← 原作三技能（范围内敌人悬浮、友军回复 + 移速）；天赋「重力转换」（待核）← 原作「重量等级」相关天赋，正是 #103 创想「重量下降一个等级」的出处，两者口径对齐。

**普攻 · 重力弹**：每 1.1 秒向 320 内敌群最密处射一枚重力弹（弹速 380），落点 r60 法术伤害 atk 20，并把 r100 内非 Boss 敌人向落点**拉拢** 40（`e.kb` 反向，精英 ×0.5，重型 ×0.3 照敌人表）。DPS 18 ≈ 65% 预算。手动普攻：A 方向类（落点 = 瞄准方向上 ±45° 最近敌人距离，`aim_land`）。

| 技能 | SP | 效果 |
|---|---|---|
| S1 重力调节 | ·7 | 下 3 发重力弹：拉拢距离 ×2（80）、半径 ×1.4、落点敌人停顿 0.6 秒（精英 0.3；短硬直，不是铃兰的持续减速） |
| S2 重力控制 | ·15 **永久** | 主控周围常驻**重力场** r150：每 0.5 秒把场内非 Boss 敌人向半径 110 的**环带**拉（内侧的往外推、外侧的往里拉），把敌人束成一圈；主控移速 +8% |
| S3 悬浮 | ·24，10 秒 | 大重力场 r220：场内全部非 Boss 敌人**悬浮**（`e.air` + 刷新的 0.5 秒 stun，精英每 1.5 秒落地 0.5 秒，Boss 只减速 30%）并每秒向场心汇聚 30；队友攻速 +20%，主控每秒回复 1%、移速 +15%；**悬浮的敌人掉落的经验 / 灯油被吸向主控**（拾取范围 ×3） |
| 天赋 重力转换（精一） | — | 她的拉拽 / 汇聚吃 `enemy_kb` 倍率（#103 创想 +40% → 拉拽 +40%）；被她拉动过的敌人 2 秒内受到的**击退 +30%**（标记 `grav_t`，给斯卡蒂 / 星熊 / 塞雷娅的击退吃）；主控在灯光内时拉拽 +20% |

**肉鸽扭转**：重力场是「队形控制」——环带让近战干员打外圈、范围干员打整圈；S3 把拾取和控制绑在一起（悬浮时经验飞过来，是她独有的经济手段）；天赋把 #103 从「全局减速藏品」变成「安洁莉娜的核心件」，C 控制流派里 #103 + 她 + 艾丽妮 = 浮空 / 击退 / 增伤闭环。

**成长线**：重力弹范围 +15% → 重力弹 ×1.15 → 精一（S2 + 天赋）→ 自定义「双重引力」：重力弹落点 0.3 秒后再拉一次（×0.5）→ 自定义「潮汐锁」：重力场环带上的敌人每秒受 ×0.2 法伤 → 精二（S3 + 普攻质变「失重」：重力弹落点中心 r30 的敌人悬浮 0.6 秒）。

**数值预算**：atk 20 / cd 1.1 / range 320 / pull 40；补偿 = 聚怪（范围干员实际 DPS 提升，批跑用 `--preset share` 里队友伤害涨幅衡量）。主控属性（原作精二满级 生命 1484 / 防御 134 / 法抗 20%，远程 ×1.00）：max_hp 100、armor 1.0、arts_res 0.2、regen 1.1。档位建议 **A+**（`skill_power +0.02`）。

**实现成本 ≈ 8 小时**，不改 game.gd：
- 现成：拉拽 = `e.kb` 反向向量（enemies.gd 145–151 行已乘重型 ×0.3 与 `g.enemy_kb_mult`，非 Boss）；悬浮 = 艾丽妮 `e.air + e.stun` 的 sin 弧线（抽成共享工具更好）；拾取范围 = `stats.add(&"pickup", "mult", 3.0, "angelina_s3")`；移速 / 攻速增益 = `move_speed` / `op_aspd` 加来源；重力弹 = 维什戴尔落点弹写法（`aim_land`）。
- 新写：环带整形（每 0.5 秒一轮、按距离差给 kb）；`grav_t` 敌人字段（击退 +30% 在 `melee_hit / area_hit` 的 kb 处乘，character.gd 一处，不进 game.gd）。
- 美术：idle / run / attack（抬手，发丝飘起）/ skill；特效主色「重力紫」`(0.7, 0.5, 0.95)`：重力弹 = 紫色小球 + 内收的弧线，重力场 = 地面环带虚线缓慢旋转 + 内外两圈相向的粒子，悬浮 = 敌人脚下紫光 + 上升尘点。音效：atk = 低沉「嗡」+ 吸入感、hit = 内收的短鸣、s1 = 三声递进嗡鸣、s2 = 低频持续基底（永久定音）、s3 = 失重上扬 + 风停。

**强度测试**：
- 单人：`--op angelina --bot expert --seeds 12`（标准）、`--bots master --tier=2 --seeds 12`（Ⅷ），目标 50–70；对照铃兰 ≤ 15 个百分点。看「3:30 存活」：纯拉拽清不动骨潮时先加 `aoe`（60 → 75）。
- 编队：`--squad angelina,eyjafjalla,hoshiguma`（聚怪 + 火山 + 魔王）、`--squad angelina,irene,saria`（控制流派）；`--preset share --extra=--nodeath`：她本人占比 10–25%，**队友艾雅法拉占比对比无她时 ≥ +15%** 才算聚怪有效。
- 藏品：`--extra=--relics=103` 对比有无创想的她（预期胜率 +5–10 个百分点，若 > 15 收 `talent_kb_scale`）。
- 旋钮：偏弱先加 `pull`（40 → 55）；偏强先收 S3 `s3_pickup`（3 → 2）与 `s3_aspd`，不动环带半径（队形手感）。

---

## 6. 接入汇总与 game.gd 改动

| 干员 | 文件 | 新挂点 | game.gd / combat.gd |
|---|---|---|---|
| 浊心斯卡蒂 | `skalter.gd` + `skalter.json` | 无（`draw_auras / area_hit / stats.add / g.lamp / g.lamp_loss_mult / g.ppos`） | 0 |
| 德克萨斯 | `texas.gd` + `texas.json` | `_squad_sp_seconds()` 从 siege.gd 搬到 character.gd 共享 | **1**：`g.dash_cd_mult`（DASH_CD 常量加倍率，1146–1149 行） |
| 星熊 | `hoshiguma.gd` + `hoshiguma.json` | 无（`dmg_taken_mult` 返回 0 即格挡） | **0–1**：combat.gd 92 行灯火流失在 dmg ≤ 0 时跳过（需确认 `hit_base` 底） |
| 能天使 | `exusiai.gd` + `exusiai.json` | 无（脚本自推进弹体，流明 `bolts` 同写法） | 0 |
| 安洁莉娜 | `angelina.gd` + `angelina.json` | 浮空弧线从 irene.gd 抽成 character.gd 共享；`grav_t` 字段在 `melee_hit / area_hit` 的 kb 处乘 | 0 |

其他登记（每人都要，docs/27 §9.2）：`balance.json operators.<id>`（先写 0，定档在校验后）、`tools/balance_run.py OPS` 加 id、`sfx.gd OP_SFX` 与 `gen_sfx_ops.py`、`lore.json` 档案、`title.gd` 选人页按职业排（辅助位会有 3 人、先锋 / 重装 / 狙击各 2 人）、图鉴。美术走 docs/27 batch2 brief 的同一规格（48×48、脚底 (24, 46)、四组帧条 + @2x），本批**没有**非人物件（不像灯塔 / 替身），只有程序绘制的歌域 / 重力场 / 热砂。

总成本估计 **35 小时**（6 + 8 + 7 + 6 + 8）+ 校验批跑；按用户优先级逐人合入，每合一人跑一次 `python tools/check.py` + `--preset squads --seeds 3` 回归（老编队同 seed 逐局相同）。

---

## 7. 强度测试总表

口径：docs/38 §8.12（2026-10-01 用户定）——每档参考机器人胜率（含超时）统一 **50–70**：标准 `--tier=0` 用高手 `--bot expert`，Ⅳ / Ⅷ `--tier=1 / 2` 用熟练 `--bots master`；Ⅷ 的任何改动以不跌破 50 为约束。单人至少 12 seed（6 seed 时单人胜率会跳 30 个百分点，docs/29 §4）。

| 干员 | 单人对照 | 编队伤害占比目标 | 过强先收 | 过弱先加 |
|---|---|---|---|---|
| 浊心斯卡蒂 | 铃兰 | 10–25% | `s3_atk`、`s3_mult` | `aura`、`atk` |
| 德克萨斯 | 推进之王 | 20–35% | `talent_sp`、`s3_sp` | `hit_sp`、`atk` |
| 星熊 | 塞雷娅 | 10–25% | `s2_dr`、`s3_dr` | `block_chance`、`atk` |
| 能天使 | 维什戴尔 | 30–50% | `s3_mult`、`mag_mult` | 「双枪」节点提前、`atk` |
| 安洁莉娜 | 铃兰 | 10–25%（队友范围干员 ≥ +15%） | `s3_pickup`、`s3_aspd` | `pull`、`aoe` |

通用命令（每人换 id）：

```bash
python tools/check.py                                                   # 契约 + 冒烟 + 同 seed 复现
python tools/balance_run.py --op <id> --bot expert --seeds 12           # 标准 单人
python tools/balance_run.py --op <id> --bots master --tier=2 --seeds 12 # Ⅷ 单人
python tools/balance_run.py --squad <id>,wisadel,saria --seeds 6
python tools/balance_run.py --preset share --extra=--nodeath            # 伤害占比
python tools/balance_run.py --preset squads --seeds 3                   # 老编队回归
```

大批量（5 人 × 2 档 × 12 seed = 120 局 + 编队）按用户授权直接建一次性云端例行任务并行跑（memory：cloud-routines-for-batch-tests）。

---

## 8. 数据草案

按 `data/characters/ulpianus.json` / `irene.json` 的实际结构起草；`sprites` 段照 batch2 的模板（帧数 / fps / 出手帧以 Codex 最终 manifest 为准）；`hit_sources` 每个伤害来源都登记（docs/27 §9.2）；`progression` 六节点同构（+15% / +15% / 精一 / 自定义 / 自定义 / 精二）。脚本里**只允许** `base("key", 默认值)` 取数，默认值 = JSON 值。

### 8.1 `data/characters/skalter.json`

```json
{
 "id": "skalter",
 "name": "浊心斯卡蒂",
 "en": "SKADI THE CORRUPTING HEART",
 "class": "辅助",
 "col": [0.85, 0.25, 0.35],
 "script": "res://scripts/characters/skalter.gd",
 "base": {
  "_doc": "基础数值（docs/59 §1）；歌域以主控 g.ppos 为中心（用户 10-11 定）",
  "atk": 14, "cd": 1.0, "aura": 190, "heal_pct": 0.003, "heal_cd": 3.0,
  "s1_dur": 5.0, "s1_aura": 1.4, "s1_heal": 0.01, "s1_lamp_loss": 0.5,
  "s2_aura": 0.3, "s2_aspd": 0.15, "s2_hunter_atk": 0.15,
  "s3_dur": 12.0, "s3_aura": 2.0, "s3_atk": 0.5, "s3_mult": 3.0, "s3_heal": 0.015, "s3_lamp_drain": 2.0, "s3_dark_mult": 1.5,
  "talent_bright": 70, "talent_dark": 30, "bright_aura": 0.2, "bright_heal": 2.0, "dark_mult": 1.5, "dark_slow": 0.1, "talent_hunter": 0.04, "talent_hunter_cap": 3,
  "echo_every": 3, "echo_mult": 0.6, "resonance_mult": 0.3, "note_n": 6, "note_kb": 120, "note_cd": 0.5
 },
 "leader": {
  "_doc": "当主控时的受击属性（docs/23）：原作精二满级 生命 1530 / 防御 148 / 法抗 20%，远程主控有效生命 ×1.00",
  "max_hp": 105, "armor": 1.0, "arts_res": 0.2, "regen": 1.1
 },
 "sprites": {
  "idle": {"tex": "op_skalter_idle", "frames": 4, "fps": 4, "foot": [24, 46]},
  "run": {"tex": "op_skalter_run", "frames": 6, "fps": 10, "foot": [24, 46]},
  "attack": {"tex": "op_skalter_attack", "frames": 5, "fps": 10, "foot": [24, 46], "fire": 2},
  "skill": {"tex": "op_skalter_skill", "frames": 7, "fps": 12, "foot": [24, 46], "fire": 3},
  "size": 48, "foot": [24, 46]
 },
 "attack": {"mode": "auto", "name": "海潮低吟", "desc": "每 1.0 秒以主控为中心放出一圈声浪（半径 190），命中圈内全部敌人造成法术伤害；主控在歌域内时每 3 秒回复 0.3%"},
 "skills": [
  {"name": "吟游", "en": "WANDERING SONG", "sp": 7, "dur": 5.0, "desc": "5 秒：歌域 ×1.4、主控每秒回复 1%，期间受击灯火流失减半", "icon": "skill_skalter_s1"},
  {"name": "深海的呼唤", "en": "CALL OF THE DEEP", "sp": 15, "permanent": true, "desc": "充能一次后永久生效：歌域 +30%；歌域内队友攻速 +15%，深海猎人（斯卡蒂、乌尔比安、归溟幽灵鲨）再 +15% 攻击", "icon": "skill_skalter_s2"},
  {"name": "死地之歌", "en": "SONG OF THE DEAD LAND", "sp": 24, "dur": 12.0, "desc": "12 秒：歌域 ×2、全队攻击 +50%、声浪 ×3、主控每秒回复 1.5%；代价是灯火每秒 -2。灯火昏暗（< 30）时不再扣灯火，改为声浪再 ×1.5", "icon": "skill_skalter_s3"}
 ],
 "talent": {"name": "溟海颂歌", "desc": "灯火充盈（≥ 70）：歌域 +20%、回复翻倍；昏暗（< 30）：声浪 +50%、歌域内敌人移速 -10%；编队里每名深海猎人，歌域内队友攻击 +4%（最多 3 人）"},
 "hit_sources": {
  "声浪": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["area", "basic"]},
  "潮汐和声": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["follow_up", "area"]},
  "深海的回响": {"emitter": "operator", "origin": "skill", "range": "远程", "kind": "法术", "tags": ["skill", "area", "dot"]},
  "死地之歌": {"emitter": "operator", "origin": "skill", "range": "远程", "kind": "法术", "tags": ["skill", "area"]},
  "溟海之声": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["basic", "area", "control"]}
 },
 "progression": [
  {"type": "stat", "stat": "aura", "mult": 1.15, "name": "歌域扩张", "icon": "growth_b_range", "desc": "声浪半径 +15%"},
  {"type": "stat", "stat": "atk", "mult": 1.15, "name": "潮声渐强", "icon": "growth_b_atk", "desc": "声浪伤害 +15%"},
  {"type": "elite", "level": 1, "name": "精英一", "desc": "解锁二技能「深海的呼唤」；解锁天赋「溟海颂歌」：灯火高低决定歌域是治愈还是溟海"},
  {"type": "custom", "id": "echo", "name": "潮汐和声", "icon": "growth_b_echo", "desc": "每第 3 次声浪追加一次回声（60% 伤害）"},
  {"type": "custom", "id": "resonance", "name": "深海的回响", "icon": "skill_skalter_s1", "desc": "「吟游」期间歌域内敌人每秒额外受到声浪 30% 的法术伤害"},
  {"type": "elite", "level": 2, "name": "精英二", "desc": "解锁三技能「死地之歌」；普攻质变「溟海之声」：歌域边缘 6 个绕行的海潮音符，碰到的敌人被推开"}
 ],
 "gallery": {"tags": ["增益", "光环", "灯火", "深海猎人"], "desc": "歌声绕着博士回荡：灯火充盈时是治愈的歌，昏暗时是溟海的歌；深海猎人在她身边更强"}
}
```

> `progression` 里 `"type": "stat"` 两条是示意：现有干员的前两节点写法以 `character.gd advance()` 实际支持的类型为准（乌尔比安 / 艾丽妮用的是 `custom`），落地时照抄一名现有干员的前两节点。

### 8.2 `data/characters/texas.json`

```json
{
 "id": "texas",
 "name": "德克萨斯",
 "en": "TEXAS",
 "class": "先锋",
 "col": [1.0, 0.55, 0.2],
 "script": "res://scripts/characters/texas.gd",
 "base": {
  "_doc": "基础数值（docs/59 §2）",
  "atk": 26, "cd": 1.1, "dash_len": 140, "dash_w": 44, "dash_t": 0.18, "dash_hold": 0.15, "hit_sp": 0.6,
  "s1_r": 130, "s1_mult": 1.6, "s1_stun": 0.5, "s1_stun_elite": 0.25, "s1_sp": 0.10,
  "s2_len": 0.4, "s2_mult": 1.3, "s2_dash_cd": 0.2,
  "s3_dur": 8.0, "s3_every": 0.5, "s3_mult": 0.9, "s3_stun": 0.3, "s3_sp": 0.4, "s3_end_mult": 1.6,
  "talent_cd": 2.0, "talent_sp": 1.0, "talent_many": 3, "talent_many_sp": 0.3,
  "back_delay": 0.2, "back_mult": 0.5, "rain2_delay": 0.3, "rain2_mult": 0.6, "trail_life": 0.6, "trail_mult": 0.3, "trail_slow": 0.5
 },
 "leader": {
  "_doc": "当主控时的受击属性（docs/23）：原作精二满级 生命 1986 / 防御 441 / 法抗 0%，近战主控有效生命 ×1.06",
  "max_hp": 118, "armor": 3.0, "arts_res": 0.0, "regen": 1.3
 },
 "sprites": {
  "idle": {"tex": "op_texas_idle", "frames": 4, "fps": 4, "foot": [24, 46]},
  "run": {"tex": "op_texas_run", "frames": 6, "fps": 10, "foot": [24, 46]},
  "attack": {"tex": "op_texas_attack", "frames": 5, "fps": 14, "foot": [24, 46], "fire": 1},
  "skill": {"tex": "op_texas_skill", "frames": 7, "fps": 12, "foot": [24, 46], "fire": 3},
  "size": 48, "foot": [24, 46]
 },
 "attack": {"mode": "auto", "name": "疾行斩", "desc": "每 1.1 秒朝最近敌人方向冲刺 140（宽 44，穿透），沿途全部敌人受物理伤害；穿过敌人时全队技力 +0.6 秒"},
 "skills": [
  {"name": "剑雨", "en": "SWORD RAIN", "sp": 6, "desc": "以自身为中心半径 130 落下剑雨，×1.6 并眩晕 0.5 秒（精英 0.25 秒，Boss 不晕），全队技力 +10%", "icon": "skill_texas_s1"},
  {"name": "可靠伙伴", "en": "RELIABLE PARTNER", "sp": 14, "permanent": true, "desc": "充能一次后永久生效：冲刺距离 +40%、疾行斩 ×1.3；主控的冲刺冷却 -20%", "icon": "skill_texas_s2"},
  {"name": "速递", "en": "EXPRESS DELIVERY", "sp": 20, "dur": 8.0, "desc": "8 秒内每 0.5 秒向敌群最密处冲刺一次（×0.9），穿过的敌人眩晕 0.3 秒、全队技力 +0.4 秒；结束时落点剑雨 ×1.6", "icon": "skill_texas_s3"}
 ],
 "talent": {"name": "冲锋手", "desc": "主控按下冲刺时德克萨斯同步冲一次疾行斩（每 2 秒至多一次）并全队技力 +1 秒；一次穿过 3 名以上敌人时额外 +0.3 秒"},
 "hit_sources": {
  "疾行斩": {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["pierce", "basic"]},
  "剑雨": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "area", "stun"]},
  "速递": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "pierce", "stun"]},
  "回马剑": {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["follow_up", "pierce"]},
  "余像": {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["basic", "dot", "control"]}
 },
 "progression": [
  {"type": "custom", "id": "wide", "name": "阔剑", "icon": "growth_b_range", "desc": "冲刺宽度 +30%"},
  {"type": "custom", "id": "sharp", "name": "利刃", "icon": "growth_b_atk", "desc": "疾行斩 ×1.15"},
  {"type": "elite", "level": 1, "name": "精英一", "desc": "解锁二技能「可靠伙伴」；解锁天赋「冲锋手」：主控冲刺时她同步冲刺并为全队回技力"},
  {"type": "custom", "id": "back", "name": "回马剑", "icon": "growth_b_echo", "desc": "冲到头 0.2 秒后原路反冲一次（50% 伤害）"},
  {"type": "custom", "id": "rain2", "name": "剑雨·连", "icon": "skill_texas_s1", "desc": "「剑雨」0.3 秒后再落一次（60% 伤害，重新瞄准）"},
  {"type": "elite", "level": 2, "name": "精英二", "desc": "解锁三技能「速递」；普攻质变「余像」：冲刺路径上留下 0.6 秒剑气残像，踩进的敌人受 30% 伤害并减速"}
 ],
 "gallery": {"tags": ["近战", "位移", "穿透", "技力"], "desc": "冲刺穿过敌阵为全队回技力；你一按冲刺，她就跟着冲"}
}
```

### 8.3 `data/characters/hoshiguma.json`

```json
{
 "id": "hoshiguma",
 "name": "星熊",
 "en": "HOSHIGUMA",
 "class": "重装",
 "col": [0.95, 0.75, 0.3],
 "script": "res://scripts/characters/hoshiguma.gd",
 "base": {
  "_doc": "基础数值（docs/59 §3）",
  "atk": 30, "cd": 1.1, "reach": 110, "arc_deg": 140, "kb": 220,
  "block_chance": 0.20, "block_chance_boss": 0.10, "block_kb_r": 90, "block_kb": 200, "beacon_bonus": 0.15,
  "s1_window": 3.0, "s1_mult": 2.0, "s1_r": 120, "s1_kb": 360, "s1_miss_mult": 1.5,
  "s2_dur": 8.0, "s2_atk": 0.4, "s2_dr": 0.2, "s2_block_x": 2.0, "sand_dur": 2.0, "sand_r": 80, "sand_mult": 0.3,
  "s3_dur": 10.0, "s3_atk": 0.6, "s3_len": 220, "s3_w": 50, "s3_kb": 1.5, "s3_dr": 0.3, "s3_quake_r": 120, "s3_quake_kb": 300,
  "wall_stun": 0.4, "ember_dur": 4.0, "ember_mult": 0.5, "oni_every": 4, "oni_mult": 1.3
 },
 "leader": {
  "_doc": "当主控时的受击属性（docs/23）：原作精二满级 生命 3446 / 防御 625 / 法抗 10%，近战主控有效生命 ×1.06",
  "max_hp": 128, "armor": 3.5, "arts_res": 0.1, "regen": 1.0
 },
 "sprites": {
  "idle": {"tex": "op_hoshiguma_idle", "frames": 4, "fps": 4, "foot": [24, 46]},
  "run": {"tex": "op_hoshiguma_run", "frames": 6, "fps": 10, "foot": [24, 46]},
  "attack": {"tex": "op_hoshiguma_attack", "frames": 5, "fps": 12, "foot": [24, 46], "fire": 3},
  "skill": {"tex": "op_hoshiguma_skill", "frames": 7, "fps": 12, "foot": [24, 46], "fire": 2},
  "size": 48, "foot": [24, 46]
 },
 "attack": {"mode": "auto", "name": "盾斧斩", "desc": "每 1.1 秒前压横扫 140°（半径 110），命中击退"},
 "skills": [
  {"name": "举盾", "en": "SHIELD UP", "sp": 6, "dur": 3.0, "desc": "3 秒内主控下一次受到的伤害被完全格挡（不掉灯火），格挡瞬间反手重斩半径 120 ×2.0 并击退；没挨打则向前一记 ×1.5", "icon": "skill_hoshiguma_s1"},
  {"name": "热砂", "en": "SCORCHING SANDS", "sp": 14, "dur": 8.0, "desc": "8 秒：攻击 +40%、主控受到的伤害 -20%、「盾卫」概率 ×2；斩击落点留下 2 秒热砂，踩进的敌人每秒灼伤", "icon": "skill_hoshiguma_s2"},
  {"name": "魔王", "en": "DEMON KING", "sp": 22, "dur": 10.0, "desc": "10 秒：攻击 +60%，盾斧斩改为直线斩（长 220、宽 50，命中沿线全部），击退 ×1.5；主控受伤 -30%，每次受击触发半径 120 震退", "icon": "skill_hoshiguma_s3"}
 ],
 "talent": {"name": "盾卫", "desc": "主控每次受伤 20% 概率完全免伤（Boss 攻击 10%），免伤的攻击不掉灯火，并推开半径 90 内敌人；灯标读条期间概率 +15%"},
 "hit_sources": {
  "盾斧斩": {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["area", "basic"]},
  "举盾反击": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "area"]},
  "热砂": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "area", "dot"]},
  "魔王": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "pierce", "area"]},
  "震退": {"emitter": "operator", "origin": "skill", "range": "近战", "kind": "物理", "tags": ["skill", "area", "control"]},
  "鬼面": {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["basic", "pierce"]}
 },
 "progression": [
  {"type": "custom", "id": "reach", "name": "阔斩", "icon": "growth_b_range", "desc": "盾斧斩范围 +15%"},
  {"type": "custom", "id": "heavy", "name": "重刃", "icon": "growth_b_atk", "desc": "盾斧斩 ×1.15"},
  {"type": "elite", "level": 1, "name": "精英一", "desc": "解锁二技能「热砂」；解锁天赋「盾卫」：概率完全免伤，挡下的攻击不掉灯火"},
  {"type": "custom", "id": "wall", "name": "盾墙", "icon": "growth_u_area", "desc": "盾卫免伤时推开的敌人眩晕 0.4 秒"},
  {"type": "custom", "id": "ember", "name": "热砂·余烬", "icon": "skill_hoshiguma_s2", "desc": "热砂持续 2 → 4 秒，灼伤 ×0.5"},
  {"type": "elite", "level": 2, "name": "精英二", "desc": "解锁三技能「魔王」；普攻质变「鬼面」：每第 4 次盾斧斩变成一记直线斩（×1.3）"}
 ],
 "gallery": {"tags": ["近战", "格挡", "击退", "护卫"], "desc": "不治疗的重装：概率把伤害完全挡下、挡下就反砍，魔王一刀穿一列"}
}
```

### 8.4 `data/characters/exusiai.json`

```json
{
 "id": "exusiai",
 "name": "能天使",
 "en": "EXUSIAI",
 "class": "狙击",
 "col": [0.95, 0.3, 0.3],
 "script": "res://scripts/characters/exusiai.gd",
 "base": {
  "_doc": "基础数值（docs/59 §4）；shots = 每次射击子弹数，是她全部成长的轴",
  "atk": 9, "cd": 0.35, "range": 300, "bullet_speed": 520, "shots": 1, "spread_deg": 8, "elite_prio": 1.2,
  "s1_ammo": 6, "s1_mult": 1.8, "s1_pierce": 1,
  "s2_dur": 8.0, "s2_cd": 0.20, "s2_mult": 0.9, "s2_overheat": 1.0,
  "s3_dur": 10.0, "s3_burst": 4, "s3_gap": 0.06, "s3_mult": 0.7, "s3_range": 0.2, "s3_pause": 0.2,
  "mag_cap": 8, "mag_lit_bonus": 2, "mag_shots": 8, "mag_spread_deg": 25, "mag_mult": 0.8, "mag_pierce": 1,
  "twin_shots": 1, "ricochet_chance": 0.4, "ricochet_r": 120, "ricochet_mult": 0.5, "e2_shots": 1, "e2_mag_cap": 12
 },
 "leader": {
  "_doc": "当主控时的受击属性（docs/23）：原作精二满级 生命 1613 / 防御 136 / 法抗 0%，远程主控有效生命 ×1.00",
  "max_hp": 105, "armor": 1.0, "arts_res": 0.0, "regen": 1.1
 },
 "sprites": {
  "idle": {"tex": "op_exusiai_idle", "frames": 4, "fps": 4, "foot": [24, 46]},
  "run": {"tex": "op_exusiai_run", "frames": 6, "fps": 10, "foot": [24, 46]},
  "attack": {"tex": "op_exusiai_attack", "frames": 3, "fps": 16, "foot": [24, 46], "fire": 0},
  "skill": {"tex": "op_exusiai_skill", "frames": 7, "fps": 12, "foot": [24, 46], "fire": 3},
  "size": 48, "foot": [24, 46]
 },
 "attack": {"mode": "auto", "name": "速射", "desc": "每 0.35 秒向最近敌人（精英优先）射出 1 发物理弹（射程 300）；每次射击的子弹数可成长，多发时各自索敌"},
 "skills": [
  {"name": "强力击", "en": "POWER STRIKE", "sp": 6, "desc": "装填 6 发强力弹：之后的射击每发 ×1.8 并穿透 1 名敌人，打完为止", "icon": "skill_exusiai_s1"},
  {"name": "过载模式", "en": "OVERDRIVE MODE", "sp": 14, "dur": 8.0, "desc": "8 秒：射击间隔 0.35 → 0.20，每发 ×0.9；结束时过热 1 秒不射", "icon": "skill_exusiai_s2"},
  {"name": "处决模式", "en": "EXECUTION MODE", "sp": 22, "dur": 10.0, "desc": "10 秒：每次射击改为 4 连射（每发 ×0.7），射程 +20%，优先精英 / Boss；连射与子弹数相乘；每轮最后一发让非精英停顿 0.2 秒", "icon": "skill_exusiai_s3"}
 ],
 "talent": {"name": "速射", "desc": "弹夹：每击杀 1 名敌人 +1（上限 8），主控在灯光内击杀 +2；弹夹满时下一次射击倾泻 8 发散射（每发 ×0.8，穿透 1）并清空"},
 "hit_sources": {
  "速射": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "物理", "tags": ["projectile", "basic"]},
  "强力击": {"emitter": "operator", "origin": "skill", "range": "远程", "kind": "物理", "tags": ["skill", "projectile", "pierce"]},
  "处决模式": {"emitter": "operator", "origin": "skill", "range": "远程", "kind": "物理", "tags": ["skill", "projectile"]},
  "弹夹倾泻": {"emitter": "operator", "origin": "talent", "range": "远程", "kind": "物理", "tags": ["projectile", "pierce", "area"]},
  "跳弹": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "物理", "tags": ["follow_up", "ricochet"]}
 },
 "progression": [
  {"type": "custom", "id": "range", "name": "延长弹道", "icon": "growth_b_range", "desc": "射程 +15%"},
  {"type": "custom", "id": "power", "name": "高压弹", "icon": "growth_b_atk", "desc": "速射 ×1.15"},
  {"type": "elite", "level": 1, "name": "精英一", "desc": "解锁二技能「过载模式」；解锁天赋「速射」：击杀喂满弹夹后倾泻 8 发"},
  {"type": "custom", "id": "twin", "name": "双枪", "icon": "growth_b_count", "desc": "每次射击子弹数 +1"},
  {"type": "custom", "id": "ricochet", "name": "跳弹", "icon": "growth_b_echo", "desc": "子弹命中后 40% 概率跳向 120 内另一名敌人（50% 伤害）"},
  {"type": "elite", "level": 2, "name": "精英二", "desc": "解锁三技能「处决模式」；普攻质变「天使的弹幕」：子弹数再 +1，弹夹上限 8 → 12"}
 ],
 "gallery": {"tags": ["远程", "连射", "单体", "子弹数"], "desc": "一秒三发的速射手；每次射击的子弹数越养越多，弹夹打满就倾泻"}
}
```

### 8.5 `data/characters/angelina.json`

```json
{
 "id": "angelina",
 "name": "安洁莉娜",
 "en": "ANGELINA",
 "class": "辅助",
 "col": [0.7, 0.5, 0.95],
 "script": "res://scripts/characters/angelina.gd",
 "base": {
  "_doc": "基础数值（docs/59 §5）；拉拽走 e.kb 反向，吃 enemy_kb 倍率（藏品 #103）",
  "atk": 20, "cd": 1.1, "range": 320, "bullet_speed": 380, "aoe": 60, "pull_r": 100, "pull": 40, "pull_elite": 0.5,
  "s1_n": 3, "s1_pull": 2.0, "s1_r": 1.4, "s1_pause": 0.6, "s1_pause_elite": 0.3,
  "s2_r": 150, "s2_ring": 110, "s2_every": 0.5, "s2_force": 30, "s2_speed": 0.08,
  "s3_dur": 10.0, "s3_r": 220, "s3_stun": 0.5, "s3_elite_up": 1.5, "s3_elite_down": 0.5, "s3_boss_slow": 0.3, "s3_gather": 30, "s3_aspd": 0.2, "s3_heal": 0.01, "s3_speed": 0.15, "s3_pickup": 3.0,
  "talent_kb_scale": 1.0, "grav_dur": 2.0, "grav_kb": 0.3, "talent_lit": 0.2,
  "pull2_delay": 0.3, "pull2_mult": 0.5, "lock_mult": 0.2, "lock_tick": 1.0, "zero_r": 30, "zero_air": 0.6
 },
 "leader": {
  "_doc": "当主控时的受击属性（docs/23）：原作精二满级 生命 1484 / 防御 134 / 法抗 20%，远程主控有效生命 ×1.00",
  "max_hp": 100, "armor": 1.0, "arts_res": 0.2, "regen": 1.1
 },
 "sprites": {
  "idle": {"tex": "op_angelina_idle", "frames": 4, "fps": 4, "foot": [24, 46]},
  "run": {"tex": "op_angelina_run", "frames": 6, "fps": 10, "foot": [24, 46]},
  "attack": {"tex": "op_angelina_attack", "frames": 5, "fps": 10, "foot": [24, 46], "fire": 2},
  "skill": {"tex": "op_angelina_skill", "frames": 7, "fps": 12, "foot": [24, 46], "fire": 3},
  "size": 48, "foot": [24, 46]
 },
 "attack": {"mode": "auto", "name": "重力弹", "desc": "每 1.1 秒向敌群最密处射一枚重力弹（射程 320）：落点半径 60 法术伤害，并把半径 100 内的敌人向落点拉拢"},
 "skills": [
  {"name": "重力调节", "en": "GRAVITY ADJUSTMENT", "sp": 7, "desc": "下 3 发重力弹：拉拢距离 ×2、范围 ×1.4，落点敌人停顿 0.6 秒（精英 0.3 秒）", "icon": "skill_angelina_s1"},
  {"name": "重力控制", "en": "GRAVITY CONTROL", "sp": 15, "permanent": true, "desc": "充能一次后永久生效：主控周围常驻重力场（半径 150），每 0.5 秒把场内敌人拉向半径 110 的环带，束成一圈；主控移速 +8%", "icon": "skill_angelina_s2"},
  {"name": "悬浮", "en": "LEVITATION", "sp": 24, "dur": 10.0, "desc": "10 秒：半径 220 内全部非 Boss 敌人悬浮并向场心汇聚（精英间歇落地，Boss 减速 30%）；队友攻速 +20%，主控每秒回复 1%、移速 +15%；悬浮敌人掉落的经验 / 灯油被吸向主控", "icon": "skill_angelina_s3"}
 ],
 "talent": {"name": "重力转换", "desc": "拉拽 / 汇聚吃敌人受到的击退倍率（藏品「安洁莉娜的创想」+40%）；被她拉动过的敌人 2 秒内受到的击退 +30%；主控在灯光内时拉拽 +20%"},
 "hit_sources": {
  "重力弹": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["projectile", "area", "basic", "control"]},
  "重力调节": {"emitter": "operator", "origin": "skill", "range": "远程", "kind": "法术", "tags": ["skill", "area", "control"]},
  "潮汐锁": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["dot", "area"]},
  "双重引力": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["follow_up", "area", "control"]},
  "失重": {"emitter": "operator", "origin": "core", "range": "远程", "kind": "法术", "tags": ["basic", "control"]}
 },
 "progression": [
  {"type": "custom", "id": "wide", "name": "引力扩散", "icon": "growth_b_range", "desc": "重力弹范围 +15%"},
  {"type": "custom", "id": "dense", "name": "致密", "icon": "growth_b_atk", "desc": "重力弹 ×1.15"},
  {"type": "elite", "level": 1, "name": "精英一", "desc": "解锁二技能「重力控制」；解锁天赋「重力转换」：拉拽吃击退倍率，被拉过的敌人更容易被击退"},
  {"type": "custom", "id": "pull2", "name": "双重引力", "icon": "growth_b_echo", "desc": "重力弹落点 0.3 秒后再拉一次（50% 伤害）"},
  {"type": "custom", "id": "lock", "name": "潮汐锁", "icon": "skill_angelina_s2", "desc": "重力场环带上的敌人每秒受到重力弹 20% 的法术伤害"},
  {"type": "elite", "level": 2, "name": "精英二", "desc": "解锁三技能「悬浮」；普攻质变「失重」：重力弹落点中心半径 30 的敌人悬浮 0.6 秒"}
 ],
 "gallery": {"tags": ["远程", "聚怪", "悬浮", "控制"], "desc": "把敌人拉成一圈再整片托上天，给范围干员喂靶子；拿到「安洁莉娜的创想」拉得更狠"}
}
```

### 8.6 `balance.json operators` 追加（先写 0，定档在 §7 校验后）

```json
"skalter":   {"tier": "A+", "atk": 0.0,  "aspd": 0.0, "range": 0.0, "skill_power": 0.02},
"texas":     {"tier": "A",  "atk": 0.0,  "aspd": 0.0, "range": 0.0, "skill_power": 0.0},
"hoshiguma": {"tier": "A+", "atk": 0.0,  "aspd": 0.0, "range": 0.0, "skill_power": 0.02},
"exusiai":   {"tier": "S",  "atk": 0.03, "aspd": 0.0, "range": 0.0, "skill_power": 0.03},
"angelina":  {"tier": "A+", "atk": 0.0,  "aspd": 0.0, "range": 0.0, "skill_power": 0.02}
```

### 8.7 脚本骨架（每人 `scripts/characters/<id>.gd`，继承 character.gd）

要覆写的挂点（照 ulpianus.gd / irene.gd / lumen.gd）：

| 干员 | `update` 里做 | `_release` / `_release_skill` | 额外覆写 |
|---|---|---|---|
| skalter | 歌域中心 = `g.ppos`（无主控时退回 pos）；每 cd 一次 `area_hit("声浪")`；每帧按在域内的队友刷新 `stats` 来源 `skalter_song`；S3 期间 `g.lamp -= drain * dt`；`g.lamp` 三档切状态 | S1 / S3 开计时；S2 `perm[1] = true` 后一次性 `stats.add` | `draw_auras()`（歌域）、`skill_active_left()` |
| texas | 冲刺状态机（覆盖 pos，follow 之后）；线段命中去重；`g.dash_t` 上升沿触发天赋（`talent_cd`）；每次穿人 `_squad_sp_seconds()` | S1 `area_hit` + stun；S2 永久写 `g.dash_cd_mult`；S3 连冲计时 | `sync_stats()` 写 `g.dash_cd_mult`、`atk_point / atk_angle`（A 类手动） |
| hoshiguma | S1 窗口计时、热砂地带 tick、S3 直线斩切换 | S1 / S2 / S3 | **`dmg_taken_mult()`**：S1 窗口内返回 0 并触发反击；否则按 `block_chance`（`g.rng`）返回 0 / 乘 S2、S3 减伤；格挡时 `area_hit(kb)` |
| exusiai | 自推进弹体（`bolts`，含 pierce / bounce）；弹夹计数；S2 过热计时 | S1 装填 `ammo`；S2 / S3 计时 | `on_kill(e)` 喂弹夹（灯光内 +2）、`aim_targets`（B 类手动）、`draw_fx_add`（弹道用 tb_* 合批） |
| angelina | 重力弹飞行 + 落点拉拢（`e.kb -= dir * pull * g.enemy_kb_mult`）；S2 环带整形每 0.5 秒；S3 悬浮弧线（共享工具）、`grav_t` 衰减 | S1 计数；S2 永久（`stats.add pickup/move_speed`）；S3 计时 | `aim_land`（A 类手动落点）、`draw_auras()`（重力场） |

共享改动（两处小重构，不改行为）：`_squad_sp_seconds()` 从 siege.gd 搬到 character.gd；浮空弧线从 irene.gd 抽成 `character.lift(e, dur, height)`。

### 8.8 `lore.json` 档案（草稿，文案会话可改）

- **skalter**：性别 女 / 出身地 阿戈尔 / 种族 阿戈尔 / 所属 深海猎人。「歌声从海底传来，温柔得让人想沉下去。」被「溟海之心」侵染的斯卡蒂，以歌声代替大剑：她的歌能治愈，也能召来海的注视。歌声总是绕着博士——她说过，她只对一个人唱。
- **texas**：女 / 叙拉古 / 鲁珀 / 企鹅物流。「快递到了，签收。」企鹅物流的送货员与前科西嘉家族的继承人；话少、剑快，冲进敌阵像穿过一条街，队友的技能节奏就是她的送货节奏。
- **hoshiguma**：女 / 东国 / 鬼 / 龙门近卫局。「站我后面，别客气。」龙门近卫局的盾与大刀：她不替你包扎，她让你根本挨不到那一下——挡下来的，她会原样砍回去。
- **exusiai**：女 / 拉特兰 / 萨科塔 / 企鹅物流。「苹果派可以慢一点，子弹不行。」企鹅物流的速射手，一秒三发还嫌慢；弹夹永远在换、笑容永远在脸上。
- **angelina**：女 / 叙拉古 / 鲁珀 / 罗德岛。「重力这种东西，稍微调一下就好啦。」罗德岛的重力术师；她不让敌人慢下来，而是让它们挤到一起、再一起浮起来。

### 8.9 音效登记（`sfx.gd OP_SFX`）

| 干员 | 类别 |
|---|---|
| skalter | atk, s1, s2, s3 |
| texas | atk, hit, s1, s2, s3 |
| hoshiguma | atk, hit, s1, s2, s3, big（格挡） |
| exusiai | atk, hit, s1, s2, s3, big（弹夹倾泻） |
| angelina | atk, hit, s1, s2, s3 |

音色描述见各人「实现成本」行；合成脚本 `game/tools/gen_sfx_ops.py` 末尾照 docs/28「加新干员」三步接。

---

## 9. 待用户 / 制作人定

**用户 10-11 已定**：
1. 德克萨斯 S3 换缄默德克萨斯的三技能原作名，机制不变；实装时对 PRTS 核名，替换 JSON 与成长节点里的暂名「速递」。
2. 星熊分支名用官方「铁卫」。
3. 标（待核）的原作技能名：落地前对 PRTS 核一次，核对结果直接改 JSON，不回头改本文。
4. 浊心斯卡蒂歌域改为**以主控为中心**（原稿以博士为中心）；她自己当主控时就是以她自己为中心。

---

## 10. 积木化方案（用户 10-11 追加要求：第三批作为「数据驱动干员」的第一步，面向将来的玩家自制干员 / 创意工坊）

> 现状：`characters/op_api.gd`（09-26）是**代码接口层**——每名干员仍是 400–860 行的 .gd（13 人共 9825 行），只是统一经 op_api 调 game.gd；藏品则已经完全数据化（`relic_effects.json` 跑在 `relic_fx.gd` 的 29 条原语上，docs/57 §1）。本节把干员也拆成一组原语，第三批五人**全部用数据表达**，真正需要代码的地方用逃生口 `"custom": "<func>"` 标出并压到最少。
> 原语命名一律用通用的 `族/名`（`shape/fan`、`verb/buff`、`ctrl/levitate`、`trig/on_kill`），**与另一会话正在写的 docs/60_skill_tag_catalog.md（原作技能 / 天赋 / 特性词汇表）事后对齐**：docs/60 若给出更合适的名字或拆分，以合并后的表为准，本节的名字只是第一版。

### 10.1 原语表（第一版）

六族：`shape`（攻击形状）、`verb`（技能动词）、`ctrl`（控制，verb 的子族，单列是因为它们改敌人字段）、`trig`（天赋 / 质变触发）、`cond`（条件与数值来源）、`mod`（修饰：对谁、乘多少、持续多久）。每条原语的参数都从干员 JSON `base` 取数（`"$key"` 引用），脚本里不写裸数字（docs/27 §9.5）。

**shape — 攻击形状**（一次「出手」命中谁，返回命中列表；全部已有实现）

| 原语 | 参数 | 对应现成代码 |
|---|---|---|
| `shape/fan` 扇形 | `reach, half_deg, origin_off, kb, stun` | `melee_hit()`（斯卡蒂、塞雷娅、推进之王、星熊） |
| `shape/ring` 环 | `r, kb` | `area_hit()` 以自身 / 任意点为心（幽灵鲨、浊心斯卡蒂声浪） |
| `shape/line` 直线穿刺 | `len, w, pierce, two_stage` | 艾丽妮刺剑的线段判定（德克萨斯、星熊魔王） |
| `shape/dash_line` 冲刺穿行 | `len, w, speed, hold` | 乌尔比安弹射的 pos 覆盖 + `shape/line`（德克萨斯） |
| `shape/bolt` 弹道 | `range, speed, shots, spread_deg, pierce, bounce, homing, target: nearest/elite/densest` | 流明 `bolts` / 铃兰狐火（能天使、安洁莉娜重力弹、Logos） |
| `shape/land` 落点爆炸 | `range, aoe, speed, arc` | 维什戴尔炮击 / 艾雅法拉火山弹 `aim_land` |
| `shape/aura` 光域 | `r, every, center: self/leader/doctor/point` | 铃兰光域 / 浊心斯卡蒂歌域 / 安洁莉娜重力场 |
| `shape/summon` 召唤物 | `what, dur, r, follow` | `extra_bodies()`（Mon3tr、灯塔、替身） |

**verb — 技能动词**（技能 / 普攻命中后做什么；可叠多条）

| 原语 | 参数 | 对应现成代码 |
|---|---|---|
| `verb/damage` | `mult, kind: 物理/法术/真实, src, tags` | `g._hit + deal_damage` |
| `verb/buff` | `stat, op: add/mult, value, who: self/leader/squad/class:<x>/ids:<...>/in_aura, dur (0 = 永久), source` | `g.stats.add(..., "op:<id>")`（乌尔比安 / 铃兰 / 浊心斯卡蒂） |
| `verb/heal` | `pct, who: leader, every` | `heal_leader()`（凯尔希 / 流明 / 塞雷娅） |
| `verb/cleanse` | `corrode, nerve, nerve_amount` | 流明 S1 |
| `verb/lamp` | `delta, per_sec, loss_mult, dur` | `g.lamp / g.lamp_loss_mult`（流明、浊心斯卡蒂） |
| `verb/sp` | `who: squad, seconds / pct, exclude_self` | `_squad_sp_seconds()` / `squad.gain_sp()`（推进之王、德克萨斯） |
| `verb/ammo` | `n, attack_patch` 次数型 | 维什戴尔 S3 / 能天使 S1 |
| `verb/mode` | `dur, attack / attack_patch, cd_mult, then_end: <verb list>` 形态变化 | 维什戴尔 S3 高速平射、星熊魔王、能天使处决模式 |
| `verb/move` | `to: point/densest/anchor, dist, speed` | 乌尔比安弹射 |
| `verb/field` | `dur, shape/aura 参数, tick: <verb list>, on_enter / on_leave` | 塞雷娅钙质化 / 铃兰迷雾 / 流明灯塔 / 安洁莉娜悬浮 |
| `verb/pickup_magnet` | `mult, dur` | `stats.add(&"pickup")` |
| `verb/negate_next` / `verb/negate` | `window, on_block: <verb list>, on_miss: <verb list>` / `keep_lamp` | 星熊举盾 / 盾卫（`dmg_taken_mult` 返回 0） |
| `verb/counter` | `name, add / set, cap` 命名计数器 | 能天使弹夹、乌尔比安血脉层数（将来） |

**ctrl — 控制**（写敌人字段，带精英 / Boss 折扣参数 `elite_mult, boss: 0/减速`）

| 原语 | 字段 |
|---|---|
| `ctrl/stun` | `e.stun` |
| `ctrl/slow` | `e.slow`（时长型，减速状态） |
| `ctrl/slow_soft` | 只乘移速、不算减速状态（浊心斯卡蒂昏暗 -10%、安洁莉娜对 Boss） |
| `ctrl/pause` | 短 `e.stun`（0.2–0.6，原作「停顿」） |
| `ctrl/levitate` | `e.air + e.stun` 弧线（艾丽妮 → 共享工具 `lift()`） |
| `ctrl/pull` | `e.kb` 反向 × `g.enemy_kb_mult`（安洁莉娜、乌尔比安 S1 的钩拽） |
| `ctrl/knockback` | `e.kb` |
| `ctrl/ring_shape` | 环带整形（安洁莉娜 S2：内推外拉到 `ring` 半径；塞雷娅阻挡圈 = 「全推」特例） |
| `ctrl/mark` | 自定义敌人字段 `{name, dur}`（`lit / requiem / grav_t`），由 `cond/marked` 读 |
| `ctrl/bullet_slow` | 遍历 `g.ebullets`（Logos S3） |

**trig — 触发**（天赋 / 成长节点 / 精二质变挂在哪）

| 原语 | 说明 |
|---|---|
| `trig/on_hit` | 每次普攻命中（`count_every: N` = 每第 N 次，`min_targets`，`delay`） |
| `trig/on_attack_start` | 起手前（可 `replace_attack` 换这一次的形状） |
| `trig/on_kill` | `on_kill(e)`，`filter: elite/boss/any`，`cond: in_light` |
| `trig/on_skill_start` / `trig/on_skill_end` | 哪个技能（S1–S3） |
| `trig/on_damage_taken` | 主控受伤（`chance`，`boss_chance`，`chance_add`，用 `g.rng`）——星熊盾卫 |
| `trig/on_leader_dash` | `g.dash_t` 上升沿——德克萨斯天赋 |
| `trig/tick` | `every` 秒，可 `cond: skill_active:<i>` |
| `trig/lamp_band` | 灯火进入 / 离开档（`>= 70`、`< 30`）——浊心斯卡蒂、幽灵鲨 |
| `trig/beacon_charging` | 主控在灯标读条中——星熊 |
| `trig/hp_threshold` | 主控生命 `< pct`——幽灵鲨 S1 的损失生命 |
| `trig/squad_has` | 编队含 `class:<x>` / `ids:[...]`（深海猎人）——乌尔比安天赋、浊心斯卡蒂 |

**cond / mod / rule**（可挂在任何 verb 上）

`cond/lamp >= / <`、`cond/in_light`（主控在 `_lamp_r` 内或目标 `e.lit`）、`cond/in_aura`、`cond/marked {name}`、`cond/counter {name} >=`、`cond/enemy_hp_pct <`、`cond/is_elite / is_boss`、`cond/on_ring`；`mod/per_stack {stat, per, cap}`（叠层）、`mod/scale_by_lost_hp`、`mod/elite_mult`、`mod/boss_mult`；`rule/<name> {cond, value}` 被动乘数（`kb_taken_mult`、`pull_mult`、`block_chance_mult`），与藏品 `rule` 同一种东西，由 data_operator 在对应原语里查询。

成长节点专用：`patch {path, set / add / append}` 改某条 block 的参数或追加子项（藏品 `temp_stat / rule` 的改法同源）；`replace_attack` 换普攻形状（精二质变）。

逃生口：`"custom": "<func>"` 调干员脚本里同名函数（若该干员有脚本；没有脚本时忽略并 `push_warning`），返回值按所在位置解释（verb → 执行，cond → bool，shape → 命中列表）。**原则：一个干员 ≤ 2 个 custom，且 custom 只能做「画面」和「原语组合表达不了的时序」，不许做数值。**

### 10.2 第三批五人的数据表达

写法：`<id>.json` 里新增 `"blocks"` 段（和 §8 的 `base / skills / talent / progression` 并存——`skills[i].desc` 仍是给玩家看的文字，`blocks` 是给 `data_operator.gd` 执行的）。下面只列 `blocks`，数字全部 `$` 引用 `base`（支持 `$a*$b`、`1-$x`、`$a/2` 这类单运算）。

**浊心斯卡蒂 `skalter`**（custom 0 个）

```json
"blocks": {
 "attack": {"shape": "aura", "center": "doctor", "r": "$aura", "every": "$cd",
            "do": [{"verb": "damage", "mult": 1.0, "kind": "法术", "src": "声浪", "tags": ["area", "basic"]}],
            "tick": [{"verb": "heal", "pct": "$heal_pct", "every": "$heal_cd", "cond": "in_aura:leader"}]},
 "skills": [
  {"verb": "mode", "dur": "$s1_dur", "aura_mult": "$s1_aura",
   "do": [{"verb": "heal", "pct": "$s1_heal", "every": 1.0}, {"verb": "lamp", "loss_mult": "$s1_lamp_loss"}]},
  {"permanent": true, "do": [
   {"verb": "buff", "stat": "aura_mult", "op": "add", "value": "$s2_aura", "who": "self"},
   {"verb": "buff", "stat": "op_aspd", "op": "add", "value": "$s2_aspd", "who": "in_aura"},
   {"verb": "buff", "stat": "op_atk", "op": "add", "value": "$s2_hunter_atk", "who": "ids:skadi,ulpianus,specter_unchained"}]},
  {"verb": "mode", "dur": "$s3_dur", "aura_mult": "$s3_aura", "attack_mult": "$s3_mult",
   "do": [{"verb": "buff", "stat": "op_atk", "op": "add", "value": "$s3_atk", "who": "squad"},
          {"verb": "heal", "pct": "$s3_heal", "every": 1.0},
          {"verb": "lamp", "per_sec": "-$s3_lamp_drain", "cond": "lamp >= $talent_dark"},
          {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": "$s3_dark_mult", "who": "self", "cond": "lamp < $talent_dark"}]}
 ],
 "talent": [
  {"trig": "lamp_band", "band": ">= $talent_bright", "do": [{"verb": "buff", "stat": "aura_mult", "op": "add", "value": "$bright_aura", "who": "self"}, {"verb": "buff", "stat": "heal_mult", "op": "mult", "value": "$bright_heal", "who": "self"}]},
  {"trig": "lamp_band", "band": "< $talent_dark", "do": [{"verb": "buff", "stat": "attack_mult", "op": "mult", "value": "$dark_mult", "who": "self"}, {"ctrl": "slow_soft", "value": "$dark_slow", "who": "in_aura"}]},
  {"trig": "squad_has", "ids": ["skadi", "ulpianus", "specter_unchained"], "do": [{"verb": "buff", "stat": "op_atk", "op": "add", "value": "$talent_hunter", "per": "count", "cap": "$talent_hunter_cap", "who": "in_aura"}]}
 ],
 "nodes": {
  "echo": {"trig": "on_hit", "count_every": "$echo_every", "do": [{"shape": "aura", "r": "$aura", "do": [{"verb": "damage", "mult": "$echo_mult", "src": "潮汐和声", "tags": ["follow_up", "area"]}]}]},
  "resonance": {"trig": "tick", "every": 1.0, "cond": "skill_active:0", "do": [{"shape": "aura", "r": "$aura", "do": [{"verb": "damage", "mult": "$resonance_mult", "src": "深海的回响", "tags": ["skill", "area", "dot"]}]}]},
  "e2": {"shape": "aura_edge_orbs", "n": "$note_n", "do": [{"ctrl": "knockback", "value": "$note_kb", "cd": "$note_cd", "src": "溟海之声"}]}
 }
}
```

`shape/aura_edge_orbs`（环边绕行体，铃兰狐火 / 塞雷娅晶体已各写一遍）是新原语，不是 custom。

**德克萨斯 `texas`**（custom 1 个：`s3_chain`——16 次连冲的时序）

```json
"blocks": {
 "attack": {"shape": "dash_line", "len": "$dash_len", "w": "$dash_w", "speed": "$dash_t", "hold": "$dash_hold", "aim": "nearest",
            "do": [{"verb": "damage", "mult": 1.0, "kind": "物理", "src": "疾行斩", "tags": ["pierce", "basic"]}],
            "on_pass": [{"verb": "sp", "who": "squad", "seconds": "$hit_sp", "exclude_self": true, "min_targets": 1}]},
 "skills": [
  {"shape": "ring", "r": "$s1_r", "do": [{"verb": "damage", "mult": "$s1_mult", "src": "剑雨", "tags": ["skill", "area", "stun"]}, {"ctrl": "stun", "dur": "$s1_stun", "elite_mult": 0.5, "boss": 0}, {"verb": "sp", "who": "squad", "pct": "$s1_sp", "exclude_self": true}]},
  {"permanent": true, "do": [{"verb": "buff", "stat": "dash_len_mult", "op": "add", "value": "$s2_len", "who": "self"}, {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": "$s2_mult", "who": "self"}, {"verb": "buff", "stat": "dash_cd_mult", "op": "mult", "value": "1-$s2_dash_cd", "who": "leader"}]},
  {"verb": "mode", "dur": "$s3_dur", "custom": "s3_chain",
   "then_end": [{"shape": "ring", "r": "$s1_r", "do": [{"verb": "damage", "mult": "$s3_end_mult", "src": "剑雨", "tags": ["skill", "area"]}]}]}
 ],
 "talent": [
  {"trig": "on_leader_dash", "cd": "$talent_cd", "do": [{"shape": "dash_line", "aim": "leader_dir", "do": [{"verb": "damage", "mult": 1.0, "src": "疾行斩"}]}, {"verb": "sp", "who": "squad", "seconds": "$talent_sp", "exclude_self": true}]},
  {"trig": "on_hit", "min_targets": "$talent_many", "do": [{"verb": "sp", "who": "squad", "seconds": "$talent_many_sp", "exclude_self": true}]}
 ],
 "nodes": {
  "wide": {"verb": "buff", "stat": "dash_w_mult", "op": "mult", "value": 1.3, "who": "self"},
  "sharp": {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": 1.15, "who": "self"},
  "back": {"trig": "on_hit", "delay": "$back_delay", "do": [{"shape": "dash_line", "aim": "reverse", "do": [{"verb": "damage", "mult": "$back_mult", "src": "回马剑", "tags": ["follow_up", "pierce"]}]}]},
  "rain2": {"trig": "on_skill_start", "skill": 0, "delay": "$rain2_delay", "do": [{"shape": "ring", "r": "$s1_r", "do": [{"verb": "damage", "mult": "$rain2_mult", "src": "剑雨"}]}]},
  "e2": {"trig": "on_hit", "do": [{"verb": "field", "shape": "line_trail", "life": "$trail_life", "tick": [{"verb": "damage", "mult": "$trail_mult", "src": "余像", "tags": ["basic", "dot"]}, {"ctrl": "slow", "dur": "$trail_slow"}]}]}
 }
}
```

`s3_chain` 之所以是 custom：「每 0.5 秒重新选最密处再冲、冲完接 stun 和回技力、8 秒内 16 次」用 `trig/tick` 也能拼（`{"trig": "tick", "every": "$s3_every", "cond": "skill_active:2", "do": [dash_line…]}`），落地时**先试拼法**，拼得出就把 custom 去掉。

**星熊 `hoshiguma`**（custom 0 个）

```json
"blocks": {
 "attack": {"shape": "fan", "reach": "$reach", "half_deg": "$arc_deg/2", "kb": "$kb",
            "do": [{"verb": "damage", "mult": 1.0, "kind": "物理", "src": "盾斧斩", "tags": ["area", "basic"]}]},
 "skills": [
  {"verb": "negate_next", "window": "$s1_window",
   "on_block": [{"shape": "ring", "r": "$s1_r", "do": [{"verb": "damage", "mult": "$s1_mult", "src": "举盾反击"}, {"ctrl": "knockback", "value": "$s1_kb"}]}],
   "on_miss": [{"shape": "fan", "reach": "$reach", "half_deg": "$arc_deg/2", "do": [{"verb": "damage", "mult": "$s1_miss_mult", "src": "盾斧斩"}]}]},
  {"verb": "mode", "dur": "$s2_dur",
   "do": [{"verb": "buff", "stat": "op_atk", "op": "add", "value": "$s2_atk", "who": "self"}, {"verb": "buff", "stat": "dmg_taken", "op": "mult", "value": "1-$s2_dr", "who": "leader"}, {"rule": "block_chance_mult", "value": "$s2_block_x"}],
   "on_hit": [{"verb": "field", "shape": "ring", "r": "$sand_r", "dur": "$sand_dur", "tick": [{"verb": "damage", "mult": "$sand_mult", "src": "热砂", "tags": ["skill", "area", "dot"]}]}]},
  {"verb": "mode", "dur": "$s3_dur", "attack": {"shape": "line", "len": "$s3_len", "w": "$s3_w", "kb_mult": "$s3_kb", "src": "魔王", "tags": ["skill", "pierce", "area"]},
   "do": [{"verb": "buff", "stat": "op_atk", "op": "add", "value": "$s3_atk", "who": "self"}, {"verb": "buff", "stat": "dmg_taken", "op": "mult", "value": "1-$s3_dr", "who": "leader"}],
   "on_damage_taken": [{"shape": "ring", "r": "$s3_quake_r", "do": [{"ctrl": "knockback", "value": "$s3_quake_kb", "src": "震退"}]}]}
 ],
 "talent": [
  {"trig": "on_damage_taken", "chance": "$block_chance", "boss_chance": "$block_chance_boss", "chance_add": [{"cond": "beacon_charging", "value": "$beacon_bonus"}],
   "do": [{"verb": "negate", "keep_lamp": true}, {"shape": "ring", "r": "$block_kb_r", "do": [{"ctrl": "knockback", "value": "$block_kb"}]}]}
 ],
 "nodes": {
  "reach": {"verb": "buff", "stat": "reach_mult", "op": "mult", "value": 1.15, "who": "self"},
  "heavy": {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": 1.15, "who": "self"},
  "wall": {"patch": "talent[0].do[1].do", "append": [{"ctrl": "stun", "dur": "$wall_stun"}]},
  "ember": {"patch": "base", "set": {"sand_dur": "$ember_dur", "sand_mult": "$sand_mult*$ember_mult"}},
  "e2": {"trig": "on_attack_start", "count_every": "$oni_every", "replace_attack": {"shape": "line", "len": "$s3_len", "w": "$s3_w", "do": [{"verb": "damage", "mult": "$oni_mult", "src": "鬼面", "tags": ["basic", "pierce"]}]}}
 }
}
```

**能天使 `exusiai`**（custom 0 个）

```json
"blocks": {
 "attack": {"shape": "bolt", "range": "$range", "speed": "$bullet_speed", "shots": "$shots", "spread_deg": "$spread_deg", "target": "nearest", "elite_prio": "$elite_prio",
            "do": [{"verb": "damage", "mult": 1.0, "kind": "物理", "src": "速射", "tags": ["projectile", "basic"]}]},
 "skills": [
  {"verb": "ammo", "n": "$s1_ammo", "attack_patch": {"mult": "$s1_mult", "pierce": "$s1_pierce", "src": "强力击", "tags": ["skill", "projectile", "pierce"]}},
  {"verb": "mode", "dur": "$s2_dur", "attack_patch": {"cd": "$s2_cd", "mult": "$s2_mult"}, "then_end": [{"verb": "buff", "stat": "attack_lock", "op": "add", "value": "$s2_overheat", "who": "self"}]},
  {"verb": "mode", "dur": "$s3_dur", "attack_patch": {"burst": "$s3_burst", "burst_gap": "$s3_gap", "mult": "$s3_mult", "range_mult": "1+$s3_range", "target": "elite", "src": "处决模式", "last_shot": [{"ctrl": "pause", "dur": "$s3_pause", "elite_mult": 0, "boss": 0}]}}
 ],
 "talent": [
  {"trig": "on_kill", "do": [{"verb": "counter", "name": "mag", "add": 1, "cap": "$mag_cap"}]},
  {"trig": "on_kill", "cond": "in_light", "do": [{"verb": "counter", "name": "mag", "add": "$mag_lit_bonus", "cap": "$mag_cap"}]},
  {"trig": "on_attack_start", "cond": "counter:mag >= $mag_cap", "replace_attack": {"shape": "bolt", "shots": "$mag_shots", "spread_deg": "$mag_spread_deg", "pierce": "$mag_pierce", "do": [{"verb": "damage", "mult": "$mag_mult", "src": "弹夹倾泻", "tags": ["projectile", "pierce", "area"]}]}, "then": [{"verb": "counter", "name": "mag", "set": 0}]}
 ],
 "nodes": {
  "range": {"verb": "buff", "stat": "range_mult", "op": "mult", "value": 1.15, "who": "self"},
  "power": {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": 1.15, "who": "self"},
  "twin": {"patch": "base", "add": {"shots": "$twin_shots"}},
  "ricochet": {"patch": "attack", "set": {"bounce": 1, "bounce_chance": "$ricochet_chance", "bounce_r": "$ricochet_r", "bounce_mult": "$ricochet_mult", "bounce_src": "跳弹"}},
  "e2": {"patch": "base", "add": {"shots": "$e2_shots"}, "set": {"mag_cap": "$e2_mag_cap"}}
 }
}
```

**安洁莉娜 `angelina`**（custom 0 个）

```json
"blocks": {
 "attack": {"shape": "land", "range": "$range", "speed": "$bullet_speed", "aoe": "$aoe", "target": "densest",
            "do": [{"verb": "damage", "mult": 1.0, "kind": "法术", "src": "重力弹", "tags": ["projectile", "area", "basic", "control"]},
                   {"ctrl": "pull", "r": "$pull_r", "dist": "$pull", "elite_mult": "$pull_elite", "boss": 0, "scale": "enemy_kb", "mark": {"name": "grav_t", "dur": "$grav_dur"}}]},
 "skills": [
  {"verb": "ammo", "n": "$s1_n", "attack_patch": {"pull_mult": "$s1_pull", "aoe_mult": "$s1_r", "extra": [{"ctrl": "pause", "dur": "$s1_pause", "elite_mult": 0.5, "boss": 0}], "src": "重力调节"}},
  {"permanent": true, "do": [{"verb": "field", "shape": "aura", "center": "leader", "r": "$s2_r", "dur": 0, "every": "$s2_every", "tick": [{"ctrl": "ring_shape", "ring": "$s2_ring", "force": "$s2_force", "boss": 0}]}, {"verb": "buff", "stat": "move_speed", "op": "mult", "value": "1+$s2_speed", "who": "leader"}]},
  {"verb": "field", "shape": "aura", "center": "leader", "r": "$s3_r", "dur": "$s3_dur", "every": 0.1,
   "tick": [{"ctrl": "levitate", "dur": "$s3_stun", "elite_cycle": ["$s3_elite_up", "$s3_elite_down"], "boss": {"ctrl": "slow_soft", "value": "$s3_boss_slow"}}, {"ctrl": "pull", "to": "center", "dist": "$s3_gather", "per_sec": true}],
   "do": [{"verb": "buff", "stat": "op_aspd", "op": "add", "value": "$s3_aspd", "who": "squad"}, {"verb": "heal", "pct": "$s3_heal", "every": 1.0}, {"verb": "buff", "stat": "move_speed", "op": "mult", "value": "1+$s3_speed", "who": "leader"}, {"verb": "pickup_magnet", "mult": "$s3_pickup"}]}
 ],
 "talent": [
  {"trig": "on_hit", "do": [{"ctrl": "mark", "name": "grav_t", "dur": "$grav_dur"}]},
  {"rule": "kb_taken_mult", "cond": "marked:grav_t", "value": "1+$grav_kb"},
  {"rule": "pull_mult", "cond": "in_light:leader", "value": "1+$talent_lit"}
 ],
 "nodes": {
  "wide": {"verb": "buff", "stat": "aoe_mult", "op": "mult", "value": 1.15, "who": "self"},
  "dense": {"verb": "buff", "stat": "attack_mult", "op": "mult", "value": 1.15, "who": "self"},
  "pull2": {"trig": "on_hit", "delay": "$pull2_delay", "do": [{"shape": "ring", "at": "last_land", "r": "$pull_r", "do": [{"verb": "damage", "mult": "$pull2_mult", "src": "双重引力", "tags": ["follow_up", "area"]}, {"ctrl": "pull", "dist": "$pull"}]}]},
  "lock": {"patch": "skills[1].do[0].tick", "append": [{"cond": "on_ring", "verb": "damage", "mult": "$lock_mult", "every": "$lock_tick", "src": "潮汐锁", "tags": ["dot", "area"]}]},
  "e2": {"patch": "attack.do", "append": [{"ctrl": "levitate", "r": "$zero_r", "dur": "$zero_air", "src": "失重"}]}
 }
}
```

**本批 custom 合计 1 个（德克萨斯 s3_chain，且可能拼掉）；新原语 7 条**：`ctrl/slow_soft`、`shape/aura_edge_orbs`、`verb/counter`、`ctrl/ring_shape`、`verb/negate_next` / `verb/negate`、`rule/*`、节点 `patch`。其余全部是现有代码的参数化。

### 10.3 现有 13 人将来能迁多少（本次不迁）

| 干员 | 行数 | 能落进原语的部分 | 还得留 custom 的部分 | 可迁比例 |
|---|---|---|---|---|
| 推进之王 | 530 | 扇形锤击、命中回技力、S1 / S2 环 + 眩晕 + 技力、S3 形态 | 跃空锤的空中翻转画面、冲锋号令的指挥动画 | ~85% |
| 斯卡蒂 | 378 | 扇形横扫、三连击（`on_hit count_every` + delay）、S1 / S2 扇形、S3 形态 + 脉冲环 | 波浪（`waves` 推进体）→ 可做成 `shape/wave` 新原语 | ~80% |
| 塞雷娅 | 556 | 拳击扇形、阻挡圈（`ctrl/ring_shape` 的「全推」特例）、S1 / S2 治疗、S3 field、天赋减伤 | 绕行晶体 / 注射器弹体的画面 | ~75% |
| 维什戴尔 | 682 | 落点炮击 + 余震（`on_hit delay ring`）、S1 ammo、S2 单发、S3 ammo + mode、殉爆 `on_kill` | 残影人形 / 魂灵之影（会跑的召唤体） | ~70% |
| 艾雅法拉 | 393 | 落点弹 + 点燃 mark/dot、S1 ammo、S2 单发易伤、S3 field 多次喷发 | 熔岩池画面 | ~85% |
| 铃兰 | 494 | 光域 slow + 易伤 mark、狐火 bolt、S1 ammo、S2 永久、S3 field | 三团狐火汇聚（merge）的时序、围炉狐火 | ~75% |
| 水月 | 600 | 伞击扇形、唤醒 ammo、S2 / S3 mode | 触手追击（独立实体 + 自己的目标选择）、镜像分身 | ~55% |
| 凯尔希 | 656 | 治疗 tick、S1 cleanse、S2 永久、S3 mode + 结束爆发 | Mon3tr 是带 AI 的召唤物（`shape/summon` 只覆盖「站着的」） | ~50% |
| 乌尔比安 | 861 | 环砸、叠层 `counter`、深海猎人共享、S2 永久、S3 落点 + move | 掷锚飞行体 + 锁链 + 钩拽时序、弹射开路 | ~55% |
| 艾丽妮 | 479 | 两段直线、S1 浮空 + 补刺（delay）、S2 锥形 + 浮空、S3 环 + 连射 bolt、天赋 `cond/marked` | 手炮 12 发的目标优先级（可做 `target: airborne`） | ~85% |
| 归溟幽灵鲨 | 501 | 环斩、S1 `mod/scale_by_lost_hp`、S3 mode、天赋灯火档 | S2 不死（`prevent_death` 挂点）+ 替身召唤物 + 倒下演出 | ~65% |
| Logos | 660 | 单体 bolt + 安魂 mark、S1 锁定 dot、S2 永久 + 处决 `cond/enemy_hp_pct`、S3 mode + `ctrl/bullet_slow`、天赋概率追击 | 咒文字形画面、溢出伤害转移 | ~75% |
| 流明 | 559 | 治疗 / 驱散 tick、光弹 bolt + lit mark、S1、S2 永久、S3 field + 结束爆发 | 灯塔 `sanctuary()` 挂点（可做 `field` 的 `sanctuary: true` 参数） | ~80% |

平均约 **72%** 能落进原语；剩下的集中在三类：**带 AI 的召唤物**（Mon3tr、魂灵之影、触手）、**飞行体 + 锁链**（乌尔比安）、**专属画面**。迁移顺序建议：艾丽妮 / 艾雅法拉 / 推进之王（85%，验证器最容易）→ 其余 → 水月 / 凯尔希最后（可能永远保留脚本，只把数值段数据化）。

### 10.4 实施计划

1. **`scripts/characters/data_operator.gd`**（继承 character.gd，≈ 600 行）：
   - `_init` 读 `def.blocks`，把 `$key` 解析成 `base()` 调用（支持 `$a*$b`、`1-$x`、`$a/2` 这类单运算，不做表达式引擎）；
   - `update(dt)`：按 `attack` 的 shape 起手（`start_attack` → `_release` 里执行 `do`）、跑 `mode / field / ammo` 的计时、`trig/tick` 与 `trig/lamp_band` 轮询、`counter` 与 `mark` 衰减；
   - `_release_skill()`：按 `cur_skill` 执行 `skills[i]`；永久型走 `perm[i]`；
   - 覆写 `on_kill / on_elite / on_custom_node / dmg_taken_mult / sync_stats / draw_auras / extra_bodies`，各自把事件分发到 `trig/*`；
   - `custom` 逃生口：`has_method(name)` 则调，否则 `push_warning`；
   - 所有随机走 `g.rng`，所有伤害先 `log_hit(src, tags)`，所有数值 `stats.add(..., "op:" + id)`——与手写干员完全同一套 op_api。
2. **原语实现放哪**：shape / ctrl 的通用部分放 `characters/op_blocks.gd`（RefCounted，data_operator 与手写干员都能调），艾丽妮的 `lift()`、推进之王的 `_squad_sp_seconds()`、艾丽妮的线段判定、流明的 `bolts` 推进在这一步搬进去（手写干员改为调共享版，行为不变，`check.py --ab` 同 seed 逐局相同）。
3. **校验**：`Character.validate_operator()` 加 `blocks` 校验——原语名在表内、`$key` 都在 `base` 里、每人 custom ≤ 2、`skills` 三条与 `blocks.skills` 三条一一对应；`tools/check.py` 的契约检查接上。
4. **等价测试**（用户要求的核心验收）：
   - 给一名现有干员写一份 `blocks`（首选艾丽妮：85% 可迁、无召唤物），`irene.json` 加 `"script_data": true` 时用 `data_operator.gd` 加载；
   - `python tools/check.py --ab <提交> --op irene`：同 seed、同参数，手写版与数据版的 **TRACE 逐帧相同**（docs/36 §3 的复现机制），伤害构成（`out` 按 src）完全一致；
   - 容许的差异只有画面（粒子种类），且画面不消耗 `g.rng`（docs/36 已约定）；
   - 这一步通过后，艾丽妮保留脚本只做画面，其余逻辑由数据驱动——这就是迁移模板。
5. **第三批落地顺序**：先做 data_operator + 等价测试（≈ 12 小时），再按用户优先级写五人的 `blocks`（每人 2–4 小时，比手写 6–8 小时省一半以上），第二人起只在原语缺口上加代码。§6 里 game.gd 的 2 处改动不变。
6. **面向创意工坊的边界**（本次只记，不做）：玩家自制干员 = 一份 JSON（`base + blocks + sprites + lore`）+ 帧条 PNG，不含 .gd；`custom` 对外部干员一律忽略；原语白名单与参数范围在 `validate_operator()` 里夹紧（`atk ≤ 80`、`shots ≤ 6` 之类），防止数据把局打崩；数据干员不进排行 / 遥测口径（docs/40），另立一个 `modded` 标记。

与 docs/60 的衔接：docs/60 按原作词汇（职业分支、技力类型、效果动词、控制类型、天赋触发、集成战略钩子）列的原语建议表出来后，把 §10.1 的名字对到它的表上，取并集；冲突时以 docs/60 的分类为准、以本节的参数为准（本节的参数都对应现成代码）。
