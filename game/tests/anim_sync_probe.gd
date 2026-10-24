extends Node
## 10-24 干员动作对时审计探针（docs/140）：正常跑一局（--balance --bot=expert，单干员），按 1/60 秒逐步推进，逐帧记
##   START   起手（attack_t 跳升）：动作帧条、逻辑类型、窗口时长 attack_dur、出手时刻 attack_fire_at、普攻间隔 cd
##   REL     出手（fire_t 走到 -1）：这一帧画面上的帧条 / 帧号，与帧条声明的出手帧 fire 比
##   DMG     dmg_out 按来源的增量（伤害真正结算的时刻；远程含飞行时间）
##   SHOT    新弹体（g.bullets 新增）
##   RUN     跑步帧：移速 mv、跑步相位推进（有效 fps）
##   CUT     出手动作画面提前让位（act_anim_yield，收势被跑步截掉）
##   SEQMV   移动中（mv > 40）画面是技能序列的非跑动段（定格 / 循环 / 起手 / 收势）：腿不动 = 原地滑行，按帧条计
## 只读：不改任何模拟量。输出一行 ANIMSYNC <json>，由 tools/probes/anim_sync_probe.py 汇总成表。

func _ready() -> void:
	var probe_t := 60.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-t="): probe_t = float(arg.get_slice("=", 1))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	var dt := 1.0 / 60.0
	var ev: Array = []
	var prev_at := 0.0
	var prev_ft := -1.0
	var prev_dmg := {}
	var seen_b: Array = []
	var run_ticks := 0
	var run_mv := 0.0
	var run_adv := 0.0
	var run_clamp_lo := 0
	var run_clamp_hi := 0
	var mov_atk_ticks := 0
	var mov_atk_swap := 0
	var cut_ticks := 0
	var run_resets := 0
	var seq_mv := {}
	var frames := 0
	while true:
		var o = g.ch
		var ph0: float = float(o.run_ph) if o != null else 0.0
		g._update(dt)
		frames += 1
		if frames % 120 == 0:
			await get_tree().process_frame
		o = g.ch
		if o == null or o.pos == Vector2.INF:
			continue
		var t: float = float(g.t)
		var st: Dictionary = o.anim_state()
		var kind := str(st.get("kind", ""))
		var fr := int(st.get("frame", -1))
		var at: float = float(o.attack_t)
		var ft: float = float(o.fire_t)
		if at > prev_at + 0.000001:
			var spec: Dictionary = o.sprite_spec(str(o.act_anim))
			ev.append({"e": "START", "t": t, "anim": str(o.act_anim), "kind": str(o.act_kind), "dur": float(o.attack_dur), "fire_at": float(o.attack_fire_at),
				"cd": float(o.get("cd")) if o.get("cd") != null else -1.0, "phased": bool(o.attack_phased), "fire": int(spec.get("fire", -1)), "frames": int(spec.get("frames", st.get("hf", 0))),
				"fps": float(spec.get("fps", 0.0)), "fd": spec.has("frame_durations"), "prev_left": prev_at, "shown": kind, "f": fr, "sq": str(o.get("sq_atk")) if o.get("sq_atk") != null else ""})
		if prev_ft >= 0.0 and ft < 0.0:
			var spec2: Dictionary = o.sprite_spec(str(o.act_anim))
			ev.append({"e": "REL", "t": t, "anim": str(o.act_anim), "kind": str(o.act_kind), "shown": kind, "f": fr, "hf": int(st.get("hf", 0)), "fire": int(spec2.get("fire", -1)),
				"elapsed": float(o.attack_dur) - at, "fire_at": float(o.attack_fire_at), "dur": float(o.attack_dur)})
		# 伤害结算
		var dd: Dictionary = g.dmg_out
		for k in dd:
			var v: float = float(dd[k])
			if v > float(prev_dmg.get(k, 0.0)) + 0.0001:
				ev.append({"e": "DMG", "t": t, "src": str(k), "v": v - float(prev_dmg.get(k, 0.0)), "shown": kind, "f": fr})
			prev_dmg[k] = v
		# 新弹体
		var nb := 0
		var keep: Array = []
		for b in g.bullets:
			keep.append(b)
			var found := false
			for s in seen_b:
				if is_same(s, b):
					found = true
					break
			if not found:
				nb += 1
		seen_b = keep
		if nb > 0:
			ev.append({"e": "SHOT", "t": t, "n": nb, "shown": kind, "f": fr})
		# 跑步
		if kind == "run":
			run_ticks += 1
			var mv: float = float(o.mv)
			run_mv += mv
			if float(o.run_ph) >= ph0:
				run_adv += float(o.run_ph) - ph0
			else:
				run_resets += 1
				run_adv += float(o.run_ph)
			var r: float = mv / 150.0
			if r < 0.6: run_clamp_lo += 1
			elif r > 2.0: run_clamp_hi += 1
		# 移动攻击
		if at > 0.0 and float(o.mv) > 40.0 and kind == str(o.act_anim):
			mov_atk_ticks += 1
			if o.anim_tex("move_" + kind) != null:
				mov_atk_swap += 1
		if at > 0.0 and o.act_anim_yield() and kind != str(o.act_anim):
			cut_ticks += 1
		if int(o.sq_ph) != 0 and float(o.mv) > 40.0 and kind != "run" and kind == o._sq_kind():
			var sr: String = o.seq_anim(o.sq.run) if o.sq.has("run") else ""
			if kind != sr:
				seq_mv[kind] = int(seq_mv.get(kind, 0)) + 1
		prev_at = at
		prev_ft = ft
		if t >= probe_t:
			break
	var o2 = g.ch
	var sp: Dictionary = o2.def.get("sprites", {}) if o2 != null else {}
	var run_spec = sp.get("run", {})
	var out := {"op": str(o2.id) if o2 != null else "?", "frames": frames, "ev": ev,
		"run": {"ticks": run_ticks, "mv": run_mv / maxf(1.0, run_ticks), "fps_eff": run_adv / maxf(0.0001, run_ticks * dt), "lo": run_clamp_lo, "hi": run_clamp_hi, "resets": run_resets,
			"fps": float(run_spec.get("fps", 10.0)) if run_spec is Dictionary else 10.0, "n": int(run_spec.get("frames", 0)) if run_spec is Dictionary else 0},
		"move_atk": {"ticks": mov_atk_ticks, "swap": mov_atk_swap}, "cut": cut_ticks, "seq_mv": seq_mv,
		"aspd": float(o2.stat(&"op_aspd")) if o2 != null else 1.0}
	print("ANIMSYNC " + JSON.stringify(out))
	get_tree().quit()
