extends RefCounted
## 界面 · 开场与教程：开局镜头演出（state OPENING）与其 HUD、新手教程分页（state INTRO）的打开 / 翻页 / 关闭 / 绘制。
## 界面层约定（docs/39 §3）：只读 game.gd 状态、只画自己的界面；改状态走 game.gd / run/ 的函数。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var opening_t := 0.0             # 开场动画时间
const SETTLED := 2.65
const DROP_START := 2.55
const TOUCHDOWN := 3.38
const DOCTOR_DROP := 3.18
const DOCTOR_LAND := 3.94
const LIFT_OFF := 4.08
const CLEAR_SKY := 6.55
const OPENING_DUR := 6.80
const OBJECTIVE_IN := 4.55
const TRANSPORT_PATH := "res://art/world/props/bad_guy_transport.png"
const RUMBLE_PATH := "res://audio/sfx/transport_rumble.ogg"
const HULL := Rect2(0, 0, 244, 223)
const SILL := Vector2(50, 178)   # 后舱坡道外端，从 Blender 的实机相机投影得到
const ROTOR_SIZE := Vector2(106, 76)
const ROTOR_ORIGINS := [Vector2(116, 124), Vector2(35, 11)]
const TRANSPORT_SCALE := 1.64
var transport: Texture2D   # 单次开场持有，不进入 Art 的整局贴图缓存
var engine_player: AudioStreamPlayer

func release_transport() -> void:
	transport = null
	if is_instance_valid(engine_player):
		engine_player.stop()
		engine_player.stream = null
		engine_player.queue_free()
	engine_player = null

## 进场时已在巡航，减速至舱门对准落点。起飞先抬高，再逐渐加速穿出画面。
func flight_height() -> float:
	return 1.0 - smoothstep(0.42, SETTLED, opening_t) + smoothstep(LIFT_OFF, LIFT_OFF + 1.60, opening_t)

## 舱口与干员脚底统一使用世界坐标，判定位置始终在地面。
func hatch() -> Vector2:
	var view: Rect2 = g.world.view_rect(0.0)
	var approach := pow(clampf(1.0 - opening_t / SETTLED, 0.0, 1.0), 2.0)
	var u := clampf(inverse_lerp(LIFT_OFF, CLEAR_SKY, opening_t), 0.0, 1.0)
	var depart := u * u * (2.0 - u)
	var travel := view.size.x * 0.65 + 315.0
	return g.ppos + Vector2(26.0 + (depart - approach) * travel, -75.0 + 108.0 * approach - 48.0 * depart - 28.0 * flight_height() + 1.2 * sin(opening_t * 2.1))

func drop_position(ground: Vector2, start := DROP_START, land := TOUCHDOWN) -> Vector2:
	var u := clampf(inverse_lerp(start, land, opening_t), 0.0, 1.0)
	return hatch().lerp(ground, u * u) + Vector2(0.0, -12.0 * sin(PI * u))

## 只露出越过后舱门下沿的像素，避免大帧条的头顶从尾翼间的透明区域透出来。
func draw_from_hatch(tx: Texture2D, frame: int, hf: int, origin: Vector2, anchor: Vector2, flip: bool, tint: Color) -> void:
	var pixel := Game.PX / A.hires_of(tx)
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var cut := clampi(ceili((hatch().y - 12.0 - origin.y) / pixel + anchor.y), 0, fh)
	if cut == fh:
		return
	var src := Rect2(fw * (frame % hf), cut, fw, fh - cut)
	var dst := Rect2(Vector2(0, cut) - anchor, src.size)
	g.wcv.draw_set_transform(origin.round(), 0.0, Vector2(-pixel if flip else pixel, pixel))
	g.wcv.draw_texture_rect_region(tx, dst, src, tint)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_transport_shadow() -> void:
	if transport == null:
		return
	var height := flight_height()
	var shadow_scale := TRANSPORT_SCALE * Vector2(0.97, 0.87)
	var shadow_origin := (hatch() + Vector2(-10.0 - 18.0 * height, 33.0 + 53.0 * height) - SILL * shadow_scale).round()
	var shade := Color(0.01, 0.02, 0.03, lerpf(0.38, 0.18, height))
	g.wcv.draw_texture_rect_region(transport, Rect2(shadow_origin, HULL.size * shadow_scale), HULL, shade)

func draw_transport() -> void:
	if transport == null:
		return
	var scale_px := TRANSPORT_SCALE * (1.0 + 0.085 * flight_height())
	var top_left := (hatch() - SILL * scale_px).round()
	var light := Color(1.35, 1.39, 1.42)
	g.wcv.draw_texture_rect_region(transport, Rect2(top_left, HULL.size * scale_px), HULL, light)
	# 两翼共用六帧外露三叶桨，反向取帧。图集下方每行三格，机身只存一次。
	var phase := int(opening_t * 24.0) % 6
	for i in ROTOR_ORIGINS.size():
		var frame := phase if i == 0 else (6 - phase) % 6
		var src := Rect2(Vector2((frame % 3) * ROTOR_SIZE.x, HULL.size.y + floori(frame / 3.0) * ROTOR_SIZE.y), ROTOR_SIZE)
		var dst := Rect2(top_left + ROTOR_ORIGINS[i] * scale_px, ROTOR_SIZE * scale_px)
		g.wcv.draw_texture_rect_region(transport, dst, src, light)


func _init(game: Game) -> void:
	g = game


func prev_page() -> void:
	if g.intro_page > 0:
		g.intro_page -= 1
		g.intro_t = 0.0
		Sfx.play("ui_move")


## 开场动画：坏家伙号悬停、编队离舱落地、点灯。任意键可跳过。
func start_opening() -> void:
	g.state = Game.S.OPENING
	opening_t = 0.0
	release_transport()
	transport = ResourceLoader.load(TRANSPORT_PATH, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var rumble := ResourceLoader.load(RUMBLE_PATH, "AudioStreamOggVorbis", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	if rumble != null:
		engine_player = AudioStreamPlayer.new()
		engine_player.bus = &"SFX"
		engine_player.volume_db = -4.0
		engine_player.stream = rumble
		g.add_child(engine_player)
		engine_player.play()
	g.p_off = Vector2.ZERO
	g.lamp_light.energy = 0.0
	for a in Cfg.dev_args():
		if a.begins_with("--openingmem"):   # 运输机释放验收（tests/opening_transport_probe.gd）
			var pr = load("res://tests/opening_transport_probe.gd").new()
			pr.g = g
			pr.skip = a == "--openingmem=skip"
			pr.tex_ref = weakref(transport)
			pr.snd_ref = weakref(rumble) if rumble != null else null
			pr.player_ref = weakref(engine_player) if engine_player != null else null
			g.add_child(pr)
	Sfx.play("start", -14.0)   # 音量巡检：开场引子开头近乎无声，-4 dB 时比音乐响 29 dB；现在只托住开头，和 1.7 秒后的引子齐平


func update_opening(dt: float) -> void:
	opening_t += dt
	if transport != null and opening_t > LIFT_OFF:
		# 最左端取机身与投影的保守外沿。出画后先退贴图，远去的尾音仍可自然衰减。
		var left_edge := hatch().x - SILL.x * TRANSPORT_SCALE * 1.085 - 32.0
		if left_edge > g.world.view_rect(0.0).end.x:
			transport = null
	if opening_t >= CLEAR_SKY and opening_t - dt < CLEAR_SKY:
		release_transport()
	if opening_t < DOCTOR_LAND:
		g.p_off = drop_position(g.sprite.position, DOCTOR_DROP, DOCTOR_LAND) - g.sprite.position
	else:
		g.p_off = Vector2.ZERO
	# 落地
	if opening_t >= TOUCHDOWN and opening_t - dt < TOUCHDOWN:
		g.world.feet_dust(3, 36.0)
		for o in g.squad.ops:
			o.play_entry()   # 编队着地接入场条（10-22）
		g.release_entry_voices()   # 登场语音在编队着地、黑场已褪时才播（以前在建局时就响，画面还没出来，用户 10-25）
	if opening_t >= TOUCHDOWN:
		for o in g.squad.ops:
			if o.vis_anim == "entry":
				o.anim_t += dt   # 开场期间干员不走 update：入场条在这里推进（end_opening 后由 update 接着走）
		g.p_sq = g.p_sq.lerp(Vector2.ONE, 1.0 - exp(-dt * 10.0))
		g.p_lean = lerpf(g.p_lean, 0.0, 1.0 - exp(-dt * 10.0))
	# 博士站定后点灯。
	if opening_t >= DOCTOR_LAND:
		g.lamp_light.energy = 1.15 * smoothstep(DOCTOR_LAND, DOCTOR_LAND + 0.8, opening_t)
		if opening_t - dt < DOCTOR_LAND:
			Sfx.play("oil", -8.0, 1.2, 0.0)
	g.vfx.update(dt)
	if opening_t >= OPENING_DUR:
		end_opening()


func end_opening() -> void:
	if g.state != Game.S.OPENING:
		return
	release_transport()
	g.p_off = Vector2.ZERO
	g.p_sq = Vector2.ONE
	g.p_lean = 0.0
	g.lamp_light.energy = 1.15
	g.state = Game.S.PLAY
	g.release_entry_voices()   # 跳过开场：没等到着地也放
	# 首局改聚光框引导（协调人 10-26，screens/tour.gd）；翻页指南只在暂停菜单「指南」里重看
	# 新手引导（docs/219）接管时不再弹旧的聚光框引导
	if not g.onboard.begin() and not Cfg.seen_intro:
		g.tour.start()


func draw_opening_hud(vs: Vector2) -> void:
	# 黑场渐亮 + 上下黑边 + 标题卡
	var dark: float = clampf(1.0 - opening_t / 0.52, 0.0, 1.0) * 0.9 + 0.1
	var fade_out := smoothstep(OPENING_DUR - 0.72, OPENING_DUR, opening_t)
	dark *= 1.0 - fade_out
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03, dark))
	var bar: float = 70.0 * (1.0 - fade_out)
	g.hud.draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0, 0, 0.95))
	g.hud.draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0, 0, 0.95))
	if opening_t > OBJECTIVE_IN:
		var a: float = smoothstep(OBJECTIVE_IN, OBJECTIVE_IN + 0.28, opening_t) * (1.0 - fade_out)
		# 11-07 用户：开场标题卡只留行动目标一行（原「干员 · 深海探索」与 OPERATION 英文行删去）
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.22 + 40), "行动目标：维持作战至 10:00，击败它们", 26, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	UI.text(g.hud, g.font, Vector2(0, vs.y - 26), "点击跳过" if Pad.touch_ui() else "任意键跳过", 12, Color(0.5, 0.6, 0.65, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 2)


## 指南文字在 data/guide.json（文案维护；10-15 从 game.gd INTRO_PAGES 与本文件的 TOUCH_SUBS / TOUCH_CONTROLS / MORE_HINT 原样搬去，docs/101 S5）：
## pages 8 页（title / en / icon / lines / more）；touch_subs 触屏版逐句替换 [键鼠说法, 触屏说法]；touch_controls 触屏版最后一页「操作」整页；
## more_hint 精简版（首次自动打开）最后一页末尾的提示
static var _guide: Dictionary = {}


static func _g() -> Dictionary:
	if _guide.is_empty():
		_guide = JSON.parse_string(FileAccess.get_file_as_string("res://data/guide.json"))
	return _guide


static func pages() -> Array:
	return _g().pages


static func touch_line(ln: String) -> String:
	if not Pad.touch_ui():
		return ln
	for p in _g().touch_subs:
		ln = ln.replace(p[0], p[1])
	return ln


## 完整版指南：从暂停菜单打开（G / 「指南」）时显示每页的 lines + more；首次进局自动打开的是精简版（只有 lines）
func full_guide() -> bool:
	return g.intro_back == Game.S.PAUSE


## 一页要显示的段落：精简版只有 lines，最后一页末尾加 more_hint；完整版接上 more
static func page_lines(pg: Dictionary, full: bool, last: bool) -> Array:
	var out: Array = pg.get("lines", []).duplicate()
	if full:
		out.append_array(pg.get("more", []))
	elif last:
		out.append(_g().more_hint)
	return out


func open(back: int) -> void:
	g.intro_back = back
	g.intro_page = 0
	g.intro_t = 0.0
	g.state = Game.S.INTRO


func next_page() -> void:
	Sfx.play("ui_move")
	if g.intro_page < view_count() - 1:
		g.intro_page += 1
		g.intro_t = 0.0
	else:
		close()


func close() -> void:
	Cfg.seen_intro = true
	Cfg.save()
	g.state = g.intro_back
	Sfx.play("ui_ok", -4.0)


## ---------------------------------------------------------------- 指南版式（11-11 按 docs/37 水月方案 A + 暂停菜单指挥台版式统一，docs/222 §20）
## 面板 = 暂停菜单同款：暗底 + 对角两枚直角刻度，居中灰色英文小签 + 白色标题（UI.heading），右上「01 / 06」页码；
## 左栏插图统一成线框示意（白线 + 灰字，金 = 灯火、青 = 当前 / 可操作、洋红 = 集火），右栏「标签｜正文」；
## 正文字号固定（桌面 15、手机 19 再走 UI.fs），整页放不下就按条拆成几页（标题后加「（续）」），不再缩字号；
## 上一页 / 跳过 / 下一页都在面板底栏里，桌面带按键牌。翻页按「视图页」（views）：一页数据可能拆成几张视图页。
const BODY_DESK := 15
const BODY_PHONE := 19
const INK := Color(1, 1, 1, 0.8)       # 示意图主线
const INK2 := Color(1, 1, 1, 0.26)     # 示意图次线 / 轨道
const FILL := Color(1, 1, 1, 0.05)     # 示意图面
var _views: Array = []
var _vkey := ""
var _c := Vector2.ZERO   # 示意图中心与缩放（_p 用）
var _s := 1.0


func _touch() -> bool:
	return Cfg.touch_device()


## 面板与各栏的位置（views 与 draw 共用，拆页按同一套尺寸量）
func _layout(vs: Vector2) -> Dictionary:
	var touch := _touch()
	var w: float = vs.x - 24.0 if touch else minf(980.0, vs.x - 48.0)
	var h: float = vs.y - 16.0 if touch else minf(600.0, vs.y - 40.0)
	var r := Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)
	var head_h := 96.0 if touch else 122.0
	var bar_h := 64.0 if touch else 62.0
	var ill_w := 260.0 if touch else 300.0
	var pad := 24.0 if touch else 36.0
	var fr := Rect2(r.position.x + pad, r.position.y + head_h, ill_w, r.size.y - head_h - bar_h - 14.0)
	var tx := fr.end.x + (24.0 if touch else 32.0)
	var fsz := BODY_PHONE if touch else BODY_DESK
	return {"r": r, "fr": fr, "tx": tx, "tw": r.end.x - pad - tx, "top": fr.position.y, "bot": fr.end.y,
		"fsz": fsz, "lsz": 15 if touch else 13, "gap": 12.0 if touch else 14.0, "bar_y": r.end.y - bar_h + (6.0 if touch else 12.0)}


## 某页实际显示的条目（触屏版最后一页换成 touch_controls）→ [{label, text}]
func _rows_of(pi: int) -> Array:
	var last: bool = pi == pages().size() - 1
	var src: Dictionary = _g().touch_controls if Pad.touch_ui() and last else pages()[pi]
	var rows: Array = []
	for ln in page_lines(src, full_guide(), last):
		var txt: String = touch_line(fill_numbers(ln))
		var cut: int = txt.find("｜")
		rows.append({"label": txt.substr(0, cut) if cut > 0 else "", "text": txt.substr(cut + 1) if cut > 0 else txt})
	return rows


## 视图页：每页数据按正文栏高度拆成一张或几张，拆分时各张高度尽量平均。缓存键 = 尺寸 + 完整 / 精简 + 触屏
func views(vs := Vector2.ZERO) -> Array:
	if vs == Vector2.ZERO:
		vs = g.hud.size
	var key := "%s|%s|%s|%s" % [vs, full_guide(), Pad.touch_ui(), UI.fk]
	if key == _vkey:
		return _views
	_vkey = key
	_views = []
	var L := _layout(vs)
	var fsz: int = L.fsz
	var lhh: float = g.font.get_height(UI.fs(fsz)) + 2.0
	var all_rows: Array = []
	var lbl_w := 0.0
	for pi in pages().size():
		var rows := _rows_of(pi)
		all_rows.append(rows)
		for row in rows:
			if row.label != "":
				lbl_w = maxf(lbl_w, g.font.get_string_size(row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(L.lsz)).x)
	lbl_w += 26.0
	var avail: float = L.bot - L.top
	for pi in all_rows.size():
		var tot := 0.0
		for row in all_rows[pi]:
			row["lines"] = UI.wrap_lines(g.font, row.text, fsz, L.tw - (lbl_w if row.label != "" else 0.0))
			row["h"] = maxf(row.lines.size(), 1) * lhh
			tot += row.h + L.gap
		var n: int = maxi(1, ceili((tot - L.gap) / avail))
		var target: float = tot / n
		var chunk: Array = []
		var ch := 0.0
		var k := 0
		for row in all_rows[pi]:
			var need: float = ch + row.h + (L.gap if not chunk.is_empty() else 0.0)
			if not chunk.is_empty() and (need > avail or (ch >= target * 0.9 and k < n - 1)):
				_views.append({"p": pi, "rows": chunk, "cont": k > 0, "h": ch})
				chunk = []
				ch = 0.0
				k += 1
				need = row.h
			chunk.append(row)
			ch = need
		_views.append({"p": pi, "rows": chunk, "cont": k > 0, "h": ch})
	for v in _views:
		v["lbl_w"] = lbl_w
		v["lhh"] = lhh
	return _views


func view_count() -> int:
	return views().size()


func draw(vs: Vector2) -> void:
	if g.onboard.modal():
		g.onboard.draw_modal(vs)   # 新手引导的问题框 / 演示图鉴（screens/onboard.gd）
		return
	if g.tour.active:
		g.tour.draw(vs)
		return
	var vw := views(vs)
	g.intro_page = clampi(g.intro_page, 0, vw.size() - 1)
	var v: Dictionary = vw[g.intro_page]
	var pg: Dictionary = pages()[v.p]
	var L := _layout(vs)
	var touch := _touch()
	var r: Rect2 = L.r
	var ea := clampf(g.intro_t / 0.25, 0.0, 1.0)
	var dy := (1.0 - UI.ease_out(ea)) * 12.0
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.84))
	# 面板：暂停菜单同款暗底 + 对角直角刻度（底比暂停略深：手机上面板占满屏，局内顶栏不能透到标题和页码后面）
	g.hud.draw_rect(r, Color(0.01, 0.015, 0.02, 0.75))
	var tk := Color(1, 1, 1, 0.5)
	g.hud.draw_polyline(PackedVector2Array([r.position + Vector2(0, 14), r.position, r.position + Vector2(14, 0)]), tk, 1.0)
	g.hud.draw_polyline(PackedVector2Array([r.end - Vector2(0, 14), r.end, r.end - Vector2(14, 0)]), tk, 1.0)
	# 顶栏：英文小签（灰）+ 标题 + 右上页码
	var cx := r.get_center().x
	var en_s: String = str(pg.en)
	var ew := UI.en_width(g.font, en_s, 12, 4.0)
	UI.en(g.hud, g.font, Vector2(cx - ew / 2.0, r.position.y + (34.0 if touch else 44.0)), en_s, 12, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, ea), 4.0)
	var title: String = str(pg.title) + ("（续）" if v.cont else "")
	var tsz := 26 if touch else 30
	UI.heading(g.hud, g.font, Vector2(cx, r.position.y + (66.0 if touch else 84.0)), title, tsz, UI.TEXT, minf(300.0, r.size.x / 2.0 - 40.0))
	var pn := "%02d / %02d" % [g.intro_page + 1, vw.size()]
	g.hud.draw_string(UI.latin(true), Vector2(r.end.x - (24.0 if touch else 36.0) - 120.0, r.position.y + (34.0 if touch else 44.0)), pn, HORIZONTAL_ALIGNMENT_RIGHT, 120.0, UI.fs(13), Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, ea))
	# 左栏：线框示意
	var fr: Rect2 = L.fr
	fr.position.y += dy
	g.hud.draw_rect(fr, Color(1, 1, 1, 0.025 * ea))
	g.hud.draw_rect(fr, Color(1, 1, 1, 0.07 * ea), false, 1.0)
	_s = clampf(minf(fr.size.x / 290.0, fr.size.y / 290.0), 0.72, 1.15)
	_c = fr.get_center()
	draw_icon(pg.icon, _c)
	# 右栏：「标签｜正文」，整块在正文栏里上下居中
	var fsz: int = L.fsz
	var lhh: float = v.lhh
	var asc: float = g.font.get_ascent(UI.fs(fsz))
	var lbl_w: float = v.lbl_w
	var tx: float = L.tx
	var tw: float = L.tw
	var y: float = L.top + maxf(0.0, (L.bot - L.top - v.h) / 2.0) + dy
	var la: float = g.font.get_ascent(UI.fs(L.lsz))
	var lh: float = g.font.get_height(UI.fs(L.lsz))
	for ri in v.rows.size():
		var row: Dictionary = v.rows[ri]
		if ri > 0:
			g.hud.draw_line(Vector2(tx, y - L.gap / 2.0), Vector2(tx + tw, y - L.gap / 2.0), Color(1, 1, 1, 0.07 * ea), 1.0)
		var bx := tx
		var body_col := Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, ea)
		if row.label != "":
			var ly := y + (lhh - lh) / 2.0
			g.hud.draw_rect(Rect2(tx, ly + 2.0, 2.0, lh - 4.0), Color(1, 1, 1, 0.75 * ea))
			g.hud.draw_string(g.font, Vector2(tx + 10.0, ly + la), row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(L.lsz), Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, ea))
			bx += lbl_w
		else:
			body_col = Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, ea)
		var yy := y
		for ln2 in row.lines:
			g.hud.draw_string(g.font, Vector2(bx, yy + asc), ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), body_col)
			yy += lhh
		y += row.h + L.gap
	# 底栏：上一页 ｜ 页码点 ｜ 跳过 · 下一页（全在面板里）
	g.intro_panel = r
	g.intro_dots.clear()
	var mp: Vector2 = g.hud.get_local_mouse_position()
	var bh := 48.0 if touch else 38.0
	var by: float = L.bar_y
	var pad := 24.0 if touch else 36.0
	var last: bool = g.intro_page == vw.size() - 1
	var w_prev := 150.0 if touch else 132.0
	var w_skip := 120.0 if touch else 104.0
	var w_next := 170.0 if touch else 152.0
	var b_prev := Rect2(r.position.x + pad, by, w_prev, bh)
	var b_next := Rect2(r.end.x - pad - w_next, by, w_next, bh)
	var b_skip := Rect2(b_next.position.x - 12.0 - w_skip, by, w_skip, bh)
	var defs := [[b_prev, "‹ 上一页", Pad.hint("←", "LB"), g.intro_page == 0], [b_skip, "跳过", Pad.hint("ESC", "Ⓑ"), false],
		[b_next, "开始探索 ›" if last else "下一页 ›", Pad.hint("→", "RB"), false]]
	for k in 3:
		var br: Rect2 = defs[k][0]
		var hit: Rect2 = br.grow_individual(6, 12, 6, 12) if Pad.touch_ui() else br
		match k:
			0: g.intro_btn_prev = hit
			1: g.intro_btn_skip = hit
			2: g.intro_btn_next = hit
		var dim: bool = defs[k][3]
		var hov: bool = br.has_point(mp) and not dim and not Pad.touch_ui()
		if hov:
			g.hud.draw_rect(br, UI.CYAN)
		else:
			g.hud.draw_rect(br, Color(1, 1, 1, 0.04))
			g.hud.draw_rect(br, Color(1, 1, 1, 0.12 if dim else 0.28), false, 1.0)
		var ink: Color = Color(0.04, 0.07, 0.09) if hov else (Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, 0.5) if dim else UI.TEXT)
		var bsz := 18 if touch else 14
		var key: String = "" if Pad.touch_ui() else str(defs[k][2])
		if key == "":
			UI.text(g.hud, g.font, Vector2(br.position.x, br.position.y + bh / 2.0 + bsz * 0.36 * UI.fk), defs[k][1], bsz, ink, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		else:
			UI.text(g.hud, g.font, Vector2(br.position.x + 14.0, br.position.y + bh / 2.0 + bsz * 0.36), defs[k][1], bsz, ink)
			UI.keycap(g.hud, g.font, Vector2(br.end.x - UI.cwidth(g.font, key, 10) - 20.0, br.position.y + (bh - 17.0) / 2.0), key, ink, 10)
	# 页码点：在「上一页」与「跳过」之间居中，可点
	var n := vw.size()
	var step := 22.0 if touch else 20.0
	var dcx: float = (b_prev.end.x + b_skip.position.x) / 2.0
	for i in n:
		var dp := Vector2(dcx - (n - 1) * step / 2.0 + i * step, by + bh / 2.0)
		var dr := Rect2(dp - Vector2(step / 2.0, 14), Vector2(step, 28))
		g.intro_dots.append([dr, i])
		var hv: bool = dr.has_point(mp) and not Pad.touch_ui()
		var cur: bool = i == g.intro_page
		UI.diamond(g.hud, dp, 5.0 if cur or hv else 3.5, Color(1, 1, 1, 0.95) if cur else (Color(1, 1, 1, 0.5) if hv else Color(1, 1, 1, 0.2)))


# ---------------------------------------------------------------- 线框示意（左栏插图）
## 示意图坐标：以左栏中心为原点、约 ±140 的方框，按 _s 缩放（字号不缩）
func _p(x: float, y: float) -> Vector2:
	return _c + Vector2(x, y) * _s


## 示意图里的小字：x 为中心（align 居中）或左端
func _lbl(x: float, y: float, s: String, col := UI.SUB, size := 13, center := true) -> void:
	if center:
		UI.text(g.hud, g.font, _p(x, y) - Vector2(80, 0), s, size, col, HORIZONTAL_ALIGNMENT_CENTER, 160)
	else:
		UI.text(g.hud, g.font, _p(x, y), s, size, col)


func _ring(c: Vector2, rad: float, col: Color, w := 1.5) -> void:
	g.hud.draw_arc(c, rad, 0.0, TAU, 64, col, w, true)


## 圆环扇区（指挥圆盘示意）
func _sector(c: Vector2, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, i / 12.0)) * r1)
	for i in 13:
		pts.append(c + Vector2.from_angle(lerpf(a1, a0, i / 12.0)) * r0)
	return pts


## 触屏版「操作」页插图：小手机框，左半屏虚拟摇杆 + 右下冲刺键 / 技能键（和局内 touch.gd 同一布局）
func _draw_touch_keys() -> void:
	var fr := Rect2(_p(-130, -78), Vector2(260, 156) * _s)
	g.hud.draw_rect(fr, FILL)
	g.hud.draw_rect(fr, INK2, false, 1.5)
	g.hud.draw_line(_p(0, -72), _p(0, 72), Color(1, 1, 1, 0.12), 1.0)
	var so := _p(-66, 0)
	g.hud.draw_circle(so, 36.0 * _s, Color(1, 1, 1, 0.04))
	_ring(so, 36.0 * _s, INK2, 2.0)
	var knob := so + Vector2(cos(g.intro_t * 1.6), sin(g.intro_t * 1.6)) * 20.0 * _s
	g.hud.draw_circle(knob, 13.0 * _s, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.3))
	_ring(knob, 13.0 * _s, UI.CYAN, 2.0)
	var dc := _p(84, 34)
	g.hud.draw_circle(dc, 24.0 * _s, Color(1, 1, 1, 0.05))
	_ring(dc, 24.0 * _s, INK, 2.0)
	UI.text(g.hud, g.font, dc + Vector2(-40, 5), "冲刺", 13, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80)
	var sc := _p(32, -22)
	var pulse: float = 0.5 + 0.5 * sin(g.intro_t * 4.0)
	g.hud.draw_circle(sc, 20.0 * _s, Color(1, 1, 1, 0.05))
	_ring(sc, 20.0 * _s, INK, 2.0)
	_ring(sc, (24.0 + 2.0 * pulse) * _s, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.3 + 0.5 * pulse), 2.0)
	UI.text(g.hud, g.font, sc + Vector2(-40, 5), "技能", 13, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80)
	_lbl(-66, 108, "左半屏拖动")
	_lbl(62, 108, "轻点自动瞄准")
	_lbl(62, 128, "按住拖方向")


func draw_icon(kind: String, _c0: Vector2) -> void:
	match kind:
		"bars":
			# 生命 / 灯火两条（灯火 30、70 两道刻度）+ 照亮圈随灯火变化 + 一片溟痕
			var lamp_k: float = 0.5 + 0.22 * sin(g.intro_t * 1.1)
			var x0 := -120.0
			var bw := 240.0
			_lbl(x0, -104, "生命", UI.SUB, 13, false)
			g.hud.draw_rect(Rect2(_p(x0, -96), Vector2(bw, 4) * Vector2(_s, 1)), Color(1, 1, 1, 0.12))
			g.hud.draw_rect(Rect2(_p(x0, -96), Vector2(bw * 0.72, 4) * Vector2(_s, 1)), INK)
			_lbl(x0, -62, "灯火", UI.GOLD, 13, false)
			g.hud.draw_rect(Rect2(_p(x0, -54), Vector2(bw, 8) * Vector2(_s, 1)), Color(0, 0, 0, 0.5))
			g.hud.draw_rect(Rect2(_p(x0, -54), Vector2(bw, 8) * Vector2(_s, 1)), INK2, false, 1.0)
			g.hud.draw_rect(Rect2(_p(x0, -54), Vector2(bw * lamp_k, 8) * Vector2(_s, 1)), UI.GOLD)
			for tv in [0.3, 0.7]:
				var tx2: float = x0 + bw * tv
				g.hud.draw_line(_p(tx2, -59), _p(tx2, -41), Color(1, 1, 1, 0.75), 1.5)
				_lbl(tx2, -24, str(int(tv * 100)), UI.SUB, 12)
			var lc := _p(-34, 66)
			var rad: float = (30.0 + 40.0 * lamp_k) * _s
			g.hud.draw_circle(lc, rad, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.08))
			_ring(lc, rad, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.7))
			UI.diamond(g.hud, lc, 6.0, INK)
			UI.text(g.hud, g.font, lc + Vector2(-40, -rad - 8.0), "照亮", 13, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var mire := UI.blob(_p(86, 82), 30.0 * _s, rng, 0.28, 18)
			g.hud.draw_colored_polygon(mire, Color(UI.VIOLET.r * 0.5, UI.VIOLET.g * 0.4, UI.VIOLET.b * 0.6, 0.55))
			mire.append(mire[0])
			g.hud.draw_polyline(mire, Color(UI.VIOLET.r, UI.VIOLET.g, UI.VIOLET.b, 0.75), 1.5, true)
			_lbl(86, 136, "溟痕")
		"command":
			# 指挥圆盘：四个扇区（上半随行 / 突击，下半集火 / 部署），每 1.4 秒轮流亮一项；集火亮洋红
			var cc := _p(0, -6)
			var r0 := 34.0 * _s
			var r1 := 100.0 * _s
			var names := ["随行", "突击", "部署", "集火"]
			var hov: int = int(g.intro_t / 1.4) % 4
			for i in 60:
				var d := Vector2.from_angle(TAU * i / 60.0)
				g.hud.draw_line(cc + d * (r1 + 5.0), cc + d * (r1 + (10.0 if i % 15 == 0 else 7.0)), Color(1, 1, 1, 0.35 if i % 15 == 0 else 0.15), 1.0)
			for i in 4:
				var a0: float = PI + i * PI / 2.0 + 0.04
				var a1: float = PI + (i + 1) * PI / 2.0 - 0.04
				var sec := _sector(cc, r0, r1, a0, a1)
				var acc: Color = UI.RED if i == 3 else UI.CYAN
				g.hud.draw_colored_polygon(sec, Color(acc.r, acc.g, acc.b, 0.22) if i == hov else FILL)
				sec.append(sec[0])
				g.hud.draw_polyline(sec, acc if i == hov else INK2, 1.5 if i == hov else 1.0, true)
				var mc := cc + Vector2.from_angle((a0 + a1) / 2.0) * (r0 + r1) / 2.0
				UI.text(g.hud, g.font, mc + Vector2(-40, 5), names[i], 14, UI.TEXT if i == hov else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 80)
			_ring(cc, r0 - 6.0 * _s, INK2)
			UI.text(g.hud, g.font, cc + Vector2(-40, 5), "指挥", 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 80)
			_lbl(0, 136, "指挥圆盘")
		"console":
			# 指挥台：中间队长头像 + 终结技环，左边生命 / 灯火 / 冲刺，右边两名队友 + 指令牌
			var ek: float = fmod(g.intro_t * 0.25, 1.0)
			var ac := _p(0, -16)
			g.hud.draw_circle(ac, 26.0 * _s, Color(0.05, 0.08, 0.1))
			_ring(ac, 31.0 * _s, Color(1, 1, 1, 0.2), 3.0)
			g.hud.draw_arc(ac, 31.0 * _s, -PI / 2.0, -PI / 2.0 + TAU * ek, 40, UI.CYAN if ek > 0.97 else INK, 3.0, true)
			_lbl(0, 34, "终结技")
			var lx0 := -132.0
			var lx1 := -48.0
			_lbl(lx0, -36, "生命", UI.SUB, 12, false)
			g.hud.draw_rect(Rect2(_p(lx0, -26), Vector2((lx1 - lx0) * _s, 3.0)), INK)
			_lbl(lx0, -6, "灯火", UI.GOLD, 12, false)
			var bx := lx0 + 30.0
			var lamp_k: float = 0.55 + 0.25 * sin(g.intro_t * 1.3)
			g.hud.draw_rect(Rect2(_p(bx, -14), Vector2((lx1 - bx) * _s, 7.0)), Color(0, 0, 0, 0.55))
			g.hud.draw_rect(Rect2(_p(lx1 - (lx1 - bx) * lamp_k, -13), Vector2((lx1 - bx) * lamp_k * _s, 5.0)), UI.GOLD)
			for tv in [0.3, 0.7]:
				var tx4: float = lx1 - (lx1 - bx) * tv
				g.hud.draw_line(_p(tx4, -16), _p(tx4, -5), Color(1, 1, 1, 0.6), 1.0)
			_lbl(lx1 - 34, 22, "冲刺", UI.SUB, 12, false)
			for q in 2:
				var px := _p(lx1 - 50 - q * 11, 16)
				g.hud.draw_colored_polygon(PackedVector2Array([px + Vector2(0, -4), px + Vector2(4, -4), px + Vector2(8, 0), px + Vector2(4, 4), px + Vector2(0, 4), px + Vector2(4, 0)]), UI.CYAN if q == 0 else Color(1, 1, 1, 0.2))
			for q in 2:
				var tr4 := Rect2(_p(46 + q * 32, -30), Vector2(26, 26) * _s)
				g.hud.draw_rect(tr4, FILL)
				g.hud.draw_rect(tr4, INK2, false, 1.0)
				g.hud.draw_rect(Rect2(tr4.position + Vector2(0, 30 * _s), Vector2(26 * _s * (0.9 - q * 0.4), 2.0)), INK)
			_lbl(75, 22, "队友")
			var cr4 := Rect2(_p(112, -30), Vector2(26, 26) * _s)
			g.hud.draw_rect(cr4, FILL)
			g.hud.draw_rect(cr4, UI.CYAN, false, 1.0)
			_lbl(125, 22, "指令")
			# 屏幕示意：外框 + 台子在正下方
			var sr := Rect2(_p(-110, 66), Vector2(220, 64) * _s)
			g.hud.draw_rect(sr, INK2, false, 1.0)
			g.hud.draw_rect(Rect2(_p(-30, 118), Vector2(60, 8) * _s), INK)
			_lbl(0, 100, "屏幕正下方")
		"merchant":
			# 屏幕框 + 边缘金色箭头指向商人；倒计时环 + 2:00 / 5:00 / 8:00 时间轴
			var sr := Rect2(_p(-120, -126), Vector2(240, 120) * _s)
			g.hud.draw_rect(sr, FILL)
			g.hud.draw_rect(sr, INK2, false, 1.0)
			UI.diamond(g.hud, _p(0, -66), 6.0, INK)
			var bob: float = 4.0 * sin(g.intro_t * 4.0)
			var ap := _p(106 + bob / _s, -66)
			g.hud.draw_colored_polygon(PackedVector2Array([ap + Vector2(8, 0) * _s, ap + Vector2(-6, -9) * _s, ap + Vector2(-2, 0) * _s, ap + Vector2(-6, 9) * _s]), UI.GOLD)
			_lbl(60, -98, "商人方向", UI.GOLD, 12)
			var left: int = 60 - int(fmod(g.intro_t * 6.0, 60.0))
			var mc: Color = UI.GOLD if left > 15 else UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(g.intro_t * 8.0))
			UI.ring(g.hud, _p(-82, 34), 22.0 * _s, left / 60.0, mc)
			UI.text(g.hud, g.font, _p(-82, 34) + Vector2(-30, 6), "%ds" % left, 14, mc, HORIZONTAL_ALIGNMENT_CENTER, 60)
			var t0 := -36.0
			var t1 := 124.0
			g.hud.draw_line(_p(t0, 34), _p(t1, 34), INK2, 1.5)
			for k in 3:
				var xm: float = t0 + (t1 - t0) * [0.2, 0.5, 0.8][k]
				UI.diamond(g.hud, _p(xm, 34), 5.0, UI.GOLD)
				_lbl(xm, 60, ["2:00", "5:00", "8:00"][k], UI.GOLD, 12)
			_lbl(0, 112, "商人  ·  停留 60 秒")
		"nodes":
			# 三张背面朝上的节点卡：中间「不期而遇」每 1.6 秒抬起一次；下面四个结局菱形
			for k in 3:
				var up: float = 10.0 * maxf(0.0, sin(g.intro_t * 3.9)) if k == 1 else 0.0
				var cr := Rect2(_p(-100 + k * 76 - 28, -98 - up), Vector2(56, 82) * _s)
				g.hud.draw_rect(cr, FILL if k != 1 else Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.1))
				g.hud.draw_rect(cr, UI.CYAN if k == 1 else INK2, false, 1.5 if k == 1 else 1.0)
				if k == 1:
					UI.text(g.hud, g.font, cr.get_center() + Vector2(-20, 9), "?", 24, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 40)
				else:
					UI.diamond(g.hud, cr.get_center(), 9.0 * _s, Color(0, 0, 0, 0), INK2)
			_lbl(0, 6, "不期而遇", UI.CYAN, 12)
			for k in 4:
				var ec: Color = g.endg.ending_col(["standard", "knight", "deep", "resolve"][k])
				var dc := _p(-75 + k * 50, 66)
				UI.diamond(g.hud, dc, 10.0 * _s, Color(ec.r, ec.g, ec.b, 0.3), ec)
				UI.text(g.hud, g.font, dc + Vector2(-20, 32 * _s), ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"][k], 13, ec, HORIZONTAL_ALIGNMENT_CENTER, 40)
			_lbl(0, 130, "四个结局")
		"keys":
			if Pad.touch_ui():
				_draw_touch_keys()
				return
			var keys := [["W", 0, -100, 1], ["A", -44, -56, 1], ["S", 0, -56, 1], ["D", 44, -56, 1], ["SPACE", 0, -6, 3],
				["F", -84, 44, 1], ["Q", -40, 44, 1], ["TAB", 12, 44, 1.5], ["ESC", 74, 44, 1.5]]
			for kk in keys:
				var kw: float = 38.0 * float(kk[3]) + 6.0 * (float(kk[3]) - 1.0)
				var kr := Rect2(_p(float(kk[1]), float(kk[2])) - Vector2(kw, 38.0) * _s / 2.0, Vector2(kw, 38.0) * _s)
				g.hud.draw_rect(kr, FILL)
				g.hud.draw_rect(kr, Color(1, 1, 1, 0.5), false, 1.0)
				UI.text(g.hud, g.font, Vector2(kr.position.x, kr.get_center().y + 5), kk[0], 13, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
			_lbl(0, 112, "键盘")


## 指南正文里的数值占位（docs/83 入队加成读 balance.json squad 段；docs/88 灯火暗淡 / 受击灯火读 lamp 段、暗淡刷新读 enemy 段；不写死）。
## 缺省值与读取处一致：combat.gd（lamp/dark_taken、hit_base、hit_scale）、enemies.gd（lamp/dark_enemy）、spawner.gd（enemy/spawn_dark_mult）
## 10-24 增补：灯标（run/beacon.gd）、宝箱 / 补给箱（combat.gd、docs/133）、指挥与切换队长（docs/114、135）
static func fill_numbers(ln: String) -> String:
	if not ln.contains("{"):
		return ln
	var Bal = preload("res://scripts/core/balance.gd")
	var Sq = preload("res://scripts/characters/squad.gd")
	var pct := func(mult: float) -> String: return str(int(round((mult - 1.0) * 100.0)))
	var pc100 := func(key: String, dflt: float) -> String: return str(int(round(Bal.v(key, dflt) * 100.0)))
	var vals := {
		"{hp_per_member}": str(int(round(Bal.v("squad/hp_per_member", 0.15) * 100.0))), "{regen_per_member}": Sq.regen_steps_text(),
		"{dark_taken}": pct.call(Bal.v("lamp/dark_taken", 1.05)), "{dark_enemy}": pct.call(Bal.v("lamp/dark_enemy", 1.1)),
		"{dark_spawn}": pct.call(Bal.v("enemy/spawn_dark_mult", 1.15)),
		"{lamp_hit_10}": Sq._num(Bal.v("lamp/hit_scale", 18.0) * 0.1), "{lamp_hit}": Sq._num(Bal.v("lamp/hit_base", 2.0)),
		"{beacon_need}": Sq._num(Bal.v("beacon/need", 2.5)), "{beacon_lamp}": Sq._num(Bal.v("beacon/lamp", 20.0)), "{beacon_block}": Sq._num(Bal.v("beacon/block_t", 30.0)),
		"{elite_chest}": pc100.call("relic/elite_drop_chance", 0.3),
		"{pack_p}": pc100.call("crate/pack_p", 0.9), "{pack_pct}": pc100.call("crate/pack_pct", 0.3), "{pack_below}": pc100.call("crate/pick_below", 0.9),
		"{crate_magnet}": pc100.call("crate/magnet_p", 0.1), "{crate_shield}": pc100.call("crate/shield_p", 0.1),
		"{cmd_stamina}": Sq._num(Bal.v("command/stamina_secs", 25.0)), "{cmd_min}": pc100.call("command/min_start", 0.3),
		"{cmd_revive}": Sq._num(Bal.v("command/revive_secs", 25.0)),
		"{cmd_aspd}": str(roundi(Bal.v("command/rush_aspd", 0.25) * 100.0)), "{cmd_sp}": Sq._num(Bal.v("command/rush_sp", 1.5)),   # 指挥加成（11-05 用户「开局指南里在指挥模式的时候可以写上队友加成」）
		"{dash_cd}": Sq._num(Bal.v("dash/cd", 1.2)),   # 冲刺冷却（docs/284 §3：操作页单列「冲刺」行）
	}
	for k in vals:
		ln = ln.replace(k, vals[k])
	return ln
