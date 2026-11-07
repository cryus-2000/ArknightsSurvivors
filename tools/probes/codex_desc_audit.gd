extends SceneTree
## 图鉴干员说明清点（11-07 用户「不是每个干员都是有文字描述，格雷迪娅和归溟幽灵鲨就没有」）：
## 对每名干员，按图鉴技能 / 成长页的版式算每行收着时留给说明的高度——旧规则（放不下就平分，overflow = false）与
## 新规则（每行至少标题 + 一行、整列滚动，overflow = true）各算一遍；同时查数据字段（说明是否为空、是否有未填的 {…} 占位）。
## 用法：godot --headless --path game -s ../tools/probes/codex_desc_audit.gd（结果打印 AUDIT 行 + 末尾 AUDIT_JSON）
func _initialize() -> void:
	var title = load("res://main.tscn").instantiate()
	root.add_child(title)
	await process_frame
	var gal = title.gallery
	gal.open()
	await process_frame
	var out: Array = []
	for ph in [false, true]:
		root.get_node("Cfg")._touch = 1 if ph else 0
		for e in gal.entries:
			if not e.has("op"):
				continue
			var cd: Dictionary = e.op
			var rows: Array = gal._skill_rows(cd)
			var w: float = (730.0 - 504.0) if ph else (1244.0 - 932.0)
			var dw: float = w - (16.0 if ph else 24.0)
			var hh: float = 28.0 if ph else (34.0 if rows.size() > 5 else 46.0)
			var gap: float = 4.0 if ph else 6.0
			var top: float = (72.0 + 38.0) if ph else (130.0 + 46.0)
			var avail: float = (352.0 if ph else 696.0) - top
			var big3: Array = []
			for ri in rows.size():
				if str(rows[ri][0]).begins_with("ULTIMATE") or str(rows[ri][0]).begins_with("LINK"):
					big3.append(ri)
			var descs: Array = rows.map(func(r): return str(r[7]))
			gal.row_sel = -1
			var old: Array = gal._row_heights(descs, avail, hh, gap, dw, ph, big3, false)
			var neu: Array = gal._row_heights(descs, avail, hh, gap, dw, ph, big3, true)
			var hidden_old: Array = []
			var hidden_new: Array = []
			var thr: float = 8.0 if ph else 10.0
			for i in rows.size():
				if float(old[i]) - hh - 4.0 < thr:
					hidden_old.append(str(rows[i][1]))
				if float(neu[i]) - hh - 4.0 < thr:
					hidden_new.append(str(rows[i][1]))
			var empty: Array = []
			var unfilled: Array = []
			for r in rows:
				if str(r[7]).strip_edges() == "":
					empty.append(str(r[1]))
				if "{$" in str(r[7]) or "{$" in str(r[8]):
					unfilled.append(str(r[1]))
			for nd in cd.get("progression", []):
				if nd is Dictionary:
					if str(nd.get("desc", "")).strip_edges() == "":
						empty.append("成长:" + str(nd.get("name", "")))
					if "{$" in str(nd.get("desc", "")):
						unfilled.append("成长:" + str(nd.get("name", "")))
			var prof: Array = gal._op_profile(str(e.id), cd, true)
			var rec := {"id": e.id, "name": e.name, "phone": ph, "rows": rows.size(), "hidden_old": hidden_old, "hidden_new": hidden_new,
				"empty": empty, "unfilled": unfilled, "profile_paras": prof.size(), "has_lore": gal.lore.has(e.id)}
			out.append(rec)
			print("AUDIT ", JSON.stringify(rec))
	print("AUDIT_JSON ", JSON.stringify(out))
	quit()
