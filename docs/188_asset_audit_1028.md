# 188 · 素材命名与目录核对（10-28）

用户 10-28 批准的素材整理第三项：**只列清单，不改**，等用户看。前两项已做（分支 `claude/asset-tidy-cfffcf`）：

- art/incoming 已接入的批次子目录与交接文档归档到 `art/archive/incoming_1028/`（见 §4）；
- 旧程序合成配乐与 SEQ 乐句拼接回退已删（docs/164、docs/21 注明）。

范围：`game/` 下全部素材（png / webp / ogg / wav / ttf / otf，不含 tests、tools、addons）共 540 个，另外把 `art/incoming/` 根目录 1631 张运行时 PNG 一起算进查重。
做法：按 sha256 查重；文件名对照 `小写字母数字 + 下划线 (+@1x/@2x)`；名字在 scripts / data / 场景里查引用，查不到的再手工看是不是拼名字加载的（`A.tex(name + "_white")`、`DIR + "medal_%d"` 之类）。
上一轮盘点见 docs/131，本文只记它之后仍然存在或新发现的问题。

## 1. 结论

| 类别 | 数量 | 处理建议 | 风险 |
|---|---|---|---|
| 没人读的文件 | 2 个，24 KB | 删（docs/131 §6 第二批已提过，一直没做） | 低 |
| 源文件放在运行时目录里 | 1 组，22 MB | 移出 game/（要用户定，同 docs/131 §7.1 第 1 条） | 中 |
| 同内容不同名 | 16 组 | 多数是有意复用，不改；干员技能条与攻击条完全相同的 5 组可以改成别名省 0.26 MB | 低 |
| 命名不合约定 | 4 处 | 改名要连带改代码 / 数据，收益小，建议不动 | — |
| 目录不合常规 | 1 处 | 不动 | — |
| 缺 .import / 孤立 .import | 0 | — | — |
| 音效：文件与载入表不一致 | 0 | 178 个 wav 全部能对上 NAMES / OP_SFX 或寻访屏字面量 | — |

## 2. 明细

### 2.1 没人读的文件

| 文件 | 大小 | 依据 |
|---|---|---|
| `game/art/player.png` | 14.3 KB | 初始提交遗物。`A.tex("player")` 落到 `art/px/player.png`，没有代码读 `res://art/player.png` |
| `game/art/px/mizuki_chibi_walk.png` | 9.7 KB | 初始提交遗物，名字在 scripts / data / 场景里都查不到 |

同带一处：两个导出预设的 `exclude_filter` 里还写着 `art/player_cut.png`，这个文件早就不在了，可以一起删掉这条规则。

### 2.2 源文件放在运行时目录里

| 目录 | 大小 | 说明 |
|---|---|---|
| `game/audio/voice/masters/*.wav`（123 个） | 22 MB | 语音 WAV 母带，`.gdignore` 挡住不进包，`game/tools/voice_ogg.py` 重编码时读。放在 game/ 里会被 check.py / 导出暂存复制，仓库体积也算它。建议移到 `art/archive/voice_masters/` 或仓库外存档；移仓库外的话重编码要改读外部路径，**要用户定** |

### 2.3 同内容不同名（sha256 完全相同）

干员 / 怪物帧条在 `art/incoming/` 根目录（游戏按名字读）：

| 大小 | 文件 | 判断 |
|---|---|---|
| 78.0 KB + 19.3 KB | `op_specter_unchained_death@2x` = `op_specter_unchained_fall@2x`；`@1x` 同 | 倒下与跌落用同一条，可改别名 |
| 62.4 KB | `op_suzuran_attack@2x` = `op_suzuran_skill_s1@2x` | 技能条复用攻击条，可改别名 |
| 56.8 KB | `op_eyjafjalla_attack@2x` = `op_eyjafjalla_skill@2x` | 同上 |
| 50.8 KB | `op_hoshiguma_attack@2x` = `op_hoshiguma_skill@2x` | 同上 |
| 34.7 KB | `op_exusiai_attack@2x` = `op_exusiai_skill@2x` | 同上 |
| < 1 KB × 8 组 | `e_knight_attack_emit` = `charge_emit` = `charge_form_emit`；`e_skimmer_emit` = `move_emit`；`e_reaper_attack_emit` = `awaken_emit`；`e_reaper_dormant_emit` = `e_reaper_emit`；`e_mimic_emit` = `move_emit`；`e_nest_emit` = `move_emit`；`e_mimic_disguised_emit` = `disguised_wound_emit`（均 @2x） | 怪物发光层空白 / 近空白帧，重画安装器按动作各出一份。太小，不值得改 |

蚀刻章空插槽（`game/art/ui/medals/`）：`medal_1/2/4/5_slot` 四张相同，`medal_7/10_slot`、`medal_8/11_slot` 各两张相同。按章号拼名字读（`medals_ui.gd` 的 `DIR`），同形状的章插槽本来就一样，不改。

前五组改别名的做法：删掉 `_skill` / `_fall` 那份，在干员 JSON 的 `sprites` 里让该槽指向攻击条（或在 art.gd ALIAS 加一条）。要连带改 art_lint 的帧数检查和 `release_slim` 的引用扫描，省 0.26 MB（对外包）。**建议等干员美术大改（op-art-on-hold）时一起做**，现在不动。

### 2.4 命名不合约定

| 位置 | 现状 | 问题 | 建议 |
|---|---|---|---|
| `game/audio/music/archive_v2.ogg` | 带版本号 | `sfx.gd` 用常量 `ARCHIVE_FILE` 指向它；现在只是 `suno_archive_full` 缺失时的回退 | 不改名；Suno 版稳定后连同 `final_suno` 一起考虑删（两首 4.7 MB，网页包已不带） |
| `game/audio/music/final_suno.ogg` | 前缀与其余 Suno 曲不一致（其余是 `suno_*`） | 同上，只在 `suno_final_p1/p2` 缺失时用 | 同上 |
| `art/incoming/op_skadi_attack_v2@1x/@2x.png` | 带版本号 | `skadi.json` 与 `tools/op_1x/` 按这个名字读 | 不改（改名要动数据与工具，没有收益） |
| `art/incoming/mizuki_runtime_*`（20 张）、`player_*@2x`（10 张） | 水月不走 `op_<id>_*` 前缀 | 历史原因：水月是最早的队长，帧条名早于干员命名约定；`mizuki.json`、world.gd 缺省帧条按这些名字读 | 不改；干员美术大改时可统一成 `op_mizuki_*` |

`art/incoming/` 根目录 1631 张 PNG 全部是小写 + 下划线，没有空格、大写或中文。

### 2.5 目录不合常规

| 文件 | 说明 | 建议 |
|---|---|---|
| `game/shaders/optical_lut.png` | 贴图放在 shaders/ 里（光学观感的调色表，optical.gdshader 与 optical.gd 用） | 跟着着色器放更好找，不动 |

## 3. 没列的

- `game/art/px/e_chest_white.png`、`e_event_white.png`：名字查不到，但 art.gd 按 `name + "_white"` 拼出来读（描边 / 受击闪白），在用。
- `game/art/ui/medals/medal_*.png`、`game/art/ui/title_deep/jelly_* / jglow_*`：按 `DIR + 格式串` 拼名字读，在用。章号 6、9 没有图，medals.json 里也没有这两个 id，一致。
- `game/art/event_cg/hi/` 与 `web/` 同名两套：桌面 / 网页各一套分辨率，导出预设分别排除另一套，正常。
- `game/audio/sfx/hh_*`（8 个）：不在 NAMES 表里，寻访屏按字面量直接读，在用。
- `art/incoming/portraits/`：docs/131 已记为死路径（Boss 名片改用 `portrait_crop`），仍被 Windows 包 `ART_SUBDIRS` 打进去；第一项归档时没动（它是运行时子目录，删要连带改 enemies.json 与 export_build.py）。

## 4. 第一项归档的留底清单

`art/archive/incoming_1028/`：12 个批次子目录（enemy_redraw_1023、world_spec_1024、voice_batch5_1012、voice_batch6_1022、headhunt_reference_fx_1022、doctor_1x_1023、title_jelly_1024、event_cg_1026、node_route_c_delivery_1026、achievement_ui_1024、headhunt_professions_1025、meta_ui_1025）+ 根目录 240 份交接 md / 清单 json。

留在 `art/incoming/` 没挪的（拿不准或仍被引用）：

- 根目录 1631 张 PNG、`portraits/`、`optical_fx/`：游戏运行时按名字读，不能挪。
- `README.md`、`monster_v2_handoff.md`：CLAUDE.md 写明在这里。
- `codex_handover_1022.md`、`codex_material_grains_1024.md`、`codex_order_*`（7 份）、`codex_task_*`（7 份）：Codex 单子，是否全部完成没法从仓库判断。
- 被代码读写或注释点名的 22 份清单 / 交接：`elite_art_1–5_manifest.json`、`enemy_fx_1_manifest.json`、`enemy_v8_handoff.md`、`fx30_handoff.md`、`logos_fx_handoff.md`、`skalter_s3_handoff.md`、`skalter_vortex_handoff.md`、`squad_2x_handoff.md`、`boss_moves_1_handoff.md`（art.gd / 测试注释）；`knight_ice_manifest.json`、`mizuki_runtime_manifest.json`、`relic_icons_hand_manifest.json`、`skill_icons_batch3_manifest.json`、`angelina / siege_ulpianus / skalter_specter / texas_hoshiguma_native_sources.json`、`siege_ulpianus_runtime_handoff.md`、`three_operator_art_1019_handoff.md`（工具读写或 art_lint 豁免注释）。
- `music_suno/`：本地 Suno 母带，未跟踪，没动。

搬走的生成脚本（meta_ui_1025 的 layout / icons / render，title_jelly_1024 的 bake，achievement_ui_1024 的 bake_pixel，enemy_redraw_1023 的安装源）已把 `parents[]` 加一层，安装器 `install_enemy_redraw.py`、`install_world_spec.py`、`probes/package_headhunt_bagfx.py` 的源路径改到归档目录。只按路径改了，没有重跑这些生成脚本。
