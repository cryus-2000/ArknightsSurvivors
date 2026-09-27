extends RefCounted
## 仅正式游玩的可见遭遇写入图鉴；演练、演示和自动测试不推进进度。
static func observe(g) -> void:
	if g.demo_op != "" or g.trial.active or g.autotest or Cfg.practice_active or Cfg.unlock_all:
		return
	var found: Array = []
	for e in g.enemies:
		if not e.dead and e.pos.distance_to(g.ppos) < 550.0:
			found.append("enemy:" + str(e.type))
	var names := {"xp": "EXP", "oil": "OIL", "gold": "INGOT", "ingot": "INGOT", "magnet": "MAGNET", "heal": "HEAL", "chest": "CHEST"}
	for item in g.gems:
		if item.pos.distance_to(g.ppos) < 350.0 and names.has(item.kind):
			found.append("item:" + names[item.kind])
	var props := {"prop_pillar": "PILLAR", "prop_wall": "RUINED WALL", "prop_wreck": "WRECK", "terrain_ridge": "RIDGE", "terrain_peak": "PEAK"}
	if g.map != null:
		for prop in g.map.sort_props:
			if props.has(prop[0]) and prop[1].distance_to(g.ppos) < 350.0:
				found.append("item:" + props[prop[0]])
	for mire in g.mires:
		if mire.pos.distance_to(g.ppos) < 350.0:
			found.append("item:MIRE")
	if not g.merchant.is_empty() and g.merchant.pos.distance_to(g.ppos) < 350.0:
		found.append("item:MERCHANT")
	var changed := false
	for key in found:
		if not Cfg.gallery_seen.has(key):
			Cfg.gallery_seen.append(key)
			changed = true
	if changed:
		Cfg.save()
