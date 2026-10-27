extends RefCounted
## 可见成长藏品（docs/163，10-27 用户拍板 §9）：藏品效果里 {"type": "growth", "kind": …} 的运行时。
##   scatter  远程普攻多射 1 发小弹，射向另一名敌人（#58 银餐叉，eps 0.25）
##   burst    远程普攻后 burst_gap 秒沿同一方向补射 1 发（#59 损坏的左轮弹巢，eps 0.35）
##   qi       近战普攻额外射出 1 道剑气（#63 锈蚀刀片 mult 0.35 / hits 1；#56 老近卫军之锋 mult 0.6 / hits 2）
##   range    近战攻击范围 +value（#64 赶车夫的长鞭），持有其他攻击范围藏品（#81 / #140）时按层递减
##   summon_n 召唤物 +1 副体（#129 散轶诗简）：维什戴尔魂灵之影；Mon3tr 例外不 +1
##   summon_size  召唤物体型 / 限时召唤物持续时间（#130 衍生者终端-超级改）
## 叠层（§2.2）：同一类的所有层（藏品等级 × 件数）按 eps 从大到小排（与获得顺序无关，同 seed 可复现），
## 第 i 层权重 count_decay^(i-1)（数量）或 size_decay^(i-1)（尺寸）。额外数量 E 的小数部分进每名干员的累加器，满 1 多一发（不取随机数）。
## 伤害预算（§2.3，实现取舍见 docs/163 §11）：主弹不削；额外弹每发 = 普攻参考伤害 × (T − 1) / E，T = 1 + Σ eps_i·w_i，所以普攻总伤 ×T；
## 没有普攻弹体的远程干员改为本人作用域伤害 ×T（refresh 里挂 stats 来源 "vgrowth"）。
## 玩法随机：不用。全部状态在 o.vg（每名干员）与 g.rfx.lv（藏品等级）里。

const Bal = preload("res://scripts/core/balance.gd")
const SwordEase = preload("res://scripts/characters/blocks/sword_ease.gd")   # 剑气非线性速度（10-27）

## 读 op_shots 之外的远程普攻形状（cmd_role 同一张表）
const RANGED_SHAPES := ["projectile", "shell", "bolt", "cannon", "point_aoe", "foxfire", "lantern"]
## 有自己剑气的近战干员：额外剑气扇形错开 qi_fan_deg，不叠第二套（§4.2）
const OWN_QI := ["lappland", "skadi"]
## 数量类不给 +1 的召唤物（§9 第 4 问：Mon3tr 例外，体型 + 时长照常）
const NO_SUB_KINDS := ["mon3tr"]
## 范围类的旧藏品（与 #64 共用递减曲线：它们算在前面的层）
const RANGE_RELICS := ["81", "140"]
const SHOT_Y := -18.0        # 弹体画在脚底上方（同能天使 EXU_AIM_Y 的量级）
const QI_PROJ := "proj_lappland_sword"   # 剑气复用拉普兰德剑气帧条，按干员代表色程序重染（§9 第 3 问）

static var _ck: Array = []   # [rfx 实例, 版本号, 旋钮]
static var _cv: Dictionary = {}


static func kn(k: String, d: float) -> float:
	return Bal.v("vgrowth/" + k, d)


## 同屏上限：按画质档 高 / 中 / 低 取 [0] / [1] / [2]（§6，起点值）
static func cap_of(k: String, dflt: int) -> int:
	var arr = Bal.sec("vgrowth").get(k, [])
	var i: int = {"high": 0, "mid": 1, "low": 2}.get(quality(), 0)
	if arr is Array and arr.size() > i:
		return int(arr[i])
	return dflt


## 生效中的画质档（autoload Cfg；核心契约测试没有 autoload 时按 high）
static func quality() -> String:
	var ml = Engine.get_main_loop()
	var c = ml.root.get_node_or_null("Cfg") if ml is SceneTree else null
	return str(c.quality) if c != null else "high"


# ---------------------------------------------------------------- 层数与曲线

## 当前持有的可见成长效果汇总（按 g.rfx.lv 缓存；藏品变化时 rfx.vg_ver 自增）
static func summary(g) -> Dictionary:
	var rf = g.get("rfx")
	if rf == null:
		return {}
	var key := [rf, int(rf.get("vg_ver")), Bal.v("relic/visible_growth", 1.0)]
	if key == _ck:
		return _cv
	_ck = key
	_cv = compute(rf.lv, rf.db)
	return _cv


## 纯函数（测试直接调）：lv = {藏品 id: 等级}，db = relic_db
static func compute(lv: Dictionary, db) -> Dictionary:
	var cd: float = kn("count_decay", 0.7)
	var sd: float = kn("size_decay", 0.8)
	var ranged: Array = []    # [eps, kind]
	var qi: Array = []        # [mult, hits]
	var rng_v: Array = []     # #64 的每层基础值
	var other_range := 0
	var sum_n := 0
	var size_l: Array = []    # [size, life]
	for id in lv:
		var n: int = int(lv[id])
		if n <= 0:
			continue
		if str(id) in RANGE_RELICS:
			other_range += n
		for ef in db.get_relic(str(id)).get("effects", []):
			if not (ef is Dictionary) or str(ef.get("type", "")) != "growth":
				continue
			for _i in n:
				match str(ef.get("kind", "")):
					"scatter", "burst":
						ranged.append([float(ef.get("eps", 0.2)), str(ef.kind)])
					"qi":
						qi.append([float(ef.get("mult", 0.35)), int(ef.get("hits", 1))])
					"range":
						rng_v.append(float(ef.get("value", 0.18)))
					"summon_n":
						sum_n += 1
					"summon_size":
						size_l.append([float(ef.get("size", 0.15)), float(ef.get("life", 0.2))])
	var out := {"e_scatter": 0.0, "e_burst": 0.0, "e_shots": 0.0, "t_shots": 1.0, "e_qi": 0.0, "qi_mult": 0.0, "qi_hits": 1,
		"range": 0.0, "sub_e": 0.0, "sub_n": 0, "size": 1.0, "life": 1.0}
	ranged.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for i in ranged.size():
		var w: float = pow(cd, i)
		out["e_" + str(ranged[i][1])] += w
		out.e_shots += w
		out.t_shots += float(ranged[i][0]) * w
	qi.sort_custom(func(a, b): return a[0] > b[0])
	for i in qi.size():
		out.e_qi += pow(cd, i)
	if not qi.is_empty():
		out.qi_mult = float(qi[0][0])
		out.qi_hits = int(qi[0][1])
	rng_v.sort()
	rng_v.reverse()
	for i in rng_v.size():
		out.range += rng_v[i] * pow(sd, other_range + i)
	for i in sum_n:
		out.sub_e += pow(cd, i)
	out.sub_n = int(floor(out.sub_e + 1e-6))
	size_l.sort_custom(func(a, b): return a[0] > b[0])
	for i in size_l.size():
		out.size += float(size_l[i][0]) * pow(sd, i)
		out.life += float(size_l[i][1]) * pow(sd, i)
	return out


## 藏品 / 编队变化后：重挂属性来源 "vgrowth"（近战范围、没有普攻弹体的远程干员的伤害 ×T）
static func refresh(g) -> void:
	if g.stats == null:
		return
	var s := summary(g)
	if s.is_empty():
		return
	g.stats.remove_source("vgrowth")
	if s.range > 0.0:
		g.stats.add(&"op_range", "add", s.range, "vgrowth", "range:近战")
	if s.e_shots > 0.0 and g.get("squad") != null:
		for o in g.squad.ops:
			if o.range_cls() == "远程" and not shot_eater(o):
				g.stats.add(&"dmg", "mult", s.t_shots, "vgrowth", "op:" + str(o.id))
	g.sync_stats()


# ---------------------------------------------------------------- 干员判定与参考伤害

static func _atk(o) -> Dictionary:
	return o.cur_attack() if o.has_method("cur_attack") else {}


## 吃「多一发」：普攻是远程弹体形状
static func shot_eater(o) -> bool:
	if not o.has_method("cur_attack"):
		return false
	return str(o.B.get("attack", {}).get("shape", "")) in RANGED_SHAPES


## 吃剑气：近战职业、普攻是近战形状（不是支援 / 远程弹体）
static func qi_eater(o) -> bool:
	if not o.has_method("cur_attack") or o.range_cls() != "近战":
		return false
	var sh: String = str(o.B.get("attack", {}).get("shape", ""))
	return sh != "" and sh != "support" and not sh in RANGED_SHAPES


## 普攻参考伤害：积木 base 攻击（atk_key → atk → bolt_atk）× attack.mult × 局部倍率 × 伤害加成（同 ob_core.exec_shape 的缺省算法）
static func ref_dmg(o) -> float:
	var a: Dictionary = o.B.get("attack", {})
	var b: float = o.base(str(a.get("atk_key", "atk")), 0.0)
	if b <= 0.0:
		b = o.base("bolt_atk", 0.0)
	var m = a.get("mult", 1.0)
	return b * (float(m) if (m is float or m is int) else 1.0) * float(o.loc.dmg) * o._dmg_bonus()


## 普攻触及距离（形状半径 × op_range；刺击按 len；远程按 range）
static func reach(o) -> float:
	var a: Dictionary = _atk(o)
	var r = a.get("r", null)
	if (r is float or r is int) and float(r) > 0.0:   # 同 ob_core.shape_radius（不预载 ob_core：本脚本被继承链里的 ob_summon 预载，互相预载会循环）
		if a.get("r_abs", false):
			return float(r) * float(a.get("r_mult", 1.0))
		return float(r) * o.stat(&"op_range") * float(a.get("r_mult", 1.0))
	if a.has("len"):
		return float(a.len) * o.stat(&"op_range")
	if a.has("range") and (a.range is float or a.range is int):
		return float(a.range) * o.stat(&"op_range")
	return 90.0 * o.stat(&"op_range")


static func _hit_kind(o) -> String:
	var hs = o.g.hit_src.get(str(o.B.get("attack", {}).get("src", "")), null)
	if hs is Dictionary:
		return str(hs.get("kind", "物理"))
	return "法术" if o.cls in ["术师", "医疗", "辅助"] else "物理"


## 伤害来源（作战记录按名字归到该干员）：每次结算前把 op / 职业 / 伤害类型写成当前干员
static func _src(o, key: String, rng: String) -> String:
	o.g.hit_src[key] = {"emitter": "operator", "origin": "core", "range": rng, "kind": _hit_kind(o), "tags": ["projectile", "growth"], "class": o.cls, "op": o.id}
	return key


static func st(o) -> Dictionary:
	if o.vg.is_empty():
		o.vg = {"acc_s": 0.0, "acc_b": 0.0, "acc_q": 0.0, "bul": [], "qi": [], "pend": [], "qside": 1.0, "n_shots": 0, "n_qi": 0, "n_merged": 0}
	return o.vg


# ---------------------------------------------------------------- 出手（data_operator._release_body 末尾调）

static func on_release(o) -> void:
	var s := summary(o.g)
	if s.is_empty():
		return
	if s.e_shots > 0.0 and shot_eater(o):
		_fire_shots(o, s)
	if s.e_qi > 0.0 and qi_eater(o):
		_fire_qi(o, s)


static func _take(v: Dictionary, k: String, e: float) -> int:
	var acc: float = float(v[k]) + e
	var n := int(floor(acc + 1e-9))
	v[k] = acc - n
	return n


static func _fire_shots(o, s: Dictionary) -> void:
	var v := st(o)
	var ns: int = _take(v, "acc_s", s.e_scatter)
	var nb: int = _take(v, "acc_b", s.e_burst)
	if ns + nb <= 0:
		return
	var rr: float = reach(o) + 30.0
	var ts: Array = o.nearest_enemies(1 + ns, rr, o.pos)
	if ts.is_empty():
		return
	var main: Dictionary = ts[0]
	var per: float = ref_dmg(o) * (s.t_shots - 1.0) / maxf(0.01, s.e_shots)
	var spread: float = deg_to_rad(kn("shot_spread_deg", 10.0))
	for k in ns:
		var tg: Dictionary = ts[k + 1] if k + 1 < ts.size() else main
		var off: float = 0.0 if k + 1 < ts.size() else spread * (1.0 + int(k / 2)) * (1.0 if k % 2 == 0 else -1.0)
		_spawn_shot(o, tg, off, per, "散射")
	for k in nb:
		v.pend.append({"t": kn("burst_gap", 0.08) * (k + 1), "tg": main, "dmg": per, "dir": (main.pos - o.pos).angle()})


static func _live_total(g, k: String) -> int:
	var n := 0
	for m in g.squad.ops:
		if not m.vg.is_empty():
			n += m.vg[k].size()
	return n


static func _spawn_shot(o, tg: Dictionary, off: float, dmg: float, key: String, ang := INF) -> void:
	var g = o.g
	var v := st(o)
	v.n_shots += 1
	var from: Vector2 = o.pos
	var a: float = ((tg.pos - from).angle() if ang == INF else ang) + off
	if _live_total(g, "bul") >= cap_of("cap_shots", 64):   # §6：超出同屏上限不生成实体，伤害直接结算到目标（总伤不变）
		v.n_merged += 1
		if not tg.get("dead", true) and int(tg.get("id", -1)) >= 0:
			_hit(o, tg, dmg, _src(o, key, "远程"))
			o.fx({"kind": "spark", "pos": tg.pos + Vector2(0, SHOT_Y), "vel": Vector2.ZERO, "life": 0.15, "col": _tint(o), "sz": 2.5, "drag": 0.0})
		return
	var spd: float = kn("shot_speed", 560.0)
	var life: float = (reach(o) + 80.0) / spd
	v.bul.append({"p": from, "v": Vector2.from_angle(a) * spd, "life": life, "dmg": dmg, "key": key, "hit": {},
		"max": 1 + mini(1, int(o.atk_pierce(0)))})   # 额外弹继承 min(底穿, 1)，不继承穿甲弹的「穿全部」（§2.4）


static func _fire_qi(o, s: Dictionary) -> void:
	var v := st(o)
	var n: int = _take(v, "acc_q", s.e_qi)
	if n <= 0:
		return
	var rr: float = reach(o)
	var dist: float = rr * kn("qi_range", 1.6)
	var ts: Array = o.nearest_enemies(1, dist + 30.0, o.pos)
	var a0: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
	var fan: float = deg_to_rad(kn("qi_fan_deg", 12.0))
	var dmg: float = ref_dmg(o) * float(s.qi_mult)
	for k in n:
		var off := 0.0
		if o.id in OWN_QI or k > 0:   # 自带剑气的干员 / 第二道起：扇形左右交替错开
			v.qside = -float(v.qside)
			off = fan * float(v.qside) * (1.0 + int(k / 2))
		v.n_qi += 1
		var a: float = a0 + off
		if _live_total(o.g, "qi") >= cap_of("cap_qi", 24):
			v.n_merged += 1
			if not ts.is_empty():
				_hit(o, ts[0], dmg, _src(o, "剑气", "近战"))
			continue
		var spd: float = kn("qi_speed", 520.0)
		var skip: float = rr * kn("qi_skip", 0.7)   # 从刀光边缘飞出，不打刀光里（普攻已经打到）的敌人：剑气专补刀光够不到的
		var q := {"p": o.pos + Vector2.from_angle(a) * skip, "v": Vector2.from_angle(a) * spd, "life": (dist - skip) / spd, "dmg": dmg, "hit": {},
			"max": int(s.qi_hits), "t": 0.0, "o0": o.pos, "skip": skip}
		var ez: Dictionary = SwordEase.cfg(str(o.id), {}, true)   # 非线性：总距离 dist − skip、总时长不变，只改中途快慢
		if not ez.is_empty():
			q.ez = ez
			q.p0 = q.p
			q.T = float(q.life)
			q.len = dist - skip
		v.qi.append(q)


static func _hit(o, e: Dictionary, dmg: float, src: String) -> void:
	o.log_hit(src, ["projectile", "growth"])
	o.deal_damage(e, dmg * (o.vs_elite() if e.elite or e.boss else 1.0))


# ---------------------------------------------------------------- 每帧（data_operator.update）

static func tick(o, dt: float) -> void:
	if o.vg.is_empty():
		return
	var v: Dictionary = o.vg
	var g = o.g
	if not v.pend.is_empty():
		var keep: Array = []
		for p in v.pend:
			p.t -= dt
			if p.t > 0.0:
				keep.append(p)
				continue
			var tg: Dictionary = p.tg
			if tg.dead:
				var ns: Array = o.nearest_enemies(1, reach(o) + 30.0, o.pos)
				if ns.is_empty():
					continue
				tg = ns[0]
			_spawn_shot(o, tg, 0.0, float(p.dmg), "连发")
		v.pend = keep
	if not v.bul.is_empty():
		for b in v.bul:
			b.p += b.v * dt
			b.life -= dt
			if b.life <= 0.0:
				continue
			for j in o.query_ids(b.p, 32.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or b.hit.has(e.id) or e.pos.distance_to(b.p) > float(e.r) + 8.0:
					continue
				b.hit[e.id] = true
				_hit(o, e, float(b.dmg), _src(o, str(b.key), "远程"))
				o.fx({"kind": "spark", "pos": e.pos + Vector2(0, SHOT_Y), "vel": b.v.normalized() * 40.0, "life": 0.14, "col": _tint(o), "sz": 2.0, "drag": 4.0})
				if b.hit.size() >= int(b.max):
					b.life = 0.0
					break
		v.bul = v.bul.filter(func(b): return b.life > 0.0)
	if not v.qi.is_empty():
		var loss: float = kn("qi_pierce_loss", 0.1)
		var mn: float = kn("qi_pierce_min", 0.5)
		var w: float = kn("qi_w", 26.0) * 0.5
		for q in v.qi:
			var qa: Vector2 = q.p   # 非线性：判定扫过上一帧 → 这一帧整段（出手几帧一帧走 20+ px）
			q.t += dt
			q.life -= dt
			if q.has("ez"):
				q.p = q.p0 + q.v.normalized() * float(q.len) * SwordEase.prog(q.ez, q.t / q.T)
			else:
				q.p += q.v * dt
				qa = q.p
			if q.life <= 0.0:
				continue
			for j in o.query_ids((qa + q.p) * 0.5, w + 40.0 + qa.distance_to(q.p) * 0.5):
				var e: Dictionary = g.enemies[j]
				if e.dead or q.hit.has(e.id) or SwordEase.seg_dist(e.pos, qa, q.p) > float(e.r) + w or e.pos.distance_to(q.o0) < float(q.skip):
					continue
				if q.has("ez") and not q.has("paused") and float(q.ez.pause) > 0.0 and SwordEase.fast(q.ez, q.t / q.T) > 0.3:   # 猛冲段头一下命中：极短顿帧（共享限频）
					q.paused = true
					o.impact_pause(float(q.ez.pause))
				var pm: float = maxf(mn, 1.0 - loss * q.hit.size())
				q.hit[e.id] = true
				_hit(o, e, float(q.dmg) * pm, _src(o, "剑气", "近战"))
				if q.hit.size() >= int(q.max):
					q.life = 0.0
					break
		v.qi = v.qi.filter(func(q): return q.life > 0.0)


# ---------------------------------------------------------------- 画面（data_operator._draw_skill_over）

static func _tint(o) -> Color:
	var c: Color = o.col()
	return c.lerp(Color(1, 1, 1), 0.4)


static func draw(o) -> void:
	if o.vg.is_empty():
		return
	var v: Dictionary = o.vg
	var g = o.g
	var cv = o.cv
	var low: bool = quality() == "low"
	var tc := _tint(o)
	var sc: float = kn("shot_scale", 0.8)
	for b in v.bul:
		var p: Vector2 = b.p + Vector2(0, SHOT_Y)
		var d: Vector2 = b.v.normalized()
		if not low:   # 拖尾：两段由浅到亮
			cv.draw_line(p - d * 30.0 * sc, p - d * 12.0 * sc, Color(tc.r, tc.g, tc.b, 0.3), 3.0 * sc)
			cv.draw_line(p - d * 14.0 * sc, p, Color(tc.r, tc.g, tc.b, 0.7), 4.0 * sc)
		cv.draw_circle(p, 7.0 * sc, Color(tc.r, tc.g, tc.b, 0.3))
		cv.draw_circle(p, 3.6 * sc, Color(minf(tc.r * 1.5, 1.8), minf(tc.g * 1.5, 1.8), minf(tc.b * 1.5, 1.8), 1.0))
	if v.qi.is_empty():
		return
	var has_tex: bool = o._fx_tex(QI_PROJ) != null
	for q in v.qi:
		var p2: Vector2 = q.p + Vector2(0, -16.0)
		var a: float = clampf(q.life / 0.08, 0.0, 1.0)
		var ang: float = q.v.angle()
		var qc := Color(minf(tc.r * 1.5, 1.8), minf(tc.g * 1.5, 1.8), minf(tc.b * 1.5, 1.8), a)   # 代表色提亮（灰白干员也看得出）
		var f := 0.0
		if q.has("ez"):   # 力量感：猛冲段提亮 + 残影（间距跟速度走），滑行段变暗
			var u: float = q.t / q.T
			f = SwordEase.fast(q.ez, u)
			var br: float = (1.0 + float(q.ez.bright) * f) * SwordEase.fade(q.ez, u)   # 滑行段压暗颜色
			qc = Color(minf(qc.r * br, 2.2), minf(qc.g * br, 2.2), minf(qc.b * br, 2.2), qc.a)
			if has_tex and f > 0.05:
				var gap: float = float(q.len) / q.T * SwordEase.vel_mul(q.ez, u) * 0.022
				for gi in range(int(q.ez.ghost), 0, -1):
					o.draw_spr_rot(QI_PROJ, mini(int(q.t * 16.0), 1), p2 - Vector2.from_angle(ang) * gap * gi, ang, g.PX * kn("qi_scale", 1.4), Color(qc.r, qc.g, qc.b, qc.a * f * 0.38 / gi))
		cv.draw_arc(p2 - Vector2.from_angle(ang) * 8.0, 18.0, ang - 1.1 * (1.0 - 0.3 * f), ang + 1.1 * (1.0 - 0.3 * f), 14, Color(qc.r, qc.g, qc.b, 0.35 * a), 7.0)   # 外层光弧（猛冲时收窄、像被拉长）
		if has_tex:
			o.draw_spr_rot(QI_PROJ, mini(int(q.t * 16.0), 1), p2, ang, g.PX * kn("qi_scale", 1.4), qc)
		else:
			cv.draw_arc(p2 - Vector2.from_angle(ang) * 10.0, 15.0, ang - 1.0, ang + 1.0, 12, qc, 4.0)


# ---------------------------------------------------------------- 召唤物（ob_summon / seg_wisadel 调）

## 体型倍率（贴图缩放；攻击半径另乘 1 + (x − 1) × summon_r_follow）
static func summon_scale(g) -> float:
	var s := summary(g)
	return float(s.get("size", 1.0)) if not s.is_empty() else 1.0


static func summon_reach(g) -> float:
	return 1.0 + (summon_scale(g) - 1.0) * kn("summon_r_follow", 0.5)


static func summon_life(g) -> float:
	var s := summary(g)
	return float(s.get("life", 1.0)) if not s.is_empty() else 1.0


## 某种召唤物的副体数（Mon3tr 例外 = 0）
static func summon_subs(g, kind := "") -> int:
	if kind.to_lower() in NO_SUB_KINDS:
		return 0
	var s := summary(g)
	return int(s.get("sub_n", 0)) if not s.is_empty() else 0
