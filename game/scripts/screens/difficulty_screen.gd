extends RefCounted
## Approved survey screen. Visual time and selection are local; gameplay settings
## are committed only by title._diff_go after its existing unlock check.
const D = preload("res://scripts/data.gd")
const Ocean = preload("res://scripts/screens/difficulty_ocean.gd")
const COLORS := [Color("38d6f0"), Color("ffce00"), Color("ef727d")]
const BG := Color("13171e")
const INK := Color("111318")
const WHITE := Color("dfe2e6")
const MUTED := Color("969ca6")
const LINE := Color("39414e")
var ocean: RefCounted
var tier := -1
var depth := 0.0
var from_depth := 0.0
var change := 1.0
var clock := 0.0
var rules: Array = []

func tick(dt: float, selected: int, reduce: bool) -> void:
	if ocean == null:
		ocean = Ocean.new()
	if tier != selected:
		from_depth = float(selected) if tier < 0 else depth
		tier = selected
		change = 0.0
		rules = condition_lines(selected)
	change = 1.0 if reduce else minf(1.0, change + dt / 0.38)
	depth = lerpf(from_depth, float(tier), 1.0 - pow(1.0 - change, 3.0))
	if not reduce:
		clock += dt

static func condition_lines(selected: int) -> Array:
	var mods := D.dmod_for_preset(selected)
	var lines := D.dmod_lines(mods)
	# Existing summary omits beneficial beacon modifiers and late-game caps.
	for row in [["beacon_every", "灯标刷新间隔"]]:
		var value := float(mods[row[0]])
		if not is_equal_approx(value, 1.0):
			lines.append("%s %+d%%" % [row[1], roundi((value - 1.0) * 100.0)])
	if float(mods.dmg_late_cap) >= 0.0:
		lines.append("后期敌人伤害成长上限 +%d%%" % roundi(float(mods.dmg_late_cap) * 100.0))
	if float(mods.boss_fight_enemy_hp) >= 0.0:
		lines.append("终局战新增敌人生命倍率 ×%.2f" % float(mods.boss_fight_enemy_hp))
	return lines

static func geometry(vs: Vector2) -> Dictionary:
	var safe: Rect2 = Cfg.touch_safe_rect(vs)
	var k := minf(safe.size.x / 1280.0, safe.size.y / 720.0)
	return {"scale": k, "offset": safe.position + (safe.size - Vector2(1280,720) * k) * 0.5}

static func input(host: Control, event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_UP, KEY_W, KEY_LEFT, KEY_A:
				host._diff_step(-1)
			KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D:
				host._diff_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				host._diff_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				host._diff_back()
			KEY_X:
				host.transition.switch_page(host.meta_ui.open)
		return
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = host.make_input_local(event).position
	elif event is InputEventScreenTouch and event.pressed:
		pos = host.make_input_local(event).position
	else:
		return
	for key in host.diff_rects:
		if not (host.diff_rects[key] as Rect2).has_point(pos):
			continue
		if key == "go":
			host._diff_go()
		elif key == "back" or key == "top_back":
			host._diff_back()
		elif key == "growth":
			host.transition.switch_page(host.meta_ui.open)
		elif str(key).begins_with("tier"):
			host._diff_step(int(str(key).substr(4)) - host.diff_sel)
		return

## 手机横屏（10-26 用户 iPhone 实机，docs/37 最小字号）：整页按 1280×720 缩到约 0.87，10–13 号的小标只剩 6–7 pt；小字抬到 PHONE_MIN_FS
const PHONE_MIN_FS := 15

static func text(c: CanvasItem, font: Font, x: float, y: float, value: String, sz: int = 18, col: Color = WHITE, width: float = -1.0) -> void:
	var ph: bool = Cfg.phone_ui()
	var size := maxi(sz, PHONE_MIN_FS) if ph else sz
	while width > 0 and size > (13 if ph else 11) and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	c.draw_string(font, Vector2(x,y+size), value, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)

static func rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_rect(r,col)

static func rule(c: CanvasItem, y: float, x0: float, x1: float) -> void:
	c.draw_line(Vector2(x0,y),Vector2(x1,y),LINE,1)

func draw(host: Control, vs: Vector2) -> void:
	# draw may precede the first process tick in screenshot/input harnesses.
	if tier != host.diff_sel or ocean == null:
		tick(0.0, host.diff_sel, Cfg.reduce_motion)
	var g := geometry(vs)
	var k: float = g.scale
	var offset: Vector2 = g.offset
	var font: Font = host.font
	var col: Color = COLORS[tier]
	var preset: Dictionary = D.DIFF_PRESETS[tier]
	var locked := tier > Cfg.diff_unlocked
	host.draw_rect(Rect2(Vector2.ZERO,vs),BG)
	host.draw_set_transform(offset,0,Vector2(k,k))
	rect(host,Rect2(0,0,1280,48),INK)
	rule(host,46,28,1252)
	text(host,font,32,12,"‹   选择难度",18)
	text(host,font,212,19,"OPERATION / SURVEY",10,MUTED)
	text(host,font,1135,14,"返回",15)
	UI.btn_key(host,font,Rect2(1175,12,60,24),"" if Pad.using else "ESC", MUTED, 10, 0.0)   # 10-31 TA H7：键名不夹在按钮文字里，「返回」右边一个按键牌
	rect(host,Rect2(0,48,267,606),WHITE)
	text(host,font,30,78,"探索深度",36,INK)
	text(host,font,32,132,"DEPTH / SELECT",12,Color("5c616a"))
	text(host,font,32,185,"难度档位",13,Color("5c616a"))
	host.draw_line(Vector2(58,239),Vector2(58,559),Color("9da5ae"),2)
	for y in range(239,560,10):
		host.draw_line(Vector2(48,y),Vector2(58,y),Color("9da5ae"),2)
	var hits := {"back": Rect2(20,664,200,48), "top_back": Rect2(1100,0,160,46), "growth":Rect2(290,664,250,48), "go":Rect2(915,666,337,46)}
	for i in D.DIFF_PRESETS.size():
		var y := 251 + i*135
		var active := i == tier
		var unavailable := i > Cfg.diff_unlocked
		hits["tier%d" % i] = Rect2(20,y-35,230,110)
		if active:
			rect(host,Rect2(20,y-35,230,110),INK)
			rect(host,Rect2(20,y-35,4,110),COLORS[i])
			text(host,font,38,y-17,"%02d" % (i+1),40,COLORS[i])
			text(host,font,106,y-13,D.DIFF_PRESETS[i].name,29)
			text(host,font,108,y+26,D.DIFF_PRESETS[i].en,11,COLORS[i])
		else:
			rect(host,Rect2(51,y-4,14,14),Color("887177") if unavailable else Color("347e8a"))
			text(host,font,90,y-18,D.DIFF_PRESETS[i].name,27,Color("5c616a"))
			text(host,font,92,y+20,D.DIFF_PRESETS[i].en,10,Color("7c828b"))
		if unavailable:
			for stripe in 5:
				host.draw_line(Vector2(214+stripe*6,y-26),Vector2(202+stripe*6,y-14),Color(0.55,0.57,0.6,0.3),1)
			text(host,font,94,y+48,"LOCKED / 通关%s" % D.DIFF_PRESETS[i-1].name,11,MUTED if active else Color("5c616a"))
	text(host,font,32,617,Pad.hint("↑ ↓  选择档位", "十字键  选择档位", "点击档位切换"),13,Color("5c616a"))
	text(host,font,302,82,"%02d" % (tier+1),17,col)
	text(host,font,346,77,preset.name,33)
	text(host,font,304,130,preset.en+" / OPERATION CONDITIONS",11,MUTED)
	text(host,font,738,66,"%02d" % (tier+1),88,Color("2b3542"))
	rule(host,169,302,865)
	text(host,font,305,188,"海域剖面",11,MUTED)
	text(host,font,688,188,["海面 / SURFACE","深水 / DEEP WATER","海渊 / ABYSS"][tier],10,MUTED)
	host.draw_set_transform(offset+Vector2(302,218)*k,0,Vector2(k*2,k*2))
	ocean.draw(host,tier,depth,0.0 if Cfg.reduce_motion else clock,change,col)
	host.draw_set_transform(offset,0,Vector2(k,k))
	var hint: String = "通关「%s」后解锁" % D.DIFF_PRESETS[maxi(0,tier-1)].name if locked else ["没有额外规则。","通关「%s」后解锁%s" % [D.DIFF_PRESETS[1].name, D.DIFF_PRESETS[2].name],"Boss 在场时大群照常来袭。"][tier]
	text(host,font,305,562,hint,15,MUTED)
	text(host,font,305,602,"结算系数",13,MUTED)
	text(host,font,410,586,"×%.2f" % float(preset.factor),29,col)
	text(host,font,628,602,"通关评级",13,MUTED)
	text(host,font,743,586,["S","SS","SSS"][tier],29)
	rect(host,Rect2(902,48,378,606),Color("1b2029"))
	rect(host,Rect2(902,48,4,107),col)
	text(host,font,935,81,"行动条件",27)
	text(host,font,937,128,"CONDITIONS / ALL",11,MUTED)
	rule(host,169,935,1244)
	if rules.is_empty():
		text(host,font,936,202,"没有额外规则。",21)
		text(host,font,936,250,"标准作战条件",14,MUTED)
	else:
		var gap := minf(28.0,365.0 / rules.size())
		for i in rules.size():
			text(host,font,936,184+i*gap,str(rules[i]),14 if gap >= 23 else 13,MUTED,310)
	rule(host,565,935,1244)
	text(host,font,936,590,"本档通关",16,MUTED)
	var best: Dictionary = Cfg.diff_best.get(str(tier),{})
	text(host,font,1130,576,"%02d" % int(best.get("wins",0)),39)
	text(host,font,1200,608,"次",13,MUTED)
	rect(host,Rect2(0,654,1280,66),INK)
	rule(host,654,28,1252)
	# 10-31 TA L6：底栏原来又写一个「返回 Esc」（与右上重复），去掉
	text(host,font,304,678,"认知塑造",19)
	UI.btn_key(host,font,Rect2(392,679,40,24),"" if Pad.using else "X", MUTED, 10, 0.0)
	rect(host,hits.go,Color("39414e") if locked else COLORS[0])
	text(host,font,942,676,"未解锁" if locked else "确认难度",22,MUTED if locked else INK)
	text(host,font,1160,684,Pad.hint("Enter  ›", "A  ›", "›"),12,MUTED if locked else INK)
	host.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	host.diff_rects.clear()
	for key in hits:
		var r: Rect2 = hits[key]
		host.diff_rects[key] = Rect2(offset+r.position*k,r.size*k)
