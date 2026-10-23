extends RefCounted
## 游戏数据表：水月的成长项、技能、模组、武器、援护、难度。
## 敌人与刷怪导演表已迁到 JSON（data/enemies.json、data/waves.json），这里只做加载，调用方仍用 D.ENEMIES / D.THREAT 等。

const Loader = preload("res://scripts/enemies/enemy_db.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json（难度修正表 difficulty 段）
static var ENEMIES: Dictionary = Loader.load_enemies()
static var THREAT: Array = Loader.load_waves().threat
static var BOSS_TIMES: Array = Loader.load_waves().boss_times
static var MID_POOL: Array = Loader.load_waves().mid_pool
## 第一个中期 Boss（3:30）只从这些 MID_POOL 下标里抽；双 Boss 与远程风筝型留到第二个（7:00），编队成型后再考（docs/29 §6）
static var MID_FIRST: Array = Loader.load_waves().get("mid_first", []).map(func(x): return int(x))   # JSON 数字是 float，转 int 才能和下标比较
static var ENDINGS: Dictionary = Loader.load_waves().endings

## 敌人：名称与机制按「水月与深蓝之树」，数值按本作换算
## ai: melee 近战追击 / ranged 进入射程后停下射击 / static 不移动
## 特殊字段：corrode 侵蚀比例、nerve 每次命中的神经损伤、role elite/boss
## 威胁等级：随时间上升，决定刷怪池、精英间隔（秒）与大群构成；升级时刷出一小波新种类
## Boss 结构：3:30 与 7:00 从第三层 Boss 池各抽一个（不重复），10:00 按结局出现最终 Boss
## 难度（参照水月肉鸽的难度分级：逐级叠加负面效果；通关当前最高难度后解锁下一级）
const DIFFICULTY := [
	{"name": "标准", "desc": "深海原本的样子"},
	{"name": "暗潮", "desc": "敌人生命 +15%"},
	{"name": "浊流", "desc": "敌人攻击 +15%"},
	{"name": "昏灯", "desc": "受击时灯火损失 +25%，灯油掉落减半"},
	{"name": "猎群", "desc": "精英出现间隔 -25%"},
	{"name": "拮据", "desc": "源石锭掉落 -30%"},
	{"name": "疾影", "desc": "Boss 招式预警时间 -25%"},
	{"name": "潮涌", "desc": "大群规模 +40%，Boss 在场时大群照常来袭"},
	{"name": "永痕", "desc": "溟痕不再消散"},
	{"name": "负伤", "desc": "初始最大生命 -20%"},
	{"name": "深蓝之树", "desc": "敌人生命与攻击再 +20%，Boss 攻击 +25%"},
]
## 旧三档（1.1 – 10-22）：标准 / Ⅳ / Ⅷ 的修正表在 data/balance.json 的 difficulty/<key> 段，段里没写的键按 level（上表的累计档位）拼出来。
## 潮位阶梯的锚点（0 / 4 / 8）和批跑 --tier=0/1/2 仍按它取表（--tier 的结果与改动前逐局相同）。
## 干员职业的显示顺序与英文名（选人页 / 图鉴 / 寻访共用；docs/126 C5，原来四处各写一份）
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
const CLASS_EN := {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER", "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}

const LEGACY_TIERS := [
	{"name": "波涛迭起", "key": "standard", "level": 0},
	{"name": "波涛迭起·Ⅳ", "key": "hard", "level": 4},
	{"name": "波涛迭起·Ⅷ", "key": "extreme", "level": 8},
]
## 潮位阶梯 0–15（docs/71 + docs/109 §5.3，用户 10-22「难度回到 15 级」）：逐级叠加，每级加一条规则或加重前面的规则；
## 通关潮位 N 解锁 N+1。存档 Cfg.difficulty / diff_unlocked 存的是潮位（0–15）。
## 锚点：0 = 旧标准、4 = 旧 Ⅳ（逐键相等），8 = 旧 Ⅷ + 寒流两键（小怪控制 5:00、寒霜 2 层，docs/71 §2.3）；
## 1–3 / 5–7 / 9–15 在前一个锚点上依次写入 TIDE_SET 的键（只往更难推）。name 是界面档名，short 是级名，desc 是本级新增的规则。
const DIFFICULTY_TIERS := [
	{"name": "潮位 0 · 海面", "short": "海面", "en": "SURFACE", "desc": "没有额外规则。", "key": "standard", "level": 0},
	{"name": "潮位 1 · 巨影", "short": "巨影", "en": "LOOMING", "desc": "Boss 生命 +15%，Boss 招式预警缩短 15%。", "level": 1},
	{"name": "潮位 2 · 昏灯", "short": "昏灯", "en": "DIM LAMP", "desc": "受击时灯火损失 +30%；灯油掉落 -30%，源石锭掉落 -10%。", "level": 2},
	{"name": "潮位 3 · 暗涌", "short": "暗涌", "en": "UNDERTOW", "desc": "敌人生命与造成的伤害 +20%。", "level": 3},
	{"name": "潮位 4 · 寒流", "short": "寒流", "en": "COLD CURRENT", "desc": "大群规模 +20%；小怪控制提前到 5:00，寒霜 2 层即冻结。", "key": "hard", "level": 4},
	{"name": "潮位 5 · 搁浅", "short": "搁浅", "en": "STRANDED", "desc": "队长初始最大生命 -10%；灯油掉落加重到 -40%，源石锭加重到 -25%。", "level": 5},
	{"name": "潮位 6 · 渊影", "short": "渊影", "en": "ABYSSAL SHADOW", "desc": "Boss 生命加重到 +35%，预警缩短加重到 20%；Boss 造成的伤害再 +15%。", "level": 6},
	{"name": "潮位 7 · 甲潮", "short": "甲潮", "en": "HARD SHELL", "desc": "敌人生命加重到 +70%，造成的伤害加重到 +25%。", "level": 7},
	{"name": "潮位 8 · 漫灌", "short": "漫灌", "en": "FLOOD", "desc": "自然溟痕常驻，只有引航灯标能驱散；大群加重到 +60%，Boss 在场时照常来袭。", "key": "extreme", "level": 8},
	{"name": "潮位 9 · 夜潮", "short": "夜潮", "en": "NIGHT TIDE", "desc": "后期敌人伤害的成长上限提高到 +50%；敌人造成的伤害加重到 +35%。", "level": 9},
	{"name": "潮位 10 · 残烛", "short": "残烛", "en": "GUTTERING", "desc": "受击时灯火损失加重到 +60%，灯油掉落加重到 -60%。", "level": 10},
	{"name": "潮位 11 · 领潮者", "short": "领潮者", "en": "TIDE LORDS", "desc": "敌人生命加重到 +100%。", "level": 11},
	{"name": "潮位 12 · 异变", "short": "异变", "en": "MUTATION", "desc": "带词条的海嗣提前到 5:00 出现，词条概率上限提高到 50%。", "level": 12},
	{"name": "潮位 13 · 深压", "short": "深压", "en": "DEEP PRESSURE", "desc": "队长初始最大生命加重到 -20%；敌人造成的伤害加重到 +50%。", "level": 13},
	{"name": "潮位 14 · 渊主", "short": "渊主", "en": "ABYSS LORD", "desc": "Boss 生命加重到 +60%；最终 Boss 生命再 +30%。", "level": 14},
	{"name": "潮位 15 · 潮不止息", "short": "潮不止息", "en": "ENDLESS TIDE", "desc": "最终 Boss 在场时海嗣照常涌来；敌人生命加重到 +140%。", "level": 15},
]
## 界面上的三档难度（用户 10-22：「难度改成三档，作为潮位系统的三个预设」）。潮位阶梯 0–15 的代码与数据保留但不在界面露出
## （危机合约类玩法留作以后）。tide = 取哪一级潮位的修正表；factor = 结算系数（= Meta.tide_factor(tide)）。
## 存档 Cfg.difficulty / diff_unlocked 存的是这里的下标；通关第 i 档解锁第 i+1 档。档名用户 10-22 定 B 组（docs/109 §15）
const DIFF_PRESETS := [
	{"name": "常规", "short": "常规", "en": "NORMAL", "tide": 0, "level": 0, "factor": 1.0,
		"desc": "没有额外规则。"},
	{"name": "高压", "short": "高压", "en": "HIGH PRESSURE", "tide": 5, "level": 5, "factor": 1.25,
		"desc": "敌人生命与伤害 +20%，大群 +20%；队长初始最大生命 -10%，灯油与源石锭掉落减少。"},
	# enemy_scale（用户 10-22，docs/109 §15）：深潮档的小怪生命 / 伤害倍率在潮位 10 的表上再乘这个系数（只乘 enemy_hp / enemy_dmg，
	# Boss 生命、潮位阶梯 TIDE_SET、结算系数 ×1.5 都不动）：四档目标（无成长常规 45–55、满点常规 85–90、高压 70–80、深潮 55–65）
	# 的跨度比潮位 0→10 的实测跨度窄，基础砍 / 树值只能整体平移，深潮档单独微降补齐
	{"name": "深潮", "short": "深潮", "en": "DEEP TIDE", "tide": 10, "level": 10, "factor": 1.5, "enemy_scale": 0.95,
		"desc": "敌人生命 +62%、伤害 +28%；溟痕常驻，大群 +60%，Boss 在场时照常来袭；受击灯火损失 +60%。"},
]
const PRESET_SCALE_KEYS := ["enemy_hp", "enemy_dmg"]


## 三档预设的修正表：潮位表 + 该档自己的 enemy_scale
static func dmod_for_preset(i: int) -> Dictionary:
	var p: Dictionary = DIFF_PRESETS[clampi(i, 0, DIFF_PRESETS.size() - 1)]
	var m := dmod_for_tier(int(p.tide))
	var k: float = float(p.get("enemy_scale", 1.0))
	if k != 1.0:
		for key in PRESET_SCALE_KEYS:
			m[key] = float(m[key]) * k
	return m


## 按潮位取修正表，潮位正好是某一档预设时带上该档的 enemy_scale（批跑 --tide=10 与界面「深潮」同一张表）；其余潮位 = 纯潮位表
static func dmod_for_tide(tide: int) -> Dictionary:
	for i in DIFF_PRESETS.size():
		if int(DIFF_PRESETS[i].tide) == tide:
			return dmod_for_preset(i)
	return dmod_for_tier(tide)


## 潮位 → 界面档名：三档预设的潮位显示档名，其余（批跑 --tide）显示潮位名
static func tier_name(tide: int) -> String:
	for p in DIFF_PRESETS:
		if int(p.tide) == tide:
			return str(p.name)
	return str(DIFFICULTY_TIERS[clampi(tide, 0, DIFFICULTY_TIERS.size() - 1)].name)


## 每级写入的修正键（锚点 0 / 4 / 8 之外）；数值是第一轮草案，按 docs/109 §5.4 云端实测再调
const TIDE_SET := {
	1: {"boss_hp": 1.15, "boss_warn": 0.85},
	2: {"lamp_hit": 1.3, "oil_drop": 0.7, "ingot": 0.9},
	3: {"enemy_hp": 1.2, "enemy_dmg": 1.2, "hunt_dur": 0.85, "hunt_ring_hp": 0.85, "beacon_every": 0.8},
	5: {"max_hp": 0.9, "oil_drop": 0.6, "ingot": 0.75},
	6: {"boss_hp": 1.35, "boss_warn": 0.8, "boss_dmg": 1.15},
	7: {"enemy_hp": 1.7, "enemy_dmg": 1.25, "hunt_dur": 0.7, "hunt_ring_hp": 0.7, "boss_fight_enemy_hp": 1.0},
	8: {"ctrl_start": 300.0, "frost_max": 2.0},
	9: {"dmg_late_cap": 0.5, "enemy_dmg": 1.35},
	10: {"lamp_hit": 1.6, "oil_drop": 0.4},
	11: {"enemy_hp": 2.0},
	12: {"affix_start": 300.0, "affix_max": 0.5},
	13: {"max_hp": 0.8, "enemy_dmg": 1.5},
	14: {"boss_hp": 1.6, "final_boss_hp": 1.3},
	15: {"final_stop_mobs": 0.0, "enemy_hp": 2.4},
}
## 难度修正表：倍率（1.0 = 不变）与开关（0 / 1）
const DMOD_DEFAULT := {
	"enemy_hp": 1.0, "enemy_dmg": 1.0, "boss_hp": 1.0, "boss_dmg": 1.0,   # 小怪与 Boss 生命 / 攻击（Boss 攻击另乘 enemy_dmg）
	"lamp_hit": 1.0, "oil_drop": 1.0, "ingot": 1.0,                      # 受击灯火损失、小怪灯油掉落率、源石锭掉落
	"elite_interval": 1.0, "boss_warn": 1.0, "horde": 1.0,               # 精英出现间隔、Boss 招式预警时间、大群规模
	"horde_in_boss": 0, "mire_permanent": 0, "max_hp": 1.0,              # Boss 在场时大群照常来袭、溟痕不消散、主控初始最大生命
	"mire_dmg": 1.0, "nerve_rate": 1.0,                                   # 溟痕伤害（run/enemies.gd）；溟痕里神经损伤累积速度（combat.update_nerve）
	"hunt_dur": 1.0, "hunt_ring_hp": 1.0,                                 # 围猎持续时间、圈上海嗣生命（run/hunt.gd；高难度下放宽，避免成为硬门槛）
	"beacon_every": 1.0,                                                  # 引航灯标刷新间隔倍率（run/beacon.gd；< 1 更频繁，数值按档填）
	# 小怪控制 / 词条按档覆盖（数值 9/30：标准档不动、只收紧 Ⅳ / Ⅷ）：-1 = 用 balance.json enemy 段的全局值，读取走 combat.enemy_knob
	"ctrl_start": -1.0, "frost_max": -1.0, "affix_start": -1.0, "affix_max": -1.0,
	"dmg_late_cap": -1.0,                                                  # 后期敌人伤害上限（run/spawner.gd；-1 = 用 enemy/dmg_late_cap，Ⅷ 跌破 50 时可单独设 0）
	"boss_fight_enemy_hp": -1.0,                                          # 最终 Boss 在场时新刷杂兵的生命倍率（-1 = 跟 enemy_hp；spawner.new_enemy）
	"final_stop_mobs": -1.0, "final_clear_mobs_s": -1.0,                 # 最终 Boss 战停刷 / 现有杂兵消散秒数按档覆盖（-1 = 跟 balance.json final 段；spawner.final_knob）
	"final_trickle_mult": -1.0, "final_trickle_cap": -1.0, "final_trickle_fresh_w": -1.0,   # 最终 Boss 战少量补怪的倍率 / 上限 / 新种类权重按档覆盖（-1 = 跟 final 段）
	"final_boss_hp": 1.0,                                                 # 只乘最终 Boss 的生命（停刷的补偿旋钮，docs/38 §8.14；不动中期 Boss / 杂兵 / 经验）
	# 灯标按档覆盖（-1 = 跟 balance.json beacon 段；beacon._sk）。这里没登记的键 dmod_for_tier 会丢掉，所以 _sk 读的键都要在这里
	"beacon_safe_bullet": -1.0, "beacon_safe_ranged": -1.0, "beacon_safe_slow": -1.0,   # 圈内安全（docs/49g）
	"beacon_guide_r": -1.0, "beacon_shade_deg": -1.0,                     # 引路 / 背光刷怪（docs/56）
	"beacon_relay_r": -1.0, "beacon_relay_rate": -1.0,                    # 接力环（docs/56 §8）
	"beacon_stagger_r": -1.0, "beacon_stagger_s": -1.0, "beacon_stagger_cd": -1.0,   # 灯边硬直（docs/56 §10）
}
## 修正项在选难度页上的说明：[键, 模板, 显示方式]；up = (v-1)×100，down = (1-v)×100，flag = 开关；
## time / count / pct = 按档覆盖的 enemy 段绝对值（-1 = 用全局），只在本档值和 balance.json enemy/<键> 不同时显示：time 写成 分:秒，pct ×100
const DMOD_TEXT := [
	["enemy_hp", "敌人生命 +%d%%", "up"], ["enemy_dmg", "敌人造成的伤害 +%d%%", "up"], ["boss_hp", "Boss 生命 +%d%%", "up"], ["boss_dmg", "Boss 造成的伤害再 +%d%%", "up"], ["final_boss_hp", "最终 Boss 生命再 +%d%%", "up"],
	["max_hp", "队长初始最大生命 -%d%%", "down"], ["lamp_hit", "受击时灯火损失 +%d%%", "up"], ["oil_drop", "灯油掉落 -%d%%", "down"], ["ingot", "源石锭掉落 -%d%%", "down"],
	["elite_interval", "精英出现间隔 -%d%%", "down"], ["boss_warn", "Boss 预警最多缩短 %d%%（≥ 0.6 秒）", "down"], ["horde", "大群规模 +%d%%", "up"],
	["horde_in_boss", "Boss 在场时大群照常来袭", "flag"], ["mire_permanent", "自然溟痕常驻，只有引航灯标能驱散", "flag"], ["mire_dmg", "溟痕伤害 +%d%%", "up"], ["nerve_rate", "神经损伤累积 +%d%%", "up"],
	["ctrl_start", "小怪控制提前到 %d:%02d", "time"], ["frost_max", "寒霜 %d 层即冻结", "count"],
	["affix_start", "词条提前到 %d:%02d", "time"], ["affix_max", "词条概率上限 %d%%", "pct"],
]
## time / count / pct 的全局缺省（与 combat.enemy_knob 调用处一致）
const DMOD_ABS_DEFAULT := {"ctrl_start": 1.0e9, "frost_max": 3.0, "affix_start": 1.0e9, "affix_max": 0.35}


## 旧累计难度（0–10，上面 DIFFICULTY 逐级叠加）拼出的修正表
static func dmod_for_level(L: int) -> Dictionary:
	var m := DMOD_DEFAULT.duplicate()
	m.enemy_hp = 1.0 + (0.15 if L >= 1 else 0.0) + (0.2 if L >= 10 else 0.0)
	m.boss_hp = 1.15 if L >= 1 else 1.0
	m.enemy_dmg = 1.0 + (0.15 if L >= 2 else 0.0) + (0.2 if L >= 10 else 0.0)
	m.lamp_hit = 1.25 if L >= 3 else 1.0
	m.oil_drop = 0.5 if L >= 3 else 1.0
	m.elite_interval = 0.75 if L >= 4 else 1.0
	m.ingot = 0.7 if L >= 5 else 1.0
	m.boss_warn = 0.75 if L >= 6 else 1.0
	m.horde = 1.4 if L >= 7 else 1.0
	m.horde_in_boss = 1 if L >= 7 else 0
	m.mire_permanent = 1 if L >= 8 else 0
	m.max_hp = 0.8 if L >= 9 else 1.0
	m.boss_dmg = 1.25 if L >= 10 else 1.0
	return m


## 旧三档的修正表：balance.json difficulty/<key> 覆盖按 level 拼出的表（批跑 --tier=0/1/2、潮位锚点）
static func dmod_for_legacy(tier: int) -> Dictionary:
	var t: Dictionary = LEGACY_TIERS[clampi(tier, 0, LEGACY_TIERS.size() - 1)]
	var m := dmod_for_level(int(t.level))
	var over: Dictionary = Bal.sec("difficulty/" + str(t.key))
	for k in over:
		if m.has(k):
			m[k] = over[k]
	return m


## 潮位 tide（0–15）的修正表：取所在块的锚点（0 / 4 / 8 = 旧三档），再依次写入锚点之后各级的 TIDE_SET
static func dmod_for_tier(tide: int) -> Dictionary:
	tide = clampi(tide, 0, DIFFICULTY_TIERS.size() - 1)
	var a := 0 if tide < 4 else (1 if tide < 8 else 2)
	var m := dmod_for_legacy(a)
	for lv in range(int(LEGACY_TIERS[a].level) + (1 if a < 2 else 0), tide + 1):
		var s: Dictionary = TIDE_SET.get(lv, {})
		for k in s:
			if m.has(k):
				m[k] = s[k]
	return m


## 修正表 → 选难度页的说明行
static func dmod_lines(m: Dictionary) -> Array:
	var out: Array = []
	for row in DMOD_TEXT:
		var v := float(m.get(row[0], DMOD_DEFAULT[row[0]]))
		match row[2]:
			"up":
				if v > 1.0001:
					out.append(row[1] % int(round((v - 1.0) * 100.0)))
			"down":
				if v < 0.9999:
					out.append(row[1] % int(round((1.0 - v) * 100.0)))
			"flag":
				if v > 0.5:
					out.append(row[1])
			"time", "count", "pct":
				var base: float = Bal.v("enemy/" + str(row[0]), float(DMOD_ABS_DEFAULT[row[0]]))
				if v < 0.0 or absf(v - base) < 0.001:
					continue
				if row[2] == "time":
					out.append(row[1] % [int(v) / 60, int(v) % 60])
				elif row[2] == "pct":
					out.append(row[1] % int(round(v * 100.0)))
				else:
					out.append(row[1] % int(v))
	return out


## 旧累计档位（--diff=）→ 潮位：同号（0–10 都在 0–15 内）
static func tier_of_level(level: int) -> int:
	return clampi(level, 0, DIFFICULTY_TIERS.size() - 1)


## 旧累计档位 → 旧三档下标（只给存档迁移 settings._migrate_diff 用）
static func _tier_of_level_old(level: int) -> int:
	var t := 0
	for i in LEGACY_TIERS.size():
		if LEGACY_TIERS[i].level <= level:
			t = i
	return t



## 支援：医疗无人机（保底治疗，开局自带 Lv.1，不占编队位），最高 Lv.5
## tags 供 Build Profile 使用
const WEAPONS := {
	"drone": {"tags": ["support", "summon", "heal"], "name": "医疗无人机", "en": "MEDIC DRONE", "glyph": "机", "col": Color(0.55, 1.0, 0.7), "lv": [
		"加入支援：跟随队长，每 6 秒回复 2% 最大生命",
		"每次回复 3% 最大生命",
		"队长生命低于 40% 时立即急救，回复 6% 最大生命（冷却 25 秒）",
		"增派第二架无人机（各回复 2% 最大生命）",
		"两架各回复 2.5% 最大生命、间隔 5 秒，治疗时清除神经损伤",
	]},
}


## 敌人本体的绘制缩放（1 个 1x 美术像素 = 多少世界像素；含 draw_scale 与伊莎玛拉变身插值）。纯函数，模拟与绘制共用
## （docs/101 B1：模拟侧不再调 render/world.gd；算式与原 world.enemy_scale 逐字相同，px 由调用方传 Game.PX）
const _NO_DEF := {}   # 只读缺省（不给每次调用新建空字典）

static func enemy_scale(e: Dictionary, t: float, px: float) -> float:
	var d: Dictionary = ENEMIES.get(e.type, _NO_DEF)
	var scale_key := "transformed_draw_scale" if e.type == "ishar" and e.phase == 2 else "draw_scale"
	var factor := float(d.get(scale_key, 1.0))
	if e.type == "ishar" and t < float(e.get("transform_until", -1.0)):
		factor = lerpf(float(d.get("draw_scale", 0.68)), factor, clampf((t - float(e.transform_started)) / 0.9, 0.0, 1.0))
	# 10-23 怪物重画：美术按目标尺寸直接画，1 美术像素 = PX 个屏幕像素、1:1 显示。判定半径 e.r（含 enemy/scale 体型）不再放大画面；
	# draw_scale 全部 1.0（保留字段只为兼容 gallery / 旧测试）。
	return px * factor


## 敌人本体的画面偏移：击退跳起 + 受击后坐（fx/recoil_px、fx/recoil_t）。纯函数，算式与原 world._eoff 逐字相同（docs/101 B1）
static func enemy_offset(e: Dictionary, t: float, rc_px: float, rc_t: float) -> Vector2:
	var off := Vector2(0, -minf(e.kb.length() * 0.03, 14.0))
	if rc_px > 0.0:
		var ra: float = e.get("rc_at", -99.0)
		var k: float = (t - ra) / rc_t
		if k >= 0.0 and k < 1.0:
			off += (e.rc_dir as Vector2) * (rc_px * float(e.rc_k) * (1.0 - k))
	return off
