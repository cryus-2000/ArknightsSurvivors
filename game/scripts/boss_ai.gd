## Boss 行为与招式预警（从 game.gd 拆出）：所有状态仍在 game.gd，本文件通过 g 访问
## 10-10 起各 Boss 的招式分支在 scripts/enemies/bosses/<type>.gd（按 enemies.json 的 role / script 约定登记，见 script_of 与 docs/38 §1.17）；本文件是公共段 + 分派 + 预警管线
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")

# 只缩短招式之间的等待；预警、锁定、连段间隔与伤害保持原约定。
const SKILL_COOLDOWN_SCALE := 0.70

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")
var patterns
var finals
# 招式令牌（docs/49d：7:00 两只 Boss 共存时不同时放大招）：有名字的 Boss 招式占用，结算后 0.6 秒释放
var token_owner = null
var token_until := 0.0
var g  # Game (Node2D)


func _init(game) -> void:
	g = game
	patterns = Patterns.new(game)
	finals = load("res://scripts/enemies/final_attacks.gd").new(game)


## Boss 行为
func boss_step(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	preload("res://scripts/run/boss_diag.gd").step(g, e, dt)
	e.bt += dt
	g.combat.gate_update(e, dt)   # 阶段卡点：每幕计时、护盾到时过卡点（docs/38 §1.3）
	if g.zone_frozen and is_same(e, g.final_boss):
		e.pos = g.combat.arena_clamp(e.pos, 80.0)   # 最终 Boss 场地：本体离圈边 ≥80（docs/38 §1.7）
	# 冲锋 / 突刺计时（_warn_resolve 的 "dash" / "stab" 写入）：Boss 不走 enemy_ai 的冲刺递减，必须在这里递减，
	# 否则骑士二阶段「再冲锋」（等 dash_t 归零）永远不会触发，冲锋帧条也会一直停在冲刺姿势（docs/38 B0 第 1 项）
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - dt)
		# 冲刺落地后的破绽（伊莎玛拉潮涌迫近，boss/ishar_close_break 秒，0 = 关）
		if e.dash_t <= 0.0 and e.get("land_break", 0.0) > 0.0:
			g.combat.start_break(e, e.land_break)
			# 落地破绽（tools/gen_sfx_boss_events.py）：伊莎玛拉 = 水花拍地 + 下沉咕噜；偏执泡影 = 膜状「啵嗯」+ 泡沫嘶声
			if e.type == "paranoia":
				Sfx.play("paranoia_land_break", -8.0, 1.0, 0.0)
			else:
				Sfx.play("ishar_land_break", -0.6, 1.0, 0.0)
			e.land_break = 0.0
	# 接潮：昏迷后回复；两者同时昏迷则一起倒下
	if e.get("coma", false):
		# 假死赛跑（docs/38 §8.4）：boss/pair_race 秒内血条涨回 pair_revive_hp（50%），期间打倒另一具 = 两具一起倒下；到时复苏
		e.coma_t = e.get("coma_t", 0.0) + dt
		var race: float = Bal.v("boss/pair_race", 8.0)
		e.hp = maxf(1.0, e.maxhp * Bal.v("boss/pair_revive_hp", 0.5) * minf(e.coma_t / race, 1.0))
		var p = e.get("partner")
		if p != null and not p.dead and p.get("coma", false):
			e.coma = false
			p.coma = false
			e.invuln = false
			p.invuln = false
			g.combat.kill(e)
			g.combat.kill(p)
			g.vfx.show_banner("接潮双体 同时倒下")
			return
		if e.coma_t >= race:
			e.coma = false
			e.invuln = false
			e.coma_t = 0.0
			e.revives = int(e.get("revives", 0)) + 1
			e.vis_act = "revive"   # 重画 *_revive 复苏帧条（纯画面，world._vis_anim）
			e.vis_t0 = g.t
			g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(0.4, 1.0, 0.9), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -50), "复苏（%d / %d）" % [e.revives, int(Bal.v("boss/pair_revives", 2.0))], Color(0.6, 1.0, 0.9), 18)
			# 复苏回调（docs/95 §12 on_revive：斥亡体「迸发」等在这里起手）
			var hr = boss(e.type)
			if hr != null:
				hr.on_revive(e)
		return
	var ready: bool = e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and e.get("channel", 0.0) <= 0.0 and e.get("dash_t", 0.0) <= 0.0 and e.age > 2.0 and e.get("break_t", 0.0) <= 0.0   # break_t：Boss 自己的破绽硬直（§1.5）
	# 封印（docs/61 §15 st.seal）：Boss 只是推迟出招——封印期间（已按 boss_mult / boss_max 缩到 ≤1.5 秒）不起新招，冷却照走；之后 boss_immune 秒免疫
	if ready and float(e.get("seal_t", 0.0)) > g.t:
		ready = false
	# 接潮「统一」（docs/95 §8.2 C，吸收原接潮共鸣）：两体之间的直线（b_owner 双端跟随），幽灵线 0.9 秒随两体移动、之后冻结锁定 0.6 秒、两体停步；
	# 平时由主教放（unite 9 秒，第二幕 7 秒，两体相距 120–520），主教假死时由搭档放（boss/tide_link_cd 4.5 秒，即原接潮共鸣）；占组内共用的招式令牌。
	# 第二幕（任一具过 50% 卡点）两体之间常亮一条低亮度幽灵线；假死时照旧画亮线。骑士的冰线 / 寒冷追击在 bosses/knight_boss.gd（docs/95 §4）
	var mate = e.get("partner")
	if mate != null and not mate.dead and e.type in ["bishop", "archon", "immortal"]:
		var mcoma: bool = mate.get("coma", false)
		var pair_p2: bool = int(e.get("gates_passed", 0)) >= 1 or int(mate.get("gates_passed", 0)) >= 1
		var linker: bool = mcoma or e.type == "bishop"
		if linker and (mcoma or pair_p2) and g.t >= float(e.get("link_visual_at", 0.0)):
			e.link_visual_at = g.t + 0.28
			var lc: Color = g.vfx.boss_color(e.type)
			if not mcoma:
				lc = Color(lc.r * 0.5, lc.g * 0.5, lc.b * 0.5, 0.55)   # 第二幕常亮的幽灵线：低亮度、不发光（§0.2 样式 0）
			g.fx.append({"kind": "tide_link", "a": e.pos, "b": mate.pos, "life": 0.36, "max": 0.36, "col": lc, "enemy": true})
		var dd: float = e.pos.distance_to(mate.pos)
		if ready and linker and dd >= 120.0 and dd <= 520.0 and g.t >= float(e.get("link_next_at", 0.0)):
			e.link_next_at = g.t + (Bal.v("boss/tide_link_cd", 4.5) if mcoma else (7.0 if pair_p2 else 9.0))
			unite(e, mate)
			ready = false
	# 招式令牌（docs/38 §1.10）：同一时刻只允许一个有名字的大招，接潮组两具也共用这一个名额（9/30 前误把搭档排除在外，7:00 双体大招会叠）；
	# 不在 g.bosses 里的（演练 / 图鉴）不算
	if ready and token_owner != null and not is_same(token_owner, e) and not token_owner.dead and g.t < token_until 			and g.bosses.has(token_owner):
		ready = false
	finals.update(e, dt)
	if e.type=="knight_boss":
		boss(e.type)._knight_stakes(e,dt)
		ready=ready and e.get("break_t",0.0)<=0.0 and e.stun<=0.0 and e.wind<=0.0
		if boss(e.type).stake_cast_step(e,dir,ready): ready=false
	if e.type == "knight_boss" and boss(e.type).combo_step(e,dir,dist,ready):
		ready = false
	if ready and finals.try_attack(e, dir, dist):
		ready = false
	if ready and patterns.try_attack(e, dir, dist):
		ready = false
	var h = boss(e.type)
	if h != null:
		h.step(e, dt, dir, dist, ready, mate)


## Boss 出招霸体（10-28 用户「骑士的攻击会被打断」）：脚本实现 super_armor(e) 且返回 true 时，enemies.add_cc 不写眩晕、apply_kb / hold_at 不动它。
## 没实现的 Boss 照旧（控制对 Boss 的减半 / 免疫口径不变）
func super_armor(e: Dictionary) -> bool:
	var h = boss(e.type)
	return h != null and h.has_method("super_armor") and h.super_armor(e)


## 接潮「统一」一次（docs/95 §8.2 C）：两体之间 17 宽直线，幽灵线 0.9 秒双端跟随、锁定 0.6 秒冻结并让两体停步（_update_warns b_owner）；
## e.dmg × 0.55 法术、侵蚀 0.25（原接潮共鸣数值）。公共段和验收 --bossmoves 都走这里
func unite(e: Dictionary, mate: Dictionary) -> Dictionary:
	return g.tele.warn(e, "line", 1.5, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos), "wid": 17.0, "track": 0.9, "act": "tide_link", "name": "统一",
		"col": g.vfx.boss_color(e.type), "corrode": 0.25, "dmg": e.dmg * 0.55, "arts": false, "cancel_dead": true, "b_owner": mate, "lock": false, "skin": "mc_link"})   # skin：点描边预警（render/mid_card_draw，docs/170）


## 远程 Boss 的迫近（协调人 9/30）：离主控超过 boss/<key>_close_min（300，0 = 关）时，每 <key>_close_cd（6）秒带直线预警冲到主控前约 140 处，
## 穿过杂兵墙进干员射程；冲刺本身无接触伤害，落地给 <key>_close_break（1）秒破绽。放了返回预警时长，没放返回 -1。伊莎玛拉二阶段、偏执泡影一阶段共用。
## 10-14（docs/95 §2.5）：它是机制不是招，dmg 0 → 预告样式 0（低亮度），和「无接触伤害」口径一致，不再和三线扫射 / 凝视抢直线
func close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	var cmin: float = Bal.v("boss/%s_close_min" % key, 300.0)
	if cmin <= 0.0 or dist <= cmin or not cd_ready(e, key + "_close", Bal.v("boss/%s_close_cd" % key, 6.0)):
		return -1.0
	var cw: Dictionary = g.tele.warn(e, "line", 0.7, {"ang": dir.angle(), "len": clampf(dist - 140.0, 80.0, 700.0), "wid": 30.0, "track": 0.3, "act": "dash", "fit_len": true,
		"name": title, "col": col, "dmg": 0.0, "close_break": Bal.v("boss/%s_close_break" % key, 1.0)})
	return cw.dur


## ---- 每只 Boss 的行为脚本（docs/55 §6 拆分，10-10；docs/126 A3 10-22 改按约定登记）：enemies.json 里 role == "boss" 的种类
## 用 scripts/enemies/bosses/<script>.gd，script 缺省 = 种类名（圣徒两档写 "script": "saint" 共用）。新 Boss = 加一个文件 + enemies.json 一条。
## 脚本无状态（状态在敌人字典上），按 type 只实例化一次；不是 Boss 的种类不出招（和拆分前的 match 缺省分支一样）
var _bosses := {}   # type -> 脚本实例


static func script_of(type: String) -> String:
	var d: Dictionary = D.ENEMIES.get(type, {})
	return str(d.get("script", type)) if str(d.get("role", "")) == "boss" else ""


func boss(type: String):
	var c = _bosses.get(type, false)   # 缓存里非 Boss 种类存 null；false = 还没查过
	if not (c is bool):
		return c
	var h = null
	var sn := script_of(type)
	if sn != "":
		h = load("res://scripts/enemies/bosses/%s.gd" % sn).new(g)
	_bosses[type] = h
	return h


## 图鉴 / Boss 演练使用正式二阶段的完整状态，避免只改贴图标记、却还留着一阶段行为。
## 正式受击触发仍由 combat.gd 结算；此入口只用于预览场景的起始条件。
func setup_preview_phase2(e: Dictionary) -> void:
	if e.phase == 2:
		return
	var h = boss(e.type)
	if h != null:
		h.setup_preview_phase2(e)


## ---- 兼容旧调用点（combat / enemies / ishar_encounter / tests）：各 Boss 自己的入口已搬进 bosses/<type>.gd，这里只转发
func transform_ishar(e: Dictionary) -> void:
	boss("ishar").transform_ishar(e)


func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float) -> void:
	boss("ishar")._ishar_phase2(e, dir, dist)


func _ishar_haste(e: Dictionary) -> float:
	return boss("ishar")._ishar_haste(e)


func saint_interrupt(e: Dictionary) -> void:
	boss("iberia").saint_interrupt(e)


func _paranoia_p2(e: Dictionary) -> void:
	boss("paranoia")._paranoia_p2(e)


func _paranoia_aura(e: Dictionary, dist: float) -> void:
	boss("paranoia")._paranoia_aura(e, dist)


func paranoia_cocoon(e: Dictionary) -> void:
	boss("paranoia").paranoia_cocoon(e)


func _paranoia_cocoon_step(e: Dictionary, dt: float) -> void:
	boss("paranoia")._paranoia_cocoon_step(e, dt)


func paranoia_hatch(e: Dictionary, broken: bool) -> void:
	boss("paranoia").paranoia_hatch(e, broken)


func izumik_absorb(e: Dictionary) -> void:
	boss("izumik").izumik_absorb(e)


func _izumik_lamp_step(e: Dictionary, dt: float) -> void:
	boss("izumik")._izumik_lamp_step(e, dt)


func izumik_safe(e: Dictionary) -> bool:
	return boss("izumik").izumik_safe(e)


func _knight_stakes(e: Dictionary, dt: float) -> void:
	boss("knight_boss")._knight_stakes(e, dt)


## Boss 招式冷却：到时返回 true 并重置
func cd_ready(e: Dictionary, key: String, dur: float) -> bool:
	if not e.has("cds"):
		e.cds = {}
	if e.cds.get(key, 0.0) <= g.t:
		e.cds[key] = g.t + dur * (SKILL_COOLDOWN_SCALE * Bal.v("boss/tempo_k_" + str(e.type), 1.0) if e.boss else 1.0)   # tempo_k：单只 Boss 出招间隔（10-29 docs/201 §7）
		return true
	return false


## ---- 预警服务已搬到 enemies/telegraph.gd（g.tele），填充层绘制搬到 render/telegraph_draw.gd（docs/101 B2，10-15）。
## 下面是同名转发：tests/ 与未合入的分支照旧能调 g.bai.warn 等；新代码直接调 g.tele.*
func cue_cat(w: Dictionary) -> String:
	return g.tele.cue_cat(w)


func warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	return g.tele.warn(e, shape, dur, d)


func update_warns(dt: float) -> void:
	g.tele.update_warns(dt)


func _warn_hit(w: Dictionary) -> bool:
	return g.tele.hits_leader(w)


func in_gap(w: Dictionary, a: float) -> bool:
	return g.tele.in_gap(w, a)


func warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	g.tele.warn_damage(w, stun_t, slow)


func warn_resolve(w: Dictionary) -> void:
	g.tele.warn_resolve(w)


func draw_warns() -> void:
	TeleDraw.draw_fills(g)


## 招式令牌（docs/49d：7:00 两只 Boss 共存时不同时放大招）：有名字的 Boss 招式登记预警时占用，until = 结算后 0.6 秒（telegraph.warn 调）
func claim_token(e: Dictionary, until: float) -> void:
	token_owner = e
	token_until = maxf(token_until if is_same(token_owner, e) else 0.0, until)


## 旧名转发（docs/101 S6，2026-10-15 改公开名）：tests/ 与未合入的分支还在调旧名，各分支合完后删
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	boss_step(e, dt, dir, dist)

func _close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	return close_in(e, dir, dist, key, title, col)

func _cd(e: Dictionary, key: String, dur: float) -> bool:
	return cd_ready(e, key, dur)

func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	return warn(e, shape, dur, d)

func _update_warns(dt: float) -> void:
	update_warns(dt)

func _warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	warn_damage(w, stun_t, slow)

func _warn_resolve(w: Dictionary) -> void:
	warn_resolve(w)

func _draw_warns() -> void:
	draw_warns()
