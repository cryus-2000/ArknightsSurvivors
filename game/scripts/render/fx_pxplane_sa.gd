## 塞雷娅转平面（docs/269，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节，单独成文件（第四批五人并行，少撞 fx_pxplane.gd）。
## 帧条由 tools/pxplane_bake_saria.py 烤（图形 tools/pxplane_saria_art.py），键前缀 sa_；
## 注射器 / 碎晶片弹体、阻挡圈、晶柱墙脚、钙化斑在这里按美术像素格逐格画（算法同 pxplane_saria_art.py 的 syringe() / shard() / guard_ring()，改一边要改另一边）。
## 只画：读玩法状态（o.hw.sa、o.vg.qi），画面专用键只写 _pxs（剑气晶刺的生成进度，玩法不读）；不碰玩法与玩法随机数。
## 挂在人身上的件带 fo（跟她）或 fol（跟队长：治疗、连携护盾、药物配置光环）；命中芒跟被打的那只（e）；冲击环、裂纹、碎晶、地面斑留在原地。
extends RefCounted

const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")

const AMB := [Color("#2a1606"), Color("#5a300c"), Color("#9a5a16"), Color("#d88a2a"), Color("#f5b860"), Color("#ffe2b0"), Color("#ffffff")]
const HEAL := [Color("#06200e"), Color("#0c4420"), Color("#16803a"), Color("#2cc060"), Color("#78e89a"), Color("#c8f8d6"), Color("#ffffff")]
const WH := [Color("#2e2820"), Color("#6a5c48"), Color("#b4a284"), Color("#e6d8bc"), Color("#fff3de"), Color("#fffaf2"), Color("#ffffff")]
const DUST3 := Color("#857a68")
const SHADOW := Color("#141210")
const SQ := 0.72
const BASH_R := [40, 49, 58, 68]
const SUIT_R := [55, 66]
const SHAT2_R := [45, 54]
const HEAL_LIGHT := Color(0.5, 1.0, 0.65)
const QI_STEP := 20.0      # 剑气晶刺：每推进 20 世界像素冒一根
const QI_MAX := 20         # 每人同屏晶刺上限（fx_pxplane 件表整队共用 72 个）
const CHIP_SZ := [4, 4, 4, 2]   # 碎晶屑边长（世界像素）：3 / 4 是 4 px 大颗、1 / 4 是 2 px 点缀，平均 3.5（docs/270 §3：平均边长 ≥ 3；原 shard 2 / 4 各半实测 2.8）
const HIT_N := 3           # 一记盾击至多画 3 只身上的命中芒

var r      # fx_pxplane 实例
var g
var _beat := {}
var _seg = null


func _init(px) -> void:
	r = px
	g = px.g


func _sg():
	if _seg == null:
		_seg = load("res://scripts/characters/blocks/seg_saria.gd")   # 运行时取（避免和积木链循环 preload）
	return _seg


func _beat_n(o, k: String) -> int:
	var key: String = str(o.id) + k
	var bt: int = int(floor(g.t * 15.0))
	var c: Array = _beat.get(key, [bt, 0])
	if int(c[0]) != bt:
		c = [bt, 0]
	c[1] = int(c[1]) + 1
	_beat[key] = c
	return int(c[1]) - 1


static func _near(arr: Array, v: float) -> int:
	var best: int = int(arr[0])
	for x in arr:
		if absf(float(x) - v) < absf(float(best) - v):
			best = int(x)
	return best


func _up(o, k: String, at: Vector2, gy: float, extra := {}) -> void:
	var it := {"k": "sa_" + k, "t0": g.t, "gp": Pxp._snap(at), "gy": gy, "flip": false, "ly": "up", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


func _gd(o, k: String, at: Vector2, extra := {}) -> void:
	var it := {"k": "sa_" + k, "t0": g.t, "gp": Pxp._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	it.merge(extra, true)
	r._push(it)


## 挂在她身上的件：fo = 相对脚底的偏移（每次绘制按她当前位置重算）
func _on_her(o, k: String, flip: bool, ly: String) -> void:
	r._push({"k": "sa_" + k, "t0": g.t, "gp": Pxp._snap(o.pos), "flip": flip, "ly": ly, "oid": str(o.id), "fo": Vector2.ZERO})


## 跟着队长的件（治疗 / 护盾）：fol = 相对队长脚底的偏移，fx_pxplane._step 每拍跳一格
func _on_lead(o, k: String, ly: String, sk := 0.0) -> void:
	r._push({"k": "sa_" + k, "t0": g.t, "gp": Pxp._snap(g.ppos), "flip": false, "ly": ly, "oid": str(o.id), "fol": Vector2.ZERO, "sk": sk})


func _hit_pts(o, es: Array, key: String) -> void:
	var n := 0
	for e in es:
		if n >= HIT_N or e.get("dead", false):
			continue
		n += 1
		var dp: Array = Pxp.pick_dir(((e.pos as Vector2) - o.pos).angle())
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.55)
		r._push({"k": "sa_" + key + "_d%d" % int(dp[0]), "t0": g.t, "gp": Pxp._snap(hp), "gy": float(e.pos.y) + 1.0, "flip": bool(dp[1]), "ly": "up", "oid": str(o.id), "e": e})


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	match kind:
		"sa_bash":   # 持盾出拳：钝头盾面冲击（立起，跟她）+ 推地擦痕（贴地，跟她）+ 命中暖白芒；钙质化期间空手拳 = 碎晶喷射 + 琥珀芒
			var Ra: int = _near(BASH_R, float(d.r) * 0.5)
			var dp: Array = Pxp.pick_dir(float(d.ang))
			var es: Array = d.get("es", [])
			if d.get("calc", false):
				_on_her(o, "cbash_r%d_d%d" % [Ra, int(dp[0])], bool(dp[1]), "up")
				_hit_pts(o, es, "hita")
			else:
				_on_her(o, "bash_r%d_e%d_up_d%d" % [Ra, mini(t, 1), int(dp[0])], bool(dp[1]), "up")
				_on_her(o, "bash_r%d_gd_d%d" % [Ra, int(dp[0])], bool(dp[1]), "gd")
				_hit_pts(o, es, "hitc" if t >= 1 else "hit")
			if not es.is_empty():
				var e0: Dictionary = es[0]
				var hp: Vector2 = e0.pos + Vector2(0, -float(e0.r) * 0.55)
				R._light(o, hp, 80.0 + 10.0 * t, 0.55 + 0.05 * t, 0.1, p.light)
				if t >= 1 or d.get("calc", false):
					R._grains(o, hp, float(e0.pos.y) + 2.0, "shard", 2 + mini(es.size(), 3), {"tier": t, "grain_sz": CHIP_SZ}, ((e0.pos as Vector2) - o.pos).normalized())
		"sa_suit":   # 精二满格环冲：贴地冲击环 + 6 道推地楔痕（留原地）+ 身前爆闪（跟她）
			var Rs: int = _near(SUIT_R, float(d.r) * 0.5)
			_gd(o, "suit_r%d_gd" % Rs, o.pos)
			_on_her(o, "suit_up", false, "up")
			_hit_pts(o, d.get("es", []), "hitc")
			R._light(o, o.pos + Vector2(0, -20), float(d.r) * 1.1, 0.8, 0.15, p.light)
			R._grains(o, o.pos + Vector2(0, -24), o.pos.y + 2.0, "shard", 8, {"tier": 2, "grain_sz": CHIP_SZ})
		"sa_pbreak":   # 晶柱环到时碎掉：每根一张碎裂帧条（立起，留原地）
			var big: bool = not d.get("small", false)
			var ps: Array = d.get("posts", [])
			for k in ps.size():
				_up(o, ("pilB%d_brk" if big else "pilS%d_brk") % (k % 3), ps[k], float(ps[k].y) + 1.0)
		"sa_chip":   # 环绕钙晶撞到敌人 / 碎晶片命中：一小团琥珀碎晶（每拍至多 3）
			if _beat_n(o, "chip") >= 3:
				return
			_up(o, "chip", d.at, float(d.get("gy", (d.at as Vector2).y + 16.0)))
		"sa_shot_hit":
			if _beat_n(o, "sh") >= 3:
				return
			var at: Vector2 = d.at
			_up(o, "syrhit" if str(d.get("kind", "")) == "syringe" else "chip", at, at.y + 16.0)
		"sa_mark":   # 晶簇碎片爆开：一圈小晶刺破土 + 碎晶尘环（留原地）
			_up(o, "markb_up", d.at, float((d.at as Vector2).y) + 1.0)
			_gd(o, "markb_gd", d.at)
			R._light(o, (d.at as Vector2) + Vector2(0, -12), 70.0, 0.5, 0.1, p.light)
		"sa_orbbrk":   # 碎晶（平时）：一枚环绕钙晶炸开
			_up(o, "orbbrk", d.at, float((d.at as Vector2).y) + 16.0)
			R._light(o, d.at, 70.0, 0.5, 0.1, p.light)
		"sa_shatter", "sa_slot":   # S3 晶柱被击碎 / 被碰碎（碎裂帧条由晶柱槽状态画）：照地一下 + 少量碎晶颗粒
			if _beat_n(o, "sl") >= 2:
				return
			var at2: Vector2 = d.at
			R._light(o, at2 + Vector2(0, -16), 70.0, 0.45, 0.1, p.light)
			R._grains(o, at2 + Vector2(0, -16), at2.y + 2.0, "shard", 3, {"tier": t, "grain_sz": CHIP_SZ})
		"sa_heal":   # S1 急救 / S2 药物配置（医疗绿，跟着队长）
			if int(d.get("s", 1)) == 2:
				_on_lead(o, "s2_e%d_gd" % maxi(1, t), "gd")
				_on_lead(o, "s2_up", "up")
			else:
				_on_lead(o, "s1_gd", "gd")
				_on_lead(o, "s1_e%d_up" % t, "up")
			R._light(o, g.ppos + Vector2(0, -20), 100.0, 0.5, 0.15, HEAL_LIGHT)
		"sa_hot":   # 持续回复每跳
			_on_lead(o, "hot_tick", "up")
		"sa_calc":   # 钙质化起手：脚下琥珀裂纹 + 外推断续环（留原地）+ 一圈晶片崩起
			_gd(o, "s3cast_gd", d.c)
			_up(o, "s3cast_up", d.c, float((d.c as Vector2).y) + 1.0)
			R._light(o, (d.c as Vector2) + Vector2(0, -16), 200.0, 0.8, 0.15, p.light)
			R._grains(o, (d.c as Vector2) + Vector2(0, -20), float((d.c as Vector2).y) + 2.0, "shard", 8, {"tier": 2, "grain_sz": CHIP_SZ})
		"sa_link":   # 连携「钙质护盾」：队长身周 6 片晶板（前后两张，跟队长）+ 区域里 7 块钙化地面斑（留原地）
			_on_lead(o, "lk_ring_gd", "gd")   # 11-05 用户「护盾会挡住队长」：晶全长在地上，后半圈排在队长身后、前半圈只有脚前小晶尖
			_on_lead(o, "lk_b", "up", -3.0)
			_on_lead(o, "lk_f", "up", 1.0)
			var c: Vector2 = d.c
			var rr: float = float(d.get("r", 150.0))
			for j in 7:
				var off: Vector2 = Vector2.from_angle(j * 2.39996) * rr * (0.25 + 0.55 * fposmod(j * 0.618, 1.0))
				_gd(o, "lk_patch_v%d" % (j % 3), c + off)
			R._light(o, g.ppos + Vector2(0, -20), 110.0, 0.55, 0.15, p.light)
		"shape":   # 碎晶·崩落（每第 3 拳，圆形 src 碎晶）：一圈晶刺往外崩 + 碎晶尘环
			if d.get("circle", false) and str(d.get("src", "")) == "碎晶":
				var c2: Vector2 = d.get("c", o.pos)
				var Rr: int = _near(SHAT2_R, float(d.get("r", 91.0)) * 0.5)
				_up(o, "shat2_r%d_up" % Rr, c2, c2.y + 1.0)
				_gd(o, "shat2_r%d_gd" % Rr, c2)
				R._grains(o, c2 + Vector2(0, -12), c2.y + 2.0, "shard", 5, {"tier": t, "grain_sz": CHIP_SZ})


# ================================================================ 绘制

## 地面层：钙质化区域边、阻挡圈、晶柱墙脚、环绕钙晶影子、贴地件；顺手生成剑气晶刺
func draw_floor(o) -> void:
	if not o.hw.has("sa") or o.pos == Vector2.INF:
		_floor_items(o)
		return
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	var px: float = g.PX
	if float(sa.calc) > 0.0 and g.ppos != Vector2.INF:   # 钙质化区域（跟着队长）：只画边，淡入淡出
		var dur: float = float(sa.calc_b.get("dur", 8.0))
		var al: float = clampf(float(sa.calc) / 0.6, 0.0, 1.0) * clampf((dur - float(sa.calc)) / 0.3, 0.0, 1.0)
		r._draw_strip(cv, "sa_field_gd", r.frame_of(0.0), Pxp._snap(g.ppos + Vector2(0, 4)), false, false, Color(1, 1, 1, al))
	var gr: Dictionary = _sg()._h4_live(o, "verb.guard_ring")
	if not gr.is_empty() and g.ppos != Vector2.INF:   # 阻挡圈：8 段断续暗琥珀弧，每 2 拍转一格
		var rr: float = float(gr.get("r", 62.0)) * o.stat(&"op_range") * 0.5
		var c0: Vector2 = Pxp._snap(g.ppos + Vector2(0, 4))
		var n: int = int(rr * 6.4)
		var bt: int = int(floor(g.t * 15.0))
		var rot: float = float((bt / 2) % 64) / 64.0 * TAU / 8.0
		for q in n:
			var tq: float = float(q) / float(n) * TAU
			var seg: float = fposmod(tq - rot, TAU / 8.0) / (TAU / 8.0)
			if seg > 0.55:
				continue
			var pq := Vector2(roundf(rr * cos(tq)), roundf(rr * sin(tq) * SQ))
			cv.draw_rect(Rect2(c0 + pq * px, Vector2(px, px)), Color(AMB[2], 0.85) if seg < 0.45 else Color(AMB[1], 0.85))
	if not sa.crystals.is_empty():   # 晶柱墙脚：柱间一道断续琥珀细线（看得出哪里挡路）
		var cr: Dictionary = sa.crystals
		if float(cr.b.get("wall", 6.0)) >= 0.0:
			var al2: float = clampf(float(cr.t) / 0.15, 0.0, 1.0)
			var posts: Array = cr.posts
			for k in posts.size():
				var a2: Vector2 = posts[k]
				var b2: Vector2 = posts[(k + 1) % posts.size()]
				var m: int = int(a2.distance_to(b2) / px)
				for i in m:
					if (i + int(floor(g.t * 15.0))) % 4 == 3:
						continue
					var q2: Vector2 = Pxp._snap(a2.lerp(b2, float(i) / float(maxi(1, m))))
					cv.draw_rect(Rect2(q2, Vector2(px, px)), Color(AMB[3] if i % 2 == 0 else AMB[2], al2))
	var ob: Dictionary = _sg()._h4_live(o, "verb.calc_orbs")
	var on: int = _sg()._h4_orb_n(o, ob)
	for k in on:   # 环绕钙晶的影子
		if sa.orb_broken.has(k):
			continue
		var gp: Vector2 = Pxp._snap(_sg()._h4_orb_ground(o, ob, on, k))
		cv.draw_rect(Rect2(gp + Vector2(-px, 0), Vector2(px * 3, px)), Color(SHADOW, 0.7))
	_floor_items(o)
	_qi_spawn(o)


func _floor_items(o) -> void:
	var id: String = str(o.id)
	for it in r.items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			r._draw_strip(o.cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)


## 后期剑气「晶刺地波」：剑气每推进 QI_STEP 在它的地面位置冒一根晶刺（立起件，留原地自己碎掉）。只读 o.vg.qi，进度记在剑气字典的 _pxs
func _qi_spawn(o) -> void:
	var vg = o.get("vg")
	if not (vg is Dictionary) or vg.is_empty():
		return
	var t: int = r.tier(o)
	var id: String = str(o.id)
	for q in vg.get("qi", []):
		var pq: Vector2 = q.p
		if not q.has("_pxs"):
			q["_pxs"] = [pq, 0]
		var st: Array = q._pxs
		var last: Vector2 = st[0]
		var dist: float = last.distance_to(pq)
		while dist >= QI_STEP:
			last = last + (pq - last).normalized() * QI_STEP
			dist -= QI_STEP
			st[1] = int(st[1]) + 1
			var n := 0
			for it in r.items:
				if it.has("qs") and str(it.oid) == id:
					n += 1
			if n >= QI_MAX:
				continue
			var side: Vector2 = (pq - last).orthogonal().normalized() if pq != last else Vector2.ZERO
			var sp: Vector2 = last + side * (4.0 if int(st[1]) % 2 == 0 else -4.0)
			_up(o, "qspk_e%d_v%d" % [t, int(st[1]) % 2], sp, sp.y + 1.0, {"qs": true})
		st[0] = last


## 上层：状态提示照画（护服充能格、晶簇碎片、回流标记），钙化拳的琥珀斑改画成像素碎晶
func draw_over(o) -> void:
	if not o.hw.has("sa") or o.pos == Vector2.INF:
		return
	var sa: Dictionary = o.hw.sa
	_sg()._h4sa_draw_nodes(o, sa)
	_sg()._h4sa_draw_suit(o, sa)
	if sa.slowed.is_empty():
		return
	var cv = o.cv
	var px: float = g.PX
	for s in sa.slowed:   # 精一钙化拳：被打中的敌人身上两粒琥珀碎晶（出现亮一拍，最后 0.4 秒褪掉）
		var e: Dictionary = s.e
		if e.get("dead", false):
			continue
		var left: float = float(s.until) - g.t
		var age: float = g.t - float(s.t0)
		var al: float = clampf(left / 0.4, 0.0, 1.0)
		for qi in 2:
			var sd: float = float(s.seed) + qi * 2.1
			var c: Vector2 = Pxp._snap(e.pos + Vector2(sin(sd) * float(e.r) * 0.55, -float(e.r) * (0.35 + 0.4 * fmod(sd * 0.7, 1.0))))
			var hot: bool = age < 0.14
			cv.draw_rect(Rect2(c, Vector2(px, px)), Color(AMB[6] if hot else AMB[5], al))
			cv.draw_rect(Rect2(c + Vector2(px, 0), Vector2(px, px)), Color(AMB[4] if hot else AMB[3], al))
			cv.draw_rect(Rect2(c + Vector2(0, px), Vector2(px, px)), Color(AMB[2], al))


## 排序项：环绕钙晶、弹体、药物配置光环（精二）
func sort_items(o, out: Array) -> void:
	if not o.hw.has("sa"):
		return
	var sa: Dictionary = o.hw.sa
	var ob: Dictionary = _sg()._h4_live(o, "verb.calc_orbs")
	var on: int = _sg()._h4_orb_n(o, ob)
	for k in on:
		if sa.orb_broken.has(k):
			continue
		var gp: Vector2 = _sg()._h4_orb_ground(o, ob, on, k)
		var hp: Vector2 = Pxp._snap(gp + Vector2(0, -16 + roundf(sin(floor(g.t * 15.0) / 15.0 * 3.0 + k) * 1.0) * 2.0))
		out.append({"sa": "orb", "gp": hp, "skey": gp.y + 1.0, "k": "sa_orb", "ph": k})
	for s in sa.shots:
		out.append({"sa": "shot", "s": s, "skey": (s.pos as Vector2).y + 16.0})
	if float(sa.hot_t) > 0.0 and r.tier(o) >= 2 and g.ppos != Vector2.INF:
		out.append({"sa": "loop", "k": "sa_hot_aura", "gp": Pxp._snap(g.ppos), "skey": g.ppos.y + 2.0})


func draw_rt(ci, it: Dictionary) -> void:
	match str(it.sa):
		"orb", "loop":
			r._draw_strip(ci, str(it.k), r.frame_of(0.0) + int(it.get("ph", 0)), it.gp, false, false)
		"shot":
			var s: Dictionary = it.s
			var d: Vector2 = Vector2.from_angle(float(s.ang))
			var syr: bool = str(s.kind) == "syringe"
			var head: Vector2 = Pxp._snap(s.pos)
			var px: float = g.PX
			var nv := Vector2(-d.y, d.x)
			var bt: int = int(floor(g.t * 15.0))
			for q in (_syr_px() if syr else _shard_px(bt)):
				var p2: Vector2 = Pxp._snap(head - d * float(q[0]) * px + nv * float(q[1]) * px)
				ci.draw_rect(Rect2(p2, Vector2(px, px)), q[2])
			if g.optical_on and r._emit_n < Pxp.EMIT_CAP:
				r._emit_n += 1
				g.glow_next.append([head, px, Color(HEAL[5] if syr else AMB[6], Bal.v("fx/px_plane_emit", 0.8))])


## 同 pxplane_saria_art.syringe()：[沿向 s（往后为正）, 法向 w, 颜色]
func _syr_px() -> Array:
	var out: Array = [[0, 0, WH[6]], [1, 0, WH[4]], [2, 0, WH[3]]]
	for s in range(3, 7):
		out.append([s, 0, HEAL[6] if s in [4, 5] else HEAL[5]])
		out.append([s, 1, WH[5]])
		out.append([s, -1, WH[4]])
	out.append_array([[7, 0, DUST3], [8, 0, DUST3], [8, 1, DUST3], [8, -1, DUST3]])
	return out


## 同 pxplane_saria_art.shard()
func _shard_px(bt: int) -> Array:
	var out: Array = [[0, 0, AMB[6]], [1, 0, AMB[5]], [2, 0, AMB[4]], [1, 1, AMB[3]]]
	for s in range(3, 6):
		if (s + bt) % 3 == 0 and s > 3:
			continue
		out.append([s, 0, AMB[2] if s < 5 else AMB[1]])
	return out


## 晶柱 / 钙质晶簇（data_operator.draw_extra 转来，参与 2.5D 排序）
func draw_extra(o, it: Dictionary) -> void:
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	if str(it.h4) == "calc":
		var sl: Dictionary = sa.slots[int(it.k)]
		var v: int = int(it.k) % 2
		var tt: float = float(sl.t)
		match int(sl.st):
			0:
				r._draw_strip(cv, "sa_cal%d_grow" % v, mini(5, int(tt / 0.4 * 6.0)), Pxp._snap(sl.pos), bool(sl.flip), false)
			1:
				r._draw_strip(cv, "sa_cal%d_idle" % v, r.frame_of(0.0) + int(it.k), Pxp._snap(sl.pos), bool(sl.flip), false)
			2:
				r._draw_strip(cv, "sa_cal%d_brk" % v, mini(4, int(tt / 0.3 * 5.0)), Pxp._snap(sl.pos), bool(sl.flip), false)
		return
	var cr: Dictionary = sa.crystals
	if cr.is_empty():
		return
	var p: Vector2 = Pxp._snap(cr.posts[int(it.k)])
	var nm: String = ("sa_pilS%d" if float(cr.b.get("pr", 14.0)) <= 12.0 else "sa_pilB%d") % (int(it.k) % 3)   # 相邻晶柱换一种晶簇（高矮 / 倾斜不同）
	var t: float = float(cr.t)
	if t < 4.0 / 15.0:
		r._draw_strip(cv, nm + "_rise", int(t * 15.0), p, int(it.k) % 2 == 1, false)
	else:
		r._draw_strip(cv, nm + "_idle", r.frame_of(0.0) + int(it.k), p, int(it.k) % 2 == 1, false)
