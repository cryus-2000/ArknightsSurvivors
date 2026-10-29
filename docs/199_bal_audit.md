# docs/199 balance 旋钮对账（10-29，claude/bal-audit）

> 来源：架构评审 arch_review_1029 §11。`Bal.v("段/键", 缺省)` 的字面缺省值和 `data/balance.json` 的现值不一致时，**运行时一律取 json 值**（缺省只在键缺失时才用），所以把代码缺省值改成 json 值，**运行结果不变**，也不碰 json 数值。扫描脚本：`tools/bal_audit.py`（只读；`--apply` 才改代码）。

## 1. 结果

- 带字面键 + 字面缺省值的读点 **901** 键；缺省与 json 不同 **170** 键 / 225 个读点（评审说 168 键，本次 170，差在评审后新增读点）。
- 已改 **208** 个读点；**17** 个读点（15 键）留给对应会话，原因是这些文件正被改：game.gd（队长属性）、character.gd（移动）、combat.gd `kill()`、hud_squad.gd，见 §3。
- 同一键在不同读点缺省互不一致的原有 3 键（`lamp/dark_taken`、`lamp/dark_enemy`、`final/escort_every`）改完一致；剩下 6 键（均在 §3 的暂缓读点里）合入暂缓项后一致。
- 只写在代码里、json 没有的键 **366** 键 / 441 个读点，见 §4，只列不动（要不要进 json 是设计决定，进 json 时按这里的缺省值写，运行结果不变）。

## 2. 已改：缺省值 → json 值（读点格式：文件:行 旧→新）

| 键 | 读点（旧 → 新） |
|---|---|
| `beacon/lamp` | intro.gd:478 5.0 → 20 |
| `boss/fullhp_guard_cd` | combat.gd:431 30.0 → 60 |
| `boss/fullhp_guard_left` | combat.gd:424 0.10 → 0.05 |
| `boss/hit_cap_pct` | combat.gd:1182 0.0 → 0.04 |
| `boss/ishar_break_t` | ishar_combos.gd:165 3.0 → 6.0 |
| `boss/ishar_break_t3` | ishar_combos.gd:165 2.6 → 4.8 |
| `boss/ishar_break_taken` | ishar.gd:459 1.7 → 2.0 |
| `boss/ishar_combo_dmg` | ishar.gd:247 0.8 → 0.85 |
| `boss/ishar_combo_gap` | ishar_combos.gd:76 0.3 → 0.26 |
| `boss/ishar_corrode` | ishar_combos.gd:359 0.5 → 1.0 |
| `boss/ishar_layer_regen` | ishar.gd:528 5.0 → 10.0 |
| `boss/ishar_nonbreak_taken` | ishar.gd:461 1.0 → 0.9 |
| `boss/ishar_p1_scale` | ishar_encounter.gd:22 0.6 → 1.0 |
| `boss/ishar_shot_mult` | ishar_combos.gd:358 1.2 → 1.4 |
| `boss/ishar_song_heal_cut` | ishar_combos.gd:600 0.5 → 0.7；combat.gd:1264 0.5 → 0.7 |
| `boss/ishar_web_floor` | ishar.gd:462 0.4 → 0.5 |
| `boss/ishar_web_heal` | ishar.gd:345 0.0003 → 0 |
| `boss/ishar_web_layer` | ishar.gd:460 0.025 → 0.01；ishar.gd:514 0.025 → 0.01 |
| `boss/ishar_web_shield` | ishar.gd:337 0.4 → 0.2 |
| `boss/ishar_zone_linger` | ishar_combos.gd:582 4.0 → 6.0 |
| `boss/ishar_zone_tick` | ishar_combos.gd:609 0.16 → 0.3 |
| `boss/izumik_break_taken` | izumik.gd:886 1.1 → 1.4 |
| `boss/izumik_bullet_mult` | izumik.gd:754 0.8 → 1.15 |
| `boss/izumik_mire_life` | izumik.gd:865 8.0 → 10.0 |
| `boss/izumik_taken_out` | izumik.gd:886 0.7 → 0.47 |
| `boss/knight_big_walk` | knight_boss.gd:780 2.5 → 1.5 |
| `boss/leader_2s_cap` | combat.gd:140 0.50 → 0.68；combat.gd:409 0.50 → 0.68 |
| `boss/mid_pattern_dmg` | mid_cards.gd:39 0.8 → 0.7 |
| `boss/paranoia_aura_taken` | paranoia.gd:310 0.5 → 0.65 |
| `boss/paranoia_drop_t` | paranoia.gd:190 4.0 → 5.0；boss_beam.gd:203 4.0 → 5.0 |
| `boss/paranoia_hover_taken` | paranoia.gd:309 0.5 → 0.65 |
| `boss/paranoia_revive` | paranoia.gd:381 0.8 → 0.5 |
| `boss/paranoia_rush_mult` | paranoia_combos.gd:548 1.0 → 1.3 |
| `command/hpbar_style` | hud_allyhp.gd:35 0.0 → 4；hud_allyhp.gd:206 0.0 → 4；hud_allyhp.gd:208 0.0 → 4；tour.gd:103 0.0 → 4 |
| `crate/bot_below` | bot.gd:266 0.75 → 0.85；autotest.gd:1707 0.75 → 0.85 |
| `crate/pack_p` | spawner.gd:611 0.0 → 0.9 |
| `crate/pick_below` | pickups.gd:164 1.0 → 0.9 |
| `enemy/alive_cap_wait` | spawner.gd:748 0.0 → 10 |
| `enemy/bullet_dmg_mult` | shot_pool.gd:44 1.0 → 0.75；shot_pool.gd:189 1.0 → 0.75 |
| `enemy/close_ring_arc` | spawner.gd:504 50.0 → 115 |
| `enemy/close_ring_rot` | spawner.gd:437 20.0 → 35 |
| `enemy/corrode_mult` | combat.gd:130 2.0 → 1.0 |
| `enemy/corrode_pool_cap` | combat.gd:133 0.0 → 0.3 |
| `enemy/density` | operator_defs.gd:51 1.0 → 0.4；gallery.gd:522 1.0 → 0.4；spawner.gd:967 1.0 → 0.4 |
| `enemy/density_dmg_exp` | gallery.gd:525 1.0 → 0.5；spawner.gd:1001 1.0 → 0.5；spawner.gd:1002 1.0 → 0.5 |
| `enemy/density_hp_exp` | gallery.gd:524 1.0 → 0.75；spawner.gd:996 1.0 → 0.75 |
| `enemy/density_kill_comp` | relic_fx.gd:1425 0.0 → 1 |
| `enemy/dmg_div` | spawner.gd:865 260.0 → 340 |
| `enemy/dmg_early` | gallery.gd:519 1.0 → 1.3；spawner.gd:868 1.0 → 1.3 |
| `enemy/dmg_gain_early` | gallery.gd:519 1.0 → 1.15；spawner.gd:876 1.0 → 1.15 |
| `enemy/early_horde_dmg` | spawner.gd:532 0.7 → 1.0 |
| `enemy/early_horde_mult` | spawner.gd:464 1.0 → 1.8 |
| `enemy/early_spawn_mult` | spawner.gd:355 1.0 → 0.9 |
| `enemy/elite_during_boss` | spawner.gd:385 1.0 → 0.5 |
| `enemy/first_elite` | spawner.gd:14 45.0 → 60 |
| `enemy/horde_base` | spawner.gd:461 24.0 → 20 |
| `enemy/horde_count_mult` | spawner.gd:468 1.0 → 1.5 |
| `enemy/horde_div` | spawner.gd:461 9.0 → 12 |
| `enemy/horde_dmg` | spawner.gd:532 0.7 → 1.4 |
| `enemy/horde_fixed_1` | spawner.gd:419 -1.0 → 225；spawner.gd:420 -1.0 → 225 |
| `enemy/horde_fixed_2` | spawner.gd:419 -1.0 → 300 |
| `enemy/horde_fixed_3` | spawner.gd:419 -1.0 → 375 |
| `enemy/horde_grow_until` | spawner.gd:461 1.0e9 → 570 |
| `enemy/horde_hp_mult` | spawner.gd:535 1.0 → 2.0 |
| `enemy/horde_hunt_count_mult` | spawner.gd:467 1.0 → 1.5 |
| `enemy/horde_hunt_gap_deg` | spawner.gd:481 22.0 → 16 |
| `enemy/horde_hunt_rush` | spawner.gd:1058 0.7 → 0.9 |
| `enemy/horde_jitter` | spawner.gd:1053 0.0 → 0.4 |
| `enemy/horde_spd_spread` | spawner.gd:1046 0.0 → 0.15 |
| `enemy/horde_wob_deg` | spawner.gd:1054 0.0 → 22 |
| `enemy/horde_wob_f` | spawner.gd:1056 1.5 → 1.6 |
| `enemy/hp_div` | balance.gd:2 120.0 → 110；relic_db.gd:25 120.0 → 110；combat.gd:759 120.0 → 110 |
| `enemy/hp_late_div` | relic_db.gd:26 300.0 → 120；combat.gd:759 300.0 → 120 |
| `enemy/merge_dmg_exp` | spawner.gd:741 0.5 → 1 |
| `enemy/scale` | spawner.gd:971 1.0 → 1.5 |
| `enemy/spawn_base` | spawner.gd:340 1.6 → 2.3 |
| `enemy/spawn_div` | spawner.gd:338 30.0 → 40 |
| `enemy/spawn_knee` | spawner.gd:339 1.0e9 → 520 |
| `enemy/spd_gain` | spawner.gd:847 1.0 → 1.05 |
| `enemy/trim_early_dmg` | gallery.gd:526 1.0 → 1.08；spawner.gd:1019 1.0 → 1.08 |
| `enemy/trim_early_hp` | gallery.gd:526 1.0 → 1.08；spawner.gd:1018 1.0 → 1.08 |
| `enemy/trim_late_hp` | spawner.gd:1022 1.0 → 0.92 |
| `enemy/windup_mult` | enemy_ai.gd:72 1.0 → 0.7 |
| `enemy/wound_dot` | combat.gd:893 0.005 → 0.0025 |
| `enemy/wound_max` | combat.gd:855 4.0 → 3 |
| `final/escort_every` | spawner.gd:411 0.0 → 50；spawner.gd:443 75.0 → 50 |
| `final/escort_first` | spawner.gd:412 20.0 → 15；spawner.gd:413 20.0 → 15 |
| `final/escort_n` | spawner.gd:474 12.0 → 16 |
| `final/escort_stop_frac` | spawner.gd:411 0.0 → 0.5 |
| `fx/kill_big_r` | vfx.gd:401 20.0 → 16 |
| `fx/tell_dim_alpha` | world.gd:4286 0.35 → 0.2；world.gd:4544 0.35 → 0.2 |
| `fx/tell_full_max` | world.gd:4404 8 → 4 |
| `fx/text_nudge_max` | vfx.gd:645 3 → 5 |
| `fx/text_nudge_t` | vfx.gd:646 0.3 → 0.6 |
| `lamp/dark_enemy` | enemies.gd:291 1.2 → 1.1；intro.gd:475 1.2 → 1.1 |
| `lamp/dark_taken` | combat.gd:100 1.15 → 1.05；intro.gd:475 1.15 → 1.05 |
| `lamp/hit_base` | combat.gd:123 4.0 → 2；intro.gd:477 4.0 → 2 |
| `lamp/hit_scale` | combat.gd:123 30.0 → 18；intro.gd:477 30.0 → 18 |
| `lamp/mire_creep_r` | enemies.gd:669 0.0 → 380；enemies.gd:685 0.0 → 380；enemies.gd:696 0.0 → 380 |
| `lamp/mire_spawn_iv` | spawner.gd:627 0.0 → 0.4 |
| `lamp/mire_spawn_near` | spawner.gd:628 0.0 → 0.4 |
| `lamp/mire_ward_dmg` | enemies.gd:641 0.0 → 0.8 |
| `lamp/mire_ward_r` | enemies.gd:668 0.0 → 200；enemies.gd:679 0.0 → 200；enemies.gd:696 0.0 → 200 |
| `levelup/force_recruit_level_1` | progression.gd:160 6 → 5 |
| `levelup/force_recruit_level_3` | progression.gd:160 12 → 9 |
| `levelup/heal_low_hp_mult` | progression.gd:95 1.5 → 1.3 |
| `levelup/heal_weight` | progression.gd:93 1.5 → 1.2 |
| `levelup/recruit_chance` | progression.gd:204 0.45 → 0.55 |
| `levelup/recruit_from_level` | progression.gd:210 5 → 4 |
| `meta/shatter_mult` | combat.gd:736 2.0 → 3.0 |
| `protect/any_2s_cap` | combat.gd:382 0.0 → 0.7 |
| `protect/any_excess_mult` | combat.gd:388 1.0 → 0.6 |
| `relic/big_extra` | progression.gd:342 0 → 1 |
| `relic/chest_rare` | progression.gd:326 0.0 → 1 |
| `relic/coin_sp` | relic_fx.gd:762 0.08 → 0.12 |
| `relic/core_gate` | relic_fx.gd:229 0.0 → 1 |
| `relic/core_gate_late` | relic_fx.gd:229 450.0 → 180 |
| `relic/elite_drop_chance` | combat.gd:1462 0.3 → 0.25 |
| `relic/elite_drop_from` | combat.gd:1463 0.0 → 120 |
| `relic/judge_cap` | relic_fx.gd:1459 0.03 → 0.04 |
| `relic/mid1_shift` | endings.gd:174 0.0 → 35；endings.gd:175 0.0 → 35 |
| `relic/wish_rare` | progression.gd:306 0.0 → 2 |
| `relic/wrath_dmg` | relic_db.gd:28 30.0 → 45.0；relic_fx.gd:922 30.0 → 45.0 |
| `render/ambient_gain` | post_fx.gd:146 1.0 → 1.05；look.gd:106 1.0 → 1.05；optical.gd:608 1.0 → 1.05 |
| `render/ambient_mult` | map.gd:63 1.0 → 1.9 |
| `render/dash_tell_alpha` | world.gd:4283 1.0 → 0.55 |
| `render/dash_tell_flow` | world.gd:4289 1.0 → 0 |
| `render/dash_tell_half` | world.gd:3318 10.0 → 6；world.gd:3321 10.0 → 6 |
| `render/dash_tell_style` | world.gd:3074 0 → 2；world.gd:3312 0 → 2 |
| `render/dash_tell_white` | world.gd:4311 1.0 → 0 |
| `render/declutter` | declutter.gd:81 0 → 3 |
| `render/elite_rim` | world.gd:267 0.0 → 0.55 |
| `render/ember_n` | optical_particles.gd:120 16.0 → 32 |
| `render/enemy_pop_black` | art.gd:247 0.10 → 0.08 |
| `render/enemy_pop_contrast` | art.gd:248 1.35 → 1.28 |
| `render/enemy_pop_sat` | art.gd:249 0.3 → 0.25 |
| `render/env_bright` | map.gd:97 1.0 → 1.15 |
| `render/env_sat` | map.gd:97 1.0 → 0.55 |
| `render/ground_glow_warm` | optical.gd:490 0.0 → 0.4 |
| `render/lead_emph` | world.gd:244 0 → 1 |
| `render/look` | look.gd:46 0 → 5 |
| `render/mire_alpha` | map.gd:907 1.0 → 0.8 |
| `render/mire_tint_b` | map.gd:905 1.0 → 0.8 |
| `render/mire_tint_g` | map.gd:905 1.0 → 0.95 |
| `render/mire_tint_r` | map.gd:905 1.0 → 0.5 |
| `render/optical_col_ebullet_h` | optical.gd:88 0.95 → 0.54 |
| `render/optical_col_ebullet_s` | optical.gd:88 0.85 → 0.8 |
| `render/optical_ground_glow` | optical.gd:482 0.06 → 0.1 |
| `render/pfx_cap` | squad.gd:1057 0.0 → 30 |
| `render/warm_spores` | optical_particles.gd:121 0.0 → 26 |
| `render/zone_dark_b` | world.gd:4857 0.22 → 0.12 |
| `render/zone_dark_g` | world.gd:4857 0.03 → 0.08 |
| `render/zone_dark_r` | world.gd:4857 0.16 → 0.03 |
| `shop/relic_step` | shop.gd:59 0.0 → 0.3；shop.gd:68 0.0 → 0.3 |
| `squad/dodge_comp_taken` | initial_stats.gd:129 1.0 → 0.9 |
| `squad/hp_per_member` | squad.gd:248 0.0 → 0.15；squad.gd:302 0.0 → 0.15；intro.gd:474 0.0 → 0.15 |
| `squad/leader_hp_mult` | initial_stats.gd:59 1.0 → 0.9 |
| `squad/leader_speed_mult` | gallery.gd:541 1.0 → 1.1；initial_stats.gd:69 1.0 → 1.1 |
| `squad/op_atk_base` | doctor.gd:436 1.0 → 0.9；operator_defs.gd:49 1.0 → 0.9；initial_stats.gd:60 1.0 → 0.9；initial_stats.gd:103 1.0 → 0.9 |
| `squad/regen_per_member` | squad.gd:272 0.0 → 0.15 |
| `sustain/regen_card` | doctor.gd:402 0.6 → 0.4；doctor.gd:426 0.6 → 0.4 |

## 3. 暂缓（文件正被别的会话改，合入后跑 `python tools/bal_audit.py --apply` 即可补齐）

| 键 | 读点（现缺省 → json 值） |
|---|---|
| `command/hpbar_style` | screens/hud_squad.gd:273 0.0 → 4 |
| `command/rush_dist` | characters/character.gd:1780 260.0 → 320 |
| `crate/magnet_p` | run/combat.gd:1303 0.0 → 0.1 |
| `crate/pack_p` | run/combat.gd:1298 0.0 → 0.9 |
| `crate/pack_pct` | run/combat.gd:1301 0.25 → 0.3 |
| `crate/shield_p` | run/combat.gd:1305 0.0 → 0.1 |
| `pickup/heal_low_cap` | run/combat.gd:1409 0.0 → 2 |
| `pickup/heal_low_hp` | run/combat.gd:1406 0.0 → 0.7 |
| `pickup/heal_low_mult` | run/combat.gd:1410 1.0 → 2.0 |
| `pickup/magnet_cap` | run/combat.gd:1395 0.0 → 2；run/combat.gd:1397 0.0 → 2 |
| `pickup/magnet_kill_chance` | run/combat.gd:1399 0.0025 → 0.00375；run/combat.gd:1421 0.0025 → 0.00375 |
| `squad/dodge_comp_taken` | game.gd:902 1.0 → 0.9 |
| `squad/leader_hp_mult` | game.gd:892 1.0 → 0.9 |
| `squad/leader_speed_mult` | game.gd:897 1.0 → 1.1 |
| `squad/op_atk_base` | game.gd:894 1.0 → 0.9 |

## 4. 只写在代码里的键（json 没有）

共 366 键。格式：键 = 缺省值（读点）。

**ai**（2）：`boss_focus`=1.0（op_api.gd）、`boss_focus_guard`=60.0（op_api.gd）

**beacon**（2）：`block_t`=30.0（intro.gd）、`need`=2.5（intro.gd）

**boss**（237）：`act_min_final`=13.0（combat.gd）、`act_min_mid`=6.0（combat.gd）、`acts_demo_len`=7.0（autotest.gd）、`arena_r`=520.0（spawner.gd）、`atk_slow_as_slow_mult`=0.67（combat.gd）、`bishop_panic`=1.0（bishop.gd）、`break_mult`=1.4（boss_base.gd 等5处）、`break_t`=3.0（combat.gd）、`budget_on`=0.0（combat.gd）、`budget_over`=0.35（combat.gd）、`budget_store`=4.0（combat.gd 等2处）、`bullet_hit_scale`=0.6（shot_pool.gd）、`carmen_dmg_mult`=1.5（saint.gd 等2处）、`carmen_fire_drift`=44.0（saint.gd）、`carmen_fire_drift_p2`=54.0（saint.gd）、`carmen_fire_gap`=80.0（saint.gd）、`carmen_fire_gap_min`=46.0（saint.gd）、`carmen_fire_life`=6.0（saint.gd）、`carmen_fire_mult`=0.65（saint.gd）、`carmen_gap_shrink`=12.0（saint.gd）、`carmen_hop_cd`=9.0（saint.gd）、`carmen_hop_spd`=480.0（saint.gd）、`carmen_hp_k`=2.4（saint.gd 等2处）、`carmen_lane_gap`=1.3（saint.gd）、`carmen_lane_mult`=1.56（saint.gd）、`carmen_reload`=3.0（saint.gd）、`carmen_reload_hop`=720.0（saint.gd）、`carmen_reload_taken`=1.5（saint.gd）、`carmen_sword`=8.0（saint.gd）、`corrode_pool_cap`=0.40（combat.gd）、`dot_cap_per_s`=0.04（combat.gd）、`final_duel`=1.0（spawner.gd）、`final_mob_cap`=120.0（spawner.gd）、`fullhp_guard_at`=0.9（combat.gd）、`fullhp_guard_combo`=2.0（combat.gd）、`gate_inv`=0.8（combat.gd 等3处）、`gates_on`=1.0（combat.gd）、`horde_defer_max`=40.0（spawner.gd）、`hp_mult_floor`=0.8（spawner.gd）、`iberia_ember_arm`=0.6（saint.gd）、`iberia_ember_cd`=1.8（saint.gd）、`iberia_ember_cd_p2`=1.3（saint.gd）、`iberia_ember_lead`=0.7（saint.gd）、`iberia_ember_life`=2.6（saint.gd）、`iberia_ember_max`=6.0（saint.gd）、`iberia_ember_mult`=0.14（saint.gd）、`iberia_ember_r`=44.0（saint.gd）、`iberia_hp_k`=2.9（saint.gd 等2处）、`iberia_judge_mult`=2.6（saint.gd）、`iberia_reload`=3.0（saint.gd）、`iberia_reload_p2`=2.6（saint.gd）、`iberia_reload_r`=160.0（saint.gd）、`iberia_reload_taken`=1.8（saint.gd）、`iberia_reload_walk`=1.8（saint.gd）、`iberia_rise_shot`=0.8（saint.gd）、`iberia_swing_mult`=1.2（saint.gd 等2处）、`iberia_swing_r`=90.0（saint.gd）、`iberia_tri_cr`=38.0（saint.gd）、`iberia_tri_mult`=1.2（saint.gd）、`iberia_tri_r`=95.0（saint.gd）、`immortal_auto_fan`=0.0（immortal.gd）、`immortal_light_rage`=1.2（immortal.gd）、`ishar_a1_reach`=320.0（ishar_combos.gd）、`ishar_break_web`=1.0（ishar.gd）、`ishar_choir_cd`=6.0（ishar.gd）、`ishar_combos`=1.0（ishar.gd）、`ishar_echo_mult`=0.6（ishar.gd 等2处）、`ishar_echo_ring_mult`=0.4（ishar.gd）、`ishar_eye_hp`=0.025（ishar.gd 等2处）、`ishar_fan_lock`=0.6（ishar.gd）、`ishar_fan_step`=0.3（ishar.gd）、`ishar_fence_min`=320.0（ishar_combos.gd）、`ishar_fence_t`=18.0（ishar_combos.gd）、`ishar_gate_haste`=0.8（ishar.gd）、`ishar_line_pause`=2.0（ishar.gd）、`ishar_relink`=3.0（ishar.gd）、`ishar_reso_cd`=6.0（ishar.gd）、`ishar_seek_t`=2.0（ishar_combos.gd）、`ishar_song_gap_px`=110.0（ishar.gd）、`ishar_song_mult`=0.7（ishar.gd）、`ishar_song_spd`=220.0（ishar.gd 等2处）、`ishar_sweep_acc`=1.4（ishar_combos.gd）、`ishar_sweep_max`=0.5（ishar_combos.gd）、`ishar_sweep_t`=2.4（ishar_combos.gd 等3处）、`ishar_twin_gap`=0.32（ishar_combos.gd）、`ishar_vortex_spin`=1.8（ishar_combos.gd）、`ishar_web_cap`=6.0（ishar.gd）、`ishar_web_cap2`=10.0（ishar.gd）、`ishar_web_each`=0.1（ishar.gd）、`izumik_absorb_cut`=0.0（izumik.gd）、`izumik_absorb_need`=5.0（izumik.gd）、`izumik_batch_cd`=12.0（izumik.gd）、`izumik_batch_spd`=45.0（izumik.gd）、`izumik_brood_n`=4.0（izumik.gd）、`izumik_brood_spd`=60.0（izumik.gd）、`izumik_cards`=1.0（izumik.gd 等2处）、`izumik_cocoon_t`=4.0（izumik.gd 等2处）、`izumik_current_mult`=1.0（izumik.gd）、`izumik_lamp_r`=120.0（izumik.gd 等2处）、`izumik_lamp_touch`=40.0（izumik.gd）、`izumik_layer_dmg`=0.08（izumik.gd）、`izumik_layer_max`=5.0（izumik.gd）、`izumik_learn`=20.0（izumik.gd）、`izumik_mire_max`=6.0（izumik.gd）、`izumik_mire_r`=90.0（izumik.gd）、`izumik_recover_mult`=1.25（izumik.gd）、`izumik_share_all_cap`=0.2（izumik.gd）、`izumik_share_all_cd`=12.0（izumik.gd）、`izumik_share_all_charge`=1.6（izumik.gd）、`izumik_share_all_warn`=3.0（izumik.gd）、`izumik_share_mult`=1.2（izumik.gd 等2处）、`izumik_share_small`=0.5（izumik.gd 等2处）、`izumik_stack_dmg`=0.15（izumik.gd）、`izumik_stack_heal`=0.05（izumik.gd）、`izumik_stack_max`=4.0（izumik.gd）、`izumik_tentacle_gap`=0.6（izumik.gd）、`izumik_tentacle_n`=4.0（izumik.gd 等2处）、`izumik_tentacle_r`=110.0（izumik.gd）、`izumik_wave_cap`=0.25（izumik.gd）、`izumik_wave_cd`=25.0（izumik.gd）、`izumik_wave_cd2`=20.0（izumik.gd）、`izumik_wave_charge`=5.0（izumik.gd）、`knight_armor_cast`=1.0（knight_boss.gd）、`knight_breath`=2.5（knight_boss.gd）、`knight_brk_far`=1.0（knight_boss.gd）、`knight_charge_mult`=1.7（knight_boss.gd 等4处）、`knight_cold_decay`=2.5（knight_boss.gd 等2处）、`knight_cold_fill`=3.0（knight_boss.gd）、`knight_cold_hot`=1.5（knight_boss.gd）、`knight_cold_r`=140.0（knight_boss.gd）、`knight_cold_r3`=180.0（knight_boss.gd）、`knight_combo_brk1`=2.4（knight_boss.gd）、`knight_combo_brk2`=3.0（knight_boss.gd）、`knight_crack`=1.0（knight_boss.gd）、`knight_drive`=1.0（knight_boss.gd）、`knight_drive_acc`=1.2（knight_boss.gd）、`knight_drive_brk`=1.0（knight_boss.gd）、`knight_drive_max`=3.0（knight_boss.gd）、`knight_drive_stun`=2.5（knight_boss.gd）、`knight_drive_turn`=0.52（knight_boss.gd）、`knight_drive_v0`=320.0（knight_boss.gd）、`knight_drive_v1`=900.0（knight_boss.gd）、`knight_frostbite`=1.5（knight_boss.gd）、`knight_frostbite_mult`=1.75（knight_boss.gd）、`knight_hug_r`=130.0（knight_boss.gd）、`knight_hug_spin`=1.5（knight_boss.gd）、`knight_hug_t`=3.5（knight_boss.gd）、`knight_hunt`=1.0（knight_boss.gd）、`knight_ice_dmg_k`=0.8（knight_boss.gd 等4处）、`knight_ice_life`=3.0（knight_boss.gd 等5处）、`knight_lap`=1.0（knight_boss.gd）、`knight_lap_brk`=2.0（knight_boss.gd）、`knight_lap_lance`=0.7（knight_boss.gd）、`knight_lap_t`=4.0（knight_boss.gd）、`knight_leap`=1.0（knight_boss.gd）、`knight_leap_cd`=12.0（knight_boss.gd）、`knight_leap_len`=280.0（knight_boss.gd）、`knight_p2_chain`=2.0（knight_boss.gd 等2处）、`knight_prisms`=1.0（knight_boss.gd）、`knight_rebirth_wave`=16.0（knight_boss.gd）、`knight_reborn_spd`=0.5（knight_boss.gd 等2处）、`knight_roll_brk`=3.0（knight_boss.gd）、`knight_roll_t`=4.0（knight_boss.gd 等2处）、`knight_shards`=1.0（knight_boss.gd）、`knight_spear_brk`=1.0（knight_boss.gd）、`knight_spear_cd`=8.0（knight_boss.gd 等2处）、`knight_spin_brk`=2.0（knight_boss.gd 等2处）、`knight_triple_cd`=20.0（knight_boss.gd）、`last_hold`=0.03（combat.gd）、`leader_hit_cap`=0.40（combat.gd 等2处）、`mid_mob_cap`=160.0（spawner.gd）、`mire_max`=12.0（shot_pool.gd）、`mire_pct`=0.01（enemies.gd）、`move_floor`=0.7（combat.gd 等2处）、`pair_race`=8.0（boss_ai.gd 等3处）、`pair_revive_hp`=0.5（boss_ai.gd）、`pair_revives`=2.0（boss_ai.gd 等2处）、`pair_sep`=360.0（boss_base.gd）、`pair_shield_gap`=0.25（boss_base.gd）、`pair_shield_gap2`=0.15（boss_base.gd）、`pair_shield_mult`=0.4（boss_base.gd）、`pair_swap_cd`=10.0（bishop.gd）、`paranoia_arena2`=520.0（paranoia.gd）、`paranoia_aura_aspd`=0.10（paranoia.gd 等2处）、`paranoia_aura_aspd2`=0.15（paranoia.gd 等2处）、`paranoia_aura_off`=5.0（paranoia.gd）、`paranoia_aura_r`=220.0（paranoia.gd）、`paranoia_aura_r2`=300.0（paranoia.gd）、`paranoia_cocoon`=8.0（paranoia.gd）、`paranoia_combos`=1.0（paranoia_combos.gd）、`paranoia_decoy_hits`=3.0（paranoia.gd）、`paranoia_decoy_respawn`=6.0（paranoia.gd）、`paranoia_drop_cd`=2.0（paranoia.gd）、`paranoia_drop_taken`=1.8（paranoia.gd）、`paranoia_gaze_mult`=1.56（paranoia.gd）、`paranoia_hatch_break`=5.0（paranoia.gd）、`paranoia_howl_cd`=6.0（paranoia.gd）、`paranoia_p2_at_gate`=1.0（paranoia.gd 等2处）、`paranoia_shell`=0.08（paranoia.gd）、`paranoia_shell_min`=4.0（paranoia.gd）、`part_chip`=0.05（combat.gd）、`part_chip_r`=160.0（combat.gd）、`path_charge_near`=110.0（path.gd）、`path_fr_every`=2.5（path.gd）、`path_fr_spd`=60.0（path.gd）、`path_lay_cd`=10.0（path.gd）、`path_life`=16.0（path.gd）、`path_lost`=3.0（path.gd 等2处）、`path_node_r`=24.0（path.gd）、`path_pat_evo_cd`=3.6（path.gd）、`path_pat_reflow_cd`=3.4（path.gd）、`path_pat_seed_cd`=2.6（path.gd）、`path_pat_tree_cd`=3.2（path.gd）、`path_reroute`=2.0（path.gd）、`path_return_heal`=0.03（path.gd）、`saint_break`=5.0（saint.gd）、`saint_break_dmg`=0.05（saint.gd）、`saint_dmg_mult`=0.8（saint.gd 等2处）、`saint_melee`=8.0（saint.gd 等2处）、`saint_ranged_max`=6.0（saint.gd）、`saint_reload_gap`=4.0（saint.gd）、`saint_stand`=1.5（saint.gd 等3处）、`saint_volley_mult`=1.2（saint.gd）、`stun_as_slow_mult`=0.7（combat.gd 等2处）、`stun_as_slow_t`=0.5（combat.gd）、`tide_armor`=0.7（boss_base.gd）、`tide_break_taken`=2.0（boss_base.gd）、`tide_brk1`=3.0（bishop.gd）、`tide_brk2`=3.4（bishop.gd）、`tide_combo_cd1`=7.5（bishop.gd）、`tide_combo_cd2`=7.0（bishop.gd）、`tide_link_cd`=4.5（boss_ai.gd）、`tide_pat_mirror_cd`=2.6（bishop.gd）、`tide_pat_ring_cd`=3.0（bishop.gd）、`tide_pat_wall_cd`=3.2（bishop.gd）、`tough_first`=25.0（combat.gd）、`tough_per_stun`=5.0（enemies.gd）

**bot**（2）：`circle_gap`=50.0（bot.gd）、`event_greedy`=1（endings.gd）

**enemy**（33）：`affix_armor`=0.75（endings.gd 等3处）、`affix_ramp`=180.0（spawner.gd）、`affix_shield`=0.30（endings.gd 等3处）、`apop_dash`=40.0（game.gd）、`apop_decay`=15.0（combat.gd）、`apop_pause`=4.0（combat.gd）、`ctrl_aspd_cap`=0.30（combat.gd）、`ctrl_move_cap`=0.45（combat.gd）、`first_horde`=75.0（game.gd）、`frost_aspd`=0.08（combat.gd）、`frost_dur`=3.0（world.gd 等3处）、`frost_immune`=4.0（combat.gd）、`frost_root`=0.6（combat.gd）、`frost_slow`=0.12（combat.gd）、`max_alive_low`=300.0（spawner.gd）、`mimic_scream_lamp`=7.0（enemy_ai.gd）、`mimic_scream_nerve`=1.6（enemy_ai.gd）、`mire_flat`=3.0（enemies.gd）、`mire_pct`=0.015（enemies.gd）、`nerve_burst`=0.12（combat.gd）、`nerve_decay`=10.0（combat.gd）、`nerve_hit_mult`=0.0（gallery.gd 等3处）、`nerve_lock`=5.0（combat.gd）、`nerve_max`=100.0（combat.gd）、`nerve_mire`=12.0（combat.gd）、`nerve_stun`=1.2（combat.gd）、`reaper_first_extra`=0.2（enemy_ai.gd）、`reaper_windup`=0.8（enemy_ai.gd）、`root_immune`=3.0（combat.gd）、`tier_dmg_scale`=1.0（spawner.gd）、`tier_hp_scale`=1.0（spawner.gd）、`wound_dur`=6.0（combat.gd 等2处）、`wound_heal_cut`=0.10（combat.gd 等2处）

**fx**（14）：`boom_dedup_r`=24.0（seg_wisadel.gd）、`boom_dedup_t`=0.2（seg_wisadel.gd）、`boom_scale_exact`=1.0（seg_wisadel.gd）、`boss_shake_px`=4.0（vfx.gd）、`boss_shake_t`=0.1（vfx.gd 等2处）、`bullet_grains`=1.0（bullet_fx.gd）、`contact_sparks`=0（vfx.gd）、`grains`=1.0（fx_grains.gd）、`hitstop_gap`=0.5（vfx.gd）、`melee_arc_reach`=0.7（world.gd）、`melee_arc_span`=105.0（vfx.gd 等2处）、`shield_style`=1.0（world.gd）、`ulp_burst`=1.0（ulpianus_charge_fx.gd）、`ulp_charge_grains`=1.0（ulpianus_charge_fx.gd）

**manual**（9）：`aim_cone_deg`=45.0（character.gd 等2处）、`atk_buf`=0.3（doctor.gd）、`click_cast`=1.0（doctor.gd）、`land_empty`=0.8（character.gd）、`m_linger`=1.2（ob_summon.gd）、`mouse_idle`=8.0（doctor.gd）、`point_charge`=0.6（doctor.gd 等3处）、`point_min`=150.0（doctor.gd 等2处）、`touch_full`=110.0（doctor.gd）

**outro**（3）：`dim_t`=1.6（defeat_outro.gd）、`slow`=0.25（defeat_outro.gd）、`slow_t`=1.2（defeat_outro.gd）

**render**（63）：`boss_fx_grains`=1.0（telegraph.gd 等2处）、`boss_grain_burst`=160.0（boss_beam.gd）、`boss_grain_rate`=600.0（boss_beam.gd）、`bullet_fx`=1.0（bullet_fx.gd）、`bullet_fx_burst`=160.0（bullet_fx.gd）、`bullet_fx_rate`=700.0（bullet_fx.gd）、`bullet_fx_sweep`=1600.0（bullet_fx.gd）、`burden_lite`=0.0（world.gd）、`cam_round`=1.0（world.gd）、`dash_flash`=0.6（world.gd）、`dash_pull`=3.0（world.gd）、`dash_short`=0.45（world.gd）、`dash_tell`=1.0（world.gd）、`ebullet_boss_danger`=0.0（optical.gd）、`enemy_dash_sparks`=1.0（world.gd）、`foe_ring_fx`=1.0（world.gd）、`grains_mobile_k`=0.35（fx_grains.gd）、`ishar_act_style`=1.0（ishar_tell_draw.gd）、`ishar_song_live`=1.0（world.gd）、`ishar_tell`=1.0（ishar_tell_draw.gd）、`knight_frost_tell`=1.0（telegraph_draw.gd 等2处）、`knight_ice_grains`=1.0（final_attack_grains.gd）、`lead_dir`=0.0（squad.gd）、`lead_hitmark`=0（vfx.gd）、`lead_top`=0.0（squad.gd）、`low_grains`=0.4（fx_grains.gd）、`mate_desat`=0.35（world.gd）、`mate_fx`=0.55（world.gd）、`mate_layer`=0.0（world.gd）、`mate_numbers`=0（vfx.gd）、`mire_anim`=1.0（map.gd）、`nest_aura_lite`=0.0（world.gd）、`optical_caustics`=0.02（optical.gd）、`optical_emissive_th`=0.72（optical.gd）、`optical_glow`=0.9（optical.gd）、`optical_ground`=1.0（map.gd 等2处）、`optical_int_zoom`=0.0（optical.gd）、`optical_kill_body`=1.0（combat.gd）、`optical_kill_debris`=1.0（combat.gd）、`optical_layer_follow`=1.0（optical.gd）、`optical_lowres`=1.0（optical.gd）、`optical_lut`=1.0（optical.gd）、`optical_ops_hi`=0.0（optical.gd）、`optical_pixel`=1.0（optical.gd）、`optical_pool_dark`=1.0（optical.gd）、`optical_pool_r`=0.7（optical.gd）、`optical_sat`=1.0（optical.gd）、`optical_sea`=0.55（optical.gd）、`optical_trail`=1.0（optical.gd）、`optical_view_h`=450.0（optical.gd 等2处）、`optical_view_h_phone`=360.0（optical.gd 等2处）、`paranoia_bubble_skin`=1.0（paranoia_combo_draw.gd）、`phone_view_h`=300.0（settings.gd）、`rage_tint`=0.0（world.gd）、`rim`=0.0（look.gd 等3处）、`rim_floor`=0.15（look.gd）、`rim_px`=2.0（look.gd）、`static_fps`=20.0（game.gd）、`tell_circle_calm`=0.0（world.gd）、`view_h_desk`=1080.0（settings.gd）、`view_h_phone`=585.0（settings.gd）、`warn_flash_fill`=1.0（telegraph_draw.gd）、`warn_hatch_flow`=1.0（telegraph_draw.gd）

**web**（1）：`font_clear_minutely`=0.0（game.gd）

## 5. Bal.v 路径缓存（架构评审 §11 ②）

**改法**（`core/balance.gd`）：`Bal.v` 原来每次调用都 `path.split("/")` 再逐段查字典（combat / spawner 等热路径每帧几百次）。现在按路径缓存解析结果（路径 → 数值或「没有 / 不是数」）。数据在 `_load` 里一次写定（`--bal=` 覆盖和 `_preset` 都在里面），之后只读，所以缓存安全。`vi` 走 `v`；`sec` 保持原语义（返回 `_store` 里的那份引用）。

**测试兼容**：约 20 个测试直接写 `Bal._data["段"]["键"] = x`。`_data` 现在是个属性：外部每读一次它（几乎都是为了改它）就丢一次缓存；`sec()` 每次调用也丢缓存；`reload()` 自带，这类写法照旧可用。**例外（10-30 补）**：「先拿到整段引用、过一阵再改 / 还原」的写法（`var ops = Bal._data.get("operators")` … `ops["saria"] = x`、`var cmd = Bal.sec("command")` … `cmd["boss_rush"] = 0`）写入发生在取引用之后，缓存不知道，读过的键会留着旧值。持有引用的测试每次改 / 还原后要调 `Bal.clear_cache()`；已补：`command_wheel_cases.gd`（boss_rush）、`prot_test.gd`（ops.saria 净化、squad.regen_t1 / t2、beacon.shade_deg，并让 `ok()` 每条断言后清一次）；`command_ai_test.gd` 由指挥会话在 6cf116560 补。内部一律用 `_store`。另：prot_test 里 11 条失败原来有两个来源——docs/178 把 json 的 `fullhp_guard_left / cd` 调成 5% / 60 秒而用例按 10% / 30 秒写（现在测试开头钉回旧值）；以及「代码缺省为关」的 protect 段（缺省对齐 json 后不再是关，现在显式写关）。

**量化**
- 微基准（Godot 4.7 无头，6 个路径轮换 120 万次调用）：原写法 1.08 µs / 次，只缓存拆分数组 0.94，缓存数值 **0.47**（本改法）。
- 真实读点数：标准场景（seed 13、斯卡蒂 + 德克萨斯 + 能天使）7–9 分钟无头每帧约 **420 次** `Bal.v`（含 `sec` 约 0.15 次 / 帧）；有画面时世界层 / HUD 的 `render/*` 读点更多。按 0.6 µs 的差，桌面约省 0.25 ms / 帧，网页（慢 2–3 倍）约 0.5–0.8 ms / 帧。
- 同局轮换（`--fixed-fps 60 --optab=60`，探针副本里加开关，窗口放副屏，本机当时 10 个其他 Godot、帧均值 50 ms，所以只看差）：8–10 分钟 新 / 旧 50.67 / 51.03 ms（**−0.36 ms，−0.7%**），0–8 分钟 61.08 / 61.36（−0.28 ms）。方向与微基准一致，量级在噪声边上，网页上收益应更明显。
- 同 seed TRACE（对 integ-1029 `bfa2bcd0`，300 秒）：seed 13 斯卡蒂 301 行、seed 1 水月 301 行、seed 3 德克萨斯 207 行（两边同时倒下）、seed 7 能天使 301 行，**四局逐行相同**。

## 6. 工具

`python tools/bal_audit.py`：只读，打印统计（明细 `build/bal_audit.json`）；`--apply` 把读点缺省改成 json 值（跳过 §3 的暂缓文件）。别的会话的分支合入后再跑一次 `--apply` 即可补齐 §3。
