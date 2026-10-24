# 00 · 文档索引

> 2026-10-14 整理（用户：「docs 也需要进行进一步的整理」）。每篇一行：编号、标题、状态、一句话说明、被谁引用。
> 状态：**现行规范**（现在仍要遵守）／**已实施记录**（已落地，留作记录或参考；代码注释可能还按节引用）／**进行中**（未全部实施或仍在追加）／**作废**。
> 「被谁引用」是 2026-10-14 扫描 docs/、AGENTS.md、CLAUDE.md、game/、tools/、art/ 的结果：数字是 docs 编号，其后是代码 / 数据文件。
> 已归档的文档在 `docs/archive/`，原位置留一行指针，所以按编号的旧引用仍能找到。归档不删内容；第一轮（10-13）的归档清单见 `docs/archive/README.md`。
> 新增文档：在对应分组加一行；文档过时或作废时改这里的状态，作废的整篇挪进 archive/ 并在原位留指针。

## 新会话先读

| 谁 | 先读 |
|---|---|
| 全部会话 | 本索引 → 06 → 41 §1–§3 → 36 §1–§3（含 §1.1）与 §7.5.1 → 39 → 76 |
| 干员 | 61 → 26 文首 → 23 文首与 §1、§3、§5、§6、§10 → 91 §0.5；改数值前加 79、80 |
| Boss与怪物 | 95 → 38 §1、§8.11–§8.14 → 49 / 49c → 98 |
| 数值 / 藏品 | 80 → 27 §2、§3、§9 → 83 → 35 → 74 |
| 界面与美术 | 37 → 98 → 87（干员帧条）→ 62 §2 → 76 |
| 音频 | 21 → 53 → 28_operator_sfx → 113_sfx_audit |
| 部署 | 33 → 22 → 89 / 99（B站 Toy） |
| 文案 | 76 → 49 / 49a |

同一件事两篇文档说法不同时，先看下面各行「说明」里写的「以 xx 为准」；还没定的冲突由协调人裁定（2026-10-14 冲突表已交协调人）。

## 规范（所有会话遵守）

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [06_git_collaboration](06_git_collaboration.md) | Git 协作与美术分工 | 现行规范 | Codex / Claude 分工、交接与合入；「Claude 在主工作区」「没有远程」两句已过时，以 41 §3 为准 | 38、41、54、91、99、归档24 等 12 篇；v14_codex_fx_props.md、skalter_s3_handoff.md、AGENTS.md 等 4 个文件 |
| [41_agent_team](41_agent_team.md) | 多会话协作 | 现行规范 | 协调人与工作会话、消息标签、分工表、工作树规则；§4.6 是历史待派队列 | 36、53、55、57、归档42、归档44 等 8 篇；run/combat.gd、tools/fix_nova_cannon.py、AGENTS.md |
| [76_language_style](76_language_style.md) | 语言风格（约束） | 现行规范 | 全部玩家可见文字的口径与术语表；§6 生命倍率已过时 | 77、82、83、88、91、95 等 8 篇；data/lore.json、cloud_save.gd、run/run_stats.gd 等 6 个文件 |
| [39_code_architecture](39_code_architecture.md) | 代码结构与界面分层 | 现行规范 | 分层、界面层、op_api、画法缓存；§1 未收 bosses/、云存档、g.mode | 38、40、41、43、50、55；game.gd、enemies/bosses/boss_base.gd、run/spawner.gd 等 10 个文件 |
| [37_ui_style](37_ui_style.md) | 界面风格「潮汐航线」 | 现行规范 | 颜色、组件、各画面规则，§8 T5s；术语以 76 为准 | 22、35、39、41、49、49e 等 11 篇；title.gd、ui.gd、run/affects.gd 等 17 个文件 |
| [62_ui_motion](62_ui_motion.md) | 界面动效系统 | 进行中 | §2 共用规则现行；部分界面的招牌动效未做；§3.1 / §3.3 被 T5s 取代 | 36、41、58、67、71、77 等 7 篇；tools/concept_title_ui.py、gallery.gd、game.gd 等 17 个文件 |
| [98_sprite_standard](98_sprite_standard.md) | 角色与怪物立绘标准 v2 | 现行规范 | 像素密度、同屏比例、敌我配色、特效归属（跨类别以本文为准）；§8 待办已过时 | 87、94、97；op_fix_a_manifest.json、op_fix_b_eye_manifest.json、op_fix_b_manifest.json 等 6 个文件 |
| [87_art_spec](87_art_spec.md) | 人物帧条统一规格 | 现行规范 | 干员帧条细则与 art_lint 机检；附录 C 记旧条款去向 | 05、91、93、94、95、97 等 17 篇；tools/art_lint.py、tools/check.py、ally_rework_1014_art_lint.json 等 15 个文件 |
| [05_art_handoff](05_art_handoff.md) | 美术交接说明 | 现行规范 | 文件存放、命名、旧特效帧数；人物尺寸（主角 / 海嗣节）已作废，见 87、98 | 87、归档15；game.gd、tools/make_skill_icons.py、incoming/README.md 等 4 个文件 |
| [11_relic_icon_spec](11_relic_icon_spec.md) | 藏品图标规范 | 现行规范 | 32×32 藏品图标画法、稀有度、命名；§1 HUD 尺寸以代码为准 | 归档34；tools/gen_relic_icons.py、art.gd、tools/gen_fx_strips.py 等 4 个文件 |
| [21_music_design](21_music_design.md) | 配乐与音效 | 现行规范 | 曲目、强度、音效约定与混音；混音优先级以 sfx.gd / 53 §5 为准 | 41、99；sfx.gd、run/music_director.gd、title.gd 等 5 个文件 |
| [49_原作参考](49_原作参考.md) | 原作参考总览 | 现行规范 | 借用原作机制、数值、名字前必查（AGENTS 指定）；索引 49a–d | 62、归档59；enemies/bosses/izumik.gd、AGENTS.md |
| [49a_集成战略](49a_集成战略.md) | 原作集成战略参考 | 现行规范 | 原作肉鸽名词与机制；§5「本作与原作相反」已过时（结局已对调） | 37、60、71、74、归档75 |
| [49b_战斗机制](49b_战斗机制.md) | 原作战斗机制参考 | 现行规范 | 职业分支、异常状态、元素损伤、敌人机制 | 38、60；run/combat.gd |
| [49c_Boss原作](49c_Boss原作.md) | Boss 原作对照 | 现行规范 | 水月 Boss 原作资料；伊祖米克层号与 49a 不一致，待核（49 §7） | 49d、95 |
| [49d_类幸存者Boss](49d_类幸存者Boss.md) | 类幸存者 Boss 设计参考 | 现行规范 | 同类游戏 Boss 设计参考；灯标、招式令牌等建议已实施 | 38、95、归档49f；run/combat.gd、boss_ai.gd、game.gd 等 7 个文件 |

## 系统设计

- [119_build_progression_plan](119_build_progression_plan.md)：待实施方案；基于 e1da3da9 核对升级、招募、六节点与藏品系统，两干员成长分支、有限候选引导、首商人预告及前期压力切片；含 Claude 分阶段实施与验收，尚未改游戏。

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [09_p0_architecture](09_p0_architecture.md) | P0 底层架构 | 已实施记录 | core/ 的 Event / Modifier / Stat / Tag 与效果数据格式；§6 迁移未做 | 17、55、归档14；core/combat_core.gd、core/stat_defs.gd |
| [17_combat_contract](17_combat_contract.md) | 战斗契约 v1.8 | 现行规范 | 伤害描述符、能力标签仍是现状；§2 / §4 / §5 已作废，见 23 §4.2、26、61 | 23、49b |
| [18_ending2_knight](18_ending2_knight.md) | 结局二「最后的骑士」 | 现行规范 | §1 骑士同伴 → 9:00 入潮 → 10:00 中心重生；§2 / §3 数值以 knight.gd、95 §4 为准 | 19、95；game.gd、allies/knight.gd |
| [19_four_endings](19_four_endings.md) | 四结局方案 | 已实施记录 | 事件箱与四结局的唯一规格；标题「未实现」不实，结局 Boss 09-29 已对调（以 waves.json 为准） | 38、49、49a、49c；endings.gd |
| [22_mobile_web](22_mobile_web.md) | 移动端适配（网页） | 现行规范 | 触屏、缩放、超宽、iOS；部署与加载器两节已作废，见 33 | 33、38、41、62、89；tools/export_web.py |
| [35_relic_lanes](35_relic_lanes.md) | 藏品流派 A–H | 现行规范 | 流派划分、职业门槛、流派加权；部分数值已被 65 §6 改（以 relic_effects.json 为准） | 27、29、36、38、41、57 等 7 篇；relic_fx.gd、characters/character.gd、run/combat.gd 等 15 个文件 |
| [40_run_telemetry](40_run_telemetry.md) | 局内数据记录 | 现行规范 | runs.jsonl 格式，按包类型决定写不写 | 33、41、43、89、归档59；game.gd、run/telemetry.gd、settings.gd 等 11 个文件 |
| [43_telemetry_upload](43_telemetry_upload.md) | 局内数据上报接口 | 进行中 | 草案，暂缓（储备方案） | 40、71、归档68；run/telemetry.gd |
| [49e_奶位分类](49e_奶位分类.md) | 奶位分类 | 已实施记录 | 「净化 / 回复」标签口径 C + 塞雷娅净化（唯一成文处） | 41、60；run/affects.gd、tests/prot_test.gd、saria_legacy.gd |
| [53_hit_feel](53_hit_feel.md) | 打击感与音效一轮 | 已实施记录 | fx 打击感旋钮说明的唯一出处；§6 遗留项未结 | 41、50、54、55；sfx.gd、render/vfx.gd、run/combat.gd 等 8 个文件 |
| [54_vfx_pass](54_vfx_pass.md) | 画面特效二轮 | 已实施记录 | 环境与事件特效 8 项；world.gd / vfx.gd 按节引用 | 41；render/world.gd、render/vfx.gd、run/autotest.gd 等 10 个文件 |
| [56_beacon_approach](56_beacon_approach.md) | 引航灯标「去不去」 | 已实施记录 | 现行灯标规则汇总（§1）与旋钮语义；「圈内安全」见归档 49g | 38、41、57、61；run/beacon.gd、render/world.gd、tests/prot_test.gd 等 10 个文件 |
| [57_relics_impl](57_relics_impl.md) | 129 件藏品实装 | 已实施记录 | 逐件读法与新池难度；§2 部分数值以 65 / relic_effects.json 为准 | 35、41、60、归档59、归档65；relic_fx.gd、core/stat_defs.gd、run/combat.gd 等 18 个文件 |
| [58_operator_ui_concept](58_operator_ui_concept.md) | 选人 / 图鉴界面 | 已实施记录 | §11 是 B+ / C4′ 定稿细则（代码引用）；其余为概念稿 | 37、41、62、67；title.gd、tools/concept_operator_ui.py、gallery.gd 等 9 个文件 |
| [67_title_redesign_concept](67_title_redesign_concept.md) | 标题页改版 | 已实施记录 | §12 T5s 已实装（规则进 37 §8）；§1–§11 为概念；设置 / 致谢二期未做 | 37、62、71、归档68；title.gd、title_menu_input_test.gd、screens/title_tiles.gd 等 14 个文件 |
| [71_is3_levels](71_is3_levels.md) | 潮位阶梯 | 进行中 | 16 级逐级难度方案；用户 10-12 定暂缓，等局外成长一起做 | 109、归档68；tools/concept_is3_levels.py |
| [109_meta_progression](109_meta_progression.md) | 局外成长 | 进行中 | v3（10-22 用户拍板）：潮位系数封顶 ×1.5、评分 ÷ 8；认知塑造 560（删钥匙、攻击改对精英 / Boss、生命去末档）；满点溢出核查（入队回复 0.9 → 0.6）；干员解锁（开局 4 人 + 寻访凭证 / 招募券 / 人事调度函 + 意向保底 + 临时招募）；4–6 小时时间线；待定建议清单 | 71、116、111 |
| [74_relic_late_value_and_lifesteal](74_relic_late_value_and_lifesteal.md) | 藏品后期价值 + 吸血 | 已实施记录 | 熔铸规则与「藏品不设上限」的唯一成文处；§7 第 3 条、L3 未做 | 50、57；relic_fx.gd、run/pickups.gd、tests/relic_impl_test.gd 等 11 个文件 |
| [77_run_stats](77_run_stats.md) | 作战记录 | 现行规范 | 局终统计界面与计数口径 | 37、62、79；run/combat.gd、game.gd、run/telemetry.gd 等 15 个文件 |
| [82_sustain_gap](82_sustain_gap.md) | 无医疗编队暴毙诊断 | 已实施记录 | §1 遥测字段（dsrc / hsrc / curve_tail）说明；§3.1 已作废，见 83 | 83、88；data/balance.json、run/telemetry.gd、run/combat.gd 等 4 个文件 |
| [83_squad_sustain_and_dash](83_squad_sustain_and_dash.md) | 入队回复台阶 + 冲刺卡 | 现行规范 | 入队回复、生存 / 机动 / 协同卡、硬化方案 B、中途换人 | 36、82、88；data/balance.json、run/combat.gd、game.gd 等 14 个文件 |
| [88_medic_gap](88_medic_gap.md) | 医疗差距 | 已实施记录 | 方案 A + B 部分已定档（28e28118），文中数值还是定档前的；§7 opbase 旋钮 | run/combat.gd、lumen_legacy.gd、run/telemetry.gd 等 11 个文件 |
| [89_toy_cloud_save](89_toy_cloud_save.md) | B站 Toy 云存档 | 现行规范 | 同步、合并、版本兼容 | 99；settings.gd、settings_panel.gd、core/cloud_pack.gd 等 10 个文件 |

## 干员

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [61_operator_blocks](61_operator_blocks.md) | 干员积木规格 | 现行规范 | 数据驱动干员的唯一规格，18 人已数据化 | 25、36、41、91、93、归档59 等 9 篇；characters/op_blocks.gd、characters/data_operator.gd、tests/test_core.gd 等 57 个文件 |
| [26_operator_skills](26_operator_skills.md) | 三技能契约 v2.5 | 现行规范 | 只看文首契约（普攻 + 3 技能 + 天赋、手动技能 / 普攻）；技能表已过时，以 JSON + 61 为准 | 17、23、27、38、41、49b 等 11 篇；settings.gd、characters/character.gd、characters/doctor.gd 等 10 个文件 |
| [23_squad_design](23_squad_design.md) | 编队制设计 v0.7 | 现行规范 | 队长 / 博士 / 编队模型、作用域、属性公式；§4.2、§6、§7、§8、§9.4、§11.2 已作废 | 17、26、27、38、49a、49b 等 11 篇；characters/character.gd、game.gd、title.gd 等 29 个文件 |
| [91_elite_forms](91_elite_forms.md) | 精英化攻击形态 | 现行规范 | §0.5 规则 + 18 人精一 / 精二形态（已全部实现） | 61、76、93；characters/op_blocks.gd、tools/check.py、game.gd 等 18 个文件 |
| [60_skill_tag_catalog](60_skill_tag_catalog.md) | 原作词汇表 → 积木 | 现行规范 | 积木命名口径（与 61 不一致时以 60 为准），新干员的菜单 | 41、61、归档59；characters/op_blocks.gd |
| [79_op_dummy_table](79_op_dummy_table.md) | 干员木桩表 | 现行规范 | 理论预算口径与工具 | 36、91、归档72；tools/op_dummy_table.py、game.gd、tests/op_dummy_test.gd 等 4 个文件 |
| [25_operator_fx](25_operator_fx.md) | 干员特效 | 现行规范 | 成长「看得见」规则、帧条锚点、能天使弹药色；§5.2 精二列被 91 取代 | 23、53、61、归档34、归档66、归档70；characters/character.gd、game.gd、characters/op_blocks.gd 等 23 个文件 |
| [28_operator_sfx](28_operator_sfx.md) | 干员专属音效 | 已实施记录 | 13 人 op_* 音色与 OP_SFX 约定；「加新干员」一节作废（新干员走 OP_ALT，见 61） | — |
| [113_sfx_audit](113_sfx_audit.md) | 干员音效盘点与调整 | 进行中 | 10-21：18 人普攻 / 命中 / 技能音效的文件、响度、触发频率总表；问题清单；已调 OP_DB / OP_GAP / OP_PVAR / VOICE_CAP；枪击、锁链替换候选待用户试听；§7 网上 CC0 素材候选清单；§8 已接入 8 个文件（能天使、乌尔比安、德克萨斯、星熊）；§10 乌尔比安锁链 v2 三候选；§11 用户定 C 已接入 | 28、53；sfx.gd、tools/gen_sfx_candidates.py |
| [31_arknights_reference](31_arknights_reference.md) | 原作技能对照（13 人） | 已实施记录 | 原作技能与档案摘录；总览差距表已过时 | 25、60、归档30；v17_codex_logos_glyphs.md |
| [维什戴尔 S2 两阶段试做](plans/2026-10-18-wisadel-s2-two-phase.md) | S2 群攻与过载四连发 | 已实施记录 | 8 秒试做、无三人上限、原生八轨动作与炮口事件；已交本地测试包 | wisadel.json、seg_wisadel.gd |
| [持续攻击阶段模块](plans/2026-10-18-sustained-attack-module-design.md) | 通用阶段、连发与收势 | 已实施记录 | 维什戴尔已迁移；独立夹具 66 项、完整快检 80 项通过 | data_operator、attack_phases、docs/61 |
| [三干员完整标准化](plans/2026-10-18-three-operator-standardization-design.md) | 维什戴尔、塞雷娅、铃兰生命周期 | 已实现记录 | 九技能统一查询、归属、结束与取消；81 项检查通过，保留角色效果 | data_operator、skill_lifecycle、docs/61 |

## 敌人与 Boss

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [95_boss_moves](95_boss_moves.md) | Boss 招式改版 | 进行中 | 每 Boss 4 招；第 1、2 批已合入（§15、§16），第 3 批（接潮组）与 Boss @2x 补单待做；Boss 招式以本文为准 | 36、38、98；boss_ai.gd、render/world.gd、tests/boss_variety_test.gd 等 20 个文件 |
| [38_boss_redesign](38_boss_redesign.md) | Boss 重做 v3 | 现行规范 | §1 框架、§8.11 预警、§8.12 难度目标、§8.14 停刷仍有效；已改版 Boss 的招式（第 1、2 批：泡影、伊莎玛拉、伊祖米克、骑士、塑路者、两位圣徒）以 95 为准，接潮组暂按本文 | 21、27、36、37、40、41 等 23 篇；run/combat.gd、boss_ai.gd、tests/prot_test.gd 等 38 个文件 |

## 美术单（给 Codex，进行中）

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [93_codex_elite_forms_art](93_codex_elite_forms_art.md) | 精英化攻击形态素材 | 已全部交付 | §0 是全部特效单的规格依据；10-22 逐条核对无未交付项（见 incoming/codex_order_1022_handoff.md §1） | 61、91、95、96、98；elite_art_1_manifest.json、game.gd、ally_rework_1014_handoff.md 等 12 个文件 |
| [94_codex_enemy_redraw](94_codex_enemy_redraw.md) | 普通 / 精英怪重画 | 进行中 | §0 敌人条款被 98 引用；暖橙补单已被冷色回调，晚补单未交 | 93、96、98；gallery.gd、enemy_redraw_3_handoff.md、game.gd 等 15 个文件 |
| [96_codex_enemy_attack_fx](96_codex_enemy_attack_fx.md) | 怪物攻击特效 | 进行中 | 第 1 批已接入，第 2 / 3 批未交 | render/world.gd、enemies/enemy_ai.gd、run/enemies.gd 等 7 个文件 |
| [97_codex_operator_fixes](97_codex_operator_fixes.md) | 干员存量修整 | 进行中 | A–F 已接入；G 批只交了水月，还在 codex/art | 98；incoming/op_fix_b_handoff.md、incoming/op_fix_e_handoff.md、characters/character.gd 等 15 个文件 |
| [codex_order_1022_handoff](../art/incoming/codex_order_1022_handoff.md) | Codex 素材单 10-22 | 进行中 | §1 精英化素材核对（无未交付项）；§2 骑士 `e_knight*` @2x = 1x × 2 返修单，待交 | docs/93、115、108 §5、98 §10.1 |
| [90_codex_toy_cover](90_codex_toy_cover.md) | B站 Toy 封面与图标 | 进行中 | 已选定 shadow_1014，未上传 | — |

## 测试与发布

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [36_testing](36_testing.md) | 测试规范 | 现行规范 | 快检分级、谁跑全量（§1.1）、复现与基线 TRACE 缓存（§3.2）、云端（§7.5.1，角色会话不推分支）、基线 | 23、27、29、38、39、40 等 22 篇；game.gd、run/autotest.gd、tools/balance_run.py 等 19 个文件 |
| [80_ab_method](80_ab_method.md) | 平衡对照口径 | 现行规范 | 置信区间 + 同种子配对；胜率差 <10 点不下结论 | 36、38、82、83、88、91 等 7 篇；tools/cloud_compare.py |
| [27_balance_framework](27_balance_framework.md) | 数值平衡框架 | 现行规范 | §2 分层、§3 档位与预算、§9 新干员流程在用；§1 目标看 38 §8.12，§6 口径看 80，§4 以 balance.json 为准 | data/balance.json |
| [29_bot_testing](29_bot_testing.md) | 分档机器人 | 现行规范 | 机器人档位与指标；§3 难度目标已作废（见 38 §8.12），第五档 master 见 36 | 27、36、38、41、79、归档46 等 7 篇；tools/balance_run.py、game.gd、data.gd 等 6 个文件 |
| [33_release_build](33_release_build.md) | 打包发布 | 现行规范 | 双版本三包、itch、瘦身、ship.py 一键发版 | 41、55、99、归档ea_boss_variety_20260927；tools/export_build.py、tools/export_web.py、tools/release_all.py 等 11 个文件 |
| [50_performance](50_performance.md) | 性能测量 | 进行中 | 帧时测量方法与各轮优化记录；§18 原生运动核心实测，§19 HUD 字体缓存与隔离对照，§20 双端 60 帧迭代（尚未达标），§21 网页为主基准（手机口径、WebGL 状态缓存 −19% / Boss −32%） | 21、35、36、38、39、41 等 15 篇；render/world.gd、game.gd、data/balance.json 等 34 个文件 |
| [55_code_audit](55_code_audit.md) | 代码冗余审计 | 进行中 | 大部分清理已做；§6 剩余项未做 | 35、39、41、56、57、归档14；boss_ai.gd、game.gd、relic_fx.gd 等 21 个文件 |
| [101_arch_audit_1015](101_arch_audit_1015.md) | 代码框架审计与 C++ 预留 | 进行中 | 10-15 框架问题 / 冗余清单、原生代码切入面与构建约束、阶段 0 / 1 / 2 路线；§7 派活清单、§8 待用户定 | — |
| [104_pixel_pipeline](104_pixel_pipeline.md) | 干员像素素材流程规范 | 现行规范 | 10-16 定：Codex 静态 f0 / 动画（分层合成）两条线、三层验收、f0 并行 + 人内串行；口径只在 103 改 | 97、103；tools/px_lint.py |
| [105_op_anim_arch_for_codex](105_op_anim_arch_for_codex.md) | 干员动画接口：现状与 Codex 改造说明 | 已实施记录 | 核心迁移已在 6b697796 完成；现行契约见 87 §3.5，补齐序列恢复与互斥校验；截图验收仍由界面与美术负责 | 87、92、101 |
| [106_codebase_overview_for_codex](106_codebase_overview_for_codex.md) | 代码架构总览（给 Codex 改代码） | 现行规范 | 10-17：目录职责、每帧次序、干员数据与动画接口、测试工具、Codex 改代码规则 §6 | 41、36、101、105 |
| [107_summon_visual_alignment](107_summon_visual_alignment.md) | 召唤物美术运行时对齐 | 进行中 | 独立显示时钟、真实出手对齐、七条身体接线与Mon3tr特效返工判断；旧专用动作保留 | 06、36、87、104、106 |
| [108_operator_runtime_arch](108_operator_runtime_arch.md) | 干员动画运行时架构（现行） | 现行规范 | 10-20 架构审读 Codex 10-17 起代码：分层、每帧次序、状态机、字段表、画布口径、冲突 / 废弃清单、剩余 9 人接入方案、校验检查表、审查发现 | 87、98、105、106、107 |
| [110_op_audit_1021](110_op_audit_1021.md) | 18 人新美术接入后统一复查 | 一次性审计记录 | 10-21：动作快慢（修 ulpianus 出手帧对齐）、攻速阈值（4人会被压缩，突发场景会糊，列待定）、旧美术残留（无硬编码旧路径，56个孤立文件待定）、文案核对（已知例子已修复，无新问题）、护盾强度（队长护盾出场率≈7%、HUD仅shield_max>0显示、塞雷娅无护盾、召唤物护盾零使用） | 76、108、109 |
| [111_balance_1021](111_balance_1021.md) | 新美术后干员 / 怪物数值复核 | 一次性记录 | 10-21：木桩表 + 云端单人开局 / 配对；水月主控生命 125 / 回复 1.5 / 拖拽 20（单开 45→70%）；标准 63.7、Ⅳ 56.5、Ⅷ 38.4（暂停校准，只登记） | 27、79、80、36 |
| [115_boss_portrait_candidates](115_boss_portrait_candidates.md) | Boss 登场名片头像：现状、候选与候选 A 实现 | 已实施记录 | 10-21：10 只都有专画头像但是糊剪影；用户选候选 A（局内像素裁切放大，暂弃用专画头像文件但不删），实现记录 + e_knight@2x 尺寸异常待核实 | 38、41、87、104 |
| [114_command_mode](114_command_mode.md) | 指挥模式（第 1 步原型） | 进行中 | 10-21：一个键循环 随行 / 突击 / 归队（F / LB / 触屏「指挥」键），归队到位后集合站定，突击耐力（25 秒耗尽自动归队、50 秒回满），屏外队友头像标记，balance command 段旋钮；对比视频与机器人小样（突击常开输出 +8%、承伤 +22%）；§7 突击三件套原型（仇恨 / 职业走位 / 队友生命与倒地，各自开关，4 组合小样）；按键名待用户定 | 22、41、76、109 |
| [116_curve_audit](116_curve_audit.md) | 玩家 / 怪物成长曲线审计 | 方案待用户看 | 10-21：TTK / TTD 按分钟实测（输出 ×22 vs 怪物生命 ×3.2；败局集中 8:20–9:30、单下接触 15–28% 最大生命）；主流肉鸽做法；建议血量不动、压重型怪单下伤害、回血不加 | 27、50、111 |
| [118_op_response_actions](118_op_response_actions.md) | 干员响应动作（设计稿） | 设计稿 | 10-21：队长冲刺 / 站定 / 开技能 / 指挥切换四类触发源，18 人每人一条轻量响应；机动性约束、四个共用触发器、同 seed 开关、第一批切片建议 | 76、108、114 |
| [120_build_branch_p1](120_build_branch_p1.md) | 分支培养 P1（试点 4 人） | 已实现、待试玩定档 | 10-22：docs/119 §4.1 节点 4 二选一 + 节点 5 沿路线强化（德克萨斯 / 星熊 / 艾雅法拉 / 铃兰）、§4.2 培养保底简化版；JSON 结构、换人 / 赠送推进事务、参数对照与两路线木桩表；开关 levelup/branch、focus_guard | 119、76、61、tests/build_progression_test |
| [121_audio_shrink](121_audio_shrink.md) | 网页包压音频 | 已实施记录 | 10-21：324 个音频文件包内大小表；BGM 重编码 0.70、语音 24 kHz 约 57 kbps，音效不动；语音按需加载估算；压前压后对比样本与实导大小 | 113；tools/shrink_audio.py、export_web.py |
| [2026-10-22-operator-voice](superpowers/plans/2026-10-22-operator-voice.md) | 第六批语音接入计划 | 实施记录 | 两人标准语音、20 条已确认突击回应、登场一次性钩子；保持调度规则与同 seed TRACE | 114、121、106；voice_command_test |
| [122_op_lappland](122_op_lappland.md) | 拉普兰德设计稿与数值（近卫 · 领主） | 设计 + 数值已填、未接美术 | 10-22：原作身份 / 技能查证（日晷 / 狼魂 / 精神摧毁；「狼之隐 / 深渊的咆哮」查无）、普攻双刃 + 领主剑气、封印天赋、三技能、精一狼之舞 / 精二双生刃、节点 4 断喝 / 狼魂·狂、响应动作「噤声」（设计）、预算表、木桩表与单人胜率、美术需求单（原作 Spine 轨）、新积木清单 | 27、61、91、108、118、119、76、79 |
| [123_op_gladiia](123_op_gladiia.md) | 歌蕾蒂娅设计稿与数值（特种 · 钩索师 · 深海猎人） | 设计 + 数值已填、未接美术 | 10-22：原作查证（缺水的大洋裂断 / 掌握怒海 / 碎漩狂舞、阿戈尔的波涛）、普攻每下掷钩拖回（hookshot）、深海猎人续航天赋、三技能、精一锚定 / 精二冲撞、节点 4 深海的庇护 / 怒海、响应动作「回收」（设计）、预算表、木桩表与单人胜率、美术需求单、新积木清单 | 27、61、91、108、118、119、76、79 |
| [124_headhunt_design](124_headhunt_design.md) | 干员寻访（局外解锁）：界面、动效与美术 | 设计稿 | 10-22：结算后寻访揭示（主动作「信号解码」：扫描线自上而下把剪影解码成彩色，4–5 秒可跳过）、招募券选职业 / 人事调度函指定、意向保底、选人 / 图鉴 / 封面干员的未解锁剪影与新加入高亮、特效单（交 Codex）、与局外成长会话的接口；样张 tools/concept_headhunt.py | 37、62、76、109 |
| [129_op_texas_rework](129_op_texas_rework.md) | 德克萨斯攻击模式（方案 A「阻挡」：原地拔刀宽扇形 + 命中最近两名定住 + 每第 4 次骤雨 360°；技能名改回原作；删定时冲刺、剑雨无敌人不放） | 10-24 已实现，云端对比见 §12 | 10-23 用户「自动冲刺太晕」→ 疾刃三连（27%）→ §11 三方案 → 10-24 拍板 A：成长节点逐个对应、技能名对照与待定、木桩表、全员自动技能空放清单 | 61 §21、108 §18、118 §6、122 |
| [129_ulpianus_s3_charge](129_ulpianus_s3_charge.md) | 乌尔比安 S3 冲锋 + 歌蕾蒂娅钩索拉人修复 | 已实现、待云端复核 | 10-24：S3 掷锚后本体沿锁链冲向落点（沿途 120% 宽 50 每名一次 + 落地 200%）、画面走光学观感；歌蕾蒂娅「拉不动人」复现（落点 230 ≈ 射程 240、push_out 反推、走廊漏人）与修复（hook_front 110、目标必拖） | 61、108、122、123、76 |
| [127_art_ta_review_1023](127_art_ta_review_1023.md) | 美术 TA 审阅（怪物 29 种 + 干员 20 名 + 特效 220 张） | 一次性审阅 | 10-23：游戏内真实缩放对照 + 量化指标（证据在 build/ta_review/）；A 阻碍可读 9 / B 风格割裂 11 / C 整洁 4（含 §6 特效专项）；先做 5 项 + 特效 3 项（文字让出队长、怪物边光、Boss 遮挡、定像素密度、Boss 体量与整数缩放） | 87、104、108 |
| [130_fx_audit](130_fx_audit.md) | 光学观感开启时的老特效盘点（重复 / 冲突 / 白跑） | 一次性审阅 | 10-24：61 条逐项（在哪 / 现状 / 建议 / 收益 / 风险）+ 精简 15 组按收益排序；法线光照与中档辉光是 GPU 大头，fx_burst 被死亡帧条吃额度是真冲突；低档回退保留 | 50、54、127 |
| [132_handoff_1024](132_handoff_1024.md) | 交接手册（10-24 晚版，Claude / GPT 通用）：换账号 / 换模型接手先读——接手第一步、工作方式、合入流程、当前状态、在飞分支、待拍板、已定口径 | 现行 |
| [135_leader_swap](135_leader_swap.md) | 切换队长（原型） | 进行中 | 10-23：Q / RB / 触屏点卡轮流切队长，谁都不瞬移、镜头 0.25 秒缓动、冷却 2 秒、倒地者不能切、生命共用、切换播出击语音；技能键改 E / J | 41、114 |
| [112_camera_zoom_brightness](112_camera_zoom_brightness.md) | 战斗镜头拉远 + 全局亮度候选 | 已结案 | 用户 10-22 定：镜头不采用、缺省不变；亮度用 B。10-21：镜头 ×0.85 / ×0.75 / ×2/3 与手机 ×1.0 / ×0.9 的截图、视频、像素与帧时间；刷怪环 / 回收视野会在画面里露馅、需改逻辑视野常量；亮度 A / B / C（暗部、环境光、全局）对照与统计；推荐桌面 2/3、手机 1.0、亮 B | 50、56、80、L4 look |
| [117_boss_pacing_audit](117_boss_pacing_audit.md) | 后期 Boss 垃圾时间审计 | 方案待用户看 | 10-21：最终 Boss 用时中位 42–101 秒（偏短不偏长）、战内无空转；根因是 10:00 登场后场上敌人数 67→11（−83%）——`final/stop_mobs` + `trickle_mult` 0.35 太保守；建议调高 trickle 旋钮，不建议砍 Boss 血量 | 38、41、95、116 |
| [99_bilibili_toy_faq](99_bilibili_toy_faq.md) | B站 Toy 官方 FAQ | 现行规范 | 官方答疑帖存档（外部参考）+ 本作对照；§0 的数字已过时 | — |
| [encrypted_release_20260928](encrypted_release_20260928.md) | Windows 加密发行 | 已实施记录 | 换机重建加密模板步骤的唯一出处（33「一次性准备」链到这里） | — |
| [live_test_launcher](live_test_launcher.md) | 免打包测试入口 | 现行规范 | 启动测试版.cmd 的用法；末段 Boss 描述已过时 | — |

## 记录

| 文档 | 标题 | 状态 | 说明 | 被谁引用 |
|---|---|---|---|---|
| [艾雅法拉弹体重量返修](plans/2026-10-20-eyja-volcanic-weight.md) | 火球、熔岩弹与火山弹表现 | 已实施记录 | 精零单发火球 / 复咏1.6倍、精一双发、精二低抛；分开两类命中，保留方格熔池与阶段实机对照，待视觉认可 | docs/61 §17.2 |
| [52_EA反馈问卷](52_EA反馈问卷.md) | EA 试玩反馈问卷 | 进行中 | 问卷在收；38 §8.12 普通档目标等它 | 38、41、56 |
| [100_store_copy](100_store_copy.md) | 商店页文案与改名候选 | 进行中 | B 站 Toy / itch 商店页文案（按 76、99）与游戏改名候选（文案，10-14） | — |

## 已归档（2026-10-14 第二轮，原位留一行指针）

| 文档 | 标题 | 归档原因 | 现行依据 | 被谁引用 |
|---|---|---|---|---|
| [08_relic_adaptation](archive/08_relic_adaptation.md) | 水月藏品改编总表（262 件，初版） | 作废：流派已换成 A–H，件表多轮手改 | game/data/relics.json、relic_effects.json；docs/35、57 | 09、11、归档06、归档14；core/relic_db.gd、data/relic_effects.json |
| [10_art_v6_spec](archive/10_art_v6_spec.md) | 美术 V6 接入约定 | 一次性接入约定；援护四类已删，通用条款被 93 §0、98 §6 取代 | docs/98、93 §0；帧数见 game.gd V6_FRAMES | 55；incoming/art_v6_handoff.md、game.gd |
| [13_art_v7_spec](archive/13_art_v7_spec.md) | 美术 V7 接入约定（战斗表现层） | 一次性接入约定，末尾接入状态表已过时 | docs/98 §6、93 §0；帧数见 game.gd V6_FRAMES | 归档12；render/world.gd、game.gd |
| [20_hires_spec](archive/20_hires_spec.md) | @2x 接入约定（水月） | 作废：画法已改为以 @2x 为主、描边 2px、怪物也要 @2x | docs/98 §1、87 §1；加载见 art.gd | 归档24；player_2x_handoff.md、incoming/squad_2x_handoff.md、squad_2x_manifest.json |
| [24_squad_art_brief](archive/24_squad_art_brief.md) | 首批编队美术指令（给 Codex） | 已交付、验收、接入；通用规格已并入 87 §1 | docs/87、98；Mon3tr 画布 64×64、脚底 (32,60) 仍以本文 §4 为准（98 §3 写成 48×48，待改） | 23、58、87、归档27、归档32、归档38 等 8 篇；characters/character.gd、incoming/squad_2x_handoff.md、squad_batch1_handoff.md 等 9 个文件 |
| [27_batch2_art_brief](archive/27_batch2_art_brief.md) | 第二批干员美术指令（给 Codex） | 已交付，经 32 审查返修后接入 | docs/87、98；灯塔画布 64×64 仍以本文为准（98 §3 未写） | 归档63 |
| [28_gamepad](archive/28_gamepad.md) | 手柄适配 | 已实施；键位表早于冲刺、手动普攻 | game/scripts/pad.gd 文件头 | — |
| [32_art_review_0926_acceptance](archive/32_art_review_0926_acceptance.md) | 美术验收：Codex 返修稿 a9471c7 | 一次性验收，已合入接线；§3-3 提亮要求已被 87 §4.2 否定 | docs/87 | 归档63 |
| [32_squad_art_review](archive/32_squad_art_review.md) | 编队人物美术审查（三批） | 一次性审查，§1 / §2.1 已交付，§3 代码已改；§2.2 次要项从未派出 | docs/87 | 归档32、归档63；art_review_0926_manifest.json |
| [42_relic_enemy_curve](archive/42_relic_enemy_curve.md) | 藏品曲线 × 怪物曲线实测 | 09-26 一次性实测，Boss 血量定值已进 balance.json | game/data/balance.json boss 段；docs/38 §8.12、35 | 27、35、归档46；run/spawner.gd、data/balance.json |
| [44_test_optimization](archive/44_test_optimization.md) | 测试优化方案 | 已实施（--auto、上云已写进 36）；§3 基线作废 | docs/36 §1、§7 | 36、71、归档68；tools/check.py |
| [49g_灯标圈内安全方案](archive/49g_灯标圈内安全方案.md) | 引航灯标「圈内安全」方案 | 已实施（safe_bullet / safe_ranged 缺省开）；标题仍写「未改代码」 | docs/56 §1；balance.json beacon 段 | 38、41、56；run/enemies.gd、enemies/enemy_ai.gd、run/beacon.gd 等 6 个文件 |
| [51_1.1_更新日志](archive/51_1.1_更新日志.md) | 1.1 更新日志 | 1.1 版本对外日志；数值段（限购、15 种上限等）已失效 | docs/74 §10、33 | 41 |
| [59_batch3_operators](archive/59_batch3_operators.md) | 第三批干员技能设计 | 一次性设计稿，五人已数据化 | docs/61 §10–14；各干员 JSON | 25、41、60、61、归档63、归档72；characters/data_operator.gd、characters/op_blocks.gd、tools/gen_fx_batch3.py 等 12 个文件 |
| [63_batch3_art_brief](archive/63_batch3_art_brief.md) | 第三批干员美术指令（给 Codex） | 已交付、验收、接入；§1 明度线已作废 | docs/87、98；技能名以 61 + 干员 JSON 为准 | 41、61、87、归档59、归档64、归档69；tools/art_lint.py、squad_batch5_reference_feedback.md、squad_batch5_skalter_handoff.md |
| [64_batch5_art_acceptance](archive/64_batch5_art_acceptance.md) | 第三批帧条验收 + 返修草稿 | §4、§7.3–7.5、§8、§9 已转成返修单并交付 | docs/87（§4 明度、§3.2 跑步） | 61、87、归档69、归档73、归档84、归档86；tools/op_bright_mockup.py、tools/texas_bright_mockup.py、squad_batch5_revision_generation.json 等 11 个文件 |
| [65_relic_audit](archive/65_relic_audit.md) | 藏品描述与数值审计 | 一次性审计，提案已全部落地；留观项转 74 | relic_effects.json；docs/35 | 61、74；tests/relic_impl_test.gd、relic_fx.gd |
| [69_codex_rework_1012](archive/69_codex_rework_1012.md) | Codex 返修总单 A / B / C | 已交付；明度线已进 87 §4 与 art_lint TONE_OVERRIDE | docs/87 §3.2、§4 | 87、归档73、归档84、归档85；squad_batch5_hoshiguma_color_handoff.md、squad_batch5_run_rework_handoff.md、squad_batch5_texas_color_handoff.md 等 7 个文件 |
| [72_operator_stat_audit](archive/72_operator_stat_audit.md) | 干员初始数值审计 | 一次性审计与调整记录，建议已改进 JSON | 干员 JSON；docs/23 文首公式、79 | 74、归档78；screens/initial_stats.gd、data/characters/kaltsit.json、tests/test_core.gd |
| [73_codex_idle_rework_1012](archive/73_codex_idle_rework_1012.md) | Codex 返修单：第三批五人待机 | 已交付，87 附录 A 记「已全部达标」 | docs/87 §3.1 | 87、归档86；squad_batch5_idle_rework_handoff.md、tools/art_lint.py、costume_1012_exusiai_handoff.md 等 4 个文件 |
| [84_codex_ulpianus_facing](archive/84_codex_ulpianus_facing.md) | Codex 返修单：乌尔比安 / 推进之王朝向 | 已交付并接入（3867bcfd）；§3 mirror 机制说明仍被代码注释引用 | docs/87 §2 | 87；characters/character.gd、art.gd、gallery.gd 等 6 个文件 |
| [85_codex_run_rework_1013](archive/85_codex_run_rework_1013.md) | Codex 返修单：五个跑步循环 | 已交付并接入（928b8a35） | docs/87 §3.2 | 87、归档86；tools/art_lint.py、elite_art_2_extended_lint_qa.json、elite_art_2_lint_qa.json 等 4 个文件 |
| [86_codex_idle_pose_1013](archive/86_codex_idle_pose_1013.md) | Codex 返修单：艾雅法拉 / 铃兰待机侧身 | 已交付并接入（0c342d58） | docs/87 §2 | 87；tools/art_lint.py、incoming/op_fix_e_qa.json |
| [92_codex_angelina_float](archive/92_codex_angelina_float.md) | Codex 美术单：安洁莉娜浮空 | 已交付，QA 通过并接入 | docs/98 §2；「离地行 38±1」仍以本文为准（98 §2 指回工单） | 98；tools/art_lint.py、incoming/op_fix_c_qa.json、incoming/op_fix_e_qa.json 等 7 个文件 |
| [ea_ishar_20260927](archive/ea_ishar_20260927.md) | 伊莎玛拉人形治疗与敌对转化（9/27） | 一次性实现记录，同 10-13 那批 ea_*_0927 | docs/38 §8.6、95 | run/ishar_encounter.gd |

## 其他目录

| 目录 | 内容 |
|---|---|
| [archive/](archive/README.md) | 归档文档（10-13 第一轮 40 篇 + 10-14 第二轮 25 篇），README 有第一轮逐篇说明 |
| [reference/](reference/README.md) | 用户提供的参考资料：262 件藏品原作表、全局设计框架 v1.0、藏品图标参考 |

| [三人全动画接入](plans/2026-10-18-three-attack-timing.md) | 29 条动画、原生像素与分段时序 | 实施记录 | 三人完整动作、攻速适配及测试包；试验分支，未合入 main | docs/87、character.gd、attack_timing_test |
| [水月标准化](plans/2026-10-18-mizuki-runtime-standardization.md) | 公共攻击时序、技能生命周期与原生像素接入 | 实施记录 | 水月四步修复、旧分支清理；试验分支，未合入 main | docs/61 §26、art/incoming/mizuki_runtime_handoff.md |

| [水月 S3 整范围触手](plans/2026-10-18-mizuki-s3-fx.md) | 原作群攻与控制方向、新触手范围表现 | 试验实现 | 保留本作数值、不扣血，移除镜像 | seg_mizuki、mizuki_s3_fx、mizuki_runtime_test |

| [博士统一画风接入](plans/2026-10-18-doctor-style-integration.md) | 待机、跑步、倒下统一及 64/128 原点 | 测试版接入 | 用户批准新画风；保留既有四干员测试基线 | doctor.json、world、title_bg、doctor_run_test |
- [2026-10-18 怪物原作机制补齐](plans/2026-10-18-enemy-identity.md)：已实施记录；四类普通怪/精英的防御、光环和控制身份补齐与回归清单；引用：docs/95、enemy_identity_test。
