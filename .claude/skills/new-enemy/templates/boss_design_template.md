# NNN · <Boss 名> `<id>` 设计稿（<中期 Boss / 最终 Boss>）

> 状态：设计稿，待审（<日期>，分支 `claude/boss-<id>`）。
> 依据：docs/38 §1（通用框架）与 §1.17（实现约定）、95 §0.2（4 招 4 样式、时序、伤害上限）、165（最终 Boss 主动攻击口径）、170（中期分级弹 / 连段）、306（弹体东方化）、283（中期可见性）、142b §8.4（专属色）、98（立绘）、76（文案）。
> 原作资料：enemy_handbook_table.json / enemy_database.json / roguelike_topic_table.json（Kengxxiao/ArknightsGameData）、PRTS `m.prts.wiki/w/<名>`；docs/49c §<x>。来源已登进 docs/76 附录 A。
> 口径：图案弹幕不做符卡；专属弹幕色；不弹文字提示；弹幕紧张主要给最终 Boss。

## 1. 原作资料（可查证）

| 项 | 原作 | 出处 |
|---|---|---|
| 名字 / 英文 | | enemy_handbook_table |
| 出场（集成战略层 / 关卡） | | roguelike_topic_table / level_rogue2_* |
| 能力（逐条） | | enemy_database |
| 外观（体色 / 眼点 / 器官） | | PRTS 小人、立绘 |

本作原创部分标「本作原创（取材 …）」。

## 2. 定位与时长

- 一句话：玩家打它时要做的事（主轴）：
- 登场位：3:30 / 7:00（mid_pool，是否进 mid_first）或 结局 <key>（endings）：
- 目标时长：中期 25–40 秒 / 最终 60–90 秒；卡点 `gates`、每幕最短 `act_min`：
- 与同场 / 同位 Boss 的区分（动词不重复）：

## 3. 招式表（4 招 = 4 种预警样式；最终 Boss 按 docs/165）

| 招 | 预警样式（① 落点圈 ② 直线 ③ 扇形 ④ 缺口环 0 区域场） | 几何 | 预警 / 锁定 / 连发间隔 | 伤害（mult，≤ 40% 单发、2 秒 ≤ 50%） | 阶段 | 实现（patterns mode / mid_cards / 脚本） |
|---|---|---|---|---|---|---|
| A | | | ≥ 0.6 秒 | | 1 | |
| B | | | | | 1 | |
| C | | | | | 1 | |
| D（标志招，`_first_tell` 先亮名 0.6 秒） | | | | | 2 | |

每幕新元素：中期 1 个 / 最终 ≤ 2 个。机制（不算招）：

## 4. 弹幕与配色（docs/306）

- 专属主色（色相，避开 194° / 340° / 45° / 175° / 27°）：`bcol` / `bcol_core` / `bcol_outline`：
- 每幕色变（同色系内）：
- 弹型：小 / 中 / 大圆弹 + 米弹 / 针弹 + 专属弹形：
- 和同场其他 Boss / 普通怪弹怎么分开：
- 粒子预算（同屏 ≤ 700，手机 ≤ 350）：

## 5. 可见性（中期，docs/283）

- 体型（站高 40–56；进 mid_pool 自动 ×1.35）：
- 不加头顶箭头 / 文字；锁定框 / 脚下环沿用现行。

## 6. 美术需求单（Codex，docs/94 / 98 / 104 只写范围）

| 帧条 | 帧数 | 画布（1x） | 说明（命中帧、`_emit` 层） |
|---|---|---|---|
| `e_<id>` 待机 | 2 | | |
| `e_<id>_move` | 4 | | |
| `e_<id>_attack` | 4（f2 命中） | | |
| `e_<id>_<招>` | | | |
| `e_<id>_death` | | | |
| 名片 `boss_<id>` | — | | `enemies/_portraits/` |

色数 ≤ 32；@2x 必交；四列对照「立绘参考 / PRTS 小人 / 上一版 / 本版」。

## 7. 按 type 写死要补的表（逐项打勾）

- [ ] `bosses/<id>.gd`（step / demo_moves / force_move / setup_preview_phase2）+ `.uid`
- [ ] `render/boss_bullet_draw.gd` TYPES / RAMP / SHAPE / AMB
- [ ] 最终：`boss_patterns.gd FINAL_TYPES`、`final_attacks.gd NAMES`、`boss_attack_draw.gd`、`music_director.gd FINAL_TRACK`、`final_boss_tells_test.gd`
- [ ] `vfx.gd BOSS_STYLE` / `HIT_SHELL` / `HIT_SPIRIT`
- [ ] `world.gd boss_strip_animation`（draw_full 帧条挂点）
- [ ] `sfx.gd CUE_VOL` + `audio/sfx/boss_<id>.wav`
- [ ] `tools/boss_bench.py BOSSES`、`tests/boss_variety_test.gd`、`enemy_pixel_contract.gd`
- [ ] 机器人会主轴（core/bot.gd）
- [ ] `lore.json` 档案、json `desc`、`intro`

## 8. 测试与难度

- 快检：data_lint / enemy_art / asset_index / enemy_pixels / `--auto`（rc）：
- `--bossmoves=<id>` 逐招截图、`--bossacts` 逐幕：
- 测试台 `boss_bench.py`（tag、快照、对照表：用时 / 破绽输出占比 / 承伤）：
- 整局（m0 45–55 / m18 65–75，≥ 3 份，同种子配对，< 10 点不下结论）：

## 9. 验收记录与待办
