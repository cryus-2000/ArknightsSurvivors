# 357 第二个肉鸽主题能否模块化：代码调研（11-17）

**状态：调研结论，只读，没有改代码。** 以 main `c1e0c6c65` 为准。用途：决定要不要立项「第二主题」（比如傀影、萨米、萨卡兹），以及先做哪些重构。

**结论：部分能，但要先重构。**「换皮」的部分（地面 / 景物 / 敌人数值 / 刷怪表 / 事件 / 藏品 / 结局条件 / 文案）基本都已经是数据驱动，可是它们都是**全局单份文件**，不能两个主题并存。「玩法」的部分（灯火、溟痕、灯标、黑潮缩圈）散在核心循环、机器人、HUD、配乐里，换主题就得先抽成接口。另外 Toy 包现在是 **49.78 MB**（`build/toy/方舟幸存者_toy_c1e0c6c65.zip`），离 50 MB 只差 0.2 MB，第二主题不可能直接塞进同一个 Toy 包。

主要阻碍（按严重程度）：
1. **主题机制写进了核心系统**：`lamp*` 411 行 / 66 个文件，`mire*` 318 / 36，`beacon` 229 / 33，`zone_*` 214 / 41（见 §2）。
2. **数据是全局单例**：`data.gd`、`enemy_db.gd`、`endings.gd` 写死了 `res://data/waves.json`、`enemies.json` 等路径；代码里有 546 处敌种 id 字面量，分布在 67 个文件里。
3. **包体与存档**：Toy 包已贴线；存档 `user://settings.cfg` 和云存档里的结局、图鉴、难度进度、认知塑造都没有分主题。

---

## 1. 已经数据驱动的部分（换主题 = 换数据）

| 数据 | 内容 | 换主题时要改什么 | 能否多份并存 |
|---|---|---|---|
| `data/maps/<id>.json` + `world/map.gd` | 地砖、地形块、景物、大型景物、环境光、光柱、前景、雪花、**溟痕参数** | 新写一份 json 并配贴图。`Map.list_ids()` 本来就会列出目录 | ✅ **已支持**（`Cfg.map_id`，`settings.gd:105`；`game.gd:1157`）。只有 `mire` 段是主题机制，要挪走 |
| `enemies.json`（30 种） | 生命、伤害、速度、贴图、`script`（Boss 脚本） | 换成新的敌种表 | ❌ 只有一份。另外 546 处字面量（大头在 `render/world.gd` 37、`gallery.gd` 36、`vfx.gd` 35、`boss_bullet_draw.gd` 35）|
| `waves.json` | `threat` 阶段表（含刷怪池 / 大群 / 精英）、`boss_times`、`mid_pool`、`endings`、`cross_deck`、`events` | 整份换掉 | ❌ 只有一份 |
| `events_v2.json`（16 个） | 事件文本、选项、`ops` 效果词表（`light / ingots / maxhp_pct / threat / kills …`） | 新写事件。效果词表可以复用，`light` 是灯火专用 | ❌ 只有一份；`endings.gd:788 _apply_op` 是通用的 |
| `relics.json` + `relic_effects.json`（265 件） | 效果词表（`stat / on_gain / rule`） | 主题藏品另开一组；通用藏品共用 | ⚠️ 词表通用，但 `relic_fx.gd` 有 50 个 `rule("…")` 规则，其中 `deep_sea`、`tree_light` 是主题规则（`affects.gd:39`、`relic_fx.gd:275`、`shop.gd:157`） |
| 结局 `waves.json endings` | 4 个结局及条件 | 新写 | ❌；`endings.gd:64 LINE_ENDS`、`:66 ROUTE_RELICS` 把结局线和藏品 id 写死在代码里 |
| `characters/*.json` + `ob_*` 积木 | 20 名干员 | **不用改，直接复用** | ✅ 和主题无关（干员碰敌人只经 `op_api`） |
| `cards / synergy / balance / meta_tree / medals / guide / lore` | 升级卡、协同、数值、认知塑造、蚀刻章、指南、档案 | 大部分复用。`balance.json` 里的 `lamp / beacon / terrain` 段归主题；`medals.set_name`「深蓝之下」、`lore.json` 敌人档案、`guide.json` 灯火 / 溟痕页归主题 | ⚠️ 要拆出主题段 |
| `l10n/*.csv` | 8 张表；`enemies / events / relics` 三张基本都是主题内容 | 主题包各带一份 | ✅ 按文件拆分即可 |

## 2. 和「水月 / 深海」写死在代码里的部分（grep 统计）

统计口径：`game/scripts/**/*.gd`，含注释。

| 项 | 标识符 | 行 / 文件 | 主要位置 |
|---|---|---|---|
| 灯火 | `lamp*`、`lamp_light` | 411 / 66 | `run/enemies.gd` 34（`:686 lamp_mire_k`、`:698 _lamp_mire`）、`game.gd` 23（`:169 :187 :218 :318 :2717 lamp_r`）、`telemetry` 23、`stats_panel` 20、`hud_bars` 20、`combat` 17、`music_director.gd:34` |
| 溟痕 | `mire*` | 318 / 36 | `world/map.gd` 73、`run/enemies.gd` 42、`spawner` 16、`render/world.gd` 15、`game.gd:328-331` |
| 引航灯标 | `beacon` | 229 / 33 | `run/beacon.gd`（404 行）、`onboard` 38、**`core/bot.gd` 27**、`world_aura_draw` 15、`squad` 14 |
| 黑潮缩圈 | `zone_*` | 214 / 41 | `run/combat.gd:559 update_zone / :587 _zone_schedule / :637 freeze_zone` 共 40 处；`bot` 10、`data_operator` 10（干员技能读圈边） |
| 偏执泡影 | `paranoia` | 180 / 29 | `bosses/paranoia*.gd`，`boss_ai.gd:44 / :198-215` 还有专门的转发 |
| 伊莎玛拉 | `ishar` | 357 / 32 | `bosses/ishar*.gd`、`run/ishar_encounter.gd`（`game.gd:101` 常驻）、`render/world.gd` 31、`telegraph` 16 |
| 博士层 | `doctor` | 97 / 26 | `characters/doctor.gd`（511 行，深蓝之心线）|
| 结局 / 翻节点卡 | `endg.`、`Endings` | 62 / 18 | `endings.gd`（1582 行，34 条 `match` 分支按事件 id 写死）|
| 标题页 | `title_deep / title_tree` | 19 / 9 | `title.gd:44, :52` 直接 preload 深海水母背景与 logo；`title_tree.gd` 画深蓝之树 |
| 敌种字面量 | `"bone"`…`"duck"` | 546 / 67 | 画法、图鉴、Boss 条、测试驱动 |
| 中文主题词出现在代码字符串里 | 灯火 / 溟痕 / 黑潮 / 海嗣 / 深海 / 潮… | 305 行 / 64 文件 | `ak_mock` 26、`data.gd` 23、`bishop` 20、`izumik` 20、`gallery` 17 |
| 难度命名 | `TIDE_SET`、「潮位」 | `data.gd:113`；`meta_bounty`「首通潮位」 | 难度档本身通用，名字归主题 |

配乐（`sfx.gd` + `music_director.gd`）按「灯火低」切层，曲目在 `audio/music/` 下没有分主题。画面观感 `look.gd`、`optical`、噪点地面是**通用渲染管线**，只有参数（环境光、雪花、光柱）来自地图 json，可以复用。

## 3. 地图层现状

**已经有地图概念，只是只有一张**：`world/map.gd`（1042 行）的注释写着「新地图 = 新增一份主题 JSON（+ 贴图）」，按 512 像素分块缓存地面，景物 / 大型景物 / 碰撞 / 前景 / 氛围层都读 json。世界本身是**无限平铺**的，边界靠黑潮缩圈（`combat.gd`）和最终 Boss 冻结场地（`freeze_zone`）。

要支持多张地图 / 多主题，需要改：
- **边界**：把缩圈从 `combat.gd` 挪进主题机制（比如有的主题用固定场地墙，有的用缩圈）。`data_operator`、`bot` 里读 `zone_r` 的 20 处改成调 `theme.arena_clamp() / arena_dir()`。
- **障碍**：`big_props` 已经带碰撞半径，够用。
- **光照**：`ambient / god_rays / snow` 已经由 json 驱动；`lamp_light`（跟随队长的灯火光圈）要变成主题可选项。
- **刷怪表**：`spawner` 读全局的 `waves.json`，改成读主题包里的 `waves.json` 即可（spawner 本身只认 `threat` 结构）。
- **贴图预载**：`art.gd:657` 已经按 `Cfg.map_id` 预载景物；敌人贴图要改成按主题敌种表预载。

## 4. 存档与进度

现状是全部写在 `user://settings.cfg` 一份里（`settings.gd:99-149`），云存档 `core/cloud_pack.gd` 的 `prog` 段包括 `diff / gal / rel / end / shows`，另有 `[meta]`、`[medals]` 段。

| 字段 | 建议 | 理由 |
|---|---|---|
| `roster_unlocked`、`roster_tickets`、干员图鉴 | **共享** | 干员是跨主题的核心收集 |
| `meta_shape`（认知塑造）、`meta_earned`（生机细胞） | **共享**，细胞来源按主题记账 | 局外成长 v3 只有一棵树；分树会让第二主题从零开始 |
| `diff_unlocked`、`diff_best`、`meta_bounty` | **按主题分开**：`{theme: …}` | 难度进度天然属于主题 |
| `endings_cleared`、`event_log`、`seen_relics`、`gallery_seen` 里的敌人 | **按主题分开** | 结局 id、事件 id 会重名 |
| `medals` | 键名加主题前缀；现有的键视为 `deep_sea` | 「深蓝之下」是主题章组 |

**兼容旧存档**：读档时，凡是没有主题层级的旧字段一律映射到 `deep_sea`，再写回新格式（`tests/save_migrate_test.gd` 已经有旧存档样本，照这个模式加用例）。云存档 `VERSION` +1，`MIN_READ` 不动，这样旧客户端仍能读，只是读不到新主题段。

## 5. 发布与包体

- Toy 包 49.78 MB，上限 50 MB。大头是配乐（`audio/music` 54 MB 原始）、特效（`art/fx` 39 MB）、音效 26 MB、语音 21 MB（Toy 版已去掉外语语音）。
- **结论：Toy 只能「一包一个主题」**，第二主题单独发一个 Toy 作品（或者等平台放宽上限）。在 Toy 里按需下载做不到：引擎只认一份 pck，远程下载 pck 也不在 Toy 的允许范围内（docs/99 FAQ 待核）。
- **itch / 桌面**：同一个包带全部主题。Godot 支持 `ProjectSettings.load_resource_pack()`，也可以按主题出 `theme_<id>.pck`，桌面上启动时挂载。
- 导出链路要改的地方：`export_presets.cfg` 的 `include_filter` / `exclude_filter` 加 `themes/<id>/*`；`tools/export_web.py` 加 `--theme=<id>`，排除别的主题目录；`check_release.py` 校验包里只有一个主题清单。

## 6. 改造方案

### 6.1 主题包结构

```
game/themes/
  deep_sea/                     # 现有内容整体搬入（第 0 阶段只搬数据和资源路径，不改行为）
    theme.json                  # 清单：id、标题、地图、机制列表、最终 Boss、配乐、标题页场景、存档键
    map.json  enemies.json  waves.json  events.json  relics.json  endings.json
    lore.json  guide.json  medals.json  balance_theme.json   # balance 的 lamp / beacon / terrain 段
    l10n/  enemies.csv events.csv relics.csv
    scripts/
      mech_lamp.gd  mech_mire.gd  mech_beacon.gd  mech_tide_zone.gd   # ThemeMechanic 子类
      bosses/ paranoia.gd ishar.gd …                                   # 已有 BossBase 子类，原样搬
      ending_rules.gd           # LINE_ENDS / ROUTE_RELICS / 34 条事件特判
      title_bg.gd               # title_deep + title_tree
    art/  audio/music/
  <next>/                       # 第二主题同结构
```

### 6.2 新建 / 复用的接口

| 接口 | 状态 | 职责 |
|---|---|---|
| `ThemeDB`（新，autoload 或挂在 `g` 上） | 新建 | 读 `theme.json`，替换 `data.gd` / `enemy_db.gd` / `endings.gd` / `map.gd` 里写死的路径；给出 `theme_path("waves.json")` |
| `ThemeMechanic`（新基类） | 新建 | 主题机制挂钩：`setup / update(dt) / on_hit / on_kill / arena_clamp / arena_dir / light_radius / hud_bars() / bot_hint() / music_tension() / trace_fields()` |
| `BossBase` | **已有，复用** | `bosses/*.gd` + `enemies.json "script"` 已经是插件式；只需把 `boss_ai.gd:182-230` 的 paranoia / ishar / izumik / knight 转发改成 `boss(type).call(...)` 或挪进各自脚本的钩子 |
| `EndingRules`（新，从 `endings.gd` 拆） | 新建 | 结局线 / 事件特判归主题；翻卡、路口、委托、`_apply_op` 等通用流程留在 `endings.gd` |
| `TitleBackground`（新，很薄） | 新建 | `title.gd:52` 改成按主题实例化背景 |
| `Map` | **已有，复用** | 只去掉 `mire` 段（挪到 `mech_mire`） |

伪代码（核心循环只认接口）：

```gdscript
# game.gd（重构后）
func _start_run():
    theme = ThemeDB.load(Cfg.theme_id)               # 缺省 "deep_sea"
    map = Map.new(self, theme.map_path())
    mechs = theme.make_mechanics(self)               # [MechLamp, MechMire, MechBeacon, MechTideZone]
    boss_ai.register(theme.boss_scripts())

func _process(dt):
    spawner.update(dt); enemies_sys.update(dt); squad.update(dt)
    for m in mechs: m.update(dt)                     # 原来散在 game / enemies / combat 里的灯火、溟痕、缩圈
    ...
func arena_clamp(p): return mechs_first("arena_clamp", p, p)   # 没有边界机制的主题 = 不夹
```

调用顺序必须和现在**逐帧一致**，并且机制内的随机流照旧用 `g.rng_*`，这样 deep_sea 的同种子 TRACE 才能不变。

### 6.3 分阶段工作量（会话日 = 一个 Claude 会话一天的量）

| 阶段 | 内容 | 估计 | 验收 |
|---|---|---|---|
| **0 搬家**（不改行为） | `ThemeDB` + 路径重定向；数据 / 资源搬到 `themes/deep_sea/`；存档加主题层级 + 迁移测试 | 3–4 | 同种子 TRACE 逐行相同；金样不变；`save_migrate_test` 通过 |
| **1 机制接口化** | 灯火 / 溟痕 / 灯标 / 缩圈改成 `ThemeMechanic`；`bot / hud_bars / stats_panel / telemetry / music_director / onboard` 读接口；`boss_ai` 转发清掉；`EndingRules` 拆分；546 处敌种字面量里画法和图鉴相关的改读数据（测试驱动的可以保留） | 8–12 | 同上，外加帧时对照（`--fixed-fps 60` 同局轮换） |
| **2 外围** | 选主题界面（标题页或选人前）、标题背景 / 配乐按主题、导出 `--theme`、Toy 单主题包、`check_release` | 3–4 | 两个包都能启动；Toy 包 ≤ 50 MB |
| **3 第二主题最小样例** | 1 张地图、3 种敌人、1 个 Boss、5 个事件、1 个结局、1 个主题机制（可以先「无机制」）；文案按 docs/76 §4 先查 PRTS | 6–8（代码）＋ 美术并行（Codex：地砖 / 景物 / 3 敌人 / Boss） | 能完整打通一局；deep_sea 不受影响 |
| **4 正式内容** | 对标现有体量：约 25 敌 + 4 最终 Boss + 15 事件 + 4 结局 + 主题藏品 + 配乐 | 30–50＋，以美术和 Boss 为主 | 平衡批跑走云端 |

**先做 0 + 1，合计约 11–16 会话日**，没有新内容也有收益：`game.gd` / `combat.gd` / `enemies.gd` 会变轻，也能顺便做 docs/339 轮回模式需要的「Boss 轮换、刷怪重组」。

### 6.4 风险

- **同种子回归**：阶段 0 / 1 必须逐行相同。机制挪位置最容易改变 `g.rng` 的调用顺序，所以每挪一个机制就跑一次 `trace_base.py`，而且要覆盖 4 条结局线（`--route=knight|heart|memory|none`）。
- **金样**：`blocks_eq` 等金样只要行为不变就不受影响；角色分支不重录，合入后由协调人在 main 统一重录。
- **性能**：机制改成虚调用后每帧多 4–6 次 GDScript 调用，可以忽略；但不要在敌人内层循环里逐个调接口（`enemies.gd` 的 `_lamp_mire` 要整段搬，不要拆成逐敌回调）。电脑网页本来就卡在 GDScript（docs/355）。
- **包体**：Toy 一包一主题；第二主题的配乐要按现有规格（Suno 分层 + 降采样）准备，否则单独一包也会超限。
- **机器人**：`core/bot.gd` 的路线判断深度依赖灯标和缩圈（37 处），批跑能不能用全靠它，必须和阶段 1 一起改。

## 7. 模块依赖图

```mermaid
flowchart LR
  classDef reuse fill:#d8f0d8,stroke:#3a7a3a,color:#000
  classDef abstr fill:#fff1c8,stroke:#a07800,color:#000
  classDef theme fill:#f8d6d6,stroke:#a03030,color:#000

  subgraph 可复用
    OPS[干员 characters/*.json + ob_* 积木 + op_api]:::reuse
    SQUAD[squad / character / data_operator]:::reuse
    COMBAT_CORE[combat.damage / weapons / shot_pool / telegraph]:::reuse
    PROG[progression / 升级卡 / 协同 / 终结技 / 连携]:::reuse
    META[认知塑造 meta / 寻访 roster / 云存档框架]:::reuse
    UI[HUD 框架 / 选卡 / 商店 / 结算 / 图鉴框架 / 设置]:::reuse
    REND[world 绘制 / look / optical / vfx / 敌人缓存]:::reuse
    SHIP[export / ship / deploy 链路]:::reuse
    BOSSBASE[BossBase 基类 + enemies.json script 字段]:::reuse
    MAPCLS[world/map.gd 地图类]:::reuse
  end

  subgraph 需抽象
    THEMEDB[ThemeDB：data.gd / enemy_db / 路径重定向]:::abstr
    MECH[ThemeMechanic 接口]:::abstr
    SPAWN[spawner 读主题 waves]:::abstr
    END_CORE[endings.gd 通用翻卡 / 路口 / _apply_op]:::abstr
    BOSSAI[boss_ai 转发清理]:::abstr
    SAVE[存档主题层级 + 迁移]:::abstr
    BOT[bot 路线判断]:::abstr
    MUSIC[music_director 张力来源]:::abstr
    TITLE[title.gd 背景挂点]:::abstr
    RELICRULE[relic_fx 主题规则]:::abstr
  end

  subgraph 主题专属：deep_sea
    LAMP[灯火 lamp]:::theme
    MIRE[溟痕 mire]:::theme
    BEACON[引航灯标 beacon]:::theme
    TIDE[黑潮缩圈 zone]:::theme
    BOSSES[偏执泡影 / 伊莎玛拉 / 斥亡体 / 骑士 …]:::theme
    DOCTOR[博士层 / 深蓝之心]:::theme
    DATA[maps / enemies / waves / events / relics / endings / lore / l10n]:::theme
    TBG[深海水母标题 / 深蓝之树 / 配乐]:::theme
  end

  THEMEDB --> DATA
  MECH --> LAMP & MIRE & BEACON & TIDE
  SPAWN --> THEMEDB
  END_CORE --> DOCTOR
  END_CORE --> THEMEDB
  BOSSAI --> BOSSBASE --> BOSSES
  MAPCLS --> DATA
  TITLE --> TBG
  MUSIC --> MECH
  BOT --> MECH
  SQUAD --> MECH
  COMBAT_CORE --> MECH
  UI --> MECH
  META --> SAVE
  OPS --> SQUAD
```

（绿 = 直接复用；黄 = 要抽接口或改成读主题；红 = 搬进 `themes/deep_sea/`，第二主题各写一套。）

## 8. 待定

1. 立不立项；立项的话，阶段 0 + 1 是否先于 docs/339 轮回模式做（建议先做，两边共用 Boss 轮换和刷怪重组的改造）。
2. 第二主题选哪个：选定后先按 docs/76 §4 在 PRTS 查原作的敌人、Boss、结局。
3. 认知塑造是否跨主题共享（本文建议共享）。
4. Toy 上是另开一个作品，还是同一作品轮换主题。
