extends RefCounted
## 世界绘制（2.5D）：地图之上按纵深排序画敌人 / 主控 / 编队 / 博士挂件 / 特效，缩圈与护盾；主控与博士的动画状态、手感（压缩 / 拉伸 / 扬尘）。
## game.gd 的 _draw 只转发到这里。地图本身在 world/map.gd，HUD 在 screens/hud.gd。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

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
var ecrowd := 0.0                 # 敌人密度 0–1（活着的敌人 90 → 210）：普通怪描边随之变淡
const CROWD_FROM := 80.0          # 特效总数超过这个开始降
const CROWD_SPAN := 220.0         # 再多这么多降到底
## 会被降透明度的友方特效种类（敌方的 rift / bbeam / horde_ring、治疗十字、地面血迹不降）
const DIM_KINDS := ["explode", "burst", "rays", "ring", "impact", "bslash", "slash", "spark", "shard", "wpillar", "pillar", "beam", "tracer", "quake", "sprite", "frost"]
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane", "tide": "proj_tide"}
## 水月 48px 动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。脚底锚点 (24,46)。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _init(game: Game) -> void:
	g = game


func update_visuals(dt: float) -> void:
	g._update_doc_follow(dt)
	var bob: float = -abs(sin(g.walk_t)) * 2.0 if g.doc_moving else 0.0
	g.sprite.position = (g.doc_pos + Vector2(0, bob + 6)).round()
	g.sprite.flip_h = g.doc_face < 0.0
	update_player_anim(g.get_process_delta_time())
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
	var flicker := 1.0 + sin(g.t * 13.0) * 0.02 + sin(g.t * 7.3) * 0.03
	if g.lamp < 30.0:
		flicker += sin(g.t * 23.0) * 0.06
	g.lamp_light.position = g.ppos + Vector2(0, -20)
	g.lamp_light.texture_scale = radius / 64.0 * flicker
	g.lamp_light.color = Color(1.0, 0.86, 0.62) if g.lamp >= 30.0 else Color(1.0, 0.6, 0.5)
	# 海中浮游颗粒
	g.map.update_snow(dt, g.get_viewport_rect().size)
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


func draw_world() -> void:
	g.map.draw_ground(g.get_viewport_rect().size)
	for m in g.mires:
		g.map.draw_mire(m)
	g.bai._draw_warns()
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
	for g_item in g.gems:
		var gz: float = g_item.get("z", 0.0)
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
	g.vfx.spr("shadow", 1, 0, g.doc_pos + Vector2(0, 6), Game.PX * 1.3)
	g.squad.draw_auras()
	for e in g.enemies:
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
		# 敌方弹幕高对比：深色外圈垫底，画完再描一圈亮洋红边，压在友方特效上也一眼看得出
		g.draw_circle(bp, b.r + 3.0, Color(0.02, 0.0, 0.05, 0.85))
		match b.get("kind", "orb"):
			"acid":
				g.draw_circle(bp, b.r + 5.0, Color(0.5, 1.4, 0.3, 0.3))
				g.draw_circle(bp, b.r, Color(0.6, 1.8, 0.4))
				g.draw_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6))
			"nova":
				g.draw_circle(bp, b.r + 5.0, Color(1.2, 0.4, 1.8, 0.3))
				g.draw_circle(bp, b.r, Color(1.5, 0.6, 2.0))
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


func draw_enemy(e: Dictionary) -> void:
	var name: String = e.tex
	# 形态切换：偏执泡影二阶段 / 接潮三件套昏迷时的假死造型
	if e.type == "paranoia" and e.phase == 2 and g.tex.get("e_paranoia2") != null:
		name = "e_paranoia2"
	elif e.coma and e.tex_feign:
		name = name + "_feign"
	var frames := 2
	var frame := int(g.t * (2.0 if e.boss else 5.0) + e.id * 0.37) % 2
	# 移动帧条（美术 V5 / V8 / V9）：移动中播放 4 帧循环；停下、晕眩、假死时用本体
	if e.tex_move:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = g.t + 0.2
		e.dpos = e.pos
		if g.t < e.mv_until and e.stun <= 0.0 and not e.coma:
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
		var ww: float = maxf(maxf(e.get("wind", 0.0), e.get("blast_w", 0.0)), maxf(maxf(e.get("burst_w", 0.0), e.get("dash_w", 0.0)), e.get("nova_w", 0.0)))   # 各种蓄力都播攻击帧条前两帧（docs/48 ⑥）
		if ww > 0.0:
			e.atk_until = g.t + 0.2
			name = e.tex + "_attack"
			frames = 4
			frame = 0 if ww > 0.2 else 1
		elif g.t < e.get("atk_until", 0.0):
			name = e.tex + "_attack"
			frames = 4
			frame = 2 if e.atk_until - g.t > 0.1 else 3
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
	if ed.has("aura_r") and g.tex.get("fx_nest_aura") != null:
		# 巢涌者神经光环：脚下的光环帧条按光环半径放大，外圈描出实际判定范围
		var ar: float = ed.aura_r
		g.vfx.spr("fx_nest_aura", 4, int(g.t * 10.0 + e.id) % 4, e.pos, ar / 24.0, false, Color(1, 1, 1, 0.45))
		g.draw_arc(e.pos, ar, 0.0, TAU, 40, Color(0.9, 0.5, 1.6, 0.35), 2.0)
	# 染色复用贴图的敌人（巨海、撕裂者、潜地者、吐酸者）按自身半径放大：enemies.json 的 draw_scale（docs/48 §1 第 7 项）
	var sc: float = Game.PX * e.r / e.r0 * float(D.ENEMIES.get(e.type, {}).get("draw_scale", 1.0))
	var col: Color = D.ENEMIES.get(e.type, {}).get("tint", Color.WHITE)
	if e.evo:
		col = col * Color(1.0, 0.62, 0.68)
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
		bpos = e.pos + Vector2(0, e.r * 0.8 + 3.0 * Game.PX)
	var k: float = clamp(e.squash / 0.14, 0.0, 1.0)
	var sq := Vector2(1.0 + 0.3 * k, 1.0 - 0.25 * k)
	# Boss 攻击姿态：蓄力时后仰变亮，出手瞬间前倾拉伸；有 _attack 帧条时改用帧条
	if e.boss and e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0:
		var pk: float = e.pose / e.pose_max
		if e.tex_attack and not e.coma:
			name = e.tex + "_attack"
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
	if e.get("air", 0.0) > 0.0:
		g.draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, e.r * 0.9, Color(0, 0, 0, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_off.y -= e.air
	# 轮廓光：深色怪物在灯光外也能看清（颜色 >1，抵消环境暗色）
	if Cfg.outline and g.tex.has(name + "_white"):
		var oc := Color(1.6, 2.4, 3.2, 0.55) if not e.elite else Color(3.2, 1.1, 0.7, 0.75)   # 精英：橙红（docs/48 ⑤，原金色和友方金圈、刀光撞色）
		if not e.elite and not e.boss:
			oc.a *= lerpf(1.0, 0.4, ecrowd)   # 后期满屏敌人时普通怪描边变淡，不再连成一片（EA 1.1）；精英 / Boss 不变
		for d in [Vector2(Game.PX, 0), Vector2(-Game.PX, 0), Vector2(0, Game.PX), Vector2(0, -Game.PX)]:
			g.vfx.spr(name + "_white", frames, frame, bpos + d, sc, flip, oc, anc, sq)
	g.vfx.spr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		g.vfx.spr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc, sq)
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
## 敌方自带的危险提示（docs/48 全局 ②，P0 狂奔者 / 囊海爬行者 / 伊祖米克）：原来画在实体层，会被光照压暗、被友方特效盖住。
## 统一画在特效之上：主题色半透明填充（从小到大表示倒计时）+ 深色外描边 + 主题色线 + 白芯；颜色不乘亮度，保住色相（全局 ④）
const ENEMY_TELL := Color(1.0, 0.3, 0.72)       # 敌方危险主色：洋红（和友方的金、青、绿、艾雅法拉的橙红都分得开）
const TELL_BURST := Color(0.78, 0.42, 1.0)      # 囊海爬行者爆裂：紫

func draw_enemy_tells() -> void:
	for e in g.enemies:
		if e.dead:
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


## Boss 招式预警的轮廓再描一遍（填色仍在地面层，boss_ai._draw_warns）：地面层会被友方特效盖住，
## 轮廓画在特效之上，后期满屏特效时也看得到往哪躲
func draw_warn_outlines() -> void:
	for w in g.warns:
		if w.done:
			continue
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		var line := Color(c.r, c.g, c.b, 0.6 + 0.35 * k)   # 不乘亮度：乘完在灯光里会褪成白 / 粉彩（docs/48 ④）
		var dark := Color(0.0, 0.0, 0.0, 0.55)
		match w.shape:
			"circle":
				g.draw_set_transform(w.pos, 0.0, Vector2(1.0, 0.72))
				g.draw_arc(Vector2.ZERO, w.r + 2.0, 0.0, TAU, 40, dark, 2.0)
				g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 40, line, 2.0)
				if w.get("must_dash", false):
					# 必须冲刺躲的招式（docs/38 §1.9）：白色双描边 + 圈上方冲刺图标（三道向外的斜杠）
					var pk: float = 0.5 + 0.5 * sin(g.t * 12.0)
					g.draw_arc(Vector2.ZERO, w.r + 7.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55 + 0.35 * pk), 2.0)
					g.draw_arc(Vector2.ZERO, w.r - 5.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45 + 0.3 * pk), 1.5)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if w.get("must_dash", false):
					var ic: Vector2 = w.pos + Vector2(0, -w.r * 0.72 - 22.0)
					for q in 3:
						var ox: float = -9.0 + q * 7.0
						g.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(0, 0, 0, 0.7), 5.0)
						g.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(1, 1, 1, 0.95), 2.5)
			"line":
				g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				g.draw_rect(Rect2(0.0, -w.wid - 2.0, w.len, w.wid * 2.0 + 4.0), dark, false, 2.0)
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), line, false, 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cone":
				var pts := PackedVector2Array([w.pos])
				for q in 17:
					pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * q / 16.0) * w.r)
				pts.append(w.pos)
				g.draw_polyline(pts, dark, 4.0)
				g.draw_polyline(pts, line, 2.0)


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


## 黑潮边缘的溟痕带（2026-09-27 用户要求：原来是沿圈摆一个个分开的溟痕贴图，改成连成一圈的潮线）：
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
	var prev_in := Vector2.ZERO
	var prev_mid := Vector2.ZERO
	var prev_out := Vector2.ZERO
	var prev_vis := false
	var c_in := Color(1.1, 0.35, 1.6, 0.55 + 0.2 * pulse)
	var c_mid := Color(0.42, 0.1, 0.62, 0.62)
	var c_out := Color(0.16, 0.03, 0.22, 0.0)
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
			_zone_crest(crest, pulse)
			crest = PackedVector2Array()
		prev_in = pin
		prev_mid = pmid
		prev_out = pout
		prev_vis = vis
	if crest.size() > 1:
		_zone_crest(crest, pulse)
	# 漂移的溟痕团：每 120 像素弧长一团，沿圈缓慢流动，大小呼吸
	var nb: int = clampi(int(TAU * r / 120.0), 12, 120)
	for j in nb:
		var a2: float = TAU * (j + fmod(t * 0.04, 1.0)) / nb
		var d2 := Vector2.from_angle(a2)
		var bp: Vector2 = c + d2 * (r + 16.0 + 8.0 * sin(j * 1.7 + t * 0.8))
		if bp.distance_to(vc) > view:
			continue
		var br: float = 5.0 + 3.0 * sin(j * 2.3 + t * 1.5)
		g.draw_set_transform(bp, a2 + PI / 2.0, Vector2(1.6, 0.8))
		g.draw_circle(Vector2.ZERO, br + 2.0, Color(0.08, 0.0, 0.12, 0.55))
		g.draw_circle(Vector2(-1, -1), br * 0.5, Color(0.9, 0.3, 1.3, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 潮头线：暗色描边垫底 + 亮紫细线（安全区边界一眼看清）
func _zone_crest(pts: PackedVector2Array, pulse: float) -> void:
	g.draw_polyline(pts, Color(0.05, 0.0, 0.08, 0.6), 5.0)
	g.draw_polyline(pts, Color(1.6, 0.6, 2.2, 0.75 + 0.25 * pulse), 2.0)


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
