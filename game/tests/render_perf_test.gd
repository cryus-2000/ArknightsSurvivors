extends Node
const Draw = preload("res://scripts/render/boss_attack_draw.gd")
var squad = null
var failures := 0
var mask_shift := 0.0
class Recorder:
	extends RefCounted
	var quads: Array = []
	var capture := true
	func tb_quad(a,b,c,d,_col):
		if capture: quads.append([a,b,c,d])
	func tb_arc(_a,_b,_c,_d,_e,_f,_g,_h): pass
func ok(b: bool, label: String):
	if not b:
		failures += 1
		printerr("FAIL: ", label)
func draw_mask_fixture(canvas):
	canvas.draw_circle(Vector2(80.25 + mask_shift, 65.75), 27.0, Color(0.2,0.7,1.0,0.6))
	canvas.draw_rect(Rect2(100.5 + mask_shift,50.5,16.5,45.5),Color(1,0.1,0.2,0.3))
func frames():
	for i in 4: await get_tree().process_frame

func check_pixel_fx_culling() -> void:
	var px = preload("res://scripts/render/fx_pxplane.gd").new()
	px.g = {"t": 1.0, "PX": 2.0, "optical_on": true, "optical_lo": false, "glow_next": [], "opt_old": 0, "OPT_PXEVICT": 536870912}
	var vp := SubViewport.new()
	vp.size = Vector2i(96, 64)
	add_child(vp)
	var target := Node2D.new()
	vp.add_child(target)
	var cv = preload("res://scripts/characters/batch_canvas.gd").new(target)
	cv.active = true
	cv.mute = true
	var entry := {"w": 8, "h": 4, "ox": 1, "oy": 2, "n": 1, "emit": [[[1, 1, "ffffff"]]]}
	for k in ["pool_gd", "ey_ball_lava_d0", "raw_blade", "tx_raw_line", "missing_strip"]:
		px.meta[k] = entry
	var edge := Vector2(108, 20)
	var far := Vector2(300, 20)
	cv.active = false
	ok(px._strip_in_view(cv, Rect2(far, Vector2.ONE), true) and px._strip_in_view(target, Rect2(far, Vector2.ONE), true),
		"untracked inherited draw transforms remain visible")
	cv.active = true
	px._draw_strip(cv, "pool_gd", 0, edge, false, true)
	ok(not px.tex.has("pool_gd") and px.g.glow_next.size() == 1, "cold offscreen sprite queues original glow without loading")
	px._draw_strip(cv, "missing_strip", 0, far, true, true)
	ok(px.g.glow_next.size() == 1 and px.tex.is_empty(), "missing offscreen source never emits")
	px._draw_strip(cv, "pool_gd", -1, edge, true, true)
	ok(px.tex.is_empty() and px.g.glow_next.size() == 1, "unstarted visible sprite stays cold")
	px._draw_strip(cv, "pool_gd", 0, edge, true, true)
	ok(px.tex.has("pool_gd") and px.g.glow_next.size() == 2, "mirrored asymmetric origin reaches the left edge of the frame")
	px.g.t = 63.0
	px._emit_n = px.EMIT_CAP - 1
	px._draw_strip(cv, "pool_gd", 0, far, true, true)
	ok(px._tex_t["pool_gd"] == 1.0 and px._emit_n == px.EMIT_CAP, "hidden hot strip keeps its old lifetime and claims its glow budget")
	px._tex_evict()
	ok(not px.tex.has("pool_gd"), "hidden hot strip can expire")
	vp.canvas_transform = Transform2D(0.0, Vector2(-260, 0))
	px._draw_strip(cv, "pool_gd", 0, far, false, true)
	ok(px.tex.has("pool_gd") and px.g.glow_next.size() == 3, "same-frame camera move reloads sprite without exceeding glow budget")
	vp.canvas_transform = Transform2D.IDENTITY
	cv.xf = Transform2D(0.0, Vector2(-260, 0))
	px.g.t = 64.0
	px._draw_strip(cv, "pool_gd", 0, far, false, true)
	ok(px._tex_t["pool_gd"] == 64.0, "unflipped strip inherits active batch transform")
	px._draw_raw(cv, "raw_blade", 0, far, PI / 2.0, -2.0)
	ok(not px.tex.has("raw_blade") and cv.xf == Transform2D.IDENTITY, "offscreen raw strip stays cold and restores prior transform")
	cv.xf = Transform2D(0.0, Vector2(8, 4))
	px._draw_raw(cv, "missing_strip", 0, far, 0.0, 2.0)
	ok(cv.xf.origin == Vector2(8, 4), "missing strip preserves caller transform")
	px._draw_raw(cv, "raw_blade", 0, Vector2(98, 20), PI / 2.0, -2.0)
	ok(px.tex.has("raw_blade"), "rotated negative-scale corner enters viewport")
	px._ey_strip_rot(cv, "ey_ball_lava_d0", 0, far, true, PI / 2.0, 0, 0.6)
	ok(not px.tex.has("ey_ball_lava_d0"), "offscreen stretched fireball stays cold")
	px._ey_strip_rot(cv, "ey_ball_lava_d0", 0, Vector2(40, 20), true, PI / 2.0, 0, 0.6)
	ok(px.tex.has("ey_ball_lava_d0") and cv.xf == Transform2D.IDENTITY, "visible stretched fireball restores batch matrix")
	var operator := {"id": "texas", "cv": cv}
	px._tx_draw_raw_lines(operator)
	ok(not px.tex.has("tx_raw_line"), "no active Texas line keeps strip cold")
	px.items = [{"ly": "rawln", "oid": "texas", "t0": px.g.t, "a": Vector2(-200, px.TX_H + 20), "b": Vector2(200, px.TX_H + 20)}]
	px._tx_draw_raw_lines(operator)
	ok(px.tex.has("tx_raw_line"), "line crossing screen loads with both endpoints outside")
	var low := SubViewport.new()
	low.size = Vector2i(60, 32)
	vp.add_child(low)
	low.canvas_transform = Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2.ZERO)
	px.g.optical_lo = true
	px.g.optical = {"lo_vp": low}
	px.g.t = 65.0
	px._draw_strip(cv, "pool_gd", 0, edge, false, true)
	ok(px._tex_t["pool_gd"] == 65.0, "low-resolution padded viewport keeps edge sprite")
	low.size = Vector2i(40, 32)
	px.g.t = 66.0
	px._draw_strip(cv, "pool_gd", 0, edge, false, true)
	ok(px._tex_t["pool_gd"] == 65.0, "same-frame low viewport resize invalidates bounds")
	vp.free()

func _ready():
	check_pixel_fx_culling()
	var rec = Recorder.new()
	var fake = {"world":rec, "combat":{"GROUND_Y":0.62}}
	var w = {"shape":"circle", "pos":Vector2(123.25,-82.5),"r":360.0,"inner_r":240.0,"col":Color.CYAN}
	Draw._shape(fake,w,0.8,true)
	for i in 40:
		var a: float = TAU*i/40.0
		var b: float = TAU*(i+1)/40.0
		var va = Vector2(cos(a),sin(a)*0.62)
		var vb = Vector2(cos(b),sin(b)*0.62)
		ok(rec.quads[i] == [w.pos+va*w.inner_r,w.pos+va*w.r,w.pos+vb*w.r,w.pos+vb*w.inner_r],"exact quad " + str(i))
	rec.capture=false
	for pass_i in 4:
		var start = Time.get_ticks_usec()
		for i in 10000: Draw._circle_fill(rec,w,0.62,Color.CYAN)
		print("CIRCLE_US_10000=",Time.get_ticks_usec()-start)
	var post = load("res://scripts/post_fx.gd").new()
	add_child(post)
	post.set_process(false)
	var other = ShaderMaterial.new()
	other.shader=load("res://shaders/post.gdshader")
	await frames()
	print("GPU_BEFORE=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	post.zone_amt=0.8
	post.refresh_zone_guards(self)
	post.mask_canvas.draw.connect(draw_mask_fixture.bind(post.mask_canvas))
	post.mask_canvas.queue_redraw()
	post.apply_zone_guards(post.mat)
	post.apply_zone_guards(other)
	await frames()
	print("GPU_ACTIVE=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)," SIZE=",post.zone_mask.size)
	var pixels = PackedByteArray()
	if DisplayServer.get_name() != "headless":
		pixels = post.zone_mask.get_texture().get_image().get_data()
		mask_shift=18.5
		post.refresh_zone_guards(self)
		await frames()
		ok(pixels != post.zone_mask.get_texture().get_image().get_data(),"mask follows moving alpha geometry")
		mask_shift=0.0
	var original_id = post.zone_mask.get_instance_id()
	post.zone_amt=0.0
	post._process(1.0)
	ok(post.zone_mask != null,"cooldown keeps mask")
	post.zone_amt=0.8
	post.refresh_zone_guards(self)
	ok(post.zone_mask.get_instance_id()==original_id,"short pause reuses mask")
	post.zone_amt=0.0
	post._process(2.1)
	await frames()
	print("GPU_IDLE=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	if not Cfg.dev_args().has("--baseline"):
		ok(post.zone_mask==null,"idle mask freed")
		ok(other.get_shader_parameter("zone_mask")==null and post.mat.get_shader_parameter("zone_mask")==null,"all consumers unbound")
	post.zone_amt=0.8
	post.refresh_zone_guards(self)
	if not Cfg.dev_args().has("--baseline"):
		post.mask_canvas.draw.connect(draw_mask_fixture.bind(post.mask_canvas))
	post.mask_canvas.queue_redraw()
	post.apply_zone_guards(other)
	await frames()
	if not pixels.is_empty():
		ok(pixels == post.zone_mask.get_texture().get_image().get_data(),"restored alpha mask pixels identical")
	ok(post.zone_mask != null and other.get_shader_parameter("zone_mask_on"),"lazy restore")
	print("GPU_RESTORE=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	post.queue_free()
	await frames()
	print("RENDER PERF failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
