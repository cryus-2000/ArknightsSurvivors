extends "res://scripts/screens/title_op_pick.gd"
## 标题界面 · 难度页（docs/126 C2，10-22 由 title.gd 原样拆出；继承链见 title_base.gd）
## 10-22 合入 Codex 局外三屏（codex/ui-shell 47e5afe1）：难度页的输入与绘制交给 screens/difficulty_screen.gd（difficulty_screen 实例在 title_base）


func _diff_input(event: InputEvent) -> void:
	DifficultyScreen.input(self, event)


func _diff_back() -> void:
	transition.switch_page(func():
		diff_pick = false
		_op_reenter())
	Sfx.play("ui_move")


func _diff_step(d: int) -> void:
	# 未解锁的档也能翻过去看效果，只是不能出发（_diff_go）
	var n := clampi(diff_sel + d, 0, D.DIFF_PRESETS.size() - 1)
	if n != diff_sel:
		diff_sel = n
		Sfx.play("ui_move")


func _diff_go() -> void:
	if transition.busy:
		return
	if diff_sel > Cfg.diff_unlocked:
		Sfx.play("ui_move", -4.0, 0.6)
		return
	Cfg.difficulty = diff_sel
	Cfg.save()
	diff_pick = false
	_prewarm()
	Sfx.play("start", -8.0)   # 音量巡检（2026-09-27）：原 0 dB 比标题曲响 18 dB，且开场一开始还会再播一次
	leaving = 0.0


func _draw_diff(vs: Vector2) -> void:
	difficulty_screen.draw(self, vs)
