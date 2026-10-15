# docs/101 附表 A：干员侧对敌人数据的直接访问（逐处清单）

由 docs/101 §7.3.10 引用。行号是 main f239070b 的快照；「现状 / 接口」列是 10-15 落地（claude/op-cc-api 8af32b80）后的实际接口名。
扫描基于 main f239070b 的 `game/scripts/characters/blocks/*.gd`、`data_operator.gd`、`character.gd`（`op_api.gd` 本身是接口层，不算）。
扫描办法：按函数认出「敌人变量」（取自 `g.enemies[…]` / `query_ids` / `nearest_enemies` / `arc_targets` / `los_targets` 的循环变量，或函数里读过 `.dead / .boss / .elite / .maxhp` 的标识符），收集它们的字段读写；写的部分逐条人工核对过（剔除特效记录、锚状态等同名字典 6 个函数，补上经 `a.e` / `lk.e` 间接写的 2 处）。读的部分按函数汇总。

## A.1 写位置 / 击退（9 处）

| 文件:行 | 函数 | 写法 | 现状 / 接口 |
|---|---|---|---|
| `ob_core.gd:499` | `slow_soft` | `e.pos -= (e.pos - last) * pct` | 留（位置可直写；可选 `o.nudge(e, delta)`） |
| `seg_irene.gd:278` | `_h3_air_tick` | `e.kb = Vector2.ZERO` | 已改：并进 `o.set_air(e, h, true)` |
| `seg_saria.gd:246` | `_h4sa_tick_e` | `e.pos -= d * pct` | 留（位置可直写；可选 `o.nudge(e, delta)`） |
| `seg_saria.gd:331` | `_h4_pillars_tick` | `e.pos = ep + push` | 留（位置可直写；可选 `o.nudge(e, delta)`） |
| `seg_ulpianus.gd:257` | `_hw4_anchor` | `e.pos = (hk.from as Vector2).lerp(hk.to, kr)` | 留（位置可直写；可选 `o.hold_at(e, p)`） |
| `seg_ulpianus.gd:258` | `_hw4_anchor` | `e.kb = Vector2.ZERO` | 留（清零可直写；可选 `o.hold_at(e, p)`） |
| `seg_ulpianus.gd:508` | `_hw4_launched` | `e.kb = Vector2.ZERO` | 已改：并进 `o.set_air(e, h, true)` |
| `seg_ulpianus.gd:965` | `_hw5_hooks` | `e.pos = (dg.from as Vector2).lerp(dg.spot, kr)` | 留（位置可直写；可选 `o.hold_at(e, p)`） |
| `seg_ulpianus.gd:966` | `_hw5_hooks` | `e.kb = Vector2.ZERO` | 留（清零可直写；可选 `o.hold_at(e, p)`） |

## A.2 写 hp / 状态（61 处；hp 本身 0 处直写，全部经 `deal_damage` → `combat.damage`）

| 文件:行 | 函数 | 字段 | 写法 | 现状 / 接口 |
|---|---|---|---|---|
| `ob_core.gd:411` | `apply_status` | `stun` | `e.stun = maxf(e.stun, float(s.dur) * k)` | 已改：`o.add_cc(e, stun)` |
| `ob_core.gd:413` | `apply_status` | `slow` | `e.slow = maxf(e.slow, float(s.dur) * (1.0 if e.boss else k))` | 已改：`o.add_cc(e, -INF, slow)` |
| `ob_core.gd:419` | `apply_status` | `wl_t` | `e["wl_t"] = maxf(float(e.get("wl_t", 0.0)), g.t + float(s.dur))` | 不改（各干员标记，字典直写） |
| `ob_core.gd:420` | `apply_status` | `wl_kb` | `e["wl_kb"] = maxf(was, float(s.kb_mult))` | 不改（各干员标记，字典直写） |
| `ob_core.gd:426` | `apply_status` | `stun` | `e.stun = maxf(e.stun, float(s.dur) * k)` | 已改：`o.add_cc(e, stun)` |
| `ob_hw.gd:373` | `hw_requiem_stack` | `requiem_n` | `e["requiem_n"] = n` | 不改（各干员标记，字典直写） |
| `ob_hw.gd:374` | `hw_requiem_stack` | `requiem_k` | `e["requiem_k"] = float(rq.get("per", 0.06)) * n` | 不改（各干员标记，字典直写） |
| `ob_hw.gd:375` | `hw_requiem_stack` | `requiem` | `e["requiem"] = float(s.dur)` | 不改（各干员标记，字典直写） |
| `ob_summon.gd:372` | `_sm_decoy` | `aggro` | `e.aggro = s.pos` | 已改：`o.set_aggro(e, p)` |
| `ob_summon.gd:436` | `sm_strike` | `stun` | `e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))` | 已改：`o.add_cc(e, stun)` |
| `ob_summon.gd:549` | `seal_apply` | `seal_txt` | `e["seal_txt"] = g.t + 1.5` | 不改（各干员标记，字典直写） |
| `ob_summon.gd:555` | `seal_apply` | `seal_imm` | `e["seal_imm"] = g.t + dur + float(s.get("boss_immune", 10.0))` | 不改（各干员标记，字典直写） |
| `ob_summon.gd:561` | `seal_apply` | `seal_t` | `e["seal_t"] = maxf(float(e.get("seal_t", 0.0)), g.t + dur)` | 不改（各干员标记，字典直写） |
| `ob_summon.gd:562` | `seal_apply` | `seal_by` | `e["seal_by"] = o.id` | 不改（各干员标记，字典直写） |
| `seg_angelina.gd:85` | `lift` | `stun` | `e.stun = maxf(e.stun, a.dur - a.t)` | 已改：`o.add_cc(e, stun)` |
| `seg_angelina.gd:88` | `lift` | `stun` | `e.stun = maxf(e.stun, dur)` | 已改：`o.add_cc(e, stun)` |
| `seg_angelina.gd:102` | `airborne_tick` | `air` | `e.air = 0.0 if e.dead or a.t >= a.dur else air_height(a)` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_angelina.gd:108` | `airborne_tick` | `air` | `a.e.air = 0.0` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_eyjafjalla.gd:213` | `hw_status` | `requiem_v` | `e["requiem_v"] = float(o.base("requiem_bonus", 0.15))` | 不改（各干员标记，字典直写） |
| `seg_eyjafjalla.gd:216` | `hw_status` | `requiem` | `e["requiem"] = float(s.dur)` | 不改（各干员标记，字典直写） |
| `seg_eyjafjalla.gd:222` | `hw_status` | `melt_t` | `e["melt_t"] = maxf(float(e.get("melt_t", 0.0)), float(g.t) + float(s.dur))` | 不改（各干员标记，字典直写） |
| `seg_eyjafjalla.gd:223` | `hw_status` | `melt_v` | `e["melt_v"] = maxf(mv, float(s.get("value", 0.08)))` | 不改（各干员标记，字典直写） |
| `seg_eyjafjalla.gd:229` | `hw_status` | `aura_weak` | `e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), float(s.dur))` | 不改（各干员标记，字典直写） |
| `seg_hoshiguma.gd:88` | `exec_line` | `stun` | `e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))` | 已改：`o.add_cc(e, stun)` |
| `seg_irene.gd:254` | `h3_launch` | `stun` | `e.stun = maxf(e.stun, dur)` | 已改：`o.add_cc(e, stun)` |
| `seg_irene.gd:273` | `_h3_air_tick` | `air` | `e.air = 0.0` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_irene.gd:277` | `_h3_air_tick` | `air` | `e.air = sin(k * PI) * a.h` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_irene.gd:280` | `_h3_air_tick` | `air` | `e.air = 0.0` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_logos.gd:301` | `hw_link_tick 一带` | `slow` | `lk.e.slow = maxf(lk.e.slow, float(b.get("slow", 0.6)) * ramp)` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_lumen.gd:144` | `_h3_bolts_tick` | `lit` | `e["lit"] = float(bt.get("lit", 3.0))` | 不改（各干员标记，字典直写） |
| `seg_lumen.gd:367` | `_h3_rain_tick` | `lit` | `e["lit"] = maxf(e.get("lit", 0.0), 1.0)` | 不改（各干员标记，字典直写） |
| `seg_lumen.gd:424` | `_h3_beam_tick` | `lit` | `e["lit"] = 3.0` | 不改（各干员标记，字典直写） |
| `seg_lumen.gd:711` | `_e3_beam_fire` | `lit` | `e["lit"] = 3.0` | 不改（各干员标记，字典直写） |
| `seg_mizuki.gd:191` | `_h3_umbrella` | `stun` | `e.stun = maxf(e.stun, stun)` | 已改：`o.add_cc(e, stun)` |
| `seg_mizuki.gd:273` | `_h3_tentacle` | `stun` | `target.stun = max(target.stun, stun if stun > 0.0 else float(tb.get("stun_min", ` | 已改：`o.add_cc(e, stun)` |
| `seg_mizuki.gd:363` | `_h3_run_delayed` | `stun` | `e.stun = maxf(e.stun, float(ec.get("stun", 0.3)))` | 已改：`o.add_cc(e, stun)` |
| `seg_mizuki.gd:709` | `_e3_sting` | `stun` | `e.stun = maxf(e.stun, sd)` | 已改：`o.add_cc(e, stun)` |
| `seg_saria.gd:172` | `_h4sa_tick` | `slow` | `e.slow = maxf(e.slow, float(gr.get("slow", 0.5)))` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_saria.gd:211` | `_h4sa_tick` | `slow` | `e2.slow = maxf(e2.slow, float(cb.get("slow", 0.5)))` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_saria.gd:212` | `_h4sa_tick` | `aura_weak` | `e2["aura_weak"] = maxf(float(e2.get("aura_weak", 0.0)), float(cb.get("weak", 0.2` | 不改（各干员标记，字典直写） |
| `seg_saria.gd:465` | `_h4_shots_tick` | `slow` | `e.slow = maxf(e.slow, float(s.slow))` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_siege.gd:61` | `_h4_hammer_release` | `stun` | `e.stun = maxf(e.stun, float(hv.get("stun", 0.8)) * (0.5 if e.elite else 1.0))` | 已改：`o.add_cc(e, stun)` |
| `seg_specter.gd:255` | `_h3_doll_tick` | `slow` | `e.slow = maxf(e.slow, float(au.get("slow", 1.0)))` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_suzuran.gd:175` | `_h4_brand_apply` | `frag_v` | `e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), v)` | 不改（各干员标记，字典直写） |
| `seg_suzuran.gd:177` | `_h4_brand_apply` | `frag_v` | `e["frag_v"] = v` | 不改（各干员标记，字典直写） |
| `seg_suzuran.gd:178` | `_h4_brand_apply` | `frag_t` | `e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + dur)` | 不改（各干员标记，字典直写） |
| `seg_suzuran.gd:261` | `_h4sz_tick` | `slow` | `e.slow = maxf(e.slow, slow)` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_suzuran.gd:263` | `_h4sz_tick` | `aura_weak` | `e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), wv)` | 不改（各干员标记，字典直写） |
| `seg_suzuran.gd:290` | `_h4_bigfox_tick` | `slow` | `e.slow = maxf(e.slow, 1.0)` | 已改：`o.add_cc(e, -INF, slow)` |
| `seg_suzuran.gd:393` | `_h4_seals_tick` | `stun` | `best.stun = maxf(best.stun, st)` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:259` | `_hw4_anchor` | `stun` | `e.stun = maxf(e.stun, 0.2)` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:358` | `_hw_reel_arrive` | `stun` | `e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (0.5 if e.elite else 1.0) + 0.` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:389` | `_hw_reel_slam` | `stun` | `e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (0.5 if e.elite or e.boss else` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:418` | `_hw_zip_land` | `stun` | `e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (sb if e.boss else (se if e.el` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:458` | `_hw_drag_in` | `stun` | `e.stun = maxf(e.stun, 0.3)` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:491` | `_hw_launch` | `stun` | `e.stun = maxf(e.stun, dur)` | 已改：`o.add_cc(e, stun)` |
| `seg_ulpianus.gd:506` | `_hw4_launched` | `air` | `e.air = 0.0 if e.dead or k >= 1.0 else sin(k * PI) * l.h` | 已改：`o.set_air(e, h, hold_kb)`（清不清击退照原样由调用方传） |
| `seg_ulpianus.gd:967` | `_hw5_hooks` | `stun` | `e.stun = maxf(e.stun, 0.15)` | 已改：`o.add_cc(e, stun)` |
| `seg_wisadel.gd:309` | `_h4wd_on_kill` | `wis_det` | `e["wis_det"] = true` | 不改（各干员标记，字典直写） |
| `seg_wisadel.gd:527` | `_h4_explode` | `stun` | `e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))` | 已改：`o.add_cc(e, stun)` |
| `character.gd:1365` | `melee_hit` | `stun` | `e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))` | 已改：`o.add_cc(e, stun)` |

## A.3 查询网格 / 敌人数组 / 敌弹池（161 处）

| 文件:行 | 函数 | 访问 | 现状 / 接口 |
|---|---|---|---|
| `ob_core.gd:493` | `slow_soft` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_core.gd:494` | `slow_soft` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_core.gd:529` | `orbit_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_core.gd:530` | `orbit_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_core.gd:616` | `displace_at` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_core.gd:617` | `displace_at` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_elite.gd:83` | `el_area_only` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `ob_elite.gd:266` | `_el_boom_sweep` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_elite.gd:267` | `_el_boom_sweep` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_summon.gd:214` | `_sm_pick` | `densest_point` | `op_api.densest_point`（已是接口） |
| `ob_summon.gd:217` | `_sm_pick` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `ob_summon.gd:219` | `_sm_pick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_summon.gd:220` | `_sm_pick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_summon.gd:228` | `_sm_pick` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `ob_summon.gd:368` | `_sm_decoy` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_summon.gd:369` | `_sm_decoy` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_summon.gd:376` | `_sm_decoy` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_summon.gd:377` | `_sm_decoy` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_summon.gd:423` | `sm_strike` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `ob_summon.gd:424` | `sm_strike` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `ob_summon.gd:1310` | `mf_step` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_angelina.gd:135` | `field_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_angelina.gd:136` | `field_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_exusiai.gd:288` | `_exu_bullets` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_exusiai.gd:289` | `_exu_bullets` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_exusiai.gd:328` | `_exu_next` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_exusiai.gd:329` | `_exu_next` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_eyjafjalla.gd:92` | `_hw_extra_targets` | `los_targets` | `op_api.los_targets`（已是接口） |
| `seg_eyjafjalla.gd:153` | `hw_lob` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_eyjafjalla.gd:159` | `hw_lob` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_eyjafjalla.gd:198` | `hw_affect` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_eyjafjalla.gd:796` | `_hw5_lob_land` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_eyjafjalla.gd:797` | `_hw5_lob_land` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_hoshiguma.gd:60` | `exec_line` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_hoshiguma.gd:64` | `exec_line` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_hoshiguma.gd:65` | `exec_line` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_irene.gd:142` | `_h3_thrust` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_irene.gd:143` | `_h3_thrust` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_irene.gd:291` | `h3_lift_around` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_irene.gd:292` | `h3_lift_around` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_logos.gd:122` | `_hw3_bolts` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_logos.gd:152` | `_hw3_bolts` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_logos.gd:207` | `hw_shape_hit` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_logos.gd:208` | `hw_shape_hit` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_logos.gd:234` | `hw_execute` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_logos.gd:258` | `hw_lock_start` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_logos.gd:259` | `hw_lock_start` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_logos.gd:355` | `_hw_fan_best` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_logos.gd:356` | `_hw_fan_best` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_logos.gd:413` | `_hw3_fan` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_logos.gd:414` | `_hw3_fan` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_logos.gd:426` | `_hw3_fan` | `g.ebullets` | 已改：`g.shots.slow_in(pred, f, tag)` / `g.shots.cancel_in(pred) -> PackedVector2Array` |
| `seg_logos.gd:435` | `_hw3_fan` | `g.ebullets` | 已改：`g.shots.slow_in(pred, f, tag)` / `g.shots.cancel_in(pred) -> PackedVector2Array` |
| `seg_logos.gd:714` | `hw_link` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_lumen.gd:136` | `_h3_bolts_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:137` | `_h3_bolts_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_lumen.gd:150` | `_h3_bolts_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:151` | `_h3_bolts_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_lumen.gd:363` | `_h3_rain_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:364` | `_h3_rain_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_lumen.gd:416` | `_h3_beam_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:417` | `_h3_beam_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_lumen.gd:652` | `_e3_refract` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:653` | `_e3_refract` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_lumen.gd:696` | `_e3_beam_fire` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_lumen.gd:697` | `_e3_beam_fire` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:47` | `_h3_low_hp_near` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_mizuki.gd:48` | `_h3_low_hp_near` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:169` | `_h3_umbrella` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_mizuki.gd:222` | `_h3_umbrella` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_mizuki.gd:227` | `_h3_umbrella` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_mizuki.gd:307` | `_h3_stakes_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_mizuki.gd:308` | `_h3_stakes_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:326` | `_h3_run_delayed` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_mizuki.gd:327` | `_h3_run_delayed` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:343` | `_h3_run_delayed` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:356` | `_h3_run_delayed` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_mizuki.gd:382` | `h3_cast_push` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_mizuki.gd:383` | `h3_cast_push` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:524` | `_h3mz_draw_over` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_mizuki.gd:525` | `_h3mz_draw_over` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:558` | `_h3mz_draw_add` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_mizuki.gd:687` | `_e3_jelly_pick` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_saria.gd:164` | `_h4sa_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_saria.gd:165` | `_h4sa_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:207` | `_h4sa_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_saria.gd:208` | `_h4sa_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:285` | `_h4_pillars_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_saria.gd:286` | `_h4_pillars_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:350` | `_h4_pillars_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:427` | `_h4_orbs_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_saria.gd:428` | `_h4_orbs_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:457` | `_h4_shots_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_saria.gd:458` | `_h4_shots_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_saria.gd:577` | `h4_saria_heal` | `los_targets` | `op_api.los_targets`（已是接口） |
| `seg_siege.gd:41` | `_h4_hammer_release` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_siege.gd:137` | `_h4_breach` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_siege.gd:138` | `_h4_breach` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_siege.gd:259` | `_h4_next_cluster` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_siege.gd:261` | `_h4_next_cluster` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_siege.gd:268` | `_h4_next_cluster` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_siege.gd:269` | `_h4_next_cluster` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_siege.gd:277` | `_h4_next_cluster` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_siege.gd:301` | `_h4sg_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_siege.gd:302` | `_h4sg_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_skadi.gd:49` | `_hw_waves` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_skadi.gd:50` | `_hw_waves` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_skalter.gd:42` | `e5_area` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_specter.gd:75` | `_h3_spin` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_specter.gd:147` | `_h3_rings_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_specter.gd:148` | `_h3_rings_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_specter.gd:248` | `_h3_doll_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_specter.gd:249` | `_h3_doll_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_specter.gd:508` | `_e3_flash_tick` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `seg_suzuran.gd:137` | `_h4_fox_release` | `los_targets` | `op_api.los_targets`（已是接口） |
| `seg_suzuran.gd:257` | `_h4sz_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:258` | `_h4sz_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_suzuran.gd:282` | `_h4_bigfox_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:283` | `_h4_bigfox_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_suzuran.gd:335` | `_h4_brand_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:336` | `_h4_brand_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_suzuran.gd:361` | `_h4_brand_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:362` | `_h4_brand_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_suzuran.gd:384` | `_h4_seals_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:385` | `_h4_seals_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_suzuran.gd:419` | `_h4_hearth_tick` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_suzuran.gd:420` | `_h4_hearth_tick` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_texas.gd:251` | `_tx_sweep` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_texas.gd:252` | `_tx_sweep` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_texas.gd:531` | `tx_rain` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_texas.gd:532` | `tx_rain` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:153` | `hw_tether_target` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:154` | `hw_tether_target` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:164` | `hw_tether_target` | `densest_point` | `op_api.densest_point`（已是接口） |
| `seg_ulpianus.gd:166` | `hw_tether_target` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_ulpianus.gd:177` | `hw_tether_aim_dir` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:178` | `hw_tether_aim_dir` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:318` | `_hw_start_reel` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_ulpianus.gd:382` | `_hw_reel_slam` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:383` | `_hw_reel_slam` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:411` | `_hw_zip_land` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:412` | `_hw_zip_land` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:445` | `_hw_drag_in` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_ulpianus.gd:470` | `_hw_open_rift` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:471` | `_hw_open_rift` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_ulpianus.gd:922` | `hw_hook_start` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_ulpianus.gd:928` | `hw_hook_start` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_ulpianus.gd:1005` | `_hw5_hook_drag_start` | `query_ids` | `op_api.query_ids` → `enemies_sys.query`（已是接口；原生后换底层网格，调用点不动） |
| `seg_ulpianus.gd:1006` | `_hw5_hook_drag_start` | `g.enemies` | `g.enemies[j]` 按查询结果下标取字典——原生后要保证下标 ↔ 字典映射稳定（或改 `enemies_sys.get(id)`） |
| `seg_wisadel.gd:51` | `_h4_wd_target` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_wisadel.gd:74` | `_h4_exec_target` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_wisadel.gd:140` | `_h4_twin` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_wisadel.gd:423` | `_h4_soul_cannon_target` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_wisadel.gd:478` | `_h4_souls_sync` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `seg_wisadel.gd:516` | `_h4_explode` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |
| `character.gd:622` | `aim_land` | `g.enemies_sys.nearest` | 已改：`nearest_raw(n, d, origin)`（op_api，不带 Boss 优先） |
| `character.gd:648` | `aim_targets` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `character.gd:651` | `aim_targets` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `character.gd:654` | `aim_targets` | `g.enemies_sys.nearest` | 已改：`nearest_raw(n, d, origin)`（op_api，不带 Boss 优先） |
| `character.gd:1317` | `melee_spot` | `nearest_enemies` | `op_api.nearest_enemies`（已是接口） |
| `character.gd:1353` | `melee_hit` | `arc_targets` | `op_api.arc_targets` → `enemies_sys.arc_hit`（已是接口） |

## A.4 只读位置 / 半径 / 标记（按函数汇总，734 处）

字段说明：`pos / r / dead / id / boss / elite` 是绝大多数；带 * 的是原生 B 段会写的列（读它们要在 B 段回写之后）。

| 文件 | 函数（首行） | 次数 | 读到的字段 |
|---|---|---|---|
| `ob_core.gd` | `apply_status`（388） | 20 | boss, pos*, elite, r, stun, wl_t, dead, slow, wl_kb |
| `ob_core.gd` | `slow_soft`（495） | 8 | pos*, id, dead, boss |
| `ob_core.gd` | `orbit_tick`（531） | 9 | dead, pos*, id, boss, r, elite |
| `ob_core.gd` | `displace_at`（618） | 7 | pos*, r, dead, elite |
| `ob_elite.gd` | `el_area_only`（84） | 5 | dead, wl_t, air, elite, boss |
| `ob_elite.gd` | `_el_boom_sweep`（268） | 13 | r, dead, id, pos*, elite, boss |
| `ob_fx.gd` | `fx_spawn`（111） | 2 | pos*, r |
| `ob_hw.gd` | `hw_requiem_stack`（372） | 2 | requiem_n, requiem |
| `ob_summon.gd` | `_sm_ok`（195） | 3 | dead, friendly, chest |
| `ob_summon.gd` | `_hp_frac`（199） | 2 | hp, maxhp |
| `ob_summon.gd` | `_sm_pick`（221） | 3 | pos*, id |
| `ob_summon.gd` | `sm_tick`（255） | 2 | dead, seal_t |
| `ob_summon.gd` | `_sm_decoy`（370） | 17 | dead, chest, ai, pos*, dmg, id, boss, coma, under, dormant, r |
| `ob_summon.gd` | `sm_strike`（425） | 12 | dead, elite, boss, pos*, r, stun |
| `ob_summon.gd` | `seal_apply`（541） | 16 | boss, pos*, r, elite, seal_t, dead, chest, friendly, seal_imm, seal_txt, id |
| `ob_summon.gd` | `sealed`（569） | 1 | seal_t |
| `ob_summon.gd` | `sm_draw_over`（580） | 6 | pos*, dead, seal_by, seal_t, r |
| `ob_summon.gd` | `mf_step`（1299） | 13 | pos*, dead, r |
| `ob_summon.gd` | `_mf_points`（1592） | 2 | pos*, r |
| `seg_angelina.gd` | `_heavy`（16） | 1 | type |
| `seg_angelina.gd` | `kb_taken`（22） | 2 | wl_kb, wl_t |
| `seg_angelina.gd` | `_movable`（27） | 5 | dead, boss, part, chest, ai |
| `seg_angelina.gd` | `displace_one`（40） | 4 | pos*, elite, r |
| `seg_angelina.gd` | `lift`（75） | 3 | stun, elite |
| `seg_angelina.gd` | `airborne_tick`（102） | 1 | dead |
| `seg_angelina.gd` | `field_tick`（137） | 3 | dead, pos* |
| `seg_exusiai.gd` | `_exu_targets`（121） | 5 | dead, pos*, elite, boss, id |
| `seg_exusiai.gd` | `_exu_bullets`（290） | 15 | dead, id, pos*, elite, boss, r, hp |
| `seg_exusiai.gd` | `_exu_next`（330） | 3 | dead, pos*, id |
| `seg_exusiai.gd` | `kill_weight`（344） | 1 | dk |
| `seg_exusiai.gd` | `el_stack_hit`（586） | 2 | id |
| `seg_exusiai.gd` | `el_stack_tex`（604） | 1 | id |
| `seg_eyjafjalla.gd` | `_hw_extra_targets`（93） | 2 | id, pos* |
| `seg_eyjafjalla.gd` | `hw_lob`（154） | 2 | pos* |
| `seg_eyjafjalla.gd` | `hw_affect`（199） | 1 | dead |
| `seg_eyjafjalla.gd` | `hw_status`（221） | 6 | melt_t, melt_v, pos*, r, aura_weak |
| `seg_eyjafjalla.gd` | `_hw5_lob_land`（798） | 3 | dead, pos*, r |
| `seg_hoshiguma.gd` | `exec_line`（66） | 10 | elite, dead, boss, pos*, r, stun |
| `seg_irene.gd` | `_h3_thrust`（144） | 10 | pos*, r, dead, air |
| `seg_irene.gd` | `h3_ctrl_mult`（212） | 3 | air, stun, slow |
| `seg_irene.gd` | `h3_launch`（243） | 4 | dead, boss, elite, stun |
| `seg_irene.gd` | `_h3_air_tick`（272） | 1 | dead |
| `seg_irene.gd` | `h3_lift_around`（293） | 3 | dead, pos*, r |
| `seg_irene.gd` | `_e3_ir_tick`（483） | 2 | dead, pos* |
| `seg_logos.gd` | `_hw3_bolts`（121） | 8 | dead, pos*, r |
| `seg_logos.gd` | `hw_bolt_hit`（166） | 2 | dead, pos* |
| `seg_logos.gd` | `hw_shape_hit`（193） | 6 | pos*, r, dead |
| `seg_logos.gd` | `hw_execute`（222） | 12 | hp, pos*, r, dead, elite, boss |
| `seg_logos.gd` | `hw_lock_start`（260） | 4 | dead, pos*, elite, boss |
| `seg_logos.gd` | `_hw_fan_best`（357） | 3 | pos*, dead |
| `seg_logos.gd` | `_hw3_fan`（415） | 5 | dead, pos*, r |
| `seg_logos.gd` | `hw_link`（710） | 2 | dead, pos* |
| `seg_logos.gd` | `hw_draw_links`（779） | 3 | dead, pos*, r |
| `seg_logos.gd` | `hw_draw_runes`（815） | 6 | requiem, dead, requiem_n, pos*, r |
| `seg_logos.gd` | `hw_melt_mark`（837） | 2 | melt_t |
| `seg_lumen.gd` | `_h3_bolts_tick`（138） | 10 | pos*, r, dead, lit |
| `seg_lumen.gd` | `_h3_rain_tick`（365） | 6 | pos*, r, dead, lit |
| `seg_lumen.gd` | `_h3_beam_tick`（418） | 8 | pos*, id, r, dead |
| `seg_lumen.gd` | `_e3_refract`（652） | 4 | pos*, r |
| `seg_lumen.gd` | `_e3_beam_fire`（698） | 7 | pos*, r, dead |
| `seg_mizuki.gd` | `_h3_low_hp_near`（49） | 4 | dead, hp, maxhp, pos* |
| `seg_mizuki.gd` | `_h3_umbrella`（170） | 9 | dead, id, boss, pos*, stun |
| `seg_mizuki.gd` | `_h3_tentacle`（269） | 8 | pos*, r, dead, stun, boss, elite |
| `seg_mizuki.gd` | `_h3_stakes_tick`（309） | 3 | dead, pos*, r |
| `seg_mizuki.gd` | `_h3_run_delayed`（328） | 13 | pos*, dead, id, r, boss, friendly, stun |
| `seg_mizuki.gd` | `h3_cast_push`（384） | 4 | dead, boss, chest, pos* |
| `seg_mizuki.gd` | `_h3mz_draw_over`（526） | 6 | r, dead, stun, id, pos* |
| `seg_mizuki.gd` | `_h3mz_draw_add`（559） | 4 | stun, id, pos*, r |
| `seg_mizuki.gd` | `_e3_pull`（590） | 4 | pos*, dead, r |
| `seg_mizuki.gd` | `_e3_jelly_tick`（650） | 4 | r, dead, pos* |
| `seg_mizuki.gd` | `_e3_jelly_pick`（688） | 3 | id, dead |
| `seg_mizuki.gd` | `_e3_sting`（707） | 8 | pos*, r, dead, boss, elite, stun |
| `seg_mizuki.gd` | `_e3_mark`（719） | 1 | id |
| `seg_saria.gd` | `_h4_bash_after`（93） | 5 | dead, boss, elite, pos*, id |
| `seg_saria.gd` | `_h4sa_tick`（166） | 12 | pos*, dead, slow, boss, chest, r, elite, aura_weak |
| `seg_saria.gd` | `_h4sa_tick_e`（242） | 3 | pos*, dead |
| `seg_saria.gd` | `_h4_pillars_tick`（290） | 14 | dead, pos*, r, elite, id, boss, ai, chest, spd |
| `seg_saria.gd` | `_h4_orbs_tick`（429） | 5 | id, dead, pos*, r |
| `seg_saria.gd` | `_h4_shots_tick`（459） | 5 | dead, pos*, r, slow |
| `seg_saria.gd` | `h4_saria_heal`（578） | 1 | pos* |
| `seg_siege.gd` | `_h4_hammer_release`（60） | 4 | dead, boss, stun, elite |
| `seg_siege.gd` | `_h4_hammer_after`（98） | 2 | dead, pos* |
| `seg_siege.gd` | `_h4_breach`（139） | 6 | pos*, r, dead |
| `seg_siege.gd` | `_h4_next_cluster`（262） | 5 | pos*, dead, chest |
| `seg_siege.gd` | `_h4sg_tick`（303） | 10 | pos*, dead, id, r, boss, elite |
| `seg_skadi.gd` | `_hw_waves`（51） | 11 | r, dead, id, pos*, boss, elite |
| `seg_skalter.gd` | `e5_ids`（13） | 1 | id |
| `seg_skalter.gd` | `e5_area`（43） | 6 | dead, id, pos*, r, elite, boss |
| `seg_specter.gd` | `_h3_spin`（83） | 10 | pos*, r, hp, maxhp, dead, boss |
| `seg_specter.gd` | `_h3_rings_tick`（149） | 3 | dead, pos*, r |
| `seg_specter.gd` | `_h3_doll_tick`（250） | 3 | dead, pos*, slow |
| `seg_specter.gd` | `_e3_flash_tick`（511） | 2 | pos*, r |
| `seg_suzuran.gd` | `_h4_fox_release`（147） | 3 | pos*, elite, boss |
| `seg_suzuran.gd` | `_h4_brand_apply`（169） | 5 | frag_t, dead, chest, frag_v |
| `seg_suzuran.gd` | `_h4sz_tick`（259） | 4 | dead, pos*, slow, aura_weak |
| `seg_suzuran.gd` | `_h4_bigfox_tick`（284） | 11 | pos*, dead, id, r, elite, boss, slow |
| `seg_suzuran.gd` | `_h4_fox_hit`（318） | 1 | dead |
| `seg_suzuran.gd` | `_h4_brand_tick`（337） | 11 | id, pos*, r, dead, elite, boss |
| `seg_suzuran.gd` | `_h4_seals_tick`（386） | 6 | pos*, r, dead, boss, elite, stun |
| `seg_suzuran.gd` | `_h4_hearth_tick`（421） | 6 | pos*, id, dead, r |
| `seg_texas.gd` | `_tx_sweep`（253） | 10 | pos*, id, r, dead, elite, boss |
| `seg_ulpianus.gd` | `hw_tether_target`（155） | 4 | dead, elite, boss, pos* |
| `seg_ulpianus.gd` | `hw_tether_aim_dir`（179） | 3 | pos*, dead |
| `seg_ulpianus.gd` | `_hw4_anchor`（255） | 2 | dead, stun |
| `seg_ulpianus.gd` | `_hw_start_reel`（327） | 7 | r, pos*, dead, boss, elite |
| `seg_ulpianus.gd` | `_hw_reel_arrive`（356） | 5 | dead, stun, elite, pos*, r |
| `seg_ulpianus.gd` | `_hw_reel_slam`（384） | 10 | dead, pos*, elite, boss, r, stun |
| `seg_ulpianus.gd` | `_hw_zip_land`（413） | 9 | dead, pos*, boss, r, stun, elite |
| `seg_ulpianus.gd` | `_hw_drag_in`（445） | 11 | pos*, r, dead, boss, elite, stun |
| `seg_ulpianus.gd` | `_hw_open_rift`（472） | 3 | dead, pos*, r |
| `seg_ulpianus.gd` | `_hw_launch`（487） | 4 | dead, boss, elite, stun |
| `seg_ulpianus.gd` | `_hw4_launched`（506） | 2 | dead |
| `seg_ulpianus.gd` | `hw_hook_start`（923） | 1 | pos* |
| `seg_ulpianus.gd` | `_hw5_hooks`（963） | 4 | dead, stun, pos*, r |
| `seg_ulpianus.gd` | `_hw5_hook_drag_start`（1007） | 6 | pos*, r, dead |
| `seg_ulpianus.gd` | `_hw5_hook_arrive`（1033） | 3 | dead, elite, boss |
| `seg_wisadel.gd` | `_h4_wd_target`（52） | 3 | pos* |
| `seg_wisadel.gd` | `_h4_exec_target`（75） | 4 | hp, elite, boss |
| `seg_wisadel.gd` | `_h4_cannon_after`（127） | 2 | id, dead |
| `seg_wisadel.gd` | `_h4_twin`（141） | 3 | pos*, id |
| `seg_wisadel.gd` | `_h4wd_tick`（245） | 3 | dead, pos*, r |
| `seg_wisadel.gd` | `_h4_mark`（290） | 10 | id, dead, chest, pos*, r |
| `seg_wisadel.gd` | `_h4wd_on_kill`（305） | 5 | id, pos* |
| `seg_wisadel.gd` | `_h4_souls_tick`（351） | 5 | pos*, r, dead |
| `seg_wisadel.gd` | `_h4_soul_fire_tick`（386） | 1 | dead |
| `seg_wisadel.gd` | `_h4_soul_cannon_target`（415） | 3 | pos*, dead |
| `seg_wisadel.gd` | `_h4_souls_follow_tick`（462） | 1 | dead |
| `seg_wisadel.gd` | `_h4_souls_sync`（471） | 8 | id, dead, pos*, chest |
| `seg_wisadel.gd` | `_h4_explode`（519） | 8 | dead, hp, wis_det, pos*, boss, stun, elite |
| `seg_wisadel.gd` | `_h4wd_draw_marks`（755） | 5 | id, dead, pos*, r |
| `seg_wisadel.gd` | `_h4wd_draw_souls`（789） | 2 | dead, pos* |
| `seg_wisadel.gd` | `_h4_draw_soul_fire`（810） | 2 | dead, pos* |
| `character.gd` | `aim_land`（623） | 1 | pos* |
| `character.gd` | `melee_spot`（1319） | 7 | pos*, dead, r |
| `character.gd` | `melee_hit`（1359） | 8 | elite, boss, dead, pos*, stun |
| `character.gd` | `cap_targets`（1391） | 4 | boss, elite, pos*, id |
| `data_operator.gd` | `on_kill`（762） | 4 | boss, elite, pos* |
| `data_operator.gd` | `_hit_fx`（789） | 4 | pos*, r |
| `data_operator.gd` | `_draw_fields`（1295） | 7 | r, pos*, dead, id |
