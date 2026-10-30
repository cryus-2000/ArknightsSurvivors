extends RefCounted
## 界面 · HUD 左侧与顶部（2026-10-10 从 hud.gd 拆出，docs/55 §6）：左上面板（等级圆 / 生命 / 灯火 / 侵蚀）与灯火状态条、
## 顶部中央（击杀 / 时间 / 楼层 / 威胁）、Boss 大血条、人物状态栏、声呐小地图。触屏分支原样保留。
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const Tris = preload("res://scripts/screens/hud_tris.gd")
const TriBatch = preload("res://scripts/render/tri_batch.gd")
const PlayClock = preload("res://scripts/run/play_clock.gd")
var g: Game
var h   # screens/hud.gd：合批段（batch_begin / _hb）、共用助手（edge_glow / corrode_seg / draw_tooltip）与兄弟模块都从这里取


func _init(hud) -> void:
	h = hud
	g = hud.g


## 经验回收提示（经验来源方案 A，架构 00dccbb）：等级圆正下方一行青色小字「回收 +N」。
## 读 g.pickups.recall_hud_n / recall_hud_t；离上一笔不到 1 秒的回收累加成一个数，最后一笔之后显示 1.5 秒（末 0.5 秒淡出）。
## 在左上面板的合批段里画（字延后），不加绘制调用
var _rc_sum := 0.0
var _rc_first := -INF
var _rc_last := -INF


## 左上面板的缓存签名（hud._layer）：draw_top_left 读到的全部状态。条 / 环的长度按 1/8 像素量化，
## 有动画（升级 / 经验闪光、受击抖动、低血 / 低灯火闪烁、侵蚀斜纹、回收提示淡出）时带上 g.t 逐帧重画
func top_left_sig(vs: Vector2) -> Array:
	var p = g.get("pickups")
	var rt: float = float(p.recall_hud_t) if p != null and "recall_hud_t" in p else -INF
	var rec: bool = g.t - rt >= 0.0 and g.t - rt <= 1.5
	var low: bool = g.hp / g.max_hp < 0.3
	var anim: bool = g.hud_lv_flash > 0.0 or g.hp_shake > 0.0 or low or g.lamp < 30.0 or g.corrode_pool > 0.0 or rec
	return [vs, g.level, int(g.hp), int(g.max_hp), g.shield, g.shield_max, int(g.lamp), int(g.lamp_cap), g.nerve > 1.0, g.corrode_pool > 0.5, rt,
		h.qpx(150.0 * g.hp / g.max_hp), h.qpx(150.0 * g.hp_trail / g.max_hp), h.qpx(1.2 * g.lamp),
		h.qpx(1.5 * g.nerve), g.t if anim else 0.0]


## 左上面板：等级圆 + 生命 / 灯火 / 神经 / 侵蚀（原 _draw_body 第一段）。在 hud 的 top_left 缓存层里画（签名见 top_left_sig）
func draw_top_left(vs: Vector2) -> void:
	# 左上（方案 A · 原作顶栏）：等级圆（外圈 = 经验）+「生命值」「灯火」彩色小标签头 + 数值 + 细条；
	# 名字与编队人数移到右下编队卡；下面一条灯火状态标签条在后面画（和状态效果一起）
	var o := Vector2(16, 12)
	var lf := g.hud_lv_flash
	var bc := UI.CYAN.lerp(UI.GOLD, lf)
	var lc0 := o + Vector2(26, 30)
	h.batch_begin()   # 左上面板：色块一批、字最后（性能 9/30）
	UI.ring(g.hud, lc0, 22.0 + 3.0 * lf, 0.0, bc, lf > 0.2)   # 只显示等级数字；经验进度在屏幕最上沿的通栏细条（draw_xp_top，10-28 用户）
	UI.ctext(g.hud, g.font, lc0 + Vector2(-20, -6), "LV", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
	UI.ctext(g.hud, g.font, lc0 + Vector2(-26, 13), str(g.level), int(20 * (1.0 + 0.3 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 52)
	draw_recall(lc0)
	# 生命值
	var hs := Vector2(sin(g.t * 90.0), cos(g.t * 70.0)) * 3.0 * g.hp_shake / 0.35
	var low := g.hp / g.max_hp < 0.3
	var hx := o.x + 64.0
	var tw0 := UI.tab(g.hud, g.font, Vector2(hx, o.y), "生命值", UI.RED if low else UI.TAB_HP)
	# 护盾层：小标签头右边一排小菱形
	for q in g.shield_max:
		UI.diamond(g.hud, Vector2(hx + tw0 + 10 + q * 11, o.y + 8.5), 4.0, Color(0.5, 0.85, 1.0) if q < g.shield else Color(1, 1, 1, 0.12), Color(0.6, 0.9, 1.0, 0.8))
	var hpc: Color = UI.RED.lerp(Color(1, 0.8, 0.85), 0.5 + 0.5 * sin(g.t * 10.0)) if low else UI.CYAN
	var hps := "%d" % int(g.hp)
	UI.ctext(g.hud, g.font, Vector2(hx, o.y + 40) + hs, hps, 21, UI.RED if low else UI.TEXT)
	UI.ctext(g.hud, g.font, Vector2(hx + UI.cwidth(g.font, hps, 21) + 4, o.y + 40) + hs, "/ %d" % int(g.max_hp), 13, UI.SUB)
	UI.gbar(g.hud, Rect2(Vector2(hx, o.y + 47) + hs, Vector2(150, 4)), g.hp / g.max_hp, hpc, 0, g.hp_trail / g.max_hp)
	h.corrode_seg(Rect2(Vector2(hx, o.y + 47) + hs, Vector2(150, 4)), 1.0)
	# 灯火：30 / 70 两道刻度
	var lx := hx + 172.0
	var lamp_low := g.lamp < 30.0
	var lc := UI.GOLD if not lamp_low else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 8.0))
	UI.tab(g.hud, g.font, Vector2(lx, o.y), "灯火", UI.TAB_LAMP if not lamp_low else UI.RED)
	var lps := "%d" % int(g.lamp)
	UI.ctext(g.hud, g.font, Vector2(lx, o.y + 40), lps, 21, lc if lamp_low else UI.TEXT)
	UI.ctext(g.hud, g.font, Vector2(lx + UI.cwidth(g.font, lps, 21) + 4, o.y + 40), "/ %d" % int(g.lamp_cap), 13, UI.SUB)
	var lbr := Rect2(Vector2(lx, o.y + 47), Vector2(120, 4))
	UI.gbar(g.hud, lbr, g.lamp / 100.0, lc)
	for tv in [30.0, 70.0]:
		var tx: float = lbr.position.x + lbr.size.x * tv / 100.0
		h._hb.rect(Rect2(tx, lbr.position.y - 2, 1, lbr.size.y + 4), Color(1, 1, 1, 0.7))
	# 神经损伤 / 侵蚀：生命条下方一道洋红细条
	if g.nerve > 1.0:
		UI.gbar(g.hud, Rect2(Vector2(hx, o.y + 54), Vector2(150, 2)), g.nerve / 100.0, Color(1.0, 0.45, 0.85))
		UI.en(g.hud, g.font, Vector2(hx + 156, o.y + 58), "NERVE", 8, Color(1.0, 0.5, 0.9), 1.0)
	if g.corrode_pool > 0.5:
		UI.text(g.hud, g.font, Vector2(hx + 190, o.y + 60), "蚀", 11, Color(0.8, 0.5, 1.0))
	h.batch_end()


func draw_recall(lc0: Vector2) -> void:
	var p = g.get("pickups")
	if p == null or not ("recall_hud_t" in p):
		return
	var t: float = float(p.recall_hud_t)
	if t > _rc_last:
		if t - _rc_first > 1.0:
			_rc_sum = 0.0
			_rc_first = t
		_rc_sum += float(p.recall_hud_n)
		_rc_last = t
	var age: float = g.t - _rc_last
	if age < 0.0 or age > 1.5 or _rc_sum < 1.0:
		return
	var a: float = clampf((1.5 - age) / 0.5, 0.0, 1.0)
	UI.ctext(g.hud, g.font, lc0 + Vector2(-40, 35), "回收 +%d" % int(round(_rc_sum)), 11, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), HORIZONTAL_ALIGNMENT_CENTER, 80)


## 经验通栏细条（10-28 用户「学习别的肉鸽，把升级进度条放在最上面，一个细条来记录进度」）：屏幕最上沿全宽 5 像素，
## 触屏避开安全区（左右刘海、顶部胶囊）。柠檬黄（10-28 用户「经验换成黄色」；比灯火的琥珀金 UI.GOLD 更亮更偏绿，与队长生命青、队友绿 / 金 / 红区分）；
## 吃到经验（g.xp_flash）时条头亮、一道流光扫过已填部分；升级（g.hud_lv_flash，pickups 置 1）时先满条白闪约 0.3 秒再清零回到新进度。
## 等级数字只在左上等级圆里（不重复）。每帧画在 hud 的 front 块
const XP_H := 5.0
var _xp_t := -9.0

func draw_xp_top(vs: Vector2) -> void:
	if g.state == Game.S.OPENING or g.state == Game.S.SHOW or g.xp_need <= 0.0:
		return
	var ins: Array = Cfg.safe_insets()
	var r := Rect2(Vector2(float(ins[0]), float(ins[1])), Vector2(vs.x - float(ins[0]) - float(ins[2]), XP_H))
	var lf: float = g.hud_lv_flash
	var full: bool = lf > 0.7   # 升级瞬间：满条白闪，之后回到新等级的进度
	var k: float = 1.0 if full else clampf(g.xp / g.xp_need, 0.0, 1.0)
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y + 1.0)), Color(0.02, 0.025, 0.04, 0.75))
	var fw: float = r.size.x * k
	var c := Color(0.55, 1.0, 0.78)   # #8cffc7 淡青绿，同经验结晶（10-29 用户定候选 B，render/gem_style 2）
	if fw > 0.0:
		g.hud.draw_rect(Rect2(r.position, Vector2(fw, r.size.y)), c)
		g.hud.draw_rect(Rect2(r.position, Vector2(fw, 1.0)), Color(0.88, 1.0, 0.94, 0.85))   # 顶部高光
	if g.xp_flash > 0.2 and g.t - _xp_t > 0.15:
		_xp_t = g.t   # 新吃到经验（xp_flash 每次置 0.3、0.1 秒衰完）：起一道 0.5 秒的流光，连续拾取时不每帧重开
	var ph: float = clampf((g.t - _xp_t) / 0.5, 0.0, 1.0)
	var xf: float = 1.0 - ph
	if xf > 0.0 and fw > 2.0 and not full:
		var sx: float = r.position.x + fw * ph   # 流光从左往右扫到条头
		g.hud.draw_rect(Rect2(Vector2(maxf(r.position.x, sx - 40.0), r.position.y), Vector2(minf(40.0, sx - r.position.x), r.size.y)), Color(1, 1, 1, 0.35 * xf))
		g.hud.draw_rect(Rect2(Vector2(r.position.x + fw - 3.0, r.position.y), Vector2(3.0, r.size.y + 2.0)), Color(1, 1, 1, 0.9 * xf))
	if full:
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y + 2.0)), Color(1, 1, 1, clampf((lf - 0.7) / 0.3, 0.0, 1.0) * 0.85))


## 灯火状态标签条（左上面板下方）
func draw_lamp_strip(vs: Vector2) -> void:
	var o := Vector2(16, 12)
	var st_txt := ""
	var st_en := "LIGHT"
	var st_col := UI.GOLD
	if g.lamp <= 0.0:
		st_txt = "灯火寂灭 · 持续受伤"
		st_en = "OUT"
		st_col = UI.RED
	elif g.lamp < 30.0:
		st_txt = "灯火暗淡 · 敌人移速与伤害 +%d%% · 受到的伤害 +%d%% · 拾取 -30%%" % [int(round((Bal.v("lamp/dark_enemy", 1.1) - 1.0) * 100.0)), int(round((Bal.v("lamp/dark_taken", 1.05) - 1.0) * 100.0))]
		st_en = "DARK"
		st_col = Color(1, 0.5, 0.5)
	elif g.lamp >= 70.0:
		st_txt = "灯火通明 · 技力回复 +30% · 拾取 +20%"
	else:
		st_txt = "灯火摇曳 · 照亮范围内敌人受伤 +25%"
		st_en = "LIT"
		st_col = Color(1.0, 0.85, 0.6)
	if h.panel_over_top():
		return   # 触屏选卡：这一行会被卡片压住截断，不画
	if Cfg.phone_ui():
		# 手机（10-27 用户嫌左上胶囊太多）：灯火正常时不常驻（顶上的灯火条已经看得出），只在寂灭时写；
		# 暗淡由状态胶囊「灯火暗淡」提示，这里不重复
		if g.lamp > 0.0:
			return
		st_txt = st_txt.get_slice(" · ", 0)
	h.batch_begin()
	UI.strip(g.hud, g.font, o + Vector2(2, 66 + h.allyhp.top_shift()), st_en, st_txt, st_col, st_col.lerp(UI.TEXT, 0.45))   # 队友血条在队长血条下（hud_allyhp 样式 4）时整行下移
	h.batch_end()


## 顶部块（顶部中央 + 右上暂停 / 倍速键 + 结局走向，hud 的 top 缓存块）的签名：两段读到的全部状态；威胁进度条按 1/8 像素量化
func top_sig(vs: Vector2) -> Array:
	var display_time: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var tfrac: float = 1.0
	if g.threat < D.THREAT.size() - 1:
		tfrac = clampf((g.t - D.THREAT[g.threat].t) / (D.THREAT[g.threat + 1].t - D.THREAT[g.threat].t), 0.0, 1.0)
	return [vs, h.panel_over_top(), int(display_time), g.kills, g.threat, h.qpx(140.0 * tfrac), g.trial.active, g.tier, g.touch.active, g.state,
		h.relics.top_hover(vs), PlayClock.current_label(), g.ending, Cfg.endings_cleared.size(), g.endg.cur, g.relics.size()]


## 顶部中央：击杀 / 时间 / 楼层 / 威胁进度（原 _draw_body「顶部中央」段）。
## 注意：这里开的合批段（h.batch_begin）由紧随其后的 hud_relics.draw_right_top 收（h.batch_end），两块在 hud._draw_body 里必须相邻
func draw_top_center(vs: Vector2) -> void:
	# 顶部中央（方案 A · 明日方舟战斗顶栏）：[敌人] 击杀 | [时钟] 时间；
	# 下面一行「◆ 楼层 + 英文」（背后淡金四叶环，原作地图顶部楼层名的样子）、威胁进度细线、威胁 / 难度
	var display_time: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var mm := int(display_time) / 60
	var ss := int(display_time) % 60
	var cx0 := vs.x / 2.0
	h.batch_begin()   # 顶部中央 + 右上暂停键：色块一批、字最后（性能 9/30）
	if h.panel_over_top():
		return   # 触屏选卡时面板标题占这里；合批段照常由 draw_right_top 收
	UI.fade_band(g.hud, Rect2(cx0 - 160, 8, 320, 40), Color(0.03, 0.035, 0.045, 0.8), 56.0)
	var ks := str(g.kills)
	var kw := UI.cwidth(g.font, ks, 23)
	var lx0 := cx0 - 16.0 - (20.0 + 6.0 + kw + 4.0 + 24.0)
	UI.icon(g.hud, "enemy", Vector2(lx0 + 10, 28), 20.0, Color.WHITE)
	UI.ctext(g.hud, g.font, Vector2(lx0 + 26, 37), ks, 23, UI.TEXT)
	UI.text(g.hud, g.font, Vector2(lx0 + 30 + kw, 36), "击杀", 11, UI.SUB)
	h._hb.rect(Rect2(cx0 - 0.5, 18, 1, 20), Color(1, 1, 1, 0.28))
	UI.icon(g.hud, "clock", Vector2(cx0 + 25, 28), 18.0, Color.WHITE)
	UI.ctext(g.hud, g.font, Vector2(cx0 + 38, 38), "%02d:%02d" % [mm, ss], 25, UI.TEXT)
	var tr: Dictionary = D.THREAT[g.threat]
	var tfrac: float = 1.0
	if g.threat < D.THREAT.size() - 1:
		tfrac = clampf((g.t - tr.t) / (D.THREAT[g.threat + 1].t - tr.t), 0.0, 1.0)
	var tcol := Color(0.9, 0.45, 1.0).lerp(UI.RED, float(g.threat) / (D.THREAT.size() - 1))
	UI.quatrefoil(g.hud, Vector2(cx0, 64), 34.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.1), 1.2)   # 10-31 TA L7：四叶环线条穿过楼层名 / 威胁字——压到很淡，只当底纹
	var fname: String = "Boss 演练" if g.trial.active else tr.name
	var fen: String = "TRIAL" if g.trial.active else String(tr.get("en", ""))
	var fw0 := g.font.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(14)).x
	var few := UI.en_width(g.font, fen, 10, 3.0)
	var fx0 := cx0 - (14.0 + fw0 + 10.0 + few) / 2.0
	UI.diamond(g.hud, Vector2(fx0 + 4, 61), 3.5, UI.GOLD)
	UI.text(g.hud, g.font, Vector2(fx0 + 14, 66), fname, 14, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	UI.en(g.hud, g.font, Vector2(fx0 + 24 + fw0, 65), fen, 10, UI.SUB, 3.0)
	UI.gbar(g.hud, Rect2(cx0 - 70, 73, 140, 2), tfrac, tcol)
	var threat_label := "不记录通关进度" if g.trial.active else ("威胁 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][g.threat]) + (("  ·  %s" % D.tier_name(g.tier)) if g.tier > 0 else "")
	UI.text(g.hud, g.font, Vector2(cx0 - 150, 90), threat_label, 14 if g.touch.active else 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300, 2)


## Boss 血条块的实际底部（没有血条时 0）；横幅（hud_banners.banner_y）与 Boss 登场名片从这里往下让
var boss_bottom := 0.0


## 招式名在副标题行停留的秒数（boss_ai 出招时写 e.move_name / e.move_t）
const MOVE_NAME_T := 1.6


## 顶部 Boss 血条的对象（2026-09-27 用户报 bug：碎片 / 之泪这类召唤物进了 g.bosses，屏幕中间叠了 6 条）：
## 只算活着、且 enemies.json 里 role == "boss" 的；上限按行算（双体 Boss 合成一行），最多 2 行
const BOSS_BARS_MAX := 2


## Boss 血条（10-27 用户 iPhone 实机：双 Boss 两条宽厚血条叠在屏幕中上部挡战场，重做，手机优先、电脑统一）：
## 顶栏下贴顶一条细条，宽 ≤ 屏宽一半、居中；一行小字（名字 + 形态点 / 吸收层 + 右侧状态）+ 细血条（单体 5 px）。
## 双体 Boss（pair）合成一个框：上下两根 3 px 细条并排，左侧一枚连环小标表示「同时击倒」（说明只在出场横幅提示一次，spawner）；
## 一体进入假死时那一根闪。掉血：受击白闪 + 延迟白条（BT_HOLD 秒后追上）；阶段刻度、阶段护盾、破绽、无敌、韧性都在细条内表现。
## 最多 BOSS_BARS_MAX 行（双体算一行），多出来的写一行「另有 N 个 Boss」
const BB_Y := 94.0          # 名字行顶边（顶部中央计时器、海域名、威胁行之下）
const BB_W_MAX := 560.0
const BB_ROW := 30.0        # 一行（名字行 + 细条）的高度
const BT_HOLD := 0.45       # 延迟白条停多久再追
const BT_RATE := 0.6        # 追的速度（每秒满条的比例）
var _bt := {}               # Boss id -> {trail, last, hold, flash}


## 本帧要画的行：[[Boss] 或 [Boss, 搭档]]（双体合一行）
func _boss_rows(bars: Array) -> Array:
	var rows: Array = []
	var used := {}
	for e in bars:
		if used.has(e.id):
			continue
		used[e.id] = true
		var p = e.get("partner")
		if p is Dictionary and not p.dead and bars.has(p) and not used.has(p.id):
			used[p.id] = true
			rows.append([e, p])
		else:
			rows.append([e])
	return rows


## 延迟白条 / 受击闪烁：按真实时间推进（暂停时 HUD 照画，白条照追）
func _bt_step(e: Dictionary, r: float) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var s: Dictionary = _bt.get(e.id, {})
	if s.is_empty():
		s = {"trail": r, "last": r, "hold": 0.0, "flash": -9.0, "t": now}
		_bt[e.id] = s
	var dt: float = clampf(now - float(s.t), 0.0, 0.1)
	s.t = now
	if r < float(s.last) - 0.0005:
		s.flash = now
		s.hold = BT_HOLD
	elif r > float(s.trail):
		s.trail = r   # 回血：白条直接跟上
	s.last = r
	if float(s.hold) > 0.0:
		s.hold = float(s.hold) - dt
	else:
		s.trail = maxf(r, float(s.trail) - BT_RATE * dt)
	return s


## 一根细条：底 → 延迟白条 → 血量（颜色按状态）→ 受击白闪 → 阶段刻度
func _boss_strip(e: Dictionary, r: Rect2, bcol: Color) -> void:
	var ratio: float = clampf(e.hp / maxf(1.0, e.maxhp), 0.0, 1.0)
	var s := _bt_step(e, ratio)
	g.hud.draw_rect(r.grow(1.0), Color(0.02, 0.02, 0.03, 0.85))
	g.hud.draw_rect(r, Color(1, 1, 1, 0.08))
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * float(s.trail), r.size.y)), Color(1, 1, 1, 0.55))
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), bcol)
	var fl: float = 1.0 - (Time.get_ticks_msec() / 1000.0 - float(s.flash)) / 0.12
	if fl > 0.0:
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(1, 1, 1, 0.6 * fl))
	var gl: Array = e.get("gates", [])
	var hold: bool = e.get("gate_hold", false)
	for gi in gl.size():
		var gx: float = r.position.x + r.size.x * float(gl[gi])
		var lit: bool = hold and gi == 0
		if lit:
			g.hud.draw_rect(Rect2(gx - 2, r.position.y - 3, 4, r.size.y + 6), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35 + 0.25 * sin(g.t * 10.0)))
		g.hud.draw_rect(Rect2(gx - 0.5, r.position.y - 2, 1, r.size.y + 4), UI.GOLD if lit else Color(1, 1, 1, 0.85))
	var tn: float = e.get("tough_need", 0.0)
	if tn > 0.0 and e.get("tough", 0.0) > 0.0 and e.get("break_t", 0.0) <= 0.0:
		g.hud.draw_rect(Rect2(r.position.x, r.end.y + 1, r.size.x * clampf(e.tough / tn, 0.0, 1.0), 1), Color(0.95, 0.85, 0.55))


## 状态色：破绽中金色；阶段护盾时金色闪；无敌灰蓝；假死时洋红闪；平时洋红
func _boss_col(e: Dictionary) -> Color:
	if e.get("break_t", 0.0) > 0.0:
		return UI.GOLD
	if e.get("gate_hold", false):
		return UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 10.0))
	if e.get("invuln", false):
		return Color(0.45, 0.6, 0.7)
	if e.get("coma", false):
		return UI.RED.lerp(Color.WHITE, 0.35 + 0.35 * sin(g.t * 12.0))
	return UI.RED


## 右侧一行状态小字（只取最要紧的一条）
func _boss_sub(e: Dictionary) -> Array:
	var brk: float = e.get("break_t", 0.0)
	var mv_name: String = e.get("move_name", "")
	if brk > 0.0:
		return ["破绽 %.1f 秒 · 受伤 +%d%%" % [brk, roundi((Game.Bal.v("boss/break_mult", 1.4) - 1.0) * 100.0)], UI.GOLD]
	if e.get("gate_hold", false):
		return ["阶段护盾 · 时限到后破碎", UI.GOLD]
	if e.get("coma", false):
		return ["假死中 —— 趁现在击倒另一体", Color(1, 0.82, 0.88)]
	if mv_name != "" and g.t - float(e.get("move_t", -99.0)) < MOVE_NAME_T:
		return [mv_name, Color(1, 0.82, 0.88)]
	if e.type == "izumik":
		return ["学习阶段 · 无敌（击杀子代阻止它成长）" if e.phase == 1 else "阐释阶段", UI.SUB]
	if e.type == "ishar":
		if e.phase == 1 and e.get("ishar_p1", false):   # 人形可受伤（10-28）：充能与提前转化的血线都写明
			var pc: int = roundi(100.0 * clampf(float(e.get("ally_charge", 0.0)) / maxf(0.01, float(e.get("ally_charge_need", 30.0))), 0.0, 1.0))
			return ["人形 · 转化充能 %d%%（打到 %d%% 血提前转化）" % [pc, roundi(100.0 * Game.Bal.v("boss/ishar_p1_line", 0.85))], UI.SUB]
		return ["转化中" if e.phase == 1 else "已完成转化 · 敌对", UI.SUB]
	if e.has("ammo"):
		return ["装填中 —— 攻击以打断！" if e.channel > 0.0 else ("弹药 %d / 3" % e.ammo if e.ammo > 0 else "近战中"), UI.SUB]
	if e.type == "paranoia":
		return [("悬浮形态（打到 1/3 血坠落）" if Game.Bal.v("boss/paranoia_p2_at_gate", 1.0) > 0.0 else "悬浮形态（结茧后坠落）") if e.phase == 1 else "第二形态", UI.SUB]
	return ["", UI.SUB]


## Boss 血条（10-28 用户「boss的血条的UI是不是也可以更有设计感一点」，选定 B「刻纹槽」）：缺省由 hud_bossbar 画；--bbstyle=0（开发版）回下面的旧细条作对照，--bbdemo 画演示
var _bb = null
var _bbs := -1
var _bbd := false

func _bb_style() -> int:
	if _bbs < 0:
		_bbs = 2   # 10-28 用户选 B「刻纹槽」（hud_bossbar）
		for a in Cfg.dev_args():
			if a.begins_with("--bbstyle="):
				_bbs = clampi(int(a.substr(10)), 0, 2)   # 0 = 旧细条（对照用）
			if a == "--bbdemo":
				_bbd = true
	return _bbs


func draw_boss_bars(vs: Vector2) -> void:
	var bby := 0.0
	if h.panel_over_top():
		return   # 触屏选卡：面板标题占顶部中央（boss_bottom 保持上一帧的值，关面板后横幅位置不跳）
	if _bb_style() > 0:
		if _bb == null:
			_bb = preload("res://scripts/screens/hud_bossbar.gd").new(h)
		if _bbd:
			_bb.draw_demo(vs)
			boss_bottom = 98.0 + 5.0 * 44.0 + 8.0
			return
		var bw2: float = minf(BB_W_MAX, vs.x * 0.5)
		var bx2: float = round(vs.x / 2.0 - bw2 / 2.0)
		var vrows: Array = []
		var y2: float = BB_Y
		var allrows: Array = _boss_rows(boss_bars())
		for ri in mini(allrows.size(), BOSS_BARS_MAX):
			var row: Array = allrows[ri]
			if row.size() == 1 and row[0].type == "ishar" and row[0].get("friendly", false):
				draw_ishar_human(row[0], bx2, bw2, y2)   # 伊莎玛拉人形（友方充能条）照旧，排在最前
				y2 += BB_ROW
				continue
			var vv: Array = []
			for e in row:
				var v: Dictionary = _bb.view_of(e)
				v["sub"] = _boss_sub(e)
				vv.append(v)
			vrows.append(vv if vv.size() == 2 else vv[0])
		var used: float = _bb.draw_views(vrows, bx2, y2, bw2) + (y2 - BB_Y)
		if allrows.size() > BOSS_BARS_MAX:
			UI.text(g.hud, g.font, Vector2(bx2, BB_Y + used + 10.0), "另有 %d 个 Boss" % (allrows.size() - BOSS_BARS_MAX), 12, Color(1, 0.82, 0.88), HORIZONTAL_ALIGNMENT_CENTER, bw2, 2)
			used += 16.0
		boss_bottom = BB_Y + used + 4.0 if used > 0.0 else 0.0
		return
	var bars: Array = boss_bars()
	var rows := _boss_rows(bars)
	var bw: float = minf(BB_W_MAX, vs.x * 0.5)
	var bx: float = round(vs.x / 2.0 - bw / 2.0)
	for ri in mini(rows.size(), BOSS_BARS_MAX):
		var row: Array = rows[ri]
		var y0: float = BB_Y + bby
		var e: Dictionary = row[0]
		if row.size() == 1 and e.type == "ishar" and e.get("friendly", false):
			draw_ishar_human(e, bx, bw, y0)
			bby += BB_ROW
			continue
		var pair: bool = row.size() == 2
		# 名字行：左边名字（双体用「 · 」连），形态点 / 吸收层跟在后面；右边状态小字（双体取更要紧的那体）
		var nm: String = str(e.name) if not pair else "%s · %s" % [row[0].name, row[1].name]
		var nx: float = bx + (14.0 if pair else 0.0)
		var nw: float = g.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(13)).x
		UI.text(g.hud, g.font, Vector2(nx, y0 + 12.0), nm, 13, Color(1, 0.86, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		var tx: float = nx + nw + 8.0
		if not pair:
			var gl: Array = e.get("gates", [])
			var acts: int = gl.size() + int(e.get("gates_passed", 0)) + 1
			if acts > 1:
				for q in acts:
					var dc := Vector2(tx + q * 8.0, y0 + 7.0)
					if q >= int(e.get("gates_passed", 0)):
						g.hud.draw_circle(dc, 2.5, UI.RED)
					else:
						g.hud.draw_arc(dc, 2.5, 0.0, TAU, 10, Color(1, 1, 1, 0.3), 1.0)
				tx += acts * 8.0 + 6.0
			if e.has("izu_layers"):
				for q in 5:
					var lit_l: bool = q < int(e.izu_layers)
					UI.diamond(g.hud, Vector2(tx + q * 8.0, y0 + 7.0), 3.0, Color(0.55, 1.0, 0.95) if lit_l else Color(1, 1, 1, 0.08), Color(0.6, 1.0, 1.0, 0.8 if lit_l else 0.3))
		var sub: Array = _boss_sub(e)
		if pair and str(sub[0]) == "":
			sub = _boss_sub(row[1])
		if str(sub[0]) != "":
			UI.text(g.hud, g.font, Vector2(bx + bw - 320.0, y0 + 12.0), str(sub[0]), 12, sub[1], HORIZONTAL_ALIGNMENT_RIGHT, 320, 2)
		if pair:
			# 两根 3 px 细条并在一个框里；左侧连环小标 = 两体需同时击倒
			_boss_strip(row[0], Rect2(bx + 14.0, y0 + 18.0, bw - 14.0, 3.0), _boss_col(row[0]))
			_boss_strip(row[1], Rect2(bx + 14.0, y0 + 23.0, bw - 14.0, 3.0), _boss_col(row[1]))
			# 连体标：两根细条左端各一个小方块，竖线连起来（两体同生共死）
			var lc := Color(1, 0.86, 0.9, 0.95)
			g.hud.draw_rect(Rect2(bx + 3.0, y0 + 17.5, 4.0, 4.0), lc)
			g.hud.draw_rect(Rect2(bx + 3.0, y0 + 22.5, 4.0, 4.0), lc)
			g.hud.draw_rect(Rect2(bx + 4.5, y0 + 19.0, 1.0, 6.0), lc)
			g.hud.draw_rect(Rect2(bx + 7.0, y0 + 19.0, 7.0, 1.0), Color(lc, 0.5))
			g.hud.draw_rect(Rect2(bx + 7.0, y0 + 24.0, 7.0, 1.0), Color(lc, 0.5))
		else:
			_boss_strip(e, Rect2(bx, y0 + 19.0, bw, 5.0), _boss_col(e))
		bby += BB_ROW
	if rows.size() > BOSS_BARS_MAX:
		var ot := "另有 %d 个 Boss" % (rows.size() - BOSS_BARS_MAX)
		UI.text(g.hud, g.font, Vector2(bx, BB_Y + bby + 10.0), ot, 12, Color(1, 0.82, 0.88), HORIZONTAL_ALIGNMENT_CENTER, bw, 2)
		bby += 16.0
	boss_bottom = BB_Y + bby + 4.0 if bby > 0.0 else 0.0


func draw_ishar_human(e: Dictionary, bx: float, bw: float, y0 := BB_Y) -> void:
	var progress: float = clampf(float(e.get("ally_charge", 0.0)) / maxf(0.01, float(e.get("ally_charge_need", 30.0))), 0.0, 1.0)
	UI.text(g.hud, g.font, Vector2(bx, y0 + 12.0), str(e.name), 13, UI.CYAN, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	UI.text(g.hud, g.font, Vector2(bx + bw - 320.0, y0 + 12.0), "人形 · 治疗海嗣 / 转化充能 %d%%" % roundi(progress * 100.0), 12, UI.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 320, 2)
	var r := Rect2(bx, y0 + 19.0, bw, 5.0)
	g.hud.draw_rect(r.grow(1.0), Color(0.02, 0.02, 0.03, 0.85))
	g.hud.draw_rect(r, Color(1, 1, 1, 0.08))
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * progress, r.size.y)), UI.CYAN)


func hostile_boss_bars() -> Array:
	return boss_bars().filter(func(e): return not e.get("friendly", false))


func boss_bars() -> Array:
	var out: Array = []
	for b in g.bosses:
		if not b.dead and D.ENEMIES.get(b.type, {}).get("role", "") == "boss":
			out.append(b)
	return out


## 人物状态栏：左上面板下方，列出当前生效的增益 / 减益（带剩余时间条）
func draw_status_bar(vs: Vector2) -> void:
	draw_status(vs, status_items())


## 状态条缓存块（hud 的 status）的签名：本帧的标签片列表（文字 / 颜色 / 进度条长度按 1/8 像素量化）+ 换行宽度
func status_sig(vs: Vector2, items: Array) -> Array:
	var sig: Array = [vs, boss_bars().is_empty(), g.touch.active, h.allyhp.top_shift()]
	for it in items:
		sig.append([it[0], it[1], h.qpx(100.0 * float(it[2])) if float(it[2]) >= 0.0 else -1])
	return sig


## 状态条的标签片：[文字, 颜色, 进度 0..1 或 -1]；开场 / 介绍 / 演出时为空
func status_items() -> Array:
	if g.state == Game.S.OPENING or g.state == Game.S.INTRO or g.state == Game.S.SHOW:
		return []
	var items: Array = []   # [文字, 颜色, 进度 0..1 或 -1]
	for it in g.ch.status_items():
		items.append(it if it.size() >= 3 else [it[0], it[1], -1.0])
	if g.shield > 0:
		items.append(["护盾 ×%d" % g.shield, Color(0.6, 0.9, 1.0), -1.0])
	if g.endg != null:
		items.append_array(g.endg.status_items())   # 事件改版：委托倒计时、暂离队友（docs/173）
	var rush_t: String = g.squad.rush_text() if g.squad != null else ""
	if rush_t != "":
		items.append(["突击 · 队友" + rush_t, Color(1.0, 0.82, 0.3), g.squad.stamina if g.squad.stamina_on() else -1.0])
	for x in g.rfx.temps:
		if x.stat == "dmg":
			items.append(["增伤 +%d%%" % int(x.value * 100.0), Color(1.0, 0.75, 0.4), clampf((x.until - g.t) / 6.0, 0.0, 1.0)])
		elif x.stat == "op_aspd":
			items.append(["攻速 +%d%%" % int(x.value * 100.0), Color(1.0, 0.9, 0.5), clampf((x.until - g.t) / 10.0, 0.0, 1.0)])
		elif x.stat == "dmg_taken":
			items.append(["减伤 %d%%" % int(-x.value * 100.0), Color(0.6, 0.9, 1.0), clampf((x.until - g.t) / 5.0, 0.0, 1.0)])
	if g.rfx.rule("black_tulip") > 0 and g.rfx.tulip_t > 1.0:
		var tb: float = g.rfx.tulip_bonus()
		items.append(["郁金香 +%d%%" % int(100.0 * tb) if tb > 0.0 else "郁金香 暂停", Color(1.0, 0.6, 0.7), g.rfx.tulip_t / 60.0])
	if g.rfx.perm_dmg > 0.0:
		items.append(["刻勋 +%.1f%%" % (g.rfx.perm_dmg * 100.0), Color(1.0, 0.85, 0.5), -1.0])
	if g.rfx.king_low() and (g.rfx.rule("king_crown") + g.rfx.rule("king_gun") + g.rfx.rule("king_cake") + g.rfx.rule("king_branch")) > 0:
		items.append(["国王之势", Color(1.0, 0.8, 0.3), -1.0])
	if g.corrode_pool > 0.5:
		items.append(["侵蚀 %d" % int(g.corrode_pool), Color(0.8, 0.5, 1.0), -1.0])
	# 神经损伤（Boss与怪物 419c84d：0–nerve_max，站在溟痕 / 巢涌者光环里上涨；满格后 nerve_lock 秒锁定）
	var nlock: float = float(g.get("nerve_lock")) if g.get("nerve_lock") != null else 0.0
	var nmax: float = g.combat.nerve_max()
	if nlock > 0.0:
		items.append(["神经 · 锁定 %.1f" % nlock, Color(0.62, 0.6, 0.66), clampf(nlock / 5.0, 0.0, 1.0)])
	elif g.nerve > 1.0:
		items.append(["神经损伤 %d" % int(g.nerve / nmax * 100.0), Color(1.0, 0.5, 0.9), clampf(g.nerve / nmax, 0.0, 1.0)])
	if g.atk_slow > 0.0:
		items.append(["攻速减缓", Color(0.6, 0.7, 0.9), clampf(g.atk_slow / 3.0, 0.0, 1.0)])
	if g.pstun > 0.0:
		items.append(["定身", UI.RED, -1.0])
	# 小怪控制（combat.gd「小怪控制」段）
	if g.cold > 0:
		items.append(["寒霜 ×%d" % g.cold, Color(0.6, 0.88, 1.0), clampf(g.cold_t / maxf(0.1, Game.Bal.v("enemy/frost_dur", 3.0)), 0.0, 1.0)])
	if g.root_t > 0.0:
		items.append(["%s · 冲刺挣脱" % g.world.root_label(), Color(0.6, 0.88, 1.0) if g.world.leader_frozen() else Color(0.8, 0.5, 1.0), clampf(g.root_t / maxf(0.05, g.world.root_max), 0.0, 1.0)])
	for bb in g.bosses:
		if not bb.dead and bb.get("burden_in", false):
			# 二阶段光环更强（docs/95 §1.2：paranoia_aura_aspd2 0.15，合计上限 −15%）
			var ak: float = minf(0.15, Game.Bal.v("boss/paranoia_aura_aspd2", 0.15) if bb.get("phase", 1) == 2 else Game.Bal.v("boss/paranoia_aura_aspd", 0.10))
			items.append(["认知负担 · 攻速 −%d%%" % roundi(ak * 100.0), Color(0.85, 0.55, 1.0), -1.0])
			break
	var apop_t: float = float(g.get("apop_t")) if g.get("apop_t") != null else 0.0
	var apop: float = float(g.get("apop")) if g.get("apop") != null else 0.0
	if apop_t > 0.0:
		items.append(["技力暂停 %.1f" % apop_t, Color(0.7, 0.85, 0.65), clampf(apop_t / 4.0, 0.0, 1.0)])
	elif apop > 1.0:
		items.append(["凋亡 %d" % int(apop), Color(0.62, 0.72, 0.6), apop / 100.0])
	if g.wound > 0:
		items.append(["创口 ×%d" % g.wound, Color(1.0, 0.35, 0.6), clampf(g.wound_t / maxf(0.1, Game.Bal.v("enemy/wound_dur", 6.0)), 0.0, 1.0)])
	if g.in_mire > 0.5:
		items.append(["溟痕 · 减速", Color(0.85, 0.45, 1.0), -1.0])
	if g.zone_state != 0 and g.ppos.distance_to(g.zone_c) > g.zone_r:
		items.append(["黑潮", Color(0.9, 0.4, 1.0), -1.0])
	if g.lamp < 30.0:
		items.append(["灯火暗淡", Color(1.0, 0.55, 0.45), -1.0])
	return items


func draw_status(vs: Vector2, items: Array) -> void:
	if items.is_empty():
		return
	var ph: bool = Cfg.phone_ui()
	var x := 18.0
	var y: float = (80.0 if ph and g.lamp > 0.0 else 104.0) + h.allyhp.top_shift()   # 手机：灯火行不常驻，胶囊上移补位；队友血条在队长血条下时下移
	var fs := 12   # 手机局内经 UI.fs 放大到约 14（docs/37 下限之上）
	# 换行宽度（§1.15）：min(360, Boss 细血条左边 − 8)，有 Boss 血条时不钻到血条下面
	var wrap_x := 360.0
	if not boss_bars().is_empty():
		wrap_x = minf(360.0, g.hud.size.x / 2.0 - minf(BB_W_MAX, g.hud.size.x * 0.5) / 2.0 - 8.0)
	# 手机：最多 3 枚，其余收成「+N」（全部在属性面板里看；10-27 用户嫌左上胶囊太大太多）
	if ph and items.size() > 3:
		var more: int = items.size() - 2
		items = items.slice(0, 2) + [["+%d" % more, Color(0.8, 0.84, 0.88), -1.0]]
	# 合批（docs/50 §13）：标签片的底 / 色条 / 进度细条一批，字（同字体同字号）一批；各片互不重叠，字画在最后与原来相同
	var tb := TriBatch.new()
	var tx: Array = []
	for it in items:
		var cw: float = g.font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fs)).x + 16.0   # 与 UI.chip 的宽度算法一致
		if x + cw > wrap_x and x > 18.0:
			x = 18.0
			y += fs + 14.0
		var w: float
		w = _chip_b(tb, tx, Vector2(x, y), it[0], it[1], UI._ks(g.hud, fs))
		if it[2] >= 0.0:
			tb.rect(Rect2(x, y + fs + 8.0, w * it[2], 2), it[1])
		x += w + 6.0
	tb.flush(g.hud)
	for f in tx:
		f.call()


## 同 UI._chip（暗底 + 左侧色条 + 字），色块进 tb、字进 tx（同一字体字号，连着画）
func _chip_b(tb: TriBatch, tx: Array, pos: Vector2, s: String, col: Color, size: int) -> float:
	var w := g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	tb.rect(Rect2(pos, Vector2(w, size + 8)), Color(0.03, 0.035, 0.045, 0.8 * col.a))
	tb.rect(Rect2(pos, Vector2(3, size + 8)), col)
	var tc: Color = Color(col.r, col.g, col.b, col.a).lerp(Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, col.a), 0.3)
	var ci: CanvasItem = g.hud
	var fnt: Font = g.font
	tx.append(func(): ci.draw_string(fnt, pos + Vector2(9, size + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tc))
	return w


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func draw_minimap(vs: Vector2) -> void:
	var rad := 58.0 if Cfg.phone_ui() else 78.0   # 手机：缩小（左下是摇杆区，10-26 实机挤）
	var c := Vector2(16 + rad + 8, vs.y - rad - 24)
	var slr := Rect2(Vector2(c.x - rad + 2, c.y - rad - 8), Vector2(UI.en_width(g.font, "SONAR", 9, 2.0) + 10.0, 14))
	# 合批（docs/50 §13）：UI.porthole（圆底 + 两道环 + 虚线十字）与标签底同一批，引擎同款几何
	var pb := TriBatch.new()
	pb.circle(c, rad, Color(0.03, 0.035, 0.045, 0.62))
	pb.arc(c, rad, 0.0, TAU, 72, Color(1, 1, 1, 0.34), 1.0)
	pb.arc(c, rad * 0.64, 0.0, TAU, 56, Color(1, 1, 1, 0.1), 1.0)
	for kk in 4:
		var dd := Vector2.from_angle(kk * PI / 2.0)
		var ss := 0.0
		while ss < rad - 4.0:
			pb.line(c + dd * ss, c + dd * minf(ss + 3.0, rad - 4.0), Color(1, 1, 1, 0.1), 1.0)
			ss += 7.0
	pb.rect(slr, Color(1, 1, 1, 0.14))
	pb.flush(g.hud)
	UI.en(g.hud, g.font, slr.position + Vector2(5, 11), "SONAR", 9, Color(0.81, 0.84, 0.86), 2.0)
	var world := 1100.0
	var k := (rad - 8.0) / world
	var lim := rad - 6.0
	# 扫描线、视野框、各色点、安全区圈都进一个无贴图批，末尾一次提交（原来约 30 次绘制调用）
	var tb := Tris.new()
	# 声呐扫描线
	var sweep := fmod(g.t * 0.9, TAU)
	tb.line(c, c + Vector2.from_angle(sweep) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.35), 1.0)
	for q in 6:
		var a := sweep - q * 0.06
		tb.line(c, c + Vector2.from_angle(a) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.06 * (6 - q) / 6.0), 3.0)
	tb.arc(c, lim * 0.5, 0.0, TAU, 1.0, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.12), 40)
	# 视野框
	var view: Vector2 = g.view_size()   # 战斗画面缩放：视野框按实际看得到的世界范围（拉远时比视口大）
	tb.frame(Rect2(c - view * 0.5 * k, view * k), Color(1, 1, 1, 0.2), 1.0)
	# 普通敌人的 2×2 红点收集起来一次 draw_multiline 画完（性能，协调人 9/30：后期 300 个敌人逐个 draw_rect）
	var dots := PackedVector2Array()
	for e in g.enemies:
		if e.dead:
			continue
		var p: Vector2 = (e.pos - g.ppos) * k
		if p.length() > lim:
			if e.boss:
				p = p.limit_length(lim)
			else:
				continue
		if e.get("friendly", false):
			tb.diamond(c + p, 5.0, UI.CYAN)
		elif e.boss:
			var bp := 0.5 + 0.5 * sin(g.t * 6.0)
			tb.circle(c + p, 5.0 + bp, Color(0.8, 0.3, 1.0), 14)
		elif e.chest:
			tb.rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(0.55, 0.8, 1.0) if e.get("event", "") != "" else UI.GOLD)
		elif e.elite:
			tb.rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.6, 0.25))
		else:
			dots.append(c + p - Vector2(1, 0))
			dots.append(c + p + Vector2(1, 0))
	if not dots.is_empty():
		g.hud.draw_multiline(dots, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.85), 2.0)
	for g_item in g.gems:
		if g_item.dead or not g_item.special:   # special = 磁铁 / 回复药剂 / 宝箱（pickups.drop），一次读字段代替三次比较（满地掉落时逐帧遍历）
			continue
		var p: Vector2 = ((g_item.pos - g.ppos) * k).limit_length(lim)
		tb.circle(c + p, 3.0, g.pickups.item_col(g_item.kind), 8)
	if not g.merchant.is_empty():
		var mp: Vector2 = ((g.merchant.pos - g.ppos) * k)
		var clipped := mp.length() > lim
		mp = mp.limit_length(lim)
		tb.diamond(c + mp, 5.0 + (1.5 * sin(g.t * 6.0) if clipped else 0.0), UI.GOLD)
	for o in g.squad.ops:
		if o.pos != Vector2.INF:
			tb.circle(c + (o.pos - g.ppos) * k, 2.0, Color(0.5, 0.9, 1.0), 6)
	if g.zone_state != 0:
		mini_circle(tb, c + (g.zone_c - g.ppos) * k, g.zone_r * k, lim, Color(0.85, 0.4, 1.0, 0.9), c)
		if g.zone_state == 1:
			mini_circle(tb, c + (g.zone_next_c - g.ppos) * k, g.zone_next_r * k, lim, Color(1, 1, 1, 0.6), c)
	tb.diamond(c, 4.0, Color(1, 1, 1))
	tb.flush(g.hud)


func mini_circle(tb: Tris, cc: Vector2, r: float, lim: float, col: Color, c: Vector2) -> void:
	var n := 48
	for i in n:
		var p0 := cc + Vector2.from_angle(TAU * i / n) * r
		var p1 := cc + Vector2.from_angle(TAU * (i + 1) / n) * r
		if (p0 - c).length() > lim or (p1 - c).length() > lim:
			continue
		tb.line(p0, p1, col, 1.5)
