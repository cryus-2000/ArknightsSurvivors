extends RefCounted
const Bubble = preload("res://scripts/render/paranoia_bubble.gd")
const Materials = preload("res://scripts/render/final_boss_materials.gd")
const IzumikDraw = preload("res://scripts/render/izumik_attack_draw.gd")
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
	for w in g.warns:
		if w.act == "izu_wave" and not w.done and not impacts and g.optical_on:
			IzumikDraw.field_warning(g,w)   # 伊祖米克全场预警（docs/170）
			continue
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
			elif f.kind == "izu_shock" and f.life > 0: IzumikDraw.shock(g,f)   # 伊祖米克全场海浪（docs/170）
			elif f.kind == "final_impact" and f.life > 0:
				_shape(g,f,clampf(float(f.life)/float(f.max)*1.5,0,1),false)
		for e in g.bosses:
			if e.type == "izumik": IzumikDraw.learn_marks(g,e)   # 伊祖米克习得弹停顿标记（docs/170）
	g.world.tb_flush()

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
			if w.get("skin","") == "tide":   # 伊祖米克迁徙潮：波峰勾边，不画矩形框（docs/170）
				IzumikDraw.tide_warning(g,w,alpha,progress)
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
		if w.get("skin","") == "current":   # 伊祖米克海流牵引：向心流线（docs/170）
			IzumikDraw.current_warning(g,w)
		if w.get("skin","") == "tentacle" and w.shape == "cone":   # 伊祖米克护群触腕：出土点鼓包（docs/170）
			IzumikDraw.tentacle_warning(g,w,clampf(float(w.get("t",0.0))/maxf(0.01,float(w.dur)),0,1))
	elif w.get("skin","") == "current":
		IzumikDraw.current_burst(g,w)
	elif w.get("skin","") == "tide":
		IzumikDraw.tide_wall(g,w,alpha)
	elif w.get("skin","") == "tentacle" and w.shape == "cone" and w.has("max"):
		IzumikDraw.tentacles(g,w)
	elif w.get("skin", "") == "bubble":
		Bubble.shadow(g.world,w,alpha)
	else:
		Materials.draw(g,w,alpha)
