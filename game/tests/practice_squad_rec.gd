extends Node
## 录片（用户 10-28）：Boss 演练里选成品分队 → 打偏执泡影。tools/practice_squad_rec.py 驱动，--fixed-fps 30 原速存帧。
## 参数：--recdir=<存帧目录> --squad=<分队 id> --boss=<Boss 键> --fight=<最长秒数>；队长按 D / S / A / W 轮流绕圈走。
const Squads = preload("res://scripts/run/practice_squads.gd")
var dir := ""
var squad_id := "wisadel_m18"
var boss := "paranoia"
var fight_secs := 130.0
var menu
var game = null
var t := 0.0
var t_fight := 0.0
var started := false
var frame := 0
var key_i := -1
var end_at := -1.0
const KEYS := [KEY_D, KEY_S, KEY_A, KEY_W]


func _ready() -> void:
	for a in Cfg.dev_args():
		if a.begins_with("--recdir="):
			dir = a.substr(9)
		elif a.begins_with("--squad="):
			squad_id = a.substr(8)
		elif a.begins_with("--boss="):
			boss = a.substr(7)
		elif a.begins_with("--fight="):
			fight_secs = float(a.substr(8))
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menu = preload("res://scripts/screens/boss_trial_menu.gd").new()
	layer.add_child(menu)
	menu.size = get_viewport().get_visible_rect().size
	menu.open()


func _process(dt: float) -> void:
	t += dt
	if not started:
		if t > 0.9 and menu.boss_pick.selected != _boss_index():
			menu.boss_pick.select(_boss_index())
		if t > 1.8 and menu.squad_pick.selected <= 0:
			menu.squad_pick.select(maxi(0, menu.squad_ids.find(squad_id)))
			menu._sync_squad()
		if t > 3.6:
			_start()
	else:
		t_fight += dt
		_steer()
		var over: bool = game.state == game.S.WIN or game.state == game.S.DEAD or game.trial.won()
		if over and end_at < 0.0:
			end_at = t_fight + 3.0
		if t_fight > fight_secs or (end_at > 0.0 and t_fight > end_at):
			print("PRACTICEREC frames=%d fight=%.1f state=%d won=%s squad=%s" % [frame, t_fight, game.state, game.trial.won(), squad_id])
			get_tree().quit()
	if dir != "":
		get_viewport().get_texture().get_image().save_jpg(dir + "/rec_%05d.jpg" % frame, 0.88)
	frame += 1


func _boss_index() -> int:
	for i in menu.boss_groups.size():
		if menu.boss_groups[i] == [boss]:
			return i
	return 0


func _start() -> void:
	started = true
	var info: Dictionary = Squads.squad(squad_id)
	Cfg.boss_trial_request = {"group": [boss], "operator": str(info.get("op", "wisadel")), "growth": 2, "phase": 1, "safe": true, "squad": squad_id}
	menu.hide()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	print("PRACTICEREC start squad=%s ops=%s level=%d relics=%d" % [squad_id, game.squad.ids(), game.level, game.relics.size()])


## 绕圈走：每 1.4 秒换一个方向键（只为录片好看；演练本身是玩家操作）
func _steer() -> void:
	var k := int(t_fight / 1.4) % KEYS.size()
	if k == key_i:
		return
	if key_i >= 0:
		var up := InputEventKey.new()
		up.keycode = KEYS[key_i]
		up.pressed = false
		Input.parse_input_event(up)
	key_i = k
	var down := InputEventKey.new()
	down.keycode = KEYS[k]
	down.pressed = true
	Input.parse_input_event(down)
