# 237 特效全量覆盖表（自动生成，别手改）

用户 11-02：每位干员的特效**整套替换**，不能有打到敌人的旧帧条漏网。本表由 `python tools/fx_coverage.py` 生成；状态改动写进各组自己的 `tools/pixelfx_fx/coverage_<组>.json`（键 `干员|特效名`，值 `{"status": "已做"|"不换", "new": 新名, "why": 理由}`；`*|特效名` 对所有归属生效），然后重新生成。新帧条按 `fx_<id>_px_*` 命名的自动算已做。

**验收口径（docs/229 §9 补充）：** 某位干员只有在本表里他的全部行（干员段 + 连携段）都是「已做」或「不换（有理由）」才算完成；组员报完成时附 `python tools/fx_coverage.py --op <id>` 的输出。终结技主视觉按规范只统一不重做，单列不计入完成判定。

**不在表里的：** 字符串拼出来的动态名（见文末清单，归属组手查）、人物本体精灵（op_*）。

## 0 覆盖率

| 归属 | 组 | 干员段 | 连携段 | 终结技（不计） |
|---|---|---|---|---|
| skadi | A | 3 / 13（23%） | 0 / 1（0%） | 0 / 10（0%） |
| hoshiguma | A | 1 / 12（8%） | 0 / 1（0%） | 0 / 4（0%） |
| lappland | A | 0 / 4（0%） | 0 / 3（0%） | 0 / 9（0%） |
| texas | A | 0 / 7（0%） | 0 / 5（0%） | 0 / 2（0%） |
| skalter | A | 0 / 2（0%） | 0 / 1（0%） | 0 / 6（0%） |
| eyjafjalla | B | 0 / 12（0%） | 0 / 5（0%） | 0 / 15（0%） |
| angelina | B | 0 / 8（0%） | 0 / 2（0%） | 0 / 5（0%） |
| logos | B | 0 / 25（0%） | 0 / 1（0%） | 0 / 7（0%） |
| lumen | B | 0 / 10（0%） | 0 / 0 | 0 / 7（0%） |
| suzuran | B | 0 / 11（0%） | 0 / 3（0%） | 0 / 7（0%） |
| gladiia | C | 0 / 12（0%） | 0 / 1（0%） | 0 / 5（0%） |
| mizuki | C | 0 / 9（0%） | 0 / 3（0%） | 0 / 11（0%） |
| ulpianus | C | 0 / 6（0%） | 0 / 7（0%） | 0 / 14（0%） |
| specter_unchained | C | 0 / 7（0%） | 0 / 3（0%） | 0 / 2（0%） |
| kaltsit | C | 0 / 8（0%） | 0 / 0 | 0 / 3（0%） |
| irene | D | 0 / 9（0%） | 0 / 3（0%） | 0 / 20（0%） |
| saria | D | 0 / 12（0%） | 0 / 3（0%） | 0 / 4（0%） |
| siege | D | 0 / 5（0%） | 0 / 3（0%） | 0 / 9（0%） |
| wisadel | D | 0 / 6（0%） | 0 / 1（0%） | 0 / 5（0%） |
| exusiai | D | 6 / 21（29%） | 0 / 2（0%） | 0 / 2（0%） |

干员合计（干员段 + 连携段）：10 / 247（4%）；敌方：0 / 59（0%）；公共：0 / 41（0%）

## 1 干员（技能 / 普攻 / 天赋 / 召唤 / 精英化 / 状态）

覆盖：10 / 199（5%）

| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |
|---|---|---|---|---|---|---|
| angelina | B | `fx_angelina_float_dust` | 普攻 | 未做 |  | json blocks/attack/then/1/do/0/on_hit/0/fx/0/strip |
| angelina | B | `fx_angelina_halt` | 普攻 | 未做 |  | json blocks/attack/on_hit/0/fx/0/strip |
| angelina | B | `fx_angelina_pull` | 普攻 | 未做 |  | json blocks/attack/then/0/fx/0/strip<br>json blocks/attack/then/1/fx/5/strip<br>json blocks/attack/then/1/do/0/fx/0/strip |
| angelina | B | `fx_angelina_well_back` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/1/strip |
| angelina | B | `fx_angelina_well_close` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/3/strip |
| angelina | B | `fx_angelina_well_front` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/2/strip |
| angelina | B | `fx_angelina_well_open` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/0/strip |
| angelina | B | `proj_angelina_orb` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/4/strip |
| exusiai | D | `fx_exusiai_blessed_flash` | 精英化 | 未做 |  | json blocks/progression/elite2/1/fx/0/strip |
| exusiai | D | `fx_exusiai_halo` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/fx/0/strip |
| exusiai | D | `fx_exusiai_hit` | 脚本 | 未做 |  | characters/blocks/seg_exusiai.gd:302<br>characters/blocks/seg_exusiai.gd:393<br>characters/blocks/seg_exusiai.gd:401 |
| exusiai | D | `fx_exusiai_hit_gold` | 天赋 | 未做 |  | json blocks/talent/1/do/0/hit_fx |
| exusiai | D | `fx_exusiai_muzzle` | 脚本 | 未做 |  | characters/blocks/seg_exusiai.gd:258 |
| exusiai | D | `fx_exusiai_muzzle_gold` | 天赋 | 未做 |  | json blocks/talent/1/do/0/muzzle_fx |
| exusiai | D | `fx_exusiai_pierce_gold` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/full_fx |
| exusiai | D | `fx_exusiai_px_hit_s1` | 技能 | 已做 |  | json blocks/skills/0/attack_patch/hit_fx |
| exusiai | D | `fx_exusiai_px_hit_s2` | 技能 | 已做 |  | json blocks/skills/1/attack_patch/hit_fx |
| exusiai | D | `fx_exusiai_px_hit_s3` | 技能 | 已做 |  | json blocks/skills/2/attack_patch/hit_fx |
| exusiai | D | `fx_exusiai_px_muzzle_s1` | 技能 | 已做 |  | json blocks/skills/0/attack_patch/muzzle_fx |
| exusiai | D | `fx_exusiai_px_muzzle_s2` | 技能 | 已做 |  | json blocks/skills/1/attack_patch/muzzle_fx |
| exusiai | D | `fx_exusiai_px_muzzle_s3` | 技能 | 已做 |  | json blocks/skills/2/attack_patch/muzzle_fx |
| exusiai | D | `proj_exusiai_bullet` | 普攻、脚本 | 未做 |  | json blocks/attack/tex<br>characters/blocks/seg_exusiai.gd:27 |
| exusiai | D | `proj_exusiai_bullet_power` | 天赋、脚本 | 未做 |  | json blocks/talent/1/do/0/tex<br>characters/blocks/seg_exusiai.gd:27 |
| exusiai | D | `proj_exusiai_bullet_s1` | 技能、脚本 | 未做 |  | json blocks/skills/0/attack_patch/tex<br>characters/blocks/seg_exusiai.gd:28 |
| exusiai | D | `proj_exusiai_bullet_s2` | 技能、脚本 | 未做 |  | json blocks/skills/1/attack_patch/tex<br>characters/blocks/seg_exusiai.gd:28 |
| exusiai | D | `proj_exusiai_bullet_s3` | 技能、脚本 | 未做 |  | json blocks/skills/2/attack_patch/tex<br>characters/blocks/seg_exusiai.gd:28 |
| exusiai | D | `proj_exusiai_bullet_t1` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/tex/0 |
| exusiai | D | `proj_exusiai_bullet_t2` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/tex/1 |
| exusiai | D | `proj_exusiai_bullet_t3` | 精英化、脚本 | 未做 |  | json blocks/progression/elite1/do/0/tex/2<br>characters/blocks/seg_exusiai.gd:299 |
| eyjafjalla | B | `fx_col` | 脚本 | 未做 |  | characters/blocks/seg_eyjafjalla.gd:116 |
| eyjafjalla | B | `fx_eyja_ignite_boom` | 技能、脚本 | 未做 |  | json blocks/skills/1/do/0/boom_fx/2/sprite/name<br>json blocks/skills/1/do/0/boom_fx/2/if_tex<br>json blocks/skills/1/do/0/boom_fx/3/if_tex<br>characters/magma_projectile.gd:67 |
| eyjafjalla | B | `fx_eyja_ignite_hit` | 脚本 | 未做 |  | characters/magma_projectile.gd:67<br>characters/magma_projectile.gd:67<br>characters/magma_projectile.gd:73<br>characters/magma_projectile.gd:74 |
| eyjafjalla | B | `fx_eyja_lava_pool` | 普攻、脚本 | 未做 |  | json blocks/attack/lob/pool/0/tex<br>characters/magma_projectile.gd:169 |
| eyjafjalla | B | `fx_eyja_lava_splash` | 技能、普攻、脚本 | 未做 |  | json blocks/attack/on_explode/0/look/land<br>json blocks/attack/lob/boom_fx/0/strip<br>json blocks/skills/0/attack_patch/on_explode/0/look/land<br>json blocks/skills/1/do/0/on_explode/0/look/land |
| eyjafjalla | B | `fx_eyja_melt_crack` | 普攻 | 未做 |  | json blocks/attack/on_explode/1/on_hit/0/look |
| eyjafjalla | B | `fx_flam_hit` | 技能、普攻、脚本 | 未做 |  | json blocks/attack/boom_fx/2/sprite/name<br>json blocks/skills/1/do/0/boom_fx/4/sprite/name<br>characters/blocks/seg_eyjafjalla.gd:470<br>characters/magma_projectile.gd:54 |
| eyjafjalla | B | `fx_logos_s1_link` | 脚本 | 未做 |  | characters/blocks/seg_eyjafjalla.gd:739 |
| eyjafjalla | B | `fx_sunburst` | 脚本 | 未做 |  | characters/blocks/seg_eyjafjalla.gd:691<br>characters/blocks/seg_eyjafjalla.gd:692 |
| eyjafjalla | B | `proj_eyja_ignite` | 技能 | 未做 |  | json blocks/skills/1/do/0/look/big_tex |
| eyjafjalla | B | `proj_eyja_lava_lob` | 技能、普攻 | 未做 |  | json blocks/attack/on_explode/0/look/tex<br>json blocks/attack/lob/tex<br>json blocks/skills/0/attack_patch/on_explode/0/look/tex<br>json blocks/skills/1/do/0/on_explode/0/look/tex |
| eyjafjalla | B | `proj_lavaball` | 技能、普攻、脚本 | 未做 |  | json blocks/attack/look/tex<br>json blocks/skills/1/do/0/look/tex<br>characters/blocks/seg_eyjafjalla.gd:632<br>characters/blocks/seg_eyjafjalla.gd:633 |
| gladiia | C | `fx_gl_pool1` | 脚本 | 未做 |  | characters/blocks/fx_gladiia_s3.gd:11 |
| gladiia | C | `fx_gl_pool2` | 脚本 | 未做 |  | characters/blocks/fx_gladiia_s3.gd:11 |
| gladiia | C | `fx_gl_pool3` | 脚本 | 未做 |  | characters/blocks/fx_gladiia_s3.gd:11 |
| gladiia | C | `fx_gladiia_pull` | 天赋、技能 | 未做 |  | json blocks/skills/2/do/0/do/1/fx/0/strip<br>json blocks/skills/2/do/0/visual_end/fx/1/strip<br>json blocks/trait/1/do/0/fx/0/strip |
| gladiia | C | `fx_gladiia_ram` | 技能、精英化 | 未做 |  | json blocks/skills/0/do/0/arrive_fx/0/strip<br>json blocks/skills/2/do/0/visual_end/fx/2/strip<br>json blocks/progression/elite2/do/0/fx/0/strip<br>json blocks/progression/elite2/do/0/fx/0/if_tex |
| gladiia | C | `fx_gladiia_tornado_close` | 技能 | 未做 |  | json blocks/skills/2/do/0/visual_end/fx/0/strip<br>json blocks/skills/2/do/0/visual_end/fx/0/if_tex |
| gladiia | C | `fx_gladiia_tornado_loop` | 技能 | 未做 |  | json blocks/skills/2/do/0/fx/1/strip<br>json blocks/skills/2/do/0/fx/1/if_tex |
| gladiia | C | `fx_gladiia_tornado_open` | 技能 | 未做 |  | json blocks/skills/2/do/0/fx/0/strip<br>json blocks/skills/2/do/0/fx/0/if_tex |
| gladiia | C | `fx_gladiia_water_glide` | blocks | 未做 |  | json blocks/run_fx/fx/0/strip |
| gladiia | C | `fx_slash_arc_deep` | 普攻 | 未做 |  | json blocks/attack/hook_nodes/slash/fx/0/blade/strip |
| gladiia | C | `fx_splash_blue` | 成长形态、普攻、精英化 | 未做 |  | json blocks/attack/hook_nodes/geyser/fx/0/sprite/name<br>json blocks/progression/elite2/do/0/fx/2/sprite/name<br>json blocks/progression/shield2/do/0/pop/0/fx/1/sprite/name |
| gladiia | C | `proj_gladiia_hook` | 天赋、技能 | 未做 |  | json blocks/skills/0/do/0/head<br>json blocks/trait/0/do/0/head |
| hoshiguma | A | `fx_hoshiguma_block` | 天赋、技能 | 未做 |  | json blocks/skills/0/do/1/fx/0/strip<br>json blocks/talent/0/fx/0/strip |
| hoshiguma | A | `fx_hoshiguma_guard_glow` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/fx/0/strip |
| hoshiguma | A | `fx_hoshiguma_px_saw` | 技能 | 已做 |  | json blocks/skills/2/do/2/attack/fx/0/strip |
| hoshiguma | A | `fx_hoshiguma_sand` | 天赋、成长形态 | 未做 |  | json blocks/trait/1/do/0/fx/0/strip<br>json blocks/progression/ember/0/do/0/fx/0/strip<br>json blocks/progression/ember/1/do/0/fx/0/strip |
| hoshiguma | A | `fx_hoshiguma_saw_spark` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/spark<br>json blocks/progression/elite2/1/do/0/spark |
| hoshiguma | A | `fx_hoshiguma_slash_rose` | 普攻 | 未做 |  | json blocks/attack/fx/0/strip |
| hoshiguma | A | `fx_hs_arc1` | 脚本 | 未做 |  | characters/blocks/seg_hoshiguma.gd:382 |
| hoshiguma | A | `fx_hs_arc2` | 脚本 | 未做 |  | characters/blocks/seg_hoshiguma.gd:382 |
| hoshiguma | A | `fx_hs_arc3` | 脚本 | 未做 |  | characters/blocks/seg_hoshiguma.gd:382 |
| hoshiguma | A | `fx_hs_fork` | 脚本 | 未做 |  | characters/blocks/seg_hoshiguma.gd:383 |
| hoshiguma | A | `fx_ul_rock` | 脚本 | 未做 |  | characters/blocks/seg_hoshiguma.gd:384 |
| hoshiguma | A | `proj_hoshiguma_sawshield` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/tex<br>json blocks/progression/elite2/1/do/0/tex |
| irene | D | `fx_cannon_burst` | 脚本 | 未做 |  | characters/blocks/seg_irene.gd:261 |
| irene | D | `fx_irene_crescent_wide` | 脚本 | 未做 |  | characters/blocks/seg_irene.gd:540 |
| irene | D | `fx_irene_gun_burst` | 脚本 | 未做 |  | characters/blocks/seg_irene.gd:514 |
| irene | D | `fx_irene_lift_arc` | 普攻 | 未做 |  | json blocks/attack/stages/0/on_first/0/fx/0/strip |
| irene | D | `fx_irene_thrust` | 普攻、脚本 | 未做 |  | json blocks/attack/look/beam<br>characters/blocks/seg_irene.gd:216 |
| irene | D | `fx_muzzle_flash` | 脚本 | 未做 |  | characters/blocks/seg_irene.gd:259 |
| irene | D | `fx_slash_heavy_rose` | 脚本 | 未做 |  | characters/blocks/seg_irene.gd:384 |
| irene | D | `fx_star_hit_rose` | 普攻、脚本 | 未做 |  | json blocks/attack/look/star<br>characters/blocks/seg_irene.gd:215 |
| irene | D | `fx_thrust_hit_rose` | 普攻、脚本 | 未做 |  | json blocks/attack/look/hit<br>characters/blocks/seg_irene.gd:195 |
| kaltsit | C | `fx_circle_steel` | blocks、精英化 | 未做 |  | json blocks/progression/elite2/1/do/0/then/0/fx/1/strip<br>json blocks/response/0/do/0/then/0/fx/1/strip |
| kaltsit | C | `fx_heal_aura_green` | 技能、普攻 | 未做 |  | json blocks/attack/do/0/fx/1/sprite/name<br>json blocks/skills/0/do/0/fx/1/sprite/name |
| kaltsit | C | `fx_holy_impact` | 技能、普攻 | 未做 |  | json blocks/attack/do/0/fx/2/sprite/name<br>json blocks/skills/0/do/0/fx/2/sprite/name |
| kaltsit | C | `fx_kaltsit_shell` | 成长形态 | 未做 |  | json blocks/progression/s1_shell/do/0/look/strip |
| kaltsit | C | `fx_mon3tr_blade` | 召唤 | 未做 |  | json blocks/summons/mon3tr/fx/4/side/strip<br>json blocks/summons/mon3tr/fx/5/side/strip |
| kaltsit | C | `fx_mon3tr_claw` | blocks、召唤、精英化 | 未做 |  | json blocks/summons/mon3tr/attack/fx/0/sprite/name<br>json blocks/summons/mon3tr/attack/fx/1/sprite/name<br>json blocks/progression/elite1/lunge/fx/1/strip<br>json blocks/progression/elite2/1/do/0/then/0/fx/2/strip |
| kaltsit | C | `fx_mon3tr_melt_slash` | 召唤 | 未做 |  | json blocks/summons/mon3tr/attack/fx/3/sprite/name |
| kaltsit | C | `fx_mon3tr_slam_ring` | blocks、精英化 | 未做 |  | json blocks/progression/elite1/lunge/fx/0/strip<br>json blocks/progression/elite2/1/do/0/then/0/fx/0/strip<br>json blocks/response/0/do/0/then/0/fx/0/strip |
| lappland | A | `fx_lappland_slash` | 成长形态、普攻 | 未做 |  | json blocks/attack/fx/0/strip<br>json blocks/attack/fx/0/if_tex<br>json blocks/attack/combo/0/do/0/fx/0/strip<br>json blocks/attack/combo/0/do/0/fx/0/if_tex |
| lappland | A | `fx_slash_heavy_deep` | 成长形态、普攻 | 未做 |  | json blocks/attack/fx/1/blade/strip<br>json blocks/attack/combo/0/do/0/fx/1/blade/strip<br>json blocks/progression/rage2/do/0/slash_fx/1/blade/strip |
| lappland | A | `proj_lappland_sword` | 天赋、成长形态、普攻、精英化 | 未做 |  | json blocks/attack/far/0/proj<br>json blocks/attack/far/1/proj<br>json blocks/attack/far/2/proj<br>json blocks/attack/far/3/proj |
| lappland | A | `proj_scale` | 脚本 | 未做 |  | characters/blocks/seg_lappland.gd:53<br>characters/blocks/seg_lappland.gd:53 |
| logos | B | `fx_circle_ink` | 技能 | 未做 |  | json blocks/skills/0/do/0/fx/0/sprite/name<br>json blocks/skills/0/do/0/jump_fx/0/sprite/name |
| logos | B | `fx_holy_pillar_ink` | 技能 | 未做 |  | json blocks/skills/2/fx/1/sprite/name |
| logos | B | `fx_ink_hit` | 普攻 | 未做 |  | json blocks/attack/then/1/fx/1/sprite/name |
| logos | B | `fx_logos_chain_anchor` | 普攻 | 未做 |  | json blocks/attack/then/2/anchor |
| logos | B | `fx_logos_chain_pulse` | 普攻 | 未做 |  | json blocks/attack/then/2/pulse |
| logos | B | `fx_logos_chain_tile` | 普攻 | 未做 |  | json blocks/attack/then/2/tile |
| logos | B | `fx_logos_glyph` | 普攻、脚本 | 未做 |  | json blocks/attack/then/0/on_exec/0/fx/3/sprite/name<br>json blocks/attack/then/1/fx/0/sprite/name<br>json blocks/attack/then/1/fx/0/if_tex<br>characters/blocks/seg_logos.gd:447 |
| logos | B | `fx_logos_glyphs` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:759 |
| logos | B | `fx_logos_s1_chain` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:334<br>characters/blocks/seg_logos.gd:795<br>characters/blocks/seg_logos.gd:798<br>characters/blocks/seg_logos.gd:881 |
| logos | B | `fx_logos_s1_link` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:275 |
| logos | B | `fx_logos_s3_back` | 技能 | 未做 |  | json blocks/skills/2/do/0/body/0 |
| logos | B | `fx_logos_s3_fan_close` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:586<br>characters/blocks/seg_logos.gd:587 |
| logos | B | `fx_logos_s3_fan_ground` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:576<br>characters/blocks/seg_logos.gd:576<br>characters/blocks/seg_logos.gd:580 |
| logos | B | `fx_logos_s3_fan_open` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:583<br>characters/blocks/seg_logos.gd:584 |
| logos | B | `fx_logos_s3_front` | 技能 | 未做 |  | json blocks/skills/2/do/0/body/1 |
| logos | B | `fx_logos_s3_orbit` | 技能 | 未做 |  | json blocks/skills/2/do/0/body/2 |
| logos | B | `fx_logos_s3_ribbon` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:605<br>characters/blocks/seg_logos.gd:606<br>characters/blocks/seg_logos.gd:609<br>characters/blocks/seg_logos.gd:610 |
| logos | B | `fx_logos_s3_slow` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:686<br>characters/blocks/seg_logos.gd:687<br>characters/blocks/seg_logos.gd:689<br>characters/blocks/seg_logos.gd:694 |
| logos | B | `fx_logos_script` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:799<br>characters/blocks/seg_logos.gd:800 |
| logos | B | `fx_logos_soul_rune_1` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/look/0 |
| logos | B | `fx_logos_soul_rune_2` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/look/1 |
| logos | B | `fx_logos_soul_rune_3` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/look/2 |
| logos | B | `proj_logos_ink` | 脚本 | 未做 |  | characters/blocks/seg_logos.gd:771<br>characters/blocks/seg_logos.gd:772 |
| logos | B | `proj_logos_ink_a` | 普攻 | 未做 |  | json blocks/attack/flight_visual/variants/0 |
| logos | B | `proj_logos_ink_b` | 普攻 | 未做 |  | json blocks/attack/flight_visual/variants/1 |
| lumen | B | `fx_circle_amber` | 技能 | 未做 |  | json blocks/skills/0/fx/1/sprite/name |
| lumen | B | `fx_heal_aura_amber` | 脚本 | 未做 |  | characters/blocks/seg_lumen.gd:56 |
| lumen | B | `fx_holy_impact_lantern` | 脚本 | 未做 |  | characters/blocks/seg_lumen.gd:51<br>characters/blocks/seg_lumen.gd:55<br>characters/blocks/seg_lumen.gd:185<br>characters/blocks/seg_lumen.gd:696 |
| lumen | B | `fx_holy_pillar_amber` | 技能 | 未做 |  | json blocks/skills/0/fx/0/sprite/name<br>json blocks/skills/2/fx/1/sprite/name |
| lumen | B | `fx_lumen_beam` | 普攻、脚本 | 未做 |  | json blocks/attack/beam/tile<br>characters/blocks/seg_lumen.gd:743<br>characters/blocks/seg_lumen.gd:754 |
| lumen | B | `fx_lumen_beam_flare` | 普攻、脚本 | 未做 |  | json blocks/attack/beam/flare<br>characters/blocks/seg_lumen.gd:744 |
| lumen | B | `fx_lumen_beam_hit` | 普攻、脚本 | 未做 |  | json blocks/attack/beam/hit<br>characters/blocks/seg_lumen.gd:739 |
| lumen | B | `fx_lumen_refract_hit` | 普攻、脚本 | 未做 |  | json blocks/attack/bolt/refract/hit<br>characters/blocks/seg_lumen.gd:695 |
| lumen | B | `fx_lumen_unit` | 脚本 | 未做 |  | characters/blocks/seg_lumen.gd:544 |
| lumen | B | `proj_lumen_bolt` | 普攻、脚本 | 未做 |  | json blocks/attack/bolt/tex<br>characters/blocks/seg_lumen.gd:521 |
| mizuki | C | `fx_mizuki_bind_ring` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:849<br>characters/blocks/seg_mizuki.gd:850 |
| mizuki | C | `fx_mizuki_jelly` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:461 |
| mizuki | C | `fx_mizuki_jelly_dart` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:834<br>characters/blocks/seg_mizuki.gd:835 |
| mizuki | C | `fx_mizuki_jelly_sting` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:805 |
| mizuki | C | `fx_mizuki_s3_field` | 脚本 | 未做 |  | characters/mizuki_s3_fx.gd:28 |
| mizuki | C | `fx_mizuki_tentacle` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:296<br>characters/blocks/seg_mizuki.gd:325<br>characters/blocks/seg_mizuki.gd:638 |
| mizuki | C | `fx_mizuki_tentacle_curl` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:685 |
| mizuki | C | `fx_tentacle_strike` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:297<br>characters/blocks/seg_mizuki.gd:437<br>characters/blocks/seg_mizuki.gd:439 |
| mizuki | C | `fx_umbrella_slash` | 脚本 | 未做 |  | characters/blocks/seg_mizuki.gd:262<br>characters/blocks/seg_mizuki.gd:268 |
| saria | D | `fx_circle_amber` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:851 |
| saria | D | `fx_heal_aura_amber` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:702 |
| saria | D | `fx_holy_impact` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:703 |
| saria | D | `fx_holy_pillar_amber` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:850 |
| saria | D | `fx_rock_burst` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:167<br>characters/blocks/seg_saria.gd:824 |
| saria | D | `fx_saria_amber_spot` | 普攻 | 未做 |  | json blocks/attack/calcify/tex |
| saria | D | `fx_saria_calcite` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:410<br>characters/blocks/seg_saria.gd:623 |
| saria | D | `fx_saria_pillar_break` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:166<br>characters/blocks/seg_saria.gd:823 |
| saria | D | `fx_saria_pillar_idle` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:424<br>characters/blocks/seg_saria.gd:425<br>characters/blocks/seg_saria.gd:426 |
| saria | D | `fx_saria_pillar_rise` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:419<br>characters/blocks/seg_saria.gd:420<br>characters/blocks/seg_saria.gd:421<br>characters/blocks/seg_saria.gd:422 |
| saria | D | `fx_saria_shield_bash` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:84 |
| saria | D | `fx_shield_amber` | 脚本 | 未做 |  | characters/blocks/seg_saria.gd:733 |
| siege | D | `fx_rock_burst` | 脚本 | 未做 |  | characters/blocks/seg_siege.gd:104 |
| siege | D | `fx_rock_spike` | 脚本 | 未做 |  | characters/blocks/seg_siege.gd:496 |
| siege | D | `fx_siege_fissure_tile` | 普攻 | 未做 |  | json blocks/attack/breach/tile |
| siege | D | `fx_siege_pebbles` | 普攻、脚本 | 未做 |  | json blocks/attack/crush/tex<br>characters/blocks/seg_siege.gd:103 |
| siege | D | `fx_siege_rock_spike` | 普攻、脚本 | 未做 |  | json blocks/attack/breach/spikes/tex<br>characters/blocks/seg_siege.gd:494 |
| skadi | A | `fx_skadi_leap_splash` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/fx/1/strip |
| skadi | A | `fx_skadi_px_cleave` | 技能 | 已做 |  | json blocks/skills/1/do/0/fx/0/blade/strip<br>json blocks/skills/1/do/1/fx/0/blade/strip |
| skadi | A | `fx_skadi_px_surge` | 成长形态、技能 | 已做 |  | json blocks/skills/0/do/2/fx/0/strip<br>json blocks/progression/surge/do/0/fx/0/strip |
| skadi | A | `fx_skadi_px_sweep` | 技能、精英化 | 已做 |  | json blocks/skills/0/do/0/fx/0/blade/strip<br>json blocks/skills/0/do/1/fx/0/blade/strip<br>json blocks/progression/elite1/do/0/fx/0/blade/strip |
| skadi | A | `fx_skadi_surge_hit` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/hit_fx/0/strip<br>json blocks/progression/elite2/0/do/0/hit_fx/0/if_tex<br>json blocks/progression/elite2/1/do/0/hit_fx/0/strip<br>json blocks/progression/elite2/1/do/0/hit_fx/0/if_tex |
| skadi | A | `fx_skadi_surge_release` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/release_fx/0/strip<br>json blocks/progression/elite2/1/do/0/release_fx/0/strip |
| skadi | A | `fx_skadi_wave` | 技能 | 未做 |  | json blocks/skills/1/do/2/tex |
| skadi | A | `fx_slash_arc_deep` | 脚本 | 未做 |  | characters/blocks/seg_skadi.gd:232<br>characters/blocks/seg_skadi.gd:477 |
| skadi | A | `fx_splash_blue` | 成长形态、技能、精英化 | 未做 |  | json blocks/skills/0/do/2/fx/3/sprite/name<br>json blocks/skills/1/do/0/fx/4/sprite/name<br>json blocks/skills/1/do/0/fx/5/sprite/name<br>json blocks/skills/1/do/0/fx/6/sprite/name |
| skadi | A | `proj_front` | 脚本 | 未做 |  | characters/blocks/seg_skadi.gd:124<br>characters/blocks/seg_skadi.gd:136<br>characters/blocks/seg_skadi.gd:429 |
| skadi | A | `proj_hold` | 脚本 | 未做 |  | characters/blocks/seg_skadi.gd:118<br>characters/blocks/seg_skadi.gd:139<br>characters/blocks/seg_skadi.gd:144<br>characters/blocks/seg_skadi.gd:425 |
| skadi | A | `proj_scale` | 脚本 | 未做 |  | characters/blocks/seg_skadi.gd:123<br>characters/blocks/seg_skadi.gd:146 |
| skadi | A | `proj_skadi_surge_blade` | 精英化 | 未做 |  | json blocks/progression/elite2/0/do/0/proj<br>json blocks/progression/elite2/1/do/0/proj |
| skalter | A | `fx_skalter_note` | 技能 | 未做 |  | json blocks/skills/0/fx/0/strip<br>json blocks/skills/1/fx/0/strip<br>json blocks/skills/2/fx/0/strip |
| skalter | A | `fx_skalter_vortex_floor` | 技能 | 未做 |  | json blocks/skills/2/do/0/fx/0/strip<br>json blocks/skills/2/do/0/fx/2/if_tex |
| specter_unchained | C | `fx_circle_ghost` | 技能、脚本 | 未做 |  | json blocks/skills/0/fx/2/sprite/name<br>json blocks/skills/1/fx/2/sprite/name<br>json blocks/skills/2/fx/2/sprite/name<br>characters/blocks/seg_specter.gd:453 |
| specter_unchained | C | `fx_specter_doll_appear` | 脚本 | 未做 |  | characters/blocks/seg_specter.gd:784<br>characters/blocks/seg_specter.gd:784 |
| specter_unchained | C | `fx_specter_doll_burst` | 脚本 | 未做 |  | characters/blocks/seg_specter.gd:802<br>characters/blocks/seg_specter.gd:802 |
| specter_unchained | C | `fx_specter_inward_ripple` | 精英化 | 未做 |  | json blocks/progression/elite1/do/0/fx/0/strip |
| specter_unchained | C | `fx_specter_saw` | 普攻、脚本 | 未做 |  | json blocks/attack/look/saw<br>characters/blocks/seg_specter.gd:100<br>characters/blocks/seg_specter.gd:100 |
| specter_unchained | C | `fx_specter_saw_blood` | 普攻、脚本 | 未做 |  | json blocks/attack/look/blood<br>characters/blocks/seg_specter.gd:100<br>characters/blocks/seg_specter.gd:100 |
| specter_unchained | C | `fx_water_splash` | 脚本 | 未做 |  | characters/blocks/seg_specter.gd:739<br>characters/blocks/seg_specter.gd:739 |
| suzuran | B | `fx_circle_gold` | 技能、脚本 | 未做 |  | json blocks/skills/0/fx/1/sprite/name<br>characters/blocks/seg_suzuran.gd:572 |
| suzuran | B | `fx_col` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:152 |
| suzuran | B | `fx_holy_pillar` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:343<br>characters/blocks/seg_suzuran.gd:568<br>characters/blocks/seg_suzuran.gd:571 |
| suzuran | B | `fx_suzuran_bigfox_trail` | 普攻 | 未做 |  | json blocks/attack/merge/trail/tex |
| suzuran | B | `fx_suzuran_foxfire_gather` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:110 |
| suzuran | B | `fx_suzuran_ninetails` | 普攻、脚本 | 未做 |  | json blocks/attack/tails/tex<br>characters/blocks/seg_suzuran.gd:625 |
| suzuran | B | `fx_suzuran_seal` | 普攻、脚本 | 未做 |  | json blocks/attack/brand/tex<br>characters/blocks/seg_suzuran.gd:738 |
| suzuran | B | `fx_suzuran_wisp` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:677 |
| suzuran | B | `proj_foxfire` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:697<br>characters/blocks/seg_suzuran.gd:698<br>characters/blocks/seg_suzuran.gd:705<br>characters/blocks/seg_suzuran.gd:706 |
| suzuran | B | `proj_max` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:93 |
| suzuran | B | `proj_suzuran_bigfox` | 脚本 | 未做 |  | characters/blocks/seg_suzuran.gd:695 |
| texas | A | `fx_rain` | 成长形态、技能、精英化 | 未做 |  | json blocks/skills/0/do/2/verb<br>json blocks/progression/rain2/do/1/verb<br>json blocks/progression/elite2/do/0/on_expire/2/verb<br>json blocks/progression/elite2/do/0/on_expire/3/verb |
| texas | A | `fx_texas_blade` | 成长形态、技能、精英化 | 未做 |  | json blocks/skills/0/do/2/strip<br>json blocks/progression/rain2/do/1/strip<br>json blocks/progression/elite2/do/0/on_expire/3/strip<br>json blocks/progression/rain3/0/do/1/strip |
| texas | A | `fx_texas_dash` | blocks、天赋 | 未做 |  | json blocks/trait/9/do/0/strip<br>json blocks/response/0/do/0/strip<br>json blocks/response/1/do/0/strip |
| texas | A | `fx_texas_pin_shatter` | 普攻 | 未做 |  | json blocks/attack/on_hit/1/fx/1/strip |
| texas | A | `fx_texas_pin_sword` | 普攻 | 未做 |  | json blocks/attack/on_hit/1/fx/0/strip |
| texas | A | `fx_texas_rain_mark` | 成长形态、技能、普攻、精英化 | 未做 |  | json blocks/attack/on_hit/1/fx/2/strip<br>json blocks/skills/0/do/2/mark<br>json blocks/progression/rain2/do/1/mark<br>json blocks/progression/elite2/do/0/on_expire/3/mark |
| texas | A | `fx_texas_sword_drop` | 精英化 | 未做 |  | json blocks/progression/elite2/do/0/on_expire/2/if_tex<br>json blocks/progression/elite2/do/0/on_expire/2/strip |
| ulpianus | C | `fx_shield_amber` | 技能 | 未做 |  | json blocks/skills/1/fx/2/sprite/name |
| ulpianus | C | `fx_slash_heavy_steel` | 天赋、技能、普攻、脚本 | 未做 |  | json blocks/attack/fx/0/sprite/name<br>json blocks/skills/1/do/1/attack/fx/0/sprite/name<br>json blocks/trait/0/do/0/fx/0/sprite/name<br>characters/blocks/seg_ulpianus.gd:459 |
| ulpianus | C | `fx_splash_blue` | 成长形态、脚本 | 未做 |  | json blocks/progression/blast2/do/0/fx/1/sprite/name<br>characters/ulpianus_charge_fx.gd:216<br>characters/ulpianus_impact.gd:13 |
| ulpianus | C | `fx_ulpianus_chain_tile` | blocks、精英化 | 未做 |  | json blocks/progression/elite2/do/0/chain<br>json blocks/response/0/do/0/chain |
| ulpianus | C | `fx_ulpianus_drag_dust` | blocks、精英化、脚本 | 未做 |  | json blocks/progression/elite2/do/0/dust_fx/0/strip<br>json blocks/response/0/do/0/dust_fx/0/strip<br>characters/blocks/seg_ulpianus.gd:327<br>characters/blocks/seg_ulpianus.gd:370 |
| ulpianus | C | `proj_ulpianus_anchor` | 脚本 | 未做 |  | characters/blocks/seg_ulpianus.gd:857<br>characters/blocks/seg_ulpianus.gd:858 |
| wisadel | D | `fx_muzzle_flash` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:107<br>characters/blocks/seg_wisadel.gd:651 |
| wisadel | D | `fx_wisadel_cannon` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:147<br>characters/blocks/seg_wisadel.gd:877<br>characters/blocks/seg_wisadel.gd:890 |
| wisadel | D | `fx_wisadel_gift_mark` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:1119 |
| wisadel | D | `fx_wisadel_mark` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:1109 |
| wisadel | D | `fx_wisadel_soul` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:1136<br>characters/blocks/seg_wisadel.gd:1141<br>characters/blocks/seg_wisadel.gd:1147 |
| wisadel | D | `proj_wisadel_soul_shell` | 脚本 | 未做 |  | characters/blocks/seg_wisadel.gd:1087<br>characters/blocks/seg_wisadel.gd:1088 |

## 2 连携（link_fx_*、skill_link、link_bond）

覆盖：0 / 54（0%）

| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |
|---|---|---|---|---|---|---|
| angelina | B | `fx_an_core` | 连携 | 未做 |  | run/link_fx_b.gd:307 |
| angelina | B | `fx_an_crater` | 连携 | 未做 |  | run/link_fx_b.gd:308 |
| exusiai | D | `fx_exusiai_muzzle` | 连携 | 未做 |  | run/link_fx_a.gd:62<br>run/link_fx_a.gd:63 |
| exusiai | D | `fx_ult_exusiai_burst_front` | 连携 | 未做 |  | run/skill_link.gd:175 |
| eyjafjalla | B | `fx_ey_fork1` | 连携 | 未做 |  | run/link_fx_b.gd:261 |
| eyjafjalla | B | `fx_ey_fork2` | 连携 | 未做 |  | run/link_fx_b.gd:261 |
| eyjafjalla | B | `fx_ey_fork3` | 连携 | 未做 |  | run/link_fx_b.gd:261 |
| eyjafjalla | B | `fx_ey_fork4` | 连携 | 未做 |  | run/link_fx_b.gd:261 |
| eyjafjalla | B | `fx_ey_rock` | 连携 | 未做 |  | run/link_fx_b.gd:260 |
| gladiia | C | `fx_gl_vortex` | 连携 | 未做 |  | run/link_fx_b.gd:291 |
| hoshiguma | A | `fx_lk_hs_shield` | 连携 | 未做 |  | run/link_fx_b.gd:124 |
| irene | D | `fx_lk_ir_lamp1` | 连携 | 未做 |  | run/link_fx_b.gd:183 |
| irene | D | `fx_lk_ir_lamp2` | 连携 | 未做 |  | run/link_fx_b.gd:183 |
| irene | D | `fx_lk_ir_lamp3` | 连携 | 未做 |  | run/link_fx_b.gd:183 |
| lappland | A | `fx_lk_lp_cres1` | 连携 | 未做 |  | run/link_fx_b.gd:12 |
| lappland | A | `fx_lk_lp_cres2` | 连携 | 未做 |  | run/link_fx_b.gd:12 |
| lappland | A | `fx_lk_lp_cres3` | 连携 | 未做 |  | run/link_fx_b.gd:12 |
| logos | B | `fx_lk_lo_ring` | 连携 | 未做 |  | run/link_fx_b.gd:169 |
| mizuki | C | `fx_lk_mz_ten1` | 连携 | 未做 |  | run/link_fx_b.gd:225 |
| mizuki | C | `fx_lk_mz_ten2` | 连携 | 未做 |  | run/link_fx_b.gd:225 |
| mizuki | C | `fx_lk_mz_ten3` | 连携 | 未做 |  | run/link_fx_b.gd:225 |
| saria | D | `fx_lk_sa_calc1` | 连携 | 未做 |  | run/link_fx_b.gd:206 |
| saria | D | `fx_lk_sa_calc2` | 连携 | 未做 |  | run/link_fx_b.gd:206 |
| saria | D | `fx_lk_sa_calc3` | 连携 | 未做 |  | run/link_fx_b.gd:206 |
| siege | D | `fx_lk_sg_crater1` | 连携 | 未做 |  | run/link_fx_b.gd:82 |
| siege | D | `fx_lk_sg_crater2` | 连携 | 未做 |  | run/link_fx_b.gd:82 |
| siege | D | `fx_lk_sg_crater3` | 连携 | 未做 |  | run/link_fx_b.gd:82 |
| skadi | A | `fx_lk_sd_trail` | 连携 | 未做 |  | run/link_fx_a.gd:18 |
| skalter | A | `fx_ult_skalter_domain_back` | 连携 | 未做 |  | run/link_fx_a.gd:71<br>run/skill_link.gd:1063 |
| specter_unchained | C | `fx_lk_sp_slash1` | 连携 | 未做 |  | run/link_fx_b.gd:41 |
| specter_unchained | C | `fx_lk_sp_slash2` | 连携 | 未做 |  | run/link_fx_b.gd:41 |
| specter_unchained | C | `fx_lk_sp_slash3` | 连携 | 未做 |  | run/link_fx_b.gd:41 |
| suzuran | B | `fx_lk_sz_fox1` | 连携 | 未做 |  | run/link_fx_b.gd:149 |
| suzuran | B | `fx_lk_sz_fox2` | 连携 | 未做 |  | run/link_fx_b.gd:149 |
| suzuran | B | `fx_lk_sz_fox3` | 连携 | 未做 |  | run/link_fx_b.gd:149 |
| texas | A | `fx_lk_tx1` | 连携 | 未做 |  | run/link_fx_a.gd:11<br>run/skill_link.gd:342<br>run/skill_link.gd:796 |
| texas | A | `fx_lk_tx2` | 连携 | 未做 |  | run/link_fx_a.gd:11 |
| texas | A | `fx_lk_tx3` | 连携 | 未做 |  | run/link_fx_a.gd:11 |
| texas | A | `fx_ult_texas_slash_front` | 连携 | 未做 |  | run/skill_link.gd:205 |
| texas | A | `fx_ult_texas_sword_front` | 连携 | 未做 |  | run/skill_link.gd:168<br>run/link_bond.gd:331 |
| ulpianus | C | `fx_ul_crack_fork` | 连携 | 未做 |  | run/link_fx_a.gd:17<br>run/link_fx_b.gd:364 |
| ulpianus | C | `fx_ul_crack_fork2` | 连携 | 未做 |  | run/link_fx_a.gd:17<br>run/link_fx_b.gd:364 |
| ulpianus | C | `fx_ul_crack_fork3` | 连携 | 未做 |  | run/link_fx_a.gd:17 |
| ulpianus | C | `fx_ul_crack_fork4` | 连携 | 未做 |  | run/link_fx_a.gd:17 |
| ulpianus | C | `fx_ul_rock` | 连携 | 未做 |  | run/link_fx_b.gd:83 |
| ulpianus | C | `fx_ulpianus_chain_tile` | 连携 | 未做 |  | run/link_fx_a.gd:88<br>run/link_fx_a.gd:101 |
| ulpianus | C | `fx_ult_ulpianus_anchor_front` | 连携 | 未做 |  | run/link_fx_a.gd:86<br>run/link_fx_a.gd:100<br>run/skill_link.gd:930<br>run/skill_link.gd:948 |
| wisadel | D | `fx_ws_crater` | 连携 | 未做 |  | run/link_fx_b.gd:332 |
| 公共 | 组长 | `fx_link_beacon1` | 连携 | 未做 |  | run/link_fx_common.gd:10 |
| 公共 | 组长 | `fx_link_beacon2` | 连携 | 未做 |  | run/link_fx_common.gd:10 |
| 公共 | 组长 | `fx_link_beacon3` | 连携 | 未做 |  | run/link_fx_common.gd:10 |
| 公共 | 组长 | `fx_link_relay1` | 连携 | 未做 |  | run/link_fx_common.gd:11 |
| 公共 | 组长 | `fx_link_relay2` | 连携 | 未做 |  | run/link_fx_common.gd:11 |
| 公共 | 组长 | `fx_link_relay3` | 连携 | 未做 |  | run/link_fx_common.gd:11 |

## 3 终结技（只统一不重做，不计完成）

覆盖：0 / 151（0%）

| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |
|---|---|---|---|---|---|---|
| angelina | B | `fx_an_core` | 终结技 | 未做 |  | run/ult_moves_b.gd:994<br>run/ult_moves_b.gd:1178 |
| angelina | B | `fx_an_crater` | 终结技 | 未做 |  | run/ult_moves_b.gd:1103<br>run/ult_moves_b.gd:1104<br>run/ult_moves_b.gd:1105<br>run/ult_moves_b.gd:1124 |
| angelina | B | `fx_angelina_well_back` | 终结技 | 未做 |  | run/ult_moves_b.gd:996 |
| angelina | B | `fx_angelina_well_close` | 终结技 | 未做 |  | run/ult_moves_b.gd:1098 |
| angelina | B | `fx_angelina_well_front` | 终结技 | 未做 |  | run/ult_moves_b.gd:1007 |
| exusiai | D | `fx_ult_exusiai_burst_front` | 终结技 | 未做 |  | run/ult_moves.gd:647<br>run/ult_moves.gd:739<br>run/ult_moves.gd:743 |
| exusiai | D | `fx_ult_exusiai_lock_orbit` | 终结技 | 未做 |  | run/ult_moves.gd:541<br>run/ult_moves.gd:846 |
| eyjafjalla | B | `fx_ey_bomb` | 终结技 | 未做 |  | run/ult_moves_b.gd:1366 |
| eyjafjalla | B | `fx_ey_fork1` | 终结技 | 未做 |  | run/ult_moves_b.gd:1361 |
| eyjafjalla | B | `fx_ey_fork2` | 终结技 | 未做 |  | run/ult_moves_b.gd:1361 |
| eyjafjalla | B | `fx_ey_fork3` | 终结技 | 未做 |  | run/ult_moves_b.gd:1361 |
| eyjafjalla | B | `fx_ey_fork4` | 终结技 | 未做 |  | run/ult_moves_b.gd:1361 |
| eyjafjalla | B | `fx_ey_fount` | 终结技 | 未做 |  | run/ult_moves_b.gd:1365 |
| eyjafjalla | B | `fx_ey_pool` | 终结技 | 未做 |  | run/ult_moves_b.gd:1363 |
| eyjafjalla | B | `fx_ey_pumice` | 终结技 | 未做 |  | run/ult_moves_b.gd:1367 |
| eyjafjalla | B | `fx_ey_rock` | 终结技 | 未做 |  | run/ult_moves_b.gd:1362 |
| eyjafjalla | B | `fx_ey_steam` | 终结技 | 未做 |  | run/ult_moves_b.gd:1364 |
| eyjafjalla | B | `fx_eyja_ignite_boom` | 终结技 | 未做 |  | run/ult_moves_b.gd:1301 |
| eyjafjalla | B | `fx_eyja_lava_pool` | 终结技 | 未做 |  | run/ult_moves_b.gd:1342 |
| eyjafjalla | B | `fx_eyja_lava_splash` | 终结技 | 未做 |  | run/ult_moves_b.gd:1249 |
| eyjafjalla | B | `fx_fire_explode` | 终结技 | 未做 |  | run/ult_moves_b.gd:1256 |
| eyjafjalla | B | `fx_missile_explode` | 终结技 | 未做 |  | run/ult_moves_b.gd:1302 |
| gladiia | C | `fx_gl_vortex` | 终结技 | 未做 |  | run/ult_moves_b.gd:941 |
| gladiia | C | `fx_gladiia_tornado_close` | 终结技 | 未做 |  | run/ult_moves_b.gd:906 |
| gladiia | C | `fx_gladiia_tornado_loop` | 终结技 | 未做 |  | run/ult_moves_b.gd:752 |
| gladiia | C | `fx_gladiia_tornado_open` | 终结技 | 未做 |  | run/ult_moves_b.gd:751 |
| gladiia | C | `fx_water_splash` | 终结技 | 未做 |  | run/ult_moves_b.gd:928<br>run/ult_moves_b.gd:930 |
| hoshiguma | A | `fx_hoshiguma_block` | 终结技 | 未做 |  | run/ult_moves_c.gd:1042 |
| hoshiguma | A | `fx_hoshiguma_guard_glow` | 终结技 | 未做 |  | run/ult_moves_c.gd:1076 |
| hoshiguma | A | `fx_hs_crack` | 终结技 | 未做 |  | run/ult_moves_c.gd:1064<br>run/ult_moves_c.gd:1101<br>run/ult_moves_c.gd:1175 |
| hoshiguma | A | `fx_hs_ring` | 终结技 | 未做 |  | run/ult_moves_c.gd:1120<br>run/ult_moves_c.gd:1175 |
| irene | D | `fx_cannon_burst` | 终结技 | 未做 |  | run/ult_moves_c.gd:1438 |
| irene | D | `fx_ir_gale` | 终结技 | 未做 |  | run/ult_moves_c.gd:1821 |
| irene | D | `fx_ir_slash1` | 终结技 | 未做 |  | run/ult_moves_c.gd:1819 |
| irene | D | `fx_ir_slash2` | 终结技 | 未做 |  | run/ult_moves_c.gd:1819 |
| irene | D | `fx_ir_slash3` | 终结技 | 未做 |  | run/ult_moves_c.gd:1819 |
| irene | D | `fx_ir_smoke1` | 终结技 | 未做 |  | run/ult_moves_c.gd:1820 |
| irene | D | `fx_ir_smoke2` | 终结技 | 未做 |  | run/ult_moves_c.gd:1820 |
| irene | D | `fx_ir_smoke3` | 终结技 | 未做 |  | run/ult_moves_c.gd:1820 |
| irene | D | `fx_ir_smoke4` | 终结技 | 未做 |  | run/ult_moves_c.gd:1820 |
| irene | D | `fx_irene_crescent_wide` | 终结技 | 未做 |  | run/ult_moves_c.gd:1401 |
| irene | D | `fx_irene_gun_burst` | 终结技 | 未做 |  | run/ult_moves_c.gd:1430 |
| irene | D | `fx_irv_chain1` | 终结技 | 未做 |  | run/ult_moves_c.gd:1464 |
| irene | D | `fx_irv_chain2` | 终结技 | 未做 |  | run/ult_moves_c.gd:1464 |
| irene | D | `fx_irv_chain3` | 终结技 | 未做 |  | run/ult_moves_c.gd:1464 |
| irene | D | `fx_irv_chain4` | 终结技 | 未做 |  | run/ult_moves_c.gd:1464 |
| irene | D | `fx_irv_seal` | 终结技 | 未做 |  | run/ult_moves_c.gd:1463 |
| irene | D | `fx_irv_smear1` | 终结技 | 未做 |  | run/ult_moves_c.gd:1465 |
| irene | D | `fx_irv_smear2` | 终结技 | 未做 |  | run/ult_moves_c.gd:1465 |
| irene | D | `fx_irv_smear3` | 终结技 | 未做 |  | run/ult_moves_c.gd:1465 |
| irene | D | `fx_irv_smear4` | 终结技 | 未做 |  | run/ult_moves_c.gd:1465 |
| kaltsit | C | `fx_ult_kaltsit_crack_back` | 终结技 | 未做 |  | run/ult_moves.gd:180<br>run/ult_moves.gd:1607 |
| kaltsit | C | `fx_ult_kaltsit_melt_front` | 终结技 | 未做 |  | run/ult_moves.gd:1556 |
| kaltsit | C | `fx_ult_kaltsit_rebuild_orbit` | 终结技 | 未做 |  | run/ult_moves.gd:1759 |
| lappland | A | `fx_la_ring2` | 终结技 | 未做 |  | run/ult_moves_c.gd:2046 |
| lappland | A | `fx_la_ring3` | 终结技 | 未做 |  | run/ult_moves_c.gd:2046 |
| lappland | A | `fx_la_ring4` | 终结技 | 未做 |  | run/ult_moves_c.gd:2046 |
| lappland | A | `fx_la_whirl` | 终结技 | 未做 |  | run/ult_moves_c.gd:2047 |
| lappland | A | `fx_la_x1` | 终结技 | 未做 |  | run/ult_moves_c.gd:2045 |
| lappland | A | `fx_la_x2` | 终结技 | 未做 |  | run/ult_moves_c.gd:2045 |
| lappland | A | `fx_la_x3` | 终结技 | 未做 |  | run/ult_moves_c.gd:2045 |
| lappland | A | `fx_la_x4` | 终结技 | 未做 |  | run/ult_moves_c.gd:2045 |
| lappland | A | `fx_lappland_slash` | 终结技 | 未做 |  | run/ult_moves_c.gd:1968 |
| logos | B | `fx_lo_glyph1` | 终结技 | 未做 |  | run/ult_moves_c.gd:831 |
| logos | B | `fx_lo_glyph2` | 终结技 | 未做 |  | run/ult_moves_c.gd:831 |
| logos | B | `fx_lo_glyph3` | 终结技 | 未做 |  | run/ult_moves_c.gd:831 |
| logos | B | `fx_lo_glyph4` | 终结技 | 未做 |  | run/ult_moves_c.gd:831 |
| logos | B | `fx_lo_rune` | 终结技 | 未做 |  | run/ult_moves_c.gd:830 |
| logos | B | `fx_logos_glyph` | 终结技 | 未做 |  | run/ult_moves_c.gd:734<br>run/ult_moves_c.gd:772<br>run/ult_moves_c.gd:805 |
| logos | B | `fx_logos_script` | 终结技 | 未做 |  | run/ult_moves_c.gd:716<br>run/ult_moves_c.gd:717 |
| lumen | B | `fx_beacon_ignite` | 终结技 | 未做 |  | run/ult_moves_c.gd:2249 |
| lumen | B | `fx_lu_pillar` | 终结技 | 未做 |  | run/ult_fx_c.gd:87 |
| lumen | B | `fx_lu_ring1` | 终结技 | 未做 |  | run/ult_fx_c.gd:88 |
| lumen | B | `fx_lu_ring2` | 终结技 | 未做 |  | run/ult_fx_c.gd:88 |
| lumen | B | `fx_lu_ring3` | 终结技 | 未做 |  | run/ult_fx_c.gd:88 |
| lumen | B | `fx_lu_shaft` | 终结技 | 未做 |  | run/ult_fx_c.gd:89 |
| lumen | B | `fx_lumen_beam_flare` | 终结技 | 未做 |  | run/ult_moves_c.gd:2250 |
| mizuki | C | `fx_mizuki_bind_ring` | 终结技 | 未做 |  | run/ult_moves_b.gd:1851 |
| mizuki | C | `fx_mizuki_tentacle` | 终结技 | 未做 |  | run/ult_moves_b.gd:1850<br>run/ult_moves_b.gd:1862 |
| mizuki | C | `fx_mizuki_tentacle_mass` | 终结技 | 未做 |  | run/ult_moves_b.gd:1831 |
| mizuki | C | `fx_mz_jelly1` | 终结技 | 未做 |  | run/ult_fx_c.gd:440 |
| mizuki | C | `fx_mz_jelly2` | 终结技 | 未做 |  | run/ult_fx_c.gd:440 |
| mizuki | C | `fx_mz_jelly3` | 终结技 | 未做 |  | run/ult_fx_c.gd:440 |
| mizuki | C | `fx_mz_small1` | 终结技 | 未做 |  | run/ult_fx_c.gd:178 |
| mizuki | C | `fx_mz_small2` | 终结技 | 未做 |  | run/ult_fx_c.gd:178 |
| mizuki | C | `fx_mz_small3` | 终结技 | 未做 |  | run/ult_fx_c.gd:178 |
| mizuki | C | `fx_mz_tent` | 终结技 | 未做 |  | run/ult_moves_b.gd:1716 |
| mizuki | C | `fx_rock_burst` | 终结技 | 未做 |  | run/ult_moves_b.gd:1683 |
| saria | D | `fx_sa_air` | 终结技 | 未做 |  | run/ult_moves_c.gd:438 |
| saria | D | `fx_sa_funnel1` | 终结技 | 未做 |  | run/ult_moves_c.gd:437 |
| saria | D | `fx_sa_funnel2` | 终结技 | 未做 |  | run/ult_moves_c.gd:437 |
| saria | D | `fx_saria_pillar_break` | 终结技 | 未做 |  | run/ult_moves_c.gd:415 |
| siege | D | `fx_rock_burst` | 终结技 | 未做 |  | run/ult_moves_c.gd:1226 |
| siege | D | `fx_sg_fork1` | 终结技 | 未做 |  | run/ult_moves_b.gd:780<br>run/ult_moves_c.gd:508<br>run/ult_moves_c.gd:1469<br>run/ult_moves_c.gd:2180 |
| siege | D | `fx_sg_fork2` | 终结技 | 未做 |  | run/ult_moves_b.gd:780<br>run/ult_moves_c.gd:508<br>run/ult_moves_c.gd:1469<br>run/ult_moves_c.gd:2180 |
| siege | D | `fx_sg_fork3` | 终结技 | 未做 |  | run/ult_moves_b.gd:780<br>run/ult_moves_c.gd:508<br>run/ult_moves_c.gd:1469<br>run/ult_moves_c.gd:2180 |
| siege | D | `fx_sg_fork4` | 终结技 | 未做 |  | run/ult_moves_b.gd:780<br>run/ult_moves_c.gd:508<br>run/ult_moves_c.gd:1469<br>run/ult_moves_c.gd:2180 |
| siege | D | `fx_sg_shock` | 终结技 | 未做 |  | run/ult_moves_c.gd:507 |
| siege | D | `fx_sg_shock2` | 终结技 | 未做 |  | run/ult_moves_c.gd:507 |
| siege | D | `fx_sg_shock3` | 终结技 | 未做 |  | run/ult_moves_c.gd:507 |
| siege | D | `fx_siege_rock_spike` | 终结技 | 未做 |  | run/ult_moves_c.gd:1224 |
| skadi | A | `fx_sd_blast1` | 终结技 | 未做 |  | run/ult_moves_b.gd:358 |
| skadi | A | `fx_sd_blast2` | 终结技 | 未做 |  | run/ult_moves_b.gd:358 |
| skadi | A | `fx_sd_blast3` | 终结技 | 未做 |  | run/ult_moves_b.gd:358 |
| skadi | A | `fx_sd_blast4` | 终结技 | 未做 |  | run/ult_moves_b.gd:358 |
| skadi | A | `fx_sd_cleave` | 终结技 | 未做 |  | run/ult_moves_b.gd:365 |
| skadi | A | `fx_sd_wall1` | 终结技 | 未做 |  | run/ult_moves_b.gd:373<br>run/ult_moves_b.gd:522<br>run/ult_moves_b.gd:563 |
| skadi | A | `fx_sd_wall2` | 终结技 | 未做 |  | run/ult_moves_b.gd:563 |
| skadi | A | `fx_sd_wave` | 终结技 | 未做 |  | run/ult_moves_b.gd:348 |
| skadi | A | `fx_skadi_surge` | 终结技 | 未做 |  | run/ult_moves_b.gd:229<br>run/ult_moves_b.gd:340<br>run/ult_moves_b.gd:908 |
| skadi | A | `fx_skadi_wave` | 终结技 | 未做 |  | run/ult_moves_b.gd:259 |
| skalter | A | `fx_sk_beam` | 终结技 | 未做 |  | run/ult_moves.gd:1070 |
| skalter | A | `fx_sk_blast` | 终结技 | 未做 |  | run/ult_moves.gd:1072 |
| skalter | A | `fx_sk_flash` | 终结技 | 未做 |  | run/ult_moves.gd:1071 |
| skalter | A | `fx_ult_skalter_domain_back` | 终结技 | 未做 |  | run/ult_moves.gd:180<br>run/ult_moves.gd:1449 |
| skalter | A | `fx_ult_skalter_seaborn_back` | 终结技 | 未做 |  | run/ult_moves.gd:962 |
| skalter | A | `fx_ult_skalter_seaborn_front` | 终结技 | 未做 |  | run/ult_moves.gd:961 |
| specter_unchained | C | `fx_sp_saw` | 终结技 | 未做 |  | run/ult_fx_c.gd:14 |
| specter_unchained | C | `fx_specter_saw_blood` | 终结技 | 未做 |  | run/ult_moves_b.gd:1660 |
| suzuran | B | `fx_sz_rslash1` | 终结技 | 未做 |  | run/ult_fx_c.gd:237 |
| suzuran | B | `fx_sz_rslash2` | 终结技 | 未做 |  | run/ult_fx_c.gd:237 |
| suzuran | B | `fx_sz_rslash3` | 终结技 | 未做 |  | run/ult_fx_c.gd:237 |
| suzuran | B | `fx_sz_slash1` | 终结技 | 未做 |  | run/ult_fx_c.gd:236 |
| suzuran | B | `fx_sz_slash2` | 终结技 | 未做 |  | run/ult_fx_c.gd:236 |
| suzuran | B | `fx_sz_slash3` | 终结技 | 未做 |  | run/ult_fx_c.gd:236 |
| suzuran | B | `fx_sz_vulpis` | 终结技 | 未做 |  | run/ult_fx_c.gd:229 |
| texas | A | `fx_ult_texas_scar_back` | 终结技 | 未做 |  | run/ult_moves.gd:403<br>run/ult_moves.gd:419 |
| texas | A | `fx_ult_texas_sword_front` | 终结技 | 未做 |  | run/ult_moves.gd:440 |
| ulpianus | C | `fx_ul_crack_fork` | 终结技 | 未做 |  | run/ult_moves.gd:1945<br>run/ult_moves.gd:1946<br>run/ult_moves_b.gd:564<br>run/ult_fx_c.gd:767 |
| ulpianus | C | `fx_ul_crack_fork2` | 终结技 | 未做 |  | run/ult_moves.gd:1946<br>run/ult_moves_b.gd:564<br>run/ult_fx_c.gd:767 |
| ulpianus | C | `fx_ul_crack_fork3` | 终结技 | 未做 |  | run/ult_moves.gd:1946<br>run/ult_moves_b.gd:564<br>run/ult_fx_c.gd:767 |
| ulpianus | C | `fx_ul_crack_fork4` | 终结技 | 未做 |  | run/ult_moves.gd:1946<br>run/ult_moves_b.gd:564<br>run/ult_fx_c.gd:767 |
| ulpianus | C | `fx_ul_crack_line` | 终结技 | 未做 |  | run/ult_moves.gd:1944 |
| ulpianus | C | `fx_ul_dust_ring` | 终结技 | 未做 |  | run/ult_moves.gd:2001<br>run/ult_moves.gd:2002<br>run/ult_moves.gd:2004 |
| ulpianus | C | `fx_ul_dust_wall` | 终结技 | 未做 |  | run/ult_moves.gd:2039<br>run/ult_moves.gd:2041<br>run/ult_moves.gd:2052<br>run/ult_pixfx.gd:10 |
| ulpianus | C | `fx_ul_rock` | 终结技 | 未做 |  | run/ult_moves_b.gd:1287<br>run/ult_pixfx.gd:9 |
| ulpianus | C | `fx_ul_rock2` | 终结技 | 未做 |  | run/ult_moves_b.gd:1287<br>run/ult_pixfx.gd:9 |
| ulpianus | C | `fx_ulpianus_chain_tile` | 终结技 | 未做 |  | run/ult_moves_c.gd:1747 |
| ulpianus | C | `fx_ult_ulpianus_anchor_front` | 终结技 | 未做 |  | run/ult_moves.gd:2064 |
| ulpianus | C | `fx_ult_ulpianus_burst_front` | 终结技 | 未做 |  | run/ult_moves.gd:1930 |
| ulpianus | C | `fx_ult_ulpianus_chain_front` | 终结技 | 未做 |  | run/ult_moves.gd:2083 |
| ulpianus | C | `fx_ult_ulpianus_crack_back` | 终结技 | 未做 |  | run/ult_moves.gd:180<br>run/ult_moves.gd:1924 |
| wisadel | D | `fx_cannon_burst` | 终结技 | 未做 |  | run/ult_moves_b.gd:1458 |
| wisadel | D | `fx_missile_explode` | 终结技 | 未做 |  | run/ult_moves_b.gd:1520 |
| wisadel | D | `fx_wd_cannon` | 终结技 | 未做 |  | run/ult_moves_b.gd:1490<br>run/ult_moves_b.gd:1490 |
| wisadel | D | `fx_wisadel_cannon` | 终结技 | 未做 |  | run/ult_moves_b.gd:1490<br>run/ult_moves_b.gd:1499 |
| wisadel | D | `fx_ws_crater` | 终结技 | 未做 |  | run/ult_moves_b.gd:1494<br>run/ult_moves_b.gd:1543 |
| 公共 | 组长 | `fx_dust_seq` | 终结技 | 未做 |  | run/ult_pixfx.gd:127 |
| 公共 | 组长 | `fx_px_burst1` | 终结技 | 未做 |  | run/ult_pixfx.gd:161 |
| 公共 | 组长 | `fx_px_burst2` | 终结技 | 未做 |  | run/ult_pixfx.gd:161 |
| 公共 | 组长 | `fx_px_burst_s` | 终结技 | 未做 |  | run/ult_pixfx.gd:162 |

## 4 公共（ob_fx / vfx / weapons …，组长与 fx-basic-atk）

覆盖：0 / 41（0%）

| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |
|---|---|---|---|---|---|---|
| 公共 | 组长 | `fx_angelina_levitate` | 公共 | 未做 |  | characters/data_operator.gd:1822<br>characters/data_operator.gd:1828 |
| 公共 | 组长 | `fx_arcane_hit` | 公共 | 未做 |  | run/weapons.gd:146 |
| 公共 | 组长 | `fx_beacon_ignite` | 公共 | 未做 |  | render/vfx.gd:1122<br>render/vfx.gd:1209<br>render/vfx.gd:1211 |
| 公共 | 组长 | `fx_bullet_hit` | 公共 | 未做 |  | run/weapons.gd:154 |
| 公共 | 组长 | `fx_circle_ghost` | 公共 | 未做 |  | render/vfx.gd:1026 |
| 公共 | 组长 | `fx_circle_steel` | 公共 | 未做 |  | render/vfx.gd:1022 |
| 公共 | 组长 | `fx_claw` | 公共 | 未做 |  | render/vfx.gd:938 |
| 公共 | 组长 | `fx_claw_double_green` | 公共 | 未做 |  | render/vfx.gd:1024 |
| 公共 | 组长 | `fx_col` | 公共 | 未做 |  | run/weapons.gd:119<br>run/weapons.gd:121<br>run/weapons.gd:146<br>run/weapons.gd:147 |
| 公共 | 组长 | `fx_death_dissolve` | 公共 | 未做 |  | render/vfx.gd:941<br>run/combat.gd:1351 |
| 公共 | 组长 | `fx_elite_spawn` | 公共 | 未做 |  | render/vfx.gd:1122<br>render/vfx.gd:1312<br>render/vfx.gd:1314<br>render/vfx.gd:1317 |
| 公共 | 组长 | `fx_ember` | 公共 | 未做 |  | render/vfx.gd:1122<br>render/vfx.gd:1190 |
| 公共 | 组长 | `fx_felspell` | 公共 | 未做 |  | render/vfx.gd:1029 |
| 公共 | 组长 | `fx_fire_explode` | 公共 | 未做 |  | run/weapons.gd:120 |
| 公共 | 组长 | `fx_heal_aura_green` | 公共 | 未做 |  | run/weapons.gd:54 |
| 公共 | 组长 | `fx_hit` | 公共 | 未做 |  | render/vfx.gd:904 |
| 公共 | 组长 | `fx_hit_flesh` | 公共 | 未做 |  | render/vfx.gd:897 |
| 公共 | 组长 | `fx_hit_shell` | 公共 | 未做 |  | render/vfx.gd:899 |
| 公共 | 组长 | `fx_hit_spirit` | 公共 | 未做 |  | render/vfx.gd:901 |
| 公共 | 组长 | `fx_knight_impact` | 公共 | 未做 |  | render/vfx.gd:1027 |
| 公共 | 组长 | `fx_levelup_pillar` | 公共 | 未做 |  | render/vfx.gd:1122<br>render/vfx.gd:1232<br>render/vfx.gd:1234 |
| 公共 | 组长 | `fx_mire_dissolve` | 公共 | 未做 |  | render/vfx.gd:1122<br>render/vfx.gd:1222 |
| 公共 | 组长 | `fx_missile_explode` | 公共 | 未做 |  | run/weapons.gd:120 |
| 公共 | 组长 | `fx_muzzle_flash` | 公共 | 未做 |  | render/vfx.gd:1020<br>render/vfx.gd:1021 |
| 公共 | 组长 | `fx_origin` | 公共 | 未做 |  | characters/blocks/ob_summon.gd:1613<br>characters/blocks/ob_summon.gd:2193 |
| 公共 | 组长 | `fx_rain` | 公共 | 未做 |  | characters/blocks/ob_core.gd:453<br>characters/blocks/ob_core.gd:827 |
| 公共 | 组长 | `fx_saria_amber_spot` | 公共 | 未做 |  | characters/blocks/ob_hw.gd:1355 |
| 公共 | 组长 | `fx_scatter` | 公共 | 未做 |  | characters/blocks/ob_core.gd:827 |
| 公共 | 组长 | `fx_slash` | 公共 | 未做 |  | render/vfx.gd:938 |
| 公共 | 组长 | `fx_slash_arc_deep` | 公共 | 未做 |  | render/vfx.gd:1025 |
| 公共 | 组长 | `fx_slash_arc_rose` | 公共 | 未做 |  | render/vfx.gd:1057 |
| 公共 | 组长 | `fx_star_hit_rose` | 公共 | 未做 |  | characters/blocks/ob_hw.gd:757 |
| 公共 | 组长 | `fx_suzuran_bigfox_trail` | 公共 | 未做 |  | characters/blocks/ob_hw.gd:1340 |
| 公共 | 组长 | `fx_suzuran_wisp` | 公共 | 未做 |  | characters/blocks/ob_hw.gd:1350 |
| 公共 | 组长 | `fx_ul_dust_ring` | 公共 | 未做 |  | render/vfx.gd:1251 |
| 公共 | 组长 | `fx_umbrella_slash` | 公共 | 未做 |  | render/vfx.gd:496<br>render/vfx.gd:516 |
| 公共 | 组长 | `fx_water_splash` | 公共 | 未做 |  | render/vfx.gd:1023<br>render/vfx.gd:1028<br>render/vfx.gd:1068 |
| 公共 | 组长 | `fx_xw` | 公共 | 未做 |  | characters/blocks/ob_fx.gd:326<br>characters/blocks/ob_fx.gd:326<br>characters/blocks/ob_fx.gd:327<br>characters/blocks/ob_fx.gd:328 |
| 公共 | 组长 | `proj_angelina_orb` | 公共 | 未做 |  | characters/data_operator.gd:1845<br>characters/data_operator.gd:1846 |
| 公共 | 组长 | `proj_lappland_sword` | 公共 | 未做 |  | characters/blocks/vis_growth.gd:30 |
| 公共 | 组长 | `proj_tide_blade_abyss` | 公共 | 未做 |  | render/vfx.gd:1082 |

## 5 敌方 / Boss（E 组）

覆盖：0 / 59（0%）

| 归属 | 组 | 特效名 | 出现在 | 状态 | 新名 / 理由 | 位置（前 4 处） |
|---|---|---|---|---|---|---|
| bishop | E | `fx_bishop_wave` | patterns | 未做 |  | enemies.json bishop/patterns/1/fx |
| boss_patterns | E | `fx_col` | 脚本 | 未做 |  | enemies/boss_patterns.gd:225 |
| boss_patterns | E | `fx_scale` | 脚本 | 未做 |  | enemies/boss_patterns.gd:227 |
| bullet_fx | E | `fx_col` | 脚本 | 未做 |  | render/bullet_fx.gd:192 |
| bullet_fx | E | `fx_px_bpop` | 脚本 | 未做 |  | render/bullet_fx.gd:36 |
| bullet_fx | E | `fx_px_btrail` | 脚本 | 未做 |  | render/bullet_fx.gd:39 |
| bullet_fx | E | `fx_px_burst1` | 脚本 | 未做 |  | render/bullet_fx.gd:40 |
| bullet_fx | E | `fx_px_burst2` | 脚本 | 未做 |  | render/bullet_fx.gd:40 |
| carmen | E | `fx_saint_clear_ring` | patterns | 未做 |  | enemies.json carmen/patterns/0/fx |
| enemy_ai | E | `fx_mother_throw` | 脚本 | 未做 |  | enemies/enemy_ai.gd:481 |
| final_attacks | E | `fx_knight_ice_hit` | 脚本 | 未做 |  | enemies/final_attacks.gd:310 |
| final_boss_materials | E | `fx_knight_crystal_break` | 脚本 | 未做 |  | render/final_boss_materials.gd:108 |
| final_boss_materials | E | `fx_knight_crystal_hold` | 脚本 | 未做 |  | render/final_boss_materials.gd:104 |
| final_boss_materials | E | `fx_knight_crystal_rise` | 脚本 | 未做 |  | render/final_boss_materials.gd:102<br>render/final_boss_materials.gd:112 |
| final_boss_materials | E | `fx_knight_ice_crest` | 脚本 | 未做 |  | render/final_boss_materials.gd:242<br>render/final_boss_materials.gd:251 |
| final_boss_materials | E | `fx_knight_ice_wall` | 脚本 | 未做 |  | render/final_boss_materials.gd:423<br>render/final_boss_materials.gd:435 |
| final_boss_materials | E | `proj_knight_ice` | 脚本 | 未做 |  | render/final_boss_materials.gd:234<br>render/final_boss_materials.gd:238 |
| final_boss_materials | E | `proj_knight_spear` | 脚本 | 未做 |  | render/final_boss_materials.gd:646<br>render/final_boss_materials.gd:648 |
| floater | E | `fx_nerve_hit` | hit_fx | 未做 |  | enemies.json floater/hit_fx |
| iberia | E | `fx_saint_clear_ring` | patterns | 未做 |  | enemies.json iberia/patterns/1/fx |
| iberia | E | `fx_saint_scatter` | patterns | 未做 |  | enemies.json iberia/patterns/0/fx |
| knight_boss | E | `fx_knight_ice_hit` | 脚本 | 未做 |  | enemies/bosses/knight_boss.gd:478 |
| knight_boss | E | `fx_knight_rebirth` | 脚本 | 未做 |  | enemies/bosses/knight_boss.gd:245<br>enemies/bosses/knight_boss.gd:570 |
| mimic | E | `fx_mimic_bite` | atk_fx | 未做 |  | enemies.json mimic/atk_fx |
| nest | E | `fx_nest_sweep` | atk_fx | 未做 |  | enemies.json nest/atk_fx |
| offspring | E | `proj_offspring_spore` | shot_tex | 未做 |  | enemies.json offspring/shot_tex |
| path | E | `fx_path_correct_ring` | patterns | 未做 |  | enemies.json path/patterns/0/fx |
| pocket | E | `fx_pocket_burst` | burst_fx | 未做 |  | enemies.json pocket/burst_fx |
| pocket | E | `fx_pocket_puddle` | puddle_fx | 未做 |  | enemies.json pocket/puddle_fx |
| reaper | E | `fx_reaper_scythe` | atk_fx | 未做 |  | enemies.json reaper/atk_fx |
| runner | E | `fx_runner_blast` | blast_fx | 未做 |  | enemies.json runner/blast_fx |
| shot_pool | E | `fx_acid_splash` | 脚本 | 未做 |  | enemies/shot_pool.gd:64<br>enemies/shot_pool.gd:263 |
| shot_pool | E | `fx_brood_land` | 脚本 | 未做 |  | enemies/shot_pool.gd:60<br>enemies/shot_pool.gd:61 |
| skimmer | E | `fx_corrode_hit` | hit_fx | 未做 |  | enemies.json skimmer/hit_fx |
| skimmer | E | `fx_skimmer_muzzle` | muzzle_fx | 未做 |  | enemies.json skimmer/muzzle_fx |
| skimmer | E | `proj_skimmer_corrode` | shot_tex | 未做 |  | enemies.json skimmer/shot_tex |
| slider | E | `fx_slider_dash` | dash_fx | 未做 |  | enemies.json slider/dash_fx |
| spitter | E | `fx_corrode_hit_acid` | hit_fx | 未做 |  | enemies.json spitter/hit_fx |
| spitter | E | `fx_spitter_land` | land_fx | 未做 |  | enemies.json spitter/land_fx |
| spitter | E | `proj_spitter_acid` | lob_tex | 未做 |  | enemies.json spitter/lob_tex |
| stone | E | `fx_rock_hit` | hit_fx | 未做 |  | enemies.json stone/hit_fx |
| telegraph | E | `fx_archon_breath` | 脚本 | 未做 |  | enemies/telegraph.gd:506 |
| telegraph | E | `fx_carmen_smash` | 脚本 | 未做 |  | enemies/telegraph.gd:496 |
| telegraph | E | `fx_immortal_burst` | 脚本 | 未做 |  | enemies/telegraph.gd:513 |
| telegraph | E | `fx_ishar_line_muzzle` | 脚本 | 未做 |  | enemies/telegraph.gd:379 |
| telegraph | E | `fx_ishar_maw_red` | 脚本 | 未做 |  | enemies/telegraph.gd:580 |
| telegraph | E | `fx_izumik_share` | 脚本 | 未做 |  | enemies/telegraph.gd:484 |
| telegraph | E | `fx_knight_frost_burst` | 脚本 | 未做 |  | enemies/telegraph.gd:430 |
| telegraph | E | `fx_knight_impact` | 脚本 | 未做 |  | enemies/telegraph.gd:322 |
| telegraph | E | `fx_knight_thrust` | 脚本 | 未做 |  | enemies/telegraph.gd:578 |
| telegraph | E | `fx_paranoia_gaze_hit` | 脚本 | 未做 |  | enemies/telegraph.gd:476 |
| telegraph | E | `fx_paranoia_howl` | 脚本 | 未做 |  | enemies/telegraph.gd:484 |
| telegraph | E | `fx_paranoia_stack` | 脚本 | 未做 |  | enemies/telegraph.gd:451 |
| telegraph | E | `fx_path_fractal_rise` | 脚本 | 未做 |  | enemies/telegraph.gd:631 |
| telegraph | E | `fx_saint_shell_burst` | 脚本 | 未做 |  | enemies/telegraph.gd:410 |
| telegraph | E | `fx_slash_heavy_steel` | 脚本 | 未做 |  | enemies/telegraph.gd:401 |
| telegraph | E | `fx_water_splash` | 脚本 | 未做 |  | enemies/telegraph.gd:340<br>enemies/telegraph.gd:348 |
| tracer | E | `fx_tracer_thrust` | atk_fx | 未做 |  | enemies.json tracer/atk_fx |
| tracer | E | `fx_tracer_thrust_enraged` | atk_fx_enraged | 未做 |  | enemies.json tracer/atk_fx_enraged |

## 6 动态拼名（不进上表，归属组手查）

- `fx_kp_%s_hit%s`  render/boss_beam.gd:81
- `fx_kp_%s_mid%s`  render/boss_beam.gd:80
- `fx_kp_%s_src%s`  render/boss_beam.gd:79
