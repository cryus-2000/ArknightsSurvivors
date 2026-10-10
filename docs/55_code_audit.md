# 55 · 架构与代码冗余审计（2026-10-10）

> 用户 10-10：「检查目前的架构和代码是否有冗余」。本文是只读审计（第 1 部分）加一次「只删确定死掉的东西」的清理提交（第 2 部分）。
> 范围：`game/scripts`、`game/tests`、`game/data`、`tools/`、`game/tools/`、`art/incoming/`。三周里十几个会话并行合入，预期有残留。
> 方法：脚本建符号索引（`func / var / const / signal / enum / class` 共 **10010 个定义、4586 个不同名字**），在全仓库（`.gd / .json / .tscn / .tres / .cfg / .py / .md / .sh / .js / .html / .bat`）按整词计引用；
> 引用数 = 定义数的即「零引用」。字符串里的名字（`call("x")`、`has_method("x")`、JSON 键、`"relic_" + id` 这类动态拼名的前缀）都按整词算进引用，所以**零引用是保守的**：动态拼名只会让候选变少，不会误杀。
> 数据键另按「段/键」字面量 + 键名整词两级查；美术文件按「文件名去掉尾段逐级缩短」查前缀（`e_slug_idle` → `e_slug`）。

## 0. 结论（一页）

| 项 | 数量 | 处理 |
| --- | --- | --- |
| GDScript 总量 | 107 个文件 41788 行（`scripts` 36.9k + `tests` 4.9k） | — |
| 零引用符号 | **36**（15 const、19 func、2 var） | 本次删 **31**；留 5（文档说明是预留 API 或被 docs / tools 点名） |
| 潮汐弹 `tide` 死分支（docs/53） | `weapons.gd` 33 行 + `world.gd` 7 行 + 登记 3 处 | 本次删 |
| `balance.json` 从未读的键 | 287 个叶子里 **1 个**（`enemy/spawn_cap`） | 本次删；其余 286 个全部被读（含动态拼名 `boss/hp_x_<type>`） |
| `Cfg`（settings.gd）从未读的字段 | **0**（3 个私有字段只在文件内用，正常） | — |
| 其他 JSON 从未读的键 | enemies 3、relic_effects 4（效果参数）、characters 5、maps 1 | 列出，不动（归各自负责会话；见 §4） |
| 完全相同的助手函数 | `_strip` ×3 文件、`_fx_tex` + `_fx_strip` ×3 文件、`_log` ×3 文件 | 建议合并到基类（§2.2），本次不动 |
| 单文件 > 1000 行 | 7 个（`world.gd` 3065 最大）；单函数 > 300 行 5 个（`draw_world` 687） | 建议（§6），本次不动 |
| 工具脚本无人引用 | `tools/` 4 个 + `game/tools/` 1 个（合计 1196 行）；另 2 个生成器功能重复 | 列出（§3），本次不动 |
| `art/incoming` 未被游戏引用的文件 | 1036 个里 **333 个**：143 张预览 / QA / 审阅图、127 张 `relic_<id>.png`（动态拼名，实际在用）、约 45 张候选孤儿素材 | 列出（§5），不删（可能等接线） |
| 测试开关漏进发布路径 | **0**：全部经 `OS.is_debug_build()` / `Cfg.dev_args()` / `g.autotest`、`g.balance` 运行时标志；`check_release.py` 通过 | — |
| 「缺图退回程序画」分支 | 22 处 `if not fx_sprite(...)`，对应贴图**全部存在** | 保留（§2.4：贴图按需懒加载，网页版 / 低内存仍可能为 null，删前要先证明加载保证） |
| 旧 V 号代码路径（`V6_FRAMES` 等） | 只是美术批次命名，**没有并存的旧路径** | 建议改名一次（§2.5），本次不动 |

**第 2 部分清理结果**：20 个文件，−176 行 / +5 行，31 个符号 + 1 个数据键；行为不变（同 seed TRACE / BALANCE 逐字节相同、快检全量通过、发布检查通过），见 §7。

---

## 1. `game/scripts`：死符号（36 个）

证据列：`g` = `game/`（不含 tests）里该名字出现的次数，`t` = tests，`o` = 仓库其他处（docs / tools / art 说明）。定义本身算 1 次，所以 `g=1 t=0` 就是零引用。

### 1.1 本次删除（31 个）

| 位置 | 符号 | 行数 | 证据 | 备注 |
| --- | --- | --- | --- | --- |
| `run/weapons.gd:59` | `func sniper_target` | 13 | g=1 t=0 o=0 | 旧援护狙击手索敌；援护系统已改成干员编队 |
| `run/weapons.gd:201` | `"tide"` 分支（`bullet_hit`） | 33 | 无任何生成者（全仓库只有命中 / 绘制分支）；docs/53 §已判死 | 一并删 `hit("潮汐弹")` 来源判断、`world.gd` 两处绘制分支、`PROJ_TEX` 与 `V6_FRAMES` 的 `proj_tide` / `fx_tide_hit` 登记。`mizuki.json` 的 `潮汐弹` 命中来源条目是数据，留着无害 |
| `render/world.gd:421` | `var jf`（局部） | 1 | 只在定义行 | 旧帧序号变量 |
| `render/world.gd:1671` | `const PARANOIA2_TINT` + `func _paranoia2_halo` | 19 | g=1 t=0 o=0 | 偏执泡影二阶段光环旧画法；现在的画法在 `_draw_enemy_full` |
| `game.gd:218` | `var orbit_a` | 1 | g=1 | 旧环绕物角度 |
| `characters/character.gd:187` | `func hud_sp_frac` | 7 | g=1 t=0 o=0 | 编队栏改用 `skill_item()` 后无人调 |
| `characters/character.gd:816` | `func apply_extra_card` | 4 | g=1 | 基类钩子，**没有任何子类覆写也没有调用点** |
| `characters/doctor.gd:301` | `func passive_cat` | 3 | g=1 | |
| `characters/squad.gd:324` | `func draw_skill_floor` | 6 | g=1 | 各干员自己在 `_draw_skill_floor` 里画（mizuki.gd:555 自调） |
| `core/build_profile.gd:63` | `func tag_weight` | 3 | g=1 | |
| `core/combat_core.gd:60` | `func lose_relic` | 7 | g=1 | `combat_core` 本身「未落地」（docs/09 §1），只剩 `test_core` 用 |
| `core/modifier_system.gd:51` | `func has_owner` | 3 | g=1 | |
| `core/stat_block.gd:44 / 82` | `func get_base`、`func count_source` | 2 + 8 | g=1 | |
| `endings.gd:135` | `func _box_alive` | 6 | g=1 | |
| `run/combat.gd:596` | `func in_zone` | 3 | g=1 | `zone_dir()` 仍在用 |
| `run/progression.gd:67` | `func open_recruit` | 8 | g=1 | 招募已并入升级三选一（`recruit_cards()` 仍在用） |
| `ui.gd:141` | `static func cut_poly` | 5 | g=1 | 注释写「保留给个别装饰用」，但零引用 |
| `ui.gd:22 / 43–50` | `TAB_GREY`、`DEEP`、`DEEP2`、`KELP`、`KELP2`、`KELP_LIGHT` | 6 | 各 g=1（`DEEP` 在 `tools/promo_keyart.py` 的同名 Python 常量无关） | 注释「兼容旧代码的深海色名」，旧代码已不在；`EDGE / EDGE_DIM / GLOW` 仍有引用，留 |
| `allies/knight.gd:10` | `const SPEED` | 1 | g=1 | 骑士速度实际用 `FOLLOW_SPD / CHARGE_SPD` |
| `data.gd:150–160` | `MAX_WEAPONS`、`ALLIES`、`RECRUIT_LEVELS` | 11 | 各 g=1 | 旧「援护干员」四职业文案表，v0.x 系统；援护已改为真实干员 |
| `gallery.gd:50` | `const LOCK_BY_ENDING` | 2 | g=1 | 图鉴解锁改走 `gallery_progress.gd` |
| `relic_fx.gd:54` | `const CLASSES` | 1 | g=1 | |
| `screens/choice_panel.gd:16` | `const EV_COL_TOP_TOUCH` | 1 | g=1 | 触屏事件列顶边已改成按高度算 |

### 1.2 保留（5 个）

| 位置 | 符号 | 原因 |
| --- | --- | --- |
| `characters/character.gd:374` | `func attack_gate` | docs/26 §手动普攻把它列为干员可调的 API；现各干员用 `idle_cd()`。建议：下次改 docs/26 时一并删 |
| `core/build_profile.gd:133` | `func snapshot` | docs/09 §5 / §6-6 计划「`--balance` 结束时打印 `core.profile.snapshot()`」，未接 |
| `core/stat_block.gd:136` | `func breakdown` | docs/09 §2 / docs/14：属性面板用，未接（`stats_panel.gd` 用的是 `STAT_SYNC`） |
| `core/balance.gd:68` | `static func reload` | 注释「测试用」；`--bal=` 探针可能用到 |
| `pad.gd:52` | `const GLYPH` | `tools/make_ui_fallback.py` 按它补圈字字形；留 |

### 1.3 方法的盲区（说明，不是发现）

- 只查了**类级与函数级**定义；未用的函数**参数**没查（GDScript 以 `_` 前缀约定，编辑器会警告）。
- 子类覆写基类虚函数（`on_elite`、`_release` 等 14 份）各算定义，不算死。
- 信号：`signal` 定义 0 个零引用。`preload` 常量 0 个零引用。

---

## 2. `game/scripts`：重复与可统一的写法

### 2.1 复制粘贴的助手（建议合并到 `characters/character.gd` 或 `op_api.gd`）

| 函数 | 文件 | 规模 | 说明 |
| --- | --- | --- | --- |
| `_strip(tx, frames, fr, p, sc, anchor_px, flip, col)` | `kaltsit.gd:661`、`lumen.gd:564`、`skadi.gd:383` | 3 × 8 行，**逐字相同** | 帧条单帧绘制（`draw_set_transform` + `draw_texture_rect_region`） |
| `_fx_tex(name)` + `_fx_strip(name, frames, frame, p, anchor, ang, col, flip)` | `mizuki.gd:450`、`suzuran.gd:449`、`wisadel.gd:640` | 3 × 约 22 行，逐字相同 | 懒加载进 `g.tex` + 画帧；`op_api.spawn_fx_sprite` 是「生成一次性特效」，不是同一件事，所以各干员各抄了一份「就地画一帧」 |
| `_log(what)` | `endings.gd:98`、`beacon.gd:226`、`hunt.gd:61` | 3 × 3 行 | `if g.autotest: print(...)`；可做成 `g.autotest_sys.log(tag, what)` |
| `_hit_fx(e, origin)` | 基类 + 6 个干员 | 各不同 | 正常覆写，**不是**重复 |
| `sparks / slash_fx / show_banner / float_text` | `op_api.gd` → `vfx.gd` | 一行转发 | 接口层设计如此（docs/39 §2），不是重复 |

**已做（10-10）**：`_strip` 与 `_fx_tex + _fx_strip` 合并进 `characters/character.gd`（−99 / +34 行，六名干员同 seed `--drawtest --maxprog` 200 秒 TRACE 逐字节相同）。`_log` ×3 **不合并**：三处分别在 `endings / beacon / hunt` 三个 RefCounted 系统里、打印内容各不相同，共同部分只有一行 `if g.autotest:` 守卫；抽成公共函数要先把带 `filter` 的字符串拼好再传，正式游玩每次调用都多付格式化开销，得不偿失。

成本：合并前两项约 40 分钟（新建基类函数、6 个文件各删一段、快检 ops 档 + 图鉴动作页截图对照）。风险低；收益是以后改帧条口径只改一处。

### 2.2 字典取默认值的模式

`e.get("x", 0.0)` 这种对敌人字典的逐帧取值：`world.gd` 181 处、`boss_ai.gd` 109 处、`combat.gd` 56 处、`enemies.gd` 47 处。docs/50 §9.11 已把 `d.get("extra", {})` 的新建空字典改成常量；剩下的是读数值，没有性能问题，只是可读性。**不建议**为此改成类——敌人用字典是 docs/39 定的（`set/get` 按字符串访问的场合多）。

### 2.3 遥测 / 统计：**没有重复**

`run/telemetry.gd` 一份记录（`record()`）同时供 `--balance` 的 `BALANCE {...}` 打印与玩家本地 `runs.jsonl`（2026-09-26 已从 `core/bot.gd` 挪出合并）。`core/build_profile.gd` 的统计（伤害来源 / 流派）是另一层（docs/09 §5），`snapshot()` 未接到 BALANCE 里——见 §1.2。

### 2.4 「缺图退回程序画」分支（22 处）

`if not g.vfx.fx_sprite("fx_xxx", ...)`：全部 19 种 `fx_*` 贴图**都在 `art/incoming/`**，加上 `kaltsit / saria / siege / irene / lumen / specter / wisadel` 等「Codex 帧条缺图退回」的 20 余段程序画（约 59 处注释）。
**为什么本次不删**：贴图是 `game.gd _ready` 按 `V6_FRAMES` 与 `optional` 名单加载，部分（`_fx_tex` 懒加载、`A.tex`）首次用到才读；网页版 / 低画质 / 线程不可用（`art.gd` `has_feature("threads")`）时 `g.tex[name]` 可能是 null，回退分支真的会走到。删之前要先做「加载保证」：启动时断言所有 `fx_*` 非 null，或把回退改成统一的「画一个方块 + push_warning」。估：盘点 1 小时 + 删 2 小时，可省约 400–600 行程序画；收益主要是可读性。建议 EA 后、美术稳定后一次做。

### 2.5 `V6_FRAMES` 等「V 号」

`V6_FRAMES`（`game.gd:1387`，42 行帧条登记表）是**唯一**的帧条登记表，V5 / V7 / V8 / V9 只出现在注释里标美术批次（`world.gd` 8 处、`vfx.gd` 3 处、`spawner.gd` 2 处）。没有新旧两套代码路径可统一。建议：改名 `FRAMES`（13 处引用，`sed` 级改动，10 分钟），注释里的批次号留着当出处。

### 2.6 测试开关

- 命令行开关只经 `Cfg.dev_args()`（发布版返回空）、`Bal._load` / `Sfx` / `art.gd --loadprof` 各自 `OS.is_debug_build()` 判断；`check_release.py` 第 2 条逐个核对。
- `g.autotest` / `g.balance` 运行时标志在 `autotest.gd` 之外有 **27 处**分支（`knight / doctor / endings / vfx / beacon / boss_trial / gallery_progress / hunt / progression / shop / spawner / telemetry / victory_flow / elite_show / hud`）。正式游玩恒为 false，不算泄漏；但 `boss_trial.gd:42` 直接把两个标志置 false 这种写法说明它们在当「模式」用。建议长期把「演练 / 演示 / 测试」合成一个 `g.mode` 枚举（1 小时，纯整理）。
  **已做（10-10）**：`game.gd` 新增 `enum Mode { PLAY, AUTOTEST, BALANCE }` + `var mode`；`game.gd` 内 12 处、其他 13 个文件 27 处（含 `autotest.gd` 7 处）改为比较 `mode`；`boss_trial.gd` 与两个测试的「两个布尔置 false」改成 `g.mode = g.Mode.PLAY`。旧 `g.autotest / g.balance` 保留为只读派生属性（`hud.gd` / `vfx.gd` / `world.gd` 本轮不动，仍读布尔；赋值走 setter 拨模式）。演示 `demo_op` 与演练 `trial.active` 不并入：前者带干员 id、后者是局内状态，不是启动模式。同 seed TRACE 逐字节同、快检 41 项、check_release 通过。

---

## 3. `tools/` 与 `game/tools/`

全部 35 + 13 + 4 个脚本按文件名在 docs / 其他工具 / 游戏 / 美术说明里查引用：

| 脚本 | 行 | 引用 | 判断 |
| --- | --- | --- | --- |
| `tools/make_logos_glyphs.py` | 278 | 无 | 与 `tools/gen_logos_glyphs.py`（352 行，docs/41 提到）**生成同一张 `fx_logos_glyphs`**；`gen_` 是后来的（art/requests v17），`make_` 是旧版 |
| `tools/make_logo.py` | 137 | 无 | 生成 `art/incoming/logo.png`，图已交付；一次性 |
| `tools/make_beacon.py` | 95 | 无 | 生成 `prop_beacon`（已交付） |
| `tools/package-lock.json` | 6 | 无 | 误留的 npm 锁文件（`tools/` 没有 package.json） |
| `game/tools/gen_art.py` | 591 | 无 | 最早的程序美术生成器（V2 之前）；产出已被 Codex 美术替换 |
| `tools/deploy_web.py` | 213 | 只 docs/33 / 41 | 阿里云 OSS 部署（dry-run）；10-06 起发布走 itch（`deploy_itch.py`，`ship.py` 调），OSS 没有启用过 |
| `tools/cloud/eq_compare.py` | 55 | 只 docs/36 | 云端 / 本机等价性对比，一次性用过 |
| `tools/split_module.py` | 405 | 只 docs/39 / 41 | 架构的拆模块工具，设计上手动用；留 |
| `tools/prepare_encrypted_template.py`、`test_encrypted_release.py`、`verify_encrypted_template.py` | 216 | 只 docs/33 / encrypted_release | 加密模板链路，按文档手动跑；留 |

**两套截图链路**：① `run/autotest.gd` 的 `--openshot / --introshot / --shopshot / --fxshot / --winshot / --choiceshot …`（docs/36 §5，测试用，`viewport.get_texture().get_image().save_png`，9 处）；② `tools/promo_shots.py` + `tools/promo_shots.gd`（宣传用，监视场面存候选）。各有用途，共同点只有 `save_png`，不值得合并；可以把 ① 的 9 个开关收成一个 `--shot=open,intro,...`（30 分钟）。
**启动器**：`启动测试版.cmd`（用 Godot 跑源码）与 `启动对内测试版.bat`（跑 `build/release` 里的对内包）用途不同，不重复。`release_all.py` ← `ship.py` 是分层，不重复。

建议：删 `make_logos_glyphs.py`、`make_logo.py`、`make_beacon.py`、`package-lock.json`、`game/tools/gen_art.py`（1107 行）前先问一声界面与美术（生成器偶尔要重跑）；`deploy_web.py` 问部署。本次都**没动**。

---

## 4. `data/`：代码不读的键

| 文件 | 键 | 位置 | 说明 |
| --- | --- | --- | --- |
| `balance.json` | `enemy/spawn_cap` = 450 | 第 122 行 | 全仓库无 `spawn_cap`（docs 也没有）；场上上限实际是 `boss/final_mob_cap` 与 `enemies.json` 各种 `cap`。**本次删** |
| `enemies.json` | `decay`（注亡拟嗣 0.08）、`aura_nerve`（深溟巢涌者 10.0）、`attack.sequence_step`（伊莎玛拉 0.6） | 93 / 312 / 813 | 代码没读；docs 没提。归 Boss与怪物 |
| `relic_effects.json` | `args.icd`（2 件）、`args.corrode_extra`、`args.not_boss`、`args.boss_pct` | 945 / 1634 / 1829 / 1862 | `sp` / `execute` / `bonus_current_hp` 三个动作的参数，`relic_fx.gd` 动作实现没读 → 这些藏品描述里的「内置冷却 0.5 秒」「不对 Boss」「Boss 0.5%」**当前不生效**。归藏品；是数值差异不是冗余，建议补实现或改描述 |
| `characters/mizuki.json` | `base.swing_arc / tentacle_mult / awaken_swings` | 24–26 | 代码里角度 / 倍率是常量 |
| `characters/logos.json` | `requiem_bonus`、`glyph_max` | 18 / 41 | |
| `maps/deep_sea.json` | `half_width: true`（一个地物） | 33 | `map.gd` 不读 |
| 各文件 `_doc` 键 | — | — | 说明用，正常 |

`characters/*.json` 的 390 个不同键里只有上面 5 个没被读；`relics.json`、`doctor.json`、`waves.json`、`lore.json` 全部在用。`Cfg` 的 40 多个存档字段全部在用。

---

## 5. `art/incoming`：游戏没引用的文件（列出，不删）

1036 个文件（不含 `.import`）。按名字（含动态前缀）能在 `game/` 找到的 533 个；171 个是说明 / 清单 / QA 的 `md / json / html / txt`；剩下 333 张图：

- **143 张预览 / QA / 审阅图**：`*_preview.png`（v12–v15 批次、squad、fx30、growth_preview_fx_*、logos_fx_preview_*）、`art_review_0926_*`（27 张）、`v13_qa/`、`v15_qa/`、`*_overview.png`、`logos_fx_composite.png`、`mizuki_48_original*`。不是游戏资源，是交接附件；仓库体积问题归 Codex / 用户定。
- **127 张 `relic_<id>.png`**：`"relic_" + id` 动态拼名，**都在用**（265 个藏品 id 里 133 个有图、**129 个没有图标文件**——这是缺图不是冗余，图鉴 / 商店会画占位）。
- **约 45 张候选孤儿素材**（代码与数据里都没有这个名字，也没有能拼出它的前缀）：
  - `evo_blade.png`、`evo_blade_abyss.png`、`evo_blade_moon.png`、`evo_tendril.png`、`evo_tendril_giant.png`、`evo_tendril_mother.png`（旧「进化」系统图标，6 张）
  - `growth_b_*`（count / dmg / echo / pierce / range / size）、`growth_t_*`（count / dmg / field / power / reach / stake）、`growth_u_*`（area / dmg / spd）：旧单人水月成长线的 15 张图标；现成长线 id 是 `squad_atk / hp / wick …`（那 13 张在用）
  - 命名式藏品图 17 张：`relic_backlight / bottle / cloak / conch / coral / deep_limb / ember / jelly_spec / oil_jar / scale / scarf / seed / symbiote / umbrella_rib / watch / whisper / wick_shield`（编号前的旧藏品）
  - `weapon_drone.png`、`drone_missile.png`、`mon3tr_float_frames.png`、`_old_logos_glyphs/`（3 张，目录名已说明）、`terrain_regions.png`（参考图）、`art_v6_qa.png`
  - 本次清理后新增 2 张：`proj_tide.png`、`fx_tide_hit.png`
  - 交叉核对 `art/requests/*.md` 与各 `*_handoff.md`：以上都没有「待接线」记录（`enemy_v8` 之类有记录的都已接）。

---

## 6. 架构：职责分得别扭的地方（建议，本次不动）

| 位置 | 现状（量化） | 建议 | 估 |
| --- | --- | --- | --- |
| `render/world.gd` 3065 行 | `draw_world()` **687 行**一个函数（按层 `_pk()` 分段），`_draw_enemy_full` 228、`draw_warn_outlines` 117；敌人画法缓存、地面、灯标、预警、主控状态全在一个文件 | 按 docs/39 的层再拆一次：`render/draw_enemies.gd`（敌人本体 + 缓存 + 状态标记，约 1200 行）、`render/draw_warn.gd`（预警轮廓 + 招式 telegraph，约 500 行），`draw_world` 只剩调度。`tools/split_module.py` 就是为此写的 | 半天 + 像素对照（docs/50 §9.9 的方法） |
| `screens/hud.gd` 1634 行 | `_draw_body` **423 行**（HUD 主体一笔画完），`draw_squad_hud` 148；同时是 `state` 分派器（docs/39 §3-4）又是 HUD 本体 | 分派留 `hud.gd`（约 200 行），HUD 本体拆 `screens/hud_bars.gd`（生命 / 灯火 / 技力）、`screens/hud_squad.gd`、`screens/hud_relics.gd` | 半天，截图对照（docs/36 §5） |
| `game.gd` 1482 行 | docs/39 拆到 1250 后又长回来：`_ready` **328 行**（初始化 + 贴图名单 + 命令行解析）、`_update` 144、`_update_doc_follow` 120、`V6_FRAMES` 表 42 行、开局指南文本 50 行 | ① 贴图名单 + `V6_FRAMES` 挪到 `art.gd`（纯数据，80 行）；② 开局指南文本挪到 `data/lore.json`（文案会话）；③ `_update_doc_follow` 是博士挂件逻辑，归 `characters/doctor.gd` | 各 20–40 分钟，快检 full |
| `boss_ai.gd` 1179 行 | `_boss_ai` **361 行**一个 `match`，`_warn_resolve` 188 | 已有 `enemies/boss_patterns.gd` 承接招式轮换；把每个 Boss 的分支拆成 `enemies/bosses/<type>.gd`（docs/38 多次提议） | 1 天，`bosstest` 招式序列对照 |
| ↳ **已做（10-10）** | `boss_ai.gd` 1179 → 583 行；`enemies/bosses/` 9 个 Boss 脚本 + `boss_base.gd`，`SCRIPTS` 注册表按 type 分派，旧 `g.bai.xxx` 调用点经一行转发不变 | 配方见 docs/38 §1.17 | 4 局同 seed 覆盖全部 10 只 Boss TRACE 逐字节相同，快检 41 项 |
| `title.gd` 1266 行 | `_draw_op_pick` 213、`_draw` 176、`_ready` 156 | 干员选择页拆 `screens/op_pick.gd` | 2 小时 |
| `core/combat_core.gd` | docs/09 §1 自述「未落地」，只给 `test_core.gd` 组装 + 校验 | 要么接进 `game.gd`（docs/09 §6，大活），要么改名 `core/core_validate.gd` 只留校验，别再叫「core」 | 改名 15 分钟 |
| `characters/*` 9896 行 | 14 名干员平均 600 行，`ulpianus.gd` 861；§2.1 的三份抄写 | 基类补 `_strip / _fx_strip`；其余是各干员表现，不建议抽象 | 见 §2.1 |
| 测试开关 | §2.6 的 27 处 `g.autotest / g.balance` | `g.mode` 枚举 | 1 小时 |

**不建议做的**：把敌人字典改成类（docs/39 定的；`set/get` 字符串访问太多）；把 `screens/` 合并（已按一界面一文件，是对的）。

---

## 7. 第 2 部分：清理提交

**范围**：§1.1 的 31 个符号 + §4 的 `enemy/spawn_cap`。20 个文件，**−176 / +5 行**。没有动 §2 / §3 / §5 / §6 的任何项。

**验证**（都在本工作树，Godot 只经 `tools/godot_runner.run_godot`）：

- 同 seed 行为对照（docs/53 §确定性的方法）：`--headless --balance --seed=1 --bot=expert --tier=0 --maxt=200 --trace=1`，水月 / 斯卡蒂各一局，清理前后各跑一次，每秒一行 `TRACE`（时间、等级、击杀、生命、敌人数、`rng.state`、主控坐标、敌人位置 / 生命哈希）+ 末尾 `BALANCE`：**201 / 201、201 / 201 行 TRACE 逐字节相同；BALANCE 56 个字段前后全部相同**（两局都无脚本错误、无超时）。
- 快检全量 `python tools/check.py --jobs 4` → `build/check/audit_full.txt`：**41 项通过、0 失败，rc=0**（131 秒；含核心契约、15 局冒烟、成长节点、主控保护、同 seed 复现、全部场景回归）。
- 发布检查 `python tools/check_release.py` → `build/check_release_audit.txt`：**通过，rc=0**。
- 残留引用：删完后按全部被删名字整词 grep `game/scripts game/tests game/data`，0 处。

**没删的理由一览**：`attack_gate`（docs/26 列为 API）、`snapshot / breakdown`（docs/09 预留）、`Bal.reload`（探针）、`GLYPH`（工具用）；`tools/` 与 `art/incoming` 的候选要先问对口会话；数据键除 `spawn_cap` 外归各自会话。

**下一步建议顺序**（按收益 / 风险）：§2.1 合并助手（低风险）→ §3 删旧生成器（问一声即可）→ §6 `game.gd` 三项搬家（低风险）→ §6 `world.gd` / `hud.gd` 拆分（中，要像素对照）→ §2.4 删回退分支（要先做加载保证）。
