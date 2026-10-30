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
| [144_endfield_wheel_style](144_endfield_wheel_style.md) | 指挥圆盘：终末地风格（调研 + 定稿） | 已实现、待用户看实机 | 10-24：终末地界面调研与 7 条规则；圆盘定稿终末地蓝 #1FA8F0（用户由黄改蓝）、12 层叠加（底盘 / 刻度环 / 斜纹带 / 切角扇区 / 外推虚框 / 指针游标…）、打开 / 常驻 / 悬停 / 收起动效、减少动态效果终态；建议只用在圆盘；探针 tools/probes/wheel_style_shots.py | 37、62、76、114 |
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
| [19_four_endings](19_four_endings.md) | 四结局方案 | 已实施记录（祭坛部分已被 154 取代） | 事件箱与四结局的旧规格；标题「未实现」不实，结局 Boss 09-29 已对调（以 waves.json 为准） | 38、49、49a、49c；endings.gd |
| [148_route_choice](148_route_choice.md) | 结局走向：替代海嗣祭坛的选路方案 | 已被 154 取代（用户选翻节点卡）；§2 原作调研与 §3 事件链仍有效 | 10-25：原作选路调研（PRTS + 解包）+ 四方案 A 航路图（推荐）/ B 岔路航标 / C Boss 宝箱 + 行商 / D 溟痕石碑；共用按原作重排的事件链；订正 49a §3.1 第 6 / 7 层；示意图 reference/148_route_*.svg | 19、49a；endings.gd、waves.json、guide.json |
| [154_node_cards](154_node_cards.md) | 翻节点卡：多结局选路正式方案 | 已实装（§9），待合入 | 10-25：取代 148 与海嗣祭坛；首通结局一后，3:30 / 7:00 中 Boss 后翻 3 张节点卡；结局只看信物、不绑灯火，结局入口每局必出、达成过的描结局色边；卡组权重、事件清单（原作 / 本作拟）、接口、机器人与测试、约 6 人日；示意图 reference/154_node_cards.png | 148、18、19；endings.gd、waves.json、choice_panel.gd |
| [156_event_cg](156_event_cg.md) | 事件插图：原作 CG 像素重构调研 | 调研待用户看 | 10-26：docs/154 用到的 18 件事件在原作都有 1600×900 专属 CG（rogue_2 choiceScenes.background）；PRTS 链接、裁切、难度、优先级（P1 结局线 7 张）；3 张 64 色草稿在 build/event_cg/ | 154；tools/probes/event_cg_pixel_draft.py |
| [162_swap_frequency](162_swap_frequency.md) | 后期换人频率 | 已改，待合入 | 10-26：满员后换人卡出现率 0.55 → 0.25（7:00 后 0.12）、两张深度卡时不出；后期换人卡间隔 46–59 秒 → 184–265 秒 | balance.json levelup；progression.gd；tools/probes/recruit_freq.py |
| [172_elite_catchup](172_elite_catchup.md) | 精英化落后补偿 | 已改，待云端对照 | 10-28 定档：深度卡按落后精英阶段加权（×1.8^差 封顶 3）、队长领先 ≥5 节点时保底让给落后者；队长精二 2:08 → 3:29、队友比队长晚 4:04 → 2:42（队友绝对时刻不变）；全队累计培养曲线不变 | balance.json levelup/catchup*；progression.gd |
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
| [166_loading_render_audio_1027](166_loading_render_audio_1027.md) | 单一启动加载页、渲染回收与激光混音 | 已实施记录 | 网页加载交接、遮罩闲置回收 7.03 MiB、圆环局部优化与低频光束提示；含测量边界 | boot_screen.gd、post_fx.gd、boss_attack_draw.gd、sfx.gd、tools/web/loader.js |
| [170_paranoia_combos_1027](170_paranoia_combos_1027.md) | 偏执泡影连携攻势与弹幕图案 | 已接入，待视觉验收 | 每幕两组有限连段轮换、收招破绽、打断规则；新增 7 种弹幕（身边睁眼轮射、正反旋、自机狙、错位缺口、缝隙墙、停滞再瞄准、幻影空心弹），主动攻击 7→14；开关 boss/paranoia_combos | paranoia_combos.gd、paranoia_combo_draw.gd、paranoia_combos_test.gd |
| [173_ishar_combos_1027](173_ishar_combos_1027.md) | 伊莎玛拉二阶段连段与图案弹幕 | 已接入，待视觉验收与云端对照 | 三幕各两组 ≤4 段连段 + 破绽；新招合唱环颂 / 泪雨 / 抚愈之歌 / 网鸣 / 大群之声粗光束 / 非弹幕歌声涟漪（7→13 招）；放松弹密度、光束蓄力与消散、伤害旋钮 ishar_combo_dmg 0.8、输出窗口 45–70%，拆网减弹；专属涟漪预警取代斜线填充；boss/ishar_combos 0 回旧轮转 | ishar.gd、ishar_combos.gd、ishar_tell_draw.gd、ishar_combo_test.gd |
| [174_izumik_combos_1027](174_izumik_combos_1027.md) | 伊祖米克分幕连携与专属弹幕 | 已接入，待视觉 / 难度验收 | 每幕两组连携（≤4 段 + 收招破绽），5 种新弹幕（潮汐相位流、子代共鸣、螺旋弹臂、习得弹、回流弹）与拦截主轴挂钩；迁徙潮预警改波峰勾边；boss/izumik_cards 可 A/B | izumik.gd、izumik_attack_draw.gd、izumik_card_test.gd |
| [173b_ishar_acts_plan](173b_ishar_acts_plan.md) | 伊莎玛拉三幕方案（一页） | §2 已做（每幕一个躲法主题），待测试台定数值 | 每幕主色 / 场地、招式表（新招 / 旧招变体）、弹幕形态、节奏与破绽；二幕潮涡（螺旋）、三幕侵蚀之泪（追踪）与双束交叉追扫待确认 | ishar_combos.gd、ishar_tell_draw.gd |
| [169_knight_combos_1027](169_knight_combos_1027.md) | 骑士连招与冰系材质 | 已接入，待视觉验收 | 放射双冰阵、冰波与三刺、二阶段新招；用户提供 Pimen / CreativeKind 素材，统一冷灰蓝及碰撞柱，实机 v4；场地裁剪、闭合夹击、四 Boss 分拍压力；一阶段插枪与耗尽后掷枪布柱，二阶段清柱并停止生成；含接手说明 | knight_boss.gd、final_boss_materials.gd、import_knight_ice.py |
| [171_saints_1027](171_saints_1027.md) | 圣徒两只：出招组、连携与分级弹幕 | 已接入，待视觉验收 | 每幕 2 组连携、打空弹药装填 = 破绽；伊比利亚重炮 → 碎弹（炮线残弹、弹坑、重炮弹），卡门直线弹列 / 交叉弹列 + 封锁线；大弹发光核心；不照搬符卡制度 | saint.gd、saint_card_preview.gd |
| [175_path_tide_1027](175_path_tide_1027.md) | 塑路者 / 接潮组弹幕图案与连段 | 已接入，待视觉与难度验收 | 每幕两套图案逐拍交替、分级弹体与显形、颗粒点预警；塑路者分形 / 树枝 / 回流 / 冲撞留弹，接潮组两体镜像弹幕与配合连段；光束蓄力 / 消散、图案弹伤害 ×0.8 旋钮；录像 build/boss_path_tide/v3 | path.gd、bishop.gd、archon.gd、immortal.gd、mid_cards.gd、mid_card_draw.gd、mid_boss_test.gd |
| [168_boss_volume_tracking_1027](168_boss_volume_tracking_1027.md) | 最终 Boss 材质、薄膜泡与攻击动作返修 | 实机审阅中 | 透明薄膜泡、独立持续追踪、破裂、三 Boss 材质与已有骨骼动作接线 | paranoia_bubble.gd、final_boss_materials.gd、final_attacks.gd、world.gd |
| [167_boss_pixel_fx_1027](167_boss_pixel_fx_1027.md) | 最终 Boss 新增招式像素材质返修 | 已否定候选 | 历史版本；后续材质、泡影追踪及动作接线以 168 为准 | boss_attack_draw.gd、final_attack_grains.gd |
| [165_final_boss_complete_1027](165_final_boss_complete_1027.md) | 最终 Boss 完整改造与联动修正 | 已实施记录 | 最终四 Boss 主动攻击 7/8/7/7，特效、追踪、冰柱、泪滴精英、友方保色、枪声与保留杂兵；覆盖 95/142b 的旧口径 | final_attacks.gd、boss_attack_draw.gd、ishar_encounter.gd、post_fx.gd、sfx.gd |
| [95_boss_moves](95_boss_moves.md) | Boss 招式改版 | 进行中 | 每 Boss 4 招；第 1、2 批已合入（§15、§16），第 3 批（接潮组）与 Boss @2x 补单待做；最终四 Boss 以 165 为准，其余招式以本文为准 | 36、38、98；boss_ai.gd、render/world.gd、tests/boss_variety_test.gd 等 20 个文件 |
| [150_hunt_into_hordes](150_hunt_into_hordes.md) | 围猎并入大群 + 难度曲线 A / B + 收紧 | 已实施记录 | 10-25：独立围猎关掉，3:45 / 5:00 / 6:15 固定节拍大群（5:00、6:15 围猎型：画面外合拢、缺口 16°、只数 ×1.5、HUD 只画缺口箭头）；所有大群速度散布 + 分批 + 左右摆「慢慢来」；方案 B dmg_late_cap 0.25（10:45 才封顶，影响很小）；合并 trim 后常规高手 76.8%，收紧 dmg_div 340 + horde_dmg 1.4 → 三档高手 58.9 / 35.7 / 14.3%；7:00 后压力回落待补；工具 tools/horde_rec.py | 146、147、149；run/spawner.gd、enemies.gd、screens/hud.gd |
| [159_assault_dash](159_assault_dash.md) | 突击模式队友低频自冲刺 | 已实施记录 | 10-26：突击中其他队友每 7 秒朝目标冲一段（复用第一下冲锋），德克萨斯每 4.5 秒带伤害冲刺；随行 / 归队不冲；`command/roam_dash` 可调 | 114、151；character.gd、texas.json |
| [164_suno_layers](164_suno_layers.md) | Suno 分轨接成整首分层循环配乐（战斗三段 / Boss / 最终 Boss / 图鉴） | 已实施记录 | 10-27：分层 / 响度 / bpm；§6 网页 BGM 16.75 MiB、共享 PCM 与切曲回收、手机全层、浏览器内存对照 | 21、50、121、132；sfx.gd、tools/suno_layers.py、web_audio.py |
| [177_boss_bench](177_boss_bench.md) | Boss 单场测试台：录正常编队打到 Boss 时的队伍快照，直接开打 Boss，云端对照各 Boss 改版 | 工具 + 结果 | 10-27：成长事件日志 + rng 状态重放；3 开局 × 2 档；破绽输出占比 | 36、142b、158；tools/boss_bench.py、tools/cloud/boss_bench_ab.sh、run/boss_bench.gd |
| [153_attack_scale](153_attack_scale.md) | 攻速整条缩放（去掉 min_duration / min_rest / 水月 min_cd 下限） | 已实施记录 | 10-25：攻击条整条按攻速等比缩短，动画倍率超 3 隔帧抽取；盘点各干员节奏下限；水月 1× / 2.5× / 4× 实测频率；1× TRACE 不变 | 140；character.gd、data_operator.gd、balance.json atkspeed |
| [155_mire_trail_fix](155_mire_trail_fix.md) | 溟痕「一长串后不动」修复 | 已实施记录 | 10-25：引痕者拖痕改按距离铺、每只 ≤8 片；怪物溟痕单独计数 16、超量淡出最老的；自然溟痕满了淡出最远一片再刷新；新溟痕 3 秒内不被灯火退散；修前 / 修后对比 build/mire_trail_before_after.mp4 | 147；enemy_ai.gd、combat.gd、shot_pool.gd、spawner.gd、enemies.gd、map.gd |
| [156_event_cg](156_event_cg.md) | 事件插图：原作 CG 像素重构调研 | 调研待用户看 | 10-26：docs/154 用到的 18 件事件在原作都有 1600×900 专属 CG（rogue_2 choiceScenes.background）；PRTS 链接、裁切、难度、优先级（P1 结局线 7 张）；3 张 64 色草稿在 build/event_cg/ | 154；tools/probes/event_cg_pixel_draft.py |
| [157_spotlight_tour](157_spotlight_tour.md) | 首局聚光框引导 + 到点小提示 | 已实现，待用户看实机 | 10-26：开局改进局后聚光框引导（生命与灯火 / 移动冲刺 / 指挥 3 步，点击翻步、可跳过）；精英 / Boss / 低灯 / 升级各弹一次小提示；翻页指南留在暂停菜单；`--tourdemo` / `--tipdemo` 录片 | 62；tests/tour_test.gd |
| [147_lamp_mire](147_lamp_mire.md) | 灯火与溟痕（方案 B） | 已实施记录 | 10-25：灯火 ≥70 身边溟痕慢慢收缩、踩着伤害 / 神经 −80%；<30 附近溟痕朝队长挪并长大、新溟痕刷得更近更勤；灯油试过 25→15、25→8（方案 A）后用户定调回原值（25 / 0.006），只保留溟痕规则；进出档小字提示；数值在 balance.json lamp 段；云端三档复测见 §5 | 146、56；run/enemies.gd、spawner.gd、combat.gd、world/map.gd |
| [160_op_synergy_design](160_op_synergy_design.md) | 干员连携技（设计稿） | 已实施（待云端配对） | 10-26：有 PRTS 出处的关系表（德克萨斯×能天使 / 拉普兰德、乌尔比安×斯卡蒂、幽灵鲨×歌蕾蒂娅、深海猎人群）；触发方案 α / β / γ 对比，推荐 β 技能联动；每对效果草案与数值区间、不成为唯一最优的约束；特效与原作台词需求；§9 用户定稿后的合击动作 + 实现记录 | 118、114、76；synergy.gd、synergy.json |
| [151_skill_need_enemy](151_skill_need_enemy.md) | 自动技能「范围内没有敌人不放」全员统一 | 已实施记录 | 10-25：门槛 = need_enemy → 伤害积木半径 + 20 → 普攻射程；治疗 / 增益类也加门槛；推进之王 S2 150 → 130；校验每个技能都能推出门槛；全表 | 129、118；data_operator.gd、ob_core.gd、ob_check.gd |
| [149_trim_pocket_dashfollow](149_trim_pocket_dashfollow.md) | 小怪前后期微调 + 囊海爬行者 1/3 血无敌自爆 + 队友跟随冲刺 | 已实施记录 | 10-25：普通怪前 3 分钟生命 / 伤害 ×1.08、7→8 分钟生命降到 ×0.92；囊海爬行者 66% / 33% 鼓胀无敌后爆裂；删德克萨斯队友短突进，随行队友在队长冲刺时一起冲；干员自动位移盘点表 | 129、118、145；spawner.gd、enemies.gd、character.gd |
| [163_visible_build_growth](163_visible_build_growth.md) | 可见成长藏品 | 已拍板、已实现（claude/build-growth-impl） | 10-26：盘点构筑体系与「拿到后看得出变强」（仅约 15% 的藏品画面可见）；远程投射物 +1（银餐叉散射 / 左轮弹巢连发）、近战范围 + 普攻剑气（锈蚀刀片 / 老近卫军之锋 / 赶车夫的长鞭）、召唤物 +1 / 体型 / 时长（散轶诗简 / 衍生者终端）共 7 件改造；叠层递减不设上限、与贯穿区分、手机降级档 | 35、61、119、111；relic_effects.json、op_shots |
| [163b_build_rework_plan_codex](163b_build_rework_plan_codex.md) | 七条流派完整改造方案 v2（Codex 163B，原文存档） | 待用户审，部分并入 163D | Codex 10-26：多弹 / 近战扩域 / 召唤驻场 / 控场引爆 / 弱点收割 / 护盾反击 / 治疗转伤；改 15 件 + 核对 5 件；撤回重击、号角减速、相机合影计数、召唤物副体拆伤 | 163D |
| [163c_relic_inventory_codex](163c_relic_inventory_codex.md) | 全量藏品分类底表（Codex 163A，265 件 + 同名 JSON） | 参考 | 12 个机制主类、当前效果 / 等级 / 渠道 / 前置 / 反馈方式 | 163B、163D |
| [163_visible_build_growth_codex](163_visible_build_growth_codex.md) | Codex 版可见成长草稿（历史） | 已被 163B 取代 | 弹体 / 范围 / 剑气 / 召唤的技术讨论 | 163D |
| [163d_build_fusion](163d_build_fusion.md) | 构筑改造融合稿（163B × 可见成长 7 件） | 已定稿、已实现 | 10-27：以 163B 七流派为骨架逐件对号；五条按推荐定稿（#56 清群倍率、#129 副体只 +1、#130 覆盖不延寿、四流派第二批、固定上限）；§6 含 5 件范围画面核对与三件闪避藏品保底 | 163、163B、163C |
| [191_relic_pacing](191_relic_pacing.md) | 藏品节奏：来源拆分、降频与核心延后 | 已实现，待整局校准 | 10-28/29：遥测加来源；精英掉箱 0.15 + 2:00 前不掉、途中一后移 35 秒、商店藏品连买涨价；大时刻宝箱多选项 + 稀有加权；升华 / 核心 73 件第一只中期 Boss 倒下前不出。胜局 17 → 12 件，胜率掉，等统一校准 | balance.json relic/*、shop/relic_step、progression、relic_fx、endings |
| [197_relic_taxonomy](197_relic_taxonomy.md) | 藏品分类统一成一套（映射表） | 待协调人审 | 10-29：lanes A–H / cat / effect_category / tags 四套合成一个 `lane`（docs/181 七流派 + 职业 / 通用 / 生存 / 经济）；265 件逐件映射、每个读取方改法、抽取份额变化 ≤3 点 | 181、35、relics.json、relic_effects.json |
| [204_test_system_plan](204_test_system_plan.md) | 测试体系方案（模块化快检 + 对账 + 图校验） | 方案 / 部分实装 | 10-30：快检分组、文本数字对账（text_reconcile）、节点 / 引用图校验（graph_lint）；§10 实装记录 | 41、126、199；tools/check.py |
| [203_relic_trim](203_relic_trim.md) | 藏品精简方案（纯属性三分、被动卡分工、回血 5 条、流派分布） | 待用户审 | 10-30：100 件纯属性藏品逐件分 改打法 19 / 删 30 / 填充 44 / 不动 7；生存被动卡 6 张删、协同 2 张改流派卡 + 新 4 张；回血收成 5 条；改打法份额 36% → 58%；未动数据 | 197、181、191、design_compass_draft_1029 |
| [187_web_shrink_1028](187_web_shrink_1028.md) | 网页包再压缩评估 | 已实现 | 10-28：按类别拆分；无损四项（字体 WOFF2、WebP 最高档、wasm LZMA 分片 + 自写解码器、art/incoming 关透明渗色）41.62 → 36.10 MiB；音频 C 档 / 音效降采样等用户 | 121、164、22 |
| [190_op_voice_more](190_op_voice_more.md) | 干员语音扩充 | 已实施 | 10-29：每人入队 4 / 突击 4 / 技能 4 / 闲聊 3 句原作语音（新增 110 条、+1.82 MiB），洗牌不重复 + 同句 60 秒；归队不再开口 | sfx.gd、voice_pools.json、tools/voice_more_1029.py |
| [192_logos_s3_fx_order](192_logos_s3_fx_order.md) | Codex 特效单：逻各斯 S3 扇形咒域 | 待转 Codex | 10-28：现状（扇形程序画、绕身符咒已是帧条）、原作出处、三条 @2x 帧条规格、范围对齐与性能约束、接口（缺图回退已接入） | seg_logos.gd、art.gd、logos_fx_handoff.md |
| [194_dmg_curve](194_dmg_curve.md) | 普通怪伤害曲线平滑化 | 已实现 | 10-29：后期一下封顶 30、前期 0–3 分钟平滑曲线、整条单调无断崖（dmg_curve/knots） | spawner.gd、dmg_curve.gd |
| [195_op_fx_audit_1029](195_op_fx_audit_1029.md) | 干员特效审查 | 记录 | 10-29：全员录像排查实心圆盘、范围跳变、特效与攻击方式不符、白灰色、装饰圆圈 | tools/op_fx_audit_rec.py |
| [205_ult_audio](205_ult_audio.md) | 终结技语音挑选与专属音效 | 方案，待用户挑 | 10-30：20 人每人终结技固定一句原作语音（候选表 + 推荐）；起手 / 冲击专属音效候选与试听录像；映射表 game/data/ult_audio.json | 198、199、113、53、190；run/ult.gd、sfx.gd |
| [201_final_boss_weak_diag](201_final_boss_weak_diag.md) | 最终 Boss「太弱」诊断与加伤 | 记录 | 10-29：最终 Boss 加伤血量不动；弹速 / 弹数 / 节奏旋钮；伊祖米克连携调度改版（izumik-sched） | 170、142b、bosses/*.gd |
| [199_bal_audit](199_bal_audit.md) | balance 旋钮对账 + Bal.v 缓存 | 记录 | 10-29：代码缺省值与 balance.json 不一致的 170 键（已改 208 读点，运行结果不变）；只在代码里的 366 键清单；`Bal.v` 路径缓存（桌面同局轮换 -0.3 ms / 帧）；`tools/bal_audit.py` | 27、balance.gd、data_lint |
| [193_integ_1029](193_integ_1029.md) | integ-1029 整合记录 | 记录 | 10-29：第一批 15 个分支的合入顺序、冲突处理、docs 重编（190 → 192）、素材挪路径 |
| [196_command_target](196_command_target.md) | 指挥模式「指点」：指定地点 / 目标进攻（方案） | 方案稿，待用户拍板 | 10-29：突击中指点地面（点位）或精英 / Boss（集火），取代清杂 / Boss 优先，圆盘仍 5 格；慢动作选点沿用 ×0.2 + 扣作战时限防滥用；手机拖拽 / 电脑点选 / 手柄光标；机器人三档校准；含默认关的示意原型与 52 秒操作录像 | 114、36、56、设计总纲草稿 |
| [200_telemetry_plan](200_telemetry_plan.md) | 数据埋点：死因分析与补洞提案 | 提案，待协调人审 | 10-29：用 cal1029 云端 1237 个死亡局做死因分析（tools/death_report.py，暴毙 = 普通怪围死为主）；现有埋点清单、三支柱缺口、分期（P0 遥测补洞 1）；只提案不实现 | 36、40、43、77、82、193；run/telemetry.gd、tools/death_report.py、balance_run.py、runs_report.py |
| [189_asset_layout_spec](189_asset_layout_spec.md) | 素材目录与命名规范 + 迁移方案 | 草案，待用户批 | 10-28：收货 art/incoming/<批次> → 在用 game/art/<类别> → 归档 art/archive；前缀 / id / 后缀规则；按索引找图；分 0–6 批迁移；检查 tools/asset_lint.py（只报告） | tools/asset_lint.py、art.gd |
| [188_asset_audit_1028](188_asset_audit_1028.md) | 素材命名与目录核对 | 待用户看 | 10-28：art/incoming 归档留底、旧合成配乐已删；game/ 没人读的 2 个、语音母带 22 MB 在运行时目录、同内容不同名 16 组、命名不合约定 4 处，只列不改 | art/archive/incoming_1028、game/audio/voice/masters |
| [186_integ_1028b](186_integ_1028b.md) | 整合分支 integ-1028b 冲突处理记录 | 记录 | 10-28 对内体验包：每处合并冲突一行 + docs 撞号重编表 | — |
| [183_knight_stage_plan](183_knight_stage_plan.md) | 最后的骑士 · 分阶段方案 v2 | 已接入 | 10-28：每幕招式组、三幕寒潮、二幕冰棱带、重生冲锋形态（原 171，撞号改 183） | knight_boss.gd、final_attacks.gd |
| [182_enemy_windup](182_enemy_windup.md) | 普通怪蓄力加速 | 已实现 | 10-28：非精英非 Boss 的蓄力 / 预警 / 引信 × windup_mult（原 179，撞号改 182） | enemy_ai.gd |
| [178_danger_pass](178_danger_pass.md) | 难度危险感回调 | 已实现 | 10-28：防暴毙保护收窄、普通怪伤害增益（claude/danger-pass） | balance.json |
| [185_card_text_1028](185_card_text_1028.md) | 卡面受益标签与文案修订 | 已实现 | 10-28：主效果 / 附带数值标签分开（淡色「仅物伤」）；点名干员卡只写当前编队；职业分支代指干员的文案改写（旧 → 新）；手机详情不截断 | 163D、76、37 |
| [181_operator_lanes](181_operator_lanes.md) | 干员流派标签重做 | 待审 | 10-28 用户提出：每人 1–2 个流派（7 个），流派件主效果只给本流派，宽泛附带删或改专属；全员流派表 + 逐件改法 + 4 个待定 | 163B、178、76 |
| [176_sword_wave_ease](176_sword_wave_ease.md) | 剑气非线性速度 | 已实现（待合入） | 10-27 用户：剑气改「爆发出手 → 衰减滑行」，总距离 / 存活时间 / 判定宽度不变；拉普兰德剑气、斯卡蒂潮刃、可见成长近战剑气共用 sword_ease.gd，旋钮 balance.json sword_ease | 163、136；sword_ease.gd、seg_skadi、vis_growth、sword_wave_capture |
| [161_elite_squad](161_elite_squad.md) | 紧急作战改「精英小队」 | 已实施记录 | 10-26：按阶段 8 / 10 / 12 只高一阶普通怪，生命 ×2、伤害 ×1.3、共用甲壳 / 潮盾词缀、红色描边 + 脚下红光、入场冲锋；计入同屏上限、放不下的推迟；全灭宝箱（稀有加权）+ 20 源石锭；iPhone 仿真帧时 | 158、154；endings.gd、render/world.gd、waves.json |
| [184_event_redesign](184_event_redesign.md) | 事件改版：有代价的取舍 + 对口交易 | 已实装（§9，P1 + P2），待合入；10-28 用户五条按推荐 | 10-27：每次摊牌至少一张交易卡、最多一张无代价卡，每件事件留稳妥项；按藏品 lanes 算主流派出对口奖励；一局 4 次翻卡（加 1:20 / 6:00 两张卡的途中路口），首通前也开但无结局入口；结局线规则不变；P1 8 件 + P2 5 件原作事件（rogue_2 choiceScenes 出处）、继承退役；V 价值口径、难度估计、约 7.5 人日、测试口径；示意图 reference/184_event_redesign.png | 154、148、156、161、35；endings.gd、events_v2.json、event_trade_test |
| [158_horde_stuck_fix](158_horde_stuck_fix.md) | 「怪物冒红光卡在原地」修复 | 已实施记录 | 10-26：大群分批出发延迟借用了收割者专用的 wake_t（只有收割者倒计时），其他怪永远站着，引痕者半血狂暴变红；改用 depart_t 统一倒计时；修前 / 修后对比 build/horde_stuck_before_after.mp4；§5 分级配比本作 vs 原作；§6 分级调整已实施（中后段高阶 10% / 25%、后段每局约 720 只，t5 定档高手 m0 30.4% / m18 55.4%）；§7 高阶单只帧时开销 | 150；spawner.gd、run/enemies.gd、enemy_ai.gd |
| [179_meta_first18](179_meta_first18.md) | 前 18 个细胞换成看得见的数值（方案） | 待用户确认 | 10-28：18 细胞 = 攻击性Ⅰ + 生存本能Ⅰ +12% + 生命感悟Ⅰ +0.3 + 自我保护Ⅰ -5%；危机感Ⅰ挪到第五位；总量 / 满点不变，预计 m18 50–58% |
| [145_enemy_canon_and_reach](145_enemy_canon_and_reach.md) | 小怪原作核对 + 攻击范围加强方案 | 方案待用户看 | 10-24：19 种普通怪 / 精英对照 PRTS 与解包数据（名字全对；奠基者 / 引痕者 / 育母弱点与原作相反、箱形恐鱼免疫非原作、囊海爬行者档案不符）；攻击范围现状表；加强 5 只（育母落点圈 30→46、狂奔者 62→90、收割者 / 巢涌者光环待定；囊海爬行者爆裂 80→160 已做），伤害不动；§4 箱形恐鱼新攻击方案；§5 奠基者踏地特效改地面层、骑士图鉴归 Boss 页（已做） | 49b、76、94、96；enemies.json、lore.json、gallery.gd |
| [146_difficulty_curve_1025](146_difficulty_curve_1025.md) | 难度曲线复查（三档 × 高手 / 普通，云端 336 局） | 方案待用户看 | 10-25：常规「前 1:30 很平 → 2 分钟陡升 → 3:00–5:30 平 → 7:00 台阶 → 7:30–9:30 平 → 最终段回落」；高压 / 深潮倍率开局全额生效、深潮高手 0–3:30 就死 27%；压力几乎全来自近身杂兵，溟痕 2:30 顶到 32 片上限几乎无威胁；方案 A 中段固定节拍大群 + 包围、B 后期伤害继续涨、C 难度倍率渐入（未实施）；§6 灯火：常规 3/4 时间满灯、回补 66% 来自精英灯油、损失 67% 是受击，寂灭占阵亡 30%（深潮 54%）；工具 tools/difficulty_curve.py | 109、111、116、117 |
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
| [50_performance](50_performance.md) | 性能测量 | 进行中 | 帧时测量方法与各轮优化记录；§18 原生运动核心实测，§19 HUD 字体缓存与隔离对照，§20 双端 60 帧迭代（尚未达标），§21 网页为主基准（手机口径、WebGL 状态缓存 −19% / Boss −32%）；§26 叠加特效后的帧率与同屏上限 65（云端不合）；§27 帧率稳定优先：启动页稳 60 再进标题、着色器预热、界面动效审计、`--ftrec` 帧时记录；§28 低配基准（限核 / 网页节流 + 手机视口）与逐级自动降档 | 21、35、36、38、39、41 等 15 篇；render/world.gd、game.gd、data/balance.json 等 34 个文件 |
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
| [143_ulpianus_charge_fx](143_ulpianus_charge_fx.md) | 乌尔比安 S3 冲锋特效（像素颗粒） | 已实现、待用户拍板 | 10-24：起冲锚尖聚光 → 路径深海水体颗粒逐颗熄灭 → 终点冲击颗粒环 + 落地冷却水花；沿途中档 / 落地重档命中三档；低画质回退 docs/129 画法；探针 tools/probes/ulp_charge_shot.py | 129、136、50、76 |
| [127_art_ta_review_1023](127_art_ta_review_1023.md) | 美术 TA 审阅（怪物 29 种 + 干员 20 名 + 特效 220 张） | 一次性审阅 | 10-23：游戏内真实缩放对照 + 量化指标（证据在 build/ta_review/）；A 阻碍可读 9 / B 风格割裂 11 / C 整洁 4（含 §6 特效专项）；先做 5 项 + 特效 3 项（文字让出队长、怪物边光、Boss 遮挡、定像素密度、Boss 体量与整数缩放） | 87、104、108 |
| [130_fx_audit](130_fx_audit.md) | 光学观感开启时的老特效盘点（重复 / 冲突 / 白跑） | 一次性审阅 | 10-24：61 条逐项（在哪 / 现状 / 建议 / 收益 / 风险）+ 精简 15 组按收益排序；法线光照与中档辉光是 GPU 大头，fx_burst 被死亡帧条吃额度是真冲突；低档回退保留 | 50、54、127 |
| [132_handoff_1024](132_handoff_1024.md) | 交接手册（10-24 晚版，Claude / GPT 通用）：换账号 / 换模型接手先读——接手第一步、工作方式、合入流程、当前状态、在飞分支、待拍板、已定口径 | 现行 |
| [135_leader_swap](135_leader_swap.md) | 切换队长（原型） | 进行中 | 10-23：Q / RB / 触屏点卡轮流切队长，谁都不瞬移、镜头 0.25 秒缓动、冷却 2 秒、倒地者不能切、生命共用、切换播出击语音；技能键改 E / J | 41、114 |
| [137_boss_flash](137_boss_flash.md) | 最终 Boss 战频闪：测量与修复 | 已实施记录 | 10-24：主因 Boss 受击白闪每下命中都续（起闪 6–7 次/秒、六七成时间是白的），命中三档次要；改为白闪间隔 ≥ 0.4 秒、0.09 秒淡出、Boss 不换受击姿态、去蓄力 sin 振荡；修后起闪 1.6–2.1 次/秒，框内超 3 次/秒的窗口 18–137 → 0–6；附录像 / 统计工具 tools/boss_flash_rec.py、boss_flash_measure.py；§7 Boss 重影：泡影二阶段别名帧条查不到重画表、按 2 帧切出 3 只并排，已修 | 53、127 |
| [139_look_nausea](139_look_nausea.md) | 画面「恶心 / 粘腻」排查：镜头取整节拍、非整数放大蠕动、高刷屏锁 60、顿帧频率、色调（暗而浓的青蓝 + 溟痕靛紫网纹）量化与旋钮方案 | 调查 / 待拍板 | 10-24：同 seed 逐项开关录帧（tools/probes/look_nausea.py）；试验开关 render/nausea_safe（缺省关） | 130、132、136 |
| [136_pixel_particle_template](136_pixel_particle_template.md) | 像素粒子模板（特效粒子化规范，样板：刀光第四版） | 现行 | 10-24：CPU 颗粒 + 一次批绘、2 px 世界格、只用 vrng、高 900 / 中 450、低画质回退；火 / 水 / 电 / 体液模板做法 | 50 §25.4、137 |
| [138_material_grains_review](138_material_grains_review.md) | Codex 材质颗粒（艾雅 / 拉普兰德）验收：能合、缺省关、修了什么、帧时、同 seed | 一次性审阅 | 10-24：fx/material_grains 关时 / 开时同 seed 逐行相同；桌面 +0.5–0.7 ms；拉普兰德返工 | 136、50 |
| [131_cleanup_inventory](131_cleanup_inventory.md) | 交接前清理盘点（art/incoming、game、tools、docs、仓库体积） | 一次性审阅 | 10-24：art/incoming 276 MiB 里在用约 21；三批删除计划（零风险约 92 MiB → 需验证约 165 → 需用户定约 41）；.git 2.9 GB 里 1.25 GB 是 codex/* 分支的 Spine 源 zip；查出 move_attack 帧条从未加载（bug） | 55、108、130 |
| [141_hit_feel_review](141_hit_feel_review.md) | 打击感偏弱的原因调研（A/B/C 三版逐项量化 + 近期削弱提交 + 改进清单，对照 hit-tiers 覆盖面） | 一次性审阅 | 10-24：怪物密度 0.4 使击杀 ×0.4、顿帧 2 帧 + 0.5 秒间隔、拥挤降噪压白闪 / 数字、近战判定 / 画面 1.7–5.5 倍；只读，未改代码 |
| [142_boss_phases](142_boss_phases.md) | Boss 分幕招式差异化设计稿（10-25 改版：看得出区别） | 设计稿待用户审 | 10-24 初稿：差别小是结构问题（中期 Boss 第二幕老三招不变、D 招出得少、最终 Boss 中间卡点多半是空的、出招不分幕、换幕信号一样），通用底座 + 10 只逐幕机制；用户定不做伊莎玛拉回人形 / 伊比利亚自损、伊祖米克全场分享灯柱内免伤且留缓冲、骑士重生慢走。10-25 改版：每幕三件套（攻击换形 + 特效套 + 转场演出，§2.5 / §3A），示意图 tools/probes/boss_phase_sheets.py → build/boss_phase_sheets/ | 38、95、117、136、137 |
| [142b_boss_axis](142b_boss_axis.md) | Boss 改版方案 B：每只一个主轴 + §8 合并 A 的新弹幕（现行推荐） | 方案待用户审 | 10-25：用户嫌方案 A 仍是「躲弹幕和冲击」，按同类游戏五种手段（docs/49d）给每只 Boss 一件必须做的事——骑士斗牛撞桩、塑路者截路（跑过路标）、伊比利亚打断装填、卡门封锁线（10-25 掩体删：玩家一直在跑）、泡影冲刺打落、伊莎玛拉破网、伊祖米克拦截子代、接潮组同步；每幕换规则、躲招精简到 2–3 招、最终战用 Boss 自己的机制小怪取代补怪；已按自动攻击核过（玩家只能移动 / 冲刺，主轴目标先于 Boss 自动攻击）；§8 合并版：A 每幕的新弹幕保留，每招标「拦路 / 惩罚 / 定拍」的用处、窗口期停火；§8.4 Boss 专属弹幕色（小怪弹仍青蓝、不加统一外圈）；§8.5 激光定用 Kanpelle（用户 10-25 购买）、枪击用现有素材 + 程序曳光；示意图 tools/probes/boss_axis_sheets.py、boss_combo_sheets.py、fx_candidates_sheet.py → build/ | 49d、95、109、137、139、142 |
| [140_op_anim_audit](140_op_anim_audit.md) | 干员动作审计：出手对时、攻速、跑动步频、星熊格挡跑动、塞雷娅 S3 放盾 | 已实施记录 + 待拍板 | 10-24：全员普攻出手 0 帧偏差、跑步不滑；修移动中技能出手帧被跑步截掉（12 人）、星熊 S1 格挡跑动条、塞雷娅 S3 按原作放盾 + 空手跑；水月 / 能天使 3 倍攻速被 min_duration 卡待定；用户追加：星熊 S1 改站定嘲讽 + 防御反击（verb.taunt_guard）、塞雷娅 S3 期间空手拳击（含跑动版）；探针 tools/probes/anim_sync_probe.py、走停录像 anim_move_capture.py | 108、110、128 |
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
| [凯尔希削弱方案](plans/2026-10-29-mon3tr-hp-plan.md) | Mon3tr 血条 / 倒地复活 / 治疗分配（待用户审） | 方案（未实施） | 怪不打召唤物的现状、推荐不吸仇恨、削弱估计 85 → 74–78%、改动文件与待定 5 项 | docs/114 §7–8、118、198 §4.4 |
| [水月标准化](plans/2026-10-18-mizuki-runtime-standardization.md) | 公共攻击时序、技能生命周期与原生像素接入 | 实施记录 | 水月四步修复、旧分支清理；试验分支，未合入 main | docs/61 §26、art/incoming/mizuki_runtime_handoff.md |

| [水月 S3 整范围触手](plans/2026-10-18-mizuki-s3-fx.md) | 原作群攻与控制方向、新触手范围表现 | 试验实现 | 保留本作数值、不扣血，移除镜像 | seg_mizuki、mizuki_s3_fx、mizuki_runtime_test |

| [博士统一画风接入](plans/2026-10-18-doctor-style-integration.md) | 待机、跑步、倒下统一及 64/128 原点 | 测试版接入 | 用户批准新画风；保留既有四干员测试基线 | doctor.json、world、title_bg、doctor_run_test |
- [2026-10-18 怪物原作机制补齐](plans/2026-10-18-enemy-identity.md)：已实施记录；四类普通怪/精英的防御、光环和控制身份补齐与回归清单；引用：docs/95、enemy_identity_test。
| [干员特效审查 10-29](195_op_fx_audit_1029.md) | 全员干员特效排查：整片填充圆盘去除、白灰色、待确认项 | 已落地一批 | 浊心 / 逻各斯另会话处理；拉普兰德失色圈待用户定 | data_operator、seg_lumen 等、tools/op_fx_audit_rec.py |
| [测试体系方案 10-30](204_test_system_plan.md) | 快检耗时盘点、`--changed` 路径映射、说明对账、节点可达性、红项登记、分期 | 方案待审 | 未实装；附只读原型 text_reconcile_scan / graph_lint | check.py、known_red、check_map、tools/graph_lint.py |
