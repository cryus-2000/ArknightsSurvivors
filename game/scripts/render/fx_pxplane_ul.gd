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

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/282 §2）
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
const ORCA_LEAP := 0.18   # 虎鲸到落点前跃起的时长（落下那一刻 = 玩法落地重击）
const ORCA_H := 64.0     # 弧顶离地（世界像素）
const SWING_LIFE := 0.2   # 挥锚弧的时长（短而急）
const SLAM_KEEP := 2   # 同一名干员同屏至多两记锚击水冠（最新 + 正在收的）

static var _SegU = null


static func _segu():
	if _SegU == null:
		_SegU = load("res://scripts/characters/blocks/seg_ulpianus.gd")   # 运行时取（避免和积木链循环 preload）
	return _SegU


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _bucket(v: float, opts: Array) -> int:
	return PxU.nearest(opts, v)


static func _strip(r, o, k: String, at: Vector2, ly: String, follow := false, extra := {}) -> void:
	var it := {"k": "ul_" + k, "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	it.merge(extra, true)
	r._push(it)


## 帧条起点对齐 15 fps 拍：这一拍剩下不到半拍就从下一拍开始（第 0 帧占满一整拍），否则从这一拍开始
static func _beat_t0(g) -> float:
	var b: float = g.t * 15.0
	return (ceilf(b) if b - floorf(b) > 0.5 else floorf(b)) / 15.0


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
		"ul_breach":   # S3 虎鲸（docs/266 §8）掷锚出手：身前破水
			var fr: Vector2 = d.from
			var dv0: Vector2 = ((d.to as Vector2) - fr).normalized() if (d.to as Vector2).distance_to(fr) > 1.0 else Vector2(o.face, 0)
			_pair(r, o, "bite_r22", fr + dv0 * 20.0)
			R._grains(o, fr + dv0 * 20.0 + Vector2(0, -10), fr.y + 2.0, "ink", 4, {"tier": 2})
			_rt(r, o, "swing", "up", SWING_LIFE, {"c": fr, "dv": dv0, "gp": fr, "gy": fr.y + 1.5})   # 挥锚：锚尖从地上抡起一道带水的弧（docs/266 §10）
		"ul_orca":   # 虎鲸出发（docs/266 §9：不再画整条拖痕，免得读成他冲出去；尾后白沫与水滴在 _draw_orca 里）
			pass
		"ul_bite":   # 锚咬地（S1 掷锚落点；S3 旧冲锋版。S3 虎鲸不经过这里）
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
		"ul_land":
			var c2: Vector2 = d.c
			if d.get("s3", false):
				if g.ult != null and not MI.on(g):   # 虎鲸砸下那一拍轻震（打击感包开着时它已经震了）
					g.ult.shake(3.0, 0.12)
				var an6: Dictionary = o.hw.get("anchor", {})
				var dv6: Vector2 = ((an6.land as Vector2) - (an6.S as Vector2)).normalized() if an6.has("S") and (an6.land as Vector2).distance_to(an6.S) > 1.0 else Vector2(o.face, 0)
				_rt(r, o, "shatter", "up", 2.0 / 15.0 + 0.02, {"gp": c2, "gy": c2.y + 2.0, "dv": dv6, "t0": _beat_t0(g)})
				var bt0: float = _beat_t0(g)   # 爆点第 1 帧（最亮）要占满一拍
				var s3k: String = "s3_r%d" % _bucket(float(d.r) * 0.5, [70, 85])
				_strip(r, o, s3k + "_up", c2, "up", false, {"t0": bt0})
				_strip(r, o, s3k + "_gd", c2, "gd", false, {"t0": bt0})
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
	var an5: Dictionary = o.hw.get("anchor", {})
	if not an5.is_empty() and an5.get("orca", false):   # S3 预兆：落点一道断续细环（判定半径），砸地时由 s3_gd 的实环接手
		_telegraph(r, cv, o, an5)
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
	if h.has("anchor") and not h.anchor.is_empty() and h.anchor.get("orca", false):   # S3 虎鲸：不画锚和锁链；虎鲸贴水游时每拍身边甩两颗水滴
		var an3: Dictionary = h.anchor
		if str(an3.phase) == "orca" and r.mode() == 1 and float(an3.t) < float(an3.dur) - SU.ORCA_LEAP:
			var beat3: int = int(floor(g.t * 15.0))
			if int(an3.get("_pxb", -1)) != beat3:
				an3["_pxb"] = beat3
				var R3 = load("res://scripts/render/fx_recipe.gd").of(g)
				var hp3: Vector2 = an3.head
				R3._grains(o, hp3 + Vector2(0, -8), hp3.y + 2.0, "ink", 2, {"tier": 2, "grain_spd": 0.8}, -(((an3.land as Vector2) - (an3.S as Vector2)).normalized()))
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
	if r.mode() != 1:
		return
	var an: Dictionary = o.hw.get("anchor", {})
	if not an.is_empty() and an.get("orca", false):
		var tq: float = floorf(float(an.t) * 15.0) / 15.0   # 按 15 fps 节拍取姿势
		for gi in [2, 1, 0]:   # 身后 2 帧残影（逐帧变淡）+ 本体
			var pose: Array = _orca_pose_t(o, an, tq - float(gi) / 15.0)
			if not pose.is_empty():
				var oi := {"ulrt": "orca", "gp": pose[0], "z": pose[1], "pitch": pose[2], "dv": pose[3], "clip": pose[4], "ghost": gi, "skey": (pose[0] as Vector2).y + 1.0 - 0.01 * float(gi), "oid": str(o.id)}
				if gi == 0:
					oi["op"] = o
					oi["an"] = an
					oi["tq"] = tq
				out.append(oi)
	if o.vg.is_empty() or not o.vg.has("qi"):
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
		"shatter":
			_draw_shatter(r, ci, it)
		"swing":
			_draw_swing(r, ci, it)


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
	var b: Vector2 = a.lerp(it.b, k * (2.0 - k) if it.get("ease_out", false) else k * k)   # 虎鲸先快后慢 / 冲锋 k²
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


## 虎鲸位置（读玩法状态 o.hw.anchor，docs/266 §8）：[地面点, 离地高度（世界像素）, 俯仰（正 = 头朝下）, 前进方向, 是否只画水面以上]。
## 掷锚那段（throw）：在身前 20 处从水里冒出来（往上升、水面以下不画）；orca 段：游的位置 = 玩法结算用的同一个 orca_head，跃起那 ORCA_LEAP 秒成弧、正好在落地重击那一刻砸到落点
## 某一时刻的虎鲸（读玩法状态 an，t = 该阶段内的时刻；残影用更早的时刻）：[地面点, 离地高度, 俯仰（正 = 头朝下）, 前进方向, 是否只画水面以上]。
## 节奏按 15 fps（docs/266 §11）：掷锚段末 2 帧破水 → 划弧（其余时间）→ 顶点停 2 帧（第 1 帧多冲 1 美术像素）→ 下砸 1 帧 → 落地（玩法落地重击）
static func _orca_pose_t(o, an: Dictionary, t: float) -> Array:
	var SU = _segu()
	var to: Vector2 = an.to
	if str(an.phase) == "throw":
		var dv: Vector2 = (to - o.pos).normalized() if to.distance_to(o.pos) > 1.0 else Vector2(o.face, 0)
		var tb: float = float(an.dur) - 2.0 / 15.0   # 末 2 帧破水
		if t < tb:
			return []
		var k: float = clampf((t - tb) / (2.0 / 15.0), 0.0, 1.0)
		return [o.pos + dv * 20.0, lerpf(-22.0, 4.0, k), -0.55, dv, true]   # 斜着把头顶出水弧
	if str(an.phase) != "orca" or t < 0.0:
		return []
	var dv2: Vector2 = ((an.land as Vector2) - (an.S as Vector2)).normalized() if (an.land as Vector2).distance_to(an.S) > 1.0 else Vector2(o.face, 0)
	var head: Vector2 = _head_at(an, t)   # 地面投影 = 玩法路径结算点
	var dur: float = float(an.dur)
	var B: float = 1.0 / 15.0
	var t_slam: float = dur - B
	var t_hold: float = t_slam - 2.0 * B
	if t < t_hold:
		var s0: float = clampf(t / maxf(0.001, t_hold), 0.0, 1.0)
		return [head, lerpf(14.0, ORCA_H, 1.0 - (1.0 - s0) * (1.0 - s0)), lerpf(-0.75, 0.0, s0), dv2, false]
	if t < t_slam:
		return [head, ORCA_H + (2.0 if t < t_hold + B else 0.0), 0.08, dv2, false]   # 顶点停 2 帧，第 1 帧多冲 1 美术像素
	return [head, ORCA_H * 0.35, 1.3, dv2, false]   # 下砸 1 帧：头朝下


## 同 seg_ulpianus.orca_head，但取任意时刻（残影用）
static func _head_at(an: Dictionary, t: float) -> Vector2:
	var L: float = _segu().ORCA_LEAP
	var sw: float = float(an.dur) - L
	if t <= sw:
		var k: float = clampf(t / maxf(0.001, sw), 0.0, 1.0)
		return (an.S as Vector2).lerp(an.P, k * (2.0 - k))
	return (an.P as Vector2).lerp(an.land, clampf((t - sw) / L, 0.0, 1.0))


## 落点预兆：判定半径上一道断续细环（1 美术像素，按节拍转），掷锚到落地前一直在
static func _telegraph(r, ci, o, an: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var dv: Vector2 = ((an.to as Vector2) - o.pos).normalized() if (an.to as Vector2).distance_to(o.pos) > 1.0 else Vector2(o.face, 0)
	var c: Vector2 = an.get("land", (an.to as Vector2) - dv * 18.0)
	var R: float = float(an.get("orca_r", an.b.get("r", 140.0))) * o.stat(&"op_range") * 0.5   # 美术像素（虎鲸范围 s3_orca_r，docs/266 §20）
	var n: int = int(TAU * R / 2.0)
	var beat: int = int(floor(g.t * 15.0))
	for i in n:
		if ((i + beat) / 3) % 2 == 1:
			continue
		var a: float = TAU * float(i) / float(n)
		r._px(ci, r._snap(c + Vector2(cos(a) * R, sin(a) * R * SY) * px), C[4])


## 水做的虎鲸（docs/266 §16，用户 11-05「把生图的当作形状约束，然后来做我们自己的」「还是显得有点实」）：
## 剪影来自生图（A3 空中 / D3 俯冲，tools/pxplane_orcamask_ulpianus.py 烘成 pxp_ul_orcam_<姿态>_a<角度>.png：RGB = 生图明暗、A = 遮罩，
## 15° 一档预旋转、1 美术像素一格，外框宽 100 美术像素 = 200 世界像素），里面是程序水（Python 试样 draw_shape_whale 的同一算法）：
##   通透的水壳——暗 / 次暗两阶半透明（α 0.4 / 0.5），只有沿生图亮带走、按节拍往尾巴流的细亮带（隔一条）、上沿浪边、3 个小漩涡、气泡是实的；
##   腹部下沿断开变淡；每拍 6–10 颗 1–3 像素带短尾的水珠往后往上飞；尾后一股上粗下细的水柱连到地面，落地处一小圈水花。
## 破水（clip）：地面拉起一段水柱、虎鲸头朝上在柱子上方。ghost > 0 = 残影：只画身体，逐帧变淡
const W4 := [Color("#10409c"), Color("#1896e2"), Color("#60d6fa"), Color("#cefaff")]   # 照 A3：深海蓝 / 饱和青 / 亮青 / 亮青白
const ORCA_STEP := 15
static var _ORCAM := {}


## 遮罩缓存：{w, h, img, pts: [x, y, …], lum: […]}；没有帧条时空字典（不画）
static func _orcam(pose: String, ang: int) -> Dictionary:
	var key: String = "%s_%d" % [pose, ang]
	if _ORCAM.has(key):
		return _ORCAM[key]
	var path: String = "res://art/fx/pxp/pxp_ul_orcam_%s_a%s.png" % [pose, ("m%d" % -ang) if ang < 0 else str(ang)]
	var d := {}
	if ResourceLoader.exists(path):
		var tx = load(path)
		var img: Image = tx.get_image() if tx is Texture2D else null
		if img != null:
			if img.is_compressed():
				img.decompress()
			var w: int = img.get_width()
			var h: int = img.get_height()
			var pts := PackedInt32Array()
			var lum := PackedFloat32Array()
			for y in h:
				for x in w:
					var px: Color = img.get_pixel(x, y)
					if px.a > 0.5:
						pts.append(x)
						pts.append(y)
						lum.append(px.r)
			var th0: float = deg_to_rad(float(ang))
			var umin: float = 1e9
			var umax: float = -1e9
			var tail := Vector2i(0, 0)
			var head := Vector2i(0, 0)
			for i in lum.size():
				var uu: float = float(pts[i * 2] - w / 2) * cos(th0) + float(pts[i * 2 + 1] - h / 2) * sin(th0)
				if uu < umin:
					umin = uu
					tail = Vector2i(pts[i * 2], pts[i * 2 + 1])
				if uu > umax:
					umax = uu
					head = Vector2i(pts[i * 2], pts[i * 2 + 1])
			d = {"w": w, "h": h, "img": img, "pts": pts, "lum": lum, "tail": tail, "head": head, "umin": umin, "umax": umax}
	_ORCAM[key] = d
	return d


## 某一姿势下的遮罩与摆放：{m, q, flip, c（遮罩中心的世界点）, z, pitch}；破水（clip）时同 _draw_orca 的调整
static func _orca_geom(r, gp: Vector2, z: float, pitch: float, dv: Vector2, clip: bool) -> Dictionary:
	if clip:
		z += 6.0
		pitch = -0.8
	var e0 := Vector2(dv.x, dv.y * SY).normalized()
	var flip: bool = e0.x < 0.0
	var ang: float = rad_to_deg(atan2(e0.y, absf(e0.x))) + rad_to_deg(pitch)
	var q: int = clampi(int(round(ang / float(ORCA_STEP))) * ORCA_STEP, -90, 90)
	var m: Dictionary = _orcam("dive" if pitch > 0.6 else "apex", q)
	if m.is_empty():
		return {}
	return {"m": m, "q": q, "flip": flip, "c": r._snap(r._snap(gp) + Vector2(0, -z - float(m.h))), "z": z, "pitch": pitch}


## 尾鳍末端的世界点
static func _orca_tail(r, geo: Dictionary) -> Vector2:
	var m: Dictionary = geo.m
	var w: int = int(m.w)
	var tl: Vector2i = m.tail
	var xx: int = (w - 1 - tl.x) if geo.flip else tl.x
	return (geo.c as Vector2) + Vector2(xx - w / 2, tl.y - int(m.h) / 2) * r.g.PX


## 尾后水流 = 受重力的粒子拖尾（docs/266 §18，用户「到中间的时候那个没有跟着身体合物理规律走」）：
## 过去 8 拍里每拍从当时的尾鳍末端放出 3 颗（1 团 2 格 + 2 滴 1 格），初速 = 尾巴当时运动方向的反方向 × 80 + 向下 30（世界像素 / 秒），
## 之后受重力（700）按抛物线落，落到放出时那一拍的地面线就变成白沫点，0.15 秒后消失；顶点停住时照样往下落（读出惯性），俯冲时自然甩向上后方。
## 不画连到出发点的固定水柱。纯按时刻算（不存状态、不抽随机数）
static func _draw_trail(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var o = it.op
	var an: Dictionary = it.an
	var tq: float = float(it.tq)
	var B: float = 1.0 / 15.0
	for k in range(1, 9):
		var te: float = tq - float(k) * B
		var p0: Array = _orca_pose_t(o, an, te)
		var p1: Array = _orca_pose_t(o, an, te - B)
		if p0.is_empty() or p1.is_empty() or p0[4]:
			continue
		var g0: Dictionary = _orca_geom(r, p0[0], float(p0[1]), float(p0[2]), p0[3], p0[4])
		var g1: Dictionary = _orca_geom(r, p1[0], float(p1[1]), float(p1[2]), p1[3], p1[4])
		if g0.is_empty() or g1.is_empty():
			continue
		var t0: Vector2 = _orca_tail(r, g0)
		var vel: Vector2 = (t0 - _orca_tail(r, g1)) / B
		var dirv: Vector2 = vel.normalized() if vel.length() > 1.0 else Vector2.ZERO
		var yg: float = float((p0[0] as Vector2).y)
		var age: float = float(k) * B
		for j in 3:
			var hj: float = _h(float(k) * 1.37 + float(j) * 4.1 + floorf(te * 15.0) * 0.53)
			var v: Vector2 = -dirv * (60.0 + 40.0 * hj) + Vector2((hj - 0.5) * 40.0, 30.0)
			var p: Vector2 = t0 + v * age + Vector2(0, 0.5 * 700.0 * age * age)
			if p.y >= yg:   # 已落地：落点处一点白沫，0.15 秒后消失
				var a_l: float = _land_age(t0.y, v.y, yg)
				if age - a_l < 0.15:
					var pl: Vector2 = t0 + Vector2(v.x * a_l, yg - t0.y)
					r._px(ci, pl, W4[3] if j == 0 else W4[2])
				continue
			var col: Color = W4[3] if k <= 2 else (W4[2] if k <= 5 else W4[1])
			r._px(ci, p, col)
			if j == 0:   # 水团：2 格 + 逆着运动的短尾
				r._px(ci, p + Vector2(px, 0), col)
				r._px(ci, p + Vector2(0, px), W4[2])
			var vn2: Vector2 = (v + Vector2(0, 700.0 * age)).normalized()
			r._px(ci, p - vn2 * px * 1.5, W4[2] if k <= 3 else W4[1])


## 抛物线落到 yg 用的时间（y0 + vy·a + 350·a² = yg 的正根）
static func _land_age(y0: float, vy: float, yg: float) -> float:
	var A: float = 350.0
	var D: float = vy * vy + 4.0 * A * (yg - y0)
	if D < 0.0:
		return 0.0
	return (-vy + sqrt(D)) / (2.0 * A)


## 砸地后鲸身余下的后半截在落点碎开（2 拍）：从头往尾一截截消失，断口处碎成亮青水花往外甩
static func _draw_shatter(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var k: int = clampi(r.frame_of(float(it.t0)), 0, 1)
	var geo: Dictionary = _orca_geom(r, it.gp, ORCA_H * 0.15, 1.3, it.dv, false)
	if geo.is_empty():
		return
	var m: Dictionary = geo.m
	var w: int = int(m.w)
	var h: int = int(m.h)
	var th: float = deg_to_rad(float(geo.q))
	var cut: float = [0.5, 0.22][k]
	var hd: Vector2i = m.head   # 整只挪到让吻扎在落点，余下的身子往里沉
	var hxx: int = (w - 1 - hd.x) if geo.flip else hd.x
	var hw: Vector2 = (geo.c as Vector2) + Vector2(hxx - w / 2, hd.y - h / 2) * px
	geo["c"] = (geo.c as Vector2) + (r._snap(it.gp) + Vector2(0, -4.0 + 6.0 * float(k) * px) - hw)
	var pts: PackedInt32Array = m.pts
	var lums: PackedFloat32Array = m.lum
	var span: float = maxf(1.0, float(m.umax) - float(m.umin))
	for i in lums.size():
		var x: int = pts[i * 2]
		var y: int = pts[i * 2 + 1]
		var u: float = float(x - w / 2) * cos(th) + float(y - h / 2) * sin(th)
		var un: float = (u - float(m.umin)) / span
		if un > cut + 0.08:
			continue
		var xx: int = (w - 1 - x) if geo.flip else x
		var pp: Vector2 = r._snap((geo.c as Vector2) + Vector2(xx - w / 2, y - h / 2) * px)
		if un > cut:   # 断口：碎成水花往外甩
			if _h(float(i) * 0.37 + float(k)) > 0.5:
				r._px(ci, pp + Vector2((_h(float(i)) - 0.5) * 8.0, -_h(float(i) * 1.7) * 4.0) * px, W4[3])
			continue
		r._px(ci, pp, Color(W4[2] if lums[i] > 0.5 else W4[1], 0.75 - 0.25 * float(k)))


static func _om_in(m: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < int(m.w) and y < int(m.h) and (m.img as Image).get_pixel(x, y).a > 0.5


static func _draw_orca(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var gpos: Vector2 = r._snap(it.gp)
	var z: float = float(it.z)
	var pitch: float = float(it.pitch)
	var dv: Vector2 = it.dv
	var ghost: int = int(it.get("ghost", 0))
	var beat: int = int(floor(g.t * 15.0))
	if it.clip:   # 破水：地面拉起一段水柱，鲸在柱子上方、头朝上
		if ghost == 0:
			_breach_column(r, ci, gpos, clampf((z + 22.0) / 26.0, 0.0, 1.0), beat)
		z += 6.0
		pitch = -0.8
	var e0 := Vector2(dv.x, dv.y * SY).normalized()
	var flip: bool = e0.x < 0.0
	var base: float = rad_to_deg(atan2(e0.y, absf(e0.x)))
	var ang: float = base + rad_to_deg(pitch)
	var pose: String = "dive" if pitch > 0.6 else "apex"
	var q: int = clampi(int(round(ang / float(ORCA_STEP))) * ORCA_STEP, -90, 90)
	var m: Dictionary = _orcam(pose, q)
	if m.is_empty():
		return
	var w: int = int(m.w)
	var h: int = int(m.h)
	var th: float = deg_to_rad(float(q))
	var e := Vector2(cos(th), sin(th))
	var n := Vector2(sin(th), -cos(th))
	var sx: float = -1.0 if flip else 1.0
	var c: Vector2 = r._snap(gpos + Vector2(0, -z - float(h)))
	var cx: int = w / 2
	var cy: int = h / 2
	if ghost == 0 and z > 6.0:   # 地上的水影（随高度缩放）
		var sk: float = clampf(1.0 - z / 220.0, 0.45, 1.0)
		var rx: float = 30.0 * sk
		var ry: float = 7.0 * sk
		for iy in range(-int(ry), int(ry) + 1):
			for ix in range(-int(rx), int(rx) + 1):
				if pow(float(ix) / rx, 2.0) + pow(float(iy) / ry, 2.0) <= 1.0:
					r._px(ci, gpos + Vector2(ix, iy) * px, Color("#0a1e46", 0.4))
	var ga: float = [1.0, 0.3, 0.15][clampi(ghost, 0, 2)]
	var flow: int = (beat * 2) % 12
	var pts: PackedInt32Array = m.pts
	var lums: PackedFloat32Array = m.lum
	var img: Image = m.img
	var tops: Array = []
	var tail := Vector2i(-1, -1)
	var best_tail: float = 1e9
	for i in lums.size():
		var x: int = pts[i * 2]
		var y: int = pts[i * 2 + 1]
		var xx: int = (w - 1 - x) if flip else x
		var pp: Vector2 = c + Vector2(xx - cx, y - cy) * px
		if ghost > 0:
			r._px(ci, pp, Color(W4[1], 0.3 * ga))
			continue
		var ox: float = float(x - cx)
		var oy: float = float(y - cy)
		var u: float = ox * e.x + oy * e.y
		var vv: float = ox * n.x + oy * n.y
		if u < best_tail:
			best_tail = u
			tail = Vector2i(xx, y)
		if not _om_in(m, x, y - 1):   # 上沿：实、亮
			r._px(ci, pp, W4[3])
			tops.append(Vector2i(xx, y))
			if (x & 1) == 0:
				r._glow(pp, W4[3])
			continue
		if not _om_in(m, x, y + 1):   # 腹部下沿：断开、变淡
			if _h(float(x) * 0.9 + float(beat) * 0.5) > 0.45:
				r._px(ci, pp, Color(W4[2], 0.55))
			continue
		if not _om_in(m, x - 1, y) or not _om_in(m, x + 1, y):
			r._px(ci, pp, W4[2])
			continue
		if pitch > 1.2:   # 下砸那一帧：头部先碎开（前 30% 只剩散开的亮青水花）
			var un: float = (u - float(m.umin)) / maxf(1.0, float(m.umax) - float(m.umin))
			if un > 0.7:
				if _h(float(i) * 0.53 + float(beat)) > 0.55:
					r._px(ci, pp + Vector2(0, (un - 0.7) * 20.0) * px, W4[3])
				continue
		var sxp: int = int(round(float(x) + e.x * float(flow)))
		var syp: int = int(round(float(y) + e.y * float(flow)))
		var L: float = img.get_pixel(sxp, syp).r if _om_in(m, sxp, syp) else lums[i]
		L = 0.65 * L + 0.35 * lums[i]
		var lane: int = int(floor(vv * 0.8 + 2.2 * sin(u * 0.13 - float(beat) * 0.35)))
		if L > 0.5 and posmod(lane, 2) == 0:   # 细而稀的亮带（实）
			r._px(ci, pp, W4[3] if L > 0.7 else W4[2])
			if L > 0.7 and (x + y + beat) % 3 == 0:
				r._glow(pp, W4[3])
		elif L > 0.22:
			r._px(ci, pp, Color(W4[1], 0.5))
		else:
			r._px(ci, pp, Color(W4[0], 0.4))   # 透出地面和怪
	if ghost > 0 or tops.is_empty():
		return
	# 3 个小漩涡（实）
	var fus := [0.7, 0.45, 0.22]
	for i in 3:
		var ux: float = (float(fus[i]) - 0.5) * float(w)
		var vy: float = (-1.0 if i == 1 else 1.0) * float(h) * 0.06
		var px0: float = float(cx) + (ux * e.x + vy * n.x) * sx
		var py0: float = float(cy) + ux * e.y + vy * n.y
		var xm: int = int((float(w - 1) - px0) if flip else px0)
		if not _om_in(m, xm, int(py0)):
			continue
		var rot: float = float(beat) * 0.9 + float(i) * 2.1
		for j in 7:
			var a: float = rot + float(j) * 0.75
			var rr: float = 1.0 + float(j) * 0.42
			r._px(ci, c + Vector2(px0 - float(cx) + cos(a) * rr, py0 - float(cy) + sin(a) * rr * 0.8) * px, W4[3] if j > 4 else W4[2])
	# 3 个往上漂的气泡
	for i in 3:
		var ph: int = (beat + i * 3) % 8
		var fx: float = 0.3 + 0.2 * float(i)
		var bx0: float = float(cx) + (fx - 0.5) * float(w) * e.x * sx
		var by0: float = float(cy) + (fx - 0.5) * float(w) * e.y - float(ph) * 1.6
		var xm2: int = int((float(w - 1) - bx0) if flip else bx0)
		if not _om_in(m, xm2, int(by0)):
			continue
		var bp: Vector2 = c + Vector2(bx0 - float(cx), by0 - float(cy)) * px
		if i % 2 == 0:
			for d4 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				r._px(ci, bp + d4 * px, W4[3])
		else:
			r._px(ci, bp, W4[3])
	# 每拍 6–10 颗水珠（1–3 像素、带短尾），从上沿 / 鳍尖往后往上飞，3 拍落下
	var nd: int = 6 + int(_h(float(beat) * 0.91) * 5.0)
	var tsorted: Array = tops.duplicate()
	tsorted.sort_custom(func(a, b): return a.y < b.y)
	for k in nd:
		for ph in 3:
			var sd: float = float(k) * 3.7 + float(beat - ph) * 0.41
			var src: Vector2i = tsorted[k] if k < 2 and k < tsorted.size() else tops[int(_h(sd + 5.0) * float(tops.size())) % tops.size()]
			var back: float = 2.0 + float(ph) * 3.0 + _h(sd) * 4.0
			var upz: float = 2.0 + float(ph) * 3.0 - float(ph * ph) * 1.3 + _h(sd + 1.0) * 3.0
			var dp: Vector2 = c + Vector2(float(src.x - cx) - e.x * back * sx, float(src.y - cy) - upz - e.y * back) * px
			var size: int = maxi(1, 1 + int(_h(sd + 2.0) * 3.0) - ph)
			var col: Color = W4[3] if ph == 0 else (W4[2] if ph == 1 else W4[1])
			for qx in size:
				for qy in size:
					r._px(ci, dp + Vector2(qx, qy) * px, col)
			for tt in [1, 2]:
				r._px(ci, dp + Vector2(e.x * sx * float(tt), float(tt) * 0.8 + e.y * float(tt)) * px, W4[2])
	if it.has("an"):
		_draw_trail(r, ci, it)


## 破水：从地面拉起一段水柱（k = 破水进度 0..1），边上白沫，四周溅水
static func _breach_column(r, ci, gp: Vector2, k: float, beat: int) -> void:
	var px: float = r.g.PX
	var hgt: float = 10.0 + 24.0 * k
	for zz in int(hgt):
		var half: float = 5.0 - float(zz) * 0.08 + sin(float(zz) * 0.5 - float(beat)) * 1.0
		for x in range(-int(half), int(half) + 1):
			var p := gp + Vector2(float(x) + float(zz) * 0.5, -float(zz)) * px
			if absi(x) >= int(half):
				r._px(ci, p, W4[3] if _h(float(zz) * 1.3 + float(beat)) > 0.4 else W4[2])
			else:
				r._px(ci, p, Color(W4[2] if (x + zz + beat) % 5 == 0 else W4[1], 0.6))
	for j in 8:
		var a: float = _h(float(j) * 2.1 + float(beat)) * PI
		var rr: float = 6.0 + _h(float(j) + float(beat) * 0.7) * 10.0
		r._px(ci, gp + Vector2(cos(a) * rr * (1.0 if j % 2 == 1 else -1.0), -sin(a) * rr * 0.8) * px, W4[3] if j % 2 == 1 else W4[2])


## 挥锚（S3 起手）：锚尖从他身前的地面抡起一道带水的弧（竖直面内，0.2 秒从前下方扫到头顶后方），弧头白、往后降阶，
## 沿弧切向甩出水滴；虎鲸就从弧起点那块地面跃出。本体动作贴图不改
static func _draw_swing(r, ci, it: Dictionary) -> void:
	var g = r.g
	var px: float = g.PX
	var age: float = g.t - float(it.t0)
	var dv: Vector2 = it.dv
	var hs := Vector2(dv.x, dv.y * SY).normalized()
	var piv: Vector2 = (it.c as Vector2) + Vector2(0, -20)
	var Ra: float = 30.0
	var kk: float = clampf(age / 0.1, 0.0, 1.0)   # 0.1 秒扫完（短而急）
	var th_h: float = lerpf(-0.75, 2.5, 1.0 - (1.0 - kk) * (1.0 - kk))   # 弧头角（弧度，0 = 正前方水平，正 = 往上）
	var fade: int = 0 if age < 0.1 else (1 if age < 0.15 else 2)
	var th0: float = maxf(-0.75, th_h - 1.9)
	var steps: int = int((th_h - th0) * Ra / px) + 1
	for i in steps:
		var th: float = th_h - float(i) * px / Ra
		var v: float = float(i) / float(maxi(1, steps))
		var p: Vector2 = piv + hs * cos(th) * Ra + Vector2(0, -sin(th) * Ra)
		var col: Color = C[5] if v < 0.35 else (C[4] if v < 0.7 else C[3])
		if fade == 1:
			col = C[5] if v < 0.5 else C[4]
		elif fade == 2:
			if _h(float(i) * 0.7) < 0.5:
				continue
			col = C[4]
		r._px(ci, p, col)
		if v < 0.5 and fade == 0:   # 2 格厚（往外一格）
			r._px(ci, piv + hs * cos(th) * (Ra + px) + Vector2(0, -sin(th) * (Ra + px)), C[5])
			if v < 0.12:
				r._glow(p, C[6])
	if fade < 2:   # 沿弧切向甩出的水滴
		var beat: int = int(floor(g.t * 15.0))
		for j in 5:
			var th2: float = th_h - _h(float(j) * 2.3 + float(beat)) * 1.2
			var out: float = Ra + 4.0 + _h(float(j) + float(beat) * 0.9) * 10.0
			r._px(ci, piv + hs * cos(th2) * out + Vector2(0, -sin(th2) * out), C[6] if j % 2 == 0 else C[5])
