extends RefCounted
## B站 Toy「支持作者」奖励（docs/313，用户 11-07 定）：只在 Toy 版出现，附加奖励、不设任何门槛（docs/99：免交互可玩、主线不强制关注）。
##   关注作者 → 一次性送 REWARD 张寻访凭证 + 专属分享卡边框「罗德岛」；
##   三连指定视频（点赞 + 投币 + 收藏，balance toy/support_bvid）→ 一次性 REWARD 张凭证 + 专属分享卡边框「深海」。
##   11-08 用户：两项各送一种边框（frames / FRAME_OF）；云存档 tsup 取并集，合并后领过哪项就有哪种。
##   11-08 用户：两项合成一个入口（entry_label），浮层里并排各自领取；support_bvid 留空时三连照样列出、写「PV 发布后开放」并置灰（triple_open）。
## 不做称号；不解锁干员 / 数值 / 难度。领取状态 Cfg.toy_support（本地存档 + 云存档 prog.tsup 取并集，docs/89）；
## 前端校验可被破解，无所谓（奖励本就是附加的）。SDK 查询在 tools/web/support.js（window.__sySupport），这里只管规则与记账。
## 11-16 用户：满足条件不再直接到账——查到满足只记成「可领取」（ready，本次运行有效，不进存档），玩家点「领取」才发券（claim）；
##   标题页进 Toy 版时后台查一次（probe），满足就在「支持作者」上挂「可领取」角标。已领过的（Cfg.toy_support）照旧「已领取」。

const Roster = preload("res://scripts/core/roster.gd")
const Bal = preload("res://scripts/core/balance.gd")

const REWARD := 5
const ITEMS := ["follow", "triple"]


static var bv_test = null    # 测试用：非 null 时顶替 support_bvid（toy_support_test 验「PV 发布后开放」）
static var ready: Array = []      # 查到已满足、还没点领取的项（只在本次运行里记；重载页面后由 probe 重新查）
static var _probed := false
static var _js = null
static var _cbs: Array = []       # JavaScriptBridge 回调要一直持有


## 三连检测的视频（PV 发了再填）；留空 = 三连那一项置灰、写「PV 发布后开放」
static func bvid() -> String:
	if bv_test != null:
		return str(bv_test)
	for a in Cfg.dev_args():
		if a.begins_with("--toybv="):
			return a.substr(8)
	var sec = Bal.sec("toy")
	return str(sec.get("support_bvid", "")).strip_edges() if sec is Dictionary else ""


## 关注那一项（toy/support_follow，1 = 显示）
static func follow_on() -> bool:
	return Bal.v("toy/support_follow", 1.0) > 0.0


## 当前列出的奖励项：三连一直列出（11-08 用户：让玩家知道有这一项），没配视频时只是不能领（triple_open）
static func items() -> Array:
	var out: Array = []
	if follow_on():
		out.append("follow")
	out.append("triple")
	return out


## 三连那一项开放了没有（配了 support_bvid）
static func triple_open() -> bool:
	return bvid() != ""


## 这一项现在能不能去领（没领过、且已开放）
static func claimable(id: String) -> bool:
	return not claimed(id) and (id != "triple" or triple_open())


static func short_name(id: String) -> String:
	return "关注" if id == "follow" else "三连"


## 结算页 / 寻访页入口的统一文案（标题页写「支持作者」+ 角标）：「支持作者：关注 +5 · 三连 +5 张寻访凭证」；领过的项不再写
static func entry_label() -> String:
	if ready_tickets() > 0:
		return "支持作者：可领取 %d 张寻访凭证" % ready_tickets()
	var parts: Array = []
	for id in items():
		if not claimed(id):
			parts.append("%s +%d" % [short_name(id), REWARD])
	if parts.is_empty():
		return "支持作者"
	return "支持作者：%s 张寻访凭证" % " · ".join(PackedStringArray(parts))


static func is_toy() -> bool:
	return preload("res://scripts/core/feedback.gd").is_toy()


## 入口要不要出现：只在 Toy 版、且至少有一项奖励
static func enabled() -> bool:
	return is_toy() and not items().is_empty()


static func claimed(id: String) -> bool:
	return id in Cfg.toy_support


## 还有没领的奖励（三连没开放也算：入口照样出现，让玩家知道有这一项）
static func pending() -> bool:
	if not enabled():
		return false
	for id in items():
		if not claimed(id):
			return true
	return false


## 还没领的凭证总数（标题页「支持作者」角标「领 N 张」）：两项都算、最多 10 张（三连没开放也算）；不在 Toy 版 / 都领过 = 0
static func pending_tickets() -> int:
	if not enabled():
		return 0
	var n := 0
	for id in items():
		if not claimed(id):
			n += REWARD
	return n


## 已满足、等玩家点领取的凭证数（标题页「可领取」角标、浮层「领取 N 张寻访凭证」按钮）
static func ready_tickets() -> int:
	if not enabled():
		return 0
	var n := 0
	for id in items():
		if is_ready(id):
			n += REWARD
	return n


## 这一项查到满足、还没领
static func is_ready(id: String) -> bool:
	return id in ready and claimable(id)


## 分享卡专属边框（11-08 用户：两项各送一种）：关注 → 「罗德岛」ri，三连 → 「深海」deep（share_card.FRAMES）
const FRAME_OF := {"follow": "ri", "triple": "deep"}


## 已解锁的相框 id（按 ITEMS 顺序）
static func frames() -> Array:
	var out: Array = []
	for id in ITEMS:
		if claimed(id):
			out.append(FRAME_OF[id])
	return out


static func frame_name(id: String) -> String:
	return "罗德岛" if id == "follow" else "深海"


static func frame_unlocked() -> bool:
	return not frames().is_empty()


## 一项的查询结果 → 只判定，不发券（11-16 用户：满足了也要玩家点一下领取）。status：yes / no / unsupported / login / err（support.js 的约定）；
## detail：triple 缺的几项（like,coin,fav）。返回 {"ready": 是否可领取, "msg": 给玩家看的一句}
static func apply(id: String, status: String, detail := "") -> Dictionary:
	var name: String = "关注作者" if id == "follow" else "三连视频"
	if claimed(id):
		return {"ready": false, "msg": "%s的奖励已经领取过了" % name}
	if id == "triple" and not triple_open():
		return {"ready": false, "msg": "PV 发布后开放"}
	match status:
		"yes":
			if not (id in ready):
				ready.append(id)
			return {"ready": true, "msg": "可以领取了"}
		"no":
			if id == "follow":
				return {"ready": false, "msg": "还没有关注作者"}
			var miss: Array = []
			for k in detail.split(",", false):
				miss.append({"like": "点赞", "coin": "投币", "fav": "收藏"}.get(k, k))
			return {"ready": false, "msg": "三连还差：%s" % "、".join(PackedStringArray(miss)) if not miss.is_empty() else "还没有完成三连"}
		"unsupported":
			return {"ready": false, "msg": "请在 B站 App 中打开"}
		"login":
			return {"ready": false, "msg": "请先登录 B站账号"}
	return {"ready": false, "msg": "暂时无法查询，请稍后再试"}


## 领取一项：只有查到满足（ready）且没领过才发；先记领取再加券、立即存档（重复点 / 重载都不会再发）。返回本次发的凭证数
static func claim(id: String) -> int:
	if not is_ready(id):
		return 0
	ready.erase(id)
	Cfg.toy_support.append(id)
	Cfg.roster_tickets[Roster.T_HUNT] = Roster.tickets() + REWARD
	Cfg.save()
	return REWARD


## 把可领取的都领了。返回 {"granted": 凭证数, "msg": 「已领取 10 张寻访凭证」+ 边框名}
static func claim_all() -> Dictionary:
	var n := 0
	var frs: Array = []
	for id in items():
		var g := claim(id)
		if g > 0:
			n += g
			frs.append("「%s」" % frame_name(id))
	if n <= 0:
		return {"granted": 0, "msg": ""}
	return {"granted": n, "msg": "已领取 %d 张寻访凭证和专属分享卡边框%s" % [n, "".join(PackedStringArray(frs))]}


## 桌面 / 测试模拟 SDK：--toysim=follow:yes,triple:no:coin → [status, detail]；没写的项 = unsupported
static func sim(id: String) -> Array:
	for a in Cfg.dev_args():
		if a.begins_with("--toysim="):
			for tok in a.substr(9).split(","):
				var ps: PackedStringArray = tok.split(":")
				if ps.size() >= 2 and ps[0] == id:
					return [ps[1], ":".join(ps.slice(2)).replace(":", ",")]
	return ["unsupported", ""]


## 标题页进 Toy 版时后台查一次（每次运行一次）：满足的只标「可领取」，查不到 / 出错不提示。done 在每项结果回来后调用（让标题页重画角标）
static func probe(done := Callable()) -> void:
	if _probed or not enabled():
		return
	_probed = true
	for id in items():
		if not claimable(id) or id in ready:
			continue
		if OS.has_feature("web"):
			if _js == null:
				_js = JavaScriptBridge.get_interface("__sySupport")
			if _js == null:
				return
			var cb := JavaScriptBridge.create_callback(func(args: Array):
				if args.size() > 0 and str(args[0]) == "yes":
					apply(id, "yes")
				if done.is_valid():
					done.call())
			_cbs.append(cb)
			_js.check(id, bvid(), cb)
		else:
			var s: Array = sim(id)
			if s[0] == "yes":
				apply(id, "yes")
	if not OS.has_feature("web") and done.is_valid():
		done.call()
