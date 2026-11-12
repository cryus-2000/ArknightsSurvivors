## 推进之王（docs/264，照 docs/246 斯卡蒂 / docs/254 星熊的做法）
## 帧条 pxp_sg_*（tools/pixelfx_fx/melee/ak-siege-pp.js，tools/pxplane_bake.py --op siege）。主色本人金（熔金 8 阶），尘 / 碎石暖土，精二点缀白金熔芯。
## 普攻「锤击」= 下砸锤弧（挂在人身上，跟人走）+ 落点白闪 / 火星线 / 分叉裂网（落地留在原地）；精一碎石 + 隆起尘墙 + 「粉碎」碎石迸开；精二裂缝熔芯 + 「破阵」地裂与岩刺；
## S1「冲锋号令·γ型」= 腰高号令声浪 + 脚下冲击环，下一锤换「号令一锤」（锤弧更粗、落点金色冲击环）；分支「万兽之王」号令波读玩法状态 o.hw.sg.waves；
## S2「跃空锤」= 起跳一小圈 → 落地竖直冲柱 + 大裂网 + 冲击环 + 碎石 + 尘墙（精二熔芯 + 环外前向枝裂）；
## S3「碎颅击」= 起手腰高横向光带 + 冲击环，持续时脚下炭火边，每锤横向扁白闪 + 向前分叉的地裂扇；
## 后期剑气（钝器）= 锤击冲击波（贴地往前滚的土浪 + 身后裂痕），同一次出手几道合成一道；技能连携 v2「冲阵」= 尾锤大砸坑。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")


static func _ev_sg(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用：事件的游戏时间
		print("PXPLOG sg %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	var id: String = str(o.id)
	match kind:
		"swing":   # 锤击（普攻 / 冲锋号令强化一锤 / 碎颅）：seg_siege._h4_hammer_release
			var ang: float = float(d.get("ang", 0.0))
			var reach: float = float(d.get("reach", 92.0))
			var heavy: bool = d.get("heavy", false)
			var patch: bool = d.get("patch", false)
			var dv := Vector2.from_angle(ang)
			var imp: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * reach * 0.7   # 锤弧落点（平面里压扁的那一点）
			var dk: Array = pv.pick_dir(ang)
			pv._sg_imp[id] = imp   # 这一锤的落点（破阵地裂从这里裂出去；只画）
			if pv.mode() == 1:   # 落点亮芯稳定进发光层（docs/270：普攻命中帧核心辉光 ≥ 30；帧条 emit 是均匀抽点，大多落在四散的火星上）
				if pv._sg_cores.size() >= 6:
					pv._sg_cores.pop_front()
				pv._sg_cores.append({"at": pv._snap(imp + Vector2(0, -6)), "t0": g.t, "big": bool(d.get("heavy", false)) or bool(d.get("patch", false))})
			if raw:
				var rk: String = "sg_raw_s3" if heavy else "sg_raw_imp_e%d" % t
				pv._push({"k": rk, "t0": g.t, "gp": imp + Vector2(0, -6), "ly": "raw", "rot": ang, "sc": g.PX * (reach * 0.5) / 46.0, "oid": id})
				return
			var ak: String
			if heavy:
				ak = "sg_arc_s3_up_d%d" % dk[0]
			elif patch:
				ak = "sg_arc_s1_e%d_up_d%d" % [t, dk[0]]
			else:
				ak = "sg_arc_r%d_e%d_up_d%d" % [pv._bucket(reach * 0.5, [46, 56, 66]), t, dk[0]]
			# 同一名干员同屏只留最新一锤 + 正在收的一锤（不叠成一团）
			var sl: Array = []
			for it in pv.items:
				if str(it.oid) == id and it.get("slash", false):
					sl.append(float(it.t0))
			if sl.size() >= 2:
				sl.sort()
				var keep_t: float = float(sl[sl.size() - 1])
				pv.items = pv.items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == id and float(it.t0) < keep_t))
			pv._push({"k": ak, "t0": g.t, "gp": pv._snap(o.pos), "flip": dk[1], "ly": "up", "oid": id, "slash": true, "fo": Vector2.ZERO})   # 锤弧挂在人身上：跟人走
			if heavy:
				pv._push({"k": "sg_s3_up", "t0": g.t, "gp": pv._snap(imp), "flip": false, "ly": "up", "oid": id})
				pv._push({"k": "sg_s3_gd_d%d" % dk[0], "t0": g.t, "gp": pv._snap(imp), "flip": dk[1], "ly": "gd", "oid": id})
			else:
				var ik: String = "sg_imp_%s_e%d" % ["s1" if patch else "atk", t]
				pv._push({"k": ik + "_up", "t0": g.t, "gp": pv._snap(imp), "flip": false, "ly": "up", "oid": id})
				pv._push({"k": ik + "_gd", "t0": g.t, "gp": pv._snap(imp), "flip": false, "ly": "gd", "oid": id})
			var big: bool = heavy or patch
			pv._burst_m(o, R, p, imp + Vector2(0, -8), imp.y + 2.0, d.get("es", []), (2 + mini(t, 1)) + (4 if big else 0), "rock", 100.0 + (60.0 if big else 0.0), 0.4 + (0.3 if big else 0.0))   # docs/270：普攻颗粒中位 10 → 压回 3–8
		"crush":   # 精一「粉碎」：击倒处碎石迸开（强制低档画面时不画）
			if t < 1 or raw:
				return
			var at: Vector2 = d.get("at", o.pos)
			pv._push({"k": "sg_crush_up", "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "up", "oid": id})
			pv._push({"k": "sg_crush_gd", "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "gd", "oid": id})
			if pv.mode() == 1:
				R._grains(o, at + Vector2(0, -8), at.y, "rock", 2, {"tier": t})
		"breach":   # 精二「破阵」地裂 + 岩刺 / 再跃（队长版）原地砸出的地裂（不出岩刺）
			var pts: PackedVector2Array = d.get("pts", PackedVector2Array())
			if pts.size() < 2 or raw:
				return
			var spikes: bool = d.get("spikes", false)
			if spikes and t < 2:
				return
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[pts.size() - 1]
			var fa: float = (b - a).angle()
			var dk2: Array = pv.pick_dir(fa)
			var st: Vector2 = pv._sg_imp.get(id, a) if spikes else o.pos + Vector2(a.x - o.pos.x, (a.y - o.pos.y) * 0.72)
			var L: int = 90 if spikes else pv._bucket(a.distance_to(b) * 0.5, [60, 90, 110])
			var pre: String = "sg_fis" if spikes else "sg_crk"
			pv._push({"k": "%s_l%d_gd_d%d" % [pre, L, dk2[0]], "t0": g.t, "gp": pv._snap(st), "flip": dk2[1], "ly": "gd", "oid": id})
			if spikes:
				pv._push({"k": "sg_fis_l90_up_d%d" % dk2[0], "t0": g.t, "gp": pv._snap(st), "flip": dk2[1], "ly": "up", "oid": id})
			if pv.mode() == 1:
				var mid: Vector2 = st + Vector2(cos(fa), sin(fa) * 0.72) * float(L)
				R._grains(o, mid + Vector2(0, -6), mid.y, "rock", 1, {"tier": t})   # docs/270：普攻单次颗粒 ≤ 12
				R._light(o, mid, 120.0, 0.45, 0.15, p.light)
		"quake":   # 成长「震地」/「狮吼」：落点一圈贴地冲击环（狮吼双环）
			if raw:
				return
			var qa: Vector2 = d.get("at", o.pos)
			pv._push({"k": "sg_quake_r%d_%s_gd" % [pv._bucket(float(d.get("r", 70.0)) * 0.5, [35, 45, 55]), "roar" if d.get("roar", false) else "q"], "t0": g.t, "gp": pv._snap(qa), "flip": false, "ly": "gd", "oid": id})
		"crash":   # 狮吼：被击退的敌人撞上别的敌人 / 障碍
			if raw:
				return
			var ca: Vector2 = d.get("at", o.pos) + Vector2(0, 8)
			pv._push({"k": "sg_crash_up", "t0": g.t, "gp": pv._snap(ca), "flip": false, "ly": "up", "oid": id})
			pv._push({"k": "sg_crash_gd", "t0": g.t, "gp": pv._snap(ca), "flip": false, "ly": "gd", "oid": id})
			if pv.mode() == 1:
				R._light(o, ca, 70.0, 0.35, 0.1, p.light)
		"leap":   # 跃空锤起跳：脚下一小圈 + 起跳点 → 落点一道金色残影弧（她在空中抡锤转一圈）
			if raw:
				return
			pv._push({"k": "sg_crash_gd", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": id})
			var to: Vector2 = d.get("to", o.pos)
			if to.distance_to(o.pos) > 8.0:
				var dk3: Array = pv.pick_dir((to - o.pos).angle())
				pv._push({"k": "sg_trail_l%d_e%d_up_d%d" % [pv._bucket(to.distance_to(o.pos) * 0.5, [24, 45]), maxi(t, 1), dk3[0]], "t0": g.t, "gp": pv._snap(o.pos), "flip": dk3[1], "ly": "up", "oid": id})
			if pv.mode() == 1:
				R._grains(o, o.pos + Vector2(0, -4), o.pos.y, "rock", 3, {"tier": t})
		"slam":   # 跃空锤落地（含再跃第二下）
			_sg_slam(pv, o, R, p, d.get("at", o.pos), float(d.get("r", 110.0)), d.get("es", []), raw, maxi(t, 1), "slam")
			_sg_motes(pv, o, 1)
		"shape":   # 路线「再跃·裂地」：跃空锤落地 0.8 秒后以自身为心再震一圈（circle 震地 r140）
			if d.get("circle", false) and str(d.get("src", "")) == "震地":
				_sg_slam(pv, o, R, p, d.get("c", o.pos), float(d.get("r", 140.0)), d.get("es", []), raw, maxi(t, 1), "rift")
		"skill":
			var i: int = int(d.get("i", -1))
			if raw:
				return
			if i == 0:   # 冲锋号令：身后战旗 + 身前狮头剪影与狮吼声波环（朝她面向，跟人走）+ 脚下淡金涟漪 + 技力粒子飞向队友 + 轻震
				pv._push({"k": "sg_s1cast_e%d_up" % t, "t0": g.t, "gp": pv._snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": id, "fo": Vector2.ZERO})
				pv._push({"k": "sg_lion_e%d_up" % t, "t0": g.t, "gp": pv._snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": id, "fo": Vector2.ZERO})   # 狮头（生图转帧条，docs/264 §8）
				if pv.mode() == 1 and g.ult != null:
					g.ult.shake(2.0, 0.12)   # 狮吼：轻微震屏（用户同意的 3px / 0.12s 量级以内，按真实时间）
				pv._push({"k": "sg_s1cast_e%d_gd" % t, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": id})
				_sg_motes(pv, o, 2)
				if pv.mode() == 1:
					R._light(o, o.pos + Vector2(0, -30), 130.0, 0.5, 0.15, p.light)
			elif i == 2:   # 碎颅击起手：腰高横向光带（跟人走）+ 脚下冲击环
				pv._push({"k": "sg_s3cast_up", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": id, "fo": Vector2.ZERO})
				pv._push({"k": "sg_s3cast_gd", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": id})
				if pv.mode() == 1:
					R._light(o, o.pos + Vector2(0, -24), 150.0, 0.6, 0.15, p.light)
		"link_dash":   # 技能连携 v2「冲阵」冲刺途中：脚下扬起的碎土（代替通用拖影 / 尘）
			if pv.mode() == 1 and g.vrng.randf() < 0.35:
				var q: Vector2 = d.get("q", o.pos)
				R._grains(o, q + Vector2(0, -2), q.y + 2.0, "rock", 1, {"tier": 1})
		"link_slam":   # 「冲阵」尾锤：大砸坑 + 裂网 + 冲击环 + 碎石 + 两层尘墙
			var lc: Vector2 = d.get("c", o.pos)
			if raw:
				pv._push({"k": "sg_raw_slam_e1", "t0": g.t, "gp": lc, "ly": "raw", "rot": 0.0, "sc": g.PX * 46.0 / 55.0, "oid": id})
				return
			pv._push({"k": "sg_link_up", "t0": g.t, "gp": pv._snap(lc), "flip": false, "ly": "up", "oid": id})
			pv._push({"k": "sg_link_gd", "t0": g.t, "gp": pv._snap(lc), "flip": false, "ly": "gd", "oid": id})
			pv._burst_m(o, R, p, lc + Vector2(0, -10), lc.y + 2.0, d.get("es", []), 10, "rock", 170.0, 0.7)


## S2 落地 = 环形尘浪（slam，不开裂）；路线「再跃·裂地」= 冲柱 + 裂网（rift）
static func _sg_slam(pv: P, o, R, p: Dictionary, at: Vector2, r: float, es: Array, raw: bool, t: int, kind: String) -> void:
	var g = pv.g
	if raw:
		pv._push({"k": "sg_raw_slam_e%d" % t, "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 55.0, "oid": str(o.id)})
		return
	var sk: String = ("sg_rift_r70_e%d" % t) if kind == "rift" else ("sg_slam_r55_e%d" % t)
	pv._push({"k": sk + "_up", "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "up", "oid": str(o.id)})
	pv._push({"k": sk + "_gd", "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})
	pv._burst_m(o, R, p, at + Vector2(0, -10), at.y + 2.0, es, 8 + 3 * t, "rock", 200.0, 0.85)


## 技力粒子：从她飞向每名队友（状态提示，原程序 h4_spmote 接管时不画，这里按美术像素格画）
static func _sg_motes(pv: P, o, n: int) -> void:
	var g = pv.g
	if pv.mode() != 1:
		return
	for m in g.squad.ops:
		if m == o or m.pos == Vector2.INF:
			continue
		for k in n:
			if pv._motes.size() >= 24:
				pv._motes.pop_front()
			pv._motes.append({"to": m, "from": o.pos + Vector2(0, -22), "t0": g.t + 0.06 * k, "life": 0.45 + 0.08 * k, "bend": g.vrng.randf_range(-40.0, 40.0)})


static func _sg_draw_motes(pv: P, o) -> void:
	var g = pv.g
	if pv._motes.is_empty():
		return
	var cv = o.cv
	var px: float = g.PX
	var keep: Array = []
	for mt in pv._motes:
		var age: float = g.t - float(mt.t0)
		if age > float(mt.life):
			continue
		keep.append(mt)
		if age < 0.0 or mt.to.pos == Vector2.INF:
			continue
		var k: float = age / float(mt.life)
		var st: Vector2 = mt.from
		var to: Vector2 = mt.to.pos + Vector2(0, -24)
		var at: Vector2 = st.lerp(to, k) + Vector2(0, -sin(k * PI) * 30.0) + st.direction_to(to).orthogonal() * sin(k * PI) * float(mt.bend)
		var k2: float = maxf(0.0, k - 0.1)
		var tl: Vector2 = st.lerp(to, k2) + Vector2(0, -sin(k2 * PI) * 30.0) + st.direction_to(to).orthogonal() * sin(k2 * PI) * float(mt.bend)
		cv.draw_rect(Rect2(pv._snap(tl), Vector2(px, px)), Color("#e08e26"))
		var c: Vector2 = pv._snap(at)
		cv.draw_rect(Rect2(c - Vector2(px, px) * 0.5, Vector2(px, px) * 2.0), Color("#ffbf3c"))
		cv.draw_rect(Rect2(c, Vector2(px, px)), Color("#fff1b8"))
		if g.optical_on and pv._emit_n < P.EMIT_CAP:
			pv._emit_n += 1
			g.glow_next.append([c, px, Color(1.0, 0.85, 0.5, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])
	pv._motes = keep


## 地面层（推进之王）：贴地件、号令波（读 o.hw.sg.waves）、碎颅击持续时脚下炭火边、锤击冲击波的影子与裂痕
static func _floor_sg(pv: P, o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	_sg_draw_cores(pv)   # 落点亮芯先排进发光层：地面层每帧最先画，整队 EMIT_CAP 顶满时也不被挤掉（docs/270）
	if o.skill_active_left(2) > 0.0:
		pv._draw_strip(cv, "sg_s3aura_gd", pv.frame_of(0.0), pv._snap(o.pos + Vector2(0, 2)), false, false)
	if o.hw.has("sg"):
		for w in o.hw.sg.get("waves", []):   # 万兽之王号令波：帧号按波自己的年龄（0.4 秒扩满 + 0.25 秒淡掉）
			pv._draw_strip(cv, "sg_cmd_gd", int(floor(float(w.t) * 15.0)), pv._snap(w.pos), false, true)
	for it in pv.items_for(id):
		if str(it.ly) == "gd":
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), pv._gp(it), it.flip, true)
	_sg_qi_track(pv, o)


static func _sg_qi_track(pv: P, o) -> void:
	var g = pv.g
	var id: String = str(o.id)
	if not o.vg.is_empty() and o.vg.has("qi"):
		var grp: Array = []
		for q in o.vg.qi:
			if not q.has("_pxw"):
				q["_pxw"] = true
				grp.append(q)
		if not grp.is_empty():
			var p0 := Vector2.ZERO
			var dsum := Vector2.ZERO
			for q in grp:
				p0 += q.p
				dsum += (q.v as Vector2).normalized()
			p0 /= float(grp.size())
			var dir: Vector2 = dsum.normalized() if dsum.length() > 0.01 else Vector2.RIGHT
			var n: int = grp.size()
			var S: int = 18 if n <= 1 else (24 if n == 2 else 30)
			var dk: Array = pv.pick_dir(dir.angle())
			var mv := {"p0": p0, "dir": Vector2(dir.x, dir.y * 0.72).normalized()}
			var k: String = "sg_wave_s%d_e%d" % [S, pv.tier(o)]
			var mine: Array = pv._sgw.filter(func(w): return str(w.oid) == id)
			if mine.size() >= 2:   # 同屏每人至多两道：最早的一道立刻收掉
				var old: Dictionary = mine[0]
				var omv: Dictionary = old.mv
				pv.items = pv.items.filter(func(it): return not (it.has("mv") and is_same(it.mv, omv)))
				pv._sgw.erase(old)
			pv._push({"k": k + "_up_d%d" % dk[0], "t0": g.t, "gp": pv._snap(p0), "flip": dk[1], "ly": "up", "oid": id, "mv": mv})
			pv._push({"k": k + "_gd_d%d" % dk[0], "t0": g.t, "gp": pv._snap(p0), "flip": dk[1], "ly": "gd", "oid": id, "mv": mv})
			pv._sgw.append({"oid": id, "mv": mv, "t0": g.t, "hits": {}, "S": float(S) * 2.0})
	if pv._sgw.is_empty() or pv.mode() != 1:
		return
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var keep: Array = []
	for w in pv._sgw:
		if g.t - float(w.t0) > 0.55:
			continue
		keep.append(w)
		if str(w.oid) != id or w.hits.size() >= 5:
			continue
		var front: Vector2 = pv._gp({"mv": w.mv, "t0": w.t0})
		for j in o.query_ids(front, float(w.S) + 20.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hits.has(e.id) or e.pos.distance_to(front) > float(w.S) * 0.8 + float(e.r):
				continue
			w.hits[e.id] = true
			R._grains(o, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.pos.y) + 2.0, "streak", 2, {"tier": pv.tier(o)}, w.mv.dir)
			if w.hits.size() >= 5:
				break
	pv._sgw = keep


## 锤击落点亮芯：白闪那三拍（0.2 秒）在落点排一块十字形发光点（中心 4×4 美术像素、四臂各 1 格；号令一锤 / 碎颅大一圈），之后每拍缩一格、变暗
static func _sg_draw_cores(pv: P) -> void:
	var g = pv.g
	if pv._sg_cores.is_empty() or not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != pv._emit_frame:   # 同 _emit：每帧重新计数（整队共用 EMIT_CAP）
		pv._emit_frame = fr
		pv._emit_n = 0
	var px: float = g.PX
	var k: float = Bal.v("fx/px_plane_emit", 0.8)
	var keep: Array = []
	for c in pv._sg_cores:
		var age: float = g.t - float(c.t0)
		if age > 0.2:
			continue
		keep.append(c)
		var f2: bool = age > 0.067
		var s: float = (4.0 if not c.big else 5.0) - (1.0 if f2 else 0.0) - (1.0 if age > 0.134 else 0.0)
		var col: Color = Color(1.0, 0.97, 0.85, minf(1.0, k * 1.2)) if not f2 else Color(1.0, 0.88, 0.55, k)
		var at: Vector2 = c.at
		var pts: Array = [[at - Vector2(s, s) * px * 0.5, s * px]]
		for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			pts.append([pv._snap(at + dv * (s * 0.5 + 0.5 + (1.0 if c.big else 0.0)) * px) - Vector2(px, px) * 0.5, px])
		for q in pts:
			if pv._emit_n >= P.EMIT_CAP:
				break
			pv._emit_n += 1
			g.glow_next.append([q[0], q[1], col])
	pv._sg_cores = keep
