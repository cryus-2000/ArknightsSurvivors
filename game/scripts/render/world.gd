extends RefCounted
## 世界绘制（2.5D）：地图之上按纵深排序画敌人 / 主控 / 编队 / 博士挂件 / 特效，缩圈与护盾；主控与博士的动画状态、手感（压缩 / 拉伸 / 扬尘）。
## game.gd 的 _draw 只转发到这里。地图本身在 world/map.gd，HUD 在 screens/hud.gd。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Look = preload("res://scripts/render/look.gd")   # 观感预设：角色本体受光封顶（render/look ≥ 1）
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（render/declutter）
const FD = preload("res://scripts/render/frame_dst.gd")   # 精灵取帧 + 落点（docs/101 B4 ②）
const GroundCrack = preload("res://scripts/render/ground_crack.gd")
const EnemyAtlas = preload("res://scripts/render/enemy_atlas.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")   # 预警填充层（docs/101 B2，原 boss_ai.draw_warns）
const TriBatch = preload("res://scripts/render/tri_batch.gd")   # 引擎同款几何的无贴图三角形批（docs/50 §13）

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
var fx_dim := 1.0                 # 友方特效的透明度系数（1 → 0.45；render/declutter 的 dim_floor）
var dcrowd := 0.0                 # 降噪用的拥挤度：max(crowd, ecrowd × declutter crowd_mix)
var mate_dim := 1.0               # 队友（非主控）特效再乘的系数（declutter mate_k；squad 绘制时按干员临时乘进 fx_dim）
var lead_dim := 1.0               # 主控自己的特效再乘的系数（declutter lead_k）
var ol_mul := 1.0                 # 普通怪描边透明度系数（随 ecrowd 降到 declutter ol_floor；原来写死 0.4）
var flash_a := 0.9                # 普通怪受击白闪透明度（随 ecrowd 从 0.9 降到 declutter flash_a）
var gem_qa := 0.7                 # 远处安静结晶的透明度（declutter gem_quiet_a 随拥挤度插值；缺省 0.7 = 不变）
var tell_fill := 1.0              # 预警填充透明度系数（declutter tell_fill_k；只压填充，轮廓不动）
var tell_edge := 1.0              # 预警轮廓线宽系数（declutter tell_edge_k；深色描边 + 白芯一起加粗）
var spark_left := 0                # 本帧世界层友方火花的剩余绘制预算（declutter spark_budget，0 = 不限）
var _dbg_friend: bool = Dc.dbg("nofriend")
var _dbg_enemy: bool = Dc.dbg("noenemy")
var _dbg_foe: bool = Dc.dbg("nofoe")
var _dbg_amb: bool = Dc.dbg("noamb")
var _dbg_ground: bool = Dc.dbg("noground")
var _dbg_gem: bool = Dc.dbg("nogem")
var _dbg_mire: bool = Dc.dbg("nomire")
var boss_seen: Array = []        # Boss 换幕 / 倒下演出的观察表：[boss, 上次的 phase, 已演过倒下]（字典作键会因内容变化失效，按 is_same 找）
var scr_flash := 0.0              # 全屏闪光剩余秒（hud 画）：换幕洋红、Boss 倒下白
var scr_flash_max := 1.0
var scr_flash_col := Color.WHITE
var _gc_sink = null   # GroundCrack.TbSink（_init 里建）
var ecrowd := 0.0                 # 敌人密度 0–1（活着的敌人 90 → 210）：普通怪描边随之变淡
## 精英冷色描边（界面与美术 10-15，协调人「精英冷色标识在局内暗处的可读性」）：Codex 10-14 把四只精英的帧条亮边改回冷色后，
## 照亮圈外（灯火 2）只看帧条分不出精英和普通怪（截图 build/shots/elite_rim/），全靠 HUD 头顶 ▼。这里只给精英画一圈
## 颜色 > 1 的冷青描边（抵消环境暗色，同 Boss 轮廓光的做法），不受「Boss 轮廓光」开关影响；普通怪仍不画（docs/50 §12 A）。
##   render/elite_rim       描边不透明度，0 = 关（缺省）；预览三档 0.35 / 0.55 / 0.8
##   render/elite_rim_gain  亮度倍数（颜色 = 冷青 × gain，缺省 2.2；> 1 才能在暗处透出来）
## 场上精英通常只有几只，每只多一次贴图切换；每帧在 _update 里读一次旋钮
const ELITE_RIM_RGB := Color(0.55, 0.9, 1.0)
var elite_rim := 0.0
var elite_rim_col := Color(0, 0, 0, 0)
var _afast := false               # 本帧缓存路径走图集快速路径（_dc_emit）
var atlas: EnemyAtlas = null      # 普通怪 / 精英帧条图集（docs/50 §12 B，build_enemy_atlas）；null = 全走原帧条贴图
var dc_on := true                 # 敌人画法缓存（docs/50 §9.9）：balance.json fx/enemy_draw_cache（缺省 1），0 = 全走原路径（对照用）
var dc_check := false             # --dccheck：抽查缓存路径与原路径发出的贴图绘制参数，不一致报 SCRIPT ERROR（快检冒烟开着）
var dc_checked := 0               # --dccheck 实际比对的次数（BALANCE prof.dc_checked）
var _rec = null                   # --dccheck 比对时：贴图绘制只记参数、不画
const CROWD_FROM := 80.0          # 特效总数超过这个开始降
const CROWD_SPAN := 220.0         # 再多这么多降到底
## 会被降透明度的友方特效种类（敌方的 rift / bbeam / horde_ring、治疗十字、地面血迹不降）
const DIM_KINDS := ["explode", "burst", "rays", "ring", "impact", "bslash", "slash", "spark", "shard", "wpillar", "pillar", "beam", "tracer", "quake", "sprite", "frost", "tide_link", "frost_track"]
const FOE_KINDS := ["boss_phase", "boss_down", "spear_fly", "frost_track", "frost_step", "reflow", "glint", "drain"]   # 没打 enemy 标记的敌方 / Boss 特效（量测分层用）
const AMB_KINDS := ["mote", "horde_ring", "beacon_burst", "mire_recoil"]   # 系统 / 环境（光尘、大群波、灯标）：量测单独一层
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane"}
## 水月旧主角动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。帧为正方形，画布 48 或 64（docs/103 §5），
## 脚底锚点读 mizuki.json sprites.foot（48 画布 (24,46)、64 画布 (32,60)）。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _init(game: Game) -> void:
	g = game
	_gc_sink = GroundCrack.TbSink.new(self)
	dc_check = Cfg.dev_args().has("--dccheck")
	dc_on = Bal.v("fx/enemy_draw_cache", 1.0) > 0.0   # 开局读一次（--bal=fx/enemy_draw_cache=0 对照旧路径；测量脚本可直接改 world.dc_on 轮换）
	rc_px = Bal.v("fx/recoil_px", 3.0)
	rc_t = maxf(0.01, Bal.v("fx/recoil_t", 0.1))


## 敌人本体的逐帧位移（docs/53）：击退抬跳（原有）+ 受击后坐（vfx.hit_react 写 rc_at / rc_dir / rc_k，这里按 g.t 线性回位）。
## 缓存路径（_dc_emit）和原路径（_draw_enemy_full）都用这一个表达式；draw_off 本来就每帧照算、不进缓存签名（docs/50 §9.9）
var rc_px := 3.0
var rc_t := 0.1

func _eoff(e: Dictionary) -> Vector2:
	return D.enemy_offset(e, g.t, rc_px, rc_t)   # 纯函数在 data.gd（docs/101 B1）


func update_visuals(dt: float) -> void:
	g.doctor.update_follow(dt)
	# 不再叠代码起伏：博士跑步帧条自带步频；旧 2 帧待机条兜底时由 update_doctor_anim 按 anim_t 自己颠
	# （原来按主控的 walk_t 起伏：步频对不上帧条，主控停下后博士还在追时 walk_t 不走，会卡在半空）
	g.sprite.position = (g.doc_pos + Vector2(0, 6)).round()
	g.sprite.flip_h = g.doc_face < 0.0
	update_player_anim(g.get_process_delta_time() if g.state in [Game.S.DEAD, Game.S.WIN] else dt)
	var real_dt: float = g.get_process_delta_time()
	if g.state == Game.S.OPENING and real_dt > 0.0:
		g.intro_screen.update_opening(real_dt)   # 开场状态机（落地 → 点灯 → end_opening 切到 PLAY；docs/101 B3 从 update_player_feel 里提出来，时机不变）
	update_player_feel(real_dt)
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
	var rd := g.get_process_delta_time()
	g.glance_step(rd)   # 镜头一瞥（game.camera_glance：骑士入潮 / 寒冰重生时看一眼黑潮中心；只动镜头）
	g.cam.position = g.cam_center().round()
	g.shake = move_toward(g.shake, 0.0, rd * 2.5)
	cam_kick = cam_kick.move_toward(Vector2.ZERO, rd * 60.0)
	g.hurt_vignette = move_toward(g.hurt_vignette, 0.0, rd * 1.5)
	g.hurt_duck = move_toward(g.hurt_duck, 0.0, rd)
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
			Sfx.play("heartbeat_hi", -0.7, 1.0, 0.0)   # 高频层：原心跳 99% 在 120 Hz 以下，手机 / 笔记本外放听不到（音频 10/1）
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
	# 骑士入潮点临时暖光：入潮演出期间亮在沉入处，随进度淡出（纯画面；10:00 重生不用）
	if g.knight_light != null:
		var sinking: bool = g.knight != null and g.knight.alive and g.knight.state == "sink"
		g.knight_light.visible = sinking
		if sinking:
			var k: float = clampf(g.knight.st / g.knight.SINK_T, 0.0, 1.0)
			g.knight_light.position = g.knight.vanish_pos + Vector2(0, -16)
			g.knight_light.energy = 1.5 * (1.0 - k * k)
	Look.update_actor_mat(g)
	update_beacon_lights()
	g.vfx.watch_lamp(rd)        # docs/54 ③ 灯火暗淡 / 寂灭的一压 + 余烬
	g.vfx.watch_merchant(rd)    # docs/54 ⑧ 商人出现 + 灯笼暖尘
	if g.merchant_light != null and g.merchant_light.visible and g.vfx.strip("fx_merchant_lantern"):
		g.merchant_light.energy = 1.2 if g.vfx.lantern_bright() else 1.0   # 灯光能量随灯笼覆盖帧一起抖
	# 海中浮游颗粒
	g.map.update_snow(dt, g.view_size())
	_enemy_act_fx()
	# 特效密度 → 友方特效降噪（图鉴演示不降，演示本来就是看特效的）
	var nfx: int = g.fx.size()
	for o in g.squad.ops:
		nfx += o.pfx.size()
	var want: float = 0.0 if g.demo_op != "" else clampf((nfx - Dc.p("crowd_from")) / Dc.p("crowd_span"), 0.0, 1.0)
	crowd = move_toward(crowd, want, rd * (3.0 if want > crowd else 0.8))
	var ne := 0
	for e in g.enemies:
		if not e.dead:
			ne += 1
	var ewant: float = 0.0 if g.demo_op != "" else clampf((ne - 90.0) / 120.0, 0.0, 1.0)
	ecrowd = move_toward(ecrowd, ewant, rd * 0.8)
	# 后期降噪预设（render/declutter，render/declutter.gd）：敌人多也算拥挤（crowd_mix，缺省 0 = 只看特效数）
	dcrowd = maxf(crowd, ecrowd * Dc.p("crowd_mix"))
	fx_dim = lerpf(1.0, Dc.p("dim_floor"), dcrowd)
	mate_dim = Dc.at("mate_k", dcrowd)
	lead_dim = Dc.at("lead_k", dcrowd)
	if _dbg_friend:
		fx_dim = 0.0   # --clutterdbg=nofriend：友方特效全透明（代码照跑、随机数照抽）
	ol_mul = lerpf(1.0, Dc.p("ol_floor"), ecrowd)
	flash_a = lerpf(0.9, Dc.p("flash_a"), ecrowd)
	spark_left = int(Dc.p("spark_budget")) if Dc.p("spark_budget") > 0.0 else 1 << 30
	elite_rim = clampf(Bal.v("render/elite_rim", 0.0), 0.0, 1.0)
	var rg: float = Bal.v("render/elite_rim_gain", 2.2)
	elite_rim_col = Color(ELITE_RIM_RGB.r * rg, ELITE_RIM_RGB.g * rg, ELITE_RIM_RGB.b * rg, elite_rim)
	g.fx_add.modulate.a = 0.0 if _dbg_friend else lerpf(1.0, Dc.p("add_floor"), dcrowd)
	if g.post != null and "crowd" in g.post:
		g.post.crowd = dcrowd
		g.post.bloom_cut = Dc.p("bloom_cut")


## 表现事件步骤（docs/101 B3，10-15）：game._process 末尾每帧调一次（有头时在本帧绘制之前），无头批跑也照常走。
## 只放画面 / 演出，不改模拟、不碰 g.rng（特效只用 vrng）。原来 watch_bosses 在 draw_world 开头，无头时从不执行
func present_step() -> void:
	watch_bosses()


## Boss 换幕 / 倒下演出（docs/48 P1：换幕只有横幅，死亡特效和精英同一套、比本体还小）。
## 只观察 g.bosses 的 phase / dead 变化来放特效，不改战斗逻辑，不影响对局随机数（特效只用 vrng）；由 present_step 每帧调
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
		# 友方 → 敌对（伊莎玛拉转化完成）：这时才演登场（screens/boss_intro.gd；纯画面观察，不改逻辑）
		var fr: bool = b.get("friendly", false)
		if s.size() < 6:
			s.resize(6)
			s[5] = fr
		elif not fr and s[5] and not b.dead:
			g.boss_intro.on_spawn([b])
		s[5] = fr
		var bk: bool = b.type == "knight_boss" and b.get("break_t", 0.0) > 4.0
		if s.size() < 5:
			s.resize(5)
			s[3] = b.get("sword_t", 0.0) > 0.0
			s[4] = bk
		elif bk and not s[4]:
			spear_fly_fx(b)
		s[4] = bk
		if b.type == "ishar" and b.get("dash_t", 0.0) > 0.0 and not b.dead:
			_tide_trail(b)
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
	g.boss_intro.on_down(b)   # 击破一拍：名字一行「击破」（screens/boss_intro.gd）


var _pt := 0


## --prof：世界绘制分段计时（dw_<段名>，微秒累计进 g.prof）
func _pk(k: String) -> void:
	if not g.prof_on:
		return
	var now := Time.get_ticks_usec()
	if k != "":
		g.prof["dw_" + k] = int(g.prof.get("dw_" + k, 0)) + now - _pt
	_pt = now


func draw_world() -> void:
	_pk("")
	scr_flash = maxf(0.0, scr_flash - g.get_process_delta_time())
	if _dbg_ground:
		g.draw_rect(view_rect(0.0), Color(0.16, 0.17, 0.2))   # --clutterdbg=noground（量测）：地面 / 地形道具换成平涂底色
	else:
		g.map.draw_ground(g.view_size())
		# 后期降噪（render/declutter ground_veil，缺省 0 = 不画）：拥挤时地面盖一层地面平均色的薄纱，压地砖 / 小道具纹理的对比，
		# 让敌人、弹幕和预警从地上浮出来；在溟痕 / 地面预警 / 掉落之下，灯火照常照在上面
		var gv: float = Dc.p("ground_veil") * dcrowd
		if gv > 0.002:
			var gm: Color = g.map.ground_mean()
			g.draw_rect(view_rect(8.0), Color(gm.r, gm.g, gm.b, gv))
	g.squad.draw_ground_fx()   # 干员紧贴地砖的大片地面特效（docs/61 §5.6 layer = ground）：压在溟痕 / 地面预警之下
	_pk("ground")
	_draw_mires()
	_pk("mire")
	tell_fill = Dc.p("tell_fill_k")
	tell_edge = Dc.p("tell_edge_k")
	_draw_warns_auras()
	_pk("warns_auras")
	if not _dbg_gem:   # --clutterdbg=nogem（量测）
		_draw_pickups()
	_pk("gems")
	var evr: Rect2 = view_rect(ENTITY_MARGIN)   # 屏幕外的敌人不画影子、不进排序（性能，协调人 9/30；绘制只改画面，不影响模拟）
	_build_vis(evr)
	_draw_shadows(evr)
	_pk("shadows")
	_draw_sorted_entities(evr)
	_pk("sorted_entities")
	_draw_overlays_shield_drones()
	_pk("shield_drones")
	_draw_bullets()
	_pk("bullets")
	_draw_fx()
	_pk("fx")
	if not _dbg_foe:   # --clutterdbg=nofoe：敌方弹幕 / 预警整层不画（量测）
		_draw_ebullets_lobs_shocks()
	_pk("ebullets_lobs_shocks")
	_draw_tells_outlines()
	_pk("tells_outlines")
	draw_zone()
	_pk("zone")
	g.map.draw_snow()
	_pk("snow_tail")


## 溟痕：地面贴图 + 视野内的气泡（上限 MIRE_BUBBLE_MAX）+ 光尘（docs/54）；tb 批在气泡前提交
func _draw_mires() -> void:
	var mvr: Rect2 = view_rect(40.0)
	var bubbles: Array = []
	var mote_budget: int = MIRE_MOTE_MAX if g.vfx.ambient_ok() and g.vfx.on("mire_motes") else 0   # docs/54 溟痕光尘（高画质、非触屏）
	var vr0: Rect2 = view_rect(4.0)
	for m in g.mires:
		# 屏幕外的溟痕不画（性能，docs/50 §11；贴图 ±1.15 r、判定圈 r + 0.75，外扩到 1.2 r 再加 4 像素，屏幕内画面不变）
		var mr: float = float(m.r) * 1.2
		if not _dbg_mire and (vr0.intersects(Rect2(m.pos - Vector2(mr, mr), Vector2(mr, mr) * 2.0))):
			g.map.draw_mire(m)
		if mvr.has_point(m.pos):
			if bubbles.size() < MIRE_BUBBLE_MAX:
				_mire_bubbles(m, bubbles)
			if mote_budget > 0:
				mote_budget -= g.vfx.mire_motes(m, mote_budget)
	tb_flush()
	if not _dbg_mire:
		_draw_mire_bubbles(bubbles)
	_draw_ground_sprites()


## 地面层帧条特效（vfx.fx_sprite ground=true，kind "gsprite"）：溟痕之上、预警 / 实体之下——喷吐者酸团落点溅射、囊海爬行者爆后残留（docs/96 第 1 批）。
## 敌方特效不降噪（docs/48 ③），按已播时间取帧，同 _draw_fx 的 "sprite"
func _draw_ground_sprites() -> void:
	g.draw_off = Vector2.ZERO
	for f in g.fx:
		if f.kind != "gsprite":
			continue
		var spec: Array = Game.V6_FRAMES[f.name]
		var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
		g.vfx.spr_rot(f.name, fr, f.pos, f.ang, f.scale, f.get("col", Color.WHITE), f.get("anchor", Vector2(-1, -1)), f.get("flip", false))


## 预警分类 → Boss 招式预警填充（render/telegraph_draw）→ 巢涌者光环 → 灯标 → 藏品特效 → 商人
func _draw_warns_auras() -> void:
	classify_tells()   # 先判哪些预警会打到主控（可读性 1.1.1）：地面填充 / 轮廓 / 冲刺线都读这个结果
	if not _dbg_foe:
		TeleDraw.draw_fills(g)
	draw_nest_auras()
	draw_beacons()
	draw_hunt_ring()
	if not _dbg_friend:
		g.rfx.draw()   # 藏品特效（--clutterdbg=nofriend 量测时不画；只画不抽随机数）
	if not g.merchant.is_empty():
		var mtx: Texture2D = g.tex.merchant
		var big_m: bool = mtx != null and mtx.get_height() >= 40
		g.vfx.spr("shadow", 1, 0, g.merchant.pos + Vector2(0, 18), Game.PX * (1.6 if big_m else 1.2))
		if big_m:
			var mfr: int = int(g.t * 2.0) % 2
			var mflip: bool = g.ppos.x < g.merchant.pos.x
			g.vfx.spr("merchant", 2, mfr, g.merchant.pos + Vector2(0, 18), Game.PX, mflip, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
			g.vfx.merchant_lantern(mfr, g.merchant.pos + Vector2(0, 18), mflip)   # 灯笼亮度闪烁覆盖帧（docs/54 §6；贴图不在就不画）
		else:
			g.vfx.spr("merchant", 2, int(g.t * 2.0) % 2, g.merchant.pos, Game.PX)
		# 「商人 %ds」标签由 HUD 层在头顶绘制（_draw_hud 商人方向指示），这里不再重复画一份


## 围猎包围圈（run/hunt.gd；用户 10-11：「一分半的围猎的包围圈不够明显，没有看到一个圈」）。
## 10-11 二版：一版 696847e 把圈画在地面层，整条线跟着灯火光照走——灯火足时靠主控发白、远处只剩 ambient 的灰紫，
## 和一百多只小怪的白描边抢不过。现在圈体（底边 + 紫色虚线 + 缺口青绿弧 + 扫描亮斑）挪到 HUD 层（screens/hud_banners.gd
## draw_hunt_ring，不受 CanvasModulate / 灯光影响，颜色就是设计色）；地面层只留「里外一眼分开」的调子：圈外压暗 0.15
## （径向渐变到圈边，一直铺到画面外）、圈内贴边一圈淡紫。低画质整段不画。全进 tb 批一次提交；只读 hunt.vis()，不改对局
const HUNT_COL := Color(0.75, 0.5, 1.0)
func draw_hunt_ring() -> void:
	if g.hunt == null or Cfg.quality == "low":
		return
	var v: Dictionary = g.hunt.vis()
	if v.is_empty() or v.alpha <= 0.0:
		return
	var c: Vector2 = v.c
	var r: float = v.r
	var alpha: float = v.alpha
	var ta: float = 0.15 * alpha
	var vr: Rect2 = view_rect(0.0)
	var far: float = 0.0
	for corner in [vr.position, vr.end, Vector2(vr.position.x, vr.end.y), Vector2(vr.end.x, vr.position.y)]:
		far = maxf(far, c.distance_to(corner))
	far = maxf(far + 40.0, r + 180.0)
	tb_ring2(c, r, r + 90.0, Color(0.0, 0.0, 0.02, 0.0), Color(0.0, 0.0, 0.02, ta), 64)
	tb_ring(c, (r + 90.0 + far) * 0.5, far - (r + 90.0), Color(0.0, 0.0, 0.02, ta), 64)
	tb_ring2(c, r - 70.0, r, Color(HUNT_COL, 0.0), Color(HUNT_COL, (0.12 + 0.1 * v.tick) * alpha), 64)
	tb_flush()


## 性能（协调人 9/30：后期没捡的结晶堆积，每颗 5–8 个图元）：屏幕外的掉落不画；结晶很多时，
## 远处安静的小结晶按 GEM_CELL 网格合并成一颗画（只合并画面，拾取仍是一颗一颗的）；拖尾 / 辉光 / 深色底进 tb 批，贴图与闪光循环后统一画
func _draw_pickups() -> void:
	_draw_pickups_fast()


## 掉落物绘制（性能 docs/50 §11 的快速写法；10-15 删掉旧写法，docs/101 S2）：
## - 光晕 / 深色底 / 拖尾 / 闪光不再逐段算三角函数、逐个追加索引：单位圆的三角形表开局算一次，每个圆用 Transform2D 整组缩放平移（引擎原生运算），
##   进一个无索引三角形批（每 3 个顶点一个三角形，和 tb_circle / tb_line 的三角形相同）；
## - 结晶贴图直接按贴图尺寸画（vfx.spr 的同一套算式），大 / 小结晶分两组连续画（同贴图连续提交才合批）；
## - 循环外先取好主控位置、拥挤判定与常量色，离主控 170 的判定用距离平方
var _gt_fan14 := PackedVector2Array()   # tb_circle(seg 14) 的单位扇形三角形表
var _gt_fan10 := PackedVector2Array()   # tb_circle(seg 10)
var _gtb := TriBatch.new()   # 表驱动快路径（docs/101 B4 ③：存储 / 提交走 TriBatch）
var _gt_c42 := PackedColorArray()
var _gt_c30 := PackedColorArray()

func _gt_tables() -> void:
	for spec in [[14, _gt_fan14], [10, _gt_fan10]]:
		var seg: int = spec[0]
		var arr: PackedVector2Array = spec[1]
		for q in seg:
			var aq: float = q * TAU / seg
			var aq2: float = ((q + 1) % seg) * TAU / seg
			arr.append_array([Vector2.ZERO, Vector2(cos(aq), sin(aq)), Vector2(cos(aq2), sin(aq2))])
	_gt_c42.resize(42)
	_gt_c30.resize(30)


func _gt_circle(c: Vector2, r: float, col: Color, fan: PackedVector2Array, cols: PackedColorArray) -> void:
	cols.fill(col)
	_gtb.tris(Transform2D(Vector2(r, 0.0), Vector2(0.0, r), c) * fan, cols)


func _gt_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var n: Vector2 = (b - a).orthogonal().normalized() * w * 0.5
	_gtb.tris(PackedVector2Array([a + n, b + n, b - n, a + n, b - n, a - n]), PackedColorArray([col, col, col, col, col, col]))


func _gt_flush() -> void:
	_gtb.flush(g)


func _draw_pickups_fast() -> void:
	if _gt_fan14.is_empty():
		_gt_tables()
	tb_flush()   # 之前各段留在 tb 批里的三角形先交（旧写法和掉落一起交，前后顺序相同）
	var vr: Rect2 = view_rect(40.0)
	gem_qa = lerpf(0.7, Dc.p("gem_quiet_a"), dcrowd)
	var n_all: int = g.gems.size()
	var crowd_gems: bool = n_all > GEM_MERGE_N
	var many: bool = n_all > 60
	var pp: Vector2 = g.ppos
	var tgt: Vector2 = pp + Vector2(0, -12)
	var t: float = g.t
	var bob_t: float = t * 4.0
	var tw_t: float = t * 6.0
	var cells := {}
	var small_p := PackedVector2Array()   # 小结晶贴图：位置 / 颜色
	var small_c := PackedColorArray()
	var big_p := PackedVector2Array()
	var big_c := PackedColorArray()
	var spark: Array = []   # 十字闪光：[位置, 长度, 闪烁]
	var ing_p := PackedVector2Array()   # 落地源石锭 / 灯油的位置（已含 draw_off）
	var oil_p := PackedVector2Array()
	var cy := UI.CYAN
	var glow_s0 := Color(cy.r * 1.6, cy.g * 1.6, cy.b * 1.6, 0.16)
	var glow_s1 := Color(cy.r * 2.0, cy.g * 2.0, cy.b * 2.0, 0.22)
	var pu := Color(0.85, 0.6, 1.0)
	var glow_b0 := Color(pu.r * 1.6, pu.g * 1.6, pu.b * 1.6, 0.16)
	var glow_b1 := Color(pu.r * 2.0, pu.g * 2.0, pu.b * 2.0, 0.22)
	var dark := Color(0.0, 0.02, 0.05, 0.55)
	var quiet_col := Color(0.9, 0.95, 1.0, gem_qa)
	var lit_s := Color(1.25, 1.25, 1.3)
	var lit_b := Color(1.35, 1.2, 1.5)
	const NEAR2 := 170.0 * 170.0
	for g_item in g.gems:
		var pos: Vector2 = g_item.pos
		if not vr.has_point(pos):
			continue
		var gz: float = g_item.z
		var kind: String = g_item.kind
		var mag: bool = g_item.mag
		if kind == "xp":
			var far: bool = not mag and pos.distance_squared_to(pp) > NEAR2
			var big: bool = g_item.val >= 5.0
			if crowd_gems and far and gz <= 1.0 and not big:
				var ck := Vector2i(floori(pos.x / GEM_CELL), floori(pos.y / GEM_CELL))
				cells[ck] = int(cells.get(ck, 0)) + 1
				continue
			if gz > 1.0:
				_pq_air_shadow(pos, gz)
			var quiet: bool = many and far
			var tw: float = 0.75 + 0.25 * sin(tw_t + g_item.seed)
			var gp: Vector2 = pos + Vector2(0, (sin(bob_t + pos.x) * 2.0 if gz <= 1.0 else 0.0) - gz)
			if mag:
				var gc: Color = pu if big else cy
				var dv: Vector2 = (gp - tgt).normalized()
				var tl: float = 10.0 + 24.0 * minf(1.0, g_item.mag_t * 2.0)
				_gt_line(gp, gp + dv * tl, Color(gc.r * 1.8, gc.g * 1.8, gc.b * 1.8, 0.55), 5.0 if big else 3.0)
				_gt_line(gp, gp + dv * tl * 0.6, Color(2.5, 2.5, 2.5, 0.7), 1.5)
			if not quiet:
				_gt_circle(gp, (13.0 if big else 9.0) * tw, glow_b0 if big else glow_s0, _gt_fan14, _gt_c42)
				_gt_circle(gp, (7.0 if big else 4.5) * tw, glow_b1 if big else glow_s1, _gt_fan14, _gt_c42)
			_gt_circle(gp + Vector2(0, 1), 6.5 if big else 4.5, dark, _gt_fan10, _gt_c30)
			var gcol: Color = quiet_col if quiet else (lit_b if big else lit_s)
			if big:
				big_p.append(gp)
				big_c.append(gcol)
			else:
				small_p.append(gp)
				small_c.append(gcol)
			if not quiet:
				spark.append([gp, 2.0 + 1.5 * tw, tw])
			continue
		# 落地的源石锭 / 灯油（不吸的时候数量可能上百）：先收集，循环后按贴图连续画（同 vfx.spr 的算式；画在结晶光晕批之前，同旧写法的前后关系）
		if gz <= 1.0 and (kind == "ingot" or kind == "oil"):
			if kind == "ingot":
				ing_p.append(pos + Vector2(0, sin(t * 3.0 + pos.y) * 1.5) + Vector2(0, -gz))
			else:
				oil_p.append(pos + Vector2(0, -gz))
			continue
		# 其他掉落（宝箱 / 磁铁 / 回复药剂、空中的源石锭 / 灯油）：数量少，照旧写法画
		_pq_item(g_item, pos, gz, kind, t)
	_pq_flush()
	var wc1 := PackedColorArray()
	wc1.resize(maxi(ing_p.size(), oil_p.size()))
	wc1.fill(Color.WHITE)
	_gem_sprites("ingot", Game.PX, ing_p, wc1)
	_gem_sprites("oil", Game.PX, oil_p, wc1)
	_gt_flush()
	_gem_sprites("gem_big", Game.PX * 1.9, big_p, big_c)
	_gem_sprites("gem_small", Game.PX * 1.45, small_p, small_c)
	for sk in spark:
		var gp2: Vector2 = sk[0]
		var sp3: float = sk[1]
		var wc := Color(2.5, 2.5, 2.5, 0.5 * sk[2])
		_gt_line(gp2 + Vector2(-sp3, -8), gp2 + Vector2(sp3, -8), wc, 1.0)
		_gt_line(gp2 + Vector2(0, -8 - sp3), gp2 + Vector2(0, -8 + sp3), wc, 1.0)
	_gt_flush()
	# 合并后的一堆：在格子中心画一颗，堆里 3 颗以上画成大结晶（紫），压暗同远处安静结晶；先画完小的再画大的（同贴图连续才合批）
	var mp_s := PackedVector2Array()
	var mp_b := PackedVector2Array()
	for ck in cells:
		var cp: Vector2 = (Vector2(ck) + Vector2(0.5, 0.5)) * GEM_CELL
		if cells[ck] >= 3:
			mp_b.append(cp)
		else:
			mp_s.append(cp)
	var qc := PackedColorArray()
	qc.resize(maxi(mp_s.size(), mp_b.size()))
	qc.fill(quiet_col)
	_gem_sprites("gem_small", Game.PX * 1.45, mp_s, qc)
	_gem_sprites("gem_big", Game.PX * 1.9, mp_b, qc)


## ---- 掉落物剩余断点合批（docs/50 §13，OPT_PICKB）：空中影子（每颗一个椭圆）、特殊掉落（宝箱 / 磁铁 / 回复药剂）的光柱、
## 光圈与细环原来逐个 draw_*，夹在特殊掉落和空中源石锭的贴图之间，每颗都断批。现在：图元按引擎同款几何进 _pb 三角形批，
## 贴图先挂起；新图元或新贴图和挂起的贴图有重叠时先按原顺序交一次（图元 → 贴图），所以有重叠的前后关系和原来一样；
## 互不重叠的挂起贴图按贴图成组连续画。几何、颜色、取整与 _gem_air_shadow / vfx.spr 相同
var _pb := TriBatch.new()
var _pq_spr: Array = []       # 挂起的贴图：[贴图, 目标矩形, 源矩形]
var _pq_rects: Array = []     # 挂起贴图的目标矩形（重叠判定）


func _pq_guard(r: Rect2) -> void:
	for sr in _pq_rects:
		if (sr as Rect2).intersects(r):
			_pq_flush()
			return


func _pq_flush() -> void:
	_pb.flush(g)
	if _pq_spr.is_empty():
		return
	var n: int = _pq_spr.size()
	var done := []
	for i in n:
		var tx: Texture2D = _pq_spr[i][0]
		if done.has(tx):
			continue
		done.append(tx)
		for j in range(i, n):
			var it: Array = _pq_spr[j]
			if it[0] == tx:
				g.draw_texture_rect_region(tx, it[1], it[2])
	_pq_spr.clear()
	_pq_rects.clear()


## 同 _gem_air_shadow
func _pq_air_shadow(pos: Vector2, gz: float) -> void:
	var r: float = 7.0 * (1.0 - clampf(gz / 80.0, 0.0, 0.6))
	var c: Vector2 = pos + Vector2(0, 8)
	_pq_guard(Rect2(c.x - r - 1.0, c.y - r * 0.45 - 1.0, r * 2.0 + 2.0, r * 0.9 + 2.0))
	_pb.circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35), Transform2D(0.0, Vector2(1.0, 0.45), 0.0, c))


## 同 vfx.spr(name, 1, 0, pos)（单帧、锚点居中、取整，含 g.draw_off）
func _pq_sprite(name: String, pos: Vector2) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	pos += g.draw_off
	var fw: int = tx.get_width()
	var fh: int = tx.get_height()
	var size := Vector2(fw, fh) * Game.PX
	var dst := FD.dst(pos, size, Vector2(0.5, 0.5))
	_pq_guard(dst)
	_pq_spr.append([tx, dst, Rect2(0, 0, fw, fh)])
	_pq_rects.append(dst)


## 特殊掉落与空中的源石锭 / 灯油（_draw_pickups_fast 的「其他掉落」分支，画法同旧写法）
func _pq_item(g_item: Dictionary, pos: Vector2, gz: float, kind: String, t: float) -> void:
	if gz > 1.0:
		_pq_air_shadow(pos, gz)
	if g_item.special:
		var ic := g.pickups.item_col(kind)
		var age: float = g_item.age
		if age < 0.9:
			var ba := (1.0 - age / 0.9) * 0.55
			_pq_guard(Rect2(pos + Vector2(-6, -141), Vector2(12, 142)))
			_pb.rect(Rect2(pos + Vector2(-5, -140), Vector2(10, 140)), Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, ba * 0.5))
			_pb.rect(Rect2(pos + Vector2(-2, -140), Vector2(4, 140)), Color(2.5, 2.5, 2.5, ba))
		if kind != "chest":
			var pr := 11.0 + 2.0 * sin(t * 5.0)
			var cc: Vector2 = pos + Vector2(0, -gz - 2)
			var rr: float = pr + 6.0
			_pq_guard(Rect2(cc - Vector2(rr, rr), Vector2(rr, rr) * 2.0))
			_pb.circle(cc, pr + 5.0, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.12))
			_pb.arc(cc, pr, 0.0, TAU, 20, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.5), 1.5)
	g.draw_off = Vector2(0, -gz)
	match kind:
		"oil":
			_pq_sprite("oil", pos)
		"chest":
			_pq_sprite("chest", pos)
		"ingot":
			_pq_sprite("ingot", pos + Vector2(0, sin(t * 3.0 + pos.y) * 1.5 if gz <= 1.0 else 0.0))
		"magnet", "heal":
			_pq_sprite("pickup_" + kind, pos + Vector2(0, -2 + (sin(t * 3.5) * 2.0 if gz <= 1.0 else 0.0)))
	g.draw_off = Vector2.ZERO


## 同一张结晶贴图连续画（FrameDst.dst 的同一套算式：单帧、锚点居中、取整；热循环内联，docs/50 §11）
func _gem_sprites(name: String, sc: float, ps: PackedVector2Array, cs: PackedColorArray) -> void:
	if ps.is_empty():
		return
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	var fw: int = tx.get_width()
	var fh: int = tx.get_height()
	var src := Rect2(0, 0, fw, fh)
	var size := Vector2(fw, fh) * sc
	var half: Vector2 = size * Vector2(0.5, 0.5)
	for i in ps.size():
		g.draw_texture_rect_region(tx, Rect2((ps[i] - half).round(), size), src, cs[i])


## Boss 登场聚光、博士 / 敌人 / 干员 / 骑士的影子、干员脚下层；evr：ENTITY_MARGIN 视野矩形（排序层共用）
func _draw_shadows(evr: Rect2) -> void:
	g.boss_intro.draw_world()   # Boss 登场：脚下聚光圈 + 扩散环（合批；没有登场时直接返回）
	g.vfx.spr("shadow", 1, 0, g.doc_pos + Vector2(0, 6), Game.PX * 1.3)
	g.squad.draw_auras()
	var stx: Texture2D = g.tex.get("shadow")
	var ens: Array = _vis_ent if _vis_on else g.enemies
	if stx == null:
		for e in ens:
			if not evr.has_point(e.pos):
				continue
			var sc: float = Game.PX * e.r / 10.0
			var hop: float = minf(e.kb.length() * 0.03, 14.0)
			g.vfx.spr("shadow", 1, 0, e.pos + Vector2(0, e.r * 0.8), sc * (1.0 - hop / 40.0), false, Color(1, 1, 1, 0.0 if _dbg_enemy else 1.0))
	else:
		# 同上，vfx.spr 内联（性能，docs/50 §11：每只敌人省一次函数调用和贴图查表；算式与 FrameDst.dst 相同）
		var sw := float(stx.get_width())
		var sh := float(stx.get_height())
		var src := Rect2(0, 0, stx.get_width(), stx.get_height())
		var scol := Color(1, 1, 1, 0.0 if _dbg_enemy else 1.0)
		var doff: Vector2 = g.draw_off
		for e in ens:
			var ep: Vector2 = e.pos
			if not evr.has_point(ep):
				continue
			var er: float = e.r
			var sc2: float = Game.PX * er / 10.0 * (1.0 - minf(e.kb.length() * 0.03, 14.0) / 40.0)
			var size := Vector2(sw, sh) * sc2
			g.draw_texture_rect_region(stx, Rect2((ep + Vector2(0, er * 0.8) + doff - size * Vector2(0.5, 0.5)).round(), size), src, scol)
	g.squad.draw_shadows()
	if g.knight.alive:
		g.vfx.spr("shadow", 1, 0, g.knight.pos + Vector2(0, 18), Game.PX * 1.6)
	g.squad.draw_entities_floor()


## 2.5D 前后遮挡：敌人 / 博士 / 干员（含额外身体）/ 骑士 / 排序道具按脚底 y 排序后依次绘制
func _draw_sorted_entities(evr: Rect2) -> void:
	_afast = atlas != null and not _dbg_enemy and not _no_flash and EnemyAtlas.xform_flip
	_am_mode = Look.actor_mod_begin(g)
	if _am_mode == 2:
		Look.actor_mod_lut_build()   # 受光封顶整屏统一算一次（docs/50 §15 D2）：逐只只查表
		_am_mode = 3
	_sorted_fast(evr)
	_am_mode = 0


## 排序实体的快速写法（性能 docs/50 §14，OPT_SORT）：排序键进 PackedFloat64Array 原生排序（不走 sort_custom 的闭包比较，
## 也不给每只实体建 [键, 类, 对象] 三元数组），键 → 实体用字典对回去。键两两不同时排出来的次序唯一，与旧写法相同。
## 键相同（多半是整数坐标的景物同一行）的几样按加入顺序画（稳定）；旧写法 sort_custom 是不稳定排序，同键的先后随整表内容变，
## 两件同一行又互相压着的景物可能逐帧换前后——这是唯一可能和旧写法不同的地方
var _se_objs: Array = []
var _se_kind := PackedByteArray()
var _se_keys := PackedFloat64Array()
var _se_at := {}

func _sorted_fast(evr: Rect2) -> bool:
	var objs: Array = _se_objs
	var kind: PackedByteArray = _se_kind
	var ka: PackedFloat64Array = _se_keys
	var at: Dictionary = _se_at
	objs.clear()
	kind.clear()
	ka.clear()
	at.clear()
	for e in (_vis_ent if _vis_on and not dc_check else g.enemies):
		var ep: Vector2 = e.pos
		if evr.has_point(ep) or dc_check:
			ka.append(ep.y + e.r * 0.8)
			objs.append(e)
	kind.resize(objs.size())
	kind.fill(0)
	ka.append(g.doc_pos.y + 6.0)
	objs.append(null)
	kind.append(2)
	for o in g.squad.ops:
		if o.pos != Vector2.INF:
			ka.append(o.pos.y + 4.0)
			objs.append(o)
			kind.append(5)
		for xb in o.extra_bodies():
			ka.append(xb.y)
			objs.append([o, xb])
			kind.append(6)
	if g.knight.alive:
		ka.append(g.knight.pos.y + 18.0)
		objs.append(null)
		kind.append(4)
	for pr in g.map.sort_props:
		ka.append(pr[1].y)
		objs.append(pr)
		kind.append(3)
	var keys := PackedFloat64Array()
	for i in ka.size():
		var k: float = ka[i]
		var v = at.get(k)
		if v == null:
			at[k] = i
			keys.append(k)
		elif v is int:
			at[k] = [v, i]
		else:
			v.append(i)
	keys.sort()
	for k in keys:
		var v = at[k]
		if v is int:
			var ob = objs[v]
			match kind[v]:   # 同 _se_draw（常见情形内联，省一次函数调用）
				0:
					draw_enemy(ob)
				5:
					var d0: float = fx_dim
					fx_dim = d0 * (lead_dim if ob.is_leader else mate_dim)
					ob.draw_body()
					fx_dim = d0
				6:
					ob[0].draw_extra(ob[1])
				4:
					g.knight.draw()
				2:
					draw_player()
				3:
					if not _dbg_ground:
						g.map.draw_sort_prop(ob)
		else:
			for i in v:
				_se_draw(objs[i], kind[i])
	objs.clear()
	return true


func _se_draw(ob, kd: int) -> void:
	match kd:
		0:
			draw_enemy(ob)
		5:
			var d0: float = fx_dim
			fx_dim = d0 * (lead_dim if ob.is_leader else mate_dim)
			ob.draw_body()
			fx_dim = d0
		6:
			ob[0].draw_extra(ob[1])
		4:
			g.knight.draw()
		2:
			draw_player()
		3:
			if not _dbg_ground:
				g.map.draw_sort_prop(ob)


## 敌人身上层（词条特效批、弱点菱形）→ 干员技能上层 → 护盾 → 无人机三遍（影子光晕 / 机体 / 核心）
func _draw_overlays_shield_drones() -> void:
	_afx_flush()
	for wm in weak_marks:
		var wpp: Vector2 = wm[0]
		var wcc: Color = wm[1]
		var t4 := [wpp + Vector2(0, -4.5), wpp + Vector2(4.5, 0), wpp + Vector2(0, 4.5), wpp + Vector2(-4.5, 0)]
		tb_quad(t4[0], t4[1], t4[2], t4[3], Color(0.02, 0.04, 0.08))
		for q in 4:
			tb_line(t4[q], t4[(q + 1) % 4], wcc, 1.0)
	weak_marks.clear()
	tb_flush()
	g.squad.draw_skill_over()
	draw_shield()
	# 无人机：影子 + 光晕一批 → 机体贴图（同贴图连续，自动合批）→ 核心亮点一批（性能 docs/50 §9 ②：原来每架 4 次绘制调用）
	for dr in g.drones:
		tb_circle(dr.pos + Vector2(0, 96), 9.0, Color(0, 0, 0, 0.35), 0.4, 14)
		tb_circle(dr.pos, 20.0, Color(0.5, 1.4, 0.8, 0.16), 1.0, 20)
	tb_flush()
	for dr in g.drones:
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
	for dr in g.drones:
		tb_circle(dr.pos + Vector2(0, 8), 3.0, Color(1.2, 2.6, 1.6, 0.6 + 0.3 * sin(g.t * 8.0)), 1.0, 8)
	tb_flush()


## 友方投射物：V6 帧条按速度方向旋转（程序只画拖尾）；没贴图的按种类程序画
func _draw_bullets() -> void:
	# 自己的投射物（render/declutter bullet_k / bullet_desat）：拥挤时略淡、略去饱和，让敌方弹幕更跳；缺省不变
	_bk = 0.0 if _dbg_friend else Dc.at("bullet_k", dcrowd)
	_bd = Dc.p("bullet_desat") * dcrowd
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
					g.draw_line(b.pos - n * 34.0, b.pos - n * 12.0, _bc(Color(1.6, 1.4, 1.0, 0.3)), 2.0)
				"fire":
					g.draw_circle(b.pos, 14.0, _bc(Color(1.4, 0.6, 2.2, 0.2)))
				"arcane":
					g.draw_line(b.pos - n * 20.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.35)), 4.0)
			g.vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), Game.PX, _bc(Color.WHITE))
			continue
		match b.kind:
			"arrow":
				g.draw_line(b.pos - n * 26.0, b.pos - n * 10.0, _bc(Color(1.6, 1.4, 1.0, 0.35)), 2.0)
				g.draw_line(b.pos - n * 14.0, b.pos + n * 4.0, _bc(Color(2.2, 2.0, 1.6)), 3.0)
			"fire":
				var fl := 1.0 + 0.2 * sin(g.t * 40.0 + b.pos.x)
				g.draw_circle(b.pos, 13.0 * fl, _bc(Color(2.0, 0.8, 0.2, 0.25)))
				g.draw_circle(b.pos, 8.0 * fl, _bc(Color(2.4, 1.1, 0.3, 0.8)))
				g.draw_circle(b.pos, 4.0, _bc(Color(2.8, 2.4, 1.4)))
			"arcane":
				g.draw_line(b.pos - n * 18.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.4)), 4.0)
				g.draw_circle(b.pos, 8.0, _bc(Color(1.2, 0.5, 2.0, 0.35)))
				UI.diamond(g, b.pos, 5.0, _bc(Color(1.8, 1.0, 2.6)), _bc(Color(2.2, 1.6, 2.8)))
			_:
				g.vfx.spr("orb", 1, 0, b.pos, Game.PX, false, _bc(Color.WHITE))


var _bk := 1.0
var _bd := 0.0


func _bc(c: Color) -> Color:
	if _bk >= 1.0 and _bd <= 0.0:
		return c
	var l: float = (c.r + c.g + c.b) / 3.0
	return Color(lerpf(c.r, l, _bd), lerpf(c.g, l, _bd), lerpf(c.b, l, _bd), c.a * _bk)


## g.fx 特效按 kind 逐个画（频闪 / 爆炸 / 地裂 / 光束 / Boss 换幕……）；fx_dim 只压友方特效；写进 tb 批的（gcrack / mote / mire_recoil）末尾一次提交
func _draw_fx() -> void:
	# 友方火花绘制预算（render/declutter spark_budget；缺省不限）：超出时跳过最早的（快淡完的），只影响绘制
	var skip_sparks := 0
	if spark_left < (1 << 29):
		var ns := 0
		for f in g.fx:
			if f.kind == "spark" and not f.get("enemy", false):
				ns += 1
		skip_sparks = maxi(0, ns - spark_left)
	for f in g.fx:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var foe: bool = f.get("enemy", false) or FOE_KINDS.has(f.kind)
		if (_dbg_foe and foe) or (_dbg_friend and not foe and not AMB_KINDS.has(f.kind)) or (_dbg_amb and AMB_KINDS.has(f.kind)):
			continue   # --clutterdbg 量测：这一层不画
		var fdim: float = 1.0 if f.get("enemy", false) else fx_dim   # 敌方特效不降噪（docs/48 ③）
		if fdim < 1.0 and DIM_KINDS.has(f.kind):
			a *= fdim
		if skip_sparks > 0 and f.kind == "spark" and not f.get("enemy", false):
			skip_sparks -= 1
			continue
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
				# op_hit：干员攻击 / 技能命中的装饰环（水月），render/hit_rings 缺省不画；其余（敌方、拾取、藏品……）照画
				if f.get("op_hit", false) and not Dc.hit_rings():
					continue
				var rr: float = f.r * (1.15 - a * 0.3)
				g.draw_arc(f.pos, rr, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.9), 4.0)
				g.draw_arc(f.pos, rr - 6.0, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.35), 2.0)
			"spark":
				g.draw_rect(Rect2(f.pos.round(), Vector2(f.sz, f.sz)), Color(f.col.r, f.col.g, f.col.b, a))
			"mote":
				# 光尘（docs/54）：进无贴图批，循环后随 tb_flush 一次提交；末段缩小淡出
				if g.vfx.p2:
					if f.get("em", false):
						# 余烬帧条 fx_ember（8×8 × 4：亮 → 暗红），按剩余寿命取帧，颜色照 mote 调制（docs/54 §6）
						var efr: int = clampi(int((1.0 - a) * 4.0), 0, 3)
						g.vfx.spr_rot("fx_ember", efr, f.pos, 0.0, Game.PX * f.sz * 0.5, Color(f.col.r, f.col.g, f.col.b, f.col.a))
						continue
					var mp: Vector2 = f.pos.round()
					var ms: float = f.sz * (0.5 + 0.5 * minf(1.0, a * 2.0))
					tb_quad(mp, mp + Vector2(ms, 0), mp + Vector2(ms, ms), mp + Vector2(0, ms), Color(f.col.r, f.col.g, f.col.b, f.col.a * minf(1.0, a * 1.5)))
			"mire_recoil":
				# 灯标点燃时被清掉的溟痕退散（docs/54）：每片一圈紫环向中心收缩、深色底渐隐，再一道从灯标推出去的淡光弧
				if g.vfx.p2 and f.get("tex", false):
					# 溟痕退散帧条 fx_mire_dissolve（64×64 × 6，和 terrain_mire 同尺寸：按判定半径 ×2.3 画）
					var mfr: int = clampi(int((1.0 - a) * 6.0), 0, 5)
					for c in f.pts:
						g.vfx.spr_rot("fx_mire_dissolve", mfr, c[0], 0.0, float(c[1]) * 2.3 / 64.0, Color(1.0, 1.0, 1.0, minf(1.0, a * 2.0)))
				elif g.vfx.p2:
					var k := 1.0 - a
					var gy: float = ground_y()
					for c in f.pts:
						var rr: float = float(c[1]) * (1.0 - pow(k, 0.7))
						if rr < 2.0:
							continue
						tb_circle(c[0], rr * 0.85, Color(0.1, 0.03, 0.14, 0.45 * a), gy, 12)
						tb_ring(c[0], rr, 2.5, Color(1.0, 0.6, 1.6, 0.8 * a), 20)
						tb_ring(c[0], rr * 0.55, 1.5, Color(1.6, 1.2, 2.0, 0.5 * a), 14)
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
				if not f.get("op_hit", false) or Dc.hit_rings():   # 干员法术弹（艾雅法拉熔岩弹）的冲击环：render/hit_rings 缺省不画，火光照画
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
				if g.tex.get("proj_knight_spear") != null:
					# Codex v14 脱手长枪（40×8 × 2 帧，水平枪尖朝右）：旋转由程序做，落地冰环照旧程序画
					# 贴图是深色钢枪，世界被灯光压暗后几乎看不见：按敌方特效惯例用 >1 的冰蓝调色提亮（同原来程序线段的颜色）
					g.vfx.spr_rot("proj_knight_spear", int(g.t * 12.0) % 2, p, ang, Game.PX, Color(1.7, 1.9, 2.3))
				else:
					var dv := Vector2.from_angle(ang) * 34.0
					g.draw_line(p - dv, p + dv, Color(0.1, 0.12, 0.2, 0.9), 6.0)
					g.draw_line(p - dv, p + dv, Color(1.4, 1.6, 1.9), 3.0)
					g.draw_circle(p + dv, 4.0, Color(1.6, 1.9, 2.2))
				if k > 0.9:
					var gk: float = (k - 0.9) / 0.1
					g.draw_arc(f.to, 10.0 + 30.0 * gk, 0.0, TAU, 20, Color(0.8, 1.2, 1.7, 1.0 - gk), 2.0)
			"tide_trail":
				var k := 1.0 - a
				g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.45))
				g.draw_circle(Vector2.ZERO, f.r * (0.7 + 0.5 * k), Color(0.3, 0.9, 1.0, 0.28 * a))
				g.draw_arc(Vector2.ZERO, f.r * (0.8 + 0.6 * k), 0.0, TAU, 24, Color(0.9, 1.6, 1.8, 0.6 * a), 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for q in 4:
					var ang: float = f.seed + q * 1.7
					g.draw_circle(f.pos + Vector2(cos(ang) * f.r * (0.6 + k), sin(ang) * f.r * 0.3 - 6.0 * k), 2.5 * a, Color(1.8, 2.0, 2.0, 0.8 * a))
			"glint":
				# 竖直闪光（换剑）：十字星从中间展开再收
				var k := 1.0 - a
				var L: float = 60.0 * sin(k * PI)
				g.draw_line(f.pos + Vector2(0, -L), f.pos + Vector2(0, L), Color(2.0, 2.0, 2.0, a), 3.0)
				g.draw_line(f.pos + Vector2(-L * 0.4, 0), f.pos + Vector2(L * 0.4, 0), Color(2.0, 2.0, 2.0, a), 2.0)
				g.draw_circle(f.pos, 6.0 * a, Color(2.0, 2.0, 2.0, a))
			"lob_shell":
				# 轰击炮弹（圣徒伊比利亚，docs/95 §6.2 C）：纯画面，从本体沿抛物线飞向落点圈心，地面画随高度缩放的阴影；Codex proj_saint_shell 缺图走程序圆弹
				var u: float = 1.0 - a
				var gp: Vector2 = f.a.lerp(f.b, u)
				var hgt: float = sin(u * PI) * clampf(f.a.distance_to(f.b) * 0.4, 60.0, 150.0)   # 弧高按射程：近处低抛，别钻到顶部 HUD 下面
				g.draw_circle(gp, 4.0 + 5.0 * u, Color(0.0, 0.0, 0.0, 0.25 + 0.3 * u))
				var sp: Vector2 = gp + Vector2(0, -hgt)
				var vang: float = (f.b - f.a).angle() - cos(u * PI) * 1.1 * signf((f.b - f.a).x + 0.001)
				if g.tex.get("proj_saint_shell") != null:
					g.vfx.spr_rot("proj_saint_shell", int(g.t * 8.0) % 2, sp, vang, Game.PX)
				else:
					g.draw_circle(sp, 10.0, Color(0.06, 0.04, 0.03))
					g.draw_circle(sp, 7.5, Color(1.7, 0.95, 0.45))
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
				if not f.get("op_spoke", false) or Dc.hit_spokes():   # 水花放射纹（render/hit_spokes 缺省不画），水花本体照画
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
			"gcrack":
				# 共用地裂（render/ground_crack.gd，和干员的 crack 同款）：第一次画时按落点生成并缓存；写进 tb 批，循环后统一提交
				if not f.has("cd"):
					f["cd"] = GroundCrack.build(f.pos, f.r, f.get("ang"), f.get("opts", {}))
				GroundCrack.draw(f.cd, f.max - f.life, a, f.col, _gc_sink, float(f.get("grow_t", 0.06)), float(f.get("hot", 1.0)))
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
				# 技能发动：放射光束（op_spoke = 干员发的，render/hit_spokes 缺省不画；晋升 / 宝箱 / 祭坛 / 藏品 / 敌方照画）
				if f.get("op_spoke", false) and not Dc.hit_spokes():
					continue
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
	tb_flush()   # gcrack 等写进 tb 批的特效在这里一次提交


## 敌方弹幕三遍（无贴图底 → 贴图 → 弹芯描边）+ Boss 刀刃 → 抛射碎石 → 冲击环
func _draw_ebullets_lobs_shocks() -> void:
	# 敌方弹幕分三遍画（性能 9/30：原来每颗子弹影子 / 底圈 / 光晕 / 贴图 / 描边交替，有贴图和无贴图来回切，每颗约 5 次绘制调用；
	# 分遍后同类连续提交能合批）：① 无贴图：影子椭圆、深色底圈、光晕；② 贴图：弹体；③ 无贴图：弹芯、亮描边
	var blades: Array = []
	for b in g.ebullets:
		if b.get("kind", "") == "boss_blade":
			blades.append(b)
			continue
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置（椭圆直接算顶点，不切画布变换）
		tb_circle(b.pos + Vector2(0, 2), b.r + 1.0, Color(0, 0, 0, 0.4), 0.45, 10)
		if _bullet_tex(b) != "":
			continue   # 专属弹体帧条（docs/96：漂移体侵蚀弹）自带 #080E18 描边，不垫底圈、不描洋红边
		var bp: Vector2 = b.pos + Vector2(0, -16)
		# 敌方弹幕高对比：深色外圈垫底，画完再描一圈亮洋红边，压在友方特效上也一眼看得出
		tb_circle(bp, b.r + 3.0, Color(0.02, 0.0, 0.05, 0.85))
		match b.get("kind", "orb"):
			"acid":
				tb_circle(bp, b.r + 5.0, Color(0.5, 1.4, 0.3, 0.3))
			"nova":
				tb_circle(bp, b.r + 5.0, Color(1.2, 0.4, 1.8, 0.3))
			"nerve":
				tb_circle(bp, b.r + 5.0, Color(1.0, 0.9, 0.3, 0.25))
			_:
				tb_circle(bp, b.r + 4.0, Color(1.0, 0.3, 0.6, 0.25))
	tb_flush()
	for b in g.ebullets:
		var kd: String = b.get("kind", "orb")
		var bp: Vector2 = b.pos + Vector2(0, -16)
		var btex: String = _bullet_tex(b)
		if btex != "":
			# 小怪专属弹体（enemies.json shot_tex，docs/96 第 1 批：漂移体 proj_skimmer_corrode）：朝右绘制、按速度方向旋转，帧率按 V6_FRAMES
			var bspec: Array = Game.V6_FRAMES[btex]
			g.vfx.spr_rot(btex, int(g.t * float(bspec[1]) + b.pos.x * 0.01) % int(bspec[0]), bp, b.vel.angle(), Game.PX)
		elif kd == "nerve" and g.tex.get("proj_floater_nerve") != null:
			# 浮海飘航者神经弹（V8 proj_floater_nerve，朝右绘制按速度方向旋转）
			g.vfx.spr_rot("proj_floater_nerve", int(g.t * 12.0 + b.pos.x * 0.01) % 4, bp, b.vel.angle(), Game.PX)
		elif kd == "acid" and g.tex.get("proj_acid") != null:
			g.vfx.spr("proj_acid", 2, int(g.t * 8.0 + b.pos.x * 0.01) % 2, bp, _hpx("proj_acid"), false, Color(1.5, 1.5, 1.5))   # Codex v14 酸团（暗橄榄，避开友方黄绿）；×1.5 提亮，压过地图暗环境光（原程序圆也是过曝色）
		elif kd == "nova" and g.tex.get("proj_nova") != null:
			g.vfx.spr("proj_nova", 4, int(g.t * 10.0 + b.pos.x * 0.01) % 4, bp, _hpx("proj_nova"), false, Color(1.5, 1.5, 1.5))   # Codex v14 新星弹；×1.5 提亮同上
		elif kd != "acid" and kd != "nova" and kd != "nerve" and kd != "boss_blade":
			g.vfx.spr("ebullet", 1, 0, bp, Game.PX * b.r / 5.0)
	for b in g.ebullets:
		var kd: String = b.get("kind", "orb")
		if kd == "boss_blade" or _bullet_tex(b) != "":
			continue
		var bp: Vector2 = b.pos + Vector2(0, -16)
		match kd:
			"acid":
				if g.tex.get("proj_acid") == null:
					tb_circle(bp, b.r, Color(0.6, 1.8, 0.4))
					tb_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6), 1.0, 6)
			"nova":
				if g.tex.get("proj_nova") == null:
					tb_circle(bp, b.r, b.get("col", Color(1.5, 0.6, 2.0)))
			"nerve":
				if g.tex.get("proj_floater_nerve") == null:
					tb_circle(bp, b.r, Color(1.8, 1.6, 0.5))
		tb_ring(bp, b.r + 2.0, 1.5, Color(2.4, 0.8, 1.8, 0.9))
	tb_flush()
	for b in blades:
		g.vfx.boss_blade(b, b.pos + Vector2(0, -16))
	# 抛射碎石 / 投嗣弹：落点预警 + 空中石块（投嗣育母投出的拟嗣：低弧，弹体 proj_mother_brood，缺图时 e_brood 基础帧缩小旋转）
	for l in g.lobs:
		var k: float = l.t / l.dur
		var brood: bool = l.get("kind", "") == "brood"
		# 抛石落点：地面椭圆（与判定一致）+ 深色描边 + 敌方洋红，不再乘亮度（docs/48 ①④）
		g.draw_set_transform(l.to, 0.0, Vector2(1.0, ground_y()))
		g.draw_circle(Vector2.ZERO, l.r * k, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, 0.22 * tell_fill))
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 4.0)
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 32, Color(ENEMY_TELL.r, ENEMY_TELL.g, ENEMY_TELL.b, 0.6 + 0.35 * sin(g.t * 20.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var gp: Vector2 = l.from.lerp(l.to, k)
		var hgt := sin(k * PI) * (80.0 if brood else 120.0)
		g.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rp := gp + Vector2(0, -hgt - 8.0)
		var ltex: String = str(l.get("tex", ""))
		if brood:
			var spin: float = k * TAU * 1.5 * (1.0 if l.to.x >= l.from.x else -1.0)   # 顺着飞行方向翻滚一圈半
			if g.tex.get("proj_mother_brood") != null:
				g.vfx.spr_rot("proj_mother_brood", int(g.t * 12.0 + l.from.x * 0.01) % 4, rp, spin, _hpx("proj_mother_brood"))
			else:
				var bt: Texture2D = g.tex.get("e_brood")
				if bt != null:
					var bw: float = bt.get_width() / 2.0
					var bh: float = float(bt.get_height())
					var bs: float = _hpx("e_brood") * 0.8
					g.draw_set_transform(rp + g.draw_off, spin, Vector2(bs, bs))
					g.draw_texture_rect_region(bt, Rect2(-Vector2(bw, bh) / 2.0, Vector2(bw, bh)), Rect2(0, 0, bw, bh), Color(1.15, 1.15, 1.15))
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					g.draw_circle(rp, 6.0, Color(0.85, 0.55, 0.75))
		elif ltex != "" and g.tex.get(ltex) != null:
			# 专属抛射物（enemies.json lob_tex，docs/96 第 1 批：喷吐者酸团 proj_spitter_acid 4 帧循环），沿同一条 lob 轨迹
			var lspec: Array = Game.V6_FRAMES[ltex]
			g.vfx.spr(ltex, int(lspec[0]), int(g.t * float(lspec[1])) % int(lspec[0]), rp, _hpx(ltex))
		elif g.tex.get("proj_rock_shard") != null:
			g.vfx.spr("proj_rock_shard", 4, int(g.t * 12.0) % 4, rp, _hpx("proj_rock_shard"))   # Codex v14 碎石（翻滚画在帧里）
		else:
			g.draw_circle(rp, 7.0, Color(0.45, 0.42, 0.4))
			g.draw_circle(rp + Vector2(-2, -2), 3.0, Color(0.7, 0.66, 0.6))
	# 冲击环（docs/48 全局 ④⑤、P0 伊祖米克）：原来写死成治疗同款的绿色、越扩越淡，到主控这里几乎看不见。
	# 改成敌方危险色：深色外描边 + 洋红紫主色 + 白芯，透明度下限 0.6，扩到最大也看得清
	for sh in g.shocks:
		var a: float = maxf(0.6, 1.0 - sh.r / sh.maxr)
		var tc: Color = sh.get("col", ENEMY_TELL)   # 缺口环（大群之歌）用 Boss 主题色，普通冲击环洋红
		g.draw_set_transform(sh.pos, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致（docs/48 ①）
		var gh: float = float(sh.get("gap_half", 0.0))
		var gaps: Array = sh.get("gaps", []) if gh > 0.0 else []
		if gaps.is_empty():
			g.draw_arc(Vector2.ZERO, sh.r - 8.0, 0.0, TAU, 48, Color(tc.r, tc.g, tc.b, 0.18 * a * tell_fill), 10.0)
			g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(0, 0, 0, 0.55 * a), 7.0)
			g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(tc.r, tc.g, tc.b, a), 4.0)
			g.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * a), 1.5)
		else:
			# 缺口环：按缺口切成几段弧画，缺口处不画，两侧亮色「出口」短线（docs/95 §12 song_ring；判定在 enemies.update）
			var starts: Array = []
			for ga in gaps:
				starts.append(fposmod(float(ga) + gh, TAU))
			starts.sort()
			for i in starts.size():
				var a0: float = starts[i]
				var a1: float = starts[(i + 1) % starts.size()] - gh * 2.0
				if a1 <= a0:
					a1 += TAU
				g.draw_arc(Vector2.ZERO, sh.r - 8.0, a0, a1, 32, Color(tc.r, tc.g, tc.b, 0.18 * a * tell_fill), 10.0)
				g.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(0, 0, 0, 0.55 * a), 7.0)
				g.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(tc.r, tc.g, tc.b, a), 4.0)
				g.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(1, 1, 1, 0.9 * a), 1.5)
			for ga in gaps:
				for side in [-1.0, 1.0]:
					var v := Vector2.from_angle(float(ga) + side * gh)
					g.draw_line(v * (sh.r - 16.0), v * (sh.r + 16.0), Color(0, 0, 0, 0.7), 5.0)
					g.draw_line(v * (sh.r - 16.0), v * (sh.r + 16.0), Color(1.0, 0.85, 0.35, 0.9), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 敌人出招提示 → 精英登场（docs/54 ④）→ 主控异常 → 预警轮廓 → 主控标记（压在所有敌方预警之上）
func _draw_tells_outlines() -> void:
	if not _dbg_foe:
		draw_enemy_tells()
	# docs/54 ④ 精英登场（按 e.age 画 0.9 秒；fx/first_sight 时改按首次入画起算；无贴图批，一次提交）
	if g.vfx.on("elite_entrance"):
		var elr: Rect2 = view_rect(120.0)
		for e in (_vis_ent if _vis_on else g.enemies):
			if e.elite and not e.boss and elr.has_point(e.pos) and g.vfx.elite_entrance_due(e):
				g.vfx.elite_entrance(e)
		tb_flush()
	draw_leader_ailments()
	if not _dbg_foe:
		draw_warn_outlines()
	# 主控标记（职业色细环 / 冲刺冷却弧 / 朝向）画在所有敌方预警之上：几十条预警叠在身上时也看得见自己在哪（协调人 1.1.1，干员拆出 draw_leader_mark）
	g.squad.draw_leader_mark()   # 内含手动普攻方向指示（draw_attack_dir，同一批）


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
		g.sprite.scale = Vector2(g.PX, g.PX) * float(g.ch.def.get("sprites", {}).get("draw_scale", 1.0)) if g.ch != null else Vector2(g.PX, g.PX)   # 干员整体缩放（docs/103：水月 0.9 试验，10-16）
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		# 脚底锚点：data/doctor.json 的 sprites.foot（旧 2 帧待机条为 45，编队美术第一批为 46）
		var foot_y: float = float(sp.get("foot", [24, 45])[1])
		g.sprite.offset = Vector2(0, -tx.get_height() / 2.0 + (tx.get_height() / A.hires_of(tx) - foot_y) * A.hires_of(tx))   # 帧高按贴图算（48 / 64 画布）
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
	if tx != null and tx.get_height() >= int(48.0 * A.hires_of(tx)):   # 48 / 64 画布都收；更小的是早期 32px 条
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
		g.sprite.scale = Vector2(g.PX, g.PX) * float(g.ch.def.get("sprites", {}).get("draw_scale", 1.0)) if g.ch != null else Vector2(g.PX, g.PX)   # 干员整体缩放（docs/103：水月 0.9 试验，10-16）
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		var hi48 := A.hires_of(tx)
		var fy48: float = float(g.ch.def.get("sprites", {}).get("foot", [0, tx.get_height() / hi48 - 2.0])[1]) if g.ch != null else tx.get_height() / hi48 - 2.0
		g.sprite.offset = Vector2(0, -tx.get_height() / 2.0 + (tx.get_height() / hi48 - fy48) * hi48)   # 脚底读 json（48 画布 = 帧底上 2 像素，同旧版）
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
	if e.phase == 2:
		var sa := _boss_warn_strip(e, ["song_ring"], "e_ishar_t_sing", 4)   # 大群之歌（docs/95 §2.4，Codex 第 1 批；缺图走下面的攻击帧）
		if not sa.is_empty():
			return sa
	if e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0:
		return {"name": base + "_attack", "frames": 4, "frame": clampi(int((1.0 - e.pose / e.pose_max) * 4.0), 0, 3)}
	if g.t < float(e.get("atk_until", 0.0)):
		return {"name": base + "_attack", "frames": 4, "frame": 2 if e.atk_until - g.t > 0.1 else 3}
	if g.t < float(e.get("mv_until", 0.0)):
		return {"name": base + "_move", "frames": 4, "frame": int(g.t * 5.0) % 4}
	return {"name": base, "frames": 2, "frame": int(g.t * 2.0) % 2}


## V13 Boss 帧条的逻辑帧（播放时机见 art/requests/v13_codex_boss_p2.md）；不适用时返回空字典，沿用原帧条。只换画面
## vfx.spr 不处理 @2x（调用方自己除密度）；Codex v14 道具 / 弹体都带 @2x，按同一逻辑尺寸画
func _hpx(name: String) -> float:
	return Game.PX / A.hires_of(g.tex.get(name))


## 敌方直线弹的专属弹体帧条名（enemy_ai.shoot 按 enemies.json 的 shot_tex 写进 b.tex）；没有或缺图返回 ""（走原程序画法）
func _bullet_tex(b: Dictionary) -> String:
	var tn: String = str(b.get("tex", ""))
	if tn == "" or g.tex.get(tn) == null:
		return ""
	return tn


func boss_strip_animation(e: Dictionary) -> Dictionary:
	var pk: float = float(e.get("pose", 0.0)) / maxf(0.01, float(e.get("pose_max", 1.0)))
	var winding: bool = e.get("wind", 0.0) > 0.0
	var posing: bool = e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0
	match e.type:
		"carmen", "iberia":
			# 圣徒两档共用一套挂点（V15：卡门 e_saint*、伊比利亚 e_saint_dark*，按 e.tex 取）：
			# 炮身近战（sword_t）出招：蓄力 f0 → f1，挥击 f2、收回 f3；装弹读条（channel）循环；射击：蓄力 f0 → f1，开火 f2、复位 f3
			if e.type == "iberia":
				var lb := _boss_warn_strip(e, ["lob"], "e_saint_dark_lob", 4)   # 轰击（docs/95 §6.4）：f0 抬炮口 → f1 后坐蓄力，结算 f2 出手、f3 放下
				if not lb.is_empty():
					return lb
			elif _lazy_tex("e_carmen_spin") != null:
				# 环射（docs/95 §7.4）：预警段 f0 平举；结算后 0.42 秒内 f1–f5（f1 / f3 / f5 三个出手帧，身体依次转向）
				for w in g.warns:
					if w.act == "pattern_ring" and not w.done and is_same(w.owner, e):
						return {"name": "e_carmen_spin", "frames": 6, "frame": 0}
				var sla = e.get("last_act")
				if sla is Dictionary and str(sla.get("act", "")) == "pattern_ring" and g.t - float(sla.get("t", -1.0)) < 0.42:
					return {"name": "e_carmen_spin", "frames": 6, "frame": clampi(1 + int((g.t - float(sla.t)) / 0.084), 1, 5)}
			var seg: int = (0 if pk > 0.5 else 1) if winding else (2 if e.pose > 0.17 else 3)
			if e.get("sword_t", 0.0) > 0.0 and posing:
				return {"name": e.tex + "_melee", "frames": 4, "frame": seg}
			if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
				return {"name": e.tex + "_reload", "frames": 4, "frame": int(g.t * 6.0) % 4}
			if posing:
				return {"name": e.tex + "_attack", "frames": 4, "frame": seg}
		"izumik":
			# 学习期（phase 1）扎根：进学习期先播 f0–f1 一次，之后 f2–f3 循环；地波蓄力按进度 f0 → f2，结算释放 f3
			if e.phase == 1 and e.has("learn_t"):
				var el: float = float(e.get("count_max", 20.0)) - float(e.learn_t)
				var f3: int = mini(int(el * 6.0), 1) if el < 0.34 else 2 + int(g.t * 3.0) % 2
				return {"name": "e_izumik_rooting", "frames": 4, "frame": f3}
			# 分享 e_izumik_share（docs/95 §3.4，Codex 第 1 批：水母收缩 / 舒展）：预警 f0 收缩 → f1 鼓起，结算 f2 喷涌、f3 回落；学习期的小分享也用它
			var za := _boss_warn_strip(e, ["sweep"], "e_izumik_share", 4)
			if not za.is_empty():
				return za
			for w in g.warns:
				if w.act == "izu_wave" and not w.done and is_same(w.owner, e):
					return {"name": "e_izumik_attack", "frames": 4, "frame": clampi(int(float(w.t) / maxf(0.01, float(w.dur)) * 3.0), 0, 2)}
			if posing and not winding:
				return {"name": "e_izumik_attack", "frames": 4, "frame": 3}
		"path":
			# 震地 / 分形塑路共用 e_path_slam（docs/95 §5.4：f0 刃肢高举 → f1 压低随预警进度，结算 f2 劈地、f3 回弹）；缺图沿用原帧条
			var ps := _boss_warn_strip(e, ["slam", "sweep"], "e_path_slam", 4)
			if not ps.is_empty():
				return ps
			# 冲撞预警段播 f0 → f1（冲出后的 f2 / f3 走现成的 _charge 挂点）
			if e.get("dash_t", 0.0) <= 0.0:
				for w in g.warns:
					if w.act == "dash" and not w.done and is_same(w.owner, e):
						return {"name": "e_path_charge", "frames": 4, "frame": 0 if float(w.t) < float(w.dur) * 0.5 else 1}
		"bishop", "archon", "immortal":
			# 接潮三体（docs/95 §8.4 / §9.4 / §10.4，Codex 第 3 批）：出招帧条随预警进度 f0 → f1、结算 f2 / f3；缺图沿用原帧条
			var tacts: Array = {"bishop": ["pillar", "pattern_ring", "pattern_fan", "tide_link"], "archon": ["sweep", "breath"], "immortal": ["stab", "erupt"]}[e.type]
			var ta := _boss_warn_strip(e, tacts, "e_%s_attack" % e.type, 4)
			if not ta.is_empty():
				return ta
		"paranoia":
			# Codex 第 1 批（docs/95 §1.4）：一阶段凝视 / 叠影蓄力 e_paranoia_gaze（f0 睁眼 → f1 前倾，f2 出手在结算后 0.2 秒、f3 收势）；
			# 二阶段呼号 e_paranoia_phase2_howl（f0 张口 → f1 吸气，f2 出手、f3 收口）。缺图沿用原帧条
			var pa := _boss_warn_strip(e, ["beam", "burst"], "e_paranoia_gaze", 4) if e.phase == 1 else _boss_warn_strip(e, ["sweep"], "e_paranoia_phase2_howl", 4)
			if not pa.is_empty():
				return pa
	return {}


## Codex 出招帧条的通用挂点（docs/95 第 1 批，4 帧单次：f0 → f1 蓄力随预警进度，结算后 0.2 秒内 f2 出手、再 0.2 秒 f3 收势）：
## 这只 Boss 有 acts 里任一招的预警在进行就播蓄力帧；刚结算就播出手 / 收势帧；贴图缺失或都不满足返回空
func _boss_warn_strip(e: Dictionary, acts: Array, strip: String, frames: int) -> Dictionary:
	if _lazy_tex(strip) == null:
		return {}
	for w in g.warns:
		if not w.done and is_same(w.owner, e) and acts.has(str(w.act)) and w.get("lock", true):
			return {"name": strip, "frames": frames, "frame": 0 if float(w.t) < float(w.dur) * 0.5 else 1}
	var la = e.get("last_act")
	if la is Dictionary and acts.has(str(la.get("act", ""))):
		var since: float = g.t - float(la.get("t", -1.0))
		if since < 0.4:
			return {"name": strip, "frames": frames, "frame": 2 if since < 0.2 else 3}
	return {}


## 骑士冲锋形态 / 插枪帧（逻辑帧选择不依赖 draw 次数）；不适用时返回空字典，沿用原帧条
func knight_animation(e: Dictionary) -> Dictionary:
	if e.get("dash_t", 0.0) > 0.0:
		return {"name": "e_knight_charge_form", "frames": 4, "frame": int(g.t * 10.0 + e.id * 0.37) % 4}
	for w in g.warns:
		if w.done or not is_same(w.owner, e):
			continue
		var wk: float = float(w.t) / maxf(0.01, float(w.dur))
		if w.act == "frost":
			return {"name": "e_knight_plant", "frames": 4, "frame": clampi(int(wk * 3.0), 0, 2)}
		# Codex 第 1 批（docs/95 §4.4）：长枪回旋 e_knight_spin（f0 收枪、f1 拧转蓄力；f2–f4 扫过在结算时播）、连刺第 3 段前刺 e_knight_thrust f0；缺图沿用原帧条
		if w.act == "spin_ring" and _lazy_tex("e_knight_spin") != null:
			return {"name": "e_knight_spin", "frames": 6, "frame": 0 if wk < 0.5 else 1}
		if w.act == "bite" and w.get("thrust", false) and wk > 0.6 and _lazy_tex("e_knight_thrust") != null:
			return {"name": "e_knight_thrust", "frames": 3, "frame": 0}
	var la = e.get("last_act")
	if la is Dictionary:
		var since: float = g.t - float(la.get("t", -1.0))
		match str(la.get("act", "")):
			"frost":
				if since < 0.45:
					return {"name": "e_knight_plant", "frames": 4, "frame": 3}
			"spin_ring":
				if since < 0.35 and _lazy_tex("e_knight_spin") != null:
					return {"name": "e_knight_spin", "frames": 6, "frame": clampi(2 + int(since / 0.0833), 2, 5)}
			"bite":
				if since < 0.22 and la.get("thrust", false) and _lazy_tex("e_knight_thrust") != null:
					return {"name": "e_knight_thrust", "frames": 3, "frame": 1 if since < 0.12 else 2}
	return {}


## 囊海爬行者破膜帧条（enemies.json burst_fx = "fx_pocket_burst" → _back / _front，6 帧 16fps）：当前帧号，没在播 / 缺图 / 没配返回 -1。
## 时间从 enemies.gd 爆发那一刻写的 burst_fx_t 算（纯画面字段）；同一帧号给两层
const BURST_FX_FRAMES := 6
const BURST_FX_FPS := 16.0

func _burst_fx_frame(e: Dictionary) -> int:
	var t0: float = float(e.get("burst_fx_t", -9.0))
	if t0 < 0.0 or g.t - t0 >= BURST_FX_FRAMES / BURST_FX_FPS:
		return -1
	var bn: String = str(D.ENEMIES.get(e.type, _NO_DEF).get("burst_fx", ""))
	if bn == "" or g.tex.get(bn + "_back") == null or g.tex.get(bn + "_front") == null:
		return -1
	return clampi(int((g.t - t0) * BURST_FX_FPS), 0, BURST_FX_FRAMES - 1)


## 破膜的一层：48×40、原点 (24,28)（归一化 (0.5, 0.7)）对齐脚底 bpos，按本体缩放（不含 @2x 密度）、随本体翻转
func _burst_fx_layer(e: Dictionary, layer: String, frame: int, bpos: Vector2, flip: bool) -> void:
	var bn: String = str(D.ENEMIES.get(e.type, _NO_DEF).get("burst_fx", "")) + layer
	g.vfx.spr(bn, BURST_FX_FRAMES, frame, bpos, enemy_scale(e) / A.hires_of(g.tex.get(bn)), flip, Color.WHITE, Vector2(0.5, 0.7))


func enemy_scale(e: Dictionary) -> float:
	return D.enemy_scale(e, g.t, Game.PX)   # 纯函数在 data.gd（docs/101 B1：模拟侧直接调它，不经 render）


## 敌人画法缓存（docs/50 §9.9，2026-10-01，第 0 步实测稳态普通怪「选帧 + 算色」每帧约 2.2 毫秒、参数变化率 11.8%）：
## 能缓存的敌人把「贴图名 / 帧数 / 帧率 / 颜色 / 缩放 / 锚点偏移 / 描边开关」存在 e.dc，签名变了才重算（_dc_compute）；
## 帧号（同一表达式按 g.t 算）、翻转、击退偏移、白闪、描边透明度（随 ecrowd 连续变）、词条、弱点每帧照算（_dc_emit）。
## 不进缓存、走 _draw_enemy_full 原路径（_dc_ok）：Boss、宝箱、部件、潜地、骑士（专用帧条）、DC_SKIP_TYPES，
## 以及正在受击形变 / 蓄力 / 冲刺 / 鼓胀 / 唤醒 / 狂暴 / 阶段护盾 / 空中 / 剑光 / 装填跪地 / 出招姿态 / 攻击帧窗口 / 灯边硬直（bstag，docs/56 §10）里的敌人。
## 签名（e.dc[0..7]）：moving、stun > 0、coma、invuln、dormant、e.r、[6]、[7] 两位恒为 false（原为普通怪 / 精英描边的 outline_skip、ol_norm，10-15 随旧写法删掉，保留下标免得改缓存格式）。
## 以后给敌人加会影响画面的新状态：要么加进 _dc_ok 的排除条件，要么加进签名；--dccheck（快检冒烟开着）会抓漏。
const DC_SKIP_TYPES := ["carmen", "iberia", "izumik", "path", "ishar", "paranoia"]

var _no_flash: bool = Look.dbg("noflash") != ""
var _act_mod := Color.WHITE   # 当前这只敌人的受光封顶缩放（Look.actor_mod；_espr 乘在本体 / 白闪上，描边不乘）

func draw_enemy(e: Dictionary) -> void:
	if _am_mode == 3:
		_act_mod = Look.actor_mod_lut(e.pos)
	elif _am_mode == 2:
		_act_mod = Look.actor_mod_at(e.pos)
	elif _am_mode == 1:
		_act_mod = Color.WHITE
	else:
		_act_mod = Look.actor_mod(g, e.pos)
	if not dc_on or not _dc_ok(e):
		_draw_enemy_full(e)
		return
	# 移动判定写回（和 _draw_enemy_full 同一段，每帧都要做）
	if e.tex_move:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = g.t + 0.2
		e.dpos = e.pos
	var moving: bool = e.tex_move and g.t < e.mv_until and e.stun <= 0.0 and not e.coma
	var c = e.get("dc")
	if c == null or c[0] != moving or c[1] != (e.stun > 0.0) or c[2] != e.coma or c[3] != e.invuln or c[4] != e.dormant or c[5] != e.r or c[6] != false or c[7] != _ol_sig():
		c = _dc_compute(e, moving)
		e["dc"] = c
	if dc_check and (e.id + Engine.get_process_frames()) % 8 == 0:
		_dc_verify(e, c)
	_dc_emit(e, c)


## 受光封顶模式（Look.actor_mod_begin；只在排序层里非 0）
var _am_mode := 0

## 缓存路径的排除条件（docs/39 §8）。Boss / 宝箱 / 骑士帧条 / DC_SKIP_TYPES 这几项开局后不会变（boss、chest、tex、type 只在生成时写），
## 第一次判过记在 e.dcs，以后只查会变的状态（docs/50 §14 OPT_EDRAW 的快速写法；10-15 删掉逐项全判的旧版，docs/101 S2）
func _dc_ok(e: Dictionary) -> bool:
	var st = e.get("dcs")
	if st == null:
		st = e.boss or e.chest or e.tex == "e_knight" or e.type in DC_SKIP_TYPES
		e["dcs"] = st
	if st:
		return false
	if e.squash > 0.0 or e.wind > 0.0 or e.dash_w > 0.0 or e.dash_t > 0.0 or e.enraged or e.wake_t > 0.0:
		return false
	if e.nova_w > 0.0 or e.blast_w > 0.0 or e.burst_w > 0.0 or e.air > 0.0 or e.pose > 0.0:
		return false
	if e.get("part", false) or e.get("under", false) or e.get("gate_hold", false) or e.get("sword_t", 0.0) > 0.0 or e.get("break_t", 0.0) > 0.0:
		return false
	if e.get("bstag", 0.0) > 0.0 or float(e.get("hatch_until", 0.0)) > g.t:
		return false
	if e.tex_attack and (g.t < e.atk_until or e.get("attack_preparing", false) or float(e.get("shot_wind_until", 0.0)) > g.t):
		return false
	if g.t - float(e.get("burst_fx_t", -9.0)) < BURST_FX_FRAMES / BURST_FX_FPS:
		return false   # 囊海爬行者破膜帧条在播（docs/96 §1.3）：本体前后各一层，走原路径
	return true



## 缓存内容：[0..7] 签名，[8] 贴图名，[9] 帧数，[10] 帧率，[11] 颜色，[12] 缩放（已除高清倍率），[13] 锚点，[14] 相对 e.pos 的偏移，
## [15] 画不画描边，[16] 白剪影名。每一项都按 _draw_enemy_full 里的同一段代码算（只保留能缓存的敌人会走到的分支）
func _dc_compute(e: Dictionary, moving: bool) -> Array:
	var name: String = e.tex
	if e.coma and e.tex_feign:
		name = name + "_feign"
	var frames := 2
	var fps := 5.0
	if moving and g.tex.get(name + "_move") != null:
		name += "_move"
		frames = 4
		fps = float(D.ENEMIES.get(e.type, {}).get("move_fps", 6.0))
		if e.type == "immortal":
			fps = 8.0
	if e.dormant and g.tex.get(e.tex + "_dormant") != null:
		name = e.tex + "_dormant"
		frames = 2
		fps = 3.0
	var sc: float = enemy_scale(e)
	var col: Color = D.ENEMIES.get(e.type, {}).get("tint", Color.WHITE)
	if e.evo:
		col = col * Color(1.0, 0.62, 0.68)
	if e.invuln:
		col = Color(0.7, 0.85, 1.0, 0.75)
	if e.stun > 0.0:
		col = col * Color(0.65, 0.75, 1.0)
	var anc := Vector2(0.5, 0.5)
	var off := Vector2.ZERO
	if g.foot_anchor.has(e.tex):
		anc = Vector2(0.5, 1.0)
		off = Vector2(0, (31.0 if e.type == "ishar" else e.r) * 0.8 + 3.0 * Game.PX)
	if g.tex.get(name) == null and not g.tex_deferred.is_empty():
		g.tex_deferred_miss(name)   # 网页版推迟加载漏网：记日志并补读
	var hr: float = A.hires_of(g.tex.get(name)) if g.tex.get(name) != null else 1.0
	if hr > 1.0:
		sc /= hr
	var ol: bool = g.tex.has(name + "_white") and _rim_on(e)
	var ra = atlas.reg.get(name) if atlas != null else null   # [17] / [18]：图集里的本体 / 白剪影区域（docs/50 §12 B），不在图集里为 null
	var rw = atlas.reg.get(name + "_white") if atlas != null else null
	return [moving, e.stun > 0.0, e.coma, e.invuln, e.dormant, e.r, false, _ol_sig(),
		name, frames, fps, col, sc, anc, off, ol, name + "_white", ra, rw]


## 缓存签名第 [7] 项：旧写法的普通怪描边开关 + 精英冷色描边开关（任一变了缓存作废）
func _ol_sig() -> int:
	return 2 if elite_rim > 0.0 else 0


## 这只敌人画不画精英冷色描边
func _rim_on(e: Dictionary) -> bool:
	return elite_rim > 0.0 and e.elite and not e.boss


## 描边颜色：精英冷色描边开着时用冷青（旧写法 ol_norm 下的橙红只在旋钮关时保留）；普通怪中性淡紫白
func _ol_col(e: Dictionary) -> Color:
	if e.elite:
		return elite_rim_col if _rim_on(e) else Color(3.2, 1.1, 0.7, 0.75)
	var oc := Color(2.2, 2.0, 2.6, 0.5)
	oc.a *= ol_mul
	return oc


## 按缓存发绘制：和 _draw_enemy_full 末段同序（描边 → 本体 → 白闪 → 词条 → 弱点）
func _dc_emit(e: Dictionary, c: Array) -> void:
	var frames: int = c[9]
	var frame: int = int(g.t * float(c[10]) + e.id * 0.37) % frames
	g.draw_off = _eoff(e)
	var flip: bool = e.fx < 0.0
	var bpos: Vector2 = e.pos + c[14]
	var sc: float = c[12]
	var anc: Vector2 = c[13]
	if c[15]:
		_espr_outline(c[8], frames, frame, bpos, sc, flip, _ol_col(e), anc, Vector2.ONE)
	var ra = c[17]
	if ra != null and _afast and _rec == null:
		# 图集快速路径（docs/50 §12 B）：本体和白闪直接按缓存的图集区域画，几何与 vfx.spr 相同；翻转时两次绘制共用一对变换
		var fw: int = ra[2] / frames
		var o: Vector2i = ra[1]
		var src := Rect2(o.x + fw * frame, o.y, fw, ra[3])
		var size := Vector2(fw, ra[3]) * sc
		var p: Vector2 = bpos + g.draw_off
		var rw = c[18] if e.flash > 0.0 else null
		if flip:
			g.draw_set_transform(p.round(), 0.0, Vector2(-1, 1))
			var rf := Rect2(-size * anc, size)
			g.draw_texture_rect_region(ra[0], rf, src, c[11] * _act_mod)
			if rw != null:
				g.draw_texture_rect_region(rw[0], rf, src, Color(1, 1, 1, 0.9 if e.elite else flash_a) * _act_mod)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var rn := Rect2((p - size * anc).round(), size)
			g.draw_texture_rect_region(ra[0], rn, src, c[11] * _act_mod)
			if rw != null:
				g.draw_texture_rect_region(rw[0], rn, src, Color(1, 1, 1, 0.9 if e.elite else flash_a) * _act_mod)
	else:
		_espr(c[8], frames, frame, bpos, sc, flip, c[11], anc, Vector2.ONE)
		if e.flash > 0.0:
			_espr(c[16], frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9 if e.elite else flash_a), anc, Vector2.ONE)
	if _rec == null and e.affix != "":
		var af: String = e.affix
		if af == "armor" or (af == "shield" and e.shield_hp > 0.0):   # 快速写法：_affix_fx 对其他词条直接返回，先判再算头顶位置
			_affix_fx(e, bpos, _enemy_top(e))
	var wk: String = e.weak
	if _rec == null and wk != "":
		var wc := Color(1.0, 0.75, 0.3) if wk == "物理" else (Color(0.7, 0.55, 1.0) if wk == "法术" else Color(1.0, 0.5, 0.8))
		var wp: Vector2 = e.pos + Vector2(e.r * 0.8 + 6.0, -e.r - 4.0)
		weak_marks.append([wp, wc])
	g.draw_off = Vector2.ZERO


## 贴图绘制的包装：--dccheck 比对时只记参数（含 draw_off，vfx.spr / _spr_outline 会加上它），平时直接画
func _espr(name: String, frames: int, frame: int, pos: Vector2, sc: float, flip: bool, col: Color, anc: Vector2, sq: Vector2) -> void:
	if _no_flash and name.ends_with("_white"):
		return   # --lookdbg=noflash：量受击闪白对「白灰」的贡献
	if _rec != null:
		_rec.append(["b", name, frames, frame, pos + g.draw_off, sc, flip, col * _act_mod, anc, sq])
		return
	if _dbg_enemy:
		col.a = 0.0   # --clutterdbg=noenemy（量测）
	if atlas != null:
		var r = atlas.reg.get(name)
		if r != null:
			EnemyAtlas.spr(g, r, frames, frame, pos + g.draw_off, sc, flip, col * _act_mod, anc, sq)
			return
	g.vfx.spr(name, frames, frame, pos, sc, flip, col * _act_mod, anc, sq)


## 普通怪 / 精英帧条图集（docs/50 §12 B）：开局贴图载完后建一次。Boss（大帧条、网页版推迟加载）和骑士（专用帧条）不进；
## 无头模式不画，不建。进图集的帧条：本体、_move / _attack 等变体、休眠 / 唤醒 / 狂暴 / 假死，各自连同白剪影
func build_enemy_atlas() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var t0 := Time.get_ticks_usec()
	var names: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if str(d.get("role", "")) == "boss" or d.get("boss", false) or d.tex == "e_knight" or k in DC_SKIP_TYPES:
			continue
		var base: String = d.tex
		for sfx in ["", "_feign", "_dormant", "_awaken", "_enraged", "_swell"] + Game.ENEMY_SUFFIXES:   # _swell：囊海爬行者鼓胀帧条（docs/96 §1.3）
			if sfx == "_death" or names.has(base + sfx):
				continue
			if g.tex.get(base + sfx) != null:
				names.append(base + sfx)
	EnemyAtlas.xform_flip = not Cfg.dev_args().has("--atlasflip=neg")
	atlas = EnemyAtlas.new()
	atlas.build(g.tex, names)
	if atlas.reg.is_empty():
		atlas = null
		return
	if Cfg.dev_args().has("--atlasinfo"):
		print("ENEMY_ATLAS strips=%d/%d size=%s px=%d ms=%.1f pop_strips=%d pop_ms=%.1f" % [atlas.n_strips, names.size(), str(atlas.tex_body.get_size()), atlas.px_used, (Time.get_ticks_usec() - t0) / 1000.0, A.pop_n, A.pop_ms])


func _espr_outline(name: String, frames: int, frame: int, pos: Vector2, sc: float, flip: bool, col: Color, anc: Vector2, sq: Vector2) -> void:
	if _rec != null:
		_rec.append(["o", name, frames, frame, pos + g.draw_off, sc, flip, col, anc, sq])
		return
	if _dbg_enemy:
		col.a = 0.0
	_spr_outline(name, frames, frame, pos, sc, flip, col, anc, sq)


## --dccheck：同一只敌人分别走原路径和缓存路径（只记参数、不画），两边的贴图绘制序列必须完全一致；
## 另外用当前状态重算一遍缓存，和存着的比（抓「签名漏了某个字段、缓存过期」）。不一致报 SCRIPT ERROR
func _dc_verify(e: Dictionary, c: Array) -> void:
	dc_checked += 1
	var off0: Vector2 = g.draw_off
	_rec = []
	_draw_enemy_full(e)
	var full: Array = _rec
	_rec = []
	_dc_emit(e, c)
	var cached: Array = _rec
	_rec = null
	g.draw_off = off0
	var bad := 0
	if full != cached:
		bad += 1
		push_error("敌人画法缓存与原路径不一致（docs/50 §9.9）：%s id=%d 原=%s 缓存=%s" % [e.type, e.id, str(full), str(cached)])
	var fresh := _dc_compute(e, c[0])
	if fresh != c:
		bad += 1
		push_error("敌人画法缓存过期（签名漏了会影响画面的字段，docs/50 §9.9）：%s id=%d 存=%s 现=%s" % [e.type, e.id, str(c), str(fresh)])
	# 计数进 BALANCE（prof 段，不开 --prof 也写）：快检冒烟断言 dc_checked > 0、dc_bad == 0（tools/check.py dc_errors）
	g.prof["dc_checked"] = dc_checked
	g.prof["dc_bad"] = int(g.prof.get("dc_bad", 0)) + bad


func _draw_enemy_full(e: Dictionary) -> void:
	if float(e.get("hatch_until", 0.0)) > g.t:
		return   # 注亡拟嗣落地展开中（enemies/shot_pool._brood_land）：本体由 fx_brood_land 帧条代画
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
		if g.t < e.mv_until and e.stun <= 0.0 and e.get("bstag", 0.0) <= 0.0 and not e.coma and g.tex.get(name + "_move") != null:
			name += "_move"
			frames = 4
			var fps: float = float(D.ENEMIES.get(e.type, _NO_DEF).get("move_fps", 6.0))
			if e.type == "reaper" and e.enraged:
				fps *= 1.45
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
	var ed: Dictionary = D.ENEMIES.get(e.type, _NO_DEF)
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
	var rage_fx: bool = e.get("enraged", false) and e.type != "reaper"   # 收割者的狂奔保持冷蓝本色；波纹另画。
	# 巢涌者神经光环改到地面层画（draw_nest_auras），不再按 4.6 倍放大帧条盖在实体上
	# 染色复用贴图的敌人（巨海、撕裂者、潜地者、吐酸者）按自身半径放大：enemies.json 的 draw_scale（docs/48 §1 第 7 项）
	var sc: float = enemy_scale(e)
	var col: Color = ed.get("tint", Color.WHITE)
	if e.evo:
		col = col * Color(1.0, 0.62, 0.68)
	var t2 = e.get("tint2")
	if t2 is Color:
		col = col * t2   # Boss 二阶段常驻低幅度着色（docs/95 §0.2 ②；bosses/*.gd _tint2 写、帧条不改）
	if e.type == "paranoia" and e.phase == 2:
		# 偏执泡影二阶段：e_paranoia2 和一阶段几乎一样（新图已下单 v12），过渡期在画面层区分——
		# 整体偏洋红、体量 ×1.1、身周一圈扭动的洋红光晕
		# V13 终稿已是洋红配色、落地破壳、体量 ×1.10（自带），不再程序染色、放大或加光晕（10-01）
		pass
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
	if e.stun > 0.0 or e.get("bstag", 0.0) > 0.0:   # 灯边硬直（docs/56 §10）复用眩晕的偏蓝
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
		if g.tex.get(e.tex + "_swell") != null:
			# 囊海爬行者鼓胀（Codex docs/96 §1.3 e_pocket_swell）：10fps 不循环，播到 f3 后停住直到 0.8 秒蓄压结束；
			# 首帧 = 本体 f0，鼓胀画在帧里，不再程序放大 / 提亮本体；范围圈仍在覆盖层画（draw_enemy_tells）
			name = e.tex + "_swell"
			frames = 4
			frame = clampi(int((float(e.get("burst_dur", 0.8)) - e.burst_w) * 10.0), 0, 3)
		else:
			# 囊海爬行者鼓胀：爆发范围预警圈从小到大，本体变亮
			var bk: float = 1.0 - e.burst_w / 0.4
			# 范围圈改在覆盖层画（draw_enemy_tells），这里只留本体变亮
			col = col.lerp(Color(2.2, 1.4, 2.6), bk * 0.7)
	g.draw_off = _eoff(e)
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
	# 最后的骑士 / 敌对骑士的专用帧条（Codex boss_p1，docs/archive/38_boss_p1_art_handoff）：冲锋途中换 e_knight_charge_form 循环（原来被出招姿态盖成攻击帧），
	# 寒冰领域插枪换 e_knight_plant（预警期间举枪 → 落枪，结算后枪尖触地一拍；原来用攻击帧定格）。只换画面，判定和时序不动
	if e.tex == "e_knight":
		var ka := knight_animation(e)
		if not ka.is_empty() and _lazy_tex(ka.name) != null:
			name = ka.name
			frames = ka.frames
			frame = ka.frame
	# Codex V13 Boss 帧条（art/requests/v13_codex_boss_p2.md）：卡门斩击 / 伊比利亚射击与装填 / 伊祖米克地波蓄力与扎根 / 塑路者冲撞预警段
	var ba := boss_strip_animation(e)
	if not ba.is_empty() and g.tex.get(ba.name) != null:
		name = ba.name
		frames = ba.frames
		frame = ba.frame
	if e.type == "ishar":
		var ia := ishar_animation(e)
		if _lazy_tex(ia.name) != null:
			name = ia.name
			frames = ia.frames
			frame = ia.frame
	# @2x 高清帧条（伊莎玛拉变身形态有 @2x）：同一逻辑尺寸，按密度减半
	if g.tex.get(name) == null and not g.tex_deferred.is_empty():
		g.tex_deferred_miss(name)   # 网页版推迟加载漏网：记日志并补读
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
			_spr_outline(name, frames, frame, bpos, sc, flip, Color(PART_COL.r * 2.0, PART_COL.g * 2.0, PART_COL.b * 2.0, 0.8), anc, sq)
	# 描边只给 Boss 和部件（docs/50 §12 A：普通怪 / 精英取消描边，少一层贴图切换）
	# 精英冷色描边（render/elite_rim）不受「Boss 轮廓光」开关影响
	if g.tex.has(name + "_white") and ((Cfg.outline and (e.boss or e.get("part", false))) or _rim_on(e)):
		var oc := Color(2.2, 2.0, 2.6, 0.5) if not e.elite else (elite_rim_col if _rim_on(e) else Color(3.2, 1.1, 0.7, 0.75))
		if e.get("part", false):
			oc = Color(PART_COL.r * 2.0, PART_COL.g * 2.0, PART_COL.b * 2.0, 0.7 + 0.3 * _heartbeat(e))   # 普通怪：中性偏淡紫白（原青白，和经验结晶、击杀溶解同色连片，docs/48 P1）   # 精英：橙红（docs/48 ⑤，原金色和友方金圈、刀光撞色）
		if not e.elite and not e.boss:
			oc.a *= ol_mul   # 后期满屏敌人时普通怪描边变淡，不再连成一片（EA 1.1；下限 render/declutter ol_floor，缺省 0.4）；精英 / Boss 不变
		_espr_outline(name, frames, frame, bpos, sc, flip, oc, anc, sq)
	# 囊海爬行者破膜（Codex docs/96 §1.3）：back（本体后）→ 本体 → front（本体前），两层同原点 (24,28)、同起播时间与帧号；
	# 原点对齐脚底 bpos，按本体缩放；只有 enemies.gd 写了 burst_fx_t（爆发那一刻）的 0.375 秒内画，缺图就不画（判定不变）
	var bfx: int = _burst_fx_frame(e)
	if bfx >= 0 and _rec == null:
		_burst_fx_layer(e, "_back", bfx, bpos, flip)
	_espr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		# 受击白闪：普通怪随 ecrowd 降到 declutter flash_a（缺省 0.9 = 不变）；精英 / Boss 照旧
		_espr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9 if (e.elite or e.boss) else flash_a), anc, sq)
	elif e.boss and _rec == null and g.tex.has(name + "_white"):
		# Boss 登场：先是白剪影、0.15–0.7 秒亮成本体（screens/boss_intro.gd；Boss 不进画法缓存，docs/50 §9.9）
		var sk: float = g.boss_intro.silhouette_k(e)
		if sk > 0.0:
			_espr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.95 * sk), anc, sq)
	if bfx >= 0 and _rec == null:
		_burst_fx_layer(e, "_front", bfx, bpos, flip)
	if _rec == null and e.get("affix", "") != "":
		_affix_fx(e, bpos, _enemy_top(e))
	var wk: String = e.get("weak", "")
	if _rec == null and wk != "" and not e.get("under", false):
		var wc := Color(1.0, 0.75, 0.3) if wk == "物理" else (Color(0.7, 0.55, 1.0) if wk == "法术" else Color(1.0, 0.5, 0.8))
		var wp: Vector2 = e.pos + Vector2(e.r * 0.8 + 6.0, -e.r - 4.0)
		weak_marks.append([wp, wc])   # 弱点菱形攒到排序实体画完后一次合批（每只一个多边形会打断敌人贴图的合批，性能 9/30）
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
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off), Vector2(fw, fh)), src, Look.op_mod(g, pos, col))
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
				Sfx.play_at("knight_charge", e.pos, -6.0 if e.boss else -10.0, 1.0, 0.05)   # 冰面急冲（音频，tools/gen_sfx_events.py）
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
	for e in (_vis_tell if _vis_on else g.enemies):
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
			_tell_line(e.pos, e.pos + e.dash_dir * _dash_len(e), 10.0, wk, ENEMY_TELL, e.get("tell_dim", false))
		# 灯边硬直（docs/56 §10）：头顶一颗暖色小光点 + 绕着转的两粒光屑，读作「被灯光震住」，随剩余时间淡出
		var bst: float = e.get("bstag", 0.0)
		if bst > 0.0:
			var ba: float = clampf(bst / 0.3, 0.0, 1.0)
			var bt: Vector2 = e.pos + Vector2(0, -e.r - 14.0)
			g.draw_circle(bt, 3.0, Color(1.9, 1.5, 0.8, 0.85 * ba))
			for k in 2:
				var bo: Vector2 = Vector2.from_angle(g.t * 9.0 + PI * k) * Vector2(9.0, 3.5)
				g.draw_circle(bt + bo, 1.6, Color(1.9, 1.5, 0.8, 0.7 * ba))
		# 伊祖米克解读阶段的冲击波已改走 boss_ai._warn（1 秒预警、must_dash 标记，Boss与怪物 docs/48 P0-5），这里不再按 bt 预告
		if e.get("count_max", 0.0) > 0.0 and float(e.get("count_end", 0.0)) > g.t:
			_count_ring(e)
		var stk = e.get("stakes")   # 不给每只敌人新建默认空数组（docs/50 §14）
		if stk is Array and not stk.is_empty():
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
	g.draw_rect(Rect2(tp + Vector2(-2, -12), Vector2(UI.cond(g.font).get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8.0, 17)), Color(0.02, 0.03, 0.05, 0.8))
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


const _NO_DEF := {}   # 只读缺省（.get(k, {}) 每次都会新建一个空字典）


## 巢涌者神经光环（docs/48 P1：帧条放大 4.6 倍后颗粒很粗，画在实体层会盖住其他东西）：
## 地面层程序绘制——淡紫柔光底、两道向内收的涟漪、缓慢转动的虚线外圈 = 判定范围
func draw_nest_auras() -> void:
	for e in g.enemies:
		if e.dead:
			continue
		if float(e.get("burden_r", 0.0)) > 0.0 and e.get("cocoon_t", 0.0) <= 0.0:
			_burden_ring(e)
		# 不给每只敌人新建默认空数组 / 空字典（docs/50 §14）
		var lm = e.get("lamps")
		if lm is Array and not lm.is_empty():
			_izu_lamps(e)
		var ed: Dictionary = D.ENEMIES.get(e.type, _NO_DEF)
		if not ed.has("aura_r"):
			continue
		var ar: float = ed.aura_r
		if not view_rect(ar + 20.0).has_point(e.pos):
			continue   # 屏外不画（性能 9/30：原来全场每只都画）
		var aura_tex := _lazy_tex("fx_nest_aura_big")
		if aura_tex != null:
			var fw: float = aura_tex.get_width() / 4.0
			var frame := int(g.t * 10.0) % 4
			g.draw_texture_rect_region(aura_tex, Rect2(e.pos - Vector2.ONE * ar, Vector2.ONE * ar * 2.0), Rect2(frame * fw, 0, fw, aura_tex.get_height()), Color(1, 1, 1, 0.35))
		# 柔光底 / 内收涟漪 / 转动虚线外圈都进无贴图批，函数末尾一次提交（原来每只约 24 次绘制调用）
		var ac := Color(0.9, 0.5, 1.6)
		for q in 4:
			tb_circle(e.pos, ar * (1.0 - q * 0.22), Color(ac.r, ac.g, ac.b, 0.035), 1.0, 32)
		for q in 2:
			var u: float = fmod(g.t * 0.5 + q * 0.5 + e.id * 0.17, 1.0)
			tb_ring(e.pos, ar * (1.0 - u * 0.85), 1.5, Color(ac.r, ac.g, ac.b, 0.28 * (1.0 - u)), 40)
		var rot: float = g.t * 0.4 + e.id
		for q in 18:
			var a0: float = rot + q * TAU / 18.0
			tb_arc(e.pos, ar, a0, a0 + TAU / 36.0, 2.0, Color(ac.r, ac.g, ac.b, 0.55), 3)

	tb_flush()



## ---- 主控身上的小怪控制（combat.gd「小怪控制」段，用户 9/29）：画在实体之上、预警轮廓之下
## 寒霜 g.cold：脚下冰霜圈 + 每层一枚绕身冰晶；冻结（寒霜满层时的 root）：半透明冰壳，快化时出裂纹；
## 束缚（其他 root）：三条暗紫触须从地面缠上来；侵蚀创口 g.wound：身上每层一道暗洋红伤口，缓慢滴落
const COLD_COL := Color(0.62, 0.9, 1.4)
const BIND_COL := Color(0.8, 0.45, 1.3)
const WOUND_COL := Color(1.1, 0.25, 0.55)
var root_max := 0.0              # 本次冻结 / 束缚的总时长（root_t 刚变大时记下，画倒计时用）
var root_prev := 0.0

func leader_frozen() -> bool:
	return g.root_t > 0.0 and g.cold >= int(g.combat.enemy_knob("frost_max", 3.0))   # 按档覆盖（combat.enemy_knob）


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
	var nmax: float = g.combat.nerve_max()
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
## 全部进无贴图批（性能 docs/50 §9.7：原来甲壳每只 9 次、潮盾 5 次绘制调用，夹在敌人贴图之间还打断贴图合批）；
## 排序循环画完后和弱点菱形一起提交，所以词条画在所有敌人之上（和弱点菱形一样）
## 词条特效（docs/50 §9.12，2026-10-01 模板化）：甲壳 / 潮盾的三角形进单独的「无索引」批（_afx：TriBatch 的 pts / cols，按排序循环里敌人的先后追加，
## 排序段画完后、弱点菱形之前一次提交，和原来在通用批里的前后顺序相同）。开销大头原来是每只每帧几十个临时数组：
## - 甲壳：3 块甲片（多边形 + 5 条边 + 1 条高光）的三角形在局部坐标里开局算一次成模板（_afx_armor，135 个顶点），每帧 Transform2D 平移整组（引擎原生）；
## - 潮盾：底圆用单位扇形模板按半径缩放 + 平移（原生）；两段弧每段算一次内外顶点再按三角形追加；血条 4 个三角形。
## 顶点算式与旧写法相同，只是甲壳先在局部坐标算、再整体平移（浮点结合顺序不同，个别边缘像素可能差最低位；协调人同意的口径见 docs/50 §9.12）
var _afx := TriBatch.new()   # 无索引词条批（docs/101 B4 ③：存储 / 提交走 TriBatch，表驱动算式不变）
var _afx_tab_ready := false
var _afx_armor := PackedVector2Array()
var _afx_armor_cols := PackedColorArray()
var _afx_fan24 := PackedVector2Array()
var _afx_d32 := PackedVector2Array()
var _afx_d8 := PackedVector2Array()

func _afx_tables() -> void:
	_afx_tab_ready = true
	var c1 := Color(0.62, 0.66, 0.72, 0.95)
	var c2 := Color(0.15, 0.17, 0.2, 1.0)
	var c3 := Color(1.4, 1.45, 1.5, 0.9)
	for q in 3:
		var p := Vector2(-8 + q * 8, -4 + absf(q - 1) * 4)
		var pl := [p + Vector2(-4, -5), p + Vector2(4, -5), p + Vector2(5, 3), p + Vector2(0, 7), p + Vector2(-5, 3)]
		for k in range(1, 4):   # tb_poly 的扇形三角形
			_afx_armor.append_array([pl[0], pl[k], pl[k + 1]])
			_afx_armor_cols.append_array([c1, c1, c1])
		for v in 6:   # tb_line：5 条边 + 高光；tb_quad 的两个三角形 (0,1,2)(0,2,3)
			var a: Vector2 = pl[v] if v < 5 else p + Vector2(-3, -4)
			var b: Vector2 = pl[(v + 1) % 5] if v < 5 else p + Vector2(3, -4)
			var n: Vector2 = (b - a).orthogonal().normalized() * 1.0 * 0.5
			var lc: Color = c2 if v < 5 else c3
			_afx_armor.append_array([a + n, b + n, b - n, a + n, b - n, a - n])
			_afx_armor_cols.append_array([lc, lc, lc, lc, lc, lc])
	for q in 24:   # tb_circle(seg 24) 的扇形：(中心, 第 q 个, 第 q+1 个)，单位半径
		var aq: float = q * TAU / 24
		var aq2: float = ((q + 1) % 24) * TAU / 24
		_afx_fan24.append_array([Vector2.ZERO, Vector2(cos(aq), sin(aq)), Vector2(cos(aq2), sin(aq2))])
	for q in 33:
		var aq3: float = lerpf(0.0, TAU, float(q) / 32)
		_afx_d32.append(Vector2(cos(aq3), sin(aq3)))
	for q in 9:
		var aq4: float = lerpf(-2.4, -1.5, float(q) / 8)
		_afx_d8.append(Vector2(cos(aq4), sin(aq4)))


func _affix_fx(e: Dictionary, bpos: Vector2, top: Vector2) -> void:
	var af: String = e.affix
	if af != "armor" and not (af == "shield" and e.shield_hp > 0.0):
		return
	if not _afx_tab_ready:
		_afx_tables()
	if af == "armor":
		var c: Vector2 = (bpos + top) / 2.0 if g.foot_anchor.has(e.tex) else e.pos
		_afx.pts.append_array(Transform2D(0.0, c) * _afx_armor)
		_afx.cols.append_array(_afx_armor_cols)
		return
	var c2: Vector2 = (bpos + top) / 2.0 if g.foot_anchor.has(e.tex) else e.pos
	var rr: float = maxf(e.r + 6.0, (bpos.y - top.y) * 0.55)
	var wob: float = 1.0 + 0.04 * sin(g.t * 5.0 + e.id)
	var r: float = rr * wob
	# 底圆（tb_circle 24 段）：单位扇形按半径缩放 + 平移
	_afx.pts.append_array(Transform2D(0.0, Vector2(r, r), 0.0, c2) * _afx_fan24)
	var fc := Color(0.5, 1.2, 1.4, 0.13)
	for q in 72:
		_afx.cols.append(fc)
	_afx_arc(c2, r, 1.5, Color(0.7, 1.5, 1.6, 0.7), _afx_d32)
	_afx_arc(c2, r * 0.8, 2.0, Color(1.6, 2.0, 2.0, 0.8), _afx_d8)
	var mx: float = e.maxhp * Game.Bal.v("enemy/affix_shield", 0.30)
	var bw: float = maxf(20.0, e.r * 1.6)
	var by: Vector2 = bpos + Vector2(-bw / 2.0, 6)
	var fw2: float = bw * clampf(e.shield_hp / maxf(mx, 1.0), 0.0, 1.0)
	var b1: Vector2 = by + Vector2(bw, 0)
	var b2: Vector2 = by + Vector2(bw, 3)
	var b3: Vector2 = by + Vector2(0, 3)
	var f1: Vector2 = by + Vector2(fw2, 0)
	var f2: Vector2 = by + Vector2(fw2, 3)
	_afx.pts.append_array([by, b1, b2, by, b2, b3, by, f1, f2, by, f2, b3])
	var k0 := Color(0, 0, 0, 0.6)
	var k1 := Color(0.7, 1.5, 1.6, 0.95)
	_afx.cols.append_array([k0, k0, k0, k0, k0, k0, k1, k1, k1, k1, k1, k1])


## tb_arc 的三角形展开（sy = 1）：每段 (内 q, 外 q, 外 q+1)、(内 q, 外 q+1, 内 q+1)，和 tb_arc 的索引顺序一致
func _afx_arc(c: Vector2, r: float, w: float, col: Color, dirs: PackedVector2Array) -> void:
	var seg: int = dirs.size() - 1
	var ri: float = r - w * 0.5
	var ro: float = r + w * 0.5
	var d0: Vector2 = dirs[0]
	var pi := c + Vector2(d0.x * ri, d0.y * ri * 1.0)
	var po := c + Vector2(d0.x * ro, d0.y * ro * 1.0)
	for q in seg:
		var d: Vector2 = dirs[q + 1]
		var ni := c + Vector2(d.x * ri, d.y * ri * 1.0)
		var no := c + Vector2(d.x * ro, d.y * ro * 1.0)
		_afx.pts.append_array([pi, po, no, pi, no, ni])
		pi = ni
		po = no
	for q in seg * 6:
		_afx.cols.append(col)


## 词条批提交（排序段画完、弱点菱形之前；无索引：每 3 个顶点一个三角形）
func _afx_flush() -> void:
	_afx.flush(g)


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
	var gy: float = ground_y()
	var o: Vector2 = e.pos
	var sq := func(v: Vector2) -> Vector2: return o + Vector2(v.x, v.y * gy)   # 地面椭圆：纵向按 GROUND_Y 压（原来用画布变换，改算顶点好进批）
	tb_circle(o, r, Color(c.r, c.g, c.b, 0.06 if inn else 0.03), gy, 48)
	tb_arc(o, r, 0.0, TAU, 2.0, Color(c.r, c.g, c.b, 0.5 * a), 72, gy)
	tb_arc(o, r - 14.0, 0.0, TAU, 1.0, Color(c.r, c.g, c.b, 0.3 * a), 72, gy)
	var rot: float = g.t * (0.35 if inn else 0.15)
	var rc := Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a)
	for q in 16:
		var ang: float = rot + q * TAU / 16.0
		var p := Vector2.from_angle(ang) * (r - 7.0)
		var tn := Vector2.from_angle(ang + PI / 2.0)
		var nr := Vector2.from_angle(ang)
		# 一枚符文：竖划 + 按序号变化的横 / 斜划
		tb_line(sq.call(p - nr * 5.0), sq.call(p + nr * 5.0), rc, 1.5)
		match q % 3:
			0:
				tb_line(sq.call(p - tn * 3.0), sq.call(p + tn * 3.0), rc, 1.5)
			1:
				tb_line(sq.call(p + nr * 5.0), sq.call(p + nr * 1.0 + tn * 4.0), rc, 1.5)
			_:
				tb_line(sq.call(p - nr * 5.0), sq.call(p - nr * 1.0 - tn * 4.0), rc, 1.5)


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
		# 石灯本体：Codex v14 prop_lamp_post（20×32，f0 熄灭、f1–f2 点亮循环，脚底第 29 行）；缺图时退回程序拼图
		if g.tex.get("prop_lamp_post") != null:
			g.vfx.spr("prop_lamp_post", 3, (1 + int(g.t * 4.0) % 2) if lit else 0, p, _hpx("prop_lamp_post"), false, Color.WHITE, Vector2(0.5, 30.0 / 32.0))
			if lit:
				g.draw_circle(p + Vector2(0, -40), 14.0 + 3.0 * pulse, Color(1.8, 1.4, 0.7, 0.25))
				UI.text(g, g.font, p + Vector2(-40, 26), "安全", 13 if not waving else 16, Color(1.0, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
			continue
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
				tb_arc(pos, r, a0, a0 + TAU / 40.0, 2.0, Color(BEACON_COL.r * 1.5, BEACON_COL.g * 1.5, BEACON_COL.b * 1.5, 0.55), 3, ground_y())   # 虚线进批（原来 20 段各一次调用）
			# 引路圈（docs/56 a，beacon/guide_r > 0 才有）：guide_r 处一圈很淡的同款虚线，寿命过 guide_life 即消失
			var gr: float = float(b.get("guide_r", 0.0))
			if gr > 0.0 and float(b.get("age", 0.0)) <= float(b.get("guide_life", 45.0)):
				for q in 28:
					var a2: float = -g.t * 0.2 + q * TAU / 28.0
					tb_arc(pos, gr, a2, a2 + TAU / 56.0, 1.5, Color(BEACON_COL.r * 1.3, BEACON_COL.g * 1.3, BEACON_COL.b * 1.3, 0.16 + 0.04 * pulse), 3, ground_y())
			# 接力环（docs/56 §8，beacon/relay_r > r 才有）：光圈外 r..relay_r 一圈很淡的暖色带（同引路圈的色），主控站在带里（进度不退 / 慢涨）时提亮
			var rr: float = float(b.get("relay_r", 0.0))
			if rr > r:
				var on_band: bool = b.get("band", false)
				g.draw_arc(Vector2.ZERO, (r + rr) * 0.5, 0.0, TAU, 48, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, (0.12 + 0.05 * pulse) if on_band else 0.06 + 0.02 * pulse), rr - r)
		else:
			var left: float = float(b.get("safe_end", 0.0)) - g.t
			if left > 0.0:
				var cr: float = float(b.get("clear_r", 260.0))
				g.draw_circle(Vector2.ZERO, cr, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, 0.05))
				for q in 36:
					var a1: float = -g.t * 0.1 + q * TAU / 36.0
					tb_arc(pos, cr, a1, a1 + TAU / 72.0, 2.0, Color(BEACON_COL.r * 1.4, BEACON_COL.g * 1.4, BEACON_COL.b * 1.4, 0.45 if left > 5.0 else 0.45 * absf(sin(g.t * 8.0))), 3, ground_y())
			g.draw_circle(Vector2.ZERO, 46.0, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.4, 0.16 + 0.06 * pulse))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		tb_flush()
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
	g.vfx.beacon_ignite(b)   # docs/54：柔光 + 余烬 + 溟痕退散（fx/beacon_burst2）


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
		if g.tex.get("prop_ice_stake") != null:
			# Codex v14 prop_ice_stake（24×56 × 2 帧，脚底第 53 行）；冰蓝过曝调色同骑士长矛（暗环境光下原色太暗）；到期前闪烁仍是程序改透明度，判定圈程序画
			g.vfx.spr("prop_ice_stake", 2, int(g.t * 4.0) % 2, p, _hpx("prop_ice_stake"), false, Color(1.6, 1.8, 2.1, a), Vector2(0.5, 54.0 / 56.0))
			continue
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
## 溟痕冒泡（V7 fx_mire_bubble，16×16 × 4 帧 8 fps；docs/13 §8、docs/48 §1-6「已交付但闲置」）：纯画面。
## 每片溟痕按半径 1–4 个冒泡位，每位 1.6–2.6 秒冒一次（0.5 秒播完 4 帧），位置由溟痕 seed 和第几次冒泡算出，不用对局随机数；
## 主控踩在溟痕里时脚边另有 2 个更快的冒泡位（V7 原意）。只画屏幕内的，全场最多 MIRE_BUBBLE_MAX 个；
## 在溟痕循环里只收集，循环后同一张贴图连续画，贴图矩形自成一批，不打断溟痕本身的合批
const MIRE_BUBBLE_MAX := 48
const MIRE_MOTE_MAX := 48      # docs/54 溟痕光尘：全场每帧最多这么多粒（tb 批 4 顶点一粒）

func _mire_bubbles(m: Dictionary, out: Array) -> void:
	var a: float = clampf(float(m.life) / 3.0, 0.0, 1.0)
	var r: float = float(m.r)
	var sd: float = float(m.get("seed", 0.0))
	var slots: int = clampi(int(r / 18.0), 1, 4)
	var feet: bool = g.combat.ground_d(g.ppos, m.pos) < r
	for k in slots + (2 if feet else 0):
		var near: bool = k >= slots
		var period: float = (0.9 if near else 1.6) + fmod(sd * 0.37 + k * 0.61, 1.0) * (0.5 if near else 1.0)
		var tt: float = g.t + sd * 0.53 + k * 0.29
		var cyc: float = floorf(tt / period)
		var ph: float = (tt - cyc * period) / 0.5
		if ph >= 1.0:
			continue
		var h: float = fmod(sin(cyc * 12.9898 + k * 78.233 + sd) * 43758.5453, 1.0)
		var h2: float = fmod(sin(cyc * 39.346 + k * 11.135 + sd * 2.0) * 24634.6345, 1.0)
		var c: Vector2 = g.ppos + Vector2(0, 6) if near else m.pos
		var rr: float = (22.0 if near else r * 0.75) * sqrt(absf(h2))
		var off := Vector2.from_angle(absf(h) * TAU) * rr
		out.append([c + Vector2(off.x, off.y * 0.55), int(ph * 4.0), a])
		if out.size() >= MIRE_BUBBLE_MAX:
			return


func _draw_mire_bubbles(bubbles: Array) -> void:
	if bubbles.is_empty():
		return
	var bt: Texture2D = _lazy_tex("fx_mire_bubble")
	if bt == null:
		return
	var hr: float = A.hires_of(bt)
	var fw: float = bt.get_width() / 4.0
	var fh: float = float(bt.get_height())
	var sz := Vector2(fw, fh) * Game.PX / hr
	for b in bubbles:
		var p: Vector2 = b[0]
		g.draw_texture_rect_region(bt, Rect2(p - Vector2(sz.x / 2.0, sz.y), sz), Rect2(fw * int(b[1]), 0, fw, fh), Color(1, 1, 1, 0.85 * float(b[2])))


## 世界层视野表（docs/101 B4 ①，§3.2 ⑥）：draw_world 开头扫一遍敌人，按原顺序分两张表——
## _vis_ent：ENTITY_MARGIN 外扩内（影子 / 排序实体 / 精英登场）；_vis_tell：TELL_MARGIN 外扩内或 Boss（敌人预警）。
## 两张表都是各层原来那次全表遍历的超集、次序不变，各层仍按自己的范围 / 条件再判一次，所以画面逐像素相同。
## 只在 draw_world 这一帧内有效（之后敌人表会变）；OPT_VIS 置位或没建表时各层照旧扫 g.enemies
var _vis_ent: Array = []
var _vis_tell: Array = []
var _vis_on := false


func _build_vis(evr: Rect2) -> void:
	_vis_ent.clear()
	_vis_tell.clear()
	_vis_on = not (g.opt_old & Game.OPT_VIS)
	if not _vis_on:
		return
	var tvr: Rect2 = view_rect(TELL_MARGIN)   # ⊃ evr（ENTITY_MARGIN < TELL_MARGIN）
	for e in g.enemies:
		var ep: Vector2 = e.pos
		if tvr.has_point(ep):
			_vis_tell.append(e)
			if evr.has_point(ep):
				_vis_ent.append(e)
		elif e.boss:
			_vis_tell.append(e)


func view_rect(margin: float) -> Rect2:
	var inv: Transform2D = g.get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = g.get_viewport_rect().size
	return (inv * Rect2(Vector2.ZERO, vs)).grow(margin)


## 敌人描边合成一次绘制（性能，协调人 9/30「排序实体每实体提交降到 ≤2」）：原来白剪影上下左右各偏 1 像素画 4 次，
## 现在把白剪影逐帧在贴图上下左右各扩 1 像素（blend_rect 叠 4 次，原生操作）合成一张带 1 像素边距的描边贴图，缓存后每只只画 1 次
var _ol_cache := {}

func _outline_tex(name: String, frames: int) -> Texture2D:
	var key: String = "%s#%d" % [name, frames]
	if _ol_cache.has(key):
		return _ol_cache[key]
	var wt: Texture2D = g.tex.get(name + "_white")
	var out_t: Texture2D = null
	if wt != null:
		var img: Image = wt.get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var fw: int = img.get_width() / frames
		var fh: int = img.get_height()
		var out := Image.create((fw + 2) * frames, fh + 2, false, Image.FORMAT_RGBA8)
		for f in frames:
			var reg: Image = img.get_region(Rect2i(f * fw, 0, fw, fh))
			var o := Vector2i(f * (fw + 2) + 1, 1)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				out.blend_rect(reg, Rect2i(0, 0, fw, fh), o + d)
		out_t = ImageTexture.create_from_image(out)
	_ol_cache[key] = out_t
	return out_t


## 画一帧描边：定位 / 翻转 / 压扁与 vfx.spr 相同，只是贴图每帧四周多 1 像素边距
func _spr_outline(name: String, frames: int, frame: int, pos: Vector2, scale: float, flip: bool, col: Color, anchor: Vector2, sq: Vector2) -> void:
	var t: Texture2D = _outline_tex(name, frames)
	if t == null:
		return
	pos += g.draw_off
	var fw: int = t.get_width() / frames - 2
	var fh: int = t.get_height() - 2
	var src := Rect2((fw + 2) * (frame % frames), 0, fw + 2, fh + 2)
	var size := Vector2(fw, fh) * scale * sq
	var pad := Vector2(scale, scale) * sq
	if flip:
		g.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		g.draw_texture_rect_region(t, Rect2(-size * anchor - pad, size + pad * 2.0), src, col)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.draw_texture_rect_region(t, Rect2((pos - size * anchor).round() - pad, size + pad * 2.0), src, col)


## 伊莎玛拉潮涌迫近（2373cc8）：冲刺中每走约 20 像素在身后留一片水潮（地面椭圆泡沫 + 浪尖白点，0.7 秒退去）
var _trail_last := {}   # boss 的 id -> 上次留痕位置

func _tide_trail(b: Dictionary) -> void:
	var lp: Vector2 = _trail_last.get(b.id, Vector2.INF)
	if lp != Vector2.INF and lp.distance_to(b.pos) < 20.0:
		return
	_trail_last[b.id] = b.pos
	g.fx.append({"kind": "tide_trail", "pos": b.pos + Vector2(0, b.r * 0.6), "r": b.r * 0.9, "life": 0.7, "max": 0.7, "seed": g.vrng.randf() * TAU, "enemy": true})


## ---- 无贴图图形合批（性能 9/30：Godot 4 只合批贴图矩形，draw_circle / draw_arc / draw_polygon 每次都是一次绘制调用）：
## 先把圆、椭圆、圆环收集成三角形，最后一次 canvas_item_add_triangle_array 提交。提交前画布变换必须是单位矩阵
var weak_marks: Array = []      # 本帧敌人弱点菱形 [位置, 颜色]
var _tbb := TriBatch.new()   # 无贴图图形批（docs/101 B4 ③：几何与次序照旧，存储 / 提交统一走 TriBatch）

func tb_circle(c: Vector2, r: float, col: Color, sy := 1.0, seg := 14) -> void:
	_tbb.circle_n(c, r, col, sy, seg)


func tb_ring(c: Vector2, r: float, w: float, col: Color, seg := 16) -> void:
	_tbb.ring_n(c, r, w, col, seg)


## 径向渐变圆环：内圈半径 r0 颜色 c0 → 外圈半径 r1 颜色 c1（顶点色插值；围猎圈内外的地面调子）
func tb_ring2(c: Vector2, r0: float, r1: float, c0: Color, c1: Color, seg := 48) -> void:
	_tbb.ring2(c, r0, r1, c0, c1, seg)


func tb_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	_tbb.quad(p0, p1, p2, p3, col)


func tb_line(a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	_tbb.line_q(a, b, col, w)


func tb_arc(c: Vector2, r: float, a0: float, a1: float, w: float, col: Color, seg := 8, sy := 1.0) -> void:
	_tbb.arc_q(c, r, a0, a1, w, col, seg, sy)


## 凸多边形（扇形三角化）
func tb_poly(pts: PackedVector2Array, col: Color) -> void:
	_tbb.fan(pts, col)


func tb_flush(ci: CanvasItem = null) -> void:   # ci：提交到哪个画布（缺省世界；HUD 传 g.hud）
	_tbb.flush(ci if ci != null else g)


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
	if e.stun > 0.05 or brk > 0.0:
		for q in 3:
			var a: float = g.t * 5.0 + q * TAU / 3.0
			var sp: Vector2 = top + Vector2(cos(a) * 18.0, sin(a) * 5.0)
			UI.diamond(g, sp, 4.0, Color(1.8, 1.6, 0.6), Color(0, 0, 0, 0.6))
		if e.has("ammo") and brk > 0.0:
			UI.text(g, g.font, top + Vector2(-120, -12), "装填被打断 · 破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif brk > 0.0:
			# 其他 Boss 的破绽（伊莎玛拉潮涌迫近落地、塑路者核心碎裂等）：同一套星 + 剩余秒数
			UI.text(g, g.font, top + Vector2(-120, -12), "破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif e.type in ["iberia", "carmen"] and e.get("ammo", 1) == 0:
			UI.text(g, g.font, top + Vector2(-120, -12), "装填被打断 · 眩晕 %.1f" % e.stun, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)


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


func _tell_line(a: Vector2, b: Vector2, half: float, k: float, c: Color, dim := false) -> void:
	var d: Vector2 = b - a
	var n: Vector2 = d.normalized().orthogonal() * half
	if dim:
		# 打不到主控的冲刺线：只画淡边框（预警不藏，但不再整片盖住主控）
		g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, Bal.v("fx/tell_dim_alpha", 0.35)), 1.5)
		return
	g.draw_colored_polygon(PackedVector2Array([a + n, a + d * k + n, a + d * k - n, a - n]), Color(c.r, c.g, c.b, (0.22 + 0.12 * k) * tell_fill))
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
			g.draw_texture_rect_region(lt, Rect2(0, -8, w / (half * 2.0 / 16.0), 16), Rect2(16 * fr, 0, w / (half * 2.0 / 16.0), 16), Color(c.r, c.g, c.b, 0.55 * tell_fill))
			x += seg
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var et: Texture2D = _wtex("fx_warn_end")
		if et != null:
			var es: float = half * 2.4 / 32.0 * 2.0
			g.draw_set_transform(b, 0.0, Vector2(es, es * ground_y()))
			g.draw_texture_rect_region(et, Rect2(-16, -16, 32, 32), Rect2(32 * fr, 0, 32, 32), Color(c.r, c.g, c.b, 0.8))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(0, 0, 0, 0.55), 4.0 * tell_edge)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, 0.85), 2.0 * tell_edge)
	g.draw_line(a, b, Color(1, 1, 1, 0.5 + 0.4 * k), 1.0)


## 手动普攻方向指示（1.1.1，用户 9/30：手动攻击时看不出要打向哪里）：只在手动普攻开启时画；从主控脚下沿 doctor.attack_dir()
## （攻击真正打出去的方向）画一段职业色半透明短线 + 末端小箭头，深色描边垫底（同预警轮廓写法，任何底色都看得见）。
## 触屏没拖（attack_dir 为零 = 吸附最近目标）时不画。长度 fx/atk_dir_len
func draw_attack_dir(cv) -> void:   # cv：干员的合批画布（squad.draw_leader_mark 的同一批里调用，不新增绘制调用）
	if g.state != Game.S.PLAY or not g.doctor.manual_attack:
		return
	var ld = g.squad.leader()
	if ld == null or ld.pos == Vector2.INF:
		return
	var dir: Vector2 = g.doctor.attack_dir()
	if dir == Vector2.ZERO:
		return
	var c: Color = ld.col()
	var L: float = Bal.v("fx/atk_dir_len", 80.0)
	var a: float = Bal.v("fx/atk_dir_alpha", 0.8)
	var p0: Vector2 = ld.pos + Vector2(0, 4) + dir * 32.0   # 从脚下环（半径 24、冲刺弧 30）外面起
	var p1: Vector2 = p0 + dir * L
	var n: Vector2 = dir.orthogonal()
	var dark := Color(0.02, 0.02, 0.05, 0.75)
	cv.draw_line(p0, p1 - dir * 8.0, dark, 6.5)
	cv.draw_colored_polygon(PackedVector2Array([p1 + dir * 3.5, p1 - dir * 14.0 + n * 11.0, p1 - dir * 14.0 - n * 11.0]), dark)
	cv.draw_line(p0, p1 - dir * 8.0, Color(c.r, c.g, c.b, a), 3.0)
	cv.draw_colored_polygon(PackedVector2Array([p1, p1 - dir * 12.0 + n * 8.0, p1 - dir * 12.0 - n * 8.0]), Color(c.r, c.g, c.b, minf(1.0, a + 0.15)))
	cv.draw_line(p0 + dir * 4.0, p1 - dir * 10.0, Color(1, 1, 1, 0.35 * a), 1.0)   # 白芯，同预警轮廓写法


## 点亮的灯标照亮周围（界面与美术 10-01，协调人派）：每座点亮中的灯标一盏暖色点光（和灯火同一套 PointLight2D 光照，
## 法线光照下地面 / 敌人 / 干员一起提亮，不新增绘制调用），半径 = 灯标的清溟痕半径 clear_r（balance beacon/clear_r，340，
## 和点亮后的虚线光圈同一个圈），光贴图自带由中心向外衰减，边缘柔和。点亮后 0.5 秒亮起，灯标寿命最后 5 秒淡出；
## 强度 beacon/lit_glow_gain（0 = 关）
var _beacon_lights: Array = []

func update_beacon_lights() -> void:
	var gain: float = Bal.v("beacon/lit_glow_gain", 1.1)
	var lit: Array = []
	var bs = g.get("beacons")
	if gain > 0.0 and bs is Array:
		for b in bs:
			if b.get("lit", false) and not b.get("dead", false) and g.t < float(b.get("safe_end", 0.0)):
				lit.append(b)
	for i in maxi(lit.size(), _beacon_lights.size()):
		if i >= lit.size():
			_beacon_lights[i].visible = false
			continue
		if i >= _beacon_lights.size():
			var l := PointLight2D.new()
			l.texture = g.tex.light
			l.color = Color(1.0, 0.84, 0.58)
			l.height = 90.0
			g.add_child(l)
			_beacon_lights.append(l)
		var b: Dictionary = lit[i]
		var fade: float = clampf((g.t - float(b.lit_t)) / 0.5, 0.0, 1.0) * clampf((float(b.safe_end) - g.t) / 5.0, 0.0, 1.0)
		var bl: PointLight2D = _beacon_lights[i]
		bl.visible = fade > 0.0
		bl.position = b.pos + Vector2(0, -20)
		bl.texture_scale = float(b.get("clear_r", 340.0)) / 64.0
		bl.energy = gain * fade


## 冲刺预警线长度：按实际冲刺距离（速度 × dash_speed × 0.35 秒）；Boss与怪物 给了 dash_len 就用它
func _dash_len(e: Dictionary) -> float:
	var dd: Dictionary = D.ENEMIES.get(e.type, {})
	return float(e.get("dash_len", clampf(e.spd * float(dd.get("dash_speed", 3.8)) * 0.35, 60.0, 400.0)))


## 预警密度（可读性 1.1.1，协调人：9:04 截图 59 条滑动者冲刺线 + 近战扇形叠满主控）：预警不能藏（是躲招信号），
## 所以按「会不会打到主控」分强度——线段 / 扇形 / 圈与主控（半径 fx/tell_lead_r + 余量 fx/tell_margin）相交的全强度，
## 打不到的只画淡边框（fx/tell_dim_alpha）；会打到的冲刺线超过 fx/tell_full_max 条时按离主控由近到远保留全强度。
## Boss 的冲刺线与招式预警、预告（style 0）、已结算的不参与。结果写在 e.tell_dim / w.dim（纯画面）
func classify_tells() -> void:
	var lr: float = Bal.v("fx/tell_lead_r", 16.0) + Bal.v("fx/tell_margin", 24.0)
	var p: Vector2 = g.ppos
	var hits: Array = []
	for e in g.enemies:
		if e.dead or e.boss or not (e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir")):
			if e.has("tell_dim"):
				e.tell_dim = false
			continue
		var a: Vector2 = e.pos
		var b: Vector2 = a + e.dash_dir * _dash_len(e)
		var hit: bool = p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 10.0 + lr
		e.tell_dim = not hit
		if hit:
			hits.append([a.distance_squared_to(p), e])
	var nmax: int = Bal.vi("fx/tell_full_max", 8)
	if hits.size() > nmax:
		hits.sort_custom(func(x, y): return x[0] < y[0])
		for i in range(nmax, hits.size()):
			hits[i][1].tell_dim = true
	var gy: float = ground_y()
	for w in g.warns:
		var ow = w.get("owner")
		if w.done or int(w.get("style", 1)) == 0 or (ow is Dictionary and ow.get("boss", false)) or not (ow is Dictionary):
			w["dim"] = false
			continue
		var hit := true
		match w.shape:
			"cone":
				var d: Vector2 = p - w.pos
				var dist: float = d.length()
				if dist > float(w.r) + lr:
					hit = false
				elif dist > lr:
					hit = absf(angle_difference(d.angle(), float(w.ang))) <= float(w.half) + asin(minf(1.0, lr / dist))
			"line":
				var b2: Vector2 = w.pos + Vector2.from_angle(float(w.ang)) * float(w.len)
				hit = p.distance_to(Geometry2D.get_closest_point_to_segment(p, w.pos, b2)) < float(w.wid) + lr
			"circle":
				var dc: Vector2 = p - w.pos
				hit = Vector2(dc.x, dc.y / maxf(gy, 0.01)).length() < float(w.r) + lr
		w["dim"] = not hit


func _tell_circle(p: Vector2, r: float, k: float, c: Color) -> void:
	var pulse: float = 0.5 + 0.5 * sin(g.t * 18.0)
	g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致
	g.draw_circle(Vector2.ZERO, r * k, Color(c.r, c.g, c.b, (0.18 + 0.1 * k) * tell_fill))
	var rt: Texture2D = _wtex("fx_warn_ring")
	if rt != null:
		# V7 涟漪：从外向内收缩的水纹，按半径缩放（radius_px 30）
		var rs: float = r / 30.0
		g.draw_set_transform(p, 0.0, Vector2(rs, rs * ground_y()))
		g.draw_texture_rect_region(rt, Rect2(-32, -32, 64, 64), Rect2(64 * (int(g.t * 12.0) % 4), 0, 64, 64), Color(c.r, c.g, c.b, 0.5 * tell_fill))
		g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 5.0 * tell_edge)
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.75 + 0.25 * pulse * k), 3.0 * tell_edge)
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55 + 0.4 * k), 1.0 * tell_edge)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Boss 招式预警的轮廓（填色仍在地面层，render/telegraph_draw.draw_fills）：按 docs/38 §8.11 收敛成五种样式，
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
		var da: float = 1.0
		if w.get("dim", false):
			# 打不到主控的杂兵预警（classify_tells）：轮廓整体降到 fx/tell_dim_alpha，不白闪；地面填充在 boss_ai._draw_warns 里跳过
			da = Bal.v("fx/tell_dim_alpha", 0.35)
			core.a *= da
			edge.a *= da
			lock_flash = 0.0
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
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, edge, 5.0 * tell_edge)
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, core, 2.0 * tell_edge)
				if must:
					# ⑤ 必须冲刺：白色双描边
					var pk: float = 0.5 + 0.5 * sin(g.t * 12.0)
					g.draw_arc(Vector2.ZERO, w.r + 7.0, 0.0, TAU, 56, Color(1, 1, 1, 0.55 + 0.35 * pk), 2.0)
					g.draw_arc(Vector2.ZERO, w.r - 5.0, 0.0, TAU, 56, Color(1, 1, 1, 0.45 + 0.3 * pk), 1.5)
				elif not ring:
					# ① 落点圈：内圈随结算时间长满，最后 0.12 秒整圈白闪
					g.draw_arc(Vector2.ZERO, maxf(2.0, w.r * k), 0.0, TAU, 48, Color(1, 1, 1, (0.35 + 0.35 * k) * da), 1.5)
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
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), edge, false, 5.0 * tell_edge)
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), core, false, 2.0 * tell_edge)
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
						g.draw_polyline(PackedVector2Array([Vector2(ax - hw, -hw), Vector2(ax, 0), Vector2(ax - hw, hw)]), Color(1, 1, 1, (0.55 + 0.35 * k) * da), 2.0)
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
					g.draw_polyline(pts, edge, 5.0 * tell_edge)
					g.draw_polyline(pts, core, 2.0 * tell_edge)
				# 扇面内一道随时间向外推的弧
				g.draw_arc(w.pos, maxf(4.0, w.r * k), w.ang - w.half, w.ang + w.half, 20, Color(1, 1, 1, (0.3 + 0.4 * k) * da), 1.5)
				if lock_flash > 0.0:
					g.draw_colored_polygon(pts, Color(1, 1, 1, 0.3 * lock_flash))
		# ④ 缺口环的出口：缺口两侧金色短线 + 中间「出口」小牌（缺口方向与真实弹道同一角度，不做地面压缩）；多缺口（gaps）每个缺口各画一组
		if w.has("gap_ang"):
			var safe_col := Color(1.0, 0.85, 0.35, 0.9)
			var r_in: float = minf(90.0, float(w.r) * 0.6)
			var r_out: float = maxf(190.0, float(w.r) + 40.0)
			for ga in w.get("gaps", [w.gap_ang]):
				for side in [-1.0, 1.0]:
					var v := Vector2.from_angle(float(ga) + side * float(w.gap_half))
					g.draw_line(w.pos + v * r_in, w.pos + v * r_out, Color(0, 0, 0, 0.7), 5.0)
					g.draw_line(w.pos + v * r_in, w.pos + v * r_out, safe_col, 2.0)
				var mp: Vector2 = w.pos + Vector2.from_angle(float(ga)) * (r_in + r_out) * 0.5
				g.draw_rect(Rect2(mp + Vector2(-20, -11), Vector2(40, 18)), Color(0.05, 0.04, 0.02, 0.85))
				UI.text(g, g.font, mp + Vector2(-20, 3), "出口", 12, safe_col, HORIZONTAL_ALIGNMENT_CENTER, 40)


func draw_zone() -> void:
	if g.zone_state == 0:
		return
	var vs := g.view_size()
	var far := vs.length() + 200.0
	var seg := 96
	var outer := g.zone_r + far + g.ppos.distance_to(g.zone_c)
	var pulse := 0.5 + 0.5 * sin(g.t * 2.5)
	_zone_dark_fast(seg, far, outer)
	draw_zone_band(pulse)
	_zone_next_ring()


## 下一圈预告（虚线）
func _zone_next_ring() -> void:
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
	var view: float = g.view_size().length() * 0.6 + 80.0
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
	# 性能（测试与验收 9/30：黑潮每帧 2.3 毫秒）：只遍历镜头附近那段圆弧的序号（原来整圈 420 段、贴图 900 块逐个算三角函数再判可见）
	var rng_i: Vector2i = _arc_range(n, c, r, vc, view)
	var run_mid := PackedVector2Array()
	var run_out := PackedVector2Array()
	if rng_i.y < rng_i.x:
		return
	var tab: Array = _zone_tab(n)
	var za: PackedFloat64Array = tab[0]
	var zd: PackedVector2Array = tab[1]
	for i in range(rng_i.x, rng_i.y + 1):
		var im: int = posmod(i, n)
		var a: float = za[im]
		var d: Vector2 = zd[im]
		# 内沿潮头：两层正弦叠加并随时间流动；外沿更慢、更宽
		var rin: float = r - 6.0 + 5.0 * sin(a * 23.0 + t * 1.3) + 1.5 * sin(a * 57.0 - t * 2.1)
		var rmid: float = r + 12.0 + 4.0 * sin(a * 31.0 - t * 0.9)
		var rout: float = r + 44.0 + 10.0 * sin(a * 13.0 + t * 0.6) + 5.0 * sin(a * 41.0 - t * 1.4)
		var pin: Vector2 = c + d * rin
		var pmid: Vector2 = c + d * rmid
		var pout: Vector2 = c + d * rout
		var vis: bool = pin.distance_to(vc) < view
		if i > rng_i.x and (vis or prev_vis):
			# 连续可见的一段收集成三条边线，整段画成两个多边形（原来每小段两次 draw_polygon，一屏约 400 次）
			if crest.is_empty():
				crest.append(prev_in)
				run_mid.append(prev_mid)
				run_out.append(prev_out)
			crest.append(pin)
			run_mid.append(pmid)
			run_out.append(pout)
		elif crest.size() > 1:
			_zone_strips(crest, run_mid, run_out, c_in, c_mid, c_out)
			crests.append(crest)
			crest = PackedVector2Array()
			run_mid = PackedVector2Array()
			run_out = PackedVector2Array()
		prev_in = pin
		prev_mid = pmid
		prev_out = pout
		prev_vis = vis
	if crest.size() > 1:
		_zone_strips(crest, run_mid, run_out, c_in, c_mid, c_out)
		crests.append(crest)
	# 溟痕贴图沿圈边密铺：每 26 像素弧长一块（贴图约 60 像素宽，互相叠一半以上，连成一整条），两帧脉动和地上的溟痕一致；
	# 大小、左右翻转、前后位置按序号取固定的伪随机，看不出重复；只画视野内的块（后期同屏元素多，一屏约五六十块）
	var mt: Texture2D = g.tex.get("terrain_mire")
	if mt != null:
		var fw: int = mt.get_width() / 2
		var nb: int = clampi(int(TAU * r / 26.0), 24, 900)
		var rng_j: Vector2i = _arc_range(nb, c, r, vc, view)
		for jr in range(rng_j.x - 1, rng_j.y + 2):
			if rng_j.y < rng_j.x:
				break
			var j: int = posmod(jr, nb)
			var d2: Vector2
			var bp: Vector2
			var bs: float
			var fl: bool
			# 每块的方向 / 径向偏移 / 大小 / 翻转只跟序号走：按块数缓存（同一算式，逐位相同），每帧只算位置
			var bt: Array = _zone_btab(nb)
			d2 = bt[0][j]
			bp = c + d2 * (r + 12.0 + bt[1][j])
			if bp.distance_to(vc) > view:
				continue
			bs = bt[2][j]
			fl = bt[3][j] != 0
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


## 黑潮缩圈快速写法（性能 docs/50 §14，OPT_ZONE）：
## 圈外暗区 seg 段的圆周点按单位方向表（seg + 1 个，算式同 Vector2.from_angle(TAU × i / seg)，末点是 TAU 本身）整组乘 Transform2D 得到
## （zone_c + d × 半径，逐位相同），可见判定同旧写法，整批无索引三角形一次提交（三角形与 tb_quad 的相同、同序）
var _zdark_dirs := {}   # seg -> PackedVector2Array(seg + 1)
var _zone_tabs := {}    # 溟痕带段数 n -> [角度 PackedFloat64Array, 方向 PackedVector2Array]
var _zone_btabs := {}   # 溟痕块数 nb -> [方向, 径向偏移, 大小, 翻转]

func _zone_dark_fast(seg: int, far: float, outer: float) -> void:
	var dirs = _zdark_dirs.get(seg)
	if dirs == null:
		dirs = PackedVector2Array()
		for i in seg + 1:
			dirs.append(Vector2.from_angle(TAU * i / seg))
		_zdark_dirs[seg] = dirs
	var zc: Vector2 = g.zone_c
	var zr: float = g.zone_r
	var pp: Vector2 = g.ppos
	var P: PackedVector2Array = Transform2D(Vector2(zr, 0.0), Vector2(0.0, zr), zc) * dirs
	var Q: PackedVector2Array = Transform2D(Vector2(outer, 0.0), Vector2(0.0, outer), zc) * dirs
	var inside: bool = pp.distance_to(zc) < zr
	var lim: float = far + 400.0
	var out := PackedVector2Array()
	out.resize(seg * 6)
	var k := 0
	var far0: bool = P[0].distance_to(pp) > lim
	for i in seg:
		var far1: bool = P[i + 1].distance_to(pp) > lim
		if inside and far0 and far1:
			far0 = far1
			continue
		far0 = far1
		var p0: Vector2 = P[i]
		var q1: Vector2 = Q[i + 1]
		out[k] = p0
		out[k + 1] = P[i + 1]
		out[k + 2] = q1
		out[k + 3] = p0
		out[k + 4] = q1
		out[k + 5] = Q[i]
		k += 6
	if k == 0:
		return
	out.resize(k)
	tb_flush()
	var cs := PackedColorArray()
	cs.resize(k)
	cs.fill(Color(0.16, 0.03, 0.22, 0.55))
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), PackedInt32Array(), out, cs)


func _zone_tab(n: int) -> Array:
	var t = _zone_tabs.get(n)
	if t == null:
		var aa := PackedFloat64Array()
		var dd := PackedVector2Array()
		for i in n:
			var a: float = TAU * i / n
			aa.append(a)
			dd.append(Vector2.from_angle(a))
		t = [aa, dd]
		if _zone_tabs.size() > 64:
			_zone_tabs.clear()
		_zone_tabs[n] = t
	return t


func _zone_btab(nb: int) -> Array:
	var t = _zone_btabs.get(nb)
	if t == null:
		var dd := PackedVector2Array()
		var ro := PackedFloat64Array()
		var bs := PackedFloat64Array()
		var fl := PackedByteArray()
		for j in nb:
			var a2: float = TAU * (j + 0.5 * sin(j * 12.9898)) / nb
			dd.append(Vector2.from_angle(a2))
			ro.append(7.0 * sin(j * 4.1))
			bs.append(56.0 * (0.85 + 0.25 * (0.5 + 0.5 * sin(j * 7.3))))
			fl.append(1 if int(j * 2654435761) % 2 == 0 else 0)
		t = [dd, ro, bs, fl]
		if _zone_btabs.size() > 64:
			_zone_btabs.clear()
		_zone_btabs[nb] = t
	return t


## 黑潮带的一段连续弧：内沿→中线、中线→外沿两条带，各自画成一个多边形（边线正走、另一边倒走），顶点色和原来逐段画的一致
## 快速写法（docs/50 §15 D1，OPT_BAND）：三条边线首尾接成一个点数组，按「相邻两列四个点两个三角形」的带状剖分（索引表按点数缓存）
## 一次提交；原来 draw_polygon 在引擎里当场耳切三角化（O(n²)）。顶点、顶点色相同，只是带内部的三角形划分不同（渐变插值方向略变）
var _band_idx := {}   # 每条边线点数 m -> [索引 PackedInt32Array, 顶点色 PackedColorArray]

func _zone_strips(pin: PackedVector2Array, pmid: PackedVector2Array, pout: PackedVector2Array, c_in: Color, c_mid: Color, c_out: Color) -> void:
	var m: int = pin.size()
	var t = _band_idx.get(m)
	if t == null:
		var ix := PackedInt32Array()
		ix.resize((m - 1) * 12)
		var k := 0
		for band in 2:   # 先整条内带（内沿→中线），再整条外带（中线→外沿），同原来两个多边形的先后
			var a0: int = band * m
			var b0: int = a0 + m
			for q in m - 1:
				ix[k] = a0 + q
				ix[k + 1] = a0 + q + 1
				ix[k + 2] = b0 + q + 1
				ix[k + 3] = a0 + q
				ix[k + 4] = b0 + q + 1
				ix[k + 5] = b0 + q
				k += 6
		var cs := PackedColorArray()
		cs.resize(m * 3)
		for q in m:
			cs[q] = c_in
			cs[m + q] = c_mid
			cs[2 * m + q] = c_out
		t = [ix, cs]
		if _band_idx.size() > 64:
			_band_idx.clear()
		_band_idx[m] = t
	var pts := PackedVector2Array(pin)
	pts.append_array(pmid)
	pts.append_array(pout)
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), t[0], pts, t[1])


## 圆周分成 n 段时，镜头 vc（半径 view）附近那段弧的序号范围 [x, y]（y 可以超过 n，调用方取模）；整圈都要画时返回 [0, n]，
## 看不到任何一段时返回 y < x
func _arc_range(n: int, c: Vector2, r: float, vc: Vector2, view: float) -> Vector2i:
	var dc: float = vc.distance_to(c)
	if absf(dc - r) > view + 60.0:
		return Vector2i(0, -1)
	if r < 1.0 or dc < 1.0 or view + 60.0 >= r:
		return Vector2i(0, n)
	var half: float = minf(PI, asin(clampf((view + 60.0) / r, 0.0, 1.0)) * 1.3)
	var a0: float = fposmod((vc - c).angle(), TAU)
	var i0: int = floori((a0 - half) / TAU * n) - 1
	var i1: int = ceili((a0 + half) / TAU * n) + 1
	if i1 - i0 >= n:
		return Vector2i(0, n)
	return Vector2i(i0, i1)


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
	# 整个护盾进一批（性能 docs/50 §9 ②：原来 1 + 层数 + 12 + 2 次绘制调用）
	tb_circle(c, r, Color(0.35, 0.7, 1.0, 0.10 + 0.05 * g.shield + 0.3 * fl), 1.0, 40)
	# 外圈 + 内圈（多层时叠加）
	for q in g.shield:
		tb_arc(c, r - q * 4.0, 0.0, TAU, 2.0, Color(0.8, 1.6, 2.4, 0.55 - q * 0.1 + 0.4 * fl), 48)
	# 六边形网格高光
	for q in 6:
		var an := TAU * q / 6.0 + g.t * 0.4
		var p0 := c + Vector2.from_angle(an) * r * 0.62
		var p1 := c + Vector2.from_angle(an + TAU / 6.0) * r * 0.62
		tb_line(p0, p1, Color(0.9, 1.6, 2.2, 0.22), 1.0)
		tb_line(p0, c + Vector2.from_angle(an) * r, Color(0.9, 1.6, 2.2, 0.15), 1.0)
	# 流光
	var sw := fmod(g.t * 1.2, 1.0)
	tb_arc(c, r, -PI * 0.9 + sw * TAU, -PI * 0.6 + sw * TAU, 3.0, Color(2.4, 2.8, 3.0, 0.8), 12)
	tb_circle(c + Vector2(-r * 0.4, -r * 0.45), 4.0, Color(2.4, 2.6, 3.0, 0.5), 1.0, 10)
	tb_flush()


## 用 Sprite2D 的动画状态手动绘制水月，以便和怪物、海草按前后排序
## 角色手感：起步拉伸、停步压扁、转身缩身、奔跑起伏与前倾、挥伞前倾、受击后坐、待机呼吸；脚下扬尘
func update_player_feel(dt: float) -> void:
	if dt <= 0.0:
		return
	var target_sq := Vector2.ONE
	var target_lean := 0.0
	var alive: bool = g.state != Game.S.DEAD
	if g.state == Game.S.OPENING:
		return   # 开场演出期间的角色姿态由 intro.update_opening 摆（update_visuals 里先调）
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
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + g.sprite.offset, Vector2(fw, fh)), src, dmod * Look.actor_mod(g, g.sprite.position))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
