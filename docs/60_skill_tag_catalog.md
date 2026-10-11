# 60 · 原作技能 / 天赋 / 特性词汇表 → 本作干员积木（2026-10-11）

> 用户 10-11：「技能模块化的方面是否可以调研一下原本明日方舟里边的各种设计。看看我们有哪些 tag 可以拿来用，确保我们内容的丰富性」。
>
> 本文是**调研 + 词汇表**：把原作职业分支特性、技能机制、天赋触发、集成战略钩子整理成「标签」，每个标签给出：一句话定义、原作例子、
> 本作覆盖（13 名干员 / 藏品原语）、在「博士居中、敌潮围攻、只有主控受击」的幸存者玩法里怎么翻译、落成哪块积木（带参数）。
> 它是 docs/59「积木化方案」的输入，也给以后的干员和玩家自制干员当菜单用。**不改任何代码和数值**，也不改 docs/59。
>
> 来源：原作知识 + arknights.wiki.gg 的 Class 分支特性页、Skadi the Corrupting Heart / Angelina / Hoshiguma / Exusiai / Texas 干员页（2026-10-11 读取，只读文字，转述）；
> 本仓库 docs/49b（解包数据统计、术语表转述）、docs/49a（集成战略）、docs/26（13 人技能表）、docs/31、docs/57（藏品原语 P1–P29）、
> `relic_fx.gd`、`core/events.gd`、`characters/op_api.gd`。原作数值只作口径参考，没核实的标（待核）。

## 0. 怎么读

### 0.1 积木的六个类

| 类 | 代号 | 是什么 | 例 |
|---|---|---|---|
| 攻击形状 | `shape.*` | 一次出手「打到谁」的几何与弹道 | 扇形、周身圈、直线穿透、落点圆、弹射链 |
| 选目标 | `target.*` | 形状对准哪里 | 最近、精英优先、最密处、最低血、受控者优先 |
| 技能动词 | `verb.*` | 技能 / 天赋「做什么」 | 限时增益、强化下一击、换攻击模式、召唤、位移、回复、给护盾 |
| 修饰 | `mod.*` | 挂在一次命中或一段时间上的改写 | 法伤 / 真伤、无视防御、溅射、处决、吸血、多段 |
| 触发 | `trig.*` | 天赋 / 被动「什么时候」生效 | 每 N 次攻击、击杀精英、主控受击、生命低于 X、编队有某阵营 |
| 状态 | `st.*` | 挂在敌人（或主控）身上的有时长效果 | 晕眩、减速、束缚、浮空、易伤、灼烧 |

另有两类「外壳」字段描述技能本身：`sp.*`（技力怎么来）和 `dur.*`（持续怎么算），见 §2.1–2.3。

### 0.2 「本作覆盖」一栏的写法

- 干员简称：水月、推王（推进之王）、斯卡蒂、塞雷娅、维什（维什戴尔）、艾雅（艾雅法拉）、凯尔希、铃兰、乌尔（乌尔比安）、艾丽妮、鲨（归溟幽灵鲨）、Logos、流明。
- 藏品原语：P1–P29 见 docs/57 §1；更早的藏品写法写名字（`status bind/stun dot`、地雷、追击 `followup`、护盾层、闪避等）。
- **「各写各的」**= 干员脚本里手写实现，没有可复用的积木；**「无」**= 全作都没有。

### 0.3 现有可复用的地基（积木要接到这里）

- 命中描述符 `g.hit = {src, emitter, origin, range, kind(物理/法术/真实), tags}`（`combat.gd`），来自干员 JSON `hit_sources`；藏品按 `class:` / `range:` / 追击标签筛选。**建议本文的标签直接当 `hit_sources.tags` 的词表**，藏品就能写 `scope: tag:summon` 之类（§4.1）。
- 事件总线 `core/events.gd`：AttackStarted / Hit / DamageDealt / DamageTaken / EnemyKilled / SkillStarted / SkillEnded / StatusApplied / Dodge / LightChanged / BossKilled / LevelUp / Healed / ShieldBroken / Tick / Recruited。§3 的触发词大多直接挂在这些事件上。
- 干员接口 `op_api.gd`：`nearest_enemies` / `query_ids` / `arc_targets` / `densest_point` / `deal_damage` / `heal_leader` / `stats.add(...,"op:<id>")` 等；询问式挂点 `dmg_taken_mult()` / `sanctuary()` / `prevent_death()` / `light_radius_mult()` / `extra_bodies()`。
- 敌人字段：`stun`、`slow`、`air`（浮空高度）、`lit`（照亮）、`requiem`（安魂）、`kb`（击退）、`elite` / `boss`。

---

## 1. 职业 × 分支特性（8 职业 · 72 分支）

> 分支名按 wiki.gg「Class」页 2026-10 的列表（先锋 6、近卫 14、重装 8、狙击 10、术师 9、医疗 7、辅助 8、特种 10 = 72 行，含两个较新分支 先锋·策士 / 狙击·裂空；docs/49b 的解包计数为 71，差异待核）。
> 「本作」列：我们的干员属于该分支的标 ★；「翻译 → 标签」是该分支特性在幸存者里最自然的落法。

### 1.1 先锋（本作定位：节奏 / 技力电池）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 尖兵 | 阻挡 2，技能稳定回费 | ★ 推王；第三批德克萨斯 | 技能给全队技力 → `verb.sp_team` |
| 冲锋手 | 击杀 +1 费，撤退全额返还 | 无（藏品 P25 积攒之手已有） | 击杀回全队技力 → `trig.on_kill` + `verb.sp_team` |
| 执旗手 | 技能期间大量回费，但不攻击不阻挡 | 无 | 「停手换资源」：技能期间本人不普攻，全队技力 / 灯火高速回复 → `verb.mode{no_attack}` + `verb.sp_team{per_s}` |
| 战术家 | 远程；在射程内放援军，援军挡住的敌人受伤 ×1.5 | 无 | 召唤一个会吸引敌人的援军，援军附近的敌人受伤加成 → `verb.summon{decoy}` + `st.fragile{near_summon}` |
| 情报官 | 再部署快、射程 2 格、技能期间每次攻击回费 | 无 | 技能期间攻击回全队技力 → `sp.on_attack` / `trig.on_hit → verb.sp_team` |
| 策士 | 技能稳定回费；天赋与技能支援**未上场**的干员 | 无 | 本作所有干员都在场：改为「支援编队里技能未就绪的干员」→ `verb.sp_team{target: lowest_sp}` |

### 1.2 近卫（本作定位：近战输出）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 无畏者 | 无特殊特性（单体高攻高血） | ★ 斯卡蒂 | 前方扇形重击 → `shape.cone` |
| 强攻手 | 同时攻击阻挡数个敌人 | 无（接近斯卡蒂） | 扇形内取前 N 个 → `shape.cone{max_n}` |
| 领主 | 不阻挡时可远程，远程只有 0.8 倍 | 无 | 近处挥砍、远处投射物 ×0.8 的双形态普攻 → `shape.dual{near, far, far_mult}` |
| 术战者 | 普攻为法伤 | 无 | 近战法伤 → `mod.dmg_type{arts}` |
| 教官 | 射程 2 格，对未被阻挡的敌人 ×1.2，技能支援队友 | 无 | 对「不在阻挡圈里」的敌人（即远处的）增伤 + 给队友增益 → `mod.cond_dmg{far}` + `verb.buff_ally` |
| 斗士 | 攻击间隔极短 | 无 | 高频小伤，天然吃「每次攻击」触发 → `shape.cone{cd 极短}` |
| 剑豪 | 一次普攻两段伤害 | ★ 艾丽妮 | `mod.multi_hit{n 2}` |
| 武者 | 不受治疗，攻击回血 | 无 | 博士只能被此人吸血回复（其他治疗打折）→ `mod.lifesteal` + 代价 `cost.heal_block` |
| 解放者 | 平时不攻击、攻击力随时间累积，开技能才打 | 无 | 「蓄力型」：普攻关掉，每秒叠攻击，技能一次释放 → `verb.mode{no_attack}` + `trig.tick → stack` |
| 收割者 | 横扫前方 3 格内全部敌人，每命中一个回少量生命（上限阻挡数） | 无 | 大扇形横扫，命中数转回复（有上限）→ `shape.cone` + `mod.lifesteal{per_hit, cap}` |
| 重剑手 | 群攻、极高攻血、无防、攻击间隔长 | 无（乌尔原作曾归此类） | 慢速大范围重砸 → `shape.circle_self{cd 长}` |
| 撼地者 | 主目标周围溅射 50% | ★ 乌尔 | `mod.splash{r, pct 0.5}` |
| 本源近卫 | 对处于元素爆发中的敌人造成元素伤害 | 无 | 依赖 `st.element` 爆发（暂缓，§8） |
| 佣兵 | 花费用强化自己 | 无 | 花「源石锭 / 技力 / 灯火」换强化 → `cost.*` + `verb.buff_self` |

### 1.3 重装（本作定位：护主控）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 铁卫 | 阻挡 3 | 第三批星熊 | 阻挡圈：顶住 N 个敌人 → `verb.block_ring{n, r}` |
| 守护者 | 技能可治疗 | ★ 塞雷娅 | `verb.heal` |
| 不屈者 | 不受治疗，靠自身技能 / 天赋回血 | 无 | 同武者：自给自足的护主 → `cost.heal_block` + `mod.lifesteal` |
| 驭法铁卫 | 技能期间普攻转法伤 | 无 | `verb.mode{dmg_type arts}` |
| 决战者 | 只阻挡 1，只在阻挡时回技力 | 无 | **受击 / 贴身回技力**：主控身边有敌人时才充能 → `sp.on_contact` |
| 要塞 | 不阻挡时远程群攻（有最小射程） | 无 | 「身边空才开炮」：主控周围 r 内没敌人时切成远程溅射 → `trig.near_count{=0}` + `shape.point_aoe{min_r}` |
| 哨戒铁卫 | 可远程，打前方 2 格、可对空 | 无 | 近战重装带一个前向远程 → `shape.line{short}` |
| 本源铁卫 | 减少受到的元素损伤，技能造成元素损伤 | 无 | 主控元素抗性（侵蚀 / 神经）→ `stat nerve_taken / corrode_taken`（藏品 131 / 132 已有） |

### 1.4 狙击（本作定位：远程单体 / 打精英 Boss）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 速射手 | 优先攻击空中 | 第三批能天使 | 优先打 `hover` / 远程敌人 → `target.priority{hover, ranged}` |
| 神射手 | 射程很远，优先最低防御 | 无 | 超远单体，优先护甲最低 / 生命最低 → `target.priority{low_def}` |
| 重射手 | 射程短、攻击高 | 无 | 近距离高伤投射物 → `shape.projectile{range 短}` |
| 散射手 | 打射程内全部，正前排 ×1.5 | 无 | 前方锥形霰弹，近处加成 → `shape.cone{range_falloff 反向}` |
| 炮手 | 群体物伤 | ★ 维什（投掷手近亲） | `shape.point_aoe` |
| 攻城手 | 有前方最小射程，优先最重敌人 | 无 | 优先精英 / 体型最大 → `target.priority{elite, heavy}` |
| 投掷手 | 两段落地伤害，第二段半伤，只打地面 | ★ 维什（余震） | `shape.point_aoe` + `mod.aftershock{pct 0.5}` |
| 猎手 | 只用弹药攻击（×1.2），没有敌人时回弹 | 无（维什 S3 是次数型技能） | 普攻弹药：打完要停手装填 → `dur.ammo` 套到普攻 |
| 回环射手 | 回旋镖，大射程，要等飞回 | 无 | 去回两次命中的穿透弹 → `shape.boomerang` |
| 裂空 | 部署后起飞只打空中，技能落地群伤 | 无 | 本作无对空分层，改为「升空期间无法被近身、落地砸地」→ `verb.dash{leap}` + `shape.circle_self` |

### 1.5 术师（本作定位：范围法伤）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 中坚 | 无特殊特性（单体法伤） | ★ 艾雅、Logos | `shape.projectile` + `mod.dmg_type{arts}` |
| 扩散 | 范围法伤 | 无（艾雅普攻实为此形态） | `shape.point_aoe` |
| 轰击 | 直线贯穿全部 | 无 | `shape.line{pierce}` |
| 链术师 | 在目标间跳跃（每跳 -15%）并造成停顿 | **无** | `shape.chain{n 3, falloff 0.15}` + `st.slow{heavy, short}` |
| 驭械 | 浮游单元独立攻击，重复命中同一目标伤害递增 | 无（Logos S1 有递增） | 伴飞召唤物 → `verb.summon{orbiter}` + `mod.ramp{same_target}` |
| 阵法 | 只在技能期间攻击，平时高防高抗 | 无 | 平时给主控减伤、开技能才输出 → `verb.mode{no_attack}` + `aura.dr` |
| 秘术师 | 没敌人时最多存 3 次攻击，之后一起放 | 无 | 「存弹齐射」：攻击冷却在空闲时累积成弹仓 → `sp.store{max 3}` |
| 本源术师 | 对元素爆发中的敌人造成元素伤害 | 无 | 依赖 `st.element`（暂缓） |
| 塑灵 | 击杀获得召唤物，能打被召唤物挡住的敌人 | 无 | **击杀生召唤物** → `trig.on_kill → verb.summon` |

### 1.6 医疗（本作定位：护主控；只有主控掉血，群体治疗要重译）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 医师 | 单体治疗、射程远 | ★ 凯尔希 | `verb.heal{periodic}` |
| 群愈师 | 同时治 3 个 | 无 | 只有一个受伤对象 → 治疗溢出转护盾 / 屏障 → `mod.overheal_to_shield` |
| 疗养师 | 范围大，对次要目标 80% | ★ 流明（原作行医，见下） | 光域治疗，离中心越近越多 → `verb.field{heal, falloff}` |
| 行医 | 治元素损伤（满血也能治） | ★ 流明 | `verb.cleanse{nerve, corrode}` |
| 咒愈师 | 攻击敌人，再把一半伤害转治疗 | **无** | `mod.lifesteal{pct}`（打得越多回得越多） |
| 链愈师 | 治疗在目标间跳跃，每跳 -25% | 无 | 无多个友方：改为「治疗跳到下一个时刻」= 分次 HoT，或跳到召唤物 / 替身 → 低优先 |
| 守望者 | 可起飞治空中单位 | 无 | 不适用 |

### 1.7 辅助（本作定位：控制与增益）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 凝滞师 | 法伤 + 短暂减速 | ★ 铃兰；第三批安洁莉娜 | `mod.on_hit_status{slow}` |
| 召唤师 | 可用召唤物 | 无（凯尔希 Mon3tr 是医疗特例） | `verb.summon` |
| 削弱者 | 削弱敌人攻击 / 防御 | 无（易伤有、虚弱无） | `st.fragile` / `st.weaken`（敌人伤害 ×） |
| 吟游者 | 不攻击，持续给范围内全部友军回血；可鼓舞别人，自己不吃鼓舞 | 第三批浊心斯卡蒂 | `aura.heal` + `aura.inspire`，本人 `verb.mode{no_attack}` |
| 护佑者 | 提高友军防御；技能期间改为治疗（0.75 倍攻击） | 无 | 平时输出、开技能改奶 → `verb.mode{attack→heal}` + `aura.dr` |
| 工匠 | 近战物伤，可放支援装置 | 无（藏品 P21 支援装置） | `verb.device` |
| 巫役 | 造成元素损伤 | 无 | `st.element`（暂缓）；短期可用 `st.dot` 代替 |
| 游击手 | 以触发型效果增益友军或伤害敌人 | 无 | 被动触发器堆 → `trig.*` 组合 |

### 1.8 特种（本作定位：机制 / 位移 / 爆发）

| 分支 | 特性（转述） | 本作 | 翻译 → 标签 |
|---|---|---|---|
| 推击手 | 技能推开敌人，同时攻击阻挡数个 | 无（斯卡蒂 S2 击退） | `verb.displace{push, force}` |
| 钩索师 | 技能把敌人拉近，前方射程长 | 无（乌尔 S1 拖拽为本人飞过去） | `verb.displace{pull, force}` |
| 处决者 | 再部署极快 | 无 | 再部署 → 「闪现落地斩」短冷却 → `verb.dash{blink}` + `trig.on_deploy` |
| 伏击客 | 打范围内全部，50% 物理 / 法术闪避，不易被选中 | ★ 水月 | 给主控闪避 → `stat dodge`；「不易被选中」→ 隐匿重译（§5） |
| 怪杰 | 攻击误伤友军却给友军增益；自身持续掉血 | 无 | 以主控生命为代价的增益 → `cost.hp_drain` + `aura.inspire` |
| 行商 | 在场持续扣费，费用用完自动撤退 | 无 | 持续消耗源石锭 / 技力换强力在场时间 → `cost.upkeep` |
| 陷阱师 | 在没有敌人的格子放陷阱 | 无（藏品地雷） | `verb.device{trap}` |
| 傀儡师 | 生命耗尽变成替身，替身倒下要重新部署 | ★ 鲨 | `verb.summon{substitute}` + `trig.on_skill_end` |
| 炼金师 | 投掷炼金单元给增益或减益 | 无 | 投出的地面物：踩上给主控增益 / 敌人减益 → `verb.device{pickup}` |
| 巡空者 | 技能起飞，可阻挡空中 | 无 | 不适用（可并入 `verb.dash{leap}`） |

### 1.9 分支层面的结论

- 72 个分支里本作已覆盖 12 个（尖兵、无畏者、剑豪、撼地者、守护者、投掷手 / 炮手、中坚 ×2、医师、行医 / 疗养、凝滞师、伏击客、傀儡师）。
- **翻译成本最低、玩法差异最大的空白分支**：链术师（弹射）、咒愈师 / 收割者（吸血）、召唤师 / 塑灵（召唤物）、吟游者 / 怪杰（光环）、决战者（贴身回技力）、秘术师（存弹齐射）、猎手（普攻弹药）、执旗手 / 解放者（停手换资源）、钩索师 / 推击手（推拉）、炼金师 / 陷阱师（场上道具）。

---

## 2. 技能机制词汇

### 2.1 技力（SP）来源 `sp.*`

原作 skill_table 计数：自动回复 1028、攻击回复 120、受击回复 33，其余被动（docs/49b §1.4）。本作全部是「随时间」+ 少数加速。

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 积木与参数 |
|---|---|---|---|---|---|
| `sp.auto` | 随时间回复 | 绝大多数技能 | 全员（`charge_skills(dt)`） | 现状 | `sp: {type: auto, need}` |
| `sp.on_attack` | 每次普攻 +1 | 能天使 S1 冲锋模式、安洁莉娜 S1 | **无** | 干员**自己出手**时充能；高攻速干员的短循环技能 | `sp: {type: attack, per_hit: 1}`，`need` 改成「次数」；水月「唤醒」普攻次数已接近 |
| `sp.on_hurt` | 受到攻击 +1 | 星熊 / 重装常见 | **无**（藏品「铁卫-无锋」受击回技力有） | **主控每挨一下，给该干员充能**——把挨打变资源，重装 / 护主类首选 | `sp: {type: hurt, per_hit: 1, cd: 0.2}` |
| `sp.on_contact` | 只在阻挡时回技力 | 决战者 | 无 | 主控 r 内有敌人时才充能 | `sp: {type: contact, r}` |
| `sp.store` | 空闲时存攻击 / 蓄力到 2 倍 | 秘术师；「蓄力」技能 | 无 | 满后继续充到 2 倍再放有额外效果；或攻击冷却在空闲时攒成弹仓 | `sp: {overcharge: 2.0, bonus}` |
| `sp.team_feed` | 自己的行为给别人充能 | 尖兵 / 冲锋手（费用） | 推王（命中回全队技力）、藏品 P13 / P24 / P25 | 已有 | `verb.sp_team{pct, target: all/lowest/class}` |
| `sp.drain` | 被扣技力 / 不能开技能 | 凋亡爆发（敌→我） | 无 | 敌人技能：充能暂停 / 倒扣（docs/49b §4.4 第 1 条） | 敌方积木，不在干员侧 |

### 2.2 释放方式 `cast.*`

| 标签 | 定义 | 原作例 | 本作覆盖 | 翻译 | 参数 |
|---|---|---|---|---|---|
| `cast.auto` | 充满自动放 | 维什 S3 等 | 全员默认 | 现状 | `mode: auto` |
| `cast.manual` | 玩家按键放 | 原作 741 条 | 乌尔 S3（只在主控时，至多 1 个） | 现状，带 `aim: true / "point"` | `mode: manual, aim` |
| `cast.passive` | 被动，没有开关 | 星熊 S2 荆棘 | 天赋层面有；技能层面靠「永久型」 | 被动技能 = 解锁即生效的永久型 | `permanent: true, sp: 0` |
| `cast.channel` | 吟唱：停手一段时间才开，被打断中止 | 少数敌人 / 干员 | 无 | 主控**站着不动** N 秒才放（移动 = 打断），给「站桩换爆发」的抉择 | `cast: channel{t, cancel_on_move}` |
| `cast.overload` | 过载：技能分两段，持续到一定时间后进入强化段 | 部分 6★ | 无 | 技能持续超过 t 秒后进入第二段（更强 / 有代价） | `phases: [{t, mods}, …]` |

### 2.3 持续类型 `dur.*`

| 标签 | 定义 | 原作例 | 本作覆盖 | 翻译 | 参数 |
|---|---|---|---|---|---|
| `dur.instant` | 瞬发一次 | 德克萨斯 S2 剑雨、星熊 无 | 多数 S1 | 现状 | `dur: 0` |
| `dur.timed` | 持续 N 秒 | 能天使 S2/S3 15 秒 | 多数 S2 / S3 | 现状 | `dur: N` |
| `dur.next_n` | 强化接下来 N 次攻击 | 能天使 S1（下一击 3 发） | 水月 S1、维什 S1、艾雅 S1、铃兰 S1 | 已普遍，**值得抽成积木** | `dur: {next_attacks: N}` |
| `dur.ammo` | 弹药：N 发打完为止 | 猎手、维什 S3 原作 | 维什 S3（各写各的） | 抽成通用 | `dur: {ammo: N, refill?}` |
| `dur.permanent` | 无限持续 / 开一次永久 | 浊心斯卡蒂 S2、乌尔 S2 原作 | 铃兰 S2、凯尔希 S2、乌尔 S2、Logos S2、流明 S2（`permanent: true`） | 现状 | `permanent: true` |
| `dur.charges` | 可存多次（2 次充能） | 艾丽妮 S2 原作 | **无**（docs/26 认为不值得为一人加） | 存 2 次后可以连放；手动技能更有意义 | `charges: 2` |
| `dur.toggle` | 开关型：开着持续消耗 | 部分技能 | 无 | 开启期间持续扣灯火 / 技力，可关 | 暂缓 |

### 2.4 攻击形状 `shape.*`（每次出手打到谁）

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 积木与参数 |
|---|---|---|---|---|---|
| `shape.cone` | 前方扇形 | 斯卡蒂、收割者 | 斯卡蒂、水月、艾丽妮 S2、推王 | 现状 | `{r, half_deg, max_n?}`，走 `arc_targets` |
| `shape.circle_self` | 以本人为中心的圈 | 重剑手、德克萨斯 S2「周围所有敌人」 | 鲨、乌尔、艾丽妮 S3 | 现状 | `{r}` |
| `shape.line` | 直线贯穿 | 轰击术师、艾丽妮 | 艾丽妮刺击 | 现状 | `{len, width, pierce: true}` |
| `shape.point_aoe` | 落点圆（投掷 / 炮击 / 法球爆炸） | 炮手、扩散术师 | 维什、艾雅 | 现状 | `{r, land: nearest/densest/aim, travel: 0 \| speed}` |
| `shape.projectile` | 单体弹道（追踪 / 直线） | 中坚、狙击 | Logos、铃兰、流明（各写各的） | 抽成通用投射物 | `{speed, homing, pierce_n, splash_r}` |
| `shape.chain` | 命中后跳到下一个目标 | 链术师（跳 3，每跳 -15%） | **无**（Logos 溢出转移最接近） | **大群里最划算的形状**：天然清群，跳数是成长维度 | `{jumps, falloff, jump_r, no_repeat}` |
| `shape.boomerang` | 回旋镖：去回各打一次 | 回环射手 | 无 | 去程穿透、回程再打一次，回到手上前不能再扔 | `{len, width, return: true}` |
| `shape.burst` | 一次攻击连射 N 发 | 能天使 S2/S3（4 / 5 连） | 艾丽妮 S3 12 发（各写各的） | 第三批能天使必需 | `mod.burst{n, interval}`，与形状正交 |
| `shape.global` | 全屏 / 射程内全部 | 散射手、部分大招 | 无（藏品 232 全屏真伤） | 只给大招，伤害低、带控制 | `{scope: screen}` |
| `shape.cross` / 方格 | 十字、前方几格 | 原作格子射程 | 无 | 幸存者里用「四向直线」表示，适合召唤物 / 装置 | `{arms: 4, len}` |
| `shape.dual` | 近处 A 形状、远处 B 形状 | 领主、要塞 | 无 | 近身挥砍 + 远处投射物（×0.8） | `{near: shape, far: shape, switch_r}` |

### 2.5 选目标 `target.*`

| 标签 | 定义 | 原作例 | 本作覆盖 | 积木 |
|---|---|---|---|---|
| `target.nearest` | 最近 | 默认 | 全员（Boss 优先已全局） | 缺省 |
| `target.elite` | 精英 / Boss 优先 | 攻城手（最重） | 乌尔 S1、Logos S1 | `{priority: elite}` |
| `target.densest` | 敌群最密处 | 群攻技能 | 艾雅 S3、乌尔 S3 | `densest_point` 已有 |
| `target.low_hp` | 生命比例最低 | 水月触手（最低血） | 水月 | `{priority: low_hp}` |
| `target.low_def` | 防御最低 | 神射手 | 无 | 本作护甲差异小，可并入 `low_hp` |
| `target.hover` | 空中 / 悬浮优先 | 速射手（能天使特性） | 无 | 优先 `hover` 与远程射击类敌人 = 「先清弹幕源」 |
| `target.controlled` | 受控者优先 | 艾丽妮 S3（打浮空） | 艾丽妮 | `{priority: stunned/air}` |
| `target.random` | 随机 | Logos 天赋 | Logos | `{priority: random}` |
| `target.multi` | 同时 N 个目标 | 安洁莉娜 S3（4 目标）、Logos S3 | Logos S3 | `{n}`，与任意单体形状组合 |

### 2.6 伤害类型与命中修饰 `mod.*`

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 积木与参数 |
|---|---|---|---|---|---|
| `mod.dmg_type` | 物理 / 法术 / 真实 | 全作 | `hit_sources.kind` 已有 | 现状；奠基者厚甲等敌人按类型减伤 | `{kind}` |
| `mod.def_pierce` | 无视 X% 防御 | 艾丽妮原作天赋 | 藏品 P6 | 干员侧也开放 | `{pct}` |
| `mod.multi_hit` | 一次攻击两段 | 剑豪 | 艾丽妮 | 每段都触发 on_hit，所以与触发词强联动 | `{n, delay}` |
| `mod.burst` | 一次攻击连射 N 发 | 能天使 | 各写各的 | §2.4 | `{n, interval, per_shot_mult}` |
| `mod.splash` | 主目标周围溅射 | 撼地者 50% | 乌尔、Logos / 流明（补丁溅射） | 抽成通用 | `{r, pct}` |
| `mod.aftershock` | 第二段延迟落地 | 投掷手 | 维什 | `mod.splash` 的延迟版 | `{delay, pct}` |
| `mod.pierce` | 穿透 N 个 | 轰击 / 狙击技能 | 艾丽妮 | 投射物通用参数 | `{n}` |
| `mod.execute` | 处决：低于阈值直接击杀 | Logos 原作 S1 | Logos S2、鲨 S3（低血 ×1.5） | 大群里「补刀」很爽，精英 / Boss 改为增伤 | `{hp_below, mode: kill \| mult, boss_mult}` |
| `mod.overflow` | 溢出伤害转给别人 | Logos | Logos | 与 `shape.chain` 合并实现 | `{to: random/nearest}` |
| `mod.ramp` | 连续命中同一目标伤害递增 | 驭械、Logos S2 原作 | Logos S1 | 打精英 / Boss 的单体成长 | `{step, max, reset_on_switch}` |
| `mod.cond_dmg` | 对特定状态的敌人增伤 | 艾丽妮天赋（对空无视防御） | 艾丽妮（受控 +30%）、水月（半血附近）、鲨 | **最通用的天赋形态** | `{if: st.* \| hp_below \| elite \| far \| lit, mult}` |
| `mod.lifesteal` | 伤害转治疗 | 咒愈师（50%）、收割者 | **无**（水月击杀回血接近） | 回主控，必须有每秒上限 | `{pct, cap_per_s}` |
| `mod.atk_to_heal` | 攻击变治疗 | 护佑者技能期间 | 无 | 技能期间普攻命中改为回主控 | `verb.mode{on_hit: heal}` |
| `mod.overheal_to_shield` | 治疗溢出转护盾 / 屏障 | 群愈重译 | 藏品「食腐者手杖」累计溢出 | 抽成积木：满血时治疗转护盾层 | `{ratio, max}` |
| `mod.on_hit_status` | 命中附状态 | 凝滞师（减速）、链术（停顿） | 铃兰、Logos、流明（照亮） | 抽成积木 | `{status, dur, chance}` |
| `mod.kb` | 命中击退 | 推击手 | 斯卡蒂 S2；藏品 P2 倍率 | 通用 | `{force}`，吃敌人体型档 |

### 2.7 技能动词 `verb.*`

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 积木与参数 |
|---|---|---|---|---|---|
| `verb.buff_self` | 限时提高自己攻击 / 攻速 / 范围 | 星熊 S1、安洁莉娜 S1（攻击 +40–110%） | 推王 S3、斯卡蒂 S3、鲨 S1/S2 | 现状 | `{stats: {atk, aspd, range}, dur}`，走 `stats.add("op:<id>")` |
| `verb.next_attack` | 强化下一次 / 下 N 次攻击 | 能天使 S1 | 水月 S1、维什 S1、艾雅 S1、铃兰 S1、艾丽妮 S1 | 已普遍 | `dur.next_n` + 任意 `mod` |
| `verb.mode` | 持续期间替换普攻（形状 / 类型 / 频率） | 安洁莉娜 S2 微粒模式（间隔大降、单发低）、驭法铁卫 | 维什 S3、斯卡蒂 S3、鲨 S3 | 「换一种攻击方式」是最省美术的技能 | `{attack: shape+mods, interval_mult, dmg_mult}` |
| `verb.big_hit` | 一次大伤害 | 大多数 S1 | 推王 S2、维什 S2、艾雅 S2 | 现状 | `shape + mult + st` |
| `verb.barrage` | 一段时间内多次落点 | 艾雅 S3 火山 | 艾雅 S3、艾丽妮 S3 | 抽成积木 | `{n, interval, shape, target}` |
| `verb.field` | 放下持续区域（伤害 / 回复 / 减速 / 易伤） | 塞雷娅 S3 钙质化 | 塞雷娅 S3、铃兰 S3、流明 S3、藏品 P12 旗帜 | **抽成积木**（三人各写各的） | `{r, dur, follow: leader \| fixed, dps, heal, slow, fragile}` |
| `verb.summon` | 召唤物（会动、会打、可被敌人瞄） | 召唤师、凯尔希、浊心斯卡蒂天赋（召唤海嗣） | 凯尔希 Mon3tr、鲨替身（各写各的） | **抽成积木**；召唤物可当诱饵（嘲讽重译） | `{hp?, life, ai: follow/guard/charge, attack: shape, decoy: bool}` |
| `verb.device` | 放下不动的装置（陷阱 / 炮台 / 桩） | 工匠、陷阱师 | 藏品 P21（补给、轰隆隆、起重机、防暴桩）、地雷 | 干员侧复用 P21 | `{what, n, life, place: front/densest/self}` |
| `verb.dash` | 本人位移（冲刺 / 闪现 / 弹射） | 处决者再部署、乌尔 S3 | 乌尔 S1/S3（锚链弹射） | 队友本人位移只影响出手点；主控位移要谨慎（不夺操作） | `{to: target/point, speed, land: shape}` |
| `verb.displace` | 推 / 拉敌人（力度） | 推击手、钩索师 | 斯卡蒂 S2 击退、乌尔 S1 拖拽 | **力度 - 体型档 = 位移距离**（原作公式简化） | `{dir: push/pull/to_point, force, stun?}` |
| `verb.heal` | 回复主控（瞬间 / 持续） | 医疗、守护者 | 凯尔希、塞雷娅、流明、铃兰 S2/S3 | 现状 | `{pct, hot_pct, hot_dur, low_hp_mult}` |
| `verb.cleanse` | 驱散负面 | 行医 | 流明、凯尔希 S1 | 现状 | `{what: nerve/corrode/slow/all, immune_t}` |
| `verb.shield` | 给主控护盾层 / 屏障 | 守护者原作、多数 6★ 重装 | **干员侧无**（只有局外 / 藏品护盾层） | 重装 / 辅助的核心护主动词 | `{layers \| barrier_hp, dur}` |
| `verb.protect` | 承伤转移 / 庇护 | 浊心斯卡蒂 S1（范围内 50% 伤害转给她） | 塞雷娅天赋 -12%（`dmg_taken_mult`） | 干员不掉血：改为「主控受到的伤害 -X%，期间干员技能条被『磨损』」或单纯减伤 | `{dr, dur}` 走 `dmg_taken_mult()` |
| `verb.undying` | 不死 / 锁血 | 傀儡师、鲨 S2 | 鲨 S2（`prevent_death`） | 现状 | `{dur}` |
| `verb.sp_team` | 回全队技力 | 尖兵（回费）、德克萨斯 S1 | 推王、藏品 P13 / P24 | 现状 | `{pct, target}` |
| `verb.lamp` | 回灯火 | 本作独有 | 流明 | 现状 | `{amount}` |
| `verb.bullet_clear` | 减速 / 消除敌方弹幕 | （原作对应「投射物减速」技能） | Logos S3 | 本作独有价值高 | `{r, slow, clear_on_end}` |
| `verb.mark` | 给敌人打标记，标记被引爆 / 被追击 | 部分 6★（印记） | Logos 安魂、流明照亮（都是易伤标记） | 统一成 `st.mark` + 引爆触发 | `{mark, detonate: on_kill/on_skill}` |
| `verb.transform` | 技能结束 / 开启时本人形态变化 | 傀儡师替身 | 鲨 S2 | 小众 | 暂缓 |

### 2.8 状态 `st.*`（施加给敌人）

原作控制与增减益定义转述见 docs/49b §2.1–2.3。本作前提：**主控在 Boss 期间永不硬控**；敌人体型档（普通 / 精英 / Boss）决定控制折扣。

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 积木与参数 |
|---|---|---|---|---|---|
| `st.stun` | 晕眩：不能动不能打 | 德克萨斯 S2、推王 S2 | 推王、维什、乌尔、艾丽妮、流明、藏品 233 | 现状；按原作「抵抗 = 时长减半」统一精英折扣 | `{dur, elite_mult 0.5, boss_mult 0.25}` |
| `st.slow` | 减速 / 停顿（-80%） | 凝滞师、链术 | 铃兰、塞雷娅、Logos、鲨替身 | 现状 | `{pct, dur}`，同名取最高 |
| `st.bind` | 束缚：不能动、仍能打 | 水月原作 | 水月 S2、藏品起重机 | 现状 | `{dur}` |
| `st.airborne` | 浮空：不能动不能打，可被追击 | 艾丽妮 | 艾丽妮（`e.air`） | 现状 | `{dur, height}` |
| `st.freeze` | 寒冷 → 再次寒冷变冻结 | 冰系术师 | 无（只有敌→主控冰霜减速） | 「两段式控制」：给控制流派一个连续命中奖励 | `{chill_dur, freeze_dur}` |
| `st.sleep` | 沉睡：无敌且不能动 | 部分 6★ | 无 | 大群里「冻住一片但打不动」是负收益 → 暂缓 | — |
| `st.fear` | 恐惧：四散逃跑 | 少数 | 无 | 敌人反向逃离主控 N 秒——幸存者里**直接等于开路** | `{dur, r}` |
| `st.attract` | 诱导：朝指定点移动 | 少数 | 无 | 把敌人吸到一点（配合落点 AOE） | `{point, dur}`，与 `verb.displace{to_point}` 合并 |
| `st.tremble` | 战栗：被阻挡后不能普攻 | 少数 | 无 | 贴近主控的敌人不能出手（近战接触伤害取消）→ 「阻挡圈」的强化 | `{dur}` |
| `st.paralyze` | 麻痹：层数打断敌人普攻 | 神经爆发 | 无 | 取消一次敌人预警招式（docs/49b） | 暂缓（依赖预警系统接口） |
| `st.silence` | 沉默：能力 / 光环失效 | 常见 | 无 | 关掉巢涌者神经光环、育母召唤 | 暂缓（要敌人能力打标） |
| `st.weightless` | 失重：重量 -1 | 安洁莉娜 S3 | 藏品 103 安洁莉娜的创想（击退 +40%） | 被击退 / 推拉距离更远 | `{kb_mult, dur}`（藏品 P2 的单体版） |
| `st.fragile` | 脆弱 / 易伤：受伤 +X% | 削弱者 | 塞雷娅 S3、铃兰、艾雅 S2 | 现状；原作同名取最高、不同名相乘——本作要定口径 | `{pct, kind?: arts/phys, dur}` |
| `st.mark_lit` / `st.requiem` | 本作独有的易伤标记 | — | 流明「照亮」、Logos「安魂」 | 已是 `st.fragile` 的命名实例 | 并入 `st.fragile{name}` |
| `st.weaken` | 虚弱：攻击力 -X% | 削弱者 | 无 | 敌人碰主控伤害 / 弹幕伤害 -X% | `{pct, dur}` |
| `st.dot` | 持续伤害（灼烧 / 流血） | — | 艾雅点燃、藏品 `status bind/stun dot` | 抽成积木 | `{dps, dur, kind}` |
| `st.element` | 元素损伤累积 → 爆发（神经 / 侵蚀 / 灼燃 / 凋亡） | 巫役、本源 | 无（只有敌→主控神经 / 侵蚀） | 我方对敌元素条：满了爆发大额固定伤害，Boss 阈值 ×2 | 暂缓（§8） |

### 2.9 防护与生存（给主控）

| 标签 | 定义 | 原作例 | 本作覆盖 | 翻译 | 积木 |
|---|---|---|---|---|---|
| `def.dr` | 受伤 -X%（庇护） | 护佑者 | 塞雷娅天赋、藏品多件 | `dmg_taken_mult()` | `aura.dr{pct}` |
| `def.flat` | 固定值减伤 | 「伤害减免」 | 主控护甲 | 克大群小额 | `stat armor` |
| `def.chance_negate` | 概率完全抵挡一次伤害（含真伤） | 星熊天赋战术装甲 | **无**（闪避不挡真伤） | 第三批星熊必需 | `{chance, cap}` 挂 DamageTaken |
| `def.dodge` | 闪避 | 伏击客 | 局外 / 藏品闪避（上限 60%） | 现状 | `stat dodge` |
| `def.shield` | 护盾层（按次数） | — | 局外 / 藏品护盾层 | 干员给护盾 = `verb.shield` | — |
| `def.barrier` | 屏障（按数值，血条外） | 多数 | 无 | 治疗溢出转屏障 | `{hp, decay}` |
| `def.thorns` | 反伤：攻击者受伤 | 星熊 S2 荆棘 | **无** | 碰到主控的近战敌人受伤 = 天然清贴脸怪 | `trig.on_hurt → damage{to: attacker, mult}` + `aura.contact_dmg{r}` |
| `def.block_ring` | 阻挡：接触敌人停下 | 铁卫 | 塞雷娅阻挡圈（推开 / 减速） | §5 重译 | `{r, n, mode: push/stop/slow}` |
| `def.max_hp` | 提高最大生命 | 浊心斯卡蒂 S1 | 鲨自定义节点 | 限时版本 = 「临时最大生命」 | `{pct, dur}` |

### 2.10 光环与团队增益 `aura.*`（干员 → 干员 / 主控）

| 标签 | 定义 | 原作例 | 本作覆盖 | 翻译 | 积木 |
|---|---|---|---|---|---|
| `aura.aspd` | 全队攻速 | 安洁莉娜天赋加速力场 | **无**（只有藏品） | 第三批安洁莉娜必需 | `{aspd, scope: all/class}` 走 `stats.add` |
| `aura.atk` / `aura.inspire` | 全队攻击 / 鼓舞（按本人攻击的 X% 加给别人） | 浊心斯卡蒂 S2/S3、吟游者 | 铃兰 S2 队友攻击 +15% | 「鼓舞」= 按本人攻击力换算的绝对加成，本人不吃 | `{atk_pct_of_self, exclude_self}` |
| `aura.heal` | 持续回复 | 吟游者特性 | 铃兰 S2（0.5%/秒）、塞雷娅 S3、流明 S3 | 现状 | `{pct_per_s, r?}` |
| `aura.dps` | 范围内持续伤害 | 浊心斯卡蒂 S3（真伤） | 鲨替身、藏品 168 | 现状 | `{dps, r, kind}` |
| `aura.sp` | 全队技力回复 | 先锋、启示「大炎的沧桑」 | 推王、藏品 sp_gain | 现状 | `stat sp_gain` |
| `aura.random_ally` | 随机给一名队友加成 | 能天使天赋天使的祝福 | 无 | 招募 / 开技能时随机一名队友 +X% | `{stat, pct, pick: random}` |

### 2.11 代价 `cost.*`（原作越往后越多的「代价换强度」）

| 标签 | 定义 | 原作例 | 本作覆盖 | 翻译 | 积木 |
|---|---|---|---|---|---|
| `cost.hp_drain` | 持续掉自己生命换强度 | 浊心斯卡蒂 S3、怪杰、狂躁损伤 | 无（鲨按已损生命加攻，是「利用」不是「付出」） | 扣**主控**生命（有下限，不致死） | `{pct_per_s, floor}` |
| `cost.heal_block` | 不受治疗 | 武者、不屈者 | 无 | 技能期间主控受到的治疗 -X% | `{pct, dur}` |
| `cost.no_attack` | 期间不普攻 | 执旗手、阵法、铃兰 S3 | 铃兰 S3 | 现状 | `verb.mode{no_attack}` |
| `cost.upkeep` | 在场持续扣资源 | 行商 | 无 | 技能持续扣灯火 / 源石锭 | 暂缓 |
| `cost.self_debuff` | 技能后虚弱 / 倒下 | 鲨 S2 | 鲨 S2（倒下 12 秒） | 现状 | `{after: down_t \| aspd_mult}` |

---

## 3. 天赋触发词汇 `trig.*`

> 天赋 = 「触发 + 条件 + 动作」。动作直接复用 §2 的动词和修饰。挂点列是现有事件或要新增的询问。

| 标签 | 定义 | 原作例 | 本作覆盖 | 幸存者翻译 | 挂点 / 参数 |
|---|---|---|---|---|---|
| `trig.on_deploy` | 部署时 | 德克萨斯天赋（部署时额外费用）、缄默德克萨斯（部署时周围法伤晕眩） | 无 | **招募入队时 / 成为主控时 / 精英化时 / 每次 Boss 结束时**（四选一） | 事件 Recruited（P10）+ 新增 LeaderChanged |
| `trig.on_attack` | 每次攻击 / 命中 | 链术、凝滞师 | 推王（命中回技力）、铃兰 | 现状 | AttackStarted / Hit |
| `trig.every_n` | 每第 N 次攻击 | 斯卡蒂原作、多段天赋 | 斯卡蒂（每第 3 次反手斩）、水月唤醒 | 抽成积木 | `{n}` 计数器 |
| `trig.chance` | 概率触发 | Logos 天赋 50% | Logos | 抽成积木（走对局 rng） | `{p}` |
| `trig.on_kill` | 击杀时（可限精英 / Boss） | 冲锋手、乌尔天赋、塑灵 | 乌尔（精英 +1 层）、维什残影、水月回血、藏品 P25 | 现状 | EnemyKilled `{elite_only}` |
| `trig.on_hurt` | 主控受击时 | 星熊 S2 荆棘、受击回复 | 藏品 P23（受击全屏真伤 / 晕眩）、铁卫-无锋 | 干员天赋开放 | DamageTaken `{min_pct, cd}` |
| `trig.on_dodge` | 闪避 / 护盾挡下时 | — | 藏品 166 | 现状 | Dodge / ShieldBroken |
| `trig.hp_below` | 主控生命低于 X% | 傀儡师、大量 6★ 天赋 | 塞雷娅 S1（低血翻倍）、藏品 P14 | 抽成条件 | 条件 `{leader_hp_below}` |
| `trig.hp_lost_scale` | 按主控已损生命线性加成 | 坚忍 / 「求生」 | 鲨 S1 | 抽成积木 | `{per_pct_lost, max}` |
| `trig.near_count` | 周围有 ≥N 名敌人 / 没有敌人 | 要塞（不阻挡时）、秘术（无敌人时存弹） | 无 | 「被围时变强」或「清场后蓄力」——幸存者里极自然 | 条件 `{r, op: >=/==0, n}` |
| `trig.enemy_state` | 目标处于某状态 | 艾丽妮天赋（对空）、本源（元素爆发） | 艾丽妮（受控 +30%）、Logos（安魂） | 现状 | 条件 `{st}` |
| `trig.enemy_hp` | 目标生命低于 / 高于 X% | 处决类 | 水月（半血附近 +22%）、鲨 S3 | 现状 | 条件 `{target_hp_below}` |
| `trig.squad_faction` | 编队有某阵营 | 乌尔 / 浊心斯卡蒂（深海猎人）、罗德岛精英、格拉斯哥帮、企鹅物流 | 乌尔（层数分给深海猎人）、鲨（深海猎人加最大生命） | **第三批天然有两个阵营**：深海猎人（浊心斯卡蒂 + 斯卡蒂 + 乌尔 + 鲨）、企鹅物流（德克萨斯 + 能天使） | JSON 加 `faction: []`，条件 `{faction, count}` |
| `trig.squad_class` | 编队有某职业 | 星熊天赋（重装加防）、原作「同职业」光环 | 精二旧条件（已废）；藏品 `requires_class` / `class:` | 现状 | 条件 `{class, count}` |
| `trig.on_skill_start` / `end` | 技能开启 / 结束时 | 傀儡师、大量天赋 | 藏品 P24、鲨（结束倒下）、凯尔希 S3（结束熔毁） | 现状 | SkillStarted / SkillEnded |
| `trig.skill_idle` | 技能**没开时**持续生效 | 安洁莉娜天赋二（技能未开时全队回血） | 藏品「黑色郁金香」类 | 第三批安洁莉娜 | 条件 `{own_skill_active: false}` |
| `trig.any_skill` | 任一队友开技能时 | 原作「队友开技能时」 | 藏品 176 | 干员侧开放 = 编队协同 | SkillStarted `{who: ally}` |
| `trig.tick` | 每 N 秒 | 自然回复、解放者累积 | 藏品 P13 / P20 | 现状 | Tick `{every}` |
| `trig.stack` | 层数累积（击杀 / 命中 / 时间）| 乌尔天赋、解放者 | 乌尔 | 抽成积木 | `{on, per, max, decay?}` |
| `trig.lamp_tier` | 灯火在某档 | 本作独有 | 鲨（昏暗）、流明（充盈） | 本作独有，**每名新干员都该考虑一条** | 条件 `{lamp: dim/lit/full}` |
| `trig.boss_present` | Boss 在场 | 原作「场上有海嗣」 | 艾丽妮原作天赋二（本作折成节点） | Boss 战专属增益 | 条件 `{boss_alive}` |
| `trig.leader` | 当主控 / 当队友时不同 | — | 手动技能只在主控时（v2.3） | 「主控天赋 / 队友天赋」分开写，给选主控一个理由 | 条件 `{is_leader}` |

---

## 4. 集成战略（肉鸽）里能改干员的钩子

只挑对干员积木有用的；系统级（灯火、排异、结局）docs/49a 已有。

| 钩子 | 原作 | 本作现状 | 对干员积木的意义 |
|---|---|---|---|
| 职业专属藏品 | 「锈刃 / 钝爪 / 折戟 / 铁卫 / 残弩 / 断杖 / 支柱 / 医者」系列 | docs/57 已全部按 `class:` 实装 | 证明「按标签筛选」可行 → 推广到 §4.1 的**按积木标签筛选** |
| 排异反应（技能海嗣化） | 4 基础 + 「+」版 + 进化 | 结局四随机一个技能海嗣化（强度 +40%、充能 +30%） | 积木化后，海嗣化可以是**改一个积木参数**（例：`shape.cone` → 半角 +50%、`st.slow` → `st.bind`），而不是统一数值 |
| 启示（7 国全队增益） | 满灯火掷骰给 | 无 | 启示 = 一条全队 `aura.*` 或 `trig.*`，可直接复用积木 |
| 坍缩范式（银凇） | 坍缩值到阈值叠一条负面规则，最多 4 条，有加深版 | 无 | 「越打越乱」的负面积木：敌人获得 `st.*` 免疫、主控受 `cost.*`；可做高难档 |
| 思绪 / 解读（萨卡兹） | 两件思绪组合解读出藏品 | 无 | 「积木合成」：两个同类标签的藏品合成一个新规则（例：`mod.splash` + `shape.chain` → 弹射溅射）——给玩家自制干员一个局内版 |
| 密文板（银凇） | 三色、同色组合触发协语 | 无 | 「标签套装」：编队里同一标签（如 `st.slow`）达到 3 个来源时给套装效果 |
| 剧目（傀影） | 一次性下一战增益 | 无 | 一次性「下一次技能 ×2」= `dur.next_n` 套到技能上 |
| 典训 / 进阶券 | 立即进阶对应职业 | 已有（`advance_class` / P10） | — |
| 分队 | 开局整局规则 | 无 | 「职业分队」= 某职业的某个积木参数全局 +X（例：狙击 `target.multi` +1） |
| 招募券 | 按职业 / 双职业 | 招募三选一 | 招募权重可按标签（例：缺 `verb.heal` 时加权，docs/49e 已对医疗做） |

### 4.1 建议：标签直接进命中描述符

`hit_sources.tags` 现在只有少量（`area`、追击）。积木化后每次命中自带形状 / 修饰标签（`chain`、`summon`、`dot`、`execute`、`burst`、`field`），藏品就能写 `scope: tag:chain`。这样**新干员一进来就自动吃到已有藏品**，内容丰富度随干员数平方增长，而不是每人手配。

---

## 5. 需要重译的原作规则（幸存者口径）

| 原作规则 | 为什么不能照搬 | 本作重译（提案） | 已有先例 |
|---|---|---|---|
| **阻挡 / 阻挡数** | 没有路线，敌人全追主控 | 「阻挡圈」：主控周围 r 内同时顶住至多 N 个敌人（停下 / 推开 / 减速），超过 N 的照常贴上；阻挡数 = 成长维度 | 塞雷娅阻挡圈、藏品 213 防暴桩 |
| **嘲讽** | 敌人只打主控 | 「诱饵」：召唤物 / 装置 / 替身吸引 r 内敌人改追它 N 秒（`verb.summon{decoy}`）；敌人只会被吸走，不会打干员 | 鲨替身（目前不吸怪） |
| **隐匿 / 迷彩** | 主控是唯一目标 | 主控「不被锁定」：远程敌人开火间隔变长 / 瞄偏，近战敌人追击速度 -X%（不是完全无视，免得无聊） | 藏品 119 捕鳞蓑 |
| **再部署 / 撤退** | 干员不死、不撤退 | 「离场 → 倒计时归队」；处决者的「再部署快」改成短冷却闪现落地斩；「撤退」= 换主控 | 鲨 S2 倒下 12 秒 |
| **部署费用（DP）** | 没有费用 | 回费 → 全队技力；花费 → 源石锭 / 灯火 / 主控生命；冲锋手击杀回费 → 击杀回技力 | 推王、藏品 P25 |
| **部署时** | 只部署一次 | 招募入队 / 成为主控 / 精英化 / Boss 后，四个时机选一 | P10 Recruited |
| **飞行 / 对空** | 没有地空分层 | 悬浮敌人（`hover`）近战伤害打折；「对空」= 优先打悬浮 / 远程射手 | 飘航者、漂移体 |
| **治疗友方 / 群愈 / 链愈** | 只有主控掉血 | 溢出转护盾 / 屏障；链愈不做 | 食腐者手杖 |
| **生命低于 X（干员自身）** | 干员没有血条 | 一律读主控生命 | 塞雷娅 S1、藏品 P14 |
| **受击回复（干员挨打）** | 干员不挨打 | 主控受击时给**该干员**充能 | 藏品「铁卫-无锋」 |
| **重量 / 力度** | 敌人没有重量字段 | 三档体型（普通 / 精英 / Boss）当重量：位移距离 = 力度 - 档位；控制时长按档 ×1 / ×0.5 / ×0.25 | 各技能里写死「精英 1 秒、Boss 不浮空」 |
| **攻击范围格子** | 连续空间 | 一律半径 / 扇形；「前方 N 格」= 直线 / 扇形，朝向 = 瞄准方向（v2.5） | — |
| **地面 / 高台位** | 没有地块类型 | 不做；近战 / 远程只影响藏品 `range:` 筛选 | — |

---

## 6. 第三批五人需要的标签（原作 → 本作）

> 原作资料：wiki.gg 干员页（2026-10-11）。中文技能名为常用译名，未逐字核对的标（待核）。本节只列积木需求，具体技能设计在 docs/59。

| 干员 | 原作分支 / 要点 | 需要的标签 | 其中**新积木**（现有 13 人没有） |
|---|---|---|---|
| **浊心斯卡蒂** | 辅助·吟游者：不攻击，持续给范围内友军回复（攻击力 10%/秒），不吃鼓舞。天赋一：召唤一只海嗣（15 / 25 秒），海嗣延伸她的范围；天赋二：范围内有友军时攻击 +6%，是深海猎人则 +15%。S1（手动 30 秒）：满血、最大生命大增、回复加强、范围内友军所受伤害一半转给她；S2（永久）：范围内友军获得「鼓舞」（按她攻击 / 防御的比例）；S3（手动 20 秒）：特性变为每秒失去 5% 生命，对范围内敌人每秒真伤，并给友军更强鼓舞 | `aura.heal`、`verb.mode{no_attack}`、`verb.summon`（海嗣，可当光环第二中心）、`trig.squad_faction{深海猎人}`、`aura.inspire`、`dur.permanent`、`verb.protect` + `def.max_hp`、`cost.hp_drain`、`aura.dps{true}`、`cast.manual` | `aura.inspire`、`verb.summon`（通用化）、`cost.hp_drain`、`trig.squad_faction`（JSON 字段） |
| **德克萨斯** | 先锋·尖兵（阻挡 2）。天赋：在编队时开局额外费用。S1 冲锋号令（自动，瞬发回费）；S2 剑雨（手动，瞬发：回费 + 周围全部敌人两次法伤 + 晕眩 2–3 秒）。另有异格「缄默德克萨斯」（特种·处决者：再部署快、部署时周围法伤晕眩）——用户若指异格，需要 `verb.dash{blink}` + `trig.on_deploy` | `verb.sp_team`、`shape.circle_self`、`mod.multi_hit{2}`、`mod.dmg_type{arts}`、`st.stun`、`trig.on_deploy`（重译为招募 / 成为主控时）、`trig.squad_faction{企鹅物流}` | `trig.on_deploy`；**风险**：原版与推王都是「技力电池」，要靠剑雨（法伤群控）和企鹅物流阵营与推王拉开 |
| **星熊** | 重装·铁卫（阻挡 3）。天赋一：概率抵挡一次伤害（含真伤，12% → 25%）；天赋二：在场时我方重装防御 +6%。S1（20–30 秒）攻防提升；S2 荆棘（被动）：防御提升，攻击她的敌人受到反伤；S3 力之锯（25 秒）攻防大幅提升，并攻击前方全部敌人 | `def.block_ring{n 3}`、`def.chance_negate`、`trig.squad_class{重装}`、`verb.buff_self`、`cast.passive`、`def.thorns` / `trig.on_hurt`、`sp.on_hurt`、`shape.cone{max_n: all}` / `shape.line` | `def.chance_negate`、`def.thorns`、`sp.on_hurt`、`verb.shield`（建议给她做护主动词） |
| **能天使** | 狙击·速射手：优先打空中。天赋一：攻速提升；天赋二：自身攻击 / 生命提高，部署时随机一名友军也获得。S1 冲锋模式（攻击回复，下一次攻击连射 3 发）；S2 扫射模式（手动 15 秒，每次攻击 4 连发）；S3 过载模式（自动 15 秒，5 连发且攻速更快） | `target.hover`、`stat aspd`、`aura.random_ally`、`sp.on_attack`、`dur.next_n`、`mod.burst{n 3/4/5}`、`verb.mode`、`trig.squad_faction{企鹅物流}` | `sp.on_attack`、`mod.burst`（通用化）、`target.hover`、`aura.random_ally` |
| **安洁莉娜** | 辅助·凝滞师：法伤并短暂减速。天赋一：全队攻速提升；天赋二：自身技能未开启时全队每秒回复。S1 速充模式（攻击回复，攻击提升）；S2 微粒模式（攻击间隔大幅缩短，但每发伤害只有攻击力 30–45%）；S3 反重力模式：全场敌人失重、射程扩大、攻击提升、同时攻击 4–5 个目标 | `mod.on_hit_status{slow}`、`aura.aspd`、`trig.skill_idle → aura.heal`、`sp.on_attack`、`verb.buff_self`、`verb.mode{interval 大降, dmg 低}`、`st.weightless`（接藏品 103 / P2）、`target.multi{4}`、`shape.global`（失重只作用于状态） | `aura.aspd`、`trig.skill_idle`、`st.weightless`（P2 的单体 / 全场版） |

**五人合计的新积木**：`sp.on_attack`、`sp.on_hurt`、`mod.burst`、`aura.inspire`、`aura.aspd`、`aura.random_ally`、`verb.summon`（通用）、`verb.shield`、`def.chance_negate`、`def.thorns`、`cost.hp_drain`、`trig.on_deploy`、`trig.skill_idle`、`trig.squad_faction`、`target.hover`、`st.weightless`。其余全部是现有 13 人已经在用、只需抽出来的积木。

---

## 7. 覆盖矩阵

### 7.1 现有 13 人 × 标签（● = 普攻 / 技能 / 天赋明确使用，○ = 近似 / 各写各的）

| 标签 | 水月 | 推王 | 斯卡蒂 | 塞雷娅 | 维什 | 艾雅 | 凯尔希 | 铃兰 | 乌尔 | 艾丽妮 | 鲨 | Logos | 流明 | 藏品 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `shape.cone` | ● | ● | ● | | | | | | | ● | | | | |
| `shape.circle_self` | | | ○ | ○ | | | | | ● | ● | ● | | | P20 |
| `shape.line` | | | | | | | | | | ● | | | | |
| `shape.point_aoe` | | | | | ● | ● | | | ● | | | | | 地雷 |
| `shape.projectile` | | | | | ○ | ○ | | ● | | | | ● | ● | |
| `shape.chain` | | | | | | | | | | | | ○ | | |
| `mod.burst` | | | | | | | | ○ | | ○ | | | | |
| `target.elite` | | | | | | | | | ● | | | ● | | |
| `target.densest` | | | | | | ● | | | ● | | | | | |
| `target.multi` | | | | | | | | ● | | | | ● | | |
| `mod.multi_hit` | | | | | | | | | | ● | | | | |
| `mod.splash` | ○ | | | | ● | ● | | ● | ● | | | ● | ● | |
| `mod.execute` | | | | | | | | | | | ● | ● | | |
| `mod.ramp` | | | | | | | | | | | | ● | | |
| `mod.cond_dmg` | ● | | | | | | | | | ● | ● | | | P14 P15 |
| `mod.lifesteal` | ○ | | | | | | | | | | | | | |
| `mod.def_pierce` | | | | | | | | | | | | | | P6 |
| `mod.dmg_type 真实` | | | | | | | ● | | | | | | | 232 |
| `verb.buff_self` | | ● | ● | | | | ● | | ● | | ● | ● | | |
| `dur.next_n` | ● | ● | ● | | ● | ● | | ● | | ● | | | | |
| `verb.mode` | | | ● | | ● | | | ● | | | ● | | | |
| `verb.barrage` | | | | | | ● | | | | ● | | | | |
| `verb.field` | | | | ● | | ○ | | ● | | | | | ● | P12 |
| `verb.summon` | ○ | | | | | | ● | | | | ● | | ○ | P21 |
| `verb.dash` | | | | | | | | | ● | | | | | |
| `verb.displace` | | | ● | ○ | | | | | ● | | | | | P2 |
| `verb.heal` | ○ | | | ● | | | ● | ● | | | | | ● | 多件 |
| `verb.cleanse` | | | | | | | ● | | | | | | ● | P18 |
| `verb.shield` | | | | | | | | | | | | | | 护盾层 |
| `verb.undying` | | | | | | | | | | | ● | | | 复活 |
| `verb.sp_team` | | ● | | | | | | | | | | | | P13 P24 P25 |
| `verb.bullet_clear` | | | | | | | | | | | | ● | | |
| `dur.permanent` | | | | | | | ● | ● | ● | | | ● | ● | |
| `dur.ammo` | | | | | ● | | | | | | | | | |
| `cast.manual` | | | | | | | | | ● | | | | | |
| `st.stun` | ● | ● | | | ● | | | | ● | ● | | | ● | P23 |
| `st.slow` | | | | ● | | | | ● | | | ● | ● | | P1 |
| `st.bind` | ● | | | | | | | | | | | | | 起重机 |
| `st.airborne` | | | | | | | | | | ● | | | | |
| `st.fragile` | | | | ● | | ● | | ● | | | | ● | ● | |
| `st.dot` | | | | | | ● | | | | | ● | | | status dot |
| `trig.every_n` | ● | | ● | | | | | | | | | | | |
| `trig.chance` | | | | | | | | | | | | ● | | |
| `trig.on_kill` | ● | | | | ● | | | | ● | | | | | P25 |
| `trig.on_hurt` | | | | | | | | | | | | | | P23 |
| `trig.hp_below` / `hp_lost_scale` | | | | ● | | | | | | | ● | | | P14 |
| `trig.near_count` | | | | | | | | | | | | | | |
| `trig.enemy_state` | | | | | | | | | | ● | | ● | | |
| `trig.squad_faction` | | | | | | | | | ● | | ● | | | |
| `trig.lamp_tier` | | | | | | | | | | | ● | | ● | 多件 |
| `trig.stack` | | | | | | | | | ● | | | | | P24 |
| `aura.atk / inspire` | | | | | | | | ○ | | | | | | |
| `aura.aspd` | | | | | | | | | | | | | | 藏品 |
| `def.dr` | | | | ● | | | | | | | | | | 多件 |
| `def.thorns` | | | | | | | | | | | | | | |
| `sp.on_attack` | ○ | | | | | | | | | | | | | |
| `sp.on_hurt` | | | | | | | | | | | | | | 铁卫-无锋 |

### 7.2 现有阵容最大的五个缺口

1. **非时间型技力（`sp.on_attack` / `sp.on_hurt`）**：13 人全部按时间充能，原作三大回复类型只用了一个。攻击回复让高攻速干员有节奏感，受击回复把主控挨打变成资源；实现只动 `charge_skills`，成本极低。
2. **团队光环 / 鼓舞（`aura.inspire` / `aura.aspd`）**：辅助、先锋给队友的增益只有铃兰 S2 一条和推王的技力；编队制的「协同」主要靠藏品。第三批浊心斯卡蒂、安洁莉娜、能天使都要。
3. **通用召唤物 / 装置（`verb.summon` / `verb.device` + 诱饵）**：Mon3tr、替身、灯塔、藏品装置全部各写各的；召唤物还是「嘲讽」唯一合理的重译载体。
4. **连锁弹射（`shape.chain`）**：原作一整个分支（链术师）+ 链愈师，本作完全没有；它是大群里性价比最高的形状，也给「跳数」这个成长维度。
5. **受击触发与给主控的防护动词（`trig.on_hurt` / `def.thorns` / `verb.shield` / `def.chance_negate`）**：干员侧没有一个「主控被打时做点什么」的天赋；护盾只来自局外和藏品。重装 / 护主类干员的设计空间几乎没开。

次一级缺口：吸血（`mod.lifesteal`，咒愈师 / 收割者）、拉怪（`verb.displace{pull}` 真正把敌人拉过来）、「被围时变强」（`trig.near_count`）、代价换强度（`cost.*`）、对敌元素爆发（`st.element`）。

---

## 8. 推荐首批积木（34 个）

> 选法：①现有 13 人里已有 ≥2 人各写各的（抽出来立刻减代码、加一致性）；②第三批五人需要；③与藏品 / 事件已有挂点直接相接；
> ④在大群玩法里玩家看得出差别。标 **[3]** = 第三批要用，**[抽]** = 从现有干员抽出。

**外壳（4）**
1. `sp.auto` / `sp.on_attack` / `sp.on_hurt`（一个字段三种取值）**[3]**（能天使、安洁莉娜、星熊）
2. `dur.instant` / `dur.timed` / `dur.next_n` / `dur.ammo` / `dur.permanent`（一个字段）**[抽][3]**
3. `cast.auto` / `cast.manual{aim}`（已有，纳入同一 schema）**[3]**（浊心斯卡蒂、德克萨斯、能天使原作手动）
4. `cast.passive`（= 解锁即生效的永久型）**[3]**（星熊荆棘）

**形状与选目标（8）**
5. `shape.cone{r, half, max_n}` **[抽][3]**（星熊 S3）
6. `shape.circle_self{r}` **[抽][3]**（德克萨斯剑雨）
7. `shape.line{len, width, pierce}` **[抽]**
8. `shape.point_aoe{r, land, travel}` **[抽]**
9. `shape.projectile{speed, homing, pierce_n}` **[抽][3]**（能天使、安洁莉娜）
10. `shape.chain{jumps, falloff, jump_r}`（新，缺口 4）
11. `target.priority{nearest / elite / densest / low_hp / hover / controlled / random}` **[抽][3]**（能天使对空）
12. `target.multi{n}` **[抽][3]**（安洁莉娜 S3）

**修饰（7）**
13. `mod.dmg_type{物理 / 法术 / 真实}` **[3]**
14. `mod.multi_hit{n}` / `mod.burst{n, interval}`（一个积木两种节奏）**[抽][3]**（能天使、德克萨斯）
15. `mod.splash{r, pct, delay}`（含余震）**[抽]**
16. `mod.cond_dmg{if, mult}`（含处决 `mode: kill`）**[抽]**
17. `mod.on_hit_status{status, dur, chance}` **[抽][3]**（安洁莉娜减速）
18. `mod.lifesteal{pct, cap_per_s}`（新，次级缺口）
19. `mod.kb{force}`（与体型档、P2 相接）**[抽][3]**（安洁莉娜失重）

**动词（9）**
20. `verb.buff_self{stats, dur}` **[抽][3]**（星熊、安洁莉娜）
21. `verb.mode{attack, interval_mult, dmg_mult, no_attack}` **[抽][3]**（能天使 S2/S3、安洁莉娜 S2、浊心斯卡蒂不攻击）
22. `verb.field{r, dur, follow, dps, heal, slow, fragile}` **[抽]**
23. `verb.summon{life, ai, attack, decoy}` **[抽][3]**（浊心斯卡蒂海嗣；缺口 3）
24. `verb.displace{push / pull / to_point, force}` **[抽]**
25. `verb.heal{pct, hot, low_hp_mult}` **[抽][3]**
26. `verb.shield{layers | barrier}` + `verb.protect{dr, dur}`（新，缺口 5）**[3]**（星熊、浊心斯卡蒂 S1）
27. `verb.sp_team{pct, target}` **[抽][3]**（德克萨斯）
28. `aura{stat: atk_inspire / aspd / heal / dps / dr, scope, exclude_self}`（光环一个积木）**[3]**（浊心斯卡蒂、安洁莉娜、能天使天赋二；缺口 2）

**状态（3）**
29. `st.control{stun / bind / airborne / weightless, dur}` + 体型档折扣 **[抽][3]**
30. `st.slow{pct, dur}` **[抽][3]**
31. `st.fragile{pct, kind, name}`（照亮 / 安魂并入）+ `st.dot{dps, dur}` **[抽]**

**触发（5，组合「触发 + 条件 + 动作」）**
32. 触发：`on_attack` / `every_n` / `chance` / `on_kill{elite}` / `on_hurt{min_pct, cd}` / `on_skill_start|end` / `tick{every}` / `on_deploy`（= Recruited + 新增 LeaderChanged）**[3]**
33. 条件：`leader_hp_below` / `hp_lost_scale` / `enemy_state` / `target_hp_below` / `near_count` / `squad_faction` / `squad_class` / `skill_idle` / `lamp_tier` / `is_leader` **[3]**（星熊 `squad_class`、浊心斯卡蒂 / 德克萨斯 / 能天使 `squad_faction`、安洁莉娜 `skill_idle`）
34. 动作扩展：`def.chance_negate{p}`、`def.thorns{mult, r}`、`cost.hp_drain{pct, floor}`、`trig.stack{on, per, max}` **[3]**（星熊、浊心斯卡蒂 S3）

配套（不是积木，但要一起做）：干员 JSON 加 `faction: []`（深海猎人、企鹅物流、罗德岛精英……）；命中描述符 `tags` 自动带上形状 / 修饰标签（§4.1）；控制时长的体型档折扣写进 `balance.json`。

---

## 9. 暂缓的标签与理由

| 标签 | 暂缓理由 |
|---|---|
| `st.element`（对敌元素累积 → 爆发） | 要给敌人加四条元素值、爆发冷却、Boss 阈值，涉及 `enemies.gd` 与绘制；收益集中在术师 / 巫役流派。等首批积木稳定后单独立项（docs/49b §4.4 第 2 条已排） |
| `st.freeze`（寒冷两段式） | 依赖「同一状态再次命中」的计数，先等 `st.control` 统一后再加，成本中等 |
| `st.sleep`（沉睡 = 无敌不能动） | 大群里让一片敌人打不动是负体验 |
| `st.fear` / `st.attract` | 要改敌人移动 AI（目前统一追主控）；`attract` 可先用 `verb.displace{to_point}` 近似 |
| `st.silence` / `st.paralyze` | 需要先给敌人能力 / 预警招式打「可沉默 / 可打断」标记，属于敌人侧改造 |
| `st.tremble`（战栗） | 本作近战敌人靠接触伤害，「不能普攻」等于取消接触伤害，强度难控 |
| `cast.channel` / `cast.overload` | 只对手动技能有意义，手动技能每人至多 1 个，先看玩家对手动技能的反馈 |
| `dur.charges`（多次充能） | docs/26 已判断不值得为一人加；手动技能普及后再议 |
| `dur.toggle` / `cost.upkeep`（行商） | 开关型技能在自动释放体系里没有决策点 |
| `sp.store`（秘术存弹）/ `sp.on_contact`（决战者） | 有趣但单一分支专用，等有对应干员再做 |
| 链愈、群愈、守望者、巡空者、裂空、对空分层 | 只有主控受伤 / 没有地空分层，重译后与现有积木重复 |
| `verb.transform` | 只有傀儡师一类，鲨已手写 |
| 再部署 / 部署费用本体 | 本作没有费用与撤退；已重译为技力 / 归队倒计时，不需要独立积木 |
| 隐匿 / 迷彩（主控） | 主控是唯一目标，完全隐身会让游戏停摆；只做藏品 119 那样的「降低被锁定」 |
| 坍缩范式 / 思绪合成 / 密文板套装 | 系统级玩法，属于藏品 / 事件会话；本文只记录它们可以复用积木（§4） |
