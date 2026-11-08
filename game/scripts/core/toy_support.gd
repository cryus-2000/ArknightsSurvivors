extends RefCounted
## B站 Toy「支持作者」奖励（docs/313，用户 11-07 定）：只在 Toy 版出现，附加奖励、不设任何门槛（docs/99：免交互可玩、主线不强制关注）。
##   关注作者 → 一次性送 REWARD 张寻访凭证 + 专属结算分享卡边框；
##   三连指定视频（点赞 + 投币 + 收藏，balance toy/support_bvid）→ 一次性 REWARD 张凭证 + 专属结算分享卡边框。
##   11-08 用户：边框两项都送，领了任意一项就解锁（frame_unlocked）；云存档 tsup 取并集，合并后任一项在就算解锁。
##   11-08 用户：两项合成一个入口（entry_label），浮层里并排各自领取；support_bvid 留空时三连照样列出、写「PV 发布后开放」并置灰（triple_open）。
## 不做称号；不解锁干员 / 数值 / 难度。领取状态 Cfg.toy_support（本地存档 + 云存档 prog.tsup 取并集，docs/89）；
## 前端校验可被破解，无所谓（奖励本就是附加的）。SDK 查询在 tools/web/support.js（window.__sySupport），这里只管规则与记账。

const Roster = preload("res://scripts/core/roster.gd")
const Bal = preload("res://scripts/core/balance.gd")

const REWARD := 5
const ITEMS := ["follow", "triple"]


static var bv_test = null    # 测试用：非 null 时顶替 support_bvid（toy_support_test 验「PV 发布后开放」）


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


## 分享卡专属边框：关注、三连领过任意一项（11-08 用户）
static func frame_unlocked() -> bool:
	for id in ITEMS:
		if claimed(id):
			return true
	return false


## 一项的查询结果 → 记账。status：yes / no / unsupported / login / err（support.js 的约定）；detail：triple 缺的几项（like,coin,fav）。
## 返回 {"granted": 本次发的凭证数, "msg": 给玩家看的一句}。已领过的不再发
static func apply(id: String, status: String, detail := "") -> Dictionary:
	var name: String = "关注作者" if id == "follow" else "三连视频"
	if claimed(id):
		return {"granted": 0, "msg": "%s的奖励已经领取过了" % name}
	if id == "triple" and not triple_open():
		return {"granted": 0, "msg": "PV 发布后开放"}
	match status:
		"yes":
			var frame_had := frame_unlocked()
			Cfg.toy_support.append(id)
			Cfg.roster_tickets[Roster.T_HUNT] = Roster.tickets() + REWARD
			Cfg.save()
			return {"granted": REWARD, "msg": "已领取：寻访凭证 ×%d%s" % [REWARD, "" if frame_had else "和专属分享卡边框"]}
		"no":
			if id == "follow":
				return {"granted": 0, "msg": "还没有关注作者"}
			var miss: Array = []
			for k in detail.split(",", false):
				miss.append({"like": "点赞", "coin": "投币", "fav": "收藏"}.get(k, k))
			return {"granted": 0, "msg": "三连还差：%s" % "、".join(PackedStringArray(miss)) if not miss.is_empty() else "还没有完成三连"}
		"unsupported":
			return {"granted": 0, "msg": "请在 B站 App 中打开"}
		"login":
			return {"granted": 0, "msg": "请先登录 B站账号"}
	return {"granted": 0, "msg": "暂时无法查询，请稍后再试"}
