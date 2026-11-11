## 艾雅法拉（docs/259，照斯卡蒂 docs/246 的做法；11-05 用户「火山和熔岩的感觉要做出来，火球也是，参考 pixelfx 的做法」）
## 帧条件（tools/pxplane_bake_eyja.py，键前缀 ey_）：爆团 / 火柱 / 火山爆团 / 喷柱都用 pixelfx 库的粒子做法（火团冷却、火星、余烬、熔岩块），
## 火球 / 熔岩块用库里 fire/fireball（按 5 个平面角生成、另一半翻转、循环），熔岩池 / 熔池只画边 + 淡渐变 + 循环的熔岩泡（立起层）。
## 弹体、熔池、熔蚀裂纹、灼烧火苗直接读玩法状态（g.bullets 里本人的 fire 弹、o.hw 的 lobs / lobvol / erupts / pools / melt_list / burns、o.vg.bul），只读；
## 画面位置按帧走、取整到美术像素格（弹体快，按 15 fps 跳格会一卡一卡，同流明光弹）；帧条形状按 15 fps 节拍换。
## 原画面（MagmaProjectile 的弹体 / 落点 / 材质颗粒、hw_draw_*、o.fx 粒子、连携的岩块 / 冲击）接管时一律不画 / 不生成，玩法照旧。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const EY_C := [Color("#1a0705"), Color("#4a110a"), Color("#8f1d0d"), Color("#d2330f"), Color("#f6561a"), Color("#ff8a3d"), Color("#fff0e0"), Color("#ffaa45")]
const EY_BOOM_R := [26, 34, 44, 56]
const EY_S1_R := [40, 52, 66]
const EY_IG_R := [44, 56]
const EY_S3_R := [38, 46]
const EY_POOL_R := [25, 30]
const EY_LAVA_R := [30, 36]
const EY_SPL_R := [15, 22]
const EY_BURN_MAX := 16
const EY_MELT_MAX := 32
## 直线弹（普攻火球 / 熔岩弹 / 二重咏唱强化 / 点燃弹）的尾焰（11-06 用户「现在的普通攻击像是平移出去的火球，没有了之前的方向感」）：
## 帧条只有 5 个 45° 角、烟一律往上飘，看不出头尾；转平面前靠 proj_lavaball 按飞行角连续旋转的彗星形。
## 这里沿真实飞行反方向排一串由白热到暗红、由粗到细的像素团（帧条底下），头部一颗热芯进发光层；只画，不抽随机数（抖动按 g.t 与 ph）。
## 开关 fx/eyja_ball_tail（缺省 1，0 = 只有帧条）
const EY_TAIL := {"fire": 1.0, "lava": 1.1, "pow": 1.3, "ign": 1.45}
const EY_TAIL_C := [6, 7, 5, 5, 4, 4, 3, 3, 2, 2, 1]   # 从头到尾的 EY_C 色阶


static func _se(pv: P):
	if pv._sey == null:
		pv._sey = load("res://scripts/characters/blocks/seg_eyjafjalla.gd")   # 运行时取（避免和积木链循环 preload）
	return pv._sey


static func _ey_push(pv: P, o, k: String, at: Vector2, ly: String, extra := {}) -> void:
	var g = pv.g
	var it := {"k": "ey_" + k, "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	it.merge(extra, true)
	pv._push(it)


static func _ey_rawi(pv: P, o, k: String, at: Vector2, rot: float, sc: float) -> void:
	var g = pv.g
	pv._push({"k": "ey_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 同一名干员正在画的某类立起件数（同屏封顶：后期弹多时爆团不叠成一片）
static func _ey_cnt(pv: P, o, pre: String) -> int:
	var n := 0
	for it in pv.items:
		if str(it.oid) == str(o.id) and str(it.ly) == "up" and str(it.k).begins_with(pre):
			n += 1
	return n


static func _ev_ey(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG ey %s %s %.3f" % [kind, str(d.get("k", d.get("i", ""))), g.t])
	var px: float = g.PX
	match kind:
		"ey_boom":   # 熔岩弹爆炸：普攻（atk）/ 三重咏唱每落一发（tri）/ 二重咏唱强化弹（s1）/ 点燃弹（s2）
			var at: Vector2 = d.at
			var r: float = float(d.r)
			match str(d.get("k", "atk")):
				"s2":
					var tt: int = maxi(t, 1)
					if raw:
						_ey_rawi(pv, o, "raw_ignite", at, 0.0, px * r * 0.5 / 47.0)
						return
					var b2: int = pv._bucket(r * 0.5, EY_IG_R)
					_ey_push(pv, o, "ignite_r%d_e%d_up" % [b2, tt], at, "up")
					_ey_push(pv, o, "ignite_r%d_e%d_gd" % [b2, tt], at, "gd")
					if pv.mode() == 1:
						R._grains(o, at + Vector2(0, -50), at.y, "streak", 5 + 3 * tt, {"tier": tt})
					R._light(o, at + Vector2(0, -40), r * 1.8, 0.65, 0.15, p.light)
				"s1":
					if raw:
						_ey_rawi(pv, o, "raw_s1boom", at, 0.0, px * r * 0.5 / 44.0)
						return
					var b1: int = pv._bucket(r * 0.5, EY_S1_R)
					_ey_push(pv, o, "s1boom_r%d_e%d_up" % [b1, t], at, "up")
					_ey_push(pv, o, "s1boom_r%d_e%d_gd" % [b1, t], at, "gd")
					if pv.mode() == 1:
						R._grains(o, at + Vector2(0, -30), at.y, "ember", 4 + 2 * t, {"tier": t})
					R._light(o, at + Vector2(0, -24), 160.0, 0.7, 0.15, p.light)   # docs/270 补齐（爆发类下限）：每发爆点一盏 160 / 0.7
					pv._push({"ert": "core", "at": at + Vector2(0, -float(b1) * 0.45 * g.PX), "rr": 5.0 + 0.5 * t, "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": at.y + 1.0, "oid": str(o.id), "k": ""})   # 爆心进 emit
				_:
					R._light(o, at + Vector2(0, -20), r * 1.3, 0.4, 0.12, p.light)
					if _ey_cnt(pv, o, "ey_boom") >= 6:
						return
					if raw:
						_ey_rawi(pv, o, "raw_boom_e%d" % t, at, 0.0, px * r * 0.5 / 30.0)
						return
					var b0: int = pv._bucket(r * 0.5, EY_BOOM_R)
					_ey_push(pv, o, "boom_r%d_e%d_up" % [b0, t], at, "up")
					_ey_push(pv, o, "boom_r%d_e%d_gd" % [b0, t], at, "gd")
					if pv.mode() == 1:
						R._grains(o, at + Vector2(0, -20), at.y, "ember", 2 + t, {"tier": t})
		"ey_splash", "ey_xhit":   # 抛射熔岩落地（火星迸溅 / 星火燎原 / 熔岩天降）、后期额外弹命中：小一号
			var at2: Vector2 = d.at
			var r2: float = float(d.get("r", 30.0))
			if kind == "ey_xhit" and pv._lm_beat_n(o, "eyx") >= 3:
				return
			if _ey_cnt(pv, o, "ey_splash") >= 5:
				return
			if raw:
				_ey_rawi(pv, o, "raw_splash", at2, 0.0, px * r2 * 0.5 / 18.0)
				return
			var bs: int = pv._bucket(r2 * 0.5, EY_SPL_R)
			_ey_push(pv, o, "splash_r%d_up" % bs, at2, "up")
			if kind == "ey_splash":
				_ey_push(pv, o, "splash_r%d_gd" % bs, at2, "gd")
				if pv.mode() == 1:
					R._grains(o, at2 + Vector2(0, -10), at2.y, "rock", 2, {"tier": t})
			R._light(o, at2 + Vector2(0, -10), r2 * 1.6, 0.4, 0.1, p.light)
		"ey_s3":   # 火山落点：实心大爆团（火团 + 往上冲的火 + 熔岩块 + 花瓣状暗红碎片 + 火星线）
			var at3: Vector2 = d.at
			var r3: float = float(d.r)
			R._light(o, at3 + Vector2(0, -30), r3 * 2.0, 0.7, 0.15, p.light)
			if raw:
				_ey_rawi(pv, o, "raw_s3boom", at3, 0.0, px * r3 * 0.5 / 38.0)
				return
			var b3: int = pv._bucket(r3 * 0.5, EY_S3_R)
			_ey_push(pv, o, "s3boom_r%d_up" % b3, at3, "up")
			_ey_push(pv, o, "s3boom_r%d_gd" % b3, at3, "gd")
			if pv.mode() == 1:
				R._grains(o, at3 + Vector2(0, -40), at3.y, "streak", 6, {"tier": 2})
				R._grains(o, at3 + Vector2(0, -20), at3.y, "rock", 3, {"tier": 2})
		"ey_fire":   # 出手：杖头两拍火光
			if raw:
				return
			pv._push({"ert": "muz", "at": pv._snap(d.at), "big": d.get("big", false), "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": o.pos.y + 1.0, "oid": str(o.id), "k": "", "fopo": o, "foff": (d.at as Vector2) - o.pos})
			R._light(o, d.at, 60.0, 0.35, 0.08, p.light)
		"ey_chain":   # 「连锁」弹射：一道 1 美术像素的火线（3 拍）
			if pv._lm_beat_n(o, "eych") >= 3 or raw:
				return
			pv._push({"ert": "chain", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
		"ey_link":   # 连携 v2「熔岩」：杖头抛出一块大熔岩块（库里火球 + 岩壳），T 秒高抛砸进区域；地上影子跟着
			var la: Vector2 = d.a
			var lc: Vector2 = d.c
			var T: float = float(d.T)
			pv._push({"ert": "lrock", "a": la, "c": lc, "T": T, "t0": g.t, "life": T, "ly": "up", "gy": lc.y + 2.0, "oid": str(o.id), "k": "", "raw": raw})
			pv._push({"ert": "lshadow", "a": Vector2(la.x, (d.get("foot", la) as Vector2).y), "c": lc, "T": T, "t0": g.t, "life": T, "ly": "gd", "oid": str(o.id), "k": ""})
			R._light(o, la, 120.0, 0.5, 0.12, p.light)
		"ey_link_hit", "ey_combo":   # 连携熔岩块砸地 / 旧连携技「放大熔岩弹」落点：火山爆团 + 一摊熔岩（只画边 + 熔岩泡）
			var c: Vector2 = d.get("c", d.get("at", o.pos))
			var lr: float = float(d.get("r", 105.0))
			var dur: float = 2.0 if kind == "ey_combo" else 0.9
			R._light(o, c + Vector2(0, -30), maxf(240.0, lr * 2.0), 0.7, 0.15, p.light)
			if raw:
				_ey_rawi(pv, o, "raw_s3boom", c, 0.0, px * lr * 0.5 / 38.0)
				return
			_ey_push(pv, o, "s3boom_r46_up", c, "up")
			_ey_push(pv, o, "s3boom_r46_gd", c, "gd")
			_ey_push(pv, o, "lava_r36_gd", c, "gd", {"loop": true, "life": dur})
			_ey_push(pv, o, "lavaup_l36_up", c, "up", {"loop": true, "life": dur})
			if pv.mode() == 1:
				R._grains(o, c + Vector2(0, -40), c.y, "streak", 10, {"tier": 2})
				R._grains(o, c + Vector2(0, -20), c.y, "rock", 6, {"tier": 2})
		"ey_link_burn":   # 连携两跳点燃：被烧的那几只身上冒火星
			if pv.mode() != 1:
				return
			var n := 0
			for e in d.get("es", []):
				if e.dead or n >= 6:
					continue
				n += 1
				R._grains(o, e.pos + Vector2(0, -float(e.r) * 0.6), float(e.pos.y), "ember", 2, {"tier": 1})
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 0:   # 二重咏唱起手：火缕绕身旋上杖头
				if raw:
					_ey_rawi(pv, o, "raw_s1cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(pv, o, "s1cast_e%d_up" % t, o.pos, "up", {"fopo": o, "foff": Vector2.ZERO})
				if t >= 2:
					_ey_push(pv, o, "s1cast_e2_gd", o.pos, "gd", {"fopo": o, "foff": Vector2.ZERO})
				# docs/270 补齐：起手本身也按爆发档——杖头一盏 160 / 0.7、杖头热芯进发光层、迸几颗火星（强化弹要等下一次普攻约 1.2 秒后才落地）
				R._light(o, o.pos + Vector2(0, -100), 160.0, 0.7, 0.15, p.light)
				pv._push({"ert": "core", "at": o.pos + Vector2(0, -110), "rr": 6.0 + 0.5 * t, "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": o.pos.y + 1.0, "oid": str(o.id), "k": "", "fop": o, "foff": Vector2(0, -110)})
				if pv.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -110), o.pos.y, "ember", 6 + t, {"tier": t})
			elif i == 2:   # 火山起手：身后熔岩喷柱 + 脚下裂缝圈
				var fl: bool = float(o.face) < 0.0
				if raw:
					_ey_rawi(pv, o, "raw_s3cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(pv, o, "s3cast_up", o.pos, "up", {"flip": fl, "sk": -6.0, "fopo": o, "foff": Vector2.ZERO})
				_ey_push(pv, o, "s3cast_gd", o.pos, "gd", {"flip": fl, "fopo": o, "foff": Vector2.ZERO})
				R._light(o, o.pos + Vector2(0, -60), 170.0, 0.7, 0.15, p.light)
				if pv.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "rock", 5, {"tier": 2})


## 地面层：一次性贴地件、循环熔岩（连携 / 旧连携技）、熔岩池 / 熔池（读 o.hw.pools）、熔蚀裂纹、抛射物影子、火山期间脚下热圈
static func _ey_floor(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	var px: float = g.PX
	if not o.hw.is_empty() and o.hw.has("pulse") and not (o.hw.pulse as Dictionary).is_empty():
		pv._draw_strip(cv, "ey_aura_gd", pv.frame_of(0.0), pv._snap(o.pos + Vector2(0, 2)), false, false)
	for l in o.hw.get("pools", []):
		var key: String = _ey_pool_key(pv, l, "gd")
		if key == "":
			continue
		pv._draw_strip(cv, key, pv.frame_of(0.0) + int(l.get("pat", 0)) % 7, pv._snap(l.pos), false, false, Color(1, 1, 1, _ey_pool_a(pv, l)))
	for it in pv.items_for(id):
		if str(it.ly) != "gd":
			continue
		if it.has("ert"):
			_ey_draw_rt(pv, cv, it)
		elif it.get("loop", false):
			pv._draw_strip(cv, str(it.k), pv.frame_of(0.0), it.gp, false, false, Color(1, 1, 1, _ey_loop_a(pv, it)))
		else:
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), it.gp, it.flip, true)
	# 熔蚀（精一普攻）：被熔岩弹命中的敌人脚下三小段暗红裂纹（状态提示）
	var nm := 0
	for m in o.hw.get("melt_list", []):
		var e: Dictionary = m.e
		var left: float = float(m.until) - g.t
		if e.dead or left <= 0.0 or nm >= EY_MELT_MAX:
			continue
		nm += 1
		var base: Vector2 = pv._snap(e.pos + Vector2(0, 2))
		var rr: float = clampf(float(e.r) * 0.5 + 4.0, 9.0, 16.0)   # docs/310 §4.2：裂纹放到身体外沿（原 5–12 被敌人本体挡住）、加粗一格
		for q in 3:
			var a0: float = q * TAU / 3.0 + float(e.id) * 0.7
			for s in 7:
				if left < 0.3 and s >= 2:
					continue
				var an: float = a0 + s * 0.1
				var pq: Vector2 = base + Vector2(cos(an) * rr, sin(an) * rr * 0.72) * px
				pv._px(cv, pq, EY_C[4] if (s + q) % 2 == 0 else EY_C[3])
				pv._px(cv, base + Vector2(cos(an) * (rr + 1.0), sin(an) * (rr + 1.0) * 0.72) * px, EY_C[1])
	# 抛射物（熔岩块 / 三重咏唱低抛弹）的地面影子：暗色小椭圆，越高越小
	for l in o.hw.get("lobs", []):
		var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
		_ey_shadow(pv, cv, (l.from as Vector2).lerp(l.to, k) + Vector2(0, (1.0 - k) * 6.0), 2.0 + 2.0 * float(l.sz), k)
	for v in o.hw.get("lobvol", []):
		for s in v.shots:
			if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
				continue
			var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
			_ey_shadow(pv, cv, (s.from as Vector2).lerp(s.to, k2) + Vector2(0, (1.0 - k2) * 40.0), 3.0, k2)


static func _ey_shadow(pv: P, cv, gp: Vector2, r: float, k: float) -> void:
	var g = pv.g
	var px: float = g.PX
	var c := Color(0.05, 0.02, 0.02, 0.45)
	var rr: int = int(round(r * (0.6 + 0.4 * k)))
	var base: Vector2 = pv._snap(gp)
	for y in range(-1, 2):
		for x in range(-rr, rr + 1):
			if absi(y) == 1 and absi(x) >= rr:
				continue
			cv.draw_rect(Rect2(base + Vector2(x, y) * px, Vector2(px, px)), c)


## 熔岩池 / 熔池帧条键：S3 熔岩（look lava）或三重咏唱熔池（look pool / weighted）
static func _ey_pool_key(pv: P, l: Dictionary, ly: String) -> String:
	var b: Dictionary = l.b
	var look: String = str(b.get("look", ""))
	if look == "lava":
		return ("ey_lava_r%d_gd" if ly == "gd" else "ey_lavaup_l%d_up") % pv._bucket(float(l.r) * 0.5, EY_LAVA_R)
	if look == "pool" or b.get("weighted", false):
		return ("ey_pool_r%d_gd" if ly == "gd" else "ey_lavaup_p%d_up") % pv._bucket(float(l.r) * 0.5, EY_POOL_R)
	return ""


static func _ey_pool_a(pv: P, l: Dictionary) -> float:
	return clampf((float(l.dur) - float(l.t)) / 0.15, 0.0, 1.0) * clampf(float(l.t) / 0.3, 0.0, 1.0)


static func _ey_loop_a(pv: P, it: Dictionary) -> float:
	var g = pv.g
	return clampf((g.t - float(it.t0)) / 0.12, 0.0, 1.0) * clampf((float(it.t0) + float(it.life) - g.t) / 0.3, 0.0, 1.0)


## 立起层的状态件：弹体（火球 / 熔岩块）、熔岩泡（循环）、灼烧火苗
static func _ey_sort_items(pv: P, o, out: Array) -> void:
	var g = pv.g
	var S = _se(pv)
	var oid: String = str(o.id)
	for bl in g.bullets:   # 本人的法术弹（普攻 / 二重咏唱强化 / 点燃弹）
		if bl.life <= 0.0 or str(bl.get("op", "")) != oid or str(bl.kind) != "fire" or not bl.has("hw_b"):
			continue
		var lk: Dictionary = bl.hw_b.get("look", {})
		var st: String = "ign" if lk.has("big_tex") else ("pow" if bl.get("pxs", false) else ("fire" if bl.get("hw_fireball", false) else "lava"))
		var lv: Array = _ey_lift(pv, bl)
		out.append({"ert": "ball", "st": st, "pos": lv[0], "dir": lv[1], "gy": (bl.pos as Vector2).y + 40.0, "ph": int(absf(bl.pos.x)) % 7})
	if not o.hw.is_empty():
		var rot_all: bool = Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0
		for l in o.hw.get("lobs", []):   # 火星迸溅 / 星火燎原 / 熔岩天降的熔岩块
			if float(l.t) >= float(l.dur):
				continue
			var lp: Vector2 = S._hw_lob_pos(l)
			var lp0: Vector2 = S._hw_lob_pos_at(l, maxf(0.0, float(l.t) - 0.03))
			var ld: Vector2 = lp - lp0
			if ld.length_squared() <= 0.01 and rot_all:   # 刚抛出那一帧往回取不到：改往前取（原来退成朝下，火块竖着闪一帧）
				ld = S._hw_lob_pos_at(l, float(l.t) + 0.03) - lp
			var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
			var big: bool = float(l.sz) >= 1.1 or str(l.src) == "熔岩天降"
			out.append({"ert": "ball", "st": "rock" if big else "chip", "pos": lp, "dir": ld if ld.length_squared() > 0.01 else Vector2.DOWN, "gy": (l.from as Vector2).lerp(l.to, k).y + 2.0, "ph": int(absf(l.to.x)) % 7})
		for v in o.hw.get("lobvol", []):   # 三重咏唱低抛弹
			var apex: float = float(v.vol.b.lob.get("apex", 20.0))
			for s in v.shots:
				if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
					continue
				var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
				var sp: Vector2 = _ey_arc(s.from, s.to, k2, apex) + Vector2(0, -8)
				var sp0: Vector2 = _ey_arc(s.from, s.to, maxf(0.0, k2 - 0.05), apex) + Vector2(0, -8)
				var sd: Vector2 = sp - sp0
				if sd.length_squared() <= 0.01 and rot_all:   # 出手那一帧：往前取切线（原来退成朝右）
					sd = _ey_arc(s.from, s.to, minf(1.0, k2 + 0.05), apex) + Vector2(0, -8) - sp
				out.append({"ert": "ball", "st": "lava", "pos": sp, "dir": sd if sd.length_squared() > 0.01 else Vector2.RIGHT, "gy": (s.from as Vector2).lerp(s.to, k2).y + 30.0, "ph": int(absf(s.to.x)) % 7,
					"len": Bal.v("fx/eyja_lob_len", 0.45)})
		for ev in o.hw.get("erupts", []):   # 火山弹
			if not ev.has("shot") or float(ev.t) <= 0.0:
				continue
			var shot: Dictionary = ev.shot
			var k3: float = clampf(1.0 - float(ev.t) / float(shot.dur), 0.0, 1.0)
			var ap: float = float(shot.get("apex", 24.0))
			var ep: Vector2 = _ey_arc(shot.from, ev.pos, k3, ap)
			var ep0: Vector2 = _ey_arc(shot.from, ev.pos, maxf(0.0, k3 - 0.05), ap)
			var ed: Vector2 = ep - ep0
			if ed.length_squared() <= 0.01 and rot_all:   # 刚射出那一帧：往前取切线（原来退成朝下）
				ed = _ey_arc(shot.from, ev.pos, minf(1.0, k3 + 0.05), ap) - ep
			out.append({"ert": "ball", "st": "rock", "pos": ep, "dir": ed if ed.length_squared() > 0.01 else Vector2.DOWN, "gy": (shot.from as Vector2).lerp(ev.pos, k3).y + 54.0 * (1.0 - k3), "ph": int(absf(ev.pos.x)) % 7})
		for l in o.hw.get("pools", []):   # 熔岩泡（循环，立起）
			var key: String = _ey_pool_key(pv, l, "up")
			if key != "":
				out.append({"loopk": key, "gp": pv._snap(l.pos), "gy": (l.pos as Vector2).y + 1.0, "mod": Color(1, 1, 1, _ey_pool_a(pv, l))})
		var nb := 0
		for bu in o.hw.get("burns", []):   # 灼烧：敌人身上两小簇火苗（状态提示）
			if nb >= EY_BURN_MAX:
				break
			if float(bu.t) <= 0.0 or bu.e.dead:
				continue
			nb += 1
			out.append({"ert": "burn", "e": bu.e, "gy": float(bu.e.pos.y) + 1.0})
	if not o.vg.is_empty():   # 后期额外弹：小熔岩块，同时最多画最新 6 颗
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"ert": "ball", "st": "chip", "pos": (xb.p as Vector2) + Vector2(0, -18.0), "dir": xb.v, "gy": (xb.p as Vector2).y + 1.0, "ph": i % 7})


## 直线弹的画面抬升（11-06 用户「感觉是不是还是斜着飞过去的」）：弹从法杖尖（脚下往上 40）出手、瞄的是敌人脚下，
## 判定点一路往下斜着走；眼睛看的是敌人身子（脚下往上一截），于是火球总像斜着往地上扎。画面上把弹按飞行进度逐渐抬到敌人身子的高度
## （fx/eyja_ball_lift 像素，0 = 不抬），朝向 / 尾焰顺着抬升后的画面路径；判定、爆点位置不动。
static func _ey_lift(pv: P, bl: Dictionary) -> Array:
	var p: Vector2 = bl.pos
	var v: Vector2 = bl.vel
	var lift: float = Bal.v("fx/eyja_ball_lift", 20.0)
	if lift <= 0.0 or not bl.has("vt") or not bl.has("vf"):
		return [p, v]
	var f: Vector2 = bl.vf
	var t: Vector2 = bl.vt
	var seg: Vector2 = t - f
	var L2: float = seg.length_squared()
	if L2 < 1.0:
		return [p, v]
	var kr: float = (p - f).dot(seg) / L2
	var k: float = clampf(kr, 0.0, 1.0)
	if Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0:
		# 朝向 = 画面上这一帧实际的移动方向（11-07 用户「不能任意方向吗」）：画面位置 p - (0, lift·k)，k 在 0–1 之间随 p 线性变，
		# 对时间求导 = v - (0, lift)·(v·seg)/|seg|²；飞过瞄准点后 k 停在 1，画面速度就是 v
		var sv: Vector2 = v - Vector2(0, lift) * (v.dot(seg) / L2) if kr > 0.0 and kr < 1.0 else v
		return [p + Vector2(0, -lift * k), sv]
	var vd: Vector2 = (t - Vector2(0, lift)) - f   # 画面路径：出手点 → 敌人身子
	return [p + Vector2(0, -lift * k), vd.normalized() * v.length() if vd.length_squared() > 0.01 else v]


## MagmaProjectile.position_at 的同一条弧（纯函数抄一份，只读）
static func _ey_arc(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	return from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k) * (1.18 - 0.36 * k))


## 运行时件：ball 弹体（帧条按方向挑）/ muz 出手火光 / chain 连锁火线 / lrock 连携熔岩块 / lshadow 它的影子 / burn 灼烧火苗
static func _ey_draw_rt(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	match str(it.ert):
		"ball":
			_ey_ball(pv, ci, str(it.st), it.pos, it.dir, int(it.get("ph", 0)), float(it.get("len", 1.0)))
		"core":   # 爆心发光点团（docs/270 补齐）：不画色块，只往发光层送一团热芯点，4 拍里由大到小
			var fc: int = pv.frame_of(float(it.t0))
			if fc < 0 or fc > 3:
				return
			var rr: int = int(round(float(it.rr) * [1.0, 0.8, 0.55, 0.3][fc]))
			var cc: Vector2 = pv._snap(it.at)
			for yy in range(-rr, rr + 1):
				for xx in range(-rr, rr + 1):
					if xx * xx + yy * yy <= rr * rr:
						pv._glow(cc + Vector2(xx, yy) * px, EY_C[7] if xx * xx + yy * yy > rr * rr / 3 else EY_C[6])
		"muz":
			var f: int = pv.frame_of(float(it.t0))
			if f < 0 or f > 1:
				return
			var c0: Vector2 = it.at
			var m: int = 3 if it.get("big", false) else 2
			pv._px(ci, c0, EY_C[6] if f == 0 else EY_C[7])
			for dv in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				for s in range(1, m + (1 if f == 0 else 0)):
					pv._px(ci, c0 + dv * float(s) * px, EY_C[7] if s == 1 else EY_C[5])
			if f == 0:
				pv._glow(c0, EY_C[7])
		"chain":
			var f2: int = pv.frame_of(float(it.t0))
			if f2 < 0 or f2 > 2:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f2 == 2 and u < 0.5:
					continue
				pv._px(ci, a.lerp(b, u), EY_C[7] if f2 == 0 else EY_C[5])
				if f2 == 0 and i % 3 == 0:
					pv._glow(a.lerp(b, u), EY_C[7])
		"lrock":
			var u2: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			var pos: Vector2 = _ey_lrock_pos(pv, it, u2)
			var pos0: Vector2 = _ey_lrock_pos(pv, it, maxf(0.0, u2 - 0.05))
			if it.get("raw", false):
				pv._draw_raw(ci, "ey_ball_boulder_d0", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), 18), pos, (pos - pos0).angle(), g.PX * 1.3)
			else:
				_ey_ball(pv, ci, "boulder", pos, pos - pos0 if pos.distance_squared_to(pos0) > 0.01 else Vector2.DOWN, 0)
		"lshadow":
			var u3: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			_ey_shadow(pv, ci, (it.a as Vector2).lerp(it.c, u3) + Vector2(0, 10), 6.0 + 8.0 * u3, u3)
		"burn":
			var e: Dictionary = it.e
			if e.dead:
				return
			var beat: int = int(floor(g.t * 15.0))
			var base: Vector2 = pv._snap(e.pos + Vector2(0, -float(e.r) * 0.55))
			var off: int = maxi(2, int(float(e.r) * 0.15))
			for j in 2:
				var x: int = -off if j == 0 else off
				var h: int = 2 + int(_hn(int(e.id) * 3 + j + beat) * 3.0)
				for s in h:
					pv._px(ci, base + Vector2(x, -s) * px, EY_C[5] if s == 0 else (EY_C[4] if s < h - 1 else EY_C[3]))
				if j == 0:
					pv._glow(base + Vector2(x, 0) * px, EY_C[5])


static func _hn(i: int) -> float:
	var x: int = (i * 1103515245 + 12345) & 0x7fffffff
	return float(x % 1000) / 1000.0


static func _ey_lrock_pos(pv: P, it: Dictionary, u: float) -> Vector2:
	var gp: Vector2 = (it.a as Vector2).lerp(it.c, u)
	return gp + Vector2(0, -140.0 * sin(PI * u))


## 一颗弹体：帧条 ey_ball_<样式>_d<方向>（按飞行方向挑最近的平面角 + 水平翻转），循环；原点 = 弹头，位置每帧走、取整到美术像素格
## ln < 1：沿飞行方向把弹身压短（弹头不动）、不加尾焰——精二三重咏唱 3 发低抛弹间隔 0.12 秒、走几乎同一条弧，
## 帧条弹身约 45 美术像素长，三发首尾相接连成一条「火绳」（11-06 用户「精二像条火绳」）；开关 fx/eyja_lob_len（1 = 原样）
## 朝向统一（11-07 用户「艾雅法拉这个火焰还是歪着过去的，不能任意方向吗」）：所有弹体样式（含火星迸溅 / 火山弹的 chip / rock / boulder，
## 原来不转、直接贴 5 个角里最近的一张，抛物线刚升起时就落到 45° 那张）一律「最近角 + 转掉剩余偏差」，朝向 = 调用方给的画面移动方向
## （直线弹 _ey_lift 的画面速度、抛射弹轨迹切线）。开关 fx/eyja_ball_rot_all（缺省 1；0 = 只有带尾焰的四种转）。帧条像素按最近邻转，不另烤方向
static func _ey_ball(pv: P, ci, st: String, pos: Vector2, dir: Vector2, ph: int, ln := 1.0) -> void:
	var has_dir: bool = dir.length_squared() > 0.0001
	var dk: Array = pv.pick_dir(dir.angle() if has_dir else 0.0)
	var tail: bool = EY_TAIL.has(st) and has_dir and Bal.v("fx/eyja_ball_tail", 1.0) > 0.0
	if has_dir and (tail or Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0):
		if tail and ln >= 1.0:
			_ey_tail(pv, ci, pos, dir.normalized(), float(EY_TAIL[st]), ph)
		pv._ey_strip_rot(ci, "ey_ball_%s_d%d" % [st, dk[0]], pv.frame_of(0.0) + ph, pv._snap(pos), dk[1], dir.angle(), float(dk[0]), ln)
	else:
		pv._draw_strip(ci, "ey_ball_%s_d%d" % [st, dk[0]], pv.frame_of(0.0) + ph, pv._snap(pos), dk[1], false)
	if has_dir and _ball_dbg(pv):
		_ey_ball_dbg(pv, ci, pos, dir)


## 局部坐标里沿角 a 方向缩放 ln、垂直方向不变：R(a) · diag(ln, 1) · R(-a)
static func _ey_squash(a: float, ln: float) -> Transform2D:
	var c := cos(a)
	var si := sin(a)
	var off := c * si * (ln - 1.0)
	return Transform2D(Vector2(c * c * ln + si * si, off), Vector2(off, si * si * ln + c * c), Vector2.ZERO)


static func _ball_dbg(pv: P) -> bool:
	if pv._bdbg < 0:
		pv._bdbg = 1 if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--balldbg") else 0
	return pv._bdbg == 1


static func _ey_ball_dbg(pv: P, ci, pos: Vector2, dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	ci.draw_line(pos - d * 80.0, pos + d * 40.0, Color(0.2, 0.95, 1.0, 0.95), 1.0)
	var fr: int = Engine.get_process_frames()
	pv._bdbg_pts.append([fr, pos])
	while not pv._bdbg_pts.is_empty() and fr - int(pv._bdbg_pts[0][0]) > 10:
		pv._bdbg_pts.pop_front()
	for q in pv._bdbg_pts:
		ci.draw_rect(Rect2((q[1] as Vector2) - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)


static func _ey_tail(pv: P, ci, pos: Vector2, d: Vector2, k: float, ph: int) -> void:
	var g = pv.g
	var px: float = g.PX
	var nrm: Vector2 = d.orthogonal()
	var n: int = int(round(9.0 * k))
	var flick: int = int(floor(g.t * 15.0)) + ph
	for i in n:
		var u: float = float(i) / float(maxi(1, n - 1))   # 0 头 → 1 尾
		var back: float = (3.0 + float(i) * 2.6) * px * 0.5 * (1.0 + 0.5 * (k - 1.0))
		var wob: float = sin(float(flick + i * 3) * 1.7) * u * 2.2 * px * 0.5
		var c: Vector2 = pv._snap(pos - d * back + nrm * wob)
		var r: int = 2 if u < 0.25 else (1 if u < 0.7 else 0)   # 半宽（美术像素）
		if k >= 1.3 and u < 0.45:
			r += 1
		var ci_k: int = EY_TAIL_C[mini(EY_TAIL_C.size() - 1, int(u * float(EY_TAIL_C.size() - 1) + 0.5))]
		var col: Color = EY_C[ci_k]
		col.a = 1.0 - 0.55 * u
		for yy in range(-r, r + 1):
			for xx in range(-r, r + 1):
				if xx * xx + yy * yy > r * r + (1 if r > 0 else 0):
					continue
				if r >= 2 and (xx + yy + flick + i) % 5 == 0:
					continue   # 边上缺几格，不成实心胶囊
				ci.draw_rect(Rect2(c + Vector2(xx, yy) * px, Vector2(px, px)), col)
		# 尾段偶尔甩出一颗火星（离轴）
		if u > 0.45 and (flick + i) % 4 == 0:
			var sp: Vector2 = pv._snap(c + nrm * (3.0 if (flick + i) % 8 == 0 else -3.0) * px)
			ci.draw_rect(Rect2(sp, Vector2(px, px)), Color(EY_C[5], 0.8 - 0.5 * u))
	pv._glow(pv._snap(pos - d * 2.0 * px), EY_C[6])


## 旧做法（2）：同一形状光晕烤进颜色、小数缩放、旋转，盖在所有单位上；弹体用 0° 帧条按飞行方向旋转 1.3 倍贴
static func _ey_draw_raw(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	var lf: int = int(g.t * rf)
	for it in pv.items_for(id):
		if str(it.ly) != "raw":
			continue
		pv._draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	for l in o.hw.get("pools", []):
		if _ey_pool_key(pv, l, "gd") != "":
			pv._draw_raw(cv, "ey_raw_lava", posmod(lf, 18), l.pos, 0.0, g.PX * float(l.r) * 0.5 / 30.0)
	var tmp: Array = []
	_ey_sort_items(pv, o, tmp)
	for it in tmp:
		if str(it.get("ert", "")) == "ball":
			pv._draw_raw(cv, "ey_ball_%s_d0" % str(it.st), posmod(lf, 18), it.pos, (it.dir as Vector2).angle(), g.PX * 1.3)
		elif str(it.get("ert", "")) == "burn":
			_ey_draw_rt(pv, cv, it)
	for it in pv.items_for(id):
		if str(it.get("ert", "")) == "lrock" and it.get("raw", false):
			_ey_draw_rt(pv, cv, it)
