extends RefCounted
## 界面 · HUD 右下编队栏与手动技能（2026-10-10 从 hud.gd 拆出，docs/55 §6）：干员部署卡 + 技能格（静态层缓存 + 每帧层）、
## 源石锭框、手动技能首次就绪提示、手动技能瞄准指示（方向 / 落点）。触屏分支原样保留。
const A = preload("res://scripts/art.gd")
const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const Tris = preload("res://scripts/screens/hud_tris.gd")
var g: Game
var h   # screens/hud.gd：合批段（batch_begin / _hb）、共用助手（edge_glow / corrode_seg / draw_tooltip）与兄弟模块都从这里取


func _init(hud) -> void:
	h = hud
	g = hud.g


## 右下编队栏（2026-09-26 方案 A）：明日方舟部署卡——每名干员一张立绘卡（左上职业、右上精英阶段、底部名字），
## 卡上方三枚方形技能格（底部充能条 / 生效时白框 + 倒计时；未解锁灰显；永久型小菱形；海嗣化紫点；手动技能标 Q）。
## 队长卡顶上紫色「队长」标签（紫 = 当前）；技能生效中的干员卡加青色外晕。卡组上方右侧是源石锭费用框 + 编队人数。
## 干员没有等级，卡上不画经验类进度（等级是整局共享的，画在左上角）。开局干员在最左，第 4 位在最右。
const SQ_COL_W := 94.0
const SQ_CARD := Vector2(84, 96)
const SQ_SK := 24.0


## 右下：编队栏（静态层签名变了才重画 + 每帧层）；原 _draw_body「右下」段
func draw(vs: Vector2) -> void:
	# 右下：技能与援护干员
	# 编队栏：静态部分（底、立绘、名字、职业 / 精英标签、技能格底与图标、源石锭框）只在内容变了才重画；
	# 充能遮罩、进度条、边框、倒计时、悬停提示等每帧画（在父画布上，压在静态层之上）
	var sbr := Vector2(vs.x - 16, vs.y - 16)
	h._layer("squad", _squad_sig(sbr), func(): draw_squad_hud(sbr, 1))
	draw_squad_hud(sbr, 2)


## 编队区最上沿（源石锭框顶）的 y：触屏冲刺键 / 技能键摆在它上方，不压住「编队 n / m」和源石锭
func squad_top(vs: Vector2) -> float:
	return vs.y - 16.0 - SQ_CARD.y - SQ_SK - 14.0 - 46.0


## 编队栏静态层的签名：这些变了才重画静态层
func _squad_sig(br: Vector2) -> Array:
	var sig: Array = [br, g.squad.size(), g.squad.cap(), g.ingots]
	for o in g.squad.ops:
		var pt: Dictionary = o.portrait()
		sig.append([o.id, o.elite, o.display_name(), o.cls, pt.tex, pt.frames])
		var items: Array = o.skill_hud()
		for k in 3:
			var it: Array = items[k]
			sig.append([it[9] if it.size() > 9 else "", it[2]])
	return sig


func draw_squad_hud(br: Vector2, part := 0) -> void:
	var S: bool = part != 2   # 画静态部分
	var Dn: bool = part != 1  # 画每帧部分
	var n: int = g.squad.size()
	var x_left: float = br.x - n * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
	if g.knight.alive and Dn:
		g.knight.draw_hud(g.hud, Vector2(x_left - 130, br.y - 30))
	# 分四层画（性能，协调人 9/30：原来每张卡 + 三枚技能格约 15 次绘制调用，字 / 色块 / 贴图交替打断合批）：
	# bg 底色批 → 贴图（立绘 / 技能图标 / 源石锭）→ fg 遮罩边框批 → 文字与悬停提示。同层内顺序不变
	var bg := Tris.new()
	var fg := Tris.new()
	var texq: Array[Callable] = []
	var txt: Array[Callable] = []
	var card_y: float = br.y - SQ_CARD.y
	var sk_y: float = card_y - SQ_SK - 14.0
	# 源石锭费用框（明日方舟部署费用的位置与样子）+ 编队人数
	var dp := Rect2(Vector2(br.x - 116, sk_y - 46), Vector2(116, 34))   # 顶 = squad_top()
	if S:
		bg.rect(dp, Color(0.03, 0.035, 0.045, 0.82))
		bg.rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
		texq.append(func(): g.hud.draw_texture_rect(g.tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false))
	var cnt := "编队 %d / %d" % [n, g.squad.cap()]
	if S:
		txt.append(func():
			UI.ctext(g.hud, g.font, dp.position + Vector2(38, 27), str(g.ingots), 26, UI.TEXT)
			UI.text(g.hud, g.font, dp.position + Vector2(76, 22), "源石锭", 10, UI.SUB)
			UI.text(g.hud, g.font, Vector2(dp.position.x - 160, dp.position.y + 22), cnt, 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 150))
	var mp := g.hud.get_local_mouse_position()
	for i in n:
		var o = g.squad.ops[i]
		var x: float = br.x - (n - i) * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
		var cr := Rect2(Vector2(x, card_y), SQ_CARD)
		var ocol: Color = o.col()
		var act: bool = o.skill_active()
		# ---- 立绘卡：上亮下暗的底 + 待机帧上半身（48 帧放大 2 倍、96 高清帧原样，都画成 96 像素）
		var ctop := Color(0.17, 0.2, 0.23, 0.95)
		var cbot := Color(0.07, 0.08, 0.1, 0.95)
		if S:
			bg.grad(cr, ctop, cbot)
		var pt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(pt.tex)
		if at != null and S:
			var fw := float(at.get_width()) / int(pt.frames)
			var fh := float(at.get_height())
			var ks: float = 2.0 / A.hires_of(at)
			var dst_h := minf(fh * ks - 8.0, cr.size.y - 8.0)
			var src := Rect2(maxf(0.0, (fw * ks - cr.size.x) / 2.0) / ks, 8.0 / ks, minf(cr.size.x / ks, fw), dst_h / ks)
			var dst := Rect2(cr.position, Vector2(minf(cr.size.x, fw * ks), dst_h))
			texq.append(func(): g.hud.draw_texture_rect_region(at, dst, src))
		var clear := Color(0, 0, 0, 0)
		var shade := Color(0, 0, 0, 0.88)
		var nm: String = o.display_name().substr(0, 5)
		var cls: String = String(o.cls).substr(0, 1)
		var el: String = ["精零", "精一", "精二"][o.elite]
		var ew := g.font.get_string_size(el, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
		if S:
			fg.grad(Rect2(Vector2(cr.position.x, cr.end.y - 28), Vector2(cr.size.x, 28)), clear, shade)
			txt.append(func(): UI.text(g.hud, g.font, Vector2(cr.position.x, cr.end.y - 8), nm, 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 2))
			if cls != "":
				fg.rect(Rect2(cr.position, Vector2(18, 18)), Color(0, 0, 0, 0.72))
				txt.append(func(): UI.text(g.hud, g.font, cr.position + Vector2(0, 14), cls, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 18))
			fg.rect(Rect2(Vector2(cr.end.x - ew, cr.position.y), Vector2(ew, 16)), Color(0, 0, 0, 0.66))
			txt.append(func(): UI.text(g.hud, g.font, Vector2(cr.end.x - ew + 4, cr.position.y + 12), el, 10, ocol.lerp(UI.TEXT, 0.4)))
		if not Dn:
			pass
		elif act:
			for k in 3:
				fg.frame(cr.grow(2.0 + k * 2.5), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.16 - k * 0.045), 2.0)
			fg.frame(cr, UI.CYAN, 1.0)
		else:
			fg.frame(cr, Color(1, 1, 1, 0.16), 1.0)
		if Dn:
			fg.rect(Rect2(cr.position + Vector2(0, cr.size.y - 2), Vector2(cr.size.x, 2)), Color(ocol.r, ocol.g, ocol.b, 0.9))
		if o == g.ch and Dn:
			var lt := Rect2(Vector2(cr.position.x + 18, card_y - 11), Vector2(cr.size.x - 36, 14))
			fg.rect(lt, UI.VIOLET)
			txt.append(func(): UI.text(g.hud, g.font, lt.position + Vector2(0, 11), "队长", 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lt.size.x))
		# ---- 三枚技能格
		var items: Array = o.skill_hud()
		for k in 3:
			var it: Array = items[k]
			var sr := Rect2(Vector2(x + k * (SQ_SK + 6.0), sk_y), Vector2(SQ_SK, SQ_SK))
			var col: Color = it[6]
			var unlocked: bool = it[2]
			var active: float = it[3]
			var frac: float = clamp(it[5], 0.0, 1.0)
			if active > 0.0:
				frac = active / it[4]
			if S:
				bg.rect(sr, Color(0.04, 0.047, 0.059, 0.9))
			var icon: Texture2D = g.tex.get(it[9]) if it.size() > 9 and it[9] != "" else null
			var c := sr.get_center()
			if icon != null:
				# 方形技能图标（仿原作）铺满格子；充能中没充满的上半截压暗，充满后整块亮起
				var tint: Color = Color.WHITE if unlocked else Color(0.3, 0.3, 0.35)
				if S:
					texq.append(func(): g.hud.draw_texture_rect(icon, sr, false, tint))
				if unlocked and active <= 0.0 and frac < 1.0 and Dn:
					fg.rect(Rect2(sr.position, Vector2(sr.size.x, sr.size.y * (1.0 - frac))), Color(0.02, 0.025, 0.035, 0.62))
			elif Dn:
				if unlocked and frac > 0.0:
					bg.rect(Rect2(Vector2(sr.position.x, sr.end.y - sr.size.y * frac), Vector2(sr.size.x, sr.size.y * frac)), Color(col.r, col.g, col.b, 0.22 if active <= 0.0 else 0.35))
				var gcol: Color = (Color(1, 1, 1) if active > 0.0 else col) if unlocked else Color(0.3, 0.35, 0.4)
				var glyph: String = it[0]
				txt.append(func(): UI.text(g.hud, g.font, Vector2(sr.position.x, c.y + 5), glyph, 12, gcol, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 2))
			if not Dn:
				continue
			if unlocked:
				fg.rect(Rect2(Vector2(sr.position.x, sr.end.y - 2), Vector2(sr.size.x * frac, 2)), col if active <= 0.0 else Color.WHITE)
			# 边框：生效中白；充满待放用干员色（有图标时格子本身亮起，边框再提示一下）；其余淡白
			var ready: bool = icon != null and unlocked and active <= 0.0 and frac >= 1.0 and not o.perm[k]
			fg.frame(sr, Color.WHITE if active > 0.0 else (Color(col.r, col.g, col.b, 0.95) if ready else Color(1, 1, 1, 0.14 if unlocked else 0.06)), 1.0)
			if active > 0.0:
				var left := "%d" % int(ceil(active))
				txt.append(func(): UI.ctext(g.hud, g.font, Vector2(sr.end.x - 12, sr.position.y + 10), left, 10, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 12))
			if unlocked and g.get("apop_t") != null and float(g.apop_t) > 0.0:
				# 凋亡损伤满条：技能充能暂停——灰绿遮罩 + 暂停符号
				fg.rect(sr, Color(0.1, 0.14, 0.1, 0.62))
				fg.rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), Color(0.8, 0.92, 0.75))
				fg.rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), Color(0.8, 0.92, 0.75))
			if o.perm[k]:
				fg.diamond(sr.end - Vector2(3, 3), 3.0, col, Color(1, 1, 1, 0.6))
			if o.rej.has(k):
				fg.diamond(Vector2(c.x, sr.position.y - 2), 3.0, Color(0.85, 0.55, 1.0))
			# 手动技能（契约 v2.2）：格子上方标按键；充满可放时青色呼吸框
			if o.is_manual(k) and unlocked:
				var rdy: bool = manual_castable(o, k)
				if rdy:
					var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0)
					fg.frame(sr.grow(2.0 + 1.5 * pulse), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.45 + 0.4 * pulse), 2.0)
				if not g.touch.active:
					txt.append(func(): UI.ctext(g.hud, g.font, Vector2(sr.position.x - 12, sr.position.y - 4), Pad.hint("Q/E", "Ⓐ/Ⓨ"), 10, UI.TEXT if rdy else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x + 24))
			# 悬停：技能名 + 解锁阶段
			if sr.has_point(mp):
				var sd: Dictionary = o.skill_def(k)
				var tip := "%s  ·  %s" % [sd.get("name", ""), ["招募", "精英一", "精英二"][k] + ("" if o.skill_unlocked(k) else "解锁")]
				var tw: float = g.font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
				var tipr := Rect2(Vector2(minf(c.x - tw / 2.0, g.hud.size.x - tw - 8.0), sk_y - 70), Vector2(tw, 28))
				txt.append(func():
					UI.panel(g.hud, tipr, UI.BG2, ocol, 6.0)
					UI.text(g.hud, g.font, tipr.position + Vector2(12, 19), tip, 12, UI.TEXT))
	bg.flush(g.hud)
	for f in texq:
		f.call()
	fg.flush(g.hud)
	for f in txt:
		f.call()


## 手动技能首次就绪提示：每局主控的手动技能第一次充满时，在主控头顶显示 3.5 秒「按 Q 释放「技能名」」
## （手柄写 Ⓐ，触屏写「点技能键释放」），之后只留技能格的呼吸框。位置在冲刺提示上方，两者不重叠
var manual_hinted := false
var manual_hint_t := 0.0
var manual_hint_text := ""


func draw_manual_hint() -> void:
	if g.state != Game.S.PLAY or g.demo_op != "":
		return
	if not manual_hinted:
		var ld = g.squad.leader()
		var i: int = ld.manual_index() if ld != null else -1
		if i >= 0 and manual_castable(ld, i):
			manual_hinted = true
			manual_hint_t = 3.5
			var nm: String = ld.skill_def(i).get("name", "技能")
			manual_hint_text = ("点技能键释放「%s」" % nm) if g.touch.active else ("按 %s 释放「%s」" % [Pad.hint("Q / E", "Ⓐ / Ⓨ"), nm])
	if manual_hint_t <= 0.0:
		return
	manual_hint_t -= g.get_process_delta_time()
	var a: float = clampf(manual_hint_t / 0.5, 0.0, 1.0) * (0.65 + 0.35 * sin(g.t * 5.0))
	var sp: Vector2 = g.hud_ct() * (g.ppos + Vector2(0, -118))
	UI.text(g.hud, g.font, sp - Vector2(140, 0), manual_hint_text, 15, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), HORIZONTAL_ALIGNMENT_CENTER, 280, 4)


## 手动技能此刻「能放」（技能格呼吸框、触屏技能键、首次提示共用）：带方向的技能（JSON "aim": true）只要朝某个方向能放就算，
## 这样附近没敌人时乌尔比安 S3 也亮——给方向就能掷向空地当位移；键鼠站着不动按 Q 仍是自动瞄准，没目标时角色自己飘字说原因
func manual_castable(o, k: int) -> bool:
	return o.manual_ready(k, Vector2.RIGHT if o.manual_aims(k) else Vector2.ZERO)


## 手动技能瞄准指示（契约 v2.4）：主控带方向的手动技能能放时，在预计落点画圈（半径 = 技能作用半径），从主控拉一条引导线。
## 触屏：按住技能键拖动时画拖出的方向（拖回中心 = 自动瞄准，圈落在自动目标上）；没按住不画。
## 键鼠 / 手柄：跟 g.doctor.manual_input_dir()（移动方向 / 右摇杆），站着不动时画自动目标，淡一些。
## 瞄准圈是按技能半径精确画的几何指示，不是特效，所以不走素材库（docs/37 §7）
const AIM_COL := Color(0.45, 0.95, 1.0)

func draw_manual_aim() -> void:
	if g.state != Game.S.PLAY or g.demo_op != "" or g.mode != Game.Mode.PLAY:
		return
	var ld = g.squad.leader()
	var i: int = ld.manual_index() if ld != null else -1
	if i < 0 or not ld.manual_aims(i):
		return
	if ld.manual_point(i):
		draw_point_aim(ld, i)
		return
	var dir := Vector2.ZERO
	var strong := false
	if g.touch.active:
		if g.touch.skill_id < 0:
			return
		dir = g.touch.aim_dir()
		strong = true
	else:
		dir = g.doctor.manual_input_dir()
		strong = dir != Vector2.ZERO
	var xf: Transform2D = g.hud_ct()
	var pt: Vector2 = ld.manual_aim_point(i, dir) if ld.manual_ready(i, dir) else Vector2.INF
	if pt == Vector2.INF:
		# 触屏按住没拖、自动瞄准又没目标（乌尔比安：400 内没敌人）：提示拖出方向，免得松手只飘一句「附近没有敌人」
		if g.touch.active and dir == Vector2.ZERO and manual_castable(ld, i):
			UI.text(g.hud, g.font, xf * (ld.pos + Vector2(0, -90)) - Vector2(100, 0), "附近没有敌人 · 拖动选方向", 13, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200)
		return
	var sc: float = xf.get_scale().x
	var a: float = (0.85 if strong else 0.4) * (0.8 + 0.2 * sin(g.t * 6.0))
	var from: Vector2 = xf * ld.pos
	var to: Vector2 = xf * pt
	var rad: float = ld.base("s3_r", 140.0) * ld.stat(&"op_range") * sc
	# 引导线：虚线，到圈边为止
	# 落点可能在屏幕外（射程 400 大于屏幕半高，验收 P2）：圈心夹进屏内，真实落点方向画一个小三角
	var vsz: Vector2 = g.hud.size
	# 四边余量至少 rad + 26（验收：原来左右下只有 rad*0.5+8，圈总出屏 62 像素），上边再让开计时面板
	var mtop: float = maxf(rad + 26.0, rad * 0.5 + 96.0)
	var inner := Rect2(Vector2(rad + 26.0, mtop), vsz - Vector2(rad * 2.0 + 52.0, mtop + rad + 26.0))
	var real_to: Vector2 = to
	to = to.clamp(inner.position, inner.end)
	# 三角只在真实落点出屏时画（验收 P3：落点在屏内、只是离边近被推进来时，三角会指到落点外很远）
	if real_to.distance_to(to) > 2.0 and not Rect2(Vector2.ZERO, vsz).has_point(real_to):
		var ad: Vector2 = (real_to - to).normalized()
		var tip: Vector2 = to + ad * (rad - 4.0)   # 三角画在圈内贴边（画在圈外会跟着出屏）
		var sd: Vector2 = ad.orthogonal() * 7.0
		g.hud.draw_colored_polygon(PackedVector2Array([tip, tip - ad * 12.0 + sd, tip - ad * 12.0 - sd]), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a))
	var seg: Vector2 = to - from
	var ln: float = seg.length()
	if ln > rad + 8.0:
		var u: Vector2 = seg / ln
		var t := 18.0
		while t < ln - rad:
			g.hud.draw_line(from + u * t, from + u * minf(t + 10.0, ln - rad), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.7), 2.0)
			t += 18.0
	g.hud.draw_circle(to, rad, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.1))
	g.hud.draw_arc(to, rad, 0.0, TAU, 48, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	# 圈内四个刻度 + 中心点：一眼看出落点
	for q in 4:
		var d: Vector2 = Vector2.from_angle(q * PI / 2.0 + g.t * 0.8)
		g.hud.draw_line(to + d * (rad - 10.0), to + d * (rad - 2.0), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	g.hud.draw_circle(to, 3.0, Color(1, 1, 1, a))
	if g.touch.active and dir == Vector2.ZERO:
		UI.text(g.hud, g.font, to + Vector2(-40, -rad - 8.0), "自动瞄准", 12, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), HORIZONTAL_ALIGNMENT_CENTER, 80)


## 选落点的手动技能（契约 v2.5，JSON "aim": "point"，首个是乌尔比安 S3）：落点圈跟着取点走（鼠标光标 / 键盘蓄距离 /
## 右摇杆推量 / 触屏拖动，doctor.point_preview 已夹在射程内），圈一直实线；蓄距离或触屏拖动时淡淡画出射程圆，键盘蓄距离时圈旁一段进度弧
func draw_point_aim(ld, i: int) -> void:
	# 充满就画（手动普攻时主控几乎一直在出手，按 manual_ready 判会一闪一闪）；此刻放不了（出手中 / 锚未收回）时淡一些
	var charged: bool = ld.skill_unlocked(i) and not ld.perm[i] and ld.sp_need(i) > 0.0 and ld.sp[i] >= ld.sp_need(i) and ld.skill_active_left(i) <= 0.0
	if not charged:
		return
	var rdy: bool = ld.manual_ready(i, Vector2.RIGHT)
	var pt: Vector2 = ld.manual_aim_point(i)
	if pt == Vector2.INF:
		return
	var xf: Transform2D = g.hud_ct()
	var sc: float = xf.get_scale().x
	var from: Vector2 = xf * ld.pos
	var to: Vector2 = xf * pt
	var rad: float = ld.base("s3_r", 140.0) * ld.stat(&"op_range") * sc
	var a: float = (0.85 if rdy else 0.4) * (0.8 + 0.2 * sin(g.t * 6.0))
	var charging: bool = not g.doctor.charge.is_empty()
	var dragging: bool = g.touch.active and g.touch.skill_id >= 0
	if charging or dragging:
		var rr: float = ld.aim_range(i) * sc
		g.hud.draw_arc(from, rr, 0.0, TAU, 64, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, 0.22), 1.5)
	# 落点可能在屏幕外（射程 400 大于屏幕半高，验收 P2）：圈心夹进屏内，真实落点方向画一个小三角
	var vsz: Vector2 = g.hud.size
	# 四边余量至少 rad + 26（验收：原来左右下只有 rad*0.5+8，圈总出屏 62 像素），上边再让开计时面板
	var mtop: float = maxf(rad + 26.0, rad * 0.5 + 96.0)
	var inner := Rect2(Vector2(rad + 26.0, mtop), vsz - Vector2(rad * 2.0 + 52.0, mtop + rad + 26.0))
	var real_to: Vector2 = to
	to = to.clamp(inner.position, inner.end)
	# 三角只在真实落点出屏时画（验收 P3：落点在屏内、只是离边近被推进来时，三角会指到落点外很远）
	if real_to.distance_to(to) > 2.0 and not Rect2(Vector2.ZERO, vsz).has_point(real_to):
		var ad: Vector2 = (real_to - to).normalized()
		var tip: Vector2 = to + ad * (rad - 4.0)   # 三角画在圈内贴边（画在圈外会跟着出屏）
		var sd: Vector2 = ad.orthogonal() * 7.0
		g.hud.draw_colored_polygon(PackedVector2Array([tip, tip - ad * 12.0 + sd, tip - ad * 12.0 - sd]), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a))
	var seg: Vector2 = to - from
	var ln: float = seg.length()
	if ln > rad + 8.0:
		var u: Vector2 = seg / ln
		var t := 18.0
		while t < ln - rad:
			g.hud.draw_line(from + u * t, from + u * minf(t + 10.0, ln - rad), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.7), 2.0)
			t += 18.0
	g.hud.draw_circle(to, rad, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.1))
	g.hud.draw_arc(to, rad, 0.0, TAU, 48, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	for q in 4:
		var d: Vector2 = Vector2.from_angle(q * PI / 2.0 + g.t * 0.8)
		g.hud.draw_line(to + d * (rad - 10.0), to + d * (rad - 2.0), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	g.hud.draw_circle(to, 3.0, Color(1, 1, 1, a))
	if charging:
		# 蓄距离进度：圈右上一段弧，蓄满（manual/point_charge 秒）= 射程最远
		var ck: float = clampf(float(g.doctor.charge.get("t", 0.0)) / maxf(0.05, Game.Bal.v("manual/point_charge", 0.6)), 0.0, 1.0)
		var full: bool = ck >= 1.0
		var cc: Color = UI.GOLD.lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(g.t * 14.0)) if full else Color(1, 1, 1, 0.9)
		g.hud.draw_arc(to, rad + 8.0, -PI / 2.0, -PI / 2.0 + TAU * ck, 40, cc, 4.0 if full else 3.0)   # 蓄满：金白闪
