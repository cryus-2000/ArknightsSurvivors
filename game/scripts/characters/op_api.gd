## 干员 → 主场景的接口层（2026-09-26 架构整理）：干员脚本需要 game.gd 提供的能力（索敌、伤害、特效、飘字、绘制……）
## 一律通过这里的方法调用，不直接调用 game.gd 里下划线开头的内部函数。
## 好处：game.gd 以后拆分 / 改名 / 改参数时只改这一个文件，13 名干员不受影响；这里也就是「干员能用什么」的完整清单。
## 读写 game.gd 的公共状态（ppos、enemies、stats、hitstop、t 等）和 CanvasItem 绘制（g.draw_*）不在此列，仍直接用 g。
## 继承关系：op_api.gd ← character.gd ← <干员>.gd
extends RefCounted

var g                      # Game (Node2D)


# ---------------------------------------------------------------- 索敌

## 离 origin（缺省为主控位置）最近的 n 个活着的敌人，max_dist 以内。
## Boss 优先（2026-09-29 协调人：普通档打不动 3:30 的第一个 Boss，输出被身边小怪抢走）：balance ai/boss_focus（缺省 1 = 开）时，
## max_dist 内有可受击的 Boss 就排到第一个；部件（e.part）优先照旧；主控 ai/boss_focus_guard（60）内有小怪贴脸时不强制
func nearest_enemies(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	var out: Array = g.enemies_sys.nearest(n, max_dist, origin)
	if out.is_empty() or out[0].boss or out[0].get("part", false):
		return out
	var BalS = preload("res://scripts/core/balance.gd")
	if BalS.v("ai/boss_focus", 1.0) <= 0.0:
		return out
	var o: Vector2 = g.ppos if origin == Vector2.INF else origin
	var best = null
	var bd: float = max_dist * max_dist
	for e in _focus_bosses():
		if e.dead:
			continue
		var d: float = e.pos.distance_squared_to(o)
		if d < bd:
			bd = d
			best = e
	if best == null:
		return out
	var guard: Array = g.enemies_sys.nearest(1, BalS.v("ai/boss_focus_guard", 60.0), g.ppos)
	if not guard.is_empty() and not guard[0].boss:
		return out   # 小怪贴着主控：先护主，不强制打 Boss
	out.erase(best)
	out.push_front(best)
	if out.size() > n:
		out.resize(n)
	return out


## 场上可受击的 Boss（每帧缓存一次）：不在假死（coma）/ 无敌（invuln、gate_inv）/ 潜地（under）
var _fb_frame := -1
var _fb_list: Array = []

func _focus_bosses() -> Array:
	if _fb_frame == g.frame_n:
		return _fb_list
	_fb_frame = g.frame_n
	_fb_list = []
	for e in g.enemies:
		if e.boss and not e.dead and not e.get("coma", false) and not e.get("invuln", false) \
				and e.get("gate_inv", 0.0) <= 0.0 and not e.get("under", false):
			_fb_list.append(e)
	return _fb_list


## 空间网格查询：排除友方，返回 pos 周围 radius 内的敌人下标（g.enemies[i]，可能包含已死亡的，调用方自己判断 e.dead）
func query_ids(pos: Vector2, radius: float) -> Array:
	return g.enemies_sys.query(pos, radius)


## 扇形内的敌人（origin 为圆心，ang 朝向，half 半角）
func arc_targets(origin: Vector2, ang: float, half: float, radius: float) -> Array:
	return g.enemies_sys.arc_hit(origin, ang, half, radius)


## origin 周围 radius 内敌人最密处（没有敌人返回 Vector2.INF）
func densest_point(radius: float, origin: Vector2 = Vector2.INF) -> Vector2:
	return g.enemies_sys.densest_point(radius, origin)


# ---------------------------------------------------------------- 伤害 / 治疗

## 登记这一击的伤害来源（结算统计、藏品触发按来源分类）；在 deal_damage 之前调用
func log_hit(src: String, extra_tags: Array = []) -> void:
	g.combat.hit(src, extra_tags)


## 对敌人造成伤害（走护甲、易伤、藏品倍率、击杀结算）
func deal_damage(e: Dictionary, dmg: float) -> void:
	var hp_before: float = e.hp
	var feedback_source: String = g.hit.get("src", "")
	g.combat.damage(e, dmg)
	if float(e.hp) < hp_before:
		g.vfx.contact(str(get("id")), e, get("pos"), feedback_source)


## 治疗主控（src 进治疗统计）
func heal_leader(v: float, src: String = "其他") -> void:
	g.combat.heal(v, src)


## 属性块变动后立即刷新 game.gd 的缓存变量（stats.add 之后需要当帧生效时调用）
func refresh_stats() -> void:
	g.sync_stats()


## 用对局随机数打乱（同 seed 可复现，docs/36）
func shuffle_rng(a: Array) -> void:
	g._shuffle(a)


# ---------------------------------------------------------------- 灯火

func lamp_radius() -> float:
	return g._lamp_r()


func lamp_sp() -> float:
	return g._lamp_sp()


# ---------------------------------------------------------------- 特效 / 提示


## 统一命中顿帧与落地碎屑，节流和预算由 VFX 模块处理。
func impact_pause(seconds: float) -> void:
	g.vfx.impact_pause(seconds)


func ground_dust(at: Vector2, radius := 22.0, count := 7) -> void:
	g.vfx.ground_dust(at, radius, count)

## 播放一次性特效帧条（V6_FRAMES 注册的 fx_*）；贴图缺失返回 false，调用方可退回程序特效
func spawn_fx_sprite(name: String, pos: Vector2, scale: float = -1.0, ang := 0.0, flip := false, bottom := false, col := Color.WHITE) -> bool:
	return g.vfx.fx_sprite(name, pos, g.PX if scale < 0.0 else scale, ang, flip, bottom, col)


## 旧式整条动画特效（跟随可选）
func play_anim_fx(name: String, pos: Vector2, dur: float, scale: float = -1.0, follow := false) -> bool:
	return g.vfx.anim(name, pos, dur, g.PX if scale < 0.0 else scale, follow)


## 挥砍弧光（普攻 / 技能的刀光）
func slash_fx(origin: Vector2, ang: float, half: float, radius: float, col: Color, tex_name := "slash", life := 0.22) -> void:
	g.vfx.slash_fx(origin, ang, half, radius, col, tex_name, life)


## 刀光贴图名（按强化状态选 base / awaken / mirage）
func slash_tex_name(kind := "base") -> String:
	return g.vfx.slash_tex(kind)


## 敌人受击闪白 / 火花
func enemy_hit_fx(e: Dictionary, dir := Vector2.ZERO) -> void:
	g.vfx.hit_fx(e, dir)


## 方向性火花
func sparks(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float) -> void:
	g.vfx.sparks(pos, dir, col, n, spd)


## 飘字
func float_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	g.vfx.add_text(pos, text, col, size)


## 屏幕中上方横幅：干员技能名等提示一律最低优先级（vfx 横幅队列：有横幅在播时直接丢掉，不挤掉精英出现等局内事件）
func show_banner(text: String) -> void:
	g.vfx.show_banner(text, 0)


## 屏幕震动（强度 0–1，受设置里的震动开关缩放）
func screen_shake(a: float) -> void:
	g.vfx.shake_screen(a)


## HUD 技能栏条目（HUD 与图鉴读取）
func skill_item(i: int) -> Dictionary:
	return g.show_screen.skill_item(self, i)


# ---------------------------------------------------------------- 绘制（只能在 draw_* 回调里调用）

## 帧条绘制（按中心 / anchor 定位）
func draw_spr(name: String, frames: int, frame: int, pos: Vector2, scale: float = -1.0, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	g.vfx.spr(name, frames, frame, pos, g.PX if scale < 0.0 else scale, flip, col, anchor, sq)


## 旋转帧条绘制（支持 @2x 贴图）
func draw_spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale: float = -1.0, col := Color.WHITE, anchor_px := Vector2(-1, -1), flip := false) -> void:
	g.vfx.spr_rot(name, frame, pos, ang, g.PX if scale < 0.0 else scale, col, anchor_px, flip)


## 画到另一个 CanvasItem 上（HUD 图标等）
func draw_spr_on(ci: CanvasItem, name: String, frames: int, frame: int, pos: Vector2, scale: float = -1.0) -> void:
	g.vfx.spr_on(ci, name, frames, frame, pos, g.PX if scale < 0.0 else scale)


## 按脚底锚点画角色帧（剪影、残影用）
func draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float) -> void:
	g.world.draw_sprite_at(pos, flip, col, frame, tx, hf, foot_off)
