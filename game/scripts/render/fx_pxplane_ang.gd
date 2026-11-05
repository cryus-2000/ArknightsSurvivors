## 安洁莉娜转平面（docs/267，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第四批五人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_angelina.py 烤（图形 tools/pxplane_ang_art.py），键前缀 an_；弹尾、弹药珠、连携碎片尾迹、透镜线在这里逐格画
## （算法同 pxplane_ang_art.py 的 trail_px() / pips_px() / link_trail()，改一边要改另一边）。
## 招牌（每招一个意象）：普攻 = 黑紫重力弹 + 落点内爆（星芒 + 三角碎片被吸进来 + 暗凹）；精一加收紧断弧（重力停顿）；精二加失重井（黑紫旋臂井）。
## S1 = 三根细长光刺从上往下钉进落点；S2 = 缠绕细绸带绕她旋进、收到环带上一点（常驻环带带流动光点）；
## S3 = 头顶重力核心（实心黑紫核 + 两道斜转光环）+ 场内空间扭曲波纹往里收 + 少数几块大碎石绕场心缓慢转、托起（同屏 ≤ 4）；连携 = 三枚大碎片绕圈收拢。
## 悬浮的敌人：影子随高度缩小变淡 + 悬停时上下浮动 1 美术像素（world.gd 读 air_look，只画；11-05 第二轮去掉脚下竖线）。
## 挂在人身上的件（杖头星芒、重力核心）带 fo 跟她走；跟场的件（环带、场边、绸带）跟着场心走；落点、井、碎石留在原地。只画，不碰玩法与玩法随机数。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/282 §2）
const Pxp = preload("res://scripts/render/fx_pxplane.gd")

const V := [Color("#140c24"), Color("#312f5c"), Color("#5c4a8e"), Color("#8765c0"), Color("#b280f2"), Color("#cdacf7"), Color("#e8d9fb"), Color("#ffffff")]
const Z := [1.0, 1.15, 1.3]
const RIB_ROT := [0, 90, 180, 270]
const MUZZLE := Vector2(34, -80)   # 同 angelina.json blocks.attack.muzzle（脚底为原点、朝右）
const ARC_H := 26.0                # 同 data_operator._draw_shots 的弧高
const LAND_CAP := 3                # 每拍至多几处落点画面
const LINK_T := 0.45               # 同 skill_link l_angelina 的 T2
const CORE_Y := -112.0             # 重力核心在她脚底上方（头顶）

var r      # fx_pxplane 实例
var g
var _beat := {}
var _air := {}          # e.id → 安洁莉娜的悬浮表项（每帧重建）
var _air_frame := -1
var _rib_n := {}        # 每人第几次绸带（汇点方位轮换）
var _field_n := {}      # 每人微粒模式第几次场拍（隔一拍出一次绸带）
var _links: Array = []  # 连携引力环：{c, r, t0, oid}


func _init(px) -> void:
	r = px
	g = px.g


func _beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat, g.t, str(o.id) + k)


## 尺寸档：挑不超过判定 × 1.1 的最大一档
static func _zi(scale: float) -> int:
	var best := 0
	for i in 3:
		if Z[i] <= scale * 1.1 + 0.001:
			best = i
	return best


func _up(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "an_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


func _gd(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "an_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 跟场心走：场心是她自己（图鉴演示）就跟她（fo），否则跟队长（fol）
func _field_follow(o, c: Vector2) -> Dictionary:
	if o.pos != Vector2.INF and c.distance_to(o.pos) < 1.0:
		return {"fo": Vector2.ZERO}
	if g.ppos != Vector2.INF:
		return {"fol": c - g.ppos}
	return {}


func _muzzle(o) -> Vector2:
	return o.pos + Vector2(MUZZLE.x * float(o.face), MUZZLE.y)


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"ang_land":   # 重力弹落点：星芒（立起）+ 碎片吸入 / 暗凹 / 精一收紧断弧（贴地）
			if _beat_n(o, "land") >= LAND_CAP:
				return
			var c: Vector2 = d.c
			var s1: bool = d.get("s1", false)
			var z: int = _zi(float(d.get("r", 75.0)) / (75.0 * (1.4 if s1 else 1.0)))
			var m: String = "s1" if s1 else "n"
			_up(o, "land_%s_e%d_z%d_up" % [m, t, z], c, {"sk": 24.0})   # 星芒在身体高度，排序往前补，压在落点附近的敌人上
			_gd(o, "land_%s_e%d_z%d_gd" % [m, t, z], c)
			# docs/270 补齐（11-05）：落点一盏照地灯（普攻 130–150 / 0.6–0.68，S1 爆发 160–180 / 0.8–0.88，0.15 秒）；
			# 颗粒改成黑紫三角碎块 tri（6–10 px，有重量、落地会弹）：普攻 4 颗、S1 12 颗
			R._light(o, c + Vector2(0, -10), (160.0 if s1 else 130.0) + 10.0 * t, (0.8 if s1 else 0.6) + 0.04 * t, 0.15, p.light)
			R._grains(o, c + Vector2(0, -10), c.y + 2.0, "tri", 12 if s1 else 4, {"tier": t})   # S1 12 颗：拥挤降噪（fx_dim）后约 7 颗
		"shape":   # 双重 / 三重引力的第二、三次拉：往里收的断续环 + 小星芒（回响）
			if d.get("circle", false) and str(d.get("src", "")) == "双重引力":
				if _beat_n(o, "echo") >= 2:
					return
				_gd(o, "echo_z%d_gd" % _zi(float(d.get("r", 75.0)) / 75.0), d.get("c", o.pos))
		"ang_field":   # 常驻力场一拍：微粒模式有敌人在场内时隔一拍出一次绸带
			if str(d.get("look", "")) != "ring" or int(d.get("n", 0)) <= 0:
				return
			var id: String = str(o.id)
			var fn: int = int(_field_n.get(id, 0)) + 1
			_field_n[id] = fn
			if fn % 2 != 1:
				return
			var rn: int = int(_rib_n.get(id, 0))
			_rib_n[id] = rn + 1
			var c2: Vector2 = d.c
			var z2: int = _zi(float(d.get("ring", 110.0)) / 110.0)
			var ex: Dictionary = _field_follow(o, c2)
			ex["flip"] = (rn / 4) % 2 == 1
			_gd(o, "rib_e%d_z%d_r%d_gd" % [maxi(1, t), z2, int(RIB_ROT[rn % 4])], c2, ex)
		"skill":
			var si: int = int(d.get("i", -1))
			if si == 0:   # 速充模式：杖头一记星芒（跟她），头顶的弹药珠是状态件
				var mz: Vector2 = _muzzle(o)
				_up(o, "s1cast_up", mz, {"fo": mz - o.pos, "sk": maxf(0.0, o.pos.y - mz.y)})
				R._light(o, mz, 90.0, 0.5, 0.12, p.light)
			elif si == 1:   # 微粒模式：场外一圈短划收到环带
				var st: Dictionary = _field_state(o, "ring")
				var c3: Vector2 = st.get("c", g.ppos if g.demo_op == "" else o.pos)
				if c3 != Vector2.INF:
					_gd(o, "bandop_z%d_gd" % _zi(float(st.get("ring", 110.0)) / 110.0), c3, _field_follow(o, c3))
			elif si == 2:   # 反重力模式：场边从外往里收亮一下 + 头顶一圈亮点收成重力核心
				var st2: Dictionary = _field_state(o, "lift")
				var c4: Vector2 = st2.get("c", g.ppos if g.demo_op == "" else o.pos)
				if c4 != Vector2.INF:
					_gd(o, "liftop_z%d_gd" % _zi(float(st2.get("r", 220.0)) / 220.0), c4, _field_follow(o, c4))
				var cp: Vector2 = o.pos + Vector2(0, CORE_Y)
				_up(o, "gcore_cast_up", cp, {"fo": cp - o.pos, "sk": -CORE_Y + 1.0})
				R._light(o, cp + Vector2(0, 40), 160.0, 0.7, 0.15, p.light)
				R._grains(o, cp, o.pos.y + 2.0, "twinkle", 5, {"tier": 2})
		"ang_splash":   # 升级卡「扩散」：往里收的断续环（每拍至多 2）
			if _beat_n(o, "sp") >= 2:
				return
			_gd(o, "splash_gd", d.at)
		"ang_dense":   # 致密：叠向中心（收拢环）→ 坍缩爆开（八芒星芒 + 一圈亮环）
			if str(d.get("ph", "")) == "in":
				_gd(o, "dense_in_gd", d.c)
			else:
				_up(o, "dense_pop_up", d.c)
				R._light(o, d.c + Vector2(0, -8), 100.0, 0.6, 0.12, p.light)
				R._grains(o, d.c + Vector2(0, -8), (d.c as Vector2).y + 2.0, "shard", 4, {"tier": t})
		"ang_sink":   # 潮汐锁·沉落锁定：脚下四角括号收紧
			if _beat_n(o, "sk") >= 3:
				return
			var e: Dictionary = d.e
			_gd(o, "lock_gd", e.pos + Vector2(0, float(e.r) * 0.8))
		"ang_link":   # 连携「引力环」：三枚大碎片绕外圈收拢（运行时件）
			_links.append({"c": d.c, "r": float(d.get("r", 150.0)), "t0": g.t, "oid": str(o.id)})
			if _links.size() > 4:
				_links.pop_front()
		"ang_link_land":
			var c5: Vector2 = d.c
			_up(o, "lk_land_up", c5)
			_gd(o, "lk_land_gd", c5)
			R._light(o, c5 + Vector2(0, -12), 150.0, 0.7, 0.15, p.light)
			R._grains(o, c5 + Vector2(0, -10), c5.y + 2.0, "tri", 4, {"tier": 2})


func _field_state(o, look: String) -> Dictionary:
	var sd = o.get("_state")
	if sd is Dictionary:
		for u in sd:
			var st = sd[u]
			if st is Dictionary and str(st.get("look", "")) == look and st.has("c"):
				return st
	return {}


# ================================================================ 绘制

func draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	# 常驻场：微粒模式环带（很暗的短划慢慢转）、反重力模式场边
	var sd = o.get("_state")
	if sd is Dictionary:
		for u in sd:
			var st = sd[u]
			if not (st is Dictionary) or not st.has("c") or st.c == Vector2.INF:
				continue
			if str(st.get("look", "")) == "ring":
				r._draw_strip(cv, "an_band2_z%d_gd" % _zi(float(st.get("ring", 110.0)) / 110.0), r.frame_of(0.0), Pxp._snap(st.c), false, false)
			elif str(st.get("look", "")) == "lift":
				r._draw_strip(cv, "an_ripple_z%d_gd" % _zi(float(st.get("r", 220.0)) / 220.0), r.frame_of(0.0), Pxp._snap(st.c), false, false)
				for rk in _rock_list(st):   # 大碎石的地面影子（随高度变小）
					r._draw_strip(cv, "an_rocksh_w%d_gd" % int(rk[4]), 0, Pxp._snap(rk[1]), false, false)
	for it in r.items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)
	# 失重井（精二）：按井的年龄选帧
	var fl = o.get("fields")
	if fl is Array:
		for f in fl:
			if not (f is Dictionary) or not f.has("r"):
				continue
			r._draw_strip(cv, "an_well_z%d_gd" % _zi(float(f.r) / 60.0), r.frame_of(g.t - float(f.t)), Pxp._snap(f.pos), false, true)
	# 重力弹的地面投影
	var sh = o.get("shots")
	if sh is Array:
		for s in sh:
			r._draw_strip(cv, "an_orb_sh_gd", 0, Pxp._snap(_shot_ground(s)), false, false)


func _shot_k(s: Dictionary) -> float:
	return clampf(float(s.t) / maxf(0.01, float(s.dur)), 0.0, 1.0)


## 弹的画面位置（同 data_operator._draw_shots：直线插值 + 弧高 26）
func _shot_pos(s: Dictionary) -> Vector2:
	var k: float = _shot_k(s)
	return (s.p0 as Vector2).lerp(s.p1, k) + Vector2(0, -sin(k * PI) * ARC_H)


func _shot_pos_k(s: Dictionary, k: float) -> Vector2:
	return (s.p0 as Vector2).lerp(s.p1, k) + Vector2(0, -sin(k * PI) * ARC_H)


## 弹的地面投影点：从杖头正下方的地面到落点
func _shot_ground(s: Dictionary) -> Vector2:
	var g0: Vector2 = s.get("g0", s.p0)
	var gs := Vector2((s.p0 as Vector2).x, g0.y)
	return gs.lerp(s.p1, _shot_k(s))


## 立起层的状态件（每帧生成）：重力弹、速充弹药珠、重力核心、反重力大碎石、连携碎片、透镜线
func sort_items(o, out: Array) -> void:
	_air_frame = -1   # 悬浮表每帧重建
	var sh = o.get("shots")
	if sh is Array:
		for s in sh:
			out.append({"an": "orb", "s": s, "o": o, "gy": _shot_ground(s).y + 1.0})
	if o.pos == Vector2.INF:
		return
	var am = o.get("ammo")
	if am is Array and int(am[0]) > 0:
		out.append({"an": "pips", "o": o, "n": mini(3, int(am[0])), "gy": o.pos.y + 0.5})
	if o.skill_active_left(2) > 0.0:
		out.append({"an": "loop", "k": "an_gcore_up", "gp": Pxp._snap(o.pos + Vector2(0, CORE_Y)), "gy": o.pos.y + 1.0})
		var st: Dictionary = _field_state(o, "lift")
		if not st.is_empty() and st.c != Vector2.INF:
			for rk in _rock_list(st):
				out.append({"an": "loop", "k": "an_rockb_v%d_up" % int(rk[0]), "gp": Pxp._snap((rk[1] as Vector2) - Vector2(0, float(rk[3]) + 10.0)), "gy": (rk[1] as Vector2).y + 1.0})
	var now: float = g.t
	_links = _links.filter(func(L): return now - float(L.t0) < LINK_T)
	for L in _links:
		if str(L.oid) != str(o.id):
			continue
		for j in 3:
			var q: Vector2 = _link_pos(L, now - float(L.t0), j)
			out.append({"an": "lks", "L": L, "j": j, "gy": q.y + 14.0})
	if "dense" in o.get("taken") and sh is Array:
		for s in sh:
			out.append({"an": "lens", "s": s, "o": o, "gy": _shot_ground(s).y})


## 反重力大碎石（同 pxplane_ang_art.rock_state）：场开着第 t 秒时在场的碎石，每 0.6 秒生一块、每块活 2 秒（同屏 ≤ 4），
## 绕场心缓慢转、托起 24 → 悬停微浮 → 落回；坐标哈希，不抽随机数。返回 [[变体, 地面点, 0, 高度, 影子半宽]]
func _rock_list(st: Dictionary) -> Array:
	var out: Array = []
	var t: float = float(st.get("t", 0.0))
	var R: float = float(st.get("r", 220.0)) * 0.97
	var c: Vector2 = st.c
	var n_now: int = int(floor(t / 0.6))
	for n in range(maxi(0, n_now - 3), n_now + 1):
		var age: float = t - float(n) * 0.6
		if age < 0.0 or age >= 2.0:
			continue
		var a0: float = _hf(n, 1, 7) * TAU
		var rr: float = R * (0.35 + 0.45 * _hf(n, 2, 13))
		var a: float = a0 + 0.55 * age
		var h: float
		if age < 0.4:
			var u: float = age / 0.4
			h = 24.0 * (1.0 - (1.0 - u) * (1.0 - u))
		elif age < 1.6:
			h = 24.0 + (2.0 if (int(age * 15.0) / 3) % 2 == 1 else 0.0)
		else:
			var u2: float = 1.0 - (age - 1.6) / 0.4
			h = 24.0 * u2 * u2
		var gp: Vector2 = c + Vector2(cos(a) * rr, sin(a) * rr * 0.72)
		var sw: int = 6 if h < 8.0 else (4 if h < 18.0 else 3)
		out.append([n % 2, gp, 0, h, sw])
	return out


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


## 连携碎片位置（同 skill_link l_angelina：半径 r + 150 → 0.4 r、转一圈），飞行高度 14
func _link_pos(L: Dictionary, age: float, j: int) -> Vector2:
	var k: float = clampf(age / LINK_T, 0.0, 1.0)
	var rr: float = lerpf(float(L.r) + 150.0, float(L.r) * 0.4, k)
	return (L.c as Vector2) + Vector2.from_angle(TAU * (k + float(j) / 3.0)) * rr + Vector2(0, -14)


func draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	match str(it.an):
		"loop":
			r._draw_strip(ci, str(it.k), r.frame_of(0.0), it.gp, false, false)
		"orb":   # 重力弹 + 弹尾 3 点（同 pxplane_ang_art.trail_px）
			var s: Dictionary = it.s
			var o = it.o
			var t: int = r.tier(o)
			var k: float = _shot_k(s)
			for q in [[1, 4], [2, 3], [3, 2]]:
				var kk: float = k - 0.05 * float(q[0])
				if kk > 0.0:
					r._px(ci, _shot_pos_k(s, kk), V[int(q[1])])
			var big: bool = not (s.get("patch", {}) as Dictionary).is_empty()
			r._draw_strip(ci, ("an_orb_s1_e%d" if big else "an_orb_e%d") % t, r.frame_of(0.0), Pxp._snap(_shot_pos(s)), false, false)
		"pips":   # 速充模式剩余弹数（同 pxplane_ang_art.pips_px）：头顶 3×3 小珠绕圈
			var o2 = it.o
			var head: Vector2 = Pxp._snap(o2.pos + Vector2(0, -92))
			var bt: int = int(floor(g.t * 15.0))
			for j in int(it.n):
				var a: float = float(bt) * 0.42 + float(j) * TAU / 3.0
				var c0 := Vector2(round(cos(a) * 7.0), round(sin(a) * 2.0))
				var front: bool = sin(a) > 0.0
				r._px(ci, head + c0 * px, V[7] if front else V[6])
				if front:
					r._glow(head + c0 * px, V[7])
				for dd in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					r._px(ci, head + (c0 + dd) * px, V[5] if front else V[4])
		"lks":   # 连携碎片 + 尾迹（同 pxplane_ang_art.link_trail）
			var L: Dictionary = it.L
			var age: float = g.t - float(L.t0)
			var j2: int = int(it.j)
			for q2 in [[1, 5], [2, 5], [3, 4], [4, 4], [5, 3], [6, 2]]:   # 每 0.01 秒一个采样点，相邻两点连成 1 像素线
				var a2: float = age - 0.01 * float(q2[0])
				if a2 <= 0.0:
					break
				var pa: Vector2 = _link_pos(L, a2 + 0.01, j2)
				var pb: Vector2 = _link_pos(L, a2, j2)
				var ns: int = maxi(1, int(pa.distance_to(pb) / px))
				for s in ns + 1:
					r._px(ci, pa.lerp(pb, float(s) / float(ns)), V[int(q2[1])])
			r._draw_strip(ci, "an_lk_shard_up", r.frame_of(float(j2) / 15.0), Pxp._snap(_link_pos(L, age, j2)), false, false)
		"lens":   # 致密的重力透镜：弹道两侧往弹头收拢的 1 像素点线（只在选了节点时）
			var s2: Dictionary = it.s
			var g0: Vector2 = s2.get("g0", s2.p0)
			var gp: Vector2 = _shot_ground(s2)
			var dv: Vector2 = gp - g0
			if dv.length() < 8.0:
				return
			var nv: Vector2 = dv.normalized().orthogonal() * float(it.o.base("lens_r", 60.0)) * 0.8
			var n: int = int(dv.length() / (px * 3.0))
			for i in n + 1:
				var u: float = float(i) / float(maxi(1, n))
				r._px(ci, g0.lerp(gp, u), V[3] if i % 2 == 0 else V[2])
				if i % 2 == 0:
					r._px(ci, (g0 + nv).lerp(gp, u), V[2])
					r._px(ci, (g0 - nv).lerp(gp, u), V[2])


## world.gd 画悬浮敌人时读（只画）：x = 影子缩放（越高越小越淡），y = 悬停时的上下浮动（世界像素，按 15 fps 节拍、1 美术像素）
func air_look(e: Dictionary) -> Vector2:
	var fr: int = Engine.get_process_frames()
	if fr != _air_frame:
		_air_frame = fr
		_air.clear()
		for o in g.squad.ops:
			if str(o.id) == "angelina":
				var al = o.get("air_list")
				if al is Array:
					for a in al:
						_air[int(a.e.id)] = a
	var a2 = _air.get(int(e.get("id", -1)), null)
	if a2 == null:
		return Vector2(1.0, 0.0)
	var hk: float = clampf(1.0 - float(e.get("air", 0.0)) / 50.0, 0.5, 1.0)
	var bob := 0.0
	if float(a2.t) > 0.2 and float(a2.dur) - float(a2.t) > 0.25:
		bob = 2.0 if posmod(int(floor(g.t * 15.0)) / 3 + int(e.id), 2) == 1 else 0.0
	return Vector2(hk, bob)
