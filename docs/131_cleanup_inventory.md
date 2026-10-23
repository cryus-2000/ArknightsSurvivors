# 131 · 交接前清理盘点（10-24，架构）

用户：「先把架构和代码整理一下，一些老的美术依赖和一大堆 preview 都可以清理，先去盘点」（准备换账号接手）。只读盘点 main 273d4cae，**未删任何东西**。
逐文件清单（机器生成，带证据列）在架构会话 scratchpad `inv/`：`art_files.csv`（art/incoming 9952 行）、`op_fx.csv`（干员特效 223 名）、`game_*.csv`、`tools.csv`、`docs.csv`；本文只写结论与有代表性的证据。
与 docs/130（光学观感下的老特效）对得上：本文管「文件与依赖」，130 管「运行时画法」。

## 0. 结论

| 区域 | 现有 | 可省（删 / 移出仓库） | 其中进包的 |
|---|---|---|---|
| art/incoming | 276 MiB / 9952 文件，**真正在用的只有约 21 MiB** | 无人引用 + 审稿产物 **92 MiB**；再把大号源素材目录移出仓库 **约 186 MiB** | 约 3.7 MiB（遮蔽的 1x 帧条 2.5、lineup 0.9、portraits、只登记不播的特效 0.2） |
| game/ | 死重很少 | 0.5 MiB（全部进包）；语音母带移出再省 20.7 MiB（不进包） | 0.5 MiB |
| tools/ | 286 个 / 2.5 MB | 一次性脚本 + 探针约 0.6 MB | — |
| docs/ | 224 个 / 8.6 MB | 归档挪动为主，基本不删 | — |
| .git | **2.9 GB**（pack 2.71 GiB） | 不改历史时 0；**1.25 GB 是 Spine 源 zip**（只在 codex/* 分支上，不在 main） | — |

**最大的一件事不在工作树里**：本地 .git 的 2.9 GB 里约 1.25 GB 是 `art/incoming/dn_latest_spine_delivery_1020/*.zip`（Codex 的 Spine 源存档，按约定不合 main、不推远端），另有约 0.13 GB 是 Codex 工具的快照引用（`refs/codex/*`，11 个）里带进来的大 wav / zip。换账号克隆远端时这些都不会跟过去；本机清 .git 需要用户定（§5）。

**顺带查出一个 bug**（§1.4）：19 名干员 json 里登记的 `move_attack`（边跑边打，10-23 加的）帧条**从没被加载**——game.gd 只加载 6 个主槽 + `extra_sprites`，这 19 人的 `move_attack` 都不在 `extra_sprites` 里，`character._move_swap` 永远拿到 null。不是清理项，要修（加进加载列表），已单列。

## 1. art/incoming

### 1.1 名字怎么落到文件（判断「在用」的依据）

- `A.tex(name)`（art.gd:272-357）按序取第一个存在的：`<名>@1x.png`（`render/op_1x` 缺省开）→ `<名>@2x.png` → `<名>.png` → ALIAS → `res://art/px/<名>` → 占位。**同名有 @2x 时 1x 基础 png 永远不会被读**；唯一例外是 boss_intro.gd:153 直接读 Boss 1x 原图裁名片。
- 能走到 `A.tex` 的名字：所有 .gd 字符串字面量与 json 值（含前后缀拼接、`%s` 格式）、enemies.json tex × 后缀表、enemy_redraw.json 键、干员 `sprites` 里**被加载的**槽（6 主槽 + extra_sprites + base / noshield，game.gd:536、760）。
- 打包：Windows 包带根目录全部 png（排除审稿通配）+ `portraits/` + `optical_fx/`；公开包与网页包再去掉干员 @2x 回退帧条（`release_slim.is_fallback_2x`）；**网页包只拷根目录 png，`optical_fx/` 不进网页包**（export_web.py:89-97）。

### 1.2 按目录

状态：**R** 游戏里加载 / **R-ui** @2x 待机条作界面立绘 / **R-opt** 光学压阶版 / **F** 只在 `op_1x=0` 时用 / **S** 被同名高优先级变体遮蔽、永不加载 / **U** 登记了但没加载的槽 / **D** 只被 docs / tools / tests 提到 / **N** 无人引用。

| 目录 | MiB | 文件 | 状态 | 说明 | 建议 | 风险 |
|---|---|---|---|---|---|---|
| enemy_redraw_1023/ | 146.4 | 6315 | D | tools/install_enemy_redraw.py 的源；安装只需 829 个（5.1 MiB：本体 / 发光帧条、各怪 manifest、integration_map），根目录 796 份装好的副本与源逐字节相同；其余约 141 MiB 是 components、contact、parts.json、lineup、wound_compare、review.html、remaining/（22）、generated/（4）、f0/、prompt、comparison | 留安装子集，其余移出仓库存档 | 低（重装要从存档取） |
| 根目录 *.png | 44.9 | 2388 | 混合 | 在用 8.7 + 界面立绘 1.5 + 回退 9.8；遮蔽 2.5；未加载槽 0.3；D 2.7；**N 19.5**；其中审稿图 22.0 | 见 1.3 / 1.5 | — |
| 根目录 *.gif | 37.5 | 70 | N / D | 全是审稿动图（preview 等） | 删 | 低 |
| headhunt_reference_fx_1022/ | 20.2 | 60 | D | docs/124 与 tools/probes/package_headhunt_bagfx.py 的源；运行时副本 `fx_hh_*@2x.png` 已在根目录（headhunt.gd:757-771） | 移出仓库存档 | 低 |
| voice_batch5_1012/、voice_batch6_1022/ | 10.5 | 120 | D | 语音交付源；游戏读 game/audio/voice（55 条在那里，30 条相同、25 条已被替换）；batch6 带 WAV 母带 | 移出仓库存档 | 低 |
| codex_order_ui_ref/ | 4.4 | 34 | N | Codex 界面单参照图，只有 handoff md 提到 | 移出 / 删 | 低 |
| 根目录 *.json | 2.9 | 249 | D / N | 1.8 MiB 是 *_qa*.json 审稿数据 | 审稿 json 删 | 低 |
| ui_shell_1022/ | 2.7 | 80 | N | 局外三屏交接（截图、review.html、渲染脚本），已合入 | 移出 / 删 | 低 |
| codex_op1x_heads/ | 2.1 | 40 | D | `*_auto1x` / `*_ref` 对照对 | 删 | 低 |
| 根目录 *.html | 1.9 | 10 | D / N | review.html 类 | 删 | 低 |
| optical_fx/ | 1.5 | 373 | R-opt 1.07 / S 0.42 | 219 个压阶版在用、无过期；153 个基础 png 被同名 @2x 遮蔽 | 删遮蔽的 153 个（先改 tools/optical_fx_quant.py 不再出 1x） | 低 |
| v15_qa/、v13_qa/、_trial_icons/、cm_enemy_scale_runtime_1018/、codex_order_headhunt_ref/ | 0.9 | 35 | D / N | 小号 QA / 试做 / 交接 | 删 | 低 |
| 根目录 *.md | 0.3 | 139 | D / N | 交接 md（Codex 单、handoff） | 保留（文字小，是交接记录） | — |
| bosses/ | 0.3 | 18 | D | 旧 Boss 待机批 + boss_preview，没有代码读 | 删 | 低 |
| portraits/ | 0.02 | 20 | 死路径 | enemies.json `intro.portrait` 字面量还在，但 10 个 Boss 都有 `portrait_crop`，boss_intro.gd:24-36 从不读 portrait；仍被 Windows 包 `ART_SUBDIRS` 打进去 | 删目录 + 删 json 字段 + 去掉 ART_SUBDIRS | 低 |

### 1.3 被新素材取代的老美术

1. **被同名 @2x 遮蔽的 1x 基础帧条：578 个、2.46 MiB，全部进包、永不加载。** 391 个 `e_*`（重绘安装器两种尺寸都拷，1.93 MiB）、172 个 `fx_*` / `proj_*`（0.47 MiB）、`doctor*` ×5、`op_mon3tr_{attack,attack_melt,idle,run,skill}`、`prop_ice_stake*`、`prop_lamp_post`、`prop_lighthouse`、`merchant`。**例外保留**：10 个 Boss 的 1x（e_path / e_izumik / e_saint / e_saint_dark / e_bishop / e_archon / e_immortal / e_paranoia / e_ishar / e_knight），boss_intro.gd:153 直接读。删前先改 install_enemy_redraw.py、optical_fx_quant.py 不再产 1x。
2. **怪物旧帧条 vs 10-23 重绘**：有重绘的怪不再画旧条。剩下 `drifter / dart / crawler / shell / boss / tentacle / jelly.png`（约 5 KB，只在 art.gd:822-823 BASE_TEX 和 ALIAS 回退里，没有绘制点）可删；`e_carmen*` / `e_iberia*`（45 KB）——卡门 / 伊比利亚已改用 e_saint / e_saint_dark，但 `e_carmen_spin@2x` 还在 enemy_pixels.json 和 world.gd 里，**先核再删**。
3. **干员 @2x 回退帧条：214 个、9.75 MiB（F）**，只在 `op_1x=0` 时用，公开包 / 网页包已剔除、只进对内包。其中 31 个待机 @2x（1.49 MiB）是界面立绘（`tex_hi`），必须留。其余 183 个：若 `op_1x=0` 开关不再需要就删（**要用户定**，见 §6 第三批）。
4. **旧 48 px 水月帧条**（`player_*@2x`、`player_attack_48@2x`，约 95 KB）：旧水月路径仍接着（world.gd:1535、1612-1634；intro.gd:290），保留。`mizuki_48_original.png`（D，docs/55）、`player_48_preview.png`（N）删。
5. **`op_skadi_attack@1x/@2x`（56 KB）**：已被 `op_skadi_attack_v2` 取代，只有测试干员 game/tests/data_ops/eqtest.json、sstest.json 还用，却每个包都带。先把两个测试改指 v2（会动积木等价金样），再删。
6. 旧 48 帧干员条已不存在；旧 FXF 名（`fx_s1_* / fx_s2_* / fx_s3_*`、`fx_cast`、`fx_stun`、`fx_death`）只剩名字登记、没有文件；`fx_hit.png`（242 B）是 vfx.gd:568 的兜底，留。

### 1.4 干员命中 / 特效美术（用户点名）

223 个干员相关 `fx_*` / `proj_*` 名，连同所有变体只有 **1.64 MiB**——清特效省不了多少体积，主要是理清依赖。所有 V6_FRAMES 条开局都会加载（game.gd:771-772），所以「登记了」≠「播了」。光学 `_fxq_step`（optical.gd:152-176）把 g.tex 里每个 `fx_` / `proj_` 换成 `optical_fx/<名>`（宽度一致才换）。

| 类 | 名数 | 大小 | 状态 | 建议 |
|---|---|---|---|---|
| 在播、有光学压阶版 | 186 | 1.41 MiB | 光学开时被 optical_fx/ 取代；根目录原条是光学关（低档）回退 | **只在光学关时作回退保留**（低档要用，不能删） |
| 在播、无光学版：`fx_missile_explode`、`fx_rock_burst`、`fx_rock_spike`、`proj_fireball`、`proj_lavaball`、`proj_tide_blade_abyss` | 6 | 0.02 MiB | 运行时在用 | 保留（可补压阶版） |
| 上面在播特效的被遮蔽 1x 基础条 | 172 个文件 | 0.47 MiB | S | 删（同 1.3-1） |
| 命中火花类（hit / impact / burst / splash / muzzle / flash） | 38 | 92 KB | 在播；**三级命中模板（claude/hit-tiers）将接管**，见 docs/130 §2.B | 等 hit-tiers 落地后按它的结论删留 |
| **只在 V6_FRAMES 登记、art.gd 以外无任何播放点** | 31 | 约 0.19 MiB | N（死登记） | 删帧条 + V6 条目 + 对应 optical_fx 副本（删前抽查运行时拼名） |

命中火花类 38 个：通用 / 按怪类 `fx_hit`、`fx_hit_flesh / shell / spirit`（vfx.gd:561-568）、`fx_arcane_hit`、`fx_bullet_hit`（weapons.gd:145、153）；能天使 `fx_exusiai_hit`、`_hit_gold`、`_hit_s1/s2/s3`、`_muzzle`、`_muzzle_gold`、`_muzzle_s1/s2/s3`、`_blessed_flash`；艾雅法拉 `fx_eyja_ignite_hit`、`fx_eyja_lava_splash`、`fx_flam_hit`、`fx_sunburst`；塞雷娅 / 流明 / 逻各斯 `fx_holy_impact`、`fx_holy_impact_lantern`、`fx_lumen_beam_hit`、`fx_lumen_refract_hit`、`fx_ink_hit`；艾丽妮 `fx_irene_gun_burst`、`fx_cannon_burst`、`fx_muzzle_flash`、`fx_thrust_hit_rose`、`fx_star_hit_rose`（ob_hw.gd:746）；斯卡蒂 / 歌蕾蒂娅类 `fx_skadi_leap_splash`、`fx_skadi_surge_hit`、`fx_splash_blue`、`fx_water_splash`；其他 `fx_hoshiguma_saw_spark`、`fx_specter_doll_burst`、`fx_rock_burst`。

只登记不播的 31 个（game/scripts、game/data 除 art.gd 外按全名与片段 grep 均无命中；也没有 `+ "_back"` / `"_front"` 拼名，world.gd:1860 只给敌人 burst_fx 拼）：
- `fx_skalter_s3_back / front / orbit`（95 KB，已换成漩涡）
- `fx_ulpianus_anchor_impact_back / front`、`fx_ulpianus_pull_ring`（13 KB）
- `fx_specter_saw_cold_back / front`（10 KB）
- `fx_mizuki_tentacle_mass`（15 KB）
- 水月 V7 遗留：`fx_kraken_rise`、`fx_tendril_stake`、`fx_tendril_stake_whip`、`fx_tentacle_grab`、`fx_tide_blade_hit`、`proj_tide_blade`、`proj_tide_blade_moon`（约 46 KB）
- `fx_slash_circle_deep / rose / ghost / blood`、`fx_claw_green`、`fx_fire_aura`（siege.gd:245 注释已写移除）、`fx_flames`
- `fx_laser_start / mid / end`、`fx_arrow_hit`、`proj_missile`
- `fx_mon3tr_afterimage`、`fx_texas_rain_hit`、`fx_texas_sword_impact`
- 非干员：`fx_nest_aura`（已被 `fx_nest_aura_big` 取代，world.gd:2748）、`proj_drone_bullet`

**登记了但从不加载的槽（bug，别删）**：`move_attack` 在 19 名干员 json 的 sprites 里（除斯卡蒂外全员），文件 `op_<id>_move_attack@1x.png` 19 个 / 0.34 MiB；19 人都没把它列进 `extra_sprites`，game.gd:536 / 760 只加载主槽 + extra，character.gd:1669 `_move_swap` 的 `anim_tex("move_" + k)` 永远 null——10-23 的边跑边打（281d3ce5）大概率一直没生效。**修法**：加载列表加上 `move_attack`（或 json 补 extra_sprites），修完用截图确认。其余 extra_sprites 槽都有对应动画名引用。

### 1.5 审稿产物：751 个、84.1 MiB

| 类（根目录） | 文件 | MiB |
|---|---|---|
| `*preview*`（png + gif） | 182 | 52.5 |
| 名字不带 preview 的 gif | 38 | 4.7 |
| `*_qa*`（多为 json） | 92 | 1.2 |
| `art_review_0926_*` | 18 | 1.8 |
| `*lineup*` | 16 | 0.9 |
| compare / comparison / contact / composite / overview | 23 | 1.2 |
| `elite_art_*`、`run_rework_*`、`idle_pose_*`、`facing_*`、`*_frames.png` | 63 | 1.1 |
| `*.html` | 10 | 1.9 |

子目录里另有：enemy_redraw_1023 11.6、headhunt_reference_fx_1022 7.0、codex_op1x_heads 2.1、bosses 0.2 MiB。

**漏网进包**：lineup 图不在 `REVIEW_ART_GLOBS` 里，16 个 / 0.9 MiB 进了包（`ally_rework_1014_lineup`、`boss_moves_1_lineup` 233 KB、`elite_cool / elite_rework_1014_lineup`、`enemy_fx_1_lineup`、`enemy_redraw_{1,2,3}_lineup`、`op_fix_{a,b,b_eye,c,d,e,g_wisadel}_lineup`、`reaper_lineup`），另 `op_fix_b_eye_detail.png`、`op_fix_g_wisadel_eyes.png`（92 KB，N）也进包。修法：`*lineup*` 加进 `REVIEW_ART_GLOBS` 和两个导出预设的 `exclude_filter`。

## 2. game/

| 项 | 文件 | MB | 进包 | 证据 | 建议 | 风险 |
|---|---|---|---|---|---|---|
| art/px 里被 art/incoming 覆盖的回退图（boss、chest、slash、tiles、全部 e_* 本体、ally_*、gem_*、oil、merchant…） | 44 | 0.30 | 是 | art.gd tex() 先查 art/incoming，同名存在就到不了 art/px；唯一别的读者是 godot_runner.py:405 拿目录列表当缓存键 | 删 | 低（缓存重建一次） |
| art/px/`*_white.png` | 25 | 0.17 | 是 | game.gd:727 有覆盖时用 `A.white_of()` 现做白版；boss / crawler / dart / drifter / shell 从来不做白版 | 删；**留 `e_chest_white`、`e_event_white`**（底图没有 art/incoming 版，真在用） | 低 |
| art/px/`mizuki_chibi_walk.png`、game/art/`player.png` | 2 | 0.03 | 是 | 无名字命中；`A.tex("player")` 落到 art/px/player.png；player.png 是初始提交遗物 | 删 | 低 |
| render/`retreat_fx.gd` + tests/`retreat_capture.gd / .tscn / .uid` | 4 | 0.01 | 否 | 无加载点；1eb2a67f 写「保留但不再触发」（10-22 退场改死亡帧条） | 删 | 低 |
| audio/voice/`masters/*.wav` | 121 | 20.7 | 否（.gdignore） | game/tools/voice_ogg.py 重编码用；语音 manifest 记 `master:` | 移出仓库存档（同 Spine 源） | 中（重编码要外部副本），**要用户定** |
| tests/golden/`fd9ce553/` | 28 | 0.45 | 否 | 与 golden_current/ 同名；check.py 约 802 行只作最后兜底读 | 去掉兜底后归档 | 低-中 |
| export_presets.cfg 排除 `art/player_cut.png` | — | — | — | 文件不存在，过期的过滤文字 | 顺手删 | 无 |

- 音效 162、音乐 71、语音 121 条、字体、着色器、`art/ui/settlement/*` **全部有引用**；没有孤儿 .uid / .import。`game/tests/manual_aim_probe.gd` 缺跟踪的 .gd.uid（违反 uid 随脚本），下次碰它时补。
- **game/tests/ 没被任何工具跑的 17 个**（都还能跑，只有 retreat_capture 确定失效）：attack_timing_capture、build_cards_capture（10-24 在用，留）、demo_hitch_probe、doll_flash_capture、enemy_identity_capture、enemy_scale_field、entry_capture、follow_pause_capture、logos_projectile_capture、merchant_leave_capture、op_ui_capture、response_demo_capture、retreat_capture、three_lifecycle_trace、three_operator_art_capture、wisadel_phase_trace、wisadel_s2_capture。建议归档其中 10-18 / 10-19、已有 check.py 对应测试的 5 个（attack_timing、three_operator_art、wisadel_s2、logos_projectile、enemy_identity，约 25 KB）。
- **balance.json 526 个叶子**：308 字面量读、13 `%s` 格式读、162 前缀拼接读（启发式）、36 节读、1 数据文件旋钮读；**确定没读点 6 个**：`command/search`（自己的 _doc 写「已不用」）、`enemy/close_ring_spread`（代码读 `_deg` 版，这是改名前的旧键）、`enemy/horde_shake`、`fx/atk_dir_alpha`、`fx/atk_dir_len`、`fx/outline_max`（game.gd:450 注释称旧描边路径）。删（后两个低-中风险）。data_lint 只做字面量匹配，漏了 `CmdBal / BranchBal / preload(...).v` 别名和数据文件旋钮——`close_ring_spread` 就是这么漏的；可顺手补。其余 data/*.json 没有死顶层键。

## 3. tools/、tools/probes/

- **核心（留）**：check.py 调的 godot_runner、art_lint、data_lint、enemy_art_check、ob_tag_audit、op_cc_lint、op_text_check、px_lint、release_slim、op_dummy_table、balance_run；ship.py 调的 check、check_release、clean_local、release_all、deploy_itch；release_all 调的 export_build（+ encrypted_release）、export_web、verify_web_build、verify_encrypted_game；`web/*`、`cloud/*`、trace_base（AGENTS 点名）、三个单元测试。
- **常用工具 / 生成器（留）**：都有代码、现行文档或 launch.json 引用（cloud_compare、runs_report、prts_spine*、serve_web、web_cloud_mock、deploy_web、加密模板两件、rename_game、split_module、install_enemy_redraw、optical_fx_quant、fx_recolor、make_ui_fallback、各图标 / 特效生成器……）。在做的干员管线 `op_1x/*`、`spine_editor/*`、`spine_run_trial/*` 留。
- **一次性 / 过期候选**（10-10 用户批过「孤儿工具可删」规则，docs/55 §3：整词复核后先问归属会话）：

| 路径 | 大小 | 证据 | 建议 | 风险 |
|---|---|---|---|---|
| b6_direct_ob.py、b6_fix_infer.py、b6_split_op_blocks.py、fix_nova_cannon.py | 22 KB | 10-11 / 10-15 一次性迁移，只有 docs/101 与 docs/41 派单记录提到 | 删 | 低 |
| concept_title_ui.py 与 _v2–_v5、_v4_sel、concept_operator_ui、concept_run_stats(+_layout)、concept_contracts、concept_is3_levels | 434 KB | 已定稿界面的样图生成器，互相 import；**concept_headhunt（docs/124 在用）依赖 concept_title_ui 与 _v4（_v4 又要 _v2、_v3）** | 整组移出仓库；headhunt 在用期间留 title_ui / v2 / v3 / v4（或把依赖内联进它） | 中（import 链） |
| promo_*（10 个，含 promo_shots.gd） | 102 KB | 10-01 至 10-07 宣传图；docs/102 改名方案要重跑其中 3 个 | 改名定了再归档 | 低 |
| relic_icons_hand_a.py 至 _h.py | 193 KB | 10-11 手绘藏品图标批次，图标已提交，只有 _h 被 docs/74 提到 | 问过界面与美术后归档 | 低 |
| motion_preview、op_bright_mockup、texas_bright_mockup | 70 KB | docs/62、已归档的 64 / 69 的样图工具 | 归档 | 低 |
| probes：cam_zoom_probe.py / .gd、cam_zoom_sheet.py（11 KB，docs/112 已结案）；5 个 review_*（33 KB，已交付美术的审稿表）；btrace_patch / btrace_report（7.5 KB）；3 个 mizuki_*（10 KB）；无文档引用的 *_shots / *_rec（约 14 KB） | 约 75 KB | 见左 | 删 | 低 |

- probes 里 `package_*` 是已交付美术的出处（干员 json、docs/108、headhunt.gd 引用），留；驱动 game/tests 场景的 anim_bugs_capture、anim_slide_probe、gem_size_capture、manual_aim_probe 与场景成对，删就成对删（连 .uid）。

## 4. docs/

- **AGENTS / CLAUDE 必读的不动**：00、06、41、36、39、76，以及 AGENTS 点名的 49、87、98、05、33、106。
- 根目录 25 个一行指针（7 KB）**保留**：代码注释还在引这些编号（如 docs/59 被 11 个文件引、docs/84 被 6 个）。`92_codex_angelina_float.md` 指针里多了一段 10-17 的附注，不规范。
- docs/archive 65 个 / 799 KB 都在 archive/README.md 登记；其中 25 个（291 KB，多为 10-13 第一轮归档）代码 / 工具零引用，可移出仓库（git 历史在），但归档规则是「不删除，只归档」，**要用户定**。

| 文档 | 大小 | 证据 | 取代者 | 建议 |
|---|---|---|---|---|
| 112_camera_zoom_brightness | 12 KB | 索引「已结案」，用户 10-22 定 | 文内已记决定 | 归档 + 留指针 |
| 105_op_anim_arch_for_codex | 7 KB | 「已实施记录」；docs/108 第 4 行写冲突以 108 为准，skill_pose 接口已进 87 §3.5 | 108、87 §3.5 | 归档 + 留指针（87、108 在引） |
| plans/2026-10-18-*（10 个）、plans/2026-10-20-*（5 个） | 86 KB | Codex 运行时实施日志；docs/108 已审到 6b697796..7784b32c，**索引里「试验分支，未合入 main」那几行已过期**；7 个没进索引 | 108、61 | 移到 docs/archive/plans/，改索引 |
| superpowers/ 下 spine-editor、summon-visual-alignment ×2 | 5 KB | 代理计划草稿，不在索引 | 107（在做）、spine_editor/README | 107 结束后归档 |
| 71_is3_levels | 31 KB | 「进行中」但 10-12 起暂停，109 §5.3 重定义了潮位阶梯 | 109 §5.3 | 留，状态改「暂缓 / 部分被 109 取代」 |
| 52 EA 反馈问卷、90 codex_toy_cover、43 telemetry_upload、100 store_copy | 24 KB | 「进行中」但 10 天以上没动 | — | 留，问协调人是否还开着 |
| 110、111、127、130（一次性记录 / 审阅），115、121（已实施） | 190 KB | 10-21 至 10-24 的一次性记录 | — | 暂留，之后归档 |

- **没进索引的**（都该补行、都不删）：101a_op_enemy_access（47 KB，101 附录）、102_rename_plan（标题误写成「# 101 ·」）、103_body_templates（87 §4.3 指定必读）、125_ak_ui_study、126_arch_review_1022、128_op_1x_redraw_move_attack（23 个 game 文件在引）、上面的 7 个 plans 与 3 个 superpowers、docs/reference 的 global_design_framework_v1.0.md 与 13 张 png。索引格式：「其他目录」表之后有 5 行计划行和 1 个列表项落在表外；119 与 enemy-identity 两行是列表项不是表格行。
- docs/reference 13 张 png 4.18 MB：被 109 / 116 / 111 引用的保留并补进 reference/README；**`event_timeline_1022.png`（34 KB）无人引用**，删或补引用；`art_audit_ref.png`（210 KB）只被 archive/12 引用；`mizuki_collectibles_adaptation.json`（106 KB）README 说与 docs/08 同步，但 08 已归档作废、relics.json 才是权威——README 标过期、文件留。

## 5. 仓库体积

| 项 | 大小 | 说明 |
|---|---|---|
| .git | **2.9 GB**（pack 2.71 GiB、37 个 pack；松散 55 MiB；垃圾临时对象 12 MiB） | 本地历史，删工作树文件不会变小 |
| 其中 Spine 源 zip（`art/incoming/dn_latest_spine_delivery_1020/*.zip`，最大的 50 个 blob 里 38 个，每个 32–37 MB） | **约 1.25 GB** | 只在 codex/art、codex/headhunt-*、codex/title-* 分支上（0ffd6b20），**不在 origin/main**；记忆「Spine 源文件只留本地」：不合 main、不推远端 |
| Codex 工具引用 `refs/codex/*`（1 个 snapshot + 10 个 turn-diffs） | 约 0.13 GB 可见（`Claude outputs/` 下 bgm / voice wav 44 + 22 + 19 + 9 MB、`4313_CreativeKind 31 in one pack.zip` 31 MB） | 这些文件不在任何分支历史里，是 Codex 快照把工作区未跟踪文件也存了进来 |
| 工作树 art/incoming | 276 MiB（磁盘 295 MB） | 见 §1；删 N + 审稿 92 MiB、再移出源目录 186 MiB |
| build/、.claude/worktrees、.worktrees（不进 git） | 见 §5.1 | 单列 |

**换账号时**：从远端克隆只拿到 main 及推送过的分支，Spine zip 与 refs/codex 都不会跟过去——新环境天然干净。**本机想把 .git 从 2.9 GB 降下来**：删除 Codex 快照引用（`refs/codex/*`）并 `git gc --prune`，可省约 0.13 GB；Spine 源 zip 那 1.25 GB 要么把那几条 codex/* 分支迁到仓库外的存档仓库再删分支，要么接受——**都要用户定**（会影响 Codex 的分支）。

### 5.1 本地不进 git 的目录

10-24 用 robocopy 统计（不含 .git）：**合计约 54.6 GB**。

| 目录 | 大小 | 说明 |
|---|---|---|
| .worktrees/ | 10.97 GB | 旧式工作树目录（Codex 等） |
| build/ | 9.50 GB | 三包、检查日志、截图、TRACE 缓存、PRTS 参照；`tools/clean_local.py` 管其中一部分 |
| .claude/worktrees/（51 个） | 约 34.1 GB | 最大 optimistic-dhawan-7e67e2 6.70 GB；1–2 GB 的 9 个（agent-a15c1f36819d13d7b、suspicious-aryabhata-40115b、confident-hopper-080e16、ecstatic-lichterman-f81c72、interesting-kilby-98da4d、blissful-keller-3f9eaa、jovial-franklin-5e6711、confident-hertz-223da6、quirky-turing-39a39f）；其余 40 个 0.05–0.9 GB（gameplay-*、gem-base、sfxa、agent-* 等临时树） |

建议：已合入分支的工作树用 `git worktree remove` + `git worktree prune` 清（归属会话确认后；在跑的会话的树别动）；build/ 用 clean_local.py。这些都不影响仓库与换账号克隆。

## 6. 删除计划（分三批）

**第一批 · 零风险（不动任何运行时读点，只删无人引用或纯审稿物）**
1. art/incoming 根目录与小目录的审稿产物：preview / gif / qa json / art_review_0926 / compare 类 / html（约 84 MiB），bosses/、v13_qa/、v15_qa/、_trial_icons/、cm_enemy_scale_runtime_1018/、codex_order_headhunt_ref/、codex_order_ui_ref/、ui_shell_1022/、codex_op1x_heads/。
2. 进包的漏网审稿图：`*lineup*` 16 个 + op_fix eye 2 个；同时把 `*lineup*` 加进 REVIEW_ART_GLOBS 与导出预设 exclude_filter。
3. game/：art/px 被覆盖的 44 个、`*_white` 25 个（留 e_chest_white / e_event_white）、mizuki_chibi_walk、game/art/player.png、retreat_fx.gd + retreat_capture 三件、export_presets 里的 player_cut 过滤。
4. balance.json 6 个死键；`mizuki_48_original.png`、`player_48_preview.png`、`docs/reference/event_timeline_1022.png`。
5. tools：b6_* 三件 + fix_nova_cannon；probes 的 cam_zoom ×3、review_* ×5、btrace ×2、mizuki_* ×3、无引用的 *_shots / *_rec。
- 验证：`--auto` + 打一次三包（看包体变小、无缺图报错）。

**第二批 · 需验证（要先改工具或测试、跑一遍再删）**
1. 被遮蔽的 1x 基础帧条 578 个 + optical_fx/ 里遮蔽的 153 个：先改 install_enemy_redraw.py、optical_fx_quant.py 不再产 1x，保留 10 个 Boss 1x；删后跑 `--auto` + 光学开 / 关各截一局。
2. 只登记不播的 31 个特效：抽查拼名后删帧条 + V6_FRAMES 条目 + optical_fx 副本。
3. portraits/ + enemies.json `intro.portrait` 字段 + ART_SUBDIRS。
4. `op_skadi_attack`：eqtest / sstest 改指 v2（积木等价金样要在 main 重录），再删。
5. 旧怪 BASE_TEX 七个小图；`e_carmen*` / `e_iberia*` 先核 enemy_pixels.json 与 world.gd 再删。
6. enemy_redraw_1023/ 只留安装子集（829 个 5.1 MiB），其余约 141 MiB 移出仓库；headhunt_reference_fx_1022/ 移出。删前用安装器从子集重装一遍，比对根目录副本逐字节相同。
7. tools 的 concept_* 组（处理 concept_headhunt 的 import 依赖）、relic_icons_hand_a–h、motion_preview / *_bright_mockup（先问界面与美术）；game/tests 5 个旧录像脚本；docs 的 112、105、plans/ 归档与索引修正。
8. data_lint 补别名与数据文件旋钮的检查。
9. **修 bug**：`move_attack` 加进加载列表（不是删除，单独一个提交，截图确认边跑边打生效）。

**第三批 · 需用户定**
1. 干员 @2x 回退帧条 183 个（9.75 MiB 去掉 31 个立绘用的）：是否还保留 `op_1x=0` 开关。
2. 语音母带 game/audio/voice/masters（20.7 MiB）、voice_batch5 / 6（10.5 MiB）移出仓库存档。
3. docs/archive 里 25 个零引用旧文档移出仓库（与「不删除，只归档」规则冲突）。
4. 本机 .git：删 `refs/codex/*` 快照 + gc（约 0.13 GB）；Spine 源 zip 所在的 codex/* 分支迁出存档（约 1.25 GB）。
5. promo_* 等改名方案相关工具：改名定了再处理。

**可省合计（工作树）**：第一批约 **92 MiB**（其中进包约 1 MiB）；第二批再约 **165 MiB**（进包约 2.7 MiB）；第三批再约 **41 MiB**。本机 .git 另可省 0.13–1.4 GB（第三批 4）；本地工作树 / build 另约 54.6 GB（不进 git，按会话确认清）。
