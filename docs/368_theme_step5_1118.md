# 368 主题包重构 · 第五步：渲染 / 图鉴 / HUD 写死点、Boss 钩子、主题模块、混合文件拆分（11-18）

**状态：已实装，待协调人合入。** 分支 `claude/theme-step5`，以 main `3b4905393` 为底。新主题接入清单单独成页：docs/369。

| 提交 | 内容 |
|---|---|
| `10d84670c` | Boss 钩子：去掉 boss_ai 的 13 个转发、骑士出招前段 / 破茧改钩子、接潮组与落地音效读数据（§2） |
| `e5f8903e6` | 主题模块（§3）+ 混合文件拆分（§4）+ 图鉴 / HUD 写死项改读数据（§1.1） |
| `4f33cd39c` | 工具：只扫 game/scripts 的工具补扫主题包（§5）、enemy_id_scan 加 theme / fp、新增 `tools/theme_shot_diff.py`（§6） |

## 1. 敌种 id 写死点（`tools/enemy_id_scan.py`）

清单工具现在扫 `game/scripts/**` 与主题包 `game/themes/**`，多两类：`theme`（主题包里的脚本，本来就是该主题的内容）、`fp`（误报白名单 `FP`：德克萨斯的 `"path"`、特效种类 `"tracer"`、伤害来源名 `"tear"`、积木字段 `"knight"`、控制遥测分类名、宝箱来源名、作战记录样例、主题模块键等）。

| 类 | 第四步后 | 现在 | 本步 |
|---|---|---|---|
| boss_self / boss_other | 53 / 13 | 53 / 13 | 不动（协调人定） |
| rule | 157 | **88** | Boss 转发（§2）、主题模块（§3）、误报进白名单 |
| render | 157 | **153** | 4 处随模块搬进主题包；其余见 §1.2 |
| ui | 71 | **30** | 图鉴机制说明、Boss 血条纹样、结局显示顺序、结局线信物表改读数据（§1.1） |
| test | 62 | 62 | 测试驱动，不改 |
| data | 5 | 5 | |
| **核心合计**（不含 theme / fp） | 497（第四步口径） | **404 / 50 个文件** | |
| theme / fp | — | 17 / 34 | |

### 1.1 图鉴 / HUD 改读数据

| 原写死 | 改成 |
|---|---|
| `gallery.ENEMY_DESC`（25 种敌人的图鉴机制说明） | `enemies.json` 的 `gallery` 字段（没写的用 `desc`）。l10n 键不变：`enemy.<id>.gallery` 本来就是这个名字，抽取器改为随 enemies.json 一起遍历 |
| `hud_bossbar.MOTIF`（10 个 Boss 的血条纹样） | `enemies.json` 的 `bossbar_motif`（缺省 `frac`） |
| `gallery.ENDING_ORDER`、`result.gd`、`intro.gd` 三处 `["standard", "knight", "deep", "resolve"]` | `waves.json endings.*.no` + `D.ending_order()` |
| `node_cards_ui.ROUTE_RELIC / TOKEN_NAME / ROUTE_NAME`（结局线信物藏品 / 信物名 / 路线名） | `waves.json endings.*.token_relic / token_name / route_name` + `NodeCardsUI.route_relic() / token_name() / route_name()` |

画面对照：见 §6。

### 1.2 渲染与剩下的 UI（没改，原因与建议）

- **`render/world.gd` 37、`boss_bullet_draw.gd` 35、`vfx.gd` 35、`boss_beam.gd` 27、`boss_attack_draw.gd` 6、`world_tells_draw.gd` 5……**：几乎全是「某个 Boss 的某招怎么画」（弹体形状、光束、预警纹理、专属颗粒）。它们和 Boss 脚本是一体的内容，换成数据字段没有意义（第二主题的 Boss 有自己的招、自己的画法），正确的去处是**随 Boss 脚本一起进主题包**：给 `BossBase` 加 `draw_bullet / draw_beam / draw_tell` 钩子，`render/*` 只按钩子分派。这一步要逐招录像对照，量大，单独排期（建议按 Boss 一个一个挪）。
- **`hud_bars.gd` 8**：伊莎玛拉友方血条、偏执泡影 / 伊祖米克的阶段条——同上，宜做成 Boss 钩子 `hud_bar(e)`。
- **`gallery.gd` 余下**：Boss 演示的阶段切换表（`enemy_phase`）、伊比利亚 / 卡门的形态页、骑士的锁定逻辑——Boss 图鉴演示内容，宜进 Boss 脚本的 `demo_*` 钩子（`demo_moves` 已有）。
- **`hud_bossbar.DEMO`、`onboard` 的演示刷怪**：截图 / 演示用的常量，归 test 性质。

## 2. Boss 钩子（`10d84670c`）

- 删掉 `boss_ai.gd` 里 13 个按 Boss 写死的转发（`transform_ishar`、`paranoia_cocoon`、`izumik_safe`、`_knight_stakes`……）：游戏代码改走 `g.bai.boss(e.type).<方法>`，测试改走 `bai.boss("<类型>").<方法>`。
- 新钩子（`boss_base.gd`）：`pre_attack(e, dt, dir, dist, ready) -> bool`（骑士的冰枪桩 / 掷桩 / 连段原来写死在 boss_ai 里，现在由 `knight_boss.gd` 实现）、`on_shell_broken(e)`（部件吸取打空茧壳 → 偏执泡影破茧）。
- 接潮组：`e.type in ["bishop", "archon", "immortal"]` → `enemies.json pair`（已有字段）；「平时由主教放统一」→ 新字段 `pair_linker`。落地破绽音效 → `land_break_sfx`。
- parity：Windows 7/7；Linux 两遍 7/7（`--alt` 判 deep_p0）。

## 3. 主题模块（`game/themes/deep_sea/mod/`）

- 伊莎玛拉遭遇（原 `run/ishar_encounter.gd`）、鸭爵（原 `run/duck_lord.gd`）、猎潮的骑士同伴（原 `allies/knight.gd`）整文件搬进主题包，清单 `modules` 段声明，`ThemePack.make_module(game, 键)` 实例化，挂在 `g.ishar / g.duck / g.knight`（构造时机不变）。
- 没有的主题为 null：`g.duck`、`g.ishar` 的核心调用点都加了判空（机器人追鸭、HUD 指针、遥测、敌人逐帧分派、伊莎玛拉泪滴遮挡判定、game 每帧更新）；`g.knight` 核心还有 85 处直读，新主题先给空实现（docs/369 §5）。
- 「骑士结局」的规则（`endings.gd` 的 `LINE_ENDS`、机器人路线、事件特判）没动，属于 docs/357 §6.2 的 EndingRules；结局线的显示数据（信物 / 路线名 / 顺序）已改读结局表（§1.1）。

## 4. 混合文件拆分（lore / guide / onboard）

| 文件 | 共享（`game/data/`） | 主题（`game/themes/deep_sea/data/`） |
|---|---|---|
| `lore.json` | 干员 / 职业 / 博士档案（25 条） | 敌人档案（28 条） |
| `guide.json` | 通用页（指挥、HUD、商人、节点卡、操作）+ 触屏替换句 | `pages_insert: [{at: 0, page: 生命与灯火}]` |
| `onboard.json` | 通用卡片（移动、升级、招募、终结技、商人、Boss、小队、指挥、连携……）+ `ask` | 灯火 / 灯标 / 溟痕 / 最终 Boss / 鸭爵五张卡 + `drill` / `drill_vet` / `tips`（演示局与提示顺序） |

- **合并规则**（`ThemePack.load_merged(键)`，Python 侧 `tools/theme_paths.load_json` 同一条）：先读共享，再叠主题部分——两边都是字典的键合并（主题优先）、`pages_insert` 按 `at` 插回 `pages`、其余主题覆盖，`_doc` 不合并。拆分时校验过：合并结果与拆分前的原文件逐键相同（三份都是）。
- 读的地方：`gallery.gd`、`title_op_pick.gd`（lore）、`screens/intro.gd`（guide）、`screens/onboard.gd`（onboard）、`tests/calc_truth_test.gd`、`tools/text_reconcile.py`、`tools/l10n/extract.py`。
- **四语 CSV 键同步**（`game/l10n/ui.csv`，62 行改键，译文不动）：抽取规则对拆开的文件改为「共享部分 `<模块>.<文件>.<路径>`、主题部分 `<模块>.<主题>.<文件>.<路径>`」。`ui.guide.pages.0.*` → `ui.deep_sea.guide.pages_insert.0.page.*`（7 行）；`ui.guide.pages.N.*` → `ui.guide.pages.(N-1).*`（40 行）；五张主题卡 `ui.onboard.cards.<卡>.*` → `ui.deep_sea.onboard.cards.<卡>.*`（15 行）。校验：按新规则从两份文件复算的键全部在 CSV 里、没有重复键。lore 的键本来就是 `lore.<id>.…`（不含文件名），不变。游戏里这三份文件都按原文查表（`Loc.s`），键名只是抽取用的行标识，运行时不受影响。

## 5. 只扫 `game/scripts` 的工具（随主题包搬家漏掉的）

主题机制（第二步）与本步的模块搬进 `game/themes/` 后，几个工具只扫 `game/scripts/**/*.gd` 会漏掉它们：

| 工具 | 影响 | 修 |
|---|---|---|
| `release_slim._runtime_files`（字体子集） | 主题脚本里的中文（灯火 / 黑潮横幅等）不进子集字体 | 加 `game/themes/**/*.gd`。核对：目前这些字全都在别处出现过，**之前出的包没有缺字**（176 个字符，缺 0） |
| `check_release` | 发布检查（调试参数守卫等）漏扫主题脚本 | 三处 glob 加主题包 |
| `data_lint` | balance 键「代码读点」漏扫 → 本步搬走伊莎玛拉遭遇后报了一条误判（`boss/izumik_share_all_charge` 疑似拼错） | 加主题包；误判消失 |
| `make_ui_fallback` | 后备字体字表 | 加主题包脚本与数据 |
| `l10n/extract` | run 模块的脚本字符串漏抽主题机制 / 模块 | `gd` 加 `themes/*/mech/*.gd`、`themes/*/mod/*.gd`，并修主题脚本的相对路径 |

## 6. 验收

### 6.1 玩法（theme_parity）

| 提交 | Windows 本机（7 局） | Linux GCP（7 局 × 两遍，`--alt` 判 deep_p0） |
|---|---|---|
| `10d84670c` | **7 / 7 一致** | 两遍都 **7 / 7 一致** |
| `e5f8903e6` | **7 / 7 一致** | 两遍都 **7 / 7 一致** |

`4f33cd39c` 只改工具，不跑。其余机器人档（normal / bad / master / human）在第四步验过，本步没碰机器人。

### 6.2 画面（`tools/theme_shot_diff.py`）

同一组截图在改前 `10d84670c` 跑两遍（噪声基线）、改后 `e5f8903e6` 跑一遍，1280×720、`--fixed-fps 60`、窗口在屏幕外：图鉴（全部解锁）敌人 / 精英 / Boss 每一种的详情页（档案文字来自拆开后合并读的 lore、机制说明来自 enemies.json gallery）、结局四页（显示顺序来自 endings.no）、Boss 测试台每个 Boss 第 120 帧（血条纹样来自 bossbar_motif）。逐像素（单通道差 > 8 算不同），改后对改前的不同比例不超过改前对改前 + 0.05% 算一致。

- 43 组里 42 组一致；`bossbar_archon` 改后 0.13%、噪声 0.04%——差异像素在走动的 Boss 本体和血条波纹动画上（`build/shot_diff/step5/diff_bossbar_archon.png`）。单独重跑接潮组三张：archon 改后 0.072% / 噪声 0.101%、bishop 0.119% / 0.302%、immortal 0.101% / 0.112%，全部在噪声内。Boss 测试台这几帧的自然噪声在 0.04%–0.3% 之间（动画按真实计时器走），判定一致。
- 截图里能看到本步改的内容都对：例如图鉴「圣徒卡门」页，上段是 lore 档案、下段是 gallery 机制说明。

### 6.3 快检（本机）

core、prot、data_lint、graph_lint、text_reconcile 与 37 项相关场景回归（图鉴、引导 / 演示局、指南、界面冒烟四语、结算、作战记录、节点卡 / 事件、伊莎玛拉 / 骑士 / 鸭爵 / 路线、theme_save……）全部通过；Boss 钩子另跑了 30 项 Boss 相关回归。

### 6.4 顺带发现

- `game/art/operators/ling/` 的 55 张帧条已入库，但对应的 55 个 `.import` 没提交（main 上是未跟踪文件）。新工作树每次都要重新导入它们（本步的临时工作树都卡在这一步几分钟），云端也会冒「未入库的旁路文件」。按 `.gitignore` 第 1 行的约定应补交——不是本步的改动，没替你提交。

## 7. 还剩的（交给后续）

1. render / hud_bars / gallery 演示里按 Boss 分支的画法（§1.2）→ Boss 画法钩子，逐 Boss 挪进主题包，配录像对照。
2. 骑士同伴核心直读（85 处）→ 判空或空实现约定。
3. EndingRules：`endings.gd` 的 `LINE_ENDS / ROUTE_RELICS`、34 条事件特判、机器人路线。
4. `settings.TEST_BOSS_ENDING`（无敌测试包按 Boss 选结局）可由结局表反推。
5. 选主题入口、标题 / 配乐接线、Toy 单主题包（docs/369 §7）。
