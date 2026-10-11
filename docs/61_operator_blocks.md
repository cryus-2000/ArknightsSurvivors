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
`power`（true = 再乘 `skill_power()`）、`on_hit`（每个命中目标执行的 `st.*` 列表）、
`max_n`（`circle` / `cone`：最多打几个，1–99，缺省不设上限；10-11 为浊心斯卡蒂辅助向加，docs/60 §2.5 的 `max_n`。取舍走 character.gd `cap_targets`：Boss → 精英 → 其余，同档离圆心 / 原点近的先、再按敌人 id，确定性；
`melee_hit / area_hit` 末尾多了可选参数 `max_n`，缺省 0 = 原行为，老干员逐字节不变）。伤害 = `base[atk_key] × mult × 本干员 dmg 倍率 × _dmg_bonus() [× skill_power]`。

| 积木 | docs/59 §10 旧名 | 参数 | 实现 |
|---|---|---|---|
| `shape.circle` | `shape/ring`、`shape/aura`（脉冲） | `center: zone / self / leader / target`、`r`（数值或 `"zone"`）、`max_n?` | ✅ `area_hit` |
| `shape.cone` | `shape/fan` | `r`、`half_deg`、`max_n?`、`origin_off` 📝；朝最近目标 | ✅ `melee_hit` |
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

见 `data/characters/skalter.json` 的 `blocks`：0 个 `custom`，没有 `skalter.gd`。基础数值起步照 docs/59 §8.1；**10-11 用户定「改成辅助向」**，现行数值见偏差第 12 条（取代第 11 条的伤害型数值）。

接入登记（docs/27 §9.2）：`balance.json operators.skalter`（A+，skill_power +0.02）、`lore.json`、`tools/balance_run.py OPS` 与预设 `skalter_mate`、
技能图标 `skill_skalter_s1..3`（main ca52b04c 的正式图；起初的 `make_skill_icons.py` 占位画法合入 main 时撤掉）、音效 `sfx.gd OP_ALT` 借用（普攻 ← 铃兰普攻低音，S1 ← 流明 S1，S2 ← 铃兰 S2，S3 ← 凯尔希 S3）。
选人页 / 图鉴 / 招募池都按 `data/characters/*.json` 自动列入（基础池，不走战绩解锁）。
**美术**：起初 `art.gd PLACEHOLDER` 借 `op_skadi_*` 帧条改「浊心红」当占位；10-11 Codex 正式帧条 `art/incoming/op_skalter_*` 验收合入（docs/64），已按 docs/64 §5.1 切过来：删 PLACEHOLDER 条目（字典留空备用）与 `sprites._placeholder`，`idle.foot` [22, 46] → [24, 46]、`attack.fps` 14 → 12、`skill.fire` 4 → 3。攻击 / 技能帧条的 fps 与 fire 决定出手时刻（character.gd `start_attack`：`fire_at = (fire + 0.5) / fps`）：普攻出手 0.18 → 0.21 秒、技能 0.38 → 0.29 秒，间隔不变（`every / op_aspd`）。

**与 docs/59 的差异（设计偏差）**

1. **名字**（协调人 10-11，按 PRTS / wiki.gg 核对，docs/63 §6）：S1「吟游」→「同归殊途之吟」、S2「深海的呼唤」→「同葬无光之愿」、S3「死地之歌」→「潮涌，潮枯」、天赋「溟海颂歌」→「捕食习性」。机制不变。
2. S3 没有单独的伤害来源（docs/59 §8.1 的 `hit_sources.死地之歌` 删掉）：S3 只是把「声浪」×3，伤害记在「声浪」名下。
3. 成长节点 1 / 2 写成 custom 节点 + `verb.buff_self`（歌域 ×1.15 / 声浪 ×1.15，docs/59 §8.1 注释里说的「照抄现有干员的前两节点」）；节点 2 图标用 `growth_b_size`（没有 `growth_b_atk`）。
4. 天赋昏暗「歌域内敌人移速 -10%」= `st.slow_soft`：每帧把区域内非 Boss 敌人这一帧的位移退回 10%（含被击退的位移），不写 `slow`、不与铃兰叠。
5. 天赋深海猎人加成数的是**除她以外**的深海猎人（她自己 JSON 也写了 `faction: 深海猎人`，否则单人开局就白拿 +4%）；受益者 = 歌域内全部干员（含她自己与主控）。
6. S2 歌域内攻速 +15% 也作用于她自己（她站在歌域里），所以 S2 后声浪间隔变短；S2 的深海猎人 +15% 攻击不看是否在歌域内（docs/59 写的是「编队里的深海猎人」）。
7. 「潮汐和声」回声延迟 0.25 秒（docs/59 没写，免得与本次声浪同帧叠在一起看不出来）。
8. 精二「溟海之声」：6 个音符沿歌域边缘（地面椭圆）绕行，0.8 弧度 / 秒，判定半径 18；只推不伤（`mult: 0`），同一敌人 0.5 秒一次，精英击退 ×0.3，Boss 不受。
9. 主控满血时不治疗（不触发「溢出治疗」类藏品，同铃兰）；S1 / S3 的回复、S2 / S3 的光环、S3 的 ×3 和「深海的回响」都乘技能强度（排异 +40% 会生效）。
10. 档案（lore.json）里「歌声总是绕着博士」改成绕着走在最前面的人（歌域以主控为中心）。
11. **数值先收一档**：docs/59 的 `atk 14`、`s3_mult 3.0` 本机 12 局标准高手 12 / 12 通关、她占全队伤害 78%——声浪打歌域内**全部**敌人，半径 190 起步还会被 S2 / 天赋 / 节点 / S3 叠到 400 以上，
    「单体 14 · 群体不设上限」在大群里就是全场最高输出。改为 `atk 6`、`s3_mult 2.0` 后 8 / 12（67%，见 §测试）。云端 56 局 × 6 批（§测试「强度测试结果」）三档主控 73 / 70 / 48%、合计 64%，胜率在区间内；
    但当队友时她拿全队 42–74% 的伤害、开局干员占比被压低 10–20 个百分点——「辅助」实际是主输出。
12. **辅助向（用户 10-11「改成辅助向」，取代第 11 条）**：她当队友时伤害占比目标 20–30%，开局干员占比回到不带她的水平；她给的胜率提升主要来自歌域里的增益，不来自她自己的声浪。原作对应：浊心斯卡蒂是给友军加攻击 + 持续回复的吟游者，S3 自损换全队大幅攻击。
    - 声浪 `atk 6`，`max_n 16`（`wave_n`，打圈内最近 16 个，Boss / 精英优先）；「潮汐和声」「深海的回响」也只打 16 个。（第一版 atk 5 / 12 个，云端后上调，见 §测试「辅助向云端结果」）S3 不再放大声浪（删 `s3_mult`，`verb.mode` 只留 `zone_mult`）。
    - **领唱**（新，特性）：她自己当主控时，每次声浪再放一圈**不设上限**的声浪（`trig.every_n n 1` + `cond is_leader`，`lead_mult 0.5`，同记「声浪」；第一版 1.2 主控偏强）——单人开局在招到人之前不能只剩 12 个目标的输出。当队友时没有这一圈。
    - 增益（受益者 = 歌域内干员，含她自己与主控；`scope in_zone`）：特性「歌声」攻击 +15%（`song_atk`，新）；S1 加攻速 +25%（`s1_aspd`，新，乘技能强度）；S2 攻击 +15%（`s2_atk`，新）+ 攻速 +15%（不变），深海猎人 0.15 → 0.25；
      S3 全队攻击 0.5 → 1.0，昏暗时不再「声浪 ×1.5」，改为全队攻击再 +30%（`s3_dark_atk`）；天赋昏暗「声浪 +50%」改为歌域内攻击 +10%（`dark_atk`）；深海猎人每人 0.04 → 0.08（最多 3 人）；节点 2「潮声渐强」从「声浪 ×1.15」改为歌域内攻击 +10%（`aura.atk`）。
    - 灯火代价不变：S3 灯火每秒 -2，昏暗时不扣；S1 受击灯火流失减半不变。治疗数值不变。

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

本机冒烟（10-11，标准 `--tier=0`，高手，单人开局自然招募，seed 1–12，含超时口径）：

| 版本 | 通关 | 超时 | 死亡 | 平均存活 | 平均击杀 | 平均等级 | 她占全队伤害 | 脚本错误 |
|---|---|---|---|---|---|---|---|---|
| docs/59 原值（atk 14、s3_mult 3.0） | 12 / 12 | 0 | 0 | 11:04 | 7133 | 28.8 | 78% | 0 |
| **现值（atk 6、s3_mult 2.0）** | **8 / 12（67%）** | 0 | 4 | 11:20 | 7080 | 27.5 | 64% | 0 |
| 对照 铃兰（同参数） | 6 / 12（50%） | 0 | 6 | 10:35 | 5436 | 24.8 | — | 0 |

（「她占全队伤害」是单人开局的主控占比，不是 docs/59 §7 的 `--preset share` 口径。）

对照：同参数把 `skalter` 换成 `suzuran`（docs/59 §7「单人对照 铃兰」，同角色相差 ≤ 15 个百分点）。偏弱先动 `aura`（190 → 210）再动 `atk`；偏强先收 `s3_atk`、`s3_mult`。

### 强度测试结果（云端 10-11，wip/skalter db36917 = 伤害型 atk 6、s3_mult 2.0；已被辅助向取代，见下一节）

结果分支 `cloud-results/sk-lead-t0/t1/t2`、`sk-mate-t0/t1/t2`（`build/cloud/<名>/`）。实际跑的是 §测试 命令的一半：主控 seed 1–56、队友 seed 1–8（各 56 局，`--maxt=1000`）。口径：超时算负；死亡分钟只数死亡局；「她的伤害占比」= 声浪 + 潮汐和声 + 深海的回响 占全队 `out`（S3 的 ×2 记在声浪名下）。

**对照选哪批**：wip/skalter 底在 main 71c078d5，它 = 6a3c857 + 灯标「引路 + 背光」缺省开（a9ce313b，标准高手 28 局 57.1%）+ 两条画面改动。
最可比的是 `rp-t0-np1`（标准 · 高手 · starts · seed 1–8）与 `rp-x-np1-1/2`（Ⅷ · 熟练 · starts · seed 1–16），底 6a3c857：262 件藏品已在，只差灯标引路。
`bg8-D-1/2`（底 269d066，`--bal` 开了同样的引路参数）是藏品实装**之前**的底，只作旁证（Ⅷ 61 / 112 = 54%，与 rp 的 50% 差在噪声内）。
Ⅳ 没有近期的 starts 批，只有 `close8-master-t1-1/2`（底 f633172，9 月底，73 / 112 = 65%），差了藏品与灯标两轮，**只能看量级**。
starts 预设与她的主控局同口径（单人开局、自然招募）；skalter_mate 是「开局干员 + 她」两人开局再招 1 人，对照是同一开局干员的 starts 局（两人随机招募），所以队友差值 = 「她」对比「一名随机招募」。

**主控（单人开局，56 局）**

| 组 | 胜 | 胜率 | 超时 | 死亡分钟（<6 / 6–7 / 8–9 / 10+） | 平均击杀 | 平均终局等级 | 她占全队伤害 | 前四伤害来源 | 主要死因 | 同档名单对照 |
|---|---|---|---|---|---|---|---|---|---|---|
| 标准 · 高手 | 41 / 56 | **73%** | 0 | 0 / 7 / 3 / 5 | 7138 | 27.4 | 61% | 声浪 46%、潮汐和声 7%、深海的回响 6%、锯刃 3% | wound 9、corrode 3 | rp-t0-np1 7 人 31 / 56 = 55%（37 / 37 / 37 / 88 / 88 / 75 / 25）；她 seed 1–8 为 6 / 8 |
| Ⅳ · 熟练 | 39 / 56 | **70%** | 1 | 2 / 6 / 7 / 1 | 7003 | 26.9 | 63% | 声浪 47%、潮汐和声 8%、深海的回响 6%、Mon3tr 2% | wound 12、corrode 2 | close8-master-t1（旧底）65%；她 seed 1–8 为 8 / 8 |
| Ⅷ · 熟练 | 27 / 56 | **48%** | 1 | 7 / 11 / 8 / 2 | 6546 | 25.2 | 65% | 声浪 49%、潮汐和声 8%、深海的回响 6%、Mon3tr 4% | wound 12、corrode 6、contact_slider 4 | rp-x-np1 7 人 56 / 112 = 50%（斯卡蒂 88、水月 63、塞雷娅 63、凯尔希 56、维什戴尔 44、艾雅法拉 25、铃兰 12）；她 seed 1–16 为 8 / 16 |

- 输出：主控每分钟伤害 63k / 70k / 71k，名单里最高的是维什戴尔 / 水月（Ⅷ 53–59k）；她占全队 61–65%，与维什戴尔（60%）、艾雅法拉（54–59%）同一档，不是独大。
- 中期 Boss：标准 2.4 只 / 41 秒、Ⅷ 2.0 只 / 63 秒（名单 Ⅷ 48–96 秒）；熄灯秒 7 / 9 / 35（名单 Ⅷ 22–98），S3 扣灯火没有把她推进黑暗。
- 档间落差：标准 → Ⅷ 掉 25 个百分点，名单平均只掉 5。她强在清大群，Ⅷ 的血量 / 侵蚀压力下回到名单中位（Ⅷ 死在 8 分钟前的 18 局，标准只有 7 局）。

**队友（7 名开局干员各带她开局，seed 1–8，每格 8 局）**

| 开局干员 | 标准：对照 → 带她（差） | 她占全队 | 开局干员占比 对照 → 带她 | Ⅳ：旧底对照 → 带她 | Ⅷ：对照 → 带她（差） | 她占全队 |
|---|---|---|---|---|---|---|
| 维什戴尔 | 3 → 3（0） | 51% | 49% → 31% | 6 → 5 | 3 → 1（−25） | 42% |
| 艾雅法拉 | 3 → 3（0） | 54% | 49% → 28% | 2 → 3 | 2 → 1（−12） | 44% |
| 斯卡蒂 | 3 → 7（+50） | 60% | 29% → 22% | 7 → 8 | 7 → 7（0） | 55% |
| 水月 | 7 → 6（−12） | 45% | 46% → 28% | 8 → 8 | 4 → 7（+38） | 54% |
| 塞雷娅 | 7 → 7（0） | 61% | 10% → 10% | 6 → 6 | 4 → 6（+25） | 57% |
| 凯尔希 | 6 → 7（+12） | 58% | 32% → 22% | 5 → 8 | 7 → 8（+12） | 57% |
| 铃兰 | 2 → 6（+50） | 74% | 27% → 12% | 5 → 3 | 1 → 3（+25） | 63% |
| **合计** | **31 → 39（55% → 70%）** | — | — | **39 → 41（70% → 73%）** | **28 → 33（50% → 59%）** | — |

- 带她平均 +15 / +3 / +9 个百分点；不是「谁带她都稳赢」：Ⅷ 维什戴尔 / 艾雅法拉带她 1 / 8，铃兰 3 / 8。每格 8 局，单格 ±25 都在噪声里，只看合计。
- 当队友时她仍拿全队 42–74% 的伤害，开局干员占比被压低 10–20 个百分点（歌域以主控为中心、打圈内全部敌人，抢走了主控的击杀）。这是设计取向问题（「辅助」却是主输出），不是胜率问题，留给制作人判断；要压可以给 `shape.circle` 加 `max_n`（docs/60 已登记），不动胜率口径。

**定档结论（伤害型）：胜率在区间内、数值不改（atk 6、s3_mult 2.0）；之后用户按队友伤害占比定「改成辅助向」，见下一节。**

1. 三档主控 73 / 70 / 48，合计 107 / 168 = 64%，在 50–70 内。标准超上沿 3 点、Ⅷ 低下沿 2 点，方向相反；56 局的标准误约 ±6 个百分点，两档都在一个标准误以内。她的旋钮不分档，任何统一收紧都会把 Ⅷ 压到 45% 以下。
2. 对名单：标准档 8 人里排第 4（水月、塞雷娅 88，凯尔希 75），Ⅷ 在中位（50% 对名单 50%），既不是最强也不是摆设。
3. 队友：抬队伍 +9 到 +15 个百分点，Ⅷ 带她合计 59%，在区间内。

**补测（把 §测试 原计划的 112 局补齐，同时拿同底的名单对照）**，在 wip/skalter-tune 上跑（数值同 db36917，结果可与上表合并）：

```bash
# 主控补 seed 57–112
python tools/balance_run.py --game game --jobs 4 --op skalter --bot expert --seeds 56 --seed0 57 --out build/cloud/sk-lead-t0-2 --tag sk-lead-t0-2 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 57 --out build/cloud/sk-lead-t1-2 --tag sk-lead-t1-2 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 57 --out build/cloud/sk-lead-t2-2 --tag sk-lead-t2-2 --extra="--maxt=1000 --tier=2"
# 队友补 seed 9–16
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot expert --seeds 8 --seed0 9 --out build/cloud/sk-mate-t0-2 --tag sk-mate-t0-2 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 9 --out build/cloud/sk-mate-t1-2 --tag sk-mate-t1-2 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 9 --out build/cloud/sk-mate-t2-2 --tag sk-mate-t2-2 --extra="--maxt=1000 --tier=2"
# 同底名单对照（starts，seed 1–16；Ⅳ 目前没有近期对照）
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 16 --seed0 1 --out build/cloud/sk-base-t0 --tag sk-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 16 --seed0 1 --out build/cloud/sk-base-t1 --tag sk-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 16 --seed0 1 --out build/cloud/sk-base-t2 --tag sk-base-t2 --extra="--maxt=1000 --tier=2"
```

事先定好的判定（112 局合并后）：标准 ≥ 75% 且 Ⅷ ≥ 50% → `aura` 190 → 180；Ⅷ < 45% 且标准 ≤ 70% → `aura` 190 → 200；其余不动。
（同底名单对照里招募池已含她，starts 局可能招到她，这才是 main 合入后的真实名单强度。）

### 辅助向冒烟（10-11，用户「改成辅助向」后；docs/61 §10 第 12 条）

上面「强度测试结果」测的是伤害型（db36917），已被取代。本机冒烟在合入 main 29082e52 之后的 skalter-tune 上跑（`--maxt=1000`，含超时口径；「她占全队」= 声浪 + 潮汐和声 + 深海的回响 占全队 `out`）：

| 版本 | 主控 标准·高手 seed 1–12 | 主控 Ⅷ·熟练 seed 1–12 | 队友 标准·高手 seed 1–3（21 局） | 她占全队（主控 / 队友） | 开局干员占比（队友局） |
|---|---|---|---|---|---|
| 伤害型 db36917（云端同 seed 子集） | 10 / 12 | 8 / 12 | 17 / 21 | 61–65% / 42–74%（均 ≈ 55%） | — |
| 辅助向第一稿（atk 4、max_n 6、领唱 ×1.0、歌声 +8%、S2 攻 +10%，seed 1–2 共 14 局） | 7 / 12 | 4 / 12 | 6 / 14 | 43–47% / 8% | 58% |
| **辅助向现值**（atk 5、max_n 12、领唱 ×1.2、歌声 +12%、S1 攻速 +25%、S2 攻 +15%、节点 2 +10%） | **7 / 12（58%）** | **9 / 12（75%）** | **17 / 21（81%）** | **55–57% / 18.6%**（各队 12–24%） | **47%** |
| 对照 rp-t0-np1（不带她，底 6a3c857，seed 1–3） | — | — | 13 / 21（62%） | — | 36% |

- 队友：她的占比从约 55% 降到 19%，开局干员占比从「被压 10–20 点」变成比不带她还高（47% 对 36%）；队伍胜率与伤害型同 seed 持平（17 / 21），提升改由歌域增益给出。占比略低于 20–30 目标的下沿，云端确认后可把 `wave_n` 12 → 14 或 `atk` 5 → 5.5 往上推一点。
- 主控：单人开局她仍是主输出（领唱圈不设上限），标准 7 / 12、Ⅷ 9 / 12，12 局的标准误约 ±14 点，方向上没有掉出 50–70。第一稿（无领唱加成、只打 6 个）Ⅷ 4 / 12，说明单人开局靠的就是领唱这一圈。
- 合入 main 后的快检全量通过；`blocks_eq` 里 eqtest 的回声加了 `max_n 5`，数据版与手写参照逐字节相同；核心契约测试加了 `cap_targets` 取舍顺序与「`max_n` 超出范围」校验两条。

**云端整轮（skalter-tune 当前提交；同一提交的 starts 对照，队友差值在同一个底上算）**：

```bash
# 主控：56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op skalter --bot expert --seeds 56 --seed0 1 --out build/cloud/sks-lead-t0 --tag sks-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sks-lead-t1 --tag sks-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sks-lead-t2 --tag sks-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友：7 名开局干员 × seed 1–8 = 56 局 × 三档
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/sks-mate-t0 --tag sks-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 1 --out build/cloud/sks-mate-t1 --tag sks-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 1 --out build/cloud/sks-mate-t2 --tag sks-mate-t2 --extra="--maxt=1000 --tier=2"
# 同提交对照：starts（7 名开局干员单人开局、自然招募）× seed 1–8 = 56 局 × 三档
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 8 --seed0 1 --out build/cloud/sks-base-t0 --tag sks-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/sks-base-t1 --tag sks-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/sks-base-t2 --tag sks-base-t2 --extra="--maxt=1000 --tier=2"
```

判定：主控三档各 50–70；队友局她占全队 20–30%、开局干员占比不低于同提交 starts；队友合计胜率比同提交 starts 高、但不超过 70 太多（每格 8 局只看合计）。
旋钮：她占比偏低 → `wave_n` / `atk`；队伍提升偏大 → `s3_atk`（0.8）、`song_atk`（0.12）；单人主控偏弱 → `lead_mult`（1.2），偏强同理往回收（只影响主控局，不动队友口径）。

### 辅助向云端结果（10-11，`sks-*` 九批，底 70843079：atk 5、max_n 12、领唱 1.2）

口径同上：超时算负；对照 = 同一提交的 starts（seed 1–8），队友差值在同一个底上算。

| 档 | 主控（56 局） | 同提交 starts 对照 | 队友 合计（56 局） | 她占全队（队友局） | 开局干员占比 带她 / 不带 | 判定 |
|---|---|---|---|---|---|---|
| 标准·高手 | **44 / 56 = 79%**（死亡 1 / 3 / 5 / 2：<6 / 6–7 / 8–9 / 10+；击杀 6792；等级 26.9；她占 55%） | 41 / 56 = 73% | 36 / 56 = 64%（−9） | 16.7% | 42.6% / 38.4% | 主控超上沿；队友占比低、队伍不升反降 |
| Ⅳ·熟练 | **49 / 56 = 88%**（0 / 3 / 3 / 1；7289；27.6；53%） | 39 / 56 = 70% | 37 / 56 = 66%（−4） | 15.7% | 44.5% / 35.5% | 主控明显超；同上 |
| Ⅷ·熟练 | **33 / 56 = 59%**（3 / 12 / 7 / 0；6520；25.5；57%） | **28 / 56 = 50%** | 34 / 56 = 61%（+11） | 13.2% | 44.7% / 37.9% | 主控、队友都在区间 |

- 主控局她占全队 53–57%（几乎全是「声浪」，含领唱圈），队友局只占 13–17%：辅助向的结构成立，开局干员占比在三档都高于同提交 starts（只有艾雅法拉标准档 55% 对 58% 略低）。
- 队友局按开局干员看（8 局一格，只作参考）：标准 凯尔希 4 → 8、铃兰 6 → 1；Ⅳ 斯卡蒂 7 → 4；Ⅷ 维什戴尔 / 艾雅法拉 / 塞雷娅 / 铃兰各 +2。铃兰 + 她（两名辅助、只剩 1 个招募位）在标准 / Ⅳ 最差。
- **Ⅷ 基线**（docs/56 §9 的担心：585aa4bc 上 Ⅷ 熟练缺省 44.6%）：同提交 `sks-base-t2` 28 / 56 = **50%**，在区间下沿；标准 73%、Ⅳ 70% 在上沿或略超。

**调数（e267737b）**：主控偏强靠领唱，队友偏弱靠占比——两头分开动：
- 她自己的声浪 `atk 5 → 6`、`wave_n 12 → 16`（队友局占比往 20–30 推）；
- 领唱 `lead_mult 1.2 → 0.5`（只影响她当主控，先 0.6 冒烟后再收一档）；
- 增益往上给一点让队友局提升回到正数：歌声 `song_atk 0.12 → 0.15`、S3 `s3_atk 0.8 → 1.0`（这两项也作用于她自己当主控，所以领唱多收了 0.1）。

本机冒烟（atk 6、wave_n 16、领唱 0.6，其余同 70843079；seed 与云端同号，作同 seed 对比）：

| | 主控 标准 seed 1–24 | 主控 Ⅳ seed 1–24 | 主控 Ⅷ seed 1–24 | 队友 标准 seed 1–4（28 局） | 队友 Ⅳ seed 1–4（28 局） |
|---|---|---|---|---|---|
| 云端 70843079 同 seed | 18 / 24 | 20 / 24 | 17 / 24 | 她占 16.7%（seed 1–8） | 15.7%（seed 1–8） |
| 冒烟 | 18 / 24（75%） | 16 / 24（67%） | 16 / 24（67%） | 20 / 28（对照 21 / 28）；**她占 25.1%**；开局干员 38.7%（对照 38.6%） | 17 / 28（对照 18 / 28）；**她占 22.6%**；开局干员 40.1%（对照 37.5%） |

占比进了 20–30；主控标准档还在 75% 左右，所以最终再把领唱收到 0.5、同时把歌声 / S3 往上给（上面最后一条）。这一版没有在本机跑（10-11 起本机冒烟每次不超过约 6 局，批量走云端）。

**接正式美术（fb82bcd6）**：攻击条 fps 14 → 12 让普攻出手晚 0.03 秒、技能出手早 0.08 秒，普攻间隔不变，对胜率的影响远小于本轮调数，一并在下面的确认轮里看。
**老干员同 seed 不变**：对 main 6010d3aa（`game/` + `art/` 同版本），维什戴尔 + 铃兰 + 塞雷娅 seed 1、斯卡蒂 + 推进之王 + 凯尔希 seed 2、艾雅法拉 `--norecruit` seed 3，`--trace=1`、10:00：TRACE **逐行相同**（BALANCE 只差 `wall` 等计时字段，main 对 main 自比也一样）。
快检全量（fb82bcd6，`--jobs 4`）46 项 rc=0；合入 6010d3aa 后 `--only core` rc=0。

**确认轮（云端，底 = wip/skalter-tune 当前提交）**：

```bash
python tools/balance_run.py --game game --jobs 4 --op skalter --bot expert --seeds 56 --seed0 1 --out build/cloud/sk3-lead-t0 --tag sk3-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sk3-lead-t1 --tag sk3-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sk3-lead-t2 --tag sk3-lead-t2 --extra="--maxt=1000 --tier=2"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/sk3-mate-t0 --tag sk3-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 1 --out build/cloud/sk3-mate-t1 --tag sk3-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 1 --out build/cloud/sk3-mate-t2 --tag sk3-mate-t2 --extra="--maxt=1000 --tier=2"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 8 --seed0 1 --out build/cloud/sk3-base-t0 --tag sk3-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/sk3-base-t1 --tag sk3-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/sk3-base-t2 --tag sk3-base-t2 --extra="--maxt=1000 --tier=2"
```

判定同上一节。已知风险：标准 / Ⅳ 的同提交基线本身就在 70 上下，「队友合计高于基线又不远超 70」在这两档几乎没有空间，以 Ⅷ 的提升和占比为主看；主控标准档若仍 > 72%，再收 `lead_mult` 0.5 → 0.4。

### 老干员同 seed 不变（10-11，对 main 71c078d5，`--trace=1`，10:00）

- 维什戴尔 + 铃兰 + 塞雷娅（满编）seed 1、斯卡蒂 + 推进之王 + 凯尔希（满编）seed 2、艾雅法拉 `--norecruit` seed 3：TRACE 与 BALANCE **逐字节相同**。
- 单人开局、自然招募（铃兰 seed 4）：第一次出招募卡（1:16）起分叉——招募池从 13 人变成 14 人，抽卡结果变了，属预期（docs/36 §2「不含她的老编队逐局相同」指满编 / 不招募的局）。
