## 世界层敌人前摇提示绘制（world.draw_enemy_tells 一族：直线 / 圆形提示、冲刺箭头、Boss 状态、倒数环、落柱）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world；成员经 wv.、常量经 W.。预警轮廓 draw_warn_outlines / classify_tells 仍在 world（测试与 boss_attack_draw 直接调）。
extends RefCounted

const Game = preload("res://scripts/game.gd")
const W = preload("res://scripts/render/world.gd")
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")


static func draw_enemy_tells(wv: W) -> void:
	var g: Game = wv.g
	var tvr: Rect2 = wv.view_rect(W.TELL_MARGIN)   # 冲刺线 / 危险圈能伸进屏幕，外扩大一些
	for e in (wv._vis_tell if wv._vis_on else g.enemies):
		if e.dead or (not e.boss and not tvr.has_point(e.pos)):
			continue
		if e.get("blast_w", 0.0) > 0.0:
			var xd: Dictionary = D.ENEMIES.get(e.type, {})
			var xk: float = clampf(1.0 - e.blast_w / float(e.get("blast_w0", xd.get("blast_fuse", 0.55))), 0.0, 1.0)
			_tell_circle(wv, e.pos, float(xd.get("blast_r", 62)), xk, W.ENEMY_TELL)
		if e.get("burst_w", 0.0) > 0.0:
			_tell_circle(wv, e.pos, float(D.ENEMIES.get(e.type, {}).get("burst_r", 80.0)), clampf(1.0 - e.burst_w / float(e.get("burst_dur", 0.4)), 0.0, 1.0), W.TELL_BURST)
		# 冲刺预警线（滑动者 / 撕裂者 / 骑士精英）：长度按实际冲刺距离算（速度 × dash_speed × 0.35 秒），
		# 不再写死 230（docs/48 P1：实际只冲 80–135）；只朝前画
		if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir") and Bal.v("render/dash_tell", 1.0) > 0.0:   # render/dash_tell 0 = 不画（docs/139 §7 量测用）
			var dd: Dictionary = D.ENEMIES.get(e.type, {})
			var wk: float = clampf(1.0 - e.dash_w / float(dd.get("dash_wind", 0.5)), 0.0, 1.0)
			var dts: int = Bal.vi("render/dash_tell_style", 3)
			if dts >= 3:
				dts = 2 if (e.elite or e.boss) else -1   # style 3：精英 / Boss 照旧画 style 2 的短箭，普通小怪不画（只靠身体预警）
			match dts:
				-1:
					pass
				1:
					_dash_chevrons(wv, e, wk, not e.get("tell_dim", false))
				2:
					if not e.get("tell_dim", false):   # 只给会冲到队长的画：冲刺距离前 45% 的短箭 + 箭头
						var sb: Vector2 = e.pos + e.dash_dir * wv._dash_len(e) * Bal.v("render/dash_short", 0.45)
						_tell_line(wv, e.pos, sb, Bal.v("render/dash_tell_half", 6.0), wk, W.ENEMY_TELL, false, true)
						_dash_head(wv, sb, e.dash_dir, wk)
				_:
					_tell_line(wv, e.pos, e.pos + e.dash_dir * wv._dash_len(e), Bal.v("render/dash_tell_half", 6.0), wk, W.ENEMY_TELL, e.get("tell_dim", false), true)   # render/dash_tell_half 半宽
		# 伊祖米克解读阶段的冲击波已改走 boss_ai._warn（1 秒预警、must_dash 标记，Boss与怪物 docs/48 P0-5），这里不再按 bt 预告
		if e.get("count_max", 0.0) > 0.0 and float(e.get("count_end", 0.0)) > g.t:
			_count_ring(wv, e)
		var stk = e.get("stakes")   # 不给每只敌人新建默认空数组（docs/50 §14）
		if stk is Array and not stk.is_empty():
			_draw_stakes(wv, e)
		var armor_def: Dictionary = D.ENEMIES.get(e.type, W._NO_DEF)
		if (float(e.get("set_t", 0.0)) > 0.0 and armor_def.has("entrench_phys_taken")) or (e.enraged and armor_def.has("enrage_phys_taken")):
			# 常亮像素盾标，直接读取真实硬化状态，结束时自然消失。
			var ap: Vector2 = (wv._enemy_top(e) + Vector2(0, -28)).round()
			g.wcv.draw_rect(Rect2(ap + Vector2(-5, -4), Vector2(10, 6)), Color(0.65, 0.8, 1.0))
			g.wcv.draw_rect(Rect2(ap + Vector2(-3, 2), Vector2(6, 2)), Color(0.65, 0.8, 1.0))
			g.wcv.draw_rect(Rect2(ap + Vector2(-1, 4), Vector2(2, 2)), Color(0.65, 0.8, 1.0))
		if e.type == "tear":
			_tear_zone(wv, e)
		elif e.boss:
			_boss_state(wv, e)


## 通用倒计时环（Boss与怪物约定：凡是 e.count_end / e.count_max 的单位——部件、假死、读条——都画这一种）：
## 脚下椭圆环按剩余时间收缩，最后 3 秒变红并加快脉动，环旁一个秒数小牌；部件金色、假死青色、其余洋红
static func _count_ring(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	var left: float = maxf(0.0, float(e.count_end) - g.t)
	var k: float = clampf(left / float(e.count_max), 0.0, 1.0)
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8) if g.foot_anchor.has(e.tex) else e.pos + Vector2(0, e.r * 0.5)
	var c: Color = W.PART_COL if e.get("part", false) else (Color(0.5, 1.5, 1.4) if e.get("coma", false) else (Color(1.6, 1.2, 0.5) if e.get("channel", 0.0) > 0.0 else W.ENEMY_TELL))   # 读条（圣徒装填）金色
	if left < 3.0:
		c = c.lerp(Color(1.8, 0.4, 0.35), 0.5 + 0.5 * sin(g.t * 16.0))
	var rr: float = maxf(e.r + 14.0, 26.0)
	wv._ground_ring(foot, rr, k, c)
	var tag := "%d" % ceili(left)
	var tp: Vector2 = foot + Vector2(rr + 6.0, -4.0)
	g.wcv.draw_rect(Rect2(tp + Vector2(-2, -12), Vector2(UI.cond(g.font).get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8.0, 17)), Color(0.02, 0.03, 0.05, 0.8))
	UI.ctext(g.wcv, g.font, tp + Vector2(2, 1), tag, 13, c)


static func _tear_zone(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	var info := wv.tear_zone_info(e)
	var r: float = info.r
	var c: Color = info.col
	var pulse: float = 0.5 + 0.5 * sin(g.t * 4.0 + e.id)
	g.wcv.draw_set_transform(e.pos, 0.0, Vector2(1.0, info.ground_scale))
	g.wcv.draw_circle(Vector2.ZERO, r, Color(c, 0.12 + 0.06 * pulse))
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 4.0)
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(c, 0.6 + 0.3 * pulse), 2.0)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if info.label != "":
		UI.text(g.wcv, g.font, e.pos + Vector2(-70, -e.r - 20), info.label, 11, c, HORIZONTAL_ALIGNMENT_CENTER, 140, 2)
	var owner: Dictionary = info.owner
	if not owner.is_empty() and not info.blocked:
		var d: Vector2 = owner.pos - e.pos
		for q in 5:
			var u: float = fmod(g.t * 0.6 + q / 5.0 + e.id * 0.13, 1.0)
			g.wcv.draw_circle(e.pos + d * u, 2.5, Color(0.6, 1.6, 1.4, 0.7 * sin(u * PI)))


## Boss 身上的状态（docs/48 P1）：
## 接潮组假死 → 身边一圈倒计时环（假死期间每秒回 10% 血，回满苏醒：环 = 血量），连一条虚线到另一体，提示「同时击倒」；
## 圣徒装填 → 金色装填环 + 三颗弹药格依次点亮，「装填中 · 攻击打断」；装填被打断 / 其他晕眩 → 头顶三颗转圈的星 + 剩余秒数
static func _boss_state(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	var top: Vector2 = wv._enemy_top(e) + Vector2(0, -18.0)
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8) if g.foot_anchor.has(e.tex) else e.pos
	if e.get("cocoon_t", 0.0) > 0.0:
		_cocoon_fx(wv, e, top, foot)
		return
	if e.get("coma", false):
		var k: float = clampf(e.hp / e.maxhp, 0.0, 1.0)
		var rr: float = e.r + 12.0
		var tc := Color(0.5, 1.5, 1.4)
		var left: float = (e.maxhp - e.hp) / maxf(e.maxhp * 0.1, 0.001)
		if e.get("count_max", 0.0) > 0.0:
			left = maxf(0.0, float(e.count_end) - g.t)   # 假死赛跑（combat：count_end / count_max），环由 _count_ring 画
		else:
			wv._ground_ring(foot, rr, k, tc)
		UI.text(g.wcv, g.font, top + Vector2(-120, -4), "假死 %d 秒 · 同时击倒另一体" % ceili(left), 13, tc, HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		var p = e.get("partner")
		if p != null and not p.dead:
			var d: Vector2 = p.pos - e.pos
			var L: float = d.length()
			var dn: Vector2 = d / maxf(L, 1.0)
			var s: float = fmod(g.t * 40.0, 16.0)
			while s < L:
				g.wcv.draw_line(e.pos + dn * s, e.pos + dn * minf(s + 8.0, L), Color(tc.r, tc.g, tc.b, 0.45), 2.0)
				s += 16.0
		return
	if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
		var gc := Color(1.6, 1.2, 0.5)
		var k: float = clampf(1.0 - e.channel / 2.0, 0.0, 1.0)
		if e.get("count_max", 0.0) > 0.0:
			k = clampf(1.0 - (float(e.count_end) - g.t) / float(e.count_max), 0.0, 1.0)   # 通用倒计时环已画在脚下
		else:
			wv._ground_ring(foot, e.r + 10.0, k, gc)
		# 读条光圈：「快打它」——身周金色光圈呼吸 + 向内收的细环
		var cc: Vector2 = (top + Vector2(0, 18) + foot) / 2.0
		var hh: float = maxf(e.r, (foot.y - top.y - 18.0) / 2.0) * 1.15
		var br: float = 0.5 + 0.5 * sin(g.t * 9.0)
		g.wcv.draw_circle(cc, hh, Color(1.6, 1.2, 0.4, 0.07 + 0.06 * br))
		g.wcv.draw_arc(cc, hh, 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.55 + 0.35 * br), 2.5)
		var u: float = fmod(g.t * 1.6, 1.0)
		g.wcv.draw_arc(cc, hh * (1.6 - 0.6 * u), 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.5 * u), 1.5)
		for q in 3:
			var on: bool = k >= (q + 1) / 3.0
			var pp: Vector2 = top + Vector2(-14 + q * 14, 10)
			g.wcv.draw_rect(Rect2(pp - Vector2(3, 5), Vector2(6, 10)), gc if on else Color(0.2, 0.15, 0.1, 0.8))
			g.wcv.draw_rect(Rect2(pp - Vector2(3, 5), Vector2(6, 10)), Color(0, 0, 0, 0.7), false, 1.0)
		UI.text(g.wcv, g.font, top + Vector2(-120, -6), "装填中 · 攻击打断", 13, gc, HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		return
	var brk: float = e.get("break_t", 0.0)
	if e.stun > 0.05 or brk > 0.0:
		var recovering: bool = e.type=="knight_boss" and e.stun<=0.05 and str(e.get("brk_label",""))=="破绽"
		var quiet: bool = brk > 0.0 and g.combat.final_break_quiet(e)   # 最终 Boss 破绽不写字（用户 10-28，render/break_ring 画金环）
		if recovering and quiet:
			pass
		elif recovering:
			UI.text(g.wcv, g.font, top + Vector2(-120,-12), "收招 · 破绽 %.1f" % brk, 13, Color(.65,.85,.95), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		else:
			for q in 3:
				var a: float = g.t * 5.0 + q * TAU / 3.0
				var sp: Vector2 = top + Vector2(cos(a) * 18.0, sin(a) * 5.0)
				UI.diamond(g.wcv, sp, 4.0, Color(1.8, 1.6, 0.6), Color(0, 0, 0, 0.6))
		if e.has("ammo") and brk > 0.0:
			UI.text(g.wcv, g.font, top + Vector2(-120, -12), "装填被打断 · 破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif brk > 0.0 and e.type == "knight_boss":
			# 骑士（用户 10-25）：只在撞冰柱眩晕时写「眩晕」读秒，别的破绽不写字
			if str(e.get("brk_label", "")) == "眩晕":
				UI.text(g.wcv, g.font, top + Vector2(-120, -12), "眩晕 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif quiet:
			pass
		elif brk > 0.0:
			# 其他 Boss 的破绽（伊莎玛拉潮涌迫近落地、塑路者核心碎裂等）：同一套星 + 剩余秒数
			UI.text(g.wcv, g.font, top + Vector2(-120, -12), "破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif e.type in ["iberia", "carmen"] and e.get("ammo", 1) == 0:
			UI.text(g.wcv, g.font, top + Vector2(-120, -12), "装填被打断 · 眩晕 %.1f" % e.stun, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)


## 泡影茧（e.cocoon_t > 0；外壳 e.shell_hp / e.shell_max）：半透明紫色泡壳包住本体，按外壳损失比例出现裂纹，壳下方一条壳量条
static func _cocoon_fx(wv: W, e: Dictionary, top: Vector2, foot: Vector2) -> void:
	var g: Game = wv.g
	var c: Vector2 = (top + Vector2(0, 18) + foot) / 2.0
	var rr: float = maxf(e.r * 1.2, (foot.y - top.y) * 0.6)
	var dmg: float = 1.0 - clampf(float(e.get("shell_hp", 0.0)) / maxf(1.0, float(e.get("shell_max", 1.0))), 0.0, 1.0)
	var wob: float = 1.0 + 0.03 * sin(g.t * 3.0)
	g.wcv.draw_circle(c, rr * wob, Color(0.75, 0.4, 1.2, 0.22))
	g.wcv.draw_arc(c, rr * wob, 0.0, TAU, 48, Color(1.2, 0.7, 1.7, 0.85), 2.5)
	g.wcv.draw_arc(c, rr * 0.82, -2.5, -1.6, 10, Color(1.8, 1.5, 2.0, 0.8), 2.5)
	if e.flash > 0.0:
		# 外壳受伤速度有上限（每秒最多 1/4）：挨打时壳面白闪 +「抵抗」，提示打得再快也要等
		g.wcv.draw_arc(c, rr * wob, 0.0, TAU, 48, Color(2.0, 2.0, 2.0, g.vfx.boss_flash_alpha(e, 0.8)), 4.0)
		UI.text(g.wcv, g.font, c + Vector2(-40, -rr - 8.0), "抵抗", 13, Color(1.0, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	# 裂纹：最多 6 道，从壳面往里，按外壳损失依次出现
	var n: int = int(ceil(dmg * 6.0))
	for q in n:
		var ang: float = q * 2.39 + e.id * 0.7
		var p0: Vector2 = c + Vector2.from_angle(ang) * rr
		var p1: Vector2 = c + Vector2.from_angle(ang + 0.25) * rr * 0.72
		var p2: Vector2 = c + Vector2.from_angle(ang - 0.1) * rr * 0.5
		g.wcv.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(0.05, 0.0, 0.1, 0.9), 3.0)
		g.wcv.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(1.8, 1.4, 2.0, 0.9), 1.2)
	var bw: float = rr * 1.4
	var by: Vector2 = c + Vector2(-bw / 2.0, rr + 10.0)
	g.wcv.draw_rect(Rect2(by, Vector2(bw, 5)), Color(0, 0, 0, 0.7))
	g.wcv.draw_rect(Rect2(by, Vector2(bw * (1.0 - dmg), 5)), Color(1.2, 0.7, 1.7))
	UI.text(g.wcv, g.font, by + Vector2(0, -4), "打破外壳", 12, Color(0.95, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, bw, 3)


## dash = 杂兵冲刺预警（docs/139 §7，用户 10-24「后期冲刺的那些太着眼」）：render/dash_tell_alpha 整体透明度倍率、
## render/dash_tell_flow 0 = 不铺流动水纹 / 终点漩涡（只留填充 + 边框），render/dash_tell_white 0 = 不画中线白芯，render/dash_tell_half 半宽（缺省 10）
static func _tell_line(wv: W, a: Vector2, b: Vector2, half: float, k: float, c: Color, dim := false, dash := false) -> void:
	var g: Game = wv.g
	var d: Vector2 = b - a
	var n: Vector2 = d.normalized().orthogonal() * half
	var ta: float = Bal.v("render/dash_tell_alpha", 0.55) if dash else 1.0
	if dim:
		# 打不到主控的冲刺线：只画淡边框（预警不藏，但不再整片盖住主控）
		g.wcv.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, Bal.v("fx/tell_dim_alpha", 0.2) * ta), 1.5)
		return
	g.wcv.draw_colored_polygon(PackedVector2Array([a + n, a + d * k + n, a + d * k - n, a - n]), Color(c.r, c.g, c.b, (0.22 + 0.12 * k) * wv.tell_fill * ta))
	var lt: Texture2D = _wtex(wv, "fx_warn_line") if not dash or Bal.v("render/dash_tell_flow", 0.0) > 0.0 else null
	if lt != null:
		# 沿线平铺流动水纹（16px 一段，按线宽缩放），终点放漩涡
		var fr: int = int(g.t * 12.0) % 4
		var seg: float = 16.0 * (half * 2.0 / 16.0)
		var L: float = d.length()
		var ang: float = d.angle()
		var x := 0.0
		while x < L - 1.0:
			var w: float = minf(seg, L - x)
			g.wcv.draw_set_transform(a + d.normalized() * x, ang, Vector2(half * 2.0 / 16.0, half * 2.0 / 16.0))
			g.wcv.draw_texture_rect_region(lt, Rect2(0, -8, w / (half * 2.0 / 16.0), 16), Rect2(16 * fr, 0, w / (half * 2.0 / 16.0), 16), Color(c.r, c.g, c.b, 0.55 * wv.tell_fill * ta))
			x += seg
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var et: Texture2D = _wtex(wv, "fx_warn_end")
		if et != null:
			var es: float = half * 2.4 / 32.0 * 2.0
			g.wcv.draw_set_transform(b, 0.0, Vector2(es, es * wv.ground_y()))
			g.wcv.draw_texture_rect_region(et, Rect2(-16, -16, 32, 32), Rect2(32 * fr, 0, 32, 32), Color(c.r, c.g, c.b, 0.8 * ta))
			g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	g.wcv.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(0, 0, 0, 0.55 * ta), 4.0 * wv.tell_edge)
	g.wcv.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, 0.85 * ta), 2.0 * wv.tell_edge)
	if not dash or Bal.v("render/dash_tell_white", 0.0) > 0.0:
		g.wcv.draw_line(a, b, Color(1, 1, 1, (0.5 + 0.4 * k) * ta), 1.0)


## render/tell_circle_calm 1（docs/139 §8）：不铺流动涟漪贴图、描边不脉动（填充随倒计时长满照旧）
static func _tell_circle(wv: W, p: Vector2, r: float, k: float, c: Color) -> void:
	var g: Game = wv.g
	var calm: bool = Bal.v("render/tell_circle_calm", 0.0) > 0.0
	var pulse: float = 0.0 if calm else 0.5 + 0.5 * sin(g.t * 18.0)
	g.wcv.draw_set_transform(p, 0.0, Vector2(1.0, wv.ground_y()))   # 地面椭圆，和判定一致
	g.wcv.draw_circle(Vector2.ZERO, r * k, Color(c.r, c.g, c.b, (0.18 + 0.1 * k) * wv.tell_fill))
	var rt: Texture2D = _wtex(wv, "fx_warn_ring") if not calm else null
	if rt != null:
		# V7 涟漪：从外向内收缩的水纹，按半径缩放（radius_px 30）
		var rs: float = r / 30.0
		g.wcv.draw_set_transform(p, 0.0, Vector2(rs, rs * wv.ground_y()))
		g.wcv.draw_texture_rect_region(rt, Rect2(-32, -32, 64, 64), Rect2(64 * (int(g.t * 12.0) % 4), 0, 64, 64), Color(c.r, c.g, c.b, 0.5 * wv.tell_fill))
		g.wcv.draw_set_transform(p, 0.0, Vector2(1.0, wv.ground_y()))
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 5.0 * wv.tell_edge)
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.75 + 0.25 * pulse * k), 3.0 * wv.tell_edge)
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55 + 0.4 * k), 1.0 * wv.tell_edge)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 冲刺预警线长度：按实际冲刺距离（速度 × dash_speed × 0.35 秒）；Boss与怪物 给了 dash_len 就用它
## 冲刺预警风格 1（docs/139 §7.4）：怪物脚前 3 个「›」箭头沿冲刺方向依次点亮（蓄力 0–⅓–⅔–1），深色底 + 危险色线；
## 打不到队长的只亮最近一个、半透明。不画整条线
static func _dash_chevrons(wv: W, e: Dictionary, wk: float, threat: bool) -> void:
	var g: Game = wv.g
	var dv: Vector2 = e.dash_dir
	var nv: Vector2 = dv.orthogonal()
	var c: Color = W.ENEMY_TELL
	var n: int = 3 if threat else 1
	for i in n:
		var lit: float = clampf(wk * 3.0 - float(i), 0.0, 1.0)
		if lit <= 0.0 and i > 0:
			continue
		var a: float = (0.35 + 0.6 * lit) * (1.0 if threat else 0.4)
		var tip: Vector2 = e.pos + dv * (float(e.get("r", 10.0)) + 10.0 + 11.0 * i)
		var pts := PackedVector2Array([tip - dv * 6.0 + nv * 6.0, tip, tip - dv * 6.0 - nv * 6.0])
		g.wcv.draw_polyline(pts, Color(0, 0, 0, 0.6 * a), 5.0)
		g.wcv.draw_polyline(pts, Color(c.r, c.g, c.b, a), 2.5)


## 风格 2 的箭头
static func _dash_head(wv: W, p: Vector2, dv: Vector2, wk: float) -> void:
	var g: Game = wv.g
	var nv: Vector2 = dv.orthogonal()
	var c: Color = W.ENEMY_TELL
	var pts := PackedVector2Array([p - dv * 9.0 + nv * 8.0, p + dv * 3.0, p - dv * 9.0 - nv * 8.0])
	g.wcv.draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0)
	g.wcv.draw_polyline(pts, Color(c.r, c.g, c.b, 0.55 + 0.4 * wk), 2.5)


static func _wtex(wv: W, n: String) -> Texture2D:
	if not wv._warn_tex.has(n):
		wv._warn_tex[n] = A.tex(n)
	return wv._warn_tex[n]


## 最后的骑士冰柱（e.stakes = [{pos, until, born}]，判定 r 22）：冰柱帧条（没有就退回冰枪桩 / 程序长枪）+ 脚下冰霜圈；快到期（< 2 秒）时闪烁
static func _draw_stakes(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	for st in e.stakes:
		if g.t < float(st.get("born", -99.0)):
			continue   # Placement preview remains visible; pillar rises only at its announced time.
		var left: float = float(st.until) - g.t
		if left <= 0.0:
			continue
		var a: float = 1.0 if left > 2.0 else 0.35 + 0.65 * absf(sin(g.t * 12.0))
		var p: Vector2 = st.pos
		g.wcv.draw_set_transform(p, 0.0, Vector2(1.0, wv.ground_y()))
		g.wcv.draw_circle(Vector2.ZERO, 22.0, Color(0.36, 0.52, 0.60, 0.10 * a))
		g.wcv.draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.60, 0.74, 0.78, 0.45 * a), 1.5)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if g.tex.get("prop_knight_frost_stake") != null:
			# 冰柱（10-25 用户「骑士的桩设置成冰柱」，tools/gen_ice_pillar.py：ansimuz Ice_b，64 × 96、脚底第 94 行）：统一冷灰蓝衍生帧条，整数像素；新立的先播破土 0.25 秒
			var age: float = g.t - float(st.get("born", -99.0))
			var pc := Color(1.0, 1.0, 1.0, a)
			if age < 0.25 and g.tex.get("prop_knight_frost_stake_rise") != null:
				g.vfx.spr("prop_knight_frost_stake_rise", 3, clampi(int(age / 0.25 * 3.0), 0, 2), p, 1.0, false, pc, Vector2(0.5, 94.0 / 96.0))
			else:
				g.vfx.spr("prop_knight_frost_stake", 4, int(g.t * 4.0) % 4, p, 1.0, false, pc, Vector2(0.5, 94.0 / 96.0))
			continue
		if g.tex.get("prop_ice_stake") != null:
			# Codex v14 prop_ice_stake（24×56 × 2 帧，脚底第 53 行）；冰蓝过曝调色同骑士长矛（暗环境光下原色太暗）；到期前闪烁仍是程序改透明度，判定圈程序画
			g.vfx.spr("prop_ice_stake", 2, int(g.t * 4.0) % 2, p, wv._hpx("prop_ice_stake"), false, Color(1.6, 1.8, 2.1, a), Vector2(0.5, 54.0 / 56.0))
			continue
		var top: Vector2 = p + Vector2(2, -70)
		g.wcv.draw_line(p + Vector2(0, 2), top, Color(0.1, 0.15, 0.25, 0.9 * a), 7.0)
		g.wcv.draw_line(p + Vector2(0, 2), top, Color(0.7, 0.95, 1.4, a), 4.0)
		g.wcv.draw_line(p + Vector2(-1, 0), top + Vector2(-1, 6), Color(1.6, 1.9, 2.2, 0.8 * a), 1.2)
		var tip := PackedVector2Array([top + Vector2(0, -18), top + Vector2(6, 0), top + Vector2(0, 6), top + Vector2(-6, 0)])
		g.wcv.draw_colored_polygon(tip, Color(0.85, 1.2, 1.7, a))
		tip.append(tip[0])
		g.wcv.draw_polyline(tip, Color(0.1, 0.15, 0.25, a), 1.5)
		for q in 3:
			var cp: Vector2 = p + Vector2(-10 + q * 10, -2 - (q % 2) * 5)
			UI.diamond(g.wcv, cp, 3.0, Color(0.8, 1.1, 1.6, 0.8 * a), Color(0.1, 0.15, 0.25, 0.8 * a))
