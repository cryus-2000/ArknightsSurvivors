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
const Fxr = preload("res://scripts/render/fx_recipe.gd")
const Pxp = preload("res://scripts/render/fx_pxplane.gd")   # 转平面试验（docs/246）
const MeleeImpact = preload("res://scripts/render/melee_impact.gd")   # 近战打击感包（docs/246 §12）：画面击退   # 配方受击反应（docs/245 §5.9，fx/recipe_hitreact）：闪本人色 + 被打那只的局部打击停顿，只改画面
const Look = preload("res://scripts/render/look.gd")   # 观感预设：角色本体受光封顶（render/look ≥ 1）
const LateRead = preload("res://scripts/render/late_read.gd")   # 后期可读性第一批（docs/247，render/late_read）
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（render/declutter）
const LateRead2 = preload("res://scripts/render/late_read2.gd")   # 后期可读性第二批（docs/251：light_share / ground_ring_edge / crowd_env_dim）
const FD = preload("res://scripts/render/frame_dst.gd")   # 精灵取帧 + 落点（docs/101 B4 ②）
const GroundCrack = preload("res://scripts/render/ground_crack.gd")
const MagnetDraw = preload("res://scripts/render/magnet_draw.gd")   # 磁铁画法（docs/284 §2 A）
const EnemyAtlas = preload("res://scripts/render/enemy_atlas.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")   # 预警填充层（docs/101 B2，原 boss_ai.draw_warns）
const LAMP_READ_EXT := 1.6   # 可读灯圈：余光延到灯半径的倍数，game.gd 的灯光贴图按它生成
const TriBatch = preload("res://scripts/render/tri_batch.gd")   # 引擎同款几何的无贴图三角形批（docs/50 §13）
const FxDraw = preload("res://scripts/render/world_fx_draw.gd")   # g.fx 特效分派绘制（docs/286 §4 第三批从本文件拆出）
const AuraDraw = preload("res://scripts/render/world_aura_draw.gd")   # 巢穴 / 光环 / 灯标地面层绘制（docs/286 §4 第三批拆出）
const TellsDraw = preload("res://scripts/render/world_tells_draw.gd")   # 敌人出招前摇提示（draw_enemy_tells 一族，docs/286 §4 第三批拆出）
const ShieldDraw = preload("res://scripts/render/world_shield_draw.gd")   # 队长护盾气泡绘制（docs/286 §4 第三批拆出）
const ZoneDraw = preload("res://scripts/render/world_zone_draw.gd")   # 缩圈（溟痕带）绘制（docs/286 §4 第三批拆出）
const EbDraw = preload("res://scripts/render/world_ebullet_draw.gd")   # 敌方弹幕 / 抛射碎石 / 冲击环绘制（docs/286 §4 第三批拆出）

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
var _dark_on := false          # 灯火暗淡（docs/222）：圈外普通海嗣压暗成暗轮廓；update_visuals 每帧写，draw_enemy 读
var _dark_c := Vector2.ZERO
var _dark_r := 0.0
var _dark_k := 0.0
const DARK_MOD := Color(0.2, 0.22, 0.3)   # 圈外本体压到的颜色（描边不乘、光学发光眼点在另一层，照常亮）
var anim_name := ""
var anim_t := 0.0
## 后期画面降噪（EA 1.1，docs/37 §7）：场上特效粒子一多，友方特效整体降透明度、加色发光层变淡、辉光减弱，
## 让敌人、敌方弹幕、Boss 预警和掉落物浮出来。crowd 0–1 按「世界特效 + 干员粒子」总数平滑算出
var crowd := 0.0
var fx_dim := 1.0                 # 友方特效的透明度系数（1 → 0.45；render/declutter 的 dim_floor）
var deco_dim := 1.0               # 装饰层（火花 / 碎片 / 光点 / 拖尾）的降噪系数；late_read V3 关时 = fx_dim（docs/247）
var lr_v3 := false                # 本帧 late_read V3 生效（降噪只压装饰层）
var dcrowd := 0.0                 # 降噪用的拥挤度：max(crowd, ecrowd × declutter crowd_mix)
var mate_dim := 1.0               # 队友（非主控）特效再乘的系数（declutter mate_k；squad 绘制时按干员临时乘进 fx_dim）
## 后期特效控制（docs/293 方案，render/late_fx，缺省 0）：late_k = 0（前期）→ 1（late_fx_t0 秒起 late_fx_ramp 秒内爬满）；
## 队友整体透明度再乘 lerp(1, late_fx_mate, late_k)，队友转平面立起层也走这个系数，队友装饰颗粒按 late_fx_grains 减量；
## 队长不再被拥挤降噪压暗（late_fx_lead）；大面积填充变薄（late_fill_k，late_fx_fill）；队友发光点进辉光减量（lf_emit_k，late_fx_emit）。敌弹、预警不动
var late_k := 0.0
var lf_emit_k := 1.0              # 当前正在画的干员的发光点系数（squad._op_dim / _pxp_sorted 设；队长恒 1，_fx_order 队长最后画，阶段结束自然回 1）
var _lf_cv = null
var _sorted_leader := ""
var _sorted_dim_mates := false
var _sorted_mate_emit := 1.0
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
var _dbg_opmask: bool = Dc.opmask_any()   # 后期特效分账（--clutterdbg=nolead / nomates / noop_<id>，Dc.mute_op）
# docs/139 §8 怪物攻击圈环盘点（量测，只隐藏不改逻辑）：nowarn 地面预警（填充 + 轮廓）、notell 敌人自带危险提示、nofoefx 敌方一次性特效、
# noshock 冲击环、noaura 光环（巢涌者 / 伪人负担圈）
var _dbg_warn: bool = Dc.dbg("nowarn")
var _dbg_tell: bool = Dc.dbg("notell")
var _dbg_foefx: bool = Dc.dbg("nofoefx")
var _dbg_shock: bool = Dc.dbg("noshock")
var _dbg_aura: bool = Dc.dbg("noaura") or Dc.dbg("noring")   # noring（docs/251 V9 量测）= 巢穴光环 + 灯标 / 灯柱 / 遥乡 / 旗帜地圈
var boss_seen: Array = []        # Boss 换幕 / 倒下演出的观察表：[boss, 上次的 phase, 已演过倒下]（字典作键会因内容变化失效，按 is_same 找）
var scr_flash := 0.0              # 全屏闪光剩余秒（hud 画）：换幕洋红、Boss 倒下白
var scr_flash_max := 1.0
var scr_flash_col := Color.WHITE
var _gc_sink = null   # GroundCrack.TbSink（_init 里建）
var ecrowd := 0.0                 # 敌人密度 0–1（活着的敌人 90 → 210）：普通怪描边随之变淡
## docs/251 V10（render/crowd_env_dim，缺省 0 = 关）：怪群密集时环境（地面 / 溟痕 / 环境颗粒）压暗的系数，1 = 不压。
## env_crowd 同 ecrowd 的口径（活着的敌人数，平滑同速），起止点单设 crowd_env_from / crowd_env_span；开关关时恒 1
var env_crowd := 0.0
var env_dim := 1.0
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
var elite_mark_v2 := false
var elite_rim_col := Color(0, 0, 0, 0)
var _afast := false               # 本帧缓存路径走图集快速路径（_dc_emit）
static var _atlas_cache := {}      # 上一次拼好的图集（键：帧条名单 + 镜像 / 法线开关；贴图 instance id 也须相同）
var atlas: EnemyAtlas = null      # 普通怪 / 精英帧条图集（docs/50 §12 B，build_enemy_atlas）；null = 全走原帧条贴图
var dc_on := true                 # 敌人画法缓存（docs/50 §9.9）：balance.json fx/enemy_draw_cache（缺省 1），0 = 全走原路径（对照用）
var dc_check := false             # --dccheck：抽查缓存路径与原路径发出的贴图绘制参数，不一致报 SCRIPT ERROR（快检冒烟开着）
var dc_checked := 0               # --dccheck 实际比对的次数（BALANCE prof.dc_checked）
var _rec = null                   # --dccheck 比对时：贴图绘制只记参数、不画
## 会被降透明度的友方特效种类（敌方的 rift / bbeam、治疗十字、地面血迹不降）
const DIM_KINDS := ["explode", "burst", "rays", "ring", "impact", "bslash", "slash", "spark", "shard", "wpillar", "pillar", "beam", "tracer", "quake", "sprite", "frost", "tide_link", "frost_track"]
const DECO_KINDS := {"spark": true, "shard": true, "mote": true, "ember": true, "trail": true}   # docs/247 V3：降噪只压这些装饰件
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
	bbv2 = preload("res://scripts/render/boss_bullet_draw.gd").new(game)   # Boss 弹幕东方化第二版（docs/306 §8，render/danmaku_v2）
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
	var off: Vector2 = D.enemy_offset(e, g.t, rc_px, rc_t)   # 纯函数在 data.gd（docs/101 B1）
	if e.has("mi_at"):
		off += MeleeImpact.off(g, e)   # 近战打击感包：被打的怪画面上推开再弹回（判定位置不动）
	return off


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
	g.hurt_vignette = move_toward(g.hurt_vignette, 0.0, rd * (LateRead.k("v1_decay", 2.5) if LateRead.on("v1") else 1.5))   # docs/247 V1：红边只在大伤害时亮，退得快一点
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
	elif g.state == Game.S.PLAY and g.lamp < 30.0 and g.vfx.dark_k > 0.5:
		# 灯火暗淡（docs/222）：低沉心跳（录音，docs/205 附），比低血心跳慢、轻；低血时让给上面那套
		heart_cd -= rd
		if heart_cd <= 0.0:
			heart_cd = 1.25 if g.lamp > 0.0 else 0.95
			Sfx.play("lamp_heart", -6.0 if g.lamp > 0.0 else -3.0, 1.0, 0.0)
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
	var dk: float = g.vfx.dark_k
	if dk > 0.0:
		radius *= 1.0 + dk * 0.025 * (0.6 * sin(g.t * 7.3) + 0.4 * sin(g.t * 13.1 + 1.7))   # 暗淡：灯圈边缘轻微抖动（docs/222，纯画面）
	if g.state == Game.S.DEAD:
		radius *= 1.0 - clampf(g.state_age / Game.HudView.DEATH_LAMP_T, 0.0, 1.0)   # 倒下过渡：灯火熄灭（hud.draw_death_transition）
	var lamp_at: Vector2 = g.ppos
	if g.ult != null and g.t < float(g.ult.cam_hold_until) and g.ult.cam_hold != Vector2.INF:
		lamp_at = g.ult.cam_hold   # 终结技钉住镜头期间灯火圈也停在原地（艾丽妮穿梭斩，用户 10-31「灯火的圈停留在原地，不要跟随人」）
	g.lamp_light.position = lamp_at + Vector2(0, -20)
	g.lamp_light.texture_scale = radius * LAMP_READ_EXT / 64.0
	g.lamp_light.color = Color(1.0, 0.98, 0.94).lerp(Color(1.08, 0.94, 0.74), g.vfx.lit_k)   # 通明（≥ 70）：灯圈暖亮一档（docs/222）
	_dark_on = dk > 0.01 and g.demo_op == ""
	_dark_c = lamp_at
	_dark_r = radius
	_dark_k = dk
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
		if o.warp_t >= 0.0:
			o.warp_t = -1.0 if o.warp_t > o.WARP_OUT + o.WARP_IN else o.warp_t + dt   # 瞬回的落点淡入计时（character.warp_k）
	var want: float = 0.0 if g.demo_op != "" else clampf((nfx - Dc.p("crowd_from")) / Dc.p("crowd_span"), 0.0, 1.0)
	crowd = move_toward(crowd, want, rd * (3.0 if want > crowd else 0.8))
	var ne := 0
	for e in g.enemies:
		if not e.dead:
			ne += 1
	var ewant: float = 0.0 if g.demo_op != "" else clampf((ne - 90.0) / 120.0, 0.0, 1.0)
	ecrowd = move_toward(ecrowd, ewant, rd * 0.8)
	_env_dim_step(ne, rd)
	# 后期降噪预设（render/declutter，render/declutter.gd）：敌人多也算拥挤（crowd_mix，缺省 0 = 只看特效数）
	dcrowd = maxf(crowd, ecrowd * Dc.p("crowd_mix"))
	fx_dim = lerpf(1.0, Dc.p("dim_floor"), dcrowd)
	mate_dim = Dc.at("mate_k", dcrowd)
	lead_dim = Dc.at("lead_k", dcrowd)
	late_k = _late_fx_k()
	lf_emit_k = 1.0
	if late_k > 0.0:
		mate_dim *= lerpf(1.0, late_fx_v("mate", 0.55), late_k)
		if late_fx_v("lead", 1.0) > 0.0:   # 队长优先清楚：后期拥挤降噪不再压队长（declutter 3 档 lead_k 0.8）
			lead_dim = lerpf(lead_dim, 1.0, late_k)
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
	# 后期可读性 V3（docs/247，render/late_read）：降噪只压装饰层。deco_dim 留原来的降噪系数给火花 / 碎片 / 光点 / 拖尾，
	# fx_dim（干员脚本、核心帧条读的那个）恒为 1，队友 / 队长的整体透明度系数也不再压
	lr_v3 = LateRead.on("v3")
	if lr_v3:
		deco_dim = fx_dim
		fx_dim = 1.0
		mate_dim = 1.0
		lead_dim = 1.0
	else:
		deco_dim = fx_dim
	if _dbg_friend:
		fx_dim = 0.0   # --clutterdbg=nofriend：友方特效全透明（代码照跑、随机数照抽）
		deco_dim = 0.0
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
	if LateRead.on("v7"):
		flash_a = minf(flash_a, LateRead.k("v7_a", 0.5))   # docs/247 V7：普通怪受击最多 50% 混白（不再整只刷白），精英 / Boss 不走 flash_a，照旧整只闪
	spark_left = int(Dc.p("spark_budget")) if Dc.p("spark_budget") > 0.0 else 1 << 30
	elite_rim = clampf(Bal.v("render/elite_rim", 0.55), 0.0, 1.0)
	elite_mark_v2 = Bal.v("render/elite_mark_v2", 0.0) > 0.0
	var rg: float = Bal.v("render/elite_rim_gain", 2.2)
	elite_rim_col = Color(ELITE_RIM_RGB.r * rg, ELITE_RIM_RGB.g * rg, ELITE_RIM_RGB.b * rg, elite_rim)
	g.fx_add.modulate.a = 0.0 if _dbg_friend else (1.0 if lr_v3 else lerpf(1.0, Dc.p("add_floor"), dcrowd))   # V3：加色层是干员核心光，不压
	if g.post != null and "crowd" in g.post:
		g.post.crowd = dcrowd
		g.post.bloom_cut = Dc.p("bloom_cut") * (LateRead.k("v3_bloom", 0.0) if lr_v3 else 1.0)   # V3：全屏辉光分不出层，拥挤削减改由装饰层自己变淡承担


## docs/251 V10：怪群密集时压暗环境。系数 = 1 − crowd_env_k（缺省 0.18）× env_crowd，env_crowd 按活敌数 crowd_env_from → +crowd_env_span 线性到 1、
## 平滑同 ecrowd；只给地面（draw_world 地面之后一层黑纱）、溟痕本体（map.draw_mire）、环境颗粒（光学孢子 / 溟痕光尘 / 浮游雪）用。
## 我方特效、小队、敌人、敌弹、预警、掉落都在黑纱之上或不读它。图鉴演示不压。只读状态
func _env_dim_step(ne: int, rd: float) -> void:
	if not LateRead2.on("crowd_env_dim") or g.demo_op != "":
		env_crowd = 0.0
		env_dim = 1.0
		return
	var w: float = clampf((float(ne) - LateRead2.k("crowd_env_from", 20.0)) / maxf(1.0, LateRead2.k("crowd_env_span", 50.0)), 0.0, 1.0)
	env_crowd = move_toward(env_crowd, w, rd * 0.8)
	env_dim = 1.0 - clampf(LateRead2.k("crowd_env_k", 0.18), 0.0, 0.5) * env_crowd


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
	bbv2.world_atlases.clear()
	_pk("")
	# 敌方顶层（docs/226 §1，render/foe_top 缺省 1）：敌弹、Boss 弹拖尾 / 落地、预警填充与轮廓、主控标记改由 g.foe_top 在友方加色层之上画；
	# 0 = 照旧全画在世界画布上（同一套函数、同一顺序）
	if _lr_ab > 0 and Engine.get_process_frames() % _lr_ab == 0:
		_ft_force_off = not _ft_force_off   # --lrab=N：每 N 帧轮换敌方顶层 + 队长剪影开 / 关（同局量帧时净差，docs/226 §4）
	_ft_on = Bal.v("render/foe_top", 1.0) > 0.0 and g.foe_top != null and not _ft_force_off
	if not _wd_read:
		_wd_args()
	if wd_ab > 0 and Engine.get_process_frames() % wd_ab == 0:
		wd_mask = 0 if wd_mask != 0 else wd_ab_bits   # --wdab=N[:掩码]：新旧写法同局轮换（docs/319 §22）
	bbv2.frame(bulfx)   # 先注册出现 / 消失钩子、推进粒子时钟（render/boss_bullet_draw.gd）
	bulfx.frame()   # 子弹出现 / 消失（render/bullet_fx.gd）：先认出本帧新弹 / 消失的弹，下面各遍画弹时乘出现缩放
	scr_flash = maxf(0.0, scr_flash - g.get_process_delta_time())
	if _dbg_ground:
		g.wcv.draw_rect(view_rect(0.0), Color(0.16, 0.17, 0.2))   # --clutterdbg=noground（量测）：地面 / 地形道具换成平涂底色
	else:
		g.map.draw_ground(g.view_size())
		# 后期降噪（render/declutter ground_veil，缺省 0 = 不画）：拥挤时地面盖一层地面平均色的薄纱，压地砖 / 小道具纹理的对比，
		# 让敌人、弹幕和预警从地上浮出来；在溟痕 / 地面预警 / 掉落之下，灯火照常照在上面
		var gv: float = Dc.p("ground_veil") * dcrowd
		if gv > 0.002:
			var gm: Color = g.map.ground_mean()
			g.wcv.draw_rect(view_rect(8.0), Color(gm.r, gm.g, gm.b, gv))
		if env_dim < 0.999:
			g.wcv.draw_rect(view_rect(8.0), Color(0.0, 0.0, 0.0, 1.0 - env_dim))   # docs/251 V10：地面 / 地形道具压暗（终结技地面层、干员地面特效、溟痕之后的一切都在这层之上）
	if g.ult != null:
		g.ult.draw_world_back(self)   # 终结技地面层帧条（刀痕残痕 / 领域 / 裂纹 / 海嗣水纹）
	g.squad.draw_ground_fx()   # 干员紧贴地砖的大片地面特效（docs/61 §5.6 layer = ground）：压在溟痕 / 地面预警之下
	_pk("ground")
	_draw_mires()
	var ground_count := g.fx.size()
	_draw_ground_sprites()
	_pk("mire")
	tell_fill = Dc.p("tell_fill_k")
	tell_edge = Dc.p("tell_edge_k")
	_draw_warns_auras()
	if not _dbg_foe:
		# 预警绘制若追加了新特效，本帧仍能看到它。
		_draw_ground_foe_fx(_ground_foe if g.fx.size() == ground_count else g.fx)
	_ground_foe.clear()
	_pk("warns_auras")
	if not _dbg_gem:   # --clutterdbg=nogem（量测）
		_draw_pickups()
	_pk("gems")
	var evr: Rect2 = view_rect(ENTITY_MARGIN)   # 屏幕外的敌人不画影子、不进排序（性能，协调人 9/30；绘制只改画面，不影响模拟）
	_build_vis(evr)
	_draw_squad_pools()
	_draw_shadows(evr)
	_pk("shadows")
	if g.state == Game.S.OPENING:
		g.intro_screen.draw_transport_shadow()
	_draw_sorted_entities(evr)
	if g.state == Game.S.OPENING:
		g.intro_screen.draw_transport()   # 岩柱、海草和舱口下方的人物都在飞行器之下
	_pk("sorted_entities")
	if not _dbg_friend:
		g.rfx.draw_upper()   # 放置物第二版（render/placeable_v2，docs/246）：地雷 / 轰隆隆 / 防暴桩本体与爆炸画在敌人之上
	_draw_overlays_shield_drones()
	_pk("shield_drones")
	_draw_placed_top()
	_draw_bullets()
	_pk("bullets")
	FxDraw._draw_fx(self)
	BossBeam.draw_top(g)   # 主控寒冷条（骑士在场时）
	_pk("fx")
	if not _ft_on:
		_draw_foe_upper()
	ZoneDraw.draw_zone(self)
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


var _ground_foe: Array = []   # 同一次世界绘制内，预警之后要画的冰面和地裂，保留源顺序

## 地面层帧条特效（vfx.fx_sprite ground=true，kind "gsprite"）：溟痕之上、预警 / 实体之下——喷吐者酸团落点溅射、囊海爬行者爆后残留（docs/96 第 1 批）。
## 敌方特效不降噪（docs/48 ③），按已播时间取帧，同 _draw_fx 的 "sprite"
func _draw_ground_sprites() -> void:
	g.draw_off = Vector2.ZERO
	for f in g.fx:
		var kind: String = f.kind
		if kind != "gsprite":
			if kind == "ice_sheet" or (kind == "gcrack" and f.get("ground", false)):
				_ground_foe.append(f)
			continue
		var spec: Array = Game.V6_FRAMES[f.name]
		var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
		g.vfx.spr_rot(f.name, fr, f.pos, f.ang, g.vfx.int_scale(f.scale), f.get("col", Color.WHITE), f.get("anchor", Vector2(-1, -1)), f.get("flip", false))


## 地面层敌方特效（ground 标记，用户 10-24：奠基者踏地「浮在最上面」）：小怪踏地的地裂与冲击环画在地面预警之上、单位之下，
## 不盖住干员和其他单位。纯画面
func _draw_ground_foe_fx(candidates: Array) -> void:
	for f in candidates:
		if f.kind == "ice_sheet" and f.life > 0.0:
			_draw_ice_sheet(f)
	for f in candidates:
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
	g.wcv.draw_polyline(body, Color(0.7, 0.88, 1.0, 0.24 * a), w)
	g.wcv.draw_polyline(hi, Color(0.95, 1.0, 1.0, 0.16 * a), 6.0)
	g.wcv.draw_polyline(l, Color(0.88, 0.97, 1.0, 0.6 * a), 2.0)
	g.wcv.draw_polyline(r, Color(0.6, 0.8, 0.95, 0.45 * a), 2.0)
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
			g.wcv.draw_line(at - ca * 8.0, at + ca * 8.0, Color(0.55, 0.78, 0.95, 0.55 * a), 2.0)
			g.wcv.draw_line(at + ca * 8.0, at + ca * 8.0 + d2 * 6.0, Color(0.55, 0.78, 0.95, 0.4 * a), 2.0)
			if (h >> 3) % 3 == 0 and fmod(g.t * 1.5 + float(h % 7) * 0.3, 2.0) < 0.35:
				g.wcv.draw_rect(Rect2(((at + n2 * 10.0) * 0.5).floor() * 2.0, Vector2(2, 2)), Color(1.0, 1.0, 1.0, 0.9 * a))


## 世界画布上敌弹 / 预警轮廓 / 主控标记那一段（原 draw_world 里 _draw_fx 之后的顺序）；敌方顶层开着时由 draw_top 在 foe_top 上画
func _draw_foe_upper() -> void:
	if not _dbg_foe:   # --clutterdbg=nofoe：敌方弹幕 / 预警整层不画（量测）
		bulfx.draw_grounds()   # Boss 落地迸散（docs/206 §4）
		bulfx.draw_trails()   # Boss 弹拖尾光粒（压在弹体之下，docs/206 §2）
		EbDraw._draw_ebullets_lobs_shocks(self)
	bulfx.draw_top()   # 新弹亮芯闪 + 消失残影（压在弹体之上）
	_draw_hit_dot()
	_pk("ebullets_lobs_shocks")
	_draw_tells_outlines()
	_pk("tells_outlines")


## Boss 招式预警地面填充（render/telegraph_draw / 伊莎玛拉 / 最终 Boss / 塑路者接潮组）
func _draw_warn_fills() -> void:
	if not _dbg_foe and not _dbg_warn:
		TeleDraw.draw_fills(g)
		IsharTell.draw(g)   # 伊莎玛拉预警（docs/170）
		FinalAttackDraw.draw(g)
		MidCardDraw.warns(g)


## 敌方顶层（g.foe_top 的绘制回调，排在世界与友方加色层 fx_add 之后）：预警填充 → 敌弹 → 预警轮廓 / 主控标记（docs/226 §1）。
## 同一套绘制函数，画布临时改指到 foe_top（g.wcv / 干员合批画布），画完改回；只画不改状态
var _ft_on := false
var _ft_force_off := false   # 量测 / 对照用
var _lr_ab: int = _lrab_arg()
## 世界绘制优化（docs/319 §22）的新旧对照：--wdab=N 每 N 帧把新写法轮换成旧写法（同局量净差，性能桶 /wd0 = 旧、/wd1 = 新），
## --wdab=N:<掩码> 只轮换掩码里的项；--wdold=<掩码> 固定走旧写法（截图逐像素对照）。位：1 Boss 弹第二版粒子，4 溟痕格，16 成长节点提示环合批、32 铃兰光域常态快速版（docs/332 §3；--wdab 缺省掩码 15 不含这两位，要写 --wdab=N:48）。正常游戏都是 0。
## --noatlas：桌面也不拼敌人图集，走手机网页的原帧条路径（截图对照 / 量帧用）
var wd_ab := 0
var wd_ab_bits := 15
var wd_mask := 0      # 本帧走旧写法的项（位同上）
var wd_noatlas := false
var _wd_read := false
func _wd_args() -> void:
	_wd_read = true
	var cfg = g.get_node_or_null("/root/Cfg")
	for a in (cfg.dev_args() if cfg != null else PackedStringArray()):
		if a.begins_with("--wdab="):
			var sp: PackedStringArray = a.substr(7).split(":")
			wd_ab = int(sp[0])
			wd_ab_bits = int(sp[1]) if sp.size() > 1 else 15
		elif a.begins_with("--wdold="):
			wd_mask = int(a.substr(8))
		elif a == "--noatlas":
			wd_noatlas = true


## 某项本帧走新写法吗（位见 wd_ab）
func wd_new(bit: int) -> bool:
	return (wd_mask & bit) == 0


static func _lrab_arg() -> int:
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a.begins_with("--lrab="):
			return int(a.substr(7))
	return 0
func draw_top() -> void:
	bbv2.top_atlases.clear()
	if not _ft_on:
		return
	var sq = g.squad
	var bc = sq.cv if sq != null else null
	var old_bc = bc.g if bc != null else null
	g.wcv = g.foe_top
	if bc != null:
		bc.g = g.foe_top
	g.draw_off = Vector2.ZERO
	_pk("")
	_draw_warn_fills()
	_pk("ft_fills")
	_draw_squad_over_warns()
	_draw_leader_sil()
	_pk("ft_sil")
	_draw_foe_upper()
	_pk("foe_top")
	g.wcv = g
	if bc != null:
		bc.g = old_bc


## 队长被友方特效盖住时的剪影（docs/226 §2，render/lead_sil 缺省 1）：敌方顶层这一遍里、预警填充之后、敌弹之前，
## 把队长本体不透明地再画一遍并描 1 格深色半透明边（剪影错开上下左右各 2 世界像素；11-03 前是暖白边 + 半透明本体，整个人发白）。只在「被盖」时出现：
## 覆盖分（见 _leader_cover）过 lead_sil_s0 起描边渐显、lead_sil_s1 全显，升降各约 0.15 秒；seed 13 开局约 4% 的时间、10 分钟后约 18% 的时间在画。
## 不读像素、只画不改状态；手机同样生效
var _sil_a := 0.0
var _sil_score := 0.0
## 覆盖分只算「真盖在身上」的大件（11-03 修：原来火花 / 气场光点 / 队长自己的标记环都计分，开局就常亮）：
## 世界帧条半径 ≥ lead_sil_min_r（18）且圆盘压到身体（中心距 < 半径 × 0.8 + 14）才计，按半径 / 24 计 0.75–4 分；
## 干员粒子只计非装饰件（pfx_cappable 之外，如技能帧条），每个 0.5
const SIL_SKIP := {"spark": true, "mote": true, "shard": true, "line": true, "flame": true, "lead_mark": true, "marc": true}
func _leader_cover() -> float:
	var c: Vector2 = g.ppos + Vector2(0, -20)
	var min_r: float = Bal.v("render/lead_sil_min_r", 18.0)
	var sc := 0.0
	for f in g.fx:
		var fp = f.get("pos")   # 先按距离筛（后期 g.fx 上百条，种类判断放后面）
		if not (fp is Vector2) or (fp as Vector2).distance_squared_to(c) > 40000.0:
			continue
		if SIL_SKIP.has(f.kind) or f.get("enemy", false) or FOE_KINDS.has(f.kind) or AMB_KINDS.has(f.kind) or f.get("delay", 0.0) > f.max - f.life:
			continue
		var fr: float = float(f.get("r", 0.0)) + float(f.get("scale", 0.0)) * 12.0
		if fr < min_r or (fp as Vector2).distance_to(c) >= fr * 0.8 + 14.0:
			continue
		var w: float = clampf(fr / 24.0, 0.75, 4.0)
		sc += w
	if g.squad != null:
		for o in g.squad.ops:
			for f in o.pfx:
				var pp = f.get("pos")
				if pp is Vector2 and (pp as Vector2).distance_squared_to(c) <= 900.0 and not f.get("floor", false) and not o.pfx_cappable(f):
					sc += 0.5
	return sc


func _draw_leader_sil() -> void:
	if Bal.v("render/lead_sil", 1.0) <= 0.0 or _ft_force_off or g.squad == null or _dbg_friend or g.state == g.S.DEAD:
		_sil_a = 0.0
		return
	var o = g.squad.leader()
	if o == null or o.pos == Vector2.INF or o.cmd_down > 0.0 or (o.arriving() and o.arrive_t < o.ARRIVE_WAIT):
		return
	if Engine.get_process_frames() % 3 == 0:
		_sil_score = _leader_cover()   # 每 3 帧算一次覆盖分（渐显本身有 0.15 秒缓冲）
		if LateRead.mode("s2", 2.0) == 1.0 and _in_warn(o.pos):
			_sil_score = maxf(_sil_score, Bal.v("render/lead_sil_s1", 10.0))   # docs/247 S2 方案 1：被敌方预警盖住也画剪影
	var s0: float = Bal.v("render/lead_sil_s0", 4.0)
	var s1: float = Bal.v("render/lead_sil_s1", 10.0)
	var want: float = clampf((_sil_score - s0) / maxf(0.01, s1 - s0), 0.0, 1.0)
	_sil_a = move_toward(_sil_a, want, g.get_process_delta_time() / 0.15)
	if _sil_a < 0.02:
		return
	var st: Dictionary = o.anim_state()
	if st.is_empty() or st.get("tex") == null:
		return
	var p: Vector2 = o.pos + Vector2(o.foot_dx(st), 0) + Vector2(0, o.arrive_dy())
	var fo: float = o.foot_off(st.tex, st.get("kind", ""))
	var wt: Texture2D = A.white_of(st.tex)
	# 11-03 修（用户截图「人物身上冒光」）：原来暖白描边 0.9 + 本体按 _sil_a 半透明重画，白剪影从半透明本体里透出来，整个人发白。
	# 现在描边改深色半透明、只描边随 _sil_a 渐显；本体一旦出现就不透明重画（只是把盖在身上的友方特效压到下面，本体与原画同一帧同一色）
	var ec: Color = Color(0.02, 0.03, 0.07, Bal.v("render/lead_sil_edge_a", 0.6) * _sil_a)
	for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_sprite_at(p + d, st.flip, ec, st.frame, wt, st.hf, fo)
	draw_sprite_at(p, st.flip, g.sprite.modulate, st.frame, st.tex, st.hf, fo)


## docs/247 S2：点 p（脚底）是否落在一个还没结算的敌方预警里（圆 / 扇形 / 直线，含 Boss 招式；判定同 classify_tells，余量 12）
func _in_warn(p: Vector2) -> bool:
	var gy: float = ground_y()
	var lr := 12.0
	for w in g.warns:
		if w.done or int(w.get("style", 1)) == 0:
			continue
		match str(w.get("shape", "")):
			"cone":
				var d: Vector2 = p - w.pos
				var dist: float = d.length()
				if dist <= float(w.r) + lr and (dist <= lr or absf(angle_difference(d.angle(), float(w.ang))) <= float(w.half) + asin(minf(1.0, lr / dist))):
					return true
			"line":
				var b2: Vector2 = w.pos + Vector2.from_angle(float(w.ang)) * float(w.len)
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, w.pos, b2)) < float(w.wid) + lr:
					return true
			"circle":
				var dc: Vector2 = p - w.pos
				if Vector2(dc.x, dc.y / maxf(gy, 0.01)).length() < float(w.r) + lr:
					return true
	return false


## docs/247 S2 方案 2（render/late_read_s2 = 2，缺省）：站在敌方预警里的干员，在敌方顶层的预警填充之后、敌弹与预警轮廓之前再画一遍本体
## 预警填充不再罩住人；敌弹、预警轮廓照样压在最上面。只画不改状态
func _draw_squad_over_warns() -> void:
	if LateRead.mode("s2", 2.0) != 2.0 or g.squad == null or g.state == g.S.DEAD or g.warns.is_empty():
		return
	for o in g.squad.ops:
		if o.pos == Vector2.INF or o.cmd_down > 0.0 or o.arriving() or not _in_warn(o.pos):
			continue
		o.draw_body()
		o._cv_flush()


## docs/247 S1：脚底光池（地面层，影子之前）：队长一圈暖白光照地，队员小一号、淡一半。三阶硬边（同 optical_steps 防油腻），
## 只往下照地、不往外扩光环；颜色暖白偏琥珀，避开结晶暖金（更白、更淡）
func _draw_squad_pools() -> void:
	if not LateRead.on("s1") or g.squad == null or g.state == g.S.DEAD:
		return
	var pc := Color(1.0, 0.9, 0.74)
	var a0: float = LateRead.k("s1_pool_a", 0.13)
	for o in g.squad.ops:
		if o.pos == Vector2.INF or o.cmd_down > 0.0 or (o.arriving() and o.arrive_t < o.ARRIVE_WAIT):
			continue
		var r: float = LateRead.k("s1_pool_r", 40.0) * (1.0 if o.is_leader else 0.65)
		var a: float = a0 * (1.0 if o.is_leader else 0.5)
		var c: Vector2 = ((o.pos + Vector2(0, 2)) / 2.0).round() * 2.0
		g.wcv.draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
		for q in 3:
			var k: float = 1.0 - float(q) / 3.0
			g.wcv.draw_circle(Vector2.ZERO, r * k, Color(pc.r, pc.g, pc.b, a * (0.55 + 0.45 * float(q) / 2.0)))
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## docs/247 S3：我方放置物在敌人之上画（地雷 / 轰隆隆走 relic_fx.draw_placed_top；干员地面池 hw.pools —— 逻各斯铭文、艾雅法拉熔池等 ——
## 补一圈本人代表色 1 格描边 + 呼吸，半径不小于 s3_rmin，最后 0.3 秒淡出）。--clutterdbg=nofriend 时不画
func _draw_placed_top() -> void:
	if _dbg_friend or not LateRead.on("s3"):
		return
	g.rfx.draw_placed_top(g.wcv)
	var rmin: float = LateRead.k("s3_rmin", 14.0)
	for o in g.squad.ops:
		var h = o.get("hw")
		if not (h is Dictionary) or not h.has("pools"):
			continue
		var c: Color = squad_ol_col(o.col())
		if c.h < 0.06 or c.h > 0.9:
			c = LateRead.ALLY_COL   # 红只留给危险：红系代表色的放置物描边改用我方青白
		var rmax: float = LateRead.k("s3_rim_max", 48.0)
		for l in h.pools:
			var al: float = clampf(float(l.t) / 0.3, 0.0, 1.0)
			if al <= 0.0 or float(l.r) >= rmax:
				continue   # 大圈（墓志铭书写圈、大熔池）本身已有完整边，不再加描边，免得画面脏
			LateRead.placed_rim(g.wcv, l.pos + Vector2(0, 4), maxf(float(l.r), rmin), Color(c.r, c.g, c.b, 1.0), g.t, fmod(absf(l.pos.x) * 0.011, 1.0), 0.5, 0.55 * al)


## 预警分类 → Boss 招式预警填充（render/telegraph_draw；敌方顶层开着时挪到 draw_top）→ 巢涌者光环 → 灯标 → 藏品特效 → 商人
func _draw_warns_auras() -> void:
	classify_tells()   # 先判哪些预警会打到主控（可读性 1.1.1）：地面填充 / 轮廓 / 冲刺线都读这个结果
	if not _ft_on:
		_draw_warn_fills()
	if not _dbg_aura:
		AuraDraw.draw_nest_auras(self)
	AuraDraw.draw_beacons(self)
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
	var gem_v2: bool = Bal.vi("render/gem_v2", 0) > 0
	var merge_n: int = Bal.vi("render/gem_cap_merge_n", 30) if Bal.vi("render/gem_cap", 0) > 0 else Bal.vi("render/gem_merge_n", GEM_MERGE_N)
	var crowd_gems: bool = n_all > merge_n
	var many: bool = n_all > 60
	var pp: Vector2 = g.ppos
	var tgt: Vector2 = pp + Vector2(0, -12)
	var t: float = g.t
	var bob_t: float = t * 4.0
	var tw_t: float = t * 6.0
	var cells := {}
	var cell_values := {}
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
	# 结晶两档亮度（11-04 用户「结晶得发光，和地面要有足够的区分度和对比色」）：
	# 静止（没被吸起、离队长超过 render/gem_near_r）——常亮，只画一圈紧贴结晶的小光晕（不铺大片光雾），十字闪光只偶尔闪
	# （render/gem_spark_rest 闪的比例）；靠近队长或被吸起——照旧两圈光晕 + 闪光，颜色再亮一档（render/gem_near_k）。
	# 不再按「远处安静」压暗。render/gem_rest = 0 回到旧画法
	var rest_on: bool = Bal.vi("render/gem_rest", 1) > 0
	var near_r: float = Bal.v("render/gem_near_r", 110.0)
	var near2: float = near_r * near_r
	var near_k: float = Bal.v("render/gem_near_k", 1.15)
	var spark_rest: float = Bal.v("render/gem_spark_rest", 0.12)
	if gem_v2:
		rest_on = true
		near_k = Bal.v("render/gem_v2_near_k", 1.12)
		core = Color(-1, 0, 0) # Emission follows each value tier and its resting brightness.
	if rest_on:
		many = false   # 不再走「远处安静」的压暗
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
				if gem_v2:
					cell_values[ck] = float(cell_values.get(ck, 0.0)) + float(g_item.val)
				continue
			if gz > 1.0:
				_pq_air_shadow(pos, gz)
			var quiet: bool = many and far
			var rest: bool = rest_on and not mag and gz <= 1.0 and pos.distance_squared_to(pp) > near2
			if gem_v2:
				lit_s = _gem_v2_color(float(g_item.val), rest)
				lit_b = lit_s
				lit_m = lit_s * near_k
				lit_m.a = 1.0
				cy = lit_s
				pu = lit_s
			var tw: float = 0.75 + 0.25 * sin(tw_t + g_item.seed)
			var gp: Vector2 = pos + Vector2(0, (sin(bob_t + pos.x) * 2.0 if gz <= 1.0 else 0.0) - gz)
			if mag:
				var gc: Color = pu if big else cy
				var dv: Vector2 = (gp - tgt).normalized()
				var tl: float = 10.0 + 24.0 * minf(1.0, g_item.mag_t * 2.0)
				_gt_line(gp, gp + dv * tl * GEM_VIS, Color(gc.r * 1.8, gc.g * 1.8, gc.b * 1.8, 0.55), (5.0 if big else 3.0) * GEM_VIS)
				_gt_line(gp, gp + dv * tl * 0.6 * GEM_VIS, Color(2.5, 2.5, 2.5, 0.7), 1.5 * GEM_VIS)
			if gem_v2:
				pass # Faceted sprite + its emission are enough; no circular glow behind new gems.
			elif rest:
				_gt_circle(gp, (7.0 if big else 5.0) * GEM_VIS, glow_b1 if big else glow_s1, _gt_fan14, _gt_c42)   # 静止：一圈紧贴的小光晕
			elif not quiet:
				_gt_circle(gp, (13.0 if big else 9.0) * tw * GEM_VIS, glow_b0 if big else glow_s0, _gt_fan14, _gt_c42)
				_gt_circle(gp, (7.0 if big else 4.5) * tw * GEM_VIS, glow_b1 if big else glow_s1, _gt_fan14, _gt_c42)
			_gt_circle(gp + Vector2(0, 1), (6.5 if big else 4.5) * GEM_VIS, dark, _gt_fan10, _gt_c30)
			var gcol: Color = quiet_col if quiet else (lit_b if big else lit_s)
			if mag and lit_m.r >= 0.0:
				gcol = lit_m.lerp(lit_b, 0.35) if big else lit_m
			elif rest_on and not rest:
				gcol = Color(gcol.r * near_k, gcol.g * near_k, gcol.b * near_k, gcol.a)   # 靠近队长：再亮一档
			if big:
				big_p.append(gp)
				big_c.append(gcol)
			else:
				small_p.append(gp)
				small_c.append(gcol)
			if not quiet and (not rest or (not gem_v2 and fposmod(g_item.seed * 0.618, 1.0) < spark_rest)):
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
	var mc_s := PackedColorArray()
	var mc_b := PackedColorArray()
	for ck in cells:
		var cp: Vector2 = (Vector2(ck) + Vector2(0.5, 0.5)) * GEM_CELL
		if cells[ck] >= 3:
			mp_b.append(cp)
			if gem_v2:
				mc_b.append(_gem_v2_color(float(cell_values[ck]), true))
		else:
			mp_s.append(cp)
			if gem_v2:
				mc_s.append(_gem_v2_color(float(cell_values[ck]), true))
	var qc := PackedColorArray()
	qc.resize(maxi(mp_s.size(), mp_b.size()))
	qc.fill(lit_s if rest_on else quiet_col)
	_gem_sprites("gem_small", Game.PX, mp_s, mc_s if gem_v2 else qc)
	_gem_sprites("gem_big", Game.PX, mp_b, mc_b if gem_v2 else qc)


func _gem_v2_color(value: float, rest: bool) -> Color:
	var levels: Array = Bal.sec("render").get("gem_v2_values", [2, 5, 20])
	var tier := 0
	for threshold in levels:
		if value >= float(threshold):
			tier += 1
	# Multipliers for the existing warm-white facets; no additional texture or halo.
	var color: Color = [Color(0.32, 0.92, 0.54), Color(0.58, 1.04, 0.48), Color(0.78, 1.12, 0.72), Color(1.16, 1.08, 0.90)][mini(tier, 3)]
	if rest:
		color *= Bal.v("render/gem_v2_rest_k", 0.82)
		color.a = 1.0
	return color


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
				g.wcv.draw_texture_rect_region(tx, it[1], it[2])
	_pq_spr.clear()
	_pq_rects.clear()


## 同 _gem_air_shadow
func _pq_air_shadow(pos: Vector2, gz: float) -> void:
	var r: float = 7.0 * (1.0 - clampf(gz / 80.0, 0.0, 0.6))
	var c: Vector2 = pos + Vector2(0, 8)
	_pq_guard(Rect2(c.x - r - 1.0, c.y - r * 0.45 - 1.0, r * 2.0 + 2.0, r * 0.9 + 2.0))
	_pb.circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35), Transform2D(0.0, Vector2(1.0, 0.45), 0.0, c))


## 同 vfx.spr(name, 1, 0, pos)（单帧、锚点居中、取整，含 g.draw_off）
func _pq_sprite(name: String, pos: Vector2, sc := 1.0) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null:
		return
	pos += g.draw_off
	var fw: int = tx.get_width()
	var fh: int = tx.get_height()
	var size := Vector2(fw, fh) * Game.PX * sc
	var dst := FD.dst(pos, size, Vector2(0.5, 0.5))
	_pq_guard(dst)
	_pq_spr.append([tx, dst, Rect2(0, 0, fw, fh)])
	_pq_rects.append(dst)


## 宝箱显示倍率（11-09 用户「宝箱本体画大一点」）：只改画面，拾取判定不读它
const CHEST_VIS := 1.75

## 特殊掉落与空中的源石锭 / 灯油（_draw_pickups_fast 的「其他掉落」分支，画法同旧写法）
func _pq_item(g_item: Dictionary, pos: Vector2, gz: float, kind: String, t: float) -> void:
	if gz > 1.0:
		_pq_air_shadow(pos, gz)
	if kind == "magnet" and MagnetDraw.on():
		MagnetDraw.draw(self, g_item, pos, gz, t, Game.PX)   # 磁铁双色马蹄 + 铁屑 + 像素脉冲（docs/284 §2 A，render/magnet_v2）
		return
	if g_item.special:
		var ic := g.pickups.item_col(kind)
		var age: float = g_item.age
		if age < 0.9:
			var ba := (1.0 - age / 0.9) * 0.55
			_pq_guard(Rect2(pos + Vector2(-6, -141), Vector2(12, 142)))
			_pb.rect(Rect2(pos + Vector2(-5, -140), Vector2(10, 140)), Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, ba * 0.5))
			_pb.rect(Rect2(pos + Vector2(-2, -140), Vector2(4, 140)), Color(2.5, 2.5, 2.5, ba))
		if kind == "chest" and gz <= 1.0:
			# 11-09 用户「精英宝箱提示要更明显，手机上也要一眼看到」：落地后一直有金色地圈脉动 + 细光柱（原来只有落地 0.9 秒的光柱）
			var cp := 0.5 + 0.5 * sin(t * 4.0)
			var gr: float = 30.0 + 6.0 * cp
			_pq_guard(Rect2(pos + Vector2(-gr - 4.0, -96), Vector2(gr * 2.0 + 8.0, 96.0 + gr * 0.5 + 4.0)))
			_pb.rect(Rect2(pos + Vector2(-3, -92), Vector2(6, 92)), Color(ic.r * 1.6, ic.g * 1.6, ic.b * 1.6, 0.16 + 0.12 * cp))
			_pb.rect(Rect2(pos + Vector2(-1, -92), Vector2(2, 92)), Color(2.0, 2.0, 1.8, 0.22 + 0.16 * cp))
			_pb.circle(pos + Vector2(0, 2), gr, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.10 + 0.06 * cp))
			_pb.arc(pos + Vector2(0, 2), gr, 0.0, TAU, 28, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.55 + 0.3 * cp), 2.0)
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
			_pq_sprite("chest", pos + Vector2(0, -6.0 * (CHEST_VIS - 1.0)), CHEST_VIS)
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
	# 7 暖金尖晶（11-04 用户「结晶得发光，和地面要有足够的区分度和对比色」）：配淡金白尖晶贴图，贴图自带色阶，调色只轻微提亮；
	# 地面深蓝 / 青绿，结晶走暖色（淡金到琥珀），亮面近白，光晕暖金——和青色敌弹、薄荷色地面晶石拉开
	[Color(1.08, 1.04, 0.96), Color(1.16, 1.08, 0.9), Color(1.4, 1.32, 1.12), Color(0.95, 0.9, 0.8),
		Color(1.0, 0.8, 0.42), Color(1.0, 0.7, 0.28), Color(1.7, 1.55, 1.2)],
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
		g.wcv.draw_texture_rect_region(tx, dst, src, cs[i])
		if etx != null and not (core.r >= 0.0 and core.a <= 0.0):   # core 全透明 = 不进发光层（静止结晶）
			g.glow_tex_next.append([etx, dst, src, cs[i] if core.r < 0.0 else core])


## Boss 登场聚光、博士 / 敌人 / 干员 / 骑士的影子、干员脚下层；evr：ENTITY_MARGIN 视野矩形（排序层共用）
func _draw_shadows(evr: Rect2) -> void:
	g.boss_intro.draw_world()   # Boss 登场：脚下聚光圈 + 扩散环（合批；没有登场时直接返回）
	g.vfx.spr("shadow", 1, 0, g.doc_pos + Vector2(0, 6), Game.PX * 1.3)
	g.squad.draw_auras()
	var stx: Texture2D = g.tex.get("shadow")
	if stx != null and not _dbg_enemy:
		var ens: Array = _vis_ent if _vis_on else g.enemies
		var nsh: bool = g.has_meta("boss_decoys")   # 只有真身有影子
		var dims := stx.get_size()
		var src := Rect2(Vector2.ZERO, dims)
		var doff: Vector2 = g.draw_off
		for e in ens:
			var ep: Vector2 = e.pos
			if (not _vis_on and not evr.has_point(ep)) or (nsh and e.has("no_shadow")):
				continue
			var er: float = e.r
			var sc2: float = Game.PX * er / 10.0 * (1.0 - minf(e.kb.length() * 0.03, 14.0) / 40.0)
			var size := dims * sc2
			g.wcv.draw_texture_rect_region(stx, Rect2((ep + Vector2(0, er * 0.8) + doff - size * Vector2(0.5, 0.5)).round(), size), src)
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
	if g.knight.alive or g.knight.leaving():   # leaving：离队就地解散的那 0.35 秒照常排进绘制顺序
		ka.append(g.knight.pos.y + 18.0)
		objs.append(null)
		kind.append(4)
	var fx_items := Pxp.sort_items(g)
	if not fx_items.is_empty():
		_prepare_sorted_fx()
	for it in fx_items:   # 立起层特效按脚底 y 排进单位层
		ka.append(Pxp.sort_key(it))
		objs.append(it)
		kind.append(7)
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
				7:
					_pxp_sorted(ob)
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
		7:
			_pxp_sorted(ob)


func _late_fx_k() -> float:
	if Bal.v("render/late_fx", 0.0) <= 0.0 or g.demo_op != "" or (g.opt_old & 1073741824):   # OPT_LATEFX（仅 --optab 对照）
		return 0.0
	return clampf((g.t - Bal.v("render/late_fx_t0", 480.0)) / maxf(Bal.v("render/late_fx_ramp", 60.0), 0.001), 0.0, 1.0)


## 后期特效控制的参数：手机网页取 late_fx_<键>_mobile（没写就同桌面）
func late_fx_v(key: String, dflt: float) -> float:
	var v: float = Bal.v("render/late_fx_" + key, dflt)
	if Cfg.mobile_web():
		v = Bal.v("render/late_fx_" + key + "_mobile", v)
	return v


## 大面积填充（咒域扇面这类整片半透明底）后期的透明度系数：队长、队友都乘（填充盖怪；边框照画）
func late_fill_k() -> float:
	return lerpf(1.0, late_fx_v("fill", 0.5), late_k) if late_k > 0.0 else 1.0


## 某名干员的发光点系数（转平面 emit 进辉光层）：队友后期 × late_fx_emit，队长 1
func late_emit_k(leader: bool) -> float:
	return 1.0 if leader or late_k <= 0.0 else lerpf(1.0, late_fx_v("emit", 0.4), late_k)


## 同一遍实体绘制共用队长与队友的调色、发光设置。下一次绘制重新读取，换队长也会生效。
func _prepare_sorted_fx() -> void:
	_sorted_dim_mates = late_k > 0.0 and Bal.v("render/late_fx_up", 1.0) > 0.0
	_sorted_leader = ""
	if _sorted_dim_mates or _dbg_opmask:
		var leader = g.squad.leader() if g.squad != null else null
		if leader != null:
			_sorted_leader = str(leader.id)
	if _sorted_dim_mates and _sorted_leader != "":
		if _lf_cv == null:
			_lf_cv = preload("res://scripts/characters/batch_canvas.gd").new(g)
		_lf_cv.set_mod(mate_dim, 0.0)
		_sorted_mate_emit = late_emit_k(false)


func _pxp_sorted(ob: Dictionary) -> void:
	var oid: String = str(ob.get("oid", ""))
	if oid != "" and (_dbg_friend or (_dbg_opmask and Dc.mute_op(oid, oid == _sorted_leader))):
		return
	if _sorted_dim_mates and _sorted_leader != "" and oid != "" and oid != _sorted_leader:
		_lf_cv.g = g.wcv
		lf_emit_k = _sorted_mate_emit
		Pxp.draw_sorted(g, _lf_cv, ob)
		lf_emit_k = 1.0
		return
	Pxp.draw_sorted(g, g.wcv, ob)


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
	g.wcv.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0.02, 0.05, 0.08, 0.55 * _dot_a))
	g.wcv.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 1.0, 1.0, _dot_a))


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
	ShieldDraw.draw_shield(self)
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
					g.wcv.draw_line(b.pos - n * 34.0, b.pos - n * 12.0, _bc(Color(1.6, 1.4, 1.0, 0.3)), 2.0)
				"fire":
					g.wcv.draw_circle(b.pos, 14.0 * vk, _bc(Color(1.4, 0.6, 2.2, 0.2)))
				"arcane":
					g.wcv.draw_line(b.pos - n * 20.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.35)), 4.0)
			var bgk: float = LateRead.grow_of(g.squad.get_op(str(b.op))) if b.has("op") and LateRead.on("v5") else 1.0
			if bgk > 1.001:   # docs/247 V5：干员投射物主形按精英化 / 节点放大（判定半径不变），精一起加厚
				var btx: Texture2D = g.tex.get(ptex)
				var bgs: Array = LateRead.grow_scale(g, btx, int(pspec[0]), Game.PX * vk, bgk, A.hires_of(btx))
				g.vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), bgs[0], _bc(Color.WHITE), Vector2(-1, -1), false, 1 if bgs[1] and bgk >= 1.2 else 0)
			else:
				g.vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), Game.PX * vk, _bc(Color.WHITE))
			continue
		match b.kind:
			"arrow":
				g.wcv.draw_line(b.pos - n * 26.0, b.pos - n * 10.0, _bc(Color(1.6, 1.4, 1.0, 0.35)), 2.0)
				g.wcv.draw_line(b.pos - n * 14.0, b.pos + n * 4.0, _bc(Color(2.2, 2.0, 1.6)), 3.0)
			"fire":
				var fl := 1.0 + 0.2 * sin(g.t * 40.0 + b.pos.x)
				g.wcv.draw_circle(b.pos, 13.0 * fl * vk, _bc(Color(2.0, 0.8, 0.2, 0.25)))
				g.wcv.draw_circle(b.pos, 8.0 * fl * vk, _bc(Color(2.4, 1.1, 0.3, 0.8)))
				g.wcv.draw_circle(b.pos, 4.0 * vk, _bc(Color(2.8, 2.4, 1.4)))
			"arcane":
				g.wcv.draw_line(b.pos - n * 18.0, b.pos, _bc(Color(1.4, 0.6, 2.2, 0.4)), 4.0)
				g.wcv.draw_circle(b.pos, 8.0 * vk, _bc(Color(1.2, 0.5, 2.0, 0.35)))
				UI.diamond(g.wcv, b.pos, 5.0 * vk, _bc(Color(1.8, 1.0, 2.6)), _bc(Color(2.2, 1.6, 2.8)))
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
var bbv2   # render/boss_bullet_draw.gd：Boss 弹幕第二版（弹体图集 + Noita 粒子，docs/306 §8）
var bulfx   # render/bullet_fx.gd： 子弹出现 / 消失画面（用户 10-27；Boss 覆盖钩子 bulfx.set_hook / set_spawn_hook）
var bfx_grains = null   # 本帧可用的颗粒层（光学观感颗粒开着且 boss_fx_grains 开时），_draw_fx 开头取


## 一道冲击环：地面椭圆，深色外描边 + 危险色主色 + 白芯；缺口环按缺口分段（ground 环由 _draw_ground_foe_fx 在单位之下画）
func _draw_shock(sh: Dictionary) -> void:
	if sh.get("boss", false) and Bal.v("render/ishar_song_live", 1.0) > 0.0 and not g.perf_alt:   # perf_alt：--perfab 同局轮换的旧段
		# Boss 冲击环：断续抖动的颗粒带 + 衰减尾带（伊莎玛拉另叠内波纹），专属色（docs/142b §9，用户 10-25）
		BossBeam.draw_song(g, sh, ground_y(), str(sh.get("src_type", "")) == "ishar")
		return
	var a: float = maxf(0.6, 1.0 - sh.r / sh.maxr)
	var tc: Color = sh.get("col", ENEMY_TELL)   # 缺口环（大群之歌）用 Boss 主题色，普通冲击环洋红
	g.wcv.draw_set_transform(sh.pos, 0.0, Vector2(1.0, ground_y()))   # 地面椭圆，和判定一致（docs/48 ①）
	var gh: float = float(sh.get("gap_half", 0.0))
	var gaps: Array = sh.get("gaps", []) if gh > 0.0 else []
	if gaps.is_empty():
		g.wcv.draw_arc(Vector2.ZERO, sh.r - 8.0, 0.0, TAU, 48, Color(tc.r, tc.g, tc.b, 0.18 * a * tell_fill), 10.0)
		g.wcv.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(0, 0, 0, 0.55 * a), 7.0)
		g.wcv.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(tc.r, tc.g, tc.b, a), 4.0)
		g.wcv.draw_arc(Vector2.ZERO, sh.r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * a), 1.5)
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
			g.wcv.draw_arc(Vector2.ZERO, sh.r - 8.0, a0, a1, 32, Color(tc.r, tc.g, tc.b, 0.18 * a * tell_fill), 10.0)
			g.wcv.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(0, 0, 0, 0.55 * a), 7.0)
			g.wcv.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(tc.r, tc.g, tc.b, a), 4.0)
			g.wcv.draw_arc(Vector2.ZERO, sh.r, a0, a1, 32, Color(1, 1, 1, 0.9 * a), 1.5)
		for ga in gaps:
			for side in [-1.0, 1.0]:
				var v := Vector2.from_angle(float(ga) + side * gh)
				g.wcv.draw_line(v * (sh.r - 16.0), v * (sh.r + 16.0), Color(0, 0, 0, 0.7), 5.0)
				g.wcv.draw_line(v * (sh.r - 16.0), v * (sh.r + 16.0), Color(1.0, 0.85, 0.35, 0.9), 2.0)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 敌人出招提示 → 精英登场（docs/54 ④）→ 主控异常 → 预警轮廓 → 主控标记（压在所有敌方预警之上）
func _draw_tells_outlines() -> void:
	if not _dbg_foe and not _dbg_tell:
		TellsDraw.draw_enemy_tells(self)
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


## 博士动画：data/doctor.json 的 sprites（idle 8 / run 8 / hurt 2 / death 4 帧，64 画布脚底 (32,60)；11-08 起待机 / 跑步为 Codex 原生 @2x（doctor_2x_1107）+ 2×2 合并导出的 @1x，hurt / death 仍是 10-24 的 1 倍放大版）；
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
				"ice_thrust", "ice_javelin": return "e_knight_thrust"
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


## 中期 Boss 画面放大（docs/283 A1，11-06 用户「中期 Boss 不明显」：截图里体型和干员一样大）。只乘 _draw_enemy_full 的绘制缩放，
## 判定 e.r、模拟侧的 D.enemy_scale 都不变（同 seed TRACE 不变）。中期 Boss = waves.json mid_pool 里的类型；部件不放大。
## render/mid_boss_scale 缺省 1.35（1 = 原样）；单只可用 render/mid_boss_scale_<类型> 覆盖（塑路者本来就大，缺省 1.2）
var _mbk := {}

func is_mid_boss(e: Dictionary) -> bool:
	if not e.boss or e.get("part", false):
		return false
	return _mid_k(str(e.type)) > 0.0


func mid_boss_k(e: Dictionary) -> float:
	return maxf(1.0, _mid_k(str(e.type))) if is_mid_boss(e) else 1.0


## 中期 Boss 类型 → 放大倍数；不是中期 Boss 返回 0（按类型缓存）
func _mid_k(ty: String) -> float:
	if not _mbk.has(ty):
		var k := 0.0
		for grp in D.MID_POOL:
			if ty in grp:
				k = Bal.v("render/mid_boss_scale_" + ty, Bal.v("render/mid_boss_scale", 1.35))
		_mbk[ty] = k
	return _mbk[ty]


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
	if e.type == "duck":
		g.duck.draw(e, g.wcv)   # 鸭爵：静态图 + 代码跑动（run/duck_lord.gd）
		return
	if _am_mode == 3:
		_act_mod = Look.actor_mod_lut(e.pos)
	elif _am_mode == 2:
		_act_mod = Look.actor_mod_at(e.pos)
	elif _am_mode == 1:
		_act_mod = Color.WHITE
	else:
		_act_mod = Look.actor_mod(g, e.pos)
	if _dark_on and not e.elite and not e.boss:
		# 灯火暗淡（docs/222）：灯圈外的普通海嗣只剩暗轮廓 + 发光眼点；圈缘 25% 半径内渐变。每帧算，不进画法缓存签名
		var d2: float = e.pos.distance_squared_to(_dark_c)
		if d2 > _dark_r * _dark_r * 0.81:
			var f: float = clampf((sqrt(d2) - _dark_r * 0.9) / (_dark_r * 0.3), 0.0, 1.0) * _dark_k
			_act_mod = _act_mod * Color.WHITE.lerp(DARK_MOD, f)
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
	if elite_mark_v2 and not e.boss and (e.elite or e.get("squad", false)):
		return false   # Marked enemies keep their full visual path outside the persistent sprite cache.
	var st = e.get("dcs")
	if st == null:
		st = e.boss or e.chest or e.tex == "e_knight" or D.ENEMIES.get(e.type, _NO_DEF).get("draw_full", false)
		e["dcs"] = st
	if st:
		return false
	if e.wind > 0.0 or e.dash_w > 0.0 or e.dash_t > 0.0 or e.enraged or e.wake_t > 0.0:
		return false
	if e.nova_w > 0.0 or e.blast_w > 0.0 or e.burst_w > 0.0 or e.pose > 0.0:
		return false
	if (e.squash > 0.0 or e.air > 0.0) and (g.opt_old & 8589934592):
		return false   # OPT_DCSQ（仅 --optab 对照）：受击形变 / 托起的敌人走原路径（11-07 前的写法）
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
	if e.get("ishar_blessed", false):
		return true
	if elite_mark_v2 and not e.boss and (e.elite or e.get("squad", false)):
		return false
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
	var frame: int
	if c[22]:
		frame = int((g.t - float(e.get("prepare_started", g.t))) * 3.0) % 2   # 举肢准备（_dc_prep）：和 _draw_enemy_full 同一选帧，再换算到帧条真实帧数
		if c[23]:
			frame = A.enemy_remap_frame(c[8], 4, frame)
	else:
		frame = int(Fxr.react_t(g, e) * float(c[10]) + e.id * 0.37) % frames
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
	# 受击形变 / 托起（11-07 docs/313：原来这两种状态整只退出缓存、走 _draw_enemy_full；选图与颜色不受它们影响，这里逐帧补上）
	var sq := Vector2.ONE
	if e.squash > 0.0:
		var k: float = clampf(e.squash / 0.14, 0.0, 1.0)
		sq = Vector2(1.0 + 0.3 * k, 1.0 - 0.25 * k)
	if e.air > 0.0:
		var alk: Vector2 = Pxp.air_look(g, e)   # 影子与抬高：同 _draw_enemy_full（影子直接画，--dccheck 比对那次由原路径画一次）
		if _rec == null:
			g.wcv.draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
			g.wcv.draw_circle(Vector2.ZERO, e.r * 0.9 * alk.x, Color(0, 0, 0, 0.35 * (0.4 + 0.6 * alk.x)))
			g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_off.y -= e.air + alk.y
	if c[15]:
		_espr_outline(body, frames, frame, bpos, sc, flip, _ol_col(e), anc, sq)
	if ra != null and _afast and _rec == null and sq == Vector2.ONE:
		# 图集快速路径（docs/50 §12 B）：本体和白闪直接按缓存的图集区域画，几何与 vfx.spr 相同；翻转时两次绘制共用一对变换
		var fw: int = ra[2] / frames
		var o: Vector2i = ra[1]
		var src := Rect2(o.x + fw * frame, o.y, fw, ra[3])
		var size := Vector2(fw, ra[3]) * sc
		var p: Vector2 = bpos + g.draw_off
		var rw = rw_all if e.flash > 0.0 else null
		var wcol: Color
		if rw != null:
			var rc: Color = Fxr.react_col(g, e)
			if rc.a == 0.0:
				rw = null
			else:
				var ha: float = 0.9 if e.elite else flash_a
				wcol = Color(1, 1, 1, ha) if rc.a < 0.0 else Color(rc.r, rc.g, rc.b, minf(rc.a, ha + 0.1))   # 同 _draw_enemy_full（配方受击色透明度封顶 hit_a + 0.1）
		if flip:
			g.wcv.draw_set_transform(p.round(), 0.0, Vector2(-1, 1))
			var rf := Rect2(-size * anc, size)
			g.wcv.draw_texture_rect_region(ra[0], rf, src, _rimc(c[11] * _act_mod))
			if rw != null:
				g.wcv.draw_texture_rect_region(rw[0], rf, src, wcol * _act_mod)
			g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var rn := Rect2((p - size * anc).round(), size)
			g.wcv.draw_texture_rect_region(ra[0], rn, src, _rimc(c[11] * _act_mod))
			if rw != null:
				g.wcv.draw_texture_rect_region(rw[0], rn, src, wcol * _act_mod)
	else:
		_espr(body, frames, frame, bpos, sc, flip, c[11], anc, sq)
		if e.flash > 0.0:
			var rc2: Color = Fxr.react_col(g, e)
			if rc2.a != 0.0:
				var ha2: float = 0.9 if e.elite else flash_a
				_espr(wht, frames, frame, bpos, sc, flip, Color(1, 1, 1, ha2) if rc2.a < 0.0 else Color(rc2.r, rc2.g, rc2.b, minf(rc2.a, ha2 + 0.1)), anc, sq)
	if g.optical_on and _rec == null:
		_glow_pts(body, frames, bpos + g.draw_off, sc * sq.x, flip, anc, e, frame)
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
			EnemyAtlas.spr(g.wcv, r, frames, frame, pos + g.draw_off, sc, flip, cm, anc, sq)
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
							if cand.is_empty():
								all_px.clear()   # 已有亮点，后面的像素不再需要深色帧的备用排名。
							cand.append([v * (0.4 + s), x, y, c])
						elif cand.is_empty():
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
	var marked: bool = elite_mark_v2 and not e.get("boss", false) and (e.get("elite", false) or e.get("squad", false))
	var big: bool = e.get("elite", false) or e.get("boss", false) or marked
	var npt: int = mini(pts.size(), 4 if big else 3)
	if npt == 0:
		return
	var cc: Color = Color.WHITE if marked else g.optical.enemy_glow(e)
	var sz: float = maxf(2.0, sc) * (1.5 if big else 1.0)
	for ip in npt:
		var pt: Array = pts[ip]
		var q: Vector2 = pt[0]
		var fs: Vector2 = pt[2]
		var d: Vector2 = (q - anc * fs) * sc / pt[3]   # sc 是 1x 美术像素的倍率，@2x 帧条要除以密度
		if flip:
			d.x = -d.x
		var point_col: Color = cc
		if marked:
			point_col = pt[1]   # Species colour from this frame's emit mask / native bright pixel.
			if ip == npt - 1:
				point_col *= 0.72 + 0.28 * (0.5 + 0.5 * sin(g.t * 3.0 + float(e.id)))
		var point_pos: Vector2 = (pos + d - Vector2(sz, sz) * 0.5).round()
		if g.optical_on:
			g.glow_next.append([point_pos, sz, point_col])
		elif marked and ip == npt - 1:
			g.wcv.draw_rect(Rect2(point_pos, Vector2(sz, sz)), point_col)


## 重画帧条的发光层（name_emit，同帧索引、同原点）：每帧取发光像素按 6 美术像素格归并，取像素最多的至多 4 团的重心。
## 缓存 name -> 每帧点表；没有 _emit 图（旧帧条）返回 null，调用方退回旧的最亮像素法
var _emit_cache := {}

func _emit_pts(name: String, frames: int, frame: int):
	var ent = _emit_cache.get(name)
	if ent == null:
		ent = []
		# 网页：发光层只在这里读一次像素算点表，不留在贴图缓存里（原来每种怪每个动作的 _emit 图整局占着显存，docs/319 §12）
		var tx: Texture2D = A.tex(name + "_emit", not OS.has_feature("web")) if A.has_override(name + "_emit") else null
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
	if not _wd_read:
		_wd_args()
	if wd_noatlas:
		return   # --noatlas（仅测试）：桌面也不拼图集，走手机网页的原帧条路径（docs/319 §22）
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
	var sc: float = enemy_scale(e) * mid_boss_k(e)   # 中期 Boss 只放大画面（docs/283 A1）
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
		g.wcv.draw_set_transform(e.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
		g.wcv.draw_circle(Vector2.ZERO, e.r + 6.0, Color(0.05, 0.02, 0.1, 0.6))
		g.wcv.draw_arc(Vector2.ZERO, e.r + 10.0 + 6.0 * sin(g.t * 9.0 + e.id), 0.0, TAU, 20, Color(0.7, 0.5, 1.0, 0.5), 2.0)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
		g.wcv.draw_set_transform(e.pos + Vector2(0, e.r * 0.7), 0.0, Vector2(1.0, 0.45))
		g.wcv.draw_circle(Vector2.ZERO, e.r * 1.3, Color(1.6, 0.25, 0.2, 0.18 + 0.12 * rp))
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 冲刺预警线改在特效之上的覆盖层画（draw_enemy_tells，docs/48 ②）
	if e.get("dash_t", 0.0) > 0.0 and Bal.v("render/enemy_dash_sparks", 1.0) > 0.0:   # docs/139 §7：0 = 冲刺途中不喷火花
		g.vfx.sparks(e.pos, -e.get("dash_dir", Vector2.ZERO), Color(0.8, 0.9, 1.0), 1, 80.0)   # 骑士绕场巡猎只设 dash_t 不设 dash_dir（11-01 预览报错，整只骑士那帧画不出）
	if e.get("nova_w", 0.0) > 0.0:
		var nk: float = 1.0 - e.nova_w / 0.6
		g.wcv.draw_circle(e.pos, e.r + 6.0 + 10.0 * nk, Color(1.4, 0.5, 2.0, 0.2 + 0.3 * nk))
		col = col.lerp(Color(2.0, 1.2, 2.4), nk * 0.6)
	if e.get("gate_hold", false):
		# 阶段护盾（docs/38 §1.3）：Boss 停在刻度上，金色护盾环脉动；这一幕满最短时长后碎掉
		var gp: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.wcv.draw_circle(e.pos, e.r + 14.0, Color(1.0, 0.8, 0.3, 0.08 + 0.06 * gp))
		g.wcv.draw_arc(e.pos, e.r + 14.0 + 3.0 * gp, 0.0, TAU, 40, Color(1.8, 1.4, 0.5, 0.55 + 0.3 * gp), 2.5)
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
	if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir") and not e.boss and Bal.vi("render/dash_tell_style", 3) >= 1:
		var dwk: float = clampf(1.0 - e.dash_w / float(e.get("dash_w0", D.ENEMIES.get(e.type, {}).get("dash_wind", 0.5))), 0.0, 1.0)
		var body_only: bool = Bal.vi("render/dash_tell_style", 3) >= 3 and not e.elite   # style 3：普通小怪不画线，只靠身体（docs/139 §7.6，参照土豆兄弟）
		var pull_k: float = dwk
		if body_only:
			# 停顿：前 render/dash_hold（0.6）段蓄力就缩到位，之后定住不动、不播走路帧——只改姿态，AI 蓄力时长不变
			pull_k = ease(clampf(dwk / Bal.v("render/dash_hold", 0.6), 0.0, 1.0), 0.4)
			if name.ends_with("_move"):
				name = name.trim_suffix("_move")
				frames = A.enemy_frames(name, 2)
			frame = 0
			# 轻微抖动：定住后按蓄力进度加到 render/dash_shake 世界像素；用 g.t 与 id 算，不抽随机数（TRACE 不变）
			var sk: float = Bal.v("render/dash_shake", 2.0) * clampf((dwk - 0.4) / 0.6, 0.0, 1.0)
			if sk > 0.0:
				bpos += Vector2(roundf(sin(g.t * 71.0 + e.id * 1.7)), roundf(sin(g.t * 59.0 + e.id * 2.9))) * sk
		bpos -= (e.dash_dir as Vector2) * Bal.v("render/dash_pull", 3.0) * Game.PX * pull_k
		var dfl: float = dwk * Bal.v("render/dash_flash", 0.6)   # 随蓄力进度平滑变色，不闪（10-24 Boss 频闪教训）
		var dc: Color = g.optical.col_danger if g.optical_on else ENEMY_TELL
		col = col.lerp(Color(dc.r * 1.6, dc.g * 1.6, dc.b * 1.6, col.a), clampf(dfl, 0.0, 1.0))
		if body_only and float(e.dash_w) <= Bal.v("render/dash_white_t", 0.1):
			col = Color(2.6, 2.6, 2.6, col.a)   # 起冲前最后 render/dash_white_t 秒整体闪白一次（只这一段，不频闪）
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
		var alk: Vector2 = Pxp.air_look(g, e)   # 转平面（docs/267）：安洁莉娜托起的敌人影子随高度缩小变淡、悬停时上下浮动 1 美术像素（只画；其余 (1, 0) 原样）
		g.wcv.draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
		g.wcv.draw_circle(Vector2.ZERO, e.r * 0.9 * alk.x, Color(0, 0, 0, 0.35 * (0.4 + 0.6 * alk.x)))
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_off.y -= e.air + alk.y
	# 轮廓光：深色怪物在灯光外也能看清（颜色 >1，抵消环境暗色）
	if e.get("part", false):
		# 部件（塑路者核心等）：心跳脉动——每拍一次放大 + 金色光晕；描边不受「怪物轮廓光」开关影响
		var hb: float = _heartbeat(e)
		sq *= 1.0 + 0.1 * hb
		g.wcv.draw_circle(e.pos, e.r * (1.3 + 0.5 * hb), Color(PART_COL.r * 1.4, PART_COL.g * 1.4, PART_COL.b * 1.4, 0.22 + 0.3 * hb))
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
		if elite_mark_v2 and not e.boss and (e.elite or e.get("squad", false)):
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
	if (g.optical_on or (elite_mark_v2 and not e.boss and (e.elite or e.get("squad", false)))) and _rec == null:
		_glow_pts(name, frames, bpos + g.draw_off, sc * sq.x, flip, anc, e, frame)
	if e.flash > 0.0:
		# 受击白闪：普通怪随 ecrowd 降到 declutter flash_a（缺省 0.9 = 不变）；精英 / Boss 照旧
		var hit_a: float = g.vfx.boss_flash_alpha(e, Bal.v("fx/flash_boss", 0.5)) if e.boss else (0.9 if e.elite else flash_a)   # Boss 白闪 50%（docs/127 C3：大体型整块变白刺眼）、限频淡出（docs/137）
		var rc3: Color = Fxr.react_col(g, e)   # 配方受击反应：闪本人色（Boss 不接管，react_col 对 Boss 返回 a < 0）
		if rc3.a != 0.0:
			_espr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, hit_a) if rc3.a < 0.0 else Color(rc3.r, rc3.g, rc3.b, minf(rc3.a, hit_a + 0.1)), anc, sq)
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
			UI.text(g.wcv, g.font, wp + Vector2(-20, 16), ("弱" + wk.substr(0, 1)) if wk != "双" else "双弱", 10, wc, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# 精英血条与标识改到 HUD 层（hud.draw_elite_marks）：不受灯光压暗，也不受「怪物轮廓光」开关影响（docs/48 P1）
	g.draw_off = Vector2.ZERO


## 在任意位置绘制水月（残影、倒影用）
## 以脚底为锚点画一帧（干员本体 / 分身 / 残影）：foot_off = 帧内脚底距底边的像素（贴图像素）
var draw_target: CanvasItem = null   # 光学观感的高清干员层：干员本体临时画到这里（render/optical.gd _draw_ops 设，画完清回 null）

## docs/247 S3 放置物描边用的我方色：代表色拉到满亮度 × s1_ol_hdr（暗场里不被压成灰）。
## 小队描边 11-05 用户定不要（小队只靠头顶红三角标识），已删；这里只剩放置物在用
func squad_ol_col(c: Color, a := 1.0) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b))
	var k: float = 1.0 / maxf(0.01, m)   # 拉到满亮度：深色代表色在暗地面上也看得见
	var hk: float = LateRead.k("s1_ol_hdr", 1.35)   # 略超 1：暗场里描边不被压成灰
	return Color(minf(1.0, c.r * k * 0.95 + 0.05) * hk, minf(1.0, c.g * k * 0.95 + 0.05) * hk, minf(1.0, c.b * k * 0.95 + 0.05) * hk, LateRead.k("s1_ol_a", 0.95) * clampf(a, 0.0, 1.0))


func draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float, sc := 1.0) -> void:
	if tx == null:
		return
	var ci: CanvasItem = draw_target if draw_target != null else g.wcv
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
	g.wcv.draw_set_transform(pos, 0.0, Vector2(-pk if flip else pk, pk))
	g.wcv.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + Vector2(0, -fh / 2.0 + 2.0 * A.hires_of(tx)), Vector2(fw, fh)), src, col)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## 地面进度环（脚下椭圆，从正上方顺时针填充）
func _ground_ring(p: Vector2, r: float, k: float, c: Color) -> void:
	g.wcv.draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 7.0)
	g.wcv.draw_arc(Vector2.ZERO, r, -PI / 2.0, -PI / 2.0 + TAU * k, 48, c, 4.0)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		g.wcv.draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
		g.wcv.draw_circle(Vector2.ZERO, 22.0 + 4.0 * g.cold, Color(COLD_COL.r, COLD_COL.g, COLD_COL.b, 0.10 * ca))
		g.wcv.draw_arc(Vector2.ZERO, 22.0 + 4.0 * g.cold, 0.0, TAU, 32, Color(COLD_COL.r, COLD_COL.g, COLD_COL.b, 0.5 * ca), 1.5)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for q in g.cold:
			var a: float = g.t * 2.2 + q * TAU / maxf(1.0, g.cold)
			var cp: Vector2 = body + Vector2(cos(a) * 26.0, sin(a) * 9.0 + 8.0)
			UI.diamond(g.wcv, cp, 4.0, Color(0.85, 1.2, 1.6, 0.9 * ca), Color(0.2, 0.4, 0.7, 0.9))
	if g.root_t > 0.0:
		var k: float = clampf(g.root_t / maxf(0.05, root_max), 0.0, 1.0)
		if leader_nerve_stun():
			# 神经损伤眩晕：头顶三颗洋红星转圈 + 脑后一圈抖动的神经纹
			for q in 3:
				var a3: float = g.t * 6.0 + q * TAU / 3.0
				UI.diamond(g.wcv, body + Vector2(cos(a3) * 18.0, -40.0 + sin(a3) * 5.0), 4.0, Color(1.8, 0.7, 1.6), Color(0.2, 0.0, 0.2, 0.9))
			var zz := PackedVector2Array()
			for i in 13:
				var a4: float = i * TAU / 12.0
				zz.append(body + Vector2(cos(a4), sin(a4) * 0.5) * (26.0 + 3.0 * sin(g.t * 30.0 + i * 2.0)) + Vector2(0, -30))
			g.wcv.draw_polyline(zz, Color(1.6, 0.6, 1.5, 0.7), 1.5)
		elif leader_frozen():
			# 冰壳：六边形晶体罩住全身，剩余越少越透明、出裂纹
			var pts := PackedVector2Array()
			for i in 6:
				var a2: float = -PI / 2.0 + i * TAU / 6.0
				pts.append(body + Vector2(cos(a2) * 28.0, sin(a2) * 44.0))
			g.wcv.draw_colored_polygon(pts, Color(0.55, 0.85, 1.3, 0.22 + 0.18 * k))
			pts.append(pts[0])
			g.wcv.draw_polyline(pts, Color(0.9, 1.3, 1.8, 0.85), 2.0)
			g.wcv.draw_line(body + Vector2(-14, -30), body + Vector2(-4, -4), Color(1.6, 1.8, 2.0, 0.7), 2.0)
			if k < 0.6:
				g.wcv.draw_polyline(PackedVector2Array([body + Vector2(8, -34), body + Vector2(2, -12), body + Vector2(12, 4), body + Vector2(4, 22)]), Color(1.6, 1.8, 2.0, 0.9), 1.5)
		else:
			# 束缚：三条暗紫触须从脚下缠到腰
			for q in 3:
				var sx: float = -24.0 + q * 24.0
				var pts2 := PackedVector2Array()
				for i in 9:
					var u: float = i / 8.0
					pts2.append(foot + Vector2(sx * (1.0 - u) + sin(u * 7.0 + q * 2.0 + g.t * 3.0) * 7.0, -u * 46.0 * (0.4 + 0.6 * k)))
				g.wcv.draw_polyline(pts2, Color(0.25, 0.1, 0.35, 0.9), 5.0)
				g.wcv.draw_polyline(pts2, BIND_COL, 2.0)
		# 倒计时环（脚下）
		g.wcv.draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
		var rc: Color = COLD_COL if leader_frozen() else (Color(1.6, 0.6, 1.5) if leader_nerve_stun() else BIND_COL)
		g.wcv.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 6.0)
		g.wcv.draw_arc(Vector2.ZERO, 36.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, rc, 4.0)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var nmax: float = g.combat.nerve_max()
	var nk: float = clampf(g.nerve / nmax, 0.0, 1.0)
	if nk > 0.05 and g.root_t <= 0.0:
		# 神经损伤累积：头部周围一圈洋红细电弧，量越高越多越快
		var n2: int = 1 + int(nk * 5.0)
		for q in n2:
			var a5: float = g.t * (3.0 + 5.0 * nk) + q * TAU / n2
			var p5: Vector2 = body + Vector2(cos(a5) * 20.0, -30.0 + sin(a5) * 7.0)
			var j: Vector2 = Vector2(sin(g.t * 40.0 + q) * 3.0, cos(g.t * 37.0 + q) * 3.0)
			g.wcv.draw_line(p5, p5 + Vector2(6, -4) + j, Color(1.8, 0.6, 1.6, 0.4 + 0.5 * nk), 1.5)
	if g.wound > 0:
		for q in g.wound:
			var wp: Vector2 = body + Vector2(-12 + (q % 2) * 20, -10 + q * 9)
			g.wcv.draw_line(wp + Vector2(-5, -3), wp + Vector2(5, 3), Color(0.2, 0.0, 0.1, 0.9), 4.0)
			g.wcv.draw_line(wp + Vector2(-5, -3), wp + Vector2(5, 3), WOUND_COL, 2.0)
			var dk: float = fmod(g.t * 0.9 + q * 0.37, 1.0)
			g.wcv.draw_circle(wp + Vector2(2, 4 + dk * 22.0), 1.8, Color(WOUND_COL.r, WOUND_COL.g, WOUND_COL.b, 1.0 - dk))


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
	g.wcv.draw_line(hilt, tip, Color(0.1, 0.1, 0.15, a), 6.0)
	g.wcv.draw_line(hilt, tip, Color(1.7, 1.7, 1.9, a), 3.0)
	g.wcv.draw_line(hilt + Vector2(-7, 2), hilt + Vector2(7, -2), Color(1.6, 1.3, 0.6, a), 3.0)


var beacon_seen: Array = []     # [beacon, 上次 lit]


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
	g.wcv.draw_line(c - d.orthogonal() * (w.wid + 10.0), c + d.orthogonal() * (w.wid + 10.0), Color(0, 0, 0, 0.7), 7.0)
	g.wcv.draw_line(c - d.orthogonal() * (w.wid + 10.0), c + d.orthogonal() * (w.wid + 10.0), Color(1.8, 1.5, 0.6, 0.8 + 0.2 * pk), 3.5)
	g.wcv.draw_circle(c + Vector2(0, -26), 12.0, Color(0.05, 0.05, 0.08, 0.85))
	g.wcv.draw_arc(c + Vector2(0, -26), 12.0, 0.0, TAU, 20, Color(1.8, 1.5, 0.6, 0.9), 1.5)
	UI.text(g.wcv, g.font, c + Vector2(-12, -20), "破", 14, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 24, 2)


## 长枪脱手（knight_boss 撞桩后的 5 秒大破绽上升沿）：一杆长枪从骑士手里旋转飞出，抛物线落到身后，落地冰屑
func spear_fly_fx(b: Dictionary) -> void:
	var dir: float = -1.0 if b.get("fx", 1.0) >= 0.0 else 1.0
	g.fx.append({"kind": "spear_fly", "pos": b.pos + Vector2(0, -b.r), "to": b.pos + Vector2(dir * 150.0, 20.0), "life": 0.8, "max": 0.8, "enemy": true})


const ENTITY_MARGIN := 180.0   # 大体型 Boss / 精英贴图从脚底往上长，外扩够画出半身
const TELL_MARGIN := 420.0
const GEM_MERGE_N := 50         # 场上结晶超过这个数才合并远处的小结晶（11-04 Codex 量后期同屏 111 颗，120 → 50；只合画面，拾取 / 经验不变；balance render/gem_merge_n 可改）
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
		g.wcv.draw_texture_rect_region(bt, Rect2(p - Vector2(sz.x / 2.0, sz.y), sz), Rect2(fw * int(b[1]), 0, fw, fh), Color(1, 1, 1, 0.85 * float(b[2])))


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
		if OS.has_feature("web"):
			out.convert(Image.FORMAT_LA8)
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
		g.wcv.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		g.wcv.draw_texture_rect_region(t, Rect2(-size * anchor - pad, size + pad * 2.0), src, col)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.wcv.draw_texture_rect_region(t, Rect2((pos - size * anchor).round() - pad, size + pad * 2.0), src, col)


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
	_tbb.flush(ci if ci != null else g.wcv)   # g.wcv：世界画布，敌方顶层那一遍是 g.foe_top（docs/226 §1）


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


## 地面形状的纵向压缩：和判定一致（combat.gd 的 GROUND_Y，Boss与怪物「画即判」；还没有这个常量时按正圆 1.0）
var _gy := -1.0


func ground_y() -> float:
	if _gy < 0.0:
		_gy = float(load("res://scripts/run/combat.gd").get_script_constant_map().get("GROUND_Y", 1.0))
	return _gy


## V7 预警帧条（docs/13 §V7，docs/48 ⑥ 接入闲置素材）：圆形涟漪 64px（radius_px 30）/ 直线流动水纹 16px 平铺 / 终点漩涡 32px
var _warn_tex := {}


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
		g.wcv.draw_arc(Vector2.ZERO, r, a, minf(a + seg * 0.55, a1), 4, col, wdt)
		a += seg


func draw_warn_outlines(ground := false) -> void:
	for w in g.warns:
		if w.done or TeleDraw.quiet(w) or bool(w.get("ground", false)) != ground or w.get("saint_beam", false):   # saint_beam：圣徒光束蓄力自己画（render/saint_draw）
			continue   # ground：小怪踏地的轮廓在地面层画（_draw_ground_foe_fx），不压在单位上
		if IsharTell.owns(w):
			continue   # 伊莎玛拉：涟漪勾边已在 ishar_tell_draw 画（docs/170）
		if preload("res://scripts/render/minion_warn.gd").owns(w):
			preload("res://scripts/render/minion_warn.gd").outline(g, w)
			continue
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
					g.wcv.draw_set_transform(w.pos, 0.0, Vector2(1.0, gy))
					_warn_dash_arc(w.r, 0.0, TAU, Color(1, 1, 1, 0.3), 1.0)
					g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					continue
				g.wcv.draw_set_transform(w.pos, 0.0, Vector2(1.0, gy))
				if tracking:
					_warn_dash_arc(w.r, 0.0, TAU, edge, 5.0)
					_warn_dash_arc(w.r, 0.0, TAU, core, 2.0)
				else:
					g.wcv.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, edge, 5.0 * tell_edge)
					g.wcv.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, core, 2.0 * tell_edge)
				if must:
					# ⑤ 必须冲刺：白色双描边
					var pk: float = 0.5 + 0.5 * sin(g.t * 12.0)
					g.wcv.draw_arc(Vector2.ZERO, w.r + 7.0, 0.0, TAU, 56, Color(1, 1, 1, 0.55 + 0.35 * pk), 2.0)
					g.wcv.draw_arc(Vector2.ZERO, w.r - 5.0, 0.0, TAU, 56, Color(1, 1, 1, 0.45 + 0.3 * pk), 1.5)
				elif not ring:
					# ① 落点圈：内圈随结算时间长满，最后 0.12 秒整圈白闪
					g.wcv.draw_arc(Vector2.ZERO, maxf(2.0, w.r * k), 0.0, TAU, 48, Color(1, 1, 1, (0.35 + 0.35 * k) * da), 1.5)
					if w.dur - w.t < 0.12:
						g.wcv.draw_circle(Vector2.ZERO, w.r, Color(1, 1, 1, 0.35))
				if lock_flash > 0.0:
					g.wcv.draw_circle(Vector2.ZERO, w.r, Color(1, 1, 1, 0.4 * lock_flash))
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if must:
					var ic: Vector2 = w.pos + Vector2(0, -w.r * gy - 22.0)
					for q in 3:
						var ox: float = -9.0 + q * 7.0
						g.wcv.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(0, 0, 0, 0.7), 5.0)
						g.wcv.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(1, 1, 1, 0.95), 2.5)
			"line":
				g.wcv.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				if tracking:
					var xx := 0.0
					while xx < w.len:
						var x2: float = minf(xx + 14.0, w.len)
						for sy in [-w.wid, w.wid]:
							g.wcv.draw_line(Vector2(xx, sy), Vector2(x2, sy), edge, 5.0)
							g.wcv.draw_line(Vector2(xx, sy), Vector2(x2, sy), core, 2.0)
						xx += 24.0
				else:
					g.wcv.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), edge, false, 5.0 * tell_edge)
					g.wcv.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), core, false, 2.0 * tell_edge)
					if lock_flash > 0.0:
						g.wcv.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), Color(1, 1, 1, 0.5 * lock_flash), true)
				# 终点端盖
				g.wcv.draw_line(Vector2(w.len, -w.wid - 6.0), Vector2(w.len, w.wid + 6.0), edge, 7.0)
				g.wcv.draw_line(Vector2(w.len, -w.wid - 6.0), Vector2(w.len, w.wid + 6.0), core, 3.0)
				# 冲锋 / 突刺：沿线的方向箭头，随时间向前流动
				if w.get("act", "") in ["dash", "stab"]:
					var hw: float = minf(w.wid * 0.6, 14.0)
					var off: float = fmod(g.t * 160.0, 70.0)
					var ax: float = 30.0 + off
					while ax < w.len - 20.0:
						g.wcv.draw_polyline(PackedVector2Array([Vector2(ax - hw, -hw), Vector2(ax, 0), Vector2(ax - hw, hw)]), edge, 5.0)
						g.wcv.draw_polyline(PackedVector2Array([Vector2(ax - hw, -hw), Vector2(ax, 0), Vector2(ax - hw, hw)]), Color(1, 1, 1, (0.55 + 0.35 * k) * da), 2.0)
						ax += 70.0
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
							g.wcv.draw_line(pts[q], pts[q + 1], edge, 5.0)
							g.wcv.draw_line(pts[q], pts[q + 1], core, 2.0)
				else:
					g.wcv.draw_polyline(pts, edge, 5.0 * tell_edge)
					g.wcv.draw_polyline(pts, core, 2.0 * tell_edge)
				# 扇面内一道随时间向外推的弧
				g.wcv.draw_arc(w.pos, maxf(4.0, w.r * k), w.ang - w.half, w.ang + w.half, 20, Color(1, 1, 1, (0.3 + 0.4 * k) * da), 1.5)
				if lock_flash > 0.0:
					g.wcv.draw_colored_polygon(pts, Color(1, 1, 1, 0.3 * lock_flash))
		# ④ 缺口环的出口：缺口两侧金色短线 + 中间「出口」小牌（缺口方向与真实弹道同一角度，不做地面压缩）；多缺口（gaps）每个缺口各画一组
		if w.has("gap_ang"):
			var safe_col := Color(1.0, 0.85, 0.35, 0.9)
			var r_in: float = minf(90.0, float(w.r) * 0.6)
			var r_out: float = float(w.r) + 40.0   # 11-01 巡检 D6：原来下限 190，环小、Boss 靠上时金线扎进 Boss 血条下面，像外来连线
			for ga in w.get("gaps", [w.gap_ang]):
				for side in [-1.0, 1.0]:
					var v := Vector2.from_angle(float(ga) + side * float(w.gap_half))
					g.wcv.draw_line(w.pos + v * r_in, w.pos + v * r_out, Color(0, 0, 0, 0.7), 5.0)
					g.wcv.draw_line(w.pos + v * r_in, w.pos + v * r_out, safe_col, 2.0)
				var mp: Vector2 = w.pos + Vector2.from_angle(float(ga)) * (r_in + r_out) * 0.5
				# 缺口处的「出口」字样 10-22b 用户取消：只留两侧金线标出缺口


## 黑潮圈边的溟痕格（栅格化 + 补洞求围边）按「圆心、半径、弧段」记住（docs/50 §26：后期每帧重算约占一帧 5%）：
## 弧段两端按 4 个采样取整（多出的格子在视野外扩 80 像素之外，屏内画面不变），圈不动时镜头走动多数帧直接复用；缩圈时半径每帧在变照旧重算
var _zc_key: Array = []
var _zc_val: Array = []


## 黑潮边缘的溟痕带（2026-09-27 用户要求：原来是沿圈摆一个个分开的溟痕贴图 → 连成一圈 → 再改成溟痕本身的样子）：
## 沿圆周连续的一条带，内沿（安全区一侧）是起伏的亮紫潮头线，往外由溟痕紫渐隐到圈外暗色；带上有缓慢漂移的暗色溟痕团，
## 表现流动。只画视野附近的弧段（段长约 22 像素，封顶 420 段），手机 / 网页每帧几十到一两百个四边形。只改画面，判定仍是 zone_r
const ZB_SEG := 22.0


## 黑潮缩圈快速写法（性能 docs/50 §14，OPT_ZONE）：
## 圈外暗区 seg 段的圆周点按单位方向表（seg + 1 个，算式同 Vector2.from_angle(TAU × i / seg)，末点是 TAU 本身）整组乘 Transform2D 得到
## （zone_c + d × 半径，逐位相同），可见判定同旧写法，整批无索引三角形一次提交（三角形与 tb_quad 的相同、同序）
var _zdark_dirs := {}   # seg -> PackedVector2Array(seg + 1)
var _zone_tabs := {}    # 溟痕带段数 n -> [角度 PackedFloat64Array, 方向 PackedVector2Array]
var _zone_btabs := {}   # 溟痕块数 nb -> [方向, 径向偏移, 大小, 翻转]


## 黑潮带的一段连续弧：内沿→中线、中线→外沿两条带，各自画成一个多边形（边线正走、另一边倒走），顶点色和原来逐段画的一致
## 快速写法（docs/50 §15 D1，OPT_BAND）：三条边线首尾接成一个点数组，按「相邻两列四个点两个三角形」的带状剖分（索引表按点数缓存）
## 一次提交；原来 draw_polygon 在引擎里当场耳切三角化（O(n²)）。顶点、顶点色相同，只是带内部的三角形划分不同（渐变插值方向略变）
var _band_idx := {}   # 每条边线点数 m -> [索引 PackedInt32Array, 顶点色 PackedColorArray]


## 面板关闭后的保护（combat.panel_grace）：脚下一圈淡金双环向内收拢、随剩余时间变淡。
## 贴地椭圆、暖白金色，和护盾（罩住身体的淡金气泡，10-28 改版）靠贴地椭圆区分；无敌期间本体照常闪烁
func draw_panel_grace() -> void:
	var left: float = g.panel_grace_until - g.t
	if left <= 0.0:
		return
	var k: float = clampf(left / maxf(0.01, Game.Bal.v("protect/panel_grace", 0.8)), 0.0, 1.0)
	var c := g.ppos + Vector2(0, 14)
	var r := 26.0 + 18.0 * k
	g.wcv.draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	g.wcv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.4, 1.25, 0.8, 0.75 * k), 2.0)
	g.wcv.draw_arc(Vector2.ZERO, r + 7.0, 0.0, TAU, 40, Color(1.4, 1.25, 0.8, 0.3 * k), 1.0)
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var _sh_prev := -1
var _sh_brk_t := -9.0      # 上次碎裂（g.t）
var _sh_chg_t := -9.0      # 上次充好一层（g.t）
var _sh_edge_pts := PackedVector2Array()
var _sh_edge_radius := -1.0


## B / C 的 48 段细边只改位置和颜色。保留原来 arc_q 的顶点（含末端），只存一圈。
func _shield_edge(c: Vector2, radius: float, col: Color) -> void:
	if radius != _sh_edge_radius:
		var template := TriBatch.new()
		template.arc_q(Vector2.ZERO, radius, 0.0, TAU, 2.0, Color.WHITE, 48)
		_sh_edge_pts = template.pts
		_sh_edge_radius = radius
	_tbb.translated_solid(_sh_edge_pts, c, col)


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
		# 扬尘只在对局里出（docs/305）：这里按真实时间走，暂停 / 三选一 / 属性面板时 g.moving 还停在 true，
		# 原来每秒照出 10 颗、而 fx 寿命只在模拟里扣 —— 面板开多久就堆多久（实测 15 分钟 7600 个、网页帧时 25 → 90 ms）
		if g.state == Game.S.PLAY:
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
	if g.state == Game.S.OPENING and g.intro_screen.opening_t < g.intro_screen.DOCTOR_DROP:
		return
	var tx: Texture2D = g.sprite.texture
	if tx == null:
		return
	var hf := g.sprite.hframes
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	if g.state == Game.S.OPENING and g.intro_screen.opening_t < g.intro_screen.DOCTOR_LAND:
		var anchor := Vector2(fw / 2.0, fh / 2.0) - g.sprite.offset
		g.intro_screen.draw_from_hatch(tx, g.sprite.frame, hf, g.sprite.position + g.p_off, anchor, g.sprite.flip_h, Look.plain_mod(g, g.sprite.position))
		return
	var src := Rect2(fw * (g.sprite.frame % hf), 0, fw, fh)
	var pk: float = Game.PX / A.hires_of(tx)   # @2x 高清贴图按半倍画
	var sx := -pk if g.sprite.flip_h else pk
	# 以脚底为轴做挤压 / 前倾 / 后坐（帧动画之上的程序手感）
	g.wcv.draw_set_transform(g.sprite.position + g.p_off, g.sprite.rotation + g.p_lean, Vector2(sx * g.p_sq.x, pk * g.p_sq.y))
	# 博士挂件不受击：不吃主控的受击闪白 / 无敌闪烁（那些现在画在主控干员身上）
	var dmod: Color = Color(0.5, 0.5, 0.6, 0.6) if g.state == Game.S.DEAD else Color.WHITE
	g.wcv.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + g.sprite.offset, Vector2(fw, fh)), src, dmod * Look.plain_mod(g, g.sprite.position))
	g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
