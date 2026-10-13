extends Control
## 图鉴：干员 / 敌人 / 精英 / Boss / 道具 / 藏品 / 结局。版式 C4'（docs/58 §8 / §11，10-11 用户定）：左暗舞台 + 右浅色终端面板、
## 平行四边形页签、黄黑警示条、警示黄 #FFCE00（docs/37：只用于图鉴）；干员页三页签 档案 / 技能 / 成长。
## 从标题菜单打开（斜切黑带转场）；Q/E 或点击切换分页，方向键或点击选择条目（最左一列再 ← 进职业轨），Z/X 或点击切换动作/形态，
## Enter / 1–3 或点击切换干员页签，Esc 返回；手柄经 Pad 翻译成同样的键；触屏用 740×360 手机版式。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Doctor = preload("res://scripts/characters/doctor.gd")
const Character = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UIMo = preload("res://scripts/ui_motion.gd")
const InitialStats = preload("res://scripts/screens/initial_stats.gd")

const TABS := [
	{"cn": "干员", "en": "OPERATOR"},
	{"cn": "敌人", "en": "ENEMY"},
	{"cn": "精英", "en": "ELITE"},
	{"cn": "Boss", "en": "BOSS"},
	{"cn": "道具", "en": "ITEM"},
	{"cn": "藏品", "en": "RELIC"},
	{"cn": "结局", "en": "ENDING"},
]
const ENDING_ORDER := ["standard", "knight", "deep", "resolve"]   # 显示编号 Ⅰ–Ⅳ（按原作：深蓝之心线 = 结局三，抉择线 = 结局四；id 不变，存档不错位）

## 敌人图鉴说明（机制按本作实现）
const ENEMY_DESC := {
	"bone": "最常见的海嗣个体，成群漂流而来。近战，命中附带「侵蚀」。",
	"slider": "贴着海床高速滑行。近战；冲刺撞上队长时额外熄灭 8 点灯火。",
	"stone": "远程投掷碎石；停下射击时会掘入海床，变得更难击退。",
	"offspring": "伊祖米克的子代，行动迟缓但生命很高；碰到队长时蜕变成 2 只其他海嗣。",
	"brood": "由投嗣育母产下的诱饵，不会移动并逐渐衰亡，接触造成侵蚀。",
	"fractal": "塑路者碎裂时放出的高速碎片。",
	"spitter": "远程抛射酸液：落点先出预警，落地造成范围伤害并留下溟痕，命中附带侵蚀。",
	"tear": "伊莎玛拉人形阶段留下的泪滴，不会伤害队长；未被压制时会加快转化充能。队长靠近泪滴即可压制，转化后泪滴消失。",
	"pocket": "精英。背负气囊的爬行者，每失去 15% 生命就鼓胀 0.8 秒后爆裂一次（范围 80），两次爆裂至少间隔 1.2 秒；看到它发亮就离开。",
	"skimmer": "精英。低空悬浮的远程个体，射击附带侵蚀；被控制后坠落，改为近战。",
	"mother": "精英。远程攻击，并不断在身边产下注亡拟嗣。",
	"mimic": "精英。伪装成补给箱，被靠近时现形扑来；击败后掉落大量源石锭。",
	"path": "中期 Boss（3:30 / 7:00）。高大的刃肢海嗣：直线冲撞、近身震地；生命降到 75% / 50% / 25% 时各碎裂一次，放出 4 块塑路者碎片。",
	"iberia": "中期 Boss（7:00）。圣徒卡门的强化状态（同一人物，同局只会出现一位）：血量与攻击更高，手炮只装 1 发，打空就近身追击；装填 2.2 秒，读条中累计受到伤害或被冲刺穿身会被打断、跪地露出破绽；「裁决」射线贯穿全屏。",
	"carmen": "中期 Boss（3:30 / 7:00）。持手炮的年迈圣徒（与伊比利亚是同一人物，同局只会出现一位）：3 发弹药，打空后近身追击并装填 3 秒，读条可被打断；第二幕弹药打空先用炮身近战 8 秒（突进、横扫）再装填。",
	"bishop": "中期 Boss（7:00）。与蔑死体或斥亡体成对出现；生命归零后进入假死并回复，两者同时假死才会真正倒下；一方假死时，存活者沿生命连接发起「接潮共鸣」。",
	"archon": "接潮主教的同伴。粗壮的近战海嗣，命中附带侵蚀，同样会假死；搭档假死时沿生命连接反击。",
	"immortal": "接潮主教的同伴。迅捷的近战海嗣，命中附带侵蚀，同样会假死；搭档假死时沿生命连接反击。",
	"paranoia": "结局一「平凡即是喜乐」的最终 Boss。悬浮远程散射并减速；打到 1/3 血时坠落，进入近战的第二形态；归零时结茧，打破外壳可抢到破绽。",
	"izumik": "结局四「如星空般深蓝」的最终 Boss。学习阶段无敌并放出子代，子代回到本体会被吸收；解读阶段周期释放冲击波。",
	"ishar": "结局三「息潮的代价」的最终 Boss。人形阶段治疗受伤海嗣，不攻击队长，干员也不会以她为目标；转化充能随时间增长，未被队长靠近压制的之泪会加快充能。充满后变为敌对白壳海嗣，使用弹幕、潮汐吐息与近身潮噬；未压制的泪滴会在变身后发动「泪滴共鸣」。",
	"knight_boss": "结局二「静谧时代」的最终 Boss。冲锋附带冰霜，近身长枪三连刺，周期展开寒冰领域；「冰线」之后发动「寒冷追击」，第一次生命归零后寒冰重生进入二阶段。",
	"knight": "精英。倒向海嗣的最后的骑士，只在猎潮的骑士（结局二路线）倒下后出现。直线冲锋，命中附带冰霜减速。",
}
const RelicDb = preload("res://scripts/core/relic_db.gd")
var lore: Dictionary = {}       # data/lore.json
var relic_db: RefCounted
var scroll := 0                 # 网格滚动的行数
var font: Font
var t := 0.0
var tab := 0
var sel := 0
var form := 0
var form_t := 0.0
var entries: Array = []
## 攻击演示：把 game.tscn 以 demo_op 模式放进 SubViewport，在展示台位置画出来（见 scripts/run/demo.gd）
var demo_vp: SubViewport
var demo_game: Node
var demo_id := ""
## 手动切换（2026-09-26 用户要求）：阶段 0 精零 / 1 精一 / 2 精二；动作 -1 轮播 / 0–2 只放该技能 / 3 只普攻。换干员时保留，方便横向比较
var demo_stage := 2
var enemy_demo_mode := 0
var demo_mode := -1
## 干员详情的信息页：档案 / 技能 / 成长（docs/58 §11，10-11 用户定：不要藏品契合、不要战绩；旧「数值」页并进技能页顶部的大数字）
var info_tab := 0
const INFO_TABS := ["档案", "属性", "技能", "成长"]   # 属性：主控数值表（与选人「属性」页同源，InitialStats.sheet）
## 敌人图鉴的附加形态（标签, 贴图, 帧数, 帧率, 循环）：说明里写了第二形态的 Boss（docs/48 验收 P2-6）
const EXTRA_FORMS := {
	"ishar": [["变身", "e_ishar_transform", 6, 7.0, false], ["变身移动", "e_ishar_t_move", 4, 5.0, true], ["变身攻击", "e_ishar_t_attack", 4, 8.0, true]],
	"knight_boss": [["冲刺", "e_knight_charge", 4, 8.0, true], ["插枪", "e_knight_plant", 4, 8.0, false], ["冲锋形态", "e_knight_charge_form", 4, 8.0, true]],
	# Codex V13（art/requests/v13_codex_boss_p2.md）；伊比利亚射击、伊祖米克地波蓄力是 _attack，已由上面的通用「攻击」行展示
	"carmen": [["炮身近战", "e_saint_melee", 4, 12.0, true], ["装弹", "e_saint_reload", 4, 6.0, true]],   # V15 圣徒统一造型
	"iberia": [["炮身近战", "e_saint_dark_melee", 4, 12.0, true], ["装弹", "e_saint_dark_reload", 4, 6.0, true]],
	"izumik": [["扎根", "e_izumik_rooting", 4, 3.0, true]],
	"path": [["冲撞", "e_path_charge", 4, 10.0, true]],
}


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
	# 画面分三层：背后层（舞台）→ 背缓冲拷贝 → 玻璃层（面板底磨砂）→ 本节点（顶栏 / 名册 / 面板正文）
	back_ci = Control.new()
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	glass_ci = Control.new()
	for c in [back_ci, bbc, glass_ci]:
		c.show_behind_parent = true
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
	back_ci.draw.connect(_draw_back)
	glass_ci.draw.connect(_draw_glass)
	var sh = load("res://shaders/ui_glass.gdshader")
	if sh is Shader:
		glass_mat = ShaderMaterial.new()
		glass_mat.shader = sh
		glass_mat.set_shader_parameter("tint", Color(UI.C_L_BG.r, UI.C_L_BG.g, UI.C_L_BG.b, 0.70))
	if Cfg.dev_args().has("--noglassfx"):
		glass_fx = false
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	glow_tex = gt


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	_build()
	_restart_open()


func close() -> void:
	visible = false
	rail_focus = false
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
	demo_game.demo_sys.configure(demo_stage, demo_mode)
	demo_vp.add_child(demo_game)
	demo_id = cid


## 敌人预览复用同一 game 场景，但逐帧由独立 enemy_demo 模块运行正式敌方 AI。
func _enemy_demo_start(eid: String, sz: Vector2i) -> void:
	if demo_id == "enemy:" + eid and demo_vp != null:
		demo_vp.size = sz
		return
	_demo_stop()
	demo_vp = SubViewport.new()
	demo_vp.size = sz
	demo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	demo_vp.handle_input_locally = false
	add_child(demo_vp)
	demo_game = load("res://game.tscn").instantiate()
	demo_game.demo_op = "mizuki"    # 沿用演示场景的 HUD、音乐、玩家输入隔离
	demo_game.demo_enemy = eid
	demo_game.enemy_demo.configure(enemy_demo_mode)
	demo_vp.add_child(demo_game)
	demo_id = "enemy:" + eid


## 点击阶段 / 动作按钮：未解锁的技能（阶段不够）不响应
func _demo_click(kind: String, v: int) -> void:
	if kind in ["enemy_phase", "enemy_replay"]:
		if kind == "enemy_phase":
			enemy_demo_mode = v
		if demo_game != null:
			demo_game.enemy_demo.configure(enemy_demo_mode)
		Sfx.play("ui_move")
		return
	if kind == "stage":
		demo_stage = v
		if demo_mode >= 0 and demo_mode <= 2 and demo_mode > demo_stage:
			demo_mode = -1   # 降阶段后当前技能还没解锁：回到轮播
	else:
		if v >= 0 and v <= 2 and v > demo_stage:
			return
		demo_mode = v
	if demo_game != null:
		demo_game.demo_sys.configure(demo_stage, demo_mode)
	Sfx.play("ui_move")


func _demo_stop() -> void:
	if demo_vp != null:
		demo_vp.queue_free()
	demo_vp = null
	demo_game = null
	demo_id = ""


func _process(delta: float) -> void:
	if not visible:
		return
	UIMo.advance(delta)
	t += delta
	form_t += delta
	# 悬停：120 ms 抬 4 px（触屏不认悬停；减少动态时直接到位）
	var hov := -1
	if not phone() and not Pad.touch:
		var mp := _design(get_local_mouse_position())
		for h in hits:
			if h[1] == "card" and h[0].has_point(mp):
				hov = h[2]
	for i in vlist:
		var target := 1.0 if (i == hov and i != sel) else 0.0
		var cur: float = hover.get(i, 0.0)
		if cur != target:
			hover[i] = target if UIMo.rm() else move_toward(cur, target, delta / 0.12)
	queue_redraw()
	back_ci.queue_redraw()
	glass_ci.queue_redraw()


# ---------------------------------------------------------------- 数据
func _anim(label: String, name: String, fps: float, loop := true) -> Dictionary:
	var tx := A.tex(name)
	var frames := 1
	if tx != null:
		frames = max(1, tx.get_width() / tx.get_height()) if tx.get_width() >= tx.get_height() * 2 else 1
	return {"label": label, "tex": tx, "frames": frames, "fps": fps, "loop": loop}


func _anim_n(label: String, name: String, frames: int, fps: float, loop := true) -> Dictionary:
	return {"label": label, "tex": A.tex(name), "frames": frames, "fps": fps, "loop": loop}


## 干员 json 的 sprites 项：字符串（帧数按宽高比推算）或 {tex, frames, fps}
func _sprite_form(label: String, v, fps: float, loop: bool) -> Dictionary:
	if v is String:
		return _anim(label, v, fps, loop)
	return _anim_n(label, v.tex, int(v.get("frames", 2)), float(v.get("fps", fps)), loop)


## 博士动画预览：data/doctor.json 的 sprites（没有就用旧 2 帧待机条）
func _doctor_forms(dd: Dictionary) -> Array:
	var sp: Dictionary = dd.get("sprites", {})
	var out: Array = []
	for kind in [["待机", "idle", 4, 4.0], ["跑步", "run", 6, 10.0], ["受击", "hurt", 2, 10.0], ["倒下", "death", 4, 6.0]]:
		var n = sp.get(kind[1], "")
		if n is String and n != "" and A.tex(n) != null:
			out.append(_anim_n(kind[0], n, kind[2], kind[3], kind[1] != "death"))   # 倒下播一次停在末帧
	if out.is_empty():
		out.append(_anim_n("待机", "doctor", 2, 2.0))
	return out


func _build() -> void:
	entries.clear()
	match tab:
		0:
			# 干员：data/characters/*.json（新干员自动出现）；顺序同选人页：封面干员水月在前，其余按职业；博士放最后
			var ops: Array = []
			for cid in Character.list_ids():
				ops.append(_op_entry(cid, Character.load_def(cid)))
			ops.sort_custom(func(x, y):
				var kx: int = 0 if x.id == "mizuki" else 1
				var ky: int = 0 if y.id == "mizuki" else 1
				if kx != ky:
					return kx < ky
				var cx: int = CLASS_ORDER.find(x.cls)
				var cy: int = CLASS_ORDER.find(y.cls)
				return cx < cy if cx != cy else x.id < y.id)
			entries.append_array(ops)
			entries.append(_doctor_entry())
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
				if k == "ishar" and A.tex("e_ishar_t") != null:
					forms.append(_anim_n("转化后", "e_ishar_t", 2, 2.0))   # 转化形态素材已交付（docs/38 §6.2），实战接入在伊莎玛拉纵切
				# 美术 V8 新敌人：另列移动 / 攻击与附加帧条（休眠 / 唤醒 / 狂暴）
				if e.get("atk_anim", false) or role == "boss":
					for fm in [["移动", "_move", 4, float(e.get("move_fps", 6.0))], ["攻击", "_attack", 4, 10.0], ["休眠", "_dormant", 2, 3.0], ["唤醒", "_awaken", 4, 10.0], ["狂暴", "_enraged", 2, 5.0]]:
						if A.tex(e.tex + fm[1]) != null:
							forms.append(_anim_n(fm[0], e.tex + fm[1], fm[2], fm[3]))
				# 说明里写了第二形态的 Boss：把已交付的形态帧条列出来（伊莎玛拉变身 / 骑士插枪、冲锋形态）
				for fm in EXTRA_FORMS.get(k, []):
					if A.tex(fm[1]) != null:
						forms.append(_anim_n(fm[0], fm[1], fm[2], fm[3], fm[4]))
				# 换色复用贴图的怪（撕裂者 / 潜地者 / 吐酸者 / 巨骸）：展示台按 enemies.json 的 tint 染色、按 draw_scale 放大（和实战一致）
				var tint: Color = e.get("tint", Color.WHITE)
				var dsc: float = float(e.get("draw_scale", 1.0))
				for fm in forms:
					fm.tint = tint
					fm.dscale = float(e.get("transformed_draw_scale", 1.0)) if k == "ishar" and fm.label in ["转化后", "变身", "变身移动", "变身攻击"] else dsc
					if fm.label == "二阶段" and k == "paranoia":
						pass   # 同实战：V13 终稿自带洋红配色和 ×1.10 体量，不再染色、不放大
				forms.append({"label": "攻击演示", "tex": null, "frames": 1, "fps": 1.0, "loop": true, "enemy_demo": k})
				var ai: String = {"melee": "近战", "ranged": "远程", "static": "固定"}.get(e.ai, "")
				var st := [["生命", str(int(e.hp))], ["伤害", str(int(e.dmg))], ["移速", str(int(e.spd))], ["类型", ai]]
				if e.has("range"):
					st.append(["射程", str(int(e.range))])
				if float(e.get("draw_scale", 1.0)) > 1.05:
					st.append(["体型", "×%.1f" % float(e.draw_scale)])
				var tags: Array = []
				if e.get("corrode", 0.0) > 0.0:
					tags.append("侵蚀")
				# 命中附带神经损伤缺省不生效（enemy/nerve_hit_mult = 0，神经只由溟痕 / 巢涌者光环累积）：倍率打开了才标
				if (e.get("nerve", 0.0) > 0.0 or e.get("shot_nerve", 0.0) > 0.0) and Bal.v("enemy/nerve_hit_mult", 0.0) > 0.0:
					tags.append("神经损伤")
				if e.get("hover", false):
					tags.append("悬浮")
				if e.get("pair", false):
					tags.append("成对")
				if e.has("ammo"):
					tags.append("装填")
				tags.append_array(e.get("chips", []))
				var mech: String = ENEMY_DESC.get(k, e.get("desc", ""))
				if e.has("extra"):
					mech += "\n\n第二招：%s（%s）。" % [str(e.extra.name), {"swipe": "扇形扫击", "pulse": "近身震爆", "pierce": "直线突刺", "volley": "扇形弹幕"}.get(str(e.extra.mode), "攻击")]
					if float(e.extra.get("frost", 0.0)) > 0.0:
						mech += "命中附加短暂寒冷。"
					if float(e.extra.get("nerve", 0.0)) > 0.0 and Bal.v("enemy/nerve_hit_mult", 0.0) > 0.0:
						mech += "命中累积神经损伤。"
					if float(e.extra.get("stun", 0.0)) > 0.0:
						mech += "命中造成短暂僵直，连续命中有保护间隔。"
				if e.has("patterns"):
					var moves: Array[String] = []
					for move in e.patterns:
						moves.append(str(move.name))
					mech += "\n\n攻击模式：" + " / ".join(moves) + "。"
				entries.append({"id": k, "name": e.name, "en": k.to_upper(), "tag": ["", "普通敌人", "精英敌人", "Boss"][tab],
					"forms": forms, "stats": st, "chips": tags, "desc": _lore_text(k, mech),
					"locked": not Cfg.unlock_all and not Cfg.gallery_seen.has("enemy:" + str(k)), "locked_text": "尚未遭遇。在探索中遇到后收录。"})
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
					"desc": gal.get("lore", "") + "\n\n触发：" + gal.get("hint", ""), "locked": not Cfg.endings_cleared.has(eid) and not Cfg.dev_args().has("--allend"), "locked_text": "尚未达成。\n\n线索：" + gal.get("hint", "")})
		5:
			# 藏品：已实装的全部列出；没获得过的显示为 ???（开发参数 --allrelics：连未实装的也列出并解锁，用来检查图标）
			var all_relics: bool = Cfg.dev_args().has("--allrelics")
			var lst: Array = relic_db.items.values() if all_relics else relic_db.implemented()
			var order := {"基础": 0, "稀有": 1, "核心": 2, "升华": 3, "遭诅古物": 4, "结局": 5}
			lst.sort_custom(func(a, b): return (order.get(a.rarity, 9) * 1000 + int(a.id)) < (order.get(b.rarity, 9) * 1000 + int(b.id)))
			for r in lst:
				var seen: bool = Cfg.seen_relics.has(r.id)
				var stt: Array = [["等级", r.rarity], ["效果分类", relic_db.effect_category_names.get(r.effect_category, r.get("cat", ""))], ["原类别", r.get("cat", "")]]
				if r.has("lanes") and not r.lanes.is_empty():
					stt.append(["流派", " / ".join(r.lanes.map(func(l): return "%s %s" % [l, str(relic_db.lane_names.get(l, "")).split("（")[0]]))])
				entries.append({"id": r.id, "name": r.name, "en": "NO. " + r.id, "tag": "藏品 · " + r.rarity + ("" if r.implemented else " · 未实装"), "forms": [_anim_n("图标", "relic_" + r.id, 1, 1.0)],
					"stats": stt, "chips": [], "desc": r.get("desc", ""), "locked": not seen and not all_relics, "locked_text": "尚未获得。在探索中拿到后收录。"})
		4:
			entries.append({"name": "经验结晶", "en": "EXP", "tag": "掉落物", "forms": [_anim_n("小", "gem_small", 1, 1.0), _anim_n("大", "gem_big", 1, 1.0)], "stats": [], "desc": "击败敌人掉落，拾取后获得经验。"})
			entries.append({"name": "灯油", "en": "OIL", "tag": "掉落物", "forms": [_anim_n("灯油", "oil", 1, 1.0)], "stats": [], "desc": "补充灯火。灯火低于 30 时敌人移速与伤害 +20%；灯火归零后每秒失去 3 点生命。"})
			entries.append({"name": "源石锭", "en": "INGOT", "tag": "货币", "forms": [_anim_n("源石锭", "ingot", 1, 1.0)], "stats": [], "desc": "精英、Boss 与箱形恐鱼会掉落，可在商人处购买藏品与补给。最后一位商人离开后，剩余和之后获得的源石锭会熔铸为全队伤害。"})
			entries.append({"name": "磁铁", "en": "MAGNET", "tag": "道具", "forms": [_anim_n("磁铁", "pickup_magnet", 1, 1.0)], "stats": [], "desc": "拾取后吸取全场的经验结晶、灯油与源石锭。小怪低概率掉落，精英与 Boss 必掉磁铁或回复药剂。"})
			entries.append({"name": "回复药剂", "en": "HEAL", "tag": "道具", "forms": [_anim_n("回复药剂", "pickup_heal", 1, 1.0)], "stats": [], "desc": "拾取后立即回复 30% 最大生命。小怪低概率掉落，队长生命低于 70% 时掉率翻倍；精英与 Boss 必掉磁铁或回复药剂。"})
			entries.append({"name": "补给箱", "en": "CHEST", "tag": "宝箱", "forms": [_anim_n("补给箱", "e_chest", 2, 1.0)], "stats": [], "desc": "地图上定期出现，打开后获得藏品。其中一部分是伪装的箱形恐鱼。"})
			for sp in [["遗迹残柱", "PILLAR", "prop_pillar", 1], ["断墙", "RUINED WALL", "prop_wall", 1], ["沉船碎片", "WRECK", "prop_wreck", 1],
					["海底岩脊", "RIDGE", "terrain_ridge", 1], ["海底山峰", "PEAK", "terrain_peak", 1], ["溟痕", "MIRE", "terrain_mire", 2], ["引航灯标", "BEACON", "prop_beacon", 2]]:
				if A.tex(sp[2]) != null:
					entries.append({"name": sp[0], "en": sp[1], "tag": "场景", "forms": [_anim_n(sp[0], sp[2], sp[3], 2.0)], "stats": [],
						"desc": {"terrain_mire": "地面上周期性出现并逐渐扩大的溟痕。站在上面会减速、持续受伤并累积神经损伤；点燃引航灯标可以驱散。", "prop_beacon": "仿照伊比利亚灯塔做的小型信标，熄灭着立在海床上。站进光圈点燃它，灯光会驱散周围的溟痕、清空神经损伤，这片地方也暂时不会再长出溟痕。"}.get(sp[2], "深海遗迹中的场景物件，会与角色前后遮挡。")})
			entries.append({"name": "商人", "en": "MERCHANT", "tag": "NPC", "forms": [_anim_n("商人", "merchant", 2, 2.0)], "stats": [], "desc": "每次探索出现 3 次，每次停留 60 秒。靠近即可交易：藏品、回复、灯油与刷新。"})
	if tab == 4:
		for entry in entries:
			entry["locked"] = not Cfg.unlock_all and not Cfg.gallery_seen.has("item:" + str(entry.en))
			entry["locked_text"] = "尚未发现。在探索中遇到后收录。"
	sel = clampi(sel, 0, max(0, entries.size() - 1))
	_rebuild_view()
	if not vlist.is_empty() and not vlist.has(sel):
		sel = vlist[0]
	form = 0
	form_t = 0.0
	_follow()


## 干员条目：形态（专属动作帧条 + 实机演示）、名册卡 / 立绘源（待机帧条）、职业色、精英阶段数
func _op_entry(cid: String, cd: Dictionary) -> Dictionary:
	var sp: Dictionary = cd.get("sprites", {})
	var forms: Array = []
	# 专属动作（docs/32 验收 §2 接线的新帧条）：有就列出来，没有就跳过
	for kind in [["待机", "idle", 4.0], ["跑步", "run", 10.0], ["攻击", "attack", 8.0], ["技能", "skill", 12.0],
			["号令", "command", 12.0], ["治疗", "skill_heal", 12.0], ["旋斩", "attack_spin", 12.0], ["倒下", "fall", 10.0],
			["受击", "hurt", 6.0], ["倒下", "death", 5.0]]:
		if not sp.has(kind[1]):
			continue
		var fm: Dictionary = _sprite_form(kind[0], sp[kind[1]], kind[2], kind[1] != "death" and kind[1] != "fall")
		if Character.strip_mirror(cd, kind[1]):
			fm.tex = A.mirror_strip(fm.tex, int(fm.frames))   # 帧条画反了（docs/84）：用镜像副本
		# 召唤物（凯尔希的 Mon3tr，帧条键 m_*）不单列：和本体同名动作并排站在一起（2026-09-27 用户）
		if sp.has("m_" + kind[1]):
			fm.pair = _sprite_form(kind[0], sp["m_" + kind[1]], kind[2], true)
			fm.pair_label = {"attack": "Mon3tr 爪击", "skill": "Mon3tr 熔毁"}.get(kind[1], "Mon3tr")
			fm.main_label = cd.get("name", cid)
		forms.append(fm)
	# 攻击演示：实机跑一段（弹道 / 命中 / 技能都是战斗里的真实效果）
	forms.append({"label": "演示", "tex": null, "frames": 1, "fps": 1.0, "loop": true, "demo": cid})
	var mech: String = cd.get("gallery", {}).get("desc", "")
	var lines: Array = []
	for si in cd.get("skills", []).size():
		var sk3: Dictionary = cd.skills[si]
		lines.append("S%d「%s」：%s" % [si + 1, sk3.get("name", ""), sk3.get("desc", "")])
	if cd.has("talent"):
		lines.append("天赋「%s」（精英一解锁）：%s" % [cd.talent.get("name", ""), cd.talent.get("desc", "")])
	if not lines.is_empty():
		mech += "\n" + "\n".join(lines)
	var st: Array = []
	if cd.has("attack"):
		st.append(["普攻", cd.attack.get("name", "")])
	# 名册卡 / 立绘：待机帧条（同选人页 title._open_op_pick）
	var idle = sp.get("idle", "")
	var tn: String = idle if idle is String else str(idle.get("tex", ""))
	var tx: Texture2D = A.tex(tn) if tn != "" else null
	var frames := 1
	if idle is Dictionary and idle.has("frames"):
		frames = int(idle.frames)
	elif tx != null:
		frames = maxi(1, tx.get_width() / tx.get_height())
	if Character.strip_mirror(cd, "idle"):
		tx = A.mirror_strip(tx, frames)
	var cls: String = cd.get("class", "")
	var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
	var cc = cd.get("col", null)
	if cc is Array and cc.size() >= 3:
		col = Color(float(cc[0]), float(cc[1]), float(cc[2]))
	var elite := 0
	for nd in cd.get("progression", []):
		if nd is Dictionary and nd.get("type", "") == "elite":
			elite += 1
	return {"id": cid, "name": cd.get("name", cid), "en": cd.get("en", cid.to_upper()), "tag": "%s干员" % cls, "forms": forms,
		"stats": st, "chips": cd.get("gallery", {}).get("tags", []), "desc": _lore_text(cid, mech), "op": cd, "cls": cls, "col": col,
		"od": {"tex": tx, "frames": frames, "hires": A.hires_of(tx)}, "elite": elite if elite > 0 else 2}


## 博士：受击体（data/doctor.json）；放在干员页最后，不属于任何职业（筛选时不出现）
func _doctor_entry() -> Dictionary:
	var dd: Dictionary = {}
	var df := FileAccess.open("res://data/doctor.json", FileAccess.READ)
	if df != null:
		var dj = JSON.parse_string(df.get_as_text())
		if dj is Dictionary:
			dd = dj
	var ds: Dictionary = dd.get("stats", {})
	var forms := _doctor_forms(dd)
	var f0: Dictionary = forms[0]
	return {"id": "doctor", "name": dd.get("name", "博士"), "en": dd.get("en", "DOCTOR"), "tag": "指挥 · 随行", "forms": forms,
		"stats": [["回复", "%.1f / 秒" % float(ds.get("regen", 0.0))], ["移速", str(int(ds.get("move_speed", 150)))],
			["闪避", "%d%%" % int(float(ds.get("dodge", 0.0)) * 100.0)], ["拾取", str(int(ds.get("pickup", 70)))]],
		"chips": ["随行", "指挥", "排异"], "cls": "", "col": UI.STEEL,
		"od": {"tex": f0.tex, "frames": int(f0.frames), "hires": A.hires_of(f0.tex)},
		"desc": _lore_text("doctor", "罗德岛的博士。失去了过去的记忆，重要的事情都回忆不起来。这次行动中负责指挥小队。")}


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


# ---------------------------------------------------------------- C4' 版式（docs/58 §8 / §11）
## 两张设计稿：桌面 1280×720、触屏 740×360（概念图同尺寸），整体等比缩放进当前界面（dk / doff）；
## 命中区都记在设计坐标里，按终态位置算（docs/62 §2.5：动效只是视觉上追上去）。
## 动效全是界面层：界面时钟 UIMo.now()（真实帧间隔）、不碰任何随机数；「减少动态效果」时位移 / 缩放 / 扫入直接终态，只留 ≤ 120 ms 淡入。
const DESK := Vector2(1280, 720)
const PHONE := Vector2(740, 360)
const ART_K := 4.0                 # 立绘倍数上限（@2x 像素）：与选人页 title.gd OP_ART_K 相同，手机 ×0.6
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
## 非干员页斜带颜色（干员页用干员色）：敌人 / 精英 / Boss / 道具 / 藏品；结局用各结局自己的颜色
const TAB_COL := [Color(0.212, 0.886, 0.863), Color(0.85, 0.3, 0.42), Color(0.957, 0.753, 0.306), Color(1.0, 0.239, 0.545),
	Color(0.212, 0.886, 0.863), Color(0.66, 0.52, 1.0), Color(0.66, 0.52, 1.0)]
const STAT_EN := {"生命": "HP", "伤害": "DMG", "移速": "SPD", "类型": "TYPE", "射程": "RNG", "体型": "SIZE", "等级": "RANK", "效果分类": "CAT",
	"原类别": "ORIG", "流派": "LANE", "Boss": "BOSS", "回复": "REGEN", "闪避": "DODGE", "拾取": "PICKUP"}
const LIGHT_BLOCK := Color(0.925, 0.933, 0.941)
var glass: Color = UI.C_L_GLASS    # 磨砂不可用时的平涂底（截图对照：--codexglass=<透明度>）
var glass_fx := true               # 磨砂玻璃（--noglassfx 关；--glassperf 轮换开关量帧时）
const GLASS_R := 8.0               # 模糊半径（设计像素，按 dk 与界面缩放换算成屏幕像素）
var glass_mat: ShaderMaterial
var glow_tex: Texture2D
var back_ci: Control               # 背后层（舞台）
var glass_ci: Control              # 玻璃层（面板底 + ARCHIVE 块）
var demo_hits: Array = []          # 演示按钮命中区（背后层画的）
const SPEC_TICKS := false          # 非干员页舞台四角的黄色小角标：10-11 去掉底框后对照过，没有框时角标像悬空的残框，关掉，只留 SPECIMEN 代码
var dk := 1.0
var doff := Vector2.ZERO
var hits: Array = []               # [Rect2（设计坐标）, 种类, 值]：按绘制顺序，命中从后往前查
var vlist: Array = []              # 网格里显示的条目（entries 下标，干员页按职业筛选）
var filter := ""                   # 干员页职业筛选（"" = 全部）
var rail_focus := false            # 键盘 / 手柄：焦点在左侧职业轨（↑↓ 换筛选，→ 回网格）
var hover := {}                    # 卡（entries 下标）→ 悬停 0–1
var row_sel := -1                  # 手机：技能 / 成长页展开说明的那一行
var open_t0 := -100.0              # 打开干员页：卡片错开浮现 → 面板滑入 → 色带 / 立绘 / 英文名
var sw_t0 := -100.0                # 换干员：色带扫入、立绘缩放进入、英文名打字、卡片抬起
var prev_sel := -1
var body_t0 := -100.0              # 面板正文开始进场（换干员 +120 ms / 打开 +200 ms / 换页签 +100 ms）
var body_slide := true             # 正文整体从右 60 px 滑入（换干员 / 打开）；换页签只逐行错开
var itab_t0 := -100.0              # 换页签：下划线 200 ms、旧正文 100 ms 淡出
var itab_from := 0.0
var itab_prev := 0
var cat_t0 := -100.0               # 非干员页：标本柜格子对角线启辉（docs/62 §3.5）
var sel_t0 := -100.0               # 非干员页：详情灯箱


## 触屏用手机版式（同选人页 _touch_mode）
func phone() -> bool:
	return Cfg.touch_device()


func _dsz() -> Vector2:
	return PHONE if phone() else DESK


func _fit_view() -> void:
	var d := _dsz()
	dk = minf(size.x / d.x, size.y / d.y) if size.x > 0.0 and size.y > 0.0 else 1.0
	doff = ((size - d * dk) / 2.0).round()


func _design(p: Vector2) -> Vector2:
	return (p - doff) / dk


## 设计坐标变换（dx / dy = 动效位移，设计像素）
func _xf(dx := 0.0, dy := 0.0) -> void:
	draw_set_transform(doff + Vector2(dx, dy) * dk, 0.0, Vector2(dk, dk))


func _grid() -> Dictionary:
	var op := tab == 0
	if phone():
		var c := Vector2(62, 90 if op else 74)
		var s := Vector2(68, 98 if op else 80)
		return {"x0": 8.0, "y0": 42.0, "card": c, "step": s, "cols": 2, "rows": maxi(1, int((PHONE.y - 18.0 - 42.0 + s.y - c.y) / s.y))}
	var c2 := Vector2(80, 110 if op else 92)
	var s2 := Vector2(88, 120 if op else 100)
	return {"x0": 76.0 if op else 24.0, "y0": 86.0, "card": c2, "step": s2, "cols": 4, "rows": maxi(1, int((684.0 - 86.0 + s2.y - c2.y) / s2.y))}


func cols() -> int:
	return _grid().cols


func rows_vis() -> int:
	return _grid().rows


func _max_scroll() -> int:
	return maxi(0, ceili(vlist.size() / float(cols())) - rows_vis())


func _stage() -> Rect2:
	return Rect2(146, 34, 320, 264) if phone() else Rect2(436, 56, 444, 388)


func _rebuild_view() -> void:
	vlist.clear()
	for i in entries.size():
		if tab != 0 or filter == "" or entries[i].get("cls", "") == filter:
			vlist.append(i)


# ---------------------------------------------------------------- 动效进度
func _now() -> float:
	return UIMo.now()


func _still() -> bool:
	return UIMo.skip_all() or UIMo.rm()


## 位移类进度：从 t0 + delay 起 dur 秒；减少动态 / 无头 = 1
func _p(t0: float, delay: float, dur: float) -> float:
	if _still():
		return 1.0
	return clampf((_now() - t0 - delay) / dur, 0.0, 1.0)


## 透明度进度：减少动态时只留从 t0 起 120 ms 的淡入
func _pa(t0: float, delay: float, dur: float) -> float:
	if UIMo.rm() and not UIMo.skip_all():
		return UIMo.rm_fade(t0)
	return _p(t0, delay, dur)


## 招牌动效进行中：这时的任意输入只跳到终态（docs/62 §2.5），不算操作
func _busy() -> bool:
	if _still():
		return false
	var n := _now()
	return n - open_t0 < 0.75 if tab == 0 else n - cat_t0 < 0.62


func _skip() -> void:
	open_t0 = -100.0
	sw_t0 = -100.0
	body_t0 = -100.0
	itab_t0 = -100.0
	cat_t0 = -100.0
	sel_t0 = -100.0


## 打开 / 切到某一页：干员页重放打开动效，其余页重放标本柜启辉
func _restart_open() -> void:
	var n := _now()
	open_t0 = n
	sw_t0 = n
	prev_sel = -1
	body_t0 = n if UIMo.rm() else n + 0.2
	body_slide = true
	itab_t0 = -100.0
	cat_t0 = n
	sel_t0 = n
	hover.clear()


## 名册卡抬起：选中 220 ms ease-out back，旧卡 160 ms 落回
func _lift(i: int) -> float:
	if i == sel:
		return 1.0 if _still() else UI.ease_back(clampf((_now() - sw_t0) / 0.22, 0.0, 1.0))
	if i == prev_sel:
		return 0.0 if _still() else 1.0 - UI.ease_out(clampf((_now() - sw_t0) / 0.16, 0.0, 1.0))
	return 0.0


## 面板正文第 i 行的 (横移, 透明度)
func _row(i: int) -> Vector2:
	if UIMo.skip_all():
		return Vector2(0, 1)
	if UIMo.rm():
		return Vector2(0, UIMo.rm_fade(body_t0))
	var n := _now()
	var dx := 0.0
	var a := 1.0
	if body_slide:
		var pp := clampf((n - body_t0) / 0.26, 0.0, 1.0)
		dx = 60.0 * (1.0 - UI.ease_out(pp))
		a = minf(1.0, pp * 1.5)
	var rt := UI.ease_out(clampf((n - body_t0 - 0.05 * mini(i, 7)) / (0.24 if body_slide else 0.22), 0.0, 1.0))
	return Vector2(dx + 40.0 * (1.0 - rt), a * rt)


## 数字跳动（450 ms ease-out，只影响显示）
func _count() -> float:
	return UI.ease_out(_p(body_t0, 0.0, 0.45))


## 打开时整个面板正文从右 300 px 滑入
func _open_dx() -> float:
	return 300.0 * (1.0 - UI.ease_out(_p(open_t0, 0.0, 0.52))) if tab == 0 else 0.0


func _open_a() -> float:
	if tab != 0:
		return 1.0
	if UIMo.rm() and not UIMo.skip_all():
		return UIMo.rm_fade(open_t0)
	return minf(1.0, _p(open_t0, 0.0, 0.52) * 2.0)


func _itab_pos() -> float:
	return lerpf(itab_from, float(info_tab), UI.ease_out(_p(itab_t0, 0.0, 0.2)))


func _name_frac() -> float:
	return _p(sw_t0, 0.08, 0.42) if tab == 0 else 1.0


func _name_a() -> float:
	if tab != 0:
		return 1.0
	if UIMo.rm() and not UIMo.skip_all():
		return UIMo.rm_fade(sw_t0)
	return minf(1.0, _name_frac() * 1.6)


## 标本柜启辉（docs/62 §3.5）：「行 + 列」对角线错开 30 ms、每格 120 ms，steps(3)：暗 → 半亮 → 闪 → 稳。返回 (亮度, 闪光)
func _ign(d: int) -> Vector2:
	if _still():
		return Vector2(1, 0)
	var p := clampf((_now() - cat_t0 - 0.03 * mini(d, 16)) / UIMo.T1, 0.0, 1.0)
	if p >= 1.0:
		return Vector2(1, 0)
	return [Vector2(0.15, 0), Vector2(0.5, 0), Vector2(1.0, 1.0)][mini(2, int(UIMo.steps(p, 3) * 3.0))]


# ---------------------------------------------------------------- 输入
var drag_acc := 0.0   # 触屏上下滑动翻页（没有滚轮）


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Pad.touch and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			drag_acc += event.relative.y / maxf(dk, 0.01)
			if absf(drag_acc) > 50.0:
				scroll = clampi(scroll + (-1 if drag_acc > 0.0 else 1), 0, _max_scroll())
				drag_acc = 0.0
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = clampi(scroll + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, _max_scroll())
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			drag_acc = 0.0
			if _busy():
				_skip()
				accept_event()
				return
			var p := _design(event.position)
			var all: Array = demo_hits + hits
			for j in range(all.size() - 1, -1, -1):
				if all[j][0].has_point(p):
					_hit(all[j][1], all[j][2])
					break
	accept_event()


func _hit(kind: String, v) -> void:
	match kind:
		"back":
			close()
		"cat":
			_set_tab(v)
		"itab":
			_set_info(v)
		"form":
			_set_form(v)
		"cls":
			rail_focus = false
			_set_filter(v)
		"card":
			rail_focus = false
			_set_sel(v)
		"demo":
			_demo_click(v[0], v[1])
		"row":
			row_sel = -1 if row_sel == v else v
			Sfx.play("ui_move")


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if _busy():
		_skip()
		return
	var k: int = event.keycode
	if rail_focus:
		match k:
			KEY_UP, KEY_W:
				_filter_step(-1)
				return
			KEY_DOWN, KEY_S:
				_filter_step(1)
				return
			KEY_RIGHT, KEY_D, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_BACKSPACE:
				rail_focus = false
				Sfx.play("ui_move")
				return
		rail_focus = false
	match k:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_Q, KEY_PAGEUP:
			_set_tab((tab + TABS.size() - 1) % TABS.size())
		KEY_E, KEY_TAB, KEY_PAGEDOWN:
			_set_tab((tab + 1) % TABS.size())
		KEY_LEFT, KEY_A:
			# 网格最左一列再往左：焦点进职业轨（桌面干员页）
			if tab == 0 and not phone() and vlist.find(sel) % cols() == 0:
				rail_focus = true
				Sfx.play("ui_move")
			else:
				_step(-1)
		KEY_RIGHT, KEY_D:
			_step(1)
		KEY_UP, KEY_W:
			_step(-cols())
		KEY_DOWN, KEY_S:
			_step(cols())
		KEY_Z:
			_form_step(-1)
		KEY_X, KEY_SPACE:
			_form_step(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_F:
			if _is_op():
				_set_info((info_tab + 1) % INFO_TABS.size())
			else:
				_form_step(1)
		KEY_1, KEY_2, KEY_3, KEY_4:
			if _is_op():
				_set_info(k - KEY_1)


func _is_op() -> bool:
	return sel >= 0 and sel < entries.size() and entries[sel].has("op") and not entries[sel].get("locked", false)


func _step(d: int) -> void:
	if vlist.is_empty():
		return
	var vi := vlist.find(sel)
	_set_sel(vlist[clampi(vi + d, 0, vlist.size() - 1)])


func _form_step(d: int) -> void:
	if entries.is_empty() or entries[sel].get("locked", false):
		return
	var n: int = entries[sel].forms.size()
	_set_form(posmod(form + d, n))


func _set_form(i: int) -> void:
	if i == form:
		return
	form = i
	form_t = 0.0
	Sfx.play("ui_move")


func _set_tab(i: int) -> void:
	if i == tab:
		return
	tab = i
	sel = 0
	scroll = 0
	filter = ""
	rail_focus = false
	row_sel = -1
	Sfx.play("ui_move")
	_build()
	_restart_open()


func _set_sel(i: int) -> void:
	if entries.is_empty():
		return
	var n := clampi(i, 0, entries.size() - 1)
	if n != sel:
		prev_sel = sel
		sel = n
		form = 0
		form_t = 0.0
		row_sel = -1
		var now := _now()
		sw_t0 = now
		sel_t0 = now
		body_t0 = now if UIMo.rm() else now + 0.12
		body_slide = true
		Sfx.play("ui_move")
	_follow()


## 选中项滚进可视行
func _follow() -> void:
	var vi := vlist.find(sel)
	if vi < 0:
		return
	var row: int = vi / cols()
	if row < scroll:
		scroll = row
	elif row >= scroll + rows_vis():
		scroll = row - rows_vis() + 1
	scroll = clampi(scroll, 0, _max_scroll())


func _set_info(i: int) -> void:
	if i == info_tab or i < 0 or i >= INFO_TABS.size():
		return
	itab_from = _itab_pos()
	itab_prev = info_tab
	info_tab = i
	var n := _now()
	itab_t0 = n
	body_t0 = n if UIMo.rm() else n + 0.1
	body_slide = false
	row_sel = -1
	Sfx.play("ui_move")


func _filter_classes() -> Array:
	var out: Array = [""]
	for c in CLASS_ORDER:
		if _class_count(c) > 0:
			out.append(c)
	return out


func _class_count(c: String) -> int:
	var n := 0
	for e in entries:
		if e.has("op") and (c == "" or e.cls == c):
			n += 1
	return n


func _set_filter(c: String) -> void:
	if c == filter:
		return
	filter = c
	_rebuild_view()
	scroll = 0
	if not vlist.is_empty() and not vlist.has(sel):
		_set_sel(vlist[0])
	_follow()
	Sfx.play("ui_move")


func _filter_step(d: int) -> void:
	var cs := _filter_classes()
	_set_filter(cs[posmod(cs.find(filter) + d, cs.size())])


## 选中某个干员 / 条目（截图自测 --galleryid=）
func select_id(id: String) -> void:
	for i in entries.size():
		if str(entries[i].get("id", "")) == id:
			sel = i
			form = 0
			_follow()
			return


# ---------------------------------------------------------------- 绘制
var _white_cache := {}
func _white_of(tx: Texture2D) -> Texture2D:
	if not _white_cache.has(tx):
		_white_cache[tx] = A.white_of(tx)
	return _white_cache[tx]


func _form_frame(f: Dictionary) -> int:
	var fr := int(form_t * f.fps)
	return fr % f.frames if f.loop else mini(fr, f.frames - 1)


## 条目的卡面 / 立绘源（干员：待机帧条；其余：第一个形态），并集区第一次用到时算
func _od(e: Dictionary) -> Dictionary:
	if not e.has("od"):
		var f: Dictionary = e.forms[0] if not e.forms.is_empty() else {}
		e.od = {"tex": f.get("tex"), "frames": int(f.get("frames", 1)), "hires": A.hires_of(f.get("tex"))}
	var od: Dictionary = e.od
	if not od.has("bb"):
		od.bb = UI.idle_bb(od.get("tex"), int(od.get("frames", 1)))
	return od


func _fbb(f: Dictionary) -> Rect2:
	if not f.has("bb"):
		f.bb = UI.idle_bb(f.get("tex"), int(f.get("frames", 1)))
	return f.bb


## 立绘适配（与选人页 title._op_fit 同一规则 UI.art_fit）：返回 [倍数（@2x 像素）, 脚底中点]；ph = 手机版式
func _art_fit(e: Dictionary, ph: bool) -> Array:
	var od := _od(e)
	var sr := Rect2(146, 34, 320, 264) if ph else Rect2(436, 56, 444, 388)
	var bb: Rect2 = od.bb
	var hi: float = float(od.get("hires", 1.0))
	return UI.art_fit(bb.size.x * 2.0 / hi, bb.size.y * 2.0 / hi, sr, ART_K * (0.6 if ph else 1.0), 380.0 if ph else 680.0, sr.end.y - 8.0)


func _band_col(e: Dictionary) -> Color:
	if e.has("col"):
		return e.col
	return TAB_COL[tab]


func _demo_form(e: Dictionary) -> bool:
	if e.is_empty() or e.get("locked", false):
		return false
	var f: Dictionary = e.forms[clampi(form, 0, e.forms.size() - 1)]
	return f.has("demo") or f.has("enemy_demo")


func _draw() -> void:
	_fit_view()
	hits.clear()
	_xf()
	var ph := phone()
	var vr := Rect2(-doff / dk, size / dk)
	var e: Dictionary = entries[sel] if sel >= 0 and sel < entries.size() else {}
	if not e.is_empty():
		form = clampi(form, 0, e.forms.size() - 1)
	var demo := _demo_form(e)
	_draw_panel_edge(ph, vr)
	_draw_top(ph, vr)
	if tab == 0 and not ph:
		_draw_rail()
	_draw_grid(ph)
	if not e.is_empty():
		_draw_name(e, ph, demo)
		_draw_forms(e, ph)
		_draw_panel(e, ph)
	_draw_hint(ph)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 职业色斜带 + 延伸到右侧面板底下的回声带（同一扫入：换干员时新颜色从左扫过、透过磨砂玻璃也看得见）
func _bands(ci: CanvasItem, H: float, b: Array, col: Color, prev: Color, t: float, alpha: float, a: float, ph: bool) -> void:
	UI.c_band(ci, H, b[0], b[1], b[2], col, prev, t, alpha, b[3], UI.C_D_INK, a)
	if ph:
		UI.c_band(ci, H, b[0] + 250.0, 70.0, b[2], col, prev, t, alpha * 0.85, Vector2(84, 6), UI.C_D_INK, a)
	else:
		UI.c_band(ci, H, b[0] + 440.0, 160.0, b[2], col, prev, t, alpha * 0.85, Vector2(180, 12), UI.C_D_INK, a)


## 立绘背后的职业色辉光：从舞台一直铺到右侧面板底下（磨砂玻璃透出来的颜色）
func _draw_glow(ci: CanvasItem, col: Color, ph: bool) -> void:
	if glow_tex == null:
		return
	var c := Vector2(380, 150) if ph else Vector2(700, 250)
	var r := Vector2(420, 230) if ph else Vector2(700, 420)
	ci.draw_texture_rect(glow_tex, Rect2(c - r, r * 2.0), false, Color(col.r, col.g, col.b, 0.3))


## 左侧暗舞台：职业色斜带（换干员时从左扫入盖住旧带）+ 描边英文名 + 立绘 / 演示
func _draw_stage(ci: CanvasItem, e: Dictionary, ph: bool, demo: bool) -> void:
	var H := _dsz().y
	var col: Color = _band_col(e) if not e.is_empty() else TAB_COL[tab]
	var b := [300.0, 100.0, 120.0, Vector2(110, 8)] if ph else [560.0, 240.0, 210.0, Vector2(258, 16)]
	# 远处淡带（静止）
	_draw_glow(ci, col, ph)
	var fx: float = 380.0 if ph else 470.0
	var fw: float = 8.0 if ph else 16.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(fx, H), Vector2(fx + fw, H), Vector2(fx + fw + b[2], 0), Vector2(fx + b[2], 0)]), UI.fa(UI.C_D_INK, 0.14))
	if tab == 0:
		var prev := Color(0, 0, 0, 0)
		if prev_sel >= 0 and prev_sel < entries.size() and prev_sel != sel:
			prev = _band_col(entries[prev_sel])
		if UIMo.rm() and not UIMo.skip_all():
			var f := UIMo.rm_fade(sw_t0)
			if f < 1.0 and prev.a > 0.0:
				_bands(ci, H, b, prev, Color(0, 0, 0, 0), 1.0, 0.6, 1.0 - f, ph)
			_bands(ci, H, b, col, Color(0, 0, 0, 0), 1.0, 0.6, f, ph)
		else:
			_bands(ci, H, b, col, prev, _p(sw_t0, 0.0, 0.38), 0.6, 1.0, ph)
	else:
		_bands(ci, H, b, col, Color(0, 0, 0, 0), 1.0, 0.45, 1.0, ph)
	if e.is_empty():
		return
	var locked: bool = e.get("locked", false)
	if demo:
		_draw_demo(ci, e, e.forms[form])
		return
	_demo_stop()
	if not locked:
		UI.ghost_name(ci, font, Vector2(150, 40) if ph else Vector2(440, 60), str(e.en), _name_frac(), 90 if ph else 150, UI.C_D_GHOST, 2)
	if e.has("od") and form == 0 and tab == 0:
		_draw_op_art(ci, e, ph)
	else:
		_draw_form_art(ci, e, e.forms[form], ph)


## 干员待机帧（整数倍最近邻、底部 25 % 渐隐、黑色硬投影；换干员 60 ms 后 300 ms 缩放 0.92 → 1、右移 24 → 0、淡入；全部裁进舞台框）
func _draw_op_art(ci: CanvasItem, e: Dictionary, ph: bool) -> void:
	var od := _od(e)
	var tx: Texture2D = od.get("tex")
	if tx == null:
		return
	var fit := _art_fit(e, ph)
	var c := UI.ease_out(_p(sw_t0, 0.06, 0.3))
	var a := _pa(sw_t0, 0.06, 0.3) if UIMo.rm() else c
	if a <= 0.0:
		return
	var frames: int = int(od.frames)
	_blit_art(ci, tx, frames, od.bb, float(od.hires), fit[0], fit[1], c, a, _stage(), Color.WHITE, int(t * 4.0) % maxi(1, frames), true)


## 一张帧条的一帧：k2 = @2x 像素倍数，foot = 脚底中点，c = 进场进度（缩放 / 右移），a = 透明度，clip = 舞台框
func _blit_art(ci: CanvasItem, tx: Texture2D, frames: int, bb: Rect2, hires: float, k2: float, foot: Vector2, c: float, a: float, clip: Rect2, tint: Color, fr: int, shadow: bool, sil := false, fade := true) -> void:
	var fw: float = tx.get_width() / float(maxi(1, frames))
	var k: float = k2 * 2.0 / hires * (0.92 + 0.08 * c)
	var sz := bb.size * k
	var pos := Vector2(foot.x - sz.x / 2.0 + 24.0 * (1.0 - c), foot.y - sz.y)
	if c >= 1.0:
		pos = pos.round()
	var src := Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var cut := floorf(bb.size.y * 0.75) if fade else bb.size.y
	var wt := _white_of(tx)
	if shadow and wt != null:
		UI.blit_clipped(ci, wt, Rect2(pos + Vector2(14, 10) * k2 / 4.0, Vector2(sz.x, cut * k)), Rect2(src.position, Vector2(src.size.x, cut)), clip, Color(0, 0, 0, 0.35 * a))
	var body: Texture2D = wt if sil and wt != null else tx
	var col := Color(tint.r, tint.g, tint.b, tint.a * a)
	UI.blit_clipped(ci, body, Rect2(pos, Vector2(sz.x, cut * k)), Rect2(src.position, Vector2(src.size.x, cut)), clip, col)
	var rows: int = int(bb.size.y - cut)
	for y in rows:
		var f := 1.0 - (y + 0.5) / float(rows)
		UI.blit_clipped(ci, body, Rect2(pos + Vector2(0, (cut + y) * k), Vector2(sz.x, k)), Rect2(src.position + Vector2(0, cut + y), Vector2(src.size.x, 1)), clip, Color(col.r, col.g, col.b, col.a * f))


## 其他形态 / 非干员条目：同一适配规则，直接画在舞台斜带前（同干员页，不画底框，10-11 用户：「敌人那里为什么有个黑框」）；
## 非干员页换条目时四角黄色小角标与 SPECIMEN 代码先亮（T2，「灯箱」只剩角标），再出精灵（T1）；未解锁画暗剪影
func _draw_form_art(ci: CanvasItem, e: Dictionary, f: Dictionary, ph: bool) -> void:
	var sr := _stage()
	var locked: bool = e.get("locked", false)
	var a := 1.0
	var box := sr
	var cx: float = 380.0 if ph else 680.0
	var foot_y: float = sr.end.y - 8.0
	if tab != 0:
		var lb := _pa(sel_t0, 0.0, UIMo.T2)
		var tk := sr.grow(-12.0)
		if SPEC_TICKS:
			for cn in [tk.position, Vector2(tk.end.x - 14, tk.position.y), Vector2(tk.position.x, tk.end.y - 2), tk.end - Vector2(14, 2)]:
				ci.draw_rect(Rect2(cn, Vector2(14, 2)), UI.fa(UI.C_ACC, lb))
		UI.code(ci, font, tk.position + Vector2(10, 8), "SPECIMEN  //  NO.%02d" % (vlist.find(sel) + 1), 7 if ph else 8, UI.fa(UI.C_D_SUB, lb))
		a = _pa(sel_t0, UIMo.T2, UIMo.T1)
		box = sr.grow(-4.0)   # 留出 SPECIMEN 代码行；其余同干员页的舞台框
		box.position.y += 14.0
		box.size.y -= 14.0
	if f.get("tex") == null or a <= 0.0:
		return
	var tx: Texture2D = f.tex
	var hi: float = A.hires_of(tx)
	var bb := _fbb(f)
	var pf: Dictionary = f.get("pair", {})
	var bb2 := Rect2()
	var gap := 4.0
	var w2: float = bb.size.x * 2.0 / hi
	var h2: float = bb.size.y * 2.0 / hi
	if pf.get("tex") != null:
		bb2 = _fbb(pf)
		w2 += (bb2.size.x + gap) * 2.0 / hi
		h2 = maxf(h2, bb2.size.y * 2.0 / hi)
	var kmax: float = ART_K * (0.6 if ph else 1.0) if tab == 0 else (2.0 if ph else ART_K - 1.0)   # 标本：桌面 3、手机 2
	var fit := UI.art_fit(w2, h2, box, kmax, cx, foot_y)
	var k2: float = fit[0]
	var foot: Vector2 = fit[1]
	var tint: Color = Color(0.2, 0.21, 0.25) if locked else f.get("tint", Color.WHITE)
	var clip := sr
	if pf.get("tex") != null:
		var k: float = k2 * 2.0 / hi
		var total: float = (bb.size.x + gap + bb2.size.x) * k
		var x0: float = foot.x - total / 2.0
		_blit_art(ci, tx, int(f.frames), bb, hi, k2, Vector2(x0 + bb.size.x * k / 2.0, foot.y), 1.0, a, clip, tint, _form_frame(f), not locked, locked)
		_blit_art(ci, pf.tex, int(pf.frames), bb2, hi, k2, Vector2(x0 + (bb.size.x + gap) * k + bb2.size.x * k / 2.0, foot.y), 1.0, a, clip, tint, _form_frame(pf), not locked, locked)
		if not locked:
			UI.code(ci, font, Vector2(x0 + bb.size.x * k / 2.0, foot.y + 4), str(f.get("main_label", "")), 8, UI.C_D_SUB, "ma")
			UI.code(ci, font, Vector2(x0 + (bb.size.x + gap) * k + bb2.size.x * k / 2.0, foot.y + 4), str(pf.get("pair_label", f.get("pair_label", ""))), 8, UI.C_D_SUB, "ma")
		return
	var ds: float = float(f.get("dscale", 1.0))
	if ds > 1.05:
		fit = UI.art_fit(w2, h2, box, minf(kmax * ds, 6.0), cx, foot_y)
		k2 = fit[0]
	if tab in [1, 2, 3] and not locked:
		# 敌人：一圈淡青白描边（同实战「怪物轮廓光」），深色小怪在暗展示台上也看得清
		var wt := _white_of(tx)
		if wt != null:
			var k3: float = k2 * 2.0 / hi
			var fr2 := _form_frame(f)
			var fw: float = tx.get_width() / float(maxi(1, int(f.frames)))
			var src := Rect2(fw * fr2 + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
			var dst := Rect2((foot - Vector2(bb.size.x * k3 / 2.0, bb.size.y * k3)).round(), bb.size * k3)
			for d in [Vector2(k3, 0), Vector2(-k3, 0), Vector2(0, k3), Vector2(0, -k3)]:
				UI.blit_clipped(ci, wt, Rect2(dst.position + d, dst.size), src, clip, Color(0.7, 0.85, 0.95, 0.5 * a))
	_blit_art(ci, tx, int(f.frames), bb, hi, k2, foot, 1.0, a, clip, tint, _form_frame(f), not locked, locked, tab in [0, 1, 2, 3, 6])
	if locked:
		UI.text_at(ci, font, foot - Vector2(0, h2 * k2 / 2.0), "?", 40 if not ph else 28, UI.C_D_SUB, "mm", true)


## 实机演示（干员技能 / 敌人攻击）：SubViewport 画进舞台框；右上两排平行四边形按钮，左下名字与当前段落
func _draw_demo(ci: CanvasItem, e: Dictionary, f: Dictionary) -> void:
	var dr := Rect2(146, 34, 320, 262) if phone() else _stage()
	var is_enemy: bool = f.has("enemy_demo")
	if is_enemy:
		_enemy_demo_start(f.enemy_demo, Vector2i(dr.size))
	else:
		_demo_start(f.demo, Vector2i(dr.size))
	if demo_vp != null:
		ci.draw_texture_rect(demo_vp.get_texture(), dr, false)
	ci.draw_rect(dr, UI.C_D_INK, false, 1.0)
	for cn in [dr.position, Vector2(dr.end.x - 16, dr.position.y)]:
		ci.draw_rect(Rect2(cn, Vector2(16, 3)), UI.C_ACC)
	var cur: int = -9
	if demo_game != null and demo_game.demo_pi >= 0 and not demo_game.demo_phases.is_empty():
		cur = demo_game.demo_phases[demo_game.demo_pi]
	var rows := [
		["stage", [["精零", 0], ["精一", 1], ["精二", 2]]],
		["mode", [["普攻", 3], ["一技能", 0], ["二技能", 1], ["三技能", 2], ["轮播", -1]]],
	]
	if is_enemy:
		rows = [["enemy_replay", [["重播", 0]]]]
		if f.enemy_demo in ["ishar", "paranoia", "knight_boss", "izumik"]:
			rows.push_front(["enemy_phase", [["完整转化", 0], ["人形治疗", 1], ["敌对", 2]]] if f.enemy_demo == "ishar" else ["enemy_phase", [["轮播", 0], ["一阶段", 1], ["二阶段", 2]]])
	var fs := 10 if phone() else 11
	for ri in rows.size():
		var kind: String = rows[ri][0]
		var cx := dr.end.x - 8.0
		var items: Array = rows[ri][1]
		for ii in range(items.size() - 1, -1, -1):
			var lbl: String = items[ii][0]
			var v: int = items[ii][1]
			var w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
			cx -= w
			var cr := Rect2(Vector2(cx, dr.position.y + 8 + ri * 25), Vector2(w, 20))
			var on: bool = enemy_demo_mode == v if kind == "enemy_phase" else ((demo_stage == v) if kind == "stage" else (demo_mode == v and kind == "mode"))
			var locked_skill: bool = kind == "mode" and v >= 0 and v <= 2 and v > demo_stage
			var playing: bool = kind == "mode" and demo_mode == -1 and v == cur and demo_game != null and not demo_game.demo_basic
			UI.para(ci, cr, 6, UI.C_D_INK if on else UI.C_D_PANEL, Color(0, 0, 0, 0) if on else (UI.C_ACC if playing else UI.fa(UI.C_D_INK, 0.55)))
			UI.text_at(ci, font, cr.get_center(), lbl, fs, UI.C_D_INV if on else (UI.fa(UI.C_D_SUB, 0.6) if locked_skill else UI.C_D_INK), "mm")
			demo_hits.append([cr, "demo", [kind, v]])
			cx -= 4.0
	var by := dr.end.y - 40.0
	ci.draw_rect(Rect2(dr.position.x + 1, by - 4, dr.size.x - 2, 43), Color(0, 0, 0, 0.55))
	UI.code(ci, font, Vector2(dr.position.x + 10, by), "%s  //  %s" % [str(e.en), "ATTACK DEMO"], 7 if phone() else 8, UI.C_D_SUB)
	UI.text_at(ci, font, Vector2(dr.position.x + 10, by + 11), "%s · 攻击演示" % e.name, 12 if phone() else 13, UI.C_D_INK)
	if demo_game != null:
		UI.text_at(ci, font, Vector2(dr.end.x - 10, by + 13), str(demo_game.demo_label), 11 if phone() else 12, UI.C_ACC, "ra")


## 右侧浅色终端面板（斜边分区 + 3 px 警示黄线）；超出设计稿的部分（宽屏 / 高屏）一直铺到屏幕边
func _panel_poly(ph: bool, vr: Rect2) -> PackedVector2Array:
	var D := _dsz()
	var top := 0.0 if ph else 48.0
	var xt := 492.0 if ph else 910.0
	var xb := 470.0 if ph else 866.0
	var y0 := minf(top, vr.position.y) if ph else top
	var y1 := maxf(D.y, vr.end.y)
	var xa := xt + (xb - xt) * (y0 - top) / (D.y - top)
	var xz := xt + (xb - xt) * (y1 - top) / (D.y - top)
	var xr := maxf(D.x, vr.end.x) + 1.0
	return PackedVector2Array([Vector2(xa, y0), Vector2(xr, y0), Vector2(xr, y1), Vector2(xz, y1)])


## 左上 ARCHIVE 浅色块（也是磨砂玻璃）
func _block_rect(ph: bool, vr: Rect2) -> Rect2:
	if ph:
		return Rect2(vr.position.x, minf(0.0, vr.position.y), 96.0 - vr.position.x, 30.0 - minf(0.0, vr.position.y))
	return Rect2(vr.position.x, 0, 120.0 - vr.position.x, 48)


## 背后层：暗底 + 辉光 + 斜带 + 描边英文名 + 立绘 / 演示（show_behind_parent，画在前层之下、玻璃之下）
func _draw_back() -> void:
	_fit_view()
	back_ci.draw_rect(Rect2(Vector2.ZERO, size), UI.C_D_BG)
	back_ci.draw_set_transform(doff, 0.0, Vector2(dk, dk))
	demo_hits.clear()
	var e: Dictionary = entries[sel] if sel >= 0 and sel < entries.size() else {}
	if not e.is_empty():
		form = clampi(form, 0, e.forms.size() - 1)
	_draw_stage(back_ci, e, phone(), _demo_form(e))


## 玻璃层：右侧面板与 ARCHIVE 块。磨砂（ui_glass.gdshader：模糊背后层 + 浅色底 0.70）；着色器不可用 / 无头 / --noglassfx 时退回 UI.C_L_GLASS 平涂
func _draw_glass() -> void:
	var ph := phone()
	var vr := Rect2(-doff / dk, size / dk)
	glass_ci.draw_set_transform(doff, 0.0, Vector2(dk, dk))
	var on := glass_on()
	glass_ci.material = glass_mat if on else null
	if on:
		var sc: float = glass_ci.get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
		glass_mat.set_shader_parameter("radius", GLASS_R * dk * sc)
	var col := Color.WHITE if on else glass
	glass_ci.draw_colored_polygon(_panel_poly(ph, vr), col)
	glass_ci.draw_rect(_block_rect(ph, vr), col if on else UI.fa(LIGHT_BLOCK, glass.a))


func glass_on() -> bool:
	return glass_fx and glass_mat != null and not UIMo.skip_all()


func _draw_panel_edge(ph: bool, vr: Rect2) -> void:
	var p := _panel_poly(ph, vr)
	draw_line(p[0], p[3], UI.C_ACC, 3.0, true)


## 顶栏：浅色标题块「ARCHIVE / 图鉴」+ 警示条（30 px / 秒缓慢滚动）+ 七个平行四边形大页签 + 收录数 + 返回
func _draw_top(ph: bool, vr: Rect2) -> void:
	var W := _dsz().x
	var ht := 0.0 if _still() else _now() * 30.0
	var unl := 0
	for en in entries:
		if not en.get("locked", false):
			unl += 1
	if ph:
		UI.hazard(self, Rect2(96, 0, 14, 30), ht)
		UI.text_at(self, font, Vector2(10, 15), "图鉴 · " + str(TABS[tab].cn), 13, UI.C_HZ, "lm", true)
		for i in TABS.size():
			var r := Rect2(116 + i * 50, 5, 48, 21)
			var on := i == tab
			UI.para(self, r, 6, UI.C_ACC if on else UI.C_D_PANEL, Color(0, 0, 0, 0) if on else UI.fa(UI.C_D_INK, 0.8))
			UI.text_at(self, font, r.get_center() + Vector2(0, 1), str(TABS[i].cn), 11, UI.C_HZ if on else UI.C_D_INK, "mm")
			hits.append([r.grow(2.0), "cat", i])
		var br := Rect2(W - 52, 6, 42, 20)
		UI.para(self, br, 6, UI.C_L_INK)
		UI.text_at(self, font, br.get_center() + Vector2(0, 1), Pad.hint("Esc", "Ⓑ", "返回"), 10, UI.C_L_INV, "mm")
		hits.append([br.grow(6.0), "back", 0])
		return
	draw_rect(Rect2(120, 0, vr.end.x - 120.0, 48), UI.C_D_PANEL)
	draw_line(Vector2(vr.position.x, 48), Vector2(vr.end.x, 48), UI.C_D_INK, 2.0)
	UI.hazard(self, Rect2(120, 0, 20, 48), ht)
	UI.code(self, font, Vector2(18, 7), "ARCHIVE", 9, UI.C_HZ)
	UI.text_at(self, font, Vector2(18, 19), "图鉴", 18, UI.C_HZ, "la", true)
	for i in TABS.size():
		var x := 156.0 + i * 106.0
		var r := Rect2(x, 8, 100, 34)
		var on := i == tab
		UI.para(self, r, 10, UI.C_ACC if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0) if on else UI.C_D_INK)
		UI.text_at(self, font, Vector2(x + 22, 10), str(TABS[i].cn), 13, UI.C_HZ if on else UI.C_D_INK, "la", on)
		UI.code(self, font, Vector2(x + 20, 28), str(TABS[i].en), 7, UI.C_HZ if on else UI.C_D_SUB)
		hits.append([r, "cat", i])
	UI.code(self, font, Vector2(W - 128, 20), "%d / %d" % [unl, entries.size()], 9, UI.C_D_SUB, "ra")
	var back := Rect2(W - 112, 10, 96, 28)
	UI.para(self, back, 8, Color(0, 0, 0, 0), UI.C_D_INK)
	UI.text_at(self, font, back.get_center() + Vector2(0, 1), Pad.hint("返回  Esc", "返回  Ⓑ", "返回"), 12, UI.C_D_INK, "mm")
	hits.append([back.grow(4.0), "back", 0])


## 左职业框轨（桌面干员页）：ALL + 8 职业；当前筛选 = 黄底黑图标；当前干员的职业 = 黄色细框；没有干员的职业变暗、不可点
func _draw_rail() -> void:
	var cs: Array = [""]
	cs.append_array(CLASS_ORDER)
	var cur_cls: String = entries[sel].get("cls", "") if sel < entries.size() else ""
	for i in cs.size():
		var c: String = cs[i]
		var r := Rect2(24, 64 + i * 44, 36, 36)
		var n := _class_count(c)
		var dim := 1.0 if n > 0 else 0.3
		var on := c == filter
		if on:
			draw_rect(r, UI.C_ACC)
		else:
			draw_rect(r, UI.C_D_PANEL)
			draw_rect(r, UI.fa(UI.C_D_INK, dim), false, 1.0)
		var gc := UI.C_HZ if on else UI.fa(UI.C_D_INK, dim)
		if c == "":
			UI.text_at(self, font, r.get_center() + Vector2(0, 1), "ALL", 10, gc, "mm", true)
		else:
			UI.class_glyph(self, c, r.get_center(), 9.0, gc, 2.0)
			if c == cur_cls and not on:
				draw_rect(r.grow(2.0), UI.C_ACC, false, 1.0)
		if rail_focus and on:
			draw_rect(r.grow(4.0), UI.C_ACC, false, 2.0)
		if n > 0:
			hits.append([r.grow(3.0), "cls", c])


func _draw_grid(ph: bool) -> void:
	var g := _grid()
	var cols_n: int = g.cols
	var rows_n: int = g.rows
	scroll = clampi(scroll, 0, _max_scroll())
	if not ph:
		var hdr := "%s  //  %s" % [["OPERATORS", "ENEMIES", "ELITES", "BOSSES", "ITEMS", "RELICS", "ENDINGS"][tab], "SORT: CLASS" if tab == 0 and filter == "" else (filter if tab == 0 else "%d ENTRIES" % vlist.size())]
		UI.code(self, font, Vector2(g.x0, 56), hdr, 8, UI.C_D_SUB)
	var u := _now() - open_t0
	for vi in vlist.size():
		var row: int = vi / cols_n - scroll
		if row < 0 or row >= rows_n:
			continue
		var cc: int = vi % cols_n
		var i: int = vlist[vi]
		var r := Rect2(g.x0 + cc * g.step.x, g.y0 + row * g.step.y, g.card.x, g.card.y)
		hits.append([r, "card", i])
		var a := 1.0
		var flash := 0.0
		if tab == 0:
			if UIMo.rm() and not UIMo.skip_all():
				a = UIMo.rm_fade(open_t0)
			elif not _still():
				var ti := UI.ease_out(clampf((u - 0.02 * (row * cols_n + cc)) / 0.2, 0.0, 1.0))
				a = ti
				r.position.y += roundf(16.0 * (1.0 - ti))
		else:
			var ig := _ign(row + cc)
			a = ig.x
			flash = ig.y
		if a <= 0.0:
			continue
		_card(r, entries[i], i, a, flash, ph)
	var ms := _max_scroll()
	if ms > 0:
		var gx: float = g.x0 + cols_n * g.step.x - 2.0
		var gh: float = (rows_n - 1) * g.step.y + g.card.y
		draw_rect(Rect2(gx, g.y0, 2, gh), UI.fa(UI.C_D_INK, 0.15))
		var th := maxf(16.0, gh * rows_n / float(rows_n + ms))
		draw_rect(Rect2(gx, g.y0 + (gh - th) * scroll / float(ms), 2, th), UI.C_ACC)
		if ph:
			var more := maxi(0, vlist.size() - (scroll + rows_n) * cols_n)
			UI.code(self, font, Vector2(g.x0 + (cols_n * g.step.x - 6.0) / 2.0, PHONE.y - 14), "SWIPE  +%d" % more if more > 0 else "SWIPE  ▲", 7, UI.C_D_SUB, "ma")


## C4' 名册卡（暗场）：顶部 4 px 色条、左上职业框、右上精英菱形、底部反色名字条；选中 = 抬起 10 px + 黑投影 + 2 px 框 + 底部黄条 + 卡上方黄线
func _card(r: Rect2, e: Dictionary, i: int, a: float, flash: float, ph: bool) -> void:
	var lift := _lift(i)
	var hv: float = hover.get(i, 0.0)
	r.position.y -= roundf(10.0 * lift + 4.0 * hv)
	var locked: bool = e.get("locked", false)
	var op: bool = e.has("op")
	var selv := lift > 0.5
	if lift > 0.01:
		draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.85 * a * minf(1.0, lift)))
	draw_rect(r, UI.fa(UI.C_D_PANEL if selv else UI.C_D_CARD, a))
	draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 4), UI.fa(UI.C_D_SUB if locked else _band_col(e), a))
	if e.has("od") and tab == 0:
		UI.card_art(self, r, _od(e), 0, Color(1, 1, 1, a), 24.0)
	else:
		_tile_art(r, e, a)
	var nb := Rect2(r.position.x + 1, r.end.y - 22, r.size.x - 2, 21)
	draw_rect(nb, UI.fa(UI.C_D_INK, a))
	var fl := UI.fit_line(font, "???" if locked else str(e.name), 11 if ph else 12, r.size.x - 8.0, 8)
	UI.text_at(self, font, nb.get_center(), fl[0], fl[1], UI.fa(UI.C_D_INV, a), "mm")
	if op:
		UI.class_box(self, r.position + Vector2(4, 8), 14 if ph else 16, str(e.cls), false, UI.C_D_INK, UI.C_D_INV, a)
		for k in int(e.get("elite", 0)):
			UI.diamond(self, Vector2(r.end.x - 8 - k * 9, r.position.y + 14), 3.0, UI.fa(UI.C_ACC, a))
	if locked:
		UI.text_at(self, font, Vector2(r.get_center().x, r.position.y + (r.size.y - 22) / 2.0 + 2), "?", 24 if not ph else 20, UI.fa(UI.C_D_SUB, a), "mm", true)
	draw_rect(r, UI.fa(UI.C_D_INK, a * (1.0 if selv else 0.8)), false, 2.0 if selv else 1.0)
	var hl := maxf(lift, hv * 0.6)
	if hl > 0.01:
		var e2 := UI.ease_out(minf(hl, 1.0))
		draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x * e2, 4), UI.fa(UI.C_ACC, a))
		draw_rect(Rect2(r.position.x - 4, r.position.y - 7, (r.size.x + 8) * e2, 2), UI.fa(UI.C_ACC, a))
	if flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.3 * flash))


## 非干员格子：第一个形态的第 0 帧，按格子缩放（≥ 2 倍取整数倍），裁进卡框；未解锁画暗剪影
func _tile_art(r: Rect2, e: Dictionary, a: float) -> void:
	var f: Dictionary = e.forms[0] if not e.forms.is_empty() else {}
	var tx: Texture2D = f.get("tex")
	if tx == null:
		return
	var bb := _fbb(f)
	var area := Rect2(r.position.x + 5, r.position.y + 9, r.size.x - 10, r.size.y - 9 - 26)
	var k: float = minf(area.size.x / bb.size.x, area.size.y / bb.size.y)
	if k >= 2.0:
		k = floorf(k)
	var sz := bb.size * k
	var dst := Rect2(Vector2(area.get_center().x - sz.x / 2.0, area.end.y - sz.y).round(), sz)
	var locked: bool = e.get("locked", false)
	var src := Rect2(bb.position, bb.size)   # 第 0 帧（并集区是帧内坐标）
	if locked:
		UI.blit_clipped(self, _white_of(tx), dst, src, r.grow(-2.0), Color(0.3, 0.31, 0.35, a))
	else:
		var tint: Color = f.get("tint", Color.WHITE)
		UI.blit_clipped(self, tx, dst, src, r.grow(-2.0), Color(tint.r, tint.g, tint.b, a))


## 名字块：微型代码 + 中文名（粗）+ 宽字距英文（打字机）+ 职业框 + 标签片；桌面干员页再加 2×2 档案小表
func _draw_name(e: Dictionary, ph: bool, demo: bool) -> void:
	if ph and demo:
		return
	var locked: bool = e.get("locked", false)
	var op: bool = e.has("op")
	var x: float = 152.0 if ph else 452.0
	var y0: float = 208.0 if ph else 452.0
	var na := _name_a()
	var frac := _name_frac()
	var no := vlist.find(sel) + 1
	UI.code(self, font, Vector2(x, y0), "No.%02d  //  %s" % [no, str(e.cls) if op else str(e.tag)], 7 if ph else 9, UI.C_D_SUB)
	if na > 0.0:
		var fl := UI.fit_line(font, "???" if locked else str(e.name), 28 if ph else 44, 310.0 if ph else 400.0, 16)
		UI.text_at(self, font, Vector2(x - 2, y0 + (10 if ph else 14)), fl[0], fl[1], UI.fa(UI.C_D_INK, na), "la", true)
		var en_s: String = "UNKNOWN" if locked else str(e.en)
		en_s = en_s.substr(0, int(round(en_s.length() * clampf(frac, 0.0, 1.0))))
		var es := 10 if ph else 13
		var ew := UI.en_width(font, en_s, es, 4.0 if ph else 5.0)
		var max_w := 310.0 if ph else 400.0
		if ew > max_w and en_s.length() > 0:
			es = maxi(7, int(es * max_w / ew))
		UI.en(self, font, Vector2(x + 2, y0 + (46 if ph else 70) + UI.cond(font).get_ascent(es)), en_s, es, UI.fa(UI.C_D_SUB, na), 4.0 if ph else 5.0)
	if locked:
		return
	var ty: float = y0 + (64 if ph else 96)
	var tx: float = x
	if op:
		var bs: float = 18.0 if ph else 22.0
		UI.class_box(self, Vector2(x, ty), bs, str(e.cls), false, UI.C_D_INK, UI.C_D_INV, na)
		tx += bs + 8.0
	var xmax: float = 466.0 if ph else 860.0
	var n := 0
	for tg in e.get("chips", []):
		var tw: float = font.get_string_size(str(tg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0
		if tx + tw > xmax or (ph and n >= 2):
			break
		tx += UI.ctag(self, font, Vector2(tx, ty + (0 if ph else 1)), str(tg), 10 if ph else 11, true, na)
		n += 1
	if op and not ph:
		var pf: Dictionary = lore.get(str(e.id), {}).get("profile", {})
		var i := 0
		for k in ["性别", "出身地", "种族", "所属"]:
			if not pf.has(k) or str(pf[k]) == "":
				continue
			var px: float = x + (i % 2) * 200.0
			var py: float = 584.0 + (i / 2) * 30.0
			UI.text_at(self, font, Vector2(px, py - 2), k, 9, UI.C_D_SUB)
			UI.text_at(self, font, Vector2(px, py + 10), str(pf[k]), 13, UI.C_D_INK)
			i += 1


## 动作 / 形态切换：平行四边形小按钮（待机 / 跑步 / 攻击 / 技能 / … / 演示），一行放不下时按比例压窄
func _draw_forms(e: Dictionary, ph: bool) -> void:
	if e.get("locked", false) or e.forms.size() <= 1:
		return
	var y: float = 300.0 if ph else 652.0
	var x0: float = 150.0 if ph else 452.0
	var avail: float = (466.0 if ph else 860.0) - x0
	var n: int = e.forms.size()
	var gap := 6.0 if not ph else 4.0
	var w: float = minf(66.0 if not ph else 60.0, (avail - gap * (n - 1)) / n)
	for i in n:
		var r := Rect2(x0 + i * (w + gap), y, w, 26.0 if not ph else 22.0)
		var on := i == form
		UI.para(self, r, 8.0 if not ph else 6.0, UI.C_D_INK if on else UI.fa(UI.C_D_BG, 0.6), Color(0, 0, 0, 0) if on else UI.C_D_INK)
		var fl := UI.fit_line(font, str(e.forms[i].label), 11 if not ph else 10, w - 14.0, 8)
		UI.text_at(self, font, r.get_center() + Vector2(0, 1), fl[0], fl[1], UI.C_D_INV if on else UI.C_D_INK, "mm")
		hits.append([r.grow(2.0), "form", i])


# ---------------------------------------------------------------- 右侧数据面板
func _panel_x() -> Vector2:
	return Vector2(504, 730) if phone() else Vector2(932, 1244)


func _draw_panel(e: Dictionary, ph: bool) -> void:
	var px := _panel_x()
	var oa := _open_a()
	var odx := _open_dx()
	_xf(odx)
	if not e.has("op") or e.get("locked", false):
		_draw_data(e, ph, px, oa, odx)
		_xf()
		return
	UI.code(self, font, Vector2(px.x, 14 if ph else 72), "OPERATOR FILE  //  %s" % ["PROFILE", "STATS", "SKILL", "GROWTH"][info_tab], 7 if ph else 8, UI.fa(UI.C_L_SUB, oa))
	var tr := Rect2(px.x, 34 if ph else 86, px.y - px.x, 26 if ph else 30)
	var rs: Array = UI.c_tabs(self, font, tr, INFO_TABS, _itab_pos(), 6.0 if ph else 8.0, 12 if ph else 13, oa)
	for i in rs.size():
		hits.append([rs[i], "itab", i])
	var box := Rect2(px.x, 72 if ph else 130, px.y - px.x, (352 if ph else 696) - (72 if ph else 130))
	var n := _now()
	if not _still() and itab_t0 > 0.0 and n - itab_t0 < 0.1 and itab_prev != info_tab:
		_content(e, itab_prev, box, ph, oa * (1.0 - (n - itab_t0) / 0.1), odx, false)
	else:
		_content(e, info_tab, box, ph, oa, odx, true)
	_xf()


func _content(e: Dictionary, which: int, box: Rect2, ph: bool, am: float, odx: float, motion: bool) -> void:
	match which:
		0:
			_c_profile(e, box, ph, am, odx, motion)
		1:
			_c_stats(e, box, ph, am, odx, motion)
		2:
			_c_skills(e, box, ph, am, odx, motion)
		3:
			_c_growth(e, box, ph, am, odx, motion)


## 第 i 行的位移与透明度（含打开时整体滑入），并把变换设好
func _rowm(i: int, am: float, odx: float, motion: bool) -> float:
	var m := _row(i) if motion else Vector2(0, 1)
	_xf(odx + m.x)
	return m.y * am


func _c_profile(e: Dictionary, box: Rect2, ph: bool, am: float, odx: float, motion: bool) -> void:
	var a := _rowm(0, am, odx, motion)
	var paras: Array = _op_profile(str(e.id), e.op, ph)
	var y := box.position.y
	for pi in paras.size():
		a = _rowm(pi, am, odx, motion)
		var s: String = paras[pi]
		var hdr := ""
		if s.begins_with("【本作定位】"):
			hdr = "ROLE  //  本作定位"
			s = s.substr(6)
		elif pi == 0 and not ph:
			hdr = "PROFILE  //  档案"
		elif pi == 0:
			hdr = "PROFILE"
		if hdr != "":
			UI.code(self, font, Vector2(box.position.x, y), hdr, 7 if ph else 8, UI.fa(UI.C_L_SUB, a))
			y += 14.0
		var left := box.end.y - y - 6.0 * (paras.size() - pi - 1) - 18.0 * (paras.size() - pi - 1)
		var share := left if pi == paras.size() - 1 else left * (0.7 if pi == 0 else 0.5)
		var f := UI.fit(font, s, box.size.x, share, [13, 12, 11] if not ph else [12, 11, 10])
		y += UI.draw_fit(self, font, Vector2(box.position.x, y), f, UI.fa(UI.C_L_INK, a)) + 10.0


## 数值表缓存（条目字典里存一份；InitialStats 读 doctor.json）
func _sheet(e: Dictionary) -> Dictionary:
	if not e.has("sheet"):
		e["sheet"] = InitialStats.sheet(str(e.id), e.op)
	return e.sheet


func b_mon3tr(sh: Dictionary) -> bool:
	return "Mon3tr" in str(InitialStats.row(sh, "atk").get("label", ""))


## 属性页：主控数值表（与选人「属性」页同源）。两列大数字（攻击行带段数 / 附加伤害），干员特有行（治疗 / 歌域 / 穿透 / 对精英）接在后面，
## 再是定位标签与口径说明；数字过长时按列宽缩字
func _c_stats(e: Dictionary, box: Rect2, ph: bool, am: float, odx: float, motion: bool) -> void:
	var sh: Dictionary = _sheet(e)
	var x0 := box.position.x
	var w := box.size.x
	var y := box.position.y
	var a := _rowm(0, am, odx, motion)
	UI.code(self, font, Vector2(x0, y), "LEADER  //  E0  //  NO RELIC", 7 if ph else 8, UI.fa(UI.C_L_SUB, a))
	y += 14.0 if ph else 18.0
	var all: Array = sh.rows + sh.extra
	var cw := w / 2.0
	var lh := 34.0 if ph else 46.0
	var vs := 15 if ph else 19
	for i in all.size():
		var r: Dictionary = all[i]
		if i % 2 == 0:
			a = _rowm(1 + i / 2, am, odx, motion)
		var cx := x0 + (i % 2) * cw
		var cy := y + (i / 2) * lh
		var lbl := UI.fit_line(font, InitialStats.label_text(r), 9, cw - UI.en_width(font, str(r.en), 8, 2.0) - 12.0, 7)
		var ew := UI.code(self, font, Vector2(cx, cy), str(r.en), 8, UI.fa(UI.C_L_SUB, a))
		UI.text_at(self, font, Vector2(cx + ew + 4, cy - 2), lbl[0], lbl[1], UI.fa(UI.C_L_SUB, a))
		var fl := UI.fit_line(font, InitialStats.value_text(r), vs, cw - 10.0, 10)
		UI.text_at(self, font, Vector2(cx, cy + 12), fl[0], fl[1], UI.fa(UI.C_L_INK, a), "la", fl[1] >= 18)
		if i % 2 == 1 or i == all.size() - 1:
			draw_line(Vector2(x0, cy + lh - 6.0), Vector2(box.end.x, cy + lh - 6.0), UI.fa(UI.C_L_INK, 0.18 * a), 1.0)
	y += ceili(all.size() / 2.0) * lh + 2.0
	a = _rowm(2 + ceili(all.size() / 2.0), am, odx, motion)
	var cx2 := x0
	for c in sh.tags:
		var cwid: float = font.get_string_size(str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 10 if ph else 11).x + 22.0
		if cx2 + cwid > box.end.x:
			cx2 = x0
			y += 24.0
		cx2 += UI.ctag(self, font, Vector2(cx2, y), str(c), 10 if ph else 11, false, a)
	y += 26.0
	var nf := UI.fit_line(font, str(sh.note), 10 if ph else 11, w, 8)
	UI.text_at(self, font, Vector2(x0, minf(y, box.end.y - 14.0)), nf[0], nf[1], UI.fa(UI.C_L_SUB, a))


## 技能页数据：[代码, 名称, 英文, 图标, SP, 标签, 手动, 说明]
func _skill_rows(cd: Dictionary) -> Array:
	var rows: Array = []
	if cd.has("attack"):
		rows.append(["ATTACK  //  普攻", str(cd.attack.get("name", "")), "", "", "", "普攻", false, str(cd.attack.get("desc", ""))])
	var sks: Array = cd.get("skills", [])
	for si in sks.size():
		var sk: Dictionary = sks[si]
		var tag := "自动"
		if sk.get("mode", "auto") == "manual":
			tag = "手动 Q"
		elif sk.get("permanent", false):
			tag = "永久"
		rows.append(["SKILL %d  //  %s" % [si + 1, ["招募", "精英一", "精英二"][mini(si, 2)]], str(sk.get("name", "")), str(sk.get("en", "")), str(sk.get("icon", "")),
			str(int(sk.sp)) if sk.has("sp") else "", tag, sk.get("mode", "auto") == "manual", str(sk.get("desc", ""))])
	if cd.has("talent"):
		rows.append(["TALENT  //  精英一", str(cd.talent.get("name", "")), "", "", "", "天赋", false, str(cd.talent.get("desc", ""))])
	return rows


func _c_skills(e: Dictionary, box: Rect2, ph: bool, am: float, odx: float, motion: bool) -> void:
	var cd: Dictionary = e.op
	var x0 := box.position.x
	var w := box.size.x
	var y := box.position.y
	# 大数字：初始生命 / 攻击 / 间隔 / 范围（数字跳动；间隔从 2× 降到终值）
	var a := _rowm(0, am, odx, motion)
	var sh: Dictionary = _sheet(e)
	var cnt := _count() if motion else 1.0
	var defs := [["hp", "生命", "HP"], ["atk", "Mon3tr" if b_mon3tr(sh) else "攻击", "ATK"], ["cd", "间隔", "INT"], ["reach", "范围", "RNG"]]
	var cw := w / 4.0
	for j in defs.size():
		var raw: String = str(InitialStats.row(sh, defs[j][0]).text).split(" ")[0]
		var v := raw.to_float()
		var shown: String
		if defs[j][0] == "cd":
			shown = "%.2f" % (v * (2.0 - cnt))
		elif "." in raw:
			shown = "%.1f" % (v * cnt)
		else:
			shown = "%d" % int(round(v * cnt))
		UI.stat_big(self, font, Vector2(x0 + j * cw, y), defs[j][1], defs[j][2], shown, 16 if ph else 20, UI.C_L_INK, UI.C_L_SUB, a)
	y += 38.0 if ph else 46.0
	var rows := _skill_rows(cd)
	var hh := 28.0 if ph else 46.0
	var gap := 4.0 if ph else 6.0
	var hs := _row_heights(rows.map(func(r): return r[7]), box.end.y - y, hh, gap, w - (16.0 if ph else 24.0), ph)
	for i in rows.size():
		a = _rowm(i + 1, am, odx, motion)
		var r: Array = rows[i]
		var rr := Rect2(x0, y, w, hs[i])
		UI.cpanel(self, rr, r[6], a)
		if ph:
			hits.append([rr, "row", i])
		var isz := 24.0 if ph else 32.0
		var ib := Rect2(x0 + (6 if ph else 8), y + (3 if ph else 7), isz, isz)
		draw_rect(ib, UI.fa(UI.C_L_INK, a))
		var itx: Texture2D = A.tex(r[3]) if r[3] != "" else null
		if itx != null:
			draw_texture_rect(itx, ib.grow(-2.0), false, Color(1, 1, 1, a))
		else:
			UI.text_at(self, font, ib.get_center() + Vector2(0, 1), "A" if i == 0 else "T", 13 if ph else 15, UI.fa(UI.C_L_INV, a), "mm", true)
		var tx0 := ib.end.x + 8.0
		var right := rr.end.x - 8.0
		if r[4] != "":
			var spw := UI.text_at(self, font, Vector2(right, y + (2 if ph else 4)), r[4], 16 if ph else 20, UI.fa(UI.C_L_INK, a), "ra", true)
			UI.code(self, font, Vector2(right, y + (20 if ph else 29)), "SP", 7, UI.fa(UI.C_L_SUB, a), "ra")
			right -= maxf(spw, 14.0) + 8.0
		var tgw := font.get_string_size(r[5], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 22.0
		var tg := Rect2(right - tgw, y + (5 if ph else 8), tgw, 18)
		UI.para(self, tg, 6, UI.fa(UI.C_ACC, a) if r[6] else Color(0, 0, 0, 0), Color(0, 0, 0, 0) if r[6] else UI.fa(UI.C_L_INK, a))
		UI.text_at(self, font, tg.get_center() + Vector2(0, 1), r[5], 10, UI.fa(UI.C_HZ if r[6] else UI.C_L_INK, a), "mm")
		if not ph:
			UI.code(self, font, Vector2(tx0, y + 5), r[0], 7, UI.fa(UI.C_L_SUB, a))
		var nf := UI.fit_line(font, r[1], 12 if ph else 14, tg.position.x - tx0 - 6.0, 9)
		UI.text_at(self, font, Vector2(tx0, y + (8 if ph else 15)), nf[0], nf[1], UI.fa(UI.C_L_INK, a))
		if not ph and r[2] != "":
			UI.code(self, font, Vector2(tx0 + 1, y + 33), r[2], 7, UI.fa(UI.C_L_SUB, a))
		_row_desc(r[7], rr, hh, ph, a)
		y += hs[i] + gap


## 成长页：progression 节点按出现顺序竖排（成长节点用 growth_* 图标，精英化用本人二 / 三技能图标 + 黄底）；局内升级时成长卡按此顺序出现
func _c_growth(e: Dictionary, box: Rect2, ph: bool, am: float, odx: float, motion: bool) -> void:
	var cd: Dictionary = e.op
	var nodes: Array = cd.get("progression", [])
	var sks: Array = cd.get("skills", [])
	var x0 := box.position.x
	var lx := x0 + (0.0 if ph else 8.0)
	var cx0 := lx + (0.0 if ph else 18.0)
	var w := box.end.x - cx0
	var y := box.position.y
	var hh := 28.0 if ph else 40.0
	var gap := 4.0 if ph else 8.0
	var bottom := box.end.y - (0.0 if ph else 18.0)
	var descs: Array = nodes.map(func(nd): return str(nd.get("desc", "")) if nd is Dictionary else "")
	var hs := _row_heights(descs, bottom - y, hh, gap, w - (16.0 if ph else 24.0), ph)
	if not ph and nodes.size() > 1:
		var a0 := _rowm(0, am, odx, motion)
		var yl := y + 18.0
		var yz := y
		for i in nodes.size() - 1:
			yz += hs[i] + gap
		draw_line(Vector2(lx, yl), Vector2(lx, yz + 18), UI.fa(UI.C_L_INK, a0), 2.0)
	var ei := 0
	for i in nodes.size():
		var nd: Dictionary = nodes[i] if nodes[i] is Dictionary else {}
		var a := _rowm(i, am, odx, motion)
		var el: bool = nd.get("type", "") == "elite"
		var icon: String = str(nd.get("icon", ""))
		if el:
			var si: int = 1 if int(nd.get("level", 1)) == 1 else 2
			if icon == "" and si < sks.size():
				icon = str(sks[si].get("icon", ""))
			ei += 1
		if icon == "" or A.tex(icon) == null:
			icon = "growth_hp"
		if not ph:
			var mk := Rect2(lx - 7, y + 11, 14, 14)
			draw_rect(mk, UI.fa(UI.C_ACC if el else UI.C_L_INK, a))
			draw_rect(mk, UI.fa(UI.C_L_INK, a), false, 2.0)
		var rr := Rect2(cx0, y, w, hs[i])
		UI.cpanel(self, rr, el, a)
		if ph:
			hits.append([rr, "row", i])
		var isz := 24.0 if ph else 32.0
		var ib := Rect2(cx0 + (6 if ph else 8), y + (3 if ph else 4), isz, isz)
		draw_rect(ib, UI.fa(UI.C_L_INK, a))
		var itx: Texture2D = A.tex(icon)
		if itx != null:
			draw_texture_rect(itx, ib.grow(-2.0), false, Color(1, 1, 1, a))
		var tx0 := ib.end.x + 8.0
		var lbl := ("精英化" if el else "成长")
		var lw := UI.text_at(self, font, Vector2(rr.end.x - 8, y + (9 if ph else 12)), lbl, 10, UI.fa(UI.C_L_SUB, a), "ra")
		if not ph:
			UI.code(self, font, Vector2(tx0, y + 3), "NODE %02d" % (i + 1), 7, UI.fa(UI.C_L_SUB, a))
		var nf := UI.fit_line(font, str(nd.get("name", "")), 12 if ph else 13, rr.end.x - 16.0 - lw - tx0, 9)
		UI.text_at(self, font, Vector2(tx0, y + (8 if ph else 14)), nf[0], nf[1], UI.fa(UI.C_L_INK, a))
		_row_desc(descs[i], rr, hh, ph, a)
		y += hs[i] + gap
	if not ph:
		var a2 := _rowm(nodes.size(), am, odx, motion)
		UI.text_at(self, font, Vector2(x0, box.end.y - 12), "探索中升级时，成长卡按这个顺序出现；精英化同时解锁新技能。", 10, UI.fa(UI.C_L_SUB, a2))


## 各行高度：桌面每行 = 标题 + 说明（字号 12 → 10，仍放不下就平分剩余高度并截断）；
## 手机 = 未展开时每行标题 + 一行说明，点开一行后其余只留标题、这一行拿剩下的高度
func _row_heights(descs: Array, avail: float, hh: float, gap: float, dw: float, ph: bool) -> Array:
	var n := descs.size()
	var out: Array = []
	if n == 0:
		return out
	var room := avail - gap * (n - 1)
	if ph:
		if row_sel < 0 or row_sel >= n:
			var h := minf(46.0, room / n)
			for i in n:
				out.append(h)
			return out
		var small := 28.0
		for i in n:
			out.append(small if i != row_sel else maxf(small, room - small * (n - 1)))
		return out
	for fs in [12, 11, 10]:
		var tot := 0.0
		var hs: Array = []
		for d in descs:
			var h2: float = hh + (UI.fit(font, d, dw, 9999.0, [fs]).h if d != "" else 0.0) + 8.0
			hs.append(h2)
			tot += h2
		if tot <= room:
			return hs
	var each := room / n
	for i in n:
		out.append(each)
	return out


## 行内说明：桌面在标题下按剩余高度排（12 → 10，截断加「…」）；手机未展开时一行、展开时整段
func _row_desc(d: String, rr: Rect2, hh: float, ph: bool, a: float) -> void:
	if d == "":
		return
	var x := rr.position.x + (8.0 if ph else 12.0)
	var w := rr.size.x - (16.0 if ph else 24.0)
	var top := rr.position.y + hh
	var room := rr.end.y - top - 4.0
	if room < (6.0 if ph else 10.0):
		return
	if ph and room < 24.0:
		if room < 8.0:
			return
		var fl := UI.fit_line(font, d.replace("\n", " "), 10, w, 10)
		UI.text_at(self, font, Vector2(x, top - 2), fl[0], fl[1], UI.fa(UI.C_L_SUB, a))
		return
	var f := UI.fit(font, d, w, room, [12, 11, 10] if not ph else [11, 10])
	UI.draw_fit(self, font, Vector2(x, top - 2), f, UI.fa(UI.C_L_SUB if ph else UI.C_L_INK, a))


## 非干员（和博士 / 未解锁）的数据面板：类别代码 + 标签行 + 大数字属性 + 标签片 + 说明
func _draw_data(e: Dictionary, ph: bool, px: Vector2, oa: float, odx: float) -> void:
	var locked: bool = e.get("locked", false)
	var a := oa
	if tab == 0 and not locked:
		a = _rowm(0, oa, odx, true)
	var x0 := px.x
	var w := px.y - px.x
	var y := 14.0 if ph else 72.0
	UI.code(self, font, Vector2(x0, y), "%s FILE  //  %s" % [str(TABS[tab].en), "LOCKED" if locked else "DATA"], 7 if ph else 8, UI.fa(UI.C_L_SUB, a))
	y += 20.0 if ph else 16.0
	var tag: String = str(e.get("tag", ""))
	UI.text_at(self, font, Vector2(x0, y), ("???" if locked else str(e.name)) if ph else tag, 15 if ph else 17, UI.fa(UI.C_L_INK, a), "la", true)
	if ph and not locked:
		UI.text_at(self, font, Vector2(px.y, y + 4), tag, 10, UI.fa(UI.C_L_SUB, a), "ra")
	y += 26.0 if ph else 30.0
	draw_line(Vector2(x0, y), Vector2(px.y, y), UI.fa(UI.C_L_INK, a), 2.0)
	y += 10.0
	if locked:
		var lf := UI.fit(font, str(e.get("locked_text", "")), w, (352.0 if ph else 680.0) - y, [13, 12, 11])
		UI.draw_fit(self, font, Vector2(x0, y), lf, UI.fa(UI.C_L_INK, a))
		return
	# 属性：短值两列大数字；长值（流派、效果分类…）占整行
	var cw := w / 2.0
	var col := 0
	for s in e.get("stats", []):
		var lbl := str(s[0])
		var val := str(s[1])
		var en_s: String = STAT_EN.get(lbl, "DATA")
		var vs := 15 if ph else 18
		var long: bool = font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x > cw - 8.0
		if long and col == 1:
			col = 0
			y += 36.0 if ph else 42.0
		if long:
			UI.code(self, font, Vector2(x0, y), en_s, 7, UI.fa(UI.C_L_SUB, a))
			UI.text_at(self, font, Vector2(x0 + UI.en_width(font, en_s, 7) + 4, y - 2), lbl, 9, UI.fa(UI.C_L_SUB, a))
			var ff := UI.fit(font, val, w, 34.0, [13, 12, 11])
			y += 12.0 + UI.draw_fit(self, font, Vector2(x0, y + 12), ff, UI.fa(UI.C_L_INK, a)) + 6.0
			continue
		UI.stat_big(self, font, Vector2(x0 + col * cw, y), lbl, en_s, val, vs, UI.C_L_INK, UI.C_L_SUB, a)
		col += 1
		if col == 2:
			col = 0
			y += 36.0 if ph else 42.0
	if col == 1:
		y += 36.0 if ph else 42.0
	var cx := x0
	var chips: Array = e.get("chips", [])
	if not chips.is_empty():
		for c in chips:
			var cwid: float = font.get_string_size(str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0
			if cx + cwid > px.y:
				cx = x0
				y += 24.0
			cx += UI.ctag(self, font, Vector2(cx, y), str(c), 10 if ph else 11, false, a)
		y += 28.0
	draw_line(Vector2(x0, y), Vector2(px.y, y), UI.fa(UI.C_L_INK, 0.3 * a), 1.0)
	y += 8.0
	var f := UI.fit(font, str(e.get("desc", "")), w, (352.0 if ph else 688.0) - y, [13, 12, 11, 10] if not ph else [11, 10, 9])
	UI.draw_fit(self, font, Vector2(x0, y), f, UI.fa(UI.C_L_INK, a))


func _draw_hint(ph: bool) -> void:
	if ph or Pad.touch_ui():
		return
	var s := Pad.hint("Q / E 分类 · 方向键选择（最左再 ← 进职业轨）· Z / X 动作 · Enter 页签 · Esc 返回", "LB / RB 分类 · 十字键选择 · Ⓧ / Ⓨ 动作 · Ⓐ 页签 · Ⓑ 返回")
	var fl := UI.fit_line(font, s, 11, 404.0, 9)
	UI.text_at(self, font, Vector2(24, 694), fl[0], fl[1], UI.C_D_SUB)


# ---------------------------------------------------------------- 干员档案文字
## 档案页：介绍段落 + 【本作定位】；手机版式的名字块没有档案小表，性别 / 出身 / 种族 / 所属放在第一段
func _op_profile(cid: String, cd: Dictionary, with_fields := false) -> Array:
	var lr: Dictionary = lore.get(cid, {})
	var out: Array = []
	var pf: Dictionary = lr.get("profile", {})
	if with_fields:
		var fields: Array = []
		for k in ["性别", "出身地", "种族", "所属"]:
			if pf.has(k) and str(pf[k]) != "":
				fields.append("%s：%s" % [k, pf[k]])
		if not fields.is_empty():
			out.append("　".join(fields))
	if lr.has("lore"):
		out.append(str(lr.lore))
	var mech: String = cd.get("gallery", {}).get("desc", "")
	if mech != "":
		out.append("【本作定位】" + mech)
	return out
