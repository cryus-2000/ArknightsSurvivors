extends RefCounted
## 游戏数据表：水月的成长项、技能、模组、武器、援护、难度。
## 敌人与刷怪导演表已迁到 JSON（data/enemies.json、data/waves.json），这里只做加载，调用方仍用 D.ENEMIES / D.THREAT 等。

const Loader = preload("res://scripts/enemies/enemy_db.gd")
static var ENEMIES: Dictionary = Loader.load_enemies()
static var THREAT: Array = Loader.load_waves().threat
static var BOSS_TIMES: Array = Loader.load_waves().boss_times
static var MID_POOL: Array = Loader.load_waves().mid_pool
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

## 支援：医疗无人机（保底治疗，开局自带 Lv.1，不占编队位），最高 Lv.5
## tags 供 Build Profile 使用
const WEAPONS := {
	"drone": {"tags": ["support", "summon", "heal"], "name": "医疗无人机", "en": "MEDIC DRONE", "glyph": "机", "col": Color(0.55, 1.0, 0.7), "lv": [
		"跟随博士，每 6 秒回复 2% 最大生命",
		"回复 3%，间隔缩短到 5 秒",
		"博士生命低于 40% 时立即急救 8%（冷却 20 秒）",
		"增派第二架无人机（治疗翻倍）",
		"间隔缩短到 4 秒、回复 4%，治疗时清除神经损伤",
	]},
}
const MAX_WEAPONS := 1

## 技能进阶卡出现概率（每次升级至多一张）
## 援护干员：原创的通用职业干员（远程支援），最多 3 名，每名最高 Lv.3
const ALLIES = {
	"sniper": {"name": "狙击干员", "en": "SNIPER", "desc": "远程单体射击，优先打精英和生命最高的敌人；命中使其流血", "up": "伤害 +35%，射速 +15%"},
	"caster": {"name": "术师干员", "en": "CASTER", "desc": "发射法术团，命中后爆炸造成范围伤害", "up": "伤害 +35%，爆炸范围扩大"},
	"medic": {"name": "医疗干员", "en": "MEDIC", "desc": "每 3.5 秒为水月回复 3.5% 最大生命", "up": "治疗量与频率提升"},
	"support": {"name": "辅助干员", "en": "SUPPORTER", "desc": "减速光环：身边敌人移速 -35%；并向 2 名敌人发射追踪法术", "up": "光环范围扩大，法术伤害与频率提升；Lv.3 时同时攻击 3 个目标"},
}
const RECRUIT_LEVELS := [5, 15, 25]

