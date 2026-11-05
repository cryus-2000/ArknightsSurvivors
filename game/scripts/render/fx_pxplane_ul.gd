## 乌尔比安「转平面」（docs/266，开关 fx/px_plane）：fx_pxplane 的乌尔比安一节单独成文件（同批五人同时改 fx_pxplane.gd，分开免得合并冲突）。
## 全部是静态函数，第一个参数 r = fx_pxplane 实例（借它的件表、帧条绘制、15 fps 节拍、发光层、精英档）。只画，不碰玩法、不抽玩法随机数（颗粒走 fx_recipe 的 g.vrng）。
## 意象：重锚、锁链、深海——和推进之王的锤击区分开，这里砸下去是海水，不画裂网：
##   普攻锚击 = 尖刺爆闪 + 一圈参差水冠 + 水泡 / 地上锚印；每一下的撼地 = 以他为心一圈 1 美术像素细涟漪；
##   精一「收链」= 锚印外圈白沫拖痕往落点收；精二 = 锚印里一个深渊暗涡（血纹暗段）+ 每第 3 下掷锚（锁链 + 拖拽水沟）。
##   S1 = 锁链（运行时逐美术像素画）+ 钩回时被拖的怪身后一道 V 字水沟（精一起）+ 重砸一束炸起的水；S2 起手 = 锁链在脚下盘成一圈界限；
##   S3 = 冲锋破浪（V 字尾迹 + 脚下水滴）+ 落地大水冠 + 漩涡；锁链回旋 = 地上一圈甩出的水弧；定点爆破 = 回涌；连携掷锚 = 海水往锚回卷。
## 帧条：game/art/fx/pxp/pxp_ul_*.png + data/pxp_ulpianus.json（tools/pxplane_bake_ulpianus.py，纯 Python 逐格生成）；
## 锚本体沿用干员自己的锚贴图（seg_ulpianus._hw_draw_anchor，是武器不是特效）；锁链 / 水沟 / 通路 / 后期冲击波逐美术像素画。
## 旧做法对照（fx/px_plane = 2）：乌尔比安没有旧 pixelfx 帧条，2 时只画锁链和锚（不画特效），三栏图那一栏留空。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const MI = preload("res://scripts/render/melee_impact.gd")
const SY := 0.72
const C := [Color("#070a1e"), Color("#0c1235"), Color("#1b2a66"), Color("#2c4397"), Color("#4463c8"), Color("#7b93e6"), Color("#c0cbf6"), Color("#ffffff")]   # OP.ulpianus 审定 7 阶 + 压底
const DUST := [Color("#131528"), Color("#212842"), Color("#323c5e"), Color("#4a5781"), Color("#6b7ba6"), Color("#9eabcf")]   # OP.ulpianus_dust：锁链
const ATK_R := [44, 56, 68, 84]
const QUAKE_R := [75, 90, 105, 125]
const ECHO_R := [50, 60, 72]
const S1_R := [45, 56, 68]
const WHIRL_R := [65, 78]
const WAKE_TAIL := 0.4
const RIFT_LIFE := 0.8
const S2_OPEN := 0.9      # S2 起手链环从脚下扩到锚击半径再收回的时长
const S2_RING := 24.0     # 常驻链环半径（美术像素，= 48 世界像素，在精二血脉环 30 外面）
const S2_REACH := 68.0    # 起手链环扩到的半径（生效后的锚击半径 136）
const TRAIL_COOL := 0.8   # S3 深海拖痕落地后冷却的时长
const QI_BREAK := 0.17    # 后期冲击波玩法上消失后，原地碎开的时长（总可见约 0.35 秒）
const ORCA := [Color("#0d0f15"), Color("#262c38"), Color("#4a5781"), Color("#e8ecf4"), Color("#b4bccc"), Color("#5c6577")]   # 虎鲸：黑 / 暗 / 背脊受光 / 白 / 白的暗面 / 鞍斑灰
const ORCA_LEAP := 0.18   # 虎鲸到落点前跃起的时长（落下那一刻 = 玩法落地重击）
const SLAM_KEEP := 2   # 同一名干员同屏至多两记锚击水冠（最新 + 正在收的）

static var _SegU = null


static func _segu():
	if _SegU == null:
		_SegU = load("res://scripts/characters/blocks/seg_ulpianus.gd")   # 运行时取（避免和积木链循环 preload）
	return _SegU


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _bucket(v: float, opts: Array) -> int:
	var best: int = int(opts[0])
	for q in opts:
		if absf(float(q) - v) < absf(float(best) - v):
			best = int(q)
	return best


static func _strip(r, o, k: String, at: Vector2, ly: String, follow := false, extra := {}) -> void:
	var it := {"k": "ul_" + k, "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	it.merge(extra, true)
	r._push(it)


static func _pair(r, o, k: String, at: Vector2, follow := false, extra := {}) -> void:
	_strip(r, o, k + "_up", at, "up", follow, extra)
	_strip(r, o, k + "_gd", at, "gd", follow, extra)


static func _rt(r, o, kind: String, ly: String, life: float, d: Dictionary) -> void:
	var it := {"ulrt": kind, "t0": r.g.t, "life": life, "ly": ly, "oid": str(o.id), "k": "", "gp": d.get("gp", o.pos)}
	it.merge(d, true)
	r._push(it)


## 同一名干员只留最新 SLAM_KEEP - 1 记锚击水冠 + 这一记（连击叠在一起会糊）
static func _trim_slams(r, o) -> void:
	var mine: Array = []
	for it in r.items:
		if it.get("ulslam", false) and str(it.oid) == str(o.id) and str(it.ly) == "up":
			mine.append(it)
	while mine.size() >= SLAM_KEEP:
		var old: Dictionary = mine.pop_front()
		old["life"] = 0.0
		for it in r.items:   # 同一记的贴地件一起收
			if it.get("ulslam", false) and float(it.t0) == float(old.t0) and str(it.oid) == str(o.id):
				it["life"] = 0.0


static func _burst(r, o, R, p: Dictionary, at: Vector2, es: Array, n: int, lr: float, li: float) -> void:
	if r.mode() != 1:
		return
	var m := {"tier": r.tier(o), "grain_spd": 1.0}
	var hp: Vector2 = at + Vector2(0, -10)
	if not es.is_empty():
		var e: Dictionary = es[0]
		hp = e.pos + Vector2(0, -float(e.r) * 0.5)
	R._grains(o, hp, at.y + 2.0, "ink", mini(n, 2 + es.size() + n / 2), m)
	R._light(o, hp, lr, li * MI.lit_k(r.g), 0.12, p.light)


# ================================================================ 事件

static func ev(r, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = r.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:
		print("PXPLOG ul %s %s %d %.3f" % [kind, str(d.get("src", "")), Engine.get_process_frames(), float(g.t)])
	if raw:
		return
	match kind:
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c: Vector2 = d.get("c", o.pos)
			var ra: float = float(d.get("r", 89.0)) * 0.5
			var es: Array = d.get("es", [])
			match src:
				"锚击", "钩与锚":
					if "skill" in d.get("tags", []):   # 不容挣脱·绞杀：钩回落地后身前再抡一锤（S1 一系的重砸）
						_trim_slams(r, o)
						_pair(r, o, "s1_r%d_e%d" % [_bucket(ra, S1_R), t], c, false, {"ulslam": true})
						_burst(r, o, R, p, c, es, 7, 150.0, 0.55)
						return
					_trim_slams(r, o)
					_pair(r, o, "atk_r%d_e%d" % [_bucket(ra, ATK_R), t], c, false, {"ulslam": true})
					_burst(r, o, R, p, c, es, 3 + t, 120.0, 0.45)
				"撼地":
					_strip(r, o, "quake_r%d_gd" % _bucket(ra, QUAKE_R), c, "gd")
				"定点爆破":
					_pair(r, o, "echo_r%d" % _bucket(ra, ECHO_R), c)
					_burst(r, o, R, p, c, es, 3, 90.0, 0.3)
				"锁链回旋":
					_strip(r, o, "whirl_r%d_gd" % _bucket(ra, WHIRL_R), c, "gd", true)
					R._grains(o, c + Vector2(0, -16), c.y + 2.0, "ink", 4, {"tier": t, "grain_spd": 1.3})
		"ul_orca":   # S3（docs/266 §7，用户「一头虎鲸打出去，因为他本来就是虎鲸」）：掷锚出手同时虎鲸破水冲出
			var fr: Vector2 = d.from
			var to: Vector2 = d.to
			var dv: Vector2 = (to - fr).normalized() if to.distance_to(fr) > 1.0 else Vector2(o.face, 0)
			var land: Vector2 = to - dv * 18.0
			var est: float = clampf(fr.distance_to(land) / 1100.0, 0.14, 0.34)   # 同 _hw_anchor_bite 的冲锋时长（到咬地时再用实际值校正）
			_rt(r, o, "orca", "up", float(d.throw) + est + 0.3, {"S": fr + dv * 20.0, "land": land, "dv": dv, "T1": g.t + float(d.throw) + est, "gp": fr, "gy": fr.y + 1.0})
			_pair(r, o, "bite_r22", fr + dv * 20.0)   # 破水
			R._grains(o, fr + dv * 20.0 + Vector2(0, -10), fr.y + 2.0, "ink", 4, {"tier": 2})
		"ul_bite":   # 锚咬地（S1 掷锚落点；S3 由虎鲸代替，不出）
			if d.get("big", false):
				return
			var at: Vector2 = d.at
			_pair(r, o, "bite_r%d" % (22 if d.get("big", false) else 14), at)
			R._grains(o, at + Vector2(0, -8), at.y + 2.0, "ink", 3, {"tier": t})
		"ul_reel":   # S1 钩住开始往回拽：精一起被拽的怪身后一道 V 字水沟
			if t >= 1:
				var an: Dictionary = d.an
				for hk in o.hw.get("hooked", []):
					_rt(r, o, "wake", "gd", float(an.dur) + 0.14 + WAKE_TAIL, {"e": hk.e, "from": hk.from, "t1": g.t + float(an.dur), "gp": hk.from, "w": 1 + t})
		"ul_slam":   # S1 重砸
			var c1: Vector2 = d.c
			_trim_slams(r, o)
			_pair(r, o, "s1_r%d_e%d" % [_bucket(float(d.r) * 0.5, S1_R), t], c1, false, {"ulslam": true})
			_burst(r, o, R, p, c1, d.get("es", []), 8 + 2 * t, 170.0, 0.65)
		"ul_zip":   # S3 冲锋开始：身后一道深海拖痕（落地后一拍一拍冷下去）；虎鲸按实际冲锋时长校正到点时刻
			_rt(r, o, "zip", "gd", float(d.dur) + TRAIL_COOL, {"a": d.a, "b": d.b, "dur": float(d.dur), "gp": d.a})
			for it in r.items:
				if str(it.get("ulrt", "")) == "orca" and str(it.oid) == str(o.id):
					it["T1"] = g.t + float(d.dur)
					it["land"] = d.b
					it["life"] = g.t - float(it.t0) + float(d.dur) + 0.3
		"ul_land":
			var c2: Vector2 = d.c
			if d.get("s3", false):
				for it in r.items:   # 虎鲸砸下去就没了（落地重击接手）
					if str(it.get("ulrt", "")) == "orca" and str(it.oid) == str(o.id):
						it["life"] = 0.0
				_strip(r, o, "s3_up", c2, "up")
				_strip(r, o, "s3_gd", c2, "gd")
				_burst(r, o, R, p, c2, d.get("es", []), 14, 240.0, 0.75)
			else:   # S1 钩不到人：锚原地砸
				_trim_slams(r, o)
				_pair(r, o, "s1_r%d_e%d" % [_bucket(float(d.r) * 0.5, S1_R), t], c2, false, {"ulslam": true})
				_burst(r, o, R, p, c2, d.get("es", []), 8, 170.0, 0.6)
		"ul_rift":   # 通路洞开：一道暗流通路（地上）+ 往上冒的水泡（立起，分段排序）
			var a: Vector2 = d.a
			var b: Vector2 = d.b
			_rt(r, o, "rift", "gd", RIFT_LIFE, {"a": a, "b": b, "gp": a, "sd": _h(a.x * 0.37 + b.y)})
			var L: float = a.distance_to(b)
			var k: int = 0
			var s: float = 20.0
			while s < L and k < 12:
				var q: Vector2 = a.lerp(b, s / L)
				_rt(r, o, "bub", "up", RIFT_LIFE, {"a": q, "gp": q, "gy": q.y + 1.0, "sd": _h(q.x + q.y * 1.7)})
				s += 34.0
				k += 1
		"ul_after":   # 通路洞开·余震：落地小涟漪
			_strip(r, o, "small_r25_gd", d.p, "gd")
		"ul_hook_hit":   # 精二掷锚 / 锚链应答落地
			var c3: Vector2 = d.c
			_pair(r, o, "bite_r22", c3)
			_strip(r, o, "echo_r%d_gd" % _bucket(float(d.r) * 0.5, ECHO_R), c3, "gd")
			_burst(r, o, R, p, c3, d.get("es", []), 5, 130.0, 0.5)
		"ul_hook_drag":   # 拖回：沿线被拖的怪身后 V 字水沟
			var hk2: Dictionary = d.hk
			for dg in hk2.get("drag", []):
				_rt(r, o, "wake", "gd", float(hk2.dur) + WAKE_TAIL, {"e": dg.e, "from": dg.from, "t1": g.t + float(hk2.dur), "gp": dg.from, "w": 2})
		"ul_hook_arrive":
			var es2: Array = d.get("es", [])
			if not es2.is_empty():
				var e0: Dictionary = es2[0]
				_strip(r, o, "small_r16_gd", e0.pos, "gd")
				R._grains(o, e0.pos + Vector2(0, -6), float(e0.pos.y) + 2.0, "ink", 2 + mini(3, es2.size()), {"tier": t})
		"skill":
			if int(d.get("i", -1)) == 1:   # S2 必须维系的界限：实心链环从脚下扩到锚击半径（跟着人走），之后脚下常驻一圈慢慢转（floor_layer）
				_rt(r, o, "s2ring", "gd", S2_OPEN, {"gp": o.pos, "fo": Vector2.ZERO, "tier": maxi(t, 1)})
				R._light(o, o.pos + Vector2(0, -14), 140.0, 0.45, 0.15, p.light)
		"ul_link":   # 连携「掷锚」：锚飞 0.2 秒 → 钉住 0.5 秒（锁链绷着），被拖的小怪身后水沟
			_rt(r, o, "link", "ov", 0.2 + 0.55, {"fp": d.fp, "tg": d.get("tg"), "tp": d.tp, "gp": d.tp})
		"ul_link_pin":
			var tp: Vector2 = d.tp
			_strip(r, o, "pin_gd", tp, "gd")
			_pair(r, o, "bite_r22", tp)
			for e in d.get("pull", []):
				_rt(r, o, "wake", "gd", 0.5 + WAKE_TAIL, {"e": e, "from": e.pos, "t1": g.t + 0.5, "gp": e.pos, "w": 1})
			R._grains(o, tp + Vector2(0, -12), tp.y + 2.0, "ink", 6, {"tier": 1})
			R._light(o, tp + Vector2(0, -10), 160.0, 0.5, 0.14, p.light)


# ================================================================ 绘制

## 地面层：贴地帧条件 + 运行时贴地件（水沟、冲锋尾迹、暗流通路）+ 精二脚下血脉环（本体状态，接管时照画）
static func floor_layer(r, o) -> void:
	var g = r.g
	var cv = o.cv
	var id: String = str(o.id)
	_segu().hw_draw_look(o, "auras")
	var t: int = r.tier(o)
	if o.get("perm_on") is Array and o.perm_on[1]:   # S2 常驻：脚下一圈实心链环慢慢转
		_ring(r, cv, r._snap(o.pos + Vector2(0, 2)), S2_RING, float(int(floor(g.t * 15.0))) * 0.02, 0, t)
	for it in r.items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("ulrt"):
			match str(it.ulrt):
				"wake":
					_draw_wake(r, cv, it)
				"zip":
					_draw_zip(r, cv, it)
				"s2ring":
					var age: float = g.t - float(it.t0)
					var u: float = clampf(age / 0.33, 0.0, 1.0)
					var rr: float = lerpf(S2_RING, S2_REACH, 1.0 - (1.0 - u) * (1.0 - u)) if age < 0.55 else lerpf(S2_REACH, S2_RING, clampf((age - 0.55) / 0.3, 0.0, 1.0))
					_ring(r, cv, r._gp(it) + Vector2(0, 2), rr, float(int(floor(g.t * 15.0))) * 0.09, 1 if age < 0.55 else 0, int(it.tier))
				"rift":
					_draw_rift(r, cv, it)
			continue
		r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), false, true)


## 上层：锁链 + 锚（掷锚 / 钩索 / 拴住 / 连携）、沉默图标；S3 冲锋中每拍脚下甩几颗水滴
static func over(r, o) -> void:
	var g = r.g
	if o.pos == Vector2.INF:
		return
	var h: Dictionary = o.hw
	var t: int = r.tier(o)
	var SU = _segu()
	var hand: Vector2 = SU._hw_hand(o)
	for it in r.items:   # 虎鲸的排序位置（地面点）每帧按时刻更新
		if str(it.get("ulrt", "")) == "orca" and str(it.oid) == str(o.id):
			var op: Array = _orca_pose(it, g.t)
			it["gp"] = op[0]
			it["gy"] = (op[0] as Vector2).y + 1.0
	if h.has("anchor") and not h.anchor.is_empty() and h.anchor.b.has("path_w") and r.mode() == 1:   # S3：锚和锁链由虎鲸代替，不画（只画脚下水滴）
		var an3: Dictionary = h.anchor
		if str(an3.phase) == "zip":
			var beat3: int = int(floor(g.t * 15.0))
			if int(an3.get("_pxb", -1)) != beat3:
				an3["_pxb"] = beat3
				var R3 = load("res://scripts/render/fx_recipe.gd").of(g)
				R3._grains(o, o.pos + Vector2(0, -6), o.pos.y + 2.0, "ink", 2, {"tier": 2, "grain_spd": 0.8}, -(((an3.land as Vector2) - (an3.start as Vector2)).normalized()))
	elif h.has("anchor") and not h.anchor.is_empty():
		var an: Dictionary = h.anchor
		var k: float = clampf(float(an.t) / maxf(0.001, float(an.dur)), 0.0, 1.0)
		var d: Vector2 = ((an.to as Vector2) - (an.from as Vector2)).normalized()
		match str(an.phase):
			"throw":
				var pa: Vector2 = SU._hw_anchor_pos(an, k)
				chain(r, o.cv, hand, pa, 1, t, false)
				SU._hw_draw_anchor(o, pa, d, 1.0)
			"reel", "hold":
				var ph: Vector2 = ((an.head if str(an.phase) == "reel" else an.front) as Vector2) + Vector2(0, -6)
				chain(r, o.cv, hand, ph, 2 if str(an.phase) == "reel" else 1, t, false)
				for hk in h.get("hooked", []):
					if not hk.e.dead:
						chain(r, o.cv, ph, hk.e.pos + Vector2(0, -float(hk.e.r) * 0.5), 2, t, false)
				SU._hw_draw_anchor(o, ph, -d, 1.0)
			"zip":
				var pz: Vector2 = (an.to as Vector2) + Vector2(0, -6)
				chain(r, o.cv, hand, pz, 3 if float(an.t) < 0.1 else 2, t, false)   # 咬地后头两拍锁链绷直一闪
				SU._hw_draw_anchor(o, pz, d, 1.0)
				var beat: int = int(floor(g.t * 15.0))
				if r.mode() == 1 and int(an.get("_pxb", -1)) != beat:   # 画面专用键：每拍脚下甩两颗水滴（玩法不读）
					an["_pxb"] = beat
					var R = load("res://scripts/render/fx_recipe.gd").of(g)
					R._grains(o, o.pos + Vector2(0, -6), o.pos.y + 2.0, "ink", 2, {"tier": 2, "grain_spd": 0.8}, -(((an.land as Vector2) - (an.start as Vector2)).normalized()))
	for hk in h.get("hooks", []):
		var p: Vector2 = (hk.head as Vector2) + Vector2(0, -6)
		if o.def.has("native_motion") and str(hk.phase) == "fly":
			p = hand.lerp(hk.to, clampf(float(hk.t) / maxf(float(hk.dur), 0.001), 0.0, 1.0)) + Vector2(0, -6)
		var taut: int = 0 if str(hk.phase) == "fly" else 2
		chain(r, o.cv, hand, p, taut, t, false)
		if str(hk.phase) == "drag":
			for dg in hk.drag:
				if not dg.e.dead:
					chain(r, o.cv, p, dg.e.pos + Vector2(0, -float(dg.e.r) * 0.5), 1, t, false)
		var dv: Vector2 = ((hk.to as Vector2) - (hk.from as Vector2)).normalized()
		SU._hw_draw_anchor(o, p, -dv if str(hk.phase) == "drag" else dv, 1.0)
	for l in h.get("leash", []):   # 不容挣脱：拴着的细链（绷直时粗、亮）
		var e: Dictionary = l.e
		if e.dead:
			continue
		var tight: bool = e.pos.distance_to(o.pos) >= float(l.r) * o.stat(&"op_range") - 3.0
		chain(r, o.cv, hand, e.pos + Vector2(0, -float(e.r) * 0.5), 1 if tight else 0, t, not tight)
	SU.hw_draw_mute(o, false)   # 沉默图标是状态提示，照画（拴链由上面画）
	for it in r.items:
		if str(it.get("ulrt", "")) == "link" and str(it.oid) == str(o.id):
			_draw_link(r, o, it)


## 后期冲击波（growth/late_shape → vis_growth._fire_qi，锚类 blunt）：排序项
static func sort_items(r, o, out: Array) -> void:
	if r.mode() != 1 or o.vg.is_empty() or not o.vg.has("qi"):
		return
	for q in o.vg.qi:
		var p: Vector2 = r._qpos(q)
		out.append({"ulrt": "qi", "q": q, "gp": p, "skey": p.y + 1.0, "oid": str(o.id), "tier": r.tier(o)})
		var bk = q.get("_ulb")   # 画面专用键（玩法不读）：这一道冲击波玩法上消失后原地碎开的件
		if bk == null:
			bk = {"ulrt": "qib", "t0": r.g.t, "life": 3.0, "ly": "up", "oid": str(o.id), "k": "", "gp": p, "gy": p.y + 1.0, "p": p, "v": q.v, "tier": r.tier(o), "seen": r.g.t, "sd": _h(p.x * 0.31 + p.y)}
			q["_ulb"] = bk
			r._push(bk)
			var R = load("res://scripts/render/fx_recipe.gd").of(r.g)
			R._light(o, p + Vector2(0, -8), 120.0, 0.55, 0.15, R.pal(o).get("light", C[5]))   # 出手一盏照地光
		bk.p = p
		bk.gp = p
		bk.gy = p.y + 1.0
		bk.seen = r.g.t


static func draw_rt(r, ci, it: Dictionary) -> void:
	match str(it.ulrt):
		"qi":
			_draw_qi(r, ci, it)
		"bub":
			_draw_bub(r, ci, it)
		"qib":
			_draw_qib(r, ci, it)
		"orca":
			_draw_orca(r, ci, it)


# ================================================================ 运行时件（逐美术像素，2 世界像素一格；15 fps 节拍换形）

## 锁链：a → b。每 4 格一组：两格正面链节（左右两侧各一点、中空）+ 一格侧面链节（中心亮）+ 一格连接；
## taut 0 = 松（细、暗）/ 1 = 常态 / 2 = 绷紧（一点白光沿链往回跑，进发光层）；精二链节多一点冷光
static func chain(r, ci, a: Vector2, b: Vector2, taut: int, tier: int, thin: bool) -> void:
	var g = r.g
	var px: float = g.PX
	var L: float = a.distance_to(b)
	if L < 2.0:
		return
	var d: Vector2 = (b - a) / L
	var nv := Vector2(-d.y, d.x)
	var n: int = int(L / px)
	var beat: int = int(floor(g.t * 15.0))
	var glint: int = (n - (beat * 5) % maxi(1, n + 8)) if taut == 2 else -99
	for i in n + 1:
		var p: Vector2 = r._snap(a + d * float(i) * px)
		if thin:
			r._px(ci, p, DUST[2] if i % 3 else DUST[4])
			continue
		var m: int = i % 4
		var body: Color = DUST[4] if taut > 0 else DUST[3]
		var hi: Color = DUST[5] if taut > 0 else DUST[4]
		if taut == 3:   # 绷直一闪：整条链亮
			body = C[6]
			hi = C[7]
			if i % 3 == 0:
				r._glow(p, C[6])
		elif absi(i - glint) <= 1:
			body = C[6]
			hi = C[7]
			r._glow(p, C[6])
		elif tier >= 2 and m == 2 and (i / 4 + beat) % 5 == 0:
			hi = C[6]
		match m:
			0, 1:
				r._px(ci, p + nv * px, body)
				r._px(ci, p - nv * px, DUST[2])
			2:
				r._px(ci, p, hi)
			3:
				r._px(ci, p, DUST[2])


## 被拖的怪身后的 V 字水沟：两道白沫线从起点往当前位置收拢（像船尾浪），中间一道暗水；到位后 WAKE_TAIL 秒降阶淡掉
static func _draw_wake(r, ci, it: Dictionary) -> void:
	var g = r.g
	var e: Dictionary = it.e
	var from: Vector2 = it.from
	if not it.has("to") or g.t <= float(it.t1):
		it["to"] = e.pos if not e.get("dead", false) else it.get("to", from)
	var to: Vector2 = it.to
	var age: float = g.t - float(it.t1)
	var fade: int = 0 if age < 0.0 else (1 if age < WAKE_TAIL * 0.5 else 2)
	_vwake(r, ci, from, to, int(it.get("w", 1)), fade, float(it.get("sd", 0.0)))


static func _vwake(r, ci, from: Vector2, to: Vector2, w: int, fade: int, sd: float) -> void:
	var g = r.g
	var px: float = g.PX
	var L: float = from.distance_to(to)
	if L < 6.0:
		return
	var d: Vector2 = (to - from) / L
	var nv := Vector2(-d.y, d.x * SY).normalized()
	var n: int = int(L / px)
	var foam: Color = [C[6], C[5], C[4]][fade]
	var dark: Color = [C[2], C[1], C[1]][fade]
	for i in n:
		var u: float = float(i) / float(maxi(1, n))   # 0 = 起点（最宽）→ 1 = 当前位置（收拢）
		var p: Vector2 = from + d * float(i) * px
		var spread: float = (1.0 - u) * (4.0 + 3.0 * w) + 1.5
		if _h(float(i) * 0.71 + sd) > 0.18:
			r._px(ci, p + nv * spread * px, foam)
			r._px(ci, p - nv * spread * px, foam if _h(float(i) * 1.3 + sd) > 0.25 else C[5])
		if i % 2 == 0:
			r._px(ci, p, dark)


## S3 深海拖痕：从起点到他当前位置（按玩法同一缓动 k²）一道深色水带——中间最暗、两侧暗水、边上断续的水光；
## 离他最近的一段边是白沫（新划开的），落地后整条一拍一拍冷下去（边先灭、中间最后）
static func _draw_zip(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var age: float = g.t - float(it.t0)
	var dur: float = float(it.dur)
	var k: float = clampf(age / maxf(0.001, dur), 0.0, 1.0)
	var a: Vector2 = it.a
	var b: Vector2 = a.lerp(it.b, k * k)
	var L: float = a.distance_to(b)
	if L < 4.0:
		return
	var d: Vector2 = (b - a) / L
	var nv := Vector2(-d.y, d.x * SY).normalized()
	var cool: float = maxf(0.0, age - dur) / TRAIL_COOL   # 0 → 1
	var n: int = int(L / px)
	for i in n:
		var p: Vector2 = a + d * float(i) * px
		var fresh: bool = (n - i) < 8 and cool <= 0.0
		var hs: float = _h(float(i) * 0.61 + 2.3)
		if hs < cool * 1.2 - 0.2:
			continue
		r._px(ci, p, C[0] if cool < 0.6 else C[1])
		if cool < 0.75:
			r._px(ci, p + nv * px, C[1])
			r._px(ci, p - nv * px, C[1])
		if cool < 0.45 and _h(float(i) * 0.37 + 5.1) > 0.3:
			r._px(ci, p + nv * 2.0 * px, C[5] if fresh else C[2])
		if cool < 0.45 and _h(float(i) * 0.83 + 1.7) > 0.3:
			r._px(ci, p - nv * 2.0 * px, C[6] if fresh else C[3])


## 暗流通路（通路洞开）：一道 2–3 格宽的深色水道，两侧断续白沫边，0.8 秒里先亮后冷
static func _draw_rift(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var L: float = a.distance_to(b)
	if L < 4.0:
		return
	var d: Vector2 = (b - a) / L
	var nv := Vector2(-d.y, d.x * SY).normalized()
	var age: float = g.t - float(it.t0)
	var grow: float = clampf(age / 0.12, 0.0, 1.0)
	var fade: int = 0 if age < 0.3 else (1 if age < 0.55 else 2)
	var n: int = int(L * grow / px)
	var sd: float = float(it.sd)
	for i in n:
		var u: float = float(i) / maxf(1.0, L / px)
		var p: Vector2 = a + d * float(i) * px + nv * (sin(sd * 10.0 + float(i) * 0.4) * 1.5 * px)
		var w: float = 1.0 + 1.5 * sin(u * PI)
		r._px(ci, p, [C[0], C[1], C[1]][fade])
		if w > 1.6:
			r._px(ci, p + nv * px, [C[1], C[1], C[2]][fade])
		if _h(float(i) * 0.53 + sd) > 0.35:
			r._px(ci, p + nv * (w + 1.0) * px, [C[6], C[5], C[3]][fade])
		if _h(float(i) * 0.91 + sd * 2.0) > 0.45:
			r._px(ci, p - nv * (w + 0.5) * px, [C[5], C[4], C[2]][fade])


## 通路上往上冒的水泡（一段一个排序项）：3×3 小环 + 高光，0.8 秒里升起、晃、破
static func _draw_bub(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var age: float = g.t - float(it.t0)
	var beat: int = int(floor(age * 15.0))
	var sd: float = float(it.sd)
	for j in 2:
		var b0: int = int(_h(sd + float(j)) * 4.0) + j * 3
		var bage: int = beat - b0
		if bage < 0 or bage > 6:
			continue
		var x: float = (_h(sd * 3.0 + float(j)) - 0.5) * 12.0 + sin(float(bage) * 0.9 + sd) * 1.5
		var p: Vector2 = r._snap((it.a as Vector2) + Vector2(x * px * 0.5, -6.0 - float(bage) * 5.0))
		if bage == 6:
			for q in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
				r._px(ci, p + q * px, C[5])
			continue
		for q in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
			r._px(ci, p + q * px, C[6] if q.y < 0.0 else C[5])
		r._px(ci, p + Vector2(-1, -1) * px, C[7])
		r._glow(p + Vector2(-1, -1) * px, C[6])


## 连携掷锚：锚从手里飞 0.2 秒到目标（锁链跟着）→ 钉住期间锁链绷着；钉下的水花 / 回卷由 ul_link_pin 的帧条画
static func _draw_link(r, o, it: Dictionary) -> void:
	var g = r.g
	var age: float = g.t - float(it.t0)
	var tg = it.get("tg")
	var tp: Vector2 = tg.pos if tg != null and not tg.dead else it.tp
	var fp: Vector2 = o.pos + Vector2(0, -20)
	var d: Vector2 = (tp - fp).normalized() if tp != fp else Vector2.RIGHT
	var SU = _segu()
	if age < 0.2:
		var q: Vector2 = (it.fp as Vector2).lerp(tp, age / 0.2)
		chain(r, o.cv, fp, q, 1, 1, false)
		SU._hw_draw_anchor(o, q, d, 1.0)
		return
	if age < 0.7:
		chain(r, o.cv, fp, tp + Vector2(0, -6), 2, 1, false)
		SU._hw_draw_anchor(o, tp + Vector2(0, -6), d, 1.0)


## 后期冲击波（锚类）：贴地往前推的一道低浪——浪身厚（沿前进方向 5–7 格）、前脸亮、背坡暗，中间高两头低，浪顶一线白（进发光层），
## 身后两道白沫拖痕。玩法上这一道只活约 0.18 秒，消失后原地再立 QI_BREAK 秒（_draw_qib：先站着、再塌成水点），总共约 0.35 秒
static func _draw_qi(r, ci, it: Dictionary) -> void:
	var q: Dictionary = it.q
	var d: Vector2 = (q.v as Vector2).normalized()
	_crest(r, ci, r._snap(it.gp), d, int(it.tier), float(q.t) < 1.0 / 15.0, float(q.get("o0", Vector2.ZERO).x) * 0.13, 1.0, true)


static func _crest(r, ci, c: Vector2, d: Vector2, tier: int, hot: bool, sd: float, k: float, wake: bool) -> void:
	var g = r.g
	var px: float = g.PX
	var nv := Vector2(-d.y, d.x * SY).normalized()
	var half: int = 12 + 3 * tier
	var H: float = (9.0 + 3.0 * float(tier)) * k
	var th: int = 5 + tier
	for s in range(-half, half + 1):
		var u: float = float(s) / float(half)
		var hh0: float = H * (1.0 - u * u) * (0.75 + 0.5 * _h(float(s) * 0.7 + sd))
		for j in range(th - 1, -1, -1):
			var base: Vector2 = c + nv * float(s) * px - d * float(j) * px
			var hh: int = int(round(hh0 * (1.0 - 0.6 * float(j) / float(th))))
			r._px(ci, base, C[1])
			for z in hh:
				var col: Color = (C[6] if z >= hh - 2 else C[5]) if j == 0 else (C[4] if j < th - 2 else C[3])
				r._px(ci, base + Vector2(0, -float(z + 1) * px), col)
			if j == 0 and hh > 0:
				var top: Vector2 = base + Vector2(0, -float(hh + 1) * px)
				r._px(ci, top, C[7])
				if absi(s) * 2 < half and (hot or (s & 1) == 0):
					r._glow(top, C[6])
	if wake:
		for j in range(th + 1, th + 12):
			var p: Vector2 = c - d * float(j) * px
			var w: float = float(half) * (1.0 - float(j - th) / 14.0)
			if _h(float(j) + sd) > 0.25:
				r._px(ci, p + nv * w * px, C[5] if j < th + 6 else C[4])
				r._px(ci, p - nv * w * px, C[5] if j < th + 6 else C[4])


## 锁链环（S2）：沿压扁的圈每 5 格一节，正面链节 = 3×2 实心块（上一排亮、下面一格暗影），侧面链节 = 一竖两格；
## rot 按 15 fps 节拍转；tone 0 常驻（暗、低调）/ 1 起手（亮）；精二一节冷光沿圈跑（进发光层）
static func _ring(r, ci, c: Vector2, R: float, rot: float, tone: int, tier: int) -> void:
	var g = r.g
	var px: float = g.PX
	var n: int = maxi(8, int(TAU * R / 5.0))
	var body: Color = DUST[4] if tone == 1 else DUST[3]
	var hi: Color = DUST[5] if tone == 1 else DUST[4]
	var gl: int = posmod(int(floor(g.t * 15.0)), n) if tier >= 2 else -1
	for i in n:
		var a: float = rot + TAU * float(i) / float(n)
		var p: Vector2 = r._snap(c + Vector2(cos(a) * R, sin(a) * R * SY) * px)
		var h2: Color = hi
		if i == gl:
			h2 = C[6]
			r._glow(p + Vector2(0, -px), C[6])
		if i % 2 == 0:
			for x in [-1, 0, 1]:
				r._px(ci, p + Vector2(x * px, 0), body)
				r._px(ci, p + Vector2(x * px, -px), h2)
			r._px(ci, p + Vector2(0, px), DUST[0])
		else:
			r._px(ci, p, DUST[2])
			r._px(ci, p + Vector2(0, -px), body)


## 后期冲击波玩法上消失后原地碎开（QI_BREAK 秒）：浪顶塌成一排白沫水点往前落，浪脚一摊暗水，照地光一盏
static func _draw_qib(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var gone: float = g.t - float(it.seen)
	if gone < 0.015:   # 这一道还活着（sort_items 每帧更新 seen）
		return
	if gone > QI_BREAK + 0.015:
		it["life"] = 0.0
		return
	if not it.get("lit", false):
		it["lit"] = true
		var R = load("res://scripts/render/fx_recipe.gd").of(g)
		var op = r._op(str(it.oid))
		if op != null:
			R._light(op, it.p + Vector2(0, -8), 110.0, 0.5, 0.12, R.pal(op).get("light", C[5]))
	var tier: int = int(it.tier)
	var d: Vector2 = (it.v as Vector2).normalized()
	var c: Vector2 = r._snap(it.p)
	var u: float = gone / QI_BREAK
	if u < 0.45:   # 先原地站一下（实心浪身，不出拖痕）
		_crest(r, ci, c, d, tier, false, float(it.sd), 1.0 - u * 0.6, false)
		return
	var nv := Vector2(-d.y, d.x * SY).normalized()
	var half: int = 12 + 3 * tier
	var v2: float = (u - 0.45) / 0.55   # 再塌成一排白沫水点往前落，浪脚一摊暗水
	for s in range(-half, half + 1):
		var w: float = 1.0 - pow(float(s) / float(half), 2.0)
		var hs: float = _h(float(s) * 1.7 + float(it.sd))
		var base: Vector2 = c + nv * float(s) * px + d * (v2 * 6.0 * hs) * px
		r._px(ci, base, C[1] if v2 < 0.6 else C[0])
		if hs < v2 * 0.8:
			continue
		var z: float = (6.0 + 3.0 * float(tier)) * w * (1.0 - v2) * (0.6 + 0.4 * hs)
		var top: Vector2 = base + Vector2(0, -z * px)
		r._px(ci, top, C[6] if v2 < 0.5 else C[5])
		if w > 0.5:
			r._px(ci, top + Vector2(px, 0), C[5])


## 虎鲸位置：[地面点, 离地高度（世界像素）, 俯仰（弧度，正 = 头朝下）]。
## 出手后沿锁链方向游到落点前 24 世界像素处（先快后慢），最后 ORCA_LEAP 秒跃起成弧、正好在玩法落地时刻砸到落点
static func _orca_pose(it: Dictionary, now: float) -> Array:
	var S: Vector2 = it.S
	var land: Vector2 = it.land
	var dv: Vector2 = it.dv
	var T1: float = float(it.T1)
	var P: Vector2 = land - dv * 24.0
	var tl: float = T1 - ORCA_LEAP
	if now < tl:
		var k: float = clampf((now - float(it.t0)) / maxf(0.01, tl - float(it.t0)), 0.0, 1.0)
		k = k * (2.0 - k)
		return [S.lerp(P, k), 4.0 + 3.0 * (1.0 - k), -0.15]
	var v: float = clampf((now - tl) / ORCA_LEAP, 0.0, 1.0)
	return [P.lerp(land, v), 4.0 + 44.0 * sin(v * PI), lerpf(-0.6, 0.8, v)]


## 虎鲸本体（逐美术像素栅格化；任意方向不转贴图）：黑背白腹、眼斑白、背鳍高、尾鳍分叉随节拍摆；
## 体长 44 美术像素（88 世界像素，< 冲锋路径与落地判定 140）；地上一块压扁的暗影，游的时候尾后一线白沫
static func _draw_orca(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var pose: Array = _orca_pose(it, g.t)
	var gpos: Vector2 = r._snap(pose[0])
	var z: float = float(pose[1])
	var dv: Vector2 = it.dv
	var e := Vector2(dv.x, dv.y * SY).normalized()
	var flip: float = 1.0 if e.x >= 0.0 else -1.0
	e = e.rotated(float(pose[2]) * flip)
	var n := Vector2(-e.y, e.x)
	if n.y > 0.0:
		n = -n
	var beat: int = int(floor(g.t * 15.0))
	# 地上暗影（离地越高越小）
	var sw: int = int(16.0 * (1.0 - clampf(z / 80.0, 0.0, 0.5)))
	for i in range(-sw, sw + 1):
		for j in [-1, 0, 1]:
			if absi(i) + absi(j) * 6 <= sw:
				r._px(ci, gpos + Vector2(float(i) * dv.x, float(i) * dv.y * SY + float(j)) * px, C[0])
	if z < 10.0:   # 贴着水面游：尾后白沫
		for i in range(14, 30):
			if _h(float(i) * 0.7 + float(beat)) > 0.45:
				r._px(ci, gpos - Vector2(dv.x, dv.y * SY) * float(i) * px + Vector2(0, -px), C[6] if i < 22 else C[5])
	var c: Vector2 = r._snap(gpos + Vector2(0, -z - 8.0))
	for jy in range(-16, 17):
		for ix in range(-26, 27):
			var q := Vector2(ix, jy)
			var u: float = q.dot(e)
			var w: float = q.dot(n)
			var k: int = _orca_cell(u, w, beat)
			if k >= 0:
				r._px(ci, c + q * px, ORCA[k])


## 虎鲸剖面：u 沿体长（尾 -22 → 吻 +22），w 垂直体长朝上（背）为正。返回 ORCA 色号，-1 = 不画
static func _orca_cell(u: float, w: float, beat: int) -> int:
	if u > 22.0 or u < -23.0:
		return -1
	var tw: float = sin(float(beat) * 1.8) * 1.5 if u < -12.0 else 0.0   # 尾部随节拍摆
	w -= tw
	var hh: float
	if u >= -10.0:
		hh = 7.0 * sqrt(maxf(0.0, 1.0 - pow((u - 4.0) / 18.0, 2.0)))
	elif u >= -18.0:
		hh = lerpf(1.6, 4.8, (u + 18.0) / 8.0)
	else:
		hh = 1.4 + (-18.0 - u) * 1.3   # 尾鳍张开
		if absf(w) < 1.0 and u < -21.0:
			return -1   # 尾鳍分叉
	var fin: float = 0.0
	if u > -4.0 and u < 5.0:
		fin = 10.0 * minf((u + 4.0) / 3.0, (5.0 - u) / 6.0)   # 背鳍：高、往后掠
	if w > hh + fin or w < -hh:
		return -1
	if w > hh:
		return 0   # 背鳍
	# 眼斑：眼后上方一块白椭圆
	if pow((u - 10.0) / 4.0, 2.0) + pow((w - 2.6) / 1.5, 2.0) <= 1.0:
		return 3
	# 腹部白（从下颌到腹部，往尾巴收窄）
	if w < -hh * 0.2 and u > -9.0:
		return 4 if w > -hh * 0.45 else 3
	# 鞍斑（背鳍后）
	if u > -9.0 and u < -3.0 and w > hh - 2.2:
		return 5
	if w > hh - 1.0:
		return 2   # 背脊受光
	return 1 if w > 0.0 else 0
