## 羁绊技第四轮画面（docs/314，11-07 用户选定的五条：狼衔剑 / 串刺 / 击锯 / 钉桩回旋 / 收力一剑）。
## 概念动画在 tools/pixelfx_fx/bond/*.js（用户看过的 GIF）；这里按同一套时序在运行时逐格画（2 px 格，硬边，不旋转贴图像素），
## 时刻与位置函数全取 run/bond2.gd（B2.rv_wolf / td_head / fn_saw / vx_anchor / ls_anchor），玩法与画面不会对不上。
## 只画：读 fx_bond2 的 items（k = "b3"），不碰玩法、不抽玩法随机数。颗粒 / 照地光走 fx_bond2 的 due（fx_recipe 颗粒池）。
extends RefCounted

const B2 = preload("res://scripts/run/bond2.gd")

const TX := [Color("#2c1406"), Color("#5a2808"), Color("#9c4610"), Color("#e2781c"), Color("#ffac3c"), Color("#ffdc9c"), Color("#ffffff")]
const LP := [Color("#15121f"), Color("#2b2542"), Color("#4a4274"), Color("#7b70b4"), Color("#b3aae4"), Color("#e4e0ff"), Color("#ffffff")]
const SK := [Color("#0b1a3a"), Color("#1c3570"), Color("#3a62c0"), Color("#598cf2"), Color("#93b4f7"), Color("#cddcfb"), Color("#ffffff")]
const GL := [Color("#0d1a2e"), Color("#1f3658"), Color("#35598f"), Color("#4c80c7"), Color("#7fa6e0"), Color("#c9d9ee"), Color("#ffffff")]
const SPP := [Color("#0d1832"), Color("#1d3866"), Color("#2c5a9a"), Color("#3a77c2"), Color("#78afe6"), Color("#c4e2fa"), Color("#ffffff")]
const SPA := Color("#ffa04a")
const ULP := [Color("#0c1235"), Color("#1a2766"), Color("#2e45a0"), Color("#4463c8"), Color("#7b93e6"), Color("#c0cbf6"), Color("#ffffff")]
const STEEL := [Color("#3a4250"), Color("#7a8494"), Color("#c8d0dc")]
const WATER := Color(0.86, 0.93, 1.0)
const SQ := 0.72
## 狼影（朝右，24 × 11 格，每格 = 2 美术像素 = 4 世界像素），两帧跑步：+ 背上受光沿、# 身体、o 眼、- 嘴（同 tools/pixelfx_fx/bond/bond-wolfsword.js）
const WOLF := [
	["                 +  +   ", "                +####   ", "  +            +#####o+ ", " ++#++++++++++++######--", "  #################     ", "   ################     ", "   ###############      ", "   ##  ##     ## ##     ", "  ##    ##   ##   ##    ", " ##      #  ##     ##   ", "##       ## #       #   "],
	["                 +  +   ", "                +####   ", "               +#####o+ ", " ++++++++++++++#######--", "+##################     ", "   ################     ", "    ##############      ", "     ## ##   ## ##      ", "     # ##    ##  #      ", "    ## #     #   ##     ", "    #  ##   ##    #     "],
]
const ANCHOR_TEX := "res://art/fx/fx_bd2_anchor@2x.png"   # 112 × 150，底边中心着地


# ================================================================ 出招：推画面件（r = fx_bond2 实例）

static func cast(r, a: Dictionary) -> void:
	var t: float = r.g.t
	var life: float = {"b_rival": 2.1, "b_lesson": 1.95, "b_tide": 1.8, "b_vortex": 2.2, "b_fins": 1.7}.get(str(a.id), 2.0)
	r._push({"k": "b3", "ly": "gd", "a": a, "t0": t, "life": life})
	r._push({"k": "b3", "ly": "up", "a": a, "t0": t, "life": life})
	var w: Dictionary = a.who
	match str(a.id):
		"b_rival":
			r.due.append([t + B2.RV_DROP, "grains", {"o": w.texas, "p": Vector2(a.S) + Vector2(0, 12), "n": 12, "c0": TX[5], "c1": TX[3], "mat": "streak"}])
			r.due.append([t + B2.RV_STAB, "grains", {"o": w.texas, "p": Vector2(a.E) + Vector2(0, 12), "n": 18, "c0": Color(1.0, 0.9, 0.7), "c1": TX[3], "mat": "ember"}])
			r.due.append([t + B2.RV_RUN, "grains", {"o": w.lappland, "p": Vector2(a.E) + Vector2(0, -10), "n": 16, "c0": LP[5], "c1": LP[3], "mat": "rise"}])
		"b_tide":
			r.due.append([t + B2.TD_STICK, "grains", {"o": w.gladiia, "p": Vector2(a.E) + Vector2(0, 12), "n": 12, "c0": WATER, "c1": GL[4], "mat": "drop"}])
			r.due.append([t + B2.TD_SAW, "grains", {"o": w.specter_unchained, "p": Vector2(a.P) + Vector2(0, 12), "n": 16, "c0": Color(1.0, 0.85, 0.6), "c1": SPA, "mat": "streak"}])
		"b_fins":
			r.due.append([t + B2.FN_BAT, "light", {"o": w.skadi, "p": Vector2(a.H) + Vector2(0, -60), "r": 120.0, "i": 0.8, "c": Color(1, 1, 1), "life": 0.12}])
			r.due.append([t + B2.FN_END, "grains", {"o": w.specter_unchained, "p": Vector2(a.E) + Vector2(0, 12), "n": 18, "c0": Color(1.0, 0.85, 0.6), "c1": SPA, "mat": "streak"}])
		"b_vortex":
			r.due.append([t + B2.VX_STAKE, "grains", {"o": w.gladiia, "p": Vector2(a.c) + Vector2(0, 12), "n": 10, "c0": WATER, "c1": GL[4], "mat": "drop"}])
			r.due.append([t + B2.VX_SLAM, "grains", {"o": w.ulpianus, "p": Vector2(a.c) + Vector2(0, 12), "n": 22, "c0": WATER, "c1": ULP[4], "mat": "drop"}])
		"b_lesson":
			r.due.append([t + B2.LS_BITE, "grains", {"o": w.ulpianus, "p": Vector2(a.F) + Vector2(0, 12), "n": 10, "c0": Color(0.42, 0.44, 0.5), "c1": Color(0.2, 0.22, 0.26), "mat": "rock"}])
			r.due.append([t + B2.LS_CUT, "grains", {"o": w.skadi, "p": Vector2(a.Pp) + Vector2(0, 12), "n": 16, "c0": WATER, "c1": SK[4], "mat": "drop"}])


static func sort_key(it: Dictionary) -> float:
	return -1.0e9 if str(it.ly) == "gd" else 1.0e9 - 3.0


static func draw(r, ci, it: Dictionary) -> void:
	var a: Dictionary = it.a
	var t: float = r.g.t - float(it.t0)
	var gd: bool = str(it.ly) == "gd"
	match str(a.id):
		"b_rival":
			_rival(r, ci, a, t, gd)
		"b_tide":
			_tide(r, ci, a, t, gd)
		"b_fins":
			_fins(r, ci, a, t, gd)
		"b_vortex":
			_vortex(r, ci, a, t, gd)
		"b_lesson":
			_lesson(r, ci, a, t, gd)


# ================================================================ 小件

static func _ln(r, ci, p0: Vector2, p1: Vector2, c: Color, step := 1.0) -> void:
	var n: int = maxi(1, int(p0.distance_to(p1) / (r.g.PX * step)))
	for i in n + 1:
		r._cell(ci, p0.lerp(p1, float(i) / float(n)), c)


## 粗条：中线亮、两侧暗（w = 半宽，世界像素）
static func _bar(r, ci, p0: Vector2, p1: Vector2, w: float, cols: Array, al := 1.0) -> void:
	var d: Vector2 = (p1 - p0).normalized()
	var nv: Vector2 = d.orthogonal()
	var px: float = r.g.PX
	var k: int = maxi(0, int(w / px))
	for j in range(-k, k + 1):
		var q: float = absf(float(j)) / maxf(1.0, float(k))
		var c: Color = cols[0] if q < 0.34 else (cols[1] if q < 0.75 else cols[2])
		_ln(r, ci, p0 + nv * float(j) * px, p1 + nv * float(j) * px, Color(c, al))


## 月牙拖影（挥砍一拍）：圆心 c、半径 R、从角 a0 扫到 a1；宽度中间粗两头尖；cols = [芯, 中, 边]
static func _crescent(r, ci, c: Vector2, R: float, a0: float, a1: float, w: float, cols: Array, al: float, teeth := false) -> void:
	var px: float = r.g.PX
	var n: int = maxi(8, int(absf(a1 - a0) * R / px))
	for i in n + 1:
		var u: float = float(i) / float(n)
		var an: float = lerpf(a0, a1, u)
		var ww: float = w * sin(PI * u) + px
		var dv := Vector2(cos(an), sin(an) * SQ)
		for s in range(0, int(ww / px) + 1):
			var v: float = float(s) * px / maxf(px, ww)
			r._cell(ci, c + dv * (R - float(s) * px), Color(cols[0] if v < 0.3 else (cols[1] if v < 0.65 else cols[2]), al))
		if teeth and i % 5 == 0:
			r._cell(ci, c + dv * (R + px), Color(SPA if i % 10 == 0 else cols[0], al))
			r._cell(ci, c + dv * (R + px * 2.0) + Vector2(dv.y, -dv.x) * px, Color(cols[1], al))
		if i % 6 == 0:
			r._glow(c + dv * R, cols[0])


## 巨剑：剑柄 h、角度 an（0 = 剑尖朝右）、长 L；德克萨斯琥珀刃
static func _sword(r, ci, h: Vector2, an: float, L: float, al := 1.0) -> void:
	var d := Vector2.from_angle(an)
	var tip: Vector2 = h + d * L
	_bar(r, ci, h + d * 10.0, tip - d * 8.0, 8.0, [TX[6], TX[4], TX[2]], al)
	_bar(r, ci, tip - d * 10.0, tip, 2.0, [TX[6], TX[5], TX[3]], al)
	_bar(r, ci, h - d.orthogonal() * 12.0 + d * 8.0, h + d.orthogonal() * 12.0 + d * 8.0, 2.0, [TX[3], TX[2], TX[1]], al)   # 护手
	_bar(r, ci, h - d * 6.0, h + d * 6.0, 2.0, [TX[1], TX[0], TX[0]], al)   # 柄
	for i in 4:
		r._glow(h.lerp(tip, 0.25 + 0.2 * float(i)), TX[4])


## 长槊：槊尖 p、朝向 d、杆长 L；歌蕾蒂娅钢蓝 + 倒刺
static func _spear(r, ci, p: Vector2, d: Vector2, L: float, al := 1.0) -> void:
	_bar(r, ci, p - d * L, p - d * 12.0, 3.0, [GL[5], GL[3], GL[1]], al)
	var nv: Vector2 = d.orthogonal()
	for k in 7:
		var w: float = 11.0 * (1.0 - float(k) / 7.0)
		_ln(r, ci, p - d * (14.0 - float(k) * 2.0) + nv * w, p - d * (14.0 - float(k) * 2.0) - nv * w, Color(GL[6] if k > 4 else GL[5], al))
	_ln(r, ci, p - d * 20.0 + nv * 10.0, p - d * 12.0 + nv * 4.0, Color(GL[4], al))
	_ln(r, ci, p - d * 20.0 - nv * 10.0, p - d * 12.0 - nv * 4.0, Color(GL[4], al))
	r._glow(p, GL[5])
	r._glow(p - d * 8.0, GL[5])


## 锯刃：中心 p、半径 R、转角 sp；钢灰 + 橙齿（幽灵鲨点缀色）
static func _saw(r, ci, p: Vector2, R: float, sp: float, hot: bool, al := 1.0) -> void:
	var px: float = r.g.PX
	var n: int = int(R / px)
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			var dd: float = Vector2(x, y).length()
			if dd > float(n):
				continue
			var c: Color = STEEL[1] if dd > float(n) - 2.5 else (STEEL[2] if x + y < -n / 2 and dd < float(n) * 0.5 else STEEL[0])
			r._cell(ci, p + Vector2(x, y) * px, Color(c, al))
	for i in 12:
		var an: float = sp + TAU * float(i) / 12.0
		var dv := Vector2.from_angle(an)
		var tg := Vector2.from_angle(an + PI * 0.5)
		for k in 3:
			r._cell(ci, p + dv * (R + float(k) * px) + tg * float(k) * px, Color(SPA if i % 2 == 0 else STEEL[2], al))
	if hot:
		for i in 4:
			r._glow(p + Vector2.from_angle(sp + float(i) * 1.57) * R, SPA)


## 锚（贴图，可转）：脚点 p、角 an（0 = 锚冠朝下立着）、缩放 sc
static func _anchor(r, ci, p: Vector2, an: float, sc: float, al := 1.0) -> void:
	var tex: Texture2D = r._tex(ANCHOR_TEX)
	if tex == null:
		return
	var sz: Vector2 = tex.get_size() * sc
	ci.draw_set_transform(r._snap(p), an, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false, Color(1, 1, 1, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 锚链：一环横一环竖（3 × 4 格），sag = 中段下垂
static func _chain(r, ci, p0: Vector2, p1: Vector2, sag := 0.0, al := 1.0) -> void:
	var px: float = r.g.PX
	var L: float = p0.distance_to(p1)
	var n: int = maxi(2, int(L / (px * 5.0)))
	var d: Vector2 = (p1 - p0) / maxf(1.0, L)
	var nv: Vector2 = d.orthogonal()
	for i in n + 1:
		var u: float = float(i) / float(n)
		var q: Vector2 = p0.lerp(p1, u) + Vector2(0, sag * sin(PI * u))
		var vert: bool = i % 2 == 0
		for x in range(-1, 2):
			for y in range(-2, 2):
				if absi(x) < 1 and y > -2 and y < 1:
					continue
				var off: Vector2 = (d * float(x) + nv * float(y)) if vert else (d * float(y) + nv * float(x))
				r._cell(ci, q + off * px, Color(ULP[4] if y == -2 else ULP[2], al))


## 狼影：脚点 p（胸前叼剑处）、朝向 fs（±1）、帧 fr、透明度 al
static func _wolf(r, ci, p: Vector2, fs: float, fr: int, al: float) -> void:
	var px: float = r.g.PX * 2.5
	var rows: Array = WOLF[fr]
	var cols := {"#": LP[2], "+": LP[5], "o": Color("#ff5ad0"), "-": LP[4]}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch: String = row[x]
			if ch == " ":
				continue
			var q := Vector2((float(x) - 22.0) * px * fs, (float(y) - 11.0) * px)
			ci.draw_rect(Rect2(r._snap(p + q), Vector2(px, px)), Color(cols[ch], al))
			if ch == "+" and x % 3 == 0:
				r._glow(p + q, LP[4])
	r._glow(p + Vector2(-20.0 * fs, -24.0), LP[4])


static func _pos(o, fb: Vector2) -> Vector2:
	return o.pos if o != null and is_instance_valid(o) and o.pos != Vector2.INF else fb


## 头顶抡锚：手 hand、第 k（0..1）圈；返回锚的位置
static func _spin(hand: Vector2, k: float) -> Vector2:
	var an: float = PI * 0.5 + k * k * PI * 2.5
	return hand + Vector2(cos(an) * 34.0, -26.0 + sin(an) * 14.0)


# ================================================================ 宿敌「狼衔剑」

static func _rival(r, ci, a: Dictionary, t: float, gd: bool) -> void:
	var S: Vector2 = a.S
	var E: Vector2 = a.E
	var dl: Vector2 = a.dl
	var fs: float = dl.x
	if gd:   # 剑尖犁出的沟：新犁的一段琥珀热、往回冷成暗痕；钉剑后 0.6 秒淡掉
		if t < B2.RV_GRAB:
			return
		var wp: Vector2 = B2.rv_wolf(a, minf(t, B2.RV_RUN))
		var fade: float = 1.0 - clampf((t - B2.RV_STAB - 0.1) / 0.5, 0.0, 1.0)
		var px: float = r.g.PX
		var n: int = int(S.distance_to(wp) / px)
		for i in n:
			var q: Vector2 = S + dl * float(i) * px - dl * 130.0
			var heat: float = 1.0 - clampf(float(n - i) * px / 160.0, 0.0, 1.0)
			var j: float = round(sin(float(i) * 0.9) * 0.7 + sin(float(i) * 0.31) * 0.8) * px
			r._cell(ci, q + Vector2(0, 8.0 + j), Color(TX[4].lerp(Color(0.24, 0.15, 0.1), 1.0 - heat), fade))
			if i % 2 == 0:
				r._cell(ci, q + Vector2(0, 10.0 + j), Color(0.08, 0.06, 0.07, 0.8 * fade))
			if heat > 0.7 and i % 4 == 0:
				r._glow(q + Vector2(0, 8.0), TX[4])
		return
	# 巨剑：落下插地 → 被叼着拖（剑尖朝后下）→ 甩上天转一圈 → 钉进 E
	if t < B2.RV_STAB + 0.7:
		var h: Vector2
		var an: float
		var al: float = 1.0 - clampf((t - B2.RV_STAB - 0.3) / 0.4, 0.0, 1.0)
		if t < B2.RV_DROP:
			var k: float = t / B2.RV_DROP
			h = S + Vector2(0, -150.0 + (1.0 - (1.0 - k) * (1.0 - k)) * 0.0 - 260.0 * (1.0 - k * k))
			an = PI * 0.5
		elif t < B2.RV_GRAB:
			h = S + Vector2(0, -150.0)
			an = PI * 0.5
		elif t < B2.RV_RUN:
			h = B2.rv_wolf(a, t) + Vector2(10.0 * fs, -40.0)
			an = PI - 0.33 if fs > 0.0 else 0.33
		elif t < B2.RV_STAB:
			var k2: float = (t - B2.RV_RUN) / (B2.RV_STAB - B2.RV_RUN)
			h = E + Vector2(0, -150.0 - 170.0 * sin(PI * k2))
			an = (PI - 0.33 if fs > 0.0 else 0.33) + k2 * (TAU + PI * 0.5 - 0.33) * fs
		else:
			h = E + Vector2(0, -150.0)
			an = PI * 0.5
		_sword(r, ci, h, an, 180.0, al)
	# 狼影：拉普兰德身边聚形 → 叼剑犁过去 → 到头散开
	if t > 0.15 and t < B2.RV_RUN + 0.08:
		var aw: float = clampf((t - 0.15) / 0.3, 0.0, 1.0) * (1.0 - clampf((t - B2.RV_RUN + 0.04) / 0.1, 0.0, 1.0))
		var fr: int = int(floor(r.g.t * 14.0)) % 2
		_wolf(r, ci, B2.rv_wolf(a, t) + Vector2(14.0 * fs, -4.0 - 2.0 * float(fr)), fs, fr, aw * 0.95)
	if t > B2.RV_STAB and t < B2.RV_STAB + 0.07:   # 钉剑那一拍：白闪一小圈
		for i in 24:
			var dv := Vector2.from_angle(TAU * float(i) / 24.0)
			r._cell(ci, E + Vector2(dv.x, dv.y * SQ) * 36.0 + Vector2(0, -6), Color(1, 1, 1, 0.9))


# ================================================================ 引潮夺命「串刺」

static func _tide(r, ci, a: Dictionary, t: float, gd: bool) -> void:
	var G: Vector2 = a.G
	var E: Vector2 = a.E
	var d: Vector2 = (E - G).normalized()
	if gd:   # 槊拖回时犁出的水痕（碎点）
		if t < B2.TD_PULL or t > B2.TD_BACK + 0.6:
			return
		var hp: Vector2 = B2.td_head(a, minf(t, B2.TD_BACK))
		var fade: float = 1.0 - clampf((t - B2.TD_BACK) / 0.6, 0.0, 1.0)
		var px: float = r.g.PX
		var n: int = int(hp.distance_to(E) / px)
		for i in n:
			var hz: float = sin(float(i) * 1.3) * 0.5 + 0.5
			if hz > 0.3:
				r._cell(ci, hp + d * float(i) * px + Vector2(0, 6.0 + round(sin(float(i) * 0.4)) * px), Color(GL[1].lerp(GL[3], hz), 0.85 * fade))
		return
	if t >= 0.08 and t < B2.TD_BACK + 0.05:
		var hp2: Vector2 = B2.td_head(a, t) + Vector2(0, -14)
		var L: float = 210.0
		if t < B2.TD_THROW:   # 举槊（在她手边往后拉）
			hp2 = G + Vector2(0, -24) + d * (20.0 - 30.0 * (t - 0.08) / (B2.TD_THROW - 0.08))
		var shake: Vector2 = Vector2.ZERO
		if t >= B2.TD_STICK and t < B2.TD_PULL:
			shake = d.orthogonal() * sin(r.g.t * 90.0) * 3.0 * (1.0 - (t - B2.TD_STICK) / (B2.TD_PULL - B2.TD_STICK))
		_spear(r, ci, hp2, d, L, 1.0)
		if shake != Vector2.ZERO:
			_bar(r, ci, hp2 - d * L + shake, hp2 - d * L * 0.6 + shake, 1.0, [GL[4], GL[3], GL[2]], 0.6)
		if t >= B2.TD_THROW and t < B2.TD_STICK:   # 速度线
			for i in 5:
				var q: Vector2 = hp2 - d * (L + 30.0 + 40.0 * float(i)) + d.orthogonal() * (8.0 if i % 2 == 0 else -8.0)
				_ln(r, ci, q, q + d * 26.0, Color(GL[4], 0.7 - 0.12 * float(i)), 1.5)
	var sa: float = t - B2.TD_SAW + 0.06
	if sa > 0.0 and sa < 0.34:   # 幽灵鲨一刀锯开：从头顶往下劈过槊线的带齿月牙
		var sp = a.who.specter_unchained
		var c0: Vector2 = _pos(sp, a.P) + Vector2(0, -40)
		var k: float = 1.0 - pow(1.0 - clampf(sa / 0.08, 0.0, 1.0), 4.0)
		var fade2: float = 1.0 - clampf((sa - 0.1) / 0.24, 0.0, 1.0)
		var base: float = (Vector2(a.P) - c0).angle()
		_crescent(r, ci, c0, maxf(80.0, c0.distance_to(a.P) + 20.0), base - 1.3, base - 1.3 + 2.6 * k, 16.0, [SPP[6], SPP[5], SPP[3]], fade2, true)


# ================================================================ 双鳍「击锯」

static func _fins(r, ci, a: Dictionary, t: float, gd: bool) -> void:
	var H: Vector2 = a.H
	var E: Vector2 = a.E
	var d: Vector2 = (E - H).normalized()
	if gd:   # 锯过的地痕：橙热 → 冷暗
		if t < B2.FN_GO or t > B2.FN_END + 0.6:
			return
		var sp: Vector2 = B2.fn_saw(a, minf(t, B2.FN_END))
		var fade: float = 1.0 - clampf((t - B2.FN_END - 0.1) / 0.5, 0.0, 1.0)
		var px: float = r.g.PX
		var n: int = int(H.distance_to(sp) / px)
		for i in n:
			var heat: float = 1.0 - clampf(float(n - i) * px / 140.0, 0.0, 1.0)
			var j: float = round(sin(float(i) * 1.1) * 0.7) * px
			r._cell(ci, H + d * float(i) * px + Vector2(0, 6.0 + j), Color(SPA.lerp(Color(0.22, 0.17, 0.15), 1.0 - heat), fade))
			if i % 2 == 0:
				r._cell(ci, H + d * float(i) * px + Vector2(0, 8.0 + j), Color(0.08, 0.06, 0.07, 0.8 * fade))
		return
	var sp0 = a.who.specter_unchained
	var sk = a.who.skadi
	var P0: Vector2 = _pos(sp0, H) + Vector2(10, -30)
	var A: Vector2 = H + Vector2(0, -70)   # 击球点（斯卡蒂面前、头顶高度）
	var spin: float = r.g.t * (40.0 if t > B2.FN_BAT else 16.0)
	if t < B2.FN_TOSS:
		_saw(r, ci, P0, 26.0, spin, false)
	elif t < B2.FN_BAT:
		var k: float = (t - B2.FN_TOSS) / (B2.FN_BAT - B2.FN_TOSS)
		_saw(r, ci, P0.lerp(A, k) + Vector2(0, -90.0 * sin(PI * k)), 26.0, spin, false)
	elif t < B2.FN_GO:
		_saw(r, ci, A, 26.0, spin, true)
	elif t < B2.FN_END + 0.02:
		var p: Vector2 = B2.fn_saw(a, t)
		var k3: float = clampf((t - B2.FN_GO) / (B2.FN_END - B2.FN_GO), 0.0, 1.0)
		var air: Vector2 = Vector2(0, -70.0 * maxf(0.0, 1.0 - k3 * 2.2) - 14.0)
		for j in range(1, 4):   # 拖影
			_saw(r, ci, B2.fn_saw(a, t - 0.025 * float(j)) + Vector2(0, -70.0 * maxf(0.0, 1.0 - clampf((t - 0.025 * float(j) - B2.FN_GO) / (B2.FN_END - B2.FN_GO), 0.0, 1.0) * 2.2) - 14.0), 26.0 - 3.0 * float(j), spin, false, 0.3 - 0.07 * float(j))
		_saw(r, ci, p + air, 26.0, spin, true)
	# 斯卡蒂挥棒：举剑一拍 → 一拍抡出的大月牙
	var K: Vector2 = _pos(sk, H) + Vector2(0, -30)
	var sw: float = t - (B2.FN_BAT - 0.05)
	if sw > -0.22 and sw < 0.0:
		_bar(r, ci, K, K + Vector2(-50.0 * signf(d.x + 0.001), -60.0), 3.0, [SK[6], SK[4], SK[2]], 1.0)
	if sw >= 0.0 and sw < 0.3:
		var k4: float = 1.0 - pow(2.0, -10.0 * clampf(sw / 0.06, 0.0, 1.0))
		var base: float = (A - K).angle()
		_crescent(r, ci, K, maxf(70.0, K.distance_to(A) + 10.0), base - 1.6, base - 1.6 + 2.4 * k4, 22.0, [SK[6], SK[5], SK[3]], 1.0 - clampf((sw - 0.06) / 0.24, 0.0, 1.0))
	if t > B2.FN_BAT and t < B2.FN_BAT + 0.07:
		for i in 20:
			var dv := Vector2.from_angle(TAU * float(i) / 20.0)
			r._cell(ci, A + dv * 30.0, Color(1, 1, 1, 0.9))


# ================================================================ 漩涡钉锚「钉桩回旋」

static func _vortex(r, ci, a: Dictionary, t: float, gd: bool) -> void:
	var c: Vector2 = a.c
	if gd:   # 锚扫过的水面涡纹（碎点，不画实线圈）
		if t < B2.VX_WRAP or t > B2.VX_SLAM + 0.5:
			return
		var fade: float = 1.0 - clampf((t - B2.VX_SLAM) / 0.5, 0.0, 1.0)
		var tt: float = minf(t, B2.VX_SLAM)
		var a1: float = B2.vx_ang(tt)
		var rr: float = B2.vx_rad(a, tt)
		for i in 90:
			var u: float = float(i) / 90.0
			var an: float = a1 - u * 2.4
			var r2: float = rr + u * 50.0 + sin(float(i) * 2.3) * 8.0
			if sin(float(i) * 7.1) > -0.2:
				r._cell(ci, c + Vector2(cos(an) * r2, sin(an) * r2 * B2.VX_SQ) + Vector2(0, 4), Color(GL[5] if u < 0.2 else GL[3], (1.0 - u) * 0.85 * fade))
		return
	var fade2: float = 1.0 - clampf((t - B2.VX_SLAM - 0.3) / 0.4, 0.0, 1.0)
	# 长槊：从天上竖直落下钉住
	var sy: float = -420.0 * (1.0 - clampf(t / B2.VX_STAKE, 0.0, 1.0) * clampf(t / B2.VX_STAKE, 0.0, 1.0))
	_spear(r, ci, c + Vector2(0, sy + 4.0), Vector2.DOWN, 110.0, fade2)
	# 锚：抡 → 掷出 → 缠槊绕圈 → 砸下
	var ul = a.who.ulpianus
	var hand: Vector2 = _pos(ul, c + Vector2(-300, 0)) + Vector2(10, -40)
	var top: Vector2 = c + Vector2(0, -90)
	if t < B2.VX_SPIN:
		_anchor(r, ci, hand + Vector2(10, 40), 0.0, 0.65)
	elif t < B2.VX_THROW:
		var q: Vector2 = _spin(hand, (t - B2.VX_SPIN) / (B2.VX_THROW - B2.VX_SPIN))
		_chain(r, ci, hand, q)
		_anchor(r, ci, q + Vector2(0, 30), (q - hand).angle() - PI * 0.5, 0.65)
	elif t < B2.VX_WRAP:
		var k: float = (t - B2.VX_THROW) / (B2.VX_WRAP - B2.VX_THROW)
		var s0: Vector2 = _spin(hand, 1.0)
		var dst: Vector2 = B2.vx_anchor(a, B2.VX_WRAP)
		var q2: Vector2 = s0.lerp(dst, 1.0 - (1.0 - k) * (1.0 - k)) + Vector2(0, -80.0 * sin(PI * k))
		_chain(r, ci, hand, q2 + Vector2(0, -20), 30.0 * (1.0 - k))
		_anchor(r, ci, q2 + Vector2(0, 30), k * 9.0, 0.7)
	elif t < B2.VX_SLAM:
		var q3: Vector2 = B2.vx_anchor(a, t)
		_chain(r, ci, top, q3 + Vector2(0, -30))
		_anchor(r, ci, q3 + Vector2(0, 10), B2.vx_ang(t) + PI * 0.5, 0.7)
	elif t < B2.VX_SLAM + 0.7:
		_anchor(r, ci, c + Vector2(30, 14), 0.0, 0.75, fade2)
	if t > B2.VX_SLAM and t < B2.VX_SLAM + 0.07:
		for i in 28:
			var dv := Vector2.from_angle(TAU * float(i) / 28.0)
			r._cell(ci, c + Vector2(dv.x, dv.y * SQ) * 54.0, Color(1, 1, 1, 0.9))


# ================================================================ 手术刀「收力一剑」

static func _lesson(r, ci, a: Dictionary, t: float, gd: bool) -> void:
	var F: Vector2 = a.F
	var Pp: Vector2 = a.Pp
	if gd:   # 锚拖过的地痕（碎点）
		if t < B2.LS_PULL or t > B2.LS_PILE + 0.6:
			return
		var ap: Vector2 = B2.ls_anchor(a, minf(t, B2.LS_PILE))
		var fade: float = 1.0 - clampf((t - B2.LS_PILE) / 0.6, 0.0, 1.0)
		var d: Vector2 = (F - ap).normalized()
		var px: float = r.g.PX
		var n: int = int(ap.distance_to(F) / px)
		for i in n:
			if sin(float(i) * 1.7) > -0.3:
				r._cell(ci, ap + d * float(i) * px + Vector2(0, 6.0 + round(sin(float(i) * 0.5)) * px), Color(ULP[2], 0.75 * fade))
		return
	var ul = a.who.ulpianus
	var sk = a.who.skadi
	var hand: Vector2 = _pos(ul, a.A) + Vector2(10, -40)
	if t < B2.LS_SPIN:
		_anchor(r, ci, hand + Vector2(10, 40), 0.0, 0.65)
	elif t < B2.LS_THROW:
		var q: Vector2 = _spin(hand, (t - B2.LS_SPIN) / (B2.LS_THROW - B2.LS_SPIN))
		_chain(r, ci, hand, q)
		_anchor(r, ci, q + Vector2(0, 30), (q - hand).angle() - PI * 0.5, 0.65)
	elif t < B2.LS_BITE:
		var k: float = (t - B2.LS_THROW) / (B2.LS_BITE - B2.LS_THROW)
		var q2: Vector2 = _spin(hand, 1.0).lerp(F, 1.0 - (1.0 - k) * (1.0 - k)) + Vector2(0, -90.0 * sin(PI * k))
		_chain(r, ci, hand, q2 + Vector2(0, -20), 30.0 * (1.0 - k))
		_anchor(r, ci, q2 + Vector2(0, 20), k * 9.0, 0.7)
	elif t < B2.LS_CUT + 0.3:
		var q3: Vector2 = B2.ls_anchor(a, t)
		_chain(r, ci, hand, q3 + Vector2(0, -24), 10.0 if t < B2.LS_PULL else 0.0)
		_anchor(r, ci, q3 + Vector2(0, 10), -PI * 0.5 + 0.3 if t < B2.LS_PILE else 0.0, 0.7)
	elif t < B2.LS_CUT + 0.6:
		var k2: float = (t - B2.LS_CUT - 0.3) / 0.3
		var q4: Vector2 = B2.ls_anchor(a, B2.LS_PILE).lerp(hand + Vector2(10, 40), k2 * k2) + Vector2(0, -40.0 * sin(PI * k2))
		_chain(r, ci, hand, q4 + Vector2(0, -24))
		_anchor(r, ci, q4 + Vector2(0, 10), k2 * 6.0, 0.65)
	# 斯卡蒂一剑：举剑 → 从头顶劈到那一堆上的大月牙（只到堆边）
	var K: Vector2 = _pos(sk, Pp) + Vector2(0, -30)
	var sw: float = t - B2.LS_CUT + 0.05
	if sw > -0.2 and sw < 0.0:
		_bar(r, ci, K, K + Vector2(-20.0, -70.0), 3.0, [SK[6], SK[4], SK[2]], 1.0)
	if sw >= 0.0 and sw < 0.28:
		var k5: float = 1.0 - pow(2.0, -10.0 * clampf(sw / 0.05, 0.0, 1.0))
		var base: float = (Pp - K).angle()
		_crescent(r, ci, K, maxf(70.0, K.distance_to(Pp) + 10.0), base - 2.0, base - 2.0 + 2.1 * k5, 24.0, [SK[6], SK[5], SK[3]], 1.0 - clampf((sw - 0.06) / 0.22, 0.0, 1.0))
	if t > B2.LS_CUT and t < B2.LS_CUT + 0.07:
		for i in 20:
			var dv := Vector2.from_angle(TAU * float(i) / 20.0)
			r._cell(ci, Pp + Vector2(dv.x, dv.y * SQ) * 40.0, Color(1, 1, 1, 0.9))
