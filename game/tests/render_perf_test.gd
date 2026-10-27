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
func _ready():
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
