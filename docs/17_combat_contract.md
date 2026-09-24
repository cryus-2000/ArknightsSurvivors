# 17 · 战斗契约：伤害描述符、三技能制、能力标签（v1.8）

> 2026-09-24，基于 refactor ①–④ 之后的结构（`characters/`、`data/characters/<id>.json`）。目的：**第二个干员只新增 `characters/<id>.gd` + `<id>.json`，藏品与统计不认角色。**
> 来源：GPT 的《19 · 三技能制、跨角色 Tag 与共享 Build 修改建议》，只取其中最小可落地的三项；事件总线、能力画像、掉落匹配、十个藏品原型不在本轮。

## 1. 伤害描述符（替代 `out_src` 字符串）

每次造成伤害前调用 `g._hit(src, extra_tags)`，`_damage` 与藏品规则只读 `g.hit`：

```text
src      来源名（统计与 Tab"本局构成"显示）
emitter  operator / summon / support / relic        谁出手
origin   core / talent / skill / route / support / relic   来自哪一层
range    近战 / 远程
kind     物理 / 法术 / 真实（真实不吃任何倍率、防御、弱点）
tags     basic empowered follow_up skill echo aftershock area projectile beam pierce ricochet entity control dot detonation execute
```

- 共享来源在 `game.gd HIT_BASE`（无人机、援护、藏品、地雷、真实）。
- 角色专属来源在角色 JSON 的 `hit_sources`，加载时合并。水月：伞击 / 技能 / 技能·法术 / 触手 / 触手桩 / 触须阵 / 巨触 / 水刃 / 潮汐弹。
- 本次特有标签用第二个参数追加：`_hit("伞击", ["empowered"])`（唤醒）、`_hit("技能", ["echo"])`（镜像）。
- 统计：`dmg_out`（按 src）、`dmg_type_out`（按 kind）、`dmg_tag_out`（按 tag）；`--balance` 输出 `out / out_type / out_tag`。

**藏品规则改读描述符**：扣挠之手 / 炸裂之手 = `tags 含 follow_up`（不再是"触手"）；扼喉之手 = `src == 援护`（支援层，非角色层）；荣耀绶带由角色的基础攻击传入本次不同目标数。仍带角色前缀的属性（`mizuki_umbrella_dmg`、`mizuki_tentacle_mult`、触手目标 +1）按 docs/09 的约定保留在角色前缀属性里。

## 2. 三技能契约

- 每名干员**恰好 3 个核心技能**，`mode` 为 `auto` 或 `manual`，`manual` **最多 1 个**。基础攻击与天赋不占槽；技能进阶、E1/E2、藏品只能改造这三个技能。
- `Character.create()` 时 `validate_skills()` 校验，不合法 `push_error`。
- 技能表字段：`mode`（释放方式）、`trigger`（count / sp / input…，只是说明）、解锁等级仍在 `skill_unlock()`；三者独立，解锁顺序不由技能编号决定。
- **唯一手动入口**：Space / J → `ch.try_manual_skill()`；三自动角色返回 false（水月）。两自动一主动的角色在这里做"已解锁？资源够？"校验后施放，成功才触发 `rfx.on_skill_start()`。
- 镜像 / 回声只复制攻击（带 `echo` 标签），不重发技能事件、不重算计数；唤醒计数在挥伞那一刻消费。

## 3. 能力标签

- 角色 JSON `gallery.tags`：3–5 个玩家能懂的词（水月：近战 · 追击 · 控制 · 范围 · 法术追击），显示在图鉴干员页与 Tab 面板标题行。
- 这是**展示用**，不驱动任何数值；驱动数值的是描述符里的 `tags`。
- Tab 面板"本局构成"：按 src 的前三名占比，让玩家看到自己的 Build 实际靠什么打。

## 4. 新干员接入清单

1. `data/characters/<id>.json`：`skills`（3 个 id）、`hit_sources`、`gallery.tags`、`stats` / `base` / `sprites` / `evo`。
2. `scripts/characters/<id>.gd`：继承 `character.gd`，实现 `update / skills / skill_unlock / try_manual_skill（若有）/ growth_table / evo_*`，所有 `_damage` 前先 `g._hit(src, tags)`。
3. `data.gd` 里的 `SKILLS / SKILL_ADV / SKILL_P` 目前仍是水月的表，第二个角色到来时随 `skills()` 接口一起搬进各自 JSON（另一个会话的"水月技能表搬 JSON"排在它的下一步）。
4. 不允许：第四个可施放动作、角色 ID 写进藏品规则、为角色单独造藏品池。

## 5. 与另一个会话的分工（避免同时改 game.gd 同一区域）

- 本会话：`_damage` / `_hit` / 藏品规则 / 技能契约 / 手动入口 / Tab 与图鉴标签 / 第二个干员的 `.gd + .json`。
- 另一会话：援护、无人机、商店、掉落再拆模块；选人界面；水月技能表搬 JSON。
- 都遵守：先 `git pull` 式核对 HEAD，三方合并，只提交自己的文件。
