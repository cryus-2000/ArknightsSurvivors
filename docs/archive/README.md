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
