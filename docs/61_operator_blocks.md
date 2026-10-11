# 61 · 干员积木规格（数据驱动干员 第一步，2026-10-11）

> 本文是**唯一的积木规格**：合并 docs/59 §10（积木化方案，按现成代码起名）与 docs/60 §0 / §8（原作词汇表，推荐首批 34 块），
> 两边名字不同时**以 docs/60 为准**（docs/59 §10 末尾已约定），参数以现成代码为准。docs/59 / docs/60 不再改，以后改积木只改本文。
> 实现：`game/scripts/characters/op_blocks.gd`（积木执行器 + 校验，纯 op_api，不碰 game.gd 内部）、
> `game/scripts/characters/data_operator.gd`（继承 character.gd，读 JSON 的 `blocks` 段）。第一个纯数据干员：浊心斯卡蒂 `skalter`（docs/59 §1）。
> 范围：只实现**现在要用的**积木（浊心斯卡蒂 + 等价测试）和现有 13 人最常见、实现成本几乎为零的几块；docs/60 §8 其余的只登记参数（标 📝），用到时再实现。

## 0. 总则

1. **一名数据干员 = 一份 JSON**（`data/characters/<id>.json`）：沿用现有干员 JSON 的全部字段（`base / leader / sprites / attack / skills / talent / hit_sources / progression / gallery`），
   另加 `blocks`（给 `data_operator.gd` 执行）和 `faction`。`skills[i].desc` 仍是给玩家看的文字，`blocks` 是给程序的；两边数值都从 `base` 来。
2. **不写 `script` 或写 `res://scripts/characters/data_operator.gd`** 都按数据干员加载（`Character.create`：有 `blocks` 而没写 `script` 时缺省用 data_operator）。
   数据干员也可以写一个继承 data_operator.gd 的小脚本放 `custom` 函数（逃生口，§6）。
3. **数值一律引用 `base`**：参数值写数字，或写 `"$key"` 表达式（§1.2）。积木里不写裸的平衡数（docs/27 §9.5）；`1.0`、`0.5` 这类结构性常数可以直接写。
4. **确定性**（docs/36 §3）：积木只用 `g.rng` 做玩法随机（第一版积木没有随机项），画面一律不碰 `g.rng`；
   属性修正按积木在 JSON 里的**固定顺序**整组重建（§5.3），浮点求和顺序与时机可复现。
5. **伤害一律先 `log_hit(src, tags)`**：`src` 必须在 `hit_sources` 里登记（校验）；伤害走 `area_hit / melee_hit`，自动吃 `vs_elite`、藏品倍率。
6. **数值改动走 `stats.add(..., "op:<id>")`**，来源名统一 `blk:<id>`，与手写干员同一套 op_api。

## 1. JSON 结构

### 1.1 干员 JSON 新增字段

```jsonc
{
 "id": "skalter",
 "faction": ["深海猎人"],          // 阵营（docs/60 §3 trig.squad_faction 配套）；手写干员也可以写，现有：skadi / ulpianus / specter_unchained
 "script": "res://scripts/characters/data_operator.gd",   // 可省（有 blocks 时缺省就是它）
 "base": { ... },                   // 全部数值
 "skills": [{"name", "sp", "dur"?, "permanent"?, "mode"?, "icon", "desc"}, ×3],   // 外壳字段照旧（§2）
 "blocks": {
  "zone":     {"center": "leader", "r": "$aura"},        // 可选：本干员的「区域」（歌域 / 光域），§3.1
  "attack":   { 攻击积木 },                               // 普攻，§3.2
  "trait":    [ 触发积木… ],                              // 特性：招募起常驻（精零），§4
  "skills":   [ 技能积木 ×3 ],                            // 与 skills[] 一一对应，§2
  "talent":   [ 触发积木… ],                              // 天赋：精英一起生效
  "progression": {"<custom 节点 id>": 积木, "elite2": 积木}   // 成长节点；elite1 / elite2 = 精英化当下附带的质变
 }
}
```

### 1.2 数值表达式

- 数字：`14`、`0.5`。
- 引用：`"$atk"` = `base.atk`。
- 一次运算：`"$a*$b"`、`"$a/2"`、`"1-$x"`、`"1+$x"`、`"-$x"`（只支持一个二元运算 `+ - * /` 或一个前置负号；不做表达式引擎）。
- 只有含 `$` 的字符串当表达式；`"src": "声浪"` 这类普通字符串原样保留。加载时一次解析成数字（`base` 运行中不变）。
- 校验：引用的 key 必须在 `base` 里；表达式写错报「干员 X 的 blocks.<路径> 表达式 …」。

### 1.3 条件 `cond`（docs/60 §3 的「条件」列）

任何积木都可以带 `"cond": "<条件>"`，条件不成立时这块积木本帧不生效（常驻类）/ 不触发（触发类）。前缀 `!` 取反。

| 条件 | 含义 | docs/60 |
|---|---|---|
| `lamp >= $x`（`> >= < <= ==`） | 灯火 | `trig.lamp_tier` |
| `hp_pct < $x` | 主控生命比例 | `trig.hp_below` |
| `elite >= 1` | 本干员精英阶段 | — |
| `faction:<阵营> >= 1` | 编队里**除自己以外**该阵营的人数 | `trig.squad_faction` |
| `class:<职业> >= 1` | 编队里除自己以外该职业的人数 | `trig.squad_class` |
| `skill_active:<i>` | 本干员技能 i（0 起）生效中 | `trig.skill_idle` 取反 |
| `in_zone:leader` | 主控在本干员区域内 | docs/59 `cond/in_aura` |
| `is_leader` | 本干员是主控 | `trig.leader` |

## 2. 外壳：技能的 `sp / dur / cast`（docs/60 §2.1–2.3）

外壳字段仍写在干员 JSON 的 `skills[i]`（HUD、充能、手动技能都读这里），`blocks.skills[i]` 只写「放出来做什么」：

```jsonc
"blocks": {"skills": [
  {"dur": "$s1_dur", "do": [ 效果积木… ]},     // dur.timed：持续 N 秒
  {"dur": "permanent", "do": [ … ]},          // dur.permanent：skills[i] 必须同时写 "permanent": true
  {"dur": 0, "do": [ … ]},                    // dur.instant：瞬发（缺省）
  {"dur": {"next_attacks": 3}, "attack_patch": {"mult": "$s1_mult"}, "do": [ … ]}   // dur.next_n：强化接下来 N 次普攻
]}
```

| 外壳 | 写法 | 状态 |
|---|---|---|
| `sp.auto` | `skills[i].sp` | ✅ 现状（character.gd `tick_sp`） |
| `sp.on_attack` / `sp.on_hurt` | `skills[i].sp_type: "attack" / "hurt"` | 📝 |
| `dur.instant / timed / permanent` | `blocks.skills[i].dur` | ✅ |
| `dur.next_n` | `{"next_attacks": N}` + `attack_patch` | 📝（13 人里最常见的 S1 写法，迁移现有干员时第一个补） |
| `dur.ammo` | `{"ammo": N}` | 📝 |
| `cast.auto` / `cast.manual` | `skills[i].mode`（`aim` 📝） | ✅（手动走 character.gd `cast_manual → start_skill`，数据干员无需另写） |
| `cast.passive` | `dur: "permanent"` + `skills[i].sp: 0` | 📝 |

时序（与手写干员相同）：充满 → `start_skill`（扣技力、播技能帧条、`permanent` 在这里置 `perm[i]`）→ 出手帧 `_release_skill`：
执行 `do` 里的**瞬时**积木一次，**常驻**积木从这一刻起生效到持续结束（`permanent` 永久）；生效期间不充能（`skill_active_left`）。
`dur.next_n`（📝）：`skill_pending(i)` 为真，`attack_patch` 叠到接下来 N 次普攻上，打完为止。

## 3. 形状 `shape.*`（每次出手打到谁）与区域

### 3.1 区域 `zone`（docs/59 `shape/aura` 的中心 + 半径；docs/60 `aura.* {r}`）

`{"center": "leader" | "self", "r": <数值>}`。半径 = `r × op_range × 本干员 zone 倍率`（§5.2）。`leader` 以 `g.ppos` 为中心（docs/59 §9 第 4 条，用户 10-11 定），
本干员是主控时就是她自己；图鉴演示（`g.demo_op`）以自己为中心。`scope: in_zone`、`cond: in_zone:leader`、`r: "zone"`、`center: "zone"` 都指它。区域由 `draw_auras` 画地面椭圆。

### 3.2 普攻 `blocks.attack`

普攻 = 一个形状积木 + 节奏字段：`every`（间隔秒，÷ `op_aspd`，× 本干员 `interval` 倍率）、`range`（索敌距离，缺省 = 形状半径）、`anim`（帧条，缺省 attack）。
没有目标（或手动普攻没按）时按 `idle_cd(0.2)` 重试；手动普攻（v2.5）：`circle` 不分方向只受闸门，`cone` 是 A 方向类（`atk_point / atk_angle`）。

### 3.3 形状表

公共参数（所有伤害形状）：`mult`（× `base[atk_key]`，`atk_key` 缺省 `"atk"`）、`src`（必须在 `hit_sources`）、`tags`（追加到命中描述符）、`kb`、`stun`（同 `melee_hit`：精英击退 ×0.3、眩晕 ×0.5，Boss 不受）、
`power`（true = 再乘 `skill_power()`）、`on_hit`（每个命中目标执行的 `st.*` 列表）。伤害 = `base[atk_key] × mult × 本干员 dmg 倍率 × _dmg_bonus() [× skill_power]`。

| 积木 | docs/59 §10 旧名 | 参数 | 实现 |
|---|---|---|---|
| `shape.circle` | `shape/ring`、`shape/aura`（脉冲） | `center: zone / self / leader / target`、`r`（数值或 `"zone"`） | ✅ `area_hit` |
| `shape.cone` | `shape/fan` | `r`、`half_deg`、`origin_off` 📝；朝最近目标 | ✅ `melee_hit` |
| `shape.orbit` | `shape/aura_edge_orbs` | `n`、`r`（`"zone"`）、`speed`（弧度 / 秒）、`hit_r`、`kb`、`cd`（同一敌人间隔）、`mult`（0 = 只推不伤） | ✅ 常驻：区域边缘绕行的 n 个判定点（地面椭圆 y × 0.55，与画面一致） |
| `shape.line` | `shape/line` | `len, width, pierce` | 📝（艾丽妮线段判定抽出后） |
| `shape.point_aoe` | `shape/land` | `r, land: nearest/densest/aim, travel` | 📝 |
| `shape.projectile` | `shape/bolt` | `speed, homing, pierce_n, shots, spread_deg` | 📝 |
| `shape.chain` | — | `jumps, falloff, jump_r` | 📝 |
| `shape.dash_line` / `shape.summon` | 同名 | docs/59 §10.1 | 📝 |

选目标 `target.*`（docs/60 §2.5）：第一版只有 `nearest`（缺省，含 Boss 优先，op_api `nearest_enemies`）；`elite / densest / low_hp / multi` 📝，写成形状的 `target` 参数。

## 4. 触发 `trig.*`（天赋 / 特性 / 成长节点挂在哪）

触发积木 = `{"trig": <名>, "cond"?, "do": [效果…]}`。`trait` 招募即生效；`talent` 精英一起生效；`progression.<id>` 选下节点起生效；`progression.elite2` 精英二起生效。
成长节点可以直接写一块效果积木（不带 `trig`），等同 `{"trig": "passive", "do": [它]}`。

| 积木 | docs/59 旧名 | 参数 | 实现 |
|---|---|---|---|
| `trig.passive` | `trig/lamp_band`、`trig/squad_has`（都改成 `cond`） | `cond` | ✅ 常驻：条件成立期间 `do` 里的常驻积木生效 |
| `trig.every_n` | `trig/on_hit {count_every}` | `n`、`delay`（秒） | ✅ 每第 n 次普攻出手，`delay` 秒后执行 `do` |
| `trig.tick` | `trig/tick` | `every`、`cond` | ✅ 条件成立时计时，满 `every` 秒执行一次（条件不成立时计时清零） |
| `trig.on_kill` | `trig/on_kill` | `filter: any / elite / boss` | ✅（`on_kill(e)` 分发；只算本干员的击杀不区分，同手写干员） |
| `trig.on_skill_start` | `trig/on_skill_start` | `skill`（0 起） | 📝 |
| `trig.on_hurt` | `trig/on_damage_taken` | `chance, min_pct, cd` | 📝（要 `dmg_taken_mult` 挂点） |
| `trig.on_leader_dash` / `trig.on_deploy` | 同名 | | 📝 |

## 5. 效果积木（放在 `do` 列表里）

**瞬时**积木在「执行」那一刻做一次（技能出手、触发器触发）；**常驻**积木在所在列表「生效期间」每帧作用（技能持续中 / 永久 / 天赋与节点的条件成立时）。下表「类」一栏标明。

### 5.1 动词 `verb.*`

| 积木 | docs/59 旧名 | 类 | 参数 | 实现 |
|---|---|---|---|---|
| `verb.heal` | `verb/heal` | 有 `every` 常驻 / 否则瞬时 | `pct`（× 主控最大生命）、`every`（秒）、`src`（治疗统计名，缺省干员名）、`power` | ✅ 主控满血时不治（不触发溢出藏品，同铃兰） |
| `verb.lamp` | `verb/lamp` | `add` 瞬时；`per_sec` / `loss_mult` 常驻 | `add`、`per_sec`（负数 = 消耗，docs/60 `cost.upkeep`）、`loss_mult`（受击灯火流失倍率 → 全局 `light_loss` mult） | ✅ |
| `verb.buff_self` | `verb/buff {who: self}` | 常驻 | `stat`、`op: add / mult`、`value`、`power`；`stat` 是 `op_atk / op_aspd / op_range / op_skill_power`（写进 `op:<id>`）或本干员局部倍率 `zone / dmg / heal / interval` | ✅ |
| `verb.mode` | `verb/mode` | 常驻 | `dmg_mult`、`zone_mult`、`interval_mult`、`no_attack`、`power`（只作用于 `dmg_mult`） | ✅（局部倍率的 mult 糖） |
| `verb.sp_team` | `verb/sp` | 瞬时 | `pct`、`exclude_self`（缺省 true） | ✅ `g.squad.gain_sp` |
| `verb.field` / `verb.summon` / `verb.shield` / `verb.protect` / `verb.displace` / `verb.cleanse` / `verb.dash` | 同名 / `verb/negate*` / `ctrl/pull` | — | docs/60 §8 第 22–27 条 | 📝 |

局部倍率（§5.2）：`(1 + Σ add) × Π mult`，按积木顺序累计；`zone` 乘区域半径，`dmg` 乘本干员所有形状的伤害，`heal` 乘本干员所有治疗，`interval` 乘普攻间隔。

### 5.2 光环 `aura.*`（docs/60 第 28 条；docs/59 `verb/buff {who: …}`）

`{"aura": "atk" | "aspd" | "skill_power" | "range", "value", "scope", "per"?, "cap"?, "power"?}` 常驻。写进 `op_<stat>`（add），每名受益干员各一条、作用域 `op:<受益者 id>`。

| `scope` | 受益者 |
|---|---|
| `squad` | 编队全体（含自己） |
| `others` | 除自己以外 |
| `in_zone` | 站在本干员区域内的干员（含自己、主控） |
| `leader` | 主控干员 |
| `faction:<阵营>` | 该阵营的干员（含自己，若自己也是） |

`per: "faction:<阵营>"`：数值 × 编队里除自己以外该阵营人数（`cap` 封顶，0 人时不生效）。`aura.heal / aura.dps / aura.dr` 用 `verb.heal` / 📝。

### 5.3 状态 `st.*`（docs/60 §2.8；docs/59 `ctrl/*`）

| 积木 | 类 | 参数 | 实现 |
|---|---|---|---|
| `st.stun` | 瞬时（命中时） | `dur`（精英 ×0.5，Boss 不受） | ✅ |
| `st.slow` | 瞬时（命中时） | `dur`（减速状态，敌人 `slow` 计时） | ✅ |
| `st.fragile` | 瞬时（命中时） | `value`（敌人 `aura_weak`，同名取最高） | 📝 |
| `st.slow_soft` | 常驻 | `pct`、`scope: in_zone`、`boss`（缺省 false） | ✅ 新：不是减速状态、不与 `st.slow` 叠——每帧把区域内非 Boss 敌人这一帧的位移退回 `pct`（含被击退的位移）。docs/59 §1 天赋「移速 -10%」 |
| `st.airborne` / `st.bind` / `st.weightless` / `st.dot` / `st.mark` | | docs/60 第 29–31 条 | 📝 |

### 5.4 修饰 `mod.*`、代价 `cost.*`

- `mod.dmg_type` = `hit_sources.<src>.kind`（JSON 已有）；`mod.kb` = 形状的 `kb`；`mod.multi_hit / burst / splash / cond_dmg / lifesteal / execute` 📝。
- `cost.upkeep`（灯火）= `verb.lamp {per_sec < 0}` ✅；`cost.hp_drain` 📝。

### 5.5 属性修正怎么落地（确定性）

每帧（`update` 开头）按固定顺序收集所有**生效中**的常驻积木：`trait` → 技能 0 / 1 / 2 → `talent`（精一起）→ 已选成长节点（按选下顺序）→ `elite2`；
每块积木内部按 `do` 的书写顺序。得到「局部倍率」和一组 `stats` 修正 `[stat, op, value, scope]`；与上一帧那组完全相同就什么都不做，
否则 `remove_source("blk:<id>")` 后按顺序整组重加、`refresh_stats()`。所以：同一份 JSON 每次的修正顺序相同，浮点结果可复现；手写参照（tests/data_ops/eqtest_hand.gd）照同一顺序加，结果逐字节一致。

## 6. 逃生口 `custom`

`{"custom": "<函数名>", ...}` 放在任何 `do` 列表里，瞬时执行：干员脚本（继承 data_operator.gd 的小脚本）有这个函数就调 `fn(block)`，没有就第一次 `push_warning` 后忽略。
规则（docs/59 §10.1）：每名干员 ≤ 2 个；只做画面和「积木表达不了的时序」，**不许做数值**；外部（玩家自制）干员一律忽略（📝 `modded` 标记）。浊心斯卡蒂 0 个。

## 7. 与 character.gd / op_api 的挂接（事件与询问）

data_operator.gd 重写这些基类钩子，把事件分发给积木（「游戏 → 干员」方向）：

| 钩子 | 做什么 |
|---|---|
| `_init` | 读 `blocks`，表达式解析成数字、条件解析成元组（§1.2 / §1.3） |
| `update(dt)` | 技能计时 → 延迟队列（`every_n delay`）→ 常驻积木（属性重建、`verb.heal every`、`verb.lamp per_sec`、`trig.tick`、`st.slow_soft`、`shape.orbit`）→ `charge_skills` 起手 → 普攻起手 |
| `_release()` | 执行普攻形状，然后 `trig.every_n` 计数 |
| `_release_skill()` | 执行 `blocks.skills[cur_skill]`：开计时 / 永久、瞬时积木 |
| `skill_active_left / skill_active_dur` | 来自技能计时 |
| `on_kill(e)` | `trig.on_kill`（`center: target` 的形状落在被击杀的敌人处） |
| `on_custom_node(id)` / `on_elite(stage)` | 记下已选节点（`nodes_taken`，字符串，成长节点测试能看到「当场有变化」） |
| `_swing_radius()` | 普攻形状半径（机器人走位用） |
| `draw_auras()` | 区域椭圆（灯火 ≥70 / <30 / 其他三种色）+ `shape.orbit` 判定点 |

调用 op_api 的「干员 → 游戏」方向只用：`nearest_enemies / query_ids / area_hit / melee_hit / log_hit / heal_leader / refresh_stats / atk_point / atk_angle / attack_gate / idle_cd / fx / float_text`，
读写公共状态 `g.ppos / g.enemies / g.stats / g.lamp / g.lamp_cap / g.hp / g.max_hp / g.squad.ops / g.t`。不调任何 `g._xxx`，不碰 `enemies.gd / combat.gd`。
音效：技能发动音由 `spend_sp` 统一播（`op_<id>_s1..3`），普攻 `op_<id>_atk`；缺专属文件时走 `sfx.gd OP_ALT` 借用现有音（docs/28），数据干员不需要新音频文件。

## 8. 校验 `validate_operator`（`tools/check.py` 核心契约测试里对每个干员跑）

`Character.validate_operator(cid, def)` 在原契约之外，`def.blocks` 存在时调 `OpBlocks.validate(cid, def)`，每条错误 `push_error` 一行，**写明干员与字段路径**，例如
`干员 skalter 的 blocks.skills[2].do[3]：不认识的积木「verb.lamb」`。规则：

1. `blocks.attack` 是一个伤害形状；`blocks.skills` 恰好 3 条，与 `skills` 一一对应；`dur: "permanent"` ⇔ `skills[i].permanent: true`。
2. 每块积木恰好有一个族键（`shape / verb / aura / st / trig / custom`），`族.名` 在本文 ✅ 表里（📝 的写了也报错：「已登记未实现」）。
3. 必填参数齐全（如 `verb.heal.pct`、`aura.scope`、`trig.every_n.n`）；`scope / center / op / stat` 取值在表内。
4. 所有 `$key` 在 `base` 里；表达式只有一个运算。
5. 所有伤害形状的 `src` 在 `hit_sources` 里。
6. `cond` 能解析；`progression` 的键是 custom 节点 id 或 `elite1 / elite2`；每个 custom 节点都有积木。
7. `custom` ≤ 2 个。
8. 夹紧（创意工坊 📝）：`mult ≤ 20`、`every ≥ 0.1`、`orbit.n ≤ 12`——防止数据把局打崩。

## 9. 名字对照（docs/59 §10 → docs/60 → 本文）

| docs/59 §10 | docs/60 | 本文 |
|---|---|---|
| `shape/fan` | `shape.cone` | `shape.cone` |
| `shape/ring` | `shape.circle_self` | `shape.circle`（`center` 可选，不止自身） |
| `shape/aura`（脉冲 / 光域） | `shape.circle_self` + `aura.* {r}` | `zone` + `shape.circle {center: zone}` |
| `shape/aura_edge_orbs` | — | `shape.orbit` |
| `shape/line` / `shape/land` / `shape/bolt` | `shape.line` / `shape.point_aoe` / `shape.projectile` | 同 docs/60（📝） |
| `verb/damage` | （形状的默认效果） | 形状自带 `mult / src / tags` |
| `verb/buff {who: self}` | `verb.buff_self` | `verb.buff_self` |
| `verb/buff {who: squad / in_aura / ids}` | `aura.atk / aura.aspd / aura.inspire` | `aura.<stat> {scope}`；`ids:[…]` 改为 `faction:<阵营>` |
| `verb/heal` | `verb.heal` | `verb.heal` |
| `verb/lamp` | `verb.lamp` + `cost.upkeep` | `verb.lamp {add / per_sec / loss_mult}` |
| `verb/sp` | `verb.sp_team` | `verb.sp_team` |
| `verb/mode` | `verb.mode` | `verb.mode` |
| `verb/ammo` | `dur.ammo` / `dur.next_n` | 外壳 `dur`（§2） |
| `ctrl/stun` / `ctrl/slow` / `ctrl/levitate` | `st.stun` / `st.slow` / `st.airborne` | `st.*` |
| `ctrl/slow_soft` | — | `st.slow_soft` |
| `ctrl/knockback` / `ctrl/pull` | `mod.kb` / `verb.displace` | 形状 `kb` / 📝 |
| `trig/on_hit {count_every}` | `trig.every_n` | `trig.every_n` |
| `trig/lamp_band` | `trig.lamp_tier`（条件） | `trig.passive {cond: "lamp >= …"}` |
| `trig/squad_has {ids}` | `trig.squad_faction` | `cond: faction:<阵营>` / `aura {per}` |
| `trig/tick` / `trig/on_kill` / `trig/on_skill_start` | 同名 | 同名 |
| `cond/in_aura` | — | `cond: in_zone:leader` / `scope: in_zone` |
| `mod/per_stack` | `trig.stack` | 📝 |
| 节点 `patch` | — | 📝（第一版节点直接写积木） |
| `"nodes": {"e2": …}` | — | `"progression": {"elite2": …}` |
| `"custom": "<func>"` | — | 同（§6） |

## 10. 浊心斯卡蒂的表达（docs/59 §1 + §8.1，歌域以主控为中心）

见 `data/characters/skalter.json` 的 `blocks`：0 个 `custom`。与 docs/59 的差异（§测试 末尾「设计偏差」）。

## 测试

### 等价测试（`python tools/check.py --only blocks_eq`，快检全量里也跑）

`game/tests/data_ops/eqtest.json`（测试专用干员，不在 `data/characters/`，不进名单 / 招募池 / 图鉴）用 §3–§5 里实现的大部分积木；
`game/tests/data_ops/eqtest_hand.gd` 是同一份数值的**手写参照**（按 13 人的写法：`base()` 取数、`update` 里自己计时）。
`--opscript=eqtest=res://tests/data_ops/eqtest_hand.gd` 让同一个 id 改用手写脚本加载。两种加载各跑 2 局，要求 `TRACE` 行与 `BALANCE`（去掉 `prof` 与画面峰值）逐字节相同：

- seed 1：`--maxprog --sptest`（开局全部节点 + 技力常满，覆盖全部技能与节点积木），4:00；
- seed 2：自然流程（机器人选卡、精英化按实际时机），5:00。

### 强度（docs/59 §7 / docs/38 §8.12：每档参考机器人含超时 50–70%）

本机冒烟（12 局）见本节末尾的记录。云端 112 局批（协调人建例行任务；`--seeds` 起点 1，结果缓存照常）：

```bash
# 主控（单人开局，招募照常）
python tools/balance_run.py --op skalter --bot expert  --seeds 112 --extra="--tier=0" --tag skalter_lead_t0
python tools/balance_run.py --op skalter --bot master  --seeds 112 --extra="--tier=1" --tag skalter_lead_t1
python tools/balance_run.py --op skalter --bot master  --seeds 112 --extra="--tier=2" --tag skalter_lead_t2
# 队友（7 名开局干员 × 16 seed = 112 局，开局就把浊心斯卡蒂编进队）
python tools/balance_run.py --preset skalter_mate --bot expert --seeds 16 --extra="--tier=0" --tag skalter_mate_t0
python tools/balance_run.py --preset skalter_mate --bot master --seeds 16 --extra="--tier=1" --tag skalter_mate_t1
python tools/balance_run.py --preset skalter_mate --bot master --seeds 16 --extra="--tier=2" --tag skalter_mate_t2
```

对照：同参数把 `skalter` 换成 `suzuran`（docs/59 §7「单人对照 铃兰」，同角色相差 ≤ 15 个百分点）。偏弱先动 `aura`（190 → 210）再动 `atk`；偏强先收 `s3_atk`、`s3_mult`。
