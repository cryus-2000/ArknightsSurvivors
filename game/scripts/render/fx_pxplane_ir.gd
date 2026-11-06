## 艾丽妮转平面（docs/272，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第五批四人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_irene.py 烤（图形 tools/pxplane_irene_art.py），键前缀 ir_；
## 刺击光刃、贯穿、手炮弹道、剑气细刺、提灯光圈 / 光尘、手提灯在这里按美术像素格逐格画（算法同 pxplane_irene_art.py 的
## lance() / lance_gd() / pierce() / tracer() / qi_needle() / lamp_ring() / lamp_motes() / lantern()，改一边要改另一边）。
## 只画：读玩法状态（o.hw.ir、o.vg.qi、敌人 air），不写玩法字段、不抽玩法随机数（本模块不抽随机数）。
## 挂在人身上的件跟她（光刃、月牙、枪口火光、追斩光刺）；起风水旋 / 挑刺 / 严律刺印跟被打的那只；冲击环、爆点、水花碎沫、提灯光圈留在原地。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")

const LT := [Color("#1e0c16"), Color("#4a1c32"), Color("#8a3a5a"), Color("#c8668a"), Color("#eaa0b8"), Color("#fbe0ea"), Color("#ffffff")]   # 白 + 粉（11-07 用户「主色调应该是白+粉为主，一技能的蓝色去掉」；粉取 PRTS 立绘 #d090a0 色相约 345°，docs/272 §8）
const LAMP := [Color("#1c1408"), Color("#4a3612"), Color("#8c6a26"), Color("#cfa24a"), Color("#efd08a"), Color("#fff0c6"), Color("#ffffff")]   # 金：只留给手提灯
const TIDE := [Color("#140a10"), Color("#2a1620"), Color("#46283a"), Color("#6e4458"), Color("#a8788c"), Color("#e0bfca"), Color("#fff2f5")]   # 原深海蓝潮水，11-07 改粉雾（去蓝，docs/272 §8）
const SHADOW := Color("#0e1218")
const SQ := 0.72
const LANCE_H := 11.0
const S2_R := [100, 116, 132]
const FIN_R := [75, 87, 99]
const S3_R := [80, 93, 106]
const GALE_R := [35, 45]
const TIDE_LIGHT := Color(1.0, 0.72, 0.84)
const PIERCE_N := 3        # 一刺至多画 3 只身上的贯穿
const RT_MAX := 48         # 运行时件上限（整队）

var r      # fx_pxplane 实例
var g
var rt: Array = []         # 运行时件：{k, t0, life, …}
var _lamp := {}            # 连携提灯：干员对象 id → 截止时间
var _air := {}
var _air_frame := -1
var _beat := {}


func _init(px) -> void:
	r = px
	g = px.g


static func _near(arr: Array, v: float) -> int:
	return PxU.nearest(arr, v)


static func _hsh(x: int, y: int, k: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF


static func _hf(x: int, y: int, k: int) -> float:
	return float(_hsh(x, y, k)) / 65535.0


func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


func _fr(t0: float) -> int:
	return r.frame_of(t0)


func _push_rt(o, it: Dictionary) -> void:
	if rt.size() >= RT_MAX:
		rt.pop_front()
	it["t0"] = g.t
	it["op"] = o
	rt.append(it)


## 帧条件：fo = 跟她（出手时相对脚底的偏移；fx_pxplane._gp 按她当前位置重算）
func _strip(o, k: String, at: Vector2, ly: String, flip := false, follow := false, gy := INF) -> void:
	var it := {"k": "ir_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": flip, "ly": ly, "oid": str(o.id)}
	if follow:
		it["fo"] = Pxp._snap(at) - o.pos
	if gy != INF:
		it["gy"] = gy
	r._push(it)


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != r._emit_frame:
		r._emit_frame = fr
		r._emit_n = 0
	if r._emit_n >= Pxp.EMIT_CAP:
		return
	r._emit_n += 1
	g.glow_next.append([p, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


## 一组 [x, y, 颜色, 发光 / 不透明度] 美术像素点，原点 = 世界坐标 o0（对齐 2 像素格）
func _pts(ci, o0: Vector2, lst: Array) -> void:
	var px: float = g.PX
	var base: Vector2 = Pxp._snap(o0)
	for q in lst:
		var p: Vector2 = base + Vector2(roundf(float(q[0])), roundf(float(q[1]))) * px
		var c: Color = q[2]
		var v = q[3]
		if v is bool:
			ci.draw_rect(Rect2(p, Vector2(px, px)), c)
			if v:
				_glow(p, c)
		else:
			ci.draw_rect(Rect2(p, Vector2(px, px)), Color(c.r, c.g, c.b, float(v)))


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"ir_thrust":   # 一段刺击：光刃（跟她）+ 投影 / 潮痕（贴地，跟她）+ 贯穿（跟被刺的那只）+ 首中处水珠 + 照地光
			var dv: Vector2 = d.d
			var es: Array = d.get("es", [])
			var star: bool = not d.get("gust", false) and Bal.v("fx/ir_atk_star", 0.0) > 0.0   # 11-07 用户「更喜欢旧版带星光的，现在太像激光」：普攻换星光画法（S1 起风不变）
			_push_rt(o, {"k": "lance", "d": dv, "L": float(d.L) * 0.5, "gust": d.get("gust", false), "star": star, "sd": int(fposmod(g.t * 997.0, 4096.0)), "life": 7.0 / 15.0 + (1.0 / 15.0 if star else 0.0) + 0.02})
			for i in mini(PIERCE_N, es.size()):
				_push_rt(o, {"k": "pierce", "e": es[i], "d": dv, "st": star, "life": (4.0 if star else 3.0) / 15.0 + 0.02})
			if not es.is_empty():
				var e0: Dictionary = es[0]
				var hp: Vector2 = e0.pos + Vector2(0, -float(e0.r) * 0.55 - float(e0.get("air", 0.0)))
				var gust: bool = d.get("gust", false)
				R._light(o, hp, 130.0 if gust else 90.0, 0.7 if gust else 0.5, 0.12, p.light)
				R._grains(o, hp, float(e0.pos.y) + 2.0, "ink", (5 if gust else 3) + mini(es.size() - 1, 2), {"tier": t}, dv)
		"ir_gust":   # S1 起风：首中那只脚下卷起水旋（跟着那只）；精一起脚下一圈细水纹
			var e: Dictionary = d.en
			_push_rt(o, {"k": "estrip", "e": e, "s": "ir_gust_e%d_up" % t, "oy": 0.0, "air": false, "life": 9.0 / 15.0 + 0.02, "ly": "up"})
			if t >= 1:
				_push_rt(o, {"k": "estrip", "e": e, "s": "ir_gust_gd", "oy": 0.0, "air": false, "life": 7.0 / 15.0 + 0.02, "ly": "gd"})
			R._light(o, e.pos + Vector2(0, -20), 140.0, 0.75, 0.14, TIDE_LIGHT)
			R._grains(o, e.pos + Vector2(0, -30), float(e.pos.y) + 2.0, "ink", 6 + 2 * t, {"tier": t})
		"ir_charge":   # 起风蓄光（S1 那一刺的起手，0.2 秒）：身前光点收拢（跟她）
			_push_rt(o, {"k": "charge", "d": Vector2.from_angle(float(d.ang)), "life": 3.0 / 15.0 + 0.02})
		"ir_launch":   # 精一挑刺（高 10 的那一下）：那只身下一道往上挑的金色细弧
			if float(d.get("h", 0.0)) <= 12.0 and not d.en.get("dead", false):
				_push_rt(o, {"k": "estrip", "e": d.en, "s": "ir_pick_up", "oy": 0.0, "air": false, "life": 5.0 / 15.0 + 0.02, "ly": "up"})
		"ir_strict":   # 严律：被停住那只头顶金白刺印（跟着那只，停多久亮多久）
			_push_rt(o, {"k": "estrip", "e": d.en, "s": "ir_brand", "oy": -float(d.en.r) * 2.4 - 12.0, "air": true, "life": float(d.get("dur", 0.3)) + 0.1, "ly": "up", "loop": true})
		"ir_cleave":
			_cleave(o, d, t, R, p)
		"ir_cannon":   # 手炮一发：枪口火光（跟她）+ 弹道细线 + 落点小爆（浮空的跟着抬）+ 灼痕
			var c: Vector2 = d.c
			var ce = d.get("en", null)
			var air: float = float(ce.get("air", 0.0)) if ce is Dictionary else 0.0
			var mz: Vector2 = d.mz
			_strip(o, "muz", mz, "up", false, true, o.pos.y + 1.0)
			_push_rt(o, {"k": "tracer", "a": mz, "b": c + Vector2(0, -10.0 - air), "life": 2.0 / 15.0 + 0.02})
			if _beat_n(o, "boom") < 3:
				_strip(o, "boom_up", c + Vector2(0, -air), "up", false, false, c.y + 1.0)
				_strip(o, "boom_gd", c, "gd")
				R._grains(o, c + Vector2(0, -10.0 - air), c.y + 2.0, "rock", 3, {"tier": t})
			R._light(o, c + Vector2(0, -10.0 - air), 110.0, 0.6, 0.12, p.light)
		"ir_gale":   # 卷风 / 响应起风：一圈螺旋水纹往里卷 + 几道往上飘的风线（留原地）
			var at: Vector2 = d.at
			var Rg: int = _near(GALE_R, float(d.r) * 0.5)
			_strip(o, "gale_r%d_gd" % Rg, at, "gd")
			_strip(o, "gale_r%d_up" % Rg, at, "up", false, false, at.y + 1.0)
			R._light(o, at + Vector2(0, -12), float(d.r) * 1.4, 0.5, 0.12, TIDE_LIGHT)
		"ir_link":
			if str(d.get("ph", "")) == "go":   # 提灯一照：区域只画边 + 往上飘的金色光尘；她手里提灯亮 0.9 秒
				var c2: Vector2 = d.c
				var rr: float = float(d.get("r", 150.0)) * 0.5
				_push_rt(o, {"k": "lampring", "c": c2, "r": rr, "life": 0.9})
				_push_rt(o, {"k": "motes", "c": c2, "r": rr, "life": 0.9, "seed": fposmod(c2.x * 0.013, TAU)})
				_lamp[o.get_instance_id()] = g.t + 0.9
				R._light(o, c2, rr * 2.0 + 40.0, 0.7, 0.15, p.light)
			else:   # 补刺：一道贯穿全程的长光刃（留在出发点，不跟她冲出去）+ 贯穿
				var a2: Vector2 = d.a
				var b2: Vector2 = d.b
				var dv2: Vector2 = (b2 - a2).normalized() if b2 != a2 else Vector2.RIGHT
				_push_rt(o, {"k": "lance", "fix": a2, "d": dv2, "L": a2.distance_to(b2) * 0.5, "gust": false, "link": true, "life": 6.0 / 15.0 + 0.02})
				var n := 0
				for e2 in d.get("es", []):
					if n >= 4:
						break
					n += 1
					_push_rt(o, {"k": "pierce", "e": e2, "d": dv2, "life": 3.0 / 15.0 + 0.02})
				R._light(o, a2.lerp(b2, 0.6), 160.0, 0.7, 0.12, p.light)
		"shape":   # exec_shape 的圆形招：卷风·追斩（src 起风）/ 裂潮·三度（src 裂潮）
			if not d.get("circle", false):
				return
			var c3: Vector2 = d.get("c", o.pos)
			match str(d.get("src", "")):
				"起风":
					_strip(o, "nova_up", o.pos, "up", false, true, o.pos.y + 1.0)
					R._light(o, o.pos + Vector2(0, -20), 160.0, 0.7, 0.12, p.light)
					R._grains(o, o.pos + Vector2(0, -20), o.pos.y + 2.0, "ink", 6, {"tier": t})
				"裂潮":
					_strip(o, "tide3_up", c3, "up", false, false, c3.y + 1.0)
					_strip(o, "tide3_gd", c3, "gd")
					R._light(o, c3 + Vector2(0, -10), 180.0, 0.75, 0.14, TIDE_LIGHT)
					R._grains(o, c3 + Vector2(0, -16), c3.y + 2.0, "ink", 10, {"tier": t})


## 斩：裂潮（look rose_heavy，二度裂潮同画）/ 裂潮余波（crescent）/ 判决（src 判决，整圈）
func _cleave(o, d: Dictionary, t: int, R, p: Dictionary) -> void:
	var ang: float = float(d.ang)
	var rr: float = float(d.r)
	var dv := Vector2.from_angle(ang)
	var es: Array = d.get("es", [])
	if str(d.get("src", "")) == "判决":
		var R3: int = _near(S3_R, rr * 0.5)
		_strip(o, "s3_r%d_gd" % R3, o.pos, "gd")
		_strip(o, "s3_r%d_up" % R3, o.pos, "up", false, false, o.pos.y + 1.0)
		R._light(o, o.pos + Vector2(0, -16), minf(240.0, rr * 1.3), 0.85, 0.15, p.light)
		R._grains(o, o.pos + Vector2(0, -24), o.pos.y + 2.0, "ink", 12, {"tier": t})
		return
	var dp: Array = Pxp.pick_dir(ang)
	var at: Vector2 = o.pos + Vector2(dv.x, dv.y * SQ) * rr * 0.6
	if str(d.get("look", "")) == "crescent":
		var Rf: int = _near(FIN_R, rr * 0.5)
		_strip(o, "fin_r%d_up_d%d" % [Rf, int(dp[0])], o.pos, "up", bool(dp[1]), true, o.pos.y + 1.0)
		_strip(o, "fin_r%d_gd_d%d" % [Rf, int(dp[0])], o.pos, "gd", bool(dp[1]), true)
		R._light(o, at + Vector2(0, -14), 150.0, 0.7, 0.12, p.light)
		R._grains(o, at + Vector2(0, -14), at.y + 2.0, "ink", 6, {"tier": t}, dv)
		return
	var R2: int = _near(S2_R, rr * 0.5)
	_strip(o, "s2_r%d_e%d_up_d%d" % [R2, maxi(1, t), int(dp[0])], o.pos, "up", bool(dp[1]), true, o.pos.y + 1.0)
	_strip(o, "s2_r%d_gd_d%d" % [R2, int(dp[0])], o.pos, "gd", bool(dp[1]), true)
	R._light(o, at + Vector2(0, -14), 180.0, 0.75, 0.14, p.light)
	R._grains(o, at + Vector2(0, -14), at.y + 2.0, "ink", 10 + mini(es.size(), 4), {"tier": t}, dv)


# ================================================================ 绘制

func _alive(it: Dictionary) -> bool:
	if g.t - float(it.t0) > float(it.life):
		return false
	if str(it.k) == "estrip" and it.e.get("dead", false):   # 跟怪的帧条随那只死掉收掉；贯穿照画完（刺死的那一下也要看得到）
		return false
	return true


## 地面层：帧条贴地件、刺击投影 / 潮痕、起风水纹、提灯光圈
func draw_floor(o) -> void:
	rt = rt.filter(_alive)
	var cv = o.cv
	var id: String = str(o.id)
	for it in r.items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)
	var t: int = r.tier(o)
	for it in rt:
		match str(it.k):
			"lance":
				if it.op == o and not it.has("fix") and not it.get("star", false):   # 星光画法没有长条，不投长影
					_pts(cv, o.pos, _lance_gd(float(it.L), it.d, _fr(float(it.t0)), t, it.gust))
			"estrip":
				if str(it.ly) == "gd" and it.op == o:
					r._draw_strip(cv, str(it.s), _fr(float(it.t0)), Pxp._snap(it.e.pos), false, true)
			"lampring":
				if it.op == o:
					_pts(cv, it.c, _lamp_ring(float(it.r), int(floor(g.t * 15.0)), g.t - float(it.t0), float(it.life)))


func draw_over(_o) -> void:
	pass


## 排序项：光刃 / 贯穿 / 弹道 / 跟怪帧条 / 光尘 / 手提灯 / 后期剑气细刺
func sort_items(o, out: Array) -> void:
	for it in rt:
		var k: String = str(it.k)
		if it.op != o:
			continue
		match k:
			"lance":
				var a: Vector2 = it.fix if it.has("fix") else o.pos
				var tip: Vector2 = a + (it.d as Vector2) * float(it.L) * 2.0
				out.append({"ir": it, "skey": maxf(a.y, tip.y) + 1.0})
			"pierce":
				out.append({"ir": it, "skey": float(it.e.pos.y) + 1.0})
			"charge":
				out.append({"ir": it, "skey": o.pos.y + 1.5})
			"tracer":
				out.append({"ir": it, "skey": maxf((it.a as Vector2).y, (it.b as Vector2).y) + 20.0})
			"estrip":
				if str(it.ly) == "up":
					out.append({"ir": it, "skey": float(it.e.pos.y) + 1.0})
			"motes":
				out.append({"ir": it, "skey": (it.c as Vector2).y + 1.0})
	if o.pos != Vector2.INF and (o.skill_active_left(2) > 0.0 or float(_lamp.get(o.get_instance_id(), -1.0)) > g.t):   # 手提灯：判决期间 / 连携提灯一照（状态件，原画法 _h3ir_draw_over 的灯改画像素提灯）
		out.append({"ir": {"k": "lantern", "op": o}, "skey": o.pos.y + 1.5})
	var vg = o.get("vg")
	if vg is Dictionary and not vg.is_empty():
		for q in vg.get("qi", []):
			out.append({"ir": {"k": "qi", "q": q, "op": o}, "skey": (q.p as Vector2).y + 1.0})


func draw_rt(ci, item: Dictionary) -> void:
	var it: Dictionary = item.ir
	var bt: int = int(floor(g.t * 15.0))
	match str(it.k):
		"lance":
			var a: Vector2 = it.fix if it.has("fix") else it.op.pos
			var t: int = 2 if it.get("link", false) else r.tier(it.op)
			if it.get("star", false):
				_pts(ci, a, _lance_star(float(it.L), it.d, _fr(float(it.t0)), t, int(it.get("sd", 0))))
			else:
				_pts(ci, a, _lance(float(it.L), it.d, _fr(float(it.t0)), t, it.gust, it.get("link", false)))
		"pierce":
			var e: Dictionary = it.e
			var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.55 - float(e.get("air", 0.0)))
			if it.get("st", false):
				_pts(ci, hp, _star_burst(_fr(float(it.t0)) - 1, int(e.get("id", 0))))   # 星光画法：刺尖到的那一拍炸开星芒
			else:
				_pts(ci, hp, _pierce(it.d, _fr(float(it.t0)) - 1, 1))   # 光锥第 1 拍到才闪
		"charge":
			_pts(ci, it.op.pos, _charge(it.d, _fr(float(it.t0))))
		"tracer":
			var a2: Vector2 = Pxp._snap(it.a)
			_pts(ci, a2, _tracer(((it.b as Vector2) - a2) * 0.5, _fr(float(it.t0))))
		"estrip":
			var e2: Dictionary = it.e
			var gp: Vector2 = e2.pos + Vector2(0, float(it.oy) - (float(e2.get("air", 0.0)) if it.air else 0.0))
			var fi: int = _fr(float(it.t0))
			r._draw_strip(ci, str(it.s), fi, Pxp._snap(gp), false, not it.get("loop", false))
		"motes":
			_pts(ci, it.c, _lamp_motes(float(it.r), bt, float(it.seed)))
		"lantern":
			var o = it.op
			var raised: bool = o.acting() and o.act_kind == "skill"
			var lp: Vector2 = o.pos + (Vector2(20.0 * o.face, -56.0) if raised else Vector2(16.0 * o.face, -22.0))
			_pts(ci, lp, _lantern(bt))
		"qi":
			var q: Dictionary = it.q
			var v: Vector2 = q.v
			var dq: Vector2 = v.normalized() if v != Vector2.ZERO else Vector2.RIGHT
			_pts(ci, (q.p as Vector2) + Vector2(0, -16), _qi_needle(dq, r.tier(it.op), bt))


## world.gd 画浮空敌人时（fx_pxplane.air_look 转来）：被艾丽妮挑起 / 掀起的敌人影子随高度缩小变淡、悬停时上下浮动 1 美术像素
func air_look(e: Dictionary) -> Vector2:
	var fr: int = Engine.get_process_frames()
	if fr != _air_frame:
		_air_frame = fr
		_air.clear()
		for o in g.squad.ops:
			if str(o.id) == "irene" and o.hw.has("ir"):
				for a in o.hw.ir.air:
					_air[int(a.e.get("id", -1))] = a
	var a2 = _air.get(int(e.get("id", -1)), null)
	if a2 == null:
		return Vector2(1.0, 0.0)
	var hk: float = clampf(1.0 - float(e.get("air", 0.0)) / 50.0, 0.5, 1.0)
	var bob := 0.0
	if float(a2.t) > 0.2 and float(a2.dur) - float(a2.t) > 0.25:
		bob = 2.0 if posmod(int(floor(g.t * 15.0)) / 3 + int(e.get("id", 0)), 2) == 1 else 0.0
	return Vector2(hk, bob)


# ================================================================ 运行时件的画法（同 tools/pxplane_irene_art.py）

static func _star(out: Array, x: float, y: float, arm: int, c0: Color, c1: Color, c2: Color) -> void:
	out.append([x, y, c0, true])
	for i in range(1, arm + 1):
		var c: Color = c1 if i < arm else c2
		out.append([x + i, y, c, false])
		out.append([x - i, y, c, false])
		out.append([x, y + i, c, false])
		out.append([x, y - i, c, false])


## 同 lance()：根宽头尖的实心光锥（白芯 + 淡紫 + 亮紫外缘）→ 收成亮线 → 从根部熄灭；出手星芒；精一刃尖碎芒
func _lance(L: float, d: Vector2, f: int, tier: int, gust: bool, link := false) -> Array:
	var n2 := Vector2(-d.y, d.x)
	var hot_f: int = 3 if gust else 2
	if f < 0 or f > hot_f + 3:
		return []
	if gust:
		L *= 1.1
	var s0 := 4.0
	var W0: float = 6.0 if (gust or link) else 3.5
	var h0 := Vector2(d.x * (s0 + 6.0), d.y * (s0 + 6.0) - LANCE_H - 1.0)
	var cells := {}
	if f >= 1 and f <= hot_f:   # 第 0 拍只闪星芒，第 1 拍起光锥一下贯穿到全长
		var Lc: float = L
		var n: int = int((Lc - s0) * 2.0) + 1
		for i in n + 1:
			var u: float = float(i) / float(n)
			var s: float = s0 + (Lc - s0) * u
			var ur: float = (s - s0) / maxf(1.0, L - s0)
			var hw: float = W0 * pow(1.0 - ur, 0.85)
			if ur < 0.06:
				hw *= 0.7 + 5.0 * ur
			var m: int = int(ceil(hw * 2.0))
			for j in range(-m, m + 1):
				var w: float = j / 2.0
				if absf(w) > hw + 0.25:
					continue
				var k: float = absf(w) / maxf(0.6, hw)
				var c: Color
				var gl := false
				if k < 0.34 or hw < 0.9:
					c = LT[6]
					gl = (i + j) % 2 == 0   # 白芯隔一格出 emit（体检 S1 emit p90 325 > 300，docs/272 §6）
				elif k < 0.62:
					c = LT[5]
				elif k < 0.86:
					c = LT[4]
				else:
					c = LT[3]
				cells[Vector2i(roundi(d.x * s + n2.x * w), roundi(d.y * s - LANCE_H + n2.y * w))] = [c, gl]
	elif f > hot_f:
		var g2: int = f - hot_f
		var lo: float = [0.0, 0.0, 0.4, 0.75][g2]
		var n3: int = int(L - s0)
		for i in n3 + 1:
			var u2: float = float(i) / float(n3)
			if u2 < lo:
				continue
			var s2: float = s0 + (L - s0) * u2
			if g2 == 3 and i % 2 == 1:
				continue
			var c2: Color = LT[6] if g2 == 1 and u2 < 0.95 else (LT[5] if g2 <= 2 else LT[4])
			cells[Vector2i(roundi(d.x * s2), roundi(d.y * s2 - LANCE_H))] = [c2, g2 == 1]
			if g2 == 1 and u2 < 0.6 and (gust or link):
				cells[Vector2i(roundi(d.x * s2 + n2.x), roundi(d.y * s2 - LANCE_H + n2.y))] = [LT[4], false]
				cells[Vector2i(roundi(d.x * s2 - n2.x), roundi(d.y * s2 - LANCE_H - n2.y))] = [LT[4], false]
	if f <= 1 and not link:   # 出手星芒（精二 / 起风八芒 + 一圈光点）
		var st: Array = []
		var arm: int = (6 if (gust or tier >= 2) else 5) if f == 0 else 2
		_star(st, h0.x, h0.y, arm, LT[6], LT[5], LT[4])
		for q in st:
			cells[Vector2i(roundi(float(q[0])), roundi(float(q[1])))] = [q[2], q[2] == LT[6]]
		if f == 0:
			var extra: Array = []
			for q2 in [-1, 1]:
				extra.append([h0.x + q2, h0.y, LT[6]])
				extra.append([h0.x, h0.y + q2, LT[6]])
			if tier >= 2 or gust:
				for q3 in range(1, 3):
					for sg in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
						extra.append([h0.x + sg.x * q3, h0.y + sg.y * q3, LT[5] if q3 == 1 else LT[4]])
				for q4 in 8:
					var a4: float = q4 / 8.0 * TAU
					extra.append([h0.x + roundf(cos(a4) * 6.0), h0.y + roundf(sin(a4) * 6.0), LT[4]])
			for e5 in extra:
				var k5 := Vector2i(roundi(float(e5[0])), roundi(float(e5[1])))
				if not cells.has(k5):
					cells[k5] = [e5[2], e5[2] == LT[6]]
	if tier >= 1 and not link and f >= hot_f and f <= hot_f + 1:   # 精一：刃尖崩出三道短碎芒
		var tp := Vector2(d.x * L, d.y * L - LANCE_H)
		for sp in [-0.45, 0.0, 0.45]:
			var a6: float = d.angle() + sp
			var r0: int = 1 + (f - hot_f) * 2
			var kn: int = 3 if f == hot_f else 2
			for k6 in kn:
				var rr: float = r0 + k6
				if rr > L * 0.1 + 2.0:
					break
				var k7 := Vector2i(roundi(tp.x + cos(a6) * rr), roundi(tp.y + sin(a6) * rr))
				if not cells.has(k7):
					cells[k7] = [LT[6] if k6 == 0 and f == hot_f else LT[4], false]
	var out: Array = []
	for kk in cells:
		out.append([float(kk.x), float(kk.y), cells[kk][0], cells[kk][1]])
	return out


## 普攻星光画法（fx/ir_atk_star，11-07 用户「更喜欢旧版带星光的，现在太像激光了」）：不画贯穿全长的实心光锥，
## 三种元素：①刺尖十字星芒顺着刺击方向两拍推到判定末端（身后只拖一截断开的短光，不连成长线）；
## ②刺尖经过的地方留下几颗小星点，闪一下、往上飘一格、熄掉；③被刺中的那只身上炸开星芒（_star_burst）。
## 第 0 拍出手星芒沿用 _lance；精一星点更多、刺尖星芒多四个斜角；精二出手星芒八芒（同 _lance）。
func _lance_star(L: float, d: Vector2, f: int, tier: int, sd: int) -> Array:
	if f < 0 or f > 6:
		return []
	var cells := {}
	var s0 := 4.0
	var n2 := Vector2(-d.y, d.x)
	if f == 0:   # 出手星芒（同 _lance 第 0 拍）
		for q in _lance(L, d, 0, tier, false):
			cells[Vector2i(roundi(float(q[0])), roundi(float(q[1])))] = [q[2], q[3]]
	var heads := [0.0, s0 + (L - s0) * 0.55, L, L, L, L, L]
	var sh: float = heads[f]
	if f >= 1 and f <= 2:   # 刺尖身后一截断开的短光：长 = 判定 0.28，4 格亮 2 格空，越往后越暗越细
		var tl: float = maxf(8.0, (L - s0) * 0.28)
		var i := 0
		var s: float = sh - 2.0
		while s > maxf(s0, sh - tl):
			var u: float = (sh - s) / tl
			if (i / 4) % 3 != 2 or i < 4:
				var c: Color = LT[6] if u < 0.25 else (LT[5] if u < 0.6 else LT[4])
				cells[Vector2i(roundi(d.x * s), roundi(d.y * s - LANCE_H))] = [c, u < 0.25 and i % 2 == 0]
				if u < 0.3:
					for sg in [-1.0, 1.0]:
						var k := Vector2i(roundi(d.x * s + n2.x * sg), roundi(d.y * s - LANCE_H + n2.y * sg))
						if not cells.has(k):
							cells[k] = [LT[4], false]
			i += 1
			s -= 1.0
	# 刺尖十字星芒：第 1 拍臂长 3、第 2 拍 4（精一多斜角）、第 3 拍 2、第 4 拍只剩一点
	var arm: int = [0, 3, 4, 2, 1, 0, 0][f]
	if arm > 0:
		var hx: float = d.x * sh
		var hy: float = d.y * sh - LANCE_H
		var st: Array = []
		_star(st, hx, hy, arm, LT[6] if f <= 3 else LT[5], LT[5] if f <= 2 else LT[4], LT[4] if f <= 2 else LT[3])
		if tier >= 1 and f >= 1 and f <= 2:
			for sg in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				st.append([hx + sg.x, hy + sg.y, LT[5], false])
				if f == 2:
					st.append([hx + sg.x * 2.0, hy + sg.y * 2.0, LT[4], false])
		for q in st:
			cells[Vector2i(roundi(float(q[0])), roundi(float(q[1])))] = [q[2], q[2] == LT[6]]
	# 路上散落的小星点：刺尖经过后出现，三拍：小十字 → 亮点上飘一格 → 暗点上飘两格
	var nd: int = [4, 6, 7][clampi(tier, 0, 2)]
	for k2 in nd:
		var u2: float = 0.12 + 0.8 * (float(k2) + _hf(k2, sd, 7)) / float(nd)
		var sk: float = s0 + (L - s0) * u2
		var born: int = 1 if sk <= heads[1] else 2
		var age: int = f - born - (_hsh(k2, sd, 11) % 2)
		if age < 0 or age > 2:
			continue
		var off: float = (_hf(k2, sd, 13) - 0.5) * 7.0
		var x: float = roundf(d.x * sk + n2.x * off)
		var y: float = roundf(d.y * sk - LANCE_H + n2.y * off) - age
		var big: bool = _hsh(k2, sd, 17) % 3 == 0
		if age == 0:
			cells[Vector2i(int(x), int(y))] = [LT[6], true]
			if big:
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var kq := Vector2i(int(x) + dd.x, int(y) + dd.y)
					if not cells.has(kq):
						cells[kq] = [LT[4], false]
		elif age == 1:
			cells[Vector2i(int(x), int(y))] = [LT[5] if big else LT[4], false]
		else:
			if (k2 + f) % 2 == 0:
				cells[Vector2i(int(x), int(y))] = [LT[3], false]
	var out: Array = []
	for kk in cells:
		out.append([float(kk.x), float(kk.y), cells[kk][0], cells[kk][1]])
	return out


## 星光画法的命中星爆（4 拍，同旧版 fx_star_hit_rose 的节奏：大四芒星 → 收小 + 斜向四颗星屑往外 → 星屑再外飘变暗 → 熄）
func _star_burst(f: int, eid: int) -> Array:
	var out: Array = []
	if f < 0 or f > 3:
		return out
	if f <= 1:
		_star(out, 0.0, 0.0, 4 if f == 0 else 2, LT[6], LT[5], LT[4] if f == 0 else LT[3])
	if f >= 1:
		var rr: float = [0.0, 3.0, 5.0, 6.0][f]
		var tw: int = eid % 4
		for q in 4:
			if f == 3 and (q + tw) % 2 == 0:
				continue
			var sg := Vector2(1 if q % 2 == 0 else -1, 1 if q < 2 else -1)
			var c: Color = LT[5] if f == 1 else (LT[4] if f == 2 else LT[3])
			out.append([sg.x * rr, sg.y * rr - (f - 1), c, f == 1])
	return out


## 同 lance_gd()：投影阴影（亮态各拍）；起风另有潮痕。普攻不画水
func _lance_gd(L: float, d: Vector2, f: int, _tier: int, gust: bool) -> Array:
	var out: Array = []
	if f < 0:
		return out
	if gust:
		L *= 1.1
	var n: int = maxi(4, int(L))
	var hot_f: int = 3 if gust else 2
	if f >= 1 and f <= hot_f:
		for i in range(int(n * 0.15), int(n * 0.9)):
			out.append([d.x * i, d.y * i, SHADOW, 0.5])
	if gust and f <= 5:
		var gv := Vector2(-d.y, d.x * SQ)
		gv = gv.normalized() if gv != Vector2.ZERO else Vector2.UP
		var cols: Array = [TIDE[5], TIDE[5], TIDE[4], TIDE[3], TIDE[3], TIDE[2]]
		for side in [-1, 1]:
			for i in range(int(n * 0.28), n):
				var u: float = float(i) / float(n)
				if u > 0.3 + 0.7 * minf(1.0, float(f + 1) / 2.0):
					continue
				if _hsh(i / 3, side, 41 + f / 2) % 4 == 0:
					continue
				if f >= 4 and (i + f) % 2 == 1:
					continue
				var off: float = 3.5 + 2.0 * u + 0.6 * f + (1.0 if (i / 4) % 2 == 1 else 0.0)
				out.append([d.x * i + gv.x * off * side, d.y * i + gv.y * off * side, cols[f], 1.0])
	return out


## 同 charge()：起风蓄光，身前 8 粒光点往里收拢（3 拍）
func _charge(d: Vector2, f: int) -> Array:
	var out: Array = []
	if f < 0 or f > 2:
		return out
	var h0 := Vector2(d.x * 10.0, d.y * 10.0 - LANCE_H - 1.0)
	var rr: float = [16.0, 9.0, 3.0][f]
	for q in 8:
		var a: float = q / 8.0 * TAU + f * 0.5
		var p := h0 + Vector2(cos(a), sin(a)) * rr
		out.append([p.x, p.y, LT[4] if f == 0 else LT[5], f == 2])
		out.append([p.x + 1.0, p.y, LT[3] if f == 0 else LT[4], false])
		if f < 2:
			var p2 := h0 + Vector2(cos(a), sin(a)) * (rr + 2.0)
			out.append([p2.x, p2.y, LT[3], false])
	for dd in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if f == 0 and dd != Vector2.ZERO:
			continue
		out.append([h0.x + dd.x, h0.y + dd.y, LT[6] if f >= 1 else LT[5], true])
	return out


## 同 pierce()：被贯穿的那只身上闪一个小十字（2 拍）
func _pierce(_d: Vector2, f: int, _tier: int) -> Array:
	var out: Array = []
	if f < 0 or f > 1:
		return out
	_star(out, 0.0, 0.0, 3 if f == 0 else 2, LT[6], LT[5] if f == 0 else LT[4], LT[4] if f == 0 else LT[3])
	return out


## 同 tracer()：p1 = 目标相对枪口（美术像素）
func _tracer(p1: Vector2, f: int) -> Array:
	var out: Array = []
	if f < 0 or f > 1:
		return out
	var n: int = maxi(2, int(maxf(absf(p1.x), absf(p1.y))))
	for i in n + 1:
		var u: float = float(i) / float(n)
		if f == 1 and u < 0.65:
			continue
		if u < 0.25 and i % 2 == 1:
			continue
		var c: Color = LT[6] if u > 0.8 else (LT[5] if u > 0.4 else LT[3])
		if f == 1:
			c = LT[4] if u > 0.85 else LT[2]
		out.append([p1.x * u, p1.y * u, c, f == 0 and u > 0.8])
	return out


## 同 qi_needle()
func _qi_needle(d: Vector2, tier: int, bt: int) -> Array:
	var out: Array = []
	var n2 := Vector2(-d.y, d.x)
	var L: int = 6 + 3 * tier
	for s in L:
		var c: Color = LT[6] if s == 0 else (LT[5] if s < 3 else (LT[4] if s < L - 2 else LT[3]))
		out.append([-d.x * s, -d.y * s, c, s <= 1])
		if s >= 1 and s <= 2 + tier:
			out.append([-d.x * s + n2.x, -d.y * s + n2.y, LT[3], false])
	var tl: int = 5 + 4 * tier
	for s in range(L, L + tl):
		if (s + bt) % 3 == 0:
			continue
		var w: int = 1 if (s / 2 + bt) % 2 == 1 else -1
		var wk: int = 0 if s < L + 2 else 1
		out.append([-d.x * s + n2.x * w * wk, -d.y * s + n2.y * w * wk, TIDE[5] if s < L + 3 else (TIDE[4] if s < L + 6 else TIDE[3]), false])
	if tier >= 2:
		_star(out, d.x, d.y, 1 + (bt % 2), LT[6], LT[5], LT[3])
	return out


## 同 lamp_ring()：[x, y, 颜色, 不透明度]
func _lamp_ring(rr: float, bt: int, age: float, life: float) -> Array:
	var out: Array = []
	var al: float = minf(1.0, age / 0.15) * minf(1.0, (life - age) / 0.3)
	if al <= 0.0:
		return out
	var n: int = int(rr * 6.6)
	var rot: float = float((bt / 2) % 32) / 32.0 * TAU / 10.0
	for q in n:
		var t: float = float(q) / float(n) * TAU
		var seg: float = fposmod(t - rot, TAU / 10.0) / (TAU / 10.0)
		if seg < 0.72:
			out.append([roundf(rr * cos(t)), roundf(rr * sin(t) * SQ), LT[5] if seg < 0.5 else LT[4], al])
		if q % 2 == 0:
			out.append([roundf((rr - 2.0) * cos(t)), roundf((rr - 2.0) * sin(t) * SQ), LT[2], al * 0.8])
	return out


## 同 lamp_motes()
func _lamp_motes(rr: float, bt: int, sd: float) -> Array:
	var out: Array = []
	for k in 12:
		var a: float = fposmod(k * 2.39996 + sd, TAU)
		var r2: float = rr * (0.2 + 0.75 * _hf(k, int(sd * 10.0), 5))
		var ph: int = (bt + k * 3) % 9
		var x: float = roundf(r2 * cos(a))
		var y: float = roundf(r2 * sin(a) * SQ) - 2.0 - ph * 2.0
		out.append([x, y, LT[6] if ph < 2 else (LT[5] if ph < 5 else LT[3]), ph < 2])
		if ph < 4:
			out.append([x, y + 1.0, LT[3], false])
	return out


## 同 lantern()
func _lantern(bt: int) -> Array:
	var cells := {}
	for y in range(1, 6):
		cells[Vector2i(-2, y)] = LAMP[2]
		cells[Vector2i(2, y)] = LAMP[2]
	for x in range(-2, 3):
		cells[Vector2i(x, 0)] = LAMP[3]
		cells[Vector2i(x, 6)] = LAMP[2]
	cells[Vector2i(0, -1)] = LAMP[3]
	var hot: bool = (bt / 2) % 2 == 0
	for y in range(2, 5):
		for x in range(-1, 2):
			cells[Vector2i(x, y)] = LAMP[6] if (x == 0 and y == 3) or (hot and absi(x) + absi(y - 3) <= 1) else LAMP[5]
	var out: Array = []
	for k in cells:
		out.append([float(k.x), float(k.y), cells[k], cells[k] == LAMP[6]])
	return out
