extends RefCounted
## 事件图鉴（docs/184 §11，用户 10-30）：图鉴「事件」页的条目来源 + 局外记录 Cfg.event_log。
## 记录口径：事件面板弹出算「遇到」一次（同一件事件重弹的下一屏不算）；弹出时显示的选项记「见过」；选了记「选过」次数。
## 老存档没有记录，从 0 开始。

const D = preload("res://scripts/data.gd")

## 同一件事件的后续屏：选项并进主事件显示（设身处地第二屏 / 再喂一屏），本身不单列、不算遇到
const CHILD := {"feeding_2": "feeding", "feeding_3": "feeding"}
## 再喂一屏的选项和第二屏是同一组，记到第二屏同一编号
const ALIAS := {"feeding_3": "feeding_2"}
const GROUPS := ["结局线事件", "不期而遇", "节点事件"]


## 全部事件（waves.json + events_v2.json），按 结局线 → 不期而遇 → 节点事件 排；
## 每条 {id, name, text, group, cg, opts: [{key, label, desc}]}
static func entries() -> Array:
	var w: Dictionary = D.Loader.load_waves()
	var evs: Array = (w.get("events", []) as Array).duplicate(true)
	var f := FileAccess.open("res://data/events_v2.json", FileAccess.READ)
	if f != null:
		var v2 = JSON.parse_string(f.get_as_text())
		if v2 is Dictionary:
			evs.append_array(v2.get("events", []))
	var by := {}
	for ev in evs:
		by[str(ev.id)] = ev
	var groups: Array = [[], [], []]
	for ev in evs:
		var id := str(ev.id)
		if CHILD.has(id):
			continue
		var g := 0 if str(ev.get("line", "")) != "" else (2 if str(ev.get("pool", "")) == "card" else 1)
		var opts: Array = []
		for k in (ev.get("options", []) as Array).size():
			opts.append(_opt(id, k, ev.options[k]))
		for cid in CHILD:
			if CHILD[cid] == id and not ALIAS.has(cid) and by.has(cid):
				for k in (by[cid].get("options", []) as Array).size():
					opts.append(_opt(cid, k, by[cid].options[k]))
		var cg := str(ev.get("cg", ""))
		groups[g].append({"id": id, "name": str(ev.get("name", id)), "text": str(ev.get("text", "")), "group": g, "cg": cg if cg != "" else id, "opts": opts})
	return groups[0] + groups[1] + groups[2]


static func _opt(id: String, k: int, o: Dictionary) -> Dictionary:
	return {"key": "%s:%d" % [id, k], "label": str(o.get("label", "")), "desc": str(o.get("desc", ""))}


static func _log() -> Dictionary:
	if not (Cfg.event_log is Dictionary):
		Cfg.event_log = {}
	for k in ["seen", "opt", "pick"]:
		if not (Cfg.event_log.get(k) is Dictionary):
			Cfg.event_log[k] = {}
	return Cfg.event_log


static func _key(k: String) -> String:
	var p := k.split(":")
	return ("%s:%s" % [ALIAS[p[0]], p[1]]) if p.size() == 2 and ALIAS.has(p[0]) else k


## 事件面板弹出：count = false 是同一件事件重弹（深蓝之心继续搜寻）；shown = 这一屏显示的选项 id（"事件:编号"）
static func note_open(ev_id: String, shown: Array, count := true) -> void:
	var lg := _log()
	if count and not CHILD.has(ev_id):
		lg.seen[ev_id] = int(lg.seen.get(ev_id, 0)) + 1
	for s in shown:
		lg.opt[_key(str(s))] = true


## 选了一项（"事件:编号"）
static func note_pick(key: String) -> void:
	var lg := _log()
	var k := _key(key)
	lg.pick[k] = int(lg.pick.get(k, 0)) + 1
	lg.opt[k] = true


static func seen_n(id: String) -> int:
	return int(_log().seen.get(id, 0))


static func opt_seen(key: String) -> bool:
	return bool(_log().opt.get(key, false))


static func pick_n(key: String) -> int:
	return int(_log().pick.get(key, 0))
