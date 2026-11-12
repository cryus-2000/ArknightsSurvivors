## 星熊（docs/254，照 docs/246 斯卡蒂的做法）
## 普攻「盾斧斩」= 腰高钝头刀痕（精一盾缘崩钢屑、精二暖金副刃 + 金火星；精二另有「般若回旋」锯盾）；
## S1「战意」= 立起的下劈弧 + 裂网冲击环 + 碎石（精一尘墙、精二裂缝熔成暖金）；
## S2「荆棘」= 起手一圈地刺破土 + 每斩留的热砂（只画边 + 内边 + 几点热光）；
## S3「力之锯」= 起手腰高青绿弧旋起 + 直线撕裂（贴地撕裂沟 + 低处锯线 + 远端暖金火星），持续时脚下一圈转动的齿印。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")


static func _ev_hsg(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG hsg %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("line", false):   # 力之锯：直线斩（seg_hoshiguma.exec_line 的钩子）
				var ang: float = float(d.get("ang", 0.0))
				var L: float = float(d.get("len", 220.0))
				var dv := Vector2.from_angle(ang)
				if raw:
					pv._push({"k": "hsg_raw_rip", "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (L * 0.5) / 110.0, "oid": str(o.id)})
				else:
					pv._add_dir(o, "hsg_rip_l%d" % pv._bucket(L * 0.5, [110, 140]), o.pos, ang)
				pv._cuts(o, es, 2, 3)
				pv._burst_m(o, R, p, o.pos + dv * L * 0.9 + Vector2(0, -12), o.pos.y + dv.y * L * 0.9, es, 6, "shard", 130.0, 0.5)
				return
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 60.0))
				match src:
					"举盾反击":   # S1 战意：下劈 + 裂网冲击环（判定圈以星熊为心）
						var fl: bool = float(o.face) < 0.0
						if raw:
							pv._push({"k": "hsg_raw_slam_e%d" % t, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 75.0, "oid": str(o.id)})
						else:
							var sk: String = "hsg_slam_r%d_e%d" % [pv._bucket(r * 0.5, [75, 95]), t]
							pv._push({"k": sk + "_up", "t0": g.t, "gp": pv._snap(c), "flip": fl, "ly": "up", "oid": str(o.id), "fop": true})   # 下劈弧跟人；裂网冲击环（_gd）是落在地上的，留在原地
							pv._push({"k": sk + "_gd", "t0": g.t, "gp": pv._snap(c), "flip": fl, "ly": "gd", "oid": str(o.id)})
						pv._cuts(o, es, t, 4)
						pv._burst_m(o, R, p, c + Vector2(-30.0 if fl else 30.0, -6), c.y + 2.0, es, 8 + 3 * t, "rock", 0.0, 0.0, false)
						if pv.mode() == 1:   # 落地那一下：一盏照地灯 200 / 0.80（docs/270 §3「爆发」140–240 / 0.6–0.9；协调人 11-05 定：有没有打中都挂），打中时挂在第一只敌人身上，没打中挂在落点
							R._light(o, (es[0].pos + Vector2(0, -float(es[0].r) * 0.5)) if not es.is_empty() else c + Vector2(-30.0 if fl else 30.0, -6), 200.0, 0.8, 0.12, p.light)
					"热砂", "热砂沸腾":
						pass   # 热砂每 0.5 秒结算一次：画面由区域本身（_floor_hsg 读 o.fields）表现，不逐跳画
					_:   # 般若之重 / 盾墙反震：贴地冲击环
						if not raw:
							pv._push({"k": "hsg_pulse_gd", "t0": g.t, "gp": pv._snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
						pv._burst_m(o, R, p, c + Vector2(0, -8), c.y + 2.0, es, 3, "rock", 110.0, 0.4)
				return
			# 锥形：盾斧斩（普攻）
			var ang2: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 94.0))
			var dv2 := Vector2.from_angle(ang2)
			pv._add(o, "hsg_sweep_r%d_e%d" % [pv._bucket(r2 * 0.5, [47, 56, 66]), t], o.pos, ang2, r2, raw, "hsg_raw_sweep_e%d" % t, 47.0)
			var el_st = o.get("el")
			var stance_on: bool = el_st is Dictionary and el_st.get("timed", {}).has("stance") and float(el_st.timed.stance.get("until", 0.0)) > float(g.t)   # 只读状态（同 ob_elite.el_buff_on）
			if not raw and t >= 1 and stance_on and Bal.v("fx/node_cue", 1.0) > 0.0:   # 反击架势（docs/310 §4.2，卡面「刀光转为暗红」）：立起层换暗红色阶的帧条（tools/hsg_stance_recolor.py）
				for k in range(pv.items.size() - 1, maxi(-1, pv.items.size() - 3), -1):
					var it2: Dictionary = pv.items[k]
					if str(it2.ly) == "up" and str(it2.oid) == str(o.id) and it2.get("slash", false):
						var sk2: String = str(it2.k).replace("_up_d", "_stance_up_d")
						if not pv._meta(sk2).is_empty():
							it2.k = sk2
						break
			if not raw:
				_follow_last(pv, o, 2)   # 刀痕（立起 + 投影）跟着星熊走
			pv._cuts(o, es, t, 2)
			pv._burst_m(o, R, p, o.pos + dv2 * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv2.y * r2 * 0.6 * 0.72, es, 2 + t, "shard" if t >= 1 else "rock", 90.0, 0.35)
		"cover":   # 技能连携 v2「举盾」：队长身侧立起鬼面大盾 1.5 秒（盾跟着队长走：fol = 相对队长的偏移）
			var sd2: Vector2 = d.get("side", Vector2.RIGHT)
			var off: Vector2 = sd2 * 46.0
			if raw:
				pv._push({"k": "hsg_raw_slam_e0", "t0": g.t, "gp": g.ppos + off, "ly": "raw", "rot": 0.0, "sc": g.PX * 30.0 / 75.0, "oid": str(o.id)})
			else:
				pv._push({"k": "hsg_cover_up", "t0": g.t, "gp": pv._snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "up", "oid": str(o.id)})
				pv._push({"k": "hsg_cover_gd", "t0": g.t, "gp": pv._snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "gd", "oid": str(o.id)})
			pv._burst_m(o, R, p, g.ppos + off + Vector2(0, -20), g.ppos.y + off.y + 2.0, [], 6, "shard", 140.0, 0.6)
		"combo_dash":   # 连携技冲刺：沿途几颗碎石（代替通用干员色拖影）
			if pv.mode() == 1:
				var a0: Vector2 = d.get("from", o.pos)
				var b0: Vector2 = d.get("to", o.pos)
				for k in 3:
					var q: Vector2 = a0.lerp(b0, 0.25 + 0.3 * k)
					R._grains(o, q + Vector2(0, -4), q.y + 2.0, "rock", 2, {"tier": 1})
		"combo":   # 连携技「举盾推挡」：盾落点立起大盾往外推 + 队长脚下冲击环与放射推痕
			var cc: Vector2 = d.get("c", o.pos)
			var at: Vector2 = d.get("at", o.pos)
			var sd: Vector2 = d.get("side", Vector2.RIGHT)
			if raw:
				pv._push({"k": "hsg_raw_slam_e1", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": g.PX * 70.0 / 75.0, "oid": str(o.id)})
			else:
				var dk: Array = pv.pick_dir(sd.angle() if sd.length() > 0.5 else 0.0)
				pv._push({"k": "hsg_shove_up_d%d" % dk[0], "t0": g.t, "gp": pv._snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
				pv._push({"k": "hsg_shove_gd", "t0": g.t, "gp": pv._snap(cc), "flip": false, "ly": "gd", "oid": str(o.id)})
			pv._burst_m(o, R, p, cc + Vector2(0, -10), cc.y + 2.0, d.get("es", []), 8, "rock", 200.0, 0.8)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:   # 荆棘起手：一圈地刺破土（身后半圈排在她身后、身前半圈排在她身前）
				var tt: int = maxi(t, 1)
				if raw:
					pv._push({"k": "hsg_raw_thorns_e%d" % tt, "t0": g.t, "gp": o.pos + Vector2(0, -8), "ly": "raw", "rot": 0.0, "sc": g.PX, "oid": str(o.id)})
				else:
					pv._push({"k": "hsg_thorns_e%d_back_up" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": -8.0})
					pv._push({"k": "hsg_thorns_e%d_front_up" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": 4.0})
					pv._push({"k": "hsg_thorns_e%d_gd" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if pv.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -20), o.pos.y, "shard", 6 + 3 * tt, {"tier": tt})
					R._light(o, o.pos + Vector2(0, -10), 120.0, 0.5, 0.15, p.accent)
			elif i == 2:   # 力之锯起手：腰高三道青绿弧旋起 + 脚下冲击环
				if raw:
					pv._push({"k": "hsg_raw_slam_e2", "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": g.PX * 50.0 / 75.0, "oid": str(o.id)})
				else:
					pv._push({"k": "hsg_s3cast_up", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fop": true})   # 身边旋起的青绿弧跟人
					pv._push({"k": "hsg_s3cast_gd", "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if pv.mode() == 1:
					R._light(o, o.pos + Vector2(0, -20), 140.0, 0.6, 0.15, p.light)


## 地面层（星熊）：贴地件、热砂（读 o.fields，循环 + 淡入淡出）、力之锯持续时脚下齿印、锯盾影子
static func _floor_hsg(pv: P, o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = clampi(pv.tier(o), 1, 2)
	for f in o.fields:
		if not f.get("sand", false):
			continue
		var fa: float = clampf((float(f.n) * float(f.every) - float(f.t)) / 0.4, 0.0, 1.0) * clampf(float(f.t) / 0.15, 0.0, 1.0)
		if fa <= 0.0:
			continue
		var rk: int = 40 if float(f.r) >= 70.0 else 30
		pv._draw_strip(cv, "hsg_sand%d_e%d_gd" % [rk, t], pv.frame_of(0.0), pv._snap(f.pos), false, false, Color(1, 1, 1, fa))
	if o.skill_active_left(2) > 0.0:
		pv._draw_strip(cv, "hsg_s3aura_gd", pv.frame_of(0.0), pv._snap(o.pos + Vector2(0, 2)), false, false)
	for it in pv.items_for(id):
		if str(it.ly) == "gd":
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), pv._gp(it), it.flip, true)
	for bm in _booms(pv, o):
		pv._draw_strip(cv, "hsg_saw_gd", pv.frame_of(0.0), _boom_gp(pv, o, bm), false, false)
	for qv in _qi_volleys(pv, o):
		pv._draw_strip(cv, qv.k + "_gd_d%d" % qv.d, int(qv.f), qv.gp, qv.flip, true)


## 般若回旋：读玩法状态 o.el.boom（往返弹体）
static func _booms(pv: P, o) -> Array:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or not el.has("boom"):
		return []
	return el.boom


## 弹体此刻离星熊的距离（同 ob_elite._el_boom_d，纯函数抄一份，只读）
static func _boom_d(bm: Dictionary) -> float:
	var t: float = float(bm.t)
	var to: float = float(bm.to)
	if t < to:
		var k: float = t / maxf(0.01, to)
		return float(bm.L) * (1.0 - (1.0 - k) * (1.0 - k))
	if t < to + float(bm.hold):
		return float(bm.L)
	var k2: float = clampf((t - to - float(bm.hold)) / maxf(0.01, float(bm.tb)), 0.0, 1.0)
	return float(bm.L) * (1.0 - k2 * k2)


## 锯盾的地面点：统一节拍时每 1/15 秒跳一格（记在弹体字典的画面专用键 _pxq，玩法不读）
static func _boom_gp(pv: P, o, bm: Dictionary) -> Vector2:
	var g = pv.g
	var p: Vector2 = o.pos + bm.dir * _boom_d(bm)
	if not is_equal_approx(pv.clock(), 15.0):
		return p
	var tick: int = int(floor(g.t * 15.0))
	var q = bm.get("_pxq")
	if q == null or int(q[0]) != tick:
		q = [tick, pv._snap(p)]
		bm["_pxq"] = q
	return q[1]


## 后期剑气（growth/late_shape → vis_growth._fire_qi）：同一次出手的几道剑气合成一道盾击冲击波（不碎）。
## 只读玩法状态 o.vg.qi；按出手时刻分组：位置 / 方向取平均，横向宽度按道数取 1 / 2 / 3+ 三档。
## 帧：出手第一拍热白（0）→ 常态（1）→ 剩余寿命 < 0.07 秒碎开（2）。位置按 15 fps 节拍跳格（记在剑气字典的画面专用键 _pxq，玩法不读）
static func _qi_volleys(pv: P, o) -> Array:
	var g = pv.g
	var out: Array = []
	if pv.mode() != 1 or o.vg.is_empty() or not o.vg.has("qi") or o.vg.qi.is_empty():
		return out
	var grp: Dictionary = {}
	for q in o.vg.qi:
		var key: int = int(round((g.t - float(q.t)) * 60.0))
		if not grp.has(key):
			grp[key] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0, "t": float(q.t), "life": float(q.life), "qs": []}
		var e: Dictionary = grp[key]
		e.p += pv._qpos(q)
		e.v += (q.v as Vector2).normalized()
		e.n += 1
		e.life = minf(float(e.life), float(q.life))
		e.qs.append(q)
	var t: int = pv.tier(o)
	var keys: Array = grp.keys()
	keys.sort()
	keys.reverse()
	for key in keys.slice(0, 2):   # 同屏至多两组（最新两次出手）
		var e: Dictionary = grp[key]
		var n: int = int(e.n)
		var S: int = 10 if n <= 1 else (16 if n == 2 else 22)
		var dk: Array = pv.pick_dir((e.v as Vector2).angle())
		var f: int = 0 if float(e.t) < 1.0 / 15.0 else (2 if float(e.life) < 0.07 else 1)
		out.append({"k": "%s_qi_s%d_e%d" % ["sg" if str(o.id) == "siege" else "hsg", S, t], "d": dk[0], "flip": dk[1], "gp": pv._snap(e.p / float(n)), "f": f})
	return out


## 最后 n 件标成「跟着出手的干员走」（fop）
static func _follow_last(pv: P, o, n: int) -> void:
	for i in range(maxi(0, pv.items.size() - n), pv.items.size()):
		if str(pv.items[i].oid) == str(o.id):
			pv.items[i]["fop"] = true
