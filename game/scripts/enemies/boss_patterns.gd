extends RefCounted
## 只扩展 BossAI 的空闲窗口；预警和受击复用原有管线。
const D = preload("res://scripts/data.gd")
const Game = preload("res://scripts/game.gd")
const FINAL_TYPES := ["paranoia", "knight_boss", "ishar", "izumik"]
const OWNER_CAP := 120
const TOTAL_CAP := 240
var g: Game
func _init(game: Game) -> void:
	g = game

func try_attack(e: Dictionary, dir: Vector2, dist: float) -> bool:
	if e.dead or e.get("friendly", false) or e.get("coma", false) or e.get("invuln", false):
		return false
	if e.type in ["ishar", "izumik"] and e.phase != 2:
		return false
	if e.get("dash2", false) or e.get("combo_n", 0) > 0 or e.has("leap"):
		return false
	var moves: Array = D.ENEMIES[e.type].get("patterns", [])
	if moves.is_empty() or dist > 760.0:
		return false
	if not e.has("pattern_next"):
		e.pattern_next = g.t + 3.0
		return false
	if g.t < e.pattern_next:
		return false
	if e.has("ammo") and (e.ammo <= 0 or e.channel > 0.0):
		return false
	var index: int = int(e.get("pattern_cycle", 0)) % moves.size()
	var move: Dictionary = moves[index]
	if move.mode == "cleave" and dist > float(move.radius) + 20.0:
		index = (index + 1) % moves.size()
		move = moves[index]
		if move.mode == "cleave":
			return false
	var enhanced: bool = FINAL_TYPES.has(e.type) and e.phase == 2
	var waves: int = int(move.waves)
	if e.has("ammo"):
		waves = mini(waves, int(e.ammo))
	var end := 0.0
	for k in waves:
		var angle: float = dir.angle() + (0.10 if k % 2 else -0.10)
		var data := {"pattern_id": str(e.type) + ":" + str(index), "pattern": move,
			"wave": k, "enhanced": enhanced, "ang": angle, "cancel_dead": true,
			"name": move.name if k == 0 else "", "col": g.vfx.boss_color(e.type),
			"dmg": e.dmg * (0.65 if FINAL_TYPES.has(e.type) else 0.8),
			"true": e.type == "ishar", "track": 0.0, "lock": true}
		var shape := "cone"
		match str(move.mode):
			"fan":
				data.act = "pattern_fan"
				data.half = float(move.spread) * 0.5
				data.r = 140.0
			"ring":
				shape = "circle"
				data.act = "pattern_ring"
				data.r = 88.0
				data.gap_ang = dir.angle() + PI * 0.5 + (0.12 if k % 2 else -0.12)
				data.gap_half = float(move.gap)
			"rain":
				shape = "circle"
				data.act = "pattern_rain"
				data.r = float(move.radius)
				data.pos = g.combat.arena_clamp(g.ppos + dir.orthogonal() * (ceili(k / 2.0) * (1 if k % 2 else -1)) * 108.0, 90.0)
			"cleave":
				data.act = "pattern_cleave"
				data.r = float(move.radius)
				data.half = float(move.half)
				data.ang = dir.angle() + (-0.42 if k == 0 else 0.42)
				data.dmg = e.dmg * 1.1
		var w: Dictionary = g.bai._warn(e, shape, 0.9 + (0.0 if move.mode == "rain" else 0.6 * k), data)
		end = maxf(end, w.dur)
	e.pattern_cycle = (index + 1) % moves.size()
	e.pattern_next = g.t + end + (5.0 if FINAL_TYPES.has(e.type) else 6.5)
	e.wind = maxf(e.wind, end + 1.0)
	e.cdt = maxf(e.cdt, end + 1.0)
	return true

func resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	if e.dead or e.get("coma", false) or e.get("friendly", false) or e.stun > 0.0 or e.get("break_t", 0.0) > 0.0 or e.get("channel", 0.0) > 0.0:
		return
	var move: Dictionary = w.pattern
	if w.act in ["pattern_cleave", "pattern_rain"]:
		g.bai._warn_damage(w)
		g.vfx.boss_pattern(w)
		return
	if e.has("ammo"):
		if e.ammo <= 0:
			return
		e.ammo -= 1
		if e.ammo <= 0:
			e.ai = "melee"
	var count: int = int(move.count) + (4 if w.enhanced and not move.get("blade", false) else 0)
	var own := 0
	var total := 0
	for b in g.ebullets:
		if b.life > 0.0:
			total += 1
			if b.get("source_id", -1) == e.id:
				own += 1
	for i in count:
		if own >= OWNER_CAP or total >= TOTAL_CAP:
			break
		var angle: float
		if w.act == "pattern_ring":
			angle = w.ang + TAU * float(i) / count + float(w.wave) * PI / count
			if absf(angle_difference(angle, w.gap_ang)) < float(w.gap_half):
				continue
		else:
			angle = w.ang + lerpf(-float(move.spread) * 0.5, float(move.spread) * 0.5, float(i) / maxf(count - 1, 1))
		var blade: bool = move.get("blade", false)
		g.ebullets.append({"pos": w.pos, "vel": Vector2.from_angle(angle) * float(move.speed),
			"dmg": w.dmg, "r": 12.0 if blade else 7.0, "life": 2.8,
			"slow": false, "corrode": 0.15, "nerve": 0.0, "true": w.get("true", false),
			"kind": "boss_blade" if blade else "nova", "home": false, "boss": true,
			"atk": "物理" if e.has("ammo") or blade else "法术", "hit_cap": e.get("hit_cap", 0.0),
			"source_id": e.id, "col": w.col, "source_type": e.type})
		own += 1
		total += 1
	g.vfx.boss_pattern(w)
