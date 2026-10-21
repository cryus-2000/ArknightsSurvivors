extends RefCounted
## 界面 · 寻访（局外成长 P1，docs/109 §12；表现层 docs/124 第三版 + §11 揭示屏加厚）：结算面板出来后，有待用的券就盖一层寻访。
## 先一次用完寻访凭证，再用定向券（招募券选职业 → 人事调度函选干员），然后整段演出：
##   拉开作战包（只拉一次，光按本次最高档）→ 光炸 → 每名干员一屏揭示（滑入 → 信号解码 → 待机循环 + 名牌 + NEW 章，5 秒自动下一名）→ 寻访结果
## 点按 / Enter：本屏直接到终态，再按下一名；Esc / 右上「跳过」：直接到寻访结果。不配语音，只用现有音效（10-22 用户）。
## 抽取在 core/roster.gd，用独立随机数，不碰局内 g.rng；演出里的碎光 / 噪点用固定表。
## 动效用真实时间（测试录屏 clock_frames 时按帧数）；「减少动态效果」不拉包、揭示直接到名牌；无头批跑直接到寻访结果。
## 作战包 / 金光 / 碎光 / 流光：Codex 交付（codex/art 35587bca，tools/probes/package_headhunt_bag.py 接入）

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")
const Roster = preload("res://scripts/core/roster.gd")
const Game = preload("res://scripts/game.gd")

const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
const CLASS_EN := {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER", "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}
## 两档（docs/124 §9.3）：金 = 新职业或意向保底命中，其余青白。[主色, 亮色]
const TIER := {"gold": [Color8(255, 196, 80), Color8(255, 240, 180)], "cyan": [Color8(96, 224, 232), Color8(200, 255, 255)]}
## 作战包时间轴（秒）：落下 0–0.4，拉链 0.4–1.6（8 档），光炸 1.45–1.9
const BAG_T := 1.9
const ZIP0 := 0.4
const ZIP1 := 1.6
const BURST := 1.55
## 每名干员一屏：滑入 0–0.5，解码 0.5–1.2，名牌 1.2–1.6（NEW 章 1.5），5 秒自动下一名（协调人缺省：每人 5 秒可跳过）
const SLIDE := 0.5
const DECODE := 1.2
const PLATE := 1.6
const STAMP := 1.5
const OP_T := 5.0
## Codex 交付的拉链契约（playback_contract.json，@2x 像素）：拉头 8 档位置、拉链右端、包体 / 金光原点
const SLIDER := [Vector2(220, 48), Vector2(194, 53), Vector2(168, 58), Vector2(142, 63), Vector2(115, 68), Vector2(89, 73), Vector2(63, 78), Vector2(37, 83)]
const ZIP_END := Vector2(220, 48)
const BAG_O := Vector2(128, 148)
const BAG_SZ := Vector2(256, 152)
const GLOW_O := Vector2(128, 272)
const GLOW_SZ := Vector2(256, 320)
## 碎光固定表：[出现时刻, 角度（度，0 = 正上）, 速度（屏高 / 秒）, 变体 0–9（6–9 是三角，只金档用）]
const SHARDS := [[0.62, -24, 0.55, 0], [0.70, 18, 0.62, 3], [0.80, -8, 0.70, 6], [0.86, 34, 0.50, 1], [0.95, -40, 0.58, 7], [1.02, 6, 0.80, 2],
	[1.10, -18, 0.66, 8], [1.16, 26, 0.72, 4], [1.24, -32, 0.60, 9], [1.30, 12, 0.85, 5], [1.38, -4, 0.90, 6], [1.44, 40, 0.64, 0],
	[1.50, -28, 0.76, 7], [1.56, 20, 0.95, 3]]

static var clock_frames := false   # 测试录屏：按渲染帧计时（--fixed-fps 下与画面同步）

var g: Game
var open := false
var step := ""            # 选择界面：Roster.T_CLASS / T_PICK / "wish"
var mode := "choose"      # choose 选择 / bag 拉包 / op 揭示 / summary 寻访结果
var back_mode := ""       # 选意向前的界面（选完回去）
var results: Array = []   # Roster.redeem_* 的返回值（只留解出干员的）
var idx := 0              # 揭示到第几名
var t0 := 0.0             # 当前段开始时刻
var _zip_ticks := 0
var _burst := false
var _stamped := -1
var reveal_id := ""       # 当前揭示的干员（测试输出用）
var choices: Array = []
var sel := 0
var rects: Array = []     # [Rect2, 动作]：动作 = "ok" / "wish" / "back" / "skip" / int（选项下标）
var _od := {}
var _img := {}            # 金光遮罩合成用的原图缓存
var _glow := {}           # [档, 帧, 拉链档] → 裁好的金光贴图


func _init(game: Game) -> void:
	g = game


func _now() -> float:
	if clock_frames:
		return Engine.get_process_frames() / 60.0
	return Time.get_ticks_msec() / 1000.0


## 结算画出来时调（hud.gd）：有待用的券就打开
func maybe_open() -> void:
	if open or not Roster.active() or Roster.pending_total() <= 0:
		return
	if Roster.locked_ids().is_empty():
		Roster.spill_to_spare()
		return
	open = true
	results.clear()
	_next()


## 下一步：先一次用完寻访凭证（第一张必出流明等规则按兑换次序，必须排在定向券前），再用定向券（各自选），最后整段演出
func _next() -> void:
	while int(Cfg.roster_tickets.get(Roster.T_HUNT, 0)) > 0 and not Roster.locked_ids().is_empty():
		var r := Roster.redeem_hunt()
		if str(r.get("id", "")) == "":
			break
		results.append(r)
	if not Roster.locked_ids().is_empty():
		for k in [Roster.T_CLASS, Roster.T_PICK]:
			if int(Cfg.roster_tickets.get(k, 0)) > 0:
				_start(k)
				return
	if Roster.locked_ids().is_empty():
		Roster.spill_to_spare()
	if results.is_empty():
		open = false
		return
	_play()


func _start(k: String) -> void:
	step = k
	sel = 0
	mode = "choose"
	if k == Roster.T_CLASS:
		var lc := Roster.locked_classes()
		choices = CLASS_ORDER.filter(func(c): return lc.has(c))
	else:
		choices = _sorted(Roster.locked_ids())


func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var ca := CLASS_ORDER.find(Roster.class_of(a))
		var cb := CLASS_ORDER.find(Roster.class_of(b))
		return ca < cb if ca != cb else a < b)
	return out


func _tier(r: Dictionary) -> String:
	return "gold" if bool(r.get("new_class", false)) or bool(r.get("pity_hit", false)) else "cyan"


func _bag_tier() -> String:
	for r in results:
		if _tier(r) == "gold":
			return "gold"
	return "cyan"


func _play() -> void:
	idx = 0
	_stamped = -1
	if UM.skip_all():
		_summary()
		return
	if UM.rm():
		_op(0)
		return
	mode = "bag"
	t0 = _now()
	_zip_ticks = 0
	_burst = false


func _op(i: int) -> void:
	idx = i
	mode = "op"
	reveal_id = results[i].id
	t0 = _now() - (DECODE if UM.rm() else 0.0)


func _summary() -> void:
	mode = "summary"
	sel = 0
	t0 = _now()


## 点按：拉包段直接到第一名；揭示段先到终态，再按下一名
func _tap() -> void:
	if mode == "bag":
		if not _burst:
			_burst_sfx()
		_op(0)
	elif mode == "op":
		if _now() - t0 < PLATE:
			t0 = _now() - PLATE
		else:
			_advance()


func _advance() -> void:
	if idx + 1 < results.size():
		_op(idx + 1)
	else:
		_summary()


func _burst_sfx() -> void:
	_burst = true
	if _bag_tier() == "gold":
		Sfx.play("beacon_lit")
		Sfx.play("levelup", -2.0)
	else:
		Sfx.play("relic")


func _act(a) -> void:
	if a is int:
		if mode != "choose" or a < 0 or a >= choices.size():
			return
		Sfx.play("ui_ok")
		if step == Roster.T_CLASS:
			_got(Roster.redeem_class(choices[a]))
		elif step == Roster.T_PICK:
			_got(Roster.redeem_pick(choices[a]))
		elif step == "wish":
			Roster.set_wish(choices[a])
			mode = back_mode
		return
	match a:
		"ok":
			if mode == "summary":
				Sfx.play("ui_ok")
				results.clear()
				_next()
			elif mode in ["bag", "op"]:
				_tap()
		"skip":
			if mode in ["bag", "op"]:
				Sfx.play("ui_ok")
				_summary()
		"wish":
			if mode == "summary" and not Roster.locked_ids().is_empty():
				Sfx.play("ui_ok")
				back_mode = mode
				step = "wish"
				choices = _sorted(Roster.locked_ids())
				sel = maxi(0, choices.find(Cfg.roster_wish))
				mode = "choose"
		"back":
			if mode == "choose" and step == "wish":
				mode = back_mode


func _got(r: Dictionary) -> void:
	if str(r.get("id", "")) != "":
		results.append(r)
	_next()


## 输入（game.gd _unhandled_input 在寻访面板打开时整段交给这里）；返回是否用掉了这次输入
func input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position / Cfg.ui_k
		for r in rects:
			if (r[0] as Rect2).has_point(p):
				_act(r[1])
				return true
		if mode in ["bag", "op"]:
			_tap()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = Pad.kc(event)
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_act(sel if mode == "choose" else "ok")
		elif k == KEY_W:
			_act("wish")
		elif k == KEY_ESCAPE:
			_act("skip" if mode in ["bag", "op"] else "back")
		elif mode == "choose" and k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D]:
			var cols := _cols()
			var d: int = {KEY_LEFT: -1, KEY_A: -1, KEY_RIGHT: 1, KEY_D: 1, KEY_UP: -cols, KEY_DOWN: cols}[k]
			sel = clampi(sel + d, 0, maxi(0, choices.size() - 1))
			g.kb_nav = true
			Sfx.play("ui_move")
		return true
	return event is InputEventMouseButton or event is InputEventScreenTouch


func _cols() -> int:
	return 4 if step == Roster.T_CLASS else 7


## 名册卡用的干员资料（同选人页 title.gd _open_op_pick 的取法，缓存）
func _card(cid: String) -> Dictionary:
	if _od.has(cid):
		return _od[cid]
	var d: Dictionary = Character.load_def(cid)
	var idle = d.get("sprites", {}).get("idle", "")
	var tn: String = idle if idle is String else idle.get("tex", "")
	var tx: Texture2D = A.tex(tn) if tn != "" else null
	var frames := 1
	if idle is Dictionary and idle.has("frames"):
		frames = int(idle.frames)
	elif tx != null:
		frames = maxi(1, tx.get_width() / tx.get_height())
	if Character.strip_mirror(d, "idle"):
		tx = A.mirror_strip(tx, frames)
	var cls: String = d.get("class", "")
	var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
	var cc = d.get("col", null)
	if cc is Array and cc.size() >= 3:
		col = Color(float(cc[0]), float(cc[1]), float(cc[2]))
	var durs: Array = idle.get("frame_durations", []) if idle is Dictionary else []
	var od := {"id": cid, "tex": tx, "frames": frames, "hires": A.hires_of(tx), "ds": UI.op_scale(d), "name": d.get("name", cid), "cls": cls, "col": col,
		"en": str(d.get("en", cid)).to_upper(), "durs": durs, "affil": _affil(cid)}
	_od[cid] = od
	return od


## 所属：lore.json 的 PRTS 档案字段（docs/76 §4）
func _affil(cid: String) -> String:
	if not _od.has("_lore"):
		var lf := FileAccess.open("res://data/lore.json", FileAccess.READ)
		var lj = JSON.parse_string(lf.get_as_text()) if lf != null else null
		_od["_lore"] = lj if lj is Dictionary else {}
	var e = _od["_lore"].get(cid, {})
	return str(e.get("profile", {}).get("所属", "")) if e is Dictionary else ""


## 待机帧：按 frame_durations 循环（没有就 4 fps）
func _idle_frame(od: Dictionary, t: float) -> int:
	var n := int(od.frames)
	var durs: Array = od.durs
	if durs.size() != n:
		return int(t * Character.ANIM_FPS.idle) % maxi(1, n)
	var total := 0.0
	for d in durs:
		total += float(d)
	var x := fmod(t, maxf(0.01, total))
	for i in n:
		x -= float(durs[i])
		if x < 0.0:
			return i
	return n - 1


func _title() -> Array:
	match step:
		Roster.T_CLASS:
			return ["招募券 · 选择职业", "RECRUITMENT PERMIT"]
		Roster.T_PICK:
			return ["人事调度函 · 指定干员", "PERSONNEL TRANSFER"]
		"wish":
			return ["设定意向干员", "PREFERRED OPERATOR"]
	return ["寻访", "HEADHUNTING"]


func _button(r: Rect2, label: String, key: String, act, hot: bool) -> void:
	rects.append([r, act])
	var hov: bool = hot if (Pad.using or g.kb_nav) else r.has_point(g.hud.get_local_mouse_position())
	g.hud.draw_rect(r, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	var ink := Color(0.04, 0.07, 0.09) if hov else UI.TEXT
	UI.text(g.hud, g.font, r.position + Vector2(14, r.size.y / 2.0 + 6.0), label, 15, ink)
	var kst: String = "" if Pad.touch else key
	if kst != "":
		UI.keycap(g.hud, g.font, Vector2(r.end.x - UI.cwidth(g.font, kst, 10) - 20, r.position.y + r.size.y / 2.0 - 9.0), kst, ink, 10)


func draw(vs: Vector2) -> void:
	rects.clear()
	match mode:
		"bag":
			_draw_bag(vs)
		"op":
			_draw_op(vs)
		"summary":
			_draw_summary(vs)
		_:
			_draw_panel(vs)


## 像素倍数：每个 1x 美术像素画几个屏幕像素，返回每个 @2x 像素的界面单位。
## 720 屏高：作战包 4 倍、立绘 6 倍，手机同屏高同倍数（docs/124 §2.1 原定立绘 4 倍、手机 2 倍，实机看太小，10-22 放大）
func _sc2(vs: Vector2, fig := false) -> float:
	var sh := vs.y * Cfg.ui_k
	var m := maxf(2.0, roundf(sh / (120.0 if fig else 180.0)))
	return m / 2.0 / Cfg.ui_k


func _blit(tx: Texture2D, frame: int, fsz: Vector2, origin: Vector2, pos: Vector2, sc: float, col := Color.WHITE) -> void:
	if tx == null:
		return
	g.hud.draw_texture_rect_region(tx, Rect2((pos - origin * sc).round(), fsz * sc), Rect2(fsz.x * frame, 0, fsz.x, fsz.y), col)


## 金光（4 帧 12 fps）按拉链档乘遮罩（交付契约：先乘 light_clip 再画，不能用整包 alpha 裁）
func _glow_tex(tier: String, f: int, s: int) -> Texture2D:
	var key := "%s%d_%d" % [tier, f, s]
	if _glow.has(key):
		return _glow[key]
	var src := _image("fx_hh_mouth_glow" + ("" if tier == "gold" else "_cyan"))
	var clip := _image("fx_hh_light_clip")
	var t: Texture2D = null
	if src != null and clip != null:
		var sz := Vector2i(GLOW_SZ)
		var dst := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
		dst.blit_rect_mask(src.get_region(Rect2i(Vector2i(f * sz.x, 0), sz)), clip.get_region(Rect2i(Vector2i(s * sz.x, 0), sz)), Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
		t = ImageTexture.create_from_image(dst)
	_glow[key] = t
	return t


func _image(name: String) -> Image:
	if _img.has(name):
		return _img[name]
	var tx := A.tex(name)
	var im: Image = tx.get_image() if tx != null else null
	if im != null:
		im = im.duplicate()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
	_img[name] = im
	return im


## 拉开作战包（docs/124 §10.2）
func _draw_bag(vs: Vector2) -> void:
	var ci: CanvasItem = g.hud
	var t := _now() - t0
	if t >= BAG_T:
		_op(0)
		_draw_op(vs)
		return
	var tier := _bag_tier()
	var tc: Array = TIER[tier]
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05))
	_scanlines(vs, t, tc[1])
	var sc := _sc2(vs)
	var ground := Vector2(roundf(vs.x / 2.0), roundf(vs.y * 0.8))
	# 落下：0–0.32 加速落地，0.32–0.4 压扁两帧
	var drop := clampf(t / 0.32, 0.0, 1.0)
	var pos := ground + Vector2(0, -(1.0 - drop * drop) * vs.y * 0.7)
	var sh := clampf(drop, 0.2, 1.0)
	ci.draw_set_transform(ground, 0.0, Vector2(1.0, 0.18))
	ci.draw_circle(Vector2.ZERO, BAG_SZ.x * sc * 0.5 * sh, Color(0, 0, 0, 0.5 * sh))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if t < ZIP0:
		var f := 0 if t < 0.32 else (1 if t < 0.36 else 2)
		_blit(A.tex("ui_hh_bag"), f, BAG_SZ, BAG_O, pos, sc)
		return
	var p := UI.ease_io((t - ZIP0) / (ZIP1 - ZIP0))
	var s := clampi(int(p * 8.0), 0, 7)
	var ticks := int((t - ZIP0) / 0.11)
	if t < ZIP1 and ticks > _zip_ticks:
		_zip_ticks = ticks
		Sfx.play("ui_move", -5.0, 1.0 + 0.04 * s)
	if t >= BURST and not _burst:
		_burst_sfx()
	_blit(A.tex("ui_hh_bag_zip"), s, BAG_SZ, BAG_O, pos, sc)
	var tl := pos - BAG_O * sc
	var mouth: Vector2 = tl + (SLIDER[s] + ZIP_END) / 2.0 * sc
	if s >= 1:
		var gt := _glow_tex(tier, int(t * 12.0) % 4, s)
		if gt != null:
			ci.draw_texture_rect(gt, Rect2((mouth - GLOW_O * sc).round(), GLOW_SZ * sc), false)
	_blit(A.tex("ui_hh_bag_zip_front"), s, BAG_SZ, BAG_O, pos, sc)
	# 碎光：从开口往上飞（三角只金档）
	var shards := A.tex("fx_hh_shards")
	for e in SHARDS:
		var lt: float = t - float(e[0]) - 0.15   # 第 1 档开口（约 0.7 秒）之后才出
		if lt < 0.0 or lt > 0.6:
			continue
		var v: int = int(e[3])
		if tier != "gold" and v >= 6:
			v -= 6
		var ang := deg_to_rad(float(e[1]))
		var d := lt * float(e[2]) * vs.y
		var sp: Vector2 = mouth + Vector2(sin(ang), -cos(ang)) * d
		_blit(shards, v, Vector2(64, 64), Vector2(32, 32), sp, sc, UI.fa(tc[1] if v < 6 else tc[0], 1.0 - lt / 0.6))
	# 光炸：档位色铺满再转白，再退（docs/124 §10.2）
	if t > 1.45:
		var a := 0.0
		var c: Color = tc[0]
		if t < 1.6:
			a = (t - 1.45) / 0.15 * 0.85
		elif t < 1.72:
			a = 0.9
			c = c.lerp(Color.WHITE, (t - 1.6) / 0.12)
		else:
			a = 0.9 * (1.0 - (t - 1.72) / 0.18)
			c = Color.WHITE
		ci.draw_rect(Rect2(Vector2.ZERO, vs), UI.fa(c, clampf(a, 0.0, 1.0)))
	_skip_button(vs)


## 全屏 4 像素暗线 + 一道自上而下移动的亮带（信号主题）
func _scanlines(vs: Vector2, t: float, hi: Color) -> void:
	var ci: CanvasItem = g.hud
	var y := 0.0
	while y < vs.y:
		ci.draw_rect(Rect2(0, y, vs.x, 1), Color(0, 0, 0, 0.22))
		y += 4.0
	var by := fmod(t * vs.y * 0.25, vs.y + 60.0) - 30.0
	ci.draw_rect(Rect2(0, by, vs.x, 24), UI.fa(hi, 0.04))
	ci.draw_rect(Rect2(0, by + 22, vs.x, 2), UI.fa(hi, 0.08))


func _skip_button(vs: Vector2) -> void:
	var r := Rect2(vs.x - 132, 18, 112, 32)
	rects.append([r, "skip"])
	var hov := r.has_point(g.hud.get_local_mouse_position())
	UI.rbox(g.hud, r, 3, Color(0.03, 0.05, 0.08, 0.7), Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.7 if hov else 0.35), 1)
	UI.text(g.hud, g.font, r.position + Vector2(14, 22), "跳过", 14, UI.TEXT)
	UI.en(g.hud, g.font, r.position + Vector2(52, 21), "SKIP", 10, UI.SUB, 2.0)


## 干员揭示屏（docs/124 §11）
func _draw_op(vs: Vector2) -> void:
	var ci: CanvasItem = g.hud
	var lt := _now() - t0
	if lt >= OP_T:
		_advance()
		if mode != "op":
			draw(vs)
			return
		lt = 0.0
	var res: Dictionary = results[idx]
	var od := _card(res.id)
	var tier := _tier(res)
	var tc: Array = TIER[tier]
	var col: Color = od.col
	var phone := Pad.touch
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.035, 0.06))
	# 背景：职业色斜向宽光束（缓慢平移）
	for i in 4:
		var bx := fmod(i * vs.x * 0.3 + lt * 18.0, vs.x * 1.3) - vs.x * 0.2
		UI.para(ci, Rect2(bx, 0, vs.x * (0.08 + 0.03 * (i % 2)), vs.y), vs.y * 0.45, UI.fa(col, 0.05 + 0.02 * (i % 2)))
	# 大号职业图标水印 + 所属名水印
	UI.class_glyph(ci, od.cls, Vector2(vs.x * 0.64, vs.y * 0.46), vs.y * 0.33, UI.fa(col, 0.08), maxf(4.0, vs.y * 0.012))
	if od.affil != "":
		UI.text(ci, g.font, Vector2(0, vs.y - 26), od.affil, 64 if not phone else 44, UI.fa(UI.TEXT, 0.06), HORIZONTAL_ALIGNMENT_RIGHT, vs.x - 28)
	# 档位色斜向流光
	var stx := A.tex("fx_hh_streak")
	if stx != null:
		var sc := _sc2(vs)
		for i in 5:
			var ph := fmod(lt * 0.55 + i * 0.37, 1.6)
			var sp := Vector2(-vs.x * 0.3 + ph * vs.x * 1.1, vs.y * (0.95 - 0.17 * i) + ph * -vs.y * 0.35)
			ci.draw_set_transform(sp.round(), deg_to_rad(-30.0), Vector2(sc, sc))
			ci.draw_texture_rect_region(stx, Rect2(Vector2(0, -8), Vector2(512, 16)), Rect2(512 * (i % 3), 0, 512, 16), UI.fa(tc[1], 0.18 + 0.06 * (i % 2)))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_scanlines(vs, lt, tc[1])
	_draw_figure(vs, od, tc, lt)
	_draw_plate(vs, od, res, tier, lt)
	# 顶栏：第几名 / 共几名
	UI.en(ci, g.font, Vector2(28, 40), "HEADHUNTING // %02d / %02d" % [idx + 1, results.size()], 12, UI.fa(tc[1], 0.8), 3.0)
	if lt >= PLATE:
		var hint := "点击继续" if idx + 1 < results.size() else "点击查看寻访结果"
		UI.text(ci, g.font, Vector2(0, vs.y - 22), hint, 12, UI.fa(UI.SUB, clampf((lt - PLATE) / 0.3, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_skip_button(vs)


## 立绘：整数倍（桌面 4 倍、手机 2 倍 × draw_scale）；滑入带 3 道残影 → 信号解码（扫描线自上而下）→ 待机循环
func _draw_figure(vs: Vector2, od: Dictionary, tc: Array, lt: float) -> void:
	var ci: CanvasItem = g.hud
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var fh: float = tx.get_height()
	var bb: Rect2 = UI.card_bb(od, tx)
	var k: float = _sc2(vs, true) * 2.0 / hi * float(od.ds)
	var foot := Vector2(roundf(vs.x * 0.64), roundf(vs.y * 0.86))
	var f := 0 if lt < DECODE else _idle_frame(od, lt - DECODE)
	var src := Rect2(fw * f + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var slide := UM.out_cubic(lt / SLIDE)
	var dx := (1.0 - slide) * vs.x * 0.45
	var pos := UI.foot_pos(foot, bb, fw, fh, hi, k).round()
	var dst := Rect2(pos + Vector2(roundf(dx), 0), (bb.size * k).round())
	var wt := A.white_of(tx)
	# 脚下投影环
	ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.22))
	for i in 3:
		ci.draw_arc(Vector2.ZERO, bb.size.x * k * (0.45 + 0.18 * i), 0, TAU, 48, UI.fa(tc[0], (0.35 - 0.1 * i) * slide), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if lt < SLIDE:
		for i in 3:
			var ar := dst
			ar.position.x += (i + 1) * vs.x * 0.05 * (1.0 - slide)
			ci.draw_texture_rect_region(wt, ar, src, UI.fa(tc[0], 0.32 - 0.09 * i))
	var dk := Color(0.07, 0.09, 0.16)
	if lt < DECODE:
		ci.draw_texture_rect_region(wt, dst, src, dk)
	if lt < SLIDE:
		return
	if lt >= DECODE:
		ci.draw_texture_rect_region(tx, dst, src)
		var fl := 1.0 - (lt - DECODE) / 0.12
		if fl > 0.0:
			ci.draw_texture_rect_region(wt, dst, src, UI.fa(Color.WHITE, fl * 0.7))
		return
	# 解码：扫过的行已是彩色
	var e := (lt - SLIDE) / (DECODE - SLIDE)
	var rows := floorf(bb.size.y * e)
	if rows > 0.0:
		ci.draw_texture_rect_region(tx, Rect2(dst.position, Vector2(dst.size.x, rows * k)), Rect2(src.position, Vector2(src.size.x, rows)))
	var sy := dst.position.y + rows * k
	ci.draw_rect(Rect2(dst.position.x - 16, sy - 1, dst.size.x + 32, 2), UI.fa(tc[1], 0.95))
	# 扫描线下沿 3 行 4 像素噪点块（固定散列，不读 g.rng）
	var cell := 4.0
	var nx := int(dst.size.x / cell) + 1
	for r in 3:
		for c in nx:
			var hsh := (c * 73856093) ^ (r * 19349663) ^ (int(lt * 20.0) * 83492791)
			if hsh % 5 < 2:
				ci.draw_rect(Rect2(dst.position.x + c * cell, sy + 2 + r * cell, cell, cell), UI.fa(tc[0] if hsh % 3 else tc[1], 0.5 - 0.14 * r))


## 名牌：职业色竖条 + 职业图标、编号 // 职业英文、大字中文名、英文代号、职业干员 · 所属；NEW 章（金档金边）
func _draw_plate(vs: Vector2, od: Dictionary, res: Dictionary, tier: String, lt: float) -> void:
	if lt < DECODE:
		return
	var ci: CanvasItem = g.hud
	var tc: Array = TIER[tier]
	var s := clampf(vs.y / (560.0 if Pad.touch else 720.0), 0.72, 1.2)
	var e := UM.out_cubic((lt - DECODE) / (PLATE - DECODE))
	var w := 440.0 * s
	var h := 200.0 * s
	var r := Rect2(roundf(vs.x * 0.06 - (1.0 - e) * w * 0.6), roundf(vs.y * 0.34), w, h)
	var a := e
	ci.draw_rect(r, Color(0.03, 0.045, 0.075, 0.82 * a))
	ci.draw_rect(Rect2(r.position, Vector2(6 * s, r.size.y)), UI.fa(od.col, a))
	if tier == "gold":
		var gc := UI.fa(tc[0], a)
		ci.draw_rect(r, gc, false, 2.0)
		ci.draw_rect(r.grow(-4.0), UI.fa(tc[1], 0.35 * a), false, 1.0)
	else:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), UI.fa(tc[0], 0.6 * a))
	var x := r.position.x + 28 * s
	UI.class_glyph(ci, od.cls, Vector2(x + 10 * s, r.position.y + 30 * s), 10 * s, UI.fa(od.col, a), 2.0)
	var no := Roster.all_ids().find(od.id) + 1
	UI.en(ci, g.font, Vector2(x + 30 * s, r.position.y + 36 * s), "NO.%02d // %s" % [no, CLASS_EN.get(od.cls, "")], int(12 * s), UI.fa(UI.SUB, a), 3.0)
	UI.text(ci, g.font, Vector2(x, r.position.y + 100 * s), od.name, int(48 * s), UI.fa(UI.TEXT, a))
	UI.en(ci, g.font, Vector2(x + 2, r.position.y + 128 * s), od.en, int(16 * s), UI.fa(od.col, a), 4.0)
	var line: String = "%s干员" % od.cls + ((" · 所属 " + od.affil) if od.affil != "" else "")
	UI.text(ci, g.font, Vector2(x, r.position.y + 160 * s), line, int(14 * s), UI.fa(UI.SUB, a))
	var cx := x
	var cy := r.position.y + 172 * s
	if bool(res.get("new_class", false)):
		cx += UI.chip(ci, g.font, Vector2(cx, cy), "新职业 · " + od.cls, UI.fa(UI.GOLD, a), int(11 * s)) + 6.0
	if bool(res.get("pity_hit", false)):
		UI.chip(ci, g.font, Vector2(cx, cy), "意向干员 · 保底", UI.fa(UI.PURPLE, a), int(11 * s))
	# NEW 章：1.5 秒盖下（out_back 缩放落定）
	if lt >= STAMP:
		if _stamped != idx:
			_stamped = idx
			Sfx.play("ui_ok")
		var se := clampf((lt - STAMP) / 0.22, 0.0, 1.0)
		var k := lerpf(1.6, 1.0, UI.ease_back(se))
		var sc_ := Vector2(r.end.x - 70 * s, r.end.y - 22 * s)
		ci.draw_set_transform(sc_, deg_to_rad(-8.0), Vector2(k, k))
		var sr := Rect2(Vector2(-46, -18) * s, Vector2(92, 36) * s)
		var sa := clampf(se * 2.0, 0.0, 1.0)
		ci.draw_rect(sr, UI.fa(tc[0], 0.2 * sa))
		ci.draw_rect(sr, UI.fa(tc[0], sa), false, 2.0)
		UI.en(ci, g.font, Vector2(-30 * s, 8 * s), "NEW", int(20 * s), UI.fa(tc[1], sa), 6.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	UI.text(ci, g.font, Vector2(r.position.x, r.end.y + 26 * s), "已加入名册", int(13 * s), UI.fa(tc[1], a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 寻访结果：一排竖卡，按职业顺序（docs/124 §11）
func _draw_summary(vs: Vector2) -> void:
	var ci: CanvasItem = g.hud
	var t := 99.0 if (UM.rm() or UM.skip_all()) else _now() - t0
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.035, 0.06))
	_scanlines(vs, t, UI.CYAN)
	var tier := _bag_tier()
	var tc: Array = TIER[tier]
	var ew := UI.en_width(g.font, "HEADHUNT RESULT", 13, 4.0)
	UI.en(ci, g.font, Vector2(vs.x / 2.0 - ew / 2.0, vs.y * 0.12), "HEADHUNT RESULT", 13, tc[0], 4.0)
	UI.heading(ci, g.font, Vector2(vs.x / 2.0, vs.y * 0.12 + 36), "寻访结果", 26, tc[0], minf(240.0, vs.x / 4.0))
	UI.text(ci, g.font, Vector2(0, vs.y * 0.12 + 70), "%d 名干员已加入名册" % results.size(), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var rs := results.duplicate()
	rs.sort_custom(func(a, b): return CLASS_ORDER.find(Roster.class_of(a.id)) < CLASS_ORDER.find(Roster.class_of(b.id)))
	var n := rs.size()
	var cw := minf(150.0, (vs.x - 96.0 - 14.0 * (n - 1)) / n)
	var chh := cw * 1.42
	var x0 := vs.x / 2.0 - (n * cw + (n - 1) * 14.0) / 2.0
	var y0 := vs.y * 0.12 + 96
	for i in n:
		var r: Dictionary = rs[i]
		var od := _card(r.id)
		var e := UM.out_cubic((t - 0.06 * i) / 0.3)
		var cr := Rect2(roundf(x0 + i * (cw + 14.0)), roundf(y0 + (1.0 - e) * 24.0), cw, chh)
		var rc: Array = TIER[_tier(r)]
		UI.roster_card(ci, g.font, cr, od, 0.0, 0.0, 0, _idle_frame(od, t), e, 13)
		ci.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 4)), UI.fa(rc[0], e))
		UI.class_glyph(ci, od.cls, cr.position + Vector2(cr.size.x - 16, 20), 7.0, UI.fa(od.col, e), 1.8)
		UI.en(ci, g.font, cr.position + Vector2(8, 24), "NEW", 11, UI.fa(rc[1], e), 3.0)
		UI.text(ci, g.font, Vector2(cr.position.x, cr.end.y + 20), Roster.TICKET_NAME.get(r.kind, ""), 11, UI.fa(UI.SUB, e), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	var locked := Roster.locked_ids()
	var wl: String
	if locked.is_empty():
		wl = "名册已满"
	elif Cfg.roster_wish != "" and locked.has(Cfg.roster_wish):
		wl = "意向干员：%s（寻访保底 %d / %d）" % [Character.load_def(Cfg.roster_wish).get("name", Cfg.roster_wish), mini(Cfg.roster_pity + 1, Roster.PITY), Roster.PITY]
	else:
		wl = "未设定意向干员：设定后 %d 张寻访凭证内必出" % Roster.PITY
	UI.text(ci, g.font, Vector2(0, y0 + chh + 58), wl, 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var bw := 180.0
	var by := minf(vs.y - 70.0, y0 + chh + 82)
	if locked.is_empty():
		_button(Rect2(vs.x / 2.0 - bw / 2.0, by, bw, 40), "完成", "Enter", "ok", true)
	else:
		_button(Rect2(vs.x / 2.0 - bw - 6.0, by, bw, 40), "完成", "Enter", "ok", sel == 0)
		_button(Rect2(vs.x / 2.0 + 6.0, by, bw, 40), "设定意向", "W", "wish", false)


## 选择界面（招募券选职业 / 人事调度函选干员 / 设定意向）
func _draw_panel(vs: Vector2) -> void:
	var ci: CanvasItem = g.hud
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.9))
	var pw := minf(vs.x - 48.0, 700.0)
	var ph := 430.0
	var r := Rect2(vs.x / 2.0 - pw / 2.0, vs.y / 2.0 - ph / 2.0, pw, ph)
	var col := UI.CYAN
	UI.frame(ci, r, col, {"t": g.t})
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	var tt := _title()
	var ew: float = g.font.get_string_size(tt[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + tt[1].length() * 4.0
	UI.en(ci, g.font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 40), tt[1], 13, col, 4.0)
	UI.heading(ci, g.font, Vector2(r.get_center().x, r.position.y + 74), tt[0], 26, col, minf(240.0, pw / 2.0 - 24.0))
	# 剩余的券
	var left: Array = []
	for k in [Roster.T_HUNT, Roster.T_CLASS, Roster.T_PICK]:
		var n := int(Cfg.roster_tickets.get(k, 0))
		if n > 0:
			left.append("%s ×%d" % [Roster.TICKET_NAME[k], n])
	UI.text(ci, g.font, Vector2(r.position.x + 24, r.end.y - 18), ("待用：" + " · ".join(left)) if not left.is_empty() else "待用：无", 12, UI.SUB)
	UI.text(ci, g.font, Vector2(r.end.x - 224, r.end.y - 18), "名册 %d / %d" % [Roster.all_ids().size() - Roster.locked_ids().size(), Roster.all_ids().size()], 12, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	_draw_choose(r)


func _draw_choose(r: Rect2) -> void:
	var ci: CanvasItem = g.hud
	var mouse := ci.get_local_mouse_position()
	if step == Roster.T_CLASS:
		UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 112), "从所选职业的未解锁干员里随机解锁 1 名", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var cols := _cols()
		var bw := (r.size.x - 64.0 - 12.0 * (cols - 1)) / cols
		for i in choices.size():
			var cls: String = choices[i]
			var br := Rect2(r.position.x + 32 + (i % cols) * (bw + 12), r.position.y + 140 + int(i / cols) * 70, bw, 58)
			rects.append([br, i])
			var hov: bool = (i == sel) if (Pad.using or g.kb_nav) else br.has_point(mouse)
			var cc: Color = Character.CLASS_COL.get(cls, UI.CYAN)
			UI.rbox(ci, br, 5, Color(0.086, 0.102, 0.204, 0.92) if hov else Color(0.039, 0.078, 0.118, 0.86), cc if hov else Color(cc.r, cc.g, cc.b, 0.45), 2 if hov else 1)
			UI.class_glyph(ci, cls, br.position + Vector2(22, 29), 7.0, cc, 1.8)
			UI.text(ci, g.font, br.position + Vector2(40, 26), cls, 16, UI.TEXT)
			var n := Roster.locked_ids().filter(func(c): return Roster.class_of(c) == cls).size()
			UI.text(ci, g.font, br.position + Vector2(40, 46), "未解锁 %d 名" % n, 11, UI.SUB)
		return
	var hint := "选择 1 名干员直接解锁" if step == Roster.T_PICK else "意向干员 %d 张寻访凭证内必出；之后可以随时更换" % Roster.PITY
	UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 112), hint, 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var cols := _cols()
	var cw := minf(78.0, (r.size.x - 48.0 - 8.0 * (cols - 1)) / cols)
	var chh := cw * 1.3
	var x0 := r.get_center().x - (cols * cw + (cols - 1) * 8.0) / 2.0
	for i in choices.size():
		var cr := Rect2(x0 + (i % cols) * (cw + 8.0), r.position.y + 132 + int(i / cols) * (chh + 14.0), cw, chh)
		rects.append([cr, i])
		var hov: bool = (i == sel) if (Pad.using or g.kb_nav) else cr.has_point(mouse)
		UI.roster_card(ci, g.font, cr, _card(choices[i]), 1.0 if hov else 0.0, 0.0, 0, int(g.t * 4.0 + i) % int(_card(choices[i]).frames), 1.0, 11)
		if choices[i] == Cfg.roster_wish:
			UI.chip(ci, g.font, cr.position + Vector2(2, cr.size.y + 4), "意向", UI.GOLD, 10)
	if step == "wish":
		_button(Rect2(r.get_center().x - 90.0, r.end.y - 62.0, 180, 36), "返回", "Esc", "back", false)
