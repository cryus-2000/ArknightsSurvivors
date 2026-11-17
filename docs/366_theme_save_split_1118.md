# 366 主题包重构 · 第三步：存档按主题分开（11-18）

**状态：已实装，待协调人合入。** 分支 `claude/theme-save`，以 main `32d862186` 为底，提交 `62c956c18`。上游：docs/357 §4（存档与进度）、docs/364（机制接口）、docs/89（B站 Toy 云存档）。

**一句话**：结局、图鉴、藏品、事件图鉴、难度解锁与最佳、首通赏金、蚀刻章按主题 id 存；干员、寻访凭证、认知塑造、设置、键位、引导保持全局。旧存档自动归水月，幂等；云存档旧版 / 新版互相读写不崩。

## 1. 字段清单

### 1.1 归主题（`core/theme_save.gd` `FIELDS`）

| 字段（Cfg） | 本地旧位置 | 云存档旧键 | 合并 | 为什么归主题 |
|---|---|---|---|---|
| `endings_cleared` | `[progress] endings_cleared` | `prog.end` | 并集 | 结局 id 是主题内容（傀影的四个结局和水月的不同）；「通关结局一后开其余结局线」也是主题内的流程 |
| `gallery_seen` | `[progress] gallery_seen` | `prog.gal` | 并集 | 内容全是 `enemy:<敌种>` 与 `item:<掉落 / 景物 / 商人>`（`run/gallery_progress.gd`），敌种和景物都随主题换 |
| `seen_relics` | `[progress] seen_relics` | `prog.rel` | 并集 | 藏品图鉴按主题收集；通用藏品在两个主题里各收一次（docs/363 §7 保留通用藏品，图鉴按主题分页更自然） |
| `event_log` | `[progress] event_log` | 不上云（同旧版） | 次数取大、见过取或 | 事件是主题内容，事件 id 会重名 |
| `diff_unlocked` | `[progress] diff_unlocked` | `prog.diff` | 取大 | 难度进度天然属于主题（docs/357 §4） |
| `diff_best` | `[progress] diff_best` | `prog.dbest` | 通关次数 / 最长取大、最快取小 | 同上，各档最佳成绩 |
| `meta_bounty` | `[meta] bounty` | `prog.meta.bounty` | 并集 | 「首通潮位赏金」按主题首通各领一次（docs/357 §4 定的） |
| `medals` | `[medals] got` | `prog.med.got` | 并集，时刻取早 | 蚀刻章组「深蓝之下」是水月的章表（`medals.json` 已经经 ThemePack 按主题取）；第二主题有自己的章组 |
| `medal_best` | `[medals] best` | `prog.med.best` | 取大 | 跟着蚀刻章 |

### 1.2 保持全局

| 字段 | 为什么全局 |
|---|---|
| `roster_unlocked`、`roster_tickets`、`roster_spare`、`roster_wish / pity / draws / seed`、`roster_fresh`、`roster_v`、`roster_int_grant` | 干员是跨主题的核心收集（docs/357 §4），寻访凭证是同一份经济 |
| `roster_tiers`（已首通的难度档，发人事调度函） | **暂定全局**：协调人定寻访凭证全局，首通发凭证跟着凭证走。代价：第二主题首通同一档不再发调度函。要改成按主题只需把它加进 `FIELDS`（见 §5 待定） |
| `meta_shape / shape_t / earned / bought / dev` | 认知塑造只有一棵树（docs/109 v3），生机细胞按设备记账；跨主题共享（docs/357 §4、§8 第 3 条建议） |
| `seen_shows` | 干员精英化 / 解锁演出，和主题无关 |
| `seen_intro`、`seen_tips`、`title_tour`、`onboard*`、`opening_seen` | 新手引导与开场只走一次；第二主题的主题机制引导（灯火 / 溟痕页）以后按卡 id 区分即可 |
| `difficulty`（上次选的难度档） | 界面偏好；读档时按当前主题的 `diff_unlocked` 夹取 |
| 设置（音量、画质、语言、界面大小、镜头……）、`touch_layout`、键位 | 设备 / 玩家偏好 |
| `toy_support` | B站 Toy「支持作者」领奖记录，按账号一次 |
| `cover_character_id` | 标题封面干员 |
| `[cloud]` 段 | 云存档同步状态 |

## 2. 存储格式

### 2.1 本地 `settings.cfg`

- 每个主题一段 `[theme_<id>]`，键 = 上表字段名（`[theme_deep_sea] endings_cleared = [...]` ……）。
- **旧位置继续写水月那一份**（`[progress]` / `[meta] bounty` / `[medals]`）：旧版本读到的就是水月的进度，降级不丢。
- 内存：Cfg 的这几个字段始终是**当前主题**（`Cfg.theme_cur`）那一份，读它们的几十处代码（图鉴、结算、蚀刻章、难度页、首通赏金……）一律不用改；别的主题在 `Cfg.theme_saves {id: {字段: 值}}`。`Cfg.theme_switch(id)` 换主题（当前这份收进 theme_saves，目标那份放出来，没有就从空开始）。当前主题由 `ThemePack.id()` 定，阶段 0–3 恒为 `deep_sea`。

### 2.2 读档（`settings._theme_load`，`_read_cfg` 最后一步）

1. 旧位置照旧读进 Cfg 字段（原有的难度 diff_ver 迁移、名册迁移等都先做完）。
2. 这份 = 水月；和 `[theme_deep_sea]` 段（如果有）按字段合并（§1.1 的「合并」列，规则与云存档相同）。
3. 其他 `[theme_*]` 段进 `theme_saves`；当前主题不是水月时切过去。

效果：
- **旧存档**（没有主题段）：旧位置原样成为水月进度——这就是迁移，玩家看到的完全不变。
- **新存档**：两处相同，合并结果不变——**幂等**，读多少次都一样。
- **降级再升级**：旧版本只会改旧位置；回到新版本时并集 / 取大把旧版新增的进度并进来，不丢。（反过来，新版本在主题段里的进度旧版本看不到——旧版本没有主题概念，只看水月，这正好就是旧位置里的东西。）

### 2.3 写档（`settings._theme_write`，`save()` 里蚀刻章补判之后）

当前主题 + `theme_saves` 里每个主题各写一段；当前主题不是水月时，旧位置改写成 `theme_saves.deep_sea`（旧位置永远是水月）。

### 2.4 云存档（docs/89）

- `prog` 原有的 `diff / gal / rel / end / dbest / med / meta.bounty` **继续是水月那一份**。
- 其他主题进新字段 `prog.th = {主题 id: {"diff", "gal", "rel", "end", "dbest", "bounty", "med"}}`（`ThemeSave.to_cloud / from_cloud`）。**只有水月时不写 th，正文与旧版本逐字相同。**
- 版本：`CloudPack.VERSION` 1 → **2**，`MIN_READ` 仍是 1（只加字段）。
  - **新版读旧档**（v1，没有 th）：照常；th 当空。
  - **旧版读新档**（v2、minv 1）：`unpack` 判 ok（minv ≤ 1）；th 是旧版不认识的 prog 字段，进 `cloud_extra.prog`，合并时以云端为准、回写时原样带上——不崩、不丢（docs/89 §3.1 的透传规则）。
- 合并（`CloudPack.merge` → `ThemeSave.merge_cloud_th`）：th 里每个主题各自难度取大、列表并集、最佳成绩 / 蚀刻章同旧键规则；本版不认识的主题、主题里不认识的子键原样保留（云端为准）。
- 套用（`cloud_apply`）：先切到水月套旧键，再把 th 里每个主题写进 `theme_saves`（事件图鉴不上云，保留本地），最后切回原来的主题。

## 3. 验证

新测试 `game/tests/theme_save_test.gd`（`check.py --only theme_save`，已登记 check_map）：

| 项 | 内容 |
|---|---|
| 典型旧存档 × 4 | 新玩家 / 通关结局一 / 四结局全通（含蚀刻章、事件图鉴、认知塑造）/ 深潮进度（难度 2、首通赏金三档、两台设备的生机细胞）：读档后 9 个主题字段与旧位置原样相同；名册、凭证、已首通档、认知塑造、生机细胞、余额、已看演出、难度选择也一并比 |
| 幂等 | 迁移后写出（旧位置 + 主题段）再读、再写再读，玩家可见状态三次一致；旧位置的值始终不变（旧版本读得到）；主题段 = 当前进度 |
| 降级再升级 | 旧版本只改旧位置（多一个结局、一件藏品、难度升一档）→ 新版本读到并集 |
| 第二个主题 | 切过去从空开始、全局（名册 / 认知塑造）不变；记进度写出再读，两个主题各是各的，旧位置仍是水月；来回切进度不变 |
| 云存档 | 只有水月时正文没有 th；有第二主题时 th 带上、旧键仍是水月；头 v2 / minv 1；旧版（reader 1）解包 ok；冲突（两台设备水月与傀影各有不同进度、云端还有一个本版不认识的主题）合并后各自并集 / 取大，未知主题保留；套用后两个主题都对；当前在第二主题时 cloud_body / cloud_apply 也对 |

相关快检（本机）：cloud_save（`cloud_save_test` 的「读旧版本走迁移」用例改成手动把头写回 v1——`pack` 写的头版本不低于本版）、save_migrate、meta、medals、settlement、toy_support、theme_save、core、ui_smoke 全部通过。

`theme_parity`：见 §4。

## 4. parity

| 平台 | 结果 |
|---|---|
| Windows 本机（7 局，基线 3c28305c 缓存） | **7 / 7 一致**，PARITY 4105 行 × 36 字段 |
| Linux GCP（7 局 × 两遍，`cloud-results/pm-62c956c18`） | 其余 6 局两遍都一致；`deep_p0` 两遍都落在已知变体 C（docs/364 §4：伊莎玛拉战 t=638.6 秒，rng 全同、只有敌人血量不同） |
| Linux `deep_p0` 加跑 | 单独 4 遍（`pmdeep-62c956c18`）也都是变体 C；于是**同时、同机型**再跑改前 main `32d862186` 与本提交各 4 遍（`pmdeepB-*`）：改前 1 / 4、本提交 2 / 4 与基线逐帧一致，其余都是变体 C——分布相同，是环境里的偶发走向，不是本提交引入的 |

存档改动碰不到局内：测试局走 `godot_runner` 的临时用户目录（固定的一份 settings.cfg），读档迁移后 Cfg 字段与改前相同，批跑不写存档。

## 5. 待定 / 没做的

1. `roster_tiers`（首通发人事调度函）归全局还是主题，见 §1.2。
2. **全部解锁（调试 / 对内包）时不要切主题**：`_real_progress` 只存了当前主题的真实值（难度 / 藏品 / 结局），`theme_switch` 后它还是原主题的，存档会把原主题的真实进度写进新主题段。现在没有切主题的入口，不会触发；第二主题上线前 `theme_switch` 要连 `_real_progress` 一起换，并按新主题重算全开的演示数据。
3. 主题选择界面、`ThemePack.id()` 读设置（阶段 2）；目前没有入口能切主题，theme_switch 只有测试在用。
4. 对局记录 `runs.jsonl`（对内包）没有主题字段；遥测 `map` 字段已有地图 id。
5. 「深潮进度」：难度阶梯本身（`D.DIFF_PRESETS`、潮位）仍是全局常量，名字归主题（docs/357 §2 末行），留给内容阶段。
