# 09 · P0 底层架构方案（Event / Modifier / Stat / Tag / Build Profile）

> 依据：全局框架 v1.0 第 27–33、35 节。本文说明 P0 的代码结构、数据格式，以及怎么把现有 `game.gd` 迁移过来。
> 状态（2026-09-24 晚）：**StatBlock 已接入 game.gd（docs/14 ③）：藏品 / 成长 / 难度的数值修正都经 `stats.add()`，旧变量只是同步缓存。** 事件总线与 ModifierSystem 的触发型效果仍由 `relic_fx.gd` 的 on_*() 钩子承担，见第 6 节。

---

## 1. 模块一览

全部在 `game/scripts/core/`，都是不依赖场景的 `RefCounted`，可以在无界面模式下单独测试。

| 文件 | 框架对应 | 作用 |
|---|---|---|
| `events.gd` | 28 Combat Event System | 事件名常量与负载约定 |
| `event_bus.gd` | 28 | 订阅 / 广播；优先级；按 owner 整体退订；嵌套深度上限 6（防止藏品互相触发死循环）；广播计数 |
| `stat_block.gd` | 30 Stat System | Base → Flat → Additive% → Multiplicative → Override → 上下限；每条修正带来源，可整体撤销；`breakdown()` 给属性面板用 |
| `stat_defs.gd` | 30 | 所有可修正属性的登记表（公共属性 + `mizuki_*` 专属 + 敌人全局属性），每项注明对应的旧变量 |
| `modifier_system.gd` | 29 Modifier System | 执行效果数据：stat / trigger / status / spawn / rule / on_gain；条件判断；冷却；限时修正；有上限的永久累加 |
| `build_profile.gd` | 31 Build Profile、35 测试标准 | Tag 权重、流派得分、主流派、相关度；伤害来源占比、击杀来源、承伤来源、灯火均值、成型时间 |
| `relic_db.gd` | 32 RelicData、13 商店、17 Boss 奖励 | 读取藏品表；候选池（前置 / 冲突 / 已拥有）；三个商店阶段的权重与 Soft Steering；精英箱；Boss 奖励规则 |
| `combat_core.gd` | — | 统一入口：`game.gd` 只持有一个 `core` |

数据：

| 文件 | 内容 |
|---|---|
| `game/data/relics.json` | 262 件藏品的名称、等级、流派、Tag、商店可否（由 `docs/08` 生成，勿手改） |
| `game/data/relic_effects.json` | **已实装**藏品的效果数据。只有写了效果的藏品才进随机池。当前是 43 件示例，覆盖全部效果类型 |

测试：`game/tests/test_core.gd`

```text
godot --headless --path game -s res://tests/test_core.gd
→ 37 checks, 0 failed / CORE TESTS PASSED
```

---

## 2. 属性（Stat）

- 计算：`value = (base + Σflat) × (1 + Σadd) × Πmult`，有 override 取最后一条，最后按上下限截断。
- 同类加成**加算**（两件 +15% = +30%），不同层之间乘算。旧代码里 `dmg_mult *= 1.15` 是连乘，迁移时用 `add` 会让叠多件时略弱一点；若要保持原手感，旧成长项先用 `mult`。
- 属性名规则：公共属性无前缀（`dmg`、`max_hp`、`sp_gain`…），角色专属用角色前缀（`mizuki_umbrella_dmg`），敌人全局属性用 `enemy_`。新干员加入时只新增自己的前缀属性。

## 3. 事件（Event）

| 事件 | 负载 | 发出位置（迁移时） |
|---|---|---|
| AttackStarted | src, tags | `_umbrella()` 开头、援护 `_ally_start()` |
| Hit | src, target, amount(可改), tags, hit_count | `_damage()` 结算前；伞击一次挥砍命中数写进 hit_count |
| DamageDealt | src, target, amount, tags | `_damage()` 结算后 |
| DamageTaken | amount(可改), by, tags, blocked(可改) | `_enemy_hit()` / `_hurt()`；护盾抵挡时 blocked=true |
| EnemyKilled | src, target, elite, boss | `_kill()` |
| SkillStarted / SkillEnded | skill, branch | `_skill_cast()`、技能持续时间结束处 |
| StatusApplied | status, target, duration(可改), src | 触手束缚 / 晕眩、辅助减速、侵蚀、神经损伤 |
| Dodge | source_enemy | 现有空函数 `on_dodge()` |
| LightChanged | before, after, reason | 灯火每次非自然变化（灯油、受击、黑潮、藏品） |
| SupportAttacked | kind, lv, target | `_ally_release()` |
| BossKilled | target, index | `_kill()` 里 Boss 分支 |
| LevelUp / RelicGained / Healed / ShieldBroken / Tick | — | 对应位置；Tick 每帧一次 |

伤害来源 `src` 统一用：`umbrella`、`tentacle`、`s1`、`s2`、`s3`、`sniper`、`caster`、`medic`、`support`、`drone`、`field`、`tide`、`relic:<id>`。`_damage()` 需要加一个 `src` 参数（现在没有），这是迁移里改动最大的一处。

## 4. 效果数据（Modifier）

```json
"120": {"effects": [
  {"type": "trigger", "event": "Dodge", "do": "temp_stat",
   "args": {"stat": "dmg", "op": "add", "value": 0.7, "dur": 6.0}}
]}
```

| type | 用途 | 例子 |
|---|---|---|
| stat | 常驻属性修正 | 老近卫军之锋：`mizuki_umbrella_dmg +35%` |
| trigger | 监听事件 → 条件 → 动作 | 《光耀卡西米尔》：闪避后 6 秒伤害 +70% |
| status | 改变状态效果，游戏查询 `status_args("bind")` | 悬丝傀儡：被束缚 / 晕眩的敌人持续受伤 |
| spawn | 周期生成 | 支援地雷组：每 20 秒一枚地雷 |
| rule | 开关 / 计数规则，游戏查询 `rule("revive_once")` | "时光之末"：复活一次 |
| on_gain | 获得时执行一次 | 夜阳花：灯火 +10 |

- 条件 `if`：`chance`、`light_below/above`、`hp_below/above`、`target_boss`、`target_elite`、`target_hp_below`、`src_is`、`tags_any`、`no_allies`、`hit_count_max`。
- 内置动作：`temp_stat`（限时，默认刷新不叠层，`max_stacks` 可叠）、`add_stat`（永久累加，`cap` 上限）。
- 游戏要注册的动作：`light`、`ingots`、`heal`、`sp`、`stun_all`、`damage_all`、`damage_area`、`execute`、`bonus_current_hp`、`scale_hit`、`spawn`。
- `core.validate()` 会检查效果里的属性名、事件名、动作名、前置藏品是否存在，启动时和测试时都跑。
- 技能分支、援护、武器、排异反应、难度都走同一个入口 `core.apply_source(id, effects, tags)`，不再各写一套。

## 5. Build Profile 与统计

- 每个来源（藏品、技能分支、援护、武器）登记 Tag，累加成 Tag 权重。
- 流派得分 = Tag 权重 × 流派系数（A 伞击 / B 触手 / C 控制技能 / D 收割 / E 低灯火 / S 援护）。领先第二名 20% 且达到门槛才算「主流派」，第一次成为主流派的时间记为**成型时间**。
- `affinity(tags)` 给商店和 Boss 奖励做**轻微**倾向（商店第二阶段权重最多 ×1.6），不强制。
- `snapshot()` 输出框架第 35 节要求的统计：最终 Tag、伤害来源占比、击杀来源、承伤来源、平均灯火、成型时间、死亡原因。接入后，`--balance` 自动测试的输出里带上这份数据，用来判断「不同的局伤害结构是否真的不同」（框架第 36 节）。

## 6. 接入 `game.gd` 的步骤（待协调）

**为什么还没接**：v0.8 由另一个开发会话提交（`d0f7dbc`），而且那个会话在 v0.8 之后还有未提交的改动在 `game.gd` 上。P0 迁移要改动 `game.gd` 的几十处（约 5000 行里所有属性读写、伤害结算、藏品），两边同时改一定会冲突。所以这次先把核心模块做成独立文件，**不碰 `game.gd`**。

建议由正在开发 `game.gd` 的那个会话，在它的改动提交后按下面顺序迁移，每一步都跑一次 `--balance` 对比数据：

1. **挂载**：`var core := Core.new()`，`_ready()` 里 `core.load_data()`，断言 `core.validate()` 为空；每帧 `core.tick(dt, lamp, t)`；一局结束 `core.dispose()`。
2. **属性**：按 `stat_defs.gd` 的 `old` 字段，把 `max_hp`、`speed`、`dmg_mult`、`u_dmg_mult` 等 20 个变量换成 `core.stats.value(&"...")`；`_apply_growth()` 改成 `core.apply_source("growth:%s#%d", [...])`。
3. **伤害管线**：`_damage(e, dmg)` → `_damage(e, dmg, src, tags)`，内部发 Hit（可改 amount）与 DamageDealt；`_enemy_hit` / `_hurt` 发 DamageTaken；`_kill` 发 EnemyKilled / BossKilled；`on_dodge()` 发 Dodge。
4. **动作注册**：在 `game.gd` 里实现第 4 节列出的 11 个动作。
5. **藏品**：删掉 `D.RELICS`、`D.COMBOS`、`_apply_relic()`、`_check_combos()` 里的原创藏品；`_open_relic_choice()` 改用 `core.db.roll_chest()`；Boss 掉落改为 `roll_boss()`；`_roll_shop()` 改用 `roll_shop(stage)`，刷新费用逐次增加。v0.8 的 6 件护盾藏品已写进 `relic_effects.json`（118 / 199 / 15 / 100，另 2 件待补）。
6. **统计**：`--balance` 结束时打印 `core.profile.snapshot()`。
7. **导出**：`export_presets.cfg` 的 `include_filter` 需要加 `data/*.json`，否则导出的游戏读不到藏品表（本次已加）。

完成后，框架第 33 节的验收标准：新加一个干员只需新增 OperatorData、基础攻击、技能、专属 Tag 和动画，不用改商店、藏品、Boss 奖励、经济、灯火、Modifier、Event。

## 7. 之后（P1）

- 技能互斥分支：每个分支就是一组 effects + tags，走 `apply_source("branch:s1_a", ...)`。
- 首批 62 件藏品的效果数据补全到 `relic_effects.json`（现在 43 件）。
- Boss 核心奖励 UI（三选一，标出与当前流派的相关性）。
