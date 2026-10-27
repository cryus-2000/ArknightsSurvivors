extends RefCounted
## Camera-facing water volume above a ground anchor; the shadow never substitutes for the body.
static var frames: Array[Texture2D] = []
const SIZE := 40
const PALETTE := [Color("112f42"), Color("19465a"), Color("27657a"), Color("43899b"), Color("76b5bf"), Color("b6dedb"), Color("ecf8e8")]

static func make_image(frame: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var uv := (Vector2(x, y) + Vector2.ONE * 0.5 - Vector2.ONE * SIZE * 0.5) / (SIZE * 0.5 - 1.0)
			var rr := uv.length_squared()
			if rr > 1.0: continue
			var radial := sqrt(rr)
			var angle := uv.angle()
			# A bubble transmits the scene; only its grazing-angle membrane catches light.
			var col := Color(0.50, 0.81, 0.84, 0.035)
			var shimmer := sin(angle * 3.0 + frame * TAU / 12.0)
			if radial > 0.94:
				col = Color(0.48, 0.78, 0.84, 0.28 + 0.12 * shimmer)
			elif radial > 0.84:
				col = Color(0.65, 0.89, 0.89, 0.12)
			# Broken curved reflections, never diffuse shading across a solid sphere.
			if radial > 0.79 and radial < 0.94 and angle > -2.9 and angle < -1.5:
				col = Color(0.88, 0.97, 0.94, 0.88 if radial > 0.85 else 0.38)
			if radial > 0.87 and angle > 0.25 and angle < 1.25:
				col = Color(0.52, 0.86, 0.88, 0.62)
			if radial > 0.62 and radial < 0.70 and angle > -2.6 and angle < -2.1:
				col = Color(0.87, 0.97, 0.95, 0.48)
			img.set_pixel(x, y, col)
	return img

static func texture(frame: int) -> Texture2D:
	if frames.is_empty():
		for i in 12: frames.append(ImageTexture.create_from_image(make_image(i)))
	return frames[posmod(frame, 12)]

static func center(w: Dictionary) -> Vector2:
	return w.pos + Vector2(0, -float(w.r) - 14.0)

static func shadow(r, w: Dictionary, alpha: float) -> void:
	var radius: float = float(w.r)
	for y in range(-6, 7, 2):
		var half_width := radius * 0.8 * sqrt(maxf(0.0, 1.0 - pow(y / 7.0, 2)))
		var a: Vector2 = (w.pos + Vector2(-half_width, y)).snapped(Vector2(2,2))
		var b: Vector2 = (w.pos + Vector2(half_width, y)).snapped(Vector2(2,2))
		r.tb_quad(a,b,b+Vector2(0,2),a+Vector2(0,2),Color(0.015,0.045,0.06,alpha*0.16))

static func draw(g, w: Dictionary, alpha: float, charging := false) -> void:
	var age: float = float(w.get("age", w.get("t", 0.0)))
	var progress: float = clampf(float(w.get("t", 0.0)) / maxf(0.01,float(w.get("dur",1.0))),0,1)
	var radius: float = float(w.r) * (lerpf(0.25,1.0,smoothstep(0.0,1.0,progress)) if charging else 1.0)
	var p := center(w) + Vector2(0,sin(age*3.0 + float(w.get("ang",0.0)))*2.0)
	g.world.tb_flush()
	var stretch := 1.0 + sin(age * 5.0 + float(w.get("ang", 0.0))) * 0.035
	var extent := Vector2(radius * stretch, radius / stretch)
	g.draw_texture_rect(texture(int(age*10.0 + float(w.get("ang",0.0))*2.0)),Rect2((p-extent).snapped(Vector2(2,2)),extent*2),false,Color(1,1,1,alpha))
	if charging:
		# Four small ground ticks indicate a forming projectile, not a floor explosion.
		for side in [-1.0,1.0]:
			var a: Vector2 = w.pos + Vector2(side * (float(w.r)+4),0)
			g.world.tb_quad(a,a+Vector2(2,0),a+Vector2(2,5),a+Vector2(0,5),Color(0.95,0.35,0.4,0.8))

static func pop(g, f: Dictionary) -> void:
	var t: float = 1.0 - float(f.life)/float(f.max)
	var p := center(f)
	var r = g.world
	# Detached shell crescents and drops retain their launch inertia while falling and cooling.
	for k in 11:
		var a: float = k * 2.399 + float(f.ang)*0.2
		var d := Vector2.from_angle(a)
		var q := p + d * float(f.r) * (0.92 + t*1.1) + Vector2(0,t*t*22)
		var sz := 2.0
		q = q.snapped(Vector2(2,2))
		var c := Color(0.76, 0.94, 0.94)
		c.a = 1.0-t
		r.tb_quad(q,q+Vector2(sz,0),q+Vector2(sz,sz),q+Vector2(0,sz),c)
		if t < 0.55 and k % 2 == 0:
			var tip := q + d.orthogonal()*float(f.r)*0.2*(1-t)
			r.tb_quad(q,tip.snapped(Vector2(2,2)),(tip+d*2).snapped(Vector2(2,2)),q+d*2,c)
