extends Control
## 结算 / 寻访两屏的静态样张（docs/125，10-22 用户：要更强的明日方舟设计味，以图鉴 C4′ / 选人 B+ 为锚，不另起风格）。
## 只给审稿用：autotest --akmock=<屏> 盖在 HUD 上画、截图退出；数据是写死的示例，不读写存档、不碰 g.rng。
## 用和选人 B+ 同一套部件（class_band 职业斜带、ghost_name 描边英文名、bpanel / btabs / pill / btab / deploy_button / roster_card），
## 设计稿尺寸同选人页：桌面 1280×720、手机 740×360，按视口等比缩放居中。
## 屏：result（结算）/ hunt（寻访入口）/ reveal（揭示）/ pick_class（招募券）/ pick_letter（人事调度函）/ hunt_result（寻访结果）

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")

const DESK := Vector2(1280, 720)
const PHONE := Vector2(740, 360)
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
const CLASS_EN := {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER", "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}
## 三种券的识别色：寻访凭证 青 / 招募券 紫 / 人事调度函 近白（不用黄，黄只留给图鉴，docs/37 §2）
const TICKET := [["寻访凭证", "HEADHUNTING PERMIT", Color(0.235, 0.784, 0.894)], ["招募券", "RECRUITMENT PERMIT", Color(0.486, 0.42, 1.0)], ["人事调度函", "TRANSFER ORDER", Color(0.85, 0.9, 0.95)]]
const LOCKED := ["mizuki", "skadi", "irene", "lumen", "logos", "specter_unchained", "gladiia", "kaltsit", "ulpianus", "wisadel", "skalter", "lappland", "angelina"]
const GOLD_T := Color(1.0, 0.769, 0.314)      # 金档 #FFC450（docs/124 §9.3，只在寻访档位上用）
const GOLD_HI := Color(1.0, 0.941, 0.706)

var g
var which := "result"
var font: Font
var _od := {}
var k := 1.0
var off := Vector2.ZERO
var phone := false


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	font = g.font
	var vs := size
	phone = Pad.touch
	var dsz := PHONE if phone else DESK
	k = minf(vs.x / dsz.x, vs.y / dsz.y)
	off = ((vs - dsz * k) / 2.0).round()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05))
	draw_set_transform(off, 0.0, Vector2(k, k))
	if which.ends_with("_f"):
		_f(dsz)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if which.ends_with("_v2"):
		_v2(dsz)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if which.ends_with("_b"):
		_b_backdrop(dsz)
		match which:
			"result_b":
				_b_result(dsz)
			"hunt_b":
				_b_hunt(dsz)
			"reveal_b":
				_b_reveal(dsz)
			"pick_class_b":
				_b_pick_class(dsz)
			"pick_letter_b":
				_b_pick_letter(dsz)
			"hunt_result_b":
				_b_hunt_result(dsz)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_backdrop(dsz)
	match which:
		"result":
			_result_phone() if phone else _result_desk()
		"hunt":
			_hunt_phone() if phone else _hunt_desk()
		"reveal":
			_reveal(dsz)
		"pick_class":
			_pick_class(dsz)
		"pick_letter":
			_pick_letter(dsz)
		"hunt_result":
			_hunt_result(dsz)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 公共

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
	var od := {"id": cid, "tex": tx, "frames": frames, "hires": A.hires_of(tx), "ds": UI.op_scale(d), "name": d.get("name", cid), "cls": cls, "col": col,
		"en": str(d.get("en", cid)).to_upper(), "def": d}
	_od[cid] = od
	return od


## 背景：同选人 B+（深海青 → 深紫斜向渐变 + 中心青色柔光）+ 网点底纹（原作底图的网点质感，docs/125 规则 4）
func _backdrop(dsz: Vector2) -> void:
	var c0 := Color(6 / 255.0, 30 / 255.0, 40 / 255.0)
	var c1 := Color(30 / 255.0, 14 / 255.0, 52 / 255.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(dsz.x, 0), dsz, Vector2(0, dsz.y)]), PackedColorArray([c0.lerp(c1, 0.45), c1, c0.lerp(c1, 0.55), c0]))
	for i in 5:
		draw_circle(Vector2(dsz.x * 0.6, dsz.y * 0.45), dsz.y * (0.55 - i * 0.09), Color(0.24, 0.78, 0.9, 0.018))
	var step := 6.0
	var y := 0.0
	while y < dsz.y:
		var x := fmod(y / step, 2.0) * step / 2.0
		while x < dsz.x:
			draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, 0.025))
			x += step
		y += step


## 立绘：整数倍（@2x 像素 × k2），脚底点 foot；sil = 剪影色（未解锁 / 揭示前）
func _figure(od: Dictionary, foot: Vector2, k2: float, sil := Color(0, 0, 0, 0), frame := 0, ring := true, clip := Rect2()) -> Rect2:
	var tx: Texture2D = od.tex
	if tx == null:
		return Rect2()
	var hi: float = od.hires
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	var kk: float = k2 * 2.0 / hi * float(od.ds)
	var pos := UI.foot_pos(foot, bb, fw, tx.get_height(), hi, kk).round()
	var dst := Rect2(pos, (bb.size * kk).round())
	var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	if ring:   # 脚下投影环（压扁的断续环，同揭示演出）
		draw_set_transform(off + foot * k, 0.0, Vector2(k, k * 0.22))
		for i in 3:
			draw_arc(Vector2.ZERO, bb.size.x * kk * (0.42 + 0.16 * i), 0, TAU, 40, Color(UI.B_ACC.r, UI.B_ACC.g, UI.B_ACC.b, 0.3 - 0.08 * i), 2.0)
		draw_set_transform(off, 0.0, Vector2(k, k))
	var t2: Texture2D = A.white_of(tx) if sil.a > 0.0 else tx
	var c2 := sil if sil.a > 0.0 else Color.WHITE
	if clip.size.x > 0.0:
		UI.blit_clipped(self, t2, dst, src, clip, c2)
	else:
		draw_texture_rect_region(t2, dst, src, c2)
	return dst


## 顶栏：节点标签条式标题（紫底白斜体英文 + 饰角菱形）+ 中文标题 + 两行说明 + 右侧标签片 + 返回（同选人 B+）
func _topbar(W: float, en: String, cn: String, sub1: String, sub2: String, chips: Array, back := "返回  Esc") -> void:
	var h := 30.0 if phone else 54.0
	draw_rect(Rect2(0, 0, W, h), Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.55))
	_hline(h + 0.5, W)
	if phone:
		var lw := UI.cwidth(font, cn, 13) + 24.0
		UI.rbox(self, Rect2(8, 5, lw, 21), 3, UI.VIOLET)
		UI.text_at(self, font, Vector2(16, 15.5), cn, 13, Color.WHITE, "lm")
		UI.en(self, font, Vector2(lw + 16, 20), en, 8, UI.fa(UI.B_SUB, 0.8), 2.0, true)
		var bk := Rect2(W - 66, 5, 56, 21)
		UI.bpanel(self, bk)
		UI.text_at(self, font, bk.get_center(), back.split(" ")[0], 11, UI.TEXT, "mm")
		return
	var lw2 := UI.en_width(font, en, 11, 2.0) + 24.0
	UI.rbox(self, Rect2(16, 12, lw2, 30), 3, UI.VIOLET)
	UI.en(self, font, Vector2(26, 19 + UI.cond(font, true).get_ascent(11)), en, 11, Color.WHITE, 2.0, true)
	UI.diamond(self, Vector2(16, 27), 5.0, UI.B_ACC)
	var tw := UI.text_at(self, font, Vector2(lw2 + 32, 27), cn, 20, UI.TEXT, "lm")
	var sx := lw2 + 32 + tw + 20.0
	UI.text_at(self, font, Vector2(sx, 14), sub1, 12, UI.B_SUB)
	UI.text_at(self, font, Vector2(sx, 30), sub2, 11, UI.B_SUB)
	var bk2 := Rect2(W - 120, 14, 104, 28)
	UI.bpanel(self, bk2)
	UI.text_at(self, font, bk2.get_center(), back, 12, UI.TEXT, "mm")
	var px := W - 136.0
	for c in chips:
		px -= UI.pill_width(font, c[0], 11)
		UI.pill(self, font, Vector2(px, 18), c[0], c[1], 11)
		px -= 6.0


func _hline(y: float, w: float) -> void:
	var cl := Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(w / 2.0, y), Vector2(w, y)]), PackedColorArray([cl, Color(cl.r, cl.g, cl.b, 0.43), cl]), 1.0)


## 段落标签：「OPERATOR FILE // PROFILE」式小号英文 + 中文（同图鉴 / 选人的段落头）
func _label(p: Vector2, en: String, cn: String, size := 9) -> void:
	var w := UI.en(self, font, p, en + "  //  ", size, UI.fa(UI.B_SUB, 0.75), 2.0)
	UI.text_at(self, font, Vector2(p.x + w, p.y - size + 1), cn, size, UI.fa(UI.B_SUB, 0.9))


## 名字块（同选人 B+ 桌面）：微型代码 + 大字中文名 + 彩色斜体英文名 + 标签片；返回下一行 y
func _name_block(p: Vector2, code: String, cn: String, en: String, col: Color, pills: Array, size := 40) -> float:
	UI.en(self, font, p, code, 9 if phone else 10, UI.fa(UI.B_SUB, 0.9), 3.0)
	UI.text_at(self, font, p + Vector2(-2, 8), cn, size, UI.TEXT, "la", true)
	var ey := p.y + 8 + size * 1.5
	UI.en(self, font, Vector2(p.x + 2, ey + 4), en, maxi(9, int(size * 0.3)), col, 5.0, true)
	var px := p.x
	var py := ey + 14
	for pl in pills:
		px += UI.pill(self, font, Vector2(px, py), pl[0], pl[1], 10 if phone else 11, pl.size() > 2 and pl[2])
	return py + 24


## 大号数字 + 小号标签（原作数据页式，docs/125 规则 6）
func _bignum(p: Vector2, num: String, cn: String, en: String, size := 30) -> float:
	var w := UI.text_at(self, font, p, num, size, UI.TEXT, "la", true)
	UI.text_at(self, font, Vector2(p.x, p.y + size * 1.3 + 2), cn, 11 if not phone else 9, UI.B_SUB)
	UI.en(self, font, Vector2(p.x + UI.cwidth(font, cn, 11 if not phone else 9) + 6, p.y + size * 1.3 + 14), en, 7, UI.fa(UI.B_SUB, 0.6), 2.0)
	return w


## 读数条（细轨 + 实段 + 端点刻度）
func _readout(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(Rect2(r.position.x, r.get_center().y - 1, r.size.x, 2), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(r.position.x, r.get_center().y - 2, r.size.x * clampf(frac, 0.0, 1.0), 4), col)
	draw_rect(Rect2(r.position.x + r.size.x * clampf(frac, 0.0, 1.0) - 1, r.position.y, 2, r.size.y), UI.TEXT)


## 券图标（本作自画：切角票面 + 识别色竖条 + 编号孔）
func _ticket_icon(c: Vector2, s: float, col: Color) -> void:
	var r := Rect2(c - Vector2(13, 8) * s, Vector2(26, 16) * s)
	UI.rbox(self, r, 2 * s, Color(0.03, 0.05, 0.09, 0.9), col, 1)
	draw_rect(Rect2(r.position + Vector2(3, 3) * s, Vector2(3, 10) * s), col)
	for i in 3:
		draw_rect(Rect2(r.position + Vector2(10 + i * 4, 7) * s, Vector2(2, 2) * s), UI.fa(col, 0.7))


## 奖励底光圈（原作获得物背后的光圈，docs/125 规则 7）：三圈台阶式同心圆
func _halo(c: Vector2, rad: float, col: Color) -> void:
	for i in 3:
		draw_circle(c, rad * (1.0 - i * 0.22), UI.fa(col, 0.07 + 0.05 * i))


## 锁定剪影卡（名册卡同款，人物换成剪影 + 右上小锁）
func _locked_card(r: Rect2, od: Dictionary, sel := false) -> void:
	UI.rbox(self, r, 5, Color(0.086, 0.102, 0.204, 0.92) if sel else Color(0.039, 0.078, 0.118, 0.86), UI.VIOLET if sel else UI.B_LINE, 2 if sel else 1)
	draw_rect(Rect2(r.position.x + 4, r.position.y + 2, r.size.x - 8, 3), UI.fa(od.col, 0.45))
	var tx: Texture2D = od.tex
	if tx != null:
		var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
		var bb: Rect2 = UI.card_bb(od, tx)
		var pl := UI.card_place(r, fw, tx.get_height(), od.hires, bb, 24.0, float(od.ds))
		UI.blit_clipped(self, A.white_of(tx), pl, Rect2(bb.position, bb.size), r.grow(-1.0), Color(0.16, 0.22, 0.36) if sel else Color(0.10, 0.14, 0.24))
	UI.rbox(self, Rect2(r.position.x + 2, r.end.y - 22, r.size.x - 4, 20), 4, Color(0.016, 0.031, 0.063, 0.78))
	UI.class_glyph(self, od.cls, r.position + Vector2(12, 16), 5.0, UI.fa(od.col, 0.6), 1.6)
	var fl := UI.fit_line(font, str(od.name), 11, r.size.x - 8.0, 9)
	UI.text_at(self, font, Vector2(r.get_center().x, r.end.y - 12), fl[0], fl[1], UI.fa(UI.TEXT, 0.9 if sel else 0.55), "mm")
	_lock(Vector2(r.end.x - 11, r.position.y + 14), UI.fa(UI.B_SUB, 0.9))
	if sel:
		UI.diamond(self, Vector2(r.get_center().x, r.position.y), 5.0, UI.B_ACC)


func _lock(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-4, -1), Vector2(8, 6)), col)
	draw_arc(c + Vector2(0, -1), 3.0, PI, TAU, 8, col, 1.5)


func _btn(r: Rect2, s: String, key := "", hot := false) -> void:
	UI.bpanel(self, r, false, hot, 1.0, UI.CYAN)
	UI.text_at(self, font, Vector2(r.position.x + 14, r.get_center().y), s, 13 if not phone else 12, UI.TEXT, "lm")
	if key != "" and not phone:
		UI.keycap(self, font, Vector2(r.end.x - UI.cwidth(font, key, 10) - 20, r.get_center().y - 9), key, UI.B_SUB, 10)


# ---------------------------------------------------------------- 结算

## 逐项计分（docs/109 §3.1；版式照原作集成战略结算：项目 / 次数 / 分值，最后总计 × 系数 → 换算）
const SCORE := [["存活", "SURVIVAL", "10:24", "100"], ["中期 Boss", "MID-BOSS", "×2", "40"], ["通关", "CLEAR", "最终 Boss", "60"], ["结局首达", "FIRST ENDING", "不乘系数", "40"]]
const SQUAD := [["mizuki", "队长 · 开局", 0.46], ["lumen", "第 3 分钟", 0.21], ["skadi", "第 6 分钟", 0.33]]


func _result_desk() -> void:
	var W := DESK.x
	var H := DESK.y
	var lead := _card("mizuki")
	UI.class_band(self, H, -20.0, 1.0, lead.col, Color(0, 0, 0, 0), 1.0, 0.35)
	UI.ghost_name(self, font, Vector2(360, 66), "PRECIOUS", 1.0, 150)
	UI.ghost_name(self, font, Vector2(470, 214), "DAYS", 1.0, 150)
	_figure(lead, Vector2(640, 560), 5.0)
	_topbar(W, "OPERATION REPORT", "作战记录", "潮位 8 · 漫灌 · 结算系数 ×1.4", "本次探索的收获已存入档案", [["SEED 7F3A-21C9", UI.STEEL], ["潮位 8", UI.STEEL]])
	# 左：结果块（编号 // 结局 + 大字结果 + 英文 + 结局名）
	var y := _name_block(Vector2(40, 100), "No.01  //  ENDING  //  结局一", "探索完成", "OPERATION COMPLETE", UI.B_ACC,
		[["平凡即是喜乐", UI.PURPLE, true], ["首次达成", UI.B_ACC]], 48)
	UI.text_at(self, font, Vector2(40, y + 4), "泡影散了。水月回到岸上，准备好好吃一顿，迎接明天。", 12, UI.B_SUB)
	# 关键数字：大号数字 + 小号标签
	var bx := 40.0
	for it in [["10:24", "探索时间", "TIME"], ["1,284", "击杀", "KILLS"], ["3", "Boss 击破", "BOSSES"], ["412K", "造成伤害", "DAMAGE"]]:
		_bignum(Vector2(bx, y + 30), it[0], it[1], it[2], 28)
		bx += 98.0
	# 左下：编队（名册卡 + 伤害占比读数）
	_label(Vector2(40, 470), "SQUAD", "编队  ·  伤害占比")
	for i in SQUAD.size():
		var od := _card(SQUAD[i][0])
		var r := Rect2(40 + i * 98, 484, 88, 112)
		UI.roster_card(self, font, r, od, 0.0, 0.0, 2 if i == 0 else 1, 0, 1.0, 12)
		if i == 0:
			UI.btab(self, font, r.position + Vector2(r.size.x - 34, -6), "队长", UI.VIOLET, 9)
		_readout(Rect2(r.position.x, r.end.y + 8, r.size.x, 8), SQUAD[i][2], od.col)
		UI.en(self, font, Vector2(r.position.x, r.end.y + 30), "%d%%" % int(SQUAD[i][2] * 100), 10, UI.TEXT, 1.0)
		UI.text_at(self, font, Vector2(r.end.x, r.end.y + 22), SQUAD[i][1], 9, UI.B_SUB, "ra")
	# 右：结算面板（页签：结算 / 数据 / 藏品；结算页 = 逐项计分 → 系数 → 生机细胞 → 券）
	var pr := Rect2(864, 70, 400, 540)
	UI.bpanel(self, pr, true)
	UI.en(self, font, Vector2(pr.position.x + 14, pr.position.y + 20), "OPERATION SCORE // 探索评分", 9, UI.fa(UI.B_SUB, 0.8), 2.0)
	UI.btabs(self, font, Rect2(pr.position.x + 4, pr.position.y + 26, pr.size.x - 8, 32), ["结算", "数据", "藏品"], 0.0, 14)
	var ry := pr.position.y + 80
	for row in SCORE:
		UI.diamond(self, Vector2(pr.position.x + 20, ry), 2.5, UI.B_ACC)
		UI.text_at(self, font, Vector2(pr.position.x + 30, ry), row[0], 13, UI.TEXT, "lm")
		UI.en(self, font, Vector2(pr.position.x + 108, ry + 4), row[1], 8, UI.fa(UI.B_SUB, 0.6), 2.0)
		UI.text_at(self, font, Vector2(pr.position.x + 250, ry), row[2], 11, UI.B_SUB, "rm")
		UI.text_at(self, font, Vector2(pr.end.x - 16, ry), row[3], 15, UI.TEXT, "rm", true)
		draw_line(Vector2(pr.position.x + 14, ry + 14), Vector2(pr.end.x - 14, ry + 14), Color(1, 1, 1, 0.05), 1.0)
		ry += 30.0
	# 总计 × 潮位系数 → 生机细胞
	draw_line(Vector2(pr.position.x + 14, ry - 2), Vector2(pr.end.x - 14, ry - 2), UI.fa(UI.B_ACC, 0.5), 1.0)
	UI.text_at(self, font, Vector2(pr.position.x + 16, ry + 14), "( 200 × 潮位 8 ×1.4 + 40 ) ÷ 8", 12, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(pr.end.x - 16, ry + 14), "= 40", 15, UI.TEXT, "rm", true)
	ry += 40.0
	_label(Vector2(pr.position.x + 16, ry + 8), "OUTCOME", "局外收获")
	ry += 18.0
	var cr := Rect2(pr.position.x + 12, ry, pr.size.x - 24, 78)
	UI.rbox(self, cr, 4, Color(0.03, 0.09, 0.12, 0.85), UI.fa(UI.GREEN, 0.5))
	draw_rect(Rect2(cr.position, Vector2(3, cr.size.y)), UI.GREEN)
	_halo(cr.position + Vector2(44, 44), 30, UI.GREEN)
	UI.btab(self, font, cr.position + Vector2(12, 10), "生机细胞", Color(0.1, 0.5, 0.42), 9)
	UI.text_at(self, font, cr.position + Vector2(14, 52), "+53", 30, UI.TEXT, "lm", true)
	UI.text_at(self, font, cr.position + Vector2(96, 30), "探索评分 +40", 11, UI.B_SUB, "lm")
	UI.text_at(self, font, cr.position + Vector2(96, 47), "首通潮位 8 赏金 +13", 11, UI.B_SUB, "lm")
	UI.en(self, font, cr.position + Vector2(cr.size.x - 128, 20), "COGNITION 222 / 560", 8, UI.fa(UI.B_SUB, 0.7), 2.0)
	_readout(Rect2(cr.position.x + 96, cr.end.y - 13, cr.size.x - 108, 6), 222.0 / 560.0, UI.GREEN)
	ry += 88.0
	for i in 3:
		var tr := Rect2(pr.position.x + 12 + i * 126, ry, 120, 50)
		UI.rbox(self, tr, 4, Color(0.03, 0.05, 0.09, 0.85), UI.fa(TICKET[i][2], 0.55))
		_halo(tr.position + Vector2(20, 25), 17, TICKET[i][2])
		_ticket_icon(tr.position + Vector2(20, 25), 1.0, TICKET[i][2])
		UI.text_at(self, font, tr.position + Vector2(40, 17), TICKET[i][0], 11, UI.TEXT, "lm")
		UI.text_at(self, font, tr.position + Vector2(40, 35), ["每次结算", "通关", "首通潮位 8"][i], 9, UI.B_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 8, tr.get_center().y), "×1", 14, TICKET[i][2], "rm", true)
	# 右下：主按钮「前往寻访」+ 次按钮
	UI.deploy_button(self, font, Rect2(1040, 630, 220, 72), "前往寻访  ›", "ENTER  ·  3 张券待用", 0.6, 0.0, 22)
	_btn(Rect2(864, 630, 160, 33), "再次探索", "R")
	_btn(Rect2(864, 669, 160, 33), "回到标题", "T")
	UI.en(self, font, Vector2(40, H - 16), "TAB  作战记录全文   ·   ENTER  前往寻访   ·   R  再次探索   ·   T  回到标题", 9, UI.fa(UI.B_SUB, 0.7), 2.0)


func _result_phone() -> void:
	var W := PHONE.x
	var H := PHONE.y
	var lead := _card("mizuki")
	UI.class_band(self, H, -150.0, 0.6, lead.col, Color(0, 0, 0, 0), 1.0, 0.35)
	UI.ghost_name(self, font, Vector2(130, 40), "PRECIOUS DAYS", 1.0, 70, Color(0.745, 0.824, 1.0, 0.18), 2)
	_figure(lead, Vector2(330, 300), 3.0)
	_topbar(W, "OPERATION REPORT", "作战记录", "", "", [])
	var y := _name_block(Vector2(14, 50), "ENDING  //  结局一", "探索完成", "OPERATION COMPLETE", UI.B_ACC, [["平凡即是喜乐", UI.PURPLE, true]], 30)
	var bx := 14.0
	for it in [["10:24", "时间", "TIME"], ["1,284", "击杀", "KILLS"], ["3", "Boss", "BOSS"]]:
		_bignum(Vector2(bx, y + 2), it[0], it[1], it[2], 18)
		bx += 64.0
	for i in SCORE.size():
		var row: Array = SCORE[i]
		var yy := y + 56 + i * 17
		UI.text_at(self, font, Vector2(14, yy), row[0], 10, UI.B_SUB, "lm")
		UI.text_at(self, font, Vector2(200, yy), row[3], 11, UI.TEXT, "rm", true)
		draw_line(Vector2(14, yy + 8), Vector2(200, yy + 8), Color(1, 1, 1, 0.05), 1.0)
	UI.text_at(self, font, Vector2(14, y + 56 + 4 * 17 + 2), "(200 ×1.4 + 40) ÷ 8 = 40", 10, UI.B_ACC, "lm")
	# 右：局外收获面板
	var pr := Rect2(470, 38, 262, 222)
	UI.bpanel(self, pr, true)
	_label(Vector2(pr.position.x + 10, pr.position.y + 18), "OUTCOME", "局外收获", 8)
	var cr := Rect2(pr.position.x + 8, pr.position.y + 26, pr.size.x - 16, 62)
	UI.rbox(self, cr, 4, Color(0.03, 0.09, 0.12, 0.85), UI.fa(UI.GREEN, 0.5))
	draw_rect(Rect2(cr.position, Vector2(3, cr.size.y)), UI.GREEN)
	_halo(cr.position + Vector2(32, 36), 24, UI.GREEN)
	UI.btab(self, font, cr.position + Vector2(10, 8), "生机细胞", Color(0.1, 0.5, 0.42), 9)
	UI.text_at(self, font, cr.position + Vector2(10, 42), "+53", 24, UI.TEXT, "lm", true)
	UI.text_at(self, font, cr.position + Vector2(72, 32), "评分 +40", 10, UI.B_SUB, "lm")
	UI.text_at(self, font, cr.position + Vector2(72, 47), "首通赏金 +13", 10, UI.B_SUB, "lm")
	_readout(Rect2(cr.position.x + 72, cr.end.y - 8, cr.size.x - 82, 6), 222.0 / 560.0, UI.GREEN)
	for i in 3:
		var tr := Rect2(pr.position.x + 8, pr.position.y + 96 + i * 40, pr.size.x - 16, 34)
		UI.rbox(self, tr, 4, Color(0.03, 0.05, 0.09, 0.85), UI.fa(TICKET[i][2], 0.55))
		_ticket_icon(tr.position + Vector2(18, 17), 0.9, TICKET[i][2])
		UI.text_at(self, font, tr.position + Vector2(38, 17), TICKET[i][0], 11, UI.TEXT, "lm")
		UI.text_at(self, font, tr.position + Vector2(120, 17), ["每次结算", "通关", "首通潮位 8"][i], 9, UI.B_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 8, tr.get_center().y), "×1", 13, TICKET[i][2], "rm", true)
	UI.deploy_button(self, font, Rect2(564, 284, 164, 62), "前往寻访  ›", "3 张券待用", 0.6, 0.0, 18)
	_btn(Rect2(400, 284, 148, 29), "再次探索")
	_btn(Rect2(400, 317, 148, 29), "回到标题")
	_btn(Rect2(240, 317, 148, 29), "作战记录")


# ---------------------------------------------------------------- 寻访入口

func _hunt_desk() -> void:
	var W := DESK.x
	var H := DESK.y
	var wish := _card("mizuki")
	UI.class_band(self, H, -20.0, 1.0, wish.col, Color(0, 0, 0, 0), 1.0, 0.35)
	UI.ghost_name(self, font, Vector2(330, 66), "HEADHUNTING", 1.0, 120)
	# 卡池：意向干员大剪影居中，另两名在后（远近视差；不剧透立绘，docs/124 §9.2）
	_figure(_card("skadi"), Vector2(470, 500), 3.0, Color(0.08, 0.11, 0.19), 0, false)
	_figure(_card("kaltsit"), Vector2(820, 500), 3.0, Color(0.08, 0.11, 0.19), 0, false)
	_figure(wish, Vector2(640, 560), 5.0, Color(0.13, 0.19, 0.32))
	_topbar(W, "HEADHUNTING", "寻访", "常驻寻访 · 罗德岛人事档案", "未解锁干员 13 名 · 不会重复", [["名册 6 / 19", UI.STEEL]])
	var y := _name_block(Vector2(40, 100), "PREFERRED  //  意向干员", "水月", "MIZUKI", UI.PURPLE, [["特种", UI.PURPLE], ["近战", UI.STEEL], ["未解锁", UI.STEEL]], 44)
	# 意向保底：三格进度 + 原作句式
	_label(Vector2(40, y + 20), "PITY", "意向干员保底")
	for i in 3:
		UI.rbox(self, Rect2(40 + i * 46, y + 30, 40, 10), 2, UI.VIOLET if i < 2 else Color(0, 0, 0, 0.4), UI.fa(UI.VIOLET, 0.8))
	UI.text_at(self, font, Vector2(40, y + 62), "再寻访 1 次，必定获得 水月", 15, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(40, y + 84), "只在使用寻访凭证时计数；更换意向会清零", 11, UI.B_SUB, "lm")
	_btn(Rect2(40, y + 102, 150, 30), "更换意向干员", "W")
	# 右：持有的券 + 规则
	var pr := Rect2(904, 70, 360, 330)
	UI.bpanel(self, pr, true)
	UI.en(self, font, Vector2(pr.position.x + 14, pr.position.y + 20), "TICKETS // 持有", 9, UI.fa(UI.B_SUB, 0.8), 2.0)
	for i in 3:
		var tr := Rect2(pr.position.x + 12, pr.position.y + 34 + i * 62, pr.size.x - 24, 54)
		UI.rbox(self, tr, 4, Color(0.03, 0.05, 0.09, 0.85), UI.fa(TICKET[i][2], 0.5))
		draw_rect(Rect2(tr.position, Vector2(3, tr.size.y)), TICKET[i][2])
		_halo(tr.position + Vector2(28, 27), 20, TICKET[i][2])
		_ticket_icon(tr.position + Vector2(28, 27), 1.2, TICKET[i][2])
		UI.text_at(self, font, tr.position + Vector2(56, 20), TICKET[i][0], 14, UI.TEXT, "lm", true)
		UI.en(self, font, tr.position + Vector2(56, 42), TICKET[i][1], 8, UI.fa(UI.B_SUB, 0.7), 2.0)
		UI.text_at(self, font, tr.position + Vector2(176, 20), ["随机 1 名 · 计入保底", "选职业 · 随机 1 名", "指定 1 名"][i], 10, UI.B_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 12, tr.get_center().y), "×%d" % [2, 1, 0][i], 22, TICKET[i][2] if i < 2 else UI.fa(UI.B_SUB, 0.6), "rm", true)
	var ry := pr.position.y + 234
	_label(Vector2(pr.position.x + 14, ry), "RULES", "规则")
	for j in 3:
		UI.diamond(self, Vector2(pr.position.x + 18, ry + 20 + j * 22), 2.5, UI.B_ACC)
		UI.text_at(self, font, Vector2(pr.position.x + 28, ry + 20 + j * 22), ["未解锁干员 13 名，不会抽到重复干员", "首次寻访必定获得医疗干员", "名册已满后，券换成生机细胞"][j], 11, UI.B_SUB, "lm")
	# 左下：未解锁名册条
	_label(Vector2(40, 562), "ROSTER", "未解锁 13 名  ·  已解锁 6 / 19")
	for i in 8:
		_locked_card(Rect2(40 + i * 66, 574, 60, 82), _card(LOCKED[i]), LOCKED[i] == "mizuki")
	UI.text_at(self, font, Vector2(40 + 8 * 66 + 6, 615), "▶ 还有 5 名", 11, UI.B_SUB, "lm")
	# 右下：寻访一次 / 全部使用
	_btn(Rect2(904, 640, 150, 50), "寻访一次", "1")
	UI.deploy_button(self, font, Rect2(1074, 628, 186, 72), "全部使用  ›", "ENTER  ·  共 3 张", 0.6, 0.0, 22)


func _hunt_phone() -> void:
	var W := PHONE.x
	var H := PHONE.y
	var wish := _card("mizuki")
	UI.class_band(self, H, -150.0, 0.6, wish.col, Color(0, 0, 0, 0), 1.0, 0.35)
	UI.ghost_name(self, font, Vector2(150, 40), "HEADHUNTING", 1.0, 64, Color(0.745, 0.824, 1.0, 0.18), 2)
	_figure(wish, Vector2(330, 300), 3.0, Color(0.13, 0.19, 0.32))
	_topbar(W, "HEADHUNTING", "寻访", "", "", [])
	var y := _name_block(Vector2(14, 50), "PREFERRED  //  意向干员", "水月", "MIZUKI", UI.PURPLE, [["特种", UI.PURPLE], ["未解锁", UI.STEEL]], 28)
	for i in 3:
		UI.rbox(self, Rect2(14 + i * 34, y + 4, 30, 8), 2, UI.VIOLET if i < 2 else Color(0, 0, 0, 0.4), UI.fa(UI.VIOLET, 0.8))
	UI.text_at(self, font, Vector2(14, y + 26), "再寻访 1 次，必定获得 水月", 11, UI.TEXT, "lm", true)
	_btn(Rect2(14, y + 42, 120, 28), "更换意向")
	var pr := Rect2(500, 38, 232, 196)
	UI.bpanel(self, pr, true)
	for i in 3:
		var tr := Rect2(pr.position.x + 8, pr.position.y + 10 + i * 46, pr.size.x - 16, 40)
		UI.rbox(self, tr, 4, Color(0.03, 0.05, 0.09, 0.85), UI.fa(TICKET[i][2], 0.5))
		draw_rect(Rect2(tr.position, Vector2(3, tr.size.y)), TICKET[i][2])
		_ticket_icon(tr.position + Vector2(22, 20), 1.0, TICKET[i][2])
		UI.text_at(self, font, tr.position + Vector2(44, 14), TICKET[i][0], 12, UI.TEXT, "lm", true)
		UI.text_at(self, font, tr.position + Vector2(44, 29), ["随机 · 计入保底", "选职业", "指定 1 名"][i], 9, UI.B_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 8, tr.get_center().y), "×%d" % [2, 1, 0][i], 16, TICKET[i][2] if i < 2 else UI.fa(UI.B_SUB, 0.6), "rm", true)
	UI.text_at(self, font, Vector2(pr.position.x + 10, pr.end.y - 14), "未解锁 13 名 · 不会重复", 9, UI.B_SUB, "lm")
	_btn(Rect2(400, 290, 144, 54), "寻访一次")
	UI.deploy_button(self, font, Rect2(560, 282, 168, 64), "全部使用  ›", "共 3 张", 0.6, 0.0, 18)


# ---------------------------------------------------------------- 揭示 / 定向 / 结果

func _reveal(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("lumen")
	if phone:
		UI.class_band(self, H, -150.0, 0.6, od.col, Color(0, 0, 0, 0), 1.0, 0.35)
		UI.ghost_name(self, font, Vector2(150, 40), od.en, 1.0, 90, Color(0.745, 0.824, 1.0, 0.18), 2)
		_figure(od, Vector2(380, 300), 4.0, Color(0, 0, 0, 0), 2)
	else:
		UI.class_band(self, H, -20.0, 1.0, od.col, Color(0, 0, 0, 0), 1.0, 0.35)
		UI.ghost_name(self, font, Vector2(380, 78), od.en, 1.0, 150)
		_figure(od, Vector2(660, 600), 6.0, Color(0, 0, 0, 0), 2)
	_topbar(W, "HEADHUNTING  //  01 / 03", "寻访", "寻访凭证 · 第 1 张", "点击继续 · Esc 跳过全部", [["新职业", GOLD_T]], "跳过  Esc")
	var p := Vector2(14, 60) if phone else Vector2(40, 300)
	var y := _name_block(p, "No.10  //  医疗  //  MEDIC", "流明", "LUMEN", od.col, [["医疗", od.col], ["新职业 · 医疗", GOLD_T, true], ["罗德岛（驻伊比利亚）", UI.STEEL]], 30 if phone else 52)
	# NEW 章（金档金边，斜置）
	var sp := Vector2(p.x + (150 if phone else 250), p.y + (30 if phone else 44))
	draw_set_transform(off + sp * k, deg_to_rad(-8.0), Vector2(k, k))
	var sr := Rect2(Vector2(-40, -15), Vector2(80, 30))
	draw_rect(sr, Color(GOLD_T.r, GOLD_T.g, GOLD_T.b, 0.18))
	draw_rect(sr, GOLD_T, false, 2.0)
	UI.en(self, font, Vector2(-26, 7), "NEW", 18, GOLD_HI, 6.0)
	draw_set_transform(off, 0.0, Vector2(k, k))
	UI.text_at(self, font, Vector2(p.x, y + 6), "干员 流明 已加入名册", 13 if not phone else 11, UI.TEXT, "lm")
	if not phone:
		UI.text_at(self, font, Vector2(p.x, y + 28), "开局可选为队长；局内招募不再标「临时招募」", 11, UI.B_SUB, "lm")
		# 右：本次寻访队列（第几名 / 共几名，后面的人保持剪影）
		var pr := Rect2(1104, 300, 160, 230)
		UI.bpanel(self, pr, true)
		UI.en(self, font, Vector2(pr.position.x + 12, pr.position.y + 18), "QUEUE // 本次", 8, UI.fa(UI.B_SUB, 0.8), 2.0)
		for i in 3:
			var cid: String = ["lumen", "irene", "gladiia"][i]
			var r := Rect2(pr.position.x + 10, pr.position.y + 28 + i * 66, pr.size.x - 20, 58)
			UI.rbox(self, r, 4, UI.B_FILL_SEL if i == 0 else UI.B_FILL, UI.VIOLET if i == 0 else UI.B_LINE, 2 if i == 0 else 1)
			_figure_mini(_card(cid), r, i > 0)
			UI.text_at(self, font, r.position + Vector2(62, 22), _card(cid).name if i == 0 else "？？？", 12, UI.TEXT if i == 0 else UI.B_SUB, "lm")
			UI.text_at(self, font, r.position + Vector2(62, 40), ["寻访凭证", "人事调度函", "招募券"][i], 9, UI.B_SUB, "lm")


func _figure_mini(od: Dictionary, r: Rect2, sil: bool) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
	var bb: Rect2 = UI.card_bb(od, tx)
	var cell := Rect2(r.position + Vector2(4, 4), Vector2(52, r.size.y - 8))
	var pl := UI.card_place(cell, fw, tx.get_height(), od.hires, bb, 0.0, float(od.ds))
	UI.blit_clipped(self, A.white_of(tx) if sil else tx, pl, Rect2(bb.position, bb.size), cell, Color(0.12, 0.17, 0.28) if sil else Color.WHITE)


func _pick_class(dsz: Vector2) -> void:
	var W := dsz.x
	_topbar(W, "RECRUITMENT PERMIT", "招募券 · 选择职业", "从所选职业的未解锁干员里随机解锁 1 名", "持有 招募券 ×1", [["职业 5 / 8 已有", UI.STEEL]])
	var cols := 4
	var x0 := 14.0 if phone else 40.0
	var top := 40.0 if phone else 76.0
	var cw := (W - x0 * 2 - 10.0 * (cols - 1)) / cols
	var ch := 120.0 if phone else 236.0
	var owned := ["先锋", "重装", "术师", "辅助", "狙击"]
	var nlock := {"先锋": 1, "近卫": 3, "重装": 0, "狙击": 1, "术师": 1, "医疗": 2, "辅助": 1, "特种": 4}
	var per := {"先锋": ["siege"], "近卫": ["skadi", "irene", "lappland"], "重装": [], "狙击": ["wisadel"], "术师": ["logos"], "医疗": ["lumen", "kaltsit"], "辅助": ["angelina"], "特种": ["mizuki", "specter_unchained", "gladiia", "skalter"]}
	for i in 8:
		var cls: String = CLASS_ORDER[i]
		var r := Rect2(x0 + (i % cols) * (cw + 10), top + int(i / cols) * (ch + 10), cw, ch)
		var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
		var dis: bool = nlock[cls] == 0
		var sel := cls == "近卫"
		var a := 0.45 if dis else 1.0
		UI.bpanel(self, r, sel, sel, a, UI.VIOLET)
		draw_rect(Rect2(r.position.x + 4, r.position.y + 2, r.size.x - 8, 3), UI.fa(col, 0.35 if dis else 1.0))
		# 卡内职业色斜带（选中才亮，同选人舞台的斜带语言）
		if sel:
			draw_colored_polygon(PackedVector2Array([r.position + Vector2(r.size.x * 0.5, 5), r.position + Vector2(r.size.x * 0.8, 5), r.position + Vector2(r.size.x * 0.6, r.size.y - 1), r.position + Vector2(r.size.x * 0.3, r.size.y - 1)]), UI.fa(col, 0.18))
		var gy := r.position.y + (24 if phone else 40)
		UI.class_glyph(self, cls, Vector2(r.position.x + (22 if phone else 34), gy), 9.0 if phone else 14.0, UI.fa(col, 0.35 if dis else 1.0), 2.0)
		UI.text_at(self, font, Vector2(r.position.x + (40 if phone else 60), gy - 2), cls, 15 if phone else 24, UI.fa(UI.TEXT, 0.4 if dis else 1.0), "lm", true)
		UI.en(self, font, Vector2(r.position.x + (40 if phone else 62), gy + (14 if phone else 22)), CLASS_EN[cls], 7 if phone else 9, UI.fa(col, 0.35 if dis else 0.9), 2.0)
		UI.text_at(self, font, Vector2(r.position.x + 12, r.end.y - 12), "已全部解锁" if dis else "未解锁 %d 名" % nlock[cls], 10 if phone else 12, UI.B_SUB, "lm")
		if not owned.has(cls) and not dis:
			UI.pill(self, font, Vector2(r.end.x - (52 if phone else 68), r.position.y + 10), "新职业", UI.PURPLE, 9 if phone else 10, true)
		var sx := r.position.x + 10
		for cid in per[cls]:
			var od := _card(cid)
			var cell := Rect2(sx, r.position.y + (44 if phone else 78), (26 if phone else 64), (52 if phone else 128))
			var tx: Texture2D = od.tex
			if tx != null:
				var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
				var bb: Rect2 = UI.card_bb(od, tx)
				var pl := UI.card_place(cell, fw, tx.get_height(), od.hires, bb, 0.0, float(od.ds))
				UI.blit_clipped(self, A.white_of(tx), pl, Rect2(bb.position, bb.size), cell, Color(0.22, 0.3, 0.48) if sel else Color(0.14, 0.2, 0.33))
			sx += cell.size.x + 4
	var br := Rect2(W - (182 if phone else 300), dsz.y - (64 if phone else 84), (168 if phone else 280), (56 if phone else 72))
	UI.deploy_button(self, font, br, "使用招募券 · 近卫  ›", "" if phone else "ENTER  ·  从 3 名近卫中随机 1 名", 0.6, 0.0, 15 if phone else 20)


func _pick_letter(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("mizuki")
	if phone:
		UI.class_band(self, H, -90.0, 0.6, od.col, Color(0, 0, 0, 0), 1.0, 0.35)
		UI.ghost_name(self, font, Vector2(220, 40), od.en, 1.0, 70, Color(0.745, 0.824, 1.0, 0.18), 2)
		_figure(od, Vector2(400, 300), 3.0, Color(0.13, 0.19, 0.32))
	else:
		UI.class_band(self, H, 60.0, 1.0, od.col, Color(0, 0, 0, 0), 1.0, 0.35)
		UI.ghost_name(self, font, Vector2(450, 78), od.en, 1.0, 140)
		_figure(od, Vector2(690, 590), 5.0, Color(0.13, 0.19, 0.32))
	_topbar(W, "TRANSFER ORDER", "人事调度函 · 指定干员", "选择 1 名未解锁干员直接加入名册", "立绘在解锁后显示", [["持有 ×1", UI.STEEL]])
	# 左：未解锁名册格
	var cols := 3 if phone else 4
	var cw := 52.0 if phone else 84.0
	var chh := 70.0 if phone else 108.0
	var x0 := 10.0 if phone else 40.0
	var y0 := 40.0 if phone else 76.0
	for i in mini(LOCKED.size(), 9 if phone else 16):
		var r := Rect2(x0 + (i % cols) * (cw + 6), y0 + int(i / cols) * (chh + 6), cw, chh)
		_locked_card(r, _card(LOCKED[i]), LOCKED[i] == "mizuki")
		if LOCKED[i] == "mizuki":
			UI.btab(self, font, r.position + Vector2(r.size.x - 28, -6), "意向", UI.VIOLET, 8)
	# 右：名字块 + 技能（未解锁也能翻看，docs/124 §3.2）
	var pr := Rect2(W - (230 if phone else 400), (38 if phone else 70), (220 if phone else 384), (232 if phone else 470))
	UI.bpanel(self, pr, true)
	var p := pr.position + Vector2(14, 22)
	var yy := _name_block(p, "No.01  //  特种" if phone else "No.01  //  特种  //  SPECIALIST", od.name, od.en, UI.PURPLE, [["特种", UI.PURPLE], ["近战", UI.STEEL]], 24 if phone else 34)
	_label(Vector2(p.x, yy + 12), "SKILL", "技能")
	var sk: Array = od.def.get("skills", [])
	for i in mini(3, sk.size()):
		var s: Dictionary = sk[i]
		var r := Rect2(pr.position.x + 10, yy + 20 + i * (30 if phone else 52), pr.size.x - 20, (26 if phone else 46))
		UI.bpanel(self, r)
		UI.text_at(self, font, r.position + Vector2(10, r.size.y / 2.0), "S%d  %s" % [i + 1, s.get("name", "")], 11 if phone else 14, UI.TEXT, "lm", true)
		if not phone:
			UI.en(self, font, r.position + Vector2(r.size.x - 130, 28), str(s.get("en", "")).to_upper(), 8, UI.fa(UI.B_SUB, 0.7), 2.0)
	if not phone:
		UI.text_at(self, font, Vector2(pr.position.x + 14, pr.end.y - 18), "立绘在解锁后显示 · 档案可在图鉴里翻看", 11, UI.B_SUB, "lm")
	var br := Rect2(W - (182 if phone else 300), H - (64 if phone else 84), (168 if phone else 280), (56 if phone else 72))
	UI.deploy_button(self, font, br, "使用人事调度函  ›", "" if phone else "ENTER  ·  水月 加入名册", 0.6, 0.0, 15 if phone else 20)


func _hunt_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	UI.ghost_name(self, font, Vector2(40 if not phone else 20, 64 if not phone else 34), "HEADHUNT RESULT", 1.0, 110 if not phone else 56)
	_topbar(W, "HEADHUNTING", "寻访结果", "3 名干员已加入名册", "名册 9 / 19 · 按职业排列", [["新职业 ×2", GOLD_T]])
	var ids := ["irene", "lumen", "gladiia"]
	var tiers := ["cyan", "gold", "cyan"]
	var src := ["人事调度函", "寻访凭证", "招募券"]
	var n := ids.size()
	var cw := 120.0 if phone else 190.0
	var ch := 222.0 if phone else 400.0
	var gap := 12.0 if phone else 24.0
	var x0 := W / 2.0 - (n * cw + (n - 1) * gap) / 2.0
	var y0 := 40.0 if phone else 96.0
	for i in n:
		var od := _card(ids[i])
		var r := Rect2(x0 + i * (cw + gap), y0, cw, ch)
		var tc := GOLD_T if tiers[i] == "gold" else Color8(96, 224, 232)
		UI.bpanel(self, r, tiers[i] == "gold", tiers[i] == "gold", 1.0, tc)
		# 卡内职业色斜带（class_band 缩影）
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(r.size.x * 0.38, 4), r.position + Vector2(r.size.x * 0.72, 4), r.position + Vector2(r.size.x * 0.48, r.size.y - 1), r.position + Vector2(r.size.x * 0.14, r.size.y - 1)]), UI.fa(od.col, 0.22))
		draw_rect(Rect2(r.position.x + 4, r.position.y + 2, r.size.x - 8, 3), tc)
		var foot := Vector2(r.get_center().x, r.end.y - (66 if phone else 116))
		_figure(od, foot, 2.0 if phone else 3.0, Color(0, 0, 0, 0), 0, true, r.grow(-2.0))
		UI.en(self, font, r.position + Vector2(10, 22), "NEW", 10 if phone else 12, tc, 3.0)
		UI.class_glyph(self, od.cls, Vector2(r.end.x - 16, r.position.y + 18), 6.0, od.col, 1.6)
		var ny := r.end.y - (54 if phone else 96)
		UI.text_at(self, font, Vector2(r.position.x + 12, ny + 14), od.name, 16 if phone else 26, UI.TEXT, "lm", true)
		UI.en(self, font, Vector2(r.position.x + 12, ny + (32 if phone else 46)), od.en, 7 if phone else 10, od.col, 3.0, true)
		UI.text_at(self, font, Vector2(r.position.x + 12, ny + (45 if phone else 74)), "%s · %s" % [od.cls, src[i]], 9 if phone else 11, UI.B_SUB, "lm")
	var by := H - (48 if phone else 86)
	if phone:
		_btn(Rect2(W / 2.0 - 190, by + 4, 150, 40), "设定意向")
		UI.deploy_button(self, font, Rect2(W / 2.0 - 20, by - 6, 210, 50), "前往选人  ›", "", 0.6, 0.0, 16)
	else:
		_btn(Rect2(W / 2.0 - 330, by + 18, 160, 38), "设定意向", "W")
		_btn(Rect2(W / 2.0 - 160, by + 18, 140, 38), "完成", "Esc")
		UI.deploy_button(self, font, Rect2(W / 2.0 + 10, by, 300, 72), "前往选人  ›", "ENTER  ·  新干员可选为队长", 0.6, 0.0, 22)


# ================================================================ 方向 B：图鉴 C4′ 系（黑白灰 + 浅色档案面板 + 平行四边形页签 + 警示条 + 警示黄）
# A 是选人 B+ 系；B 把图鉴的语言推到结算 / 寻访（docs/125 §4.3）。黄目前只许图鉴用（docs/37 §2），选 B 要用户放宽这条

func _b_backdrop(dsz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, dsz), UI.C_D_BG)
	var y := 0.0
	while y < dsz.y:
		draw_line(Vector2(0, y), Vector2(dsz.x, y), Color(1, 1, 1, 0.025), 1.0)
		y += 24.0
	var x := 0.0
	while x < dsz.x:
		draw_line(Vector2(x, 0), Vector2(x, dsz.y), Color(1, 1, 1, 0.025), 1.0)
		x += 24.0


## 顶栏（图鉴式）：左上浅色标题块 + 警示条 + 说明 + 平行四边形返回键
func _b_top(W: float, en: String, cn: String, sub: String, back := "返回  Esc") -> void:
	var h := 32.0 if phone else 48.0
	draw_rect(Rect2(0, 0, W, h), Color(0.04, 0.043, 0.05, 0.92))
	var bw := 96.0 if phone else 132.0
	draw_rect(Rect2(0, 0, bw, h), UI.C_L_GLASS)
	UI.code(self, font, Vector2(10, 5 if phone else 7), en, 7 if phone else 8, UI.C_L_SUB)
	UI.text_at(self, font, Vector2(10, h * 0.62), cn, 13 if phone else 18, UI.C_L_INK, "lm", true)
	UI.hazard(self, Rect2(bw, 0, 14 if phone else 22, h))
	if not phone:
		UI.text_at(self, font, Vector2(bw + 40, h / 2.0), sub, 12, UI.C_D_SUB, "lm")
	var bk := Rect2(W - (66 if phone else 120), (5 if phone else 10), (56 if phone else 104), (22 if phone else 28))
	UI.para(self, bk, 8.0, UI.C_D_PANEL, UI.C_D_INK)
	UI.text_at(self, font, bk.get_center(), back.split(" ")[0] if phone else back, 11 if phone else 12, UI.C_D_INK, "mm")


## 浅色档案面板（图鉴右侧磨砂面板同色）+ 左边一道斜切
func _b_glass(r: Rect2, cut := 28.0) -> void:
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), UI.C_L_GLASS)


func _b_head(p: Vector2, en: String, cn: String) -> void:
	UI.code(self, font, p, en + "  //  " + cn, 8 if phone else 9, UI.C_L_SUB)


## 暗场名字块（图鉴舞台式：No.xx // 分类 + 大字 + 英文 + 墨色标签片）
func _b_name(p: Vector2, code: String, cn: String, en: String, tags: Array, size := 48) -> float:
	UI.code(self, font, p, code, 9 if phone else 10, UI.C_D_SUB)
	UI.text_at(self, font, p + Vector2(-2, 8), cn, size, UI.C_D_INK, "la", true)
	var ey := p.y + 8 + size * 1.5
	UI.en(self, font, Vector2(p.x + 2, ey + 4), en, maxi(9, int(size * 0.28)), UI.C_D_SUB, 5.0)
	var px := p.x
	for tg in tags:
		px += UI.ctag(self, font, Vector2(px, ey + 14), tg, 10 if phone else 11, true)
	return ey + 44


func _b_btn(r: Rect2, s: String, main := false) -> void:
	UI.para(self, r, 10.0, UI.C_ACC if main else UI.C_D_PANEL, Color(0, 0, 0, 0) if main else UI.C_D_INK)
	var sz := (20 if not phone else 15) if main else (13 if not phone else 12)
	UI.text_at(self, font, r.get_center(), s, sz, UI.C_L_INK if main else UI.C_D_INK, "mm", main)


func _b_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var lead := _card("mizuki")
	var gp := 0.62 if not phone else 0.6
	_b_glass(Rect2(W * gp, 0, W * (1.0 - gp), H), 60.0 if not phone else 34.0)
	UI.c_band(self, H, W * (0.28 if not phone else 0.2), W * 0.16, W * 0.16, lead.col, Color(0, 0, 0, 0), 1.0, 0.6, Vector2(W * 0.2, 12 if not phone else 8))
	UI.ghost_name(self, font, Vector2(W * 0.02, H * 0.14), "PRECIOUS DAYS", 1.0, 120 if not phone else 60, UI.C_D_GHOST, 2)
	_figure(lead, Vector2(W * 0.42, H * 0.86), 5.0 if not phone else 3.0, Color(0, 0, 0, 0), 0, false)
	_b_top(W, "OPERATION REPORT", "作战记录", "潮位 8 · 漫灌 · 结算系数 ×1.4   ·   SEED 7F3A-21C9")
	var y := _b_name(Vector2(24 if phone else 40, 50 if phone else 80), "No.01  //  ENDING 01", "探索完成", "OPERATION COMPLETE", ["平凡即是喜乐", "首次达成"], 30 if phone else 54)
	var bx := 24.0 if phone else 40.0
	for it in [["10:24", "探索时间"], ["1,284", "击杀"], ["3", "Boss"]]:
		UI.text_at(self, font, Vector2(bx, y), it[0], 18 if phone else 30, UI.C_D_INK, "la", true)
		UI.text_at(self, font, Vector2(bx, y + (24 if phone else 40)), it[1], 9 if phone else 11, UI.C_D_SUB)
		bx += 64.0 if phone else 104.0
	# 右：档案面板（页签 + 计分表 + 收获）
	var px := W * gp + (76.0 if not phone else 42.0)
	var pw := W - px - (16.0 if phone else 24.0)
	var ty := 40.0 if phone else 64.0
	UI.c_tabs(self, font, Rect2(px, ty, pw, 24 if phone else 34), ["结算", "数据", "藏品"], 0.0, 8.0, 11 if phone else 13)
	var ry := ty + (40.0 if phone else 60.0)
	_b_head(Vector2(px, ry - (14 if phone else 18)), "OPERATION SCORE", "探索评分")
	for row in SCORE:
		UI.text_at(self, font, Vector2(px, ry), row[0], 10 if phone else 13, UI.C_L_INK, "lm")
		if not phone:
			UI.text_at(self, font, Vector2(px + pw - 70, ry), row[2], 11, UI.C_L_SUB, "rm")
		UI.text_at(self, font, Vector2(px + pw, ry), row[3], 11 if phone else 15, UI.C_L_INK, "rm", true)
		draw_line(Vector2(px, ry + (8 if phone else 13)), Vector2(px + pw, ry + (8 if phone else 13)), Color(0, 0, 0, 0.12), 1.0)
		ry += 16.0 if phone else 28.0
	draw_rect(Rect2(px, ry - (4 if phone else 6), pw, 2), UI.C_L_INK)
	UI.text_at(self, font, Vector2(px, ry + (6 if phone else 10)), "(200 × 潮位 8 ×1.4 + 40) ÷ 8", 9 if phone else 12, UI.C_L_SUB, "lm")
	UI.text_at(self, font, Vector2(px + pw, ry + (6 if phone else 10)), "= 40", 12 if phone else 16, UI.C_L_INK, "rm", true)
	ry += 20.0 if phone else 40.0
	_b_head(Vector2(px, ry), "OUTCOME", "局外收获")
	ry += 6.0 if phone else 10.0
	var cr := Rect2(px, ry, pw, 40 if phone else 70)
	UI.cpanel(self, cr, true)
	UI.text_at(self, font, cr.position + Vector2(12, cr.size.y / 2.0), "+53", 20 if phone else 34, UI.C_L_INK, "lm", true)
	UI.text_at(self, font, cr.position + Vector2(64 if phone else 100, cr.size.y * 0.32), "生机细胞", 10 if phone else 13, UI.C_L_INK, "lm", true)
	UI.text_at(self, font, cr.position + Vector2(64 if phone else 100, cr.size.y * 0.72), "评分 +40 · 首通赏金 +13", 8 if phone else 11, UI.C_L_SUB, "lm")
	ry += cr.size.y + (5 if phone else 10)
	for i in 3:
		var tw := (pw - 12.0) / 3.0
		var tr := Rect2(px + i * (tw + 6), ry, tw, 30 if phone else 52)
		UI.cpanel(self, tr)
		draw_rect(Rect2(tr.position, Vector2(tr.size.x, 3)), TICKET[i][2].darkened(0.3))
		UI.text_at(self, font, tr.position + Vector2(6, tr.size.y * 0.42), TICKET[i][0], 8 if phone else 12, UI.C_L_INK, "lm", true)
		if not phone:
			UI.text_at(self, font, tr.position + Vector2(8, 38), ["每次结算", "通关", "首通潮位 8"][i], 9, UI.C_L_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 6, tr.position.y + tr.size.y * (0.72 if phone else 0.42)), "×1", 10 if phone else 16, UI.C_L_INK, "rm", true)
	var by := H - (42 if phone else 78)
	_b_btn(Rect2(px - 20, by, pw * 0.36, 34 if phone else 54), "再次探索")
	_b_btn(Rect2(px - 20 + pw * 0.38, by, pw * 0.64 + 20, 34 if phone else 54), "前往寻访  ›", true)
	UI.hazard(self, Rect2(0, H - 8, W * gp - 20, 8))


func _b_hunt(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var wish := _card("mizuki")
	var gp := 0.64 if not phone else 0.62
	_b_glass(Rect2(W * gp, 0, W * (1.0 - gp), H), 60.0 if not phone else 34.0)
	UI.c_band(self, H, W * 0.26, W * 0.16, W * 0.16, wish.col, Color(0, 0, 0, 0), 1.0, 0.6, Vector2(W * 0.2, 12 if not phone else 8))
	UI.ghost_name(self, font, Vector2(W * 0.02, H * 0.12), "HEADHUNTING", 1.0, 120 if not phone else 60, UI.C_D_GHOST, 2)
	if not phone:
		_figure(_card("skadi"), Vector2(W * 0.3, H * 0.74), 3.0, Color(0.16, 0.17, 0.2), 0, false)
		_figure(_card("kaltsit"), Vector2(W * 0.56, H * 0.74), 3.0, Color(0.16, 0.17, 0.2), 0, false)
	_figure(wish, Vector2(W * 0.44, H * 0.84), 5.0 if not phone else 3.0, Color(0.24, 0.26, 0.31), 0, false)
	_b_top(W, "HEADHUNTING", "寻访", "常驻寻访 · 罗德岛人事档案 · 未解锁 13 名 · 不会重复")
	var y := _b_name(Vector2(24 if phone else 40, 50 if phone else 80), "PREFERRED  //  意向干员", "水月", "MIZUKI", ["特种", "未解锁"], 30 if phone else 50)
	for i in 3:
		UI.para(self, Rect2((24 if phone else 40) + i * (34 if phone else 50), y, 30 if phone else 44, 10), 4.0, UI.C_ACC if i < 2 else Color(0, 0, 0, 0), UI.C_ACC)
	UI.text_at(self, font, Vector2(24 if phone else 40, y + (26 if phone else 34)), "再寻访 1 次，必定获得 水月", 11 if phone else 16, UI.C_D_INK, "lm", true)
	var px := W * gp + (76.0 if not phone else 42.0)
	var pw := W - px - (16.0 if phone else 24.0)
	var ry := 48.0 if phone else 80.0
	_b_head(Vector2(px, ry), "TICKETS", "持有")
	ry += 8.0
	for i in 3:
		var tr := Rect2(px, ry + i * (44 if phone else 74), pw, 38 if phone else 64)
		UI.cpanel(self, tr, i == 0)
		draw_rect(Rect2(tr.position + Vector2(4 if i == 0 else 0, 0), Vector2(3, tr.size.y)), TICKET[i][2].darkened(0.3))
		UI.text_at(self, font, tr.position + Vector2(14, tr.size.y * 0.36), TICKET[i][0], 12 if phone else 16, UI.C_L_INK, "lm", true)
		UI.text_at(self, font, tr.position + Vector2(14, tr.size.y * 0.72), ["随机 1 名 · 计入保底", "选职业 · 随机 1 名", "指定 1 名"][i], 9 if phone else 11, UI.C_L_SUB, "lm")
		UI.text_at(self, font, Vector2(tr.end.x - 10, tr.get_center().y), "×%d" % [2, 1, 0][i], 16 if phone else 26, UI.C_L_INK, "rm", true)
	if not phone:
		var rr := ry + 3 * 74 + 10
		_b_head(Vector2(px, rr), "RULES", "规则")
		for j in 3:
			UI.text_at(self, font, Vector2(px, rr + 20 + j * 20), "· " + ["未解锁干员 13 名，不会抽到重复干员", "首次寻访必定获得医疗干员", "名册已满后，券换成生机细胞"][j], 11, UI.C_L_SUB, "lm")
	var by := H - (42 if phone else 78)
	_b_btn(Rect2(px - 20, by, pw * 0.38, 34 if phone else 54), "寻访一次")
	_b_btn(Rect2(px - 20 + pw * 0.4, by, pw * 0.62 + 20, 34 if phone else 54), "全部使用  ›", true)
	UI.hazard(self, Rect2(0, H - 8, W * gp - 20, 8))


## 揭示 B：浅色底 + 墨色大字 + 职业色斜带（亮场版图鉴舞台，接近原作寻访的白底出场）
func _b_reveal(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("lumen")
	draw_rect(Rect2(Vector2.ZERO, dsz), UI.C_L_BG)
	UI.c_band(self, H, W * 0.42, W * 0.18, W * 0.18, od.col, Color(0, 0, 0, 0), 1.0, 0.75, Vector2(W * 0.22, 14 if not phone else 8), UI.C_L_INK)
	UI.ghost_name(self, font, Vector2(W * 0.3, H * 0.08), od.en, 1.0, 150 if not phone else 80, Color(0, 0, 0, 0.12), 3)
	_figure(od, Vector2(W * 0.66, H * 0.9), 6.0 if not phone else 4.0, Color(0, 0, 0, 0), 2, false)
	var p := Vector2(24 if phone else 48, H * (0.3 if phone else 0.36))
	UI.code(self, font, p, "No.10  //  MEDIC  //  HEADHUNTING 01 / 03", 9 if phone else 10, UI.C_L_SUB)
	UI.text_at(self, font, p + Vector2(-2, 8), "流明", 36 if phone else 72, UI.C_L_INK, "la", true)
	var ey := p.y + (64 if phone else 124)
	UI.en(self, font, Vector2(p.x + 2, ey), "LUMEN", 12 if phone else 20, UI.C_L_SUB, 6.0)
	var tx := p.x
	for tg in ["医疗", "新职业", "罗德岛（驻伊比利亚）"]:
		tx += UI.ctag(self, font, Vector2(tx, ey + 12), tg, 10 if phone else 12, false)
	# NEW：警示黄实底斜块
	var nr := Rect2(p.x, ey + (42 if phone else 56), 70 if phone else 104, 22 if phone else 32)
	UI.para(self, nr, 8.0, UI.C_ACC)
	UI.en(self, font, nr.position + Vector2(14, nr.size.y * 0.72), "NEW", 12 if phone else 18, UI.C_L_INK, 6.0)
	UI.text_at(self, font, Vector2(nr.end.x + 12, nr.get_center().y), "已加入名册", 11 if phone else 14, UI.C_L_INK, "lm", true)
	UI.hazard(self, Rect2(0, H - 10, W, 10))
	var bk := Rect2(W - (66 if phone else 120), (8 if phone else 14), (56 if phone else 104), (22 if phone else 28))
	UI.para(self, bk, 8.0, UI.C_L_INK)
	UI.text_at(self, font, bk.get_center(), "跳过" if phone else "跳过  Esc", 11 if phone else 12, UI.C_L_INV, "mm")


func _b_pick_class(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	_b_top(W, "RECRUITMENT PERMIT", "招募券", "选择职业：从该职业的未解锁干员里随机解锁 1 名 · 持有 ×1")
	var cols := 4
	var x0 := 14.0 if phone else 40.0
	var top := 42.0 if phone else 72.0
	var cw := (W - x0 * 2 - 10.0 * (cols - 1)) / cols
	var ch := 116.0 if phone else 232.0
	var nlock := {"先锋": 1, "近卫": 3, "重装": 0, "狙击": 1, "术师": 1, "医疗": 2, "辅助": 1, "特种": 4}
	var per := {"先锋": ["siege"], "近卫": ["skadi", "irene", "lappland"], "重装": [], "狙击": ["wisadel"], "术师": ["logos"], "医疗": ["lumen", "kaltsit"], "辅助": ["angelina"], "特种": ["mizuki", "specter_unchained", "gladiia", "skalter"]}
	for i in 8:
		var cls: String = CLASS_ORDER[i]
		var r := Rect2(x0 + (i % cols) * (cw + 10), top + int(i / cols) * (ch + 10), cw, ch)
		var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
		var dis: bool = nlock[cls] == 0
		var sel := cls == "近卫"
		UI.cpanel(self, r, sel, 0.45 if dis else 1.0)
		draw_rect(Rect2(r.position + Vector2(4 if sel else 0, 0), Vector2(r.size.x - (4 if sel else 0), 4)), UI.fa(col.darkened(0.2), 0.4 if dis else 1.0))
		UI.code(self, font, r.position + Vector2(12, 10), "%02d  //  %s" % [i + 1, CLASS_EN[cls]], 7 if phone else 9, UI.C_L_SUB)
		UI.class_glyph(self, cls, Vector2(r.end.x - (18 if phone else 28), r.position.y + (22 if phone else 34)), 8.0 if phone else 13.0, UI.fa(UI.C_L_INK, 0.35 if dis else 1.0), 2.0)
		UI.text_at(self, font, r.position + Vector2(12, 34 if phone else 50), cls, 18 if phone else 32, UI.fa(UI.C_L_INK, 0.35 if dis else 1.0), "lm", true)
		UI.text_at(self, font, Vector2(r.position.x + 12, r.end.y - 12), "已全部解锁" if dis else "未解锁 %d 名" % nlock[cls], 10 if phone else 12, UI.C_L_SUB, "lm")
		var sx := r.position.x + 10
		for cid in per[cls]:
			var od := _card(cid)
			var cell := Rect2(sx, r.position.y + (50 if phone else 82), (24 if phone else 60), (44 if phone else 120))
			var tx: Texture2D = od.tex
			if tx != null:
				var fw: float = tx.get_width() / float(maxi(1, int(od.frames)))
				var bb: Rect2 = UI.card_bb(od, tx)
				var pl := UI.card_place(cell, fw, tx.get_height(), od.hires, bb, 0.0, float(od.ds))
				UI.blit_clipped(self, A.white_of(tx), pl, Rect2(bb.position, bb.size), cell, UI.fa(UI.C_L_INK, 0.75 if sel else 0.35))
			sx += cell.size.x + 4
	_b_btn(Rect2(W - (200 if phone else 330), H - (44 if phone else 80), (186 if phone else 300), (34 if phone else 56)), "使用招募券 · 近卫  ›", true)
	UI.hazard(self, Rect2(0, H - 8, W - (220 if phone else 360), 8))


func _b_pick_letter(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("mizuki")
	var gp := 0.64 if not phone else 0.62
	_b_glass(Rect2(W * gp, 0, W * (1.0 - gp), H), 60.0 if not phone else 34.0)
	UI.c_band(self, H, W * 0.36, W * 0.14, W * 0.14, od.col, Color(0, 0, 0, 0), 1.0, 0.6, Vector2(W * 0.18, 12 if not phone else 8))
	UI.ghost_name(self, font, Vector2(W * 0.3, H * 0.12), od.en, 1.0, 130 if not phone else 64, UI.C_D_GHOST, 2)
	_figure(od, Vector2(W * 0.5, H * 0.86), 5.0 if not phone else 3.0, Color(0.24, 0.26, 0.31), 0, false)
	_b_top(W, "TRANSFER ORDER", "人事调度函", "选择 1 名未解锁干员直接加入名册 · 立绘在解锁后显示")
	var cols := 3
	var cw := 50.0 if phone else 78.0
	var chh := 66.0 if phone else 100.0
	for i in mini(LOCKED.size(), 9 if phone else 12):
		var r := Rect2((10 if phone else 32) + (i % cols) * (cw + 6), (40 if phone else 66) + int(i / cols) * (chh + 6), cw, chh)
		_locked_card(r, _card(LOCKED[i]), LOCKED[i] == "mizuki")
	var px := W * gp + (76.0 if not phone else 42.0)
	var pw := W - px - (16.0 if phone else 24.0)
	var ry := 46.0 if phone else 76.0
	UI.code(self, font, Vector2(px, ry), "No.01  //  SPECIALIST", 8 if phone else 10, UI.C_L_SUB)
	UI.text_at(self, font, Vector2(px - 2, ry + 6), od.name, 26 if phone else 48, UI.C_L_INK, "la", true)
	UI.en(self, font, Vector2(px, ry + (48 if phone else 86)), od.en, 9 if phone else 14, UI.C_L_SUB, 5.0)
	var tx := px
	for tg in ["特种", "近战", "意向干员"]:
		tx += UI.ctag(self, font, Vector2(tx, ry + (54 if phone else 96)), tg, 9 if phone else 11, false)
	ry += 82.0 if phone else 138.0
	UI.code(self, font, Vector2(px, ry), "SKILL  //  技能", 8 if phone else 9, UI.C_L_SUB)
	var sk: Array = od.def.get("skills", [])
	for i in mini(3, sk.size()):
		var r := Rect2(px, ry + 8 + i * (28 if phone else 52), pw, 24 if phone else 44)
		UI.cpanel(self, r)
		UI.text_at(self, font, r.position + Vector2(10, r.size.y / 2.0), "S%d  %s" % [i + 1, sk[i].get("name", "")], 11 if phone else 15, UI.C_L_INK, "lm", true)
	var by := H - (42 if phone else 78)
	_b_btn(Rect2(px - 20, by, pw + 20, 34 if phone else 54), "使用人事调度函  ›", true)
	UI.hazard(self, Rect2(0, H - 8, W * gp - 20, 8))


## 寻访结果 B：原作十连式斜切竖条（条里裁切立绘，顶边档位色，NEW 斜块，名字压在条底）
func _b_hunt_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	_b_top(W, "HEADHUNTING", "寻访结果", "3 名干员已加入名册 · 名册 9 / 19 · 按职业排列")
	var ids := ["irene", "lumen", "gladiia"]
	var tiers := ["cyan", "gold", "cyan"]
	var n := ids.size()
	var sw := 140.0 if phone else 220.0
	var sk := 30.0 if phone else 50.0
	var x0 := W / 2.0 - (n * sw - (n - 1) * 6.0) / 2.0
	var top := 40.0 if phone else 64.0
	var bot := H - (54 if phone else 96)
	for i in n:
		var od := _card(ids[i])
		var x := x0 + i * (sw - 6.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x + sk, top), Vector2(x + sw, top), Vector2(x + sw - sk, bot), Vector2(x, bot)]), UI.C_D_CARD)
		var tc := UI.C_ACC if tiers[i] == "gold" else Color8(200, 255, 255)
		draw_colored_polygon(PackedVector2Array([Vector2(x + sk, top), Vector2(x + sw, top), Vector2(x + sw - 2, top + 8), Vector2(x + sk - 2, top + 8)]), tc)
		var clip := Rect2(x + sk * 0.5, top + 8, sw - sk, bot - top - 8)
		_figure(od, Vector2(x + sw / 2.0, bot - (50 if phone else 90)), 3.0 if phone else 5.0, Color(0, 0, 0, 0), 0, false, clip)
		draw_rect(Rect2(x + 4, bot - (44 if phone else 76), sw - 14, (44 if phone else 76)), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(x + 4, bot - (44 if phone else 76), 4, (44 if phone else 76)), od.col)
		UI.text_at(self, font, Vector2(x + 14, bot - (26 if phone else 46)), od.name, 15 if phone else 26, UI.C_D_INK, "lm", true)
		UI.en(self, font, Vector2(x + 14, bot - (8 if phone else 14)), od.en, 7 if phone else 10, UI.C_D_SUB, 3.0)
		var nr := Rect2(x + sk + 6, top + 14, 50 if phone else 70, 16 if phone else 22)
		UI.para(self, nr, 5.0, tc)
		UI.en(self, font, nr.position + Vector2(10, nr.size.y * 0.75), "NEW", 9 if phone else 12, UI.C_L_INK, 4.0)
	var by := H - (42 if phone else 78)
	_b_btn(Rect2(W / 2.0 - (180 if phone else 300), by, (150 if phone else 240), 34 if phone else 54), "设定意向")
	_b_btn(Rect2(W / 2.0 - (20 if phone else 40), by, (200 if phone else 340), 34 if phone else 54), "前往选人  ›", true)
	UI.hazard(self, Rect2(0, H - 8, W, 8))


# ================================================================ 第二版（10-22 用户：「同质化严重」→ 同一系统、不同主体）
# 每屏一个主导元素、一种版式，不共用骨架；强调色、左右重心、字号层级、动效每屏不同（docs/125 §4.5）。只出桌面。
# 共同的只有底层语言：B+ 的深色底与职业色、像素整数倍立绘、中英混排与编号、角括号框角（docs/125 S4）

const V2_INK := Color(0.05, 0.06, 0.08)
const V2_PAPER := Color(0.93, 0.92, 0.88)
const V2_STAMP := Color(0.78, 0.16, 0.22)


func _v2(dsz: Vector2) -> void:
	match which:
		"result_v2":
			_v2_result(dsz)
		"hunt_v2":
			_v2_hunt(dsz)
		"pick_class_v2":
			_v2_pick_class(dsz)
		"pick_letter_v2":
			_v2_pick_letter(dsz)
		"reveal_v2":
			_v2_reveal(dsz)
		"hunt_result_v2":
			_v2_hunt_result(dsz)


## 角括号（⌐ ¬ 四角，像素阶梯）：框不画全，只画四个角
func _brackets(r: Rect2, col: Color, l := 14.0, w := 2.0) -> void:
	for c in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
		var p: Vector2 = c[0]
		draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -l, 0 if c[2] > 0 else -w), Vector2(l, w)), col)
		draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -w, 0 if c[2] > 0 else -l), Vector2(w, l)), col)


## 双色巨型英文（S1）：前半实色、后半描边
func _twotone(p: Vector2, s: String, size: int, solid: Color, line: Color, split := 0.5) -> void:
	var n := int(round(s.length() * split))
	var a := s.substr(0, n)
	draw_string(font, p + Vector2(0, font.get_ascent(size)), a, HORIZONTAL_ALIGNMENT_LEFT, -1, size, solid)
	var w := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, p + Vector2(w, font.get_ascent(size)), s.substr(n), HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, line)


## 动效标注（样张里说明这一屏的招牌动作，实装时去掉）
func _motion_tag(W: float, s: String) -> void:
	var w := UI.cwidth(font, s, 10) + 20
	draw_rect(Rect2(W - w - 12, 8, w, 20), Color(0, 0, 0, 0.55))
	UI.text_at(self, font, Vector2(W - w - 2, 18), s, 10, Color(1, 1, 1, 0.8), "lm")


# ---- 1 结算 = 作战报告：评级大字 + 数据表与条形读数 + 底部获得物资条；重心在右；强调白 + 青；横滑
func _v2_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	draw_rect(Rect2(Vector2.ZERO, dsz), Color(0.035, 0.04, 0.05))
	var lead := _card("mizuki")
	# 左：队长站在一块暗斜板上，脚底出画面下缘
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(440, 0), Vector2(320, H), Vector2(0, H)]), Color(0.07, 0.085, 0.11))
	draw_colored_polygon(PackedVector2Array([Vector2(440, 0), Vector2(452, 0), Vector2(332, H), Vector2(320, H)]), UI.fa(lead.col, 0.8))
	_figure(lead, Vector2(210, H - 70), 6.0, Color(0, 0, 0, 0), 0, false)
	# 队长读数（作战记录 run_stats：伤害占比 / 参与击杀 / 等级与精英阶段）
	draw_rect(Rect2(0, H - 64, 330, 64), Color(0, 0, 0, 0.55))
	UI.btab(self, font, Vector2(24, H - 56), "队长", UI.VIOLET, 9)
	UI.text_at(self, font, Vector2(64, H - 49), "水月", 15, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(24, H - 24), "伤害 46%  ·  参与击杀 590  ·  Lv.24 精二", 11, UI.fa(UI.TEXT, 0.85), "lm")
	draw_rect(Rect2(24, H - 10, 280, 3), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(24, H - 10, 280 * 0.46, 3), lead.col)
	UI.code(self, font, Vector2(24, 20), "OPERATION REPORT  //  ENDING 01  //  潮位 8", 9, UI.fa(UI.TEXT, 0.6))
	# 评级大字（描边）+ 结果
	draw_string_outline(font, Vector2(470, 40 + font.get_ascent(220)), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 220, 4, UI.fa(UI.TEXT, 0.9))
	UI.code(self, font, Vector2(476, 318), "RATING  //  评级", 9, UI.fa(UI.TEXT, 0.6))
	UI.text_at(self, font, Vector2(660, 64), "探索完成", 44, UI.TEXT, "la", true)
	UI.en(self, font, Vector2(644, 140), "OPERATION COMPLETE", 13, UI.B_ACC, 6.0)
	UI.text_at(self, font, Vector2(640, 158), "结局一 · 平凡即是喜乐", 15, UI.fa(UI.TEXT, 0.85))
	UI.text_at(self, font, Vector2(640, 182), "泡影散了。水月回到岸上，准备好好吃一顿，迎接明天。", 11, UI.B_SUB)
	# 数据表：项目 / 数值 / 条形读数（长条）
	var rows := [["探索时间", "10:24", 1.0], ["击杀", "1,284", 0.86], ["精英击杀", "23", 0.55], ["Boss 击破", "3 / 3", 1.0], ["造成伤害", "412,880", 0.92], ["受到的伤害", "1,206", 0.18]]
	var ty := 222.0
	draw_line(Vector2(640, ty - 8), Vector2(W - 40, ty - 8), UI.fa(UI.TEXT, 0.5), 1.0)
	for i in rows.size():
		var y := ty + i * 24
		var sl := 0.0 if i < 4 else (14.0 if i == 4 else 30.0)   # 横滑：后两行还在滑入
		UI.text_at(self, font, Vector2(640 + sl, y + 10), rows[i][0], 12, UI.fa(UI.TEXT, 0.75 if sl == 0.0 else 0.4), "lm")
		draw_rect(Rect2(760 + sl, y + 8, 300, 4), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(760 + sl, y + 8, 300 * rows[i][2], 4), UI.fa(UI.B_ACC, 0.9 if sl == 0.0 else 0.35))
		UI.text_at(self, font, Vector2(W - 40 + sl, y + 10), rows[i][1], 16, UI.fa(UI.TEXT, 1.0 if sl == 0.0 else 0.4), "rm", true)
	# 计分 → 系数 → 生机细胞
	var sy := ty + rows.size() * 24 + 6
	draw_line(Vector2(640, sy), Vector2(W - 40, sy), UI.fa(UI.TEXT, 0.5), 1.0)
	UI.text_at(self, font, Vector2(640, sy + 18), "探索评分  存活 100 + 中期 Boss 40 + 通关 60  =  200   × 潮位 8  ×1.4   + 结局首达 40   ÷ 8", 11, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(W - 40, sy + 18), "40", 16, UI.TEXT, "rm", true)
	# 本局编队：队友小像（3 倍，出卡框上缘）+ 一行读数；换下的灰显「已撤退」，本局新解锁的标 NEW（队长在左侧大立绘）
	var mates := [["lumen", "伤害 21%  ·  击杀 312", "Lv.18 精一", 0.21, "new"], ["skadi", "伤害 27%  ·  击杀 361", "Lv.16 精一", 0.27, ""],
		["exusiai", "伤害 6%  ·  击杀 21", "Lv.9 精零", 0.06, "out"]]
	var qy := sy + 38.0
	UI.code(self, font, Vector2(640, qy), "SQUAD  //  本局编队 · 队友", 9, UI.fa(UI.TEXT, 0.6))
	for i in mates.size():
		var od := _card(mates[i][0])
		var out: bool = mates[i][4] == "out"
		var r := Rect2(640 + i * 204, qy + 60, 192, 64)
		draw_rect(r, Color(0.07, 0.08, 0.1, 0.9))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), UI.fa(od.col, 0.35 if out else 1.0))
		_figure(od, Vector2(r.position.x + 34, r.end.y - 6), 1.0, Color(0.22, 0.23, 0.27) if out else Color(0, 0, 0, 0), 0, false)
		UI.text_at(self, font, r.position + Vector2(72, 16), od.name, 14, UI.fa(UI.TEXT, 0.45 if out else 1.0), "lm", true)
		UI.text_at(self, font, r.position + Vector2(72, 36), mates[i][1], 10, UI.fa(UI.TEXT, 0.45 if out else 0.85), "lm")
		UI.text_at(self, font, r.position + Vector2(72, 52), mates[i][2], 10, UI.fa(UI.B_SUB, 0.6 if out else 1.0), "lm")
		draw_rect(Rect2(r.position.x + 72, r.end.y - 4, r.size.x - 84, 2), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(r.position.x + 72, r.end.y - 4, (r.size.x - 84) * mates[i][3], 2), UI.fa(od.col, 0.4 if out else 1.0))
		if mates[i][4] == "new":
			UI.para(self, Rect2(r.end.x - 52, r.position.y + 6, 44, 16), 4.0, Color8(255, 196, 80))
			UI.en(self, font, Vector2(r.end.x - 42, r.position.y + 18), "NEW", 9, V2_INK, 3.0)
		elif out:
			UI.btab(self, font, Vector2(r.end.x - 56, r.position.y + 6), "已撤退", Color(0.3, 0.32, 0.36), 9)
	# 底部：获得物资条（原作结算的一排奖励，带光圈 + 分类小标签）
	draw_rect(Rect2(332, H - 150, W - 332, 150), Color(0, 0, 0, 0.45))
	UI.code(self, font, Vector2(372, H - 136), "REWARDS  //  获得", 9, UI.fa(UI.TEXT, 0.6))
	var items := [["生机细胞", "+53", UI.GREEN, "常规 + 首通"], ["寻访凭证", "×1", TICKET[0][2], "每次结算"], ["招募券", "×1", TICKET[1][2], "通关"], ["人事调度函", "×1", TICKET[2][2], "首通"]]
	for i in items.size():
		var c := Vector2(420 + i * 150, H - 76)
		_halo(c, 40, items[i][2])
		if i == 0:
			draw_circle(c, 16, UI.fa(UI.GREEN, 0.9))
			draw_circle(c, 9, Color(0.75, 1.0, 0.9))
		else:
			_ticket_icon(c, 1.6, items[i][2])
		UI.text_at(self, font, c + Vector2(44, -14), items[i][1], 20, UI.TEXT, "lm", true)
		UI.text_at(self, font, c + Vector2(44, 10), items[i][0], 11, UI.fa(UI.TEXT, 0.8), "lm")
		UI.btab(self, font, c + Vector2(-34, 30), items[i][3], Color(0.2, 0.24, 0.3), 8)
	UI.deploy_button(self, font, Rect2(W - 240, H - 112, 210, 64), "前往寻访  ›", "ENTER", 0.6, 0.0, 20)
	UI.text_at(self, font, Vector2(W - 135, H - 30), "R 再次探索  ·  T 回到标题  ·  Tab 作战记录", 10, UI.B_SUB, "ma")
	_motion_tag(W, "动效：数据行自右横滑入 · 读数条拉长 · 奖励逐个落下")


# ---- 2 寻访入口 = 卡池海报：双色巨型英文 + 大剪影出框 + 凭证角标；重心在中右；强调紫；视差缓移
func _v2_hunt(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var wish := _card("mizuki")
	draw_rect(Rect2(Vector2.ZERO, dsz), Color(0.06, 0.05, 0.12))
	# 主题色只铺大斜块（S3）
	draw_colored_polygon(PackedVector2Array([Vector2(520, 0), Vector2(W, 0), Vector2(W, H), Vector2(300, H)]), UI.fa(UI.VIOLET, 0.55))
	draw_colored_polygon(PackedVector2Array([Vector2(700, 0), Vector2(760, 0), Vector2(540, H), Vector2(480, H)]), UI.fa(UI.PURPLE, 0.35))
	for i in 6:
		draw_line(Vector2(900 + i * 34, 0), Vector2(700 + i * 34, H), Color(1, 1, 1, 0.06), 2.0)
	_twotone(Vector2(60, 196), "HEADHUNTING", 150, UI.fa(Color.WHITE, 0.92), UI.fa(Color.WHITE, 0.5), 0.45)
	# 卡池：意向干员巨型剪影（出画面上下缘），两名小剪影在后（视差）
	_figure(_card("skadi"), Vector2(560, 560), 4.0, Color(0.16, 0.12, 0.32), 0, false)
	_figure(_card("kaltsit"), Vector2(1110, 560), 4.0, Color(0.16, 0.12, 0.32), 0, false)
	_figure(wish, Vector2(830, H + 70), 9.0, Color(0.10, 0.08, 0.20), 0, false)
	# 左上：卡池名实色块（S1 的中文名块）
	draw_rect(Rect2(60, 70, 330, 56), Color.WHITE)
	UI.text_at(self, font, Vector2(76, 98), "常驻寻访", 30, V2_INK, "lm", true)
	UI.code(self, font, Vector2(214, 86), "STANDARD HEADHUNTING", 8, UI.fa(V2_INK, 0.6))
	UI.text_at(self, font, Vector2(214, 106), "罗德岛人事档案", 12, V2_INK, "lm")
	UI.code(self, font, Vector2(60, 52), "R.I. PERSONNEL  //  NO.0001", 9, UI.fa(UI.TEXT, 0.6))
	# 意向保底（原作「下次…必定为」句式）
	draw_rect(Rect2(60, 400, 6, 70), UI.VIOLET)
	UI.text_at(self, font, Vector2(80, 414), "意向干员  水月", 15, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(80, 442), "再寻访 1 次，必定获得 水月！！", 20, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(80, 466), "未解锁 13 名 · 不会重复 · 首次寻访必定获得医疗干员", 11, UI.B_SUB, "lm")
	# 右上：凭证角标（叠成一摞的票签）
	for i in 3:
		var r := Rect2(W - 214, 60 + i * 50, 190, 42)
		draw_rect(r, Color(0.04, 0.04, 0.08, 0.85))
		draw_rect(Rect2(r.position, Vector2(5, r.size.y)), TICKET[i][2])
		_ticket_icon(r.position + Vector2(30, 21), 1.0, TICKET[i][2])
		UI.text_at(self, font, r.position + Vector2(52, 21), TICKET[i][0], 13, UI.TEXT, "lm", true)
		UI.text_at(self, font, Vector2(r.end.x - 12, r.get_center().y), "×%d" % [2, 1, 0][i], 20, TICKET[i][2] if i < 2 else UI.B_SUB, "rm", true)
	# 左下：两个斜按钮
	UI.para(self, Rect2(60, H - 120, 200, 64), 18.0, Color(1, 1, 1, 0.1), Color.WHITE)
	UI.text_at(self, font, Vector2(160, H - 88), "寻访一次", 18, UI.TEXT, "mm", true)
	UI.para(self, Rect2(270, H - 120, 260, 64), 18.0, Color.WHITE)
	UI.text_at(self, font, Vector2(400, H - 96), "全部使用", 22, V2_INK, "mm", true)
	UI.code(self, font, Vector2(352, H - 80), "×3 PERMITS", 8, UI.fa(V2_INK, 0.6))
	UI.code(self, font, Vector2(60, H - 26), "© 本作同人 · 卡池里的干员在解锁前以剪影展示", 8, UI.fa(UI.TEXT, 0.4))
	_motion_tag(W, "动效：三层剪影视差缓移 · 巨型英文缓慢平移")


# ---- 3 招募券 = 调度表格：职业图标大格阵列（像编队页）+ 左侧调度栏 + 底部候选表；重心居中偏下；强调所选职业色；逐格点亮
func _v2_pick_class(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	draw_rect(Rect2(Vector2.ZERO, dsz), Color(0.05, 0.06, 0.07))
	var sel := "近卫"
	var sc: Color = Character.CLASS_COL[sel]
	# 左：调度栏（竖条，深色实底）
	draw_rect(Rect2(0, 0, 230, H), Color(0.08, 0.09, 0.11))
	draw_rect(Rect2(230, 0, 2, H), UI.fa(sc, 0.8))
	UI.code(self, font, Vector2(24, 40), "RECRUITMENT PERMIT", 9, UI.B_SUB)
	UI.text_at(self, font, Vector2(24, 76), "招募券", 32, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(24, 112), "选择一个职业，", 13, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(24, 132), "从中随机解锁 1 名干员", 13, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(24, 200), "持有", 11, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(24, 232), "×1", 40, TICKET[1][2], "lm", true)
	UI.text_at(self, font, Vector2(24, 300), "已有职业", 11, UI.B_SUB, "lm")
	UI.text_at(self, font, Vector2(24, 330), "5 / 8", 26, UI.TEXT, "lm", true)
	UI.para(self, Rect2(24, H - 90, 186, 56), 12.0, sc)
	UI.text_at(self, font, Vector2(117, H - 62), "确认 · 近卫", 18, V2_INK, "mm", true)
	# 中：2 × 4 大格阵列（每格一个职业大图标）
	var nlock := {"先锋": 1, "近卫": 3, "重装": 0, "狙击": 1, "术师": 1, "医疗": 2, "辅助": 1, "特种": 4}
	var x0 := 270.0
	var y0 := 50.0
	var cs := 236.0
	var gap := 12.0
	for i in 8:
		var cls: String = CLASS_ORDER[i]
		var col: Color = Character.CLASS_COL[cls]
		var r := Rect2(x0 + (i % 4) * (cs + gap), y0 + int(i / 4) * (196 + gap), cs, 196)
		var dis: bool = nlock[cls] == 0
		var on: bool = cls == sel
		var lit := i <= 5   # 逐格点亮：后两格还没亮
		draw_rect(r, Color(0.09, 0.10, 0.12) if not on else UI.fa(col, 0.22))
		if on:
			draw_rect(r, col, false, 3.0)
			_brackets(r.grow(8), Color.WHITE, 20, 3)
		UI.class_glyph(self, cls, r.get_center() + Vector2(0, -24), 40.0, UI.fa(col if not dis else UI.B_SUB, (1.0 if lit else 0.25) * (0.35 if dis else 1.0)), 4.0)
		UI.text_at(self, font, Vector2(r.position.x + 16, r.end.y - 24), cls, 20, UI.fa(UI.TEXT, 0.35 if dis else 1.0), "lm", true)
		UI.code(self, font, Vector2(r.position.x + 70, r.end.y - 30), CLASS_EN[cls], 8, UI.fa(col, 0.7))
		UI.text_at(self, font, Vector2(r.end.x - 14, r.end.y - 24), "已满" if dis else "%d" % nlock[cls], 22 if not dis else 12, UI.fa(UI.TEXT, 0.35 if dis else 1.0), "rm", true)
		UI.code(self, font, r.position + Vector2(12, 10), "%02d" % (i + 1), 9, UI.B_SUB)
		if ["近卫", "医疗", "特种"].has(cls):
			UI.btab(self, font, Vector2(r.end.x - 52, r.position.y + 8), "新职业", UI.VIOLET, 9)
	# 底：所选职业的候选表（剪影 + 名字隐去，表格行）
	var by := y0 + 2 * (196 + gap) + 10
	UI.code(self, font, Vector2(x0, by), "CANDIDATES  //  近卫 · 未解锁 3 名（随机 1 名）", 9, UI.B_SUB)
	for j in 3:
		var od := _card(["skadi", "irene", "lappland"][j])
		var r := Rect2(x0 + j * 330, by + 14, 320, 76)
		draw_rect(r, Color(0.08, 0.09, 0.11))
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), sc)
		_figure_mini(od, Rect2(r.position + Vector2(8, 4), Vector2(60, 68)), true)
		UI.text_at(self, font, r.position + Vector2(80, 26), "？？？", 16, UI.B_SUB, "lm", true)
		UI.code(self, font, r.position + Vector2(80, 48), "GUARD  //  CANDIDATE %02d" % (j + 1), 8, UI.B_SUB)
	_motion_tag(W, "动效：格子逐格点亮 · 选中时角括号收拢")


# ---- 4 人事调度函 = 一封公文：纵向信纸 + 印章 + 签名，大面积留白；重心正中；强调印泥红；盖章
func _v2_pick_letter(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	draw_rect(Rect2(Vector2.ZERO, dsz), Color(0.10, 0.10, 0.11))
	# 左：未解锁名单（纯文字目录）
	UI.code(self, font, Vector2(60, 60), "INDEX  //  未解锁干员", 9, UI.B_SUB)
	for i in LOCKED.size():
		var od := _card(LOCKED[i])
		var y := 90 + i * 34
		var on: bool = LOCKED[i] == "mizuki"
		if on:
			draw_rect(Rect2(52, y - 13, 200, 26), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(52, y - 13, 3, 26), V2_STAMP)
		UI.text_at(self, font, Vector2(64, y), od.name, 14, UI.TEXT if on else UI.fa(UI.TEXT, 0.55), "lm", on)
		UI.text_at(self, font, Vector2(240, y), od.cls, 10, UI.B_SUB, "rm")
	# 中：信纸
	var pr := Rect2(W / 2.0 - 230, 34, 460, H - 68)
	draw_rect(Rect2(pr.position + Vector2(8, 10), pr.size), Color(0, 0, 0, 0.35))
	draw_rect(pr, V2_PAPER)
	var ink := Color(0.12, 0.12, 0.14)
	var x := pr.position.x + 44
	UI.code(self, font, Vector2(x, pr.position.y + 34), "RHODES ISLAND  //  PERSONNEL TRANSFER ORDER", 8, UI.fa(ink, 0.6))
	UI.text_at(self, font, Vector2(x, pr.position.y + 70), "人事调度函", 30, ink, "lm", true)
	UI.text_at(self, font, Vector2(pr.end.x - 44, pr.position.y + 70), "编号 RI-PT-0042", 10, UI.fa(ink, 0.6), "rm")
	draw_rect(Rect2(x, pr.position.y + 94, pr.size.x - 88, 2), ink)
	UI.text_at(self, font, Vector2(x, pr.position.y + 136), "兹调派下列干员加入罗德岛干员名册：", 13, ink, "lm")
	UI.text_at(self, font, Vector2(x + 30, pr.position.y + 196), "水月", 46, ink, "lm", true)
	UI.en(self, font, Vector2(x + 34, pr.position.y + 236), "MIZUKI  //  SPECIALIST", 10, UI.fa(ink, 0.6), 4.0)
	draw_line(Vector2(x + 20, pr.position.y + 250), Vector2(pr.end.x - 64, pr.position.y + 250), UI.fa(ink, 0.4), 1.0)
	for j in 3:
		var yy := pr.position.y + 290 + j * 30
		UI.text_at(self, font, Vector2(x, yy), ["职业", "技能", "生效"][j], 11, UI.fa(ink, 0.6), "lm")
		UI.text_at(self, font, Vector2(x + 60, yy), ["特种 · 近战", "唤醒 / 囚徒困境 / 镜花水月", "即日起可选为队长"][j], 12, ink, "lm")
		draw_line(Vector2(x, yy + 12), Vector2(pr.end.x - 44, yy + 12), UI.fa(ink, 0.12), 1.0)
	# 签名 + 印章（大面积留白在中段）
	UI.text_at(self, font, Vector2(pr.end.x - 200, pr.end.y - 110), "签发", 11, UI.fa(ink, 0.6), "lm")
	UI.text_at(self, font, Vector2(pr.end.x - 150, pr.end.y - 112), "博士", 26, ink, "lm")
	draw_line(Vector2(pr.end.x - 156, pr.end.y - 92), Vector2(pr.end.x - 44, pr.end.y - 92), ink, 1.0)
	UI.text_at(self, font, Vector2(pr.end.x - 200, pr.end.y - 70), "1101 年 10 月 22 日", 10, UI.fa(ink, 0.6), "lm")
	var sc := Vector2(pr.end.x - 110, pr.end.y - 116)
	draw_arc(sc, 46, 0, TAU, 40, UI.fa(V2_STAMP, 0.85), 4.0)
	draw_arc(sc, 38, 0, TAU, 40, UI.fa(V2_STAMP, 0.85), 1.5)
	UI.text_at(self, font, sc + Vector2(0, -8), "人事部", 16, UI.fa(V2_STAMP, 0.9), "mm", true)
	UI.code(self, font, sc + Vector2(-28, 10), "R.I. HR DEPT.", 7, UI.fa(V2_STAMP, 0.9))
	# 右：一个小剪影 + 确认
	_figure(_card("mizuki"), Vector2(1110, 470), 3.0, Color(0.22, 0.22, 0.26), 0, false)
	UI.text_at(self, font, Vector2(1110, 500), "立绘在解锁后显示", 10, UI.B_SUB, "ma")
	UI.para(self, Rect2(1000, H - 120, 230, 60), 14.0, V2_STAMP)
	UI.text_at(self, font, Vector2(1115, H - 90), "盖章确认", 20, Color.WHITE, "mm", true)
	_motion_tag(W, "动效：信纸自下滑入 · 按确认时印章落下（盖章）")


# ---- 5 揭示 = 全屏立绘 + 大字名牌，几乎无框；重心在右；强调该干员职业色；扫描线
func _v2_reveal(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("lumen")
	var col: Color = od.col
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), dsz, Vector2(0, H)]), PackedColorArray([Color(0.95, 0.96, 0.97), Color(0.88, 0.94, 0.96), col.lerp(Color.WHITE, 0.55), Color(0.93, 0.95, 0.96)]))
	draw_colored_polygon(PackedVector2Array([Vector2(640, 0), Vector2(1000, 0), Vector2(760, H), Vector2(400, H)]), UI.fa(col, 0.5))
	for i in 5:
		draw_line(Vector2(1040 + i * 26, 0), Vector2(800 + i * 26, H), UI.fa(col, 0.35), 3.0)
	_twotone(Vector2(40, 18), "LUMEN", 230, UI.fa(V2_INK, 0.88), UI.fa(V2_INK, 0.35), 0.4)
	_figure(od, Vector2(860, H + 40), 9.0, Color(0, 0, 0, 0), 2, false)
	# 扫描线（解码进行中：画在立绘下半段）
	draw_rect(Rect2(560, 520, 600, 3), UI.fa(Color.WHITE, 0.95))
	for i in 18:
		if (i * 7) % 3 != 0:
			draw_rect(Rect2(560 + i * 34, 526 + (i % 3) * 6, 24, 6), UI.fa(col, 0.45))
	# 名牌：实色块中文名（S1）
	draw_rect(Rect2(40, 330, 300, 86), V2_INK)
	UI.text_at(self, font, Vector2(60, 373), "流明", 50, Color.WHITE, "lm", true)
	UI.code(self, font, Vector2(196, 350), "No.10 // MEDIC", 9, UI.fa(Color.WHITE, 0.6))
	UI.text_at(self, font, Vector2(196, 384), "罗德岛（驻伊比利亚）", 11, UI.fa(Color.WHITE, 0.85), "lm")
	UI.para(self, Rect2(40, 424, 150, 30), 8.0, col)
	UI.text_at(self, font, Vector2(115, 439), "医疗 · 新职业", 13, V2_INK, "mm", true)
	UI.para(self, Rect2(198, 424, 92, 30), 8.0, Color8(255, 196, 80))
	UI.en(self, font, Vector2(216, 446), "NEW", 15, V2_INK, 5.0)
	UI.code(self, font, Vector2(40, 470), "HEADHUNTING  01 / 03  //  寻访凭证", 9, UI.fa(V2_INK, 0.6))
	UI.text_at(self, font, Vector2(40, H - 36), "点击继续", 12, UI.fa(V2_INK, 0.6), "lm")
	_motion_tag(W, "动效：扫描线自上而下把剪影解码成彩色")


# ---- 6 寻访结果 = 名单卡片墙：横向证件卡排成墙，逐张翻入；重心靠下；强调档位色；卡片翻入
func _v2_hunt_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	draw_rect(Rect2(Vector2.ZERO, dsz), Color(0.07, 0.08, 0.10))
	var gy := 0.0
	while gy < H:
		draw_line(Vector2(0, gy), Vector2(W, gy), Color(1, 1, 1, 0.03), 1.0)
		gy += 32.0
	UI.code(self, font, Vector2(60, 50), "HEADHUNT RESULT  //  ROSTER UPDATE", 9, UI.B_SUB)
	UI.text_at(self, font, Vector2(60, 92), "寻访结果", 40, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(260, 98), "3 名干员已加入名册 · 名册 9 / 19", 13, UI.B_SUB, "lm")
	var ids := ["irene", "lumen", "gladiia", "", "", ""]
	var tiers := ["cyan", "gold", "cyan"]
	var src := ["人事调度函", "寻访凭证", "招募券"]
	var cw := 360.0
	var ch := 170.0
	for i in 6:
		var r := Rect2(60 + (i % 3) * (cw + 20), 150 + int(i / 3) * (ch + 20) + (i % 3) * 14, cw, ch)
		if ids[i] == "":
			_brackets(r, Color(1, 1, 1, 0.12), 16, 2)
			UI.code(self, font, r.get_center() + Vector2(-24, -4), "— EMPTY —", 8, Color(1, 1, 1, 0.18))
			continue
		var od := _card(ids[i])
		var tc := Color8(255, 196, 80) if tiers[i] == "gold" else Color8(200, 255, 255)
		var flip := 1.0 if i < 2 else 0.35   # 第 3 张正在翻入（横向压窄）
		var rr := Rect2(r.position.x + r.size.x * (1.0 - flip) / 2.0, r.position.y, r.size.x * flip, r.size.y)
		draw_rect(rr, Color(0.93, 0.94, 0.95) if flip == 1.0 else Color(0.6, 0.62, 0.66))
		if flip < 1.0:
			continue
		draw_rect(Rect2(rr.position, Vector2(140, rr.size.y)), UI.fa(od.col, 0.85))
		_figure(od, Vector2(rr.position.x + 70, rr.end.y - 10), 2.0, Color(0, 0, 0, 0), 0, false, Rect2(rr.position, Vector2(140, rr.size.y)))
		draw_rect(Rect2(rr.position.x + 140, rr.position.y, rr.size.x - 140, 6), tc)
		UI.code(self, font, rr.position + Vector2(156, 22), "No.%02d  //  %s" % [[7, 10, 17][i], CLASS_EN[od.cls]], 8, UI.fa(V2_INK, 0.6))
		UI.text_at(self, font, rr.position + Vector2(154, 58), od.name, 28, V2_INK, "lm", true)
		UI.en(self, font, rr.position + Vector2(156, 92), od.en, 10, UI.fa(V2_INK, 0.6), 4.0)
		UI.text_at(self, font, rr.position + Vector2(156, 118), "%s · %s" % [od.cls, src[i]], 11, UI.fa(V2_INK, 0.7), "lm")
		UI.para(self, Rect2(rr.end.x - 84, rr.end.y - 38, 70, 24), 6.0, tc)
		UI.en(self, font, Vector2(rr.end.x - 70, rr.end.y - 20), "NEW", 12, V2_INK, 4.0)
	UI.para(self, Rect2(W - 330, H - 104, 270, 60), 14.0, Color.WHITE)
	UI.text_at(self, font, Vector2(W - 195, H - 74), "前往选人  ›", 20, V2_INK, "mm", true)
	UI.para(self, Rect2(W - 520, H - 104, 176, 60), 14.0, Color(1, 1, 1, 0.08), Color.WHITE)
	UI.text_at(self, font, Vector2(W - 432, H - 74), "设定意向", 16, UI.TEXT, "mm")
	_motion_tag(W, "动效：卡片逐张横向翻入（第 3 张正在翻）")


# ================================================================ 定稿（10-22 用户：以 GPT 寻访概念图 27–33 为准，docs/125 §6）
# 规则改动：只有一种「寻访凭证」（每局 3 张、通关 4 张）；入口只留凭证数 +「寻访一次（1 张）」+「定向寻访（2 张）」；
# 定向 = 先选职业（28 式阵列）再选干员（30 式）；意向干员与保底删除；拉包 / 揭示 / 汇总照做（汇总去掉「设定意向」）。结算用同一语言补一张

const HS = preload("res://scripts/screens/hh_style.gd")


func _f(dsz: Vector2) -> void:
	HS.backdrop(self, dsz)
	match which:
		"hunt_f":
			_f_hunt(dsz)
		"class_f":
			_f_class(dsz)
		"pick_f":
			_f_pick(dsz)
		"bag_f":
			_f_bag(dsz)
		"reveal_f":
			_f_reveal(dsz)
		"summary_f":
			_f_summary(dsz)
		"result_f":
			_f_result(dsz)


## 灰色像素剪影 + 底部 LOCKED（卡池 / 候选用）
func _f_locked(od: Dictionary, foot: Vector2, k2: float, label := true) -> void:
	_figure(od, foot, k2, HS.SIL, 0, false)
	draw_set_transform(off + foot * k, 0.0, Vector2(k, k * 0.2))
	draw_circle(Vector2.ZERO, 80 * k2 / 4.0, Color(0, 0, 0, 0.35))
	draw_set_transform(off, 0.0, Vector2(k, k))
	if label:
		HS.solid_px(self, foot + Vector2(0, 22), "LOCKED", 2.0, Color(1, 1, 1, 0.6), 1)


func _f_hunt(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	HS.left_panel(self, dsz, 470, 330, 62)
	HS.topbar(self, font, dsz, ["PERSONNEL /", "RECRUITMENT"], "寻访")
	HS.title_block(self, font, Vector2(36, 150), "01", "人事寻访", "寻访", "HEADHUNT", 1.0, 80)
	# 凭证（只有一种）
	var vr := Rect2(36, 400, 380, 76)
	draw_rect(vr, Color(1, 1, 1, 0.55))
	draw_rect(vr, Color(0, 0, 0, 0.25), false, 1.0)
	HS.voucher(self, vr.position + Vector2(52, 38), 1.0)
	UI.text_at(self, font, vr.position + Vector2(110, 38), "寻访凭证", 20, HS.INK, "lm", true)
	UI.text_at(self, font, Vector2(vr.end.x - 20, vr.position.y + 38), "× 3", 30, HS.INK, "rm", true)
	for j in 3:
		draw_rect(Rect2(40, 506 + j * 26, 6, 6), HS.INK)
		UI.text_at(self, font, Vector2(56, 509 + j * 26), ["每次探索结算获得 3 张，通关获得 4 张", "未解锁 12 名 · 不会抽到重复干员", "首次寻访必定获得医疗干员"][j], 14, HS.INK2, "lm")
	HS.hr_mark(self, font, Vector2(40, 640))
	# 右：卡池（巨型描边英文 + 三个灰色像素剪影 + 每组一排小剪影）
	HS.outline_px(self, Vector2(560, 180), "PERSONNEL", 11.0, Color(1, 1, 1, 0.12), HS.DARK)
	var pools := [["skadi", ["irene", "lappland", "specter_unchained", "gladiia"]], ["lumen", ["kaltsit", "mizuki", "logos", "angelina"]], ["wisadel", ["ulpianus", "skalter", "siege", "saria"]]]
	for i in 3:
		var cx := 690.0 + i * 250.0
		var big := i == 1
		_f_locked(_card(pools[i][0]), Vector2(cx, 520 if big else 500), 4.0 if big else 3.0)
		for j in 4:
			_figure(_card(pools[i][1][j]), Vector2(cx - 84 + j * 56, 600 if big else 580), 0.7, Color(0.45, 0.47, 0.52), 0, false)
	_brackets(Rect2(840, 250, 200, 300), Color(1, 1, 1, 0.85), 22, 3)
	HS.para(self, Rect2(840, 210, 210, 36), UI.fa(UI.VIOLET, 0.9))
	UI.text_at(self, font, Vector2(945, 228), "卡池 · 未解锁 12 名", 15, Color.WHITE, "mm", true)
	# 右下：两个按钮
	HS.ghost_btn(self, font, Rect2(620, 636, 300, 62), "定向寻访  （2 张）", "", 1.0)
	HS.main_btn(self, font, Rect2(940, 632, 310, 68), "寻访一次  （1 张）", "")


func _f_class(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	HS.left_panel(self, dsz, 500, 380, 62)
	HS.topbar(self, font, dsz, ["PERSONNEL /", "RECRUITMENT"], "定向寻访 · 选择职业")
	var by := HS.title_block(self, font, Vector2(36, 150), "01", "定向寻访", "定向寻访", "DIRECTED", 1.0, 72)
	UI.text_at(self, font, Vector2(36, by + 34), "先选职业，再从该职业的未解锁干员中指定 1 名。", 15, HS.INK, "lm")
	UI.text_at(self, font, Vector2(36, by + 58), "消耗寻访凭证 2 张。", 15, HS.INK, "lm")
	_blit_bag(Vector2(210, 650), 1.0, 0)
	HS.hr_mark(self, font, Vector2(36, 430))
	# 右：4 × 2 职业卡
	var nlock := {"先锋": 1, "近卫": 3, "重装": 0, "狙击": 1, "术师": 1, "医疗": 2, "辅助": 1, "特种": 4}
	var per := {"先锋": ["siege"], "近卫": ["skadi", "irene", "lappland"], "重装": [], "狙击": ["wisadel"], "术师": ["logos"], "医疗": ["lumen", "kaltsit"], "辅助": ["angelina"], "特种": ["mizuki", "specter_unchained", "gladiia", "skalter"]}
	var owned := ["先锋", "重装", "术师", "辅助", "狙击"]
	for i in 8:
		var cls: String = CLASS_ORDER[i]
		var col: Color = Character.CLASS_COL[cls]
		var row := int(i / 4)
		var r := Rect2(560 + (i % 4) * 182 - row * 60, 104 + row * 284, 166, 262)
		var sel := cls == "近卫"
		var dis: bool = nlock[cls] == 0
		HS.card(self, r, col, sel, dis)
		var ink := HS.INK if sel else Color(1, 1, 1, 0.4 if dis else 1.0)
		var cx := r.get_center().x + 10
		UI.class_glyph(self, cls, Vector2(cx, r.position.y + 70), 26.0, ink, 4.0)
		HS.spaced(self, font, Vector2(cx - UI.cwidth(font, CLASS_EN[cls], 9) * 0.5 - 18, r.position.y + 128), CLASS_EN[cls], 9, UI.fa(ink, 0.7), 3.0)
		UI.text_at(self, font, Vector2(cx, r.position.y + 154), cls, 30, ink, "mm", true)
		draw_line(Vector2(r.position.x + 30, r.position.y + 182), Vector2(r.end.x - 20, r.position.y + 182), UI.fa(ink, 0.3), 1.0)
		UI.text_at(self, font, Vector2(cx, r.position.y + 204), "已全部解锁" if dis else "未解锁  %d" % nlock[cls], 16, ink, "mm")
		var sx: float = cx - per[cls].size() * 16.0
		for cid in per[cls]:
			_figure(_card(cid), Vector2(sx + 16, r.end.y - 10), 0.32, Color(0.4, 0.42, 0.47) if not sel else Color(0.45, 0.47, 0.52), 0, false)
			sx += 32.0
		if not owned.has(cls) and not dis:
			HS.tag(self, font, r.position + Vector2(r.size.y * HS.SKEW * 0.2 + 34, 10), "新职业", 0.85, HS.CYB)
	HS.bottom_bar(self, dsz, 88)
	HS.voucher(self, Vector2(80, H - 44), 0.8)
	UI.text_at(self, font, Vector2(130, H - 44), "持有寻访凭证  × 3", 20, UI.TEXT, "lm")
	UI.text_at(self, font, Vector2(330, H - 44), "本次消耗 2", 15, HS.MUTE, "lm")
	UI.text_at(self, font, Vector2(640, H - 44), "方向键选择", 15, UI.TEXT, "mm")
	HS.main_btn(self, font, Rect2(W - 330, H - 74, 310, 60), "确认职业", "Enter")


func _f_pick(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	HS.right_panel(self, dsz, 780, 640, 62, H - 88)
	HS.topbar(self, font, dsz, ["PERSONNEL /", "TRANSFER"], "定向寻访 · 指定干员")
	# 左：该职业的候选（一排大卡：剪影 + 名字可见）
	var cands := ["skadi", "irene", "lappland"]
	for i in 3:
		var od := _card(cands[i])
		var r := Rect2(40 + i * 220, 104, 200, 470)
		var sel := i == 1
		HS.card(self, r, od.col, sel)
		var ink := HS.INK if sel else Color.WHITE
		UI.class_glyph(self, od.cls, r.position + Vector2(70, 40), 14.0, ink, 3.0)
		HS.spaced(self, font, r.position + Vector2(96, 36), "GUARD", 9, UI.fa(ink, 0.7), 3.0)
		UI.text_at(self, font, r.position + Vector2(96, 54), od.cls, 16, ink, "lm", true)
		_figure(od, Vector2(r.get_center().x, r.end.y - 104), 1.8, Color(0.42, 0.44, 0.5) if not sel else Color(0.30, 0.32, 0.37), 0, false)
		draw_line(Vector2(r.position.x + 30, r.end.y - 80), Vector2(r.end.x - 30, r.end.y - 80), UI.fa(ink, 0.3), 1.0)
		UI.text_at(self, font, Vector2(r.get_center().x - 8, r.end.y - 44), od.name, 28, ink, "mm", true)
	# 右：浅色档案（编号 + 大字名 + 像素描边英文 + 职业 + 技能）+ 大剪影
	var od2 := _card("irene")
	var by := HS.title_block(self, font, Vector2(820, 130), "01", "人事调度", od2.name, od2.en, 1.0, 64)
	UI.class_glyph(self, od2.cls, Vector2(846, by + 50), 22.0, HS.INK, 4.0)
	HS.spaced(self, font, Vector2(890, by + 40), "GUARD", 10, HS.INK2, 4.0)
	UI.text_at(self, font, Vector2(890, by + 64), "近卫", 22, HS.INK, "lm", true)
	draw_rect(Rect2(820, by + 92, 240, 2), HS.INK)
	draw_rect(Rect2(820, by + 116, 3, 16), HS.INK)
	UI.text_at(self, font, Vector2(832, by + 124), "技能", 16, HS.INK, "lm", true)
	var sk: Array = od2.def.get("skills", [])
	for j in mini(3, sk.size()):
		var y := by + 150 + j * 52
		draw_rect(Rect2(820, y, 40, 40), HS.INK)
		HS.solid_px(self, Vector2(840, y + 20), "S%d" % (j + 1), 2.0, Color.WHITE, 1)
		UI.text_at(self, font, Vector2(876, y + 20), str(sk[j].get("name", "")), 17, HS.INK, "lm")
		draw_line(Vector2(876, y + 44), Vector2(1060, y + 44), UI.fa(HS.INK, 0.2), 1.0)
	_figure(od2, Vector2(1160, H - 130), 3.0, Color(0.16, 0.17, 0.21), 0, false)
	UI.text_at(self, font, Vector2(820, H - 112), "指定 1 名未解锁干员加入名册。立绘在解锁后显示。", 14, HS.INK, "lm")
	HS.bottom_bar(self, dsz, 88)
	HS.voucher(self, Vector2(80, H - 44), 0.8)
	UI.text_at(self, font, Vector2(130, H - 44), "持有寻访凭证  × 3", 20, UI.TEXT, "lm")
	UI.text_at(self, font, Vector2(330, H - 44), "本次消耗 2", 15, HS.MUTE, "lm")
	HS.ghost_btn(self, font, Rect2(W - 560, H - 72, 210, 56), "返回", "Esc")
	HS.main_btn(self, font, Rect2(W - 330, H - 74, 310, 60), "确认寻访", "Enter")


## Codex 作战包（ui_hh_bag_zip@2x 第 f 档）画在 foot（底边中点），sc = 每 @2x 像素的界面单位
func _blit_bag(foot: Vector2, sc: float, f: int) -> void:
	var tx := A.tex("ui_hh_bag_zip")
	if tx == null:
		return
	draw_texture_rect_region(tx, Rect2((foot - Vector2(128, 148) * sc).round(), Vector2(256, 152) * sc), Rect2(256 * f, 0, 256, 152))


func _f_bag(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	# 地面（浅灰台面 + 斜向墙面）
	draw_colored_polygon(PackedVector2Array([Vector2(0, 470), Vector2(W, 470), Vector2(W, H), Vector2(0, H)]), Color8(58, 62, 72))
	draw_colored_polygon(PackedVector2Array([Vector2(180, 470), Vector2(W - 180, 470), Vector2(W - 60, H), Vector2(60, H)]), Color8(74, 78, 88))
	for x in [150.0, 320.0, W - 320.0, W - 150.0]:
		draw_line(Vector2(x, 0), Vector2(x - 60, 470), Color(1, 1, 1, 0.05), 24.0)
	var foot := Vector2(W / 2.0, 600)
	var sc := 2.0
	var s := 6
	var tx := A.tex("ui_hh_bag_zip")
	var tl := foot - Vector2(128, 148) * sc
	if tx != null:
		draw_texture_rect_region(tx, Rect2(tl, Vector2(256, 152) * sc), Rect2(256 * s, 0, 256, 152))
	var gl := A.tex("fx_hh_mouth_glow")
	var slider := [Vector2(220, 48), Vector2(194, 53), Vector2(168, 58), Vector2(142, 63), Vector2(115, 68), Vector2(89, 73), Vector2(63, 78), Vector2(37, 83)]
	var mouth: Vector2 = tl + (slider[s] + Vector2(220, 48)) / 2.0 * sc
	if gl != null:
		draw_texture_rect_region(gl, Rect2(mouth - Vector2(128, 272) * sc, Vector2(256, 320) * sc), Rect2(256, 0, 256, 320))
	var fr := A.tex("ui_hh_bag_zip_front")
	if fr != null:
		draw_texture_rect_region(fr, Rect2(tl, Vector2(256, 152) * sc), Rect2(256 * s, 0, 256, 152))
	var sh := A.tex("fx_hh_shards")
	if sh != null:
		for e in [[-120, -260, 6], [90, -330, 7], [-60, -420, 8], [150, -200, 9], [-190, -160, 0], [40, -480, 2]]:
			draw_texture_rect_region(sh, Rect2(mouth + Vector2(e[0], e[1]) - Vector2(32, 32) * sc, Vector2(64, 64) * sc), Rect2(64 * e[2], 0, 64, 64), Color8(255, 196, 80))
	draw_rect(Rect2(40, 34, 3, 64), UI.TEXT)
	UI.text_at(self, font, Vector2(64, 48), "寻访", 26, UI.TEXT, "lm", true)
	draw_rect(Rect2(64, 74, 140, 1.5), UI.TEXT)
	HS.spaced(self, font, Vector2(64, 98), "PERSONNEL", 13, UI.TEXT, 5.0)
	var br := Rect2(W - 210, 26, 180, 50)
	HS.para(self, br, Color(0, 0, 0, 0.3), UI.TEXT)
	UI.text_at(self, font, br.get_center(), "跳过    Esc", 17, UI.TEXT, "mm", true)
	draw_line(Vector2(W / 2.0 - 160, H - 66), Vector2(W / 2.0 - 70, H - 66), UI.TEXT, 3.0)
	draw_polyline(PackedVector2Array([Vector2(W / 2.0 - 146, H - 78), Vector2(W / 2.0 - 160, H - 66), Vector2(W / 2.0 - 146, H - 54)]), UI.TEXT, 3.0)
	HS.spaced(self, font, Vector2(W / 2.0 - 50, H - 58), "向左拉开拉链", 18, UI.TEXT, 8.0)


func _f_reveal(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	var od := _card("lumen")
	var col: Color = od.col
	# 右：职业色半透明斜带 + 大号职业图标水印 + 描边英文
	draw_colored_polygon(PackedVector2Array([Vector2(1080, 0), Vector2(1280, 0), Vector2(1280, 0), Vector2(900, H), Vector2(700, H)]), UI.fa(col.darkened(0.35), 0.45))
	UI.class_glyph(self, od.cls, Vector2(1000, 250), 150.0, UI.fa(col.darkened(0.2), 0.45), 28.0)
	HS.outline_px(self, Vector2(440, 450), od.en, 28.0, Color(1, 1, 1, 0.16), HS.DARK)
	# 左：浅灰斜切名牌面板
	draw_colored_polygon(PackedVector2Array([Vector2(0, 48), Vector2(460, 48), Vector2(300, 660), Vector2(0, 660)]), HS.LIGHT)
	draw_line(Vector2(300, 668), Vector2(650, 668), Color(1, 1, 1, 0.3), 1.0)
	UI.class_glyph(self, od.cls, Vector2(110, 190), 40.0, HS.INK, 7.0)
	draw_rect(Rect2(186, 152, 2, 76), HS.INK)
	HS.spaced(self, font, Vector2(214, 176), "MEDIC", 13, HS.INK, 8.0)
	UI.text_at(self, font, Vector2(212, 212), "医疗", 40, HS.INK, "lm", true)
	UI.text_at(self, font, Vector2(46, 262), "流明", 110, HS.INK, "la", true)
	draw_rect(Rect2(52, 410, 66, 4), HS.YEL)
	HS.outline_px(self, Vector2(52, 456), od.en, 14.0, HS.INK2, HS.LIGHT)
	HS.tag(self, font, Vector2(52, 540), "新加入", 1.1)
	draw_rect(Rect2(170, 544, 2, 26), HS.INK)
	UI.text_at(self, font, Vector2(186, 557), "已加入名册", 18, HS.INK, "lm")
	draw_line(Vector2(330, 557), Vector2(420, 557), HS.INK2, 1.0)
	# 立绘（6 倍像素）+ 网点投影
	_figure(od, Vector2(820, 650), 6.0, Color(0, 0, 0, 0), 2, false)
	for i in 120:
		var x := 640.0 + (i % 40) * 9.0
		var y := 640.0 + int(i / 40) * 8.0
		draw_rect(Rect2(x + (int(i / 40) % 2) * 4, y, 3, 3), Color(0, 0, 0, 0.35))
	var br := Rect2(W - 190, 18, 160, 40)
	HS.para(self, br, Color(0, 0, 0, 0.3), UI.TEXT)
	UI.text_at(self, font, br.get_center(), "跳过   Esc", 15, UI.TEXT, "mm", true)
	HS.main_btn(self, font, Rect2(W - 330, H - 112, 300, 70), "继续", "Enter")


func _f_summary(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	HS.left_panel(self, dsz, 400, 290, 62)
	HS.topbar(self, font, dsz, ["PERSONNEL /", "RECRUITMENT"], "本次寻访")
	var by := HS.title_block(self, font, Vector2(36, 150), "01", "人员寻访记录", "本次寻访", "RECORD", 1.0, 72)
	UI.text_at(self, font, Vector2(36, by + 34), "本次加入干员如下。", 18, HS.INK, "lm")
	draw_rect(Rect2(40, by + 74, 3, 100), HS.INK)
	UI.text_at(self, font, Vector2(64, by + 88), "本次加入", 18, HS.INK, "lm")
	UI.text_at(self, font, Vector2(60, by + 110), "3", 76, HS.INK, "la", true)
	UI.text_at(self, font, Vector2(118, by + 156), "名", 30, HS.INK, "lm", true)
	HS.hr_mark(self, font, Vector2(36, 600))
	var ids := ["irene", "lumen", "gladiia"]
	var tiers := ["cyan", "gold", "cyan"]
	for i in 3:
		var od := _card(ids[i])
		var r := Rect2(470 + i * 266, 112, 246, 520)
		HS.card(self, r, od.col)
		UI.class_glyph(self, od.cls, Vector2(r.get_center().x + 28, r.position.y + 46), 22.0, Color.WHITE, 4.0)
		HS.spaced(self, font, Vector2(r.get_center().x - 6, r.position.y + 94), CLASS_EN[od.cls], 9, UI.fa(Color.WHITE, 0.7), 3.0)
		UI.text_at(self, font, Vector2(r.get_center().x + 26, r.position.y + 118), od.cls, 24, Color.WHITE, "mm", true)
		_figure(od, Vector2(r.get_center().x + 6, r.position.y + 372), 2.5, Color(0, 0, 0, 0), 0, false)
		# 名牌：浅色斜块 + 新加入黄签
		var nr := Rect2(r.position.x + 10, r.end.y - 132, r.size.x - 22, 112)
		HS.para(self, nr, HS.LIGHT)
		HS.tag(self, font, nr.position + Vector2(30, -12), "新加入", 0.9, HS.YEL if tiers[i] == "gold" else HS.CYB)
		UI.text_at(self, font, Vector2(nr.get_center().x, nr.position.y + 46), od.name, 34, HS.INK, "mm", true)
		draw_line(Vector2(nr.position.x + 50, nr.position.y + 74), Vector2(nr.end.x - 50, nr.position.y + 74), HS.INK2, 1.0)
		HS.spaced(self, font, Vector2(nr.get_center().x - UI.cwidth(font, od.en, 10) * 0.9, nr.position.y + 98), od.en, 10, HS.INK2, 6.0)
	HS.bottom_bar(self, dsz, 88)
	UI.text_at(self, font, Vector2(64, H - 44), "已加入名册。新干员可以在选人页选为队长。", 16, UI.TEXT, "lm")
	HS.main_btn(self, font, Rect2(W - 330, H - 74, 310, 60), "完成", "")


func _f_result(dsz: Vector2) -> void:
	var W := dsz.x
	var H := dsz.y
	HS.left_panel(self, dsz, 440, 320, 62)
	HS.topbar(self, font, dsz, ["OPERATION /", "REPORT"], "作战记录", 1.0, "潮位 8")
	var by := HS.title_block(self, font, Vector2(36, 140), "01", "作战报告", "探索完成", "COMPLETE", 1.0, 62)
	# 评级大字（像素描边）+ 结局 + 关键数字
	HS.outline_px(self, Vector2(306, 206), "A", 12.0, HS.INK, HS.LIGHT)
	HS.spaced(self, font, Vector2(300, 266), "RATING", 9, HS.INK2, 4.0)
	UI.text_at(self, font, Vector2(36, by + 14), "结局一 · 平凡即是喜乐", 15, HS.INK, "lm", true)
	by += 20.0
	var bx := 36.0
	for it in [["10:24", "探索时间"], ["1,284", "击杀"], ["3 / 3", "Boss"]]:
		UI.text_at(self, font, Vector2(bx, by + 30), it[0], 30, HS.INK, "la", true)
		UI.text_at(self, font, Vector2(bx, by + 74), it[1], 13, HS.INK2, "la")
		bx += 116.0
	# 计分
	var sy := by + 116
	for j in 4:
		var row: Array = SCORE[j]
		UI.text_at(self, font, Vector2(36, sy + j * 24), row[0], 14, HS.INK, "lm")
		UI.text_at(self, font, Vector2(330, sy + j * 24), row[3], 15, HS.INK, "rm", true)
		draw_line(Vector2(36, sy + j * 24 + 11), Vector2(330, sy + j * 24 + 11), UI.fa(HS.INK, 0.15), 1.0)
	UI.text_at(self, font, Vector2(36, sy + 104), "(200 × 潮位 8 ×1.4 + 40) ÷ 8 = 40", 13, HS.INK2, "lm")
	HS.hr_mark(self, font, Vector2(36, 646), 1.0, HS.INK2, ["RHODES ISLAND", "OPERATION RECORD"])
	# 右：本局编队（队长大卡 + 队友小卡）
	HS.spaced(self, font, Vector2(500, 104), "SQUAD  //  本局编队", 11, HS.MUTE, 3.0)
	var lead := _card("mizuki")
	var lr := Rect2(500, 124, 300, 420)
	HS.card(self, lr, lead.col)
	HS.tag(self, font, lr.position + Vector2(90, 14), "队长", 0.85, UI.VIOLET)
	_figure(lead, Vector2(lr.get_center().x + 20, lr.end.y - 116), 4.0, Color(0, 0, 0, 0), 0, false)
	UI.text_at(self, font, Vector2(lr.position.x + 40, lr.end.y - 84), lead.name, 30, Color.WHITE, "lm", true)
	UI.text_at(self, font, Vector2(lr.position.x + 36, lr.end.y - 50), "伤害 46% · 参与击杀 590", 14, UI.TEXT, "lm")
	UI.text_at(self, font, Vector2(lr.position.x + 30, lr.end.y - 26), "Lv.24 精二", 13, HS.MUTE, "lm")
	var mates := [["lumen", "伤害 21% · 击杀 312", "Lv.18 精一", "new"], ["skadi", "伤害 27% · 击杀 361", "Lv.16 精一", ""], ["exusiai", "伤害 6% · 击杀 21", "Lv.9 精零", "out"]]
	for i in 3:
		var od := _card(mates[i][0])
		var out: bool = mates[i][3] == "out"
		var r := Rect2(840 - i * 20, 124 + i * 142, 400, 126)
		HS.card(self, r, od.col, false, out)
		_figure(od, Vector2(r.position.x + 92, r.end.y - 12), 1.5, Color(0.3, 0.32, 0.36) if out else Color(0, 0, 0, 0), 0, false)
		UI.text_at(self, font, Vector2(r.position.x + 160, r.position.y + 36), od.name, 22, UI.fa(Color.WHITE, 0.45 if out else 1.0), "lm", true)
		UI.text_at(self, font, Vector2(r.position.x + 158, r.position.y + 70), mates[i][1], 13, UI.fa(UI.TEXT, 0.45 if out else 0.9), "lm")
		UI.text_at(self, font, Vector2(r.position.x + 154, r.position.y + 96), mates[i][2], 12, UI.fa(HS.MUTE, 0.6 if out else 1.0), "lm")
		if mates[i][3] == "new":
			HS.tag(self, font, Vector2(r.end.x - 110, r.position.y + 14), "新加入", 0.8)
		elif out:
			HS.tag(self, font, Vector2(r.end.x - 110, r.position.y + 14), "已撤退", 0.8, HS.MUTE)
	# 底栏：获得（生机细胞 + 寻访凭证）+ 按钮
	HS.bottom_bar(self, dsz, 96)
	HS.spaced(self, font, Vector2(470, H - 66), "REWARDS", 10, HS.MUTE, 4.0)
	_halo(Vector2(520, H - 36), 22, UI.GREEN)
	draw_circle(Vector2(520, H - 36), 11, UI.GREEN)
	UI.text_at(self, font, Vector2(548, H - 36), "生机细胞  +53", 18, UI.TEXT, "lm", true)
	HS.voucher(self, Vector2(720, H - 36), 0.65)
	UI.text_at(self, font, Vector2(756, H - 36), "寻访凭证  × 4", 18, UI.TEXT, "lm", true)
	UI.text_at(self, font, Vector2(900, H - 36), "通关 4 张", 12, HS.MUTE, "lm")
	HS.ghost_btn(self, font, Rect2(24, H - 78, 190, 56), "再次探索", "R")
	HS.ghost_btn(self, font, Rect2(224, H - 78, 190, 56), "回到标题", "T")
	HS.main_btn(self, font, Rect2(W - 300, H - 80, 280, 62), "前往寻访", "Enter")
