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
## 玩家可选的难度档（1.1 用户决定：界面只给 3 档，以后再推多难度；命名取原作「波涛迭起」，desc 为选难度页的副标题）。存档 Cfg.difficulty / diff_unlocked 存的是档位下标。
## 每档一张修正表（g.dmod，键见 DMOD_DEFAULT），数值在 data/balance.json 的 difficulty/<key> 段填；
## 段里没写的键按 level（上表的累计档位）拼出来，所以不填 = 与旧累计难度逐局相同。批跑 --diff=N 也按累计档位拼表。
const DIFFICULTY_TIERS := [
	{"name": "波涛迭起", "en": "RISING TIDE", "desc": "海洋的真容，才刚刚显露。", "key": "standard", "level": 0},
	{"name": "波涛迭起·Ⅳ", "en": "RISING TIDE Ⅳ", "desc": "暗礁更多，灯火更难守住。", "key": "hard", "level": 4},
	{"name": "波涛迭起·Ⅷ", "en": "RISING TIDE Ⅷ", "desc": "大海不再留情。", "key": "extreme", "level": 8},
]
## 难度修正表：倍率（1.0 = 不变）与开关（0 / 1）
const DMOD_DEFAULT := {
	"enemy_hp": 1.0, "enemy_dmg": 1.0, "boss_hp": 1.0, "boss_dmg": 1.0,   # 小怪与 Boss 生命 / 攻击（Boss 攻击另乘 enemy_dmg）
	"lamp_hit": 1.0, "oil_drop": 1.0, "ingot": 1.0,                      # 受击灯火损失、小怪灯油掉落率、源石锭掉落
	"elite_interval": 1.0, "boss_warn": 1.0, "horde": 1.0,               # 精英出现间隔、Boss 招式预警时间、大群规模
	"horde_in_boss": 0, "mire_permanent": 0, "max_hp": 1.0,              # Boss 在场时大群照常来袭、溟痕不消散、主控初始最大生命
	"mire_dmg": 1.0,                                                      # 溟痕伤害（run/enemies.gd，数值要求可按档单独加重）
}
## 修正项在选难度页上的说明：[键, 模板, 显示方式]；up = (v-1)×100，down = (1-v)×100，flag = 开关
const DMOD_TEXT := [
	["enemy_hp", "敌人生命 +%d%%", "up"], ["enemy_dmg", "敌人造成的伤害 +%d%%", "up"], ["boss_hp", "Boss 生命 +%d%%", "up"], ["boss_dmg", "Boss 造成的伤害再 +%d%%", "up"],
	["max_hp", "主控初始最大生命 -%d%%", "down"], ["lamp_hit", "受击时灯火损失 +%d%%", "up"], ["oil_drop", "灯油掉落 -%d%%", "down"], ["ingot", "源石锭掉落 -%d%%", "down"],
	["elite_interval", "精英出现间隔 -%d%%", "down"], ["boss_warn", "Boss 预警跟踪段 -%d%%（总时长 ≥ 0.6 秒）", "down"], ["horde", "大群规模 +%d%%", "up"],
	["horde_in_boss", "Boss 在场时大群照常来袭", "flag"], ["mire_permanent", "溟痕不再消散", "flag"], ["mire_dmg", "溟痕伤害 +%d%%", "up"],
]


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


## 某一档的修正表：balance.json difficulty/<key> 覆盖按 level 拼出的表
static func dmod_for_tier(tier: int) -> Dictionary:
	var t: Dictionary = DIFFICULTY_TIERS[tier]
	var m := dmod_for_level(int(t.level))
	var over: Dictionary = Bal.sec("difficulty/" + str(t.key))
	for k in over:
		if m.has(k):
			m[k] = over[k]
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
	return out


## 累计档位落在哪一档（取 level 不超过它的最高档）
static func tier_of_level(level: int) -> int:
	var t := 0
	for i in DIFFICULTY_TIERS.size():
		if DIFFICULTY_TIERS[i].level <= level:
			t = i
	return t



## 支援：医疗无人机（保底治疗，开局自带 Lv.1，不占编队位），最高 Lv.5
## tags 供 Build Profile 使用
const WEAPONS := {
	"drone": {"tags": ["support", "summon", "heal"], "name": "医疗无人机", "en": "MEDIC DRONE", "glyph": "机", "col": Color(0.55, 1.0, 0.7), "lv": [
		"加入支援：跟随主控，每 6 秒回复 2% 最大生命",
		"回复 3%",
		"主控生命低于 40% 时立即急救 6%（冷却 25 秒）",
		"增派第二架无人机（各回复 2%）",
		"两架各回复 2.5%、间隔 5 秒，治疗时清除神经损伤",
	]},
}
const MAX_WEAPONS := 1

## 技能进阶卡出现概率（每次升级至多一张）
## 援护干员：原创的通用职业干员（远程支援），最多 3 名，每名最高 Lv.3
const ALLIES = {
	"sniper": {"name": "狙击干员", "en": "SNIPER", "desc": "远程单体射击，优先打精英和生命最高的敌人；命中使其流血", "up": "伤害 +35%，射速 +15%"},
	"caster": {"name": "术师干员", "en": "CASTER", "desc": "发射法术团，命中后爆炸造成范围伤害", "up": "伤害 +35%，爆炸范围扩大"},
	"medic": {"name": "医疗干员", "en": "MEDIC", "desc": "每 3.5 秒为博士回复 3.5% 最大生命", "up": "治疗量与频率提升"},
	"support": {"name": "辅助干员", "en": "SUPPORTER", "desc": "减速光环：身边敌人移速 -35%；并向 2 名敌人发射追踪法术", "up": "光环范围扩大，法术伤害与频率提升；Lv.3 时同时攻击 3 个目标"},
}
const RECRUIT_LEVELS := [5, 15, 25]

