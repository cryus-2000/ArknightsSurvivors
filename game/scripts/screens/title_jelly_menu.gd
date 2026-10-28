extends RefCounted
## 标题页菜单·深海水母（docs/67 §13，10-24 用户定：Codex 47-C「探索徽记」构图 + 方向二「青光航标」精修；对照图 art/archive/incoming_1028/title_jelly_1024/）。
## 左侧入口分主次（10-25 用户定原 B，对照图 art/archive/incoming_1028/title_jelly_1024/hierarchy/B.png）：「成长」寻访 / 认知塑造（大）、
## 「档案」图鉴 / 蚀刻章（小一号）、试炼（一行小字）；刻度圆盘「集结出发」；底部一行（设置 / 操作说明 / 退出）。
## 选中态：深色半透明斜切底条 + 青色左边标 + 青下划线 + 实心圆环图标（各档同一套，按行高缩放）；青色只给「可操作 / 选中」。
## 版式两套：桌面（UI 逻辑高 ≥ 712，设计坐标 1280×720，多出的高度给下半部）；紧凑（手机横屏 / 矮窗口：缩小、「集结出发」挪到右下拇指区）。
## 都按 Cfg.safe_insets() 让开刘海 / 圆角。导航按几何方向找最近的一项（不循环），Tab 按可见顺序线性走。

const UI = preload("res://scripts/ui.gd")

## 菜单表：id 是 title.gd sel / item_rects / menu_water 的下标（沿用旧磁贴表的 id，不重排）。
## slot：list = 左侧入口、deploy = 圆盘主按钮、foot = 底部一行
const MENU := [
	{"id": 0, "cn": "集结出发", "en": "DEPLOY", "slot": "deploy"},
	{"id": 7, "cn": "寻访", "en": "HEADHUNT", "slot": "list", "icon": "headhunt", "tier": 0},
	{"id": 6, "cn": "认知塑造", "en": "COGNITION", "slot": "list", "icon": "cognition", "tier": 0},
	{"id": 1, "cn": "图鉴", "en": "ARCHIVE", "slot": "list", "icon": "gallery", "tier": 1},
	{"id": 8, "cn": "蚀刻章", "en": "MEDALS", "slot": "list", "icon": "medals", "tier": 1},   # 10-25 蚀刻章「深蓝之下」（screens/medals_ui.gd）
	{"id": 2, "cn": "试炼", "en": "TRIAL", "slot": "list", "icon": "trial", "tier": 2, "tag": "测试版"},
	{"id": 4, "cn": "设置", "en": "SETTINGS", "slot": "foot"},
	{"id": 3, "cn": "操作说明", "en": "GUIDE", "slot": "foot"},
	{"id": 5, "cn": "退出", "en": "EXIT", "slot": "foot"},
]

const C := Color(0.616, 0.898, 0.937)          # #9de5ef 青（选中 / 可操作）
const T := Color(0.914, 0.941, 0.953)          # #e9f0f3
const M := Color(0.635, 0.725, 0.784)          # #a2b9c8 次级字
const L := Color(0.275, 0.380, 0.443)          # #466171 线
const INK := Color(0.075, 0.153, 0.204)        # #132734
const RING := Color(0.361, 0.494, 0.561)       # #5c7e8f
const GLYPH := Color(0.792, 0.851, 0.882)      # #cad9e1
const STRIP := Color(0.094, 0.204, 0.267, 0.84)
## 三档入口（设计坐标）：h 行高、gap 行后空、ring 圆环半径（0 = 不画圈）、ix 图标中心 x、ik 图标缩放、tx 中文左边、fs 中文字号、
## en 英文字号（0 = 不写）、en_inline 英文跟在中文右边、sw 选中底条宽、ul 选中下划线 y
const TIERS := [
	{"h": 52.0, "gap": 6.0, "ring": 19.0, "ix": 26.0, "ik": 1.0, "tx": 60.0, "fs": 25, "en": 9, "en_inline": false, "sw": 300.0, "ul": 53.0},
	{"h": 40.0, "gap": 4.0, "ring": 15.0, "ix": 24.0, "ik": 0.8, "tx": 50.0, "fs": 20, "en": 7, "en_inline": true, "sw": 262.0, "ul": 38.0},
	{"h": 26.0, "gap": 0.0, "ring": 0.0, "ix": 24.0, "ik": 0.55, "tx": 38.0, "fs": 13, "en": 0, "en_inline": false, "sw": 176.0, "ul": 25.0},
]
## 组小标题（设计坐标高 22；档案组前多空 10）
const GROUPS := [["成长", "GROWTH"], ["档案", "RECORDS"]]
const LABEL_H := 22.0
const EDGE := 40.0                              # 桌面版式整体离左边再收进来的量（设计坐标）


static func item(id: int) -> Dictionary:
	for m in MENU:
		if int(m.id) == id:
			return m
	return {}


## 可见顺序（Tab 线性走）：左侧入口 → 集结出发 → 底部一行
static func order() -> Array:
	var out: Array = []
	for slot in ["list", "deploy", "foot"]:
		for m in MENU:
			if m.slot == slot:
				out.append(int(m.id))
	return out


static func linear(ids: Array, sel: int, step: int) -> int:
	var k := ids.find(sel)
	if k < 0:
		return ids[0]
	return ids[posmod(k + step, ids.size())]


## 分组导航（不循环）：左侧入口上下走；桌面版式 入口 ↓ 集结出发 ↓ 底部一行（↓ 落到第一项）、↑ 反向；底部一行 ← → 走。
## 紧凑版式（集结出发在右下）：入口 ↓ 底部一行、入口 → 集结出发、底部一行最右再 → 集结出发、集结出发 ← 底部最后一项 / ↑ 最后一个入口
static func nav(lay: Dictionary, sel: int, d: Vector2i) -> int:
	var lst: Array = lay.list.ids
	var ft: Array = lay.foot.ids
	var has_d: bool = lay.rects.has(0)
	var cp: bool = lay.compact
	var li := lst.find(sel)
	var fi := ft.find(sel)
	var out := sel
	if li >= 0:
		if d.y != 0:
			out = lst[li + d.y] if li + d.y >= 0 and li + d.y < lst.size() else sel
			if li + d.y >= lst.size():
				out = (0 if has_d and not cp else (ft[0] if not ft.is_empty() else sel))
		elif d.x > 0 and cp and has_d:
			out = 0
	elif fi >= 0:
		if d.x != 0:
			if fi + d.x >= 0 and fi + d.x < ft.size():
				out = ft[fi + d.x]
			elif d.x > 0 and cp and has_d:
				out = 0
		elif d.y < 0:
			out = 0 if has_d and not cp else (lst[lst.size() - 1] if not lst.is_empty() else sel)
	elif sel == 0:
		if d.y < 0 and not lst.is_empty():
			out = lst[lst.size() - 1]
		elif d.y > 0 and not cp and not ft.is_empty():
			out = ft[0]
		elif d.x < 0 and cp and not ft.is_empty():
			out = ft[ft.size() - 1]
	return out


## 版式。ids：可见项；ins：安全边距 [左, 上, 右, 下]；touch：触屏（命中区至少 44 高）
## 返回 {compact, rects{id: Rect2}, logo{o,k}, list{o,k,ids}, deploy{o,k}, foot{o,k,ids,xs}, legal{pos, align}}
static func layout(vs: Vector2, ids: Array, ins: Array, touch: bool, font: Font) -> Dictionary:
	var compact := vs.y < 712.0
	var il: float = ins[0]
	var it: float = ins[1]
	var ir: float = ins[2]
	var ib: float = ins[3]
	var lay := {"compact": compact, "rects": {}, "vs": vs}
	var list_ids: Array = []
	var foot_ids: Array = []
	for m in MENU:
		if ids.has(int(m.id)):
			if m.slot == "list":
				list_ids.append(int(m.id))
			elif m.slot == "foot":
				foot_ids.append(int(m.id))
	var lo: Vector2
	var lk: float
	var dO: Vector2
	var dk: float
	var fo: Vector2
	var fk: float
	if not compact:
		var dy := vs.y - 720.0
		var x0 := EDGE + maxf(0.0, il)   # 10-24 用户：字别太靠边
		lo = Vector2(68 + x0, 52 + it)
		lk = 1.0
		lay.list = {"o": Vector2(64 + x0, 176 + dy * 0.55), "k": 1.0, "ids": list_ids}
		dO = Vector2(64 + x0, 466 + dy - ib)
		dk = 1.0
		fo = Vector2(68 + x0, 648 + dy - ib)
		fk = 1.0
	else:
		var lm := maxf(64.0, il + 30.0)
		var tm := maxf(22.0, it + 14.0)
		var bm := vs.y - maxf(10.0, ib + 8.0)
		var rm := vs.x - maxf(48.0, ir + 26.0)
		lk = 0.86
		lo = Vector2(lm, tm)
		var ly := tm + 86.0 * lk
		var avail := bm - 56.0 - ly   # 列表一直排到底部一行上面（集结出发在右下）
		var k := 1.0
		while k > 0.66 and _stack(list_ids, k, touch).h * k > avail:
			k -= 0.02
		lay.list = {"o": Vector2(lm - 4.0, ly), "k": k, "ids": list_ids}
		dk = clampf(vs.y / 600.0, 0.7, 0.92)
		dO = Vector2(rm - 320.0 * dk, bm - 178.0 * dk)
		fk = 0.9
		fo = Vector2(lm, bm - 48.0)
	lay.logo = {"o": lo, "k": lk}
	var lst: Dictionary = lay.list
	var stk: Dictionary = _stack(list_ids, lst.k, touch)
	lst.rows = stk.rows
	lst.labels = stk.labels
	for r in stk.rows:
		var o: Vector2 = lst.o + Vector2(0, r.y) * lst.k
		lay.rects[r.id] = Rect2(o.x, o.y, (TIERS[r.tier].sw + 8.0) * lst.k, r.h * lst.k)
	lay.deploy = {"o": dO, "k": dk}
	if ids.has(0):
		lay.rects[0] = Rect2(dO, Vector2(320, 176) * dk)
	# 底部一行：各项文字宽度排开，中间「/」
	var xs: Array = []
	var x := 7.0
	var fsz := 15
	for j in foot_ids.size():
		if j > 0:
			x += 30.0
		var w: float = font.get_string_size(item(foot_ids[j]).cn, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		xs.append([x, w])
		var h := (44.0 / fk) if touch else 34.0   # 触屏：缩放后命中区仍至少 44 高
		lay.rects[foot_ids[j]] = Rect2(fo + Vector2(x - 8.0, 25.0 - h / 2.0) * fk, Vector2(w + 16.0, h) * fk)
		x += w
	lay.foot = {"o": fo, "k": fk, "ids": foot_ids, "xs": xs, "end": fo.x + x * fk}
	if compact:
		lay.legal = {"pos": Vector2(maxf(fo.x + x * fk + 28.0, fo.x), fo.y + 30.0 * fk), "align": "l", "max_x": dO.x - 16.0}
	else:
		lay.legal = {"pos": Vector2(vs.x - 48.0 - ir, vs.y - 24.0 - ib), "align": "r", "max_x": vs.x}
	return lay


## 左侧入口逐行排：组小标题 + 各档行高（触屏时一行至少 44 逻辑像素高，内容在行内竖直居中）
## 返回 {rows: [{id, tier, y, h, pad}], labels: [{y, cn, en}], h}（设计坐标，相对列表原点）
static func _stack(list_ids: Array, k: float, touch: bool) -> Dictionary:
	var rows: Array = []
	var labels: Array = []
	var y := 0.0
	var last := -1
	for id in list_ids:
		var tier: int = item(id).tier
		if tier != last:
			if last >= 0:
				y += 10.0 if tier < GROUPS.size() else 6.0
			if tier < GROUPS.size():
				labels.append({"y": y, "cn": GROUPS[tier][0], "en": GROUPS[tier][1]})
				y += LABEL_H
		last = tier
		var tt: Dictionary = TIERS[tier]
		var h: float = maxf(tt.h, (44.0 / k) if touch else 0.0)
		rows.append({"id": id, "tier": tier, "y": y, "h": h, "pad": (h - tt.h) / 2.0})
		y += h + tt.gap
	return {"rows": rows, "labels": labels, "h": y}


# ---------------------------------------------------------------- 绘制
## st：{font, sel, water[], now, rm, a_logo, a_list[], a_deploy, a_foot, slide, dim[], tickets(-1 = 不显示), logo_tex}

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func _txt(ci: CanvasItem, font: Font, top_left: Vector2, s: String, size: int, col: Color) -> float:
	ci.draw_string(font, top_left + Vector2(0, font.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 拉丁小标签（压缩字 + 字距），pos 左上
static func _en(ci: CanvasItem, font: Font, top_left: Vector2, s: String, size: int, col: Color, sp: float) -> float:
	var f: Font = UI.cond(font)
	return UI.en(ci, font, top_left + Vector2(0, f.get_ascent(size)), s, size, col, sp)


static func _spaced(ci: CanvasItem, font: Font, top_left: Vector2, s: String, size: int, col: Color, sp: float) -> void:
	var x := top_left.x
	var y := top_left.y + font.get_ascent(size)
	for ch in s:
		ci.draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + sp


static func _arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	ci.draw_arc(c, r, deg_to_rad(a0), deg_to_rad(a1), maxi(6, int(absf(a1 - a0) / 4.0)), col, w, true)


static func draw(ci: CanvasItem, lay: Dictionary, st: Dictionary) -> void:
	var font: Font = st.font
	_draw_logo(ci, lay.logo.o, lay.logo.k, font, st.a_logo, st.logo_tex)
	var lst: Dictionary = lay.list
	var a0: float = st.a_list[0] if not st.a_list.is_empty() else 0.0
	for lb in lst.labels:
		_draw_label(ci, lst.o + Vector2(-st.slide * (1.0 - a0), lb.y * lst.k), lst.k, font, lb.cn, lb.en, a0)
	for i in lst.rows.size():
		var r: Dictionary = lst.rows[i]
		var a: float = st.a_list[i]
		if a <= 0.0:
			continue
		var o: Vector2 = lst.o + Vector2(0, r.y + r.pad) * lst.k + Vector2(-st.slide * (1.0 - a), 0)
		_draw_row(ci, o, lst.k, font, item(r.id), TIERS[r.tier], st.water[r.id], a, st.dim.has(r.id), st.tickets if r.id == 7 else -1)
	if lay.rects.has(0) and st.a_deploy > 0.0:
		_draw_deploy(ci, lay.deploy.o, lay.deploy.k, font, st.water[0], st.a_deploy, st.now, st.rm)
	if st.a_foot > 0.0:
		_draw_foot(ci, lay.foot, font, st.water, st.a_foot)


static func _draw_logo(ci: CanvasItem, o: Vector2, k: float, font: Font, a: float, tex: Texture2D) -> void:
	if a <= 0.0:
		return
	var w := 262.0 * k
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(o, Vector2(w, w * tex.get_height() / tex.get_width())), false, Color(1, 1, 1, a))
	var sc := w / 482.0
	_en(ci, font, o + Vector2(132.0 * sc + 1.0, -3.0 * k), "ARKNIGHTS", int(round(9 * k)), _fa(Color(0.765, 0.827, 0.863), a), 3.2 * k)
	var ry := o.y + 92.0 * sc
	ci.draw_line(Vector2(o.x, ry), Vector2(o.x + w, ry), _fa(Color(0.231, 0.333, 0.4), a), 1.0)
	ci.draw_line(Vector2(o.x, ry), Vector2(o.x + 22.0 * k, ry), _fa(C, a), 2.0)
	var sx := o.x + 30.0 * k
	var fs := int(round(9 * k))
	sx += _en(ci, font, Vector2(sx, ry + 6.0 * k), "RHODES ISLAND", fs, _fa(M, a), 2.6 * k) + 6.0 * k
	sx += _en(ci, font, Vector2(sx, ry + 6.0 * k), "·", fs, _fa(L, a), 0.0) + 8.0 * k
	_en(ci, font, Vector2(sx, ry + 6.0 * k), "SURVIVORS", fs, _fa(Color(0.835, 0.886, 0.91), a), 2.6 * k)


## 组小标题：青色短竖条 + 中文 + 英文
static func _draw_label(ci: CanvasItem, o: Vector2, k: float, font: Font, cn: String, en: String, a: float) -> void:
	if a <= 0.0:
		return
	ci.draw_rect(Rect2(o + Vector2(2, 2) * k, Vector2(3, 11) * k), _fa(C, a))
	var w := _txt(ci, font, o + Vector2(12, 0) * k, cn, int(round(12 * k)), _fa(C, a))
	_en(ci, font, o + Vector2(20, 3) * k + Vector2(w, 0), en, int(round(8 * k)), _fa(M, a), 2.2 * k)


## 一行入口（tt = TIERS 里的一档；o = 行左上，内容按 tt.h 画）
static func _draw_row(ci: CanvasItem, o: Vector2, k: float, font: Font, m: Dictionary, tt: Dictionary, water: float, a: float, dim: bool, tickets: int) -> void:
	var w := _ease(water)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var h: float = tt.h
	if w > 0.0:
		var rx: float = tt.sw * w
		ci.draw_colored_polygon(PackedVector2Array([P.call(0, 0), P.call(rx, 0), P.call(maxf(0.0, rx - h * 0.3), h), P.call(0, h)]), _fa(STRIP, a * w))
		ci.draw_rect(Rect2(P.call(0, 0), Vector2(3, h) * k), _fa(C, a))
	var dm := 0.45 if dim else 1.0
	var rc: Vector2 = P.call(tt.ix, h / 2.0)
	if tt.ring > 0.0:
		if w > 0.0:
			ci.draw_circle(rc, tt.ring * k, _fa(Color(0.055, 0.157, 0.204), a * w))
		ci.draw_arc(rc, tt.ring * k, 0.0, TAU, 48, _fa(RING.lerp(C, w), a * dm), maxf(1.0, 1.2 * k), true)
	_icon(ci, rc, str(m.icon), _fa(GLYPH.lerp(C, w), a * dm * (1.0 if tt.ring > 0.0 else 0.8)), k * tt.ik)
	var fs := int(round(tt.fs * k))
	var tc: Color = Color(0.859, 0.898, 0.918).lerp(Color.WHITE, w)
	if tt.ring == 0.0:
		tc = Color(0.627, 0.69, 0.729).lerp(Color.WHITE, w)   # 最轻一档（试炼）：字也暗一档
	var ty: float = 7.0 if tt.en > 0 and not tt.en_inline else (h - tt.fs * 1.3) / 2.0
	var cw := _txt(ci, font, P.call(tt.tx, ty), m.cn, fs, _fa(tc, a * dm))
	var tx: Vector2 = P.call(tt.tx, ty) + Vector2(cw + 10.0 * k, 0)
	if tt.en > 0:
		var efs := int(round(tt.en * k))
		if tt.en_inline:
			tx.x += _en(ci, font, tx + Vector2(0, (fs - efs) * 0.62), m.en, efs, _fa(M.lerp(C, w), a * dm), 2.2 * k) + 8.0 * k
		else:
			_en(ci, font, P.call(tt.tx + 1, 37), m.en, efs, _fa(M.lerp(C, w), a * dm), 2.4 * k)
	if m.has("tag"):
		var tfs := int(round((10 if tt.ring > 0.0 else 9) * k))
		_txt(ci, font, tx + Vector2(0, (fs - tfs) * 0.55), m.tag, tfs, _fa(M, a))
	if tickets >= 0:
		# 寻访凭证数：黄底斜块 + 黑字（寻访界面的黄色，hh_style）；没有凭证时灰
		var s := "×%d" % tickets
		var bfs := int(round(13 * k))
		var bw: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x + 14.0 * k
		var by := tx.y + 6.0 * k
		var bh := 18.0 * k
		var col := Color8(255, 206, 0) if tickets > 0 else Color8(110, 118, 128)
		var q := bh * 0.2
		ci.draw_colored_polygon(PackedVector2Array([Vector2(tx.x + q, by), Vector2(tx.x + bw, by), Vector2(tx.x + bw - q, by + bh), Vector2(tx.x, by + bh)]), _fa(col, a))
		ci.draw_string(font, Vector2(tx.x, by + bh * 0.5 + (font.get_ascent(bfs) - font.get_descent(bfs)) * 0.5), s, HORIZONTAL_ALIGNMENT_CENTER, bw, bfs, Color(0.07, 0.07, 0.09, a))
	if w > 0.0:
		ci.draw_line(P.call(tt.tx, tt.ul), P.call(tt.tx + (tt.sw - tt.tx - 64.0) * w, tt.ul), _fa(C, a * w), maxf(1.0, 1.4 * k))
		var cx: float = tt.sw - 22.0 - h * 0.15
		var ch: float = minf(10.0, h * 0.2)
		ci.draw_polyline(PackedVector2Array([P.call(cx - 5, h / 2 - ch), P.call(cx + 4, h / 2), P.call(cx - 5, h / 2 + ch)]), _fa(C, a * w), maxf(1.0, 1.8 * k), true)


## 线框图标（同 Codex 41 版 icon()，尺寸统一到同一光学大小）
static func _icon(ci: CanvasItem, c: Vector2, kind: String, col: Color, k: float) -> void:
	var s: float = {"headhunt": 0.82, "gallery": 0.74, "cognition": 0.78, "trial": 0.78, "medals": 0.8}.get(kind, 0.8) * k
	var lw := maxf(1.0, 1.3 * k)
	var ln := func(pts: Array) -> void:
		var pv := PackedVector2Array()
		for p in pts:
			pv.append(c + Vector2(p[0], p[1]) * s)
		ci.draw_polyline(pv, col, lw, true)
	match kind:
		"headhunt":
			ci.draw_arc(c + Vector2(-3, -5) * s, 4.0 * s, 0.0, TAU, 20, col, lw, true)
			ln.call([[-11, 10], [-11, 6], [-8, 2], [1, 2], [5, 6], [5, 10]])
			ln.call([[6, -8], [11, -5], [10, 0], [7, 2], [12, 4], [14, 9]])
		"gallery":
			c += Vector2(0, 1) * k
			ln.call([[0, 12], [-11, 7], [-14, 7], [-14, -10], [-6, -10], [0, -6], [6, -10], [14, -10], [14, 7], [11, 7], [0, 12], [0, -6]])
			ln.call([[-10, -5], [-5, -3]])
			ln.call([[5, -3], [10, -5]])
		"cognition":
			ln.call([[-12, -6], [0, 5], [10, -11]])
			ln.call([[0, 5], [13, 12]])
			for p in [[-12, -6], [0, 5], [10, -11], [13, 12]]:
				ln.call([[p[0], p[1] - 3], [p[0] + 3, p[1]], [p[0], p[1] + 3], [p[0] - 3, p[1]], [p[0], p[1] - 3]])
		"medals":
			ln.call([[-7, -13], [-3, -4]])
			ln.call([[7, -13], [3, -4]])
			ci.draw_arc(c + Vector2(0, 4) * s, 8.0 * s, 0.0, TAU, 28, col, lw, true)
			ci.draw_arc(c + Vector2(0, 4) * s, 3.5 * s, 0.0, TAU, 16, col, lw, true)
		"trial":
			ln.call([[-11, -10], [11, 10]])
			ln.call([[-11, 10], [11, -10]])
			ln.call([[-11, -10], [-6, -9], [-10, -5]])
			ln.call([[11, -10], [6, -9], [10, -5]])


static var _glow_tex: Texture2D


static func _glow() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_glow_tex = gt
	return _glow_tex


## 集结出发：刻度圆盘 + 方向箭头 + 双行大字。动效都很慢：外圈弧 4°/秒转、中心光晕 7 秒一呼吸（±0.03）、选中时箭头沿方向 3.2 秒往复 2.5 像素；
## 减少动态效果全部静止
static func _draw_deploy(ci: CanvasItem, o: Vector2, k: float, font: Font, water: float, a: float, now: float, rm: bool) -> void:
	var w := _ease(water)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var cc: Vector2 = P.call(224, 80)
	var breathe := 0.0 if rm else 0.03 * sin(now * TAU / 7.0)
	var gr := 96.0 * k
	ci.draw_texture_rect(_glow(), Rect2(cc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, _fa(Color(0.43, 0.82, 0.9), a * (0.14 + 0.1 * w + breathe)))
	var rot := 0.0 if rm else fmod(now * 4.0, 360.0)
	for seg in [[76, 197, 342], [86, 12, 123], [67, 16, 126], [82, 133, 174]]:
		_arc(ci, cc, seg[0] * k, seg[1] + rot, seg[2] + rot, _fa(Color(0.365, 0.592, 0.667), a), 1.0)
	var tick: Color = Color(0.333, 0.471, 0.541).lerp(Color(0.561, 0.827, 0.875), w)
	for i in 28:
		var g := deg_to_rad(-78.0 + i * 5.4)
		var lng := i % 7 == 0
		var dv := Vector2(cos(g), sin(g))
		ci.draw_line(cc + dv * (70.0 if lng else 73.0) * k, cc + dv * 82.0 * k, _fa(tick, a), 1.2 if lng else 1.0, true)
	_arc(ci, cc, 76.0 * k, -78.0, -78.0 + lerpf(22.0, 58.0, w), _fa(C, a), maxf(1.5, 2.4 * k))
	var nudge := Vector2(1, -1).normalized() * (0.0 if rm else 2.5 * w * (0.5 + 0.5 * sin(now * TAU / 3.2)))
	ci.draw_line(P.call(194, 126) + nudge, P.call(258, 62) + nudge, _fa(C, a), maxf(1.5, 2.4 * k), true)
	ci.draw_colored_polygon(PackedVector2Array([P.call(266, 54) + nudge, P.call(240, 60) + nudge, P.call(260, 80) + nudge]), _fa(C, a))
	ci.draw_circle(P.call(190, 130), 4.0 * k, _fa(C, a))
	var fs := int(round(50 * k))
	_spaced(ci, font, P.call(8, 14), "集结", fs, _fa(Color.WHITE, a), 4.0 * k)
	_spaced(ci, font, P.call(34, 74), "出发", fs, _fa(Color.WHITE, a), 4.0 * k)
	ci.draw_colored_polygon(PackedVector2Array([P.call(12, 142), P.call(84, 142), P.call(78, 158), P.call(12, 158)]), _fa(C, a))
	_en(ci, font, P.call(18, 144), "DEPLOY", int(round(10 * k)), _fa(INK, a), 3.0 * k)
	ci.draw_line(P.call(11, 168), P.call(11 + 161.0 * lerpf(0.55, 1.0, w), 168), _fa(L.lerp(C, w), a), maxf(1.0, 1.3 * k))


static func _draw_foot(ci: CanvasItem, f: Dictionary, font: Font, water: Array, a: float) -> void:
	var o: Vector2 = f.o
	var k: float = f.k
	ci.draw_line(o, o + Vector2(250, 0) * k, _fa(Color(0.149, 0.224, 0.29), a), 1.0)
	var fs := int(round(15 * k))
	for j in f.ids.size():
		var id: int = f.ids[j]
		var x: float = f.xs[j][0]
		var tw: float = f.xs[j][1]
		if j > 0:
			_txt(ci, font, o + Vector2(x - 19.0, 13) * k, "/", int(round(12 * k)), _fa(Color(0.231, 0.333, 0.4), a))
		var w := _ease(water[id])
		_txt(ci, font, o + Vector2(x, 12) * k, item(id).cn, fs, _fa(Color(0.776, 0.831, 0.863).lerp(Color.WHITE, w), a))
		if w > 0.0:
			ci.draw_line(o + Vector2(x, 36) * k, o + Vector2(x + tw * w, 36) * k, _fa(C, a), 2.0)
