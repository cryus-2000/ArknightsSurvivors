## 干员积木 · ob_vortex（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_fx.gd"

const VORTEX_DEF := {
	"n": 32,              # 流线条数（≤ 64）
	"r": 1.0,             # 外半径 = 区域半径 × r
	"max_r": 520.0,       # 外半径上限（世界像素）
	"r0": 0.12,           # 流线卷到的最内圈（外半径的比例）
	"len": 1.3,           # 每条流线的弧长（弧度）
	"curl": 0.22,         # 尾端比头端外扩多少（外半径比例）：螺旋感
	"spin": 0.55,         # 角速度（弧度 / 秒，外圈；内圈按 1 / (0.35 + 0.65 rf) 加快）
	"drift": 0.10,        # 向内卷的速度（每秒走完生命周期的几分之几）
	"w": 1.6,             # 线宽（世界像素，中段；两端收细）
	"a": 0.3,             # 流线最大透明度
	"col": [0.55, 0.92, 1.0],    # 主色（青）
	"acc": [0.95, 0.32, 0.42],   # 点缀色（暗红）
	"acc_n": 4,           # 点缀流线条数
	"acc_a": 0.55,        # 点缀流线透明度系数（相对 a）
	"seg": 8,             # 每条流线分几段
	"halo": 0.0,          # 软边：再画一遍宽 halo 倍、透明度 halo_a 倍的淡线（0 = 不画；约多一倍顶点）
	"halo_a": 0.25,
	"motes": 24,          # 光点个数（≤ 64）
	"mote_a": 0.55,       # 光点最大透明度
	"mote_sz": 2.0,       # 光点边长（世界像素）
	"mote_rise": 18.0,    # 光点上飘高度（世界像素，一个周期）
	"glow": 0.12,         # 中心柔光透明度（0 = 不画）
	"glow_r": 0.3,        # 中心柔光半径（外半径比例）
	"fill": 0.05,         # 整片水色底透明度（0 = 不画）
	"ring": 1.0,          # 区域椭圆边线透明度倍率（< 1 把程序硬边压淡；取所有生效漩涡的最小值）
	"sy": 0.55,           # 透视压扁（同区域椭圆）
}

const VORTEX_LIM := {"n": [0, 64], "r": [0.05, 3.0], "max_r": [16.0, 2000.0], "r0": [0.0, 0.95], "len": [0.1, 6.3], "curl": [-1.0, 1.0],
	"spin": [-8.0, 8.0], "drift": [0.0, 2.0], "w": [0.5, 8.0], "a": [0.0, 1.0], "halo": [0.0, 8.0], "halo_a": [0.0, 1.0], "acc_n": [0, 64], "acc_a": [0.0, 2.0], "seg": [2, 24],
	"motes": [0, 64], "mote_a": [0.0, 1.0], "mote_sz": [0.5, 8.0], "mote_rise": [-200.0, 200.0], "glow": [0.0, 1.0], "glow_r": [0.0, 1.0],
	"fill": [0.0, 1.0], "ring": [0.0, 1.0], "sy": [0.1, 1.0]}


static func _vp(v: Dictionary, k: String):
	return v.get(k, VORTEX_DEF[k])


static func _vcol(v: Dictionary, k: String) -> Color:
	var a = v.get(k, VORTEX_DEF[k])
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Color.WHITE


## 区域椭圆边线的透明度倍率：e 是贴身层记录（data_operator._fxb 的值）
static func vortex_ring_mul(o, e: Dictionary) -> float:
	var m := 1.0
	for f in e.b.fx:
		if f is Dictionary and f.has("vortex") and fx_on(o, f):
			m = minf(m, float(_vp(f.vortex, "ring")))
	return m


## 画 e（贴身层记录 {b, el, fade, fl}）上 layer 层的漩涡条目。alpha：整体倍率（进出淡入淡出按条目 fade 在这里算，fx_hold_alpha）；sink：带 add_tris 的合批画布或 CanvasItem
static func fx_vortex(sink, o, e: Dictionary, layer: String, alpha: float, c_zone: Vector2, r_zone: float) -> void:
	var g = o.g
	var fx_arr = e.b.fx
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var t: float = float(g.t)
	if not e.has("vx"):
		e["vx"] = {}
		e["va"] = {}
		e["vt"] = t
	var dt: float = clampf(t - float(e.vt), 0.0, 0.1)
	e.vt = t
	for i in fx_arr.size():
		var f = fx_arr[i]
		if not (f is Dictionary) or not f.has("vortex") or str(f.get("layer", "floor")) != layer:
			continue
		# 条目条件切换时 0.35 秒交叉淡入淡出（例：歌域漩涡在 S3 期间让位给 S3 漩涡）
		var want: float = 1.0 if fx_on(o, f) else 0.0
		var ca: float = float(e.va.get(i, want))
		ca = move_toward(ca, want, dt / 0.35)
		e.va[i] = ca
		var al: float = alpha * fx_hold_alpha(f, e) * ca * float(g.world.fx_dim)
		var tv = f.get("tint", [])
		var tint := Color.WHITE
		if tv is Array and tv.size() >= 3:
			tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		al *= tint.a
		if al <= 0.004:
			continue
		var v: Dictionary = f.vortex
		var c: Vector2 = c_zone
		match str(f.get("at", "zone")):
			"self":
				c = o.pos
			"leader":
				c = o.lead_pos()
		var ov = f.get("off", [])
		if ov is Array and ov.size() == 2:
			c += Vector2(float(ov[0]), float(ov[1]))
		if c == Vector2.INF:
			continue
		var R: float = minf(r_zone * float(_vp(v, "r")), float(_vp(v, "max_r")))
		if R <= 1.0:
			continue
		var n: int = int(_vp(v, "n"))
		var acc_n: int = mini(int(_vp(v, "acc_n")), n)
		var nm: int = int(_vp(v, "motes"))
		if not e.vx.has(i):
			# 随机常数（g.vrng）：流线 [基角, 相位, 弧长倍率, 透明度倍率, 速度倍率, 线宽倍率]，光点 [角, 半径比例, 相位, 速度, 闪烁相位]
			var sl: Array = []
			for k in n:
				sl.append([g.vrng.randf() * TAU, g.vrng.randf(), g.vrng.randf_range(0.6, 1.4), g.vrng.randf_range(0.45, 1.0),
					g.vrng.randf_range(0.75, 1.3), g.vrng.randf_range(0.6, 1.25)])
			var ml: Array = []
			for k in nm:
				ml.append([g.vrng.randf() * TAU, sqrt(g.vrng.randf()) * 0.95, g.vrng.randf(), g.vrng.randf_range(0.15, 0.4), g.vrng.randf() * TAU,
					2.0 if g.vrng.randf() < 0.3 else 1.0])
			e.vx[i] = [sl, ml]
		var sl2: Array = e.vx[i][0]
		var ml2: Array = e.vx[i][1]
		var sy: float = float(_vp(v, "sy"))
		var col: Color = _vcol(v, "col") * Color(tint.r, tint.g, tint.b, 1.0)
		var acc: Color = _vcol(v, "acc") * Color(tint.r, tint.g, tint.b, 1.0)
		# 整片水色底 + 中心柔光：径向扇形（中心 → glow_r → 外缘），顶点色插值成软边
		var fill: float = float(_vp(v, "fill")) * al
		var glow: float = float(_vp(v, "glow")) * al
		if fill > 0.002 or glow > 0.002:
			var gr: float = R * float(_vp(v, "glow_r"))
			var segc := 28
			var b0: int = pts.size()
			pts.append(c)
			cols.append(Color(col.r, col.g, col.b, glow + fill))
			for q in segc:
				var d := Vector2(cos(q * TAU / segc), sin(q * TAU / segc) * sy)
				pts.append(c + d * gr)
				cols.append(Color(col.r, col.g, col.b, fill))
				pts.append(c + d * R)
				cols.append(Color(col.r, col.g, col.b, 0.0))
			for q in segc:
				var q1: int = (q + 1) % segc
				var i0: int = b0 + 1 + q * 2
				var i1: int = b0 + 1 + q1 * 2
				idx.append_array([b0, i0, i1, i0, i0 + 1, i1 + 1, i0, i1 + 1, i1])
		# 流线
		var r0: float = float(_vp(v, "r0"))
		var ln: float = float(_vp(v, "len"))
		var curl: float = float(_vp(v, "curl"))
		var spin: float = float(_vp(v, "spin"))
		var drift: float = float(_vp(v, "drift"))
		var w: float = float(_vp(v, "w"))
		var amax: float = float(_vp(v, "a")) * al
		var acc_a: float = float(_vp(v, "acc_a"))
		var seg: int = int(_vp(v, "seg"))
		var halo: float = float(_vp(v, "halo"))
		var halo_a: float = float(_vp(v, "halo_a"))
		var dir: float = 1.0 if spin >= 0.0 else -1.0
		for k in n:
			var s: Array = sl2[k]
			var u: float = fposmod(float(s[1]) + t * drift * float(s[4]), 1.0)
			var env: float = sin(u * PI)
			var aa: float = amax * float(s[3]) * env
			if aa <= 0.004:
				continue
			var rf: float = lerpf(1.0, r0, u)
			var a0: float = float(s[0]) + spin * t * float(s[4]) / (0.35 + 0.65 * rf)
			var cc: Color = acc if k < acc_n else col
			if k < acc_n:
				aa *= acc_a
			var L: float = ln * float(s[2]) * (0.6 + 0.4 * rf)
			var ww: float = w * float(s[5])
			var cp := PackedVector2Array()   # 中心线与法向（近似取径向：流线大致沿切向）
			var cn := PackedVector2Array()
			var pr := PackedFloat32Array()   # 沿线包络：两端渐隐、中段最亮
			for q in seg + 1:
				var sq: float = float(q) / seg
				var ang: float = a0 - dir * L * (1.0 - sq)          # 头（sq = 1）在前，尾在后
				var rr: float = R * (rf + curl * (1.0 - sq) * rf)    # 尾端更靠外：螺旋
				var ca2: float = cos(ang)
				var sa2: float = sin(ang)
				cp.append(c + Vector2(ca2 * rr, sa2 * rr * sy))
				cn.append(Vector2(ca2, sa2 * sy).normalized())
				pr.append(sin(sq * PI))
			# 两遍：halo（宽、很淡，软边水光）→ 芯线（细、亮）
			for pass_i in 2:
				var pw: float = ww * (halo if pass_i == 0 else 1.0)
				var pa: float = aa * (halo_a if pass_i == 0 else 1.0)
				if pass_i == 0 and (halo <= 0.0 or halo_a <= 0.0):
					continue
				var b1: int = pts.size()
				for q in seg + 1:
					var nrm: Vector2 = cn[q] * (pw * 0.5 * (0.35 + 0.65 * pr[q]))
					var va: float = pa * pow(pr[q], 0.7) if q > 0 and q < seg else 0.0
					pts.append(cp[q] - nrm)
					pts.append(cp[q] + nrm)
					var vc := Color(cc.r, cc.g, cc.b, va)
					cols.append(vc)
					cols.append(vc)
				for q in seg:
					var j: int = b1 + q * 2
					idx.append_array([j, j + 1, j + 3, j, j + 3, j + 2])
		# 光点：跟着漩涡慢转、上飘、闪烁（mote_sz 见方的小方块，三成是两倍大，像素风）
		var ma: float = float(_vp(v, "mote_a")) * al
		var msz: float = float(_vp(v, "mote_sz"))
		var mrise: float = float(_vp(v, "mote_rise"))
		var mcol: Color = Color(minf(col.r * 1.3, 1.0), minf(col.g * 1.15, 1.0), 1.0)
		for k in nm:
			var m: Array = ml2[k]
			var ph: float = fposmod(float(m[2]) + t * float(m[3]), 1.0)
			var am: float = ma * sin(ph * PI) * (0.6 + 0.4 * sin(t * 5.0 + float(m[4])))
			if am <= 0.004:
				continue
			var ang2: float = float(m[0]) + spin * 0.6 * t
			var rm: float = R * float(m[1])
			var mp := c + Vector2(cos(ang2) * rm, sin(ang2) * rm * sy - ph * mrise)
			mp = mp.round()
			var ms: float = msz * float(m[5])
			var b2: int = pts.size()
			pts.append_array([mp, mp + Vector2(ms, 0), mp + Vector2(ms, ms), mp + Vector2(0, ms)])
			var mc := Color(mcol.r, mcol.g, mcol.b, am)
			cols.append_array([mc, mc, mc, mc])
			idx.append_array([b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3])
	if idx.is_empty():
		return
	if sink != null and sink.has_method("add_tris"):
		sink.add_tris(pts, cols, idx)
	else:
		RenderingServer.canvas_item_add_triangle_array(sink.get_canvas_item(), idx, pts, cols)


## 校验漩涡参数（§8 第 9 条）
static func _fx_vortex_check(v, q: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if not (v is Dictionary):
		errs.append(q + ".vortex 必须是对象（参数见 docs/61 §5.6 漩涡表）")
		return
	for k in v:
		if not VORTEX_DEF.has(k):
			errs.append("%s.vortex.%s：不认识的漩涡参数（只能是 %s）" % [q, k, " / ".join(VORTEX_DEF.keys())])
		elif k in ["col", "acc"]:
			var a = v[k]
			if not (a is Array) or a.size() != 3 or a.any(func(x): return not (x is int or x is float)):
				errs.append("%s.vortex.%s 必须是 3 个数字的数组" % [q, k])
		elif VORTEX_LIM.has(k):
			_num(v, k, q + ".vortex", ctx, false, float(VORTEX_LIM[k][0]), float(VORTEX_LIM[k][1]))


## 贴身层（behind / front）：锚点对准干员脚底 o.pos（+ off）；e 是贴身层记录 {b, el = 积木已生效秒数, fade}，进出淡入淡出按条目 fade（fx_hold_alpha）
static func fx_body(ci, o, e: Dictionary, front: bool) -> void:
	var g = o.g
	var entries = e.b.get("fx", [])
	var el: float = float(e.el)
	if not (entries is Array) or o.pos == Vector2.INF:
		return
	for f in entries:
		if not (f is Dictionary) or str(f.get("layer", "")) != ("front" if front else "behind") or not fx_on(o, f):
			continue
		var name: String = str(f.get("strip", ""))
		if g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var tv = f.get("tint", [])
		var col := Color.WHITE
		if tv is Array and tv.size() >= 3:
			col = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		col.a *= fx_hold_alpha(f, e) * g.world.fx_dim
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		if f.get("face_x", false):   # 精英化段：偏移随朝向（星熊盾在身前）
			off.x *= float(o.face)
		var base: Vector2 = o.pos
		if f.has("on_sprite"):   # 10-15：跟着帧条里的定位点走（星熊反击架势红光对准盾心）；这一帧没有（盾离手）就不画
			base = o.sprite_point(str(f.on_sprite)) if o.has_method("sprite_point") else Vector2.INF
			if base == Vector2.INF:
				continue
		var av = f.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2(-1, -1)
		fx_frame(ci, g, name, frames, int(floor(el * float(spec[1]))) % frames, base + off, float(f.get("scale", 1.0)) * g.PX, col, anc, deg_to_rad(float(f.get("ang", 0.0))))


## shape.orbit 上 at = orbit 的条目：每个判定点画一个循环帧条（代替缺省的小菱形）。返回是否画了（缺图时 false，调用方画菱形）
static func fx_orbit(ci, o, b: Dictionary, pts: Array, dim: float) -> bool:
	var g = o.g
	var drew := false
	for f in b.get("fx", _EA):
		if not (f is Dictionary) or str(f.get("at", "")) != "orbit" or not fx_on(o, f):
			continue
		var name: String = str(f.get("strip", ""))
		if g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var sc: float = float(f.get("scale", 1.0)) * g.PX
		var tv = f.get("tint", [])
		var col := Color.WHITE
		if tv is Array and tv.size() >= 3:
			col = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		col.a *= dim
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		var anc := Vector2(-1, -1)
		var av = f.get("anchor", [])
		if av is Array and av.size() == 2:
			anc = Vector2(float(av[0]), float(av[1]))
		for k in pts.size():
			fx_frame(ci, g, name, frames, int(g.t * float(spec[1])) + k, pts[k] + off, sc, col, anc)
		drew = true
	return drew


## 校验 fx 列表（docs/61 §8 第 9 条）。owner：所属积木的「族.名」，技能本身是 "cast"
static func _fx(arr, p: String, ctx: Dictionary, owner: String) -> void:
	var errs: Array = ctx.errs
	if not (arr is Array):
		errs.append(p + " 必须是数组（fx 条目列表）")
		return
	if arr.size() > 16:
		errs.append("%s：一块积木至多 16 个 fx 条目，这里有 %d 个" % [p, arr.size()])
	var instant_owner: bool = owner in FX_INSTANT_OWNERS
	for i in arr.size():
		var q := "%s[%d]" % [p, i]
		var f = arr[i]
		if not (f is Dictionary):
			errs.append(q + " 必须是对象")
			continue
		if _F()._hw_fx_check(f, q, ctx, owner):   # 手写迁移段的程序条目（blade / aura_ring / outline）
			continue
		if _F()._mf_fx_check(f, q, ctx, owner):   # 召唤物扩展段的程序条目（pfx / sprite / sparks / ghost …）
			continue
		for k in f:
			if not k in FX_KEYS:
				errs.append("%s.%s：fx 条目不认识的字段（只能是 %s）" % [q, k, " / ".join(FX_KEYS)])
		for flag in ["no_fade", "inward"]:
			if f.has(flag) and not f[flag] is bool:
				errs.append(q + "." + flag + " 须为布尔值")
		var sn = f.get("strip", null)
		if f.has("vortex"):
			# 程序漩涡：不用帧条；常驻跟随（同贴身层），只能挂在常驻积木上；层只能 floor / add；at 只能 zone / self / leader
			_fx_vortex_check(f.vortex, q, ctx)
			if f.has("strip"):
				errs.append(q + "：vortex 条目是程序画法，不写 strip")
			if instant_owner:
				errs.append(q + ".vortex 是常驻漩涡，只能挂在常驻积木上（光环、技能 do 里的常驻积木等）")
			if not str(f.get("layer", "floor")) in ["floor", "add"]:
				errs.append(q + ".layer：vortex 只能是 floor / add")
			if not str(f.get("at", "zone")) in ["zone", "self", "leader"]:
				errs.append(q + ".at：vortex 只能是 zone / self / leader")
			for k in ["every", "life", "n", "spread", "rise", "fit", "scale", "max_scale", "anchor", "ang", "rot"]:
				if f.has(k):
					errs.append("%s.%s：vortex 条目不写这个字段（参数写进 vortex 对象）" % [q, k])
		elif not (sn is String) or not (sn.begins_with("fx_") or sn.begins_with("proj_")):
			errs.append(q + ".strip 必须是 V6_FRAMES 里登记的帧条名（fx_* / proj_*）")
		if not str(f.get("layer", "over")) in FX_LAYERS:
			errs.append("%s.layer 只能是 %s" % [q, " / ".join(FX_LAYERS)])
		var at := str(f.get("at", "center"))
		if not at in FX_AT:
			errs.append("%s.at 只能是 %s" % [q, " / ".join(FX_AT)])
		elif at == "orbit" and owner != "shape.orbit":
			errs.append(q + ".at = orbit 只能挂在 shape.orbit 上")
		elif at == "hits" and not owner in FX_HITS_OWNERS:
			errs.append(q + ".at = hits 只能挂在伤害形状（shape.circle / shape.cone）上")
		if str(f.get("layer", "")) in FX_BODY:
			if instant_owner:
				errs.append(q + ".layer = behind / front 是贴身常驻层，只能挂在常驻积木上（技能 do 里的常驻积木、光环等）")
			if f.has("every") or f.has("life") or f.has("n") or f.has("spread") or f.has("rise"):
				errs.append(q + "：贴身层（behind / front）跟着积木生效循环，不写 every / life / n / spread / rise")
			if at != "self" and f.has("at"):
				errs.append(q + ".at：贴身层只能是 self（干员脚底）")
		if f.has("every") and instant_owner:
			errs.append(q + ".every：瞬时积木 / 技能发动只播一次，every 只能写在常驻积木上")
		# 常驻跟随帧条 hold / 进出淡入淡出 fade / 按贴图有无取舍 if_tex（10-12 加，§5.6）
		if f.has("hold"):
			if not (f.hold is bool):
				errs.append(q + ".hold 必须是 true / false")
			elif f.hold:
				if f.has("vortex"):
					errs.append(q + ".hold：vortex 本来就跟着积木常驻，不写 hold")
				if instant_owner:
					errs.append(q + ".hold 是常驻跟随帧条，只能挂在常驻积木上（技能 do 里的常驻积木、光环等）")
				if not str(f.get("layer", "floor")) in FX_HOLD_LAYERS:
					errs.append("%s.layer：hold 帧条只能是 %s" % [q, " / ".join(FX_HOLD_LAYERS)])
				if not at in ["center", "zone", "self", "leader", "members"]:
					errs.append(q + ".at：hold 帧条只能是 zone / self / leader / members")
				if at == "members" and not owner.begins_with("aura."):
					errs.append(q + ".at = members（光环受益者）只能挂在 aura.* 上")
				for k in ["every", "life", "n", "spread", "rise", "rot"]:
					if f.has(k):
						errs.append("%s.%s：hold 帧条跟着积木生效循环，不写这个字段" % [q, k])
		if str(f.get("layer", "")) == "ground" and not _hold(f):
			errs.append(q + ".layer = ground 只给常驻跟随帧条（hold: true）用")
		if f.has("fade"):
			var fv = f.fade
			if not fx_is_hold(f):
				errs.append(q + ".fade 只用于常驻跟随条目（贴身层 / vortex / hold 帧条）")
			if fv is int or fv is float:
				if float(fv) < 0.0 or float(fv) > 5.0:
					errs.append(q + ".fade 超出范围（0–5 秒）")
			elif fv is Array and fv.size() == 2 and fv.all(func(x): return x is int or x is float):
				if fv.any(func(x): return float(x) < 0.0 or float(x) > 5.0):
					errs.append(q + ".fade 超出范围（0–5 秒）")
			else:
				errs.append(q + ".fade 必须是秒数，或 [淡入, 淡出] 两个秒数")
		if f.has("if_tex"):
			var tn = f.if_tex
			var tb: String = tn.trim_prefix("!") if tn is String else ""
			if not (tb.begins_with("fx_") or tb.begins_with("proj_")):
				errs.append(q + ".if_tex 必须是帧条名（fx_* / proj_*），前面加 ! 表示缺这条贴图时才画")
		if f.has("cond"):
			if not (f.cond is String):
				errs.append(q + ".cond 必须是字符串")
			else:
				var c := parse_cond(f.cond, ctx.base)
				if c.has("err"):
					errs.append("%s.cond：%s" % [q, c.err])
		# 扩散缓动 ease / grow / grow0 / grow_to / wake、交叉淡入淡出 xfade（10-13 加，§5.6）
		if f.has("ease") or f.has("grow") or f.has("grow0") or f.has("grow_to") or f.has("wake"):
			if not str(f.get("ease", "")) in FX_EASES:
				errs.append("%s.ease 只能是 %s（grow / grow0 / grow_to / wake 要配 ease）" % [q, " / ".join(FX_EASES)])
			if fx_is_hold(f) or f.has("life") or f.has("vortex"):
				errs.append(q + ".ease：扩散缓动只给一次性帧条用（不写 hold / life / vortex，不放贴身层）")
			if f.has("grow_to") and str(f.grow_to) != "zone" and not _F().e5_grow_to_ok(f.grow_to, ctx):
				errs.append(q + ".grow_to 只能是 zone（扩到区域半径、跟着区域走）/ summon:<带 zone 的召唤物种类>")
			if f.has("play") and str(f.play) != "fps":
				errs.append(q + ".play 只能是 fps（帧号按帧条 fps 播）")
			if f.has("wake"):
				var wk = f.wake
				if not (wk is Dictionary):
					errs.append(q + ".wake 必须是对象 {n, w, a, lag, sy, col}")
				else:
					for k in wk:
						if k == "col":
							var cv = wk.col
							if not (cv is Array) or cv.size() != 3 or cv.any(func(x): return not (x is int or x is float)):
								errs.append(q + ".wake.col 必须是 3 个数字 [r, g, b]")
						elif not FX_WAKE_LIM.has(k):
							errs.append("%s.wake.%s：不认识的参数（只能是 n / w / a / lag / sy / col）" % [q, k])
						elif not (wk[k] is int or wk[k] is float) or float(wk[k]) < float(FX_WAKE_LIM[k][0]) or float(wk[k]) > float(FX_WAKE_LIM[k][1]):
							errs.append("%s.wake.%s 超出范围（%s–%s）" % [q, k, str(FX_WAKE_LIM[k][0]), str(FX_WAKE_LIM[k][1])])
		if f.has("play") and not f.has("ease"):   # 精英化第 5 批段
			errs.append(q + ".play 要配 ease（只用于扩散缓动条目）")
		if f.has("xfade"):
			if fx_is_hold(f):
				errs.append(q + ".xfade 只给一次性帧条用（常驻条目的 cond 切换另有淡入淡出）")
			if not f.has("cond"):
				errs.append(q + ".xfade 要配 cond（按 cond 的真假交叉淡入淡出）")
		_num(f, "grow", q, ctx, false, 0.1, 3.0)
		_num(f, "grow0", q, ctx, false, 0.0, 0.95)
		_num(f, "xfade", q, ctx, false, 0.0, 3.0)
		_num(f, "fit", q, ctx, false, 1.0, 512.0)
		_num(f, "scale", q, ctx, false, 0.05, 8.0)
		_num(f, "max_scale", q, ctx, false, 0.5, 16.0)
		_num(f, "n", q, ctx, false, 1.0, 16.0)
		_num(f, "spread", q, ctx, false, 0.0, 1.5)
		_num(f, "rise", q, ctx, false, -400.0, 400.0)
		_num(f, "life", q, ctx, false, 0.05, 5.0)
		_num(f, "every", q, ctx, false, 0.05, 60.0)
		_num(f, "ang", q, ctx, false)
		# 精英化段（docs/91 第 1 批）：delay / stay / once / face_x / flash；at = members / mate 的宿主
		_num(f, "delay", q, ctx, false, 0.0, 5.0)
		_num(f, "stay", q, ctx, false, 0.05, 5.0)
		_num(f, "along", q, ctx, false, -2.0, 2.0)
		for k in ["once", "face_x"]:
			if f.has(k) and not (f[k] is bool):
				errs.append("%s.%s 只能是 true / false" % [q, k])
		if (f.has("delay") or f.has("stay")) and fx_is_hold(f):
			errs.append(q + "：delay / stay 只给一次性帧条用")
		if f.has("stay") and f.has("life") and not f.get("once", false):
			errs.append(q + ".stay：循环帧条（写了 life）不停在末帧")
		if f.has("flash") and (str(f.flash) != "fire" or not _hold(f)):
			errs.append(q + ".flash 只能是 fire，且只给常驻跟随帧条（hold）用")
		if at == "mate" and owner != "trig.on_mate_attack":
			errs.append(q + ".at = mate 只能挂在 trig.on_mate_attack 上")
		if at == "members" and not _hold(f):
			errs.append(q + ".at = members 只给常驻跟随帧条（hold）用")
		for k in f:
			if k != "cond" and f[k] is String and "$" in f[k]:
				var ev := eval_expr(f[k], ctx.base)
				if not ev[0]:
					errs.append("%s.%s：%s" % [q, k, ev[2]])
		for k in [["tint", 3, 4], ["anchor", 2, 2], ["off", 2, 2]]:
			if f.has(k[0]):
				var v = f[k[0]]
				if not (v is Array) or v.size() < k[1] or v.size() > k[2] or v.any(func(x): return not (x is int or x is float)):
					errs.append("%s.%s 必须是 %d%s 个数字的数组" % [q, k[0], k[1], "" if k[1] == k[2] else "–%d" % k[2]])
