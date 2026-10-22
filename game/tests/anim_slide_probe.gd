extends Node
## 10-22 攻击后滑步 / 卡末帧探针（用户反馈：星熊、歌蕾蒂娅等攻击后停在最后一个攻击帧然后跑步平移）：
## 正常跑一局（--balance --bot=expert），逐帧取队长 anim_state()，统计
##   slide：画面还是出手帧条、且出手帧已过（收势）或窗口已结束、同时在移动（mv > 40）的帧数
##   stuck：出手帧条停在末帧连续 ≥ 8 帧（约 0.13 秒）的次数
##   atk：画面是出手帧条的总帧数（分母）
## 用法：tools/probes/anim_slide_probe.py [--game <目录>] [--ops a,b] [--t 40]；本脚本只读，不改任何模拟量。

func _ready() -> void:
	var probe_t := 40.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-t="): probe_t = float(arg.get_slice("=", 1))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)   # 批跑模式一帧跑多步，改成自己按 1/60 秒逐步推进、每步取样
	var slide := 0
	var stuck := 0
	var atk := 0
	var frames := 0
	var last_run := 0
	var seen := {}
	var by := {}   # 帧条 → [slide, stuck]
	while true:
		g._update(1.0 / 60.0)
		if frames % 120 == 0:
			await get_tree().process_frame
		if g.ch == null or g.ch.pos == Vector2.INF:
			frames += 1
			continue
		var o = g.ch
		frames += 1
		var st: Dictionary = o.anim_state()
		var kind := str(st.get("kind", ""))
		var act := str(o.act_anim)
		var is_atk := kind == act and act != "" and act != "idle" and act != "run"
		if is_atk:
			atk += 1
			seen[kind] = true
			if not by.has(kind): by[kind] = [0, 0]
			var elapsed: float = float(o.attack_dur) - float(o.attack_t)
			var recovering: bool = float(o.attack_t) <= 0.0 or elapsed >= float(o.attack_fire_at)
			if recovering and float(o.mv) > 40.0:
				slide += 1
				by[kind][0] += 1
			if int(st.get("frame", -1)) == int(st.get("hf", 0)) - 1:
				last_run += 1
				if last_run == 8:
					stuck += 1
					by[kind][1] += 1
			else:
				last_run = 0
		else:
			last_run = 0
		if float(g.t) >= probe_t:
			break
	print("ANIMPROBE op=%s frames=%d atk=%d slide=%d stuck=%d by=%s" % [str(g.ch.id) if g.ch != null else "?", frames, atk, slide, stuck, JSON.stringify(by)])
	get_tree().quit()
