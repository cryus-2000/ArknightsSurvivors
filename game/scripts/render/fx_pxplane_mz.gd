## 水月（docs/261，照 docs/246 斯卡蒂的做法）
## 意象：深海、水母、触手、幻象。色：深蓝紫 8 阶（OP.mizuki）+ 水母荧光青；精二点缀荧光紫。
## 分档按「每升一档多一个新元素」（11-05 用户）：精零 = 伞面 + 水母；精一起触手出现；精二荧光紫 + 深蓝之籽 + 双触手 / 对缠。
## 普攻「伞击」= 腰高伞面月牙（伞沿扇贝 + 伞骨；精二伞骨荧光紫）+ 命中处青色水母绽开 + 精一起生命最低的那只脚下钻出触手（精零只绽开水母）；
## S1「唤醒」= 更大更白的伞面 + 青白沿 + 向外甩水，命中处三团大水母绽开 + 地上冲击环；精一起每团下面钻出触手；
## S2「囚徒困境」= 起手一圈触手钻出 + 中心冰蓝尖晶；持续期间伞击更薄更快、青白沿 + 幻影残弧，被触手打中的缠住（前后两半圈）；
## S3「镜花水月」= 起手大水母从脚下浮起 + 地上一圈水镜带月影；持续期间深蓝紫旋斩 + 荧光紫刃，脚下水镜，触手更粗；
## 触手五种形态按场合用：普攻追击拍击（精二多一根卷须）、唤醒刺穿、束缚卷须 + 缠绕、镜花水月粗拍击、连携群生。
## 精二「深蓝之籽」= 身后小水母改画像素水母（离身游猎时拖三点尾），蛰中一朵紫色小水母；连携「小触手」= 高触手钻出 + 缠住 1 秒。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const MI = preload("res://scripts/render/melee_impact.gd")   # 近战打击感包（docs/246 §11）：斩痕 / 照地光提亮
# ================================================================ 水月（docs/261，照 docs/246 斯卡蒂的做法） → fx_pxplane_mz.gd（docs/286 §4 第三批拆出）
const MZ_TENT_MAX := 5     # 同屏触手（同一名干员）；GCP 实机 E1 一次 5–6 根拍击堆成一丛，8 → 5
const MZ_COIL_MAX := 10    # 同屏缠绕
const MZ_BLOOM_MAX := 5    # 同屏命中水母绽开


static func _smz(pv: P):
	if pv._smzs == null:
		pv._smzs = load("res://scripts/characters/blocks/seg_mizuki.gd")   # 运行时取（避免和积木链循环 preload）
	return pv._smzs


static func _mz_pick(r: float, opts: Array) -> int:
	var best: int = int(opts[0])
	for v in opts:
		if absf(float(v) - r) < absf(float(best) - r):
			best = int(v)
	return best


static func _mz_count(pv: P, o, pre: String) -> int:
	var n := 0
	for it in pv.items:
		if str(it.oid) == str(o.id) and str(it.k).begins_with(pre) and str(it.ly) == "up":
			n += 1
	return n


## 伞面月牙（方向件 / 旋斩）：挂在人身上（fo，跟人走）；同一名干员只留上一刀 + 这一刀（不碎）
static func _mz_slash(pv: P, o, key: String, ang: float, spin: bool) -> void:
	var g = pv.g
	var sl: Array = []
	for it in pv.items:
		if str(it.oid) == str(o.id) and it.get("slash", false) and str(it.ly) == "up":
			sl.append(it.t0)
	if sl.size() >= 2:
		sl.sort()
		var keep_t: float = float(sl[sl.size() - 1])
		pv.items = pv.items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == str(o.id) and float(it.t0) < keep_t))
	var dk: Array = pv.pick_dir(ang)
	var ku: String = (key + "_up") if spin else "%s_up_d%d" % [key, dk[0]]
	var kg: String = (key + "_gd") if spin else "%s_gd_d%d" % [key, dk[0]]
	var fl: bool = dk[1] and not spin
	pv._push({"k": ku, "t0": g.t, "gp": pv._snap(o.pos), "flip": fl, "ly": "up", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})
	pv._push({"k": kg, "t0": g.t, "gp": pv._snap(o.pos), "flip": fl, "ly": "gd", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})


## 命中水母绽开：原点 = 命中点，排在被打那只前面；同屏至多 MZ_BLOOM_MAX 团
static func _mz_bloom(pv: P, o, e: Dictionary, key: String, raw: bool, t: int) -> void:
	var g = pv.g
	var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.55)
	if raw:
		pv._push({"k": "mz_raw_bloom_e%d" % t, "t0": g.t, "gp": hp, "ly": "raw", "rot": 0.0, "sc": g.PX * 1.2, "oid": str(o.id)})
		return
	if _mz_count(pv, o, "mz_bloom") + _mz_count(pv, o, "mz_sting") >= MZ_BLOOM_MAX:
		return
	pv._push({"k": key, "t0": g.t, "gp": pv._snap(hp), "gy": float(e.pos.y) + 2.0, "flip": false, "ly": "up", "oid": str(o.id)})


## 触手：目标脚边（离水月远的一侧）钻出，朝水月倾（拖拽感）；束缚（stun ≥ 0.45，非 Boss）时再缠住 min(stun, 1.2) 秒
static func _mz_tent(pv: P, o, e: Dictionary, at: Vector2, key: String, raw: bool, t: int, bind: float) -> void:
	var g = pv.g
	var side: float = 1.0 if at.x >= o.pos.x else -1.0
	var er: float = float(e.get("r", 14.0))
	var arc: bool = key.contains("_slam_") or key.contains("_big_")   # 拍击要越过头顶拍下来：底座放远一点，落点正好在目标上（不拍到旁边空地）
	var base: Vector2 = at + Vector2(side * (er * 0.55 + (16.0 if arc else 0.0)), 3.0)
	if raw:
		pv._push({"k": "mz_raw_tent_e%d" % t, "t0": g.t, "gp": base, "ly": "raw", "rot": 0.0, "sc": g.PX * 1.15, "oid": str(o.id)})
		return
	var busy := false   # 同一只身上已经有一根还没缩回的触手：不再叠（囚徒困境 / 镜花水月连挥时不堆成一丛）
	for it in pv.items:
		if it.has("tg") and is_same(it.tg, e) and g.t - float(it.t0) < 0.35:
			busy = true
			break
	if not busy and _mz_count(pv, o, "mz_tent") < MZ_TENT_MAX:
		pv._push({"k": key + "_up", "t0": g.t, "gp": pv._snap(base), "gy": base.y + 0.5, "flip": side > 0.0, "ly": "up", "oid": str(o.id), "tg": e})
		pv._push({"k": key + "_gd", "t0": g.t, "gp": pv._snap(base), "flip": side > 0.0, "ly": "gd", "oid": str(o.id)})
	if bind >= 0.45 and not e.get("boss", false) and not e.get("dead", false):
		_mz_coil(pv, o, e, clampi(t, 1, 2), minf(bind, 1.2))


static func _mz_coil(pv: P, o, e: Dictionary, t: int, life: float) -> void:
	var g = pv.g
	var found := false
	for it in pv.items:   # 同一只已经缠着：续时间，不叠
		if it.has("ef") and is_same(it.ef, e):
			it.life = maxf(float(it.life), g.t - float(it.t0) + life)
			found = true
	if found or _mz_count(pv, o, "mz_coil") >= MZ_COIL_MAX * 2:
		return
	var rx: int = _mz_pick(float(e.r) * 0.5, [6, 9, 13, 18])
	for half in ["back", "front"]:
		pv._push({"k": "mz_coil_r%d_e%d_%s_up" % [rx, t, half], "t0": g.t, "gp": pv._snap(e.pos), "ef": e, "sk": -1.5 if half == "back" else 1.5,
			"flip": false, "ly": "up", "oid": str(o.id), "loop": true, "life": life})


static func _ev_mz(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	match kind:
		"mz_umb":
			var ang: float = float(d.get("ang", 0.0))
			var r: float = float(d.get("r", 112.0))
			var lst: Array = (d.get("es", []) as Array).duplicate()
			lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
			var nb := 2
			var bk: String = "mz_bloom_e%d_up" % t
			if d.get("s3", false):   # 镜花水月：全范围深蓝紫旋斩
				if raw:
					pv._push({"k": "mz_raw_spin3", "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 81.0, "oid": str(o.id)})
				else:
					_mz_slash(pv, o, "mz_spin3_r%d" % _mz_pick(r * 0.5, [81, 104]), 0.0, true)
				nb = 3
				bk = "mz_bloom_e2_up"
			elif d.get("emp", false):   # 唤醒强化的那一击（命中处另有三团大水母：mz_burst）
				if raw:
					pv._push({"k": "mz_raw_s1_e%d" % t, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / 73.0, "oid": str(o.id)})
				else:
					_mz_slash(pv, o, "mz_s1_r%d_e%d" % [_mz_pick(r * 0.5, [73, 92]), t], ang, false)
				nb = 1
			else:
				var r0: int = _mz_pick(r * 0.5, [56, 70])
				if raw:
					pv._push({"k": "mz_raw_atk_e%d" % t, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / 56.0, "oid": str(o.id)})
				elif d.get("s2", false):   # 囚徒困境期间
					_mz_slash(pv, o, "mz_s2_r%d_e%d" % [r0, clampi(t, 1, 2)], ang, false)
				else:
					_mz_slash(pv, o, "mz_atk_r%d_e%d" % [r0, t], ang, false)
			for i in mini(nb, lst.size()):
				_mz_bloom(pv, o, lst[i], bk, raw, t)
			if pv.mode() == 1 and not lst.is_empty():
				var hp: Vector2 = lst[0].pos + Vector2(0, -float(lst[0].r) * 0.5)
				for i in mini(2, lst.size()):   # docs/270：命中帧要量得出核心辉光——命中点一小撮白芯进 emit（4 拍）
					var hot := {"k": "", "mzhot": true, "t0": g.t, "gp": pv._snap(lst[i].pos + Vector2(0, -float(lst[i].r) * 0.55)), "ly": "gd", "oid": str(o.id), "life": 4.0 / 15.0}
					if i == 0:   # 颗粒等白芯第一次画的时候再撒（发光层晚一帧上屏：颗粒和辉光落在同一帧）；每次挥伞 4–5 颗（原来伞击 + 每根触手各撒，一簇 13 颗）
						hot["gr"] = [hp, float(lst[0].pos.y) + 2.0, 4 + (1 if t >= 2 else 0), t, (hp - o.pos).normalized()]
					pv._push(hot)
				R._light(o, hp, 100.0, 0.5 * MI.lit_k(g), 0.12, p.light)   # docs/270 复测：照地亮度峰值 +42 → 0.45 时 +48（下限 +50）→ 0.5（实测约 0.68）
		"mz_tent":
			var e: Dictionary = d.get("e", {})
			if e.is_empty():
				return
			var s3: bool = d.get("s3", false)
			if t == 0 and not s3:   # 11-05 用户：精零普攻不出触手（触手是精一的招牌），追击那一下只在目标身上绽开一朵水母
				_mz_bloom(pv, o, e, "mz_bloom_e0_up", raw, t)
				return
			var stn: float = float(d.get("stun", 0.0))
			_mz_tent(pv, o, e, d.get("at", e.pos), _mz_tk(pv, "big", 2) if s3 else (_mz_tk(pv, "curl", t) if stn >= 0.45 else _mz_tk(pv, "slam", t)), raw, t, stn)   # 触手不再另撒颗粒（颗粒数算进伞击那一簇）
		"mz_burst":   # 唤醒创伤扩散：大水母绽开 + 地上冲击环
			var at: Vector2 = d.get("at", o.pos)
			if raw:
				pv._push({"k": "mz_raw_bloom_e%d" % t, "t0": g.t, "gp": at + Vector2(0, -16), "ly": "raw", "rot": 0.0, "sc": g.PX * 2.2, "oid": str(o.id)})
				return
			pv._push({"k": "mz_burst_e%d_up" % t, "t0": g.t, "gp": pv._snap(at + Vector2(0, -16)), "gy": at.y + 3.0, "flip": false, "ly": "up", "oid": str(o.id)})
			pv._push({"k": "mz_burst_e%d_gd" % t, "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})
			if t >= 1:   # 精一起：每团大水母下面钻出一根触手（分档加新元素，不靠换色）
				_mz_tent(pv, o, {"pos": at, "r": 10.0, "boss": true}, at, _mz_tk(pv, "pierce", t), raw, t, 0.0)
			if pv.mode() == 1:
				R._grains(o, at + Vector2(0, -18), at.y, "ink", 3, {"tier": t})   # docs/270：三团合一簇 ≤ 16（伞击 4–5 + 3 × 3）
				pv._push({"k": "", "mzhot": true, "t0": g.t, "gp": pv._snap(at + Vector2(0, -16)), "ly": "gd", "oid": str(o.id), "life": 4.0 / 15.0})
				R._light(o, at + Vector2(0, -14), 140.0, 0.55 * MI.lit_k(g), 0.14, p.light)
		"mz_sting":   # 深蓝之籽蛰中：一朵紫色小水母
			var e2: Dictionary = d.get("e", {})
			if not e2.is_empty() and not raw:
				_mz_bloom(pv, o, e2, "mz_sting_up", raw, t)
		"mz_stake":
			var at2: Vector2 = d.get("at", o.pos)
			_mz_tent(pv, o, {"pos": at2, "r": 8.0, "boss": true}, at2, _mz_tk(pv, "pierce", t), raw, t, 0.0)
		"mz_splash":   # 扩散：一圈细水纹（每拍至多 3 圈）
			if raw or _mz_count_gd(pv, o, "mz_ripple") >= 3:
				return
			pv._push({"k": "mz_ripple_gd", "t0": g.t, "gp": pv._snap(d.get("at", o.pos)), "flip": false, "ly": "gd", "oid": str(o.id)})
		"mz_link":   # 连携「小触手」：高触手钻出 + 缠住 1 秒（不分档）
			for e3 in d.get("es", []):
				if e3.get("dead", false):
					continue
				_mz_tent(pv, o, e3, e3.pos, _mz_tk(pv, "cluster", 2), raw, 2, 0.0 if e3.get("boss", false) else 1.0)
			if pv.mode() == 1:
				R._light(o, d.get("c", o.pos), 150.0, 0.5, 0.15, p.light)
		"shape":   # 惊跳反射·余悸（circle，src 触手）：身边一圈触手抽打
			if d.get("circle", false) and not raw:
				var c: Vector2 = d.get("c", o.pos)
				pv._push({"k": "mz_awk2_up", "t0": g.t, "gp": pv._snap(c), "flip": false, "ly": "up", "oid": str(o.id)})
				pv._push({"k": "mz_awk2_gd", "t0": g.t, "gp": pv._snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
		"skill":
			if raw:
				return
			var i: int = int(d.get("i", -1))
			if i == 1:   # 囚徒困境起手：一圈触手钻出 + 中心冰蓝尖晶（跟人）
				var tt: int = clampi(t, 1, 2)
				pv._push({"k": "mz_s2cast_e%d_up" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
				pv._push({"k": "mz_s2cast_e%d_gd" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				R._light(o, o.pos + Vector2(0, -14), 160.0, 0.7, 0.15, p.hot)
			elif i == 2:   # 镜花水月起手：大水母浮起（跟人）+ 水镜月影
				pv._push({"k": "mz_moon_up", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
				pv._push({"k": "mz_moon_gd", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "ink", 6, {"tier": 2})
				R._light(o, o.pos + Vector2(0, -30), 170.0, 0.7, 0.15, p.light)


## 触手形态键（11-05 用户「多做几个形态」）：slam 拍击（普攻追击）/ pierce 刺穿（唤醒大水母下、触手桩）/ curl 卷须（束缚）/ big 粗拍击（镜花水月）/ cluster 群生（连携）；
## 每种 3 个变体（弯向 / 长短 / 粗细不同），按画面随机数挑，不像复制粘贴
static func _mz_tk(pv: P, form: String, t: int) -> String:
	var g = pv.g
	var tt: int = 2 if form in ["big", "cluster"] else clampi(t, 1, 2)
	return "mz_tent_%s_e%d_v%d" % [form, tt, g.vrng.randi_range(0, 2)]


static func _mz_count_gd(pv: P, o, pre: String) -> int:
	var g = pv.g
	var n := 0
	for it in pv.items:
		if str(it.oid) == str(o.id) and str(it.k).begins_with(pre) and str(it.ly) == "gd" and g.t - float(it.t0) < 1.0 / 15.0:
			n += 1
	return n


## 地面层：贴地件 + 唤醒充能小环 + 镜花水月水镜（跟人）
static func _mz_draw_floor(pv: P, o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	if o.ammo[0] > 0:
		pv._draw_strip(cv, "mz_ready_gd", pv.frame_of(0.0), pv._snap(o.pos + Vector2(0, 4)), false, false)
	if o.skill_active_left(2) > 0.0:
		var rr: float = float(o.hw.mz.get("s3_fx_radius", 0.0)) if o.hw.has("mz") else 0.0
		if rr <= 0.0:
			rr = 162.0
		pv._draw_strip(cv, "mz_pool_r%d_gd" % _mz_pick(rr * 0.5, [81, 104]), pv.frame_of(0.0), pv._snap(o.pos + Vector2(0, 2)), false, false)
	for it in pv.items_for(id):
		if str(it.ly) == "gd":
			if it.has("mzhot"):
				_mz_hot(pv, it)
				continue
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), pv._gp(it), it.flip, true)


## 命中白芯：只进发光层（4 拍：十字 + 斜角，逐拍收小变淡，emit 预算内），不画色层——色层的亮由水母绽开那一帧自己画；
## docs/270 复测：体检挑的命中帧在出手后约 0.2 秒，2 拍白芯已熄（辉光面积 8），延到 4 拍
static func _mz_hot(pv: P, it: Dictionary) -> void:
	var g = pv.g
	if it.has("gr"):
		var gr: Array = it.gr
		it.erase("gr")
		var oo = pv._op(str(it.oid))
		if oo != null:
			load("res://scripts/render/fx_recipe.gd").of(g)._grains(oo, gr[0], gr[1], "ink", int(gr[2]), {"tier": int(gr[3])}, gr[4])
	if not g.optical_on:
		return
	var f: int = pv.frame_of(float(it.t0))
	if f < 0 or f > 3:
		return
	var fr: int = Engine.get_process_frames()
	if fr != pv._emit_frame:
		pv._emit_frame = fr
		pv._emit_n = 0
	var px: float = g.PX
	var c0: Vector2 = it.gp
	var k: float = minf(1.0, Bal.v("fx/px_plane_emit", 0.8) * MI.lit_k(g) * [1.0, 0.9, 0.75, 0.55][f])
	var pts: Array = [Vector2.ZERO, Vector2(px, 0), Vector2(-px, 0), Vector2(0, px), Vector2(0, -px), Vector2(px, px), Vector2(-px, px), Vector2(px, -px), Vector2(-px, -px)]
	if f <= 1:
		pts += [Vector2(px * 2, 0), Vector2(-px * 2, 0), Vector2(0, px * 2), Vector2(0, -px * 2)]
	for q in pts:
		if pv._emit_n >= P.EMIT_CAP:
			return
		pv._emit_n += 1
		g.glow_next.append([c0 + q, px, Color(0.85, 0.97, 1.0, k)])


## 排序项：深蓝之籽（身后 / 离身游猎的小水母）、藏品剑气（小水母游过去）
static func _mz_sort_items(pv: P, o, out: Array) -> void:
	var t: int = pv.tier(o)
	var mz: Dictionary = o.hw.get("mz", {})
	for j in mz.get("jel", []):
		var jp: Vector2 = j.p
		out.append({"mzj": "mz_jelly_up", "a": jp, "v": j.get("v", Vector2.ZERO) if str(j.ph) != "home" else Vector2.ZERO, "gp": pv._snap(jp + Vector2(0, 6)), "gy": jp.y + 34.0})
	if o.get("vg") is Dictionary and not o.vg.is_empty():
		for q in o.vg.get("qi", []):
			var qp: Vector2 = pv._wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q)
			out.append({"mzj": "mz_qi_e%d_up" % t, "a": qp + Vector2(0, -14), "v": q.v, "gp": pv._snap(qp + Vector2(0, -8)), "gy": qp.y + 1.0})


## 小水母：循环帧条 + 离身时身后三点尾（逐美术像素，越后越暗）
static func _mz_draw_jelly(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var v: Vector2 = it.v
	if v.length() > 1.0:
		var back: Vector2 = -v.normalized()
		var cols := [Color.html("#9aa8ff"), Color.html("#5a7cf0"), Color.html("#3150c8")]
		for i in 3:
			var pp: Vector2 = pv._snap((it.a as Vector2) + back * float(6 + i * 6))
			ci.draw_rect(Rect2(pp, Vector2(g.PX, g.PX)), cols[i])
	pv._draw_strip(ci, str(it.mzj), pv.frame_of(0.0), it.gp, false, false)
