## 后期画面降噪预设（用户 10-12「现在游戏进行到后期画面是不是太乱了，容易看不清」；量测与对照 tools/late_clutter.py）。
## 一个旋钮 render/declutter（0–3）切整套参数，只改画面，不碰对局（同 seed TRACE 不变：只调透明度 / 字号 / 绘制预算，
## 唯一改「生成量」的是击杀火花，用的是 g.vrng）。可读性分层：
##   必须一直跳出来：主控、敌方弹幕 / 预警、灯火半径、掉落物 —— 这些一律不降（预警反而描边加粗、填充减淡）
##   可以退后：队友特效、自己的投射物、伤害数字、击杀爆点、环境粒子、普通怪描边 / 白闪
## 各档（0 = 现状，所有键的缺省值就是现在的行为）：
##   1 轻：友方特效降噪下限 0.45 → 0.38，队友特效再 ×0.8，满屏时白字伤害数字更早让位，普通怪描边 / 白闪略淡，击杀火花 ×0.7，
##        雪 ×0.7，远处安静结晶 0.7 → 0.6
##   2 中：再加：降噪更早开始（特效 60 个起）、敌人多也算拥挤、队友特效 ×0.6、自己的投射物略淡略去饱和、普通白字满屏时最多 4 个且小一号
##        （暴击 / 弱点 / 破绽照飘；同一片的数字合并窗口 0.25 → 0.5 秒、半径 28 → 44）、世界层友方火花每帧绘制预算 140、远景光束 ×0.6、预警填充 ×0.7 / 轮廓加粗 ×1.25、地面纹理薄纱 0.25、远处结晶 0.45
##   3 强：队友特效 ×0.5、主控自己 ×0.8、普通白字与「弱点」满屏时都不飘（只留暴击 / 破绽）、普通怪描边几乎只剩精英、预算 90、
##        地面薄纱 0.35……
## 拥挤度：crowd = 世界特效 + 干员粒子数（crowd_from 起、再 crowd_span 到顶）；敌人密度 ecrowd（活着的敌人 90 → 210）
## 按 crowd_mix 混进来（max(crowd, ecrowd × crowd_mix)）。所有「× k」都是 crowd = 1 时的值，中间按拥挤度线性插值，空场不变。
## 调试（只 debug 构建）：--bal=render/declutter=N 切档，--bal=render/declutter_<键>=值 单项覆盖；
## --clutterdbg=nofriend,nonum,noenemy,nofoe,noamb 把某一层画成全透明（代码照跑、随机数照抽，只是不显示），
## 量各层占屏幕的份额（tools/late_clutter.py）；--clutterab=N 每 N 帧在 0 档与当前档之间轮换（--perf 分 /d0 /dN 两桶量帧时间）
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const BASE := {
	"crowd_from": 80.0, "crowd_span": 220.0, "crowd_mix": 0.0,
	"dim_floor": 0.45, "add_floor": 0.6, "bloom_cut": 0.5,
	"mate_k": 1.0, "lead_k": 1.0,
	"bullet_k": 1.0, "bullet_desat": 0.0,
	"ol_floor": 0.4, "flash_a": 0.9,
	"num_cap": 30.0, "num_scale": 1.0,
	"kill_k": 1.0, "kill_ring": 1.0,
	"spark_budget": 0.0,
	"snow_k": 1.0, "god_k": 1.0, "ground_veil": 0.0, "num_weak": 1.0, "gem_quiet_a": 0.7,
	"num_merge_t": 0.25, "num_merge_r": 28.0,
	"tell_fill_k": 1.0, "tell_edge_k": 1.0,
}
const PRESETS := [
	{},
	{"crowd_mix": 0.5, "dim_floor": 0.38, "mate_k": 0.8, "ol_floor": 0.3, "flash_a": 0.75, "num_cap": 18.0, "kill_k": 0.7, "snow_k": 0.7,
		"gem_quiet_a": 0.6},
	{"crowd_from": 60.0, "crowd_mix": 0.8, "dim_floor": 0.3, "add_floor": 0.45, "mate_k": 0.6, "lead_k": 0.9,
		"bullet_k": 0.8, "bullet_desat": 0.3, "ol_floor": 0.2, "flash_a": 0.6, "num_cap": 4.0, "num_scale": 0.85,
		"kill_k": 0.5, "kill_ring": 0.0, "spark_budget": 140.0, "snow_k": 0.5, "god_k": 0.6, "tell_fill_k": 0.7, "tell_edge_k": 1.25,
		"ground_veil": 0.25, "gem_quiet_a": 0.45, "num_merge_t": 0.5, "num_merge_r": 44.0},
	{"crowd_from": 50.0, "crowd_mix": 1.0, "dim_floor": 0.25, "add_floor": 0.4, "bloom_cut": 0.6, "mate_k": 0.5, "lead_k": 0.8,
		"bullet_k": 0.65, "bullet_desat": 0.5, "ol_floor": 0.12, "flash_a": 0.45, "num_cap": 0.0, "num_scale": 0.75, "num_weak": 0.0,
		"kill_k": 0.35, "kill_ring": 0.0, "spark_budget": 90.0, "snow_k": 0.3, "god_k": 0.4, "tell_fill_k": 0.55, "tell_edge_k": 1.4,
		"ground_veil": 0.35, "gem_quiet_a": 0.4, "num_merge_t": 0.6, "num_merge_r": 56.0},
]

static var _lv := -1
static var _p: Dictionary = {}
static var _dbg: Dictionary = {}
static var _dbg_read := false
static var ab_every := -1          # --clutterab=N
static var ab_alt := false         # 轮换中：true = 本帧按 0 档画
static var _hr := -1


## 干员攻击 / 技能命中的装饰圆圈（用户 10-13：艾雅法拉攻击特效的圆圈不用加，保留火焰；其余干员也是）。
## render/hit_rings：0 = 不画（缺省），1 = 照旧画（回退）。只在绘制时跳过：粒子照常生成、计数、走完寿命，不碰对局与 fx 计数。
## 标了 keep 的干员环（升级、召唤物出入场、状态提示、替身减速范围）和敌方预警 / 拾取 / 灯标等一律不受影响。
static func hit_rings() -> bool:
	if _hr < 0:
		_hr = 1 if Bal.v("render/hit_rings", 0.0) > 0.0 else 0
	return _hr == 1


static var _hs := -1

## 干员命中 / 技能发动的放射线（用户 10-13 追加：「向四周发散的直线一样的特效」也删）：g.fx rays（标 op_spoke 的）、
## 水月创伤扩散的放射纹、维什戴尔爆炸的放射刀锋光条、推进之王落地光柱的张开光线 / 号令波狮鬃纹、凯尔希 Mon3tr 的 beamray。
## render/hit_spokes：0 = 不画（缺省），1 = 照旧画（回退）。同 hit_rings，只在绘制时跳过。
## 连线、锁定线、预警射线、激光 / 光束（本身就是攻击判定的线）不受影响。
static func hit_spokes() -> bool:
	if _hs < 0:
		_hs = 1 if Bal.v("render/hit_spokes", 0.0) > 0.0 else 0
	return _hs == 1


static func level() -> int:
	if _lv < 0:
		_lv = clampi(Bal.vi("render/declutter", 3), 0, PRESETS.size() - 1)
	return 0 if ab_alt else _lv


static func p(key: String) -> float:
	if _p.is_empty():
		level()
		for lv in PRESETS.size():
			var d: Dictionary = BASE.duplicate()
			d.merge(PRESETS[lv], true)
			# 单项微调：render/declutter_<键>（只作用在所选档；0 档恒为现状，轮换对照时才是干净的基线）
			if lv == _lv and lv > 0:
				for k in d:
					d[k] = Bal.v("render/declutter_" + k, float(d[k]))
			_p[lv] = d
	return float(_p[level()].get(key, 0.0))


## 按拥挤度 c（0–1）在 1 和 crowd = 1 时的值 k 之间插值
static func at(key: String, c: float) -> float:
	return lerpf(1.0, p(key), c)


## --clutterdbg=a,b：某一层画成全透明（量测用）；发布版恒空
static func dbg(key: String) -> bool:
	if not _dbg_read:
		_dbg_read = true
		for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
			if a.begins_with("--clutterdbg="):
				for t in a.substr(13).split(","):
					_dbg[t] = true
			if a.begins_with("--clutterab="):
				ab_every = int(a.substr(12))
	return _dbg.has(key)


## --clutterab=N：每 N 帧轮换（autotest 每帧调）
static func ab_step(frame: int) -> void:
	dbg("")
	if ab_every > 0 and frame % ab_every == 0:
		ab_alt = not ab_alt
