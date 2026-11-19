# 主题开关与无灯火主题的空引用（T-R1，11-19）

萨米样例关键路径的第一件（docs/391 T-R1、docs/390 §11.1 两个「挡」项）。验收：`--theme=sami` 空主题包能进局不报错；deep_sea `theme_parity` 零差异。

## 1. 主题开关

- `ThemePack.id()`（`scripts/core/theme_pack.gd`）：开发版读命令行 `--theme=<id>`；否则读 `res://data/build.json` 的 `theme`；都没有 = `deep_sea`。`res://themes/<id>/theme.json` 不存在时 `push_error` 并退回 `deep_sea`。第一次调用后缓存，局中不切。
- 存档：`Cfg._theme_load` 本来就按 `ThemePack.id()` 切到该主题的存档层（docs/366），不用改。
- `ThemePack.has_mechanic(id)`：清单里有没有这个机制，game 没建好时也能问。

## 2. 打包时选主题（`tools/export_web.py --theme <id>`）

- 11-19 用户定：一个主题一个 Toy，itch 一个包带全部主题。
- 打包副本只留 `game/themes/<id>/`，`build.json` 写 `theme`。
- Toy 包一律只带一个主题：`--toy` 不给 `--theme` 时按 `deep_sea`；`--toy-out`（itch + Toy 共用导入）时 `--theme` 只管 Toy 那份，itch 那份照旧带全部主题。
- 非 deep_sea 主题的 Toy zip 名加 `_<id>`（`方舟幸存者_toy_<提交>_sami.zip`）。
- 还没做（T-D1）：标题 / 配乐 / 地面等仍放在 `game/art`、`game/audio` 下的主题素材按主题剔除；`check_release` 单主题校验。

## 3. 无灯火 / 灯标 / 骑士的主题

| 项 | 做法 |
|---|---|
| `g.lamp` | `game.has_lamp`（清单有 `lamp` 机制）为假时，`g.lamp` 钉在 `LAMP_NEUTRAL = 50`（setter：加减写进来也拉回 50）。三十多处干员 / 藏品 / 事件直接加减、按档位读（≥70 通明 / <30 昏暗 / ≤0 熄灭）的效果在 50 都不触发，不用逐处改 |
| 灯光增伤 | `combat.gd` 「光中敌人 +25% / +40%」只在 `has_lamp` 时生效 |
| 灯光半径 | 判定 `lamp_r()` 原本就按满灯；画面 `world.gd` 灯光半径也按满灯 |
| `g.beacon_sys` | 原有调用都已判空；`onboard.light_demo`、`autotest._light` 补判空 |
| `g.knight` | 清单 `modules` 没有 knight 时 `ThemePack.make_module(game, "knight", fallback)` 用 `scripts/core/knight_none.gd`（空骑士：同名成员、空函数，永远不在队）。新主题不必再自己写空实现（docs/369 §5 那条改成可选） |
| `g.ishar` / `g.duck` | 第五步已判空，没有模块就是 null |

**仍归后续单子**：

- HUD 的灯火条、作战记录 / 统计面板的灯火行（T-C5「HUD 无灯火条」）。
- 灯火 / 灯标藏品出池（T-C5）。
- 油灯类掉落仍会掉，拾取不涨灯火（T-B2 / T-C5 换掉落表）。
- 音乐里灯火驱动的滤波按 50 算（`music_director`）。

## 4. 萨米占位包

`game/themes/sami/theme.json`：数据与地图全指向水月，机制、模块都空，只为验证开关和空引用。T-B1 起由主题会话换成萨米自己的 data / maps / mech / mod。

## 5. 验证（`820384a21`，基线改前 main `e257f0de6`）

| 项 | 结果 |
|---|---|
| 萨米冒烟（Linux 云端 `cloud-results/theme-switch-1119`） | 3 局 `--theme=sami` 机器人局 0 条脚本错误，`lamp` 全程 50：mizuki `--maxt=300` 打到 218 秒阵亡；skadi `--god` 691 秒胜、logos `--god` 731 秒胜（结局 standard，主题数据仍是水月的）。`--theme=nosuch` 只报一条「theme not found」、按 deep_sea 进局 |
| theme_parity Linux（同上，基线录两遍） | 6 / 7 逐帧一致；`deep_p0` 伊莎玛拉战 t=646.5 秒分歧（rng 全同，只有 `eh` / `boss` 不同） |
| `deep_p0` 加跑（`cloud-results/theme-switch-deep-1119`，同机型改前 / 改后各 3 遍） | 改前自己 3 遍互相分叉（t=648.5），改后自己 3 遍也分叉（t=672.3）；两次云端跑之间改前自己也不同（t=638.6 vs t≈680）。改前 / 改后之间没有一对逐帧相同，分歧点 638.6 / 646.5 都在 docs/359 §5、docs/364 §4 记过的伊莎玛拉战窗口，分歧行 rng 全同、只有敌人血量哈希不同 |
| theme_parity **Windows 本机**（确定性对照） | `deep_p0w`（Windows 走 deep 线，**完整打伊莎玛拉战**，750 秒胜）、`deep_p0` 两局都 **逐帧一致**（PARITY 1508 行 × 36 字段） |
| 快检（Linux 云端） | core、data_lint、check_release 通过；graph_lint 19 条命中，全是令 / 傀影技能图标不在贴图索引（这些数据本提交没动，不是本提交引入） |

**判定**：Linux `deep_p0` 是已知的环境不确定性（同一提交自跑就分叉），不是本提交引入；本提交在确定性的 Windows 上把同一段伊莎玛拉战逐帧复现。代码层面 deep_sea 下 `has_lamp` 恒真，setter / combat / world 三处改动在水月下取值与改前完全相同。

**附带观察**：这次改前 / 改后 10 份 Linux 记录没有一对跨提交逐帧相同（前几步每次都有），按「环境偶发」解释得通，但 Linux `deep_p0` 已经不适合当零差异判据，建议以后这局只看 Windows（`deep_p0w`）或干脆从 Linux 判据里拿掉。
