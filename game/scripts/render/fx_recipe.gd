## 运行时攻击特效配方（docs/245）：开关 fx/recipe（缺省 0 = 关）。
## 11-05 第二轮（docs/245 §5）：用户要「以原作技能特效为底的本作改编，更显眼」——主形按原作轮廓与配色在运行时像素化重建
## （逻各斯：墨迹彗星「言」、四芒星芒、白色不规则碎芒、咒文字块、地面椭圆咒域；推进之王：银橙旋光、白热闪、熔岩裂网、前向枝裂、锤徽、黑三角碎块），
## 改编部分：比原作大、命中定帧爆亮、少量大颗 Noita 颗粒（墨滴 / 火星线 / 三角碎块 / 暗烟）、照地光；同一招元素 ≤ 3 种。
## 精英三档：E1 = 同主形 ×1.2–1.3 + 加厚 + 多一拍 + 一处形状差（八芒、燕尾、双行咒文、齿轮、小裂网 …）；E2 = 换原作更高阶的意象、体量 ×1.5。
## 节奏「蓄势 → 命中定帧爆亮 → 冷却余韵」；分两层：核心（主形，不受拥挤降噪）/ 装饰（颗粒，按 world.fx_dim 和拥挤度减量减淡）。
## 每名干员一份数据 data/fx_recipes/<id>.json（形状尺寸、颜色组、质感、光、各精英档怎么变）；只有有配方的干员被接管。
## 接管 = 该干员原来的攻击 / 技能画面（帧条、pfx、刀光、命中颗粒）只跳过绘制或不生成画面件；玩法调用、玩法随机数一律照旧（同 seed TRACE 逐行一致）。
## 画面随机只用 g.vrng（形状的不规则度用种子散列 _h）。坐标是世界坐标，画在 squad.cv（合批画布，进低分辨率层：多边形自然落在 2 px 格上 = 硬边像素形）。
## 原作参照素材只在本机 Claude outputs/（logos_ref / siege_ref / fx_canon_1105），不进 git / 包。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Pxp = preload("res://scripts/render/fx_pxplane.gd")   # docs/246 转平面试验（fx/px_plane）：斯卡蒂借这里的接管、颗粒、灯光预算
const DIR := "res://data/fx_recipes/"
const PXP_DIR := "res://data/fx_pxplane/"
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
var reacts := {}          # 受击反应（fx/recipe_hitreact）：敌人 id → [命中时刻, 颜色, 停顿到, 冻结的选帧时间]
var _x_frame := -1
var _x_outline := false
var _x_hitlight := false
var _x_react := false
var stat_lights := 0      # 量测：上一帧送进 optical 的灯数
var stat_parts := 0


static func of(game):
	if game == null or not (game is Object):
		return null   # 契约测试的假 g 是 Dictionary（eyja_volcanic_weight）：不接管
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
		_on = (Bal.v("fx/recipe", 0.0) > 0.0 or Bal.v("fx/px_plane", 0.0) > 0.0) and not g.headless_batch
	return _on


const _NONE := {}

func recipe(id: String) -> Dictionary:
	# 转平面试验（docs/246）的干员只在 fx/px_plane 开着时有配方（读 data/fx_pxplane/）；其余干员只在 fx/recipe 开着时有
	# 推进之王（docs/264）原本有 docs/245 的配方：转平面关着时照旧走 fx/recipe 的配方（缓存键分开）
	var px: bool = Pxp.IDS.has(id) and Pxp.owns_id(g, id)
	if not px and Bal.v("fx/recipe", 0.0) <= 0.0:
		return _NONE
	var ck: String = ("px:" + id) if px else id
	if not recipes.has(ck):
		var d := {}
		var p: String = (PXP_DIR if px else DIR) + id + ".json"
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				d = v
				_prep(d)
		recipes[ck] = d
	return recipes[ck]


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
	# 附加色组（白碎芒、白热闪、灰尘、冷钢 …）：形状的 tone 字段指过来；缺的键沿用主色组
	var tones := {}
	var tsrc: Dictionary = d.get("tones", {})
	for tk in tsrc:
		var tp := {}
		for k in ["dark", "main", "hot", "accent", "light"]:
			tp[k] = _col(tsrc[tk][k]) if tsrc[tk].has(k) else out[k]
		tp["accent_on"] = out.accent_on
		tones[tk] = tp
	out["tones"] = tones
	d["_pal"] = out


## 三项实验开关（docs/245 §5.9，11-05 起缺省 1，都要 fx/recipe 开着才生效）：每帧读一次
func _exp() -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _x_frame:
		return
	_x_frame = fr
	var on: bool = enabled()
	_x_outline = on and Bal.v("fx/recipe_outline", 1.0) > 0.0
	_x_hitlight = on and Bal.v("fx/recipe_hitlight", 1.0) > 0.0
	_x_react = on and Bal.v("fx/recipe_hitreact", 1.0) > 0.0


## 这名干员的画面由配方接管吗（开关开 + 有配方）
static func owns(o) -> bool:
	if o == null or o.g == null:
		return false
	var r = of(o.g)
	return r != null and r.enabled() and not r.recipe(str(o.id)).is_empty()


static func owns_id(game, oid: String) -> bool:
	if game == null or oid == "":
		return false
	var r = of(game)
	return r != null and r.enabled() and not r.recipe(oid).is_empty()


# ================================================================ 配方读取

## 某一招在这名干员当前精英档下的参数：moves[name] 合并 e1（精一起）/ e2（精二起），sc = 档位体量；tier_min = 该招解锁时的精英档
func move(o, name: String) -> Dictionary:
	var rc: Dictionary = recipe(str(o.id))
	var base: Dictionary = rc.get("moves", {}).get(name, {})
	if base.is_empty():
		return {}
	# 技能按精英化解锁（character.skill_unlocked：S2 精一、S3 精二），配方里这些招式没有更低的档：tier_min 托底，不留死档
	var t: int = maxi(tier(o), int(base.get("tier_min", 0)))
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
	_exp()
	var pxm: int = Pxp.of(g).mode() if Pxp.IDS.has(str(o.id)) else 0
	if _x_react and pxm != 2:   # 转平面「旧做法」对照（2）不加受击反应
		var heavy: bool = kind in ["exec", "slam", "lock_tick", "fan_tick"] or (kind == "swing" and d.get("heavy", false))
		var col: Color = p.get("flash", p.light)
		var ft2: float = float(recipe(str(o.id)).get("flash_t", REACT_FLASH))   # 干员自己的闪色时长（docs/265 凯尔希：1–2 帧）
		if d.has("e") and d.e != null:
			_react(d.e, col, heavy, ft2)
		for e in d.get("es", []):
			_react(e, col, heavy, ft2)
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 三档并排图对齐用（tools/fx_canon_shots.py）：事件发生的引擎帧
		print("FXRLOG %s %s%s %d %.3f" % [str(o.id), kind, str(d.get("i", "")) if kind == "skill" else ("_h" if d.get("heavy", false) else ""), Engine.get_process_frames(), float(g.t)])   # 第 5 列 = 游戏时间（实局找事件时刻用，docs/255）
	if pxm > 0:
		Pxp.of(g).ev(o, kind, d)   # 转平面试验（docs/246）
		return
	match kind:
		"fire":
			# 逻各斯出手：笔尖四芒星芒（原作 attack 0.50 s「出手星芒」）；精一起加斜向四芒成八芒
			var m: Dictionary = move(o, "fire")
			if m.is_empty():
				return
			var at: Vector2 = d.get("at", o.pos)
			var dir: Vector2 = d.get("dir", Vector2.RIGHT)
			_shape(o, {"k": "flare", "c": at, "ang": 0.0, "r": float(m.get("len", 22.0)) * m.sc, "rv": float(m.get("len", 22.0)) * m.sc * float(m.get("rv_k", 0.7)),
				"w": float(m.get("w", 5.0)) * m.sc * m.thick, "n8": m.tier >= 1, "life": float(m.get("life", 0.12)), "freeze": float(m.get("freeze", 0.04)), "layer": "over",
				"grow": true, "tone": str(m.get("tone", ""))})
			if m.tier >= 1:
				_grains(o, at, at.y + 30.0, "twinkle", int(m.get("n", 2)), m, dir)
			# 起手笔光（原作 attack_start：身前挥出白弧 + 墨弧）→ 身周化成一圈字环
			_shape(o, {"k": "whirl", "c": o.pos + Vector2(0, -24), "ang": dir.angle(), "r": float(m.get("arc_r", 22.0)) * m.sc, "half": 1.1,
				"w": float(m.get("arc_w", 9.0)) * m.sc * m.thick, "strands": 2, "life": 0.16, "freeze": 0.03, "layer": "over", "tone": "shard",
				"sdir": -1.0 if dir.x * float(o.face) < 0.0 else 1.0})
			_shape(o, {"k": "glyphring", "c": o.pos + Vector2(0, -22), "r": float(m.get("ring_r", 24.0)) * m.sc, "n": int(m.get("ring_n", 9)) + 3 * m.tier,
				"life": float(m.get("ring_life", 0.36)), "freeze": 0.0, "layer": "over", "delay": 0.05, "follow": true, "accent": m.tier >= 2})
		"hit":
			_hit(o, d.get("at", o.pos), float(d.get("gy", 0.0)), str(d.get("move", "hit")), d.get("dir", Vector2.ZERO))
		"exec":
			_exec(o, d, p)
		"lock_tick", "fan_tick":
			_tick(o, kind, d, p)
		"skill":
			_cast(o, int(d.get("i", 0)), p)
		"swing":
			_swing(o, d)
		"quake":
			var m5: Dictionary = move(o, "quake")
			if m5.is_empty():
				return
			_shape(o, {"k": "ring", "c": d.at, "r0": 12.0, "r": float(d.get("r", 70.0)), "w": float(m5.get("w", 6.0)) * m5.thick * (1.3 if d.get("roar", false) else 1.0),
				"life": float(m5.get("life", 0.3)), "freeze": 0.0, "layer": "floor", "tone": "ash"})
		"crush":
			# 精一粉碎：击倒处一小块熔岩裂网 + 黑色三角碎块
			var m6: Dictionary = move(o, "crush")
			if m6.is_empty() or m6.tier < 1:   # 粉碎是精一玩法：强制低档画面（三档图）时不画
				return
			_shape(o, {"k": "web", "c": d.at, "r": float(m6.get("r", 18.0)) * m6.sc, "n": int(m6.get("branches", 5)), "w": float(m6.get("w", 5.0)) * m6.thick,
				"life": float(m6.get("life", 0.45)), "freeze": 0.04, "layer": "floor", "grow": true})
			_grains(o, d.at + Vector2(0, -8), (d.at as Vector2).y, str(m6.get("grain", "tri")), int(m6.get("n", 3)), m6)
		"breach":
			# 精二破阵：沿裂隙熔开一道分叉地裂（原作 S3 hit 的前向枝裂），沿线崩出黑色三角碎块
			var m7: Dictionary = move(o, "breach")
			if m7.is_empty() or m7.tier < 2:   # 破阵是精二玩法：强制低档画面（三档图）时不画
				return
			var pts2: PackedVector2Array = d.pts
			_shape(o, {"k": "crack", "pts": pts2, "w": float(m7.get("w", 9.0)) * m7.thick, "life": minf(float(d.get("life", 0.6)), float(m7.get("life", 0.45))), "freeze": 0.05, "layer": "floor", "grow": true,
				"forks": int(m7.get("forks", 5)), "tone": "crack"})
			var a0: Vector2 = pts2[0]
			var a1: Vector2 = pts2[pts2.size() - 1]
			for k2 in 3:
				var sp: Vector2 = a0.lerp(a1, 0.25 + 0.3 * k2)
				_grains(o, sp + Vector2(0, -6), sp.y, "tri", int(m7.get("n", 2)), m7)
			_light(o, a0.lerp(a1, 0.5), float(m7.get("light_r", 120.0)), float(m7.get("light_i", 0.55)), 0.15, p.light)
		"leap":
			# 跃空锤起跳：橙色三角碎片向锤身汇聚（原作 skill_02_start）+ 空中一圈银橙旋光；落点一圈灰色预示
			var m8: Dictionary = move(o, "leap")
			if m8.is_empty():
				return
			var tl: float = float(d.get("t", 0.42))
			_shape(o, {"k": "converge", "c": o.pos + Vector2(0, -30), "r": float(m8.get("conv_r", 70.0)) * m8.sc, "n": int(m8.get("conv_n", 9)) + (2 if m8.tier >= 2 else 0),
				"w": float(m8.get("conv_w", 6.0)) * m8.sc, "life": tl * 0.7, "freeze": 0.0, "layer": "over"})
			_shape(o, {"k": "whirl", "c": o.pos + Vector2(0, -36), "ang": -PI / 2.0, "r": float(m8.get("whirl_r", 30.0)) * m8.sc, "half": PI * 0.92,
				"w": float(m8.get("whirl_w", 9.0)) * m8.sc * m8.thick, "strands": 3 if m8.tier < 2 else 4, "life": tl, "delay": tl * 0.35, "freeze": 0.0, "layer": "over",
				"follow": true, "accent": m8.tier >= 2})
			_shape(o, {"k": "ring", "c": d.get("to", o.pos), "r0": float(m8.get("mark_r", 26.0)) * m8.sc, "r": float(m8.get("mark_r", 26.0)) * m8.sc, "w": 3.0,
				"life": tl + 0.05, "freeze": 0.0, "layer": "floor", "tone": "ash", "hold": true})
		"slam":
			_slam(o, d, p)
		"crash":
			var m10: Dictionary = move(o, "crash")
			if m10.is_empty():
				return
			_shape(o, {"k": "flare", "c": d.at, "ang": 0.0, "r": float(m10.get("r", 14.0)) * m10.sc, "rv": float(m10.get("r", 14.0)) * m10.sc * 0.8, "w": 5.0,
				"life": 0.14, "freeze": 0.04, "layer": "over", "tone": "flash"})


## 命中。逻各斯：白色不规则长碎芒 + 芯部四芒星芒 → 地面墨色椭圆环（原作 hit_01）；精一八芒 + 双环 + 回声；精二换咒文交叉（原作殁亡处决的符文链）+ 白热光团
func _hit(o, at: Vector2, gy: float, name: String, dir: Vector2) -> void:
	var m: Dictionary = move(o, name)
	if m.is_empty():
		return
	var p: Dictionary = pal(o)
	if gy == 0.0:
		gy = at.y + 12.0
	var R: float = float(m.get("r", 24.0)) * m.sc
	var a0: float = dir.angle() if dir != Vector2.ZERO else g.vrng.randf_range(-0.6, 0.6)
	var sh := {"k": "shards", "c": at, "r": R, "n": int(m.get("shards", 5)), "w": float(m.get("w", 5.0)) * m.sc * m.thick, "ang": a0,
		"life": float(m.get("life", 0.26)), "freeze": float(m.get("freeze", 0.05)), "layer": "over", "grow": true, "tone": str(m.get("shard_tone", "shard"))}
	_shape(o, sh)
	if m.tier >= 1:
		# 精一起：外圈再多一圈短碎刺（8 根，转半格），手机宽度下也看得出「多一圈」
		_shape(o, {"k": "shards", "c": at, "r": R * float(m.get("ring2_k", 1.45)), "n": 8, "w": float(m.get("w", 5.0)) * m.sc * 0.7, "ang": a0 + 0.39, "inner": 0.6,
			"life": float(m.get("life", 0.26)) * 0.85, "freeze": float(m.get("freeze", 0.05)), "layer": "over", "grow": true, "tone": str(m.get("shard_tone", "shard")), "delay": 0.03})
	if m.tier < 2:
		_shape(o, {"k": "flare", "c": at, "ang": 0.0, "r": R * 0.62, "rv": R * 0.62, "w": float(m.get("w", 5.0)) * m.sc, "n8": m.tier >= 1,
			"life": float(m.get("life", 0.26)) * 0.8, "freeze": float(m.get("freeze", 0.05)), "layer": "over", "grow": true})
		_shape(o, {"k": "ring", "c": Vector2(at.x, gy), "r0": R * 0.5, "r": R * float(m.get("ring_k", 1.4)), "w": float(m.get("ring_w", 3.0)) * m.thick,
			"life": float(m.get("ring_life", 0.5)), "freeze": 0.0, "layer": "floor", "delay": 0.04})
	else:
		_shape(o, {"k": "orb", "c": at, "r": R * 0.42, "life": 0.14, "freeze": 0.06, "layer": "over", "grow": true, "tone": "shard"})
		_shape(o, {"k": "runex", "c": at, "len": R * float(m.get("rune_k", 2.0)), "gs": float(m.get("gs", 2.0)), "spread": 0.5, "strips": 2,
			"life": float(m.get("rune_life", 0.42)), "freeze": 0.05, "layer": "over", "accent": true, "seed2": g.vrng.randi()})
	if float(m.beat) > 0.0 and bool(m.get("echo", true)):
		# 精一起「多一拍」：碎芒晚 beat 秒再炸一次（转 0.5 rad、大一圈、只剩中间色），读作双响
		var e2 := sh.duplicate()
		e2["delay"] = float(m.beat)
		e2["r"] = float(sh.r) * 1.2
		e2["life"] = float(sh.life) * 0.8
		e2["echo"] = true
		e2["ang"] = float(sh.ang) + 0.5
		_shape(o, e2)
	_grains(o, at, gy, str(m.get("grain", "ink")), int(m.get("n", 3)), m, dir)
	_hitlight(o, at, gy, R, float(m.get("light_r", 80.0)) * m.sc, float(m.get("light_i", 0.5)), float(m.get("light_life", 0.11)), p.light)


## 逻各斯殁亡处决（原作 S1 hit_03）：目标上竖起交叉的咒文链（X）+ 竖直墨柱；精一三道（米字），精二白热光团 + 双柱；溢出伤害飞一支墨迹彗星到下一名
func _exec(o, d: Dictionary, p: Dictionary) -> void:
	var m2: Dictionary = move(o, "exec")
	if m2.is_empty():
		return
	var e_at: Vector2 = d.get("at", o.pos)
	var gy: float = float(d.get("gy", e_at.y))
	var L: float = float(m2.get("len", 60.0)) * m2.sc
	_shape(o, {"k": "runex", "c": e_at + Vector2(0, -L * 0.15), "len": L, "gs": 2.0, "spread": 0.42,
		"strips": 3, "life": float(m2.get("life", 0.5)), "freeze": float(m2.get("freeze", 0.06)), "layer": "over", "accent": m2.tier >= 2,
		"seed2": g.vrng.randi(), "grow": true})
	var pw: float = float(m2.get("w", 12.0)) * m2.sc * m2.thick
	_shape(o, {"k": "beam", "a": Vector2(e_at.x, gy), "b": Vector2(e_at.x, gy - L * 1.15), "w": pw, "life": float(m2.get("life", 0.5)) * 0.8,
		"freeze": float(m2.get("freeze", 0.06)), "layer": "over", "grow": true})
	if m2.tier >= 2:
		for sg in [-1.0, 1.0]:
			_shape(o, {"k": "beam", "a": Vector2(e_at.x + sg * L * 0.32, gy + 2.0), "b": Vector2(e_at.x + sg * L * 0.32, gy - L * 0.8), "w": pw * 0.6,
				"life": float(m2.get("life", 0.5)) * 0.7, "freeze": 0.0, "layer": "over", "grow": true, "delay": 0.06})
		_shape(o, {"k": "orb", "c": e_at, "r": L * 0.22, "life": 0.14, "freeze": 0.06, "layer": "over", "grow": true, "tone": "shard"})
	if d.has("to"):
		_shape(o, {"k": "dart", "a": e_at, "b": d.to, "len": float(m2.get("dart_len", 22.0)) * m2.sc, "w": float(m2.get("dart_w", 8.0)) * m2.sc, "life": 0.2,
			"freeze": 0.0, "layer": "over"})
	_grains(o, Vector2(e_at.x, gy - 30.0), gy, str(m2.get("grain", "ink")), int(m2.get("n", 5)), m2)
	_hitlight(o, e_at, gy, L * 0.4, float(m2.get("light_r", 110.0)) * m2.sc, float(m2.get("light_i", 0.75)), float(m2.get("light_life", 0.14)), p.light)


## 每跳：提喻（lock_tick）= 目标处竖直长芒（原作提喻 hitloop）；精二换成高大的竖碎芒。咒域（fan_tick）= 区域内敌人紫白四芒星 + 白碎片；精二每跳先飞来一支大墨迹彗星（原作延异视阈每轮 4 发）
func _tick(o, kind: String, d: Dictionary, p: Dictionary) -> void:
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
		var R: float = float(m3.get("r", 16.0)) * m3.sc
		var dl: float = 0.0
		if kind == "fan_tick":
			dl = float(m3.get("dart_t", 0.12))
			var src: Vector2 = o.pos + Vector2(-o.face * 26.0 + 18.0 * (k - 1.5), -70.0 - 6.0 * k)
			_shape(o, {"k": "dart", "a": src, "b": qa, "len": float(m3.get("dart_len", 34.0)) * m3.sc, "w": float(m3.get("dart_w", 12.0)) * m3.sc, "life": dl / 0.6,
				"freeze": 0.0, "layer": "over", "delay": 0.03 * k})
		if kind == "lock_tick":
			if m3.tier >= 2:
				_shape(o, {"k": "shards", "c": qa, "r": R * 2.2, "n": 4, "w": float(m3.get("w", 5.0)) * m3.sc, "ang": -PI / 2.0, "vert": true,
					"life": float(m3.get("life", 0.22)), "freeze": float(m3.get("freeze", 0.04)), "layer": "over", "grow": true, "tone": "shard"})
			_shape(o, {"k": "flare", "c": qa, "ang": 0.0, "r": R * 0.55, "rv": R * (1.5 if m3.tier < 1 else 1.9), "w": float(m3.get("w", 5.0)) * m3.sc * m3.thick,
				"n8": m3.tier >= 1, "life": float(m3.get("life", 0.22)), "freeze": float(m3.get("freeze", 0.04)), "layer": "over", "grow": true, "tone": "shard"})
		else:
			_shape(o, {"k": "flare", "c": qa, "ang": 0.0, "r": R, "rv": R * 0.9, "w": float(m3.get("w", 5.0)) * m3.sc * m3.thick, "n8": true,
				"life": float(m3.get("life", 0.22)), "freeze": float(m3.get("freeze", 0.04)), "layer": "over", "grow": true, "delay": dl + 0.03 * k,
				"accent": true})
			_shape(o, {"k": "shards", "c": qa, "r": R * 1.1, "n": 5, "w": 4.0 * m3.sc, "ang": g.vrng.randf() * TAU, "life": float(m3.get("life", 0.22)) * 0.9,
				"freeze": 0.03, "layer": "over", "grow": true, "tone": "shard", "delay": dl + 0.03 * k})
		_grains(o, qa, qgy, str(m3.get("grain", "ink")), int(m3.get("n", 1)), m3)
		k += 1
	if not pts.is_empty():
		_hitlight(o, pts[0][0], float(pts[0][1]), float(m3.get("r", 16.0)) * m3.sc, float(m3.get("light_r", 70.0)) * m3.sc, float(m3.get("light_i", 0.4)), 0.1, p.light)


## 技能起手：每招一种原作意象（json 的 core）
##   flare 笔尖星芒 / whirl 环身挥笔刃光（逻各斯殁亡起手）/ orb 开域爆亮 / hammer 头顶锤徽（推进之王，原作 S3 buff 的锤 + 齿轮）/ band 横向镜头光带
func _cast(o, i: int, p: Dictionary) -> void:
	var m4: Dictionary = move(o, "cast%d" % (i + 1))
	if m4.is_empty():
		return
	var c: Vector2 = o.pos + Vector2(0, -float(m4.get("y", 26.0)))
	var life: float = float(m4.get("life", 0.32))
	var fz: float = float(m4.get("freeze", 0.06))
	for core in str(m4.get("core", "flare")).split("+"):
		match core:
			"flare":
				_shape(o, {"k": "flare", "c": c, "ang": 0.0, "r": float(m4.get("r", 26.0)) * m4.sc, "rv": float(m4.get("r", 26.0)) * m4.sc * 0.75,
					"w": float(m4.get("w", 6.0)) * m4.sc * m4.thick, "n8": m4.tier >= 1, "life": life, "freeze": fz, "layer": "over", "grow": true})
			"orb":
				_shape(o, {"k": "orb", "c": c + Vector2(o.face * 16.0, 0), "r": float(m4.get("orb_r", 14.0)) * m4.sc, "life": life * 0.6, "freeze": fz, "layer": "over",
					"grow": true, "tone": "shard"})
			"whirl":
				_shape(o, {"k": "whirl", "c": o.pos + Vector2(0, -22), "ang": PI if o.face < 0 else 0.0, "r": float(m4.get("whirl_r", 30.0)) * m4.sc, "half": PI * 0.85,
					"w": float(m4.get("whirl_w", 9.0)) * m4.sc * m4.thick, "strands": 2 + m4.tier, "life": life, "freeze": fz, "layer": "over", "grow": true,
					"tone": str(m4.get("whirl_tone", "")), "accent": m4.tier >= 2})
			"hammer":
				_shape(o, {"k": "hammer", "c": c, "r": float(m4.get("r", 26.0)) * m4.sc, "gear": m4.tier >= 1, "life": life, "freeze": fz, "layer": "over", "grow": true,
					"accent": m4.tier >= 2})
			"band":
				var bc: Vector2 = o.pos + Vector2(0, -float(m4.get("band_y", 24.0)))
				_shape(o, {"k": "flare", "c": bc, "ang": 0.0, "r": float(m4.get("band_r", 90.0)) * m4.sc, "rv": float(m4.get("band_rv", 8.0)) * (2.6 if m4.tier >= 2 else 1.0) * m4.sc,
					"w": float(m4.get("band_w", 5.0)) * m4.thick, "life": float(m4.get("band_life", 0.22)), "freeze": fz, "layer": "over", "grow": true, "tone": "flash"})
	if m4.has("ring"):
		_shape(o, {"k": "ring", "c": o.pos + Vector2(0, 4), "r0": 10.0, "r": float(m4.ring) * m4.sc, "w": float(m4.get("ring_w", 5.0)) * m4.thick,
			"life": float(m4.get("ring_life", 0.4)), "freeze": float(m4.get("ring_freeze", 0.0)), "layer": "floor", "tone": str(m4.get("ring_tone", ""))})
		if m4.tier >= 1 and m4.get("ring2", false):   # 精一：晚一拍再震一圈（形状差）
			_shape(o, {"k": "ring", "c": o.pos + Vector2(0, 4), "r0": 8.0, "r": float(m4.ring) * m4.sc * 0.62, "w": float(m4.get("ring_w", 5.0)) * m4.thick * 0.8,
				"life": float(m4.get("ring_life", 0.4)) * 0.8, "freeze": 0.0, "layer": "floor", "tone": str(m4.get("ring_tone", "")), "delay": 0.1, "accent": m4.tier >= 2})
	if m4.has("grain"):
		_grains(o, c, o.pos.y, str(m4.grain), int(m4.get("n", 6)), m4)
	_light(o, o.pos, float(m4.get("light_r", 120.0)) * m4.sc, float(m4.get("light_i", 0.7)), float(m4.get("light_life", 0.15)), p.light)


## 推进之王锤击：身前一道银橙旋光（原作 S2 / S3 的抡锤旋光，几股细弧）+ 落点白热闪（原作 attack hit）+ 放射状橙色火星线；
## 精一落点多一小块熔岩裂网（原作 S2 落地的裂网）+ 回声闪，精二旋光冷钢边 + 黑色三角碎块。
## 碎颅（heavy，原作 S3 hit）：横向扁白闪 + 向前分叉的地裂扇 + 暗烟；精一加暗烟坑圈，精二地裂冷钢边 + 三角碎块
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
	var sh := {"k": "whirl", "c": c, "ang": ang, "r": reach * float(m.get("r_k", 0.7)) * m.sc, "half": float(m.get("half", 1.0)), "w": float(m.get("w", 12.0)) * m.sc * m.thick,
		"strands": int(m.get("strands", 3)) + mini(m.tier, 1), "life": float(m.get("life", 0.18)), "freeze": float(m.get("freeze", 0.045)), "layer": "over",
		"sdir": 1.0 if sin(ang) >= 0.0 else -1.0, "accent": m.tier >= 2}
	_shape(o, sh)
	var fr: float = float(m.get("flash_r", 18.0)) * m.sc
	var fl := {"k": "flare", "c": land + Vector2(0, -6), "ang": 0.0, "r": fr * (2.2 if heavy else 1.0), "rv": fr * (0.45 if heavy else 0.85),
		"w": float(m.get("flash_w", 9.0)) * m.sc * m.thick, "life": float(m.get("flash_life", 0.14)), "freeze": float(m.get("freeze", 0.045)), "layer": "over",
		"grow": true, "tone": "flash", "n8": m.tier >= 2 and not heavy}
	_shape(o, fl)
	if float(m.beat) > 0.0:
		var e2 := fl.duplicate()
		e2["delay"] = float(m.beat)
		e2["r"] = float(fl.r) * 1.25
		e2["rv"] = float(fl.rv) * 1.25
		e2["life"] = float(fl.life) * 0.8
		e2["echo"] = true
		_shape(o, e2)
	if heavy:
		_shape(o, {"k": "cfan", "c": land + Vector2(0, 6), "ang": ang, "r": float(m.get("crack_r", 60.0)) * m.sc, "n": int(m.get("branches", 6)),
			"w": float(m.get("crack_w", 6.0)) * m.thick, "spread": 0.55, "life": float(m.get("crack_life", 0.7)), "freeze": float(m.get("freeze", 0.045)),
			"layer": "floor", "grow": true, "tone": "crack", "accent": true})
		_shape(o, {"k": "ring", "c": land + Vector2(0, 6), "r0": 10.0, "r": float(m.get("smoke_r", 34.0)) * m.sc, "w": float(m.get("smoke_w", 10.0)),
			"life": float(m.get("smoke_life", 0.5)), "freeze": 0.0, "layer": "floor", "tone": "ash"})
	elif m.tier >= 1:
		_shape(o, {"k": "web", "c": land + Vector2(0, 6), "r": float(m.get("web_r", 20.0)) * m.sc, "n": int(m.get("branches", 5)) + m.tier, "w": float(m.get("web_w", 5.0)) * m.thick,
			"life": float(m.get("web_life", 0.45)), "freeze": float(m.get("freeze", 0.045)), "layer": "floor", "grow": true, "accent": m.tier >= 2})
	_grains(o, land + Vector2(0, -6), land.y + 6.0, str(m.get("grain", "streak")), int(m.get("n", 5)), m, Vector2.from_angle(ang))
	if m.has("grain2"):
		_grains(o, land + Vector2(0, -6), land.y + 6.0, str(m.grain2), int(m.get("n2", 3)), m, Vector2.from_angle(ang))
	_hitlight(o, land, land.y + 6.0, fr, float(m.get("light_r", 100.0)) * m.sc, float(m.get("light_i", 0.6)), float(m.get("light_life", 0.12)), p.light)


## 跃空锤落地（原作 skill_02_attack）：地面炸开熔岩裂网（橙黄枝裂）+ 灰色尘环 + 黑色三角碎块；精一加竖直冲柱，精二裂网冷钢边、环外再裂出四道前向枝裂
func _slam(o, d: Dictionary, p: Dictionary) -> void:
	var m9: Dictionary = move(o, "slam")
	if m9.is_empty():
		return
	var r9: float = float(d.get("r", 110.0))
	var at9: Vector2 = d.get("at", o.pos)
	var fz: float = float(m9.get("freeze", 0.07))
	_shape(o, {"k": "web", "c": at9 + Vector2(0, 2), "r": r9 * float(m9.get("web_k", 0.6)) * m9.sc, "n": int(m9.get("branches", 9)),
		"w": float(m9.get("web_w", 8.0)) * m9.thick, "life": float(m9.get("life", 0.75)), "freeze": fz, "layer": "floor", "grow": true, "accent": m9.tier >= 2})
	_shape(o, {"k": "ring", "c": at9 + Vector2(0, 2), "r0": r9 * 0.3, "r": r9, "w": float(m9.get("ring_w", 12.0)) * m9.thick, "life": float(m9.get("ring_life", 0.4)),
		"freeze": 0.0, "layer": "floor", "tone": "ash"})
	_shape(o, {"k": "flare", "c": at9 + Vector2(0, -10), "ang": 0.0, "r": r9 * 0.3 * m9.sc, "rv": r9 * 0.22 * m9.sc, "w": 12.0 * m9.sc, "life": 0.16, "freeze": fz,
		"layer": "over", "grow": true, "tone": "flash"})
	_shape(o, {"k": "beam", "a": at9 + Vector2(0, 4), "b": at9 + Vector2(0, -float(m9.get("pillar", 120.0)) * m9.sc), "w": float(m9.get("pillar_w", 18.0)) * m9.sc,
		"life": float(m9.get("pillar_life", 0.2)), "freeze": fz, "layer": "over", "grow": true, "tone": "flash"})
	if m9.tier >= 2:
		for k in 4:
			var a: float = TAU * (k + 0.5) / 4.0 + g.vrng.randf_range(-0.3, 0.3)
			_shape(o, {"k": "cfan", "c": at9 + Vector2(cos(a), sin(a) * SY) * r9 * 0.55, "ang": a, "r": r9 * 0.6, "n": 3, "w": 6.0, "spread": 0.35,
				"life": float(m9.get("life", 0.75)) * 0.9, "freeze": fz, "layer": "floor", "grow": true, "tone": "crack", "accent": true, "delay": 0.05})
	_grains(o, at9 + Vector2(0, -10), at9.y, str(m9.get("grain", "tri")), int(m9.get("n", 8)), m9)
	if m9.has("grain2"):
		_grains(o, at9 + Vector2(0, -10), at9.y, str(m9.grain2), int(m9.get("n2", 4)), m9)
	_hitlight(o, at9, at9.y, r9 * 0.3 * m9.sc, float(m9.get("light_r", 150.0)) * m9.sc, float(m9.get("light_i", 0.85)), 0.15, p.light)


## 受击反应：被打中的敌人闪本人颜色（REACT_FLASH 秒，不白闪）；重击 / 技能命中再加 REACT_STOP 秒的局部打击停顿（只冻结这一只的选帧时间）
const REACT_FLASH := 0.06
const REACT_STOP := 2.0 / 60.0


func _react(e, col: Color, heavy: bool, ft2: float = REACT_FLASH) -> void:
	if not (e is Dictionary) or e.get("dead", false) or e.get("boss", false):
		return
	var id = e.get("id", -1)
	var prev: Array = reacts.get(id, [])
	var st: float = g.t + REACT_STOP if heavy else (float(prev[2]) if not prev.is_empty() else -1.0)
	var ft: float = float(prev[3]) if not prev.is_empty() and g.t < float(prev[2]) else g.t
	reacts[id] = [g.t, col, st, ft, ft2]   # ft2：闪色时长（配方 / 转平面 json 的 flash_t，缺省 REACT_FLASH）


## world.gd 选帧用：打击停顿期间返回命中那一刻的时间（只这一只的动画停），其余照常 g.t
static func react_t(game, e: Dictionary) -> float:
	if not game.has_meta("fx_recipe"):
		return game.t
	var r = game.get_meta("fx_recipe")
	r._exp()
	if not r._x_react or r.reacts.is_empty():
		return game.t
	var q: Array = r.reacts.get(e.id, [])
	if q.is_empty() or game.t >= float(q[2]):
		return game.t
	return float(q[3])


## world.gd 受击闪用：a < 0 = 不接管（照旧白闪）；a = 0 = 接管、这一帧不闪（白闪由本人色取代）；a > 0 = 闪这个颜色
## 配方 / 转平面的受击反应没接管时回落到近战打击感包（docs/246 §12）：闪本人色
static func react_col(game, e: Dictionary) -> Color:
	var c: Color = _react_col_r(game, e)
	if c.a < 0.0:
		return preload("res://scripts/render/melee_impact.gd").col(game, e)
	return c


static func _react_col_r(game, e: Dictionary) -> Color:
	if not game.has_meta("fx_recipe"):
		return Color(0, 0, 0, -1)
	var r = game.get_meta("fx_recipe")
	r._exp()
	if not r._x_react or r.reacts.is_empty():
		return Color(0, 0, 0, -1)
	var q: Array = r.reacts.get(e.id, [])
	if q.is_empty():
		return Color(0, 0, 0, -1)
	var age: float = game.t - float(q[0])
	if age < 0.0 or age > 0.3:
		return Color(0, 0, 0, -1)
	if age < (float(q[4]) if q.size() > 4 else REACT_FLASH):
		var c: Color = q[1]
		return Color(c.r, c.g, c.b, 0.85)
	return Color(0, 0, 0, 0)


## 命中照地（fx/recipe_hitlight，Noita 式「每次命中一盏有寿命的光」）：一盏 0.13 秒本人色点光（比常规命中光大、亮），
## 同时命中点脚下压暗一小圈（半径 1.5 倍星芒、压暗 15%、0.1 秒），衬出光。开关关时照旧挂常规命中光。
func _hitlight(o, at: Vector2, gy: float, R: float, r: float, inten: float, life: float, col: Color) -> void:
	_exp()
	if not _x_hitlight:
		_light(o, at, r, inten, life, col)
		return
	_light(o, at, r * float(Bal.v("fx/recipe_hitlight_r", 1.3)), minf(1.0, inten * float(Bal.v("fx/recipe_hitlight_i", 1.4))), clampf(life, 0.1, 0.15) if life >= 0.1 else 0.13, col)
	_shape(o, {"k": "shade", "c": Vector2(at.x, gy), "r": R * 1.5, "life": 0.1, "freeze": 0.0, "layer": "floor"})


func _shape(o, s: Dictionary) -> void:
	var id: String = str(o.id)
	if not shapes.has(id):
		shapes[id] = []
	var lst: Array = shapes[id]
	s["t0"] = g.t + float(s.get("delay", 0.0))
	s["seed"] = g.vrng.randi()
	if s.get("follow", false):
		s["op"] = o
		s["off"] = (s.c as Vector2) - o.pos
	lst.append(s)
	if lst.size() > SHAPE_MAX:
		lst.pop_front()


func _light(o, at: Vector2, r: float, inten: float, life: float, col: Color) -> void:
	lights.append([at, r, col, g.t, minf(LIGHT_LIFE_MAX, life), inten, str(o.id)])
	if lights.size() > 32:
		lights.pop_front()


# ================================================================ 装饰颗粒（Noita 式：少、大颗、有重量、落地、会弹）

## 材质：grav 重力（高度轴）、rest 弹性（0 = 不弹）、bounce 最多弹几次、land 落地后停留秒数、sz 颗粒边长（世界像素，2 的倍数）
## ink 墨滴（落地成墨点）/ drop 飞行滴墨 / twinkle 淡蓝小星（逻各斯，原作的金色小星改冷色，避开结晶暖金）/
## ember 火星 / streak 橙色火星线（推进之王，原作放射状细长火星）/ rock 碎石 / tri 黑色三角碎块（原作 S2 / S3 的黑三角）/ puff 暗烟团（上浮变大）/ shard 碎晶
const MATS := {
	"ink": {"grav": 820.0, "rest": 0.0, "bounce": 0, "land": 0.55, "sz": [4, 6], "spd": [50.0, 140.0], "up": [70.0, 170.0], "life": 0.9},
	"drop": {"grav": 700.0, "rest": 0.0, "bounce": 0, "land": 0.4, "sz": [2, 4], "spd": [4.0, 18.0], "up": [-10.0, 20.0], "life": 0.8},
	"twinkle": {"grav": 60.0, "rest": 0.0, "bounce": 0, "land": 0.0, "sz": [2, 2], "spd": [20.0, 60.0], "up": [20.0, 60.0], "life": 0.5},
	"ember": {"grav": 900.0, "rest": 0.38, "bounce": 1, "land": 0.3, "sz": [2, 4], "spd": [60.0, 170.0], "up": [80.0, 210.0], "life": 0.8},
	"streak": {"grav": 520.0, "rest": 0.3, "bounce": 1, "land": 0.2, "sz": [2, 4], "spd": [170.0, 320.0], "up": [60.0, 180.0], "life": 0.42},
	"rock": {"grav": 1100.0, "rest": 0.3, "bounce": 2, "land": 0.6, "sz": [4, 6], "spd": [50.0, 130.0], "up": [110.0, 230.0], "life": 1.0},
	"tri": {"grav": 1000.0, "rest": 0.3, "bounce": 1, "land": 0.5, "sz": [6, 10], "spd": [70.0, 170.0], "up": [140.0, 260.0], "life": 1.0},
	"puff": {"grav": -40.0, "rest": 0.0, "bounce": 0, "land": 0.0, "sz": [8, 12], "spd": [10.0, 40.0], "up": [10.0, 40.0], "life": 0.6},
	"shard": {"grav": 760.0, "rest": 0.45, "bounce": 1, "land": 0.35, "sz": [2, 4], "spd": [70.0, 160.0], "up": [90.0, 200.0], "life": 0.8},
	"rise": {"grav": -55.0, "rest": 0.0, "bounce": 0, "land": 0.0, "sz": [2, 2], "spd": [4.0, 16.0], "up": [18.0, 40.0], "life": 1.0},   # 慢慢上飘的光点（凯尔希治疗 / 熔毁火星，docs/265）
	"dust": {"grav": 420.0, "rest": 0.0, "bounce": 0, "land": 0.3, "sz": [2, 4], "spd": [40.0, 110.0], "up": [40.0, 100.0], "life": 0.75},   # 落地扬起的尘点（docs/265；docs/270 体检后加大到 2–4 px、寿命 0.75）
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
			"sz": sz, "nb": 0, "landed": -1.0, "rot": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14.0, 14.0),
			"accent": m.get("tier", 0) >= 2 and mat == "shard"})
		if m.has("c0"):   # 自带颜色（docs/265：颗粒池按干员一套色，凯尔希的治疗薄荷 / 熔毁红另给）
			parts[parts.size() - 1]["c0"] = m.c0
			parts[parts.size() - 1]["c1"] = m.get("c1", m.c0)


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
		q.rot = float(q.rot) + float(q.spin) * dt
		if float(q.h) <= 0.0:
			q.h = 0.0
			if int(q.nb) < int(mt.bounce) and absf(float(q.vh)) > 60.0:
				q.nb = int(q.nb) + 1
				q.vh = -float(q.vh) * float(mt.rest)
				q.v = q.v * 0.55
				q.spin = float(q.spin) * 0.5
			elif float(mt.land) > 0.0:
				q.landed = 0.0
		if float(q.age) < float(q.life) + float(mt.land):
			keep.append(q)
	parts = keep
	var now: float = g.t
	lights = lights.filter(func(L): return now - float(L[3]) < float(L[4]))
	for id in shapes:
		var lst: Array = shapes[id]
		shapes[id] = lst.filter(func(s): return now - float(s.t0) < float(s.life) + 0.02)
	if not reacts.is_empty():
		for id in reacts.keys():
			if now - float(reacts[id][0]) > 0.3:
				reacts.erase(id)


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
	n = mini(n, _share(game, nmax, n))
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


## 我方照地份额（late-read-b2 的 V4 render/light_share 合入后生效）：light_share.gd 若提供 static func recipe_share(game, nmax) -> int，
## 配方灯盏数取它与 fx/recipe_dl 的较小值；没有这个脚本 / 方法时原样返回（docs/245 §5.9）
static func _share(game, nmax: int, n: int) -> int:
	if not ResourceLoader.exists("res://scripts/render/light_share.gd"):
		return n
	var LS = load("res://scripts/render/light_share.gd")
	if LS == null or not LS.has_method("recipe_share"):
		return n
	return int(LS.recipe_share(game, nmax))


# ================================================================ 绘制

## 地面层（data_operator.draw_entities_floor 接管时调；敌人之下）：熔岩裂网、地裂、尘环、墨环、咒域、号令波、铭文
func draw_floor(o) -> void:
	_step()
	if o.pos == Vector2.INF:
		return
	if Pxp.owns_id(g, str(o.id)):
		Pxp.of(g).draw_floor(o)   # 转平面试验（docs/246）：贴地层
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
	if o.pos == Vector2.INF or Pxp.owns_id(g, str(o.id)):
		return
	var cv = o.cv
	var keep_mod := _core_mod(cv)
	if o.hw.has("fan"):
		_draw_fan(o, cv, pal(o))
	if o.hw.has("s3_shots"):   # 原画法在绘制时清理出手轨迹；接管后由这里清，免得列表只增不减
		var now: float = g.t
		o.hw["s3_shots"] = o.hw.s3_shots.filter(func(sh): return now - float(sh.t0) < 0.3)
	_restore_mod(cv, keep_mod)


## 上层（_draw_skill_over 接管时调）：羽笔「言」、咒文连线、主形、颗粒
func draw_over(o) -> void:
	_step()
	var cv = o.cv
	var p: Dictionary = pal(o)
	if Pxp.owns_id(g, str(o.id)):   # 转平面试验（docs/246）：旧做法整张贴在这里；转平面版只有 Noita 水滴颗粒在这层
		Pxp.of(g).draw_over(o)
		_draw_parts(o, cv, p)
		return
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


## 形状用的色组：tone 指向配方 tones 里的一组（白碎芒、白热闪、灰尘、冷钢 …），缺省用本人主色组
static func _tp(p: Dictionary, s: Dictionary) -> Dictionary:
	var t: String = str(s.get("tone", ""))
	if t == "":
		return p
	return p.get("tones", {}).get(t, p)


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


## 画面用的确定性散列（形状的不规则度按种子定，不抽随机数）：0..1
static func _h(sd: int, i: int) -> float:
	var x: int = (sd ^ (i * 0x9E3779B1)) & 0x7fffffff
	x = (x * 1103515245 + 12345) & 0x7fffffff
	x = x ^ (x >> 13)
	x = (x * 1103515245 + 12345) & 0x7fffffff
	return float((x >> 8) & 0xffff) / 65535.0


func _draw_shape(cv, s: Dictionary, p: Dictionary) -> void:
	var age: float = g.t - float(s.t0)
	if age < 0.0:
		return
	if s.get("follow", false) and s.get("op", null) != null:
		s["c"] = s.op.pos + (s.off as Vector2)
	var pp: Dictionary = _tp(p, s)
	var life: float = float(s.life)
	var tn: Array = _tones(pp, age, life, float(s.get("freeze", 0.0)), s.get("accent", false))
	if s.get("echo", false):
		tn = [tn[0], tn[1], Color(0, 0, 0, 0), float(tn[3]) * 0.9]
	var u: float = clampf(age / maxf(0.001, life), 0.0, 1.0)
	s["_u"] = u
	# 体量：grow 的主形前 18% 从 0.55 弹到 1.08 再落回 1（起手拉伸 / 冲出），最后 30% 收缩
	var gk: float = 1.0
	if s.get("grow", false):
		gk = lerpf(0.55, 1.08, clampf(u / 0.18, 0.0, 1.0)) if u < 0.18 else lerpf(1.08, 1.0, clampf((u - 0.18) / 0.15, 0.0, 1.0))
	if u > 0.7 and not s.get("hold", false):
		gk *= 1.0 - 0.45 * (u - 0.7) / 0.3
	match str(s.k):
		"ring":
			_draw_ring(cv, s, tn, u)
			return
		"crack":
			_draw_crack(cv, s, tn, u)
			return
		"whirl":
			_draw_whirl(cv, s, tn, u, p)
			return
		"runex":
			_draw_runex(cv, s, tn, u, gk, p)
			return
		"glyphring":
			_draw_glyphring(cv, s, tn, u, p)
			return
		"shade":   # 命中照地的压暗圈（地面，扁椭圆，α 0.15 → 0）
			cv.draw_set_transform(_snap(s.c), 0.0, Vector2(1.0, SY))
			cv.draw_circle(Vector2.ZERO, float(s.r), Color(0, 0, 0, 0.15 * (1.0 - u)))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
	_exp()
	if _x_outline and str(s.k) in OUTLINE_KINDS:
		var oc: Color = _outline_col(p)
		oc.a *= float(tn[3])
		for poly in _geo(s, gk, 1.0):
			if poly.size() >= 3:
				for op in Geometry2D.offset_polygon(poly, 2.0, Geometry2D.JOIN_MITER):
					cv.draw_colored_polygon(op, oc)
	var layers: Array = [[1.0, tn[0]], [0.72, tn[1]], [0.36, tn[2]]]
	for L in layers:
		var col: Color = L[1]
		if col.a <= 0.0:
			continue
		col.a *= float(tn[3])
		for poly in _geo(s, gk, float(L[0])):
			if poly.size() >= 3:
				cv.draw_colored_polygon(poly, col)


## 描边（fx/recipe_outline，Hades 式线稿）：只给小物件主形（弹体、刃、星芒、碎刺、光柱、三角汇聚），大面积场域、地面裂网与文字不加
const OUTLINE_KINDS := ["flare", "shards", "orb", "dart", "spike", "tear", "converge", "crescent", "beam", "spear3", "star"]


static func _outline_col(p: Dictionary) -> Color:
	var m: Color = p.main
	return Color(m.r * 0.3, m.g * 0.3, m.b * 0.3, 1.0)


## 四芒星芒（原作逻各斯出手 / 命中 / 咒域四角的星芒；推进之王的白热闪与镜头光带也是这个形，臂长不等）
static func _star4(c: Vector2, dv: Vector2, nv: Vector2, r: float, rv: float, w: float) -> PackedVector2Array:
	var q: float = w * 0.7
	return PackedVector2Array([_snap(c + dv * r), _snap(c + (dv + nv) * q), _snap(c + nv * rv), _snap(c + (nv - dv) * q),
		_snap(c - dv * r), _snap(c - (dv + nv) * q), _snap(c - nv * rv), _snap(c + (dv - nv) * q)])


## 一段渐细的实心带（裂纹枝、碎芒）
static func _seg(a: Vector2, b: Vector2, wa: float, wb: float) -> PackedVector2Array:
	var nv: Vector2 = (b - a).normalized().orthogonal()
	return PackedVector2Array([_snap(a + nv * wa * 0.5), _snap(b + nv * wb * 0.5), _snap(b - nv * wb * 0.5), _snap(a - nv * wa * 0.5)])


## 墨迹彗星（逻各斯「言」，原作 trail 的羽笔形：尖头、前宽、长身收尾）；fork = 燕尾（精一的形状差）
static func _quill(c: Vector2, dv: Vector2, L: float, W: float, fork: bool) -> PackedVector2Array:
	var nv: Vector2 = dv.orthogonal()
	var pts := PackedVector2Array([_snap(c + dv * L * 0.5), _snap(c + dv * L * 0.22 + nv * W * 0.5), _snap(c - dv * L * 0.12 + nv * W * 0.36)])
	if fork:
		pts.append_array([_snap(c - dv * L * 0.6 + nv * W * 0.42), _snap(c - dv * L * 0.34), _snap(c - dv * L * 0.6 - nv * W * 0.42)])
	else:
		pts.append_array([_snap(c - dv * L * 0.5 + nv * W * 0.1), _snap(c - dv * L * 0.5 - nv * W * 0.1)])
	pts.append_array([_snap(c - dv * L * 0.12 - nv * W * 0.36), _snap(c + dv * L * 0.22 - nv * W * 0.5)])
	return pts


## 形状库：返回若干多边形（世界坐标、对齐 2 px 格）；k = 粗细层（1 外暗边 / 0.72 主体 / 0.36 热芯），gk = 体量
func _geo(s: Dictionary, gk: float, k: float) -> Array:
	var c: Vector2 = s.get("c", Vector2.ZERO)
	match str(s.k):
		"flare":
			var r: float = float(s.r) * gk * (0.5 + 0.5 * k)
			var rv: float = float(s.rv) * gk * (0.5 + 0.5 * k)
			var w: float = maxf(1.5, float(s.w) * k)
			var dv := Vector2.from_angle(float(s.get("ang", 0.0)))
			var out: Array = [_star4(c, dv, dv.orthogonal(), r, rv, w)]
			if s.get("n8", false):
				var d2: Vector2 = dv.rotated(PI / 4.0)
				out.append(_star4(c, d2, d2.orthogonal(), maxf(r, rv) * 0.55, maxf(r, rv) * 0.55, w * 0.8))
			return out
		"shards":   # 不规则长碎芒：一根特别长，其余长短不一（原作逻各斯 hit 的白色碎芒 / 提喻后段的竖长芒）
			var R: float = float(s.r) * gk
			var n: int = maxi(2, int(s.get("n", 5)))
			var sd: int = int(s.seed)
			var out2: Array = []
			for i in n:
				var a: float
				if s.get("vert", false):
					a = (-PI / 2.0 if i % 2 == 0 else PI / 2.0) + (_h(sd, i) - 0.5) * 0.5
				else:
					a = float(s.ang) + TAU * i / n + (_h(sd, i) - 0.5) * 1.1
				var L: float = R * (0.5 + 0.5 * _h(sd, i + 17)) * (1.35 if i == 0 else 1.0) * (0.6 if s.get("vert", false) and i % 2 == 1 else 1.0)
				L *= 0.65 + 0.35 * k
				var bw: float = maxf(1.5, float(s.w) * (0.6 + 0.4 * _h(sd, i + 31)) * k)
				var dv2 := Vector2.from_angle(a)
				var nv2: Vector2 = dv2.orthogonal()
				var c2: Vector2 = c + dv2 * R * float(s.get("inner", 0.0))
				if s.has("inner"):
					a = float(s.ang) + TAU * i / n
					dv2 = Vector2.from_angle(a)
					nv2 = dv2.orthogonal()
					c2 = c + dv2 * R * float(s.inner)
					L = R * (1.0 - float(s.inner)) * (0.7 + 0.3 * _h(sd, i + 17)) * (0.65 + 0.35 * k)
				out2.append(PackedVector2Array([_snap(c2 - dv2 * bw * 0.6), _snap(c2 + nv2 * bw * 0.5), _snap(c2 + dv2 * L), _snap(c2 - nv2 * bw * 0.5)]))
			return out2
		"orb":   # 白热星核（11-05：不准用圆形光团显眼）：八芒尖星，内角收到 0.22，长短芒交替
			var r3: float = float(s.r) * gk * (0.55 + 0.45 * k)
			var pts3 := PackedVector2Array()
			for i in 16:
				var a3: float = TAU * i / 16.0 - PI / 2.0
				var rr3: float = r3 * (0.22 if i % 2 == 1 else (1.0 if (i / 2) % 2 == 0 else 0.6))
				pts3.append(_snap(c + Vector2(cos(a3), sin(a3)) * rr3))
			return [pts3]
		"web":
			return _web(s, gk, k, true)
		"cfan":
			return _web(s, gk, k, false)
		"converge":   # 三角碎片向中心汇聚（原作推进之王 S2 起手）
			var u: float = float(s.get("_u", 0.0))
			var sd4: int = int(s.seed)
			var out4: Array = []
			var w4: float = float(s.w) * (0.6 + 0.4 * k) + (2.0 if k >= 1.0 else 0.0)
			for i in int(s.n):
				var a4: float = TAU * (i + _h(sd4, i) * 0.6) / float(s.n)
				var rr: float = float(s.r) * (1.0 - u) * (0.7 + 0.3 * _h(sd4, i + 5)) + float(s.r) * 0.08
				var q: Vector2 = c + Vector2(cos(a4), sin(a4) * 0.8) * rr
				var dv4: Vector2 = (c - q).normalized()
				var nv4: Vector2 = dv4.orthogonal()
				out4.append(PackedVector2Array([_snap(q + dv4 * w4 * 1.3), _snap(q - dv4 * w4 * 0.6 + nv4 * w4 * 0.7), _snap(q - dv4 * w4 * 0.6 - nv4 * w4 * 0.7)]))
			return out4
		"dart":   # 飞行中的墨迹彗星：前 60% 寿命从 a 飞到 b，之后不画（命中交给星芒）
			var u5: float = float(s.get("_u", 0.0))
			if u5 > 0.62:
				return []
			var a5: Vector2 = s.a
			var b5: Vector2 = s.b
			var dv5: Vector2 = (b5 - a5).normalized()
			var at5: Vector2 = a5.lerp(b5, clampf(u5 / 0.6, 0.0, 1.0))
			return [_quill(at5, dv5, float(s.len) * (0.75 + 0.25 * k), float(s.w) * k, false)]
		"hammer":
			return _hammer(s, gk, k)
		"beam":   # 光束 / 竖柱：两端收尖的实心带
			var a: Vector2 = s.a
			var b: Vector2 = s.b
			if s.get("grow", false):
				b = a.lerp(b, minf(1.0, gk))
			var w3: float = float(s.w) * k
			var dv3: Vector2 = (b - a).normalized()
			var nv3: Vector2 = dv3.orthogonal() * w3 * 0.5
			var L3: float = a.distance_to(b)
			var e: float = minf(L3 * 0.2, 10.0)
			return [PackedVector2Array([_snap(a), _snap(a + dv3 * e + nv3), _snap(b - dv3 * e + nv3), _snap(b), _snap(b - dv3 * e - nv3), _snap(a + dv3 * e - nv3)])]
		"crescent":   # 弧刃（旋光的一股）
			return [_arc_band(c, float(s.r) * gk, float(s.ang) - float(s.half), float(s.ang) + float(s.half), float(s.w) * k, 0.0, 1.0)]
	return []


## 熔岩裂网（web：从中心向四周分叉，原作推进之王 S2 落地）/ 前向枝裂扇（cfan：沿 ang 张开，原作 S3 hit）；贴地压扁 SY
func _web(s: Dictionary, gk: float, k: float, full: bool) -> Array:
	var c: Vector2 = s.c
	var R: float = float(s.r) * gk
	var n: int = maxi(2, int(s.get("n", 6)))
	var w0: float = float(s.get("w", 6.0))
	var sd: int = int(s.seed)
	var out: Array = []
	for i in n:
		var a: float
		if full:
			a = TAU * (i + _h(sd, i) * 0.6) / n
		else:
			var sp: float = float(s.get("spread", 0.5))
			a = float(s.ang) + sp * ((i + 0.5) / n * 2.0 - 1.0) + (_h(sd, i) - 0.5) * 0.25
		var L: float = R * (0.55 + 0.45 * _h(sd, i + 7))
		var cur: Vector2 = c + Vector2(cos(a), sin(a) * SY) * (R * 0.08 if full else 0.0)
		var ca: float = a
		for j in 3:
			ca += (_h(sd, i * 7 + j + 50) - 0.5) * 0.7
			var nxt: Vector2 = cur + Vector2(cos(ca), sin(ca) * SY) * L / 3.0
			var wa: float = maxf(1.5, w0 * (1.0 - 0.25 * j) * k)
			var wb: float = maxf(1.5, w0 * (1.0 - 0.25 * (j + 1)) * k)
			out.append(_seg(cur, nxt, wa, wb))
			if j < 2:
				var fa: float = ca + (0.75 if _h(sd, i * 5 + j + 90) > 0.5 else -0.75)
				var fe: Vector2 = nxt + Vector2(cos(fa), sin(fa) * SY) * L * (0.32 - 0.1 * j)
				out.append(_seg(nxt, fe, wb * 0.8, 1.5))
			cur = nxt
	if full:
		var cb := PackedVector2Array()
		var rb: float = w0 * 1.7 * k + 2.0
		for i in 8:
			var a2: float = TAU * (i + 0.5) / 8.0
			cb.append(_snap(c + Vector2(cos(a2), sin(a2) * SY) * rb * (0.8 + 0.4 * _h(sd, i + 70))))
		out.append(cb)
	return out


## 锤徽（推进之王 S1 号令；原作 S3 buff 的锤 + 齿轮）：像素位图，k = 1 外暗边（每格外扩半格）/ 0.72 主体 / 0.36 高光；gear = 精一起手柄上的半圈齿轮
const HAMMER := ["..######.", "#########", "..######.", "...###...", "....#....", "....#....", "....#....", "....#....", "....#....", "...###...", "....#...."]
const GEAR := [Vector2i(2, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(2, 9), Vector2i(0, 6), Vector2i(0, 8), Vector2i(3, 5), Vector2i(3, 9)]


func _hammer(s: Dictionary, gk: float, k: float) -> Array:
	var cs: float = maxf(2.0, round(float(s.r) * gk / 5.5 / 2.0) * 2.0)
	var o: Vector2 = _snap(s.c - Vector2(4.5, 5.5) * cs)
	var cells: Array = []
	for y in HAMMER.size():
		for x in 9:
			if HAMMER[y][x] == "#":
				cells.append(Vector2i(x, y))
	if s.get("gear", false):
		cells.append_array(GEAR)
	var out: Array = []
	for cl in cells:
		var p0: Vector2 = o + Vector2(cl.x, cl.y) * cs
		var e: float
		if k >= 1.0:
			e = cs * 0.5
		elif k >= 0.7:
			e = 0.0
		else:
			if not (cl.y == 1 or (cl.x == 4 and cl.y >= 3 and cl.y <= 8)):
				continue
			e = -cs * 0.25
		out.append(PackedVector2Array([p0 + Vector2(-e, -e), p0 + Vector2(cs + e, -e), p0 + Vector2(cs + e, cs + e), p0 + Vector2(-e, cs + e)]))
	return out


## 弧带：圆心 c、半径 R、角度 a0 → a1，厚 th；t0..t1 = 只画这段（挥动扫过）；头厚尾尖（y × 0.8 贴地透视）
static func _arc_band(c: Vector2, R: float, a0: float, a1: float, th: float, t0: float, t1: float) -> PackedVector2Array:
	var N := 14
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in N + 1:
		var t: float = lerpf(t0, t1, float(i) / N)
		var a: float = lerpf(a0, a1, t)
		var f: float = float(i) / N
		var prof: float = pow(f, 0.7) * (1.0 - 0.35 * pow(f, 6.0))
		var ro: float = R + th * 0.5 * prof
		var ri: float = R - th * 0.5 * prof
		outer.append(_snap(c + Vector2(cos(a) * ro, sin(a) * ro * 0.8)))
		inner.append(_snap(c + Vector2(cos(a) * ri, sin(a) * ri * 0.8)))
	inner.reverse()
	outer.append_array(inner)
	return outer


## 旋光（推进之王抡锤 / 逻各斯殁亡起手的挥笔刃光）：几股同心细弧沿挥动方向扫过，头厚尾尖；第一股本人主色带热芯，其余银色（tones.steel / 本色组）
func _draw_whirl(cv, s: Dictionary, tn: Array, u: float, p: Dictionary) -> void:
	if u > 0.8:
		return   # 旋光不留暗色余韵（大块暗弧会脏）
	var n: int = maxi(1, int(s.get("strands", 3)))
	var sd: float = float(s.get("sdir", 1.0))
	var half: float = float(s.half)
	var a0: float = float(s.ang) - half * sd
	var a1: float = float(s.ang) + half * sd
	var head: float = clampf(u / 0.35, 0.0, 1.0)
	var t0: float = maxf(0.0, head - 1.0)
	var al: float = float(tn[3])
	var silver: Color = p.get("tones", {}).get("steel", {}).get("main", tn[1])
	var gk: float = 1.0 if u < 0.7 else 1.0 - 0.3 * (u - 0.7) / 0.3
	for i in n:
		var R: float = float(s.r) * gk * (1.0 - 0.11 * i)
		var hh: float = 1.0 - 0.12 * i
		var th: float = maxf(2.0, float(s.w) * (0.62 - 0.12 * i) * (1.6 if i == 0 else 1.0))
		var aa: float = lerpf(float(s.ang), a0, hh)
		var bb: float = lerpf(float(s.ang), a1, hh)
		var mc: Color = tn[1] if i == 0 else (silver if str(s.get("tone", "")) == "" else tn[1])
		var dk: Color = tn[0]
		if _x_outline:
			var oc: Color = _outline_col(p)
			cv.draw_colored_polygon(_arc_band(s.c, R, aa, bb, th + 8.0, t0, head * (1.0 - 0.06 * i)), Color(oc.r, oc.g, oc.b, al))
		cv.draw_colored_polygon(_arc_band(s.c, R, aa, bb, th + 4.0, t0, head * (1.0 - 0.06 * i)), Color(dk.r, dk.g, dk.b, dk.a * al))
		cv.draw_colored_polygon(_arc_band(s.c, R, aa, bb, th, t0, head * (1.0 - 0.06 * i)), Color(mc.r, mc.g, mc.b, mc.a * al))
		if i == 0 and (tn[2] as Color).a > 0.0:
			var hc: Color = tn[2]
			cv.draw_colored_polygon(_arc_band(s.c, R, aa, bb, maxf(2.0, th * 0.38), t0, head), Color(hc.r, hc.g, hc.b, hc.a * al))


# ---------------------------------------------------------------- 咒文（原作逻各斯提喻的连线字块、殁亡处决的符文链；本作 3×4 像素字形）

const GLYPHS := [
	["###", "..#", ".##", "..#", "..#"], [".#.", "###", ".#.", ".#.", ".#."], ["#.#", "#.#", ".#.", "#.#", "#.#"], ["###", ".#.", ".#.", ".#.", "###"],
	[".#.", "...", "...", "#.#", "..."], ["##.", "..#", "..#", "..#", "##."], ["#..", "#..", "###", "#.#", "#.#"], ["#.#", "#.#", "###", "..#", "..#"],
	[".#.", "#.#", "#.#", "#.#", "#.#"], ["#..", "##.", "#.#", "#..", "#.."], ["###", "#.#", "#.#", "#.#", "#.#"], ["...", ".#.", "...", ".#.", "..."],
]
static var _gcells: Array = []


static func _glyph_cells() -> Array:
	if _gcells.is_empty():
		for gl in GLYPHS:
			var cl: Array = []
			for y in gl.size():
				for x in 3:
					if gl[y][x] == "#":
						cl.append(Vector2(x, y))
			_gcells.append(cl)
	return _gcells


## 一条咒文（11-05 用户：白字不准加粗）：从 a 沿 dv 排 L 长；字是 3×5 细笔画、1 美术像素（2 px）宽、字距 2 格、直立不旋转、不画底色块；
## 字形按 sd 散列选；scroll = 沿线流动（像素 / 秒）；reveal 0..1 = 从起点写出的比例；rows = 1 或 2（2 = 中线两侧各一行、前后错开半字，精一的形状差）；
## fg / fg2 字色交替（精二用更亮的白 + 点缀紫，不加粗）。bg 参数保留不用。
func _glyph_strip(cv, a: Vector2, dv: Vector2, L: float, _cs: float, sd: int, _bg: Color, fg: Color, fg2: Color, reveal: float, rows: int, scroll := 0.0) -> void:
	var cs := 2.0
	var nv: Vector2 = dv.orthogonal()
	if nv.y > 0.0:
		nv = -nv
	var adv: float = cs * 5.0
	var Lr: float = L * clampf(reveal, 0.0, 1.0)
	if Lr < adv:
		return
	var cells: Array = _glyph_cells()
	var sh: float = fmod(g.t * scroll, adv) if scroll != 0.0 else 0.0
	var base_i: int = int(floor(g.t * scroll / adv)) if scroll != 0.0 else 0
	var n: int = int(Lr / adv) + 1
	for r in rows:
		var off: float = (5.0 if rows == 1 else (11.0 if r == 0 else -1.0)) * cs * 0.5
		var stag: float = 0.0 if r == 0 else adv * 0.5
		for i in n + 1:
			var x0: float = i * adv + sh - adv + stag
			if x0 < 0.0 or x0 + cs * 3.0 > Lr:
				continue
			var gi: int = int(_h(sd + r * 977, i - base_i) * GLYPHS.size()) % GLYPHS.size()
			var col: Color = fg if (i - base_i + r) % 3 != 0 else fg2
			var q0: Vector2 = _snap(a + dv * (x0 + cs * 1.5) + nv * off - Vector2(cs * 1.5, cs * 2.5))
			for cl in cells[gi]:
				cv.draw_rect(Rect2(q0 + Vector2(cl.x, cl.y) * cs, Vector2(cs, cs)), col)


## 咒文交叉（殁亡处决 / 精二命中）：2–3 条咒文从中心交叉，前 25% 寿命写出
func _draw_runex(cv, s: Dictionary, tn: Array, u: float, gk: float, p: Dictionary) -> void:
	var L: float = float(s.len) * gk
	var cs := 2.0
	var al: float = float(tn[3])
	var bg: Color = tn[0]
	bg.a *= 0.85 * al
	var fg: Color = (tn[2] if (tn[2] as Color).a > 0.0 else tn[1])
	fg.a *= al
	var fg2: Color = (p.accent if s.get("accent", false) else tn[1])
	fg2.a *= al
	var st: int = int(s.get("strips", 2))
	var sp: float = float(s.get("spread", 0.45))
	var angs: Array = [-PI / 2.0 - sp, -PI / 2.0 + sp, -PI / 2.0]
	var c: Vector2 = s.c
	for j in st:
		var dv := Vector2.from_angle(float(angs[j]))
		_glyph_strip(cv, c - dv * L * 0.5, dv, L, cs, int(s.get("seed2", s.seed)) + j * 131, bg, fg, fg2, u / 0.25, 1)


## 字环（逻各斯起手：笔光化成的一圈咒文，原作 attack 0.26–0.34 s）：身周扁椭圆上一圈直立小字，缓转，前 30% 寿命逐字亮起
func _draw_glyphring(cv, s: Dictionary, tn: Array, u: float, p: Dictionary) -> void:
	var n: int = maxi(4, int(s.get("n", 9)))
	var r: float = float(s.r) * (0.8 + 0.2 * minf(1.0, u / 0.3))
	var al: float = float(tn[3])
	var cells: Array = _glyph_cells()
	var rot: float = g.t * 2.2
	var c: Vector2 = s.c
	var sd: int = int(s.seed)
	for i in n:
		if float(i) / n > u / 0.3:
			break
		var a: float = rot + TAU * i / n
		var q: Vector2 = _snap(c + Vector2(cos(a) * r, sin(a) * r * 0.42) - Vector2(3, 5))
		var front: bool = sin(a) > 0.0
		var col: Color = (p.hot if front else p.light) if not (s.get("accent", false) and i % 3 == 0) else p.accent
		col.a *= al * (1.0 if front else 0.7)
		for cl in cells[int(_h(sd, i) * GLYPHS.size()) % GLYPHS.size()]:
			cv.draw_rect(Rect2(q + Vector2(cl.x, cl.y) * 2.0, Vector2(2, 2)), col)


## 冲击环 / 墨环 / 尘环 / 号令波（地面）：一条实心厚带从 r0 扩到 r（缓出），三阶：外暗边 → 主色 → 热芯细线
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


## 地裂（精二破阵）：前 0.08 秒向前裂开，暗边 + 熔芯 + 白热细芯；forks = 沿线分出的细枝（原作 S3 的枝裂）
func _draw_crack(cv, s: Dictionary, tn: Array, u: float) -> void:
	var pts: PackedVector2Array = s.pts
	var age: float = g.t - float(s.t0)
	var grow: float = clampf(age / 0.08, 0.0, 1.0)
	var m: int = maxi(2, int(ceil(pts.size() * grow)))
	var sub: PackedVector2Array = pts.slice(0, m)
	var w: float = float(s.w) * (1.0 - 0.5 * u)
	var al: float = float(tn[3])
	var br: Array = []
	var nf: int = int(s.get("forks", 0))
	var sd: int = int(s.seed)
	for i in nf:
		var j: int = 1 + int(_h(sd, i) * maxf(1.0, m - 2))
		if j >= m - 1:
			continue
		var d: Vector2 = (pts[j + 1] - pts[j]).normalized()
		var fa: float = d.angle() + (0.8 if _h(sd, i + 40) > 0.5 else -0.8)
		var fe: Vector2 = pts[j] + Vector2(cos(fa), sin(fa) * SY) * (12.0 + 16.0 * _h(sd, i + 80))
		br.append(PackedVector2Array([pts[j], fe]))
	for Ly in [[tn[0], w + 4.0, 4.0], [tn[1], w, 2.0], [tn[2], maxf(2.0, w * 0.3), 0.0]]:
		var col: Color = Ly[0]
		if col.a <= 0.0:
			continue
		col.a *= al
		cv.draw_polyline(sub, col, float(Ly[1]))
		for b in br:
			cv.draw_polyline(b, col, maxf(2.0, float(Ly[1]) * 0.45 + float(Ly[2]) * 0.5))


## 颗粒：硬边方块 / 三角 / 火星线 / 小星，按年龄硬切色阶；落地后变暗、扁成 2 格宽的点，停留后熄灭（墨点 / 碎块 / 冷掉的火星）
func _draw_parts(o, cv, p: Dictionary) -> void:
	var id: String = str(o.id)
	var dim: float = clampf(g.world.fx_dim, 0.0, 1.0) if g.world != null else 1.0
	var ash: Dictionary = p.get("tones", {}).get("ash", p)
	var n := 0
	for q in parts:
		if str(q.op) != id:
			continue
		n += 1
		var mt: Dictionary = MATS[q.m]
		var sz: float = float(q.sz)
		var col: Color
		var u: float = clampf(float(q.age) / maxf(0.001, float(q.life)), 0.0, 1.0)
		var pos: Vector2 = q.gp - Vector2(0, float(q.h))
		if q.has("c0"):   # 自带颜色：热 → 冷，落地后再压暗一阶、熄灭前半透明
			col = (q.c0 as Color).lerp(q.c1, clampf(u * 1.4, 0.0, 1.0))
			var sz2 := Vector2(sz, sz)
			if float(q.landed) >= 0.0:
				var lk3: float = float(q.landed) / maxf(0.01, float(mt.land))
				col = col.lerp(Color(0, 0, 0), 0.35)
				if lk3 > 0.6:
					col.a *= 0.5
			elif str(q.m) == "rise" and u > 0.7:
				col.a *= 0.6
			col.a *= dim
			cv.draw_rect(Rect2(_snap(pos), sz2), col)
			continue
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
			"twinkle":
				col = (p.hot if u < 0.4 else p.light) if not q.get("gold", false) else (p.get("gold", p.hot) if u < 0.5 else p.get("gold", p.hot).lerp(p.dark, 0.3))
				col.a *= dim * (1.0 if u < 0.75 else 0.5)
				var cc: Vector2 = _snap(pos)
				cv.draw_rect(Rect2(cc, Vector2(2, 2)), col)
				if u < 0.6:
					for dd in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
						cv.draw_rect(Rect2(cc + dd, Vector2(2, 2)), col)
				continue
			"streak":
				col = p.hot if u < 0.25 else (p.main if u < 0.6 else p.main.lerp(p.dark, 0.5))
				col.a *= dim
				var vv := Vector2(q.v.x, q.v.y - float(q.vh))
				if float(q.landed) >= 0.0 or vv.length() < 20.0:
					cv.draw_rect(Rect2(_snap(pos), Vector2(2, 2)), col)
				else:
					var tl: float = clampf(vv.length() * 0.05, 4.0, 18.0)
					cv.draw_line(_snap(pos), _snap(pos - vv.normalized() * tl), col, sz)
				continue
			"tri":
				var hotc: bool = u < 0.2 and float(q.landed) < 0.0
				col = Color(0.09, 0.07, 0.07)
				var r: float = sz * 0.6
				var rot: float = float(q.rot)
				if float(q.landed) >= 0.0:
					var lk: float = float(q.landed) / maxf(0.01, float(mt.land))
					col.a *= 1.0 if lk < 0.66 else 0.5
				col.a *= dim
				var tri := PackedVector2Array()
				for i in 3:
					var a: float = rot + TAU * i / 3.0
					tri.append(_snap(pos + Vector2(cos(a), sin(a) * 0.85) * r * (1.25 if i == 0 else 1.0)))
				if hotc:
					var rim: Color = p.main
					rim.a *= dim
					var tr2 := PackedVector2Array()
					for v in tri:
						tr2.append(_snap(pos + (v - pos) * 1.45))
					cv.draw_colored_polygon(tr2, rim)
				cv.draw_colored_polygon(tri, col)
				continue
			"puff":
				col = ash.main
				col.a *= (0.75 if u < 0.5 else (0.45 if u < 0.8 else 0.25)) * dim
				var ps: float = round(sz * (1.0 + 1.2 * u) / 2.0) * 2.0
				cv.draw_rect(Rect2(_snap(pos - Vector2(ps, ps) * 0.5), Vector2(ps, ps)), col)
				continue
			_:
				col = p.main
		var size := Vector2(sz, sz)
		if float(q.landed) >= 0.0:
			var lk2: float = float(q.landed) / maxf(0.01, float(mt.land))
			col = col.lerp(p.dark, 0.5 + 0.4 * lk2)
			if lk2 > 0.66:
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


## 逻各斯「言」（原作 trail_01）：墨迹彗星 = 白热亮头 + 深蓝墨尾（尾上蓝色闪点）；精一墨尾后段分两股，精二体量 ×1.5、身后拖一行白 / 紫咒文（原作提喻的字块）
func _draw_bolts(o, cv, p: Dictionary) -> void:
	var m: Dictionary = move(o, "bolt")
	if m.is_empty():
		return
	for bo in o.hw.bolts:
		var pose: Array = _bolt_pose(bo)
		var at: Vector2 = pose[0]
		var dv := Vector2.from_angle(float(pose[1]))
		var hist: Array = bo.get("visual", {}).get("hist", bo.hist)
		# 11-05 用户：放大只放在长度上——墨尾随档位加长，弹头保持小而尖（三档最多差 1 美术像素），墨尾宽不随档位变
		var L: float = float(m.get("len", 66.0)) * m.sc
		var W: float = float(m.get("w", 6.0))
		var hl: float = float(m.get("head_len", 12.0)) + (2.0 if m.tier >= 1 else 0.0)
		var hw: float = float(m.get("head_w", 4.0)) + (2.0 if m.tier >= 1 else 0.0)
		var age: float = float(bo.get("age", 0.0))
		var hot: bool = age < 0.06   # 出手首帧亮一下（只变亮，不变大）
		var fork: bool = m.tier >= 1
		if m.tier >= 2:   # 精二：尾后一行细笔画咒文
			_glyph_strip(cv, at - dv * L * 0.5, -dv, L * float(m.get("rune_k", 0.9)), 2.0, int(bo.get("_fxr_sd", 7)), Color(0, 0, 0, 0), p.hot, p.accent, 1.0, 1, -40.0)
		# 墨尾（原作 trail_01）：细长深蓝墨尾沿飞行历史点走（弧线），不够长就顺着来向延长到 L；越往后越细
		var path: Array = [at]
		for i in range(hist.size() - 1, -1, -1):
			if (hist[i] as Vector2).distance_to(path[-1]) > 1.0:
				path.append(hist[i])
		var cut: Array = [at]
		var acc := 0.0
		for i in range(1, path.size()):
			var sl: float = (path[i] as Vector2).distance_to(path[i - 1])
			if acc + sl >= L:
				cut.append((path[i - 1] as Vector2).lerp(path[i], (L - acc) / sl))
				acc = L
				break
			cut.append(path[i])
			acc += sl
		if acc < L:
			var back: Vector2 = -dv if cut.size() < 2 else ((cut[-1] as Vector2) - (cut[-2] as Vector2)).normalized()
			cut.append((cut[-1] as Vector2) + back * (L - acc))
		var nv: Vector2 = dv.orthogonal()
		var tot := 0.0
		var fs: Array = [0.0]
		for i in range(1, cut.size()):
			tot += (cut[i] as Vector2).distance_to(cut[i - 1])
			fs.append(tot)
		var mc: Color = p.main if m.tier < 2 else p.accent
		for i in range(1, cut.size()):
			var f0: float = float(fs[i - 1]) / maxf(1.0, tot)
			var f1: float = float(fs[i]) / maxf(1.0, tot)
			var wa: float = W * pow(1.0 - f0, 0.9)
			var wb: float = W * pow(1.0 - f1, 0.9)
			if _x_outline:
				cv.draw_colored_polygon(_seg(cut[i - 1], cut[i], wa + 6.0, maxf(2.0, wb) + 4.0), _outline_col(p))
			cv.draw_colored_polygon(_seg(cut[i - 1], cut[i], wa + 2.0, maxf(2.0, wb)), p.dark)
			if fork and f0 > 0.3:
				# 精一：墨尾在后段分成两股（形状差）
				var sp0: float = W * 0.45 * (f0 - 0.3) / 0.7
				var sp1: float = W * 0.45 * (f1 - 0.3) / 0.7
				for sg in [-1.0, 1.0]:
					var o0: Vector2 = (cut[i - 1] as Vector2) + nv * sp0 * sg
					var o1: Vector2 = (cut[i] as Vector2) + nv * sp1 * sg
					cv.draw_colored_polygon(_seg(o0, o1, maxf(2.0, wa * 0.34), 2.0), mc)
			elif wa * 0.4 >= 2.0:
				cv.draw_colored_polygon(_seg(cut[i - 1], cut[i], maxf(2.0, wa * 0.4), maxf(2.0, wb * 0.4)), mc)
		# 墨尾纹理（原作尾里细密的条纹 / 点）：沿尾每 4 px 一个 1 美术像素亮点，左右交替，越往后越稀越暗
		var d := 4.0
		var seg_i := 1
		while d < tot * 0.9 and seg_i < cut.size():
			while seg_i < cut.size() - 1 and float(fs[seg_i]) < d:
				seg_i += 1
			var s0: float = float(fs[seg_i - 1])
			var s1: float = float(fs[seg_i])
			var q: Vector2 = (cut[seg_i - 1] as Vector2).lerp(cut[seg_i], clampf((d - s0) / maxf(0.01, s1 - s0), 0.0, 1.0))
			var f: float = d / maxf(1.0, tot)
			var k: int = int(d / 4.0)
			if not (f > 0.55 and k % 2 == 1):
				var dc: Color = p.light if f < 0.4 else p.main.lerp(p.light, 0.35)
				cv.draw_rect(Rect2(_snap(q + nv * W * 0.22 * (1.0 - f) * (1.0 if k % 2 == 0 else -1.0)), Vector2(2, 2)), dc)
			d += 4.0
		# 弹头：小而尖的白色箭头状亮点（不画圆球）
		_exp()
		if _x_outline:
			for op in Geometry2D.offset_polygon(_quill(at + dv * hl * 0.15, dv, hl + 2.0, hw + 2.0, false), 2.0, Geometry2D.JOIN_MITER):
				cv.draw_colored_polygon(op, _outline_col(p))
		cv.draw_colored_polygon(_quill(at + dv * hl * 0.15, dv, hl + 2.0, hw + 2.0, false), p.light)
		cv.draw_colored_polygon(_quill(at + dv * hl * 0.2, dv, hl, hw, false), p.hot if not hot else Color(2.0, 2.0, 2.2))
		# 滴墨：每 shed 秒一滴（画面计时，按弹的年龄定，不抽玩法随机）
		var sh: float = float(m.get("shed", 0.1))
		if sh > 0.0 and int(age / sh) != int(bo.get("_fxr_drip", -1)):
			bo["_fxr_drip"] = int(age / sh)
			if not bo.has("_fxr_sd"):
				bo["_fxr_sd"] = g.vrng.randi() % 100000
			var tg: Dictionary = bo.get("e", {})
			var gy: float = (tg.pos.y if not tg.is_empty() else at.y) + 8.0
			_grains(o, at - dv * L * 0.4, maxf(gy, at.y + 18.0), "drop", 1, m)
			if m.tier >= 1 and int(age / sh) % 2 == 0:   # 精一起：飞行中零星金色小星（原作 0.88 s，淡金，比结晶的暖金浅）
				_grains(o, at - dv * L * 0.25, maxf(gy, at.y + 18.0), "twinkle", 1, m)
				parts[-1]["gold"] = true
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


## 地面椭圆细环（目标脚下的套环）
func _ell(cv, c: Vector2, r: float, w: float, dk: Color, mc: Color) -> void:
	cv.draw_set_transform(_snap(c), 0.0, Vector2(1.0, SY))
	var segs: int = clampi(int(r / 3.0), 16, 48)
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, segs, dk, w + 4.0)
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, segs, mc, w)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 提喻（S1，原作提喻 line_01）：笔尖 → 目标一行白色咒文字块向目标流动，下衬一道蓝丝线；目标脚下椭圆套环
## 精一：咒文分成丝线两侧两行 + 双套环（形状差）；精二：字格加大、紫白相间，读作咒文锁链
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
	var head: float = minf(1.0, (int(lk.n) * float(lk.b.get("tick", 0.25)) + float(lk.tick)) / maxf(0.05, float(lk.b.get("tick", 0.25))))
	var bb: Vector2 = a.lerp(b, head)
	var dv: Vector2 = (bb - a).normalized()
	var L: float = a.distance_to(bb)
	var tw: float = (float(m.get("w", 2.0)) + float(m.get("w_ramp", 2.0)) * ramp) * m.thick
	cv.draw_line(_snap(a), _snap(bb), Color(p.dark.r, p.dark.g, p.dark.b, 0.9), tw + 4.0)
	cv.draw_line(_snap(a), _snap(bb), p.main, tw)
	if L > 8.0:
		var fg: Color = p.hot if m.tier >= 2 else p.get("glyph", p.light)
		_glyph_strip(cv, a + dv * 6.0, dv, L - 6.0, 2.0, 3 + int(lk.n) / 4, Color(0, 0, 0, 0), fg, p.accent if m.tier >= 2 else fg,
			1.0, 2 if m.tier >= 1 else 1, float(m.get("scroll", 70.0)))
	if head >= 1.0:
		var gp: Vector2 = lk.e.pos + Vector2(0, 4)
		var r: float = (16.0 + 8.0 * ramp) * m.sc
		_ell(cv, gp, r, 3.0, Color(p.dark.r, p.dark.g, p.dark.b, 0.85), p.main if m.tier < 2 else p.accent)
		if m.tier >= 1:
			_ell(cv, gp, r * 1.5, 2.0, Color(p.dark.r, p.dark.g, p.dark.b, 0.7), p.light)
	_light_follow(o, b, float(m.get("light_r", 60.0)) * m.sc, float(m.get("light_i", 0.25)) * (0.6 + 0.4 * ramp), p.light)


## 精二连缀：成员之间一行紫白咒文（同提喻的字块）
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
			var bg: Color = p.dark
			bg.a = 0.7 * al
			var fg: Color = p.hot
			fg.a *= al
			var fg2: Color = p.accent
			fg2.a *= al
			_glyph_strip(cv, pa, (pb - pa).normalized(), pa.distance_to(pb), float(m.get("cs", 2.0)), 11 + i, bg, fg, fg2, 1.0, 1, 50.0)


## 铭文 / 墓志铭（地面）：椭圆细环 + 横排一行咒文，墓志铭从 0 写满再收
func _draw_pools(o, cv, p: Dictionary) -> void:
	for l in o.hw.pools:
		if str(l.b.get("look", "")) != "rune":
			continue
		var burst: bool = l.b.get("burst", false)
		var k: float = 1.0 - float(l.t) / maxf(0.01, float(l.dur)) if burst else 1.0
		var al: float = clampf(float(l.t) / 0.3, 0.0, 1.0)
		var r: float = float(l.r) * (0.6 if not burst else 0.4 + 0.5 * k)
		var c: Vector2 = l.pos + Vector2(0, 4)
		var dk: Color = p.dark
		dk.a = 0.8 * al
		var mc: Color = p.main
		mc.a *= al
		_ell(cv, c, r, 2.0 if not burst else 4.0, dk, mc)
		var fg: Color = p.hot
		fg.a *= al
		var fg2: Color = p.light
		fg2.a *= al
		_glyph_strip(cv, c - Vector2(r * 0.7, 0), Vector2.RIGHT, r * 1.4, 2.0, 5, Color(0, 0, 0, 0), fg, fg2, k if burst else 1.0, 1)


## 环形带（扇形咒域用）：fa ± half，半径 r0..r1（y × 0.8）
static func _fan_band(c: Vector2, fa: float, half: float, r0: float, r1: float, N: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in N + 1:
		var a: float = fa - half + 2.0 * half * i / N
		pts.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * r1))
	for i in range(N, -1, -1):
		var a: float = fa - half + 2.0 * half * i / N
		pts.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * r0))
	return pts


static func _fan_arc(c: Vector2, fa: float, half: float, r: float, N: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in N + 1:
		var a: float = fa - half + 2.0 * half * i / N
		pts.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * r))
	return pts


## 延异视阈（S3，原作 range_01 的地面咒域）。11-05 用户嫌平涂分层：改成
## 外圈一道亮蓝细边（2 美术像素）+ 内部由外向内变暗的低透明度渐变（12 圈、每圈只差约 0.02，最外 α ≤ 0.22，不盖敌人，掺点缀紫）+ 两道很淡的流动旋涡纹 +
## 外沿一排细笔画咒文；亮度靠一盏跟随照地光，不靠填色。弧两端与正中各一枚小四芒星；每跳飞来深色墨刃（见 _tick，实心）。S3 精二才解锁，只有这一个形态
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
	var N := 28
	var tk: float = float(b.get("tick", 0.5))
	var ut: float = 1.0 - clampf(float(fn.get("tick", 0.0)) / maxf(0.05, tk), 0.0, 1.0)
	var pulse: bool = ut < 0.16
	var amax: float = minf(0.25, float(m.get("fill_a", 0.22)))
	var tint: Color = p.main.lerp(p.accent, 0.45)
	var nb: int = 12
	for j in nb:
		var k: float = 1.0 - float(j) / nb   # 1 外 → 0 内
		var r1: float = rr * k
		var r0: float = maxf(4.0, rr * (k - 1.0 / nb))
		var col: Color = p.dark.lerp(tint, 0.25 + 0.6 * k)
		col.a = (0.02 + (amax - 0.02) * k * k) * fade
		cv.draw_colored_polygon(_fan_band(c, fa, half, r0, r1, N), col)
	# 淡旋涡纹：两道虚线弧，随时间沿弧流动
	var sw: Color = p.light
	for q in 2:
		var rq: float = rr * (0.5 + 0.24 * q + 0.04 * sin(g.t * 1.3 + q))
		var seg := PackedVector2Array()
		for i in N * 2 + 1:
			var a: float = fa - half + 2.0 * half * i / (N * 2)
			var on: bool = sin(a * 9.0 - g.t * (2.4 + q)) > 0.35
			if on:
				seg.append(_snap(c + Vector2(cos(a), sin(a) * 0.8) * (rq + 6.0 * (float(i) / (N * 2) - 0.5))))
			elif seg.size() >= 2:
				cv.draw_polyline(seg, Color(sw.r, sw.g, sw.b, 0.16 * fade), 2.0)
				seg = PackedVector2Array()
			else:
				seg = PackedVector2Array()
		if seg.size() >= 2:
			cv.draw_polyline(seg, Color(sw.r, sw.g, sw.b, 0.16 * fade), 2.0)
	# 外圈亮蓝细边（每跳提亮一拍）+ 两侧细边
	var ew := 4.0
	var ec: Color = p.hot if pulse else p.light
	var arc: PackedVector2Array = _fan_arc(c, fa, half, rr, N)
	cv.draw_polyline(arc, Color(p.dark.r, p.dark.g, p.dark.b, 0.6 * fade), ew + 2.0)
	cv.draw_polyline(arc, Color(ec.r, ec.g, ec.b, fade), ew)
	for sgn in [-1.0, 1.0]:
		var ea: float = fa + half * sgn
		cv.draw_line(_snap(c), _snap(c + Vector2(cos(ea), sin(ea) * 0.8) * rr), Color(p.light.r, p.light.g, p.light.b, 0.55 * fade), 2.0)
	# 四芒星：弧两端 + 正中（小物件，实心）
	var fr: float = float(m.get("star_r", 9.0)) * m.sc * (0.85 + 0.15 * sin(g.t * 6.0))
	for k2 in 3:
		var a2: float = fa + half * float(k2 - 1) * 1.02
		var q2: Vector2 = c + Vector2(cos(a2), sin(a2) * 0.8) * (rr + 6.0)
		var st := {"k": "flare", "c": q2, "ang": 0.0, "r": fr, "rv": fr * 1.3, "w": 3.0}
		for Ly in [[1.0, p.dark], [0.72, p.light if not pulse else p.hot], [0.36, p.hot]]:
			var col2: Color = Ly[1]
			col2.a *= fade
			for poly in _geo(st, 1.0, float(Ly[0])):
				cv.draw_colored_polygon(poly, col2)
	# 外沿一排细笔画咒文（切向小字行）
	var nr: int = int(m.get("rune_rows", 4))
	var fg: Color = Color(p.hot.r, p.hot.g, p.hot.b, fade)
	var fg2: Color = Color(p.accent.r, p.accent.g, p.accent.b, fade)
	for i in nr:
		var a3: float = fa - half + 2.0 * half * (i + 0.5) / nr
		var q3: Vector2 = c + Vector2(cos(a3), sin(a3) * 0.8) * (rr + 16.0)
		var tg := Vector2(-sin(a3), cos(a3) * 0.8).normalized()
		if tg.x < 0.0:
			tg = -tg
		var Lr: float = rr * float(m.get("rune_len", 0.26))
		_glyph_strip(cv, q3 - tg * Lr * 0.5, tg, Lr, 2.0, 41 + i * 13, Color(0, 0, 0, 0), fg, fg2, open, 1, 24.0)
	# 亮度靠照地：咒域中部一盏跟随光（每跳亮一拍）
	var mid: Vector2 = c + Vector2(cos(fa), sin(fa) * 0.8) * rr * 0.6
	_light_follow(o, mid, rr * 0.9, float(m.get("light_i", 0.3)) * (1.6 if pulse else 1.0) * fade, p.light)


## 扇形半径与判定同一个函数（运行时 load，不 preload 积木脚本，免得循环引用）
static func _fan_r(o, b: Dictionary) -> float:
	return float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, b))


## 号令波（推进之王 S1 + 万兽之王）：贴地灰色尘环（tones.ash）随玩法半径扩张
func _draw_waves(o, cv, p: Dictionary) -> void:
	var sg: Dictionary = o.hw.sg
	if sg.waves.is_empty():
		return
	var m: Dictionary = move(o, "wave")
	if m.is_empty():
		return
	var pa: Dictionary = p.get("tones", {}).get(str(m.get("tone", "ash")), p)
	for w in sg.waves:
		var dur: float = float(w.b.get("dur", 0.4))
		var fade: float = clampf(1.0 - (float(w.t) - dur) / 0.25, 0.0, 1.0) if float(w.t) > dur else 1.0
		var tn: Array = _tones(pa, float(w.t), dur + 0.25, 0.05, m.tier >= 2)
		var s := {"c": w.pos, "r0": float(w.r), "r": float(w.r), "w": float(m.get("w", 10.0)) * m.thick}
		tn[3] = float(tn[3]) * fade
		_draw_ring(cv, s, tn, 0.0)
