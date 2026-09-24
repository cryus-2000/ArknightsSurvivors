# 14 · 藏品系统合一（v1.5）

> 开发方（Claude）实现文档，2026-09-24。把原来并存的三套藏品表合成一套。

## 1. 结果

| 之前 | 现在 |
|---|---|
| `data.gd RELICS`（23 件原创，实际在跑）+ `COMBOS`（5 组合） | **删除**。原创藏品与组合按 docs/08 的决定不再出现；发光水母 / 涨潮螺壳 / 组合的代码一并移除 |
| `scripts/relics.gd`（164 件，0 引用） | **删除** |
| `data/relics.json`（262 件元数据）+ `data/relic_effects.json`（43 件有效果） | **唯一数据源**。效果补到 **71 件**（首批 62 + 护盾 6 + 3 件已有效果），编号即原作编号，图标 `art/incoming/relic_<编号>.png` 直接对上 |

## 2. 接法

- `scripts/core/relic_db.gd` 读两份 JSON（加了 `cat` 字段透传），只有 `relic_effects.json` 里有 `effects` 的藏品进池。
- `scripts/relic_fx.gd`（新）：把 effects 落到 game.gd 的变量与钩子上，**不经过 ModifierSystem / StatBlock**（游戏状态还没迁进去；等阶段 3 再换）。
  - `stat`：映射到 `dmg_mult / u_dmg_mult / t_mult / ally_mult / arts_mult / enemy_dmg_mult / enemy_hp_mult / enemy_cd_mult / low_hp_bonus / regen_pct / dodge / dodge_melee / dodge_ranged / sp_mult / control_mult / shop_price_mult / lamp_decay / dmg_taken_mult / max_hp / shield_max / shield_every`。
  - `trigger`：game.gd 在对应时机调 `rfx.on_dodge / on_skill_start / on_hurt / on_death / on_kill / on_hit / on_tentacle_hit / sniper_execute / single_hit_mult`。
  - `rule`：`black_tulip / king_crown / king_gun / king_cake / king_branch / low_light_sp / coin_toy / four_choices / revive_once / tree_light / shield_burst / shield_heal`。
  - `status`：受控（晕眩 / 减速）敌人每 0.5 秒受法术伤害。`spawn`：地雷。`on_gain`：灯火 / 源石锭。
  - 每次伤害查询的动态倍率：`dmg_extra()`（限时增伤、国王的冠冕、黑色郁金香、刻勋之手）、`umbrella_interval_mult()`（极速之手、国王的新枪、投币玩具 / 骑士戒律）、`taken_mult()`（佣兵保单、国王的圆饼）、`sp_extra()`（火油与药膏、国王的枝条）。
- 抽取：`_relic_pool_ids(for_shop)` 用 `relic_db.pool()` 过滤（已实装、未拥有、满足 `requires`），再按稀有度加权：基础 60 / 稀有 26 / 核心 12 / 升华 3（7:00 后才出）；护盾系 7:00 前 ×1.6。**遭诅古物只在商店出现**（权重 8，价 6，名字前标【遭诅】）。
- 商店价格走 `relic_db.price(id)`（基础 10 / 稀有 14 / 核心 20 / 升华 30 / 遭诅 6）× `shop_price_mult`（锈蚀的铁锤）。四叶草化石：三选一变四选一（藏品与升级都生效）。
- 卡片标签显示「分类 · 稀有度」；分类颜色补进 `ui.gd CAT_COL`。
- 字体子集现在把 `data/*.json` 里的藏品名与描述也算进去（**以后改 JSON 文案要重生成字体**）。

## 3. 新补效果（25 件）

28/29 源石锭、31 灯火、43 敌攻 −12%、48/49 敌血 −15%/−10%、55 伞击 +25%、58/59 援护 +25%/+35%、66/68 法术伤害 +20%/+40%、73/74 近战/弹幕闪避 +15%、79 全伤 +30%、94 受伤回技力、96 受控敌人受伤 90%、98/99 控制时长 +110%/+150%、114/126/127 国王套装（低血攻速 / 减伤 / 技力）、190 四选一、200/202 护盾、208 骑士戒律、218/220 灯火消耗、243 深蓝之树（敌攻速 +15%，60 秒未受伤灯火 +15）。

## 4. 未做 / 待定

- 升华藏品现在只是 7:00 后小概率进普通池；设计上应是第二个 Boss 的专属奖励（Boss 三选一还没做）。
- 遭诅古物没有"风险交易"（换取收益），只是便宜的负面品。
- 210 支援地雷组、89 羽兽肝酱、231 小格兰法洛已有效果但没有图标。
- 原创 17 件的图标（`relic_backlight.png` 等）现在没有用到。
- `--relicshot` 测试参数：第 30 帧强制一次藏品三选一并截图，第 400 帧开商店。
