## 敌人绘制写法微基准（docs/50 §31，调研报告 build/perf_tech_survey.md 第 1 项「GDScript 版 SpriteBatch」的过线测试）：
## 同一窗口里两种写法每 30 帧轮换，量 _draw（含 B 的列收集）每帧耗时，取 P10 / P50（低分位受抢占影响小）。
##   A：现在的写法——每只从字典读十几个键，算帧区域 / 落点 / 颜色，draw_texture_rect_region（受击再画一遍白剪影）
##   B：先一遍循环把这些字段写进 Packed 列（模拟里顺手收集），绘制时只读列、往一个顶点数组追加 6 个顶点，一次 canvas_item_add_triangle_array
## 用法：godot --path game res://tests/sprite_batch_bench.tscn -- [--n=150] [--frames=1800]
## 过线标准（调研报告）：B 比 A 每只省 ≥ 60% 才值得把 world.gd 的敌人路径改成批绘制
extends Node2D

var n := 150
var frames := 1800
var frame := 0
var enemies: Array = []
var tex: Texture2D
var white: Texture2D
var stats := {"A": PackedFloat32Array(), "B": PackedFloat32Array()}
var mode := "A"
# B 的列
var c_pos := PackedVector2Array()
var c_fr := PackedInt32Array()
var c_flip := PackedByteArray()
var c_flash := PackedFloat32Array()
var c_col := PackedColorArray()
var c_sc := PackedFloat32Array()
var verts := PackedVector2Array()
var uvs := PackedVector2Array()
var cols := PackedColorArray()
const FW := 64
const FH := 64
const NF := 8


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		if a.begins_with("--frames="):
			frames = int(a.substr(9))
	var img := Image.create(FW * NF, FH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.7, 0.9, 1.0))
	tex = ImageTexture.create_from_image(img)
	var wi := Image.create(FW * NF, FH, false, Image.FORMAT_RGBA8)
	wi.fill(Color.WHITE)
	white = ImageTexture.create_from_image(wi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var e := {"id": i, "type": "e_x", "tex": "e_x", "pos": Vector2(rng.randf_range(40, 1240), rng.randf_range(40, 680)),
			"vel": Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), "hp": 10.0, "maxhp": 10.0, "r": 12.0, "speed": 40.0,
			"anim_t": rng.randf(), "fps": 8.0, "flip": rng.randf() < 0.5, "flash": 0.0, "scale": 1.0 + rng.randf() * 0.3, "elite": rng.randf() < 0.1,
			"squash": 1.0, "age": 0.0, "kb": Vector2.ZERO, "stun": 0.0, "slow": 0.0, "dead": false, "dmg": 3.0, "xp": 1.0, "dk": 1.0,
			"frames": NF, "anchor": Vector2(0.5, 0.9), "mv_until": 0.0, "dc": 0, "state": "walk", "shield_hp": 0.0, "col": Color.WHITE}
		enemies.append(e)
	c_pos.resize(n)
	c_fr.resize(n)
	c_flip.resize(n)
	c_flash.resize(n)
	c_col.resize(n)
	c_sc.resize(n)


func _process(delta: float) -> void:
	for e in enemies:   # 两种写法共用的「模拟」：动一下、偶尔受击
		e.pos += e.vel * delta
		if e.pos.x < 20 or e.pos.x > 1260:
			e.vel.x = -e.vel.x
		if e.pos.y < 20 or e.pos.y > 700:
			e.vel.y = -e.vel.y
		e.anim_t += delta
		e.flash = maxf(0.0, e.flash - delta)
		if randf() < 0.01:
			e.flash = 0.12
	frame += 1
	mode = "A" if (frame / 30) % 2 == 0 else "B"
	queue_redraw()
	if frame >= frames:
		for k in stats:
			var d: PackedFloat32Array = stats[k].duplicate()
			d.sort()
			print("SBBENCH %s n=%d frames=%d p10=%.3fms p50=%.3fms per_sprite_p10=%.2fus" % [k, n, d.size(), d[int(d.size() * 0.1)], d[int(d.size() * 0.5)], d[int(d.size() * 0.1)] * 1000.0 / n])
		get_tree().quit()


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	if mode == "A":
		_draw_a()
	else:
		_gather_b()
		_draw_b()
	if frame % 30 > 3:   # 切换后头几帧不记
		stats[mode].append((Time.get_ticks_usec() - t0) / 1000.0)


func _draw_a() -> void:
	for e in enemies:
		if e.dead:
			continue
		var frames_n: int = e.frames
		var fr: int = int(e.anim_t * e.fps) % frames_n
		var sc: float = e.scale * (1.15 if e.elite else 1.0)
		var sz := Vector2(FW, FH) * sc * Vector2(1.0, e.squash)
		var anc: Vector2 = e.anchor
		var p: Vector2 = e.pos - sz * anc
		var src := Rect2(fr * FW, 0, FW, FH)
		var dst := Rect2(p, Vector2(-sz.x if e.flip else sz.x, sz.y))
		if e.flip:
			dst.position.x += sz.x
		var col: Color = e.col
		draw_texture_rect_region(tex, dst, src, col)
		if e.flash > 0.0:
			draw_texture_rect_region(white, dst, src, Color(1, 1, 1, e.flash / 0.12))


func _gather_b() -> void:
	var i := 0
	for e in enemies:
		c_pos[i] = e.pos
		c_fr[i] = int(e.anim_t * e.fps) % int(e.frames)
		c_flip[i] = 1 if e.flip else 0
		c_flash[i] = e.flash
		c_sc[i] = e.scale * (1.15 if e.elite else 1.0)
		c_col[i] = e.col
		i += 1


func _draw_b() -> void:
	var m := n * 6
	if verts.size() != m:
		verts.resize(m)
		uvs.resize(m)
		cols.resize(m)
	var tw := float(FW * NF)
	var k := 0
	for i in n:
		var sc: float = c_sc[i]
		var sx: float = FW * sc
		var sy: float = FH * sc
		var p: Vector2 = c_pos[i] - Vector2(sx * 0.5, sy * 0.9)
		var u0: float = c_fr[i] * FW / tw
		var u1: float = (c_fr[i] + 1) * FW / tw
		if c_flip[i] == 1:
			var tmp := u0
			u0 = u1
			u1 = tmp
		var a := p
		var b := p + Vector2(sx, 0)
		var c := p + Vector2(sx, sy)
		var d := p + Vector2(0, sy)
		verts[k] = a
		verts[k + 1] = b
		verts[k + 2] = c
		verts[k + 3] = a
		verts[k + 4] = c
		verts[k + 5] = d
		uvs[k] = Vector2(u0, 0)
		uvs[k + 1] = Vector2(u1, 0)
		uvs[k + 2] = Vector2(u1, 1)
		uvs[k + 3] = Vector2(u0, 0)
		uvs[k + 4] = Vector2(u1, 1)
		uvs[k + 5] = Vector2(u0, 1)
		var col: Color = c_col[i]
		for j in 6:
			cols[k + j] = col
		k += 6
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), verts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())
	for i in n:   # 受击白闪少（约 1%），照旧单画
		if c_flash[i] > 0.0:
			var sc2: float = c_sc[i]
			var sz := Vector2(FW, FH) * sc2
			draw_texture_rect_region(white, Rect2(c_pos[i] - sz * Vector2(0.5, 0.9), sz), Rect2(c_fr[i] * FW, 0, FW, FH), Color(1, 1, 1, c_flash[i] / 0.12))
