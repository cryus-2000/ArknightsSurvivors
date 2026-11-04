extends RefCounted
## 后期诊断遥测（docs/243，只读）：只在命令行带 --diagbins 时启用，按 30 秒分桶记
##   伤害 / 击杀按来源类别（普攻 / S1–S3 / 天赋 / 分支 / 终结技 / 连携 / 藏品 / 召唤 / 支援）、对普通怪的伤害、
##   每秒采样的同屏敌人数与怪群总血量、本桶新刷出的敌人数与生命总量。
## 不读写任何随机数、不改任何玩法量；敌人字典上只多一个记账键 _dg（与 telemetry 的 _hb 同性质）。
## S1–S3 按「命中时该干员最近一次起手的技能序号 cur_skill」归类，持续性技能区域跨技能时有误差。

const BIN := 30.0
var g
var on := false
var bins: Array = []
var _acc := 0.0
var warn_stats: Dictionary = {}   # "施法者类型|形状|动作|boss/elite/mob" -> [次数, 时长和, 面积和（世界像素²）, 颜色]
var elites: Array = []            # 精英死亡：{t0 首次出现, t1 死亡, cat 致死类别, ultf 终结技伤害 / 最大生命, horde 是否围猎 / 大群}
var _ult_d: Dictionary = {}       # Boss 实例 id -> [类型, 终结技伤害, 最大生命]
const VIEW := Vector2(1280.0, 720.0)


func _init(game) -> void:
	g = game
	on = Cfg.dev_args().has("--diagbins")


func _bin() -> Dictionary:
	var i := int(g.t / BIN)
	while bins.size() <= i:
		bins.append({"t": bins.size() * int(BIN), "dmg": {}, "dmg_nb": {}, "kill": {}, "ns": 0, "ns_sum": 0, "ns_pk": 0,
			"na_sum": 0, "hps_sum": 0.0, "hpa_sum": 0.0, "sp_n": 0, "sp_hp": 0.0, "lv": 0, "squad": 0})
	return bins[i]


func cat(h: Dictionary) -> String:
	var tags: Array = h.get("tags", [])
	if "终结技" in tags:
		return "ult"
	if "连携" in tags:
		return "combo"
	var em := str(h.get("emitter", ""))
	var org := str(h.get("origin", ""))
	if em == "relic" or org == "relic":
		return "relic"
	if em == "summon":
		return "summon"
	if em == "support" or org == "support":
		return "support"
	if org == "skill":
		var opid := str(h.get("op", ""))
		for o in g.squad.ops:
			if str(o.id) == opid:
				return "S%d" % (int(o.cur_skill) + 1)
		return "S?"
	if org == "core":
		return "basic"
	if org == "talent":
		return "talent"
	if org == "route":
		return "route"
	return "other"


func dmg(e: Dictionary, eff: float, h: Dictionary) -> void:
	if not on or eff <= 0.0 or e.get("chest", false) or e.get("friendly", false):
		return
	var b := _bin()
	var c := cat(h)
	if c == "ult" and e.elite and not e.boss:
		e["_dgu"] = float(e.get("_dgu", 0.0)) + eff
	if e.boss:
		if not e.has("_dgb"):
			e["_dgb"] = _ult_d.size() + 1
			_ult_d[int(e._dgb)] = [str(e.type), 0.0, float(e.maxhp)]
		var bk := int(e._dgb)
		_ult_d[bk][2] = maxf(float(_ult_d[bk][2]), float(e.maxhp))
		if c == "ult":
			_ult_d[bk][1] += eff
	b.dmg[c] = float(b.dmg.get(c, 0.0)) + eff
	if not e.boss:
		b.dmg_nb[c] = float(b.dmg_nb.get(c, 0.0)) + eff


func kill(e: Dictionary) -> void:
	if not on:
		return
	var b := _bin()
	var c := cat(g.hit if g.hit != null else {})
	b.kill[c] = int(b.kill.get(c, 0)) + 1
	if e.elite and not e.boss:
		elites.append({"t0": snappedf(float(e.get("_dgt", g.t)), 0.1), "t1": snappedf(g.t, 0.1), "cat": c, "type": str(e.type),
			"ultf": snappedf(float(e.get("_dgu", 0.0)) / maxf(1.0, float(e.maxhp)), 0.001), "horde": e.has("horde")})
	if not e.boss and not e.has("_dg"):
		e["_dg"] = 1   # 一秒内刷出又被打死的，也算进本桶刷怪量
		b.sp_n += 1
		b.sp_hp += float(e.maxhp)


func tick(dt: float) -> void:
	if not on:
		return
	_acc += dt
	if _acc < 1.0:
		return
	_acc -= 1.0
	var b := _bin()
	var half: Vector2 = VIEW / maxf(0.1, Cfg.battle_zoom()) * 0.5
	var c: Vector2 = g.ppos
	var ns := 0
	var na := 0
	var hps := 0.0
	var hpa := 0.0
	for e in g.enemies:
		if e.dead or e.boss or e.get("chest", false) or e.get("friendly", false):
			continue
		na += 1
		hpa += maxf(0.0, e.hp)
		if absf(e.pos.x - c.x) <= half.x and absf(e.pos.y - c.y) <= half.y:
			ns += 1
			hps += maxf(0.0, e.hp)
		if not e.has("_dg"):
			e["_dg"] = 1
			e["_dgt"] = g.t
			b.sp_n += 1
			b.sp_hp += float(e.maxhp)
	# 预警：新出现的登记一次（类型 / 形状 / 时长 / 面积），每秒采样在场数量与总面积
	var wa := 0.0
	for w in g.warns:
		var a := _warn_area(w)
		wa += a
		if not w.has("_dg"):
			w["_dg"] = 1
			var o = w.get("owner")
			var ot := "?"
			var tier := "mob"
			if o is Dictionary:
				ot = str(o.get("type", "?"))
				tier = "boss" if o.get("boss", false) else ("elite" if o.get("elite", false) else "mob")
			var k := "%s|%s|%s|%s" % [ot, str(w.shape), str(w.act), tier]
			var st: Array = warn_stats.get(k, [0, 0.0, 0.0, ""])
			st[0] += 1
			st[1] += float(w.dur)
			st[2] += a
			var col: Color = w.get("col", Color.WHITE)
			st[3] = col.to_html(false)
			warn_stats[k] = st
	b["wn_sum"] = int(b.get("wn_sum", 0)) + g.warns.size()
	b["wa_sum"] = float(b.get("wa_sum", 0.0)) + wa
	if g.ult != null:
		var us: Dictionary = g.ult.stats
		b["ue"] = [snappedf(float(us.e_out), 0.1), snappedf(float(us.e_kill), 0.1), snappedf(float(us.e_hurt), 0.1), snappedf(float(us.e_combo), 0.1)]
	b.ns += 1
	b.ns_sum += ns
	b.ns_pk = maxi(b.ns_pk, ns)
	b.na_sum += na
	b.hps_sum += hps
	b.hpa_sum += hpa
	b.lv = g.level
	b.squad = g.squad.size()


func _warn_area(w: Dictionary) -> float:
	match str(w.shape):
		"circle":
			return PI * float(w.r) * float(w.r)
		"line":
			return float(w.len) * float(w.wid) * 2.0
		"cone":
			return float(w.half) * float(w.get("len", w.r)) * float(w.get("len", w.r))
	return 0.0


func extra() -> Dictionary:
	var bo: Array = []
	for k in _ult_d:
		bo.append({"type": _ult_d[k][0], "ultf": snappedf(_ult_d[k][1] / maxf(1.0, _ult_d[k][2]), 0.001)})
	var ws := {}
	for k in warn_stats:
		var st: Array = warn_stats[k]
		ws[k] = [st[0], snappedf(st[1], 0.01), int(st[2]), st[3]]
	return {"warns": ws, "elites": elites, "bosses": bo}


func report() -> Array:
	var out: Array = []
	for b in bins:
		var o: Dictionary = b.duplicate(true)
		for k in ["dmg", "dmg_nb"]:
			for c in o[k]:
				o[k][c] = int(o[k][c])
		o.hps_sum = int(o.hps_sum)
		o.hpa_sum = int(o.hpa_sum)
		o.sp_hp = int(o.sp_hp)
		if o.has("wa_sum"):
			o.wa_sum = int(o.wa_sum)
		out.append(o)
	return out
