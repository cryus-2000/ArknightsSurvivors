extends RefCounted
## 世界绘制（2.5D）：地图之上按纵深排序画敌人 / 主控 / 编队 / 博士挂件 / 特效，缩圈与护盾；主控与博士的动画状态、手感（压缩 / 拉伸 / 扬尘）。
## game.gd 的 _draw 只转发到这里。地图本身在 world/map.gd，HUD 在 screens/hud.gd。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var p_turn := 0.0                # 转身瞬间
var p_was_moving := false
var p_last_facing := 1.0
var p_dust_t := 0.0
var p_swing_prev := 0.0
var p_hurt_prev := 0.0
var cam_kick := Vector2.ZERO
var heart_cd := 0.0
var anim_name := ""
var anim_t := 0.0
## 后期画面降噪（EA 1.1，docs/37 §7）：场上特效粒子一多，友方特效整体降透明度、加色发光层变淡、辉光减弱，
## 让敌人、敌方弹幕、Boss 预警和掉落物浮出来。crowd 0–1 按「世界特效 + 干员粒子」总数平滑算出
var crowd := 0.0
var fx_dim := 1.0                 # 友方特效的透明度系数（1 → 0.45）
var boss_seen: Array = []        # Boss 换幕 / 倒下演出的观察表：[boss, 上次的 phase, 已演过倒下]（字典作键会因内容变化失效，按 is_same 找）
var scr_flash := 0.0              # 全屏闪光剩余秒（hud 画）：换幕洋红、Boss 倒下白
var scr_flash_max := 1.0
var scr_flash_col := Color.WHITE
var ecrowd := 0.0                 # 敌人密度 0–1（活着的敌人 90 → 210）：普通怪描边随之变淡
const CROWD_FROM := 80.0          # 特效总数超过这个开始降
const CROWD_SPAN := 220.0         # 再多这么多降到底
## 会被降透明度的友方特效种类（敌方的 rift / bbeam / horde_ring、治疗十字、地面血迹不降）
const DIM_KINDS := ["explode", "burst", "rays", "ring", "impact", "bslash", "slash", "spark", "shard", "wpillar", "pillar", "beam", "tracer", "quake", "sprite", "frost", "tide_link", "frost_track"]
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane", "tide": "proj_tide"}
## 水月 48px 动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。脚底锚点 (24,46)。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _init(game: Game) -> void:
	g = game


func update_visuals(dt: float) -> void:
	g._update_doc_follow(dt)
	# 不再叠代码起伏：博士跑步帧条自带步频；旧 2 帧待机条兜底时由 update_doctor_anim 按 anim_t 自己颠
	# （原来按主控的 walk_t 起伏：步频对不上帧条，主控停下后博士还在追时 walk_t 不走，会卡在半空）
	g.sprite.position = (g.doc_pos + Vector2(0, 6)).round()
	g.sprite.flip_h = g.doc_face < 0.0
	update_player_anim(g.get_process_delta_time() if g.state in [Game.S.DEAD, Game.S.WIN] else dt)
	update_player_feel(g.get_process_delta_time())
	if g.state == Game.S.DEAD:
		g.sprite.modulate = Color(0.5, 0.5, 0.6, 0.6)
	elif g.hurt_flash > 0.12:
		g.sprite.modulate = Color(3.0, 3.0, 3.0)
	elif g.hurt_flash > 0.0:
		g.sprite.modulate = Color(1.0, 0.4, 0.4)
	elif g.invuln > 0.0 and int(g.invuln * 20.0) % 2 == 0:
		g.sprite.modulate = Color(1, 1, 1, 0.6)
	else:
		g.sprite.modulate = Color.WHITE
	g.cam.position = g.view_center().round()
	var rd := g.get_process_delta_time()
	g.shake = move_toward(g.shake, 0.0, rd * 2.5)
	cam_kick = cam_kick.move_toward(Vector2.ZERO, rd * 60.0)
	g.hurt_vignette = move_toward(g.hurt_vignette, 0.0, rd * 1.5)
	g.red_flash = move_toward(g.red_flash, 0.0, rd * 2.0)
	g.hp_shake = move_toward(g.hp_shake, 0.0, rd)
	g.head_bar_t = move_toward(g.head_bar_t, 0.0, rd)
	g.hp_trail = move_toward(g.hp_trail, g.hp, rd * g.max_hp * (0.15 if g.hp_shake > 0.0 else 0.6))
	if g.hp_trail < g.hp:
		g.hp_trail = g.hp
	# 低血量心跳
	if g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0:
		heart_cd -= rd
		if heart_cd <= 0.0:
			heart_cd = 0.55 + 0.6 * g.hp / (g.max_hp * 0.3)
			Sfx.play("heartbeat", -2.0, 1.0, 0.0)
	# 镜头震动已整体移除（见 _shake）。干员脚本里还有直接写 g.shake 的（2.5–5，按 10·shake² 就是 ±250 像素），
	# 在这里统一不用它，图鉴演示 / 精英化演出 / 实战都不再震；shake 变量只留给以后可能的非镜头用途
	g.cam.offset = cam_kick.round()
	# 灯火光源：半径随灯火变化，快熄灭时闪烁
	var radius: float = lerp(150.0, 520.0, g.lamp / 100.0) * g.squad.light_radius_mult()
	if g.state == Game.S.DEAD:
		radius *= 1.0 - clampf(g.state_age / Game.HudView.DEATH_LAMP_T, 0.0, 1.0)   # 倒下过渡：灯火熄灭（hud.draw_death_transition）
	var flicker := 1.0 + sin(g.t * 13.0) * 0.02 + sin(g.t * 7.3) * 0.03
	if g.lamp < 30.0:
		flicker += sin(g.t * 23.0) * 0.06
	g.lamp_light.position = g.ppos + Vector2(0, -20)
	g.lamp_light.texture_scale = radius / 64.0 * flicker
	g.lamp_light.color = Color(1.0, 0.86, 0.62) if g.lamp >= 30.0 else Color(1.0, 0.6, 0.5)
	# 海中浮游颗粒
	g.map.update_snow(dt, g.get_viewport_rect().size)
	_enemy_act_fx()
	# 特效密度 → 友方特效降噪（图鉴演示不降，演示本来就是看特效的）
	var nfx: int = g.fx.size()
	for o in g.squad.ops:
		nfx += o.pfx.size()
	var want: float = 0.0 if g.demo_op != "" else clampf((nfx - CROWD_FROM) / CROWD_SPAN, 0.0, 1.0)
	crowd = move_toward(crowd, want, rd * (3.0 if want > crowd else 0.8))
	fx_dim = lerpf(1.0, 0.45, crowd)
	var ne := 0
	for e in g.enemies:
		if not e.dead:
			ne += 1
	var ewant: float = 0.0 if g.demo_op != "" else clampf((ne - 90.0) / 120.0, 0.0, 1.0)
	ecrowd = move_toward(ecrowd, ewant, rd * 0.8)
	g.fx_add.modulate.a = lerpf(1.0, 0.6, crowd)
	if g.post != null and "crowd" in g.post:
		g.post.crowd = crowd


## Boss 换幕 / 倒下演出（docs/48 P1：换幕只有横幅，死亡特效和精英同一套、比本体还小）。
## 只在画面里观察 g.bosses 的 phase / dead 变化来放特效，不改战斗逻辑；平衡模式不绘制，不影响对局随机数（特效只用 vrng）
func watch_bosses() -> void:
	boss_seen = boss_seen.filter(func(s): return g.bosses.any(func(b): return is_same(b, s[0])))
	for b in g.bosses:
		var s: Array = []
		for s2 in boss_seen:
			if is_same(s2[0], b):
				s = s2
				break
		if s.is_empty():
			boss_seen.append([b, b.get("phase", 1), b.dead])
			# 一帧内击倒 / 首次绘制已经死亡也补播，不依赖先看见活体。
			if b.dead and not b.get("retreated", false):
				boss_down_fx(b)
			continue
		if b.get("phase", 1) != s[1] and not b.dead:
			s[1] = b.get("phase", 1)
			boss_phase_fx(b)
		var bk: bool = b.type == "knight_boss" and b.get("break_t", 0.0) > 4.0
		if s.size() < 5:
			s.resize(5)
			s[3] = b.get("sword_t", 0.0) > 0.0
			s[4] = bk
		elif bk and not s[4]:
			spear_fly_fx(b)
		s[4] = bk
		var sw: bool = b.get("sword_t", 0.0) > 0.0
		if s.size() < 4:
			s.append(sw)
		elif sw and not s[3]:
			sword_swap_fx(b)
		s[3] = sw
		if b.dead and not s[2]:
			s[2] = true
			if not b.get("retreated", false):
				boss_down_fx(b)


func _flash(col: Color, t: float) -> void:
	scr_flash = t
	scr_flash_max = t
	scr_flash_col = col


## 换幕：洋红冲击波两圈 + 放射光刺 + 全屏洋红一闪
func boss_phase_fx(b: Dictionary) -> void:
	g.fx.append({"kind": "boss_phase", "pos": b.pos, "r": b.r, "life": 0.9, "max": 0.9})
	g.vfx.sparks(b.pos, Vector2.ZERO, Color(1.4, 0.4, 1.1), 20, 300.0)
	_flash(Color(1.0, 0.3, 0.8), 0.35)


## Boss 倒下：白色核心爆闪 + 三道错开的冲击环（最大到本体 8 倍）+ 竖直光柱 + 大量碎光，全屏白闪
func boss_down_fx(b: Dictionary) -> void:
	g.fx.append({"kind": "boss_down", "pos": b.pos, "r": maxf(b.r, 24.0), "life": 1.6, "max": 1.6})
	g.vfx.sparks(b.pos, Vector2.ZERO, Color(1.6, 1.4, 1.8), 30, 420.0)
	g.vfx.sparks(b.pos, Vector2.UP, Color(1.4, 0.5, 1.2), 16, 360.0)
	_flash(Color(1.0, 0.97, 0.95), 0.4)


func draw_world() -> void:
	watch_bosses()
	scr_flash = maxf(0.0, scr_flash - g.get_process_delta_time())
	g.map.draw_ground(g.get_viewport_rect().size)
	for m in g.mires:
		g.map.draw_mire(m)
	g.bai._draw_warns()
	draw_nest_auras()
	draw_beacons()
	g.rfx.draw()
	if not g.merchant.is_empty():
		var mtx: Texture2D = g.tex.merchant
		var big_m: bool = mtx != null and mtx.get_height() >= 40
		g.vfx.spr("shadow", 1, 0, g.merchant.pos + Vector2(0, 18), Game.PX * (1.6 if big_m else 1.2))
		if big_m:
			g.vfx.spr("merchant", 2, int(g.t * 2.0) % 2, g.merchant.pos + Vector2(0, 18), Game.PX, g.ppos.x < g.merchant.pos.x, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
		else:
			g.vfx.spr("merchant", 2, int(g.t * 2.0) % 2, g.merchant.pos, Game.PX)
		# 「商人 %ds」标签由 HUD 层在头顶绘制（_draw_hud 商人方向指示），这里不再重复画一份
	# 性能（协调人 9/30：后期没捡的结晶堆积，每颗 5–8 个图元）：屏幕外的掉落不画；结晶很多时，
	# 远处安静的小结晶按 GEM_CELL 网格合并成一颗画（只合并画面，拾取仍是一颗一颗的）
	var vr: Rect2 = view_rect(40.0)
	var crowd_gems: bool = g.gems.size() > GEM_MERGE_N
	var cells := {}
	for g_item in g.gems:
		if not vr.has_point(g_item.pos):
			continue
		var gz: float = g_item.get("z", 0.0)
		if crowd_gems and g_item.kind == "xp" and not g_item.mag and gz <= 1.0 and g_item.val < 5.0 and g_item.pos.distance_to(g.ppos) > 170.0:
			var ck := Vector2i(floori(g_item.pos.x / GEM_CELL), floori(g_item.pos.y / GEM_CELL))
			cells[ck] = int(cells.get(ck, 0)) + 1
			continue
		if gz > 1.0:
			g.draw_set_transform(g_item.pos + Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
			g.draw_circle(Vector2.ZERO, 7.0 * (1.0 - clampf(gz / 80.0, 0.0, 0.6)), Color(0, 0, 0, 0.35))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if g_item.get("special", false):
			var ic := g.pickups.item_col(g_item.kind)
			var age: float = g_item.get("age", 0.0)
			# 掉落光柱（0.9 秒淡出）+ 常驻脉动光圈
			if age < 0.9:
				var ba := (1.0 - age / 0.9) * 0.55
				g.draw_rect(Rect2(g_item.pos + Vector2(-5, -140), Vector2(10, 140)), Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, ba * 0.5))
				g.draw_rect(Rect2(g_item.pos + Vector2(-2, -140), Vector2(4, 140)), Color(2.5, 2.5, 2.5, ba))
			if g_item.kind != "chest":
				var pr := 11.0 + 2.0 * sin(g.t * 5.0)
				g.draw_circle(g_item.pos + Vector2(0, -gz - 2), pr + 5.0, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.12))
				g.draw_arc(g_item.pos + Vector2(0, -gz - 2), pr, 0.0, TAU, 20, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.5), 1.5)
		g.draw_off = Vector2(0, -gz)
		match g_item.kind:
			"xp":
				# 经验结晶：放大 + 常驻辉光 + 闪烁；被吸时拖尾。后期满地结晶时（> 60 颗）离主控 170 以外的不画辉光和闪光，
				# 只留结晶本体 + 深色底，免得一地青光和敌人的青色描边搅在一起
				var big: bool = g_item.val >= 5.0
				var quiet: bool = g.gems.size() > 60 and not g_item.mag and g_item.pos.distance_to(g.ppos) > 170.0
				var gc: Color = Color(0.85, 0.6, 1.0) if big else UI.CYAN
				var tw: float = 0.75 + 0.25 * sin(g.t * 6.0 + g_item.get("seed", 0.0))
				var gp: Vector2 = g_item.pos + Vector2(0, (sin(g.t * 4.0 + g_item.pos.x) * 2.0 if gz <= 1.0 else 0.0) - gz)
				if g_item.mag:
					var dv: Vector2 = (gp - (g.ppos + Vector2(0, -12))).normalized()
					var tl: float = 10.0 + 24.0 * minf(1.0, g_item.get("mag_t", 0.0) * 2.0)
					g.draw_line(gp, gp + dv * tl, Color(gc.r * 1.8, gc.g * 1.8, gc.b * 1.8, 0.55), 5.0 if big else 3.0)
					g.draw_line(gp, gp + dv * tl * 0.6, Color(2.5, 2.5, 2.5, 0.7), 1.5)
				if not quiet:
					g.draw_circle(gp, (13.0 if big else 9.0) * tw, Color(gc.r * 1.6, gc.g * 1.6, gc.b * 1.6, 0.16))
					g.draw_circle(gp, (7.0 if big else 4.5) * tw, Color(gc.r * 2.0, gc.g * 2.0, gc.b * 2.0, 0.22))
				g.draw_off = Vector2.ZERO
				g.draw_circle(gp + Vector2(0, 1), 6.5 if big else 4.5, Color(0.0, 0.02, 0.05, 0.55))   # 深色底：压在特效和敌人上也分得出
				var gcol: Color = Color(1.25, 1.25, 1.3) if not big else Color(1.35, 1.2, 1.5)
				if quiet:
					gcol = Color(0.9, 0.95, 1.0, 0.7)   # 远处的结晶压暗一些，贴近主控或被吸时才亮
				g.vfx.spr("gem_big" if big else "gem_small", 1, 0, gp, Game.PX * (1.9 if big else 1.45), false, gcol)
				if not quiet:
					var sp2: float = 2.0 + 1.5 * tw
					g.draw_line(gp + Vector2(-sp2, -8), gp + Vector2(sp2, -8), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
					g.draw_line(gp + Vector2(0, -8 - sp2), gp + Vector2(0, -8 + sp2), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
			"oil":
				g.vfx.spr("oil", 1, 0, g_item.pos)
			"chest":
				g.vfx.spr("chest", 1, 0, g_item.pos)
			"ingot":
				g.vfx.spr("ingot", 1, 0, g_item.pos + Vector2(0, sin(g.t * 3.0 + g_item.pos.y) * 1.5 if gz <= 1.0 else 0.0))
			"magnet", "heal":
				g.vfx.spr("pickup_" + g_item.kind, 1, 0, g_item.pos + Vector2(0, -2 + (sin(g.t * 3.5) * 2.0 if gz <= 1.0 else 0.0)))
		g.draw_off = Vector2.ZERO
	for ck in cells:
		# 合并后的一堆：在格子中心画一颗，堆里 3 颗以上画成大结晶（紫），压暗同远处安静结晶
		var n: int = cells[ck]
		var cp: Vector2 = (Vector2(ck) + Vector2(0.5, 0.5)) * GEM_CELL
		g.vfx.spr("gem_big" if n >= 3 else "gem_small", 1, 0, cp, Game.PX * (1.9 if n >= 3 else 1.45), false, Color(0.9, 0.95, 1.0, 0.7))
	g.vfx.spr("shadow", 1, 0, g.doc_pos + Vector2(0, 6), Game.PX * 1.3)
	g.squad.draw_auras()
	var evr: Rect2 = view_rect(ENTITY_MARGIN)   # 屏幕外的敌人不画影子、不进排序（性能，协调人 9/30；绘制只改画面，不影响模拟）
	for e in g.enemies:
		if not evr.has_point(e.pos):
			continue
		var sc: float = Game.PX * e.r / 10.0
		var hop: float = minf(e.kb.length() * 0.03, 14.0)
		g.vfx.spr("shadow", 1, 0, e.pos + Vector2(0, e.r * 0.8), sc * (1.0 - hop / 40.0))
	g.squad.draw_shadows()
	if g.knight.alive:
		g.vfx.spr("shadow", 1, 0, g.knight.pos + Vector2(0, 18), Game.PX * 1.6)
	g.squad.draw_entities_floor()
	# ---- 2.5D 前后遮挡：按脚底 y 排序后依次绘制 ----
	var dl: Array = []
	for e in g.enemies:
		if evr.has_point(e.pos):
			dl.append([e.pos.y + e.r * 0.8, 0, e])
	dl.append([g.doc_pos.y + 6.0, 2, null])
	for o in g.squad.ops:
		if o.pos != Vector2.INF:
			dl.append([o.pos.y + 4.0, 5, o])
		for xb in o.extra_bodies():
			dl.append([xb.y, 6, [o, xb]])
	if g.knight.alive:
		dl.append([g.knight.pos.y + 18.0, 4, null])
	for pr in g.map.sort_props:
		dl.append([pr[1].y, 3, pr])
	dl.sort_custom(func(a, b): return a[0] < b[0])
	for it in dl:
		match it[1]:
			5:
				it[2].draw_body()
			6:
				it[2][0].draw_extra(it[2][1])
			4:
				g.knight.draw()
			0:
				draw_enemy(it[2])
			2:
				draw_player()
			3:
				g.map.draw_sort_prop(it[2])
	g.squad.draw_skill_over()
	draw_shield()
	for dr in g.drones:
		g.draw_set_transform(dr.pos + Vector2(0, 96), 0.0, Vector2(1.0, 0.4))
		g.draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_circle(dr.pos, 20.0, Color(0.5, 1.4, 0.8, 0.16))
		# Codex 美术 V5 的激光型机体（4 帧：0-1 悬浮，2-3 发射）染成医疗绿；治疗瞬间用发射帧
		var dfr := int(g.t * 6.0) % 2
		if dr.get("beam", 0.0) > 0.2:
			dfr = 2
		elif dr.get("beam", 0.0) > 0.0:
			dfr = 3
		if g.tex.get("drone_laser") != null:
			g.vfx.spr("drone_laser", 4, dfr, dr.pos, 1.0, dr.get("face", 1.0) < 0.0, Color(0.85, 1.25, 0.95))
		elif g.tex.get("drone") != null:
			g.vfx.spr("drone", 2, int(g.t * 20.0) % 2, dr.pos, Game.PX, false, Color(1.2, 1.7, 1.4))
		g.draw_circle(dr.pos + Vector2(0, 8), 3.0, Color(1.2, 2.6, 1.6, 0.6 + 0.3 * sin(g.t * 8.0)))
	var jf := int(g.t * 6.0) % 2
	for b in g.bullets:
		if b.life <= 0.0 or b.get("hidden", false):
			continue
		var n: Vector2 = b.vel.normalized()
		# 美术 V6：投射物帧条（朝右绘制，按速度方向旋转）；程序只画拖尾
		var ptex: String = PROJ_TEX.get(b.kind, "")
		if ptex != "" and g.tex.get(ptex) != null:
			var pspec: Array = Game.V6_FRAMES[ptex]
			var pfr: int = (int(g.t * pspec[1] + b.pos.x * 0.01) % int(pspec[0])) if pspec[1] > 0.0 else 0
			match b.kind:
				"arrow":
					g.draw_line(b.pos - n * 34.0, b.pos - n * 12.0, Color(1.6, 1.4, 1.0, 0.3), 2.0)
				"fire":
					g.draw_circle(b.pos, 14.0, Color(1.4, 0.6, 2.2, 0.2))
				"arcane":
					g.draw_line(b.pos - n * 20.0, b.pos, Color(1.4, 0.6, 2.2, 0.35), 4.0)
				"tide":
					g.draw_circle(b.pos, 11.0, Color(0.5, 1.2, 2.0, 0.2))
			g.vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), Game.PX)
			continue
		match b.kind:
			"arrow":
				g.draw_line(b.pos - n * 26.0, b.pos - n * 10.0, Color(1.6, 1.4, 1.0, 0.35), 2.0)
				g.draw_line(b.pos - n * 14.0, b.pos + n * 4.0, Color(2.2, 2.0, 1.6), 3.0)
			"fire":
				var fl := 1.0 + 0.2 * sin(g.t * 40.0 + b.pos.x)
				g.draw_circle(b.pos, 13.0 * fl, Color(2.0, 0.8, 0.2, 0.25))
				g.draw_circle(b.pos, 8.0 * fl, Color(2.4, 1.1, 0.3, 0.8))
				g.draw_circle(b.pos, 4.0, Color(2.8, 2.4, 1.4))
			"arcane":
				g.draw_line(b.pos - n * 18.0, b.pos, Color(1.4, 0.6, 2.2, 0.4), 4.0)
				g.draw_circle(b.pos, 8.0, Color(1.2, 0.5, 2.0, 0.35))
				UI.diamond(g, b.pos, 5.0, Color(1.8, 1.0, 2.6), Color(2.2, 1.6, 2.8))
			"tide":
				g.draw_circle(b.pos, 10.0, Color(0.5, 1.2, 2.0, 0.25))
				g.draw_circle(b.pos, 6.0, Color(0.7, 1.5, 2.2, 0.9))
				g.draw_circle(b.pos + Vector2(-2, -2), 2.0, Color(2.5, 2.5, 2.5))
			_:
				g.vfx.spr("orb", 1, 0, b.pos, Game.PX)
	for f in g.fx:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var fdim: float = 1.0 if f.get("enemy", false) else fx_dim   # 敌方特效不降噪（docs/48 ③）
		if fdim < 1.0 and DIM_KINDS.has(f.kind):
			a *= fdim
		match f.kind:
			"frost":
				# 寒冰领域：淡蓝地面 + 旋转冰纹（地面椭圆与判定一致，ground_y，docs/48 ①）
				var fa: float = minf(1.0, f.life / 0.6) * 0.9
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, ground_y()))
				g.draw_circle(Vector2.ZERO, f.r, Color(0.5, 0.8, 1.2, 0.14 * fa))
				g.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 48, Color(0.8, 1.2, 1.8, 0.6 * fa), 2.0)
				for q in 6:
					var qa: float = g.t * 0.6 + TAU * q / 6.0
					g.draw_line(Vector2.from_angle(qa) * f.r * 0.2, Vector2.from_angle(qa) * f.r * 0.95, Color(0.9, 1.3, 1.9, 0.25 * fa), 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"frost_track":
				# 骑士冰线：连续的碎裂冰脊与亮芯，和追击预警共用相同方向。
				var side: Vector2 = (f.b - f.a).orthogonal().normalized()
				var spine := PackedVector2Array()
				for q in 12:
					var u: float = float(q) / 11.0
					spine.append(f.a.lerp(f.b, u) + side * sin(u * 47.0) * 5.0)
				g.draw_polyline(spine, Color(0.06, 0.2, 0.32, 0.8 * a), 14.0)
				g.draw_polyline(spine, Color(0.55, 1.2, 1.65, 0.85 * a), 5.0)
				g.draw_polyline(spine, Color(2.0, 2.4, 2.6, 0.9 * a), 1.5)
				for q in 9:
					var u: float = (float(q) + 0.5) / 9.0
					var at: Vector2 = f.a.lerp(f.b, u)
					var reach: float = 10.0 + float(q % 3) * 4.0
					g.draw_line(at, at + side * reach * (1.0 if q % 2 == 0 else -1.0), Color(0.8, 1.4, 1.9, 0.8 * a), 2.0)
			"frost_step":
				# 骑士冲锋脚下的冰霜拖尾：扁平冰斑 + 两道冰晶
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.45))
				g.draw_circle(Vector2.ZERO, f.r, Color(0.6, 0.85, 1.3, 0.28 * a))
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				g.draw_line(f.pos + Vector2(-5, 1), f.pos + Vector2(5, -1), Color(1.2, 1.5, 2.0, 0.6 * a), 1.5)
			"ring":
				var rr: float = f.r * (1.15 - a * 0.3)
				g.draw_arc(f.pos, rr, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.9), 4.0)
				g.draw_arc(f.pos, rr - 6.0, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.35), 2.0)
			"spark":
				g.draw_rect(Rect2(f.pos.round(), Vector2(f.sz, f.sz)), Color(f.col.r, f.col.g, f.col.b, a))
			"shard":
				var sv: Vector2 = Vector2.from_angle(f.rot + g.t * 8.0) * 5.0
				g.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.5, f.pos + sv]), Color(1.2, 1.9, 2.4, a))
			"blood":
				# 流血：地面血迹
				for q in 5:
					var off := Vector2(sin(f.seed + q * 1.7), cos(f.seed * 1.3 + q)) * 7.0
					g.draw_set_transform(f.pos + off, 0.0, Vector2(1.0, 0.5))
					g.draw_circle(Vector2.ZERO, 3.0 + (q % 3), Color(0.5, 0.02, 0.05, 0.6 * a))
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"explode":
				# 爆炸：火光 + 冲击环
				var k := 1.0 - a
				var c: Color = f.col
				g.draw_circle(f.pos, f.r * (0.3 + 0.7 * k), Color(c.r * 2.2, c.g * 1.8, c.b * 1.2, 0.45 * a))
				g.draw_circle(f.pos, f.r * 0.45 * a, Color(2.8, 2.4, 1.6, a))
				g.draw_arc(f.pos, f.r * (0.5 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 2.4, c.g * 2.0, c.b * 1.4, a), 4.0)
			"cross":
				# 治疗：上升的绿色十字
				var age: float = f.max - f.life
				if age >= f.get("delay", 0.0):
					var p: Vector2 = f.pos + Vector2(0, -40.0 * (age - f.delay))
					if g.tex.get("fx_heal_cross") != null:
						g.vfx.spr_rot("fx_heal_cross", mini(3, int((age - f.delay) * 10.0)), p, 0.0, Game.PX * f.sz / 4.5, Color(1, 1, 1, a))
					else:
						var sz: float = f.sz
						var ca := Color(0.7, 2.2, 1.0, a)
						g.draw_rect(Rect2(p - Vector2(sz * 0.35, sz), Vector2(sz * 0.7, sz * 2.0)), ca)
						g.draw_rect(Rect2(p - Vector2(sz, sz * 0.35), Vector2(sz * 2.0, sz * 0.7)), ca)
			"drain":
				# 部件吸取（周围小怪被击杀削部件血）：一串金色光点从击杀点沿弧线飞进部件，末端部件闪一下
				var k := 1.0 - a
				var mid: Vector2 = (f.a + f.b) / 2.0 + Vector2(0, -30)
				for q in 5:
					var u: float = clampf(k * 1.5 - q * 0.1, 0.0, 1.0)
					if u <= 0.0 or u >= 1.0:
						continue
					var p: Vector2 = f.a.lerp(mid, u).lerp(mid.lerp(f.b, u), u)
					g.draw_circle(p, 3.5 - q * 0.4, Color(1.9, 1.6, 0.7, 0.9))
				if k > 0.65:
					g.draw_circle(f.b, 12.0 * (k - 0.65) / 0.35 + 4.0, Color(1.9, 1.6, 0.7, 0.5 * (1.0 - k) / 0.35))
			"beacon_burst":
				var k := 1.0 - a
				var rr: float = f.r * (1.0 - pow(1.0 - k, 3.0))
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, ground_y()))
				g.draw_circle(Vector2.ZERO, rr, Color(1.6, 1.3, 0.7, 0.18 * a))
				g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, Color(1.9, 1.6, 0.9, 0.9 * a), 6.0)
				g.draw_arc(Vector2.ZERO, rr * 0.8, 0.0, TAU, 64, Color(2.0, 2.0, 1.8, 0.6 * a), 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 12:
					var dv := Vector2.from_angle(q * TAU / 12.0)
					g.draw_line(f.pos + dv * rr * 0.3, f.pos + dv * rr * 0.6, Color(1.9, 1.6, 0.9, 0.7 * a), 3.0)
			"spear_fly":
				var k := 1.0 - a
				var p: Vector2 = f.pos.lerp(f.to, k) + Vector2(0, -110.0 * sin(k * PI))
				var ang: float = k * TAU * 1.5
				var dv := Vector2.from_angle(ang) * 34.0
				g.draw_line(p - dv, p + dv, Color(0.1, 0.12, 0.2, 0.9), 6.0)
				g.draw_line(p - dv, p + dv, Color(1.4, 1.6, 1.9), 3.0)
				g.draw_circle(p + dv, 4.0, Color(1.6, 1.9, 2.2))
				if k > 0.9:
					var gk: float = (k - 0.9) / 0.1
					g.draw_arc(f.to, 10.0 + 30.0 * gk, 0.0, TAU, 20, Color(0.8, 1.2, 1.7, 1.0 - gk), 2.0)
			"glint":
				# 竖直闪光（换剑）：十字星从中间展开再收
				var k := 1.0 - a
				var L: float = 60.0 * sin(k * PI)
				g.draw_line(f.pos + Vector2(0, -L), f.pos + Vector2(0, L), Color(2.0, 2.0, 2.0, a), 3.0)
				g.draw_line(f.pos + Vector2(-L * 0.4, 0), f.pos + Vector2(L * 0.4, 0), Color(2.0, 2.0, 2.0, a), 2.0)
				g.draw_circle(f.pos, 6.0 * a, Color(2.0, 2.0, 2.0, a))
			"reflow":
				# 碎片回流（塑路者核心超时）：一串碎石沿弧线从碎片位置冲回本体，尾迹变红，末端在本体上炸一圈
				var k := 1.0 - a
				var mid: Vector2 = (f.a + f.b) / 2.0 + (f.b - f.a).orthogonal().normalized() * 40.0
				for q in 6:
					var u: float = clampf(k * 1.4 - q * 0.07, 0.0, 1.0)
					if u <= 0.0 or u >= 1.0:
						continue
					var p0: Vector2 = f.a.lerp(mid, u).lerp(mid.lerp(f.b, u), u)
					var u2: float = maxf(0.0, u - 0.14)
					var p1: Vector2 = f.a.lerp(mid, u2).lerp(mid.lerp(f.b, u2), u2)
					g.draw_line(p1, p0, Color(1.6, 0.45, 0.35, 0.8), 6.0)
					UI.diamond(g, p0, 8.0 - q * 0.7, Color(0.75, 0.8, 1.2, 1.0), Color(0.1, 0.1, 0.2, 0.9))
				if k > 0.7:
					var rk: float = (k - 0.7) / 0.3
					g.draw_arc(f.b, 20.0 + 40.0 * rk, 0.0, TAU, 32, Color(1.6, 0.45, 0.35, 1.0 - rk), 3.0)
			"tide_link":
				# 双层弯曲潮线与逆流光点：接潮生命连接、伊莎玛拉泪滴共鸣共用。
				var c: Color = f.col
				var normal: Vector2 = (f.b - f.a).orthogonal().normalized()
				for side in [-1.0, 1.0]:
					var points := PackedVector2Array()
					for q in 13:
						var u: float = float(q) / 12.0
						points.append(f.a.lerp(f.b, u) + normal * side * sin(u * PI * 2.0 + g.t * 11.0) * 7.0 * sin(u * PI))
					g.draw_polyline(points, Color(0.02, 0.08, 0.16, 0.65 * a), 9.0)
					g.draw_polyline(points, Color(c.r * 1.4, c.g * 1.6, c.b * 1.8, 0.8 * a), 3.0)
				for q in 5:
					var u: float = fposmod(float(q) / 5.0 + g.t * 0.9, 1.0)
					var bead: Vector2 = f.a.lerp(f.b, u)
					g.draw_circle(bead, 3.5, Color(1.6, 2.4, 2.5, 0.8 * a))
				g.draw_arc(f.a, 14.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, a), 2.0)
				g.draw_arc(f.b, 14.0, 0.0, TAU, 20, Color(c.r, c.g, c.b, a), 2.0)
			"beam":
				var c: Color = f.col
				g.draw_line(f.a, f.b, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.35 * a), f.w * 3.0)
				g.draw_line(f.a, f.b, Color(2.5, 2.5, 2.5, a), f.w * 0.6)
			"rift":
				# 地面裂隙（触手 / 巨触出现前的预警）
				var k := 1.0 - a
				g.draw_set_transform(f.pos + Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
				g.draw_circle(Vector2.ZERO, f.r * (0.5 + 0.5 * k), Color(0.12, 0.02, 0.18, 0.6))
				g.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 36, Color(1.6, 0.7, 2.4, 0.4 + 0.5 * k), 2.0)
				for q in 5:
					var dv := Vector2.from_angle(q * TAU / 5.0 + f.r)
					g.draw_line(dv * f.r * 0.15, dv * f.r * (0.4 + 0.5 * k), Color(1.8, 0.9, 2.6, 0.8), 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tendril":
				# 从水月脚下伸向目标的触须线
				var pts := PackedVector2Array()
				var nrm: Vector2 = (f.b - f.a).orthogonal().normalized()
				for q in 13:
					var u := q / 12.0
					pts.append(f.a.lerp(f.b, u) + nrm * sin(u * PI * 2.0 + f.seed + g.t * 10.0) * 10.0 * (1.0 - u))
				g.draw_polyline(pts, Color(0.5, 0.2, 0.8, 0.55 * a), 5.0)
				g.draw_polyline(pts, Color(1.6, 0.9, 2.4, 0.8 * a), 1.5)
			"giant_t":
				# 巨型触手破土
				var k := 1.0 - a
				var fr := clampi(int(k * 6.0), 0, 4)
				var tc: Color = g.ch.tentacle_col(1.15) if g.ch.has_method("tentacle_col") else Color(1.3, 1.1, 1.6)
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(0, 16), Game.PX * 4.2, false, tc, Vector2(0.5, 1.0))
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(-50, 20), Game.PX * 2.6, true, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
				g.vfx.spr("tentacle", 5, fr, f.pos + Vector2(48, 22), Game.PX * 2.4, false, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
			"sprite":
				var spec: Array = Game.V6_FRAMES[f.name]
				var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
				var scol: Color = f.get("col", Color.WHITE)
				scol.a *= fdim
				g.vfx.spr_rot(f.name, fr, f.pos, f.ang, f.scale, scol, f.get("anchor", Vector2(-1, -1)), f.get("flip", false))
				if f.get("ring", 0.0) > 0.0 and fr == 0:
					g.draw_arc(f.pos, f.ring, 0.0, TAU, 40, Color(2.2, 2.0, 1.6, 0.6), 1.5)
			"impact":
				# 唤醒命中：十字闪光
				var k := 1.0 - a
				var L := 30.0 + 70.0 * k
				var c: Color = f.col
				var gc := Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a)
				for q in 4:
					var dv := Vector2.from_angle(f.ang + q * PI / 2.0 + PI / 4.0)
					g.draw_line(f.pos - dv * L * (0.6 if q % 2 else 1.0), f.pos + dv * L * (0.6 if q % 2 else 1.0), gc, 5.0 * a + 1.0)
				g.draw_circle(f.pos, 18.0 * a + 4.0, Color(3.0, 2.6, 1.8, a * 0.8))
			"burst":
				# 创伤扩散：水花冲击
				var k := 1.0 - a
				var rr: float = f.r * (0.4 + 0.7 * k)
				var c: Color = f.col
				g.draw_circle(f.pos, rr, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, 0.25 * a))
				g.draw_arc(f.pos, rr, 0.0, TAU, 32, Color(c.r * 2.2, c.g * 2.0, c.b * 1.6, a), 5.0)
				g.draw_arc(f.pos, rr * 0.7, 0.0, TAU, 32, Color(0.6, 1.6, 2.0, a * 0.6), 2.0)
				for q in 10:
					var dv := Vector2.from_angle(q * TAU / 10.0 + f.r)
					g.draw_line(f.pos + dv * rr * 0.8, f.pos + dv * (rr + 14.0 * a), Color(2.0, 1.8, 1.2, a), 2.0)
			"wpillar":
				# 潮汐柱：升起的水柱 + 水花
				var k := 1.0 - a
				var c: Color = f.col
				var hgt: float = f.r * 2.4 * minf(1.0, k * 3.0)
				var wd: float = f.r * 0.8 * a
				g.draw_rect(Rect2(f.pos + Vector2(-wd / 2.0, -hgt), Vector2(wd, hgt)), Color(c.r * 1.4, c.g * 1.4, c.b * 1.6, 0.35 * a))
				g.draw_rect(Rect2(f.pos + Vector2(-wd / 5.0, -hgt), Vector2(wd / 2.5, hgt)), Color(2.2, 2.6, 2.8, 0.6 * a))
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				g.draw_arc(Vector2.ZERO, f.r * (0.6 + 0.6 * k), 0.0, TAU, 32, Color(c.r * 1.6, c.g * 1.6, c.b * 1.8, a), 3.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"quake":
				# 震地 / 跳砸：地面裂纹放射
				var k := 1.0 - a
				var c: Color = f.col
				for q in 9:
					var dv := Vector2.from_angle(q * TAU / 9.0 + f.pos.x * 0.01)
					var l: float = f.r * (0.4 + 0.6 * minf(1.0, k * 2.5))
					g.draw_line(f.pos + dv * 8.0, f.pos + dv * l, Color(0.05, 0.03, 0.02, 0.8 * a), 3.0)
					g.draw_line(f.pos + dv * 8.0, f.pos + dv * l * 0.7, Color(c.r * 1.6, c.g * 1.4, c.b, a), 1.5)
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				g.draw_arc(Vector2.ZERO, f.r * (0.3 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, a * 0.8), 4.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tracer":
				# 狙击 / 裁决弹道
				var c: Color = f.col
				g.draw_line(f.a, f.b, Color(c.r * 1.5, c.g * 1.5, c.b * 1.2, 0.35 * a), f.wid * 2.0 * a + 2.0)
				g.draw_line(f.a, f.b, Color(2.6, 2.4, 2.0, a), 2.0)
			"bbeam":
				# 偏执凝视：粗光束
				var c: Color = f.col
				var k := 1.0 - a
				var wd: float = f.wid * 2.0 * (0.4 + 0.6 * a) + 6.0 * sin(g.t * 40.0)
				g.draw_line(f.a, f.b, Color(c.r * 1.2, c.g * 0.8, c.b * 1.6, 0.45 * a), wd * 1.6)
				g.draw_line(f.a, f.b, Color(c.r * 2.0, c.g * 1.4, c.b * 2.4, 0.8 * a), wd)
				g.draw_line(f.a, f.b, Color(2.6, 2.2, 2.8, a), wd * 0.3)
				for q in 6:
					var pp: Vector2 = f.a.lerp(f.b, (q + 0.5) / 6.0 + k * 0.1)
					g.draw_circle(pp, 5.0 + 4.0 * sin(g.t * 30.0 + q), Color(2.0, 1.6, 2.6, 0.6 * a))
			"bslash":
				# 横扫：宽弧刀光
				var c: Color = f.col
				var k := 1.0 - a
				var a0: float = f.ang - f.half + f.half * 2.0 * minf(1.0, k * 1.6)
				var a1: float = f.ang - f.half
				g.draw_arc(f.pos, f.r * 0.9, a1, a0, 24, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, a), 14.0)
				g.draw_arc(f.pos, f.r * 0.75, a1, a0, 24, Color(2.4, 2.6, 2.6, a), 4.0)
				g.draw_arc(f.pos, f.r * 0.5, a1, a0, 24, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.5 * a), 8.0)
			"pillar":
				# 触手破土：光柱
				var c: Color = f.col
				var hgt := 90.0 * (1.0 - a * 0.3)
				g.draw_rect(Rect2(f.pos + Vector2(-7 * a, -hgt), Vector2(14 * a, hgt)), Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.35 * a))
				g.draw_rect(Rect2(f.pos + Vector2(-2, -hgt), Vector2(4, hgt)), Color(2.5, 2.5, 2.5, 0.6 * a))
			"ghost":
				# 倒影：半透明的水月残像
				draw_player_at(f.pos, f.flip, Color(1.2, 0.8, 2.0, 0.55 * a), g.sprite.frame)
			"chain":
				# 束缚传播：锁链
				var n := 8
				for q in n:
					var p0: Vector2 = f.a.lerp(f.b, float(q) / n)
					UI.diamond(g, p0 + Vector2(0, -8), 4.0, Color(0.02, 0.05, 0.08, a), Color(0.7, 1.4, 2.0, a))
			"boss_phase":
				# Boss 换幕：两圈洋红冲击波 + 12 道放射光刺
				var k := 1.0 - a
				var mc := Color(1.6, 0.45, 1.3)
				for q in 2:
					var kq: float = clampf(k * 1.3 - q * 0.25, 0.0, 1.0)
					if kq > 0.0 and kq < 1.0:
						var rq: float = f.r * (1.2 + 6.0 * (1.0 - pow(1.0 - kq, 2.0)))
						g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
						g.draw_arc(Vector2.ZERO, rq, 0.0, TAU, 64, Color(mc.r, mc.g, mc.b, (1.0 - kq) * 0.9), 6.0 - q * 2.0)
						g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 12:
					var dv := Vector2.from_angle(q * TAU / 12.0 + 0.26)
					var r0: float = f.r * (0.8 + 3.0 * k)
					g.draw_line(f.pos + dv * r0, f.pos + dv * (r0 + f.r * 1.6 * a + 10.0), Color(mc.r, mc.g, mc.b, a), 3.0)
			"boss_down":
				# Boss 倒下：核心爆闪 → 三道冲击环 → 光柱收细
				var k := 1.0 - a
				var el: float = f.max - f.life
				if el < 0.3:
					var ck: float = el / 0.3
					g.draw_circle(f.pos, f.r * (1.0 + 1.5 * ck), Color(2.0, 1.9, 2.0, 1.0 - ck))
				var cols := [Color(2.0, 1.9, 2.0), Color(1.6, 0.45, 1.3), Color(0.5, 1.5, 1.6)]
				for q in 3:
					var kq: float = clampf((el - q * 0.14) / 1.1, 0.0, 1.0)
					if kq > 0.0 and kq < 1.0:
						var rq: float = f.r * (1.0 + 7.0 * (1.0 - pow(1.0 - kq, 3.0)))
						var cq: Color = cols[q]
						g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
						g.draw_arc(Vector2.ZERO, rq, 0.0, TAU, 72, Color(cq.r, cq.g, cq.b, (1.0 - kq) * 0.85), 7.0 - q * 2.0)
						g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var pw: float = f.r * 1.4 * (1.0 - k * k)
				if pw > 0.5:
					g.draw_rect(Rect2(f.pos.x - pw / 2.0, f.pos.y - 520.0, pw, 520.0 + f.r * 0.4), Color(1.8, 1.6, 2.0, 0.55 * a))
					g.draw_rect(Rect2(f.pos.x - pw / 6.0, f.pos.y - 520.0, pw / 3.0, 520.0 + f.r * 0.4), Color(2.0, 2.0, 2.0, 0.8 * a))
			"rays":
				# 技能发动：放射光束
				var k := 1.0 - a
				var c: Color = f.col
				for q in 16:
					var dv := Vector2.from_angle(q * TAU / 16.0 + k * 0.6)
					var r0 := 30.0 + 200.0 * k
					g.draw_line(f.pos + dv * r0, f.pos + dv * (r0 + 60.0 * a + 20.0), Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a), 3.0)
			"horde_ring":
				# 大群压迫波：从视野外向水月收缩
				var k := 1.0 - a
				var rr: float = lerpf(f.r, 170.0, k * k)
				var c: Color = f.col
				g.draw_arc(f.pos, rr, 0.0, TAU, 64, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.8 * a), 10.0)
				g.draw_arc(f.pos, rr + 18.0, 0.0, TAU, 64, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.3 * a), 5.0)
				for j in 24:
					var ang := TAU * j / 24.0 + g.t * 0.5
					var p0: Vector2 = f.pos + Vector2.from_angle(ang) * rr
					g.draw_line(p0, p0 + Vector2.from_angle(ang) * 40.0 * a, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.5 * a), 2.0)
			"slash":
				var nf: int = f.get("frames", 4)
				var fr := clampi(int((1.0 - a) * float(nf)), 0, nf - 1)
				var tn: String = f.get("tex", "slash")
				g.draw_set_transform(f.pos, f.ang, Vector2.ONE)
				var sc_col: Color = f.col if (tn == "slash" or tn.begins_with("fx_umbrella_slash")) else Color.WHITE
				g.vfx.spr(tn, nf, fr, Vector2.ZERO, f.scale, false, sc_col, f.get("anchor", Vector2(0.5, 0.5)))
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in g.ebullets:
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置
		g.draw_set_transform(b.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, b.r + 1.0, Color(0, 0, 0, 0.4))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp: Vector2 = b.pos + Vector2(0, -16)
		if b.get("kind", "") == "boss_blade":
			g.vfx.boss_blade(b, bp)
			continue
		# 敌方弹幕高对比：深色外圈垫底，画完再描一圈亮洋红边，压在友方特效上也一眼看得出
		g.draw_circle(bp, b.r + 3.0, Color(0.02, 0.0, 0.05, 0.85))
		match b.get("kind", "orb"):
			"acid":
				g.draw_circle(bp, b.r + 5.0, Color(0.5, 1.4, 0.3, 0.3))
				g.draw_circle(bp, b.r, Color(0.6, 1.8, 0.4))
				g.draw_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6))
			"nova":
				g.draw_circle(bp, b.r + 5.0, Color(1.2, 0.4, 1.8, 0.3))
				g.draw_circle(bp, b.r, b.get("col", Color(1.5, 0.6, 2.0)))
			"nerve":
				# 浮海飘航者神经弹（V8 proj_floater_nerve，朝右绘制按速度方向旋转）
				g.draw_circle(bp, b.r + 5.0, Color(1.0, 0.9, 0.3, 0.25))
				if g.tex.get("proj_floater_nerve") != null:
					g.vfx.spr_rot("proj_floater_nerve", int(g.t * 12.0 + b.pos.x * 0.01) % 4, bp, b.vel.angle(), Game.PX)
				else:
					g.draw_circle(bp, b.r, Color(1.8, 1.6, 0.5))
			_:
				g.draw_circle(bp, b.r + 4.0, Color(1.0, 0.3, 0.6, 0.25))
				g.vfx.spr("ebullet", 1, 0, bp, Game.PX * b.r / 5.0)
		g.draw_arc(bp, b.r + 2.0, 0.0, TAU, 16, Color(2.4, 0.8, 1.8, 0.9), 1.5)
	# 抛射碎石：落点预警 + 空中石块
	for l in g.lobs:
		var k: float = l.t / l.dur
		# 抛石落点：地面椭圆（与判定一致）+ 深色描边 + 敌方洋红，不再乘亮度（docs/48 ①④）
		g.draw_set_transform(l.to, 0.0, Vector2(1.0, ground_y()))
		g.draw_circle(Vector2.ZERO, l.r * k, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, 0.22))
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 4.0)
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 32, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, 0.6 + 0.35 * sin(g.t * 20.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var gp: Vector2 = l.from.lerp(l.to, k)
		var hgt := sin(k * PI) * 120.0
		g.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rp := gp + Vector2(0, -hgt - 8.0)
		g.draw_circle(rp, 7.0, Color(0.45, 0.42, 0.4))
		g.draw_circle(rp + Vector2(-2, -2), 3.0, Color(0.7, 0.66, 0.6))
	# 冲击环（docs/48 全局 ④⑤、P0 伊祖米克）：原来写死成治疗同款的绿色、越扩越淡，到主控这里几乎看不见。
	# 改成敌方危险色：深色外描边 + 洋红紫主色 + 白芯，透明度下限 0.6，扩到最大也看得清
	for sh in g.shocks:
		var a: float = maxf(0.6, 1.0 - sh.r / sh.maxr)
		g.draw_set_transform(sh.pos, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致（docs/48 ①）
		g.draw_arc(Vector2.ZERO, sh.r - 8.0, 0.0, TAU, 48, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, 0.18 * a), 10.0)
		g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(0, 0, 0, 0.55 * a), 7.0)
		g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, a), 4.0)
		g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * a), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_enemy_tells()
	draw_leader_ailments()
	draw_warn_outlines()
	draw_zone()
	g.map.draw_snow()


## 主角帧动画（美术交付 player_*.png 后自动启用；帧为正方形，帧数 = 宽 / 高）
func update_player_anim(dt: float) -> void:
	if g.tex.get("doctor") != null:
		update_doctor_anim(dt)
		return
	if g.tex.get("player_attack_48") != null:
		update_player_anim48(dt)
		return
	var want := "player_idle"
	if g.state == Game.S.DEAD:
		want = "player_death"
	elif g.hurt_flash > 0.05:
		want = "player_hurt"
	elif g.swing_face > 0.0:
		want = "player_attack"
	elif g.moving:
		want = "player_run"
	if g.tex.get(want) == null:
		want = "player_idle" if g.tex.get("player_idle") != null else ""
	if want == "":
		return
	if want != anim_name:
		anim_name = want
		anim_t = 0.0
		var tx: Texture2D = g.tex[want]
		g.sprite.texture = tx
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		g.sprite.offset = Vector2(0, -tx.get_height() / 2.0)
	anim_t += dt
	var n := g.sprite.hframes
	match anim_name:
		"player_attack":
			g.sprite.frame = clampi(int(anim_t / 0.25 * n), 0, n - 1)
		"player_death":
			g.sprite.frame = clampi(int(anim_t * 6.0), 0, n - 1)
		_:
			g.sprite.frame = int(anim_t * (12.0 if anim_name == "player_run" else 6.0)) % n


## 博士动画：data/doctor.json 的 sprites（编队美术第一批：idle 4 / run 6 / hurt 2 / death 4 帧，脚底 46）；
## 某个动作没有贴图时退回旧 2 帧待机条（doctor）：跑步 = 加快切帧 + 颠簸，倒下 = 侧倒
func update_doctor_anim(dt: float) -> void:
	# 博士是挂件：不受击，只有待机 / 跑步；主控倒下时一起倒下
	var want := "idle"
	if g.state == Game.S.DEAD:
		want = "death"
	elif g.doc_moving:
		want = "run"
	var sp: Dictionary = g.doctor.def.get("sprites", {})
	var tx: Texture2D = g.tex.get(sp.get(want, ""), null) if sp.has(want) else null
	var fallback := tx == null
	if fallback:
		tx = g.tex["doctor"]
	var key := want + ("_fb" if fallback else "")
	if key != anim_name:
		anim_name = key
		anim_t = 0.0
		g.sprite.texture = tx
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		# 脚底锚点：data/doctor.json 的 sprites.foot（旧 2 帧待机条为 45，编队美术第一批为 46）
		var foot_y: float = float(sp.get("foot", [24, 45])[1])
		g.sprite.offset = Vector2(0, -tx.get_height() / 2.0 + (48.0 - foot_y) * A.hires_of(tx))
	anim_t += dt
	var n := g.sprite.hframes
	g.sprite.rotation = 0.0
	if fallback:
		match want:
			"death":
				g.sprite.frame = 0
				g.sprite.rotation = lerpf(0.0, -1.45 * (1.0 if g.facing >= 0.0 else -1.0), clampf(anim_t / 0.35, 0.0, 1.0))
			"run":
				g.sprite.frame = int(anim_t * 7.0) % n
				g.sprite.position.y -= Game.PX * absf(sin(anim_t * 11.0)) * 1.5
			_:
				g.sprite.frame = int(anim_t * 2.0) % n
	else:
		var spec: Array = P48.get(want, [4.0, true])
		var f := int(anim_t * spec[0])
		g.sprite.frame = f % n if spec[1] else mini(f, n - 1)


func p48_tex(kind: String) -> Texture2D:
	if kind == "attack":
		return g.tex.get("player_attack_48")
	var tx: Texture2D = g.tex.get("player_" + kind)
	if tx != null and tx.get_height() == int(48.0 * A.hires_of(tx)):
		return tx
	return null


func update_player_anim48(dt: float) -> void:
	var want := "idle"
	if g.state == Game.S.DEAD:
		want = "death"
	elif g.hurt_flash > 0.05:
		want = "hurt"
	elif g.swing_face > 0.0:
		want = "attack"
	elif g.moving:
		want = "run"
	var tx := p48_tex(want)
	var fallback := tx == null
	if fallback:
		tx = g.tex["player_attack_48"]
	var key := want + ("_fb" if fallback else "")
	if key != anim_name:
		anim_name = key
		anim_t = 0.0
		g.sprite.texture = tx
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		g.sprite.offset = Vector2(0, -tx.get_height() / 2.0 + 2.0 * A.hires_of(tx))
	anim_t += dt
	var n := g.sprite.hframes
	g.sprite.rotation = 0.0
	if want == "attack" and not fallback:
		g.sprite.frame = clampi(int((0.25 - g.swing_face) / 0.25 * n), 0, n - 1)
	elif fallback:
		g.sprite.frame = 0
		if want == "death":
			g.sprite.rotation = lerpf(0.0, -1.45 * (1.0 if g.facing >= 0.0 else -1.0), clampf(anim_t / 0.35, 0.0, 1.0))
		elif want == "idle":
			g.sprite.position.y -= Game.PX * float(int(g.t / 0.8) % 2)
	else:
		var spec: Array = P48[want]
		var f := int(anim_t * spec[0])
		g.sprite.frame = f % n if spec[1] else mini(f, n - 1)


## 逻辑帧选择不依赖 draw 次数，自动测试 / 演练 / 实战共用。
func ishar_animation(e: Dictionary) -> Dictionary:
	var base: String = "e_ishar_t" if e.phase == 2 else "e_ishar"
	if e.phase == 2 and g.t < float(e.get("transform_until", -1.0)):
		return {"name": "e_ishar_transform", "frames": 6, "frame": clampi(int((g.t - float(e.transform_started)) / 0.15), 0, 5)}
	if e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0:
		return {"name": base + "_attack", "frames": 4, "frame": clampi(int((1.0 - e.pose / e.pose_max) * 4.0), 0, 3)}
	if g.t < float(e.get("atk_until", 0.0)):
		return {"name": base + "_attack", "frames": 4, "frame": 2 if e.atk_until - g.t > 0.1 else 3}
	if g.t < float(e.get("mv_until", 0.0)):
		return {"name": base + "_move", "frames": 4, "frame": int(g.t * 5.0) % 4}
	return {"name": base, "frames": 2, "frame": int(g.t * 2.0) % 2}


func enemy_scale(e: Dictionary) -> float:
	var d: Dictionary = D.ENEMIES.get(e.type, {})
	var scale_key := "transformed_draw_scale" if e.type == "ishar" and e.phase == 2 else "draw_scale"
	var factor := float(d.get(scale_key, 1.0))
	if e.type == "ishar" and g.t < float(e.get("transform_until", -1.0)):
		factor = lerpf(float(d.get("draw_scale", 0.68)), factor, clampf((g.t - float(e.transform_started)) / 0.9, 0.0, 1.0))
	return Game.PX * e.r / e.r0 * factor


func draw_enemy(e: Dictionary) -> void:
	var name: String = e.tex
	# 形态切换：偏执泡影二阶段 / 接潮三件套昏迷时的假死造型
	if e.type == "paranoia" and e.phase == 2 and g.tex.get("e_paranoia2") != null:
		name = "e_paranoia2"
	elif e.coma and e.tex_feign:
		name = name + "_feign"
	# 伊莎玛拉完成转化（phase 2）：换成白壳金棘的变身形态 e_ishar_t*（112×96，docs/38 §6.2，docs/48 P1）；刚变身时先播 e_ishar_transform 一次
	var tbase: String = e.tex
	if e.type == "ishar" and e.phase == 2 and _lazy_tex("e_ishar_t") != null:
		tbase = "e_ishar_t"
		name = tbase
		_lazy_tex("e_ishar_t_move")
		_lazy_tex("e_ishar_t_attack")
	var frames := 2
	var frame := int(g.t * (2.0 if e.boss else 5.0) + e.id * 0.37) % 2
	# 移动帧条（美术 V5 / V8 / V9）：移动中播放 4 帧循环；停下、晕眩、假死时用本体
	if e.tex_move:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = g.t + 0.2
		e.dpos = e.pos
		if g.t < e.mv_until and e.stun <= 0.0 and not e.coma and g.tex.get(name + "_move") != null:
			name += "_move"
			frames = 4
			var fps: float = float(D.ENEMIES.get(e.type, {}).get("move_fps", 6.0))
			if e.type == "immortal":
				fps = 8.0
			elif e.type in ["paranoia", "izumik", "ishar"]:
				fps = 5.0
			frame = int(g.t * fps + e.id * 0.37) % 4
	# 冲刺帧条（V9 骑士）：蓄力用前 2 帧，冲出去用后 2 帧
	if e.get("tex_charge", false) and (e.get("dash_w", 0.0) > 0.0 or e.get("dash_t", 0.0) > 0.0):
		name = e.tex + "_charge"
		frames = 4
		if e.dash_w > 0.0:
			frame = 0 if e.dash_w > 0.25 else 1
		else:
			frame = 2 if e.dash_t > 0.12 else 3
	# 美术 V8 小怪帧条：攻击（atk_anim：蓄力 / 鼓胀时第 1、2 帧，出手后 0.2 秒第 3、4 帧）、休眠 / 唤醒、狂暴待机
	var ed: Dictionary = D.ENEMIES.get(e.type, {})
	if ed.get("atk_anim", false) and e.tex_attack:
		var ww: float = maxf(maxf(maxf(e.get("wind", 0.0), e.get("blast_w", 0.0)), maxf(maxf(e.get("burst_w", 0.0), e.get("dash_w", 0.0)), e.get("nova_w", 0.0))), float(e.get("shot_wind_until", 0.0)) - g.t)   # 各种蓄力都播攻击帧条前两帧（docs/48 ⑥）
		if ww > 0.0:
			e.atk_until = g.t + 0.2
			name = e.tex + "_attack"
			frames = 4
			frame = 0 if ww > 0.2 else 1
		elif g.t < e.get("atk_until", 0.0):
			name = e.tex + "_attack"
			frames = 4
			frame = 2 if e.atk_until - g.t > 0.1 else 3
		elif e.get("attack_preparing", false):
			name = e.tex + "_attack"
			frames = 4
			# 远处举肢准备；实际预警和出手帧仍优先，伤害窗口不变。
			frame = int((g.t - float(e.get("prepare_started", g.t))) * 3.0) % 2
	if e.get("dormant", false) and g.tex.get(e.tex + "_dormant") != null:
		name = e.tex + "_dormant"
		frames = 2
		frame = int(g.t * 3.0 + e.id * 0.37) % 2
	elif e.get("wake_t", 0.0) > 0.0 and g.tex.get(e.tex + "_awaken") != null:
		name = e.tex + "_awaken"
		frames = 4
		frame = clampi(int((0.4 - e.wake_t) * 10.0), 0, 3)
	elif e.get("enraged", false) and name == e.tex and g.tex.get(e.tex + "_enraged") != null:
		name = e.tex + "_enraged"
		frames = 2
		frame = int(g.t * 5.0 + e.id * 0.37) % 2
	var rage_fx: bool = e.get("enraged", false)   # 狂暴：除了待机帧换图，移动 / 攻击帧也染红、脚下红光（docs/48 P1：原来只在待机帧生效）
	# 巢涌者神经光环改到地面层画（draw_nest_auras），不再按 4.6 倍放大帧条盖在实体上
	# 染色复用贴图的敌人（巨海、撕裂者、潜地者、吐酸者）按自身半径放大：enemies.json 的 draw_scale（docs/48 §1 第 7 项）
	var sc: float = enemy_scale(e)
	var col: Color = D.ENEMIES.get(e.type, {}).get("tint", Color.WHITE)
	if e.evo:
		col = col * Color(1.0, 0.62, 0.68)
	if e.type == "paranoia" and e.phase == 2:
		# 偏执泡影二阶段：e_paranoia2 和一阶段几乎一样（新图已下单 v12），过渡期在画面层区分——
		# 整体偏洋红、体量 ×1.1、身周一圈扭动的洋红光晕
		col = col * PARANOIA2_TINT
		sc *= 1.1
		_paranoia2_halo(e)
	if e.get("under", false):
		# 潜行中：只画地面波纹与影子
		g.draw_set_transform(e.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, e.r + 6.0, Color(0.05, 0.02, 0.1, 0.6))
		g.draw_arc(Vector2.ZERO, e.r + 10.0 + 6.0 * sin(g.t * 9.0 + e.id), 0.0, TAU, 20, Color(0.7, 0.5, 1.0, 0.5), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if e.invuln:
		col = Color(0.7, 0.85, 1.0, 0.75)
	if e.chest:
		frame = 0
		var wob := 0.0
		if e.hidden and fmod(g.t + e.id, 3.0) < 0.25:
			wob = sin(g.t * 60.0) * 1.5
		if e.get("event", "") != "":
			frame = int(g.t * 2.0) % 2
			g.draw_set_transform(e.pos + Vector2(0, 14), 0.0, Vector2(1.0, 0.45))
			g.draw_circle(Vector2.ZERO, 34.0 + 4.0 * sin(g.t * 3.0), Color(0.3, 0.6, 1.4, 0.18))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.vfx.spr(name, 2, frame, e.pos + Vector2(wob, 0), Game.PX, false, col)
		if e.flash > 0.0:
			g.vfx.spr(name + "_white", 2, 0, e.pos, Game.PX, false, Color(1, 1, 1, 0.9))
		return
	if e.stun > 0.0:
		col = col * Color(0.65, 0.75, 1.0)
	if rage_fx:
		var rp: float = 0.5 + 0.5 * sin(g.t * 10.0 + e.id)
		col = col * Color(1.35, 0.78, 0.72).lerp(Color(1.6, 0.7, 0.6), rp)
		g.draw_set_transform(e.pos + Vector2(0, e.r * 0.7), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, e.r * 1.3, Color(1.6, 0.25, 0.2, 0.18 + 0.12 * rp))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 冲刺预警线改在特效之上的覆盖层画（draw_enemy_tells，docs/48 ②）
	if e.get("dash_t", 0.0) > 0.0:
		g.vfx.sparks(e.pos, -e.dash_dir, Color(0.8, 0.9, 1.0), 1, 80.0)
	if e.get("nova_w", 0.0) > 0.0:
		var nk: float = 1.0 - e.nova_w / 0.6
		g.draw_circle(e.pos, e.r + 6.0 + 10.0 * nk, Color(1.4, 0.5, 2.0, 0.2 + 0.3 * nk))
		col = col.lerp(Color(2.0, 1.2, 2.4), nk * 0.6)
	if e.get("gate_hold", false):
		# 阶段护盾（docs/38 §1.3）：Boss 停在刻度上，金色护盾环脉动；这一幕满最短时长后碎掉
		var gp: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.draw_circle(e.pos, e.r + 14.0, Color(1.0, 0.8, 0.3, 0.08 + 0.06 * gp))
		g.draw_arc(e.pos, e.r + 14.0 + 3.0 * gp, 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.55 + 0.3 * gp), 2.5)
		col = col.lerp(Color(1.8, 1.5, 0.9), 0.25)
	if e.get("blast_w", 0.0) > 0.0:
		# 壳海狂奔者自爆鼓胀：爆炸范围预警圈从小到大，本体胀大变亮
		var xd: Dictionary = D.ENEMIES.get(e.type, {})
		var xk: float = 1.0 - e.blast_w / float(xd.get("blast_fuse", 0.55))
		# 范围圈改在特效之上的覆盖层画（draw_enemy_tells，docs/48 ②），这里只留本体胀大变亮
		col = col.lerp(Color(2.4, 1.1, 1.6), xk * 0.7)
		e.squash = maxf(e.squash, 0.14 * xk * (0.6 + 0.4 * sin(g.t * 40.0)))
	if e.get("burst_w", 0.0) > 0.0:
		# 囊海爬行者鼓胀：爆发范围预警圈从小到大，本体变亮
		var bk: float = 1.0 - e.burst_w / 0.4
		# 范围圈改在覆盖层画（draw_enemy_tells），这里只留本体变亮
		col = col.lerp(Color(2.2, 1.4, 2.6), bk * 0.7)
	g.draw_off = Vector2(0, -minf(e.kb.length() * 0.03, 14.0))
	var flip: bool = e.fx < 0.0
	var anc := Vector2(0.5, 0.5)
	var bpos: Vector2 = e.pos
	if g.foot_anchor.has(e.tex):
		anc = Vector2(0.5, 1.0)
		bpos = e.pos + Vector2(0, (31.0 if e.type == "ishar" else e.r) * 0.8 + 3.0 * Game.PX)
	var k: float = clamp(e.squash / 0.14, 0.0, 1.0)
	var sq := Vector2(1.0 + 0.3 * k, 1.0 - 0.25 * k)
	# Boss 攻击姿态：蓄力时后仰变亮，出手瞬间前倾拉伸；有 _attack 帧条时改用帧条
	if e.boss and e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0:
		var pk: float = e.pose / e.pose_max
		if (e.tex_attack or g.tex.get(tbase + "_attack") != null) and not e.coma:
			name = tbase + "_attack"
			frames = 4
			frame = clampi(int((1.0 - pk) * 4.0), 0, 3)
		elif e.pose > 0.3:
			var wk: float = minf(1.0, (1.0 - pk) * 2.0)
			sq *= Vector2(1.0 - 0.06 * wk, 1.0 + 0.08 * wk)
			bpos.x -= e.fx * 4.0 * wk
			col = col.lerp(Color(1.8, 1.5, 1.4), 0.35 * wk + 0.25 * wk * sin(g.t * 30.0))
		else:
			var rk: float = e.pose / 0.3
			sq *= Vector2(1.0 + 0.22 * rk, 1.0 - 0.14 * rk)
			bpos.x += e.fx * 12.0 * rk
	if e.type == "ishar":
		var ia := ishar_animation(e)
		if _lazy_tex(ia.name) != null:
			name = ia.name
			frames = ia.frames
			frame = ia.frame
	# @2x 高清帧条（伊莎玛拉变身形态有 @2x）：同一逻辑尺寸，按密度减半
	var hr: float = A.hires_of(g.tex.get(name)) if g.tex.get(name) != null else 1.0
	if hr > 1.0:
		sc /= hr
	if e.has("ammo") and e.get("break_t", 0.0) > 0.0:
		sq *= Vector2(1.1, 0.78)   # 装填被打断：跪地（没有跪地帧条，压低代替）
		col = col * Color(0.8, 0.8, 0.9)
	if e.get("sword_t", 0.0) > 0.0:
		_sword_glint(e, bpos)
	if e.get("air", 0.0) > 0.0:
		g.draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, e.r * 0.9, Color(0, 0, 0, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_off.y -= e.air
	# 轮廓光：深色怪物在灯光外也能看清（颜色 >1，抵消环境暗色）
	if e.get("part", false):
		# 部件（塑路者核心等）：心跳脉动——每拍一次放大 + 金色光晕；描边不受「怪物轮廓光」开关影响
		var hb: float = _heartbeat(e)
		sq *= 1.0 + 0.1 * hb
		g.draw_circle(e.pos, e.r * (1.3 + 0.5 * hb), Color(PART_COL.r * 1.4, PART_COL.g * 1.4, PART_COL.b * 1.4, 0.22 + 0.3 * hb))
		if not Cfg.outline and g.tex.has(name + "_white"):
			for d in [Vector2(Game.PX, 0), Vector2(-Game.PX, 0), Vector2(0, Game.PX), Vector2(0, -Game.PX)]:
				g.vfx.spr(name + "_white", frames, frame, bpos + d, sc, flip, Color(PART_COL.r * 2.0, PART_COL.g * 2.0, PART_COL.b * 2.0, 0.8), anc, sq)
	if Cfg.outline and g.tex.has(name + "_white"):
		var oc := Color(2.2, 2.0, 2.6, 0.5) if not e.elite else Color(3.2, 1.1, 0.7, 0.75)
		if e.get("part", false):
			oc = Color(PART_COL.r * 2.0, PART_COL.g * 2.0, PART_COL.b * 2.0, 0.7 + 0.3 * _heartbeat(e))   # 普通怪：中性偏淡紫白（原青白，和经验结晶、击杀溶解同色连片，docs/48 P1）   # 精英：橙红（docs/48 ⑤，原金色和友方金圈、刀光撞色）
		if not e.elite and not e.boss:
			oc.a *= lerpf(1.0, 0.4, ecrowd)   # 后期满屏敌人时普通怪描边变淡，不再连成一片（EA 1.1）；精英 / Boss 不变
		for d in [Vector2(Game.PX, 0), Vector2(-Game.PX, 0), Vector2(0, Game.PX), Vector2(0, -Game.PX)]:
			g.vfx.spr(name + "_white", frames, frame, bpos + d, sc, flip, oc, anc, sq)
	g.vfx.spr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		g.vfx.spr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc, sq)
	if e.get("affix", "") != "":
		_affix_fx(e, bpos, _enemy_top(e))
	var wk: String = e.get("weak", "")
	if wk != "" and not e.get("under", false):
		var wc := Color(1.0, 0.75, 0.3) if wk == "物理" else (Color(0.7, 0.55, 1.0) if wk == "法术" else Color(1.0, 0.5, 0.8))
		var wp: Vector2 = e.pos + Vector2(e.r * 0.8 + 6.0, -e.r - 4.0)
		UI.diamond(g, wp, 4.5, Color(0.02, 0.04, 0.08), wc)
		if e.boss:
			UI.text(g, g.font, wp + Vector2(-20, 16), ("弱" + wk.substr(0, 1)) if wk != "双" else "双弱", 10, wc, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# 精英血条与标识改到 HUD 层（hud.draw_elite_marks）：不受灯光压暗，也不受「怪物轮廓光」开关影响（docs/48 P1）
	g.draw_off = Vector2.ZERO


## 在任意位置绘制水月（残影、倒影用）
## 以脚底为锚点画一帧（干员本体 / 分身 / 残影）：foot_off = 帧内脚底距底边的像素（贴图像素）
func draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float) -> void:
	if tx == null:
		return
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	var pk: float = Game.PX / A.hires_of(tx)
	g.draw_set_transform((pos + g.draw_off).round(), 0.0, Vector2(-pk if flip else pk, pk))
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off), Vector2(fw, fh)), src, col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_player_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D = null, hf: int = 0) -> void:
	if tx == null:
		tx = g.sprite.texture
		hf = g.sprite.hframes
	if tx == null:
		return
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	var pk: float = Game.PX / A.hires_of(tx)
	g.draw_set_transform(pos, 0.0, Vector2(-pk if flip else pk, pk))
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + Vector2(0, -fh / 2.0 + 2.0 * A.hires_of(tx)), Vector2(fw, fh)), src, col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 黑潮：圈外暗紫雾 + 圈边脉动溟痕 + 下一圈预告
## 敌方出招特效（2026-09-27 用户反馈：骑士攻击没有特效）：Boss与怪物 在预警结算 / 小怪起冲时写 e.last_act = {act, shape, pos, ang, r, len, wid, half, t}，
## 这里按 t 变化触发一次。目前接骑士（敌对骑士精英 / 最后的骑士）：冲锋留冰霜拖尾 + 终点冲击、长枪连刺冰蓝刀光、寒冰领域冰晶爆开。都标 enemy，不被降噪
const KNIGHT_TYPES := ["knight", "knight_boss"]

func _enemy_act_fx() -> void:
	for e in g.enemies:
		if e.dead or not KNIGHT_TYPES.has(e.type):
			continue
		var la = e.get("last_act")
		if not (la is Dictionary) or float(la.get("t", -1.0)) <= float(e.get("act_seen_t", -1.0)):
			continue
		e["act_seen_t"] = float(la.t)
		var p0: Vector2 = la.get("pos", e.pos)
		var ang: float = float(la.get("ang", 0.0))
		match str(la.get("act", "")):
			"dash", "charge":
				Sfx.play("knight_charge", -6.0 if e.boss else -10.0, 1.0, 0.05)   # 冰面急冲（音频，tools/gen_sfx_events.py）
				var L: float = float(la.get("len", 200.0))
				var dv := Vector2.from_angle(ang)
				var s := 0.0
				while s < L:
					g.fx.append({"kind": "frost_step", "pos": p0 + dv * s + Vector2(0, 8), "life": 0.9, "max": 0.9, "r": 14.0, "enemy": true})
					s += 30.0
				g.vfx.fx_sprite("fx_knight_impact", p0 + dv * L, g.PX * 1.2, ang)
				g.fx[g.fx.size() - 1]["enemy"] = true
			"bite":
				Sfx.play("knight_stab", -2.0, 1.0, 0.06)   # 枪刺「锵」+ 冰光
				g.vfx.slash_fx(p0, ang, float(la.get("half", 0.8)), float(la.get("r", 125.0)), Color(0.7, 0.9, 1.6), "slash", 0.26)
				for q in range(g.fx.size() - 3, g.fx.size()):
					if q >= 0:
						g.fx[q]["enemy"] = true
				g.vfx.fx_sprite("fx_knight_impact", p0 + Vector2.from_angle(ang) * float(la.get("r", 125.0)) * 0.7, g.PX, ang)
				g.fx[g.fx.size() - 1]["enemy"] = true
			"frost":
				Sfx.play("knight_frost", -4.0, 1.0, 0.0)   # 冰晶爆开
				var fr: float = float(la.get("r", 200.0))
				g.fx.append({"kind": "ring", "pos": p0, "r": fr, "life": 0.6, "max": 0.6, "col": Color(0.7, 0.9, 1.4), "enemy": true})
				for q in 10:
					var dq := Vector2.from_angle(TAU * q / 10.0)
					g.vfx.fx_sprite("fx_knight_impact", p0 + dq * fr * 0.6, g.PX * 0.7, dq.angle())
					g.fx[g.fx.size() - 1]["enemy"] = true


## 敌方自带的危险提示（docs/48 全局 ②，P0 狂奔者 / 囊海爬行者 / 伊祖米克）：原来画在实体层，会被光照压暗、被友方特效盖住。
## 统一画在特效之上：主题色半透明填充（从小到大表示倒计时）+ 深色外描边 + 主题色线 + 白芯；颜色不乘亮度，保住色相（全局 ④）
const PART_COL := Color(1.0, 0.82, 0.35)      # Boss 部件（e.part）：金色描边 + 心跳
const ENEMY_TELL := Color(1.0, 0.3, 0.72)       # 敌方危险主色：洋红（和友方的金、青、绿、艾雅法拉的橙红都分得开）
const TELL_BURST := Color(0.78, 0.42, 1.0)      # 囊海爬行者爆裂：紫

func draw_enemy_tells() -> void:
	var tvr: Rect2 = view_rect(TELL_MARGIN)   # 冲刺线 / 危险圈能伸进屏幕，外扩大一些
	for e in g.enemies:
		if e.dead or (not e.boss and not tvr.has_point(e.pos)):
			continue
		if e.get("blast_w", 0.0) > 0.0:
			var xd: Dictionary = D.ENEMIES.get(e.type, {})
			var xk: float = clampf(1.0 - e.blast_w / float(xd.get("blast_fuse", 0.55)), 0.0, 1.0)
			_tell_circle(e.pos, float(xd.get("blast_r", 62)), xk, ENEMY_TELL)
		if e.get("burst_w", 0.0) > 0.0:
			_tell_circle(e.pos, 80.0, clampf(1.0 - e.burst_w / float(e.get("burst_dur", 0.4)), 0.0, 1.0), TELL_BURST)
		# 冲刺预警线（滑动者 / 撕裂者 / 骑士精英）：长度按实际冲刺距离算（速度 × dash_speed × 0.35 秒），
		# 不再写死 230（docs/48 P1：实际只冲 80–135）；只朝前画
		if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir"):
			var dd: Dictionary = D.ENEMIES.get(e.type, {})
			var wk: float = clampf(1.0 - e.dash_w / float(dd.get("dash_wind", 0.5)), 0.0, 1.0)
			var L: float = float(e.get("dash_len", clampf(e.spd * float(dd.get("dash_speed", 3.8)) * 0.35, 60.0, 400.0)))   # Boss与怪物 给了 dash_len 就用它
			_tell_line(e.pos, e.pos + e.dash_dir * L, 10.0, wk, ENEMY_TELL)
		# 伊祖米克解读阶段的冲击波已改走 boss_ai._warn（1 秒预警、must_dash 标记，Boss与怪物 docs/48 P0-5），这里不再按 bt 预告
		if e.get("count_max", 0.0) > 0.0 and float(e.get("count_end", 0.0)) > g.t:
			_count_ring(e)
		if e.get("stakes", []) is Array and not e.get("stakes", []).is_empty():
			_draw_stakes(e)
		if e.type == "tear":
			_tear_zone(e)
		elif e.boss:
			_boss_state(e)


## 通用倒计时环（Boss与怪物约定：凡是 e.count_end / e.count_max 的单位——部件、假死、读条——都画这一种）：
## 脚下椭圆环按剩余时间收缩，最后 3 秒变红并加快脉动，环旁一个秒数小牌；部件金色、假死青色、其余洋红
func _count_ring(e: Dictionary) -> void:
	var left: float = maxf(0.0, float(e.count_end) - g.t)
	var k: float = clampf(left / float(e.count_max), 0.0, 1.0)
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8) if g.foot_anchor.has(e.tex) else e.pos + Vector2(0, e.r * 0.5)
	var c: Color = PART_COL if e.get("part", false) else (Color(0.5, 1.5, 1.4) if e.get("coma", false) else (Color(1.6, 1.2, 0.5) if e.get("channel", 0.0) > 0.0 else ENEMY_TELL))   # 读条（圣徒装填）金色
	if left < 3.0:
		c = c.lerp(Color(1.8, 0.4, 0.35), 0.5 + 0.5 * sin(g.t * 16.0))
	var rr: float = maxf(e.r + 14.0, 26.0)
	_ground_ring(foot, rr, k, c)
	var tag := "%d" % ceili(left)
	var tp: Vector2 = foot + Vector2(rr + 6.0, -4.0)
	g.draw_rect(Rect2(tp + Vector2(-2, -12), Vector2(UI.cwidth(g.font, tag, 13) + 8.0, 17)), Color(0.02, 0.03, 0.05, 0.8))
	UI.ctext(g, g.font, tp + Vector2(2, 1), tag, 13, c)


## 地面进度环（脚下椭圆，从正上方顺时针填充）
func _ground_ring(p: Vector2, r: float, k: float, c: Color) -> void:
	g.draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 7.0)
	g.draw_arc(Vector2.ZERO, r, -PI / 2.0, -PI / 2.0 + TAU * k, 48, c, 4.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 敌人贴图头顶的世界坐标（脚底锚点的贴图从脚往上长，不能按 e.r 算）
func _enemy_top(e: Dictionary) -> Vector2:
	var name: String = ishar_animation(e).name if e.type == "ishar" else e.tex
	var tx: Texture2D = _lazy_tex(name)
	if tx == null or not g.foot_anchor.has(e.tex):
		return e.pos + Vector2(0, -e.r - 8.0)
	var sc: float = enemy_scale(e) / A.hires_of(tx)
	return e.pos + Vector2(0, (31.0 if e.type == "ishar" else e.r) * 0.8 + 3.0 * Game.PX - tx.get_height() * sc)


## 巢涌者神经光环（docs/48 P1：帧条放大 4.6 倍后颗粒很粗，画在实体层会盖住其他东西）：
## 地面层程序绘制——淡紫柔光底、两道向内收的涟漪、缓慢转动的虚线外圈 = 判定范围
func draw_nest_auras() -> void:
	for e in g.enemies:
		if e.dead:
			continue
		if float(e.get("burden_r", 0.0)) > 0.0 and e.get("cocoon_t", 0.0) <= 0.0:
			_burden_ring(e)
		if e.get("lamps", []) is Array and not e.get("lamps", []).is_empty():
			_izu_lamps(e)
		var ed: Dictionary = D.ENEMIES.get(e.type, {})
		if not ed.has("aura_r"):
			continue
		var ar: float = ed.aura_r
		var aura_tex := _lazy_tex("fx_nest_aura_big")
		if aura_tex != null:
			var fw: float = aura_tex.get_width() / 4.0
			var frame := int(g.t * 10.0) % 4
			g.draw_texture_rect_region(aura_tex, Rect2(e.pos - Vector2.ONE * ar, Vector2.ONE * ar * 2.0), Rect2(frame * fw, 0, fw, aura_tex.get_height()), Color(1, 1, 1, 0.35))
		var ac := Color(0.9, 0.5, 1.6)
		for q in 4:
			g.draw_circle(e.pos, ar * (1.0 - q * 0.22), Color(ac.r, ac.g, ac.b, 0.035))
		for q in 2:
			var u: float = fmod(g.t * 0.5 + q * 0.5 + e.id * 0.17, 1.0)
			g.draw_arc(e.pos, ar * (1.0 - u * 0.85), 0.0, TAU, 40, Color(ac.r, ac.g, ac.b, 0.28 * (1.0 - u)), 1.5)
		var rot: float = g.t * 0.4 + e.id
		for q in 18:
			var a0: float = rot + q * TAU / 18.0
			g.draw_arc(e.pos, ar, a0, a0 + TAU / 36.0, 4, Color(ac.r, ac.g, ac.b, 0.55), 2.0)


const PARANOIA2_TINT := Color(1.35, 0.72, 1.25)

func _paranoia2_halo(e: Dictionary) -> void:
	# 以贴图中心为圆心（脚底锚点的贴图从脚往上长），半径按贴图半高
	var top: Vector2 = _enemy_top(e)
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8)
	var c: Vector2 = (top + foot) / 2.0
	var hh: float = maxf(e.r, (foot.y - top.y) / 2.0)
	for q in 3:
		var pts := PackedVector2Array()
		var rr: float = hh * (1.2 + 0.14 * q)
		for i in 33:
			var a: float = i * TAU / 32.0
			var w: float = 1.0 + 0.08 * sin(a * 5.0 + g.t * (3.0 + q) + q * 1.7)
			pts.append(c + Vector2(cos(a), sin(a) * 0.8) * rr * w)
		g.draw_polyline(pts, Color(1.7, 0.45, 1.5, 0.7 - 0.18 * q), 2.5 - 0.5 * q)


## ---- 主控身上的小怪控制（combat.gd「小怪控制」段，用户 9/29）：画在实体之上、预警轮廓之下
## 寒霜 g.cold：脚下冰霜圈 + 每层一枚绕身冰晶；冻结（寒霜满层时的 root）：半透明冰壳，快化时出裂纹；
## 束缚（其他 root）：三条暗紫触须从地面缠上来；侵蚀创口 g.wound：身上每层一道暗洋红伤口，缓慢滴落
const COLD_COL := Color(0.62, 0.9, 1.4)
const BIND_COL := Color(0.8, 0.45, 1.3)
const WOUND_COL := Color(1.1, 0.25, 0.55)
var root_max := 0.0              # 本次冻结 / 束缚的总时长（root_t 刚变大时记下，画倒计时用）
var root_prev := 0.0

func leader_frozen() -> bool:
	return g.root_t > 0.0 and g.cold >= int(Game.Bal.v("enemy/frost_max", 3.0))


## 神经损伤满格的眩晕：同样走 g.root_t（冲刺挣脱），刚满格时 nerve_lock > 0
func leader_nerve_stun() -> bool:
	return g.root_t > 0.0 and not leader_frozen() and g.get("nerve_lock") != null and float(g.nerve_lock) > 0.0


func root_label() -> String:
	return "冻结" if leader_frozen() else ("眩晕" if leader_nerve_stun() else "束缚")


func draw_leader_ailments() -> void:
	if g.root_t > root_prev + 0.01:
		root_max = g.root_t
	root_prev = g.root_t
	if g.state != Game.S.PLAY and g.state != Game.S.CHOICE:
		return
	var foot: Vector2 = g.ppos + Vector2(0, 16)
	var body: Vector2 = g.ppos + Vector2(0, -26)
	if g.cold > 0:
		var ca: float = clampf(g.cold_t / maxf(0.1, Game.Bal.v("enemy/frost_dur", 3.0)), 0.3, 1.0)
		g.draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
		g.draw_circle(Vector2.ZERO, 22.0 + 4.0 * g.cold, Color(COLD_COL.r, COLD_COL.g, COLD_COL.b, 0.10 * ca))
		g.draw_arc(Vector2.ZERO, 22.0 + 4.0 * g.cold, 0.0, TAU, 32, Color(COLD_COL.r, COLD_COL.g, COLD_COL.b, 0.5 * ca), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for q in g.cold:
			var a: float = g.t * 2.2 + q * TAU / maxf(1.0, g.cold)
			var cp: Vector2 = body + Vector2(cos(a) * 26.0, sin(a) * 9.0 + 8.0)
			UI.diamond(g, cp, 4.0, Color(0.85, 1.2, 1.6, 0.9 * ca), Color(0.2, 0.4, 0.7, 0.9))
	if g.root_t > 0.0:
		var k: float = clampf(g.root_t / maxf(0.05, root_max), 0.0, 1.0)
		if leader_nerve_stun():
			# 神经损伤眩晕：头顶三颗洋红星转圈 + 脑后一圈抖动的神经纹
			for q in 3:
				var a3: float = g.t * 6.0 + q * TAU / 3.0
				UI.diamond(g, body + Vector2(cos(a3) * 18.0, -40.0 + sin(a3) * 5.0), 4.0, Color(1.8, 0.7, 1.6), Color(0.2, 0.0, 0.2, 0.9))
			var zz := PackedVector2Array()
			for i in 13:
				var a4: float = i * TAU / 12.0
				zz.append(body + Vector2(cos(a4), sin(a4) * 0.5) * (26.0 + 3.0 * sin(g.t * 30.0 + i * 2.0)) + Vector2(0, -30))
			g.draw_polyline(zz, Color(1.6, 0.6, 1.5, 0.7), 1.5)
		elif leader_frozen():
			# 冰壳：六边形晶体罩住全身，剩余越少越透明、出裂纹
			var pts := PackedVector2Array()
			for i in 6:
				var a2: float = -PI / 2.0 + i * TAU / 6.0
				pts.append(body + Vector2(cos(a2) * 28.0, sin(a2) * 44.0))
			g.draw_colored_polygon(pts, Color(0.55, 0.85, 1.3, 0.22 + 0.18 * k))
			pts.append(pts[0])
			g.draw_polyline(pts, Color(0.9, 1.3, 1.8, 0.85), 2.0)
			g.draw_line(body + Vector2(-14, -30), body + Vector2(-4, -4), Color(1.6, 1.8, 2.0, 0.7), 2.0)
			if k < 0.6:
				g.draw_polyline(PackedVector2Array([body + Vector2(8, -34), body + Vector2(2, -12), body + Vector2(12, 4), body + Vector2(4, 22)]), Color(1.6, 1.8, 2.0, 0.9), 1.5)
		else:
			# 束缚：三条暗紫触须从脚下缠到腰
			for q in 3:
				var sx: float = -24.0 + q * 24.0
				var pts2 := PackedVector2Array()
				for i in 9:
					var u: float = i / 8.0
					pts2.append(foot + Vector2(sx * (1.0 - u) + sin(u * 7.0 + q * 2.0 + g.t * 3.0) * 7.0, -u * 46.0 * (0.4 + 0.6 * k)))
				g.draw_polyline(pts2, Color(0.25, 0.1, 0.35, 0.9), 5.0)
				g.draw_polyline(pts2, BIND_COL, 2.0)
		# 倒计时环（脚下）
		g.draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
		var rc: Color = COLD_COL if leader_frozen() else (Color(1.6, 0.6, 1.5) if leader_nerve_stun() else BIND_COL)
		g.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 6.0)
		g.draw_arc(Vector2.ZERO, 36.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, rc, 4.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var nmax: float = g.combat.nerve_max() if g.combat.has_method("nerve_max") else 100.0
	var nk: float = clampf(g.nerve / nmax, 0.0, 1.0)
	if nk > 0.05 and g.root_t <= 0.0:
		# 神经损伤累积：头部周围一圈洋红细电弧，量越高越多越快
		var n2: int = 1 + int(nk * 5.0)
		for q in n2:
			var a5: float = g.t * (3.0 + 5.0 * nk) + q * TAU / n2
			var p5: Vector2 = body + Vector2(cos(a5) * 20.0, -30.0 + sin(a5) * 7.0)
			var j: Vector2 = Vector2(sin(g.t * 40.0 + q) * 3.0, cos(g.t * 37.0 + q) * 3.0)
			g.draw_line(p5, p5 + Vector2(6, -4) + j, Color(1.8, 0.6, 1.6, 0.4 + 0.5 * nk), 1.5)
	if g.wound > 0:
		for q in g.wound:
			var wp: Vector2 = body + Vector2(-12 + (q % 2) * 20, -10 + q * 9)
			g.draw_line(wp + Vector2(-5, -3), wp + Vector2(5, 3), Color(0.2, 0.0, 0.1, 0.9), 4.0)
			g.draw_line(wp + Vector2(-5, -3), wp + Vector2(5, 3), WOUND_COL, 2.0)
			var dk: float = fmod(g.t * 0.9 + q * 0.37, 1.0)
			g.draw_circle(wp + Vector2(2, 4 + dk * 22.0), 1.8, Color(WOUND_COL.r, WOUND_COL.g, WOUND_COL.b, 1.0 - dk))


## 小怪词条外观（spawner.roll_affix）：甲壳 armor = 身前三块灰钢甲片；潮盾 shield = 青白泡壳 + 脚下细条（剩余护盾）
func _affix_fx(e: Dictionary, bpos: Vector2, top: Vector2) -> void:
	var af: String = e.get("affix", "")
	if af == "armor":
		var c: Vector2 = (bpos + top) / 2.0 if g.foot_anchor.has(e.tex) else e.pos
		for q in 3:
			var p: Vector2 = c + Vector2(-8 + q * 8, -4 + absf(q - 1) * 4)
			var pl := PackedVector2Array([p + Vector2(-4, -5), p + Vector2(4, -5), p + Vector2(5, 3), p + Vector2(0, 7), p + Vector2(-5, 3)])
			g.draw_colored_polygon(pl, Color(0.62, 0.66, 0.72, 0.95))
			pl.append(pl[0])
			g.draw_polyline(pl, Color(0.15, 0.17, 0.2, 1.0), 1.0)
			g.draw_line(p + Vector2(-3, -4), p + Vector2(3, -4), Color(1.4, 1.45, 1.5, 0.9), 1.0)
	elif af == "shield" and e.get("shield_hp", 0.0) > 0.0:
		var c2: Vector2 = (bpos + top) / 2.0 if g.foot_anchor.has(e.tex) else e.pos
		var rr: float = maxf(e.r + 6.0, (bpos.y - top.y) * 0.55)
		var wob: float = 1.0 + 0.04 * sin(g.t * 5.0 + e.id)
		g.draw_circle(c2, rr * wob, Color(0.5, 1.2, 1.4, 0.13))
		g.draw_arc(c2, rr * wob, 0.0, TAU, 32, Color(0.7, 1.5, 1.6, 0.7), 1.5)
		g.draw_arc(c2, rr * wob * 0.8, -2.4, -1.5, 8, Color(1.6, 2.0, 2.0, 0.8), 2.0)
		var mx: float = e.maxhp * Game.Bal.v("enemy/affix_shield", 0.30)
		var bw: float = maxf(20.0, e.r * 1.6)
		var by: Vector2 = bpos + Vector2(-bw / 2.0, 6)
		g.draw_rect(Rect2(by, Vector2(bw, 3)), Color(0, 0, 0, 0.6))
		g.draw_rect(Rect2(by, Vector2(bw * clampf(e.shield_hp / maxf(mx, 1.0), 0.0, 1.0), 3)), Color(0.7, 1.5, 1.6, 0.95))


## 部件心跳：约 1.3 拍 / 秒，倒计时最后 3 秒加快到 2.6 拍；返回 0–1 的尖峰
func _heartbeat(e: Dictionary) -> float:
	var rate: float = 1.3
	if e.get("count_max", 0.0) > 0.0 and float(e.get("count_end", 0.0)) - g.t < 3.0:
		rate = 2.6
	var ph: float = fmod(g.t * rate + e.id * 0.13, 1.0)
	return maxf(pow(maxf(0.0, 1.0 - ph * 5.0), 2.0), 0.6 * pow(maxf(0.0, 1.0 - absf(ph - 0.28) * 6.0), 2.0))


## 卡门换剑（sword_t 上升沿）：枪收剑出——白色竖闪 + 一圈银环 + 火花
func sword_swap_fx(b: Dictionary) -> void:
	g.fx.append({"kind": "ring", "pos": b.pos, "r": b.r * 2.2, "life": 0.4, "max": 0.4, "col": Color(1.6, 1.6, 1.8), "enemy": true})
	g.fx.append({"kind": "glint", "pos": b.pos + Vector2(b.fx * b.r * 0.9, -b.r * 0.6), "life": 0.35, "max": 0.35, "enemy": true})
	g.vfx.sparks(b.pos + Vector2(0, -b.r * 0.5), Vector2.UP, Color(1.8, 1.7, 1.4), 12, 260.0)


## 剑形态期间：身侧一把竖着的银色剑光（剩最后 1 秒闪烁提示要换回枪）
func _sword_glint(e: Dictionary, bpos: Vector2) -> void:
	var st: float = e.sword_t
	var a: float = 0.85 if st > 1.0 else 0.4 + 0.45 * absf(sin(g.t * 14.0))
	var side: float = 1.0 if e.fx >= 0.0 else -1.0
	var hilt: Vector2 = bpos + Vector2(side * e.r * 0.9, -e.r * 0.9)
	var tip: Vector2 = hilt + Vector2(side * 10.0, -e.r * 1.6)
	g.draw_line(hilt, tip, Color(0.1, 0.1, 0.15, a), 6.0)
	g.draw_line(hilt, tip, Color(1.7, 1.7, 1.9, a), 3.0)
	g.draw_line(hilt + Vector2(-7, 2), hilt + Vector2(7, -2), Color(1.6, 1.3, 0.6, a), 3.0)


## 偏执泡影「认知负担」光环（e.burden_r，主控在圈里 e.burden_in）：地面紫色符文圈缓慢旋转；主控在圈里时加亮、符文逆转
func _burden_ring(e: Dictionary) -> void:
	var r: float = float(e.burden_r)
	var inn: bool = e.get("burden_in", false)
	var c := Color(0.8, 0.45, 1.4)
	var a: float = 0.85 if inn else 0.45
	g.draw_set_transform(e.pos, 0.0, Vector2(1.0, ground_y()))
	g.draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, 0.06 if inn else 0.03))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 72, Color(c.r, c.g, c.b, 0.5 * a), 2.0)
	g.draw_arc(Vector2.ZERO, r - 14.0, 0.0, TAU, 72, Color(c.r, c.g, c.b, 0.3 * a), 1.0)
	var rot: float = g.t * (0.35 if inn else 0.15)
	for q in 16:
		var ang: float = rot + q * TAU / 16.0
		var p := Vector2.from_angle(ang) * (r - 7.0)
		var tn := Vector2.from_angle(ang + PI / 2.0)
		var nr := Vector2.from_angle(ang)
		# 一枚符文：竖划 + 按序号变化的横 / 斜划
		g.draw_line(p - nr * 5.0, p + nr * 5.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a), 1.5)
		match q % 3:
			0:
				g.draw_line(p - tn * 3.0, p + tn * 3.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a), 1.5)
			1:
				g.draw_line(p + nr * 5.0, p + nr * 1.0 + tn * 4.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a), 1.5)
			_:
				g.draw_line(p - nr * 5.0, p - nr * 1.0 - tn * 4.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 伊祖米克灯柱（e.lamps = [{pos, lit, prog}]，e.lamp_r）：未点亮 = 暗色石灯 + 脚下 40 半径的点亮进度环；
## 点亮 = 暖黄光圈（半径 lamp_r）+ 圈内「安全」标记（全场地波躲在这里），地波蓄力时光圈加亮脉动
func _izu_lamps(e: Dictionary) -> void:
	var lr: float = float(e.get("lamp_r", 120.0))
	var waving := false
	for w in g.warns:
		if not w.done and w.get("act", "") == "izu_wave":
			waving = true
	for lp in e.lamps:
		var p: Vector2 = lp.get("pos", Vector2.ZERO)
		var lit: bool = lp.get("lit", false)
		var pulse: float = 0.5 + 0.5 * sin(g.t * (10.0 if waving else 3.0))
		g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))
		if lit:
			g.draw_circle(Vector2.ZERO, lr, Color(1.0, 0.8, 0.4, (0.12 + 0.08 * pulse) if waving else 0.08))
			g.draw_arc(Vector2.ZERO, lr, 0.0, TAU, 56, Color(1.8, 1.4, 0.6, 0.6 + 0.35 * pulse if waving else 0.55), 3.0 if waving else 2.0)
		else:
			g.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.45, 0.35), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not lit and float(lp.get("prog", 0.0)) > 0.0:
			_ground_ring(p + Vector2(0, 2), 40.0, clampf(float(lp.prog), 0.0, 1.0), Color(1.6, 1.3, 0.6))
		# 石灯本体：方座 + 灯柱 + 灯龛（程序画）
		var base := Color(0.32, 0.36, 0.42) if not lit else Color(0.5, 0.48, 0.44)
		g.draw_rect(Rect2(p + Vector2(-11, -8), Vector2(22, 8)), Color(0.1, 0.11, 0.14))
		g.draw_rect(Rect2(p + Vector2(-10, -7), Vector2(20, 6)), base)
		g.draw_rect(Rect2(p + Vector2(-5, -34), Vector2(10, 27)), Color(0.1, 0.11, 0.14))
		g.draw_rect(Rect2(p + Vector2(-4, -33), Vector2(8, 25)), base)
		g.draw_rect(Rect2(p + Vector2(-9, -48), Vector2(18, 15)), Color(0.1, 0.11, 0.14))
		g.draw_rect(Rect2(p + Vector2(-8, -47), Vector2(16, 13)), Color(1.9, 1.5, 0.7) if lit else Color(0.18, 0.24, 0.3))
		g.draw_rect(Rect2(p + Vector2(-10, -51), Vector2(20, 4)), Color(0.1, 0.11, 0.14))
		if lit:
			g.draw_circle(p + Vector2(0, -40), 14.0 + 3.0 * pulse, Color(1.8, 1.4, 0.7, 0.25))
			UI.text(g, g.font, p + Vector2(-40, 26), "安全", 13 if not waving else 16, Color(1.0, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)


## 泡影茧（e.cocoon_t > 0；外壳 e.shell_hp / e.shell_max）：半透明紫色泡壳包住本体，按外壳损失比例出现裂纹，壳下方一条壳量条
func _cocoon_fx(e: Dictionary, top: Vector2, foot: Vector2) -> void:
	var c: Vector2 = (top + Vector2(0, 18) + foot) / 2.0
	var rr: float = maxf(e.r * 1.2, (foot.y - top.y) * 0.6)
	var dmg: float = 1.0 - clampf(float(e.get("shell_hp", 0.0)) / maxf(1.0, float(e.get("shell_max", 1.0))), 0.0, 1.0)
	var wob: float = 1.0 + 0.03 * sin(g.t * 3.0)
	g.draw_circle(c, rr * wob, Color(0.75, 0.4, 1.2, 0.22))
	g.draw_arc(c, rr * wob, 0.0, TAU, 48, Color(1.2, 0.7, 1.7, 0.85), 2.5)
	g.draw_arc(c, rr * 0.82, -2.5, -1.6, 10, Color(1.8, 1.5, 2.0, 0.8), 2.5)
	if e.flash > 0.0:
		# 外壳受伤速度有上限（每秒最多 1/4）：挨打时壳面白闪 +「抵抗」，提示打得再快也要等
		g.draw_arc(c, rr * wob, 0.0, TAU, 48, Color(2.0, 2.0, 2.0, 0.8), 4.0)
		UI.text(g, g.font, c + Vector2(-40, -rr - 8.0), "抵抗", 13, Color(1.0, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	# 裂纹：最多 6 道，从壳面往里，按外壳损失依次出现
	var n: int = int(ceil(dmg * 6.0))
	for q in n:
		var ang: float = q * 2.39 + e.id * 0.7
		var p0: Vector2 = c + Vector2.from_angle(ang) * rr
		var p1: Vector2 = c + Vector2.from_angle(ang + 0.25) * rr * 0.72
		var p2: Vector2 = c + Vector2.from_angle(ang - 0.1) * rr * 0.5
		g.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(0.05, 0.0, 0.1, 0.9), 3.0)
		g.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(1.8, 1.4, 2.0, 0.9), 1.2)
	var bw: float = rr * 1.4
	var by: Vector2 = c + Vector2(-bw / 2.0, rr + 10.0)
	g.draw_rect(Rect2(by, Vector2(bw, 5)), Color(0, 0, 0, 0.7))
	g.draw_rect(Rect2(by, Vector2(bw * (1.0 - dmg), 5)), Color(1.2, 0.7, 1.7))
	UI.text(g, g.font, by + Vector2(0, -4), "打破外壳", 12, Color(0.95, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, bw, 3)
## ---- 灯标（docs/49d §13.5 方案 C；逻辑在玩法系统，字段一律 get() 带缺省）：
## g.beacons 每项 {pos, lit, r 点燃光圈, clear_r 清痕半径, count_end / count_max 点燃进度, safe_end 安全区结束}
## 熄灭：暗灯塔 + 脚下暖色光圈呼吸（「站进来」）+ 点燃进度环；点燃瞬间：暖光爆扩到清痕半径；
## 亮着：灯室发光 + 旋转的灯塔光束 + 安全区虚线圈（剩余秒数），安全区结束后只留灯光
const BEACON_COL := Color(1.0, 0.78, 0.42)
var beacon_seen: Array = []     # [beacon, 上次 lit]

func draw_beacons() -> void:
	var bs = g.get("beacons")
	if not (bs is Array):
		return
	beacon_seen = beacon_seen.filter(func(s): return bs.any(func(b): return is_same(b, s[0])))
	var tx: Texture2D = _lazy_tex("prop_beacon")
	for b in bs:
		var pos: Vector2 = b.get("pos", Vector2.ZERO)
		var lit: bool = b.get("lit", false)
		var s: Array = []
		for s2 in beacon_seen:
			if is_same(s2[0], b):
				s = s2
		if s.is_empty():
			beacon_seen.append([b, lit])
		elif lit and not s[1]:
			s[1] = true
			beacon_burst(b)
		var r: float = float(b.get("r", 70.0))
		var pulse: float = 0.5 + 0.5 * sin(g.t * 3.0)
		g.draw_set_transform(pos, 0.0, Vector2(1.0, ground_y()))
		if not lit:
			g.draw_circle(Vector2.ZERO, r, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, 0.07 + 0.05 * pulse))
			for q in 20:
				var a0: float = g.t * 0.3 + q * TAU / 20.0
				g.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 40.0, 4, Color(BEACON_COL.r * 1.5, BEACON_COL.g * 1.5, BEACON_COL.b * 1.5, 0.55), 2.0)
		else:
			var left: float = float(b.get("safe_end", 0.0)) - g.t
			if left > 0.0:
				var cr: float = float(b.get("clear_r", 260.0))
				g.draw_circle(Vector2.ZERO, cr, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, 0.05))
				for q in 36:
					var a1: float = -g.t * 0.1 + q * TAU / 36.0
					g.draw_arc(Vector2.ZERO, cr, a1, a1 + TAU / 72.0, 4, Color(BEACON_COL.r * 1.4, BEACON_COL.g * 1.4, BEACON_COL.b * 1.4, 0.45 if left > 5.0 else 0.45 * absf(sin(g.t * 8.0))), 2.0)
			g.draw_circle(Vector2.ZERO, 46.0, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.4, 0.16 + 0.06 * pulse))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 点燃进度（暖色环；读 prog / need，离开光圈时进度缓慢回退也看得到）
		if not lit and float(b.get("prog", 0.0)) > 0.0:
			var k: float = clampf(float(b.prog) / maxf(0.1, float(b.get("need", 2.5))), 0.0, 1.0)   # prog 离开圈会缓慢回退、不清零
			_ground_ring(pos + Vector2(0, 4), 30.0, k, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.3))
		if tx != null:
			var sc: float = Game.PX / A.hires_of(tx)
			g.vfx.spr("prop_beacon", 2, 1 if lit else 0, pos + Vector2(0, 3.0 * Game.PX), sc, false, Color.WHITE, Vector2(0.5, 41.0 / 44.0))
		var lamp: Vector2 = pos + Vector2(0, -(41.0 - 10.0) * Game.PX)
		if lit:
			# 灯塔光束：从灯室往外旋转的一道扇形暖光 + 灯室光晕
			var ang: float = g.t * 1.4
			for side in [0.0, PI]:
				var d0 := Vector2.from_angle(ang + side - 0.12)
				var d1 := Vector2.from_angle(ang + side + 0.12)
				var L: float = 220.0
				g.draw_colored_polygon(PackedVector2Array([lamp, lamp + Vector2(d0.x, d0.y * 0.5) * L, lamp + Vector2(d1.x, d1.y * 0.5) * L]), Color(BEACON_COL.r * 1.5, BEACON_COL.g * 1.5, BEACON_COL.b * 1.2, 0.10))
			g.draw_circle(lamp, 16.0, Color(1.8, 1.5, 0.9, 0.25 + 0.1 * pulse))
			var lf: float = float(b.get("safe_end", 0.0)) - g.t
			if lf > 0.0:
				UI.text(g, g.font, pos + Vector2(-80, 30), "安全区 %d 秒" % ceili(lf), 12, Color(1.0, 0.85, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 160, 3)
		else:
			g.draw_circle(lamp, 6.0, Color(0.5, 0.6, 0.7, 0.2 + 0.15 * pulse))


## 点燃瞬间：暖白爆闪 + 一道光环扩到清痕半径 + 放射光束 + 火花
func beacon_burst(b: Dictionary) -> void:
	var pos: Vector2 = b.get("pos", Vector2.ZERO)
	g.fx.append({"kind": "beacon_burst", "pos": pos, "r": float(b.get("clear_r", 260.0)), "life": 0.9, "max": 0.9})
	g.vfx.sparks(pos + Vector2(0, -60), Vector2.ZERO, Color(1.8, 1.4, 0.7), 18, 300.0)
	_flash(Color(1.0, 0.85, 0.55), 0.3)


## 最后的骑士冰枪桩（e.stakes = [{pos, until}]，r 22）：竖立的冰晶长枪 + 脚下冰霜圈；快到期（< 2 秒）时闪烁
func _draw_stakes(e: Dictionary) -> void:
	for st in e.stakes:
		var left: float = float(st.until) - g.t
		if left <= 0.0:
			continue
		var a: float = 1.0 if left > 2.0 else 0.35 + 0.65 * absf(sin(g.t * 12.0))
		var p: Vector2 = st.pos
		g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))
		g.draw_circle(Vector2.ZERO, 22.0, Color(0.6, 0.85, 1.3, 0.14 * a))
		g.draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.8, 1.1, 1.6, 0.6 * a), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var top: Vector2 = p + Vector2(2, -70)
		g.draw_line(p + Vector2(0, 2), top, Color(0.1, 0.15, 0.25, 0.9 * a), 7.0)
		g.draw_line(p + Vector2(0, 2), top, Color(0.7, 0.95, 1.4, a), 4.0)
		g.draw_line(p + Vector2(-1, 0), top + Vector2(-1, 6), Color(1.6, 1.9, 2.2, 0.8 * a), 1.2)
		var tip := PackedVector2Array([top + Vector2(0, -18), top + Vector2(6, 0), top + Vector2(0, 6), top + Vector2(-6, 0)])
		g.draw_colored_polygon(tip, Color(0.85, 1.2, 1.7, a))
		tip.append(tip[0])
		g.draw_polyline(tip, Color(0.1, 0.15, 0.25, a), 1.5)
		for q in 3:
			var cp: Vector2 = p + Vector2(-10 + q * 10, -2 - (q % 2) * 5)
			UI.diamond(g, cp, 3.0, Color(0.8, 1.1, 1.6, 0.8 * a), Color(0.1, 0.15, 0.25, 0.8 * a))


## 冲锋预警撞桩端盖：按当前 w.ang / w.len 和 e.stakes 求交（线宽按 e.r + 22），在第一根会撞上的桩处画「破」字端盖
func _stake_cap(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var a: Vector2 = w.pos
	var d: Vector2 = Vector2.from_angle(w.ang)
	var b: Vector2 = a + d * w.len
	var best := -1.0
	var hit := Vector2.ZERO
	for st in e.get("stakes", []):
		if float(st.until) <= g.t:
			continue
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(st.pos, a, b)
		if cp.distance_to(st.pos) < e.r + 22.0:
			var along: float = (cp - a).dot(d)
			if best < 0.0 or along < best:
				best = along
				hit = st.pos
	if best < 0.0:
		return
	var c: Vector2 = a + d * best
	var pk: float = 0.5 + 0.5 * sin(g.t * 10.0)
	g.draw_line(c - d.orthogonal() * (w.wid + 10.0), c + d.orthogonal() * (w.wid + 10.0), Color(0, 0, 0, 0.7), 7.0)
	g.draw_line(c - d.orthogonal() * (w.wid + 10.0), c + d.orthogonal() * (w.wid + 10.0), Color(1.8, 1.5, 0.6, 0.8 + 0.2 * pk), 3.5)
	g.draw_circle(c + Vector2(0, -26), 12.0, Color(0.05, 0.05, 0.08, 0.85))
	g.draw_arc(c + Vector2(0, -26), 12.0, 0.0, TAU, 20, Color(1.8, 1.5, 0.6, 0.9), 1.5)
	UI.text(g, g.font, c + Vector2(-12, -20), "破", 14, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 24, 2)


## 长枪脱手（knight_boss 撞桩后的 5 秒大破绽上升沿）：一杆长枪从骑士手里旋转飞出，抛物线落到身后，落地冰屑
func spear_fly_fx(b: Dictionary) -> void:
	var dir: float = -1.0 if b.get("fx", 1.0) >= 0.0 else 1.0
	g.fx.append({"kind": "spear_fly", "pos": b.pos + Vector2(0, -b.r), "to": b.pos + Vector2(dir * 150.0, 20.0), "life": 0.8, "max": 0.8, "enemy": true})


const ENTITY_MARGIN := 180.0   # 大体型 Boss / 精英贴图从脚底往上长，外扩够画出半身
const TELL_MARGIN := 420.0
const GEM_MERGE_N := 120        # 场上结晶超过这个数才合并远处的小结晶
const GEM_CELL := 26.0


## 当前镜头看到的世界矩形（外扩 margin）：屏幕外剔除用
func view_rect(margin: float) -> Rect2:
	var inv: Transform2D = g.get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = g.get_viewport_rect().size
	return (inv * Rect2(Vector2.ZERO, vs)).grow(margin)


## 按需加载的敌人贴图（不在 game.gd 预载表里的新帧条）：连同白色剪影一起放进 g.tex
func _lazy_tex(n: String) -> Texture2D:
	if not g.tex.has(n):
		g.tex[n] = A.tex(n)
		if g.tex[n] != null:
			g.tex[n + "_white"] = A.white_of(g.tex[n])
	return g.tex[n]


## 泪滴显示与实际机制一致：中立泪是可踩入的压制区；遗留敌对泪仍显示伤害圈。
## 连接只认该枚泪的有效 owner，不根据场上所有 Boss 猜测归属。
func tear_zone_info(e: Dictionary) -> Dictionary:
	var neutral: bool = e.get("friendly", false)
	var blocked: bool = neutral and g.ishar.tear_blocked(e)
	var owner = e.get("owner")
	if not owner is Dictionary or owner.get("type", "") != "ishar" or owner.get("dead", true) or owner.get("phase", 0) != 1:
		owner = {}
	return {
		"r": Bal.v("boss/ishar_tear_block_radius", 32.0) if neutral else e.r + 14.0,
		"ground_scale": 1.0 if neutral else ground_y(),
		"blocked": blocked, "owner": owner,
		"col": (Color(0.25, 1.0, 0.85) if blocked else Color(0.55, 0.7, 1.0)) if neutral else ENEMY_TELL,
		"label": ("充能已压制" if blocked else "靠近压制充能") if neutral else ""
	}


func _tear_zone(e: Dictionary) -> void:
	var info := tear_zone_info(e)
	var r: float = info.r
	var c: Color = info.col
	var pulse: float = 0.5 + 0.5 * sin(g.t * 4.0 + e.id)
	g.draw_set_transform(e.pos, 0.0, Vector2(1.0, info.ground_scale))
	g.draw_circle(Vector2.ZERO, r, Color(c, 0.12 + 0.06 * pulse))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 4.0)
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(c, 0.6 + 0.3 * pulse), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if info.label != "":
		UI.text(g, g.font, e.pos + Vector2(-70, -e.r - 20), info.label, 11, c, HORIZONTAL_ALIGNMENT_CENTER, 140, 2)
	var owner: Dictionary = info.owner
	if not owner.is_empty() and not info.blocked:
		var d: Vector2 = owner.pos - e.pos
		for q in 5:
			var u: float = fmod(g.t * 0.6 + q / 5.0 + e.id * 0.13, 1.0)
			g.draw_circle(e.pos + d * u, 2.5, Color(0.6, 1.6, 1.4, 0.7 * sin(u * PI)))



## Boss 身上的状态（docs/48 P1）：
## 接潮组假死 → 身边一圈倒计时环（假死期间每秒回 10% 血，回满苏醒：环 = 血量），连一条虚线到另一体，提示「同时击倒」；
## 圣徒装填 → 金色装填环 + 三颗弹药格依次点亮，「装填中 · 攻击打断」；装填被打断 / 其他晕眩 → 头顶三颗转圈的星 + 剩余秒数
func _boss_state(e: Dictionary) -> void:
	var top: Vector2 = _enemy_top(e) + Vector2(0, -18.0)
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8) if g.foot_anchor.has(e.tex) else e.pos
	if e.get("cocoon_t", 0.0) > 0.0:
		_cocoon_fx(e, top, foot)
		return
	if e.get("coma", false):
		var k: float = clampf(e.hp / e.maxhp, 0.0, 1.0)
		var rr: float = e.r + 12.0
		var tc := Color(0.5, 1.5, 1.4)
		var left: float = (e.maxhp - e.hp) / maxf(e.maxhp * 0.1, 0.001)
		if e.get("count_max", 0.0) > 0.0:
			left = maxf(0.0, float(e.count_end) - g.t)   # 假死赛跑（combat：count_end / count_max），环由 _count_ring 画
		else:
			_ground_ring(foot, rr, k, tc)
		UI.text(g, g.font, top + Vector2(-120, -4), "假死 %d 秒 · 同时击倒另一体" % ceili(left), 13, tc, HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		var p = e.get("partner")
		if p != null and not p.dead:
			var d: Vector2 = p.pos - e.pos
			var L: float = d.length()
			var dn: Vector2 = d / maxf(L, 1.0)
			var s: float = fmod(g.t * 40.0, 16.0)
			while s < L:
				g.draw_line(e.pos + dn * s, e.pos + dn * minf(s + 8.0, L), Color(tc.r, tc.g, tc.b, 0.45), 2.0)
				s += 16.0
		return
	if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
		var gc := Color(1.6, 1.2, 0.5)
		var k: float = clampf(1.0 - e.channel / 2.0, 0.0, 1.0)
		if e.get("count_max", 0.0) > 0.0:
			k = clampf(1.0 - (float(e.count_end) - g.t) / float(e.count_max), 0.0, 1.0)   # 通用倒计时环已画在脚下
		else:
			_ground_ring(foot, e.r + 10.0, k, gc)
		# 读条光圈：「快打它」——身周金色光圈呼吸 + 向内收的细环
		var cc: Vector2 = (top + Vector2(0, 18) + foot) / 2.0
		var hh: float = maxf(e.r, (foot.y - top.y - 18.0) / 2.0) * 1.15
		var br: float = 0.5 + 0.5 * sin(g.t * 9.0)
		g.draw_circle(cc, hh, Color(1.6, 1.2, 0.4, 0.07 + 0.06 * br))
		g.draw_arc(cc, hh, 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.55 + 0.35 * br), 2.5)
		var u: float = fmod(g.t * 1.6, 1.0)
		g.draw_arc(cc, hh * (1.6 - 0.6 * u), 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.5 * u), 1.5)
		for q in 3:
			var on: bool = k >= (q + 1) / 3.0
			var pp: Vector2 = top + Vector2(-14 + q * 14, 10)
			g.draw_rect(Rect2(pp - Vector2(3, 5), Vector2(6, 10)), gc if on else Color(0.2, 0.15, 0.1, 0.8))
			g.draw_rect(Rect2(pp - Vector2(3, 5), Vector2(6, 10)), Color(0, 0, 0, 0.7), false, 1.0)
		UI.text(g, g.font, top + Vector2(-120, -6), "装填中 · 攻击打断", 13, gc, HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		return
	var brk: float = e.get("break_t", 0.0)
	if e.stun > 0.05 or (brk > 0.0 and e.has("ammo")):
		for q in 3:
			var a: float = g.t * 5.0 + q * TAU / 3.0
			var sp: Vector2 = top + Vector2(cos(a) * 18.0, sin(a) * 5.0)
			UI.diamond(g, sp, 4.0, Color(1.8, 1.6, 0.6), Color(0, 0, 0, 0.6))
		if e.has("ammo") and brk > 0.0:
			UI.text(g, g.font, top + Vector2(-120, -12), "装填被打断 · 破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif e.type in ["iberia", "carmen"] and e.get("ammo", 1) == 0:
			UI.text(g, g.font, top + Vector2(-120, -12), "装填被打断 · 晕眩 %.1f" % e.stun, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)


## 地面形状的纵向压缩：和判定一致（combat.gd 的 GROUND_Y，Boss与怪物「画即判」；还没有这个常量时按正圆 1.0）
var _gy := -1.0
func ground_y() -> float:
	if _gy < 0.0:
		_gy = float(load("res://scripts/run/combat.gd").get_script_constant_map().get("GROUND_Y", 1.0))
	return _gy


## V7 预警帧条（docs/13 §V7，docs/48 ⑥ 接入闲置素材）：圆形涟漪 64px（radius_px 30）/ 直线流动水纹 16px 平铺 / 终点漩涡 32px
var _warn_tex := {}
func _wtex(n: String) -> Texture2D:
	if not _warn_tex.has(n):
		_warn_tex[n] = A.tex(n)
	return _warn_tex[n]


func _tell_line(a: Vector2, b: Vector2, half: float, k: float, c: Color) -> void:
	var d: Vector2 = b - a
	var n: Vector2 = d.normalized().orthogonal() * half
	g.draw_colored_polygon(PackedVector2Array([a + n, a + d * k + n, a + d * k - n, a - n]), Color(c.r, c.g, c.b, 0.22 + 0.12 * k))
	var lt: Texture2D = _wtex("fx_warn_line")
	if lt != null:
		# 沿线平铺流动水纹（16px 一段，按线宽缩放），终点放漩涡
		var fr: int = int(g.t * 12.0) % 4
		var seg: float = 16.0 * (half * 2.0 / 16.0)
		var L: float = d.length()
		var ang: float = d.angle()
		var x := 0.0
		while x < L - 1.0:
			var w: float = minf(seg, L - x)
			g.draw_set_transform(a + d.normalized() * x, ang, Vector2(half * 2.0 / 16.0, half * 2.0 / 16.0))
			g.draw_texture_rect_region(lt, Rect2(0, -8, w / (half * 2.0 / 16.0), 16), Rect2(16 * fr, 0, w / (half * 2.0 / 16.0), 16), Color(c.r, c.g, c.b, 0.55))
			x += seg
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var et: Texture2D = _wtex("fx_warn_end")
		if et != null:
			var es: float = half * 2.4 / 32.0 * 2.0
			g.draw_set_transform(b, 0.0, Vector2(es, es * ground_y()))
			g.draw_texture_rect_region(et, Rect2(-16, -16, 32, 32), Rect2(32 * fr, 0, 32, 32), Color(c.r, c.g, c.b, 0.8))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(0, 0, 0, 0.55), 4.0)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, 0.85), 2.0)
	g.draw_line(a, b, Color(1, 1, 1, 0.5 + 0.4 * k), 1.0)


func _tell_circle(p: Vector2, r: float, k: float, c: Color) -> void:
	var pulse: float = 0.5 + 0.5 * sin(g.t * 18.0)
	g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致
	g.draw_circle(Vector2.ZERO, r * k, Color(c.r, c.g, c.b, 0.18 + 0.1 * k))
	var rt: Texture2D = _wtex("fx_warn_ring")
	if rt != null:
		# V7 涟漪：从外向内收缩的水纹，按半径缩放（radius_px 30）
		var rs: float = r / 30.0
		g.draw_set_transform(p, 0.0, Vector2(rs, rs * ground_y()))
		g.draw_texture_rect_region(rt, Rect2(-32, -32, 64, 64), Rect2(64 * (int(g.t * 12.0) % 4), 0, 64, 64), Color(c.r, c.g, c.b, 0.5))
		g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 5.0)
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.75 + 0.25 * pulse * k), 3.0)
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55 + 0.4 * k), 1.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Boss 招式预警的轮廓（填色仍在地面层，boss_ai._draw_warns）：按 docs/38 §8.11 收敛成五种样式，
## 轮廓一律「白芯 + 深色描边」（颜色只在填充里区分 Boss 主题）；追踪中虚线，锁定（w.track）后实线并白闪。
## ① 落点圈：固定落点 circle —— 地面椭圆外圈 + 内圈随结算时间长满，落地前一瞬白闪
## ② 直线：line —— 边框 + 终点端盖；冲锋 / 突刺沿线画方向箭头；骑士撞桩端盖写「破」
## ③ 扇形：cone —— 两条边 + 弧，扇面内一道随时间扫过的弧
## ④ 缺口环：follow 的 circle 或带 gap_ang 的环 —— 环 + 缺口处金色「出口」标记
## ⑤ 全场·必须冲刺：must_dash —— 白色双描边 + 冲刺图标（屏幕级提示在 hud.draw_field_wave）
const WARN_CORE := Color(1, 1, 1)
const WARN_EDGE := Color(0.02, 0.02, 0.05)

func _warn_dash_arc(r: float, a0: float, a1: float, col: Color, wdt: float) -> void:
	var seg: float = 0.22
	var a: float = a0
	while a < a1:
		g.draw_arc(Vector2.ZERO, r, a, minf(a + seg * 0.55, a1), 4, col, wdt)
		a += seg


func draw_warn_outlines() -> void:
	for w in g.warns:
		if w.done:
			continue
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var tr: float = float(w.get("track", 0.0))
		var tracking: bool = tr > 0.0 and w.t < tr
		var lk: float = w.t - tr
		var lock_flash: float = (1.0 - lk / 0.15) if tr > 0.0 and lk >= 0.0 and lk < 0.15 else 0.0
		var core := Color(WARN_CORE.r, WARN_CORE.g, WARN_CORE.b, 0.7 + 0.3 * k)
		var edge := Color(WARN_EDGE.r, WARN_EDGE.g, WARN_EDGE.b, 0.7)
		var gy: float = ground_y()
		match w.shape:
			"circle":
				# 样式按 Boss与怪物 在 _warn 里填的 w.style（c46c668）：0 预告 / 1 落点圈 / 4 缺口环 / 5 必须冲刺；
				# follow 只表示圈跟着施法者走，不等于环（钻地咬击、踏地、触须爆发、寒冰领域都是 follow 的落点圈）
				var st: int = int(w.get("style", 1))
				var ring: bool = st == 4
				var must: bool = st == 5 or w.get("must_dash", false)
				if st == 0:
					# 预告（不伤人，如投嗣育母生成点）：很淡的虚线细圈，不填内圈、不白闪
					g.draw_set_transform(w.pos, 0.0, Vector2(1.0, gy))
					_warn_dash_arc(w.r, 0.0, TAU, Color(1, 1, 1, 0.3), 1.0)
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					continue
				g.draw_set_transform(w.pos, 0.0, Vector2(1.0, gy))
				if tracking:
					_warn_dash_arc(w.r, 0.0, TAU, edge, 5.0)
					_warn_dash_arc(w.r, 0.0, TAU, core, 2.0)
				else:
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, edge, 5.0)
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, core, 2.0)
				if must:
					# ⑤ 必须冲刺：白色双描边
					var pk: float = 0.5 + 0.5 * sin(g.t * 12.0)
					g.draw_arc(Vector2.ZERO, w.r + 7.0, 0.0, TAU, 56, Color(1, 1, 1, 0.55 + 0.35 * pk), 2.0)
					g.draw_arc(Vector2.ZERO, w.r - 5.0, 0.0, TAU, 56, Color(1, 1, 1, 0.45 + 0.3 * pk), 1.5)
				elif not ring:
					# ① 落点圈：内圈随结算时间长满，最后 0.12 秒整圈白闪
					g.draw_arc(Vector2.ZERO, maxf(2.0, w.r * k), 0.0, TAU, 48, Color(1, 1, 1, 0.35 + 0.35 * k), 1.5)
					if w.dur - w.t < 0.12:
						g.draw_circle(Vector2.ZERO, w.r, Color(1, 1, 1, 0.35))
				if lock_flash > 0.0:
					g.draw_circle(Vector2.ZERO, w.r, Color(1, 1, 1, 0.4 * lock_flash))
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if must:
					var ic: Vector2 = w.pos + Vector2(0, -w.r * gy - 22.0)
					for q in 3:
						var ox: float = -9.0 + q * 7.0
						g.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(0, 0, 0, 0.7), 5.0)
						g.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(1, 1, 1, 0.95), 2.5)
			"line":
				g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				if tracking:
					var xx := 0.0
					while xx < w.len:
						var x2: float = minf(xx + 14.0, w.len)
						for sy in [-w.wid, w.wid]:
							g.draw_line(Vector2(xx, sy), Vector2(x2, sy), edge, 5.0)
							g.draw_line(Vector2(xx, sy), Vector2(x2, sy), core, 2.0)
						xx += 24.0
				else:
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), edge, false, 5.0)
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), core, false, 2.0)
					if lock_flash > 0.0:
						g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), Color(1, 1, 1, 0.5 * lock_flash), true)
				# 终点端盖
				g.draw_line(Vector2(w.len, -w.wid - 6.0), Vector2(w.len, w.wid + 6.0), edge, 7.0)
				g.draw_line(Vector2(w.len, -w.wid - 6.0), Vector2(w.len, w.wid + 6.0), core, 3.0)
				# 冲锋 / 突刺：沿线的方向箭头，随时间向前流动
				if w.get("act", "") in ["dash", "stab"]:
					var hw: float = minf(w.wid * 0.6, 14.0)
					var off: float = fmod(g.t * 160.0, 70.0)
					var ax: float = 30.0 + off
					while ax < w.len - 20.0:
						g.draw_polyline(PackedVector2Array([Vector2(ax - hw, -hw), Vector2(ax, 0), Vector2(ax - hw, hw)]), edge, 5.0)
						g.draw_polyline(PackedVector2Array([Vector2(ax - hw, -hw), Vector2(ax, 0), Vector2(ax - hw, hw)]), Color(1, 1, 1, 0.55 + 0.35 * k), 2.0)
						ax += 70.0
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if w.get("stake_hit", false) or (w.get("owner") is Dictionary and w.owner.get("stakes", []) is Array and not w.owner.get("stakes", []).is_empty()):
					_stake_cap(w)
			"cone":
				var pts := PackedVector2Array([w.pos])
				for q in 17:
					pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * q / 16.0) * w.r)
				pts.append(w.pos)
				if tracking:
					for q in pts.size() - 1:
						if q % 2 == 0:
							g.draw_line(pts[q], pts[q + 1], edge, 5.0)
							g.draw_line(pts[q], pts[q + 1], core, 2.0)
				else:
					g.draw_polyline(pts, edge, 5.0)
					g.draw_polyline(pts, core, 2.0)
				# 扇面内一道随时间向外推的弧
				g.draw_arc(w.pos, maxf(4.0, w.r * k), w.ang - w.half, w.ang + w.half, 20, Color(1, 1, 1, 0.3 + 0.4 * k), 1.5)
				if lock_flash > 0.0:
					g.draw_colored_polygon(pts, Color(1, 1, 1, 0.3 * lock_flash))
		# ④ 缺口环的出口：缺口两侧金色短线 + 中间「出口」小牌（缺口方向与真实弹道同一角度，不做地面压缩）
		if w.has("gap_ang"):
			var safe_col := Color(1.0, 0.85, 0.35, 0.9)
			for side in [-1.0, 1.0]:
				var v := Vector2.from_angle(float(w.gap_ang) + side * float(w.gap_half))
				g.draw_line(w.pos + v * 90.0, w.pos + v * 190.0, Color(0, 0, 0, 0.7), 5.0)
				g.draw_line(w.pos + v * 90.0, w.pos + v * 190.0, safe_col, 2.0)
			var mp: Vector2 = w.pos + Vector2.from_angle(float(w.gap_ang)) * 150.0
			g.draw_rect(Rect2(mp + Vector2(-20, -11), Vector2(40, 18)), Color(0.05, 0.04, 0.02, 0.85))
			UI.text(g, g.font, mp + Vector2(-20, 3), "出口", 12, safe_col, HORIZONTAL_ALIGNMENT_CENTER, 40)


func draw_zone() -> void:
	if g.zone_state == 0:
		return
	var vs := g.get_viewport_rect().size
	var far := vs.length() + 200.0
	var seg := 96
	var outer := g.zone_r + far + g.ppos.distance_to(g.zone_c)
	var pulse := 0.5 + 0.5 * sin(g.t * 2.5)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := g.zone_c + Vector2.from_angle(a0) * g.zone_r
		var p1 := g.zone_c + Vector2.from_angle(a1) * g.zone_r
		# 只画视野附近的部分
		if p0.distance_to(g.ppos) > far + 400.0 and p1.distance_to(g.ppos) > far + 400.0 and g.ppos.distance_to(g.zone_c) < g.zone_r:
			continue
		var q0 := g.zone_c + Vector2.from_angle(a0) * outer
		var q1 := g.zone_c + Vector2.from_angle(a1) * outer
		g.draw_colored_polygon(PackedVector2Array([p0, p1, q1, q0]), Color(0.16, 0.03, 0.22, 0.55))
	draw_zone_band(pulse)
	# 下一圈预告（虚线）
	if g.zone_state == 1:
		var n2 := 72
		for i in n2:
			if i % 2 == 0:
				continue
			var a0 := TAU * i / n2
			var a1 := TAU * (i + 1) / n2
			g.draw_line(g.zone_next_c + Vector2.from_angle(a0) * g.zone_next_r, g.zone_next_c + Vector2.from_angle(a1) * g.zone_next_r, Color(2.2, 2.2, 2.4, 0.6), 2.0)


## 黑潮边缘的溟痕带（2026-09-27 用户要求：原来是沿圈摆一个个分开的溟痕贴图 → 连成一圈 → 再改成溟痕本身的样子）：
## 沿圆周连续的一条带，内沿（安全区一侧）是起伏的亮紫潮头线，往外由溟痕紫渐隐到圈外暗色；带上有缓慢漂移的暗色溟痕团，
## 表现流动。只画视野附近的弧段（段长约 22 像素，封顶 420 段），手机 / 网页每帧几十到一两百个四边形。只改画面，判定仍是 zone_r
const ZB_SEG := 22.0
func draw_zone_band(pulse: float) -> void:
	var r: float = g.zone_r
	var c: Vector2 = g.zone_c
	var vc: Vector2 = g.cam.position
	var view: float = g.get_viewport_rect().size.length() * 0.6 + 80.0
	var n: int = clampi(int(TAU * r / ZB_SEG), 64, 420)
	var t: float = g.t
	var crest := PackedVector2Array()
	var crests: Array = []           # 内沿线段先收集，等溟痕贴图铺完再画在最上面
	var prev_in := Vector2.ZERO
	var prev_mid := Vector2.ZERO
	var prev_out := Vector2.ZERO
	var prev_vis := false
	# 溟痕配色（2026-09-27 用户要求：圈边要是溟痕本身的样子——深色黏液 + 青黑纹理，和地上的溟痕一致；不再用粉紫潮线）
	var c_in := Color(0.06, 0.03, 0.1, 0.92)
	var c_mid := Color(0.05, 0.03, 0.08, 0.8)
	var c_out := Color(0.05, 0.02, 0.08, 0.0)
	for i in n + 1:
		var a: float = TAU * i / n
		var d := Vector2.from_angle(a)
		# 内沿潮头：两层正弦叠加并随时间流动；外沿更慢、更宽
		var rin: float = r - 6.0 + 5.0 * sin(a * 23.0 + t * 1.3) + 1.5 * sin(a * 57.0 - t * 2.1)
		var rmid: float = r + 12.0 + 4.0 * sin(a * 31.0 - t * 0.9)
		var rout: float = r + 44.0 + 10.0 * sin(a * 13.0 + t * 0.6) + 5.0 * sin(a * 41.0 - t * 1.4)
		var pin: Vector2 = c + d * rin
		var pmid: Vector2 = c + d * rmid
		var pout: Vector2 = c + d * rout
		var vis: bool = pin.distance_to(vc) < view
		if i > 0 and (vis or prev_vis):
			g.draw_polygon(PackedVector2Array([prev_in, pin, pmid, prev_mid]), PackedColorArray([c_in, c_in, c_mid, c_mid]))
			g.draw_polygon(PackedVector2Array([prev_mid, pmid, pout, prev_out]), PackedColorArray([c_mid, c_mid, c_out, c_out]))
			if crest.is_empty():
				crest.append(prev_in)
			crest.append(pin)
		elif crest.size() > 1:
			crests.append(crest)
			crest = PackedVector2Array()
		prev_in = pin
		prev_mid = pmid
		prev_out = pout
		prev_vis = vis
	if crest.size() > 1:
		crests.append(crest)
	# 溟痕贴图沿圈边密铺：每 26 像素弧长一块（贴图约 60 像素宽，互相叠一半以上，连成一整条），两帧脉动和地上的溟痕一致；
	# 大小、左右翻转、前后位置按序号取固定的伪随机，看不出重复；只画视野内的块（后期同屏元素多，一屏约五六十块）
	var mt: Texture2D = g.tex.get("terrain_mire")
	if mt != null:
		var fw: int = mt.get_width() / 2
		var nb: int = clampi(int(TAU * r / 26.0), 24, 900)
		for j in nb:
			var a2: float = TAU * (j + 0.5 * sin(j * 12.9898)) / nb
			var d2 := Vector2.from_angle(a2)
			var bp: Vector2 = c + d2 * (r + 12.0 + 7.0 * sin(j * 4.1))
			if bp.distance_to(vc) > view:
				continue
			var bs: float = 56.0 * (0.85 + 0.25 * (0.5 + 0.5 * sin(j * 7.3)))
			var fl: bool = int(j * 2654435761) % 2 == 0
			var sz := Vector2(bs, bs)
			var fr: int = (int(t * 2.0) + j) % 2
			if fl:
				g.draw_set_transform(bp, 0.0, Vector2(-1, 1))
				g.draw_texture_rect_region(mt, Rect2(-sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95))
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				g.draw_texture_rect_region(mt, Rect2(bp - sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95))
	for cr in crests:
		_zone_crest(cr, pulse)


## 溟痕内沿：暗色描边垫底 + 溟痕裂纹的青色细线（安全区边界一眼看清，颜色取自溟痕贴图的青色裂纹）
func _zone_crest(pts: PackedVector2Array, pulse: float) -> void:
	g.draw_polyline(pts, Color(0.02, 0.0, 0.04, 0.75), 5.0)
	g.draw_polyline(pts, Color(0.35, 0.95, 0.95, 0.55 + 0.25 * pulse), 2.0)


## 护盾：淡蓝色六边形能量泡，层数越多越厚
func draw_shield() -> void:
	if g.shield <= 0:
		return
	var c := g.ppos + Vector2(0, -26)
	var pop := 1.0 + 0.3 * (g.shield_pop / 0.4)
	var r := (38.0 + 2.0 * sin(g.t * 3.0)) * pop
	var fl := g.shield_flash / 0.3
	g.draw_circle(c, r, Color(0.35, 0.7, 1.0, 0.10 + 0.05 * g.shield + 0.3 * fl))
	# 外圈 + 内圈（多层时叠加）
	for q in g.shield:
		g.draw_arc(c, r - q * 4.0, 0.0, TAU, 48, Color(0.8, 1.6, 2.4, 0.55 - q * 0.1 + 0.4 * fl), 2.0)
	# 六边形网格高光
	for q in 6:
		var an := TAU * q / 6.0 + g.t * 0.4
		var p0 := c + Vector2.from_angle(an) * r * 0.62
		var p1 := c + Vector2.from_angle(an + TAU / 6.0) * r * 0.62
		g.draw_line(p0, p1, Color(0.9, 1.6, 2.2, 0.22), 1.0)
		g.draw_line(p0, c + Vector2.from_angle(an) * r, Color(0.9, 1.6, 2.2, 0.15), 1.0)
	# 流光
	var sw := fmod(g.t * 1.2, 1.0)
	g.draw_arc(c, r, -PI * 0.9 + sw * TAU, -PI * 0.6 + sw * TAU, 12, Color(2.4, 2.8, 3.0, 0.8), 3.0)
	g.draw_circle(c + Vector2(-r * 0.4, -r * 0.45), 4.0, Color(2.4, 2.6, 3.0, 0.5))


## 用 Sprite2D 的动画状态手动绘制水月，以便和怪物、海草按前后排序
## 角色手感：起步拉伸、停步压扁、转身缩身、奔跑起伏与前倾、挥伞前倾、受击后坐、待机呼吸；脚下扬尘
func update_player_feel(dt: float) -> void:
	if dt <= 0.0:
		return
	var target_sq := Vector2.ONE
	var target_lean := 0.0
	var alive: bool = g.state != Game.S.DEAD
	if g.state == Game.S.OPENING:
		g.intro_screen.update_opening(dt)
		return
	# 转身
	if g.facing != p_last_facing:
		p_turn = 1.0
		p_last_facing = g.facing
	p_turn = maxf(0.0, p_turn - dt * 9.0)
	# 起步 / 停步冲量
	if g.moving and not p_was_moving:
		g.p_sq = Vector2(0.84, 1.16)
		p_dust_t = 0.0
	elif not g.moving and p_was_moving:
		g.p_sq = Vector2(1.18, 0.84)
		feet_dust(4, 90.0)
	p_was_moving = g.moving
	if alive and g.moving and g.pstun <= 0.0:
		var ph: float = absf(sin(g.walk_t))
		target_sq = Vector2(1.0 + 0.05 * ph, 1.0 - 0.06 * ph)
		target_lean = 0.09 * g.facing
		p_dust_t -= dt
		if p_dust_t <= 0.0:
			p_dust_t = 0.2
			feet_dust(2, 60.0)
	elif alive:
		target_sq = Vector2(1.0 - 0.012 * sin(g.t * 2.2), 1.0 + 0.022 * sin(g.t * 2.2))
	# 挥伞：出手瞬间前倾 + 拉伸，随后回弹
	if g.swing_face > 0.0 and p_swing_prev <= 0.0:
		g.p_sq = Vector2(1.12, 0.92)
	if g.swing_face > 0.0:
		target_lean += 0.13 * g.facing * (g.swing_face / 0.25)
	p_swing_prev = g.swing_face
	# 受击：向后坐一下，微微后仰
	if g.hurt_flash > 0.12 and p_hurt_prev <= 0.12:
		var away := Vector2(-g.facing, 0.0)
		var nn := g.enemies_sys.nearest(1, 160.0)
		if not nn.is_empty():
			away = (g.ppos - nn[0].pos).normalized()
		g.p_off = away * 9.0
		g.p_sq = Vector2(1.1, 0.9)
	p_hurt_prev = g.hurt_flash
	if g.hurt_flash > 0.05:
		target_lean -= 0.12 * g.facing
	# 定身：轻微颤抖
	if g.pstun > 0.0:
		g.p_off.x += sin(g.t * 60.0) * 1.2
	var k := 1.0 - exp(-dt * 16.0)
	g.p_sq = g.p_sq.lerp(target_sq, k)
	g.p_sq.x *= 1.0 - 0.3 * p_turn
	g.p_lean = lerpf(g.p_lean, target_lean, k)
	g.p_off = g.p_off.lerp(Vector2.ZERO, 1.0 - exp(-dt * 12.0))


func feet_dust(n: int, spd: float) -> void:
	for k in n:
		var v := Vector2(-g.facing * randf_range(20.0, spd), -randf_range(10.0, 40.0))
		g.fx.append({"kind": "spark", "pos": g.ppos + Vector2(randf_range(-6, 6), 4), "vel": v, "sz": 2.0, "life": 0.35, "max": 0.35, "col": Color(0.55, 0.65, 0.7, 0.8)})


func draw_player() -> void:
	var tx: Texture2D = g.sprite.texture
	if tx == null:
		return
	var hf := g.sprite.hframes
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (g.sprite.frame % hf), 0, fw, fh)
	var pk: float = Game.PX / A.hires_of(tx)   # @2x 高清贴图按半倍画
	var sx := -pk if g.sprite.flip_h else pk
	# 以脚底为轴做挤压 / 前倾 / 后坐（帧动画之上的程序手感）
	g.draw_set_transform(g.sprite.position + g.p_off, g.sprite.rotation + g.p_lean, Vector2(sx * g.p_sq.x, pk * g.p_sq.y))
	# 博士挂件不受击：不吃主控的受击闪白 / 无敌闪烁（那些现在画在主控干员身上）
	var dmod: Color = Color(0.5, 0.5, 0.6, 0.6) if g.state == Game.S.DEAD else Color.WHITE
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + g.sprite.offset, Vector2(fw, fh)), src, dmod)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
