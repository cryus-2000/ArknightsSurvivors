extends Control
## 图鉴：展示游戏里的各类贴图（干员 / 敌人 / 精英 / Boss / 道具），藏品页待藏品系统完成后开放。
## 从标题菜单打开；Q/E 或点击切换分页，方向键或点击选择条目，Z/X 或点击切换动作/形态，Esc 返回。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")

const TABS := [
	{"cn": "干员", "en": "OPERATOR"},
	{"cn": "敌人", "en": "ENEMY"},
	{"cn": "精英", "en": "ELITE"},
	{"cn": "Boss", "en": "BOSS"},
	{"cn": "道具", "en": "ITEM"},
	{"cn": "藏品", "en": "RELIC"},
]

## 敌人图鉴说明（机制按本作实现）
const ENEMY_DESC := {
	"bone": "最常见的海嗣个体，成群漂流而来。近战，命中附带「侵蚀」。",
	"slider": "贴着海床高速滑行。近战，命中造成「神经损伤」，积满后水月会短暂僵直。",
	"stone": "远程投掷碎石；停下射击时会掘入海床，变得更难击退。",
	"offspring": "伊祖米克的子代，行动迟缓但生命很高，存活一段时间后会变异。",
	"brood": "由投嗣育母产下的诱饵，不会移动并逐渐衰亡，接触造成侵蚀。",
	"fractal": "塑路者受击时分裂出的高速碎片。",
	"tear": "伊莎玛拉渗出的泪滴，停留在原地造成真实伤害。",
	"pocket": "精英。背负气囊的爬行者，死亡时会爆裂。",
	"skimmer": "精英。低空悬浮的远程个体，射击附带侵蚀；被控制后坠落，改为近战。",
	"mother": "精英。远程攻击，并不断在身边产下注亡拟嗣。",
	"mimic": "精英。伪装成补给箱，被靠近时现形扑来；击败后掉落大量源石锭。",
	"path": "第三层 Boss。高大的刃肢海嗣，近战；受到 10 次攻击后召唤塑路者碎片。",
	"iberia": "第三层 Boss。持剑的圣徒，携带 3 发弹药；每 20 秒原地装填 2 秒，装填时被打断会僵直 6 秒。",
	"carmen": "第三层 Boss。持火铳的圣徒，射程更远；装填机制与伊比利亚相同。",
	"bishop": "第三层 Boss。与蔑死体或斥亡体成对出现；生命归零后进入假死并回复，两者同时假死才会真正倒下。",
	"archon": "接潮主教的同伴。粗壮的近战海嗣，命中附带侵蚀，同样会假死。",
	"immortal": "接潮主教的同伴。迅捷的近战海嗣，命中附带侵蚀，同样会假死。",
	"paranoia": "结局一的最终 Boss。悬浮远程散射并减速；首次被控制后失去悬浮，进入第二形态。",
	"izumik": "后续结局登场。",
	"ishar": "后续结局登场。",
}
const LOCKED := ["izumik", "ishar", "tear"]

var font: Font
var t := 0.0
var tab := 0
var sel := 0
var form := 0
var form_t := 0.0
var entries: Array = []
var tab_rects: Array = []
var tile_rects: Array = []
var form_rects: Array = []
var close_rect := Rect2()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	visible = true
	_build()


func close() -> void:
	visible = false
	Sfx.play("ui_ok")


func _process(delta: float) -> void:
	if visible:
		t += delta
		form_t += delta
		queue_redraw()


# ---------------------------------------------------------------- 数据
func _anim(label: String, name: String, fps: float, loop := true) -> Dictionary:
	var tx := A.tex(name)
	var frames := 1
	if tx != null:
		frames = max(1, tx.get_width() / tx.get_height()) if tx.get_width() >= tx.get_height() * 2 else 1
	return {"label": label, "tex": tx, "frames": frames, "fps": fps, "loop": loop}


func _anim_n(label: String, name: String, frames: int, fps: float) -> Dictionary:
	return {"label": label, "tex": A.tex(name), "frames": frames, "fps": fps, "loop": true}


func _build() -> void:
	entries.clear()
	match tab:
		0:
			var atk := "player_attack_48" if A.tex("player_attack_48") != null else "player_attack"
			entries.append({"name": "水月", "en": "MIZUKI", "tag": "主角 · 特种", "forms": [
				_anim("待机", "player_idle", 4.0), _anim("跑步", "player_run", 10.0), _anim("攻击", atk, 16.0),
				_anim("受击", "player_hurt", 6.0), _anim("倒下", "player_death", 5.0, false)],
				"stats": [], "desc": "持伞近战，挥伞横扫身前的敌人；天赋「创伤性癔症」让触手追击生命最低的敌人。\n技能：唤醒（Lv3）→ 囚徒困境（Lv10 精英化一）→ 镜花水月（Lv20 精英化二），全部自动释放；每个技能各有两段进阶。"})
			for k in D.ALLIES:
				var a: Dictionary = D.ALLIES[k]
				entries.append({"name": a.name, "en": a.en, "tag": "援护干员", "forms": [_anim_n("待机", "ally_" + k, 2, 3.0)],
					"stats": [], "desc": a.desc + "\n升级：" + a.up + "（Lv.5 / 15 / 25 时招募或升级）"})
		1, 2, 3:
			var role: String = ["", "", "elite", "boss"][tab]
			for k in D.ENEMIES:
				var e: Dictionary = D.ENEMIES[k]
				if e.get("role", "") != role:
					continue
				var forms: Array = [_anim_n("常态", e.tex, 2, 2.0 if role == "boss" else 5.0)]
				if k == "paranoia" and A.tex("e_paranoia2") != null:
					forms[0].label = "一阶段"
					forms.append(_anim_n("二阶段", "e_paranoia2", 2, 2.0))
				if A.tex(e.tex + "_feign") != null:
					forms.append(_anim_n("假死", e.tex + "_feign", 2, 2.0))
				var ai: String = {"melee": "近战", "ranged": "远程", "static": "固定"}.get(e.ai, "")
				var st := [["生命", str(int(e.hp))], ["伤害", str(int(e.dmg))], ["移速", str(int(e.spd))], ["类型", ai]]
				if e.has("range"):
					st.append(["射程", str(int(e.range))])
				var tags: Array = []
				if e.get("corrode", 0.0) > 0.0:
					tags.append("侵蚀")
				if e.get("nerve", 0.0) > 0.0:
					tags.append("神经损伤")
				if e.get("hover", false):
					tags.append("悬浮")
				if e.get("pair", false):
					tags.append("成对")
				if e.has("ammo"):
					tags.append("装填")
				entries.append({"id": k, "name": e.name, "en": k.to_upper(), "tag": ["", "普通敌人", "精英敌人", "Boss"][tab],
					"forms": forms, "stats": st, "chips": tags, "desc": ENEMY_DESC.get(k, ""), "locked": LOCKED.has(k)})
		4:
			entries.append({"name": "经验结晶", "en": "EXP", "tag": "掉落物", "forms": [_anim_n("小", "gem_small", 1, 1.0), _anim_n("大", "gem_big", 1, 1.0)], "stats": [], "desc": "击败敌人掉落，拾取后获得经验。"})
			entries.append({"name": "灯油", "en": "OIL", "tag": "掉落物", "forms": [_anim_n("灯油", "oil", 1, 1.0)], "stats": [], "desc": "补充灯火。灯火过低时敌人更快、更凶，熄灭后持续受到伤害。"})
			entries.append({"name": "源石锭", "en": "INGOT", "tag": "货币", "forms": [_anim_n("源石锭", "ingot", 1, 1.0)], "stats": [], "desc": "精英、Boss 与箱形恐鱼会掉落，可在局内商人处购买藏品与补给。"})
			entries.append({"name": "磁铁", "en": "MAGNET", "tag": "道具", "forms": [_anim_n("磁铁", "pickup_magnet", 1, 1.0)], "stats": [], "desc": "拾取后吸取全场的经验结晶、灯油与源石锭。小怪低概率掉落，精英与 Boss 必掉磁铁或回复药剂。"})
			entries.append({"name": "回复药剂", "en": "HEAL", "tag": "道具", "forms": [_anim_n("回复药剂", "pickup_heal", 1, 1.0)], "stats": [], "desc": "拾取后立即回复 30% 最大生命。"})
			entries.append({"name": "补给箱", "en": "CHEST", "tag": "宝箱", "forms": [_anim_n("补给箱", "e_chest", 2, 1.0)], "stats": [], "desc": "地图上定期出现，打开后获得藏品。其中一部分是伪装的箱形恐鱼。"})
			for sp in [["遗迹残柱", "PILLAR", "prop_pillar", 1], ["断墙", "RUINED WALL", "prop_wall", 1], ["沉船碎片", "WRECK", "prop_wreck", 1],
					["海底岩脊", "RIDGE", "terrain_ridge", 1], ["海底山峰", "PEAK", "terrain_peak", 1], ["溟痕", "MIRE", "terrain_mire", 2]]:
				if A.tex(sp[2]) != null:
					entries.append({"name": sp[0], "en": sp[1], "tag": "场景", "forms": [_anim_n(sp[0], sp[2], sp[3], 2.0)], "stats": [],
						"desc": "地面上周期性出现并逐渐扩大的溟痕，站在上面会持续受到伤害并积累神经损伤。" if sp[2] == "terrain_mire" else "深海遗迹中的场景物件，会与角色前后遮挡。"})
			entries.append({"name": "商人", "en": "MERCHANT", "tag": "NPC", "forms": [_anim_n("商人", "merchant", 2, 2.0)], "stats": [], "desc": "局内会出现 3 次，停留 60 秒。靠近即可交易：藏品、回复、灯油与刷新。"})
	sel = clampi(sel, 0, max(0, entries.size() - 1))
	form = 0
	form_t = 0.0


# ---------------------------------------------------------------- 输入
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if close_rect.has_point(event.position):
			close()
			return
		for i in tab_rects.size():
			if tab_rects[i].has_point(event.position):
				_set_tab(i)
				return
		for i in tile_rects.size():
			if tile_rects[i].has_point(event.position):
				_set_sel(i)
				return
		for i in form_rects.size():
			if form_rects[i].has_point(event.position):
				form = i
				form_t = 0.0
				Sfx.play("ui_move")
				return
	accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_Q, KEY_PAGEUP:
			_set_tab((tab + TABS.size() - 1) % TABS.size())
		KEY_E, KEY_TAB, KEY_PAGEDOWN:
			_set_tab((tab + 1) % TABS.size())
		KEY_LEFT, KEY_A:
			_set_sel(sel - 1)
		KEY_RIGHT, KEY_D:
			_set_sel(sel + 1)
		KEY_UP, KEY_W:
			_set_sel(sel - 5)
		KEY_DOWN, KEY_S:
			_set_sel(sel + 5)
		KEY_Z, KEY_X, KEY_SPACE:
			if not entries.is_empty():
				var n: int = entries[sel].forms.size()
				form = (form + (1 if event.keycode != KEY_Z else n - 1)) % n
				form_t = 0.0
				Sfx.play("ui_move")
	get_viewport().set_input_as_handled()


func _set_tab(i: int) -> void:
	if i == tab:
		return
	tab = i
	sel = 0
	Sfx.play("ui_move")
	_build()


func _set_sel(i: int) -> void:
	if entries.is_empty():
		return
	var n := clampi(i, 0, entries.size() - 1)
	if n != sel:
		sel = n
		form = 0
		form_t = 0.0
		Sfx.play("ui_move")


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 1.0))
	draw_rect(Rect2(0, 0, vs.x, 140), Color(0.03, 0.09, 0.12, 0.6))
	UI.text(self, font, Vector2(60, 64), "图鉴", 30, UI.TEXT)
	UI.en(self, font, Vector2(132, 62), "GALLERY", 13, UI.CYAN, 4.0)
	close_rect = Rect2(vs.x - 150, 34, 100, 36)
	UI.panel(self, close_rect, Color(0.03, 0.08, 0.1, 0.8), UI.LINE, 8.0)
	UI.text(self, font, close_rect.position + Vector2(0, 24), "返回  Esc", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, close_rect.size.x)
	# 分页
	tab_rects.clear()
	for i in TABS.size():
		var r := Rect2(60 + i * 128, 88, 120, 40)
		tab_rects.append(r)
		var on := i == tab
		UI.panel(self, r, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.06, 0.09, 0.7), UI.CYAN if on else Color(0.2, 0.4, 0.45, 0.5), 8.0, UI.CYAN if on else Color(0, 0, 0, 0))
		UI.text(self, font, r.position + Vector2(14, 27), TABS[i].cn, 17, UI.TEXT if on else UI.SUB)
		UI.en(self, font, r.position + Vector2(r.size.x - 8 - TABS[i].en.length() * 6.5, 25), TABS[i].en, 8, UI.CYAN if on else Color(0.3, 0.45, 0.5), 0.5)
	if tab == 5:
		_draw_relic_placeholder(vs)
	else:
		_draw_grid()
		_draw_detail(vs)
	UI.text(self, font, Vector2(0, vs.y - 22), "Q / E 切换分页 · 方向键选择 · Z / X 切换动作与形态 · Esc 返回", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _frame_rect(f: Dictionary, frame: int) -> Rect2:
	var tx: Texture2D = f.tex
	var fw: int = tx.get_width() / f.frames
	return Rect2(fw * (frame % f.frames), 0, fw, tx.get_height())


func _draw_grid() -> void:
	tile_rects.clear()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var r := Rect2(60 + (i % 5) * 110, 150 + (i / 5) * 124, 100, 114)
		tile_rects.append(r)
		var on := i == sel
		UI.panel(self, r, Color(0.05, 0.16, 0.2, 0.95) if on else Color(0.02, 0.06, 0.09, 0.8), UI.CYAN if on else Color(0.2, 0.4, 0.45, 0.45), 8.0, UI.CYAN if on else Color(0, 0, 0, 0))
		var f: Dictionary = e.forms[0]
		if f.tex != null:
			var src := _frame_rect(f, 0)
			var k: float = minf(76.0 / src.size.x, 70.0 / src.size.y)
			if k >= 2.0:
				k = floorf(k)
			var sz := src.size * k
			var c := r.position + Vector2(r.size.x / 2, 46)
			var col := Color(0, 0, 0, 0.9) if e.get("locked", false) else Color.WHITE
			draw_texture_rect_region(f.tex, Rect2((c - sz / 2).round(), sz), src, col)
		var nm: String = "???" if e.get("locked", false) else e.name
		UI.text(self, font, r.position + Vector2(2, 104), nm, 13 if nm.length() <= 6 else 11, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 4)


func _draw_detail(vs: Vector2) -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries[sel]
	var locked: bool = e.get("locked", false)
	var pr := Rect2(640, 150, vs.x - 700, vs.y - 200)
	UI.panel(self, pr, Color(0.02, 0.06, 0.09, 0.9), UI.LINE, 14.0, UI.CYAN)
	# 展示台
	var box := Rect2(pr.position + Vector2(20, 20), Vector2(260, 290))
	var base := box.position + Vector2(box.size.x / 2, box.size.y - 34)
	draw_circle(base + Vector2(0, -90), 120.0, Color(0.3, 0.8, 0.9, 0.05))
	draw_set_transform(base, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 80.0, Color(0.3, 0.8, 0.9, 0.12))
	draw_arc(Vector2.ZERO, 80.0, 0.0, TAU, 40, Color(0.3, 0.9, 0.9, 0.5), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	form = clampi(form, 0, e.forms.size() - 1)
	var f: Dictionary = e.forms[form]
	if f.tex != null:
		var fr := int(form_t * f.fps)
		fr = fr % f.frames if f.loop else mini(fr, f.frames - 1)
		var src := _frame_rect(f, fr)
		var k: float = minf(240.0 / src.size.x, 250.0 / src.size.y)
		k = floorf(minf(k, 6.0)) if k >= 1.0 else k
		var sz := src.size * k
		var col := Color(0, 0, 0, 0.95) if locked else Color.WHITE
		draw_texture_rect_region(f.tex, Rect2((base - Vector2(sz.x / 2, sz.y - 6)).round(), sz), src, col)
	# 动作 / 形态切换
	form_rects.clear()
	if e.forms.size() > 1 and not locked:
		for i in e.forms.size():
			var br := Rect2(box.position.x + i * 52, box.end.y + 8, 48, 28)
			form_rects.append(br)
			var on: bool = i == form
			UI.panel(self, br, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.06, 0.09, 0.7), UI.CYAN if on else Color(0.2, 0.4, 0.45, 0.5), 5.0)
			UI.text(self, font, br.position + Vector2(0, 19), e.forms[i].label, 12, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	# 文字
	var tx := pr.position.x + 300
	var tw := pr.end.x - tx - 20
	UI.en(self, font, Vector2(tx, pr.position.y + 40), e.en if not locked else "UNKNOWN", 11, UI.CYAN_DIM, 3.0)
	UI.text(self, font, Vector2(tx, pr.position.y + 76), e.name if not locked else "???", 26, UI.TEXT)
	draw_rect(Rect2(Vector2(tx, pr.position.y + 92), Vector2(4, 16)), UI.CYAN)
	UI.text(self, font, Vector2(tx + 12, pr.position.y + 106), e.tag, 14, UI.CYAN)
	var y := pr.position.y + 140
	if not locked:
		for s in e.stats:
			UI.text(self, font, Vector2(tx, y), s[0], 14, UI.SUB)
			UI.text(self, font, Vector2(tx + 60, y), s[1], 15, UI.TEXT)
			y += 26
		var cx := tx
		for c in e.get("chips", []):
			var w: float = 16.0 + c.length() * 14.0
			UI.panel(self, Rect2(cx, y - 4, w, 24), Color(0.2, 0.08, 0.25, 0.8), UI.PURPLE, 4.0)
			UI.text(self, font, Vector2(cx, y + 13), c, 12, UI.PURPLE, HORIZONTAL_ALIGNMENT_CENTER, w)
			cx += w + 8
	var dy := maxf(y + 34, box.end.y + 60)
	UI.rule(self, Vector2(pr.position.x + 20, dy - 18), Vector2(pr.end.x - 20, dy - 18), UI.CYAN_DIM)
	var desc: String = e.desc if not locked else "尚未遭遇。" + e.desc
	draw_multiline_string(font, Vector2(pr.position.x + 24, dy + 4), desc, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 48, 15, -1, Color(0.8, 0.9, 0.92))


func _draw_relic_placeholder(vs: Vector2) -> void:
	var r := Rect2(60, 150, vs.x - 120, vs.y - 200)
	UI.panel(self, r, Color(0.02, 0.06, 0.09, 0.9), UI.LINE, 14.0, UI.GOLD)
	for i in 60:
		var c := r.position + Vector2(60 + (i % 15) * 74, 60 + (i / 15) * 74)
		UI.diamond(self, c, 22.0, Color(0.03, 0.08, 0.1), Color(0.3, 0.4, 0.42, 0.5))
		UI.text(self, font, c + Vector2(-20, 7), "?", 18, Color(0.35, 0.45, 0.48), HORIZONTAL_ALIGNMENT_CENTER, 40)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 60), "藏品图鉴即将开放", 22, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 30), "藏品系统完成后，局内获得过的藏品会收录在这里", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
