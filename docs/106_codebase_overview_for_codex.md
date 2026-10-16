# 106 代码架构总览（给 Codex 改代码用，2026-10-17）

Codex 自 10-17 起可以改代码（AGENTS.md 已更新）。本文是一张地图：先读这页，再按 §6 的规则做。细节以各处引用的文档为准；docs/00_index.md 是全部文档的索引。

## 1. 一句话

Godot 4.7 单场景幸存者 roguelite：`game/scripts/game.gd` 是局内总控（autoload `g`），每帧按固定次序推进「刷怪 → 敌人 → 干员 → 弹体 / 结算 → 拾取 / 进度 → 绘制」。所有玩法数据在 `game/data/*.json`（数值 `balance.json`、干员 `characters/<id>.json`、敌人 `enemies.json`、藏品 `relics.json` …），代码读数据，不写死数值。美术帧条在 `art/incoming/`，运行时由 `art.gd` 加载。

## 2. 目录与职责

| 目录 / 文件 | 职责 | 入口 |
|---|---|---|
| `game/scripts/game.gd` | 局内总控：状态、`g.rng`（玩法随机）与 `g.vrng`（画面随机）、主循环、`OPT_*` 对照位 | `_process` |
| `game/scripts/core/` | 数值表 `balance.gd`（读 `balance.json`，`--bal=段/键=值` 运行时覆盖）、机器人 `bot.gd`、藏品库 `relic_db.gd`、属性块 `stat_block.gd` | |
| `game/scripts/run/` | 局内系统：刷怪 `spawner.gd`、敌人容器 `enemies.gd`（`g.enemies_sys`：admit / slot / by_id，更新拆 A 决策 / B 运动 / C 结算三段，docs/101 §7.4）、结算 `combat.gd`（`combat.damage(e, dmg, hit)`）、我方武器 `weapons.gd`、拾取 `pickups.gd`、进度 `progression.gd`、商店 / 灯标 / 围猎 / 结局 | |
| `game/scripts/enemies/` | 敌人 AI `enemy_ai.gd`、Boss 招式 `boss_patterns.gd`、敌弹池 `shot_pool.gd`（直线 / 追踪 / 抛物 / 环，SoA）、预警 `telegraph.gd`、敌人表 `enemy_db.gd` | |
| `game/scripts/bosses/`、`boss_ai.gd` | 各 Boss 行为 | |
| `game/scripts/characters/` | 队伍 `squad.gd`；干员基类 `character.gd`（动画、绘制、校验）；数据驱动干员 `data_operator.gd`（技能计时、积木执行）；积木 `blocks/`（公共 `ob_*.gd` 为一条单继承链，各人专属 `seg_<id>.gd`；门面 `op_blocks.gd` 只给测试）；对外接口 `op_api.gd`（干员碰敌人只能走这里：`nearest_raw / add_cc / set_air / hold_at / nudge / set_aggro`，docs/101 §7.3.10） | |
| `game/scripts/render/` | 世界绘制 `world.gd`（队长精灵、敌人、影子、掉落、灯光；剔除视野表、`frame_dst.gd` 取帧、`tri_batch.gd` 三角形批）、特效 `vfx.gd`、画面预设 `look.gd`、敌人图集 `enemy_atlas.gd` | `draw_world` |
| `game/scripts/screens/`、`ui.gd`、`title.gd`、`gallery.gd` | HUD、选卡 / 商店面板、选人、图鉴、作战记录、标题 | |
| `game/scripts/art.gd` | `A.tex(name)`：`art/incoming/<name>@2x.png` 优先（密度 2，`A.hires_of`），缺 1x 可运行；`V6_FRAMES` 登记特效帧条 | |
| `game/scripts/run/autotest.gd` | `--balance / --autotest / --trace / --shots…` 等无头与截图入口（docs/36 §5 列全） | |
| `game/tests/` | `test_core.gd`（干员契约 / 积木校验等 2800+ 断言）、各场景回归（`check.py SCENE_REGRESSIONS`） | |
| `tools/` | `check.py` 快检、`godot_runner.py`（唯一允许起 Godot 的方式）、`trace_base.py` 同 seed 对照、`balance_run.py` 批跑、`art_lint.py` / `px_lint.py` / `body_metrics.py` 美术机检、`export_build.py` / `release_all.py` / `ship.py` 出包发版、`cloud/` 云端批跑脚本 | |
| `native/` | C++ GDExtension 原型（EnemyCore，缺省不启用；docs/101 §4.7） | |

## 3. 每帧次序与数据流（局内）

1. `spawner` 按 `waves.json` + 密度旋钮刷怪 → `enemies_sys.admit`（用 `rng_spawn`）。
2. `enemies.gd` 三段：A 决策（计时、AI、Boss 步，`rng_enemy`）→ B 运动（纯位置，将来原生）→ C 结算（接触 / 泪 / 蜕变，读 A 段缓存的 `_seg_d`）。
3. `squad.update`：各干员 `character.gd` 状态机（移动 / 普攻 / 技能 / 受击），积木在 `data_operator` 里按 tag 执行；碰敌人只经 `op_api`。
4. `weapons`（我方弹体）与 `shot_pool`（敌弹）推进；`combat.damage` 结算；`relic_fx` 藏品效果。
5. `pickups / progression / hunt / beacon` 等局内进度。
6. `world.draw_world`：剔除一次 → 排序 → 影子 / 实体 / 特效 / 灯光；HUD 在 `screens/`。

随机：玩法一律 `g.rng`（及派生流 `rng_spawn / rng_enemy / rng_drop / rng_op`），画面用 `g.vrng`。**同 seed 必须逐局相同**（docs/36 §3.2），这是所有代码改动的第一验收。

## 4. 干员（Codex 最常碰的部分）

- 数据：`characters/<id>.json` = 属性、`attack`、`skills[0..2]`（数值、`anim`）、`blocks`（积木，tag → 执行器）、`sprites`（帧条槽）、`extra_sprites`。启动时 `validate_operator` 校验，`test_core` 的「干员契约」断言会抓。
- 动画接口：docs/105（现状 + 目标契约 `sprites.skills.sN`），docs/87 §3.5。
- 帧条规格：docs/103（尺度：身体 64 @2x、头高公式）、docs/104（制作 / 验收流程）、docs/87（命名、`art_lint`）。
- 精英化形态：docs/91（设计）、docs/93（素材单）。

## 5. 测试与工具（改代码必跑）

| 命令 | 作用 |
|---|---|
| `python tools/check.py --auto` | 按改动分层跑：核心契约、场景回归、art_lint、px_lint、金样积木等价…（0 失败才能交） |
| `python tools/check.py --only <项>` | 单跑某项（`op_select / codex / ea_ui / run_stats / art_lint / blocks_eq …`） |
| `python tools/trace_base.py <seed> <干员> <秒> --here` | 同 seed TRACE 对 main 基线逐行比（退出码 0 = 相同） |
| `python tools/art_lint.py --ops <id>` | 帧条机检；新规格下描边 / 跑步阈值项用 `WAIVERS` 豁免并写明原因 |
| `python tools/px_lint.py --only2x <png>` | @2x 像素纪律（孤点 / 单点高光 / 描边 / 连通体） |
| Godot 本机 | `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`，一律 `--headless --audio-driver Dummy`，只经 `godot_runner.py` 起进程，**不要按进程名杀 Godot** |

## 6. Codex 改代码的规则（10-17 起）

1. 分支：从 `main` 开 `codex/<主题>`；美术仍在 `codex/art`。一次任务一个分支，不混。
2. 不合 `main`、不推别的分支、不 force-push、不 reset --hard、不动别人的工作树；交付 = 提交号 + 改动说明 + 快检结果 + 同 seed 结论，由协调人合入（docs/41 §3）。
3. 只改任务涉及的文件；`.gd.uid` 随脚本同一提交；不提交 `.godot/`、`build/`。
4. 数值写 json 不写代码；玩法随机只用 `g.rng` 系；画面随机用 `g.vrng`。
5. 文档：改了字段 / 接口要同步 docs/87 或对应规范，并在 docs/00_index.md 登记新文档。
6. 不确定的接口（例如敌人字段语义）先看 docs/101、docs/101a，再问协调人，不猜。
7. 不做：发版、推 itch、改 AGENTS.md / CLAUDE.md、改 `tools/ship.py`。

## 7. 关键文档速查

| 主题 | 文档 |
|---|---|
| 协作与分支 | docs/06、docs/41 |
| 测试口径 | docs/36 |
| 架构审计与原生化路线 | docs/101、101a |
| 干员动画接口 | docs/105、docs/87 §3.5、docs/92 |
| 帧条规格 / 尺度 / 流程 | docs/87、103、104 |
| Boss / 怪物 | docs/95、96 |
| 难度与数值方法 | docs/27、50、80 |
