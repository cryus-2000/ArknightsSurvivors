extends Node
const Draw = preload("res://scripts/render/boss_attack_draw.gd")
var failures := 0
class Recorder:
	extends RefCounted
	var vertices: Array = []
	var colors: Array = []
	func tb_quad(a, b, c, d, color):
		vertices.append_array([a,b,c,d])
		colors.append(color)
	func tb_poly(points, color):
		for p in points: vertices.append(p)
		colors.append(color)
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _ready() -> void:
	var rec = Recorder.new()
	var g = {"world":rec,"combat":{"GROUND_Y":0.62}}
	for skin in ["bubble","phantom","ice","ice_field","crescent","step","spear","choir","tentacle","tide"]:
		for shape in ["circle","line","cone","arc"]:
			var w = {"skin":skin,"shape":shape,"pos":Vector2(103.25,-81.5),"ang":0.7,"len":530.0,"wid":24.0,"r":280.0,"inner_r":220.0,"half":0.8,"col":Color.CYAN,"velocity":Vector2(70,40),"life":2.0,"age":0.15,"t":0.5,"dur":1.3}
			var saved: Dictionary = w.duplicate(true)
			for warning in [true,false]:
				rec.vertices.clear()
				rec.colors.clear()
				Draw._shape(g,w,0.85,warning)
				check(w == saved, "drawing must not mutate attack " + skin)
				check(rec.vertices.all(func(p): return p.is_finite()), "finite geometry " + skin)
				check(rec.vertices.size() < 10000, "bounded geometry " + skin)
				if warning:
					check(rec.colors.all(func(c): return c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0), "no HDR white warning body " + skin)
	var delayed := {"skin":"ice_field","shape":"line","pos":Vector2.ZERO,"ang":0.0,"len":1000.0,"wid":75.0,"t":1.0,"dur":2.7,"tell_after":1.3}
	rec.vertices.clear()
	Draw._warning(g,delayed,1.0)
	check(rec.vertices.is_empty(),"second ice wave cannot reveal early")
	delayed.t=1.31
	Draw._warning(g,delayed,1.0)
	check(not rec.vertices.is_empty(),"second ice wave reveals after first release")
	print("BOSS FX GEOMETRY failures=",failures)
	get_tree().quit(1 if failures else 0)
