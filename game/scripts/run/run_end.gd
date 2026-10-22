extends RefCounted
## 一局结束时的局外结算（docs/126 C1，10-22 由 game._process 原样搬出）：进入胜 / 负那一帧调一次（演练局不调）。
## 寻访凭证（Roster）、生机细胞（Meta）、各档最佳成绩（倒下这里记，通关的在 victory_flow.record_win 记）、B站云存档上传。不碰 g.rng

const Roster = preload("res://scripts/core/roster.gd")
const Meta = preload("res://scripts/core/meta.gd")


static func settle(g) -> void:
	var won: bool = g.state == g.S.WIN
	Roster.on_run_end(g, won)   # 干员解锁：发寻访凭证（docs/109 §12；不碰 g.rng）
	Meta.on_run_end(g, won)   # 局外成长：记生机细胞（docs/109 §3.1）
	if g.state == g.S.DEAD and g.mode == g.Mode.PLAY and g.preset >= 0 and g.demo_op == "" and not Cfg.practice_active:
		Cfg.note_diff_best(g.preset, false, g.t)
	Cloud.flush("run_end")   # B站云存档：一局结算时上传（只在 B站环境生效，docs/89）
