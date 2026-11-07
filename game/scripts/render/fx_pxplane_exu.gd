## 能天使转平面（docs/262，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第三批四人并行，少撞 fx_pxplane.gd）。
## 帧条（枪口焰 / 命中火花 / 贴地环 / 光环 / 烟）由 tools/pxplane_bake_exusiai.py 烤（图形 tools/pxplane_exu_art.py），键前缀 ex_；
## 弹体、连携曳光、连锁细线在这里按美术像素格逐格画（算法同 pxplane_exu_art.py 的 bullet() / tracer_line()，改一边要改另一边）。
## 同屏封顶（纯射手、高射速，最常出现的三类件）：弹体每人只画最新 24 颗（额外弹 6 颗）；枪口焰每人同时 1 个（新的顶掉旧的）；
## 命中火花每拍（1/15 秒）至多 3 团（技能弹 4 团）、同时在画至多 8 团；额外弹 / 连锁 / 溅射每拍各至多 3 / 3 / 2；照地光每拍至多 1 盏；弹壳每拍至多 1 颗。
## 挂在人身上的件（枪口焰、过热烟、过载光环）带 fo 跟着她走（docs/246 §11）；命中火花、贴地环留在原地。只画，不碰玩法与玩法随机数。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const ObFx = preload("res://scripts/characters/blocks/ob_fx.gd")
const ObCore = preload("res://scripts/characters/blocks/ob_core.gd")   # aura_members

## 色阶（同 pxplane_exu_art.RAMP）
const RAMP := {
	"n": ["#2a100c", "#5c2418", "#a8402a", "#f07048", "#ffa880", "#ffe0cc", "#ffffff"],
	"s1": ["#08202a", "#0f4458", "#1b7f9e", "#38c0e0", "#8fe6f5", "#d6f8ff", "#ffffff"],
	"s2": ["#2a1406", "#5c2c0a", "#a8520f", "#f08a1e", "#ffbd5a", "#ffe6b0", "#ffffff"],
	"s3": ["#3a140a", "#7a2814", "#d05030", "#ff8050", "#ffb890", "#fff0e0", "#ffffff"],
	"g": ["#2a1c06", "#5c3e0a", "#a8741a", "#e8b030", "#ffd86a", "#fff2c0", "#ffffff"],
	"t1": ["#2a1c10", "#5c3a20", "#a86a40", "#e8a070", "#ffd0a8", "#fff0e0", "#ffffff"],
	"t2": ["#2a1c06", "#5c3e0a", "#a8741a", "#f0c050", "#ffe08a", "#fff6d8", "#ffffff"],
	"t3": ["#2a1c06", "#5c3e0a", "#a8741a", "#e8b030", "#ffd86a", "#fff2c0", "#ffffff"],
}
## 11-05 第四轮（用户「还是以肉鸽的可视化为优先级最高」）：高可读光弹——弹身 B 格（4 宽 + 一圈光晕描边，第五轮加大约 30%）+ 亮尾 T 格（同 pxplane_exu_art）
const B_BODY := {"n": [8, 9, 9], "s1": [10, 10, 10], "s2": [7, 8, 8], "s3": [9, 9, 9], "g": [9, 10, 10], "t1": [8, 9, 9], "t2": [8, 9, 9], "t3": [8, 9, 9], "tr": [10, 10, 10], "x": [5, 5, 5]}
const B_TAIL := {"n": [10, 12, 13], "s1": [13, 14, 14], "s2": [8, 9, 10], "s3": [11, 12, 12], "g": [10, 12, 12], "t1": [11, 12, 13], "t2": [11, 12, 13], "t3": [11, 12, 13], "tr": [18, 18, 18], "x": [6, 6, 6]}
const TIER_MIN := {"n": 0, "s1": 0, "s2": 1, "s3": 2, "g": 1}
const BKIND := {"proj_exusiai_bullet": "n", "proj_exusiai_bullet_s1": "s1", "proj_exusiai_bullet_s2": "s2", "proj_exusiai_bullet_s3": "s3",
	"proj_exusiai_bullet_power": "g", "proj_exusiai_bullet_t1": "t1", "proj_exusiai_bullet_t2": "t2", "proj_exusiai_bullet_t3": "t3"}
const FXMODE := {"fx_exusiai_muzzle": "n", "fx_exusiai_muzzle_s1": "s1", "fx_exusiai_muzzle_s2": "s2", "fx_exusiai_muzzle_s3": "s3", "fx_exusiai_muzzle_gold": "g",
	"fx_exusiai_hit": "n", "fx_exusiai_hit_s1": "s1", "fx_exusiai_hit_s2": "s2", "fx_exusiai_hit_s3": "s3", "fx_exusiai_hit_gold": "g", "fx_exusiai_pierce_gold": "full"}
const BUL_DRAW := 24      # 11-05 第三轮：后期满屏也看得出一串弹雨
const XBUL_DRAW := 6
const HIT_LIVE := 8
const MZ_Y := 35.0        # 枪口在脚底上方约 35（seg_exusiai muzzle [30, -35]）：挂在人身上的件排序时往下补回脚底
const HALO_Y := -72.0     # 队友头顶光环（原数据 off [0, -66] 压在头发上，抬到头顶）

var _parent: WeakRef
var r:   # Owner holds this helper; the backreference must not retain its cache.
	get:
		return _parent.get_ref()
var g
var _cols := {}
var _beat := {}
var _vc := {}      # 每人第几轮射击（枪口火两种变体交替、每 3 轮一缕枪口烟）
var _kick := {}    # 每人最近一次开火的时刻（后坐 1 美术像素，只改画面）


func _init(px) -> void:
	_parent = weakref(px)
	g = px.g


func _c(ramp: String, i: int) -> Color:
	var k: String = ramp + str(i)
	if not _cols.has(k):
		_cols[k] = Color.html(RAMP[ramp][i])
	return _cols[k]


## 这一拍（1/15 秒）某类件已出几个（超过上限就不再加画面）
func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


func _mtier(m: String, t: int) -> int:
	return maxi(t, int(TIER_MIN.get(m, 0)))


func _up(o, k: String, at: Vector2, gy: float, extra := {}) -> void:
	var it := {"k": "ex_" + k, "t0": g.t, "gp": Pxp._snap(at), "gy": gy, "flip": false, "ly": "up", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


func _gd(o, k: String, at: Vector2, t0 := -1.0) -> void:
	r._push({"k": "ex_" + k, "t0": g.t if t0 < 0.0 else t0, "gp": Pxp._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})


## 挂在她身上的件：fo = 相对脚底的偏移（每次绘制按她当前位置重算），sk 把排序补回脚底
func _on_her(o, k: String, at: Vector2, flip := false, tag := "") -> void:
	var it := {"k": "ex_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": flip, "ly": "up", "oid": str(o.id), "fo": at - o.pos, "sk": maxf(0.0, o.pos.y - at.y)}
	if tag != "":
		it[tag] = true
	r._push(it)


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"exu_fire":   # 一轮射击：枪口火（同时 1 个）+ 照地光（每发一盏、每拍至多 2）+ 弹壳（每拍至多 1）
			var mz: Vector2 = d.mz
			var m: String = str(FXMODE.get(str(d.get("fx", "")), "n"))
			var tt: int = _mtier(m, t)
			var dp: Array = Pxp.pick_dir((d.d as Vector2).angle())
			var id: String = str(o.id)
			r.items = r.items.filter(func(it): return not (it.has("mz") and str(it.oid) == id))
			var vc: int = int(_vc.get(id, 0)) + 1
			_vc[id] = vc
			_kick[id] = g.t
			_on_her(o, "mz_%s_e%d_v%d_d%d" % [m, tt, vc % 2, int(dp[0])], mz, bool(dp[1]), "mz")
			if vc % 3 == 0:   # 偶尔一缕枪口烟
				_on_her(o, "smoke_up", mz)
			if _beat_n(o, "fire") < 2:   # 枪口照地：每发都照一下（短而亮，每拍至多 2 盏，走配方灯光预算）
				R._light(o, mz, 90.0 + 12.0 * tt + (20.0 if m != "n" else 0.0), 0.6 + 0.08 * tt, 0.07, p.light)
			if _beat_n(o, "casing") == 0:
				R._grains(o, mz + Vector2(-4.0 * float(o.face), 0), o.pos.y + 2.0, "shard", 2 if d.get("fan", false) else 1, {"tier": 0}, Vector2(-float(o.face), -0.4))   # 弹壳：往后上方抛出、落地弹一下
		"exu_hit":
			var e: Dictionary = d.e
			var at: Vector2 = d.at
			var m2: String = str(FXMODE.get(str(d.get("fx", "")), "n"))
			if d.get("tr", false):   # 曳光弹命中：脚下金色锁定括号
				_gd(o, "mark_gd", e.pos)
			var cap: int = 3 if m2 in ["n", "s2"] else 4
			if m2 == "full":
				cap = 5
			if _fresh_near(o, at) or _beat_n(o, "hit") >= cap or _live(o, "hit") >= HIT_LIVE:
				return   # 同一只身上 2 拍内只留一团（过载 4 连射 / 扫射不叠成一团白）
			var hd: Array = Pxp.pick_dir((d.get("v", e.pos - o.pos) as Vector2).angle())
			var key: String = ("hit_full_d%d" % int(hd[0])) if m2 == "full" else "hit_%s_e%d_d%d" % [m2, _mtier(m2, t), int(hd[0])]
			_up(o, key, at, float(e.pos.y) + 1.0, {"hit": true, "flip": bool(hd[1])})
			if _beat_n(o, "hl") < 2:   # 命中照地：亮度压过受击闪色
				var big: bool = m2 != "n" and m2 != "s2"
				R._light(o, at, (80.0 if big else 65.0) + 12.0 * t, (0.6 if big else 0.5) + 0.08 * t, 0.1, p.light)
			if _beat_n(o, "hg") == 0:   # 命中碎屑（Noita，docs/270 §3）：2–4 颗 4–6 px 金属碎屑往回溅、落地弹一下；每拍只给第一下，不刷屏
				var ng: int = 2 + (1 if t >= 1 else 0) + (1 if m2 != "n" and m2 != "s2" else 0)
				R._grains(o, at, float(e.pos.y) + 2.0, "rock", ng, {"tier": t}, -(d.get("v", Vector2.ZERO) as Vector2).normalized())
		"exu_xhit":   # 后期额外弹 / 跳弹落点：小一号，每拍至多 3 团
			if _beat_n(o, "xh") >= 3 or _live(o, "hit") >= HIT_LIVE:
				return
			var xd: Array = Pxp.pick_dir(((d.e.pos as Vector2) - o.pos).angle())
			_up(o, "hit_x_d%d" % int(xd[0]), d.at, float(d.e.pos.y) + 1.0, {"hit": true, "flip": bool(xd[1])})
		"exu_chain":   # 「连锁」弹射：1 美术像素细线（3 拍）+ 落点小火花；每拍至多 3 道
			if _beat_n(o, "ch") >= 3:
				return
			r._push({"ex": "line", "a": d.a, "b": d.b, "gp": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
			var cd: Array = Pxp.pick_dir(((d.b as Vector2) - (d.a as Vector2)).angle())
			_up(o, "hit_x_d%d" % int(cd[0]), d.b, float(d.get("gy", 0.0)), {"hit": true, "flip": bool(cd[1])})
		"exu_splash":   # 「扩散」溅射：贴地断续红环；每拍至多 2
			if _beat_n(o, "sp") >= 2:
				return
			_gd(o, "ring_splash_gd", d.at)
		"exu_heat":   # 扫射模式结束枪管过热：枪口两缕烟
			_on_her(o, "steam_up", d.mz)
		"exu_bless":   # 天使的祝福：被祝福的队友出手时手边一颗金色小星芒（每拍至多 2）
			if _beat_n(o, "bl") >= 2:
				return
			_up(o, "bless_up", d.at, float(d.gy))
		"exu_link":   # 连携技「穿透扫射」一发：长曳光（3 拍从枪口推到尽头）+ 枪口焰（倾泻金，跟人）+ 前 2 只被穿的敌人按到达时刻各一团火花
			var fp: Vector2 = d.fp
			var tp: Vector2 = d.tp
			var i: int = int(d.i)
			r._push({"ex": "ltr", "a": fp, "b": tp, "gp": fp, "i": i, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": fp.y + 20.0, "oid": str(o.id), "k": ""})
			var dp2: Array = Pxp.pick_dir((tp - fp).angle())
			var id2: String = str(o.id)
			r.items = r.items.filter(func(it): return not (it.has("mz") and str(it.oid) == id2))
			_kick[id2] = g.t
			_on_her(o, "mz_g_e2_v%d_d%d" % [i % 2, int(dp2[0])], fp, bool(dp2[1]), "mz")
			var L: float = maxf(1.0, fp.distance_to(tp))
			var es: Array = d.get("es", [])
			for k in mini(2, es.size()):
				var e2: Dictionary = es[k]
				var hp: Vector2 = e2.pos + Vector2(0, -float(e2.r) * 0.55)
				r._push({"k": "ex_hit_%s_e2_d%d" % ["n" if i % 2 == 0 else "g", int(dp2[0])], "t0": g.t + 0.2 * clampf(fp.distance_to(hp) / L, 0.0, 1.0), "gp": Pxp._snap(hp), "gy": float(e2.pos.y) + 1.0, "flip": bool(dp2[1]), "ly": "up", "oid": str(o.id), "hit": true})
			if i % 2 == 0:
				R._light(o, fp, 90.0, 0.45, 0.1, p.light)
		"shape":   # 「跳弹·碎裂」击杀处弹片：贴地金色弹片环
			if d.get("circle", false) and str(d.get("src", "")) == "弹片":
				if _beat_n(o, "fr") >= 2:
					return
				_gd(o, "ring_frag_gd", d.get("c", o.pos))
				R._grains(o, d.get("c", o.pos) + Vector2(0, -10), float((d.get("c", o.pos) as Vector2).y) + 2.0, "shard", 3, {"tier": t})
		"skill":
			var si: int = int(d.get("i", -1))
			var foot: Vector2 = o.pos
			if si == 0:   # 冲锋模式装填：脚下一圈冰青断续环
				_gd(o, "ring_s1_gd", foot)
				R._light(o, foot + Vector2(0, -20), 110.0, 0.45, 0.12, Color(0.55, 0.9, 1.0))
			elif si == 1:   # 扫射模式：照地一下（持续期间枪管发红由状态件画）
				R._light(o, foot + Vector2(0, -30), 90.0, 0.4, 0.12, Color(1.0, 0.65, 0.3))
			elif si == 2:   # 过载模式：脚下大环 + 头顶光环亮起（持续期间常驻，状态件）
				_gd(o, "ring_s3_gd", foot)
				_on_her(o, "halo_fire_up", foot + Vector2(0, -80))
				R._light(o, foot + Vector2(0, -40), 160.0, 0.7, 0.15, p.light)
				R._grains(o, foot + Vector2(0, -70), foot.y, "shard", 5, {"tier": 2})


func _fresh_near(o, at: Vector2) -> bool:
	var id: String = str(o.id)
	for it in r.items:
		if it.has("hit") and str(it.oid) == id and g.t - float(it.t0) < 2.0 / 15.0 and (it.gp as Vector2).distance_to(at) < 10.0:
			return true
	return false


func _live(o, tag: String) -> int:
	var n := 0
	var id: String = str(o.id)
	for it in r.items:
		if it.has(tag) and str(it.oid) == id:
			n += 1
	return n


# ================================================================ 绘制

func draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	for it in r.items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)


## 立起层的状态件（每帧生成）：弹体、额外弹、过载光环、队友头顶光环、扫射期间枪管发红
func sort_items(o, out: Array) -> void:
	var st = o.get("ext")
	if st is Dictionary and st.has("bul"):
		var bs: Array = st.bul
		for i in range(maxi(0, bs.size() - BUL_DRAW), bs.size()):
			var bu: Dictionary = bs[i]
			out.append({"ex": "bul", "b": bu, "o": o, "gy": (bu.p as Vector2).y + 20.0, "n": i})
	var vg = o.get("vg")
	if vg is Dictionary and not vg.is_empty():
		var xs: Array = vg.get("bul", [])
		for i in range(maxi(0, xs.size() - XBUL_DRAW), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"ex": "xbul", "b": xb, "o": o, "gy": (xb.p as Vector2).y + 1.0})
	if o.pos == Vector2.INF:
		return
	if o.skill_active_left(2) > 0.0:
		out.append({"ex": "loop", "k": "ex_halo_s3_up", "gp": Pxp._snap(o.pos + Vector2(0, -80)), "gy": o.pos.y + 1.0})
	if o.skill_active_left(1) > 0.0:
		out.append({"ex": "barrel", "o": o, "gy": o.pos.y + 1.0})
	_halos(o, out)


## 天使的祝福（精二）：原数据的头顶光环帧条（fx_exusiai_halo，hold）接管时改画这里——受益队友头顶一圈像素椭圆环（一点亮光绕环走），她开火时一亮
func _halos(o, out: Array) -> void:
	var fxb = o.get("_fxb")
	if not (fxb is Dictionary):
		return
	var el = o.get("el")
	var fire_t: float = float(el.get("fire_t", -99.0)) if el is Dictionary else -99.0
	for u in fxb:
		var e: Dictionary = fxb[u]
		for f in e.b.get("fx", []):
			if not (f is Dictionary) or str(f.get("strip", "")) != "fx_exusiai_halo" or not ObFx.fx_on(o, f):
				continue
			if ObFx.fx_hold_alpha(f, e) < 0.5:
				continue
			for m in ObCore.aura_members(o, str(e.b.get("scope", "others"))):
				if m.pos == Vector2.INF:
					continue
				var hp: Vector2 = Pxp._snap(m.pos + Vector2(0, HALO_Y))
				out.append({"ex": "loop", "k": "ex_halo_up", "gp": hp, "gy": m.pos.y + 1.0})
				if g.t - fire_t < 0.2:
					out.append({"ex": "once", "k": "ex_halo_fire_up", "t0": fire_t, "gp": hp, "gy": m.pos.y + 1.5})


func draw_rt(ci, it: Dictionary) -> void:
	var renderer = r
	match str(it.ex):
		"loop":
			renderer._draw_strip(ci, str(it.k), renderer.frame_of(0.0), it.gp, false, false)
		"once":
			renderer._draw_strip(ci, str(it.k), renderer.frame_of(float(it.t0)), it.gp, false, true)
		"bul":
			var bu: Dictionary = it.b
			var kind: String = str(BKIND.get(str(bu.get("tex", "")), "n"))
			var tr: bool = not (bu.get("tr", {}) as Dictionary).is_empty()
			var back: float = float(int(it.n) % 4) * 3.0 if kind == "g" else 0.0   # 倾泻 8 发同一帧出膛：画面上按序号前后错开（只画），不成一排梳子
			if float(bu.get("stn", 0.0)) > 0.0:   # docs/298 B′ 眩晕弹（11-07 用户「颜色可以更加有对比感」）：单颗粗圆头大弹，深红芯 + 亮金边 + 一段暗红残光
				_stun_bullet(ci, bu.p, bu.v)
				return
			_bullet(ci, bu.p, bu.v, kind, renderer.tier(it.o), not bu.get("ric", true), tr, back)
		"xbul":
			var xb: Dictionary = it.b
			_bullet(ci, (xb.p as Vector2) + Vector2(0, -18.0), xb.v, "n", renderer.tier(it.o), true, false)
		"barrel":   # 扫射期间枪口发红：2×2 美术像素琥珀，按拍明暗
			var o = it.o
			var mz: Vector2 = o.pos + Vector2(30.0 * float(o.face), -MZ_Y)
			var hot: bool = int(floor(g.t * 15.0)) % 2 == 0
			for q in [Vector2.ZERO, Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)]:
				renderer._px(ci, mz + q, _c("s2", 4 if hot else 3))
			renderer._glow(mz, _c("s2", 5))
		"line":
			var f: int = renderer.frame_of(float(it.t0))
			if f < 0 or f > 2:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / g.PX))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f == 2 and u < 0.5:
					continue
				renderer._px(ci, a.lerp(b, u), _c("n", 5 if f == 0 else 4) if i % 2 == 0 else _c("g", 5 if f == 0 else 4))
				if f == 0 and i % 4 == 0:
					renderer._glow(a.lerp(b, u), _c("g", 6))
		"ltr":   # 连携曳光（同 pxplane_exu_art.tracer_line）
			var f2: int = renderer.frame_of(float(it.t0))
			if f2 < 0 or f2 > 2:
				return
			var a2: Vector2 = it.a
			var b2: Vector2 = it.b
			var dv: Vector2 = (b2 - a2).normalized()
			var nv := Vector2(-dv.y, dv.x)
			var L: float = a2.distance_to(b2) / g.PX
			var i2: int = int(it.i)
			var rp: String = "n" if i2 % 2 == 0 else "g"
			var head: float = L * float(f2 + 1) / 3.0
			for s in int(head):
				var q: Vector2 = a2 + dv * float(s) * g.PX
				if float(s) > head - 18.0:
					var u2: float = (head - float(s)) / 18.0
					renderer._px(ci, q, _c(rp, 6 if u2 < 0.12 else (5 if u2 < 0.4 else 4)))
					if u2 < 0.4:
						renderer._px(ci, q - nv * g.PX, _c(rp, 4))
					if u2 < 0.12:
						renderer._glow(q, _c(rp, 6))
				elif f2 < 2 and _hsh(s, i2, 1) % 3 != 0:
					renderer._px(ci, q, _c(rp, 2))


static func _hsh(x: int, y: int, k: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF


## 光弹像素表（同 pxplane_exu_art.bullet_px）：按弹道坐标扫像素格分类，任意方向不漏洞；按 32 个方向缓存。项 = [x, y, 色阶序号（-1 = 描边）, 是否进发光层]
var _bpx := {}

func _bul_px(key: String, t: int, small: bool, ai: int) -> Array:
	var ck: String = "%s|%d|%d|%d" % [key, t, 1 if small else 0, ai]
	if _bpx.has(ck):
		return _bpx[ck]
	var ang: float = float(ai) * TAU / 32.0
	var dx: float = cos(ang)
	var dy: float = sin(ang)
	var B: int = int(B_BODY[key][t])
	var T: int = int(B_TAIL[key][t])
	var wide: int = 2 if not small else 1   # 11-05 第五轮：精零 / 精一也 4 宽
	var c0: float = -1.5
	var c1: float = 1.5 + float(wide - 1)
	var R: int = B + T + 4
	var out: Array = []
	for y in range(-R, R + 1):
		for x in range(-R, R + 1):
			var av: float = -(float(x) * dx + float(y) * dy)
			var cv: float = float(x) * -dy + float(y) * dx
			var e: bool = av < 0.5 or av > float(B) - 1.5
			var lo: float = c0 + 1.0 if e else c0
			var hi: float = c1 - 1.0 if e else c1
			if av >= -0.5 and av <= float(B) - 0.5 and cv >= lo and cv <= hi:
				var white: bool = absf(cv - float(wide - 1) * 0.5) < 0.5 + float(wide - 1) * 0.5 and not (e and av > float(B) - 1.5)
				out.append([x, y, 6 if white else 5, white])
			elif not small and av >= -1.5 and av <= float(B) and cv >= lo - 1.0 and cv <= hi + 1.0 and not (av > float(B) - 0.5 and absf(cv) < 0.5):
				out.append([x, y, -1, false])
			elif av > float(B) - 0.5 and av <= float(B + T) - 0.5:
				var j: float = av - float(B)
				var u: float = j / float(maxi(1, T))
				if absf(cv) < 0.5:
					out.append([x, y, 5 if u < 0.3 else (4 if u < 0.65 else 3), false])
				elif j < 2.5 and absf(cv) < 1.5 and not small:
					out.append([x, y, 4 if j < 1.5 else 3, false])
	_bpx[ck] = out
	return out


## 一颗光弹（同 pxplane_exu_art.bullet，肉鸽式高可读弹）：弹身中线白芯 + 两侧亮色（4 宽）+ 一圈光晕描边（精一起金色）、两头圆钝，
## 芯进发光层；亮尾前 3 格 3 宽、之后 1 宽渐暗；精二弹头两侧按拍闪金点；额外弹小一号无描边。back = 只画面的后移（美术像素）
func _bullet(ci, pos: Vector2, vel: Vector2, kind: String, t: int, small: bool, tracer: bool, back := 0.0) -> void:
	var rp: String = "g" if tracer else kind
	var key: String = "tr" if tracer else ("x" if small else kind)
	var ai: int = posmod(int(round(vel.angle() / TAU * 32.0)), 32)
	var d: Vector2 = Vector2.from_angle(float(ai) * TAU / 32.0)
	var px: float = g.PX
	var head: Vector2 = Pxp._snap(pos) - (d * back).round() * px
	var rim: Color = _c("g", 4) if (t >= 1 and not small and not tracer) else _c(rp, 3)
	for q in _bul_px(key, t, small, ai):
		var at: Vector2 = head + Vector2(float(q[0]), float(q[1])) * px
		var k: int = int(q[2])
		ci.draw_rect(Rect2(at, Vector2(px, px)), rim if k < 0 else _c(rp, k))
		if q[3]:
			r._glow(at, _c(rp, 6))
	if t >= 2 and not small and int(floor(g.t * 15.0)) % 2 == 0:
		var nv := Vector2(-d.y, d.x)
		r._px(ci, head - d * px - nv * px * 4.0, _c("g", 6))
		r._px(ci, head - d * px * 2.0 + nv * px * 5.0, _c("g", 5))

## 眩晕弹（docs/298 B′，只画）：按美术像素格逐格判形——弹头半径 4 格的圆 + 身长 9 格、半宽 3.3 格（总宽约普通弹 2 倍），
## 最外 1 格亮金边、往里深红、芯部亮红、弹头前缘一点暖白；身后 12 格红残光逐渐收窄变暗、远端隔格抖动；弹头一圈红光 + 金光
const STN_RIM := Color("#ffd040")
const STN_RIM_D := Color("#6a1a08")
const STN_BODY := Color("#c8102a")
const STN_CORE := Color("#ff4a30")
const STN_HOT := Color("#fff0c0")
const STN_TR := [Color("#ff3a2a"), Color("#c8142a"), Color("#7a0c1c")]

func _stun_bullet(ci, pos: Vector2, vel: Vector2) -> void:
	var px: float = g.PX
	var ai: int = posmod(int(round(vel.angle() / TAU * 32.0)), 32)
	var d: Vector2 = Vector2.from_angle(float(ai) * TAU / 32.0)
	var nv := Vector2(-d.y, d.x)
	var head: Vector2 = Pxp._snap(pos)
	var fl: int = int(floor(g.t * 15.0)) % 2
	for ix in range(-22, 23):
		for iy in range(-22, 23):
			var q := Vector2(float(ix), float(iy))
			var u: float = q.dot(d)
			var w: float = absf(q.dot(nv))
			var dep: float = -1.0
			if u >= -1.0:
				dep = 4.0 - q.length() if u > 0.0 else maxf(4.0 - q.length(), 3.3 - w)
			elif u >= -9.0:
				dep = 3.3 - w
			var at: Vector2 = head + q * px
			if dep >= 0.0:
				var c: Color = STN_RIM if dep < 1.0 else (STN_BODY if dep < 1.9 else STN_CORE)
				if u > 1.0 and dep >= 1.0 and w < 1.6:
					c = STN_HOT
				ci.draw_rect(Rect2(at, Vector2(px, px)), c)
			elif dep >= -1.0 and u < -1.0 and u >= -9.0:
				ci.draw_rect(Rect2(at, Vector2(px, px)), STN_RIM_D)
			elif u < -9.0 and u >= -21.0:
				var k: float = (-9.0 - u) / 12.0
				if w <= 2.8 * (1.0 - k) + 0.4:
					if k > 0.5 and (ix + iy + fl) % 2 == 0:
						continue
					ci.draw_rect(Rect2(at, Vector2(px, px)), STN_TR[mini(2, int(k * 3.0))])
	r._glow(head, STN_CORE)
	r._glow(head + d * px * 2.0, STN_RIM)


## 后坐（只改画面，character.draw_body 读）：开火那一拍本体往枪口反方向挪 1 美术像素
func kick(o) -> Vector2:
	if g.t - float(_kick.get(str(o.id), -99.0)) < 1.0 / 15.0:
		return Vector2(-float(o.face) * g.PX, 0.0)
	return Vector2.ZERO
