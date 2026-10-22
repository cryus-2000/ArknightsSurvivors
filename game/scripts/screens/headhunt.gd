extends RefCounted
## 界面 · 寻访（局外成长 P1，docs/109 §12；表现层 docs/124 第三版 + docs/125 §6 定稿：10-22 用户以 GPT 寻访概念图 27–33 为准）。
## 规则（10-22 用户）：只有一种「寻访凭证」，每局结算 3 张、通关 4 张；寻访一次（随机 1 名）1 张，定向寻访（先选职业、再指定干员）2 张；没有意向与保底。
## 流程：结算面板出来后，有凭证就盖一层寻访入口 →（寻访一次 | 定向寻访 → 选职业 → 指定干员）→ 拉开作战包 → 光炸 → 揭示 → 本次寻访 → 回入口（凭证用完或名册满则关）。
## 视觉：hh_style.gd（左白右黑斜切、像素描边英文、职业色斜卡、青色主按钮）；版面按 1280×720 设计、等比缩放居中。不配语音，只用现有音效（10-22 用户）。
## 抽取在 core/roster.gd，用独立随机数，不碰局内 g.rng；演出里的碎光 / 噪点用固定表。
## 动效用真实时间（测试录屏 clock_frames 时按帧数）；「减少动态效果」不拉包、揭示直接到名牌；无头批跑直接到本次寻访。
## 作战包 / 金光 / 碎光 / 流光：Codex 交付（codex/art 35587bca，tools/probes/package_headhunt_bag.py 接入）

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const A = preload("res://scripts/art.gd")
const HS = preload("res://scripts/screens/hh_style.gd")
const Character = preload("res://scripts/characters/character.gd")
const Roster = preload("res://scripts/core/roster.gd")
const Game = preload("res://scripts/game.gd")

const DESK := Vector2(1280, 720)   # 桌面设计稿尺寸
var D := DESK                      # 当前版面：手机横屏按屏幕比例取 1280 ×（600–720），纵向位置用 _p() 单独排（docs/124 §13.7）
var _phone := false
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
const CLASS_EN := {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER", "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}
## 光炸色：拉包光效只有金一档（10-22 用户：全部用 Codex 原图，金 / 青白两档作废，docs/124 §9.3）
const BURST_COL := Color8(255, 196, 80)
## 作战包时间轴（秒）：落下 0–0.4，拉链 0.4–1.6（8 档，每档 0.17 秒，同 Codex manifest.opening），全开后光柱循环约 0.6 秒，光炸 2.05–2.5
const BAG_T := 2.5
const ZIP0 := 0.4
const ZIP1 := 1.6
const ZIP_STEP := 0.17
const BURST := 2.15
## 每名干员一屏：名牌滑入 0–0.4，立绘滑入 0–0.5，解码 0.5–1.2，新加入签 1.3，5 秒自动下一名（协调人缺省：每人 5 秒可跳过）
const SLIDE := 0.5
const DECODE := 1.2
const PLATE := 1.6
const STAMP := 1.3
const OP_T := 5.0
## Codex 交付的包体（playback_contract.json，@2x 像素）：拉链 8 档帧条，原点 = 底边中点
const BAG_O := Vector2(128, 148)
const BAG_SZ := Vector2(256, 152)
## Codex 光效回归（main 9444db06，reference_return/manifest.json）：主光柱 + 上冲碎光各 24 帧 384×400、12 fps，原点 (192,350)，
## 固定放置 = 包左上 + (128,66) − 原点；层序 合并光层（乘开包遮罩）→ 包底层 → 光层裁片 (64,78,256,320) 乘全开口遮罩 → 包前景
const FX_SZ := Vector2(384, 400)
const FX_AT := Vector2(128, 66) - Vector2(192, 350)
const FX_CROP := Rect2i(64, 78, 256, 320)

static var clock_frames := false   # 测试录屏：按渲染帧计时（--fixed-fps 下与画面同步）

## 转场（docs/124 §12）：enter = 从结算进入（最重，PV 感）/ slide = 屏间横移（轻）/ cut = 硬切白闪（进拉包）/ wipe = 斜向遮罩擦除（揭示 → 本次寻访）。
## 全部 ≤ 0.6 秒；点按 / 任意键跳过；减少动态效果与无头直接切
const TR_DUR := {"enter": 0.6, "slide": 0.3, "cut": 0.15, "wipe": 0.4}

var g: Game
var open := false
var mode := "entry"       # entry 入口 / class 定向选职业 / pick 定向选干员 / bag 拉包 / op 揭示 / summary 本次寻访
var results: Array = []   # Roster.redeem_* 的返回值（只留解出干员的）
var idx := 0              # 揭示到第几名
var t0 := 0.0             # 当前段开始时刻
var _zip_ticks := 0
var _burst := false
var _stamped := -1
var reveal_id := ""       # 当前揭示的干员（测试输出用）
var sel := 0              # 入口：0 寻访一次 / 1 定向；选职业 / 选干员：格子下标
var sel_cls := ""
var choices: Array = []   # 选职业：职业；选干员：干员 id
var rects: Array = []     # [Rect2（设计坐标）, 动作]
var _k := 1.0             # 设计 → 界面单位
var _off := Vector2.ZERO
var _od := {}
var _img := {}            # 金光遮罩合成用的原图缓存
var _glow := {}           # [档, 帧, 拉链档] → 裁好的金光贴图
var _tr := ""             # 当前转场（"" = 没有）
var _tr_t0 := 0.0
var _tr_cut := false      # enter 的硬切音效是否已放
var _mode_t0 := 0.0       # 进入当前屏的时刻（各屏招牌动效用）


func _init(game: Game) -> void:
	g = game


func _now() -> float:
	if clock_frames:
		return Engine.get_process_frames() / 60.0
	return Time.get_ticks_msec() / 1000.0


func _vouchers() -> int:
	return int(Cfg.roster_tickets.get(Roster.T_HUNT, 0))


# ---- 规则接口适配（10-22：券规则由局外成长会话改 roster.gd，这里只读接口；合入时由协调人对接）
# 新接口（claude/difficulty-3tiers b9e1d6bc）：RUN_TICKETS / WIN_BONUS / COST_RANDOM / COST_PICK、redeem_random()、redeem_pick(id) 花 COST_PICK 张、
# migrate_tickets()、spill_to_cells()。旧接口（main）没有这些时：随机走 redeem_hunt，定向走 redeem_pick（人事调度函），满员走 spill_to_spare
func _rule(name: String, dflt: int) -> int:
	return int((Roster as GDScript).get_script_constant_map().get(name, dflt))


func _roster_has(fn: String) -> bool:
	for m in (Roster as GDScript).get_script_method_list():
		if m.name == fn:
			return true
	return false


func _rcall(fn: String, args := []) -> Variant:
	return (Roster as GDScript).callv(fn, args)


func _new_rules() -> bool:
	return _roster_has("redeem_random")


func _cost_pick() -> int:
	return _rule("COST_PICK", 2)


func _per_run() -> int:
	return _rule("RUN_TICKETS", 3)


func _per_clear() -> int:
	return _rule("RUN_TICKETS", 3) + _rule("WIN_BONUS", 1)


func _redeem_random() -> Dictionary:
	return _rcall("redeem_random") if _new_rules() else _rcall("redeem_hunt")


func _redeem_directed(cid: String) -> Dictionary:
	return Roster.redeem_pick(cid)


func _can_random() -> bool:
	return _vouchers() >= _rule("COST_RANDOM", 1)


func _can_direct() -> bool:
	if _new_rules():
		return _vouchers() >= _cost_pick()
	return int(Cfg.roster_tickets.get("pick", 0)) > 0


func _spill() -> void:
	if _roster_has("spill_to_cells"):
		_rcall("spill_to_cells")
	elif _roster_has("spill_to_spare"):
		_rcall("spill_to_spare")


## 结算画出来时调（hud.gd）：有寻访凭证就打开入口
func maybe_open() -> void:
	if open or not Roster.active():
		return
	if _roster_has("migrate_tickets"):
		(Roster as GDScript).call("migrate_tickets")
	if not _can_random() and not _can_direct():
		return
	if Roster.locked_ids().is_empty():
		_spill()
		return
	open = true
	_entry()
	_trans("enter")


func _entry() -> void:
	results.clear()
	if (not _can_random() and not _can_direct()) or Roster.locked_ids().is_empty():
		if Roster.locked_ids().is_empty():
			_spill()
		open = false
		return
	mode = "entry"
	sel = 0
	t0 = _now()
	_mode_t0 = t0


func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var ca := CLASS_ORDER.find(Roster.class_of(a))
		var cb := CLASS_ORDER.find(Roster.class_of(b))
		return ca < cb if ca != cb else a < b)
	return out


func _play() -> void:
	idx = 0
	_stamped = -1
	if results.is_empty():
		_entry()
		return
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
	_trans("cut")


func _op(i: int) -> void:
	idx = i
	mode = "op"
	reveal_id = results[i].id
	t0 = _now() - (PLATE if UM.rm() else 0.0)


func _summary() -> void:
	if mode in ["op", "bag"]:
		_trans("wipe")
	mode = "summary"
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
	Sfx.play("beacon_lit")
	Sfx.play("levelup", -2.0)


func _act(a) -> void:
	match mode:
		"entry":
			if a is int:
				sel = a
				a = "one" if a == 0 else "directed"
			if a == "one" and _can_random():
				Sfx.play("ui_ok")
				var r := _redeem_random()
				if str(r.get("id", "")) != "":
					results = [r]
				_play()
			elif a == "directed" and _can_direct():
				Sfx.play("ui_ok")
				mode = "class"
				_trans("slide")
				var lc := Roster.locked_classes()
				choices = CLASS_ORDER.duplicate()
				sel = 0
				for i in choices.size():
					if lc.has(choices[i]):
						sel = i
						break
			elif a == "back":
				Sfx.play("ui_ok")
				open = false
		"class":
			if a is int and a >= 0 and a < choices.size():
				if not Roster.locked_classes().has(choices[a]):
					return
				var again: bool = sel == a or Pad.touch
				sel = a
				Sfx.play("ui_move")
				if not again:
					return
				a = "ok"
			if a == "ok" and Roster.locked_classes().has(choices[sel]):
				Sfx.play("ui_ok")
				sel_cls = choices[sel]
				choices = _sorted(Roster.locked_ids().filter(func(c): return Roster.class_of(c) == sel_cls))
				sel = 0
				mode = "pick"
				_trans("slide")
			elif a == "back":
				Sfx.play("ui_ok")
				mode = "entry"
				sel = 1
				_trans("slide")
		"pick":
			if a is int and a >= 0 and a < choices.size():
				if sel != a:
					_mode_t0 = _now()   # 换人：档案重新解码
				sel = a
				Sfx.play("ui_move")
				return
			if a == "ok" and sel < choices.size():
				Sfx.play("ui_ok")
				var r := _redeem_directed(choices[sel])
				if str(r.get("id", "")) != "":
					results = [r]
				_play()
			elif a == "back":
				Sfx.play("ui_ok")
				mode = "class"
				choices = CLASS_ORDER.duplicate()
				sel = maxi(0, choices.find(sel_cls))
				_trans("slide")
		"bag", "op":
			if a == "skip":
				Sfx.play("ui_ok")
				_summary()
			elif a == "ok":
				_tap()
		"summary":
			if a == "ok":
				Sfx.play("ui_ok")
				_entry()
				if open:
					_trans("slide")


## 输入（game.gd _unhandled_input 在寻访打开时整段交给这里）；返回是否用掉了这次输入
func input(event: InputEvent) -> bool:
	if _tr != "" and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_tr = ""   # 转场中任意键 / 点按：直接到位，这次输入不再往下传
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (event.position / Cfg.ui_k - _off) / _k
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
			_act(("one" if sel == 0 else "directed") if mode == "entry" else "ok")
		elif k == KEY_ESCAPE:
			_act("skip" if mode in ["bag", "op"] else "back")
		elif k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S]:
			var d: int = {KEY_LEFT: -1, KEY_A: -1, KEY_RIGHT: 1, KEY_D: 1, KEY_UP: -4, KEY_W: -4, KEY_DOWN: 4, KEY_S: 4}[k]
			if mode == "entry":
				sel = clampi(sel - signi(d), 0, 1)
			elif mode == "class":
				var n := sel
				for _i in 8:
					n = clampi(n + (d if absi(d) == 4 else signi(d)), 0, choices.size() - 1)
					if Roster.locked_classes().has(choices[n]):
						sel = n
						break
					if absi(d) == 4:
						d = signi(d)
			elif mode == "pick":
				sel = clampi(sel + signi(d), 0, maxi(0, choices.size() - 1))
			g.kb_nav = true
			Sfx.play("ui_move")
		return true
	return event is InputEventMouseButton or event is InputEventScreenTouch


## 干员资料（同选人页的取法，缓存）
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
		"en": str(d.get("en", cid)).to_upper(), "durs": durs, "def": d}
	_od[cid] = od
	return od


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


## 立绘（k2 = 每个 @2x 像素的设计单位，再乘 draw_scale）：脚底点 foot；sil = 剪影色；返回目标矩形
func _figure(od: Dictionary, foot: Vector2, k2: float, sil := Color(0, 0, 0, 0), frame := 0, clip := Rect2()) -> Rect2:
	var tx: Texture2D = od.tex
	if tx == null:
		return Rect2()
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	var kk: float = k2 * 2.0 / hi * float(od.ds)
	var dst := Rect2(UI.foot_pos(foot, bb, fw, tx.get_height(), hi, kk).round(), (bb.size * kk).round())
	var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var t2: Texture2D = A.white_of(tx) if sil.a > 0.0 else tx
	var c2 := sil if sil.a > 0.0 else Color.WHITE
	if clip.size.x > 0.0:
		UI.blit_clipped(g.hud, t2, dst, src, clip, c2)
	else:
		g.hud.draw_texture_rect_region(t2, dst, src, c2)
	return dst


func _btn(r: Rect2, act) -> void:
	rects.append([r, act])


func draw(vs: Vector2) -> void:
	rects.clear()
	var ci: CanvasItem = g.hud
	_phone = Pad.touch
	D = Vector2(1280, clampf(roundf(1280.0 * vs.y / vs.x), 600.0, 720.0)) if _phone else DESK
	_k = minf(vs.x / D.x, vs.y / D.y)
	_off = ((vs - D * _k) / 2.0).round()
	ci.draw_rect(Rect2(Vector2.ZERO, vs), HS.DARK)
	var k0 := _k
	var off0 := _off
	var p := _tr_p()
	HS.glitch_seed = Engine.get_process_frames() / 3
	HS.reveal = 1.0
	if _tr == "enter":   # 镜头轻推 1.06 → 1 + 文字解码
		var sc := lerpf(1.06, 1.0, UM.out_cubic(p))
		_k = k0 * sc
		_off = off0 + D * k0 * (1.0 - sc) / 2.0
		HS.reveal = clampf((p * 0.6 - 0.15) / 0.4, 0.0, 1.0)
	elif _tr == "slide":   # 内容自右横移 60 + 文字逐字出现
		var e := UM.out_cubic(p)
		_off.x += (1.0 - e) * 60.0 * k0
		HS.reveal = e
	ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	if mode == "bag":
		_draw_bag()
	elif mode == "op":
		_draw_op()
	else:
		HS.backdrop(ci, D)
		match mode:
			"entry":
				_draw_entry()
			"class":
				_draw_class()
			"pick":
				_draw_pick()
			"summary":
				_draw_summary()
	HS.reveal = 1.0
	_k = k0
	_off = off0
	ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	_draw_trans(p)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _trans(kind: String) -> void:
	if UM.rm() or UM.skip_all():
		_tr = ""
		return
	_tr = kind
	_tr_t0 = _now()
	_tr_cut = false
	_mode_t0 = _tr_t0
	match kind:
		"enter":
			Sfx.play("dodge", -4.0, 0.8)
		"slide":
			Sfx.play("dodge", -12.0, 1.4)
		"wipe":
			Sfx.play("dodge", -8.0, 1.1)


## 转场进度 0–1（没有转场 = 1；到时自动结束）
func _tr_p() -> float:
	if _tr == "":
		return 1.0
	var p := (_now() - _tr_t0) / float(TR_DUR[_tr])
	if p >= 1.0:
		_tr = ""
		return 1.0
	return p


## 转场叠层（画在整屏之上，设计坐标）
func _draw_trans(p: float) -> void:
	if _tr == "":
		return
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var full := Rect2(-_off / _k, D + _off * 2.0 / _k)
	var sk := D.y * 0.35   # 斜切量
	match _tr:
		"enter":
			var t := p * 0.6
			if t < 0.12:
				# ① 黑场 + 黄色斜切色块从左扫过（后面跟一道青细带）
				ci.draw_rect(full, Color(0.02, 0.025, 0.035))
				var x := lerpf(-500.0, D.x + 200.0, UM.in_out_cubic(t / 0.12))
				HS.fill(ci, PackedVector2Array([Vector2(x, 0), Vector2(x + 260, 0), Vector2(x + 260 - sk, D.y), Vector2(x - sk, D.y)]), HS.RIB)
				HS.fill(ci, PackedVector2Array([Vector2(x - 40, 0), Vector2(x - 30, 0), Vector2(x - 30 - sk, D.y), Vector2(x - 40 - sk, D.y)]), HS.CYB)
				HS.spaced(ci, f, Vector2(60, D.y / 2.0), "RHODES ISLAND  //  PERSONNEL", 14, Color(1, 1, 1, 0.8), 6.0)
				return
			if not _tr_cut:
				_tr_cut = true
				Sfx.play("crit_tick", -2.0)
			# ② 硬切 + 白闪（2 帧量级）
			var fl := 1.0 - (t - 0.12) / 0.08
			if fl > 0.0:
				ci.draw_rect(full, UI.fa(Color.WHITE, fl * 0.85))
			# ③ 斜向遮罩从左往右擦除（黄 + 青边）
			var e := UM.in_out_cubic((t - 0.12) / 0.48)
			var ex := lerpf(-200.0, D.x + sk + 40.0, e)
			var rx := maxf(full.end.x, ex) + 1.0   # 遮罩右边界跟着前沿出画面，避免前沿越过屏幕右缘时多边形自交
			HS.fill(ci, PackedVector2Array([Vector2(ex, 0), Vector2(rx, 0), Vector2(rx, D.y), Vector2(ex - sk, D.y)]), Color(0.02, 0.025, 0.035))
			HS.fill(ci, PackedVector2Array([Vector2(ex - 14, 0), Vector2(ex, 0), Vector2(ex - sk, D.y), Vector2(ex - sk - 14, D.y)]), HS.RIB)
			HS.fill(ci, PackedVector2Array([Vector2(ex - 30, 0), Vector2(ex - 26, 0), Vector2(ex - 26 - sk, D.y), Vector2(ex - 30 - sk, D.y)]), HS.CYB)
			# ④ 扫描线 + 噪点自上而下
			var sy := e * D.y
			ci.draw_rect(Rect2(0, sy, D.x, 2), UI.fa(Color.WHITE, 0.8))
			for c in 64:
				var hsh := absi(hash([c, HS.glitch_seed]))
				if hsh % 3 == 0:
					ci.draw_rect(Rect2(c * 20.0, sy + 4 + (hsh % 4) * 4, 12, 4), UI.fa(HS.CYB, 0.5))
			# ⑤ 右上角编号逐字打出
			HS.reveal = clampf((t - 0.12) / 0.4, 0.0, 1.0)
			HS.spaced(ci, f, Vector2(D.x - 470, 92), HS.dec("R.I. HR DEPT.  //  ACCESS GRANTED  //  01"), 10, HS.MUTE, 3.0)
			HS.reveal = 1.0
		"slide":
			var e := UM.out_cubic(p)
			ci.draw_rect(full, Color(0.02, 0.025, 0.035, (1.0 - e) * 0.55))
			var x := lerpf(-100.0, D.x + sk, e)
			HS.fill(ci, PackedVector2Array([Vector2(x, 0), Vector2(x + 4, 0), Vector2(x + 4 - sk, D.y), Vector2(x - sk, D.y)]), UI.fa(HS.CYB, 1.0 - e))
		"cut":
			ci.draw_rect(full, UI.fa(Color.WHITE, (1.0 - p) * 0.9))
		"wipe":
			var e := UM.in_out_cubic(p)
			var ex := lerpf(D.x + sk, -40.0, e)
			var lx := minf(full.position.x, ex - sk) - 1.0   # 同上：前沿越过屏幕左缘时左边界跟着走
			HS.fill(ci, PackedVector2Array([Vector2(lx, 0), Vector2(ex, 0), Vector2(ex - sk, D.y), Vector2(lx, D.y)]), Color(0.02, 0.025, 0.035))
			HS.fill(ci, PackedVector2Array([Vector2(ex, 0), Vector2(ex + 12, 0), Vector2(ex + 12 - sk, D.y), Vector2(ex - sk, D.y)]), HS.YEL)


## 纵向位置：桌面值 / 手机横屏值
func _p(desk: float, phone: float) -> float:
	return phone if _phone else desk


func _hot(i: int, r: Rect2) -> bool:
	if Pad.using or g.kb_nav:
		return sel == i
	return r.has_point((g.hud.get_local_mouse_position() - _off) / _k)


# ---------------------------------------------------------------- 入口（GPT 27）

func _draw_entry() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var n := _vouchers()
	var locked := Roster.locked_ids()
	HS.left_panel(ci, D, 470, 330, 62)
	_btn(HS.topbar(ci, f, D, ["PERSONNEL /", "RECRUITMENT"], "寻访"), "back")
	HS.title_block(ci, f, Vector2(36, _p(150, 116)), "01", "人事寻访", "寻访", "HEADHUNT", 1.0, int(_p(80, 64)))
	var vr := Rect2(36, _p(400, 320), 380, 76)
	ci.draw_rect(vr, Color(1, 1, 1, 0.55))
	ci.draw_rect(vr, Color(0, 0, 0, 0.25), false, 1.0)
	HS.voucher(ci, vr.position + Vector2(52, 38), 1.0)
	UI.text_at(ci, f, vr.position + Vector2(110, 38), "寻访凭证", 20, HS.INK, "lm", true)
	UI.text_at(ci, f, Vector2(vr.end.x - 20, vr.position.y + 38), "× %d" % n, 30, HS.INK, "rm", true)
	var rules := ["每次探索结算获得 %d 张，通关获得 %d 张" % [_per_run(), _per_clear()], "未解锁 %d 名 · 不会抽到重复干员" % locked.size()]
	if Cfg.roster_draws == 0:
		rules.append("首次寻访必定获得医疗干员")
	for j in rules.size():
		ci.draw_rect(Rect2(40, _p(506, 418) + j * 28, 6, 6), HS.INK)
		UI.text_at(ci, f, Vector2(56, _p(509, 421) + j * 28), rules[j], int(_p(14, 17)), HS.INK2, "lm")
	if not _phone:
		HS.hr_mark(ci, f, Vector2(40, 640))
	# 卡池：三组灰色像素剪影（未解锁的前 3 名 + 每组 4 名小剪影），缓慢视差
	HS.outline_px(ci, Vector2(560, _p(180, 130)), "PERSONNEL", 11.0, Color(1, 1, 1, 0.12), HS.DARK)
	var pool := _sorted(locked)
	var t := _now() - t0
	for i in mini(3, pool.size()):
		var cx := 690.0 + i * 250.0
		var big := i == 1
		var foot := Vector2(cx + (0.0 if UM.rm() else sin(t * 0.6 + i) * 6.0), _p(520.0, 430.0) if big else _p(500.0, 414.0))
		_figure(_card(pool[i]), foot, 4.0 if big else 3.0, HS.SIL)
		ci.draw_set_transform(_off + foot * _k, 0.0, Vector2(_k, _k * 0.2))
		ci.draw_circle(Vector2.ZERO, 70.0 if big else 56.0, Color(0, 0, 0, 0.35))
		ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
		HS.solid_px(ci, foot + Vector2(0, 22), "LOCKED", 2.0, Color(1, 1, 1, 0.6), 1)
		for j in 4:
			var pj := 3 + i * 4 + j
			if pj < pool.size():
				_figure(_card(pool[pj]), Vector2(cx - 84 + j * 56, _p(600.0, 514.0) if big else _p(580.0, 498.0)), 0.7, Color(0.45, 0.47, 0.52))
	if pool.size() >= 2:
		_brackets(Rect2(840, _p(250, 176), 200, _p(300, 270)), Color(1, 1, 1, 0.85))
	HS.para(ci, Rect2(840, _p(210, 138), 210, 36), UI.fa(UI.VIOLET, 0.9))
	UI.text_at(ci, f, Vector2(945, _p(228, 156)), "卡池 · 未解锁 %d 名" % locked.size(), 15, Color.WHITE, "mm", true)
	var r1 := Rect2(620, D.y - 84, 300, 62)
	var r0 := Rect2(940, D.y - 88, 310, 68)
	HS.ghost_btn(ci, f, r1, "定向寻访  （%d 张）" % _cost_pick(), "", 1.0)
	if not _can_direct():
		HS.para(ci, r1, Color(0, 0, 0, 0.55))
	elif _hot(1, r1):
		HS.para(ci, r1.grow(3), Color(0, 0, 0, 0), HS.CYB, 2.0)
	HS.main_btn(ci, f, r0, "寻访一次  （1 张）", "")
	if _hot(0, r0):
		HS.para(ci, r0.grow(4), Color(0, 0, 0, 0), Color.WHITE, 2.0)
	_btn(r1, 1)
	_btn(r0, 0)


func _brackets(r: Rect2, col: Color, l := 22.0, w := 3.0) -> void:
	var ci: CanvasItem = g.hud
	for c in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
		var p: Vector2 = c[0]
		ci.draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -l, 0 if c[2] > 0 else -w), Vector2(l, w)), col)
		ci.draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -w, 0 if c[2] > 0 else -l), Vector2(w, l)), col)


# ---------------------------------------------------------------- 定向 · 选职业（GPT 28）

func _bottom(text_mid := "") -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	HS.bottom_bar(ci, D, 88)
	HS.voucher(ci, Vector2(80, D.y - 44), 0.8)
	UI.text_at(ci, f, Vector2(130, D.y - 44), "持有寻访凭证  × %d" % _vouchers(), 20, UI.TEXT, "lm")
	UI.text_at(ci, f, Vector2(350, D.y - 44), "本次消耗 %d" % _cost_pick(), 15, HS.MUTE, "lm")
	if text_mid != "":
		UI.text_at(ci, f, Vector2(640, D.y - 44), text_mid, 15, UI.TEXT, "mm")


func _draw_class() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	HS.left_panel(ci, D, 500, 380, 62)
	_btn(HS.topbar(ci, f, D, ["PERSONNEL /", "RECRUITMENT"], "定向寻访 · 选择职业"), "back")
	var by := HS.title_block(ci, f, Vector2(36, _p(150, 116)), "01", "定向寻访", "定向寻访", "DIRECTED", 1.0, int(_p(72, 60)))
	UI.text_at(ci, f, Vector2(36, by + 34), "先选职业，再从该职业的未解锁干员中指定 1 名。", int(_p(15, 17)), HS.INK, "lm")
	UI.text_at(ci, f, Vector2(36, by + 60), "消耗寻访凭证 %d 张。" % _cost_pick(), int(_p(15, 17)), HS.INK, "lm")
	if not _phone:
		HS.hr_mark(ci, f, Vector2(36, 430))
	var bag := A.tex("ui_hh_bag_zip")
	if bag != null:
		ci.draw_texture_rect_region(bag, Rect2(Vector2(210, _p(650, D.y - 96)) - BAG_O, BAG_SZ), Rect2(0, 0, 256, 152))
	var locked := Roster.locked_ids()
	var owned := Roster.owned_classes()
	for i in 8:
		var cls: String = CLASS_ORDER[i]
		var col: Color = Character.CLASS_COL[cls]
		var row := int(i / 4)
		var ch := _p(262, (D.y - 88 - 82 - 22 - 12) / 2.0)   # 手机：两行卡挤进顶栏与底栏之间
		var fy := ch / 262.0
		var r := Rect2(560 + (i % 4) * 182 - row * 60 * fy, _p(104, 82) + row * (ch + 22), 166, ch)
		var mine: Array = _sorted(locked.filter(func(c): return Roster.class_of(c) == cls))
		var dis := mine.is_empty()
		var lt := 99.0 if UM.rm() else _now() - _mode_t0 - 0.05 * i   # 逐格点亮：每格晚 0.05 秒，点亮瞬间闪一下白边
		if lt < 0.0:
			HS.para(ci, r, Color(0, 0, 0, 0), Color(1, 1, 1, 0.12), 1.0)
			continue
		var on: bool = i == sel and not dis
		HS.card(ci, r, col, on, dis)
		if not dis and not on and not (Pad.using or g.kb_nav) and r.has_point((ci.get_local_mouse_position() - _off) / _k):
			HS.para(ci, r.grow(2), Color(0, 0, 0, 0), UI.fa(HS.CYB, 0.6), 1.5)
		var ink := HS.INK if on else Color(1, 1, 1, 0.4 if dis else 1.0)
		var cx := r.get_center().x + 10
		UI.class_glyph(ci, cls, Vector2(cx, r.position.y + 70 * fy), 26.0 * minf(1.0, fy + 0.1), ink, 4.0)
		HS.spaced(ci, f, Vector2(cx - UI.cwidth(f, CLASS_EN[cls], 9) * 0.5 - 18, r.position.y + 128 * fy), CLASS_EN[cls], 9, UI.fa(ink, 0.7), 3.0)
		UI.text_at(ci, f, Vector2(cx, r.position.y + 154 * fy), cls, 30, ink, "mm", true)
		ci.draw_line(Vector2(r.position.x + 30, r.position.y + 182 * fy), Vector2(r.end.x - 20, r.position.y + 182 * fy), UI.fa(ink, 0.3), 1.0)
		UI.text_at(ci, f, Vector2(cx, r.position.y + 204 * fy), "已全部解锁" if dis else "未解锁  %d" % mine.size(), 16, ink, "mm")
		var sx: float = cx - mini(4, mine.size()) * 16.0
		for j in mini(4, mine.size()):
			_figure(_card(mine[j]), Vector2(sx + 16, r.end.y - 10), 0.32, Color(0.45, 0.47, 0.52))
			sx += 32.0
		if not owned.has(cls) and not dis:
			HS.tag(ci, f, r.position + Vector2(r.size.y * HS.SKEW * 0.2 + 34, 10), "新职业", 0.85, HS.CYB)
		if not dis:
			_btn(r, i)
		if lt < 0.1:
			HS.para(ci, r.grow(2), UI.fa(Color.WHITE, 0.35 * (1.0 - lt / 0.1)), UI.fa(Color.WHITE, 1.0 - lt / 0.1), 2.0)
	_bottom("" if Pad.touch else "方向键选择")
	var br := Rect2(D.x - 330, D.y - 74, 310, 60)
	HS.main_btn(ci, f, br, "确认职业", "" if Pad.touch else "Enter")
	_btn(br, "ok")


# ---------------------------------------------------------------- 定向 · 指定干员（GPT 30）

func _draw_pick() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	HS.right_panel(ci, D, 780, 640, 62, D.y - 88)
	_btn(HS.topbar(ci, f, D, ["PERSONNEL /", "TRANSFER"], "定向寻访 · 指定干员"), "back")
	var n := choices.size()
	var cw := minf(200.0, (660.0 - 20.0 * (n - 1)) / maxf(1.0, n))
	for i in n:
		var od := _card(choices[i])
		var r := Rect2(40 + i * (cw + 20), _p(104, 84), cw, _p(470, D.y - 88 - 84 - 18))
		var on := i == sel
		HS.card(ci, r, od.col, on)
		var ink := HS.INK if on else Color.WHITE
		UI.class_glyph(ci, od.cls, r.position + Vector2(70, 40), 14.0, ink, 3.0)
		HS.spaced(ci, f, r.position + Vector2(96, 36), CLASS_EN[od.cls], 9, UI.fa(ink, 0.7), 3.0)
		UI.text_at(ci, f, r.position + Vector2(96, 54), od.cls, 16, ink, "lm", true)
		_figure(od, Vector2(r.get_center().x, r.end.y - 104), minf(1.8, cw / 110.0), Color(0.42, 0.44, 0.5) if not on else Color(0.30, 0.32, 0.37))
		ci.draw_line(Vector2(r.position.x + 30, r.end.y - 80), Vector2(r.end.x - 30, r.end.y - 80), UI.fa(ink, 0.3), 1.0)
		var fl := UI.fit_line(f, str(od.name), 28, cw - 40, 14)
		UI.text_at(ci, f, Vector2(r.get_center().x - 8, r.end.y - 44), fl[0], fl[1], ink, "mm", true)
		_btn(r, i)
	if sel < n:
		HS.reveal = minf(HS.reveal, 1.0 if UM.rm() else clampf((_now() - _mode_t0) / 0.5, 0.0, 1.0))
		var od2 := _card(choices[sel])
		var by := HS.title_block(ci, f, Vector2(820, _p(130, 100)), "01", "人事调度", od2.name, od2.en, 1.0, int(_p(64, 52)))
		UI.class_glyph(ci, od2.cls, Vector2(846, by + 50), 22.0, HS.INK, 4.0)
		HS.spaced(ci, f, Vector2(890, by + 40), CLASS_EN[od2.cls], 10, HS.INK2, 4.0)
		UI.text_at(ci, f, Vector2(890, by + 64), od2.cls, 22, HS.INK, "lm", true)
		ci.draw_rect(Rect2(820, by + _p(92, 84), 240, 2), HS.INK)
		ci.draw_rect(Rect2(820, by + _p(116, 100), 3, 16), HS.INK)
		UI.text_at(ci, f, Vector2(832, by + _p(124, 108)), "技能", 16, HS.INK, "lm", true)
		var sk: Array = od2.def.get("skills", [])
		for j in mini(3, sk.size()):
			var y := by + _p(150, 128) + j * _p(52, 46)
			ci.draw_rect(Rect2(820, y, 40, 40), HS.INK)
			HS.solid_px(ci, Vector2(840, y + 20), "S%d" % (j + 1), 2.0, Color.WHITE, 1)
			UI.text_at(ci, f, Vector2(876, y + 20), str(sk[j].get("name", "")), 17, HS.INK, "lm")
			ci.draw_line(Vector2(876, y + 44), Vector2(1060, y + 44), UI.fa(HS.INK, 0.2), 1.0)
		_figure(od2, Vector2(1160, D.y - 130), 3.0, Color(0.16, 0.17, 0.21))
		if not _phone:
			UI.text_at(ci, f, Vector2(820, D.y - 112), "指定 1 名未解锁干员加入名册。立绘在解锁后显示。", 14, HS.INK, "lm")
		HS.reveal = 1.0
	_bottom()
	var bb := Rect2(D.x - 560, D.y - 72, 210, 56)
	HS.ghost_btn(ci, f, bb, "返回", "" if Pad.touch else "Esc")
	_btn(bb, "back")
	var br := Rect2(D.x - 330, D.y - 74, 310, 60)
	HS.main_btn(ci, f, br, "确认寻访", "" if Pad.touch else "Enter")
	_btn(br, "ok")


# ---------------------------------------------------------------- 拉包（GPT 31，Codex 作战包）

## 拉包光层：主光 + 碎光第 f 帧合成；拉链没全开（s < 7）时只留开包遮罩第 s 档露出的部分。返回 [整层, 裁片]，按 [帧, 拉链档] 缓存
## 裁片 = 整层的 FX_CROP 区再乘全开口遮罩（原 delivery light_clip 第 7 档），画在包底层之上、前景之下，让光从开口里透出
func _light(f: int, s: int) -> Array:
	var key := "%d_%d" % [f, mini(s, 7)]
	if _glow.has(key):
		return _glow[key]
	var beams := _image("fx_hh_beams")
	var frags := _image("fx_hh_frags")
	var out := [null, null]
	if beams != null:
		var sz := Vector2i(FX_SZ)
		var img := beams.get_region(Rect2i(Vector2i(f * sz.x, 0), sz))
		if frags != null:
			img.blend_rect(frags.get_region(Rect2i(Vector2i(f * sz.x, 0), sz)), Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
		var rv := _image("fx_hh_reveal")
		if s < 7 and rv != null:
			var m := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
			m.blit_rect_mask(img, rv.get_region(Rect2i(Vector2i(s * sz.x, 0), sz)), Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
			img = m
		out[0] = ImageTexture.create_from_image(img)
		var clip := _image("fx_hh_light_clip")
		if clip != null:
			var c := Image.create(FX_CROP.size.x, FX_CROP.size.y, false, Image.FORMAT_RGBA8)
			c.blit_rect_mask(img.get_region(FX_CROP), clip.get_region(Rect2i(Vector2i(7 * FX_CROP.size.x, 0), FX_CROP.size)), Rect2i(Vector2i.ZERO, FX_CROP.size), Vector2i.ZERO)
			out[1] = ImageTexture.create_from_image(c)
	_glow[key] = out
	return out


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


func _blit(tx: Texture2D, frame: int, fsz: Vector2, origin: Vector2, pos: Vector2, sc: float, col := Color.WHITE) -> void:
	if tx == null:
		return
	g.hud.draw_texture_rect_region(tx, Rect2((pos - origin * sc).round(), fsz * sc), Rect2(fsz.x * frame, 0, fsz.x, fsz.y), col)


func _skip() -> void:
	var ci: CanvasItem = g.hud
	var br := Rect2(D.x - 210, 26, 180, 50)
	HS.para(ci, br, Color(0, 0, 0, 0.3), UI.TEXT)
	UI.text_at(ci, g.font, br.get_center(), "跳过" if Pad.touch else "跳过    Esc", 17, UI.TEXT, "mm", true)
	_btn(br, "skip")


func _draw_bag() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var t := _now() - t0
	if t >= BAG_T:
		_op(0)
		_draw_op()
		return
	# 台面与墙面
	ci.draw_rect(Rect2(Vector2.ZERO, D), Color8(22, 25, 32))
	var fl := D.y - 250.0   # 台面线
	for x in [150.0, 320.0, D.x - 320.0, D.x - 150.0]:
		ci.draw_line(Vector2(x, 0), Vector2(x - 60, fl), Color(1, 1, 1, 0.05), 24.0)
	HS.fill(ci, PackedVector2Array([Vector2(0, fl), Vector2(D.x, fl), D, Vector2(0, D.y)]), Color8(58, 62, 72))
	HS.fill(ci, PackedVector2Array([Vector2(180, fl), Vector2(D.x - 180, fl), Vector2(D.x - 60, D.y), Vector2(60, D.y)]), Color8(74, 78, 88))
	var sc := 2.0
	var ground := Vector2(D.x / 2.0, D.y - 120)
	var drop := clampf(t / 0.32, 0.0, 1.0)
	var pos := ground + Vector2(0, -(1.0 - drop * drop) * D.y * 0.7)
	ci.draw_set_transform(_off + ground * _k, 0.0, Vector2(_k, _k * 0.18))
	ci.draw_circle(Vector2.ZERO, BAG_SZ.x * sc * 0.5 * clampf(drop, 0.2, 1.0), Color(0, 0, 0, 0.45))
	ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	if t < ZIP0:
		_blit(A.tex("ui_hh_bag"), 0 if t < 0.32 else (1 if t < 0.36 else 2), BAG_SZ, BAG_O, pos, sc)
	else:
		var s := clampi(1 + int((t - ZIP0) / ZIP_STEP), 1, 7)
		var ticks := int((t - ZIP0) / 0.11)
		if t < ZIP1 and ticks > _zip_ticks:
			_zip_ticks = ticks
			Sfx.play("ui_move", -5.0, 1.0 + 0.04 * s)
		if t >= BURST and not _burst:
			_burst_sfx()
		var tl := (pos - BAG_O * sc).round()
		var lit := _light(int((t - ZIP0) * 12.0) % 24, s)
		var la := (tl + FX_AT * sc).round()
		if lit[0] != null:
			ci.draw_texture_rect(lit[0], Rect2(la, FX_SZ * sc), false)
		_blit(A.tex("ui_hh_bag_zip"), s, BAG_SZ, BAG_O, pos, sc)
		if lit[1] != null:
			ci.draw_texture_rect(lit[1], Rect2(la + Vector2(FX_CROP.position) * sc, Vector2(FX_CROP.size) * sc), false)
		_blit(A.tex("ui_hh_bag_zip_front"), s, BAG_SZ, BAG_O, pos, sc)
	ci.draw_rect(Rect2(40, 34, 3, 64), UI.TEXT)
	UI.text_at(ci, f, Vector2(64, 48), "寻访", 26, UI.TEXT, "lm", true)
	ci.draw_rect(Rect2(64, 74, 140, 1.5), UI.TEXT)
	HS.spaced(ci, f, Vector2(64, 98), "PERSONNEL", 13, UI.TEXT, 5.0)
	if t < ZIP1:
		ci.draw_line(Vector2(D.x / 2.0 - 160, D.y - 66), Vector2(D.x / 2.0 - 70, D.y - 66), UI.TEXT, 3.0)
		ci.draw_polyline(PackedVector2Array([Vector2(D.x / 2.0 - 146, D.y - 78), Vector2(D.x / 2.0 - 160, D.y - 66), Vector2(D.x / 2.0 - 146, D.y - 54)]), UI.TEXT, 3.0)
		HS.spaced(ci, f, Vector2(D.x / 2.0 - 50, D.y - 58), "向左拉开拉链", 18, UI.TEXT, 8.0)
	# 光炸：档位色铺满再转白，再退（docs/124 §10.2）
	if t > BURST - 0.1:
		var a := 0.0
		var c: Color = BURST_COL
		var bt := t - (BURST - 0.1)
		if bt < 0.15:
			a = bt / 0.15 * 0.85
		elif bt < 0.27:
			a = 0.9
			c = c.lerp(Color.WHITE, (bt - 0.15) / 0.12)
		else:
			a = 0.9 * (1.0 - (bt - 0.27) / 0.18)
			c = Color.WHITE
		ci.draw_rect(Rect2(-_off / _k, D + _off * 2.0 / _k), UI.fa(c, clampf(a, 0.0, 1.0)))
	_skip()


# ---------------------------------------------------------------- 揭示（GPT 32）

func _draw_op() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var lt := _now() - t0
	if lt >= OP_T:
		_advance()
		if mode != "op":
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw(g.hud.size)
			return
		lt = 0.0
	var res: Dictionary = results[idx]
	var od := _card(res.id)
	var col: Color = od.col
	HS.backdrop(ci, D)
	# 右：职业色斜带 + 职业图标水印 + 描边英文（缓慢平移）
	var drift := 0.0 if UM.rm() else lt * 6.0
	HS.fill(ci, PackedVector2Array([Vector2(1080, 0), Vector2(1280, 0), Vector2(900, D.y), Vector2(700, D.y)]), UI.fa(col.darkened(0.35), 0.45))
	UI.class_glyph(ci, od.cls, Vector2(1000, 250), 150.0, UI.fa(col.darkened(0.2), 0.45), 28.0)
	HS.outline_px(ci, Vector2(440 - drift, D.y - 270), od.en, 28.0, Color(1, 1, 1, 0.16), HS.DARK)
	# 立绘：滑入（3 道残影）→ 信号解码 → 待机循环；网点投影
	_reveal_figure(od, lt)
	# 左：浅灰名牌（滑入）
	var e := UM.out_cubic(lt / 0.4)
	ci.draw_set_transform(_off + Vector2(-(1.0 - e) * 480.0, 0) * _k, 0.0, Vector2(_k, _k))
	var py := _p(0.0, -60.0)   # 手机：名牌整体上移
	HS.fill(ci, PackedVector2Array([Vector2(0, 48), Vector2(460, 48), Vector2(460 - 0.262 * (D.y - 108), D.y - 60), Vector2(0, D.y - 60)]), HS.LIGHT)
	UI.class_glyph(ci, od.cls, Vector2(110, 190 + py * 0.6), 40.0, HS.INK, 7.0)
	ci.draw_rect(Rect2(186, 152 + py * 0.6, 2, 76), HS.INK)
	HS.spaced(ci, f, Vector2(214, 176 + py * 0.6), CLASS_EN[od.cls], 13, HS.INK, 8.0)
	UI.text_at(ci, f, Vector2(212, 212 + py * 0.6), od.cls, 40, HS.INK, "lm", true)
	var fl := UI.fit_line(f, str(od.name), int(_p(110, 96)), 330, 48)
	UI.text_at(ci, f, Vector2(46, 262 + py + (110 - fl[1]) * 0.6), fl[0], fl[1], HS.INK, "la", true)
	ci.draw_rect(Rect2(52, 410 + py, 66, 4), HS.YEL)
	HS.outline_px(ci, Vector2(52, 456 + py), od.en, minf(14.0, 84.0 / maxf(1.0, od.en.length())), HS.INK2, HS.LIGHT)
	if lt >= STAMP:
		if _stamped != idx:
			_stamped = idx
			Sfx.play("ui_ok")
		var se := clampf((lt - STAMP) / 0.2, 0.0, 1.0)
		var tg := Vector2(52, 540 + py) + Vector2(0, (1.0 - UI.ease_back(se)) * -14.0)
		HS.tag(ci, f, tg, "新职业" if bool(res.get("new_class", false)) else "新加入", 1.1)
		ci.draw_rect(Rect2(170, 544 + py, 2, 26), HS.INK)
		UI.text_at(ci, f, Vector2(186, 557 + py), "已加入名册", 18, HS.INK, "lm")
	ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	HS.spaced(ci, f, Vector2(40, 30), "PERSONNEL  //  %02d / %02d" % [idx + 1, results.size()], 10, HS.MUTE, 3.0)
	_skip()
	if lt >= PLATE:
		var br := Rect2(D.x - 330, D.y - 112, 300, 70)
		HS.main_btn(ci, f, br, "继续", "" if Pad.touch else "Enter")
		_btn(br, "ok")


func _reveal_figure(od: Dictionary, lt: float) -> void:
	var ci: CanvasItem = g.hud
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	var kk: float = 6.0 * 2.0 / hi * float(od.ds)
	var foot := Vector2(820, D.y - 70)
	var fr := 0 if lt < DECODE else _idle_frame(od, lt - DECODE)
	var src := Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var slide := UM.out_cubic(lt / SLIDE)
	var dst := Rect2(UI.foot_pos(foot, bb, fw, tx.get_height(), hi, kk).round() + Vector2(roundf((1.0 - slide) * 520.0), 0), (bb.size * kk).round())
	var wt := A.white_of(tx)
	for i in 120:   # 网点投影
		var x := 640.0 + (i % 40) * 9.0
		var y := D.y - 80.0 + int(i / 40) * 8.0
		ci.draw_rect(Rect2(x + (int(i / 40) % 2) * 4, y, 3, 3), Color(0, 0, 0, 0.35 * slide))
	if lt < SLIDE:
		for i in 3:
			var ar := dst
			ar.position.x += (i + 1) * 60.0 * (1.0 - slide)
			ci.draw_texture_rect_region(wt, ar, src, UI.fa(od.col, 0.32 - 0.09 * i))
	if lt < DECODE:
		ci.draw_texture_rect_region(wt, dst, src, Color8(60, 64, 74))
	if lt < SLIDE:
		return
	if lt >= DECODE:
		ci.draw_texture_rect_region(tx, dst, src)
		var fl := 1.0 - (lt - DECODE) / 0.12
		if fl > 0.0:
			ci.draw_texture_rect_region(wt, dst, src, UI.fa(Color.WHITE, fl * 0.7))
		return
	# 扫描线解码：扫过的行已是彩色，扫描线下沿 3 行 6 单位噪点块（固定散列，不读 g.rng）
	var rows := floorf(bb.size.y * (lt - SLIDE) / (DECODE - SLIDE))
	if rows > 0.0:
		ci.draw_texture_rect_region(tx, Rect2(dst.position, Vector2(dst.size.x, rows * kk)), Rect2(src.position, Vector2(src.size.x, rows)))
	var sy := dst.position.y + rows * kk
	ci.draw_rect(Rect2(dst.position.x - 20, sy - 1, dst.size.x + 40, 3), UI.fa(Color.WHITE, 0.95))
	var nx := int(dst.size.x / 6.0) + 1
	for r in 3:
		for c in nx:
			var hsh := (c * 73856093) ^ (r * 19349663) ^ (int(lt * 20.0) * 83492791)
			if hsh % 5 < 2:
				ci.draw_rect(Rect2(dst.position.x + c * 6.0, sy + 3 + r * 6.0, 6, 6), UI.fa(od.col, 0.5 - 0.14 * r))


# ---------------------------------------------------------------- 本次寻访（GPT 33）

func _draw_summary() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var t := 99.0 if (UM.rm() or UM.skip_all()) else _now() - t0
	HS.left_panel(ci, D, 400, 290, 62)
	HS.topbar(ci, f, D, ["PERSONNEL /", "RECRUITMENT"], "本次寻访", 1.0, "01 / 01", "")
	var by := HS.title_block(ci, f, Vector2(36, _p(150, 116)), "01", "人员寻访记录", "本次寻访", "RECORD", 1.0, int(_p(72, 60)))
	UI.text_at(ci, f, Vector2(36, by + 34), "本次加入干员如下。", 18, HS.INK, "lm")
	ci.draw_rect(Rect2(40, by + 74, 3, 100), HS.INK)
	UI.text_at(ci, f, Vector2(64, by + 88), "本次加入", 18, HS.INK, "lm")
	UI.text_at(ci, f, Vector2(60, by + 110), str(results.size()), 76, HS.INK, "la", true)
	UI.text_at(ci, f, Vector2(118, by + 156), "名", 30, HS.INK, "lm", true)
	if not _phone:
		HS.hr_mark(ci, f, Vector2(36, 600))
	var rs := results.duplicate()
	rs.sort_custom(func(a, b): return CLASS_ORDER.find(Roster.class_of(a.id)) < CLASS_ORDER.find(Roster.class_of(b.id)))
	var n := rs.size()
	var cw := minf(246.0, (780.0 - 20.0 * (n - 1)) / maxf(1.0, n))
	var x0 := 470.0 + (780.0 - (n * cw + (n - 1) * 20.0)) / 2.0
	for i in n:
		var r: Dictionary = rs[i]
		var od := _card(r.id)
		var e := UM.out_cubic((t - 0.1 * i) / 0.35)   # 卡片翻入（横向压窄 → 展开）
		if e <= 0.0:
			continue
		var full := Rect2(x0 + i * (cw + 20), _p(112, 86), cw, _p(520, D.y - 88 - 86 - 16))
		var rr := Rect2(full.position.x + full.size.x * (1.0 - e) / 2.0, full.position.y, full.size.x * e, full.size.y)
		HS.card(ci, rr, od.col)
		if e < 0.98:
			continue
		var cx := rr.get_center().x
		UI.class_glyph(ci, od.cls, Vector2(cx + 28, rr.position.y + 46), 22.0, Color.WHITE, 4.0)
		HS.spaced(ci, f, Vector2(cx - 6, rr.position.y + 94), CLASS_EN[od.cls], 9, UI.fa(Color.WHITE, 0.7), 3.0)
		UI.text_at(ci, f, Vector2(cx + 26, rr.position.y + 118), od.cls, 24, Color.WHITE, "mm", true)
		_figure(od, Vector2(cx + 6, rr.end.y - _p(148, 118)), minf(_p(2.5, 2.0), cw / 98.0), Color(0, 0, 0, 0), _idle_frame(od, t))
		var nr := Rect2(rr.position.x + 10, rr.end.y - _p(132, 104), rr.size.x - 22, _p(112, 92))
		HS.para(ci, nr, HS.LIGHT)
		HS.tag(ci, f, nr.position + Vector2(30, -12), "新职业" if bool(r.get("new_class", false)) else "新加入", 0.9)
		var fl := UI.fit_line(f, str(od.name), 34, nr.size.x - 40, 16)
		UI.text_at(ci, f, Vector2(nr.get_center().x, nr.position.y + nr.size.y * 0.41), fl[0], fl[1], HS.INK, "mm", true)
		ci.draw_line(Vector2(nr.position.x + 50, nr.position.y + nr.size.y * 0.66), Vector2(nr.end.x - 50, nr.position.y + nr.size.y * 0.66), HS.INK2, 1.0)
		HS.spaced(ci, f, Vector2(nr.get_center().x - UI.cwidth(f, od.en, 10) * 0.9, nr.position.y + nr.size.y * 0.875), od.en, 10, HS.INK2, 6.0)
	HS.bottom_bar(ci, D, 88)
	var left := _vouchers()
	var more: bool = (left > 0 or _can_direct()) and not Roster.locked_ids().is_empty()
	UI.text_at(ci, f, Vector2(64, D.y - 44), "已加入名册。新干员可以在选人页选为队长。" + ("   剩余寻访凭证 × %d" % left if more else ""), 16, UI.TEXT, "lm")
	var br := Rect2(D.x - 330, D.y - 74, 310, 60)
	HS.main_btn(ci, f, br, "继续寻访" if more else "完成", "")
	_btn(br, "ok")
