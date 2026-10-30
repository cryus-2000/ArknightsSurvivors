extends SceneTree
## 按住瞄准录像驱动（10-31，tools/hold_aim_rec.py 调用；不改游戏代码）：机器人照常走位，在 --ha_from..--ha_to 秒之间替玩家「按住瞄准」，
## 其余时间不按（自动普攻）。--ha_mode=kb：模拟按住左键（doctor.sim_atk / sim_dir），画面上画一个光标在瞄准方向；
## --ha_mode=touch：配 --touch，写触屏瞄准键的按住 / 拖动（touch.atk_id / atk_drag + doctor.touch_atk / touch_atk_dir），画一个指尖圈。
## 方向：--ha_dirs=角度,角度,…（度，0 = 右，90 = 下），按住期间平均分段轮流用；--ha_spin=度每秒 > 0 时改为从第一个角度匀速转
var g: Node = null
var mode := "kb"
var t0 := 3.0
var t1 := 9.0
var dirs: Array = [180.0]
var spin := 0.0
var overlay: Node2D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ha_mode="):
			mode = a.substr(10)
		if a.begins_with("--ha_from="):
			t0 = float(a.substr(10))
		if a.begins_with("--ha_to="):
			t1 = float(a.substr(8))
		if a.begins_with("--ha_dirs="):
			dirs = []
			for s in a.substr(10).split(","):
				dirs.append(float(s))
		if a.begins_with("--ha_spin="):
			spin = float(a.substr(10))
	change_scene_to_file.call_deferred("res://game.tscn")


func aim_dir() -> Vector2:
	var u: float = clampf((g.t - t0) / maxf(0.01, t1 - t0), 0.0, 0.999)
	var deg: float = float(dirs[0]) + spin * (g.t - t0) if spin > 0.0 else float(dirs[int(u * dirs.size())])
	return Vector2.from_angle(deg_to_rad(deg))


func holding() -> bool:
	return g != null and g.state == g.S.PLAY and g.t >= t0 and g.t < t1


func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g) or g.get("doctor") == null:
			g = null
			return false
		var cl := CanvasLayer.new()
		cl.layer = 120
		overlay = Overlay.new()
		overlay.drv = self
		cl.add_child(overlay)
		g.add_child(cl)
	if g.doctor == null or g.state != g.S.PLAY:
		return false
	g.doctor._ma_init = true
	g.doctor.aim_on = true   # 机器人局缺省不响应按住瞄准；录像替玩家按
	var on := holding()
	var d := aim_dir()
	if mode == "touch":
		var tc = g.touch
		if on:
			var L: Dictionary = tc.layout(g.hud.size)
			tc.atk_id = 7
			tc.atk_origin = L.atk.c
			tc.atk_drag = d * 60.0
			g.doctor.touch_atk = true
			g.doctor.touch_atk_dir = d * 60.0
		elif tc.atk_id == 7:
			tc._atk_release()
	else:
		g.doctor.sim_atk = on
		g.doctor.sim_dir = d
	overlay.queue_redraw()
	return false


class Overlay extends Node2D:
	var drv

	func _draw() -> void:
		var g = drv.g
		if g == null or not drv.holding():
			return
		var d: Vector2 = drv.aim_dir()
		if drv.mode == "touch":
			# 指尖：按在瞄准键上、拖到 atk_drag 处（界面坐标 × ui_k = 视口坐标）
			var p: Vector2 = (g.touch.atk_origin + g.touch.atk_drag) * float(g.get_node("/root/Cfg").ui_k)
			draw_circle(p, 26.0, Color(1, 1, 1, 0.22))
			draw_arc(p, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
			return
		# 光标：主控指向光标处（光标离主控约 190 像素），按住时光标下有一圈
		var sp: Vector2 = g.get_viewport().get_canvas_transform() * (g.ppos + d * 190.0)
		var pts := PackedVector2Array([sp, sp + Vector2(0, 22), sp + Vector2(6, 17), sp + Vector2(10, 26), sp + Vector2(14, 24), sp + Vector2(10, 15), sp + Vector2(17, 15)])
		draw_colored_polygon(pts, Color(1, 1, 1))
		draw_polyline(pts + PackedVector2Array([sp]), Color(0, 0, 0), 1.5)
		draw_arc(sp, 12.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.45, 0.9), 2.0)
