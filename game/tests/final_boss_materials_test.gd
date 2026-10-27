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
	var art = preload("res://scripts/art.gd")
	for name in ["prop_knight_frost_stake","prop_knight_frost_stake_rise","prop_knight_frost_stake_break","fx_knight_crystal_rise","fx_knight_crystal_hold","fx_knight_crystal_break","fx_knight_ice_crest","proj_knight_ice","fx_knight_ice_hit"]:
		var texture = art.tex(name)
		if texture==null or texture.get_width()%int(art.V6_FRAMES[name][0])!=0:
			printerr("FAIL imported ice strip ",name)
			errors+=1
	for skin in ["ice","ice_field","ice_wave","ice_thrust","ice_lance","ice_wall","crescent","spear","step","choir","tentacle","tide","abyss"]:
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
