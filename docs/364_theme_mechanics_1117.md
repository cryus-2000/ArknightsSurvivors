# 364 主题包重构 · 第二步：主题机制接口 ThemeMechanic（11-17）

**状态：已实装，待协调人合入。** 分支 `claude/theme-mech`，以 main `3c28305c3` 为底，按机制拆成四个提交，每个都过 `theme_parity`：

| 提交 | 内容 |
|---|---|
| `a5920f918` | 接口 `scripts/core/theme_mechanic.gd` + `ThemePack.make_mechanics` + 清单 `mechanics` 段；**灯火** → `mech_lamp` |
| `f19956a6f` | **溟痕** → `mech_mire` |
| `f6be8317e` | **引航灯标** → `mech_beacon`（原 `run/beacon.gd` 整文件搬家） |
| `eddc0593f` | **黑潮缩圈** → `mech_tide_zone` |
| `9baabf2b3` | 云端 `setup_linux.sh` 导入前重建 `art/index.json`（§5，和机制无关） |

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

## 5. `game/art/index.json` 缺 66 个名字（协调人顺带问）

- **原因确认**：仓库里提交的 `game/art/index.json` 落后于磁盘。重建只**增加** 66 个名字（22 张干员 `*_chibi`、`bad_guy_transport`、`op_lappland_move_throw@1x`、`op_wisadel_move_s2_attack@1x` / `_over_attack@1x`、星熊 `pxp_hsg_sweep_*_stance_up_*` 30 张、维什戴尔 `pxp_wd_dawn2_*` 12 张），没有删除、没有改路径。
- **为什么不直接提交新索引**：11-09 `c4b86fbdf`「撤回误提交的 game/art/index.json（本地生成文件，不进提交）」定的口径是不提交；本机每次录像 / 快检前都先 `asset_index.py` 重建，所以本机不红，只有云端新检出（用的是仓库里那份旧的）会红。
- **修法（`9baabf2b3`，安全）**：`tools/cloud/setup_linux.sh` 在导入前跑一次 `python3 tools/asset_index.py`，云端和本机口径一致。仓库里的 index.json 没动。
- **待协调人定**：既然「不进提交」，更干净的做法是 `git rm --cached game/art/index.json` + 加进 `.gitignore`，导出 / ship 链路确认都会先重建（`check_release` / `export_web` 是否依赖仓库版本要先查）。这一步改了跟踪状态，没替你做。
