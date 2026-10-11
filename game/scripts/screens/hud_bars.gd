extends RefCounted
## 界面 · HUD 左侧与顶部（2026-10-10 从 hud.gd 拆出，docs/55 §6）：左上面板（等级圆 / 生命 / 灯火 / 侵蚀）与灯火状态条、
## 顶部中央（击杀 / 时间 / 楼层 / 威胁）、Boss 大血条、人物状态栏、声呐小地图。触屏分支原样保留。
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const Tris = preload("res://scripts/screens/hud_tris.gd")
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


## 左上面板：等级圆 + 生命 / 灯火 / 神经 / 侵蚀（原 _draw_body 第一段）
func draw_top_left(vs: Vector2) -> void:
	# 左上（方案 A · 原作顶栏）：等级圆（外圈 = 经验）+「生命值」「灯火」彩色小标签头 + 数值 + 细条；
	# 名字与编队人数移到右下编队卡；下面一条灯火状态标签条在后面画（和状态效果一起）
	var o := Vector2(16, 12)
	var lf := g.hud_lv_flash
	var bc := UI.CYAN.lerp(UI.GOLD, lf).lerp(Color(0.8, 1.6, 1.8), g.xp_flash * 0.7)
	var lc0 := o + Vector2(26, 30)
	h.batch_begin()   # 左上面板：色块一批、字最后（性能 9/30）
	UI.ring(g.hud, lc0, 22.0 + 3.0 * lf, g.xp / g.xp_need, bc, lf > 0.2)
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
		st_txt = "灯火暗淡 · 敌人更快更凶更多 · 拾取 -30%"
		st_en = "DARK"
		st_col = Color(1, 0.5, 0.5)
	elif g.lamp >= 70.0:
		st_txt = "灯火通明 · 技力 +30% · 拾取 +20%"
	else:
		st_txt = "灯火摇曳 · 光中敌人受伤 +25%"
		st_en = "LIT"
		st_col = Color(1.0, 0.85, 0.6)
	h.batch_begin()
	UI.strip(g.hud, g.font, o + Vector2(2, 66), st_en, st_txt, st_col, st_col.lerp(UI.TEXT, 0.45))
	h.batch_end()


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
	UI.quatrefoil(g.hud, Vector2(cx0, 64), 34.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.28), 1.6)
	var fname: String = "Boss 演练" if g.trial.active else tr.name
	var fen: String = "TRIAL" if g.trial.active else String(tr.get("en", ""))
	var fw0 := g.font.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var few := UI.en_width(g.font, fen, 10, 3.0)
	var fx0 := cx0 - (14.0 + fw0 + 10.0 + few) / 2.0
	UI.diamond(g.hud, Vector2(fx0 + 4, 61), 3.5, UI.GOLD)
	UI.text(g.hud, g.font, Vector2(fx0 + 14, 66), fname, 14, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	UI.en(g.hud, g.font, Vector2(fx0 + 24 + fw0, 65), fen, 10, UI.SUB, 3.0)
	UI.gbar(g.hud, Rect2(cx0 - 70, 73, 140, 2), tfrac, tcol)
	var threat_label := "不记录通关进度" if g.trial.active else ("威胁 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][g.threat]) + (("  ·  %s" % D.DIFFICULTY_TIERS[g.tier].name) if g.tier > 0 else "")
	UI.text(g.hud, g.font, Vector2(cx0 - 150, 90), threat_label, 14 if g.touch.active else 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300, 2)


## Boss 血条块的实际底部（没有血条时 0）；横幅（hud_banners.banner_y）与 Boss 登场名片从这里往下让
var boss_bottom := 0.0


## 招式名在副标题行停留的秒数（boss_ai 出招时写 e.move_name / e.move_t）
const MOVE_NAME_T := 1.6


## 顶部 Boss 大血条的对象（2026-09-27 用户报 bug：碎片 / 之泪这类召唤物进了 g.bosses，屏幕中间叠了 6 条）：
## 只算活着、且 enemies.json 里 role == "boss" 的；两体 Boss（接潮双体等）正好 2 条，所以上限 2
const BOSS_BARS_MAX := 2


## Boss 大血条（最多 BOSS_BARS_MAX 条，多的写一行「另有 N 个 Boss」），画完记下 boss_bottom
func draw_boss_bars(vs: Vector2) -> void:
	# Boss 血条：只给真 Boss 画（boss_bars），最多 BOSS_BARS_MAX 条，多出来的写一行「另有 N 个 Boss」
	var bby := 0.0
	var bars: Array = boss_bars()
	for bi in mini(bars.size(), BOSS_BARS_MAX):
		var shown: Dictionary = bars[bi]
		var bw := 620.0
		var bx := vs.x / 2 - bw / 2
		g.hud.draw_set_transform(Vector2(0, bby), 0.0, Vector2.ONE)
		bby += 54.0
		if shown.type == "ishar" and shown.get("friendly", false):
			draw_ishar_human(shown, bx, bw)
			g.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		# 洋红 = 危险（原作「险路恶敌」）：暗底 + 顶部洋红细线 + BOSS 节点标签条
		var bbr := Rect2(bx - 12, 100, bw + 24, 46)
		g.hud.draw_rect(bbr, Color(0.03, 0.035, 0.045, 0.8))
		g.hud.draw_rect(Rect2(bbr.position, Vector2(bbr.size.x, 1)), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.7))
		var sw: float = UI.strip(g.hud, g.font, Vector2(bx, 106), "BOSS", shown.name, UI.RED, Color(1, 0.82, 0.88), 12)
		# 名字旁的形态小圆点（§1.15）：总幕数 = 剩余刻度 + 已过刻度 + 1，亮的是还没打完的幕（含当前这一幕）
		var gl: Array = shown.get("gates", [])
		var gp: int = int(shown.get("gates_passed", 0))
		var acts: int = gl.size() + gp + 1
		if acts > 1:
			for q in acts:
				var dc := Vector2(bx + sw + 10.0 + q * 11.0, 116.0)
				if q >= gp:
					g.hud.draw_circle(dc, 3.5, UI.RED)
				else:
					g.hud.draw_arc(dc, 3.5, 0.0, TAU, 12, Color(1, 1, 1, 0.3), 1.0)
		# 伊祖米克学习期吸收层数（e.izu_layers 0–5）：名字旁五枚小菱形，亮的是已吸收层
		if shown.has("izu_layers"):
			var izx: float = bx + sw + 14.0 + (acts * 11.0 if acts > 1 else 0.0)
			UI.text(g.hud, g.font, Vector2(izx, 121), "吸收", 10, UI.SUB)
			for q in 5:
				var lit_l: bool = q < int(shown.izu_layers)
				UI.diamond(g.hud, Vector2(izx + 30 + q * 11.0, 116.0), 4.0, Color(0.55, 1.0, 0.95) if lit_l else Color(1, 1, 1, 0.08), Color(0.6, 1.0, 1.0, 0.8 if lit_l else 0.3))
		var brk: float = shown.get("break_t", 0.0)
		var hold: bool = shown.get("gate_hold", false)
		var sub := ""
		var sub_col := UI.SUB
		var mv_name: String = shown.get("move_name", "")
		if brk > 0.0:
			sub = "破绽 %.1f 秒 · 受到的伤害 +%d%%" % [brk, roundi((Game.Bal.v("boss/break_mult", 1.4) - 1.0) * 100.0)]
			sub_col = UI.GOLD
		elif hold:
			sub = "阶段护盾 · 本幕时限到后破碎"
			sub_col = UI.GOLD
		elif mv_name != "" and g.t - float(shown.get("move_t", -99.0)) < MOVE_NAME_T:
			sub = mv_name   # 招式名进副标题行，不再头顶浮字（§1.15）
			sub_col = Color(1, 0.82, 0.88)
		elif shown.type == "izumik":
			sub = "学习阶段 · 无敌（击杀子代阻止它成长）" if shown.phase == 1 else "解读阶段"
		elif shown.type == "ishar":
			sub = "转化中" if shown.phase == 1 else "已完成转化 · 敌对"
		elif shown.has("ammo"):
			sub = "装填中 —— 攻击以打断！" if shown.channel > 0.0 else ("弹药 %d / 3" % shown.ammo if shown.ammo > 0 else "近战中")
		elif shown.get("coma", false):
			sub = "假死中 —— 趁现在击倒另一体！"
		elif D.ENEMIES[shown.type].get("pair", false):
			sub = "两体需同时击倒"
		elif shown.type == "paranoia":
			sub = ("悬浮形态（打到 1/3 血坠落）" if Game.Bal.v("boss/paranoia_p2_at_gate", 1.0) > 0.0 else "悬浮形态（结茧后坠落）") if shown.phase == 1 else "第二形态"
		UI.text(g.hud, g.font, Vector2(bx + bw - 400, 122), sub, 12, sub_col, HORIZONTAL_ALIGNMENT_RIGHT, 400)
		# 血条颜色：破绽中金色；阶段护盾时金色闪；无敌灰蓝；平时洋红
		var bcol: Color = UI.RED
		if brk > 0.0:
			bcol = UI.GOLD
		elif hold:
			bcol = UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 10.0))
		elif shown.invuln:
			bcol = Color(0.45, 0.6, 0.7)
		UI.gbar(g.hud, Rect2(bx, 131, bw, 6), shown.hp / shown.maxhp, bcol, 20)
		# 阶段刻度：剩余刻度画在血条上（最大生命比例），停在刻度上（阶段护盾）时那一道发光
		for gi in gl.size():
			var gx: float = bx + bw * float(gl[gi])
			var lit: bool = hold and gi == 0
			var gc: Color = UI.GOLD if lit else Color(1, 1, 1, 0.85)
			if lit:
				g.hud.draw_rect(Rect2(gx - 3, 126, 6, 16), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35 + 0.25 * sin(g.t * 10.0)))
			g.hud.draw_rect(Rect2(gx - 1, 128, 2, 12), Color(0.02, 0.02, 0.03, 0.9))
			g.hud.draw_rect(Rect2(gx - 0.5, 129, 1, 10), gc)
		# 韧性条（§1.15）：贴在血条下沿 3px，只有开了韧性的 Boss（tough_need > 0 且在白名单里被累计）才画
		var tn: float = shown.get("tough_need", 0.0)
		if tn > 0.0 and shown.get("tough", 0.0) > 0.0 and brk <= 0.0:
			g.hud.draw_rect(Rect2(bx, 138, bw, 3), Color(1, 1, 1, 0.1))
			g.hud.draw_rect(Rect2(bx, 138, bw * clampf(shown.tough / tn, 0.0, 1.0), 3), Color(0.95, 0.85, 0.55))
		g.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bars.size() > BOSS_BARS_MAX:
		var ot := "另有 %d 个 Boss" % (bars.size() - BOSS_BARS_MAX)
		var ow: float = g.font.get_string_size(ot, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
		g.hud.draw_rect(Rect2(vs.x / 2.0 - ow / 2.0, 100 + bby - 2, ow, 20), Color(0.03, 0.035, 0.045, 0.8))
		UI.text(g.hud, g.font, Vector2(0, 100 + bby + 13), ot, 12, Color(1, 0.82, 0.88), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		bby += 22.0
	boss_bottom = 100.0 + bby if bby > 0.0 else 0.0


func draw_ishar_human(e: Dictionary, bx: float, bw: float) -> void:
	var rect := Rect2(bx - 12, 100, bw + 24, 46)
	g.hud.draw_rect(rect, Color(0.03, 0.035, 0.045, 0.8))
	g.hud.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color(UI.CYAN, 0.7))
	UI.strip(g.hud, g.font, Vector2(bx, 106), "NEUTRAL", e.name, UI.CYAN, UI.TEXT, 12)
	var progress: float = clampf(float(e.get("ally_charge", 0.0)) / maxf(0.01, float(e.get("ally_charge_need", 30.0))), 0.0, 1.0)
	UI.text(g.hud, g.font, Vector2(bx + bw - 300, 122), "人形 · 治疗海嗣 / 转化充能 %d%%" % roundi(progress * 100.0), 12, UI.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	UI.gbar(g.hud, Rect2(bx, 131, bw, 6), progress, UI.CYAN, 20)


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
	if g.state == Game.S.OPENING or g.state == Game.S.INTRO or g.state == Game.S.SHOW:
		return
	var items: Array = []   # [文字, 颜色, 进度 0..1 或 -1]
	for it in g.ch.status_items():
		items.append(it if it.size() >= 3 else [it[0], it[1], -1.0])
	if g.shield > 0:
		items.append(["护盾 ×%d" % g.shield, Color(0.6, 0.9, 1.0), -1.0])
	for x in g.rfx.temps:
		if x.stat == "dmg":
			items.append(["增伤 +%d%%" % int(x.value * 100.0), Color(1.0, 0.75, 0.4), clampf((x.until - g.t) / 6.0, 0.0, 1.0)])
		elif x.stat == "op_aspd":
			items.append(["攻速 +%d%%" % int(x.value * 100.0), Color(1.0, 0.9, 0.5), clampf((x.until - g.t) / 10.0, 0.0, 1.0)])
		elif x.stat == "dmg_taken":
			items.append(["减伤 %d%%" % int(-x.value * 100.0), Color(0.6, 0.9, 1.0), clampf((x.until - g.t) / 5.0, 0.0, 1.0)])
	if g.rfx.rule("black_tulip") > 0 and g.rfx.tulip_t > 1.0:
		items.append(["郁金香 +%d%%" % int(80.0 * g.rfx.tulip_t / 60.0), Color(1.0, 0.6, 0.7), g.rfx.tulip_t / 60.0])
	if g.rfx.perm_dmg > 0.0:
		items.append(["刻勋 +%.1f%%" % (g.rfx.perm_dmg * 100.0), Color(1.0, 0.85, 0.5), -1.0])
	if g.rfx.king_low() and (g.rfx.rule("king_crown") + g.rfx.rule("king_gun") + g.rfx.rule("king_cake") + g.rfx.rule("king_branch")) > 0:
		items.append(["国王之势", Color(1.0, 0.8, 0.3), -1.0])
	if g.corrode_pool > 0.5:
		items.append(["侵蚀 %d" % int(g.corrode_pool), Color(0.8, 0.5, 1.0), -1.0])
	# 神经损伤（Boss与怪物 419c84d：0–nerve_max，站在溟痕 / 巢涌者光环里上涨；满格后 nerve_lock 秒锁定）
	var nlock: float = float(g.get("nerve_lock")) if g.get("nerve_lock") != null else 0.0
	var nmax: float = g.combat.nerve_max() if g.combat.has_method("nerve_max") else 100.0
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
			items.append(["认知负担 · 攻速 −%d%%" % roundi(Game.Bal.v("boss/paranoia_aura_aspd", 0.10) * 100.0), Color(0.85, 0.55, 1.0), -1.0])
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
	if items.is_empty():
		return
	var x := 18.0
	var y := 104.0
	# 换行宽度（§1.15）：min(360, Boss 血条框左边 − 8)，有 Boss 血条时不钻到血条框下面
	var wrap_x := 360.0
	if not boss_bars().is_empty():
		wrap_x = minf(360.0, g.hud.size.x / 2.0 - 310.0 - 12.0 - 8.0)
	for it in items:
		var cw: float = g.font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0   # 与 UI.chip 的宽度算法一致
		if x + cw > wrap_x and x > 18.0:
			x = 18.0
			y += 26.0
		var w: float = UI.chip(g.hud, g.font, Vector2(x, y), it[0], it[1], 12)
		if it[2] >= 0.0:
			g.hud.draw_rect(Rect2(x, y + 20, w * it[2], 2), it[1])
		x += w + 6.0


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func draw_minimap(vs: Vector2) -> void:
	var rad := 78.0
	var c := Vector2(16 + rad + 8, vs.y - rad - 24)
	UI.porthole(g.hud, c, rad, UI.GLOW)
	var slr := Rect2(Vector2(c.x - rad + 2, c.y - rad - 8), Vector2(UI.en_width(g.font, "SONAR", 9, 2.0) + 10.0, 14))
	g.hud.draw_rect(slr, Color(1, 1, 1, 0.14))
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
	var view := g.get_viewport_rect().size
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
		if g_item.dead or not (g_item.kind == "magnet" or g_item.kind == "heal" or g_item.kind == "chest"):
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
