## 铃兰转平面（docs/271，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第五批四人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_suzuran.py 烤（图形 tools/pxplane_suzuran_art.py），键前缀 sz_；
## 狐火弹、光域边、传火线、连携狐火在这里按美术像素格逐格画（算法同 pxplane_suzuran_art.py 的 fox_bolt() / aura_ring() / pass_line()，改一边要改另一边）。
## 只画：读玩法状态（o.hw.sz、g.bullets 里她的狐火），画面专用键只写 _pxv（狐火弹是不是全力以赴那一发，玩法不读）；不碰玩法与玩法随机数。
## 挂在人身上的件带 fo（跟她：符阵、火柱、尾焰、九尾）或 fol（跟队长：祝福）；命中 / 落点 / 火环留在原地；金印 / 灼印 / 附着火跟着那只敌人。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")

const F := [Color("#2e2618"), Color("#5e4e34"), Color("#9a8058"), Color("#ccae78"), Color("#e8d4a8"), Color("#fbf1d8"), Color("#ffffff")]   # 淡米金：取色 PRTS 立绘尾巴 / 头发（docs/271 §1）
const P := [Color("#2e2a24"), Color("#5a5448"), Color("#9a9282"), Color("#d8d0c0"), Color("#fffaf0")]
const SQ := 0.72
const S2_R := [68, 80, 92, 104]
const S3_R := [94, 110, 126, 142]
const PRAY_R := [40, 48, 56, 64]
const HB_R := [52, 60, 68]
const HEAL_LIGHT := Color(0.6, 1.0, 0.75)
const HIT_BEAT := 4        # 每拍至多画几处狐火命中
const LINK_T1 := 0.35      # 同 skill_link l_suzuran：绕身一圈
const LINK_T2 := 0.25      # 追向敌人

var _parent: WeakRef
var r:   # Owner holds this helper; the backreference must not retain its cache.
	get:
		return _parent.get_ref()
var g
var _beat := {}
var _last := {}      # 限频：上一次挂命中灯的时刻
var _seg = null
var _ring_key := ""
var _ring_px: Array = []
var _rt: Array = []        # 运行时件：传火线 {pass, a, b, t0}、连携 {link, o, ts, t0, hist}
var _pend: Array = []      # 延后的画面（狐火落点：落下 3 拍后才炸开照地）


func _init(px) -> void:
	_parent = weakref(px)
	g = px.g


func _sz():
	if _seg == null:
		_seg = load("res://scripts/characters/blocks/seg_suzuran.gd")   # 运行时取（避免和积木链循环 preload）
	return _seg


func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


## 不超过判定 × 1.1 的最大一档（都超就取最小档）
static func _fit(arr: Array, v: float) -> int:
	var best: int = int(arr[0])
	for x in arr:
		if float(x) <= v * 1.1 and int(x) > best:
			best = int(x)
	return best


func _up(o, k: String, at: Vector2, gy: float, extra := {}) -> void:
	var it := {"k": "sz_" + k, "t0": g.t, "gp": Pxp._snap(at), "gy": gy, "flip": false, "ly": "up", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


func _gd(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "sz_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 挂在她身上的件：fo = 相对脚底的偏移（每次绘制按她当前位置重算）；sk = 排序偏移（后半圈 −3、前半圈 +1）
func _on_her(o, k: String, ly: String, off := Vector2.ZERO, sk := 1.0, flip := false) -> void:
	r._push({"k": "sz_" + k, "t0": g.t, "gp": Pxp._snap(o.pos + off), "flip": flip, "ly": ly, "oid": str(o.id), "fo": off, "gyo": sk - off.y})


func _on_lead(o, k: String, ly: String) -> void:
	r._push({"k": "sz_" + k, "t0": g.t, "gp": Pxp._snap(g.ppos), "flip": false, "ly": ly, "oid": str(o.id), "fol": Vector2.ZERO, "sk": 1.0})


## 命中：小火苗 + 小火环每处都画；照地灯与颗粒按时间限频（docs/270 §3 上限：普攻一簇灯 ≤ 2、颗粒 ≤ 12，爆发灯 ≤ 3）——
## 精二大狐火一次贯穿一串、全力以赴五发同时到，GCP 体检（render-suzuran-1105b）一簇灯 6 盏、颗粒 18–21 颗，超上限
func _pop(o, R, p: Dictionary, e: Dictionary, li: float, gn: int) -> void:
	var ep: Vector2 = e.pos
	_up(o, "hit_up", ep, ep.y + 1.0)
	_gd(o, "hit_gd", ep)
	var lit: bool = g.t - float(_last.get("hl", -9.0)) >= 0.12
	if lit:
		_last["hl"] = g.t
		R._light(o, ep + Vector2(0, -12), 90.0, li, 0.12, p.light)
	R._grains(o, ep + Vector2(0, -12), ep.y + 2.0, "flame", gn if lit else 1, {})


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"sz_fire":   # 出手：全力以赴那一发标 _pxv（画大一号的狐火）；精一杖头火柱、精二九尾张开
			var volley: bool = d.get("volley", false)
			for b in d.get("bs", []):
				b["_pxv"] = volley
				if volley:   # 11-05：五发出手时错开成扇形（画面上沿各自出射方向先推出去，0.3 秒内并回真实位置）
					b["_pxf"] = [g.t, (b.vel as Vector2).normalized()]
			if volley:
				var tip: Vector2 = d.get("tip", o.pos)
				if t >= 1:
					_on_her(o, "s1col_up", "up", tip - o.pos, 2.0)
				if t >= 2:
					_on_her(o, "tails_flare", "up", Vector2.ZERO, -2.0, o.face < 0.0)
				R._light(o, tip, 100.0, 0.55, 0.12, p.light)
		"sz_big":   # 三火归一：大狐火离手
			var fp: Vector2 = d.get("from", o.pos)
			R._light(o, fp, 120.0, 0.6, 0.12, p.light)
			R._grains(o, fp, o.pos.y + 2.0, "flame", 3, {})
		"sz_hit":   # 狐火命中（weapons.bullet_hit arcane）：小火苗炸开 + 贴地小火环；全力以赴那一发多盖一枚金印
			if _beat_n(o, "hit") >= HIT_BEAT:
				return
			var e: Dictionary = d.e
			var b: Dictionary = d.get("b", {})
			if b.get("_pxv", false):
				_gd(o, "stamp_gd", e.pos)
				_pop(o, R, p, e, 0.62, 4)
			else:
				_pop(o, R, p, e, 0.5, 3)
		"sz_bhit":   # 大狐火贯穿：每只一下
			if _beat_n(o, "bhit") >= 3:
				return
			_pop(o, R, p, d.e, 0.55, 3)
		"sz_att":   # 狐火点点每跳：被附着那只脚下一圈暗火环
			if _beat_n(o, "att") >= 1:
				return
			var c: Vector2 = d.c
			_gd(o, "att_gd", c)
			R._light(o, c + Vector2(0, -10), 70.0, 0.4, 0.1, p.light)
			R._grains(o, c + Vector2(0, -12), c.y + 2.0, "flame", 1, {})
		"sz_pass":   # 传火：两只之间一道往上拱的金线
			if _rt.size() < 24:
				_rt.append({"pass": true, "a": d.a, "b": d.b, "t0": g.t, "oid": str(o.id)})
		"sz_heal":   # 祝福（暖光 / 狐火渺然每秒回复队长）：头顶落三朵小铃铛
			if g.ppos == Vector2.INF:
				return
			_on_lead(o, "heal_up", "up")
			_on_lead(o, "heal_gd", "gd")
			R._light(o, g.ppos + Vector2(0, -24), 90.0, 0.45, 0.12, HEAL_LIGHT)
		"sz_drop":   # 狐火渺然期间：一团狐火从上落下炸开（落地 3 拍后才照地 + 颗粒）
			var at: Vector2 = d.at
			_up(o, "drop_up", at, at.y + 1.0)
			_gd(o, "drop_gd", at)
			_pend.append({"t": g.t + 0.2, "at": at, "o": o})
		"sz_splash":   # 扩散（late_shape 升级卡）：命中处一圈火环往外推
			if _beat_n(o, "spl") >= 2:
				return
			_gd(o, "splash_gd", d.at)
			R._light(o, (d.at as Vector2) + Vector2(0, -8), 80.0, 0.4, 0.1, p.light)
		"sz_link":   # 连携「狐火」：四团狐火绕她一圈再各追一只（画面按 skill_link 同公式每帧重算）
			_rt.append({"link": true, "o": o, "ts": d.get("ts", []), "c": d.get("c", o.pos), "t0": g.t, "hist": [[], [], [], []], "oid": str(o.id)})
			R._light(o, o.pos + Vector2(0, -24), 100.0, 0.5, 0.15, p.light)
		"sz_link_hit":
			var at2: Vector2 = d.at
			_up(o, "hit_up", at2 + Vector2(0, 12), at2.y + 13.0)
			_gd(o, "hit_gd", at2 + Vector2(0, 12))
			R._light(o, at2, 100.0, 0.6, 0.12, p.light)
			R._grains(o, at2, at2.y + 14.0, "flame", 4, {})
		"skill":
			var i: int = int(d.get("i", -1))
			var fl: Dictionary = _sz()._h4_live(o, "verb.foxlight")
			var rad: float = _sz().h4_fox_r(o, fl) if not fl.is_empty() else 170.0
			if i == 0:   # 全力以赴：脚下金色符阵（跟她）
				_on_her(o, "s1sig_gd", "gd", Vector2(0, 4))
				R._light(o, o.pos + Vector2(0, -16), 140.0, 0.7, 0.15, p.light)
				R._grains(o, o.pos + Vector2(0, -30), o.pos.y + 2.0, "flame", 6, {})
				if "fox_seal2" in str(o.nodes_taken).split(","):   # 画地为牢·禁足：身边一圈金色火舌立起（定身范围）
					var rs: float = float(o.base("aura", 85.0)) * float(o.base("seal2_r_mult", 1.5)) * 0.5
					var Rp: int = _fit(PRAY_R, rs)
					_on_her(o, "pray_r%d_gd" % Rp, "gd", Vector2(0, 4))
					_on_her(o, "pray_r%d_b" % Rp, "up", Vector2(0, 4), -3.0)
					_on_her(o, "pray_r%d_f" % Rp, "up", Vector2(0, 4), 1.0)
			elif i == 1:   # 儿时的舞乐：光域推开一圈火（落地火环）
				var R2: int = _fit(S2_R, rad * 0.5)
				var c2: Vector2 = o.pos + Vector2(0, 4)
				_gd(o, "s2_r%d_gd" % R2, c2)
				_up(o, "s2_r%d_b" % R2, c2, c2.y - 3.0)
				_up(o, "s2_r%d_f" % R2, c2, c2.y + 1.0)
				R._light(o, o.pos + Vector2(0, -16), minf(240.0, rad), 0.75, 0.15, p.light)
				R._grains(o, o.pos + Vector2(0, -24), o.pos.y + 2.0, "flame", 10, {})
			elif i == 2:   # 狐火渺然：一条大火尾绕身扫一圈（跟她）
				var R3: int = _fit(S3_R, rad * 0.5)
				_on_her(o, "s3_r%d_gd" % R3, "gd", Vector2(0, 4))
				_on_her(o, "s3_r%d_b" % R3, "up", Vector2(0, 4), -3.0)
				_on_her(o, "s3_r%d_f" % R3, "up", Vector2(0, 4), 1.0)
				R._light(o, o.pos + Vector2(0, -16), 220.0, 0.85, 0.15, p.light)
				R._grains(o, o.pos + Vector2(0, -24), o.pos.y + 2.0, "flame", 14, {})
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var cc: Vector2 = d.get("c", o.pos)
			var rr: float = float(d.get("r", 85.0))
			if src == "狐火":   # 响应「祈愿」：队长处光域闪一下（一圈火舌立起）
				var Rq: int = _fit(PRAY_R, rr * 0.5)
				_gd(o, "pray_r%d_gd" % Rq, cc + Vector2(0, 4))
				_up(o, "pray_r%d_b" % Rq, cc + Vector2(0, 4), cc.y + 1.0)
				_up(o, "pray_r%d_f" % Rq, cc + Vector2(0, 4), cc.y + 5.0)
				R._light(o, cc + Vector2(0, -16), minf(200.0, rr * 1.2), 0.6, 0.12, p.light)
				R._grains(o, cc + Vector2(0, -16), cc.y + 2.0, "flame", 5, {})
			elif src == "围炉":   # 围炉·添薪：脚下火环往外窜
				var Rh: int = _fit(HB_R, rr * 0.5)
				_gd(o, "hb_r%d_gd" % Rh, cc + Vector2(0, 4))
				_up(o, "hb_r%d_b" % Rh, cc + Vector2(0, 4), cc.y + 1.0)
				_up(o, "hb_r%d_f" % Rh, cc + Vector2(0, 4), cc.y + 5.0)
				R._light(o, cc + Vector2(0, -16), minf(200.0, rr * 1.3), 0.7, 0.13, p.light)
				R._grains(o, cc + Vector2(0, -16), cc.y + 2.0, "flame", 8, {})


# ================================================================ 绘制

## 地面层：光域边（虚线，压扁）、灼印 / 金印（跟敌人）、贴地件；顺手放延后的落点照地
func draw_floor(o) -> void:
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	for i in range(_pend.size() - 1, -1, -1):
		var q: Dictionary = _pend[i]
		if g.t >= float(q.t):
			_pend.remove_at(i)
			if is_instance_valid(q.o):
				R._light(q.o, (q.at as Vector2) + Vector2(0, -8), 90.0, 0.5, 0.12, p.light)
				R._grains(q.o, (q.at as Vector2) + Vector2(0, -8), (q.at as Vector2).y + 2.0, "flame", 3, {})
	if o.pos == Vector2.INF or not o.hw.has("sz"):
		_floor_items(o)
		return
	var cv = o.cv
	var px: float = g.PX
	var sz: Dictionary = o.hw.sz
	var fl: Dictionary = _sz()._h4_live(o, "verb.foxlight")
	if not fl.is_empty():
		var rad: float = _sz().h4_fox_r(o, fl)
		var mode: int = 2 if float(sz.haze_t) > 0.0 else (1 if _sz()._h4_warm(o, fl) else 0)
		var c0: Vector2 = Pxp._snap(o.pos + Vector2(0, 4))
		var ring: Array = _aura_px(int(round(rad * 0.5)), int(floor(g.t * 15.0)), mode)
		if cv.active and not (g.opt_old & g.OPT_SZAURA):   # 整组展开好的矩形平移后一次接到批尾（docs/287 §3 ④）；圆心在 2 像素格上，顶点与逐个 draw_rect 逐位相同
			if _ring_q_key != _ring_key:
				_ring_q_key = _ring_key
				_ring_q = _aura_quads(ring, px)
			cv.add_quads(Transform2D(0.0, c0) * (_ring_q[0] as PackedVector2Array), _ring_q[1])
		else:
			for q in ring:
				cv.draw_rect(Rect2(c0 + Vector2(q[0], q[1]) * px, Vector2(px, px)), q[2])
	# 精一狐火灼印：原来画在敌人脚下、被身体挡住 → 改到立起层印在身上（sort_items，docs/310 §4.2）
	for s3 in sz.seals:   # 画地为牢：被定身的敌人脚下金色封印
		var e2: Dictionary = s3.e
		if e2.get("dead", false):
			continue
		r._draw_strip(cv, "sz_seal_gd", r.frame_of(0.0), Pxp._snap(e2.pos + Vector2(0, 4)), false, false, Color(1, 1, 1, clampf(float(s3.t) / 0.15, 0.0, 1.0)))
	_floor_items(o)


func _floor_items(o) -> void:
	var id: String = str(o.id)
	for it in r.items_for(id):
		if str(it.ly) == "gd":
			r._draw_strip(o.cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)


func draw_over(_o) -> void:
	pass


var _ring_q_key := ""
var _ring_q: Array = []

## 光域像素 → 以圆心为原点、已展开的矩形三角形（点序同 batch_canvas._quad）与逐点颜色
func _aura_quads(ring: Array, px: float) -> Array:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(ring.size() * 6)
	cols.resize(ring.size() * 6)
	var k := 0
	for q in ring:
		var p0: Vector2 = Vector2(q[0], q[1]) * px
		var p1: Vector2 = p0 + Vector2(px, 0.0)
		var p2: Vector2 = p0 + Vector2(px, px)
		var p3: Vector2 = p0 + Vector2(0.0, px)
		pts[k] = p0
		pts[k + 1] = p1
		pts[k + 2] = p2
		pts[k + 3] = p0
		pts[k + 4] = p2
		pts[k + 5] = p3
		for j in 6:
			cols[k + j] = q[2]
		k += 6
	return [pts, cols]


func _aura_px(R: int, bt: int, mode: int) -> Array:
	# 11-11 docs/332 §3：常态（mode 0）的光域只随旋转格 (bt / 2) % 64 变，键按它取（原来按 bt，每拍都重算，其中一半算出来一模一样）；
	# 重算走预计算的采样表（_aura_ring0），不再逐点 cos / sin、Vector2i 字典去重，结果与 aura_ring 逐项相同。--wdold=32 / --wdab=N:32 退回
	var fast: bool = mode == 0 and g.world != null and g.world.wd_new(32)
	var key: String = ("%d:r%d:0" % [R, (bt / 2) % 64]) if fast else ("%d:%d:%d" % [R, bt, mode])
	if key != _ring_key:
		_ring_key = key
		_ring_px = _aura_ring0(R, bt) if fast else aura_ring(R, bt, mode)
	return _ring_px


var _r0_R := -1
var _r0_tt: Array = []              # 采样点角度 t，与 aura_ring 同式算出（GDScript float 是 64 位，PackedFloat32 会丢精度，所以用 Array）
var _r0_id := PackedInt32Array()    # 采样点 → 去重后的像素格编号
var _r0_xy: Array = []              # 像素格编号 → [x, y]


## aura_ring(R, bt, 0) 的同结果快速版：同一 R 只建一次采样表；逐帧只做「是否在亮段」与按格去重（PackedByteArray），次序 / 取色与原式相同
func _aura_ring0(R: int, bt: int) -> Array:
	var n: int = maxi(24, int(R * 6.4))
	if R != _r0_R:
		_r0_R = R
		_r0_tt = []
		_r0_id = PackedInt32Array()
		_r0_xy = []
		var ids := {}
		for q in n:
			var t: float = float(q) / float(n) * TAU
			var key := Vector2i(int(roundf(R * cos(t))), int(roundf(R * sin(t) * SQ)))
			if not ids.has(key):
				ids[key] = _r0_xy.size()
				_r0_xy.append([key.x, key.y])
			_r0_tt.append(t)
			_r0_id.append(int(ids[key]))
	var out: Array = []
	var rot: float = float((bt / 2) % 64) / 64.0 * TAU / 12.0
	var duty: float = 0.42
	var seen := PackedByteArray()
	seen.resize(_r0_xy.size())
	for q in n:
		var seg: float = fposmod(float(_r0_tt[q]) - rot, TAU / 12.0) / (TAU / 12.0)
		if seg > duty:
			continue
		var id: int = _r0_id[q]
		if seen[id] != 0:
			continue
		seen[id] = 1
		var xy: Array = _r0_xy[id]
		out.append([xy[0], xy[1], F[2] if seg < duty * 0.7 else F[1]])
	return out


## 排序项：九尾、绕身狐火、狐火弹、大狐火、附着火、拖尾、光域边火、传火线、连携狐火
func sort_items(o, out: Array) -> void:
	if not o.hw.has("sz"):
		return
	var S = _sz()
	var sz: Dictionary = o.hw.sz
	var a: Dictionary = o.B.get("attack", {})
	var bt: int = int(floor(g.t * 15.0))
	var flare := false
	for it in r.items_for(str(o.id)):
		if str(it.k) == "sz_tails_flare":
			flare = true
	if not flare and not S._h4_sub(o, a.get("tails", null)).is_empty():   # 精二九尾：排在她身后
		out.append({"sz": "strip", "k": "sz_tails", "gp": Pxp._snap(o.pos), "flip": o.face < 0.0, "skey": o.pos.y - 2.0, "loop": true})
	# 绕身狐火（数量 = 每次普攻的狐火数）；三火归一那一次三团往杖头汇
	var n: int = S._h4_fox_shots(o, a)
	var conv := 0.0
	if sz.merging:
		conv = 1.0
	elif float(sz.haze_t) <= 0.0 and S._h4_next_merge(o, a):
		conv = clampf(1.0 - o.cd / 0.45, 0.0, 1.0)
	var tip: Vector2 = S._h4_tip(o, a)
	if r.tier(o) >= 2:   # 11-05：精二九尾和绕身狐火只留九尾常驻（三火归一汇聚那一下仍画杖头狐火）
		n = 0
	for k in n:
		var an: float = float(bt) / 15.0 * 1.6 + k * TAU / n
		var gy: float = o.pos.y + sin(an) * 13.0
		var pp: Vector2 = o.pos + Vector2(cos(an) * 40.0, -22.0 + sin(an) * 13.0)
		if k < 3 and conv > 0.0:
			if conv > 0.85:
				continue
			pp = pp.lerp(tip, conv * conv)
		out.append({"sz": "strip", "k": "sz_fl_s", "gp": Pxp._snap(pp + Vector2(0, 4)), "flip": false, "skey": gy + 1.0, "loop": true, "ph": k})
	if conv > (0.2 if n == 0 else 0.5):
		out.append({"sz": "strip", "k": "sz_gather", "gp": Pxp._snap(tip), "flip": false, "skey": o.pos.y + 2.0, "loop": true})
	for s2 in sz.brands:   # 精一狐火灼印：印在被打中的敌人身上（排在本体之后），出现那 0.3 秒外加一圈金色亮边
		var e: Dictionary = s2.e
		if e.get("dead", false):
			continue
		var al: float = clampf(float(s2.t) / 0.3, 0.0, 1.0)
		out.append({"sz": "strip", "k": "sz_brand_gd", "gp": Pxp._snap(e.pos + Vector2(0, -float(e.r) * 0.75)), "flip": false, "skey": float(e.pos.y) + 3.0, "ph": int(e.id), "a": al})
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != o.id or b.kind != "arcane":
			continue
		out.append({"sz": "bolt", "b": b, "skey": _bolt_pos(b).y + 4.0})
	for f in sz.bigfox:
		var dk: Array = Pxp.pick_dir((f.vel as Vector2).angle())
		out.append({"sz": "strip", "k": "sz_bigfox_d%d" % int(dk[0]), "gp": Pxp._snap(f.pos), "flip": bool(dk[1]), "skey": (f.pos as Vector2).y + 8.0, "loop": true})
	for s2 in sz.att:   # 狐火点点：附在敌人头上的一团火
		var ee: Dictionary = s2.e
		if ee.get("dead", false):
			continue
		out.append({"sz": "strip", "k": "sz_fl_m", "gp": Pxp._snap(ee.pos + Vector2(0, -float(ee.r) * 1.1)), "flip": false, "skey": float(ee.pos.y) + 1.0, "loop": true, "ph": int(ee.id),
			"a": clampf(float(s2.t) / 0.3, 0.0, 1.0)})
	var tr: Dictionary = a.get("merge", {}).get("trail", {})
	var life: float = float(tr.get("life", 1.0))
	for tg in sz.trails:   # 精二狐火拖尾：路上一簇簇矮火苗，按剩余寿命变矮变暗
		var j := 0
		for q in tg.pts:
			var u: float = clampf(1.0 - float(q.t) / life, 0.0, 1.0)
			var lv: int = 0 if u < 0.4 else (1 if u < 0.75 else 2)
			out.append({"sz": "tuft", "gp": Pxp._snap((q.pos as Vector2) + Vector2(0, 6)), "tf": lv * 4 + (bt + j) % 4, "skey": (q.pos as Vector2).y + 6.0})
			j += 1
	var fl: Dictionary = S._h4_live(o, "verb.foxlight")
	if not fl.is_empty():
		var rad: float = S.h4_fox_r(o, fl)
		var hr: Dictionary = S._h4_hearth(o, fl)
		if not hr.is_empty():   # 围炉：光域边上的大狐火（画在玩法位置：0.55 椭圆，同 _h4_hearth_tick）
			var hn: int = int(hr.get("n", 6))
			for k in hn:
				var an2: float = g.t * 0.8 + k * TAU / hn
				var hp: Vector2 = o.pos + Vector2(4, 4) + Vector2(cos(an2) * rad, sin(an2) * rad * 0.55)
				out.append({"sz": "strip", "k": "sz_fl_l", "gp": Pxp._snap(hp), "flip": false, "skey": hp.y, "loop": true, "ph": k})
		else:
			var on: bool = _sz()._h4_warm(o, fl) or float(sz.haze_t) > 0.0
			var en: int = 9 if float(sz.haze_t) > 0.0 else 6
			for k in en:
				var an3: float = float(bt) / 15.0 * 0.8 + k * TAU / en
				var ep: Vector2 = o.pos + Vector2(0, 4) + Vector2(cos(an3) * rad, sin(an3) * rad * SQ)
				out.append({"sz": "strip", "k": "sz_fl_m" if on else "sz_fl_s", "gp": Pxp._snap(ep), "flip": false, "skey": ep.y, "loop": true, "ph": k})
	_rt = _rt.filter(func(x): return g.t - float(x.t0) < (0.2 if x.has("pass") else LINK_T1 + LINK_T2 + 0.05))
	for x in _rt:
		if str(x.oid) != str(o.id):
			continue
		if x.has("pass"):
			out.append({"sz": "pass", "x": x, "skey": maxf((x.a as Vector2).y, (x.b as Vector2).y) + 1.0})
		elif x.has("link") and is_instance_valid(x.o) and x.o.pos != Vector2.INF:
			_link_step(x)
			for j2 in 4:
				var h: Array = x.hist[j2]
				if h.is_empty():
					continue
				out.append({"sz": "lk", "x": x, "j": j2, "skey": (h[h.size() - 1] as Vector2).y + 26.0})


## 连携狐火：同 skill_link l_suzuran 的位置公式（绕身 T1 秒 → 追向第 j 只 T2 秒）；每拍记一个位置画追迹
func _link_step(x: Dictionary) -> void:
	var t: float = g.t - float(x.t0)
	var bt: int = int(floor(g.t * 15.0))
	if int(x.get("bt", -1)) == bt:
		return
	x["bt"] = bt
	var p = x.o
	for j in 4:
		var orb: Vector2 = p.pos + Vector2(0, -24) + Vector2.from_angle(TAU * (j / 4.0 + minf(t, LINK_T1) / LINK_T1)) * 40.0
		var q: Vector2 = orb
		if t >= LINK_T1:
			var e = x.ts[j] if j < x.ts.size() else null
			var to: Vector2 = (e.pos + Vector2(0, -12)) if e != null and not e.dead else (x.c as Vector2)
			q = orb.lerp(to, minf(1.0, (t - LINK_T1) / LINK_T2))
		var h: Array = x.hist[j]
		h.append(Pxp._snap(q))
		if h.size() > 6:
			h.pop_front()


func draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	var bt: int = int(floor(g.t * 15.0))
	match str(it.sz):
		"strip":
			var fi: int = r.frame_of(0.0) + int(it.get("ph", 0))
			r._draw_strip(ci, str(it.k), fi, it.gp, bool(it.get("flip", false)), false, Color(1, 1, 1, float(it.get("a", 1.0))))
		"tuft":
			r._draw_strip(ci, "sz_tuft", int(it.tf), it.gp, false, true)   # 键名 tf（fi / ex / wave / cut 等被 fx_pxplane.draw_sorted 先截走）
		"bolt":
			var b: Dictionary = it.b
			var dv: Vector2 = (b.vel as Vector2).normalized() if (b.vel as Vector2).length() > 1.0 else Vector2.RIGHT
			_bolt(ci, Pxp._snap(_bolt_pos(b)), dv, bt, b.get("_pxv", false))
		"pass":
			var x: Dictionary = it.x
			var f: int = int(floor(g.t * 15.0)) - int(floor(float(x.t0) * 15.0))
			var a0: Vector2 = Pxp._snap((x.a as Vector2) + Vector2(0, -12))
			var b0: Vector2 = (x.b as Vector2) + Vector2(0, -12)
			for q in pass_line((b0.x - a0.x) / px, (b0.y - a0.y) / px, f):
				ci.draw_rect(Rect2(a0 + Vector2(q[0], q[1]) * px, Vector2(px, px)), q[2])
		"lk":
			var x2: Dictionary = it.x
			var h: Array = x2.hist[int(it.j)]
			var head: Vector2 = h[h.size() - 1]
			var dv2: Vector2 = (head - (h[h.size() - 2] as Vector2)).normalized() if h.size() >= 2 and head != h[h.size() - 2] else Vector2.UP
			for k in range(h.size() - 1):   # 追迹：身后几拍的位置连成一道浅金细线（越旧越暗）
				var p0: Vector2 = h[k]
				var p1: Vector2 = h[k + 1]
				var m: int = int(maxf(absf(p1.x - p0.x), absf(p1.y - p0.y)) / px)
				var col: Color = P[2] if k < h.size() - 3 else F[4]
				for i in m:
					if (i + k) % 2 == 1 and k < h.size() - 3:
						continue
					ci.draw_rect(Rect2(Pxp._snap(p0.lerp(p1, float(i) / float(maxi(1, m)))), Vector2(px, px)), col)
			_bolt(ci, head, dv2, bt, true)


## 画面位置：全力以赴那五发出手 0.3 秒内沿各自出射方向多推 22 世界像素（扇形错开），之后就是真实位置
func _bolt_pos(b: Dictionary) -> Vector2:
	if not b.has("_pxf"):
		return b.pos
	var k: float = maxf(0.0, 1.0 - (g.t - float(b._pxf[0])) / 0.3)
	return (b.pos as Vector2) + (b._pxf[1] as Vector2) * 22.0 * k


func _bolt(ci, head: Vector2, d: Vector2, bt: int, big: bool) -> void:
	var px: float = g.PX
	var nv := Vector2(-d.y, d.x)
	for q in fox_bolt(bt, big):
		var p2: Vector2 = Pxp._snap(head - d * float(q[0]) * px + nv * float(q[1]) * px)
		ci.draw_rect(Rect2(p2, Vector2(px, px)), q[2])
	if g.optical_on and r._emit_n < Pxp.EMIT_CAP:
		r._emit_n += 1
		g.glow_next.append([head, px, Color(F[6], (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])


# ================================================================ 运行时像素（同 tools/pxplane_suzuran_art.py）

static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


## 同 fox_bolt()：[沿向 s（往后为正）, 法向 w, 颜色]
static func fox_bolt(bt: int, big: bool) -> Array:
	var out: Array = [[0, 0, F[6]], [-1, 0, F[5]], [0, 1, F[5]], [0, -1, F[5]], [1, 0, F[5]], [1, 1, F[4]], [1, -1, F[4]], [2, 0, F[4]]]
	if big:
		out.append_array([[-1, 1, F[4]], [-1, -1, F[4]], [0, 2, F[3]], [0, -2, F[3]], [-2, 0, F[5]], [1, 2, F[3]], [1, -2, F[3]]])
		for s in range(2, 8):
			var w: int = 1 if s < 6 else 2
			if (s + bt) % 4 == 3 and s > 3:
				continue
			var col: Color = F[4] if s < 4 else (F[3] if s < 6 else F[2])
			out.append([s, w, col])
			out.append([s, -w, col])
		out.append([8, 2 if bt % 2 == 0 else 1, P[3]])
		out.append([8, -2 if bt % 2 == 1 else -1, P[3]])
	else:
		for s in range(3, 6):
			if (s + bt) % 3 == 0 and s > 3:
				continue
			out.append([s, 0, F[3] if s < 5 else F[2]])
		out.append([4, 1 if bt % 2 == 0 else -1, F[3]])
		out.append([6, -1 if bt % 2 == 0 else 1, P[2]])
	return out


## 同 aura_ring()：[x, y, 颜色]（美术像素，相对光域中心）
static func aura_ring(R: int, bt: int, mode: int) -> Array:
	var out: Array = []
	var n: int = maxi(24, int(R * 6.4))
	var rot: float = float((bt / 2) % 64) / 64.0 * TAU / 12.0
	var duty: float = [0.42, 0.62, 0.66][mode]
	var seen := {}
	for q in n:
		var t: float = float(q) / float(n) * TAU
		var seg: float = fposmod(t - rot, TAU / 12.0) / (TAU / 12.0)
		if seg > duty:
			continue
		var x: int = int(roundf(R * cos(t)))
		var y: int = int(roundf(R * sin(t) * SQ))
		var key := Vector2i(x, y)
		if seen.has(key):
			continue
		seen[key] = true
		var c: Color
		if mode == 0:
			c = F[2] if seg < duty * 0.7 else F[1]
		elif mode == 1:
			c = F[4] if seg < duty * 0.25 else (F[3] if seg < duty * 0.75 else F[2])
		else:
			c = P[3] if (q / 6) % 2 == 0 else F[3]
			if seg > duty * 0.8:
				c = P[1]
		out.append([x, y, c])
		if mode >= 1 and seg < duty * 0.75:
			var ki := Vector2i(int(roundf((R - 1) * cos(t))), int(roundf((R - 1) * sin(t) * SQ)))
			if not seen.has(ki):
				seen[ki] = true
				out.append([ki.x, ki.y, F[1] if mode == 1 else P[0]])
	if mode == 1:
		var r2: float = R * 0.86
		var m: int = maxi(12, int(r2 * 1.6))
		for q in m:
			var t2: float = float(q) / float(m) * TAU - rot * 0.5
			if (q + bt / 3) % 3 != 0:
				continue
			out.append([int(roundf(r2 * cos(t2))), int(roundf(r2 * sin(t2) * SQ)), P[2]])
	if mode == 2:
		var bands := [[0.74, 5.0], [0.5, 4.0]]
		for k in 2:
			var r3: float = R * float(bands[k][0])
			var m3: int = maxi(16, int(r3 * 3.2))
			for q in m3:
				var t3: float = float(q) / float(m3) * TAU
				if _hf(q, k, 5) < 0.45 or (q + bt / 2 + k * 7) % 9 < 3:
					continue
				var wob: float = sin(t3 * float(bands[k][1]) + bt * 0.12 + k) * 3.0
				out.append([int(roundf((r3 + wob) * cos(t3))), int(roundf((r3 + wob) * sin(t3) * SQ)), P[2] if q % 4 != 0 else P[1]])
	return out


## 同 pass_line()：[x, y, 颜色]（美术像素，相对 a）
static func pass_line(dx: float, dy: float, f: int) -> Array:
	var L: float = maxf(1.0, Vector2(dx, dy).length())
	var m: int = int(L)
	var out: Array = []
	for i in m + 1:
		var u: float = float(i) / float(maxi(1, m))
		if f == 1 and u < 0.45:
			continue
		if f >= 2 and u < 0.82:
			continue
		var lift: float = 4.0 * L * 0.12 * u * (1.0 - u)
		out.append([int(roundf(dx * u)), int(roundf(dy * u - lift)), F[5] if (f == 0 and u > 0.3 and u < 0.9) else F[4]])
	return out
