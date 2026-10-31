extends RefCounted
## 世界绘制（2.5D）：地图之上按纵深排序画敌人 / 主控 / 编队 / 博士挂件 / 特效，缩圈与护盾；主控与博士的动画状态、手感（压缩 / 拉伸 / 扬尘）。
## game.gd 的 _draw 只转发到这里。地图本身在 world/map.gd，HUD 在 screens/hud.gd。2026-09-26 从 game.gd 拆出。

const LaserDraw = preload("res://scripts/render/laser_draw.gd")
const FinalAttackDraw = preload("res://scripts/render/boss_attack_draw.gd")
const IsharTell = preload("res://scripts/render/ishar_tell_draw.gd")
const MidCardDraw = preload("res://scripts/render/mid_card_draw.gd")   # 塑路者 / 接潮组弹体与预警（docs/170）
const BossBeam = preload("res://scripts/render/boss_beam.gd")   # Boss 改版样板：Kanpelle 光束、骑士寒气圈 / 寒冷条（docs/142b）
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
const LAMP_READ_EXT := 1.6   # 可读灯圈：余光延到灯半径的倍数，game.gd 的灯光贴图按它生成
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
## 开火微震（vfx._leader_kick）：方向（远离目标）、美术像素、剩余 / 总时长；cam.offset 按阶梯取整（1 px → 0；2 px → 1 → 0），不动 cam.position
var _kick_dir := Vector2.ZERO
var _kick_px := 0
var _kick_t := 0.0
var _kick_dur := 0.06


func kick(to_target: Vector2, px: int, dur: float) -> void:
	if px <= 0 or (_kick_t > 0.0 and px <= _kick_px):
		return
	var d: Vector2 = -to_target
	# 八方向取整：斜向时两轴各挪同样的整像素
	_kick_dir = Vector2(signf(d.x) if absf(d.x) > absf(d.y) * 0.4 else 0.0, signf(d.y) if absf(d.y) > absf(d.x) * 0.4 else 0.0)
	_kick_px = px
	_kick_dur = maxf(0.01, dur)
	_kick_t = _kick_dur
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
var mate_desat := 0.0             # 队友特效去饱和（docs/139 §10，render/mate_desat）
var lead_boost := 1.0             # 队长特效提亮（docs/139 §11，render/lead_emph 档位或 render/lead_boost）
var lead_tint := 0.0              # 队长特效暖色偏移（render/lead_tint）
var lead_num_k := 1.0             # 队长伤害数字放大（render/lead_num_k）
var lead_lv := 0                  # render/lead_emph：0 关 / 1 中 / 2 强
var mate_on := false              # render/mate_layer 开着（缺省关）：子弹 / 刀光 / 命中颗粒才按队友另压
var ol_mul := 1.0                 # 普通怪描边透明度系数（随 ecrowd 降到 declutter ol_floor；原来写死 0.4）
var _lamp_rim := false              # 朝灯边缘亮线原型（balance render/rim > 0 且白色保护材质在）：敌人本体绘制的 alpha 取负作标记，actor_light.gdshader 认
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
# docs/139 §8 怪物攻击圈环盘点（量测，只隐藏不改逻辑）：nowarn 地面预警（填充 + 轮廓）、notell 敌人自带危险提示、nofoefx 敌方一次性特效、
# noshock 冲击环、noaura 光环（巢涌者 / 伪人负担圈）
var _dbg_warn: bool = Dc.dbg("nowarn")
var _dbg_tell: bool = Dc.dbg("notell")
var _dbg_foefx: bool = Dc.dbg("nofoefx")
var _dbg_shock: bool = Dc.dbg("noshock")
var _dbg_aura: bool = Dc.dbg("noaura")
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
## 紧急作战精英小队（docs/161，e.squad）：危险红描边（> 1 抵消环境暗色）；颜色语言：红只给危险。脚下红光 10-26 用户去掉（「红色描边就可以」）；
## 原 (2.6, 0.45, 0.45) 过曲线后发粉，压低绿蓝通道成正红（10-26 第二次反馈）；身体本色不调
const SQUAD_RIM_COL := Color(2.4, 0.16, 0.12, 0.95)
var elite_rim := 0.0
var elite_rim_col := Color(0, 0, 0, 0)
var _afast := false               # 本帧缓存路径走图集快速路径（_dc_emit）
static var _atlas_cache := {}      # 上一次拼好的图集（键：帧条名单 + 镜像 / 法线开关；贴图 instance id 也须相同）
var atlas: EnemyAtlas = null      # 普通怪 / 精英帧条图集（docs/50 §12 B，build_enemy_atlas）；null = 全走原帧条贴图
var dc_on := true                 # 敌人画法缓存（docs/50 §9.9）：balance.json fx/enemy_draw_cache（缺省 1），0 = 全走原路径（对照用）
var dc_check := false             # --dccheck：抽查缓存路径与原路径发出的贴图绘制参数，不一致报 SCRIPT ERROR（快检冒烟开着）
var dc_checked := 0               # --dccheck 实际比对的次数（BALANCE prof.dc_checked）
var _rec = null                   # --dccheck 比对时：贴图绘制只记参数、不画
const CROWD_FROM := 80.0          # 特效总数超过这个开始降
const CROWD_SPAN := 220.0         # 再多这么多降到底
## 会被降透明度的友方特效种类（敌方的 rift / bbeam、治疗十字、地面血迹不降）
const DIM_KINDS := ["explode", "burst", "rays", "ring", "impact", "bslash", "slash", "spark", "shard", "wpillar", "pillar", "beam", "tracer", "quake", "sprite", "frost", "tide_link", "frost_track"]
const FOE_KINDS := ["boss_phase", "boss_down", "spear_fly", "frost_track", "frost_step", "reflow", "glint", "drain"]   # 没打 enemy 标记的敌方 / Boss 特效（量测分层用）
const AMB_KINDS := ["mote", "beacon_burst", "mire_recoil"]   # 系统 / 环境（光尘、大群波、灯标）：量测单独一层
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane"}
## 水月旧主角动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。帧为正方形，画布 48 或 64（docs/103 §5），
## 脚底锚点读 mizuki.json sprites.foot（48 画布 (24,46)、64 画布 (32,60)）。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _init(game: Game) -> void:
	g = game
	bulfx = preload("res://scripts/render/bullet_fx.gd").new(game, self)
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
	elif g.invuln > maxf(0.0, g.invuln_move_until - g.t) + 0.001 and int(g.invuln * 20.0) % 2 == 0:   # 技能位移的短暂无敌不闪（闪烁 0.6 透明在空中翻转时读成虚化）
		g.sprite.modulate = Color(1, 1, 1, 0.6)
	else:
		g.sprite.modulate = Color.WHITE
	var rd := g.get_process_delta_time()
	g.glance_step(rd)   # 镜头一瞥（game.camera_glance：骑士入潮 / 寒冰重生时看一眼黑潮中心；只动镜头）
	# docs/139 试验旋钮 render/cam_round：1 = 取整到 1 世界像素（缺省，现状）；0 = 不取整（低分辨率层靠 lo_rect 亚像素补偿，地面匀速）；
	# 2 = 取整到 1 美术像素（= 低分辨率格，与队长绘制同一格）
	var cround: float = Bal.v("render/cam_round", 1.0)
	var ccen: Vector2 = g.cam_center()
	g.cam.position = ccen.round() if cround == 1.0 else ((ccen / Game.PX).round() * Game.PX if cround >= 2.0 else ccen)
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
	var kick_off := Vector2.ZERO
	if _kick_t > 0.0:
		_kick_t = maxf(0.0, _kick_t - rd)
		kick_off = _kick_dir * float(ceili(_kick_px * _kick_t / _kick_dur)) * Game.PX
		if _kick_t <= 0.0:
			_kick_px = 0
	g.cam.offset = cam_kick.round() + kick_off + (g.ult.shake_off() if g.ult != null else Vector2.ZERO)   # 终结技轻震（用户 10-30 点名要，只给终结技；减少动态效果开时为 0）
	# 灯火光源：可读灯圈（10-24 用户定；旧开关 render/lamp_readable 与闪烁 / 低灯变红的旧灯光 10-29 已删）——
	# 圈内亮度固定、不闪、低灯不变红，灯火变弱只缩半径
	var radius: float = lerp(150.0, 520.0, g.lamp / 100.0) * g.squad.light_radius_mult()
	if g.state == Game.S.DEAD:
		radius *= 1.0 - clampf(g.state_age / Game.HudView.DEATH_LAMP_T, 0.0, 1.0)   # 倒下过渡：灯火熄灭（hud.draw_death_transition）
	g.lamp_light.position = g.ppos + Vector2(0, -20)
	g.lamp_light.texture_scale = radius * LAMP_READ_EXT / 64.0
	g.lamp_light.color = Color(1.0, 0.98, 0.94)
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
	# 海中浮游颗粒
	g.map.update_snow(dt, g.view_size())
	_enemy_act_fx()
	# 特效密度 → 友方特效降噪（图鉴演示不降，演示本来就是看特效的）
	var nfx: int = g.fx.size()
	for o in g.squad.ops:
		nfx += o.pfx.size()
		if o.arrive_t >= 0.0:
			o.arrive_t = -1.0 if not o.arriving() else o.arrive_t + dt   # 换人入场的下落计时（character.arrive_dy）
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
	# 主次分层试验（docs/139 §10）：render/mate_layer 1 = 队友特效恒定压到 render/mate_fx（0.55）并去饱和 render/mate_desat；
	# 用户 10-25「队友特效不要降，想其它办法」→ 缺省 0（只剩原来的拥挤降噪），改走 §11「突出队长」
	mate_desat = 0.0
	# 突出队长（docs/139 §11，用户 10-25「队友特效不要降」「队长明不明显没看太出来」）：render/lead_emph 1 = 中、2 = 强；
	# 各参数可用同名键单独覆盖。图鉴演示不加
	lead_lv = Bal.vi("render/lead_emph", 1) if g.demo_op == "" else 0
	lead_boost = Bal.v("render/lead_boost", [1.0, 1.35, 1.6][clampi(lead_lv, 0, 2)])
	lead_tint = Bal.v("render/lead_tint", [0.0, 0.0, 0.3][clampi(lead_lv, 0, 2)])
	lead_num_k = Bal.v("render/lead_num_k", [1.0, 1.35, 1.6][clampi(lead_lv, 0, 2)])
	mate_on = Bal.v("render/mate_layer", 0.0) > 0.0 and g.demo_op == ""
	if mate_on:
		mate_dim = minf(mate_dim, Bal.v("render/mate_fx", 0.55))
		mate_desat = Bal.v("render/mate_desat", 0.35)
	if _dbg_friend:
		fx_dim = 0.0   # --clutterdbg=nofriend：友方特效全透明（代码照跑、随机数照抽）
	ol_mul = lerpf(1.0, Dc.p("ol_floor"), ecrowd)
	flash_a = lerpf(0.9, Dc.p("flash_a"), ecrowd)
	_lamp_rim = (Bal.v("render/rim", 0.0) > 0.0 or g.optical_on) and g.get("actor_mat") != null
	# 集体白闪封顶（docs/127 FX-A1，10-23）：同一帧在白闪的普通怪超过 fx/flash_group（缺省 6）只时，白闪按 6 / 只数 压淡（最低 fx/flash_group_floor），
	# 群伤技能不再把一整片怪刷成白块盖住技能本体与队长；精英 / Boss 不受影响（纯画面）
	var nfl := 0
	for e in g.enemies:
		if e.flash > 0.0 and not e.elite and not e.boss:
			nfl += 1
	var fg: float = Bal.v("fx/flash_group", 6.0)
	if nfl > fg:
		flash_a *= maxf(Bal.v("fx/flash_group_floor", 0.35), fg / float(nfl))
	spark_left = int(Dc.p("spark_budget")) if Dc.p("spark_budget") > 0.0 else 1 << 30
	elite_rim = clampf(Bal.v("render/elite_rim", 0.55), 0.0, 1.0)
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
	var bc: Color = g.vfx.boss_color(str(b.get("type", "")))
	g.fx.append({"kind": "boss_down", "pos": b.pos, "r": maxf(b.r, 24.0), "life": 1.6, "max": 1.6, "bcol": bc})
	g.vfx.sparks(b.pos, Vector2.ZERO, Color(bc.r * 1.5, bc.g * 1.5, bc.b * 1.5), 30, 420.0)
	g.vfx.sparks(b.pos, Vector2.UP, Color(bc.r * 0.9, bc.g * 0.9, bc.b * 0.9), 16, 360.0)
	# 全屏白闪去掉（docs/137 不闪白；用户 10-25 特效精修）：改成专属色颗粒爆散 + 升起的余烬
	var gr0 = BossBeam.grains(g)
	if gr0 != null:
		var gr = _BfxCap.new(gr0, BossBeam.take(g, 130))
		for i in 90:
			var d := Vector2.from_angle(g.vrng.randf() * TAU)
			gr.push("bfx_burst", b.pos + d * float(b.r) * g.vrng.randf_range(0.0, 0.6), d, bc, g.vrng.randf() * 0.25)
		for i in 40:
			gr.push("bfx_dust", b.pos + Vector2(g.vrng.randf_range(-1.2, 1.2) * float(b.r), g.vrng.randf_range(-1.0, 0.4) * float(b.r)), Vector2.UP, bc, g.vrng.randf() * 0.6)
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
	bulfx.frame()   # 子弹出现 / 消失（render/bullet_fx.gd）：先认出本帧新弹 / 消失的弹，下面各遍画弹时乘出现缩放
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
	if g.ult != null:
		g.ult.draw_world_back(self)   # 终结技地面层帧条（刀痕残痕 / 领域 / 裂纹 / 海嗣水纹）
	g.squad.draw_ground_fx()   # 干员紧贴地砖的大片地面特效（docs/61 §5.6 layer = ground）：压在溟痕 / 地面预警之下
	_pk("ground")
	_draw_mires()
	_pk("mire")
	tell_fill = Dc.p("tell_fill_k")
	tell_edge = Dc.p("tell_edge_k")
	_draw_warns_auras()
	if not _dbg_foe:
		_draw_ground_foe_fx()
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
	BossBeam.draw_top(g)   # 主控寒冷条（骑士在场时）
	_pk("fx")
	if not _dbg_foe:   # --clutterdbg=nofoe：敌方弹幕 / 预警整层不画（量测）
		bulfx.draw_trails()   # Boss 弹拖尾光粒（压在弹体之下，docs/206 §2）
		_draw_ebullets_lobs_shocks()
	bulfx.draw_top()   # 新弹亮芯闪 + 消失残影（压在弹体之上）
	_draw_hit_dot()
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
	var mote_budget: int = MIRE_MOTE_MAX if g.vfx.ambient_ok() and g.vfx._kv("mire_motes", 3.0) > 0.0 else 0   # docs/54 溟痕光尘（高画质、非触屏）
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
		g.vfx.spr_rot(f.name, fr, f.pos, f.ang, g.vfx.int_scale(f.scale), f.get("col", Color.WHITE), f.get("anchor", Vector2(-1, -1)), f.get("flip", false))


## 地面层敌方特效（ground 标记，用户 10-24：奠基者踏地「浮在最上面」）：小怪踏地的地裂与冲击环画在地面预警之上、单位之下，
## 不盖住干员和其他单位。纯画面
func _draw_ground_foe_fx() -> void:
	for f in g.fx:
		if f.kind == "ice_sheet" and f.life > 0.0:
			_draw_ice_sheet(f)
	for f in g.fx:
		if f.kind == "gcrack" and f.get("ground", false) and f.life > 0.0:
			if not f.has("cd"):
				f["cd"] = GroundCrack.build(f.pos, f.r, f.get("ang"), f.get("opts", {}))
			GroundCrack.draw(f.cd, f.max - f.life, clampf(f.life / f.max, 0.0, 1.0), f.col, _gc_sink, float(f.get("grow_t", 0.06)), float(f.get("hot", 1.0)))
	tb_flush()
	for sh in (g.shocks if not _dbg_shock else []):
		if sh.get("ground", false):
			_draw_shock(sh)
	BossBeam.draw_ground(g)   # 骑士寒气圈（docs/142b §3.1）
	draw_warn_outlines(true)


## 骑士冲锋留下的冰面（10-28 用户「冰面的视觉效果需要修改」）：原来借「冰线」画法（黑底 + 锯齿亮脊）像焦痕 / 电弧。
## 改为地面层的一整片浅冰：半透明冰白底 + 两侧亮边 + 偏一侧的高光带 + 短冰裂 + 闪点；宽 52（寒冷条判定半径 26 × 2），
## 最后 30% 寿命淡出。只画画面，不抽随机（裂纹、闪点按段号取）
func _draw_ice_sheet(f: Dictionary) -> void:
	var pts: Array = f.pts
	if pts.size() < 2:
		return
	var a: float = clampf(f.life / f.max / 0.3, 0.0, 1.0)
	var w := 52.0
	var body := PackedVector2Array()
	var l := PackedVector2Array()
	var r := PackedVector2Array()
	var hi := PackedVector2Array()
	for i in pts.size():
		var p: Vector2 = pts[i]
		var d: Vector2 = ((pts[mini(i + 1, pts.size() - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var n := d.orthogonal()
		body.append(p)
		l.append(p + n * w * 0.5)
		r.append(p - n * w * 0.5)
		hi.append(p + n * w * 0.2)
	g.draw_polyline(body, Color(0.7, 0.88, 1.0, 0.24 * a), w)
	g.draw_polyline(hi, Color(0.95, 1.0, 1.0, 0.16 * a), 6.0)
	g.draw_polyline(l, Color(0.88, 0.97, 1.0, 0.6 * a), 2.0)
	g.draw_polyline(r, Color(0.6, 0.8, 0.95, 0.45 * a), 2.0)
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var seg := p1 - p0
		var sl := seg.length()
		if sl < 1.0:
			continue
		var d2 := seg / sl
		var n2 := d2.orthogonal()
		var k := int(sl / 60.0) + 1
		for q in k:
			var h: int = (i * 131 + q * 977) & 1023
			var at: Vector2 = p0 + d2 * sl * (float(q) + 0.5) / float(k) + n2 * (float(h % 31) - 15.0)
			var ca := d2.rotated(0.6 if h & 1 else -0.6)
			g.draw_line(at - ca * 8.0, at + ca * 8.0, Color(0.55, 0.78, 0.95, 0.55 * a), 2.0)
			g.draw_line(at + ca * 8.0, at + ca * 8.0 + d2 * 6.0, Color(0.55, 0.78, 0.95, 0.4 * a), 2.0)
			if (h >> 3) % 3 == 0 and fmod(g.t * 1.5 + float(h % 7) * 0.3, 2.0) < 0.35:
				g.draw_rect(Rect2(((at + n2 * 10.0) * 0.5).floor() * 2.0, Vector2(2, 2)), Color(1.0, 1.0, 1.0, 0.9 * a))


## 预警分类 → Boss 招式预警填充（render/telegraph_draw）→ 巢涌者光环 → 灯标 → 藏品特效 → 商人
func _draw_warns_auras() -> void:
	classify_tells()   # 先判哪些预警会打到主控（可读性 1.1.1）：地面填充 / 轮廓 / 冲刺线都读这个结果
	if not _dbg_foe and not _dbg_warn:
		TeleDraw.draw_fills(g)
		IsharTell.draw(g)   # 伊莎玛拉预警（docs/170）
		FinalAttackDraw.draw(g)
		MidCardDraw.warns(g)
	if not _dbg_aura:
		draw_nest_auras()
	draw_beacons()
	if not _dbg_friend:
		g.rfx.draw()   # 藏品特效（--clutterdbg=nofriend 量测时不画；只画不抽随机数）
	if not g.merchant.is_empty():
		var mtx: Texture2D = g.tex.merchant
		var big_m: bool = mtx != null and mtx.get_height() >= 40
		g.vfx.spr("shadow", 1, 0, g.merchant.pos + Vector2(0, 18), Game.PX * (1.6 if big_m else 1.2))
		if big_m:
			var mfr: int = int(g.t * 2.0) % 2
			var mflip: bool = g.ppos.x < g.merchant.pos.x
			g.vfx.spr("merchant", 2, mfr, g.merchant.pos + Vector2(0, 18), Game.PX / A.hires_of(mtx), mflip, Color.WHITE, Vector2(0.5, 45.0 / 48.0))   # @2x（10-21 坎诺特）不放大世界尺寸
		else:
			g.vfx.spr("merchant", 2, int(g.t * 2.0) % 2, g.merchant.pos, Game.PX)
		# 「商人 %ds」标签由 HUD 层在头顶绘制（_draw_hud 商人方向指示），这里不再重复画一份


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
	var pu := Color(0.85, 0.6, 1.0)
	if g.optical_on:
		cy = g.optical.col_loot   # 光学观感颜色语言（10-23）：经验结晶光晕 / 吸取拖尾淡金白（结晶贴图本身是美术，不改）
		pu = g.optical.col_loot.lerp(Color.WHITE, 0.3)
	var glow_s0 := Color(cy.r * 1.6, cy.g * 1.6, cy.b * 1.6, 0.16)
	var glow_s1 := Color(cy.r * 2.0, cy.g * 2.0, cy.b * 2.0, 0.22)
	var glow_b0 := Color(pu.r * 1.6, pu.g * 1.6, pu.b * 1.6, 0.16)
	var glow_b1 := Color(pu.r * 2.0, pu.g * 2.0, pu.b * 2.0, 0.22)
	var dark := Color(0.0, 0.02, 0.05, 0.55)
	var quiet_col := Color(0.9, 0.95, 1.0, gem_qa)
	var lit_s := Color(1.25, 1.25, 1.3)
	var lit_b := Color(1.35, 1.2, 1.5)
	var lit_m := Color(-1, 0, 0)   # 被磁铁 / 拾取范围吸起时的颜色（< 0 = 同落地）
	var core := Color(-1, 0, 0)    # 发光层主高光颜色（< 0 = 同贴图调色）
	var gs: int = int(Bal.v("render/gem_style", 2.0))
	if gs > 0:
		# 经验结晶调色候选（用户 10-29「地上的经验现在是白色，不明显」，docs/128 §6.1）：贴图本身淡金白，这里只改调色，零额外开销。
		# 层级：小 = 浅、大 = 更饱和更亮 + 光晕大一圈、吸起 = 提亮近白 + 同色拖尾、远处安静 = 压暗去饱和
		var hs: Array = GEM_TINT[gs - 1]
		lit_s = hs[0]
		lit_b = hs[1]
		lit_m = hs[2]
		quiet_col = Color(hs[3].r, hs[3].g, hs[3].b, gem_qa)
		cy = hs[4]
		pu = hs[5]
		core = hs[6]
		glow_s0 = Color(cy.r * 1.6, cy.g * 1.6, cy.b * 1.6, 0.16)
		glow_s1 = Color(cy.r * 2.0, cy.g * 2.0, cy.b * 2.0, 0.22)
		glow_b0 = Color(pu.r * 1.6, pu.g * 1.6, pu.b * 1.6, 0.2)
		glow_b1 = Color(pu.r * 2.0, pu.g * 2.0, pu.b * 2.0, 0.26)
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
				_gt_line(gp, gp + dv * tl * GEM_VIS, Color(gc.r * 1.8, gc.g * 1.8, gc.b * 1.8, 0.55), (5.0 if big else 3.0) * GEM_VIS)
				_gt_line(gp, gp + dv * tl * 0.6 * GEM_VIS, Color(2.5, 2.5, 2.5, 0.7), 1.5 * GEM_VIS)
			if not quiet:
				_gt_circle(gp, (13.0 if big else 9.0) * tw * GEM_VIS, glow_b0 if big else glow_s0, _gt_fan14, _gt_c42)
				_gt_circle(gp, (7.0 if big else 4.5) * tw * GEM_VIS, glow_b1 if big else glow_s1, _gt_fan14, _gt_c42)
			_gt_circle(gp + Vector2(0, 1), (6.5 if big else 4.5) * GEM_VIS, dark, _gt_fan10, _gt_c30)
			var gcol: Color = quiet_col if quiet else (lit_b if big else lit_s)
			if mag and lit_m.r >= 0.0:
				gcol = lit_m.lerp(lit_b, 0.35) if big else lit_m
			if big:
				big_p.append(gp)
				big_c.append(gcol)
			else:
				small_p.append(gp)
				small_c.append(gcol)
			if not quiet:
				spark.append([gp, (2.0 + 1.5 * tw) * GEM_VIS, tw])
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
	_gem_sprites("gem_big", Game.PX, big_p, big_c, core)
	_gem_sprites("gem_small", Game.PX, small_p, small_c, core)
	for sk in spark:
		var gp2: Vector2 = sk[0]
		var sp3: float = sk[1]
		var wc := Color(2.5, 2.5, 2.5, 0.5 * sk[2])
		var sy: float = -8.0 * GEM_VIS
		_gt_line(gp2 + Vector2(-sp3, sy), gp2 + Vector2(sp3, sy), wc, 1.0)
		_gt_line(gp2 + Vector2(0, sy - sp3), gp2 + Vector2(0, sy + sp3), wc, 1.0)
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
	_gem_sprites("gem_small", Game.PX, mp_s, qc)
	_gem_sprites("gem_big", Game.PX, mp_b, qc)


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
		"magnet", "heal", "pack":
			_pq_sprite("pickup_" + ("heal" if kind == "pack" else kind), pos + Vector2(0, -2 + (sin(t * 3.5) * 2.0 if gz <= 1.0 else 0.0)))   # 应急补给先用回复药剂的贴图占位（素材单 art/incoming/codex_order_supply_crate.md）
	g.draw_off = Vector2.ZERO


## 同一张结晶贴图连续画（FrameDst.dst 的同一套算式：单帧、锚点居中、取整；热循环内联，docs/50 §11）
## 经验结晶显示倍率（10-21 用户实玩「结晶画得太大」）：贴图、光晕、暗底、闪光、吸附拖尾一起缩；拾取判定不读它
const GEM_VIS := 0.75

## 经验结晶 / 源石锭 / 灯油的贴图（同贴图连续合批）。左上角吸附到美术像素格（PX 世界单位；奇数宽的大结晶不落半像素，Codex world_spec_1024）。
## 结晶带 _emit 发光层（gem_small_emit / gem_big_emit，只有主高光像素）时，光学观感下同位置 1:1 排进发光层，取代 optical._draw_loot 的单个发光点
var gem_emit := false
var _gem_e := {}
var _mde = 0   # fx_mire_dissolve_emit 贴图（0 = 还没查）


func _mire_dissolve_emit() -> Texture2D:
	if typeof(_mde) == TYPE_INT:
		_mde = A.tex("fx_mire_dissolve_emit") if A.has_override("fx_mire_dissolve_emit") else null
	return _mde

## 经验结晶调色候选（render/gem_style 1 / 2）：[小, 大, 吸起, 远处安静, 小光晕 / 拖尾, 大光晕 / 拖尾, 发光层主高光]。
## 贴图是淡金白（约 242,233,210），调色 = 目标色 ÷ 贴图色；>1 的分量在 HDR 下更亮
const GEM_TINT := [
	# 1 柠檬黄：与顶部经验细条 #ffe65c 同色；灯火是橙金（色相 0.075），结晶取 0.15 偏绿的黄，饱和更高
	[Color(1.12, 1.06, 0.45), Color(1.3, 1.14, 0.3), Color(1.45, 1.4, 0.9), Color(0.85, 0.82, 0.45),
		Color(1.0, 0.92, 0.35), Color(1.0, 0.85, 0.2), Color(1.0, 0.97, 0.75)],
	# 2 淡青绿带亮芯：色相约 0.42，避开海嗣发光 / 敌弹青蓝（0.54–0.55）与环境暗青灰（低饱和）；高光像素近白
	[Color(0.6, 1.12, 0.85), Color(0.4, 1.2, 0.75), Color(1.15, 1.45, 1.3), Color(0.6, 0.85, 0.75),
		Color(0.45, 1.0, 0.72), Color(0.3, 1.0, 0.6), Color(1.6, 1.7, 1.65)],
	# 3 宝蓝带白芯（用户 10-29「蓝色行不行」）：色相约 0.63，比海嗣发光 / 敌弹青蓝（0.54–0.55）偏紫、更深更饱和；高光像素近白
	[Color(0.45, 0.64, 1.21), Color(0.3, 0.47, 1.25), Color(1.0, 1.15, 1.45), Color(0.5, 0.6, 0.85),
		Color(0.4, 0.6, 1.0), Color(0.3, 0.45, 1.0), Color(1.6, 1.65, 1.75)],
	# 4 金色（用户 10-29「或者金色」）：色相约 0.12，介于灯火橙金（0.075）与柠檬黄之间；灯油掉落贴图也是橙金，靠更亮的白芯区分
	[Color(1.05, 0.86, 0.33), Color(1.1, 0.78, 0.2), Color(1.4, 1.25, 0.8), Color(0.85, 0.72, 0.4),
		Color(1.0, 0.75, 0.25), Color(1.0, 0.65, 0.15), Color(1.7, 1.55, 1.2)],
	# 5 翠绿带白芯（用户 10-29「柠檬黄不是很好看」）：色相约 0.36，比候选 2 更饱和；与队友生命绿同色系但不同层（地面 vs HUD）
	[Color(0.37, 1.03, 0.57), Color(0.21, 0.99, 0.43), Color(0.9, 1.35, 1.0), Color(0.45, 0.75, 0.5),
		Color(0.3, 1.0, 0.45), Color(0.2, 1.0, 0.35), Color(1.5, 1.75, 1.5)],
	# 6 亮紫带白芯：色相约 0.76；敌弹已改青蓝，紫让出来了；危险色是洋红偏红（0.95），紫偏蓝一侧
	[Color(0.83, 0.6, 1.21), Color(0.74, 0.43, 1.21), Color(1.3, 1.1, 1.5), Color(0.7, 0.55, 0.85),
		Color(0.8, 0.5, 1.0), Color(0.7, 0.35, 1.0), Color(1.75, 1.6, 1.8)],
]

func _gem_sprites(name: String, sc: float, ps: PackedVector2Array, cs: PackedColorArray, core := Color(-1, 0, 0)) -> void:
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
	if not _gem_e.has(name):
		_gem_e[name] = A.tex(name + "_emit") if A.has_override(name + "_emit") else null
		gem_emit = _gem_e.get("gem_small") != null or _gem_e.get("gem_big") != null
	var etx: Texture2D = _gem_e[name] if g.optical_on else null
	for i in ps.size():
		var dst := Rect2(((ps[i] - half) / Game.PX).round() * Game.PX, size)
		g.draw_texture_rect_region(tx, dst, src, cs[i])
		if etx != null:
			g.glow_tex_next.append([etx, dst, src, cs[i] if core.r < 0.0 else core])


## Boss 登场聚光、博士 / 敌人 / 干员 / 骑士的影子、干员脚下层；evr：ENTITY_MARGIN 视野矩形（排序层共用）
func _draw_shadows(evr: Rect2) -> void:
	g.boss_intro.draw_world()   # Boss 登场：脚下聚光圈 + 扩散环（合批；没有登场时直接返回）
	g.vfx.spr("shadow", 1, 0, g.doc_pos + Vector2(0, 6), Game.PX * 1.3)
	g.squad.draw_auras()
	var stx: Texture2D = g.tex.get("shadow")
	var ens: Array = _vis_ent if _vis_on else g.enemies
	var nsh: bool = g.has_meta("boss_decoys")   # 泡影二幕幻影不画影子（docs/142b §3.5：只有真身在地上有影子）；平时不多查字段
	if stx == null:
		for e in ens:
			if not evr.has_point(e.pos) or (nsh and e.has("no_shadow")):
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
			if not evr.has_point(ep) or (nsh and e.has("no_shadow")):
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
		if g.optical_ops_hi:
			break   # 光学观感高清干员层（render/optical_ops_hi）：干员本体改由 render/optical.gd 画（全分辨率，统一压在怪物上面）
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
					var t0 := Time.get_ticks_usec() if g.prof_on else 0
					ob.draw_body()
					if g.prof_on:
						g.prof_add("op_body_" + str(ob.id), t0)   # 干员本体绘制（docs/50 §37）
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
## 判定点（10-29，enemy/bullet_core_hit）：队长身上一个 2 格白芯 + 暗细描边的小点（敌弹按弹芯打这里），压在弹幕之上。
## 全程都画：平时 boss/hit_dot_idle（0.06，几乎看不见）；boss/hit_dot_near（110）像素内有敌弹时渐亮到 0.85；
## 有活着的 Boss 时不低于 boss/hit_dot_boss（0.6）；站定再 ×0.6。纯画面
var _dot_a := 0.0


## 加层预警（shot_pool.layer_q）：同一发射点、同一时刻只画一个收拢圈（专属色），离出弹越近越小越亮；纯画面
func _draw_layer_warns() -> void:
	if g.shots == null or g.shots.layer_q.is_empty():
		return
	var seen := {}
	for q in g.shots.layer_q:
		var key := Vector3i(int(q[1].x / 8.0), int(q[1].y / 8.0), int(float(q[0]) * 10.0))
		if seen.has(key):
			continue
		seen[key] = true
		var left: float = float(q[0]) - g.t
		var kk: float = clampf(left / 0.6, 0.0, 1.0)
		var c: Color = q[3]
		tb_ring(q[1], 10.0 + 26.0 * kk, 2.0, Color(c.r, c.g, c.b, 0.35 + 0.5 * (1.0 - kk)))
		tb_circle(q[1], 4.0, Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, 0.3 + 0.6 * (1.0 - kk)), 1.0, 8)
	tb_flush()


func _draw_hit_dot() -> void:
	_draw_layer_warns()
	# 调试：--hitcircles 画出每颗敌弹的判定圈（绿）和队长判定点（白），录对照用；只开发版
	if OS.is_debug_build() and Cfg.dev_args().has("--hitcircles") and g.shots != null:
		for b in g.ebullets:
			if b.life > 0.0:
				tb_ring(g.shots.hit_c(b), g.shots.hit_r(b), 1.5, Color(0.3, 2.0, 0.6, 0.95))
		tb_circle(g.ppos + Vector2(0, -14), 3.0, Color(2.0, 2.0, 2.0), 1.0, 8)
		tb_flush()
	if g.shots == null or not g.shots.core_hit_live():
		return
	var p: Vector2 = g.ppos + Vector2(0, -14)
	var near: float = Bal.v("boss/hit_dot_near", 110.0)
	var want: float = Bal.v("boss/hit_dot_idle", 0.06)
	for b in g.ebullets:
		if b.life > 0.0 and absf(b.pos.x - p.x) < near and absf(b.pos.y - p.y) < near and b.pos.distance_to(p) < near:
			want = 0.85
			break
	if g.bosses.any(func(e): return not e.dead):
		want = maxf(want, Bal.v("boss/hit_dot_boss", 0.6))
	if g.leader_still_t > 0.3:
		want *= 0.6
	_dot_a = move_toward(_dot_a, want, g.get_process_delta_time() * (4.0 if want > _dot_a else 1.5))
	if _dot_a < 0.02:
		return
	var c: Vector2 = (p * 0.5).floor() * 2.0
	g.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0.02, 0.05, 0.08, 0.55 * _dot_a))
	g.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 1.0, 1.0, _dot_a))


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
	if g.ult != null:
		g.ult.draw_world(self)   # 终结技瞄准指示 + 程序占位图形（docs/198 原型）
	draw_shield()
	draw_panel_grace()
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
			g.vfx.spr("drone_laser", 4, dfr, (dr.pos / Game.PX).round() * Game.PX, Game.PX / A.hires_of(g.tex.drone_laser), dr.get("face", 1.0) < 0.0, Color(0.85, 1.25, 0.95))   # 24×20 × 4 原生 1x，按 PX 1:1（world_spec_1024）
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
	var lid: String = str(g.ch.id) if g.ch != null else ""
	for b in g.bullets:
		if b.life <= 0.0 or b.get("hidden", false):
			continue
		_bmate = mate_on and b.has("op") and str(b.op) != lid   # 队友的弹：再乘队友系数（docs/139 §10）
		_blead = lead_lv > 0 and b.has("op") and str(b.op) == lid   # 队长的弹：提亮 / 暖色（docs/139 §11）
		var n: Vector2 = b.vel.normalized()
		var vk: float = bulfx.k(b)   # 出现动画缩放（render/bullet_fx.gd）
		# 美术 V6：投射物帧条（朝右绘制，按速度方向旋转）；程序只画拖尾
		var ptex: String = PROJ_TEX.get(b.kind, "")
		if ptex != "" and g.tex.get(ptex) != null:
			var pspec: Array = Game.V6_FRAMES[ptex]
			var pfr: int = (int(g.t * pspec[1] + b.pos.x * 0.01) % int(pspec[0])) if pspec[1] > 0.0 else 0
			match b.kind:
				"arrow":
					g.draw_line(b.pos - n * 34.0, b.pos - n * 12.0, _bc(Color(1.6, 1.4, 1.0, 0.3)), 2.0)
				"fire":
					g.draw_circle(b.pos, 14.0 * vk, _bc(Color(1.4, 0.6, 2.2, 0.2)))
				"arcane":
					g.draw_line(b.pos - n * 20.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.35)), 4.0)
			g.vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), Game.PX * vk, _bc(Color.WHITE))
			continue
		match b.kind:
			"arrow":
				g.draw_line(b.pos - n * 26.0, b.pos - n * 10.0, _bc(Color(1.6, 1.4, 1.0, 0.35)), 2.0)
				g.draw_line(b.pos - n * 14.0, b.pos + n * 4.0, _bc(Color(2.2, 2.0, 1.6)), 3.0)
			"fire":
				var fl := 1.0 + 0.2 * sin(g.t * 40.0 + b.pos.x)
				g.draw_circle(b.pos, 13.0 * fl * vk, _bc(Color(2.0, 0.8, 0.2, 0.25)))
				g.draw_circle(b.pos, 8.0 * fl * vk, _bc(Color(2.4, 1.1, 0.3, 0.8)))
				g.draw_circle(b.pos, 4.0 * vk, _bc(Color(2.8, 2.4, 1.4)))
			"arcane":
				g.draw_line(b.pos - n * 18.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.4)), 4.0)
				g.draw_circle(b.pos, 8.0 * vk, _bc(Color(1.2, 0.5, 2.0, 0.35)))
				UI.diamond(g, b.pos, 5.0 * vk, _bc(Color(1.8, 1.0, 2.6)), _bc(Color(2.2, 1.6, 2.8)))
			_:
				g.vfx.spr("orb", 1, 0, b.pos, Game.PX * vk, false, _bc(Color.WHITE))


var _bk := 1.0
var _bd := 0.0
var _bmate := false
var _blead := false


## 队友特效颜色：往同亮度灰拉 mate_desat（不改透明度，透明度由调用方乘 mate_dim）
## 队长特效颜色：往琥珀偏 lead_tint（保持亮度）再 × lead_boost（同 batch_canvas._dim）
func lead_col(c: Color) -> Color:
	if lead_tint > 0.0:
		var m: float = maxf(c.r, maxf(c.g, c.b))
		c = Color(lerpf(c.r, m, lead_tint), lerpf(c.g, 0.78 * m, lead_tint), lerpf(c.b, 0.42 * m, lead_tint), c.a)
	return Color(c.r * lead_boost, c.g * lead_boost, c.b * lead_boost, c.a)


func mate_col(c: Color) -> Color:
	if mate_desat <= 0.0:
		return c
	var l: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return Color(lerpf(c.r, l, mate_desat), lerpf(c.g, l, mate_desat), lerpf(c.b, l, mate_desat), c.a)


func _bc(c: Color) -> Color:
	if _blead:
		c = lead_col(c)
	var k: float = _bk * (mate_dim if _bmate else 1.0)
	var dd: float = maxf(_bd, mate_desat if _bmate else 0.0)
	if k >= 1.0 and dd <= 0.0:
		return c
	var l: float = (c.r + c.g + c.b) / 3.0
	return Color(lerpf(c.r, l, dd), lerpf(c.g, l, dd), lerpf(c.b, l, dd), c.a * k)


## g.fx 特效按 kind 逐个画（频闪 / 爆炸 / 地裂 / 光束 / Boss 换幕……）；fx_dim 只压友方特效；写进 tb 批的（gcrack / mote / mire_recoil）末尾一次提交
## Boss 结算特效颗粒化（docs/142b §9 特效精修，用户 10-25）：这些矢量平涂的结算形（环 / 爆炸 / 水柱 / 震地 / 刀光 / 放射 / 弹道）
## 画成半透明的底、颗粒做主体；冰面等持续区域不在表里（是读法，不压暗）。render/boss_fx_grains 0 = 旧画法
const BFX_KINDS := {"ring": true, "explode": true, "wpillar": true, "quake": true, "bslash": true, "rays": true, "tracer": true}
const BFX_DIM := 0.45
const BFX_CAP := {"ring": 48, "explode": 56, "wpillar": 48, "quake": 36, "bslash": 30, "rays": 20, "tracer": 22}   # 单个特效颗粒上限（再受 BossBeam 预算）


## 单个特效的颗粒配额：push 到配额用完就不再发（各分支照常写循环，超出的直接丢）
class _BfxCap:
	var gr
	var left: int
	func _init(grains, n: int) -> void:
		gr = grains
		left = n
	func push(name: String, p: Vector2, dir: Vector2, c: Color, delay := 0.0) -> void:
		if left <= 0:
			return
		left -= 1
		gr.push(name, p, dir, c, delay)
var bulfx   # render/bullet_fx.gd： 子弹出现 / 消失画面（用户 10-27；Boss 覆盖钩子 bulfx.set_hook / set_spawn_hook）
var bfx_grains = null   # 本帧可用的颗粒层（光学观感颗粒开着且 boss_fx_grains 开时），_draw_fx 开头取


func _bfx_grains(f: Dictionary) -> void:
	var c: Color = f.bfx
	var gr = _BfxCap.new(bfx_grains, BossBeam.take(g, BFX_CAP.get(str(f.kind), 32)))
	var p: Vector2 = f.get("pos", Vector2.ZERO)
	match str(f.kind):
		"ring":
			var r: float = float(f.get("r", 40.0))
			var n: int = clampi(int(r * 0.35), 16, 48)
			for i in n:
				var d := Vector2.from_angle(TAU * i / n + g.vrng.randf_range(-0.08, 0.08))
				gr.push("bfx_burst", p + Vector2(d.x, d.y * 0.72) * r, d, c)
		"explode":
			var r2: float = float(f.get("r", 40.0))
			for i in 44:
				var d2 := Vector2.from_angle(g.vrng.randf() * TAU)
				gr.push("bfx_burst", p + d2 * r2 * g.vrng.randf_range(0.0, 0.35), d2, c)
			for i in 12:
				gr.push("bfx_dust", p + Vector2(g.vrng.randf_range(-0.5, 0.5) * r2, 0), Vector2.UP, c)
		"wpillar":
			# 水柱：一柱颗粒自下而上（不再是两个矩形）
			var r3: float = float(f.get("r", 40.0))
			for i in 34:
				var y: float = -g.vrng.randf() * r3 * 2.2
				gr.push("bfx_dust", p + Vector2(g.vrng.randf_range(-0.35, 0.35) * r3, y), Vector2.UP, c, g.vrng.randf() * 0.12)
			for i in 14:
				var d3 := Vector2.from_angle(PI + g.vrng.randf() * PI)
				gr.push("bfx_burst", p + Vector2(d3.x * r3 * 0.5, 0), d3, c)
		"quake":
			var r4: float = float(f.get("r", 60.0))
			var dc := Color(c.r * 0.55 + 0.25, c.g * 0.55 + 0.22, c.b * 0.55 + 0.2)   # 尘土：专属色掺土灰
			for i in 36:
				var d4 := Vector2.from_angle(g.vrng.randf() * TAU)
				gr.push("bfx_dust", p + Vector2(d4.x, d4.y * 0.6) * r4 * g.vrng.randf_range(0.2, 1.0), d4, dc)
		"bslash":
			# 刀光：沿弧撒刀光颗粒（切向 + 略向外），顺着挥刀方向依次出（emit_delay）
			var r5: float = float(f.get("r", 80.0))
			var a0: float = float(f.ang) - float(f.half)
			for i in 30:
				var u: float = float(i) / 29.0
				var aa: float = a0 + float(f.half) * 2.0 * u
				var d5 := Vector2.from_angle(aa)
				gr.push("slash", p + d5 * r5 * g.vrng.randf_range(0.55, 0.92), (d5.orthogonal() + d5 * 0.6).normalized(), c, u * 0.12)
		"rays":
			for i in 20:
				var d6 := Vector2.from_angle(TAU * i / 20.0)
				gr.push("bfx_burst", p + d6 * 20.0, d6, c)
		"tracer":
			var pa: Vector2 = f.a
			var pb: Vector2 = f.b
			var nrm: Vector2 = (pb - pa).orthogonal().normalized()
			for i in 22:
				var u2: float = g.vrng.randf()
				gr.push("bfx_flash", pa.lerp(pb, u2), nrm * (1.0 if g.vrng.randf() < 0.5 else -1.0), c, u2 * 0.04)   # 激光类收尾 ≤ 0.25 秒（用户 10-26）


func _draw_fx() -> void:
	if not _dbg_foe and not _dbg_foefx:
		FinalAttackDraw.draw(g, true)
	bfx_grains = BossBeam.grains(g)
	# 友方火花绘制预算（render/declutter spark_budget；缺省不限）：超出时跳过最早的（快淡完的），只影响绘制
	var skip_sparks := 0
	if spark_left < (1 << 29):
		var ns := 0
		for f in g.fx:
			if f.kind == "spark" and not f.get("enemy", false):
				ns += 1
		skip_sparks = maxi(0, ns - spark_left)
	for f in g.fx:
		if f.life <= 0.0 or f.get("ground", false):
			continue   # ground：地面层敌方特效（奠基者地裂）已在 _draw_ground_foe_fx 画过；到期还没被 _cleanup 回收的特效不画：最终 Boss 击破的慢动作（victory_flow）走 g.vfx.update 但不跑 game._update/_cleanup，
			# 到期特效会一直留在 g.fx 里；"sprite" 类按已播时间取帧，life ≤ 0 后会被夹在末帧一直画（骑士死亡原地留下冰晶/冰砖残留）
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var foe: bool = f.get("enemy", false) or FOE_KINDS.has(f.kind)
		if ((_dbg_foe or _dbg_foefx) and foe) or (_dbg_friend and not foe and not AMB_KINDS.has(f.kind)) or (_dbg_amb and AMB_KINDS.has(f.kind)):
			continue   # --clutterdbg 量测：这一层不画
		if bfx_grains != null and f.has("bfx") and BFX_KINDS.has(f.kind):
			# Boss 结算特效（telegraph.warn_resolve 打的 bfx = 专属色）：第一帧迸出颗粒，矢量形压成半透明的底（起手 = 预警、爆发 = 颗粒、消散 = 颗粒飘散）
			if not f.has("bg"):
				f["bg"] = true
				_bfx_grains(f)
			a *= BFX_DIM
		var fdim: float = 1.0 if f.get("enemy", false) else fx_dim   # 敌方特效不降噪（docs/48 ③）
		if fdim < 1.0 and DIM_KINDS.has(f.kind):
			a *= fdim
		if skip_sparks > 0 and f.kind == "spark" and not f.get("enemy", false):
			skip_sparks -= 1
			continue
		if f.kind == "kp_beam":
			BossBeam.draw(g, f)   # Boss 激光（Kanpelle 帧条，docs/142b §8.5）；缺图不画（结算伤害不受影响）
			continue
		if f.kind == "beam" or f.kind == "bbeam" or f.kind == "tracer":
			LaserDraw.draw(g, f, a)   # 激光 A 像素光束（docs/138 §12；旧开关 fx/laser_style 与原画法已删）
			continue
		match f.kind:
			"leave_jump":   # 队友离队 / 换人：原地一蹲后向上跳出屏幕（squad._leave_fx，10-22）
				var jt: float = (f.max - f.life) / f.max
				var jy: float = 2.0 * g.PX if jt < 0.12 else -pow((jt - 0.12) / 0.88, 1.6) * (view_rect(0.0).size.y + 80.0 * g.PX)
				draw_sprite_at(f.pos + Vector2(0, jy), f.st.flip, Color.WHITE, f.st.frame, f.st.tex, f.st.hf, f.foot_off)
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
				# 骑士冲锋脚下的冰霜拖尾（10-27 打磨）：不再画一串圆斑，改为 2 像素格的霜点 + 一道短冰裂，按格冷却变暗（白 → 青 → 暗蓝）
				var fp: Vector2 = ((f.pos as Vector2) * 0.5).floor() * 2.0
				var fk: int = int(absf(fp.x) * 0.5 + absf(fp.y) * 1.5)
				var fcol := Color(0.85, 0.97, 1.0) if a > 0.75 else (Color(0.5, 0.78, 0.92) if a > 0.4 else Color(0.2, 0.34, 0.5))
				for q in 7:
					var h: int = (fk * 73 + q * 977) & 1023
					var off := Vector2(float(h % 15) - 7.0, float((h >> 4) % 7) - 3.0) * 2.0
					g.draw_rect(Rect2(fp + (off * 0.5).floor() * 2.0, Vector2(2, 2)), Color(fcol.r, fcol.g, fcol.b, 0.75 * a))
				g.draw_line(fp + Vector2(-8, 2), fp + Vector2(0, -2), Color(0.45, 0.68, 0.82, 0.5 * a), 2.0)
				g.draw_line(fp + Vector2(0, -2), fp + Vector2(6, 0), Color(0.45, 0.68, 0.82, 0.5 * a), 2.0)
			"lead_mark":
				# 队长命中记号（vfx.lead_mark，docs/139 §11）：敌人身上四个像素角标（暖白），跟着敌人走；前 70% 寿命满亮不闪，之后两阶熄灭
				var me = f.get("e")
				var mp: Vector2 = f.pos
				if me is Dictionary and not me.get("dead", false):
					mp = (me.pos as Vector2) + Vector2(0, -float(me.get("r", 12.0)) * 0.6)
				var mq: float = 1.0 if a > 0.3 else (0.66 if a > 0.15 else 0.33)
				var mr: float = clampf(float(f.get("r", 12.0)) * 0.8 + 4.0, 12.0, 24.0) * (1.25 if lead_lv >= 2 else 1.0)
				var arm: float = 6.0 if lead_lv < 1 else (9.0 if lead_lv == 1 else 11.0)
				mp = (mp / 2.0).round() * 2.0
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						var cn: Vector2 = mp + Vector2(sx * mr, sy * mr)
						g.draw_line(cn, cn - Vector2(sx * (arm + 1.0), 0), Color(0.05, 0.04, 0.03, 0.8 * mq), 4.0)
						g.draw_line(cn, cn - Vector2(0, sy * (arm + 1.0)), Color(0.05, 0.04, 0.03, 0.8 * mq), 4.0)
						g.draw_line(cn, cn - Vector2(sx * arm, 0), Color(1.0, 0.82, 0.5, mq), 2.0)   # 琥珀白（不过 1，免得被截成纯白）
						g.draw_line(cn, cn - Vector2(0, sy * arm), Color(1.0, 0.82, 0.5, mq), 2.0)
			"hstar":
				# 命中星（vfx._tier_fx）：中档 4 臂、重档 8 臂；臂长随寿命先长后缩，2 px 线 + 白芯，三阶跳着消失
				var hq: float = ceilf(a * 3.0) / 3.0 * float(f.get("ka", 1.0))   # ka：队友命中压透明度（docs/139 §10）
				var hl: float = float(f.r) * (0.6 + 0.4 * sin((1.0 - a) * PI))
				var hc: Color = f.col
				for q in int(f.n):
					var dv := Vector2.from_angle(TAU * q / float(f.n)) * (hl if q % 2 == 0 else hl * 0.6)
					g.draw_line(f.pos, f.pos + dv, Color(hc.r * 1.4, hc.g * 1.4, hc.b * 1.4, hq), 2.0)
				g.draw_rect(Rect2(f.pos - Vector2(2, 2), Vector2(4, 4)), Color(1.8, 1.8, 1.8, hq))
			"marc":
				# 近战刀光（vfx.melee_arc，10-24 用户嫌「沿判定圈的细弧像雷达」改样）：贴着武器的月牙——中间厚两头尖，
				# 半径 = 判定半径 × fx/melee_arc_reach（0.7，贴近身体），扫过角度最多 fx/melee_arc_span（105°）；
				# 判定扇形更宽 / 360° 时只画命中一侧（hit_react 把中心转到第一个被打中的敌人方向）。
				# 三阶硬边：外沿暗带 → 干员本色 → 靠外缘的亮芯（重档加白芯）；厚度按命中档（轻 / 中 / 重）。
				# 跟着挥刀走：前端在前 55% 寿命里扫到终点，尾端从 35% 起追上；位置按干员当前脚底 + 出手时偏移
				var tr: int = int(f.tier)
				var aq: float = ceilf(a * 3.0) / 3.0
				var tk: float = [0.0, 0.8, 1.0, 1.25][tr]   # 厚度按命中档
				var kb: float = [0.0, 1.0, 1.25, 1.6][tr]
				var full: bool = float(f.half) >= PI - 0.01
				var ap: Vector2 = f.pos
				var aop = g.squad.get_op(str(f.get("op", ""))) if g.squad != null else null
				if aop != null and aop.pos != Vector2.INF:
					ap = aop.pos + f.get("off", Vector2.ZERO)
				var rc: float = maxf(18.0, float(f.r) * Bal.v("fx/melee_arc_reach", 0.7))
				var span: float = minf(float(f.half) * 2.0, deg_to_rad(Bal.v("fx/melee_arc_span", 105.0)))
				var sd: float = float(f.get("sdir", 1.0))
				var s0: float = float(f.ang) - span * 0.5 * sd   # 挥刀起点（以刀光中心方向对称）
				# 10-24 用户「还不够像刀光」：厚月牙（厚度 ≈ 半径 30%）、前粗后尖（彗星形）、外沿白刃 → 本色 → 内沿暗边；
				# 前 25% 寿命里一下扫满（拖影帧），之后尾端从起点吃回去；外侧 2–3 道速度线，刀尖迸几颗火星
				var tw: float = clampf(rc * 0.3, 7.0, 26.0) * tk
				var pr: float = 1.0 - a
				var hd: float = clampf(pr / 0.25, 0.0, 1.0)
				var tl: float = clampf((pr - 0.25) / 0.75, 0.0, 1.0)
				var cc: Color = f.col
				if aop != null and aop.is_leader and (lead_boost != 1.0 or lead_tint > 0.0):
					cc = lead_col(cc)   # 队长刀光：提亮 / 暖色（docs/139 §11）
				if mate_on and aop != null and not aop.is_leader:
					cc = mate_col(cc)   # 队友刀光：去饱和、压透明度（颗粒走 cc.a，docs/139 §10）
					cc.a = mate_dim
					aq *= mate_dim
				var gr = g.optical.grains if g.optical != null else null
				if gr != null and gr.on() and not gr.off and hd > 0.0:
					# 刀光第四版（docs/136「slash」粒子模板）：月牙本体由像素颗粒在这一帧扫过的那一段上生成，前沿只留一道热白细线
					_marc_grains(f, gr, ap, rc, tw, s0, sd * span, hd, cc, kb, aq)
				elif hd - tl > 0.02:
					var sw: float = sd * span
					_crescent(ap, rc + 1.0, s0, sw, tl, hd, tw + 2.0, Color(cc.r * 0.35, cc.g * 0.35, cc.b * 0.4, 0.75 * aq), 1.0)   # 暗边（内沿收边）
					_crescent(ap, rc, s0, sw, tl, hd, tw, Color(cc.r * kb, cc.g * kb, cc.b * kb, aq), 1.0)   # 本色刀身
					_crescent(ap, rc, s0, sw, tl, hd, tw * 0.5, Color(minf(1.6, cc.r * kb * 1.4 + 0.4), minf(1.6, cc.g * kb * 1.4 + 0.4), minf(1.6, cc.b * kb * 1.4 + 0.4), aq), 1.0)   # 亮带
					_crescent(ap, rc, s0, sw, tl, hd, maxf(2.0, tw * 0.18), Color(1.9, 1.9, 1.9, aq), 1.0)   # 白刃（外沿）
					for q in (2 if tr < 3 else 3):   # 速度线：外沿外侧几道短细线，越往外越短
						var lr: float = rc + 4.0 + 4.0 * q
						var lu0: float = maxf(tl, hd - 0.45 + 0.12 * q)
						if hd - lu0 > 0.05:
							g.draw_arc(ap, lr, minf(s0 + sw * lu0, s0 + sw * hd), maxf(s0 + sw * lu0, s0 + sw * hd), 8, Color(cc.r * kb + 0.3, cc.g * kb + 0.3, cc.b * kb + 0.3, 0.55 * aq), 2.0)
					if hd < 1.0 or pr < 0.4:
						var tip: Vector2 = ap + Vector2.from_angle(s0 + sw * hd) * (rc - tw * 0.3)
						for q in 3:   # 刀尖火星（2 px，确定性摆位，不用随机数）
							var sv := Vector2.from_angle(s0 + sw * hd + sd * (0.6 + 0.5 * q)) * (4.0 + 5.0 * q)
							g.draw_rect(Rect2((tip + sv).round(), Vector2(2, 2)), Color(1.8, 1.8, 1.8, aq))
				var a0: float = 0.0 if full else float(f.ang) - float(f.half)
				var a1: float = TAU if full else float(f.ang) + float(f.half)
				if g.vfx.arc_dbg < 0:
					g.vfx.arc_dbg = 1 if Cfg.dev_args().has("--arcdbg") else 0
				if g.vfx.arc_dbg == 1:
					g.draw_arc(f.pos, f.r, 0.0, TAU, 64, Color(1, 1, 1, 0.5), 1.0)   # 判定圈（核对，画在出手那一刻的判定原点）
					if not full:
						g.draw_line(f.pos, f.pos + Vector2.from_angle(a0) * float(f.r), Color(1, 1, 0.3, 0.7), 1.0)
						g.draw_line(f.pos, f.pos + Vector2.from_angle(a1) * float(f.r), Color(1, 1, 0.3, 0.7), 1.0)
			"ring":
				# op_hit：干员攻击 / 技能命中的装饰环（水月），render/hit_rings 缺省不画；其余（敌方、拾取、藏品……）照画
				if f.get("op_hit", false) and not Dc.hit_rings():
					continue
				if f.get("enemy", false) and Bal.v("render/foe_ring_fx", 1.0) <= 0.0:
					continue   # docs/139 §8：敌方结算后的装饰环（伤害已结算，不是预警）不画
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
				# 灯标点燃时被清掉的溟痕退散（docs/54）：每片一圈紫环向中心收缩、深色底渐隐，再一道从灯标推出去的淡光弧。
				# 10-26：每片带延迟 c[2]（自灯标向外扫开），各自在 pd 秒里播完；sweep_r > 0 时再画一道从中心扫到圈边的驱散环
				var el: float = f.max - f.life
				var pd: float = float(f.get("pd", f.max))
				if float(f.get("sweep_r", 0.0)) > 0.0:
					var sk: float = clampf(el / maxf(0.01, float(f.sweep_t)), 0.0, 1.0)
					if sk < 1.0 or el < float(f.sweep_t) + 0.12:
						var sa: float = 1.0 - clampf((el - float(f.sweep_t)) / 0.12, 0.0, 1.0)
						var srr: float = float(f.sweep_r) * (1.0 - pow(1.0 - sk, 3.0))
						g.draw_set_transform(f.from, 0.0, Vector2(1.0, ground_y()))   # 与清除圈同一个地面椭圆
						g.draw_arc(Vector2.ZERO, srr, 0.0, TAU, 64, Color(1.7, 1.25, 2.1, 0.75 * sa), 5.0)
						g.draw_arc(Vector2.ZERO, srr * 0.94, 0.0, TAU, 64, Color(2.0, 1.9, 1.6, 0.5 * sa), 2.0)
						g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if g.vfx.p2 and f.get("tex", false):
					# 溟痕退散帧条 fx_mire_dissolve（64×64 × 6 原生 1x，world_spec_1024）：按 PX 1:1，不按半径拉伸；
					# 一块 64 美术像素 = 128 世界单位，大溟痕在圆内按 96 世界单位间距多点铺（块与块叠一圈、格心离圆心 ≤ 半径）；_emit 层进光学发光层
					var dtx: Texture2D = g.tex.get("fx_mire_dissolve")
					var dhs: float = A.hires_of(dtx) if dtx != null else 1.0
					var detx: Texture2D = _mire_dissolve_emit() if g.optical_on else null
					var step: float = 64.0 * Game.PX
					var pitch: float = 48.0 * Game.PX
					var me: float = Bal.v("render/optical_mire_emit", 0.35)   # 每格都用，循环外读一次（docs/50 §26）
					for c in f.pts:
						var lp: float = (el - (float(c[2]) if c.size() > 2 else 0.0)) / maxf(0.01, pd)
						if lp <= 0.0 or lp >= 1.0:
							continue
						var mfr: int = clampi(int(lp * 6.0), 0, 5)
						var dcol := Color(1.0, 1.0, 1.0, minf(1.0, (1.0 - lp) * 2.0))
						var nn: int = maxi(0, ceili((float(c[1]) - step * 0.5) / pitch))
						for iy in range(-nn, nn + 1):
							for ix in range(-nn, nn + 1):
								var off := Vector2(ix, iy) * pitch
								if off.length() > float(c[1]) and (ix != 0 or iy != 0):
									continue
								var dp: Vector2 = ((c[0] + off) / Game.PX).round() * Game.PX
								g.vfx.spr_rot("fx_mire_dissolve", mfr, dp, 0.0, Game.PX / dhs, dcol)
								if detx != null:
									g.glow_tex_next.append([detx, Rect2(dp - Vector2(step, step) * 0.5, Vector2(step, step)), Rect2(mfr * 64, 0, 64, 64), Color(1, 1, 1, dcol.a * me)])
				elif g.vfx.p2:
					var gy: float = ground_y()
					for c in f.pts:
						var lp2: float = (el - (float(c[2]) if c.size() > 2 else 0.0)) / maxf(0.01, pd)
						if lp2 <= 0.0 or lp2 >= 1.0:
							continue
						var k := lp2
						a = 1.0 - lp2
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
				var el: float = f.max - f.life - float(f.get("delay", 0.0))   # delay：延后开播（vfx.fx_sprite）
				if el < 0.0:
					continue
				var fr := mini(int(el * float(f.get("fps", spec[1]))), spec[0] - 1)   # fps：加快过的死亡帧条（vfx.death_shatter）
				var scol: Color = f.get("col", Color.WHITE)
				scol.a *= fdim
				if lead_lv > 0 and f.get("lead", false):
					scol = lead_col(scol)   # 队长放的帧条特效：提亮 / 暖色（docs/139 §11）
				if g.optical != null and g.optical.grains != null and g.optical.grains.body_frame(f, fr, int(spec[0])):
					continue   # 形状颗粒化（fx_grains.GRAIN_BODY，docs/138 §13）：这一帧由颗粒拼出形状
				g.vfx.spr_rot(f.name, fr, f.pos, f.ang, g.vfx.int_scale(f.scale), scol, f.get("anchor", Vector2(-1, -1)), f.get("flip", false))
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
				var dbc: Color = f.get("bcol", Color(1.0, 0.95, 1.0))   # 专属色系（亮 → 本色 → 暗），核心不再白闪
				if el < 0.3:
					var ck: float = el / 0.3
					g.draw_circle(f.pos, f.r * (1.0 + 1.5 * ck), Color(dbc.r * 1.4, dbc.g * 1.4, dbc.b * 1.4, (1.0 - ck) * 0.55))
				var cols := [Color(dbc.r * 0.5 + 0.7, dbc.g * 0.5 + 0.7, dbc.b * 0.5 + 0.7), Color(dbc.r * 1.2, dbc.g * 1.2, dbc.b * 1.2), Color(dbc.r * 0.6, dbc.g * 0.6, dbc.b * 0.6)]
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
## Boss 弹画灰度弹体再乘专属色（_eb_gray 从原图做：optical._eb_step 把杂兵弹换成青蓝色相时，原图留在 g.tex[名 + "@boss"]；
## docs/139 §7.3、docs/142b §8.4；旧开关 render/ebullet_boss_own 10-29 已删）
func _eb_tex(b: Dictionary, nm: String) -> String:
	return _eb_gray(nm) if b.get("boss", false) else nm


## 敌弹画在哪：脚下 16 像素上方；Boss 弹再加一点垂直于飞行方向的轻摆（±2，按所在位置错相——同一圈弹各摆各的，飞起来是一条条细波，不是整片平移）。只画面
func _ebp(b: Dictionary) -> Vector2:
	var p: Vector2 = b.pos + Vector2(0, -16)
	if b.get("boss", false) and bfx_grains != null:
		var v: Vector2 = b.vel
		if v.length_squared() > 1.0:
			p += v.orthogonal().normalized() * sin(g.t * 9.0 + (b.pos.x + b.pos.y) * 0.06) * 2.0
	return p


## Boss 弹体脉动（±14%，错相同上）；不是 Boss 弹或颗粒关着时 1
func _eb_pulse(b: Dictionary) -> float:
	if not (b.get("boss", false) and bfx_grains != null):
		return 1.0
	return 1.0 + 0.14 * sin(g.t * 13.0 + (b.pos.x - b.pos.y) * 0.05)


## Boss 弹体的调色：专属色 × 1.1（只略提亮：再高光学辉光一叠色相就偏，炮火橙会变黄；docs/142b §8.4，不加危险色外圈，
## 用户 10-25「描边不要加」）；不是 Boss 弹时用 base
func _eb_mod(b: Dictionary, base: Color) -> Color:
	if not b.get("boss", false):
		return base
	if b.has("bcol"):
		return b.bcol   # 弹自带弹芯色（伊莎玛拉按幕换色，docs/170 §15）
	var t: String = str(b.get("src_type", ""))
	var c: Color = b.own_col if b.has("own_col") else D.ENEMIES.get(t, {}).get("bcol_core", g.vfx.boss_color(t))   # 有弹芯色（伊比利亚）用弹芯色；own_col = 弹自带专属色（伊祖米克分幕，docs/170 §16）
	return Color(c.r * 1.1, c.g * 1.1, c.b * 1.1)


## Boss 弹的同色系外描边（enemies.json bcol_outline，目前只伊比利亚，用户 10-25「描边要同调、有层次」）：压在亮边外侧、2 世界像素（1 个低分辨率格）、不闪
func _eb_boss_outline(b: Dictionary, bp: Vector2, br := -1.0) -> void:
	if not b.get("boss", false):
		return
	var oc = D.ENEMIES.get(str(b.get("src_type", "")), {}).get("bcol_outline")
	if oc is Color:
		tb_ring(bp, (b.r if br < 0.0 else br) + 3.5, 2.0, Color(oc.r, oc.g, oc.b, 1.0))


## 弹体贴图的灰度版 g.tex[名 + "@gray"]（第一次用时从原色版做：按最亮通道提到 0.35–1.0 的灰、保留透明度），画时乘专属色。纯画面
func _eb_gray(nm: String) -> String:
	var key: String = nm + "@gray"
	if g.tex.has(key):
		return key
	var src: Texture2D = g.tex.get(nm + "@boss", g.tex.get(nm))
	if src == null:
		return nm
	var im: Image = src.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	for y in im.get_height():
		for x in im.get_width():
			var c: Color = im.get_pixel(x, y)
			if c.a > 0.0:
				var v: float = clampf(0.35 + maxf(c.r, maxf(c.g, c.b)) * 0.75, 0.0, 1.0)
				im.set_pixel(x, y, Color(v, v, v, c.a))
	g.tex[key] = ImageTexture.create_from_image(im)
	return key


func _draw_ebullets_lobs_shocks() -> void:
	# 敌方弹幕分三遍画（性能 9/30：原来每颗子弹影子 / 底圈 / 光晕 / 贴图 / 描边交替，有贴图和无贴图来回切，每颗约 5 次绘制调用；
	# 分遍后同类连续提交能合批）：① 无贴图：影子椭圆、深色底圈、光晕；② 贴图：弹体；③ 无贴图：弹芯、亮描边
	var blades: Array = []
	var mcs: Array = []   # 中期 Boss 分级弹（docs/170，render/mid_card_draw 单独画）
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("own_draw", false):
			continue   # 命中 / 到期、还没被回收的敌弹不画（同我方子弹；正式局 _cleanup 每帧回收，图鉴演示由 enemy_demo 回收）；own_draw = 弹体由 Boss 自己画（偏执泡影二阶段，docs/170）
		if b.get("kind", "") == "boss_blade":
			blades.append(b)
			continue
		if b.get("mc", false):
			mcs.append(b)
			continue
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置（椭圆直接算顶点，不切画布变换）
		var vk: float = bulfx.k(b)   # 出现动画缩放（只画面，判定半径 b.r 不变）
		tb_circle(b.pos + Vector2(0, 2), (b.r + 1.0) * vk, Color(0, 0, 0, 0.4), 0.45, 10)
		if _bullet_tex(b) != "":
			continue   # 专属弹体帧条（docs/96：漂移体侵蚀弹）自带 #080E18 描边，不垫底圈、不描洋红边
		var bp: Vector2 = _ebp(b)
		# 敌方弹幕高对比：深色外圈垫底，画完再描一圈亮洋红边，压在友方特效上也一眼看得出
		tb_circle(bp, (b.r + 3.0) * vk, Color(0.02, 0.0, 0.05, 0.85))
		if g.optical_on:
			var ec: Color = g.optical.eb_col(b)   # 光学观感颜色语言：杂兵弹敌弹色、Boss 弹危险色（docs/139 §6.7 / §7.3）
			tb_circle(bp, (b.r + 4.0) * vk, Color(ec.r, ec.g, ec.b, 0.3))
			continue
		match b.get("kind", "orb"):
			"acid":
				tb_circle(bp, (b.r + 5.0) * vk, Color(0.5, 1.4, 0.3, 0.3))
			"nova":
				tb_circle(bp, (b.r + 5.0) * vk, Color(1.2, 0.4, 1.8, 0.3))
			"nerve":
				tb_circle(bp, (b.r + 5.0) * vk, Color(1.0, 0.9, 0.3, 0.25))
			_:
				tb_circle(bp, (b.r + 4.0) * vk, Color(1.0, 0.3, 0.6, 0.25))
	tb_flush()
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("mc", false) or b.get("own_draw", false):
			continue
		var kd: String = b.get("kind", "orb")
		var bp: Vector2 = _ebp(b)
		var btex: String = _bullet_tex(b)
		var vk: float = bulfx.k(b)
		if btex != "":
			# 小怪专属弹体（enemies.json shot_tex，docs/96 第 1 批：漂移体 proj_skimmer_corrode）：朝右绘制、按速度方向旋转，帧率按 V6_FRAMES
			var bspec: Array = Game.V6_FRAMES[btex]
			g.vfx.spr_rot(btex, int(g.t * float(bspec[1]) + b.pos.x * 0.01) % int(bspec[0]), bp, b.vel.angle(), Game.PX * vk)
		elif kd == "nerve" and g.tex.get("proj_floater_nerve") != null:
			# 浮海飘航者神经弹（V8 proj_floater_nerve，朝右绘制按速度方向旋转）
			g.vfx.spr_rot(_eb_tex(b, "proj_floater_nerve"), int(g.t * 12.0 + b.pos.x * 0.01) % 4, bp, b.vel.angle(), Game.PX * vk, _eb_mod(b, Color.WHITE))
		elif kd == "acid" and g.tex.get("proj_acid") != null:
			g.vfx.spr("proj_acid", 2, int(g.t * 8.0 + b.pos.x * 0.01) % 2, bp, _hpx("proj_acid") * vk, false, Color(1.5, 1.5, 1.5))   # Codex v14 酸团（暗橄榄，避开友方黄绿）；×1.5 提亮，压过地图暗环境光（原程序圆也是过曝色）
		elif kd == "nova" and g.tex.get("proj_nova") != null:
			g.vfx.spr(_eb_tex(b, "proj_nova"), 4, int(g.t * 10.0 + b.pos.x * 0.01) % 4, bp, _hpx("proj_nova") * _eb_pulse(b) * vk, false, _eb_mod(b, Color(1.5, 1.5, 1.5)))   # Codex v14 新星弹；×1.5 提亮同上；Boss 弹 = 专属色
		elif kd != "acid" and kd != "nova" and kd != "nerve" and kd != "boss_blade":
			g.vfx.spr(_eb_tex(b, "ebullet"), 1, 0, bp, Game.PX * b.r / 5.0 * _eb_pulse(b) * vk, false, _eb_mod(b, Color.WHITE))
	var eb_ow: float = Bal.v("render/ebullet_outline", 0.0) if g.optical_on else 0.0
	for b in g.ebullets:
		var kd: String = b.get("kind", "orb")
		if kd == "boss_blade" or kd == "mc" or b.life <= 0.0 or b.get("own_draw", false):
			continue
		var bp: Vector2 = _ebp(b)
		var vk: float = bulfx.k(b)
		var br: float = b.r * vk   # 出现动画缩放后的画面半径（判定仍是 b.r）
		if _bullet_tex(b) != "":
			if eb_ow > 0.0:   # 专属弹体（漂移体侵蚀弹）也加同一圈外描边
				var dc0: Color = g.optical.col_danger
				tb_ring(bp, br + 3.0 + eb_ow * 0.5, eb_ow, Color(dc0.r, dc0.g, dc0.b, 1.0))
			continue
		match kd:
			"acid":
				if g.tex.get("proj_acid") == null:
					tb_circle(bp, br, Color(0.6, 1.8, 0.4))
					tb_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6), 1.0, 6)
			"nova":
				if g.tex.get("proj_nova") == null:
					tb_circle(bp, br, b.get("col", Color(1.5, 0.6, 2.0)))
			"nerve":
				if g.tex.get("proj_floater_nerve") == null:
					tb_circle(bp, br, Color(1.8, 1.6, 0.5))
		if b.has("core_r"):
			tb_circle(bp, float(b.core_r) * vk, b.get("core_col", Color(1.8, 1.7, 1.5)))   # 弹体分级：大弹发光核心（圣徒符卡，docs/171）
		if g.optical_on:
			var ebc: Color = g.optical.eb_col(b)
			var bk: float = 1.3 if b.get("boss", false) else 2.0   # Boss 弹专属色亮描边只提到 ×1.3（×2 叠辉光后色相偏）
			tb_ring(bp, br + 2.0, 1.5, Color(ebc.r * bk, ebc.g * bk, ebc.b * bk, 0.9))   # 亮描边改敌弹色（原亮洋红）；Boss 弹 = 专属色
			var ow: float = eb_ow
			if ow > 0.0:
				# docs/139 §7 敌弹外描边（用户 10-24「敌方子弹加一个描边看一下」）：危险色、不闪，宽 ow 世界像素（2 = 1 个低分辨率格），压在亮描边外侧
				var dc: Color = g.optical.col_danger
				tb_ring(bp, br + 3.0 + ow * 0.5, ow, Color(dc.r, dc.g, dc.b, 1.0))
			_eb_boss_outline(b, bp, br)
			if bfx_grains != null and b.get("boss", false) and g.vrng.randf() < 0.08 and BossBeam.take(g, 1) > 0:
				bfx_grains.push("mote_shed", bp, -b.vel.normalized(), ebc)   # 沿途散颗粒（拖尾之外的「活」，走预算）
		elif b.get("boss", false):
			var bc: Color = g.vfx.boss_color(str(b.get("src_type", "")))
			tb_ring(bp, br + 2.0, 1.5, Color(bc.r * 1.3, bc.g * 1.3, bc.b * 1.3, 0.9))   # Boss 弹亮描边 = 专属色（不加危险色外圈，用户 10-25「描边不要加」）
			_eb_boss_outline(b, bp, br)
		else:
			tb_ring(bp, br + 2.0, 1.5, Color(2.4, 0.8, 1.8, 0.9))
	tb_flush()
	for b in blades:
		g.vfx.boss_blade(b, b.pos + Vector2(0, -16))
	if not mcs.is_empty():
		MidCardDraw.bullets(self, g, mcs)
	# 抛射碎石 / 投嗣弹：落点预警 + 空中石块（投嗣育母投出的拟嗣：低弧，弹体 proj_mother_brood，缺图时 e_brood 基础帧缩小旋转）
	for l in g.lobs:
		var k: float = l.t / l.dur
		var brood: bool = l.get("kind", "") == "brood"
		# 抛石落点的地面椭圆预警 10-22b 用户取消（g.lobs 只有普通怪的抛射，Boss 抛射走 g.warns）：只画空中的石块 / 投嗣弹
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
	for sh in (g.shocks if not _dbg_shock else []):   # --clutterdbg=noshock 量测（docs/139 §8）
		if not sh.get("ground", false):
			_draw_shock(sh)


## 一道冲击环：地面椭圆，深色外描边 + 危险色主色 + 白芯；缺口环按缺口分段（ground 环由 _draw_ground_foe_fx 在单位之下画）
func _draw_shock(sh: Dictionary) -> void:
	if sh.get("boss", false) and Bal.v("render/ishar_song_live", 1.0) > 0.0 and not g.perf_alt:   # perf_alt：--perfab 同局轮换的旧段
		# Boss 冲击环：断续抖动的颗粒带 + 衰减尾带（伊莎玛拉另叠内波纹），专属色（docs/142b §9，用户 10-25）
		BossBeam.draw_song(g, sh, ground_y(), str(sh.get("src_type", "")) == "ishar")
		return
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
	if not _dbg_foe and not _dbg_tell:
		draw_enemy_tells()
	# docs/54 ④ 精英登场（按首次入画起算画 0.9 秒；无贴图批，一次提交）
	if g.vfx.p2:
		var elr: Rect2 = view_rect(120.0)
		for e in (_vis_ent if _vis_on else g.enemies):
			if e.elite and not e.boss and elr.has_point(e.pos) and g.vfx.elite_entrance_due(e):
				g.vfx.elite_entrance(e)
		tb_flush()
	draw_leader_ailments()
	if not _dbg_foe and not _dbg_warn:
		draw_warn_outlines()
	# 主控标记（职业色细环 / 冲刺冷却弧 / 朝向）画在所有敌方预警之上：几十条预警叠在身上时也看得见自己在哪（协调人 1.1.1，干员拆出 draw_leader_mark）
	g.squad.draw_leader_mark()   # 内含按住瞄准方向指示（draw_attack_dir，同一批）


## 主角帧动画（美术交付 player_*.png 后自动启用；帧为正方形，帧数 = 宽 / 高）
func update_player_anim(dt: float) -> void:
	if g.tex.get(str(g.doctor.def.get("sprites", {}).get("idle", ""))) != null:
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


## 博士动画：data/doctor.json 的 sprites（idle 4 / run 8 / hurt 2 / death 4 帧，10-24 起 doctor_*@1x 1 倍帧条，64 画布脚底 (32,60)）；
## 某个动作没有贴图时退回待机条：跑步 = 加快切帧 + 颠簸，倒下 = 侧倒
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
		tx = g.tex[sp.idle]
	var key := want + ("_fb" if fallback else "")
	if key != anim_name:
		anim_name = key
		anim_t = 0.0
		g.sprite.texture = tx
		g.sprite.scale = Vector2(g.PX, g.PX)
		g.sprite.hframes = max(1, tx.get_width() / tx.get_height())
		# 各动作从数据取脚底；缺图回退用待机条的脚底。
		var foot_y: float = float(sp.get(("idle" if fallback else want) + "_foot", sp.get("foot", [32, 60]))[1])
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
				g.sprite.frame = int(anim_t * 4.0) % n
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
		var mn: int = A.enemy_frames(base + "_move", 4)
		return {"name": base + "_move", "frames": mn, "frame": int(g.t * A.enemy_loop_fps(base + "_move", 5.0)) % mn}
	var inn: int = A.enemy_frames(base, 2)
	return {"name": base, "frames": inn, "frame": int(g.t * A.enemy_loop_fps(base, 2.0)) % inn}


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
			if e.get("gate_hold", false) and _lazy_tex(e.tex + "_skill") != null:
				# 过卡点阶段护盾（重画 *_skill，8 帧）：起势一次后停在后三帧循环
				var sn: int = A.enemy_frames(e.tex + "_skill", 8)
				return {"name": e.tex + "_skill", "frames": sn, "frame": sn - 3 + int(g.t * 4.0) % 3}
			var seg: int = (0 if pk > 0.5 else 1) if winding else (2 if e.pose > 0.17 else 3)
			if e.get("sword_t", 0.0) > 0.0 and posing:
				return {"name": e.tex + "_melee", "frames": 4, "frame": seg}
			if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
				return {"name": e.tex + "_reload", "frames": 4, "frame": int(g.t * 6.0) % 4}
			if posing:
				return {"name": e.tex + "_attack", "frames": 4, "frame": seg}
		"izumik":
			# 学习期（phase 1）扎根：进学习期先播 f0–f1 一次，之后 f2–f3 循环；地波蓄力按进度 f0 → f2，结算释放 f3
			if e.phase == 1 and e.has("learn_t") and _lazy_tex("e_izumik_root_begin") != null and _lazy_tex("e_izumik_root_loop") != null:
				# 重画扎根（10-23）：起势 root_begin 播一次 → 学习期 root_loop 循环；收势 root_end 由 vis_act 在进阐释阶段时播
				var el0: float = float(e.get("count_max", 20.0)) - float(e.learn_t)
				var bd: float = float(A.enemy_redraw("e_izumik_root_begin").get("duration", 1.0))
				if el0 < bd:
					var bn: int = A.enemy_frames("e_izumik_root_begin", 8)
					return {"name": "e_izumik_root_begin", "frames": bn, "frame": clampi(int(el0 / bd * bn), 0, bn - 1)}
				var ln: int = A.enemy_frames("e_izumik_root_loop", 6)
				return {"name": "e_izumik_root_loop", "frames": ln, "frame": int(g.t * A.enemy_loop_fps("e_izumik_root_loop", 6.0)) % ln}
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
			var ps := _boss_warn_strip(e, ["sweep"], "e_path_skill", 4)   # 分形塑路（sweep）用重画 skill 帧条（10-23），旧图没有时走 slam
			if ps.is_empty():
				ps = _boss_warn_strip(e, ["slam", "sweep"], "e_path_slam", 4)
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


## Added final attacks use the existing native Spine strips, with the authored release event aligned to damage.
func _final_boss_strip(e: Dictionary, skin: String) -> String:
	match str(e.type):
		"paranoia": return "e_paranoia_gaze" if e.phase == 1 else "e_paranoia_phase2_howl"
		"ishar": return "e_ishar_t_attack" if e.phase == 2 else "e_ishar_attack"
		"izumik": return "e_izumik_attack" if skin == "tentacle" else "e_izumik_share"
		"knight_boss":
			match skin:
				"ice", "ice_field", "ice_lance", "ice_wall": return "e_knight_plant"
				"ice_wave": return "e_knight_spin"
				"ice_thrust": return "e_knight_thrust"
				"crescent": return "e_knight_spin"
				"spear": return "e_knight_thrust"
				"step": return "e_knight_charge_form"
	return ""

func _final_boss_frame(e: Dictionary, skin: String, progress: float, since: float) -> Dictionary:
	var strip := _final_boss_strip(e, skin)
	if strip == "" or _lazy_tex(strip) == null:
		return {}
	var rd := A.enemy_redraw(strip)
	var times: Array = rd.get("sample_times", [])
	var n: int = int(rd.get("frames", 0))
	if times.is_empty() or n < 2:
		return {}
	var events: Array = rd.get("event_frames", [])
	var event: int = int(events[0]) if not events.is_empty() else int(rd.get("release_frame") if rd.get("release_frame") != null else n / 2)
	event = clampi(event, 1, n - 1)
	var event_time: float = float(times[event])
	var animation_time: float
	if since < 0.0:
		animation_time = minf(event_time - 0.001, maxf(0.0, progress) * event_time)
	else:
		# Preserve the source follow-through; a terminal contact pose holds briefly instead of disappearing at once.
		if since >= maxf(0.25, float(rd.duration) - event_time):
			return {}
		animation_time = event_time + since
	var frame := 0
	for i in n:
		if float(times[i]) <= animation_time:
			frame = i
	return {"name":strip, "frames":n, "frame":frame}

func final_boss_animation(e: Dictionary) -> Dictionary:
	if e.get("dead", false) or e.get("coma", false) or e.get("stun", 0.0) > 0.0 or e.get("break_t", 0.0) > 0.0:
		return {}
	var pending: Dictionary = {}
	var other_cast := false
	for w in g.warns:
		if w.done or not is_same(w.owner, e):
			continue
		if str(w.act) != "final_attack":
			other_cast = true
		elif pending.is_empty() or float(w.dur) - float(w.t) < float(pending.dur) - float(pending.t):
			pending = w
	var last = e.get("last_act")
	var since := INF
	if last is Dictionary and str(last.get("act", "")) == "final_attack":
		since = g.t - float(last.get("t", -99.0))
		# A subsequent warning must not hide the release pose of the projectile that just left the body.
		if since >= 0.0 and since < 0.12:
			return _final_boss_frame(e, str(last.get("skin", "")), 1.0, since)
	if not pending.is_empty():
		var delay: float = float(pending.get("tell_after",0.0))
		return _final_boss_frame(e, str(pending.get("skin", "")), maxf(0.0,float(pending.t)-delay) / maxf(0.01,float(pending.dur)-delay), -1.0)
	if not other_cast and since >= 0.0 and since < INF:
		return _final_boss_frame(e, str(last.get("skin", "")), 1.0, since)
	return {}


## 重画新增动作（10-23）的一次性画面：现形 reveal / 复苏 revive / 落地变身 change / 扎根收势 root_end，由触发点写 e.vis_act / e.vis_t0（纯画面字段）。
## 条名 = 基础帧条名 + "_" + 动作；时长取原作动画时长，播完清掉。没有这条帧条返回 {}
func _vis_anim(e: Dictionary) -> Dictionary:
	var act: String = e.get("vis_act", "")
	if act == "":
		return {}
	var base: String = e.tex
	if e.type == "paranoia" and e.phase == 2:
		base = "e_paranoia_phase2"
	elif e.type == "ishar" and e.phase == 2:
		base = "e_ishar_t"
	var strip: String = base + "_" + act
	var rd := A.enemy_redraw(strip)
	if rd.is_empty() or _lazy_tex(strip) == null:
		e.erase("vis_act")
		return {}
	var d: float = maxf(0.2, float(rd.get("duration", 1.0)))
	var k: float = (g.t - float(e.get("vis_t0", -99.0))) / d
	if k < 0.0 or k >= 1.0:
		e.erase("vis_act")
		return {}
	var n: int = int(rd.frames)
	return {"name": strip, "frames": n, "frame": clampi(int(k * n), 0, n - 1)}


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
	if e.has("stake_cast"):
		var cast: Dictionary=e.stake_cast
		var strip: String="e_knight_attack" if cast.throw else "e_knight_plant"
		var frame: int=3
		if cast.stage=="wind": frame=clampi(int(cast.warning.t/cast.warning.dur*(2 if cast.throw else 3)),0,1 if cast.throw else 2)
		elif cast.throw and g.t-float(cast.get("release_at",g.t))<.2: frame=2
		return {"name":strip,"frames":4,"frame":frame}
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
## 以及正在受击形变 / 蓄力 / 冲刺 / 鼓胀 / 唤醒 / 狂暴 / 阶段护盾 / 空中 / 剑光 / 装填跪地 / 出招姿态 / 攻击帧窗口 /（，docs/56 §10）里的敌人。
## 签名（e.dc[0..7]）：moving、stun > 0、coma、invuln、dormant、e.r、[6] 举肢准备（_dc_prep，10-26 docs/158 §7）、[7] 描边开关（_ol_sig）。
## 以后给敌人加会影响画面的新状态：要么加进 _dc_ok 的排除条件，要么加进签名；--dccheck（快检冒烟开着）会抓漏。
## enemies.json draw_full：带专用帧条挂点的几只 Boss（卡门 / 伊比利亚 / 伊祖米克 / 塑路者 / 伊莎玛拉 / 偏执泡影）

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
	if c == null or c[0] != moving or c[1] != (e.stun > 0.0) or c[2] != e.coma or c[3] != e.invuln or c[4] != e.dormant or c[5] != e.r or c[6] != _dc_prep(e) or c[7] != _ol_sig():
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
		st = e.boss or e.chest or e.tex == "e_knight" or D.ENEMIES.get(e.type, _NO_DEF).get("draw_full", false)
		e["dcs"] = st
	if st:
		return false
	if e.squash > 0.0 or e.wind > 0.0 or e.dash_w > 0.0 or e.dash_t > 0.0 or e.enraged or e.wake_t > 0.0:
		return false
	if e.nova_w > 0.0 or e.blast_w > 0.0 or e.burst_w > 0.0 or e.air > 0.0 or e.pose > 0.0:
		return false
	if e.get("part", false) or e.get("under", false) or e.get("gate_hold", false) or e.get("sword_t", 0.0) > 0.0 or e.get("break_t", 0.0) > 0.0:
		return false
	if e.has("vis_act"):
		return false   # 现形 / 复苏 / 落地变身一次性帧条在播（_vis_anim）：走原路径
	if float(e.get("hatch_until", 0.0)) > g.t:
		return false
	if e.tex_attack and (g.t < e.atk_until or float(e.get("shot_wind_until", 0.0)) > g.t):
		return false   # 举肢准备（attack_preparing）进缓存（签名 [6]，_dc_prep）：高阶四种在 300 像素内几乎一直处在准备态，原来六七成走原路径（docs/158 §7）
	if g.t - float(e.get("burst_fx_t", -9.0)) < BURST_FX_FRAMES / BURST_FX_FPS:
		return false   # 囊海爬行者破膜帧条在播（docs/96 §1.3）：本体前后各一层，走原路径
	return true



## 缓存内容：[0..7] 签名，[8] 贴图名，[9] 帧数，[10] 帧率，[11] 颜色，[12] 缩放（已除高清倍率），[13] 锚点，[14] 相对 e.pos 的偏移，
## [15] 画不画描边，[16] 白剪影名，[17]–[21] 图集区域 / 受击姿态，[22] 举肢准备选帧，[23] 准备帧要不要换算到帧条真实帧数。每一项都按 _draw_enemy_full 里的同一段代码算（只保留能缓存的敌人会走到的分支）
func _dc_compute(e: Dictionary, moving: bool) -> Array:
	var name: String = e.tex
	if e.coma and e.tex_feign:
		name = name + "_feign"
	var frames: int = A.enemy_frames(name, 2)
	var fps: float = A.enemy_loop_fps(name, 5.0)
	if moving and g.tex.get(name + "_move") != null:
		name += "_move"
		frames = A.enemy_frames(name, 4)
		fps = A.enemy_loop_fps(name, float(D.ENEMIES.get(e.type, {}).get("move_fps", 6.0)))
	var prep: bool = _dc_prep(e)
	if prep:
		name = e.tex + "_attack"   # 远处举肢准备：攻击帧条前两帧按 3 fps 来回（_draw_enemy_full 同段）；帧号在 _dc_emit 按 prepare_started 算
		frames = 4
	if e.dormant and g.tex.get(e.tex + "_dormant") != null:
		name = e.tex + "_dormant"
		frames = A.enemy_frames(name, 2)
		fps = A.enemy_loop_fps(name, 3.0)
		prep = false
	var remap: bool = false
	if prep:
		var nfr: int = A.enemy_frames(name, frames)
		remap = nfr != frames
		frames = nfr
	var wname: String = (e.tex + "_wound") if (g.tex.get(e.tex + "_wound") != null and (name == e.tex or name == e.tex + "_move" or prep)) else ""   # 受击姿态（重画 *_wound，1 帧）：_dc_emit 在 flash > 0 时换它
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
	anc = A.enemy_pixel_anchor(name, anc)
	sc *= A.enemy_pixel_scale(name)
	var ol: bool = g.tex.has(name + "_white") and _rim_on(e)
	var ra = atlas.reg.get(name) if atlas != null else null   # [17] / [18]：图集里的本体 / 白剪影区域（docs/50 §12 B），不在图集里为 null
	var rw = atlas.reg.get(name + "_white") if atlas != null else null
	var wra = null
	var wrw = null
	if wname != "" and g.tex.get(wname) != null:
		wra = atlas.reg.get(wname) if atlas != null else null
		wrw = atlas.reg.get(wname + "_white") if atlas != null else null
	else:
		wname = ""
	return [moving, e.stun > 0.0, e.coma, e.invuln, e.dormant, e.r, _dc_prep(e), _ol_sig(),
		name, frames, fps, col, sc, anc, off, ol, name + "_white", ra, rw, wname, wra, wrw, prep, remap]


## 缓存签名第 [6] 项：举肢准备态（atk_anim 的敌人在 prepare_range 内、还没蓄力 / 出手时换攻击帧条前两帧，_draw_enemy_full 同条件）
func _dc_prep(e: Dictionary) -> bool:
	return e.tex_attack and e.get("attack_preparing", false) and D.ENEMIES.get(e.type, _NO_DEF).get("atk_anim", false)


## 缓存签名第 [7] 项：旧写法的普通怪描边开关 + 精英冷色描边开关（任一变了缓存作废）
func _ol_sig() -> int:
	return 2 if elite_rim > 0.0 else 0


## 这只敌人画不画精英冷色描边
func _rim_on(e: Dictionary) -> bool:
	return e.get("ishar_blessed", false) or (elite_rim > 0.0 and e.elite and not e.boss) or e.get("squad", false)


## 描边颜色：精英冷色描边开着时用冷青（旧写法 ol_norm 下的橙红只在旋钮关时保留）；普通怪中性淡紫白
func _ol_col(e: Dictionary) -> Color:
	if e.get("ishar_blessed", false):
		return Color(3.2, 0.24, 0.3, 0.9)
	if e.get("squad", false):
		return SQUAD_RIM_COL
	if e.elite:
		return elite_rim_col if _rim_on(e) else Color(3.2, 1.1, 0.7, 0.75)
	var oc := Color(2.2, 2.0, 2.6, 0.5)
	oc.a *= ol_mul
	return oc


## 按缓存发绘制：和 _draw_enemy_full 末段同序（描边 → 本体 → 白闪 → 词条 → 弱点）
func _dc_emit(e: Dictionary, c: Array) -> void:
	var frames: int = c[9]
	var frame: int = int(g.t * float(c[10]) + e.id * 0.37) % frames
	if c[22]:
		frame = int((g.t - float(e.get("prepare_started", g.t))) * 3.0) % 2   # 举肢准备（_dc_prep）：和 _draw_enemy_full 同一选帧，再换算到帧条真实帧数
		if c[23]:
			frame = A.enemy_remap_frame(c[8], 4, frame)
	var ra = c[17]
	var rw_all = c[18]
	var body: String = c[8]
	var wht: String = c[16]
	if e.flash > 0.0 and c[19] != "":
		# 重画受击姿态（*_wound，1 帧）：受击闪白那几帧换姿态，白剪影同姿态
		body = c[19]
		wht = body + "_white"
		ra = c[20]
		rw_all = c[21]
		frames = 1
		frame = 0
	g.draw_off = _eoff(e)
	var flip: bool = e.fx < 0.0
	var bpos: Vector2 = e.pos + c[14]
	var sc: float = c[12]
	var anc: Vector2 = c[13]
	if c[15]:
		_espr_outline(body, frames, frame, bpos, sc, flip, _ol_col(e), anc, Vector2.ONE)
	if ra != null and _afast and _rec == null:
		# 图集快速路径（docs/50 §12 B）：本体和白闪直接按缓存的图集区域画，几何与 vfx.spr 相同；翻转时两次绘制共用一对变换
		var fw: int = ra[2] / frames
		var o: Vector2i = ra[1]
		var src := Rect2(o.x + fw * frame, o.y, fw, ra[3])
		var size := Vector2(fw, ra[3]) * sc
		var p: Vector2 = bpos + g.draw_off
		var rw = rw_all if e.flash > 0.0 else null
		if flip:
			g.draw_set_transform(p.round(), 0.0, Vector2(-1, 1))
			var rf := Rect2(-size * anc, size)
			g.draw_texture_rect_region(ra[0], rf, src, _rimc(c[11] * _act_mod))
			if rw != null:
				g.draw_texture_rect_region(rw[0], rf, src, Color(1, 1, 1, 0.9 if e.elite else flash_a) * _act_mod)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var rn := Rect2((p - size * anc).round(), size)
			g.draw_texture_rect_region(ra[0], rn, src, _rimc(c[11] * _act_mod))
			if rw != null:
				g.draw_texture_rect_region(rw[0], rn, src, Color(1, 1, 1, 0.9 if e.elite else flash_a) * _act_mod)
	else:
		_espr(body, frames, frame, bpos, sc, flip, c[11], anc, Vector2.ONE)
		if e.flash > 0.0:
			_espr(wht, frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9 if e.elite else flash_a), anc, Vector2.ONE)
	if g.optical_on and _rec == null:
		_glow_pts(body, frames, bpos + g.draw_off, sc, flip, anc, e, frame)
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
	var cm: Color = col * _act_mod if name.ends_with("_white") else _rimc(col * _act_mod)
	if atlas != null:
		var r = atlas.reg.get(name)
		if r != null:
			EnemyAtlas.spr(g, r, frames, frame, pos + g.draw_off, sc, flip, cm, anc, sq)
			return
	g.vfx.spr(name, frames, frame, pos, sc, flip, cm, anc, sq)


## 光学观感原型的敌人发光点（render/optical，占位）：每种帧条首帧里最亮、偏饱和的至多 3 个像素当「眼睛 / 核心」，
## 排进 g.glow_next，下一帧由 render/optical.gd 的发光层（跟随镜头、不受环境暗色与灯光影响）画，后期按发光体散辉光。只看帧条首帧、按帧条名缓存；美术重做后换成发光遮罩图
var _glow_cache := {}
## 位置取帧条首帧最亮的几处像素；颜色按颜色语言统一（render/optical.gd enemy_glow：普通 / 精英 / Boss），不用像素自身颜色。
## 普通怪 3 处，精英 / Boss 多一处、大一号
func _glow_pts(name: String, frames: int, pos: Vector2, sc: float, flip: bool, anc: Vector2, e: Dictionary, frame: int = 0) -> void:
	var pts = _emit_pts(name, frames, frame)   # 重画帧条（10-23）带独立 _emit 发光层：读它，不再自动取最亮像素
	if pts == null:
		pts = _glow_cache.get(name)
	if pts == null:
		pts = []
		var tx: Texture2D = g.tex.get(name)
		if tx != null:
			var img: Image = tx.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				var fw: int = img.get_width() / maxi(1, frames)
				var fh: int = img.get_height()
				# 先找「亮且偏饱和」的像素；整张都暗（深色怪）就退而取这一帧里相对最亮的像素，颜色拉到满亮度、偏青
				var cand: Array = []
				var all_px: Array = []
				for y in range(0, fh, 1):
					for x in range(0, fw, 1):
						var c: Color = img.get_pixel(x, y)
						if c.a < 0.9:
							continue
						var v: float = maxf(c.r, maxf(c.g, c.b))
						var s: float = (v - minf(c.r, minf(c.g, c.b))) / maxf(v, 0.001)
						if v > 0.7 and s > 0.3:
							cand.append([v * (0.4 + s), x, y, c])
						all_px.append([v + s * 0.3, x, y, c])
				if cand.is_empty() and not all_px.is_empty():
					all_px.sort_custom(func(a, b): return a[0] > b[0])
					for k in mini(12, all_px.size()):
						var c0: Color = all_px[k][3]
						var hc := Color.from_hsv(c0.h if c0.s > 0.15 else 0.5, maxf(c0.s, 0.45), 1.0)
						cand.append([all_px[k][0], all_px[k][1], all_px[k][2], hc])
				cand.sort_custom(func(a, b): return a[0] > b[0])
				var dens: float = A.hires_of(tx)
				for cd in cand:
					if pts.size() >= 4:
						break
					var q := Vector2(cd[1], cd[2])
					var far := true
					for o in pts:
						if (o[0] as Vector2).distance_to(q) < 3.0 * dens:
							far = false
					if far:
						pts.append([q, cd[3], Vector2(fw, fh), dens])
		_glow_cache[name] = pts
	var big: bool = e.get("elite", false) or e.get("boss", false)
	var cc: Color = g.optical.enemy_glow(e)
	var npt: int = mini(pts.size(), 4 if big else 3)
	for ip in npt:
		var pt: Array = pts[ip]
		var q: Vector2 = pt[0]
		var fs: Vector2 = pt[2]
		var d: Vector2 = (q - anc * fs) * sc / pt[3]   # sc 是 1x 美术像素的倍率，@2x 帧条要除以密度
		if flip:
			d.x = -d.x
		var sz: float = maxf(2.0, sc) * (1.5 if big else 1.0)
		g.glow_next.append([(pos + d - Vector2(sz, sz) * 0.5).round(), sz, cc])


## 重画帧条的发光层（name_emit，同帧索引、同原点）：每帧取发光像素按 6 美术像素格归并，取像素最多的至多 4 团的重心。
## 缓存 name -> 每帧点表；没有 _emit 图（旧帧条）返回 null，调用方退回旧的最亮像素法
var _emit_cache := {}

func _emit_pts(name: String, frames: int, frame: int):
	var ent = _emit_cache.get(name)
	if ent == null:
		ent = []
		var tx: Texture2D = A.tex(name + "_emit") if A.has_override(name + "_emit") else null
		if tx != null:
			var img: Image = tx.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				var dens: float = A.hires_of(tx)
				var n: int = maxi(1, frames)
				var fw: int = img.get_width() / n
				var fh: int = img.get_height()
				var cell: int = int(6.0 * dens)
				for fi in n:
					var cl := {}
					for y in fh:
						for x in range(fw * fi, fw * (fi + 1)):
							var c: Color = img.get_pixel(x, y)
							if c.a < 0.5:
								continue
							var key := Vector2i((x - fw * fi) / cell, y / cell)
							var a: Array = cl.get(key, [0, 0.0, 0.0, c])
							a[0] += 1
							a[1] += float(x - fw * fi)
							a[2] += float(y)
							cl[key] = a
					var lst: Array = cl.values()
					lst.sort_custom(func(p, q): return p[0] > q[0])
					var fpts: Array = []
					for k in mini(4, lst.size()):
						fpts.append([Vector2(lst[k][1] / lst[k][0], lst[k][2] / lst[k][0]), lst[k][3], Vector2(fw, fh), dens])
					ent.append(fpts)
		_emit_cache[name] = ent
	if ent.is_empty():
		return null
	return ent[clampi(frame, 0, ent.size() - 1)]


## 朝灯边缘亮线标记：开着时把 alpha 取负（着色器 vertex() 认、还原），关着原样返回
func _rimc(c: Color) -> Color:
	if _lamp_rim:
		c.a = -c.a
	return c


## 普通怪 / 精英帧条图集（docs/50 §12 B）：开局贴图载完后建一次。Boss（大帧条、网页版推迟加载）和骑士（专用帧条）不进；
## 无头模式不画，不建。进图集的帧条：本体、_move / _attack 等变体、休眠 / 唤醒 / 狂暴 / 假死，各自连同白剪影
func build_enemy_atlas() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Cfg.mobile_web() and Cfg.mobile_knob("mobile_no_atlas", 1.0):
		return   # 手机网页不拼图集（docs/50 §30）：图集是普通怪 / 精英帧条与白剪影的整份拷贝，原帧条也还留着，显存多一倍；手机按内存优先，走原帧条（不合批）
	var t0 := Time.get_ticks_usec()
	var names: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if str(d.get("role", "")) == "boss" or d.get("boss", false) or d.tex == "e_knight" or d.get("draw_full", false):
			continue
		var base: String = d.tex
		for sfx in ["", "_feign", "_dormant", "_awaken", "_enraged", "_swell"] + Game.ENEMY_SUFFIXES:   # _swell：囊海爬行者鼓胀帧条（docs/96 §1.3）
			if sfx == "_death" or names.has(base + sfx):
				continue
			if g.tex.get(base + sfx) != null:
				names.append(base + sfx)
	EnemyAtlas.xform_flip = not Cfg.dev_args().has("--atlasflip=neg")
	# 同一进程里贴图来自 A.tex 缓存、名单相同则图集相同：复用（10-21，图鉴演示每建一局重拼图集卡 1.5–2 秒）
	var key := "|".join(names) + "#%s#%s" % [EnemyAtlas.xform_flip, A.normal_maps]
	var ids := []
	for n in names:
		ids.append(g.tex[n].get_instance_id())
	if _atlas_cache.get("key", "") == key and _atlas_cache.get("ids", []) == ids:
		atlas = null if _atlas_cache.atlas.reg.is_empty() else _atlas_cache.atlas
		return
	atlas = EnemyAtlas.new()
	atlas.build(g.tex, names)
	_atlas_cache = {"key": key, "ids": ids, "atlas": atlas}
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
	var frames: int = A.enemy_frames(name, 2)
	var vt: float = g.t + g.vis_t   # 失败慢放里 g.t 已停，帧按画面时钟走（defeat_outro）
	var frame := int(vt * A.enemy_loop_fps(name, 2.0 if e.boss else 5.0) + e.id * 0.37) % frames
	# 移动帧条（美术 V5 / V8 / V9）：移动中播放 4 帧循环；停下、晕眩、假死时用本体
	if e.tex_move:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = vt + 0.2
		e.dpos = e.pos
		if vt < e.mv_until and e.stun <= 0.0 and not e.coma and g.tex.get(name + "_move") != null:
			name += "_move"
			frames = A.enemy_frames(name, 4)
			# 重画帧条（10-23）：循环速度 = 帧数 / 原作动画时长；旧的 move_fps 是给 4 帧旧图调的，没登记的帧条仍用它
			var fps: float = A.enemy_loop_fps(name, float(D.ENEMIES.get(e.type, _NO_DEF).get("move_fps", 6.0)))
			if e.enraged:
				fps *= float(D.ENEMIES.get(e.type, _NO_DEF).get("rage_move_fps_mult", 1.0))   # 收割者狂奔时腿更快（enemies.json）
			frame = int(vt * fps + e.id * 0.37) % frames
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
		frames = A.enemy_frames(name, 2)
		frame = int(g.t * A.enemy_loop_fps(name, 3.0) + e.id * 0.37) % frames
	elif e.get("wake_t", 0.0) > 0.0 and g.tex.get(e.tex + "_awaken") != null:
		name = e.tex + "_awaken"
		frames = A.enemy_frames(name, 4)
		frame = clampi(int((0.4 - e.wake_t) / 0.4 * frames), 0, frames - 1)
	elif e.get("enraged", false) and name == e.tex and g.tex.get(e.tex + "_enraged") != null:
		name = e.tex + "_enraged"
		frames = 2
		frame = int(g.t * 5.0 + e.id * 0.37) % 2
	var rage_fx: bool = e.get("enraged", false) and not D.ENEMIES.get(e.type, _NO_DEF).get("rage_keep_tint", false) and not e.get("squad", false) and Bal.v("render/rage_tint", 0.0) > 0.0   # rage_keep_tint：收割者的狂奔保持冷蓝本色；波纹另画。精英小队不叠狂暴的脚下红椭圆和全身红调（红描边已标危险；10-26 用户「还是有红色的底，并且全身发红」）；10-27 用户：普通怪狂暴也不染红、不画脚下红椭圆（render/rage_tint 缺省 0，1 = 恢复）
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
	if e.invuln and e.type != "ishar":   # 伊莎玛拉一阶段人形（friendly + invuln）画本色：蓝灰半透明会把白金配色洗成灰（用户 10-24「一阶段人形态是灰色的」）
		col = Color(0.7, 0.85, 1.0, 0.75)
	if e.chest:
		frame = 0
		var wob := 0.0
		if e.hidden and fmod(g.t + e.id, 3.0) < 0.25:
			wob = sin(g.t * 60.0) * 1.5
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
	if e.get("dash_t", 0.0) > 0.0 and Bal.v("render/enemy_dash_sparks", 1.0) > 0.0:   # docs/139 §7：0 = 冲刺途中不喷火花
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
		var xk: float = 1.0 - e.blast_w / float(e.get("blast_w0", xd.get("blast_fuse", 0.55)))
		# 范围圈改在特效之上的覆盖层画（draw_enemy_tells，docs/48 ②），这里只留本体胀大变亮
		col = col.lerp(Color(2.4, 1.1, 1.6), xk * 0.7)
		e.squash = maxf(e.squash, 0.14 * xk * (0.6 + 0.4 * sin(g.t * 40.0)))
	if e.get("burst_w", 0.0) > 0.0:
		if g.tex.get(e.tex + "_swell") != null:
			# 囊海爬行者鼓胀（Codex docs/96 §1.3 e_pocket_swell）：10fps 不循环，播到 f3 后停住直到蓄压结束（burst_fuse，囊海爬行者 1.1 秒）；
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
	# 冲刺蓄力的身体表现（docs/139 §7.4，render/dash_tell_style ≥ 1）：往冲刺反方向缩 render/dash_pull 美术像素、按蓄力进度渐变到危险色（不闪）
	if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir") and not e.boss and Bal.vi("render/dash_tell_style", 2) >= 1:
		var dwk: float = clampf(1.0 - e.dash_w / float(e.get("dash_w0", D.ENEMIES.get(e.type, {}).get("dash_wind", 0.5))), 0.0, 1.0)
		bpos -= (e.dash_dir as Vector2) * Bal.v("render/dash_pull", 3.0) * Game.PX * dwk
		var dfl: float = dwk * Bal.v("render/dash_flash", 0.6)   # 随蓄力进度平滑变色，不闪（10-24 Boss 频闪教训）
		var dc: Color = g.optical.col_danger if g.optical_on else ENEMY_TELL
		col = col.lerp(Color(dc.r * 1.6, dc.g * 1.6, dc.b * 1.6, col.a), clampf(dfl, 0.0, 1.0))
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
			col = col.lerp(Color(1.8, 1.5, 1.4), 0.35 * wk)   # 蓄力逐渐提亮（原来叠 sin(t×30) 约 5 Hz 明暗振荡，docs/137 去掉）
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
	var final_pose := final_boss_animation(e) if e.boss else {}
	if not final_pose.is_empty():
		name = final_pose.name
		frames = final_pose.frames
		frame = final_pose.frame
	var va := _vis_anim(e)
	if not va.is_empty():
		name = va.name
		frames = va.frames
		frame = va.frame
	# 重画受击姿态（10-23 *_wound，1 帧）：受击闪白那几帧，待机 / 移动 / 攻击 / 专用动作都换它（白剪影同姿态）；死亡、伪装等不换。
	# Boss 不换（docs/137）：白剪影跟当前动作走，密集命中时不在当前动作和单帧受击姿态之间来回跳
	if e.flash > 0.0 and not e.boss and not e.chest and (name == e.tex or name == e.tex + "_move" or name.ends_with("_attack") or name == tbase or name == "e_paranoia2" or name.begins_with("e_knight")):
		var wb: String = "e_paranoia_phase2" if name == "e_paranoia2" else (tbase if tbase != e.tex else e.tex)
		if name.begins_with("e_knight_walk"):
			wb = "e_knight_walk"
		if _lazy_tex(wb + "_wound") != null:
			name = wb + "_wound"
			frames = 1
			frame = 0
	# 重画帧条（10-23）：上面各选帧器按旧帧数（2 / 4 帧）给的帧号，换成帧条真实帧数；攻击类蓄力段摊到出手帧之前、出手后摊到之后（A.enemy_remap_frame）
	var nfr: int = A.enemy_frames(name, frames)
	if nfr != frames:
		frame = A.enemy_remap_frame(name, frames, frame)
		frames = nfr
	# @2x 高清帧条（伊莎玛拉变身形态有 @2x）：同一逻辑尺寸，按密度减半
	if g.tex.get(name) == null and not g.tex_deferred.is_empty():
		g.tex_deferred_miss(name)   # 网页版推迟加载漏网：记日志并补读
	var hr: float = A.hires_of(g.tex.get(name)) if g.tex.get(name) != null else 1.0
	if hr > 1.0:
		sc /= hr
	anc = A.enemy_pixel_anchor(name, anc)
	sc *= A.enemy_pixel_scale(name)
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
		if e.get("squad", false):
			oc = SQUAD_RIM_COL
		if e.get("part", false):
			oc = Color(PART_COL.r * 2.0, PART_COL.g * 2.0, PART_COL.b * 2.0, 0.7 + 0.3 * _heartbeat(e))   # 普通怪：中性偏淡紫白（原青白，和经验结晶、击杀溶解同色连片，docs/48 P1）   # 精英：橙红（docs/48 ⑤，原金色和友方金圈、刀光撞色）
		if e.get("ishar_blessed", false):
			oc = _ol_col(e)
		if not e.elite and not e.boss and not e.get("squad", false):
			oc.a *= ol_mul   # 后期满屏敌人时普通怪描边变淡，不再连成一片（EA 1.1；下限 render/declutter ol_floor，缺省 0.4）；精英 / Boss 不变
		_espr_outline(name, frames, frame, bpos, sc, flip, oc, anc, sq)
	# 囊海爬行者破膜（Codex docs/96 §1.3）：back（本体后）→ 本体 → front（本体前），两层同原点 (24,28)、同起播时间与帧号；
	# 原点对齐脚底 bpos，按本体缩放；只有 enemies.gd 写了 burst_fx_t（爆发那一刻）的 0.375 秒内画，缺图就不画（判定不变）
	var bfx: int = _burst_fx_frame(e)
	if bfx >= 0 and _rec == null:
		_burst_fx_layer(e, "_back", bfx, bpos, flip)
	_espr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if g.optical_on and _rec == null:
		_glow_pts(name, frames, bpos + g.draw_off, sc * sq.x, flip, anc, e, frame)
	if e.flash > 0.0:
		# 受击白闪：普通怪随 ecrowd 降到 declutter flash_a（缺省 0.9 = 不变）；精英 / Boss 照旧
		var hit_a: float = g.vfx.boss_flash_alpha(e, Bal.v("fx/flash_boss", 0.5)) if e.boss else (0.9 if e.elite else flash_a)   # Boss 白闪 50%（docs/127 C3：大体型整块变白刺眼）、限频淡出（docs/137）
		_espr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, hit_a), anc, sq)
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
var draw_target: CanvasItem = null   # 光学观感的高清干员层：干员本体临时画到这里（render/optical.gd _draw_ops 设，画完清回 null）

func draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float, sc := 1.0) -> void:
	if tx == null:
		return
	var ci: CanvasItem = draw_target if draw_target != null else g
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	var pk: float = Game.PX / A.hires_of(tx) * sc   # sc：召唤物体型（可见成长 #130，docs/163）；缺省 1
	ci.draw_set_transform((pos + g.draw_off).round(), 0.0, Vector2(-pk if flip else pk, pk))
	ci.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off), Vector2(fw, fh)), src, Look.op_mod(g, pos, col))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
				var s := 0.0 if not e.boss or Bal.v("render/knight_frost_tell", 1.0) <= 0.0 else L   # 骑士 Boss 的冲锋霜纹改由 boss_attack_draw._dash_frost 按到达时间显露
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
			var xk: float = clampf(1.0 - e.blast_w / float(e.get("blast_w0", xd.get("blast_fuse", 0.55))), 0.0, 1.0)
			_tell_circle(e.pos, float(xd.get("blast_r", 62)), xk, ENEMY_TELL)
		if e.get("burst_w", 0.0) > 0.0:
			_tell_circle(e.pos, float(D.ENEMIES.get(e.type, {}).get("burst_r", 80.0)), clampf(1.0 - e.burst_w / float(e.get("burst_dur", 0.4)), 0.0, 1.0), TELL_BURST)
		# 冲刺预警线（滑动者 / 撕裂者 / 骑士精英）：长度按实际冲刺距离算（速度 × dash_speed × 0.35 秒），
		# 不再写死 230（docs/48 P1：实际只冲 80–135）；只朝前画
		if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir") and Bal.v("render/dash_tell", 1.0) > 0.0:   # render/dash_tell 0 = 不画（docs/139 §7 量测用）
			var dd: Dictionary = D.ENEMIES.get(e.type, {})
			var wk: float = clampf(1.0 - e.dash_w / float(dd.get("dash_wind", 0.5)), 0.0, 1.0)
			match Bal.vi("render/dash_tell_style", 2):
				1:
					_dash_chevrons(e, wk, not e.get("tell_dim", false))
				2:
					if not e.get("tell_dim", false):   # 只给会冲到队长的画：冲刺距离前 45% 的短箭 + 箭头
						var sb: Vector2 = e.pos + e.dash_dir * _dash_len(e) * Bal.v("render/dash_short", 0.45)
						_tell_line(e.pos, sb, Bal.v("render/dash_tell_half", 6.0), wk, ENEMY_TELL, false, true)
						_dash_head(sb, e.dash_dir, wk)
				_:
					_tell_line(e.pos, e.pos + e.dash_dir * _dash_len(e), Bal.v("render/dash_tell_half", 6.0), wk, ENEMY_TELL, e.get("tell_dim", false), true)   # render/dash_tell_half 半宽
		# 伊祖米克解读阶段的冲击波已改走 boss_ai._warn（1 秒预警、must_dash 标记，Boss与怪物 docs/48 P0-5），这里不再按 bt 预告
		if e.get("count_max", 0.0) > 0.0 and float(e.get("count_end", 0.0)) > g.t:
			_count_ring(e)
		var stk = e.get("stakes")   # 不给每只敌人新建默认空数组（docs/50 §14）
		if stk is Array and not stk.is_empty():
			_draw_stakes(e)
		var armor_def: Dictionary = D.ENEMIES.get(e.type, _NO_DEF)
		if (float(e.get("set_t", 0.0)) > 0.0 and armor_def.has("entrench_phys_taken")) or (e.enraged and armor_def.has("enrage_phys_taken")):
			# 常亮像素盾标，直接读取真实硬化状态，结束时自然消失。
			var ap: Vector2 = (_enemy_top(e) + Vector2(0, -28)).round()
			g.draw_rect(Rect2(ap + Vector2(-5, -4), Vector2(10, 6)), Color(0.65, 0.8, 1.0))
			g.draw_rect(Rect2(ap + Vector2(-3, 2), Vector2(6, 2)), Color(0.65, 0.8, 1.0))
			g.draw_rect(Rect2(ap + Vector2(-1, 4), Vector2(2, 2)), Color(0.65, 0.8, 1.0))
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
	if tx == null:
		return e.pos + Vector2(0, -e.r - 8.0)
	var foot: bool = g.foot_anchor.has(e.tex)
	var offset: float = (31.0 if e.type == "ishar" else e.r) * 0.8 + 3.0 * Game.PX if foot else 0.0
	var sc: float = enemy_scale(e) / A.hires_of(tx)
	if not A.enemy_pixel_spec(name).is_empty():
		return e.pos + Vector2(0, offset - A.enemy_pixel_top(name, tx) * sc * A.enemy_pixel_scale(name))
	if not foot:
		return e.pos + Vector2(0, -e.r - 8.0)
	return e.pos + Vector2(0, offset - tx.get_height() * sc)


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
		if ed.has("aura_arts_mult") and (float(e.get("seal_t", 0.0)) > g.t or e.stun > 0.0):
			continue
		if ed.has("scream_r") and not ed.has("aura_r"):
			if g.t >= float(e.get("scream_t0", INF)) and g.t < float(e.get("scream_t1", -1.0)):
				_scream_aura(e, float(ed.scream_r))
			continue
		if not ed.has("aura_r"):
			continue
		var ar: float = ed.aura_r
		if not view_rect(ar + 20.0).has_point(e.pos):
			continue   # 屏外不画（性能 9/30：原来全场每只都画）
		var lite: bool = Bal.v("render/nest_aura_lite", 0.0) > 0.0   # docs/139 §8：只留一层淡底 + 不转的虚线边界
		var aura_tex := _lazy_tex("fx_nest_aura_big") if not lite else null
		if aura_tex != null:
			var fw: float = aura_tex.get_width() / 4.0
			var frame := int(g.t * 10.0) % 4
			g.draw_texture_rect_region(aura_tex, Rect2(e.pos - Vector2.ONE * ar, Vector2.ONE * ar * 2.0), Rect2(frame * fw, 0, fw, aura_tex.get_height()), Color(1, 1, 1, 0.5 if g.t - float(e.get("aura_pulse_t", -1.0)) < 0.15 else 0.35))
		# 柔光底 / 内收涟漪 / 转动虚线外圈都进无贴图批，函数末尾一次提交（原来每只约 24 次绘制调用）
		var ac := Color(0.9, 0.5, 1.6)
		if lite:
			tb_circle(e.pos, ar, Color(ac.r, ac.g, ac.b, 0.05), 1.0, 32)
			for q in 18:
				var a0l: float = e.id + q * TAU / 18.0
				tb_arc(e.pos, ar, a0l, a0l + TAU / 36.0, 2.0, Color(ac.r, ac.g, ac.b, 0.45), 3)
			continue
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



## 箱形恐鱼尖叫光环（docs/145 §4 A；画法按画面观感会话 10-25「圆圈收敛」口径）：随它移动、地面层；
## 常亮淡底 + 不转的 18 段虚线边界（起始角按 e.id 固定），不加涟漪 / 脉动 / 贴图；危险色；
## 尖叫开始 0.2 秒内边界 0.7 → 0.45（一次性），队长在圈内时边界 0.6。判定同 enemy_ai._scream（直线距离 < r）
func _scream_aura(e: Dictionary, r: float) -> void:
	if not view_rect(r + 20.0).has_point(e.pos):
		return
	var c: Color = g.optical.col_danger if g.optical_on else ENEMY_TELL
	var since: float = g.t - float(e.scream_t0)
	var ea: float = lerpf(0.7, 0.45, clampf(since / 0.2, 0.0, 1.0))
	if g.ppos.distance_to(e.pos) < r:
		ea = maxf(ea, 0.6)
	tb_circle(e.pos, r, Color(c.r, c.g, c.b, 0.05), 1.0, 40)
	var a0: float = float(e.id) * 0.37
	for q in 18:
		var s0: float = a0 + q * TAU / 18.0
		tb_arc(e.pos, r, s0, s0 + TAU / 36.0, 2.0, Color(c.r, c.g, c.b, ea), 3)


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
	# 10-27（docs/170）：去掉整片平涂和实线外圈（像 UI 光盘），外缘改成一圈缓慢漂移的小泡沫
	tb_circle(o, r, Color(c.r, c.g, c.b, 0.02 if inn else 0.008), gy, 48)
	for q in 44:
		var fa: float = q * TAU / 44.0 + g.t * 0.08 + 0.05 * sin(g.t * 1.3 + q * 1.7)
		var fr: float = 2.0 + 1.5 * absf(sin(q * 2.3 + g.t * 0.9))
		tb_arc(sq.call(Vector2.from_angle(fa) * (r - 3.0 + 4.0 * sin(q * 0.9 + g.t))), fr, 0.0, TAU, 1.0, Color(c.r, c.g, c.b, 0.55 * a), 8)
	if Bal.v("render/burden_lite", 0.0) > 0.0:
		return   # docs/139 §8：只留淡底 + 外圈（不画内圈与转动符文）
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
		g.draw_arc(c, rr * wob, 0.0, TAU, 48, Color(2.0, 2.0, 2.0, g.vfx.boss_flash_alpha(e, 0.8)), 4.0)
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
			# 未点燃：灯室一点琥珀色呼吸光（10-28 用户「灯塔还没被激活时加提醒」；原来是很淡的灰蓝，看不出在等人点）
			var br: float = 0.5 + 0.5 * sin(g.t * 2.4)
			g.draw_circle(lamp, 9.0 + 3.0 * br, Color(1.0, 0.68, 0.32, 0.16 + 0.16 * br))
			g.draw_circle(lamp, 4.0, Color(1.5, 1.05, 0.55, 0.55 + 0.35 * br))


## 点燃瞬间：暖白爆闪 + 一道光环扩到清痕半径 + 放射光束 + 火花
func beacon_burst(b: Dictionary) -> void:
	var pos: Vector2 = b.get("pos", Vector2.ZERO)
	g.fx.append({"kind": "beacon_burst", "pos": pos, "r": float(b.get("clear_r", 260.0)), "life": 0.9, "max": 0.9})
	g.vfx.sparks(pos + Vector2(0, -60), Vector2.ZERO, Color(1.8, 1.4, 0.7), 18, 300.0)
	_flash(Color(1.0, 0.85, 0.55), 0.3)
	g.vfx.beacon_ignite(b)   # docs/54：柔光 + 余烬 + 溟痕退散


## 最后的骑士冰柱（e.stakes = [{pos, until, born}]，判定 r 22）：冰柱帧条（没有就退回冰枪桩 / 程序长枪）+ 脚下冰霜圈；快到期（< 2 秒）时闪烁
func _draw_stakes(e: Dictionary) -> void:
	for st in e.stakes:
		if g.t < float(st.get("born", -99.0)):
			continue   # Placement preview remains visible; pillar rises only at its announced time.
		var left: float = float(st.until) - g.t
		if left <= 0.0:
			continue
		var a: float = 1.0 if left > 2.0 else 0.35 + 0.65 * absf(sin(g.t * 12.0))
		var p: Vector2 = st.pos
		g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))
		g.draw_circle(Vector2.ZERO, 22.0, Color(0.36, 0.52, 0.60, 0.10 * a))
		g.draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.60, 0.74, 0.78, 0.45 * a), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if g.tex.get("prop_knight_frost_stake") != null:
			# 冰柱（10-25 用户「骑士的桩设置成冰柱」，tools/gen_ice_pillar.py：ansimuz Ice_b，64 × 96、脚底第 94 行）：统一冷灰蓝衍生帧条，整数像素；新立的先播破土 0.25 秒
			var age: float = g.t - float(st.get("born", -99.0))
			var pc := Color(1.0, 1.0, 1.0, a)
			if age < 0.25 and g.tex.get("prop_knight_frost_stake_rise") != null:
				g.vfx.spr("prop_knight_frost_stake_rise", 3, clampi(int(age / 0.25 * 3.0), 0, 2), p, 1.0, false, pc, Vector2(0.5, 94.0 / 96.0))
			else:
				g.vfx.spr("prop_knight_frost_stake", 4, int(g.t * 4.0) % 4, p, 1.0, false, pc, Vector2(0.5, 94.0 / 96.0))
			continue
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


## 任意（可凹）多边形：同 draw_colored_polygon 的三角化（Geometry2D.triangulate_polygon），进批
func tb_polygon(pts: PackedVector2Array, col: Color) -> void:
	_tbb.polygon(pts, col)


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
		"label": ("泪滴已净化" if blocked else "触碰净化泪滴") if neutral else ""
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
		var recovering: bool = e.type=="knight_boss" and e.stun<=0.05 and str(e.get("brk_label",""))=="破绽"
		var quiet: bool = brk > 0.0 and g.combat.final_break_quiet(e)   # 最终 Boss 破绽不写字（用户 10-28，render/break_ring 画金环）
		if recovering and quiet:
			pass
		elif recovering:
			UI.text(g, g.font, top + Vector2(-120,-12), "收招 · 破绽 %.1f" % brk, 13, Color(.65,.85,.95), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		else:
			for q in 3:
				var a: float = g.t * 5.0 + q * TAU / 3.0
				var sp: Vector2 = top + Vector2(cos(a) * 18.0, sin(a) * 5.0)
				UI.diamond(g, sp, 4.0, Color(1.8, 1.6, 0.6), Color(0, 0, 0, 0.6))
		if e.has("ammo") and brk > 0.0:
			UI.text(g, g.font, top + Vector2(-120, -12), "装填被打断 · 破绽 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif brk > 0.0 and e.type == "knight_boss":
			# 骑士（用户 10-25）：只在撞冰柱眩晕时写「眩晕」读秒，别的破绽不写字
			if str(e.get("brk_label", "")) == "眩晕":
				UI.text(g, g.font, top + Vector2(-120, -12), "眩晕 %.1f" % brk, 13, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 240, 3)
		elif quiet:
			pass
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


## dash = 杂兵冲刺预警（docs/139 §7，用户 10-24「后期冲刺的那些太着眼」）：render/dash_tell_alpha 整体透明度倍率、
## render/dash_tell_flow 0 = 不铺流动水纹 / 终点漩涡（只留填充 + 边框），render/dash_tell_white 0 = 不画中线白芯，render/dash_tell_half 半宽（缺省 10）
func _tell_line(a: Vector2, b: Vector2, half: float, k: float, c: Color, dim := false, dash := false) -> void:
	var d: Vector2 = b - a
	var n: Vector2 = d.normalized().orthogonal() * half
	var ta: float = Bal.v("render/dash_tell_alpha", 0.55) if dash else 1.0
	if dim:
		# 打不到主控的冲刺线：只画淡边框（预警不藏，但不再整片盖住主控）
		g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, Bal.v("fx/tell_dim_alpha", 0.2) * ta), 1.5)
		return
	g.draw_colored_polygon(PackedVector2Array([a + n, a + d * k + n, a + d * k - n, a - n]), Color(c.r, c.g, c.b, (0.22 + 0.12 * k) * tell_fill * ta))
	var lt: Texture2D = _wtex("fx_warn_line") if not dash or Bal.v("render/dash_tell_flow", 0.0) > 0.0 else null
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
			g.draw_texture_rect_region(lt, Rect2(0, -8, w / (half * 2.0 / 16.0), 16), Rect2(16 * fr, 0, w / (half * 2.0 / 16.0), 16), Color(c.r, c.g, c.b, 0.55 * tell_fill * ta))
			x += seg
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var et: Texture2D = _wtex("fx_warn_end")
		if et != null:
			var es: float = half * 2.4 / 32.0 * 2.0
			g.draw_set_transform(b, 0.0, Vector2(es, es * ground_y()))
			g.draw_texture_rect_region(et, Rect2(-16, -16, 32, 32), Rect2(32 * fr, 0, 32, 32), Color(c.r, c.g, c.b, 0.8 * ta))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(0, 0, 0, 0.55 * ta), 4.0 * tell_edge)
	g.draw_polyline(PackedVector2Array([a + n, b + n, b - n, a - n, a + n]), Color(c.r, c.g, c.b, 0.85 * ta), 2.0 * tell_edge)
	if not dash or Bal.v("render/dash_tell_white", 0.0) > 0.0:
		g.draw_line(a, b, Color(1, 1, 1, (0.5 + 0.4 * k) * ta), 1.0)


## （10-23 用户定：手动普攻的方向 / 目标箭头指示已去掉——方向就是玩家的指向，不再画线与箭头；原 draw_attack_dir 删除）


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
## 冲刺预警风格 1（docs/139 §7.4）：怪物脚前 3 个「›」箭头沿冲刺方向依次点亮（蓄力 0–⅓–⅔–1），深色底 + 危险色线；
## 打不到队长的只亮最近一个、半透明。不画整条线
func _dash_chevrons(e: Dictionary, wk: float, threat: bool) -> void:
	var dv: Vector2 = e.dash_dir
	var nv: Vector2 = dv.orthogonal()
	var c: Color = ENEMY_TELL
	var n: int = 3 if threat else 1
	for i in n:
		var lit: float = clampf(wk * 3.0 - float(i), 0.0, 1.0)
		if lit <= 0.0 and i > 0:
			continue
		var a: float = (0.35 + 0.6 * lit) * (1.0 if threat else 0.4)
		var tip: Vector2 = e.pos + dv * (float(e.get("r", 10.0)) + 10.0 + 11.0 * i)
		var pts := PackedVector2Array([tip - dv * 6.0 + nv * 6.0, tip, tip - dv * 6.0 - nv * 6.0])
		g.draw_polyline(pts, Color(0, 0, 0, 0.6 * a), 5.0)
		g.draw_polyline(pts, Color(c.r, c.g, c.b, a), 2.5)


## 风格 2 的箭头
func _dash_head(p: Vector2, dv: Vector2, wk: float) -> void:
	var nv: Vector2 = dv.orthogonal()
	var c: Color = ENEMY_TELL
	var pts := PackedVector2Array([p - dv * 9.0 + nv * 8.0, p + dv * 3.0, p - dv * 9.0 - nv * 8.0])
	g.draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0)
	g.draw_polyline(pts, Color(c.r, c.g, c.b, 0.55 + 0.4 * wk), 2.5)


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
	var nmax: int = Bal.vi("fx/tell_full_max", 4)
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


## render/tell_circle_calm 1（docs/139 §8）：不铺流动涟漪贴图、描边不脉动（填充随倒计时长满照旧）
func _tell_circle(p: Vector2, r: float, k: float, c: Color) -> void:
	var calm: bool = Bal.v("render/tell_circle_calm", 0.0) > 0.0
	var pulse: float = 0.0 if calm else 0.5 + 0.5 * sin(g.t * 18.0)
	g.draw_set_transform(p, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致
	g.draw_circle(Vector2.ZERO, r * k, Color(c.r, c.g, c.b, (0.18 + 0.1 * k) * tell_fill))
	var rt: Texture2D = _wtex("fx_warn_ring") if not calm else null
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

## 刀光第四版：把这一帧前沿新扫过的角度段 [上帧前沿, 本帧前沿] 按月牙剖面（外沿到内沿，2 世界像素一格）取样成颗粒发射点，
## 初速沿挥刀切线（惯性），颜色 = 干员本色（模板颜色阶乘在上面：热白 → 本色 → 冷暗）；单帧点数超模板上限时均匀抽稀。
## 前沿另画一道 2 px 热白细线，读出「刀口」；尾部不画实体，由颗粒自己冷却熄灭
func _marc_grains(f: Dictionary, gr, ap: Vector2, rc: float, tw: float, s0: float, sw: float, hd: float, cc: Color, kb: float, aq: float) -> void:
	var u0: float = float(f.get("gu", 0.0))
	if hd > u0 + 0.001 and (gr.pos.size() >= gr.budget() or not gr.view.has_point(ap)):
		f["gu"] = hd   # 颗粒已满 / 挥刀点在屏外（docs/50 §26）：这段不取样（push 反正全丢），刀口线照画
	elif hd > u0 + 0.001:
		var cells: Array = []
		var nu: int = maxi(1, int(absf(sw) * (hd - u0) * rc / 2.0))
		for i in nu:
			var u: float = lerpf(u0, hd, (float(i) + 0.5) / float(nu))
			var uu: float = clampf(u, 0.0, 1.0)
			var th: float = tw * pow(sin(PI * uu), 0.6) * (0.35 + 0.65 * uu)
			var ang: float = s0 + sw * u
			var dv := Vector2.from_angle(ang)
			var tg := dv.orthogonal() * signf(sw)   # 挥刀切线方向
			var nr: int = maxi(1, int(th / 2.0))
			for j in nr:
				cells.append([ap + dv * (rc - float(j) * 2.0), tg])
		var cap: int = int(gr.TEMPLATES.slash.per_frame)
		var stride: float = maxf(1.0, float(cells.size()) / float(cap))
		var k: float = 0.0
		var col := Color(minf(1.0, cc.r * kb), minf(1.0, cc.g * kb), minf(1.0, cc.b * kb), cc.a)
		while int(k) < cells.size():
			var c: Array = cells[int(k)]
			gr.push("slash", c[0], c[1], col)
			k += stride
		f["gu"] = hd
	if hd < 1.0:
		var e0: float = s0 + sw * maxf(0.0, hd - 0.06)
		var e1: float = s0 + sw * hd
		g.draw_arc(ap, rc - 1.0, minf(e0, e1), maxf(e0, e1), 6, Color(2.0, 2.0, 2.0, aq), 2.0)   # 刀口热白线


## 近战刀光月牙（"marc"）：外沿在半径 r 的圆上，内沿离外沿 thick × sin(π u)；u 是整次挥刀上的位置（0 起点 / 1 终点），
## 只画 [u0, u1] 那一段（跟着挥刀扫）。起点角 s0，扫过 sweep（带方向的弧度）
func _crescent(c: Vector2, r: float, s0: float, sweep: float, u0: float, u1: float, thick: float, col: Color, _k: float) -> void:
	var n: int = clampi(int(absf(sweep) * (u1 - u0) * r / 4.0), 3, 40)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var u: float = lerpf(u0, u1, float(i) / float(n))
		var ang: float = s0 + sweep * u
		var uu: float = clampf(u, 0.0, 1.0)
		var th: float = thick * pow(sin(PI * uu), 0.6) * (0.35 + 0.65 * uu)   # 前粗后尖（彗星形）：靠挥刀终点一侧最厚
		var dv := Vector2.from_angle(ang)
		outer.append(c + dv * r)
		inner.append(c + dv * maxf(0.0, r - th))
	inner.reverse()
	outer.append_array(inner)
	if outer.size() >= 3:
		g.draw_colored_polygon(outer, col)


func _warn_dash_arc(r: float, a0: float, a1: float, col: Color, wdt: float) -> void:
	var seg: float = 0.22
	var a: float = a0
	while a < a1:
		g.draw_arc(Vector2.ZERO, r, a, minf(a + seg * 0.55, a1), 4, col, wdt)
		a += seg


func draw_warn_outlines(ground := false) -> void:
	for w in g.warns:
		if w.done or TeleDraw.quiet(w) or bool(w.get("ground", false)) != ground or w.get("saint_beam", false):   # saint_beam：圣徒光束蓄力自己画（render/saint_draw）
			continue   # ground：小怪踏地的轮廓在地面层画（_draw_ground_foe_fx），不压在单位上
		if IsharTell.owns(w):
			continue   # 伊莎玛拉：涟漪勾边已在 ishar_tell_draw 画（docs/170）
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var tr: float = float(w.get("track", 0.0))
		var tracking: bool = tr > 0.0 and w.t < tr
		var lk: float = w.t - tr
		var lock_flash: float = (1.0 - lk / 0.15) if tr > 0.0 and lk >= 0.0 and lk < 0.15 else 0.0
		var core := Color(WARN_CORE.r, WARN_CORE.g, WARN_CORE.b, 0.7 + 0.3 * k)
		if g.optical_on and g.optical.fx1:
			var dc: Color = g.optical.col_danger   # 光学观感 ④：描边危险色、闪烁（越近结算越快）
			core = Color(minf(1.0, dc.r * 1.15), minf(1.0, dc.g * 1.15 + 0.1), minf(1.0, dc.b * 1.15 + 0.1), 0.55 + 0.45 * absf(sin(g.t * (8.0 + 10.0 * k))))
		var edge := Color(WARN_EDGE.r, WARN_EDGE.g, WARN_EDGE.b, 0.7)
		var da: float = 1.0
		if w.get("dim", false):
			# 打不到主控的杂兵预警（classify_tells）：轮廓整体降到 fx/tell_dim_alpha，不白闪；地面填充在 boss_ai._draw_warns 里跳过
			da = Bal.v("fx/tell_dim_alpha", 0.2)
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
				# 缺口处的「出口」字样 10-22b 用户取消：只留两侧金线标出缺口


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


## 黑潮圈边的溟痕格（栅格化 + 补洞求围边）按「圆心、半径、弧段」记住（docs/50 §26：后期每帧重算约占一帧 5%）：
## 弧段两端按 4 个采样取整（多出的格子在视野外扩 80 像素之外，屏内画面不变），圈不动时镜头走动多数帧直接复用；缩圈时半径每帧在变照旧重算
var _zc_key: Array = []
var _zc_val: Array = []
func _zone_cells(c: Vector2, r: float, cw: float, nb2: int, rj: Vector2i) -> Array:
	var a0: int = floori((rj.x - 1) / 4.0) * 4
	var a1: int = ceili((rj.y + 2) / 4.0) * 4
	var key: Array = [c, r, nb2, a0, a1]
	if key == _zc_key:
		return _zc_val
	var ins := {}
	for jr in range(a0, a1):
		var d3 := Vector2.from_angle(TAU * float(posmod(jr, nb2)) / nb2)
		var rr := r - 4.0
		while rr <= r + 36.0:
			var q := Vector2i(floori((c.x + d3.x * rr) / cw), floori((c.y + d3.y * rr) / cw))
			if not ins.has(q):
				var dd: float = ((Vector2(q) + Vector2(0.5, 0.5)) * cw).distance_to(c)
				if dd >= r - 4.0 and dd <= r + 36.0:
					ins[q] = true
			rr += cw * 0.5
	_zc_key = key
	_zc_val = g.map.mire_cells(ins) if not ins.is_empty() else []
	return _zc_val


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
	# 10-24 用户「直接改溟痕颜色」（docs/139 §6.4 方案 A）：带色、贴图块与地上溟痕同乘 render/mire_tint，靛紫 → 深海青蓝
	var mtn: Color = g.map.mire_tint()
	var c_in := Color(0.06, 0.03, 0.1, 0.92) * mtn
	var c_mid := Color(0.05, 0.03, 0.08, 0.8) * mtn
	var c_out := Color(0.05, 0.02, 0.08, 0.0) * mtn
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
	# 溟痕 v2（world_spec_1024）：圈边改用同一套 1:1 平铺 + 围边——环带 [r − 4, r + 36]（世界单位）按溟痕格栅格化，只取镜头附近那段弧
	var mt: Texture2D = null if g.map.mire_v2 else g.tex.get("terrain_mire")
	if g.map.mire_v2:
		var cw: float = g.map.MIRE_CELL * Game.PX
		var nb2: int = clampi(int(TAU * r / (cw * 0.5)), 24, 4000)
		var rj: Vector2i = _arc_range(nb2, c, r, vc, view)
		if rj.y >= rj.x:
			var zc: Array = _zone_cells(c, r, cw, nb2, rj)
			if not zc.is_empty():
				g.map.draw_mire_cells(zc, int(t * 2.0) % 2, Color(1, 1, 1, 0.95))
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
				g.draw_texture_rect_region(mt, Rect2(-sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95) * mtn)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				g.draw_texture_rect_region(mt, Rect2(bp - sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95) * mtn)
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
	# docs/139 §6 试验旋钮 render/zone_dark_r / _g / _b：黑潮圈外压暗色（缺省原值紫 0.16, 0.03, 0.22）
	cs.fill(Color(Bal.v("render/zone_dark_r", 0.03), Bal.v("render/zone_dark_g", 0.08), Bal.v("render/zone_dark_b", 0.12), 0.55))
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


## 面板关闭后的保护（combat.panel_grace）：脚下一圈淡金双环向内收拢、随剩余时间变淡。
## 贴地椭圆、暖白金色，和护盾（罩住身体的淡金气泡，10-28 改版）靠贴地椭圆区分；无敌期间本体照常闪烁
func draw_panel_grace() -> void:
	var left: float = g.panel_grace_until - g.t
	if left <= 0.0:
		return
	var k: float = clampf(left / maxf(0.01, Game.Bal.v("protect/panel_grace", 0.8)), 0.0, 1.0)
	var c := g.ppos + Vector2(0, 14)
	var r := 26.0 + 18.0 * k
	g.draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.4, 1.25, 0.8, 0.75 * k), 2.0)
	g.draw_arc(Vector2.ZERO, r + 7.0, 0.0, TAU, 40, Color(1.4, 1.25, 0.8, 0.3 * k), 1.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 护盾（用户 10-28「护盾看不到，重新画」）：偏白淡金柔和气泡罩住队长身体中心（10-28 用户嫌条段环丑，三候选里定 B），层数 = 边缘光带厚度 + 边顶小菱形，
## 不填实心、不压脚下预警；未满时外侧细弧显示下一层充能进度。层数变化在画面这边比对得出（只画面，不改逻辑）：
## 少一层 = 碎裂（碎片颗粒 + 外扩闪环），碎时一下淡金微闪，之后 0.5 秒无敌期间边上流微光；多一层 = 边缘亮一下 + 充能完成颗粒。
## 低画质照画形状与层数，颗粒由 fx_grains 按 low_k 稀疏。
const SH_COL := Color(1.0, 0.9, 0.68)   # 偏白淡金（10-28 用户嫌原琥珀黄发光后像警示黄）
var _sh_prev := -1
var _sh_brk_t := -9.0      # 上次碎裂（g.t）
var _sh_chg_t := -9.0      # 上次充好一层（g.t）

func draw_shield() -> void:
	var c := g.ppos + Vector2(0, -26)
	var r0 := 34.0
	var n: int = g.shield
	if _sh_prev < 0:
		_sh_prev = n
	if n < _sh_prev:
		_sh_brk_t = g.t
		_sh_burst(c, r0, "sh_shard", 14)
	elif n > _sh_prev:
		_sh_chg_t = g.t
		_sh_burst(c, r0, "sh_glint", 6)
	_sh_prev = n
	var tb: float = g.t - _sh_brk_t
	var tc: float = g.t - _sh_chg_t
	if n <= 0 and g.shield_max <= 0 and tb > 0.6:
		return
	var a_dim := 1.0 if n > 0 else 0.0
	var fresh := clampf(1.0 - tc / 0.35, 0.0, 1.0)   # 刚充好一层：边缘亮一下
	match int(Bal.v("fx/shield_style", 2.0)):   # 10-31 TA 审阅 docs/208 H1 / M16（泡泡盖住本体、又是一个圈）改缺省 C 环绕光点（2）；10-28 定的 B 气泡 = 1、A 细光边 = 0
		0:
			_shield_rim(c, r0, n, fresh)
		2:
			_shield_motes(c, r0, n, fresh)
		_:
			_shield_bubble(c, r0, n, fresh)
	# 充能进度不在身上画（10-31 TA 审阅 docs/208 H1：0 层时常驻的空槽环、充能弧都是圈）：左上生命值旁的护盾菱形已经显示层数
	# 碎裂：碎掉的那一环外扩淡出 0.25 秒；之后无敌期间（0.5 秒）环位上两点微光绕行
	if tb < 0.25:
		var e := tb / 0.25
		var rb := r0 + 16.0 * e
		tb_arc(c, rb, 0.0, TAU, 4.0 * (1.0 - e) + 1.0, Color(1.4, 1.3, 1.05, 0.9 * (1.0 - e)), 40)
		if tb < 0.06:
			tb_circle(c, r0, Color(1.35, 1.15, 0.7, 0.16 * (1.0 - tb / 0.06)), 1.0, 24)
	if tb < 0.5 and g.invuln > 0.0:
		var sa := 1.0 - tb / 0.5
		tb_arc(c, r0, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, (0.18 + 0.14 * sin(g.t * 40.0)) * sa), 40)
		for q in 2:
			var a: float = g.t * 9.0 + PI * q
			var p := (c + Vector2.from_angle(a) * r0).snapped(Vector2(2, 2))
			tb_quad(p - Vector2(2, 2), p + Vector2(2, -2), p + Vector2(2, 2), p + Vector2(-2, 2), Color(1.5, 1.4, 1.1, 0.85 * sa))


## 候选 A 细光边：一道连续细边（1 美术像素），层数 = 边的亮度 + 边顶的小菱形个数
func _shield_rim(c: Vector2, r0: float, n: int, fresh: float) -> void:
	if n <= 0:
		return
	var al: float = 0.35 + 0.15 * mini(n, 3) + 0.4 * fresh
	tb_arc(c, r0 + 2.0 * fresh, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, al), 48)
	_shield_pips(c, r0, n)


## 候选 B 柔和气泡：边缘向内渐隐的淡光层 + 连续细边；层数 = 气泡厚度（每层边缘光带加宽一截）+ 小菱形
func _shield_bubble(c: Vector2, r0: float, n: int, fresh: float) -> void:
	if n <= 0:
		return
	var band: float = 6.0 + 4.0 * mini(n, 3)
	var edge := Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.16 + 0.04 * mini(n, 3) + 0.25 * fresh)
	tb_ring2(c, r0 - band, r0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.0), edge, 40)
	tb_arc(c, r0, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.45 + 0.4 * fresh), 48)
	# 左上一点高光（气泡感）
	tb_arc(c, r0 - 4.0, -PI * 0.85, -PI * 0.65, 2.0, Color(1.4, 1.35, 1.2, 0.5), 6)
	_shield_pips(c, r0, n)


## 候选 C 环绕光点：极淡连续边 + 每层一颗绕身体转的光点（带两格拖尾），层数 = 光点个数
func _shield_motes(c: Vector2, r0: float, n: int, fresh: float) -> void:
	if n <= 0:
		return
	tb_arc(c, r0, 0.0, TAU, 2.0, Color(SH_COL.r, SH_COL.g, SH_COL.b, 0.2 + 0.3 * fresh), 48)
	var k: int = mini(n, 6)
	for i in k:
		var a0: float = g.t * 1.6 + TAU * i / k
		for q in 3:
			var p := (c + Vector2.from_angle(a0 - 0.14 * q) * r0).snapped(Vector2(2, 2))
			var h: float = 3.0 - q
			var al: float = (0.95 - 0.3 * q)
			tb_quad(p - Vector2(h, h), p + Vector2(h, -h), p + Vector2(h, h), p + Vector2(-h, h), Color(SH_COL.r * 1.3, SH_COL.g * 1.25, SH_COL.b * 1.1, al))


## 层数标记：边顶的小菱形（每层一个，最多 8 个）
func _shield_pips(c: Vector2, r0: float, n: int) -> void:
	var k: int = mini(n, 8)
	for i in k:
		var p := (c + Vector2((i - (k - 1) * 0.5) * 8.0, -r0 - 6.0)).snapped(Vector2(2, 2))
		tb_quad(p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0), Color(SH_COL.r * 1.25, SH_COL.g * 1.2, SH_COL.b * 1.1, 0.9))


## 护盾碎片 / 充能颗粒：沿环一圈向外（fx_grains，docs/136；低画质 / 关颗粒时由 push 稀疏或不出）
func _sh_burst(c: Vector2, r: float, tpl: String, k: int) -> void:
	if g.optical == null or g.optical.grains == null or not g.optical.grains.on():
		return
	for i in k:
		var d := Vector2.from_angle(TAU * (i + 0.5 * (i % 2)) / k)
		g.optical.grains.push(tpl, c + d * r, d, SH_COL)


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
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + g.sprite.offset, Vector2(fw, fh)), src, dmod * Look.plain_mod(g, g.sprite.position))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
