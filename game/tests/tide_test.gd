extends Node
## 潮位阶梯（docs/109 §5 / docs/71）单元测试（check.py 场景回归 tide）：16 级；锚点 0 / 4 与旧标准 / Ⅳ 逐键相等，8 = 旧 Ⅷ + 寒流两键；
## 严格累加（每级只往更难推：倍率键不降、开关不关、提前类时间不推后）；--tier=0/1/2 仍是旧表。
const D = preload("res://scripts/data.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TIDE: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


## 「更难」方向：大于 1 难的键越大越难；小于 1 难的键越小越难
const DOWN_HARD := ["max_hp", "oil_drop", "ingot", "boss_warn", "hunt_dur", "hunt_ring_hp", "beacon_every", "elite_interval"]


func run() -> void:
	check(D.DIFFICULTY_TIERS.size() == 16, "潮位应为 16 级")
	for i in 16:
		check(int(D.DIFFICULTY_TIERS[i].level) == i, "第 %d 级 level" % i)
	check(D.dmod_for_tier(0) == D.dmod_for_legacy(0), "潮位 0 = 旧标准")
	# 三档预设（docs/109 §15）：标准 / 困难 = 纯潮位表；极限 = 潮位 10 的表上小怪生命 / 伤害再乘 enemy_scale；其余键与潮位 10 相同；--tide=10 走同一张表
	check(D.dmod_for_preset(0) == D.dmod_for_tier(0) and D.dmod_for_preset(1) == D.dmod_for_tier(5), "标准 / 困难预设 = 潮位 0 / 5 的表")
	var m10 := D.dmod_for_tier(10)
	var px := D.dmod_for_preset(2)
	var ks: float = float(D.DIFF_PRESETS[2].get("enemy_scale", 1.0))
	check(ks < 1.0 and is_equal_approx(float(px.enemy_hp), float(m10.enemy_hp) * ks) and is_equal_approx(float(px.enemy_dmg), float(m10.enemy_dmg) * ks), "极限预设：小怪生命 / 伤害 × enemy_scale（%s）" % ks)
	for k in m10:
		if not k in D.PRESET_SCALE_KEYS:
			check(px[k] == m10[k], "极限预设其余键同潮位 10：" + str(k))
	check(D.dmod_for_tide(10) == px and D.dmod_for_tide(5) == D.dmod_for_tier(5) and D.dmod_for_tide(8) == D.dmod_for_tier(8), "--tide=10 带极限档修正，5 / 8 为纯潮位表")
	check(D.dmod_for_tier(4) == D.dmod_for_legacy(1), "潮位 4 = 旧 Ⅳ")
	var m8 := D.dmod_for_legacy(2)
	m8.ctrl_start = 300.0
	m8.frost_max = 2.0
	check(D.dmod_for_tier(8) == m8, "潮位 8 = 旧 Ⅷ + 寒流两键")
	for i in range(1, 16):
		var a := D.dmod_for_tier(i - 1)
		var b := D.dmod_for_tier(i)
		for k in a:
			if k in ["hunt_dur", "hunt_ring_hp", "beacon_every", "boss_fight_enemy_hp"]:
				continue   # 补偿键（docs/71 §2.1：跟着规则走的放宽）
			var va := float(a[k])
			var vb := float(b[k])
			if va == vb:
				continue
			if k in DOWN_HARD:
				check(vb <= va, "潮位 %d 的 %s 变易：%s → %s" % [i, k, va, vb])
			elif k in ["ctrl_start", "affix_start"]:
				check(va < 0.0 or vb <= va, "潮位 %d 的 %s 推后" % [i, k])
			elif k == "frost_max":
				check(va < 0.0 or vb <= va, "潮位 %d 寒霜层数变多" % i)
			elif k == "final_stop_mobs":
				check(vb == 0.0, "潮位 %d 最终 Boss 停刷" % i)
			else:
				check(vb >= va, "潮位 %d 的 %s 变易：%s → %s" % [i, k, va, vb])
	print("TIDE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
