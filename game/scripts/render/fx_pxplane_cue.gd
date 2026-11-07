## 成长节点通用提示（docs/310 §2，11-07 用户「成长节点开始修」）：转平面接管后 o.fx / o.sparks 不画，
## 节点触发时的提示改走这个事件：`_FXR.ev(o, "node_cue", {...})`。只画，不碰玩法与玩法随机数（形状散布按 t0 / 位置哈希）。
##
## 字段：p 位置（世界）· top 立起件压最上层 · c 主色（Color，缺省干员配方 main）· shape · r 半径 · r0 起始半径 · life 秒 · n 火花数 · fe 跟随的敌人（只读位置）· to 目标干员 id（mote）
##   ring   贴地扩散环：3 美术像素宽（外暗 / 中主色 / 内亮），r0 → r，外加 n 颗像素火花向外飞
##   in     贴地收缩环：r → r × 0.3（拉拢、聚拢）
##   burst  只有火花（不画环）：碎片 / 火星四散
##   mark   跟随敌人的四角准星（目标被选中 / 被标记），轻微收紧
##   mote   一颗带尾光点从 p 飞向干员 to（技力 / 回复「交给谁」）；to 为 "*" 时飞向全部其他干员、"@" 飞向队长
##   ghost  队长（to 缺省 "@"，或干员 id）在 p 处留一份当前帧的着色残影，向上飘散（德克萨斯居合刷新冲刺）
## 节拍按 15 fps 跳格（同其余转平面件），同屏至多 CAP 个，超出顶掉最旧的。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const CAP := 32
const SY := 0.62   # 贴地环纵向压扁（同地面椭圆）


static var _log := -1   # --cuelog（调试构建）：每次推入带 tag 的提示打一行 CUE（实机局对照挑帧用，tools/gcp/render_jobs/cue_real.sh）


static func push(r, o, d: Dictionary) -> void:
	if Bal.v("fx/node_cue", 1.0) <= 0.0:   # 0 = 关（选前 / 选后同帧对照用，docs/310）
		return
	if _log < 0:
		_log = 1 if OS.is_debug_build() and OS.get_cmdline_user_args().has("--cuelog") else 0
	if _log == 1 and d.has("tag"):
		var sp: Vector2 = r.g.get_viewport().get_canvas_transform() * Vector2(d.get("p", o.pos)) if r.g.is_inside_tree() else Vector2.ZERO
		print("CUE %.3f %s %s %d %d" % [float(r.g.t), str(o.id), str(d.tag), int(sp.x), int(sp.y)])   # 屏幕坐标（挑帧后按这里裁小块）
	if str(d.get("shape", "")) == "none":   # 只记日志的标记点（直接改绘制、没有提示事件的项）
		return
	var c: Color = d.get("c", Color(-1, 0, 0))
	if c.r < 0.0:
		var p: Dictionary = load("res://scripts/render/fx_recipe.gd").of(r.g).pal(o)
		c = p.get("main", p.get("light", Color(1, 0.85, 0.4)))
	var sh: String = str(d.get("shape", "ring"))
	var pos: Vector2 = d.get("p", o.pos)
	var base := {"t0": float(r.g.t), "c": c, "shape": sh, "p": pos, "oid": str(o.id),
		"r": float(d.get("r", 40.0)), "r0": float(d.get("r0", 8.0)), "life": float(d.get("life", {"mote": 0.55, "mark": 0.5}.get(sh, 0.35))),
		"n": int(d.get("n", 6)), "seed": int(absf(pos.x) * 7.0 + absf(pos.y) * 13.0) % 997}
	if d.has("fe") and d.fe is Dictionary:
		base["fe"] = d.fe
	if d.get("top", false):
		base["top"] = true   # 立起件压最上层（头顶处的火花，不被敌人本体盖住）
	if sh == "ghost":
		var who = _who(r, str(d.get("to", "@")))
		if who == null:
			return
		base["to"] = str(who.id)
		base["st"] = who.anim_state()   # 推入时的那一帧（残影定格，不跟着本体换帧）
		base["flip"] = float(who.face) < 0.0
	if sh == "mote":
		var to: String = str(d.get("to", "@"))
		var tos: Array = []
		if to == "*":
			for m in r.g.squad.ops:
				if m != o and m.pos != Vector2.INF:
					tos.append(str(m.id))
		else:
			tos.append(to)
		var k := 0
		for tid in tos:
			var it: Dictionary = base.duplicate()
			it["to"] = tid
			it["t0"] = float(r.g.t) + 0.04 * k   # 一颗接一颗，不叠成一团
			it["seed"] = (int(it.seed) + 131 * k) % 997
			_add(r, it)
			k += 1
		return
	_add(r, base)


static func _who(r, to: String):
	if to == "@":
		return r.g.squad.leader()
	return r._op(to)


static func _add(r, it: Dictionary) -> void:
	if r.cues.size() >= CAP:
		r.cues.pop_front()
	r.cues.append(it)


static func step(r) -> void:
	var now: float = r.g.t
	r.cues = r.cues.filter(func(it): return now - float(it.t0) < float(it.life) + 0.07)


static func _age(r, it: Dictionary) -> float:
	return maxf(0.0, floor((float(r.g.t) - float(it.t0)) * 15.0) / 15.0)


static func _pos(it: Dictionary) -> Vector2:
	if it.has("fe"):
		var e: Dictionary = it.fe
		if not e.get("dead", false):
			return e.pos
	return it.p


static func _h(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)


## 贴地层（fx_pxplane.draw_floor 开头）：ring / in 的环身
static func floor_layer(r, o) -> void:
	if r.cues.is_empty():
		return
	var cv = o.cv
	var id: String = str(o.id)
	for it in r.cues:
		if str(it.oid) != id or float(r.g.t) < float(it.t0):
			continue
		var sh: String = str(it.shape)
		if sh != "ring" and sh != "in":
			continue
		var u: float = clampf(_age(r, it) / maxf(0.05, float(it.life)), 0.0, 1.0)
		var e: float = 1.0 - (1.0 - u) * (1.0 - u)
		var rr: float = lerpf(float(it.r0), float(it.r), e) if sh == "ring" else lerpf(float(it.r), float(it.r) * 0.3, e)
		var a: float = 1.0 if u < 0.55 else clampf(1.0 - (u - 0.55) / 0.45, 0.0, 1.0)
		_ring(r, cv, _pos(it), rr, it.c, a, int(it.seed))


static func _ring(r, ci, c: Vector2, rr: float, col: Color, a: float, seed: int) -> void:
	var px: float = r.g.PX
	var n: int = maxi(12, int(TAU * rr / px))
	var dk: Color = col.darkened(0.55)
	var lt: Color = col.lightened(0.55)
	dk.a = a * 0.9
	var mc: Color = col
	mc.a = a
	lt.a = a
	var gl := 0
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var dv := Vector2(cos(ang), sin(ang) * SY)
		r._px(ci, c + dv * (rr + px), dk)
		r._px(ci, c + dv * rr, mc)
		r._px(ci, c + dv * (rr - px), lt)
		if a > 0.5 and i % 9 == seed % 9 and gl < 8:
			r._glow(c + dv * rr, col)
			gl += 1


## 立起层：火花、准星、光点（fx_pxplane.sort_items 收进来，按脚底 y 排序）
static func sort_items(r, out: Array) -> void:
	for it in r.cues:
		if float(r.g.t) < float(it.t0):
			continue
		var y: float = _pos(it).y + 1.0
		if str(it.shape) == "mote" or str(it.shape) == "mark" or it.get("top", false):
			y = 1e6   # 飞向队友的光点（跨越整屏）与准星（套在敌人身上，不能被敌人本体盖住）压在最上面
		out.append({"cue": it, "skey": y})


static func draw_up(r, ci, it: Dictionary) -> void:
	var sh: String = str(it.shape)
	var px: float = r.g.PX
	var age: float = _age(r, it)
	var u: float = clampf(age / maxf(0.05, float(it.life)), 0.0, 1.0)
	var col: Color = it.c
	var lt: Color = col.lightened(0.6)
	var a: float = 1.0 if u < 0.6 else clampf(1.0 - (u - 0.6) / 0.4, 0.0, 1.0)
	lt.a = a
	var mc: Color = col
	mc.a = a
	var c: Vector2 = _pos(it)
	var sd: int = int(it.seed)
	match sh:
		"ring", "in", "burst":
			var n: int = int(it.n)
			var R0: float = float(it.r0) if sh != "in" else float(it.r)
			var R1: float = float(it.r) * (1.35 if sh != "in" else 0.25)
			for k in n:
				var ang: float = TAU * (float(k) + _h(sd + k) * 0.6) / float(maxi(1, n))
				var sp: float = lerpf(R0, R1, 1.0 - (1.0 - u) * (1.0 - u)) * (0.8 + 0.4 * _h(sd + 31 * k))
				var q: Vector2 = c + Vector2(cos(ang), sin(ang) * SY) * sp + Vector2(0, -6.0 - 10.0 * u)
				r._px(ci, q, lt)
				if u < 0.5:   # 前半程带一格尾巴
					r._px(ci, q - Vector2(cos(ang), sin(ang) * SY) * px, mc)
					r._glow(q, col)
		"mark":
			var e: Dictionary = it.get("fe", {})
			var er: float = float(e.get("r", 14.0)) if not e.is_empty() else 14.0
			var h: float = er * (1.6 - 0.45 * minf(1.0, u * 3.0)) + px * 3.0
			var cc: Vector2 = c + Vector2(0, -er * 0.55)
			var dk: Color = col.darkened(0.6)
			dk.a = a
			for sx in [-1.0, 1.0]:
				for sy2 in [-1.0, 1.0]:   # 四角 L 形：每条臂 3 美术像素、2 像素粗，外圈暗边
					var k0: Vector2 = cc + Vector2(sx * h, sy2 * h * 0.85)
					for j in 5:
						for w in 2:
							var ph: Vector2 = k0 - Vector2(sx * px * j, sy2 * px * w)
							var pv: Vector2 = k0 - Vector2(sx * px * w, sy2 * px * j)
							r._px(ci, ph + Vector2(0, sy2 * px), dk)
							r._px(ci, pv + Vector2(sx * px, 0), dk)
							r._px(ci, ph, lt if j == 0 else mc)
							r._px(ci, pv, lt if j == 0 else mc)
			if u < 0.5:
				r._glow(cc, col)
		"ghost":
			var who = r._op(str(it.get("to", "")))
			if who == null or (it.get("st", {}) as Dictionary).is_empty():
				return
			var gc: Color = col.lightened(0.5)
			gc.a = a * 0.9
			who.draw_body_at((c + Vector2(0, -px * floor(u * 4.0))).round(), bool(it.flip), gc, it.st)
			if u < 0.5:
				r._glow(c + Vector2(0, -20), col)
		"mote":
			var to = r._op(str(it.get("to", "")))
			var dst: Vector2 = r.g.ppos if str(it.get("to", "")) == "@" or to == null else to.pos
			if dst == Vector2.INF:
				return
			dst += Vector2(0, -26)
			var src: Vector2 = it.p + Vector2(0, -10)
			var mid: Vector2 = (src + dst) * 0.5 + Vector2(0, -30.0 - 20.0 * _h(sd))
			var tt: float = 1.0 - (1.0 - u) * (1.0 - u)
			for j in 3:
				var t2: float = clampf(tt - 0.07 * float(j), 0.0, 1.0)
				var q: Vector2 = src.lerp(mid, t2).lerp(mid.lerp(dst, t2), t2)
				var cj: Color = lt if j == 0 else mc
				cj.a = a * (1.0 - 0.3 * float(j))
				r._px(ci, q, cj)
				if j == 0:
					r._px(ci, q + Vector2(px, 0), mc)
					r._glow(q, col)
			if u > 0.85:   # 到手一闪
				for dv in [Vector2(px * 2, 0), Vector2(-px * 2, 0), Vector2(0, px * 2), Vector2(0, -px * 2)]:
					r._px(ci, dst + dv, lt)
