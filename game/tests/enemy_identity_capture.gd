extends Node
## Silent rendering fixture for armor indicators and the existing aura.
var vp: SubViewport
var g: Node
func _ready() -> void:
 vp = SubViewport.new()
 vp.size = Vector2i(960, 540)
 vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(vp)
 g = load("res://game.tscn").instantiate()
 g.demo_op = "mizuki"
 vp.add_child(g)
 for i in 8:
  await get_tree().process_frame
 g.set_process(false)
 g.enemies = []
 g.warns = []
 g.fx = []
 g.t = 10.0
 var types := ["stone", "tracer", "nest", "mimic"]
 for i in types.size():
  var e: Dictionary = g.spawner.spawn_enemy(types[i], g.ppos + Vector2(-200 + i * 140, -50))
  e.hidden = false
  e.stun = 0.0
  e.flash = 0.0
  e.pose = 0.0
  if types[i] == "stone":
   e.set_t = 10.0
   e.set_done = true
  elif types[i] == "tracer":
   e.enraged = true
  elif types[i] == "nest":
   e["aura_pulse_t"] = g.t
 g.enemies_sys.build_grid()
 g.queue_redraw()
 await RenderingServer.frame_post_draw
 var path := "res://../build/enemy_identity_capture.png"
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--capture="): path = a.substr(10)
 var result: int = vp.get_texture().get_image().save_png(path)
 print("IDENTITY CAPTURE result=%d" % result)
 get_tree().quit(result)
