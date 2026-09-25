extends Control
## 图鉴：展示游戏里的各类贴图（干员 / 敌人 / 精英 / Boss / 道具），藏品页待藏品系统完成后开放。
## 从标题菜单打开；Q/E 或点击切换分页，方向键或点击选择条目，Z/X 或点击切换动作/形态，Esc 返回。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Doctor = preload("res://scripts/characters/doctor.gd")
const Character = preload("res://scripts/characters/character.gd")

const TABS := [
	{"cn": "干员", "en": "OPERATOR"},
	{"cn": "敌人", "en": "ENEMY"},
	{"cn": "精英", "en": "ELITE"},
	{"cn": "Boss", "en": "BOSS"},
	{"cn": "道具", "en": "ITEM"},
	{"cn": "藏品", "en": "RELIC"},
	{"cn": "结局", "en": "ENDING"},
]
const ENDING_ORDER := ["standard", "knight", "resolve", "deep"]

## 敌人图鉴说明（机制按本作实现）
const ENEMY_DESC := {
	"bone": "最常见的海嗣个体，成群漂流而来。近战，命中附带「侵蚀」。",
	"slider": "贴着海床高速滑行。近战，命中造成「神经损伤」，积满后博士会短暂僵直。",
	"stone": "远程投掷碎石；停下射击时会掘入海床，变得更难击退。",
	"offspring": "伊祖米克的子代，行动迟缓但生命很高，存活一段时间后会变异。",
	"brood": "由投嗣育母产下的诱饵，不会移动并逐渐衰亡，接触造成侵蚀。",
	"fractal": "塑路者受击时分裂出的高速碎片。",
	"tear": "伊莎玛拉渗出的泪滴，停留在原地造成真实伤害。",
	"pocket": "精英。背负气囊的爬行者，每失去 15% 生命就鼓胀 0.4 秒后爆裂一次（范围 80，附带神经损伤），看到它发亮就离开。",
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
	"izumik": "结局四「深蓝」的最终 Boss。学习阶段无敌并放出子代，子代回到本体会被吸收；解读阶段周期释放冲击波。",
	"ishar": "结局三「抉择」的最终 Boss。渗出伊莎玛拉之泪，泪未被清除时持续充能，充满后变身。",
	"knight_boss": "结局二「最后的骑士」的最终 Boss。冲锋附带冰霜，近身长枪三连刺，周期展开寒冰领域；第一次生命归零后寒冰重生进入二阶段。",
	"knight": "精英。堕入海嗣的最后的骑士——只在同伴骑士道中阵亡后出现。直线冲锋，命中附带冰霜减速。",
}
## 结局 Boss 与敌对骑士：达成对应结局 / 遭遇后解锁
const LOCK_BY_ENDING := {"izumik": "deep", "ishar": "resolve", "knight_boss": "knight", "tear": "resolve"}
const RelicDb = preload("res://scripts/core/relic_db.gd")
var lore: Dictionary = {}       # data/lore.json
var relic_db: RefCounted
var scroll := 0                 # 网格滚动的行数
const COLS := 5
const ROWS := 4

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
## 攻击演示：把 game.tscn 以 demo_op 模式放进 SubViewport，在展示台位置画出来（见 game.gd _demo_step）
var demo_vp: SubViewport
var demo_game: Node
var demo_id := ""
## 手动切换（2026-09-26 用户要求）：阶段 0 精零 / 1 精一 / 2 精二；动作 -1 轮播 / 0–2 只放该技能 / 3 只普攻。换干员时保留，方便横向比较
var demo_stage := 2
var demo_mode := -1
var demo_rects: Array = []       # [Rect2, "stage" | "mode", 值]
const DEMO_H := 290


func _ready() -> void:
	var lf := FileAccess.open("res://data/lore.json", FileAccess.READ)
	if lf != null:
		var ld = JSON.parse_string(lf.get_as_text())
		if ld is Dictionary:
			lore = ld
	relic_db = RelicDb.new()
	relic_db.load_files()
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
	_demo_stop()
	Sfx.play("ui_ok")


## 启动 / 切换演示：同一干员不重建
func _demo_start(cid: String, sz: Vector2i) -> void:
	if demo_id == cid and demo_vp != null:
		if demo_vp.size != sz:
			demo_vp.size = sz
		return
	_demo_stop()
	demo_vp = SubViewport.new()
	demo_vp.size = sz
	demo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	demo_vp.handle_input_locally = false
	add_child(demo_vp)
	demo_game = load("res://game.tscn").instantiate()
	demo_game.demo_op = cid
	demo_game.demo_configure(demo_stage, demo_mode)
	demo_vp.add_child(demo_game)
	demo_id = cid


## 点击阶段 / 动作按钮：未解锁的技能（阶段不够）不响应
func _demo_click(kind: String, v: int) -> void:
	if kind == "stage":
		demo_stage = v
		if demo_mode >= 0 and demo_mode <= 2 and demo_mode > demo_stage:
			demo_mode = -1   # 降阶段后当前技能还没解锁：回到轮播
	else:
		if v >= 0 and v <= 2 and v > demo_stage:
			return
		demo_mode = v
	if demo_game != null:
		demo_game.demo_configure(demo_stage, demo_mode)
	Sfx.play("ui_move")


func _demo_stop() -> void:
	if demo_vp != null:
		demo_vp.queue_free()
	demo_vp = null
	demo_game = null
	demo_id = ""


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


## 博士动画预览：data/doctor.json 的 sprites（没有就用旧 2 帧待机条）
func _doctor_forms(dd: Dictionary) -> Array:
	var sp: Dictionary = dd.get("sprites", {})
	var out: Array = []
	for kind in [["待机", "idle", 4, 4.0], ["跑步", "run", 6, 10.0], ["受击", "hurt", 2, 10.0], ["倒下", "death", 4, 6.0]]:
		var n = sp.get(kind[1], "")
		if n is String and n != "" and A.tex(n) != null:
			out.append(_anim_n(kind[0], n, kind[2], kind[3]))
	if out.is_empty():
		out.append(_anim_n("待机", "doctor", 2, 2.0))
	return out


func _build() -> void:
	entries.clear()
	match tab:
		0:
			var atk := "player_attack_48" if A.tex("player_attack_48") != null else "player_attack"
			# 博士：受击体（data/doctor.json）
			var dd: Dictionary = {}
			var df := FileAccess.open("res://data/doctor.json", FileAccess.READ)
			if df != null:
				var dj = JSON.parse_string(df.get_as_text())
				if dj is Dictionary:
					dd = dj
			var ds: Dictionary = dd.get("stats", {})
			entries.append({"name": dd.get("name", "博士"), "en": dd.get("en", "DOCTOR"), "tag": "指挥 · 唯一受击体", "forms": _doctor_forms(dd),
				"stats": [["生命", str(int(ds.get("max_hp", 100)))], ["回复", "%.1f / 秒" % float(ds.get("regen", 0.0))], ["移速", str(int(ds.get("move_speed", 150)))],
					["闪避", "%d%%" % int(float(ds.get("dodge", 0.0)) * 100.0)], ["拾取", str(int(ds.get("pickup", 70)))]],
				"chips": ["移动", "受击", "拾取", "指挥"], "desc": _lore_text("doctor", "博士是场上唯一会受伤的人：用 WASD 走位、拉怪、躲弹幕、抢掉落；干员们跟在身边自动输出，不会倒下。")})
			# 干员：data/characters/*.json（职业、普攻 / 技能 / 天赋、成长线）
			for cid in Character.list_ids():
				var cd: Dictionary = Character.load_def(cid)
				var sp: Dictionary = cd.get("sprites", {})
				var st: Array = []
				if cd.has("attack"):
					st.append(["普攻", cd.attack.get("name", "")])
				var sks: Array = cd.get("skills", [])
				for si in sks.size():
					st.append(["技能 %d" % (si + 1), "%s%s · %s" % [sks[si].get("name", ""), ("（充能 %d）" % int(sks[si].sp)) if sks[si].has("sp") else "", ["招募", "精一", "精二"][si]]])
				if cd.has("talent"):
					st.append(["天赋", cd.talent.get("name", "")])
				var forms: Array = []
				for kind in [["待机", "idle", 4.0], ["跑步", "run", 10.0], ["攻击", "attack", 8.0], ["技能", "skill", 12.0], ["受击", "hurt", 6.0], ["倒下", "death", 5.0],
						["Mon3tr", "m_idle", 4.0], ["爪击", "m_attack", 14.0]]:
					if not sp.has(kind[1]):
						continue
					var v = sp[kind[1]]
					if v is String:
						forms.append(_anim(kind[0], v, kind[2], kind[1] != "death"))
					else:
						forms.append(_anim_n(kind[0], v.tex, int(v.get("frames", 2)), float(v.get("fps", kind[2]))))
				# 攻击演示：实机跑一段（弹道 / 命中 / 技能都是战斗里的真实效果）
				forms.append({"label": "演示", "tex": null, "frames": 1, "fps": 1.0, "loop": true, "demo": cid})
				var mech: String = cd.get("gallery", {}).get("desc", "")
				var lines: Array = []
				for si in cd.get("skills", []).size():
					var sk3: Dictionary = cd.skills[si]
					lines.append("S%d「%s」：%s" % [si + 1, sk3.get("name", ""), sk3.get("desc", "")])
				if cd.has("talent"):
					lines.append("天赋「%s」：%s" % [cd.talent.get("name", ""), cd.talent.get("desc", "")])
				if not lines.is_empty():
					mech += "\n" + "\n".join(lines)
				entries.append({"name": cd.get("name", cid), "en": cd.get("en", cid.to_upper()), "tag": "%s干员" % cd.get("class", ""), "forms": forms,
					"stats": st, "chips": cd.get("gallery", {}).get("tags", []), "desc": _lore_text(cid, mech)})
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
					"forms": forms, "stats": st, "chips": tags, "desc": _lore_text(k, ENEMY_DESC.get(k, "")),
					"locked": LOCK_BY_ENDING.has(k) and not Cfg.endings_cleared.has(LOCK_BY_ENDING[k]), "locked_text": "尚未遭遇。达成对应结局后收录。"})
		6:
			# 结局：四格；未达成显示 ???，达成后显示最终 Boss 立绘与一句话
			for i in ENDING_ORDER.size():
				var eid: String = ENDING_ORDER[i]
				if not D.ENDINGS.has(eid):
					continue
				var en: Dictionary = D.ENDINGS[eid]
				var bd: Dictionary = D.ENEMIES.get(en.boss, {})
				var gal: Dictionary = en.get("gallery", {})
				var forms: Array = [_anim_n("最终 Boss", bd.get("tex", "boss"), 2, 2.0)]
				if en.boss == "paranoia" and A.tex("e_paranoia2") != null:
					forms.append(_anim_n("二阶段", "e_paranoia2", 2, 2.0))
				var c = en.get("col", [0.8, 0.6, 1.0])
				entries.append({"id": eid, "name": en.name, "en": en.get("en", eid.to_upper()), "tag": "结局 · %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"][i],
					"forms": forms, "stats": [["Boss", bd.get("name", "")]], "chips": [], "col": Color(c[0], c[1], c[2]),
					"desc": gal.get("lore", "") + "\n\n触发：" + gal.get("hint", ""), "locked": not Cfg.endings_cleared.has(eid) and not OS.get_cmdline_user_args().has("--allend"), "locked_text": "尚未达成。\n\n线索：" + gal.get("hint", "")})
		5:
			# 藏品：已实装的全部列出；没获得过的显示为 ???
			var lst: Array = relic_db.implemented()
			var order := {"基础": 0, "稀有": 1, "核心": 2, "升华": 3, "遭诅古物": 4, "结局": 5}
			lst.sort_custom(func(a, b): return (order.get(a.rarity, 9) * 1000 + int(a.id)) < (order.get(b.rarity, 9) * 1000 + int(b.id)))
			for r in lst:
				var seen: bool = Cfg.seen_relics.has(r.id)
				var stt: Array = [["等级", r.rarity], ["类别", r.get("cat", "")]]
				if r.has("lanes") and not r.lanes.is_empty():
					stt.append(["流派", " / ".join(r.lanes)])
				entries.append({"id": r.id, "name": r.name, "en": "NO. " + r.id, "tag": "藏品 · " + r.rarity, "forms": [_anim_n("图标", "relic_" + r.id, 1, 1.0)],
					"stats": stt, "chips": [], "desc": r.get("desc", ""), "locked": not seen, "locked_text": "尚未获得。在一局中拿到它之后会收录到这里。"})
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


## 介绍文字：lore.json 的档案文字在前，机制说明在后
func _lore_text(key: String, mech: String) -> String:
	var lr: String = str(lore.get(key, {}).get("lore", ""))
	if lr != "" and tab == 0:
		var first: String = lr.split("\n")[0]
		return first + ("\n" + mech if mech != "" else "")
	var l: Dictionary = lore.get(key, {})
	var out: String = l.get("lore", "")
	if out != "" and mech != "":
		out += "\n\n" + mech
	elif out == "":
		out = mech
	return out


# ---------------------------------------------------------------- 输入
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP):
		var max_scroll: int = maxi(0, ceili(entries.size() / float(COLS)) - ROWS)
		scroll = clampi(scroll + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, max_scroll)
		accept_event()
		return
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
		for dr0 in demo_rects:
			if dr0[0].has_point(event.position):
				_demo_click(dr0[1], dr0[2])
				accept_event()
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
	scroll = 0
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
	var row: int = sel / COLS
	if row < scroll:
		scroll = row
	elif row >= scroll + ROWS:
		scroll = row - ROWS + 1


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 1.0))
	for i in 4:
		var lx := vs.x * 0.15 + i * vs.x * 0.24 + sin(t * 0.25 + i) * 30.0
		var lw := 50.0 + 24.0 * sin(t * 0.4 + i * 1.7)
		draw_colored_polygon(PackedVector2Array([Vector2(lx, 0), Vector2(lx + lw, 0), Vector2(lx + lw * 2.4 - 160, vs.y), Vector2(lx - 160, vs.y)]), Color(0.33, 0.92, 0.88, 0.02 + 0.01 * sin(t * 0.7 + i)))
	draw_rect(Rect2(0, 0, vs.x, 140), Color(0.03, 0.09, 0.12, 0.6))
	UI.text(self, font, Vector2(60, 64), "图鉴", 30, UI.TEXT)
	UI.en(self, font, Vector2(132, 62), "GALLERY", 13, UI.CYAN, 4.0)
	close_rect = Rect2(vs.x - 150, 34, 100, 36)
	UI.panel(self, close_rect, Color(0.03, 0.08, 0.1, 0.8), UI.LINE, 8.0)
	UI.text(self, font, close_rect.position + Vector2(0, 24), Pad.hint("返回  Esc", "返回  Ⓑ"), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, close_rect.size.x)
	# 分页
	tab_rects.clear()
	for i in TABS.size():
		var r := Rect2(60 + i * 128, 88, 120, 40)
		tab_rects.append(r)
		var on := i == tab
		UI.panel(self, r, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.06, 0.09, 0.7), UI.CYAN if on else Color(0.2, 0.4, 0.45, 0.5), 8.0, UI.CYAN if on else Color(0, 0, 0, 0))
		UI.text(self, font, r.position + Vector2(14, 27), TABS[i].cn, 17, UI.TEXT if on else UI.SUB)
		UI.en(self, font, r.position + Vector2(r.size.x - 8 - TABS[i].en.length() * 6.5, 25), TABS[i].en, 8, UI.CYAN if on else Color(0.3, 0.45, 0.5), 0.5)
	_draw_grid()
	_draw_detail(vs)
	if entries.size() > COLS * ROWS:
		var max_scroll: int = maxi(0, ceili(entries.size() / float(COLS)) - ROWS)
		UI.text(self, font, Vector2(60, vs.y - 34), "滚轮翻页  %d / %d" % [scroll + 1, max_scroll + 1], 12, UI.SUB)
	UI.text(self, font, Vector2(0, vs.y - 22), Pad.hint("Q / E 切换分页 · 方向键选择 · Z / X 切换动作与形态 · Esc 返回", "LB / RB 切换分页 · 摇杆选择 · Ⓧ / Ⓨ 切换动作与形态 · Ⓑ 返回"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _frame_rect(f: Dictionary, frame: int) -> Rect2:
	var tx: Texture2D = f.tex
	var fw: int = tx.get_width() / f.frames
	return Rect2(fw * (frame % f.frames), 0, fw, tx.get_height())


func _draw_grid() -> void:
	tile_rects.clear()
	var max_scroll: int = maxi(0, ceili(entries.size() / float(COLS)) - ROWS)
	scroll = clampi(scroll, 0, max_scroll)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row: int = i / COLS - scroll
		var r := Rect2(60 + (i % COLS) * 110, 150 + row * 124, 100, 114)
		tile_rects.append(r)
		if row < 0 or row >= ROWS:
			tile_rects[i] = Rect2()
			continue
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
	UI.panel(self, pr, Color(0.02, 0.06, 0.09, 0.9), UI.LINE, 14.0, UI.CYAN, 71, t)
	form = clampi(form, 0, e.forms.size() - 1)
	var f: Dictionary = e.forms[form]
	var demo: bool = f.has("demo") and not locked
	# 展示台（演示时换成横贯面板的实机画面，名称 / 属性文字让位）
	var box := Rect2(pr.position + Vector2(20, 20), Vector2(260, DEMO_H if demo else 236))
	if demo:
		var dr := Rect2(box.position, Vector2(pr.size.x - 40, DEMO_H))
		_demo_start(f.demo, Vector2i(dr.size))
		if demo_vp != null:
			draw_texture_rect(demo_vp.get_texture(), dr, false)
		draw_rect(dr, Color(0.3, 0.9, 0.9, 0.5), false, 1.0)
		UI.en(self, font, dr.position + Vector2(12, 20), e.en, 11, UI.CYAN, 3.0)
		UI.text(self, font, dr.position + Vector2(12, 44), "%s · 攻击演示" % e.name, 18, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		# 两排可点按钮（右上角）：阶段 精零 / 精一 / 精二；动作 普攻 / 一技能 / 二技能 / 三技能 / 轮播
		demo_rects.clear()
		var cur: int = -9
		if demo_game != null and demo_game.demo_pi >= 0 and not demo_game.demo_phases.is_empty():
			cur = demo_game.demo_phases[demo_game.demo_pi]
		var rows := [
			["stage", [["精零", 0], ["精一", 1], ["精二", 2]]],
			["mode", [["普攻", 3], ["一技能", 0], ["二技能", 1], ["三技能", 2], ["轮播", -1]]],
		]
		for ri in rows.size():
			var kind: String = rows[ri][0]
			var cx := dr.end.x - 12.0
			var items: Array = rows[ri][1]
			for ii in range(items.size() - 1, -1, -1):
				var lbl: String = items[ii][0]
				var v: int = items[ii][1]
				var w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
				cx -= w
				var cr := Rect2(Vector2(cx, dr.position.y + 10 + ri * 28), Vector2(w, 22))
				var on: bool = (demo_stage == v) if kind == "stage" else (demo_mode == v)
				var locked_skill: bool = kind == "mode" and v >= 0 and v <= 2 and v > demo_stage
				var playing: bool = kind == "mode" and demo_mode == -1 and v == cur and not demo_game.demo_basic
				var edge: Color = UI.CYAN if on else (Color(0.5, 0.8, 0.9, 0.7) if playing else UI.LINE)
				UI.panel(self, cr, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.05, 0.08, 0.6), edge, 4.0)
				UI.text(self, font, cr.position + Vector2(0, 16), lbl, 12, Color(0.35, 0.4, 0.45) if locked_skill else (UI.TEXT if on or playing else UI.SUB), HORIZONTAL_ALIGNMENT_CENTER, w, 2)
				demo_rects.append([cr, kind, v])
				cx -= 6.0
		if demo_game != null:
			UI.text(self, font, dr.position + Vector2(12, 68), demo_game.demo_label, 14, UI.CYAN, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	else:
		demo_rects.clear()
		_demo_stop()
	var base := box.position + Vector2(box.size.x / 2, box.size.y - 34)
	if not demo:
		draw_circle(base + Vector2(0, -90), 120.0, Color(0.3, 0.8, 0.9, 0.05))
		draw_set_transform(base, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 80.0, Color(0.3, 0.8, 0.9, 0.12))
		draw_arc(Vector2.ZERO, 80.0, 0.0, TAU, 40, Color(0.3, 0.9, 0.9, 0.5), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if f.tex != null:
		var fr := int(form_t * f.fps)
		fr = fr % f.frames if f.loop else mini(fr, f.frames - 1)
		var src := _frame_rect(f, fr)
		var k: float = minf(240.0 / src.size.x, 200.0 / src.size.y)
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
	var y := pr.position.y + 140
	if not demo:
		UI.en(self, font, Vector2(tx, pr.position.y + 40), e.en if not locked else "UNKNOWN", 11, UI.CYAN_DIM, 3.0)
		UI.text(self, font, Vector2(tx, pr.position.y + 76), e.name if not locked else "???", 26, UI.TEXT)
		draw_rect(Rect2(Vector2(tx, pr.position.y + 92), Vector2(4, 16)), UI.CYAN)
		UI.text(self, font, Vector2(tx + 12, pr.position.y + 106), e.tag, 14, UI.CYAN)
	if not locked and not demo:
		for s in e.stats:
			UI.text(self, font, Vector2(tx, y), s[0], 14, UI.SUB)
			UI.text(self, font, Vector2(tx + 60, y), s[1], 15, UI.TEXT)
			y += 26
		# 标签行放在动作按钮行之下，避免与按钮重叠
		if e.forms.size() > 1:
			y = maxf(y, box.end.y + 52)
		var cx := tx
		for c in e.get("chips", []):
			var w: float = 16.0 + c.length() * 14.0
			UI.panel(self, Rect2(cx, y - 4, w, 24), Color(0.2, 0.08, 0.25, 0.8), UI.PURPLE, 4.0)
			UI.text(self, font, Vector2(cx, y + 13), c, 12, UI.PURPLE, HORIZONTAL_ALIGNMENT_CENTER, w)
			cx += w + 8
	var dy := maxf(y + 42, box.end.y + 60)
	UI.rule(self, Vector2(pr.position.x + 20, dy - 18), Vector2(pr.end.x - 20, dy - 18), UI.CYAN_DIM)
	var desc: String = e.desc if not locked else e.get("locked_text", "尚未遭遇。" + e.desc)
	# 介绍文字：按剩余高度自适应字号（15 → 12），仍放不下则按行裁切，不越出面板
	var avail := pr.end.y - 16.0 - (dy + 4)
	var fs := 15
	var soft := UI.soft(desc)
	while fs > 11 and font.get_multiline_string_size(soft, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 48, fs, -1, UI.BRK).y > avail:
		fs -= 1
	var lh := font.get_height(fs)
	var max_lines := maxi(1, int(avail / lh))
	draw_multiline_string(font, Vector2(pr.position.x + 24, dy + 4), soft, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 48, fs, max_lines, Color(0.8, 0.9, 0.92), UI.BRK)
