# 369 新主题接入清单（11-18）

**状态：现行规范。** 一个新主题包要提供哪些文件、字段、接口和测试。以水月（`deep_sea`）为样板，傀影（建议 id `phantom`，内容见 docs/358、360–363）照着填 §8 的表。实现背景：docs/357（方案）、359（基准 / 清单）、364（机制接口）、366（存档按主题）、367（数据搬家 / 敌种 id）、368（第五步）。

> 现状提醒：**核心还不能真正切到第二个主题**——没有选主题入口（`ThemePack.id()` 恒为 `deep_sea`），标题页 / 配乐仍是 preload，骑士同伴在核心里有 85 处直读，渲染 / 图鉴 / HUD 里还有按敌种写死的分支。§7 列了这些阻塞点。本页先把「包里要放什么」定死，傀影的数据、Boss、美术可以照着并行做。

## 1. 目录

```
game/themes/<id>/
  theme.json                 # 清单（§2）
  data/                      # 主题数据（§3）
    waves.json  enemies.json  events_v2.json  relics.json  relic_effects.json
    medals.json  medals_layout.json  enemy_pixels.json  enemy_redraw.json
    lore.json  guide.json  onboard.json        # 混合文件的主题部分（§3.3）
    maps/<地图 id>.json
  mech/                      # 主题机制（§4），继承 scripts/core/theme_mechanic.gd
  mod/                       # 主题模块（§5），_init(game)
（Boss 脚本目前仍在 game/scripts/enemies/bosses/<名>.gd，按 enemies.json 的 script 字段找；美术在 game/art/…，按 art/index.json 名字找）
```

导出：`themes/*/theme.json`、`themes/*/data/*.json`、`themes/*/data/maps/*.json` 已在两个导出预设与 `encrypted_release` 的 include_filter 里；脚本（`.gd`）是资源，自动进包。字体子集、`check_release`、`data_lint`、l10n 抽取都已扫 `game/themes/**`。

## 2. `theme.json`

| 段 | 必填 | 内容 |
|---|---|---|
| `id` / `name` | ✅ | 与目录名一致的 id；显示名 |
| `data` | ✅ | `{键: "res://…json"}`。代码经 `ThemePack.path(键)` / `ThemePack.load_merged(键)` 读。必须有的键：`waves`、`enemies`、`events_v2`、`relics`、`relic_effects`、`medals`、`medals_layout`、`enemy_pixels`、`enemy_redraw`、`lore`、`guide`、`onboard`、`doctor`、`meta_tree`、`meta_roots`、`ult_text`、`ult_audio`（后五个共享，照抄水月指向 `res://data/…`） |
| `maps` | ✅ | `{"dir": "res://themes/<id>/data/maps", "default": "<地图 id>"}` |
| `mechanics` | 可空 | `[{"id", "script"}]`，顺序 = 同一挂钩点的调用顺序（§4） |
| `modules` | 见 §5 | `{键: 脚本}`，挂在 `g.<键>` |
| `assets` | 登记 | 标题背景脚本、logo、shader、配乐目录 / 分层清单、主题 l10n 表——阶段 2 才接线，先登记 |

## 3. 数据文件

### 3.1 `enemies.json`（`{"enemies": {id: {...}}}`）

通用字段照水月（`name / hp / dmg / spd / r / tex / ai / pattern / role / script / tint / ecol / bcol* / cap / tier_cap / elite_after / no_spawn …`，docs/38、98）。第四、五步新加的**主题数据字段**（代码只认字段、不认 id）：

| 字段 | 谁读 | 说明 |
|---|---|---|
| `role` = `boss` + `script` | boss_ai.script_of | Boss 脚本 `scripts/enemies/bosses/<script>.gd`，继承 `boss_base.gd`（§6） |
| `final_track` | music_director | 最终 Boss 配乐键（缺省 `final`） |
| `final_attack_names` | enemies/final_attacks | 最终 Boss 补充攻击招式名；没有 = 不出补充攻击 |
| `land_break_sfx` | boss_ai | 冲刺落地破绽音效 `[名, 分贝]`（缺省伊莎玛拉那一个） |
| `pair` / `pair_linker` | boss_base.on_lethal、boss_ai | 双体组（假死赛跑、统一连线）；`pair_linker` 平时放连线的那一具 |
| `person` | spawner | 同一人物（中期池不重复出场） |
| `ctrl_cat` | combat 控制遥测 | 分类名（报表固定 founder / skimmer / boss / other 四类） |
| `cap_steps` | spawner.type_cap | `[[到这一秒为止, 上限], …, [-1, 之后]]`（没有 `cap` 时） |
| `morph_pool` | enemies.morph | 子代蜕变成的敌种 |

### 3.2 `waves.json`

`threat`（阶段表：刷怪池 / 大群 / 精英）、`boss_times`、`mid_pool`、`mid_first`、`endings`（**结局表**：`{id: {name, en, boss, col, omen, requires?, forbids?, priority?, gallery}}`——`boss` 就是最终 Boss 判定的来源）、`cross_deck`（路口牌组）、`cap_fallback {early, late}`（同种满员换怪）、`events`。

### 3.3 混合文件的主题部分（`ThemePack.load_merged`，规则见 docs/368 §4）

- `lore.json`：本主题敌人档案 `{敌种 id: {lore, profile}}`（干员档案在共享 `data/lore.json`）。
- `guide.json`：`{"pages_insert": [{"at": 第几页, "page": {title, en, icon, lines, more}}]}`——主题机制的说明页插回指定位置。
- `onboard.json`：`cards`（主题机制卡，例：灯火 / 灯标 / 溟痕 / 最终 Boss / 稀有敌人）+ `drill` / `drill_vet` / `tips`（演示局与到点提示顺序，整列替换）。

### 3.4 其余

`events_v2.json`（事件与路口卡，效果词表 `ops` 通用，`light` 是灯火专用）、`relics.json` + `relic_effects.json`（主题藏品；通用藏品要不要复用见 docs/363 §7）、`medals.json` + `medals_layout.json`（主题章组）、`enemy_pixels.json` / `enemy_redraw.json`（敌人帧条规格，`tools/install_enemy_redraw.py` 生成）、`maps/<id>.json`（地砖 / 景物 / 大型景物 / 环境光 / 光柱 / 雪花 / 前景；水月的 `mire` 段是溟痕机制参数）。

## 4. 主题机制（`mech/*.gd`，docs/364）

继承 `res://scripts/core/theme_mechanic.gd`，自己声明 `const Game = preload("res://scripts/game.gd")`、`var g: Game`、`_init(game)`。只实现用得到的挂钩：

| 挂钩 | 时机 |
|---|---|
| `on_player_tick(dt)` | 队长回复之后、护盾之前（水月：灯火熄灭、黑潮） |
| `on_player_hit(dmg, src)` | 队长受击结算中（水月：掉灯火） |
| `on_status_tick(dt) -> bool` | 地面危害（返回 true = 已结算巢涌光环与神经损伤） |
| `on_spawn_tick()` | 刷怪段（水月：自然溟痕） |
| `on_world_tick(dt)` | 杂项段（水月：引航灯标） |
| `on_arena_freeze(fresh)` | 最终 Boss 场地冻结（`run/arena.gd`，通用） |
| `bot_return_dir / bot_score / bot_goal / bot_outside_dir / bot_land_bad / bot_pull / bot_steer` | 机器人（批跑能不能跑全靠它） |

约束：挂钩里随机数只用 `g.rng_*`，纯画面用 `g.vrng`；不要在敌人内层循环里逐个调接口。没有边界机制的主题：最终 Boss 场地照样有（`run/arena.gd`），但场地边没有伤害——要不要做「场地墙」是设计问题。

## 5. 主题模块（`mod/*.gd`）

`ThemePack.make_module(game, 键)`，挂到 `g.ishar` / `g.duck` / `g.knight`。

| 键 | 水月 | 新主题 |
|---|---|---|
| `ishar` | 伊莎玛拉遭遇（友方人形、泪滴、歌眼） | 不需要就不写（核心已判空） |
| `duck` | 鸭爵（稀有敌人） | 不需要就不写（核心已判空）；要做自己的稀有敌人可以照它写 |
| `knight` | 猎潮的骑士同伴（结局二） | **必须提供**：核心还有 85 处直读 `g.knight`（`alive`、`update`、`tick_final`……），新主题先给一个空实现（`alive = false`、各方法空操作），以后再改判空 |

## 6. Boss

`scripts/enemies/bosses/<script>.gd` 继承 `boss_base.gd`，可实现：`step`、`pre_attack`（出招前占窗口）、`on_lethal`（结茧 / 重生 / 假死）、`on_shell_broken`、`on_revive`、`on_damaged`、`absorb_damage`、`block_damage`、`taken_mult`、`on_kill`、`on_gate`、`setup_preview_phase2`、`demo_moves` / `force_move`（图鉴 / 演练）、`super_armor`。Boss 脚本内部写自己的 id 是允许的（`enemy_id_scan` 记 boss_self）。规格与流程：`.claude/skills/new-enemy`、docs/95 / 142b / 165。

## 7. 现在还挡着第二个主题的（核心侧，待做）

1. **选主题入口**：`ThemePack.id()` 读设置 / 选主题界面（阶段 2）；`Cfg.theme_switch(id)` 已能换存档（docs/366）。
2. **标题 / 配乐 / 加载页**：`title.gd`、`screens/loading_screen.gd`、`screens/boot_screen.gd`、`sfx.gd` 仍 preload 水月资源（清单 `assets` 段已登记）。
3. **骑士同伴**：§5。
4. **按敌种写死的画法 / 图鉴 / HUD**：`render/*`、`gallery.gd`、`screens/hud_bossbar.gd` 等，`python tools/enemy_id_scan.py` 的 render / ui 两类（docs/368 §1）。新主题的敌人在这些分支里走缺省画法——能玩，但特效 / Boss 血条样式要补数据字段。
5. **结局线**：`endings.gd` 的 `LINE_ENDS` / `ROUTE_RELICS` / 34 条事件特判、机器人路线（docs/357 §6.2 EndingRules）。
6. **难度命名**：潮位 / 深潮等名字（`data.gd`、`meta_bounty` 文案）。
7. **Toy 单主题包**：`export_web --theme`（docs/357 §5）。

## 8. 测试（新主题合入前）

| 项 | 怎么做 |
|---|---|
| 数据 | `python tools/data_lint.py`、`graph_lint.py`（waves 引用的敌种都在 enemies、Boss 有脚本、事件藏品存在、贴图在索引里） |
| 写死 | `python tools/enemy_id_scan.py`：核心（非 theme / fp / boss_self）不得新增 |
| 存档 | `check.py --only theme_save`（主题进度各存各的、云存档 th 往返） |
| 水月不受影响 | `python tools/theme_parity.py`（Windows 本机 + GCP Linux，`--alt` 判 deep_p0） |
| 新主题本身 | 给 `theme_parity.py` 加一组本主题的局（每个结局一局 + Boss 台 + 短局），录自己的基线；机器人打满一局不崩（`--balance --god`） |
| 画面 | 图鉴敌人页 / Boss 血条 / 主题机制的截图（`--galleryshot`、`--bosstest`），人看 |
| 文案 | docs/76（明日方舟口吻、术语表、原作出处 PRTS 优先），l10n 键 `ui.<主题>.<文件>.<路径>` |

## 9. 傀影样例（`phantom`）填表

| 项 | 傀影要填的 | 出处 |
|---|---|---|
| `theme.json` id / name | `phantom` / 傀影与猩红孤钻 | docs/358 |
| 地图 | `maps/phantom_*.json`：剧院主题地砖 / 景物 / 光照 | docs/362 §4、363 §1 |
| 敌人 | `enemies.json`：docs/362 §3 筛出的名单；四个结局 Boss + 中期 Boss（`role boss`、`script`、`final_track`、`final_attack_names`） | docs/362 §3、358 §6–§7 |
| 刷怪 / 结局 | `waves.json`：`threat`、`boss_times`、`mid_pool`、`endings`（舞会终场 / 滑稽喜剧 / 盛大揭幕 / 沉默之章，各自 `boss`、`requires`） | docs/358 §2、§7 |
| 事件 | `events_v2.json`：45 件原作事件对位 | docs/361、362 §1 |
| 藏品 | `relics.json` + `relic_effects.json`：保留通用藏品 + 主题藏品折算 | docs/362 §2、363 §7 |
| 主题机制 | 机制 A「无主的财富」：`mech/mech_fortune.gd`（实现需要的挂钩 + 机器人挂钩） | docs/358 §5、362 §5 |
| 模块 | `knight` 空实现（§5）；不要 `ishar` / `duck` 或自己的稀有敌人 | — |
| 指南 / 引导 / 档案 | `guide.json pages_insert`（机制说明页）、`onboard.json`（机制卡 + drill / tips）、`lore.json`（敌人档案） | docs/76 §4 |
| 蚀刻章 | `medals.json` + `medals_layout.json`（傀影章组） | — |
| 配乐 / 标题 | `assets` 登记（接线等 §7 第 2 条） | docs/362 §4、363 §3 |
| 测试 | §8 全部 | — |
