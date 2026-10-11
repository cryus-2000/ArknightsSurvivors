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

### 5.6 画面帧条 `fx`（10-11 加，纯画面，追加式）

任何积木（以及 `blocks.skills[i]` 本身 = 技能发动那一刻）可以带 `"fx": [条目…]`，把 `game.gd V6_FRAMES` 里登记的帧条挂上去。**不写 `fx` 的干员画法逐像素不变**；
`fx` 只往干员自己的 `pfx` 加粒子，散布只用 `g.vrng`，不碰 `g.rng` / 玩法状态（同 seed `TRACE` / `BALANCE` 不变，见 §测试「fx 同 seed」）。缺图（`g.tex` 没有这条）时静默跳过，原来的程序画法照旧作底。
实现：`op_blocks.gd` 末尾的 `fx_play / fx_tick / fx_spawn / fx_draw / fx_body / fx_orbit / _fx`；`data_operator.gd` 的 `_draw_pfx`、`draw_fx_add`、`draw_body`（贴身层）、`draw_auras`（绕行体）。

| 字段 | 缺省 | 说明 |
|---|---|---|
| `strip` | 必填 | 帧条名（`fx_*` / `proj_*`，帧数与 fps 取 `V6_FRAMES`） |
| `cond` | — | 同 §1.3 的条件串（例：`"lamp < $talent_dark"` 选昏暗版） |
| `at` | `center` | `center`：形状中心（技能发动 / 常驻积木时是区域中心）；`self`：干员脚底；`leader`：主控；`zone`：区域中心；`hits`：本次命中的每个敌人（只限伤害形状）；`orbit`：`shape.orbit` 的每个判定点（代替小菱形，循环播） |
| `layer` | `over` | `floor`：地面层（人物下面）；`over`：上层普通混合；`add`：加色层；`behind` / `front`：贴身层，画在本体后 / 前（见下） |
| `fit` | — | 帧条在 1x 美术像素里的「半径」；写了就按形状半径缩放：每个 1x 像素 = `r / fit` 世界像素（再乘 `scale`） |
| `scale` | 1 | 没写 `fit` 时：每个 1x 像素 = `g.PX × scale` 世界像素；写了 `fit` 时是额外倍率 |
| `max_scale` | 3.2 | 放大上限（每 1x 像素至多几世界像素，同 `vfx.gd FX_SCALE_MAX`），免得颗粒比人物粗太多 |
| `n` / `spread` | 1 / 0 | 播几份；在 `spread × 半径` 的地面椭圆里随机散开（`g.vrng`） |
| `rise` | 0 | 向上飘的速度（像素 / 秒） |
| `life` | 一遍 | 写了就循环播这么多秒（最后三成淡出）；不写 = 帧数 / fps 播一遍 |
| `every` | — | 只用于常驻积木：生效期间每隔这么多秒播一次（第一帧就播）；瞬时积木 / 技能发动上写了报错 |
| `tint` | 白 | `[r, g, b]` 或 `[r, g, b, a]` |
| `anchor` | 帧中心 | 1x 帧内锚点（@2x 贴图自动 × `A.hires`，docs/25 §6 的规则） |
| `off` / `ang` / `rot` | — | 位置偏移（世界像素）/ 旋转角度（度）/ `true` = 随锥形朝向转 |
| `hold` | false | `true` = **常驻跟随帧条**（10-12 加，见下）：挂常驻积木，生效期间循环、每帧跟着区域中心 / 当前区域半径走 |
| `fade` | 见下 | 常驻跟随条目（贴身层 / `vortex` / `hold`）的进出淡入淡出秒数：一个数 = 进出同长，`[进, 出]` 分开写（0–5）。缺省：贴身层 `[0, 0.15]`、`vortex` `[0.5, 0.4]`、`hold` `[0.3, 0.3]` |
| `if_tex` | — | 按贴图有无取舍（10-12 加，纯画面）：`"fx_x"` = 有这条贴图才画，`"!fx_x"` = 缺这条贴图才画（程序回退）。任何条目都能写 |

**常驻跟随帧条**（`hold: true`，10-12 加，浊心斯卡蒂 S3 地面漩涡 docs/66 首用）：同贴身层一样跟着常驻积木（技能 do 里的 `verb.mode`、光环等）——生效期间一直画，
帧号 = `floor(积木已生效秒数 × fps) % 帧数`；位置 = `at`（`zone` 缺省 / `self` / `leader`）+ `off`；写了 `fit` 时**每帧**按当前区域半径缩放（每个 1x 像素 = `r / fit × scale`，夹到 `max_scale`），
区域被 buff 放大缩小即时跟上；整体透明度 = `tint` 的 a × 进出淡入淡出（`fade`）× 特效亮度设置。不写 `every / life / n / spread / rise / rot`。
`layer` 只能是 `ground`（**紧贴地砖**：画在地砖之后、溟痕 / Boss 地面预警 / 灯标 / 掉落之前，大片地面特效不盖住危险提示；`world.draw_world` → `squad.draw_ground_fx` → `data_operator.draw_ground_fx`）、
`floor`（区域椭圆层，在程序漩涡下面）或 `add`（加色层）。`ground` 只给 `hold` 帧条用。实现：`op_blocks.fx_hold_strips / fx_hold_alpha / fx_fade_io / fx_hold_out / fx_on`。
贴身层记录退出后保留 = 各常驻跟随条目淡出秒数的最大值（原来：有漩涡 0.4、否则 0.15；不写 `fade` 时与原来相同）。

**贴身层**（`layer: behind / front`）：挂在常驻积木上（例：S3 的 `verb.mode`），积木生效期间循环；锚点对准干员脚底 `pos`（+ `off`），每 1x 像素 = `g.PX × scale`、不压扁不旋转；
帧号 = `floor(积木已生效秒数 × fps) % 帧数`（同一块积木的 back / front 共用）；积木失效后 0.15 秒淡出。不写 `every / life / n / spread / rise`，`at` 只能是 `self`。

**程序漩涡**（`{"vortex": {参数…}}`，10-11 加，用户对照原作 S3「饱和度太高，要这种效果」）：不用帧条，程序画一片铺在地面上的大漩涡——
许多细弧形水流线在透视椭圆（y × `sy`）里螺旋着绕中心转、各自从外圈卷向内圈（生命周期 sin 包络淡入淡出）、沿线两端渐隐，
少量点缀色（暗红）流线、上飘闪烁的小光点、中心柔光与一层极淡的水色底。像贴身层一样**跟着常驻积木**：生效期间一直画，0.5 秒淡入、退出 0.4 秒淡出；
条目 `cond` 切换时 0.35 秒交叉淡入淡出。条目字段只用 `vortex / layer（floor = 人物下面，缺省；add = 加色层）/ at（zone 缺省 / self / leader）/ off / cond / tint / fade / if_tex`（tint 的 a 乘整体透明度）。
有了美术帧条后的写法（10-12，浊心斯卡蒂 S3）：帧条用 `hold` 条目作主体，完整程序漩涡写 `"if_tex": "!帧条名"` 留作缺图回退，另一条只剩光点的漩涡（`n: 0`）写 `"if_tex": "帧条名"` 叠在帧条上。
全部顶点色三角形攒进编队合批画布一次提交（`batch_canvas.add_tris`，docs/50 合批口径）；随机常数在第一次画时用 `g.vrng` 生成并缓存，运动只看 `g.t`，不碰玩法。
`--perfab=N` 同局轮换时 /b 桶不画漩涡（量净成本用）。

| 参数 | 缺省 | 说明 |
|---|---|---|
| `n` / `acc_n` | 32 / 4 | 流线条数（≤ 64）/ 其中点缀色几条 |
| `r` / `max_r` / `r0` | 1 / 520 / 0.12 | 外半径 = 区域半径 × r（封顶 max_r 世界像素）/ 流线卷到的最内圈比例 |
| `len` / `curl` | 1.3 / 0.22 | 每条弧长（弧度）/ 尾端比头端外扩多少（螺旋感） |
| `spin` / `drift` | 0.55 / 0.10 | 角速度（弧度 / 秒，内圈更快）/ 向内卷的速度（生命周期 / 秒） |
| `w` / `a` | 1.6 / 0.3 | 线宽（世界像素）/ 最大透明度 |
| `halo` / `halo_a` | 0 / 0.25 | 软边：再画一遍宽 halo 倍、透明度 halo_a 倍的淡线（0 = 不画） |
| `col` / `acc` / `acc_a` | 青 / 暗红 / 0.55 | 主色、点缀色 `[r, g, b]`、点缀透明度倍率 |
| `seg` | 8 | 每条流线分几段 |
| `motes` / `mote_a` / `mote_sz` / `mote_rise` | 24 / 0.55 / 2 / 18 | 光点个数（≤ 64）/ 透明度 / 边长（三成两倍大）/ 上飘高度 |
| `glow` / `glow_r` / `fill` | 0.12 / 0.3 / 0.05 | 中心柔光透明度 / 半径比例 / 整片水色底透明度 |
| `ring` | 1 | 区域椭圆边线透明度倍率（< 1 压淡程序硬边；取所有生效漩涡的最小值） |
| `sy` | 0.55 | 透视压扁 |

浊心斯卡蒂（§10 第 13 条）：

```jsonc
"attack": {"shape": "circle", …, "fx": [
  {"strip": "fx_skalter_wave",     "fit": 30, "max_scale": 4, "layer": "floor", "cond": "lamp >= $talent_dark"},
  {"strip": "fx_skalter_wave_dim", "fit": 30, "max_scale": 4, "layer": "floor", "cond": "lamp < $talent_dark"}]},
"skills": [{"dur": "$s1_dur", "fx": [{"strip": "fx_skalter_note", "at": "zone", "n": 6, "spread": 0.6, "rise": 26, "life": 1.1, "scale": 1.2}], "do": […]}, …,
  {"dur": "$s3_dur", "fx": [{"strip": "fx_skalter_wave", "at": "zone", "fit": 30, "max_scale": 4, "layer": "add", …}], "do": [
    {"verb": "mode", "zone_mult": "$s3_aura", "fx": [
      {"strip": "fx_skalter_s3_back", "layer": "behind", "anchor": [48, 84]},
      {"strip": "fx_skalter_s3_front", "layer": "front", "anchor": [48, 84]},
      {"strip": "fx_skalter_vortex_floor", "hold": true, "layer": "ground", "fit": 160, "scale": 0.62, "max_scale": 2.0625, "fade": 0.45, "tint": [0.92, 0.98, 0.98, 0.5]},
      {"vortex": {…完整程序漩涡…}, "layer": "floor", "if_tex": "!fx_skalter_vortex_floor"},
      {"vortex": {"n": 0, "motes": 40, …}, "layer": "floor", "fade": 0.45, "if_tex": "fx_skalter_vortex_floor"}]}, …]}]
```

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
9. `fx`（§5.6）：是数组、≤ 8 条；字段只能是表里那些；`strip` 是 `fx_*` / `proj_*`；`layer` / `at` 取值在表内（`orbit` 只挂 `shape.orbit`、`hits` 只挂伤害形状）；
   `every` 和贴身层只能在常驻积木上；`cond` 能解析；数值夹紧（`scale` 0.05–8、`max_scale` 0.5–16、`n` ≤ 16、`spread` ≤ 1.5、`life` ≤ 5、`every` ≥ 0.05）。技能条目 `blocks.skills[i]` 允许 `dur / do / fx` 三个字段。
   `hold` 条目（10-12）：`hold` 是布尔，只能挂常驻积木，`layer` 只能 ground / floor / add、`at` 只能 zone / self / leader，不写 every / life / n / spread / rise / rot，不和 vortex 同写；`layer: ground` 只给 hold 帧条；
   `fade` 只写在常驻跟随条目上，一个数或两个数、0–5 秒；`if_tex` 是 `fx_*` / `proj_*` 帧条名（可带 `!`）。
   `vortex` 条目：不写 `strip`，只能挂常驻积木，`layer` 只能 floor / add、`at` 只能 zone / self / leader，不写帧条专用字段；`vortex` 对象的键在漩涡表内、数值按表夹紧、`col / acc` 是 3 个数字。

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
    - 声浪 `atk 4`，`max_n 16`（`wave_n`，打圈内最近 16 个，Boss / 精英优先）；「潮汐和声」「深海的回响」也只打 16 个。（10-11 再往辅助推一档，见第 15 条；第一版 atk 5 / 12 个，云端后上调，见 §测试「辅助向云端结果」）S3 不再放大声浪（删 `s3_mult`，`verb.mode` 只留 `zone_mult`）。
    - **领唱**（新，特性）：她自己当主控时，每次声浪再放一圈**不设上限**的声浪（`trig.every_n n 1` + `cond is_leader`，`lead_mult 0.3`（第 15 条），同记「声浪」；第一版 1.2 主控偏强）——单人开局在招到人之前不能只剩 12 个目标的输出。当队友时没有这一圈。
    - 增益（受益者 = 歌域内干员，含她自己与主控；`scope in_zone`）：特性「歌声」攻击 +18%（`song_atk`，新，第 15 条）；S1 加攻速 +25%（`s1_aspd`，新，乘技能强度）；S2 攻击 +15%（`s2_atk`，新）+ 攻速 +15%（不变），深海猎人 0.15 → 0.25；
      S3 全队攻击 0.5 → 1.0，昏暗时不再「声浪 ×1.5」，改为全队攻击再 +30%（`s3_dark_atk`）；天赋昏暗「声浪 +50%」改为歌域内攻击 +10%（`dark_atk`）；深海猎人每人 0.04 → 0.08（最多 3 人）；节点 2「潮声渐强」从「声浪 ×1.15」改为歌域内攻击 +10%（`aura.atk`）。
    - 灯火代价不变：S3 灯火每秒 -2，昏暗时不扣；S1 受击灯火流失减半不变。治疗数值不变。
13. **特效帧条**（10-11，§5.6 `fx`）：每次声浪（普攻）在地面播 `fx_skalter_wave`，灯火昏暗（< `talent_dark`）换 `fx_skalter_wave_dim`；「潮汐和声」回声同样播、透明度 0.6；
    S1 / S2 发动时歌域里散 6 个 `fx_skalter_note` 上飘；S3 发动时区域中心加色层一圈声浪，持续期间脚下 Codex 重绘的 `fx_skalter_s3_back / _front`（ec06672e，`art/incoming/skalter_s3_handoff.md`）分层夹住本体，S3 期间不再撒旧音符、不叠 `fx_skalter_s3_orbit`（不分层预览 / 回退件）；
    精二「溟海之声」6 个判定点画 `fx_skalter_note` 代替小菱形。歌域椭圆与 `exec_shape` 的程序扩散环照旧作底。
    声浪帧条按 30px 半径画、放大封顶 `max_scale 4`（@2x 每像素 2 世界像素，与人物 1x 像素同密度）：歌域 190–460 时帧条只到中心约 120 像素，外圈仍由程序环扩到歌域边——
    完全按歌域放大会是 7–15 像素的大方块（实测截图，`build/skalter_fx/`）；要「帧条直接铺满歌域」需要 Codex 出更大的声浪图（例如外径 ≥ 100px、线宽 1px）。
14. **降饱和 + 地面大漩涡**（10-11，用户对照原作 S3：「饱和度是不是太高了」）：所有 fx 条目加 `tint`——声浪 0.5、回声 0.35、音符 0.7 / 0.75、S3 发动加色声浪 0.45、
    贴身 `fx_skalter_s3_back / _front` 0.55 / 0.45，颜色乘 `[0.8, 0.98, 0.92]` 一类（压红、压蓝，偏青，降低饱和观感）；帧条本身仍是二值透明，半透明全靠 modulate。
    S3 的 `verb.mode` 加一条程序 `vortex`（外半径 = 歌域 × 0.62、封顶 330；40 条流线含 6 条暗红、halo 软边、50 个光点、区域边线压到 0.4）；
    常驻歌域光环（特性 `aura.atk`）加一条更淡的 `vortex`（16 条、无中心光，`cond: "!skill_active:2"`，S3 期间交叉淡出让位）。
    正式的地面漩涡帧条已写特效单给 Codex：docs/66。
    评审后再压一档：灯火昏暗的声浪 `fx_skalter_wave_dim`（普攻与回声）的紫色还是太亮，透明度 0.5 → 0.38、回声 0.35 → 0.27（同比例），与第 15 条同一次提交。
15. **再往辅助推一档（用户 10-11 批）**：用户看画面觉得声浪比别的干员的普攻还显眼、还强。`atk 6 → 4`（声浪、潮汐和声、深海的回响、领唱都按它算）、领唱 `lead_mult 0.5 → 0.3`、歌声 `song_atk 0.15 → 0.18`；其余不变。
    她当队友时占全队的伤害会再降（sks 云端 13–17% → 预计 10% 上下），胜率提升更多来自歌声；当主控时单人输出降一截（声浪 ×0.67、领唱 ×0.4），靠歌声 +18% 与 S2 / S3 加在她自己身上补一部分。定档看 §测试「再推辅助一档」的云端批。
16. **S3 地面大漩涡换 Codex 帧条**（10-12，docs/66，素材 b49d0047 `fx_skalter_vortex_floor` 8 帧 320×176 10fps 循环，`art/incoming/skalter_vortex_handoff.md`）：
    S3 `verb.mode` 加一条 `hold` 帧条——`layer: ground`（地砖之上、溟痕 / Boss 地面预警 / 掉落之下，不盖危险提示）、中心 = 歌域中心（主控）、
    `fit 160 × scale 0.62`（每个 1x 像素 = 漩涡外半径 / 160，外半径 = 歌域 × 0.62，同原程序漩涡，跟着歌域 buff 变）、`max_scale 2.0625`（外半径封顶 330，同程序版 `max_r`）、透明度 0.5、tint 略压红、进出 0.45 秒淡入淡出；
    原程序漩涡（40 条流线）改成 `if_tex: "!fx_skalter_vortex_floor"`，只在缺图时画（回退）；有图时另画一条只有光点 + 淡中心光的漩涡（`n: 0`、40 个光点、区域边线照旧压到 0.4）。贴身 `_back / _front` 不变。
    「外半径」按 docs/66 §2.1 的算例（240–330 → 每 1x 像素 1.5–2 世界像素）取漩涡外半径；按整个歌域（× 1）放大时后期歌域 500+，帧条铺出画面、只看得到中心留空的那一圈（实测截图后改）。

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

### 再推辅助一档（10-11，第 15 条：atk 4、领唱 0.3、歌声 +18%）

在 main 13b4a8e3 + 54e6e502（降饱和与漩涡）上改数（`skalter.json` 的三个数与对应说明文字，外加昏暗声浪帧条透明度，见第 14 条末），本机不跑批（每次 ≤ 6 局的规则），云端：

```bash
# 主控 56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op skalter --bot expert --seeds 56 --seed0 1 --out build/cloud/sk4-lead-t0 --tag sk4-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sk4-lead-t1 --tag sk4-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op skalter --bot master --seeds 56 --seed0 1 --out build/cloud/sk4-lead-t2 --tag sk4-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友 7 名开局干员 × seed 1–8 = 56 局 × 标准 / Ⅷ
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/sk4-mate-t0 --tag sk4-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset skalter_mate --bot master --seeds 8 --seed0 1 --out build/cloud/sk4-mate-t2 --tag sk4-mate-t2 --extra="--maxt=1000 --tier=2"
```

队友差值的对照用 `sks-base-t0 / t2`（70843079，同 seed 1–8）或之后同提交的 starts 批；合入的 main 带进了藏品审计（docs/65），严格比较时补同提交 starts。
判定同前：主控每档 50–70；队友局她的占比低于 20% 可以接受（用户定的方向是辅助），但开局干员占比不低于对照、队友合计不低于对照。
主控 Ⅷ 若掉到 50 以下，先把 `lead_mult` 回 0.4，不动 `atk`。

快检全量（`--jobs 4`）46 项 rc=0；老干员同 seed（维什戴尔 + 铃兰 + 塞雷娅 seed 1、斯卡蒂 + 推进之王 + 凯尔希 seed 2、艾雅法拉 `--norecruit` seed 3，`--trace=1`、10:00）对改数前的 13b4a8e3 + 54e6e502（`game/` + `art/`）TRACE 逐行相同。

### 老干员同 seed 不变（10-11，对 main 71c078d5，`--trace=1`，10:00）

- 维什戴尔 + 铃兰 + 塞雷娅（满编）seed 1、斯卡蒂 + 推进之王 + 凯尔希（满编）seed 2、艾雅法拉 `--norecruit` seed 3：TRACE 与 BALANCE **逐字节相同**。
- 单人开局、自然招募（铃兰 seed 4）：第一次出招募卡（1:16）起分叉——招募池从 13 人变成 14 人，抽卡结果变了，属预期（docs/36 §2「不含她的老编队逐局相同」指满编 / 不招募的局）。

### fx 同 seed（10-11，§5.6 接入后对 main b8b97658，headless `--balance --seed=1 --bot=expert --maxt=240 --trace=1 --maxprog --sptest`）

浊心斯卡蒂当主控（`--op=skalter`）、当队友（`--op=mizuki --squad=skalter`）各 1 局：`TRACE` 241 行逐字节相同；`BALANCE` 去掉 `prof` 与 `bot.peak / peak_min`（画面峰值，blocks_eq 同口径）后逐字段相同。
画面：`build/skalter_fx/skalter_fx.mp4`（14 秒：声浪 → S3 → 灯火切昏暗的深紫声浪 → S3 结束）、`before_after.png`（同局同帧，左 = 去掉 fx 条目、右 = 现行）。

### 程序漩涡（10-11，§5.6 `vortex`）

- 画面：`build/skalter_fx/ref_compare.png`（原作参考 | 改前 main | 改后，同局同帧：`--balance --seed=1 --bot=expert --op=skalter --maxprog --sptest --nodeath`，1280×720，帧 525 / 690，S3 生效、灯火 36 / 昏暗 29）；
  `skalter_fx_v2.mp4`（同参数 `--recframes=28,330`，22 秒，15 fps）。
- 成本（同局轮换 `--perf --prof --perfab=30`，同上参数跑到 150 秒，1280×720，每桶约 1130 帧，S3 约一半时间生效）：`dw_shadows`（歌域与漩涡所在段）0.15 / 0.04 毫秒（开 / 关），
  `draw_world` 0.41 / 0.30 → 漩涡净成本约 **0.11 毫秒 / 帧**；渲染 CPU 中位 1.15 / 1.19、GPU 中位 1.03 / 1.01 毫秒（噪声内）。
- 同 seed（对 main f024142a，headless `--balance --seed=1 --bot=expert --maxt=240 --trace=1 --maxprog --sptest`，主控 / 队友各 1 局）：TRACE 241 行与 BALANCE（去 prof、画面峰值）逐字节相同。

### S3 地面漩涡帧条（10-12，§10 第 16 条）

- 快检全量 rc=0（53 项，合 origin/main 246341f2 后）；`test_core.test_fx_hold`：skalter.json 通过校验、11 条反例全部被拒、淡入淡出与 `if_tex` 数值。
- 同 seed（对 origin/main 246341f2，headless `--balance --seed=1 --bot=expert --maxt=240 --trace=1 --maxprog --sptest`，主控 `--op=skalter` / 队友 `--op=mizuki --squad=skalter`）：TRACE 241 行与 BALANCE（去 prof、画面峰值）逐字节相同。
- 缺图回退：在临时副本里拿掉 `fx_skalter_vortex_floor(@2x).png` 同局录屏，完整程序漩涡照旧出现、没有报错（`build/skalter_vortex/*_fallback.*`）。
- 画面：`build/skalter_vortex/`——`s3_early_0109_strip.png` / `s3_late_0831_strip.png`（同局 `--balance --seed=1 --bot=expert --op=skalter --maxprog --nodeath --realtime --fixed-fps 30`，1280×720，01:09 与 08:31 满屏敌人）、
  `*_fallback.png`（同帧缺图回退）、`compare_strip_vs_fallback.png`、`skalter_vortex_s3.mp4`（30.5–46.5 秒：S3 发动淡入 → 循环 → 结束淡出，30fps）与 `skalter_vortex_s3_fallback.mp4`。
- 素材检查：alpha 只有 0 / 255、帧边缘无不透明像素（无裁切）；相邻帧 alpha 变化 2972–3167 像素，末帧 → 首帧 3164（在相邻范围内，循环不跳）。

## 11. 星熊 `hoshiguma` 的表达（docs/59 §3 + §8.3，纯数据干员，10-11）

见 `data/characters/hoshiguma.json` 的 `blocks`：0 个 `custom`，没有 `hoshiguma.gd`。名字按 docs/63 §6（S1「战意」、S2「荆棘」、S3「力之锯」、天赋「战术装甲」，分支铁卫）。
帧条用 Codex 第五批正式图（`op_hoshiguma_*`，docs/64 验收，无占位），技能图标 `skill_hoshiguma_s1..3`，特效帧条 `fx_hoshiguma_block / _sand / _demon_slash`（docs/25 §6）。

### 新积木（`op_blocks.gd` / `data_operator.gd` 末尾「星熊 hoshiguma」段，追加式）

积木是通用的，星熊只是第一个用的。名字登记在 `op_blocks.gd` 的 `EXT_BLOCKS`（族.名 → 放置类别）/ `EXT_CONDS`；校验在 `_ext_block`，执行在 `data_operator.gd` 同名段。
中段只加了转发：`parse_cond` / `cond_true` 认 `EXT_CONDS`，`_block` 认 `EXT_BLOCKS`；data_operator 的 `update` / `_release` 用 `cur_attack()`（`verb.swap_attack`）、`_sustain` 末尾调 `_ext_sustain`、`_exec_list` 缺省分支调 `_ext_exec`。
后来的干员追加积木：另起自己的段落，往 `EXT_BLOCKS` / `EXT_CONDS` 加名字。

| 积木 | 类 | 参数 | 说明 |
|---|---|---|---|
| `shape.line` | 瞬时 / 普攻形状 | `len, width, mult, kb, stun, max_n, src, tags, on_hit, fx` | 从自身朝最近目标（手动普攻按 A 方向）长 `len`（× op_range）、宽 `width` 的矩形，命中沿线全部；击退沿斩击方向；伤害口径同 `exec_shape`；`fx`（§5.6）中心 = 线段中点、半径 = 半长、角度 = 斩击方向（`rot: true`），没有 fx 时画程序线 |
| `verb.displace` | 瞬时 | `center: self/leader/target/last_hit, r, kb, on_hit` | r 内非 Boss 敌人沿离心方向 `e.kb += kb`（负 = 拉），精英 ×0.3；**不造成伤害、不登记命中**（不触发命中类藏品） |
| `verb.field` | 瞬时（生成） | `center, r, dur, every, do, fx` | 地面区域：每 `every` 秒以区域中心为 `target` 执行一次 `do`，共 round(dur / every) 次（按次数计，不靠浮点累加）；每名干员同时 ≤ 16 个；`fx` 在生成时以区域中心 / 半径播，没写 `life` 的条目循环到区域结束 |
| `verb.negate_next` | 只能放技能 do | `on_block, on_miss, fx, text` | 技能持续期间主控下一次受到的攻击完全格挡并执行 `on_block`、技能随即结束；持续结束仍没挨打执行 `on_miss` |
| `verb.dr` | 常驻 | `value` | 主控受到的伤害 × (1 − value)（经 `dmg_taken_mult`） |
| `verb.negate_chance` | 常驻 | `add, mult` | 本干员 `negate: true` 的 `trig.on_hurt` 概率 = (chance + Σadd) × Πmult |
| `verb.swap_attack` | 常驻 | `attack`（circle / cone / line） | 生效期间普攻换形状，节奏仍按 `blocks.attack.every` |
| `trig.on_hurt` | 触发 | `chance, boss_chance, max_chance, negate, cd, fx, text, do` | 主控将受到一次攻击（闪避 / 护盾之后）。概率 0 / 1 时不取随机数，(0, 1) 用 `g.rng` 取一次；`negate` = 这一下完全格挡 |
| `trig.on_negate` | 触发 | `do` | 本干员格挡了一次攻击（negate_next 或 negate 的 on_hurt） |
| 条件 `beacon_charging` | — | — | 主控正在给灯标读条（`beacon_sys.charging`） |

受击询问里触发的 `do`（反击、推开、震退）推迟到本干员下一次 `update` 开头执行（延迟队列 t = 0）：`enemy_hit` 常在敌人遍历中途被调用，不在那里造成伤害 / 击杀。

**combat.gd 1 处**（docs/59 §6 预计的「0–1 处」，通用挂点，任何干员都能用）：`enemy_hit` 询问 `dmg_taken_mult` 期间把来源放进 `combat.cur_src`（读 `boss`）；任一干员返回 ≤ 0 即**整下作废**——不扣血、不掉灯火、不吃控制 / 侵蚀、不算「受伤」（同闪避，给 0.3 秒无敌）。
需要这一处是因为 `hurt()` 对物理伤害有 `max(1, dmg − armor)` 的底、灯火流失有 `hit_base 4` 的底，乘 0 仍会掉 1 血和 4 灯火。现有干员的 `dmg_taken_mult` 都 > 0，行为不变。

### 积木写法

- 画面：格挡 / 热砂 / 鬼面·力之锯 三条帧条都走通用 `fx` 字段（§5.6）。合入 main 前分支上的专用字段 `fx_strip / fx_r / fx_y` 已撤掉：格挡 `{strip: fx_hoshiguma_block, off: [0, -26], scale: 1.4}`（中心 = 主控）、热砂 `{layer: floor, fit: 23}`（余烬 fit 30）、直线斩 `{fit: 32, rot: true, off: [0, -30]}`。
- 普攻 `shape.cone`（r 110、半角 70、kb 220，`slash: true` 画刀光）。
- S1 战意（3 秒）：`verb.negate_next`，on_block = 主控周围 r120 ×2.0 kb 360「举盾反击」；on_miss = 前方扇形 ×1.5。
- S2 荆棘（8 秒）：`buff_self op_atk +0.4`、`verb.dr 0.2`、`verb.negate_chance ×2`；热砂 = 特性里 `trig.every_n n 1 cond skill_active:1` → `verb.field center last_hit`（r80、2 秒、每 0.5 秒 ×0.15 = 每秒 ×0.3）。
- S3 力之锯（10 秒）：`buff_self op_atk +0.6`、`verb.dr 0.3`、`verb.swap_attack` → `shape.line`（220 × 50，kb 220 × 1.5）；震退 = 特性里 `trig.on_hurt cond skill_active:2` → `verb.displace r120 kb300`（含被格挡的那一下）。
- 天赋 战术装甲：`trig.on_hurt chance 0.25 / boss_chance 0.1 / max_chance 0.8 negate` → `verb.displace r90 kb200`；`trig.passive cond beacon_charging` → `verb.negate_chance add 0.15`。
- 节点：阔斩 `op_range +0.15`；重刃 局部 `dmg ×1.15`；盾墙 `trig.on_negate` → `verb.displace kb 0 + st.stun 0.4`；热砂·余烬 / 精二鬼面见差异。

### 与 docs/59 的差异

1. 名字按 docs/63 §6；hit_sources 去掉「震退」（只推不伤，不登记来源）。
2. 战术装甲免伤时的推开 r90 = `verb.displace`，不造成伤害。
3. 「盾墙」眩晕作用于**每次格挡**（含 S1 战意的格挡），不只天赋。
4. 「热砂·余烬」：docs/59 §8.3 写的是 patch（sand_dur 2 → 4、灼伤 ×0.5），积木还没有 `patch`，改为**每处热砂再叠一层 4 秒余烬**（每秒 ×0.2，`ember_mult`）：前 2 秒合计每秒 ×0.5，之后 2 秒 ×0.2。
5. 精二「鬼面」：没有 `replace_attack`，写成 `trig.every_n n 4`，第 4 次盾斧斩**之后追加**一记直线斩（×1.3），不是替换。
6. S2 热砂落点 = 本次盾斧斩命中的第一个敌人（`center: last_hit`），没打中不留砂。
7. 格挡概率封顶 0.8（`block_max`）；格挡反击 / 推开在下一帧执行。
8. **数值**：`atk 30 → 32`、`block_chance 0.20 → 0.25`（docs/59 §3 的旋钮顺序：偏弱先加 block_chance 再加 atk）。原值本机标准高手 4 / 12；见下表。

接入登记：`balance.json operators.hoshiguma`（A+，skill_power +0.02）、`lore.json`、`tools/balance_run.py OPS` 与预设 `hoshiguma_mate`、音效 `sfx.gd OP_ALT` 借用
（普攻 ← 塞雷娅普攻 ×0.85、hit ← 推进之王、big（格挡「铛」）← 推进之王重击 ×1.25、S1 ← 塞雷娅 S1、S2 ← 推进之王 S2、S3 ← 斯卡蒂 S3）。选人页 / 图鉴 / 招募池按 JSON 自动列入（基础池）。
单元测试：`tests/test_core.gd test_hoshiguma_blocks`（14 条校验反例、编译出的数值、线段判定、格挡概率、概率 0 / 1 不取随机数）。

### 冒烟（本机，wip/skalter-tune + origin/main 52d01a6e，`--maxt=1000`，含超时口径，seed 1–12；「她占全队」= 盾斧斩 + 举盾反击 + 热砂 + 力之锯 + 鬼面 占全队 `out`）

| 版本 | 主控 标准·高手 | 主控 Ⅷ·熟练 | 队友 标准·高手（7 开局 × seed 1） | 她占全队（主控 / 队友） | 脚本错误 |
|---|---|---|---|---|---|
| docs/59 原值（atk 30、block 0.20） | 4 / 12（33%） | 6 / 12（50%） | 6 / 7 | 23% / 16% | 0 |
| atk 34、block 0.25 | 9 / 12 | — | — | 19% / — | 0 |
| atk 30、block 0.25 | 5 / 12 | — | — | 27% / — | 0 |
| **现值 atk 32、block 0.25** | **12 / 12（100%）** | **8 / 12（67%）** | **6 / 7**（输的是艾雅法拉） | **21% / 22%**（队友各队 10–39%） | 0 |
| 对照 塞雷娅（同参数） | 8 / 12（67%） | — | — | — | 0 |

- 12 局的噪声极大：atk 30 → 32 → 34 三档标准分别 5 / 12、12 / 12、9 / 12，不单调；招募链（谁先招到）比她自己的数值影响大。block 0.25 的三批合计标准 26 / 36（72%）。现值只作云端整轮的起点，不作定档。
- 队友伤害占比 22% 在 docs/59 §7 目标 10–25% 内；主控局 21%（单人开局后期主输出是招来的人）。

### 老干员同 seed 不变（`--trace=1`，10:00，对加星熊前的同一提交 ba093017）

- 维什戴尔 + 铃兰 + 塞雷娅（满编）seed 1、斯卡蒂 + 推进之王 + 凯尔希（满编）seed 2、艾雅法拉 `--norecruit` seed 3、浊心斯卡蒂 `--norecruit` seed 5：TRACE 与 BALANCE（去掉 prof 与画面峰值 `bot.peak*`）**逐字节相同**。
- 单人开局、自然招募（铃兰 seed 4）：52 秒起分叉——招募池 14 → 15 人，属预期（同浊心斯卡蒂）。

### 云端整轮（主控 56 局 × 三档；队友 7 名开局干员 × seed 1–8 × 三档；同提交塞雷娅 / starts 对照）

```bash
# 主控：56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op hoshiguma --bot expert --seeds 56 --seed0 1 --out build/cloud/hsg-lead-t0 --tag hsg-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op hoshiguma --bot master --seeds 56 --seed0 1 --out build/cloud/hsg-lead-t1 --tag hsg-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op hoshiguma --bot master --seeds 56 --seed0 1 --out build/cloud/hsg-lead-t2 --tag hsg-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友：7 名开局干员 × seed 1–8 = 56 局 × 三档
python tools/balance_run.py --game game --jobs 4 --preset hoshiguma_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/hsg-mate-t0 --tag hsg-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset hoshiguma_mate --bot master --seeds 8 --seed0 1 --out build/cloud/hsg-mate-t1 --tag hsg-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset hoshiguma_mate --bot master --seeds 8 --seed0 1 --out build/cloud/hsg-mate-t2 --tag hsg-mate-t2 --extra="--maxt=1000 --tier=2"
# 同提交对照：塞雷娅单人（docs/59 §3「对照塞雷娅 ≤ 15 个百分点」）+ starts
python tools/balance_run.py --game game --jobs 4 --op saria --bot expert --seeds 56 --seed0 1 --out build/cloud/hsg-saria-t0 --tag hsg-saria-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op saria --bot master --seeds 56 --seed0 1 --out build/cloud/hsg-saria-t2 --tag hsg-saria-t2 --extra="--maxt=1000 --tier=2"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 8 --seed0 1 --out build/cloud/hsg-base-t0 --tag hsg-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/hsg-base-t1 --tag hsg-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/hsg-base-t2 --tag hsg-base-t2 --extra="--maxt=1000 --tier=2"
```

判定：主控三档各 50–70、对塞雷娅同档差 ≤ 15 个百分点；队友局她占全队 10–25%（docs/59 §7）；另看承伤 / 分与熄灯秒（应低于塞雷娅）。
旋钮（docs/59 §3）：偏弱先 `block_chance`（0.25 → 0.30）再 `atk`；偏强先回收 `atk`（32 → 30）、`s2_dr`（0.2 → 0.15）、`s3_dr`，战术装甲基础概率不低于 0.20（身份）；Ⅷ 跌破 50 先看 `beacon_bonus`。

## 12. 安洁莉娜的表达（docs/59 §5 + §8.5；10-11 第三批第 5 人）

见 `data/characters/angelina.json` 的 `blocks`：0 个 `custom`，没有 `angelina.gd`。名字按 docs/63 §6（S1–S3「秘杖·速充 / 微粒 / 反重力模式」，分支凝滞师），天赋只借原作名「加速力场」、机制按本作（用户 10-11 定，docs/59 §9）。

### 12.1 新积木（`op_blocks.gd` 文件末尾「安洁莉娜」段，只往后加）

第三批四人同时在加积木，为了好合并：新积木不改顶部的 `IMPL / PLANNED` 表，`_block` 里一行分流（`tag in ANGELINA_TAGS → _v_angelina`），执行器 / 校验全部写在文件末尾的本段；
`data_operator.gd` 的挂点各一行（`_exec_list` / `_sustain` / `update` / `_release` / `_release_skill` / `draw_auras`），状态变量与绘制写在它文件末尾的同名段。表里的 📝 → ✅ 只对本段生效。

| 积木 | 类 | 参数 | 说明 |
|---|---|---|---|
| `shape.point_aoe` | 普攻形状 | `range`（× op_range）、`land: densest / nearest`、`speed`、`r`（× 本干员 `area`）、`mult`、`src`、`muzzle [x, y]`（脚底为原点朝右，@2x 像素）、`on_hit`、`then` | 落点弹：出手帧从杖头射向射程内敌群最密处（手动普攻 A 类 = `aim_land`），飞 `距离 / speed` 秒；落地半径 r 伤害 → 对命中者 `on_hit` → 在落点执行 `then`（瞬时积木，`center: target` = 落点）→ `trig.on_impact` |
| `verb.displace` | 瞬时 / 力场子项 | `dir: pull / push`（力场里另有 `center / ring`）、`dist`（实际位移像素）、`r`、`center`、`elite_mult`（缺省 0.5）、`per_sec`（力场里 × 间隔）、`on_hit`（动了的敌人吃的状态）、`fx` | docs/60 `verb.displace`。体型档：Boss / 部件 / 宝箱 / 固定物不动，精英 × elite_mult，重型 × 0.3；拉向中心时夹住不越过中心，环带整形夹住不越过环 |
| `verb.field` | 常驻 | `center: leader / self`、`r`（× op_range）、`every`、`ring`、`ring_w`、`look: ring / lift / none`、`tick: [子项]` | docs/60 第 22 条。每 `every` 秒对场内敌人逐个执行子项（`verb.displace` / `st.*`），生效当帧先跑一次；`look` 是程序画法（§12.3） |
| `verb.buff_leader` | 常驻 | `stat: move_speed / pickup`、`op`、`value` | 主控（全局作用域）的移速 / 拾取范围 |
| `st.airborne` | 命中 / 力场子项 | `dur`、`h`、`within`、`elite_up / elite_down` | docs/60 `st.airborne`：悬浮 = `e.stun` + `e.air`（同艾丽妮：world.gd 抬高绘制、悬空没有接触伤害）。精英时长 × 0.5，Boss 不受；`elite_up / down` = 精英按局内时间间歇落地 |
| `st.weightless` | 命中 / 力场子项 | `dur`、`kb_mult` | docs/60 `st.weightless`（藏品 P2 的单体版）：期间受到的击退 × kb_mult。character.gd `melee_hit / area_hit` 的击退乘 `OpBlocks.kb_taken(e)`（没失重 = 1.0，老干员逐字节不变），她自己的位移也乘 |
| `st.dot` | 力场子项 | `mult`、`src`、`where: ring` | 力场 tick 时的伤害（× atk × 本干员 dmg 倍率，吃 vs_elite） |
| `trig.on_impact` | 触发 | `delay` | `shape.point_aoe` 落地时触发，`do` 里 `center: target` = 落点 |
| `dur.next_n` | 技能外壳 | `{"next_attacks": N}` + `attack_patch {mult, r_mult, force_mult, src, on_hit}` | docs/61 §2 📝 → ✅：接下来 N 发普攻带补丁。同维什戴尔 S1：打完之前照常充能（`skill_pending` 为真、`skill_active_left` 为 0），再放时重置为 N |

状态的公共筛选（`st.*` 任何位置）：`cond`、`boss: true`（Boss 也受，stun × 0.25）、`boss_only: true`、`within`、`where: ring`。新局部倍率 `area / force / force_lit`（`verb.buff_self`）：落点与拉拢范围、位移距离、灯光内位移。

**位移怎么落地（与藏品 #103 对齐）**：位移写成 `e.kb` 速度（enemies.gd 每秒衰减 900，位移 = |kb|² / 1800 × 移动倍率），反解时已把重型 0.3 与 `g.enemy_kb_mult` 算进去——
所以「拉拢 40」就是实际被拉 40 像素，**拿到 #103「安洁莉娜的创想」（受到的击退 +40%）她拉得远 40%**，和斯卡蒂 / 塞雷娅的击退吃同一个倍率。离散步进多走约半帧（单元测试：< 3% + 2 像素）。

### 12.2 积木写法

- 普攻：`shape.point_aoe`（r75、atk 20、1.1 秒）→ `then: verb.displace pull r100 dist 40`，被拉动的敌人（精一起）`st.weightless 2 秒 ×1.3`；精二起落点 r30 内 `st.airborne 0.6 秒`（`cond: elite >= 2`，即普攻质变「失重」）。
- S1：`dur.next_n 3` + `attack_patch {r_mult 1.4, force_mult 2.0, src 秘杖·速充模式, on_hit [st.stun 0.6]}`（精英 0.3）。
- S2（永久）：`verb.field r150 ring110 every 0.5 look ring` → `verb.displace dir ring dist 30`（+ 失重）；`verb.buff_leader move_speed ×1.08`。
- S3（10 秒）：`verb.field r220 every 0.2 look lift` → `st.airborne 0.5`（精英 1.5 秒托起 / 0.5 秒落地）、`verb.displace dir center 30/秒`、`st.slow boss_only`；`aura.aspd squad +20%`、`verb.heal 1%/秒`、`buff_leader move_speed ×1.15`、`pickup ×3`。
- 天赋：`verb.buff_self force_lit +0.2`（失重写在普攻 / S2 的 `on_hit` 里，`cond: elite >= 1`）。
- 成长：`wide` = `area ×1.15`；`dense` = `dmg ×1.15`；`pull2` = `trig.on_impact delay 0.3` → 落点 r75 ×0.5 伤害 + r100 拉 20；`lock` = 另一块 `verb.field`（同 S2 圆心半径，`cond: skill_active:1`，`st.dot 0.2 where ring ±30`，每秒）。

### 12.3 画面与音效

- 帧条：Codex 正式帧条 `op_angelina_*`（docs/64 验收通过），出手帧 attack f2 / skill f3；重力弹从杖头 (+34, −80)（docs/64 §5.2）飞出，带 26 像素弧高。
- 特效帧条（docs/25 §6）：`proj_angelina_orb`（重力弹，S1 强化弹放大 1.35 倍）、`fx_angelina_pull`（落点拉拢，按拉拢半径缩放，上限 3.2 倍 ≈ 96 像素）、`fx_angelina_levitate`（悬浮敌人脚下循环）。
- 程序画（`draw_auras`，地面层）：S2 重力场 = 场内淡紫底 + 环带 24 段虚线缓慢旋转 + 外圈往里 / 内圈往外的相向光点；S3 = 大圆脉动 + 外缘反向旋转虚线 + 上升光点；落点预示圈随弹飞近收缩。全部只读 `g.t`，不碰随机数。
- 技能图标 `skill_angelina_s1..3`（docs/25 §6 批 3）。音效 `sfx.gd OP_ALT` 借用：普攻 ← Logos 普攻 ×0.7、落点 ← 铃兰命中 ×0.7、S1 ← Logos S1、S2 ← 铃兰 S2 ×0.6、S3 ← 流明 S3 ×1.15。

### 12.4 与 docs/59 §5 的差异

1. **「拉拽吃 enemy_kb」不是天赋**：位移走 `e.kb`，#103 倍率从招募起就生效（和藏品描述「受到的击退 +40%」同一个口径，没有理由只在精一后生效）；`talent_kb_scale` 删掉。
2. **「主控在灯光内时拉拽 +20%」**：主控永远在自己的灯光里，这条会恒成立。改为「灯光照亮范围内（`lamp_radius`，同『光中敌人受伤 +25%』）的敌人被拉得更远 +20%」：灯火高时范围大、更容易吃到。
3. **`grav_t` 标记改成 `st.weightless`**（docs/60 的名字）：除了别人的 `melee_hit / area_hit` 击退 +30%，她自己的拉拽 / 环带也 +30%。其他直接写 `e.kb` 的击退（浊心斯卡蒂音符、维什戴尔炮弹等）不吃。
4. S1 次数型打完之前照常充能（同维什戴尔 S1），再放重置为 3 发。
5. S3「Boss 只减速 30%」→ 本作只有一种减速状态（−35%），Boss 在场内吃 `st.slow`；「悬浮敌人掉落的经验被吸向主控」按 docs/59 的实现注记做成 S3 期间拾取范围 ×3（全局）；队友攻速 +20% 用 `aura.aspd scope squad`（含她自己），乘技能强度。
6. 「双重引力」的 50% 同时作用于伤害（落点 r75）和拉拢（20）；「潮汐锁」环带宽 ±30（`lock_w`）。
7. 精二「失重」不登记伤害来源（只控不伤），`hit_sources.失重` 删掉；节点 2 图标用 `growth_b_size`（没有 `growth_b_atk`，同浊心斯卡蒂）。
8. S2 / S3 半径乘 `op_range`；落点 / 拉拢半径乘本干员 `area`（节点「引力扩散」），不乘 `op_range`。

9. **`aoe` 60 → 75**（docs/59 §5「纯拉拽清不动骨潮时先加 aoe（60 → 75）」）：60 时本机冒烟 Ⅷ 4 / 12，主控死在 5–8 分钟的大群里；75 后标准 / Ⅷ 都是 6 / 12（§12.6）。

### 12.5 测试

- 核心契约（`tests/test_core.gd test_blocks_angelina`）：angelina.json 通过校验；12 种改坏写法被拒（放错位置、`dir ring` 不在力场、力场没子项、`where ring` 但没 `ring`、`st.dot` 不在力场、次数型写成永久、`attack_patch` 坏键 / 跟错外壳、主控属性不在白名单、失重倍率 < 1、触发器 do 放常驻积木、位移越界）；位移反解在 m = 1 / 0.3 / 1.4 × 15 / 40 / 80 像素下与步进模拟相符；`kb_taken` 失重期间 / 过期；悬浮高度起止为 0、中段满高。
- 老干员同 seed：见 §12.8。

### 12.6 冒烟（10-11，本机，`--maxt=1000`，含超时口径）

「她占全队」= 重力弹 + 秘杖·速充模式 + 双重引力 + 潮汐锁 占全队 `out`；主控局是单人开局、自然招募。

| 组 | aoe 60（docs/59 原值） | **aoe 75（现值）** | 她占全队（现值） |
|---|---|---|---|
| 主控 · 标准 · 高手 seed 1–12 | 6 / 12（50%） | **6 / 12（50%）**，超时 1 | 33.5%（16–52%） |
| 主控 · Ⅷ · 熟练 seed 1–12 | 4 / 12（33%） | **6 / 12（50%）**，超时 2 | 36.8%（13–62%） |
| 队友 · 标准 · 高手（angelina_mate，7 名开局干员 × seed 1） | 5 / 7 | **6 / 7** | 25.1%（12–39%） |

- 队友局各开局干员：维什戴尔 胜（她 12%）、艾雅法拉 负（17%）、斯卡蒂 胜（23%）、水月 胜（28%）、塞雷娅 胜（33%）、凯尔希 胜（25%）、铃兰 胜（39%）；平均 25%，在 docs/59 §7 的 10–25% 上沿。
- 输出构成：她最大的来源是「秘杖·速充模式」（S1 三发 ×1.4 范围，平均占全队 13–18%），其次双重引力、重力弹各 5–9%。S1 打完之前照常充能，7 SP 的技能等于每 3–4 发普攻就有 3 发强化，偏强时先收 `s1_r`（1.4）或 `s1_n`。
- 结论：12 局的标准误约 ±14 个百分点，两档都在 50–70 的下沿，方向上没有越界；队友抬队伍、她占比不超 25%。数值不再动，等云端（§12.7）。对照铃兰（docs/61 §测试：同参数标准 6 / 12）持平。
- 截图：`build/batch3_impl/angelina/`（`select_angelina*.png` 选人页三个技能页签；`shot_*.png` 带艾雅法拉 + 斯卡蒂的满编局，S2 环带 + S3 悬浮场 + 重力弹飞行；`solo/shot_1650.png` 单人 S3 悬浮场里整圈敌人被托起、脚下挂 `fx_angelina_levitate`）。

### 12.7 云端命令（协调人建例行任务；与浊心斯卡蒂同口径）

```bash
# 主控：56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op angelina --bot expert --seeds 56 --seed0 1 --out build/cloud/an-lead-t0 --tag an-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op angelina --bot master --seeds 56 --seed0 1 --out build/cloud/an-lead-t1 --tag an-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op angelina --bot master --seeds 56 --seed0 1 --out build/cloud/an-lead-t2 --tag an-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友：7 名开局干员 × seed 1–8 = 56 局 × 三档（预设 angelina_mate）
python tools/balance_run.py --game game --jobs 4 --preset angelina_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/an-mate-t0 --tag an-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset angelina_mate --bot master --seeds 8 --seed0 1 --out build/cloud/an-mate-t1 --tag an-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset angelina_mate --bot master --seeds 8 --seed0 1 --out build/cloud/an-mate-t2 --tag an-mate-t2 --extra="--maxt=1000 --tier=2"
```

判定：主控三档各 50–70；队友局她占全队 10–25%、开局干员占比不低于同提交 starts；队友合计胜率比同提交 starts 高。同提交 starts 对照可复用 docs/61 §测试的 `sks-base-t0/t1/t2` 写法（四名新干员合入后跑一次即可，不必每人一份）。
旋钮：偏弱先加 `pull`（40 → 55），再 `aoe`（75 → 85）；偏强先收 `s1_r`（1.4）/ `s1_n`（3），再收 `s3_pickup`（3 → 2）与 `s3_aspd`；不动 S2 环带半径（队形手感）。
藏品 #103 对照（可选，docs/59 §5）：同命令加 `--relics=103`，预期胜率 +5–10 个百分点，> 15 收 `grav_kb`。

### 12.8 老干员同 seed 不变

对本分支合入 main 后、改动前的 903e9252，`--trace=1`，10:00：维什戴尔 + 铃兰 + 塞雷娅 seed 1、斯卡蒂 + 推进之王 + 凯尔希 seed 2、艾雅法拉 `--norecruit` seed 3、浊心斯卡蒂 + 维什戴尔 + 塞雷娅 seed 4、艾丽妮 + Logos + 流明 seed 5：
TRACE 与 BALANCE（去掉 prof 与画面峰值）**逐字节相同**。单人开局自然招募的局从第一次出招募卡起会分叉（招募池多了她），属预期。
## 13. 德克萨斯 `texas`（docs/59 §2 + §8.2，第二名纯数据干员，10-11）

见 `data/characters/texas.json` 的 `blocks`：**0 个 `custom`**，没有 `texas.gd`。docs/59 §10 预留的逃生口 `s3_chain`（剑雨滂沱 16 次连冲的时序）用积木拼掉了：
`trait` 里一块 `trig.tick {every: $s3_every, cond: "skill_active:2"}`，`do` = 一次 `shape.dash_line {aim: densest}` + `verb.sp_secs`；结束的剑雨是 `trig.on_skill_end {skill: 2}`。

### 13.0 10-12 改版：自动冲刺（用户「德克萨斯的技能你改成自动冲刺」）

- **天赋「战术快递」**：不再跟主控的冲刺键。她在编队里时，**自己按冷却自动冲**：`talent` 里一块 `trig.tick {every: $talent_cd（2.5 秒）, cond: "!skill_active:1"}`，
  `do` = 一次 `shape.dash_line {aim: densest, src: 战术快递}`（她本人朝 1.6 × 冲刺长度内敌群最密处冲刺穿行，沿线扫伤害，同疾行斩倍率；附近没有敌人就不冲）。
  穿过 ≥ 1 名敌人时全队技力 +0.8 秒（`trig.on_dash_end {src: 战术快递, min_hits: 1}` → `verb.sp_secs $talent_sp`）；一次穿过 ≥ 3 名再 +0.3 秒（疾行斩、战术快递各一块 `on_dash_end`）。
  她当主控时这次冲刺同样自动，带着主控本体冲（同普攻冲刺：不停顿、0.12 秒无敌）；**玩家自己的冲刺键与 `DASH_CD` 完全不变**。
- **S2「可靠伙伴」**：只强化**她自己**的冲刺——冲刺距离 +40%（`verb.dash_mod`）、伤害 ×1.3、自动冲刺间隔 ×0.8（2.5 → 2.0 秒：第二块 `trig.tick {every: "$talent_cd*$s2_cd_mult", cond: "skill_active:1"}`，与上一块条件互斥）。
  原来「主控冲刺冷却 −20%」撤掉：`game.gd` 的 `dash_cd_mult`、`stat_defs.gd` 的 `dash_cd`、HUD / 触屏 / 主控脚下冲刺环的冷却比例都恢复成 main 原样（game.gd 与 main 相同），`LEADER_STATS` 去掉 `dash_cd`。
- **S3「剑雨滂沱」**：照原设计（8 秒内每 0.5 秒向敌群最密处冲一次 ×0.9 + 眩晕 0.3 秒 + 全队技力 +0.4 秒，结束在最后落点落剑雨 ×1.6）。
- 新来源「战术快递」（`origin: talent`，`basic` / `pierce`）：天赋冲刺的伤害单独记账；它不触发「回马剑」（只认疾行斩），「余像」对所有冲刺生效。
- 积木：全用已有积木（`trig.tick` / `trig.on_dash_end` / `shape.dash_line` / `verb.sp_secs` / `verb.dash_mod` / `verb.buff_self`），只改了 `dash_line aim: densest` 一处——附近没有敌人时不起冲（原来朝面向随便冲），S3 也受益。
  `trig.on_leader_dash` 积木保留（校验与执行都在），只是德克萨斯不再用它。
- **本机冒烟（10-12，自动冲刺版，`--maxt=1000`，含超时口径，主控单人开局 seed 1–6）**：

  | 组 | 胜 | 她占全队 | 其中战术快递 | 备注 |
  |---|---|---|---|---|
  | 主控 · 标准 · 高手 | 3 / 6 | 20–52% | 3–9% | 输的 3 局都死在 5:09–5:35（卡门之后），承伤第一是泥沼（mire） |
  | 主控 · Ⅷ · 熟练 | 2 / 6 | 30–57% | 4–10% | 输在 4:57 / 4:59 / 6:57 / 10:28 |

  合计 5 / 12，低于改版前的 14 / 24（同口径 seed 1–12）。样本很小（±20 点），但早死集中在 5 分钟附近、泥沼承伤偏高，
  怀疑是她当主控时天赋冲刺把主控本体拖进敌群 / 泥沼。云端整轮先按现值跑；若主控确实偏低，旋钮顺序：
  ① 她当主控时天赋冲刺不带主控本体（只扫线，同旧 `leader_dir` 的 ride 写法）；② `talent_cd` 2.5 → 3.5；③ 再看 `hit_sp`。队友局不受影响。

### 13.1 新积木（`op_blocks.gd` 末尾「德克萨斯段」，append-only）

第三批四人并行实装，约定每人的新积木在文件末尾各占一段；核心部分只加转发，冲突时按段合并即可。

| 积木 | 类 | 参数 | 说明 |
|---|---|---|---|
| `shape.dash_line` | 瞬时（起冲；命中逐帧结算） | `r`（冲刺长度，× `op_range` × 冲刺长度倍率）、`w`（宽，× 冲刺宽度倍率）、`t`（用时，缺省 0.18）、`hold`（到头停顿）、`aim`、`mult / src / tags / power / on_hit`（同 `shape.circle`）、`strip`（剑光帧条，可选；合并时由 `fx` 改名，避开通用 `fx` 字段）、`sfx`（起冲音，可选） | 每帧扫「上一帧位置 → 这一帧位置」的线段，宽 w/2 + 敌人半径内、这次还没打过的敌人各吃一次（精英 / Boss 乘 `vs_elite`）。`aim`：`nearest`（普攻：最近敌人，索敌 = 长度 × 1.3；手动普攻 A 方向类）/ `densest`（长度 × 1.6 内最近 24 个敌人中 80 像素内邻居最多者）/ `leader_dir`（`g.dash_dir`）/ `reverse`（上一次冲刺的反方向）。先快后慢（ease-out）。**干员是主控时冲刺就是主控本体位移**（同乌尔比安弹射：squad.update 把 `g.ppos` 拉过去并给 0.12 秒无敌），且不停顿；`leader_dir` 且本干员是主控时不另行位移，跟着主控自己的冲刺扫。新的一次起冲先把正在冲的那次结算掉。普攻形状表加了它（`validate`），普攻只许 `aim: nearest` |
| `verb.sp_secs` | 瞬时 | `seconds`、`exclude_self`（缺省 true） | 编队各技能 +N 秒充能（推进之王 `_squad_sp_seconds` 的写法：不吃技力回复倍率，永久型跳过） |
| `verb.dash_mod` | 常驻 | `len_add / len_mult / w_add / w_mult` | 本干员冲刺长度 / 宽度倍率 `(1 + Σadd) × Πmult`（存在 `tx.len / tx.w`） |
| `verb.buff_leader` | 常驻 | `stat`、`op: add / mult`、`value` | 合并后归「共用积木」（与安洁莉娜一份，`move_speed / pickup`）；德克萨斯 10-12 改版后不再用（原来写 `dash_cd`） |
| `verb.trail` | 瞬时（放在 `trig.on_dash_end`） | `life`、`mult`、`src`、`tags`、`on_hit` | 沿刚结束的那次冲刺留 `life` 秒残像（宽 = 那次冲刺的宽），踩进的敌人每道残像各吃一次 |
| `verb.fx_scatter` | 瞬时、只有画面 | `strip`、`n`、`r`、`center: self / target`、`stagger` | 半径内撒 n 个帧条（错开起播）；黄金角序列取点，不碰 `g.rng` |
| `trig.on_dash_end` | 触发 | `src`（只认这个来源的冲刺，缺省全部）、`min_hits`、`delay` | 本干员任一次 `dash_line` 结束；`do` 里的 `verb.trail` / `aim: reverse` 读这次冲刺的起止点 |
| `trig.on_leader_dash` | 触发 | `cd` | 主控按下冲刺（`g.dash_t` 上升沿）；图鉴演示不触发。10-12 起德克萨斯不再用（见 §13.0），积木保留 |
| `trig.on_skill_start` / `trig.on_skill_end` | 触发 | `skill`（0 起）、`delay`（只 start） | 技能出手帧 / 持续型技能计时归零那一帧；`on_skill_end` 的 `center: target` 落在最后一次冲刺的终点 |

核心改动（都标了「德克萨斯段」）：`op_blocks.gd` 的 `validate`（普攻形状表）、`_block`（`TX_IMPL` 命中转 `_tx_block`）、`exec_shape`（`dash_line` 分支）；
`data_operator.gd` 加 `var tx` 与 6 处转发（`update` 冲刺中不起手、普攻起手点、`_sustain` 末尾 `tx_sustain`、`_exec_list` 缺省分支、`_release_skill` 后 `tx_skill_start`、`_draw_pfx` 画 `tx_strip` 粒子）。
帧条粒子 `kind: tx_strip`（合并时由 `strip` 改名，与通用 fx 的 strip 粒子分开；`strip / frames / fps / anchor / ang / sx / delay`）。

**game.gd**：10-12 自动冲刺改版后**不改 game.gd**（原来的 `dash_cd_mult` 冲刺冷却倍率已撤，见 §13.0）。

### 13.2 与 docs/59 的差异

1. **名字**：S1「剑雨」（原作名）、S2「可靠伙伴」（用户 10-11 定保留原创名）、S3「剑雨滂沱」（缄默德克萨斯三技能，用户 10-11 定）、天赋「战术快递」（原作天赋，docs/63 §6）。分支「尖兵」写进 JSON `branch`（目前没有界面读它）；`faction: 企鹅物流`。
2. **S3 不用 custom**（见本节开头）。S3 期间普攻停（`verb.mode no_attack`），第一次连冲在出手后 0.5 秒，技能计时归零那一帧不再冲，所以 8 秒实际 15–16 次；每次 ×0.9 × 技能强度、穿过的敌人眩晕 0.3 秒（精英减半、Boss 不晕）、全队技力 +0.4 秒；结束剑雨落在**最后一次冲刺的终点**，记在「剑雨」名下。
3. **主控时冲刺不停顿**（`hold` 只给队友）：主控每 1.1 秒被钉 0.15 秒手感太差。主控冲刺位移照乌尔比安的写法带 0.12 秒无敌。
4. ~~天赋同步冲刺~~（10-12 改为自动冲刺，见 §13.0）：她按自己的冷却朝敌群冲，来源「战术快递」，伤害同疾行斩倍率（含 S2 ×1.3）。
5. S2「疾行斩 ×1.3」与节点「利刃 ×1.15」写成 `verb.buff_self dmg`，乘她全部伤害（含剑雨 / 剑雨滂沱），与浊心斯卡蒂节点写法一致。
6. 「全队技力 +N 秒」只加给**除她以外**的队友（推进之王同），不吃技力回复倍率；单人开局招到人之前疾行斩回技力没有受益者。
7. 普攻「穿过 ≥ 1 名 +0.6 秒」只认「疾行斩」；天赋「穿过 ≥ 1 名 +0.8 秒」只认「战术快递」；「穿过 ≥ 3 名再 +0.3 秒」两者都认；都不认剑雨滂沱 / 回马剑。
8. 回马剑：疾行斩（含天赋冲刺）结束 0.2 秒后从**当时的位置**沿反方向冲同样长度；她是主控时也带着主控反冲。
9. 剑雨·连「重新瞄准」= 0.3 秒后以她当时脚下为中心。
10. 精二「余像」对她所有冲刺生效（含剑雨滂沱、回马剑、天赋冲刺）。
11. 选人页「攻击范围」读 `dash_len`（`initial_stats.gd` 的键表加一个）。
12. **机器人**：改自动冲刺前，高手（`--bot expert`）几乎不按冲刺，标准档天赋几乎不触发；10-12 起天赋与玩家 / 机器人操作无关，各档机器人口径一致。

### 13.3 接入登记

`balance.json operators.texas`（A，全 0）、`lore.json`（docs/59 §8.8 档案）、`tools/balance_run.py OPS` 与预设 `texas_mate`、`sfx.gd OP_ALT`（普攻 ← 艾丽妮普攻 ×1.15，命中 ← 艾丽妮命中，S1 ← 艾丽妮 S1，S2 ← 推进之王 S2，S3 ← 艾丽妮 S3；没有新音频文件）。
美术：Codex 正式帧条 `op_texas_*`（docs/64，返修 d954797d；发色 / 1x 徽记还在 Codex 返修中，换文件不用改 JSON），manifest 帧数 / fps / 出手帧（攻 5f14 / 1、技 7f12 / 3，脚底 (24, 46)）；
技能图标 `skill_texas_s1..3`；特效 `fx_texas_dash`（锚在终点、朝冲刺方向、横向拉到冲刺长度）与 `fx_texas_blade`（剑雨撒 12 柄，错开起播），docs/25 §6。

### 13.4 测试

- 快检全量 rc=0（47 项）；`test_core` 加 `test_blocks_texas`：texas.json 通过校验，11 条反例（aim 写错、普攻不朝最近、缺宽度、主控属性不在白名单、瞬时冲刺放进常驻节点、常驻 dash_mod 放进触发器、触发积木放进技能 do、on_skill_end 带 delay、on_dash_end 的 src 没登记、残像 mult 超上限、fx_scatter 缺帧条）全部被拒，`tx_sustain` 的倍率累计与主控属性修正。
- **老干员同 seed 不变**（对 texas-impl 合并底 70125472，`--trace=1`，10:00）：维什戴尔 + 铃兰 + 塞雷娅 seed 1、斯卡蒂 + 推进之王 + 凯尔希 seed 2、艾雅法拉 `--norecruit` seed 3、浊心斯卡蒂 + 流明 + 艾丽妮 Ⅷ 熟练 seed 4：TRACE 逐字节相同，BALANCE 只有 `bot.peak*`（画面峰值）不同。
  单人开局自然招募（铃兰 seed 4）：TRACE 从 1:16 起分叉（招募池 14 → 15 人，抽卡结果变了），属预期。
- 截图（开窗口，godot_runner 副屏）：`build/batch3_impl/texas/select_tab0..2/shot_oppick.png`（选人页三个页签）、`build/batch3_impl/texas/ingame/shot_*.png`（`--maxprog --sptest --realtime`，主控德克萨斯 + 维什戴尔 + 塞雷娅 seed 3：剑雨短剑、冲刺剑光、余像残线）。

**本机冒烟（10-11，`--maxt=1000`，含超时口径；「她占全队」= 疾行斩 + 剑雨 + 剑雨滂沱 + 回马剑 + 余像 占全队 `out`）**

| 组 | 胜 | 她占全队 | 备注 |
|---|---|---|---|
| 主控 · 标准 · 高手 seed 1–12 | **7 / 12（58%）** | 35%（20–56） | 输的 5 局死在 6:25–7:43 |
| 主控 · Ⅷ · 熟练 seed 1–12 | **7 / 12（58%）** | 25%（11–42） | 熟练会冲刺，天赋常触发 |
| 队友 · 标准 · 高手 `texas_mate` seed 1（7 局） | 4 / 7 | 20%（7–49） | 节奏位目标 20–35%；维什戴尔 7%、塞雷娅 49% 两头 |

脚本错误 0。两档主控都在 50–70 里（12 局标准误约 ±14 点）。

**云端整轮（同 skalter 口径：主控 56 局 × 三档、队友 7 名开局干员 × seed 1–8 × 三档、同提交 starts 对照）**：

```bash
# 主控：56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op texas --bot expert --seeds 56 --seed0 1 --out build/cloud/tx-lead-t0 --tag tx-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op texas --bot master --seeds 56 --seed0 1 --out build/cloud/tx-lead-t1 --tag tx-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op texas --bot master --seeds 56 --seed0 1 --out build/cloud/tx-lead-t2 --tag tx-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友：7 名开局干员 × seed 1–8 = 56 局 × 三档
python tools/balance_run.py --game game --jobs 4 --preset texas_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/tx-mate-t0 --tag tx-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset texas_mate --bot master --seeds 8 --seed0 1 --out build/cloud/tx-mate-t1 --tag tx-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset texas_mate --bot master --seeds 8 --seed0 1 --out build/cloud/tx-mate-t2 --tag tx-mate-t2 --extra="--maxt=1000 --tier=2"
# 同提交对照：starts × seed 1–8 = 56 局 × 三档（招募池已含她）
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 8 --seed0 1 --out build/cloud/tx-base-t0 --tag tx-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/tx-base-t1 --tag tx-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/tx-base-t2 --tag tx-base-t2 --extra="--maxt=1000 --tier=2"
```

判定：主控三档各 50–70；队友局她占全队 20–35%（docs/59 §7 节奏位）；对照推进之王单人同档差 ≤ 15 个百分点（docs/59 §2）。
旋钮（docs/59 §2）：偏弱先加 `hit_sp`（0.6 → 0.8）再 `atk`；偏强先收 `talent_sp`（1.0 → 0.7）和 `s3_sp`；不动冲刺距离（手感）。
## 14. 能天使的表达（docs/59 §4 + §8.4，第三批第四人，10-11）

见 `data/characters/exusiai.json` 的 `blocks`：0 个 `custom`，没有 `exusiai.gd`。帧条用 Codex 正式稿（docs/64，attack / skill 为 d954797d 返修的「枪保持水平」版），弹体与特效用 docs/25 §6 的 `proj_exusiai_bullet(_power)`、`fx_exusiai_muzzle(_gold)`、`fx_exusiai_hit`，技能图标 `skill_exusiai_s1..3`。

### 14.1 新积木（`op_blocks.gd` 末尾「能天使 exusiai」一段，只追加）

| 积木 | 类 | 参数 | 说明 |
|---|---|---|---|
| `shape.projectile` | 普攻 / 瞬时 | `every`（普攻）、`range`、`speed`、`shots`（1–12）、`spread_deg`、`pierce`、`kb`、`mult`、`elite_prio`、`focus_boss`、`fan`、`burst` / `burst_gap`、`tex`、`muzzle [x, y]`、`muzzle_fx`、`src`、`on_hit` | 自推进弹体（不追踪），命中走 `log_hit + deal_damage`，乘 `vs_elite`。子弹数 = `shots ×` 属性 `op_shots`（只对普攻）。各发独立索敌：候选 = `aim_targets`（自动 = 最近、保留 Boss 优先；手动 = B 类瞄准锥），按「距离 ÷ 精英优先度」再按 id 取前 n 个，目标不够时多出的子弹按 ±`spread_deg` 逐级错开；`focus_boss: true` = 头号目标是 Boss 时全部子弹打它；`fan: true` = 朝最近目标的扇形均布；`kb` 沿弹道击退（精英 ×0.3、Boss 不受，同 `melee_hit`）。枪口 = 脚底 + (`x × 朝向`, `y`)，瞄准 / 判定点 = 敌人脚底上方 10 |
| 外壳 `dur: {"ammo": N}` | — | `ammo` | 次数型（docs/61 §2 的 📝 `dur.ammo`）：出手帧装填 N 发，配 `attack_patch` 时普攻**每发子弹**扣 1 发、按补丁射，打完为止；HUD 环显示剩余 / 总数，装填期间不充能 |
| 技能 `attack_patch` | — | `mult`、`range_mult`（相乘）、`power`（取或）、`pierce`、`src`、`tags`、`tex`、`burst`、`burst_gap`、`elite_prio`、`spread_deg`、`focus_boss`、`kb`、`last_on_hit`、`muzzle_fx`（覆盖） | 技能生效期间（持续型 / 永久型）或有余弹时（次数型）改普攻弹道；`burst` > 1 时一次射击连射几轮，`last_on_hit` 只挂在最后一轮 |
| 技能 `end` | — | 瞬时积木列表 | 持续型技能计时归零那一帧执行一次 |
| `trig.on_attack` | 触发 | `counter`、`need`（缺省 = 该计数器当前上限）、`replace`（缺省 true）、`reset`（缺省 true）、`do` | 普攻出手时计数器 ≥ need：执行 `do`、清零，并换掉这一次普攻 |
| `verb.counter` | 瞬时 | `name`、`add`、`add_lit`（目标点在主控灯光半径内时用它代替 `add`）、`cap`、`set`、`own`（true = 只算本干员的击杀，看 `g.hit.op`）、`label`（状态条显示名） | 命名计数器 |
| `verb.counter_cap` | 常驻 | `name`、`value` | 改计数器上限（精英化 / 节点里写） |
| `verb.attack_lock` | 瞬时 | `dur` | 之后 `dur` 秒不普攻（技能照放） |
| `verb.ricochet` | 常驻 | `chance`、`r`、`mult`、`src` | 本干员子弹命中后掷 `g.rng`，命中则向 `r` 内离被击中者最近的另一名敌人（同距按 id）射一发 `mult` 倍的子弹，跳出的子弹不再跳 |
| `st.pause` | 命中时 | `dur`（0–2） | 短停顿：写 `e.stun`，只对非精英、非 Boss（`apply_status` 里加了这一分支，圆 / 锥的 `on_hit` 也能用） |

属性 `op_shots`（`stat_defs.gd`，基础 1，下限 1）：子弹数倍率，`add 1.0` = 单发干员多 1 发。`verb.buff_self` 的 `stat` 可写它（成长节点「双枪」、精英二），藏品也可以直接写：`{"type": "stat", "stat": "op_shots", "op": "add", "value": 1.0, "scope": "range:远程"}`（本次没有新增这类藏品）。

挂钩（通用代码里只插了这些行，都标「能天使挂钩」）：`op_blocks.gd` 的 `OP_STATS` 加 `op_shots`、`exec_shape` 加 `projectile` 分支、`apply_status` 加 `pause`、`validate` 的普攻形状列表 / 技能字段列表 / `dur` 对象分支 / `_exu_skill`、`_block` 开头 `_exu_block`；
`data_operator.gd` 加 `var ext`、`update` 里 `exu_tick` 与普攻 `projectile` 分支、`_exec_list` 的缺省分支、`_release_skill` 的 `dur` 对象分支、`skill_active_left` 取次数型余弹，末尾 `_draw_skill_over` / `status_items`。
没用到这些积木的数据干员（浊心斯卡蒂、eqtest）不建 `ext`、不走任何新分支，`blocks_eq` 逐字节相同。

### 14.2 能天使的数据表达

- 普攻「速射」：`shape.projectile`，`every $cd`（0.35）、`range 300`、`speed 520`、`shots 1`、`pierce 2`、`kb 30`、`spread 8°`、精英优先度 1.2、`focus_boss`、枪口 (+30, −35)（docs/64 §5.2 返修后的出手帧，@2x 像素 = 世界像素）；`atk 13`。
- S1「冲锋模式」：`dur {"ammo": 6}` + `attack_patch {mult 1.8, pierce 3, src 冲锋模式, 金色弹体, power}`。
- S2「扫射模式」：8 秒 `verb.mode {interval_mult $s2_cd/$cd, dmg_mult 0.9}`，`end: verb.attack_lock 1.0`（过热）。
- S3「过载模式」：10 秒 `attack_patch {burst 4, burst_gap 0.06, mult 0.8, range_mult 1.2, elite_prio 99, src 过载模式, power, last_on_hit: st.pause 0.2}`。
- 天赋「快速弹匣」：`trig.on_kill → verb.counter mag {own, add 1, add_lit 2, cap 8}`；`trig.on_attack {counter mag} → shape.projectile {shots 8, fan, ±25°, pierce 1, ×1.0, src 弹夹倾泻, 金色弹体与枪口焰}`。弹匣满时枪口挂一点金光，状态条显示「弹匣 n/上限」「冲锋模式 ×n」「过热」。
- 成长（顺序：双枪 → 高压弹 → 精英一 → 延长弹道 → 跳弹 → 精英二）：双枪 `buff_self op_shots +1`；高压弹 `buff_self dmg ×1.15`；延长弹道 `buff_self op_range +0.15`；跳弹 `verb.ricochet {0.4, 120, 0.5}`；精英二 `trig.passive {op_shots +1, counter_cap mag 12}`。
- 接入登记：`balance.json operators.exusiai`（S，atk +0.03、skill_power +0.03）、`lore.json`、`tools/balance_run.py OPS` 与预设 `exusiai_mate`、`sfx.gd OP_ALT` 借音（普攻 ← 维什戴尔普攻 ×1.9 −6 dB，命中 ← 艾丽妮命中，S1 ← 艾丽妮 S1，S2 / S3 ← 维什戴尔 S2 / S3，弹匣倾泻 big ← 维什戴尔 big）、`check.py` 场景回归 `exusiai_blocks`。选人页 / 图鉴 / 招募池按 JSON 自动列入（基础池）。

**与 docs/59 的差异**

1. 名字按 docs/63 §6：S1 冲锋模式、S2 扫射模式、S3 过载模式、天赋快速弹匣（§8.4 草案已改）；`faction: 企鹅物流`（新写，给将来德克萨斯协同用）。
2. 弹匣只吃**她自己的**击杀（`own`）。docs/61 §4 的 `trig.on_kill` 照旧是「谁杀的都算」，满编时队友的击杀会让弹匣几乎每发都满，倾泻就变成常态普攻。
3. 「灯光内 +2」= 被击杀的敌人在主控灯光半径内时 **+2 代替 +1**（docs/59「在灯光内翻倍」），不是 +1 再 +2；流明照亮的 `e.lit` 不算（积木拿到的只有位置）。
4. 「高压弹」是她**全部**伤害 ×1.15（局部 `dmg` 倍率），不只速射；图标用 `growth_b_size`（没有 `growth_b_atk`）。
5. S1 / S3 的子弹乘技能强度（`power`），S2 的 ×0.9 不乘；倾泻与跳弹不乘。
6. S3 每一轮重新选目标（目标在连射中被打死就换人）；连射与子弹数相乘（精英二 3 发 × 4 轮 = 12 发）。
7. 射击间隔短于 0.25 秒的攻击动作时（S2 0.20 秒、攻速加成），出手后把剩下的动作截短，射速不被动作拖慢。
8. 跳弹只从普攻 / 技能 / 倾泻的子弹起跳一次，半径 120 不吃射程加成；这是她唯一用 `g.rng` 的地方。
9. 过热只停普攻，技能照常起手。
10. **数值上调（本机冒烟，见 11.3）**：docs/59 原值（atk 9、不穿透）标准高手 3 / 12、Ⅷ 熟练 0 / 12（9 局死在 2:00 前后），对照维什戴尔同 seed 8 / 12、5 / 12。
    按 docs/59 §4 的旋钮先把「双枪」提前到第 1 节点、atk 9 → 10，早死消失但胜率仍在 10–25%；只加伤害（atk 13–16、S3 ×0.8、倾泻 ×1.0）胜率不动——她的问题不是总伤害，而是单体弹挡不住贴脸的冲锋怪。
    改成**普攻穿透 2 + 每发击退 30**（S1 强力弹穿透 3）之后同 seed 胜率翻倍。现值 `atk 13`、`pierce 2`、`kb 30`、`s1_pierce 3`、`s3_mult 0.8`、`mag_mult 1.0`、`focus_boss`（新：最近的是 Boss 时多发子弹全打 Boss）。docs/59「单体、无范围」的定位因此松动成「单体 + 穿透 + 轻击退」。
    主控胜率仍低于 50–70 的下沿（下表），等云端 56 局定；队友局反而偏强。

### 14.3 测试

- `python tools/check.py --only exusiai_blocks`（快检全量里也跑）：`tests/exusiai_blocks_test.tscn`，校验正反例 12 条 + 运行时 46 条（子弹数、枪口、命中与击退、S1 余弹与倍率、弹匣 +1 / +2 / 别人的击杀、倾泻 8 发 ±25°、精英二上限 12 与子弹数、S2 过热、S3 四连与最后一轮停顿、停顿不吃精英、跳弹、无跳弹时不碰 `g.rng`、浊心斯卡蒂不受影响）。

**本机冒烟（10-11 / 12，`--maxt=1000`，含超时口径，单人开局自然招募；「她占全队」= 速射 + 冲锋模式 + 过载模式 + 弹夹倾泻 + 跳弹 占全队 `out`）**

| 版本 | 主控 标准·高手 seed 1–12 | 主控 Ⅷ·熟练 seed 1–12 | 她占全队（主控） | 备注 |
|---|---|---|---|---|
| docs/59 原值（atk 9，不穿透，range 节点在前） | 3 / 12 | 0 / 12 | 36% / 70% | Ⅷ 9 局死在 2:00 前后（1:15 骨潮清不动，docs/59 预警过的情况） |
| 双枪提前 + atk 10 | 1 / 12 | 3 / 12 | 28% / 38% | 早死消失，死在 5–8 分钟 |
| + atk 13、S3 ×0.8、倾泻 ×1.0 / + focus_boss、atk 12 | 2 / 12、2 / 12 | 3 / 12、2 / 12 | 32–35% | 加伤害不加胜率 |
| + 穿透 2（atk 12），36 局 | 11 / 36（31%） | 9 / 36（25%） | 43% | |
| **+ 击退 30**（atk 12 / 14 / **13 现值**，各 24 / 24 / 12 局） | 12 / 24、12 / 24、**3 / 12**；合计 **27 / 60（45%）** | 11 / 24、8 / 24、**4 / 12**；合计 **23 / 60（38%）** | 40–48% | 主要死因 bullet（敌方弹幕）、contact_slider / tracer |
| 对照 维什戴尔（同参数，seed 1–12） | 8 / 12 | 5 / 12 | 55–57% | 主控每分钟伤害 39k / 50k，她 24k / 27k |

队友（`exusiai_mate`，7 名开局干员各带她开局，标准·高手 seed 1，现值）：**5 / 7**（对照同提交 `starts` seed 1：2 / 7）；她占全队 39%（16–66%，在 docs/59 §7 的 30–50 内）。

- 12 局一批的标准误约 ±14 个百分点，同一版本两批能差 50 点（穿透 2：标准 1 / 12 → 10 / 24）；结论只看 24 局以上的合计。
- 判断：主控两档都低于 50–70 的下沿（45% / 38%），对照维什戴尔差 7–25 点；队友偏强。没有继续往上加，等云端 56 局 × 三档再定；按上面的经验，下一刀先动 `kb`（30 → 40）或 `pierce`，不先动 `atk`。
- **10-12 合入 batch3-integrate 时按这条先动了第一刀：`kb` 30 → 40**（atk 不动；单独一个提交）。云端整轮在合入后的最终提交上跑。

**老干员同 seed 不变**（对本分支合入前的底 bf159d14，`--trace=1 --maxt=600`，高手）：维什戴尔 + 铃兰 + 塞雷娅（满编）seed 1、斯卡蒂 + 推进之王 + 凯尔希（满编）seed 2、艾雅法拉 `--norecruit` seed 3、浊心斯卡蒂 + 流明 + 艾丽妮（满编，数据干员）seed 4：
TRACE **逐行相同**，BALANCE 除 `bot.peak / peak_min`（画面峰值，docs/61 §测试 同样排除）外相同。单人开局自然招募（铃兰 seed 5）在第一次招募（1:12）起分叉——招募池 14 → 15 人，属预期。

**云端（协调人建例行任务；口径同 §测试 浊心斯卡蒂）**

```bash
# 主控：56 局 × 三档（seed 1–56）
python tools/balance_run.py --game game --jobs 4 --op exusiai --bot expert --seeds 56 --seed0 1 --out build/cloud/exu-lead-t0 --tag exu-lead-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --op exusiai --bot master --seeds 56 --seed0 1 --out build/cloud/exu-lead-t1 --tag exu-lead-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --op exusiai --bot master --seeds 56 --seed0 1 --out build/cloud/exu-lead-t2 --tag exu-lead-t2 --extra="--maxt=1000 --tier=2"
# 队友：7 名开局干员 × seed 1–8 = 56 局 × 三档
python tools/balance_run.py --game game --jobs 4 --preset exusiai_mate --bot expert --seeds 8 --seed0 1 --out build/cloud/exu-mate-t0 --tag exu-mate-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset exusiai_mate --bot master --seeds 8 --seed0 1 --out build/cloud/exu-mate-t1 --tag exu-mate-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset exusiai_mate --bot master --seeds 8 --seed0 1 --out build/cloud/exu-mate-t2 --tag exu-mate-t2 --extra="--maxt=1000 --tier=2"
# 同提交对照：starts × seed 1–8 × 三档（与 sks-base-* 同口径；招募池已含她）
python tools/balance_run.py --game game --jobs 4 --preset starts --bots expert --seeds 8 --seed0 1 --out build/cloud/exu-base-t0 --tag exu-base-t0 --extra="--maxt=1000 --tier=0"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/exu-base-t1 --tag exu-base-t1 --extra="--maxt=1000 --tier=1"
python tools/balance_run.py --game game --jobs 4 --preset starts --bots master --seeds 8 --seed0 1 --out build/cloud/exu-base-t2 --tag exu-base-t2 --extra="--maxt=1000 --tier=2"
```

判定（docs/59 §7）：主控三档各 50–70，对照维什戴尔相差 ≤ 15 个百分点；队友局她占全队 30–50%。旋钮：偏弱先把「双枪」节点提前到第 1 节点、再 `atk` 9 → 10；偏强先收 `s3_mult`（0.7 → 0.6）、`mag_mult`（0.8 → 0.65），不动 `cd 0.35`。
