extends Node
const Materials = preload("res://scripts/render/final_boss_materials.gd")
class Recorder:
	extends RefCounted
	var points: Array = []
	func tb_poly(p,c): points.append_array(p)
	func tb_quad(a,b,c,d,col): points.append_array([a,b,c,d])
func _ready():
	var r := Recorder.new()
	var g := {"world":r,"combat":{"GROUND_Y":.62}}
	var errors := 0
	for skin in ["ice","ice_field","crescent","spear","step","choir","tentacle","tide","abyss"]:
		for shape in ["line","circle","cone","arc"]:
			for age in [0.0,.1,.3,1.0]:
				var w := {"pos":Vector2(40,20),"skin":skin,"shape":shape,"ang":.6,"len":520.0,"wid":28.0,"r":240.0,"inner_r":120.0,"half":.55,"age":age,"velocity":Vector2(100,0)}
				var before := w.duplicate(true)
				r.points.clear()
				Materials.draw(g,w,.9)
				if w!=before or r.points.is_empty() or not r.points.all(func(p):return p.is_finite()) or r.points.size()>10000:
					printerr("FAIL ",skin," ",shape," ",age)
					errors+=1
	print("FINAL BOSS MATERIALS failures=",errors)
	get_tree().quit(1 if errors else 0)
