extends RefCounted
## 新手引导（docs/219，11-01 用户改口径）：问一次 + 1–2 分钟演示局 + 正式局里第一次碰到时弹提示卡（带实时小演示）。取代首局聚光框引导。
## 1. 问一次：首局开场结束后（intro.end_opening）暂停局内弹问题框「玩过《吸血鬼幸存者》这类游戏吗？」玩过 / 没玩过 / 跳过引导，
##    结果存 Cfg.onboard（"" 未问 / new / vet / off），设置「操作 · 新手引导」可改。
## 2. 没玩过（new）：先走演示局（drill）——移动与自动攻击 → 捡经验升级三选一（身边放经验结晶）→ 招募一名队友（直接弹招募画面）
##    → 放一次终结技（直接充满）→「演示结束」，2.5 秒后重开进正式局（同一套开局配置）。演示局怪少（onboard/density）、敌伤低（onboard/enemy_dmg），
##    最晚 onboard/drill_max 秒强制结束；每张卡的「跳过演示」直接进正式局。
## 3. 正式局（两条线共用）：灯火 / 商人 / Boss / 小队与队长 / 指挥圆盘 / 终结技 / 连携 / 溟痕与引航灯标 / 节点卡，第一次碰到时弹提示卡。
## 每张卡只出一次（Cfg.onboard_seen）。卡片不暂停、不拦输入（只拦「跳过」按钮），只在 PLAY 状态显示。演示图鉴：暂停菜单「演示」，←/→ 翻全部卡。
## 只在真人对局生效（机器人 / 自动测试 / 演练 / 练习 / 图鉴演示不进，同 seed 不变）。
## 强制（docs/219 §6，11-02 用户「第一把开局的指南设置成不能跳过」）：本机和云存档都没有完成记录（Cfg.onboard_done）时，两条线都走演示局
##   （没玩过 drill / 玩过 drill_vet：小队、连携、终结技、指挥圆盘），问题框不给「跳过引导」、Esc 不选、卡上没有「跳过」；
##   演示局最长 onboard/drill_max 秒。暂停菜单照常可用，中途退出不算完成，下次进来从头。走完记 onboard_done（随云存档同步），之后照常可跳过。
## 测试 / 录片：--onboard=new|vet|ask|view（自动测试局里也走引导，不读不写存档；ask = 先弹问题框，2.4 秒后自动选「没玩过」；
##   测试里演示局结束时直接退出，不重开；new / vet / ask 按第一次进游戏的强制版走，加 --onboardfree 走可跳过版；
##   强制版里机器人不会用圆盘、按 Q，到点由这里代按）、--onboarddemo=<卡 id>（进局即出该卡，常驻不收起）。文案在 data/onboard.json，演示画法在 screens/onboard_demos.gd。

const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Demos = preload("res://scripts/screens/onboard_demos.gd")
const Character = preload("res://scripts/characters/character.gd")
const LinkV2 = preload("res://scripts/run/link_v2.gd")

const INFO_SECS := 9.0       # 看完自动收起的卡（hint 为空）停留秒数
const MOVE_NEED := 450.0     # 「移动」做完：累计移动像素
const XP_DIST := 170.0       # 演示局「经验与升级」：经验结晶放在队长身边多远（拾取半径之外，要走过去）
const END_SECS := 2.5        # 演示局「演示结束」卡停留几秒后进正式局
const ACT_SECS := 40.0       # 特有系统的动作卡（指挥 / 终结技）等这么久没做也收起，不挡后面的卡
const MIN_SHOW := 4.0        # 每张卡至少显示几秒（动作做得快也让人看完一句话；期间做完的动作照算）
const GAP := 1.6             # 两张卡之间至少隔几秒
const DRILL_MIN := 2.5       # 演示局里每张卡至少显示几秒（强制部分 ≤ 90 秒，节奏紧凑）
const DRILL_GAP := 0.6       # 演示局里两张卡之间隔几秒
const PACK_N := 10          # 演示局「部署」：从一侧涌来的怪
const PACK_D := 400.0        # 这群怪离队长多远出现（屏内靠边：看得见涌来、看得见队友过去挡）
const LINK_PACK := 8         # 演示局「连携」：在队长身边放几只怪
const LINK_NUDGE := 3.0      # 演示局「连携」：这么久队长还没放出技能就直接触发连携
const LINK_WAIT := 10.0      # 演示局「连携」：充满队长技力后等这么久还没连携（附近没敌人）就往下走
const MATE_FALLBACK := ["saria", "exusiai", "texas", "silverash", "ptilopsis"]

var g: Game
var data: Dictionary = {}
var mode := ""               # 本局生效的线：new / vet / ""（不引导）
var dev := ""                # --onboard=…：测试用，不读不写存档
var demo_id := ""            # --onboarddemo=<id>
var seen_mem: Array = []     # 测试模式下的「已出过」（不进存档）
var drill := false           # 演示局进行中
var drill_left := -1.0       # 「演示结束」卡出现后的倒计时（≥ 0 时到 0 进正式局）
var forced := false          # 第一次进游戏：引导不可跳过（docs/219 §6）
var _nudged := false
var pack_dir := Vector2.RIGHT   # 演示局「部署」：怪群从哪一侧来（世界方向）
var drill_t0 := -1.0         # 演示局开始的局内时刻（强制部分时长）

var cur := ""                # 当前卡
var cur_t := 0.0             # 当前卡在 PLAY 状态下已显示的秒数
var out_id := ""             # 正在收起的卡（做完：打勾后滑出）
var out_t := -1.0
var gap_t := 0.0
var moved := 0.0
var _last_p := Vector2.INF
var ev := {}                 # 事件计数：oil / wheel
var ev0 := {}                # 当前卡开始时的事件计数
var recruit_t := -1.0        # 第一次编队 ≥ 2 人的局内时刻
var beacons0 := 0
var lv0 := 1                 # 当前卡开始时的等级（「经验与升级」：升过一级才算）
var skip_rect := Rect2()
var now := 0.0               # 真实秒（演示动画用）

var ask_on := false
var ask_sel := 1
var ask_t := 0.0
var ask_rects: Array = []
var _ask_shot := false

var view_on := false
var view_i := 0
var view_t := 0.0
var view_back := 0
var view_rects := {}


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open("res://data/onboard.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			data = d
	for a in Cfg.dev_args():
		if a.begins_with("--onboard="):
			dev = a.substr(10)
		elif a.begins_with("--onboarddemo="):
			demo_id = a.substr(14)


func _dev_arg(key: String, def: String) -> String:
	for a in Cfg.dev_args():
		if a.begins_with(key):
			return a.substr(key.length())
	return def


# ---------------------------------------------------------------- 开局

## 只在真人对局里引导（测试开关 --onboard 例外）
func eligible() -> bool:
	if dev != "" or demo_id != "":
		return true
	return g.mode == g.Mode.PLAY and not g.trial.active and g.demo_op == "" and not Cfg.practice_active


## 开场结束时调（intro.end_opening）：返回 true = 引导接管（不再弹旧的聚光框引导）
func begin() -> bool:
	if not eligible():
		return false
	if demo_id != "":
		mode = "vet"
		_show(demo_id)
		return true
	var m: String = dev if dev != "" else str(Cfg.onboard)
	forced = _first_time()
	if forced:
		if dev == "":
			m = ""   # 没走完过：不管设置里选了什么，从问题框重新开始
			for id in all_ids() + ["drill", "drill_end"]:   # 上次中途退出：演示局从头走
				Cfg.onboard_seen.erase(id)
		elif m not in ["new", "vet"]:
			m = "ask"
	if m == "view":
		open_viewer()   # --onboard=view：直接打开演示图鉴（截图用；--onboardview=<序号> 定在第几张）
		for a in Cfg.dev_args():
			if a.begins_with("--onboardview="):
				view_i = int(a.substr(14))
		return true
	if m == "" or m == "ask":
		_open_ask()
		return true
	_setup(m)
	return true


## 第一次进游戏（本机和云存档都没有完成记录）：引导强制走完
func _first_time() -> bool:
	if dev != "":
		return dev in ["new", "vet", "ask"] and not Cfg.dev_args().has("--onboardfree")
	return not Cfg.onboard_done


func _setup(m: String) -> void:
	mode = m if m in ["new", "vet"] else ""
	if dev == "":
		Cfg.seen_intro = true   # 新引导取代旧的聚光框引导
		if mode != "":
			for id in ["levelup", "lamp", "boss"]:   # 旧到点小提示里这三条由演示局 / 提示卡覆盖
				if not Cfg.seen_tips.has(id):
					Cfg.seen_tips.append(id)
		Cfg.save()
	if mode != "" and not _seen("drill"):
		_drill_on()   # 玩过 / 没玩过都走演示局（玩过 = 快速版 drill_vet）


func _drill_on() -> void:
	drill = true
	drill_t0 = g.t
	g.stats.add(&"enemy_dmg", "mult", Bal.v("onboard/enemy_dmg", 0.5), "onboard")
	g.sync_stats()


func _drill_off() -> void:
	if not drill:
		return
	drill = false
	g.stats.remove_source("onboard")
	g.sync_stats()


## 演示局的怪物密度系数（spawner.density 乘上）
func dens_k() -> float:
	return Bal.v("onboard/density", 0.5) if drill else 1.0


## 演示局「招募」这一步：升级面板按保底招募画面弹（build_guide.must_recruit）
func force_recruit() -> bool:
	return drill and cur == "recruit"


## 演示局结束：记下看过，重开进正式局（测试里直接退出）
func _drill_end() -> void:
	_mark("drill")
	if forced:
		print("ONBOARD forced_done route=%s t=%.1f real=%.1f" % [mode, g.t - drill_t0, now])
		forced = false
		if dev == "":
			Cfg.onboard_done = true   # 强制部分走完：之后照常可跳过（随云存档同步）
			Cfg.save()
	_drill_off()
	cur = ""
	drill_left = -1.0
	if dev != "":
		g.get_tree().quit()
		return
	g.get_tree().reload_current_scene()


func _seen(id: String) -> bool:
	return seen_mem.has(id) if dev != "" else Cfg.onboard_seen.has(id)


func _mark(id: String) -> void:
	if dev != "":
		if not seen_mem.has(id):
			seen_mem.append(id)
		return
	if not Cfg.onboard_seen.has(id):
		Cfg.onboard_seen.append(id)
		Cfg.save()


## 局内事件（指挥圆盘下令 "wheel"）
func note(what: String) -> void:
	ev[what] = int(ev.get(what, 0)) + 1


# ---------------------------------------------------------------- 卡片

func card(id: String) -> Dictionary:
	return data.get("cards", {}).get(id, {})


## 卡片正文按输入方式取：触屏 touch、手柄 pad（11-03：键名按输入方式显示），都没写就用键鼠的 text
func text_of(id: String, touch: bool) -> String:
	var c := card(id)
	if touch:
		return str(c.get("touch", c.get("text", "")))
	if Pad.using and c.has("pad"):
		return str(c.pad)
	return str(c.get("text", ""))


## 本局演示局的步骤（玩过 = 快速版 drill_vet）
func _drill_list() -> Array:
	return (data.get("drill_vet", []) as Array) if mode == "vet" else (data.get("drill", []) as Array)


## 演示局的步骤（不含「演示结束」）
func drill_ids() -> Array:
	return _drill_list().filter(func(x): return x != "drill_end")


## 演示图鉴列出的卡：演示局步骤 + 正式局提示卡（去重，不含「演示结束」）
func all_ids() -> Array:
	var out: Array = (data.get("drill", []) as Array).filter(func(x): return x != "drill_end")
	for id in data.get("tips", []):
		if not out.has(id):
			out.append(id)
	return out


## 当前该轮询的卡：演示局只走演示步骤，正式局走提示卡
func _queue_ids() -> Array:
	return _drill_list() if drill else (data.get("tips", []) as Array)


## 卡能否出现（触发条件）
func _trigger(id: String) -> bool:
	var sq: int = g.squad.size()
	if drill:
		if id == "deploy" and g.ult != null and g.ult.phase != "":
			return false   # 终结技演出完再摆怪群（余波会把它清掉）
		var lst: Array = _drill_list()   # 按顺序：前面的都做完才出
		var i: int = lst.find(id)
		for k in maxi(i, 0):
			if not _seen(str(lst[k])):
				return false
		return i >= 0
	match id:
		"lamp":
			return g.lamp < 75.0 and g.t > 5.0
		"merchant":
			return not g.merchant.is_empty()
		"boss":
			return g.spawner.boss_alive()
		"squad":
			return sq >= 2
		"command":
			return g.squad.cmd_on() and sq >= 2 and recruit_t >= 0.0 and g.t - recruit_t >= 8.0
		"ult":
			return g.ult != null and g.ult.full()
		"link":
			return g.ult != null and int(g.ult.stats.get("v2_links", 0)) > 0
		"mire":
			if g.in_mire > 0.05:
				return true
			for b in g.beacons:
				if not b.get("lit", false) and not b.get("dead", false) and b.pos.distance_to(g.ppos) < 520.0:
					return true
			return false
		"nodes":
			return int(g.telemetry.nodes) > 0
	return false


## 已经不用教了：不弹，直接记成看过（演示局里招募过 → 正式局不出小队卡；没有终结技 / 招募不了 → 演示局跳过那一步）
func _moot(id: String) -> bool:
	match id:
		"squad":
			return _seen("recruit")
		"recruit":
			return drill and g.progression.recruit_cards().is_empty() and g.squad.size() < 2
		"ult":
			return drill and g.ult == null
		"link":
			return drill and (g.squad.size() < 2 or not LinkV2.on())
		"command":
			return (drill and (g.squad.size() < 2 or not g.squad.cmd_on())) or (not drill and _seen("deploy"))   # 演示局教过部署 / 随行：正式局不再出圆盘卡
		"deploy", "regroup":
			return drill and (g.squad.size() < 2 or not g.squad.cmd_on() or not g.pick.proto_on())
	return false


## 当前卡做完了吗
func _done(id: String) -> bool:
	if demo_id != "" or id == "drill_end":
		return false
	match id:
		"move":
			return moved >= MOVE_NEED
		"xp":
			return g.level > lv0
		"recruit":
			return g.squad.size() >= 2
		"merchant":
			return g.merchant.is_empty() or g.state == Game.S.SHOP
		"command":
			return int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)) or (cur_t > ACT_SECS and not drill)
		"link":
			return _links() > int(ev0.get("links", 0)) or (drill and cur_t > LINK_WAIT)
		"deploy":
			return _deployed()
		"regroup":
			return int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)) and g.squad.order_kind == "" and g.squad.stance != g.squad.ROAM
		"ult":
			return not g.ult.full() or (cur_t > ACT_SECS and not drill)
		"mire":
			return _lit_count() > beacons0 or cur_t > 25.0
	return cur_t >= INFO_SECS


## 「部署」做完：部署指令在生效（落点在怪群那一侧），且至少一名队友已经走到驻扎位上（以指令实际生效为准，点了扇区不算）
func _deployed() -> bool:
	var sq = g.squad
	if sq.order_kind != "point" or sq.order_pos == Vector2.INF or (sq.order_pos - g.ppos).dot(pack_dir) <= 40.0:
		return false
	for o in sq.ops:
		if not o.is_leader and o.pos != Vector2.INF and o.cmd_down <= 0.0 and o.pos.distance_to(sq.station_of(o)) <= 48.0:
			return true
	return false


## 指挥圆盘打开时各扇区依次亮起（command_wheel.draw 读）：演示局「部署」这一步
func wheel_tour() -> bool:
	return drill and cur == "deploy"


func _links() -> int:
	return int(g.ult.stats.get("v2_links", 0)) if g.ult != null else 0


func _lit_count() -> int:
	var n := 0
	for b in g.beacons:
		if b.get("lit", false):
			n += 1
	return n


func _show(id: String) -> void:
	cur = id
	cur_t = 0.0
	lv0 = g.level
	ev0 = ev.duplicate()
	ev0["links"] = _links()
	beacons0 = _lit_count()
	if drill and demo_id == "":
		match id:
			"xp":
				# 身边放一圈经验结晶，够升一级（走过去捡）
				var need: float = maxf(1.0, g.xp_need - g.xp) * 1.15
				for k in 5:
					var dir := Vector2.RIGHT.rotated(-0.9 + k * 0.45)
					g.pickups.drop(g.ppos + dir * (XP_DIST + k * 12.0), "xp", need / 5.0)
			"recruit":
				g.pending_levelups += 1   # 下一次升级面板按保底招募画面弹（force_recruit）
			"link":
				var ld = g.squad.leader()
				if ld != null:
					ld.fill_sp()   # 队长技力充满：自动放技能，队友接连携（羁绊搭档在队时换专属合击）
				for k in LINK_PACK:   # 身边放一圈怪：技能和连携都要有目标（演示局怪少，附近常常是空的）
					var ep: Vector2 = g.map.push_out(g.ppos + Vector2.RIGHT.rotated(TAU * k / LINK_PACK) * 210.0, 12.0)
					g.enemies.append(g.spawner.new_enemy(g.spawner.pick_type(), ep))
			"deploy":
				# 固定场景：一群怪从队长右侧（离得远就换左侧，挑地图里放得下的一边）涌来，提示部署队友阻挡
				pack_dir = Vector2.RIGHT if g.map.push_out(g.ppos + Vector2.RIGHT * PACK_D, 12.0).distance_to(g.ppos + Vector2.RIGHT * PACK_D) < 40.0 else Vector2.LEFT
				for k in PACK_N:
					var ep: Vector2 = g.ppos + pack_dir * (PACK_D + (k % 2) * 40.0) + pack_dir.orthogonal() * (k - (PACK_N - 1) / 2.0) * 34.0
					g.enemies.append(g.spawner.new_enemy(g.spawner.pick_type(), g.map.push_out(ep, 12.0)))
				if g.squad.stance == g.squad.ROAM:
					g.squad.apply_command("guard")   # 从随行开始
			"ult":
				g.ult.energy = g.ult.FULL   # 终结技直接充满
			"drill_end":
				drill_left = END_SECS
	Sfx.play("ui_move", -6.0)
	if dev != "":
		print("ONBOARD card=%s t=%.1f real=%.1f" % [id, g.t - maxf(drill_t0, 0.0), now])   # 录片 / 测试：每张卡出现的局内时刻


func _finish(skipped := false) -> void:
	if cur == "":
		return
	_mark(cur)
	out_id = cur
	out_t = 0.0 if not skipped else 0.5
	cur = ""
	gap_t = DRILL_GAP if drill else GAP
	if not skipped:
		Sfx.play("ui_ok", -6.0)


func skip_all() -> void:
	if forced:
		return   # 第一次进游戏：不可跳过
	if cur != "":
		_finish(true)
	mode = ""
	_drill_off()
	if dev == "":
		Cfg.onboard = "off"
		Cfg.save()


# ---------------------------------------------------------------- 每帧（game._process 真实 delta）

func update(dt: float) -> void:
	now += dt
	if ask_on:
		ask_t += dt
		if dev == "ask":
			if not _ask_shot and ask_t >= 1.2 and DisplayServer.get_name() != "headless":
				_ask_shot = true
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/onb_ask.png")   # 录片：问题框截图
			if ask_t >= 2.4:
				_choose(int(_dev_arg("--onboardpick=", "1")))   # 录片：--onboardpick=<序号> 选哪一项（缺省第 2 项）
		return
	if view_on:
		view_t += dt
		if dev == "view" and DisplayServer.get_name() != "headless" and view_t >= 1.6:
			# 截图：每张卡第 1.6 秒存一张 onb_view_<序号>.png，翻完退出
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/onb_view_%02d.png" % view_i)
			if view_i >= all_ids().size() - 1:
				g.get_tree().quit()
			else:
				_view_step(1)
		return
	if out_t >= 0.0:
		out_t += dt
		if out_t > 1.0:
			out_t = -1.0
			out_id = ""
	if mode == "" and cur == "":
		return
	if g.state != Game.S.PLAY:
		if cur == "merchant" and g.state == Game.S.SHOP:
			_finish()
		return
	if _last_p != Vector2.INF:
		moved += minf(g.ppos.distance_to(_last_p), 40.0)
	_last_p = g.ppos
	if recruit_t < 0.0 and g.squad.size() >= 2:
		recruit_t = g.t
	if drill_left >= 0.0:
		cur_t += dt   # 「演示结束」卡照常淡入
		drill_left -= dt
		if drill_left <= 0.0:
			_drill_end()
		return
	if drill and g.t - drill_t0 >= Bal.v("onboard/drill_max", 90.0) and cur != "drill_end":
		cur = ""
		_show("drill_end")   # 演示局拖太久：直接结束
		return
	if cur != "":
		cur_t += dt
		if forced and dev != "":
			_dev_act()
		if drill and cur == "link" and cur_t >= LINK_NUDGE and not _nudged and _links() <= int(ev0.get("links", 0)):
			_nudged = true   # 有的队长技能是蓄在下一次普攻里的（水月）或要等目标：到点按「队长放了技能」触发一次连携
			var ld = g.squad.leader()
			if ld != null and g.ult != null:
				g.ult.on_skill(ld, 0)
		if cur_t >= (DRILL_MIN if drill else MIN_SHOW) and _done(cur):
			_finish()
		return
	if gap_t > 0.0:
		gap_t -= dt
		return
	for id in _queue_ids():
		if _seen(id):
			continue
		if _moot(id):
			_mark(id)
			continue
		if _trigger(id):
			_show(id)
			return


## 录片 / 自动测试的强制版：机器人不会用圆盘、按 Q，到点代按（真人局不走这里）
func _dev_act() -> void:
	if cur_t < 1.6:
		return
	match cur:
		"ult":
			if g.ult.full() and g.ult.phase == "" and g.ult.press_q():
				g.ult.release_q()
		"command":
			if int(ev.get("wheel", 0)) <= int(ev0.get("wheel", 0)):
				g.wheel.confirm(1)   # 突击
		"deploy":
			# 打开圆盘 → 看完扇区依次亮起 → 选「部署」→ 准星挪到怪群前方 → 确认
			if g.squad.order_kind == "point":
				return
			if not g.wheel.is_open and not g.pick.active and cur_t >= 1.6 and cur_t < 2.0:
				g.wheel.open()
			elif g.wheel.is_open and g.wheel.t_open >= g.wheel.TOUR_STEP * (g.wheel.ITEMS.size() + 0.6):
				g.wheel.confirm(g.wheel.item_index("point"))
			elif g.pick.active:
				g.pick._goal = g.hud_ct() * (g.ppos + pack_dir * float(_dev_arg("--onboarddeploy=", "220"))) - g.pick._offset()   # --onboarddeploy=<距离>：录片用，部署点放远一点（撤回时触发瞬回）
				if g.pick.t >= 1.3:
					g.pick.confirm()
		"regroup":
			if int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)):
				return
			if not g.wheel.is_open and cur_t >= 1.6 and cur_t < 2.0:
				g.wheel.open()
			elif g.wheel.is_open and g.wheel.t_open >= 0.9:
				g.wheel.confirm(g.wheel.item_index("guard"))


# ---------------------------------------------------------------- 问题框

## 问题框的选项（强制时不给「跳过引导」）
func _ask_opts() -> Array:
	var opts: Array = data.get("ask", {}).get("opts", [])
	return opts.filter(func(o): return str(o[2]) != "off") if forced else opts


func modal() -> bool:
	return ask_on or view_on


func _open_ask() -> void:
	ask_on = true
	ask_t = 0.0
	ask_sel = 1
	g.intro_back = Game.S.PLAY
	g.state = Game.S.INTRO


func _choose(i: int) -> void:
	var opts: Array = _ask_opts()
	if i < 0 or i >= opts.size():
		return
	var m: String = str(opts[i][2])
	ask_on = false
	if dev == "":
		Cfg.onboard = m
		Cfg.save()
	if g.state == Game.S.INTRO:
		g.state = Game.S.PLAY
	g.combat.panel_grace()
	Sfx.play("ui_ok")
	_setup(m)


# ---------------------------------------------------------------- 演示图鉴（暂停菜单「演示」）

func open_viewer() -> void:
	view_on = true
	view_i = 0
	view_t = 0.0
	view_back = g.state
	g.state = Game.S.INTRO


func _view_step(d: int) -> void:
	var n: int = all_ids().size()
	view_i = (view_i + d + n) % n
	view_t = 0.0
	Sfx.play("ui_move")


func _view_close() -> void:
	view_on = false
	g.state = view_back
	Sfx.play("ui_ok", -4.0)


# ---------------------------------------------------------------- 输入（game._input 最前面转进来）；返回 true = 已处理

func input(event: InputEvent) -> bool:
	if not ask_on and not view_on and (cur == "" or g.state != Game.S.PLAY):
		return false
	var touch: bool = g.touch != null and g.touch.active
	var press := false
	var mp := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		press = true
		mp = (g.hud.make_input_local(event) as InputEventScreenTouch).position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not touch:
		press = true
		mp = g.hud.get_local_mouse_position()
	elif event is InputEventMouseMotion and ask_on and not touch:
		var lp: Vector2 = g.hud.get_local_mouse_position()
		for i in ask_rects.size():
			if (ask_rects[i] as Rect2).has_point(lp):
				ask_sel = i
	if ask_on:
		if event is InputEventKey and event.pressed and not event.echo:
			match Pad.kc(event):
				KEY_UP, KEY_W:
					ask_sel = posmod(ask_sel - 1, _ask_opts().size())
					Sfx.play("ui_move")
				KEY_DOWN, KEY_S, KEY_TAB:
					ask_sel = posmod(ask_sel + 1, _ask_opts().size())
					Sfx.play("ui_move")
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_choose(ask_sel)
				KEY_1, KEY_2, KEY_3:
					_choose(Pad.kc(event) - KEY_1)
				KEY_ESCAPE:
					if not forced:
						_choose(2)   # 跳过引导（第一次进游戏时 Esc 不选）
			return true
		if press:
			for i in ask_rects.size():
				if (ask_rects[i] as Rect2).has_point(mp):
					_choose(i)
					return true
		return event is InputEventMouseButton or event is InputEventScreenTouch
	if view_on:
		if event is InputEventKey and event.pressed and not event.echo:
			match Pad.kc(event):
				KEY_LEFT, KEY_A, KEY_PAGEUP:
					_view_step(-1)
				KEY_RIGHT, KEY_D, KEY_PAGEDOWN, KEY_SPACE, KEY_ENTER:
					_view_step(1)
				KEY_ESCAPE, KEY_H, KEY_BACKSPACE:
					_view_close()
			return true
		if press:
			for k in view_rects:
				if (view_rects[k] as Rect2).has_point(mp):
					match k:
						"prev":
							_view_step(-1)
						"next":
							_view_step(1)
						"close":
							_view_close()
					return true
		return event is InputEventMouseButton or event is InputEventScreenTouch
	if press and skip_rect.has_area() and skip_rect.has_point(mp) and not (forced and drill):
		if drill:
			_drill_end()   # 演示局：直接进正式局
		else:
			_finish(true)
		return true
	return false


# ---------------------------------------------------------------- 画

func _ctx() -> Dictionary:
	var lead_id: String = str(g.ch.id) if g.ch != null else "mizuki"
	var mates: Array = []
	for o in g.squad.ops:
		if o != g.ch and mates.size() < 2:
			mates.append(g.panel_ui.op_idle(str(o.id)))
	for cid in MATE_FALLBACK:
		if mates.size() >= 2:
			break
		if cid != lead_id and not g.squad.has(cid):
			var idl: Dictionary = g.panel_ui.op_idle(cid)
			if not idl.is_empty():
				mates.append(idl)
	return {"g": g, "font": g.font, "touch": g.touch != null and g.touch.active, "lead": g.panel_ui.op_idle(lead_id), "mates": mates}


## 局内提示卡（hud 每帧调）：紧凑编辑式（11-03 用户「占地太大了」）——屏宽 ≤ 约 30%、高约原来一半；
## 电脑放右侧中部（不挡战场中心、避开右上藏品与右下编队），手机放左上生命 / 灯火条下方（右侧是触屏按键）；做完打勾后滑出
func draw(vs: Vector2) -> void:
	skip_rect = Rect2()
	if ask_on or view_on or g.state != Game.S.PLAY:
		return
	var id: String = cur if cur != "" else out_id
	if id == "":
		return
	var a := 1.0
	var slide := 0.0
	var done_k := 0.0
	if cur != "":
		var e: float = Demos._e(clampf(cur_t / 0.3, 0.0, 1.0))
		a = e
		slide = 1.0 - e
	else:
		done_k = clampf(out_t / 0.25, 0.0, 1.0)
		var o: float = clampf((out_t - 0.6) / 0.3, 0.0, 1.0)
		a = 1.0 - o
		slide = Demos._e(o)
	if a <= 0.01:
		return
	var touch: bool = g.touch != null and g.touch.active
	var w: float = clampf(vs.x * (0.32 if touch else 0.3), 300.0, 420.0 if touch else 390.0)
	var pos := Vector2(16.0, 72.0) if touch else Vector2(vs.x - w - 16.0, roundf(vs.y * 0.32))
	pos.x += slide * (-40.0 if touch else 40.0)
	_card(vs, id, Rect2(pos, Vector2(w, 0.0)), now, a, done_k, cur != "", touch, false)


const PAPER := Color(0.914, 0.906, 0.882)   # 纸白 #E9E7E1（docs/222 §13 的 UI.PAPER；HUD 编辑式合入后改用令牌）
const ORANGE := Color(0.941, 0.502, 0.188)  # 橙 #F08030（只用于步骤指示与做完条件标记，docs/222 §10）
const INK := Color(0.07, 0.075, 0.085)      # 纸白上的墨色字


## 一张卡（docs/222 §10 编辑式，11-03 重做）：左边暗色演示窗（真实精灵的循环小演示），右边纸白面板——
## 小号字距大写标签（TUTORIAL / NEW）+ 粗体标题 + 标题下一根墨线 + 一句话 + 橙色小方块起头的做完条件；演示局右上一排橙色步骤点（当前带圈）。
## 去掉金边。big = 演示图鉴里的大卡（同一版式放大）。返回卡片矩形
func _card(vs: Vector2, id: String, frame: Rect2, t: float, a: float, done_k: float, live: bool, touch: bool, big: bool) -> Rect2:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var c := card(id)
	var k: float = 1.7 if big else 1.0
	var w: float = frame.size.x
	var pad: float = 10.0 * k
	var dh: float = 84.0 * k
	var dw: float = minf(roundf(dh * 1.35), w * 0.4)
	var tx_w: float = w - dw - pad * 2.0
	var fsz: int = int(round((13.0 if touch else 12.0) * k))
	var tsz: int = int(round(17.0 * k))
	var lines: PackedStringArray = UI.wrap_lines(font, text_of(id, touch), fsz, tx_w)
	var lh: float = font.get_height(UI.fs(fsz)) + 2.0
	var th: float = font.get_height(UI.fs(tsz))
	var hint: String = str(c.get("hint", ""))
	var text_h: float = pad + 10.0 * k + th + 7.0 * k + lines.size() * lh + (lh + 4.0 * k if hint != "" else 6.0 * k) + pad * 0.6
	if live and not big and drill and not forced and drill_ids().has(id):
		text_h += (26.0 if touch else 18.0) + 4.0   # 重看演示局：右下「跳过演示」占一行（右上是步骤点）
	var h: float = maxf(dh, text_h)
	var pr := Rect2(frame.position, Vector2(w, h))
	var ink := Color(INK.r, INK.g, INK.b, a)
	# 左：演示窗（暗底，真实精灵）
	var dr := Rect2(pr.position, Vector2(dw, h))
	hud.draw_rect(dr, Color(0.03, 0.04, 0.05, 0.94 * a))
	if a > 0.6:
		Demos.draw(hud, id, dr.grow(-1.0), t, _ctx())
	# 右：纸白面板
	var pp := Rect2(Vector2(dr.end.x, pr.position.y), Vector2(w - dw, h))
	hud.draw_rect(pp, Color(PAPER.r, PAPER.g, PAPER.b, 0.97 * a))
	var x0: float = pp.position.x + pad
	var y0: float = pp.position.y + pad
	var basic: Array = drill_ids()
	var step_i: int = basic.find(id) if drill and not big else -1
	var lab: String = "TUTORIAL" if step_i >= 0 or id == "drill_end" else "NEW"
	UI.en(hud, font, Vector2(x0, y0 + 7.0 * k), lab, int(round(8.0 * k)), Color(INK.r, INK.g, INK.b, 0.62 * a), 2.6)
	if step_i >= 0:   # 演示局步骤：橙色细线 + 圆点，做过的实心、当前带圈
		var n: int = basic.size()
		var gap: float = 9.0 * k
		var dx: float = pp.end.x - pad - (n - 1) * gap
		var dy: float = y0 + 4.0 * k
		hud.draw_line(Vector2(dx, dy), Vector2(dx + (n - 1) * gap, dy), Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.8 * a), 1.0)
		for q in n:
			var dp := Vector2(dx + q * gap, dy)
			hud.draw_circle(dp, 2.0 * k, Color(ORANGE.r, ORANGE.g, ORANGE.b, a) if q <= step_i else Color(PAPER.r, PAPER.g, PAPER.b, a))
			if q > step_i:
				hud.draw_arc(dp, 2.0 * k, 0.0, TAU, 10, Color(ORANGE.r, ORANGE.g, ORANGE.b, a), 1.0)
			if q == step_i:
				hud.draw_arc(dp, 4.2 * k, 0.0, TAU, 14, Color(ORANGE.r, ORANGE.g, ORANGE.b, a), 1.2)
	var ty: float = y0 + 10.0 * k + font.get_ascent(UI.fs(tsz))
	var title: String = str(c.get("title", ""))
	UI.text(hud, font, Vector2(x0, ty), title, tsz, ink)
	var tw: float = minf(tx_w, font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(tsz)).x + 6.0 * k)
	hud.draw_rect(Rect2(Vector2(x0, ty + 5.0 * k), Vector2(maxf(tw, 40.0 * k), 1.5)), ink)
	var by: float = ty + 7.0 * k + font.get_ascent(UI.fs(fsz)) + 2.0
	for i in lines.size():
		UI.text(hud, font, Vector2(x0, by + i * lh), lines[i], fsz, Color(INK.r, INK.g, INK.b, 0.86 * a))
	var hy: float = by + lines.size() * lh
	if live and not big:
		if hint != "":
			var pulse: float = 0.75 + 0.25 * sin(t * 5.0)
			hud.draw_rect(Rect2(Vector2(x0, hy - 6.0 * k), Vector2(6.0 * k, 6.0 * k)), Color(ORANGE.r, ORANGE.g, ORANGE.b, pulse * a))
			UI.text(hud, font, Vector2(x0 + 11.0 * k, hy + 1.0), hint, fsz, ink)
			if id == "move":
				var bw: float = minf(70.0 * k, tx_w * 0.3)
				var br := Rect2(Vector2(pp.end.x - pad - bw, hy - 4.0 * k), Vector2(bw, 2.0))
				hud.draw_rect(br, Color(INK.r, INK.g, INK.b, 0.15 * a))
				hud.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(moved / MOVE_NEED, 0.0, 1.0), br.size.y)), Color(ORANGE.r, ORANGE.g, ORANGE.b, a))
		else:
			var left: float = clampf(drill_left / END_SECS, 0.0, 1.0) if id == "drill_end" else clampf(1.0 - cur_t / INFO_SECS, 0.0, 1.0)
			hud.draw_rect(Rect2(Vector2(x0, pp.end.y - 4.0), Vector2(tx_w * left, 1.5)), Color(INK.r, INK.g, INK.b, 0.35 * a))
		# 跳过（只跳这一张）；第一次进游戏的演示局不给。放在纸白面板右下，不和步骤点抢位置
		if not (forced and drill):
			var skip_s: String = "跳过演示" if drill else "跳过"
			var ssz: int = 11 if not touch else 13
			var sw: float = font.get_string_size(skip_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(ssz)).x + (14.0 if not touch else 20.0)
			var sh: float = 18.0 if not touch else 26.0
			skip_rect = Rect2(Vector2(pp.end.x - sw - 6.0, pp.end.y - sh - 6.0), Vector2(sw, sh)) if step_i >= 0 else Rect2(Vector2(pp.end.x - sw - 6.0, pp.position.y + 6.0), Vector2(sw, sh))
			hud.draw_rect(skip_rect, Color(INK.r, INK.g, INK.b, 0.55 * a), false, 1.0)
			UI.text(hud, font, Vector2(skip_rect.position.x, skip_rect.get_center().y + UI.fs(ssz) * 0.36), skip_s, ssz, Color(INK.r, INK.g, INK.b, 0.8 * a), HORIZONTAL_ALIGNMENT_CENTER, skip_rect.size.x)
	# 做完：橙色圆里一个墨色勾（纸白面板右上）
	if done_k > 0.0:
		var cc: Vector2 = Vector2(pp.end.x - 16.0 * k, pp.position.y + 16.0 * k)
		var kk: float = Demos._e(done_k)
		hud.draw_circle(cc, 10.0 * kk * k, Color(ORANGE.r, ORANGE.g, ORANGE.b, a))
		hud.draw_polyline(PackedVector2Array([cc + Vector2(-5, 0) * kk * k, cc + Vector2(-1.2, 4) * kk * k, cc + Vector2(5.5, -4) * kk * k]), Color(PAPER.r, PAPER.g, PAPER.b, a), 2.0)
	return pr


## 模态（state INTRO，intro.draw 转进来）：问题框 / 演示图鉴
func draw_modal(vs: Vector2) -> void:
	if ask_on:
		_draw_ask(vs)
	elif view_on:
		_draw_view(vs)


func _draw_ask(vs: Vector2) -> void:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ask: Dictionary = data.get("ask", {})
	var opts: Array = _ask_opts()
	var e: float = Demos._e(clampf(ask_t / 0.3, 0.0, 1.0))
	var touch: bool = g.touch != null and g.touch.active
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.72 * e))
	var w: float = minf(vs.x - 32.0, 560.0)
	var oh: float = 64.0 if touch else 56.0
	var h: float = 150.0 + opts.size() * (oh + 10.0) + 20.0
	var pr := Rect2(Vector2((vs.x - w) / 2.0, (vs.y - h) / 2.0 + (1.0 - e) * 24.0), Vector2(w, h))
	UI.panel(hud, pr, Color(UI.BG2.r, UI.BG2.g, UI.BG2.b, 0.97 * e), Color(1, 1, 1, 0.16 * e), 14.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e))
	hud.draw_rect(Rect2(pr.position + Vector2(0, 14), Vector2(4, h - 28)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e))
	UI.en(hud, font, pr.position + Vector2(32, 38), str(ask.get("en", "")), 11, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e), 3.0)
	UI.text(hud, font, pr.position + Vector2(32, 72), str(ask.get("title", "")), 24, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e))
	UI.text(hud, font, pr.position + Vector2(32, 112), str(ask.get("q", "")), 17, Color(0.85, 0.93, 0.95, e))
	ask_rects = []
	for i in opts.size():
		var r := Rect2(pr.position + Vector2(32, 134 + i * (oh + 10.0)), Vector2(w - 64.0, oh))
		ask_rects.append(r)
		var hot: bool = i == ask_sel
		hud.draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.95 if hot else 0.0) * e) if hot else Color(0.03, 0.04, 0.05, 0.8 * e))
		hud.draw_rect(r, Color(1, 1, 1, (0.0 if hot else 0.28) * e), false, 1.0)
		var fg := Color(0.04, 0.07, 0.09, e) if hot else Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e)
		var sub := Color(0.04, 0.07, 0.09, 0.75 * e) if hot else Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e)
		if not touch:
			UI.keycap(hud, font, r.position + Vector2(14, oh / 2.0 - 18.0), str(i + 1), fg, 11)   # 与标题行居中对齐
		var x0: float = 50.0 if not touch else 18.0
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 - 3.0), str(opts[i][0]), 18, fg)
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 + 17.0), str(opts[i][1]), 12, sub)


func _draw_view(vs: Vector2) -> void:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var touch: bool = g.touch != null and g.touch.active
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.85))
	var ids: Array = all_ids()
	var id: String = ids[clampi(view_i, 0, ids.size() - 1)]
	var w: float = minf(vs.x - 48.0, 860.0)
	var pr: Rect2 = _card(vs, id, Rect2(Vector2((vs.x - w) / 2.0, view_top(vs)), Vector2(w, 0.0)), view_t, 1.0, 0.0, false, touch, true)
	_view_h = pr.size.y
	view_rects = {}
	var by: float = pr.end.y + 18.0
	var bh: float = 44.0 if touch else 34.0
	view_rects["prev"] = Rect2(Vector2(pr.position.x, by), Vector2(110, bh))
	view_rects["next"] = Rect2(Vector2(pr.end.x - 110.0, by), Vector2(110, bh))
	view_rects["close"] = Rect2(Vector2(vs.x / 2.0 - 60.0, by), Vector2(120, bh))
	UI.button(hud, font, view_rects.prev, "‹ 上一张", "outline", false, 14)
	UI.button(hud, font, view_rects.next, "下一张 ›", "outline", false, 14)
	UI.button(hud, font, view_rects.close, "关闭", "primary", false, 14)
	UI.en(hud, font, Vector2(pr.position.x, pr.position.y - 12.0), "DEMO  %d / %d" % [view_i + 1, ids.size()], 11, UI.CYAN, 3.0)
	if not touch:
		UI.text(hud, font, Vector2(vs.x / 2.0 - 120.0, by + bh + 28.0), "← → 翻页　Esc 关闭", 12, UI.SUB)


var _view_h := 0.0

## 演示图鉴的卡片纵向位置：按上一帧量出的高度垂直居中
func view_top(vs: Vector2) -> float:
	return maxf(40.0, (vs.y - _view_h - 70.0) / 2.0)
