extends RefCounted
## 干员数值表（选人页「属性」页签与图鉴「属性」页共用，docs/72 §2 / §4.2）。
## 口径：当主控、精零、1 级、无藏品，含 balance.json 档位修正（atk / aspd / range）。纯显示，不参与战斗计算。
## 角色 JSON 的攻击键名不统一（atk / m_atk / umbrella_dmg / bolt_atk …），这里统一映射；
## 写死在干员脚本里、JSON 读不到的显示信息（艾丽妮每次 2 段、水月触手系数）放在下面的常量里，改脚本时一起改。
const Bal = preload("res://scripts/core/balance.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")

const NOTE := "以上为队长、精零、无藏品时的数值"
## 每张数值表都必须有的行（测试按这个查缺）
const REQUIRED := ["hp", "atk", "cd", "dps", "reach", "armor", "arts", "regen", "speed"]
## 每次普攻的段数写死在脚本里的干员（irene.gd：刺击两段，N1 再审才 3 段）
const ATK_KEYS := ["atk", "m_atk", "umbrella_dmg", "bolt_atk"]
const CD_KEYS := ["cd", "m_cd", "swing_interval", "bolt_cd"]
## 范围键 → [标签, 英文]；按顺序取第一个存在的键（aura：浊心斯卡蒂歌域，docs/61；dash_len：德克萨斯冲刺距离）
const REACH_KEYS := [["range", "射程", "RANGE"], ["bolt_range", "射程", "RANGE"], ["reach", "攻击半径", "RADIUS"],
	["m_reach", "Mon3tr 半径", "RADIUS"], ["swing_radius", "攻击半径", "RADIUS"], ["len", "刺击长度", "LENGTH"],
	["aura", "歌域半径", "AURA"], ["dash_len", "冲刺距离", "DASH"]]

static var _doctor: Dictionary = {}


static func _first(data: Dictionary, keys: Array, fallback := 0.0) -> float:
	for key in keys:
		if data.has(key):
			return float(data[key])
	return fallback


static func _doctor_stats() -> Dictionary:
	if _doctor.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/doctor.json"))
		_doctor = d.get("stats", {}) if d is Dictionary else {}
	return _doctor


## 减伤一律保留一位小数（0.5 档不能被截成整数，docs/72 §4.1 #4）
static func fmt_armor(v: float) -> String:
	return "%.1f" % v


## 去掉多余的 .0（12.0 → 12，12.6 → 12.6）
static func _num(v: float) -> String:
	return "%d" % int(round(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v


static func _row(key: String, label: String, en: String, text: String, val: float, sub := "") -> Dictionary:
	return {"key": key, "label": label, "en": en, "text": text, "val": val, "sub": sub}


## 数值表：{rows: [{key, label, en, text, val, sub}], extra: [同上，干员特有], tags: [定位], note}
## rows 固定 9 行（REQUIRED 顺序）；extra 是领唱 / 歌域 / 穿透 / 格挡 / 对精英 / 治疗等只有部分干员有的行
static func sheet(cid: String, definition: Dictionary) -> Dictionary:
	var b: Dictionary = definition.get("base", {})
	var lead: Dictionary = definition.get("leader", {})
	var doc := _doctor_stats()
	var mod: Dictionary = Bal.op(cid)
	# 局内开局对基础值乘的旋钮（game.gd 开局 / squad._apply_leader_regen）这里同样乘上，面板数字 = 开局实际值（10-28 乌尔比安回复显示 2.0、实际 1.6）
	var hp: float = float(lead.get("max_hp", doc.get("max_hp", StatDefs.PLAYER[&"max_hp"].base))) * Bal.v("squad/leader_hp_mult", 0.9) * Bal.v("squad/dodge_comp_hp", 1.0)
	var atk: float = _first(b, ATK_KEYS) * (1.0 + float(mod.get("atk", 0.0))) * Bal.v("squad/op_atk_base", 0.9)
	var interval: float = _first(b, CD_KEYS) / maxf(0.2, 1.0 + float(mod.get("aspd", 0.0)))
	var reach_lbl: Array = ["攻击范围", "RANGE"]
	var reach := 0.0
	for rk in REACH_KEYS:
		if b.has(rk[0]):
			reach = float(b[rk[0]]) * (1.0 + float(mod.get("range", 0.0)))
			reach_lbl = [rk[1], rk[2]]
			break
	var speed: float = float(doc.get("move_speed", StatDefs.PLAYER[&"move_speed"].base)) * Bal.v("squad/leader_speed_mult", 1.1)
	# 普攻的段数 / 附加伤害：单体每秒伤害 = 攻击 × 段数 × (1 + 附加) ÷ 间隔
	var atk_lbl := "Mon3tr 攻击" if b.has("m_atk") else "攻击"
	var hits: int = int(b.get("shots", definition.get("stat_hits", 1)))   # stat_hits：干员 json（艾丽妮一次刺击 2 段）
	var follow := 0.0
	var atk_sub := ""
	var dps_sub := "单体"
	var extra: Array = []
	if hits > 1:
		atk_sub = "× %d %s" % [hits, "段" if definition.has("stat_hits") else "发"]
	if b.has("quake"):   # 维什戴尔：落点 0.45 秒后余震
		follow = float(b.quake)
		atk_sub = "+ 余震 %s" % _num(atk * follow)
	if b.has("umbrella_dmg"):   # 水月：伞击附带触手追击（法术），系数在 stat_defs
		follow = float(StatDefs.MIZUKI.get(&"mizuki_tentacle_mult", {"base": 0.6}).base)
		atk_sub = "+ 触手 %s" % _num(atk * follow)
	var single := atk * hits * (1.0 + follow)
	if b.has("wave_n"):   # 浊心斯卡蒂：声浪打圈内最近的 wave_n 个；当主控时另有领唱打圈内全部
		atk_lbl = "声浪伤害"
		atk_sub = "× 最多 %d 名" % int(b.wave_n)
		var lm: float = float(b.get("lead_mult", 0.0))
		single = atk * (1.0 + lm)
		dps_sub = "单体 · 含领唱"
		if lm > 0.0:
			extra.append(_row("lead", "领唱", "LEAD", "圈内全部 ×%s%%" % _num(lm * 100.0), lm))
	if b.has("song_atk"):
		extra.append(_row("song", "歌域增益", "SONG", "攻击 +%s%%" % _num(float(b.song_atk) * 100.0), float(b.song_atk)))
	if int(b.get("pierce", 0)) > 0:
		extra.append(_row("pierce", "穿透", "PIERCE", "%d 名" % int(b.pierce), float(b.pierce)))
	if float(b.get("block_chance", 0.0)) > 0.0:   # 星熊：战术装甲概率完全免伤
		extra.append(_row("block", "格挡", "BLOCK", "%d%%" % int(round(float(b.block_chance) * 100.0)), float(b.block_chance), "完全免伤"))
	if float(b.get("vs_elite", 1.0)) > 1.0:
		extra.append(_row("elite", "对精英", "VS ELITE", "伤害 ×%s" % _num(float(b.vs_elite)), float(b.vs_elite)))
	if b.has("heal_pct") and b.has("heal_cd"):
		var hp_pct: float = float(b.heal_pct) * 100.0 * Bal.v("squad/op_atk_base", 0.9) * (1.0 + float(mod.get("atk", 0.0)))   # 治疗乘开局 op_atk（同说明 $k_atk）
		extra.append(_row("heal", "治疗队长", "HEAL", "%s%% / %s 秒" % [String.num(hp_pct, 2), _num(float(b.heal_cd))], float(b.heal_pct), "最大生命"))
	var dps := single / maxf(0.05, interval)
	var armor: float = float(lead.get("armor", 0.0))
	var arts: float = float(lead.get("arts_res", 0.0))
	var regen: float = float(lead.get("regen", doc.get("regen", 1.0))) * Bal.v("sustain/base_regen_mult", 1.0)
	var rows := [
		_row("hp", "生命", "HP", "%d" % int(round(hp)), hp),
		_row("atk", atk_lbl, "ATK", _num(atk), atk, atk_sub),
		_row("cd", "攻击间隔", "INTERVAL", "%.2f 秒" % interval, interval),
		_row("dps", "每秒伤害", "DPS", "%.1f" % dps, dps, dps_sub),
		_row("reach", reach_lbl[0], reach_lbl[1], "%d" % int(round(reach)), reach),
		_row("armor", "物理减伤", "ARMOR", fmt_armor(armor), armor),
		_row("arts", "法术抗性", "RES", "%d%%" % int(round(arts * 100.0)), arts),
		_row("regen", "生命回复", "REGEN", "%.1f / 秒" % regen, regen),
		_row("speed", "移动速度", "SPEED", "%d" % int(round(speed)), speed),
	]
	var tags: Array = []
	var cls: String = str(definition.get("class", ""))
	if cls != "":
		tags.append(cls)
	for tg in definition.get("gallery", {}).get("tags", []):
		if not tags.has(str(tg)):
			tags.append(str(tg))
	# 队长默认受到的伤害倍率（squad/dodge_comp_taken，闪避移进局外成长后的补偿，所有队长相同）写进口径说明（10-28 用户：局内有效果但界面没写）
	var note: String = NOTE
	var tk: float = Bal.v("squad/dodge_comp_taken", 0.9)
	if absf(tk - 1.0) > 0.001:
		note += "；队长受到的伤害 %s%d%%" % ["-" if tk < 1.0 else "+", int(round(absf(1.0 - tk) * 100.0))]
	return {"rows": rows, "extra": extra, "tags": tags, "note": note}


## 按 key 取一行（没有返回空字典）
static func row(sh: Dictionary, key: String) -> Dictionary:
	for r in sh.get("rows", []) + sh.get("extra", []):
		if r.key == key:
			return r
	return {}


## 显示用：攻击行把段数 / 附加伤害接在数字后面（「24 × 2 段」「4 × 最多 16 名」），其余行的 sub 是说明，接在标签后
static func value_text(r: Dictionary) -> String:
	return str(r.text) + (" " + str(r.sub) if r.key == "atk" and str(r.sub) != "" else "")


static func label_text(r: Dictionary) -> String:
	return str(r.label) + (" · " + str(r.sub) if r.key != "atk" and str(r.sub) != "" else "")
