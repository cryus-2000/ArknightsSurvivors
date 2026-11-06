extends Node
const Hud = preload("res://scripts/screens/hud.gd")
const BossBar = preload("res://scripts/screens/hud_bossbar.gd")
const Settlement = preload("res://scripts/screens/settlement_screen.gd")
const Game = preload("res://scripts/game.gd")
class ProbeGame:
	extends "res://scripts/game.gd"
	func hud_ct() -> Transform2D:
		return Transform2D.IDENTITY
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	for cycle in 3:
		var hud = Hud.new(null)
		var owner: WeakRef = weakref(hud)
		var children: Array = []
		hud.bars._bb = BossBar.new(hud)
		for section in [hud.bars, hud.relics, hud.squad, hud.banners, hud.allyhp, hud.ult, hud.v2, hud.v3, hud.bars._bb]:
			check(section.h == hud, "live HUD backref")
			children.append(weakref(section))
		check(hud.ult.v.u == hud.ult, "live ultimate backref")
		children.append(weakref(hud.ult.v))
		var resource = Resource.new()
		var cached: WeakRef = weakref(resource)
		hud.set_meta("resource_sentinel", resource)
		resource = null
		hud = null
		check(owner.get_ref() == null, "HUD released without entering tree %d" % cycle)
		check(cached.get_ref() == null, "HUD cached resource released %d" % cycle)
		for i in children.size():
			check(children[i].get_ref() == null, "HUD section released %d/%d" % [cycle, i])
	var hud = Hud.new(null)
	var owner: WeakRef = weakref(hud)
	var surviving = hud.ult.v
	hud = null
	check(owner.get_ref() == null, "retained ultimate view does not retain HUD")
	check(surviving.u == null, "expired ultimate backref is null")
	# The settlement screen owns its presentation style and cached run artwork.
	for cycle in 3:
		var screen = Settlement.new(null)
		var screen_ref: WeakRef = weakref(screen)
		var style_ref: WeakRef = weakref(screen.sty)
		check(screen.sty.s == screen, "live settlement style backref")
		var resource = Resource.new()
		var cached: WeakRef = weakref(resource)
		screen.art["sentinel"] = resource
		resource = null
		screen = null
		check(screen_ref.get_ref() == null, "settlement screen released %d" % cycle)
		check(style_ref.get_ref() == null, "settlement style released %d" % cycle)
		check(cached.get_ref() == null, "settlement artwork released %d" % cycle)
	var screen = Settlement.new(null)
	var screen_ref: WeakRef = weakref(screen)
	var surviving_style = screen.sty
	screen = null
	check(screen_ref.get_ref() == null, "retained style does not retain settlement")
	check(surviving_style.s == null, "expired settlement backref is null")
	# Cached draw callbacks must be released when their owning canvas is freed.
	var game = ProbeGame.new()
	game.hud = Control.new()
	game.add_child(game.hud)
	game.demo_op = "lifetime_fixture"
	game.state = Game.S.PLAY
	var view = game.hud_view
	var view_ref: WeakRef = weakref(view)
	view._draw_body()
	view = null
	game.free()
	check(view_ref.get_ref() == null, "HUD cached draw callable released with canvas")
	print("HUD LIFETIME failures=", failures)
	get_tree().quit(1 if failures else 0)
