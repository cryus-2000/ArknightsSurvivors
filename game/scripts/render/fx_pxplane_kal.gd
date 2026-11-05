## 凯尔希 + Mon3tr 转平面（docs/265，fx/px_plane = 1）：fx_pxplane 的一节，单独成文件（同歌蕾蒂娅 fx_pxplane_gl.gd）。
## 帧条 tools/pxplane_kal_art.py 程序生成（art/fx/pxp/pxp_ka_<键>.png + data/pxp_kaltsit.json，键前缀 ka_）；送审 GIF tools/pxplane_gif_kaltsit.py 用同一批帧条。
## 色：Mon3tr 攻击 = 黑 / 墨绿 / 荧光绿；治疗 = 骨白 + 薄荷（不用红，和攻击分开）。只画，不碰玩法与玩法随机数（颗粒走 g.vrng）。
## 招牌：普攻爪击 = 三道平行爪痕（精一 + 地上犁痕，精二 + 命中处黑晶刺）；治疗 = 缝合环（精一 + 头顶骨白十字，精二 + 下针光柱）；
##       扑击 = 交叉爪 + 四道地爪印；回防 / 护主 = 一圈黑骨刺破土；S1 = 骨肋合拢（精一 + 六角板，精二 + 头顶结扣）；
##       S3 期间 Mon3tr 本体保持原色，叠熔毁红粒子轮廓 + 外沿局部染红（ob_summon.mf_draw 调 rim）+ 火星从轮廓上往上飘；与甲缝 / 爪痕 / 爆炸同一套红色阶；
##       S2 = 荧光指令符上升（精二 + 热流）；S3（红，用户 11-05 指定，和 Mon3tr 本体染红统一）= 本体甲缝裂开泛红光 + 脚下红色冲击 → 熔毁爪（实心重月牙 + 熔滴）+ 身边热流 → 结束红色实心大爆团；
##       不毁重构 = 小红爆 + 回响环 → 碎片飞回本体、本体甲棱（取自 Mon3tr 贴图）从躯干往外一段段亮起、外轮廓合拢一闪（+ 一盏照地光）；余焰 = 淡边；连携「Mon3tr 掩护」= 朝敌一侧半圈骨刺墙 + 推波。
## 旧做法对照（fx/px_plane = 2）凯尔希不接管（fx_pxplane.owns_id 返回 false），画面 = 当前游戏。
extends RefCounted

const MI = preload("res://scripts/render/melee_impact.gd")

const ID := "kaltsit"
const CLAW_R := [109, 128, 161, 200]          # 爪痕帧条分档（判定外沿 = reach + pad，世界像素）
const ECHO_R := [70, 87, 105, 130, 162, 195]
const LINK_D := [-90, -45, 0, 45, 90]


static var _dye := {}
const MELT_RED := Color8(204, 54, 26)     # 熔毁红色阶主红（RD m2）：精二身侧红弧等程序画的件用
const MELT_HOT := Color8(255, 108, 46)    # 亮橙红（RD f）
const MELT_DK := Color8(92, 16, 13)       # 暗血红（RD d2）
const MELT_FLOOR := Color8(148, 28, 18)   # 熔毁期间脚下常驻照地光（暗红）
const GR_HOT := Color8(170, 242, 62)      # 荧光绿
const GR_DK := Color8(30, 62, 34)         # 墨绿
const HEAL_HOT := Color8(238, 246, 228)   # 骨白
const HEAL_DK := Color8(70, 168, 124)     # 薄荷
const DUST_HOT := Color8(132, 138, 120)   # 扬尘
const DUST_DK := Color8(58, 64, 56)


## 有色 Noita 颗粒（fx_recipe 颗粒池，自带颜色；数量封顶，只在转平面版）：粒子算在该招主元素里，不另算一种（协调人 11-05）
static func _pp(r, o, at: Vector2, gy: float, mat: String, n: int, c0: Color, c1: Color, dir := Vector2.ZERO) -> void:
	if r.mode() != 1 or n <= 0:
		return
	var R = load("res://scripts/render/fx_recipe.gd").of(r.g)
	R._grains(o, at, gy, mat, mini(n, 10), {"tier": r.tier(o), "c0": c0, "c1": c1}, dir)


static func _hp(e: Dictionary) -> Vector2:
	return e.pos + Vector2(0, -float(e.r) * 0.5)


## S3 熔毁期间 Mon3tr 的红轮廓叠层（用户 11-05「m3 的染红可以是那种粒子特效带来的轮廓和部分染色」）：
## tools/pxplane_kal_art.py rim_m3 按实装 native 帧条逐帧烘（外轮廓一圈熔毁红 + 外沿甲片局部染红 + 轮廓外零星火星），A / B 两版按 15 fps 节拍交替。
## 和本体同一帧、同一套画法参数叠画（ob_summon.mf_draw）；没有对应叠层（旧帧条）返回 null
static func rim(tx: Texture2D, beat: int) -> Texture2D:
	if tx == null or tx.resource_path == "":
		return null
	var key: String = tx.resource_path + str(beat & 1)
	if not _dye.has(key):
		var b: String = tx.resource_path.get_file().get_basename()   # op_mon3tr_native_idle@2x
		var p: String = "res://art/fx/pxp/pxp_ka_rim%s_%s.png" % ["ab"[beat & 1], b.replace("@", "_")]
		_dye[key] = load(p) if ResourceLoader.exists(p) else null
	return _dye[key]


static func _m3(o):
	var sm = o.get("sm")
	if sm is Dictionary and sm.has("list"):
		for x in sm.list:
			if str(x.kind) == "mon3tr" and not x.get("gone", false):
				return x
	return null


static func _bucket(arr: Array, r: float) -> int:
	var best: int = int(arr[0])
	for v in arr:
		if float(v) <= r * 1.1:
			best = int(v)
	return best


## 一件：k 不带前缀；ly up / gd；fol = "m3" / "lead" / "" 跟谁走（存续期间按对方当前位置 + 偏移，每拍跳格）
static func _put(r, o, k: String, at: Vector2, ly: String, fol := "", flip := false, sk := 0.0, delay := 0.0) -> Dictionary:
	var it := {"k": "ka_" + k, "t0": r.g.t + delay, "gp": r._snap(at), "flip": flip, "ly": ly, "oid": ID}
	if sk != 0.0:
		it["sk"] = sk
	if fol == "m3":
		var s = _m3(o)
		if s != null:
			it["kfm"] = at - (s.pos as Vector2)
	elif fol == "lead":
		it["kfl"] = at - r.g.ppos
	r._push(it)
	return it


# ================================================================ 事件

static func ev(r, o, kind: String, d: Dictionary, t: int, R, p: Dictionary) -> void:
	var g = r.g
	match kind:
		"kal_claw":   # Mon3tr 爪击（ob_summon._mf_claw，每个方向一次；second = 骨爪增生第二爪）
			var s = d.get("s", null)
			if s == null:
				return
			var at: Vector2 = s.pos
			var ang: float = float(d.get("ang", 0.0))
			var flip: bool = cos(ang) < 0.0
			var Rb: int = _bucket(CLAW_R, float(d.get("reach", 109.0)))
			var sw: int = 0 if float(s.get("swing", 1.0)) >= 0.0 else 1
			if d.get("second", false):
				sw = 1 - sw
			var es: Array = d.get("es", [])
			if o.skill_active_left(2) > 0.0:   # S3 熔毁期间：墨绿实心重月牙 + 熔滴
				_put(r, o, "mclaw_r%d_s%d_up" % [Rb, sw], at, "up", "m3", flip)
				_put(r, o, "mclaw_r%d_s%d_gd" % [Rb, sw], at, "gd", "m3", flip)
				_hit(r, o, R, p, es, "", 0, 110.0, 0.5, p.get("melt", p.light))
				if not es.is_empty():   # 熔滴火星：红，几颗，快飞快落
					_pp(r, o, _hp(es[0]), float(es[0].pos.y) + 2.0, "ember", 3, MELT_HOT, MELT_DK, (_hp(es[0]) - at).normalized())
				return
			_put(r, o, "claw_r%d_s%d_up" % [Rb, sw], at, "up", "m3", flip)
			_put(r, o, "claw_r%d_s%d_%s" % [Rb, sw, "gd1" if t >= 1 else "gd"], at, "gd", "", flip)   # 犁痕落地不跟走
			if t >= 2 and not d.get("second", false):   # 精二：命中处黑晶刺（至多 3 只）
				var n := 0
				for e in es:
					if n >= 3 or e.get("dead", false):
						continue
					n += 1
					_put(r, o, "spike_up", e.pos, "up")
					_put(r, o, "spike_gd", e.pos, "gd")
			_hit(r, o, R, p, es, "", 0, 90.0, 0.35)
			if not es.is_empty():   # 命中甩出荧光火星 / 碎晶屑：几颗，飞得快、落得快（粒子算在爪痕主元素里）
				_pp(r, o, _hp(es[0]), float(es[0].pos.y) + 2.0, "ember", 2 + t, GR_HOT, GR_DK, (_hp(es[0]) - at).normalized())
		"kal_pounce":   # 精一扑击落地（ob_elite._el_land）
			var at2: Vector2 = d.get("at", o.pos)
			var fl: bool = float(d.get("face", 1.0)) < 0.0
			_put(r, o, "pounce_up", at2, "up", "", fl)
			_put(r, o, "pounce_gd", at2, "gd", "", fl)
			_hit(r, o, R, p, d.get("es", []), "", 0, 90.0, 0.4)
			R._light(o, at2 + Vector2(0, -8), 90.0, 0.35, 0.12, p.light)
			_pp(r, o, at2 + Vector2(0, -2), at2.y, "dust", 6, DUST_HOT, DUST_DK)
		"kal_heal":   # 治疗（data_operator._heal）：目标 = 队长或 Mon3tr；技能治疗（S1）只出地环
			var tm3: bool = d.get("m3", false)
			var s2 = _m3(o) if tm3 else null
			var tp: Vector2 = s2.pos if s2 != null else g.ppos
			if tp == Vector2.INF:
				return
			var fo: String = "m3" if s2 != null else "lead"
			_put(r, o, "heal_gd", tp, "gd", fo)
			_pp(r, o, tp + Vector2(0, -4), tp.y, "rise", 3 if d.get("power", false) else 4, HEAL_HOT, HEAL_DK)
			if d.get("power", false):
				R._light(o, tp + Vector2(0, -20), 90.0, 0.35, 0.15, p.get("heal", p.light))
				return
			if t >= 1:
				_put(r, o, "heal_cross_up", tp, "up", fo, false, 1.0)
			if t >= 2:
				_put(r, o, "heal_col_up", tp, "up", fo, false, -2.0)
			R._light(o, tp + Vector2(0, -20), 70.0, 0.3, 0.12, p.get("heal", p.light))
		"skill":
			var i: int = int(d.get("i", -1))
			var s3 = _m3(o)
			if i == 0 and s3 != null and "melt_triple" in o.taken:   # S1 分支「不毁重构」：三连爆之后 Mon3tr 身上碎片回收 + 骨架一段段亮起合拢（用户 11-05「太不明显」）
				var rb := _put(r, o, "rebuild_up", s3.pos, "up", "m3", float(s3.face) < 0.0, 2.0, 7.0 / 15.0)   # 骨架取自本体贴图，叠在本体上、随朝向翻转
				rb["klit"] = true
				_put(r, o, "rebuild_gd", s3.pos, "gd", "m3", false, 0.0, 7.0 / 15.0)
			if i == 0 and g.ppos != Vector2.INF:   # S1 结构加固：队长身边骨肋合拢
				_put(r, o, "s1rib_bk_up", g.ppos, "up", "lead", false, -3.0)
				_put(r, o, "s1rib_fr2_up" if t >= 2 else "s1rib_fr_up", g.ppos, "up", "lead", false, 1.0)
				if t >= 1:
					_put(r, o, "s1hex_gd", g.ppos, "gd", "lead")
				R._light(o, g.ppos + Vector2(0, -30), 120.0, 0.45, 0.15, p.get("heal", p.light))
			elif i == 1 and s3 != null:   # S2 战术协同：Mon3tr 身上指令符
				_put(r, o, "s2hex_gd", s3.pos, "gd", "m3")
				_put(r, o, "s2cmd_up", s3.pos, "up", "m3", false, 1.0)
				if t >= 2:
					_put(r, o, "s2str_up", s3.pos, "up", "m3", false, 1.0)
				R._light(o, s3.pos + Vector2(0, -30), 100.0, 0.45, 0.15, p.light)
			elif i == 2 and s3 != null:   # S3 熔毁起手（用户 11-05）：本体甲缝从躯干往外裂开泛红光 + 热流上蒸 + 脚下贴地红色冲击
				_put(r, o, "s3cast_up", s3.pos, "up", "m3", float(s3.face) < 0.0, 2.0)
				_put(r, o, "s3cast_gd", s3.pos, "gd", "m3")
				R._light(o, s3.pos + Vector2(0, -40), 130.0, 0.6, 0.15, p.get("melt", p.light))
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c: Vector2 = d.get("c", o.pos)
			var rr: float = float(d.get("r", 70.0))
			var es2: Array = d.get("es", [])
			if src.ends_with("回防"):   # 精二回防 / 技能响应护主：一圈黑骨刺破土
				_put(r, o, "guard_gd", c, "gd")
				_put(r, o, "guard_bk_up", c, "up", "", false, -3.0)
				_put(r, o, "guard_fr_up", c, "up")
				_hit(r, o, R, p, es2, "", 0, 140.0, 0.55)
				R._light(o, c + Vector2(0, -10), 160.0, 0.5, 0.15, p.light)
				_pp(r, o, c + Vector2(0, -2), c.y, "dust", 8, DUST_HOT, DUST_DK)
			elif src.ends_with("熔毁"):
				if "dot" in d.get("tags", []):   # 不毁重构·余焰：每跳一圈淡边 + 少量余烬
					_put(r, o, "smol_r%d_gd" % (130 if rr >= 117.0 else 105), c, "gd")
					if not es2.is_empty():
						_pp(r, o, _hp(es2[0]), float(es2[0].pos.y), "rise", 1, MELT_HOT, MELT_DK)
					return
				var last: float = float(o.get_meta("ka_melt_t", -9.0))
				if g.t - last < 0.6:   # 三连爆的第 2 / 3 下：回响环 + 碎晶
					_put(r, o, "echo_r%d_gd" % _bucket(ECHO_R, rr), c, "gd")
					_put(r, o, "echo_up", c, "up", "", false, 3.0)
					_hit(r, o, R, p, es2, "", 0, 150.0, 0.5, p.get("melt", p.light))
					_pp(r, o, c + Vector2(0, -16), c.y, "ember", 4, MELT_HOT, MELT_DK)
				else:   # 熔毁爆（S3 结束，大）/ 不毁重构 · 倒地重构（小）：一枚墨绿结晶炸开
					o.set_meta("ka_melt_t", g.t)
					var big: bool = rr >= 115.0
					_put(r, o, "melt_r%d_up" % (130 if big else 70), c, "up", "", false, 3.0)
					_put(r, o, "melt_r%d_gd" % (130 if big else 70), c, "gd")
					R._light(o, c + Vector2(0, -20), 240.0 if big else 160.0, 1.0 if big else 0.65, 0.15, p.get("melt", p.light))
					_pp(r, o, c + Vector2(0, -30), c.y, "ember", 10 if big else 6, MELT_HOT, MELT_DK)   # 火星迸出、落地熄灭
					_pp(r, o, c + Vector2(0, -20), c.y, "rise", 4 if big else 2, MELT_HOT, MELT_DK)
		"kal_link":   # 连携「Mon3tr 掩护」（skill_link l_kaltsit）：朝敌一侧半圈骨刺墙 + 推波；队长身上治疗
			var at3: Vector2 = d.get("at", o.pos)
			var sd: Vector2 = d.get("side", Vector2.RIGHT)
			var dk: Array = r.pick_dir(sd.angle())
			_put(r, o, "link_up_d%d" % dk[0], at3, "up", "", dk[1], -3.0 if int(dk[0]) < 0 else 1.0)
			_put(r, o, "link_gd_d%d" % dk[0], at3, "gd", "", dk[1])
			if g.ppos != Vector2.INF:
				_put(r, o, "heal_gd", g.ppos, "gd", "lead")
				_put(r, o, "heal_cross_up", g.ppos, "up", "lead", false, 1.0)
			R._light(o, at3 + Vector2(0, -16), 150.0, 0.55, 0.15, p.light)
			_pp(r, o, at3 + sd * 30.0 + Vector2(0, -4), at3.y + sd.y * 30.0, "dust", 7, DUST_HOT, DUST_DK, sd)
		"kal_debride":   # 节点「清创」累积满：敌人脚下黑晶刺 + 回响环
			var e: Dictionary = d.get("e", {})
			if e.is_empty():
				return
			_put(r, o, "spike_up", e.pos, "up")
			_put(r, o, "echo_r70_gd", e.pos, "gd")
			_hit(r, o, R, p, [e], "", 0, 100.0, 0.4)
			_pp(r, o, _hp(e), float(e.pos.y), "ember", 3, GR_HOT, GR_DK)


## 命中：少量 Noita 颗粒（fx_recipe 颗粒池）+ 一盏照地短光；只在转平面版
static func _hit(r, o, R, p: Dictionary, es: Array, mat: String, n: int, lr: float, li: float, lc = null) -> void:
	if r.mode() != 1 or es.is_empty():
		return
	var e: Dictionary = es[0]
	var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
	if n > 0:
		R._grains(o, hp, float(e.pos.y) + 2.0, mat, mini(n, 1 + es.size()), {"tier": r.tier(o)}, (hp - o.pos).normalized())
	R._light(o, hp, lr, li * MI.lit_k(r.g), 0.12, p.light if lc == null else lc)


# ================================================================ 绘制

## 跟人 / 跟 Mon3tr 的件：每拍（15 fps）按对方当前位置跳一格
static func _follow(r, o) -> void:
	var tk: int = int(floor(r.g.t * 15.0))
	if int(o.get_meta("ka_fol_tk", -1)) == tk:
		return
	o.set_meta("ka_fol_tk", tk)
	var s = _m3(o)
	for it in r.items:
		if str(it.oid) != ID:
			continue
		if it.has("kfm") and s != null:
			it.gp = r._snap((s.pos as Vector2) + (it.kfm as Vector2))
		elif it.has("kfl") and r.g.ppos != Vector2.INF:
			it.gp = r._snap(r.g.ppos + (it.kfl as Vector2))


## 地面层（fx_pxplane.draw_floor 转来）
static func floor_layer(r, o) -> void:
	_follow(r, o)
	var cv = o.cv
	var s = _m3(o)
	if s != null and o.skill_active_left(2) > 0.0:   # 熔毁期间 Mon3tr 脚下一圈淡环（循环，跟着走）
		r._draw_strip(cv, "ka_s3aura_gd", r.frame_of(0.0), r._snap(s.pos), false, false)
		var bt: int = int(floor(r.g.t * 15.0))
		if int(o.get_meta("ka_s3_bt", -1)) != bt:
			o.set_meta("ka_s3_bt", bt)
			var R = load("res://scripts/render/fx_recipe.gd").of(r.g)
			if bt % 2 == 0:   # 脚下常驻一圈暗红照地光（灯寿命 0.15 秒，每两拍续一盏，走光照预算）
				R._light(o, (s.pos as Vector2) + Vector2(0, -6), 110.0, 0.35, 0.15, MELT_FLOOR)
			if bt % 2 == 1 and r.mode() == 1:   # 火星从本体轮廓往上飘
				var ep: Vector2 = (s.pos as Vector2) + Vector2(r.g.vrng.randf_range(-36.0, 36.0), -r.g.vrng.randf_range(30.0, 96.0))
				_pp(r, o, ep, float(s.pos.y), "rise", 1, MELT_HOT, MELT_DK)
	for it in r.items:
		if it.get("klit", false) and r.frame_of(float(it.t0)) >= 11:   # 不毁重构合拢那一拍：一盏照地光
			it["klit"] = false
			var R = load("res://scripts/render/fx_recipe.gd").of(r.g)
			R._light(o, (it.gp as Vector2) + Vector2(0, -22), 150.0, 0.7, 0.15, R.pal(o).get("melt", Color(1.0, 0.42, 0.18)))
		if str(it.ly) == "gd" and str(it.oid) == ID:
			r._draw_strip(cv, str(it.k), r.frame_of(float(it.t0)), it.gp, it.flip, true)


## 排序项：熔毁期间 Mon3tr 身边的竖直热流（循环，跟着走；排在 Mon3tr 前面一点）
static func sort_items(r, o, out: Array) -> void:
	var s = _m3(o)
	if s != null and o.skill_active_left(2) > 0.0:
		out.append({"loopk": "ka_s3aura_up", "gp": r._snap(s.pos), "skey": float(s.pos.y) + 2.0})
