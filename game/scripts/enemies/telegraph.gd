## 预警服务（docs/101 B2，10-15 从 boss_ai.gd 搬来）：g.warns 队列的登记 warn / 推进 update_warns / 判定 hits_leader、in_gap /
## 结算 warn_damage、warn_resolve。Boss 脚本、小怪招式（enemy_ai）、数据招式（boss_patterns）都经 g.tele 调；boss_ai 留同名转发。
## 有名字的 Boss 招式占「招式令牌」仍由 boss_ai 管（warn 里调 g.bai.claim_token）。填充层绘制在 render/telegraph_draw.gd，轮廓在 world.draw_warn_outlines
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const KP_LIFE := 0.25   # Boss 激光画面总长（秒）：判定在结算那一刻已结束，画面 ≤ 0.25 秒收完（用户 10-26「打完之后消失的很慢」；原 Kanpelle 0.42、缺图光束 0.4–0.55）
const UI = preload("res://scripts/ui.gd")

var g  # Game (Node2D)


func _init(game) -> void:
	g = game


## 预警 → 音效类别（docs/38 §8.11 对照表）：落地 land / 冲锋 charge / 光束 beam / 近身 melee / 全场 global
func cue_cat(w: Dictionary) -> String:
	if w.get("must_dash", false):
		return "global"
	if w.act == "final_attack" and w.shape == "line" and w.get("skin", "") in ["phantom", "choir"]:
		return "beam"
	match str(w.act):
		"dash", "stab":
			return "charge"
		"shot", "beam", "breath", "pattern_line", "ishar_line", "frost_track", "tide_link", "ishar_echo":
			return "beam"
		"bite", "sweep", "pattern_fan", "pattern_cleave", "spin_ring":
			return "melee"
	return "land"   # 落地圈、缺口环、大群之歌（song_ring：全场类的轻量版，不进全场警报）、轰击（lob）都算落地类


## Boss 招式预警：shape = circle / line / cone；dur 秒后结算 act
## 可选字段（docs/95 §12 底座，10-14）：
##   track_pos  "leader" / "self"：circle 在 track 秒内跟随主控 / 本体，之后冻结（叠影、寒冷）；line / cone 的 track 仍是转向追踪
##   seq_no     连发序号（1 / 2 / 3），画在预警起点 / 圈上（凝视、叠影）
##   gaps       缺口角度数组（与 gap_ang / gap_half 并存；多缺口环：大群之歌、环射）；circle 的 hits_leader 排除缺口弧
##   slow_t / slow_mult / slow_kind  命中后移速减速（秒 / 倍率，缺省 0.7；呼号）；chill  命中后寒冷秒数（走 frost_leader，骑士）
##   b_owner    直线另一端跟随的敌人（接潮「统一」双端跟随）
##   spawn_after / spawn_r / spawn_cap / spawn_life  sweep 结算后在扇形轴线 spawn_r 处生成该敌人（分形塑路：fractal、r140、本体所属 <8、20 秒自灭；docs/95 §5.2 C）
##   cone_fx    sweep 结算时扇形里放的特效帧条（缺图只有刀光）
func warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var w := {"shape": shape, "t": 0.0, "dur": dur, "owner": e, "pos": e.pos, "ang": 0.0, "r": 60.0, "len": 300.0, "wid": 14.0,
		"half": 0.8, "col": Color(1.0, 0.3, 0.35), "act": "", "dmg": e.dmg, "name": "", "corrode": 0.0, "done": false, "follow": false, "track": 0.0, "lock": true}
	w.merge(d, true)
	preload("res://scripts/run/boss_diag.gd").on_warn(w)
	# 预警样式（docs/38 §8.11）：界面按 style 画，不再从 follow / gap_ang 猜。0 预告（无伤害，低亮度）；① 落点圈 ② 直线 ③ 扇形 ④ 缺口环 ⑤ 必须冲刺。
	# follow 只表示「圈跟着施法者走」，钻地咬击、踏地、触须爆发都是 ① —— 走出圈即可
	if not w.has("style"):
		if w.get("must_dash", false):
			w.style = 5
		elif float(w.dmg) <= 0.0:
			w.style = 0
		elif shape == "line":
			w.style = 2
		elif shape == "cone":
			w.style = 3
		elif w.has("gap_ang") or w.has("gaps") or w.act in ["song_ring", "spin_ring"]:
			w.style = 4
		else:
			w.style = 1
	if w.has("gaps") and not w.has("gap_ang"):
		w.gap_ang = float(w.gaps[0])   # 画面 / 判定都先看 gap_ang；多缺口再看 gaps
	if w.get("track_pos", "") != "" and w.track > 0.0:
		w.pos = g.combat.arena_clamp(e.pos if str(w.track_pos) == "self" else g.ppos, 90.0)
	# Boss 激光蓄力加快（用户 10-29，docs/201）：带 kp（Kanpelle 光束）的预警，蓄力与追踪段 × boss/laser_tell_k，
	# 不低于 boss/laser_tell_min（0.6 秒，下面的通用下限也兜底）；开火后的保持 / 扫速不在这里，不变
	if e.boss and w.has("kp"):
		var lk: float = Bal.v("boss/laser_tell_k", 0.65)
		if lk < 1.0 and w.dur > Bal.v("boss/laser_tell_min", 0.6):
			var nd: float = maxf(w.dur * lk, Bal.v("boss/laser_tell_min", 0.6))
			w.track = float(w.track) * nd / w.dur
			w.dur = nd
	# 时序下限（§1.9、docs/48 P0-2）：Boss 预警总时长 ≥0.6 秒；锁定（追踪结束 → 结算）≥0.4 秒，不够时缩短追踪段
	if e.boss:
		w.dur = maxf(w.dur, 0.6)
		w.track = minf(w.track, maxf(0.0, w.dur - 0.4))
		if float(w.dmg) > 0.0:
			e.moves_n = int(e.get("moves_n", 0)) + 1   # docs/117 节奏审计：Boss 有伤害的预警次数，纯计数字段，只读不改判定
	# 冲刺 / 突刺的预警线长 = 实际冲出的距离（docs/48 P0-3：原来斥亡体画 190 冲 373、塑路者画 440 冲 214）：
	# 按击退每秒衰减 900 算，距离 = v²/1800 + 本体半径（自冲不受重型削减）。fit_len：按设计线长反推速度（骑士冲锋、塑路者冲撞要真冲到位）
	if w.act in ["dash", "stab"] and shape == "line":
		if w.get("fit_len", false):
			# Reborn Knight travels 1.4x faster at the same telegraphed distance.
			w.dash_decel = 1764.0 if w.act=="dash" and e.type=="knight_boss" and e.phase==2 else 900.0
			w.spd = sqrt(2.0 * w.dash_decel * maxf(w.len - e.r, 40.0))
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
	if e.type == "knight_boss":
		g.bai.boss(e.type).on_warning(e,w)
	# 大招固定音效（docs/38 §8.11）：有名字的 Boss 招式起手播「类别起手音 + Boss 专属音色」，结算时播命中音
	if e.boss and w.name != "":
		w.cue = cue_cat(w)
		Sfx.play_cue(w.cue, e.type, "start")
	if e.boss and w.name != "":
		g.bai.claim_token(e, g.t + w.dur + 0.6)
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



func update_warns(dt: float) -> void:
	for w in g.warns:
		w.t += dt
		var e: Dictionary = w.owner
		var source = w.get("source")
		if source is Dictionary and source.get("dead", false):
			w.done = true
			w.t = w.dur + 1.0
			continue
		if w.follow and not e.dead:
			w.pos = e.pos
		var bo = w.get("b_owner")
		if bo is Dictionary and not bo.dead and not e.dead:
			if w.t < w.track or w.track <= 0.0:
				# 双端跟随（接潮「统一」）：幽灵线段起点跟本体、终点跟另一具
				w.pos = e.pos
				w.ang = (bo.pos - e.pos).angle()
				w.len = e.pos.distance_to(bo.pos)
			elif not w.get("b_locked", false):
				# 锁定：线冻结在这一刻，两体停步到结算（docs/95 §8.2 C：线两端都在动，锁定段必须站住，画即判）
				w.b_locked = true
				var rem: float = w.dur - w.t
				e.wind = maxf(e.get("wind", 0.0), rem)
				bo.wind = maxf(bo.get("wind", 0.0), rem)
		if w.track > 0.0 and w.t < w.track:
			if w.get("track_center", false):
				w.pos = g.ppos - Vector2.from_angle(w.ang) * w.len * 0.5
			elif w.shape != "circle" and not (bo is Dictionary):
				var target: Vector2 = g.ppos + Vector2(0, -14)
				var op = w.get("aim_op")
				if is_instance_valid(op) and op.pos != Vector2.INF:
					target = op.pos + Vector2(0, -14)
				if source is Dictionary:
					w.pos = source.pos
				var want: float = (target - w.pos).angle() + float(w.get("aim_offset", 0.0))
				if w.get("aim_extend", false):
					w.len = maxf(w.len, w.pos.distance_to(target) + 40.0)
				w.ang = lerp_angle(w.ang, want, minf(1.0, dt * 10.0))
			elif w.get("track_pos", "") != "":
				# 落点圈追踪（叠影跟主控、寒冷跟本体）：track 秒内跟着走，之后冻结在锁定时刻的位置
				w.pos = g.combat.arena_clamp(e.pos if str(w.track_pos) == "self" else g.ppos, 90.0)
		if w.act == "final_attack" and w.get("skin", "") == "crescent" and not w.done:
			e.fx = cos(w.ang)
		if w.t >= w.dur and not w.done:
			w.done = true
			if not e.dead or (w.shape == "circle" and not w.get("cancel_dead", false)):
				warn_resolve(w)
	g.warns = g.warns.filter(func(w): return w.t < w.dur + 0.25)



func hits_leader(w: Dictionary) -> bool:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	match w.shape:
		"arc":
			var center: Vector2 = w.pos - Vector2.from_angle(w.ang)*float(w.get("arc_back",0.0))
			var delta: Vector2 = pp - center
			var offset := clampf(angle_difference(w.ang, delta.angle()), -float(w.half), float(w.half))
			var nearest: Vector2 = center + Vector2.from_angle(w.ang + offset) * w.r
			return nearest.distance_to(pp) < w.wid + 12.0
		"circle":
			if g.combat.ground_d(g.ppos, w.pos) < float(w.get("inner_r", 0.0)):
				return false
			if g.combat.ground_d(g.ppos, w.pos) >= w.r:   # 画即判：主控脚底落在画出的椭圆里才算中（§1.9）
				return false
			return not in_gap(w, (g.ppos - w.pos).angle())   # 缺口环（长枪回旋等一次性判定）：站在缺口弧里不算中
		"line":
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			return Geometry2D.get_closest_point_to_segment(pp, w.pos, b).distance_to(pp) < w.wid + 12.0
		"cone":
			var dv: Vector2 = pp - w.pos
			if w.get("skin","")=="ice_field":
				if w.has("arena_radius") and pp.distance_to(w.arena_center)>w.arena_radius: return false
				return dv.length()>=float(w.get("inner_r",0.0)) and dv.length()<w.r and absf(angle_difference(dv.angle(),w.ang))<w.half
			return dv.length() < w.r + 10.0 and absf(angle_difference(dv.angle(), w.ang)) < w.half + 0.12
	return false



## 角度 a 是否落在预警 / 冲击环的缺口弧里（gap_ang + gap_half，或 gaps 数组里任一缺口）
func in_gap(w: Dictionary, a: float) -> bool:
	var gh: float = float(w.get("gap_half", 0.0))
	if gh <= 0.0:
		return false
	for ga in w.get("gaps", [w.get("gap_ang", INF)]):
		if absf(angle_difference(a, float(ga))) < gh:
			return true
	return false



func warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	if not hits_leader(w):
		return
	var e: Dictionary = w.owner
	# 伤害来源名：Boss 的招式记 boss_<类型>，普通怪 / 精英借用预警系统的招式记 atk_<类型>（引痕者前刺、钻地咬击、踏地等；
	# 原来一律记 boss_，统计里被误算成 Boss。Boss 保护看的是 enemy_hit 的 boss 标记 = e.boss，不看这个名字）
	var dsrc: String = ("boss_" if e.boss else "atk_") + e.type
	preload("res://scripts/run/boss_diag.gd").tag = str(w.get("act", "")) + "/" + str(w.get("name", ""))
	var it: Array = ["远程", "法术"] if w.act in ["pillar", "burst", "beam", "pattern_rain", "tide_link"] else (["远程", "物理"] if w.act == "shot" else ["近战", "物理"])
	if w.get("arts", false):
		it = ["近战", "法术"]   # 伊祖米克「分享」：近战法术溅射（PRTS）
	var true_damage: bool = w.get("true", false)
	if true_damage:
		it = ["远程" if w.act in ["ishar_strike", "ishar_line", "ishar_volley", "ishar_echo"] else "近战", "真实"]
	if w.has("hit_range"):
		it[0] = str(w.hit_range)
	if g.invuln <= 0.0:
		var hp_before: float = g.hp
		g.combat.enemy_hit(w.dmg, {"corrode": w.corrode, "boss": e.boss, "nerve": float(w.get("nerve", 0.0)),
			"frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type, "warn": true}, true_damage, true, it, dsrc)   # 预警系统精英也在用（钻地咬击、踏地），按放招的敌人算
		if not e.boss and g.hp < hp_before and float(w.get("stun", 0.0)) > 0.0 and g.t >= g.combat.enemy_stun_next:
			g.combat.enemy_stun_next = g.t + 8.0
			if not g.combat.stun_as_slow():
				g.pstun = maxf(g.pstun, minf(float(w.stun), 0.25))
		if stun_t > 0.0 and not g.combat.stun_as_slow(e.boss):   # Boss 战里僵直改成减速（docs/38 §1.11）
			g.pstun = maxf(g.pstun, stun_t)
		if slow and not g.combat.atk_slow_as_slow(3.0, e.boss):   # Boss 来源不写 atk_slow，改成移速减速（docs/38 §1.11）
			g.atk_slow = 3.0
		if g.hp < hp_before:
			# 招式自带的命中附加（docs/95 §12）：移速减速 slow_t 秒（呼号 1.5 秒 −30%）/ 寒冷 chill 秒（骑士；走冰霜，受 Boss 战移速下限 0.7）
			if float(w.get("slow_t", 0.0)) > 0.0:
				g.combat.slow_leader(str(w.get("slow_kind", "boss_move")), float(w.slow_t), float(w.get("slow_mult", 0.7)))
			if float(w.get("chill", 0.0)) > 0.0:
				g.combat.frost_leader(float(w.chill), "boss")
				g.vfx.add_text(g.ppos + Vector2(0, -96), "寒冷", Color(0.65, 0.9, 1.3), 14)
			if float(w.get("corrode_amp", 0.0)) > 0.0:
				# 蚀潮吐息（docs/95 §9.2 C）：命中后 corrode_amp_t 秒内侵蚀结算伤害 ×（1 + corrode_amp），仍受 Boss 持续伤害上限（combat.drain_corrode）
				g.combat.corrode_amp_until = g.t + float(w.get("corrode_amp_t", 3.0))
				g.combat.corrode_amp_mult = 1.0 + float(w.corrode_amp)



func warn_resolve(w: Dictionary) -> void:
	var n0: int = g.fx.size()
	_resolve(w)
	var e: Dictionary = w.owner
	if e.get("boss", false) and Bal.v("render/boss_fx_grains", 1.0) > 0.0:
		var bc: Color = g.vfx.boss_color(str(e.type))
		for i in range(n0, g.fx.size()):
			if not g.fx[i].has("bfx"):
				g.fx[i]["bfx"] = bc


func _resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var c: Color = w.col
	if w.act == "final_attack" and g.bai.finals.cancelled(w):
		return
	if w.act == "tide_link" and (e.get("partner") == null or e.partner.dead):
		return
	if w.has("cue"):
		Sfx.play_cue(w.cue, e.type, "hit")
	elif e.boss and cue_cat(w) == "beam":
		# 连发后续轮次通常省略招式名，但每轮实际发射仍需提示音。
		Sfx.play_cue("beam", e.type, "hit")
	if e.boss:
		# 预警结束后明确重新起攻击动作，而不是沿用蓄力末帧。
		e.pose = 0.35
		e.pose_max = 0.35
	# 出手事件（给画面层画攻击特效用，界面与美术读）：动作、形状、位置、朝向、范围、时刻
	e.last_act = {"act": w.act, "shape": w.shape, "pos": w.pos, "ang": w.ang, "r": w.r, "len": w.len, "wid": w.wid, "half": w.half, "t": g.t,
		"thrust": w.get("thrust", false), "name": w.name, "skin": w.get("skin", "")}
	if w.get("secondary", false):
		e.atk_until = g.t + 0.35
	if w.act=="knight_seed": return # The spear landing, not release, emits the impact and pillar warnings.
	var dv := Vector2.from_angle(w.ang)
	if w.act == "final_attack":
		g.bai.finals.resolve(w)
		return
	if str(w.act).begins_with("pattern_"):
		g.bai.patterns.resolve(w)
		return
	if e.get("boss", false):
		g.vfx.boss_signature(w)
	if str(w.get("atk_fx", "")) != "":
		_atk_fx(e, w, dv)
	match w.act:
		"frost_track":
			var ice_fx: Dictionary = w.duplicate()
			ice_fx.merge({"kind": "final_impact", "skin": "ice", "life": 0.36, "max": 0.36, "enemy": true}, true)
			g.fx.append(ice_fx)
			for i in 8:
				var pos: Vector2 = w.pos + dv * w.len * (float(i) + 0.5) / 8.0
				g.fx.append({"kind": "frost_step", "pos": pos, "r": 13.0, "life": 0.9, "max": 0.9, "enemy": true})
			g.vfx.fx_sprite("fx_knight_impact", w.pos + dv * w.len, g.PX * 1.2)
			g.vfx.sparks(w.pos + dv * w.len, dv, c, 10, 180.0)
			e.hunt_angle = w.ang
			e.hunt_follow_at = g.t + 0.25
			Sfx.play("hit", -9.0, 1.4)
			warn_damage(w)
		"tide_link":
			if not _kp(w, w.pos, w.pos + dv * w.len):
				g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": KP_LIFE, "max": KP_LIFE, "col": c, "enemy": true})
			var sw = w.get("b_owner")
			if w.get("swap", false) and sw is Dictionary and not sw.dead and not e.dead:
				# 接潮「换位」（docs/142b §3.8）：两具互换位置
				var tmp: Vector2 = e.pos
				e.pos = sw.pos
				sw.pos = tmp
				g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.4, "max": 0.4, "col": c, "enemy": true})
				g.fx.append({"kind": "ring", "pos": sw.pos, "r": sw.r * 2.2, "life": 0.4, "max": 0.4, "col": c, "enemy": true})
				Sfx.play("tentacle", -4.0, 0.7)
			g.vfx.fx_sprite("fx_water_splash", w.pos + dv * w.len, g.PX * 1.2)
			Sfx.play("tentacle", -8.0, 1.1)
			warn_damage(w)
		"ishar_echo":
			if _ishar_laser(e):
				pass   # 10-31：统一光束由 render/ishar_tell_draw 画（ishar_combos._fade_fx）
			elif not _kp(w, w.pos, w.pos + dv * w.len):
				g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": KP_LIFE, "max": KP_LIFE, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos, g.PX * 1.0)
			Sfx.play("tentacle", -8.0, 1.25)
			warn_damage(w)
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
					"atk": D.ENEMIES[e.type].get("atk", "法术"), "boss": e.boss, "src_type": e.type, "source_id": e.id, "no_rock": true})   # no_rock：预警类攻击不受地形阻挡
			g.fx.append({"kind": "rays", "pos": w.pos, "life": 0.25, "max": 0.25, "col": c, "enemy": true})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
		"ishar_strike":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.45, "max": 0.45, "col": c})   # 落点打击保留水柱（10-31 用户「三重齐击改回原版，和激光做点差异」）
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, c, 10, 230.0)
			Sfx.play("tentacle", -6.0, 1.2)
			g.vfx.shake_screen(0.3)
			warn_damage(w)
		"ishar_line":
			if _ishar_laser(e):
				pass   # 10-31：统一光束由 render/ishar_tell_draw 画（ishar_combos._fade_fx），不叠通用光束和棘鳍闪光
			elif not _kp(w, w.pos, w.pos + dv * w.len):
				g.fx.append({"kind": "bbeam", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.28, "max": 0.28, "col": c, "wid": w.wid})
			if not _ishar_laser(e) and g.vfx.fx_sprite("fx_ishar_line_muzzle", w.pos + dv * 30.0, g.PX * 1.2, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 每条线起点的棘鳍闪光（Codex fx_ishar_line_muzzle；缺图只有光束）
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
			g.vfx.shake_screen(0.25)
			warn_damage(w)
		"song_ring":
			# 大群之歌（docs/95 §2.2 C）：以本体为心的扩散环进 g.shocks，带缺口（gaps）、扩散 ≤220px/s、真实伤害命中一次；缺口判定在 enemies.update 的冲击环循环
			g.shocks.append({"pos": w.pos, "r": w.r, "maxr": float(w.get("maxr", 600.0)), "dmg": w.dmg, "hit": false, "boss": e.boss, "src_type": e.type,
				"spd": float(w.get("spd", 220.0)), "gaps": w.get("gaps", [w.get("gap_ang", INF)]), "gap_half": float(w.get("gap_half", 0.0)),
				"true": w.get("true", false), "col": c, "owner": e})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c, "enemy": true})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.4, 1.5), 12, 240.0)
			Sfx.play("tentacle", -6.0, 0.8)
			g.vfx.shake_screen(0.3)
		"spin_ring":
			# 长枪回旋（docs/95 §4.2 D）：静止缺口环一次性判定——主控在 r 内且不在缺口弧里才中（hits_leader 的 circle 分支排除缺口）；
			# 环刀光按环切 8 段排布，缺口段不画
			for k in 8:
				var ka: float = w.ang + TAU * k / 8.0
				if in_gap(w, ka):
					continue
				var kp: Vector2 = w.pos + Vector2(cos(ka), sin(ka) * g.combat.GROUND_Y) * w.r * 0.8
				if not g.vfx.fx_sprite("fx_slash_heavy_steel", kp, g.PX * 1.2, ka + PI * 0.5):
					g.fx.append({"kind": "bslash", "pos": w.pos, "ang": ka, "half": 0.35, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c, "enemy": true})
			Sfx.play("swing", 0.0, 0.5)
			g.vfx.shake_screen(0.6)
			warn_damage(w)
		"lob":
			# 轰击（docs/95 §6.2 C，第 2 批用）：固定落点圈结算 + 1.5 秒火光（纯画面）；耗弹由放招方按 ammo_cost 处理
			if not g.vfx.fx_sprite("fx_saint_shell_burst", w.pos, g.PX * 1.5, 0.0):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r * 0.8, "life": 1.5, "max": 1.5, "col": Color(c.r * 1.2, c.g * 0.8, c.b * 0.5), "enemy": true})
			g.vfx.sparks(w.pos, Vector2.UP, Color(1.6, 1.0, 0.5), 16, 280.0)
			Sfx.play("boom", -2.0, 0.9, 0.0)
			g.vfx.shake_screen(0.8)
			warn_damage(w)
		"pillar":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.55, "max": 0.55, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.2, 1.6), 14, 260.0)
			Sfx.play("tentacle", -5.0, 1.1)
			g.vfx.shake_screen(0.3)
			warn_damage(w, 0.4)
		"frost":
			# 寒冷（骑士，docs/95 §4.2 C）：结算圈 + 留 6 秒冰面（r = w.r，只减速；knight_boss.gd step）；Codex fx_knight_frost_burst 到了优先，缺图走程序冰晶
			e.frost_pos = w.pos
			e.frost_t = 6.0
			g.fx.append({"kind": "frost", "pos": w.pos, "r": w.r, "life": 6.0, "max": 6.0, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			if g.vfx.fx_sprite("fx_knight_frost_burst", w.pos, g.PX * 1.6, 0.0):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 16, 240.0)
			Sfx.play("skill", -4.0, 0.7)
			warn_damage(w)
		"slam":
			# 小怪踏地（奠基者）的冲击环与地裂画在地面层（单位之下，用户 10-24「浮在最上面」）；Boss 的仍压在单位之上
			g.shocks.append({"pos": w.pos, "r": e.r, "maxr": w.r, "dmg": w.dmg, "hit": false, "boss": e.boss, "src_type": e.type, "ground": not e.boss})
			# 地裂（界面与美术 10-01，协调人定）：塑路者锈红、奠基者土黄暗色（起宽加粗），同干员的共用地裂画法（render/ground_crack.gd）；其他仍走旧放射线
			var gc_col = {"path": Color(0.95, 0.38, 0.22), "founder": Color(0.62, 0.46, 0.22)}.get(e.type)
			if gc_col != null:
				g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.7, "max": 0.7, "col": gc_col, "enemy": true, "ground": not e.boss,
					"opts": {"n": 10} if e.type == "path" else {"n": 11, "w0": Vector2(5.0, 7.0)}})
			else:
				g.fx.append({"kind": "quake", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.8, 0.7, 0.6), 18, 300.0)
			Sfx.play("boom", 0.0, 0.6, 0.0)
			g.vfx.shake_screen(1.2)
			g.vfx.stop(0.05, "boss_slam")
		"burst":
			# 叠影每圈结算（docs/95 §1.2 C）：Codex fx_paranoia_stack（泡影从地面涌起破裂）优先，缺图走程序爆点；每圈一声「啵」按序号逐次升调
			if not (e.type == "paranoia" and g.vfx.fx_sprite("fx_paranoia_stack", w.pos, g.PX * 1.4, 0.0)):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": Color(0.7, 0.35, 1.0)})
			g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.ZERO, Color(1.2, 0.6, 1.8), 12, 240.0)
			Sfx.play("boom", -8.0, 1.2 + 0.12 * float(w.get("seq_no", 1) - 1), 0.0)
			warn_damage(w)
		"shot":
			var b: Vector2 = w.pos + dv * w.len
			if str(w.get("kp", "")) != "":
				# Boss 激光（Kanpelle 帧条，docs/142b §8.5）：w.kp = 帧条名里的 Boss 段，kp_k = 粗细（世界像素 / 美术像素）
				g.fx.append({"kind": "kp_beam", "a": w.pos + Vector2(0, -18), "b": b, "life": KP_LIFE, "max": KP_LIFE, "boss": str(w.kp), "k": float(w.get("kp_k", 2.0)), "enemy": true})
			else:
				g.fx.append({"kind": "tracer", "a": w.pos + Vector2(0, -18), "b": b, "life": 0.35, "max": 0.35, "col": c, "wid": w.wid})
			g.vfx.sparks(w.pos + dv * 24.0, dv, c if w.get("secondary", false) else Color(2.0, 1.6, 0.8), 8, 320.0)
			Sfx.play("hit", 0.0, 0.5, 0.0)
			g.vfx.shake_screen(0.4)
			warn_damage(w)
		"beam":
			var b2: Vector2 = w.pos + dv * w.len
			var eye: Vector2 = Vector2.ZERO if w.get("no_eye", false) else Vector2(0, -20)   # 眼位偏移只给从本体射出的线
			if not _kp(w, w.pos + eye, b2):
				g.fx.append({"kind": "bbeam", "a": w.pos + eye, "b": b2, "life": KP_LIFE, "max": KP_LIFE, "col": c, "wid": w.wid})
			if e.type == "paranoia":
				# 凝视命中端的紫白爆点（Codex fx_paranoia_gaze_hit；缺图只有光束）：画在主控被打到的位置，没打到画在线端
				var hp: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos + Vector2(0, -14), w.pos, b2) if hits_leader(w) else b2
				if g.vfx.fx_sprite("fx_paranoia_gaze_hit", hp, g.PX * 1.3, 0.0):
					g.fx[g.fx.size() - 1]["enemy"] = true
			Sfx.play("skill", -2.0, 0.5)
			g.vfx.shake_screen(0.7)
			warn_damage(w, 0.0, true)
		"sweep":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			# 扇形内的喷涌特效（Codex 第 1 批：泡影呼号 fx_paranoia_howl、伊祖米克分享 fx_izumik_share；左中原点朝右，程序按扇形旋转、按 r 缩放；缺图只有刀光）
			var cone_fx: String = str(w.get("cone_fx", "fx_paranoia_howl" if w.get("howl", false) else ("fx_izumik_share" if w.get("arts", false) else "")))
			if cone_fx != "" and g.vfx.fx_sprite(cone_fx, w.pos + dv * w.r * 0.5, g.PX * clampf(w.r / 160.0, 0.8, 2.2), w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos + dv * w.r * 0.6, dv, Color(0.8, 1.4, 1.4), 12, 260.0)
			Sfx.play("swing", -2.0, 0.55)
			g.vfx.shake_screen(0.5)
			warn_damage(w, 0.25)
			if str(w.get("spawn_after", "")) != "" and not e.dead:
				_spawn_after(e, w, dv)
		"smash":
			# 炮身砸击（卡门第二幕，docs/95 §7.2 D）：落点圈结算（她在起手时已冲到圈边，saint.gd）；金色地裂 + Codex fx_carmen_smash（缺图只有地裂与尘土）
			g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.8, 0.35), "enemy": true, "opts": {"n": 8}})
			if g.vfx.fx_sprite("fx_carmen_smash", w.pos, g.PX * 1.4, 0.0, false, false, Color.WHITE, true):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(1.4, 1.1, 0.6), 14, 240.0)
			Sfx.play("boom", -4.0, 1.1, 0.0)
			g.vfx.shake_screen(0.6)
			warn_damage(w)
		"breath":
			# 蚀潮吐息（蔑死体，docs/95 §9.2 C）：口部射出的腐蚀流；Codex fx_archon_breath（左中原点朝右，按线长拉伸）缺图走程序光束
			if not _kp(w, w.pos + Vector2(0, -16), w.pos + dv * w.len):
				g.fx.append({"kind": "bbeam", "a": w.pos + Vector2(0, -16), "b": w.pos + dv * w.len, "life": KP_LIFE, "max": KP_LIFE, "col": c, "wid": w.wid, "enemy": true})
				if g.vfx.fx_sprite("fx_archon_breath", w.pos + Vector2(0, -16), g.PX * w.len / 320.0, w.ang, false, false, Color.WHITE, false, Vector2(0, 24)):
					g.fx[g.fx.size() - 1]["enemy"] = true
			Sfx.play("tentacle", -6.0, 1.3)
			g.vfx.shake_screen(0.3)
			warn_damage(w)
		"erupt":
			# 迸发（斥亡体，docs/95 §10.2 C）：以自身为心的落点圈结算；Codex fx_immortal_burst 优先，缺图走程序爆点
			if not g.vfx.fx_sprite("fx_immortal_burst", w.pos, g.PX * w.r / 60.0, 0.0, false, false, Color.WHITE, true):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 14, 260.0)
			Sfx.play("boom", -5.0, 1.3, 0.0)
			g.vfx.shake_screen(0.5)
			warn_damage(w)
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
			warn_damage(w, 0.3)
		"dash":
			e.land_break = float(w.get("close_break", 0.0))
			e.kb = dv * w.get("spd", 600.0)
			e.dash_decel = float(w.get("dash_decel",900.0))
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.45
			e.pose = 0.45
			e.pose_max = 0.45
			g.vfx.sparks(e.pos, -dv, Color(0.9, 0.9, 1.0), 10, 200.0)
			Sfx.play("swing", -4.0, 0.5)
		"stab":
			e.kb = dv * w.get("spd", 800.0)
			e.dash_decel = 900.0
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.2
			e.pose = 0.25
			e.pose_max = 0.25
			g.fx.append({"kind": "tracer", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.22, "max": 0.22, "col": c, "wid": w.wid})
			Sfx.play("swing", -6.0, 0.7)
			warn_damage(w)
		"izu_wave":
			# 震撼（原全场地波）：没有缺口、覆盖全场；冲刺无敌或站在点亮的灯柱光圈里才躲得开。伤害 ≤ 最大生命 25%，减速 1.5 秒，不僵直；
			# 33% 后（w.burn > 0）命中者 4 秒持续法伤（izumik.gd _burn_step），地波环改双层
			g.bai.boss("izumik").wave_fx(e, w)   # 伊祖米克全场海浪 + 颗粒（docs/170，原来两道细环）
			g.fx.append({"kind": "gcrack", "pos": e.pos, "r": 170.0, "life": 0.9, "max": 0.9, "col": Color(0.9, 0.4, 1.15), "enemy": true, "opts": {"n": 12}})   # 地波源头：伊祖米克脚下大地裂（纯画面，界面与美术 10-01）
			Sfx.play("boom", -2.0, 0.5, 0.0)
			var safe: bool = g.bai.izumik_safe(e)   # 先判安全再熄灯（熄掉的灯柱这一下仍算庇护）
			if w.get("share_all", false):
				# 伊祖米克三幕「分享·全场」（docs/142b §3.7）：结算这一刻你站着的那根亮灯柱熄灭
				for l in e.get("lamps", []):
					if l.lit and g.combat.ground_d(g.ppos, l.pos) < float(e.get("lamp_r", 120.0)):
						g.fx.append({"kind": "ring", "pos": l.pos, "r": float(e.get("lamp_r", 120.0)), "life": 0.6, "max": 0.6, "col": Color(0.5, 0.6, 0.8), "enemy": true})
						g.vfx.add_text(l.pos + Vector2(0, -40), "灯柱熄灭", Color(0.7, 0.75, 0.9), 15)
						l.out = true
						l.lit = false
						break
			if g.invuln <= 0.0 and not safe:
				g.combat.enemy_hit(w.dmg, {"boss": true, "src_type": e.type}, false, true, ["远程", "法术"], "boss_" + e.type)
				g.combat.slow_leader("wave", 1.5, 0.6)
				if float(w.get("burn", 0.0)) > 0.0:
					e.burn_t = 4.0
					e.burn_dps = float(w.burn)
					e.burn_acc = 0.0
		"bite":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.25, "max": 0.25, "col": c})
			if w.get("thrust", false) and g.vfx.fx_sprite("fx_knight_thrust", w.pos + dv * w.r * 0.55, g.PX * 1.3, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 连刺第 3 段前刺的枪尖寒光（Codex fx_knight_thrust；缺图只有刀光）
			if w.get("mirror", false) and g.vfx.fx_sprite("fx_ishar_maw_red", w.pos + dv * w.r * 0.5, g.PX * 1.2, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 伊莎玛拉濒死强化第 2 段的红色牙光（Codex fx_ishar_maw_red）
			g.vfx.sparks(w.pos + dv * w.r * 0.65, dv, c, 6, 150.0)
			Sfx.play("swing", -6.0, 0.9)
			warn_damage(w)



## Boss 激光（Kanpelle 帧条，docs/142b §8.5）：预警带 kp（帧条里的 Boss 段名）就画 kp_beam，返回 true = 调用方跳过原来的光束画法；kp_k = 粗细
## 伊莎玛拉统一光束（10-31 用户「激光不像激光、所有激光统一」）：render/ishar_laser 1 时结算帧只留伤害与音效，画面全交 ishar_tell_draw
func _ishar_laser(e: Dictionary) -> bool:
	return str(e.get("type", "")) == "ishar" and Bal.v("render/ishar_laser", 1.0) > 0.0 and Bal.v("render/ishar_tell", 1.0) > 0.0


func _kp(w: Dictionary, a: Vector2, b: Vector2) -> bool:
	if str(w.get("kp", "")) == "":
		return false
	# kp_life / kp_on：可选的画面总长与开合时长（偏执泡影凝视是持续光束，docs/170；缺省 KP_LIFE / 0.06）
	var kl: float = float(w.get("kp_life", KP_LIFE))
	g.fx.append({"kind": "kp_beam", "a": a, "b": b, "life": kl, "max": kl, "on_t": float(w.get("kp_on", 0.06)), "boss": str(w.kp), "k": float(w.get("kp_k", 2.0)), "enemy": true})
	return true


## 小怪器官攻击的出手特效（docs/96 §2.2，Codex 第 2 批：收割者镰肢 fx_reaper_scythe、引痕者触须刺击 fx_tracer_thrust（狂暴 _enraged）、巢涌者触须横扫 fx_nest_sweep）：
## 帧条朝右，朝左出手时镜像（spr_rot 先镜像再转，角度减 π）；原点 = enemies.json atk_fx_origin（1x 美术像素，manifest 的 origin_1x，缺省帧中心），
## 画在本体中心偏上 0.6 r；按本体缩放（world.enemy_scale）。缺图 fx_sprite 返回 false，程序刀光照旧。纯画面，不碰随机数
func _atk_fx(e: Dictionary, w: Dictionary, dv: Vector2) -> void:
	var left: bool = dv.x < 0.0 and w.shape != "circle"
	var ang: float = 0.0 if w.shape == "circle" else (w.ang - PI if left else w.ang)
	var o: Array = w.get("atk_fx_origin", [-1, -1])
	if g.vfx.fx_sprite(str(w.atk_fx), e.pos + Vector2(0, -e.r * 0.6), D.enemy_scale(e, g.t, g.PX), ang, left, false, Color.WHITE, false, Vector2(float(o[0]), float(o[1]))):
		g.fx[g.fx.size() - 1]["enemy"] = true


## sweep 结算后的召唤（分形塑路，docs/95 §5.2 C）：不管命没命中，扇形轴线 spawn_r 处长出一只 spawn_after；本体所属的同类 ≥ spawn_cap 时不长。
## 长出来的记进 e.spawned_after（Boss 脚本按 expire_at 让它自灭）；Codex fx_path_fractal_rise（从劈痕里长出）缺图走程序光环
func _spawn_after(e: Dictionary, w: Dictionary, dv: Vector2) -> void:
	var kind: String = str(w.spawn_after)
	var n := 0
	for o in g.enemies:
		if o.type == kind and not o.dead and is_same(o.get("owner"), e):
			n += 1
	if n >= int(w.get("spawn_cap", 8)):
		return
	var at: Vector2 = g.combat.arena_clamp(w.pos + dv * float(w.get("spawn_r", 140.0)), 60.0)
	var o: Dictionary = g.spawner.spawn_enemy(kind, at)
	o.owner = e
	o.expire_at = g.t + float(w.get("spawn_life", 20.0))
	var lst: Array = e.get("spawned_after", [])
	lst.append(o)
	e["spawned_after"] = lst
	if g.vfx.fx_sprite("fx_path_fractal_rise", at, g.PX, 0.0, false, true):
		g.fx[g.fx.size() - 1]["enemy"] = true
	else:
		g.fx.append({"kind": "ring", "pos": at, "r": 26.0, "life": 0.35, "max": 0.35, "col": w.col, "enemy": true})
