extends "res://scripts/characters/data_operator.gd"
var events: Array = []
var ends := 0
func _init(game, definition: Dictionary) -> void:
	super(game, definition)
func phase_shot(round_: Dictionary, shot: int) -> void:
	events.append({"shot":shot,"damage":round_.damage_mult,"anim":round_.anim})
	super(round_,shot)
func phase_skill_end(i: int) -> void:
	ends += 1
	super(i)
