## 干员响应动作（docs/118）：由队长的动作触发的附加效果，写在干员 json 的 blocks.response（触发积木数组）。
## 四类触发源：
##   trig.on_leader_dash   队长冲刺起步（g.dash_t 上升沿）：cd
##   trig.passive + cond   队长站定：条件 still >= 秒（g.leader_still_t，队长连续没移动的秒数；移动 / 冲刺 / 被定身清零），
##                         常驻效果在 data_operator._sustain 里随条件收放（同 trait 的 passive）
##   trig.on_leader_skill  队长自己的技能出手（g.leader_skill_n 上升）：skill（只认这个序号，缺省全部）、cd
##   trig.on_stance        指挥模式切换（squad.stance_log 增长）：to = guard / roam / recall、cd
## 每条可写 hint（玩家可见的短名，docs/76）：触发 / 生效那一刻在干员头顶飘一次职业色小字。
## 总开关 balance.json response.on（缺省 1）：0 = 响应段整段不求值、常驻条目不收集，TRACE 与没有响应时逐行相同。
## 不抽随机数；冷却按 g.t 记在 o.rsp 里（只本干员可见）。
extends RefCounted

const BalS = preload("res://scripts/core/balance.gd")
const EVENT_TAGS := ["trig.on_leader_dash", "trig.on_leader_skill", "trig.on_stance"]
const STANCES := {"guard": 0, "roam": 1, "recall": 2}
const _ED := {}
const _EA := []


static func on() -> bool:
	return BalS.vi("response/on", 1) > 0


## 每帧（data_operator.update 在常驻积木之后调）：三类事件触发器求值；站定类只负责在生效那一刻飘提示
static func tick(o) -> void:
	var rs: Array = o.B.get("response", _EA)
	if rs.is_empty() or not on() or o.pos == Vector2.INF or o.g.demo_op != "":
		return
	var g = o.g
	var st: Dictionary = o.rsp
	var dash_up: bool = float(g.dash_t) > 0.0 and float(st.get("prev_dash", 0.0)) <= 0.0
	st["prev_dash"] = float(g.dash_t)
	var skill_n: int = int(g.leader_skill_n)
	var skill_up: bool = skill_n != int(st.get("prev_skill", skill_n))
	st["prev_skill"] = skill_n
	var log: Array = g.squad.stance_log if g.squad != null and "stance_log" in g.squad else _EA
	var stance_up: bool = log.size() > int(st.get("prev_stance", log.size()))
	st["prev_stance"] = log.size()
	for t in rs:
		var tag: String = str(t.get("_tag", ""))
		var fire := false
		match tag:
			"trig.on_leader_dash":
				fire = dash_up
			"trig.on_leader_skill":
				fire = skill_up and (not t.has("skill") or int(t.skill) == int(g.leader_skill_i))
			"trig.on_stance":
				fire = stance_up and int(log[-1][1]) == int(STANCES.get(str(t.get("to", "roam")), 1))
			"trig.passive":
				_hint_edge(o, t)
				continue
		if not fire or not o.ObCore.cond_true(o, t.get("cond", _ED)):
			continue
		var k: String = "cd%d" % int(t.get("_uid", 0))
		if g.t < float(st.get(k, -99.0)):
			continue
		st[k] = g.t + float(t.get("cd", 0.0))
		o._exec_list(t.get("do", _EA))
		hint(o, t)


## 站定类：条件由假变真的那一帧飘一次提示（效果本身由 _sustain 随条件收放）
static func _hint_edge(o, t: Dictionary) -> void:
	if not t.has("hint"):
		return
	var k: String = "on%d" % int(t.get("_uid", 0))
	var now: bool = o.ObCore.cond_true(o, t.get("cond", _ED))
	if now and not o.rsp.get(k, false):
		hint(o, t)
	o.rsp[k] = now


## 头顶职业色小字（纯画面）
static func hint(o, t: Dictionary) -> void:
	if not t.has("hint") or o.g.vfx == null:
		return
	o.g.vfx.add_text(o.pos + Vector2(0, -78), str(t.hint), o.col().lerp(Color.WHITE, 0.35), 13)


## 校验（ob_check 转来）：on_leader_skill / on_stance 的参数与 do；on_leader_dash 由德克萨斯段校验
static func validate(b: Dictionary, p: String, tag: String, ctx: Dictionary, F) -> void:
	F._num(b, "cd", p, ctx, false, 0.0, 60.0)
	match tag:
		"trig.on_leader_skill":
			F._num(b, "skill", p, ctx, false, 0.0, 2.0)
		"trig.on_stance":
			if not str(b.get("to", "")) in STANCES:
				ctx.errs.append(p + ".to 只能是 guard / roam / recall")
	F._list(b.get("do", []), p + ".do", "instant", ctx)


## blocks.response 段整体（ob_check 转来）：必须是触发积木数组；站定类只能是 trig.passive（带 still 条件），事件类只能是上面三种
static func validate_section(arr, ctx: Dictionary, F) -> void:
	if not (arr is Array):
		ctx.errs.append("blocks.response 必须是数组")
		return
	for i in arr.size():
		var b = arr[i]
		var p := "blocks.response[%d]" % i
		F._trig(b, p, ctx)
		if b is Dictionary and b.has("trig") and not ("trig." + str(b.trig)) in EVENT_TAGS + ["trig.passive"]:
			ctx.errs.append(p + "：响应只能用 on_leader_dash / on_leader_skill / on_stance，或带 still 条件的 passive")
		if b is Dictionary and b.has("hint") and not (b.hint is String and str(b.hint).length() <= 6):
			ctx.errs.append(p + ".hint 须是至多 6 个字的短名")
