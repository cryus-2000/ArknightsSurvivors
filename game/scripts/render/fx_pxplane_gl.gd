## 歌蕾蒂娅「转平面」（docs/263，开关 fx/px_plane）：fx_pxplane 的歌蕾蒂娅一节单独成文件（同批四人同时改 fx_pxplane.gd，分开免得合并冲突）。
## 全部是静态函数，第一个参数 r = fx_pxplane 实例（借它的件表、帧条绘制、15 fps 节拍、发光层、精英档）。只画，不碰玩法、不抽随机数（变化取位置 / 时刻的哈希）。
## 意象：钩索、锚、海流。普攻每一下都是掷钩 → 落地水刺 → 绷紧 → 拖回（地上一道 V 字拖痕）→ 到位拍水；
##   精一「锚定」：到位处地上一枚锚印（眩晕期间）；精二（质变）：水团芯换深渊紫、落点再炸开一小冠深渊紫水花，到位「冲撞」一圈贴地细涟漪。
## S1 大洋裂断 = 重钩（两格粗链）+ 一大冠水花炸开 + 沿钩线两侧像拉链一样掀起翻卷的浪（「裂断」，运行时逐格画）、塌成贴地白沫；
## S2 掌握怒海 = 起手倾斜水环升起 + 脚下浪沫圈（持续）+ 每次掷钩身边海水往里倒卷；S3 碎漩狂舞 = 龙卷水墙（用户认可的龙卷版转平面：远半圈 / 近半圈分开排序）。
## 连携（技能连携 v2「聚拢」）= 几道链同时甩出把怪拖向区域 + 四周海水往中心倒卷、汇成一柱。
## 帧条：game/art/fx/pxp/pxp_gl_*.png + data/pxp_gladiia.json（tools/pxplane_bake_gladiia.py）；运行时线状件（链、钩头、拖痕、裂断暗沟、沉底锁链）逐美术像素画。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Bal = preload("res://scripts/core/balance.gd")
const MI = preload("res://scripts/render/melee_impact.gd")
const C := [Color("#0d1a2e"), Color("#182f51"), Color("#294a78"), Color("#3a65a0"), Color("#4c80c7"), Color("#8bacdb"), Color("#c9d9ee"), Color("#ffffff")]   # OP.gladiia 7 阶 + 压底
const CH := [Color("#243246"), Color("#5c7090"), Color("#8798b3"), Color("#dbe2ec"), Color("#f6f8fb")]   # 链：OP.gladiia_tide 冷灰蓝
const ACC := Color("#b3a8ee")   # 精二点缀深渊紫（OP.gladiia_abyss）
const ACC2 := Color("#7a6cc8")
const CYAN := Color("#6ec6d8")   # S1 翻卷浪的青色中段（深海蓝 → 青 → 白沫）
const SY := 0.72
const HIT_R := [38, 52, 66]
const S1_R := [35, 48, 61]
const S3_R := 65.0   # 美术像素（s3_r 130）
const WAKE_TAIL := 0.45   # 到位后拖痕散掉的时长
const SPLASH_BEAT := 2    # 扩散（late_shape）每拍至多几团
## S1 爆发档的照地灯（docs/270 §3：爆发 半径 140–240 / 强度 0.6–0.9，取中段；11-05 体检照地峰值 +55 卡在边上后补）
const S1_LIGHT_R := 190.0
const S1_LIGHT_I := 0.75
const S1_WAVE_LIGHT_R := 160.0
const S1_WAVE_LIGHT_I := 0.6
const S1_LIGHT_CAP := 0.85   # 打击感包提亮 ×1.35 后也不超过上限 0.9

static var _SegU = null


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


## 一维值噪声（相邻格的哈希平滑插值，0..1）
static func _vn(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_h(i), _h(i + 1.0), f)


static func _bucket(v: float, opts: Array) -> int:
	return PxU.nearest(opts, v)


static func _strip_pair(r, o, key: String, at: Vector2, follow := false, sk := 0.0) -> void:
	var a := {"k": "gl_" + key + "_up", "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	var b := {"k": "gl_" + key + "_gd", "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if follow:
		a["fo"] = at - o.pos
		b["fo"] = at - o.pos
	if sk != 0.0:
		a["sk"] = sk
	r._push(a)
	r._push(b)


## 贴地涟漪两件：近半圈零星水沫 up（排在环的近沿）+ 地面细涟漪 gd；ra = 环半径（美术像素）
static func _ring3(r, o, key: String, at: Vector2, ra: float, follow := false) -> void:
	_strip(r, o, key + "_up", at, "up", follow, ra * 2.0 * SY)
	_strip(r, o, key + "_gd", at, "gd", follow)


static func _strip(r, o, k: String, at: Vector2, ly: String, follow := false, sk := 0.0, flip := false) -> void:
	var it := {"k": "gl_" + k, "t0": r.g.t, "gp": r._snap(at), "flip": flip, "ly": ly, "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	if sk != 0.0:
		it["sk"] = sk
	r._push(it)


static func _raw(r, o, k: String, at: Vector2, rot: float, sc: float) -> void:
	r._push({"k": "gl_" + k, "t0": r.g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 这一拍（1/15 秒）同一名干员某类件已出几个
static func _beat_n(r, o, key: String) -> int:
	return r._lm_beat_n(o, "gl_" + key)


# ================================================================ 事件

static func ev(r, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = r.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:
		print("PXPLOG gl %s %s %d %.3f" % [kind, str(d.get("src", "")), Engine.get_process_frames(), float(g.t)])
	match kind:
		"gl_throw":
			var hk: Dictionary = d.hk
			if not raw and o.skill_active_left(1) > 0.0 and str(hk.b.get("src", "")) == "钩索":   # 掌握怒海：每次掷钩身边海水往里倒卷（拉近 160 内）
				_ring3(r, o, "s2pull_e%d" % maxi(t, 1), o.pos, 80.0)
		"gl_impact":
			var hki: Dictionary = d.hk
			var c: Vector2 = d.c
			var heavy: bool = str(hki.b.get("src", "")) == "大洋裂断"
			var ra: float = float(d.get("r", 77.0)) * 0.5
			hki["_pxf"] = g.t   # 画面专用：绷紧那一拍链子发白（玩法不读）
			if raw:
				_raw(r, o, "raw_s1hit" if heavy else "raw_hit", c, 0.0, g.PX * ra / (35.0 if heavy else 38.0))
				return
			if heavy:
				_strip_pair(r, o, "s1hit_r%d_e%d" % [_bucket(ra, S1_R), t], c)
				_parting(r, o, o.pos, c, t)
				_burst(r, o, R, p, c, d.get("es", []), 8 + 3 * t, S1_LIGHT_R, S1_LIGHT_I)   # docs/270 爆发档：灯取标准中段（半径 140–240 / 强度 0.6–0.9）
				if o.pos.distance_to(c) >= 60.0:   # 翻卷浪掀到一半处再挂一盏（浪身本身也是爆发的一部分，照亮钩线）
					var mid: Vector2 = o.pos.lerp(c, 0.55) + Vector2(0, -12)
					R._light(o, mid, S1_WAVE_LIGHT_R, minf(S1_LIGHT_CAP, S1_WAVE_LIGHT_I * MI.lit_k(g)), 0.15, p.light)
			else:
				_strip_pair(r, o, "hit_r%d_e%d" % [_bucket(ra, HIT_R), t], c)
				_burst(r, o, R, p, c, d.get("es", []), 3 + t, 110.0, 0.4)
		"gl_drag":
			if raw:
				return
			var hk2: Dictionary = d.hk
			for dg in hk2.drag:
				r._push({"glrt": "wake", "e": dg.e, "from": dg.from, "t0": g.t, "t1": g.t + float(hk2.dur), "life": float(hk2.dur) + WAKE_TAIL, "ly": "gd", "oid": str(o.id), "k": "", "gp": dg.from, "sd": float(dg.e.get("id", 0)) * 0.37})
		"gl_arrive":
			if raw:
				return
			var hk3: Dictionary = d.hk
			var heavy2: bool = str(hk3.b.get("src", "")) == "大洋裂断"
			var n: int = 0
			for e in d.get("es", []):
				if n >= 3:
					break
				n += 1
				_strip_pair(r, o, ("s1arr_e%d" if heavy2 else "arr_e%d") % t, e.pos)
			if n > 0:
				var e0: Dictionary = d.es[0]
				R._grains(o, e0.pos + Vector2(0, -6), float(e0.pos.y) + 2.0, "ink", 2 + n + (3 if heavy2 else 0), {"tier": t, "grain_spd": 1.0})
				R._light(o, e0.pos + Vector2(0, -6), 90.0, 0.35, 0.1, p.light)
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c2: Vector2 = d.get("c", o.pos)
			match src:
				"冲撞":   # 精二：拖回到位那一刻身前一圈往外走的碎浪
					if raw:
						_raw(r, o, "raw_ram", c2, 0.0, g.PX * float(d.get("r", 80.0)) * 0.5 / 40.0)
					else:
						_ring3(r, o, "ram", c2, 40.0)
						_burst(r, o, R, p, c2, d.get("es", []), 5, 150.0, 0.5)
				"反震":
					if not raw:
						_ring3(r, o, "pop", c2, 60.0)
						_burst(r, o, R, p, c2, [], 6, 160.0, 0.45)
				"碎漩狂舞":   # S3 每跳：地上四段浪沫弧往里收（拉扯）
					if not raw:
						_strip(r, o, "s3tick_gd", c2, "gd")
						R._grains(o, c2 + Vector2(0, -20), c2.y + 2.0, "ink", 3, {"tier": 2, "grain_spd": 1.0})
		"gl_slash":   # 回收斩（成长节点）：腰高刀痕，挂在人身上
			if raw:
				return
			var dk: Array = r.pick_dir(float(d.ang))
			_strip(r, o, "slash_up_d%d" % dk[0], o.pos, "up", true, 0.0, dk[1])
			_strip(r, o, "slash_gd_d%d" % dk[0], o.pos, "gd", true, 0.0, dk[1])
			r._cuts(o, d.get("es", []), t, 3)
		"gl_geyser":
			if not raw:
				_strip_pair(r, o, "geyser", d.p)
		"gl_barb":   # 倒钩：拖拽路径迸的火星改成少量水沫颗粒
			if not raw and _beat_n(r, o, "barb") < 2:
				var eb: Dictionary = d.e
				R._grains(o, eb.pos + Vector2(0, -6), float(eb.pos.y) + 2.0, "ink", 1, {"tier": t, "grain_spd": 0.7})
		"gl_splash":   # late_shape「扩散」：被钩中的那只身边一圈小浪
			if not raw and _beat_n(r, o, "splash") < SPLASH_BEAT:
				var es: Dictionary = d.e
				_ring3(r, o, "splash", es.pos, 30.0)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1 and not raw:   # 掌握怒海起手：倾斜水环（远半圈排在她身后）+ 脚下一柱
				var tt: int = maxi(t, 1)
				_strip(r, o, "s2cast_e%d_bk" % tt, o.pos, "up", true, -66.0)
				_strip(r, o, "s2cast_e%d_up" % tt, o.pos, "up", true)
				_strip(r, o, "s2cast_e%d_gd" % tt, o.pos, "gd", true)
				R._grains(o, o.pos + Vector2(0, -30), o.pos.y, "ink", 6, {"tier": tt})
				R._light(o, o.pos + Vector2(0, -16), 140.0, 0.5, 0.15, p.light)
		"gl_s3":
			var f: Dictionary = d.f
			R._light(o, f.pos + Vector2(0, -30), 220.0, 0.55, 0.15, p.light)
			if not raw:
				R._grains(o, f.pos + Vector2(0, -40), float(f.pos.y), "ink", 8, {"tier": 2})
		"gl_s3end":
			var f2: Dictionary = d.f
			if not raw:
				_strip(r, o, "s3close_bk", f2.pos, "up", false, -S3_R * 2.0 * SY)
				_strip(r, o, "s3close_up", f2.pos, "up", false, S3_R * 2.0 * SY)
				_strip(r, o, "s3close_gd", f2.pos, "gd")
				R._grains(o, f2.pos + Vector2(0, -50), float(f2.pos.y) + 2.0, "ink", 12, {"tier": 2})
			R._light(o, f2.pos + Vector2(0, -30), 240.0, 0.7, 0.15, p.light)
			if g.ult != null:
				g.ult.shake(3.0, 0.15)   # 用户同意的量级（同 fx_gladiia_s3 收尾）
		"gl_lthrow":   # 连携「聚拢」甩钩：几道链同时甩出（over 层），被拖的怪地上留拖痕
			if raw:
				return
			var pull: Array = d.get("pull", [])
			r._push({"glrt": "lchain", "es": pull, "t0": g.t, "life": 1.0, "ly": "ov", "oid": str(o.id), "k": "", "gp": o.pos})
			for e in pull:
				r._push({"glrt": "wake", "e": e, "from": e.pos, "t0": g.t + 0.14, "t1": g.t + 0.5, "life": 0.5 + WAKE_TAIL, "ly": "gd", "oid": str(o.id), "k": "", "gp": e.pos, "sd": float(e.get("id", 0)) * 0.37})
		"gl_lland":
			var c3: Vector2 = d.c
			if not raw:
				_ring3(r, o, "link", c3, 75.0)
				R._grains(o, c3 + Vector2(0, -30), c3.y + 2.0, "ink", 10, {"tier": 1})
			R._light(o, c3 + Vector2(0, -20), 220.0, 0.6, 0.15, p.light)


static func _burst(r, o, R, p: Dictionary, at: Vector2, es: Array, n: int, lr: float, li: float) -> void:
	if r.mode() != 1:
		return
	var m := {"tier": r.tier(o), "grain_spd": 1.0}
	var hp: Vector2 = at + Vector2(0, -8)
	if not es.is_empty():
		var e: Dictionary = es[0]
		hp = e.pos + Vector2(0, -float(e.r) * 0.5)
	R._grains(o, hp, at.y + 2.0, "ink", mini(n, 2 + es.size() + n / 2), m)
	R._light(o, hp, lr, minf(S1_LIGHT_CAP, li * MI.lit_k(r.g)), 0.12, p.light)


## S1「裂断」（用户 11-05 第三轮：「水墙不用去掉，换一个表现形式，可以稍微华丽一点」）：沿钩线两侧掀起翻卷的浪——
## 从她脚边往目标像拉链一样依次掀起，浪身外倾、浪顶卷成白色浪舌碎成水沫、甩出成团水滴，约 0.6 秒后塌成贴地白沫与细涟漪；
## 浪身深海蓝 → 青 → 白沫，带少量海流纹，浪尖细碎亮光（进发光层）；两侧有空隙，中间被拉的怪看得见；精二浪更高、透深渊紫、外侧再掀第二层。
## 立起的浪按 32 世界像素一段分段排序；地上一道暗沟 + 两侧白沫线往外推开成细涟漪
static func _parting(r, o, a: Vector2, c: Vector2, t: int) -> void:
	var L: float = a.distance_to(c)
	if L < 60.0:
		return
	var d: Vector2 = (c - a) / L
	var s: float = 28.0
	var k: int = 0
	while s < L - 8.0 and k < 14:
		var s1: float = minf(L - 8.0, s + 32.0)
		var mid: Vector2 = a + d * ((s + s1) * 0.5)
		r._push({"glrt": "part", "a": a, "d": d, "s0": s, "s1": s1, "L": L, "tier": t, "t0": r.g.t, "life": PART_ZIP + PART_LIFE, "ly": "up", "oid": str(o.id), "k": "", "gp": mid, "gy": mid.y + 1.0})
		s = s1
		k += 1
	r._push({"glrt": "trench", "a": a, "d": d, "L": L, "tier": t, "t0": r.g.t, "life": 1.0, "ly": "gd", "oid": str(o.id), "k": "", "gp": a})


const PART_ZIP := 0.25    # 从脚边掀到目标处用的时间（拉链）
const PART_LIFE := 0.7    # 每一处浪从掀起到塌完


## 一段翻卷浪（两侧）：u = 这一处的局部时刻（按离她的距离依次推迟）
static func _draw_part(r, ci, it: Dictionary) -> void:
	var g = r.g
	var tier: int = int(it.tier)
	var a: Vector2 = it.a
	var d: Vector2 = it.d
	var L: float = float(it.L)
	var nrm := Vector2(-d.y, d.x * SY).normalized()
	var hmax: float = [10.0, 13.0, 17.0][tier]
	var s: float = float(it.s0)
	while s < float(it.s1):
		var u: float = g.t - float(it.t0) - PART_ZIP * (s / maxf(1.0, L))
		if u >= 0.0 and u < PART_LIFE:
			var taper: float = clampf((s - 28.0) / 30.0, 0.0, 1.0) * clampf((L - 8.0 - s) / 24.0, 0.0, 1.0)
			for layer in (2 if tier >= 2 else 1):
				var lu: float = u - 0.06 * float(layer)
				if lu < 0.0:
					continue
				for sg in [-1.0, 1.0]:
					var gv: float = _vn(s / 14.0 + sg * 1.7 + float(layer) * 3.1)
					if gv < 0.3:   # 空隙（成段，中间被拉的怪看得见）
						continue
					var hs: float = _vn(s / 9.0 + sg * 3.0 + float(layer))   # 浪高沿钩线缓缓起伏（不成梳齿）
					var off: float = 14.0 + 8.0 * float(layer)
					var bp: Vector2 = a + d * s + nrm * sg * off * (1.0 + 0.12 * hs)
					var hl: float = hmax * (1.0 - 0.45 * float(layer))
					_wave_col(r, ci, bp, nrm * sg, lu, hl * (0.6 + 0.4 * hs) * (0.4 + 0.6 * taper) * clampf((gv - 0.3) / 0.08, 0.3, 1.0), tier, s + sg * 31.0 + float(layer) * 7.0, gv > 0.36)
		s += 2.0


## 翻卷浪的一列：0.1 秒掀起 → 浪身外倾、浪顶卷出白色浪舌 → 0.32 秒起浪舌碎成水沫甩出水滴 → 0.45–0.7 秒塌下
static func _wave_col(r, ci, bp: Vector2, out: Vector2, u: float, H: float, tier: int, sd: float, tongue := true) -> void:
	var rise: float = 1.0 - pow(1.0 - clampf(u / 0.1, 0.0, 1.0), 3.0)
	var fall: float = clampf((u - 0.45) / 0.25, 0.0, 1.0)
	var curl: float = clampf(u / 0.3, 0.0, 1.0)
	var h: float = H * rise * (1.0 - fall)
	var hp: int = int(round(h))
	if hp >= 1:
		for z in hp + 1:
			var kz: float = float(z) / maxf(1.0, float(hp))
			var c: Color = C[2] if kz < 0.3 else (C[4] if kz < 0.6 else (CYAN if kz < 0.85 else C[6]))
			if tier >= 2 and kz > 0.25 and kz < 0.6 and _h(sd * 0.7 + float(z) * 1.3) > 0.55:
				c = ACC2   # 精二：浪身里透出深渊紫
			if kz > 0.2 and kz < 0.8 and _h(sd * 0.3 + float(z) * 0.9 + u * 15.0) > 0.86:
				c = C[5]   # 少量海流纹
			var lean: Vector2 = out * (kz * kz * 4.0 * curl)
			r._px(ci, bp + lean + Vector2(0, -2.0 * float(z)), c)
		# 浪舌：浪顶往外卷出 2–3 格白，再往下垂一格
		if tongue and curl > 0.3 and u < 0.36:   # 空隙边上不画（免得孤零零一根竖白）；朝镜头 / 背镜头的浪舌压短
			var top: Vector2 = bp + out * (4.0 * curl) + Vector2(0, -2.0 * float(hp))
			var tl: int = (1 if absf(out.y) > 0.7 else 2) + int(_h(sd) * 2.0)
			for q in tl:
				r._px(ci, top + out * 2.0 * float(q + 1), C[7])
			r._px(ci, top + out * 2.0 * float(tl) + Vector2(0, 2), C[6])
			if _h(sd * 1.9 + floorf(u * 15.0)) > 0.72:   # 浪尖细碎亮光
				r._glow(top + out * 2.0, C[7])
				r._px(ci, top + out * 2.0 + Vector2(0, -2), C[7])
	# 浪舌碎成水沫、甩出成团水滴（有重力）
	if u > 0.32 and u < 0.62 and _h(sd * 0.57) > 0.4:
		var v: float = u - 0.32
		var dp: Vector2 = bp + out * (8.0 + 70.0 * v) + Vector2(0, -2.0 * H * 0.85 - 40.0 * v + 420.0 * v * v)
		if dp.y < bp.y:
			var dc: Color = ACC if tier >= 2 and _h(sd * 2.3) > 0.7 else C[6]
			r._px(ci, dp, dc)
			if _h(sd * 3.1) > 0.5:
				r._px(ci, dp + Vector2(2, 0), C[5])

# ================================================================ 绘制

## 地面层：贴地件 + 运行时贴地件（拖痕、裂断暗沟）+ 状态件（S2 脚下浪沫圈、S3 龙卷地面边、沉底锁链）
static func floor_layer(r, o) -> void:
	var cv = o.cv
	var g = r.g
	var id: String = str(o.id)
	if o.skill_active_left(1) > 0.0:
		r._draw_strip(cv, "gl_s2aura_e%d_gd" % maxi(r.tier(o), 1), r.frame_of(0.0), r._snap(o.pos + Vector2(0, 2)), false, false)
	for f in o.fields:
		if f.get("pxp", false):
			var born: float = g.t - float(f.t)
			if float(f.t) < 0.33:
				r._draw_strip(cv, "gl_s3open_gd", r.frame_of(born), r._snap(f.pos), false, true)
			else:
				r._draw_strip(cv, "gl_s3loop_gd", r.frame_of(0.0), r._snap(f.pos), false, false)
	if o.hw.has("glc"):
		for ch in o.hw.glc:
			_draw_sunk(r, cv, ch)
	for it in r.items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("glrt"):
			if str(it.glrt) == "wake":
				_draw_wake(r, cv, it)
			elif str(it.glrt) == "trench":
				_draw_trench(r, cv, it)
			continue
		r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)


## 上层：链 + 钩头（在空中，盖在单位上面）、连携的几道链；旧做法（2）的整张贴图
static func over(r, o) -> void:
	var cv = o.cv
	var g = r.g
	if r.mode() == 2:
		for it in r.items:
			if str(it.ly) == "raw" and str(it.oid) == str(o.id):
				r._draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8)), it.gp, float(it.rot), float(it.sc))
		for f in o.fields:
			if f.get("pxp", false):
				r._draw_raw(cv, "gl_raw_s3loop", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(r._meta("gl_raw_s3loop").get("n", 1))), f.pos + Vector2(0, -40), 0.0, g.PX * 1.0)
	_draw_hooks(r, o, cv)
	for it in r.items:
		if str(it.ly) == "ov" and str(it.oid) == str(o.id) and str(it.get("glrt", "")) == "lchain":
			_draw_lchain(r, o, cv, it)


## 排序项：S3 龙卷远半圈 / 近半圈（状态件，按区域读）
static func sort_items(r, o, out: Array) -> void:
	var g = r.g
	for f in o.fields:
		if not f.get("pxp", false):
			continue
		var born: float = g.t - float(f.t)
		var dz: float = S3_R * 2.0 * SY
		if float(f.t) < 0.33:
			out.append({"k": "gl_s3open_bk", "t0": born, "gp": r._snap(f.pos), "flip": false, "sk": -dz})
			out.append({"k": "gl_s3open_up", "t0": born, "gp": r._snap(f.pos), "flip": false, "sk": dz})
		else:
			out.append({"k": "gl_s3loop_bk", "t0": 0.0, "gp": r._snap(f.pos), "flip": false, "loop": true, "sk": -dz})
			out.append({"k": "gl_s3loop_up", "t0": 0.0, "gp": r._snap(f.pos), "flip": false, "loop": true, "sk": dz})


static func draw_rt(r, ci, it: Dictionary) -> void:
	if str(it.glrt) == "part":
		_draw_part(r, ci, it)


# ---------------------------------------------------------------- 运行时线状件

## 两点间逐美术像素的格点（2 世界像素一格）
static func _line(a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	var n: int = int(ceilf(maxf(absf(b.x - a.x), absf(b.y - a.y)) / 2.0))
	var last := Vector2.INF
	for i in n + 1:
		var q: Vector2 = ((a + (b - a) * (float(i) / maxf(1.0, float(n)))) / 2.0).round() * 2.0
		if q != last:
			out.append(q)
			last = q
	return out


static func _hand(o) -> Vector2:
	if o.def.has("native_motion"):
		if _SegU == null:
			_SegU = load("res://scripts/characters/blocks/seg_ulpianus.gd")
		return _SegU._hw_hand(o)
	return o.pos + Vector2(33.0 * float(o.face), -33.0)


## 钩索（读玩法状态 o.hw.hooks，只读）：链 1 美术像素（重钩 2 格）、亮暗相间的链节；落地绷紧那一拍整条发白；掌握怒海期间链节点深渊紫。钩头逐格画（倒钩 + 杆）
static func _draw_hooks(r, o, cv) -> void:
	var g = r.g
	if not o.hw.has("hooks") or o.pos == Vector2.INF:
		return
	var s2: bool = o.skill_active_left(1) > 0.0
	for hk in o.hw.hooks:
		var b: Dictionary = hk.b
		var heavy: bool = str(b.get("src", "")) == "大洋裂断"
		var hand: Vector2 = _hand(o)
		var p: Vector2 = (hk.head as Vector2) + Vector2(0, -6)
		if o.def.has("native_motion") and str(hk.phase) == "fly":
			p = hand.lerp(hk.to, clampf(float(hk.t) / maxf(float(hk.dur), 0.001), 0.0, 1.0)) + Vector2(0, -6)
		var flash: bool = hk.has("_pxf") and int(floor(g.t * 15.0)) - int(floor(float(hk._pxf) * 15.0)) <= 0
		chain(r, cv, hand, p, heavy, flash, s2)
		if str(hk.phase) == "drag":
			for dg in hk.drag:
				if not dg.e.dead:
					chain(r, cv, p, dg.e.pos + Vector2(0, -float(dg.e.r) * 0.5), false, false, s2)
		var dirv: Vector2 = ((hk.to as Vector2) - (hk.from as Vector2)).normalized()
		head(r, cv, p, -dirv if str(hk.phase) == "drag" else dirv, heavy)


static func chain(r, cv, a: Vector2, b: Vector2, heavy: bool, flash: bool, s2: bool) -> void:
	var pts: Array = _line(a, b)
	var dv: Vector2 = (b - a).normalized()
	var nrm := Vector2(-dv.y, dv.x)
	var off: Vector2 = ((nrm * 2.0) / 2.0).round() * 2.0
	for i in pts.size():
		var q: Vector2 = pts[i]
		var c: Color = CH[4] if flash else (CH[3] if i % 3 == 0 else CH[2])
		if s2 and not flash and i % 6 == 3:
			c = ACC
		r._px(cv, q, c)
		if heavy:
			r._px(cv, q + off, CH[0] if not flash else CH[3])
	if flash and pts.size() > 0:
		r._glow(pts[pts.size() - 1], CH[4])


static func head(r, cv, p: Vector2, dir: Vector2, heavy: bool) -> void:
	var L: int = 6 if heavy else 4
	var bl: int = 4 if heavy else 3
	for s in L + 1:
		r._px(cv, p - dir * float(s) * 2.0, C[7] if s == 0 else C[6])
	for sg in [-1.0, 1.0]:
		var bd: Vector2 = (-dir).rotated(0.62 * sg)
		for s in range(1, bl + 1):
			r._px(cv, p + bd * float(s) * 2.0, C[5] if s < bl else C[4])
	r._glow(p, C[7])


## 拖痕：被拖的怪从起点到当前位置，地上一道 V 字水痕（暗湿芯 + 两侧白沫，越靠后越宽越稀）；到位后 0.45 秒按噪声散掉
static func _draw_wake(r, cv, it: Dictionary) -> void:
	var g = r.g
	var e: Dictionary = it.e
	var from: Vector2 = it.from
	var cur: Vector2 = e.pos if not e.get("dead", false) else it.get("last", from)
	it["last"] = cur
	if g.t < float(it.t0):
		return
	var L: float = from.distance_to(cur)
	if L < 4.0:
		return
	var d: Vector2 = (cur - from) / L
	var nrm := Vector2(-d.y, d.x * SY).normalized()
	var fade: float = clampf((g.t - float(it.t1)) / WAKE_TAIL, 0.0, 1.0)
	var sd: float = float(it.sd)
	var n: int = int(L / 2.0)
	for j in n:
		var back: float = float(j) * 2.0   # 离怪多远（世界像素）
		var q: Vector2 = cur - d * back + Vector2(0, 2)
		var w: float = minf(10.0, 2.0 + back / 5.0)
		var k: float = back / maxf(1.0, L)
		if _h(back * 0.37 + sd) > 0.25 + fade * 0.75:
			r._px(cv, q, C[1])
		for sg in [-1.0, 1.0]:
			if _h(back * 1.3 + sd + sg * 7.0) > 0.35 + 0.4 * k + fade * 0.65:
				r._px(cv, q + nrm * w * sg, C[7] if back < 8.0 and fade <= 0.0 else C[6] if k < 0.5 else C[5])


static func _draw_trench(r, cv, it: Dictionary) -> void:
	var g = r.g
	var u: float = g.t - float(it.t0)
	var gone: float = clampf((u - 0.45) / 0.55, 0.0, 1.0)
	var tier: int = int(it.tier)
	var a: Vector2 = it.a
	var d: Vector2 = it.d
	var nrm := Vector2(-d.y, d.x * SY).normalized()
	var w: float = 8.0 + 6.0 * (1.0 - pow(1.0 - clampf(u / 0.15, 0.0, 1.0), 3.0)) + 14.0 * clampf((u - 0.5) / 0.45, 0.0, 1.0)   # 两侧白沫往外推开；浪塌后继续外扩成细涟漪
	var s: float = 28.0
	while s < float(it.L) - 8.0:
		var base: Vector2 = a + d * s + Vector2(0, 2)
		if _h(s * 0.41) > 0.2 + 0.8 * gone:
			r._px(cv, base, C[0])
		for sg in [-1.0, 1.0]:
			var q: float = _h(s * 0.9 + sg * 5.0)
			if q > 0.3 + 0.7 * gone:
				var c: Color = C[5] if q > 0.6 else C[2]
				if tier >= 2 and _h(s * 1.7 + sg) > 0.9:
					c = ACC
				r._px(cv, base + nrm * sg * w, c)
			if tier >= 1 and _h(s * 1.3 + sg * 9.0) > 0.78 + 0.22 * gone:
				r._px(cv, base + nrm * sg * (w + 3.0), C[6])
		s += 2.0


## 沉底的锁链（怒海，读 o.hw.glc，只读）：地上一道暗链（暗 / 中相间）+ 零星白沫；到期前 0.4 秒按噪声散
static func _draw_sunk(r, cv, ch: Dictionary) -> void:
	var a: Vector2 = (ch.a as Vector2) + Vector2(0, 2)
	var c: Vector2 = (ch.c as Vector2) + Vector2(0, 2)
	var gone: float = 0.0
	if str(ch.phase) == "live":
		gone = clampf(1.0 - (float(ch.life) - float(ch.t)) / 0.4, 0.0, 1.0)
	else:
		gone = 0.6
	var pts: Array = _line(a, c)
	for i in pts.size():
		var hq: float = _h(float(i) * 0.53 + a.x * 0.01)
		if hq < gone:
			continue
		r._px(cv, pts[i], CH[1] if i % 3 == 0 else CH[0])
		if hq > 0.86:
			r._px(cv, pts[i] + Vector2(0, -2), C[6])


## 连携「聚拢」：甩钩 0.14 秒（链头从她手里飞向每只）→ 拖 0.36 秒（链连着怪）→ 落地后链残留 0.5 秒按噪声散
static func _draw_lchain(r, o, cv, it: Dictionary) -> void:
	var g = r.g
	var u: float = g.t - float(it.t0)
	var hand: Vector2 = o.pos + Vector2(0, -20)
	for e in it.es:
		if e.get("dead", false):
			continue
		var tgt: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		var tip: Vector2 = hand.lerp(tgt, clampf(u / 0.14, 0.0, 1.0))
		if u < 0.5:
			chain(r, cv, hand, tip, false, u >= 0.14 and u < 0.2, false)
			head(r, cv, tip, (tgt - hand).normalized() if u < 0.14 else (hand - tgt).normalized(), false)
		else:
			var gone: float = clampf((u - 0.5) / 0.5, 0.0, 1.0)
			var pts: Array = _line(hand, tgt)
			for i in pts.size():
				if _h(float(i) * 0.61 + float(e.get("id", 0))) > gone:
					r._px(cv, pts[i], CH[2] if i % 3 else CH[1])
