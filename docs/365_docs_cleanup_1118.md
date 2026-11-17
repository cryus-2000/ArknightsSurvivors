# 365 · docs/ 整理报告（11-18）

用户 11-18：「整理一下一些不在用到的文档，不用的全部删掉，然后再重新整理一下现有的文档。」
分支 `claude/gifted-stonebraker-c702d1`，基线 main `1c4f2e695`。只动文档、代码注释里的文档引用；没改游戏逻辑。

## 0. 结果

| 项 | 数量 |
|---|---|
| 整理前 docs/ 下 .md | 433（含 archive 65、plans 17、superpowers 8、assets 6） |
| 删除 | 85 份（另有 5 份合并后删除、1 份碎片补录后删除） |
| 合并 | 4 组，6 份并入 4 份现行文档 |
| 从 archive 挪回 docs/ 根 | 32 份（仍被代码 / 工具 / README / 美术交接引用）；`docs/archive/` 撤销 |
| 保留（进索引） | 317 份，状态见 [00_index](00_index.md) |
| 待定（不删，等用户 / 协调人定） | 44 份方案稿 + 2 份点名待定（见 §4） |

提交（按批，便于回看）：

| 批 | 提交 | 内容 |
|---|---|---|
| 1 | `cb0fe9f53` | 删除 85 份 |
| 2 | `6f2ecb601` | 撤销 archive，32 份挪回 docs/ 根，路径引用改 docs/ |
| 3 | `4444e8a5d` | 同主题合并 4 组 + 113 碎片补录 |
| 4 | `c96795aca` | 修指向已删文档的引用 |
| 5 | `0b0b48920` | 重建 00_index |
| 6 | 本文所在提交 | 本报告 |

## 1. 判断依据

1. **引用**：全仓库（`game/`、`tools/`、`.claude/skills/`、`AGENTS.md`、`CLAUDE.md`、`README.md`、`art/`、其他文档）按文件名和 `docs/<编号>` 扫描。编号撞号（113、129、142、160、163、199、201、222、246、298、327、335、359，以及 archive 与现行文档同号的 00 / 06 / 21 / 27 / 28 / 38）逐个按文件名复核，不算虚引用。`art/archive/` 里的旧交接不算现行引用。
2. **被代码、工具、技能或入口文件引用的一律不删**（哪怕内容已过时，状态标「记录」或「旧稿（仍被引用）」）。
3. **不能删的**：主题重构 357 / 359 / 364，傀影 358 / 360–363，令美术试点用的 104 / 105 / 108 / 128 / 140 / `plans/2026-10-20-spine-run-trial`，AGENTS.md / CLAUDE.md 必读清单里的 06 / 41 / 36 / 39 / 76 / 49 系列 / 05 / 87 / 98。
4. **删的**：无引用且属于一次性审计 / 巡检 / 整合记录、已落地的实施记录（代码为准）、被后来文档推翻的方案、已交付的 Codex 单、已实施的计划文件、归档旧稿。
5. 拿不准的列进 §4「待定」，不删。

## 2. 删除清单（85 份）

| 文件 | 标题 | 理由 |
|---|---|---|
| `110_op_audit_1021` | 110 干员新美术接入后统一复查（2026-10-21） | 一次性审计（10-21 新美术接入复查），结论已落地 |
| `135_leader_swap` | 129 切换队长（原型） | 原型 10-27 被用户关闭（「Q 直接删掉吧」），开关缺省 0，代码为准 |
| `141_hit_feel_review` | 141 · 打击感偏弱的原因调研（10-24，测试与验收） | 一次性调研（10-24 打击感），只读未改代码；后续由 291 等接手 |
| `148_route_choice` | 148 · 结局走向：替代「海嗣祭坛」的选路方案（10-25；用户最终选翻节点卡，见 docs/15 | 被 154 翻节点卡取代 |
| `149_trim_pocket_dashfollow` | 149 · 小怪前后期微调 + 囊海爬行者三分之一血无敌自爆 + 队友只在队长冲刺时一起冲（10-2 | 已实施记录，数值在 balance.json |
| `163_visible_build_growth_codex` | 163 · 可见成长藏品：七件候选历史草稿 v2 | Codex 历史草稿，已被 163b / 163d 取代 |
| `166_loading_render_audio_1027` | 启动加载、渲染回收与激光混音（2026-10-27） | 已实施记录，无引用 |
| `167_boss_pixel_fx_1027` | 最终 Boss 新增招式：像素材质特效返修（候选） | 用户否定的候选方案 |
| `176_sword_wave_ease` | 170 剑气非线性速度（10-27） | 已实施记录，旋钮 balance.json sword_ease |
| `185_card_text_1028` | 178 卡面受益标签与文案修订（10-28） | 已实施记录（卡面文案），以数据为准 |
| `186_integ_1028b` | 186 整合分支 integ-1028b 冲突处理记录（10-28） | 一次性整合记录 |
| `188_asset_audit_1028` | 188 · 素材命名与目录核对（10-28） | 一次性核对，被 189 规范与后续清理取代 |
| `195_op_fx_audit_1029` | 191 · 干员特效审查（10-29） | 一次性审查记录 |
| `19_four_endings` | 19 · 四结局总体方案（已实施：09-24 落地，见 `game/scripts/endings. | 已实施记录；结局入口已被 154 取代，现行以 endings.gd / waves.json 为准 |
| `253_late_game_research` | 253 同类游戏的后期画面可读性调研（11-04） | 一次性调研，结论已进 247 / 251 / 293 |
| `281_asset_inventory_1106` | 281 · 素材引用清扫与归档清单（11-06） | 一次性素材清扫记录 |
| `300_suzuran_heal_1107` | 300 铃兰回血砍一刀（11-07） | 已实施（数值在 suzuran.json） |
| `303_ult_dmg_1107` | 303 终结技伤害现状与上调（11-07） | 已实施记录 |
| `316_ult_link_names_1107` | 316 · 终结技 / 连携技改名方案（11-07） | 定稿名字已进游戏数据 |
| `329_chibi_codex_order_1108` | 329 干员 Q 版像素小人美术单（Codex，11-08） | Codex 单已交付接入 |
| `330_mobile_frame_followup_1107` | 313 · 手机网页后期帧时：接 Codex 继续（11-07，帧率会话，分支 claude/mob | 一次性帧时排查记录 |
| `334_music_loop_1112` | 334 配乐循环验收（11-12） | 一次性验收记录（有 music_loop 快检） |
| `338_vreview_carbon_cmp_1112` | vreview 模型对比：gemini-3-flash-preview vs gemini-4-ca | 一次性模型对比，结论「缺省不换」 |
| `351_boss_targeting_audit_1117` | 351 选敌排查：干员不打 Boss（11-17） | 已实施记录（选敌排查），代码为准 |
| `52_EA反馈问卷` | 《方舟幸存者》EA 1.1 · 试玩反馈问卷 | EA 1.1 问卷，已过期 |
| `27_batch2_art_brief` | > **已归档（2026-10-14）**：第二批干员美术指令（给 Codex） → [docs/a | 指向已删归档的一行指针 |
| `28_gamepad` | > **已归档（2026-10-14）**：手柄适配 → [docs/archive/28_game | 指向已删归档的一行指针 |
| `51_1.1_更新日志` | > **已归档（2026-10-14）**：1.1 更新日志 → [docs/archive/51_ | 指向已删归档的一行指针 |
| `85_codex_run_rework_1013` | > **已归档（2026-10-14）**：Codex 返修单：五个跑步循环 → [docs/arc | 指向已删归档的一行指针 |
| `86_codex_idle_pose_1013` | > **已归档（2026-10-14）**：Codex 返修单：艾雅法拉 / 铃兰待机侧身 → [d | 指向已删归档的一行指针 |
| `plans/2026-10-18-doctor-style-integration` | 博士统一画风接入（2026-10-18） | 已实施计划，无引用 |
| `plans/2026-10-18-enemy-identity` | 怪物原作机制补齐（用户已确认检查清单） | 已实施计划，无引用 |
| `plans/2026-10-18-mizuki-runtime-standardization` | Mizuki runtime standardization and animation repai | 已实施计划，无引用 |
| `plans/2026-10-18-mizuki-s3-fx` | 水月 S3 原作方向与整范围触手试版 | 已实施计划，无引用 |
| `plans/2026-10-18-sustained-attack-module-design` | 持续攻击阶段模块设计（用户已确认） | 已实施计划，无引用 |
| `plans/2026-10-18-sustained-attack-module-implementation` | 持续攻击阶段模块实施计划 | 已实施计划，无引用 |
| `plans/2026-10-18-three-operator-capability-audit` | 三干员能力归属与生命周期审计 | 已实施计划，无引用 |
| `plans/2026-10-18-three-operator-standardization-design` | 三干员完整标准化方案（已实现并通过验收） | 已实施计划，无引用 |
| `plans/2026-10-18-three-operator-standardization-implementation` | Three-operator standardization implementation plan | 已实施计划，无引用 |
| `plans/2026-10-18-wisadel-s2-two-phase` | 维什戴尔 S2 两阶段群攻试做（2026-10-18） | 已实施计划，无引用 |
| `plans/2026-10-20-eyja-volcanic-weight` | 艾雅法拉熔岩弹与火山弹重量返修 | 已实施计划，无引用 |
| `plans/2026-10-20-siege-ulpianus-native-integration` | 推进之王、乌尔比安测试版接入 | 已实施计划，无引用 |
| `plans/2026-10-20-ulpianus-fracture` | 乌尔比安裂地加强 | 已实施计划，无引用 |
| `plans/2026-10-20-ulpianus-impact-doctor` | 乌尔比安落地特效与博士新版接入 | 已实施计划，无引用 |
| `superpowers/plans/2026-10-20-spine-editor` | Native Spine pose editor | 实施计划草稿，无引用 |
| `superpowers/plans/2026-10-20-summon-visual-alignment` | Summon Visual Alignment Implementation Plan | 实施计划草稿，无引用 |
| `superpowers/plans/2026-10-22-operator-voice` | Operator voice implementation plan | 实施计划草稿，无引用 |
| `superpowers/plans/2026-10-27-boss-fx-rework` | Final Boss pixel-material VFX rework | 实施计划草稿，无引用 |
| `superpowers/plans/2026-10-27-final-boss-complete` | Final Boss completion implementation plan | 实施计划草稿，无引用 |
| `superpowers/plans/2026-10-27-loading-performance-audio` | Loading, performance and laser mix implementation  | 实施计划草稿，无引用 |
| `superpowers/plans/2026-11-06-mobile-performance` | Mobile performance implementation plan | 实施计划草稿，无引用 |
| `superpowers/specs/2026-10-20-summon-visual-alignment` | Summon visual alignment | 实施计划草稿，无引用 |
| `archive/00_game_design` | 00 · 游戏设计总览 | 归档旧稿，无现行引用 |
| `archive/03_sprite_spec` | 03 · 主角像素小人规格（给画师） | 归档旧稿，无现行引用 |
| `archive/04_skill_relic_design` | 04 · 水月技能与藏品设计（草案 v1） | 归档旧稿，无现行引用 |
| `archive/06_v05_plan` | 06 · v0.5 计划：宝箱与金钱、藏品重做、海嗣重做 | 归档旧稿，无现行引用 |
| `archive/07_boss_art_handoff` | Boss 首轮美术交接（2026-09-24） | 归档旧稿，无现行引用 |
| `archive/12_art_audit` | 12 · 美术表现体检与提升清单（讨论稿） | 归档旧稿，无现行引用 |
| `archive/12_boss_attack_design` | 12 · Boss 攻击与技能设计（v1.3） | 归档旧稿，无现行引用 |
| `archive/13_balance_v14` | 13 · v1.4 平衡重做与架构第一步 | 归档旧稿，无现行引用 |
| `archive/14_refactor_plan` | 14 · 架构重构：角色 / 地图 / 藏品 / 敌人可扩展化 | 归档旧稿，无现行引用 |
| `archive/14_relic_unify` | 14 · 藏品系统合一（v1.5） | 归档旧稿，无现行引用 |
| `archive/15_v16_changes` | 15 · v1.6：伤害类型、威胁等级、新海嗣、藏品等级、巨触横扫 | 归档旧稿，无现行引用 |
| `archive/16_build_design_summary` | 16 · 水月 Build 设计现状总结（v1.7.2，供讨论） | 归档旧稿，无现行引用 |
| `archive/21_balance_routes` | 21 · 四条精英化路线的强度核对（2026-09-25） | 归档旧稿，无现行引用 |
| `archive/27_batch2_art_brief` | 27 · 第二批干员美术指令（给 Codex） | 归档旧稿，无现行引用 |
| `archive/28_gamepad` | 28 · 手柄适配 | 归档旧稿，无现行引用 |
| `archive/32_art_review_0926_handoff` | 编队人物返修交接 · 2026-09-26 | 归档旧稿，无现行引用 |
| `archive/34_growth_art_requests` | 34 · 可见成长线的美术清单 + 给 Codex 的需求单 | 归档旧稿，无现行引用 |
| `archive/47_horde_mix_v8_enemies` | 47 大群混编与 V8 新敌人（EA 1.1） | 归档旧稿，无现行引用 |
| `archive/51_1.1_更新日志` | 《方舟幸存者》1.1 更新日志 | 归档旧稿，无现行引用 |
| `archive/75_copy_audit` | 75 游戏内文案「AI 味」排查（只审计，不改文件） | 归档旧稿，无现行引用 |
| `archive/78_melee_share` | 78 近战伤害占比与「抢怪」审计（10-12） | 归档旧稿，无现行引用 |
| `archive/85_codex_run_rework_1013` | 85 · Codex 返修单：五个跑步循环（2026-10-13） | 归档旧稿，无现行引用 |
| `archive/86_codex_idle_pose_1013` | 86 · Codex 返修单：艾雅法拉、铃兰待机改为朝右侧身（2026-10-13） | 归档旧稿，无现行引用 |
| `archive/README` | docs/archive · 归档文档索引 | archive 目录撤销 |
| `archive/balance_pass_20260928` | 2026-09-28 藏品与生存资源调整 | 归档旧稿，无现行引用 |
| `archive/boss_mechanics_20260928` | Boss 机制与特效交接（2026-09-28） | 归档旧稿，无现行引用 |
| `archive/ea_boss_variety_20260927` | Boss 招式与密集弹幕（2026-09-27） | 归档旧稿，无现行引用 |
| `archive/ea_economy_20260927` | EA 经济、成长与交互物位置调整（2026-09-27） | 归档旧稿，无现行引用 |
| `archive/ea_iteration_20260927` | EA 试玩改进交接（2026-09-27） | 归档旧稿，无现行引用 |
| `archive/enemy_attack_variety_20260928` | 敌人与 Boss 攻击丰富化（2026-09-28） | 归档旧稿，无现行引用 |
| `archive/enemy_attacks_20260928` | 普通怪与精英攻击调整（2026-09-28） | 归档旧稿，无现行引用 |
| `archive/enemy_status_20260928` | 定向冰霜与侵蚀补强（2026-09-28） | 归档旧稿，无现行引用 |
| `archive/relic_reclassification_20260928` | 133 件实装藏品：效果二次分类与强度复核（2026-09-28） | 归档旧稿，无现行引用 |

## 3. 合并（4 组）+ 碎片补录

| 现行文档 | 并入 | 说明 |
|---|---|---|
| [285_web_shrink_1106](285_web_shrink_1106.md)（网页包体） | 187_web_shrink_1028（10-28 再压缩评估）、295_toy_trim_audit_1107（Toy 包白占盘点） | 285 正文是 11-06 拆账与方案，187 / 295 原文为附录 A / B。`tools/export_web.py`、`web_audio.py`、`release_slim.py`、`test_web_lzma.py`、`tools/web/loader.js`、`lzma_dec.js` 注释里的 docs/187、docs/295 改成「docs/285（原 187 / 295）」 |
| [142b_boss_axis](142b_boss_axis.md)（Boss 分幕，方案 B） | 142_boss_phases（方案 A） | 142b §8 本来就合并了 A 的新弹幕；原 142 为附录 A。`.claude/skills/new-enemy/SKILL.md`、`render/boss_beam.gd`、`tools/probes/boss_phase_sheets.py` 的引用已改 |
| [165_final_boss_complete_1027](165_final_boss_complete_1027.md)（最终 Boss） | 168_boss_volume_tracking_1027（材质 / 泡影追踪返修） | 原 168 为附录 A；167（被否候选）直接删 |
| [173_ishar_combos_1027](173_ishar_combos_1027.md)（伊莎玛拉） | 173b_ishar_acts_plan（三幕一页方案，标题号 170b） | 原 173b 为附录 A；`ishar_combos.gd`、`ishar_combo_test.gd`、`ishar_p2_test.gd` 注释里的 docs/170b 改指 docs/173 |
| [113_sfx_audit](113_sfx_audit.md) §19.x | `113_exusiai*.md`（文件名带不可见字符的 7 行碎片） | 能天使 10-27 定稿「原作 Q + 闷响」补录到 §19 后 |

没有合并、但考虑过的：

- 英文本地化 276 / 277 / 278：277、278 是 `tools/l10n/preview.py`、`overflow_check.py --md` 的输出文件，合并会让工具重写回原路径，所以保留，状态标「工具输出」。
- 后期可读性 247 / 251、转平面各干员页 254–274：各自被十几个渲染脚本按编号引用，合并要改大量 `render/` 注释，而主循环 / 渲染正有别的会话在改，暂不动。
- 构筑 163 / 163b / 163c / 163d：代码注释直接写「163B §3」「docs/163D」，保留四份；只删了被取代的 163_visible_build_growth_codex。

### 3.1 从 archive 挪回 docs/ 根（32 份，状态「旧稿（仍被引用）」）

01_brainstorm、02_roadmap（README）；08、10、13_art_v7_spec、24、30、42、45、46、48、49f、49g、59、64、65、66、72、84、92、ea_ishar_20260927（代码注释）；44、63、68、69、73（tools）；20、32_art_review_0926_acceptance、32_squad_art_review、38_boss_p1_art_handoff、38_boss_p1_art_acceptance、70（代码注释或 art/incoming、art/requests 交接文件）。原位的一行指针文件一并替换掉。

## 4. 待定（保留，不删）

点名待定：

| 文档 | 为什么拿不准 |
|---|---|
| [132_handoff_1024](132_handoff_1024.md) | 换账号交接手册，10-30 后没更新，内容已被 41 + 本索引覆盖；但 memory「交接手册」还指向它。建议删或改成一页指针，请协调人 / 用户定 |
| [282_bond_non_numeric](282_bond_non_numeric.md) | 11-06 羁绊玩法差异设计稿，没审没做，无引用；不知道还要不要 |

方案稿（状态「待定（方案待审）」，44 份）：55、101、43、71、116、146、179、181、196、197、200、203、248、249、250、252、335_balance_check、107、118、280、304、310、plans/2026-10-29-mon3tr-hp-plan、117、145、283、156、124、125、222_hud_redesign、284、315、328、337、243、245、246_pxplane_skadi、291、293、205、339、340，以及上面两份。其中不少其实已部分落地（例如 249 开关、310 修了一批），只是文档状态没人回写；建议各角色会话认领自己的那几份，落地的改「记录」，否掉的删。

## 5. 引用修改

| 改了什么 | 位置 |
|---|---|
| `docs/archive/<文件>` → `docs/<文件>` | README.md（01 / 02 两处 + 目录树）、`render/world.gd` 一处注释、102 / 131 / 13 / 23 / 35 / 38 / 49b / 57 / 68 / 72 / 91 / 93 / 98 等文档内链接 |
| 合并文档的旧编号 → 「docs/<新>（原 <旧>）」 | 见 §3 |
| 指向已删文档的链接 → 纯文字 +「（已删）」；`docs/<编号>` → 加「（已删）」 | 35 份文档：05、09、13、150、154、163d、164、165、184、189、18、193、305、332、337、339、356、35、36、38、41、49、49a、49b、49c、55、56、57、61、72、76、87、95、98、mobile_performance_1106 |
| 笔误订正 | `tools/ult_inventory.py`、`ult_inventory_sheet.py` 文件头把 docs/280 写成 docs/278 |
| 坏链接 | 163c 指向底表 JSON 的链接（`163_relic_inventory.json` → `163c_relic_inventory_codex.json`） |

**没改的**：

- `AGENTS.md` 第 5 行的归档说明：用户 11-18 直接确认后单独提交 `cc108d392` 改成「没有归档目录，作废直接删，合并写来源，仍被引用的旧稿标旧稿」。CLAUDE.md 不涉及，没改。
- `art/incoming/ult_batch1_1029/alignment_audit.md` 写 `docs/archive/70`（现在是 `docs/70_codex_fx_texas_rain.md`）：Codex 交付文件，不改。
- `art/archive/incoming_1028/*` 里的旧交接文件引用旧编号：归档美术，不改。

## 6. 待核

### 6.1 指向从未进 main 的文档编号

全仓库扫 `docs/<编号>`，这些编号在 main 上从来没有对应文件（多半在别的分支上写过、没合入，或撞号后改了号）：

| 编号 | 引用处（举例） | 猜测 |
|---|---|---|
| 198 | 40 处：`.claude/skills/new-operator/SKILL.md`、`templates/design_template.md`、199_ult_proto、202、`tools/check_map.json` 等 | 终结技 / 连携设计稿 docs/198 在 `claude/ultimate-design` 分支，一直没合 main（41 §4.6「故意不合」） |
| 242 | 24 处：245 文档、`tools/pixelfx_fx/logos_ul_ref/*.js` 等 | pixelfx「放开版」方案（memory 记作 docs/242），没进 main |
| 208 | 12 处：211、249、`characters/character.gd`、`squad.gd` | 未知 |
| 207 | `art.gd`、`run/ult_fx_c.gd` | 未知（终结技特效相关） |
| 236 | `enemies/shot_pool.gd`、`render/bullet_fx.gd` | 未知 |
| 134 | 67、`settings.gd` | 未知 |
| 210 | 209 | 未知 |
| 81 | 36 | 未知 |
| 342 | `tools/perf_web.py` | 未知 |

这些是整理前就有的悬空引用，本次没改。

### 6.2 指向仓库外的图

- 331、335_balance_check 里的 `../Claude outputs/...png`：图在仓库外，链接在仓库里打不开。
- 184 引用 `reference/184_event_redesign.png`，仓库里只有 `reference/173_event_redesign.png`（184 由 173 改号而来，可能是同一张图，未确认，没改）。

### 6.3 内容与代码不符

本次没有逐篇核对内容。旧索引里已标的过时段落（06 两句、22 部署节、23 多节、26 技能表、29 §3、76 §6、98 §8、99 §0 等）照旧写在新索引的「说明」列里。

## 7. 快检

- 文档链接：全部 `docs/**/*.md`、README、`.claude/**/*.md` 的相对链接扫描，除 §6.2 外无坏链接。
- `check.py --only check_map`：通过（169 个场景回归全部归组）。
- `check.py --only core`：通过（7776 checks，0 failed）。
- `check.py --only text_reconcile`：通过（613 个数字已解释 89%，待核基线 67 条，与整理前相同）。
- `check.py --only graph_lint`：第一次 3 条硬命中（拉普兰德 / 维什戴尔 3 张移动攻击帧条在 art 索引里找不到）——是本地生成的 `game/art/index.json` 落后（docs/364 记过），与文档无关；`python tools/asset_index.py` 重建本地索引后通过。`game/art/index.json` 没提交。
- 没有别的快检读 docs/ 的内容（`check_map.json` 里 `docs/**` 不触发任何测试组）。
