extends RefCounted
## 诊断探针（临时分支，不提交）：--bossdiag 时按 Boss 统计各状态时间占比、出招数、新弹数与弹速
static var acc := {}

static func on() -> bool:
	return Cfg.dev_args().has("--bossdiag")

static func _a(e: Dictionary) -> Dictionary:
	var k := str(e.type)
	if not acc.has(k):
		acc[k] = {"t": 0.0, "stun": 0.0, "brk": 0.0, "seal": 0.0, "wind": 0.0, "chan": 0.0, "dash": 0.0, "inv": 0.0, "hold": 0.0,
			"flash": 0.0, "shake": 0.0, "blocked": 0.0, "warns": 0, "warns_dmg": 0, "acts": {}, "bul": 0, "spd": 0.0, "phase_t": {}, "hits": 0}
	return acc[k]

static func step(g, e: Dictionary, dt: float) -> void:
	if not on() or dt <= 0.0 or e.dead:
		return
	var a := _a(e)
	a.t += dt
	var ph := str(int(e.get("phase", 1)))
	a.phase_t[ph] = float(a.phase_t.get(ph, 0.0)) + dt
	var st: bool = float(e.get("stun", 0.0)) > 0.0
	var br: bool = float(e.get("break_t", 0.0)) > 0.0
	var se: bool = float(e.get("seal_t", 0.0)) > g.t
	if st: a.stun += dt
	if br: a.brk += dt
	if se: a.seal += dt
	if float(e.get("wind", 0.0)) > 0.0: a.wind += dt
	if float(e.get("channel", 0.0)) > 0.0: a.chan += dt
	if float(e.get("dash_t", 0.0)) > 0.0: a.dash += dt
	if e.get("invuln", false): a.inv += dt
	if e.get("gate_hold", false): a.hold += dt
	if float(e.get("flash", 0.0)) > 0.0: a.flash += dt
	if g.t - float(e.get("bh_at", -99.0)) < float(e.get("bh_t", 0.1)): a.shake += dt
	if st or br or se: a.blocked += dt
	if not a.has("kinds"):
		a.kinds = {}
	a.bul_peak = maxi(int(a.get("bul_peak", 0)), g.ebullets.size())
	for b in g.ebullets:
		var v = b.get("vel", Vector2.ZERO)
		var sp: float = (v as Vector2).length() if v is Vector2 else 0.0
		if not b.has("_dg"):
			b._dg = g.t
			a.bul += 1
			a.spd += sp
			var kk := str(b.get("kind", "?")) + "/" + str(b.get("izu", b.get("motion", b.get("tier", ""))))
			b._dgk = kk
			if not a.kinds.has(kk):
				a.kinds[kk] = {"n": 0, "v0": [], "v1": [], "vmax": 0.0, "home": 0, "r": []}
			a.kinds[kk].n += 1
			if a.kinds[kk].r.size() < 200:
				a.kinds[kk].r.append(snappedf(float(b.get("r", 0.0)), 0.1))
			if a.kinds[kk].v0.size() < 400:
				a.kinds[kk].v0.append(snappedf(sp, 1.0))
			if b.get("home", false) or b.get("homing", false) or b.has("track"):
				a.kinds[kk].home += 1
		elif not b.has("_dg1") and g.t - float(b._dg) >= 1.0:
			b._dg1 = 1
			var kr: Dictionary = a.kinds.get(str(b.get("_dgk", "")), {})
			if not kr.is_empty() and kr.v1.size() < 400:
				kr.v1.append(snappedf(sp, 1.0))
		if b.has("_dgk"):
			var kr2: Dictionary = a.kinds.get(str(b._dgk), {})
			if not kr2.is_empty():
				kr2.vmax = maxf(float(kr2.vmax), sp)

static func on_hit(e: Dictionary) -> void:
	if on() and e.get("boss", false):
		_a(e).hits += 1

## 队长承受 Boss 来源伤害（护甲 / 法抗后、保护截断前）：按来源名记命中数与占最大生命比例
static var phit := {}
static var tag := ""
static func on_phit(g, amount: float, raw := 0.0) -> void:
	if not on() or g.final_boss == null or g.final_boss.dead:
		return
	var k := str(g.final_boss.type)
	if not phit.has(k):
		phit[k] = {"sum": 0.0, "n": 0, "src": {}, "mh": 0.0}
	var p: Dictionary = phit[k]
	p.sum += amount
	p.n += 1
	p.mh = float(g.max_hp)
	var s := str(g.dmg_src)
	if s == "bullet" or s.begins_with("boss_"):
		s += ":" + tag
	tag = ""
	if not p.src.has(s):
		p.src[s] = []
	p.src[s].append([snappedf(amount / maxf(1.0, g.max_hp), 0.001), snappedf(raw, 0.1)])


static func on_warn(w: Dictionary) -> void:
	if not on():
		return
	var e = w.get("owner")
	if not (e is Dictionary) or not e.get("boss", false):
		return
	var a := _a(e)
	a.warns += 1
	if float(w.get("dmg", 0.0)) > 0.0:
		a.warns_dmg += 1
	var nm := str(w.get("act", "")) + "/" + str(w.get("name", ""))
	a.acts[nm] = int(a.acts.get(nm, 0)) + 1
	if w.has("kp"):
		if not a.has("lasers"):
			a.lasers = {}
		if not a.lasers.has(nm):
			a.lasers[nm] = []
		if a.lasers[nm].size() < 40:
			a.lasers[nm].append([snappedf(float(w.dur), 0.01), snappedf(float(w.get("track", 0.0)), 0.01)])

static func squad(g, tag: String) -> void:
	if not on():
		return
	var ops: Array = []
	for o in g.allies.list if g.get("allies") != null and "list" in g.allies else []:
		ops.append(str(o.get("id", "?")) + ":e" + str(o.get("elite", "?")))
	print("BOSSDIAG_SQUAD %s t=%.1f lvl=%s max_hp=%.0f relics=%s leader=%s e%d ops=%s" % [tag, g.t, str(g.get("level")), float(g.max_hp),
		str(g.relics.size()) if g.get("relics") != null else "?", str(g.ch.def.get("id", "?")) if g.ch != null else "?", int(g.ch.elite) if g.ch != null else -1, str(ops)])

static var _sq_done := false
static var _done := false
## 每帧：最终 Boss 到场时打一次分队；胜 / 负 / 战斗满 --diagmax 秒（缺省 150）或总时长超 --maxt 时打报告并退出
static var _ft_last := 0
static var ft_hi: Array = []
static var ft_all: Array = []
static func poll(g) -> void:
	if not on() or _done:
		return
	# 帧时（无头，只含模拟，不含绘制）：同屏敌弹 >= 130 时记一帧
	var now_us := Time.get_ticks_usec()
	if _ft_last > 0 and g.final_boss != null and not g.final_boss.dead:
		var ft := float(now_us - _ft_last) / 1000.0
		if ft_all.size() < 20000:
			ft_all.append(ft)
		if g.ebullets.size() >= 130 and ft_hi.size() < 20000:
			ft_hi.append(ft)
	_ft_last = now_us
	if not _sq_done and g.final_boss != null:
		_sq_done = true
		squad(g, "arrival")
	var mx := 150.0
	for x in Cfg.dev_args():
		if x.begins_with("--diagmax="):
			mx = float(x.substr(10))
	var ft := 0.0
	for k in acc:
		ft = maxf(ft, float(acc[k].t))
	var fin: bool = g.state == g.S.WIN or g.state == g.S.DEAD or (g.final_boss != null and g.final_boss.dead)
	if fin or ft >= mx:
		_done = true
		report(g, "win" if (g.final_boss != null and g.final_boss.dead) or g.state == g.S.WIN else ("dead" if g.state == g.S.DEAD else "cap"))
		g.get_tree().quit()


static func report(g, why: String) -> void:
	if not on():
		return
	for k in acc:
		var a: Dictionary = acc[k]
		var o := {"boss": k, "why": why, "fight_t": snappedf(a.t, 0.1), "now": snappedf(g.t, 0.1)}
		for f in ["stun", "brk", "seal", "wind", "chan", "dash", "inv", "hold", "flash", "shake", "blocked"]:
			o[f] = snappedf(float(a[f]) / maxf(0.1, a.t), 0.001)
		o.warns_per_min = snappedf(a.warns * 60.0 / maxf(0.1, a.t), 0.1)
		o.dmg_warns_per_min = snappedf(a.warns_dmg * 60.0 / maxf(0.1, a.t), 0.1)
		o.bul_per_s = snappedf(a.bul / maxf(0.1, a.t), 0.01)
		o.bul_spd = snappedf(a.spd / maxf(1.0, a.bul), 1.0)
		o.hits_per_s = snappedf(a.hits / maxf(0.1, a.t), 0.1)
		o.acts = a.acts
		o.phase_t = a.phase_t
		o.kinds = a.get("kinds", {})
		var hs: Array = ft_hi.duplicate()
		hs.sort()
		var al: Array = ft_all.duplicate()
		al.sort()
		o.ft_hi_n = hs.size()
		o.ft_hi_p50 = snappedf(float(hs[hs.size() / 2]), 0.01) if hs.size() > 0 else -1.0
		o.ft_hi_p95 = snappedf(float(hs[int(hs.size() * 0.95)]), 0.01) if hs.size() > 0 else -1.0
		o.ft_all_p50 = snappedf(float(al[al.size() / 2]), 0.01) if al.size() > 0 else -1.0
		o.ft_all_p95 = snappedf(float(al[int(al.size() * 0.95)]), 0.01) if al.size() > 0 else -1.0
		o.bul_peak = int(a.get("bul_peak", 0))
		o.lasers = a.get("lasers", {})
		if phit.has(k):
			var p: Dictionary = phit[k]
			o.taken_per_min = snappedf(p.sum * 60.0 / maxf(0.1, a.t), 0.1)
			o.taken_pct_per_min = snappedf(p.sum * 60.0 / maxf(0.1, a.t) / maxf(1.0, p.mh), 0.001)
			o.max_hp = p.mh
			o.p_hits = p.n
			o.p_src = p.src
		print("BOSSDIAG " + JSON.stringify(o))
