# 367 主题包重构 · 第四步：主题数据搬家、敌种 id 写死点、存档收尾（11-18）

**状态：已实装，待协调人合入。** 分支 `claude/theme-step4`，以 main `a7f3d41bd` 为底。上游：docs/357（分阶段方案）、docs/359（基准与清单）、docs/364（机制接口）、docs/366（存档按主题）。

| 提交 | 内容 |
|---|---|
| `546858461` | 存档：`roster_tiers` 改按主题；全部解锁包切主题的保护 |
| `fb8145173` | 主题数据搬进 `game/themes/deep_sea/data/` |
| `56bd40aee` | 敌种 id：一批规则改读 `enemies.json` / `waves.json`；写死点清单工具 |
| `d6fc5d52b` | 搬家漏改的工具：`desc_value_audit`、`install_enemy_redraw`（pathlib 写法）、`check.py` 的 JSON 解析检查与 `--auto` 说明字段分级认 `game/themes/*/data` |

## 1. 存档收尾

- **`roster_tiers`（已首通的难度档）按主题**（协调人 11-18 定：新主题首通同一档也发凭证）。一行加进 `ThemeSave.FIELDS`（合并方式「并集」），旧位置 `[roster] tiers` 与云存档旧键 `prog.optier` 仍是水月，其他主题在 `[theme_<id>] roster_tiers` / `prog.th.<id>.optier`。注意：现在游戏逻辑里已经没有代码读 `roster_tiers`（通关发凭证走 `Roster` 的 `CLEAR_TICKETS`，每局都发），它只剩存档 / 云存档的记录作用；以后要恢复「首通才发」时按主题读它即可。
- **全部解锁（调试 / 对内包）切主题的保护**（docs/366 §5 第 2 条）：`theme_switch` 在 `unlock_all` 时，收进 `theme_saves` 的是 `_real_progress` 里的真实值；切过去后按新主题重算 `_real_progress` 与全开的演示数据（`_apply_unlock_all` 的那段抽成 `_unlock_display()`）。旧主题的真实进度不再写进新主题段。
- 测试 `theme_save` 补：已首通档两主题各存各的、旧位置与 `optier` 仍是水月；全开时切主题、写档、切回，两边真实进度都对。

## 2. 主题数据搬家

### 2.1 搬了什么

| 搬进 `game/themes/deep_sea/data/` | 留在 `game/data/`（共享或混合） |
|---|---|
| `waves.json`（含结局表 endings、路口牌组）、`enemies.json`、`events_v2.json`、`relics.json`、`relic_effects.json`、`medals.json`、`medals_layout.json`、`enemy_pixels.json`、`enemy_redraw.json`、`maps/deep_sea.json` | `lore.json`（干员档案和敌人档案混在一份里）、`guide.json` / `onboard.json`（通用页与灯火 / 溟痕页混在一起）、`doctor.json`、`meta_tree.json` / `meta_roots.json`（认知塑造跨主题共享）、`ult_text.json` / `ult_audio.json`（干员终结技）、其余通用数据 |

混合文件拆分是内容阶段的事（第二主题的敌人档案 / 主题页另放主题包，清单键指过去即可）。

### 2.2 跟着改的

- **清单** `themes/deep_sea/theme.json`：data 段 9 个键与 `maps.dir` 改指 `res://themes/deep_sea/data/…`。游戏代码一律经 `ThemePack.path()` 取，代码不用改。
- **导出**：两个导出预设与 `tools/encrypted_release.py` 的 `include_filter` 加 `themes/*/data/*.json`、`themes/*/data/maps/*.json`。
- **发布链路里按目录扫 JSON 的**：`tools/release_slim.py` 的字体子集（只扫 `data/` 会让主题数据里的字从子集字体里掉出去——网页 / 对外包会缺字）、`tools/verify_encrypted_game.py` 的包内 JSON 探测，都加了 `themes/**`。
- **Python 工具**：新增 `tools/theme_paths.py`（读同一份清单：`data_file(名)`、`data_dirs()`、`maps_dir()`）；`data_lint`、`graph_lint`、`text_reconcile`、`text_reconcile_scan`、`l10n/extract` 走它；另外 18 个工具 / 探针里写死的 `game/data/<文件>` 改成新路径（`asset_lint`、`asset_paths`、`balance_run`、`death_report`、`gen_relic_icons`、`relic_icons_hand`、`enemy_tone`、`gen_boss_laser`、`dmg_curve_plot`、`balance_audit_1110`、`pxplane_gif_exusiai_ult`、`probes/*` 六个）。`l10n/extract` 写进条目的来源路径会变成新路径；已有 CSV 的 `_source` 列下次重抽时更新（游戏按原文查表，不受影响）。
- **check_map**：规则改到 `game/themes/*/data/…`；`theme.json`、`mech/*.gd`、主题地图进「全局公共文件」（改了就分支全量）。
- **测试**：3 处写死的 `res://data/enemies.json` / `medals_layout.json` 改新位置。
- **出包验证**（本机，`ebe9f5981`）：`export_build.py` 出对外加密 Windows 包，`verify_encrypted_game.py` 通过——包内 4578 张 PNG、1362 个音频、90 个 JSON（含主题包 11 个）全部能从加密 pck 读出。
- **云端全量快检**（GCP `check.py --nocache`）：`ebe9f5981` 时 `desc_values` 报找不到 `game/data/relic_effects.json`（pathlib 写法漏改），`d6fc5d52b` 修后 218 项、217 通过，唯一失败是积木等价「金样过期」（分支必然过期，合入后重录）；asset_index / graph_lint 已在云端转绿（docs/364 §5 的修法生效）。结果分支 `cloud-results/ci-step4b-d6fc5d52b`。
- 验证：data_lint、graph_lint、text_reconcile、asset_lint 直接跑通过；check：core、ui_smoke、medals、theme_save、cloud_save、public_gallery、knight_combo、l10n、data_lint、graph_lint、check_map 通过。`tools/test_web_audio.py` 两个 `engine_patch` 用例在改前的 HEAD 上就报错（与本步无关），导出过滤器相关的用例通过。

## 3. 敌种 id 写死点

### 3.1 清单工具

`python tools/enemy_id_scan.py`（`--files` 按文件、`--list <类>` 逐条）：在 `game/scripts/**/*.gd` 的**代码部分**（去掉注释）找整串等于 `enemies.json` 某个 id 的引号字面量，按文件位置分七类。docs/357 的 546 含注释；本工具口径改前 main 为 **542 处 / 66 个文件**。有少量假阳性：`"path"`（字典键 / 德克萨斯「沿路径」）、`"knight"`（骑士同伴与结局 id）、`"tracer"`（特效种类名）、`"tear"`（伤害来源名）、`"founder" / "skimmer"`（控制遥测的分类名）——它们和敌种同名但不是敌种引用，归类时照样计数，下表「说明」里点出。

### 3.2 分类与处理（改前 → 改后）

| 类 | 改前 | 改后 | 处理 |
|---|---|---|---|
| `boss_self` Boss 脚本内部引用自己 / 自己的召唤物（`enemies/bosses/<名>*.gd`、`render/ishar*` 等） | 53 / 9 | 53 / 9 | **保持不动**（协调人定）：saint 27（伊比利亚 / 卡门两人共用脚本互相判断）、ishar 6、izumik 5、bishop 4、ishar_combos 3、paranoia 3、paranoia_combos 2、ishar_tell_draw 2、archon 1 |
| `boss_other` Boss 脚本引用别的敌种 | 13 / 4 | 13 / 4 | 保持：bishop 搭档判断 archon（招式名分支）与召唤 bone / slider；ishar 召唤 bone / slider；paranoia 召唤 bone；path 召唤 fractal。属于 Boss 自己的招式内容，第二主题的 Boss 各写各的 |
| `rule` 玩法规则 | 184 / 29 | **157 / 29** | 本步改成数据的见 §3.3；剩下的见 §3.4 |
| `render` 画法 / 特效 / 预警 | 157 / 13 | 157 / 13 | 未动：world 37、boss_bullet_draw 35、vfx 35、boss_beam 27……按敌种分支画特效与弹体。无头批跑不画世界层，theme_parity 照不到，必须配画面对照（memory「画面对照用干净局」）才能改，留给后续 |
| `ui` 图鉴 / HUD | 71 / 8 | 71 / 8 | 未动：gallery 36（敌人页的形态 / 动作表）、hud_bossbar 18（Boss 血条样式）、hud_bars 8……建议改成 `enemies.json` 的 `gallery` / `bossbar` 字段，同样要截图对照 |
| `test` 测试与机器人驱动 | 62 / 5 | 62 / 5 | 不改：autotest 21、enemy_demo 15、demo 13、god_suite 8、ult_bench 5（测试局刷指定敌人） |
| `data` 数据门面 | 2 / 1 | 5 / 1 | data.gd：`CAP_FALLBACK` 缺省值（waves.json 没写时）多了 3 个 |
| **合计** | **542 / 66** | **518 / 66** | |

### 3.3 本步改成数据的（全部在 `rule` 类，玩法零变化）

| 原写死 | 改成 | 说明 |
|---|---|---|
| `boss_patterns.FINAL_TYPES = [paranoia, knight_boss, ishar, izumik]`（3 处判断） | `g.spawner.is_final_boss_type()`：读结局表 `waves.json endings.*.boss` | 最终 Boss = 某个结局的 Boss，第二主题的结局表自动生效 |
| `music_director.FINAL_TRACK`（3 个 Boss → 配乐键） | `enemies.json` 新字段 `final_track` | 没写的用 `final`（偏执泡影） |
| `spawner.SAME_PERSON`（卡门 / 伊比利亚同一人物） | `enemies.json` 新字段 `person` | 中期池不重复出场同一人物 |
| `combat.CTRL_CATS`（奠基者 / 漂移体的控制遥测分类） | `enemies.json` 新字段 `ctrl_cat` | 报表的四个分类名不变 |
| `spawner.type_cap` 里 stone / brood / spitter / offspring 的按时间同种上限 | `enemies.json` 新字段 `cap_steps` `[[到这一秒为止, 上限], …, [-1, 之后]]` | 有 `cap` 的照旧优先 |
| `spawner` 同种全满时的换怪 `["bone", "slider"]` / `"bone"` | `waves.json` 新字段 `cap_fallback {early, late}` | 前段固定（不抽随机数）、中后段等概率抽，随机数调用次数不变 |
| `enemies.morph` 子代蜕变成 `["bone", "slider", "stone"]` | `enemies.json` offspring 的 `morph_pool` | 同上，抽取方式不变 |
| `final_attacks.NAMES`（四个最终 Boss 的补充攻击招式名，12 处） | `enemies.json` 新字段 `final_attack_names` | `g.bai.finals.NAMES[类型]`（Boss 脚本与测试在读）保留为实例字典，`_init` 时按数据建 |

### 3.4 `rule` 类还剩的（157 处），下一步建议

- **Boss 转发**：`boss_ai.gd` 20（`boss("ishar").transform_ishar(e)` 这类按类型转发到 Boss 脚本）→ docs/357 §6.2 说的「`boss_ai` 转发清理」：改成 `BossBase` 钩子（`on_phase2 / on_cocoon / safe …`），Boss 脚本各自实现。
- **最终 Boss 补充攻击按类型分支**：`final_attacks.gd` 余下的 `knight_boss` / `paranoia` 弹色、皮肤、`ishar` 真伤等 → Boss 数据字段或 Boss 脚本钩子。
- **伊莎玛拉遭遇**：`run/ishar_encounter.gd` 6、`combat.gd` 的泪滴喂食、`enemies.gd` 的泪滴接触掉血、`relic_fx` 的「击杀回复不算泪滴」→ 整块是伊莎玛拉的主题内容，宜随 Boss 一起挪进主题包（类似 docs/364 的机制接口），或给泪滴打 `no_kill_reward` 一类标签。
- **鸭爵**：`run/duck_lord.gd` 6 与 `combat` / `enemies` / `build_guide` / `telemetry` 里的 `"duck"` → 稀有敌人系统本身就是一个模块，可以照主题机制的样子做成可选模块。
- **骑士同伴 / 结局**：`allies/knight.gd`、`endings.gd`（结局 id `"knight"`、`LINE_ENDS`、机器人路线）、`game.gd` 两处 `D.ENEMIES.has("knight")` → docs/357 §6.2 的 `EndingRules`（结局线拆进主题）。
- **测试辅助常量**：`settings.TEST_BOSS_ENDING`（无敌测试包按 Boss 选结局）可以由结局表反推；`run_stats.gd` 的样例数据（截图用）。
- **假阳性**（不是敌种引用）：德克萨斯 `"path"`（ob_check / ob_core / seg_texas / combo，6）、`"tracer"` 特效种类（synergy / relic_fx / combo / telegraph，7）、`"tear"` 伤害来源名（combat NO_LOG / telemetry / run_stats，4）、`"knight"` 积木字段（ob_check、data_operator，2）。

## 4. parity

基线：Windows `build/parity_cache/3c28305c`（游戏代码自 docs/359 起没变过玩法）；Linux `cloud-results/parity-b2-5a30ebf0` rep1，外加改前代码自己跑出的 `deep_p0` 另一种走向 `cloud-results/pmdeepB-32d862186` rep2（变体 C）。

| 提交 | Windows 本机（7 局） | Linux GCP（7 局 × 两遍） |
|---|---|---|
| `546858461` 存档收尾 | **7 / 7 一致** | 两遍都 **7 / 7 一致**（其中 `deep_p0` 两遍都与改前的变体 C 逐帧相同） |
| `fb8145173` 数据搬家 | **7 / 7 一致** | 同上 |
| `56bd40aee` 敌种 id | **7 / 7 一致** | 两遍都 **7 / 7 一致**（`deep_p0` 两遍都与主基线逐帧相同） |

`theme_parity compare` 新增 `--alt <目录>`（可重复）：某局和主基线不同、但和基线提交自己跑出的某个已知走向逐帧相同，也判一致，报告里注明是哪一份。这样 Linux `deep_p0` 的判定不再靠人看：

```
python tools/theme_parity.py compare <基线 rep1> <被测> --alt <基线的变体 C 目录>
```

`deep_p0` 的 Linux 走向（docs/364 §4、docs/366 §4）现在每次都只落在改前代码自己会出的两种之一（A：710 行、C：704 行），从没出现第三种——这也说明这几步改动没有引入新的不确定性。

## 5. 待定

1. `lore / guide / onboard` 的主题部分拆分（内容阶段）。
2. `render` / `ui` 两类 228 处按敌种分支的画法与界面：改成数据要配截图 / 录像对照，单独排期。
3. `roster_tiers` 现在没有读者（§1）；如果以后恢复「首通才发凭证」，按主题读。
