# docs/archive · 归档文档索引

2026-10-13 整理（用户：「现在有哪些 docs 用不到了可以清理一下」）。原则：**不删除，只归档**。下列文档已过时、一次性完成或已被新文档取代，原文件名与编号不变，正文未改，从 `docs/` 根目录 `git mv` 到这里；需要时可随时搬回。

- 其他文档或代码注释里只写编号的引用（如「docs/46 §6」「docs/48 ⑥」），对应文件若在本表中，就到这里找；带完整路径的引用已改成 `docs/archive/<文件名>`。
- 重号说明：06、12、13、14、21、28、32、38 有两份同号文档，本表注明归档的是哪一份；未列出的同号文档仍在 `docs/` 根目录。
- `art/incoming/` 里 Codex 的交付清单 / 交接说明仍写旧路径（`knight_v9_handoff.md` → 07、`fx30_manifest.json` → 30、`growth_fx_manifest.json` → 34、`boss_p1_manifest.json` → 38_boss_p1_art_acceptance），属于历史交付记录，没有改；按文件名在本表查即可。

| 文件 | 内容 | 归档原因 | 现行依据 |
|---|---|---|---|
| 00_game_design.md | v0.8 设计总览（水月单人时代，按全局框架 v1.0 标状态） | 停在 v0.8，编队制 / 三技能 / Boss 重做后整体过时 | docs/23、26、27、35、38、39 |
| 01_brainstorm.md | 立项头脑风暴与待定问题 | 阶段 0 的讨论稿，问题早已定完 | docs/23、37 等现行规格 |
| 02_roadmap.md | 按框架 P0–P4 排的开发路线 | 路线已走完，后续排期在协作队列 | docs/41 |
| 03_sprite_spec.md | 主角 32×32 像素小人规格 | 人物已改 48px + @2x 96px 标准 | docs/05、20、24 |
| 04_skill_relic_design.md | 水月技能与藏品设计草案 v1 | 早期草案，水月不再是唯一主角，藏品体系已重做 | docs/26、35、57 |
| 06_v05_plan.md | v0.5 计划：宝箱、金钱、藏品与海嗣重做（**06 号的计划稿**，不是 06_git_collaboration） | v0.5 已交付 | docs/08、35、38 |
| 07_boss_art_handoff.md | Codex 首轮 Boss 本体美术交接（2026-09-24） | 一次性交接，已接入 | docs/38；Boss 美术以 art/incoming 现行素材为准 |
| 12_art_audit.md | v1.3 美术体检与提升清单（讨论稿） | 讨论结果已落成 V7 约定 | docs/13_art_v7_spec、48→53/54 |
| 12_boss_attack_design.md | v1.3 Boss 攻击与技能设计 | 被 Boss 重做方案取代（docs/38 附录已指出其过时数值） | docs/38_boss_redesign |
| 13_balance_v14.md | v1.4 平衡重做与架构第一步（**13 号的平衡稿**，不是 13_art_v7_spec） | 版本实现记录，数值早已改过多轮 | docs/27_balance_framework |
| 14_refactor_plan.md | 架构重构计划（角色 / 地图 / 藏品 / 敌人可扩展化） | 重构已完成 | docs/39 |
| 14_relic_unify.md | v1.5 藏品系统合一实现记录 | 一次性实现记录，藏品已扩到 262 件并重分流派 | docs/35、57、65 |
| 15_v16_changes.md | v1.6 改动：伤害类型、威胁等级、新海嗣、藏品等级 | 版本实现记录 | docs/17、38、57 |
| 16_build_design_summary.md | v1.7.2 水月 Build 现状总结（供讨论） | 水月单人时代的讨论材料 | docs/23、35 |
| 21_balance_routes.md | 水月四条精英化路线强度核对（**21 号的数值稿**，不是 21_music_design） | 一次性测量，精英化路线已随编队制取消 | docs/27、29 |
| 30_codex_fx_requests.md | 给 Codex 的第二批干员武器特效需求 | 已交付并接入（art/incoming/fx30_*） | docs/25 |
| 32_art_review_0926_handoff.md | Codex 编队人物返修交接（2026-09-26） | 一次性交接，已合入 | docs/32_squad_art_review、32_art_review_0926_acceptance |
| 34_growth_art_requests.md | 可见成长线美术清单 + 给 Codex 的需求单 | 已交付并接入（art/incoming/growth_fx_*） | docs/25 |
| 38_boss_p1_art_acceptance.md | Boss P1（骑士 / 伊莎玛拉）美术验收（**38 号的验收稿**） | 一次性验收，返修已交付接入 | docs/38_boss_redesign §6.2 |
| 38_boss_p1_art_handoff.md | Boss P1 返修美术交接（**38 号的交接稿**） | 一次性交接，已接入 | docs/38_boss_redesign §6.2 |
| 45_gallery_demo_audit.md | 图鉴技能演示检查清单（2026-09-26） | 一次性检查，问题已修复并复核（c4defcc） | docs/36、61 |
| 46_ea11_numbers_plan.md | EA 1.1 数值优化计划 | 1.1 已发布，计划已执行完 | docs/27、80、82 |
| 47_horde_mix_v8_enemies.md | 大群混编与 V8 新敌人实现记录（EA 1.1） | 一次性实现记录；现行数据在 game/data/waves.json、enemies.json | docs/38、27 |
| 48_monster_vfx_audit.md | 怪物特效审查（2026-09-27，只读） | 审查项已在后续提交里落实（代码注释仍按编号引用） | docs/53、54 |
| 49f_灯标点燃调整方案.md | 引航灯标「点燃难」三种调整比较（方案稿） | 三种旋钮实测推不动，被圈内安全方案与「去不去」方案接替 | docs/49g、56 |
| 66_codex_fx_brief_skalter.md | Codex 特效单：浊心斯卡蒂 S3 地面大漩涡 | 已交付并接入（5cd03b80） | docs/61 §5.6 |
| 68_contracts.md | 潮汐合约：危机合约式自选难度 | 文首已标「已被取代」；难度改版另按潮位阶梯 | docs/71 |
| 70_codex_fx_texas_rain.md | Codex 特效单：德克萨斯「剑雨」 | 已交付并接入（0b7735d1） | docs/61 |
| 75_copy_audit.md | 游戏内文案「AI 味」排查（只审计） | 审计结论已收进语言风格规范 | docs/76 |
| 78_melee_share.md | 近战伤害占比与「抢怪」审计（只读） | 一次性分析，结论为没有抢怪效应 | docs/72、79 |
| balance_pass_20260928.md | 9/28 藏品与生存资源调整记录 | 一次性调整记录，数值已多轮更新 | game/data/balance.json、docs/27 |
| boss_mechanics_20260928.md | 9/28 Boss 机制与特效交接 | 一次性实现记录 | docs/38_boss_redesign |
| ea_boss_variety_20260927.md | 9/27 Boss 招式与密集弹幕 | 一次性实现记录 | docs/38_boss_redesign |
| ea_economy_20260927.md | 9/27 EA 经济、成长与交互物位置调整 | 一次性调整记录；其中藏品种类上限等已删（不设硬上限） | docs/27、35 |
| ea_iteration_20260927.md | 9/27 EA 试玩改进交接 | 一次性交接总表 | docs/27、38 |
| enemy_attack_variety_20260928.md | 9/28 敌人与 Boss 攻击丰富化 | 一次性实现记录；现行数据在 enemies.json | docs/38 |
| enemy_attacks_20260928.md | 9/28 普通怪与精英攻击调整 | 一次性调整记录 | docs/38 |
| enemy_status_20260928.md | 9/28 定向冰霜与侵蚀补强 | 一次性调整记录 | docs/49b、38 |
| relic_reclassification_20260928.md | 9/28 133 件藏品效果二次分类与强度复核 | 已被 262 件实装与新审计取代 | docs/57、65、74 |

## 2026-10-14 第二轮（协调人派，用户：「docs 也需要进行进一步的整理」）

和第一轮的区别：**原位置留一行指针文件**（写明归档原因与现行依据），所以代码注释、其他文档里按编号或完整路径的旧引用都不用改。这一轮之后 docs/ 根目录不再有同号的现行文档（27、28、32 的重号都归档了）。全部文档的分组与状态见 docs/00_index.md。

| 文件 | 内容 | 归档原因 | 现行依据 |
|---|---|---|---|
| 08_relic_adaptation.md | 水月藏品改编总表（262 件，初版） | 作废：流派已换成 A–H，件表多轮手改 | game/data/relics.json、relic_effects.json；docs/35、57 |
| 10_art_v6_spec.md | 美术 V6 接入约定 | 一次性接入约定；援护四类已删，通用条款被 93 §0、98 §6 取代 | docs/98、93 §0；帧数见 game.gd V6_FRAMES |
| 13_art_v7_spec.md | 美术 V7 接入约定（战斗表现层） | 一次性接入约定，末尾接入状态表已过时 | docs/98 §6、93 §0；帧数见 game.gd V6_FRAMES |
| 20_hires_spec.md | @2x 接入约定（水月） | 作废：画法已改为以 @2x 为主、描边 2px、怪物也要 @2x | docs/98 §1、87 §1；加载见 art.gd |
| 24_squad_art_brief.md | 首批编队美术指令（给 Codex） | 已交付、验收、接入；通用规格已并入 87 §1 | docs/87、98；Mon3tr 画布 64×64、脚底 (32,60) 仍以本文 §4 为准（98 §3 写成 48×48，待改） |
| 27_batch2_art_brief.md | 第二批干员美术指令（给 Codex） | 已交付，经 32 审查返修后接入 | docs/87、98；灯塔画布 64×64 仍以本文为准（98 §3 未写） |
| 28_gamepad.md | 手柄适配 | 已实施；键位表早于冲刺、手动普攻 | game/scripts/pad.gd 文件头 |
| 32_art_review_0926_acceptance.md | 美术验收：Codex 返修稿 a9471c7 | 一次性验收，已合入接线；§3-3 提亮要求已被 87 §4.2 否定 | docs/87 |
| 32_squad_art_review.md | 编队人物美术审查（三批） | 一次性审查，§1 / §2.1 已交付，§3 代码已改；§2.2 次要项从未派出 | docs/87 |
| 42_relic_enemy_curve.md | 藏品曲线 × 怪物曲线实测 | 09-26 一次性实测，Boss 血量定值已进 balance.json | game/data/balance.json boss 段；docs/38 §8.12、35 |
| 44_test_optimization.md | 测试优化方案 | 已实施（--auto、上云已写进 36）；§3 基线作废 | docs/36 §1、§7 |
| 49g_灯标圈内安全方案.md | 引航灯标「圈内安全」方案 | 已实施（safe_bullet / safe_ranged 缺省开）；标题仍写「未改代码」 | docs/56 §1；balance.json beacon 段 |
| 51_1.1_更新日志.md | 1.1 更新日志 | 1.1 版本对外日志；数值段（限购、15 种上限等）已失效 | docs/74 §10、33 |
| 59_batch3_operators.md | 第三批干员技能设计 | 一次性设计稿，五人已数据化 | docs/61 §10–14；各干员 JSON |
| 63_batch3_art_brief.md | 第三批干员美术指令（给 Codex） | 已交付、验收、接入；§1 明度线已作废 | docs/87、98；技能名以 61 + 干员 JSON 为准 |
| 64_batch5_art_acceptance.md | 第三批帧条验收 + 返修草稿 | §4、§7.3–7.5、§8、§9 已转成返修单并交付 | docs/87（§4 明度、§3.2 跑步） |
| 65_relic_audit.md | 藏品描述与数值审计 | 一次性审计，提案已全部落地；留观项转 74 | relic_effects.json；docs/35 |
| 69_codex_rework_1012.md | Codex 返修总单 A / B / C | 已交付；明度线已进 87 §4 与 art_lint TONE_OVERRIDE | docs/87 §3.2、§4 |
| 72_operator_stat_audit.md | 干员初始数值审计 | 一次性审计与调整记录，建议已改进 JSON | 干员 JSON；docs/23 文首公式、79 |
| 73_codex_idle_rework_1012.md | Codex 返修单：第三批五人待机 | 已交付，87 附录 A 记「已全部达标」 | docs/87 §3.1 |
| 84_codex_ulpianus_facing.md | Codex 返修单：乌尔比安 / 推进之王朝向 | 已交付并接入（3867bcfd）；§3 mirror 机制说明仍被代码注释引用 | docs/87 §2 |
| 85_codex_run_rework_1013.md | Codex 返修单：五个跑步循环 | 已交付并接入（928b8a35） | docs/87 §3.2 |
| 86_codex_idle_pose_1013.md | Codex 返修单：艾雅法拉 / 铃兰待机侧身 | 已交付并接入（0c342d58） | docs/87 §2 |
| 92_codex_angelina_float.md | Codex 美术单：安洁莉娜浮空 | 已交付，QA 通过并接入 | docs/98 §2；「离地行 38±1」仍以本文为准（98 §2 指回工单） |
| ea_ishar_20260927.md | 伊莎玛拉人形治疗与敌对转化（9/27） | 一次性实现记录，同 10-13 那批 ea_*_0927 | docs/38 §8.6、95 |
