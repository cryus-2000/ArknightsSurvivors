# 14 · 架构重构：角色 / 地图 / 藏品 / 敌人可扩展化

> 2026-09-24 起，基于 v1.7.2。目标：**新增一个干员、一张地图、一件藏品、一种敌人，各自只需新增文件 + 数据，不改 game.gd。**
> 每一步都保证游戏可玩、`--autotest --balance` 跑通、`test_core` 通过，单独提交。

## 0. 现状与拆分原则

- `game.gd` 6300 行，持有全部状态；`boss_ai.gd` / `relic_fx.gd` 已经用"模块持 `g` 引用"的方式拆出，本次沿用同一模式，不引入新框架。
- 模块都是 `RefCounted`，构造时拿 `g`（Game 节点）；绘制通过 `g.draw_*` / `g._spr`，状态尽量迁到模块内。
- 数据一律 JSON 放 `game/data/`，脚本放对应目录；`data.gd` 只保留仍未迁移的表。
- 数值走 `core/stat_block.gd`（docs/09），角色专属属性带角色前缀。

## 1. 目标目录

```text
game/
  data/
    maps/deep_sea.json          地图主题（地砖 / 地纹 / 道具 / 大型景物 / 溟痕 / 氛围）
    characters/mizuki.json      角色定义（属性、贴图集、成长池、技能表、精英化树）
    enemies.json                敌人表（从 data.gd ENEMIES 迁出）
    relics.json / relic_effects.json（已有）
  scripts/
    game.gd                     场景编排：状态机、输入、主循环、掉落 / 商店 / 升级 / HUD
    world/map.gd                Map：读主题，铺地、道具、大型景物、碰撞、氛围层
    characters/character.gd     Character 基类：属性块、通用接口
    characters/mizuki.gd        水月：伞击、触手、s1–s3、潮刃 / 群触、专属绘制
    enemies/enemy_ai.gd         小怪行为：按 enemies.json 的 ai / pattern 字段分派
    boss_ai.gd、relic_fx.gd、core/*（已有）
```

## 2. 接口

### Map（`world/map.gd`）

```gdscript
Map.new(g, theme_id)          # 读 data/maps/<id>.json
map.draw_ground(vs)           # 地砖 + 地纹 + 小道具；把需要 2.5D 排序的道具放进 map.sort_props
map.collect_big_props(vs)     # 大型景物 → map.sort_props
map.push_out(pos, r)          # 圆形实体推出景物底座（原 _prop_push）
map.draw_atmosphere_add(vs)   # 远景光束（加法层）
map.draw_foreground(vs)       # 前景虚化剪影
map.mire_params(t, diff)      # 溟痕生成参数（间隔 / 大小 / 寿命）
map.theme.ambient / .fog      # 氛围色，game.gd 只读
```

主题 JSON 字段：`tiles`、`tile_size`、`patches`、`props`（名称 → 权重 / 锚点）、`big_props`、`big_cell`、`clear_radius`、`ambient`、`god_rays`、`foreground`、`snow`、`mire`。

### Character（`characters/character.gd`，水月为 `mizuki.gd`）

```gdscript
Character.new(g, def)          # def = data/characters/<id>.json
ch.stats: StatBlock            # max_hp / speed / dmg / … + 角色前缀属性
ch.update(dt)                  # 普攻节奏、技能计时、专属实体（触手桩 / 巨触 / 水刃）
ch.on_skill(sid)               # 技能发动
ch.on_levelup_pool() -> Array  # 本角色的成长项 / 精英化候选
ch.apply_growth(id) / apply_evo(id)
ch.draw_floor() / draw_over()  # 角色脚下 / 身上的技能表现
ch.draw_entities()             # 触手桩、巨触、触须阵等专属实体
ch.anim: 贴图集与帧率来自 def.sprites
```

game.gd 不再出现 `s1_` / `evo1 ==` / `u_dmg_mult` 这类水月专属名字；藏品与成长引用的是属性名（`mizuki_umbrella_dmg`）。

### 敌人（`enemies/enemy_ai.gd` + `data/enemies.json`）

- `ENEMIES` 表整体迁到 JSON，字段不变；`ai` 分派到 `melee / ranged / static` 基础行为，`pattern` 字段（burrow、stomp、spit…）分派到 `enemy_ai.gd` 的对应函数。
- 新敌人 = JSON 一条 + 贴图（+ 若有新招式，enemy_ai.gd 一个函数）。

## 3. 迁移顺序与验收

| 步 | 内容 | 验收 |
|---|---|---|
| ① | Map 抽出 + `deep_sea.json` | 自动对局通过；同种子截图与重构前一致 |
| ② | Character 抽出，水月迁入；成长 / 精英化 / 动画随之 | 自动对局 + `--evo=blade,blade_moon` / `tendril,tendril_giant` 两条路线通过；`BALANCE` 输出结构不变 |
| ③ | 玩家数值走 StatBlock；`relic_fx` 的 stat 效果改写 StatBlock；事件在 `_damage/_kill/_hurt/_skill_cast` 广播 | `test_core` 通过；属性面板 breakdown 可用 |
| ④ | 敌人表 JSON 化 + 行为分派 | 自动对局 + Boss 画廊截图 |

## 4. 进度

- [x] ① 地图（v1.8 refactor-1）
- [x] ② 角色（refactor-2）：`characters/character.gd` 基类 + `characters/mizuki.gd`（995 行）+ `data/characters/mizuki.json`；game.gd 5300 → 5200 行，不再出现水月专属名字
- [x] ③ 藏品 / 成长 / 难度的数值修正全部走 `stats: StatBlock`（带来源，可撤销，可 breakdown）；旧变量成为同步缓存（`STAT_SYNC` 表 + `_sync_stats()`）；角色专属属性由 `ch.stat_defs()` 定义、`ch.sync_stats()` 回填；`test_core` 37/37
- [x] ④ 敌人表 → `data/enemies.json`（`D.ENEMIES` 改为从 JSON 加载的静态变量，调用方不变），刷怪导演表 → `data/waves.json`；小怪招式按 `pattern` 字段分派到 `enemies/enemy_ai.gd`（burrow / stomp / dash / acid / nova），远程按 `shot_*` / `lob` / `spawn_on_shot` 字段

## 5. 新增一个角色要做什么（② 完成后的实际流程）

1. `data/characters/<id>.json`：`id / name / en / script / sprites{base,idle,run,attack,hurt,death,size,foot} / icons{s1,s2,s3} / evo{paths, mutations}`。
2. `scripts/characters/<id>.gd`：`extends "res://scripts/characters/character.gd"`，实现：
   - `update(dt)` 普攻节奏与技能计时；`_swing_radius()`、`_dmg_bonus()`
   - `skills() / skill_unlock() / skill_adv() / growth_table() / evo_table()` 返回本角色的表（水月目前仍指向 data.gd；新角色可直接在 .gd 里写字典或读 JSON）
   - `_apply_growth(id) / _growth_preview(id)`、`on_elite(stage) / on_evo_pick(id) / on_kill(e)`
   - 绘制：`draw_auras() / draw_entities_floor() / draw_fx_add(ci, loop) / _draw_skill_floor() / _draw_skill_over()`
   - HUD：`skill_hud() / status_items() / stats_rows() / evo_label()`
3. 贴图放 `art/incoming/`，名字写进 JSON。
4. `Cfg.character_id = "<id>"`（选人界面接上后由标题页设置）。

game.gd 里仍是通用的：位置 / 生命 / 等级 / 经验 / 灯火 / 护盾 / 成长计数 `growth` / 技能等级 `skill_lv`（固定 s1–s3 三槽）/ 精英化阶段 `elite_stage`。

## 6. 新增一种敌人 / 一张地图要做什么（④ 完成后）

**敌人**：`data/enemies.json` 加一条：`name / hp / spd / dmg / r / xp / tex / ai(melee|ranged|static) / role(elite|boss)` 与可选字段 `tint / weak / corrode / nerve / heavy / hover / morph / entrench / burst`，招式用 `pattern` 选现成的（`burrow` `stomp` `dash` `acid` `nova`，各有参数字段），远程用 `shot_n / shot_kind / shot_spd / shot_home / lob / spit / spawn_on_shot`。新招式 = `enemy_ai.gd` 加一个 `_xxx()` 并在 `pattern()` 里登记一行。贴图 `art/incoming/<tex>.png`。加进刷怪池：`data/waves.json` 的 `threat[].pool / horde`。

**地图**：`data/maps/<id>.json` 一份主题（见 §2），贴图放 `art/incoming/`，`Cfg.map_id = "<id>"`。目前只有程序生成的无限地图；手工摆放的地标可以之后在 `map.gd` 里加一个 `landmarks` 字段实现，不影响其它模块。

## 7. 结果

| | 重构前 | 重构后 |
|---|---|---|
| game.gd | 6341 行 | ≈5120 行（场景编排 / 输入 / 主循环 / 掉落 / 商店 / 升级 / HUD） |
| 新模块 | — | `world/map.gd` 300、`characters/character.gd` 110、`characters/mizuki.gd` 1000、`enemies/enemy_ai.gd` 150、`enemies/enemy_db.gd` 40 |
| 数据 | data.gd 硬编码 | `data/maps/*.json`、`data/characters/*.json`、`data/enemies.json`、`data/waves.json`、`data/relics.json` + `relic_effects.json` |
| 数值 | 各处直接 `*=` | 全部 `stats.add(stat, op, value, source)`，可撤销、可 breakdown |

仍留在 game.gd 里、下一步可继续抽的：援护干员（`_update_allies` / `_ally_*`）、无人机（`_update_weapons`）、商店（`_open_shop` 一族）、掉落与经验（`_update_gems`）、HUD 绘制。水月的技能 / 成长 / 精英化表仍在 `data.gd`，通过 `ch.skills()` 等访问；第二个角色出现时再决定是否把它们也搬进 JSON。
