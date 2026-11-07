## 归溟幽灵鲨转平面（docs/268，照 docs/246 斯卡蒂的做法）：fx_pxplane.gd 只做分流，这一节的件都在这里。
## 帧条：game/art/fx/pxp/pxp_su_*.png + data/pxp_specter_unchained.json（tools/pxplane_su_art.py 生成，键前缀 su_）。
## 意象：深海 + 替身 + 镰锯（11-05 用户「技能要更突出锯子」）。
##   普攻环斩 = 腰高一圈锯环（前倾锯齿每拍转、出手两拍白热刀头弧扫过，前后半圈分开排序）+ 贴地接触影 + 命中处切向橙色火星；
##     精一 = 起手外圈一道往里收的水纹（卷刃）；精二 = 锯齿甩水珠 + 替身闪现（现身水花 → 三次脉冲环 → 碎成泡沫）。
##   S1 = 光柱落下 + 符环（精一贴地不规则水花 + 鳍尖破水、精二两片鲨鳍绕身），期间深海暗焰；S2 = 横向白闪 + 冒泡，期间身后两道替身残影（替身青，与本体分色），
##     精二环斩时朝最近的敌人一记鲨口咬合；结束倒下 = 水花里替身起身，替身光环每秒一圈；S3 = 起手大浪绕身，期间重锯（齿尖橙热、火星多、地上切向锯痕）。
##   分支：双重回转 = 小一号、抬高一截的反转锯（和主锯环错位交叠）；血色潮痕 = 深海青潮痕（只画边）；锯鸣 = 旋锯（青白锯环 + 内圈回声）；共振 = 水刃 + 收尾震地；困兽 = 追加一圈 + 白环。
##   late_shape 剑气 = 横飞的锯盘；连携 l_specter = 替身残影冲过 → 带锯齿的斩线 → 地上一道鲨鳍划水的 V 形水痕。
## 只画：读玩法状态（o.hw.sp、o.vg.qi），画面计时 / 火星 / 残影快照都存在 fx_pxplane 实例的 meta「su」里；随机只用 g.vrng。红色只给危险：原 S3 / 困兽 / 锯鸣的红改成橙热 / 青白。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const Bal = preload("res://scripts/core/balance.gd")
const SY := 0.72
const RING_R := {"n": [51, 58, 66], "w": [51, 58, 66], "d": [36, 41, 46, 53], "s": [66, 76, 88], "h": [76, 88, 100]}
const SPK := [Color("#fff3cc"), Color("#ffd27a"), Color("#ffa04a"), Color("#e3692a"), Color("#8a3d1d")]
const GH := [Color("#0e3846"), Color("#2a7c96"), Color("#6ccde4"), Color("#c6f4ff")]
const AB := [Color("#060a15"), Color("#0d1832"), Color("#172f5e"), Color("#234d94"), Color("#3a77c2"), Color("#78afe6"), Color("#c4e2fa"), Color("#ffffff")]
const GHOST := Color(0.45, 0.95, 1.15)
const SPARK_MAX := 72
const ECHO_KEEP := 0.3
const EMIT_CAP := 360   # 同 fx_pxplane.EMIT_CAP（整队每帧送进发光层的点数上限）


static func _st(r) -> Dictionary:
	if not r.has_meta("su"):
		r.set_meta("su", {"sparks": [], "t_last": -1.0, "echo": [], "links": [], "cuts": [], "qi_t": {}})
	return r.get_meta("su")


static func _bucket(v: float, opts: Array) -> int:
	return PxU.nearest(opts, v)


# ================================================================ 事件（fx_pxplane.ev 转来）

static func ev(r, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = r.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用：事件的游戏时间
		print("PXPLOG su %s %s %.3f" % [kind, str(d.get("kind", d.get("i", ""))), g.t])
	var id: String = str(o.id)
	match kind:
		"su_spin":
			var k: int = int(d.get("kind", 0))
			var rr: float = float(d.get("r", 102.0))
			var heavy: bool = bool(d.get("heavy", false))
			var rev: bool = bool(d.get("rev", false))
			var es: Array = d.get("es", [])
			var sty := "n"
			if k == 1:   # 双重回转：小一号、抬高一截的反转锯，和还在转的主锯环错位交叠（11-05 用户「和旋锯拉开」）
				sty = "d"
				rr *= 0.7
			elif k == 2:
				sty = "s"
			elif heavy:
				sty = "h"
			elif t >= 2:
				sty = "w"
			_ring(r, o, sty, rr, rev, raw)
			if raw:
				return
			if sty == "h":
				r._push({"k": "su_gouge_r%d_gd" % _bucket(rr / 2.0, RING_R.h), "t0": g.t, "gp": r._snap(o.pos), "flip": rev, "ly": "gd", "oid": id})
			if k != 1:
				_hit_sparks(r, o, es, rev, 8 if heavy else (2 if k == 2 else 5), heavy)   # 火星（docs/270 §3：每圈 3–8 颗、头 2×2 美术像素）
			if k == 0 and t >= 2 and o.s_t.size() > 1 and o.s_t[1] > 0.0 and not es.is_empty():
				_bite(r, o, es)   # S2 精二：鲨口咬合（11-05 用户：触须换成鲨鱼意象）
			var n: int = mini(es.size(), 3 if k == 2 else 6)
			if not es.is_empty():
				# 命中：ink 水滴 + 一盏照地灯（普攻 110 / 0.45；重锯按爆发档 190 / 0.75；旋锯每段 90 / 0.38）
				r._burst(o, R, p, o.pos + Vector2(0, -14), o.pos.y + 2.0, es, 2 + n, 190.0 if heavy else (90.0 if k == 2 else 110.0), 0.75 if heavy else (0.38 if k == 2 else 0.45))
				if heavy and r.mode() == 1:
					R._grains(o, es[0].pos + Vector2(0, -8), float(es[0].pos.y) + 2.0, "rock", 4, {"tier": 2})
		"su_windup":   # 精一卷刃：起手外圈往里收的水纹
			if t >= 1 and not raw:
				var cr: float = 160.0 * o.stat(&"op_range") / 2.0
				r._push({"k": "su_curl_r%d_gd" % _bucket(cr, [80, 90]), "t0": g.t, "gp": r._snap(o.pos), "flip": false, "ly": "gd", "oid": id, "fo": Vector2.ZERO})
		"skill":
			var i: int = int(d.get("i", -1))
			if raw:
				return
			if i == 0:   # S1：光柱 + 符环（+ 精一贴地水花）
				_up(r, o, "su_s1col_up", o.pos, -2.0, true)
				_gd(r, o, "su_s1rune_gd", o.pos, true)
				if t >= 1:
					_up(r, o, "su_s1splash_up", o.pos, 3.0, true)   # 11-05 用户「水冠有点奇怪」：改成贴地不规则水花 + 鳍尖破水
					_gd(r, o, "su_s1splash_gd", o.pos, true)
				if r.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -6), o.pos.y + 2.0, "ink", 6, {"tier": t})
				R._light(o, o.pos + Vector2(0, -30), 160.0, 0.7, 0.15, p.light)
			elif i == 1:   # S2：横向白闪 + 冒泡
				_up(r, o, "su_s2cast_up", o.pos, 2.0, true)
				_gd(r, o, "su_s2cast_gd", o.pos, true)
				if r.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -8), o.pos.y + 2.0, "ink", 6, {"tier": t})
				R._light(o, o.pos, 140.0, 0.65, 0.14, p.light)
			elif i == 2:   # S3：大浪绕身
				var sk: float = 76.0 * 2.0 * SY * 0.8
				_up(r, o, "su_s3wave_bk_up", o.pos, -sk, true)
				_up(r, o, "su_s3wave_fr_up", o.pos, sk, true)
				_gd(r, o, "su_s3wave_gd", o.pos, false)
				if r.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "ink", 8, {"tier": 2})
				R._light(o, o.pos + Vector2(0, -10), 210.0, 0.8, 0.15, p.light)
		"su_echo":   # 困兽：追加一圈的白环
			if not raw:
				_gd(r, o, "su_echo_gd", o.pos, true)
		"su_quake":   # 锯鸣·共振收尾震地
			if not raw:
				_gd(r, o, "su_quake_gd", o.pos, false)
				_up(r, o, "su_quake_up", o.pos, 2.0, false)
				if r.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -12), o.pos.y + 2.0, "rock", 6, {"tier": 1})
				R._light(o, o.pos, 170.0, 0.55, 0.15, p.light)
		"su_fall":   # S2 结束：本体倒下，水花里替身起身
			if not raw:
				var at: Vector2 = d.get("at", o.pos)
				_up(r, o, "su_dollin_up", at, 1.0, false)
				R._light(o, at + Vector2(0, -20), 120.0, 0.45, 0.12, p.light)
		"su_dpulse":   # 天赋替身光环：每秒一圈
			if not raw:
				_gd(r, o, "su_dollpulse_gd", d.get("at", o.pos), false)
		"su_back":   # 替身归队：碎成泡沫
			if not raw:
				_up(r, o, "su_dollout_up", d.get("at", o.pos), 1.0, false)
		"su_flash":   # 精二替身闪现：现身水花；碎成泡沫排在连斩之后（未来的 t0，到点才画）
			if not raw:
				var c: Vector2 = d.get("c", o.pos)
				_up(r, o, "su_flin_up", c, 24.0, false)
				var it := {"k": "su_flout_up", "t0": g.t + float(d.get("ap", 0.25)) + float(d.get("sw", 0.3)), "gp": r._snap(c), "flip": false, "ly": "up", "oid": id, "sk": 24.0}
				r._push(it)
		"su_fpulse":   # 替身法术脉冲（以替身为心外扩的断续环）
			if not raw:
				var c2: Vector2 = d.get("c", o.pos)
				_gd(r, o, "su_flpulse_gd", c2, false)
				r._burst(o, R, p, c2 + Vector2(0, -16), c2.y, d.get("es", []), 3, 110.0, 0.35)
		"su_lgo":   # 连携 l_specter：替身残影冲过（0.2 秒）
			var s := _st(r)
			s.links.append({"fp": d.fp, "tp": d.tp, "t0": g.t, "T": float(d.get("T", 0.2)), "st": o.anim_state(), "oid": id})
			if s.links.size() > 4:
				s.links.pop_front()
		"su_lcut", "su_combo":   # 连携斩线（旧连携技三斩也用这一道，短一些）
			var s2 := _st(r)
			var fp: Vector2 = d.get("fp", o.pos)
			var tp: Vector2 = d.get("tp", o.pos)
			s2.cuts.append({"fp": fp, "tp": tp, "t0": g.t, "oid": id})
			if s2.cuts.size() > 6:
				s2.cuts.pop_front()
			if r.mode() == 1:
				for q in 4:
					var pp: Vector2 = fp.lerp(tp, 0.3 + 0.18 * q)
					_sparks_at(r, id, pp + Vector2(0, -10), pp.y + 4.0, Vector2.UP, 4, 1.0, PI * 0.45)
				R._light(o, fp.lerp(tp, 0.6), 150.0, 0.5, 0.15, p.light)
				r._burst(o, R, p, fp.lerp(tp, 0.5), tp.y, d.get("es", []), 4, 110.0, 0.35)


## 锯环：前后半圈两件（挂在人身上，跟人走）+ 贴地接触影；同一名干员只留最新一圈 + 正在收的一圈
static func _ring(r, o, sty: String, rw: float, rev: bool, raw: bool) -> void:
	var g = r.g
	var id: String = str(o.id)
	var R: int = _bucket(rw / 2.0, RING_R[sty])
	var k: String = "su_saw_%s_r%d" % [sty, R]
	if raw:   # 旧做法对照：整张盖在上面、小数缩放
		var sc: float = g.PX * 1.3 * (rw / 2.0) / float(R)
		r._push({"k": k + "_bk_up", "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": sc, "oid": id})
		r._push({"k": k + "_fr_up", "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": sc, "oid": id})
		return
	var tl: Array = []
	for it in r.items:
		if str(it.oid) == id and it.get("su_ring", false):
			if not tl.has(float(it.t0)):
				tl.append(float(it.t0))
	if tl.size() >= 2:
		tl.sort()
		var keep_t: float = float(tl[tl.size() - 1])
		r.items = r.items.filter(func(it): return not (it.get("su_ring", false) and str(it.oid) == id and float(it.t0) < keep_t))
	var sk: float = float(R) * 2.0 * SY * 0.8
	var gp: Vector2 = r._snap(o.pos)
	r._push({"k": k + "_bk_up", "t0": g.t, "gp": gp, "flip": rev, "ly": "up", "oid": id, "su_ring": true, "fo": Vector2.ZERO, "sk": -sk})
	r._push({"k": k + "_fr_up", "t0": g.t, "gp": gp, "flip": rev, "ly": "up", "oid": id, "su_ring": true, "fo": Vector2.ZERO, "sk": sk})
	if not r._meta(k + "_gd").is_empty():
		r._push({"k": k + "_gd", "t0": g.t, "gp": gp, "flip": rev, "ly": "gd", "oid": id, "su_ring": true, "fo": Vector2.ZERO})


## S2 精二鲨口：朝最近的那只，上下两道锯齿颌弧从张开到合拢（帧条按 5 个平面角预生成、另一半翻转；挂在她身上）
static func _bite(r, o, es: Array) -> void:
	var best: Dictionary = es[0]
	for e in es:
		if e.pos.distance_squared_to(o.pos) < best.pos.distance_squared_to(o.pos):
			best = e
	var ang: float = (best.pos - o.pos).angle()
	var dk: Array = r.pick_dir(ang)
	r._push({"k": "su_s2bite_up_d%d" % int(dk[0]), "t0": r.g.t, "gp": r._snap(o.pos), "flip": dk[1], "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO, "sk": sin(ang) * 46.0})


static func _up(r, o, k: String, at: Vector2, sk: float, follow: bool) -> void:
	var it := {"k": k, "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": "up", "oid": str(o.id), "sk": sk}
	if follow:
		it["fo"] = at - o.pos
	r._push(it)


static func _gd(r, o, k: String, at: Vector2, follow: bool) -> void:
	var it := {"k": k, "t0": r.g.t, "gp": r._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	r._push(it)


# ================================================================ 火星（橙色，切向甩出、受重力、落地熄灭；只画，随机只用 g.vrng）

## 一圈的火星总数 n（docs/270 §3：3–8 颗）分给最近的几只，顺切线甩出
static func _hit_sparks(r, o, es: Array, rev: bool, n: int, heavy: bool) -> void:
	if r.mode() != 1 or es.is_empty():
		return
	var g = r.g
	var lst: Array = es.duplicate()
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	var m: int = mini(4 if heavy else 3, lst.size())
	var s := _st(r)
	for q in n:
		var e: Dictionary = lst[q % m]
		var rd: Vector2 = e.pos - o.pos
		var tg: Vector2 = Vector2(-rd.y, rd.x).normalized() if rd.length() > 1.0 else Vector2.RIGHT
		if rev:
			tg = -tg
		var at: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		if s.sparks.size() >= SPARK_MAX:
			s.sparks.pop_front()
		var a: float = tg.angle() + g.vrng.randf_range(-0.5, 0.5)
		var sp: float = g.vrng.randf_range(150.0, 260.0) * (1.25 if heavy else 1.0)
		var v := Vector2(cos(a) * sp, sin(a) * sp * 0.8 - g.vrng.randf_range(40.0, 120.0)) + rd.normalized() * 40.0
		s.sparks.append({"p": at, "v": v, "gy": float(e.pos.y) + 2.0, "age": 0.0, "life": g.vrng.randf_range(0.28, 0.42), "oid": str(o.id)})


static func _sparks_at(r, oid: String, at: Vector2, gy: float, dir: Vector2, n: int, k: float, spread: float) -> void:
	var g = r.g
	var s := _st(r)
	for q in n:
		if s.sparks.size() >= SPARK_MAX:
			s.sparks.pop_front()
		var a: float = dir.angle() + g.vrng.randf_range(-spread, spread)
		var sp: float = g.vrng.randf_range(140.0, 240.0) * k
		s.sparks.append({"p": at, "v": Vector2(cos(a), sin(a)) * sp, "gy": gy, "age": 0.0, "life": g.vrng.randf_range(0.22, 0.38), "oid": oid})


static func _spark_step(r) -> void:
	var g = r.g
	var s := _st(r)
	var dt: float = 0.0 if float(s.t_last) < 0.0 else clampf(g.t - float(s.t_last), 0.0, 0.1)
	if dt <= 0.0 and float(s.t_last) >= 0.0:
		return
	s.t_last = g.t
	if dt <= 0.0:
		return
	var keep: Array = []
	for q in s.sparks:
		q.age = float(q.age) + dt
		q.p = (q.p as Vector2) + (q.v as Vector2) * dt
		var v: Vector2 = q.v
		v.y += 760.0 * dt
		q.v = v * maxf(0.0, 1.0 - 2.2 * dt)
		if float(q.age) < float(q.life) and (q.p as Vector2).y <= float(q.gy):
			keep.append(q)
	s.sparks = keep


static func _draw_sparks(r, o, cv) -> void:
	var g = r.g
	var px: float = g.PX
	var id: String = str(o.id)
	for q in _st(r).sparks:
		if str(q.oid) != id:
			continue
		var a: float = float(q.age) / maxf(0.01, float(q.life))
		var ci: int = 0 if a < 0.2 else (1 if a < 0.45 else (2 if a < 0.75 else 3))
		var v: Vector2 = q.v
		var p: Vector2 = r._snap(q.p)
		var tail: Vector2 = r._snap((q.p as Vector2) - v.normalized() * px)
		cv.draw_rect(Rect2(tail, Vector2(px, px)), SPK[mini(4, ci + 1)])
		var hs: float = px * (2.0 if ci <= 1 else 1.0)   # 头 2×2 美术像素（热的两阶），冷了缩成 1 格
		cv.draw_rect(Rect2(p, Vector2(hs, hs)), SPK[ci])
		if ci <= 1 and g.optical_on and r._emit_n < EMIT_CAP:
			r._emit_n += 1
			g.glow_next.append([p, px, Color(SPK[ci].r, SPK[ci].g, SPK[ci].b, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])


# ================================================================ 绘制

## 地面层：贴地件、潮痕、锯鸣点、连携地痕
static func floor_layer(r, o) -> void:
	var g = r.g
	var cv = o.cv
	var id: String = str(o.id)
	for it in r.items_for(id):
		if str(it.ly) == "gd":
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, true)
	if not o.hw.has("sp"):
		return
	var sp: Dictionary = o.hw.sp
	for rg in sp.get("rings", []):   # 血色潮痕：循环帧条（只画边），最后 0.3 秒隔拍闪掉
		if float(rg.t) < 0.3 and (int(floor(g.t * 15.0)) & 1) == 1:
			continue
		r._draw_strip(cv, "su_tide_r%d_gd" % _bucket(float(rg.r) / 2.0, [51, 58, 66, 76, 88, 100]), r.frame_of(0.0), r._snap(rg.pos), false, false)
	_draw_hum(r, o, sp, cv)
	_draw_cut_scars(r, o, cv)


## 锯鸣点（状态提示）：脚下一圈 max 个小点，攒满时青白两色按拍闪（原来攒满变红，红只给危险）
static func _draw_hum(r, o, sp: Dictionary, cv) -> void:
	var hm = o.B.get("attack", {}).get("saw_hum", null)
	if not (hm is Dictionary) or o.pos == Vector2.INF or int(sp.get("hum", 0)) <= 0 or bool(sp.get("hum_on", false)):
		return
	var g = r.g
	var mx: int = int(hm.get("max", 12))
	var n: int = int(sp.hum)
	var full: bool = n >= mx
	var px: float = g.PX
	for q in mx:
		var an: float = TAU * q / float(mx) - PI * 0.5
		var c: Color = ((GH[3] if (int(floor(g.t * 7.5)) & 1) == 0 else GH[2]) if full else (AB[6] if q < n else AB[2]))
		cv.draw_rect(Rect2(r._snap(o.pos + Vector2(cos(an) * 30.0, 6.0 + sin(an) * 30.0 * SY)), Vector2(px, px)), c)


## 上层：火星、连携斩线（前 3 拍）；旧做法对照（2）的整张贴图
static func over(r, o) -> void:
	var g = r.g
	var cv = o.cv
	_spark_step(r)
	if r.mode() == 2:
		var id: String = str(o.id)
		for it in r.items_for(id):
			if str(it.ly) == "raw":
				r._draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8)), it.gp, float(it.rot), float(it.sc))
		return
	if r.mode() != 1:
		return
	_draw_sparks(r, o, cv)
	_draw_cuts(r, o, cv)
	_qi_sparks(r, o)


## 连携斩线：出手第 0 拍白芯 + 两侧替身青 + 一侧锯齿尖，第 1 / 2 拍收成青，之后地上冷成暗痕（地面层画）
static func _draw_cuts(r, o, cv) -> void:
	var g = r.g
	var id: String = str(o.id)
	var s := _st(r)
	s.cuts = s.cuts.filter(func(c): return g.t - float(c.t0) < 1.0)
	for c in s.cuts:
		if str(c.oid) != id:
			continue
		var f: int = r.frame_of(float(c.t0))
		if f < 0 or f > 2:
			continue
		var cols: Array = [[Color.WHITE, GH[2]], [GH[3], GH[2]], [GH[2], GH[1]]][f]
		_cut_line(r, cv, c.fp, c.tp, cols[0], cols[1], true, f == 0)


## 斩线之后地上留一道鲨鳍划水的 V 形水痕（11-05 用户「拿鲨鱼来点意象」）：尖在斩线末端，往回张开；近尖白沫、远处暗；0.9 秒隔拍散掉
static func _draw_cut_scars(r, o, cv) -> void:
	var g = r.g
	var id: String = str(o.id)
	var px: float = g.PX
	for c in _st(r).cuts:
		if str(c.oid) != id:
			continue
		var f: int = r.frame_of(float(c.t0))
		var u: float = g.t - float(c.t0)
		if f < 1 or u > 0.9 or (u > 0.5 and (f & 1) == 1):
			continue
		var a: Vector2 = (c.fp as Vector2) + Vector2(0, 2)
		var b: Vector2 = (c.tp as Vector2) + Vector2(0, 2)
		var L: float = a.distance_to(b)
		if L < 4.0:
			continue
		var d: Vector2 = (b - a) / L
		var nv := Vector2(-d.y, d.x * SY)
		var n: int = int(L / px)
		for i in n + 1:
			var s: float = float(i) * px   # 离尖的距离
			var k: float = s / L
			if (i % 3) == 2 or k > 0.85:
				continue
			var cc: Color = Color.html("#e6f3ff") if k < 0.2 else (AB[5] if k < 0.45 else AB[3])
			if u > 0.5:
				cc = AB[4] if k < 0.3 else AB[2]
			for sd in [-1.0, 1.0]:
				cv.draw_rect(Rect2(r._snap(b - d * s + nv * sd * s * 0.16), Vector2(px, px)), cc)


static func _cut_line(r, cv, a: Vector2, b: Vector2, core: Color, side: Color, teeth: bool, emit: bool) -> void:
	var g = r.g
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var n: int = int(L / px)
	if n <= 0:
		return
	var d: Vector2 = (b - a) / L
	var nv := Vector2(-d.y, d.x)
	var ne: int = 0
	for i in n + 1:
		var u: float = float(i) / float(n)
		var w: float = 1.0 - absf(u - 0.6) / 0.6
		var x: Vector2 = a + d * float(i) * px
		if w > 0.15:
			var p: Vector2 = r._snap(x)
			cv.draw_rect(Rect2(p, Vector2(px, px)), core)
			if emit and (i & 1) == 0 and ne < 40 and g.optical_on and r._emit_n < EMIT_CAP:
				ne += 1
				r._emit_n += 1
				g.glow_next.append([p, px, Color(1, 1, 1, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])
		if side.a > 0.0 and w > 0.35:
			cv.draw_rect(Rect2(r._snap(x + nv * px), Vector2(px, px)), side)
			cv.draw_rect(Rect2(r._snap(x - nv * px), Vector2(px, px)), side)
		if teeth and side.a > 0.0 and i % 6 == 0 and u > 0.1 and u < 0.95:
			for k in [2, 3]:
				cv.draw_rect(Rect2(r._snap(x + nv * px * float(k) + d * px * float(k - 2)), Vector2(px, px)), side)


## 剑气锯盘：精一起尾部甩火星（每拍一颗）
static func _qi_sparks(r, o) -> void:
	if r.tier(o) < 1 or not (o.get("vg") is Dictionary) or o.vg.is_empty():
		return
	var g = r.g
	var s := _st(r)
	var tk: int = int(floor(g.t * 15.0))
	if int(s.qi_t.get(str(o.id), -1)) == tk:
		return
	s.qi_t[str(o.id)] = tk
	var nq: int = 0
	for q in o.vg.get("qi", []):
		nq += 1
		if nq > 4:
			break
		var v: Vector2 = q.v
		_sparks_at(r, str(o.id), (q.p as Vector2) + Vector2(0, -12) - v.normalized() * 10.0, float((q.p as Vector2).y) + 2.0, -v.normalized() + Vector2(0, -0.4), 1, 0.5, 0.5)


# ================================================================ 排序项（world._sorted_fast，kind 7）

static func sort_items(r, o, out: Array) -> void:
	var g = r.g
	var t: int = r.tier(o)
	var away: bool = o.hw.has("sp") and float(o.hw.sp.get("doll_t", 0.0)) > 0.0
	var gp: Vector2 = r._snap(o.pos)
	var s := _st(r)
	# 替身残影快照（S2 期间）：每帧记下位置与当前帧，留 0.3 秒
	var echo: Array = s.echo
	var s2: bool = o.s_t.size() > 1 and o.s_t[1] > 0.0 and not away
	if s2:
		echo.append([g.t, o.pos, o.anim_state()])
	while not echo.is_empty() and (g.t - float(echo[0][0]) > ECHO_KEEP or not s2):
		echo.pop_front()
	if not away:
		if o.s_t[0] > 0.0:   # S1 期间：深海暗焰（+ 精二鲨鳍，前后半圈）
			out.append({"surt": "loop", "k": "su_s1aura_up", "gp": gp, "skey": gp.y + 1.0})
			if t >= 2:
				out.append({"surt": "loop", "k": "su_s1fin_bk_up", "gp": gp, "skey": gp.y - 30.0})
				out.append({"surt": "loop", "k": "su_s1fin_fr_up", "gp": gp, "skey": gp.y + 30.0})
		if s2:
			for lg in [[0.24, 0.3], [0.12, 0.5]]:
				var snap: Array = _echo_at(echo, g.t - float(lg[0]))
				if not snap.is_empty() and not (snap[2] as Dictionary).is_empty() and (snap[1] as Vector2).distance_to(o.pos) > 6.0:
					out.append({"surt": "ghost", "o": o, "st": snap[2], "p": snap[1], "a": float(lg[1]), "skey": (snap[1] as Vector2).y - 0.5})
	# 连携：替身残影冲过（3 道，按冲刺进度排开）
	s.links = s.links.filter(func(L): return g.t - float(L.t0) < float(L.T) + 0.05)
	for L in s.links:
		if str(L.oid) != str(o.id):
			continue
		var u: float = (g.t - float(L.t0)) / maxf(0.01, float(L.T))
		if u < 0.0 or u > 1.0:
			continue
		for gi in 3:
			var kk: float = clampf(u - float(gi) * 0.18, 0.0, 1.0)
			var q: Vector2 = (L.fp as Vector2).lerp(L.tp, kk)
			out.append({"surt": "ghost", "o": o, "st": L.st, "p": q, "a": [0.7, 0.45, 0.22][gi], "skey": q.y})
	if o.hw.has("sp"):   # 锯鸣·共振的水刃
		for bl in o.hw.sp.get("blades", []):
			var dk: Array = r.pick_dir((bl.dir as Vector2).angle())
			var bp: Vector2 = r._snap((bl.pos as Vector2) + Vector2(0, 8))
			out.append({"surt": "strip", "k": "su_blade_up_d%d" % int(dk[0]), "gp": bp, "flip": dk[1], "skey": bp.y})
	if o.get("vg") is Dictionary and not o.vg.is_empty():   # late_shape 剑气 = 锯盘
		var nq: int = 0
		for q in o.vg.get("qi", []):
			nq += 1
			if nq > 8:
				break
			var qp: Vector2 = r._snap(q.p)
			out.append({"surt": "strip", "k": "su_qi_e%d_up" % t, "gp": qp, "flip": false, "skey": qp.y})


static func _echo_at(echo: Array, tt: float) -> Array:
	var best: Array = []
	for e in echo:
		if float(e[0]) <= tt:
			best = e
	return best


static func draw_rt(r, ci, it: Dictionary) -> void:
	match str(it.surt):
		"loop":
			r._draw_strip(ci, str(it.k), r.frame_of(0.0), it.gp, false, false)
		"strip":
			r._draw_strip(ci, str(it.k), r.frame_of(0.0), it.gp, bool(it.get("flip", false)), false)
		"ghost":   # 替身残影：本体那一帧按替身青乘色 + 透明度（和本体分色）
			var o = it.o
			var st: Dictionary = it.st
			if st.is_empty() or st.get("tex") == null or not is_instance_valid(o):
				return
			var p: Vector2 = it.p
			o.draw_sprite_at(p + Vector2(o.foot_dx(st), 0), bool(st.get("flip", false)), Color(GHOST.r, GHOST.g, GHOST.b, float(it.a)),
				int(st.get("frame", 0)), st.tex, int(st.get("hf", 1)), o.foot_off(st.tex, str(st.get("kind", ""))))
