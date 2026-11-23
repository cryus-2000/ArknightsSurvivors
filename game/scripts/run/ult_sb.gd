## 圣聆初雪终结技「千分之一的心」（docs/403 §2.7、§9）：以队长为心（aim none）。摇铃 0.3 秒 → 冰面由内向外冻结（0.3–0.9 秒，敌人依次冻住，Boss 只减速）
## → 静止、冰缝从中心亮起、往里一吸（1.05–1.2）→ 1.2 秒整片冰面碎裂（全段唯一一下冲击帧）→ 留下满层雪地。
## 接口同 ult_moves_c（handles / aim_kind / aim_r / start / step），ult_moves 按 id 转来。伤害一律走 u.hit；冻结段标 pre，冲击帧只落在碎裂。
## 画面全部发 Fxr 事件给 render/fx_pxplane_sb.gd（只画），本文件不画、不抽随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Fxr = preload("res://scripts/render/fx_recipe.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")
static var SB = null   # seg_sbell2（运行时 load：积木链很长，别在 ult_moves 的 preload 里拉进来）

const FREEZE0 := 0.3
const FREEZE1 := 0.9
const SHATTER := 1.2
const END_T := 2.0


static func handles(id: String) -> bool:
	return id == "sbell2"


static func aim_kind(_id: String) -> String:
	return "none"


static func aim_r(_id: String) -> float:
	return Bal.v("ult/sb_r", 420.0)


static func start(u, o, _aim: Vector2, _dir: Vector2) -> Dictionary:
	if SB == null:
		SB = load("res://scripts/characters/blocks/seg_sbell2.gd")
	if o == null or o.pos == Vector2.INF:
		return {}
	var c: Vector2 = o.pos
	var R: float = Bal.v("ult/sb_r", 420.0)
	o.play_vis_anim("skill")
	Fxr.ev(o, "sb_ult_go", {"c": c, "R": R})
	return {"id": "sbell2", "k": "sb", "no_ring": true, "no_debris": true, "c": c, "R": R, "fz": {}, "shat": false, "snow": false}


static func step(u, a: Dictionary, _dt: float) -> bool:
	var o = a.o
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	if t >= FREEZE0 and t < SHATTER:
		var rf: float = R * clampf((t - FREEZE0) / (FREEZE1 - FREEZE0), 0.0, 1.0)
		for e in u.in_circle(c, rf):
			var k: int = int(e.id)
			if a.fz.has(k):
				continue
			a.fz[k] = true
			u.hit(o, e, Bal.v("ult/sb_freeze_frac", 0.15), {"src": "落雪", "pre": true})
			if e.dead:
				continue
			if e.boss:
				o.add_cc(e, -INF, 2.0)   # Boss 不冻，减速
			else:
				SB.sb_freeze(o, e, (SHATTER - t) + Bal.v("ult/sb_freeze_tail", 0.6))
	if not a.snow and t >= FREEZE1 and o.gn.has("sb"):   # 范围内地格积满（之后照常被踩掉；S2 期间会立刻溢出）
		a.snow = true
		var mx: int = int(SB.sb_st(o).b.get("max", 5))
		for kk in SB.sb_keys_in(o, c, R * Bal.v("ult/sb_snow_k", 0.8)):
			SB.sb_add(o, kk, mx)
	if not a.shat and t >= SHATTER:
		a.shat = true
		PF.hf_on(u, a)
		u.impact(c)   # 冲击帧钉在冰面碎裂中心（全段唯一一下）
		Fxr.ev(o, "sb_ult_shatter", {"c": c})
		for e in u.in_circle(c, R):
			u.hit(o, e, Bal.v("ult/sb_shatter_frac", 0.85), {"src": "碎冰", "edge": e.pos.distance_to(c) > R * 0.85})
	return t >= END_T
