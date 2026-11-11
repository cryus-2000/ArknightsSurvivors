extends RefCounted
## 无敌测试包「四个最终 Boss 连测」（11-11 用户：「自动测试能不能四个连着测？这样也好测试重新开一局的情况，然后用负载中最高的几个干员测。然后性能报告要记录全面」）。
## 网址 boss=all 或 suite=1（调试版 --testsuite；--testsuite=new 先清掉旧进度）：等于 auto=1 + loop=1，一局一个最终 Boss，
## 按 偏执泡影 → 伊莎玛拉 → 伊祖米克 → 最后的骑士 轮完四局后停在汇总页。手机网页局间是整页重载（core/run_reload.gd），
## 进度存 localStorage（sy_suite；桌面 user://god_suite.json），重载后接着下一个——正好走真人「再来一局」的路径。
## 编队：网址没给 squad= 时每局换一套高负载编队（docs/333 §2，按 docs/332 §5 二十人贴图表）。
## 每局结算（perf_report.finish，含中途退出）写一段：完整性能报告 + Boss 战段帧时 / 内存。开局时先记「进行中」，
## 页面被杀（闪退）后下次打开发现「进行中」那局没结算，就把它记成「未结算」并附上闪退报告（crash_box 上次那份），接着下一个 Boss。
## 只在 Cfg.test_god 包里生效；正式包 Cfg.test_suite() 恒为 false，本脚本不会被调到。

const ORDER := ["paranoia", "ishar", "izumik", "knight"]           # Cfg.TEST_BOSS_ENDING 的键
const BOSS_NAME := {"paranoia": "偏执泡影", "ishar": "伊莎玛拉", "izumik": "伊祖米克", "knight": "最后的骑士"}
## 每局一套（队长在前）：docs/332 §5 常驻 + 终结技贴图最高的几人轮换（凯尔希 69.5 / 斯卡蒂 62（终结技放招时）/ 维什戴尔 52 / 乌尔比安 39.7 /
## 归溟幽灵鲨 32 / 水月 30.2 / 星熊 30.1 MiB）；第二套是 11-11 iPhone 10:24 闪退的那队
const SQUADS := [
	["kaltsit", "wisadel", "ulpianus"],
	["wisadel", "skalter", "irene"],
	["ulpianus", "specter_unchained", "mizuki"],
	["kaltsit", "hoshiguma", "skadi"],
]
const OP_NAME := {"kaltsit": "凯尔希", "wisadel": "维什戴尔", "ulpianus": "乌尔比安", "skalter": "浊心斯卡蒂", "irene": "艾丽妮",
	"specter_unchained": "归溟幽灵鲨", "mizuki": "水月", "hoshiguma": "星熊", "skadi": "斯卡蒂"}
const KEY := "sy_suite"
const PREV_KEY := "sy_suite_prev"
const PANEL_ID := "sy-suite"
const TEXT_CAP := 40000   # 每局报告文本上限（localStorage 一般 5 MB，四局加闪退报告远低于此）

static var _d = null          # 本页读到 / 改过的进度
static var _crash_seen := false   # 本页打开时发现上一局没结算（闪退 / 页面被关）


static func on() -> bool:
	return Cfg.test_suite()


## 进度（本页第一次调时读存档并核对上一局有没有结算）
static func data() -> Dictionary:
	if _d is Dictionary:
		return _d
	var raw := _load_raw()
	var d = JSON.parse_string(raw) if raw != "" else null
	if not d is Dictionary or Cfg.dev_args().has("--testsuite=new") or not d.get("runs") is Array:
		d = _fresh()
	_d = d
	var cur: Dictionary = d.get("cur", {})
	if not cur.is_empty():
		# 开局记过「进行中」却没走到结算：闪退 / 页面被杀 / 手动关页。附上崩溃快照（crash_box 上次那份，开局时间不早于这局才算）
		_crash_seen = true
		var CB = load("res://scripts/core/crash_box.gd")
		var p: Dictionary = CB.check_prev()
		var txt := ""
		if not p.is_empty() and _unix(str(p.get("start", ""))) >= _unix(str(cur.get("start", ""))) - 30:
			txt = CB.report_text(p)
		var e := {"idx": int(cur.get("idx", 0)), "boss": str(cur.get("boss", "")), "squad": cur.get("squad", []), "result": "crash",
			"start": str(cur.get("start", "")), "len": 0, "text": txt.left(TEXT_CAP) if txt != "" else "（没有找到这一局的崩溃快照）"}
		if not p.is_empty():
			var a: Array = p.get("s", [])
			if not a.is_empty():
				e["len"] = float(a[-1].get("t", 0))
		(d.runs as Array).append(e)
		d.idx = int(cur.get("idx", 0)) + 1
		d.cur = {}
		d.done = int(d.idx) >= ORDER.size()
		_save()
	print("PF SUITE page idx=%d runs=%d done=%s crash=%s" % [int(d.idx), (d.runs as Array).size(), str(d.get("done", false)), str(_crash_seen)])
	return d


static func _fresh() -> Dictionary:
	var old := _load_raw()
	if old != "":
		_store(PREV_KEY, old)   # 上一轮连测留一份（汇总页看不到它，但不会被新一轮直接冲掉）
	return {"v": 1, "id": Time.get_datetime_string_from_system(false, true), "idx": 0, "runs": [], "cur": {}, "done": false}


static func done() -> bool:
	return on() and bool(data().get("done", false))


static func crash_seen() -> bool:
	data()
	return _crash_seen


static func idx() -> int:
	return clampi(int(data().get("idx", 0)), 0, ORDER.size() - 1)


## 本局最终 Boss 对应的结局线（Cfg.test_boss_ending 在连测时返回它）
static func cur_ending() -> String:
	return str(Cfg.TEST_BOSS_ENDING.get(ORDER[idx()], ""))


## 本局编队（网址 squad= 优先，由 Cfg.test_squad 判断）
static func cur_squad() -> PackedStringArray:
	return PackedStringArray(SQUADS[idx() % SQUADS.size()])


## 开局（auto_play 建起来时）：记「进行中」——没走到 run_done 就是闪退
static func start_run(g) -> void:
	var d := data()
	if bool(d.get("done", false)):
		return
	var sq: Array = Array(Cfg.test_squad())   # auto_play 建起来时队友还没入队（run_setup 在后面），记计划编队
	d.cur = {"idx": int(d.idx), "boss": ORDER[idx()], "squad": sq, "start": Time.get_datetime_string_from_system(false, true)}
	_save()
	print("PF SUITE start idx=%d boss=%s squad=%s" % [int(d.idx), ORDER[idx()], ",".join(PackedStringArray(sq))])


## 局终（perf_report.finish：胜 / 负 / 中途退出都调一次）。rec 是性能报告那条（性能报告没开 / 太短时为空）
static func run_done(g, rec: Dictionary, result: String) -> void:
	var d := data()
	var cur: Dictionary = d.get("cur", {})
	if cur.is_empty():
		return
	var PR = load("res://scripts/core/perf_report.gd")
	if result == "quit" and g.auto_play != null and float(g.t) >= g.auto_play._timeout() - 1.0:
		result = "timeout"   # auto_play.SUITE_TIMEOUT 到点重开
	var sq: Array = []
	for o in g.squad.ops:
		sq.append(str(o.id))
	var fb = g.final_boss
	var e := {"idx": int(cur.idx), "boss": str(cur.boss), "squad": sq, "squad0": cur.get("squad", []), "result": result, "start": str(cur.get("start", "")),
		"len": snappedf(float(g.t), 1.0), "boss_killed": fb != null and fb.dead, "boss_type": str(fb.get("type")) if fb != null else "", "lv": int(g.level)}
	for k in ["p50", "p95", "p99", "min1s", "mem_peak", "wasm_max", "boss_seg", "up_peak", "up_max", "late", "enemy_peak"]:
		if rec.has(k):
			e[k] = rec[k]
	var txt: String = PR.report_text(rec) if not rec.is_empty() else "（这一局没有性能报告：对局太短或报告未开启）"
	e["text"] = txt.left(TEXT_CAP)
	(d.runs as Array).append(e)
	d.idx = int(cur.idx) + 1
	d.cur = {}
	d.done = int(d.idx) >= ORDER.size()
	_save()
	print("PF SUITE done idx=%d boss=%s type=%s result=%s len=%s p50=%s p95=%s min1s=%s mem=%s boss_seg=%s" % [int(cur.idx), str(cur.boss), str(e.boss_type), result,
		str(e.len), str(e.get("p50", "-")), str(e.get("p95", "-")), str(e.get("min1s", "-")), str(e.get("mem_peak", "-")), JSON.stringify(e.get("boss_seg", {}))])


# ---------------------------------------------------------------- 汇总

static func _unix(s: String) -> int:
	return 0 if s == "" else int(Time.get_unix_time_from_datetime_string(s))


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


static func _names(a) -> String:
	var o := PackedStringArray()
	for c in a:
		o.append(str(OP_NAME.get(str(c), str(c))))
	return "、".join(o)


const RESULT := {"win": "击破", "dead": "倒下", "quit": "中途退出", "crash": "未结算（闪退 / 页面被关）", "timeout": "超时未击破"}


## 一局一行（汇总表）
static func row_line(e: Dictionary) -> String:
	var bs: Dictionary = e.get("boss_seg", {})
	var res: String = RESULT.get(str(e.get("result", "")), str(e.get("result", "")))
	if str(e.get("result", "")) == "win" and not bool(e.get("boss_killed", true)):
		res = "结算"
	var s := "%d. %s · %s · %s · %s" % [int(e.get("idx", 0)) + 1, BOSS_NAME.get(str(e.get("boss", "")), str(e.get("boss", ""))), _names(e.get("squad", [])), _mmss(float(e.get("len", 0))), res]
	if e.has("p50"):
		s += " · 帧时 P50 %.1f / P95 %.1f 毫秒 · 最差 1 秒 %s 帧 · 内存峰值 %d MB%s" % [float(e.p50), float(e.get("p95", 0)),
			("%.0f" % float(e.get("min1s", 0))) if float(e.get("min1s", 0)) > 0.0 else "—", int(e.get("mem_peak", 0)),
			(" · WASM %.0f MiB" % float(e.wasm_max)) if float(e.get("wasm_max", 0)) > 0.0 else ""]
	if not bs.is_empty():
		s += " · Boss 战 " + boss_seg_text(bs)
	return s


static func boss_seg_text(bs: Dictionary) -> String:
	if bs.is_empty():
		return "—"
	return "%s 起 %s · P50 %.1f / P95 %.1f 毫秒 · 最差 1 秒 %s 帧 · 内存峰值 %d MB%s" % [_mmss(float(bs.get("t0", 0))),
		("共 %s" % _mmss(float(bs.get("len", 0)))) if float(bs.get("len", 0)) > 0.0 else "", float(bs.get("p50", 0)), float(bs.get("p95", 0)),
		("%.0f" % float(bs.get("min1s", 0))) if float(bs.get("min1s", 0)) > 0.0 else "—", int(bs.get("mem_peak", 0)),
		(" · WASM %.0f MiB" % float(bs.wasm_max)) if float(bs.get("wasm_max", 0)) > 0.0 else ""]


static func summary_text() -> String:
	var d := data()
	var runs: Array = d.get("runs", [])
	var o := PackedStringArray()
	o.append("方舟幸存者 · 无敌包四个最终 Boss 连测（%s 开始）%s" % [str(d.get("id", "")).replace("T", " "),
		" · 已完成" if bool(d.get("done", false)) else " · 进行中（第 %d / %d 局）" % [mini(int(d.get("idx", 0)) + 1, ORDER.size()), ORDER.size()]])
	o.append("设备 " + load("res://scripts/core/perf_report.gd").device_line(load("res://scripts/core/perf_report.gd").device()))
	o.append("")
	o.append("【汇总】")
	for e in runs:
		o.append(row_line(e))
	if runs.is_empty():
		o.append("（还没有结算的局）")
	for e in runs:
		o.append("")
		o.append("━━━━ 第 %d 局 · %s · 开局编队 %s ━━━━" % [int(e.get("idx", 0)) + 1, BOSS_NAME.get(str(e.get("boss", "")), str(e.get("boss", ""))), _names(e.get("squad0", e.get("squad", [])))])
		if e.has("boss_seg"):
			o.append("Boss 战段 " + boss_seg_text(e.boss_seg))
		o.append(str(e.get("text", "")))
	return "\n".join(o)


## 汇总页：网页 DOM 面板（复制全部 / 保存文件 / 重新连测 / 关闭；按钮本身是用户手势，iOS 剪贴板才放行）。桌面打到日志 + 写 user://god_suite_report.txt
static func show_summary() -> void:
	var t := summary_text()
	if not OS.has_feature("web"):
		var f := FileAccess.open("user://god_suite_report.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(t)
		for ln in t.split("\n"):
			print("PF SUITE| " + ln)
		return
	JavaScriptBridge.eval("""(function(t){var o=document.getElementById(__ID__);if(o)o.remove();
o=document.createElement('div');o.id=__ID__;
o.style.cssText='position:fixed;left:3%;top:4%;width:94%;height:88%;z-index:99999;background:#0d1419;border:1px solid #3fd2e6;padding:10px;box-sizing:border-box;display:flex;flex-direction:column;gap:8px;font-family:sans-serif';
var a=document.createElement('textarea');a.value=t;a.readOnly=true;
a.style.cssText='flex:1;width:100%;font-size:12px;line-height:1.45;color:#e6eef2;background:#05090c;border:1px solid #2a3a44;padding:6px;box-sizing:border-box';
var n=document.createElement('div');n.style.cssText='color:#f2c94c;font-size:14px;min-height:18px';
var row=document.createElement('div');row.style.cssText='display:flex;gap:8px';
function B(s,f){var b=document.createElement('button');b.textContent=s;b.style.cssText='flex:1;height:46px;font-size:16px;color:#0d1419;background:#3fd2e6;border:0;border-radius:4px';b.onclick=f;row.appendChild(b);return b}
B('复制全部',function(){var ok=function(){n.textContent='已复制，可以直接粘贴发给我们'};
try{navigator.clipboard.writeText(t).then(ok,function(){a.focus();a.select();try{document.execCommand('copy');ok()}catch(e){n.textContent='没能复制：请长按文字全选后复制'}})}
catch(e){a.focus();a.select();try{document.execCommand('copy');ok()}catch(e2){n.textContent='没能复制：请长按文字全选后复制'}}});
B('保存文件',function(){try{var u=URL.createObjectURL(new Blob([t],{type:'text/plain'}));var l=document.createElement('a');l.href=u;l.download='suite_log.txt';document.body.appendChild(l);l.click();l.remove();setTimeout(function(){URL.revokeObjectURL(u)},4000);n.textContent='已保存（在「文件」或下载里）'}catch(e){n.textContent='这里不能存文件：请用「复制」'}});
B('重新连测',function(){if(!confirm('清掉这一轮的记录，从偏执泡影重新开始？'))return;try{localStorage.setItem(__PK__,localStorage.getItem(__K__)||'');localStorage.removeItem(__K__)}catch(e){}location.reload()});
B('关闭',function(){o.remove()});
o.appendChild(a);o.appendChild(n);o.appendChild(row);document.body.appendChild(o)})(__T__)""".replace("__T__", JSON.stringify(t)).replace("__ID__", JSON.stringify(PANEL_ID)).replace("__K__", JSON.stringify(KEY)).replace("__PK__", JSON.stringify(PREV_KEY)), true)   # CSS 里有 %，不能用 % 格式化


static func panel_open() -> bool:
	if not OS.has_feature("web"):
		return false
	return JavaScriptBridge.eval("!!document.getElementById(%s)" % JSON.stringify(PANEL_ID), true) == true


static func close_panel() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){var o=document.getElementById(%s);if(o)o.remove()})()" % JSON.stringify(PANEL_ID), true)


# ---------------------------------------------------------------- 存取

static func _file() -> String:
	return "user://god_suite.json"


static func _load_raw() -> String:
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("(function(){try{return localStorage.getItem(%s)||''}catch(e){return ''}})()" % JSON.stringify(KEY), true)
		return str(r) if r is String else ""
	return FileAccess.get_file_as_string(_file()) if FileAccess.file_exists(_file()) else ""


static func _store(key: String, s: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem(%s,%s)}catch(e){}" % [JSON.stringify(key), JSON.stringify(s)], true)
	else:
		var f := FileAccess.open(_file() if key == KEY else "user://god_suite_prev.json", FileAccess.WRITE)
		if f != null:
			f.store_string(s)


static func _save() -> void:
	if _d is Dictionary:
		_store(KEY, JSON.stringify(_d))
