## 干员多段技能帧条序列（sprites.skills.sN 的 seq：起手 / 循环 / 收招段的推进、打断、暂停，循环期间的普攻变体与残影）。
## docs/286 §4 第三批从 characters/character.gd 原样拆出，行为不变：全部 static func，第一个参数 ov = 干员实例（成员经 ov.、常量 / 静态函数经 C.）。
## 状态变量（sq_*）仍在 character.gd；_sq_kind / _sq_clear / _seq_frames 有外部调用（data_operator、测试），留在 character.gd。
extends RefCounted

const C = preload("res://scripts/characters/character.gd")


## 「段」的时长（秒）
static func _seq_len(ov: C, seg) -> float:
	var k := C.seq_anim(seg)
	if k == "" or (ov.anim_tex(k) == null and not ov.sprite_spec(k).has("frames")):
		return 0.0
	return ov.frames_seconds(k, ov._seq_frames(seg, k))


## 起手：按 skills.sN 的类型设出手窗口并进入序列；没定义 / 缺图返回 false（走单条）
static func _start_skill_seq(ov: C, aim: Vector2, i: int) -> bool:
	var q := ov.skill_seq(i)
	if q.is_empty():
		return false
	var hold: bool = q.has("hold")
	var head = q.get("intro" if hold else "start", q.get("anim", null))
	var hk := C.seq_anim(head)
	if hk == "" or (ov.anim_tex(hk) == null and not ov.sprite_spec(hk).has("frames")):
		return false
	if not hold and not q.has("start"):
		return false   # 只写 anim 的走单条（skill_anim 同义）
	if aim != Vector2.INF and absf(aim.x - ov.pos.x) > C.FACE_DEAD:
		ov._set_face(signf(aim.x - ov.pos.x))
	var spec := ov.sprite_spec(hk)
	var fps := float(spec.get("fps", 12.0))
	var frs: Array = [0] if (hold and not (head is Dictionary)) else ov._seq_frames(head, hk)
	var dur := ov.frames_seconds(hk, frs)
	var fire_at := dur
	if hold:
		dur += float(q.get("hold_ms", 250)) / 1000.0   # 出手 = 定格开始
	else:
		var fi: int = frs.find(int(spec.get("fire", 0)))
		fire_at = float(spec.get("fire_time", (float(fi if fi >= 0 else frs.size() - 1) + 0.5) / fps))
		if spec.has("logic") and frs.size() == int(spec.get("frames", 0)):
			var lw := C.logic_window(spec)
			dur = lw[0]
			fire_at = lw[1]
	_sq_pause(ov, i)
	ov.sq = q
	ov.sq_i = i
	ov.sq_ph = 1
	ov.sq_t = 0.0
	ov.sq_own = true
	ov.sq_atk = ""
	ov.sq_atk_t = -1.0
	ov.attack_phased = false
	ov.act_kind = "skill"
	ov.act_anim = hk
	ov.attack_dur = dur
	ov.attack_t = dur
	ov.fire_t = fire_at
	ov.anim_kind = hk
	ov.anim_t = 0.0
	return true


## 纯画面版起手（play_vis_skill）：同 _start_skill_seq 的序列状态，但不设出手窗口（attack_t / fire_t / act_* 不动）。
## 起手段仍 sq_own（压过同帧起手的普攻画面，与出手窗口版一致），起手播完 _tick_sq 清掉 sq_own，之后普攻画面压过循环、播完接着循环
static func _start_vis_seq(ov: C, i: int) -> bool:
	var q := ov.skill_seq(i)
	if q.is_empty():
		return false
	var hold: bool = q.has("hold")
	var head = q.get("intro" if hold else "start", null)
	var hk := C.seq_anim(head)
	if hk == "" or ov.anim_tex(hk) == null:
		return false
	_sq_pause(ov, i)
	ov.sq = q
	ov.sq_i = i
	ov.sq_ph = 1
	ov.sq_t = 0.0
	ov.sq_own = true
	ov.sq_atk = ""
	ov.sq_atk_t = -1.0
	ov.vis_anim = ""
	ov.anim_kind = hk
	ov.anim_t = 0.0
	return true


## 当前阶段的「段」
static func _sq_seg(ov: C):
	match ov.sq_ph:
		1:
			return ov.sq.get("intro" if ov.sq.has("hold") else "start", null)
		2:
			if not ov.sq.has("hold") and ov.sq.has("run"):
				var running: bool = ov.mv > (C.RUN_EXIT if ov.anim_kind == C.seq_anim(ov.sq.run) else C.RUN_ENTER)
				if running and ov.anim_tex(C.seq_anim(ov.sq.run)) != null:
					return ov.sq.run
			return ov.sq.get("hold" if ov.sq.has("hold") else "loop", null)
		3:
			return ov.sq.get("end", null)
		4:
			return ov.sq.get("enter", null)
	return null


## 当前阶段的帧号：起手 / 收势按帧表播一遍停末帧，定格 / 循环按 fps 循环
static func _sq_frame(ov: C, n: int) -> int:
	var seg = _sq_seg(ov)
	var k := C.seq_anim(seg)
	if ov.sq_ph == 2 and (k == "run" or (ov.sq.has("run") and k == C.seq_anim(ov.sq.run))):
		return int(ov.run_ph) % n   # 普通跑步与技能跑步段共享相位，不随技能计时重启；步频随移速（10-24 起非 run 帧条的跑动段也是）
	var frs: Array = [0] if (ov.sq_ph == 1 and ov.sq.has("hold") and not (seg is Dictionary)) else ov._seq_frames(seg, k)
	if frs.is_empty():
		return 0
	var elapsed := ov.attack_dur - ov.attack_t if ov.sq_ph == 1 and ov.sq_own and ov.attack_t > 0.0 and ov.act_kind == "skill" and ov.act_anim == k else ov.sq_t
	return clampi(ov.timed_frame(k, frs, elapsed, ov.sq_ph == 2), 0, n - 1)


static func _sq_interrupt(ov: C) -> void:
	if ov.sq_ph == 1 or ov.sq_ph == 3:
		ov._sq_clear()
	ov.sq_own = false
	ov.sq_atk = ""   # 新动作起手：变体作废（普攻会在 follow 里按新的出手窗口重新对齐）
	ov.sq_atk_t = -1.0


static func _sq_pause(ov: C, i: int) -> void:
	for n in range(ov.sq_paused.size() - 1, -1, -1):
		if ov.sq_paused[n].i == i:
			ov.sq_paused.remove_at(n)
	if ov.sq_i != i and ov.sq_ph in [2, 4] and not ov.sq.has("hold"):
		ov.sq_paused.append({"q": ov.sq, "i": ov.sq_i, "ph": ov.sq_ph, "t": ov.sq_t})


## follow() 每帧：推进序列阶段（纯画面）
static func _tick_sq(ov: C, dt: float) -> void:
	if ov.sq_ph == 0:
		return
	var hold: bool = ov.sq.has("hold")
	# 施法后的进入段被其他动作遮住时暂停，不改变那些动作的逻辑窗口。
	if ov.sq_ph != 4 or (ov.attack_t <= 0.0 and ov.vis_anim == ""):
		ov.sq_t += dt
	match ov.sq_ph:
		1:
			var head = ov.sq.get("intro" if hold else "start")
			var n1: float = (1.0 / float(ov.sprite_spec(C.seq_anim(head)).get("fps", 12.0))) if (hold and not (head is Dictionary)) else _seq_len(ov, head)
			if ov.sq_t >= n1:
				ov.sq_t = 0.0
				if not hold:
					ov.sq_own = false   # start 段结束：出手窗口版此时 attack_t 也正好到 0；纯画面版（play_vis_skill）之后让普攻画面压过循环。hold 的出手窗口覆盖整个定格，保留
				if hold or ov.skill_active_left(ov.sq_i) > 0.0:
					ov.sq_ph = 4 if not hold and _seq_len(ov, ov.sq.get("enter")) > 0.0 else 2
				else:
					_sq_end(ov)
		2:
			if hold:
				if ov.sq_t >= float(ov.sq.get("hold_ms", 250)) / 1000.0:
					ov._sq_clear()
			elif ov.skill_active_left(ov.sq_i) <= 0.0:
				ov.sq_t = 0.0
				_sq_end(ov)
		4:
			if ov.skill_active_left(ov.sq_i) <= 0.0:
				ov.sq_t = 0.0
				_sq_end(ov)
			elif ov.sq_t >= _seq_len(ov, ov.sq.get("enter")):
				ov.sq_t = 0.0
				ov.sq_ph = 2
		3:
			if ov.sq_t >= _seq_len(ov, ov.sq.get("end")):
				ov._sq_clear()
	_tick_sq_atk(ov, dt)


## 循环期间的普攻变体（sq.attack）：普攻出手窗口开着（act_anim = "attack"）就从这次起手对齐，attack_t 归零后继续播到末帧再清掉
static func _tick_sq_atk(ov: C, dt: float) -> void:
	var k := _sq_atk_kind(ov)
	if k == "":
		ov.sq_atk = ""
		ov.sq_atk_t = -1.0
		return
	if ov.attack_t > 0.0 and ov.act_kind == "attack" and ov.act_anim == "attack" and not ov.sq_own:
		var el: float = ov.attack_dur - ov.attack_t   # 这次普攻已播秒数
		if ov.sq_atk_t < 0.0 or el < ov.sq_atk_t - 0.0001:
			ov.sq_atk = k   # 新一次普攻：从头对齐（变体比出手窗口短时播完清掉，同一次普攻不再触发）
		ov.sq_atk_t = el
	elif ov.sq_atk != "":
		ov.sq_atk_t += dt
	else:
		return
	if ov.sq_atk == "":
		return
	var spec := ov.sprite_spec(ov.sq_atk)
	var n := float(spec.get("frames", ov.anim_hframes(ov.anim_tex(ov.sq_atk), ov.sq_atk)))
	if (ov.sq_atk_t >= ov.attack_dur) if ov.attack_phased else (ov.sq_atk_t + _sq_atk_off(ov) >= ov.frames_seconds(ov.sq_atk, range(int(n)))):
		ov.sq_atk = ""   # 播完回循环


## 移动只暂时让出画面，保留变体时钟；同轮停下可接着收势。
static func _sq_atk_yield(ov: C) -> bool:
	if ov.sq_atk == "" or ov.sq_ph != 2 or not ov.sq.has("run") or ov.sq_atk_t < ov.attack_fire_at:
		return false
	if ov.anim_tex("move_" + ov.sq_atk) != null:
		return false   # 变体有跑动版：不让位，_move_swap 换上（10-24 塞雷娅跑动拳击）
	var spec := ov.sprite_spec(ov.sq_atk)
	if _sq_atk_frame(ov, int(spec.get("frames", ov.anim_hframes(ov.anim_tex(ov.sq_atk), ov.sq_atk)))) <= int(spec.get("fire", 0)):
		return false   # 出手帧播完再让（10-24 docs/140，同 act_anim_yield）
	var run_slot := C.seq_anim(ov.sq.run)
	return ov.anim_tex(run_slot) != null and ov.mv > (C.RUN_EXIT if ov.anim_kind == run_slot else C.RUN_ENTER)


## 当前序列循环阶段可用的普攻变体帧条（"" = 没写 / 缺图 / 不在循环阶段）
static func _sq_atk_kind(ov: C) -> String:
	if ov.sq_ph != 2 or ov.sq.has("hold"):
		return ""
	var k := C.seq_anim(ov.sq.get("attack", null))
	return k if k != "" and ov.anim_tex(k) != null else ""


## 变体时间轴相对普攻起手的偏移：变体 fire 帧中点对齐普攻条（attack 槽）的出手时刻；变体时间 = sq_atk_t + 偏移
static func _sq_atk_off(ov: C) -> float:
	var vs := ov.sprite_spec(ov.sq_atk)
	var vfps := float(vs.get("fps", 12.0))
	var v_fire: float = float(vs.get("fire_time", (float(vs.get("fire", 0)) + 0.5) / vfps))
	var a := ov.sprite_spec("attack")
	var a_fire: float = float(a.get("fire_time", (float(a.get("fire", 0)) + 0.5) / float(a.get("fps", 12.0)))) if a.has("fire") else ov.attack_dur * 0.5
	return v_fire - a_fire


static func _sq_atk_frame(ov: C, n: int) -> int:
	if ov.attack_phased:
		return ov.attack_phase_frame(n, int(ov.sprite_spec(ov.sq_atk).get("fire", 0)), ov.sq_atk_t, ov.sq_atk)
	if ov.sprite_spec(ov.sq_atk).has("frame_durations"):
		return ov.timed_frame(ov.sq_atk, range(n), maxf(0.0, ov.sq_atk_t + _sq_atk_off(ov)))
	var fps := float(ov.sprite_spec(ov.sq_atk).get("fps", 12.0))
	return clampi(int(maxf(0.0, ov.sq_atk_t + _sq_atk_off(ov)) * fps), 0, n - 1)


static func _sq_end(ov: C) -> void:
	if _seq_len(ov, ov.sq.get("end")) > 0.0:
		ov.sq_ph = 3
	else:
		ov._sq_clear()


static func _tick_sq_shadow(ov: C, dt: float) -> void:
	if ov.sq_ph != 0:
		ov.sq_shadow = Vector2(float(ov.sq.get("shadow", 1.0)), float(ov.sq.get("shadow_a", 1.0)))
	var up: bool = ov.sq_ph == 2 or ov.sq_ph == 4 or (ov.sq_ph == 1 and not ov.sq.has("enter"))
	ov.sq_air = move_toward(ov.sq_air, 1.0 if up else 0.0, dt / 0.25)
