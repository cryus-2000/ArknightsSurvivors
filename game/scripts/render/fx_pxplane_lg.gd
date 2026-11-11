## 逻各斯（docs/258，照斯卡蒂 docs/246 / 流明 docs/255 的做法）
## 帧条件（tools/pxplane_bake_logos.py，键前缀 lg_）：命中星芒 + 碎刺 / 地面墨环、出手笔光 + 字环、提喻每跳、殁亡交叉咒文链 + 墨柱、延异视阈起手。
## 运行时逐格画（2 世界像素一格，方向任意、不旋转贴图，形状按 15 fps 节拍换）：「言」墨迹彗星（白头尖细 + 深蓝墨尾）、提喻咒文行、连缀咒文链、
## 殁亡溢出跳转笔、咒域（只画边 + 淡渐变 + 外沿细字行）、连携字环 / 消弹墨点、铭文 / 墓志铭地面咒文。咒文一律 3×5 细字（1 美术像素笔画）。
## 彗星位置每帧走、只取整到像素格（同流明光弹：按 15 fps 跳格会一卡一卡）。
## 旧做法（2）：旧放开版帧条（tools/pixelfx_fx/logos_ul_ref）光晕烤进颜色，小数缩放 + 旋转，盖在所有单位上。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const CUE = preload("res://scripts/render/fx_pxplane_cue.gd")   # 成长节点通用提示（docs/310 §2）   # 归溟幽灵鲨一节（docs/268）单独成文件
const LG_C := [Color("#28355f"), Color("#495694"), Color("#6a78ca"), Color("#8c99ff"), Color("#b4bdff"), Color("#dce0ff"), Color("#ffffff")]   # house.js OP.logos 7 阶
const LG_INK := [Color("#0b0d22"), Color("#161c3e")]   # 墨（压底两阶）
const LG_AC := Color("#a487ff")   # 精二点缀紫
const LG_GOLD := Color("#e8d6a0")   # 连携「黑金咒文」的淡金（只点在少数字上）
const LG_SY := 0.72
## 细字咒文 3×5（同 ak-logos-pp.js 的 GLYPHS）：每字 15 位，行优先
const LG_GL := ["111010010010011", "101111001001001", "110001010100011", "010111010010110", "100110101100111",
	"011100111001110", "101101010101101", "111100110100100", "010010111000101", "110101110100100"]
const LG_BOLT_LEN := [24, 28, 32]   # 墨尾长（美术像素，11-05 第四轮对原作：约 3/4 身高）：放大只放在长度上，弹头三档一样尖
## 延异视阈咒域（原作 range_01；11-05 第三轮用户「改成渐变填充」「符文条太直」）：
## 填充 = 亮蓝边缘往中心渐暗（7 阶，最浓 α 0.38，怪透得出来），每个美术像素按 interleaved gradient noise 抖动取相邻两阶，不出平涂色带；
## 外边 2 格亮边保留；域内随机冒出咒文段（第七轮：每段 6–10 字各走各的曲线，一个个写出来再扭一下，停 0.8–1.2 秒后逐字褪去，段尾细丝 + 墨点，部分字暗紫辉光，同屏至多 4 段）；每跳外边亮一拍
const LG_FILL := [[Color("#0b0d22"), 0.34], [Color("#161c3e"), 0.34], [Color("#28355f"), 0.32], [Color("#495694"), 0.33],
	[Color("#6a78ca"), 0.36], [Color("#8c99ff"), 0.38], [Color("#b4bdff"), 0.38]]
const LG_SEG_N := 4   # 咒文段同屏上限（第七轮：段变长，段数从 6 减到 4）
const LG_SEG_P := 2.1   # 每段一轮的秒数（书写 ≈ 0.4–0.6 秒 + 停 0.8–1.2 秒 + 褪去）
const LG_GLOW := Color("#6a4fc0")   # 咒文暗紫辉光（进发光层）


static func _lg_h(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)


static func _lg_up(pv: P, o, k: String, at: Vector2, gy: float, flip := false, follow := false) -> void:
	var g = pv.g
	if k.begins_with("hit_"):   # 同屏上限：主命中至多 3 团同时在画，再多换小一号；小一号至多 3 团（后期多弹不叠成一片白）
		var n := 0
		for it in pv.items:
			if str(it.oid) == "logos" and str(it.get("k", "")).begins_with("lg_hit_") and str(it.ly) == "up":
				n += 1
		if n >= (3 if pv.tier(o) < 1 else 2):   # 第六轮：精一 / 精二命中亮核大，怪群密时同屏主命中压到 2 团
			k = k.replace("hit_", "hits_")
	if k.begins_with("hits_"):
		var n2 := 0
		for it in pv.items:
			if str(it.oid) == "logos" and str(it.get("k", "")).begins_with("lg_hits_") and str(it.ly) == "up":
				n2 += 1
		if n2 >= 3:
			return
	var it := {"k": "lg_" + k, "t0": g.t, "gp": pv._snap(at), "gy": gy, "flip": flip, "ly": "up", "oid": "logos"}
	if follow:
		it["fopl"] = o   # 逻各斯跟施放者（对象本身；星熊用的 fop 是布尔 + 按 id 找人，键分开）
	pv._push(it)


static func _lg_gd(pv: P, k: String, at: Vector2) -> void:
	var g = pv.g
	pv._push({"k": "lg_" + k, "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "gd", "oid": "logos"})


static func _lg_raw(pv: P, k: String, at: Vector2, rot: float, sc: float) -> void:
	var g = pv.g
	pv._push({"k": "lg_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": "logos"})


static func _lg_tip(pv: P, o) -> Vector2:
	var tv = o.B.get("attack", {}).get("tip", [40, -36])
	return o.pos + Vector2(float(tv[0]) * float(o.face), float(tv[1]))


static func _ev_logos(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG lg %s %s %.3f" % [kind, str(d.get("i", "")), g.t])
	if kind == "shape" and d.get("circle", false) and str(d.get("src", "")) in ["提喻", "墓志铭"]:   # 转喻·共振 / 墓志铭爆开（docs/310 §2）：原来没有画面，补一圈咒文紫环 + 墨点
		var big: bool = float(d.get("r", 60.0)) >= 100.0
		CUE.push(pv, o, {"p": d.get("c", o.pos), "shape": "ring", "r": float(d.get("r", 60.0)), "r0": float(d.get("r", 60.0)) * 0.25, "c": LG_C[4] if not big else LG_AC, "n": 10 if not big else 6, "life": 0.4})
		return
	match kind:
		"fire":   # 出手：身前笔光 → 身周细字字环 + 笔尖星芒（原点 = 脚底；朝左水平翻转）。连发（复指 / 天赋）0.25 秒内只画一次
			if g.t - pv._lg_fire_t < 0.25 and g.t >= pv._lg_fire_t:
				return
			pv._lg_fire_t = g.t
			var hand: Vector2 = d.get("at", _lg_tip(pv, o))
			if raw:
				_lg_raw(pv, "raw_start_e%d" % t, hand, (d.get("dir", Vector2.RIGHT) as Vector2).angle(), px)
				return
			_lg_up(pv, o, "fire_e%d_up" % t, o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
			R._light(o, hand, 60.0, 0.3, 0.1, p.light)
			if t >= 1:
				R._grains(o, hand, o.pos.y + 2.0, "twinkle", 1 + t, {"tier": t}, d.get("dir", Vector2.RIGHT))
		"hit":   # 「言」命中（原作 hit_01）：白色星芒 + 不规整长碎刺，冷成深蓝 → 墨；地上一圈墨环
			var e: Dictionary = d.e
			var at: Vector2 = d.get("at", e.pos)
			if raw:
				_lg_raw(pv, "raw_hit_e%d" % t, at, (at - o.pos).angle(), px)
				return
			_lg_up(pv, o, "hit_e%d_up" % t, at, float(e.pos.y) + 1.0)
			_lg_gd(pv, "hit_e%d_gd" % t, e.pos + Vector2(0, 2))
			R._light(o, at, 90.0 + 20.0 * t, 0.5 + 0.1 * t, 0.12, p.light)
			R._grains(o, at, float(e.pos.y) + 2.0, "ink", 1 + t, {"tier": t}, (at - o.pos).normalized())
			if t >= 1:
				R._grains(o, at, float(e.pos.y) + 2.0, "twinkle", t, {"tier": t})
		"exec":   # 殁亡处决（原作 hit_03）：交叉细字咒文链 + 竖墨柱；溢出伤害跳转 = 一笔墨（白笔头）写到下一只
			var e2: Dictionary = d.e
			var tt: int = maxi(t, 1)
			var foot: Vector2 = e2.pos
			if raw:
				_lg_raw(pv, "raw_epitaph", foot, 0.0, px * 0.9)
				if d.has("to"):
					var dv0: Vector2 = (d.to as Vector2) - (d.at as Vector2)
					_lg_raw(pv, "raw_link", d.at, dv0.angle(), px * dv0.length() / 128.0)
				return
			_lg_up(pv, o, "exec_e%d_up" % tt, foot, foot.y + 1.0)
			_lg_gd(pv, "exec_e%d_gd" % tt, foot + Vector2(0, 2))
			R._light(o, foot + Vector2(0, -40), 150.0, 0.75, 0.14, p.light)
			R._grains(o, foot + Vector2(0, -30), foot.y + 2.0, "ink", 3 + tt, {"tier": tt})
			if d.has("to"):
				var b: Vector2 = d.to
				pv._push({"lrt": "jump", "a": d.at, "b": b, "t0": g.t + 0.05, "life": 4.0 / 15.0, "ly": "up", "gy": b.y + 12.0, "oid": "logos", "k": ""})
				pv._push({"k": "lg_hits_e%d_up" % t, "t0": g.t + 0.05 + 2.0 / 15.0, "gp": pv._snap(b), "gy": b.y + 12.0, "flip": false, "ly": "up", "oid": "logos"})
		"lock_tick":   # 提喻每一跳：目标身上一颗小星芒 + 碎刺（白 → 冷）
			var pts: Array = d.get("pts", [])
			if pts.is_empty():
				return
			var pt: Vector2 = pts[0][0]
			if raw:
				_lg_raw(pv, "raw_tick_e%d" % t, pt, (pt - o.pos).angle(), px * 0.8)
				return
			_lg_up(pv, o, "tick_e%d_up" % t, pt, float(pts[0][1]))
			R._light(o, pt, 70.0, 0.35, 0.1, p.light)
		"fan_tick":   # 延异视阈每一跳：笔尖向咒域里至多 4 只各射一道墨迹彗星（0.2 秒飞到），落点小星芒
			var pts2: Array = d.get("pts", [])
			if raw:
				for q in pts2:
					_lg_raw(pv, "raw_hit_e2", q[0], 0.0, px * 0.7)
				return
			var tip: Vector2 = _lg_tip(pv, o)
			for i in pts2.size():
				var q2: Vector2 = pts2[i][0]
				var t1: float = g.t + 0.03 * i
				pv._push({"lrt": "vbolt", "a": tip, "b": q2, "t0": t1, "life": 0.2, "ly": "up", "gy": float(pts2[i][1]), "oid": "logos", "k": "", "tier": 2, "side": 1.0 if i % 2 == 0 else -1.0})
				pv._push({"k": "lg_hits_e1_up", "t0": t1 + 0.2, "gp": pv._snap(q2), "gy": float(pts2[i][1]), "flip": false, "ly": "up", "oid": "logos"})
			if not pts2.is_empty():
				R._light(o, pts2[0][0], 110.0, 0.45, 0.12, p.light)
		"lg_xhit":   # 后期额外弹命中：小一号星芒；同一拍至多 3 团
			if pv._lm_beat_n(o, "xh") >= 3:
				return
			if raw:
				_lg_raw(pv, "raw_hit_e%d" % t, d.at, 0.0, px * 0.6)
				return
			_lg_up(pv, o, "hits_e%d_up" % t, d.at, float((d.e as Dictionary).pos.y) + 1.0)
		"lg_chain":   # 「连锁」弹射：一笔墨跳转 + 落点小星芒；同一拍至多 3 道
			if pv._lm_beat_n(o, "ch") >= 3:
				return
			if raw:
				var dv1: Vector2 = (d.b as Vector2) - (d.a as Vector2)
				_lg_raw(pv, "raw_link", d.a, dv1.angle(), px * dv1.length() / 128.0)
				return
			pv._push({"lrt": "jump", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": "logos", "k": ""})
			_lg_up(pv, o, "hits_e%d_up" % t, d.b, float(d.get("gy", 0.0)))
		"lg_link":   # 连携 v2「消弹」（skill_link l_logos）：区域上空浮起一圈细字咒文（少数淡金 = 原作黑金），被消的每颗敌弹化一点墨落下
			var c: Vector2 = d.c
			var r: float = float(d.r)
			var gone: PackedVector2Array = d.get("gone", PackedVector2Array())
			if raw:
				_lg_raw(pv, "raw_seal", c, 0.0, px * (r + 20.0) / 80.0)
				return
			pv._push({"lrt": "seal", "c": pv._snap(c), "r": r + 20.0, "t0": g.t, "life": 0.8, "ly": "up", "gy": c.y + (r + 20.0) * LG_SY, "oid": "logos", "k": ""})
			pv._push({"lrt": "ring", "c": pv._snap(c), "r": r + 20.0, "t0": g.t, "life": 0.6, "ly": "gd", "oid": "logos", "k": ""})
			for i in mini(gone.size(), 16):
				pv._push({"lrt": "pop", "c": pv._snap(gone[i]), "t0": g.t + 0.02 * (i % 5), "life": 0.4, "ly": "up", "gy": gone[i].y + 20.0, "oid": "logos", "k": "", "gi": i})
			R._light(o, c, r + 60.0, 0.6, 0.15, p.light)
		"lg_cshot":   # 连携技（combo.gd，link/v2 = 0）出手：一颗大彗星飞到落点
			if raw:
				pv._push({"lrt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "raw", "oid": "logos", "k": ""})
				return
			pv._push({"lrt": "vbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "up", "gy": (d.b as Vector2).y + 1.0, "oid": "logos", "k": "", "tier": 2, "side": 1.0, "big": true})
		"lg_combo":   # 连携技「咒文扩散」落点：大墨环闪一下；处决的每只一道墨笔 + 殁亡咒文链（至多 6）
			var tp: Vector2 = d.at
			var es: Array = d.get("es", [])
			if raw:
				_lg_raw(pv, "raw_seal", tp, 0.0, px * 1.5)
				return
			pv._push({"lrt": "ring", "c": pv._snap(tp), "r": 240.0, "t0": g.t, "life": 0.45, "ly": "gd", "oid": "logos", "k": ""})
			_lg_up(pv, o, "hit_e2_up", tp + Vector2(0, -10), tp.y + 1.0)
			for i in mini(es.size(), 6):
				var ee: Dictionary = es[i]
				pv._push({"lrt": "jump", "a": tp + Vector2(0, -10), "b": ee.pos + Vector2(0, -8), "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": float(ee.pos.y) + 1.0, "oid": "logos", "k": ""})
				pv._push({"k": "lg_exec_e2_up", "t0": g.t + 0.1, "gp": pv._snap(ee.pos), "gy": float(ee.pos.y) + 1.0, "flip": false, "ly": "up", "oid": "logos"})
			R._light(o, tp, 260.0, 0.85, 0.15, p.light)
			R._grains(o, tp + Vector2(0, -20), tp.y, "ink", 6, {"tier": 2})
		"skill":
			var si: int = int(d.get("i", -1))
			if si == 1:   # 殁亡（永久）：起手一圈字环
				if raw:
					_lg_raw(pv, "raw_start_e%d" % maxi(t, 1), _lg_tip(pv, o), 0.0, px * 1.2)
					return
				_lg_up(pv, o, "fire_e%d_up" % maxi(t, 1), o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
				R._light(o, o.pos + Vector2(0, -30), 110.0, 0.5, 0.14, p.light)
			elif si == 2:   # 延异视阈起手：双层字环 → 笔尖蓄势 → 开域爆亮
				if raw:
					_lg_raw(pv, "raw_seal", o.pos + Vector2(0, -20), 0.0, px)
					return
				_lg_up(pv, o, "s3open_up", o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
				var tip2: Vector2 = _lg_tip(pv, o)
				R._light(o, tip2, 160.0, 0.8, 0.15, p.light)
				R._grains(o, tip2, o.pos.y + 2.0, "twinkle", 5, {"tier": 2})


## 贴地层：一次性件 + 运行时贴地件 + 状态件（咒域、提喻目标脚下墨环、铭文 / 墓志铭）
static func _lg_draw_floor(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	for it in pv.items_for("logos"):
		if str(it.ly) != "gd":
			continue
		if it.has("lrt"):
			_lg_draw_rt(pv, cv, it)
		else:
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), it.gp, it.flip, true)
	var h: Dictionary = o.hw
	if h.has("s3_shots"):   # 原画法在绘制时清理出手轨迹；接管后由这里清，免得列表只增不减
		var now: float = g.t
		h["s3_shots"] = h.s3_shots.filter(func(sh): return now - float(sh.t0) < 0.3)
	if h.has("pools"):
		for l in h.pools:
			if str(l.b.get("look", "")) == "rune":
				_lg_pool(pv, cv, l)
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		var ramp: float = clampf(int(lk.n) / float(lk.b.get("ramp_n", 12.0)), 0.0, 1.0)
		var rr: float = 11.0 + 5.0 * ramp
		_lg_ell(pv, cv, lk.e.pos + Vector2(0, 3), rr, 1.0, 1, 7)
		if pv.tier(o) >= 1:
			_lg_ell(pv, cv, lk.e.pos + Vector2(0, 3), rr + 5.0, 0.8, 0, 11)
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and float(fn.get("t", 0.0)) > 0.0:
		_lg_fan(pv, cv, o, fn)


## 地面细椭圆环（美术像素格，按噪声断续）：r 美术像素
static func _lg_ell(pv: P, ci, c: Vector2, r: float, a: float, hi: int, sd: int) -> void:
	var g = pv.g
	var px: float = g.PX
	var n: int = maxi(12, int(TAU * r))
	var cc: Vector2 = pv._snap(c)
	for i in n:
		var an: float = TAU * i / n
		var hv: float = _lg_h(sd * 977 + i)
		if hv < 0.22 or hv > a + 0.22:
			continue
		var q: Vector2 = cc + Vector2(cos(an) * r, sin(an) * r * LG_SY) * px
		var lit: bool = hi > 0 and sin(an) > 0.3 and hv > 0.55
		ci.draw_rect(Rect2(pv._snap(q), Vector2(px, px)), LG_C[4] if lit else (LG_C[2] if hv > 0.7 else LG_INK[1]))


## 二次贝塞尔（弯的符文行 / 锁链用）
static func _lg_bez(a: Vector2, c: Vector2, b: Vector2, s: float) -> Vector2:
	var u: float = 1.0 - s
	return a * (u * u) + c * (2.0 * u * s) + b * (s * s)


## a → b 往上拱 bow（世界像素）的控制点：弧顶离弦 bow
static func _lg_bow_ctrl(a: Vector2, b: Vector2, bow: float) -> Vector2:
	var d: Vector2 = b - a
	var n := Vector2(-d.y, d.x).normalized()
	if n.y > 0.0:
		n = -n
	return (a + b) * 0.5 + n * bow * 2.0


static func _lg_glyph(pv: P, ci, p: Vector2, gi: int, col: Color, sc := 1) -> void:
	var g = pv.g
	var px: float = g.PX * float(sc)   # sc 2 = 每笔 2×2 美术像素（铭文浮字，docs/310 §4.2）
	var s: String = LG_GL[posmod(gi, LG_GL.size())]
	var o0: Vector2 = pv._snap(p) - Vector2(px, 2.0 * px)
	for k in 15:
		if s.unicode_at(k) == 49:
			ci.draw_rect(Rect2(o0 + Vector2(k % 3, k / 3) * px, Vector2(px, px)), col)


## 铭文 / 墓志铭（成长节点）：地上一圈断续墨环 + 上方浮着几个细字；墓志铭从少到多写满
static func _lg_pool(pv: P, ci, l: Dictionary) -> void:
	var g = pv.g
	var al: float = clampf(float(l.t) / 0.3, 0.0, 1.0)
	var burst: bool = l.b.get("burst", false)
	var k: float = 1.0 - float(l.t) / maxf(0.01, float(l.dur)) if burst else 1.0
	var r: float = float(l.r) / g.PX
	_lg_ell(pv, ci, l.pos, r * (0.6 + 0.4 * k), al, 1, int(l.pos.x))
	_lg_ell(pv, ci, l.pos, r * (0.6 + 0.4 * k) + 1.0, al, 1, int(l.pos.x) + 5)   # docs/310 §4.2：环加到 2 像素
	var beat: int = int(floor(g.t * 15.0))
	var n: int = 3 if not burst else 1 + int(k * 4.0)
	for i in n:
		var x: float = (float(i) - (n - 1) * 0.5) * 8.0
		var bob: float = (2.0 if ((beat / 4 + i) % 2) == 0 else 0.0) - 0.05 * x * x   # 浮字排成一小段弧（第六轮：不留笔直的字行）
		var c: Color = LG_C[5] if (beat / 3 + i) % 4 != 0 else LG_C[6]
		c.a = al
		var gp: Vector2 = l.pos + Vector2(x, -22.0 - bob) * g.PX
		var gi: int = int(l.pos.x) + i * 3 + beat / 8
		var dk: Color = LG_INK[1]
		dk.a = al
		_lg_glyph(pv, ci, gp + Vector2(g.PX, g.PX), gi, dk, 2)   # 暗影衬底
		_lg_glyph(pv, ci, gp, gi, c, 2)   # 字放到 6×10（原 3×5 叠在命中墨环上看不出）


## 一段咒文的曲线（扇形平面坐标、美术像素、未压扁）：龟形走法每步 4 像素，转角按类型给——0 螺旋收拢 / 1 波浪起伏 / 2 弯钩 / 3 往外甩。
## 返回 [Vector3(x, y, 朝向)]，6–10 个
static func _lg_seg_path(pv: P, sd: int, rc: float, fa: float, half: float) -> Array:
	var typ: int = int(_lg_h(sd + 9) * 4.0)
	var n: int = 6 + int(_lg_h(sd + 3) * 5.0)
	var af: float = (_lg_h(sd + 1) * 2.0 - 1.0) * 0.8
	var rf: float = 0.30 + 0.5 * _lg_h(sd + 2)
	var a0: float = fa + half * af
	var x: float = cos(a0) * rc * rf
	var y: float = sin(a0) * rc * rf
	var head: float = a0 + (PI / 2.0 if _lg_h(sd + 5) < 0.5 else -PI / 2.0) + (_lg_h(sd + 6) - 0.5) * 0.8
	if typ == 3:
		head = a0 + (_lg_h(sd + 6) - 0.5) * 0.6
	var sg: float = 1.0 if _lg_h(sd + 7) < 0.5 else -1.0
	var out: Array = []
	for j in n:
		out.append(Vector3(x, y, head))
		var k: float
		match typ:
			0:
				k = sg * (0.28 + 0.05 * j)
			1:
				k = 0.55 * sin(j * 1.1 + sd) * sg
			2:
				k = 0.05 * sg if j < n * 0.5 else 0.62 * sg
			_:
				k = 0.10 * sg
		head += k
		x += cos(head) * 4.0
		y += sin(head) * 4.0
	return out


static func _lg_ign(x: int, y: int) -> float:   # interleaved gradient noise：细密、不成格子（不是 Bayer）
	return fposmod(52.9829189 * fposmod(0.06711056 * x + 0.00583715 * y, 1.0), 1.0)


## 整盘渐变（压扁椭圆，半径 R 美术像素）只生成一次（按 R 缓存）；扇形用带 UV 的多边形取其中一块，1 贴图像素 = 1 美术像素
static func _lg_fill(pv: P, R: int) -> Texture2D:
	if pv._lg_fill_tex.has(R):
		return pv._lg_fill_tex[R]
	var ry: int = int(ceil(R * LG_SY))
	var img := Image.create_empty(2 * R + 1, 2 * ry + 1, false, Image.FORMAT_RGBA8)
	var n: int = LG_FILL.size()
	for y in range(-ry, ry + 1):
		for x in range(-R, R + 1):
			var q: float = Vector2(float(x) / R, float(y) / (R * LG_SY)).length()
			if q > 1.0:
				continue
			var ang: float = atan2(float(y) / LG_SY, float(x))
			var flow: float = 0.35 * sin(ang * 5.0 + q * 7.0)   # 一道静止的旋涡纹，抖动阈值跟着弯（读作缓慢流动的墨域）
			var v: float = pow(q, 2.4) * (n - 1) + (_lg_ign(x + 4000, y + 4000) - 0.5) * 1.15 + flow * 0.5
			var k: int = clampi(int(floor(v + 0.5)), 0, n - 1)
			var c: Color = LG_FILL[k][0]
			c.a = float(LG_FILL[k][1])
			img.set_pixel(x + R, y + ry, c)
	var tx := ImageTexture.create_from_image(img)
	pv._lg_fill_tex[R] = tx
	return tx


static func _lg_fan(pv: P, ci, o, fn: Dictionary) -> void:
	var g = pv.g
	var b: Dictionary = fn.b
	var px: float = g.PX
	var r: float = float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, b))
	var half: float = deg_to_rad(float(b.get("deg", 100.0))) * 0.5
	var fa: float = float(o.hw.fan_ang)
	var dur: float = float(b.get("dur", 12.0))
	var el: float = dur - float(fn.t)
	var open: float = clampf(floor(el * 15.0) / 15.0 / 0.33, 0.0, 1.0)   # 按拍张开
	var fade: float = clampf(float(fn.t) / 0.35, 0.0, 1.0)
	var rr: float = r * (0.55 + 0.45 * (1.0 - pow(1.0 - open, 2.0)))
	var c: Vector2 = pv._snap(o.pos)
	var tk: float = float(b.get("tick", 0.5))
	var pulse: bool = float(fn.get("tick", 0.0)) > tk - 1.0 / 15.0
	var beat: int = int(floor(g.t * 15.0))
	# 渐变填充
	var R: int = maxi(8, int(round(r / px)))
	var tex: Texture2D = _lg_fill(pv, R)
	var tw: float = 2.0 * R + 1.0
	var th: float = 2.0 * ceil(R * LG_SY) + 1.0
	var k: float = float(R) * px / rr   # 张开期间按比例取（张满后 = 1，贴图像素正好落在美术像素格上）
	var N := 40
	var pts := PackedVector2Array([c])
	var uvs := PackedVector2Array([Vector2((R + 0.5) / tw, (ceil(R * LG_SY) + 0.5) / th)])
	for i in N + 1:
		var a: float = fa - half + 2.0 * half * i / N
		var p: Vector2 = Vector2(cos(a), sin(a) * LG_SY) * rr
		pts.append(c + p)
		var lp: Vector2 = p * k / px
		uvs.append(Vector2((lp.x + R + 0.5) / tw, (lp.y + ceil(R * LG_SY) + 0.5) / th))
	ci.draw_colored_polygon(pts, Color(1, 1, 1, fade * float(g.world.late_fill_k())), uvs, tex)   # 后期填充变薄、边照画（docs/293 late_fx_fill）
	# 外边：2 美术像素（外亮内墨），按噪声断续加厚；两侧边：1 像素断续
	var rc: float = rr / px
	var n: int = maxi(16, int(2.0 * half * rc))
	for i in n + 1:
		var a3: float = fa - half + 2.0 * half * i / n
		var hv: float = _lg_h(i * 31 + 7)
		var q: Vector2 = c + Vector2(cos(a3), sin(a3) * LG_SY) * rr
		var ec: Color = LG_C[6] if pulse else (LG_C[5] if hv > 0.66 else LG_C[4])
		ec.a = fade
		ci.draw_rect(Rect2(pv._snap(q), Vector2(px, px)), ec)
		if hv > 0.45:
			ci.draw_rect(Rect2(pv._snap(c + Vector2(cos(a3), sin(a3) * LG_SY) * (rr + px)), Vector2(px, px)), Color(LG_C[4].r, LG_C[4].g, LG_C[4].b, fade))
		var ic: Color = LG_INK[1] if hv > 0.3 else LG_C[1]
		ic.a = fade
		ci.draw_rect(Rect2(pv._snap(c + Vector2(cos(a3), sin(a3) * LG_SY) * (rr - px * 1.2)), Vector2(px, px)), ic)
		if pulse and (i % 3) == 0:
			pv._glow(q, LG_C[5])
	for sgn in [-1.0, 1.0]:
		var ea: float = fa + half * sgn
		var dv := Vector2(cos(ea), sin(ea) * LG_SY)
		var m: int = int(dv.length() * rr / px)
		var dn: Vector2 = dv.normalized()
		for i in m:
			if (i / 3) % 3 == 2:
				continue
			ci.draw_rect(Rect2(pv._snap(c + dn * float(i) * px), Vector2(px, px)), Color(LG_C[3].r, LG_C[3].g, LG_C[3].b, 0.8 * fade))
	# 咒文段（11-05 第七轮用户「长一点没关系，要有咒术和巫术的感觉，每个字可以用不同的曲线」）：同屏至多 LG_SEG_N 段，每段 6–10 个细字，
	# 各走各的曲线（螺旋收拢 / 波浪起伏 / 弯钩 / 往外甩）；字一个个被写出来（第一拍白），写出后自己扭一下；停 0.8–1.2 秒后从头到尾逐字褪去；
	# 写完时段尾拖出一道细丝和三点墨；每三个字一个带暗紫辉光（进光学发光层）。位置 / 曲线按「段号 + 第几轮」固定种子取，时间按 15 fps 拍子取
	if open > 0.5:
		var tb: float = floor(g.t * 15.0) / 15.0
		for ks in LG_SEG_N:
			var P: float = LG_SEG_P + 0.23 * float(ks % 3)
			var lt0: float = tb + P * float(ks) / LG_SEG_N
			var cyc: int = int(floor(lt0 / P))
			var lt: float = lt0 - float(cyc) * P
			var sd: int = ks * 977 + cyc * 131
			var path: Array = _lg_seg_path(pv, sd, rc, fa, half)
			var nseg: int = path.size()
			var hold: float = 0.8 + 0.4 * _lg_h(sd + 8)
			for j in nseg:
				var tin: float = 0.06 * j
				var tout: float = 0.06 * nseg + hold + 0.05 * j
				if lt < tin or lt > tout + 0.12:
					continue
				var pj: Vector3 = path[j]
				var ang: float = atan2(pj.y, pj.x)
				if Vector2(pj.x, pj.y).length() > rc * 0.97 or absf(wrapf(ang - fa, -PI, PI)) > half * 0.95:
					continue
				var al2: float = clampf(1.0 - (lt - tout) / 0.12, 0.0, 1.0)
				var age: float = lt - tin
				var wig: float = round(sin(age * 22.0) * 1.2) if age < 0.27 else 0.0   # 写出来后自己扭一下
				var gq := Vector2(pj.x - sin(pj.z) * wig, (pj.y + cos(pj.z) * wig) * LG_SY)
				var glow: bool = (j + sd) % 3 == 0
				var gc: Color = LG_C[6] if age < 1.0 / 15.0 else (LG_AC if glow else LG_C[5])
				gc.a = fade * al2
				var gp: Vector2 = c + gq * px
				_lg_glyph(pv, ci, gp, sd + j * 3, gc)
				if glow and age >= 1.0 / 15.0 and al2 > 0.5:
					pv._glow(gp, LG_GLOW)
					pv._glow(gp + Vector2(0, -2.0 * px), LG_GLOW)
			# 段尾细丝 + 三点墨
			var tdone: float = 0.06 * nseg
			var toutn: float = 0.06 * nseg + hold + 0.05 * nseg
			if lt >= tdone and lt <= toutn + 0.12 and nseg > 0:
				var al3: float = minf(1.0, (lt - tdone) / 0.1) * clampf(1.0 - (lt - toutn) / 0.12, 0.0, 1.0) * fade
				var pe: Vector3 = path[nseg - 1]
				var hv := Vector2(cos(pe.z), sin(pe.z))
				for k3 in range(1, 7):
					var q3: Vector2 = Vector2(pe.x, pe.y) + hv * float(3 + k3) + Vector2(0, sin(k3 * 0.9) * 0.8)
					ci.draw_rect(Rect2(pv._snap(c + Vector2(q3.x, q3.y * LG_SY) * px), Vector2(px, px)), Color(LG_C[2].r, LG_C[2].g, LG_C[2].b, al3 * (1.0 - k3 / 8.0)))
				var dd: Array = [9.0, 11.5, 13.5]
				for k4 in 3:
					var q4: Vector2 = Vector2(pe.x, pe.y) + hv * float(dd[k4]) + Vector2(0, (k4 - 1) * 0.8)
					ci.draw_rect(Rect2(pv._snap(c + Vector2(q4.x, q4.y * LG_SY) * px), Vector2(px, px)), Color(LG_INK[1].r, LG_INK[1].g, LG_INK[1].b, al3))
	var R2 = load("res://scripts/render/fx_recipe.gd").of(g)
	R2._light_follow(o, c + Vector2(cos(fa), sin(fa) * LG_SY) * rr * 0.6, rr * 0.9, (0.45 if pulse else 0.25) * fade, LG_C[3])


## 立起层的状态件：「言」彗星（运行时）、后期额外弹、提喻咒文行、连缀咒文链
static func _lg_sort_items(pv: P, o, out: Array) -> void:
	var h: Dictionary = o.hw
	if h.has("bolts"):
		for bo in h.bolts:
			out.append({"lrt": "bolt", "b": bo, "o": o, "gy": float((bo.to as Vector2).y) + 14.0})
	if not o.vg.is_empty():   # 后期额外弹：同时最多画最新 6 颗（更早的照常结算，只是不画）
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"lrt": "xbolt", "b": xb, "o": o, "gy": (xb.p as Vector2).y + 1.0})
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		out.append({"lrt": "lock", "o": o, "gy": float(lk.e.pos.y) + 1.0})
	if h.has("links") and not h.links.is_empty():
		for lkk in h.links:
			out.append({"lrt": "links", "l": lkk, "o": o, "gy": float((lkk.m[0] as Dictionary).pos.y) + 1.0})


## 法术弹道（只画面）：第四轮的上抛弧被用户否了（11-05「不应该是迫击炮的感觉，而应该是法术投射的感觉」），
## 改成贴着平面飞、只带一点侧向弯曲：一道浅弧（side 决定往哪边弯）加一点 S 形摆动，两端都落在 a / b 上，s ∈ [0, 1]；判定与命中时间仍走玩法里的追踪弹位
static func _lg_arc(a: Vector2, b: Vector2, s: float, lift: float, side := 1.0) -> Vector2:
	var d: Vector2 = b - a
	var n := Vector2(-d.y, d.x).normalized() * side
	return a.lerp(b, s) + n * (lift * sin(PI * s) + 0.3 * lift * sin(TAU * s))


## 沿弧线从弹头往回取墨尾的点（每点相隔约 1 美术像素），弹头在前
static func _lg_arc_path(pv: P, a: Vector2, b: Vector2, u: float, n: int, lift: float, side := 1.0) -> PackedVector2Array:
	var g = pv.g
	var out := PackedVector2Array()
	var ds: float = g.PX / maxf(8.0, a.distance_to(b) * 1.15)
	for k in n + 1:
		var s: float = u - float(k) * ds
		if s < 0.0:
			break
		out.append(_lg_arc(a, b, s, lift, side))
	return out


static func _lg_line_path(pv: P, head: Vector2, dv: Vector2, n: int) -> PackedVector2Array:
	var g = pv.g
	var out := PackedVector2Array()
	for k in n + 1:
		out.append(head - dv * float(k) * g.PX)
	return out


## 墨迹彗星（原作 trail_01）：path = 弹头在前的弧线点列。白头尖细（6 格箭头，不做光球）；墨尾深蓝（墨边 + 一根蓝芯线 + 按拍闪的蓝点），
## 粗在前三成、往后收尖，沿弧线拖；尾旁零星淡金小星（原作 0.88 s）。精一：墨尾分成两股绞着走；精二：尾后一行细字（白 / 紫）
static func _lg_comet(pv: P, ci, path: PackedVector2Array, t: int, al := 1.0, big := false, sd := 0) -> void:
	var g = pv.g
	var px: float = g.PX
	var L: int = path.size() - 1
	if L < 1:
		return
	var beat: int = int(floor(g.t * 15.0))
	var W: float = 2.6 if big else 2.0
	var head: Vector2 = path[0]
	var dv0: Vector2 = (path[0] - path[1]).normalized()
	var nL: float = float(LG_BOLT_LEN[mini(t, 2)] if not big else 36)
	for i in range(2, L + 1):
		var v: float = float(i) / nL
		var dv: Vector2 = (path[i - 1] - path[i]).normalized()
		var nv := Vector2(-dv.y, dv.x)
		var w: float = W * (1.0 - pow((v - 0.3) / 0.7, 1.5)) if v > 0.3 else W * smoothstep(0.05, 0.3, v)
		var split: float = (1.2 + 2.6 * v) * absf(sin(v * 5.0 + float(beat) * 0.4)) + 0.8 if (t >= 1 and v > 0.12) else 0.0   # 精一新元素：墨尾分成两股绞着走
		var ctr: Vector2 = path[i]
		var sides: Array = [-1.0, 1.0] if split > 0.6 else [0.0]
		for sgn in sides:
			var c0: Vector2 = ctr + nv * float(sgn) * split * px
			var ww: int = int(round(w * (0.6 if split > 0.6 else 1.0)))
			for q in range(-ww, ww + 1):
				var col: Color
				if q == 0:
					col = LG_C[5] if ((i + beat) % 6 == 0 and v < 0.8) else (LG_C[3] if v < 0.7 else LG_C[2])
				elif absi(q) == ww:
					col = LG_INK[0]
				else:
					col = LG_INK[1]
				col.a = al * (1.0 if v < 0.75 else maxf(0.0, 1.0 - (v - 0.75) * 2.4))
				ci.draw_rect(Rect2(pv._snap(c0 + nv * float(q) * px), Vector2(px, px)), col)
	var h0: Vector2 = pv._snap(head)
	var nv0 := Vector2(-dv0.y, dv0.x)
	var cells: Array = [[1, 0], [0, 0], [-1, 0], [-1, 1], [-1, -1], [-2, 0]]
	for qq in cells:
		var cell: Vector2 = h0 + (dv0 * float(qq[0]) + nv0 * float(qq[1])) * px
		var hc: Color = Color(1, 1, 1, al) if int(qq[1]) == 0 else Color(LG_C[5].r, LG_C[5].g, LG_C[5].b, al)
		ci.draw_rect(Rect2(pv._snap(cell), Vector2(px, px)), hc)
	pv._glow(h0, LG_C[6])
	pv._glow(h0 - dv0 * px, LG_C[5])
	# 淡金小星：尾旁两颗，按拍明灭（亮的那拍是十字，暗的那拍一点）
	for k in 2:
		var idx: int = int(L * (0.55 + 0.3 * k))
		if idx >= path.size() or idx < 2:
			continue
		var ph: float = _lg_h(sd * 13 + k * 7 + beat / 2)
		if ph < 0.35:
			continue
		var dvk: Vector2 = (path[idx - 1] - path[idx]).normalized()
		var gp: Vector2 = pv._snap(path[idx] + Vector2(-dvk.y, dvk.x) * (4.0 if k == 0 else -5.0) * px)
		var gc := Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, al)
		ci.draw_rect(Rect2(gp, Vector2(px, px)), gc)
		if ph > 0.7:
			for o4 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_rect(Rect2(gp + o4 * px, Vector2(px, px)), Color(gc.r, gc.g, gc.b, al * 0.7))
	# 咒文残光（法术弹的拖尾感）：尾后几个细字一路变淡；精零 1 个暗字、精一 2 个、精二 3 个亮字（白 / 紫）
	var tail: Vector2 = path[L]
	var dvt: Vector2 = (path[maxi(0, L - 1)] - path[L]).normalized()
	for k in t + 1:
		var gp2: Vector2 = tail - dvt * float(5 + 6 * k) * px
		var gc2: Color = (LG_AC if (k + beat / 3) % 3 == 0 else LG_C[5]) if t >= 2 else LG_C[3 + t]
		gc2.a = al * (0.9 - 0.25 * k) * (1.0 if t >= 2 else 0.7)
		_lg_glyph(pv, ci, gp2, k + beat / 3 + sd, gc2)


## 运行时件
static func _lg_draw_rt(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	match str(it.lrt):
		"bolt":   # 「言」：画面走弧线（a = 出手点，b = 目标，u = 飞行进度），玩法弹位照旧追踪；只记画面专用键 _pxs0 / _pxu
			var bo: Dictionary = it.b
			var o = it.o
			var a0: Vector2
			var u0: float
			if bo.has("visual"):
				a0 = bo.visual.start
				u0 = float(bo.visual.u)
			else:
				if not bo.has("_pxs0"):
					bo["_pxs0"] = bo.pos
				a0 = bo._pxs0
				var d0: float = maxf(1.0, a0.distance_to(bo.to))
				u0 = maxf(float(bo.get("_pxu", 0.0)), clampf(1.0 - (bo.pos as Vector2).distance_to(bo.to) / d0, 0.0, 1.0))
				bo["_pxu"] = u0
			var tt: int = pv.tier(o)
			var lift: float = minf(26.0, a0.distance_to(bo.to) * 0.12)
			var sd0: int = int(bo.get("rune", 0)) & 1023
			_lg_comet(pv, ci, _lg_arc_path(pv, a0, bo.to, u0, LG_BOLT_LEN[tt], lift, 1.0 if sd0 % 2 == 0 else -1.0), tt, 1.0, false, sd0)
		"xbolt":
			var xb: Dictionary = it.b
			_lg_comet(pv, ci, _lg_line_path(pv, (xb.p as Vector2) + Vector2(0, -16), (xb.v as Vector2).normalized(), 14), mini(1, pv.tier(it.o)))
		"vbolt":   # 咒域每跳 / 连携出手：贴着平面带一点侧弯飞到 b，飞到即止
			var u: float = (g.t - float(it.t0)) / float(it.life)
			if u < 0.0 or u > 1.0:
				return
			var big: bool = it.get("big", false)
			var lift2: float = minf(24.0, (it.a as Vector2).distance_to(it.b) * 0.12)
			_lg_comet(pv, ci, _lg_arc_path(pv, it.a, it.b, u, 36 if big else 24, lift2, float(it.get("side", 1.0))), int(it.tier), 1.0, big, int(it.get("side", 1.0) > 0.0))
		"lock":   # 提喻：笔尖 → 目标一道弯的蓝丝线（往上拱、随拍轻轻摆）+ 沿弧一行细字向目标流动；精一上下两行；精二字白紫相间、丝线成一串墨珠
			# 11-05 第六轮用户「还有笔直的符文条」：原来是一条直线，改成二次弧（不再有笔直的字行）
			var o2 = it.o
			var lk: Dictionary = o2.hw.lock
			var t2: int = pv.tier(o2)
			var a2: Vector2 = _lg_tip(pv, o2)
			var b2: Vector2 = lk.e.pos + Vector2(0, -float(lk.e.r) * 0.5)
			var head: float = minf(1.0, (int(lk.n) * float(lk.b.get("tick", 0.25)) + float(lk.tick)) / maxf(0.05, float(lk.b.get("tick", 0.25))))
			var Lf: float = a2.distance_to(b2) / px
			if Lf < 2.0:
				return
			var beat2: int = int(floor(g.t * 15.0))
			var bow: float = clampf(Lf * 0.1, 4.0, 16.0) + 1.0 * sin(float(beat2) * 0.35)
			var ctrl: Vector2 = _lg_bow_ctrl(a2, b2, bow * px)
			var n: int = int(Lf * head)
			var prev: Vector2 = a2
			var cum: float = 0.0
			var nextg: float = 3.0
			var k: int = 0
			var rows: Array = [6.0] if t2 < 1 else ([6.0, -6.0] if t2 < 2 else [7.0, 0.0, -7.0])   # 精二质变：丝线本身也写成一行字（三行字成链）
			var ng2: int = int(Lf * head / 5.0)
			for i in n:
				var s: float = float(i) / Lf
				var p2: Vector2 = _lg_bez(a2, ctrl, b2, s)
				if t2 >= 2 and i % 3 == 1:
					ci.draw_rect(Rect2(pv._snap(p2), Vector2(px, px)), LG_INK[1])
				else:
					ci.draw_rect(Rect2(pv._snap(p2), Vector2(px, px)), LG_C[3] if (i + beat2) % 7 != 0 else LG_C[5])
				cum += p2.distance_to(prev) / px
				prev = p2
				if cum >= nextg:
					nextg += 5.0
					var tg: Vector2 = (_lg_bez(a2, ctrl, b2, minf(1.0, s + 0.02)) - p2).normalized()
					var nv2 := Vector2(-tg.y, tg.x)
					if nv2.y > 0.0:
						nv2 = -nv2   # 字行在线的上方
					for ri in rows.size():
						var gc2: Color = LG_C[5]
						if t2 >= 2 and (k + beat2 / 2) % 2 == 0:
							gc2 = LG_AC
						elif k == ng2 - 1:
							gc2 = LG_C[6]
						_lg_glyph(pv, ci, p2 + nv2 * float(rows[ri]) * px, k * 3 + ri * 5 - beat2 / 2, gc2)
					k += 1
			pv._glow(prev, LG_C[5])
		"links":   # 精二连缀：成员之间一道下垂的弧链（像挂着的锁链，不再是直线）：一串墨珠 + 每 9 像素一个细字，一颗白珠按拍沿链走
			var lkk: Dictionary = it.l
			var mm: Array = lkk.m
			var a0: Dictionary = mm[0]
			if a0.dead:
				return
			var al: float = clampf(float(lkk.t) / 0.25, 0.0, 1.0)
			var pa: Vector2 = a0.pos + Vector2(0, -float(a0.r) * 0.6)
			var beat3: int = int(floor(g.t * 15.0))
			for j in range(1, mm.size()):
				var q: Dictionary = mm[j]
				if q.dead:
					continue
				var pb: Vector2 = q.pos + Vector2(0, -float(q.r) * 0.6)
				var Lq: int = int(pa.distance_to(pb) / px)
				if Lq < 2:
					continue
				var sag: Vector2 = (pa + pb) * 0.5 + Vector2(0, minf(float(Lq) * 0.2, 14.0) * px)   # 往下垂
				var ctl: Vector2 = sag * 2.0 - (pa + pb) * 0.5
				for i in Lq:
					if i % 2 == 1:
						continue
					var cc: Color = LG_C[6] if (i / 2) == (beat3 % maxi(1, Lq / 2)) else (LG_C[3] if i % 4 == 0 else LG_INK[1])
					cc.a = al
					ci.draw_rect(Rect2(pv._snap(_lg_bez(pa, ctl, pb, float(i) / Lq)), Vector2(px, px)), cc)
				for k2 in range(1, Lq / 9):
					var gc3: Color = LG_C[5] if k2 % 2 else LG_AC
					gc3.a = al
					_lg_glyph(pv, ci, _lg_bez(pa, ctl, pb, float(k2 * 9) / Lq) + Vector2(0, -4.0 * px), k2 + j * 4 + beat3 / 4, gc3)
		"jump":   # 一笔墨（白笔头）从 a 写到 b：第 0 拍写到 70%、第 1 拍写满、之后从笔尾干回去
			var f: int = pv.frame_of(float(it.t0))
			if f < 0:
				return
			var a3: Vector2 = it.a
			var b3: Vector2 = it.b
			var Lj: int = int(a3.distance_to(b3) / px)
			if Lj < 2:
				return
			var dj: Vector2 = (b3 - a3) / (float(Lj) * px)
			var nj := Vector2(-dj.y, dj.x)
			var i1: int = int(Lj * (0.7 if f == 0 else 1.0))
			var i0: int = 0 if f <= 1 else int(Lj * (0.4 * (f - 1)))
			for i in range(i0, i1):
				var v: float = float(i) / Lj
				var p3: Vector2 = a3 + dj * float(i) * px
				var hot: bool = i >= i1 - 3
				ci.draw_rect(Rect2(pv._snap(p3), Vector2(px, px)), LG_C[6] if hot else LG_C[3])
				if not hot and v > 0.15 and v < 0.85:
					ci.draw_rect(Rect2(pv._snap(p3 + nj * px), Vector2(px, px)), LG_INK[1])
			if i1 > 0:
				pv._glow(a3 + dj * float(i1 - 1) * px, LG_C[6])
		"seal":   # 连携「消弹」：区域边上浮起一圈细字（少数淡金），整圈按拍转、往上浮，0.8 秒散
			var u2: float = (g.t - float(it.t0)) / float(it.life)
			if u2 < 0.0 or u2 > 1.0:
				return
			var c2: Vector2 = it.c
			var rr2: float = float(it.r)
			var beat4: int = int(floor(g.t * 15.0))
			var n2: int = clampi(int(TAU * rr2 / px / 8.0), 16, 56)   # 第六轮：字距 11 → 8
			var rise: float = minf(1.0, u2 / 0.15) * 10.0 + u2 * 8.0
			for i in n2:
				var an: float = TAU * float(i) / n2 + float(beat4 - int(floor(float(it.t0) * 15.0))) * 0.03
				var hv2: float = _lg_h(i * 17 + 3)
				if u2 > 0.6 and hv2 < (u2 - 0.6) * 2.5:
					continue
				var gp3: Vector2 = c2 + Vector2(cos(an) * rr2, sin(an) * rr2 * LG_SY) + Vector2(0, -rise * px)
				var back: bool = sin(an) < -0.2
				var gc4: Color = LG_GOLD if i % 4 == 0 else (LG_C[4] if back else LG_C[6])   # 第六轮：提亮一档（前半圈白、后半圈亮蓝、淡金 1/4）
				if u2 < 0.08:
					gc4 = LG_C[6]
				ci.draw_rect(Rect2(pv._snap(gp3) + Vector2(0, 3.0 * px), Vector2(px, px)), LG_INK[0])   # 字脚一点墨影
				ci.draw_rect(Rect2(pv._snap(gp3) + Vector2(px, 3.0 * px), Vector2(px, px)), LG_C[3])   # 字脚一道亮蓝底线（读作一圈环）
				if u2 < 0.3 and i % 2 == 0:
					pv._glow(gp3, LG_C[5])
				_lg_glyph(pv, ci, gp3, i * 3 + beat4 / 3, gc4)
		"pop":   # 被消的敌弹：一点白 → 一团墨收紧 → 一小块细字碎块落下熄灭
			var f2: int = pv.frame_of(float(it.t0))
			if f2 < 0 or f2 > 6:
				return
			var c3: Vector2 = it.c
			if f2 == 0:
				for qq in [[0, 0], [1, 0], [0, 1], [1, 1]]:
					ci.draw_rect(Rect2(pv._snap(c3) + Vector2(qq[0], qq[1]) * px, Vector2(px, px)), LG_C[6])
			elif f2 <= 2:
				for y in range(-1, 3):
					for x in range(-1, 3):
						var md: int = absi(x * 2 - 1) + absi(y * 2 - 1)
						if md <= 4:
							ci.draw_rect(Rect2(pv._snap(c3) + Vector2(x, y) * px, Vector2(px, px)), LG_INK[0] if md < 4 else LG_C[2])
			else:
				_lg_glyph(pv, ci, c3 + Vector2(0, float((f2 - 2) * (f2 - 2)) * px), int(it.gi), LG_C[4] if f2 < 5 else LG_C[2])
		"ring":   # 贴地大墨环原地闪一下（不外扩）：外亮内墨 2 像素，按噪声断续
			var u3: float = (g.t - float(it.t0)) / float(it.life)
			if u3 < 0.0 or u3 > 1.0:
				return
			var rr3: float = float(it.r) / px
			var a5: float = 1.0 if u3 < 0.12 else 1.0 - (u3 - 0.12) / 0.88
			var n3: int = int(TAU * rr3)
			for i in n3:
				var hv3: float = _lg_h(i * 7 + 11)
				if hv3 > a5 + 0.15 or hv3 < 0.12:
					continue
				var an2: float = TAU * float(i) / n3
				var q3: Vector2 = (it.c as Vector2) + Vector2(cos(an2) * rr3, sin(an2) * rr3 * LG_SY) * px
				ci.draw_rect(Rect2(pv._snap(q3), Vector2(px, px)), LG_C[6] if u3 < 0.1 else (LG_C[4] if hv3 > 0.5 else LG_C[3]))
				ci.draw_rect(Rect2(pv._snap(q3 - Vector2(cos(an2), sin(an2) * LG_SY) * px * 1.2), Vector2(px, px)), LG_INK[1])


## 旧做法（2）：状态件整张贴（彗星帧条、锁定印、咒域帧条），旋转 + 小数缩放，盖在所有单位上
static func _lg_draw_raw(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var fps: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	var t: int = pv.tier(o)
	var h: Dictionary = o.hw
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and float(fn.get("t", 0.0)) > 0.0:
		var r: float = float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, fn.b))
		pv._draw_raw(cv, "lg_raw_field", posmod(int(g.t * fps), maxi(1, int(pv._meta("lg_raw_field").get("n", 1)))), o.pos, float(h.fan_ang), r / 150.0)
	if h.has("bolts"):
		for bo in h.bolts:
			var pose: Array = load("res://scripts/render/fx_recipe.gd")._bolt_pose(bo)
			pv._draw_raw(cv, "lg_raw_bolt_e%d" % t, posmod(int(g.t * fps), maxi(1, int(pv._meta("lg_raw_bolt_e%d" % t).get("n", 1)))), pose[0], float(pose[1]), g.PX * 1.1)
	if not o.vg.is_empty():
		for xb in o.vg.bul:
			pv._draw_raw(cv, "lg_raw_bolt_e0", posmod(int(g.t * fps), maxi(1, int(pv._meta("lg_raw_bolt_e0").get("n", 1)))), (xb.p as Vector2) + Vector2(0, -16), (xb.v as Vector2).angle(), g.PX * 0.8)
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		var b: Vector2 = lk.e.pos + Vector2(0, -float(lk.e.r) * 0.5)
		cv.draw_line(_lg_tip(pv, o), b, Color(0.55, 0.6, 1.0, 0.9), 3.0)
		pv._draw_raw(cv, "lg_raw_lock", posmod(int(g.t * fps), maxi(1, int(pv._meta("lg_raw_lock").get("n", 1)))), lk.e.pos + Vector2(0, -float(lk.e.r) - 20.0), 0.0, g.PX * 1.3)
	if h.has("links"):
		for lkk in h.links:
			var mm: Array = lkk.m
			for j in range(1, mm.size()):
				if not mm[0].dead and not mm[j].dead:
					cv.draw_line(mm[0].pos + Vector2(0, -10), mm[j].pos + Vector2(0, -10), Color(0.65, 0.53, 1.0, 0.8), 2.0)
	for it in pv.items_for("logos"):
		if str(it.ly) == "raw" and str(it.get("lrt", "")) == "rawline":
			var u: float = (g.t - float(it.t0)) / maxf(0.01, float(it.life))
			if u >= 0.0 and u <= 1.0:
				cv.draw_line(it.a, (it.a as Vector2).lerp(it.b, u), Color(0.55, 0.6, 1.0, 0.9), 4.0)
