# 281 · 素材引用清扫与归档清单（11-06）

用户 11-06 睡前交代：整理素材与文档。基线 main 319b5de4b（分支 `claude/assets-docs-7bdf32`）。

## 0. 结论

1. **进包素材已经很干净**。10-24 的 docs/131 盘点、10-28 的 docs/188 / 189 整理（art/incoming 87 MiB 无人引用物、`enemy_redraw_1023` 等源素材移出）已经做完；现在 `game/art` 约 72 MB、9836 个文件，`game/audio` 约 83 MB。
2. 新扫描（`tools/asset_unref_scan.py`）**只找出 3 张确定无引用**的贴图，已删（共 3 张 + 3 个 .import，约 12 KB）。
3. 用户否决的终结技新版帧条（推进之王 / 乌尔比安 / 凯尔希 / 浊心斯卡蒂 / 归溟幽灵鲨 / 铃兰）**从未合入 main**，只存在于各自本地分支（见 §3），main 上没有要移走的。
4. 没有发现原作贴图 / Spine 进包：`game/` 里无 spine / skel / atlas / PRTS 文件；PRTS 参照图只在 `art/reference/prts/`（不在 Godot 工程内，导出不带）。原作音源可进包（11-05 授权，docs/279）。

## 1. 扫描规则（`tools/asset_unref_scan.py`）

运行时引用来源：`game/scripts/**/*.gd` 字符串字面量、`game/data/**/*.json` 键与值、`game/audio/**/*.json`（voice_pools / suno_layers）、`.tscn` / `.tres` / `project.godot` 全文（复用 `release_slim.runtime_text`）。贴图索引 `game/art/index.json` 由 `asset_index.py` 按目录生成，**不当作引用来源**（否则全部自引）。

一个文件算「有引用」，只要名字（去 `@1x/@2x`、去扩展名，带 `portraits/` `optical_fx/` 前缀的另算）出现在上面文本里；或 `res://` 路径出现；或可以在某个 `_` 处切成前后两段字符串字面量（`"growth_" + id`）；或匹配格式串（`%s` / `%d`）。release_slim 的白名单（`REVIEW_ART_GLOBS`）已确认没有误伤运行时引用（`release_slim.py` 通过）。

用法：`python tools/asset_unref_scan.py [--out 清单.tsv]`。

## 2. 已删（可从 git 找回：`git show 319b5de4b:<路径>`）

| 文件 | 原因 |
|---|---|
| `game/art/fx/fx_hh_streak@2x.png` | 寻访特效旧件，headhunt.gd 只用 beams / frags / reveal |
| `game/art/operators/mizuki/mizuki_48_original.png` | docs/131、55 提到过；运行时文本里没有引用（只有索引和 tools 路径表） |
| `game/art/world/terrain/terrain_mire_grow.png` | 运行时文本里没有引用（`mire_grow_cap` 只是数值旋钮，不是贴图名） |

同步更新了 `game/art/index.json`（4818 → 4815 个名字）。

## 3. 只列入清单、不删（拿不准）

扫描后仍标「无引用」的 423 个文件、5.45 MB，**绝大部分是误报**（运行时拼名字，静态扫不到）：

| 类别 | 个数 / MB | 判断 | 处理 |
|---|---|---|---|
| `art/fx/pxp/*`、`pxp/ult_sd/*` | 377 / 5.31 | 方向变体（`_d45` `_dm45`、`_gd` / `_up`、`_e0–e2`）由 `fx_pxplane*.gd` 按 `pxp_*.json` 的键 + 方向动态拼名；`ult_px_sd.gd` 按 `"sd_d" + 角度` 拼名。**绝大多数在用** | 保留。要确认哪些变体真没人读，须在 GCP 上带加载日志跑一遍（`tools/gcp/batch.py`），不要靠静态扫 |
| `art/fx/fx_kp_*`（Boss 预警 hit / mid / src） | 18 / 0.04 | 预警由 `"kp": "archon"` 等字段 + 拼名加载 | 保留 |
| `art/ui/medals/medal_*` | 18 / 0.06 | `medal_toast.gd` 的 `medal_%d.png` | 保留 |
| `art/ui/title_deep/jelly_*` `jglow_*` | 6 / 0.03 | `title_deep.gd` / `loading_screen.gd` 的 `jglow_%d.png` | 保留 |
| `art/world/terrain/terrain_regions.png` | 1 | 只被 tools/pxplane_gif_*.py 用 | 保留 |

被否决 / 搁置的终结技新版只在本地分支，**不要从分支合入**：

| 干员 | 分支 @ 提交 | 备注 |
|---|---|---|
| 推进之王 | `claude/pxplane-siege-2a54d6` @ e2673433c | 本机，不合 |
| 乌尔比安 | `claude/pxplane-ulpianus` @ 4f03d6841 | 只改了 docs/266 §21 |
| 凯尔希 | `claude/pxplane-kaltsit` @ ccd09f6e9 | 换色版已 revert 429ef38da |
| 浊心斯卡蒂 | 配色版 0d51ce1fa | 不合 |
| 归溟幽灵鲨 | 新版 d3aa10612 | 不合 |
| 铃兰 | `claude/suzuran-ult-px-shelved`（8563e013d / c98ac87fe） | 记录 `claude/pxplane-suzuran` @ 31d0d36d8 |
| Boss 描边 | `claude/boss-readable` @ 5176aea75 | 用户判旧版更好看，docs/277 |

## 4. 仓库里其它大头（只影响仓库 / 克隆体积，不进包）

| 目录 | 大小 | 说明 |
|---|---|---|
| `art/archive/` | 244 MB / 6968 文件 | 已归档的 10-28 前 incoming 内容，历史里本来就在；要进一步瘦身需用户决定（可整体移出仓库做压缩包） |
| `art/promo/` | 80 MB | 宣传 / 封面素材 |
| `art/source/` | 47 MB | 语音 WAV 母带等源文件 |
| `art/reference/` | 23 MB | PRTS 参照图（内部参照，不进包） |

## 5. 检查结果（本机，最多 1 个 Godot）

`asset_index` 一致；`asset_lint` ERROR 0；`release_slim` 通过；`art_lint` 21 人 FAIL 0（69 项已豁免）；`check.py --only ui_smoke` 通过；干员冒烟 `--only smoke` 见提交说明。
