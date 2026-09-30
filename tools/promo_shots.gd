extends SceneTree
## 宣传截图监视器（界面与美术 2026-09-30，tools/promo_shots.py 调用；不改游戏代码）：
## 跑确定性批跑（--balance + 机器人 + --fixed-fps 60），每帧检查六种场面，命中就存一张 1920×1080 候选：
##   boss_warn  Boss 在场且未结算预警 ≥ 3            分数 = 预警数
##   beacon     灯标点亮后 0.25–0.6 秒（光爆扩散中）    分数 = 屏内敌人数
##   levelup    升级三选一面板打开（暂停 2 帧再截）    只截前几次
##   horde      「大群来袭」横幅倒计时中               分数 = 屏内敌人数
##   ult        斯卡蒂潮汐浪墙推进中 / 水月触手群刚冒出  分数 = 屏内敌人数（+100 斯卡蒂 / +50 水月）
##   manual     --promo_manual_t（缺省 140 秒）起 20 秒临时打开手动普攻（机器人照常走位、模拟按住攻击键），截方向指示
## 每类同一类两张之间至少隔 min_gap 帧；用户参数：--promo_out=目录 --promo_maxt=秒 --promo_only=类,类 --promo_manual_t=秒
## GIF：--promo_rec=名@起始秒@时长秒@每几帧（可给多个；--promo_only=none 时只录不截）
var g: Node = null
var out := "."
var maxt := 660.0
var last := {}
var count := {}
var lv_wait := -1
var lv_ms := 0
var only := []
var manual_t := 140.0
var lit_seen := {}
var lit_at := {}
var recs := []   # [{name, t0, dur, every, n}]
const MIN_GAP := 90
const CAP := {"boss_warn": 12, "beacon": 6, "levelup": 4, "horde": 8, "ult": 10, "manual": 6}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--promo_out="):
			out = a.substr(12)
		if a.begins_with("--promo_maxt="):
			maxt = float(a.substr(13))
		if a.begins_with("--promo_manual_t="):
			manual_t = float(a.substr(17))
		if a.begins_with("--promo_rec="):
			var sp: PackedStringArray = a.substr(12).split("@")
			recs.append({"name": sp[0], "t0": float(sp[1]), "dur": float(sp[2]), "every": int(sp[3]), "n": 0})
			DirAccess.make_dir_recursive_absolute(out + "/rec_" + sp[0])
		if a.begins_with("--promo_only="):
			only = Array(a.substr(13).split(","))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file.call_deferred("res://game.tscn")


func _on_screen(p: Vector2) -> bool:
	var ct: Transform2D = g.get_viewport().get_canvas_transform()
	var sp: Vector2 = ct * p
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	return sp.x > 40 and sp.y > 40 and sp.x < vs.x - 40 and sp.y < vs.y - 40


func _enemies_on_screen() -> int:
	var n := 0
	for e in g.enemies:
		if not e.dead and _on_screen(e.pos):
			n += 1
	return n


func _shot(cat: String, score: float) -> void:
	if not only.is_empty() and not (cat in only):
		return
	var f: int = Engine.get_process_frames()
	if f - int(last.get(cat, -99999)) < MIN_GAP or int(count.get(cat, 0)) >= int(CAP[cat]):
		return
	last[cat] = f
	count[cat] = int(count.get(cat, 0)) + 1
	var fn := "%s/%s_%05d_s%03d_t%04d.png" % [out, cat, f, int(score), int(g.t)]
	g.get_viewport().get_texture().get_image().save_png(fn)
	print("PROMO ", cat, " f=", f, " t=", snappedf(g.t, 0.1), " score=", score)


func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g):
			g = null
			return false
	# GIF 录制：窗口内每 every 帧存一张（python 端缩到 640 宽、拼 GIF）
	for r in recs:
		if g.t >= float(r.t0) and g.t < float(r.t0) + float(r.dur) and Engine.get_process_frames() % int(r.every) == 0:
			g.get_viewport().get_texture().get_image().save_png("%s/rec_%s/f%04d.png" % [out, r.name, int(r.n)])
			r.n = int(r.n) + 1
	if g.t > maxt:
		print("PROMO done ", count)
		quit()
		return false
	# 升级面板：打开后暂停、等卡片入场排好再截，然后恢复（机器人随后照常选卡）
	if lv_wait >= 0:
		g.panel_ui.animate_cards(1.0 / 60.0)   # 卡片淡入 / 入场在 game._process 里推进，暂停时手动推；错开入场按真实时间算，等 0.9 秒
		if Time.get_ticks_msec() - lv_ms > 900:
			lv_wait = -1
			_shot("levelup", 0)
			paused = false
		return false
	if g.state != g.S.PLAY and not (g.panel.visible and int(count.get("levelup", 0)) < int(CAP.levelup)):
		return false
	if g.panel.visible and int(count.get("levelup", 0)) < int(CAP.levelup) and Engine.get_process_frames() - int(last.get("levelup", -99999)) >= MIN_GAP:
		paused = true
		lv_wait = 1
		lv_ms = Time.get_ticks_msec()
		return false
	if g.state != g.S.PLAY:
		return false
	# Boss 预警密集
	var boss_on := false
	for b in g.bosses:
		if not b.dead and _on_screen(b.pos):
			boss_on = true
	if boss_on:
		var nw := 0
		for w in g.warns:
			if not w.done:
				nw += 1
		if nw >= 3:
			_shot("boss_warn", nw)
	# 灯标点亮的一刻：记下变亮的时刻，0.25–0.6 秒内截（点亮光爆正在扩散）
	var bs = g.get("beacons")
	if bs is Array:
		for i in bs.size():
			var b: Dictionary = bs[i]
			var key: String = str(b.get("pos", Vector2.ZERO))
			if b.get("lit", false) and not lit_seen.get(key, false):
				lit_at[key] = g.t
			lit_seen[key] = b.get("lit", false)
			if lit_at.has(key):
				var dt: float = g.t - float(lit_at[key])
				if dt > 0.25 and dt < 0.6 and _on_screen(b.get("pos", Vector2.ZERO)):
					_shot("beacon", _enemies_on_screen())
				elif dt >= 0.6:
					lit_at.erase(key)
	# 大群来袭
	if g.horde_warn > 0.6 and g.horde_warn < 2.6:
		_shot("horde", _enemies_on_screen())
	# 水月 / 斯卡蒂大招瞬间：斯卡蒂潮汐中且浪墙在推（tide > 0、waves 非空）；水月触手群帧条刚冒出
	for o in g.squad.ops:
		if g.lamp < 40.0:
			break   # 灯火快灭时画面整片压暗，不截
		if o.id == "skadi" and float(o.get("tide")) > 0.0 and not (o.get("waves") as Array).is_empty():
			_shot("ult", 100 + _enemies_on_screen())
	for f in g.fx:
		if f.get("name", "") == "fx_mizuki_tentacle_mass" and float(f.max) - float(f.life) > 0.1 and float(f.max) - float(f.life) < 0.35:
			_shot("ult", 50 + _enemies_on_screen())
			break
	# 手动普攻方向指示：manual_t 起 20 秒临时打开（缺省 2:20，场面不太乱、箭头看得清；模拟按住攻击键，不用鼠标瞄准 = 按走位方向 / 朝向）
	if g.t >= manual_t and g.t < manual_t + 20.0:
		g.doctor.manual_attack = true
		g.doctor.sim_atk = true
		g.doctor._mouse_t = -99.0
		if g.t > manual_t + 2.0:
			_shot("manual", _enemies_on_screen())
	elif g.t >= manual_t + 20.0 and g.doctor.manual_attack:
		g.doctor.manual_attack = false
		g.doctor.sim_atk = false
	return false
