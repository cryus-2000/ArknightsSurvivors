extends Control
## 图鉴：展示游戏里的各类贴图（干员 / 敌人 / 精英 / Boss / 道具），藏品页待藏品系统完成后开放。
## 从标题菜单打开；Q/E 或点击切换分页，方向键或点击选择条目，Z/X 或点击切换动作/形态，Esc 返回。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Doctor = preload("res://scripts/characters/doctor.gd")
const Character = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")

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
	"slider": "贴着海床高速滑行。近战；冲刺撞上主控时额外熄灭 8 点灯火。",
	"stone": "远程投掷碎石；停下射击时会掘入海床，变得更难击退。",
	"offspring": "伊祖米克的子代，行动迟缓但生命很高；碰到主控时蜕变成 2 只其他海嗣。",
	"brood": "由投嗣育母产下的诱饵，不会移动并逐渐衰亡，接触造成侵蚀。",
	"fractal": "塑路者碎裂时放出的高速碎片。",
	"spitter": "远程抛射酸液：落点先出预警，落地造成范围伤害并留下溟痕，命中附带侵蚀。",
	"tear": "伊莎玛拉人形阶段留下的泪滴，不会伤害主控；未被压制时会加快转化充能。主控靠近泪滴即可压制，转化后泪滴消失。",
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
	"ishar": "结局三「息潮的代价」的最终 Boss。人形阶段治疗受伤海嗣，不攻击主控，干员也不会以她为目标；转化充能随时间增长，未被主控靠近压制的之泪会加快充能。充满后变为敌对白壳海嗣，使用弹幕、潮汐吐息与近身潮噬；未压制的泪滴会在变身后发动「泪滴共鸣」。",
	"knight_boss": "结局二「静谧时代」的最终 Boss。冲锋附带冰霜，近身长枪三连刺，周期展开寒冰领域；「冰线」之后发动「寒冷追击」，第一次生命归零后寒冰重生进入二阶段。",
	"knight": "精英。堕入海嗣的最后的骑士——只在同伴骑士道中阵亡后出现。直线冲锋，命中附带冰霜减速。",
}
const RelicDb = preload("res://scripts/core/relic_db.gd")
var lore: Dictionary = {}       # data/lore.json
var relic_db: RefCounted
var scroll := 0                 # 网格滚动的行数
const COLS := 5
const ROWS := 4


## 手机（触屏，界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：格子 4 列、可视行数按高度算（约 2 行），详情面板相应变窄
func phone() -> bool:
	return Cfg.touch_device() and size.y < 520.0


func cols() -> int:
	return 4 if phone() else COLS


func rows_vis() -> int:
	return maxi(1, int((size.y - 150.0 - 46.0 + 10.0) / 124.0)) if phone() else ROWS

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
## 攻击演示：把 game.tscn 以 demo_op 模式放进 SubViewport，在展示台位置画出来（见 scripts/run/demo.gd）
var demo_vp: SubViewport
var demo_game: Node
var demo_id := ""
## 手动切换（2026-09-26 用户要求）：阶段 0 精零 / 1 精一 / 2 精二；动作 -1 轮播 / 0–2 只放该技能 / 3 只普攻。换干员时保留，方便横向比较
var demo_stage := 2
var enemy_demo_mode := 0
var demo_mode := -1
var demo_rects: Array = []       # [Rect2, "stage" | "mode", 值]
## 干员详情的信息页（2026-09-26）：档案 / 技能 / 数值 分页显示，解决「档案 + 三技能 + 天赋挤在一个文本框里放不下」
var info_tab := 0
var info_rects: Array = []
const INFO_TABS := ["档案", "技能", "数值"]
const DEMO_H := 290
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


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
			var atk := "player_attack_48" if A.tex("player_attack_48") != null else "player_attack"
			# 博士：受击体（data/doctor.json）
			var dd: Dictionary = {}
			var df := FileAccess.open("res://data/doctor.json", FileAccess.READ)
			if df != null:
				var dj = JSON.parse_string(df.get_as_text())
				if dj is Dictionary:
					dd = dj
			var ds: Dictionary = dd.get("stats", {})
			entries.append({"name": dd.get("name", "博士"), "en": dd.get("en", "DOCTOR"), "tag": "指挥 · 随行", "forms": _doctor_forms(dd),
				"stats": [["回复", "%.1f / 秒" % float(ds.get("regen", 0.0))], ["移速", str(int(ds.get("move_speed", 150)))],
					["闪避", "%d%%" % int(float(ds.get("dodge", 0.0)) * 100.0)], ["拾取", str(int(ds.get("pickup", 70)))]],
				"chips": ["随行", "指挥", "排异"], "desc": _lore_text("doctor", "罗德岛的高层领导，三大创始人之一。作为矿石病治疗与天灾研究方面的顶尖学者，拥有生物学，神经工程学博士等学历。致力于清除矿石病，是罗德岛的中流砥柱之一。虽然本身没有战斗能力，但是拥有极强的指挥能力。")})
			# 干员：data/characters/*.json（职业、普攻 / 技能 / 天赋、成长线）
			for cid in Character.list_ids():
				var cd: Dictionary = Character.load_def(cid)
				var sp: Dictionary = cd.get("sprites", {})
				var st: Array = []
				if cd.has("attack"):
					st.append(["普攻", cd.attack.get("name", "")])
				var sks: Array = cd.get("skills", [])
				for si in sks.size():
					st.append(["技能 %d" % (si + 1), "%s · %s" % [sks[si].get("name", ""), ["招募", "精英一", "精英二"][si]]])
				if cd.has("talent"):
					st.append(["天赋", cd.talent.get("name", "")])
				var forms: Array = []
				# 专属动作（docs/32 验收 §2 接线的新帧条）：有就列出来，没有就跳过
				for kind in [["待机", "idle", 4.0], ["跑步", "run", 10.0], ["攻击", "attack", 8.0], ["技能", "skill", 12.0],
						["号令", "command", 12.0], ["治疗", "skill_heal", 12.0], ["旋斩", "attack_spin", 12.0], ["倒下", "fall", 10.0],
						["受击", "hurt", 6.0], ["倒下", "death", 5.0]]:
					if not sp.has(kind[1]):
						continue
					var fm: Dictionary = _sprite_form(kind[0], sp[kind[1]], kind[2], kind[1] != "death" and kind[1] != "fall")
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
				entries.append({"name": cd.get("name", cid), "en": cd.get("en", cid.to_upper()), "tag": "%s干员" % cd.get("class", ""), "forms": forms,
					"stats": st, "chips": cd.get("gallery", {}).get("tags", []), "desc": _lore_text(cid, mech),
					"pages": {"档案": _op_profile(cid, cd), "技能": _op_skill_rows(cd), "数值": _op_numbers(cid, cd)}})
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
					"locked": not Cfg.unlock_all and not Cfg.gallery_seen.has("enemy:" + str(k)), "locked_text": "尚未遭遇。在冒险中遭遇后收录。"})
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
			# 藏品：已实装的全部列出；没获得过的显示为 ???
			var lst: Array = relic_db.implemented()
			var order := {"基础": 0, "稀有": 1, "核心": 2, "升华": 3, "遭诅古物": 4, "结局": 5}
			lst.sort_custom(func(a, b): return (order.get(a.rarity, 9) * 1000 + int(a.id)) < (order.get(b.rarity, 9) * 1000 + int(b.id)))
			for r in lst:
				var seen: bool = Cfg.seen_relics.has(r.id)
				var stt: Array = [["等级", r.rarity], ["效果分类", relic_db.effect_category_names.get(r.effect_category, r.get("cat", ""))], ["原类别", r.get("cat", "")]]
				if r.has("lanes") and not r.lanes.is_empty():
					stt.append(["流派", " / ".join(r.lanes.map(func(l): return "%s %s" % [l, str(relic_db.lane_names.get(l, "")).split("（")[0]]))])
				entries.append({"id": r.id, "name": r.name, "en": "NO. " + r.id, "tag": "藏品 · " + r.rarity, "forms": [_anim_n("图标", "relic_" + r.id, 1, 1.0)],
					"stats": stt, "chips": [], "desc": r.get("desc", ""), "locked": not seen and not Cfg.dev_args().has("--allrelics"), "locked_text": "尚未获得。在一局中拿到它之后会收录到这里。"})
		4:
			entries.append({"name": "经验结晶", "en": "EXP", "tag": "掉落物", "forms": [_anim_n("小", "gem_small", 1, 1.0), _anim_n("大", "gem_big", 1, 1.0)], "stats": [], "desc": "击败敌人掉落，拾取后获得经验。"})
			entries.append({"name": "灯油", "en": "OIL", "tag": "掉落物", "forms": [_anim_n("灯油", "oil", 1, 1.0)], "stats": [], "desc": "补充灯火。灯火过低时敌人更快、更凶，熄灭后持续受到伤害。"})
			entries.append({"name": "源石锭", "en": "INGOT", "tag": "货币", "forms": [_anim_n("源石锭", "ingot", 1, 1.0)], "stats": [], "desc": "精英、Boss 与箱形恐鱼会掉落，可在局内商人处购买藏品与补给。"})
			entries.append({"name": "磁铁", "en": "MAGNET", "tag": "道具", "forms": [_anim_n("磁铁", "pickup_magnet", 1, 1.0)], "stats": [], "desc": "拾取后吸取全场的经验结晶、灯油与源石锭。小怪低概率掉落，精英与 Boss 必掉磁铁或回复药剂。"})
			entries.append({"name": "回复药剂", "en": "HEAL", "tag": "道具", "forms": [_anim_n("回复药剂", "pickup_heal", 1, 1.0)], "stats": [], "desc": "拾取后立即回复 30% 最大生命。"})
			entries.append({"name": "补给箱", "en": "CHEST", "tag": "宝箱", "forms": [_anim_n("补给箱", "e_chest", 2, 1.0)], "stats": [], "desc": "地图上定期出现，打开后获得藏品。其中一部分是伪装的箱形恐鱼。"})
			for sp in [["遗迹残柱", "PILLAR", "prop_pillar", 1], ["断墙", "RUINED WALL", "prop_wall", 1], ["沉船碎片", "WRECK", "prop_wreck", 1],
					["海底岩脊", "RIDGE", "terrain_ridge", 1], ["海底山峰", "PEAK", "terrain_peak", 1], ["溟痕", "MIRE", "terrain_mire", 2], ["引航灯标", "BEACON", "prop_beacon", 2]]:
				if A.tex(sp[2]) != null:
					entries.append({"name": sp[0], "en": sp[1], "tag": "场景", "forms": [_anim_n(sp[0], sp[2], sp[3], 2.0)], "stats": [],
						"desc": {"terrain_mire": "地面上周期性出现并逐渐扩大的溟痕。站在上面会减速、持续受伤并累积神经损伤；点燃引航灯标可以驱散。", "prop_beacon": "仿照伊比利亚灯塔做的小型信标，熄灭着立在海床上。站进光圈点燃它，灯光会驱散周围的溟痕、清空神经损伤，这片地方也暂时不会再长出溟痕。"}.get(sp[2], "深海遗迹中的场景物件，会与角色前后遮挡。")})
			entries.append({"name": "商人", "en": "MERCHANT", "tag": "NPC", "forms": [_anim_n("商人", "merchant", 2, 2.0)], "stats": [], "desc": "局内会出现 3 次，停留 60 秒。靠近即可交易：藏品、回复、灯油与刷新。"})
	if tab == 4:
		for entry in entries:
			entry["locked"] = not Cfg.unlock_all and not Cfg.gallery_seen.has("item:" + str(entry.en))
			entry["locked_text"] = "尚未发现。在冒险中发现后收录。"
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
var drag_acc := 0.0   # 触屏上下滑动翻页（没有滚轮）


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Pad.touch and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		drag_acc += event.relative.y
		if absf(drag_acc) > 60.0:
			var ms: int = maxi(0, ceili(entries.size() / float(cols())) - rows_vis())
			scroll = clampi(scroll + (-1 if drag_acc > 0.0 else 1), 0, ms)
			drag_acc = 0.0
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP):
		var max_scroll: int = maxi(0, ceili(entries.size() / float(cols())) - rows_vis())
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
		for ir in info_rects:
			if ir[0].has_point(event.position):
				info_tab = ir[1]
				Sfx.play("ui_move")
				accept_event()
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
	var row: int = sel / cols()
	if row < scroll:
		scroll = row
	elif row >= scroll + rows_vis():
		scroll = row - rows_vis() + 1


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
	UI.text(self, font, close_rect.position + Vector2(0, 24), Pad.hint("返回  Esc", "返回  Ⓑ", "返回"), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, close_rect.size.x)
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
	if entries.size() > cols() * rows_vis():
		var max_scroll: int = maxi(0, ceili(entries.size() / float(cols())) - rows_vis())
		UI.text(self, font, Vector2(60, vs.y - 34), ("上下滑动翻页  %d / %d" if Pad.touch_ui() else "滚轮翻页  %d / %d") % [scroll + 1, max_scroll + 1], 12, UI.SUB)
	UI.text(self, font, Vector2(0, vs.y - 22), Pad.hint("Q / E 切换分页 · 方向键选择 · Z / X 切换动作与形态 · Esc 返回", "LB / RB 切换分页 · 摇杆选择 · Ⓧ / Ⓨ 切换动作与形态 · Ⓑ 返回", "点上方分页切换 · 点格子查看 · 点动作 / 形态按钮切换"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


var _white_cache := {}
func _white_of(tx: Texture2D) -> Texture2D:
	if not _white_cache.has(tx):
		_white_cache[tx] = A.white_of(tx)
	return _white_cache[tx]


func _form_frame(f: Dictionary) -> int:
	var fr := int(form_t * f.fps)
	return fr % f.frames if f.loop else mini(fr, f.frames - 1)


func _frame_rect(f: Dictionary, frame: int) -> Rect2:
	var tx: Texture2D = f.tex
	var fw: int = tx.get_width() / f.frames
	return Rect2(fw * (frame % f.frames), 0, fw, tx.get_height())


func _draw_grid() -> void:
	tile_rects.clear()
	var max_scroll: int = maxi(0, ceili(entries.size() / float(cols())) - rows_vis())
	scroll = clampi(scroll, 0, max_scroll)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row: int = i / cols() - scroll
		var r := Rect2(60 + (i % cols()) * 110, 150 + row * 124, 100, 114)
		tile_rects.append(r)
		if row < 0 or row >= rows_vis():
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
			var col: Color = Color(0, 0, 0, 0.9) if e.get("locked", false) else f.get("tint", Color.WHITE)
			draw_texture_rect_region(f.tex, Rect2((c - sz / 2).round(), sz), src, col)
		var nm: String = "???" if e.get("locked", false) else e.name
		var nfl: Array = UI.fit_line(font, nm, 13, r.size.x - 6.0, 9)   # 长名字（《杜林地上环游记》）按格宽缩到 9 号
		UI.text(self, font, r.position + Vector2(2, 104), nfl[0], nfl[1], UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 4)


func _draw_detail(vs: Vector2) -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries[sel]
	var locked: bool = e.get("locked", false)
	var ph: bool = phone()
	var pr := Rect2(640, 150, vs.x - 700, vs.y - 200) if not ph else Rect2(60 + cols() * 110 + 10, 150, vs.x - (60 + cols() * 110 + 10) - 40, vs.y - 190)
	UI.panel(self, pr, Color(0.02, 0.06, 0.09, 0.9), UI.LINE, 14.0, UI.CYAN, 71, t)
	form = clampi(form, 0, e.forms.size() - 1)
	var f: Dictionary = e.forms[form]
	var is_enemy_demo: bool = f.has("enemy_demo")
	var demo: bool = (f.has("demo") or is_enemy_demo) and not locked
	# 展示台（演示时换成横贯面板的实机画面，名称 / 属性文字让位）；手机：展示台 200×120、演示画面占到面板底
	var demo_h: float = DEMO_H if not ph else pr.size.y - 40.0
	var box := Rect2(pr.position + Vector2(20, 20), Vector2(260, demo_h if demo else 236) if not ph else Vector2(200, demo_h if demo else 120))
	if demo:
		var dr := Rect2(box.position, Vector2(pr.size.x - 40, demo_h))
		if is_enemy_demo:
			_enemy_demo_start(f.enemy_demo, Vector2i(dr.size))
		else:
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
		if is_enemy_demo:
			rows = [["enemy_replay", [["重播", 0]]]]
			if f.enemy_demo in ["ishar", "paranoia", "knight_boss", "izumik"]:
				rows.push_front(["enemy_phase", [["完整转化", 0], ["人形治疗", 1], ["敌对", 2]]] if f.enemy_demo == "ishar" else ["enemy_phase", [["轮播", 0], ["一阶段", 1], ["二阶段", 2]]])
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
				var on: bool = enemy_demo_mode == v if kind == "enemy_phase" else ((demo_stage == v) if kind == "stage" else (demo_mode == v and kind == "mode"))
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
	# 技能 / 数值页：信息区占满面板，立绘缩小到名字左侧的小展示台，不画动作按钮
	var wide: bool = e.has("pages") and not locked and not demo and info_tab != 0
	if wide:
		box = Rect2(pr.position + Vector2(20, 14), Vector2(260, 110))
		base = box.position + Vector2(box.size.x / 2, box.size.y - 6)
	if not demo and not wide:
		draw_circle(base + Vector2(0, -90), 120.0, Color(0.3, 0.8, 0.9, 0.05))
		draw_set_transform(base, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 80.0, Color(0.3, 0.8, 0.9, 0.12))
		draw_arc(Vector2.ZERO, 80.0, 0.0, TAU, 40, Color(0.3, 0.9, 0.9, 0.5), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pf: Dictionary = f.get("pair", {})
	if f.tex != null and pf.get("tex") != null:
		# 本体 + 召唤物并排（同一倍率，保持相对大小）：本体在左、召唤物在右，脚下各一行小字
		var src := _frame_rect(f, _form_frame(f))
		var src2 := _frame_rect(pf, _form_frame(pf))
		var gap := 4.0
		var k: float = minf((250.0 if not ph else 190.0) / (src.size.x + src2.size.x + gap), (100.0 if (wide or ph) else 190.0) / maxf(src.size.y, src2.size.y))
		k = floorf(minf(k, 6.0)) if k >= 1.0 else k
		var sz := src.size * k
		var sz2 := src2.size * k
		var x0: float = base.x - (sz.x + sz2.x + gap * k) / 2.0
		var col := Color(0, 0, 0, 0.95) if locked else Color.WHITE
		draw_texture_rect_region(f.tex, Rect2(Vector2(x0, base.y - sz.y + 6).round(), sz), src, col)
		draw_texture_rect_region(pf.tex, Rect2(Vector2(x0 + sz.x + gap * k, base.y - sz2.y + 6).round(), sz2), src2, col)
		if not wide and not locked:
			UI.text(self, font, Vector2(x0 - 20, base.y + 28), f.get("main_label", ""), 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sz.x + 40)
			UI.text(self, font, Vector2(x0 + sz.x + gap * k - 20, base.y + 28), pf.get("pair_label", f.get("pair_label", "")), 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sz2.x + 40)
	elif f.tex != null:
		var src := _frame_rect(f, _form_frame(f))
		var fitk: float = minf((240.0 if not ph else 180.0) / src.size.x, (100.0 if (wide or ph) else 200.0) / src.size.y)
		var k: float = floorf(minf(fitk, 6.0)) if fitk >= 1.0 else fitk
		var ds: float = float(f.get("dscale", 1.0))
		if ds > 1.05:
			k = floorf(minf(fitk, k * ds)) if fitk >= 1.0 else fitk   # 巨骸等放大的怪在展示台上也更大（受台面限制）
		var sz := src.size * k
		var col: Color = Color(0, 0, 0, 0.95) if locked else f.get("tint", Color.WHITE)
		var rect := Rect2((base - Vector2(sz.x / 2, sz.y - 6)).round(), sz)
		if tab in [1, 2, 3] and not locked:
			# 敌人：一圈淡青白描边（同实战「怪物轮廓光」），深色小怪（塑路者碎片）在暗色展示台上也看得清
			var wt: Texture2D = _white_of(f.tex)
			for d in [Vector2(k, 0), Vector2(-k, 0), Vector2(0, k), Vector2(0, -k)]:
				draw_texture_rect_region(wt, Rect2(rect.position + d, rect.size), src, Color(0.7, 0.85, 0.95, 0.55))
		draw_texture_rect_region(f.tex, rect, src, col)
	# 动作 / 形态切换
	form_rects.clear()
	if e.forms.size() > 1 and not locked and not wide:
		# 按钮宽度按文字算（至少 44）：长标签不被截断；一行放不下时按比例压窄
		var ws: Array = []
		var total := 0.0
		for i in e.forms.size():
			var w: float = maxf(44.0, font.get_string_size(e.forms[i].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0)
			ws.append(w)
			total += w + 4.0
		var avail: float = pr.end.x - 20.0 - box.position.x
		var squeeze: float = minf(1.0, avail / maxf(total, 1.0))
		var bx: float = box.position.x
		for i in e.forms.size():
			var br := Rect2(bx, box.end.y + 8, ws[i] * squeeze, 28)
			bx += (ws[i] + 4.0) * squeeze
			form_rects.append(br)
			var on: bool = i == form
			UI.panel(self, br, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.06, 0.09, 0.7), UI.CYAN if on else Color(0.2, 0.4, 0.45, 0.5), 5.0)
			var fl: Array = UI.fit_line(font, e.forms[i].label, 12, br.size.x - 6.0, 10)
			UI.text(self, font, br.position + Vector2(0, 19), fl[0], fl[1], UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	# 文字
	var tx := pr.position.x + (300 if not ph else 240)
	var tw := pr.end.x - tx - 20
	var y := pr.position.y + (140 if not ph else 100)
	if wide:
		y = pr.position.y + (134 if not ph else 100)   # 技能 / 数值页：标签紧跟在职业行下，分隔线让到标签下方
	if not demo:
		UI.en(self, font, Vector2(tx, pr.position.y + (40 if not ph else 28)), e.en if not locked else "UNKNOWN", 11, UI.CYAN_DIM, 3.0)
		UI.text(self, font, Vector2(tx, pr.position.y + (76 if not ph else 56)), e.name if not locked else "???", 26 if not ph else 22, UI.TEXT)
		draw_rect(Rect2(Vector2(tx, pr.position.y + (92 if not ph else 68)), Vector2(4, 16)), UI.CYAN)
		UI.text(self, font, Vector2(tx + 12, pr.position.y + (106 if not ph else 82)), e.tag, 14, UI.CYAN)
	if not locked and not demo:
		# 干员有「档案 / 技能 / 数值」分页，右侧不再重复列技能名：标签放在名字下面，下方信息区更高
		if not e.has("pages"):
			for s in e.stats:
				UI.text(self, font, Vector2(tx, y), s[0], 14, UI.SUB)
				UI.text(self, font, Vector2(tx + 60, y), s[1], 15, UI.TEXT)
				y += 26 if not ph else 22
		# 标签行放在动作按钮行之下，避免与按钮重叠（干员页标签在名字下方，不受此限）
		if e.forms.size() > 1 and not e.has("pages"):
			y = maxf(y, box.end.y + 52)
		var cx := tx
		for c in e.get("chips", []):
			var w: float = 16.0 + c.length() * 14.0
			UI.panel(self, Rect2(cx, y - 4, w, 24), Color(0.2, 0.08, 0.25, 0.8), UI.PURPLE, 4.0)
			UI.text(self, font, Vector2(cx, y + 13), c, 12, UI.PURPLE, HORIZONTAL_ALIGNMENT_CENTER, w)
			cx += w + 8
	var dy := maxf(y + 42, box.end.y + 60) if not (e.has("pages") and not locked and not demo) else box.end.y + 64
	if ph:
		dy = maxf(y + 36, box.end.y + 46) if not (e.has("pages") and not locked and not demo) else box.end.y + 50
	if wide:
		dy = y + 50
	if ph and demo:
		return   # 手机：演示画面占满面板，下面没有信息区
	UI.rule(self, Vector2(pr.position.x + 20, dy - 18), Vector2(pr.end.x - 20, dy - 18), UI.CYAN_DIM)
	info_rects.clear()
	if e.has("pages") and not locked:
		_draw_pages(e, pr, dy)
		return
	var desc: String = e.desc if not locked else e.get("locked_text", "尚未遭遇。" + e.desc)
	# 介绍文字：按剩余高度自适应字号（15 → 11）；最小字号仍放不下才截断，末行加「…」，不越出面板
	var avail := pr.end.y - 16.0 - (dy + 4)
	UI.draw_fit(self, font, Vector2(pr.position.x + 24, dy + 4 - font.get_ascent(15) + 2), UI.fit(font, desc, pr.size.x - 48, avail, [15, 14, 13, 12, 11]), Color(0.8, 0.9, 0.92))


# ---------------------------------------------------------------- 干员信息页（档案 / 技能 / 数值）

## 分页标签 + 当前页内容；内容按剩余高度自适应字号（15 → 11），仍放不下才裁行
func _draw_pages(e: Dictionary, pr: Rect2, dy: float) -> void:
	var cx := pr.position.x + 24
	for i in INFO_TABS.size():
		var w: float = font.get_string_size(INFO_TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0
		var r := Rect2(Vector2(cx, dy - 12), Vector2(w, 24))
		var on: bool = i == info_tab
		UI.panel(self, r, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.02, 0.05, 0.08, 0.6), UI.CYAN if on else UI.LINE, 4.0)
		UI.text(self, font, r.position + Vector2(0, 17), INFO_TABS[i], 13, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, w, 2)
		info_rects.append([r, i])
		cx += w + 8
	var top := dy + 22
	var avail := pr.end.y - 14.0 - top
	var width := pr.size.x - 48
	var x := pr.position.x + 24
	var page = e.pages[INFO_TABS[info_tab]]
	match info_tab:
		0:
			_draw_fit_text(page, Vector2(x, top), width, avail)
		1:
			# 技能页：每条「标签 名称」一行 + 说明；整体放不下时统一缩字号
			var fs := 14
			while fs > 10 and _skill_rows_h(page, width, fs) > avail:
				fs -= 1
			# 最小字号还放不下：每条技能都画，说明平分剩余高度，排不完的末行加「…」（不再整条被丢掉）
			var fits := _skill_rows_h(page, width, fs) <= avail
			var per_desc: float = maxf(font.get_height(fs - 1), (avail - page.size() * (fs + 15)) / maxf(1.0, page.size()))
			var yy := top
			if not fits and page.size() * (fs + 8 + font.get_height(fs - 1) + 7) > avail:
				# 演示时信息区只剩约 110 像素：每条一行「标签 名称　说明…」，行高按剩余高度分
				var rh: float = clampf(avail / maxf(1.0, page.size()), 16.0, 24.0)
				for row in page:
					var tw2: float = UI.chip(self, font, Vector2(x, yy + 1), row[0], row[3], 10) + 6
					var nm_w: float = minf(font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, width * 0.4)
					UI.text_fit(self, font, Vector2(x + tw2, yy + 14), row[1], 12, UI.TEXT, nm_w + 2, 10)
					UI.text_fit(self, font, Vector2(x + tw2 + nm_w + 12, yy + 14), row[2], 11, Color(0.78, 0.88, 0.9), width - tw2 - nm_w - 12, 10)
					yy += rh
				return
			for row in page:
				# 技能行左边画技能图标（32px 原尺寸），标题与说明整体右移
				var itx: Texture2D = A.tex(row[4]) if row.size() > 4 and row[4] != "" else null
				var ix: float = SKILL_ICON_W if itx != null else 0.0
				if itx != null:
					draw_texture_rect(itx, Rect2(Vector2(x, yy + 1), Vector2(32, 32)), false)
				var tag_w: float = UI.chip(self, font, Vector2(x + ix, yy + 2), row[0], row[3], 11) + 8
				UI.text_fit(self, font, Vector2(x + ix + tag_w, yy + fs + 1), row[1], fs + 1, UI.TEXT, width - ix - tag_w, 10)
				var y0 := yy
				yy += fs + 8
				var fd := UI.fit(font, row[2], width - ix - 8, 9999.0 if fits else per_desc, [fs - 1])
				UI.draw_fit(self, font, Vector2(x + ix + 8, yy + fs - 2 - font.get_ascent(fs - 1)), fd, Color(0.78, 0.88, 0.9))
				yy = maxf(yy + float(fd.h) + 7, y0 + (40.0 if itx != null else 0.0))
		2:
			# 数值页：两列表格
			# 行距按剩余高度收缩（演示时下方空间小）；脚注紧跟表格，放不下就不画
			var col_w := width / 2.0
			var nrow: int = (page.size() + 1) / 2
			var step: float = clampf((avail - 26.0) / maxf(nrow, 1), 20.0, 30.0)
			var fs2: int = 15 if step >= 26.0 else 13
			var yy2 := top + 14
			for i in page.size():
				var cxx: float = x + (i % 2) * col_w
				if i % 2 == 0 and i > 0:
					yy2 += step
				UI.text(self, font, Vector2(cxx, yy2), page[i][0], fs2 - 2, UI.SUB)
				UI.text(self, font, Vector2(cxx + 92, yy2), page[i][1], fs2, UI.TEXT)
			if yy2 + 24 <= top + avail:
				UI.text(self, font, Vector2(x, yy2 + 24), "数值为基础值（未计成长节点、藏品与全队加成）；每秒伤害 = 单次伤害 × 每次出手的段数 ÷ 攻击间隔。", 11, UI.SUB)


const SKILL_ICON_W := 40.0   # 技能页：图标 32px + 间距


func _skill_rows_h(rows: Array, width: float, fs: int) -> float:
	var h := 0.0
	for row in rows:
		var has_icon: bool = row.size() > 4 and row[4] != "" and A.tex(row[4]) != null
		var ix: float = SKILL_ICON_W if has_icon else 0.0
		var rh: float = fs + 8 + font.get_multiline_string_size(UI.soft(row[2]), HORIZONTAL_ALIGNMENT_LEFT, width - ix - 8, fs - 1, -1, UI.BRK).y + 7
		h += maxf(rh, 40.0 if has_icon else 0.0)
	return h


func _draw_fit_text(txt: String, at: Vector2, width: float, avail: float) -> void:
	UI.draw_fit(self, font, at + Vector2(0, 15 - font.get_ascent(15)), UI.fit(font, txt, width, avail, [15, 14, 13, 12, 11]), Color(0.82, 0.9, 0.92))


## 档案页：lore.json 的 profile（代号 / 性别 / 出身 / 种族 / 所属，来自 PRTS 档案）+ 介绍；再接玩法定位一句
func _op_profile(cid: String, cd: Dictionary) -> String:
	var lr: Dictionary = lore.get(cid, {})
	var out: Array = []
	var pf: Dictionary = lr.get("profile", {})
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
	return "\n\n".join(out)


## 技能页：普攻 / S1–S3 / 天赋，每条 [标签, 名称, 说明, 颜色]
func _op_skill_rows(cd: Dictionary) -> Array:
	var rows: Array = []
	var col := Color(0.4, 0.85, 0.9)
	if cd.has("attack"):
		rows.append(["普攻", cd.attack.get("name", ""), cd.attack.get("desc", ""), col])
	var sks: Array = cd.get("skills", [])
	for si in sks.size():
		var sk: Dictionary = sks[si]
		var meta: Array = [["招募", "精英一", "精英二"][si] + "解锁"]
		if sk.has("sp"):
			meta.append("充能 %d 秒" % int(sk.sp))
		if sk.get("permanent", false):
			meta.append("永久")
		if sk.get("mode", "auto") == "manual":
			meta.append("手动")
		rows.append(["S%d" % (si + 1), "%s　（%s）" % [sk.get("name", ""), " · ".join(meta)], sk.get("desc", ""), UI.GOLD, sk.get("icon", "")])
	if cd.has("talent"):
		rows.append(["天赋", cd.talent.get("name", "") + "　（精英一解锁）", cd.talent.get("desc", ""), UI.PURPLE])
	return rows


## 数值页：从 base 段取各干员的基础数值（键名因人而异，这里统一成 攻击 / 间隔 / DPS / 距离 / 范围 / 治疗）
func _op_numbers(cid: String, cd: Dictionary) -> Array:
	var b: Dictionary = cd.get("base", {})
	var pick := func(keys: Array):
		for k in keys:
			if b.has(k):
				return float(b[k])
		return -1.0
	var atk: float = pick.call(["atk", "m_atk", "umbrella_dmg", "bolt_atk"])
	var cdv: float = pick.call(["cd", "m_cd", "swing_interval", "bolt_cd"])
	var rng_v: float = pick.call(["range", "bolt_range"])
	var reach: float = pick.call(["reach", "m_reach", "swing_radius", "len"])
	var aoe: float = pick.call(["aoe"])
	var out: Array = []
	out.append(["职业", "%s · %s" % [cd.get("class", ""), "远程" if rng_v > 0.0 else "近战"]])
	var tier: String = str(Bal.op(cid).get("tier", "—"))
	out.append(["档位", tier])
	# 当主控时的受击属性（JSON leader 段，按原作精二满级换算）
	var ld: Dictionary = cd.get("leader", {})
	if not ld.is_empty():
		out.append(["生命", "%d" % int(ld.get("max_hp", 120))])
		out.append(["物理减伤", "%s" % str(snappedf(float(ld.get("armor", 0.0)), 0.5))])
		out.append(["法术抗性", "%d%%" % int(round(float(ld.get("arts_res", 0.0)) * 100.0))])
		out.append(["生命回复", "%.1f / 秒" % float(ld.get("regen", 1.0))])
	if atk > 0.0:
		out.append(["攻击", "%d%s" % [int(atk), "（Mon3tr）" if b.has("m_atk") else ""]])
	if cdv > 0.0:
		out.append(["攻击间隔", "%.2f 秒" % cdv])
	if atk > 0.0 and cdv > 0.0:
		# 一次出手打几下：艾丽妮剑豪每次出手刺两下（帧条带 second 帧 = 第二刺），其余一下
		var hits: int = 2 if cd.get("sprites", {}).has("second") else 1
		out.append(["每秒伤害", "%.1f%s" % [atk * hits / cdv, "（每次两刺）" if hits == 2 else ""]])
	if rng_v > 0.0:
		out.append(["射程", "%d" % int(rng_v)])
	elif reach > 0.0:
		out.append(["攻击范围", "%d" % int(reach)])
	if aoe > 0.0:
		out.append(["爆炸 / 溅射", "半径 %d" % int(aoe)])
	if b.has("heal_pct"):
		out.append(["治疗", "%.1f%% / %.1f 秒" % [float(b.heal_pct) * 100.0, float(b.get("heal_cd", 3.0))]])
	var sks: Array = cd.get("skills", [])
	var sp: Array = []
	for sk in sks:
		sp.append(str(int(sk.get("sp", 0))))
	out.append(["技能充能", " / ".join(sp) + " 秒"])
	return out
