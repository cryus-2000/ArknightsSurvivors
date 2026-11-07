## 拉普兰德转平面（docs/273，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第五批四人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_lappland.py 烤（图形 tools/pxplane_lappland_art.py），键前缀 lp_；
## 剑气细针 / 狼首弹拖尾与晶片 / 命中斩痕 / 封招符印 / 观察刻痕 / 连携斩痕在这里按美术像素格逐格画（算法同 pxplane_lappland_art.py 的
## needle() / cut_px() / cross_px() / tally_px()，改一边要改另一边）。
## 只画：读玩法状态（o.hw.waves、o.vg.qi、敌人的 seal_t / 观察层数），画面专用键只写剑气字典的 _pxq（按 15 fps 跳格的位置），玩法不读；不碰玩法与玩法随机数。
## 挂在人身上的件带 fo（跟她）或 fol（日晷格挡跟队长）；斩痕 / 剑气命中星跟被打的那只（e / ef）；冲击环、声波、烟环、刻痕环留原地。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const CUE = preload("res://scripts/render/fx_pxplane_cue.gd")   # 成长节点提示（docs/310）

const LP := [Color("#15121f"), Color("#2b2542"), Color("#4a4274"), Color("#7b70b4"), Color("#b3aae4"), Color("#e4e0ff"), Color("#ffffff")]
const WOLF := [Color("#0a090f"), Color("#1b1828"), Color("#2e2a40"), Color("#4d4862"), Color("#8a8698"), Color("#cfcdd8"), Color("#ffffff")]
const SHADOW := Color("#100e16")
const ATK_R := [44, 50, 58, 68]
const DANCE_R := [60, 70, 84]
const BARK_R := [75, 90]
const CROSS_N := 4                      # 封招叉半臂长（美术像素，同 pxplane_lappland_art.CROSS_N）
const CROSS_CORE := Color("#46464a")     # 原作 chenmo_02 笔画深灰
const CROSS_RIM := Color("#c4c6ca")      # 原作描边浅灰（提亮，暗地面上读得出）
const HIT_N := 3           # 一记横扫至多画 3 只身上的斩痕
const WHIT_BEAT := 3       # 剑气命中星每拍至多 3 个
const LIGHT := Color(0.78, 0.74, 1.0)

var _parent: WeakRef
var r:   # Owner holds this helper; the backreference must not retain its cache.
	get:
		return _parent.get_ref()
var g
var _beat := {}
var _last_atk := {}        # 干员 id → 上一记双刃的时刻（双刃连斩补刀 0.12 秒后到，画反向月牙）
var _links: Array = []     # 连携月牙剑气：{oid, sp, ep, t0, T, d}
var _rt: Array = []        # 运行时地面件：{k: scar / chain, a, b, t0}
var _claw_rot := 0         # 狼之舞爪痕起始组型（只画）
var _seal_st := {}         # 敌人 id → [封印止时刻, 起拍时刻]（不往敌人字典里写画面键）


func _init(px) -> void:
	_parent = weakref(px)
	g = px.g


func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


static func _near(arr: Array, v: float) -> int:
	return PxU.nearest(arr, v)


func _px(ci, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(Pxp._snap(p), Vector2(g.PX, g.PX)), c)


func _glow(p: Vector2, c: Color) -> void:
	if g.optical_on and r._emit_n < Pxp.EMIT_CAP:
		r._emit_n += 1
		g.glow_next.append([Pxp._snap(p), g.PX, Color(c, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])


## 一对挂在她身上的方向件（立起 + 贴地）；斩击类只留最近两刀（11-05 用户「碎斩击」口径，同 fx_pxplane._add）
func _slash(o, up_key: String, gd_key: String, ang: float) -> void:
	var sl: Array = []
	for it in r.items:
		if str(it.oid) == str(o.id) and it.get("slash", false) and str(it.ly) == "up":
			sl.append(float(it.t0))
	if sl.size() >= 2:
		sl.sort()
		var keep_t: float = float(sl[sl.size() - 1])
		r.items = r.items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == str(o.id) and float(it.t0) < keep_t))
	var dk: Array = Pxp.pick_dir(ang)
	r._push({"k": up_key % int(dk[0]), "t0": g.t, "gp": Pxp._snap(o.pos), "flip": dk[1], "ly": "up", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})
	r._push({"k": gd_key % int(dk[0]), "t0": g.t, "gp": Pxp._snap(o.pos), "flip": dk[1], "ly": "gd", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})


func _on_her(o, k: String, ly: String) -> void:
	r._push({"k": "lp_" + k, "t0": g.t, "gp": Pxp._snap(o.pos), "flip": false, "ly": ly, "oid": str(o.id), "fo": Vector2.ZERO})


func _stay(o, k: String, at: Vector2, ly: String, extra := {}) -> void:
	var it := {"k": "lp_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 命中斩痕：被砍中的至多 n 只身上一道斜的白芯线（跟着那只，3 拍收掉；x = 交叉成 X）
func _cuts(o, es: Array, t: int, n: int, x: bool) -> void:
	var lst: Array = es.duplicate()
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	for i in mini(n, lst.size()):
		var e: Dictionary = lst[i]
		if e.get("dead", false):
			continue
		var rd: Vector2 = e.pos - o.pos
		var tg: Vector2 = Vector2(-rd.y, rd.x).normalized() if rd.length() > 1.0 else Vector2.RIGHT
		tg = tg.rotated(-0.45 if tg.x * tg.y >= 0.0 else 0.45)
		r._push({"lp": "cut", "k": "", "life": 0.2, "e": e, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0,
			"d": tg, "x": x, "L": 7.0 + 2.0 * t, "ly": "up", "oid": str(o.id)})


## 狼之舞爪痕（11-05 用户「更加大一点以及杂乱一点」）：一组三道弯钩抓痕，长 22–26 美术像素、角度 / 长短 / 间距各不相同，偶有分叉或断成两截；
## 三种组（帧条 lp_claw_v0/1/2：斜抓 / 近乎横抓 / 反方向），几组之间轮换错开，敌人在她左边时水平翻转；第 k 组晚 k 拍抓出；贴地 lp_claw_v*_gd 很淡的爪印
func _claws(o, es: Array, rr: float) -> void:
	var lst: Array = []
	for e in es:
		if not e.get("dead", false):
			lst.append(e)
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	var n: int = mini(3, lst.size())
	_claw_rot = (_claw_rot + 1) % 3   # 每次狼之舞换一个起始组型，连着几次不重样
	for k in n:
		var e: Dictionary = lst[k]
		var t0: float = (floor(g.t * 15.0) + k) / 15.0
		var fl: bool = (e.pos as Vector2).x < o.pos.x
		var v: int = (k + _claw_rot) % 3
		r._push({"k": "lp_claw_v%d_up" % v, "t0": t0, "gp": Pxp._snap(e.pos + Vector2(0, -float(e.r) * 0.55)), "gy": float(e.pos.y) + 1.0, "flip": fl, "ly": "up", "oid": str(o.id), "e": e})
		r._push({"k": "lp_claw_v%d_gd" % v, "t0": t0, "gp": Pxp._snap(e.pos), "flip": fl, "ly": "gd", "oid": str(o.id)})
	if n == 0:   # 没打中：身前扇形里两组
		var fa: float = o.facing_angle() if o.has_method("facing_angle") else 0.0
		for k in 2:
			var a: float = fa + (-0.35 if k == 0 else 0.35)
			var gp: Vector2 = o.pos + Vector2(cos(a), sin(a) * 0.72) * rr * 0.6
			var t1: float = (floor(g.t * 15.0) + k) / 15.0
			var v2: int = (k + _claw_rot) % 3
			r._push({"k": "lp_claw_v%d_up" % v2, "t0": t1, "gp": Pxp._snap(gp + Vector2(0, -12)), "gy": gp.y + 1.0, "flip": cos(a) < 0.0, "ly": "up", "oid": str(o.id)})
			r._push({"k": "lp_claw_v%d_gd" % v2, "t0": t1, "gp": Pxp._snap(gp), "flip": cos(a) < 0.0, "ly": "gd", "oid": str(o.id)})


## 命中颗粒（Noita：碎光片 shard 为主 + 1 枚黑三角 tri 压边长）+ 一盏照地短光
func _hit_fx(o, R, p: Dictionary, es: Array, n_shard: int, n_tri: int, lr: float, li: float, at := Vector2.INF) -> void:
	var e0 = null
	for e in es:
		if not e.get("dead", false):
			e0 = e
			break
	var hp: Vector2 = at
	var gy: float = at.y + 10.0
	var dir := Vector2.ZERO
	if e0 != null:
		hp = e0.pos + Vector2(0, -float(e0.r) * 0.55)
		gy = float(e0.pos.y) + 2.0
		dir = ((e0.pos as Vector2) - o.pos).normalized()
	if hp == Vector2.INF:
		return
	var m := {"tier": r.tier(o)}
	if n_shard > 0:
		R._grains(o, hp, gy, "shard", n_shard, m, dir)
	if n_tri > 0:
		R._grains(o, hp, gy, "tri", n_tri, m, dir)
	R._light(o, hp, lr, li, 0.12, p.light)


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var rr: float = float(d.get("r", 100.0))
				match src:
					"狼之舞":   # 精一旋身斩（11-05 用户「改成爪痕」）：被打中的至多 3 只身上各一组三道爪痕，一组隔一拍依次抓出（跟着那只）；
						# 没打中就落在她身前扇形里；地上只留很淡的爪印投影；转一圈的月牙降为陪衬（短、细、暗）
						var Rd: int = _near(DANCE_R, rr * 0.5)
						_on_her(o, "dance_r%d_up" % Rd, "up")
						_claws(o, es, rr)
						_hit_fx(o, R, p, es, 6, 2, 170.0, 0.75, o.pos + Vector2(0, -12))
					"断喝":   # 狼嚎声波：锯齿断续双环往外推（地面，留原地）
						_stay(o, "bark_r%d_gd" % _near(BARK_R, rr * 0.5), c, "gd")
						R._light(o, c + Vector2(0, -10), 180.0, 0.7, 0.15, p.light)
						R._grains(o, c + Vector2(0, -16), c.y + 2.0, "shard", 6, {"tier": t})
					"噤声":   # 观察刻满：十字斩（跟被斩的那只）
						var e1 = es[0] if not es.is_empty() else null
						var it := {"k": "lp_xcut_up", "t0": g.t, "gp": Pxp._snap(c), "flip": false, "ly": "up", "oid": str(o.id)}
						if e1 != null:
							it["ef"] = e1
						r._push(it)
						_hit_fx(o, R, p, es, 6, 3, 170.0, 0.85, c + Vector2(0, -18))
				return
			if src == "双刃":
				var ang: float = float(d.get("ang", 0.0))
				var Ra: int = _near(ATK_R, float(d.get("r", 100.0)) * 0.5)
				var mirror: bool = g.t - float(_last_atk.get(str(o.id), -9.0)) < 0.2   # 双刃连斩：0.12 秒后的补刀反向扫
				_last_atk[str(o.id)] = g.t
				_slash(o, "lp_atk_r%d_%s_up_d%%d" % [Ra, "m" if mirror else "e%d" % t], "lp_atk_r%d_gd_d%%d" % Ra, ang)
				_cuts(o, es, t, HIT_N, t >= 2)
				if not es.is_empty():
					_hit_fx(o, R, p, es, 2, 1, 110.0, 0.5)   # 体检（11-06）：一簇中位 10 → 2 + 1
		"skill":
			match int(d.get("i", -1)):
				0:   # 日晷：脚下刻度盘（精一加晷针、精二加上飘三角光点）
					_on_her(o, "s1_e%d_gd" % t, "gd")
					if t >= 2:
						_on_her(o, "s1_up", "up")
					R._light(o, o.pos + Vector2(0, -10), 110.0, 0.5, 0.15, p.light)
				1:   # 狼魂：双刃左右展开（跟她）+ 脚下黑烟环（留原地）
					_on_her(o, "s2_up", "up")
					_stay(o, "s2_gd", o.pos, "gd")
					R._light(o, o.pos + Vector2(0, -14), 150.0, 0.6, 0.15, p.light)
					R._grains(o, o.pos + Vector2(0, -20), o.pos.y + 2.0, "tri", 4, {"tier": t})
				2:   # 噤声：X 刃一闪（跟她）+ 刻痕环推到观察范围边（留原地）
					_on_her(o, "s3_up", "up")
					_stay(o, "s3_gd", o.pos, "gd")
					R._light(o, o.pos + Vector2(0, -20), 170.0, 0.7, 0.15, p.light)
		"ll_block":   # 日晷格挡：队长身前双刃交叉一闪（跟队长）
			if g.ppos == Vector2.INF:
				return
			r._push({"k": "lp_block_up", "t0": g.t, "gp": Pxp._snap(g.ppos), "flip": false, "ly": "up", "oid": str(o.id), "fol": Vector2.ZERO, "sk": 2.0})
			R._light(o, g.ppos + Vector2(0, -16), 90.0, 0.6, 0.12, p.light)
			R._grains(o, g.ppos + Vector2(0, -16), g.ppos.y + 2.0, "shard", 3, {"tier": t})
		"ll_arm":   # 日晷·反斩待命：脚下小刻度盘一闪
			_on_her(o, "arm_gd", "gd")
		"ll_riposte":   # 日晷·回敬：原地重斩（厚、亮）
			var Rr: int = _near(ATK_R, float(d.get("r", 130.0)) * 0.5)
			_slash(o, "lp_atk_r%d_h_up_d%%d" % Rr, "lp_atk_r%d_gd_d%%d" % Rr, float(d.get("ang", 0.0)))
			_cuts(o, d.get("es", []), 2, HIT_N, true)
			_hit_fx(o, R, p, d.get("es", []), 4, 2, 140.0, 0.65, o.pos + Vector2(0, -12))
		"ll_spread":   # 断喝·传染：死亡处符印炸开 + 细虚线连到新被封印的
			var at: Vector2 = d.at
			_stay(o, "spread_up", at, "up", {"gy": at.y + 1.0})
			for q in d.get("to", []):
				_rt.append({"k": "chain", "a": at + Vector2(0, -12), "b": (q as Vector2) + Vector2(0, -12), "t0": g.t})
				CUE.push(r, o, {"p": q, "shape": "ring", "r": 26.0, "r0": 6.0, "c": LP[5], "n": 5, "life": 0.35})   # 传染：新被封印的先亮一圈（docs/310 §4.2，只画）
			CUE.push(r, o, {"p": at, "shape": "ring", "r": 110.0, "r0": 20.0, "c": LP[4], "n": 10, "life": 0.4})
			R._light(o, at + Vector2(0, -10), 130.0, 0.6, 0.12, p.light)
		"ll_whit":   # 剑气 / 狼首弹命中：一枚四角星（跟被打的那只）
			var e: Dictionary = d.e
			if _beat_n(o, "wh") >= WHIT_BEAT:
				return
			r._push({"lp": "star", "k": "", "life": 0.2, "e": e, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0, "ly": "up", "oid": str(o.id)})
			var wolf: bool = str(d.get("src", "")) == "狼魂"
			if not wolf:   # 剑气命中：斩痕炸开（交叉，跟着那只）
				var wd: Vector2 = ((e.pos as Vector2) - o.pos).normalized() if (e.pos as Vector2) != o.pos else Vector2.RIGHT
				r._push({"lp": "cut", "k": "", "life": 0.2, "e": e, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0,
					"d": wd.orthogonal(), "x": true, "L": 9.0, "ly": "up", "oid": str(o.id)})
			_hit_fx(o, R, p, [e], 1, 1 if wolf else 0, 90.0 if not wolf else 120.0, 0.45 if not wolf else 0.6)
		"ll_link":   # 连携「月牙剑气」：大月牙从起点扫到终点（T 秒），扫完地上留一道斩痕
			_links.append({"oid": str(o.id), "sp": d.sp, "ep": d.ep, "t0": g.t, "T": float(d.T), "d": d.d})
			R._light(o, (d.sp as Vector2).lerp(d.ep, 0.5) + Vector2(0, -10), 160.0, 0.6, 0.15, p.light)
			R._grains(o, (d.sp as Vector2) + Vector2(0, -16), (d.sp as Vector2).y + 2.0, "shard", 6, {"tier": 2}, d.d)


# ================================================================ 绘制

## 地面层：狼魂持续黑烟、贴地件、连携斩痕、后期剑气地面划痕
func draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	if o.pos != Vector2.INF and o.skill_active_left(1) > 0.0:
		r._draw_strip(cv, "lp_s2_aura", r.frame_of(0.0), Pxp._snap(o.pos), false, false)
	for it in r.items_for(id):
		if str(it.ly) == "gd":
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)
	_links_step()
	_rt = _rt.filter(func(q): return g.t - float(q.t0) < 0.62)
	for q in _rt:
		var age: int = r.frame_of(float(q.t0))
		var a: Vector2 = q.a
		var b: Vector2 = q.b
		var n: int = int(a.distance_to(b) / g.PX)
		for i in n:
			var u: float = float(i) / float(maxi(1, n))
			if str(q.k) == "scar":
				if age > 4 and Pxp.Fxr_h(i * 7 + age) < (age - 4) * 0.2:
					continue
				_px(cv, a.lerp(b, u), LP[5] if age < 2 else (LP[3] if age < 5 else LP[2]))
	_qi_scratch(o, cv)
	if not o.hw.is_empty() and o.hw.has("waves"):   # 剑气贴地影子
		for w in o.hw.waves:
			var b: Dictionary = w.b
			if b.get("ll", false) and str(b.get("src", "")) != "狼魂":
				_qi_shadow(cv, "big" if w.get("big", false) else ("twin" if str(b.get("src", "")) == "双生刃" else "far"), r._wpos(w), w.dir)
	var vg = o.get("vg")
	if vg is Dictionary and not vg.is_empty():
		for q in vg.get("qi", []):
			_qi_shadow(cv, "qi", r._wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q), (q.v as Vector2).normalized())


## 上层：封印传染的细虚线
func draw_over(o) -> void:
	for q in _rt:
		if str(q.k) != "chain":
			continue
		var age: int = r.frame_of(float(q.t0))
		if age > 5:   # docs/310 §4.2：0.27 → 0.4 秒、加粗一格
			continue
		var a: Vector2 = q.a
		var b: Vector2 = q.b
		var n: int = int(a.distance_to(b) / g.PX)
		for i in n:
			if (i + age) % 3 == 2:
				continue
			var p: Vector2 = a.lerp(b, float(i) / float(maxi(1, n)))
			_px(o.cv, p, LP[6] if age < 2 else LP[4])
			_px(o.cv, p + Vector2(0, g.PX), LP[4] if age < 2 else LP[3])
			if age == 0 and i % 4 == 0:
				_glow(p, LP[6])


func _links_step() -> void:
	var keep: Array = []
	for lk in _links:
		var age: float = g.t - float(lk.t0)
		if age >= float(lk.T):
			_rt.append({"k": "scar", "a": lk.sp, "b": lk.ep, "t0": g.t})
			continue
		keep.append(lk)
	_links = keep


## 精一起后期剑气：身后地上一道细划痕（从出手点到剑气当前位置）
func _qi_scratch(o, cv) -> void:
	var vg = o.get("vg")
	if not (vg is Dictionary) or vg.is_empty() or r.tier(o) < 1:
		return
	for q in vg.get("qi", []):
		var dv: Vector2 = (q.v as Vector2).normalized()
		var p0: Vector2 = q.get("p0", q.p)
		var L: float = minf(160.0, (q.p as Vector2).distance_to(p0))
		var s := 10.0
		while s < L:
			_px(cv, (q.p as Vector2) - dv * (L - s), LP[3] if L - s < 30.0 else LP[2])
			s += g.PX


## 排序项：剑气（细针 / 狼首弹 / 大剑气）、后期剑气、连携月牙
func sort_items(o, out: Array) -> void:
	if not o.hw.is_empty() and o.hw.has("waves"):
		for w in o.hw.waves:
			if not (w.b as Dictionary).get("ll", false):
				continue
			var gp: Vector2 = r._wpos(w)
			out.append({"lp": "wave", "w": w, "gp": gp, "skey": gp.y + 1.0, "t": r.tier(o)})
	var vg = o.get("vg")
	if vg is Dictionary and not vg.is_empty():
		for q in vg.get("qi", []):
			var qp: Vector2 = r._wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q)
			out.append({"lp": "qi", "q": q, "gp": qp, "skey": qp.y + 1.0, "t": r.tier(o)})
	for lk in _links:
		if str(lk.oid) != str(o.id):
			continue
		var u: float = clampf((g.t - float(lk.t0)) / float(lk.T), 0.0, 1.0)
		var tk: float = floor(u * float(lk.T) * 15.0) / maxf(0.001, float(lk.T) * 15.0)   # 15 fps 节拍跳格
		var lp: Vector2 = Pxp._snap((lk.sp as Vector2).lerp(lk.ep, tk))
		out.append({"lp": "link", "d": lk.d, "gp": lp, "skey": lp.y + 1.0})


func draw_rt(ci, it: Dictionary) -> void:
	match str(it.lp):
		"cut":
			_draw_cut(ci, it)
		"star":
			var f: int = r.frame_of(float(it.t0))
			if f < 0 or f > 2:
				return
			var c0: Vector2 = Pxp._snap(r._gp(it))
			var L: int = [4, 3, 2][f]
			for s in range(-L, L + 1):
				var c: Color = LP[6] if absi(s) < 2 else LP[4]
				_px(ci, c0 + Vector2(s * g.PX, 0), c)
				_px(ci, c0 + Vector2(0, s * g.PX), c)
			if f == 0:
				_glow(c0, LP[6])
		"wave":
			_draw_wave(ci, it)
		"qi":
			var q: Dictionary = it.q
			var dv: Vector2 = (q.v as Vector2).normalized()
			_qi(ci, "qi", it.gp, dv, 0)
			if int(it.t) >= 2:   # 精二：旁边一道晚半拍的小回声
				r._draw_strip(ci, "lp_qi_qi_d%d" % int(Pxp.pick_dir(dv.angle())[0]), r.frame_of(0.0), Pxp._snap((it.gp as Vector2) - dv * 12.0 + dv.orthogonal() * 8.0), Pxp.pick_dir(dv.angle())[1], false, Color(1, 1, 1, 0.5))
		"link":
			var dk: Array = Pxp.pick_dir((it.d as Vector2).angle())
			r._draw_strip(ci, "lp_link_d%d" % int(dk[0]), 0, it.gp, dk[1], false)
			r._draw_strip(ci, "lp_link_d%d" % int(dk[0]), 0, Pxp._snap((it.gp as Vector2) - (it.d as Vector2) * 26.0), dk[1], false, Color(1, 1, 1, 0.4), false)


## 剑气：领主远掷 / 双生刃 = 细针；狼魂 = 狼首弹（帧条）+ 细尾，精二沿途掉菱形晶片；日晷·反斩 = 大剑气（两道平行细针 + 宽芯）
func _draw_wave(ci, it: Dictionary) -> void:
	var w: Dictionary = it.w
	var b: Dictionary = w.b
	var dv: Vector2 = w.dir
	var gp: Vector2 = it.gp
	var hd: Vector2 = gp + Vector2(0, -16)
	var src: String = str(b.get("src", ""))
	var fade: Color = Color(1, 1, 1, clampf((float(w.max) - float(w.dist)) / 30.0, 0.35, 1.0))
	if src == "狼魂":
		var t: int = maxi(1, int(it.t))
		var dk: Array = Pxp.pick_dir(dv.angle())
		_needle(ci, hd - dv * 8.0 * g.PX, dv, 14, 1, false)
		r._draw_strip(ci, "lp_wolf_e%d_d%d" % [t, int(dk[0])], r.frame_of(0.0), gp, dk[1], false, fade)
		if t >= 2:
			var sp: float = float(b.get("speed", 500.0))
			var trav: float = float(w.dist)
			var k := 0
			while k * 24.0 + 12.0 < trav:
				var sk: float = k * 24.0 + 12.0
				var age: float = (trav - sk) / sp * 15.0
				if age <= 7.0:
					var q: Vector2 = (w.p0 if w.has("p0") else gp - dv * trav) + dv * sk + Vector2((Pxp.Fxr_h(k + 31) - 0.5) * 10.0, -16.0 + age * 2.2)
					for pc in [[0, -1, WOLF[5]], [0, 0, WOLF[4]], [-1, 0, WOLF[3]], [1, 0, WOLF[3]], [0, 1, WOLF[3]]]:
						_px(ci, q + Vector2(pc[0], pc[1]) * g.PX, pc[2])
				k += 1
		return
	_qi(ci, "big" if w.get("big", false) else ("twin" if src == "双生刃" else "far"), gp, dv, 0, fade)   # 11-05 用户「远掷应该是剑气」：月牙剑气贴地飞 + 残光
	if w.has("hm"):   # 追猎：被盯上的那只四角各一点淡紫
		var tg = w.get("tg", {})
		if tg is Dictionary and not tg.is_empty() and not tg.get("dead", true):
			var c0: Vector2 = Pxp._snap((tg.pos as Vector2) + Vector2(0, -float(tg.r) * 0.55))
			var h: float = float(tg.r) * 0.7 + 4.0
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_px(ci, c0 + Vector2(sx * h, sy * h * 0.8), LP[4])


## 月牙剑气（帧条 lp_qi_<档>_d*，贴地低飞）+ 身后两道残光（7 / 14 世界像素后、透明 0.45 / 0.22；出手头两拍逐道出现）
func _qi(ci, kind: String, gp: Vector2, dv: Vector2, _age: int, mod := Color.WHITE) -> void:
	var dk: Array = Pxp.pick_dir(dv.angle())
	var k: String = "lp_qi_%s_d%d" % [kind, int(dk[0])]
	var gap: float = 10.0 if kind == "big" else 7.0
	for gi in [2, 1]:
		r._draw_strip(ci, k, r.frame_of(0.0), Pxp._snap(gp - dv * gap * gi), dk[1], false, Color(1, 1, 1, (0.22 if gi == 2 else 0.45) * mod.a), false)
	r._draw_strip(ci, k, r.frame_of(0.0), gp, dk[1], false, mod)


## 剑气贴地影子（地面层）
func _qi_shadow(cv, kind: String, gp: Vector2, dv: Vector2) -> void:
	var dk: Array = Pxp.pick_dir(dv.angle())
	r._draw_strip(cv, "lp_qish_%s_d%d" % [kind, int(dk[0])], 0, gp, dk[1], false)


## 同 pxplane_lappland_art.needle()：头 2 格白热，后面渐暗收尖；big = 两侧再各一道平行细针
func _needle(ci, hd: Vector2, dv: Vector2, L: int, wd: int, big: bool, tint := Color(0, 0, 0, 0)) -> void:
	var nv: Vector2 = dv.orthogonal()
	var px: float = g.PX
	for s in L:
		var u: float = float(s) / float(L)
		var c: Color = LP[6] if s < 2 else (LP[5] if u < 0.35 else (LP[4] if u < 0.65 else LP[3]))
		if tint.a > 0.0:
			c = tint
		var p: Vector2 = hd - dv * float(s) * px
		_px(ci, p, c)
		if s < 2 and tint.a <= 0.0:
			_glow(p, LP[6])
		if u < 0.45 and s >= 1:
			_px(ci, p + nv * px, LP[4] if u < 0.25 else LP[3])
			if wd >= 2:
				_px(ci, p - nv * px, LP[3])
	if big:
		for side in [-3.0, 3.0]:
			for s in range(1, int(L * 0.7)):
				var p2: Vector2 = hd - dv * float(s) * px + nv * side * px
				_px(ci, p2, LP[5] if s < 3 else LP[3])
				if s < 2:
					_glow(p2, LP[6])


## 同 pxplane_lappland_art.cut_px()
func _draw_cut(ci, it: Dictionary) -> void:
	var f: int = r.frame_of(float(it.t0))
	if f < 0 or f > 2:
		return
	var px: float = g.PX
	var c0: Vector2 = Pxp._snap(r._gp(it))
	var dirs: Array = [it.d]
	if it.x:
		dirs.append((it.d as Vector2).rotated(1.25))
	var core: Color = LP[6] if f == 0 else LP[5]
	var side: Color = LP[4] if f == 0 else LP[3]
	var lk: float = Pxp.MI.lit_k(g)
	var m: int = int(float(it.L) * [1.0, 0.8, 0.5][f] * (1.0 + (lk - 1.0) * 0.6))
	for d in dirs:
		var dv: Vector2 = d
		var nv := Vector2(-dv.y, dv.x)
		for i in range(-m, m + 1):
			if f == 2 and absi(i) < m - 2:
				continue
			var wq: float = 1.0 - absf(float(i)) / float(m + 1)
			var p: Vector2 = c0 + Vector2(roundf(dv.x * i), roundf(dv.y * i)) * px
			ci.draw_rect(Rect2(p, Vector2(px, px)), core if wq > 0.25 else side)
			if f == 0 and wq > 0.55:
				ci.draw_rect(Rect2(p + Vector2(roundf(nv.x), roundf(nv.y)) * px, Vector2(px, px)), side)
			if f == 0 and wq > 0.4 and (i & 1) == 0:
				_glow(p, LP[6])


# ================================================================ 状态提示（ob_summon.sm_draw_over 转来，接管时代替灰叉 / 银圈）

## 封招叉（同 pxplane_lappland_art.cross_px；11-05 用户「封印原作的表现形式就是一个叉，用叉就行」）：照原作 buff_silence 的 chenmo_02——
## 深灰实心粗笔画（3 像素宽）+ 1 像素浅灰描边的方正 X。只给精英 / Boss 画（普通怪不画，免得满屏）。
## 第 0–1 拍左上→右下一笔划出、第 1–2 拍右上→左下第二笔，第 2–3 拍整叉闪白（进发光层），之后保持，最后 0.3 秒淡出。
## 起拍记在本模块的 _seal_st（[封印止时刻, 起拍时刻]，止时刻变了 = 新的一次封印，重来一遍划出）
func draw_seal(cv, e: Dictionary, lift: float) -> void:
	if not (e.get("elite", false) or e.get("boss", false)):
		return
	var eid: int = int(e.get("id", 0))
	var st = _seal_st.get(eid)
	if not (st is Array) or not is_equal_approx(float(st[0]), float(e.seal_t)):
		st = [float(e.seal_t), g.t]
		_seal_st[eid] = st
		if _seal_st.size() > 256:
			for k in _seal_st.keys():
				if float(_seal_st[k][0]) < g.t:
					_seal_st.erase(k)
	var age: int = r.frame_of(float(st[1]))
	var al: float = clampf((float(e.seal_t) - g.t) / 0.3, 0.0, 1.0)
	var n: int = CROSS_N
	var a_len: int = 0 if age < 1 else n + 1          # 第一笔（第 0 拍先划到叉心）
	var b_len: int = n + 1 if age >= 2 else (0 if age >= 1 else -n - 1)
	var core := {}
	for i in range(-n, n + 2):   # 叉心在 (0.5, 0.5)：上下左右对称   # 实心粗笔画 3 像素宽（11-05 用户「叉可以是实心的」；左右镜像，叉心在 x = 0.5）
		if i <= a_len:
			for dx in [-1, 0, 1]:
				core[Vector2i(i + dx, i)] = true
		if i <= b_len:
			for dx in [-1, 0, 1]:
				core[Vector2i(1 - i + dx, i)] = true
	var flash: bool = age >= 2 and age < 4
	var c0: Vector2 = Pxp._snap(e.pos + Vector2(0, -float(e.r) * 2.0 - 20.0 - lift))
	var px: float = g.PX
	var rim := {}
	for q in core:
		for o2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q2: Vector2i = q + o2
			if not core.has(q2):
				rim[q2] = true
	for q in rim:
		var p: Vector2 = c0 + Vector2(q) * px
		cv.draw_rect(Rect2(p, Vector2(px, px)), Color(LP[6] if flash else CROSS_RIM, al))
		if flash:
			_glow(p, LP[6])
	for q in core:
		cv.draw_rect(Rect2(c0 + Vector2(q) * px, Vector2(px, px)), Color(LP[5] if flash else CROSS_CORE, al))


## 观察刻痕（同 pxplane_lappland_art.tally_px）：头顶 n 道斜竖短刻，新叠的那道白热
func draw_tally(cv, e: Dictionary, n: int, fresh: bool) -> void:
	var c0: Vector2 = Pxp._snap(e.pos + Vector2(0, -float(e.r) * 2.0 - 10.0))
	var px: float = g.PX
	for k in n:
		var x0: float = (float(k) - float(n - 1) / 2.0) * 3.0
		var hot: bool = fresh and k == n - 1
		for s in 5:
			var p: Vector2 = c0 + Vector2(roundf(x0 + s * 0.4), -s) * px
			cv.draw_rect(Rect2(p, Vector2(px, px)), LP[6] if hot else (LP[5] if s >= 1 else LP[4]))
			if hot:
				_glow(p, LP[6])
		cv.draw_rect(Rect2(c0 + Vector2(roundf(x0) + 1, 0) * px, Vector2(px, px)), SHADOW)
