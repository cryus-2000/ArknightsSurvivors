## Boss 行为与招式预警（从 game.gd 拆出）：所有状态仍在 game.gd，本文件通过 g 访问
## 10-10 起各 Boss 的招式分支在 scripts/enemies/bosses/<type>.gd（见下方 SCRIPTS 注册表与 docs/38 §1.17）；本文件是公共段 + 分派 + 预警管线
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

# 只缩短招式之间的等待；预警、锁定、连段间隔与伤害保持原约定。
const SKILL_COOLDOWN_SCALE := 0.70

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
var patterns
# 招式令牌（docs/49d：7:00 两只 Boss 共存时不同时放大招）：有名字的 Boss 招式占用，结算后 0.6 秒释放
var token_owner = null
var token_until := 0.0
var g  # Game (Node2D)


func _init(game) -> void:
	g = game
	patterns = Patterns.new(game)


## Boss 行为
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
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
			g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(0.4, 1.0, 0.9), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -50), "复苏（%d / %d）" % [e.revives, int(Bal.v("boss/pair_revives", 2.0))], Color(0.6, 1.0, 0.9), 18)
		return
	var ready: bool = e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and e.get("channel", 0.0) <= 0.0 and e.get("dash_t", 0.0) <= 0.0 and e.age > 2.0 and e.get("break_t", 0.0) <= 0.0   # break_t：Boss 自己的破绽硬直（§1.5）
	# 原作机制转译：冰线后的骑士冲锋、接潮双体的假死反击。均走正式预警管线。
	if ready and e.type == "knight_boss" and g.t >= float(e.get("hunt_follow_at", INF)):
		e.hunt_follow_at = INF
		_warn(e, "line", 0.7, {"ang": float(e.get("hunt_angle", dir.angle())), "len": 520.0, "wid": 32.0,
			"fit_len": true, "act": "dash", "name": "寒冷追击", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 1.35})
		ready = false
	if ready and e.type == "knight_boss" and dist >= 120.0 and dist <= 600.0 and _cd(e, "hunt", 12.0):
		_warn(e, "line", 0.85, {"ang": dir.angle(), "len": minf(560.0, dist + 60.0), "wid": 18.0,
			"track": 0.25, "act": "frost_track", "name": "冰线", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 0.4})
		ready = false
	var mate = e.get("partner")
	if mate != null and not mate.dead and mate.get("coma", false) and e.type in ["bishop", "archon", "immortal"]:
		if g.t >= float(e.get("link_visual_at", 0.0)):
			e.link_visual_at = g.t + 0.28
			g.fx.append({"kind": "tide_link", "a": e.pos, "b": mate.pos, "life": 0.36, "max": 0.36, "col": g.vfx.boss_color(e.type), "enemy": true})
		if ready and g.t >= float(e.get("link_next_at", 0.0)):
			e.link_next_at = g.t + Bal.v("boss/tide_link_cd", 4.5)
			_warn(e, "line", 0.9, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos),
				"wid": 17.0, "act": "tide_link", "name": "接潮共鸣", "col": g.vfx.boss_color(e.type),
				"corrode": 0.25, "dmg": e.dmg * 0.55, "cancel_dead": true})
			ready = false
	# 招式令牌（docs/38 §1.10）：同一时刻只允许一个有名字的大招，接潮组两具也共用这一个名额（9/30 前误把搭档排除在外，7:00 双体大招会叠）；
	# 不在 g.bosses 里的（演练 / 图鉴）不算
	if ready and token_owner != null and not is_same(token_owner, e) and not token_owner.dead and g.t < token_until 			and g.bosses.has(token_owner):
		ready = false
	if ready and patterns.try_attack(e, dir, dist):
		ready = false
	var h = boss(e.type)
	if h != null:
		h.step(e, dt, dir, dist, ready, mate)


## 远程 Boss 的迫近（协调人 9/30）：离主控超过 boss/<key>_close_min（300，0 = 关）时，每 <key>_close_cd（6）秒带直线预警（②）冲到主控前约 140 处，
## 穿过杂兵墙进干员射程；冲刺本身无接触伤害，落地给 <key>_close_break（1）秒破绽。放了返回预警时长，没放返回 -1。伊莎玛拉二阶段、偏执泡影一阶段共用
func _close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	var cmin: float = Bal.v("boss/%s_close_min" % key, 300.0)
	if cmin <= 0.0 or dist <= cmin or not _cd(e, key + "_close", Bal.v("boss/%s_close_cd" % key, 6.0)):
		return -1.0
	var cw := _warn(e, "line", 0.7, {"ang": dir.angle(), "len": clampf(dist - 140.0, 80.0, 700.0), "wid": 30.0, "track": 0.3, "act": "dash", "fit_len": true,
		"name": title, "col": col, "dmg": e.dmg, "close_break": Bal.v("boss/%s_close_break" % key, 1.0)})
	return cw.dur


## ---- 每只 Boss 的行为脚本（docs/55 §6 拆分，10-10）：type → scripts/enemies/bosses/<文件>.gd；新 Boss = 加一个文件 + 在这里登记一行
## （圣徒两档共用 saint.gd）。脚本无状态（状态在敌人字典上），按 type 只实例化一次；没登记的 type 不出招（和拆分前的 match 缺省分支一样）
const SCRIPTS := {
	"iberia": "saint", "carmen": "saint", "path": "path", "bishop": "bishop", "archon": "archon", "immortal": "immortal",
	"paranoia": "paranoia", "izumik": "izumik", "knight_boss": "knight_boss", "ishar": "ishar",
}
var _bosses := {}   # type -> 脚本实例


func boss(type: String):
	if _bosses.has(type):
		return _bosses[type]
	var h = null
	if SCRIPTS.has(type):
		h = load("res://scripts/enemies/bosses/%s.gd" % SCRIPTS[type]).new(g)
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


func _path_core(e: Dictionary) -> void:
	boss("path")._path_core(e)


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


## 预警 → 音效类别（docs/38 §8.11 对照表）：落地 land / 冲锋 charge / 光束 beam / 近身 melee / 全场 global
func cue_cat(w: Dictionary) -> String:
	if w.get("must_dash", false):
		return "global"
	match str(w.act):
		"dash", "stab":
			return "charge"
		"shot", "beam", "pattern_line", "ishar_line", "frost_track", "tide_link", "ishar_echo":
			return "beam"
		"bite", "sweep", "pattern_fan", "pattern_cleave":
			return "melee"
	return "land"


## Boss 招式冷却：到时返回 true 并重置
func _cd(e: Dictionary, key: String, dur: float) -> bool:
	if not e.has("cds"):
		e.cds = {}
	if e.cds.get(key, 0.0) <= g.t:
		e.cds[key] = g.t + dur * (SKILL_COOLDOWN_SCALE if e.boss else 1.0)
		return true
	return false



## Boss 招式预警：shape = circle / line / cone；dur 秒后结算 act
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var w := {"shape": shape, "t": 0.0, "dur": dur, "owner": e, "pos": e.pos, "ang": 0.0, "r": 60.0, "len": 300.0, "wid": 14.0,
		"half": 0.8, "col": Color(1.0, 0.3, 0.35), "act": "", "dmg": e.dmg, "name": "", "corrode": 0.0, "done": false, "follow": false, "track": 0.0, "lock": true}
	w.merge(d, true)
	# 预警样式（docs/38 §8.11）：界面按 style 画，不再从 follow / gap_ang 猜。0 预告（无伤害，低亮度）；① 落点圈 ② 直线 ③ 扇形 ④ 缺口环 ⑤ 必须冲刺。
	# follow 只表示「圈跟着施法者走」，钻地咬击、踏地、触须爆发、寒冰领域都是 ① —— 走出圈即可
	if not w.has("style"):
		if w.get("must_dash", false):
			w.style = 5
		elif float(w.dmg) <= 0.0:
			w.style = 0
		elif shape == "line":
			w.style = 2
		elif shape == "cone":
			w.style = 3
		elif w.has("gap_ang") or w.act == "bring":
			w.style = 4
		else:
			w.style = 1
	# 时序下限（§1.9、docs/48 P0-2）：Boss 预警总时长 ≥0.6 秒；锁定（追踪结束 → 结算）≥0.4 秒，不够时缩短追踪段
	if e.boss:
		w.dur = maxf(w.dur, 0.6)
		w.track = minf(w.track, maxf(0.0, w.dur - 0.4))
	# 冲刺 / 突刺的预警线长 = 实际冲出的距离（docs/48 P0-3：原来斥亡体画 190 冲 373、塑路者画 440 冲 214）：
	# 按击退每秒衰减 900 算，距离 = v²/1800 + 本体半径（自冲不受重型削减）。fit_len：按设计线长反推速度（骑士冲锋、塑路者冲撞要真冲到位）
	if w.act in ["dash", "stab"] and shape == "line":
		if w.get("fit_len", false):
			w.spd = sqrt(1800.0 * maxf(w.len - e.r, 40.0))
		else:
			var v: float = float(w.get("spd", 600.0 if w.act == "dash" else 800.0))
			w.len = v * v / 1800.0 + e.r
		# 骑士冲锋：预先标出这一冲会不会撞上冰枪桩（画面画「破」字端盖，docs/38 §8.8）
		for st in e.get("stakes", []):
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			if Geometry2D.get_closest_point_to_segment(st.pos, w.pos, b).distance_to(st.pos) < e.r + 22.0:
				w.stake_hit = true
	# 难度缩短预警只压缩追踪段（跟着主控转向的那段），总时长至少 0.6 秒，原本就短于 0.6 的不动（docs/38 B0 第 5 项）；
	# 修正值大于 1（放宽）时整体拉长
	var wm := float(g.dmod.boss_warn)
	if wm < 1.0 and w.track > 0.0:
		var cut: float = minf(w.track * (1.0 - wm), maxf(0.0, w.dur - 0.6))
		w.track -= cut
		w.dur -= cut
	elif wm > 1.0:
		w.dur *= wm
		w.track *= wm
	g.warns.append(w)
	# 大招固定音效（docs/38 §8.11）：有名字的 Boss 招式起手播「类别起手音 + Boss 专属音色」，结算时播命中音
	if e.boss and w.name != "":
		w.cue = cue_cat(w)
		Sfx.play_cue(w.cue, e.type, "start")
	if e.boss and w.name != "":
		token_owner = e
		token_until = maxf(token_until if is_same(token_owner, e) else 0.0, g.t + w.dur + 0.6)
	if w.lock:
		e.wind = maxf(e.get("wind", 0.0), w.dur)
		e.pose = w.dur + 0.3
		e.pose_max = w.dur + 0.3
	if w.name != "":
		# 招式名进 Boss 血条的副标题行，不再头顶浮字（docs/38 §1.15，hud.gd 读 move_name / move_t）
		e["move_name"] = w.name
		e["move_t"] = g.t
		Sfx.play("skill", -12.0, 1.4)
	return w



func _update_warns(dt: float) -> void:
	for w in g.warns:
		w.t += dt
		var e: Dictionary = w.owner
		if w.follow and not e.dead:
			w.pos = e.pos
		if w.track > 0.0 and w.t < w.track and w.shape != "circle":
			var want: float = (g.ppos + Vector2(0, -14) - w.pos).angle()
			w.ang = lerp_angle(w.ang, want, minf(1.0, dt * 10.0))
		if w.t >= w.dur and not w.done:
			w.done = true
			if not e.dead or (w.shape == "circle" and not w.get("cancel_dead", false)):
				_warn_resolve(w)
	g.warns = g.warns.filter(func(w): return w.t < w.dur + 0.25)



func _warn_hit(w: Dictionary) -> bool:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	match w.shape:
		"circle":
			return g.combat.ground_d(g.ppos, w.pos) < w.r   # 画即判：主控脚底落在画出的椭圆里才算中（§1.9）
		"line":
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			return Geometry2D.get_closest_point_to_segment(pp, w.pos, b).distance_to(pp) < w.wid + 12.0
		"cone":
			var dv: Vector2 = pp - w.pos
			return dv.length() < w.r + 10.0 and absf(angle_difference(dv.angle(), w.ang)) < w.half + 0.12
	return false



func _warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	if not _warn_hit(w):
		return
	var e: Dictionary = w.owner
	# 伤害来源名：Boss 的招式记 boss_<类型>，普通怪 / 精英借用预警系统的招式记 atk_<类型>（引痕者前刺、钻地咬击、踏地等；
	# 原来一律记 boss_，统计里被误算成 Boss。Boss 保护看的是 enemy_hit 的 boss 标记 = e.boss，不看这个名字）
	g.dmg_src = ("boss_" if e.boss else "atk_") + e.type
	g.in_type = ["远程", "法术"] if w.act in ["pillar", "burst", "beam", "bring", "pattern_rain", "tide_link"] else (["远程", "物理"] if w.act == "shot" else ["近战", "物理"])
	var true_damage: bool = w.get("true", false)
	if true_damage:
		g.in_type = ["远程" if w.act in ["ishar_strike", "ishar_line", "ishar_volley", "ishar_echo"] else "近战", "真实"]
	if g.invuln <= 0.0:
		var hp_before: float = g.hp
		g.combat.enemy_hit(w.dmg, {"corrode": w.corrode, "boss": e.boss, "nerve": float(w.get("nerve", 0.0)),
			"frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type, "warn": true}, true_damage, true)   # 预警系统精英也在用（钻地咬击、踏地），按放招的敌人算
		if not e.boss and g.hp < hp_before and float(w.get("stun", 0.0)) > 0.0 and g.t >= g.combat.enemy_stun_next:
			g.combat.enemy_stun_next = g.t + 8.0
			if not g.combat.stun_as_slow():
				g.pstun = maxf(g.pstun, minf(float(w.stun), 0.25))
		if stun_t > 0.0 and not g.combat.stun_as_slow(e.boss):   # Boss 战里僵直改成减速（docs/38 §1.11）
			g.pstun = maxf(g.pstun, stun_t)
		if slow and not g.combat.atk_slow_as_slow(3.0, e.boss):   # Boss 来源不写 atk_slow，改成移速减速（docs/38 §1.11）
			g.atk_slow = 3.0



func _warn_resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var c: Color = w.col
	if w.has("cue"):
		Sfx.play_cue(w.cue, e.type, "hit")
	if e.boss:
		# 预警结束后明确重新起攻击动作，而不是沿用蓄力末帧。
		e.pose = 0.35
		e.pose_max = 0.35
	# 出手事件（给画面层画攻击特效用，界面与美术读）：动作、形状、位置、朝向、范围、时刻
	e.last_act = {"act": w.act, "shape": w.shape, "pos": w.pos, "ang": w.ang, "r": w.r, "len": w.len, "wid": w.wid, "half": w.half, "t": g.t}
	if w.get("secondary", false):
		e.atk_until = g.t + 0.35
	var dv := Vector2.from_angle(w.ang)
	if str(w.act).begins_with("pattern_"):
		patterns.resolve(w)
		return
	if w.act == "tide_link" and (e.get("partner") == null or not e.partner.get("coma", false)):
		return
	if e.get("boss", false):
		g.vfx.boss_signature(w)
	match w.act:
		"frost_track":
			g.fx.append({"kind": "frost_track", "a": w.pos, "b": w.pos + dv * w.len,
				"life": 1.0, "max": 1.0, "enemy": true})
			for i in 8:
				var pos: Vector2 = w.pos + dv * w.len * (float(i) + 0.5) / 8.0
				g.fx.append({"kind": "frost_step", "pos": pos, "r": 13.0, "life": 0.9, "max": 0.9, "enemy": true})
			g.vfx.fx_sprite("fx_knight_impact", w.pos + dv * w.len, g.PX * 1.2)
			g.vfx.sparks(w.pos + dv * w.len, dv, c, 10, 180.0)
			e.hunt_angle = w.ang
			e.hunt_follow_at = g.t + 0.25
			Sfx.play("hit", -9.0, 1.4)
			_warn_damage(w)
		"tide_link":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos + dv * w.len, g.PX * 1.2)
			Sfx.play("tentacle", -8.0, 1.1)
			_warn_damage(w)
		"ishar_echo":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos, g.PX * 1.0)
			Sfx.play("tentacle", -8.0, 1.25)
			_warn_damage(w)
		"extra_volley":
			var a: Dictionary = w.extra
			var count: int = mini(int(a.count), 5)
			var kind: String = D.ENEMIES[e.type].get("shot_kind", "orb")
			var speed: float = float(a.speed)
			var spread: float = float(a.spread)
			for i in count:
				if g.ebullets.size() >= 240:
					break
				var angle: float = w.ang + lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, float(count - 1)))
				g.ebullets.append({"pos": w.pos, "vel": Vector2.from_angle(angle) * speed, "dmg": w.dmg,
					"r": 5.0, "life": 2.4, "slow": false, "frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "corrode": e.corrode,
					"nerve": float(w.get("nerve", 0.0)), "true": false, "kind": kind, "home": false,
					"atk": D.ENEMIES[e.type].get("atk", "法术"), "boss": false, "source_id": e.id})
			g.fx.append({"kind": "rays", "pos": w.pos, "life": 0.25, "max": 0.25, "col": c, "enemy": true})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
		"ishar_strike":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.45, "max": 0.45, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, c, 10, 230.0)
			Sfx.play("tentacle", -6.0, 1.2)
			g.vfx.shake_screen(0.3)
			_warn_damage(w)
		"ishar_line":
			g.fx.append({"kind": "bbeam", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.28, "max": 0.28, "col": c, "wid": w.wid})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
			g.vfx.shake_screen(0.25)
			_warn_damage(w)
		"ishar_volley":
			g.eai.shoot(e, dv)
			e.cdt = maxf(e.cdt, e.cd * 0.82)
		"pillar":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.55, "max": 0.55, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.2, 1.6), 14, 260.0)
			Sfx.play("tentacle", -5.0, 1.1)
			g.vfx.shake_screen(0.3)
			_warn_damage(w, 0.4)
		"frost":
			e.frost_pos = w.pos
			e.frost_t = 6.0
			g.fx.append({"kind": "frost", "pos": w.pos, "r": w.r, "life": 6.0, "max": 6.0, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 16, 240.0)
			Sfx.play("skill", -4.0, 0.7)
			_warn_damage(w)
		"slam":
			g.shocks.append({"pos": w.pos, "r": e.r, "maxr": w.r, "dmg": w.dmg, "hit": false, "boss": e.boss, "src_type": e.type})
			# 地裂（界面与美术 10-01，协调人定）：塑路者锈红、奠基者土黄暗色（起宽加粗），同干员的共用地裂画法（render/ground_crack.gd）；其他仍走旧放射线
			var gc_col = {"path": Color(0.95, 0.38, 0.22), "founder": Color(0.62, 0.46, 0.22)}.get(e.type)
			if gc_col != null:
				g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.7, "max": 0.7, "col": gc_col, "enemy": true,
					"opts": {"n": 10} if e.type == "path" else {"n": 11, "w0": Vector2(5.0, 7.0)}})
			else:
				g.fx.append({"kind": "quake", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.8, 0.7, 0.6), 18, 300.0)
			Sfx.play("boom", 0.0, 0.6, 0.0)
			g.vfx.shake_screen(1.2)
			g.hitstop = maxf(g.hitstop, 0.05)
		"burst":
			g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": Color(0.7, 0.35, 1.0)})
			g.vfx.sparks(w.pos, Vector2.ZERO, Color(1.2, 0.6, 1.8), 12, 240.0)
			Sfx.play("boom", -8.0, 1.2, 0.0)
			_warn_damage(w)
		"shot":
			var b: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "tracer", "a": w.pos + Vector2(0, -18), "b": b, "life": 0.35, "max": 0.35, "col": c, "wid": w.wid})
			g.vfx.sparks(w.pos + dv * 24.0, dv, c if w.get("secondary", false) else Color(2.0, 1.6, 0.8), 8, 320.0)
			Sfx.play("hit", 0.0, 0.5, 0.0)
			g.vfx.shake_screen(0.4)
			_warn_damage(w)
		"beam":
			var b2: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "bbeam", "a": w.pos + Vector2(0, -20), "b": b2, "life": 0.5, "max": 0.5, "col": c, "wid": w.wid})
			Sfx.play("skill", -2.0, 0.5)
			g.vfx.shake_screen(0.7)
			_warn_damage(w, 0.0, true)
		"sweep":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos + dv * w.r * 0.6, dv, Color(0.8, 1.4, 1.4), 12, 260.0)
			Sfx.play("swing", -2.0, 0.55)
			g.vfx.shake_screen(0.5)
			_warn_damage(w, 0.25)
		"leap":
			e.pos = w.pos
			e.air = 0.0
			e.erase("leap")
			# 冲击环不超过预警圆（docs/38 B0 第 5 项：原来 +40，圈外也会被打到）
			g.shocks.append({"pos": w.pos, "r": 10.0, "maxr": w.r, "dmg": w.dmg * 0.5, "hit": false, "boss": e.boss, "src_type": e.type})
			g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": Color(0.85, 0.35, 0.95), "enemy": true, "opts": {"n": 9}})   # 地裂洋红紫（原青绿和友方撞色，界面与美术 10-01）
			g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r * 0.8, "life": 0.3, "max": 0.3, "col": Color(0.5, 0.9, 0.9)})
			Sfx.play("boom", -2.0, 0.8, 0.0)
			g.vfx.shake_screen(1.0)
			_warn_damage(w, 0.3)
		"dash":
			e.land_break = float(w.get("close_break", 0.0))
			e.kb = dv * w.get("spd", 600.0)
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.45
			e.pose = 0.45
			e.pose_max = 0.45
			g.vfx.sparks(e.pos, -dv, Color(0.9, 0.9, 1.0), 10, 200.0)
			Sfx.play("swing", -4.0, 0.5)
		"stab":
			e.kb = dv * w.get("spd", 800.0)
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.2
			e.pose = 0.25
			e.pose_max = 0.25
			g.fx.append({"kind": "tracer", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.22, "max": 0.22, "col": c, "wid": w.wid})
			Sfx.play("swing", -6.0, 0.7)
			_warn_damage(w)
		"izu_wave":
			# 全场地波：没有缺口、覆盖全场；冲刺无敌或站在点亮的灯柱光圈里才躲得开。伤害 ≤ 最大生命 25%，减速 1.5 秒，不僵直
			g.fx.append({"kind": "ring", "pos": w.pos, "r": 900.0, "life": 0.7, "max": 0.7, "col": c, "enemy": true})
			g.fx.append({"kind": "gcrack", "pos": e.pos, "r": 170.0, "life": 0.9, "max": 0.9, "col": Color(0.9, 0.4, 1.15), "enemy": true, "opts": {"n": 12}})   # 地波源头：伊祖米克脚下大地裂（纯画面，界面与美术 10-01）
			Sfx.play("boom", -2.0, 0.5, 0.0)
			if g.invuln <= 0.0 and not izumik_safe(e):
				g.dmg_src = "boss_" + e.type
				g.in_type = ["远程", "法术"]
				g.combat.enemy_hit(w.dmg, {"boss": true, "src_type": e.type}, false, true)
				g.combat.slow_leader("wave", 1.5, 0.6)
		"spawn":
			# 预告后生成（投嗣育母的注亡拟嗣，docs/48 P0-7）
			g.spawner.spawn_enemy(w.spawn, w.pos)
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
		"bite":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.25, "max": 0.25, "col": c})
			g.vfx.sparks(w.pos + dv * w.r * 0.65, dv, c, 6, 150.0)
			Sfx.play("swing", -6.0, 0.9)
			_warn_damage(w)
		"bring":
			for k in 14:
				var d2 := Vector2.from_angle(TAU * k / 14.0 + w.t)
				g.ebullets.append({"pos": w.pos, "vel": d2 * 252.0, "dmg": w.dmg, "slow": true, "r": 7.0, "life": 3.0,
					"corrode": 0.5, "nerve": 0.0, "true": false, "kind": "ebullet", "home": false, "boss": e.boss})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			Sfx.play("tentacle", -8.0, 1.3)



## 预警绘制：外框 + 随时间填满的内圈；结算瞬间闪白
func _draw_warns() -> void:
	for w in g.warns:
		if w.get("dim", false):
			continue   # 打不到主控的杂兵预警只画淡轮廓（world.classify_tells / draw_warn_outlines，可读性 1.1.1，界面与美术）
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		var pulse: float = 0.5 + 0.5 * sin(g.t * 14.0)
		var fa := 0.10 + 0.14 * k
		var oa := 0.55 + 0.35 * pulse * k
		if w.done:
			var f: float = clampf(1.0 - (w.t - w.dur) / 0.25, 0.0, 1.0)
			c = Color(2.0, 2.0, 2.0)
			fa = 0.45 * f
			oa = 0.9 * f
			k = 1.0
		# 颜色不再乘 1.7–2.0：乘完在灯光里褪成白色 / 粉彩，色相丢失（docs/48 全局 ④）；亮度靠 alpha 和白芯（world.draw_warn_outlines）
		if w.get("style", 1) == 0:
			# 预告（如注亡拟嗣生成点）：没有伤害，压低亮度，别和伤害圈抢眼
			fa *= 0.4
			oa *= 0.45
		var fill := Color(c.r, c.g, c.b, fa * 1.3)
		var line := Color(c.r, c.g, c.b, oa)
		match w.shape:
			"circle":
				g.draw_set_transform(w.pos, 0.0, Vector2(1.0, g.combat.GROUND_Y))
				g.draw_circle(Vector2.ZERO, w.r, fill)
				g.draw_circle(Vector2.ZERO, w.r * k, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 40, line, 2.5)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"line":
				g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), fill)
				g.draw_rect(Rect2(0.0, -w.wid * k, w.len, w.wid * 2.0 * k), Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), line, false, 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cone":
				var pts := PackedVector2Array([w.pos])
				var pts2 := PackedVector2Array([w.pos])
				for q in 17:
					var a: float = w.ang - w.half + w.half * 2.0 * q / 16.0
					var dv := Vector2.from_angle(a)
					pts.append(w.pos + dv * w.r)
					pts2.append(w.pos + dv * w.r * k)
				g.draw_colored_polygon(pts, fill)
				if k > 0.05:
					g.draw_colored_polygon(pts2, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				pts.append(w.pos)
				g.draw_polyline(pts, line, 2.5)
