# 359 主题包重构 · 阶段 0 前半：同种子基准 + 数据路径清单（11-17）

**状态：已实装，待协调人合入。** 分支 `claude/ecstatic-haslett-49e12c`：`e46cfed1b`（基准工具，只加测试输出）→ `5a30ebf00`（主题清单 + 路径门面）→ 本文档提交。以 main `c168b1f6d` 为底。上游方案：docs/357 §6（本步 = 阶段 0 的「ThemeDB + 路径重定向」，不搬数据、不动存档）；下一个主题：docs/358。

**一句话**：数据路径改经 `themes/deep_sea/theme.json` 清单取，玩法、数值、画面零变化；`theme_parity` 7 局（四结局 × 三档 + Boss 台 + 短局）在改前 / 改后逐帧逐字段相同。

---

## 1. 同种子基准 `theme_parity`

### 1.1 怎么跑

```
python tools/theme_parity.py                        # 基线 = main（缓存）、当前工作树各跑 6 局，逐帧逐字段比
python tools/theme_parity.py --ref <提交>           # 基线换成别的提交
python tools/theme_parity.py --self                 # 当前工作树自己跑两遍（查噪声）
python tools/theme_parity.py --cases short,boss     # 只跑部分局
python tools/theme_parity.py record <目录>          # 只录一套（GCP / 例行任务用）
python tools/theme_parity.py compare <目录A> <目录B>
python tools/check.py --only theme_parity           # 同第一条，基线取环境变量 ARK_PARITY_REF（缺省 main）
```

- 本机约 25–50 分钟（每会话 2 个 Godot，负载高时更久），不进 `--auto` / 全量。
- **GCP**（推荐，本机不占 CPU）：两次提交各开一台跑 `record`，本机 `compare`：

```
printf '%s\n' 'python3 tools/theme_parity.py record $OUT/rep1 --jobs $GODOT_MAX_PROCS' > cmds.sh
python tools/gcp/batch.py run parity-a-<sha8> --commit <改前> --cmd-file cmds.sh
python tools/gcp/batch.py run parity-b-<sha8> --commit <改后> --cmd-file cmds.sh
git fetch origin cloud-results/parity-a-<sha8> cloud-results/parity-b-<sha8>    # 取出 build/cloud/<tag>/rep1 两份目录后：
python tools/theme_parity.py compare <A 目录> <B 目录>
```
  GCP（Linux）和本机（Windows）不是同一平台（docs/36 §7.4），只能同平台两两比。
- 基线缓存：`<主仓库>/build/parity_cache/<提交前 8 位>/<局名>_<参数哈希>.txt`，同提交同参数只跑一次。
- **被测两边都必须带 `--parity`**（`e46cfed1b` 起）。比 `e46cfed1b` 更早的提交没有 PARITY 行，工具会报「PARITY 行太少」。

### 1.2 局目（`tools/theme_parity.py` 的 `CASES`）

| 局名 | 参数 | 结局 / 结果（本机） |
|---|---|---|
| `standard_p0` | seed 11 · 水月 · `--preset=0` · `--route=none` | 结局一 standard，胜，约 731 秒 |
| `knight_p2` | seed 13 · 斯卡蒂 · `--preset=2` · `--route=knight` · `--god --meta=full` | knight（两平台） |
| `deep_p0` | seed 33 · 水月 · `--preset=0` · `--route=heart` · `--god` | Linux：deep；Windows：standard |
| `deep_p0w` | seed 37 · 同上 | Windows：deep；Linux：standard |
| `resolve_p1` | seed 22 · 水月 · `--preset=1` · `--route=memory` · `--god` | Windows：resolve；Linux：standard |
| `boss` | seed 15 · 水月 · `--bosstest=ishar2`，每 5 帧一行 | 伊莎玛拉二阶段，约 610 帧后自动退出 |
| `short` | seed 3 · 逻各斯 + 拉普兰德 · `--maxt=180` | 3 分钟短局 |

共同参数：`--balance --bot=expert --trace=1 --parity=15`（`--balance` 步长约 1/15 秒，每 15 帧 ≈ 每游戏秒一行）。

**结局靠 seed 选出来**：机器人按 `--route` 选卡，但能不能翻到结局线入口卡看发牌。实测（e46cfed1b，GCP `cloud-results/parity-sweep-1117` + 本机）：
- 不带 `--god` 时 `--preset=1/2` 的高手机器人多半撑不到路口二（seed 12 维什戴尔 268 秒、seed 13 斯卡蒂 91 秒倒下），所以四条线都加了 `--god`（队长倒下回满，测试专用，`settings.gd test_god`）。
- `--route=heart` 在 GCP 跑了 28 局（seed 25–38，水月潮位 0 / 维什戴尔满认知）只有 **seed 33** 走到 deep，本机跑了 seed 32–40（水月潮位 0）只有 **seed 37** 走到 deep——跨平台本来不逐局一致（docs/36 §7.4），所以两局都留，各自保证本平台有一局 deep；其余多为 standard，少数 knight。`--route=memory` 和 `--route=heart` 在 seed 21–24 上结果逐局相同（两条线只在「opening」事件分岔，这几局都没翻到）。**机器人的 heart / memory 线覆盖很弱**，以后改结局线代码要另补定向用例（记为发现，未改）。
- 局名里的结局是「实际走到的」，如果以后的改动让某局换了结局，`compare` 会在 PARITY 的 `end=` / `endg=` 字段报分歧。

### 1.3 比什么

每局收三种行，**全部**要一致：

1. **PARITY**（新，`autotest.gd parity_line()`，`--parity=N` 每 N 帧一行；按帧计不按 `g.t`，所以 `--bosstest` 冻结时间也照样出）。36 个字段：
   `f` 帧号、`t` 游戏时间、`st` 状态、`lv` / `xp` / `xpn` 等级经验、`k` 击杀、`hp` / `mhp`、`lamp` / `lcap` 灯火、`thr` 威胁档、`ing` 源石锭、
   `n` 敌数、`eh` 敌人逐个（类型、位置 ×0.001、生命 ×0.001）拼串哈希、`boss` Boss 类型与血量、`rng` 五条玩法流 state、`pos` 队长位置、
   `rl` / `nrl` 藏品 id 序列哈希与件数、`gr` 成长项哈希、`wp` 支援哈希、`sq` 队友哈希（同 TRACE）、`nd` 神经损伤哈希、`zone` 缩圈（状态 / 半径 / 圆心 / 冻结）、
   `mire` 溟痕（个数 / 下次时刻 / 站在里面的程度）、`bcn` 灯标数、`eb` 敌弹数、`gem` 经验结晶数、`end` 结局、`endg` 结局箱（当前结局 / 路口数 / 翻开哪张 / 摊牌位 / 冻结）、
   `ck` / `nch` 选项面板类型与选项数、`plv` / `pch` 待升级 / 待开箱、`shield` 护盾层。
   报第一处分歧：局、帧、游戏时间、第一个不同的字段与两边的值、同行其余不同字段。
2. **TRACE**（docs/36 §3.2 原格式，每秒一行）逐行。
3. **BALANCE**（结算数据 `telemetry.record`）逐键；只去掉 `prof` 与 `bot.peak` / `bot.peak_min`（同屏特效 / 飘字峰值，画面计数，docs/36 §7.7 已知会差几个）。

PARITY 只在 debug 构建的 autotest 里、只读、不碰 rng；正式游戏路径零开销。

### 1.4 稳定性（零噪声确认）

- **本机 Windows**：`e46cfed1b` 内容上 `--self` 两遍，6 局（当时的旧局目，含 3 局倒下的路线局）PARITY 2137 行 × 36 字段、TRACE、BALANCE 全部一致；新局目见 §3。
- **GCP Linux**：两次提交各录两遍（rep1 / rep2）互比，见 §3。
- 已知不确定性来源（这一轮都没触发，记在这里供以后排查）：
  - 画面计数（特效 / 飘字峰值）按真实帧变 → 已从 BALANCE 剔除；
  - `g.vrng` / 全局 `randf()` 被玩法读到会让同种子分叉（docs/36 §3，check.py `repro` 的 `--rngshift` 专抓这一路）；
  - 跨平台（Windows / Linux）浮点与调度不同，结果本来就不逐局一致（docs/36 §7.4），所以只做同平台对照；
  - 字典遍历顺序：GDScript Dictionary 按插入序，PARITY 的 `gr` / `wp` 用 `JSON.stringify` 哈希，同代码同输入顺序固定；如果以后重构改了 `growth` / `weapons` 的插入顺序（玩法不变），这两个字段会假报分歧——遇到时先看 TRACE / BALANCE 是否一致再判断；
  - docs/36 §7.7 记过 bbdb305c9 上云端同种子自己也分叉（36 / 168 局）。**这次在 Linux 上抓到一例**：`deep_p0` 伊莎玛拉战 t≈646 秒，4 份记录里 1 份分叉，rng 不变而 Boss 血不同（§5 第 1 条）。所以 Linux 上 `deep_p0` 单独报分歧时，先看同一提交自己跑两遍是否也分歧，再判断是不是改动引入的。

## 2. 主题清单与路径门面

### 2.1 文件

- `game/themes/deep_sea/theme.json`：清单。主题 id 沿用 docs/357 的 `deep_sea`（地图 id、云存档迁移设想里也都叫 `deep_sea`）。
- `game/scripts/core/theme_pack.gd`：门面 `ThemePack`（**不叫 ThemeDB**：`ThemeDB` 是 Godot 内置单例类名，常量叫这个会「shadows a native class」整片编译失败，docs/357 §6.2 的名字要改）。用法 `const ThemePack = preload("res://scripts/core/theme_pack.gd")`，不做自动加载（memory：render / -s 契约测试里直接写自动加载会编译失败）。
  - `ThemePack.id()`：当前主题，阶段 0 恒为 `deep_sea`；
  - `ThemePack.path(键)`：清单 `data` 段里的 res:// 路径；清单缺键时 `push_error` 并退回 `res://data/<键>.json`；
  - `ThemePack.maps_dir()` / `ThemePack.map_path(地图 id)`：`maps.dir`（`res://data/maps`）。
  - 清单读一次缓存在静态变量；只读文件、不抽随机数。
- 导出：两个导出预设和 `tools/encrypted_release.py` 的 `include_filter` 加 `themes/*/theme.json`（json 不是资源，不列就不进包，ThemePack 会退回旧路径并报错）；`tools/test_web_audio.py` 加了这条断言。

### 2.2 清单格式

```json
{
  "id": "deep_sea",
  "name": "水月与深蓝之树",
  "data":   { "<键>": "res://…json", … },
  "maps":   { "dir": "res://data/maps", "default": "deep_sea" },
  "assets": { "title_bg_script": …, "title_logo": …, "music_dir": …, "music_layers": …, … }
}
```

- `data`（17 个，全部经 ThemePack 读）：`waves`（含 `endings` / `cross_deck` / `events` / `boss_times` / `mid_pool` / `threat`）、`enemies`、`events_v2`、`relics`、`relic_effects`、`meta_tree`、`meta_roots`、`guide`、`onboard`、`lore`、`medals`、`medals_layout`、`doctor`、`enemy_pixels`、`enemy_redraw`、`ult_text`、`ult_audio`。
  - `meta_tree` / `meta_roots`（认知塑造）、`ult_text` / `ult_audio`（干员终结技）按 docs/357 §4 更可能**跨主题共享**；进清单是为了留口子：第二主题的清单可以直接指向同一个文件。
- `maps`：地图目录（`Map.list_ids` 列它）与缺省地图；地面、景物、环境光、光柱、雪花、溟痕参数都在地图 json 里。`Cfg.map_id` 仍由 `settings.gd` 管，缺省值没改。
- `assets`：**只登记、没接线**——标题背景（`title_deep.gd` / `title_tree.gd`、`art/ui/title_deep/`、两个 shader）、配乐（`audio/music/`、`suno_layers.json`、`web_music.json`）、主题相关的 l10n 表（enemies / events / relics）。这些现在仍是代码里 `preload` / 常量写死，阶段 2（选主题界面、标题背景按主题）再改。

### 2.3 改了哪些读取（19 个脚本、30 处）

| 文件 | 改为 |
|---|---|
| `enemies/enemy_db.gd` | `enemies`、`waves`（`data.gd` 的 D.ENEMIES / D.THREAT 等都经它） |
| `endings.gd`、`core/event_book.gd` | `events_v2` |
| `core/relic_db.gd` | `load_files()` 缺省参数 → `relics` / `relic_effects`（显式传路径的调用照旧） |
| `core/meta.gd`、`screens/meta_tree_ui.gd` | `meta_tree`、`meta_roots`（删了 `const PATH`） |
| `core/medals.gd`、`screens/medals_ui.gd` | `medals`、`medals_layout`（删了 `const PATH` / `LAYOUT`） |
| `gallery.gd`、`screens/title_op_pick.gd` | `lore`、`doctor`、`ult_text` |
| `game.gd`、`characters/doctor.gd`、`screens/initial_stats.gd` | `doctor`、地图 `map_path` |
| `screens/intro.gd`、`screens/onboard.gd` | `guide`、`onboard` |
| `run/ult.gd` | `ult_text`、`ult_audio`（删了 `TEXT_PATH` / `AUDIO_PATH`，外部没人引用） |
| `run/ult_bench.gd` | `waves` |
| `art.gd` | `enemy_pixels`、`enemy_redraw` |
| `world/map.gd` | `maps_dir()`、`map_path()` |

### 2.4 写死点统计（grep，`game/scripts/**/*.gd`）

| 口径 | 改前（c168b1f6d） | 改后 |
|---|---|---|
| 清单里 17 个主题文件 + `data/maps` 的 `res://data/…` 字面量（不含注释） | 28 行 / 20 个文件 | **0**（只剩 `relic_db.gd` 文件头两行注释） |
| 全部 `res://data/` 字面量 | 56 行 | 26 行（都是通用数据：`characters/`、`balance.json`、`build.json`、`cards.json`、`synergy.json`、`pxp_*` / `fx_*` 特效配方、`boot_*`、`credits`、`practice_squads`、`ult_px_skadi`） |

**还写死、留给后续的**：
- **测试 5 处**：`calc_truth_test`（guide）、`cloud_save_test` / `knight_combo_test`（enemies）、`medals_test`（medals_layout）、`meta_mech_test`（meta_tree）。测试只跑 deep_sea，搬数据时一起改。
- **Python 工具 27 个文件 51 处**直接读 `game/data/<主题文件>.json`（`balance_run.py`、`art_lint.py`、`asset_lint.py`、`asset_paths.py`、`desc_value_audit.py`、`death_report.py`、`l10n/extract.py`、`new_op_check.py`、`gen_relic_icons.py`、`install_enemy_redraw.py` 以及一批 probes / 一次性审查脚本）。搬家那步要给 Python 也做一个读清单的小函数，或者搬家后统一改路径。
- **敌种 id 字面量 546 处 / 67 个文件**（docs/357 §1）：本步按任务不动。
- **标题 / 配乐 / 加载页**：`title.gd:44,52`、`screens/loading_screen.gd:11`、`screens/boot_screen.gd:133` 的 `art/ui/title_deep/…` 与 `title_deep.gd`；`sfx.gd` 的 `audio/music/…`。阶段 2。
- **l10n**：`core/loc.gd` 的模块表（enemies / events / relics 三张属主题）。
- **主题机制**（灯火 411 / 溟痕 318 / 灯标 229 / 缩圈 214 行，docs/357 §2）：下一步。
- `balance.json` 里的 `lamp / beacon / terrain` 段、`relic_fx.gd` 的主题规则（`deep_sea` / `tree_light`）、`endings.gd` 的 `LINE_ENDS` / `ROUTE_RELICS` 与 34 条事件特判：阶段 1。

## 3. 验收结果

改前 A = `e46cfed1b`（main c168b1f6d + 只加 PARITY 输出），改后 B = `5a30ebf00`。

| 平台 | 对照 | 结果 |
|---|---|---|
| 本机 Windows | A vs B，7 局 | **7 / 7 一致**：PARITY 4105 行 × 36 字段、TRACE、BALANCE（73–74 键）逐项相同。结局 standard（胜 731 秒）/ knight（胜 647）/ deep（胜 750）/ resolve（胜 684）/ standard（deep_p0 在 Windows）+ Boss 台 328 行 + 短局 182 行 |
| 本机 Windows | A 自比（旧局目 6 局） | 6 / 6 一致，PARITY 2137 行 |
| GCP Linux | B rep1 vs B rep2，7 局 | **7 / 7 一致**，PARITY 4123 行 |
| GCP Linux | A rep2 vs B rep1 / rep2，7 局 | **7 / 7 一致**（结局 standard / knight / deep / standard / standard，Linux 上 resolve_p1 也是 standard） |
| GCP Linux | A rep1 vs 其余三份 | 6 / 7；`deep_p0` 在 t=646.5 秒分歧——**A 自己两遍就不同**（A rep1 vs A rep2 同处分歧），B 两遍与 A rep2 完全相同：是改前就有的偶发不确定性，见 §5 第 1 条，不是本步引入 |

GCP 结果分支：`cloud-results/parity-a2-e46cfed1`（A，提交 a8f3fd0b1 = e46cfed1b + 结果文件）、`cloud-results/parity-b2-5a30ebf0`（B，b1ed550ee = 5a30ebf00 + 结果文件），各含 rep1 / rep2 两套原始记录和 `self_compare.txt`。两台 e2-standard-8 抢占式并行，各约 7 分钟、约 0.01 美元。

**汇总**：改前 / 改后共 7 局（同平台对照）全部逐帧逐字段一致；Windows 4 个结局全覆盖，Linux 覆盖 standard / knight / deep。

快检（GCP e2-standard-8，`check.py --nocache` 真全量，B = 5a30ebf00，结果分支 `cloud-results/ci-theme-5a30ebf0`）：217 项，214 通过；3 项失败都与本步无关：
- 积木等价「金样过期」14 组：分支改了玩法输入文件的哈希就必然过期（docs/36 §1.4，按规矩不在分支重录，合入后协调人在 main 重录）；
- `asset_index` / `graph_lint`：仓库里提交的 `game/art/index.json` 落后于磁盘贴图（缺 `op_lappland_move_throw`、`op_wisadel_move_s2_attack` 等 66 个名字），云端新检出就会报；本机按惯例先跑 `asset_index.py` 不会报。与主题改动无关。
其中 core、check_map、l10n、ui 冒烟、boss_trial、settlement、toy_support、release_slim、复现（含 `--rngshift`）都通过。

## 4. 交给下一步（阶段 0 后半 / 阶段 1：主题机制接口）

1. **每挪一样东西就跑一次 `theme_parity`**（基线 = 挪之前那个提交）。机制挪位置最容易改变 `g.rng` 调用顺序，PARITY 的 `rng` 字段会第一时间报。
2. 机制接口建议仍按 docs/357 §6.2 的 `ThemeMechanic`（`setup / update / on_hit / on_kill / arena_clamp / light_radius / hud_bars / bot_hint / music_tension / trace_fields`）；挂到 `ThemePack` 上由清单的 `mechanics` 段列出（例如 `["lamp", "mire", "beacon", "tide_zone"]`），本步没有加这个段。
3. PARITY 已经覆盖灯火（`lamp` / `lcap`）、溟痕（`mire`）、灯标（`bcn`，只数个数——挪灯标时建议给 PARITY 加灯标进度哈希）、缩圈（`zone`），以及结局箱（`endg`）。
4. 数据搬家（`res://data/` → `res://themes/deep_sea/`）只需改清单路径 + §2.4 的测试 / Python 工具写死点 + 导出 `include_filter`；搬之前先给 Python 工具一个读清单的入口，避免 27 个工具各自改。
5. 存档主题层级（docs/357 §4）与本步无关，还没动。

## 5. 记下没修的

1. **最终 Boss 段偶发不确定性（Linux，改前就有）**：`deep_p0`（seed 33 水月潮位 0 `--route=heart --god`）在 e46cfed1b 上 GCP 跑两遍，t=645.5 → 646.5 秒之间伊莎玛拉的血一遍掉到 32092.39、一遍 32000.67（差约 91.7），而这一行**五条玩法 rng 完全相同**；下一行（647.5 秒）起击杀、敌数、掉落 rng、队友哈希跟着分叉。说明伊莎玛拉战里有一笔伤害不经 rng、却随运行而变（候选：按真实时间 / 帧间隔算的伤害、读了 `g.vrng` 或全局随机的玩法分支、字典遍历顺序），4 份记录里出现 1 次。旁证：此时 `g.bosses` 里还留着已死的 carmen（-10.99）/ archon（1.00）。Windows 本机 deep 局（seed 37）两遍一致。排查方法：对这局 `--parity=1` 在 9810–9825 帧逐帧比，再在伊莎玛拉受伤入口打点。docs/36 §7.7 记过的「bbdb305c9 云端同种子 36 / 168 局分叉」很可能同源。
2. 机器人 heart / memory 结局线覆盖弱（§1.2），批跑里这两条线的样本大多其实走成了 standard。
3. 局卡死不退出：脚本编译失败时 `--balance` 局不会自己退，`theme_parity` / `trace_base` 要等到超时（40 分钟）。这次改名前就这样卡过一次。
