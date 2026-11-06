extends RefCounted
## 新手引导（docs/219，11-01 用户改口径）：问一次 + 1–2 分钟演示局 + 正式局里第一次碰到时弹提示卡（带实时小演示）。取代首局聚光框引导。
## 1. 问一次：首局开场结束后（intro.end_opening）暂停局内弹问题框「玩过《吸血鬼幸存者》这类游戏吗？」玩过 / 没玩过 / 跳过引导，
##    结果存 Cfg.onboard（"" 未问 / new / vet / off），设置「操作 · 新手引导」可改。
## 2. 没玩过（new）：先走演示局（drill）——移动与自动攻击 → 捡经验升级三选一（身边放经验结晶）→ 招募一名队友（直接弹招募画面）
##    → 放一次终结技（直接充满）→「演示结束」，2.5 秒后重开进正式局（同一套开局配置）。演示局怪少（onboard/density）、敌伤低（onboard/enemy_dmg），
##    最晚 onboard/drill_max 秒强制结束；每张卡的「跳过演示」直接进正式局。
## 3. 正式局（两条线共用）：灯火 / 商人 / Boss / 小队与队长 / 指挥圆盘 / 终结技 / 连携 / 溟痕与引航灯标 / 节点卡，第一次碰到时弹提示卡。
## 每张卡只出一次（Cfg.onboard_seen）。卡片不暂停、不拦输入（只拦「跳过」按钮），只在 PLAY 状态显示。演示图鉴：暂停菜单「演示」，←/→ 翻全部卡。
## 只在真人对局生效（机器人 / 自动测试 / 演练 / 练习 / 图鉴演示不进，同 seed 不变）。
## 强制（docs/219 §6，11-02 用户「第一把开局的指南设置成不能跳过」）：本机和云存档都没有完成记录（Cfg.onboard_done）时，两条线都走演示局
##   （没玩过 drill / 玩过 drill_vet：小队、连携、终结技、指挥圆盘），问题框不给「跳过引导」、Esc 不选、卡上没有「跳过」；
##   演示局最长 onboard/drill_max 秒。暂停菜单照常可用，中途退出不算完成，下次进来从头。走完记 onboard_done（随云存档同步），之后照常可跳过。
## 测试 / 录片：--onboard=new|vet|ask|view（自动测试局里也走引导，不读不写存档；ask = 先弹问题框，2.4 秒后自动选「没玩过」；
##   测试里演示局结束时直接退出，不重开；new / vet / ask 按第一次进游戏的强制版走，加 --onboardfree 走可跳过版；
##   强制版里机器人不会用圆盘、按 Q，到点由这里代按）、--onboarddemo=<卡 id>（进局即出该卡，常驻不收起）。文案在 data/onboard.json，演示画法在 screens/onboard_demos.gd。

const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Demos = preload("res://scripts/screens/onboard_demos.gd")
const Character = preload("res://scripts/characters/character.gd")
const LinkV2 = preload("res://scripts/run/link_v2.gd")
const PlayKeys = preload("res://scripts/core/play_keys.gd")

## 指挥台开着时（v3）卡片 / 问题框按属性面板画（11-07 用户「开局指南卡要不要改成面板风格 要的」，docs/300）：
## 深底 + 白直角刻度、标题（Heavy）+ 灰英文小签 + 细分隔线与白短条、细线进度条、灰字小按钮；可操作的仍是青
const W3 := Color(0.925, 0.933, 0.941)
const G3 := Color(0.588, 0.612, 0.643)
const INFO_SECS := 9.0       # 看完自动收起的卡（hint 为空）停留秒数
const MOVE_NEED := 450.0     # 「移动」做完：累计移动像素
const XP_DIST := 170.0       # 演示局「经验与升级」：经验结晶放在队长身边多远（拾取半径之外，要走过去）
const END_SECS := 2.5        # 演示局「演示结束」卡停留几秒后进正式局
const ACT_SECS := 40.0       # 特有系统的动作卡（指挥 / 终结技）等这么久没做也收起，不挡后面的卡
const MIN_SHOW := 4.0        # 每张卡至少显示几秒（动作做得快也让人看完一句话；期间做完的动作照算）
const GAP := 1.6             # 两张卡之间至少隔几秒
const DRILL_MIN := 2.5       # 演示局里每张卡至少显示几秒（强制部分 ≤ 90 秒，节奏紧凑）
const DRILL_GAP := 0.6       # 演示局里两张卡之间隔几秒
const PACK_N := 10          # 演示局「部署」：从一侧涌来的怪
const PACK_D := 400.0        # 这群怪离队长多远出现（屏内靠边：看得见涌来、看得见队友过去挡）
const LINK_PACK := 8         # 演示局「连携」：在队长身边放几只怪
const LINK_NUDGE := 3.0      # 演示局「连携」：这么久队长还没放出技能就直接触发连携
const LINK_WAIT := 10.0      # 演示局「连携」：充满队长技力后等这么久还没连携（附近没敌人）就往下走
const BEACON_DIST := 240.0   # 演示局「引航灯标」：灯标放在队长身边多远（走几步就到，光圈半径 70）
const BEACON_WAIT := 24.0    # 等这么久还没点燃就由引导代点亮（演示一遍效果），不让人卡在这一步
const BEACON_MIRES := 3      # 灯标周围放几片溟痕（点燃后退散，看得见效果）
const FOCUS_DIST := 380.0    # 演示局「集火」：精英放在队长身边多远（圆盘选点范围内，屏内）
const FOCUS_WAIT := 24.0     # 等这么久还没下集火就由引导代下一次
const FOCUS_HP_K := 8.0      # 精英生命 ×：别被自动攻击提前打死
const STEP_TRIES := 2        # 灯标 / 精英刷不出来或被打掉：最多重放几次，再不行就跳过这一步
const MATE_FALLBACK := ["saria", "exusiai", "texas", "silverash", "ptilopsis"]

var g: Game
var data: Dictionary = {}
var mode := ""               # 本局生效的线：new / vet / ""（不引导）
var dev := ""                # --onboard=…：测试用，不读不写存档
var demo_id := ""            # --onboarddemo=<id>
var seen_mem: Array = []     # 测试模式下的「已出过」（不进存档）
var drill := false           # 演示局进行中
var drill_left := -1.0       # 「演示结束」卡出现后的倒计时（≥ 0 时到 0 进正式局）
var forced := false          # 第一次进游戏：引导不可跳过（docs/219 §6）
var _nudged := false
var demo_beacon = null        # 演示局「引航灯标」：放出来的那座灯标（字典，g.beacons 里同一个）
var beacon_tries := 0
var focus_tgt = null          # 演示局「集火」：放出来的精英
var focus_tries := 0
var _focus_given := false     # 玩家（或引导代做）已经下过集火
var _skip_beacon := false     # 「引航灯标」刷不出来：这一步直接跳过
var _skip_focus := false      # 「集火」刷不出精英 / 编队不能下令：这一步直接跳过
var pack_dir := Vector2.RIGHT   # 演示局「部署」：怪群从哪一侧来（世界方向）
var drill_t0 := -1.0         # 演示局开始的局内时刻（强制部分时长）
static var _reloaded := false   # --onboardreload：演示局结束后已重开过场景

var cur := ""                # 当前卡
var cur_t := 0.0             # 当前卡在 PLAY 状态下已显示的秒数
var out_id := ""             # 正在收起的卡（做完：打勾后滑出）
var out_t := -1.0
var gap_t := 0.0
var moved := 0.0
var _last_p := Vector2.INF
var ev := {}                 # 事件计数：oil / wheel
var ev0 := {}                # 当前卡开始时的事件计数
var recruit_t := -1.0        # 第一次编队 ≥ 2 人的局内时刻
var beacons0 := 0
var lv0 := 1                 # 当前卡开始时的等级（「经验与升级」：升过一级才算）
var skip_rect := Rect2()
var now := 0.0               # 真实秒（演示动画用）

var ask_on := false
var ask_sel := 1
var ask_t := 0.0
var ask_rects: Array = []
var _ask_shot := false

var view_on := false
var view_i := 0
var view_t := 0.0
var view_back := 0
var view_rects := {}


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open("res://data/onboard.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			data = d
	for a in Cfg.dev_args():
		if a.begins_with("--onboard="):
			dev = a.substr(10)
		elif a.begins_with("--onboarddemo="):
			demo_id = a.substr(14)
	if _reloaded:
		dev = ""   # --onboardreload：演示局结束重开后按走完处理，进正式局
		print("ONBOARD reloaded")


func _dev_arg(key: String, def: String) -> String:
	for a in Cfg.dev_args():
		if a.begins_with(key):
			return a.substr(key.length())
	return def


# ---------------------------------------------------------------- 开局

## 只在真人对局里引导（测试开关 --onboard 例外）
func eligible() -> bool:
	if dev != "" or demo_id != "":
		return true
	return g.mode == g.Mode.PLAY and not g.trial.active and g.demo_op == "" and not Cfg.practice_active


## 开场结束时调（intro.end_opening）：返回 true = 引导接管（不再弹旧的聚光框引导）
func begin() -> bool:
	if not eligible():
		return false
	if demo_id != "":
		mode = "vet"
		_show(demo_id)
		return true
	var m: String = dev if dev != "" else str(Cfg.onboard)
	forced = _first_time()
	if forced:
		if dev == "":
			m = ""   # 没走完过：不管设置里选了什么，从问题框重新开始
			for id in all_ids() + ["drill", "drill_end"]:   # 上次中途退出：演示局从头走
				Cfg.onboard_seen.erase(id)
		elif m not in ["new", "vet"]:
			m = "ask"
	if m == "view":
		open_viewer()   # --onboard=view：直接打开演示图鉴（截图用；--onboardview=<序号> 定在第几张）
		for a in Cfg.dev_args():
			if a.begins_with("--onboardview="):
				view_i = int(a.substr(14))
		return true
	if m == "" or m == "ask":
		_open_ask()
		return true
	_setup(m)
	return true


## 第一次进游戏（本机和云存档都没有完成记录）：引导强制走完
func _first_time() -> bool:
	if dev != "":
		return dev in ["new", "vet", "ask"] and not Cfg.dev_args().has("--onboardfree")
	return not Cfg.onboard_done


func _setup(m: String) -> void:
	mode = m if m in ["new", "vet"] else ""
	if dev == "":
		Cfg.seen_intro = true   # 新引导取代旧的聚光框引导
		if mode != "":
			for id in ["levelup", "lamp", "boss"]:   # 旧到点小提示里这三条由演示局 / 提示卡覆盖
				if not Cfg.seen_tips.has(id):
					Cfg.seen_tips.append(id)
		Cfg.save()
	if mode != "" and not _seen("drill"):
		_drill_on()   # 玩过 / 没玩过都走演示局（玩过 = 快速版 drill_vet）


func _drill_on() -> void:
	drill = true
	drill_t0 = g.t
	g.stats.add(&"enemy_dmg", "mult", Bal.v("onboard/enemy_dmg", 0.5), "onboard")
	g.sync_stats()


func _drill_off() -> void:
	if not drill:
		return
	drill = false
	g.stats.remove_source("onboard")
	g.sync_stats()


## 演示局的怪物密度系数（spawner.density 乘上）
func dens_k() -> float:
	return Bal.v("onboard/density", 0.5) if drill else 1.0


## 演示局「招募」这一步：升级面板按保底招募画面弹（build_guide.must_recruit）
func force_recruit() -> bool:
	return drill and cur == "recruit"


## 演示局结束：记下看过，重开进正式局（测试里直接退出）
func _drill_end() -> void:
	_mark("drill")
	if forced:
		print("ONBOARD forced_done route=%s t=%.1f real=%.1f" % [mode, g.t - drill_t0, now])
		forced = false
		if dev == "":
			Cfg.onboard_done = true   # 强制部分走完：之后照常可跳过（随云存档同步）
			Cfg.save()
	_drill_off()
	cur = ""
	drill_left = -1.0
	if dev != "":
		if not Cfg.dev_args().has("--onboardreload"):
			g.get_tree().quit()
			return
		_reloaded = true   # 测试：像真人一样重开场景进正式局（11-04 教程结束闪退，之前测试一律直接退出、没走过这条路）
	# 延到帧末再重开：当场重开时旧场景立即离树，这一帧剩下的 squad / world / 音乐更新拿不到视口（get_viewport 为空），
	# 对内包里就是「教程结束以后闪退」（11-04 用户实测 a055a6bd6）
	g.get_tree().reload_current_scene.call_deferred()


func _seen(id: String) -> bool:
	return seen_mem.has(id) if dev != "" else Cfg.onboard_seen.has(id)


func _mark(id: String) -> void:
	if dev != "":
		if not seen_mem.has(id):
			seen_mem.append(id)
		return
	if not Cfg.onboard_seen.has(id):
		Cfg.onboard_seen.append(id)
		Cfg.save()


## 局内事件（指挥圆盘下令 "wheel"）
func note(what: String) -> void:
	ev[what] = int(ev.get(what, 0)) + 1


# ---------------------------------------------------------------- 卡片

func card(id: String) -> Dictionary:
	return data.get("cards", {}).get(id, {})


func text_of(id: String, touch: bool) -> String:
	var c := card(id)
	var tx: String = str(c.get("touch", c.get("text", ""))) if touch else str(c.get("text", ""))
	return tx.replace("{cmd}", key_of("command"))


## 局内按键提示（键名按 play_keys 取，手柄时给手柄键；演示卡 / 文案共用）
func key_of(action: String) -> String:
	return Pad.hint(PlayKeys.hint(action, true, false), PlayKeys.hint(action, true, true))


## 本局演示局的步骤（玩过 = 快速版 drill_vet）
func _drill_list() -> Array:
	return (data.get("drill_vet", []) as Array) if mode == "vet" else (data.get("drill", []) as Array)


## 演示局的步骤（不含「演示结束」）
func drill_ids() -> Array:
	return _drill_list().filter(func(x): return x != "drill_end")


## 演示图鉴列出的卡：演示局步骤 + 正式局提示卡（去重，不含「演示结束」）
func all_ids() -> Array:
	var out: Array = (data.get("drill", []) as Array).filter(func(x): return x != "drill_end")
	for id in data.get("tips", []):
		if not out.has(id):
			out.append(id)
	return out


## 当前该轮询的卡：演示局只走演示步骤，正式局走提示卡
func _queue_ids() -> Array:
	return _drill_list() if drill else (data.get("tips", []) as Array)


## 卡能否出现（触发条件）
func _trigger(id: String) -> bool:
	var sq: int = g.squad.size()
	if drill:
		if id == "deploy" and g.ult != null and g.ult.phase != "":
			return false   # 终结技演出完再摆怪群（余波会把它清掉）
		var lst: Array = _drill_list()   # 按顺序：前面的都做完才出
		var i: int = lst.find(id)
		for k in maxi(i, 0):
			if not _seen(str(lst[k])):
				return false
		return i >= 0
	match id:
		"lamp":
			return g.lamp < 75.0 and g.t > 5.0
		"merchant":
			return not g.merchant.is_empty()
		"boss":
			return g.spawner.boss_alive()
		"squad":
			return sq >= 2
		"command":
			return g.squad.cmd_on() and sq >= 2 and recruit_t >= 0.0 and g.t - recruit_t >= 8.0
		"ult":
			return g.ult != null and g.ult.full()
		"link":
			return g.ult != null and int(g.ult.stats.get("v2_links", 0)) > 0
		"mire":
			if g.in_mire > 0.05:
				return true
			for b in g.beacons:
				if not b.get("lit", false) and not b.get("dead", false) and b.pos.distance_to(g.ppos) < 520.0:
					return true
			return false
		"nodes":
			return int(g.telemetry.nodes) > 0
	return false


## 已经不用教了：不弹，直接记成看过（演示局里招募过 → 正式局不出小队卡；没有终结技 / 招募不了 → 演示局跳过那一步）
func _moot(id: String) -> bool:
	match id:
		"squad":
			return _seen("recruit")
		"recruit":
			return drill and g.progression.recruit_cards().is_empty() and g.squad.size() < 2
		"ult":
			return drill and g.ult == null
		"link":
			return drill and (g.squad.size() < 2 or not LinkV2.on())
		"command":
			return (drill and (g.squad.size() < 2 or not g.squad.cmd_on())) or (not drill and _seen("deploy"))   # 演示局教过部署 / 随行：正式局不再出圆盘卡
		"deploy", "regroup":
			return drill and (g.squad.size() < 2 or not g.squad.cmd_on() or not g.pick.proto_on())
		"focus":
			return drill and (g.squad.size() < 2 or not g.squad.cmd_on() or g.wheel.item_index("focus") < 0 or _skip_focus)
		"beacon":
			return drill and (Bal.v("beacon/enabled", 1.0) <= 0.0 or _skip_beacon)
	return false


## 当前卡做完了吗
func _done(id: String) -> bool:
	if demo_id != "" or id == "drill_end":
		return false
	match id:
		"move":
			return moved >= MOVE_NEED
		"xp":
			return g.level > lv0
		"recruit":
			return g.squad.size() >= 2
		"merchant":
			return g.merchant.is_empty() or g.state == Game.S.SHOP
		"command":
			return int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)) or (cur_t > ACT_SECS and not drill)
		"link":
			return _links() > int(ev0.get("links", 0)) or (drill and cur_t > LINK_WAIT)
		"deploy":
			return _deployed()
		"regroup":
			return int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)) and g.squad.order_kind == "" and g.squad.stance != g.squad.ROAM
		"ult":
			return not g.ult.full() or (cur_t > ACT_SECS and not drill)
		"mire":
			return _lit_count() > beacons0 or cur_t > 25.0
		"beacon":
			return _skip_beacon or (demo_beacon != null and bool(demo_beacon.lit))
		"focus":
			return _skip_focus or _focus_given
	return cur_t >= INFO_SECS


## 「部署」做完：部署指令在生效（落点在怪群那一侧），且至少一名队友已经走到驻扎位上（以指令实际生效为准，点了扇区不算）
func _deployed() -> bool:
	var sq = g.squad
	if sq.order_kind != "point" or sq.order_pos == Vector2.INF or (sq.order_pos - g.ppos).dot(pack_dir) <= 40.0:
		return false
	for o in sq.ops:
		if not o.is_leader and o.pos != Vector2.INF and o.cmd_down <= 0.0 and o.pos.distance_to(sq.station_of(o)) <= 48.0:
			return true
	return false


## 演示局放东西用的空地：队长身边 dist 处，朝部署怪群的侧面起转一圈 8 个方向，挑第一个放得下（没被地形挡、在缩圈里）的；都不行返回 INF
func _free_spot(dist: float, margin: float) -> Vector2:
	var a0: float = pack_dir.angle() + PI * 0.5
	for k in 8:
		var want: Vector2 = g.spawner.safe_event_pos(g.ppos + Vector2.from_angle(a0 + TAU * k / 8.0) * dist, 110.0)
		var got: Vector2 = g.map.push_out(want, margin)
		if got.distance_to(want) < 24.0 and got.distance_to(g.ppos) > dist * 0.5:
			return got
	return Vector2.INF


## 演示局「引航灯标」：队长身边放一座灯标，周围几片溟痕（点燃后退散）；放不下就跳过这一步
func _place_beacon() -> void:
	demo_beacon = null
	for b in g.beacons:
		if not b.lit and not b.dead:
			demo_beacon = b   # 场上已经有一座没点的：直接用它
			return
	var p: Vector2 = _free_spot(BEACON_DIST, 40.0)
	if p == Vector2.INF:
		_skip_beacon = true
		return
	demo_beacon = g.beacon_sys.spawn_demo(p)
	for k in BEACON_MIRES:
		var m: Dictionary = g.map.mire_new(p + Vector2.from_angle(TAU * k / BEACON_MIRES + 0.5) * 120.0, g.t, false)
		m.r = m.maxr
		m.life = 90.0
		m["boss"] = true   # 演示局灯火是满的，自然溟痕会被灯火自己退散；按 Boss 溟痕画 / 算（不吃灯火退散、伤害轻），点燃灯标时一起驱散
		g.mires.append(m)


## 演示局「集火」：队长身边放一只精英（生命加厚，别被自动攻击提前打死）；放不下就跳过这一步
func _place_focus() -> void:
	focus_tgt = null
	var p: Vector2 = _free_spot(FOCUS_DIST, 30.0)
	if p == Vector2.INF:
		_skip_focus = true
		return
	var e: Dictionary = g.spawner.new_enemy("mother", p)
	e.hp *= FOCUS_HP_K
	e.maxhp = e.hp
	g.enemies.append(e)
	focus_tgt = e


## 「引航灯标」一步每帧：灯标被熄灭 / 清掉就重放（最多 STEP_TRIES 次）；等太久没点就代点亮
func _beacon_tick() -> void:
	if _skip_beacon:
		return
	if demo_beacon == null or bool(demo_beacon.dead):
		beacon_tries += 1
		if beacon_tries > STEP_TRIES:
			_skip_beacon = true
			return
		_place_beacon()
		return
	if cur_t >= BEACON_WAIT and not bool(demo_beacon.lit):
		g.beacon_sys.light_demo(demo_beacon)


## 「集火」一步每帧：下了集火指令就算做完；精英被打掉就重放（最多 STEP_TRIES 次）；等太久没下就代下一次
func _focus_tick() -> void:
	if _skip_focus or _focus_given:
		return
	if g.squad.order_kind == "focus":
		_focus_given = true
		return
	if focus_tgt == null or bool(focus_tgt.dead):
		focus_tries += 1
		if focus_tries > STEP_TRIES:
			_skip_focus = true
			return
		_place_focus()
		return
	if cur_t >= FOCUS_WAIT:
		g.squad.apply_order("focus", focus_tgt.pos, focus_tgt)
		_focus_given = g.squad.order_kind == "focus"
		if not _focus_given:
			_skip_focus = true   # 编队不能下令（作战时限没恢复之类）：不卡在这一步


## 指挥圆盘打开时各扇区依次亮起（command_wheel.draw 读）：演示局「部署」这一步
func wheel_tour() -> bool:
	return drill and cur == "deploy"


func _links() -> int:
	return int(g.ult.stats.get("v2_links", 0)) if g.ult != null else 0


func _lit_count() -> int:
	var n := 0
	for b in g.beacons:
		if b.get("lit", false):
			n += 1
	return n


func _show(id: String) -> void:
	cur = id
	cur_t = 0.0
	lv0 = g.level
	ev0 = ev.duplicate()
	ev0["links"] = _links()
	beacons0 = _lit_count()
	if drill and demo_id == "":
		match id:
			"xp":
				# 身边放一圈经验结晶，够升一级（走过去捡）
				var need: float = maxf(1.0, g.xp_need - g.xp) * 1.15
				for k in 5:
					var dir := Vector2.RIGHT.rotated(-0.9 + k * 0.45)
					g.pickups.drop(g.ppos + dir * (XP_DIST + k * 12.0), "xp", need / 5.0)
			"recruit":
				g.pending_levelups += 1   # 下一次升级面板按保底招募画面弹（force_recruit）
			"link":
				var ld = g.squad.leader()
				if ld != null:
					ld.fill_sp()   # 队长技力充满：自动放技能，队友接连携（羁绊搭档在队时换专属合击）
				for k in LINK_PACK:   # 身边放一圈怪：技能和连携都要有目标（演示局怪少，附近常常是空的）
					var ep: Vector2 = g.map.push_out(g.ppos + Vector2.RIGHT.rotated(TAU * k / LINK_PACK) * 210.0, 12.0)
					g.enemies.append(g.spawner.new_enemy(g.spawner.pick_type(), ep))
			"deploy":
				# 固定场景：一群怪从队长右侧（离得远就换左侧，挑地图里放得下的一边）涌来，提示部署队友阻挡
				pack_dir = Vector2.RIGHT if g.map.push_out(g.ppos + Vector2.RIGHT * PACK_D, 12.0).distance_to(g.ppos + Vector2.RIGHT * PACK_D) < 40.0 else Vector2.LEFT
				for k in PACK_N:
					var ep: Vector2 = g.ppos + pack_dir * (PACK_D + (k % 2) * 40.0) + pack_dir.orthogonal() * (k - (PACK_N - 1) / 2.0) * 34.0
					g.enemies.append(g.spawner.new_enemy(g.spawner.pick_type(), g.map.push_out(ep, 12.0)))
				if g.squad.stance == g.squad.ROAM:
					g.squad.apply_command("guard")   # 从随行开始
			"ult":
				g.ult.energy = g.ult.FULL   # 终结技直接充满
			"beacon":
				beacon_tries = 0
				_skip_beacon = false
				_place_beacon()
			"focus":
				focus_tries = 0
				_skip_focus = false
				_focus_given = false
				_place_focus()
			"drill_end":
				drill_left = END_SECS
	Sfx.play("ui_move", -6.0)
	if dev != "":
		print("ONBOARD card=%s t=%.1f real=%.1f" % [id, g.t - maxf(drill_t0, 0.0), now])   # 录片 / 测试：每张卡出现的局内时刻


func _finish(skipped := false) -> void:
	if cur == "":
		return
	_mark(cur)
	out_id = cur
	out_t = 0.0 if not skipped else 0.5
	cur = ""
	gap_t = DRILL_GAP if drill else GAP
	if not skipped:
		Sfx.play("ui_ok", -6.0)


func skip_all() -> void:
	if forced:
		return   # 第一次进游戏：不可跳过
	if cur != "":
		_finish(true)
	mode = ""
	_drill_off()
	if dev == "":
		Cfg.onboard = "off"
		Cfg.save()


# ---------------------------------------------------------------- 每帧（game._process 真实 delta）

func update(dt: float) -> void:
	now += dt
	if ask_on:
		ask_t += dt
		if dev == "ask":
			if not _ask_shot and ask_t >= 1.2 and DisplayServer.get_name() != "headless":
				_ask_shot = true
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/onb_ask.png")   # 录片：问题框截图
			if ask_t >= 2.4:
				_choose(int(_dev_arg("--onboardpick=", "1")))   # 录片：--onboardpick=<序号> 选哪一项（缺省第 2 项）
		return
	if view_on:
		view_t += dt
		if dev == "view" and DisplayServer.get_name() != "headless" and view_t >= 1.6:
			# 截图：每张卡第 1.6 秒存一张 onb_view_<序号>.png，翻完退出
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/onb_view_%02d.png" % view_i)
			if view_i >= all_ids().size() - 1:
				g.get_tree().quit()
			else:
				_view_step(1)
		return
	if out_t >= 0.0:
		out_t += dt
		if out_t > 1.0:
			out_t = -1.0
			out_id = ""
	if mode == "" and cur == "":
		return
	if g.state != Game.S.PLAY:
		if cur == "merchant" and g.state == Game.S.SHOP:
			_finish()
		return
	if _last_p != Vector2.INF:
		moved += minf(g.ppos.distance_to(_last_p), 40.0)
	_last_p = g.ppos
	if recruit_t < 0.0 and g.squad.size() >= 2:
		recruit_t = g.t
	if drill_left >= 0.0:
		cur_t += dt   # 「演示结束」卡照常淡入
		drill_left -= dt
		if drill_left <= 0.0:
			_drill_end()
		return
	if drill and g.t - drill_t0 >= Bal.v("onboard/drill_max", 90.0) and cur != "drill_end":
		cur = ""
		_show("drill_end")   # 演示局拖太久：直接结束
		return
	if cur != "":
		cur_t += dt
		if forced and dev != "":
			_dev_act()
		if drill and cur == "beacon":
			_beacon_tick()
		elif drill and cur == "focus":
			_focus_tick()
		if drill and cur == "link" and cur_t >= LINK_NUDGE and not _nudged and _links() <= int(ev0.get("links", 0)):
			_nudged = true   # 有的队长技能是蓄在下一次普攻里的（水月）或要等目标：到点按「队长放了技能」触发一次连携
			var ld = g.squad.leader()
			if ld != null and g.ult != null:
				g.ult.on_skill(ld, 0)
		if cur_t >= (DRILL_MIN if drill else MIN_SHOW) and _done(cur):
			_finish()
		return
	if gap_t > 0.0:
		gap_t -= dt
		return
	for id in _queue_ids():
		if _seen(id):
			continue
		if _moot(id):
			_mark(id)
			continue
		if _trigger(id):
			_show(id)
			return


## 录片 / 自动测试的强制版：机器人不会用圆盘、按 Q，到点代按（真人局不走这里）
func _dev_act() -> void:
	if cur_t < 1.6:
		return
	match cur:
		"ult":
			if g.ult.full() and g.ult.phase == "" and g.ult.press_q():
				g.ult.release_q()
		"command":
			if int(ev.get("wheel", 0)) <= int(ev0.get("wheel", 0)):
				g.wheel.confirm(1)   # 突击
		"deploy":
			# 打开圆盘 → 看完扇区依次亮起 → 选「部署」→ 准星挪到怪群前方 → 确认
			if g.squad.order_kind == "point":
				return
			if not g.wheel.is_open and not g.pick.active and cur_t >= 1.6 and cur_t < 2.0:
				g.wheel.open()
			elif g.wheel.is_open and g.wheel.t_open >= g.wheel.TOUR_STEP * (g.wheel.ITEMS.size() + 0.6):
				g.wheel.confirm(g.wheel.item_index("point"))
			elif g.pick.active:
				g.pick._goal = g.hud_ct() * (g.ppos + pack_dir * float(_dev_arg("--onboarddeploy=", "220"))) - g.pick._offset()   # --onboarddeploy=<距离>：录片用，部署点放远一点（撤回时触发瞬回）
				if g.pick.t >= 1.3:
					g.pick.confirm()
		"beacon":
			# 机器人不会踩灯标：队长挪到灯标上，光圈自己读条点燃
			if demo_beacon != null and not bool(demo_beacon.lit) and not bool(demo_beacon.dead):
				g.ppos = demo_beacon.pos   # 每帧钉在灯标上，直到光圈读条点燃（机器人自己会走开）
				if g.ch != null:
					g.ch.pos = demo_beacon.pos
		"focus":
			# 打开圆盘 → 选「集火」→ 准星挪到精英上 → 确认
			if _focus_given or focus_tgt == null or bool(focus_tgt.dead):
				return
			if not g.wheel.is_open and not g.pick.active and cur_t >= 1.6 and cur_t < 2.0:
				g.wheel.open()
			elif g.wheel.is_open and g.wheel.t_open >= 0.9:
				g.wheel.confirm(g.wheel.item_index("focus"))
			elif g.pick.active:
				g.pick._goal = g.hud_ct() * focus_tgt.pos - g.pick._offset()
				if g.pick.t >= 1.3:
					g.pick.confirm()
		"regroup":
			if int(ev.get("wheel", 0)) > int(ev0.get("wheel", 0)):
				return
			if not g.wheel.is_open and cur_t >= 1.6 and cur_t < 2.0:
				g.wheel.open()
			elif g.wheel.is_open and g.wheel.t_open >= 0.9:
				g.wheel.confirm(g.wheel.item_index("guard"))


# ---------------------------------------------------------------- 问题框

## 问题框的选项（强制时不给「跳过引导」）
func _ask_opts() -> Array:
	var opts: Array = data.get("ask", {}).get("opts", [])
	return opts.filter(func(o): return str(o[2]) != "off") if forced else opts


func modal() -> bool:
	return ask_on or view_on


func _open_ask() -> void:
	ask_on = true
	ask_t = 0.0
	ask_sel = 1
	g.intro_back = Game.S.PLAY
	g.state = Game.S.INTRO


func _choose(i: int) -> void:
	var opts: Array = _ask_opts()
	if i < 0 or i >= opts.size():
		return
	var m: String = str(opts[i][2])
	ask_on = false
	if dev == "":
		Cfg.onboard = m
		Cfg.save()
	if g.state == Game.S.INTRO:
		g.state = Game.S.PLAY
	g.combat.panel_grace()
	Sfx.play("ui_ok")
	_setup(m)


# ---------------------------------------------------------------- 演示图鉴（暂停菜单「演示」）

func open_viewer() -> void:
	view_on = true
	view_i = 0
	view_t = 0.0
	view_back = g.state
	g.state = Game.S.INTRO


func _view_step(d: int) -> void:
	var n: int = all_ids().size()
	view_i = (view_i + d + n) % n
	view_t = 0.0
	Sfx.play("ui_move")


func _view_close() -> void:
	view_on = false
	g.state = view_back
	Sfx.play("ui_ok", -4.0)


# ---------------------------------------------------------------- 输入（game._input 最前面转进来）；返回 true = 已处理

func input(event: InputEvent) -> bool:
	if not ask_on and not view_on and (cur == "" or g.state != Game.S.PLAY):
		return false
	var touch: bool = g.touch != null and g.touch.active
	var press := false
	var mp := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		press = true
		mp = (g.hud.make_input_local(event) as InputEventScreenTouch).position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not touch:
		press = true
		mp = g.hud.get_local_mouse_position()
	elif event is InputEventMouseMotion and ask_on and not touch:
		var lp: Vector2 = g.hud.get_local_mouse_position()
		for i in ask_rects.size():
			if (ask_rects[i] as Rect2).has_point(lp):
				ask_sel = i
	if ask_on:
		if event is InputEventKey and event.pressed and not event.echo:
			match Pad.kc(event):
				KEY_UP, KEY_W:
					ask_sel = posmod(ask_sel - 1, _ask_opts().size())
					Sfx.play("ui_move")
				KEY_DOWN, KEY_S, KEY_TAB:
					ask_sel = posmod(ask_sel + 1, _ask_opts().size())
					Sfx.play("ui_move")
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_choose(ask_sel)
				KEY_1, KEY_2, KEY_3:
					_choose(Pad.kc(event) - KEY_1)
				KEY_ESCAPE:
					if not forced:
						_choose(2)   # 跳过引导（第一次进游戏时 Esc 不选）
			return true
		if press:
			for i in ask_rects.size():
				if (ask_rects[i] as Rect2).has_point(mp):
					_choose(i)
					return true
		return event is InputEventMouseButton or event is InputEventScreenTouch
	if view_on:
		if event is InputEventKey and event.pressed and not event.echo:
			match Pad.kc(event):
				KEY_LEFT, KEY_A, KEY_PAGEUP:
					_view_step(-1)
				KEY_RIGHT, KEY_D, KEY_PAGEDOWN, KEY_SPACE, KEY_ENTER:
					_view_step(1)
				KEY_ESCAPE, KEY_H, KEY_BACKSPACE:
					_view_close()
			return true
		if press:
			for k in view_rects:
				if (view_rects[k] as Rect2).has_point(mp):
					match k:
						"prev":
							_view_step(-1)
						"next":
							_view_step(1)
						"close":
							_view_close()
					return true
		return event is InputEventMouseButton or event is InputEventScreenTouch
	if press and skip_rect.has_area() and skip_rect.has_point(mp) and not (forced and drill):
		if drill:
			_drill_end()   # 演示局：直接进正式局
		else:
			_finish(true)
		return true
	return false


# ---------------------------------------------------------------- 画

func _ctx() -> Dictionary:
	var lead_id: String = str(g.ch.id) if g.ch != null else "mizuki"
	var mates: Array = []
	for o in g.squad.ops:
		if o != g.ch and mates.size() < 2:
			mates.append(g.panel_ui.op_idle(str(o.id)))
	for cid in MATE_FALLBACK:
		if mates.size() >= 2:
			break
		if cid != lead_id and not g.squad.has(cid):
			var idl: Dictionary = g.panel_ui.op_idle(cid)
			if not idl.is_empty():
				mates.append(idl)
	return {"g": g, "font": g.font, "touch": g.touch != null and g.touch.active, "lead": g.panel_ui.op_idle(lead_id), "mates": mates}


## 局内提示卡（hud 每帧调）：桌面左上（生命 / 灯火条下方），触屏顶部居中；做完打勾后滑出
func draw(vs: Vector2) -> void:
	skip_rect = Rect2()
	if ask_on or view_on or g.state != Game.S.PLAY:
		return
	var id: String = cur if cur != "" else out_id
	if id == "":
		return
	var a := 1.0
	var slide := 0.0
	var done_k := 0.0
	if cur != "":
		var e: float = Demos._e(clampf(cur_t / 0.3, 0.0, 1.0))
		a = e
		slide = 1.0 - e
	else:
		done_k = clampf(out_t / 0.25, 0.0, 1.0)
		var o: float = clampf((out_t - 0.6) / 0.3, 0.0, 1.0)
		a = 1.0 - o
		slide = Demos._e(o)
	if a <= 0.01:
		return
	var touch: bool = g.touch != null and g.touch.active
	var v3on: bool = g.hud_view.v3 != null and g.hud_view.v3.on()
	var w: float = minf(vs.x - 24.0, (470.0 if touch else 440.0) if v3on else (540.0 if touch else 500.0))   # v3 卡收小一号（11-07 用户「新手引导的格子能不能小一点」）
	var pos := Vector2(16.0, 72.0) if touch else Vector2(16.0, 112.0)   # 触屏也放左上（生命 / 灯火条下方）：顶部居中会盖住屏幕中央的队长
	pos.x -= slide * 50.0
	_card(vs, id, Rect2(pos, Vector2(w, 0.0)), now, a, done_k, cur != "", touch, false)


## 一张卡：左演示、右文字（窄屏上下排）。big = 演示图鉴里的大卡。返回卡片矩形
func _card(vs: Vector2, id: String, frame: Rect2, t: float, a: float, done_k: float, live: bool, touch: bool, big: bool) -> Rect2:
	if g.hud_view.v3 != null and g.hud_view.v3.on():
		return _card_v3(id, frame, t, a, done_k, live, touch, big)
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var c := card(id)
	var w: float = frame.size.x
	var stacked: bool = w < 440.0
	var pad: float = 14.0 if not big else 22.0
	var dw: float = (w - pad * 2.0) if stacked else (w * 0.44)
	var dh: float = dw * 0.6
	var tx_w: float = (w - pad * 2.0) if stacked else (w - dw - pad * 3.0)
	var fsz: int = 15 if not big else 18
	var lines: PackedStringArray = UI.wrap_lines(font, text_of(id, touch), fsz, tx_w)
	var lh: float = font.get_height(UI.fs(fsz)) + 3.0
	var text_h: float = 52.0 + lines.size() * lh + 30.0
	var h: float = (pad + dh + 10.0 + text_h) if stacked else maxf(dh + pad * 2.0, text_h + pad)
	var pr := Rect2(frame.position, Vector2(w, h))
	var gold := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a)
	var v3: bool = g.hud_view.v3 != null and g.hud_view.v3.on()   # 指挥台统一（docs/222 §20）：金边 / 金竖条换成白，英文小签换灰；做完条件仍是青（可操作）
	if v3:
		gold = Color(0.925, 0.933, 0.941, a)
		hud.draw_rect(pr, Color(0.02, 0.03, 0.04, 0.9 * a))
		hud.draw_polyline(PackedVector2Array([pr.position + Vector2(0, 12), pr.position, pr.position + Vector2(12, 0)]), Color(1, 1, 1, 0.55 * a), 1.0)
		hud.draw_polyline(PackedVector2Array([pr.end - Vector2(0, 12), pr.end, pr.end - Vector2(12, 0)]), Color(1, 1, 1, 0.55 * a), 1.0)
		hud.draw_rect(Rect2(pr.position + Vector2(0, 10), Vector2(2, h - 20)), gold)
	else:
		UI.panel(hud, pr, Color(UI.BG2.r, UI.BG2.g, UI.BG2.b, 0.95 * a), Color(1, 1, 1, 0.16 * a), 10.0, gold)
		hud.draw_rect(Rect2(pr.position + Vector2(0, 10), Vector2(4, h - 20)), gold)
	var dr := Rect2(pr.position + Vector2(pad, pad), Vector2(dw, dh))
	if a > 0.6:
		Demos.draw(hud, id, dr, t, _ctx())
	var tp: Vector2 = (dr.position + Vector2(0, dh + 12.0)) if stacked else Vector2(dr.end.x + pad, pr.position.y + pad - 2.0)
	var basic: Array = drill_ids()
	var en: String = ("TUTORIAL  %d / %d" % [basic.find(id) + 1, basic.size()]) if (drill and basic.has(id) and not big) else (("TUTORIAL  ·  %s" % c.get("en", "")) if id == "drill_end" else ("NEW  ·  %s" % c.get("en", "")))
	UI.en(hud, font, tp + Vector2(0, 14), en, 10, Color(0.6, 0.63, 0.66, a) if v3 else gold, 2.5)
	UI.text(hud, font, tp + Vector2(0, 40), str(c.get("title", "")), 20 if not big else 24, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	var asc: float = font.get_ascent(UI.fs(fsz))
	for i in lines.size():
		hud.draw_string(font, Vector2(tp.x, tp.y + 52.0 + asc + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), Color(0.85, 0.93, 0.95, a))
	# 做完条件 / 进度
	var hy: float = tp.y + 52.0 + lines.size() * lh + 10.0
	var hint: String = str(c.get("hint", ""))
	if live and not big:
		if hint != "":
			var pulse: float = 0.6 + 0.4 * sin(t * 5.0)
			hud.draw_circle(Vector2(tp.x + 4.0, hy + 7.0), 3.5, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, pulse * a))
			UI.text(hud, font, Vector2(tp.x + 14.0, hy + 13.0), hint, 13, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
			if id == "move":
				var bw: float = minf(120.0, tx_w - 110.0)
				var br := Rect2(Vector2(tp.x + tx_w - bw, hy + 4.0), Vector2(bw, 5.0))
				hud.draw_rect(br, Color(1, 1, 1, 0.12 * a))
				hud.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(moved / MOVE_NEED, 0.0, 1.0), br.size.y)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
		else:
			var left: float = clampf(drill_left / END_SECS, 0.0, 1.0) if id == "drill_end" else clampf(1.0 - cur_t / INFO_SECS, 0.0, 1.0)
			hud.draw_rect(Rect2(Vector2(tp.x, hy + 6.0), Vector2(tx_w * left, 2.0)), Color(1, 1, 1, 0.3 * a))
		# 跳过（只跳这一张）；第一次进游戏的演示局不给
		if forced and drill:
			return pr
		var skip_s: String = "跳过演示" if drill else "跳过"
		var sw: float = (58.0 if touch else 46.0) + (28.0 if drill else 0.0)
		var sh: float = 30.0 if touch else 22.0
		skip_rect = Rect2(Vector2(pr.end.x - sw - 10.0, pr.position.y + 8.0), Vector2(sw, sh))
		hud.draw_rect(skip_rect, Color(0.03, 0.04, 0.05, 0.8 * a))
		hud.draw_rect(skip_rect, Color(1, 1, 1, 0.3 * a), false, 1.0)
		var stw: float = font.get_string_size(skip_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(12)).x
		hud.draw_string(font, skip_rect.get_center() + Vector2(-stw / 2.0, UI.fs(12) * 0.36), skip_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(12), Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, a))
	# 做完：打勾
	if done_k > 0.0:
		var cc: Vector2 = pr.position + Vector2(pr.size.x - 30.0, 26.0)
		var k: float = Demos._e(done_k)
		hud.draw_circle(cc, 13.0 * k, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
		hud.draw_polyline(PackedVector2Array([cc + Vector2(-6, 0) * k, cc + Vector2(-1.5, 5) * k, cc + Vector2(7, -5) * k]), Color(0.04, 0.07, 0.09, a), 2.5)
	return pr


static func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## 两角直角刻度（同属性面板 draw_v3 / draw_phone_v3）
func _brackets(r: Rect2, a: float) -> void:
	var tc := Color(1, 1, 1, 0.45 * a)
	g.hud.draw_polyline(PackedVector2Array([r.position + Vector2(0, 12), r.position, r.position + Vector2(12, 0)]), tc, 1.0)
	g.hud.draw_polyline(PackedVector2Array([r.end - Vector2(0, 12), r.end, r.end - Vector2(12, 0)]), tc, 1.0)


## 节标题（同属性面板 _v3_head）：中文标题（Heavy）+ 右侧灰英文小签，下面一道细线 + 左端白短条
func _head_v3(p: Vector2, w: float, cn: String, en: String, fs: int, cfs: float, a: float, cap_max := -1.0) -> void:
	var v2 = g.hud_view.v2
	v2.txt(p, cn, fs, _ca(W3, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, UI.name_font(g.font))
	if en != "" and cap_max >= 0.0 and _cap_w(en, cfs, 1.6) > cap_max - v2.twidth(cn, fs) - 10.0:
		en = ""   # 右上角有「跳过」：英文小签放不下就不画（手机卡窄）
	if en != "":
		v2.cap(Vector2(p.x + v2.twidth(cn, fs) + 10.0, p.y - 1.0), en, cfs, _ca(G3, a), 1.6)
	g.hud.draw_rect(Rect2(p.x, p.y + 8.0, w, 1), Color(1, 1, 1, 0.2 * a))
	g.hud.draw_rect(Rect2(p.x, p.y + 7.5, 18, 2), _ca(W3, a))


## hud_v2.cap 的宽度（同一套逐字量法）
func _cap_w(s: String, size: float, sp: float) -> float:
	var f: Font = UI.latin(true)
	var w := 0.0
	for ch in s:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(size))).x + sp
	return w - sp


## 细线进度条（同属性面板 _v3_hair）
func _hair_v3(x: float, y: float, w: float, frac: float, col: Color, a: float) -> void:
	g.hud.draw_rect(Rect2(x, y, w, 1.6), Color(1, 1, 1, 0.16 * a))
	g.hud.draw_rect(Rect2(x, y - 0.8, w * clampf(frac, 0.0, 1.0), 3.2), _ca(col, a))


## v3 卡片：几何与行为同 _card（左演示、右文字，窄屏上下排；做完条件 / 进度 / 跳过 / 打勾），只换画法
func _card_v3(id: String, frame: Rect2, t: float, a: float, done_k: float, live: bool, touch: bool, big: bool) -> Rect2:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var v2 = g.hud_view.v2
	var c := card(id)
	var w: float = frame.size.x
	var stacked: bool = w < 380.0
	var pad: float = 12.0 if not big else 24.0
	var dw: float = (w - pad * 2.0) if stacked else (w * (0.44 if big else 0.4))
	var dh: float = dw * 0.6
	var tx_w: float = (w - pad * 2.0) if stacked else (w - dw - pad * 3.0)
	var fsz: int = 15 if not big else 18
	var tfs: int = (22 if touch else 18) if not big else 24   # 标题：手机同手机属性面板名字一级（24 / 22），桌面同节标题放大一级
	var cfs: float = 7.5 if touch else 6.5                  # 英文小签：同各自属性面板
	var lines: PackedStringArray = UI.wrap_lines(font, text_of(id, touch), fsz, tx_w)
	var lh: float = font.get_height(UI.fs(fsz)) + 3.0
	var head_h: float = 46.0 if touch else 42.0
	var text_h: float = head_h + lines.size() * lh + 30.0
	var h: float = (pad + dh + 12.0 + text_h) if stacked else maxf(dh + pad * 2.0, text_h + pad)
	var pr := Rect2(frame.position, Vector2(w, h))
	hud.draw_rect(pr, Color(0.008, 0.012, 0.018, 0.92 * a))
	_brackets(pr, a)
	var dr := Rect2(pr.position + Vector2(pad, pad), Vector2(dw, dh))
	if a > 0.6:
		Demos.draw(hud, id, dr, t, _ctx())
	hud.draw_rect(dr.grow(1.0), Color(1, 1, 1, 0.2 * a), false, 1.0)   # 演示框：细框（同属性面板分隔线亮度）
	var tp: Vector2 = (dr.position + Vector2(0, dh + 14.0)) if stacked else Vector2(dr.end.x + pad, pr.position.y + pad - 2.0)
	var basic: Array = drill_ids()
	var en: String = ("TUTORIAL  %d / %d" % [basic.find(id) + 1, basic.size()]) if (drill and basic.has(id) and not big) else (("TUTORIAL  ·  %s" % c.get("en", "")) if id == "drill_end" else ("NEW  ·  %s" % c.get("en", "")))
	var sk_w: float = 0.0
	if live and not big and not (forced and drill):
		sk_w = (58.0 if touch else 46.0) + (28.0 if drill else 0.0) + 12.0
	_head_v3(tp + Vector2(0, 20.0 if touch else 18.0), tx_w if stacked else (pr.end.x - pad - tp.x), str(c.get("title", "")), en, tfs, cfs, a, (pr.end.x - 10.0 - sk_w - tp.x) if sk_w > 0.0 else -1.0)
	var asc: float = font.get_ascent(UI.fs(fsz))
	for i in lines.size():
		hud.draw_string(font, Vector2(tp.x, tp.y + head_h + asc + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), _ca(W3, 0.9 * a))
	# 做完条件 / 进度
	var hy: float = tp.y + head_h + lines.size() * lh + 10.0
	var hint: String = str(c.get("hint", ""))
	if live and not big:
		if hint != "":
			var pulse: float = 0.6 + 0.4 * sin(t * 5.0)
			hud.draw_rect(Rect2(Vector2(tp.x, hy + 3.0), Vector2(6, 6)), _ca(UI.CYAN, pulse * a))   # 方点（指挥台没有圆点）
			UI.text(hud, font, Vector2(tp.x + 14.0, hy + 13.0), hint, 13, _ca(UI.CYAN, a))
			if id == "move":
				var bw: float = minf(120.0, tx_w - 110.0)
				_hair_v3(tp.x + tx_w - bw, hy + 7.0, bw, moved / MOVE_NEED, UI.CYAN, a)
		else:
			var left: float = clampf(drill_left / END_SECS, 0.0, 1.0) if id == "drill_end" else clampf(1.0 - cur_t / INFO_SECS, 0.0, 1.0)
			_hair_v3(tp.x, hy + 7.0, tx_w, left, W3, 0.55 * a)
		# 跳过（只跳这一张）；第一次进游戏的演示局不给
		if forced and drill:
			return pr
		var skip_s: String = "跳过演示" if drill else "跳过"
		var sw: float = sk_w - 12.0
		var sh: float = 30.0 if touch else 22.0
		skip_rect = Rect2(Vector2(pr.end.x - sw - 10.0, pr.position.y + 8.0), Vector2(sw, sh))
		hud.draw_rect(skip_rect, Color(0.02, 0.03, 0.05, 0.92 * a))   # 同属性面板等级牌：深底 + 35% 白框
		hud.draw_rect(skip_rect, Color(1, 1, 1, 0.35 * a), false, 1.0)
		var sfs: int = 13 if touch else 12
		v2.txt(Vector2(skip_rect.position.x, skip_rect.get_center().y + UI.fs(sfs) * 0.36), skip_s, sfs, _ca(G3, a), HORIZONTAL_ALIGNMENT_CENTER, skip_rect.size.x)
	# 做完：打勾（青方块 + 勾，同指挥台「可用」色）
	if done_k > 0.0:
		var cc: Vector2 = pr.position + Vector2(pr.size.x - 30.0, 26.0)
		var k: float = Demos._e(done_k)
		hud.draw_rect(Rect2(cc - Vector2(12, 12) * k, Vector2(24, 24) * k), _ca(UI.CYAN, a))
		hud.draw_polyline(PackedVector2Array([cc + Vector2(-6, 0) * k, cc + Vector2(-1.5, 5) * k, cc + Vector2(7, -5) * k]), Color(0.04, 0.07, 0.09, a), 2.5)
	return pr


## v3 问题框：几何同 _draw_ask，只换画法
func _draw_ask_v3(vs: Vector2) -> void:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ask: Dictionary = data.get("ask", {})
	var opts: Array = _ask_opts()
	var e: float = Demos._e(clampf(ask_t / 0.3, 0.0, 1.0))
	var touch: bool = g.touch != null and g.touch.active
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.012, 0.018, 0.72 * e))
	var w: float = minf(vs.x - 32.0, 560.0)
	var oh: float = 64.0 if touch else 56.0
	var h: float = 150.0 + opts.size() * (oh + 10.0) + 20.0
	var pr := Rect2(Vector2((vs.x - w) / 2.0, (vs.y - h) / 2.0 + (1.0 - e) * 24.0), Vector2(w, h))
	hud.draw_rect(pr, Color(0.008, 0.012, 0.018, 0.96 * e))
	_brackets(pr, e)
	_head_v3(pr.position + Vector2(32, 60), w - 64.0, str(ask.get("title", "")), str(ask.get("en", "")), 24 if touch else 22, 7.5 if touch else 6.5, e)
	UI.text(hud, font, pr.position + Vector2(32, 106), str(ask.get("q", "")), 17, _ca(W3, 0.85 * e))
	ask_rects = []
	for i in opts.size():
		var r := Rect2(pr.position + Vector2(32, 134 + i * (oh + 10.0)), Vector2(w - 64.0, oh))
		ask_rects.append(r)
		var hot: bool = i == ask_sel
		if hot:   # 选中：青框 + 淡青底 + 左青竖条（同属性面板页签当前项用青）
			hud.draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12 * e))
			hud.draw_rect(r, _ca(UI.CYAN, e), false, 1.0)
			hud.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), _ca(UI.CYAN, e))
		else:
			hud.draw_rect(r, Color(1, 1, 1, 0.03 * e))
			hud.draw_rect(r, Color(1, 1, 1, 0.2 * e), false, 1.0)
		var fg: Color = _ca(W3, e)
		var sub: Color = _ca(G3, e)
		if not touch:
			UI.keycap(hud, font, r.position + Vector2(14, oh / 2.0 - 18.0), str(i + 1), _ca(UI.CYAN, e) if hot else fg, 11)
		var x0: float = 50.0 if not touch else 18.0
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 - 3.0), str(opts[i][0]), 18, fg)
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 + 17.0), str(opts[i][1]), 12, sub)


## 模态（state INTRO，intro.draw 转进来）：问题框 / 演示图鉴
func draw_modal(vs: Vector2) -> void:
	if ask_on:
		_draw_ask(vs)
	elif view_on:
		_draw_view(vs)


func _draw_ask(vs: Vector2) -> void:
	if g.hud_view.v3 != null and g.hud_view.v3.on():
		_draw_ask_v3(vs)
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ask: Dictionary = data.get("ask", {})
	var opts: Array = _ask_opts()
	var e: float = Demos._e(clampf(ask_t / 0.3, 0.0, 1.0))
	var touch: bool = g.touch != null and g.touch.active
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.72 * e))
	var w: float = minf(vs.x - 32.0, 560.0)
	var oh: float = 64.0 if touch else 56.0
	var h: float = 150.0 + opts.size() * (oh + 10.0) + 20.0
	var pr := Rect2(Vector2((vs.x - w) / 2.0, (vs.y - h) / 2.0 + (1.0 - e) * 24.0), Vector2(w, h))
	UI.panel(hud, pr, Color(UI.BG2.r, UI.BG2.g, UI.BG2.b, 0.97 * e), Color(1, 1, 1, 0.16 * e), 14.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e))
	hud.draw_rect(Rect2(pr.position + Vector2(0, 14), Vector2(4, h - 28)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e))
	UI.en(hud, font, pr.position + Vector2(32, 38), str(ask.get("en", "")), 11, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e), 3.0)
	UI.text(hud, font, pr.position + Vector2(32, 72), str(ask.get("title", "")), 24, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e))
	UI.text(hud, font, pr.position + Vector2(32, 112), str(ask.get("q", "")), 17, Color(0.85, 0.93, 0.95, e))
	ask_rects = []
	for i in opts.size():
		var r := Rect2(pr.position + Vector2(32, 134 + i * (oh + 10.0)), Vector2(w - 64.0, oh))
		ask_rects.append(r)
		var hot: bool = i == ask_sel
		hud.draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.95 if hot else 0.0) * e) if hot else Color(0.03, 0.04, 0.05, 0.8 * e))
		hud.draw_rect(r, Color(1, 1, 1, (0.0 if hot else 0.28) * e), false, 1.0)
		var fg := Color(0.04, 0.07, 0.09, e) if hot else Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e)
		var sub := Color(0.04, 0.07, 0.09, 0.75 * e) if hot else Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e)
		if not touch:
			UI.keycap(hud, font, r.position + Vector2(14, oh / 2.0 - 18.0), str(i + 1), fg, 11)   # 与标题行居中对齐
		var x0: float = 50.0 if not touch else 18.0
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 - 3.0), str(opts[i][0]), 18, fg)
		UI.text(hud, font, r.position + Vector2(x0, oh / 2.0 + 17.0), str(opts[i][1]), 12, sub)


func _draw_view(vs: Vector2) -> void:
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var touch: bool = g.touch != null and g.touch.active
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.85))
	var ids: Array = all_ids()
	var id: String = ids[clampi(view_i, 0, ids.size() - 1)]
	var w: float = minf(vs.x - 48.0, 860.0)
	var pr: Rect2 = _card(vs, id, Rect2(Vector2((vs.x - w) / 2.0, view_top(vs)), Vector2(w, 0.0)), view_t, 1.0, 0.0, false, touch, true)
	_view_h = pr.size.y
	view_rects = {}
	var by: float = pr.end.y + 18.0
	var bh: float = 44.0 if touch else 34.0
	view_rects["prev"] = Rect2(Vector2(pr.position.x, by), Vector2(110, bh))
	view_rects["next"] = Rect2(Vector2(pr.end.x - 110.0, by), Vector2(110, bh))
	view_rects["close"] = Rect2(Vector2(vs.x / 2.0 - 60.0, by), Vector2(120, bh))
	UI.button(hud, font, view_rects.prev, "‹ 上一张", "outline", false, 14)
	UI.button(hud, font, view_rects.next, "下一张 ›", "outline", false, 14)
	UI.button(hud, font, view_rects.close, "关闭", "primary", false, 14)
	UI.en(hud, font, Vector2(pr.position.x, pr.position.y - 12.0), "DEMO  %d / %d" % [view_i + 1, ids.size()], 11, UI.CYAN, 3.0)
	if not touch:
		UI.text(hud, font, Vector2(vs.x / 2.0 - 120.0, by + bh + 28.0), "← → 翻页　Esc 关闭", 12, UI.SUB)


var _view_h := 0.0

## 演示图鉴的卡片纵向位置：按上一帧量出的高度垂直居中
func view_top(vs: Vector2) -> float:
	return maxf(40.0, (vs.y - _view_h - 70.0) / 2.0)
