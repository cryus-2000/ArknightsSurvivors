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
