extends Node

var game: Node
var frames := 0
var fails := 0

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--doctor-capture"):
		return
	var folder := ProjectSettings.globalize_path("res://../build/doctor_style_capture")
	DirAccess.make_dir_recursive_absolute(folder)
	game.queue_redraw()
	game.hud.queue_redraw()
	game.fg.queue_redraw()
	game.fx_add.queue_redraw()
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)

func check(value: bool, message: String) -> void:
	if not value:
		fails += 1
		printerr("FAIL: ", message)

func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	game.state = game.S.PLAY
	if OS.get_cmdline_user_args().has("--doctor-capture"):
		game.t = 60.0
		game.p_off = Vector2.ZERO
		game.p_lean = 0.0
		game.p_sq = Vector2.ONE
		game.lamp_light.energy = 1.0
		game.doc_pos = game.ppos + Vector2(150,20)   # 空地（-80 会叠在随行干员身上）
		game.sprite.position = game.doc_pos + Vector2(0,6)
	game.doc_moving = false
	game.world.anim_name = ""
	game.world.update_doctor_anim(0.0)
	check(game.sprite.texture.get_height() == 64 and game.sprite.hframes == 8, "new idle")   # 11-08 Codex 原生 @2x 呼吸 8 帧（art/incoming/doctor_2x_1107）
	check(game.sprite.offset.y == -28.0, "idle foot 60")
	for i in 16:
		game.world.anim_t = float(i) / 4.0 + 0.001
		game.world.update_doctor_anim(0.0)
		check(game.sprite.frame == i % 8, "idle 4 fps / 2 s loop frame %d" % i)
		if i < 8:
			await capture("idle_%02d" % i)
	game.doc_moving = true
	game.world.update_doctor_anim(0.0)
	check(game.sprite.texture.get_height() == 64 and game.sprite.hframes == 8, "new run")
	check(game.sprite.offset.y == -28.0, "run foot 60")
	for i in 16:
		game.world.anim_t = float(i) / 10.0 + 0.001
		game.world.update_doctor_anim(0.0)
		check(game.sprite.frame == i % 8, "10 fps / 0.8 s loop frame %d" % i)
		if i < 8:
			await capture("run_%02d" % i)
	game.doc_moving = false
	game.world.update_doctor_anim(0.0)
	check(game.sprite.hframes == 8 and game.sprite.offset.y == -28.0 and game.sprite.frame == 0, "return to idle without anchor jump")
	game.state = game.S.DEAD
	game.world.update_doctor_anim(0.0)
	for i in 4:
		game.world.anim_t = float(i) / 6.0 + 0.001
		game.world.update_doctor_anim(0.0)
		check(game.sprite.texture.get_height() == 64 and game.sprite.frame == i, "death 6 fps frame %d" % i)
		await capture("death_%02d" % i)
	game.world.update_doctor_anim(2.0)
	check(game.sprite.frame == 3 and game.sprite.offset.y == -28.0, "death stays on last frame and common anchor")
	var idle: Image = game.tex.doctor_idle.get_image().get_region(Rect2i(0,0,64,64))
	var death: Image = game.tex.doctor_death.get_image().get_region(Rect2i(0,0,64,64))
	# 11-08：待机 / 跑步换成 Codex 原生 @2x 第一批，倒下条是第二批（docs/304 §5）还没交，首帧暂不等于新待机；第二批接入后恢复下面这条
	if idle.get_data() != death.get_data():
		print("DOCTOR RUN note: death f0 != idle f0（倒下条待 Codex 第二批）")
	# 1 倍帧条（doctor_*@1x，10-24）：密度 1，不被同名 @2x 遮蔽
	check(preload("res://scripts/art.gd").hires_of(game.tex.doctor_idle) == 1.0 and preload("res://scripts/art.gd").hires_of(game.tex.doctor_run) == 1.0, "1x strips loaded")
	var saved: Texture2D = game.tex.doctor_run
	game.tex.erase("doctor_run")
	game.state = game.S.PLAY
	game.doc_moving = true
	game.world.update_doctor_anim(0.0)
	check(game.sprite.texture == game.tex.doctor_idle and game.sprite.offset.y == -28.0, "missing run falls back to idle strip and idle anchor")
	game.tex.doctor_run = saved
	game.doc_moving = false
	print("DOCTOR RUN failures=", fails)
	game.world._gc_sink = null
	var hud = game.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	game.queue_free()
	game = null
	await get_tree().process_frame
	hud._layers.clear()
	await get_tree().create_timer(0.1).timeout
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if fails else 0)
