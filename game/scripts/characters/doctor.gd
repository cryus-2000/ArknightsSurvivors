## 博士（docs/23 §3）：场上唯一的受击体。生命 / 位置 / 移动 / 拾取 / 灯火 / 等级这些通用状态仍由 game.gd 持有（ppos / hp / …），
## 本文件放博士层的专属逻辑：指挥技能（唯一的手动技能）、排异反应、局外成长接入。
extends RefCounted

var g
var def: Dictionary = {}
var rej_count := 0             # 排异反应次数（结局线用）
var rej_log: Array = []        # 每次排异的说明文字

## 博士被动（cat doctor）与全队被动（cat squad），docs/23 §6：各自最多选 4 种，选满后只出已有种类
const PASSIVES := {
	"hp": {"name": "坚韧", "desc": "最大生命 +20", "max": 99, "cat": "doctor"},
	"regen": {"name": "自愈", "desc": "每秒回复生命 +0.6", "max": 5, "cat": "doctor"},
	"armor": {"name": "硬化", "desc": "物理减伤 +2（法术、真实伤害无效）", "max": 4, "cat": "doctor"},
	"dodge": {"name": "水影", "desc": "闪避率 +5%", "max": 4, "cat": "doctor"},
	"speed": {"name": "轻盈", "desc": "移动速度 +10%", "max": 5, "cat": "doctor"},
	"pickup": {"name": "感知", "desc": "拾取范围 +30%", "max": 5, "cat": "doctor"},
	"wick": {"name": "护灯", "desc": "受击时灯火损失 -15%", "max": 4, "cat": "doctor"},
	"sp": {"name": "协同·技", "desc": "全队技能充能 +15%", "max": 4, "cat": "squad"},
	"squad_atk": {"name": "协同·攻", "desc": "全队干员攻击 +8%", "max": 5, "cat": "squad"},
	"squad_aspd": {"name": "协同·迅", "desc": "全队干员攻速 +6%", "max": 5, "cat": "squad"},
	"squad_range": {"name": "协同·广", "desc": "全队干员射程 / 范围 +8%", "max": 4, "cat": "squad"},
	"squad_crit": {"name": "协同·锐", "desc": "全队干员技能强度 +10%", "max": 4, "cat": "squad"},
}
const PASSIVE_CAP := 4         # 每类最多几种


func _init(game) -> void:
	g = game
	var f := FileAccess.open("res://data/doctor.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			def = d


func name() -> String:
	return def.get("name", "博士")


## 唯一的手动技能入口（Space / J）。P1 阶段博士还没有指挥技能：返回 false
func try_manual_skill() -> bool:
	return false


## 排异反应：博士承受，效果落在编队里随机一名能被海嗣化的干员身上（干员实现 apply_rejection）；
## 没有可承受的干员时改为直接削减博士生命上限
func apply_rejection() -> String:
	rej_count += 1
	var cands: Array = []
	for o in g.squad.ops:
		if o.has_method("apply_rejection"):
			cands.append(o)
	var what := ""
	cands.shuffle()
	for c in cands:
		what = c.apply_rejection()
		if what != "":
			break
	if what == "":
		g.stats.add(&"max_hp", "flat", -20.0, "rejection")
		g._sync_stats()
		g.hp = minf(g.hp, g.max_hp)
		what = "生命上限 -20"
	rej_log.append(what)
	return what


## 排异记录（结算 / Tab 面板）：合并各干员的 rej 字典
func rej() -> Dictionary:
	var out: Dictionary = {}
	for o in g.squad.ops:
		if "rej" in o:
			for k in o.rej:
				out[k] = true
	return out


# ---------------------------------------------------------------- 被动

func passive_cat(pid: String) -> String:
	return PASSIVES.get(pid, {}).get("cat", "")


## 已选种类数（按类别）
func passive_kinds(cat: String) -> int:
	var n := 0
	for pid in PASSIVES:
		if PASSIVES[pid].cat == cat and g.growth.get(pid, 0) > 0:
			n += 1
	return n


## 可出的被动卡（按类别；种类满 4 后只出已有的）
func passive_cards(cat: String) -> Array:
	var out: Array = []
	var full: bool = passive_kinds(cat) >= PASSIVE_CAP
	for pid in PASSIVES:
		var pdef: Dictionary = PASSIVES[pid]
		if pdef.cat != cat:
			continue
		var n: int = g.growth.get(pid, 0)
		if n >= pdef.max or (full and n == 0):
			continue
		var nm: String = pdef.name if pdef.max > 90 else "%s  %d/%d" % [pdef.name, n + 1, pdef.max]
		out.append({"kind": "growth", "id": pid, "name": nm, "desc": pdef.desc + "\n" + passive_preview(pid), "cat": ("博士被动  DOCTOR" if cat == "doctor" else "全队被动  SQUAD")})
	return out


func apply_passive(pid: String) -> bool:
	if not PASSIVES.has(pid):
		return false
	var st = g.stats
	var src := "growth:" + pid
	match pid:
		"hp": st.add(&"max_hp", "flat", 20.0, src)
		"regen": st.add(&"regen", "flat", 0.6, src)
		"armor": st.add(&"armor", "flat", 2.0, src)
		"dodge": st.add(&"dodge", "flat", 0.05, src)
		"speed": st.add(&"move_speed", "mult", 1.1, src)
		"pickup": st.add(&"pickup", "mult", 1.3, src)
		"wick": st.add(&"light_decay", "mult", 0.85, src)
		"sp": st.add(&"sp_gain", "mult", 1.15, src)
		"squad_atk": st.add(&"op_atk", "add", 0.08, src, "squad")
		"squad_aspd": st.add(&"op_aspd", "add", 0.06, src, "squad")
		"squad_range": st.add(&"op_range", "add", 0.08, src, "squad")
		"squad_crit": st.add(&"op_skill_power", "add", 0.1, src, "squad")
	g._sync_stats()
	return true


func passive_preview(pid: String) -> String:
	match pid:
		"hp": return "最大生命 %d → %d" % [int(g.max_hp), int(g.max_hp) + 20]
		"regen": return "生命回复 %.1f → %.1f / 秒" % [g.regen, g.regen + 0.6]
		"armor": return "减伤 %d → %d" % [int(g.armor), int(g.armor) + 2]
		"dodge": return "闪避 %d%% → %d%%" % [int(g.dodge * 100), int(g.dodge * 100) + 5]
		"speed": return "移动速度 %d → %d" % [int(g.speed), int(g.speed * 1.1)]
		"pickup": return "拾取范围 %d → %d" % [int(g.pickup), int(g.pickup * 1.3)]
		"wick": return "受击灯火损失 ×%.2f → ×%.2f" % [g.lamp_decay, g.lamp_decay * 0.85]
		"sp": return "技力回复 ×%.2f → ×%.2f" % [g.sp_mult, g.sp_mult * 1.15]
		"squad_atk": return "全队攻击 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_atk", ["squad"]), g.stats.value_for(&"op_atk", ["squad"]) + 0.08]
		"squad_aspd": return "全队攻速 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_aspd", ["squad"]), g.stats.value_for(&"op_aspd", ["squad"]) + 0.06]
		"squad_range": return "全队范围 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_range", ["squad"]), g.stats.value_for(&"op_range", ["squad"]) + 0.08]
		"squad_crit": return "技能强度 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_skill_power", ["squad"]), g.stats.value_for(&"op_skill_power", ["squad"]) + 0.1]
	return ""


## 填充卡：其他类别都满时
func filler_cards() -> Array:
	return [
		{"kind": "filler", "id": "heal", "name": "急救补给", "desc": "立刻回复博士 30% 最大生命", "cat": "补给  SUPPLY"},
		{"kind": "filler", "id": "oil", "name": "灯油补给", "desc": "灯火 +30", "cat": "补给  SUPPLY"},
		{"kind": "filler", "id": "atk", "name": "临时协同", "desc": "全队干员攻击 +4%（可叠加）", "cat": "补给  SUPPLY"},
	]


func apply_filler(fid: String) -> void:
	match fid:
		"heal": g._heal(g.max_hp * 0.3, "填充卡")
		"oil": g.lamp = minf(g.lamp_cap, g.lamp + 30.0)
		"atk":
			g.stats.add(&"op_atk", "add", 0.04, "filler", "squad")
			g._sync_stats()
