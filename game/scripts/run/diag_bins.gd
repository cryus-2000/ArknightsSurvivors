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
	b.dmg[c] = float(b.dmg.get(c, 0.0)) + eff
	if not e.boss:
		b.dmg_nb[c] = float(b.dmg_nb.get(c, 0.0)) + eff


func kill(e: Dictionary) -> void:
	if not on:
		return
	var b := _bin()
	var c := cat(g.hit if g.hit != null else {})
	b.kill[c] = int(b.kill.get(c, 0)) + 1
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
			b.sp_n += 1
			b.sp_hp += float(e.maxhp)
	b.ns += 1
	b.ns_sum += ns
	b.ns_pk = maxi(b.ns_pk, ns)
	b.na_sum += na
	b.hps_sum += hps
	b.hpa_sum += hpa
	b.lv = g.level
	b.squad = g.squad.size()


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
		out.append(o)
	return out
