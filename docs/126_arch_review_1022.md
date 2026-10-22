# 126 · 架构复审：模块化扩展与耦合（架构，2026-10-22）

> 用户 10-22：「目前的架构和代码是否有问题？是否方便模块化扩展？」协调人派：只读 + 写文档，不改代码。
> 基线 main 711da1c0。做法：四路只读盘点（扩展触点 / 耦合热点 / 校验与测试面 / 三端分支点），关键结论回到代码抽查过（hud.gd 236、doctor.gd 15、boss_ai.gd 128、title.gd 899–914、character.gd 286 / 293、headhunt.gd 93）。行号是 711da1c0 时的位置。
> 对照 docs/101（10-15 审计定案）。那份管的是「每帧性能 + C++ 预留」，本文管的是「加内容方不方便、哪里容易出事」。docs/101 已做的 S8（招募校验只在 debug 跑）、B1–B4、B6（干员积木拆段）本文不再重复。
> 「TRACE」列指同 seed TRACE（tools/trace_base.py）：**不动** = 可以逐行相同地做完；**格式变** = 玩法不变但 TRACE 行的内容变，要协调人统一重录金样；**会变** = 玩法结果变。

## 0. 结论（一页）

**框架整体能扩展，干员这条线最顺；升级卡、局外界面、Boss 和藏品四条线还要改代码。**

| 加一个… | 改几处 | 能否只改数据 | 一句话 |
|---|---|---|---|
| 干员（复用现有积木） | json 1 + lore 1 +（可选）音效表 1 | **是** | 名单扫目录，选人 / 图鉴 / 寻访 / Boss 演练自动出现；拉普兰德、歌蕾蒂娅首个提交 32dfd996 就是只填 json |
| 干员（新积木语义） | 再加 seg 文件 + 插进单继承链 + ob_check 分派 + ob_core 执行分支 | 否 | 18 个 seg 串成一条继承链，链尾写死在 data_operator.gd:22 |
| 普通敌人（现有 3 种 ai × 4 种 extra.mode） | enemies.json + waves.json + enemy_pixels.json + 素材 | **是** | 特殊机制（育母、滑行、收割、泪、口袋）按 `e.type == "…"` 写死在 enemies / spawner / world / combat |
| Boss | 脚本 1 + `boss_ai.SCRIPTS` 1 + world.gd 绘制 match + 出场卡 + 音效名 + waves | 否（约 6 处） | 招式要代码是合理的，但绘制挂点 / 音效 / 出场卡散在别处 |
| 藏品（现有 stat / do） | relics.json + relic_effects.json + 图标 | **部分** | 新 `rule` 要在代码里加读点；relic_fx.gd 里 26 处 `g.relics.has("数字")` 写死 |
| 升级卡（博士被动 / 填充） | doctor.gd 常量 + 3 个 match + progression.gd + bot.gd 权重 + 图标 | **否（5–6 处）** | 全是 GDScript 常量 |
| 局外成长节点 | meta_tree.json | **是**（现有 5 种 effect、已登记的 stat、已有的线） | 新线要改 meta_tree_ui.gd:11 `LINES` |
| 局外界面 | title.gd 6 处 + title_tiles.gd 2 处 | 否 | 菜单按整数下标写死；没有界面层级栈，Esc 各自处理 |

**耦合**：game.gd 已从 1925 行降到 1865 行，但顶层字段 332 个，`_ready` 约 370 行里夹着难度预设、批跑 / 测试参数解析，局终结算放在 `_process`。全局 `g` 被 111 个文件访问 9807 次（world 1034、autotest 778、combat 540），UI 拿 `g` 当服务定位器（`g.hud` 548、`g.font` 402）。新系统里，响应动作、分支节点、大群压力、语音都是独立模块，只加了少量钩子，接得干净。局外成长 + 寻访接得最乱：寻访界面在 HUD 的绘制回调里打开，规则接口靠反射探新旧版本。

**数据契约**：干员 json 校验最完整（契约 V1–V9 + 积木校验，快检全员过一遍）；藏品、局外树、敌人帧条在测试里查。**敌人表、波次表、平衡表、升级卡没有 schema**：`balance.json` 拼错的键会静默取缺省值，改了等于没改，也不报错。

**测试面**：快检 111 项（76 项场景回归 + 22 局冒烟 + 核心契约等），干员 / 敌人 / Boss 覆盖好。30 多个界面 / 渲染脚本没有直接测试（寻访、商店、作战记录、HUD 各层、局外树、胜利流程）。同 seed TRACE 只记队长、敌人和随机流状态，**队友、技力、灯火、藏品不在里面**：只改队友内部状态的改动，「关着 TRACE 不变」查不出来。

**三端**：基本收敛在壳层。Toy SDK 全在 JS 壳（tools/web/container.js、cloud.js），GDScript 只读 `__sySafe` / `__syCloud` 两个全局；平台判断集中在 settings.gd（Cfg）。例外是 `Cfg.touch_device()` / `phone_ui()` 的布局分支散在 UI 里约 50 处。原生模块有 GDScript 回退和逐行等价测试，但导出预设排除了 `bin/*`，正式包现在都走 GDScript。

**问题数**：阻碍扩展 6 条、风险 7 条（R8 核对后撤销）、整洁 7 条（§6）。**建议先做的 5 项**见 §7；性能 / 帧率视角见 §8，已做的见 §9。

## 1. 加一项内容要碰几处（详细）

### 1.1 干员

- 数据：`data/characters/<id>.json`；名单由 `character.gd:84 list_ids()` 扫目录，选人 title.gd:1574、图鉴 gallery.gd:311、寻访 core/roster.gd:30、Boss 演练 boss_trial_menu.gd:66 都读它。脚本缺省走 data_operator.gd（character.gd:277）。
- 档案 `data/lore.json`；语音按文件名约定 `audio/voice/<id>_<key>.ogg`（sfx.gd:595），不登记；干员音效 `sfx.gd:17 OP_SFX` 按 id 写表，有通用兜底（:61）。
- 写死 id 的地方（新干员不用改，但说明有个案逻辑漏在公共代码里）：ob_core.gd:422 `o.id == "suzuran"`（减速用 stop 型）、squad.gd:578 `"wisadel"`（语音换笑声）、initial_stats.gd:13 `HITS {"irene": 2}`、vfx.gd:83–84 打击感 heavy / melee 两个 id 数组、gallery.gd:318 / title.gd:1606 水月排第一、roster.gd:13 `STARTERS` / :16 `PRIORITY`（这两个本来就是规则表）、check.py:632 / 744 测试登记。
- 职业固定 8 类，`CLASS_ORDER` / `CLASS_COL` 在 title.gd:15、headhunt.gd:21、gallery.gd:549、character.gd:60 各写一份。
- 新积木语义：seg 单继承链（seg_angelina ← seg_texas ← … ← seg_skalter，op_blocks.gd:7 与 data_operator.gd:22 预载链尾）+ ob_check.gd:183–240 `_block` 分派 + ob_core.gd:334 `match b.shape`。p1 / p2 响应动作的经验：多数新语义能做成现有积木的一个参数（`at: end`、`from: leader`、`aim: behind_leader`），只有塞雷娅晶柱要新积木名。

### 1.2 敌人与 Boss

- 普通敌人：enemies.json（enemy_db.gd:16 全量读；图集 art.gd:113、图鉴 gallery.gd:329、精英池 spawner.gd:114 遍历）+ waves.json（threat.pool / horde / horde_mix）+ enemy_pixels.json。行为只能在 `ai = melee / ranged / static`（enemies.gd:434）× `extra.mode = swipe / pulse / pierce / volley`（enemy_ai.gd:90）里组合。
- 写死：combat.gd:14 `ECOL`（有缺省色）、gallery.gd:29 `ENEMY_DESC`（缺了退回 json）、spawner.gd:121 兜底 `"pocket"`；特殊机制 `e.type == "brood" / "slider" / "reaper" / "tear" / "pocket"` 散在 enemies / spawner / world / combat。
- Boss：enemies.json `role: "boss"` + `enemies/bosses/<x>.gd`（继承 boss_base）+ boss_ai.gd:128 `SCRIPTS` 登记（未登记不出招）+ waves.json `mid_pool` / `endings[].boss`（演练列表由此自动生成）+ boss_intro.gd:28 `CARDS` / :46 `PORTRAIT_CROP` + sfx.gd:8 `NAMES` 的 `boss_<type>`；绘制挂点 world.gd:1682 `match e.type`、:1825 `DC_SKIP_TYPES`；enemy_ai / world 里还有多处 `type == "ishar" / "paranoia"`，music_director.gd:75 写死 izumik。

### 1.3 藏品、升级卡、局外节点

- 藏品：relics.json（名字 / 稀有度 / 流派）+ relic_effects.json（只有写了效果的才进池）+ 图标。effect 种类 stat / rule / on_gain / trigger / spawn / status；现有 stat 与 do 分支可纯数据，新 rule 名要在代码里 `rfx.rule("名")`（relic_fx.gd:106）。写死：relic_fx.gd 26 处 `g.relics.has("数字")`、:840 `"174"`、knight.gd:85 / 108 与 endings.gd:248 / 266 的 `"222"` / `"223"`、build_affinity.gd:21 / 23 交互表。
- 升级卡：被动卡 doctor.gd:15 `PASSIVES` + :351 `apply_passive` + :376 `passive_desc` + :403 `passive_preview`；填充卡 :421 `filler_cards` + :431 `apply_filler`；种类分派 progression.gd:491；回复类 progression.gd:32 `HEAL_CARDS`；机器人权重 bot.gd:397–399；图标 `growth_<id>`。
- 局外节点：meta_tree.json（req / need / order）；生效 core/meta.gd:167 `apply_run` 认 stat / rule / start_ingots / once_heal / start_relic；stat 必须已在 stat_defs.gd；线名 meta_tree_ui.gd:11 `LINES`。

### 1.4 局外界面

以「认知塑造」为样板：title.gd:18 `ITEMS`、:153–160 preload + add_child、:717 / :788 两处 overlay 可见性枚举、:776 `menu_track`、:862 `_menu_ids`、:899–914 `_activate` 按下标 match；title_tiles.gd:11–13 `CN / EN / ICON`（与 ITEMS 重复）、:28 分行 `[[0], [1, 2, 6], [3, 4, 5]]`。Esc 由各界面自己的 `_input` 处理（meta_tree_ui.gd:147），title 靠 visible 变化察觉（:720）。手柄统一翻成键盘事件（pad.gd:33），触屏靠触摸模拟鼠标（touch.gd），这两点对新界面友好。局内界面另走 game.gd:85 `enum S` 与 :1213 / :1288 输入分派。

## 2. 耦合热点

| 文件 | 行（10-15 → 10-22） | 说明 |
|---|---|---|
| render/world.gd | 4267 → 4030 | 130 个函数；69 处写 `g.x =`（`update_visuals` 103–206、`update_player_feel` 3951–4014），主控 / 博士动画状态机 1516–1667 |
| title.gd | 2764 → 2787 | 选人页 1485–2746 约 1260 行（docs/101 §3.6 建议拆出，未做）；`_ready` 98–384 有 27 处 `dev_args` |
| characters/character.gd | 1699 → 2517 | 189 个函数；基类里带 JSON 加载 + 文本公式求值（84–260）+ 契约校验（293–414） |
| game.gd | 1925 → 1865 | 顶层字段 332、常量 87；`_ready` 628–1000；难度预设 879–905；批跑 / 测试参数 941–998（`dev_args` 22 次）；局终结算在 `_process` 1125–1130 |
| characters/data_operator.gd | 1247 → 1623 | 响应、分支、精英化挂钩都进了 `_sustain` / `update` |
| run/autotest.gd | 1270 → 1353 | `step()` 351–860 一个函数约 510 行，另夹性能采样（1099–1237）与音效统计 |
| screens/headhunt.gd | 新 1061 | 93–151 用 `get_script_constant_map` / `callv` 反射探 roster.gd 新旧接口（注释「合入时由协调人对接」） |
| screens/hud.gd | 581 | 分派器；236 在绘制回调里 `g.headhunt.maybe_open()` |

- **全局 `g`**：111 个文件 9807 次。高频字段：`g.t` 854、`hud` 548、`ppos` 476、`vfx` 416、`font` 402、`tex` 262、`fx` 252、`vrng` 232、`state` 208、`enemies` 198、`squad` 192。autoload 4 个：Cfg（53 个文件 581 处）、Sfx（42 / 316）、Pad（22 / 135）、Cloud（3 / 19）。
- **存档迁移**：settings.gd 有 `DIFF_VER := 4`、`LOOK_VER := 1` 两个版本号，迁移不是链式：300–304 `dv < 2 → _migrate_diff`、`elif dv == 3 → _migrate_tide_to_preset`（`_migrate_diff` 注释说一步到位成 v4 含义；dv == 2 不处理，是否有 v2 存档在外需核）；`_migrate_tide()`（442）全仓无调用。其余迁移按字段判断、无版本号：`play_speed == 2.0` 回落（245）、无 [roster] 段走 `_migrate_roster`（297）、每次加载都调 `roster.migrate_tickets()`（291 / 669）。局外成长与寻访存在 settings.cfg 的 [meta] / [roster] 段，没有各自的版本号。只有云存档 core/cloud_pack.gd 是规范写法（`VERSION` / `MIN_READ` / `MIGRATIONS` 逐级迁移，有测试）。测试覆盖：`migrate_brightness`（look_test）、`migrate_tickets`（roster_test）、云存档迁移（cloud_save_test）；**`_migrate_diff` / `_migrate_tide_to_preset` 没有测试**。
- **10-15 之后的新系统怎么接的**：
  - 响应动作：独立 blocks/responses.gd，data_operator 两处调用，g 上加 `leader_still_t / leader_skill_n / leader_skill_i` 三个字段。干净。
  - 指挥模式：状态在 squad.gd（stance / stamina / stance_log），game.gd 只有 `toggle_command` 与一处输入。干净。
  - 第 4 节点分支：progression.gd + character.gd，game.gd 一处 `open_branch_queued`。干净。
  - 大群压力：数据在 waves.json，逻辑在 spawner.gd 434–495，g 上加 horde_* 字段。可以。
  - 三档难度：`data.gd:66 DIFF_PRESETS` + game.gd 879–905 应用 + 选档界面在 title.gd 403–695。界面不该在 title 里。
  - 语音：sfx.gd 579–676，调用点 character.gd 2 处、squad.gd 2 处。干净。
  - 局外成长 + 寻访：game.gd 加了 preload、字段、`Meta.apply_run`（701）、`on_run_end`（1127）、`_update` 两段（1678–1681 / 1704–1707）、寻访输入（1307）；hud.gd 236 在绘制里打开寻访；title.gd 挂 meta_ui。散得最开。

## 3. 数据契约校验

| 数据 | 校验 | 位置 |
|---|---|---|
| characters/*.json | **完整**：契约 V1–V9 + 积木校验（加载时只在 debug，快检全员） | character.gd:286–414、operator_contract.gd、blocks/ob_check.gd；test_core.gd:289 / 343；tools/op_text_check.py、art_lint.py |
| relics.json + relic_effects.json | 测试时（264 件，属性 / 事件 / 动作 / 前置 / 说明 / 门槛 / 流派） | test_core.gd:189–235、combat_core.gd:83 |
| enemy_pixels.json | 测试时（帧尺寸、锚点、缩放、29 个敌人 draw_scale） | tests/enemy_pixel_contract.gd |
| meta_tree.json | 测试时（总价、前置、推荐顺序、文案齐全） | meta_test.gd:40–60 |
| voice_manifest.json | 测试时（文件存在、不循环、时长） | test_core.gd:375 |
| **enemies.json** | 只有加载容错 + 行为测试（部分字段） | enemy_db.gd:16–28；enemy_attack_variety_test、enemy_demo_test |
| **waves.json** | 只有容错；只测 horde_mix 一项 | enemy_db.gd:31–35；prot_test.gd:619。boss_times / mid_pool / endings / events 无校验 |
| **balance.json** | 只有容错（「找不到的键一律返回缺省值」）；零散测试 | balance.gd:2；tide_test、economy_regression |
| **升级卡**（doctor.gd 常量）、难度预设（data.gd）、寻访卡池（roster.gd） | 没有 schema，只有行为测试 | build_progression / card_desc / node_test、tide_test、roster_test |
| credits / guide / lore / maps | 无（加载缺失时 push_error） | — |

所有 json 另有 check.py:136 的「能解析」检查。

## 4. 测试面

- 快检全量 111 项（check.py:1116–1166）：不开 Godot 的 7 项（json 解析、art_lint、release_slim、op_text、ob_tag、cc_lint、enemy_art）、核心契约 core、22 局冒烟（20 名干员各一局 + 2 局自然流程）、nodes / prot / repro / native_eq / blocks_eq，以及 76 项场景回归：干员积木 / 共享 15、干员个体 17、敌人 10、Boss 8、UI 界面 8、存档 / 局外 / 难度 4、藏品 / 经济 4、升级卡 / 构筑 3、渲染 / 反馈 / 时钟 3、输入触屏 2、音频 2。性能与网页没有快检项。
- 没有被任何测试或快检项直接引用的脚本（按文件名 / 路径搜索）：screens 下 headhunt、hh_style、meta_tree_ui、shop_screen、run_stats_screen、stats_panel、tide_ui、title_tiles、touch_editor、boss_intro、elite_show、card_motion、scene_transition、hud_banners / bars / icons / relics / textq、ak_mock；run 下 victory_flow、weapons、music_director、ishar_encounter；enemies 下 boss_base、boss_patterns、saint、enemy_db、shot_pool；render 下 enemy_atlas、frame_dst、tri_batch、telegraph_draw、declutter、ground_crack；根目录 settings_panel、title_tree、ui_motion。其中玩法相关的（weapons、boss_base、shot_pool、victory_flow）实际经冒烟局间接跑到；**界面类基本只靠人眼**。
- 同 seed TRACE（autotest.gd:657–663）每行：t、lv、击杀 k、队长 hp、敌人数 n、五条玩法随机流状态、队长位置、全体敌人位置 + 血量加权和 h。**不含**队友位置 / 血量 / 技力、灯火、经验、藏品、画面随机流。trace_base.py 逐行比 TRACE、BALANCE 行只提示；blocks_eq 另逐字段比 BALANCE 金样；repro 只比 BALANCE。

## 5. 三端分支点

- 平台判断集中在 settings.gd（Cfg）：触屏判定 114–116、读屏许可 132–133、网页安全区 186–187（读 JS 写好的 `__sySafe`）、触屏放大与网页关滤镜 231–238、网页音量 396、手机缺省画质 498。另有 cloud_save.gd 52–62（JS `__syCloud`）、art.gd 69 / 357 / 381（网页包内贴图、线程预热）、sfx.gd 267 / 370 / 385（网页语音按墙钟）、title.gd 112（网页不显示退出）、game.gd 766（网页敌人贴图按需加载）、native/native.gd 13、run/enemies.gd 142–144。都是「加载 / 平台能力」性质，收敛得不错。
- Toy SDK 全在 JS 壳：tools/web/container.js（按域名 / UA 异步加载 SDK、横屏沉浸、安全区）、cloud.js（云存档）；export_presets.cfg 没有自定义 shell，靠 tools/export_web.py 往 `head_include` 的占位标记注入。排行榜、用户资料、分享还没接。
- 散开的是**触屏布局**：`Cfg.touch_device()` / `phone_ui()` 在 choice_panel 约 16 处、shop_screen 5、title 5、settings_panel 4、result / stats_panel / touch / autotest 各 3–4、其余 7 个文件各 1。
- 原生：native/（core + gdext + build_native.py）→ game/bin；回退在 run/enemies.gd:141–150 `_motion_native`；等价测试 check.py:553–583 `check_native_eq`（同局原生 vs `--optold=131072` 逐行比 TRACE），**没有 dll 的机器直接跳过**。两个导出预设都排除 `bin/*`（export_presets.cfg:10 / 41），正式包恒走 GDScript；game.gd:454 注释「原生库还没接入」已过时。

## 6. 问题清单

### 6.1 阻碍扩展（6）

| # | 问题 | 改法 | 工作量 | TRACE |
|---|---|---|---|---|
| A1 | 升级卡（博士被动 / 填充）全是 doctor.gd 常量 + 3 个 match + progression / bot 各一处，加一张卡改 5–6 处 | `data/cards.json`：id / 名 / 说明模板 / 图标 / 机器人权重 / effect（复用 meta 与藏品已有的 stat / rule 种类）；`apply_passive` 等改成按 effect 解释；先「原样搬家」再谈新卡 | 中 | 不动（保持卡池次序与数值） |
| A2 | 局外界面接入：title.gd 6 处 + title_tiles.gd 2 处，菜单按整数下标；没有界面层级栈，Esc 各界面自管 | 菜单表一处声明（id、标题、图标、行、打开函数、显示条件）；title 维护一个 overlay 栈（push / pop / 顶层收输入），Esc 统一由栈处理；难度选档页从 title.gd 拆出（同 §3.6 的选人页） | 中 | 不动（局外） |
| A3 | Boss 的绘制挂点 / 音效名 / 出场卡 / 跳过缓存散在 world.gd、sfx.gd、boss_intro.gd，加一个 Boss 约 6 处 | Boss 脚本或 enemies.json 声明 `draw_hooks / sfx / intro_card / dc_skip`；world 的 `match e.type` 改查表；`SCRIPTS` 注册改成按目录 + 命名约定自动登记 | 中 | 不动（画面像素 0 差） |
| A4 | 普通敌人的特殊机制按 `e.type == "…"` 写死在 enemies / spawner / world / combat 四处 | 把 brood / slider / reaper / tear / pocket 收成 `extra.mode` 或 `traits[]` 能力字段，代码按能力判断、不按类型名 | 中–大 | 不动（逐只按原次序执行） |
| A5 | 藏品 26 处 `g.relics.has("数字")` + knight / endings 写死编号；新 rule 要加代码读点 | 写死编号改成 relic_effects 的命名 rule（`rfx.rule("…")`），代码只认 rule 名；一次性替换，判断结果不变 | 中 | 不动 |
| A6 | 干员新积木语义要插进 18 段单继承链（链尾写死 data_operator.gd:22），段之间靠继承顺序互相可见 | 维持现状够用（复用积木就能纯数据，p2 14 人只新增 1 个积木名）；以后若 seg 再多，改成「每段独立 RefCounted + 注册表单播」（docs/101 B6 ③ 的方向走完） | 大 | 不动（调用次序照旧） |

### 6.2 风险（7；R8 撤销）

| # | 问题 | 改法 | 工作量 | TRACE |
|---|---|---|---|---|
| R1 | 存档迁移不成链：`DIFF_VER` 用 `dv < 2` / `elif dv == 3`，`_migrate_diff` / `_migrate_tide_to_preset` 没测试，`_migrate_tide` 死代码；[meta] / [roster] 无版本号，`migrate_tickets` 每次加载都跑。玩家存档出错不可逆 | 照 core/cloud_pack.gd 的写法：一个 `SAVE_VER` + `MIGRATIONS` 表逐级迁移；[meta] / [roster] 纳入；加旧存档样本测试（v1–v4 各一份 cfg → 迁移 → 断言） | 中 | 不动（局外） |
| R2 | `enemies.json` / `waves.json` / `balance.json` / 升级卡没有 schema；`balance.json` 拼错键静默取缺省值 | 快检加一项不开 Godot 的 `tools/data_lint.py`：已知键表、waves → enemies / Boss 的 id 交叉引用、`balance.json` 的键与代码里 `Bal.v / BalS.vi("…")` 读点双向对照（json 里有代码不读 = 拼错或死键；代码读了 json 没写 = 走缺省值） | 小 | 不动 |
| R3 | TRACE 不含队友 / 技力 / 灯火 / 藏品：响应动作这类只动队友内部状态的改动，「关着 TRACE 不变」查不出漏网 | TRACE 行加一个队友聚合哈希（位置、hp、技力、普攻计时）+ 灯火 + 藏品数 | 小 | **格式变**（玩法不变；trace_cache 与金样由协调人统一重录） |
| R4 | 寻访界面在 HUD 绘制回调里打开（hud.gd 236 `maybe_open`）：流程状态长在表现层，无头跑时走不到，机器人 / 批跑覆盖不到寻访流程 | 挪到局终流程步（victory_flow / `_process` 局终段）里判定是否打开，HUD 只画 | 小 | 不动 |
| R5 | headhunt.gd 93–151 反射探 roster 新旧接口，注释写「合入时由协调人对接」；接口一改就静默走旧路径 | 两边都已合入 main，删掉适配层、直接调新接口；roster_test 加一条接口存在性断言 | 小 | 不动 |
| R6 | 30 多个界面 / 渲染脚本没有任何测试（寻访、商店、作战记录、HUD 各层、局外树、胜利流程…），只靠人眼 | 一个通用界面冒烟：逐个局外 / 局内界面「打开 → 键盘 / 手柄 / 触屏各导航一步 → Esc 关闭 → 无报错」，并存一张截图给人眼对照；A2 的菜单表做好后可自动遍历 | 中 | 不动 |
| R7 | 原生等价测试在没有 dll 的机器上跳过，导出包又排除 `bin/*`：原生路径实际只在编过 dll 的那台机器上验证过 | 现状可以接受（正式包不走原生）；把「跳过」改成快检报告里的显式提示，并在 build_native 之后强制跑一次 native_eq；修正 game.gd:454 过时注释 | 小 | 不动 |
| ~~R8~~ | ~~渲染层写模拟 / 流程状态：world.gd 69 处 `g.x =`~~ **核对后撤销**：69 处都是纯画面字段（震屏、受伤暗角、血条拖尾、主控挤压、`draw_off`），HUD 与世界层共读，不进模拟、不进 TRACE；放在 g 上是绘制热路径少传参（§8.1） | — | — | — |

### 6.3 整洁（7）

| # | 问题 | 改法 | 工作量 | TRACE |
|---|---|---|---|---|
| C1 | game.gd 顶层字段 332 个；`_ready` 约 370 行夹难度预设与批跑 / 测试参数（`dev_args` 22 次）；局终结算放在 `_process` | 开局参数解析 → `run/run_setup.gd`（与 autotest 的参数表合一）；局终结算（Roster / Meta / 最佳成绩 / 云存档）→ `run/run_end.gd`；字段按「队长 / 局内流程 / 局外」分组成子对象（分批） | 中 | 不动 |
| C2 | title.gd 2787 行：选人页约 1260 行、难度页约 290 行、制作人员约 220 行都在里面（docs/101 §3.6 已建议，未做） | 拆成 `screens/op_pick.gd` / `diff_pick.gd` / `credits.gd`；和 A2 一起做 | 中 | 不动 |
| C3 | character.gd 从 1699 行涨到 2517 行：基类里有 JSON 加载、文本公式求值、契约校验 | 拆出 `operator_loader.gd`（list_ids / 读 json / 公式）和 `operator_validate.gd`（validate_operator 与 V1–V9），基类只留运行时 | 中 | 不动 |
| C4 | autotest.gd `step()` 一个函数约 510 行，另夹性能采样与音效统计 | 按开关拆成 `_step_bot / _step_shots / _step_perf / _step_trace…`；性能与音效统计挪到 telemetry / perf 模块 | 小–中 | 不动 |
| C5 | 公共代码里的个案 id：`ob_core.gd:422 "suzuran"`、`squad.gd:578 "wisadel"`、`initial_stats.gd:13 irene`、vfx.gd:83–84 打击感 id 数组、水月排第一（gallery / title）；职业表 4 处各写一份 | 改成干员 json 字段（`slow_kind`、`voice_alt`、`hit_feel`、`gallery_order`）；职业表收成一个 `class_db` | 小 | 不动（字段值照搬） |
| C6 | 触屏布局分支散在 UI 里约 50 处（choice_panel 16、shop 5、title 5…） | 每个界面一份布局参数（桌面 / 触屏 / 手机三档）在顶部集中取，正文不再判断平台 | 中 | 不动；像素 0 差可截图核对 |
| C7 | 全局 `g` 当服务定位器：UI 取 `g.font`（402）/ `g.hud`（548）/ `g.tex`；新界面不得不依赖整个 game | UI 层改用一个只读的 `UiCtx`（font / tex / 主题 / 输入状态），先在新界面上用，旧界面顺手迁 | 大（分批） | 不动 |

## 7. 建议先做的 5 项

按「收益 / 风险比」排，前三项都能在不动 TRACE 的前提下各自独立完成：

1. **R2 数据 lint**（小）：`tools/data_lint.py` 进快检。最便宜，直接防「改了平衡表没生效」这类隐性错误，也为 A1 / A4 的数据化先立规矩。
2. **R1 存档迁移链 + 旧存档样本测试**（中）：唯一会伤到玩家已有存档的地方，局外成长 / 寻访刚上线、券规则还在改，越早收口越好。
3. **A1 升级卡数据化**（中）：内容扩展里最常改、现在最不方便的一条线；先原样搬家（TRACE 不动），之后新卡只改 json。
4. **A2 + R4 局外界面表 + 层级栈，寻访挪出 HUD 绘制**（中）：局外界面正在快速增加（寻访、认知塑造、作战记录），趁界面还不多把接入点收成一处；顺带让界面冒烟（R6）能自动遍历。
5. **R3 TRACE 加队友聚合**（小，**格式变**）：让「关着 TRACE 不变」真正覆盖干员侧改动；需协调人排在一次统一重录金样的时机，和其他会改 TRACE 格式的事合并做。

不急的：A6（seg 注册表）、C7（UiCtx）工作量大、眼下纯数据加干员已经够用；A3 / A4 等下一个 Boss / 特殊敌人进来时顺手做。

## 8. 性能 / 帧率视角（用户 10-22 追问：「HUD 等等是不是因为帧率优化的问题」）

帧率口径以网页（B站 Toy）为主基准（docs/50 §21）。网页上关掉整个 HUD 能省 12%（7–10 分钟）/ 26%（Boss 段），是 GDScript 侧最大的一层；其次是干员地面 / 上层特效（7% / 12%）、掉落物（6% / 8%）。所以本文的每条改法都要先问「会不会多每帧开销」。

### 8.1 哪些「看起来别扭」的写法是帧率优化留下的，应保留

| 写法 | 来历 | 结论 |
|---|---|---|
| HUD 合批段（`batch_begin / batch_end`、全局 `UI.sink` / `UI.tq`、`h._hb`）、字按字体字号归组（hud_textq）、飘字分层 | docs/50 §13（OPT_HUDB）：HUD 绘制调用 353 → 289，网页 8–10 分钟 −2.0 毫秒 | **保留**。全局「当前批 / 当前字队列」是为了让 77 个 UI 助手不改签名就能进批；改成显式参数要动几百处调用，收益为零 |
| HUD 分层缓存子画布（藏品栏 / 编队静态层 / 小地图每 3 帧）、HUD 图标图集 | docs/50 §9.10、§13：HUD 脚本 2.80 → 1.90 毫秒 | **保留** |
| 编队栏每帧只取一次 `skill_hud()` / `portrait()`、触屏按钮进 TriBatch | docs/50 §21.4 #1 / #2（OPT_HUDSQ / OPT_TOUCHB） | **保留** |
| `g.draw_off` 全局「当前偏移」、world 往 `g.shake / hurt_vignette / hp_trail / p_sq …` 写画面状态 | 绘制热路径上不额外传参；这些都是**纯画面字段**（HUD 与世界层共读），不进模拟、不进 TRACE | **保留**。R8 降级：69 处 `g.x =` 核对后都是画面状态，不是渲染写模拟 |
| 敌人画面字段（`e.dc` 缓存签名等）放在模拟字典上 | docs/101 B3b 有意推迟：按 `e.id` 挪到渲染侧会让敌人绘制每只多一次字典读 | **保留**，等 B5 槽位数组再做 |

**不是**帧率优化的：寻访在 HUD 绘制回调里打开（`hud.gd` 236，76421d6a 局外 P1 接入时的捷径），以及它的反射适配层——后者反而每帧在绘制里 `get_script_constant_map()` / `get_script_method_list()` 分配整张表（结算界面上，量不大，但纯属浪费）。

### 8.2 本文各条改法的每帧代价

| 条目 | 每帧代价 | 说明 |
|---|---|---|
| R1 / R2 / R5、A1、A2、C1–C4 | 0 | 读档、快检、开局、选卡、局外界面、拆文件，都不在战斗每帧路径上 |
| R4 寻访挪出 HUD 绘制 | 略降 | 结算界面每帧少一次反射探测；战斗中只多一次 `state` 比较 |
| R3 TRACE 加队友聚合 | 0（正式游戏） | 只在 `--balance --trace` 下算 |
| A3 Boss 绘制挂点查表 | 0 | 每只 Boss 每帧一次字典查找，替掉一次 `match` |
| A4 敌人特殊机制改能力字段 | **要量** | 敌人逐只更新是热路径：做法必须是出生时把能力算成布尔字段（`e.is_brood` 之类），比现在的字符串比较只快不慢；不许每帧查表 |
| A5 藏品写死编号改 rule 名 | **要量** | `g.relics.has("116")` 有的在每次命中路径上；改成 `rfx.rule()` 前先把 rule 值在藏品变化时缓存成成员，不许每次命中查字典链 |
| C6 触屏布局参数 | 略降 | 现在每帧在绘制里反复调 `Cfg.phone_ui()`（每次取一次视口大小）；集中成每界面每帧一份 |
| C5 个案 id 改 json 字段 | 0 | 字段在编译 / 入队时读出 |
| C7 UiCtx | **可能增** | UI 助手调用量很大（HUD 每帧几百次），多一层间接在网页上不是零成本；只在新界面用，旧 HUD 不迁 |
| A6 seg 注册表 | **要量** | 改分派方式会碰干员每帧路径（docs/50 §21.2 干员特效 7–12%），要同局轮换量过 |

## 9. 执行记录（10-22，分支 `claude/arch-fix-1022`，基于 main aa7028c4）

用户 10-22：「需要考虑到性能和帧率问题，然后去进行修改」。先做每帧代价为 0、同 seed TRACE 不动的几项：

| 条目 | 改了什么 | 验证 |
|---|---|---|
| R4 | 寻访打不打开改由 `headhunt.tick()` 在 `game._process` 里判定（条件照旧：胜利即时、倒下等过渡画完、演练 / 作战记录开着不开）；`hud.gd` 只画 | `--huntshot` 实机走完 入口 → 定向 → 选人 → 拉包 → 揭示 → 汇总 → 回入口；7 张截图与 main 比 6 张 0 差，第 1 张只差待机动画相位（打开时刻从绘制挪到主循环） |
| R5 | 删掉 headhunt 的反射适配层（`_rule / _roster_has / _rcall / _new_rules`），直接读 `Roster.COST_PICK` 等常量、直接调 `redeem_random / spill_to_cells`；旧券折算只由读档时的 `migrate_tickets` 做 | 同上；roster 回归 |
| R2 | 新增 `tools/data_lint.py`，快检不开 Godot 项 `data_lint`：json 重复键、waves 引用的敌人 / Boss / 藏品存在且 Boss 已在 `SCRIPTS` 登记、balance.json 疑似拼错的键（读点不存在而同段有名字相近的未读键） | 现在 33 个 json 0 失败；balance.json 无字面读点的叶子键 203 个只作提示（多为 `Bal.sec` 整段读或动态拼路径） |
| R1 | settings.gd 读档主体抽成 `_read_cfg(c)`；难度版本迁移改成逐版本显式分支 `_migrate_progress`（v1 → `_migrate_diff`、v2 原样、v3 → `_migrate_tide_to_preset`、v4 及以上原样，行为与原来相同）；删掉无调用的 `_migrate_tide` | 新增 `tests/save_migrate_test.gd`（快检 `save_migrate`）：diff_ver 1–5 各样本、旧 2× 倍速、旧缺省亮度、三种旧券 + spare 折算、没有 [roster] 段的新 / 老存档，共 16 条断言 |
| A1 | 升级卡（15 张被动 + 3 张补给）的定义从 doctor.gd 常量原样迁到 `data/cards.json`（键序 = 出卡与机器人遍历顺序，照抄）；`apply_passive` / `apply_filler` 改成按 json 的 stat / op / value（或 `value_bal` + `invert`）通用执行；卡面说明与预览保留原有特别写法，新卡缺省写「属性 现值 → 选中后」。加一张走属性系统的新卡 = 只改 json + 图标 | card_desc、build_progression 回归；同 seed TRACE 水月 seed 1 240 秒、维什戴尔 seed 2 300 秒与 main 逐行相同（机器人在这段里选了成长卡） |
| A2（部分） | 标题菜单的文字 / 英文 / 图标 / 分行收成 `screens/title_tiles.gd` 的 `MENU` 表（`CN / EN / ICON / rows / order()` 都由它派生），title.gd 的 `ITEMS` 指向它；「有界面盖在标题上」的两处判断收成 `_overlays()` 一个列表。新入口 = 表里一行 + `_activate` 一支（+ 盖层界面登记进 `_overlays()`），原来是 title.gd 6 处 + title_tiles.gd 2 处。界面层级栈（Esc 统一处理）没做：各界面已自管 Esc，改栈要动每个界面的输入，留到下一个局外界面进来时 | title_menu 回归（四种菜单组、二维导航、键鼠 / 手柄 / 触屏）；标题页 1280×720 静帧与 main 0 像素差 |

快检：`--auto` 113 项只有「积木等价金样过期」1 项（本分支改了 game.gd / settings.gd，金样按代码哈希判过期；按约定合入后由协调人在 main 统一重录，本分支已用上面的同 seed TRACE 代核）。

### 9.1 HUD 两步（用户 10-22：「有没有可能在保证架构的情况下优化 HUD」→「先做第一步，先不用测」→「继续」；分支 `claude/hud-layer-1022`）

- **第一步（已做，3ac79695）**：左上面板进 HUD 现有的缓存层（`hud._layer`），签名 `top_left_sig` 写全读到的状态、条 / 环长度按 1/8 像素量化、动画进行中带 `g.t`；缓存层按 `LAYER_ORDER` 固定次序建。同局 900 / 1800 / 2700 帧整屏截图新对旧只差小地图声呐（旧对旧同样差）。没做性能测量。
  顶栏、Boss 血条、状态栏、灯火状态条不能这样挪：主画布里在它们前后都有会叠上来的东西（指示箭头、横幅、Boss 登场黑边），子画布整体在主画布之下，挪了会改层次。
- **第二步（试过，不建议做）**：统计一局 HUD 画字用到 57 种「字体变体 × 字号 × 描边」组合，原型把字号收成 6 档（A）/ 5 档（B）、小字描边统一 3：同局同帧绘制调用 桌面 124 / 135 / 208 → 121 / 132 / 205（A）、121 / 132 / 211（B），手机横屏 109 / 124 / 183 → 107 / 122 / 180（A）、106 / 122 / 189（B），**只省约 2–3 次**，画面却会变（字号与描边粗细肉眼可见）。原因：合批段里的字本来就按字号成组（hud_textq），每段只有少数几组；HUD 的调用数主要来自分段（每段一次色块批 + 几组字）与各子画布本身，不是字号种类。原型没入库。
- **下一步要先量**：HUD 在网页上占帧时 12–26%（docs/50 §21.2），但分不清是 GDScript 逐帧逻辑还是引擎画布提交。要在网页测量副本上把 HUD 拆成「脚本时间 / 各段调用」同局轮换量一次，再决定是继续扩缓存层（需要把主画布按块拆成有序的兄弟画布，代价是多几次调用）还是合并分段。
