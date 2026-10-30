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
const Meta = preload("res://scripts/core/meta.gd")

## 用户 10-25：寻访专用原作职业标志，来源见 art/archive/incoming_1028/headhunt_professions_1025/sources.json。
const CLASS_ICONS := {
	"先锋": preload("res://art/ui/professions/pioneer.png"),
	"近卫": preload("res://art/ui/professions/warrior.png"),
	"重装": preload("res://art/ui/professions/tank.png"),
	"狙击": preload("res://art/ui/professions/sniper.png"),
	"术师": preload("res://art/ui/professions/caster.png"),
	"医疗": preload("res://art/ui/professions/medic.png"),
	"辅助": preload("res://art/ui/professions/support.png"),
	"特种": preload("res://art/ui/professions/special.png"),
}

const DESK := Vector2(1280, 720)   # 桌面设计稿尺寸
var D := DESK                      # 当前版面：手机横屏按屏幕比例取 1280 ×（600–720），纵向位置用 _p() 单独排（docs/124 §13.7）
var _phone := false
const CLASS_ORDER: Array = preload("res://scripts/data.gd").CLASS_ORDER
const CLASS_EN: Dictionary = preload("res://scripts/data.gd").CLASS_EN
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
const TEN_OP_T := 3.4
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

var g   # Game，或标题页的 screens/hunt_host.gd（只用 hud / font / kb_nav）
var open := false
var browse := false     # 标题页进入（10-24 用户：没有凭证也能点进去看卡池；按钮灰显）
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
var _buy_t0 := -9.0       # 上次兑换成功的时刻（「+1」上浮用）
## 开包进度（10-26 用户：按住往左拖 = 拉开，往回拖 = 合上、光跟着收回；拖过一半松手自动拉开，不到一半弹回合上；
## 键盘 / 手柄按住确认或左方向匀速拉开；单点一下 = 自动拉开）。0 = 合着，1 = 全开（触发光炸）
const DRAG_W := 380.0         # 从合着拖到全开要拖的设计单位
const OPEN_KEY := 0.9         # 按住键时每秒拉开的进度
var _open := 0.0
var _open_to := -1.0          # 松手后自动走向的目标（1 拉开 / 0 合上；−1 = 不动）
var _odrag := {}              # 开包拖动：{x 按下处, p 按下时进度, moved 是否拖动过}
var _okey := false            # 键盘 / 手柄按住拉开
var _burst_t := -1.0          # 光炸开始的时刻（−1 = 还没到）
var _zip_s := 0               # 上一帧的拉链档（档位变化时响一下拉链齿）
var _bag_last := 0.0
var _hum: AudioStreamPlayer   # 开口里的光：循环音，音量 / 音高跟开包进度（可逆）
var _flip_n := 0              # 十人总览：已经响过翻卡声的张数（第 TEN 张之后再响一下收尾和弦）
var ten := false          # 本次是十连（结果屏用十人总览）
var ten_first := false    # 新手十连（10-26：名册为空时入口只有「十连寻访」；揭示每人 TEN_OP_T 秒，最后一屏十人总览，完成回主界面）
                          # 常规十连（10-28）：拉包光炸后直接进十人总览（不逐个揭示），最高稀有度排最后、单独落入，完成回寻访入口
const TEN_HOLD := 0.45    # 常规十连：最后一张（最高稀有度）比前一张多等这么久再落入
var pick_scroll := 0      # 指定干员列表：第一张可见卡的下标
var _pdrag := {}          # 指定干员列表的拖动翻页：{x, scroll, act}
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


func _init(game) -> void:
	g = game


func _now() -> float:
	if clock_frames:
		return Engine.get_process_frames() / 60.0
	return Time.get_ticks_msec() / 1000.0


func _vouchers() -> int:
	return int(Cfg.roster_tickets.get(Roster.T_HUNT, 0))


# ---- 券规则（core/roster.gd，docs/124）：直接读常量、直接调兑换。10-22 架构复审（docs/126 R5）删掉了合入前的反射适配层——
# 它在绘制里每帧 get_script_constant_map / get_script_method_list（分配整张表），旧券的折算由 Cfg 读档时的 migrate_tickets 做
func _cost_pick() -> int:
	return Roster.COST_PICK


func _per_run() -> int:
	return Roster.RUN_TICKETS


func _per_clear() -> int:
	return Roster.RUN_TICKETS + Roster.WIN_BONUS


func _redeem_random() -> Dictionary:
	return Roster.redeem_random()


func _redeem_directed(cid: String) -> Dictionary:
	return Roster.redeem_pick(cid)


func _can_random() -> bool:
	return _vouchers() >= Roster.COST_RANDOM


func _can_direct() -> bool:
	return _vouchers() >= Roster.COST_PICK


func _spill() -> void:
	Roster.spill_to_cells()


## 主循环每帧调（game._process，docs/126 R4：原来在 hud.gd 的绘制回调里调）：结算面板出来后（胜利即时；倒下等过渡画完）有待用的凭证就盖一层，
## 用完才回到结算按钮；作战记录开着、演练局不开
func tick() -> void:
	if not (g.state == g.S.WIN or (g.state == g.S.DEAD and g.state_age >= g.hud_view.DEATH_T + 0.35)) or g.trial.active or g.run_stats.open:
		return
	maybe_open()


func maybe_open() -> void:
	if open or not Roster.active():
		return
	browse = false
	if not _can_random() and not _can_direct():
		return
	if Roster.locked_ids().is_empty():
		_spill()
		return
	open = true
	_entry()
	_trans("enter")


## 标题页入口：没有凭证 / 名册已满也打开（只能看，寻访按钮灰显）；返回是否打开了
func open_browse() -> bool:
	if open or not Roster.active():
		return open
	browse = true
	open = true
	_entry()
	if open:
		_trans("enter")
	return open


func _entry() -> void:
	results.clear()
	ten = false
	ten_first = false
	if Roster.locked_ids().is_empty():
		_spill()
	if not browse and ((not _can_random() and not _can_direct()) or Roster.locked_ids().is_empty()):
		open = false
		return
	mode = "entry"
	sel = 0
	_warm_start()
	t0 = _now()
	_mode_t0 = t0


## 预载（10-25 用户：进寻访卡顿）：入口先同步载好卡池前 3 名（在转场计时之前），其余未解锁干员每帧载一名，
## 到选人 / 揭示时精细立绘、剪影、包围盒都已就绪；与 fps-first 的引擎层预热互不依赖
var _warm_q: Array = []
var _warmed := {}


func _warm_one(cid: String, stage := 3) -> void:
	var od := _card(cid)   # 阶段 0：载精细立绘；1：帧内包围盒；2：剪影贴图（单张最重，约 5–90 毫秒，所以分帧）
	if od.tex == null:
		_warmed[cid] = true
		return
	if stage == 1 or stage >= 3:
		UI.card_bb(od, od.tex)
	if stage == 2 or stage >= 3:
		A.white_of(od.tex)
		_warmed[cid] = true


## 入口只画已预载好的剪影（转场黑场期间逐帧载完，没有一次性卡顿）；选人 / 揭示 / 本次寻访画到时当场补载
func _is_warm(cid: String) -> bool:
	return _warmed.has(cid)


func _warm_start() -> void:
	var pool := _sorted(Roster.locked_ids())
	_warm_q = []
	for cid in pool:
		if not _warmed.has(cid):
			for st in 3:
				_warm_q.append([cid, st])


func _warm() -> void:
	if not _warm_q.is_empty():
		var w: Array = _warm_q.pop_front()
		_warm_one(w[0], w[1])


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
		if ten and not ten_first:
			_summary()
		else:
			_op(0)
		return
	mode = "bag"
	t0 = _now()
	_zip_ticks = 0
	_burst = false
	_open = 0.0
	_open_to = -1.0
	_odrag = {}
	_okey = false
	_burst_t = -1.0
	_zip_s = 0
	_bag_last = _now()
	Sfx.ensure(Sfx.HH_SFX)
	Sfx.play("hh_drop", -4.0, 1.0, 0.0)
	_trans("cut")


func _op(i: int) -> void:
	_hum_set(0.0)
	Sfx.play("hh_reveal", -6.0, 1.0, 0.03)
	Sfx.play("hh_star6", -12.0, 1.0, 0.0)   # 每名干员同一套声音（不按稀有度区别对待）
	idx = i
	mode = "op"
	reveal_id = results[i].id
	t0 = _now() - (PLATE if UM.rm() else 0.0)


func _summary() -> void:
	_hum_set(0.0)
	_flip_n = 0
	if mode in ["op", "bag"]:
		_trans("wipe")
	mode = "summary"
	t0 = _now()


## 点按：拉包段 = 自动拉开（拉开后光炸进第一名）；揭示段先到终态，再按下一名
func _tap() -> void:
	if mode == "bag":
		if _burst_t < 0.0:
			_open_to = 1.0
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
	Sfx.play("hh_burst", -2.0, 1.0, 0.0)
	Sfx.play("hh_star6", -5.0, 1.0, 0.0)   # 光炸上叠一串上行钟音


## 开口里的光（循环）：v = 0–1 音量，按开包进度走；进度降回 0 时停
func _hum_set(v: float) -> void:
	if v <= 0.001:
		if _hum != null and _hum.playing:
			_hum.stop()
		return
	if _hum == null:
		Sfx.ensure(["hh_hum"])
		var st = Sfx.streams.get("hh_hum")
		if st == null:
			return
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		_hum = AudioStreamPlayer.new()
		_hum.stream = st
		_hum.bus = "SFX"
		g.hud.add_child(_hum)
	_hum.volume_db = linear_to_db(maxf(v, 0.001)) - 2.0
	_hum.pitch_scale = 0.8 + 0.45 * v
	if not _hum.playing:
		_hum.play()
	if Sfx.trace_on:
		Sfx.trace.append([Engine.get_process_frames(), "hh_hum~", _hum.volume_db, _hum.pitch_scale])


func _act(a) -> void:
	match mode:
		"entry":
			if a is String and a == "buy":
				if Roster.exchange_ticket():
					_buy_t0 = _now()
					Sfx.play("ui_ok")
					Sfx.play("levelup", -8.0)
				else:
					Sfx.play("ui_move", -4.0, 0.6)   # 细胞不够 / 名册已满：只响一声
				return
			if Roster.needs_first():
				# 新手十连（10-26 用户）：入口只有这一个按钮，不能拆成单抽 / 定向
				if (a is int and a == 0) or (a is String and a in ["one", "ten"]):
					if _vouchers() >= Roster.TEN:
						Sfx.play("ui_ok")
						results = Roster.redeem_ten()
						ten = true
						ten_first = true
						_play()
					else:
						Sfx.play("ui_move", -4.0, 0.6)
				elif a is String and a == "back":
					Sfx.play("ui_ok")
					open = false
				else:
					Sfx.play("ui_move", -4.0, 0.6)
				return
			if a is int:
				sel = a
				a = ["one", "directed", "ten"][a]
			if a == "ten":
				if Roster.can_ten():
					Sfx.play("ui_ok")
					results = _ten_order(Roster.redeem_ten_hunt())
					ten = not results.is_empty()
					_play()
				else:
					Sfx.play("ui_move", -4.0, 0.6)   # 凭证不够 / 未解锁不足 10 名：灰显按钮只响一声
				return
			if a == "one" and _can_random() and not Roster.locked_ids().is_empty():
				Sfx.play("ui_ok")
				var r := _redeem_random()
				if str(r.get("id", "")) != "":
					results = [r]
				_play()
			elif a == "directed" and _can_direct() and not Roster.locked_ids().is_empty():
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
			else:
				Sfx.play("ui_move", -4.0, 0.6)   # 凭证不够 / 没有可寻访的干员：灰显按钮只响一声
		"class":
			if a is int and a >= 0 and a < choices.size():
				if not Roster.locked_classes().has(choices[a]):
					return
				sel = a   # 点一下就进（10-24 用户：抽卡界面点击就抽）
				a = "ok"
			if a == "ok" and Roster.locked_classes().has(choices[sel]):
				Sfx.play("ui_ok")
				sel_cls = choices[sel]
				choices = _sorted(Roster.locked_ids().filter(func(c): return Roster.class_of(c) == sel_cls))
				sel = 0
				pick_scroll = 0
				_pdrag = {}
				mode = "pick"
				_trans("slide")
			elif a == "back":
				Sfx.play("ui_ok")
				mode = "entry"
				sel = 1
				_trans("slide")
		"pick":
			if a is String and a.begins_with("scroll_"):
				_pick_step(-1 if a == "scroll_l" else 1)
				return
			if a is int and a >= 0 and a < choices.size():
				sel = a
				a = "ok"   # 点一下就寻访（10-24 用户）
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
			if a == "ok" and ten and not _sum_done():
				_sum_finish()   # 十人总览还在落卡：先全部到位，再按一次才离开
				return
			if a == "ok":
				Sfx.play("ui_ok")
				if ten_first:
					ten = false
					ten_first = false
					open = false   # 新手十连看完总览直接回主界面（此时可以集结出发了）
					return
				_entry()
				if open:
					_trans("slide")


## 输入（game.gd _unhandled_input 在寻访打开时整段交给这里）；返回是否用掉了这次输入
func input(event: InputEvent) -> bool:
	if mode == "pick" and choices.size() > _pick_geom().cap:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
			_pick_step(-1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1)
			return true
		if not _pdrag.is_empty() and (event is InputEventMouseMotion or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
			var px: float = (event.position.x / Cfg.ui_k - _off.x) / _k
			if event is InputEventMouseMotion:
				pick_scroll = clampi(int(_pdrag.s) - int(roundf((px - float(_pdrag.x)) / float(_pick_geom().pitch))), 0, maxi(0, choices.size() - int(_pick_geom().cap)))
				return true
			var act = _pdrag.act
			var moved := absf(px - float(_pdrag.x)) >= 12.0
			_pdrag = {}
			if not moved:
				_act(act)
			return true
	if _tr != "" and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_tr = ""   # 转场中任意键 / 点按：直接到位，这次输入不再往下传
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (event.position / Cfg.ui_k - _off) / _k
		for r in rects:
			var box: Rect2 = r[0]
			var hit := box.has_point(p)
			if hit and mode == "pick" and r[1] is int:
				# 加宽后的斜卡外接矩形会相交，命中只认卡片真实截面。
				var left := box.position.x + (box.end.y - p.y) * HS.SKEW
				hit = p.x >= left and p.x <= left + box.size.x - box.size.y * HS.SKEW
				if hit and choices.size() > _pick_geom().cap:
					_pdrag = {"x": p.x, "s": pick_scroll, "act": r[1]}   # 列表要滚动时：按下先当拖动，松手时位移 < 12 才算点选
					return true
			if hit:
				_act(r[1])
				return true
		if mode == "bag":
			_odrag = {"x": p.x, "p": _open, "moved": false}
			_open_to = -1.0
			return true
		if mode == "op":
			_tap()
		elif mode == "summary" and ten and not _sum_done():
			_sum_finish()
		return true
	if mode == "bag" and not _odrag.is_empty():
		if event is InputEventMouseMotion or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			var px: float = (event.position.x / Cfg.ui_k - _off.x) / _k
			var dx: float = float(_odrag.x) - px   # 往左为正
			if absf(dx) >= 12.0:
				_odrag.moved = true
			if event is InputEventMouseMotion:
				if _odrag.moved and _burst_t < 0.0:
					_open = clampf(float(_odrag.p) + dx / DRAG_W, 0.0, 1.0)
				return true
			var moved: bool = _odrag.moved
			_odrag = {}
			if _burst_t < 0.0:
				_open_to = 1.0 if (not moved or _open >= 0.5) else 0.0   # 单点 = 自动拉开；拖过一半松手自动拉开，不到一半弹回
			return true
	if mode == "bag" and event is InputEventKey and not event.echo:
		var kb: int = Pad.kc(event)
		if kb in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_LEFT, KEY_A]:
			_okey = event.pressed
			if event.pressed:
				_open_to = -1.0
			elif _burst_t < 0.0:
				_open_to = 1.0 if _open >= 0.5 else 0.0
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = Pad.kc(event)
		if k == KEY_B and mode == "entry":
			_act("buy")
		elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_act(sel if mode == "entry" else "ok")
		elif k == KEY_ESCAPE:
			_act("skip" if mode in ["bag", "op"] else "back")
		elif k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S]:
			var d: int = {KEY_LEFT: -1, KEY_A: -1, KEY_RIGHT: 1, KEY_D: 1, KEY_UP: -4, KEY_W: -4, KEY_DOWN: 4, KEY_S: 4}[k]
			if mode == "entry":
				# 入口按钮从左到右：定向（1）/ 寻访一次（0）/ 十连（2）；新手十连只有一个
				var row: Array = [0] if Roster.needs_first() else [1, 0, 2]
				sel = row[clampi(row.find(sel) + signi(d), 0, row.size() - 1)]
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
				_pick_scroll_to(sel)
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
	var tx: Texture2D = A.tex_hi(tn) if tn != "" else null   # 精细 @2x 立绘（同选人页，10-25 用户：寻访不用局内 1 倍帧条）
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


## 立绘放进 area：按帧内非透明区 bb 等比缩到恰好装得下（不超过 kmax 倍的 @2x 像素设计单位），水平居中、底边贴 area 底，
## 任何干员都不会画出 area（10-25 用户：立绘出框）；sil = 剪影色；dx = 额外水平偏移（滑入用）；返回目标矩形
func _figure(od: Dictionary, area: Rect2, kmax: float, sil := Color(0, 0, 0, 0), frame := 0, dx := 0.0) -> Rect2:
	var tx: Texture2D = od.tex
	if tx == null:
		return Rect2()
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return Rect2()
	var kk: float = minf(minf(area.size.x / bb.size.x, area.size.y / bb.size.y), kmax * 2.0 / hi * float(od.ds))
	var sz := (bb.size * kk).round()
	var dst := Rect2(Vector2(area.position.x + roundf((area.size.x - sz.x) / 2.0) + dx, area.end.y - sz.y), sz)
	var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var t2: Texture2D = A.white_of(tx) if sil.a > 0.0 else tx
	g.hud.draw_texture_rect_region(t2, dst, src, sil if sil.a > 0.0 else Color.WHITE)
	return dst


func _btn(r: Rect2, act) -> void:
	rects.append([r, act])


func draw(vs: Vector2) -> void:
	rects.clear()
	_warm()
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
				if ten:
					_draw_summary10()
				else:
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
	var rules := ["探索 %d 分钟以上结算获得 %d 张，通关获得 %d 张" % [int(Roster.RUN_MIN_T / 60.0), _per_run(), _per_clear()], "未解锁 %d 名 · 不会抽到重复干员" % locked.size()]
	var first := Roster.needs_first()
	if locked.is_empty():
		rules = ["干员已全部入职", "此后获得的凭证每张折算为 %d 生机细胞" % Roster.CELLS_PER_TICKET]
	elif first:
		rules = ["新手寻访：一次招募 %d 名不同干员" % Roster.TEN, "从全部干员中随机，招募后即可编队出发"]
	elif Cfg.roster_draws == 0:
		rules.append("首次寻访必定获得医疗干员")
	# 10-31 TA 审阅 docs/208 H9：规则第三条（首次寻访必定获得医疗干员）原来被兑换框压住一半——兑换框接在规则列表后面排，下面的部门字样跟着让
	var ry0: float = _p(500, 414)
	var rstep: float = _p(26, 26)
	for j in rules.size():
		ci.draw_rect(Rect2(40, ry0 - 3 + j * rstep, 6, 6), HS.INK)
		UI.text_at(ci, f, Vector2(56, ry0 + j * rstep), rules[j], int(_p(14, 17)), HS.INK2, "lm")
	var ey: float = ry0 + rules.size() * rstep + 6.0
	if Roster.exchange_visible() and not first:
		_draw_exchange(ci, f, ey)
		ey += 62.0
	if not _phone:
		HS.hr_mark(ci, f, Vector2(40, maxf(640.0, ey + 6.0)))
	# 卡池：三个灰色剪影（未解锁的前 3 名；10-25 用户：「未解锁」下面的小剪影不要了），缓慢视差
	HS.outline_px(ci, Vector2(560, _p(104, 64)), "PERSONNEL", 11.0, Color(1, 1, 1, 0.12), HS.DARK)   # 10-31 TA H9：上移，「寻访范围」标签不再压在大字上
	var pool := _sorted(locked)
	var t := _now() - t0
	for i in mini(3, pool.size()):
		var cx := 670.0 + i * 245.0
		var big := i == 1
		var foot := Vector2(cx + (0.0 if UM.rm() else sin(t * 0.6 + i) * 6.0), _p(520.0, 430.0) if big else _p(500.0, 414.0))
		var ah := _p(300.0, 240.0) * (1.0 if big else 0.82)
		if _is_warm(pool[i]):
			_figure(_card(pool[i]), Rect2(foot.x - 100.0, foot.y - ah, 200.0, ah), 4.0 if big else 3.0, HS.SIL)
		ci.draw_set_transform(_off + foot * _k, 0.0, Vector2(_k, _k * 0.2))
		ci.draw_circle(Vector2.ZERO, 70.0 if big else 56.0, Color(0, 0, 0, 0.35))
		ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
		HS.solid_px(ci, foot + Vector2(0, 22), "LOCKED", 2.0, Color(1, 1, 1, 0.6), 1)
	if pool.size() >= 2:
		_brackets(Rect2(805, _p(250, 176), 200, _p(300, 270)), Color(1, 1, 1, 0.85))
	if pool.is_empty():
		# 名册已满（10-24 用户问「全有了显示什么」）：卡池位置换成「全员入职」签，不留空场
		_brackets(Rect2(700, _p(270, 196), 480, _p(200, 180)), Color(1, 1, 1, 0.5))
		UI.text_at(ci, f, Vector2(940, _p(340, 262)), "全员已入职", int(_p(44, 38)), Color.WHITE, "mm", true)
		HS.solid_px(ci, Vector2(940, _p(392, 308)), "ALL OPERATORS ON BOARD", 2.0, Color(1, 1, 1, 0.6), 1)
		UI.text_at(ci, f, Vector2(940, _p(430, 344)), "罗德岛人事部已无待寻访的干员", 15, UI.fa(Color.WHITE, 0.55), "mm")
	else:
		HS.para(ci, Rect2(800, _p(210, 138), 210, 36), UI.fa(UI.VIOLET, 0.9))
		UI.text_at(ci, f, Vector2(905, _p(228, 156)), "寻访范围 · %d 名" % locked.size(), 15, Color.WHITE, "mm", true)
	if first:
		# 新手十连：只有一个主按钮（10 张），呼吸描边提示
		var rt := Rect2(860, D.y - 92, 390, 74)
		var can_t := n >= Roster.TEN
		HS.main_btn(ci, f, rt, "十连寻访  （%d 张）" % Roster.TEN, "", 1.1)
		if not can_t:
			HS.para(ci, rt, Color(0, 0, 0, 0.55))
		else:
			var pa := 0.5 + 0.5 * sin(_now() * 4.0) if not UM.rm() else 1.0
			HS.para(ci, rt.grow(4.0 + 3.0 * pa), Color(0, 0, 0, 0), UI.fa(Color.WHITE, 0.4 + 0.5 * pa), 2.0)
		_btn(rt, 0)
		return
	# 底部三枚按钮，从左到右：定向 / 寻访一次 / 十连（10-28 用户加十连：价格 = 单次 × 10，不够时灰掉并写还差多少）
	var r1 := Rect2(440, D.y - 84, 240, 62)
	var r0 := Rect2(696, D.y - 88, 264, 68)
	var r2 := Rect2(976, D.y - 88, 274, 68)
	HS.ghost_btn(ci, f, r1, "定向寻访  （%d 张）" % _cost_pick(), "", 1.0)
	if not _can_direct() or locked.is_empty():
		HS.para(ci, r1, Color(0, 0, 0, 0.55))
	elif _hot(1, r1):
		HS.para(ci, r1.grow(3), Color(0, 0, 0, 0), HS.CYB, 2.0)
	HS.main_btn(ci, f, r0, "寻访一次  （1 张）", "")
	if not _can_random() or locked.is_empty():
		HS.para(ci, r0, Color(0, 0, 0, 0.55))
	elif _hot(0, r0):
		HS.para(ci, r0.grow(4), Color(0, 0, 0, 0), Color.WHITE, 2.0)
	HS.main_btn(ci, f, r2, "十连寻访  （%d 张）" % Roster.COST_TEN, "")
	if not Roster.can_ten():
		HS.para(ci, r2, Color(0, 0, 0, 0.55))
		var why := "还差 %d 张寻访凭证" % Roster.ten_short() if Roster.ten_short() > 0 else "未解锁干员不足 %d 名" % Roster.TEN
		UI.text_at(ci, f, Vector2(r2.get_center().x, r2.position.y - 14), why, 14, UI.fa(Color.WHITE, 0.75), "mm")
	elif _hot(2, r2):
		HS.para(ci, r2.grow(4), Color(0, 0, 0, 0), Color.WHITE, 2.0)
	_btn(r1, 1)
	_btn(r0, 0)
	_btn(r2, 2)


## 用生机细胞兑换寻访凭证（用户 10-25：1 张 = Roster.TICKET_PRICE 个细胞，不设上限）：凭证数下面一枚按钮，细胞不够就灰掉并写还差多少
func _draw_exchange(ci: CanvasItem, f: Font, y := -1.0) -> void:
	var r := Rect2(36, y if y >= 0.0 else _p(570.0, 500.0), 380, 50)
	var can := Roster.exchange_short() == 0
	var hot: bool = can and not (Pad.using or g.kb_nav) and r.has_point((ci.get_local_mouse_position() - _off) / _k)
	HS.para(ci, r, HS.INK if can else Color(0, 0, 0, 0), Color(0, 0, 0, 0) if can else UI.fa(HS.INK, 0.35), 1.5)
	if hot:
		HS.para(ci, r.grow(3), Color(0, 0, 0, 0), HS.CYB, 2.0)
	var ink := Color.WHITE if can else UI.fa(HS.INK, 0.55)
	UI.text_at(ci, f, Vector2(r.position.x + 22, r.position.y + 18), "用生机细胞兑换 1 张（%d）" % Roster.TICKET_PRICE, 17, ink, "lm", true)
	var sub := "持有生机细胞  %d" % Meta.available() if can else "还差 %d 生机细胞  ·  持有 %d" % [Roster.exchange_short(), Meta.available()]
	UI.text_at(ci, f, Vector2(r.position.x + 22, r.position.y + 38), sub, 13, UI.fa(ink, 0.8), "lm")
	var bt := _now() - _buy_t0
	if bt >= 0.0 and bt < 0.9:   # 兑换成功：凭证数旁「+1」上浮淡出
		var vy := _p(400.0, 320.0)
		UI.text_at(ci, f, Vector2(300, vy - 6.0 - bt * 24.0), "+1", 26, UI.fa(HS.INK, 1.0 - bt / 0.9), "mm", true)
	_btn(r, "buy")


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


## 仅影响寻访界面；纹理原始宽高比保持不变，颜色跟随选中/禁用状态。
func _class_icon(ci: CanvasItem, cls: String, center: Vector2, radius: float, color: Color, _width := 2.0) -> void:
	var texture: Texture2D = CLASS_ICONS.get(cls)
	if texture == null:
		return
	var size := texture.get_size()
	size *= radius * 2.0 / maxf(size.x, size.y)
	ci.draw_texture_rect(texture, Rect2((center - size * 0.5).round(), size.round()), false, color)


func _draw_class() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	HS.left_panel(ci, D, 500, 380, 62)
	_btn(HS.topbar(ci, f, D, ["PERSONNEL /", "RECRUITMENT"], "定向寻访 · 选择职业"), "back")
	var by := HS.title_block(ci, f, Vector2(36, _p(150, 116)), "01", "定向寻访", "定向寻访", "DIRECTED", 1.0, int(_p(72, 60)))
	UI.text_at(ci, f, Vector2(36, by + 34), "先选职业，再从未解锁干员中指定 1 名。", int(_p(15, 17)), HS.INK, "lm")
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
		_class_icon(ci, cls, Vector2(cx, r.position.y + 70 * fy), 38.0 * minf(1.0, fy + 0.1), ink, 4.0)
		HS.spaced(ci, f, Vector2(cx - UI.cwidth(f, CLASS_EN[cls], 9) * 0.5 - 18, r.position.y + 128 * fy), CLASS_EN[cls], 9, UI.fa(ink, 0.7), 3.0)
		UI.text_at(ci, f, Vector2(cx, r.position.y + 154 * fy), cls, 30, ink, "mm", true)
		ci.draw_line(Vector2(r.position.x + 30, r.position.y + 182 * fy), Vector2(r.end.x - 20, r.position.y + 182 * fy), UI.fa(ink, 0.3), 1.0)
		UI.text_at(ci, f, Vector2(cx, r.position.y + 204 * fy), "已全部解锁" if dis else "未解锁  %d" % mine.size(), 16, ink, "mm")
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

## 指定干员列表：固定卡宽，放不下的横向滚动（滚轮 / 方向键 / 两侧箭头 / 拖动），一次露出 PICK_CAP 张以内（10-25 用户：小人列表要能滚动、别出框）
const PICK_CW := 190.0
const PICK_X0 := 24.0
const PICK_X1 := 770.0   # 右侧信息面板（right_panel 从 780 起）之前


func _pick_geom() -> Dictionary:
	var height := _p(470.0, D.y - 88.0 - 84.0 - 18.0)
	var skew := height * HS.SKEW
	var pitch := PICK_CW + 20.0
	var cap := maxi(1, int((PICK_X1 - PICK_X0 - PICK_CW - skew) / pitch) + 1)
	return {"h": height, "skew": skew, "pitch": pitch, "cap": cap, "y": _p(104.0, 84.0)}


func _pick_step(d: int) -> void:
	var cap: int = _pick_geom().cap
	var np := clampi(pick_scroll + d, 0, maxi(0, choices.size() - cap))
	if np != pick_scroll:
		pick_scroll = np
		Sfx.play("ui_move", -6.0)


func _arrow(c: Vector2, d: int, col: Color) -> void:
	var r := 9.0
	g.hud.draw_polyline(PackedVector2Array([c + Vector2(-d * r * 0.5, -r), c + Vector2(d * r * 0.5, 0), c + Vector2(-d * r * 0.5, r)]), col, 3.0)


func _pick_scroll_to(i: int) -> void:
	var cap: int = _pick_geom().cap
	pick_scroll = clampi(pick_scroll, 0, maxi(0, choices.size() - cap))
	if i < pick_scroll:
		pick_scroll = i
	elif i >= pick_scroll + cap:
		pick_scroll = i - cap + 1
	pick_scroll = clampi(pick_scroll, 0, maxi(0, choices.size() - cap))


func _draw_pick() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	HS.right_panel(ci, D, 780, 640, 62, D.y - 88)
	_btn(HS.topbar(ci, f, D, ["PERSONNEL /", "TRANSFER"], "定向寻访 · 指定干员"), "back")
	var n := choices.size()
	var gm := _pick_geom()
	var cap: int = gm.cap
	var height: float = gm.h
	var skew: float = gm.skew
	pick_scroll = clampi(pick_scroll, 0, maxi(0, n - cap))
	for k in mini(cap, n - pick_scroll):
		var i := pick_scroll + k
		var od := _card(choices[i])
		var r := Rect2(PICK_X0 + k * gm.pitch, gm.y, PICK_CW + skew, height)
		var on := i == sel
		HS.card(ci, r, od.col, on)
		var ink := HS.INK if on else Color.WHITE
		# 斜卡每个高度的中心不同；文字宽度扣除斜切及内边距。
		var inner := maxf(24.0, r.size.x - skew - 24.0)
		var top_x := r.get_center().x + skew * 0.5 - 34.0 * HS.SKEW
		_class_icon(ci, od.cls, Vector2(top_x, r.position.y + 34), 14.0, ink)
		var en := UI.fit_line(f, CLASS_EN[od.cls], 9, inner, 8)
		UI.text_at(ci, f, Vector2(top_x - 24.0 * HS.SKEW, r.position.y + 58), en[0], en[1], UI.fa(ink, 0.7), "mm")
		UI.text_at(ci, f, Vector2(top_x - 46.0 * HS.SKEW, r.position.y + 80), od.cls, 16, ink, "mm", true)
		# 立绘区：卡中段，宽度扣掉这一段高度上斜边的位移，保证整个人在卡框里
		var ay0 := r.position.y + 96.0
		var ay1 := r.end.y - 96.0
		var drift := (ay1 - ay0) * HS.SKEW
		var cxm := r.position.x + (r.end.y - (ay0 + ay1) * 0.5) * HS.SKEW + PICK_CW * 0.5
		var area := Rect2(cxm - (PICK_CW - drift - 16.0) * 0.5, ay0, PICK_CW - drift - 16.0, ay1 - ay0)
		_figure(od, area, 3.0, Color(0.42, 0.44, 0.5) if not on else Color(0.30, 0.32, 0.37))
		var line_x := r.get_center().x - skew * 0.5 + 80.0 * HS.SKEW
		ci.draw_line(Vector2(line_x - inner * 0.5, r.end.y - 80), Vector2(line_x + inner * 0.5, r.end.y - 80), UI.fa(ink, 0.3), 1.0)
		var fl := UI.fit_line(f, str(od.name), 28, inner - 6.0, 22)
		var name_x := r.get_center().x - skew * 0.5 + 44.0 * HS.SKEW
		UI.text_at(ci, f, Vector2(name_x, r.end.y - 44), fl[0], fl[1], ink, "mm", true)
		_btn(r, i)
	if n > cap:
		# 滚动箭头 + 位置（左右各一枚，点一下翻一张；灰 = 到头了）
		var my: float = float(gm.y) + height * 0.5
		for d in [-1, 1]:
			var can: bool = pick_scroll > 0 if d < 0 else pick_scroll + cap < n
			var ar := Rect2(PICK_X0 - 18.0 if d < 0 else PICK_X1 - 22.0, my - 34.0, 40.0, 68.0)
			HS.para(ci, ar, Color(0.0, 0.0, 0.0, 0.62 if can else 0.3), UI.fa(HS.CYB, 0.9) if can else Color(1, 1, 1, 0.12), 1.5)
			_arrow(ar.get_center(), d, HS.CYB if can else Color(1, 1, 1, 0.2))
			if can:
				_btn(ar, "scroll_l" if d < 0 else "scroll_r")
		UI.text_at(ci, f, Vector2((PICK_X0 + PICK_X1) * 0.5, gm.y + height + 22.0), "%d–%d / %d" % [pick_scroll + 1, mini(n, pick_scroll + cap), n], 14, UI.fa(Color.WHITE, 0.6), "mm")
	if sel < n:
		HS.reveal = minf(HS.reveal, 1.0 if UM.rm() else clampf((_now() - _mode_t0) / 0.5, 0.0, 1.0))
		var od2 := _card(choices[sel])
		var by := HS.title_block(ci, f, Vector2(820, _p(130, 100)), "01", "人事调度", od2.name, od2.en, 1.0, int(_p(64, 52)))
		_class_icon(ci, od2.cls, Vector2(846, by + 50), 22.0, HS.INK, 4.0)
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
		var fy0 := by + _p(92, 84) - 6.0
		_figure(od2, Rect2(1066.0, fy0, 198.0, D.y - 130.0 - fy0), 3.0, Color(0.16, 0.17, 0.21))
		if not _phone:
			UI.text_at(ci, f, Vector2(820, D.y - 112), "指定 1 名未招募干员加入名册，招募后显示干员立绘。", 14, HS.INK, "lm")
		HS.reveal = 1.0
	_bottom("" if Pad.touch or n <= cap else "方向键 / 滚轮翻页")
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
	UI.text_at(ci, g.font, br.get_center(), "跳过", 17, UI.TEXT, "mm", true)
	UI.btn_key(ci, g.font, br, "ESC", UI.SUB, 10, br.size.y * HS.SKEW + 12.0)   # 10-31 TA H7
	_btn(br, "skip")


func _draw_bag() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var t := _now() - t0
	var dt := clampf(_now() - _bag_last, 0.0, 0.1)
	_bag_last = _now()
	if _burst_t >= 0.0 and _now() - _burst_t >= 0.45:
		if ten and not ten_first:
			_summary()   # 常规十连：光炸后一屏展开十张（不逐个揭示）
			HS.backdrop(g.hud, D)
			_draw_summary10()
			return
		_op(0)
		_draw_op()
		return
	# 开包进度：拖动中由 input 直接写；按住键匀速拉开；松手后走向 _open_to（拉开 2.4 / 秒、弹回 3 / 秒）
	if t >= ZIP0 and _burst_t < 0.0:
		if _okey:
			_open = minf(1.0, _open + dt * OPEN_KEY)
		elif _odrag.is_empty() and _open_to >= 0.0:
			_open = move_toward(_open, _open_to, dt * (2.4 if _open_to > 0.5 else 3.0))
			if _open_to < 0.5 and _open <= 0.0:
				_open_to = -1.0
		if _open >= 1.0:
			_open = 1.0
			_burst_t = _now()
			_odrag = {}
			_okey = false
			_burst_sfx()
	var s := clampi(int(roundf(_open * 7.0)), 0, 7)
	if s != _zip_s:
		Sfx.play("hh_zip", -7.0, (0.9 + 0.06 * s) if s > _zip_s else (0.72 + 0.04 * s), 0.02)   # 拉开升调、合上降调
		_zip_s = s
	_hum_set(_open if _burst_t < 0.0 else 0.0)
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
	# 开口的光把台面也照亮一点（随进度）
	if _open > 0.0:
		ci.draw_set_transform(_off + ground * _k, 0.0, Vector2(_k, _k * 0.3))
		ci.draw_circle(Vector2.ZERO, 260.0 * (0.6 + 0.4 * _open), UI.fa(_burst_col(), 0.12 * _open))
		ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	ci.draw_set_transform(_off + ground * _k, 0.0, Vector2(_k, _k * 0.18))
	ci.draw_circle(Vector2.ZERO, BAG_SZ.x * sc * 0.5 * clampf(drop, 0.2, 1.0), Color(0, 0, 0, 0.45))
	ci.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	if t < ZIP0:
		_blit(A.tex("ui_hh_bag"), 0 if t < 0.32 else (1 if t < 0.36 else 2), BAG_SZ, BAG_O, pos, sc)
	else:
		var tl := (pos - BAG_O * sc).round()
		var la := (tl + FX_AT * sc).round()
		var lit: Array = _light(int((t - ZIP0) * 12.0) % 24, maxi(1, s)) if _open > 0.01 else [null, null]
		var lc := Color(1, 1, 1, clampf(_open * 1.6, 0.0, 1.0))   # 光随开口亮起、往回拖时一起收回
		if lit[0] != null:
			ci.draw_texture_rect(lit[0], Rect2(la, FX_SZ * sc), false, lc)
		_blit(A.tex("ui_hh_bag_zip"), s, BAG_SZ, BAG_O, pos, sc)
		if lit[1] != null:
			ci.draw_texture_rect(lit[1], Rect2(la + Vector2(FX_CROP.position) * sc, Vector2(FX_CROP.size) * sc), false, lc)
		_blit(A.tex("ui_hh_bag_zip_front"), s, BAG_SZ, BAG_O, pos, sc)
	ci.draw_rect(Rect2(40, 34, 3, 64), UI.TEXT)
	UI.text_at(ci, f, Vector2(64, 48), "寻访", 26, UI.TEXT, "lm", true)
	ci.draw_rect(Rect2(64, 74, 140, 1.5), UI.TEXT)
	HS.spaced(ci, f, Vector2(64, 98), "PERSONNEL", 13, UI.TEXT, 5.0)
	if _burst_t < 0.0 and t >= ZIP0 * 0.5:
		# 提示：箭头左右轻摆（拖动中停摆），下面一条进度条，中点刻度 = 过了松手就自动拉开
		var sw := 0.0 if UM.rm() or not _odrag.is_empty() else sin(_now() * 4.0) * 8.0
		var hx := D.x / 2.0 + sw
		var ha := 1.0 - _open * 0.6
		ci.draw_line(Vector2(hx - 160, D.y - 66), Vector2(hx - 70, D.y - 66), UI.fa(UI.TEXT, ha), 3.0)
		ci.draw_polyline(PackedVector2Array([Vector2(hx - 146, D.y - 78), Vector2(hx - 160, D.y - 66), Vector2(hx - 146, D.y - 54)]), UI.fa(UI.TEXT, ha), 3.0)
		HS.spaced(ci, f, Vector2(hx - 50, D.y - 58), "按住确认键拉开拉链" if Pad.using else "按住向左拖，拉开拉链", 18, UI.fa(UI.TEXT, ha), 6.0)
		var pr := Rect2(D.x / 2.0 - 200, D.y - 36, 400, 4)
		ci.draw_rect(pr, Color(1, 1, 1, 0.15))
		ci.draw_rect(Rect2(pr.end.x - pr.size.x * _open, pr.position.y, pr.size.x * _open, pr.size.y), UI.fa(_burst_col(), 0.9))
		ci.draw_rect(Rect2(pr.get_center().x - 1, pr.position.y - 3, 2, 10), Color(1, 1, 1, 0.35))
	# 光炸：档位色铺满再转白，再退（docs/124 §10.2）
	if _burst_t >= 0.0:
		var a := 0.0
		var c: Color = _burst_col()
		var bt := _now() - _burst_t
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
	if lt >= (TEN_OP_T if ten else OP_T):
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
	_class_icon(ci, od.cls, Vector2(1000, 250), 150.0, UI.fa(col.darkened(0.2), 0.45), 28.0)
	HS.outline_px(ci, Vector2(440 - drift, D.y - 270), od.en, 28.0, Color(1, 1, 1, 0.16), HS.DARK)
	# 立绘：滑入（3 道残影）→ 信号解码 → 待机循环；网点投影
	_reveal_figure(od, lt)
	# 左：浅灰名牌（滑入）
	var e := UM.out_cubic(lt / 0.4)
	ci.draw_set_transform(_off + Vector2(-(1.0 - e) * 480.0, 0) * _k, 0.0, Vector2(_k, _k))
	var py := _p(0.0, -60.0)   # 手机：名牌整体上移
	HS.fill(ci, PackedVector2Array([Vector2(0, 48), Vector2(460, 48), Vector2(460 - 0.262 * (D.y - 108), D.y - 60), Vector2(0, D.y - 60)]), HS.LIGHT)
	_class_icon(ci, od.cls, Vector2(110, 190 + py * 0.6), 40.0, HS.INK, 7.0)
	ci.draw_rect(Rect2(186, 152 + py * 0.6, 2, 76), HS.INK)
	HS.spaced(ci, f, Vector2(214, 176 + py * 0.6), CLASS_EN[od.cls], 13, HS.INK, 8.0)
	UI.text_at(ci, f, Vector2(212, 212 + py * 0.6), od.cls, 40, HS.INK, "lm", true)
	_stars(ci, Vector2(214 + UI.cwidth(f, od.cls, 40) + 26.0, 214 + py * 0.6), Roster.rarity(res.id), 9.0, _rar_col(Roster.rarity(res.id)), HS.INK)   # 原作星数（10-26）
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
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return
	# 立绘区（桌面 / 手机各一块，名牌与右缘斜带之间；顶栏之下、底边之上）：立绘按 bb 等比缩到装得下，最多 6 倍 @2x 像素，整个人不出框
	var area := Rect2(560.0, _p(86.0, 70.0), 520.0, D.y - 70.0 - _p(86.0, 70.0))
	var kk: float = minf(minf(area.size.x / bb.size.x, area.size.y / bb.size.y), 6.0 * 2.0 / hi * float(od.ds))
	var sz := (bb.size * kk).round()
	var fr := 0 if lt < DECODE else _idle_frame(od, lt - DECODE)
	var src := Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var slide := UM.out_cubic(lt / SLIDE)
	var dst := Rect2(Vector2(area.get_center().x - roundf(sz.x / 2.0) + roundf((1.0 - slide) * 520.0), area.end.y - sz.y), sz)
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


# ---------------------------------------------------------------- 稀有度（原作星数，Roster.rarity）

## 卡面 / 星 / 光的颜色：所有干员统一同一种金橙（10-26 用户：「德克萨斯的颜色不要和别的干员不一样，所有干员用一个颜色」）；
## 星数仍按原作（Roster.rarity），只是不再按稀有度换色
const CARD_COL := Color8(255, 140, 40)


func _rar_col(_r: int) -> Color:
	return CARD_COL


func _burst_col() -> Color:
	return BURST_COL


## 一排星（中心在 c 左起，r = 外半径）：像素风五角星，带 1 像素描边
func _stars(ci: CanvasItem, c: Vector2, n: int, r: float, col: Color, line: Color) -> void:
	for i in n:
		var o := c + Vector2(i * r * 2.3, 0)
		var pts := PackedVector2Array()
		for k in 10:
			var ang := -PI / 2.0 + k * PI / 5.0
			var rr := r if k % 2 == 0 else r * 0.45
			pts.append((o + Vector2(cos(ang), sin(ang)) * rr).round())
		HS.fill(ci, pts, col)
		pts.append(pts[0])
		ci.draw_polyline(pts, line, 1.0)


# ---------------------------------------------------------------- 新手十连 · 十人总览（10-26 用户：模仿原作十连结果屏）

## 十连总览（10-26 用户第二版：「人物大小不一，全部用大号的；画面更有设计感」，参照原作十连结算屏）：
## 暗底 + 中心暖光 + 斜向光带 + 上浮像素尘；十张竖卡依次从上方落入（每张晚 0.09 秒），卡内稀有度色自下而上渐亮 + 竖向光柱微微闪动 +
## 职业大水印；干员一律按同一倍数（精细 @2x，按画布统一，不按各自包围盒缩放）画在同一条脚底线上、裁在本卡内（长武器裁掉，不压相邻卡）；
## 名牌：顶线、星级一行、中文名大字、英文小字；每张卡落定后一道斜向闪光扫过（所有干员同一配色、同一套光效）
const SUM_K := 2.6            # 十连总览的统一立绘倍数（每个 @2x 像素占的设计单位，手机 ×0.9）


## 常规十连的出场顺序：按稀有度从低到高（同稀有度保持抽到的顺序），最高稀有度最后落入
func _ten_order(rs: Array) -> Array:
	var out: Array = []
	for rar in range(1, 7):
		for r in rs:
			if Roster.rarity(str(r.id)) == rar:
				out.append(r)
	return out


## 常规十连的最后一张单独强调（多等 TEN_HOLD 再落入）；新手十连照旧等间隔
func _emph(i: int, n: int) -> bool:
	return ten and not ten_first and n > 1 and i == n - 1


## 第 i 张卡开始落入的时刻（相对总览开始）
func _drop_at(i: int, n: int) -> float:
	return 0.09 * i + (TEN_HOLD if _emph(i, n) else 0.0)


func _sum_done() -> bool:
	return UM.rm() or UM.skip_all() or _now() - t0 >= _drop_at(results.size() - 1, results.size()) + 1.1


## 点一下：总览直接到终态（剩下的翻卡声不再补放）
func _sum_finish() -> void:
	t0 = _now() - (_drop_at(results.size() - 1, results.size()) + 1.1)
	_flip_n = results.size() + 1


func _draw_summary10() -> void:
	var ci: CanvasItem = g.hud
	var f: Font = g.font
	var t := 99.0 if (UM.rm() or UM.skip_all()) else _now() - t0
	var n := results.size()
	var any6 := false
	for r in results:
		if Roster.rarity(str(r.id)) >= 6:
			any6 = true
	var warm: Color = _rar_col(6 if any6 else 5)
	# ---- 背景：暗底、中心暖光（同心圆叠加）、三道斜向光带缓慢平移、上浮的像素尘
	var full := Rect2(-_off / _k, D + _off * 2.0 / _k)
	ci.draw_rect(full, Color8(9, 11, 16))
	for k in 7:
		ci.draw_circle(Vector2(D.x / 2.0, D.y * 0.42), 640.0 - k * 80.0, UI.fa(warm, 0.022 + k * 0.004))
	var drift := 0.0 if UM.rm() else fmod(t * 18.0, 260.0)
	for k in 3:
		var bx := 180.0 + k * 420.0 + drift
		HS.fill(ci, PackedVector2Array([Vector2(bx, 0), Vector2(bx + 90, 0), Vector2(bx - 150, D.y), Vector2(bx - 240, D.y)]), UI.fa(warm, 0.035))
	for k in 46:
		var hsh := absi(hash([k, 77]))
		var px := float(hsh % 1280)
		var sp := 14.0 + float(hsh % 23)
		var py := D.y - fmod((0.0 if UM.rm() else t) * sp + float(hsh % 997), D.y + 40.0)
		var sz := 2.0 + float(hsh % 3)
		ci.draw_rect(Rect2(px, py, sz, sz), UI.fa(warm if k % 3 else Color.WHITE, 0.10 + 0.05 * float(hsh % 4)))
	HS.outline_px(ci, Vector2(30, D.y - _p(196.0, 176.0)), "RECRUITMENT", 9.0, Color(1, 1, 1, 0.05), Color8(9, 11, 16))
	HS.topbar(ci, f, D, ["PERSONNEL /", "RECRUITMENT"], "寻访结果", 1.0, "%02d / %02d" % [n, Roster.TEN], "")
	# ---- 十张卡
	var gap := 6.0
	var x0 := 22.0
	var cw := (D.x - x0 * 2.0 - gap * (n - 1)) / maxf(1.0, n)
	var y0 := _p(80.0, 72.0)
	var ch := D.y - 88.0 - 12.0 - y0
	var np_h := _p(98.0, 86.0)
	var k2 := SUM_K * (0.9 if _phone else 1.0)
	# 翻卡声：每张落定时一下，音高逐张升；全部落定 0.3 秒后收尾和弦（只响一次）
	while _flip_n < n and t - _drop_at(_flip_n, n) >= 0.12:
		Sfx.play("hh_card", -8.0, 0.92 + 0.035 * _flip_n, 0.0)
		if _emph(_flip_n, n):
			Sfx.play("hh_star6", -9.0, 1.0, 0.0)   # 常规十连最后一张：落定时叠一串上行钟音
		_flip_n += 1
	if _flip_n == n and t >= _drop_at(n - 1, n) + 0.54:
		_flip_n += 1
		Sfx.play("hh_done", -6.0, 1.0, 0.0)
	for i in n:
		var r: Dictionary = results[i]
		var od := _card(r.id)
		var rar := Roster.rarity(r.id)
		var rc := _rar_col(rar)
		var lt := t - _drop_at(i, n)
		var e := UM.out_cubic(lt / 0.45)
		var emph := _emph(i, n)
		if e <= 0.0:
			if emph and t > _drop_at(i - 1, n) + 0.2:
				# 最后一张落下之前：空位四角框呼吸，提示还有一张
				var er := Rect2(x0 + i * (cw + gap), y0, cw, ch)
				var pa := 0.6 if UM.rm() else 0.45 + 0.4 * sin(t * 14.0)
				_brackets(er.grow(-6.0), UI.fa(rc, pa), 16.0, 2.0)
			continue
		var a := clampf(e * 1.5, 0.0, 1.0)
		var rr := Rect2(x0 + i * (cw + gap), y0 - (1.0 - e) * 46.0, cw, ch)
		var fig := Rect2(rr.position, Vector2(rr.size.x, rr.size.y - np_h))
		# 卡底：深色 + 稀有度色自下而上渐亮（12 段像素色块）+ 竖向光柱（闪动）
		ci.draw_rect(rr, Color(0.06, 0.07, 0.1, 0.96 * a))
		for k in 12:
			var yb := roundf(fig.end.y - fig.size.y * k / 12.0)
			var yt := roundf(fig.end.y - fig.size.y * (k + 1) / 12.0)
			ci.draw_rect(Rect2(fig.position.x, yt, fig.size.x, yb - yt), UI.fa(rc, (0.34 - k * 0.028) * a))
		var pul := 0.0 if UM.rm() else 0.06 * sin(t * 3.0 + i * 0.9)
		ci.draw_rect(Rect2(fig.get_center().x - cw * 0.22, fig.position.y, cw * 0.44, fig.size.y), UI.fa(rc, (0.10 + pul) * a))
		ci.draw_rect(Rect2(fig.get_center().x - cw * 0.06, fig.position.y, cw * 0.12, fig.size.y), UI.fa(Color.WHITE, (0.05 + pul * 0.5) * a))
		_class_icon(ci, od.cls, Vector2(fig.get_center().x, fig.position.y + fig.size.y * 0.4), cw * 0.42, UI.fa(rc, 0.16 * a))
		# 干员：统一倍数、同一脚底线、裁在本卡
		_figure_k(od, Vector2(fig.get_center().x, fig.end.y - 8.0), k2, fig, _idle_frame(od, t), a)
		# 顶部：稀有度色条 + 职业徽（菱形底）+ NEW
		ci.draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, 3.0), UI.fa(rc, a))
		var bc := Vector2(rr.position.x + rr.size.x - 16.0, rr.position.y + 20.0)
		HS.fill(ci, PackedVector2Array([bc + Vector2(0, -13), bc + Vector2(13, 0), bc + Vector2(0, 13), bc + Vector2(-13, 0)]), UI.fa(Color(0.04, 0.05, 0.07), 0.85 * a))
		_class_icon(ci, od.cls, bc, 9.0, UI.fa(Color.WHITE, a))
		HS.tag(ci, f, rr.position + Vector2(6.0, 10.0), "NEW", 0.68, HS.YEL)
		# 名牌：深底、稀有度顶线、星级一行、中文名大字、英文小字
		var nr := Rect2(rr.position.x, rr.end.y - np_h, rr.size.x, np_h)
		ci.draw_rect(nr, Color(0.035, 0.04, 0.055, 0.98 * a))
		ci.draw_rect(Rect2(nr.position.x, nr.position.y, nr.size.x, 2.0), UI.fa(rc, a))
		var sr := 5.0 if cw < 112.0 else 5.5
		_stars(ci, Vector2(nr.get_center().x - (rar - 1) * sr * 1.15, nr.position.y + 15.0), rar, sr, rc, Color(0, 0, 0, 0.6 * a))
		var fl := UI.fit_line(f, str(od.name), int(_p(22, 20)), nr.size.x - 10.0, 12)
		UI.text_at(ci, f, Vector2(nr.get_center().x, nr.position.y + np_h * 0.5), fl[0], fl[1], UI.fa(Color.WHITE, a), "mm", true)
		var en := UI.fit_line(f, od.en, 8, nr.size.x - 12.0, 6)
		UI.text_at(ci, f, Vector2(nr.get_center().x, nr.end.y - 13.0), en[0], en[1], UI.fa(rc.lerp(Color.WHITE, 0.4), 0.85 * a), "mm")
		ci.draw_rect(rr, UI.fa(rc, 0.5 * a), false, 1.0)
		# 落入白闪；6★ 落定后斜向闪光扫过一次
		if lt < 0.3:
			ci.draw_rect(rr, UI.fa(Color.WHITE, (1.0 - lt / 0.3) * (0.85 if emph else 0.55)))
		if emph:
			# 常规十连最后一张（最高稀有度）：外圈稀有度色描边常亮、缓慢呼吸，落定时向外扩一圈
			var ga := 0.75 if UM.rm() else 0.55 + 0.3 * sin(t * 3.2)
			ci.draw_rect(rr.grow(3.0), UI.fa(rc, ga * a), false, 2.0)
			if lt > 0.3 and lt < 0.9:
				var q := (lt - 0.3) / 0.6
				ci.draw_rect(rr.grow(3.0 + 18.0 * UM.out_cubic(q)), UI.fa(rc, (1.0 - q) * 0.8), false, 2.0)
		if lt > 0.45 and lt < 1.05:
			var gx := lerpf(rr.position.x - 40.0, rr.end.x + 40.0, (lt - 0.45) / 0.6)
			var gl := PackedVector2Array([Vector2(gx, rr.position.y), Vector2(gx + 18.0, rr.position.y), Vector2(gx - 22.0, rr.end.y - np_h), Vector2(gx - 40.0, rr.end.y - np_h)])
			var ok := true
			for q in gl:
				ok = ok and q.x >= rr.position.x - 1.0 and q.x <= rr.end.x + 1.0
			if ok:
				HS.fill(ci, gl, UI.fa(Color.WHITE, 0.35))
	HS.bottom_bar(ci, D, 88)
	var cls_n := {}
	for r in results:
		cls_n[Roster.class_of(r.id)] = true
	UI.text_at(ci, f, Vector2(48, D.y - 44), "%d 名干员已加入名册（覆盖 %d 个职业），可在编队界面设为队长。" % [n, cls_n.size()], 16, UI.TEXT, "lm")
	var br := Rect2(D.x - 330, D.y - 74, 310, 60)
	HS.main_btn(ci, f, br, "完成", "" if Pad.touch else "Enter")
	_btn(br, "ok")


## 统一倍数画立绘：k2 = 每个 @2x 像素占的设计单位（再乘干员自己的 draw_scale），脚底点 foot，裁进 clip
func _figure_k(od: Dictionary, foot: Vector2, k2: float, clip: Rect2, frame := 0, a := 1.0) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	var kk: float = k2 * 2.0 / hi * float(od.ds)
	var dst := Rect2(UI.foot_pos(foot, bb, fw, tx.get_height(), hi, kk).round(), (bb.size * kk).round())
	var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	UI.blit_clipped(g.hud, tx, dst, src, clip, Color(1, 1, 1, a))


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
		_class_icon(ci, od.cls, Vector2(cx + 28, rr.position.y + 46), 22.0, Color.WHITE, 4.0)
		HS.spaced(ci, f, Vector2(cx - 6, rr.position.y + 94), CLASS_EN[od.cls], 9, UI.fa(Color.WHITE, 0.7), 3.0)
		UI.text_at(ci, f, Vector2(cx + 26, rr.position.y + 118), od.cls, 24, Color.WHITE, "mm", true)
		var nr := Rect2(rr.position.x + 10, rr.end.y - _p(132, 104), rr.size.x - 22, _p(112, 92))
		var fy := rr.position.y + _p(134.0, 126.0)
		_figure(od, Rect2(rr.position.x + 14.0, fy, rr.size.x - 28.0, nr.position.y - 10.0 - fy), _p(2.5, 2.0), Color(0, 0, 0, 0), _idle_frame(od, t))
		HS.para(ci, nr, HS.LIGHT)
		HS.tag(ci, f, nr.position + Vector2(30, -12), "新职业" if bool(r.get("new_class", false)) else "新加入", 0.9)
		var fl := UI.fit_line(f, str(od.name), 34, nr.size.x - 40, 16)
		UI.text_at(ci, f, Vector2(nr.get_center().x, nr.position.y + nr.size.y * 0.41), fl[0], fl[1], HS.INK, "mm", true)
		ci.draw_line(Vector2(nr.position.x + 50, nr.position.y + nr.size.y * 0.66), Vector2(nr.end.x - 50, nr.position.y + nr.size.y * 0.66), HS.INK2, 1.0)
		HS.spaced(ci, f, Vector2(nr.get_center().x - UI.cwidth(f, od.en, 10) * 0.9, nr.position.y + nr.size.y * 0.875), od.en, 10, HS.INK2, 6.0)
	HS.bottom_bar(ci, D, 88)
	var left := _vouchers()
	var more: bool = (left > 0 or _can_direct()) and not Roster.locked_ids().is_empty()
	UI.text_at(ci, f, Vector2(64, D.y - 44), "已加入名册。新干员可在编队界面设为队长。" + ("   剩余寻访凭证 × %d" % left if more else ""), 16, UI.TEXT, "lm")
	var br := Rect2(D.x - 330, D.y - 74, 310, 60)
	HS.main_btn(ci, f, br, "继续寻访" if more else "完成", "")
	_btn(br, "ok")
