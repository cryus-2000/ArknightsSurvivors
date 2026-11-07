extends RefCounted
## 玩家反馈入口（11-07 用户批，docs/311）：结算底栏 + 标题页底部一行「意见反馈」（11-07 用户：从设置页挪到标题页、改叫「意见反馈」）。
## 去向按平台分流，两个目标都在 balance.json feedback 段，留空 = 不显示入口（不给坏链接）：
##   itch / 桌面 / itch 网页：form_url（问卷链接，OS.shell_open；网页上就是 window.open，在点按处理里调，浏览器认作用户手势）
##   B站 Toy（window.toy 在）：不跳站外（docs/99 外链条），toy.navigate({type:'video', id: toy_bv}) 去作者自己的视频评论区；
##     Toy 环境下即使配了 form_url 也不用它
## 反馈码：版本 / 提交号 + 本局摘要（队长、小队、难度、结果、倒下时刻、倒下原因类型、局时），不含任何个人信息；
## 玩家点按钮时复制到剪贴板、自己贴进问卷 / 评论，不上传。标题页入口只带版本。解码：tools/feedback_decode.py（同一张位表）
## 位表（v1，高位在前，Crockford base32，末尾 1 位校验字）：
##   fmt 3 | kind 1（0 = 只有版本，1 = 带本局）| 版本 主 4 · 次 7 · 修 6 | 有提交号 1 [+ 提交号前 7 位十六进制 28]
##   kind 1：队长 6 | 队友数 3 | 队友 6 × n | 难度（潮位）5 | 结果 2（0 倒下 / 1 胜利 / 2 中途退出 / 3 其他）| Boss 演练 1
##           | 倒下时刻 秒 12（未倒下 0）| 局时 秒 13（真实时间，含暂停与选卡）| 倒下原因类型 4（CAUSES 下标）

const D = preload("res://scripts/data.gd")

const FMT := 1
const ALPHA := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## 干员编号表：只许往后追加（解码脚本同一张表）。0 = 无，63 = 表外（新干员没登记）
const OPS := ["", "angelina", "exusiai", "eyjafjalla", "gladiia", "hoshiguma", "irene", "kaltsit", "lappland", "logos", "lumen",
	"mizuki", "saria", "siege", "skadi", "skalter", "specter_unchained", "suzuran", "texas", "ulpianus", "wisadel"]
## 倒下原因类型（只记类型，不记具体敌人）：只许往后追加
const CAUSES := ["", "enemy", "elite", "boss", "rare", "env:zone", "env:mire", "env:dark", "env:relic", "env:bullet",
	"env:corrode", "env:wound", "env:nerve", "other"]


static func _bal(key: String) -> String:
	var sec = load("res://scripts/core/balance.gd").sec("feedback")
	return str(sec.get(key, "")).strip_edges() if sec is Dictionary else ""


## 测试：--fburl=<链接> / --fbbv=<BV号> / --fbtoy（按 Toy 环境走）覆盖配置（只在调试版读命令行）
static func _arg(prefix: String) -> String:
	for a in Cfg.dev_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


static func form_url() -> String:
	var v := _arg("--fburl=")
	return v if v != "" else _bal("form_url")


static func toy_bv() -> String:
	var v := _arg("--fbbv=")
	return v if v != "" else _bal("toy_bv")


## B站 Toy 环境：页面里有 Toy SDK（Toy 包一律加载 SDK，itch 网页包没有）
static func is_toy() -> bool:
	if "--fbtoy" in Cfg.dev_args():
		return true
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("!!(window.toy && typeof window.toy.navigate === 'function')", true))


## 入口要不要显示：当前平台对应的目标配了才显示
static func enabled() -> bool:
	return toy_bv() != "" if is_toy() else form_url() != ""


## 去反馈目标（必须在点按处理里调）。返回是否发出
static func go() -> bool:
	if is_toy():
		var bv := toy_bv()
		if bv == "":
			return false
		if not OS.has_feature("web"):
			return true   # 测试（--fbtoy）：桌面上没有 Toy，当作已发出
		return bool(JavaScriptBridge.eval("(function(bv){try{var t=window.toy;if(t&&typeof t.navigate==='function'){Promise.resolve(t.navigate({type:'video',id:bv})).catch(function(){});return true}}catch(e){}return false})(%s)" % JSON.stringify(bv), true))
	var url := form_url()
	if url == "" or not (url.begins_with("https://") or url.begins_with("http://")):
		return false
	OS.shell_open(url)
	return true


static func build_info() -> Dictionary:
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	return info if info is Dictionary else {}


## 本局摘要（结算模型 run/run_stats.gd model() 的输出 + 局时秒数）→ 反馈码；summary 为空 = 只带版本
static func code(summary := {}) -> String:
	var bits: Array = []
	var info := build_info()
	_put(bits, FMT, 3)
	_put(bits, 0 if summary.is_empty() else 1, 1)
	var ver: PackedStringArray = str(info.get("version", "0")).split(".")
	_put(bits, int(ver[0]) if ver.size() > 0 else 0, 4)
	_put(bits, int(ver[1]) if ver.size() > 1 else 0, 7)
	_put(bits, int(ver[2]) if ver.size() > 2 else 0, 6)
	var cm := str(info.get("commit", "")).to_lower()
	var hexok := cm.length() >= 7 and cm.substr(0, 7).is_valid_hex_number()
	_put(bits, 1 if hexok else 0, 1)
	if hexok:
		_put(bits, cm.substr(0, 7).hex_to_int(), 28)
	if not summary.is_empty():
		var ids: Array = summary.get("ops", [])
		_put(bits, _op(str(ids[0]) if ids.size() > 0 else ""), 6)
		var mates: Array = ids.slice(1, 8)
		_put(bits, mates.size(), 3)
		for id in mates:
			_put(bits, _op(str(id)), 6)
		_put(bits, clampi(int(summary.get("tier", 0)), 0, 31), 5)
		var res := str(summary.get("result", ""))
		_put(bits, 2 if bool(summary.get("quit", false)) else {"dead": 0, "win": 1}.get(res, 3), 2)
		_put(bits, 1 if bool(summary.get("trial", false)) else 0, 1)
		_put(bits, clampi(int(summary.get("death_t", 0.0)), 0, 4095), 12)
		_put(bits, clampi(int(summary.get("wall_s", 0.0)), 0, 8191), 13)
		_put(bits, maxi(0, CAUSES.find(str(summary.get("cause", "")))), 4)
	while bits.size() % 5 != 0:
		bits.append(0)
	var vals: Array = []
	for i in range(0, bits.size(), 5):
		vals.append(bits[i] * 16 + bits[i + 1] * 8 + bits[i + 2] * 4 + bits[i + 3] * 2 + bits[i + 4])
	vals.append(_check(vals))
	var s := ""
	for i in vals.size():
		if i > 0 and i % 4 == 0:
			s += "-"
		s += ALPHA[vals[i]]
	return "AS-" + s


static func _check(vals: Array) -> int:
	var c := 7
	for i in vals.size():
		c = (c * 33 + int(vals[i]) * (i + 3)) % 1021
	return c % 32


static func _put(bits: Array, v: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((v >> i) & 1)


static func _op(id: String) -> int:
	if id == "":
		return 0
	var i := OPS.find(id)
	return i if i > 0 else 63


## 结算模型 → 反馈码要的摘要（只取这些字段）
static func summary(model: Dictionary, wall_s: float) -> Dictionary:
	var ids: Array = []
	var rows: Array = model.get("rows", [])
	for r in rows:   # rows 已按「队长在前，其余按入队时间」排
		if bool(r.get("leader", false)):
			ids.append(str(r.key))
	for r in rows:
		if not bool(r.get("leader", false)) and str(r.key) in OPS:
			ids.append(str(r.key))
	var dead: bool = str(model.get("result", "")) == "dead" and not bool(model.get("quit", false))
	return {"ops": ids, "tier": int(model.get("tier", 0)), "result": str(model.get("result", "")), "quit": bool(model.get("quit", false)),
		"trial": bool(model.get("trial", false)), "death_t": float(model.get("t", 0.0)) if dead else 0.0, "wall_s": wall_s,
		"cause": cause(model.get("killer", {})) if dead else ""}


static func cause(k: Dictionary) -> String:
	if k.is_empty():
		return ""
	var ty := str(k.get("type", ""))
	if ty != "":
		var role := str(D.ENEMIES.get(ty, {}).get("role", ""))
		return role if role in ["elite", "boss", "rare"] else "enemy"
	var ev := "env:" + str(k.get("env", ""))
	return ev if ev in CAUSES else "other"


## 复制到剪贴板。桌面同步返回是否成功；网页走 navigator.clipboard（异步：结果在 window.__syFbCopy，1 = 成功 / 0 = 失败）
static func copy(text: String) -> bool:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(t){window.__syFbCopy=-1;try{navigator.clipboard.writeText(t).then(function(){window.__syFbCopy=1},function(){window.__syFbCopy=0})}catch(e){window.__syFbCopy=0}})(%s)" % JSON.stringify(text), true)
		return false
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get() == text
