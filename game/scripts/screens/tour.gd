extends RefCounted
## 聚光框引导 + 到点小提示（协调人 10-26，用户同意方向；取代首次进局自动弹出的翻页指南，翻页指南仍在暂停菜单「指南」里）。
## 1. 聚光框引导：只在第一局（存档里 seen_intro 为假）开场结束后触发。借用 state INTRO 暂停局内，整屏压暗，依次用方框框住要讲的 HUD 元素
##    （生命值与灯火 / 移动与冲刺 / 指挥），每步一两句；点击 / 任意键下一步，右键 / ← 上一步，Esc / 「跳过引导」结束。
##    框的位置：桌面按 hud_bars / hud_banners 的固定坐标，触屏取 touch.layout()（摇杆 / 冲刺键 / 指挥键）。
## 2. 到点小提示：第一次遇到精英、第一次 Boss、灯火第一次低于 30、第一次升级选卡，各在左上角弹一个不暂停的小框（8 秒），每样只弹一次，
##    已弹过的 id 记在存档 Cfg.seen_tips；老存档（已看过旧指南）升级后不再弹。文案按 docs/76，样式按 docs/37（斜切、黄条）。
## 测试 / 录片：--tourdemo（跳过开场，直接走一遍引导，每步 2.2 秒自动下一步，存帧 rec_%05d.png 到 --shotdir，配 --fixed-fps 30）、
## --tipdemo=<id>（进局 25 帧后弹该提示并存帧）；tests/tour_test.gd 测触发与存档。

const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")
const Spotlight = preload("res://scripts/screens/spotlight.gd")
const Bal = preload("res://scripts/core/balance.gd")

const TIP_LIFE := 8.0
const DEMO_STEP_SECS := 2.2
## 小提示：id → [标题, 英文小标, 正文]
const TIPS := {
	"elite": ["精英海嗣", "ELITE", "带金色光环与血条。击败掉落源石锭，有概率掉落宝箱。"],
	"boss": ["Boss 登场", "BOSS", "Boss 在场时暂停缩圈。看清地面的预警圈再走位，冲刺中无敌。"],
	"lamp": ["灯火不足", "LAMP", "灯火低于 30：受到的伤害更多，海嗣更强。拾取灯油或点燃引航灯标补充。"],
	"levelup": ["升级", "LEVEL UP", "屏幕最上沿的紫色细条是经验，满条即升级。三选一：属性、技能或招募干员。按数字键或点击选择。"],
}

var g: Game
var active := false
var step := 0
var t := 0.0               # 当前步已过的真实秒
var skip_rect := Rect2()
var _steps: Array = []

var tip_id := ""
var tip_t := 0.0
var _queue: Array = []
var _poll := 0.0

var _demo := ""            # "tour" / 提示 id / ""
var _demo_n := 0
var _rec_i := 0
var _rec_tail := -1


func _init(game: Game) -> void:
	g = game
	for a in Cfg.dev_args():
		if a == "--tourdemo":
			_demo = "tour"
		elif a.begins_with("--tipdemo="):
			_demo = a.substr(10)


# ---------------------------------------------------------------- 聚光框引导

func demo_active() -> bool:
	return _demo != ""


func start() -> void:
	if active or g.state == Game.S.INTRO:
		return
	g.intro_back = Game.S.PLAY
	g.intro_t = 0.0
	g.state = Game.S.INTRO
	active = true
	step = 0
	t = 0.0
	_steps = _build(g.hud.size)
	if _steps.is_empty():
		finish()


## 全部步骤：{title, en, rects, text}。指挥未开（command/on = 0）时去掉第 3、4 步；队友生命关（command/hp = 0）或没有队友时去掉第 4 步
func _build(vs: Vector2) -> Array:
	var touch: bool = g.touch.active
	var out: Array = []
	out.append({"title": "生命与灯火", "en": "HEALTH · LAMP", "rects": [Rect2(70.0, 4.0, 310.0, 66.0)],
		"text": "生命值是队长的生命，归零即探索失败。灯火受击时下降，低于 30 时受到的伤害更多；拾取灯油、点燃引航灯标补充。"})
	if touch:
		var lay: Dictionary = g.touch.layout(vs)
		var sr: float = g.touch.stick_r() * 1.25
		var dr: float = g.touch.BTN * 0.7 * float(lay.dash.s) + 6.0
		out.append({"title": "移动与冲刺", "en": "MOVE", "text": "按住左半屏拖动移动；点冲刺键冲刺，冲刺中无敌。",
			"rects": [Rect2(lay.stick.c - Vector2(sr, sr), Vector2(sr, sr) * 2.0), Rect2(lay.dash.c - Vector2(dr, dr), Vector2(dr, dr) * 2.0)]})
	else:
		out.append({"title": "移动与冲刺", "en": "MOVE", "text": "WASD 移动，空格冲刺，冲刺中无敌。", "rects": [Rect2(vs / 2.0 - Vector2(64.0, 88.0), Vector2(128.0, 150.0))]})
	if g.squad.cmd_on():
		var crect: Rect2
		var ctext: String
		if touch:
			var ce: Dictionary = g.touch.layout(vs).cmd
			var cr: float = g.touch.BTN / 2.0 * float(ce.s) + 6.0
			crect = Rect2(ce.c - Vector2(cr, cr), Vector2(cr, cr) * 2.0)
			ctext = "点「指挥」键打开指挥圆盘：队形（随行 / 突击 / 归队）与队友的索敌偏好。突击时队友离队索敌，耐力耗尽自动归队。"
		else:
			var y: float = g.hud_view.squad.squad_top(vs) - 38.0
			crect = Rect2(vs.x - 306.0, y - 8.0, 296.0, 46.0)
			ctext = "按 F（手柄 LB）打开指挥圆盘：队形（随行 / 突击 / 归队）与队友的索敌偏好。突击时队友离队索敌，耐力耗尽自动归队。"
		out.append({"title": "指挥", "en": "COMMAND", "rects": [crect], "text": ctext})
		# 队友生命（10-28 用户「开局指引的时候记得把他们的血条也得框一下」）：队友生命开（command/hp）且有队友时才出；框跟着血条样式走（hud_allyhp.guide_rect）
		var hr: Rect2 = g.hud_view.allyhp.guide_rect(vs) if g.squad.hp_on() else Rect2()
		if hr.has_area():
			var where: String = ["编队卡下方", "编队卡下方", "队友头顶", "左侧", "队长生命值下方"][clampi(int(Bal.v("command/hpbar_style", 0.0)), 0, 4)]
			out.append({"title": "队友生命", "en": "SQUAD HP", "rects": [hr],
				"text": where + "是队友的生命。突击中队友会受伤，生命归零即倒地，%d 秒后原地复活；队长站到倒地的队友身边，复活快 %d 倍。" % [int(Bal.v("command/revive_secs", 25.0)), int(Bal.v("command/revive_near_k", 4.0))]})
	return out


func finish() -> void:
	if not active:
		return
	active = false
	Cfg.seen_intro = true
	Cfg.save()
	if g.state == Game.S.INTRO:
		g.state = Game.S.PLAY
	Sfx.play("ui_ok", -4.0)
	if _demo == "tour":
		_rec_tail = 24


func next() -> void:
	if not active:
		return
	step += 1
	t = 0.0
	if step >= _steps.size():
		finish()
	else:
		Sfx.play("ui_move")


func prev() -> void:
	if active and step > 0:
		step -= 1
		t = 0.0
		Sfx.play("ui_move")


## 输入（game._input 在 state INTRO 且 active 时转进来）；返回 true = 已处理
func input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_ESCAPE:
				finish()
			KEY_LEFT, KEY_A, KEY_PAGEUP, KEY_BACKSPACE:
				prev()
			_:
				next()
		return true
	if event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = g.hud.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			prev()
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if skip_rect.has_point(mp) and event.button_index == MOUSE_BUTTON_LEFT:
				finish()
			else:
				next()
		return true
	return false


# ---------------------------------------------------------------- 每帧（game._process 真实 delta）

func update(dt: float) -> void:
	if active:
		t += dt
	_demo_update(dt)
	if active:
		return
	if tip_id != "":
		tip_t += dt
		if tip_t >= TIP_LIFE:
			tip_id = ""
	if tip_id == "" and not _queue.is_empty():
		tip_id = _queue.pop_front()
		tip_t = 0.0
	if not _eligible():
		return
	_poll += dt
	if _poll < 0.5:
		return
	_poll = 0.0
	if g.state == Game.S.CHOICE:
		if g.choice_kind == "level":
			show_tip("levelup")
		return
	if g.state != Game.S.PLAY:
		return
	if g.lamp < 30.0 and g.t > 15.0:
		show_tip("lamp")
	if g.spawner.boss_alive():
		show_tip("boss")
	if not Cfg.seen_tips.has("elite"):
		for e in g.enemies:
			if e.get("elite", false) and not e.dead and not e.get("chest", false) and e.pos.distance_to(g.ppos) < 600.0:
				show_tip("elite")
				break


## 只在真人对局里弹（测试 / 批跑 / 演练 / 图鉴演示 / 练习都不弹）
func _eligible() -> bool:
	return g != null and g.mode == g.Mode.PLAY and not g.trial.active and g.demo_op == "" and not Cfg.practice_active


## 排队弹一个提示（每样只弹一次：弹的同时记进存档）。force = 演示用，不查不记
func show_tip(id: String, force := false) -> void:
	if not TIPS.has(id):
		return
	if not force:
		if Cfg.seen_tips.has(id):
			return
		Cfg.seen_tips.append(id)
		Cfg.save()
	if tip_id == "":
		tip_id = id
		tip_t = 0.0
	else:
		_queue.append(id)


# ---------------------------------------------------------------- 画

func draw(vs: Vector2) -> void:
	if not active or _steps.is_empty():
		return
	var st: Dictionary = _steps[mini(step, _steps.size() - 1)]
	var touch: bool = g.touch.active
	skip_rect = Spotlight.draw(g.hud, g.font, vs, st.rects, {"idx": step, "n": _steps.size(), "en": st.en, "title": st.title, "text": st.text, "touch": touch,
		"e": _ease(clampf(t / 0.28, 0.0, 1.0)), "t": t, "hint": Pad.hint("点击 / 任意键：下一步　右键 / ←：上一步", "Ⓐ：下一步　Ⓑ：跳过", "点击：下一步")})


## 到点小提示：左上角（生命 / 灯火条下方）斜切小框 + 黄条，滑入 / 淡出；不拦输入
func draw_tip(vs: Vector2) -> void:
	if tip_id == "" or active or not TIPS.has(tip_id):
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var info: Array = TIPS[tip_id]
	var a: float = clampf(tip_t / 0.25, 0.0, 1.0) * clampf((TIP_LIFE - tip_t) / 0.45, 0.0, 1.0)
	var pw: float = minf(vs.x - 32.0, 340.0)
	var fsz := 14
	var lines: PackedStringArray = UI.wrap_lines(font, info[2], fsz, pw - 40.0)
	var lh: float = font.get_height(UI.fs(fsz)) + 2.0
	var ph: float = 56.0 + lines.size() * lh + 12.0
	var pr := Rect2(Vector2(16.0 - (1.0 - _ease(clampf(tip_t / 0.25, 0.0, 1.0))) * 40.0, 112.0), Vector2(pw, ph))
	UI.panel(hud, pr, Color(UI.BG2.r, UI.BG2.g, UI.BG2.b, 0.95 * a), Color(1, 1, 1, 0.16 * a), 10.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a))
	hud.draw_rect(Rect2(pr.position + Vector2(0, 10), Vector2(4, ph - 20)), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a))
	UI.en(hud, font, pr.position + Vector2(20, 22), "TIP  ·  %s" % info[1], 10, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a), 2.5)
	UI.text(hud, font, pr.position + Vector2(20, 46), info[0], 18, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	var asc: float = font.get_ascent(UI.fs(fsz))
	for i in lines.size():
		hud.draw_string(font, Vector2(pr.position.x + 20, pr.position.y + 54.0 + asc + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), Color(0.85, 0.93, 0.95, a))


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


# ---------------------------------------------------------------- 测试 / 录片（--tourdemo / --tipdemo=<id>）

func _demo_update(_dt: float) -> void:
	if _demo == "":
		return
	_demo_n += 1
	var shot: bool = DisplayServer.get_name() != "headless"
	if _demo_n == 25:
		if _demo == "tour":
			start()
		else:
			show_tip(_demo, true)
	if _demo_n >= 25 and shot:
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/rec_%05d.png" % _rec_i)
		_rec_i += 1
	if _demo == "tour":
		if active and t >= DEMO_STEP_SECS:
			next()
		if _rec_tail > 0:
			_rec_tail -= 1
			if _rec_tail == 0:
				g.get_tree().quit()
	elif _demo_n > 25 and tip_id == "":
		g.get_tree().quit()
