extends RefCounted
const Bubble = preload("res://scripts/render/paranoia_bubble.gd")
const Materials = preload("res://scripts/render/final_boss_materials.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")
const Grains = preload("res://scripts/render/final_attack_grains.gd")
const Bal = preload("res://scripts/core/balance.gd")
## Candidate presentation: exact tells underneath coarse pixel material bodies. No simulation writes.
static var _circle_points := PackedVector2Array()
static var _circle_gy := -INF
const DARK := Color(0.025, 0.045, 0.07)
const DANGER := Color(0.82, 0.24, 0.43)

static func _circle_geometry(gy: float) -> PackedVector2Array:
	if _circle_gy != gy:
		_circle_points.resize(41)
		for i in 41:
			var a: float = TAU * i / 40.0
			_circle_points[i] = Vector2(cos(a), sin(a) * gy)
		_circle_gy = gy
	return _circle_points

static func draw(g, impacts := false) -> void:
	var caps: Array = []
	if not impacts:
		for w in g.warns:
			if not TeleDraw.knight_line(w): continue
			_knight_line_tell(g, w)
			if not w.done and w.owner.get("stakes", []) is Array and not w.owner.get("stakes", []).is_empty(): caps.append(w)
		for b in g.bosses:
			if b.type != "knight_boss": continue
			_stage_set(b)
			_stage_ground(g, b)
			if b.get("kb_self", false): Grains.dash_frost(g, b)
			_dash_frost(g, b)
	for w in g.warns:
		if w.act != "final_attack" or w.done: continue
		if w.get("skin", "") == "bubble":
			if impacts: Bubble.draw(g,w,0.95,true)
			else: Bubble.shadow(g.world,w,0.7)
		elif not impacts:
			_shape(g,w,0.65+0.25*clampf(w.t/w.dur,0,1),true)
	for h in g.bai.finals.hazards:
		if not g.bosses.has(h.owner) or g.bai.finals.cancelled(h): continue
		if h.get("skin", "") == "bubble":
			if impacts: Bubble.draw(g,h,1.0)
			else: Bubble.shadow(g.world,h,0.8)
		elif not impacts: _shape(g,h,0.95,false)
	if impacts:
		for f in g.fx:
			if f.kind == "bubble_pop" and f.life > 0: Bubble.pop(g,f)
			elif f.kind == "knight_crash" and f.life > 0:
				_crash(g, f)
			elif f.kind == "final_impact" and f.life > 0:
				_shape(g,f,clampf(float(f.life)/float(f.max)*1.5,0,1),false)
	g.world.tb_flush()
	for w in caps: g.world._stake_cap(w)   # 撞柱提示保持原样（world.draw_warn_outlines 不再画骑士线形预警）

## ---- 骑士分阶段风格（docs/169，10-28）：冰面 / 碎冰 / 冰颗粒按阶段乘色，场地按阶段加霜带、飘雪、重生裂冰。只画画面，不抽随机
const STAGE_ICE := [Color(1, 1, 1), Color(0.9, 1.0, 1.0), Color(0.78, 0.88, 1.12), Color(1.0, 1.0, 1.06)]
static var _tint := Color(1, 1, 1)

static func _t(c: Color) -> Color:
	return Color(c.r * _tint.r, c.g * _tint.g, c.b * _tint.b, c.a)

static func _stage(b) -> int:
	return 3 if int(b.get("phase", 1)) == 2 else clampi(int(b.get("gates_passed", 0)), 0, 2)

static func _stage_set(b) -> void:
	_tint = STAGE_ICE[_stage(b)]
	Grains.ice_tint = Color(_tint.r, _tint.g, _tint.b, Grains.ICE_TINT.a)

static func _stage_ground(g, b) -> void:
	var st := _stage(b)
	if st == 0 or Grains.ice_off or not g.zone_frozen:
		return
	var r = g.world
	var gy: float = g.combat.GROUND_Y
	var c: Vector2 = g.zone_c
	var R: float = g.zone_r
	# 霜带：场地边缘往里爬（二幕 24 → 60，三幕 / 重生 100）；只画视野附近的段
	var grow: float = clampf(float(b.get("act_t", 0.0)) / 30.0, 0.0, 1.0)
	var band: float = (24.0 + 36.0 * grow) if st == 1 else 100.0
	var tone: Color = [Color(), Color(0.62, 0.86, 0.9, 0.12), Color(0.42, 0.56, 0.8, 0.12), Color(0.7, 0.84, 0.95, 0.12)][st]
	var rim: Color = [Color(), Color(0.82, 0.96, 1.0, 0.32), Color(0.8, 0.88, 1.0, 0.3), Color(0.9, 0.97, 1.0, 0.34)][st]
	var view: Vector2 = g.ppos
	var seg := 96
	for i in seg:
		var a0: float = TAU * i / seg
		var a1: float = TAU * (i + 1) / seg
		var o0 := c + Vector2(cos(a0), sin(a0) * gy) * R
		if o0.distance_to(view) > 900.0:
			continue
		var o1 := c + Vector2(cos(a1), sin(a1) * gy) * R
		var w0: float = band * (0.65 + 0.35 * _noise(i, 41 + st))
		var w1: float = band * (0.65 + 0.35 * _noise((i + 1) % seg, 41 + st))
		var i0 := c + Vector2(cos(a0), sin(a0) * gy) * (R - w0)
		var i1 := c + Vector2(cos(a1), sin(a1) * gy) * (R - w1)
		r.tb_quad(_snap(o0), _snap(o1), _snap(i1), _snap(i0), tone)
		_strip(r, i0, i1, 2.0, rim)
		if _noise(i, 57 + st) > 0.6:   # 霜刺：从霜带内缘往里扎一小截
			var m: Vector2 = (i0 + i1) * 0.5
			_strip(r, m, m + (c - m).normalized() * (8.0 + 14.0 * _noise(i, 61)), 2.0, rim)
	# 三幕飘雪：视野内 90 粒，按时间斜落；重生不下雪（换裂冰）
	if st == 2:
		var t: float = g.t
		for k in 90:
			var px: float = fposmod(_noise(k, 71) * 1400.0 - t * (26.0 + 14.0 * _noise(k, 73)), 1400.0) - 700.0
			var py: float = fposmod(_noise(k, 79) * 800.0 + t * (48.0 + 30.0 * _noise(k, 83)), 800.0) - 400.0
			_dot(r, view + Vector2(px, py), Color(0.92, 0.97, 1.0, 0.3 + 0.3 * _noise(k, 89)), 2.0)
	# 重生裂冰：重生点一片淡冰圆盘 + 放射状白裂纹（docs/171 v2：配色回冰白）
	if st == 3 and b.has("kn_reborn_pos"):
		var p: Vector2 = b.kn_reborn_pos
		if p.distance_to(view) < 1100.0:
			for i in 28:
				var a0: float = TAU * i / 28.0
				var a1: float = TAU * (i + 1) / 28.0
				var rr: float = 220.0 * (0.82 + 0.18 * _noise(i, 97))
				r.tb_quad(p, p, p + Vector2(cos(a0), sin(a0) * gy) * rr, p + Vector2(cos(a1), sin(a1) * gy) * rr, Color(0.62, 0.78, 0.92, 0.14))
			for j in 14:
				var ang: float = TAU * (j + _noise(j, 101) * 0.7) / 14.0
				var reach: float = 120.0 + _noise(j, 103) * 110.0
				var last: Vector2 = p
				for s in 6:
					var u: float = float(s + 1) / 6.0
					var jit: float = (_noise(j * 6 + s, 107) - 0.5) * 0.45
					var at: Vector2 = p + Vector2(cos(ang + jit), sin(ang + jit) * gy) * reach * u
					_strip(r, last, at, 2.0, Color(0.85, 0.94, 1.0, 0.7 - 0.4 * u))
					if s == 3 and _noise(j, 109) > 0.5:   # 分叉
						var br: float = ang + 0.5 * (1.0 if _noise(j, 113) > 0.5 else -1.0)
						_strip(r, at, at + Vector2(cos(br), sin(br) * gy) * 34.0, 2.0, Color(0.7, 0.84, 0.98, 0.4))
					last = at

static func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(2.0, 2.0))

static func _ink(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Stable visual variation: no gameplay RNG and no new jitter pattern on every frame.
static func _noise(i: int, salt := 0) -> float:
	var k: int = (i * 73471 + salt * 19391 + 137) & 65535
	k = ((k ^ (k >> 7)) * 127) & 65535
	return float(k) / 65535.0

static func _dot(r, p: Vector2, c: Color, size := 2.0) -> void:
	var a := _snap(p)
	var s := maxf(2.0, snappedf(size, 2.0))
	r.tb_quad(a, a + Vector2(s, 0), a + Vector2(s, s), a + Vector2(0, s), c)

static func _strip(r, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var n := (b - a).normalized().orthogonal() * width * 0.5
	r.tb_quad(_snap(a - n), _snap(b - n), _snap(b + n), _snap(a + n), c)

static func _facet(r, pts: Array, c: Color) -> void:
	var snapped := PackedVector2Array()
	for p in pts: snapped.append(_snap(p))
	r.tb_poly(snapped, c)

static func _ring(r, p: Vector2, radius: float, gy: float, width: float, c: Color, a0 := 0.0, a1 := TAU, broken := false) -> void:
	var count: int = clampi(ceili(radius * (a1 - a0) / 10.0), 12, 150)
	for i in count:
		if broken and _noise(i, 4) < 0.22: continue
		var a: float = lerpf(a0, a1, float(i) / count)
		var b: float = lerpf(a0, a1, float(i + 1) / count)
		_strip(r, p + Vector2(cos(a), sin(a) * gy) * radius, p + Vector2(cos(b), sin(b) * gy) * radius, width, c)

static func _circle_fill(r, w: Dictionary, gy: float, c: Color) -> void:
	var inner: float = float(w.get("inner_r", 0.0))
	var points := _circle_geometry(gy)
	for i in 40:
		var va := points[i]
		var vb := points[i + 1]
		r.tb_quad(w.pos + va * inner, w.pos + va * w.r, w.pos + vb * w.r, w.pos + vb * inner, c)

static func _warning(g, w: Dictionary, alpha: float) -> void:
	var r = g.world
	var p: Vector2 = w.pos
	var delay: float = float(w.get("tell_after",0.0))
	if float(w.get("t",0.0)) < delay: return
	var progress: float = clampf((float(w.get("t", 0.0))-delay) / maxf(0.01, float(w.get("dur", 1.0))-delay), 0.0, 1.0)
	var edge := _ink(DANGER, alpha)
	var fill := Color(0.24, 0.035, 0.085, 0.09 + progress * 0.06)
	var gy: float = g.combat.GROUND_Y
	if w.get("skin","") == "ice_wave":
		for segment in Materials._wave_segments(w,gy):
			var a: float = segment.x
			var b: float = segment.y
			var i: int = int((a+b)*.5*100/TAU)
			var va := Vector2(cos(a),sin(a)*gy)
			var vb := Vector2(cos(b),sin(b)*gy)
			var inner: float = float(w.get("inner_r",0))
			r.tb_quad(p+va*inner,p+va*w.r,p+vb*w.r,p+vb*inner,Color(.18,.31,.4,.045+progress*.04))
			_strip(r,p+va*w.r,p+vb*w.r,2,edge)
			if i%6==1: _strip(r,p+va*inner,p+va*(inner+(w.r-inner)*progress),1,_ink(Color(.42,.63,.75),alpha*.5))
		return
	match str(w.shape):
		"arc":
			var arc_center: Vector2 = p - Vector2.from_angle(w.ang)*float(w.get("arc_back",0.0))
			_ring(r,arc_center,w.r,1.0,2.0,edge,w.ang-w.half,w.ang+w.half)
			var forming: Dictionary = w.duplicate()
			forming.formation = smoothstep(0.0,0.82,progress)
			Materials._blade(r,forming,0.0,0.25+0.6*progress)
			var forward := Vector2.from_angle(w.ang)
			for side in [-1.0,1.0]:
				var tip: Vector2 = arc_center+Vector2.from_angle(w.ang+side*w.half)*w.r
				_strip(r,tip,tip+forward*180,2.0,_ink(DANGER,0.35))
		"circle":
			_circle_fill(r, w, gy, fill)
			_ring(r, p, w.r, gy, 5.0, _ink(DARK, 0.8))
			_ring(r, p, w.r, gy, 2.0, edge)
			var inner: float = float(w.get("inner_r", 0.0))
			if inner > 0.0:
				_ring(r, p, inner, gy, 5.0, _ink(DARK, 0.9))
				_ring(r, p, inner, gy, 2.0, edge)
			# A short filling arc encodes time, not a solid white spell body.
			_ring(r, p, w.r, gy, 3.0, _ink(Color(1.0, 0.48, 0.57), alpha), -PI * 0.5, -PI * 0.5 + maxf(0.02, progress) * TAU)
		"line":
			if w.get("skin", "") in ["ice_thrust", "spear"]:
				var tr: float = float(w.get("track", 0.0))
				var since_lock: float = float(w.get("t", 0.0)) - tr
				var lock_flash: float = 1.0 - since_lock / 0.15 if tr > 0.0 and since_lock >= 0.0 and since_lock < 0.15 else 0.0
				_frost_line(r, p, w.ang, w.len, w.wid, progress, tr <= 0.0 or since_lock >= 0.0, alpha, lock_flash * 0.6)
				return
			var d := Vector2.from_angle(w.ang)
			var n := d.orthogonal()
			var end: Vector2 = p + d * w.len
			r.tb_quad(p - n * w.wid, end - n * w.wid, end + n * w.wid, p + n * w.wid, fill)
			for side in [-1.0, 1.0]:
				_strip(r, p + n * w.wid * side, end + n * w.wid * side, 5.0, _ink(DARK, 0.85))
				_strip(r, p + n * w.wid * side, end + n * w.wid * side, 2.0, edge)
			_strip(r, p - n * w.wid, p + n * w.wid, 2.0, edge)
			_strip(r, end - n * w.wid, end + n * w.wid, 2.0, edge)
			if w.get("skin", "") == "ice_field":
				for j in 20:
					var at: Vector2 = p+d*w.len*(j+.5)/20.0+n*(_noise(j,3)*2-1)*w.wid*.7
					var reach: float = 5+progress*15
					_strip(r,at-d*reach,at+n*reach*.6,2,_ink(Color(.45,.68,.79),alpha*progress*.75))
					_strip(r,at+n*reach*.6,at+d*reach*.7,2,_ink(Color(.45,.68,.79),alpha*progress*.75))
				return
			var lead: Vector2 = p + d * w.len * progress
			_strip(r, lead - d * 12.0 - n * minf(w.wid * 0.35, 10.0), lead, 2.0, edge)
			_strip(r, lead - d * 12.0 + n * minf(w.wid * 0.35, 10.0), lead, 2.0, edge)
			if w.get("skin", "") in ["tide","ice_wall"]:
				var travel: Vector2 = w.velocity * w.life
				r.tb_quad(p, end, end + travel, p + travel, Color(0.25, 0.06, 0.1, 0.045))
				_strip(r, p, p + travel, 2.0, _ink(DANGER, 0.55))
				_strip(r, end, end + travel, 2.0, _ink(DANGER, 0.55))
				var v: Vector2 = travel.normalized()
				for j in 3:
					var at: Vector2 = p.lerp(end, 0.5) + travel * (j + 0.5) / 3.0
					_strip(r, at - v * 12 + d * 8, at, 2.0, edge)
					_strip(r, at - v * 12 - d * 8, at, 2.0, edge)
		"cone":
			if w.get("skin","") == "ice_field":
				var inner: float = float(w.get("inner_r",0))
				for i in 16:
					var va := Vector2.from_angle(w.ang-w.half+2*w.half*i/16)
					var vb := Vector2.from_angle(w.ang-w.half+2*w.half*(i+1)/16)
					var ra: float = Materials.field_radius(w,va.angle())
					var rb: float = Materials.field_radius(w,vb.angle())
					if minf(ra,rb)<=inner: continue
					r.tb_quad(p+va*inner,p+va*ra,p+vb*rb,p+vb*inner,fill)
					_strip(r,p+va*ra,p+vb*rb,2,edge)
					_strip(r,p+va*inner,p+vb*inner,2,edge)
					if i%4==1: _strip(r,p+va*(inner+15),p+va*(inner+(ra-inner)*progress),1,_ink(Color(.45,.68,.79),alpha*.6))
				for side in [-1.0,1.0]:
					var direction := Vector2.from_angle(w.ang+side*w.half)
					if Materials.field_radius(w,direction.angle())>inner:
						_strip(r,p+direction*inner,p+direction*Materials.field_radius(w,direction.angle()),2,edge)
				return
			var pts := PackedVector2Array([p])
			for i in 25: pts.append(p + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / 24.0) * w.r)
			r.tb_poly(pts, fill)
			_ring(r, p, w.r, 1.0, 2.0, edge, w.ang - w.half, w.ang + w.half)
			for side in [-1.0, 1.0]: _strip(r, p, p + Vector2.from_angle(w.ang + w.half * side) * w.r, 2.0, edge)

static func _shape(g, w: Dictionary, alpha: float, warning: bool) -> void:
	if warning:
		_warning(g,w,alpha)
	elif w.get("skin", "") == "bubble":
		Bubble.shadow(g.world,w,alpha)
	else:
		Materials.draw(g,w,alpha)

## ---- Knight frost tells (10-27 polish): no hatch, chevrons or white slab. Low dark-red fill plus an ice-crack border;
## a ground crack spreads from the Knight along the route. The outer boundary is exactly the hit rectangle (jitter only moves inward).
const CRACK_ICE := Color(0.6, 0.84, 0.95)
const CRACK_EDGE := Color(0.6, 0.14, 0.27)
const CRACK_SHADE := Color(0.03, 0.04, 0.07)

## Generic Knight line warnings from g.warns (charge, re-charge, cold pursuit, ice line, spear throw).
static func _knight_line_tell(g, w: Dictionary) -> void:
	var t: float = float(w.t)
	var dur: float = maxf(0.01, float(w.dur))
	if w.done:
		# Release: the crack flashes ice-white and fades within 0.25 s instead of a translucent white slab.
		var f: float = clampf(1.0 - (t - dur) / 0.25, 0.0, 1.0)
		if f > 0.0: _frost_line(g.world, w.pos, w.ang, w.len, w.wid, 1.0, true, 0.9 * f, f, true)
		return
	var tr: float = float(w.get("track", 0.0))
	var since_lock: float = t - tr
	var lock_flash: float = 1.0 - since_lock / 0.15 if tr > 0.0 and since_lock >= 0.0 and since_lock < 0.15 else 0.0
	var k: float = clampf(t / dur, 0.0, 1.0)
	_frost_line(g.world, w.pos, w.ang, w.len, w.wid, k, tr <= 0.0 or since_lock >= 0.0, 0.7 + 0.25 * k, lock_flash * 0.6)

static func _frost_line(r, p: Vector2, ang: float, length: float, half_w: float, k: float, locked: bool, alpha: float, flash := 0.0, released := false) -> void:
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	var end: Vector2 = p + d * length
	var salt: int = int(length) & 255
	var white := Color(0.88, 0.98, 1.0)
	# 1. Low dark-red fill: the complete hit area, quiet enough to read terrain through it.
	if not released:
		r.tb_quad(p - n * half_w, end - n * half_w, end + n * half_w, p + n * half_w, Color(0.24, 0.035, 0.085, 0.08 + 0.07 * k))
	# 2. Frozen border: a ragged dark-red crack (random-length runs that step inward 0-4 px, never outward), feathered by
	# short pale frost needles. While the tell still tracks, runs are broken; once the direction locks they close.
	var edge_a: float = alpha * (0.85 if locked else 0.6)
	var edge_c: Color = CRACK_EDGE.lerp(white, flash)
	var frost_c: Color = CRACK_ICE.lerp(white, flash)
	var steps: int = maxi(2, ceili(length / 6.0))
	for side in [-1.0, 1.0]:
		var salt_side: int = salt + (3 if side > 0.0 else 7)
		var prev: Vector2 = p + n * side * half_w
		for i in steps:
			var u: float = float(i + 1) / steps
			# Inset holds for a few cells, then jumps: reads as a fractured ice rim rather than a ruled line.
			var inset: float = 0.0 if i + 1 == steps else floorf(_noise(int(i / 3.0), salt_side) * 3.0) * 2.0
			var at: Vector2 = p + d * length * u + n * side * (half_w - inset)
			if locked or _noise(i, salt + 11) > 0.45:
				_strip(r, prev, at, 2.0, _ink(edge_c, edge_a))
			prev = at
			# Frost needles grow inward from the rim, creeping from the Knight toward the far end over the tell.
			if u <= k and _noise(i, salt_side + 13) < 0.42:
				var reach_in: float = 4.0 + _noise(i, salt_side + 19) * 8.0
				var lean: float = (_noise(i, salt_side + 23) - 0.5) * 6.0
				_strip(r, at - n * side * 2.0, at - n * side * reach_in + d * lean, 2.0, _ink(frost_c, alpha * 0.7))
				if _noise(i, salt_side + 29) < 0.3:
					_dot(r, at - n * side * (reach_in + 3.0), _ink(white, alpha * 0.6))
	# 3. Stop line: a jagged crack across the far end.
	var across: int = maxi(2, ceili(half_w * 2.0 / 6.0))
	var prev_end: Vector2 = end - n * half_w
	for i in across:
		var v: float = -half_w + half_w * 2.0 * float(i + 1) / across
		var at: Vector2 = end + n * v - d * (0.0 if i + 1 == across else _noise(i, salt + 29) * 4.0)
		_strip(r, prev_end, at, 2.0, _ink(edge_c, edge_a))
		prev_end = at
	# 4. Route crack spreading from the Knight: shows direction and timing without arrows. Kinks every ~32 px with
	# straight runs between (ice fracture), not a per-cell zigzag that would read as lightning.
	var reach: float = length * k
	if reach < 4.0: return
	var seg: int = maxi(1, ceili(reach / 8.0))
	var last: Vector2 = p
	var crack_c: Color = CRACK_ICE.lerp(white, maxf(flash, 0.25 if released else 0.0))
	for i in seg:
		var s: float = minf(reach, float(i + 1) * 8.0)
		var knot: float = s / 32.0
		var a0: float = (_noise(int(knot), salt + 31) - 0.5) * half_w * 0.5
		var a1: float = (_noise(int(knot) + 1, salt + 31) - 0.5) * half_w * 0.5
		var wob: float = lerpf(a0, a1, knot - floorf(knot))
		var at: Vector2 = p + d * s + n * wob
		_strip(r, last, at, 4.0, _ink(CRACK_SHADE, alpha * 0.4))
		_strip(r, last, at, 2.0, _ink(crack_c, alpha * 0.7))
		# Side fractures at some knots, leaning forward, never past the border.
		if i % 4 == 3 and _noise(i, salt + 43) < 0.7:
			var bs: float = 1.0 if _noise(i, salt + 37) < 0.5 else -1.0
			var blen: float = half_w * (0.4 + 0.45 * _noise(i, salt + 41))
			var tip: Vector2 = at + d * minf(blen * 0.7, length - 4.0 - s) + n * bs * maxf(0.0, minf(blen, half_w - absf(wob) - 4.0))
			_strip(r, at, tip, 2.0, _ink(crack_c, alpha * 0.45))
		last = at
	if not released and k < 1.0:
		_dot(r, last, _ink(white, alpha), 4.0)   # Advancing crack tip.

## Dash ice sheet (user 10-27: a wide frozen surface, not a line): the charge path freezes into a translucent ice band about
## the Knight's width with a ragged rim. Each cell freezes when the Knight arrives (white freezing front), holds, then fades.
## The pattern is fixed per charge (seeded by its path), so nothing flickers; sheen streaks and a few glints read as ice.
const DASH_SLIDE := 0.45
const SHEET_HOLD := 0.9
const SHEET_FADE := 0.45
static func _dash_frost(g, e: Dictionary) -> void:
	var la = e.get("last_act")
	if Grains.ice_off or not (la is Dictionary) or str(la.get("act", "")) != "dash": return   # --iceab 同局轮换一并关冰面
	var since: float = g.t - float(la.t)
	# Phase one from the second act leaves a real 3 s ice strip (knight_boss._ice_step, cold build-up): show the sheet that long.
	var hold: float = SHEET_HOLD
	if int(e.get("phase", 1)) == 1 and int(e.get("gates_passed", 0)) >= 1:
		hold = maxf(SHEET_HOLD, Bal.v("boss/knight_ice_life", 3.0) - SHEET_FADE)
	if since < 0.0 or since > DASH_SLIDE + hold + SHEET_FADE: return
	var r = g.world
	var d := Vector2.from_angle(float(la.ang))
	var n := d.orthogonal()
	var length: float = float(la.len)
	if str(e.get("brk_label", "")) == "眩晕":
		length = clampf((Vector2(e.pos) - Vector2(la.pos)).dot(d), 8.0, length)   # 撞柱停下：冰面只铺到柱前
	var half: float = clampf(float(la.get("wid", 34.0)) * 0.7, 16.0, 26.0)
	var origin: Vector2 = Vector2(la.pos) + Vector2(0, 10)
	var salt: int = (int(absf(origin.x)) * 7 + int(absf(origin.y)) * 13) & 1023
	var steps: int = maxi(2, ceili(length / 6.0))
	var front := -1
	for i in steps:
		var u0: float = float(i) / steps
		var u1: float = float(i + 1) / steps
		# Constant-deceleration slide: fraction u is reached at T·(1 − sqrt(1 − u)).
		var age: float = since - DASH_SLIDE * (1.0 - sqrt(maxf(0.0, 1.0 - u1)))
		if age < 0.0: continue
		front = i
		var fade: float = 1.0 if age < hold else clampf(1.0 - (age - hold) / SHEET_FADE, 0.0, 1.0)
		if fade <= 0.0: continue
		var a: Vector2 = origin + d * length * u0
		var b: Vector2 = origin + d * length * u1
		# Ragged rim: each side steps inward 0–6 px in runs of three cells; the taper keeps the ends from reading as a box.
		var taper: float = minf(1.0, minf(u1, 1.0 - u0) * 8.0)
		for side in [-1.0, 1.0]:
			var inset: float = floorf(_noise(int(i / 3.0), salt + (3 if side > 0.0 else 7)) * 4.0) * 2.0
			var w_side: float = (half - inset) * (0.45 + 0.55 * taper)
			# Two bands per side; each picks a tone that holds for ~18 px, so the sheet reads as mottled ice slabs, not a flat bar.
			for band in 2:
				var c0: float = w_side * band * 0.5
				var tone: float = _noise(int(i / 3.0) * 4 + band * 2 + (1 if side > 0.0 else 0), salt + 41)
				var sheet := _t(Color(0.85, 0.96, 1.0, 0.5))
				if age >= 0.08:
					if tone < 0.3: sheet = _t(Color(0.2, 0.34, 0.46, 0.24 * fade))
					elif tone < 0.75: sheet = _t(Color(0.38, 0.58, 0.7, 0.17 * fade))
					else: sheet = _t(Color(0.6, 0.8, 0.9, 0.2 * fade))
				_strip(r, a + n * side * (c0 + w_side * 0.25), b + n * side * (c0 + w_side * 0.25), w_side * 0.5, sheet)
			# Frozen rim: a lighter 2 px lip along the edge.
			_strip(r, a + n * side * w_side, b + n * side * w_side, 2.0, _t(Color(0.7, 0.86, 0.94, 0.38 * fade)))
		# Sheen: short diagonal highlights across the sheet, as on polished ice.
		if i % 7 == 3:
			var across: float = (_noise(i, salt + 17) - 0.5) * half
			var c: Vector2 = (a + b) * 0.5 + n * across
			_strip(r, c - (d + n) * 5.0, c + (d + n) * 5.0, 2.0, _t(Color(0.88, 0.96, 1.0, 0.35 * fade)))
		# Hairline cracks frozen into the sheet.
		if i % 5 == 1 and _noise(i, salt + 21) < 0.6:
			var c0: Vector2 = a + n * (_noise(i, salt + 23) - 0.5) * half * 1.2
			_strip(r, c0, c0 + (d * 0.6 + n * (_noise(i, salt + 29) - 0.5) * 1.6).normalized() * (6.0 + _noise(i, salt + 31) * 10.0), 2.0, _t(Color(0.22, 0.36, 0.5, 0.5 * fade)))
		if _noise(i, salt + 9) < 0.07 and age > 0.1 and age < 0.7 and int((age + _noise(i, salt + 11)) * 12.0) % 3 == 0:
			_dot(r, a + n * (_noise(i, salt + 13) - 0.5) * half, _t(Color(0.92, 0.98, 1.0, 0.9)))   # Ice glint.
	# Freezing front: a bright line across the band at the newest frozen cell while the Knight is still sliding.
	if front >= 0 and front < steps - 1:
		var fp: Vector2 = origin + d * length * float(front + 1) / steps
		_strip(r, fp - n * half * 0.9, fp + n * half * 0.9, 2.0, _t(Color(0.9, 0.98, 1.0, 0.8)))

## 撞柱冲锋的地面冰爆（骑士独有招，10-27）：圆盘霜面 + 8 道参差冰裂从柱根向外长（0.15 秒长满），白 → 青 → 暗蓝后淡出。纯画面
static func _crash(g, f: Dictionary) -> void:
	var r = g.world
	var age: float = float(f.max) - float(f.life)
	var k: float = clampf(age / 0.15, 0.0, 1.0)
	var fade: float = clampf(float(f.life) / 0.5, 0.0, 1.0)
	var gy: float = g.combat.GROUND_Y
	var p: Vector2 = f.pos
	var salt: int = (int(absf(p.x)) * 7 + int(absf(p.y)) * 3) & 1023
	var disc := _t(Color(0.4, 0.6, 0.72, 0.22 * fade)) if age > 0.06 else _t(Color(0.85, 0.96, 1.0, 0.5))
	for i in 20:
		var a0: float = TAU * i / 20.0
		var a1: float = TAU * (i + 1) / 20.0
		var rr: float = 46.0 * k * (0.8 + 0.25 * _noise(i, salt))
		r.tb_quad(p, p, p + Vector2(cos(a0), sin(a0) * gy) * rr, p + Vector2(cos(a1), sin(a1) * gy) * rr, disc)
	var crack := _t(Color(0.88, 0.97, 1.0, 0.9)) if age < 0.12 else (_t(Color(0.58, 0.82, 0.94, 0.75 * fade)) if age < 0.6 else _t(Color(0.25, 0.4, 0.56, 0.6 * fade)))
	for j in 8:
		var ang: float = TAU * (j + _noise(j, salt + 3) * 0.6) / 8.0
		var reach: float = (60.0 + _noise(j, salt + 5) * 50.0) * k
		var last: Vector2 = p
		for s in 5:
			var u: float = float(s + 1) / 5.0
			var jitter: float = (_noise(j * 5 + s, salt + 7) - 0.5) * 0.5
			var at: Vector2 = p + Vector2(cos(ang + jitter), sin(ang + jitter) * gy) * reach * u
			_strip(r, last, at, 2.0, crack)
			last = at
