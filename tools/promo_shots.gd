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
var lv_cat := "levelup"
var only := []
var bait := false   # --promo_stake_bait：骑士冲锋时在它前方摆一根冰枪桩（协调人允许「摆桩」），让游戏自己的撞桩逻辑触发长枪脱手
var bait_at := -99.0
var nohud := false   # --promo_nohud：整局隐藏 HUD（宣传图不露等级 / 血量等穿帮数值）
var rt_win: Array = []   # --promo_rt=起-止,起-止（游戏秒）：只在这些窗口里按真实步长跑、截图，窗口外批跑快进
var manual_t := 140.0
var lit_seen := {}
var lit_at := {}
var recs := []   # [{name, t0, dur, every, n}]
const MIN_GAP := 90
const CAP := {"boss_warn": 12, "beacon": 6, "levelup": 4, "horde": 8, "ult": 10, "manual": 6,
	"saint": 10, "hatch": 6, "stake": 8, "glow": 6, "mire": 6, "late": 8, "relic": 4}
var phase_at := {}    # Boss id → 进入二阶段的时刻（泡影破壳）
var brk_at := {}      # 骑士 id → 长枪脱手（破绽开始）的时刻


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
		if a.begins_with("--promo_rt="):
			for w in a.substr(11).split(","):
				var ab: PackedStringArray = w.split("-")
				rt_win.append([float(ab[0]), float(ab[1])])
		if a == "--promo_stake_bait":
			bait = true
		if a == "--promo_nohud":
			nohud = true
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
	if nohud and g.hud.visible:
		g.hud.visible = false
	if not rt_win.is_empty():
		var inside := false
		for w in rt_win:
			if g.t >= float(w[0]) and g.t < float(w[1]):
				inside = true
		g.realtime = inside
		if not inside:
			return false   # 快进段不截图
	if g.t > maxt:
		print("PROMO done ", count)
		quit()
		return false
	# 升级面板：打开后暂停、等卡片入场排好再截，然后恢复（机器人随后照常选卡）
	if lv_wait >= 0:
		g.panel_ui.animate_cards(1.0 / 60.0)   # 卡片淡入 / 入场在 game._process 里推进，暂停时手动推；错开入场按真实时间算，等 0.9 秒
		if Time.get_ticks_msec() - lv_ms > 900:
			lv_wait = -1
			_shot(lv_cat, 0)
			paused = false
		return false
	if g.state != g.S.PLAY and not g.panel.visible:
		return false
	var pcat: String = "relic" if str(g.get("choice_kind")) in ["relic", "event"] else "levelup"
	if g.panel.visible and (only.is_empty() or pcat in only) and int(count.get(pcat, 0)) < int(CAP[pcat]) and Engine.get_process_frames() - int(last.get(pcat, -99999)) >= MIN_GAP:
		lv_cat = pcat
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
	# 圣徒（卡门 / 伊比利亚）出招或装填时
	for b in g.bosses:
		if b.dead or not _on_screen(b.pos):
			continue
		if b.type in ["carmen", "iberia"] and (float(b.get("pose", 0.0)) > 0.0 or float(b.get("wind", 0.0)) > 0.0 or float(b.get("channel", 0.0)) > 0.0):
			_shot("saint", _enemies_on_screen())
		# 泡影：进入二阶段（破壳落地）后 0.2–0.8 秒；结茧中也截
		if b.type == "paranoia":
			if int(b.get("phase", 1)) == 2 and not phase_at.has(b.id):
				phase_at[b.id] = g.t
			if phase_at.has(b.id) and g.t - float(phase_at[b.id]) > 0.2 and g.t - float(phase_at[b.id]) < 0.8:
				_shot("hatch", 1)
			if float(b.get("cocoon_t", 0.0)) > 0.0:
				_shot("hatch", 0)
		# 骑士：冰枪桩在场时；长枪脱手（破绽开始）后 0.2–1.0 秒
		if b.type == "knight_boss" and bait and b.get("kb_self", false) and (b.kb as Vector2).length() > 100.0 and g.t - bait_at > 6.0 and b.has("stakes"):
			b.stakes.append({"pos": b.pos + (b.kb as Vector2).normalized() * 70.0, "until": g.t + 12.0})
			bait_at = g.t
		if b.type == "knight_boss":
			if float(b.get("break_t", 0.0)) > 0.0 and not brk_at.has(b.id):
				brk_at[b.id] = g.t
			elif float(b.get("break_t", 0.0)) <= 0.0:
				brk_at.erase(b.id)
			if brk_at.has(b.id) and g.t - float(brk_at[b.id]) > 0.2 and g.t - float(brk_at[b.id]) < 1.0:
				_shot("stake", 100)
			elif (b.get("stakes", []) as Array).size() >= 2 and float(b.get("pose", 0.0)) > 0.0:
				_shot("stake", 0)
	# 灯标点亮后 1–4 秒：暖光区域已经亮起
	if bs is Array:
		for b in bs:
			if b.get("lit", false) and g.t - float(b.get("lit_t", -99.0)) > 1.0 and g.t - float(b.get("lit_t", -99.0)) < 4.0 and _on_screen(b.get("pos", Vector2.ZERO)):
				_shot("glow", _enemies_on_screen())
	# 溟痕冒泡：屏幕内有 3 片以上溟痕
	var nm := 0
	for m in g.mires:
		if _on_screen(m.pos):
			nm += 1
	if nm >= 3:
		_shot("mire", nm)
	# 后期满屏怪潮
	if g.t >= 540.0:
		var ne := _enemies_on_screen()
		if ne >= 150:
			_shot("late", ne)
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
	var want_manual: bool = only.is_empty() or "manual" in only   # 不截手动指示的局不改操作方式（干净局）
	if want_manual and g.t >= manual_t and g.t < manual_t + 20.0:
		g.doctor.manual_attack = true
		g.doctor.sim_atk = true
		g.doctor._mouse_t = -99.0
		if g.t > manual_t + 2.0:
			_shot("manual", _enemies_on_screen())
	elif g.t >= manual_t + 20.0 and g.doctor.manual_attack:
		g.doctor.manual_attack = false
		g.doctor.sim_atk = false
	return false
