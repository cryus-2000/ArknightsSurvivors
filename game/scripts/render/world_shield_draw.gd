## 队长护盾气泡绘制（world.draw_shield 一族）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world；层数比对状态 _sh_* 仍在 world 上，经 wv. 读写；_shield_edge 留在 world（render_perf_test 直接调）。
extends RefCounted

const Game = preload("res://scripts/game.gd")
const W = preload("res://scripts/render/world.gd")
const Bal = preload("res://scripts/core/balance.gd")
## 护盾（用户 10-28「护盾看不到，重新画」）：偏白淡金柔和气泡罩住队长身体中心（10-28 用户嫌条段环丑，三候选里定 B），层数 = 边缘光带厚度 + 边顶小菱形，
## 不填实心、不压脚下预警；未满时外侧细弧显示下一层充能进度。层数变化在画面这边比对得出（只画面，不改逻辑）：
## 少一层 = 碎裂（碎片颗粒 + 外扩闪环），碎时一下淡金微闪，之后 0.5 秒无敌期间边上流微光；多一层 = 边缘亮一下 + 充能完成颗粒。
## 低画质照画形状与层数，颗粒由 fx_grains 按 low_k 稀疏。
const SH_COL := Color(1.0, 0.9, 0.68)   # 偏白淡金（10-28 用户嫌原琥珀黄发光后像警示黄）


static func draw_shield(wv: W) -> void:
	var g: Game = wv.g
	var c := g.ppos + Vector2(0, -26)
	var r0 := 34.0
	var n: int = g.shield
	if wv._sh_prev < 0:
		wv._sh_prev = n
	if n < wv._sh_prev:
		wv._sh_brk_t = g.t
		_sh_burst(wv, c, r0, "sh_shard", 14)
	elif n > wv._sh_prev:
		wv._sh_chg_t = g.t
		_sh_burst(wv, c, r0, "sh_glint", 6)
	wv._sh_prev = n
	var tb: float = g.t - wv._sh_brk_t
	var tc: float = g.t - wv._sh_chg_t
	if n <= 0 and g.shield_max <= 0 and tb > 0.6:
		return
	var a_dim := 1.0 if n > 0 else 0.0
	var fresh := clampf(1.0 - tc / 0.35, 0.0, 1.0)   # 刚充好一层：边缘亮一下
	match int(Bal.v("fx/shield_style", 2.0)):   # 10-31 TA 审阅 docs/208 H1 / M16（泡泡盖住本体、又是一个圈）改缺省 C 环绕光点（2）；10-28 定的 B 气泡 = 1、A 细光边 = 0
		0:
			_shield_rim(wv, c, r0, n, fresh)
		2:
			_shield_motes(wv, c, r0, n, fresh)
		_:
			_shield_bubble(wv, c, r0, n, fresh)
	# 充能进度不在身上画（10-31 TA 审阅 docs/208 H1：0 层时常驻的空槽环、充能弧都是圈）：左上生命值旁的护盾菱形已经显示层数
	# 碎裂：碎掉的那一环外扩淡出 0.25 秒；之后无敌期间（0.5 秒）环位上两点微光绕行
	if tb < 0.25:
		var e := tb / 0.25
		var rb := r0 + 16.0 * e
		wv.tb_arc(c, rb, 0.0, TAU, 4.0 * (1.0 - e) + 1.0, Color(1.4, 1.3, 1.05, 0.9 * (1.0 - e)), 40)
		if tb < 0.06:
			wv.tb_circle(c, r0, Color(1.35, 1.15, 0.7, 0.16 * (1.0 - tb / 0.06)), 1.0, 24)
	if tb < 0.5 and g.invuln > 0.0:
		var sa := 1.0 - tb / 0.5
		wv.tb_arc(c, r0, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, (0.18 + 0.14 * sin(g.t * 40.0)) * sa), 40)
		for q in 2:
			var a: float = g.t * 9.0 + PI * q
			var p := (c + Vector2.from_angle(a) * r0).snapped(Vector2(2, 2))
			wv.tb_quad(p - Vector2(2, 2), p + Vector2(2, -2), p + Vector2(2, 2), p + Vector2(-2, 2), Color(1.5, 1.4, 1.1, 0.85 * sa))


## 候选 A 细光边：一道连续细边（1 美术像素），层数 = 边的亮度 + 边顶的小菱形个数
static func _shield_rim(wv: W, c: Vector2, r0: float, n: int, fresh: float) -> void:
	if n <= 0:
		return
	var al: float = 0.35 + 0.15 * mini(n, 3) + 0.4 * fresh
	wv.tb_arc(c, r0 + 2.0 * fresh, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, al), 48)
	_shield_pips(wv, c, r0, n)


## 候选 B 柔和气泡：边缘向内渐隐的淡光层 + 连续细边；层数 = 气泡厚度（每层边缘光带加宽一截）+ 小菱形
static func _shield_bubble(wv: W, c: Vector2, r0: float, n: int, fresh: float) -> void:
	if n <= 0:
		return
	var band: float = 6.0 + 4.0 * mini(n, 3)
	var edge := Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.16 + 0.04 * mini(n, 3) + 0.25 * fresh)
	wv.tb_ring2(c, r0 - band, r0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.0), edge, 40)
	wv._shield_edge(c, r0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.45 + 0.4 * fresh))
	# 左上一点高光（气泡感）
	wv.tb_arc(c, r0 - 4.0, -PI * 0.85, -PI * 0.65, 2.0, Color(1.4, 1.35, 1.2, 0.5), 6)
	_shield_pips(wv, c, r0, n)


## 候选 C 环绕光点：极淡连续边 + 每层一颗绕身体转的光点（带两格拖尾），层数 = 光点个数
static func _shield_motes(wv: W, c: Vector2, r0: float, n: int, fresh: float) -> void:
	var g: Game = wv.g
	if n <= 0:
		return
	wv._shield_edge(c, r0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.2 + 0.3 * fresh))
	var k: int = mini(n, 6)
	for i in k:
		var a0: float = g.t * 1.6 + TAU * i / k
		for q in 3:
			var p := (c + Vector2.from_angle(a0 - 0.14 * q) * r0).snapped(Vector2(2, 2))
			var h: float = 3.0 - q
			var al: float = (0.95 - 0.3 * q)
			wv.tb_quad(p - Vector2(h, h), p + Vector2(h, -h), p + Vector2(h, h), p + Vector2(-h, h), Color(SH_COL.r * 1.3, SH_COL.g * 1.25, SH_COL.b * 1.1, al))


## 层数标记：边顶的小菱形（每层一个，最多 8 个）
static func _shield_pips(wv: W, c: Vector2, r0: float, n: int) -> void:
	var k: int = mini(n, 8)
	for i in k:
		var p := (c + Vector2((i - (k - 1) * 0.5) * 8.0, -r0 - 6.0)).snapped(Vector2(2, 2))
		wv.tb_quad(p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0), Color(SH_COL.r * 1.25, SH_COL.g * 1.2, SH_COL.b * 1.1, 0.9))


## 护盾碎片 / 充能颗粒：沿环一圈向外（fx_grains，docs/136；低画质 / 关颗粒时由 push 稀疏或不出）
static func _sh_burst(wv: W, c: Vector2, r: float, tpl: String, k: int) -> void:
	var g: Game = wv.g
	if g.optical == null or g.optical.grains == null or not g.optical.grains.on():
		return
	for i in k:
		var d := Vector2.from_angle(TAU * (i + 0.5 * (i % 2)) / k)
		g.optical.grains.push(tpl, c + d * r, d, SH_COL)
