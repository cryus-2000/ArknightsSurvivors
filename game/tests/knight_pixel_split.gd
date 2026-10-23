extends Node

const A = preload("res://scripts/art.gd")
const Knight = preload("res://scripts/allies/knight.gd")

class DrawProbe extends RefCounted:
	var calls: Array = []
	func spr(name, frames, frame, pos, scale, flip, col, anchor):
		calls.append([name, frames, frame, anchor])
	func sparks(_pos, _dir, _color, _count, _speed):
		pass

class GameProbe extends RefCounted:
	var tex: Dictionary = {}
	var vfx := DrawProbe.new()
	var t := 0.0
	var PX := 2.0
	func draw_rect(_rect, _color):
		pass

func _ready():
	call_deferred("check")

func check():
	var g := GameProbe.new()
	var im := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	im.fill(Color.WHITE)
	var tx := ImageTexture.create_from_image(im)
	for suffix in ["", "_move", "_attack", "_charge"]:
		g.tex["e_knight_walk" + suffix] = tx
	A.enemy_pixel_spec("")
	A.enemy_pixels["__pixel_top_test"] = {"anchor": [0.5, 0.75]}
	var padded := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	padded.fill_rect(Rect2i(2, 2, 4, 4), Color.WHITE)
	var padded_tx := ImageTexture.create_from_image(padded)
	assert(A.enemy_pixel_top("__pixel_top_test", padded_tx) == 4.0)
	A.enemy_pixels.erase("__pixel_top_test")
	padded_tx = null
	padded = null
	var k := Knight.new(g)
	k.alive = true
	for row in [["idle", 0.0, "e_knight_walk", 6, 0], ["idle", 50.0, "e_knight_walk_move", 6, 0], ["stab", 0.0, "e_knight_walk_attack", 8, 3], ["charge", 0.0, "e_knight_walk_charge", 4, 2]]:   # 10-23 重画：待机 / 移动 6 帧、攻击 8 帧（出手帧 3，旧第 2 帧重映射到它），冲锋仍 4 帧:
		g.vfx.calls.clear()
		k.state = row[0]
		k.mv = row[1]
		k.st = 0.2
		k.draw()
		assert(g.vfx.calls.size() == 1)
		assert(g.vfx.calls[0][0] == row[2])
		assert(g.vfx.calls[0][1] == row[3])
		assert(g.vfx.calls[0][2] == row[4])
	assert(Knight.CHARGE_WIND == 0.3 and Knight.CHARGE_T == 0.42)
	assert(Knight.STAB_T == 0.4 and Knight.STAB_HIT_T == 0.2)
	g.tex.clear()
	k.g = null
	k = null
	g = null
	tx = null
	im = null
	print("KNIGHT_PIXEL_SPLIT_OK walking draw slots and original combat timings")
	await get_tree().create_timer(0.1).timeout
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
