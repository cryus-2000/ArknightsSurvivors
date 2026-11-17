# 364 主题包重构 · 第二步：主题机制接口 ThemeMechanic（11-17）

**状态：已实装，待协调人合入。** 分支 `claude/theme-mech`，以 main `3c28305c3` 为底，按机制拆成四个提交，每个都过 `theme_parity`：

| 提交 | 内容 |
|---|---|
| `a5920f918` | 接口 `scripts/core/theme_mechanic.gd` + `ThemePack.make_mechanics` + 清单 `mechanics` 段；**灯火** → `mech_lamp` |
| `f19956a6f` | **溟痕** → `mech_mire` |
| `f6be8317e` | **引航灯标** → `mech_beacon`（原 `run/beacon.gd` 整文件搬家） |
| `eddc0593f` | **黑潮缩圈** → `mech_tide_zone` |
| `9baabf2b3`、`82e528b20` | 云端 `setup_linux.sh` 与 GCP 预制镜像路径（`tools/gcp/vm_startup.sh`）导入前重建 `art/index.json`（§5，和机制无关） |

上游：docs/357 §6.2（接口设想）、docs/359 §4（交接）。玩法、数值、画面零变化。

## 1. 接口

- **基类** `game/scripts/core/theme_mechanic.gd`：只有 `var id` 和五个空挂钩。子类自己声明 `var g: Game` 与 `_init(game)`（基类不声明 g：子类重复声明成员会报错，而无类型的 g 会让子类里大量 `:=` 推断失败）。
- **清单**（`themes/deep_sea/theme.json`）：

```json
"mechanics": [
  {"id": "lamp",      "script": "res://themes/deep_sea/mech/mech_lamp.gd"},
  {"id": "mire",      "script": "res://themes/deep_sea/mech/mech_mire.gd"},
  {"id": "beacon",    "script": "res://themes/deep_sea/mech/mech_beacon.gd"},
  {"id": "tide_zone", "script": "res://themes/deep_sea/mech/mech_tide_zone.gd"}
]
```
  顺序就是同一挂钩点里的调用顺序。
- **实例化**：`game.gd` 成员初始化里 `mech_by_id = ThemePack.make_mechanics(self)`（放在原来 `beacon_sys = Beacon.new(self)` 的位置，构造时机不变），`mechs = mech_by_id.values()`，`game.mech(id)` 取实例（本主题没有时为 null），`beacon_sys` 指向灯标机制实例。
- **挂钩点**（都放在改造前写死调用的同一行）：

| 挂钩 | 位置 | 谁实现 |
|---|---|---|
| `on_player_tick(dt)` | `game._update_player`，队长回复之后、护盾之前 | 灯火（熄灭掉血）→ 缩圈（`update_zone`） |
| `on_player_hit(dmg, src)` | `combat.enemy_hit`，控制 / 凋亡之后、侵蚀之前 | 灯火（受击熄灭） |
| `on_status_tick(dt) -> bool` | `enemies.update_status`，侵蚀之后 | 溟痕（减速 / 掉血 / 神经损伤，返回 true）；**没有机制认领时核心照常结算巢涌光环与神经损伤**（不在溟痕里） |
| `on_spawn_tick()` | `spawner._horde_tail_rest`，补给箱之后、商人之前 | 溟痕（自然溟痕刷新） |
| `on_world_tick(dt)` | `game` 杂项段，结局箱之后、骑士之前 | 灯标 |

- **核心留的转发**（调用方太多，先不动它们）：`combat.add_enemy_mire / fade_mire` → `mech("mire")`；`combat.freeze_zone / zone_dir` → `mech("tide_zone")`；`game.lamp_r() / _lamp_sp()` → `mech("lamp").light_radius() / sp_mult()`（没有灯火机制时按满灯）。`combat.arena_clamp / mire_blocked` 只看 `g.zone_frozen / zone_next_*` 场地状态，算通用「场地」接口，留在 combat。
- **状态还在 g 上**：`g.lamp / lamp_cap`、`g.mires / in_mire / next_mire`、`g.beacons`、`g.zone_* `。这一步只收「谁来结算」，读写它们的地方（§3）没改。

## 2. 各机制收进了什么

| 机制 | 文件 | 从哪里搬来（函数体原样） |
|---|---|---|
| 灯火 | `mech_lamp.gd` | game：熄灭每秒 3 点掉血、`lamp_r`、`_lamp_sp` 的灯火部分；combat.enemy_hit：受击掉灯火 + 遥测 + 飘字 |
| 溟痕 | `mech_mire.gd` | enemies.update_status 溟痕段（含 `mire_tick`）、`lamp_mire_k`、`_lamp_mire`、`_lamp_hint`（含 `lamp_band / lamp_hint_t`）；spawner 自然溟痕刷新段；combat `add_enemy_mire`、`fade_mire` |
| 灯标 | `mech_beacon.gd` | `run/beacon.gd` 整个文件（git mv，uid 不变），加 `on_world_tick` |
| 缩圈 | `mech_tide_zone.gd` | combat：`update_zone`、`_zone_schedule`、`freeze_zone`、`_arena_step`、`zone_dir`、缩圈 / 场地计时状态与 `ZONE_START / GRACE / RADII` |

跟着改的读取点：`hud_banners.draw_zone_hint`（`zone_out_t` / `ZONE_GRACE`）、`telemetry`（`zone_phase`）、`tests/prot_test.gd`（`mire_tick`、`update_zone`）。

## 3. 剩余写死处（grep，`game/scripts/**/*.gd`，含注释；口径同 docs/357 §2）

| 机制 | 标识符 | main 3c28305c3 | 现在 | 大头 |
|---|---|---|---|---|
| 灯火 | `\blamp` | 444 行 / 66 文件 | **397 / 66** | telemetry 25、game 23（`lamp_light` 光源、HUD 光圈）、hud_bars 21、stats_panel 20、izumik 20、relic_fx 17、vfx 16；三十多处干员 / 藏品 / 事件直接加减 `g.lamp` |
| 溟痕 | `\bmire` | 238 / 31 | **165 / 28** | world/map.gd 37（地图 json 的 mire 段、`mire_new`）、shot_pool 12、telemetry 10、combat 8（转发 + `mire_blocked`）、boss_bench 7、vfx / world 画面 |
| 灯标 | `beacon` | 230 / 33 | **186 / 31** | onboard 38、**bot 27**、world_aura_draw / world 各 15、squad 14（移动指令吸附）、vfx 13；enemy_ai / shot_pool 直接调 `g.beacon_sys.*`（没有灯标的主题会空引用） |
| 缩圈 | `\bzone_` | 323 / 41 | **255 / 40** | post_fx 35、data_operator 15（干员技能读圈边）、fx_pxplane_sk 12、**bot 11**、world_zone_draw 10、hud_banners 9 |

主题机制目录里现在有 lamp 62 / mire 90 / beacon 47 / zone_ 83 行（含注释）。

**下一步建议**（按收益排）：
1. **机器人**（`core/bot.gd` 灯标 27 + 缩圈 11）：加挂钩 `bot_goal(p) / bot_avoid(p)`，灯标寻路和回圈逻辑搬进各自机制；批跑能不能用第二主题全靠它。
2. **没有该机制的主题能跑**：`enemy_ai`、`shot_pool`、`squad`、`seg_hoshiguma` 里的 `g.beacon_sys.*` 改成 `g.mech("beacon")` 判空；`freeze_zone` 的「最终 Boss 场地」拆成通用场地（缩圈机制只负责日程），否则没有缩圈的主题打最终 Boss 没有场地。
3. **HUD / 配乐 / 遥测**：加查询 `hud_bars()`、`music_cutoff()`（`music_director.gd:34` 灯火低时低通）、`trace_fields()`；`stats_panel`、`hud_bars`、`telemetry` 改读接口。
4. **画面**：world / vfx / post_fx 的溟痕、灯标、黑潮画法挪进机制的 `draw_*`（无头批跑不画世界层，parity 照不到，要配截图对照，memory「画面对照用干净局」）。
5. **数值段**：`balance.json` 的 `lamp / beacon / terrain` 段归主题包。

## 4. 验收

基线：main `3c28305c3` 的游戏代码与 `5a30ebf00` 相同，直接沿用 docs/359 已录的基线（Windows `build/parity_cache/e46cfed1`，Linux `cloud-results/parity-b2-5a30ebf0`）。

| 提交 | Windows 本机（7 局，vs 基线） | Linux GCP（7 局 × 两遍，vs 基线两遍） |
|---|---|---|
| `a5920f918` 灯火 | **7 / 7 一致**，PARITY 4105 行 × 36 字段 | rep1 / rep2 的另外 6 局一致，`deep_p0` 两遍都落在已知变体 C（见下）；`deep_p0` 补跑 4 遍（`cloud-results/pmdeep-a5920f918`）：**2 遍与基线逐帧一致**、2 遍变体 C |
| `f19956a6f` 溟痕 | **7 / 7 一致** | rep1 **7 / 7 一致**；rep2 只有 `deep_p0` 落在变体 C |
| `f6be8317e` 灯标 | **7 / 7 一致** | rep1、rep2 都 **7 / 7 一致** |
| `eddc0593f` 缩圈（四个机制全收完） | **7 / 7 一致** | rep1 **7 / 7 一致**；rep2 只有 `deep_p0` 落在变体 C |

**Linux `deep_p0` 的已知不确定性（docs/359 §5 第 1 条）**：现在至少见到 3 种结局走向，都在伊莎玛拉战里，分歧那一行五条 rng 全同、只有敌人血量哈希 `eh` 不同：
- 变体 A（基线 B rep1/rep2、A rep2）：710 行、deep 胜 701 秒；
- 变体 B（e46cfed1b A rep1）：t=646.5 秒分歧；
- 变体 C：t=638.6 秒分歧，704 行、deep 胜 695 秒——出现在灯火提交两遍、溟痕 rep2、缩圈 rep2。
四个提交都至少有一遍 `deep_p0` 和基线逐帧相同（灯火在补跑里 2 / 4），变体 C 是同一提交内部的随机走向，不是改动引入的；其余 6 局（含 Windows 的 deep 局 `deep_p0w`）每个提交都逐帧一致。结果分支：`cloud-results/pm-<提交>`。

## 4.1 全量快检

GCP `check.py --nocache` 真全量（`a04a96bbc`，`cloud-results/ci-mech-a04a96bb`）：217 项、214 通过；失败的 3 项是积木等价「金样过期」14 组（分支必然过期，合入后在 main 重录）和 asset_index / graph_lint（§5，已在 `82e528b20` 修好，单独验证通过）。

## 5. `game/art/index.json` 缺 66 个名字（协调人顺带问）

- **原因确认**：仓库里提交的 `game/art/index.json` 落后于磁盘。重建只**增加** 66 个名字（22 张干员 `*_chibi`、`bad_guy_transport`、`op_lappland_move_throw@1x`、`op_wisadel_move_s2_attack@1x` / `_over_attack@1x`、星熊 `pxp_hsg_sweep_*_stance_up_*` 30 张、维什戴尔 `pxp_wd_dawn2_*` 12 张），没有删除、没有改路径。
- **为什么不直接提交新索引**：11-09 `c4b86fbdf`「撤回误提交的 game/art/index.json（本地生成文件，不进提交）」定的口径是不提交；本机每次录像 / 快检前都先 `asset_index.py` 重建，所以本机不红，只有云端新检出（用的是仓库里那份旧的）会红。
- **修法（`9baabf2b3` + `82e528b20`，安全）**：`tools/cloud/setup_linux.sh` 和 GCP 预制镜像路径（`vm_startup.sh`，镜像不走 setup_linux）在导入前跑一次 `python3 tools/asset_index.py`，云端和本机口径一致。仓库里的 index.json 没动。验证：GCP `cloud-results/ci-idx-82e528b2` 上 asset_index、graph_lint 都通过。
- **待协调人定**：既然「不进提交」，更干净的做法是 `git rm --cached game/art/index.json` + 加进 `.gitignore`，导出 / ship 链路确认都会先重建（`check_release` / `export_web` 是否依赖仓库版本要先查）。这一步改了跟踪状态，没替你做。

---

## 6. 第二步收尾（11-18，分支 `claude/theme-mech2`，以 main `1c4f2e695` 为底）

| 提交 | 内容 |
|---|---|
| `953866d48` | `game/art/index.json` 停止跟踪（§8） |
| `857a70d97` | 机器人的灯标 / 缩圈逻辑改走机制挂钩；`g.beacon_sys` 直接调用判空 |
| `1c46e1811` | 最终 Boss 场地从缩圈里拆成通用 `run/arena.gd`（§7） |

### 6.1 机器人挂钩（`theme_mechanic.gd`，缺省都是「没意见」）

| 挂钩 | 调用处 | 水月实现 |
|---|---|---|
| `bot_return_dir(p, margin)` | 手残 `_move_bad` | 缩圈：离圈边 < margin 往圈心 |
| `bot_score(q, s) -> float` | 高手 `_score_point`（传入当前分、返回新分，加减顺序原样） | 缩圈：圈边 120 内按超出扣分、圈外 −30 |
| `bot_goal(bot, p)` | 高手 `_expert_goal`（INF = 没意见；可写 `bot.beacon_hold / beacon_w`） | 灯标：找最近未点燃灯标、近了在光圈站着 |
| `bot_outside_dir(p)` / `bot_land_bad(land, p)` | master 冲刺 `_master_dash_dir` | 缩圈：出圈冲回、落点不往更外 |
| `bot_pull(pull)` / `bot_steer(at, mv)` | 普通机器人 `autotest.bot_move`（计时状态 `zone_out_since` / `want_dash` 仍在 autotest） | 灯标拉力；缩圈回圈与出圈冲刺 |

`g.beacon_sys` 直接调用全部判空（`enemy_ai` 2 处、`shot_pool` 2、`enemies` 1、`run_stats` 1、`spawner` 1、`onboard` 1、`map` 1、`mech_mire` 2），没有灯标机制的主题（`beacon_sys == null`）不会空引用。

**机器人还剩的写死**：`bot.gd` 里 `beacon_hold / beacon_w`（通用的「站桩点」加权，名字沿用）和 `_bdbg` 灯标诊断日志、human 档 `zone_edge` 一行（`bot.gd:931`，等价于 `bot_return_dir(p, 90) != ZERO`，下次顺手换）。

### 6.2 验证

- `theme_parity`（只有高手机器人）：见 §9。
- **其余机器人档**另跑同种子对照（seed 5 维什戴尔 500 秒，`1c4f2e695` vs `857a70d97`，Windows）：normal 214 行 PARITY + 212 行 TRACE、bad 81 + 81、master 506 + 501、human 246 + 243，**四档全部逐行相同**。

## 7. 最终 Boss 场地拆出来（`run/arena.gd`）

- `freeze(r)`（原 `freeze_zone`）、`step(dt)`（原 `_arena_step`，冻结后 3 秒插值）、`blocked(pos, r)`（原 `mire_blocked`）、`clamp_point(p, margin)`（原 `arena_clamp`）原样搬来；`g.arena` 挂在 game 上，`combat.freeze_zone / mire_blocked / arena_clamp` 改转发，调用方不变。
- 冻结末尾调各机制 `on_arena_freeze(fresh)`：缩圈重置阶段（`zone_phase = -1`，原在冻结开头，中间没人读，等价）、溟痕清掉场地里的（原在冻结末尾）。
- 插值从缩圈 `update_zone` 开头挪到 `_update_player` 里机制挂钩之前（`arena.step`），中间只有灯火挂钩、它不读圈，顺序等价。
- **效果**：没有缩圈机制的主题也有最终 Boss 场地（约束 Boss / 召唤落点、禁生成）。圈外伤害仍归主题机制（水月：黑潮）；没有缩圈的主题场地边上没有伤害，要不要另做「场地墙」是下一个主题的设计问题。

## 9. 收尾 parity（`857a70d97`、`1c46e1811`）

| 提交 | Windows 本机（7 局） | Linux GCP（7 局 × 两遍） |
|---|---|---|
| `857a70d97` 机器人 | **7 / 7 一致**，PARITY 4105 行 × 36 字段 | rep1 **7 / 7 一致**；rep2 只有 `deep_p0` 落在变体 C（`cloud-results/pm-857a70d97`） |
| `1c46e1811` 场地 | **7 / 7 一致**，PARITY 4105 行 × 36 字段 | rep1 **7 / 7 一致**；rep2 只有 `deep_p0` 落在变体 C（`cloud-results/pm-1c46e1811`） |

### 9.1 剩余写死处（同 §3 口径）

| 机制 | main 3c28305c3 | 第二步 1c4f2e695 | 现在 1c46e1811 |
|---|---|---|---|
| `\blamp` | 444 / 66 | 397 / 66 | **397 / 66** |
| `\bmire` | 238 / 31 | 165 / 28 | **165 / 29**（多出的是 `run/arena.gd` 的注释与 `mire_blocked` 名字） |
| `beacon` | 230 / 33 | 186 / 31 | **183 / 32** |
| `\bzone_` | 323 / 41 | 255 / 40 | **249 / 41** |

协调人定：状态本身（`g.lamp / g.mires / g.beacons / g.zone_*`）的读取方暂不迁移，第三步（存档按主题分）之后再评估；剩下的主要就是这些读取方（HUD、遥测、画面、干员技能、Boss 招式）。

## 8. `game/art/index.json` 停止跟踪（`953866d48`，协调人同意）

- `git rm --cached` + `.gitignore`。`tools/asset_index.py` 加 `write(game_art)`（按磁盘重建，内容没变不写）。
- 用前重建的地方：
  - `export_build.py`、`export_web.py`（含 `--toy` / `--toy-out`）：`git archive` 解出副本后**第一步**重建（`web_half.make` 在瘦身之前读它，以前读的是仓库里那份旧的）；之后 `release_slim.prune_game_art` 照旧按瘦身后的文件再重写一次。`release_all.py` / `ship.py` 都经这两个脚本出包，`encrypted_release.py` 只改预设文本，`verify_encrypted_game.py` 读的是副本里的 index。
  - `godot_runner.ensure_imported`：快检、批跑、`trace_base` / `theme_parity` 临时工作树起 Godot 前重建。
  - 云端：`setup_linux.sh`、GCP `vm_startup.sh`（上一轮已加）。
- `ship.py` 的「工作区有未提交改动就停止」：被忽略的文件不出现在 `git status --short`，不再触发。**注意**：主工作区合入这个提交时 git 会删掉工作区里那份 index.json（它不再被跟踪）；下一次跑快检 / 出包会自动重建，手动开编辑器前先 `python tools/asset_index.py`。
- **出包对照**（本机，改前 = `1c4f2e695` 的工具与源码，改后 = `953866d48`；网页 / Toy 拼回分片解压、读 pck 目录比）：

| 包 | 改前 | 改后 | 结论 |
|---|---|---|---|
| Windows 对外加密包 | 打包副本 27224 个文件、pck 126.76 MB、加密 PNG 4545 张 | 同左 | 文件名与大小逐个相同（只有编辑器的 `filesystem_cache10` 差 3 字节）；副本 `art/index.json` 逐字节相同 |
| itch 网页包 | pck 12937 个文件、56.19 MB（6 片） | 同左 | pck 目录逐项（路径 + 大小）相同，含 `art/index.json` 323097 字节 |
| Toy 包 | pck 11459 个文件、33.60 MB（4 片）；zip 49,784,144 字节 | 同左 | pck 目录逐项相同，zip 字节数相同 |
