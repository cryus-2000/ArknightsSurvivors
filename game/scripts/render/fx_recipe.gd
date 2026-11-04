## 运行时攻击特效配方（11-05 用户定方向，docs/245）：开关 fx/recipe（缺省 0 = 关）。
## 方向：保留 Noita 底子；每招一个运行时生成的实心、硬边、2–3 阶像素主形（弧刃 / 突刺 / 投射弹 + 拖尾 / 爆团 / 光束 / 浪身 / 锁链 / 落点坑），
## 节奏「蓄势 → 命中定帧爆亮 → 冷却余韵」；质感用少量、颗粒大、有重量、会落地会弹的 Noita 式颗粒（墨滴 / 火星 / 余烬 / 碎晶 / 碎石）；
## 命中短暂照地（本人主色，有光源预算和上限）。同一招同时出现的元素不超过 2–3 种；精英化三档肉眼可分（E1 放大加厚多一拍，E2 主形质变 + 专属点缀色）。
## 分两层：核心（主形，不受拥挤降噪）/ 装饰（颗粒，按 world.fx_dim 和拥挤度减量减淡）。
## 每名干员一份数据 data/fx_recipes/<id>.json（形状、颜色、质感、光、各精英档怎么变）；只有有配方的干员被接管。
## 接管 = 该干员原来的攻击 / 技能画面（帧条、pfx、刀光、命中颗粒）只跳过绘制或不生成画面件；玩法调用、玩法随机数一律照旧（同 seed TRACE 逐行一致）。
## 画面随机只用 g.vrng。坐标是世界坐标，画在 squad.cv（合批画布，进低分辨率层：多边形自然落在 2 px 格上 = 硬边像素形）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const DIR := "res://data/fx_recipes/"
const SY := 0.55          # 地面椭圆压扁（同区域画法）
const SHAPE_MAX := 48     # 每名干员同时在画的主形上限（超出丢最旧的）
const LIGHT_LIFE_MAX := 0.15

var g
var recipes := {}         # 干员 id → 配方（缺文件 = 空字典 = 不接管）
var shapes := {}          # 干员 id → [主形]
var parts: Array = []     # 装饰颗粒（全队共用上限 fx/recipe_grains）
var lights: Array = []    # [pos, r, col, t0, life, inten, op]
var _on := false
var _on_frame := -1
var _step_frame := -1
var _t_last := -1.0
var stat_lights := 0      # 量测：上一帧送进 optical 的灯数
var stat_parts := 0


static func of(game):
	if game == null:
		return null
	if game.has_meta("fx_recipe"):
		return game.get_meta("fx_recipe")
	var r = new()
	r.g = game
	game.set_meta("fx_recipe", r)
	return r


## 开关（每帧读一次）
func enabled() -> bool:
	var fr: int = Engine.get_process_frames()
	if fr != _on_frame:
		_on_frame = fr
		_on = Bal.v("fx/recipe", 0.0) > 0.0 and not g.headless_batch
	return _on


func recipe(id: String) -> Dictionary:
	if not recipes.has(id):
		var d := {}
		var p: String = DIR + id + ".json"
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				d = v
				_prep(d)
		recipes[id] = d
	return recipes[id]


## 颜色字段（"#rrggbb" 或 [r, g, b]）预先转成 Color
static func _col(v, dflt := Color.WHITE) -> Color:
	if v is String:
		return Color.html(v)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return dflt


static func _prep(d: Dictionary) -> void:
	var pal: Dictionary = d.get("palette", {})
	var out := {}
	for k in pal:
		out[k] = _col(pal[k])
	for k in ["dark", "main", "hot", "accent", "light"]:
		if not out.has(k):
			out[k] = Color.WHITE
	out["accent_on"] = str(d.get("accent_on", "body"))   # 精二点缀色落在哪一阶：body 主体 / rim 外边
	d["_pal"] = out


## 这名干员的画面由配方接管吗（开关开 + 有配方）
static func owns(o) -> bool:
	if o == null or o.g == null:
		return false
	var r = of(o.g)
	return r.enabled() and not r.recipe(str(o.id)).is_empty()


static func owns_id(game, oid: String) -> bool:
	if game == null or oid == "":
		return false
	var r = of(game)
	return r.enabled() and not r.recipe(oid).is_empty()


# ================================================================ 配方读取

## 某一招在这名干员当前精英档下的参数：moves[name] 合并 e1（精一起）/ e2（精二起），sc = 档位体量
func move(o, name: String) -> Dictionary:
	var rc: Dictionary = recipe(str(o.id))
	var base: Dictionary = rc.get("moves", {}).get(name, {})
	if base.is_empty():
		return {}
	var t: int = tier(o)
	var m: Dictionary = base.duplicate()
	if t >= 1 and base.get("e1", null) is Dictionary:
		m.merge(base.e1, true)
	if t >= 2 and base.get("e2", null) is Dictionary:
		m.merge(base.e2, true)
	var tr: Dictionary = rc.get("tiers", {}).get("e%d" % t, {})
	m["sc"] = float(m.get("scale", 1.0)) * float(tr.get("scale", 1.0))
	m["thick"] = float(tr.get("thick", 1.0))
	m["beat"] = float(tr.get("beat", 0.0))
	m["tier"] = t
	return m


func tier(o) -> int:
	var f: float = Bal.v("fx/recipe_tier", -1.0)   # 三档并排图用：强制某一档画面（只改画面）
	if f >= 0.0:
		return clampi(int(f), 0, 2)
	return clampi(int(o.elite), 0, 2)


func pal(o) -> Dictionary:
	return recipe(str(o.id)).get("_pal", {})


# ================================================================ 事件（玩法代码里的一行钩子；只记画面，不碰玩法）

## kind：fire / hit / exec / lock_tick / fan_tick / skill / swing / quake / crush / breach / slam / leap / crash
static func ev(o, kind: String, d: Dictionary = {}) -> void:
	if not owns(o):
		return
	of(o.g)._ev(o, kind, d)


func _ev(o, kind: String, d: Dictionary) -> void:
	var p: Dictionary = pal(o)
	match kind:
		"fire":
			var m: Dictionary = move(o, "fire")
			if m.is_empty():
				return
			var at: Vector2 = d.get("at", o.pos)
			var dir: Vector2 = d.get("dir", Vector2.RIGHT)
			_shape(o, {"k": "spike", "c": at, "ang": dir.angle(), "len": float(m.get("len", 14.0)) * m.sc, "w": float(m.get("w", 6.0)) * m.sc * m.thick,
				"life": float(m.get("life", 0.09)), "freeze": 0.0, "layer": "over", "grow": true})
		"hit":
			_hit(o, d.get("at", o.pos), float(d.get("gy", 0.0)), str(d.get("move", "hit")), d.get("dir", Vector2.ZERO))
		"exec":
			var m2: Dictionary = move(o, "exec")
			if m2.is_empty():
				return
			var e_at: Vector2 = d.get("at", o.pos)
			var gy: float = float(d.get("gy", e_at.y))
			_shape(o, {"k": "spike", "c": Vector2(e_at.x, gy), "ang": -PI / 2.0, "len": float(m2.get("len", 46.0)) * m2.sc, "w": float(m2.get("w", 12.0)) * m2.sc * m2.thick,
				"life": float(m2.get("life", 0.34)), "freeze": float(m2.get("freeze", 0.06)), "layer": "over", "grow": true, "accent": m2.tier >= 2})
			if d.has("to"):
				# 溢出伤害的转移线：细、无定帧爆亮（处决很频繁，跨半屏的白热光束会抢主形）
				_shape(o, {"k": "beam", "a": e_at, "b": d.to, "w": float(m2.get("beam_w", 4.0)) * m2.thick, "life": 0.16, "freeze": 0.0, "layer": "over", "echo": true})
			_grains(o, Vector2(e_at.x, gy - 30.0), gy, str(m2.get("grain", "ink")), int(m2.get("n", 6)), m2)
			_light(o, e_at, float(m2.get("light_r", 110.0)) * m2.sc, float(m2.get("light_i", 0.75)), float(m2.get("light_life", 0.14)), p.light)
		"lock_tick", "fan_tick":
			var m3: Dictionary = move(o, "s1_tick" if kind == "lock_tick" else "s3_tick")
			if m3.is_empty():
				return
			var pts: Array = d.get("pts", [])
			var k := 0
			for q in pts:
				if k >= int(m3.get("max", 4)):
					break
				var qa: Vector2 = q[0]
				var qgy: float = float(q[1])
				_shape(o, {"k": str(m3.get("core", "spike")), "c": Vector2(qa.x, qgy) if str(m3.get("core", "spike")) == "spike" else qa, "ang": -PI / 2.0,
					"len": float(m3.get("len", 26.0)) * m3.sc, "w": float(m3.get("w", 7.0)) * m3.sc * m3.thick, "r": float(m3.get("r", 10.0)) * m3.sc,
					"n": int(m3.get("points", 4)), "life": float(m3.get("life", 0.2)), "freeze": float(m3.get("freeze", 0.03)), "layer": "over", "grow": true,
					"accent": m3.tier >= 2 and m3.get("accent", false)})
				_grains(o, qa, qgy, str(m3.get("grain", "ink")), int(m3.get("n", 2)), m3)
				k += 1
			if not pts.is_empty():
				_light(o, pts[0][0], float(m3.get("light_r", 70.0)) * m3.sc, float(m3.get("light_i", 0.4)), 0.1, p.light)
		"skill":
			var i: int = int(d.get("i", 0))
			var m4: Dictionary = move(o, "cast%d" % (i + 1))
			if m4.is_empty():
				return
			var c: Vector2 = o.pos + Vector2(0, -float(m4.get("y", 26.0)))
			_shape(o, {"k": str(m4.get("core", "star")), "c": c, "r": float(m4.get("r", 22.0)) * m4.sc, "n": int(m4.get("points", 6)), "ang": -PI / 2.0,
				"len": float(m4.get("len", 40.0)) * m4.sc, "w": float(m4.get("w", 10.0)) * m4.sc * m4.thick,
				"life": float(m4.get("life", 0.32)), "freeze": float(m4.get("freeze", 0.06)), "layer": "over", "grow": true, "accent": m4.tier >= 2})
			if m4.has("ring"):
				_shape(o, {"k": "ring", "c": o.pos + Vector2(0, 4), "r0": 10.0, "r": float(m4.ring) * m4.sc, "w": float(m4.get("ring_w", 5.0)) * m4.thick,
					"life": float(m4.get("ring_life", 0.4)), "freeze": 0.0, "layer": "floor"})
			if m4.has("grain"):
				_grains(o, c, o.pos.y, str(m4.grain), int(m4.get("n", 6)), m4)
			_light(o, o.pos, float(m4.get("light_r", 120.0)) * m4.sc, float(m4.get("light_i", 0.7)), float(m4.get("light_life", 0.15)), p.light)
		"swing":
			_swing(o, d)
		"quake":
			var m5: Dictionary = move(o, "quake")
			if m5.is_empty():
				return
			_shape(o, {"k": "ring", "c": d.at, "r0": 12.0, "r": float(d.get("r", 70.0)), "w": float(m5.get("w", 6.0)) * m5.thick * (1.3 if d.get("roar", false) else 1.0),
				"life": float(m5.get("life", 0.3)), "freeze": 0.0, "layer": "floor"})
		"crush":
			var m6: Dictionary = move(o, "crush")
			if m6.is_empty():
				return
			_shape(o, {"k": "crater", "c": d.at, "r": float(m6.get("r", 16.0)) * m6.sc, "life": float(m6.get("life", 0.5)), "freeze": 0.04, "layer": "floor"})
			_grains(o, d.at + Vector2(0, -8), (d.at as Vector2).y, str(m6.get("grain", "rock")), int(m6.get("n", 4)), m6)
		"breach":
			var m7: Dictionary = move(o, "breach")
			if m7.is_empty():
				return
			var pts2: PackedVector2Array = d.pts
			_shape(o, {"k": "crack", "pts": pts2, "w": float(m7.get("w", 9.0)) * m7.thick, "life": float(d.get("life", 0.6)), "freeze": 0.05, "layer": "floor", "grow": true})
			var step: float = float(m7.get("spike_step", 40.0))
			var a0: Vector2 = pts2[0]
			var a1: Vector2 = pts2[pts2.size() - 1]
			var L: float = a0.distance_to(a1)
			var nsp: int = mini(int(m7.get("spike_max", 5)), int(L / step))
			for k2 in nsp:
				var sp: Vector2 = a0.lerp(a1, (k2 + 0.6) / float(nsp + 0.4))
				_shape(o, {"k": "spike", "c": sp, "ang": -PI / 2.0 + g.vrng.randf_range(-0.25, 0.25), "len": float(m7.get("spike_len", 30.0)) * g.vrng.randf_range(0.8, 1.15),
					"w": float(m7.get("spike_w", 9.0)), "life": float(m7.get("spike_life", 0.42)), "freeze": 0.03, "layer": "over", "grow": true, "accent": true,
					"delay": 0.06 + 0.035 * k2})
			_light(o, a0.lerp(a1, 0.5), float(m7.get("light_r", 120.0)), float(m7.get("light_i", 0.55)), 0.15, p.light)
		"leap":
			var m8: Dictionary = move(o, "leap")
			if m8.is_empty():
				return
			_shape(o, {"k": "spike", "c": o.pos, "ang": -PI / 2.0, "len": float(m8.get("len", 40.0)) * m8.sc, "w": float(m8.get("w", 16.0)) * m8.sc,
				"life": float(m8.get("life", 0.14)), "freeze": 0.0, "layer": "over", "grow": true})
			_shape(o, {"k": "crater", "c": d.get("to", o.pos), "r": float(m8.get("mark_r", 26.0)) * m8.sc, "life": float(d.get("t", 0.42)) + 0.05, "freeze": 0.0,
				"layer": "floor", "mark": true})
		"slam":
			var m9: Dictionary = move(o, "slam")
			if m9.is_empty():
				return
			var r9: float = float(d.get("r", 110.0))
			var at9: Vector2 = d.get("at", o.pos)
			_shape(o, {"k": "crater", "c": at9 + Vector2(0, 2), "r": r9 * float(m9.get("crater_k", 0.42)) * m9.sc, "life": float(m9.get("life", 0.7)), "freeze": float(m9.get("freeze", 0.07)),
				"layer": "floor", "accent": m9.tier >= 2})
			_shape(o, {"k": "ring", "c": at9 + Vector2(0, 2), "r0": r9 * 0.3, "r": r9, "w": float(m9.get("ring_w", 9.0)) * m9.thick, "life": float(m9.get("ring_life", 0.32)),
				"freeze": 0.0, "layer": "floor"})
			_grains(o, at9 + Vector2(0, -10), at9.y, str(m9.get("grain", "rock")), int(m9.get("n", 8)), m9)
			_light(o, at9, float(m9.get("light_r", 150.0)) * m9.sc, float(m9.get("light_i", 0.85)), 0.15, p.light)
		"crash":
			var m10: Dictionary = move(o, "crash")
			if m10.is_empty():
				return
			_shape(o, {"k": "star", "c": d.at, "r": float(m10.get("r", 10.0)) * m10.sc, "n": 4, "ang": g.vrng.randf() * PI, "life": 0.16, "freeze": 0.03, "layer": "over"})


## 命中：主形（爆团 / 印 / 碎晶团）+ 颗粒 + 照地
func _hit(o, at: Vector2, gy: float, name: String, dir: Vector2) -> void:
	var m: Dictionary = move(o, name)
	if m.is_empty():
		return
	var p: Dictionary = pal(o)
	if gy == 0.0:
		gy = at.y + 12.0
	var core: String = str(m.get("core", "star"))
	var sh := {"k": core, "c": at, "r": float(m.get("r", 12.0)) * m.sc, "n": int(m.get("points", 5)), "ang": g.vrng.randf() * TAU if core == "star" else 0.0,
		"w": float(m.get("w", 4.0)) * m.thick, "life": float(m.get("life", 0.24)), "freeze": float(m.get("freeze", 0.05)), "layer": "over", "grow": true,
		"accent": m.tier >= 2 and bool(m.get("accent", true))}
	_shape(o, sh)
	if float(m.beat) > 0.0 and bool(m.get("echo", true)):
		# 精一起「多一拍」：同一主形晚 beat 秒再落一次（大一圈、只剩中间色），读作双响
		var e2 := sh.duplicate()
		e2["delay"] = float(m.beat)
		e2["r"] = float(sh.r) * 1.25
		e2["life"] = float(sh.life) * 0.8
		e2["echo"] = true
		e2["ang"] = float(sh.ang) + 0.6
		_shape(o, e2)
	_grains(o, at, gy, str(m.get("grain", "ink")), int(m.get("n", 4)), m, dir)
	_light(o, at, float(m.get("light_r", 80.0)) * m.sc, float(m.get("light_i", 0.5)), float(m.get("light_life", 0.11)), p.light)


## 近战抡锤：身前一道实心弧刃（起手拉伸 → 命中定帧爆亮 → 冷却）+ 落点坑 + 火星 / 碎石；碎颅（heavy）走 s3_swing
func _swing(o, d: Dictionary) -> void:
	var heavy: bool = d.get("heavy", false)
	var m: Dictionary = move(o, "s3_swing" if heavy else "swing")
	if m.is_empty():
		return
	var p: Dictionary = pal(o)
	var ang: float = float(d.get("ang", 0.0))
	var reach: float = float(d.get("reach", 90.0))
	var land: Vector2 = d.get("land", o.pos)
	var c: Vector2 = o.pos + Vector2(0, -14)
	var sh := {"k": "crescent", "c": c, "ang": ang, "r": reach * float(m.get("r_k", 0.78)) * m.sc, "half": float(m.get("half", 1.0)), "w": float(m.get("w", 14.0)) * m.sc * m.thick,
		"life": float(m.get("life", 0.18)), "freeze": float(m.get("freeze", 0.045)), "layer": "over", "sdir": 1.0 if sin(ang) >= 0.0 else -1.0, "accent": m.tier >= 2}
	_shape(o, sh)
	if float(m.beat) > 0.0:
		var e2 := sh.duplicate()
		e2["delay"] = float(m.beat)
		e2["r"] = float(sh.r) * 1.12
		e2["w"] = float(sh.w) * 0.6
		e2["life"] = float(sh.life) * 0.85
		e2["echo"] = true
		_shape(o, e2)
	_shape(o, {"k": "crater", "c": land + Vector2(0, 6), "r": float(m.get("crater_r", 14.0)) * m.sc, "life": float(m.get("crater_life", 0.45)), "freeze": 0.04, "layer": "floor",
		"accent": m.tier >= 2})
	_grains(o, land, land.y + 6.0, str(m.get("grain", "ember")), int(m.get("n", 5)), m, Vector2.from_angle(ang))
	_light(o, land, float(m.get("light_r", 100.0)) * m.sc, float(m.get("light_i", 0.6)), float(m.get("light_life", 0.12)), p.light)


func _shape(o, s: Dictionary) -> void:
	var id: String = str(o.id)
	if not shapes.has(id):
		shapes[id] = []
	var lst: Array = shapes[id]
	s["t0"] = g.t + float(s.get("delay", 0.0))
	s["seed"] = g.vrng.randi()
	lst.append(s)
	if lst.size() > SHAPE_MAX:
		lst.pop_front()


func _light(o, at: Vector2, r: float, inten: float, life: float, col: Color) -> void:
	lights.append([at, r, col, g.t, minf(LIGHT_LIFE_MAX, life), inten, str(o.id)])
	if lights.size() > 32:
		lights.pop_front()


# ================================================================ 装饰颗粒（Noita 式：少、大颗、有重量、落地、会弹）

## 材质：col 色阶（按年龄硬切）、grav 重力（高度轴）、rest 弹性（0 = 不弹）、bounce 最多弹几次、land 落地后停留秒数、sz 颗粒边长（世界像素，2 的倍数）
const MATS := {
	"ink": {"grav": 820.0, "rest": 0.0, "bounce": 0, "land": 0.55, "sz": [4, 4], "spd": [40.0, 120.0], "up": [70.0, 160.0], "life": 0.9},
	"drop": {"grav": 700.0, "rest": 0.0, "bounce": 0, "land": 0.4, "sz": [2, 4], "spd": [4.0, 18.0], "up": [-10.0, 20.0], "life": 0.8},
	"ember": {"grav": 900.0, "rest": 0.38, "bounce": 1, "land": 0.3, "sz": [2, 4], "spd": [60.0, 170.0], "up": [80.0, 210.0], "life": 0.8},
	"rock": {"grav": 1100.0, "rest": 0.3, "bounce": 2, "land": 0.6, "sz": [4, 6], "spd": [50.0, 130.0], "up": [110.0, 230.0], "life": 1.0},
	"shard": {"grav": 760.0, "rest": 0.45, "bounce": 1, "land": 0.35, "sz": [2, 4], "spd": [70.0, 160.0], "up": [90.0, 200.0], "life": 0.8},
}


## at：出生点（画面坐标，已含高度），gy：落地线（脚底世界 y）
func _grains(o, at: Vector2, gy: float, mat: String, n: int, m: Dictionary, dir := Vector2.ZERO) -> void:
	if n <= 0 or not MATS.has(mat):
		return
	var mt: Dictionary = MATS[mat]
	# 拥挤降噪只减装饰层：fx_dim 1 → 0.45 时颗粒数 ×1 → ×0.55
	var k: float = clampf(g.world.fx_dim, 0.0, 1.0) if g.world != null else 1.0
	n = maxi(1, int(round(n * lerpf(0.55, 1.0, k) * float(m.get("grain_k", 1.0)))))
	var cap: int = int(Bal.v("fx/recipe_grains", 160.0))
	var h0: float = maxf(0.0, gy - at.y)
	for i in n:
		if parts.size() >= cap:
			parts.pop_front()
		var a: float = g.vrng.randf() * TAU
		if dir != Vector2.ZERO:
			a = dir.angle() + g.vrng.randf_range(-0.9, 0.9)
		var spd: float = g.vrng.randf_range(float(mt.spd[0]), float(mt.spd[1])) * float(m.get("grain_spd", 1.0))
		var sz: int = int(mt.sz[0]) if g.vrng.randf() < 0.5 else int(mt.sz[1])
		parts.append({"op": str(o.id), "m": mat, "gp": Vector2(at.x, gy), "h": h0, "v": Vector2(cos(a), sin(a) * SY) * spd,
			"vh": g.vrng.randf_range(float(mt.up[0]), float(mt.up[1])), "age": 0.0, "life": float(mt.life) * g.vrng.randf_range(0.8, 1.2),
			"sz": sz, "nb": 0, "landed": -1.0, "accent": m.get("tier", 0) >= 2 and mat == "shard"})


func _step() -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _step_frame:
		return
	_step_frame = fr
	var dt: float = 0.0 if _t_last < 0.0 else clampf(g.t - _t_last, 0.0, 0.1)
	_t_last = g.t
	if dt <= 0.0:
		return
	var keep: Array = []
	for q in parts:
		var mt: Dictionary = MATS[q.m]
		q.age = float(q.age) + dt
		if float(q.landed) >= 0.0:
			q.landed = float(q.landed) + dt
			if float(q.landed) < float(mt.land):
				keep.append(q)
			continue
		q.gp = q.gp + q.v * dt
		q.v = q.v * maxf(0.0, 1.0 - 1.2 * dt)
		q.vh = float(q.vh) - float(mt.grav) * dt
		q.h = float(q.h) + float(q.vh) * dt
		if float(q.h) <= 0.0:
			q.h = 0.0
			if int(q.nb) < int(mt.bounce) and absf(float(q.vh)) > 60.0:
				q.nb = int(q.nb) + 1
				q.vh = -float(q.vh) * float(mt.rest)
				q.v = q.v * 0.55
			else:
				q.landed = 0.0
		if float(q.age) < float(q.life) + float(mt.land):
			keep.append(q)
	parts = keep
	var now: float = g.t
	lights = lights.filter(func(L): return now - float(L[3]) < float(L[4]))
	for id in shapes:
		var lst: Array = shapes[id]
		shapes[id] = lst.filter(func(s): return now - float(s.t0) < float(s.life) + 0.02)


# ================================================================ 光（照地；全局光源预算 + 上限）

## optical._dyn_lights 调：返回至多 fx/recipe_dl 盏（缺省 4，且不超过总灯数一半），强度总和封顶 fx/recipe_dl_sum（缺省 1.8）；
## 每盏寿命 ≤ 0.15 秒、强度随寿命线性衰减。格式同 optical 候选 [强度, 位置, 半径, 颜色]
static func lights_for(game, vr: Rect2, nmax: int) -> Array:
	if game == null or not game.has_meta("fx_recipe"):
		return []
	var r = game.get_meta("fx_recipe")
	if not r.enabled() or r.lights.is_empty():
		r.stat_lights = 0
		return []
	var cand: Array = []
	for L in r.lights:
		var age: float = game.t - float(L[3])
		if age < 0.0 or age >= float(L[4]) or not vr.has_point(L[0]):
			continue
		var k: float = 1.0 - age / maxf(0.001, float(L[4]))
		cand.append([float(L[5]) * k, L[0], float(L[1]), L[2]])
	cand.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var n: int = mini(int(Bal.v("fx/recipe_dl", 4.0)), nmax / 2)
	cand = cand.slice(0, maxi(0, n))
	var sum := 0.0
	for c in cand:
		sum += float(c[0])
	var cap: float = Bal.v("fx/recipe_dl_sum", 1.8)
	if sum > cap:
		for c in cand:
			c[0] = float(c[0]) * cap / sum
	r.stat_lights = cand.size()
	return cand


# ================================================================ 绘制

## 地面层（data_operator.draw_entities_floor 接管时调；敌人之下）：落点坑、冲击环、地裂、扇形咒域、号令波、铭文
func draw_floor(o) -> void:
	_step()
	if o.pos == Vector2.INF:
		return
	var cv = o.cv
	var p: Dictionary = pal(o)
	var keep_mod := _core_mod(cv)
	_draw_state_floor(o, cv, p)
	for s in shapes.get(str(o.id), []):
		if str(s.layer) == "floor":
			_draw_shape(cv, s, p)
	_restore_mod(cv, keep_mod)


## 区域层（draw_auras 接管时调）：持续技能的场
func draw_auras(o) -> void:
	_step()
	if o.pos == Vector2.INF:
		return
	var cv = o.cv
	var keep_mod := _core_mod(cv)
	if o.hw.has("fan"):
		_draw_fan(o, cv, pal(o))
	if o.hw.has("s3_shots"):   # 原画法在绘制时清理出手轨迹；接管后由这里清，免得列表只增不减
		var now: float = g.t
		o.hw["s3_shots"] = o.hw.s3_shots.filter(func(sh): return now - float(sh.t0) < 0.3)
	_restore_mod(cv, keep_mod)


## 上层（_draw_skill_over 接管时调）：投射弹、锁定光束、链、主形、颗粒
func draw_over(o) -> void:
	_step()
	var cv = o.cv
	var p: Dictionary = pal(o)
	var keep_mod := _core_mod(cv)
	_draw_state_over(o, cv, p)
	for s in shapes.get(str(o.id), []):
		if str(s.layer) == "over":
			_draw_shape(cv, s, p)
	_restore_mod(cv, keep_mod)
	_draw_parts(o, cv, p)   # 装饰层：沿用 squad 设好的降噪系数，再乘 fx_dim


## 核心层不受拥挤降噪：临时把合批画布的透明度系数拉回 1（保留队长提亮 / 量测静音）
func _core_mod(cv) -> Array:
	var keep := [cv.amul, cv.dsat, cv.boost, cv.tint]
	cv.set_mod(1.0, 0.0, cv.boost, cv.tint)
	return keep


func _restore_mod(cv, k: Array) -> void:
	cv.set_mod(float(k[0]), float(k[1]), float(k[2]), float(k[3]))


## 三阶色：t = 年龄，freeze 定帧爆亮期（暗 → 主、主 → 热、热 → 白热），之后冷却（u > 0.5 起热芯熄、u > 0.78 只剩暗边 + 主色收缩）
static func _tones(p: Dictionary, age: float, life: float, freeze: float, accent: bool) -> Array:
	var dark: Color = p.dark
	var main: Color = p.main
	var hot: Color = p.hot
	if accent:
		if str(p.get("accent_on", "body")) == "rim":
			dark = p.accent
		else:
			main = p.accent
	if age < freeze:
		# 定帧爆亮：主体 → 热色、热芯 → 白热；外边仍是暗边（和敌人受击白闪分得开）
		return [dark, hot, Color(hot.r * 1.6, hot.g * 1.6, hot.b * 1.6), 1.0]
	var u: float = clampf((age - freeze) / maxf(0.001, life - freeze), 0.0, 1.0)
	if u < 0.5:
		return [dark, main, Color(hot.r * 1.25, hot.g * 1.25, hot.b * 1.25), 1.0 - 0.15 * u]
	if u < 0.78:
		return [dark, main.lerp(dark, 0.35), main, 0.85 - 0.25 * (u - 0.5)]
	return [Color(dark.r, dark.g, dark.b, 0.85), main.lerp(dark, 0.65), Color(0, 0, 0, 0), 0.62 - 0.6 * (u - 0.78)]


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


func _draw_shape(cv, s: Dictionary, p: Dictionary) -> void:
	var age: float = g.t - float(s.t0)
	if age < 0.0:
		return
	var life: float = float(s.life)
	var tn: Array = _tones(p, age, life, float(s.get("freeze", 0.0)), s.get("accent", false))
	if s.get("echo", false):
		tn = [tn[0], tn[1], Color(0, 0, 0, 0), float(tn[3]) * 0.9]
	var u: float = clampf(age / maxf(0.001, life), 0.0, 1.0)
	# 体量：grow 的主形前 18% 从 0.55 弹到 1.08 再落回 1（起手拉伸 / 冲出），最后 30% 收缩
	var gk: float = 1.0
	if s.get("grow", false):
		gk = lerpf(0.55, 1.08, clampf(u / 0.18, 0.0, 1.0)) if u < 0.18 else lerpf(1.08, 1.0, clampf((u - 0.18) / 0.15, 0.0, 1.0))
	if u > 0.7:
		gk *= 1.0 - 0.45 * (u - 0.7) / 0.3
	match str(s.k):
		"ring":
			_draw_ring(cv, s, tn, u)
			return
		"crack":
			_draw_crack(cv, s, tn, u)
			return
	var layers: Array = [[1.0, tn[0]], [0.72, tn[1]], [0.36, tn[2]]]
	for L in layers:
		var col: Color = L[1]
		if col.a <= 0.0:
			continue
		col.a *= float(tn[3])
		for poly in _geo(s, gk, float(L[0])):
			if poly.size() >= 3:
				cv.draw_colored_polygon(poly, col)


## 形状库：返回若干多边形（世界坐标、对齐 2 px 格）；k = 粗细层（1 外暗边 / 0.72 主体 / 0.36 热芯），gk = 体量
func _geo(s: Dictionary, gk: float, k: float) -> Array:
	var c: Vector2 = s.get("c", Vector2.ZERO)
	match str(s.k):
		"star":   # 爆团：n 角硬边星，内角半径 0.42
			var r: float = float(s.r) * gk * (0.45 + 0.55 * k)
			var n: int = maxi(3, int(s.get("n", 5)))
			var pts := PackedVector2Array()
			for i in n * 2:
				var a: float = float(s.get("ang", 0.0)) + PI * i / n
				var rr: float = r if i % 2 == 0 else r * 0.42
				pts.append(_snap(c + Vector2(cos(a), sin(a) * 0.85) * rr))
			return [pts]
		"seal":   # 印（逻各斯精二命中）：45° 方框（四条实心边）+ 中心菱形
			var r2: float = float(s.r) * gk
			var w: float = maxf(2.0, float(s.get("w", 4.0)) * (0.5 + k))
			var out: Array = []
			var cs: Array = [Vector2(0, -r2), Vector2(r2, 0), Vector2(0, r2), Vector2(-r2, 0)]
			for i in 4:
				var a0: Vector2 = cs[i]
				var a1: Vector2 = cs[(i + 1) % 4]
				var nv: Vector2 = (a1 - a0).orthogonal().normalized() * w * 0.5
				out.append(PackedVector2Array([_snap(c + a0 - nv), _snap(c + a1 - nv), _snap(c + a1 + nv), _snap(c + a0 + nv)]))
			var d: float = r2 * 0.42 * (0.5 + 0.5 * k)
			out.append(PackedVector2Array([_snap(c + Vector2(0, -d)), _snap(c + Vector2(d, 0)), _snap(c + Vector2(0, d)), _snap(c + Vector2(-d, 0))]))
			return out
		"spike":   # 突刺：从 c 沿 ang 伸出 len 的实心菱刺，最宽处在 25%
			var L: float = float(s.len) * gk * (0.8 + 0.2 * k)
			var w2: float = float(s.w) * k
			var dv := Vector2.from_angle(float(s.ang))
			var nv2: Vector2 = dv.orthogonal()
			return [PackedVector2Array([_snap(c - dv * L * 0.06), _snap(c + dv * L * 0.25 + nv2 * w2 * 0.5), _snap(c + dv * L), _snap(c + dv * L * 0.25 - nv2 * w2 * 0.5)])]
		"crescent":   # 弧刃：中间厚两头尖的月牙，内外沿都是圆弧（y × 0.8 贴地透视）
			var R: float = float(s.r) * gk
			var half: float = float(s.half)
			var th: float = float(s.w) * k
			var a0c: float = float(s.ang)
			var N := 14
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in N + 1:
				var t: float = float(i) / N
				var a: float = a0c - half + 2.0 * half * t
				var prof: float = pow(sin(PI * t), 0.65)
				var ro: float = R + th * 0.5 * prof
				var ri: float = R - th * 0.5 * prof
				outer.append(_snap(c + Vector2(cos(a) * ro, sin(a) * ro * 0.8)))
				inner.append(_snap(c + Vector2(cos(a) * ri, sin(a) * ri * 0.8)))
			inner.reverse()
			outer.append_array(inner)
			return [outer]
		"crater":   # 落点坑（地面）：不规则扁椭圆，种子定形
			var r3: float = float(s.r) * gk * (0.7 + 0.3 * k) * (1.0 if not s.get("mark", false) else (0.6 + 0.4 * k))
			var sd: int = int(s.seed)
			var pts3 := PackedVector2Array()
			for i in 10:
				var a: float = TAU * i / 10.0
				var j: float = 0.78 + 0.22 * float((sd >> (i * 3)) & 7) / 7.0
				pts3.append(_snap(c + Vector2(cos(a), sin(a) * SY) * r3 * j))
			return [pts3]
		"beam":   # 光束：两端收尖的实心带
			var a: Vector2 = s.a
			var b: Vector2 = s.b
			var w3: float = float(s.w) * k * gk
			var dv3: Vector2 = (b - a).normalized()
			var nv3: Vector2 = dv3.orthogonal() * w3 * 0.5
			var L3: float = a.distance_to(b)
			var e: float = minf(L3 * 0.2, 10.0)
			return [PackedVector2Array([_snap(a), _snap(a + dv3 * e + nv3), _snap(b - dv3 * e + nv3), _snap(b), _snap(b - dv3 * e - nv3), _snap(a + dv3 * e - nv3)])]
		"tear":   # 投射弹头：水滴形（尖朝前）
			var L4: float = float(s.len) * gk * (0.6 + 0.4 * k)
			var w4: float = float(s.w) * gk * k
			var dv4 := Vector2.from_angle(float(s.ang))
			var nv4: Vector2 = dv4.orthogonal()
			return [PackedVector2Array([_snap(c + dv4 * L4 * 0.6), _snap(c + dv4 * L4 * 0.05 + nv4 * w4 * 0.5), _snap(c - dv4 * L4 * 0.3 + nv4 * w4 * 0.32),
				_snap(c - dv4 * L4 * 0.4), _snap(c - dv4 * L4 * 0.3 - nv4 * w4 * 0.32), _snap(c + dv4 * L4 * 0.05 - nv4 * w4 * 0.5)])]
		"spear3":   # 三叉墨枪（逻各斯精二弹头）：中锋长菱 + 两侧倒钩
			var L5: float = float(s.len) * gk * (0.7 + 0.3 * k)
			var w5: float = float(s.w) * gk * k
			var dv5 := Vector2.from_angle(float(s.ang))
			var nv5: Vector2 = dv5.orthogonal()
			var mid := PackedVector2Array([_snap(c + dv5 * L5 * 0.7), _snap(c + nv5 * w5 * 0.4), _snap(c - dv5 * L5 * 0.45), _snap(c - nv5 * w5 * 0.4)])
			var out5: Array = [mid]
			for sg in [-1.0, 1.0]:
				var base: Vector2 = c - dv5 * L5 * 0.1 + nv5 * w5 * 0.35 * sg
				out5.append(PackedVector2Array([_snap(base + dv5 * L5 * 0.32 + nv5 * w5 * 0.5 * sg), _snap(base - dv5 * L5 * 0.18 + nv5 * w5 * 0.15 * sg), _snap(base - nv5 * w5 * 0.25 * sg)]))
			return out5
	return []


## 冲击环 / 号令波（地面）：一条实心厚带从 r0 扩到 r（缓出），三阶：外暗边 → 主色 → 热芯细线
func _draw_ring(cv, s: Dictionary, tn: Array, u: float) -> void:
	var e: float = 1.0 - pow(1.0 - u, 2.2)
	var rr: float = lerpf(float(s.get("r0", 10.0)), float(s.r), e)
	var w: float = float(s.w) * (1.0 - 0.55 * u)
	var c: Vector2 = s.c
	cv.draw_set_transform(_snap(c), 0.0, Vector2(1.0, SY))
	var al: float = float(tn[3])
	var segs: int = clampi(int(rr / 3.0), 16, 56)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, segs, Color(tn[0].r, tn[0].g, tn[0].b, tn[0].a * al), w + 4.0)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, segs, Color(tn[1].r, tn[1].g, tn[1].b, tn[1].a * al), w)
	if (tn[2] as Color).a > 0.0:
		cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, segs, Color(tn[2].r, tn[2].g, tn[2].b, tn[2].a * al), maxf(2.0, w * 0.35))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 地裂：前 0.08 秒向前裂开，暗边 + 熔芯 + 白热细芯
func _draw_crack(cv, s: Dictionary, tn: Array, u: float) -> void:
	var pts: PackedVector2Array = s.pts
	var age: float = g.t - float(s.t0)
	var grow: float = clampf(age / 0.08, 0.0, 1.0)
	var m: int = maxi(2, int(ceil(pts.size() * grow)))
	var sub: PackedVector2Array = pts.slice(0, m)
	var w: float = float(s.w) * (1.0 - 0.5 * u)
	var al: float = float(tn[3])
	cv.draw_polyline(sub, Color(tn[0].r, tn[0].g, tn[0].b, tn[0].a * al), w + 4.0)
	cv.draw_polyline(sub, Color(tn[1].r, tn[1].g, tn[1].b, tn[1].a * al), w)
	if (tn[2] as Color).a > 0.0:
		cv.draw_polyline(sub, Color(tn[2].r, tn[2].g, tn[2].b, tn[2].a * al), maxf(2.0, w * 0.3))


## 颗粒：硬边方块，按年龄硬切色阶；落地后变暗、扁成 2 格宽的点，停留后熄灭（墨点 / 碎石 / 冷掉的火星）
func _draw_parts(o, cv, p: Dictionary) -> void:
	var id: String = str(o.id)
	var dim: float = clampf(g.world.fx_dim, 0.0, 1.0) if g.world != null else 1.0
	var n := 0
	for q in parts:
		if str(q.op) != id:
			continue
		n += 1
		var mt: Dictionary = MATS[q.m]
		var sz: float = float(q.sz)
		var col: Color
		var u: float = clampf(float(q.age) / maxf(0.001, float(q.life)), 0.0, 1.0)
		match str(q.m):
			"ink", "drop":
				col = p.main if u < 0.25 else p.dark.lerp(p.main, 0.3)
			"ember":
				col = p.hot if u < 0.2 else (p.main if u < 0.55 else p.main.lerp(p.dark, 0.6))
			"rock":
				col = p.main.lerp(p.dark, 0.3) if u < 0.12 else Color(0.22, 0.2, 0.21)
			"shard":
				col = p.accent if q.get("accent", false) else p.hot
				if u > 0.4:
					col = col.lerp(p.dark, 0.5)
			_:
				col = p.main
		var pos: Vector2 = q.gp - Vector2(0, float(q.h))
		var size := Vector2(sz, sz)
		if float(q.landed) >= 0.0:
			var lk: float = float(q.landed) / maxf(0.01, float(mt.land))
			col = col.lerp(p.dark, 0.5 + 0.4 * lk)
			if lk > 0.66:
				col.a *= 0.5   # 熄灭前一阶
			size = Vector2(sz + 2.0, maxf(2.0, sz - 2.0))
		col.a *= dim
		cv.draw_rect(Rect2(_snap(pos), size), col)
	stat_parts = n


# ---------------------------------------------------------------- 状态驱动的主形（直接读玩法状态，只画）

func _draw_state_over(o, cv, p: Dictionary) -> void:
	var h: Dictionary = o.hw
	if h.has("bolts"):
		_draw_bolts(o, cv, p)
		_draw_lock(o, cv, p)
		_draw_links(o, cv, p)


func _draw_state_floor(o, cv, p: Dictionary) -> void:
	var h: Dictionary = o.hw
	if h.has("pools"):
		_draw_pools(o, cv, p)
	if h.has("sg"):
		_draw_waves(o, cv, p)


## 逻各斯「言」：弹头（E0 水滴 / E1 大一号加厚 / E2 三叉墨枪 + 点缀色）+ 实心收尖拖尾；飞行中滴墨（装饰）
func _draw_bolts(o, cv, p: Dictionary) -> void:
	var m: Dictionary = move(o, "bolt")
	if m.is_empty():
		return
	var head: String = str(m.get("head", "tear"))
	for bo in o.hw.bolts:
		var pose: Array = _bolt_pose(bo)
		var at: Vector2 = pose[0]
		var hist: Array = bo.get("visual", {}).get("hist", bo.hist)
		var s := {"k": head, "c": at, "ang": float(pose[1]), "len": float(m.get("len", 14.0)) * m.sc, "w": float(m.get("w", 8.0)) * m.sc * m.thick}
		# 拖尾：沿历史点的实心收尖带（暗边 + 主色），长度随档位
		if hist.size() >= 2:
			var tw: float = float(m.get("trail_w", 5.0)) * m.sc * m.thick
			for i in range(1, hist.size()):
				var k: float = float(i) / float(hist.size())
				var a0: Vector2 = hist[i - 1]
				var a1: Vector2 = hist[i]
				cv.draw_line(_snap(a0), _snap(a1), Color(p.dark.r, p.dark.g, p.dark.b, 0.9), maxf(2.0, tw * k + 2.0))
				cv.draw_line(_snap(a0), _snap(a1), p.main if m.tier < 2 else p.accent, maxf(2.0, tw * k * 0.6))
		var age: float = float(bo.get("age", 0.0))
		var hot: bool = age < 0.06   # 出手首帧亮一下
		for L in [[1.0, p.dark], [0.66, p.main if m.tier < 2 else p.accent], [0.3, p.hot if not hot else Color(2.0, 2.0, 2.2)]]:
			for poly in _geo(s, 1.0 + (0.25 if hot else 0.0), float(L[0])):
				if poly.size() >= 3:
					cv.draw_colored_polygon(poly, L[1])
		# 滴墨：每 shed 秒一滴（画面计时，按弹的年龄定，不抽玩法随机）
		var sh: float = float(m.get("shed", 0.1))
		if sh > 0.0 and int(age / sh) != int(bo.get("_fxr_drip", -1)):
			bo["_fxr_drip"] = int(age / sh)
			var tg: Dictionary = bo.get("e", {})
			var gy: float = (tg.pos.y if not tg.is_empty() else at.y) + 8.0
			_grains(o, at, maxf(gy, at.y + 18.0), "drop", 1, m)
		_light_follow(o, at, float(m.get("light_r", 46.0)) * m.sc, float(m.get("light_i", 0.22)), p.light)


func _light_follow(o, at: Vector2, r: float, inten: float, col: Color) -> void:
	if inten <= 0.0:
		return
	lights.append([at, r, col, g.t, 0.05, inten, str(o.id)])
	if lights.size() > 32:
		lights.pop_front()


## 同 seg_logos.hw_bolt_pose（弧线只用于显示；这里不 preload 积木脚本，免得循环引用）
static func _bolt_pose(bo: Dictionary) -> Array:
	if not bo.has("visual"):
		var hist: Array = bo.hist
		return [bo.pos, (bo.pos - hist[-2]).angle() if hist.size() >= 2 else 0.0]
	var v: Dictionary = bo.visual
	var cfg: Dictionary = bo.b.flight_visual
	var delta: Vector2 = bo.to - v.start
	var axis: Vector2 = delta.normalized()
	var normal := Vector2(axis.y, -axis.x)
	var lift := clampf(delta.length() * float(cfg.arc_lift[int(v.variant)]), -float(cfg.max_lift), float(cfg.max_lift))
	var u: float = v.u
	return [v.start.lerp(bo.to, u) + normal * (4.0 * lift * u * (1.0 - u)), (delta + normal * (4.0 * lift * (1.0 - 2.0 * u))).angle()]


## 提喻（S1）锁定：笔尖 → 目标一道实心光束，粗细随叠层；E2 变成一串咒文菱节（锁链）；目标处一枚旋转的方印
func _draw_lock(o, cv, p: Dictionary) -> void:
	var lk = o.hw.get("lock", {})
	if not (lk is Dictionary) or lk.is_empty() or float(lk.t) <= 0.0 or lk.e == null or lk.e.dead:
		return
	var m: Dictionary = move(o, "s1")
	if m.is_empty():
		return
	var tipv = o.B.get("attack", {}).get("tip", [40, -36])
	var a: Vector2 = o.pos + Vector2(float(tipv[0]) * float(o.face), float(tipv[1]))
	var b: Vector2 = lk.e.pos + Vector2(0, -lk.e.r * 0.5)
	var ramp: float = clampf(int(lk.n) / float(lk.b.get("ramp_n", 12.0)), 0.0, 1.0)
	var w: float = (float(m.get("w", 4.0)) + float(m.get("w_ramp", 4.0)) * ramp) * m.sc * m.thick
	var head: float = minf(1.0, (int(lk.n) * float(lk.b.get("tick", 0.25)) + float(lk.tick)) / maxf(0.05, float(lk.b.get("tick", 0.25))))
	var bb: Vector2 = a.lerp(b, head)
	if m.get("chain", false):
		var L: float = a.distance_to(bb)
		var step: float = float(m.get("link", 12.0)) * m.sc
		var dv: Vector2 = (bb - a).normalized()
		var nlk: int = maxi(1, int(L / step))
		var scroll: float = fmod(g.t * 60.0, step)
		for i in nlk:
			var cc: Vector2 = a + dv * (step * i + scroll)
			if cc.distance_to(a) > L:
				break
			var s := {"k": "spike", "c": cc - dv * step * 0.4, "ang": dv.angle(), "len": step * 0.9, "w": w * 1.4}
			for Ly in [[1.0, p.dark], [0.66, p.accent if i % 2 == 0 else p.main]]:
				for poly in _geo(s, 1.0, float(Ly[0])):
					cv.draw_colored_polygon(poly, Ly[1])
	else:
		var s2 := {"k": "beam", "a": a, "b": bb, "w": w}
		for Ly in [[1.0, p.dark], [0.66, p.main], [0.3, p.hot]]:
			for poly in _geo(s2, 1.0, float(Ly[0])):
				cv.draw_colored_polygon(poly, Ly[1])
	if head >= 1.0:
		var seal := {"k": "seal", "c": b, "r": (8.0 + 5.0 * ramp) * m.sc, "w": 3.0 * m.thick}
		var rot: float = g.t * 3.0
		for Ly in [[1.0, p.dark], [0.66, p.accent if m.tier >= 2 else p.main]]:
			for poly in _geo(seal, 1.0, float(Ly[0])):
				var pr := PackedVector2Array()
				for v in poly:
					pr.append(_snap(b + (v - b).rotated(rot)))
				cv.draw_colored_polygon(pr, Ly[1])
	_light_follow(o, b, float(m.get("light_r", 60.0)) * m.sc, float(m.get("light_i", 0.25)) * (0.6 + 0.4 * ramp), p.light)


## 精二连缀：成员之间的实心锁链（菱节，点缀色 / 主色交替），成员处一枚小方印
func _draw_links(o, cv, p: Dictionary) -> void:
	var h: Dictionary = o.hw
	if not h.has("links") or h.links.is_empty():
		return
	var m: Dictionary = move(o, "link")
	if m.is_empty():
		return
	for lk in h.links:
		var mm: Array = lk.m
		var a0: Dictionary = mm[0]
		if a0.dead:
			continue
		var al: float = clampf(float(lk.t) / 0.25, 0.0, 1.0)
		var pa: Vector2 = a0.pos + Vector2(0, -float(a0.r) * 0.6)
		for i in range(1, mm.size()):
			var q: Dictionary = mm[i]
			if q.dead:
				continue
			var pb: Vector2 = q.pos + Vector2(0, -float(q.r) * 0.6)
			var L: float = pa.distance_to(pb)
			var step: float = float(m.get("link", 12.0))
			var dv: Vector2 = (pb - pa).normalized()
			var nlk: int = maxi(1, int(L / step))
			for j in nlk:
				var s := {"k": "spike", "c": pa + dv * step * j, "ang": dv.angle(), "len": step * 0.9, "w": float(m.get("w", 5.0))}
				for Ly in [[1.0, p.dark], [0.6, p.accent if j % 2 == 0 else p.main]]:
					var col: Color = Ly[1]
					col.a *= al
					for poly in _geo(s, 1.0, float(Ly[0])):
						cv.draw_colored_polygon(poly, col)


## 铭文 / 墓志铭（地面）：一枚实心方印，墓志铭从 0 写满再收
func _draw_pools(o, cv, p: Dictionary) -> void:
	for l in o.hw.pools:
		if str(l.b.get("look", "")) != "rune":
			continue
		var burst: bool = l.b.get("burst", false)
		var k: float = 1.0 - float(l.t) / maxf(0.01, float(l.dur)) if burst else 1.0
		var al: float = clampf(float(l.t) / 0.3, 0.0, 1.0)
		var r: float = float(l.r) * (0.5 if not burst else 0.35 + 0.5 * k)
		var c: Vector2 = l.pos + Vector2(0, 4)
		var s := {"k": "seal", "c": c, "r": r, "w": 3.0 if not burst else 5.0}
		for Ly in [[1.0, p.dark], [0.6, p.main]]:
			var col: Color = Ly[1]
			col.a *= al * (0.8 if not burst else 1.0)
			for poly in _geo(s, 1.0, float(Ly[0])):
				var pr := PackedVector2Array()
				for v in poly:
					pr.append(_snap(c + Vector2((v - c).x, (v - c).y * SY)))
				cv.draw_colored_polygon(pr, col)


## 延异视阈（S3）：贴地实心扇形（暗墨底 α 0.3 + 主色硬边 3 阶），一道热色扫线沿弧走；E1 加一道内弧，E2 弧上一排点缀色笔画
func _draw_fan(o, cv, p: Dictionary) -> void:
	var h: Dictionary = o.hw
	var fn = h.get("fan", {})
	if not (fn is Dictionary) or fn.is_empty() or float(fn.t) <= 0.0:
		return
	var m: Dictionary = move(o, "s3")
	if m.is_empty():
		return
	var b: Dictionary = fn.b
	var r: float = _fan_r(o, b)
	var half: float = deg_to_rad(float(b.get("deg", 100.0))) * 0.5
	var fa: float = float(h.fan_ang)
	var dur: float = float(b.get("dur", 12.0))
	var el: float = dur - float(fn.t)
	var open: float = clampf(el / 0.35, 0.0, 1.0)
	var fade: float = clampf(float(fn.t) / 0.35, 0.0, 1.0)
	var rr: float = r * (0.6 + 0.4 * (1.0 - pow(1.0 - open, 2.0)))
	var c: Vector2 = o.pos
	var N := 20
	var pts := PackedVector2Array([_snap(c)])
	for i in N + 1:
		var a: float = fa - half + 2.0 * half * i / N
		pts.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * rr))
	var dk: Color = p.dark
	cv.draw_colored_polygon(pts, Color(dk.r, dk.g, dk.b, float(m.get("fill_a", 0.32)) * fade))
	var ew: float = float(m.get("edge_w", 4.0)) * m.thick
	var arc := pts.slice(1)
	var mc: Color = p.main
	cv.draw_polyline(arc, Color(dk.r, dk.g, dk.b, 0.9 * fade), ew + 4.0)
	cv.draw_polyline(arc, Color(mc.r, mc.g, mc.b, fade), ew)
	cv.draw_line(_snap(c), arc[0], Color(mc.r, mc.g, mc.b, 0.8 * fade), maxf(2.0, ew * 0.6))
	cv.draw_line(_snap(c), arc[arc.size() - 1], Color(mc.r, mc.g, mc.b, 0.8 * fade), maxf(2.0, ew * 0.6))
	# 扫线：每个伤害周期从一侧扫到另一侧（热色实心刺）
	var tk: float = float(b.get("tick", 0.5))
	var u: float = 1.0 - clampf(float(fn.get("tick", 0.0)) / maxf(0.05, tk), 0.0, 1.0)
	var sa: float = fa - half + 2.0 * half * u
	var sw := {"k": "spike", "c": c + Vector2(cos(sa), sin(sa) * 0.8) * rr * 0.25, "ang": atan2(sin(sa) * 0.8, cos(sa)), "len": rr * 0.75, "w": ew * 1.6}
	for Ly in [[0.66, p.main], [0.3, p.hot]]:
		var col: Color = Ly[1]
		col.a *= fade
		for poly in _geo(sw, 1.0, float(Ly[0])):
			cv.draw_colored_polygon(poly, col)
	if m.tier >= 1:   # 精一：内弧一道（多一拍）
		var inner := PackedVector2Array()
		for i in N + 1:
			var a: float = fa - half + 2.0 * half * i / N
			inner.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * rr * 0.62))
		cv.draw_polyline(inner, Color(mc.r, mc.g, mc.b, 0.7 * fade), maxf(2.0, ew * 0.6))
	if m.tier >= 2:   # 精二：弧外一排点缀色竖笔画（主形本身变：扇面变「书页」）
		var ac: Color = p.accent
		for i in 9:
			var a: float = fa - half + 2.0 * half * (i + 0.5) / 9.0
			var q: Vector2 = c + Vector2(cos(a), sin(a) * 0.8) * (rr + 10.0)
			var hh: float = 14.0 + 6.0 * float((i * 7) % 3)
			var st := {"k": "spike", "c": q, "ang": -PI / 2.0, "len": hh * (0.8 + 0.2 * sin(g.t * 4.0 + i)), "w": 7.0}
			for Ly in [[1.0, p.dark], [0.6, ac]]:
				var col2: Color = Ly[1]
				col2.a *= fade
				for poly in _geo(st, 1.0, float(Ly[0])):
					cv.draw_colored_polygon(poly, col2)


## 扇形半径与判定同一个函数（运行时 load，不 preload 积木脚本，免得循环引用）
static func _fan_r(o, b: Dictionary) -> float:
	return float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, b))


## 号令波（推进之王 S1 + 万兽之王）：贴地厚环，随玩法半径扩张
func _draw_waves(o, cv, p: Dictionary) -> void:
	var sg: Dictionary = o.hw.sg
	if sg.waves.is_empty():
		return
	var m: Dictionary = move(o, "wave")
	if m.is_empty():
		return
	for w in sg.waves:
		var dur: float = float(w.b.get("dur", 0.4))
		var fade: float = clampf(1.0 - (float(w.t) - dur) / 0.25, 0.0, 1.0) if float(w.t) > dur else 1.0
		var tn: Array = _tones(p, float(w.t), dur + 0.25, 0.05, m.tier >= 2)
		var s := {"c": w.pos, "r0": float(w.r), "r": float(w.r), "w": float(m.get("w", 10.0)) * m.thick}
		tn[3] = float(tn[3]) * fade
		_draw_ring(cv, s, tn, 0.0)
